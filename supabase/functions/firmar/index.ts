// =====================================================================
// POST /functions/v1/firmar
// Firma una inscripción: comprueba que está completa, verifica los
// archivos, genera el PDF definitivo, calcula su huella y lo guarda.
// La familia nunca genera ni sube el PDF firmado: lo hace el servidor.
// =====================================================================
import * as PDFLib from 'npm:pdf-lib@1.17.1';
import { generarExpediente } from '../_shared/plantilla-pdf.js';
import { plantillaAdultos, plantillaMenores } from '../_shared/plantillas-pdf.js';
import { sha256Hex, tipoReal } from '../_shared/archivos.js';
import { faltanParaFirmar } from '../_shared/validacion.js';
import {
  auditar, cabecerasCors, contexto, ipCliente, leerJson, respuesta, rolDe, UUID,
} from '../_shared/servidor.ts';

const texto = (v: unknown, max: number) =>
  typeof v === 'string' ? v.trim().slice(0, max) : '';

function pngDesdeDataUrl(v: unknown): Uint8Array | null {
  if (typeof v !== 'string') return null;
  const m = v.match(/^data:image\/png;base64,([A-Za-z0-9+/=]+)$/);
  if (!m) return null;
  try {
    const bin = atob(m[1]);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return bytes;
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cabecerasCors(req) });
  if (req.method !== 'POST') return respuesta(req, { error: 'Método no permitido' }, 405);

  try {
    const ctx = await contexto(req);
    if (ctx instanceof Response) return ctx;
    const { usuario, admin, user } = ctx;

    const cuerpo = await leerJson(req, 600_000);
    if (!cuerpo) return respuesta(req, { error: 'Petición no válida' }, 400);
    const id = texto(cuerpo.inscripcion_id, 36);
    if (!UUID.test(id)) return respuesta(req, { error: 'Inscripción no válida' }, 400);

    // 1. La inscripción tiene que ser visible para quien llama (RLS)...
    const { data: ins } = await usuario
      .from('inscripciones')
      .select('*, educandos(*), rondas(nombre), secciones(nombre, adultos)')
      .eq('id', id)
      .maybeSingle();
    if (!ins) return respuesta(req, { error: 'Inscripción no encontrada' }, 404);

    // ...y quien llama tiene que ser tutor/a, no solo alguien del equipo.
    const { data: vinculo } = await admin
      .from('educando_tutores').select('usuario_id')
      .eq('educando_id', ins.educando_id).eq('usuario_id', user.id).maybeSingle();
    if (!vinculo) return respuesta(req, { error: 'Solo un tutor/a legal puede firmar' }, 403);
    if (!['borrador', 'rechazada'].includes(ins.estado)) {
      return respuesta(req, { error: 'Esta inscripción ya está firmada' }, 409);
    }

    // 2. Firma dibujada: PNG real y de tamaño razonable.
    const png = pngDesdeDataUrl(cuerpo.firma_png);
    if (!png || tipoReal(png) !== 'image/png' || png.length > 400_000) {
      return respuesta(req, { error: 'La firma no es válida. Vuelve a firmar.' }, 400);
    }

    const [{ data: tutores }, { data: ficha }, { data: docs }] = await Promise.all([
      admin.from('tutores').select('*').eq('inscripcion_id', id).order('orden'),
      admin.from('fichas_sanitarias').select('*').eq('inscripcion_id', id).maybeSingle(),
      admin.from('documentos').select('*').eq('inscripcion_id', id),
    ]);

    // 3. Archivos: se descargan y se comprueba su tipo REAL por los
    //    primeros bytes. Se calcula la huella de cada uno.
    const documentos = [];
    for (const doc of docs ?? []) {
      if (!String(doc.ruta).startsWith(`${id}/`)) {
        return respuesta(req, { error: 'Ruta de archivo no válida' }, 400);
      }
      const { data: blob, error } = await admin.storage.from('documentos').download(doc.ruta);
      if (error || !blob) return respuesta(req, { error: `Falta el archivo "${doc.nombre_archivo}". Vuelve a subirlo.` }, 422);
      const bytes = new Uint8Array(await blob.arrayBuffer());
      if (tipoReal(bytes) !== doc.mime) {
        return respuesta(req, { error: `"${doc.nombre_archivo}" no es un ${doc.mime} válido. Sube otro archivo.` }, 422);
      }
      documentos.push({
        tipo: doc.tipo, nombre_archivo: doc.nombre_archivo, tamano: bytes.length, sha256: await sha256Hex(bytes),
      });
    }

    const fecha = new Date().toISOString();
    const ip = ipCliente(req);
    const ua = (req.headers.get('user-agent') ?? '').slice(0, 300) || null;
    const adulto = ins.secciones?.adultos === true;
    const datos = {
      id,
      adulto,
      contacto: { nombre: ins.contacto_nombre, telefono1: ins.contacto_telefono1, telefono2: ins.contacto_telefono2 },
      ronda: ins.rondas?.nombre,
      seccion: ins.secciones?.nombre,
      seccion_id: ins.seccion_id,
      educando: ins.educandos,
      tutores: adulto ? [] : tutores ?? [],
      ficha: ficha ?? {},
      autorizaciones: ins,
      documentos,
      firma: {
        nombre: texto(cuerpo.firmante_nombre, 120),
        documento: texto(cuerpo.firmante_documento, 20),
        lugar: texto(cuerpo.lugar, 80),
        fecha,
        png,
      },
      evidencias: { email: user.email ?? '', ip, user_agent: ua, fecha },
    };

    // 4. El servidor manda: se vuelve a validar todo aquí.
    const faltan = faltanParaFirmar(datos);
    if (faltan.length) return respuesta(req, { error: 'Faltan datos', faltan }, 422);

    // 5. PDF definitivo + huella. Cada firma se guarda con nombre propio,
    //    así una nueva firma tras una devolución no pisa la anterior.
    const pdf = await generarExpediente(PDFLib, datos, { plantilla: adulto ? plantillaAdultos() : plantillaMenores() });
    const huella = await sha256Hex(pdf);
    if (!huella) throw new Error('Sin Web Crypto en el servidor');
    const ruta = `${datos.ronda}/${id}/${fecha.replace(/[:.]/g, '-')}-${huella.slice(0, 12)}.pdf`;
    const { error: errSubida } = await admin.storage
      .from('expedientes').upload(ruta, pdf, { contentType: 'application/pdf', upsert: false });
    if (errSubida) throw errSubida;

    const { data: actualizada, error: errAct } = await admin
      .from('inscripciones')
      .update({
        estado: 'firmada',
        motivo_rechazo: null,
        firmante_nombre: datos.firma.nombre,
        firmante_documento: datos.firma.documento,
        firma_lugar: datos.firma.lugar,
        firmada_en: fecha,
        firmada_por: user.id,
        firma_ip: ip,
        firma_user_agent: ua,
        pdf_ruta: ruta,
        pdf_sha256: huella,
      })
      .eq('id', id)
      .in('estado', ['borrador', 'rechazada']) // por si llegan dos firmas a la vez
      .select('id');
    if (errAct) throw errAct;
    if (!actualizada?.length) {
      await admin.storage.from('expedientes').remove([ruta]);
      return respuesta(req, { error: 'Esta inscripción ya está firmada' }, 409);
    }

    await auditar(admin, user.id, await rolDe(admin, user.id), 'firmar', 'inscripcion', id, {
      pdf_sha256: huella, ip,
    });
    return respuesta(req, { ok: true, pdf_sha256: huella, firmada_en: fecha });
  } catch (e) {
    console.error(e);
    return respuesta(req, { error: 'Error interno. Inténtalo de nuevo en unos minutos.' }, 500);
  }
});

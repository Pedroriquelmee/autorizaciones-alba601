// =====================================================================
// POST /functions/v1/descargar   { inscripcion_id, recurso }
// Devuelve un enlace temporal (60 s) a un expediente o documento.
// Toda descarga pasa por aquí para que quede registrada en la auditoría:
// los buckets no tienen enlaces públicos ni lectura directa del equipo.
// =====================================================================
import { nombreSeguro } from '../_shared/archivos.js';
import {
  auditar, cabecerasCors, contexto, leerJson, respuesta, rolDe, UUID,
} from '../_shared/servidor.ts';

const RECURSOS = ['expediente', 'tarjeta_sanitaria', 'dni_nie', 'cartilla_vacunacion'];
const CADUCIDAD = 60; // segundos

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cabecerasCors(req) });
  if (req.method !== 'POST') return respuesta(req, { error: 'Método no permitido' }, 405);

  try {
    const ctx = await contexto(req);
    if (ctx instanceof Response) return ctx;
    const { usuario, admin, user } = ctx;

    const cuerpo = await leerJson(req, 2_000);
    const id = String(cuerpo?.inscripcion_id ?? '');
    const recurso = String(cuerpo?.recurso ?? '');
    if (!UUID.test(id) || !RECURSOS.includes(recurso)) {
      return respuesta(req, { error: 'Petición no válida' }, 400);
    }

    // RLS decide si quien llama puede ver esta inscripción
    // (tutor/a, coordinación o scouter de su sección).
    const { data: ins } = await usuario
      .from('inscripciones')
      .select('id, pdf_ruta, educandos(nombre, apellidos), rondas(nombre)')
      .eq('id', id)
      .maybeSingle();
    if (!ins) return respuesta(req, { error: 'No encontrada' }, 404);

    // deno-lint-ignore no-explicit-any
    const ed = ins.educandos as any;
    // deno-lint-ignore no-explicit-any
    const ronda = (ins.rondas as any)?.nombre ?? '';
    let bucket: string;
    let ruta: string | null;
    let nombre: string;

    if (recurso === 'expediente') {
      bucket = 'expedientes';
      ruta = ins.pdf_ruta;
      nombre = nombreSeguro(`expediente-${ed?.apellidos}-${ed?.nombre}-${ronda}.pdf`);
    } else {
      const { data: doc } = await admin
        .from('documentos').select('ruta, nombre_archivo')
        .eq('inscripcion_id', id).eq('tipo', recurso).maybeSingle();
      bucket = 'documentos';
      ruta = doc?.ruta ?? null;
      nombre = nombreSeguro(`${recurso}-${ed?.apellidos}-${ed?.nombre}-${doc?.nombre_archivo ?? ''}`);
    }
    if (!ruta) return respuesta(req, { error: 'Todavía no hay archivo' }, 404);

    const { data: firmada, error } = await admin.storage
      .from(bucket).createSignedUrl(ruta, CADUCIDAD, { download: nombre });
    if (error || !firmada) throw error ?? new Error('Sin URL');

    await auditar(admin, user.id, await rolDe(admin, user.id), 'descargar', recurso, id);
    return respuesta(req, { url: firmada.signedUrl, caduca_en: CADUCIDAD });
  } catch (e) {
    console.error(e);
    return respuesta(req, { error: 'Error interno' }, 500);
  }
});

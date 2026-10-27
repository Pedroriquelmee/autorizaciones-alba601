// "Almacén" de mentira para la demo: todo ocurre en el navegador.
import { generarExpediente } from '../web/js/compartido/plantilla-pdf.js';
import { sha256Hex } from '../web/js/compartido/archivos.js';
import { abrirPdf, abrirVentana } from '../web/js/formulario.js';
import { SECCIONES } from './datos-ejemplo.js';

const espera = (ms) => new Promise((r) => setTimeout(r, ms));
const uuid = () => globalThis.crypto?.randomUUID?.() ?? `demo-${Date.now()}`;

export function crearAlmacenDemo(PDFLib, plantillas) {
  let ultimo = null;
  return {
    demo: true,

    async cargar() {
      return {
        id: uuid(), ronda: '2026-2027', secciones: SECCIONES, seccion_id: null, estado: 'borrador',
        educando: {}, tutores: [{ email: 'familia@ejemplo.com' }], contacto: {}, ficha: {}, autorizaciones: {},
        documentos: [], firma: {}, email: 'familia@ejemplo.com',
      };
    },

    async guardar() {
      await espera(150);
    },

    async subirDocumento(est, tipo, archivo) {
      const bytes = new Uint8Array(await archivo.blob.arrayBuffer());
      return {
        tipo, nombre_archivo: archivo.nombre, mime: archivo.mime, tamano: archivo.tamano, sha256: await sha256Hex(bytes),
      };
    },

    async quitarDocumento() {},

    // En la web real esto lo hace el servidor; aquí se simula igual.
    async firmar(est, firmaPng) {
      await espera(300);
      const png = Uint8Array.from(atob(firmaPng.split(',')[1]), (c) => c.charCodeAt(0));
      const fecha = new Date().toISOString();
      const bytes = await generarExpediente(PDFLib, {
        id: est.id,
        adulto: est.adulto,
        contacto: est.contacto,
        ronda: est.ronda,
        seccion: SECCIONES.find((s) => s.id === Number(est.seccion_id))?.nombre,
        educando: est.educando,
        tutores: est.adulto ? [] : est.tutores,
        ficha: est.ficha,
        autorizaciones: est.autorizaciones,
        documentos: est.documentos,
        firma: { ...est.firma, fecha, png },
        evidencias: { email: est.email, ip: 'Demo (sin servidor)', user_agent: navigator.userAgent, fecha },
      }, { plantilla: est.adulto ? plantillas.adultos : plantillas.menores });
      ultimo = new Blob([bytes], { type: 'application/pdf' });
      return { pdf_sha256: await sha256Hex(bytes), firmada_en: fecha };
    },

    async descargarExpediente() {
      abrirPdf(ultimo, 'expediente-demo.pdf', abrirVentana());
    },
  };
}

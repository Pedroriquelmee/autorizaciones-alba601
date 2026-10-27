// Punto de entrada de la demo (se empaqueta en un solo HTML).
import * as PDFLib from 'pdf-lib';
import { montarFormulario } from '../web/js/formulario.js';
import { crearAlmacenDemo } from './almacen-demo.js';
import { EJEMPLO, EJEMPLO_ADULTO } from './datos-ejemplo.js';
import { plantillaAdultos, plantillaMenores } from '../supabase/functions/_shared/plantillas-pdf.js';

const plantillas = { menores: plantillaMenores(), adultos: plantillaAdultos() };
montarFormulario(document.getElementById('formulario'), {
  almacen: crearAlmacenDemo(PDFLib, plantillas),
  PDFLib,
  plantilla: async (adulto) => (adulto ? plantillas.adultos : plantillas.menores),
  ejemplo: { datos: EJEMPLO, adulto: EJEMPLO_ADULTO, documentos: documentosDeEjemplo },
});

// Dos PDFs de mentira para no tener que buscar archivos en el móvil.
async function documentosDeEjemplo(lib, adulto) {
  const crear = async (titulo, nombre) => {
    const pdf = await lib.PDFDocument.create();
    const p = pdf.addPage([420, 260]);
    const f = await pdf.embedFont(lib.StandardFonts.HelveticaBold);
    p.drawRectangle({ x: 16, y: 16, width: 388, height: 228, borderWidth: 1.5, borderColor: lib.rgb(0.3, 0.3, 0.3) });
    p.drawText(titulo, { x: 34, y: 200, size: 16, font: f });
    p.drawText('DOCUMENTO DE EJEMPLO', { x: 34, y: 172, size: 11, font: f, color: lib.rgb(0.5, 0.5, 0.5) });
    const blob = new Blob([await pdf.save()], { type: 'application/pdf' });
    return { blob, nombre, mime: 'application/pdf', tamano: blob.size };
  };
  const docs = [
    { tipo: 'tarjeta_sanitaria', archivo: await crear('Tarjeta sanitaria', 'tarjeta-sanitaria.pdf') },
    { tipo: 'cartilla_vacunacion', archivo: await crear('Cartilla de vacunación', 'cartilla-vacunacion.pdf') },
  ];
  if (adulto) docs.push({ tipo: 'dni_nie', archivo: await crear('DNI', 'dni.pdf') });
  return docs;
}

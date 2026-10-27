// Genera un expediente de ejemplo con datos ficticios para revisar el
// diseño del PDF sin montar nada. Uso: npm run ejemplo
import * as PDFLib from 'pdf-lib';
import { PNG } from 'pngjs';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { generarExpediente } from '../supabase/functions/_shared/plantilla-pdf.js';
import { sha256Hex } from '../supabase/functions/_shared/archivos.js';
import { EJEMPLO, EJEMPLO_ADULTO, SECCIONES } from '../demo/datos-ejemplo.js';

// Firma garabateada (PNG transparente) para que el ejemplo sea realista.
function firmaDeEjemplo() {
  const w = 460;
  const h = 150;
  const png = new PNG({ width: w, height: h });
  const punto = (cx, cy, r) => {
    for (let dy = -r; dy <= r; dy++) {
      for (let dx = -r; dx <= r; dx++) {
        const x = Math.round(cx + dx);
        const y = Math.round(cy + dy);
        if (x < 0 || y < 0 || x >= w || y >= h || dx * dx + dy * dy > r * r) continue;
        const i = (y * w + x) * 4;
        png.data[i] = 20; png.data[i + 1] = 20; png.data[i + 2] = 30; png.data[i + 3] = 255;
      }
    }
  };
  for (let t = 0; t <= 1; t += 0.0004) {
    const x = 30 + 390 * t + 18 * Math.sin(t * Math.PI * 22);
    const y = 78 - 34 * Math.sin(t * Math.PI * 22) * (1 - 0.55 * t) + 10 * Math.sin(t * Math.PI * 5);
    punto(x, y, 2);
  }
  for (let t = 0; t <= 1; t += 0.001) punto(60 + 330 * t, 118 + 4 * Math.sin(t * Math.PI * 3), 1.4);
  return new Uint8Array(PNG.sync.write(png));
}

const plantilla = await readFile('plantillas/autorizaciones-anuales.pdf');
const ahora = new Date().toISOString();
const docFalso = async (texto) => sha256Hex(new TextEncoder().encode(texto));

const datos = {
  ...EJEMPLO,
  id: crypto.randomUUID(),
  ronda: '2026-2027',
  seccion: SECCIONES.find((s) => s.id === EJEMPLO.seccion_id).nombre,
  documentos: [
    { tipo: 'tarjeta_sanitaria', nombre_archivo: 'tarjeta-sanitaria.jpg', tamano: 812345, sha256: await docFalso('tarjeta') },
    { tipo: 'cartilla_vacunacion', nombre_archivo: 'cartilla-vacunas.pdf', tamano: 1456789, sha256: await docFalso('cartilla') },
  ],
  firma: { ...EJEMPLO.firma, fecha: ahora, png: firmaDeEjemplo() },
  evidencias: {
    email: 'carmen@ejemplo.com',
    ip: '203.0.113.24',
    user_agent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1',
    fecha: ahora,
  },
};

await mkdir('ejemplos', { recursive: true });
const firmado = await generarExpediente(PDFLib, datos, { plantilla });
await writeFile('ejemplos/expediente-ejemplo.pdf', firmado);
const borrador = await generarExpediente(
  PDFLib,
  { ...datos, firma: { ...datos.firma, png: null }, evidencias: null },
  { plantilla, marcaAgua: 'BORRADOR · SIN FIRMAR' },
);
await writeFile('ejemplos/borrador-ejemplo.pdf', borrador);
console.log('ejemplos/expediente-ejemplo.pdf  SHA-256', await sha256Hex(firmado));
console.log('ejemplos/borrador-ejemplo.pdf');

// Persona adulta (Scouters / Comité)
const adulto = await generarExpediente(PDFLib, {
  ...EJEMPLO_ADULTO,
  adulto: true,
  id: crypto.randomUUID(),
  ronda: '2026-2027',
  seccion: SECCIONES.find((s) => s.id === EJEMPLO_ADULTO.seccion_id).nombre,
  tutores: [],
  documentos: [
    { tipo: 'tarjeta_sanitaria', nombre_archivo: 'tarjeta.jpg', tamano: 640000, sha256: await docFalso('t2') },
    { tipo: 'cartilla_vacunacion', nombre_archivo: 'vacunas.pdf', tamano: 980000, sha256: await docFalso('c2') },
    { tipo: 'dni_nie', nombre_archivo: 'dni.jpg', tamano: 410000, sha256: await docFalso('d2') },
  ],
  firma: { ...EJEMPLO_ADULTO.firma, fecha: ahora, png: firmaDeEjemplo() },
  evidencias: { ...datos.evidencias, email: 'marta@ejemplo.com' },
}, { plantilla: await readFile('plantillas/autorizaciones-adultos.pdf') });
await writeFile('ejemplos/expediente-adulto-ejemplo.pdf', adulto);
console.log('ejemplos/expediente-adulto-ejemplo.pdf  SHA-256', await sha256Hex(adulto));

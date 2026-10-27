// 1. Copia el código compartido (textos legales, PDF, validación) a la web.
// 2. Prepara el PDF original de las autorizaciones para la web y el servidor.
// 3. Empaqueta la demo en un único HTML que funciona sin servidor.
// Uso: npm run construir
import { build } from 'esbuild';
import { mkdir, readFile, writeFile } from 'node:fs/promises';

const COMPARTIDOS = ['textos-legales.js', 'plantilla-pdf.js', 'archivos.js', 'validacion.js'];
const AVISO = '// COPIA generada por `npm run construir`. Edita el original en supabase/functions/_shared/\n';

await mkdir('web/js/compartido', { recursive: true });
for (const f of COMPARTIDOS) {
  const original = await readFile(`supabase/functions/_shared/${f}`, 'utf8');
  await writeFile(`web/js/compartido/${f}`, AVISO + original);
}
console.log(`Copiados ${COMPARTIDOS.length} archivos compartidos a web/js/compartido/`);

// Los PDF de siempre (menores y mayores de edad): la web los descarga para
// la vista previa y el servidor los lleva dentro (en base64) para firmar.
const PLANTILLAS = { Menores: 'autorizaciones-anuales.pdf', Adultos: 'autorizaciones-adultos.pdf' };
await mkdir('web/plantillas', { recursive: true });
let modulo = '// GENERADO por `npm run construir` a partir de plantillas/*.pdf. No editar.\n' +
  'const decodificar = (b64) => {\n' +
  '  const bin = atob(b64);\n' +
  '  const bytes = new Uint8Array(bin.length);\n' +
  '  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);\n' +
  '  return bytes;\n' +
  '};\n';
for (const [nombre, archivo] of Object.entries(PLANTILLAS)) {
  const pdf = await readFile(`plantillas/${archivo}`);
  await writeFile(`web/plantillas/${archivo}`, pdf);
  modulo += `export const plantilla${nombre} = () => decodificar('${pdf.toString('base64')}');\n`;
  console.log(`Plantilla ${archivo} (${(pdf.length / 1024).toFixed(0)} KB)`);
}
await writeFile('supabase/functions/_shared/plantillas-pdf.js', modulo);

const resultado = await build({
  entryPoints: ['demo/entrada.js'],
  bundle: true,
  format: 'iife',
  minify: true,
  write: false,
  target: ['es2022'],
  legalComments: 'none',
});
const js = resultado.outputFiles[0].text.replace(/<\/script/gi, '<\\/script');
const css = await readFile('web/css/estilos.css', 'utf8');
const html = (await readFile('demo/plantilla.html', 'utf8'))
  .replace('/*CSS*/', () => css)
  .replace('/*JS*/', () => js);

await mkdir('dist', { recursive: true });
await writeFile('dist/demo.html', html);
console.log(`dist/demo.html (${(html.length / 1024).toFixed(0)} KB)`);

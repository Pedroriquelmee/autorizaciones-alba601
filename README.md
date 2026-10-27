# Gestor de inscripciones · Grupo Scout Alba 601

Las autorizaciones anuales del grupo convertidas en un formulario web que se rellena y firma desde el móvil: las cinco de los educandos (asistencia, ficha sanitaria, medicamentos, cesión de imagen y WhatsApp), que firma la familia, y las de mayores de edad (ficha sanitaria y cesión de imagen), que firman los propios scouters y miembros del comité. Al firmar se genera **vuestro mismo PDF de siempre, rellenado y firmado** (los datos en azul, como a boli), más un anexo con la documentación y las evidencias de la firma. Los documentos se suben al momento y el equipo lo revisa todo desde un panel.

```
Familia                         Servidor (Supabase)                     Equipo
───────                         ───────────────────                     ──────
Correo → enlace mágico ───────► Auth (sin contraseñas)
Formulario 6 pasos ───────────► Postgres con RLS (guarda cada paso)
Sube DNI, tarjeta, vacunas ───► Storage privado (bucket "documentos")
Firma con el dedo ────────────► Función "firmar":                        Panel:
                                 · revalida todo                         · estado por sección
                                 · comprueba el tipo real de archivos    · ficha sanitaria (auditada)
                                 · genera el PDF y su huella             · validar / devolver
                                 · lo guarda en "expedientes"            · listado sanitario
                                Función "descargar" (enlace de 60 s) ◄── · descargas (auditadas)
                                Tabla "auditoria" (solo se añade) ─────► · registro de accesos
```

## Estructura

```
plantillas/
  autorizaciones-anuales.pdf    ← VUESTROS PDF ORIGINALES: son los que se rellenan y se firman
  autorizaciones-adultos.pdf      (menores / Scouters y Comité)
supabase/
  migrations/0001_esquema.sql   Tablas, RLS, buckets, auditoría y funciones del equipo
  migrations/0002_adultos.sql   Secciones de mayores de edad (Scouters y Comité)
  seed.sql                      Ronda activa y secciones
  functions/
    firmar/                     Genera y guarda el PDF firmado
    descargar/                  Enlaces temporales + auditoría
    _shared/                    Código común (también lo usa la web):
      textos-legales.js           ← textos que se muestran en el formulario
      plantilla-pdf.js            Dónde va cada dato sobre los PDF originales (MAPA, MAPA_ADULTOS) + anexo
      plantillas-pdf.js           Los PDF originales en base64 (generado, no editar)
      validacion.js               Qué es obligatorio, letra del DNI/NIE
      archivos.js                 Tipo real de archivo, SHA-256
web/                            Web estática (se publica tal cual)
  index.html · familia.html · inscripcion.html · panel.html
  js/config.js                  ← URL y clave pública de Supabase
demo/                           Demo sin servidor
pruebas/                        Pruebas de seguridad del esquema (60 casos)
scripts/                        construir (copia código común + demo) y PDF de ejemplo
```

## Seguridad (lo que hay y por qué)

| Medida | Qué evita |
|---|---|
| RLS en todas las tablas | Que una familia vea datos de otra, o un scouter los de otra sección |
| Privilegios por columna | Que una familia se ponga `rol = coordinador` o marque su inscripción como firmada |
| Ficha sanitaria sin lectura directa para el equipo; solo vía `ver_ficha()` / `listado_sanitario()` | Accesos a datos de salud sin dejar rastro |
| Scouters y Comité solo visibles para la coordinación (un scouter no puede tener asignada esa sección) | Que un scouter vea las fichas sanitarias de sus compañeros |
| Tabla `auditoria` de solo inserción | Que alguien borre sus huellas |
| Buckets privados + enlaces de 60 s vía función | Enlaces públicos que circulen por WhatsApp |
| Comprobación de *magic bytes* (cliente y servidor) | Subir un `.exe` renombrado a `.pdf` |
| `ruta_en_su_carpeta` (CHECK) | Que una familia apunte a un archivo de otra y el servidor lo incluya en su expediente |
| PDF generado en el servidor + SHA-256 guardado en BD | Que se manipule el documento firmado sin que se note |
| CSP estricta, sin `innerHTML` | XSS (probado con `<img onerror>` en un nombre) |
| Enlace mágico, sin contraseñas | Contraseñas débiles o reutilizadas |
| Validación repetida en el servidor | Saltarse el formulario llamando a la API a mano |

Las pruebas están en `pruebas/rls.sql` (60 casos: familia A contra B, scouter de una sección contra otra, anónimo, firma, devolución, auditoría…).

## Puesta en marcha (inscripciones.pedroriquelme.tech)

Necesitas: el Mac con Node instalado (`node -v`, versión 18 o superior), cuenta de GitHub y acceso a Dondominio.
Todo lo de abajo es gratis.

### 1. Supabase: proyecto y base de datos
1. supabase.com → *New project*. Región **Central EU (Frankfurt)**. Guarda la contraseña de la base de datos.
2. *SQL Editor* → *New query* → pega y ejecuta (*Run*), **por este orden**, `supabase/migrations/0001_esquema.sql`,
   `supabase/migrations/0002_adultos.sql` y `supabase/seed.sql`.
3. Comprueba: *Table Editor* muestra las tablas y *Storage* los buckets `documentos` y `expedientes`.
4. Botón *Connect* (arriba) o *Project Settings → API Keys*: copia la **URL** y la **clave publicable**
   (`sb_publishable_…`) en `web/js/config.js`. La clave secreta no se copia en ningún sitio.

### 2. Correo (Resend)
1. resend.com → *Domains → Add domain* → `pedroriquelme.tech`. Te da unos registros DNS (TXT/MX).
2. Dondominio → tu dominio → *Zona DNS*: añade esos registros tal cual. En Resend, *Verify*.
3. Resend → *API Keys* → crea una con permiso de envío.
4. Supabase → *Authentication → Emails → SMTP Settings* → activa *custom SMTP*:
   host `smtp.resend.com`, puerto `465`, usuario `resend`, contraseña = la API key de Resend,
   remitente `inscripciones@pedroriquelme.tech`, nombre `Grupo Scout Alba 601`.
5. *Authentication → Emails → Templates*: traduce **Magic Link** y **Confirm signup** (ver plantilla abajo).
6. *Authentication → Rate Limits*: sube los correos por hora (p. ej. 100) cuando abráis inscripciones.

Plantilla para los dos correos (asunto: `Entra en las inscripciones del Grupo Scout Alba 601`):

```html
<h2>Grupo Scout Alba 601</h2>
<p>Pulsa el botón para entrar en las inscripciones y autorizaciones:</p>
<p><a href="{{ .ConfirmationURL }}">Entrar</a></p>
<p>El enlace caduca en una hora y solo vale una vez. Si no lo has pedido tú, ignora este correo.</p>
```

### 3. Funciones del servidor (Terminal, en la carpeta del proyecto)
```bash
npx supabase login
npx supabase init                         # "Generate VS Code settings for Deno?" → N
npx supabase link --project-ref TU_REF    # TU_REF: lo que va antes de .supabase.co en tu URL
npx supabase functions deploy firmar
npx supabase functions deploy descargar
```
Si `link` pide la contraseña de la base de datos, puedes dejarla en blanco.

### 4. Web y subdominio
1. GitHub → *New repository* (`inscripciones-alba601`). Puede ser público: no hay nada secreto.
2. Súbelo:
   ```bash
   git init && git add . && git commit -m "Gestor de inscripciones"
   git branch -M main
   git remote add origin https://github.com/TU-USUARIO/inscripciones-alba601.git
   git push -u origin main
   ```
3. Repositorio → *Settings → Pages → Source: GitHub Actions*. En *Actions*, «Publicar web» tiene que salir en verde
   (si no ha arrancado, *Run workflow*).
4. Dondominio → *Zona DNS* → registro **CNAME**: nombre `inscripciones`, valor `TU-USUARIO.github.io`.
5. *Settings → Pages → Custom domain*: `inscripciones.pedroriquelme.tech` → *Save*. Cuando se ponga en verde,
   marca *Enforce HTTPS*.
6. Supabase → *Authentication → URL Configuration*: *Site URL* `https://inscripciones.pedroriquelme.tech` y en
   *Redirect URLs* añade `https://inscripciones.pedroriquelme.tech/index.html`.
7. Terminal:
   ```bash
   npx supabase secrets set ORIGENES_PERMITIDOS=https://inscripciones.pedroriquelme.tech
   ```

### 5. Primera prueba
1. Entra en la web con tu correo y abre el enlace que te llega.
2. *SQL Editor*: `update public.perfiles set rol = 'coordinador' where email = 'TU-CORREO';` y recarga la web.
3. Desde el móvil y con **otro** correo, haz una inscripción de prueba completa (Manada) y otra como scouter.
4. En el panel: abre la ficha, descarga el PDF, valida una y devuelve otra. Mira *Registro de accesos*.
5. Borra las pruebas: `delete from public.educandos where apellidos = 'APELLIDOS-DE-PRUEBA';`
   y sus archivos en *Storage*.

### Si algo falla
| Síntoma | Causa probable y solución |
|---|---|
| No llega el correo | Mira en spam y en *Resend → Logs*. Revisa los datos SMTP y el límite de *Rate Limits*. |
| «Ese enlace ha caducado» | Falta la dirección en *Redirect URLs*, o el enlace ya se usó. Algunos correos (Outlook/Hotmail) abren los enlaces solos para revisarlos y lo gastan: pedir otro suele bastar. |
| Al firmar: «Invalid JWT» (401) | La comprobación previa de la plataforma con las nuevas claves de firma. Vuelve a desplegar con `npx supabase functions deploy firmar --no-verify-jwt` (y lo mismo con `descargar`): la función ya comprueba la sesión por su cuenta. |
| Error de CORS al firmar o descargar | `ORIGENES_PERMITIDOS` tiene que ser exactamente la dirección de la web, con `https://` y sin `/` al final. |
| «No tienes permiso…» al guardar | Las migraciones no se ejecutaron enteras o en orden. Repite el paso 1.2. |
| Aviso amarillo «Falta configurar config.js» | Falta el paso 1.4 (o no has vuelto a subir a GitHub tras editarlo). |

## Uso diario

- **Familias**: entran con su correo → «Nueva inscripción» o «Renovar para 2027-2028» (copia datos y ficha del año anterior; autorizaciones, firma y documentos se piden de nuevo).
- **Scouters y Comité**: entran con su correo y se inscriben a sí mismos eligiendo su sección. El formulario cambia solo: contacto de emergencia en vez de tutores, su ficha sanitaria de adultos, su cesión de imagen y tres documentos (tarjeta sanitaria, cartilla de vacunación y DNI).
- **Scouters**: ven solo su sección, consultan fichas, descargan documentos, validan o devuelven con motivo.
- **Coordinación**: todo lo anterior + mover de sección, gestionar el equipo y ver el registro de accesos.
- **Nueva ronda**:
  ```sql
  update public.rondas set activa = false;
  insert into public.rondas (nombre, activa) values ('2027-2028', true);
  ```

## El PDF firmado

Se parte de vuestros PDF de siempre (`autorizaciones-anuales.pdf`, 8 páginas, o `autorizaciones-adultos.pdf`, 3 páginas, según la sección) y se escribe encima de cada hueco:
líneas de puntos, casillas con aspa, «SI/NO» rodeados en la ficha sanitaria y la firma en cada documento. La hoja de
WhatsApp se duplica cuando hay segundo tutor/a, porque es personal. Si un dato no cabe en su hueco, se reduce la letra
y, si aun así no cabe, se corta y el texto completo aparece en el anexo final.

## Cambiar las autorizaciones

- **Solo cambia algún texto del formulario** (lo que lee la familia): edita `supabase/functions/_shared/textos-legales.js`.
- **Cambia el documento en papel**: sustituye el PDF que toque en `plantillas/`. Si los huecos siguen en el mismo
  sitio, no hay que hacer nada más. Si se mueven, hay que volver a medir sus coordenadas en `MAPA` o `MAPA_ADULTOS`
  (`plantilla-pdf.js`); con `pdfplumber` se sacan en un momento.

En ambos casos, después:

```bash
npm install
npm run construir                      # copia código común y plantilla a web/, regenera la demo
npm run ejemplo                        # revisa ejemplos/expediente-ejemplo.pdf
npx supabase functions deploy firmar   # para que el servidor use la versión nueva
```

## Probar sin montar nada

```bash
npm install
npm run ejemplo      # ejemplos/expediente-ejemplo.pdf con datos ficticios
npm run construir    # dist/demo.html: la demo completa en un solo archivo
PGHOST=... PGUSER=postgres npm run pruebas   # pruebas de seguridad en un PostgreSQL local
```

## Mantenimiento

- En el plan gratuito, el proyecto se pausa tras una semana sin actividad; en verano conviene entrar de vez en cuando o reactivarlo desde el panel de Supabase.
- Supabase retira las claves antiguas (`anon` / `service_role`) a finales de 2026: el proyecto ya usa las nuevas (publicable y secreta), no hay que hacer nada.
- Espacio: cada PDF firmado ocupa cerca de 1 MB (vuestro PDF original lleva sus fuentes dentro) y cada familia sube hasta 3 documentos de máximo 5 MB. El plan gratuito trae 1 GB de almacenamiento: vigiladlo en *Storage* y borrad rondas antiguas cuando toque.
- Copia de seguridad: `npx supabase db dump -f copia.sql` de vez en cuando (y descarga los buckets si los queréis guardar fuera).

## A revisar en los documentos actuales

Cosas detectadas al pasar las autorizaciones a digital. Conviene revisarlas con alguien de la federación o con asesoría legal antes de usar el sistema:

1. **Derechos ARCO**: el texto de protección de datos habla de «cancelación», terminología de la antigua LOPD. Con el RGPD son acceso, rectificación, supresión, oposición, limitación y portabilidad (la cesión de imagen ya lo pone bien).
2. **Plazo de conservación**: «mínimo 5 años… tras lo cual seguirá archivado» va contra el principio de limitación del plazo. Hace falta un plazo máximo concreto, sobre todo para los datos de salud.
3. **Datos de salud**: se piden con un consentimiento conjunto (tratamiento médico, facturas, contacto…). Son categoría especial (art. 9 RGPD) y requieren consentimiento explícito; por eso el formulario lo pide aparte.
4. **Mayores de 14 años**: la cesión de imagen es para menores de 14. A partir de esa edad el menor puede consentir sobre sus propios datos, así que en Tropa (los mayores), Unidad y Clan habría que pedirle también su consentimiento.
5. **Información obligatoria que falta**: base jurídica, plazo concreto, derecho a reclamar ante la AEPD y que hay un **encargado del tratamiento** (Supabase). Hay que mencionarlo y aceptar su acuerdo de tratamiento de datos (DPA).
6. **Huecos en blanco**: la cesión de imagen dejaba vacíos la dirección y el correo para ejercer derechos. Se han rellenado con los del membrete (`ORGANIZACION` en `textos-legales.js`).
7. **WhatsApp del segundo tutor/a**: esa autorización es personal, pero solo firma una persona. La hoja del segundo tutor/a se rellena con lo que indicó quien firma, y así consta en ella. Si queréis el consentimiento de cada uno por separado, haría falta una segunda firma.
8. **Ficha de adultos**: pregunta por anticonceptivos, embarazo, tabaco y alcohol. Son datos de salud muy sensibles; el formulario deja las dos primeras como opcionales («Prefiero no decirlo»), pero conviene valorar si todas son necesarias (principio de minimización).
9. **Imagen en la autorización general**: el papel pregunta por la imagen dos veces (autorización general y cesión de imagen). En el formulario se pregunta una vez y la casilla de la autorización general se marca igual que «redes sociales y web» de la cesión.

## Ideas para siguientes versiones

- Recordatorio automático por correo a las familias con la inscripción a medias.
- Flujo para socios mayores de edad (Clan), que firman por sí mismos.
- Segunda firma opcional para el otro tutor/a (WhatsApp y cesión de imagen).
- Borrado automático de fichas sanitarias al acabar la ronda (cuando esté decidido el plazo).
- Exportar a Excel el listado de la sección para campamentos.

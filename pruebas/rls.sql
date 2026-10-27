-- =====================================================================
-- Pruebas de seguridad del esquema (RLS, privilegios por columna,
-- almacenamiento y funciones del equipo). Se ejecutan con
-- pruebas/ejecutar.sh contra un PostgreSQL local desechable.
-- =====================================================================
\set ON_ERROR_STOP on
\set QUIET on
set client_min_messages = notice;
\o /dev/null

-- ---------- Utilidades de prueba ----------
create schema pruebas;
create table pruebas.resultados (n serial, nombre text, ok boolean);
create table pruebas.ids (clave text primary key, valor uuid);

create function pruebas.ok(p_nombre text, p_ok boolean) returns void
language plpgsql security definer as $$
begin
  insert into pruebas.resultados (nombre, ok) values (p_nombre, p_ok);
  if p_ok then raise notice 'OK     %', p_nombre; else raise warning 'FALLO  %', p_nombre; end if;
end $$;

create function pruebas.guardar(p text, v uuid) returns void
language sql security definer as $$ insert into pruebas.ids values (p, v) $$;

create function pruebas.id(p text) returns uuid
language sql stable security definer as $$ select valor from pruebas.ids where clave = p $$;

-- Debe dar error.
create function pruebas.falla(p_nombre text, p_sql text) returns void language plpgsql as $$
begin
  execute p_sql;
  perform pruebas.ok(p_nombre || '  (no dio error)', false);
exception when others then
  perform pruebas.ok(p_nombre || '  → ' || sqlerrm, true);
end $$;

-- Debe devolver este número.
create function pruebas.cuenta(p_nombre text, p_sql text, p_esperado int) returns void
language plpgsql as $$
declare n int;
begin
  execute p_sql into n;
  perform pruebas.ok(format('%s  (%s, esperado %s)', p_nombre, n, p_esperado), n = p_esperado);
end $$;

-- Debe modificar este número de filas.
create function pruebas.afecta(p_nombre text, p_sql text, p_esperado int) returns void
language plpgsql as $$
declare n int;
begin
  execute p_sql;
  get diagnostics n = row_count;
  perform pruebas.ok(format('%s  (%s filas, esperado %s)', p_nombre, n, p_esperado), n = p_esperado);
end $$;

grant usage on schema pruebas to anon, authenticated, service_role;
grant execute on all functions in schema pruebas to anon, authenticated, service_role;

-- ---------- Datos de partida ----------
\i supabase/seed.sql
insert into public.rondas (nombre, activa) values ('2025-2026', false);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'familia.a@ejemplo.com'),
  ('00000000-0000-0000-0000-00000000000b', 'familia.b@ejemplo.com'),
  ('00000000-0000-0000-0000-000000000005', 'scouter.manada@ejemplo.com'),
  ('00000000-0000-0000-0000-000000000007', 'scouter.tropa@ejemplo.com'),
  ('00000000-0000-0000-0000-00000000000c', 'coordinacion@ejemplo.com'),
  ('00000000-0000-0000-0000-00000000000d', 'scouter.adulta@ejemplo.com');

select pruebas.cuenta('El alta de usuarios crea su perfil como familia',
  $q$select count(*) from public.perfiles where rol = 'familia'$q$, 6);

\set como_a 'reset role; select set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-00000000000a'', false); set role authenticated;'
\set como_b 'reset role; select set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-00000000000b'', false); set role authenticated;'
\set como_s 'reset role; select set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-000000000005'', false); set role authenticated;'
\set como_t 'reset role; select set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-000000000007'', false); set role authenticated;'
\set como_c 'reset role; select set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-00000000000c'', false); set role authenticated;'
\set como_d 'reset role; select set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-00000000000d'', false); set role authenticated;'
\set como_anon 'reset role; select set_config(''request.jwt.claim.sub'', '''', false); set role anon;'
\set como_admin 'reset role;'

\echo
\echo '== Familia A rellena su inscripción (Manada) =='
:como_a
with n as (
  insert into public.educandos (nombre, apellidos, fecha_nacimiento, direccion, poblacion, provincia, codigo_postal)
  values ('Lucía', 'García Pérez', '2017-03-14', 'C/ Mayor 1', 'El Algar', 'Murcia', '30366')
  returning id
) select pruebas.guardar('edu_a', id) from n;

with n as (
  insert into public.inscripciones (educando_id, ronda_id, seccion_id)
  values (pruebas.id('edu_a'), 1, 1) returning id
) select pruebas.guardar('ins_a', id) from n;

insert into public.tutores (inscripcion_id, orden, documento, nombre, apellidos, movil, email, whatsapp_autoriza)
values (pruebas.id('ins_a'), 1, '12345678Z', 'Ana', 'Pérez Ruiz', '600000000', 'familia.a@ejemplo.com', false);

insert into public.fichas_sanitarias (inscripcion_id, seguro, numero_seguro, enuresis, sonambulismo,
  enfermedad_cronica, tratamiento_medico, dieta_especial, alergia_medicamentos, alergia_medicamentos_cual)
values (pruebas.id('ins_a'), 'Seguridad Social', 'MU123', false, false, false, false, false, true, 'Penicilina');

-- El formulario guarda con "upsert": tiene que funcionar repetido.
select pruebas.afecta('A puede volver a guardar su ficha (upsert)',
  $q$insert into public.fichas_sanitarias (inscripcion_id, seguro) values (pruebas.id('ins_a'), 'Seguridad Social')
     on conflict (inscripcion_id) do update set seguro = excluded.seguro$q$, 1);
select pruebas.afecta('A puede volver a guardar el tutor 1 (upsert)',
  $q$insert into public.tutores (inscripcion_id, orden, nombre) values (pruebas.id('ins_a'), 1, 'Ana')
     on conflict (inscripcion_id, orden) do update set nombre = excluded.nombre$q$, 1);

select set_config('pruebas.ruta_a', pruebas.id('ins_a')::text || '/tarjeta_sanitaria-1.pdf', false);
insert into storage.objects (bucket_id, name) values ('documentos', current_setting('pruebas.ruta_a'));
insert into public.documentos (inscripcion_id, tipo, ruta, nombre_archivo, mime, tamano)
values (pruebas.id('ins_a'), 'tarjeta_sanitaria', current_setting('pruebas.ruta_a'), 'tarjeta.pdf', 'application/pdf', 1000);

select pruebas.cuenta('A ve su educando', 'select count(*) from public.educandos', 1);
select pruebas.cuenta('A ve su ficha', 'select count(*) from public.fichas_sanitarias', 1);
select pruebas.cuenta('A ve su archivo en Storage', 'select count(*) from storage.objects', 1);

select pruebas.falla('A NO puede marcar su inscripción como firmada',
  $q$update public.inscripciones set estado = 'firmada'$q$);
select pruebas.falla('A NO puede rellenar el hash del PDF',
  $q$update public.inscripciones set pdf_sha256 = repeat('a', 64)$q$);
select pruebas.falla('A NO puede hacerse coordinadora',
  $q$update public.perfiles set rol = 'coordinador'$q$);
select pruebas.falla('A NO puede escribir en la auditoría',
  $q$insert into public.auditoria (accion) values ('falsificada')$q$);
select pruebas.falla('A NO puede inscribir en una ronda cerrada',
  $q$insert into public.inscripciones (educando_id, ronda_id, seccion_id) values (pruebas.id('edu_a'), 2, 1)$q$);
select pruebas.falla('A NO puede elegir el id del educando',
  $q$insert into public.educandos (id, nombre, apellidos, fecha_nacimiento) values (gen_random_uuid(), 'X', 'Y', '2015-01-01')$q$);
select pruebas.falla('A NO puede atribuir un educando a otra cuenta',
  $q$insert into public.educandos (nombre, apellidos, fecha_nacimiento, creado_por) values ('X', 'Y', '2015-01-01', '00000000-0000-0000-0000-00000000000b')$q$);
select pruebas.falla('A NO puede subir archivos fuera de una carpeta de inscripción',
  $q$insert into storage.objects (bucket_id, name) values ('documentos', '../../otra/cosa.pdf')$q$);
select pruebas.falla('A NO puede escribir en el bucket de expedientes',
  $q$insert into storage.objects (bucket_id, name) values ('expedientes', pruebas.id('ins_a')::text || '/falso.pdf')$q$);

\echo
\echo '== Familia B intenta acceder a lo de A =='
:como_b
select pruebas.cuenta('B no ve educandos ajenos', 'select count(*) from public.educandos', 0);
select pruebas.cuenta('B no ve inscripciones ajenas', 'select count(*) from public.inscripciones', 0);
select pruebas.cuenta('B no ve tutores ajenos', 'select count(*) from public.tutores', 0);
select pruebas.cuenta('B no ve fichas ajenas', 'select count(*) from public.fichas_sanitarias', 0);
select pruebas.cuenta('B no ve documentos ajenos', 'select count(*) from public.documentos', 0);
select pruebas.cuenta('B no ve archivos ajenos', 'select count(*) from storage.objects', 0);
select pruebas.afecta('B no puede modificar la ficha de A',
  $q$update public.fichas_sanitarias set otras_alergias = 'x'$q$, 0);
select pruebas.falla('B NO puede añadirse como tutor en la inscripción de A',
  $q$insert into public.tutores (inscripcion_id, orden, nombre) values (pruebas.id('ins_a'), 2, 'Intruso')$q$);
select pruebas.falla('B NO puede subir a la carpeta de A',
  $q$insert into storage.objects (bucket_id, name) values ('documentos', pruebas.id('ins_a')::text || '/malo.pdf')$q$);
select pruebas.falla('B NO puede inscribir al educando de A',
  $q$insert into public.inscripciones (educando_id, ronda_id, seccion_id) values (pruebas.id('edu_a'), 1, 2)$q$);
select pruebas.falla('B NO puede ver fichas con ver_ficha()',
  $q$select public.ver_ficha(pruebas.id('ins_a'))$q$);
select pruebas.falla('B NO puede pedir el listado sanitario',
  $q$select * from public.listado_sanitario()$q$);
select pruebas.falla('B NO puede asignarse roles',
  $q$select public.asignar_rol('familia.b@ejemplo.com', 'coordinador')$q$);

with n as (
  insert into public.educandos (nombre, apellidos, fecha_nacimiento, direccion, poblacion, provincia, codigo_postal)
  values ('Mario', 'López Sánchez', '2013-07-02', 'C/ Sol 2', 'El Algar', 'Murcia', '30366')
  returning id
) select pruebas.guardar('edu_b', id) from n;
with n as (
  insert into public.inscripciones (educando_id, ronda_id, seccion_id)
  values (pruebas.id('edu_b'), 1, 2) returning id
) select pruebas.guardar('ins_b', id) from n;

select pruebas.falla('B NO puede registrar como suyo un archivo de la carpeta de A',
  $q$insert into public.documentos (inscripcion_id, tipo, ruta, nombre_archivo, mime, tamano)
     values (pruebas.id('ins_b'), 'tarjeta_sanitaria', current_setting('pruebas.ruta_a'), 'x.pdf', 'application/pdf', 10)$q$);

\echo
\echo '== Persona adulta (Scouters) se inscribe a sí misma =='
:como_d
with n as (
  insert into public.educandos (nombre, apellidos, documento, fecha_nacimiento, direccion, poblacion, provincia, codigo_postal, movil, email)
  values ('Marta', 'Ruiz Gómez', '00000002W', '1998-04-20', 'C/ Luna 3', 'El Algar', 'Murcia', '30366', '600000003', 'scouter.adulta@ejemplo.com')
  returning id
) select pruebas.guardar('edu_d', id) from n;
with n as (
  insert into public.inscripciones (educando_id, ronda_id, seccion_id)
  values (pruebas.id('edu_d'), 1, 4) returning id
) select pruebas.guardar('ins_d', id) from n;
select pruebas.afecta('Guarda su contacto de emergencia',
  $q$update public.inscripciones set contacto_nombre = 'Luis Ruiz', contacto_telefono1 = '600000004' where id = pruebas.id('ins_d')$q$, 1);
select pruebas.afecta('Guarda su ficha de adulto',
  $q$insert into public.fichas_sanitarias (inscripcion_id, alergia_medicamentos, otras_alergias_tiene, enfermedad_cronica,
       dieta_especial, fumador, alcohol, gafas_lentillas)
     values (pruebas.id('ins_d'), false, false, true, false, false, false, true)$q$, 1);
select set_config('pruebas.ruta_d', pruebas.id('ins_d')::text || '/dni_nie-1.pdf', false);
insert into storage.objects (bucket_id, name) values ('documentos', current_setting('pruebas.ruta_d'));
select pruebas.afecta('Sube su DNI',
  $q$insert into public.documentos (inscripcion_id, tipo, ruta, nombre_archivo, mime, tamano)
     values (pruebas.id('ins_d'), 'dni_nie', current_setting('pruebas.ruta_d'), 'dni.pdf', 'application/pdf', 900)$q$, 1);
select pruebas.cuenta('Solo ve lo suyo', 'select count(*) from public.inscripciones', 1);

\echo
\echo '== Coordinación =='
:como_admin
update public.perfiles set rol = 'coordinador' where email = 'coordinacion@ejemplo.com';
:como_c
select public.asignar_rol('scouter.manada@ejemplo.com', 'scouter', 1::smallint);
select public.asignar_rol('scouter.tropa@ejemplo.com', 'scouter', 2::smallint);
select pruebas.falla('Un scouter no puede llevar la sección Scouters (vería las fichas del equipo)',
  $q$select public.asignar_rol('familia.b@ejemplo.com', 'scouter', 4::smallint)$q$);
select pruebas.falla('Un scouter necesita sección',
  $q$select public.asignar_rol('familia.b@ejemplo.com', 'scouter')$q$);
select pruebas.falla('La única persona coordinadora no puede quitarse el rol',
  $q$select public.asignar_rol('coordinacion@ejemplo.com', 'familia')$q$);
select pruebas.cuenta('Coordinación ve todas las inscripciones', 'select count(*) from public.inscripciones', 3);
select pruebas.cuenta('Coordinación NO lee fichas directamente', 'select count(*) from public.fichas_sanitarias', 0);
select pruebas.cuenta('Coordinación lee la ficha con ver_ficha()',
  $q$select count(*) from public.ver_ficha(pruebas.id('ins_a')) where seguro is not null$q$, 1);

\echo
\echo '== Scouter de Manada =='
:como_s
select pruebas.cuenta('Ve solo las inscripciones de su sección (ni las de adultos)', 'select count(*) from public.inscripciones', 1);
select pruebas.cuenta('Ve solo los educandos de su sección', 'select count(*) from public.educandos', 1);
select pruebas.cuenta('Ve los metadatos de documentos de su sección', 'select count(*) from public.documentos', 1);
select pruebas.cuenta('NO lee archivos de Storage directamente', 'select count(*) from storage.objects', 0);
select pruebas.cuenta('NO lee fichas directamente', 'select count(*) from public.fichas_sanitarias', 0);
select pruebas.cuenta('NO ve la auditoría', 'select count(*) from public.auditoria', 0);
select pruebas.cuenta('Lee la ficha de su sección con ver_ficha()',
  $q$select count(*) from public.ver_ficha(pruebas.id('ins_a')) where alergia_medicamentos_cual = 'Penicilina'$q$, 1);
select pruebas.falla('NO puede ver fichas de otra sección',
  $q$select public.ver_ficha(pruebas.id('ins_b'))$q$);
select pruebas.falla('NO puede validar una inscripción sin firmar',
  $q$select public.cambiar_estado(pruebas.id('ins_a'), 'validada')$q$);
select pruebas.falla('NO puede asignar roles',
  $q$select public.asignar_rol('familia.a@ejemplo.com', 'coordinador')$q$);
select pruebas.cuenta('Listado sanitario vacío mientras no haya firmadas',
  'select count(*) from public.listado_sanitario()', 0);

\echo
\echo '== Se firma la inscripción de A (lo hace el servidor) =='
:como_admin
update public.inscripciones
   set estado = 'firmada', firmada_en = now(), pdf_ruta = '2026-2027/x.pdf', pdf_sha256 = repeat('b', 64)
 where id = pruebas.id('ins_a');

:como_s
select pruebas.cuenta('Listado sanitario: su sección aunque pida otra',
  'select count(*) from public.listado_sanitario(2::smallint)', 1);

:como_t
select pruebas.cuenta('Scouter de Tropa ve solo su sección', 'select count(*) from public.inscripciones', 1);
select pruebas.falla('Scouter de Tropa NO ve fichas de Manada',
  $q$select public.ver_ficha(pruebas.id('ins_a'))$q$);
select pruebas.falla('Scouter de Tropa NO valida inscripciones de Manada',
  $q$select public.cambiar_estado(pruebas.id('ins_a'), 'validada')$q$);

:como_a
select pruebas.afecta('A NO puede cambiar autorizaciones ya firmadas',
  'update public.inscripciones set vuelve_solo = true', 0);
select pruebas.afecta('A NO puede cambiar la ficha ya firmada',
  $q$update public.fichas_sanitarias set otras_alergias = 'cambio'$q$, 0);
select pruebas.afecta('A NO puede cambiar los datos del educando ya firmado',
  $q$update public.educandos set direccion = 'Otra'$q$, 0);
select pruebas.afecta('A NO puede quitar documentos ya firmados',
  'delete from public.documentos', 0);
select pruebas.falla('A NO puede subir archivos a una inscripción firmada',
  $q$insert into storage.objects (bucket_id, name) values ('documentos', pruebas.id('ins_a')::text || '/otro.pdf')$q$);
select pruebas.cuenta('A NO ve la auditoría', 'select count(*) from public.auditoria', 0);

\echo
\echo '== El scouter la devuelve y la familia puede corregir =='
:como_s
select pruebas.falla('Devolver exige motivo',
  $q$select public.cambiar_estado(pruebas.id('ins_a'), 'rechazada', '  ')$q$);
select public.cambiar_estado(pruebas.id('ins_a'), 'rechazada', 'Falta la cartilla de vacunación');
:como_a
select pruebas.afecta('A puede corregir una inscripción devuelta',
  'update public.inscripciones set vuelve_solo = false', 1);

\echo
\echo '== Clave secreta (lo que usan las funciones firmar y descargar) =='
reset role;
set role service_role;
select pruebas.cuenta('Lee fichas sanitarias para generar el PDF', 'select count(*) from public.fichas_sanitarias', 2);
select pruebas.cuenta('Lee tutores y documentos',
  'select (select count(*) from public.tutores) + (select count(*) from public.documentos)', 3);
select pruebas.afecta('Escribe en la auditoría',
  $q$insert into public.auditoria (accion, objeto) values ('prueba', 'service_role')$q$, 1);
select pruebas.afecta('Marca una inscripción como firmada',
  $q$update public.inscripciones set firma_lugar = 'El Algar' where id = pruebas.id('ins_d')$q$, 1);

\echo
\echo '== Anónimo (sin sesión) =='
:como_anon
select pruebas.falla('Sin sesión no se lee nada', 'select count(*) from public.educandos');
select pruebas.falla('Sin sesión no se llama a ver_ficha()', $q$select public.ver_ficha(pruebas.id('ins_a'))$q$);

\echo
\echo '== Auditoría =='
:como_c
select pruebas.cuenta('Quedan registrados los accesos a datos de salud y los cambios',
  $q$select count(*) from public.auditoria where accion in ('ver_ficha', 'listado_sanitario', 'devolver', 'asignar_rol')$q$, 7);

:como_admin
\echo
select count(*) filter (where ok) as correctas, count(*) filter (where not ok) as fallidas
from pruebas.resultados \gset
\echo 'Resultado:' :correctas 'correctas,' :fallidas 'fallidas'
select case when :fallidas > 0 then 1/0 end;  -- código de salida distinto de 0 si algo falla

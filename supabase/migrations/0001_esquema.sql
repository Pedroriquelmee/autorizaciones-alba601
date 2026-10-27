-- =====================================================================
-- Gestor de inscripciones · Grupo Scout Alba 601
-- 0001 · Esquema, seguridad y almacenamiento
-- ---------------------------------------------------------------------
-- Principios de diseño:
--   1. RLS en todas las tablas: cada fila solo la ve quien debe.
--   2. Mínimo privilegio también por COLUMNA: una familia no puede
--      cambiar su rol ni marcar su inscripción como firmada.
--   3. Los datos de salud no se leen directamente: el equipo usa
--      funciones que dejan rastro en `auditoria`.
--   4. Archivos en buckets privados, sin enlaces públicos.
-- =====================================================================

create schema if not exists privado;
revoke all on schema privado from public;
grant usage on schema privado to authenticated;

-- ---------------------------------------------------------------------
-- Tipos
-- ---------------------------------------------------------------------
create type public.rol_usuario as enum ('coordinador', 'scouter', 'familia');
create type public.estado_inscripcion as enum ('borrador', 'firmada', 'validada', 'rechazada');
create type public.tipo_documento as enum ('tarjeta_sanitaria', 'dni_nie', 'cartilla_vacunacion');

-- ---------------------------------------------------------------------
-- Tablas
-- ---------------------------------------------------------------------
create table public.rondas (
  id      smallint generated always as identity primary key,
  nombre  text not null unique check (nombre ~ '^\d{4}-\d{4}$'),
  activa  boolean not null default false
);
-- Solo puede haber una ronda activa a la vez.
create unique index rondas_una_activa on public.rondas (activa) where activa;

create table public.secciones (
  id      smallint generated always as identity primary key,
  nombre  text not null unique,
  orden   smallint not null default 0
);

create table public.perfiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  email       text not null,
  nombre      text check (length(nombre) <= 120),
  rol         public.rol_usuario not null default 'familia',
  seccion_id  smallint references public.secciones (id),
  creado_en   timestamptz not null default now(),
  constraint scouter_con_seccion check (rol <> 'scouter' or seccion_id is not null)
);

create table public.educandos (
  id                uuid primary key default gen_random_uuid(),
  nombre            text not null check (length(nombre) between 1 and 80),
  apellidos         text not null check (length(apellidos) between 1 and 120),
  documento         text check (length(documento) <= 20),
  fecha_nacimiento  date not null check (fecha_nacimiento > date '1990-01-01'),
  direccion         text check (length(direccion) <= 200),
  poblacion         text check (length(poblacion) <= 80),
  provincia         text check (length(provincia) <= 80),
  codigo_postal     text check (codigo_postal ~ '^\d{5}$'),
  telefono_fijo     text check (length(telefono_fijo) <= 20),
  movil             text check (length(movil) <= 20),
  email             text check (length(email) <= 120),
  creado_por        uuid not null default auth.uid() references auth.users (id),
  creado_en         timestamptz not null default now()
);

-- Qué cuentas pueden gestionar a qué educando (padre, madre, tutor/a).
create table public.educando_tutores (
  educando_id  uuid not null references public.educandos (id) on delete cascade,
  usuario_id   uuid not null references auth.users (id) on delete cascade,
  primary key (educando_id, usuario_id)
);
create index educando_tutores_usuario on public.educando_tutores (usuario_id);

-- Una inscripción por educando y ronda. Recoge las autorizaciones y la firma.
create table public.inscripciones (
  id                       uuid primary key default gen_random_uuid(),
  educando_id              uuid not null references public.educandos (id) on delete cascade,
  ronda_id                 smallint not null references public.rondas (id),
  seccion_id               smallint references public.secciones (id),
  estado                   public.estado_inscripcion not null default 'borrador',
  motivo_rechazo           text,
  -- Autorizaciones (null = todavía sin responder)
  acepta_participacion     boolean not null default false,
  vuelve_solo              boolean,
  autoriza_medicacion      boolean,
  imagen_canales_internos  boolean,
  imagen_redes_y_medios    boolean,
  imagen_mensajeria        boolean,
  acepta_info_rgpd         boolean not null default false,
  consiente_datos_salud    boolean not null default false,
  -- Firma: solo la escribe el servidor (función `firmar`)
  firmante_nombre          text,
  firmante_documento       text,
  firma_lugar              text,
  firmada_en               timestamptz,
  firmada_por              uuid references auth.users (id),
  firma_ip                 inet,
  firma_user_agent         text,
  pdf_ruta                 text,
  pdf_sha256               text check (pdf_sha256 ~ '^[0-9a-f]{64}$'),
  creado_en                timestamptz not null default now(),
  actualizado_en           timestamptz not null default now(),
  unique (educando_id, ronda_id),
  constraint firmada_con_evidencias check (
    estado in ('borrador', 'rechazada')
    or (firmada_en is not null and pdf_ruta is not null and pdf_sha256 is not null)
  )
);
create index inscripciones_ronda_seccion on public.inscripciones (ronda_id, seccion_id);

create table public.tutores (
  id                 uuid primary key default gen_random_uuid(),
  inscripcion_id     uuid not null references public.inscripciones (id) on delete cascade,
  orden              smallint not null check (orden in (1, 2)),
  documento          text check (length(documento) <= 20),
  nombre             text check (length(nombre) <= 80),
  apellidos          text check (length(apellidos) <= 120),
  profesion          text check (length(profesion) <= 80),
  telefono_fijo      text check (length(telefono_fijo) <= 20),
  movil              text check (length(movil) <= 20),
  email              text check (length(email) <= 120),
  whatsapp_autoriza  boolean,
  whatsapp_telefono  text check (length(whatsapp_telefono) <= 20),
  unique (inscripcion_id, orden)
);

-- Datos de salud (categoría especial, art. 9 RGPD). Tabla aparte para
-- poder aplicarle reglas más estrictas que al resto.
create table public.fichas_sanitarias (
  inscripcion_id             uuid primary key references public.inscripciones (id) on delete cascade,
  seguro                     text check (length(seguro) <= 120),
  numero_seguro              text check (length(numero_seguro) <= 60),
  enuresis                   boolean,
  sonambulismo               boolean,
  enfermedad_cronica         boolean,
  enfermedad_cronica_cual    text check (length(enfermedad_cronica_cual) <= 500),
  tratamiento_medico         boolean,
  tratamiento_medico_cual    text check (length(tratamiento_medico_cual) <= 500),
  dieta_especial             boolean,
  dieta_especial_cual        text check (length(dieta_especial_cual) <= 500),
  alergia_medicamentos       boolean,
  alergia_medicamentos_cual  text check (length(alergia_medicamentos_cual) <= 500),
  otras_alergias             text check (length(otras_alergias) <= 500),
  necesidades_educativas     text check (length(necesidades_educativas) <= 500),
  actualizado_en             timestamptz not null default now()
);

-- Metadatos de los archivos subidos (el archivo vive en Storage).
create table public.documentos (
  id              uuid primary key default gen_random_uuid(),
  inscripcion_id  uuid not null references public.inscripciones (id) on delete cascade,
  tipo            public.tipo_documento not null,
  ruta            text not null unique,
  nombre_archivo  text not null check (length(nombre_archivo) <= 120),
  mime            text not null check (mime in ('application/pdf', 'image/jpeg', 'image/png')),
  tamano          integer not null check (tamano > 0 and tamano <= 5242880),
  subido_por      uuid not null default auth.uid() references auth.users (id),
  subido_en       timestamptz not null default now(),
  unique (inscripcion_id, tipo),
  -- La ruta tiene que estar en la carpeta de SU inscripción. Sin esto,
  -- una familia podría apuntar a un archivo de otra y el servidor (que
  -- lee con privilegios) lo incluiría en su expediente.
  constraint ruta_en_su_carpeta check (
    split_part(ruta, '/', 1) = inscripcion_id::text and ruta !~ '\.\.'
  )
);
create index documentos_inscripcion on public.documentos (inscripcion_id);

-- Registro de accesos: solo se añade, nunca se edita ni se borra.
create table public.auditoria (
  id          bigint generated always as identity primary key,
  en          timestamptz not null default now(),
  usuario_id  uuid,
  rol         public.rol_usuario,
  accion      text not null,
  objeto      text,
  objeto_id   uuid,
  detalle     jsonb
);
create index auditoria_en on public.auditoria (en desc);

-- ---------------------------------------------------------------------
-- Funciones auxiliares (esquema `privado`, no expuesto en la API)
-- SECURITY DEFINER + search_path vacío: evitan recursión en RLS y
-- secuestros de search_path.
-- ---------------------------------------------------------------------
create function privado.mi_rol() returns public.rol_usuario
language sql stable security definer set search_path = '' as $$
  select rol from public.perfiles where id = auth.uid()
$$;

create function privado.mi_seccion() returns smallint
language sql stable security definer set search_path = '' as $$
  select seccion_id from public.perfiles where id = auth.uid()
$$;

create function privado.ronda_activa() returns smallint
language sql stable security definer set search_path = '' as $$
  select id from public.rondas where activa
$$;

create function privado.es_tutor(p_educando uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.educando_tutores
    where educando_id = p_educando and usuario_id = auth.uid()
  )
$$;

-- Tutor de la inscripción. Con p_editable, además tiene que estar en
-- borrador o devuelta: una inscripción firmada ya no se puede tocar.
create function privado.tutor_de_inscripcion(p_inscripcion uuid, p_editable boolean default false)
returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.inscripciones i
    join public.educando_tutores t on t.educando_id = i.educando_id
    where i.id = p_inscripcion
      and t.usuario_id = auth.uid()
      and (not p_editable or i.estado in ('borrador', 'rechazada'))
  )
$$;

-- Coordinación: todas. Scouter: solo las de su sección.
create function privado.staff_de_inscripcion(p_inscripcion uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.inscripciones i
    join public.perfiles p on p.id = auth.uid()
    where i.id = p_inscripcion
      and (p.rol = 'coordinador' or (p.rol = 'scouter' and i.seccion_id = p.seccion_id))
  )
$$;

create function privado.staff_de_educando(p_educando uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.perfiles p
    where p.id = auth.uid()
      and (
        p.rol = 'coordinador'
        or (p.rol = 'scouter' and exists (
          select 1 from public.inscripciones i
          where i.educando_id = p_educando and i.seccion_id = p.seccion_id
        ))
      )
  )
$$;

-- Los datos del educando se congelan mientras su inscripción de la
-- ronda activa esté firmada o validada.
create function privado.educando_editable(p_educando uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select not exists (
    select 1 from public.inscripciones i
    where i.educando_id = p_educando
      and i.ronda_id = (select id from public.rondas where activa)
      and i.estado in ('firmada', 'validada')
  )
$$;

-- Extrae el id de inscripción de una ruta "uuid/archivo" sin reventar
-- si alguien manda basura.
create function privado.uuid_de_ruta(p_ruta text) returns uuid
language sql immutable set search_path = '' as $$
  select case
    when split_part(p_ruta, '/', 1) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then split_part(p_ruta, '/', 1)::uuid
  end
$$;

create function privado.registrar(p_accion text, p_objeto text, p_objeto_id uuid, p_detalle jsonb default null)
returns void
language sql security definer set search_path = '' as $$
  insert into public.auditoria (usuario_id, rol, accion, objeto, objeto_id, detalle)
  values (auth.uid(), privado.mi_rol(), p_accion, p_objeto, p_objeto_id, p_detalle)
$$;

revoke execute on all functions in schema privado from public;
grant execute on function
  privado.mi_rol(), privado.mi_seccion(), privado.ronda_activa(),
  privado.es_tutor(uuid), privado.tutor_de_inscripcion(uuid, boolean),
  privado.staff_de_inscripcion(uuid), privado.staff_de_educando(uuid),
  privado.educando_editable(uuid), privado.uuid_de_ruta(text)
to authenticated;
-- privado.registrar NO se concede: solo la usan las funciones de abajo.

-- ---------------------------------------------------------------------
-- Disparadores
-- ---------------------------------------------------------------------
create function privado.crear_perfil() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.perfiles (id, email) values (new.id, coalesce(new.email, ''));
  return new;
end $$;

create trigger al_crear_usuario
  after insert on auth.users
  for each row execute function privado.crear_perfil();

create function privado.vincular_tutor() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.educando_tutores (educando_id, usuario_id) values (new.id, new.creado_por);
  return new;
end $$;

create trigger al_crear_educando
  after insert on public.educandos
  for each row execute function privado.vincular_tutor();

create function privado.tocar() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.actualizado_en := now();
  return new;
end $$;

create trigger tocar before update on public.inscripciones
  for each row execute function privado.tocar();
create trigger tocar before update on public.fichas_sanitarias
  for each row execute function privado.tocar();

-- ---------------------------------------------------------------------
-- Privilegios por tabla y columna (RLS decide luego QUÉ FILAS)
-- ---------------------------------------------------------------------
-- Desde mayo de 2026, Supabase ya no da permisos automáticos a las
-- tablas nuevas: se conceden aquí uno a uno, sin depender de cómo esté
-- configurado el proyecto. Se empieza quitándolo todo y se da solo lo
-- necesario (mínimo privilegio).
grant usage on schema public to anon, authenticated, service_role;
revoke all on all tables in schema public from anon, authenticated;

-- Las funciones de servidor (firmar, descargar) usan la clave secreta.
grant select, insert, update, delete on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;

-- Con sesión iniciada se puede LEER (RLS decide qué filas)...
grant select on all tables in schema public to authenticated;

-- ...y escribir solo en estas tablas y columnas.
grant insert, update, delete on public.tutores to authenticated;
grant insert, update on public.fichas_sanitarias to authenticated;

grant update (nombre) on public.perfiles to authenticated;

grant insert (nombre, apellidos, documento, fecha_nacimiento, direccion, poblacion,
              provincia, codigo_postal, telefono_fijo, movil, email)
  on public.educandos to authenticated;
grant update (nombre, apellidos, documento, fecha_nacimiento, direccion, poblacion,
              provincia, codigo_postal, telefono_fijo, movil, email)
  on public.educandos to authenticated;

grant insert (educando_id, ronda_id, seccion_id) on public.inscripciones to authenticated;
grant update (seccion_id, acepta_participacion, vuelve_solo, autoriza_medicacion,
              imagen_canales_internos, imagen_redes_y_medios, imagen_mensajeria,
              acepta_info_rgpd, consiente_datos_salud)
  on public.inscripciones to authenticated;

grant insert (inscripcion_id, tipo, ruta, nombre_archivo, mime, tamano)
  on public.documentos to authenticated;
grant delete on public.documentos to authenticated;

-- ---------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------
alter table public.rondas            enable row level security;
alter table public.secciones         enable row level security;
alter table public.perfiles          enable row level security;
alter table public.educandos         enable row level security;
alter table public.educando_tutores  enable row level security;
alter table public.inscripciones     enable row level security;
alter table public.tutores           enable row level security;
alter table public.fichas_sanitarias enable row level security;
alter table public.documentos        enable row level security;
alter table public.auditoria         enable row level security;

create policy "Lectura con sesión" on public.rondas
  for select to authenticated using (true);
create policy "Lectura con sesión" on public.secciones
  for select to authenticated using (true);

-- Perfiles
create policy "Mi perfil, o todos si coordino" on public.perfiles
  for select to authenticated
  using (id = (select auth.uid()) or privado.mi_rol() = 'coordinador');
create policy "Editar mi nombre" on public.perfiles
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- Educandos
create policy "Ver educandos" on public.educandos
  for select to authenticated
  using (creado_por = (select auth.uid()) or privado.es_tutor(id) or privado.staff_de_educando(id));
create policy "Crear educando" on public.educandos
  for insert to authenticated
  with check (creado_por = (select auth.uid()));
create policy "Editar educando mientras no esté firmado" on public.educandos
  for update to authenticated
  using (privado.es_tutor(id) and privado.educando_editable(id))
  with check (privado.es_tutor(id) and privado.educando_editable(id));

create policy "Ver vínculos" on public.educando_tutores
  for select to authenticated
  using (usuario_id = (select auth.uid()) or privado.staff_de_educando(educando_id));

-- Inscripciones
create policy "Ver inscripciones" on public.inscripciones
  for select to authenticated
  using (
    privado.es_tutor(educando_id)
    or privado.mi_rol() = 'coordinador'
    or (privado.mi_rol() = 'scouter' and seccion_id = privado.mi_seccion())
  );
create policy "Crear inscripción en la ronda activa" on public.inscripciones
  for insert to authenticated
  with check (privado.es_tutor(educando_id) and ronda_id = privado.ronda_activa());
create policy "Editar inscripción no firmada" on public.inscripciones
  for update to authenticated
  using (privado.es_tutor(educando_id) and estado in ('borrador', 'rechazada'))
  with check (privado.es_tutor(educando_id) and estado in ('borrador', 'rechazada'));

-- Tutores
create policy "Ver tutores" on public.tutores
  for select to authenticated
  using (privado.tutor_de_inscripcion(inscripcion_id) or privado.staff_de_inscripcion(inscripcion_id));
create policy "Añadir tutores" on public.tutores
  for insert to authenticated
  with check (privado.tutor_de_inscripcion(inscripcion_id, true));
create policy "Editar tutores" on public.tutores
  for update to authenticated
  using (privado.tutor_de_inscripcion(inscripcion_id, true))
  with check (privado.tutor_de_inscripcion(inscripcion_id, true));
create policy "Quitar tutores" on public.tutores
  for delete to authenticated
  using (privado.tutor_de_inscripcion(inscripcion_id, true));

-- Ficha sanitaria: la familia la ve y edita. El equipo NO tiene política
-- de lectura: solo puede consultarla con ver_ficha() / listado_sanitario(),
-- que registran cada acceso.
create policy "La familia ve su ficha" on public.fichas_sanitarias
  for select to authenticated
  using (privado.tutor_de_inscripcion(inscripcion_id));
create policy "La familia crea su ficha" on public.fichas_sanitarias
  for insert to authenticated
  with check (privado.tutor_de_inscripcion(inscripcion_id, true));
create policy "La familia edita su ficha" on public.fichas_sanitarias
  for update to authenticated
  using (privado.tutor_de_inscripcion(inscripcion_id, true))
  with check (privado.tutor_de_inscripcion(inscripcion_id, true));

-- Documentos (metadatos)
create policy "Ver documentos" on public.documentos
  for select to authenticated
  using (privado.tutor_de_inscripcion(inscripcion_id) or privado.staff_de_inscripcion(inscripcion_id));
create policy "Registrar documento" on public.documentos
  for insert to authenticated
  with check (privado.tutor_de_inscripcion(inscripcion_id, true) and subido_por = (select auth.uid()));
create policy "Quitar documento" on public.documentos
  for delete to authenticated
  using (privado.tutor_de_inscripcion(inscripcion_id, true));

-- Auditoría: solo la coordinación la lee; nadie la modifica.
create policy "Solo coordinación" on public.auditoria
  for select to authenticated
  using (privado.mi_rol() = 'coordinador');

-- ---------------------------------------------------------------------
-- Funciones para el equipo (expuestas como RPC)
-- ---------------------------------------------------------------------

-- Ficha sanitaria de un educando. Cada llamada queda registrada.
create function public.ver_ficha(p_inscripcion uuid)
returns public.fichas_sanitarias
language plpgsql security definer set search_path = '' as $$
declare
  r public.fichas_sanitarias;
begin
  if not privado.staff_de_inscripcion(p_inscripcion) then
    raise exception 'Sin permiso para ver esta ficha' using errcode = '42501';
  end if;
  select * into r from public.fichas_sanitarias where inscripcion_id = p_inscripcion;
  perform privado.registrar('ver_ficha', 'inscripcion', p_inscripcion);
  return r;
end $$;

-- Resumen sanitario de una sección (alergias, dietas, tratamientos) para
-- salidas y campamentos. Un scouter solo puede pedir el de su sección.
create function public.listado_sanitario(p_seccion smallint default null)
returns table (
  inscripcion_id uuid, nombre text, apellidos text, seccion text, fecha_nacimiento date,
  enfermedad_cronica text, tratamiento_medico text, dieta_especial text,
  alergia_medicamentos text, otras_alergias text, necesidades_educativas text,
  enuresis boolean, sonambulismo boolean
)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  v_rol public.rol_usuario := privado.mi_rol();
begin
  if v_rol is null or v_rol = 'familia' then
    raise exception 'Sin permiso' using errcode = '42501';
  end if;
  if v_rol = 'scouter' then
    p_seccion := privado.mi_seccion();
  end if;
  perform privado.registrar('listado_sanitario', 'seccion', null,
                            jsonb_build_object('seccion_id', p_seccion));
  return query
    select i.id, e.nombre, e.apellidos, s.nombre, e.fecha_nacimiento,
           case when f.enfermedad_cronica then f.enfermedad_cronica_cual end,
           case when f.tratamiento_medico then f.tratamiento_medico_cual end,
           case when f.dieta_especial then f.dieta_especial_cual end,
           case when f.alergia_medicamentos then f.alergia_medicamentos_cual end,
           f.otras_alergias, f.necesidades_educativas, f.enuresis, f.sonambulismo
    from public.inscripciones i
    join public.educandos e on e.id = i.educando_id
    left join public.secciones s on s.id = i.seccion_id
    left join public.fichas_sanitarias f on f.inscripcion_id = i.id
    where i.ronda_id = privado.ronda_activa()
      and i.estado in ('firmada', 'validada')
      and (p_seccion is null or i.seccion_id = p_seccion)
    order by s.orden, e.apellidos, e.nombre;
end $$;

-- Validar una inscripción firmada, o devolverla a la familia con un motivo.
create function public.cambiar_estado(
  p_inscripcion uuid, p_estado public.estado_inscripcion, p_motivo text default null
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_actual public.estado_inscripcion;
begin
  if not privado.staff_de_inscripcion(p_inscripcion) then
    raise exception 'Sin permiso' using errcode = '42501';
  end if;
  if p_estado not in ('validada', 'rechazada') then
    raise exception 'Estado no permitido';
  end if;
  select estado into v_actual from public.inscripciones where id = p_inscripcion for update;
  if v_actual not in ('firmada', 'validada') then
    raise exception 'Solo se puede validar o devolver una inscripción firmada';
  end if;
  if p_estado = 'rechazada' and coalesce(trim(p_motivo), '') = '' then
    raise exception 'Indica el motivo para devolverla a la familia';
  end if;
  update public.inscripciones
     set estado = p_estado,
         motivo_rechazo = case when p_estado = 'rechazada' then left(trim(p_motivo), 500) end
   where id = p_inscripcion;
  perform privado.registrar(
    case when p_estado = 'validada' then 'validar' else 'devolver' end,
    'inscripcion', p_inscripcion,
    case when p_estado = 'rechazada' then jsonb_build_object('motivo', left(trim(p_motivo), 500)) end
  );
end $$;

-- Dar rol de scouter/coordinación a alguien que ya ha entrado una vez.
create function public.asignar_rol(p_email text, p_rol public.rol_usuario, p_seccion smallint default null)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if privado.mi_rol() is distinct from 'coordinador' then
    raise exception 'Solo la coordinación puede asignar roles' using errcode = '42501';
  end if;
  select id into v_id from public.perfiles where lower(email) = lower(trim(p_email));
  if v_id is null then
    raise exception 'Esa persona aún no ha entrado nunca. Pídele que acceda una vez con su correo.';
  end if;
  if p_rol = 'scouter' and p_seccion is null then
    raise exception 'Un scouter necesita una sección';
  end if;
  if v_id = auth.uid() and p_rol <> 'coordinador'
     and (select count(*) from public.perfiles where rol = 'coordinador') <= 1 then
    raise exception 'No puedes quitarte el rol: eres la única persona coordinadora';
  end if;
  update public.perfiles
     set rol = p_rol, seccion_id = case when p_rol = 'scouter' then p_seccion end
   where id = v_id;
  perform privado.registrar('asignar_rol', 'perfil', v_id,
                            jsonb_build_object('rol', p_rol, 'seccion_id', p_seccion));
end $$;

-- Mover una inscripción de sección (paso de etapa, error al inscribir...).
create function public.asignar_seccion(p_inscripcion uuid, p_seccion smallint)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  if privado.mi_rol() is distinct from 'coordinador' then
    raise exception 'Solo la coordinación puede cambiar la sección' using errcode = '42501';
  end if;
  update public.inscripciones set seccion_id = p_seccion where id = p_inscripcion;
  perform privado.registrar('asignar_seccion', 'inscripcion', p_inscripcion,
                            jsonb_build_object('seccion_id', p_seccion));
end $$;

revoke execute on function
  public.ver_ficha(uuid),
  public.listado_sanitario(smallint),
  public.cambiar_estado(uuid, public.estado_inscripcion, text),
  public.asignar_rol(text, public.rol_usuario, smallint),
  public.asignar_seccion(uuid, smallint)
from public, anon;
grant execute on function
  public.ver_ficha(uuid),
  public.listado_sanitario(smallint),
  public.cambiar_estado(uuid, public.estado_inscripcion, text),
  public.asignar_rol(text, public.rol_usuario, smallint),
  public.asignar_seccion(uuid, smallint)
to authenticated;

-- ---------------------------------------------------------------------
-- Almacenamiento (buckets privados)
-- El propio bucket rechaza tipos y tamaños no permitidos.
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('documentos',  'documentos',  false, 5242880,  array['application/pdf', 'image/jpeg', 'image/png']),
  ('expedientes', 'expedientes', false, 10485760, array['application/pdf'])
on conflict (id) do nothing;

-- Las familias suben, ven y quitan archivos SOLO en la carpeta de su
-- inscripción, y solo mientras no esté firmada.
create policy "Familias suben a su carpeta" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'documentos'
    and privado.tutor_de_inscripcion(privado.uuid_de_ruta(name), true)
  );
create policy "Familias ven su carpeta" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'documentos'
    and privado.tutor_de_inscripcion(privado.uuid_de_ruta(name))
  );
create policy "Familias quitan de su carpeta" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'documentos'
    and privado.tutor_de_inscripcion(privado.uuid_de_ruta(name), true)
  );
-- `expedientes` no tiene políticas: solo el servidor escribe ahí, y todas
-- las descargas del equipo pasan por la función `descargar`, que audita.

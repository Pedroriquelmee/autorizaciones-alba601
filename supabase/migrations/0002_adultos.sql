-- =====================================================================
-- Gestor de inscripciones · Grupo Scout Alba 601
-- 0002 · Secciones de mayores de edad (Scouters y Comité)
-- ---------------------------------------------------------------------
-- Las personas adultas se inscriben a sí mismas: sin tutores legales,
-- con un contacto de emergencia y su propia ficha sanitaria y cesión de
-- imagen. Las reglas de seguridad de 0001 siguen valiendo tal cual: la
-- cuenta que crea la inscripción es la que puede gestionarla.
-- =====================================================================

-- Sección para mayores de edad: cambia el formulario y el PDF.
alter table public.secciones add column adultos boolean not null default false;

-- Contacto de emergencia (adultos).
alter table public.inscripciones
  add column contacto_nombre    text check (length(contacto_nombre) <= 120),
  add column contacto_telefono1 text check (length(contacto_telefono1) <= 20),
  add column contacto_telefono2 text check (length(contacto_telefono2) <= 20);

grant update (contacto_nombre, contacto_telefono1, contacto_telefono2)
  on public.inscripciones to authenticated;

-- Preguntas de la ficha sanitaria de adultos.
alter table public.fichas_sanitarias
  add column otras_alergias_tiene boolean,
  add column anticonceptivo       boolean,
  add column embarazo             boolean,
  add column fumador              boolean,
  add column alcohol              boolean,
  add column gafas_lentillas      boolean;

-- Un scouter no puede tener asignada una sección de adultos: vería las
-- fichas sanitarias de todo el equipo. Esas secciones solo las ve la
-- coordinación. (Misma función que en 0001 con una comprobación más.)
create or replace function public.asignar_rol(p_email text, p_rol public.rol_usuario, p_seccion smallint default null)
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
  if p_rol = 'scouter' and (select adultos from public.secciones where id = p_seccion) then
    raise exception 'Scouters y Comité solo los gestiona la coordinación';
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

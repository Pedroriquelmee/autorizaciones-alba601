-- Simula lo mínimo de Supabase (roles, auth.uid(), storage) para poder
-- probar el esquema y sus reglas de seguridad en un PostgreSQL normal.
-- NO se ejecuta en Supabase: allí todo esto ya existe.

do $$ begin
  -- Los roles son de todo el servidor: solo se crean la primera vez.
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
    create role authenticated nologin noinherit;
    create role service_role nologin noinherit bypassrls;
  end if;
end $$;

create schema auth;
create table auth.users (id uuid primary key default gen_random_uuid(), email text);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;

create schema storage;
create table storage.buckets (
  id text primary key, name text, public boolean,
  file_size_limit bigint, allowed_mime_types text[]
);
create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets (id),
  name text not null,
  owner uuid default auth.uid()
);
alter table storage.objects enable row level security;
grant usage on schema storage to anon, authenticated, service_role;
grant all on storage.objects to authenticated, service_role;
grant select on storage.buckets to authenticated, service_role;

-- Como en los proyectos de Supabase creados desde mayo de 2026: las
-- tablas nuevas NO reciben permisos automáticos. Así las pruebas fallan
-- si a la migración se le olvida conceder alguno.
grant usage on schema public to anon, authenticated, service_role;

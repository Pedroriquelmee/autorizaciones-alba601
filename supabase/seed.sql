-- Datos iniciales: ronda activa y secciones del Grupo Scout Alba 601.
-- Ejecutar DESPUÉS de las migraciones 0001 y 0002.
-- Si abrís otra sección (Colonia, Clan…), añadidla aquí o desde el
-- Table Editor de Supabase. "adultos" = la persona se inscribe a sí misma.
insert into public.rondas (nombre, activa) values ('2026-2027', true);

insert into public.secciones (nombre, orden, adultos) values
  ('Manada Alba de Seonee', 1, false),
  ('Tropa Amazonas',        2, false),
  ('Esculta Mabuloa',       3, false),
  ('Scouters',              4, true),
  ('Comité',                5, true);

-- Después de entrar tú por primera vez en la web, hazte coordinador:
-- update public.perfiles set rol = 'coordinador' where email = 'tu-correo@ejemplo.com';

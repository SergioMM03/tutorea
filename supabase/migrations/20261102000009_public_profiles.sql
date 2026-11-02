-- Tutorea · Fase 14.2 · 09 Vista public_profiles
--
-- Expone solo columnas públicas y solo de la universidad de quien consulta.
-- No tiene correo (profiles tampoco lo tiene) ni legacy_id, career_id o fechas.
--
-- Se ejecuta con los permisos de su dueño (sin security_invoker) para poder leer
-- profiles sin abrir la tabla; por eso filtra ella misma con current_university_id().
-- security_barrier impide que filtros del cliente se evalúen antes que el de la vista.
-- El linter de Supabase mostrará "security_definer_view" para esta vista: es esperado.

create view public.public_profiles
with (security_barrier = true)
as
select
  p.id,
  p.university_id,
  p.full_name,
  p.career_name,
  p.academic_year,
  p.role
from public.profiles p
where p.university_id = public.current_university_id();

comment on view public.public_profiles is
  'Datos públicos (sin correo) de los usuarios de la misma universidad. Solo authenticated.';

revoke all on table public.public_profiles from public, anon, authenticated;
grant select on table public.public_profiles to authenticated;

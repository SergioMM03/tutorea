-- Tutorea · Fase 14.2 · 07 Funciones auxiliares de universidad y rol
--
-- SECURITY DEFINER porque las políticas necesitan leer el perfil propio sin activar el
-- RLS de profiles (evita la recursión profiles → política → profiles).
-- Reglas: search_path vacío y nombres calificados; el usuario sale siempre de auth.uid(),
-- nunca de un parámetro; solo devuelven datos del usuario actual.
-- Sin sesión (auth.uid() null) devuelven null / false: las políticas fallan cerradas.

create or replace function public.current_university_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.university_id
  from public.profiles p
  where p.id = (select auth.uid());
$$;

create or replace function public.current_user_role()
returns public.user_role
language sql
stable
security definer
set search_path = ''
as $$
  select p.role
  from public.profiles p
  where p.id = (select auth.uid());
$$;

-- ¿El usuario actual es administrador de esa universidad?
create or replace function public.is_admin_of(target_university_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    target_university_id is not null
    and exists (
      select 1
      from public.profiles p
      where p.id = (select auth.uid())
        and p.role = 'administrador'
        and p.university_id = target_university_id
    ),
    false
  );
$$;

revoke all on function public.current_university_id() from public, anon;
revoke all on function public.current_user_role() from public, anon;
revoke all on function public.is_admin_of(uuid) from public, anon;

grant execute on function public.current_university_id() to authenticated;
grant execute on function public.current_user_role() to authenticated;
grant execute on function public.is_admin_of(uuid) to authenticated;

-- Tutorea · Fase 14.2 · 10 assign_admin y auditoría de administradores
--
-- Procedimiento administrativo (decisiones 11, A2, C5 y C6):
--   1. Crear una cuenta INDEPENDIENTE para el administrador, con rol estudiante y metadata
--      válida (universidad, carrera, año, nombre):
--        a) registro normal en la app, o
--        b) Admin API desde la computadora del equipo (service_role en variable de
--           entorno, nunca en el repositorio ni en Flutter):
--           auth.admin.createUser({ email, password, email_confirm: true,
--             user_metadata: { university_id, career_id, full_name, academic_year } })
--      El botón "Add user" del panel de Supabase NO sirve: no envía metadata y
--      handle_new_user rechaza el registro.
--   2. En el SQL editor de Supabase (postgres) o con la service_role:
--        select public.assign_admin('<uuid de auth.users>', '<quién asigna>');
--
-- Reglas:
--   - Solo cuentas con rol estudiante. Un tutor existente no se promueve (C5).
--   - Conserva la universidad de la cuenta: un administrador solo gestiona la suya.
--   - Cada asignación queda en public.admin_role_assignments (C6): a quién, quién y cuándo.
--
-- SECURITY INVOKER a propósito (decisión 13): no necesita saltarse permisos, porque solo
-- la ejecutan postgres o service_role. EXECUTE revocado para public, anon y authenticated,
-- y una verificación interna por si alguien concede EXECUTE por error.

-- ---------------------------------------------------------------------------
-- Auditoría (append-only). Sin FK a profiles/auth.users a propósito: el registro debe
-- sobrevivir aunque la cuenta se elimine más adelante.
-- ---------------------------------------------------------------------------
create table public.admin_role_assignments (
  id               uuid primary key default gen_random_uuid(),
  target_user_id   uuid not null,                       -- a quién
  target_full_name text not null,                       -- nombre en ese momento
  university_id    uuid not null references public.universities (id) on delete restrict,
  previous_role    public.user_role not null,
  assigned_by      text not null                        -- quién (integrante del equipo)
                   check (length(trim(assigned_by)) between 3 and 120),
  db_role          text not null default current_user,  -- postgres o service_role
  assigned_at      timestamptz not null default now()   -- cuándo
);

create index admin_role_assignments_target_idx
  on public.admin_role_assignments (target_user_id, assigned_at desc);

-- Sin políticas: ningún cliente (anon / authenticated) la lee ni la escribe.
alter table public.admin_role_assignments enable row level security;

revoke all on table public.admin_role_assignments from public, anon, authenticated, service_role;
grant select, insert on table public.admin_role_assignments to service_role;

create or replace function public.prevent_audit_changes()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'La auditoría de administradores no se modifica ni se borra.'
    using errcode = '42501';
end;
$$;

revoke all on function public.prevent_audit_changes() from public, anon, authenticated;

create trigger admin_role_assignments_append_only
  before update or delete on public.admin_role_assignments
  for each row execute function public.prevent_audit_changes();

-- ---------------------------------------------------------------------------
-- assign_admin
-- ---------------------------------------------------------------------------
create or replace function public.assign_admin(target_user_id uuid, assigned_by text)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_profile public.profiles%rowtype;
  v_by      text := trim(coalesce(assigned_by, ''));
begin
  if not public.is_privileged_session() then
    raise exception 'Solo el equipo puede asignar administradores desde Supabase.'
      using errcode = '42501';
  end if;

  if length(v_by) < 3 then
    raise exception 'Indica quién realiza la asignación.' using errcode = '22023';
  end if;

  select * into v_profile
  from public.profiles p
  where p.id = target_user_id
  for update;

  if not found then
    raise exception 'La cuenta % no existe o no tiene perfil.', target_user_id
      using errcode = 'P0002';
  end if;

  if v_profile.role = 'administrador' then
    raise notice 'La cuenta % ya es administrador.', target_user_id;
    return;
  end if;

  if v_profile.role <> 'estudiante' then
    raise exception 'Solo una cuenta independiente con rol estudiante puede ser administrador (la cuenta % es %).',
      target_user_id, v_profile.role
      using errcode = '22023';
  end if;

  update public.profiles
  set role = 'administrador'
  where id = target_user_id;

  insert into public.admin_role_assignments
    (target_user_id, target_full_name, university_id, previous_role, assigned_by)
  values
    (v_profile.id, v_profile.full_name, v_profile.university_id, v_profile.role, v_by);

  raise notice 'La cuenta % ahora es administrador de su universidad.', target_user_id;
end;
$$;

revoke all on function public.assign_admin(uuid, text) from public, anon, authenticated;
grant execute on function public.assign_admin(uuid, text) to service_role;

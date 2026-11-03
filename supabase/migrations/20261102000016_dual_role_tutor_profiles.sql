-- Tutorea · Corrección de la Fase 14.7 · 16 Doble rol: estudiante y tutor en la misma cuenta
--
-- Decisión funcional: una misma cuenta puede actuar como estudiante y como tutor.
--  - Tener una fila en tutor_profiles = poder ofrecer tutorías.
--  - profiles.role ya no decide si alguien puede ser tutor: queda como el rol
--    principal elegido al registrarse ('estudiante' o 'tutor', solo define la
--    pantalla inicial) y para 'administrador', que se asigna solo desde el servidor.
--  - Buscar tutores y solicitar tutorías no depende del rol (las políticas de
--    lectura de las migraciones 12–14 ya solo exigen sesión y misma universidad).
--
-- Esta migración no modifica las anteriores: reemplaza dos funciones.
--  1. prepare_tutor_profile (migración 12): ya no exige role = 'tutor'. Cualquier
--     cuenta estudiante o tutor crea SU perfil; una cuenta administradora no
--     (sus privilegios siguen separados). El resto de la guarda no cambia.
--  2. assign_admin (migración 10): además de exigir una cuenta con rol estudiante,
--     rechaza cuentas que ya ofrecen tutorías (tienen tutor_profiles), para que
--     un administrador siga siendo una cuenta independiente.

-- ---------------------------------------------------------------------------
-- 1. prepare_tutor_profile
-- ---------------------------------------------------------------------------
create or replace function public.prepare_tutor_profile()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_privileged boolean := public.is_privileged_session();
  v_role       public.user_role;
begin
  if tg_op = 'INSERT' then
    if v_privileged then
      select p.role into v_role from public.profiles p where p.id = new.user_id;
      if new.university_id is null then
        select p.university_id into new.university_id from public.profiles p where p.id = new.user_id;
      end if;
    else
      new.user_id := auth.uid();
      if new.user_id is null then
        raise exception 'Inicia sesión para crear tu perfil de tutor.' using errcode = '42501';
      end if;
      new.university_id := public.current_university_id();
      v_role := public.current_user_role();
      new.rating_avg := null;
      new.rating_count := 0;
      new.photo_path := null;
      new.legacy_id := null;
    end if;
    if v_role is null then
      raise exception 'Tu cuenta no tiene perfil; no puede ofrecer tutorías.' using errcode = '42501';
    end if;
    if v_role = 'administrador' then
      raise exception 'Una cuenta administradora no puede ofrecer tutorías.' using errcode = '42501';
    end if;
    return new;
  end if;

  -- UPDATE (sin cambios respecto de la migración 12)
  if not v_privileged then
    if new.id is distinct from old.id
       or new.user_id is distinct from old.user_id
       or new.university_id is distinct from old.university_id
       or new.rating_avg is distinct from old.rating_avg
       or new.rating_count is distinct from old.rating_count
       or new.legacy_id is distinct from old.legacy_id
       or new.photo_path is distinct from old.photo_path then
      raise exception 'Ese dato del perfil de tutor no se puede cambiar desde la app.' using errcode = '42501';
    end if;
    if old.user_id is distinct from auth.uid()
       and (new.description, new.hourly_rate, new.offers_in_person, new.offers_virtual)
           is distinct from (old.description, old.hourly_rate, old.offers_in_person, old.offers_virtual) then
      raise exception 'Un administrador solo puede activar o desactivar perfiles de tutor.' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.prepare_tutor_profile() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. assign_admin: igual que en la migración 10, más el rechazo de cuentas que
--    ofrecen tutorías. Conserva sus permisos (solo service_role y postgres).
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

  if exists (select 1 from public.tutor_profiles tp where tp.user_id = target_user_id) then
    raise exception 'La cuenta % ofrece tutorías; un administrador debe ser una cuenta independiente.',
      target_user_id
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

comment on column public.profiles.role is
  'Rol principal: estudiante o tutor (pantalla inicial) o administrador (solo con assign_admin). '
  'Ofrecer tutorías depende de tener tutor_profiles, no de este valor.';

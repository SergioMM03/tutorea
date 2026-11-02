-- Tutorea · Fase 14.2 · 08 handle_new_user y protección de rol y universidad

-- ---------------------------------------------------------------------------
-- Rol privilegiado: la conexión directa del equipo (SQL editor, migraciones) o la
-- service_role. Una petición de la app (JWT anon o authenticated) nunca lo es, ni
-- siquiera dentro de una función SECURITY DEFINER.
-- ---------------------------------------------------------------------------
create or replace function public.is_privileged_session()
returns boolean
language sql
stable
security invoker  -- invoker: current_user debe ser el de quien llama
set search_path = ''
as $$
  select current_user in ('postgres', 'service_role', 'supabase_admin')
     and coalesce((select auth.jwt()) ->> 'role', '') not in ('anon', 'authenticated');
$$;

revoke all on function public.is_privileged_session() from public, anon;
-- authenticated la necesita porque la guarda de profiles (security invoker) la llama
-- en cada update; solo devuelve un booleano sobre la sesión actual.
grant execute on function public.is_privileged_session() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- handle_new_user: crea el perfil al registrarse.
-- Metadata esperada (options.data en signUp):
--   university_id (uuid), career_id (uuid), full_name, academic_year (1–10), role.
-- role: solo 'tutor' se respeta; cualquier otro valor, incluido 'administrador',
-- se convierte en 'estudiante'. legacy_id nunca se lee de la metadata.
-- Si un dato no es válido el registro falla completo (no queda usuario sin perfil).
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  meta            jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_name          text  := trim(coalesce(meta ->> 'full_name', ''));
  v_university_id uuid;
  v_career_id     uuid;
  v_career_name   text;
  v_year          smallint;
  v_role          public.user_role;
begin
  begin
    v_university_id := nullif(meta ->> 'university_id', '')::uuid;
    v_career_id     := nullif(meta ->> 'career_id', '')::uuid;
    v_year          := nullif(meta ->> 'academic_year', '')::smallint;
  exception
    when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'Datos de registro no válidos.' using errcode = '22023';
  end;

  if v_university_id is null or not exists (
    select 1 from public.universities u
    where u.id = v_university_id and u.is_active
  ) then
    raise exception 'Universidad no válida o no disponible.' using errcode = '22023';
  end if;

  select c.name into v_career_name
  from public.careers c
  where c.id = v_career_id and c.university_id = v_university_id;

  if v_career_name is null then
    raise exception 'Carrera no válida para esta universidad.' using errcode = '22023';
  end if;

  if v_year is null or v_year not between 1 and 10 then
    raise exception 'Año académico no válido.' using errcode = '22023';
  end if;

  if length(v_name) < 2 then
    raise exception 'Escribe tu nombre.' using errcode = '22023';
  end if;

  v_role := case
    when meta ->> 'role' = 'tutor' then 'tutor'::public.user_role
    else 'estudiante'::public.user_role
  end;

  insert into public.profiles (id, university_id, role, full_name, career_id, career_name, academic_year)
  values (new.id, v_university_id, v_role, v_name, v_career_id, v_career_name, v_year);

  return new;
end;
$$;

revoke all on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Guarda de identidad: rechaza cambios de id, role, university_id o legacy_id salvo
-- en una sesión privilegiada. Es la segunda defensa: los permisos de columna ya
-- impiden que authenticated escriba esas columnas.
-- ---------------------------------------------------------------------------
create or replace function public.guard_profile_identity()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if (new.id is distinct from old.id
      or new.role is distinct from old.role
      or new.university_id is distinct from old.university_id
      or new.legacy_id is distinct from old.legacy_id)
     and not public.is_privileged_session() then
    raise exception 'No se puede cambiar el rol ni la universidad de una cuenta.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function public.guard_profile_identity() from public, anon, authenticated;

create trigger profiles_guard_identity
  before update on public.profiles
  for each row execute function public.guard_profile_identity();

-- ---------------------------------------------------------------------------
-- career_name se toma siempre de la carrera elegida, así el texto visible no puede
-- contradecir a career_id. La carrera es obligatoria (career_id not null en la tabla)
-- y se puede cambiar por otra carrera de la misma universidad.
-- SECURITY DEFINER solo para leer el nombre aunque la universidad esté inactiva.
-- ---------------------------------------------------------------------------
create or replace function public.sync_profile_career()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.career_id is null then
    raise exception 'Elige tu carrera.' using errcode = '23502';
  end if;

  select c.name into new.career_name
  from public.careers c
  where c.id = new.career_id and c.university_id = new.university_id;

  if not found then
    raise exception 'La carrera no pertenece a tu universidad.' using errcode = '23503';
  end if;
  return new;
end;
$$;

revoke all on function public.sync_profile_career() from public, anon, authenticated;

create trigger profiles_sync_career
  before insert or update on public.profiles
  for each row execute function public.sync_profile_career();

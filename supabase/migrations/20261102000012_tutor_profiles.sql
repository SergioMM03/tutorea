-- Tutorea · Fase 14.7 · 12 tutor_profiles
-- Perfil de tutor (uno por cuenta con rol tutor), según el diseño 14.1 sección 3.
-- El servidor fija user_id (auth.uid()) y university_id (la del perfil); el
-- cliente nunca los envía. rating_*, photo_path y legacy_id no los escribe la app.

create table public.tutor_profiles (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null unique,
  university_id     uuid not null,
  description       text not null default '' check (length(description) <= 2000),
  hourly_rate       numeric(8,2) not null check (hourly_rate >= 0),
  offers_in_person  boolean not null default true,
  offers_virtual    boolean not null default true,
  is_active         boolean not null default true,
  photo_path        text,                       -- Storage (fase de fotografías)
  rating_avg        numeric(3,2) check (rating_avg between 1 and 5), -- trigger de reviews
  rating_count      integer not null default 0 check (rating_count >= 0),
  legacy_id         text unique,                -- tp-valeria…; solo migración
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint tutor_profiles_modality_check check (offers_in_person or offers_virtual),
  -- Destino de las FK compuestas de tutor_subjects y (más adelante) bookings.
  constraint tutor_profiles_id_university_key unique (id, university_id),
  constraint tutor_profiles_user_fk foreign key (user_id, university_id)
    references public.profiles (id, university_id) on delete cascade
);

create index tutor_profiles_university_active_idx on public.tutor_profiles (university_id, is_active);

alter table public.tutor_profiles enable row level security;

create trigger tutor_profiles_set_updated_at
  before update on public.tutor_profiles
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Preparación y guarda. SECURITY INVOKER: is_privileged_session() debe ver el
-- current_user real de quien llama.
--  - Alta desde la app: user_id = auth.uid(), university_id = la del perfil,
--    rating/foto/legacy vacíos; la cuenta debe tener rol tutor.
--  - Cambios desde la app: nunca id, user_id, university_id, rating_*,
--    legacy_id ni photo_path. Si quien cambia no es el dueño (administrador de
--    esa universidad, según RLS), solo puede cambiar is_active.
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
    if v_role is distinct from 'tutor' then
      raise exception 'Solo una cuenta con rol tutor puede tener perfil de tutor.' using errcode = '42501';
    end if;
    return new;
  end if;

  -- UPDATE
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

create trigger tutor_profiles_prepare
  before insert or update on public.tutor_profiles
  for each row execute function public.prepare_tutor_profile();

-- ---------------------------------------------------------------------------
-- Permisos y RLS
-- ---------------------------------------------------------------------------
revoke all on table public.tutor_profiles from public, anon, authenticated;
grant select on table public.tutor_profiles to authenticated;
grant insert (description, hourly_rate, offers_in_person, offers_virtual, is_active)
  on table public.tutor_profiles to authenticated;
grant update (description, hourly_rate, offers_in_person, offers_virtual, is_active)
  on table public.tutor_profiles to authenticated;
-- Sin delete: un perfil se desactiva, no se borra (historial de reservas).

-- Leer: su universidad; activos, el propio o, si es administrador, todos.
create policy tutor_profiles_select_university
  on public.tutor_profiles for select
  to authenticated
  using (
    university_id = (select public.current_university_id())
    and (is_active or user_id = (select auth.uid()) or public.is_admin_of(university_id))
  );

-- Crear: el propio usuario (el trigger exige rol tutor y fija universidad).
create policy tutor_profiles_insert_own
  on public.tutor_profiles for insert
  to authenticated
  with check (user_id = (select auth.uid()) and university_id = (select public.current_university_id()));

create policy tutor_profiles_update_own
  on public.tutor_profiles for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- El administrador de esa universidad puede activar o desactivar (el trigger
-- le impide cambiar lo demás).
create policy tutor_profiles_update_admin
  on public.tutor_profiles for update
  to authenticated
  using (public.is_admin_of(university_id))
  with check (public.is_admin_of(university_id));

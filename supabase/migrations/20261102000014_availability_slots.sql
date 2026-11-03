-- Tutorea · Fase 14.7 · 14 availability_slots
-- Bloques semanales de disponibilidad, en minutos desde medianoche (igual que
-- AvailabilitySlot en Flutter). La base impide bloques inválidos y cruces.

create table public.availability_slots (
  id                uuid primary key default gen_random_uuid(),
  tutor_profile_id  uuid not null references public.tutor_profiles (id) on delete cascade,
  weekday           smallint not null check (weekday between 1 and 7),   -- 1 = lunes
  start_minute      smallint not null check (start_minute between 0 and 1439),
  end_minute        smallint not null check (end_minute <= 1440),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint availability_slots_range_check check (end_minute > start_minute),
  -- Sin bloques que se crucen del mismo tutor y día (btree_gist, migración 01).
  constraint availability_slots_no_overlap exclude using gist (
    tutor_profile_id with =,
    weekday with =,
    int4range(start_minute, end_minute) with &&
  )
);

create index availability_slots_profile_idx on public.availability_slots (tutor_profile_id, weekday);

alter table public.availability_slots enable row level security;

create trigger availability_slots_set_updated_at
  before update on public.availability_slots
  for each row execute function public.set_updated_at();

revoke all on table public.availability_slots from public, anon, authenticated;
grant select, delete on table public.availability_slots to authenticated;
grant insert (tutor_profile_id, weekday, start_minute, end_minute)
  on table public.availability_slots to authenticated;
grant update (weekday, start_minute, end_minute) on table public.availability_slots to authenticated;

-- Leer: los bloques de los perfiles que el usuario puede ver (RLS de tutor_profiles).
create policy availability_slots_select_visible
  on public.availability_slots for select
  to authenticated
  using (exists (select 1 from public.tutor_profiles tp where tp.id = tutor_profile_id));

-- Escribir: solo el dueño del perfil de tutor.
create policy availability_slots_insert_owner
  on public.availability_slots for insert
  to authenticated
  with check (exists (
    select 1 from public.tutor_profiles tp
    where tp.id = tutor_profile_id and tp.user_id = (select auth.uid())
  ));

create policy availability_slots_update_owner
  on public.availability_slots for update
  to authenticated
  using (exists (
    select 1 from public.tutor_profiles tp
    where tp.id = tutor_profile_id and tp.user_id = (select auth.uid())
  ))
  with check (exists (
    select 1 from public.tutor_profiles tp
    where tp.id = tutor_profile_id and tp.user_id = (select auth.uid())
  ));

create policy availability_slots_delete_owner
  on public.availability_slots for delete
  to authenticated
  using (exists (
    select 1 from public.tutor_profiles tp
    where tp.id = tutor_profile_id and tp.user_id = (select auth.uid())
  ));

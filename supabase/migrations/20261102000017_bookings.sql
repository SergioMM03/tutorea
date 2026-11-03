-- Tutorea · Fase 14.8 · 17 bookings (reservas)
--
-- Una reserva relaciona a la cuenta que solicita (student_id) con un perfil de
-- tutor (tutor_profile_id) de la MISMA universidad, para una materia de esa
-- universidad. Cualquier cuenta puede solicitar (doble rol, migración 16).
--
-- Escritura: solo con las funciones de la migración 18 (request_booking,
-- accept_booking, reject_booking, cancel_booking). La app no tiene permisos de
-- insert, update ni delete sobre la tabla.
--
-- Fechas: starts_at / ends_at son timestamptz (se guardan en UTC). La
-- disponibilidad semanal del tutor (availability_slots) está en hora local de la
-- universidad; la conversión se hace en el servidor con public.tutorea_time_zone()
-- ('America/El_Salvador', sin horario de verano).
--
-- Estados (enum booking_status, migración 02) y transiciones permitidas:
--   pendiente              → aceptada | rechazada | cancelada
--   aceptada               → cancelada | pendiente_confirmacion
--   pendiente_confirmacion → completada
--   rechazada, cancelada, completada: finales.
-- Las confirmaciones e incidencias (pendiente_confirmacion → completada) llegan
-- en una fase posterior; la guarda ya acepta esas transiciones.

-- ---------------------------------------------------------------------------
-- Zona horaria de Tutorea (una sola universidad por ahora: ESEN, El Salvador).
-- ---------------------------------------------------------------------------
create or replace function public.tutorea_time_zone()
returns text
language sql
immutable
set search_path = ''
as $$ select 'America/El_Salvador'::text $$;

grant execute on function public.tutorea_time_zone() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Tabla
-- ---------------------------------------------------------------------------
create table public.bookings (
  id                   uuid primary key default gen_random_uuid(),
  university_id        uuid not null,
  student_id           uuid not null,
  tutor_profile_id     uuid not null,
  subject_id           uuid not null,
  modality             public.booking_modality not null,
  topic                text check (topic is null or length(topic) <= 500),
  location             text check (location is null or length(location) <= 300), -- lugar o enlace
  starts_at            timestamptz not null,
  ends_at              timestamptz not null,
  duration_minutes     smallint not null check (duration_minutes in (60, 90, 120)),
  agreed_price         numeric(8,2) not null check (agreed_price >= 0),  -- se fija al solicitar
  status               public.booking_status not null default 'pendiente',
  status_changed_at    timestamptz not null default now(),
  responded_at         timestamptz,            -- aceptada o rechazada
  cancelled_by         uuid,
  cancelled_at         timestamptz,
  cancellation_reason  text check (cancellation_reason is null or length(cancellation_reason) <= 500),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),

  constraint bookings_ends_check check (ends_at = starts_at + duration_minutes * interval '1 minute'),
  constraint bookings_cancel_fields_check check (
    (status = 'cancelada') = (cancelled_at is not null)
    and (cancelled_at is null) = (cancelled_by is null)
  ),
  -- Todo en la misma universidad (FK compuestas).
  constraint bookings_student_fk foreign key (student_id, university_id)
    references public.profiles (id, university_id) on delete restrict,
  constraint bookings_tutor_fk foreign key (tutor_profile_id, university_id)
    references public.tutor_profiles (id, university_id) on delete restrict,
  constraint bookings_subject_fk foreign key (subject_id, university_id)
    references public.subjects (id, university_id) on delete restrict,
  -- Una sesión confirmada no se cruza con otra del mismo tutor ni del mismo estudiante.
  -- Las pendientes pueden coexistir; el cruce se comprueba al aceptar.
  constraint bookings_tutor_no_overlap exclude using gist (
    tutor_profile_id with =,
    tstzrange(starts_at, ends_at) with &&
  ) where (status in ('aceptada', 'pendiente_confirmacion', 'completada')),
  constraint bookings_student_no_overlap exclude using gist (
    student_id with =,
    tstzrange(starts_at, ends_at) with &&
  ) where (status in ('aceptada', 'pendiente_confirmacion', 'completada'))
);

-- Una sola solicitud vigente por estudiante, tutor y hora de inicio.
create unique index bookings_no_duplicate_request_idx
  on public.bookings (student_id, tutor_profile_id, starts_at)
  where status in ('pendiente', 'aceptada');

create index bookings_student_idx on public.bookings (student_id, starts_at desc);
create index bookings_tutor_idx on public.bookings (tutor_profile_id, starts_at);
create index bookings_university_idx on public.bookings (university_id);

alter table public.bookings enable row level security;

create trigger bookings_set_updated_at
  before update on public.bookings
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Guarda: transiciones, campos protegidos y nada de borrados.
-- SECURITY INVOKER (solo compara filas). Aplica también a las funciones de la
-- migración 18: es la última defensa si alguna tuviera un error.
-- ---------------------------------------------------------------------------
create or replace function public.guard_booking_changes()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Las reservas no se eliminan; se cancelan.' using errcode = '42501';
  end if;

  if tg_op = 'INSERT' then
    new.ends_at := new.starts_at + new.duration_minutes * interval '1 minute';
    new.status_changed_at := now();
    if not public.is_privileged_session() then
      if new.status is distinct from 'pendiente'
         or new.responded_at is not null
         or new.cancelled_at is not null
         or new.cancelled_by is not null
         or new.cancellation_reason is not null then
        raise exception 'Toda reserva nueva nace pendiente.' using errcode = '42501';
      end if;
    end if;
    return new;
  end if;

  -- UPDATE: lo acordado no cambia.
  if new.id is distinct from old.id
     or new.university_id is distinct from old.university_id
     or new.student_id is distinct from old.student_id
     or new.tutor_profile_id is distinct from old.tutor_profile_id
     or new.subject_id is distinct from old.subject_id
     or new.modality is distinct from old.modality
     or new.topic is distinct from old.topic
     or new.location is distinct from old.location
     or new.starts_at is distinct from old.starts_at
     or new.ends_at is distinct from old.ends_at
     or new.duration_minutes is distinct from old.duration_minutes
     or new.agreed_price is distinct from old.agreed_price
     or new.created_at is distinct from old.created_at then
    raise exception 'Los datos acordados de una reserva no se modifican.' using errcode = '42501';
  end if;

  if new.status is distinct from old.status then
    if not (
      (old.status = 'pendiente' and new.status in ('aceptada', 'rechazada', 'cancelada'))
      or (old.status = 'aceptada' and new.status in ('cancelada', 'pendiente_confirmacion'))
      or (old.status = 'pendiente_confirmacion' and new.status = 'completada')
    ) then
      raise exception 'Una reserva % no puede pasar a %.', old.status, new.status using errcode = 'TU010';
    end if;
    new.status_changed_at := now();
  elsif new.status_changed_at is distinct from old.status_changed_at then
    raise exception 'La fecha del último cambio la fija el servidor.' using errcode = '42501';
  end if;

  -- Los datos de cancelación solo se escriben al cancelar, y no se cambian después.
  if (new.cancelled_by, new.cancelled_at, new.cancellation_reason)
     is distinct from (old.cancelled_by, old.cancelled_at, old.cancellation_reason)
     and not (old.status <> 'cancelada' and new.status = 'cancelada') then
    raise exception 'Los datos de cancelación no se modifican.' using errcode = '42501';
  end if;
  if new.responded_at is distinct from old.responded_at
     and not (old.status = 'pendiente' and new.status in ('aceptada', 'rechazada')) then
    raise exception 'La fecha de respuesta no se modifica.' using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function public.guard_booking_changes() from public, anon, authenticated;

create trigger bookings_guard
  before insert or update or delete on public.bookings
  for each row execute function public.guard_booking_changes();

-- ---------------------------------------------------------------------------
-- Ayudantes para políticas (SECURITY DEFINER: evitan la recursión entre las
-- políticas de bookings y tutor_profiles). Solo responden sobre auth.uid().
-- ---------------------------------------------------------------------------
create or replace function public.owns_tutor_profile(target_tutor_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.tutor_profiles tp
    where tp.id = target_tutor_profile_id and tp.user_id = (select auth.uid())
  );
$$;

create or replace function public.has_booking_with_tutor(target_tutor_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.bookings b
    where b.tutor_profile_id = target_tutor_profile_id and b.student_id = (select auth.uid())
  );
$$;

revoke all on function public.owns_tutor_profile(uuid) from public, anon;
revoke all on function public.has_booking_with_tutor(uuid) from public, anon;
grant execute on function public.owns_tutor_profile(uuid) to authenticated;
grant execute on function public.has_booking_with_tutor(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Permisos y RLS: solo lectura para las partes de la reserva.
-- ---------------------------------------------------------------------------
revoke all on table public.bookings from public, anon, authenticated;
grant select on table public.bookings to authenticated;

-- Quien solicitó o el dueño del perfil de tutor, siempre dentro de su universidad.
create policy bookings_select_participants
  on public.bookings for select
  to authenticated
  using (
    university_id = (select public.current_university_id())
    and (student_id = (select auth.uid()) or public.owns_tutor_profile(tutor_profile_id))
  );

-- Quien tiene una reserva con un tutor sigue viendo su perfil aunque el tutor lo
-- haya desactivado (para mostrar el historial). Se suma a las políticas de la 12.
create policy tutor_profiles_select_booked
  on public.tutor_profiles for select
  to authenticated
  using (
    university_id = (select public.current_university_id())
    and public.has_booking_with_tutor(id)
  );

-- ---------------------------------------------------------------------------
-- Supabase Realtime: cambios de reservas para las dos partes (respeta RLS).
-- La publicación existe en Supabase; en un PostgreSQL sin Supabase no se hace nada.
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.bookings;
  end if;
end;
$$;

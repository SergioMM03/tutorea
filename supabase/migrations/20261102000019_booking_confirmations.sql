-- Tutorea · Fase 14.9 · 19 confirmaciones de sesiones (tabla y ayudantes)
--
-- Después de la hora de fin, cada parte (estudiante y tutor) confirma que la
-- sesión se realizó. La primera confirmación deja la reserva en
-- 'pendiente_confirmacion' y la segunda en 'completada' (función
-- confirm_booking, migración 21, que también revisa las incidencias abiertas).
-- Nada se completa solo por tiempo.
--
-- Una fila por parte y reserva (PK). Historial: las filas no se modifican ni
-- se borran. La app solo LEE; escribir es exclusivo de confirm_booking.

-- ---------------------------------------------------------------------------
-- (id, university_id) único en bookings: destino de las FK compuestas de las
-- tablas de seguimiento (confirmaciones, incidencias, reseñas), para que todo
-- quede en la universidad de la reserva.
-- ---------------------------------------------------------------------------
alter table public.bookings
  add constraint bookings_id_university_key unique (id, university_id);

-- ---------------------------------------------------------------------------
-- Ayudante: ¿qué parte de la reserva es la cuenta con sesión?
-- 'estudiante', 'tutor' o null (no participa). SECURITY DEFINER para usarse en
-- políticas sin recursión de RLS; solo responde sobre auth.uid().
-- ---------------------------------------------------------------------------
create or replace function public.booking_party(target_booking_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when b.student_id = (select auth.uid()) then 'estudiante'
    when tp.user_id = (select auth.uid()) then 'tutor'
  end
  from public.bookings b
  join public.tutor_profiles tp on tp.id = b.tutor_profile_id
  where b.id = target_booking_id;
$$;

revoke all on function public.booking_party(uuid) from public, anon;
grant execute on function public.booking_party(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Ayudante para triggers de seguridad: bloquea UPDATE y DELETE en tablas de
-- historial (incluso desde funciones de la app). Solo una sesión privilegiada
-- del equipo puede corregir datos.
-- ---------------------------------------------------------------------------
create or replace function public.prevent_history_changes()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if public.is_privileged_session() then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  raise exception 'Este historial no se modifica ni se elimina.' using errcode = '42501';
end;
$$;

revoke all on function public.prevent_history_changes() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Tabla
-- ---------------------------------------------------------------------------
create table public.booking_confirmations (
  booking_id     uuid not null,
  university_id  uuid not null,
  party          text not null check (party in ('estudiante', 'tutor')),
  user_id        uuid not null,
  confirmed_at   timestamptz not null default now(),
  primary key (booking_id, party),
  constraint booking_confirmations_user_key unique (booking_id, user_id),
  constraint booking_confirmations_booking_fk foreign key (booking_id, university_id)
    references public.bookings (id, university_id) on delete restrict,
  constraint booking_confirmations_user_fk foreign key (user_id, university_id)
    references public.profiles (id, university_id) on delete restrict
);

create index booking_confirmations_university_idx on public.booking_confirmations (university_id);

alter table public.booking_confirmations enable row level security;

create trigger booking_confirmations_history
  before update or delete on public.booking_confirmations
  for each row execute function public.prevent_history_changes();

-- Solo lectura: las partes de la reserva y el administrador de esa universidad.
revoke all on table public.booking_confirmations from public, anon, authenticated;
grant select on table public.booking_confirmations to authenticated;

create policy booking_confirmations_select_participants
  on public.booking_confirmations for select
  to authenticated
  using (
    university_id = (select public.current_university_id())
    and public.booking_party(booking_id) is not null
  );

create policy booking_confirmations_select_admin
  on public.booking_confirmations for select
  to authenticated
  using (public.is_admin_of(university_id));

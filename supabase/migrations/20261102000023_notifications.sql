-- Tutorea · Fase 14.9 · 23 notificaciones
--
-- Las crea SOLO el servidor, con triggers sobre bookings y booking_incidents:
--   reserva_solicitada     → al tutor, al crear la solicitud
--   reserva_aceptada       → al estudiante
--   reserva_rechazada      → al estudiante
--   reserva_cancelada      → a la otra parte (no a quien canceló)
--   confirmacion_pendiente → a la parte que todavía no confirmó
--   reserva_completada     → a las dos partes
--   incidencia_reportada   → a la otra parte y a los administradores de la universidad
--   incidencia_actualizada → a las dos partes (cambio de estado por el administrador)
-- Las notas internas de una incidencia no notifican.
--
-- Sin duplicados: event_key identifica el hecho (p. ej. 'booking:<id>:aceptada')
-- y es único por destinatario; los estados de reservas e incidencias no se
-- repiten, así que cada hecho genera como mucho una notificación por persona.
--
-- La app solo LEE sus notificaciones y las marca como leídas con
-- mark_notifications_read (no puede insertar, cambiar ni borrar). Realtime:
-- se agrega a la publicación supabase_realtime (respeta RLS).

create table public.notifications (
  id             uuid primary key default gen_random_uuid(),
  recipient_id   uuid not null,
  university_id  uuid not null,
  type           public.notification_type not null,
  booking_id     uuid,
  incident_id    uuid,
  event_key      text not null,
  read_at        timestamptz,
  created_at     timestamptz not null default now(),
  constraint notifications_event_key unique (recipient_id, event_key),
  constraint notifications_recipient_fk foreign key (recipient_id, university_id)
    references public.profiles (id, university_id) on delete cascade,
  constraint notifications_booking_fk foreign key (booking_id, university_id)
    references public.bookings (id, university_id) on delete cascade,
  constraint notifications_incident_fk foreign key (incident_id, university_id)
    references public.booking_incidents (id, university_id) on delete cascade,
  constraint notifications_reference_check check (booking_id is not null or incident_id is not null)
);

create index notifications_recipient_idx on public.notifications (recipient_id, created_at desc);
create index notifications_unread_idx on public.notifications (recipient_id) where read_at is null;

alter table public.notifications enable row level security;

-- Guarda: solo read_at puede pasar de null a una fecha; nada más cambia.
create or replace function public.guard_notification_changes()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if public.is_privileged_session() then return old; end if;
    raise exception 'Las notificaciones no se eliminan.' using errcode = '42501';
  end if;
  if (new.id, new.recipient_id, new.university_id, new.type, new.booking_id, new.incident_id,
      new.event_key, new.created_at)
     is distinct from
     (old.id, old.recipient_id, old.university_id, old.type, old.booking_id, old.incident_id,
      old.event_key, old.created_at)
     or (old.read_at is not null and new.read_at is distinct from old.read_at) then
    raise exception 'Una notificación solo se puede marcar como leída.' using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function public.guard_notification_changes() from public, anon, authenticated;

create trigger notifications_guard
  before update or delete on public.notifications
  for each row execute function public.guard_notification_changes();

revoke all on table public.notifications from public, anon, authenticated;
grant select on table public.notifications to authenticated;

create policy notifications_select_own
  on public.notifications for select
  to authenticated
  using (recipient_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Marcar como leídas (las propias). p_ids null = todas.
-- ---------------------------------------------------------------------------
create or replace function public.mark_notifications_read(p_ids uuid[] default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_count integer;
begin
  if v_uid is null then
    raise exception 'Inicia sesión.' using errcode = '42501';
  end if;
  update public.notifications n
  set read_at = now()
  where n.recipient_id = v_uid
    and n.read_at is null
    and (p_ids is null or n.id = any (p_ids));
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.mark_notifications_read(uuid[]) from public, anon;
grant execute on function public.mark_notifications_read(uuid[]) to authenticated;

-- ---------------------------------------------------------------------------
-- Ayudante interno: una notificación sin duplicar.
-- ---------------------------------------------------------------------------
create or replace function public.push_notification(
  p_recipient   uuid,
  p_university  uuid,
  p_type        public.notification_type,
  p_booking_id  uuid,
  p_incident_id uuid,
  p_event_key   text
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.notifications (recipient_id, university_id, type, booking_id, incident_id, event_key)
  select p_recipient, p_university, p_type, p_booking_id, p_incident_id, p_event_key
  where p_recipient is not null
  on conflict (recipient_id, event_key) do nothing;
$$;

revoke all on function public.push_notification(uuid, uuid, public.notification_type, uuid, uuid, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Reservas
-- ---------------------------------------------------------------------------
create or replace function public.notify_booking_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tutor_user uuid;
  v_key        text := 'booking:' || new.id || ':' || new.status;
begin
  if tg_op = 'UPDATE' and new.status is not distinct from old.status then
    return null;
  end if;
  -- Una reserva nueva de la app siempre nace pendiente; las que el equipo carga
  -- con otro estado (datos migrados) no generan avisos.
  if tg_op = 'INSERT' and new.status <> 'pendiente' then
    return null;
  end if;
  select tp.user_id into v_tutor_user from public.tutor_profiles tp where tp.id = new.tutor_profile_id;

  case new.status
    when 'pendiente' then
      perform public.push_notification(v_tutor_user, new.university_id, 'reserva_solicitada', new.id, null, v_key);
    when 'aceptada' then
      perform public.push_notification(new.student_id, new.university_id, 'reserva_aceptada', new.id, null, v_key);
    when 'rechazada' then
      perform public.push_notification(new.student_id, new.university_id, 'reserva_rechazada', new.id, null, v_key);
    when 'cancelada' then
      perform public.push_notification(
        case when new.cancelled_by = new.student_id then v_tutor_user else new.student_id end,
        new.university_id, 'reserva_cancelada', new.id, null, v_key);
    when 'pendiente_confirmacion' then
      -- A la parte que aún no confirmó (confirm_booking guarda la confirmación antes).
      if exists (select 1 from public.booking_confirmations c
                 where c.booking_id = new.id and c.party = 'estudiante') then
        perform public.push_notification(v_tutor_user, new.university_id, 'confirmacion_pendiente', new.id, null, v_key);
      end if;
      if exists (select 1 from public.booking_confirmations c
                 where c.booking_id = new.id and c.party = 'tutor') then
        perform public.push_notification(new.student_id, new.university_id, 'confirmacion_pendiente', new.id, null, v_key);
      end if;
    when 'completada' then
      perform public.push_notification(new.student_id, new.university_id, 'reserva_completada', new.id, null, v_key);
      perform public.push_notification(v_tutor_user, new.university_id, 'reserva_completada', new.id, null, v_key);
    else
      null;
  end case;
  return null;
end;
$$;

revoke all on function public.notify_booking_event() from public, anon, authenticated;

create trigger bookings_notify
  after insert or update of status on public.bookings
  for each row execute function public.notify_booking_event();

-- ---------------------------------------------------------------------------
-- Incidencias
-- ---------------------------------------------------------------------------
create or replace function public.notify_incident_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_student    uuid;
  v_tutor_user uuid;
  v_key        text := 'incident:' || new.id || ':' || new.status;
  v_admin      uuid;
begin
  if tg_op = 'UPDATE' and new.status is not distinct from old.status then
    return null;
  end if;
  select b.student_id, tp.user_id into v_student, v_tutor_user
  from public.bookings b join public.tutor_profiles tp on tp.id = b.tutor_profile_id
  where b.id = new.booking_id;

  if tg_op = 'INSERT' then
    -- A la otra parte y a los administradores de la universidad.
    perform public.push_notification(
      case when new.reported_by = v_student then v_tutor_user else v_student end,
      new.university_id, 'incidencia_reportada', new.booking_id, new.id, v_key);
    for v_admin in
      select p.id from public.profiles p
      where p.university_id = new.university_id and p.role = 'administrador'
    loop
      perform public.push_notification(v_admin, new.university_id, 'incidencia_reportada',
                                       new.booking_id, new.id, v_key);
    end loop;
  else
    perform public.push_notification(v_student, new.university_id, 'incidencia_actualizada', new.booking_id, new.id, v_key);
    perform public.push_notification(v_tutor_user, new.university_id, 'incidencia_actualizada', new.booking_id, new.id, v_key);
  end if;
  return null;
end;
$$;

revoke all on function public.notify_incident_event() from public, anon, authenticated;

create trigger booking_incidents_notify
  after insert or update of status on public.booking_incidents
  for each row execute function public.notify_incident_event();

-- ---------------------------------------------------------------------------
-- Supabase Realtime (la publicación existe en Supabase).
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.notifications;
  end if;
end;
$$;

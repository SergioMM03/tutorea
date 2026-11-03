-- Tutorea · Fase 14.9 · 20 incidencias de reservas
--
-- Estudiante o tutor reportan un problema de una reserva aceptada, desde que se
-- acepta hasta 7 días después de la hora de fin. Mientras haya una incidencia
-- abierta ('pendiente_revision' o 'en_investigacion') la reserva no puede
-- completarse ni calificarse; las confirmaciones ya hechas se conservan.
--
-- La gestiona el administrador de la universidad de la reserva:
--   pendiente_revision → en_investigacion | resuelta | desestimada
--   en_investigacion   → resuelta | desestimada
--   resuelta, desestimada: finales.
-- Resolver o desestimar NO cambia la reserva, no crea calificaciones ni sanciona.
--
-- Historial: booking_incident_events guarda el reporte, cada cambio de estado y
-- las notas internas del administrador (internal = true, solo las ve él). Nada
-- se borra. La app solo LEE; escribir es exclusivo de las funciones de abajo.
--
-- Códigos de error (la app los traduce a mensajes fijos):
--   TU009 reserva no encontrada para esta cuenta
--   TU030 la reserva no está aceptada (ni por confirmar ni completada)
--   TU031 pasaron más de 7 días desde el fin de la sesión
--   TU032 ya tienes una incidencia abierta para esta reserva
--   TU033 categoría o descripción no válidas
--   TU034 incidencia no encontrada (o de otra universidad)
--   TU035 transición de incidencia no permitida
--   TU036 falta la nota o la resolución
--   42501 sin sesión / no es administrador

-- ---------------------------------------------------------------------------
-- Tablas
-- ---------------------------------------------------------------------------
create table public.booking_incidents (
  id               uuid primary key default gen_random_uuid(),
  booking_id       uuid not null,
  university_id    uuid not null,
  reported_by      uuid not null,
  reporter_party   text not null check (reporter_party in ('estudiante', 'tutor')),
  category         text not null check (category in (
                     'inasistencia', 'impuntualidad', 'conducta', 'calidad', 'tecnico', 'otro')),
  description      text not null check (length(btrim(description)) between 10 and 2000),
  status           public.incident_status not null default 'pendiente_revision',
  resolution_note  text check (resolution_note is null or length(resolution_note) <= 2000),
  resolved_by      uuid,
  resolved_at      timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint booking_incidents_id_university_key unique (id, university_id),
  constraint booking_incidents_booking_fk foreign key (booking_id, university_id)
    references public.bookings (id, university_id) on delete restrict,
  constraint booking_incidents_reporter_fk foreign key (reported_by, university_id)
    references public.profiles (id, university_id) on delete restrict,
  constraint booking_incidents_resolver_fk foreign key (resolved_by, university_id)
    references public.profiles (id, university_id) on delete restrict,
  constraint booking_incidents_final_check check (
    (status in ('resuelta', 'desestimada')) = (resolved_at is not null)
    and (resolved_at is null) = (resolved_by is null)
  )
);

-- Una incidencia abierta por persona y reserva (las dos partes pueden reportar).
create unique index booking_incidents_one_open_idx
  on public.booking_incidents (booking_id, reported_by)
  where status in ('pendiente_revision', 'en_investigacion');

create index booking_incidents_booking_idx on public.booking_incidents (booking_id);
create index booking_incidents_university_status_idx on public.booking_incidents (university_id, status, created_at);

alter table public.booking_incidents enable row level security;

create trigger booking_incidents_set_updated_at
  before update on public.booking_incidents
  for each row execute function public.set_updated_at();

create table public.booking_incident_events (
  id             uuid primary key default gen_random_uuid(),
  incident_id    uuid not null,
  university_id  uuid not null,
  event          text not null check (event in ('reportada', 'estado', 'nota')),
  from_status    public.incident_status,
  to_status      public.incident_status,
  note           text check (note is null or length(note) <= 2000),
  internal       boolean not null default false,
  actor_id       uuid not null,
  created_at     timestamptz not null default now(),
  constraint booking_incident_events_incident_fk foreign key (incident_id, university_id)
    references public.booking_incidents (id, university_id) on delete restrict,
  constraint booking_incident_events_actor_fk foreign key (actor_id, university_id)
    references public.profiles (id, university_id) on delete restrict,
  constraint booking_incident_events_shape_check check (
    (event = 'estado') = (to_status is not null)
    and (event <> 'nota' or (note is not null and internal))
  )
);

create index booking_incident_events_incident_idx on public.booking_incident_events (incident_id, created_at);

alter table public.booking_incident_events enable row level security;

create trigger booking_incident_events_history
  before update or delete on public.booking_incident_events
  for each row execute function public.prevent_history_changes();

-- ---------------------------------------------------------------------------
-- Guarda de incidencias: sin borrados; lo reportado no cambia; solo
-- transiciones válidas; los datos de cierre solo se escriben al cerrar.
-- ---------------------------------------------------------------------------
create or replace function public.guard_incident_changes()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if public.is_privileged_session() then return old; end if;
    raise exception 'Las incidencias no se eliminan.' using errcode = '42501';
  end if;

  if new.id is distinct from old.id
     or new.booking_id is distinct from old.booking_id
     or new.university_id is distinct from old.university_id
     or new.reported_by is distinct from old.reported_by
     or new.reporter_party is distinct from old.reporter_party
     or new.category is distinct from old.category
     or new.description is distinct from old.description
     or new.created_at is distinct from old.created_at then
    raise exception 'Lo reportado en una incidencia no se modifica.' using errcode = '42501';
  end if;

  if new.status is distinct from old.status then
    if not (
      (old.status = 'pendiente_revision' and new.status in ('en_investigacion', 'resuelta', 'desestimada'))
      or (old.status = 'en_investigacion' and new.status in ('resuelta', 'desestimada'))
    ) then
      raise exception 'Una incidencia % no puede pasar a %.', old.status, new.status using errcode = 'TU035';
    end if;
  end if;

  if (new.resolution_note, new.resolved_by, new.resolved_at)
     is distinct from (old.resolution_note, old.resolved_by, old.resolved_at)
     and not (old.status in ('pendiente_revision', 'en_investigacion')
              and new.status in ('resuelta', 'desestimada')) then
    raise exception 'Los datos de cierre de una incidencia no se modifican.' using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function public.guard_incident_changes() from public, anon, authenticated;

create trigger booking_incidents_guard
  before update or delete on public.booking_incidents
  for each row execute function public.guard_incident_changes();

-- ---------------------------------------------------------------------------
-- Ayudantes (SECURITY DEFINER, solo sobre auth.uid() o sobre una reserva).
-- ---------------------------------------------------------------------------
-- ¿La reserva tiene alguna incidencia abierta?
create or replace function public.booking_has_open_incident(target_booking_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.booking_incidents i
    where i.booking_id = target_booking_id
      and i.status in ('pendiente_revision', 'en_investigacion')
  );
$$;

-- ¿La reserva tiene incidencias? (el administrador ve solo esas reservas)
create or replace function public.booking_has_incident(target_booking_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.booking_incidents i where i.booking_id = target_booking_id);
$$;

-- Parte de la reserva de una incidencia para la cuenta con sesión, o null.
create or replace function public.incident_party(target_incident_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select public.booking_party(i.booking_id)
  from public.booking_incidents i
  where i.id = target_incident_id;
$$;

revoke all on function public.booking_has_open_incident(uuid) from public, anon;
revoke all on function public.booking_has_incident(uuid) from public, anon;
revoke all on function public.incident_party(uuid) from public, anon;
grant execute on function public.booking_has_open_incident(uuid) to authenticated;
grant execute on function public.booking_has_incident(uuid) to authenticated;
grant execute on function public.incident_party(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Permisos y RLS: solo lectura.
-- ---------------------------------------------------------------------------
revoke all on table public.booking_incidents from public, anon, authenticated;
revoke all on table public.booking_incident_events from public, anon, authenticated;
grant select on table public.booking_incidents to authenticated;
grant select on table public.booking_incident_events to authenticated;

-- Las partes ven las incidencias de SUS reservas (las propias y las de la otra parte).
create policy booking_incidents_select_participants
  on public.booking_incidents for select
  to authenticated
  using (
    university_id = (select public.current_university_id())
    and public.booking_party(booking_id) is not null
  );

create policy booking_incidents_select_admin
  on public.booking_incidents for select
  to authenticated
  using (public.is_admin_of(university_id));

-- Historial: las partes ven el reporte y los cambios de estado; las notas
-- internas solo el administrador de esa universidad.
create policy booking_incident_events_select_participants
  on public.booking_incident_events for select
  to authenticated
  using (
    not internal
    and university_id = (select public.current_university_id())
    and public.incident_party(incident_id) is not null
  );

create policy booking_incident_events_select_admin
  on public.booking_incident_events for select
  to authenticated
  using (public.is_admin_of(university_id));

-- El administrador ve las reservas de su universidad que tienen incidencias
-- (contexto para revisarlas). Se suma a la política de las partes (migración 17).
create policy bookings_select_admin_with_incident
  on public.bookings for select
  to authenticated
  using (public.is_admin_of(university_id) and public.booking_has_incident(id));

-- ---------------------------------------------------------------------------
-- Reportar (estudiante o tutor de la reserva)
-- ---------------------------------------------------------------------------
create or replace function public.report_incident(
  p_booking_id  uuid,
  p_category    text,
  p_description text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_booking public.bookings%rowtype;
  v_party   text;
  v_text    text := btrim(coalesce(p_description, ''));
  v_id      uuid;
begin
  if v_uid is null then
    raise exception 'Inicia sesión para reportar una incidencia.' using errcode = '42501';
  end if;

  -- Misma fila que bloquean confirm_booking y submit_review: un reporte y la
  -- confirmación final no se cruzan.
  select * into v_booking from public.bookings b where b.id = p_booking_id for update;
  v_party := case
    when not found then null
    else public.booking_party(p_booking_id)
  end;
  if v_party is null then
    raise exception 'No encontramos esa reserva entre las tuyas.' using errcode = 'TU009';
  end if;

  if v_booking.status not in ('aceptada', 'pendiente_confirmacion', 'completada') then
    raise exception 'Solo se reportan incidencias de reservas aceptadas.' using errcode = 'TU030';
  end if;
  if now() > v_booking.ends_at + interval '7 days' then
    raise exception 'Pasaron más de 7 días desde el fin de la sesión.' using errcode = 'TU031';
  end if;
  if p_category is null or p_category not in (
       'inasistencia', 'impuntualidad', 'conducta', 'calidad', 'tecnico', 'otro')
     or length(v_text) < 10 or length(v_text) > 2000 then
    raise exception 'Elige una categoría y describe el problema (10 a 2000 caracteres).' using errcode = 'TU033';
  end if;
  if exists (
    select 1 from public.booking_incidents i
    where i.booking_id = p_booking_id and i.reported_by = v_uid
      and i.status in ('pendiente_revision', 'en_investigacion')
  ) then
    raise exception 'Ya tienes una incidencia abierta para esta reserva.' using errcode = 'TU032';
  end if;

  insert into public.booking_incidents (booking_id, university_id, reported_by, reporter_party, category, description)
  values (p_booking_id, v_booking.university_id, v_uid, v_party, p_category, v_text)
  returning id into v_id;

  insert into public.booking_incident_events (incident_id, university_id, event, to_status, actor_id)
  values (v_id, v_booking.university_id, 'reportada', null, v_uid);

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Gestión administrativa (para el futuro panel; ADMIN 1–3).
-- Solo el administrador de la universidad de la incidencia. Para cualquier
-- otra cuenta la incidencia "no existe" (TU034): no se revela nada.
-- ---------------------------------------------------------------------------
create or replace function public.admin_change_incident(
  p_incident_id uuid,
  p_status      public.incident_status,
  p_note        text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_incident public.booking_incidents%rowtype;
  v_note     text := nullif(btrim(coalesce(p_note, '')), '');
  v_final    boolean := p_status in ('resuelta', 'desestimada');
begin
  if v_uid is null then
    raise exception 'Inicia sesión.' using errcode = '42501';
  end if;
  select * into v_incident from public.booking_incidents i where i.id = p_incident_id for update;
  if not found or not public.is_admin_of(v_incident.university_id) then
    raise exception 'No encontramos esa incidencia.' using errcode = 'TU034';
  end if;
  if p_status is null or p_status = 'pendiente_revision' or not (
    (v_incident.status = 'pendiente_revision' and p_status in ('en_investigacion', 'resuelta', 'desestimada'))
    or (v_incident.status = 'en_investigacion' and p_status in ('resuelta', 'desestimada'))
  ) then
    raise exception 'Una incidencia % no puede pasar a %.', v_incident.status, p_status using errcode = 'TU035';
  end if;
  if v_final and (v_note is null or length(v_note) < 5) then
    raise exception 'Escribe la resolución (mínimo 5 caracteres).' using errcode = 'TU036';
  end if;
  if v_note is not null and length(v_note) > 2000 then
    raise exception 'La nota es demasiado larga.' using errcode = 'TU036';
  end if;

  update public.booking_incidents
  set status = p_status,
      resolution_note = case when v_final then v_note else resolution_note end,
      resolved_by     = case when v_final then v_uid else resolved_by end,
      resolved_at     = case when v_final then now() else resolved_at end
  where id = p_incident_id;

  -- Cambio de estado visible para las partes; en una investigación la nota
  -- queda interna (la resolución final, en cambio, la ven las partes).
  insert into public.booking_incident_events
    (incident_id, university_id, event, from_status, to_status, note, internal, actor_id)
  values
    (p_incident_id, v_incident.university_id, 'estado', v_incident.status, p_status,
     case when v_final then v_note end, false, v_uid);
  if not v_final and v_note is not null then
    insert into public.booking_incident_events
      (incident_id, university_id, event, note, internal, actor_id)
    values (p_incident_id, v_incident.university_id, 'nota', v_note, true, v_uid);
  end if;
end;
$$;

revoke all on function public.admin_change_incident(uuid, public.incident_status, text)
  from public, anon, authenticated;

create or replace function public.admin_start_incident_investigation(p_incident_id uuid, p_note text default null)
returns void
language sql
security definer
set search_path = ''
as $$ select public.admin_change_incident(p_incident_id, 'en_investigacion', p_note); $$;

create or replace function public.admin_resolve_incident(p_incident_id uuid, p_resolution text)
returns void
language sql
security definer
set search_path = ''
as $$ select public.admin_change_incident(p_incident_id, 'resuelta', p_resolution); $$;

create or replace function public.admin_dismiss_incident(p_incident_id uuid, p_resolution text)
returns void
language sql
security definer
set search_path = ''
as $$ select public.admin_change_incident(p_incident_id, 'desestimada', p_resolution); $$;

-- Nota interna (no cambia el estado; se puede agregar también a una cerrada).
create or replace function public.admin_add_incident_note(p_incident_id uuid, p_note text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_incident public.booking_incidents%rowtype;
  v_note     text := nullif(btrim(coalesce(p_note, '')), '');
begin
  if v_uid is null then
    raise exception 'Inicia sesión.' using errcode = '42501';
  end if;
  select * into v_incident from public.booking_incidents i where i.id = p_incident_id for share;
  if not found or not public.is_admin_of(v_incident.university_id) then
    raise exception 'No encontramos esa incidencia.' using errcode = 'TU034';
  end if;
  if v_note is null or length(v_note) > 2000 then
    raise exception 'Escribe la nota (máximo 2000 caracteres).' using errcode = 'TU036';
  end if;
  insert into public.booking_incident_events (incident_id, university_id, event, note, internal, actor_id)
  values (p_incident_id, v_incident.university_id, 'nota', v_note, true, v_uid);
end;
$$;

revoke all on function public.report_incident(uuid, text, text) from public, anon;
revoke all on function public.admin_start_incident_investigation(uuid, text) from public, anon;
revoke all on function public.admin_resolve_incident(uuid, text) from public, anon;
revoke all on function public.admin_dismiss_incident(uuid, text) from public, anon;
revoke all on function public.admin_add_incident_note(uuid, text) from public, anon;

grant execute on function public.report_incident(uuid, text, text) to authenticated;
grant execute on function public.admin_start_incident_investigation(uuid, text) to authenticated;
grant execute on function public.admin_resolve_incident(uuid, text) to authenticated;
grant execute on function public.admin_dismiss_incident(uuid, text) to authenticated;
grant execute on function public.admin_add_incident_note(uuid, text) to authenticated;

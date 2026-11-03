-- Tutorea · Fase 14.8 · 18 funciones de reservas
--
-- request_booking, accept_booking, reject_booking y cancel_booking son la ÚNICA
-- forma de escribir en public.bookings (la app no tiene permisos de escritura).
--
-- SECURITY DEFINER porque la tabla no da permisos de escritura a authenticated.
-- Por eso cada función:
--   - fija search_path = '' y usa nombres completos;
--   - toma la identidad SOLO de auth.uid() y la universidad del perfil de esa
--     cuenta (nunca de parámetros de la app);
--   - comprueba que quien llama es la parte que corresponde;
--   - bloquea las filas que valida (FOR UPDATE / FOR SHARE) para que dos
--     peticiones simultáneas no confirmen sesiones que se cruzan. La restricción
--     EXCLUDE de la migración 17 es la garantía final (error 23P01).
-- La guarda bookings_guard (migración 17) sigue aplicando: transiciones y
-- campos protegidos.
--
-- Códigos de error propios (la app los traduce a mensajes fijos):
--   TU001 tutor no disponible          TU008 el tutor ya tiene una sesión confirmada
--   TU002 autorreserva                 TU009 reserva no encontrada para esta cuenta
--   TU003 materia no ofrecida          TU010 transición no permitida
--   TU004 modalidad no ofrecida        TU011 falta el motivo de cancelación
--   TU005 duración no válida           TU012 la sesión ya empezó
--   TU006 fecha pasada                 TU013 el tutor rechaza (no cancela) pendientes
--   TU007 fuera de la disponibilidad   TU014 el estudiante ya tiene una sesión confirmada
--   TU015 al aceptar, la sesión ya no está dentro de la disponibilidad actual del tutor
--   42501 sin sesión / sin perfil / cuenta administradora
--   23505 solicitud duplicada (índice bookings_no_duplicate_request_idx)

-- ---------------------------------------------------------------------------
-- Ayudante interno: ¿hay una sesión confirmada que se cruce?
-- ---------------------------------------------------------------------------
create or replace function public.booking_overlaps(
  p_tutor_profile_id uuid,
  p_student_id       uuid,
  p_starts_at        timestamptz,
  p_ends_at          timestamptz,
  p_exclude_id       uuid
)
returns text   -- 'tutor', 'student' o null
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when exists (
      select 1 from public.bookings b
      where b.tutor_profile_id = p_tutor_profile_id
        and b.id is distinct from p_exclude_id
        and b.status in ('aceptada', 'pendiente_confirmacion', 'completada')
        and tstzrange(b.starts_at, b.ends_at) && tstzrange(p_starts_at, p_ends_at)
    ) then 'tutor'
    when exists (
      select 1 from public.bookings b
      where b.student_id = p_student_id
        and b.id is distinct from p_exclude_id
        and b.status in ('aceptada', 'pendiente_confirmacion', 'completada')
        and tstzrange(b.starts_at, b.ends_at) && tstzrange(p_starts_at, p_ends_at)
    ) then 'student'
  end;
$$;

revoke all on function public.booking_overlaps(uuid, uuid, timestamptz, timestamptz, uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Ayudante interno: ¿la sesión completa cabe en la disponibilidad semanal ACTUAL?
-- La disponibilidad está en hora local de la universidad; starts_at es UTC. La
-- conversión se hace aquí con tutorea_time_zone() ('America/El_Salvador').
-- La sesión debe caber en UN bloque: [inicio, inicio + duración] dentro de
-- [start_minute, end_minute] del mismo día (no cruza la medianoche porque
-- end_minute <= 1440). Se exige un inicio en minuto exacto.
-- La usan request_booking y accept_booking (misma regla en los dos momentos).
-- ---------------------------------------------------------------------------
create or replace function public.booking_fits_availability(
  p_tutor_profile_id uuid,
  p_starts_at        timestamptz,
  p_duration_minutes integer
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_local timestamp := p_starts_at at time zone public.tutorea_time_zone();
  v_dow   integer   := extract(isodow from v_local)::integer;   -- 1 = lunes
  v_from  integer   := extract(hour from v_local)::integer * 60 + extract(minute from v_local)::integer;
begin
  if p_starts_at is null or p_duration_minutes is null
     or date_trunc('minute', p_starts_at) <> p_starts_at then
    return false;
  end if;
  return exists (
    select 1 from public.availability_slots a
    where a.tutor_profile_id = p_tutor_profile_id
      and a.weekday = v_dow
      and a.start_minute <= v_from
      and a.end_minute >= v_from + p_duration_minutes
  );
end;
$$;

revoke all on function public.booking_fits_availability(uuid, timestamptz, integer)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Solicitar
-- ---------------------------------------------------------------------------
create or replace function public.request_booking(
  p_tutor_profile_id uuid,
  p_subject_id       uuid,
  p_modality         public.booking_modality,
  p_starts_at        timestamptz,
  p_duration_minutes integer,
  p_topic            text default null,
  p_location         text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_student public.profiles%rowtype;
  v_tutor   public.tutor_profiles%rowtype;
  v_ends_at timestamptz;
  v_overlap text;
  v_id      uuid;
begin
  if v_uid is null then
    raise exception 'Inicia sesión para solicitar una tutoría.' using errcode = '42501';
  end if;
  select * into v_student from public.profiles p where p.id = v_uid;
  if not found then
    raise exception 'Tu cuenta no tiene perfil.' using errcode = '42501';
  end if;
  if v_student.role = 'administrador' then
    raise exception 'Una cuenta administradora no solicita tutorías.' using errcode = '42501';
  end if;

  if p_duration_minutes is null or p_duration_minutes not in (60, 90, 120) then
    raise exception 'La duración debe ser de 60, 90 o 120 minutos.' using errcode = 'TU005';
  end if;
  if p_starts_at is null or p_starts_at <= now() then
    raise exception 'Elige una fecha y hora futuras.' using errcode = 'TU006';
  end if;
  v_ends_at := p_starts_at + p_duration_minutes * interval '1 minute';

  -- Tutor de la misma universidad y activo (FOR SHARE: no cambia mientras se valida).
  select * into v_tutor
  from public.tutor_profiles tp
  where tp.id = p_tutor_profile_id and tp.university_id = v_student.university_id
  for share;
  if not found or not v_tutor.is_active then
    raise exception 'Este tutor no está disponible.' using errcode = 'TU001';
  end if;
  if v_tutor.user_id = v_uid then
    raise exception 'No puedes solicitarte una tutoría a ti mismo.' using errcode = 'TU002';
  end if;

  if not exists (
    select 1 from public.tutor_subjects ts
    join public.subjects s on s.id = ts.subject_id and s.university_id = v_student.university_id
    where ts.tutor_profile_id = v_tutor.id and ts.subject_id = p_subject_id
  ) then
    raise exception 'El tutor no imparte esa materia.' using errcode = 'TU003';
  end if;

  if p_modality is null
     or (p_modality = 'presencial' and not v_tutor.offers_in_person)
     or (p_modality = 'virtual' and not v_tutor.offers_virtual) then
    raise exception 'El tutor no ofrece esa modalidad.' using errcode = 'TU004';
  end if;

  -- La sesión completa debe caber en la disponibilidad semanal (hora de El Salvador).
  if not public.booking_fits_availability(v_tutor.id, p_starts_at, p_duration_minutes) then
    raise exception 'El tutor no atiende en ese horario.' using errcode = 'TU007';
  end if;

  v_overlap := public.booking_overlaps(v_tutor.id, v_uid, p_starts_at, v_ends_at, null);
  if v_overlap = 'tutor' then
    raise exception 'El tutor ya tiene una sesión confirmada en ese horario.' using errcode = 'TU008';
  elsif v_overlap = 'student' then
    raise exception 'Ya tienes una sesión confirmada en ese horario.' using errcode = 'TU014';
  end if;

  insert into public.bookings (
    university_id, student_id, tutor_profile_id, subject_id, modality,
    topic, location, starts_at, ends_at, duration_minutes, agreed_price
  ) values (
    v_student.university_id, v_uid, v_tutor.id, p_subject_id, p_modality,
    nullif(trim(coalesce(p_topic, '')), ''), nullif(trim(coalesce(p_location, '')), ''),
    p_starts_at, v_ends_at, p_duration_minutes,
    round(v_tutor.hourly_rate * p_duration_minutes / 60.0, 2)
  )
  returning id into v_id;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Aceptar (solo el dueño del perfil de tutor). Vuelve a validar estado, hora,
-- perfil activo, disponibilidad ACTUAL y cruces, todo en la misma transacción.
-- ---------------------------------------------------------------------------
create or replace function public.accept_booking(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_booking public.bookings%rowtype;
  v_tutor   public.tutor_profiles%rowtype;
  v_overlap text;
begin
  if v_uid is null then
    raise exception 'Inicia sesión.' using errcode = '42501';
  end if;

  -- Bloquear primero el perfil del tutor: las aceptaciones del mismo tutor van en fila.
  select tp.* into v_tutor
  from public.tutor_profiles tp
  join public.bookings b on b.tutor_profile_id = tp.id
  where b.id = p_booking_id and tp.user_id = v_uid
  for update of tp;
  if not found then
    raise exception 'No encontramos esa solicitud entre las tuyas.' using errcode = 'TU009';
  end if;

  select * into v_booking from public.bookings b where b.id = p_booking_id for update;

  if v_booking.status <> 'pendiente' then
    raise exception 'Una solicitud % ya no se puede aceptar.', v_booking.status using errcode = 'TU010';
  end if;
  if v_booking.starts_at <= now() then
    raise exception 'La hora de inicio ya pasó; no se puede aceptar.' using errcode = 'TU012';
  end if;
  if not v_tutor.is_active then
    raise exception 'Tu perfil de tutor está desactivado.' using errcode = 'TU001';
  end if;

  -- La disponibilidad pudo cambiar después de la solicitud: se vuelve a validar con
  -- la ACTUAL. FOR SHARE bloquea los bloques del tutor hasta el final de la
  -- transacción: un cambio simultáneo (save_tutor_profile o un DELETE/UPDATE
  -- directo) espera a que termine la aceptación, o la aceptación espera a que el
  -- cambio termine y entonces valida contra los bloques ya actualizados.
  -- save_tutor_profile, además, actualiza la fila de tutor_profiles bloqueada arriba.
  perform 1 from public.availability_slots a
  where a.tutor_profile_id = v_tutor.id
  for share;
  if not public.booking_fits_availability(v_tutor.id, v_booking.starts_at, v_booking.duration_minutes) then
    raise exception 'Esa sesión ya no está dentro de tu disponibilidad actual.' using errcode = 'TU015';
  end if;

  v_overlap := public.booking_overlaps(v_booking.tutor_profile_id, v_booking.student_id,
                                       v_booking.starts_at, v_booking.ends_at, v_booking.id);
  if v_overlap = 'tutor' then
    raise exception 'Ya aceptaste otra sesión en ese horario.' using errcode = 'TU008';
  elsif v_overlap = 'student' then
    raise exception 'El estudiante ya tiene otra sesión confirmada en ese horario.' using errcode = 'TU014';
  end if;

  update public.bookings
  set status = 'aceptada', responded_at = now()
  where id = p_booking_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Rechazar (solo el dueño del perfil de tutor)
-- ---------------------------------------------------------------------------
create or replace function public.reject_booking(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_booking public.bookings%rowtype;
begin
  if v_uid is null then
    raise exception 'Inicia sesión.' using errcode = '42501';
  end if;

  select b.* into v_booking
  from public.bookings b
  join public.tutor_profiles tp on tp.id = b.tutor_profile_id
  where b.id = p_booking_id and tp.user_id = v_uid
  for update of b;
  if not found then
    raise exception 'No encontramos esa solicitud entre las tuyas.' using errcode = 'TU009';
  end if;
  if v_booking.status <> 'pendiente' then
    raise exception 'Una solicitud % ya no se puede rechazar.', v_booking.status using errcode = 'TU010';
  end if;

  update public.bookings
  set status = 'rechazada', responded_at = now()
  where id = p_booking_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Cancelar
--   pendiente: solo quien la solicitó (el tutor la rechaza).
--   aceptada:  quien la solicitó o el tutor, antes del inicio y con motivo.
-- ---------------------------------------------------------------------------
create or replace function public.cancel_booking(p_booking_id uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid := auth.uid();
  v_booking    public.bookings%rowtype;
  v_tutor_user uuid;
  v_reason     text := nullif(trim(coalesce(p_reason, '')), '');
begin
  if v_uid is null then
    raise exception 'Inicia sesión.' using errcode = '42501';
  end if;

  select b.* into v_booking from public.bookings b where b.id = p_booking_id for update;
  if not found then
    raise exception 'No encontramos esa reserva entre las tuyas.' using errcode = 'TU009';
  end if;
  select tp.user_id into v_tutor_user from public.tutor_profiles tp where tp.id = v_booking.tutor_profile_id;
  if v_booking.student_id <> v_uid and v_tutor_user is distinct from v_uid then
    raise exception 'No encontramos esa reserva entre las tuyas.' using errcode = 'TU009';
  end if;

  if v_booking.status = 'pendiente' then
    if v_booking.student_id <> v_uid then
      raise exception 'Una solicitud pendiente se rechaza; solo quien la envió la cancela.' using errcode = 'TU013';
    end if;
  elsif v_booking.status = 'aceptada' then
    if v_booking.starts_at <= now() then
      raise exception 'La sesión ya empezó; no se puede cancelar.' using errcode = 'TU012';
    end if;
    if v_reason is null or length(v_reason) < 3 then
      raise exception 'Escribe el motivo para cancelar una reserva aceptada.' using errcode = 'TU011';
    end if;
  else
    raise exception 'Una reserva % ya no se puede cancelar.', v_booking.status using errcode = 'TU010';
  end if;

  update public.bookings
  set status = 'cancelada',
      cancelled_by = v_uid,
      cancelled_at = now(),
      cancellation_reason = v_reason
  where id = p_booking_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Permisos: solo authenticated.
-- ---------------------------------------------------------------------------
revoke all on function public.request_booking(uuid, uuid, public.booking_modality, timestamptz, integer, text, text)
  from public, anon;
revoke all on function public.accept_booking(uuid) from public, anon;
revoke all on function public.reject_booking(uuid) from public, anon;
revoke all on function public.cancel_booking(uuid, text) from public, anon;

grant execute on function public.request_booking(uuid, uuid, public.booking_modality, timestamptz, integer, text, text)
  to authenticated;
grant execute on function public.accept_booking(uuid) to authenticated;
grant execute on function public.reject_booking(uuid) to authenticated;
grant execute on function public.cancel_booking(uuid, text) to authenticated;

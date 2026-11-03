-- Tutorea · Fase 14.9 · 21 confirm_booking
--
-- Confirmación de que la sesión se realizó, por cada parte:
--   - solo el estudiante o el tutor de la reserva (auth.uid());
--   - la reserva debe estar 'aceptada' (primera) o 'pendiente_confirmacion'
--     (segunda) y su hora de fin ya debe haber pasado;
--   - cada parte confirma una sola vez;
--   - primera confirmación → 'pendiente_confirmacion';
--   - segunda confirmación → 'completada', solo si NO hay incidencias abiertas.
--     Con una incidencia abierta la segunda confirmación se rechaza (TU022) y no
--     se guarda: las confirmaciones ya hechas se conservan y, cuando el
--     administrador resuelve o desestima la incidencia, quien faltaba vuelve a
--     confirmar y la reserva se completa.
-- Nunca se completa una reserva por tiempo.
--
-- Concurrencia: bloquea la fila de la reserva (FOR UPDATE). report_incident y
-- submit_review bloquean la misma fila, así un reporte y la confirmación final
-- no se cruzan: o el reporte llega antes y bloquea la finalización, o la
-- reserva ya está completada cuando se reporta (y entonces bloquea la reseña).
--
-- Códigos de error:
--   TU009 reserva no encontrada para esta cuenta
--   TU020 la sesión todavía no termina
--   TU021 ya confirmaste esta sesión
--   TU022 hay una incidencia abierta: no se puede completar todavía
--   TU023 la reserva no está aceptada (ni pendiente de confirmación)

create or replace function public.confirm_booking(p_booking_id uuid)
returns public.booking_status
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_booking public.bookings%rowtype;
  v_party   text;
  v_other   boolean;
  v_status  public.booking_status;
begin
  if v_uid is null then
    raise exception 'Inicia sesión para confirmar la sesión.' using errcode = '42501';
  end if;

  select * into v_booking from public.bookings b where b.id = p_booking_id for update;
  v_party := case when found then public.booking_party(p_booking_id) end;
  if v_party is null then
    raise exception 'No encontramos esa reserva entre las tuyas.' using errcode = 'TU009';
  end if;

  if v_booking.status not in ('aceptada', 'pendiente_confirmacion') then
    raise exception 'Solo se confirman sesiones aceptadas que ya terminaron.' using errcode = 'TU023';
  end if;
  if now() < v_booking.ends_at then
    raise exception 'La sesión todavía no termina; podrás confirmarla al finalizar.' using errcode = 'TU020';
  end if;
  if exists (
    select 1 from public.booking_confirmations c
    where c.booking_id = p_booking_id and c.party = v_party
  ) then
    raise exception 'Ya confirmaste esta sesión.' using errcode = 'TU021';
  end if;

  v_other := exists (
    select 1 from public.booking_confirmations c
    where c.booking_id = p_booking_id and c.party <> v_party
  );

  if v_other then
    -- Segunda confirmación: completa la reserva, salvo incidencia abierta.
    if public.booking_has_open_incident(p_booking_id) then
      raise exception 'Hay una incidencia abierta; la sesión se completará cuando se resuelva.'
        using errcode = 'TU022';
    end if;
    v_status := 'completada';
  else
    v_status := 'pendiente_confirmacion';
  end if;

  -- Primero la confirmación y después el estado: el aviso de "falta tu
  -- confirmación" (migración 23) ya ve quién confirmó.
  insert into public.booking_confirmations (booking_id, university_id, party, user_id)
  values (p_booking_id, v_booking.university_id, v_party, v_uid);

  if v_booking.status <> v_status then
    update public.bookings set status = v_status where id = p_booking_id;
  end if;

  return v_status;
end;
$$;

revoke all on function public.confirm_booking(uuid) from public, anon;
grant execute on function public.confirm_booking(uuid) to authenticated;

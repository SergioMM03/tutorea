-- Tutorea · Fase 14.9 · notificaciones (migración 23)
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(34);

-- ---------------------------------------------------------------------------
-- Datos comunes de las pruebas de la Fase 14.9 (todo se deshace con rollback)
--   Universidad A: estudiante S, otro estudiante O, tutor T, segundo tutor T2,
--                  administrador AD.
--   Universidad C: estudiante SC, tutor TC y administrador ADC.
-- ---------------------------------------------------------------------------
create function pg_temp.login(p uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;
create function pg_temp.logout() returns void language plpgsql as $$
begin
  perform set_config('role', 'none', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

insert into public.universities (id, slug, name, short_name, country) values
  ('a9000000-0000-0000-0000-000000000001', 'f9-a', 'Universidad F9 A', 'FA', 'El Salvador'),
  ('c9000000-0000-0000-0000-000000000001', 'f9-c', 'Universidad F9 C', 'FC', 'El Salvador');
insert into public.careers (id, university_id, slug, name) values
  ('a9000000-0000-0000-0000-0000000000c1', 'a9000000-0000-0000-0000-000000000001', 'fa-eco', 'Economía FA'),
  ('c9000000-0000-0000-0000-0000000000c1', 'c9000000-0000-0000-0000-000000000001', 'fc-eco', 'Economía FC');
insert into public.subjects (id, university_id, career_id, slug, name, category) values
  ('a9000000-0000-0000-0000-00000000005a', 'a9000000-0000-0000-0000-000000000001', null, 'fa-mat', 'Matemáticas FA', 'Matemáticas'),
  ('c9000000-0000-0000-0000-00000000005a', 'c9000000-0000-0000-0000-000000000001', null, 'fc-mat', 'Matemáticas FC', 'Matemáticas');

insert into auth.users (id, email, raw_user_meta_data)
select v.id::uuid, v.email, jsonb_build_object(
  'university_id', v.uni, 'career_id', v.career, 'full_name', v.name, 'academic_year', 2, 'role', v.role)
from (values
  ('a9000000-0000-0000-0000-0000000000e1', 's.f9@test.local',  'a9000000-0000-0000-0000-000000000001', 'a9000000-0000-0000-0000-0000000000c1', 'Estudiante S', 'estudiante'),
  ('a9000000-0000-0000-0000-0000000000e9', 'o.f9@test.local',  'a9000000-0000-0000-0000-000000000001', 'a9000000-0000-0000-0000-0000000000c1', 'Otro O',       'estudiante'),
  ('a9000000-0000-0000-0000-0000000000f1', 't.f9@test.local',  'a9000000-0000-0000-0000-000000000001', 'a9000000-0000-0000-0000-0000000000c1', 'Tutor T',      'tutor'),
  ('a9000000-0000-0000-0000-0000000000f2', 't2.f9@test.local', 'a9000000-0000-0000-0000-000000000001', 'a9000000-0000-0000-0000-0000000000c1', 'Tutor T2',     'tutor'),
  ('a9000000-0000-0000-0000-0000000000ad', 'ad.f9@test.local', 'a9000000-0000-0000-0000-000000000001', 'a9000000-0000-0000-0000-0000000000c1', 'Admin A',      'estudiante'),
  ('c9000000-0000-0000-0000-0000000000e1', 'sc.f9@test.local', 'c9000000-0000-0000-0000-000000000001', 'c9000000-0000-0000-0000-0000000000c1', 'Estudiante C', 'estudiante'),
  ('c9000000-0000-0000-0000-0000000000f1', 'tc.f9@test.local', 'c9000000-0000-0000-0000-000000000001', 'c9000000-0000-0000-0000-0000000000c1', 'Tutor C',      'tutor'),
  ('c9000000-0000-0000-0000-0000000000ad', 'adc.f9@test.local','c9000000-0000-0000-0000-000000000001', 'c9000000-0000-0000-0000-0000000000c1', 'Admin C',      'estudiante')
) as v(id, email, uni, career, name, role);
select public.assign_admin('a9000000-0000-0000-0000-0000000000ad', 'Prueba pgTAP');
select public.assign_admin('c9000000-0000-0000-0000-0000000000ad', 'Prueba pgTAP');

-- Perfiles de tutor (todo el día, todos los días), creados por cada tutor.
create table public._ids (k text primary key, id uuid);
grant select, insert on public._ids to authenticated;
create function pg_temp.tutor(p_user uuid, p_subject uuid) returns void language plpgsql as $$
begin
  perform pg_temp.login(p_user);
  perform public.save_tutor_profile('Tutor de prueba', 10, true, true, true, array[p_subject]::uuid[],
    (select jsonb_agg(jsonb_build_object('weekday', d, 'start_minute', 0, 'end_minute', 1440))
     from generate_series(1, 7) d));
  perform pg_temp.logout();
end $$;
select pg_temp.tutor('a9000000-0000-0000-0000-0000000000f1', 'a9000000-0000-0000-0000-00000000005a');
select pg_temp.tutor('a9000000-0000-0000-0000-0000000000f2', 'a9000000-0000-0000-0000-00000000005a');
select pg_temp.tutor('c9000000-0000-0000-0000-0000000000f1', 'c9000000-0000-0000-0000-00000000005a');

-- Reserva creada por el equipo (sesión privilegiada) con el estado y la hora
-- indicados: permite tener sesiones que ya terminaron.
create function pg_temp.booking(p_key text, p_student uuid, p_tutor_user uuid, p_start timestamptz,
                                p_status public.booking_status) returns uuid language plpgsql as $$
declare v_id uuid;
begin
  insert into public.bookings (university_id, student_id, tutor_profile_id, subject_id, modality,
                               starts_at, ends_at, duration_minutes, agreed_price, status,
                               responded_at, cancelled_by, cancelled_at, cancellation_reason)
  select tp.university_id, p_student, tp.id, ts.subject_id, 'presencial',
         p_start, p_start + interval '1 hour', 60, 10, p_status,
         case when p_status <> 'pendiente' then now() end,
         case when p_status = 'cancelada' then p_student end,
         case when p_status = 'cancelada' then now() end,
         case when p_status = 'cancelada' then 'Prueba' end
  from public.tutor_profiles tp join public.tutor_subjects ts on ts.tutor_profile_id = tp.id
  where tp.user_id = p_tutor_user
  returning id into v_id;
  insert into public._ids values (p_key, v_id);
  return v_id;
end $$;
create function pg_temp.id(p_key text) returns uuid language sql as $$ select id from public._ids where k = p_key $$;

-- Lunes de la próxima semana a las 10:00 (El Salvador) para solicitudes reales.
create function pg_temp.next_monday(p_hour int) returns timestamptz language sql as $$
  select (date_trunc('week', now() at time zone 'America/El_Salvador') + interval '7 days' + p_hour * interval '1 hour')
         at time zone 'America/El_Salvador'
$$;
create function pg_temp.request(p_student uuid, p_key text, p_hour int) returns void language plpgsql as $$
begin
  perform pg_temp.login(p_student);
  insert into public._ids select p_key, public.request_booking(
    (select id from public.tutor_profiles where user_id = 'a9000000-0000-0000-0000-0000000000f1'),
    'a9000000-0000-0000-0000-00000000005a', 'presencial', pg_temp.next_monday(p_hour), 60);
  perform pg_temp.logout();
end $$;
create function pg_temp.notes(p_user uuid) returns table (type text, booking uuid, incident uuid) language sql as $$
  select n.type::text, n.booking_id, n.incident_id from public.notifications n where n.recipient_id = p_user
$$;

-- Estructura y permisos
select ok((select relrowsecurity from pg_class where oid = 'public.notifications'::regclass), 'RLS en notifications');
select ok(not has_table_privilege('authenticated', 'public.notifications', 'insert'), 'la app no inserta notificaciones');
select ok(not has_table_privilege('authenticated', 'public.notifications', 'update'), 'ni las actualiza directamente');
select ok(not has_table_privilege('authenticated', 'public.notifications', 'delete'), 'ni las borra');
select ok(not has_table_privilege('anon', 'public.notifications', 'select'), 'anon no las lee');
select ok(not has_function_privilege('authenticated',
  'public.push_notification(uuid, uuid, public.notification_type, uuid, uuid, text)', 'execute'),
  'la app no puede crear notificaciones para otros');
select ok(exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'notifications'),
  'las notificaciones se publican por Realtime');

-- ---------- Ciclo de una reserva ----------
select pg_temp.request('a9000000-0000-0000-0000-0000000000e1', 'r1', 10);
select bag_eq($$ select type, booking from pg_temp.notes('a9000000-0000-0000-0000-0000000000f1') $$,
  $$ values ('reserva_solicitada', pg_temp.id('r1')) $$, 'solicitud → al tutor');
select is((select count(*)::int from public.notifications where recipient_id = 'a9000000-0000-0000-0000-0000000000e1'), 0,
  'quien solicita no recibe aviso de su propia solicitud');

select pg_temp.login('a9000000-0000-0000-0000-0000000000f1');
select public.accept_booking(pg_temp.id('r1'));
select pg_temp.logout();
select bag_eq($$ select type, booking from pg_temp.notes('a9000000-0000-0000-0000-0000000000e1') $$,
  $$ values ('reserva_aceptada', pg_temp.id('r1')) $$, 'aceptada → al estudiante');

select pg_temp.request('a9000000-0000-0000-0000-0000000000e9', 'r2', 15);
select pg_temp.login('a9000000-0000-0000-0000-0000000000f1');
select public.reject_booking(pg_temp.id('r2'));
select pg_temp.logout();
select bag_eq($$ select type, booking from pg_temp.notes('a9000000-0000-0000-0000-0000000000e9') $$,
  $$ values ('reserva_rechazada', pg_temp.id('r2')) $$, 'rechazada → al estudiante');

select pg_temp.login('a9000000-0000-0000-0000-0000000000e1');
select public.cancel_booking(pg_temp.id('r1'), 'Ya no necesito la tutoría.');
select pg_temp.logout();
select is((select count(*)::int from public.notifications where type = 'reserva_cancelada'
  and recipient_id = 'a9000000-0000-0000-0000-0000000000f1' and booking_id = pg_temp.id('r1')), 1,
  'cancelada por el estudiante → al tutor');
select is((select count(*)::int from public.notifications where type = 'reserva_cancelada'
  and recipient_id = 'a9000000-0000-0000-0000-0000000000e1'), 0, 'quien cancela no recibe el aviso');

-- Confirmaciones de una sesión que ya terminó (la crea el equipo).
select pg_temp.booking('d1', 'a9000000-0000-0000-0000-0000000000e1', 'a9000000-0000-0000-0000-0000000000f1',
  now() - interval '3 hours', 'aceptada');
select pg_temp.login('a9000000-0000-0000-0000-0000000000e1');
select public.confirm_booking(pg_temp.id('d1'));
select pg_temp.logout();
select is((select count(*)::int from public.notifications where type = 'confirmacion_pendiente'
  and recipient_id = 'a9000000-0000-0000-0000-0000000000f1' and booking_id = pg_temp.id('d1')), 1,
  'primera confirmación → a la parte que falta (tutor)');
select is((select count(*)::int from public.notifications where type = 'confirmacion_pendiente'
  and recipient_id = 'a9000000-0000-0000-0000-0000000000e1'), 0, 'no a quien ya confirmó');
select pg_temp.login('a9000000-0000-0000-0000-0000000000f1');
select public.confirm_booking(pg_temp.id('d1'));
select pg_temp.logout();
select is((select count(*)::int from public.notifications where type = 'reserva_completada' and booking_id = pg_temp.id('d1')), 2,
  'completada → a las dos partes');

-- ---------- Incidencias ----------
select pg_temp.booking('d2', 'a9000000-0000-0000-0000-0000000000e1', 'a9000000-0000-0000-0000-0000000000f1',
  now() - interval '27 hours', 'aceptada');
select pg_temp.login('a9000000-0000-0000-0000-0000000000e1');
insert into public._ids select 'i2', public.report_incident(pg_temp.id('d2'), 'inasistencia', 'El tutor no llegó a la sesión.');
select pg_temp.logout();
select bag_eq($$ select recipient_id from public.notifications where type = 'incidencia_reportada' and incident_id = pg_temp.id('i2') $$,
  $$ values ('a9000000-0000-0000-0000-0000000000f1'::uuid), ('a9000000-0000-0000-0000-0000000000ad'::uuid) $$,
  'reportada → a la otra parte y al administrador de la universidad (no al de otra)');
select pg_temp.login('a9000000-0000-0000-0000-0000000000ad');
select public.admin_start_incident_investigation(pg_temp.id('i2'), 'Revisando.');
select public.admin_add_incident_note(pg_temp.id('i2'), 'Nota interna sin aviso.');
select public.admin_resolve_incident(pg_temp.id('i2'), 'Se repone la sesión.');
select pg_temp.logout();
select is((select count(*)::int from public.notifications where type = 'incidencia_actualizada' and incident_id = pg_temp.id('i2')), 4,
  'cada cambio de estado → a las dos partes (2 cambios × 2), las notas no avisan');

-- ---------- Sin duplicados ----------
select is((select count(*)::int from (select recipient_id, event_key from public.notifications
  group by 1, 2 having count(*) > 1) x), 0, 'ningún hecho se notifica dos veces a la misma persona');
select public.push_notification('a9000000-0000-0000-0000-0000000000f1', 'a9000000-0000-0000-0000-000000000001',
  'reserva_solicitada', pg_temp.id('r1'), null, 'booking:' || pg_temp.id('r1') || ':pendiente');
select is((select count(*)::int from public.notifications where type = 'reserva_solicitada' and booking_id = pg_temp.id('r1')), 1,
  'repetir el mismo hecho no crea otra notificación');

-- ---------- Lectura, aislamiento y RLS ----------
select pg_temp.login('a9000000-0000-0000-0000-0000000000e1');
select is((select count(*)::int from public.notifications), 4,
  'el estudiante solo ve las suyas (aceptada, completada, incidencia actualizada ×2)');
select is((select count(*)::int from public.notifications where read_at is null), 4, 'todas sin leer');
insert into public._ids select 'nS', (select id from public.notifications where type = 'reserva_aceptada');
select is(public.mark_notifications_read(array[pg_temp.id('nS')]), 1, 'marca una como leída');
select is(public.mark_notifications_read(array[pg_temp.id('nS')]), 0, 'marcarla otra vez no cambia nada');
select ok((select read_at is not null from public.notifications where id = pg_temp.id('nS')), 'queda con fecha de lectura');
insert into public._ids select 'nT', (select id from public.notifications where recipient_id = 'a9000000-0000-0000-0000-0000000000f1' limit 1);
select is(pg_temp.id('nT'), null::uuid, 'no puede ver notificaciones del tutor');
select throws_ok($$ insert into public.notifications (recipient_id, university_id, type, booking_id, event_key)
  values ('a9000000-0000-0000-0000-0000000000f1', 'a9000000-0000-0000-0000-000000000001', 'reserva_aceptada',
          pg_temp.id('d1'), 'falsa') $$, '42501', null, 'no inserta notificaciones para otros');
select throws_ok($$ update public.notifications set read_at = null $$, '42501', null, 'no las modifica directamente');
select throws_ok($$ delete from public.notifications $$, '42501', null, 'no las borra');
select is(public.mark_notifications_read(), 3, 'marca todas las demás como leídas');
select pg_temp.logout();

select pg_temp.login('a9000000-0000-0000-0000-0000000000f1');
select is(public.mark_notifications_read(array[pg_temp.id('nS')]), 0, 'no marca como leída una notificación ajena');
select ok((select count(*) from public.notifications where read_at is null) > 0, 'las del tutor siguen sin leer');
select pg_temp.logout();
select pg_temp.login('c9000000-0000-0000-0000-0000000000ad');
select is((select count(*)::int from public.notifications), 0, 'el administrador de otra universidad no recibe nada');
select pg_temp.logout();
select set_config('request.jwt.claims', '', true);
select throws_ok($$ update public.notifications set type = 'reserva_rechazada' where id = pg_temp.id('nS') $$,
  '42501', null, 'una notificación solo puede marcarse como leída (ni el equipo cambia su contenido)');

select * from finish();
rollback;

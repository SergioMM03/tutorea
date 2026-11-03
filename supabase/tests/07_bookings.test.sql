-- Tutorea · Fase 14.8 · reservas (migraciones 17 y 18)
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(59);

-- ---------------------------------------------------------------------------
-- Datos: universidades A y C
-- ---------------------------------------------------------------------------
insert into public.universities (id, slug, name, short_name, country) values
  ('a2000000-0000-0000-0000-000000000001', 'bk-a', 'Universidad Reservas A', 'RA', 'El Salvador'),
  ('c2000000-0000-0000-0000-000000000001', 'bk-c', 'Universidad Reservas C', 'RC', 'El Salvador');
insert into public.careers (id, university_id, slug, name) values
  ('a2000000-0000-0000-0000-0000000000c1', 'a2000000-0000-0000-0000-000000000001', 'ra-eco', 'Economía RA'),
  ('c2000000-0000-0000-0000-0000000000c1', 'c2000000-0000-0000-0000-000000000001', 'rc-eco', 'Economía RC');
insert into public.subjects (id, university_id, career_id, slug, name, category) values
  ('a2000000-0000-0000-0000-00000000005a', 'a2000000-0000-0000-0000-000000000001', null, 'ra-mat', 'Matemáticas RA', 'Matemáticas'),
  ('a2000000-0000-0000-0000-00000000005b', 'a2000000-0000-0000-0000-000000000001', null, 'ra-est', 'Estadística RA', 'Matemáticas'),
  ('a2000000-0000-0000-0000-00000000005c', 'a2000000-0000-0000-0000-000000000001', null, 'ra-mic', 'Micro RA', 'Economía'),
  ('c2000000-0000-0000-0000-00000000005a', 'c2000000-0000-0000-0000-000000000001', null, 'rc-mat', 'Matemáticas RC', 'Matemáticas');

-- Cuentas de A: estudiantes S y S2, tutor T, cuenta doble D (estudiante con perfil de
-- tutor), tutor inactivo I, administrador AD. En C: tutor TC.
insert into auth.users (id, email, raw_user_meta_data)
select v.id::uuid, v.email, jsonb_build_object(
  'university_id', v.uni, 'career_id', v.career, 'full_name', v.name, 'academic_year', 2, 'role', v.role)
from (values
  ('a2000000-0000-0000-0000-0000000000e1', 's.bk@test.local',  'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-0000000000c1', 'Estudiante S',  'estudiante'),
  ('a2000000-0000-0000-0000-0000000000e2', 's2.bk@test.local', 'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-0000000000c1', 'Estudiante S2', 'estudiante'),
  ('a2000000-0000-0000-0000-0000000000f1', 't.bk@test.local',  'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-0000000000c1', 'Tutor T',       'tutor'),
  ('a2000000-0000-0000-0000-0000000000d1', 'd.bk@test.local',  'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-0000000000c1', 'Doble D',       'estudiante'),
  ('a2000000-0000-0000-0000-0000000000f9', 'i.bk@test.local',  'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-0000000000c1', 'Tutor Inactivo', 'tutor'),
  ('a2000000-0000-0000-0000-0000000000ad', 'ad.bk@test.local', 'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-0000000000c1', 'Admin A',       'estudiante'),
  ('c2000000-0000-0000-0000-0000000000f1', 'tc.bk@test.local', 'c2000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-0000000000c1', 'Tutor C',       'tutor')
) as v(id, email, uni, career, name, role);
select public.assign_admin('a2000000-0000-0000-0000-0000000000ad', 'Prueba pgTAP');

-- Fechas en hora de El Salvador (la próxima semana): lunes 07:00, 10:00, 11:00; martes 14:00, 15:00.
create table public._t (k text primary key, v timestamptz);
insert into public._t
select k, (date_trunc('week', now() at time zone 'America/El_Salvador') + interval '7 days' + d) at time zone 'America/El_Salvador'
from (values ('m7', interval '7 hours'), ('m10', interval '10 hours'), ('m11', interval '11 hours'),
             ('t14', interval '1 day 14 hours'), ('t15', interval '1 day 15 hours')) as x(k, d);
insert into public._t values ('past', now() - interval '2 days');
create table public._b (k text primary key, id uuid);
grant select on public._t to authenticated, anon;
grant select, insert on public._b to authenticated;

-- Perfiles de tutor, creados por cada cuenta
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-0000000000f1","role":"authenticated"}', true);
set local role authenticated;
select public.save_tutor_profile('Tutor T', 10, true, false, true,
  array['a2000000-0000-0000-0000-00000000005a','a2000000-0000-0000-0000-00000000005b']::uuid[],
  '[{"weekday":1,"start_minute":480,"end_minute":720},{"weekday":2,"start_minute":840,"end_minute":1080}]');
reset role;
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-0000000000d1","role":"authenticated"}', true);
set local role authenticated;
select public.save_tutor_profile('Doble D', 8, false, true, true,
  array['a2000000-0000-0000-0000-00000000005a']::uuid[], '[{"weekday":1,"start_minute":480,"end_minute":720}]');
reset role;
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-0000000000f9","role":"authenticated"}', true);
set local role authenticated;
select public.save_tutor_profile('Inactivo', 9, true, true, false,
  array['a2000000-0000-0000-0000-00000000005a']::uuid[], '[{"weekday":1,"start_minute":480,"end_minute":720}]');
reset role;
select set_config('request.jwt.claims', '{"sub":"c2000000-0000-0000-0000-0000000000f1","role":"authenticated"}', true);
set local role authenticated;
select public.save_tutor_profile('Tutor C', 9, true, true, true,
  array['c2000000-0000-0000-0000-00000000005a']::uuid[], '[{"weekday":1,"start_minute":480,"end_minute":720}]');
reset role;
select set_config('request.jwt.claims', '', true);
insert into public._b select 'T', id from public.tutor_profiles where user_id = 'a2000000-0000-0000-0000-0000000000f1';
insert into public._b select 'D', id from public.tutor_profiles where user_id = 'a2000000-0000-0000-0000-0000000000d1';
insert into public._b select 'I', id from public.tutor_profiles where user_id = 'a2000000-0000-0000-0000-0000000000f9';
insert into public._b select 'TC', id from public.tutor_profiles where user_id = 'c2000000-0000-0000-0000-0000000000f1';

-- ---------------------------------------------------------------------------
-- Estructura
-- ---------------------------------------------------------------------------
select ok((select relrowsecurity from pg_class where oid = 'public.bookings'::regclass), 'RLS en bookings');
select ok(not has_table_privilege('authenticated', 'public.bookings', 'insert'), 'la app no inserta directamente');
select ok(not has_table_privilege('authenticated', 'public.bookings', 'update'), 'la app no actualiza directamente');
select ok(not has_table_privilege('authenticated', 'public.bookings', 'delete'), 'la app no borra');
select ok(not has_table_privilege('anon', 'public.bookings', 'select'), 'anon no lee reservas');
select ok(not has_function_privilege('anon',
  'public.request_booking(uuid, uuid, public.booking_modality, timestamptz, integer, text, text)', 'execute'),
  'anon no solicita');

-- Sin sesión (rol anon)
set local role anon;
select throws_ok($$ select public.request_booking((select id from public._b where k = 'T'),
  'a2000000-0000-0000-0000-00000000005a', 'presencial', (select v from public._t where k = 'm10'), 60) $$,
  '42501', null, 'un usuario no autenticado no solicita');
reset role;

-- ---------------------------------------------------------------------------
-- Estudiante S solicita
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;

select lives_ok($$ insert into public._b select 'b1', public.request_booking((select id from public._b where k = 'T'),
  'a2000000-0000-0000-0000-00000000005a', 'presencial', (select v from public._t where k = 'm10'), 60, ' Límites ', ' Biblioteca ') $$,
  'solicitud válida');
select results_eq($$ select status::text, agreed_price, student_id, university_id, topic, location, duration_minutes::int
  from public.bookings where id = (select id from public._b where k = 'b1') $$,
  $$ values ('pendiente', 10.00::numeric, 'a2000000-0000-0000-0000-0000000000e1'::uuid,
            'a2000000-0000-0000-0000-000000000001'::uuid, 'Límites', 'Biblioteca', 60) $$,
  'nace pendiente; el servidor fija estudiante, universidad y precio acordado');
select results_eq($$ select ends_at - starts_at from public.bookings where id = (select id from public._b where k = 'b1') $$,
  $$ values (interval '60 minutes') $$, 'ends_at = inicio + duración');
select lives_ok($$ insert into public._b select 'b90', public.request_booking((select id from public._b where k = 'T'),
  'a2000000-0000-0000-0000-00000000005b', 'presencial', (select v from public._t where k = 't15'), 90) $$,
  'solicitud de 90 minutos');
select results_eq($$ select agreed_price from public.bookings where id = (select id from public._b where k = 'b90') $$,
  $$ values (15.00::numeric) $$, 'precio = tarifa × duración');
select throws_ok($$ select public.request_booking((select id from public._b where k = 'T'),
  'a2000000-0000-0000-0000-00000000005a', 'presencial', (select v from public._t where k = 'm10'), 60) $$,
  '23505', null, 'no repite la misma solicitud vigente');
select throws_ok($$ select public.request_booking((select id from public._b where k = 'I'),
  'a2000000-0000-0000-0000-00000000005a', 'presencial', (select v from public._t where k = 'm10'), 60) $$,
  'TU001', null, 'tutor inactivo');
select throws_ok($$ select public.request_booking((select id from public._b where k = 'TC'),
  'c2000000-0000-0000-0000-00000000005a', 'presencial', (select v from public._t where k = 'm10'), 60) $$,
  'TU001', null, 'tutor de otra universidad');
select throws_ok($$ select public.request_booking((select id from public._b where k = 'T'),
  'a2000000-0000-0000-0000-00000000005c', 'presencial', (select v from public._t where k = 'm10'), 60) $$,
  'TU003', null, 'materia que el tutor no ofrece');
select throws_ok($$ select public.request_booking((select id from public._b where k = 'T'),
  'c2000000-0000-0000-0000-00000000005a', 'presencial', (select v from public._t where k = 'm10'), 60) $$,
  'TU003', null, 'materia de otra universidad');
select throws_ok($$ select public.request_booking((select id from public._b where k = 'T'),
  'a2000000-0000-0000-0000-00000000005a', 'virtual', (select v from public._t where k = 'm10'), 60) $$,
  'TU004', null, 'modalidad que el tutor no ofrece');
select throws_ok($$ select public.request_booking((select id from public._b where k = 'T'),
  'a2000000-0000-0000-0000-00000000005a', 'presencial', (select v from public._t where k = 'm10'), 45) $$,
  'TU005', null, 'duración no válida');
select throws_ok($$ select public.request_booking((select id from public._b where k = 'T'),
  'a2000000-0000-0000-0000-00000000005a', 'presencial', (select v from public._t where k = 'past'), 60) $$,
  'TU006', null, 'fecha pasada');
select throws_ok($$ select public.request_booking((select id from public._b where k = 'T'),
  'a2000000-0000-0000-0000-00000000005a', 'presencial', (select v from public._t where k = 'm7'), 60) $$,
  'TU007', null, 'fuera de la disponibilidad');
select throws_ok($$ select public.request_booking((select id from public._b where k = 'T'),
  'a2000000-0000-0000-0000-00000000005a', 'presencial', (select v from public._t where k = 'm11'), 90) $$,
  'TU007', null, 'la sesión debe caber completa en el bloque');
select throws_ok($$ select public.accept_booking((select id from public._b where k = 'b1')) $$,
  'TU009', null, 'el estudiante no acepta su propia solicitud');
select throws_ok($$ update public.bookings set status = 'aceptada' $$,
  '42501', null, 'no cambia el estado con un UPDATE directo');
select throws_ok($$ insert into public.bookings (university_id, student_id, tutor_profile_id, subject_id, modality,
  starts_at, ends_at, duration_minutes, agreed_price)
  values ('a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-0000000000e1', (select id from public._b where k = 'T'),
  'a2000000-0000-0000-0000-00000000005a', 'presencial', now() + interval '3 days', now() + interval '3 days 1 hour', 60, 0) $$,
  '42501', null, 'no inserta reservas directamente');
select is((select count(*)::int from public.bookings), 2, 've solo sus reservas');
reset role;

-- S2 pide el mismo horario: las pendientes pueden coexistir
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-0000000000e2","role":"authenticated"}', true);
set local role authenticated;
select lives_ok($$ insert into public._b select 'b2', public.request_booking((select id from public._b where k = 'T'),
  'a2000000-0000-0000-0000-00000000005a', 'presencial', (select v from public._t where k = 'm10'), 60) $$,
  'otra cuenta pide el mismo horario (pendientes coexisten)');
select is((select count(*)::int from public.bookings), 1, 'S2 no ve la reserva de S');
reset role;

-- ---------------------------------------------------------------------------
-- Tutor T responde
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-0000000000f1","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.bookings), 3, 'el tutor ve las solicitudes recibidas');
select lives_ok($$ select public.accept_booking((select id from public._b where k = 'b1')) $$, 'el tutor acepta');
select results_eq($$ select status::text, responded_at is not null from public.bookings where id = (select id from public._b where k = 'b1') $$,
  $$ values ('aceptada', true) $$, 'queda aceptada con fecha de respuesta');
select throws_ok($$ select public.accept_booking((select id from public._b where k = 'b2')) $$,
  'TU008', null, 'no acepta otra sesión que se cruza');
select lives_ok($$ select public.reject_booking((select id from public._b where k = 'b2')) $$, 'rechaza la otra');
select throws_ok($$ select public.accept_booking((select id from public._b where k = 'b2')) $$,
  'TU010', null, 'una rechazada no se vuelve a aceptar');
select throws_ok($$ select public.cancel_booking((select id from public._b where k = 'b90')) $$,
  'TU013', null, 'el tutor no cancela pendientes (las rechaza)');
select throws_ok($$ update public.bookings set agreed_price = 1 $$,
  '42501', null, 'no cambia el precio acordado');
select throws_ok($$ select public.cancel_booking((select id from public._b where k = 'b1')) $$,
  'TU011', null, 'cancelar una aceptada exige motivo');
select lives_ok($$ select public.cancel_booking((select id from public._b where k = 'b1'), 'Me enfermé') $$,
  'el tutor cancela una aceptada antes del inicio, con motivo');
select results_eq($$ select status::text, cancelled_by, cancellation_reason, cancelled_at is not null
  from public.bookings where id = (select id from public._b where k = 'b1') $$,
  $$ values ('cancelada', 'a2000000-0000-0000-0000-0000000000f1'::uuid, 'Me enfermé', true) $$,
  'guarda quién, cuándo y por qué');
reset role;

-- ---------------------------------------------------------------------------
-- Estudiante S
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;
select results_eq($$ select cancellation_reason from public.bookings where id = (select id from public._b where k = 'b1') $$,
  $$ values ('Me enfermé') $$, 'la contraparte ve el motivo');
select lives_ok($$ select public.cancel_booking((select id from public._b where k = 'b90')) $$,
  'el estudiante cancela su solicitud pendiente sin motivo');
select lives_ok($$ insert into public._b select 'b3', public.request_booking((select id from public._b where k = 'T'),
  'a2000000-0000-0000-0000-00000000005a', 'presencial', (select v from public._t where k = 'm10'), 60) $$,
  'vuelve a pedir el horario (la anterior está cancelada)');
reset role;
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-0000000000f1","role":"authenticated"}', true);
set local role authenticated;
select lives_ok($$ select public.accept_booking((select id from public._b where k = 'b3')) $$, 'el tutor acepta b3');
select lives_ok($$ select public.save_tutor_profile('Tutor T', 20, true, false, true,
  array['a2000000-0000-0000-0000-00000000005a','a2000000-0000-0000-0000-00000000005b']::uuid[],
  '[{"weekday":1,"start_minute":480,"end_minute":720},{"weekday":2,"start_minute":840,"end_minute":1080}]') $$,
  'el tutor sube su tarifa');
reset role;
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;
select results_eq($$ select agreed_price from public.bookings where id = (select id from public._b where k = 'b3') $$,
  $$ values (10.00::numeric) $$, 'la reserva conserva el precio acordado');
select throws_ok($$ select public.request_booking((select id from public._b where k = 'D'),
  'a2000000-0000-0000-0000-00000000005a', 'virtual', (select v from public._t where k = 'm10'), 60) $$,
  'TU014', null, 'el estudiante no tiene dos sesiones confirmadas que se crucen');
reset role;

-- ---------------------------------------------------------------------------
-- Cuenta doble D: solicita como estudiante, pero no a sí misma
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-0000000000d1","role":"authenticated"}', true);
set local role authenticated;
select throws_ok($$ select public.request_booking((select id from public._b where k = 'D'),
  'a2000000-0000-0000-0000-00000000005a', 'virtual', (select v from public._t where k = 'm10'), 60) $$,
  'TU002', null, 'no se reserva contra el propio perfil');
select lives_ok($$ select public.request_booking((select id from public._b where k = 'T'),
  'a2000000-0000-0000-0000-00000000005a', 'presencial', (select v from public._t where k = 't14'), 60) $$,
  'con perfil de tutor sigue solicitando tutorías');
reset role;

-- ---------------------------------------------------------------------------
-- Otra universidad y administrador
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub":"c2000000-0000-0000-0000-0000000000f1","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.bookings), 0, 'otra universidad no ve reservas de A');
select throws_ok($$ select public.cancel_booking((select id from public._b where k = 'b3'), 'motivo') $$,
  'TU009', null, 'ni las cancela');
reset role;
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-0000000000ad","role":"authenticated"}', true);
set local role authenticated;
select throws_ok($$ select public.request_booking((select id from public._b where k = 'T'),
  'a2000000-0000-0000-0000-00000000005a', 'presencial', (select v from public._t where k = 't14'), 60) $$,
  '42501', null, 'una cuenta administradora no solicita tutorías');
reset role;

-- ---------------------------------------------------------------------------
-- Sesiones que ya empezaron y garantías de la base (sesión del equipo)
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims', '', true);
with x as (
  insert into public.bookings (university_id, student_id, tutor_profile_id, subject_id, modality,
    starts_at, ends_at, duration_minutes, agreed_price, status)
  values ('a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-0000000000e1', (select id from public._b where k = 'T'),
    'a2000000-0000-0000-0000-00000000005a', 'presencial', now() - interval '30 minutes', now() + interval '30 minutes', 60, 10, 'aceptada')
  returning id)
insert into public._b select 'old', id from x;
with x as (
  insert into public.bookings (university_id, student_id, tutor_profile_id, subject_id, modality,
    starts_at, ends_at, duration_minutes, agreed_price)
  values ('a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-0000000000e2', (select id from public._b where k = 'T'),
    'a2000000-0000-0000-0000-00000000005a', 'presencial', now() - interval '3 days', now() - interval '3 days' + interval '1 hour', 60, 10)
  returning id)
insert into public._b select 'oldp', id from x;

select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;
select throws_ok($$ select public.cancel_booking((select id from public._b where k = 'old'), 'Ya no puedo') $$,
  'TU012', null, 'no se cancela una sesión que ya empezó');
reset role;
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-0000000000f1","role":"authenticated"}', true);
set local role authenticated;
select throws_ok($$ select public.accept_booking((select id from public._b where k = 'oldp')) $$,
  'TU012', null, 'no se acepta una solicitud cuya hora ya pasó');
-- Tutor desactiva su perfil: quien tiene reservas con él sigue viéndolo
select lives_ok($$ update public.tutor_profiles set is_active = false where user_id = auth.uid() $$, 'el tutor se desactiva');
reset role;
select set_config('request.jwt.claims', '{"sub":"a2000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.tutor_profiles where id = (select id from public._b where k = 'T')), 1,
  'el estudiante sigue viendo el perfil del tutor de sus reservas');
reset role;
select set_config('request.jwt.claims', '', true);

-- Doble aceptación aunque se salte la función: la restricción EXCLUDE lo impide.
select throws_ok($$ update public.bookings set status = 'aceptada'
  where id = (select id from public._b where k = 'b2') $$,
  'TU010', null, 'rechazada → aceptada no es una transición válida (ni para el equipo)');
select throws_ok($$ insert into public.bookings (university_id, student_id, tutor_profile_id, subject_id, modality,
    starts_at, ends_at, duration_minutes, agreed_price, status)
  values ('a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-0000000000e2', (select id from public._b where k = 'T'),
    'a2000000-0000-0000-0000-00000000005a', 'presencial', (select v from public._t where k = 'm10'),
    (select v from public._t where k = 'm10') + interval '1 hour', 60, 10, 'aceptada') $$,
  '23P01', null, 'dos sesiones confirmadas del mismo tutor no se cruzan (EXCLUDE)');
select throws_ok($$ delete from public.bookings where id = (select id from public._b where k = 'b2') $$,
  '42501', null, 'las reservas no se eliminan');
select throws_ok($$ update public.bookings set starts_at = starts_at + interval '1 day'
  where id = (select id from public._b where k = 'b3') $$,
  '42501', null, 'la fecha acordada no se modifica');

select * from finish();
rollback;

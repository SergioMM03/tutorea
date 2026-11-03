-- Tutorea · Fase 14.9 · confirmaciones de sesiones (migraciones 19 y 21)
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(38);

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

-- Sesiones: d1, d2, d3 terminaron hace 2 h; fut empieza en 2 días; pend está pendiente.
select pg_temp.booking('d1',   'a9000000-0000-0000-0000-0000000000e1', 'a9000000-0000-0000-0000-0000000000f1', now() - interval '3 hours', 'aceptada');
select pg_temp.booking('d2',   'a9000000-0000-0000-0000-0000000000e1', 'a9000000-0000-0000-0000-0000000000f1', now() - interval '27 hours', 'aceptada');
select pg_temp.booking('d3',   'a9000000-0000-0000-0000-0000000000e1', 'a9000000-0000-0000-0000-0000000000f1', now() - interval '51 hours', 'aceptada');
select pg_temp.booking('d4',   'a9000000-0000-0000-0000-0000000000e1', 'a9000000-0000-0000-0000-0000000000f1', now() - interval '75 hours', 'aceptada');
select pg_temp.booking('fut',  'a9000000-0000-0000-0000-0000000000e1', 'a9000000-0000-0000-0000-0000000000f1', now() + interval '2 days', 'aceptada');
select pg_temp.booking('pend', 'a9000000-0000-0000-0000-0000000000e1', 'a9000000-0000-0000-0000-0000000000f1', now() + interval '3 days', 'pendiente');
select pg_temp.booking('canc', 'a9000000-0000-0000-0000-0000000000e1', 'a9000000-0000-0000-0000-0000000000f1', now() - interval '99 hours', 'cancelada');

-- Estructura y permisos
select ok((select relrowsecurity from pg_class where oid = 'public.booking_confirmations'::regclass), 'RLS en booking_confirmations');
select ok(not has_table_privilege('authenticated', 'public.booking_confirmations', 'insert'), 'la app no inserta confirmaciones');
select ok(not has_table_privilege('authenticated', 'public.booking_confirmations', 'update'), 'la app no modifica confirmaciones');
select ok(not has_table_privilege('anon', 'public.booking_confirmations', 'select'), 'anon no lee confirmaciones');
select ok(not has_function_privilege('anon', 'public.confirm_booking(uuid)', 'execute'), 'anon no confirma');

-- ---------- Primera y segunda confirmación ----------
select pg_temp.login('a9000000-0000-0000-0000-0000000000e1');
select is(public.confirm_booking(pg_temp.id('d1'))::text, 'pendiente_confirmacion', 'primera confirmación (estudiante) → pendiente_confirmacion');
select results_eq($$ select party, user_id from public.booking_confirmations where booking_id = pg_temp.id('d1') $$,
  $$ values ('estudiante', 'a9000000-0000-0000-0000-0000000000e1'::uuid) $$, 'queda registrada la confirmación del estudiante');
select throws_ok($$ select public.confirm_booking(pg_temp.id('d1')) $$, 'TU021', null, 'no confirma dos veces');
select throws_ok($$ select public.confirm_booking(pg_temp.id('fut')) $$, 'TU020', null, 'no confirma antes de que termine la sesión');
select throws_ok($$ select public.confirm_booking(pg_temp.id('pend')) $$, 'TU023', null, 'no confirma una solicitud pendiente');
select throws_ok($$ select public.confirm_booking(pg_temp.id('canc')) $$, 'TU023', null, 'no confirma una reserva cancelada');
select throws_ok($$ insert into public.booking_confirmations (booking_id, university_id, party, user_id)
  values (pg_temp.id('d2'), 'a9000000-0000-0000-0000-000000000001', 'estudiante', auth.uid()) $$,
  '42501', null, 'no inserta confirmaciones directamente');
select pg_temp.logout();

select pg_temp.login('a9000000-0000-0000-0000-0000000000e9');
select throws_ok($$ select public.confirm_booking(pg_temp.id('d1')) $$, 'TU009', null, 'un usuario externo no confirma');
select is((select count(*)::int from public.booking_confirmations), 0, 'un usuario externo no ve confirmaciones ajenas');
select pg_temp.logout();
select pg_temp.login('c9000000-0000-0000-0000-0000000000f1');
select throws_ok($$ select public.confirm_booking(pg_temp.id('d1')) $$, 'TU009', null, 'un tutor de otra universidad no confirma');
select pg_temp.logout();

select pg_temp.login('a9000000-0000-0000-0000-0000000000f1');
select is((select count(*)::int from public.booking_confirmations where booking_id = pg_temp.id('d1')), 1, 'el tutor ve la confirmación del estudiante');
select is(public.confirm_booking(pg_temp.id('d1'))::text, 'completada', 'segunda confirmación (tutor) → completada');
select results_eq($$ select status::text from public.bookings where id = pg_temp.id('d1') $$, $$ values ('completada') $$, 'la reserva queda completada');
select throws_ok($$ select public.confirm_booking(pg_temp.id('d1')) $$, 'TU023', null, 'una completada ya no se confirma');
select pg_temp.logout();

-- ---------- Incidencia abierta: conserva confirmaciones y bloquea la finalización ----------
select pg_temp.login('a9000000-0000-0000-0000-0000000000e1');
select is(public.confirm_booking(pg_temp.id('d2'))::text, 'pendiente_confirmacion', 'el estudiante confirma d2');
select pg_temp.logout();
select pg_temp.login('a9000000-0000-0000-0000-0000000000f1');
select lives_ok($$ insert into public._ids select 'i2', public.report_incident(pg_temp.id('d2'), 'impuntualidad', 'El estudiante llegó 40 minutos tarde.') $$,
  'el tutor reporta una incidencia en d2');
select throws_ok($$ select public.confirm_booking(pg_temp.id('d2')) $$, 'TU022', null, 'con incidencia abierta no se completa');
select results_eq($$ select status::text from public.bookings where id = pg_temp.id('d2') $$, $$ values ('pendiente_confirmacion') $$,
  'la reserva sigue pendiente de confirmación');
select is((select count(*)::int from public.booking_confirmations where booking_id = pg_temp.id('d2')), 1,
  'la confirmación del estudiante se conserva');
select pg_temp.logout();

select pg_temp.login('a9000000-0000-0000-0000-0000000000ad');
select lives_ok($$ select public.admin_resolve_incident(pg_temp.id('i2'), 'Se habló con ambas partes.') $$, 'el administrador resuelve');
select pg_temp.logout();
select pg_temp.login('a9000000-0000-0000-0000-0000000000f1');
select is(public.confirm_booking(pg_temp.id('d2'))::text, 'completada', 'resuelta la incidencia, el tutor completa su confirmación');
select pg_temp.logout();

-- d3: la incidencia llega antes de cualquier confirmación y se desestima.
select pg_temp.login('a9000000-0000-0000-0000-0000000000e1');
select lives_ok($$ insert into public._ids select 'i3', public.report_incident(pg_temp.id('d3'), 'otro', 'El enlace de la reunión no funcionaba.') $$,
  'el estudiante reporta en d3');
select is(public.confirm_booking(pg_temp.id('d3'))::text, 'pendiente_confirmacion', 'la primera confirmación se permite con incidencia abierta');
select pg_temp.logout();
select pg_temp.login('a9000000-0000-0000-0000-0000000000f1');
select throws_ok($$ select public.confirm_booking(pg_temp.id('d3')) $$, 'TU022', null, 'la segunda no, mientras siga abierta');
select pg_temp.logout();
select pg_temp.login('a9000000-0000-0000-0000-0000000000ad');
select lives_ok($$ select public.admin_dismiss_incident(pg_temp.id('i3'), 'Problema técnico del estudiante.') $$, 'el administrador la desestima');
select pg_temp.logout();
select pg_temp.login('a9000000-0000-0000-0000-0000000000f1');
select is(public.confirm_booking(pg_temp.id('d3'))::text, 'completada', 'desestimada, el tutor completa su confirmación');
select throws_ok($$ update public.booking_confirmations set confirmed_at = now() where booking_id = pg_temp.id('d3') $$,
  '42501', null, 'las confirmaciones no se modifican');
select throws_ok($$ delete from public.booking_confirmations where booking_id = pg_temp.id('d3') $$,
  '42501', null, 'ni se borran');
select pg_temp.logout();

-- ---------- Nada se completa por tiempo; administradores ----------
select results_eq($$ select status::text from public.bookings where id = pg_temp.id('d4') $$, $$ values ('aceptada') $$,
  'una sesión terminada sin confirmaciones sigue aceptada');
select pg_temp.login('a9000000-0000-0000-0000-0000000000ad');
select is((select count(*)::int from public.booking_confirmations), 6, 'el administrador ve las confirmaciones de su universidad');
select throws_ok($$ select public.confirm_booking(pg_temp.id('d4')) $$, 'TU009', null, 'el administrador no confirma por las partes');
select pg_temp.logout();
select pg_temp.login('c9000000-0000-0000-0000-0000000000ad');
select is((select count(*)::int from public.booking_confirmations), 0, 'el administrador de otra universidad no ve nada');
select pg_temp.logout();
select set_config('request.jwt.claims', '', true);
select throws_ok($$ update public.bookings set status = 'completada' where id = pg_temp.id('d4') $$,
  'TU010', null, 'ni el equipo salta de aceptada a completada sin confirmación');

select * from finish();
rollback;

-- Tutorea · Fase 14.7 · tutor_profiles, tutor_subjects, availability_slots y save_tutor_profile
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(43);

-- Universidades A y C con carreras y materias
insert into public.universities (id, slug, name, short_name, country) values
  ('a0000000-0000-0000-0000-000000000001', 'test-a', 'Universidad A', 'UA', 'El Salvador'),
  ('c0000000-0000-0000-0000-000000000001', 'test-c', 'Universidad C', 'UC', 'El Salvador');
insert into public.careers (id, university_id, slug, name) values
  ('a0000000-0000-0000-0000-0000000000c1', 'a0000000-0000-0000-0000-000000000001', 'a-eco', 'Economía A'),
  ('c0000000-0000-0000-0000-0000000000c1', 'c0000000-0000-0000-0000-000000000001', 'c-eco', 'Economía C');
insert into public.subjects (id, university_id, career_id, slug, name, category) values
  ('a0000000-0000-0000-0000-00000000005a', 'a0000000-0000-0000-0000-000000000001', null, 'a-mat', 'Matemáticas A', 'Matemáticas'),
  ('a0000000-0000-0000-0000-00000000005b', 'a0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-0000000000c1', 'a-mic', 'Micro A', 'Economía'),
  ('c0000000-0000-0000-0000-00000000005a', 'c0000000-0000-0000-0000-000000000001', null, 'c-mat', 'Matemáticas C', 'Matemáticas');

-- Cuentas: dos tutores y un estudiante en A, un futuro administrador en A y un tutor en C
insert into auth.users (id, email, raw_user_meta_data) values
  ('a0000000-0000-0000-0000-0000000000f1', 't1.a@test.local',
   '{"university_id":"a0000000-0000-0000-0000-000000000001","career_id":"a0000000-0000-0000-0000-0000000000c1","full_name":"Tutor Uno","academic_year":4,"role":"tutor"}'),
  ('a0000000-0000-0000-0000-0000000000f2', 't2.a@test.local',
   '{"university_id":"a0000000-0000-0000-0000-000000000001","career_id":"a0000000-0000-0000-0000-0000000000c1","full_name":"Tutor Dos","academic_year":3,"role":"tutor"}'),
  ('a0000000-0000-0000-0000-0000000000e1', 'e1.a@test.local',
   '{"university_id":"a0000000-0000-0000-0000-000000000001","career_id":"a0000000-0000-0000-0000-0000000000c1","full_name":"Estudiante A","academic_year":1}'),
  ('a0000000-0000-0000-0000-0000000000ad', 'admin.a@test.local',
   '{"university_id":"a0000000-0000-0000-0000-000000000001","career_id":"a0000000-0000-0000-0000-0000000000c1","full_name":"Admin A","academic_year":5}'),
  ('c0000000-0000-0000-0000-0000000000f1', 't1.c@test.local',
   '{"university_id":"c0000000-0000-0000-0000-000000000001","career_id":"c0000000-0000-0000-0000-0000000000c1","full_name":"Tutor C","academic_year":2,"role":"tutor"}');
select public.assign_admin('a0000000-0000-0000-0000-0000000000ad', 'Prueba pgTAP');

-- Estructura
select ok((select relrowsecurity from pg_class where oid = 'public.tutor_profiles'::regclass), 'RLS en tutor_profiles');
select ok((select relrowsecurity from pg_class where oid = 'public.tutor_subjects'::regclass), 'RLS en tutor_subjects');
select ok((select relrowsecurity from pg_class where oid = 'public.availability_slots'::regclass), 'RLS en availability_slots');
select ok(not has_table_privilege('anon', 'public.tutor_profiles', 'select'), 'anon no lee tutores');
select ok(not has_function_privilege('anon', 'public.save_tutor_profile(text, numeric, boolean, boolean, boolean, uuid[], jsonb)', 'execute'), 'anon no guarda perfiles');
select ok(not has_column_privilege('authenticated', 'public.tutor_profiles', 'rating_avg', 'update'), 'la app no escribe rating_avg');
select ok(not has_column_privilege('authenticated', 'public.tutor_profiles', 'university_id', 'insert'), 'la app no elige la universidad');
select isnt_definer('public', 'save_tutor_profile', array['text','numeric','boolean','boolean','boolean','uuid[]','jsonb'], 'save_tutor_profile es invoker (RLS)');

-- ---------- Tutor 1 de A crea su perfil ----------
select set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-0000000000f1","role":"authenticated"}', true);
set local role authenticated;

select lives_ok($$ select public.save_tutor_profile('Clases de mate', 10, true, false, true,
  array['a0000000-0000-0000-0000-00000000005a','a0000000-0000-0000-0000-00000000005b']::uuid[],
  '[{"weekday":1,"start_minute":480,"end_minute":720},{"weekday":3,"start_minute":840,"end_minute":1020}]') $$,
  'un tutor crea su perfil con materias y horarios');
select results_eq($$ select user_id, university_id, rating_count, offers_virtual from public.tutor_profiles $$,
  $$ values ('a0000000-0000-0000-0000-0000000000f1'::uuid, 'a0000000-0000-0000-0000-000000000001'::uuid, 0, false) $$,
  'el servidor fija dueño y universidad');
select is((select count(*)::int from public.tutor_subjects), 2, 'dos materias asociadas');
select is((select count(*)::int from public.availability_slots), 2, 'dos horarios');
select is((select count(distinct university_id)::int from public.tutor_subjects), 1, 'las materias quedan en la universidad del tutor');

select lives_ok($$ select public.save_tutor_profile('Clases de mate y micro', 12.5, true, true, true,
  array['a0000000-0000-0000-0000-00000000005b']::uuid[],
  '[{"weekday":2,"start_minute":600,"end_minute":660}]') $$,
  'actualiza el perfil (misma función)');
select results_eq($$ select description, hourly_rate::float8, offers_virtual from public.tutor_profiles $$,
  $$ values ('Clases de mate y micro', 12.5::float8, true) $$, 'datos actualizados');
select results_eq($$ select subject_id from public.tutor_subjects $$,
  $$ values ('a0000000-0000-0000-0000-00000000005b'::uuid) $$, 'materias reemplazadas');
select results_eq($$ select weekday::int, start_minute::int, end_minute::int from public.availability_slots $$,
  $$ values (2, 600, 660) $$, 'horarios reemplazados');
select is((select count(*)::int from public.tutor_profiles), 1, 'sigue habiendo un solo perfil por tutor');

select throws_ok($$ select public.save_tutor_profile('x', 10, true, true, true, '{}'::uuid[],
  '[{"weekday":1,"start_minute":480,"end_minute":600},{"weekday":1,"start_minute":540,"end_minute":660}]') $$,
  '23P01', null, 'horarios que se cruzan se rechazan');
select results_eq($$ select weekday::int from public.availability_slots $$, $$ values (2) $$,
  'el rechazo no deja cambios a medias');
select throws_ok($$ select public.save_tutor_profile('x', 10, true, true, true, '{}'::uuid[],
  '[{"weekday":8,"start_minute":480,"end_minute":600}]') $$, '23514', null, 'día inválido');
select throws_ok($$ select public.save_tutor_profile('x', 10, true, true, true, '{}'::uuid[],
  '[{"weekday":1,"start_minute":600,"end_minute":600}]') $$, '23514', null, 'hora de fin antes o igual al inicio');
select throws_ok($$ select public.save_tutor_profile('x', 10, false, false, true, '{}'::uuid[], '[]') $$,
  '23514', null, 'al menos una modalidad');
select throws_ok($$ select public.save_tutor_profile('x', -1, true, true, true, '{}'::uuid[], '[]') $$,
  '23514', null, 'tarifa negativa');
select throws_ok($$ select public.save_tutor_profile('x', 10, true, true, true,
  array['c0000000-0000-0000-0000-00000000005a']::uuid[], '[]') $$,
  '23503', null, 'no puede impartir materias de otra universidad');
select throws_ok($$ update public.tutor_profiles set rating_avg = 5 $$, '42501', null, 'no se pone calificación');
select throws_ok($$ insert into public.tutor_profiles (user_id, hourly_rate) values ('a0000000-0000-0000-0000-0000000000f2', 1) $$,
  '42501', null, 'no crea perfiles a nombre de otro (sin permiso de columna)');
select lives_ok($$ insert into public.availability_slots (tutor_profile_id, weekday, start_minute, end_minute)
  select id, 5, 60, 120 from public.tutor_profiles $$, 'agrega un horario directo');
select lives_ok($$ update public.availability_slots set end_minute = 180 where weekday = 5 $$, 'modifica un horario');
select results_eq($$ with d as (delete from public.availability_slots where weekday = 5 returning 1) select count(*)::int from d $$,
  $$ values (1) $$, 'elimina un horario');
reset role;

-- ---------- Tutor 2 de A ----------
select set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-0000000000f2","role":"authenticated"}', true);
set local role authenticated;
select lives_ok($$ select public.save_tutor_profile('Tutor dos', 8, true, true, false,
  array['a0000000-0000-0000-0000-00000000005a']::uuid[], '[{"weekday":1,"start_minute":480,"end_minute":600}]') $$,
  'otro tutor crea su perfil inactivo');
select results_eq($$ with u as (update public.tutor_profiles set description = 'hackeado'
  where user_id = 'a0000000-0000-0000-0000-0000000000f1' returning 1) select count(*)::int from u $$,
  $$ values (0) $$, 'no modifica el perfil de otro tutor');
select throws_ok($$ insert into public.availability_slots (tutor_profile_id, weekday, start_minute, end_minute)
  select id, 4, 60, 120 from public.tutor_profiles where user_id = 'a0000000-0000-0000-0000-0000000000f1' $$,
  '42501', null, 'no agrega horarios a otro tutor');
select results_eq($$ with d as (delete from public.tutor_subjects ts using public.tutor_profiles tp
  where tp.id = ts.tutor_profile_id and tp.user_id = 'a0000000-0000-0000-0000-0000000000f1' returning 1) select count(*)::int from d $$,
  $$ values (0) $$, 'no quita materias de otro tutor');
reset role;

-- ---------- Estudiante de A ----------
select set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;
-- Migración 16 (doble rol): un estudiante SÍ puede crear su perfil de tutor
-- (lo prueba 06_dual_role.test.sql). Aquí solo se comprueba que aún no tiene uno.
select is((select count(*)::int from public.tutor_profiles where user_id = auth.uid()), 0,
  'el estudiante todavía no tiene perfil de tutor');
select is((select count(*)::int from public.tutor_profiles), 1, 'el estudiante ve solo los tutores activos de su universidad');
select is((select count(*)::int from public.availability_slots), 1, 'y solo sus horarios');
select results_eq($$ with u as (update public.tutor_profiles set is_active = false returning 1) select count(*)::int from u $$,
  $$ values (0) $$, 'un estudiante no modifica perfiles de tutor');
reset role;

-- ---------- Tutor de C ----------
select set_config('request.jwt.claims', '{"sub":"c0000000-0000-0000-0000-0000000000f1","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.tutor_profiles), 0, 'otra universidad no ve tutores de A');
select is((select count(*)::int from public.tutor_subjects), 0, 'ni sus materias');
reset role;

-- ---------- Administrador de A ----------
select set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-0000000000ad","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.tutor_profiles), 2, 'el administrador ve también los inactivos');
select lives_ok($$ update public.tutor_profiles set is_active = false where user_id = 'a0000000-0000-0000-0000-0000000000f1' $$,
  'el administrador desactiva un perfil');
select throws_ok($$ update public.tutor_profiles set hourly_rate = 1 where user_id = 'a0000000-0000-0000-0000-0000000000f1' $$,
  '42501', null, 'el administrador no cambia la tarifa');
reset role;

select * from finish();
rollback;

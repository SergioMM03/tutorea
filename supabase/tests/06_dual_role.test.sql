-- Tutorea · Corrección 14.7 (migración 16) · una cuenta puede ser estudiante y tutor
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(33);

-- Universidades A y C
insert into public.universities (id, slug, name, short_name, country) values
  ('a1000000-0000-0000-0000-000000000001', 'dual-a', 'Universidad Dual A', 'DA', 'El Salvador'),
  ('c1000000-0000-0000-0000-000000000001', 'dual-c', 'Universidad Dual C', 'DC', 'El Salvador');
insert into public.careers (id, university_id, slug, name) values
  ('a1000000-0000-0000-0000-0000000000c1', 'a1000000-0000-0000-0000-000000000001', 'da-eco', 'Economía DA'),
  ('c1000000-0000-0000-0000-0000000000c1', 'c1000000-0000-0000-0000-000000000001', 'dc-eco', 'Economía DC');
insert into public.subjects (id, university_id, career_id, slug, name, category) values
  ('a1000000-0000-0000-0000-00000000005a', 'a1000000-0000-0000-0000-000000000001', null, 'da-mat', 'Matemáticas DA', 'Matemáticas'),
  ('a1000000-0000-0000-0000-00000000005b', 'a1000000-0000-0000-0000-000000000001', null, 'da-est', 'Estadística DA', 'Matemáticas'),
  ('c1000000-0000-0000-0000-00000000005a', 'c1000000-0000-0000-0000-000000000001', null, 'dc-mat', 'Matemáticas DC', 'Matemáticas');

-- Cuentas de A: estudiante E (será también tutor), estudiante E2, tutor T (rol principal tutor),
-- administrador AD. En C: tutor TC.
insert into auth.users (id, email, raw_user_meta_data) values
  ('a1000000-0000-0000-0000-0000000000e1', 'e1.dual@test.local',
   '{"university_id":"a1000000-0000-0000-0000-000000000001","career_id":"a1000000-0000-0000-0000-0000000000c1","full_name":"Estudiante Dual","academic_year":2}'),
  ('a1000000-0000-0000-0000-0000000000e2', 'e2.dual@test.local',
   '{"university_id":"a1000000-0000-0000-0000-000000000001","career_id":"a1000000-0000-0000-0000-0000000000c1","full_name":"Estudiante Dos","academic_year":1}'),
  ('a1000000-0000-0000-0000-0000000000f1', 't1.dual@test.local',
   '{"university_id":"a1000000-0000-0000-0000-000000000001","career_id":"a1000000-0000-0000-0000-0000000000c1","full_name":"Tutor Dual","academic_year":4,"role":"tutor"}'),
  ('a1000000-0000-0000-0000-0000000000ad', 'admin.dual@test.local',
   '{"university_id":"a1000000-0000-0000-0000-000000000001","career_id":"a1000000-0000-0000-0000-0000000000c1","full_name":"Admin Dual","academic_year":5}'),
  ('c1000000-0000-0000-0000-0000000000f1', 'tc.dual@test.local',
   '{"university_id":"c1000000-0000-0000-0000-000000000001","career_id":"c1000000-0000-0000-0000-0000000000c1","full_name":"Tutor C","academic_year":3,"role":"tutor"}');
select public.assign_admin('a1000000-0000-0000-0000-0000000000ad', 'Prueba pgTAP');

-- ---------- Tutor T (rol principal tutor) y tutor de C crean sus perfiles ----------
select set_config('request.jwt.claims', '{"sub":"a1000000-0000-0000-0000-0000000000f1","role":"authenticated"}', true);
set local role authenticated;
select lives_ok($$ select public.save_tutor_profile('Tutor de A', 10, true, true, true,
  array['a1000000-0000-0000-0000-00000000005a']::uuid[], '[{"weekday":2,"start_minute":600,"end_minute":720}]') $$,
  'una cuenta con rol principal tutor sigue creando su perfil');
reset role;
select set_config('request.jwt.claims', '{"sub":"c1000000-0000-0000-0000-0000000000f1","role":"authenticated"}', true);
set local role authenticated;
select lives_ok($$ select public.save_tutor_profile('Tutor de C', 9, true, true, true,
  array['c1000000-0000-0000-0000-00000000005a']::uuid[], '[{"weekday":1,"start_minute":480,"end_minute":600}]') $$,
  'el tutor de C crea su perfil');
reset role;

-- ---------- Estudiante E: crea y administra su perfil de tutor ----------
select set_config('request.jwt.claims', '{"sub":"a1000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;

select lives_ok($$ select public.save_tutor_profile('Doy clases de mate', 7.5, false, true, true,
  array['a1000000-0000-0000-0000-00000000005a','a1000000-0000-0000-0000-00000000005b']::uuid[],
  '[{"weekday":1,"start_minute":480,"end_minute":600},{"weekday":4,"start_minute":900,"end_minute":1020}]') $$,
  'un estudiante crea su perfil de tutor');
select results_eq($$ select role::text from public.profiles where id = auth.uid() $$,
  $$ values ('estudiante') $$, 'su rol principal sigue siendo estudiante');
select results_eq($$ select user_id, university_id, rating_count from public.tutor_profiles where user_id = auth.uid() $$,
  $$ values ('a1000000-0000-0000-0000-0000000000e1'::uuid, 'a1000000-0000-0000-0000-000000000001'::uuid, 0) $$,
  'el servidor fija dueño y universidad');
select is((select count(*)::int from public.tutor_subjects ts join public.tutor_profiles tp on tp.id = ts.tutor_profile_id
  where tp.user_id = auth.uid()), 2, 'sus dos materias quedaron asociadas');
select is((select count(*)::int from public.availability_slots a join public.tutor_profiles tp on tp.id = a.tutor_profile_id
  where tp.user_id = auth.uid()), 2, 'sus dos horarios quedaron guardados');

select lives_ok($$ select public.save_tutor_profile('Doy clases de estadística', 8, true, true, true,
  array['a1000000-0000-0000-0000-00000000005b']::uuid[], '[{"weekday":3,"start_minute":540,"end_minute":660}]') $$,
  'actualiza su perfil, materias y horarios');
select results_eq($$ select ts.subject_id from public.tutor_subjects ts join public.tutor_profiles tp on tp.id = ts.tutor_profile_id
  where tp.user_id = auth.uid() $$, $$ values ('a1000000-0000-0000-0000-00000000005b'::uuid) $$, 'materias reemplazadas');
select results_eq($$ select a.weekday::int from public.availability_slots a join public.tutor_profiles tp on tp.id = a.tutor_profile_id
  where tp.user_id = auth.uid() $$, $$ values (3) $$, 'horarios reemplazados');
select is((select count(*)::int from public.tutor_profiles where user_id = auth.uid()), 1, 'sigue teniendo un solo perfil de tutor');
select lives_ok($$ insert into public.availability_slots (tutor_profile_id, weekday, start_minute, end_minute)
  select id, 5, 600, 660 from public.tutor_profiles where user_id = auth.uid() $$, 'agrega un horario directamente');
select lives_ok($$ insert into public.tutor_subjects (tutor_profile_id, subject_id)
  select id, 'a1000000-0000-0000-0000-00000000005a' from public.tutor_profiles where user_id = auth.uid() $$,
  'agrega una materia directamente');
select results_eq($$ with d as (delete from public.tutor_subjects ts using public.tutor_profiles tp
  where tp.id = ts.tutor_profile_id and tp.user_id = auth.uid() and ts.subject_id = 'a1000000-0000-0000-0000-00000000005a'
  returning 1) select count(*)::int from d $$, $$ values (1) $$, 'quita una materia');
select throws_ok($$ select public.save_tutor_profile('x', 8, true, true, true, '{}'::uuid[],
  '[{"weekday":3,"start_minute":540,"end_minute":660},{"weekday":3,"start_minute":600,"end_minute":700}]') $$,
  '23P01', null, 'sus horarios tampoco se pueden cruzar');
select throws_ok($$ select public.save_tutor_profile('x', 8, true, true, true,
  array['c1000000-0000-0000-0000-00000000005a']::uuid[], '[]') $$,
  '23503', null, 'no imparte materias de otra universidad');

-- Sigue pudiendo buscar tutores (base para solicitar tutorías)
select is((select count(*)::int from public.tutor_profiles where user_id <> auth.uid()), 1,
  'sigue viendo a los demás tutores activos de su universidad');
select is((select count(*)::int from public.tutor_subjects ts join public.tutor_profiles tp on tp.id = ts.tutor_profile_id
  where tp.user_id <> auth.uid()), 1, 'y sus materias');
select is((select count(*)::int from public.availability_slots a join public.tutor_profiles tp on tp.id = a.tutor_profile_id
  where tp.user_id <> auth.uid()), 1, 'y sus horarios');

-- No modifica perfiles de otros
select results_eq($$ with u as (update public.tutor_profiles set description = 'hackeado'
  where user_id = 'a1000000-0000-0000-0000-0000000000f1' returning 1) select count(*)::int from u $$,
  $$ values (0) $$, 'no modifica el perfil de otro tutor');
select throws_ok($$ insert into public.availability_slots (tutor_profile_id, weekday, start_minute, end_minute)
  select id, 6, 60, 120 from public.tutor_profiles where user_id = 'a1000000-0000-0000-0000-0000000000f1' $$,
  '42501', null, 'no agrega horarios a otro tutor');
select results_eq($$ with d as (delete from public.tutor_subjects ts using public.tutor_profiles tp
  where tp.id = ts.tutor_profile_id and tp.user_id = 'a1000000-0000-0000-0000-0000000000f1' returning 1)
  select count(*)::int from d $$, $$ values (0) $$, 'no quita materias de otro tutor');

-- No se asigna privilegios
select throws_ok($$ update public.profiles set role = 'administrador' where id = auth.uid() $$,
  '42501', null, 'no cambia su rol a administrador');
select throws_ok($$ select public.assign_admin(auth.uid(), 'yo mismo') $$,
  '42501', null, 'no puede ejecutar assign_admin');
select throws_ok($$ update public.tutor_profiles set rating_avg = 5 where user_id = auth.uid() $$,
  '42501', null, 'no se pone calificación');
reset role;

-- ---------- Administrador de A ----------
select set_config('request.jwt.claims', '{"sub":"a1000000-0000-0000-0000-0000000000ad","role":"authenticated"}', true);
set local role authenticated;
select throws_ok($$ select public.save_tutor_profile('x', 5, true, true, true, '{}'::uuid[], '[]') $$,
  '42501', null, 'una cuenta administradora no ofrece tutorías');
select lives_ok($$ update public.tutor_profiles set is_active = false where user_id = 'a1000000-0000-0000-0000-0000000000e1' $$,
  'el administrador desactiva el perfil de tutor del estudiante');
select throws_ok($$ update public.tutor_profiles set hourly_rate = 1 where user_id = 'a1000000-0000-0000-0000-0000000000e1' $$,
  '42501', null, 'el administrador no cambia su tarifa');
select is((select count(*)::int from public.tutor_profiles where university_id = 'c1000000-0000-0000-0000-000000000001'), 0,
  'el administrador de A no ve tutores de C');
select results_eq($$ with u as (update public.tutor_profiles set is_active = false
  where user_id = 'c1000000-0000-0000-0000-0000000000f1' returning 1) select count(*)::int from u $$,
  $$ values (0) $$, 'ni desactiva perfiles de C');
reset role;

-- ---------- Asignación de administradores (equipo, sesión privilegiada) ----------
select set_config('request.jwt.claims', '', true);  -- conexión directa del equipo, sin JWT
select throws_ok($$ select public.assign_admin('a1000000-0000-0000-0000-0000000000e1', 'Prueba pgTAP') $$,
  '22023', null, 'una cuenta que ofrece tutorías no se convierte en administrador');
select lives_ok($$ select public.assign_admin('a1000000-0000-0000-0000-0000000000e2', 'Prueba pgTAP') $$,
  'un estudiante sin perfil de tutor sí puede ser administrador');
select results_eq($$ select role::text from public.profiles where id = 'c1000000-0000-0000-0000-0000000000f1' $$,
  $$ values ('tutor') $$, 'el tutor de C sigue intacto');

select * from finish();
rollback;

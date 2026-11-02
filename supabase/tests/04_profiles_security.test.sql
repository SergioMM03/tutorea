-- Tutorea · Fase 14.2 · profiles, public_profiles, handle_new_user, guarda de rol y assign_admin
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(48);

insert into public.universities (id, slug, name, short_name, country, is_active) values
  ('a0000000-0000-0000-0000-000000000001', 'test-a', 'Universidad A', 'UA', 'El Salvador', true),
  ('b0000000-0000-0000-0000-000000000001', 'test-b', 'Universidad B', 'UB', 'El Salvador', false),
  ('c0000000-0000-0000-0000-000000000001', 'test-c', 'Universidad C', 'UC', 'El Salvador', true);
insert into public.careers (id, university_id, slug, name) values
  ('a0000000-0000-0000-0000-0000000000c1', 'a0000000-0000-0000-0000-000000000001', 'a-eco', 'Economía A'),
  ('a0000000-0000-0000-0000-0000000000c2', 'a0000000-0000-0000-0000-000000000001', 'a-sof', 'Software A'),
  ('b0000000-0000-0000-0000-0000000000c1', 'b0000000-0000-0000-0000-000000000001', 'b-eco', 'Economía B'),
  ('c0000000-0000-0000-0000-0000000000c1', 'c0000000-0000-0000-0000-000000000001', 'c-eco', 'Economía C');

-- ---------- handle_new_user ----------
insert into auth.users (id, email, raw_user_meta_data) values
  ('a0000000-0000-0000-0000-0000000000e1', 'est1.a@test.local',
   '{"university_id":"a0000000-0000-0000-0000-000000000001","career_id":"a0000000-0000-0000-0000-0000000000c1","full_name":"  Estudiante Uno ","academic_year":2,"role":"administrador","legacy_id":"u-sergio"}'),
  ('a0000000-0000-0000-0000-0000000000e2', 'est2.a@test.local',
   '{"university_id":"a0000000-0000-0000-0000-000000000001","career_id":"a0000000-0000-0000-0000-0000000000c2","full_name":"Estudiante Dos","academic_year":1}'),
  ('a0000000-0000-0000-0000-0000000000f1', 'tutor.a@test.local',
   '{"university_id":"a0000000-0000-0000-0000-000000000001","career_id":"a0000000-0000-0000-0000-0000000000c1","full_name":"Tutor A","academic_year":4,"role":"tutor"}'),
  ('a0000000-0000-0000-0000-0000000000ad', 'admin.a@test.local',
   '{"university_id":"a0000000-0000-0000-0000-000000000001","career_id":"a0000000-0000-0000-0000-0000000000c1","full_name":"Admin A","academic_year":5}'),
  ('c0000000-0000-0000-0000-0000000000e1', 'est.c@test.local',
   '{"university_id":"c0000000-0000-0000-0000-000000000001","career_id":"c0000000-0000-0000-0000-0000000000c1","full_name":"Estudiante C","academic_year":3}');

select is((select role::text from public.profiles where id = 'a0000000-0000-0000-0000-0000000000e1'), 'estudiante',
  'el rol administrador en la metadata se convierte en estudiante');
select is((select role::text from public.profiles where id = 'a0000000-0000-0000-0000-0000000000f1'), 'tutor',
  'el rol tutor de la metadata se respeta');
select is((select legacy_id from public.profiles where id = 'a0000000-0000-0000-0000-0000000000e1'), null,
  'legacy_id nunca se toma de la metadata');
select is((select full_name from public.profiles where id = 'a0000000-0000-0000-0000-0000000000e1'), 'Estudiante Uno',
  'el nombre se guarda sin espacios sobrantes');
select is((select career_name from public.profiles where id = 'a0000000-0000-0000-0000-0000000000e2'), 'Software A',
  'career_name sale de la carrera elegida');
select throws_ok($$ insert into auth.users (id, email, raw_user_meta_data) values (gen_random_uuid(), 'x1@test.local',
  '{"university_id":"b0000000-0000-0000-0000-000000000001","career_id":"b0000000-0000-0000-0000-0000000000c1","full_name":"Xx","academic_year":1}') $$,
  '22023', null, 'no hay registro en una universidad inactiva');
select throws_ok($$ insert into auth.users (id, email, raw_user_meta_data) values (gen_random_uuid(), 'x2@test.local',
  '{"university_id":"a0000000-0000-0000-0000-000000000001","career_id":"c0000000-0000-0000-0000-0000000000c1","full_name":"Xx","academic_year":1}') $$,
  '22023', null, 'no hay registro con una carrera de otra universidad');
select throws_ok($$ insert into auth.users (id, email, raw_user_meta_data) values (gen_random_uuid(), 'x3@test.local', '{}') $$,
  '22023', null, 'no hay registro sin metadata');
select throws_ok($$ insert into auth.users (id, email, raw_user_meta_data) values (gen_random_uuid(), 'x4@test.local',
  '{"university_id":"no-es-uuid","career_id":"a0000000-0000-0000-0000-0000000000c1","full_name":"Xx","academic_year":1}') $$,
  '22023', null, 'un university_id mal formado se rechaza con mensaje claro');
select throws_ok($$ insert into auth.users (id, email, raw_user_meta_data) values (gen_random_uuid(), 'x5@test.local',
  '{"university_id":"a0000000-0000-0000-0000-000000000001","career_id":"a0000000-0000-0000-0000-0000000000c1","full_name":"Xx","academic_year":11}') $$,
  '22023', null, 'año académico fuera de rango se rechaza');

-- ---------- estudiante 1 de A ----------
select set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;

select results_eq($$ select id from public.profiles $$,
  $$ values ('a0000000-0000-0000-0000-0000000000e1'::uuid) $$, 'el estudiante solo lee su propio perfil');
select is((select count(*)::int from public.public_profiles), 4, 'public_profiles muestra a los 4 usuarios de su universidad');
select is((select count(*)::int from public.public_profiles where university_id <> 'a0000000-0000-0000-0000-000000000001'), 0,
  'public_profiles no muestra otras universidades');
select is(public.current_university_id(), 'a0000000-0000-0000-0000-000000000001'::uuid, 'current_university_id es la propia');
select is(public.current_user_role()::text, 'estudiante', 'current_user_role es estudiante');
select ok(not public.is_admin_of('a0000000-0000-0000-0000-000000000001'), 'un estudiante no es administrador');
select throws_ok($$ select * from auth.users $$, '42501', null, 'el cliente no consulta auth.users (correos)');

select lives_ok($$ update public.profiles set full_name = 'Estudiante Editado', academic_year = 3 where id = 'a0000000-0000-0000-0000-0000000000e1' $$,
  'el estudiante edita su nombre y año');
select lives_ok($$ update public.profiles set career_id = 'a0000000-0000-0000-0000-0000000000c2', career_name = 'Texto falso' where id = 'a0000000-0000-0000-0000-0000000000e1' $$,
  'el estudiante cambia de carrera');
select is((select career_name from public.profiles where id = 'a0000000-0000-0000-0000-0000000000e1'), 'Software A',
  'career_name se corrige desde la carrera, no desde el texto enviado');
select throws_ok($$ update public.profiles set career_id = 'c0000000-0000-0000-0000-0000000000c1' where id = 'a0000000-0000-0000-0000-0000000000e1' $$,
  '23503', null, 'no puede elegir una carrera de otra universidad');
select throws_ok($$ update public.profiles set career_id = null where id = 'a0000000-0000-0000-0000-0000000000e1' $$,
  '23502', null, 'no puede quedarse sin carrera');
select throws_ok($$ update public.profiles set role = 'administrador' where id = 'a0000000-0000-0000-0000-0000000000e1' $$,
  '42501', null, 'no puede cambiar su rol');
select throws_ok($$ update public.profiles set university_id = 'c0000000-0000-0000-0000-000000000001' where id = 'a0000000-0000-0000-0000-0000000000e1' $$,
  '42501', null, 'no puede cambiar su universidad');
select results_eq($$ with u as (update public.profiles set full_name = 'Hackeado' where id = 'a0000000-0000-0000-0000-0000000000e2' returning 1) select count(*)::int from u $$,
  $$ values (0) $$, 'no puede editar el perfil de otro');
select throws_ok($$ delete from public.profiles where id = 'a0000000-0000-0000-0000-0000000000e1' $$,
  '42501', null, 'no puede borrar perfiles');
select throws_ok($$ select public.assign_admin('a0000000-0000-0000-0000-0000000000e1', 'Intruso') $$,
  '42501', null, 'no puede ejecutar assign_admin');
reset role;

-- ---------- anon ----------
set local role anon;
select throws_ok($$ select * from public.profiles $$, '42501', null, 'anon no lee profiles');
select throws_ok($$ select * from public.public_profiles $$, '42501', null, 'anon no lee public_profiles');
reset role;

-- ---------- defensa en profundidad: una petición de la app dentro de una función definer ----------
-- current_user es postgres (como en una función SECURITY DEFINER) pero el JWT es authenticated.
select throws_ok($$ update public.profiles set role = 'administrador' where id = 'a0000000-0000-0000-0000-0000000000e2' $$,
  '42501', null, 'la guarda bloquea el cambio de rol aunque corra como postgres con un JWT de la app');

-- ---------- assign_admin (sesión del equipo, sin JWT) ----------
select set_config('request.jwt.claims', '', true);
select lives_ok($$ select public.assign_admin('a0000000-0000-0000-0000-0000000000ad', 'Equipo Tutorea') $$, 'el equipo asigna un administrador');
select is((select role::text || '/' || university_id::text from public.profiles where id = 'a0000000-0000-0000-0000-0000000000ad'),
  'administrador/a0000000-0000-0000-0000-000000000001', 'el administrador conserva su universidad');
select throws_ok($$ select public.assign_admin('00000000-0000-0000-0000-000000000000', 'Equipo Tutorea') $$,
  'P0002', null, 'assign_admin falla con una cuenta inexistente');
select throws_ok($$ select public.assign_admin('a0000000-0000-0000-0000-0000000000f1', 'Equipo Tutorea') $$,
  '22023', null, 'un tutor existente no se promueve a administrador');
select is((select role::text from public.profiles where id = 'a0000000-0000-0000-0000-0000000000f1'), 'tutor',
  'el tutor conserva su rol');
select throws_ok($$ select public.assign_admin('a0000000-0000-0000-0000-0000000000e2', '  ') $$,
  '22023', null, 'assign_admin exige indicar quién asigna');
select results_eq(
  $$ select target_user_id, target_full_name, university_id, previous_role::text, assigned_by, db_role
     from public.admin_role_assignments where target_user_id = 'a0000000-0000-0000-0000-0000000000ad' $$,
  $$ values ('a0000000-0000-0000-0000-0000000000ad'::uuid, 'Admin A', 'a0000000-0000-0000-0000-000000000001'::uuid,
             'estudiante', 'Equipo Tutorea', 'postgres') $$,
  'la auditoría registra a quién, de qué universidad, rol previo, quién asignó y con qué rol de base');
select ok((select assigned_at is not null and assigned_at <= now() from public.admin_role_assignments
           where target_user_id = 'a0000000-0000-0000-0000-0000000000ad'), 'la auditoría registra cuándo');
select lives_ok($$ select public.assign_admin('a0000000-0000-0000-0000-0000000000ad', 'Equipo Tutorea') $$,
  'asignar de nuevo a un administrador no falla');
select is((select count(*)::int from public.admin_role_assignments where target_user_id = 'a0000000-0000-0000-0000-0000000000ad'), 1,
  'repetir la asignación no duplica la auditoría');
select throws_ok($$ update public.admin_role_assignments set assigned_by = 'Otro' $$,
  '42501', null, 'la auditoría no se modifica (ni como postgres)');
select throws_ok($$ delete from public.admin_role_assignments $$,
  '42501', null, 'la auditoría no se borra (ni como postgres)');

-- service_role (script del equipo con la Admin API): también puede asignar.
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select lives_ok($$ select public.assign_admin('c0000000-0000-0000-0000-0000000000e1', 'Script del equipo') $$, 'service_role puede ejecutar assign_admin');
reset role;
select is((select role::text || '/' || db_role from public.profiles p join public.admin_role_assignments a on a.target_user_id = p.id
           where p.id = 'c0000000-0000-0000-0000-0000000000e1'), 'administrador/service_role',
  'la asignación con service_role queda aplicada y auditada');

-- ---------- administrador de A ----------
select set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-0000000000ad","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.profiles), 4, 'el administrador lee los perfiles de su universidad');
select is((select count(*)::int from public.profiles where university_id = 'c0000000-0000-0000-0000-000000000001'), 0,
  'el administrador no lee perfiles de otra universidad');
select throws_ok($$ select * from public.admin_role_assignments $$, '42501', null,
  'un administrador no lee la auditoría desde la app');
select results_eq($$ with u as (update public.profiles set full_name = 'Editado por admin' where id = 'a0000000-0000-0000-0000-0000000000e2' returning 1) select count(*)::int from u $$,
  $$ values (0) $$, 'el administrador no edita perfiles ajenos (pendiente de decisión)');
reset role;

select * from finish();
rollback;

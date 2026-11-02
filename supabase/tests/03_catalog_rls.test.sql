-- Tutorea · Fase 14.2 · RLS de universities, careers y subjects
-- Datos propios de la prueba (no depende del seed); todo se deshace con rollback.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(14);

-- Universidad A activa, B inactiva, C activa
insert into public.universities (id, slug, name, short_name, country, is_active) values
  ('a0000000-0000-0000-0000-000000000001', 'test-a', 'Universidad A', 'UA', 'El Salvador', true),
  ('b0000000-0000-0000-0000-000000000001', 'test-b', 'Universidad B', 'UB', 'El Salvador', false),
  ('c0000000-0000-0000-0000-000000000001', 'test-c', 'Universidad C', 'UC', 'El Salvador', true);
insert into public.careers (id, university_id, slug, name) values
  ('a0000000-0000-0000-0000-0000000000c1', 'a0000000-0000-0000-0000-000000000001', 'a-eco', 'Economía A'),
  ('b0000000-0000-0000-0000-0000000000c1', 'b0000000-0000-0000-0000-000000000001', 'b-eco', 'Economía B'),
  ('c0000000-0000-0000-0000-0000000000c1', 'c0000000-0000-0000-0000-000000000001', 'c-eco', 'Economía C');
insert into public.subjects (university_id, career_id, slug, name, category) values
  ('b0000000-0000-0000-0000-000000000001', null, 'b-mat', 'Matemáticas B', 'Matemáticas');

-- Usuarios: estudiante y futuro administrador en A
insert into auth.users (id, email, raw_user_meta_data) values
  ('a0000000-0000-0000-0000-0000000000e1', 'est.a@test.local',
   '{"university_id":"a0000000-0000-0000-0000-000000000001","career_id":"a0000000-0000-0000-0000-0000000000c1","full_name":"Estudiante A","academic_year":2}'),
  ('a0000000-0000-0000-0000-0000000000ad', 'admin.a@test.local',
   '{"university_id":"a0000000-0000-0000-0000-000000000001","career_id":"a0000000-0000-0000-0000-0000000000c1","full_name":"Admin A","academic_year":5}');
select public.assign_admin('a0000000-0000-0000-0000-0000000000ad', 'Prueba pgTAP');

-- ---------- anon ----------
set local role anon;
select is((select count(*)::int from public.universities where slug like 'test-%'), 2, 'anon ve solo universidades activas (A y C)');
select is((select count(*)::int from public.careers where university_id = 'b0000000-0000-0000-0000-000000000001'), 0, 'anon no ve carreras de una universidad inactiva');
select is((select count(*)::int from public.subjects where university_id = 'b0000000-0000-0000-0000-000000000001'), 0, 'anon no ve materias de una universidad inactiva');
select is((select count(*)::int from public.careers where university_id = 'a0000000-0000-0000-0000-000000000001'), 1, 'anon ve carreras de una universidad activa (registro)');
select throws_ok($$ insert into public.careers (university_id, slug, name) values ('a0000000-0000-0000-0000-000000000001', 'x', 'Xx') $$,
  '42501', null, 'anon no crea carreras');
reset role;

-- ---------- estudiante de A ----------
select set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;
select throws_ok($$ insert into public.careers (university_id, slug, name) values ('a0000000-0000-0000-0000-000000000001', 'x', 'Xx') $$,
  '42501', null, 'un estudiante no crea carreras');
select results_eq($$ with u as (update public.careers set name = 'Hackeada' returning 1) select count(*)::int from u $$,
  $$ values (0) $$, 'un estudiante no modifica carreras');
reset role;

-- ---------- administrador de A ----------
select set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-0000000000ad","role":"authenticated"}', true);
set local role authenticated;
select lives_ok($$ insert into public.careers (university_id, slug, name) values ('a0000000-0000-0000-0000-000000000001', 'a-der', 'Derecho A') $$,
  'el administrador crea carreras en su universidad');
select throws_ok($$ insert into public.careers (university_id, slug, name) values ('c0000000-0000-0000-0000-000000000001', 'c-der', 'Derecho C') $$,
  '42501', null, 'el administrador no crea carreras en otra universidad');
select results_eq($$ with u as (update public.careers set name = 'Hackeada' where university_id = 'c0000000-0000-0000-0000-000000000001' returning 1) select count(*)::int from u $$,
  $$ values (0) $$, 'el administrador no modifica carreras de otra universidad');
select throws_ok($$ update public.careers set university_id = 'c0000000-0000-0000-0000-000000000001' where slug = 'a-der' $$,
  '42501', null, 'nadie mueve una carrera a otra universidad (sin permiso de columna)');
select lives_ok($$ insert into public.subjects (university_id, career_id, slug, name, category) values ('a0000000-0000-0000-0000-000000000001', null, 'a-mat', 'Matemáticas A', 'Matemáticas') $$,
  'el administrador crea materias en su universidad');
select throws_ok($$ insert into public.subjects (university_id, career_id, slug, name, category) values ('a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-0000000000c1', 'a-mix', 'Mezcla', 'Matemáticas') $$,
  '23503', null, 'una materia no puede usar una carrera de otra universidad (FK compuesta)');
select results_eq($$ with d as (delete from public.careers where slug = 'a-der' returning 1) select count(*)::int from d $$,
  $$ values (1) $$, 'el administrador borra una carrera sin uso de su universidad');
reset role;

select * from finish();
rollback;

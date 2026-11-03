-- Tutorea · Fase 14.8 · disponibilidad al solicitar y al ACEPTAR (migración 18)
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(22);

insert into public.universities (id, slug, name, short_name, country) values
  ('a3000000-0000-0000-0000-000000000001', 'av-a', 'Universidad Disponibilidad', 'UD', 'El Salvador');
insert into public.careers (id, university_id, slug, name) values
  ('a3000000-0000-0000-0000-0000000000c1', 'a3000000-0000-0000-0000-000000000001', 'ud-eco', 'Economía UD');
insert into public.subjects (id, university_id, career_id, slug, name, category) values
  ('a3000000-0000-0000-0000-00000000005a', 'a3000000-0000-0000-0000-000000000001', null, 'ud-mat', 'Matemáticas UD', 'Matemáticas');

insert into auth.users (id, email, raw_user_meta_data)
select v.id::uuid, v.email, jsonb_build_object(
  'university_id', 'a3000000-0000-0000-0000-000000000001', 'career_id', 'a3000000-0000-0000-0000-0000000000c1',
  'full_name', v.name, 'academic_year', 2, 'role', v.role)
from (values
  ('a3000000-0000-0000-0000-0000000000e1', 'e1.av@test.local', 'Estudiante Uno', 'estudiante'),
  ('a3000000-0000-0000-0000-0000000000e2', 'e2.av@test.local', 'Estudiante Dos', 'estudiante'),
  ('a3000000-0000-0000-0000-0000000000e3', 'e3.av@test.local', 'Estudiante Tres', 'estudiante'),
  ('a3000000-0000-0000-0000-0000000000f1', 't.av@test.local',  'Tutor',          'tutor')
) as v(id, email, name, role);

-- Fechas de la próxima semana en hora de El Salvador.
create table public._t (k text primary key, v timestamptz);
insert into public._t
select k, (date_trunc('week', now() at time zone 'America/El_Salvador') + interval '7 days' + d) at time zone 'America/El_Salvador'
from (values
  ('lun10', interval '10 hours'), ('lun11', interval '11 hours'), ('lun12', interval '12 hours'),
  ('mie15', interval '2 days 15 hours'),
  ('vie09', interval '4 days 9 hours'),
  ('sab08', interval '5 days 8 hours')
) as x(k, d);
create table public._b (k text primary key, id uuid);
grant select on public._t to authenticated;
grant select, insert on public._b to authenticated;

-- Disponibilidad del tutor: lunes 08–12, miércoles 14–18, viernes 09–11, sábado 08–10.
select set_config('request.jwt.claims', '{"sub":"a3000000-0000-0000-0000-0000000000f1","role":"authenticated"}', true);
set local role authenticated;
select public.save_tutor_profile('Tutor', 10, true, true, true, array['a3000000-0000-0000-0000-00000000005a']::uuid[],
  '[{"weekday":1,"start_minute":480,"end_minute":720},{"weekday":3,"start_minute":840,"end_minute":1080},
    {"weekday":5,"start_minute":540,"end_minute":660},{"weekday":6,"start_minute":480,"end_minute":600}]');
insert into public._b select 'T', id from public.tutor_profiles where user_id = auth.uid();
reset role;

-- Una función para pedir como cada estudiante (todo en la misma transacción de la prueba).
create function pg_temp.pedir(p_student uuid, p_key text, p_when text, p_minutes int) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_student, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into public._b select p_key, public.request_booking((select id from public._b where k = 'T'),
    'a3000000-0000-0000-0000-00000000005a', 'presencial', (select v from public._t where k = p_when), p_minutes);
  reset role;
end;
$$;

-- ---------------------------------------------------------------------------
-- Al solicitar
-- ---------------------------------------------------------------------------
select lives_ok($$ select pg_temp.pedir('a3000000-0000-0000-0000-0000000000e1', 'lunes', 'lun10', 60) $$,
  'solicitud dentro de la disponibilidad');
select lives_ok($$ select pg_temp.pedir('a3000000-0000-0000-0000-0000000000e1', 'limite', 'lun11', 60) $$,
  'solicitud que termina justo al final del bloque (11:00–12:00)');
select throws_ok($$ select pg_temp.pedir('a3000000-0000-0000-0000-0000000000e1', 'x1', 'lun12', 60) $$,
  'TU007', null, 'solicitud fuera de la disponibilidad');
select throws_ok($$ select pg_temp.pedir('a3000000-0000-0000-0000-0000000000e1', 'x2', 'lun11', 90) $$,
  'TU007', null, 'solicitud cuya duración sale del bloque');
select lives_ok($$ select pg_temp.pedir('a3000000-0000-0000-0000-0000000000e2', 'miercoles', 'mie15', 60) $$,
  'solicitud del miércoles');
select lives_ok($$ select pg_temp.pedir('a3000000-0000-0000-0000-0000000000e1', 'viernes', 'vie09', 90) $$,
  'solicitud de 90 minutos el viernes (09:00–10:30)');
select lives_ok($$ select pg_temp.pedir('a3000000-0000-0000-0000-0000000000e2', 'sabado', 'sab08', 60) $$,
  'solicitud del sábado');
select lives_ok($$ select pg_temp.pedir('a3000000-0000-0000-0000-0000000000e3', 'cruce', 'lun10', 60) $$,
  'otra cuenta pide el mismo horario del lunes (pendientes coexisten)');
select lives_ok($$ select pg_temp.pedir('a3000000-0000-0000-0000-0000000000e2', 'directo', 'lun11', 60) $$,
  'otra solicitud del lunes 11:00');
select set_config('request.jwt.claims', '', true);

-- ---------------------------------------------------------------------------
-- El tutor cambia su disponibilidad: quita el miércoles, acorta el viernes a
-- 09–10 y mueve el sábado de 08–10 a 14–16. El lunes no cambia.
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub":"a3000000-0000-0000-0000-0000000000f1","role":"authenticated"}', true);
set local role authenticated;
select lives_ok($$ select public.save_tutor_profile('Tutor', 10, true, true, true, array['a3000000-0000-0000-0000-00000000005a']::uuid[],
  '[{"weekday":1,"start_minute":480,"end_minute":720},{"weekday":5,"start_minute":540,"end_minute":600},
    {"weekday":6,"start_minute":840,"end_minute":960}]') $$, 'el tutor cambia su disponibilidad');

select lives_ok($$ select public.accept_booking((select id from public._b where k = 'lunes')) $$,
  'acepta cuando la disponibilidad sigue vigente');
select lives_ok($$ select public.accept_booking((select id from public._b where k = 'limite')) $$,
  'acepta la que termina justo al final del bloque');
select throws_ok($$ select public.accept_booking((select id from public._b where k = 'miercoles')) $$,
  'TU015', null, 'no acepta si el tutor eliminó ese horario');
select throws_ok($$ select public.accept_booking((select id from public._b where k = 'sabado')) $$,
  'TU015', null, 'no acepta si el tutor movió ese horario');
select throws_ok($$ select public.accept_booking((select id from public._b where k = 'viernes')) $$,
  'TU015', null, 'no acepta si la duración ya no cabe en el horario');
select results_eq($$ select status::text from public.bookings
  where id in (select id from public._b where k in ('miercoles', 'sabado', 'viernes')) $$,
  $$ values ('pendiente'), ('pendiente'), ('pendiente') $$, 'las rechazadas por disponibilidad siguen pendientes');
select lives_ok($$ select public.reject_booking((select id from public._b where k = 'miercoles')) $$,
  'el tutor todavía puede rechazarla');

-- Los cruces se siguen comprobando: el lunes 11:00 ya está ocupado.
select throws_ok($$ select public.accept_booking((select id from public._b where k = 'directo')) $$,
  'TU008', null, 'no acepta otra sesión que se cruza con una aceptada');
-- Borrar el bloque del lunes directamente (sin save_tutor_profile) también cuenta.
select lives_ok($$ delete from public.availability_slots where weekday = 1 $$, 'el tutor borra el lunes');
reset role;

-- ---------------------------------------------------------------------------
-- Conflictos: el cruce se revisa antes que nada que dependa del orden, y la
-- restricción EXCLUDE es la garantía final ante aceptaciones simultáneas.
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub":"a3000000-0000-0000-0000-0000000000f1","role":"authenticated"}', true);
set local role authenticated;
select throws_ok($$ select public.accept_booking((select id from public._b where k = 'cruce')) $$,
  'TU015', null, 'con el lunes borrado, la del mismo horario ya no se puede aceptar');
reset role;
select set_config('request.jwt.claims', '', true);
select throws_ok($$ update public.bookings set status = 'aceptada' where id = (select id from public._b where k = 'cruce') $$,
  '23P01', null, 'aunque se salte la función, dos sesiones confirmadas no se cruzan');
select is((select count(*)::int from public.bookings where status = 'aceptada'), 2,
  'solo quedan confirmadas las dos sesiones válidas del lunes');

select * from finish();
rollback;

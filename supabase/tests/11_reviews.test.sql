-- Tutorea · Fase 14.9 · reseñas y promedio del tutor (migración 22)
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(35);

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

-- c1, c2, c3 se completan con las dos confirmaciones; d0 terminó pero no se confirmó.
select pg_temp.booking('c1',   'a9000000-0000-0000-0000-0000000000e1', 'a9000000-0000-0000-0000-0000000000f1', now() - interval '3 hours', 'aceptada');
select pg_temp.booking('c2',   'a9000000-0000-0000-0000-0000000000e1', 'a9000000-0000-0000-0000-0000000000f1', now() - interval '27 hours', 'aceptada');
select pg_temp.booking('c3',   'a9000000-0000-0000-0000-0000000000e1', 'a9000000-0000-0000-0000-0000000000f1', now() - interval '51 hours', 'aceptada');
select pg_temp.booking('d0',   'a9000000-0000-0000-0000-0000000000e1', 'a9000000-0000-0000-0000-0000000000f1', now() - interval '75 hours', 'aceptada');
select pg_temp.booking('rej',  'a9000000-0000-0000-0000-0000000000e1', 'a9000000-0000-0000-0000-0000000000f1', now() + interval '2 days', 'rechazada');
select pg_temp.booking('canc', 'a9000000-0000-0000-0000-0000000000e1', 'a9000000-0000-0000-0000-0000000000f1', now() - interval '99 hours', 'cancelada');
select pg_temp.booking('pend', 'a9000000-0000-0000-0000-0000000000e1', 'a9000000-0000-0000-0000-0000000000f1', now() + interval '3 days', 'pendiente');
create function pg_temp.complete(p_key text) returns void language plpgsql as $$
begin
  perform pg_temp.login('a9000000-0000-0000-0000-0000000000e1');
  perform public.confirm_booking(pg_temp.id(p_key));
  perform pg_temp.login('a9000000-0000-0000-0000-0000000000f1');
  perform public.confirm_booking(pg_temp.id(p_key));
  perform pg_temp.logout();
end $$;
select pg_temp.complete('c1');
select pg_temp.complete('c2');
select pg_temp.complete('c3');

-- Estructura y permisos
select ok((select relrowsecurity from pg_class where oid = 'public.reviews'::regclass), 'RLS en reviews');
select ok(not has_table_privilege('authenticated', 'public.reviews', 'insert'), 'la app no inserta reseñas directamente');
select ok(not has_table_privilege('authenticated', 'public.reviews', 'update'), 'ni las edita');
select ok(not has_table_privilege('authenticated', 'public.reviews', 'delete'), 'ni las borra');
select ok(not has_column_privilege('authenticated', 'public.tutor_profiles', 'rating_count', 'update'), 'la app no escribe el total');
select hasnt_column('public', 'public_reviews', 'student_id', 'la vista pública no expone al estudiante');
select hasnt_column('public', 'public_reviews', 'booking_id', 'ni la reserva');

select results_eq($$ select rating_avg, rating_count from public.tutor_profiles where user_id = 'a9000000-0000-0000-0000-0000000000f2' $$,
  $$ values (null::numeric, 0) $$, 'un tutor sin reseñas: promedio nulo y total 0 («Nuevo»)');

-- ---------- Quién y cuándo ----------
select pg_temp.login('a9000000-0000-0000-0000-0000000000f1');
select throws_ok($$ select public.submit_review(pg_temp.id('c1'), 5, 'Me califico yo.') $$, 'TU041', null, 'el tutor no se califica');
select pg_temp.logout();
select pg_temp.login('a9000000-0000-0000-0000-0000000000e9');
select throws_ok($$ select public.submit_review(pg_temp.id('c1'), 1) $$, 'TU009', null, 'un usuario externo no califica');
select pg_temp.logout();

select pg_temp.login('a9000000-0000-0000-0000-0000000000e1');
select throws_ok($$ select public.submit_review(pg_temp.id('d0'), 4) $$, 'TU042', null, 'no califica antes de completar');
select throws_ok($$ select public.submit_review(pg_temp.id('rej'), 4) $$, 'TU042', null, 'ni una rechazada');
select throws_ok($$ select public.submit_review(pg_temp.id('canc'), 4) $$, 'TU042', null, 'ni una cancelada');
select throws_ok($$ select public.submit_review(pg_temp.id('pend'), 4) $$, 'TU042', null, 'ni una pendiente');
select throws_ok($$ select public.submit_review(pg_temp.id('c1'), 6) $$, 'TU045', null, 'no más de 5 estrellas');
select throws_ok($$ select public.submit_review(pg_temp.id('c1'), 0) $$, 'TU045', null, 'ni menos de 1');

select lives_ok($$ select public.submit_review(pg_temp.id('c1'), 4, ' Muy clara la explicación. ') $$, 'calificación válida');
select results_eq($$ select rating::int, comment, student_id from public.reviews where booking_id = pg_temp.id('c1') $$,
  $$ values (4, 'Muy clara la explicación.', 'a9000000-0000-0000-0000-0000000000e1'::uuid) $$, 'guarda la reseña');
select throws_ok($$ select public.submit_review(pg_temp.id('c1'), 5) $$, 'TU044', null, 'una sola reseña por reserva');
select results_eq($$ select rating_avg, rating_count from public.tutor_profiles where user_id = 'a9000000-0000-0000-0000-0000000000f1' $$,
  $$ values (4.00::numeric, 1) $$, 'promedio 4,00 con 1 reseña');
select lives_ok($$ select public.submit_review(pg_temp.id('c2'), 5) $$, 'segunda reseña, otra reserva');
select results_eq($$ select rating_avg, rating_count from public.tutor_profiles where user_id = 'a9000000-0000-0000-0000-0000000000f1' $$,
  $$ values (4.50::numeric, 2) $$, 'promedio 4,50 con 2 reseñas');
select throws_ok($$ update public.reviews set rating = 1 where booking_id = pg_temp.id('c1') $$, '42501', null, 'no se edita');
select throws_ok($$ delete from public.reviews where booking_id = pg_temp.id('c1') $$, '42501', null, 'no se borra');
select pg_temp.logout();

-- ---------- Incidencia abierta en una completada ----------
select pg_temp.login('a9000000-0000-0000-0000-0000000000f1');
select lives_ok($$ insert into public._ids select 'i3', public.report_incident(pg_temp.id('c3'), 'conducta', 'Comentarios ofensivos al final de la sesión.') $$,
  'el tutor reporta en una reserva completada');
select throws_ok($$ update public.tutor_profiles set rating_avg = 5 where user_id = auth.uid() $$,
  '42501', null, 'el tutor no fija su propia calificación');
select pg_temp.logout();
select pg_temp.login('a9000000-0000-0000-0000-0000000000e1');
select throws_ok($$ select public.submit_review(pg_temp.id('c3'), 1) $$, 'TU043', null, 'con incidencia abierta no se califica');
select pg_temp.logout();
select pg_temp.login('a9000000-0000-0000-0000-0000000000ad');
select public.admin_resolve_incident(pg_temp.id('i3'), 'Se advirtió al estudiante.');
select pg_temp.logout();
select pg_temp.login('a9000000-0000-0000-0000-0000000000e1');
select lives_ok($$ select public.submit_review(pg_temp.id('c3'), 3) $$, 'resuelta, ya se puede calificar');
select results_eq($$ select rating_avg, rating_count from public.tutor_profiles where user_id = 'a9000000-0000-0000-0000-0000000000f1' $$,
  $$ values (4.00::numeric, 3) $$, 'promedio (4 + 5 + 3) / 3 = 4,00');
select is((select count(*)::int from public.reviews), 3, 'el estudiante ve sus reseñas');
select pg_temp.logout();

-- ---------- Privacidad ----------
select pg_temp.login('a9000000-0000-0000-0000-0000000000e9');
select is((select count(*)::int from public.reviews), 0, 'otro estudiante no lee la tabla de reseñas');
select results_eq($$ select count(*)::int, sum(rating)::int from public.public_reviews
  where tutor_profile_id = (select id from public.tutor_profiles where user_id = 'a9000000-0000-0000-0000-0000000000f1') $$,
  $$ values (3, 12) $$, 'pero ve las reseñas en el perfil público del tutor');
select pg_temp.logout();
select pg_temp.login('a9000000-0000-0000-0000-0000000000f1');
select is((select count(*)::int from public.reviews), 3, 'el tutor ve las reseñas que recibió');
select pg_temp.logout();
select pg_temp.login('c9000000-0000-0000-0000-0000000000e1');
select is((select count(*)::int from public.public_reviews), 0, 'otra universidad no ve reseñas');
select pg_temp.logout();
set local role anon;
select throws_ok($$ select * from public.public_reviews $$, '42501', null, 'anon no ve reseñas');
reset role;

select * from finish();
rollback;

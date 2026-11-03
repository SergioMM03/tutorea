-- Tutorea · Fase 14.9 · incidencias y su gestión administrativa (migración 20)
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(48);

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

select pg_temp.booking('d1',   'a9000000-0000-0000-0000-0000000000e1', 'a9000000-0000-0000-0000-0000000000f1', now() - interval '3 hours', 'aceptada');
select pg_temp.booking('d2',   'a9000000-0000-0000-0000-0000000000e1', 'a9000000-0000-0000-0000-0000000000f1', now() - interval '27 hours', 'aceptada');
select pg_temp.booking('old',  'a9000000-0000-0000-0000-0000000000e1', 'a9000000-0000-0000-0000-0000000000f1', now() - interval '8 days 2 hours', 'aceptada');
select pg_temp.booking('edge', 'a9000000-0000-0000-0000-0000000000e1', 'a9000000-0000-0000-0000-0000000000f1', now() - interval '7 days 1 hour', 'aceptada');
select pg_temp.booking('fut',  'a9000000-0000-0000-0000-0000000000e1', 'a9000000-0000-0000-0000-0000000000f1', now() + interval '2 days', 'aceptada');
select pg_temp.booking('pend', 'a9000000-0000-0000-0000-0000000000e1', 'a9000000-0000-0000-0000-0000000000f1', now() + interval '3 days', 'pendiente');
select pg_temp.booking('nada', 'a9000000-0000-0000-0000-0000000000e9', 'a9000000-0000-0000-0000-0000000000f2', now() - interval '5 hours', 'aceptada');

-- Estructura y permisos
select ok((select relrowsecurity from pg_class where oid = 'public.booking_incidents'::regclass), 'RLS en booking_incidents');
select ok((select relrowsecurity from pg_class where oid = 'public.booking_incident_events'::regclass), 'RLS en el historial');
select ok(not has_table_privilege('authenticated', 'public.booking_incidents', 'insert'), 'la app no inserta incidencias');
select ok(not has_table_privilege('authenticated', 'public.booking_incidents', 'update'), 'la app no actualiza incidencias');
select ok(not has_table_privilege('authenticated', 'public.booking_incident_events', 'insert'), 'la app no escribe el historial');
select ok(not has_function_privilege('authenticated', 'public.admin_change_incident(uuid, public.incident_status, text)', 'execute'),
  'el cambio genérico de estado no se expone');

-- El estudiante confirma d1 antes de reportar (la confirmación debe conservarse).
select pg_temp.login('a9000000-0000-0000-0000-0000000000e1');
select public.confirm_booking(pg_temp.id('d1'));

-- ---------- Reportes ----------
select lives_ok($$ insert into public._ids select 'iS', public.report_incident(pg_temp.id('d1'), 'inasistencia', '  El tutor no se conectó a la sesión.  ') $$,
  'reporte del estudiante');
select results_eq($$ select reporter_party, status::text, category, description from public.booking_incidents where id = pg_temp.id('iS') $$,
  $$ values ('estudiante', 'pendiente_revision', 'inasistencia', 'El tutor no se conectó a la sesión.') $$,
  'nace pendiente de revisión, con la parte que reporta');
select results_eq($$ select event, internal from public.booking_incident_events where incident_id = pg_temp.id('iS') $$,
  $$ values ('reportada', false) $$, 'queda en el historial');
select throws_ok($$ select public.report_incident(pg_temp.id('d1'), 'otro', 'Otro problema distinto con la sesión.') $$,
  'TU032', null, 'no abre una segunda incidencia mientras la primera siga abierta');
select throws_ok($$ select public.report_incident(pg_temp.id('pend'), 'otro', 'Todavía no me aceptan la solicitud.') $$,
  'TU030', null, 'no reporta una solicitud pendiente');
select throws_ok($$ select public.report_incident(pg_temp.id('old'), 'otro', 'Quiero reportar algo de hace días.') $$,
  'TU031', null, 'no reporta fuera de la ventana de siete días');
select lives_ok($$ select public.report_incident(pg_temp.id('edge'), 'calidad', 'Seis días y 23 horas después del fin.') $$,
  'reporta dentro de los siete días');
select lives_ok($$ select public.report_incident(pg_temp.id('fut'), 'conducta', 'Mensajes inapropiados antes de la sesión.') $$,
  'reporta una reserva aceptada antes de la sesión');
select throws_ok($$ select public.report_incident(pg_temp.id('d2'), 'robo', 'Una categoría que no existe aquí.') $$,
  'TU033', null, 'categoría no válida');
select throws_ok($$ select public.report_incident(pg_temp.id('d2'), 'otro', 'corto') $$,
  'TU033', null, 'descripción demasiado corta');
select throws_ok($$ select public.admin_resolve_incident(pg_temp.id('iS'), 'Me la resuelvo yo mismo.') $$,
  'TU034', null, 'un participante no gestiona incidencias');
select throws_ok($$ update public.booking_incidents set status = 'resuelta' where id = pg_temp.id('iS') $$,
  '42501', null, 'ni con un UPDATE directo');
select pg_temp.logout();

select pg_temp.login('a9000000-0000-0000-0000-0000000000f1');
select lives_ok($$ insert into public._ids select 'iT', public.report_incident(pg_temp.id('d1'), 'impuntualidad', 'El estudiante llegó tarde a la sesión.') $$,
  'reporte del tutor (la otra parte) sobre la misma reserva');
select is((select count(*)::int from public.booking_incidents where booking_id = pg_temp.id('d1')), 2,
  'el tutor ve las dos incidencias de su reserva');
select pg_temp.logout();

select pg_temp.login('a9000000-0000-0000-0000-0000000000e9');
select throws_ok($$ select public.report_incident(pg_temp.id('d1'), 'otro', 'No soy parte de esta reserva.') $$,
  'TU009', null, 'un usuario externo no reporta');
select is((select count(*)::int from public.booking_incidents), 0, 'un usuario externo no ve incidencias ajenas');
select pg_temp.logout();
select pg_temp.login('c9000000-0000-0000-0000-0000000000e1');
select is((select count(*)::int from public.booking_incidents), 0, 'otra universidad no ve incidencias');
select pg_temp.logout();

-- ---------- Administrador de la universidad ----------
select pg_temp.login('a9000000-0000-0000-0000-0000000000ad');
select is((select count(*)::int from public.booking_incidents), 4, 'el administrador ve las incidencias de su universidad');
select is((select count(*)::int from public.bookings), 3, 'y solo las reservas que tienen incidencias');
select lives_ok($$ select public.admin_start_incident_investigation(pg_temp.id('iS'), 'Revisar con el tutor.') $$,
  'abre la investigación');
select lives_ok($$ select public.admin_add_incident_note(pg_temp.id('iS'), 'El tutor dice que tuvo un problema de red.') $$,
  'agrega una nota interna');
select throws_ok($$ select public.admin_start_incident_investigation(pg_temp.id('iS')) $$,
  'TU035', null, 'en investigación → en investigación no es válida');
select throws_ok($$ select public.admin_resolve_incident(pg_temp.id('iS'), '') $$,
  'TU036', null, 'resolver exige la resolución');
select lives_ok($$ select public.admin_resolve_incident(pg_temp.id('iS'), 'El tutor repondrá la sesión.') $$,
  'resuelve');
select results_eq($$ select status::text, resolution_note, resolved_by, resolved_at is not null
  from public.booking_incidents where id = pg_temp.id('iS') $$,
  $$ values ('resuelta', 'El tutor repondrá la sesión.', 'a9000000-0000-0000-0000-0000000000ad'::uuid, true) $$,
  'guarda quién, cuándo y la resolución');
select throws_ok($$ select public.admin_dismiss_incident(pg_temp.id('iS'), 'Cambio de opinión.') $$,
  'TU035', null, 'una resuelta es final');
select throws_ok($$ select public.admin_start_incident_investigation(pg_temp.id('iS')) $$,
  'TU035', null, 'ni vuelve a investigación');
select lives_ok($$ select public.admin_dismiss_incident(pg_temp.id('iT'), 'No se pudo comprobar.') $$,
  'desestima directamente desde pendiente de revisión');
select bag_eq($$ select event, coalesce(from_status::text, '-') as desde, coalesce(to_status::text, '-') as hasta, internal
  from public.booking_incident_events where incident_id = pg_temp.id('iS') $$,
  $$ values ('reportada', '-', '-', false), ('estado', 'pendiente_revision', 'en_investigacion', false),
            ('nota', '-', '-', true), ('nota', '-', '-', true), ('estado', 'en_investigacion', 'resuelta', false) $$,
  'historial completo: reporte, estados y notas internas');
select pg_temp.logout();

select pg_temp.login('c9000000-0000-0000-0000-0000000000ad');
select throws_ok($$ select public.admin_dismiss_incident(pg_temp.id('iT'), 'Desde otra universidad.') $$,
  'TU034', null, 'un administrador de otra universidad no gestiona');
select throws_ok($$ select public.admin_add_incident_note(pg_temp.id('iS'), 'Nota ajena.') $$,
  'TU034', null, 'ni agrega notas');
select is((select count(*)::int from public.booking_incidents), 0, 'ni ve incidencias de otra universidad');
select is((select count(*)::int from public.bookings), 0, 'ni sus reservas');
select pg_temp.logout();

-- ---------- Las partes ----------
select pg_temp.login('a9000000-0000-0000-0000-0000000000e1');
select is((select count(*)::int from public.booking_incident_events where incident_id = pg_temp.id('iS')), 3,
  'las partes ven el reporte y los cambios de estado, no las notas internas');
select is((select count(*)::int from public.booking_incident_events where internal), 0, 'ninguna nota interna visible');
select results_eq($$ select resolution_note from public.booking_incidents where id = pg_temp.id('iS') $$,
  $$ values ('El tutor repondrá la sesión.') $$, 'la resolución sí es visible para las partes');
select is((select count(*)::int from public.booking_confirmations where booking_id = pg_temp.id('d1')), 1,
  'la confirmación hecha antes de la incidencia se conserva');
select results_eq($$ select status::text from public.bookings where id = pg_temp.id('d1') $$,
  $$ values ('pendiente_confirmacion') $$, 'resolver no cambia la reserva');
select is((select count(*)::int from public.reviews), 0, 'ni crea calificaciones');
select results_eq($$ select coalesce(rating_avg, 0), rating_count from public.tutor_profiles
  where user_id = 'a9000000-0000-0000-0000-0000000000f1' $$, $$ values (0::numeric, 0) $$, 'ni toca la calificación del tutor');
select pg_temp.logout();
select set_config('request.jwt.claims', '', true);
select throws_ok($$ update public.booking_incidents set description = 'Otra cosa distinta.' where id = pg_temp.id('iS') $$,
  '42501', null, 'lo reportado no se modifica (ni el equipo)');
select throws_ok($$ update public.booking_incidents set status = 'pendiente_revision' where id = pg_temp.id('iT') $$,
  'TU035', null, 'una desestimada no se reabre');

select * from finish();
rollback;

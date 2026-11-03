-- Tutorea · Fase 14.10 · fotografías de tutores en Storage (migración 24)
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(36);

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

-- ---------------------------------------------------------------------------
-- Rutas de las fotografías
-- ---------------------------------------------------------------------------
insert into public._ids
select 'tpT', id from public.tutor_profiles where user_id = 'a9000000-0000-0000-0000-0000000000f1';
insert into public._ids
select 'tpT2', id from public.tutor_profiles where user_id = 'a9000000-0000-0000-0000-0000000000f2';
insert into public._ids
select 'tpTC', id from public.tutor_profiles where user_id = 'c9000000-0000-0000-0000-0000000000f1';
create function pg_temp.p(p_key text, p_uni text, p_file text) returns text language sql as $$
  select p_uni || '/' || pg_temp.id(p_key) || '/' || p_file
$$;
-- Universidades
create function pg_temp.ua() returns text language sql as $$ select 'a9000000-0000-0000-0000-000000000001' $$;
create function pg_temp.uc() returns text language sql as $$ select 'c9000000-0000-0000-0000-000000000001' $$;
create function pg_temp.put(p_name text) returns void language sql as $$
  insert into storage.objects (bucket_id, name, metadata)
  values ('tutor-photos', p_name, '{"mimetype":"image/jpeg","size":1000}')
$$;

-- Bucket privado con límites del servidor
select is((select public from storage.buckets where id = 'tutor-photos'), false, 'el bucket tutor-photos es privado');
select is((select file_size_limit from storage.buckets where id = 'tutor-photos'), 2097152::bigint,
  'límite de 2 MB en el servidor');
select is((select allowed_mime_types from storage.buckets where id = 'tutor-photos'),
  array['image/jpeg', 'image/png', 'image/webp'], 'solo JPEG, PNG y WebP');

-- ---------------------------------------------------------------------------
-- Subir (Storage RLS)
-- ---------------------------------------------------------------------------
select pg_temp.login('a9000000-0000-0000-0000-0000000000f1');
select lives_ok($$ select pg_temp.put(pg_temp.p('tpT', pg_temp.ua(), 'a1.jpg')) $$,
  'el tutor sube una foto a su carpeta');
select lives_ok($$ select pg_temp.put(pg_temp.p('tpT', pg_temp.ua(), 'a2.webp')) $$, 'acepta WebP');
select throws_ok($$ select pg_temp.put(pg_temp.p('tpT2', pg_temp.ua(), 'x.jpg')) $$,
  '42501', null, 'no sube a la carpeta de otro tutor');
select throws_ok($$ select pg_temp.put(pg_temp.p('tpT', pg_temp.uc(), 'x.jpg')) $$,
  '42501', null, 'no sube a la carpeta de otra universidad');
select throws_ok($$ select pg_temp.put(pg_temp.p('tpT', pg_temp.ua(), 'x.gif')) $$,
  '42501', null, 'rechaza extensiones no permitidas');
select throws_ok($$ select pg_temp.put(pg_temp.p('tpT', pg_temp.ua(), '../x.jpg')) $$,
  '42501', null, 'rechaza nombres con rutas');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('otro', 'a/b/c.jpg') $$,
  '42501', null, 'no escribe en otros buckets');
select pg_temp.logout();

select pg_temp.login('a9000000-0000-0000-0000-0000000000e1');
select throws_ok($$ select pg_temp.put(pg_temp.p('tpT', pg_temp.ua(), 'e.jpg')) $$,
  '42501', null, 'un estudiante sin perfil de tutor no sube fotos');
select pg_temp.logout();

-- ---------------------------------------------------------------------------
-- Fijar la foto del perfil
-- ---------------------------------------------------------------------------
select pg_temp.login('a9000000-0000-0000-0000-0000000000f1');
select is(public.set_tutor_photo(pg_temp.p('tpT', pg_temp.ua(), 'a1.jpg')), null::text,
  'fija la foto (no había anterior)');
select is((select photo_path from public.tutor_profiles where id = pg_temp.id('tpT')),
  pg_temp.p('tpT', pg_temp.ua(), 'a1.jpg'), 'photo_path guarda solo la ruta');
select is(public.set_tutor_photo(pg_temp.p('tpT', pg_temp.ua(), 'a2.webp')),
  pg_temp.p('tpT', pg_temp.ua(), 'a1.jpg'), 'reemplazar devuelve la ruta anterior para borrarla');
select ok(exists (
  select 1 from pg_policies
  where schemaname = 'storage' and tablename = 'objects'
    and policyname = 'tutor_photos_delete_owner' and cmd = 'DELETE'
    and qual like '%can_write_tutor_photo%'
), 'la política permite borrar solo al dueño del perfil');
select is((select count(*)::int from storage.objects where name like pg_temp.ua() || '/' || pg_temp.id('tpT') || '/%'),
  2, 'el objeto anterior queda pendiente de borrado mediante Storage API');
select throws_ok($$ select public.set_tutor_photo(pg_temp.p('tpT', pg_temp.ua(), 'noexiste.jpg')) $$,
  'TU051', null, 'no acepta una ruta sin archivo');
select throws_ok($$ select public.set_tutor_photo(pg_temp.p('tpT2', pg_temp.ua(), 'a1.jpg')) $$,
  'TU051', null, 'no acepta la carpeta de otro tutor');
select throws_ok($$ update public.tutor_profiles set photo_path = 'cualquier/cosa.jpg' where id = pg_temp.id('tpT') $$,
  '42501', null, 'la app no cambia photo_path con un update directo');
select pg_temp.logout();

select pg_temp.login('a9000000-0000-0000-0000-0000000000e1');
select throws_ok($$ select public.set_tutor_photo(null) $$, 'TU050', null,
  'sin perfil de tutor no hay foto que fijar');
-- Misma universidad: ve el objeto (para pedir la URL firmada).
select is((select count(*)::int from storage.objects where bucket_id = 'tutor-photos'), 2,
  'un estudiante de la misma universidad ve los objetos de fotos');
select ok(exists (
  select 1 from pg_policies
  where schemaname = 'storage' and tablename = 'objects'
    and policyname = 'tutor_photos_delete_owner' and cmd = 'DELETE'
    and qual like '%can_write_tutor_photo%'
), 'la política de borrado exige ser dueño del perfil');
select pg_temp.logout();
select is((select count(*)::int from storage.objects where bucket_id = 'tutor-photos'), 2,
  'la prueba SQL no borra objetos; la autorización se aplica mediante Storage API');

select pg_temp.login('c9000000-0000-0000-0000-0000000000e1');
select is((select count(*)::int from storage.objects where bucket_id = 'tutor-photos'), 0,
  'otra universidad no ve la foto');
select pg_temp.logout();

select pg_temp.login('a9000000-0000-0000-0000-0000000000f2');
select ok(not public.can_write_tutor_photo(pg_temp.p('tpT', pg_temp.ua(), 'a2.webp')),
  'otro tutor no tiene permiso de escritura sobre la foto ajena');
select ok(exists (
  select 1 from pg_policies
  where schemaname = 'storage' and tablename = 'objects'
    and policyname = 'tutor_photos_delete_owner' and cmd = 'DELETE'
    and qual like '%can_write_tutor_photo%'
), 'el borrado está restringido por la política de propietario');
select pg_temp.logout();
select is((select count(*)::int from storage.objects where bucket_id = 'tutor-photos'), 2,
  'otro tutor no modifica ni elimina objetos mediante la política de Storage');

-- Eliminar la foto
select pg_temp.login('a9000000-0000-0000-0000-0000000000f1');
select is(public.set_tutor_photo(null), pg_temp.p('tpT', pg_temp.ua(), 'a2.webp'), 'quitar la foto devuelve la ruta para borrarla');
select is((select photo_path from public.tutor_profiles where id = pg_temp.id('tpT')), null::text, 'el perfil queda sin foto');
select ok(public.can_write_tutor_photo(pg_temp.p('tpT', pg_temp.ua(), 'a2.webp')),
  'el dueño conserva permiso para borrar su propio objeto mediante Storage API');
select ok(exists (
  select 1 from pg_policies
  where schemaname = 'storage' and tablename = 'objects'
    and policyname = 'tutor_photos_delete_owner' and cmd = 'DELETE'
    and qual like '%can_write_tutor_photo%'
), 'la política de borrado del bucket sigue activa');
select pg_temp.logout();
select is((select count(*)::int from storage.objects where bucket_id = 'tutor-photos'), 2,
  'los objetos se eliminan mediante Storage API, no con SQL directo');

-- Un tutor nuevo nace sin foto aunque la app mande una ruta.
select is((select photo_path from public.tutor_profiles where id = pg_temp.id('tpT2')), null::text,
  'perfil nuevo sin foto');
-- El resto de la guarda sigue igual.
select pg_temp.login('a9000000-0000-0000-0000-0000000000f1');
select throws_ok($$ update public.tutor_profiles set legacy_id = 'x' where id = pg_temp.id('tpT') $$,
  '42501', null, 'la guarda del perfil sigue protegiendo los demás campos');
select throws_ok($$ update public.tutor_profiles set rating_avg = 5, rating_count = 9 where id = pg_temp.id('tpT') $$,
  '42501', null, 'la calificación sigue siendo del servidor');
select pg_temp.logout();

-- Sin claves de anon
select throws_ok($$ set local role anon; select public.set_tutor_photo(null) $$, '42501', null,
  'anon no puede fijar fotos');

select * from finish();
rollback;


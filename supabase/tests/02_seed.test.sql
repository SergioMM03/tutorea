-- Tutorea · Fase 14.2 · Pruebas del catálogo inicial (supabase/seed.sql)
-- Verifica el contenido exacto del seed sin depender de que existan o no usuarios.
-- La ejecución repetida del seed completo se prueba con scripts/check_seed_idempotency_*.sql.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(5);

select results_eq(
  $$ select slug, name, short_name, country, is_active from public.universities where slug = 'esen' $$,
  $$ values ('esen', 'Escuela Superior de Economía y Negocios (ESEN)', 'ESEN', 'El Salvador', true) $$,
  'ESEN existe, activa y con los datos del seed');

select set_eq(
  $$ select c.slug, c.name from public.careers c
     join public.universities u on u.id = c.university_id where u.slug = 'esen' $$,
  $$ values ('esen-eyn', 'Licenciatura en Economía y Negocios'),
            ('esen-ing-negocios', 'Ingeniería de Negocios'),
            ('esen-juridicas', 'Licenciatura en Ciencias Jurídicas'),
            ('esen-software', 'Ingeniería de Software y Negocios Digitales') $$,
  'ESEN tiene exactamente sus 4 carreras');

select set_eq(
  $$ select s.slug, s.name, s.category, c.slug as career_slug, s.academic_year::int as academic_year
     from public.subjects s
     join public.universities u on u.id = s.university_id
     left join public.careers c on c.id = s.career_id
     where u.slug = 'esen' $$,
  $$ values ('mat', 'Matemáticas',         'Matemáticas', null::text,          1),
            ('est', 'Estadística',         'Matemáticas', null,                2),
            ('cal', 'Cálculo',             'Matemáticas', null,                1),
            ('alg', 'Álgebra lineal',      'Matemáticas', null,                1),
            ('eco', 'Economía',            'Economía',    'esen-eyn',          1),
            ('mic', 'Microeconomía',       'Economía',    'esen-eyn',          2),
            ('mac', 'Macroeconomía',       'Economía',    'esen-eyn',          2),
            ('ecm', 'Econometría',         'Economía',    'esen-eyn',          3),
            ('fin', 'Finanzas',            'Negocios',    'esen-ing-negocios', 3),
            ('con', 'Contabilidad',        'Negocios',    null,                1),
            ('anf', 'Análisis financiero', 'Negocios',    'esen-ing-negocios', 3),
            ('pro', 'Programación',        'Tecnología',  'esen-software',     1),
            ('bdd', 'Bases de datos',      'Tecnología',  'esen-software',     2) $$,
  'ESEN tiene exactamente sus 13 materias con categoría, carrera y año');

select is(
  (select count(*)::int from public.subjects s
   join public.careers c on c.id = s.career_id
   where c.university_id <> s.university_id),
  0, 'ninguna materia apunta a una carrera de otra universidad');

select is((select count(*)::int from public.universities where slug = 'esen'), 1, 'ESEN no está duplicada');

select * from finish();
rollback;

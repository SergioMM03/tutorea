-- Tutorea · Fase 14.2 · Seed del catálogo
-- ESEN, sus 4 carreras y sus 13 materias, con los mismos nombres, categorías y años
-- que LocalSeed (lib/data/local/local_seed.dart). El slug es el id viejo.
--
-- Repetible: si se ejecuta dos veces actualiza en lugar de duplicar.
-- No crea usuarios, perfiles de tutor ni calificaciones (esas van en 14.3 y 14.4).

begin;

insert into public.universities (slug, name, short_name, country, is_active)
values ('esen', 'Escuela Superior de Economía y Negocios (ESEN)', 'ESEN', 'El Salvador', true)
on conflict (slug) do update
  set name = excluded.name,
      short_name = excluded.short_name,
      country = excluded.country,
      is_active = excluded.is_active;

insert into public.careers (university_id, slug, name)
select u.id, c.slug, c.name
from public.universities u
cross join (values
  ('esen-eyn',          'Licenciatura en Economía y Negocios'),
  ('esen-ing-negocios', 'Ingeniería de Negocios'),
  ('esen-juridicas',    'Licenciatura en Ciencias Jurídicas'),
  ('esen-software',     'Ingeniería de Software y Negocios Digitales')
) as c (slug, name)
where u.slug = 'esen'
on conflict (university_id, slug) do update
  set name = excluded.name;

-- career_slug null = materia común a varias carreras.
-- Los años son los aproximados del seed local.
insert into public.subjects (university_id, career_id, slug, name, category, academic_year)
select u.id, c.id, s.slug, s.name, s.category, s.academic_year
from public.universities u
cross join (values
  ('mat', 'Matemáticas',         'Matemáticas', null,                1::smallint),
  ('est', 'Estadística',         'Matemáticas', null,                2::smallint),
  ('cal', 'Cálculo',             'Matemáticas', null,                1::smallint),
  ('alg', 'Álgebra lineal',      'Matemáticas', null,                1::smallint),
  ('eco', 'Economía',            'Economía',    'esen-eyn',          1::smallint),
  ('mic', 'Microeconomía',       'Economía',    'esen-eyn',          2::smallint),
  ('mac', 'Macroeconomía',       'Economía',    'esen-eyn',          2::smallint),
  ('ecm', 'Econometría',         'Economía',    'esen-eyn',          3::smallint),
  ('fin', 'Finanzas',            'Negocios',    'esen-ing-negocios', 3::smallint),
  ('con', 'Contabilidad',        'Negocios',    null,                1::smallint),
  ('anf', 'Análisis financiero', 'Negocios',    'esen-ing-negocios', 3::smallint),
  ('pro', 'Programación',        'Tecnología',  'esen-software',     1::smallint),
  ('bdd', 'Bases de datos',      'Tecnología',  'esen-software',     2::smallint)
) as s (slug, name, category, career_slug, academic_year)
left join public.careers c
  on c.university_id = u.id and c.slug = s.career_slug
where u.slug = 'esen'
on conflict (university_id, slug) do update
  set career_id = excluded.career_id,
      name = excluded.name,
      category = excluded.category,
      academic_year = excluded.academic_year;

commit;

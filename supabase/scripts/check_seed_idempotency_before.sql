-- Tutorea · Comprobación de que supabase/seed.sql se puede ejecutar dos veces seguidas.
-- No es una prueba pgTAP: se ejecuta con psql concatenando tres archivos en una sola
-- sesión (ver supabase/README.md). Parte 1 de 2 (antes): foto del catálogo antes de repetir.
\set ON_ERROR_STOP on

create temp table seed_snapshot as
select 'u' as kind, id, slug, name || '|' || short_name || '|' || country || '|' || is_active as data
from public.universities where slug = 'esen'
union all
select 'c', c.id, c.slug, c.name
from public.careers c join public.universities u on u.id = c.university_id where u.slug = 'esen'
union all
select 's', s.id, s.slug, s.name || '|' || s.category || '|' || coalesce(s.career_id::text, '-') || '|' || coalesce(s.academic_year::text, '-')
from public.subjects s join public.universities u on u.id = s.university_id where u.slug = 'esen';

do $$
begin
  if (select count(*) from seed_snapshot) <> 18 then
    raise exception 'Antes de repetir el seed se esperaban 1 + 4 + 13 filas y hay %', (select count(*) from seed_snapshot);
  end if;
end $$;

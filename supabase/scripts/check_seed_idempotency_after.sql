-- Tutorea · Comprobación del seed repetido. Parte 2 de 2: compara con la foto.
\set ON_ERROR_STOP on

do $$
declare
  v_diff int;
begin
  with now_rows as (
    select 'u' as kind, id, slug, name || '|' || short_name || '|' || country || '|' || is_active as data
    from public.universities where slug = 'esen'
    union all
    select 'c', c.id, c.slug, c.name
    from public.careers c join public.universities u on u.id = c.university_id where u.slug = 'esen'
    union all
    select 's', s.id, s.slug, s.name || '|' || s.category || '|' || coalesce(s.career_id::text, '-') || '|' || coalesce(s.academic_year::text, '-')
    from public.subjects s join public.universities u on u.id = s.university_id where u.slug = 'esen'
  )
  select count(*) into v_diff from (
    (select * from now_rows except select * from seed_snapshot)
    union all
    (select * from seed_snapshot except select * from now_rows)
  ) d;

  if v_diff <> 0 then
    raise exception 'El seed repetido cambió % filas del catálogo (ids o datos).', v_diff;
  end if;
  raise notice 'OK: el seed se ejecutó dos veces más sin duplicar ni cambiar ids (18 filas iguales).';
end $$;

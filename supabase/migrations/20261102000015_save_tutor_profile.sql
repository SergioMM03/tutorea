-- Tutorea · Fase 14.7 · 15 save_tutor_profile
-- Guarda el perfil de tutor del usuario con sesión, sus materias y su
-- disponibilidad en UNA transacción: si algo falla (horarios cruzados, materia
-- de otra universidad, rol no tutor), no queda nada a medias.
--
-- SECURITY INVOKER: corre como el usuario, con RLS, permisos de columna y los
-- triggers de las migraciones 12 a 14. No recibe user_id, rol ni universidad:
-- el perfil siempre es el de auth.uid().
--
-- p_slots: [{"weekday":1,"start_minute":480,"end_minute":720}, ...]

create or replace function public.save_tutor_profile(
  p_description      text,
  p_hourly_rate      numeric,
  p_offers_in_person boolean,
  p_offers_virtual   boolean,
  p_is_active        boolean,
  p_subject_ids      uuid[],
  p_slots            jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_id       uuid;
  v_subjects uuid[] := coalesce(p_subject_ids, '{}');
begin
  if v_uid is null then
    raise exception 'Inicia sesión para guardar tu perfil de tutor.' using errcode = '42501';
  end if;
  if p_slots is null or jsonb_typeof(p_slots) <> 'array' then
    raise exception 'Disponibilidad no válida.' using errcode = '22023';
  end if;

  select tp.id into v_id from public.tutor_profiles tp where tp.user_id = v_uid;

  if v_id is null then
    insert into public.tutor_profiles
      (description, hourly_rate, offers_in_person, offers_virtual, is_active)
    values
      (coalesce(p_description, ''), p_hourly_rate, p_offers_in_person, p_offers_virtual, p_is_active)
    returning id into v_id;
  else
    update public.tutor_profiles
    set description = coalesce(p_description, ''),
        hourly_rate = p_hourly_rate,
        offers_in_person = p_offers_in_person,
        offers_virtual = p_offers_virtual,
        is_active = p_is_active
    where id = v_id;
  end if;

  -- Materias: quita las que ya no imparte y agrega las nuevas.
  delete from public.tutor_subjects ts
  where ts.tutor_profile_id = v_id and not (ts.subject_id = any (v_subjects));

  insert into public.tutor_subjects (tutor_profile_id, subject_id)
  select v_id, s.subject_id
  from (select distinct unnest(v_subjects) as subject_id) s
  where not exists (
    select 1 from public.tutor_subjects ts
    where ts.tutor_profile_id = v_id and ts.subject_id = s.subject_id
  );

  -- Disponibilidad: se reemplaza completa (la exclusión impide cruces).
  delete from public.availability_slots a where a.tutor_profile_id = v_id;

  insert into public.availability_slots (tutor_profile_id, weekday, start_minute, end_minute)
  select v_id, (e ->> 'weekday')::smallint, (e ->> 'start_minute')::smallint, (e ->> 'end_minute')::smallint
  from jsonb_array_elements(p_slots) e;

  return v_id;
end;
$$;

revoke all on function public.save_tutor_profile(text, numeric, boolean, boolean, boolean, uuid[], jsonb)
  from public, anon;
grant execute on function public.save_tutor_profile(text, numeric, boolean, boolean, boolean, uuid[], jsonb)
  to authenticated;

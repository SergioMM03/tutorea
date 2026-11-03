-- Tutorea · Fase 14.10 · Datos de demostración (tutores de ESEN)
--
-- NO es una migración ni crea cuentas: completa el perfil de tutor, sus materias
-- y su disponibilidad para cuentas de demostración que YA existen en Supabase
-- Auth (ver supabase/README.md, "Datos de demostración"). Sin contraseñas, sin
-- reservas, sin reseñas ni calificaciones: los tutores aparecen como «Nuevo».
--
-- Se ejecuta en el SQL Editor del panel (rol postgres). Repetible: actualiza en
-- lugar de duplicar. Las cuentas que no existan se omiten con un aviso.

do $$
declare
  v_uni   uuid;
  v_user  uuid;
  v_tp    uuid;
  r       record;
begin
  select id into v_uni from public.universities where slug = 'esen';
  if v_uni is null then
    raise exception 'Falta la universidad esen: ejecuta primero supabase/seed.sql.';
  end if;

  for r in
    select * from (values
      ('demo.valeria@tutorea.app', 'Estudiante de tercer año de Economía. Explico Estadística y Microeconomía con ejercicios prácticos.',
        10.00, true,  true,  array['est', 'mat', 'mic'], '[[1,840,1080],[3,840,1080],[5,480,720]]'::jsonb),
      ('demo.daniel@tutorea.app',  'Estudiante de Ingeniería de Negocios. Finanzas y Contabilidad paso a paso.',
        12.00, true,  false, array['fin', 'con', 'anf'], '[[2,900,1140],[4,900,1140]]'::jsonb),
      ('demo.camila@tutorea.app',  'Me gusta enseñar Cálculo y Álgebra lineal con ejemplos visuales.',
        9.00,  false, true,  array['cal', 'alg', 'mat'], '[[1,1080,1260],[2,1080,1260],[6,540,780]]'::jsonb),
      ('demo.andres@tutorea.app',  'Ingeniería de Software. Programación desde cero y Bases de datos.',
        11.00, true,  true,  array['pro', 'bdd'],        '[[3,600,840],[5,600,840]]'::jsonb)
    ) as t(email, description, rate, in_person, virtual, subjects, slots)
  loop
    select p.id into v_user
    from auth.users u join public.profiles p on p.id = u.id
    where lower(u.email) = r.email and p.university_id = v_uni and p.role <> 'administrador';
    if v_user is null then
      raise notice 'Se omite %: crea primero la cuenta (ver README).', r.email;
      continue;
    end if;

    insert into public.tutor_profiles (user_id, university_id, description, hourly_rate,
                                       offers_in_person, offers_virtual, is_active)
    values (v_user, v_uni, r.description, r.rate, r.in_person, r.virtual, true)
    on conflict (user_id) do update
      set description = excluded.description,
          hourly_rate = excluded.hourly_rate,
          offers_in_person = excluded.offers_in_person,
          offers_virtual = excluded.offers_virtual,
          is_active = true
    returning id into v_tp;

    delete from public.tutor_subjects where tutor_profile_id = v_tp;
    insert into public.tutor_subjects (tutor_profile_id, subject_id, university_id)
    select v_tp, s.id, v_uni from public.subjects s
    where s.university_id = v_uni and s.slug = any (r.subjects);

    delete from public.availability_slots where tutor_profile_id = v_tp;
    insert into public.availability_slots (tutor_profile_id, weekday, start_minute, end_minute)
    select v_tp, (x ->> 0)::smallint, (x ->> 1)::smallint, (x ->> 2)::smallint
    from jsonb_array_elements(r.slots) x;

    raise notice 'Tutor de demostración listo: %', r.email;
  end loop;
end
$$;

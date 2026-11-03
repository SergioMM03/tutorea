-- Tutorea · Fase 14.10 · 24 fotografías de tutores (Supabase Storage)
--
-- Bucket PRIVADO `tutor-photos`: JPEG, PNG o WebP de hasta 2 MB (los límites los
-- valida el servidor de Storage al subir). Ruta obligatoria:
--   <university_id>/<tutor_profile_id>/<nombre>.<jpg|jpeg|png|webp>
-- La app nunca guarda imágenes en PostgreSQL: tutor_profiles.photo_path solo
-- guarda la ruta del objeto. Se muestran con URLs firmadas (createSignedUrl).
--
-- Storage RLS (storage.objects):
--   - ver: cuentas de la MISMA universidad (primer segmento de la ruta);
--   - subir, reemplazar y borrar: solo el dueño del perfil de tutor de la ruta.
--
-- set_tutor_photo(p_path): fija o quita la foto del perfil propio (auth.uid()),
-- solo con una ruta de su carpeta que ya exista en el bucket. La app borra el
-- archivo anterior después (Storage no permite borrar objetos desde SQL), así
-- no quedan archivos huérfanos al reemplazar.
--
-- prepare_tutor_profile: igual que en la migración 22, salvo que photo_path
-- puede cambiar si y solo si queda null o es una ruta válida de ese perfil
-- (antes no podía cambiar nunca fuera de una sesión privilegiada).
--
-- Códigos de error:
--   TU050 no tienes perfil de tutor
--   TU051 ruta de fotografía no válida o archivo inexistente

-- ---------------------------------------------------------------------------
-- Bucket
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('tutor-photos', 'tutor-photos', false, 2097152,
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- ---------------------------------------------------------------------------
-- Ayudantes
-- ---------------------------------------------------------------------------

-- ¿La ruta tiene la forma <universidad>/<perfil>/<archivo>.<ext> de ESE perfil?
create or replace function public.tutor_photo_path_matches(
  p_path text, p_university_id uuid, p_tutor_profile_id uuid)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_path is not null
     and p_path ~ ('^' || p_university_id::text || '/' || p_tutor_profile_id::text
                   || '/[A-Za-z0-9_-]{1,80}\.(jpg|jpeg|png|webp)$');
$$;

revoke all on function public.tutor_photo_path_matches(text, uuid, uuid) from public, anon;
grant execute on function public.tutor_photo_path_matches(text, uuid, uuid) to authenticated;

-- ¿La cuenta con sesión puede escribir ese objeto? (su universidad y su perfil)
create or replace function public.can_write_tutor_photo(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.tutor_profiles tp
    where tp.user_id = (select auth.uid())
      and public.tutor_photo_path_matches(p_name, tp.university_id, tp.id)
  );
$$;

revoke all on function public.can_write_tutor_photo(text) from public, anon;
grant execute on function public.can_write_tutor_photo(text) to authenticated;

-- ¿Existe el objeto en el bucket y es de la carpeta propia? (definer: no
-- depende de la RLS de quien llama; solo responde sobre la carpeta propia)
create or replace function public.own_tutor_photo_exists(p_path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.can_write_tutor_photo(p_path)
     and exists (
       select 1 from storage.objects o where o.bucket_id = 'tutor-photos' and o.name = p_path
     );
$$;

revoke all on function public.own_tutor_photo_exists(text) from public, anon;
grant execute on function public.own_tutor_photo_exists(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Storage RLS
-- ---------------------------------------------------------------------------
drop policy if exists tutor_photos_select_same_university on storage.objects;
create policy tutor_photos_select_same_university
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'tutor-photos'
    and (storage.foldername(name))[1] = (select public.current_university_id())::text
  );

drop policy if exists tutor_photos_insert_owner on storage.objects;
create policy tutor_photos_insert_owner
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'tutor-photos' and public.can_write_tutor_photo(name));

drop policy if exists tutor_photos_update_owner on storage.objects;
create policy tutor_photos_update_owner
  on storage.objects for update
  to authenticated
  using (bucket_id = 'tutor-photos' and public.can_write_tutor_photo(name))
  with check (bucket_id = 'tutor-photos' and public.can_write_tutor_photo(name));

drop policy if exists tutor_photos_delete_owner on storage.objects;
create policy tutor_photos_delete_owner
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'tutor-photos' and public.can_write_tutor_photo(name));

-- ---------------------------------------------------------------------------
-- prepare_tutor_profile (copia de la migración 22; solo cambia photo_path)
-- ---------------------------------------------------------------------------
create or replace function public.prepare_tutor_profile()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_privileged boolean := public.is_privileged_session();
  v_role       public.user_role;
  v_avg        numeric;
  v_count      integer;
begin
  if tg_op = 'INSERT' then
    if v_privileged then
      select p.role into v_role from public.profiles p where p.id = new.user_id;
      if new.university_id is null then
        select p.university_id into new.university_id from public.profiles p where p.id = new.user_id;
      end if;
    else
      new.user_id := auth.uid();
      if new.user_id is null then
        raise exception 'Inicia sesión para crear tu perfil de tutor.' using errcode = '42501';
      end if;
      new.university_id := public.current_university_id();
      v_role := public.current_user_role();
      new.rating_avg := null;
      new.rating_count := 0;
      new.photo_path := null;
      new.legacy_id := null;
    end if;
    if v_role is null then
      raise exception 'Tu cuenta no tiene perfil; no puede ofrecer tutorías.' using errcode = '42501';
    end if;
    if v_role = 'administrador' then
      raise exception 'Una cuenta administradora no puede ofrecer tutorías.' using errcode = '42501';
    end if;
    return new;
  end if;

  -- UPDATE
  if not v_privileged then
    if (new.rating_avg, new.rating_count) is distinct from (old.rating_avg, old.rating_count) then
      select round(avg(r.rating)::numeric, 2), count(*)::integer into v_avg, v_count
      from public.reviews r where r.tutor_profile_id = old.id;
      if (new.rating_avg, new.rating_count) is distinct from (v_avg, v_count) then
        raise exception 'La calificación del tutor la calcula el servidor.' using errcode = '42501';
      end if;
    end if;
    -- Fotografía: solo null o una ruta existente de la carpeta de ESTE perfil.
    if new.photo_path is distinct from old.photo_path and new.photo_path is not null then
      if not public.tutor_photo_path_matches(new.photo_path, old.university_id, old.id) then
        raise exception 'Fotografía no válida.' using errcode = 'TU051';
      end if;
      if not public.own_tutor_photo_exists(new.photo_path) then
        raise exception 'Fotografía no válida.' using errcode = 'TU051';
      end if;
    end if;
    if new.id is distinct from old.id
       or new.user_id is distinct from old.user_id
       or new.university_id is distinct from old.university_id
       or new.legacy_id is distinct from old.legacy_id then
      raise exception 'Ese dato del perfil de tutor no se puede cambiar desde la app.' using errcode = '42501';
    end if;
    if old.user_id is distinct from auth.uid()
       and (new.description, new.hourly_rate, new.offers_in_person, new.offers_virtual, new.photo_path)
           is distinct from (old.description, old.hourly_rate, old.offers_in_person, old.offers_virtual, old.photo_path) then
      raise exception 'Un administrador solo puede activar o desactivar perfiles de tutor.' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.prepare_tutor_profile() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- set_tutor_photo: fija (ruta) o quita (null) la foto del perfil propio.
-- Devuelve la ruta anterior para que la app borre ese archivo.
-- ---------------------------------------------------------------------------
create or replace function public.set_tutor_photo(p_path text default null)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_profile public.tutor_profiles%rowtype;
  v_path    text := nullif(btrim(coalesce(p_path, '')), '');
begin
  if v_uid is null then
    raise exception 'Inicia sesión.' using errcode = '42501';
  end if;
  select * into v_profile from public.tutor_profiles tp where tp.user_id = v_uid for update;
  if not found then
    raise exception 'No tienes perfil de tutor.' using errcode = 'TU050';
  end if;
  if v_path is not null then
    if not public.tutor_photo_path_matches(v_path, v_profile.university_id, v_profile.id)
       or not public.own_tutor_photo_exists(v_path) then
      raise exception 'Fotografía no válida.' using errcode = 'TU051';
    end if;
  end if;
  update public.tutor_profiles set photo_path = v_path where id = v_profile.id;
  return v_profile.photo_path;
end;
$$;

revoke all on function public.set_tutor_photo(text) from public, anon;
grant execute on function public.set_tutor_photo(text) to authenticated;

-- Tutorea · Fase 14.9 · 22 reseñas del estudiante al tutor
--
-- Reglas (submit_review):
--   - solo el estudiante de la reserva (auth.uid()); el tutor no se califica;
--   - la reserva debe estar 'completada' y sin incidencias abiertas;
--   - de 1 a 5 estrellas y un comentario opcional;
--   - una sola reseña por reserva; no se edita ni se borra (MVP).
-- El promedio (rating_avg) y el total (rating_count) del tutor los calcula el
-- servidor con un trigger a partir de las reseñas; la app nunca los escribe.
-- Un tutor sin reseñas tiene rating_avg null y rating_count 0 («Nuevo» en la app).
--
-- Privacidad: el perfil público del tutor lee la vista public_reviews (sin
-- estudiante ni reserva). La tabla solo la leen el autor, el tutor calificado y
-- el administrador de la universidad.
--
-- Códigos de error:
--   TU009 reserva no encontrada para esta cuenta
--   TU040 solo el estudiante de la reserva califica
--   TU041 el tutor no puede calificarse a sí mismo
--   TU042 la reserva no está completada
--   TU043 hay una incidencia abierta
--   TU044 ya calificaste esta reserva
--   TU045 la calificación debe ser de 1 a 5 (o el comentario es muy largo)

create table public.reviews (
  id                uuid primary key default gen_random_uuid(),
  booking_id        uuid not null unique,
  university_id     uuid not null,
  tutor_profile_id  uuid not null,
  student_id        uuid not null,
  rating            smallint not null check (rating between 1 and 5),
  comment           text check (comment is null or length(comment) <= 1000),
  created_at        timestamptz not null default now(),
  constraint reviews_booking_fk foreign key (booking_id, university_id)
    references public.bookings (id, university_id) on delete restrict,
  constraint reviews_tutor_fk foreign key (tutor_profile_id, university_id)
    references public.tutor_profiles (id, university_id) on delete restrict,
  constraint reviews_student_fk foreign key (student_id, university_id)
    references public.profiles (id, university_id) on delete restrict
);

create index reviews_tutor_idx on public.reviews (tutor_profile_id, created_at desc);

alter table public.reviews enable row level security;

-- MVP: las reseñas no se editan ni se borran (salvo el equipo, para moderar).
create trigger reviews_history
  before update or delete on public.reviews
  for each row execute function public.prevent_history_changes();

revoke all on table public.reviews from public, anon, authenticated;
grant select on table public.reviews to authenticated;

create policy reviews_select_author_or_tutor
  on public.reviews for select
  to authenticated
  using (
    university_id = (select public.current_university_id())
    and (student_id = (select auth.uid()) or public.owns_tutor_profile(tutor_profile_id))
  );

create policy reviews_select_admin
  on public.reviews for select
  to authenticated
  using (public.is_admin_of(university_id));

-- ---------------------------------------------------------------------------
-- Vista pública (perfil del tutor): sin estudiante ni reserva, misma universidad.
-- Igual que public_profiles (migración 09): corre con los permisos del dueño y
-- filtra por la universidad de la sesión; security_barrier evita que un filtro
-- del cliente se evalúe antes.
-- ---------------------------------------------------------------------------
create view public.public_reviews
with (security_barrier = true)
as
select r.id, r.tutor_profile_id, r.university_id, r.rating, r.comment, r.created_at
from public.reviews r
where r.university_id = public.current_university_id();

comment on view public.public_reviews is
  'Reseñas visibles en el perfil del tutor (sin datos del estudiante). Solo authenticated.';

revoke all on table public.public_reviews from public, anon, authenticated;
grant select on table public.public_reviews to authenticated;

-- ---------------------------------------------------------------------------
-- Promedio y total del tutor, calculados en el servidor.
-- ---------------------------------------------------------------------------
create or replace function public.recalc_tutor_rating()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tutor uuid := case when tg_op = 'DELETE' then old.tutor_profile_id else new.tutor_profile_id end;
begin
  update public.tutor_profiles tp
  set rating_avg = s.avg_rating,
      rating_count = s.total
  from (
    select round(avg(r.rating)::numeric, 2) as avg_rating, count(*)::integer as total
    from public.reviews r where r.tutor_profile_id = v_tutor
  ) s
  where tp.id = v_tutor;
  return null;
end;
$$;

revoke all on function public.recalc_tutor_rating() from public, anon, authenticated;

create trigger reviews_recalc_tutor_rating
  after insert or delete on public.reviews
  for each row execute function public.recalc_tutor_rating();

-- ---------------------------------------------------------------------------
-- prepare_tutor_profile: igual que en la migración 16, con un único cambio en
-- UPDATE: rating_avg y rating_count pueden cambiar si y solo si quedan iguales
-- al cálculo sobre public.reviews (lo que hace recalc_tutor_rating). Así ni la
-- app ni nadie fija una calificación inventada, y el trigger del servidor puede
-- mantenerla al día.
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
    if new.id is distinct from old.id
       or new.user_id is distinct from old.user_id
       or new.university_id is distinct from old.university_id
       or new.legacy_id is distinct from old.legacy_id
       or new.photo_path is distinct from old.photo_path then
      raise exception 'Ese dato del perfil de tutor no se puede cambiar desde la app.' using errcode = '42501';
    end if;
    if old.user_id is distinct from auth.uid()
       and (new.description, new.hourly_rate, new.offers_in_person, new.offers_virtual)
           is distinct from (old.description, old.hourly_rate, old.offers_in_person, old.offers_virtual) then
      raise exception 'Un administrador solo puede activar o desactivar perfiles de tutor.' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.prepare_tutor_profile() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Calificar (solo el estudiante de la reserva)
-- ---------------------------------------------------------------------------
create or replace function public.submit_review(
  p_booking_id uuid,
  p_rating     integer,
  p_comment    text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_booking public.bookings%rowtype;
  v_party   text;
  v_comment text := nullif(btrim(coalesce(p_comment, '')), '');
  v_id      uuid;
begin
  if v_uid is null then
    raise exception 'Inicia sesión para calificar.' using errcode = '42501';
  end if;

  select * into v_booking from public.bookings b where b.id = p_booking_id for update;
  v_party := case when found then public.booking_party(p_booking_id) end;
  if v_party is null then
    raise exception 'No encontramos esa reserva entre las tuyas.' using errcode = 'TU009';
  end if;
  if v_party = 'tutor' then
    raise exception 'El tutor no puede calificarse a sí mismo.' using errcode = 'TU041';
  end if;
  if v_booking.student_id <> v_uid then
    raise exception 'Solo el estudiante de la reserva puede calificar.' using errcode = 'TU040';
  end if;
  if v_booking.status <> 'completada' then
    raise exception 'Solo se califican tutorías completadas.' using errcode = 'TU042';
  end if;
  if public.booking_has_open_incident(p_booking_id) then
    raise exception 'Hay una incidencia abierta; podrás calificar cuando se resuelva.' using errcode = 'TU043';
  end if;
  if exists (select 1 from public.reviews r where r.booking_id = p_booking_id) then
    raise exception 'Ya calificaste esta tutoría.' using errcode = 'TU044';
  end if;
  if p_rating is null or p_rating < 1 or p_rating > 5
     or (v_comment is not null and length(v_comment) > 1000) then
    raise exception 'La calificación debe ser de 1 a 5 estrellas (comentario hasta 1000 caracteres).'
      using errcode = 'TU045';
  end if;

  insert into public.reviews (booking_id, university_id, tutor_profile_id, student_id, rating, comment)
  values (p_booking_id, v_booking.university_id, v_booking.tutor_profile_id, v_uid, p_rating, v_comment)
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.submit_review(uuid, integer, text) from public, anon;
grant execute on function public.submit_review(uuid, integer, text) to authenticated;

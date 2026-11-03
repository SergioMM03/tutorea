-- Tutorea · Fase 14.7 · 13 tutor_subjects
-- Materias que imparte cada tutor. university_id lo fija el servidor desde el
-- perfil de tutor y las FK compuestas obligan a que la materia sea de la misma
-- universidad que el tutor.

create table public.tutor_subjects (
  tutor_profile_id  uuid not null,
  subject_id        uuid not null,
  university_id     uuid not null,
  created_at        timestamptz not null default now(),
  primary key (tutor_profile_id, subject_id),
  constraint tutor_subjects_profile_fk foreign key (tutor_profile_id, university_id)
    references public.tutor_profiles (id, university_id) on delete cascade,
  constraint tutor_subjects_subject_fk foreign key (subject_id, university_id)
    references public.subjects (id, university_id) on delete restrict
);

create index tutor_subjects_subject_idx on public.tutor_subjects (subject_id);
create index tutor_subjects_university_idx on public.tutor_subjects (university_id);

alter table public.tutor_subjects enable row level security;

-- university_id siempre desde el perfil de tutor (nunca del cliente).
create or replace function public.prepare_tutor_subject()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  select tp.university_id into new.university_id
  from public.tutor_profiles tp
  where tp.id = new.tutor_profile_id;
  if new.university_id is null then
    raise exception 'Perfil de tutor no encontrado.' using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function public.prepare_tutor_subject() from public, anon, authenticated;

create trigger tutor_subjects_prepare
  before insert on public.tutor_subjects
  for each row execute function public.prepare_tutor_subject();

revoke all on table public.tutor_subjects from public, anon, authenticated;
grant select, delete on table public.tutor_subjects to authenticated;
grant insert (tutor_profile_id, subject_id) on table public.tutor_subjects to authenticated;
-- Sin update: se borra y se vuelve a crear.

create policy tutor_subjects_select_university
  on public.tutor_subjects for select
  to authenticated
  using (university_id = (select public.current_university_id()));

create policy tutor_subjects_insert_owner
  on public.tutor_subjects for insert
  to authenticated
  with check (exists (
    select 1 from public.tutor_profiles tp
    where tp.id = tutor_profile_id and tp.user_id = (select auth.uid())
  ));

create policy tutor_subjects_delete_owner
  on public.tutor_subjects for delete
  to authenticated
  using (exists (
    select 1 from public.tutor_profiles tp
    where tp.id = tutor_profile_id and tp.user_id = (select auth.uid())
  ));

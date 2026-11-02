-- Tutorea · Fase 14.2 · 05 careers y subjects

create table public.careers (
  id             uuid primary key default gen_random_uuid(),
  university_id  uuid not null references public.universities (id) on delete restrict,
  slug           text not null check (slug ~ '^[a-z0-9-]+$'),
  name           text not null check (length(trim(name)) between 2 and 200),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  -- Destino de las FK compuestas (career_id, university_id): impide mezclar universidades.
  constraint careers_id_university_key unique (id, university_id),
  constraint careers_university_slug_key unique (university_id, slug),
  constraint careers_university_name_key unique (university_id, name)
);

create table public.subjects (
  id             uuid primary key default gen_random_uuid(),
  university_id  uuid not null references public.universities (id) on delete restrict,
  career_id      uuid,  -- null = materia común a varias carreras
  slug           text not null check (slug ~ '^[a-z0-9-]+$'),
  name           text not null check (length(trim(name)) between 2 and 200),
  category       text not null check (length(trim(category)) between 2 and 80),
  academic_year  smallint check (academic_year between 1 and 10),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint subjects_id_university_key unique (id, university_id),
  constraint subjects_university_slug_key unique (university_id, slug),
  -- La carrera, si existe, debe ser de la misma universidad.
  constraint subjects_career_fk foreign key (career_id, university_id)
    references public.careers (id, university_id) on delete restrict
);

create index subjects_university_category_idx on public.subjects (university_id, category);
create index subjects_career_idx on public.subjects (career_id);

alter table public.careers enable row level security;
alter table public.subjects enable row level security;

create trigger careers_set_updated_at
  before update on public.careers
  for each row execute function public.set_updated_at();

create trigger subjects_set_updated_at
  before update on public.subjects
  for each row execute function public.set_updated_at();

-- Lectura: anon y authenticated (el registro necesita las carreras antes del login).
-- Escritura: solo authenticated y solo las columnas indicadas; las políticas de la
-- migración 11 la limitan al administrador de esa universidad.
revoke all on table public.careers, public.subjects from public, anon, authenticated;
grant select on table public.careers, public.subjects to anon, authenticated;

grant insert (university_id, slug, name) on table public.careers to authenticated;
grant update (slug, name) on table public.careers to authenticated;
grant delete on table public.careers to authenticated;

grant insert (university_id, career_id, slug, name, category, academic_year)
  on table public.subjects to authenticated;
grant update (career_id, slug, name, category, academic_year)
  on table public.subjects to authenticated;
grant delete on table public.subjects to authenticated;

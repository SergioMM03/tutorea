-- Tutorea · Fase 14.2 · 06 profiles (1 a 1 con auth.users)
-- Sin correo ni contraseña: el correo vive solo en auth.users y las credenciales las
-- guarda Supabase Auth.

create table public.profiles (
  id             uuid primary key references auth.users (id) on delete cascade,
  university_id  uuid not null references public.universities (id) on delete restrict,
  role           public.user_role not null default 'estudiante',
  full_name      text not null check (length(trim(full_name)) between 2 and 120),
  career_id      uuid not null,  -- obligatoria; se puede cambiar por otra de la misma universidad
  career_name    text not null check (length(trim(career_name)) between 2 and 200),  -- copia del nombre (trigger)
  academic_year  smallint not null check (academic_year between 1 and 10),
  legacy_id      text unique,  -- u-sergio…; solo lo escribe el script de migración
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  -- Destino de las FK compuestas (user_id, university_id) de tutor_profiles y bookings.
  constraint profiles_id_university_key unique (id, university_id),
  constraint profiles_career_fk foreign key (career_id, university_id)
    references public.careers (id, university_id) on delete restrict
);

create index profiles_university_role_idx on public.profiles (university_id, role);
create index profiles_career_idx on public.profiles (career_id);

alter table public.profiles enable row level security;

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Nadie inserta ni borra desde la app (la fila la crea handle_new_user).
-- Update solo de las 4 columnas editables; role, university_id, id y legacy_id quedan fuera.
revoke all on table public.profiles from public, anon, authenticated;
grant select on table public.profiles to authenticated;
grant update (full_name, career_id, career_name, academic_year)
  on table public.profiles to authenticated;

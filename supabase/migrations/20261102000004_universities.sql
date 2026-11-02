-- Tutorea · Fase 14.2 · 04 universities
-- RLS se activa en la misma migración que crea la tabla: sin políticas, nadie lee nada
-- hasta la migración 11.

create table public.universities (
  id          uuid primary key default gen_random_uuid(),
  slug        text not null unique check (slug ~ '^[a-z0-9-]+$'),
  name        text not null check (length(trim(name)) between 2 and 200),
  short_name  text not null check (length(trim(short_name)) between 2 and 40),
  country     text not null check (length(trim(country)) >= 2),
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table public.universities enable row level security;

create trigger universities_set_updated_at
  before update on public.universities
  for each row execute function public.set_updated_at();

-- Supabase concede ALL por defecto a anon y authenticated: se quita y se da solo lectura.
-- Altas y cambios de universidades: solo el equipo desde Supabase (service_role / postgres).
revoke all on table public.universities from public, anon, authenticated;
grant select on table public.universities to anon, authenticated;

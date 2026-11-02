-- Tutorea · Fase 14.2 · 03 Trigger común de updated_at

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Solo la usan los triggers; nadie la invoca directamente.
revoke all on function public.set_updated_at() from public, anon, authenticated;

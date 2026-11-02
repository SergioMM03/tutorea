-- Tutorea · Fase 14.2 · 11 Políticas RLS de universities, careers, subjects y profiles
-- Ninguna política usa "using (true)". Las que llaman funciones auxiliares son solo
-- "to authenticated" (anon no puede ejecutarlas).

-- universities ---------------------------------------------------------------
create policy universities_select_active
  on public.universities for select
  to anon, authenticated
  using (is_active);

-- Quien ya pertenece a una universidad la sigue viendo aunque se desactive.
create policy universities_select_own
  on public.universities for select
  to authenticated
  using (id = (select public.current_university_id()));

-- careers --------------------------------------------------------------------
create policy careers_select_active_university
  on public.careers for select
  to anon, authenticated
  using (exists (
    select 1 from public.universities u
    where u.id = careers.university_id and u.is_active
  ));

create policy careers_select_admin
  on public.careers for select
  to authenticated
  using (public.is_admin_of(university_id));

create policy careers_insert_admin
  on public.careers for insert
  to authenticated
  with check (public.is_admin_of(university_id));

create policy careers_update_admin
  on public.careers for update
  to authenticated
  using (public.is_admin_of(university_id))
  with check (public.is_admin_of(university_id));

create policy careers_delete_admin
  on public.careers for delete
  to authenticated
  using (public.is_admin_of(university_id));

-- subjects -------------------------------------------------------------------
create policy subjects_select_active_university
  on public.subjects for select
  to anon, authenticated
  using (exists (
    select 1 from public.universities u
    where u.id = subjects.university_id and u.is_active
  ));

create policy subjects_select_admin
  on public.subjects for select
  to authenticated
  using (public.is_admin_of(university_id));

create policy subjects_insert_admin
  on public.subjects for insert
  to authenticated
  with check (public.is_admin_of(university_id));

create policy subjects_update_admin
  on public.subjects for update
  to authenticated
  using (public.is_admin_of(university_id))
  with check (public.is_admin_of(university_id));

create policy subjects_delete_admin
  on public.subjects for delete
  to authenticated
  using (public.is_admin_of(university_id));

-- profiles -------------------------------------------------------------------
-- Leer: el propio y el administrador de su universidad. Los demás usan public_profiles.
create policy profiles_select_own_or_admin
  on public.profiles for select
  to authenticated
  using (id = (select auth.uid()) or public.is_admin_of(university_id));

-- Modificar: solo el propio (las columnas las limita el GRANT de la migración 06).
-- Sin políticas de insert ni delete: nadie los hace desde la app.
create policy profiles_update_own
  on public.profiles for update
  to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

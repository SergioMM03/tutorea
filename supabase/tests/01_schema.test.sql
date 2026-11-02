-- Tutorea · Fase 14.2 · Pruebas de estructura, permisos y funciones
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(47);

-- Tablas y RLS activado
select has_table('public', 'universities', 'existe universities');
select has_table('public', 'careers', 'existe careers');
select has_table('public', 'subjects', 'existe subjects');
select has_table('public', 'profiles', 'existe profiles');
select ok((select relrowsecurity from pg_class where oid = 'public.universities'::regclass), 'RLS activo en universities');
select ok((select relrowsecurity from pg_class where oid = 'public.careers'::regclass), 'RLS activo en careers');
select ok((select relrowsecurity from pg_class where oid = 'public.subjects'::regclass), 'RLS activo en subjects');
select ok((select relrowsecurity from pg_class where oid = 'public.profiles'::regclass), 'RLS activo en profiles');

-- profiles sin correo ni contraseña; vista con columnas públicas exactas
select hasnt_column('public', 'profiles', 'email', 'profiles no guarda correo');
select hasnt_column('public', 'profiles', 'password', 'profiles no guarda contraseña');
select col_not_null('public', 'profiles', 'career_id', 'la carrera es obligatoria');
select has_table('public', 'admin_role_assignments', 'existe la auditoría de administradores');
select ok((select relrowsecurity from pg_class where oid = 'public.admin_role_assignments'::regclass), 'RLS activo en la auditoría');
select ok(not has_table_privilege('authenticated', 'public.admin_role_assignments', 'select'), 'authenticated no lee la auditoría');
select ok(not has_table_privilege('anon', 'public.admin_role_assignments', 'select'), 'anon no lee la auditoría');
select ok(not has_table_privilege('service_role', 'public.admin_role_assignments', 'update')
          and not has_table_privilege('service_role', 'public.admin_role_assignments', 'delete'),
  'ni service_role modifica ni borra la auditoría');
select columns_are('public', 'public_profiles',
  array['id', 'university_id', 'full_name', 'career_name', 'academic_year', 'role'],
  'public_profiles solo expone columnas públicas');
select ok((select 'security_barrier=true' = any (reloptions) from pg_class
           where oid = 'public.public_profiles'::regclass),
  'public_profiles tiene security_barrier');

-- Tipos enumerados
select enum_has_labels('public', 'user_role', array['estudiante', 'tutor', 'administrador'], 'user_role');
select enum_has_labels('public', 'booking_modality', array['presencial', 'virtual'], 'booking_modality');
select enum_has_labels('public', 'booking_status',
  array['pendiente', 'aceptada', 'rechazada', 'cancelada', 'pendiente_confirmacion', 'completada'], 'booking_status');
select enum_has_labels('public', 'incident_status',
  array['pendiente_revision', 'en_investigacion', 'resuelta', 'desestimada'], 'incident_status');
select has_type('public', 'notification_type', 'existe notification_type');

-- SECURITY DEFINER solo donde hace falta, siempre con search_path vacío
select is_definer('public', 'current_university_id', array[]::name[], 'current_university_id es definer');
select is_definer('public', 'current_user_role', array[]::name[], 'current_user_role es definer');
select is_definer('public', 'is_admin_of', array['uuid'], 'is_admin_of es definer');
select is_definer('public', 'handle_new_user', array[]::name[], 'handle_new_user es definer');
select isnt_definer('public', 'assign_admin', array['uuid', 'text'], 'assign_admin es invoker');
select isnt_definer('public', 'guard_profile_identity', array[]::name[], 'la guarda es invoker (lee current_user real)');
select isnt_definer('public', 'is_privileged_session', array[]::name[], 'is_privileged_session es invoker');
select hasnt_function('public', 'assign_admin', array['uuid'], 'no queda la versión de assign_admin sin auditoría');
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and not coalesce(p.proconfig @> array['search_path=""'], false)),
  0, 'toda función SECURITY DEFINER de public fija search_path vacío');

-- EXECUTE limitado
select ok(not has_function_privilege('authenticated', 'public.assign_admin(uuid, text)', 'execute'), 'authenticated no ejecuta assign_admin');
select ok(not has_function_privilege('anon', 'public.assign_admin(uuid, text)', 'execute'), 'anon no ejecuta assign_admin');
select ok(has_function_privilege('service_role', 'public.assign_admin(uuid, text)', 'execute'), 'service_role ejecuta assign_admin');
select ok(not has_function_privilege('authenticated', 'public.handle_new_user()', 'execute'), 'authenticated no ejecuta handle_new_user');
select ok(not has_function_privilege('anon', 'public.current_university_id()', 'execute'), 'anon no ejecuta current_university_id');
select ok(not has_function_privilege('anon', 'public.is_admin_of(uuid)', 'execute'), 'anon no ejecuta is_admin_of');
select ok(has_function_privilege('authenticated', 'public.is_admin_of(uuid)', 'execute'), 'authenticated ejecuta is_admin_of');

-- Permisos de tabla y columna
select ok(not has_table_privilege('anon', 'public.profiles', 'select'), 'anon no lee profiles');
select ok(not has_table_privilege('anon', 'public.public_profiles', 'select'), 'anon no lee public_profiles');
select ok(not has_table_privilege('authenticated', 'public.profiles', 'insert'), 'authenticated no inserta profiles');
select ok(not has_table_privilege('authenticated', 'public.profiles', 'delete'), 'authenticated no borra profiles');
select ok(not has_column_privilege('authenticated', 'public.profiles', 'role', 'update'), 'authenticated no actualiza role');
select ok(not has_column_privilege('authenticated', 'public.profiles', 'university_id', 'update'), 'authenticated no actualiza university_id');
select ok(not has_table_privilege('authenticated', 'public.universities', 'insert'), 'authenticated no crea universidades');
select ok(not has_function_privilege('authenticated', 'public.prevent_audit_changes()', 'execute'), 'authenticated no ejecuta funciones de trigger');

select * from finish();
rollback;

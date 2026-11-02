# Tutorea · Supabase (Fase 14.2: esquema base)

Esquema base de la migración a Supabase según el documento
«Tutorea — Fase 14.1 Arquitectura y base de datos Supabase».

```
migrations/   11 migraciones en orden (extensiones → políticas RLS)
seed.sql      catálogo inicial: ESEN, 4 carreras, 13 materias (repetible)
tests/        pruebas pgTAP (supabase test db)
scripts/      comprobación de que el seed se puede ejecutar varias veces
```

Ningún archivo contiene claves. La `service_role` solo se usa desde la computadora
del equipo, en una variable de entorno, nunca en Flutter ni en el repositorio.

## 1. Probar en local

Requiere la CLI de Supabase y Docker Desktop. Desde la raíz del proyecto Flutter:

```
supabase init            # solo la primera vez; crea supabase/config.toml (no sobrescribe migrations/)
supabase start
supabase db reset        # aplica las migraciones y luego seed.sql
supabase test db         # corre supabase/tests
```

Comprobar que el seed completo se puede repetir (lo ejecuta dos veces más y compara
ids y datos). En Windows, desde `cmd` (no PowerShell, que puede cambiar los acentos):

```
type supabase\scripts\check_seed_idempotency_before.sql supabase\seed.sql supabase\seed.sql supabase\scripts\check_seed_idempotency_after.sql | docker exec -i supabase_db_tutorea psql -U postgres -d postgres -v ON_ERROR_STOP=1
```

Debe terminar con `OK: el seed se ejecutó dos veces más sin duplicar ni cambiar ids`.
`supabase_db_tutorea` es el contenedor de la base local (`supabase_db_<project_id>` de
`config.toml`); `docker ps` muestra el nombre exacto.

## 2. Configuración de Auth (MVP)

**Confirmación de correo desactivada.** El registro de la app espera la sesión
inmediata y el perfil se crea al registrarse.

- Local: en `supabase/config.toml`, sección `[auth.email]`, `enable_confirmations = false`
  (es el valor por defecto en local).
- Proyecto remoto: en el panel de Supabase, Authentication → proveedor Email →
  desactivar «Confirm email». En proyectos nuevos viene activada.

No se validan dominios de correo institucional en esta versión.

## 3. Desplegar en el proyecto remoto

`--include-seed` es **obligatorio** en el primer despliegue: sin él el proyecto queda sin
ESEN y nadie puede registrarse (handle_new_user exige una universidad activa).

```
supabase login
supabase link --project-ref <ref-del-proyecto>
supabase db push --dry-run
supabase db push --include-seed
```

El seed se puede volver a ejecutar sin duplicar datos.

## 4. Registro (metadata que exige handle_new_user)

`signUp` / `auth.admin.createUser` deben enviar en `data` / `user_metadata`:

| Clave | Valor |
|---|---|
| `university_id` | uuid de la universidad (activa) |
| `career_id` | uuid de una carrera de esa universidad (obligatoria) |
| `full_name` | 2 a 120 caracteres |
| `academic_year` | 1 a 10 |
| `role` | `estudiante` o `tutor`; cualquier otro valor se guarda como `estudiante` |

Flutter conserva sus ids actuales (`esen`, `esen-eyn`, `est`…). Los repositorios de
Supabase los traducen a uuid buscando por `slug` (universities, careers, subjects).

Si un dato no es válido, Supabase Auth responde «Database error saving new user»: la app
debe validar antes de llamar a `signUp`.

## 5. Crear un administrador

Los administradores son **cuentas independientes**: no se promueve a un tutor existente.

1. Crear la cuenta con rol estudiante y metadata válida (sección 4), de una de dos formas:
   - registro normal en la app, o
   - Admin API desde la computadora del equipo, con `email_confirm: true` y `user_metadata`.

   El botón «Add user» del panel de Supabase no sirve: no envía metadata.
2. En el SQL editor de Supabase:

   ```sql
   select public.assign_admin('<uuid de auth.users>', '<nombre de quien asigna>');
   ```

`assign_admin` solo la pueden ejecutar `postgres` y `service_role`. Conserva la universidad
de la cuenta y registra la asignación en `public.admin_role_assignments` (a quién, de qué
universidad, rol anterior, quién asignó, con qué rol de base y cuándo). Ese registro no se
puede modificar ni borrar, y la app no puede leerlo.

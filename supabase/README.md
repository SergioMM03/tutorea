# Tutorea · Supabase (esquema base 14.2 y tutores 14.7)

Esquema base de la migración a Supabase según el documento
«Tutorea — Fase 14.1 Arquitectura y base de datos Supabase».

```
migrations/   01–11 esquema base (14.2); 12–15 tutores, materias, disponibilidad y save_tutor_profile (14.7);
              16 doble rol: cualquier cuenta puede tener perfil de tutor (corrección 14.7);
              17–18 reservas: tabla bookings y funciones request/accept/reject/cancel (14.8)
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

### Fase 14.7: desplegar tutores y disponibilidad

Las migraciones 12 a 15 se agregan sin tocar las anteriores. Después de probarlas en local
(`supabase db reset` y `supabase test db`, que incluye `tests/05_tutors.test.sql`):

```
supabase db push --dry-run     # debe listar solo 20261102000012 … 20261102000015
supabase db push
```

- `tutor_profiles`: un perfil por cuenta con rol tutor; el servidor fija dueño y universidad.
- `tutor_subjects`: materias del tutor, siempre de su misma universidad (FK compuesta).
- `availability_slots`: días 1–7, minutos 0–1440, sin cruces (restricción EXCLUDE).
- `save_tutor_profile(...)`: guarda perfil, materias y horarios en una transacción, con RLS.

### Corrección 14.7: doble rol (migración 16)

Una misma cuenta puede ser estudiante y tutor. Ofrecer tutorías = tener una fila en
`tutor_profiles`; `profiles.role` solo es el rol principal (pantalla inicial) o
`administrador`. La migración 16 reemplaza `prepare_tutor_profile` (cualquier cuenta
estudiante o tutor crea su perfil; una administradora no) y `assign_admin` (rechaza
cuentas que ya ofrecen tutorías). No modifica las migraciones 01–15.

```
supabase db reset && supabase test db   # incluye tests/06_dual_role.test.sql
supabase db push --dry-run              # debe listar solo 20261102000016 (si 12–15 ya están)
supabase db push
```

### Fase 14.8: reservas (migraciones 17 y 18)

- `bookings` (17): reserva entre la cuenta que solicita y un perfil de tutor de la misma
  universidad (FK compuestas). Precio acordado fijo, `starts_at`/`ends_at` en `timestamptz`
  (UTC), duración 60/90/120, modalidad, lugar o enlace, estado y datos de cancelación.
  Dos `EXCLUDE` impiden sesiones confirmadas que se crucen (por tutor y por estudiante).
  La guarda `bookings_guard` protege transiciones y campos; las reservas no se borran.
  RLS: solo lectura para las dos partes. Se agrega a la publicación `supabase_realtime`.
- Funciones (18), `SECURITY DEFINER` con `search_path = ''`: `request_booking`,
  `accept_booking`, `reject_booking`, `cancel_booking`. Toman la identidad de `auth.uid()`;
  la disponibilidad se compara en hora de El Salvador (`tutorea_time_zone()`) al solicitar
  y otra vez al aceptar (con la disponibilidad actual, bloqueando los horarios del tutor:
  si la cambió o la borró, `TU015`).

```
supabase db reset && supabase test db   # incluye tests/07_bookings y 08_booking_availability
supabase db push --dry-run              # debe listar solo 20261102000017 y 20261102000018
```

Después del despliegue, comprobar en el panel (Database → Publications → supabase_realtime)
que `bookings` aparece; si no, activar Realtime para esa tabla.

### Fase 14.9: confirmaciones, incidencias, calificaciones y notificaciones (migraciones 19 a 23)

No modifican las migraciones 01–18. Toda escritura pasa por funciones `SECURITY DEFINER`
con `search_path = ''` que toman la identidad de `auth.uid()`; las tablas son de solo
lectura para `authenticated` (RLS) y el historial no se modifica ni se borra.

- `booking_confirmations` (19): una confirmación por parte (`estudiante` / `tutor`) y reserva.
- `booking_incidents` y `booking_incident_events` (20): `report_incident` (partes, desde
  `aceptada` hasta 7 días después de `ends_at`, una abierta por persona). Gestión del
  administrador de la misma universidad (`is_admin_of`): `admin_start_incident_investigation`,
  `admin_add_incident_note` (nota interna), `admin_resolve_incident`, `admin_dismiss_incident`.
  Resolver o desestimar no cambia la reserva, no crea calificaciones ni sanciona.
- `confirm_booking` (21): 1.ª confirmación → `pendiente_confirmacion`; 2.ª → `completada`,
  salvo incidencia abierta (`TU022`). Nunca se completa por tiempo.
- `reviews` y vista `public_reviews` (22): `submit_review` (solo el estudiante, reserva
  completada y sin incidencias abiertas, 1–5, una por reserva, sin edición). El trigger
  `recalc_tutor_rating` calcula `rating_avg`/`rating_count`; sin reseñas, `rating_avg` es null.
- `notifications` (23): las crean triggers sobre `bookings` y `booking_incidents` (sin
  duplicados: `event_key` único por destinatario). La app solo lee las propias y las marca
  con `mark_notifications_read`. Se agrega a `supabase_realtime`.

```
supabase db reset && supabase test db   # incluye tests/09 a 12
supabase db push --dry-run              # debe listar solo 20261102000019 … 20261102000023
```

Después del despliegue, comprobar que `notifications` está en la publicación
`supabase_realtime`.

## 4. Registro (metadata que exige handle_new_user)

`signUp` / `auth.admin.createUser` deben enviar en `data` / `user_metadata`:

| Clave | Valor |
|---|---|
| `university_id` | uuid de la universidad (activa) |
| `career_id` | uuid de una carrera de esa universidad (obligatoria) |
| `full_name` | 2 a 120 caracteres |
| `academic_year` | 1 a 10 |
| `role` | rol principal: `estudiante` o `tutor`; cualquier otro valor se guarda como `estudiante`. Ofrecer tutorías no depende del rol |

Flutter conserva sus ids actuales (`esen`, `esen-eyn`, `est`…). Los repositorios de
Supabase los traducen a uuid buscando por `slug` (universities, careers, subjects).

Si un dato no es válido, Supabase Auth responde «Database error saving new user»: la app
debe validar antes de llamar a `signUp`.

## 5. Crear un administrador

Los administradores son **cuentas independientes**: no se promueve a una cuenta con rol
tutor ni a una que tenga perfil de tutor.

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

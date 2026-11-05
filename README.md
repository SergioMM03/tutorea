# Tutorea

**Plataforma de tutorías académicas entre estudiantes universitarios.**

Tutorea conecta estudiantes que necesitan apoyo académico con estudiantes que ofrecen tutorías. La aplicación permite explorar tutores, consultar sus perfiles, solicitar sesiones y gestionar el proceso de tutoría.

El proyecto está desarrollado con **Flutter** y utiliza **Supabase** como infraestructura backend.

## Características principales

- Registro e inicio de sesión de usuarios.
- Selección de universidad y consulta de catálogo académico.
- Perfiles de estudiantes y tutores.
- Cuentas con doble rol: un usuario puede recibir y ofrecer tutorías.
- Búsqueda y filtrado de tutores por materia, modalidad, disponibilidad, calificación y otros criterios.
- Gestión de materias y horarios disponibles.
- Fotografías de tutores mediante almacenamiento privado.
- Solicitud, aceptación, rechazo y cancelación de reservas.
- Confirmación de sesiones por ambas partes.
- Reporte y gestión de incidencias.
- Calificaciones y reseñas después de completar una tutoría.
- Notificaciones relacionadas con las reservas y las incidencias.

## Tecnologías

| Componente | Tecnología |
|---|---|
| Aplicación móvil | Flutter / Dart |
| Backend | Supabase |
| Base de datos | PostgreSQL |
| Autenticación | Supabase Auth |
| Seguridad de datos | Row Level Security (RLS) |
| Operaciones de negocio | PostgreSQL RPC |
| Fotografías | Supabase Storage |
| Actualizaciones en tiempo real | Supabase Realtime |
| Gestión de dependencias | Provider / ChangeNotifier |

## Arquitectura

La aplicación utiliza una arquitectura por capas:

1. **Presentación:** pantallas, componentes y navegación de Flutter.
2. **Estado:** Stores basados en Provider y ChangeNotifier.
3. **Dominio:** modelos, reglas de negocio y contratos de repositorios.
4. **Datos:** implementaciones de repositorios y fuentes de datos.
5. **Backend:** Supabase Auth, PostgreSQL, RLS, funciones RPC, triggers, Realtime y Storage.

Las pantallas interactúan con los Stores y los contratos de repositorios, evitando depender directamente de la implementación de Supabase.

En producción, las operaciones y validaciones críticas se realizan en el servidor. La aplicación no utiliza una base de datos local como respaldo automático.

## Requisitos

Para ejecutar el proyecto necesitas:

- Flutter y Dart compatibles con las versiones declaradas en `pubspec.yaml`.
- Git.
- Una conexión a Internet.
- Acceso al proyecto de Supabase y sus credenciales públicas de aplicación.

Para ejecutar una instancia local de Supabase también necesitas Docker Desktop y Supabase CLI.

## Instalación

Clona el repositorio:

```bash
git clone https://github.com/SergioMM03/tutorea.git
cd tutorea
```

Instala las dependencias:

```bash
flutter pub get
```

## Configuración de Supabase

La aplicación necesita las siguientes variables de entorno de compilación:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`

### 1. Crear el archivo de configuración

Copia el archivo de ejemplo:

**Windows PowerShell:**

```powershell
Copy-Item env/supabase.example.json env/supabase.dev.json
```

**macOS / Linux:**

```bash
cp env/supabase.example.json env/supabase.dev.json
```

### 2. Configurar las credenciales

Edita `env/supabase.dev.json`:

```json
{
  "SUPABASE_URL": "https://<project-ref>.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_..."
}
```

Sustituye los valores por los correspondientes a tu proyecto de Supabase.

### 3. Ejecutar la aplicación

```bash
flutter run --dart-define-from-file=env/supabase.dev.json
```

**Importante sobre las credenciales:**

- En Flutter se utiliza únicamente la publishable key (o la antigua anon key).
- Nunca incluyas una clave `service_role` o `sb_secret_` en la aplicación.
- El archivo `env/supabase.dev.json` está excluido del repositorio mediante `.gitignore`.
- El archivo `env/supabase.example.json` contiene únicamente valores de ejemplo.

## Modos de ejecución

### Producción y conexión con Supabase

La aplicación utiliza Supabase para autenticación y operaciones de datos.

Si la configuración está incompleta o no se puede establecer la conexión, se muestra la pantalla **«Sin conexión con Tutorea»**, con la opción de reintentar.

La aplicación no cambia automáticamente a datos locales.

### Modo local de desarrollo

Existe un modo local explícito para desarrollo y demostraciones:

```bash
flutter run --dart-define=TUTOREA_AUTH=local
```

Este modo no representa el funcionamiento de producción y se ignora en compilaciones release.

## Base de datos y backend

La estructura del backend se encuentra en el directorio `supabase/`.

```text
supabase/
├── migrations/       # Migraciones de PostgreSQL
├── tests/            # Pruebas automatizadas con pgTAP
├── scripts/          # Scripts auxiliares y datos de demostración
├── seed.sql          # Catálogo inicial
└── README.md         # Documentación del backend
```

El backend incluye:

- Perfiles y universidades.
- Carreras y materias.
- Perfiles de tutores y disponibilidad.
- Reservas y control de horarios.
- Confirmaciones de sesiones.
- Incidencias e historial de eventos.
- Reseñas y calificaciones.
- Notificaciones.
- Políticas RLS y funciones RPC.
- Almacenamiento privado de fotografías.

Para conocer los detalles de las migraciones, configuración de Auth, despliegue, datos de demostración y pruebas de base de datos, consulta [`supabase/README.md`](supabase/README.md).

## Pruebas

Para ejecutar el análisis estático:

```bash
flutter analyze
```

Para ejecutar las pruebas de Flutter:

```bash
flutter test
```

Para ejecutar las pruebas SQL con Supabase local:

```bash
supabase start
supabase db reset
supabase test db
```

La ejecución de pruebas SQL requiere Docker Desktop y una instancia local de Supabase.

## Datos de demostración

El proyecto incluye un script para preparar perfiles de tutores de demostración:

```text
supabase/scripts/demo_tutors.sql
```

Este script actualiza los perfiles, materias y horarios de las cuentas de demostración existentes. **No crea usuarios de autenticación ni contraseñas.**

Consulta `supabase/README.md` para conocer el procedimiento completo.

## Equipo de desarrollo

Proyecto académico desarrollado para la asignatura **Desarrollo de Aplicaciones Móviles**, en la Escuela Superior de Economía y Negocios (ESEN).

| Integrante | Responsabilidad |
|---|---|
| Sergio Andrés Mandujano Membreño | Backend e infraestructura |
| Fernando Andrés Mendez Abrego | Usuarios y experiencia |
| Kevin Giovanni Landos Castaneda | Tutores y catálogo |
| Marco Andrés Gutierrez Ramos | Reservas y sesiones |
| Raúl Ariel Somoza Barahona | Administración y confianza |

## Repositorio

[GitHub – SergioMM03/Tutorea](https://github.com/SergioMM03/tutorea)

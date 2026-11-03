# Tutorea – estructura base

    flutter create .
    flutter pub get
    flutter run

`flutter create .` genera las carpetas android/ios sin tocar `lib/`.
Las fotos de los tutores van en `assets/images/` (valeria.png, daniel.png, camila.png).

## Modo local y Supabase (Fase 14.3)

La app guarda todo en el dispositivo (shared_preferences). Supabase solo se
**inicializa** cuando recibe una configuración válida; todavía no se consulta y
los datos siguen siendo locales. Sin configuración, la app funciona igual que antes.

### Modo local (sin Supabase)

    flutter run
    flutter test

En la consola aparece `[Supabase] Supabase no configurado ... La app sigue en modo local.`

### Con Supabase inicializado

1. Copia el ejemplo y escribe los valores del proyecto
   (panel de Supabase → Project Settings → API Keys):

       copy env\supabase.example.json env\supabase.dev.json      (Windows)
       cp env/supabase.example.json env/supabase.dev.json        (macOS / Linux)

   ```json
   {
     "SUPABASE_URL": "https://<project-ref>.supabase.co",
     "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_..."
   }
   ```

2. Ejecuta con ese archivo:

       flutter run --dart-define-from-file=env/supabase.dev.json

   En la consola aparece `[Supabase] Inicializado (...). Datos todavía en modo local.`

`env/*.json` está en `.gitignore`; solo `env/supabase.example.json` va al repositorio.

### Reglas de las claves

- En Flutter va **solo la publishable key** (`sb_publishable_...`, o la anon key antigua).
  Queda dentro de la app compilada: es pública por diseño y lo que protege los datos es RLS.
- **Nunca** la `service_role` ni una clave `sb_secret_...`. La app las rechaza
  (`RECHAZADA: ... clave secreta o service_role`) y sigue en modo local.
  Esas claves solo se usan en scripts del equipo, con variables de entorno, fuera del repositorio.
- Sin configuración, con una URL que no sea https, o si Supabase no responde en 5 s,
  la app sigue en modo local.

### Diagnóstico del catálogo remoto (Fase 14.4)

Prueba explícita de solo lectura: consulta `universities`, `careers` y `subjects`
de ESEN en Supabase y las compara con el catálogo local (LocalSeed). La app normal
no ejecuta esta consulta y no necesita Internet para arrancar.

    flutter run -t lib/diagnostics/catalog_diagnostic_main.dart --dart-define-from-file=env/supabase.dev.json

Consulta exitosa: en la consola y en pantalla (barra verde) aparece
`[Diagnóstico catálogo] RESULTADO: OK — el catálogo remoto coincide con el local (1 universidad, 4 carreras, 13 materias).`
Si algo falla aparece `RESULTADO: ERROR` o `RESULTADO: DIFERENCIAS` con el detalle (barra roja).

### Autenticación con Supabase (Fase 14.5)

Por defecto las cuentas siguen siendo locales. Para registrar e iniciar sesión con
Supabase Auth se agrega `TUTOREA_AUTH=supabase`:

    flutter run --dart-define-from-file=env/supabase.dev.json --dart-define=TUTOREA_AUTH=supabase

En la consola aparece `[Auth] Supabase Auth activo. Tutores, reservas y catálogo siguen en modo local.`
Si Supabase no está configurado o no se inicializa, aparece `[Auth] ... Modo local.` y la app
usa las cuentas locales de siempre.

- El registro crea la cuenta en Supabase Auth; el perfil lo crea la base (trigger
  `handle_new_user`) con la universidad, carrera, año y rol (solo estudiante o tutor).
- La sesión queda guardada por supabase_flutter y se recupera al reabrir la app.
- Las cuentas locales y del seed no se migran: en modo Supabase hay que registrarse de nuevo.
- Todavía no disponible con Supabase: editar el perfil (Fase 14.6) y cuentas de administrador.

Esquema de la base, seed y pruebas SQL: ver `supabase/README.md`.

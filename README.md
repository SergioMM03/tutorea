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

### Modo Supabase (Fases 14.5 a 14.7)

Por defecto todo sigue siendo local. Con `TUTOREA_AUTH=supabase`, las cuentas, los
perfiles, el catálogo (universidades, carreras y materias) y los tutores con su
disponibilidad vienen de Supabase:

    flutter run --dart-define-from-file=env/supabase.dev.json --dart-define=TUTOREA_AUTH=supabase

En la consola aparece `[Datos] Supabase activo: cuentas, perfiles, catálogo, tutores y disponibilidad. Las reservas siguen en modo local.`
Si Supabase no está configurado o no se inicializa, aparece `[Datos] ... Modo local.`

Requisito para tutores: haber desplegado las migraciones 12 a 15 (ver `supabase/README.md`).

- Registro: la cuenta se crea en Supabase Auth y el perfil lo crea la base (`handle_new_user`).
- Editar perfil: nombre, carrera y año en `profiles` (solo el propio).
- Perfil de tutor: descripción, tarifa, modalidades, materias, horarios y visibilidad se guardan
  juntos con `save_tutor_profile`; solo una cuenta tutor puede tenerlo y solo el propio.
- Búsqueda: tutores activos de la misma universidad (RLS), con filtros por materia, categoría,
  modalidad y disponibilidad.
- Todavía locales: reservas (validan contra los tutores remotos). Aún no: fotografía del tutor
  en Supabase (Storage), cuentas demo y administradores en la app.
- Las cuentas, tutores y reservas locales no se migran: en modo Supabase empiezan vacíos.

Esquema de la base, seed y pruebas SQL: ver `supabase/README.md`.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config/auth_mode.dart';
import 'data/local/local_repositories.dart';
import 'data/supabase/auth_selection.dart';
import 'data/supabase/supabase_data_sources.dart';
import 'data/supabase/supabase_bootstrap.dart';
import 'routes/app_navigator.dart';
import 'routes/routes.dart';
import 'state/app_providers.dart';
import 'theme/app_theme.dart';
import 'widgets/booking_notice_listener.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Abre la base local (shared_preferences) y carga los datos iniciales.
  final repositories = await LocalRepositories.open();

  // Fase 14.3: Supabase se inicializa solo con configuración válida
  // (--dart-define-from-file). Todavía no se usa: los datos siguen siendo
  // locales. Si no hay configuración o falla, la app arranca igual que antes.
  await SupabaseBootstrap.initializeIfConfigured();

  // Fases 14.5 a 14.8: con TUTOREA_AUTH=supabase (y Supabase inicializado),
  // cuentas, perfiles, catálogo, tutores, disponibilidad y reservas usan
  // Supabase; si no, los repositorios locales.
  final data = selectDataSources(
    mode: AuthMode.fromEnvironment(),
    supabaseReady: SupabaseBootstrap.isReady,
    local: localDataSources(repositories),
    remote: () => supabaseDataSources(repositories),
  );

  // Con sesión guardada abre directo en la pantalla de su rol;
  // sin sesión, en la selección de universidad.
  final session = await data.auth.currentSession();
  final initialRoute = AppNavigator.initialRouteFor(session);

  runApp(AppProviders.local(
    repositories,
    auth: data.auth,
    universities: data.universities,
    subjects: data.subjects,
    tutors: data.tutors,
    bookings: data.bookings,
    incidents: data.incidents,
    reviews: data.reviews,
    notifications: data.notifications,
    child: TutoreaApp(initialRoute: initialRoute),
  ));
}

class TutoreaApp extends StatelessWidget {
  /// Selección de universidad, Inicio del estudiante o Dashboard del tutor.
  final String initialRoute;

  const TutoreaApp({super.key, this.initialRoute = AppRoutes.universitySelection});

  /// Límite para el tamaño de texto del sistema: respeta la preferencia
  /// del usuario sin que los diseños se rompan con textos gigantes.
  static const double _maxTextScale = 1.3;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tutorea',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      initialRoute: initialRoute,
      onGenerateInitialRoutes: onGenerateInitialRoutes,
      routes: appRoutes,
      onUnknownRoute: onUnknownRoute,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return AnnotatedRegion<SystemUiOverlayStyle>(
          // Íconos oscuros en la barra de estado (fondo blanco),
          // también en pantallas sin AppBar como Bienvenida e Inicio.
          value: SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
          ),
          child: MediaQuery(
            data: media.copyWith(
              textScaler: media.textScaler.clamp(maxScaleFactor: _maxTextScale),
            ),
            // Tocar fuera de un campo de texto cierra el teclado.
            child: GestureDetector(
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              // Avisos de reservas que cambió la otra parte (Fase 14.8).
              child: BookingNoticeListener(child: child!),
            ),
          ),
        );
      },
    );
  }
}

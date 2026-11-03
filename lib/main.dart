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
import 'widgets/startup_error_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await startTutorea();
}

/// Arranca la app. Producción (Fase 14.10): solo Supabase. Si Supabase no está
/// configurado o no responde, muestra un error con "Reintentar" (que vuelve a
/// llamar a esta función); nunca cambia a datos locales.
Future<void> startTutorea({AuthMode? mode}) async {
  final effective = mode ?? AuthMode.fromEnvironment();
  try {
    runApp(await _buildApp(effective));
  } on DataSourcesUnavailable catch (e) {
    runApp(StartupErrorApp(message: e.message, onRetry: () => startTutorea(mode: effective)));
  }
}

Future<Widget> _buildApp(AuthMode mode) async {
  if (mode == AuthMode.local) {
    // Desarrollo (TUTOREA_AUTH=local, nunca en release): datos de demostración
    // en el dispositivo.
    final repositories = await LocalRepositories.open();
    final data = selectDataSources(
      mode: mode,
      supabaseReady: false,
      local: () => localDataSources(repositories),
      remote: () => throw StateError('modo local'),
    );
    final session = await data.auth.currentSession();
    return AppProviders.local(repositories,
        child: TutoreaApp(initialRoute: AppNavigator.initialRouteFor(session)));
  }

  // Producción: Supabase Auth y todos los datos de negocio en Supabase.
  await SupabaseBootstrap.initializeIfConfigured();
  final data = selectDataSources(
    mode: mode,
    supabaseReady: SupabaseBootstrap.isReady,
    local: () => throw StateError('Producción no usa datos locales.'),
    remote: supabaseDataSources,
  );
  // ¿Responde el servidor? (catálogo público de universidades)
  try {
    await data.universities.getActive().timeout(const Duration(seconds: 10));
  } catch (_) {
    throw const DataSourcesUnavailable(supabaseUnreachableMessage);
  }

  // Con sesión guardada abre directo en la pantalla de su rol;
  // sin sesión, en la selección de universidad.
  final session = await data.auth.currentSession();
  return AppProviders.fromSources(data,
      child: TutoreaApp(initialRoute: AppNavigator.initialRouteFor(session)));
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

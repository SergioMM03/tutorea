/// Espaciados y radios usados en toda la app.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;

  /// Margen lateral de las pantallas.
  static const double screenPadding = 20;
}

class AppRadius {
  AppRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double card = 16;
  static const double pill = 100;
}

/// Anchos máximos para que el contenido no se estire en tablets.
class AppLayout {
  AppLayout._();

  /// Pantallas de contenido (Inicio, Perfil, Reserva).
  static const double maxContentWidth = 600;

  /// Pantallas de entrada (Bienvenida).
  static const double maxNarrowWidth = 480;
}

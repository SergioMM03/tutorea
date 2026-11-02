import 'package:flutter/material.dart';

import '../domain/models/user_role.dart';
import '../state/tutor_store.dart';
import '../screens/booking_screen.dart';
import '../screens/home_screen.dart';
import '../screens/login_screen.dart';
import '../screens/my_bookings_screen.dart';
import '../screens/not_found_screen.dart';
import '../screens/register_screen.dart';
import '../screens/student_booking_detail_screen.dart';
import '../screens/student_edit_profile_screen.dart';
import '../screens/tutor_dashboard_screen.dart';
import '../screens/tutor_edit_profile_screen.dart';
import '../screens/tutor_my_profile_screen.dart';
import '../screens/tutor_request_detail_screen.dart';
import '../screens/tutor_requests_screen.dart';
import '../screens/tutor_profile_screen.dart';
import '../screens/tutor_search_screen.dart';
import '../screens/university_selection_screen.dart';
import '../screens/user_profile_screen.dart';
import '../screens/welcome_screen.dart';

/// Sistema de rutas centralizado de Tutorea.
///
/// - [AppRoutes]: nombres de las rutas (usar siempre estas constantes).
/// - Clases *Args: datos que viajan entre pantallas.
/// - [appRoutes]: tabla nombre → pantalla que usa MaterialApp.
///
/// Aquí solo se decide QUÉ pantalla corresponde a cada ruta.
/// Los datos (tutores, reservas) vienen de `data/` y `state/`, nunca de aquí.
class AppRoutes {
  AppRoutes._();

  // Flujo principal
  /// Pantalla inicial sin sesión: elegir universidad.
  static const String universitySelection = '/';
  static const String welcome = '/welcome';
  static const String home = '/home';
  static const String tutorProfile = '/tutor-profile';
  static const String booking = '/booking';

  // Autenticación
  static const String login = '/login';
  static const String register = '/register';

  // Tutor
  static const String tutorDashboard = '/tutor';
  static const String tutorRequests = '/tutor/requests';
  static const String tutorRequestDetail = '/tutor/request';
  static const String tutorMyProfile = '/tutor/profile';
  static const String tutorEditProfile = '/tutor/profile/edit';

  // Pantallas ya existentes conectadas al flujo
  static const String myBookings = '/my-bookings';
  static const String studentBookingDetail = '/my-bookings/detail';
  static const String profile = '/profile';
  static const String editStudentProfile = '/profile/edit';
  static const String search = '/search';
}

// ---------------- Argumentos entre pantallas ----------------

/// Bienvenida → Registro (rol preseleccionado, ej. "¿Eres tutor?").
class RegisterArgs {
  final UserRole initialRole;
  const RegisterArgs({this.initialRole = UserRole.estudiante});
}

/// Home / Búsqueda → Perfil del tutor (tutor real del MVP).
class TutorProfileArgs {
  final TutorSummary tutor;
  const TutorProfileArgs(this.tutor);
}

/// Perfil del tutor → Reserva (tutor real del MVP).
class BookingArgs {
  final TutorSummary tutor;
  const BookingArgs(this.tutor);
}

/// Solicitudes del tutor → Detalle (se lee del BookingStore por id,
/// así el detalle se actualiza al aceptar o rechazar).
class TutorRequestDetailArgs {
  final String bookingId;
  const TutorRequestDetailArgs(this.bookingId);
}

/// Mis reservas → Detalle de una reserva (se lee del BookingStore por id,
/// así el detalle se actualiza al cancelar).
class StudentBookingDetailArgs {
  final String bookingId;
  const StudentBookingDetailArgs(this.bookingId);
}

/// Home → Búsqueda (opcional).
class SearchArgs {
  final String initialQuery;
  final String? category;
  const SearchArgs({this.initialQuery = '', this.category});
}

/// Lee los argumentos de la ruta actual con su tipo, o null si no vienen.
T? _argsOf<T>(BuildContext context) {
  final args = ModalRoute.of(context)?.settings.arguments;
  return args is T ? args : null;
}

// ---------------- Tabla de rutas ----------------

/// Rutas para `MaterialApp.routes`. Si una ruta llega sin los datos
/// que necesita, muestra NotFoundScreen en vez de fallar.
final Map<String, WidgetBuilder> appRoutes = {
  AppRoutes.universitySelection: (_) => const UniversitySelectionScreen(),
  AppRoutes.welcome: (_) => const WelcomeScreen(),
  AppRoutes.home: (_) => const HomeScreen(),

  AppRoutes.tutorProfile: (context) {
    final args = _argsOf<TutorProfileArgs>(context);
    return args == null
        ? const NotFoundScreen()
        : TutorProfileScreen(tutor: args.tutor);
  },

  AppRoutes.booking: (context) {
    final args = _argsOf<BookingArgs>(context);
    return args == null ? const NotFoundScreen() : BookingScreen(tutor: args.tutor);
  },

  AppRoutes.myBookings: (_) => const MyBookingsScreen(),

  AppRoutes.studentBookingDetail: (context) {
    final args = _argsOf<StudentBookingDetailArgs>(context);
    return args == null
        ? const NotFoundScreen()
        : StudentBookingDetailScreen(bookingId: args.bookingId);
  },

  AppRoutes.profile: (_) => const UserProfileScreen(),
  AppRoutes.editStudentProfile: (_) => const StudentEditProfileScreen(),

  AppRoutes.search: (context) =>
      TutorSearchScreen(args: _argsOf<SearchArgs>(context) ?? const SearchArgs()),

  AppRoutes.login: (_) => const LoginScreen(),
  AppRoutes.register: (context) => RegisterScreen(
        initialRole: _argsOf<RegisterArgs>(context)?.initialRole ?? UserRole.estudiante,
      ),

  // Tutor
  AppRoutes.tutorDashboard: (_) => const TutorDashboardScreen(),
  AppRoutes.tutorRequests: (_) => const TutorRequestsScreen(),
  AppRoutes.tutorRequestDetail: (context) {
    final args = _argsOf<TutorRequestDetailArgs>(context);
    return args == null
        ? const NotFoundScreen()
        : TutorRequestDetailScreen(bookingId: args.bookingId);
  },
  AppRoutes.tutorMyProfile: (_) => const TutorMyProfileScreen(),
  AppRoutes.tutorEditProfile: (_) => const TutorEditProfileScreen(),
};

/// Ruta inicial única (sin apilar '/' debajo, como haría Flutter con '/home').
List<Route<dynamic>> onGenerateInitialRoutes(String initialRoute) {
  final builder = appRoutes[initialRoute] ?? appRoutes[AppRoutes.universitySelection]!;
  return [
    MaterialPageRoute(builder: builder, settings: RouteSettings(name: initialRoute)),
  ];
}

/// Cualquier ruta que no esté en [appRoutes].
Route<dynamic> onUnknownRoute(RouteSettings settings) =>
    MaterialPageRoute(builder: (_) => const NotFoundScreen(), settings: settings);

import 'package:flutter/material.dart';

import '../domain/models/session.dart';
import '../domain/models/user_role.dart';
import '../state/tutor_store.dart';
import 'routes.dart';

/// Pestañas de la barra inferior del estudiante.
enum AppTab { home, myBookings, profile }

/// Pestañas de la barra inferior del tutor.
enum TutorTab { home, requests, profile }

/// Único lugar donde se decide CÓMO se navega.
/// Las pantallas solo dicen A DÓNDE ir (ej. `AppNavigator.toBooking(context, tutor)`).
class AppNavigator {
  AppNavigator._();

  // ---------------- Pestañas (pantallas raíz) ----------------

  /// Abre una pestaña como raíz: "atrás" no regresa a la pestaña anterior.
  static void toTab(BuildContext context, AppTab tab) {
    final route = switch (tab) {
      AppTab.home => AppRoutes.home,
      AppTab.myBookings => AppRoutes.myBookings,
      AppTab.profile => AppRoutes.profile,
    };
    Navigator.pushNamedAndRemoveUntil(context, route, (_) => false);
  }

  static void toHome(BuildContext context) => toTab(context, AppTab.home);

  static void toUserProfile(BuildContext context) => toTab(context, AppTab.profile);

  static void toMyBookings(BuildContext context) => toTab(context, AppTab.myBookings);

  // ---------------- Pantallas apiladas ----------------

  static void toTutorProfile(BuildContext context, TutorSummary tutor) =>
      Navigator.pushNamed(context, AppRoutes.tutorProfile,
          arguments: TutorProfileArgs(tutor));

  static void toBooking(BuildContext context, TutorSummary tutor) =>
      Navigator.pushNamed(context, AppRoutes.booking, arguments: BookingArgs(tutor));

  static void toSearch(BuildContext context) =>
      Navigator.pushNamed(context, AppRoutes.search);

  /// Perfil del estudiante → Editar perfil (se apila; "atrás" no guarda).
  static void toEditStudentProfile(BuildContext context) =>
      Navigator.pushNamed(context, AppRoutes.editStudentProfile);

  static void toStudentBookingDetail(BuildContext context, String bookingId) =>
      Navigator.pushNamed(context, AppRoutes.studentBookingDetail,
          arguments: StudentBookingDetailArgs(bookingId));

  // ---------------- Tutor ----------------

  /// Abre una pestaña del tutor como raíz (igual que [toTab]).
  static void toTutorTab(BuildContext context, TutorTab tab) {
    final route = switch (tab) {
      TutorTab.home => AppRoutes.tutorDashboard,
      TutorTab.requests => AppRoutes.tutorRequests,
      TutorTab.profile => AppRoutes.tutorMyProfile,
    };
    Navigator.pushNamedAndRemoveUntil(context, route, (_) => false);
  }

  static void toTutorDashboard(BuildContext context) =>
      toTutorTab(context, TutorTab.home);

  static void toTutorRequests(BuildContext context) =>
      toTutorTab(context, TutorTab.requests);

  static void toTutorMyProfile(BuildContext context) =>
      toTutorTab(context, TutorTab.profile);

  static void toTutorRequestDetail(BuildContext context, String bookingId) =>
      Navigator.pushNamed(context, AppRoutes.tutorRequestDetail,
          arguments: TutorRequestDetailArgs(bookingId));

  static void toTutorEditProfile(BuildContext context) =>
      Navigator.pushNamed(context, AppRoutes.tutorEditProfile);

  // ---------------- Autenticación ----------------

  static void toLogin(BuildContext context) =>
      Navigator.pushNamed(context, AppRoutes.login);

  static void toRegister(BuildContext context, {UserRole role = UserRole.estudiante}) =>
      Navigator.pushNamed(context, AppRoutes.register,
          arguments: RegisterArgs(initialRole: role));

  /// Botones de Bienvenida (mismos nombres que usa WelcomeScreen).
  static void signIn(BuildContext context) => toLogin(context);
  static void toTutorRegister(BuildContext context) =>
      toRegister(context, role: UserRole.tutor);

  /// Ruta de entrada según el rol (también la usa main.dart al abrir la app).
  static String homeRouteFor(UserRole role) => switch (role) {
        UserRole.estudiante => AppRoutes.home,
        UserRole.tutor => AppRoutes.tutorDashboard,
      };

  /// Después de iniciar sesión o registrarse: va a la pantalla de su rol
  /// y limpia el historial (atrás no regresa al login).
  static void afterAuth(BuildContext context, UserRole role) =>
      Navigator.pushNamedAndRemoveUntil(context, homeRouteFor(role), (_) => false);

  /// Pantalla inicial: elegir universidad (limpia el historial).
  /// Se usa al cerrar sesión y desde Login/Registro para cambiar de universidad.
  static void toUniversitySelection(BuildContext context) => Navigator.pushNamedAndRemoveUntil(
      context, AppRoutes.universitySelection, (_) => false);

  /// Después de elegir universidad: Bienvenida encima de la selección,
  /// así "atrás" permite cambiarla.
  static void afterUniversitySelected(BuildContext context) =>
      Navigator.pushNamed(context, AppRoutes.welcome);

  /// Ruta al abrir la app: con sesión válida, el módulo de su rol;
  /// sin sesión, la selección de universidad.
  static String initialRouteFor(Session session) =>
      session.rol == null ? AppRoutes.universitySelection : homeRouteFor(session.rol!);

  static void back(BuildContext context) => Navigator.maybePop(context);
}

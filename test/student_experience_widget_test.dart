import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorea/data/local/local_repositories.dart';
import 'package:tutorea/domain/models/models.dart';
import 'package:tutorea/main.dart';
import 'package:tutorea/state/app_providers.dart';

/// Próximo [weekday] (1 = lunes) a la hora indicada, siempre en el futuro.
DateTime _next(int weekday, int hour) {
  var day = DateTime.now().add(const Duration(days: 1));
  while (day.weekday != weekday) {
    day = day.add(const Duration(days: 1));
  }
  return DateTime(day.year, day.month, day.day, hour);
}

/// Bienvenida → Login como Sergio (estudiante).
Future<void> _loginStudent(WidgetTester tester) async {
  await _chooseEsen(tester);
  final welcomeLogin = find.widgetWithText(ElevatedButton, 'Iniciar sesión');
  await tester.ensureVisible(welcomeLogin);
  await tester.tap(welcomeLogin);
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextFormField, 'Correo'), 'sergio@esen.edu.sv');
  await tester.enterText(find.widgetWithText(TextFormField, 'Contraseña'), 'tutorea123');
  await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Iniciar sesión'));
  await tester.tap(find.widgetWithText(ElevatedButton, 'Iniciar sesión'));
  await tester.pumpAndSettle();
}

Future<void> _openMyBookings(WidgetTester tester) async {
  await tester.tap(find.descendant(
      of: find.byType(BottomNavigationBar), matching: find.text('Mis reservas')));
  await tester.pumpAndSettle();
}

Finder get _listScrollable =>
    find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;

/// Sergio: una pendiente con Valeria (Estadística, 1.5 h) y una aceptada con Daniel.
Future<void> _seed(LocalRepositories repos) async {
  await repos.bookings.create(Booking(
    id: 'bk-pend',
    studentId: 'u-sergio',
    tutorId: 'tp-valeria',
    subjectId: 'est',
    tema: 'Distribuciones',
    fechaHora: _next(DateTime.tuesday, 10),
    duracion: 90,
    precio: 0,
  ));
  await repos.bookings.create(Booking(
    id: 'bk-acep',
    studentId: 'u-sergio',
    tutorId: 'tp-daniel',
    subjectId: 'fin',
    fechaHora: _next(DateTime.monday, 10),
    duracion: 60,
    precio: 0,
  ));
  await repos.bookings.updateStatus('bk-acep', BookingStatus.aceptada);
}

void main() {
  testWidgets('Búsqueda: nombre, materia, filtros, sin resultados y limpiar', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repos = await LocalRepositories.open();
    await tester.pumpWidget(AppProviders.local(repos, child: const TutoreaApp()));
    await _loginStudent(tester);

    // Inicio → Búsqueda (ícono de la lupa).
    await tester.tap(find.byTooltip('Buscar'));
    await tester.pumpAndSettle();
    expect(find.text('Buscar tutores'), findsOneWidget);
    expect(find.text('5 tutores'), findsOneWidget);

    final field = find.byKey(const Key('tutor-search-field'));

    // Por materia: se actualiza al escribir.
    await tester.enterText(field, 'finan');
    await tester.pumpAndSettle();
    expect(find.text('Daniel Rivas'), findsOneWidget);
    expect(find.text('Valeria Gómez'), findsNothing);

    // Por nombre.
    await tester.enterText(field, 'valeria');
    await tester.pumpAndSettle();
    expect(find.text('Valeria Gómez'), findsOneWidget);
    expect(find.text('1 tutor'), findsOneWidget);

    // Sin resultados → mensaje y botón para limpiar.
    await tester.enterText(field, 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No encontramos tutores con esa búsqueda.'), findsOneWidget);
    await tester.tap(find.text('Limpiar búsqueda y filtros'));
    await tester.pumpAndSettle();
    expect(find.text('5 tutores'), findsOneWidget);

    // Categoría + texto combinados.
    await tester.tap(find.text('Matemáticas'));
    await tester.pumpAndSettle();
    expect(find.text('2 tutores'), findsOneWidget);
    await tester.enterText(field, 'andres');
    await tester.pumpAndSettle();
    expect(find.text('Andrés Martínez'), findsOneWidget);
    expect(find.text('Valeria Gómez'), findsNothing);

    // Abrir el perfil y volver: la búsqueda se conserva.
    await tester.tap(find.text('Andrés Martínez'));
    await tester.pumpAndSettle();
    expect(find.text('Reservar sesión'), findsOneWidget);
    await tester.tap(find.byTooltip('Volver')); // botón volver de la app
    await tester.pumpAndSettle();
    expect(find.text('Andrés Martínez'), findsOneWidget);
    expect(find.text('andres'), findsOneWidget); // texto del buscador

    // "Limpiar" en la barra superior quita texto y filtros.
    await tester.tap(find.text('Limpiar'));
    await tester.pumpAndSettle();
    expect(find.text('5 tutores'), findsOneWidget);
  });

  testWidgets('Detalle de una reserva y cancelación desde el detalle', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repos = await LocalRepositories.open();
    await _seed(repos);
    await tester.pumpWidget(AppProviders.local(repos, child: const TutoreaApp()));
    await _loginStudent(tester);
    await _openMyBookings(tester);

    // Solo la pendiente ofrece cancelar.
    expect(find.text('Pendiente'), findsOneWidget);
    expect(find.text('Aceptada'), findsOneWidget);
    expect(find.text('Cancelar solicitud'), findsOneWidget);

    // Abrir el detalle desde la tarjeta.
    await tester.tap(find.text('Estadística'));
    await tester.pumpAndSettle();
    expect(find.text('Reserva'), findsOneWidget);
    expect(find.text('Valeria Gómez'), findsOneWidget);
    expect(find.text('Pendiente'), findsOneWidget);
    expect(find.text('Estadística'), findsOneWidget);
    expect(find.text('Distribuciones'), findsOneWidget);
    expect(find.text('1.5 horas'), findsOneWidget);
    expect(find.text('\$15'), findsOneWidget); // 1.5 h × $10
    await tester.scrollUntilVisible(find.text('Ver perfil del tutor'), 200,
        scrollable: _listScrollable);
    expect(find.text('Sobre el tutor'), findsOneWidget);
    expect(find.text('\$10/hora'), findsOneWidget);

    // Cancelar (con confirmación).
    await tester.tap(find.text('Cancelar solicitud'));
    await tester.pumpAndSettle();
    expect(find.text('¿Cancelar solicitud?'), findsOneWidget);
    await tester.tap(find.text('Sí, cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Solicitud cancelada'), findsOneWidget);
    // El detalle se actualiza (el estado está arriba; antes se hizo scroll hacia abajo).
    await tester.scrollUntilVisible(find.text('Cancelada'), -200, scrollable: _listScrollable);
    expect(find.text('Cancelada'), findsOneWidget);
    expect(find.text('Cancelaste esta solicitud.'), findsOneWidget);
    expect(find.text('Cancelar solicitud'), findsNothing);

    // Volver: la lista también se actualizó.
    await tester.tap(find.byTooltip('Volver')); // botón volver de la app
    await tester.pumpAndSettle();
    expect(find.text('Pendiente'), findsNothing);
    expect(find.text('Aceptada'), findsOneWidget);
    expect(find.text('Cancelar solicitud'), findsNothing);
    await tester.tap(find.text('Historial'));
    await tester.pumpAndSettle();
    expect(find.text('Cancelada'), findsOneWidget);

    // Una aceptada no se puede cancelar.
    await tester.tap(find.text('Próximas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finanzas'));
    await tester.pumpAndSettle();
    expect(find.text('Aceptada'), findsOneWidget);
    expect(find.text('Cancelar solicitud'), findsNothing);
    expect(find.textContaining('ya no se puede cancelar'), findsOneWidget);
  });

  testWidgets('Cancelar desde Mis reservas y conservarlo al reabrir la app', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repos = await LocalRepositories.open();
    await _seed(repos);
    await tester.pumpWidget(AppProviders.local(repos, child: const TutoreaApp()));
    await _loginStudent(tester);
    await _openMyBookings(tester);

    // La tarjeta pendiente puede quedar bajo la barra inferior: llevarla a la vista.
    await tester.ensureVisible(find.text('Cancelar solicitud'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar solicitud'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí, cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Solicitud cancelada'), findsOneWidget);
    expect(find.text('Pendiente'), findsNothing);

    // "Reinicio": repositorios nuevos sobre lo guardado.
    final prefs = await SharedPreferences.getInstance();
    SharedPreferences.setMockInitialValues(
        {for (final k in prefs.getKeys()) k: prefs.get(k)!});
    final reopened = await LocalRepositories.open();
    final saved = await reopened.bookings.getForStudent('u-sergio');
    expect(saved.firstWhere((b) => b.id == 'bk-pend').estado, BookingStatus.cancelada);
  });
}

/// Pantalla inicial: elegir ESEN y continuar (si se está en esa pantalla).
Future<void> _chooseEsen(WidgetTester tester) async {
  await tester.pumpAndSettle();
  if (find.text('Selecciona tu universidad').evaluate().isEmpty) return;
  await tester.tap(find.text('Escuela Superior de Economía y Negocios (ESEN)'));
  await tester.pump();
  final continuar = find.widgetWithText(ElevatedButton, 'Continuar');
  await tester.ensureVisible(continuar);
  await tester.tap(continuar);
  await tester.pumpAndSettle();
}

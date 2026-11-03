import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorea/data/local/local_repositories.dart';
import 'package:tutorea/domain/models/models.dart';
import 'package:tutorea/main.dart';
import 'package:tutorea/routes/app_navigator.dart';
import 'package:tutorea/state/app_providers.dart';
import 'package:tutorea/theme/app_colors.dart';
import 'package:tutorea/widgets/booking_status_badge.dart';

void main() {
  testWidgets('Bienvenida → Login → Inicio → Perfil → Reserva → Mis reservas',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repos = await LocalRepositories.open();
    await tester.pumpWidget(AppProviders.local(repos, child: const TutoreaApp()));

    // Sin sesión, la app abre en la selección de universidad.
    await tester.pumpAndSettle();
    expect(find.text('Selecciona tu universidad'), findsOneWidget);
    await _chooseEsen(tester);
    expect(find.text('Tutorea'), findsOneWidget);
    expect(find.text('Aprende mejor, con\nestudiantes como tú.'), findsOneWidget);
    expect(find.text('ESEN'), findsOneWidget); // universidad elegida

    // Bienvenida → Login.
    final welcomeLogin = find.widgetWithText(ElevatedButton, 'Iniciar sesión');
    await tester.ensureVisible(welcomeLogin);
    await tester.tap(welcomeLogin);
    await tester.pumpAndSettle();

    // Contraseña incorrecta: muestra el error del store.
    await tester.enterText(find.widgetWithText(TextFormField, 'Correo'), 'sergio@esen.edu.sv');
    await tester.enterText(find.widgetWithText(TextFormField, 'Contraseña'), 'mala');
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Iniciar sesión'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Iniciar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('Correo o contraseña incorrectos.'), findsOneWidget);

    // Contraseña correcta (estudiante) → Inicio del estudiante.
    await tester.enterText(find.widgetWithText(TextFormField, 'Contraseña'), 'tutorea123');
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Iniciar sesión'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(find.text('Hola, Sergio'), findsOneWidget);
    expect(find.text('Tutores recomendados'), findsOneWidget);
    expect(find.text('Valeria Gómez'), findsOneWidget);

    // Tocar un tutor abre su perfil.
    await tester.ensureVisible(find.text('Valeria Gómez'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Valeria Gómez'));
    await tester.pumpAndSettle();
    expect(find.text('Licenciatura en Economía y Negocios'), findsOneWidget); // carrera real
    expect(find.text('Sobre mí'), findsOneWidget);
    expect(find.text('\$10/hora'), findsOneWidget);

    // "Reservar sesión" abre la reserva con el tutor seleccionado.
    await tester.tap(find.text('Reservar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('Enviar solicitud'), findsOneWidget);
    // El resumen está al final de la lista: hacer scroll hasta verlo.
    // Fecha y hora vienen preseleccionadas (primer horario disponible).
    await tester.scrollUntilVisible(
      find.text('Total: \$10'),
      200,
      scrollable: find
          .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
          .first,
    );
    expect(find.text('Total: \$10'), findsOneWidget);

    // "Enviar solicitud" crea la reserva en BookingStore y abre Mis reservas.
    await tester.tap(find.text('Enviar solicitud'));
    await tester.pumpAndSettle();
    expect(find.text('Solicitud enviada correctamente'), findsOneWidget);
    expect(find.text('Próximas'), findsOneWidget);
    expect(find.text('Pendiente'), findsOneWidget);
    expect(find.text('Valeria Gómez'), findsOneWidget);

    // Historial: todavía vacío.
    await tester.tap(find.text('Historial'));
    await tester.pumpAndSettle();
    expect(find.text('Sin tutorías anteriores'), findsOneWidget);

    // Barra inferior: ir a Perfil y volver a Mis reservas desde su menú.
    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();
    expect(find.text('Información académica'), findsOneWidget);
    // Datos reales del estudiante autenticado (no MockData).
    expect(find.text('Sergio'), findsOneWidget);
    expect(find.text('sergio@esen.edu.sv'), findsOneWidget);
    expect(find.text('Escuela Superior de Economía y Negocios (ESEN)'), findsOneWidget);
    expect(find.text('Licenciatura en Economía y Negocios'), findsOneWidget);
    expect(find.text('2.º año'), findsOneWidget);
  });

  testWidgets('Tutor: Dashboard → Solicitudes → aceptar y rechazar → estudiante ve el resultado',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repos = await LocalRepositories.open();
    await _seedRequests(repos);
    // Una cuarta solicitud a Valeria que el estudiante canceló.
    await repos.bookings.create(Booking(
      id: 'bk-test-4',
      studentId: 'u-sergio',
      tutorId: 'tp-valeria',
      subjectId: 'mic',
      fechaHora: _next(DateTime.thursday, 10),
      duracion: 60,
      precio: 0,
    ));
    await repos.bookings.updateStatus('bk-test-4', BookingStatus.cancelada);
    await tester.pumpWidget(AppProviders.local(repos, child: const TutoreaApp()));

    // 1. El tutor entra a su Dashboard.
    await _login(tester, 'valeria@esen.edu.sv');
    expect(find.text('Hola, Valeria'), findsOneWidget);
    expect(find.textContaining('Escuela Superior de Economía y Negocios'), findsWidgets);
    expect(_stat(tester, 'Pendientes'), '2');
    expect(_stat(tester, 'Aceptadas'), '0');

    // 2. Solo ve sus solicitudes (la de Daniel, Finanzas, no aparece).
    expect(find.text('Finanzas'), findsNothing);
    expect(find.text('Sergio'), findsWidgets); // nombre, no el id del estudiante
    expect(find.textContaining('u-sergio'), findsNothing);

    // 3. Consulta las pendientes.
    // (Desde la barra inferior del tutor; el botón "Ver solicitudes" queda
    // fuera de pantalla con 2 tarjetas en el resumen.)
    await tester.tap(find.descendant(
        of: find.byType(BottomNavigationBar), matching: find.text('Solicitudes')));
    await tester.pumpAndSettle();
    expect(find.text('Pendientes (2)'), findsOneWidget);
    // La cancelada tiene su propia pestaña y no cuenta como rechazada.
    expect(find.text('Rechazadas (0)'), findsOneWidget);
    expect(find.text('Canceladas (1)'), findsOneWidget);

    // 4. Acepta la de Estadística.
    await tester.tap(find.text('Estadística'));
    await tester.pumpAndSettle();
    expect(find.text('Rechazar'), findsOneWidget);
    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();
    expect(find.text('Solicitud aceptada'), findsOneWidget);
    expect(find.text('Pendientes (1)'), findsOneWidget);
    expect(find.text('Aceptadas (1)'), findsOneWidget);

    // 5. Rechaza la de Matemáticas (con confirmación).
    await tester.tap(find.text('Matemáticas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rechazar'));
    await tester.pumpAndSettle();
    expect(find.text('¿Rechazar solicitud?'), findsOneWidget);
    await tester.tap(find.text('Sí, rechazar'));
    await tester.pumpAndSettle();
    expect(find.text('Pendientes (0)'), findsOneWidget);
    expect(find.text('Rechazadas (1)'), findsOneWidget);
    expect(find.text('Canceladas (1)'), findsOneWidget);

    // Pestaña Canceladas: solo la de Microeconomía, con su etiqueta propia.
    await _tapTab(tester, 'Canceladas (1)');
    await tester.pumpAndSettle();
    expect(find.text('Microeconomía'), findsOneWidget);
    expect(find.text('Cancelada'), findsOneWidget);
    expect(find.text('Rechazada'), findsNothing);
    await _tapTab(tester, 'Rechazadas (1)');
    await tester.pumpAndSettle();
    expect(find.text('Matemáticas'), findsOneWidget);
    expect(find.text('Rechazada'), findsOneWidget);
    expect(find.text('Cancelada'), findsNothing);

    // 6. Una solicitud aceptada ya no muestra botones.
    await _tapTab(tester, 'Aceptadas (1)');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Estadística'));
    await tester.pumpAndSettle();
    expect(find.text('Aceptar'), findsNothing);
    expect(find.text('Rechazar'), findsNothing);
    await tester.scrollUntilVisible(find.textContaining('no se puede modificar'), 200,
        scrollable: find
            .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    expect(find.textContaining('no se puede modificar'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    // Mi perfil → Cerrar sesión → Bienvenida.
    await tester.tap(find.descendant(
        of: find.byType(BottomNavigationBar), matching: find.text('Mi perfil')));
    await tester.pumpAndSettle();
    // El SnackBar "Solicitud rechazada" sigue visible y tapa "Cerrar sesión".
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).clearSnackBars();
    await tester.pumpAndSettle();
    final profileList = find
        .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(find.text('Materias que ofrezco'), 200,
        scrollable: profileList);
    expect(find.text('Materias que ofrezco'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Cerrar sesión'), 200,
        scrollable: profileList);
    // Que quede completo en pantalla (no solo el borde sobre la barra inferior).
    await tester.ensureVisible(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('Selecciona tu universidad'), findsOneWidget); // vuelve al inicio

    // 7. El estudiante ve el resultado en Mis reservas.
    await _login(tester, 'sergio@esen.edu.sv');
    await tester.tap(find.descendant(
        of: find.byType(BottomNavigationBar), matching: find.text('Mis reservas')));
    await tester.pumpAndSettle();
    expect(find.text('Aceptada'), findsOneWidget); // Valeria · Estadística
    expect(find.text('Pendiente'), findsOneWidget); // Daniel · Finanzas
    await tester.tap(find.text('Historial'));
    await tester.pumpAndSettle();
    expect(find.text('Rechazada'), findsOneWidget); // Valeria · Matemáticas
    expect(find.text('Cancelada'), findsOneWidget); // Valeria · Microeconomía
    expect(find.byType(BookingStatusBadge), findsNWidgets(2)); // etiqueta compartida
  });

  testWidgets('8. Al reabrir la app, el tutor vuelve a su Dashboard con los datos guardados',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repos = await LocalRepositories.open();
    final ids = await _seedRequests(repos);
    await repos.bookings.updateStatus(ids.first, BookingStatus.aceptada);
    await repos.auth.login(correo: 'valeria@esen.edu.sv', password: 'tutorea123');

    // "Reinicio": nuevos repositorios sobre lo guardado en shared_preferences.
    final prefs = await SharedPreferences.getInstance();
    SharedPreferences.setMockInitialValues(
        {for (final k in prefs.getKeys()) k: prefs.get(k)!});
    final reopened = await LocalRepositories.open();
    final session = await reopened.auth.currentSession();
    expect(session.rol, UserRole.tutor);

    await tester.pumpWidget(AppProviders.local(
      reopened,
      child: TutoreaApp(initialRoute: AppNavigator.homeRouteFor(session.rol!)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Hola, Valeria'), findsOneWidget);
    expect(_stat(tester, 'Pendientes'), '1');
    expect(_stat(tester, 'Aceptadas'), '1');
  });

  testWidgets('Horarios distintos por día se conservan al guardar el perfil',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repos = await LocalRepositories.open();
    const horarios = [
      AvailabilitySlot(diaSemana: 1, horaInicio: 8 * 60, horaFin: 12 * 60),
      AvailabilitySlot(diaSemana: 3, horaInicio: 14 * 60, horaFin: 18 * 60),
      AvailabilitySlot(diaSemana: 6, horaInicio: 9 * 60, horaFin: 11 * 60),
    ];
    final original = (await repos.tutors.getById('tp-valeria'))!;
    await repos.tutors.save(original.copyWith(disponibilidad: horarios));

    await tester.pumpWidget(AppProviders.local(repos, child: const TutoreaApp()));
    await _login(tester, 'valeria@esen.edu.sv');
    await tester.tap(find.descendant(
        of: find.byType(BottomNavigationBar), matching: find.text('Mi perfil')));
    await tester.pumpAndSettle();

    // Mi perfil muestra cada horario por separado.
    final profileList = find
        .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(find.text('8:00 AM – 12:00 PM'), 200,
        scrollable: profileList);
    expect(find.text('2:00 PM – 6:00 PM'), findsOneWidget);
    expect(find.text('9:00 AM – 11:00 AM'), findsOneWidget);

    // Editar → Guardar sin cambios: no se reemplazan por un mismo horario.
    await tester.scrollUntilVisible(find.text('Editar perfil'), 200, scrollable: profileList);
    await tester.tap(find.text('Editar perfil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar perfil'));
    await tester.pumpAndSettle();
    expect(find.text('Perfil guardado'), findsOneWidget);

    final saved = (await repos.tutors.getById('tp-valeria'))!;
    expect(saved.disponibilidad, horarios);

    // "Reabrir": repositorios nuevos sobre los mismos datos.
    final prefs = await SharedPreferences.getInstance();
    SharedPreferences.setMockInitialValues(
        {for (final k in prefs.getKeys()) k: prefs.get(k)!});
    final reopened = await LocalRepositories.open();
    expect((await reopened.tutors.getById('tp-valeria'))!.disponibilidad, horarios);
  });

  testWidgets('BookingStatusBadge: nombre y colores de cada estado', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          for (final status in BookingStatus.values) BookingStatusBadge(status: status),
        ]),
      ),
    ));

    Color background(String label) {
      final box = tester.widget<Container>(find.ancestor(
          of: find.text(label), matching: find.byType(Container)).first);
      return (box.decoration! as BoxDecoration).color!;
    }

    Color? foreground(String label) => tester.widget<Text>(find.text(label)).style?.color;

    expect(background('Pendiente'), AppColors.warningLight);
    expect(foreground('Pendiente'), AppColors.warningDark);
    expect(background('Aceptada'), AppColors.successLight);
    expect(foreground('Aceptada'), AppColors.success);
    expect(background('Rechazada'), AppColors.errorLight);
    expect(foreground('Rechazada'), AppColors.error);
    expect(background('Cancelada'), AppColors.errorLight);
    expect(foreground('Cancelada'), AppColors.error);
  });
}

/// Bienvenida → Login con la contraseña de las cuentas de ejemplo.
Future<void> _login(WidgetTester tester, String correo) async {
  await _chooseEsen(tester);
  final welcomeLogin = find.widgetWithText(ElevatedButton, 'Iniciar sesión');
  await tester.ensureVisible(welcomeLogin);
  await tester.tap(welcomeLogin);
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextFormField, 'Correo'), correo);
  await tester.enterText(find.widgetWithText(TextFormField, 'Contraseña'), 'tutorea123');
  await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Iniciar sesión'));
  await tester.tap(find.widgetWithText(ElevatedButton, 'Iniciar sesión'));
  await tester.pumpAndSettle();
}

/// Toca una pestaña de Solicitudes del tutor. La barra de 4 pestañas se
/// desplaza: primero se lleva la pestaña a la vista.
Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// Valor de un contador del Dashboard del tutor.
String? _stat(WidgetTester tester, String label) =>
    tester.widget<Text>(find.byKey(Key('tutor-stat-$label'))).data;

/// Próximo [weekday] (1 = lunes) a la hora indicada, siempre en el futuro.
DateTime _next(int weekday, int hour) {
  var day = DateTime.now().add(const Duration(days: 1));
  while (day.weekday != weekday) {
    day = day.add(const Duration(days: 1));
  }
  return DateTime(day.year, day.month, day.day, hour);
}

/// Sergio envía 2 solicitudes a Valeria (Estadística, Matemáticas)
/// y 1 a Daniel (Finanzas). Devuelve los ids en ese orden.
Future<List<String>> _seedRequests(LocalRepositories repos) async {
  final requests = [
    ('bk-test-1', 'tp-valeria', 'est', _next(DateTime.tuesday, 10)),
    ('bk-test-2', 'tp-valeria', 'mat', _next(DateTime.tuesday, 14)),
    ('bk-test-3', 'tp-daniel', 'fin', _next(DateTime.monday, 10)),
  ];
  for (final (id, tutorId, subjectId, start) in requests) {
    await repos.bookings.create(Booking(
      id: id,
      studentId: 'u-sergio',
      tutorId: tutorId,
      subjectId: subjectId,
      fechaHora: start,
      duracion: 60,
      precio: 0,
    ));
  }
  return [for (final r in requests) r.$1];
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

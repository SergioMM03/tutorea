import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorea/data/local/local_auth_repository.dart';
import 'package:tutorea/data/local/local_booking_repository.dart';
import 'package:tutorea/data/local/local_database.dart';
import 'package:tutorea/data/local/local_seed.dart';
import 'package:tutorea/data/local/local_subject_repository.dart';
import 'package:tutorea/data/local/local_tutor_repository.dart';
import 'package:tutorea/data/local/local_university_repository.dart';
import 'package:tutorea/domain/models/models.dart';
import 'package:tutorea/domain/repositories/repositories.dart';

void main() {
  late LocalDatabase db;
  late LocalAuthRepository auth;
  late LocalTutorRepository tutors;
  late LocalBookingRepository bookings;

  // "Hoy" fijo para las pruebas: lunes 13 de octubre de 2025.
  final now = DateTime(2025, 10, 13, 7);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await LocalDatabase.open();
    auth = LocalAuthRepository(db);
    tutors = LocalTutorRepository(db);
    bookings = LocalBookingRepository(db, tutors, now: () => now);
  });

  test('Carga los datos iniciales', () async {
    expect((await LocalSubjectRepository(db).getAll()).length, LocalSeed.subjects.length);
    expect((await tutors.getAvailable()).length, 5);
    expect((await tutors.getAvailable(categoria: 'Negocios')).length, 2);
    expect((await tutors.getAvailable(subjectId: 'est')).single.id, 'tp-valeria');
  });

  test('Registro, sesión, cierre e inicio de sesión', () async {
    final user = await auth.register(
      nombre: 'Ana',
      correo: 'ANA@esen.edu.sv',
      password: 'clave123',
      careerId: LocalSeed.eyn,
      carrera: 'Economía',
      anioAcademico: 1,
      rol: UserRole.estudiante,
    );
    expect(user.correo, 'ana@esen.edu.sv');
    expect((await auth.currentSession()).usuario?.id, user.id);

    await expectLater(
      auth.register(
          nombre: 'Ana 2',
          correo: 'ana@esen.edu.sv',
          password: 'clave123',
          careerId: LocalSeed.eyn,
          carrera: 'X',
          anioAcademico: 1,
          rol: UserRole.tutor),
      throwsA(isA<RepositoryException>()),
    );

    await auth.logout();
    expect((await auth.currentSession()).iniciada, isFalse);

    await expectLater(auth.login(correo: 'ana@esen.edu.sv', password: 'mala'),
        throwsA(isA<RepositoryException>()));
    final again = await auth.login(correo: 'ana@esen.edu.sv', password: 'clave123');
    expect(again.id, user.id);
  });

  test('Solicitud: crear, validar y aceptar', () async {
    Booking request(DateTime when, {String student = 'u-sergio'}) => Booking(
          id: 'b-${when.millisecondsSinceEpoch}-$student',
          studentId: student,
          tutorId: 'tp-valeria',
          subjectId: 'est',
          fechaHora: when,
          duracion: 60,
          precio: 0,
        );

    final tuesday10 = DateTime(2025, 10, 14, 10);
    final created = await bookings.create(request(tuesday10));
    expect(created.estado, BookingStatus.pendiente);
    expect(created.precio, 10); // calculado con el precio del tutor

    // Duplicada, en domingo (no atiende) y en el pasado → rechazadas.
    await expectLater(bookings.create(request(tuesday10)), throwsA(isA<RepositoryException>()));
    await expectLater(bookings.create(request(DateTime(2025, 10, 19, 10))),
        throwsA(isA<RepositoryException>()));
    await expectLater(bookings.create(request(DateTime(2025, 10, 10, 10))),
        throwsA(isA<RepositoryException>()));

    expect((await bookings.getForTutor('tp-valeria')).single.id, created.id);
    expect((await bookings.getForStudent('u-sergio')).single.id, created.id);

    final accepted = await bookings.updateStatus(created.id, BookingStatus.aceptada);
    expect(accepted.estado, BookingStatus.aceptada);

    // Ya no se puede rechazar una aceptada.
    await expectLater(bookings.updateStatus(created.id, BookingStatus.rechazada),
        throwsA(isA<RepositoryException>()));

    // Otro estudiante en el mismo horario: el tutor ya está ocupado.
    await expectLater(bookings.create(request(tuesday10, student: 'u-otro')),
        throwsA(isA<RepositoryException>()));
  });

  test('ESEN y sus carreras; materias por carrera', () async {
    final universities = LocalUniversityRepository(db);
    final active = await universities.getActive();
    expect(active.single.id, kDefaultUniversityId);
    expect((await universities.getCareers(kDefaultUniversityId)).length, 4);

    final subjects = LocalSubjectRepository(db);
    final software = await subjects.getAll(careerId: LocalSeed.software);
    expect(software.map((s) => s.id), containsAll(['pro', 'bdd', 'mat'])); // + comunes
    expect(software.map((s) => s.id), isNot(contains('mic')));

    expect((await tutors.getAvailable(universityId: kDefaultUniversityId)).length, 5);
    expect((await tutors.getAvailable(universityId: 'otra')).length, 0);

    final sergio = await auth.login(correo: 'sergio@esen.edu.sv', password: LocalSeed.demoPassword);
    expect(sergio.careerId, LocalSeed.eyn);
  });

  test('Migración v1 → v2 conserva cuentas, perfiles y solicitudes', () async {
    // Datos guardados con la versión 1 (sin universidades).
    SharedPreferences.setMockInitialValues({
      LocalDatabase.seedVersion: 1,
      LocalDatabase.users: '[{"id":"u-nueva","nombre":"Ana","correo":"ana@esen.edu.sv",'
          '"password":"clave123","carrera":"Economía y Negocios","anioAcademico":1,'
          '"rol":"estudiante","fechaCreacion":"2026-10-10T10:00:00.000"}]',
      LocalDatabase.tutorProfiles: '[{"id":"tp-x","userId":"u-x","descripcion":"d",'
          '"precioHora":8,"materias":["est"],"disponibilidad":[],"rating":0,"activo":true}]',
      LocalDatabase.bookings: '[{"id":"b1","studentId":"u-nueva","tutorId":"tp-x",'
          '"subjectId":"est","tema":null,"fechaHora":"2026-11-03T10:00:00.000",'
          '"duracion":60,"precio":8,"estado":"pendiente"}]',
    });
    final migrated = await LocalDatabase.open();

    expect(migrated.readInt(LocalDatabase.seedVersion), LocalSeed.version);
    final users = migrated.readList(LocalDatabase.users).map(AppUser.fromJson).toList();
    expect(users.single.id, 'u-nueva');
    expect(users.single.universityId, kDefaultUniversityId);
    expect(users.single.careerId, LocalSeed.eyn); // deducida del texto
    expect(migrated.readList(LocalDatabase.tutorProfiles).single['universityId'],
        kDefaultUniversityId);
    expect(migrated.readList(LocalDatabase.bookings).single['id'], 'b1');
    expect(migrated.readList(LocalDatabase.careers).length, 4);
  });
}

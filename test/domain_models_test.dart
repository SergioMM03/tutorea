import 'package:flutter_test/flutter_test.dart';
import 'package:tutorea/domain/models/models.dart';

void main() {
  test('AppUser: toJson/fromJson conserva los datos', () {
    final user = AppUser(
      id: 'u1',
      nombre: 'Sergio',
      correo: 'sergio@esen.edu.sv',
      password: 'secreta1',
      carrera: 'Economía y Negocios',
      anioAcademico: 2,
      rol: UserRole.estudiante,
      fechaCreacion: DateTime(2026, 10, 13, 8, 30),
    );
    final copy = AppUser.fromJson(user.toJson());
    expect(copy.nombre, 'Sergio');
    expect(copy.rol, UserRole.estudiante);
    expect(copy.fechaCreacion, user.fechaCreacion);
    expect(user.toPublicJson().containsKey('password'), isFalse);
  });

  test('TutorProfile: disponibilidad y JSON', () {
    const profile = TutorProfile(
      id: 'tp1',
      userId: 'u2',
      descripcion: 'Tutora de Estadística',
      precioHora: 10,
      materias: ['est'],
      disponibilidad: [AvailabilitySlot(diaSemana: 2, horaInicio: 480, horaFin: 720)],
      rating: 4.9,
    );
    // Martes 14 de octubre de 2025, 10:00 → cabe 1 hora; 11:30 + 1 h no cabe.
    expect(profile.disponibleEn(DateTime(2025, 10, 14, 10), 60), isTrue);
    expect(profile.disponibleEn(DateTime(2025, 10, 14, 11, 30), 60), isFalse);
    expect(profile.disponibleEn(DateTime(2025, 10, 15, 10), 60), isFalse); // miércoles
    expect(profile.completo, isTrue);

    final copy = TutorProfile.fromJson(profile.toJson());
    expect(copy.disponibilidad.single, profile.disponibilidad.single);
    expect(copy.materias, ['est']);
  });

  test('Booking: precio, fin, estados y JSON', () {
    final booking = Booking(
      id: 'b1',
      studentId: 'u1',
      tutorId: 'tp1',
      subjectId: 'est',
      tema: 'Distribuciones',
      fechaHora: DateTime(2025, 10, 14, 10),
      duracion: 90,
      precio: Booking.calcularPrecio(10, 90),
    );
    expect(booking.precio, 15);
    expect(booking.fin, DateTime(2025, 10, 14, 11, 30));
    expect(booking.estado, BookingStatus.pendiente);
    expect(BookingStatus.pendiente.puedeCambiarA(BookingStatus.aceptada), isTrue);
    expect(BookingStatus.aceptada.puedeCambiarA(BookingStatus.rechazada), isFalse);

    final copy = Booking.fromJson(booking.toJson());
    expect(copy.tema, 'Distribuciones');
    expect(copy.fechaHora, booking.fechaHora);
  });

  test('Session: guarda usuario y rol sin contraseña', () {
    final user = AppUser(
      id: 'u2',
      nombre: 'Valeria',
      correo: 'valeria@esen.edu.sv',
      password: 'secreta1',
      carrera: 'Economía',
      anioAcademico: 3,
      rol: UserRole.tutor,
      fechaCreacion: DateTime(2026, 10, 1),
    );
    final session = Session.forUser(user);
    final json = session.toJson();
    expect((json['usuario'] as Map).containsKey('password'), isFalse);

    final copy = Session.fromJson(json);
    expect(copy.iniciada, isTrue);
    expect(copy.rol, UserRole.tutor);
    expect(const Session.empty().iniciada, isFalse);
  });

  test('University y Career: JSON', () {
    const u = University(id: 'esen', nombre: 'ESEN', pais: 'El Salvador');
    expect(University.fromJson(u.toJson()).pais, 'El Salvador');
    const c = Career(id: 'esen-eyn', universityId: 'esen', nombre: 'Economía y Negocios');
    expect(Career.fromJson(c.toJson()).universityId, 'esen');
  });

  test('Datos guardados antes de universidades se leen como ESEN', () {
    final oldUser = AppUser.fromJson({
      'id': 'u1',
      'nombre': 'Ana',
      'correo': 'ana@esen.edu.sv',
      'password': 'x',
      'carrera': 'Economía',
      'anioAcademico': 1,
      'rol': 'estudiante',
      'fechaCreacion': '2026-10-01T00:00:00.000',
    });
    expect(oldUser.universityId, kDefaultUniversityId);
    expect(oldUser.careerId, isNull);

    final oldSubject = Subject.fromJson({'id': 'est', 'nombre': 'Estadística', 'categoria': 'Matemáticas'});
    expect(oldSubject.universityId, kDefaultUniversityId);
    expect(oldSubject.esDeCarrera('cualquiera'), isTrue); // común

    final oldProfile = TutorProfile.fromJson({
      'id': 'tp1',
      'userId': 'u2',
      'descripcion': 'x',
      'precioHora': 10,
      'materias': ['est'],
      'disponibilidad': [],
    });
    expect(oldProfile.universityId, kDefaultUniversityId);
  });
}

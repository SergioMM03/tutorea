import '../../domain/models/models.dart';
import 'local_database.dart';

/// Datos iniciales del MVP: ESEN (única universidad), sus carreras,
/// catálogo de materias, 5 tutores y 1 estudiante.
/// Contraseña de todas las cuentas de ejemplo: tutorea123
///
/// Versiones:
///   1 → primera versión (sin universidades).
///   2 → universidades y carreras. Al actualizar desde la 1 se MIGRAN los
///       datos guardados (cuentas creadas, perfiles y solicitudes se conservan).
class LocalSeed {
  LocalSeed._();

  static const int version = 2;
  static const String demoPassword = 'tutorea123';

  static Future<void> ensureSeeded(LocalDatabase db) async {
    final current = db.readInt(LocalDatabase.seedVersion);
    if (current == version) return;

    if (current == null) {
      await _seedFresh(db);
    } else {
      await _migrateFromV1(db);
    }
    await db.writeInt(LocalDatabase.seedVersion, version);
  }

  /// Instalación nueva: carga todo desde cero.
  static Future<void> _seedFresh(LocalDatabase db) async {
    await db.clear();
    await _writeCatalog(db);
    await db.writeList(LocalDatabase.users, users.map((u) => u.toJson()).toList());
    await db.writeList(
        LocalDatabase.tutorProfiles, tutorProfiles.map((p) => p.toJson()).toList());
    await db.writeList(LocalDatabase.bookings, const []);
  }

  /// v1 → v2 sin borrar datos del usuario.
  static Future<void> _migrateFromV1(LocalDatabase db) async {
    // Catálogo (datos del sistema): universidades, carreras y materias
    // con los ids de siempre más los campos nuevos.
    await _writeCatalog(db);

    // Cuentas: se asigna ESEN y, si se puede, la carrera.
    final seedUsers = {for (final u in users) u.id: u};
    final migratedUsers = db.readList(LocalDatabase.users).map((json) {
      final user = AppUser.fromJson(json); // universityId = 'esen' si faltaba
      final seed = seedUsers[user.id];
      if (seed != null) {
        return user.copyWith(careerId: seed.careerId, carrera: seed.carrera);
      }
      final career = matchCareer(user.carrera);
      return career == null ? user : user.copyWith(careerId: career.id);
    }).map((u) => u.toJson()).toList();
    await db.writeList(LocalDatabase.users, migratedUsers);

    // Perfiles de tutor: fromJson agrega universityId = 'esen'.
    final migratedProfiles = db
        .readList(LocalDatabase.tutorProfiles)
        .map(TutorProfile.fromJson)
        .map((p) => p.toJson())
        .toList();
    await db.writeList(LocalDatabase.tutorProfiles, migratedProfiles);

    // Solicitudes y sesión: no cambian.
  }

  static Future<void> _writeCatalog(LocalDatabase db) async {
    await db.writeList(
        LocalDatabase.universities, universities.map((u) => u.toJson()).toList());
    await db.writeList(LocalDatabase.careers, careers.map((c) => c.toJson()).toList());
    await db.writeList(LocalDatabase.subjects, subjects.map((s) => s.toJson()).toList());
  }

  /// Busca una carrera de ESEN por el texto que el usuario escribió.
  /// Ej. "economía y negocios" → Licenciatura en Economía y Negocios.
  static Career? matchCareer(String texto) {
    final t = texto.trim().toLowerCase();
    if (t.length < 4) return null; // muy corto para adivinar
    for (final c in careers) {
      final name = c.nombre.toLowerCase();
      if (name == t || name.contains(t) || t.contains(_core(name))) return c;
    }
    return null;
  }

  /// "licenciatura en economía y negocios" → "economía y negocios"
  static String _core(String name) =>
      name.replaceFirst('licenciatura en ', '').replaceFirst('ingeniería en ', '');

  // ---------------- Universidades ----------------
  static const List<University> universities = [
    University(
      id: kDefaultUniversityId,
      nombre: 'Escuela Superior de Economía y Negocios (ESEN)',
      pais: 'El Salvador',
    ),
  ];

  // ---------------- Carreras de ESEN ----------------
  static const String eyn = 'esen-eyn';
  static const String ingNegocios = 'esen-ing-negocios';
  static const String juridicas = 'esen-juridicas';
  static const String software = 'esen-software';

  static const List<Career> careers = [
    Career(id: eyn, universityId: kDefaultUniversityId,
        nombre: 'Licenciatura en Economía y Negocios'),
    Career(id: ingNegocios, universityId: kDefaultUniversityId,
        nombre: 'Ingeniería de Negocios'),
    Career(id: juridicas, universityId: kDefaultUniversityId,
        nombre: 'Licenciatura en Ciencias Jurídicas'),
    Career(id: software, universityId: kDefaultUniversityId,
        nombre: 'Ingeniería de Software y Negocios Digitales'),
  ];

  // ---------------- Materias ----------------
  // careerId null = materia común a varias carreras.
  // Los años son aproximados: ajustarlos con el plan de estudios real.
  static const List<Subject> subjects = [
    Subject(id: 'mat', nombre: 'Matemáticas', categoria: 'Matemáticas', anioAcademico: 1),
    Subject(id: 'est', nombre: 'Estadística', categoria: 'Matemáticas', anioAcademico: 2),
    Subject(id: 'cal', nombre: 'Cálculo', categoria: 'Matemáticas', anioAcademico: 1),
    Subject(id: 'alg', nombre: 'Álgebra lineal', categoria: 'Matemáticas', anioAcademico: 1),
    Subject(id: 'eco', nombre: 'Economía', categoria: 'Economía', careerId: eyn, anioAcademico: 1),
    Subject(id: 'mic', nombre: 'Microeconomía', categoria: 'Economía', careerId: eyn, anioAcademico: 2),
    Subject(id: 'mac', nombre: 'Macroeconomía', categoria: 'Economía', careerId: eyn, anioAcademico: 2),
    Subject(id: 'ecm', nombre: 'Econometría', categoria: 'Economía', careerId: eyn, anioAcademico: 3),
    Subject(id: 'fin', nombre: 'Finanzas', categoria: 'Negocios', careerId: ingNegocios, anioAcademico: 3),
    Subject(id: 'con', nombre: 'Contabilidad', categoria: 'Negocios', anioAcademico: 1),
    Subject(id: 'anf', nombre: 'Análisis financiero', categoria: 'Negocios', careerId: ingNegocios, anioAcademico: 3),
    Subject(id: 'pro', nombre: 'Programación', categoria: 'Tecnología', careerId: software, anioAcademico: 1),
    Subject(id: 'bdd', nombre: 'Bases de datos', categoria: 'Tecnología', careerId: software, anioAcademico: 2),
  ];

  // ---------------- Usuarios ----------------
  static final DateTime _created = DateTime(2026, 10, 1);

  static AppUser _user(String id, String nombre, String correo, String careerId,
      int anio, UserRole rol) {
    final career = careers.firstWhere((c) => c.id == careerId);
    return AppUser(
      id: id,
      nombre: nombre,
      correo: correo,
      password: demoPassword,
      universityId: kDefaultUniversityId,
      careerId: career.id,
      carrera: career.nombre,
      anioAcademico: anio,
      rol: rol,
      fechaCreacion: _created,
    );
  }

  static final List<AppUser> users = [
    _user('u-sergio', 'Sergio', 'sergio@esen.edu.sv', eyn, 2, UserRole.estudiante),
    _user('u-valeria', 'Valeria Gómez', 'valeria@esen.edu.sv', eyn, 3, UserRole.tutor),
    _user('u-daniel', 'Daniel Rivas', 'daniel@esen.edu.sv', eyn, 3, UserRole.tutor),
    _user('u-camila', 'Camila Torres', 'camila@esen.edu.sv', ingNegocios, 4, UserRole.tutor),
    _user('u-andres', 'Andrés Martínez', 'andres@esen.edu.sv', ingNegocios, 4, UserRole.tutor),
    _user('u-sofia', 'Sofía Hernández', 'sofia@esen.edu.sv', software, 3, UserRole.tutor),
  ];

  // ---------------- Perfiles de tutor ----------------
  /// Bloques de 8:00 AM a 8:00 PM en los días indicados (1 = lunes).
  static List<AvailabilitySlot> _days(List<int> days) => [
        for (final d in days) AvailabilitySlot(diaSemana: d, horaInicio: 480, horaFin: 1200),
      ];

  static final List<TutorProfile> tutorProfiles = [
    TutorProfile(
      id: 'tp-valeria',
      userId: 'u-valeria',
      descripcion: 'Estudiante de tercer año de Economía en la ESEN. Me apasiona '
          'enseñar y ayudar a otros estudiantes a entender los temas de una '
          'manera práctica y clara.',
      precioHora: 10,
      materias: const ['est', 'mat', 'mic', 'mac', 'ecm'],
      disponibilidad: _days([1, 2, 3, 4, 5, 6]),
      rating: 4.9,
    ),
    TutorProfile(
      id: 'tp-daniel',
      userId: 'u-daniel',
      descripcion: 'Estudiante de Economía y Negocios. Explico paso a paso con '
          'ejercicios reales.',
      precioHora: 12,
      materias: const ['eco', 'fin'],
      disponibilidad: _days([1, 3, 5]),
      rating: 4.8,
    ),
    TutorProfile(
      id: 'tp-camila',
      userId: 'u-camila',
      descripcion: 'Estudiante de Ingeniería de Negocios. Me enfoco en que '
          'entiendas el porqué de cada cálculo.',
      precioHora: 10,
      materias: const ['con', 'anf'],
      disponibilidad: _days([2, 4, 6]),
      rating: 4.9,
    ),
    TutorProfile(
      id: 'tp-andres',
      userId: 'u-andres',
      descripcion: 'Estudiante de cuarto año de Ingeniería de Negocios. Resuelvo '
          'ejercicios de parciales anteriores para que llegues preparado.',
      precioHora: 11,
      materias: const ['cal', 'alg'],
      disponibilidad: _days([1, 2, 4]),
      rating: 4.7,
    ),
    TutorProfile(
      id: 'tp-sofia',
      userId: 'u-sofia',
      descripcion: 'Estudiante de Ingeniería de Software y Negocios Digitales. '
          'Te ayudo a entender la lógica antes de escribir código.',
      precioHora: 15,
      materias: const ['pro', 'bdd'],
      disponibilidad: _days([3, 5, 6]),
      rating: 5.0,
    ),
  ];
}

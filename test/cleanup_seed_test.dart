import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorea/data/local/local_repositories.dart';
import 'package:tutorea/data/local/local_seed.dart';
import 'package:tutorea/state/session_store.dart';
import 'package:tutorea/state/tutor_store.dart';

/// Fase 13.7: el prototipo antiguo ya no existe y los datos seed de la
/// demostración siguen completos y funcionando.
void main() {
  group('Sin código del prototipo antiguo', () {
    const removed = [
      'lib/data/mock_data.dart',
      'lib/data/repositories.dart',
      'lib/data/tutor_repository.dart',
      'lib/models/tutor.dart',
      'lib/models/student.dart',
      'lib/models/subject.dart',
    ];

    test('los archivos del prototipo fueron eliminados', () {
      for (final path in removed) {
        expect(File(path).existsSync(), isFalse, reason: '$path debería estar eliminado');
      }
    });

    test('ningún archivo de lib/ usa MockData ni los modelos antiguos', () {
      final dartFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      for (final file in dartFiles) {
        final code = file.readAsStringSync();
        expect(code.contains('MockData'), isFalse, reason: file.path);
        expect(code.contains('mock_data.dart'), isFalse, reason: file.path);
        expect(RegExp(r"import '[./]*models/(tutor|student|subject)\.dart'").hasMatch(code),
            isFalse,
            reason: file.path);
      }
    });
  });

  group('Datos seed de la demostración', () {
    late LocalRepositories repos;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      repos = await LocalRepositories.open();
    });

    test('ESEN es la única universidad, con sus carreras y materias', () async {
      final active = await repos.universities.getActive();
      expect(active.map((u) => u.id), ['esen']);
      expect(await repos.universities.getCareers('esen'), hasLength(LocalSeed.careers.length));
      expect(await repos.subjects.getAll(universityId: 'esen'), hasLength(LocalSeed.subjects.length));
    });

    test('todas las cuentas seed inician sesión con ESEN elegida', () async {
      final session = SessionStore(repos.auth, repos.universities);
      await session.loadUniversities();
      expect(await session.selectUniversity('esen'), isTrue);

      for (final user in LocalSeed.users) {
        expect(await session.login(correo: user.correo, password: LocalSeed.demoPassword), isTrue,
            reason: user.correo);
        expect(session.role, user.rol);
        await session.logout();
      }
    });

    test('los 5 tutores seed aparecen en el catálogo de ESEN', () async {
      final tutors = TutorStore(repos.tutors, repos.subjects, repos.auth, repos.universities);
      await tutors.loadForUniversity('esen');
      expect(tutors.availableTutors.map((t) => t.id).toSet(),
          LocalSeed.tutorProfiles.map((p) => p.id).toSet());
    });

    // Fase 13.8: ya no hay fotografías ficticias de tutores.
    test('los tutores seed no tienen fotografía (se muestran sus iniciales)', () {
      for (final profile in LocalSeed.tutorProfiles) {
        expect(profile.photoPath, isNull, reason: profile.id);
      }
      for (final name in ['valeria', 'daniel', 'camila']) {
        expect(File('assets/images/$name.png').existsSync(), isFalse,
            reason: 'assets/images/$name.png debería estar eliminado');
      }
      expect(File('lib/utils/tutor_photo.dart').existsSync(), isFalse);
    });
  });
}

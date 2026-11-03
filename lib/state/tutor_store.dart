import 'package:flutter/foundation.dart';

import '../domain/models/models.dart';
import '../domain/repositories/repositories.dart';

/// Lo que la UI necesita para mostrar un tutor: perfil + cuenta + materias.
/// (El perfil solo guarda ids; aquí se resuelven nombres.)
class TutorSummary {
  final TutorProfile profile;
  final AppUser user;
  final List<Subject> subjects;

  const TutorSummary({
    required this.profile,
    required this.user,
    required this.subjects,
  });

  String get id => profile.id;
  String get nombre => user.nombre;
  double get precioHora => profile.precioHora;
  double get rating => profile.rating;

  /// Promedio para mostrar, o null si es «Nuevo» (sin reseñas).
  double? get calificacion => profile.calificacion;
  int get totalResenas => profile.totalResenas;
}

/// Tutores: lista para estudiantes y perfil propio para tutores.
/// UI → TutorStore → TutorRepository / SubjectRepository → almacenamiento.
///
/// Búsqueda del estudiante:
/// - universidad, categoría y materia se filtran en el repositorio;
/// - texto (nombre del tutor o materia) y carrera se filtran aquí, sobre
///   los tutores ya cargados ([searchResults]), así se actualiza al escribir.
class TutorStore extends ChangeNotifier {
  final TutorRepository _tutors;
  final SubjectRepository _subjects;
  final AuthRepository _auth; // solo para leer el nombre de cada tutor
  final UniversityRepository? _universities; // solo para nombres de carrera
  final ProfilePhotoRepository? _photos; // fotografía de perfil (opcional)

  TutorStore(this._tutors, this._subjects, this._auth, [this._universities, this._photos]);

  List<Subject> _catalog = const [];
  List<TutorSummary> _available = const [];
  String? _universityId;
  String? _subjectFilter;
  String? _categoryFilter;
  String _query = '';
  String? _careerFilter;
  List<Career> _careers = const [];
  TutoringModality? _modalityFilter;
  DateTime? _availableAt;
  int _availableMinutes = 60;

  /// Todos los tutores ya resueltos, por id de perfil (aunque no pasen el
  /// filtro actual). Lo usan Mis reservas y el detalle de una reserva.
  final Map<String, TutorSummary> _known = {};
  TutorProfile? _myProfile;
  bool _loading = false;
  String? _error;

  // ---------------- Lectura ----------------

  /// Catálogo completo de materias.
  List<Subject> get subjects => _catalog;

  /// Categorías del catálogo, sin repetir (Matemáticas, Economía…).
  List<String> get categories =>
      _catalog.map((s) => s.categoria).toSet().toList(growable: false);

  /// Tutores visibles con el filtro actual.
  List<TutorSummary> get availableTutors => _available;

  String? get universityId => _universityId;
  String? get subjectFilter => _subjectFilter;
  String? get categoryFilter => _categoryFilter;

  /// Texto de búsqueda actual (nombre del tutor o materia).
  String get query => _query;

  /// Career.id elegido en el filtro de carrera (null = todas).
  String? get careerFilter => _careerFilter;

  /// Modalidad elegida (null = cualquiera).
  TutoringModality? get modalityFilter => _modalityFilter;

  /// Fecha y hora en que el tutor debe estar disponible (null = cualquiera).
  DateTime? get availabilityFilter => _availableAt;

  /// Carreras de la universidad actual que tienen materias propias en el
  /// catálogo (solo esas se pueden usar como filtro).
  List<Career> get careers => _careers
      .where((c) => _catalog.any((s) => s.careerId == c.id))
      .toList(growable: false);

  /// ¿Hay algo que limpiar en la búsqueda?
  bool get hasSearchOrFilters =>
      _query.trim().isNotEmpty ||
      _careerFilter != null ||
      _categoryFilter != null ||
      _subjectFilter != null ||
      _modalityFilter != null ||
      _availableAt != null;

  /// Tutores disponibles que coinciden con el texto y la carrera.
  /// (Universidad y categoría ya vienen filtradas en [availableTutors].)
  List<TutorSummary> get searchResults {
    final q = _normalize(_query.trim());
    return _available.where((t) {
      if (_careerFilter != null && !t.subjects.any((s) => s.careerId == _careerFilter)) {
        return false;
      }
      if (q.isEmpty) return true;
      return _normalize(t.nombre).contains(q) ||
          t.subjects.any((s) => _normalize(s.nombre).contains(q));
    }).toList(growable: false);
  }

  /// Perfil del tutor que inició sesión (null si aún no lo crea).
  TutorProfile? get myProfile => _myProfile;

  bool get isLoading => _loading;
  String? get error => _error;

  // ---------------- Estudiante ----------------

  /// Muestra solo tutores (y materias) de esa universidad.
  /// Normalmente la del usuario actual: SessionStore.user.universityId.
  Future<void> loadForUniversity(String? universityId) {
    if (universityId != _universityId) {
      _universityId = universityId;
      _catalog = const []; // el catálogo cambia con la universidad
      _careers = const [];
      _subjectFilter = null;
      _categoryFilter = null;
      _careerFilter = null;
      _modalityFilter = null;
      _availableAt = null;
      _query = '';
    }
    return loadAvailable();
  }

  /// Carga materias y tutores disponibles con el filtro actual.
  Future<void> loadAvailable() => _run(() async {
        if (_catalog.isEmpty) _catalog = await _subjects.getAll(universityId: _universityId);
        final universities = _universities;
        final universityId = _universityId;
        if (_careers.isEmpty && universities != null && universityId != null) {
          _careers = await universities.getCareers(universityId);
        }
        final profiles = await _queryAvailable();
        _available = await _summaries(profiles);
      });

  /// Filtra por materia (null = todas). Quita el filtro de categoría.
  Future<void> filterBySubject(String? subjectId) {
    _subjectFilter = subjectId;
    _categoryFilter = null;
    return loadAvailable();
  }

  /// Filtra por categoría (null = todas). Quita el filtro de materia.
  Future<void> filterByCategory(String? categoria) {
    _categoryFilter = categoria;
    _subjectFilter = null;
    return loadAvailable();
  }

  /// Filtra por modalidad (null = cualquiera).
  Future<void> filterByModality(TutoringModality? modalidad) {
    _modalityFilter = modalidad;
    return loadAvailable();
  }

  /// Filtra por disponibilidad: tutores que atienden una sesión de
  /// [duracionMinutos] que empieza en [inicio] (null = cualquier horario).
  Future<void> filterByAvailability(DateTime? inicio, {int duracionMinutos = 60}) {
    _availableAt = inicio;
    _availableMinutes = duracionMinutos;
    return loadAvailable();
  }

  /// Busca por nombre del tutor o materia (sin distinguir mayúsculas ni tildes).
  void search(String text) {
    if (text == _query) return;
    _query = text;
    notifyListeners();
  }

  /// Filtra por carrera: tutores que imparten materias de esa carrera (null = todas).
  void filterByCareer(String? careerId) {
    if (careerId == _careerFilter) return;
    _careerFilter = careerId;
    notifyListeners();
  }

  /// Quita texto, carrera, categoría y materia, y recarga la lista completa.
  Future<void> clearSearch() {
    _query = '';
    _careerFilter = null;
    _categoryFilter = null;
    _subjectFilter = null;
    _modalityFilter = null;
    _availableAt = null;
    return loadAvailable();
  }

  /// Tutor ya cargado por id de perfil, sin importar los filtros (o null).
  TutorSummary? cachedTutor(String tutorId) => _known[tutorId];

  /// Carga los tutores indicados (ej. los de las reservas del estudiante)
  /// para mostrarlos por nombre con [cachedTutor]. Los ya cargados no se repiten.
  Future<void> loadTutors(Iterable<String> tutorIds) async {
    final missing = tutorIds.toSet().where((id) => !_known.containsKey(id)).toList();
    if (missing.isEmpty) return;
    final profiles = <TutorProfile>[];
    for (final id in missing) {
      final profile = await _tutors.getById(id);
      if (profile != null) profiles.add(profile);
    }
    await _summaries(profiles); // quedan guardados en _known
    notifyListeners();
  }

  /// Un tutor por su id de perfil (para Perfil del tutor y Reserva).
  Future<TutorSummary?> getTutor(String tutorId) async {
    for (final t in _available) {
      if (t.id == tutorId) return t;
    }
    final profile = await _tutors.getById(tutorId);
    if (profile == null) return null;
    final list = await _summaries([profile]);
    return list.isEmpty ? null : list.first;
  }

  /// Vuelve a leer un tutor (p. ej. después de calificarlo: el promedio y el
  /// total los recalcula el servidor o el repositorio local).
  Future<void> refreshTutor(String tutorId) async {
    try {
      final profile = await _tutors.getById(tutorId);
      if (profile == null) return;
      final list = await _summaries([profile]);
      if (list.isEmpty) return;
      _available = [for (final t in _available) t.id == tutorId ? list.first : t];
      if (_myProfile?.id == tutorId) _myProfile = profile;
      notifyListeners();
    } catch (_) {
      // Sin red: se mantiene lo que ya se mostraba.
    }
  }

  // ---------------- Tutor ----------------

  /// Carga el perfil del tutor que inició sesión.
  Future<void> loadMyProfile(String userId) => _run(() async {
        if (_catalog.isEmpty) _catalog = await _subjects.getAll();
        _myProfile = await _tutors.getByUserId(userId);
      });

  /// Crea o actualiza el perfil del tutor. Devuelve true si se guardó.
  Future<bool> saveProfile(TutorProfile profile) => _run(() async {
        _myProfile = await _tutors.save(profile);
        // La lista de estudiantes puede cambiar (precio, materias, activo).
        final profiles = await _queryAvailable();
        _available = await _summaries(profiles);
      });

  // ---------------- Fotografía de perfil ----------------

  /// Hay selector de fotografías disponible (en pruebas puede no haberlo).
  bool get canPickPhotos => _photos != null;

  /// Abre la galería y guarda una COPIA permanente de la imagen.
  /// Devuelve la ruta de la copia, o null si se canceló o falló
  /// (el motivo queda en [error]). No cambia el perfil: eso lo hace [saveProfile].
  Future<String?> pickProfilePhoto(String ownerId) async {
    final photos = _photos;
    if (photos == null) return null;
    try {
      final temp = await photos.pickFromGallery();
      if (temp == null) return null; // canceló
      return await photos.saveCopy(temp, ownerId: ownerId);
    } catch (_) {
      _error = 'No se pudo cargar la fotografía. Intenta con otra imagen.';
      notifyListeners();
      return null;
    }
  }

  /// Borra un archivo de fotografía que ya no se usa (reemplazada o eliminada).
  Future<void> deletePhotoFile(String path) async {
    try {
      await _photos?.delete(path);
    } catch (_) {
      // Si no se puede borrar, solo queda un archivo huérfano: no afecta al perfil.
    }
  }

  /// Al cerrar sesión, olvida el perfil propio.
  void reset() {
    _myProfile = null;
    _universityId = null;
    _available = const [];
    _catalog = const [];
    _subjectFilter = null;
    _categoryFilter = null;
    _careerFilter = null;
    _modalityFilter = null;
    _availableAt = null;
    _careers = const [];
    _known.clear();
    _query = '';
    _error = null;
    notifyListeners();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  // ---------------- Interno ----------------

  Future<List<TutorProfile>> _queryAvailable() => _tutors.getAvailable(
        universityId: _universityId,
        subjectId: _subjectFilter,
        categoria: _categoryFilter,
        modalidad: _modalityFilter,
        disponibleEn: _availableAt,
        duracionMinutos: _availableMinutes,
      );

  /// Minúsculas y sin tildes: "Estadística" → "estadistica".
  static String _normalize(String text) {
    const from = 'áéíóúüñ';
    const to = 'aeiouun';
    final lower = text.toLowerCase();
    final buffer = StringBuffer();
    for (final ch in lower.split('')) {
      final i = from.indexOf(ch);
      buffer.write(i < 0 ? ch : to[i]);
    }
    return buffer.toString();
  }

  /// Une cada perfil con su cuenta y sus materias.
  Future<List<TutorSummary>> _summaries(List<TutorProfile> profiles) async {
    final result = <TutorSummary>[];
    for (final p in profiles) {
      final user = await _auth.getUserById(p.userId);
      if (user == null) continue; // perfil huérfano: no se muestra
      final summary = TutorSummary(
        profile: p,
        user: user,
        subjects: await _subjects.getByIds(p.materias),
      );
      _known[p.id] = summary;
      result.add(summary);
    }
    return result;
  }

  Future<bool> _run(Future<void> Function() action) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on RepositoryException catch (e) {
      _error = e.message;
      return false;
    } catch (_) {
      _error = 'No se pudieron cargar los tutores. Intenta de nuevo.';
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}

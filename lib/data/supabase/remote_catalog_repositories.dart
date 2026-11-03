import 'dart:async';

import '../../domain/catalog_rules.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import '../local/local_seed.dart';
import 'remote_catalog.dart';

/// Repositorios productivos de catálogo con Supabase (Fase 14.6).
///
/// - Solo lectura: universities, careers y subjects con la publishable key y la
///   sesión del usuario (RLS). Nunca escriben en Supabase.
/// - Los ids siguen siendo los de Flutter (slug); los uuid quedan en
///   [RemoteCatalog] para traducir (decisión 17).
/// - Las reglas de filtro y orden son las mismas que en local ([CatalogRules]).

/// Caché del catálogo remoto para la sesión de la app. La comparten la
/// autenticación y los repositorios de catálogo, así cada universidad se
/// consulta una sola vez.
class RemoteCatalogCache {
  final CatalogRowsSource _catalog;
  final UniversityListSource _universities;
  final Duration _timeout;

  final Map<String, RemoteCatalog> _bySlug = {};
  final Map<String, String> _slugByUuid = {};
  final Set<String> _missing = {};
  List<University>? _active;

  RemoteCatalogCache({
    required CatalogRowsSource catalog,
    required UniversityListSource universities,
    Duration timeout = const Duration(seconds: 15),
  })  : _catalog = catalog,
        _universities = universities,
        _timeout = timeout;

  /// Catálogos ya cargados.
  Iterable<RemoteCatalog> get loaded => _bySlug.values;

  /// Universidades activas, ordenadas por nombre.
  Future<List<University>> activeUniversities() async {
    final cached = _active;
    if (cached != null) return cached;
    final rows = await _guard(_universities.fetchActiveUniversities);
    final universities = _map(() => [for (final row in rows) CatalogMapper.university(row)]);
    return _active = CatalogRules.active(universities);
  }

  /// Catálogo de la universidad con ese slug, o null si no existe o no es visible.
  Future<RemoteCatalog?> bySlug(String slug) async {
    final cached = _bySlug[slug];
    if (cached != null) return cached;
    if (_missing.contains(slug)) return null;
    final rows = await _guard(() => _catalog.fetch(slug));
    if (rows == null) {
      _missing.add(slug);
      return null;
    }
    final catalog = _map(() => CatalogMapper.map(rows));
    _bySlug[slug] = catalog;
    _slugByUuid[catalog.universityUuid] = slug;
    return catalog;
  }

  /// Catálogo a partir del uuid de la universidad (perfiles guardan uuid).
  Future<RemoteCatalog?> byUuid(String universityUuid) async {
    final slug = _slugByUuid[universityUuid] ??
        await _guard(() => _universities.universitySlugById(universityUuid));
    return slug == null ? null : bySlug(slug);
  }

  /// Carga los catálogos de todas las universidades activas.
  Future<List<RemoteCatalog>> allActive() async {
    final result = <RemoteCatalog>[];
    for (final university in await activeUniversities()) {
      final catalog = await bySlug(university.id);
      if (catalog != null) result.add(catalog);
    }
    return result;
  }

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call().timeout(_timeout);
    } on RepositoryException {
      rethrow;
    } on TimeoutException {
      throw const RepositoryException(catalogTimeoutMessage);
    } catch (_) {
      throw const RepositoryException(catalogConnectionMessage);
    }
  }

  static T _map<T>(T Function() mapper) {
    try {
      return mapper();
    } on CatalogMappingException {
      throw const RepositoryException(catalogFormatMessage);
    }
  }
}

const String catalogConnectionMessage =
    'No se pudo cargar el catálogo. Revisa tu conexión a Internet.';
const String catalogTimeoutMessage =
    'El servidor tardó demasiado en responder. Intenta de nuevo.';
const String catalogFormatMessage = 'El catálogo recibido no tiene el formato esperado.';

/// UniversityRepository remoto. La universidad elegida en la pantalla inicial
/// es contexto del dispositivo: se sigue guardando en local ([deviceSelection]).
class RemoteUniversityRepository implements UniversityRepository {
  final RemoteCatalogCache _cache;
  final UniversityRepository _deviceSelection;

  RemoteUniversityRepository(this._cache, {required UniversityRepository deviceSelection})
      : _deviceSelection = deviceSelection;

  @override
  Future<List<University>> getActive() => _cache.activeUniversities();

  @override
  Future<University?> getById(String id) async {
    for (final u in await _cache.activeUniversities()) {
      if (u.id == id) return u;
    }
    // La propia del usuario puede estar inactiva y seguir siendo visible.
    return (await _cache.bySlug(id))?.university;
  }

  @override
  Future<List<Career>> getCareers(String universityId) async {
    final catalog = await _cache.bySlug(universityId);
    return catalog == null ? const [] : CatalogRules.careersOf(catalog.careers, universityId);
  }

  @override
  Future<Career?> getCareerById(String id) async {
    final found = _findCareer(_cache.loaded, id);
    if (found != null) return found;
    return _findCareer(await _cache.allActive(), id);
  }

  @override
  Future<String?> getSelectedUniversityId() => _deviceSelection.getSelectedUniversityId();

  @override
  Future<void> saveSelectedUniversityId(String universityId) =>
      _deviceSelection.saveSelectedUniversityId(universityId);

  static Career? _findCareer(Iterable<RemoteCatalog> catalogs, String id) {
    for (final catalog in catalogs) {
      for (final c in catalog.careers) {
        if (c.id == id) return c;
      }
    }
    return null;
  }
}

/// SubjectRepository remoto.
class RemoteSubjectRepository implements SubjectRepository {
  final RemoteCatalogCache _cache;

  RemoteSubjectRepository(this._cache);

  @override
  Future<List<Subject>> getAll({String? universityId, String? careerId}) async {
    final List<RemoteCatalog> catalogs;
    if (universityId == null) {
      catalogs = await _cache.allActive();
    } else {
      final catalog = await _cache.bySlug(universityId);
      catalogs = catalog == null ? const [] : [catalog];
    }
    final subjects = [for (final c in catalogs) ...orderLikeLocal(c.subjects)];
    return CatalogRules.filterSubjects(subjects, universityId: universityId, careerId: careerId);
  }

  /// Respeta el orden de [ids] e ignora ids desconocidos.
  @override
  Future<List<Subject>> getByIds(List<String> ids) async =>
      CatalogRules.subjectsByIds(await getAll(), ids);

  /// El repositorio local devuelve las materias en el orden del catálogo
  /// guardado (LocalSeed), y las pantallas derivan de ese orden, por ejemplo,
  /// el de los chips de categoría. La tabla `subjects` no tiene una columna de
  /// orden, así que las materias conocidas se ordenan como en LocalSeed y las
  /// nuevas van al final por nombre. Transitorio hasta que el esquema tenga orden.
  static List<Subject> orderLikeLocal(List<Subject> subjects) {
    final rank = {for (final (i, s) in LocalSeed.subjects.indexed) s.id: i};
    final known = subjects.where((s) => rank.containsKey(s.id)).toList()
      ..sort((a, b) => rank[a.id]!.compareTo(rank[b.id]!));
    final others = subjects.where((s) => !rank.containsKey(s.id)).toList()
      ..sort((a, b) => a.nombre.compareTo(b.nombre));
    return [...known, ...others];
  }
}

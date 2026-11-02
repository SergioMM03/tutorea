import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'local_seed.dart';

/// "Base de datos" local del MVP sobre shared_preferences.
/// Cada colección se guarda como una lista JSON bajo su propia clave.
/// Solo la usan los repositorios locales; el resto de la app no la conoce.
class LocalDatabase {
  static const String universities = 'tutorea.universities';
  static const String careers = 'tutorea.careers';
  static const String users = 'tutorea.users';
  static const String subjects = 'tutorea.subjects';
  static const String tutorProfiles = 'tutorea.tutorProfiles';
  static const String bookings = 'tutorea.bookings';
  static const String session = 'tutorea.session';
  static const String seedVersion = 'tutorea.seedVersion';

  /// Universidad elegida en la pantalla inicial (contexto del dispositivo).
  static const String selectedUniversity = 'tutorea.selectedUniversity';

  final SharedPreferences _prefs;

  LocalDatabase(this._prefs);

  /// Abre la base y carga los datos iniciales la primera vez.
  static Future<LocalDatabase> open() async {
    final db = LocalDatabase(await SharedPreferences.getInstance());
    await LocalSeed.ensureSeeded(db);
    return db;
  }

  List<Map<String, dynamic>> readList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> writeList(String key, List<Map<String, dynamic>> items) =>
      _prefs.setString(key, jsonEncode(items));

  Map<String, dynamic>? readMap(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> writeMap(String key, Map<String, dynamic> value) =>
      _prefs.setString(key, jsonEncode(value));

  int? readInt(String key) => _prefs.getInt(key);

  String? readString(String key) => _prefs.getString(key);

  Future<void> writeString(String key, String value) => _prefs.setString(key, value);

  Future<void> writeInt(String key, int value) => _prefs.setInt(key, value);

  Future<void> remove(String key) => _prefs.remove(key);

  /// Borra todo lo de Tutorea (útil para reiniciar la demo).
  Future<void> clear() async {
    for (final key in [
      universities,
      careers,
      users,
      subjects,
      tutorProfiles,
      bookings,
      session,
      seedVersion,
      selectedUniversity,
    ]) {
      await _prefs.remove(key);
    }
  }
}

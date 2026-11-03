import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart'
    show FileOptions, PostgrestException, StorageException, SupabaseClient;

import '../../domain/models/models.dart';
import '../../domain/photo_rules.dart';
import '../../domain/repositories/repositories.dart';
import 'remote_catalog_repositories.dart';

const String photoFailedMessage = 'No se pudo guardar la fotografía. Intenta de nuevo.';
const String photoNoProfileMessage = 'Primero guarda tu perfil de tutor.';
const String photoInvalidMessage = 'Fotografía no válida. Elige otra imagen.';
const String photoConnectionMessage = 'No se pudo conectar con el servidor. Revisa tu conexión a Internet.';

/// Operaciones de Storage y de la base que usa [RemoteTutorPhotoStorage].
abstract class PhotoStorageSource {
  Future<void> upload(String path, Uint8List bytes, String contentType);
  Future<void> remove(List<String> paths);

  /// set_tutor_photo (migración 24): devuelve la ruta anterior.
  Future<String?> setPhoto(String? path);
  Future<String> signedUrl(String path, Duration expiresIn);
}

/// Fotografías de tutores en el bucket privado `tutor-photos`.
///
/// Subir: valida tipo y tamaño (el servidor lo vuelve a validar), sube a
/// `<universidad>/<perfil>/<marca de tiempo>.<ext>`, la fija con
/// set_tutor_photo y borra el archivo anterior. Si fijarla falla, borra lo que
/// subió: no quedan archivos huérfanos.
class RemoteTutorPhotoStorage implements TutorPhotoStorage {
  final PhotoStorageSource _source;
  final RemoteCatalogCache _catalog;
  final Future<Uint8List> Function(String path) _read;
  final DateTime Function() _now;
  final Duration _timeout;

  /// Duración de cada URL firmada; se renueva antes de que venza.
  static const Duration urlLifetime = Duration(hours: 1);
  final Map<String, (String, DateTime)> _urls = {};

  RemoteTutorPhotoStorage(
    this._source,
    this._catalog, {
    Future<Uint8List> Function(String path)? readFile,
    DateTime Function()? now,
    Duration timeout = const Duration(seconds: 30),
  })  : _read = readFile ?? ((path) => File(path).readAsBytes()),
        _now = now ?? DateTime.now,
        _timeout = timeout;

  @override
  Future<String?> validate(String localPath) async {
    if (PhotoRules.mimeOf(localPath) == null) return PhotoRules.invalidTypeMessage;
    try {
      return PhotoRules.problem(localPath, (await _read(localPath)).length);
    } catch (_) {
      return photoInvalidMessage;
    }
  }

  @override
  Future<String> upload(TutorProfile profile, String localPath) async {
    final bytes = await _guard(() => _read(localPath));
    final problem = PhotoRules.problem(localPath, bytes.length);
    if (problem != null) throw RepositoryException(problem);
    final catalog = await _guard(() => _catalog.bySlug(profile.universityId));
    if (catalog == null) throw const RepositoryException(photoFailedMessage);

    final ext = PhotoRules.extensionOf(localPath);
    final path = '${catalog.universityUuid}/${profile.id}/${_now().millisecondsSinceEpoch}.$ext';
    await _guard(() => _source.upload(path, bytes, PhotoRules.mimeOf(localPath)!));
    final String? previous;
    try {
      previous = await _guard(() => _source.setPhoto(path));
    } catch (_) {
      await _quietRemove([path]);
      rethrow;
    }
    if (previous != null && previous != path) await _quietRemove([previous]);
    return path;
  }

  @override
  Future<void> remove(TutorProfile profile) async {
    final previous = await _guard(() => _source.setPhoto(null));
    if (previous != null) await _quietRemove([previous]);
  }

  @override
  String? cachedUrl(String path) {
    final entry = _urls[path];
    if (entry == null || !_now().isBefore(entry.$2)) return null;
    return entry.$1;
  }

  @override
  Future<String?> signedUrl(String path) async {
    final cached = cachedUrl(path);
    if (cached != null) return cached;
    try {
      final url = await _source.signedUrl(path, urlLifetime).timeout(_timeout);
      // Se considera vencida 5 minutos antes para no mostrar una URL caducada.
      _urls[path] = (url, _now().add(urlLifetime - const Duration(minutes: 5)));
      return url;
    } catch (_) {
      return null; // sin URL: el avatar muestra las iniciales
    }
  }

  Future<void> _quietRemove(List<String> paths) async {
    try {
      await _source.remove(paths).timeout(_timeout);
    } catch (_) {
      // No se pudo borrar: el archivo queda en la carpeta del tutor (privada).
    }
  }

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call().timeout(_timeout);
    } on RepositoryException {
      rethrow;
    } on TimeoutException {
      throw const RepositoryException(photoConnectionMessage);
    } on PostgrestException catch (e) {
      throw RepositoryException(switch (e.code) {
        'TU050' => photoNoProfileMessage,
        'TU051' => photoInvalidMessage,
        _ => photoFailedMessage,
      });
    } on StorageException catch (e) {
      throw RepositoryException(switch (e.statusCode) {
        '413' => PhotoRules.tooLargeMessage,
        '415' => PhotoRules.invalidTypeMessage,
        _ => photoFailedMessage,
      });
    } on FileSystemException {
      throw const RepositoryException(photoInvalidMessage);
    } catch (_) {
      throw const RepositoryException(photoConnectionMessage);
    }
  }
}

/// Supabase real: bucket privado `tutor-photos` y set_tutor_photo.
class SupabasePhotoStorageSource implements PhotoStorageSource {
  static const String bucket = 'tutor-photos';
  final SupabaseClient _client;
  SupabasePhotoStorageSource(this._client);

  @override
  Future<void> upload(String path, Uint8List bytes, String contentType) async {
    await _client.storage
        .from(bucket)
        .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: contentType, upsert: false));
  }

  @override
  Future<void> remove(List<String> paths) async {
    await _client.storage.from(bucket).remove(paths);
  }

  @override
  Future<String?> setPhoto(String? path) async {
    final previous = await _client.rpc<dynamic>('set_tutor_photo', params: {'p_path': path});
    return previous is String ? previous : null;
  }

  @override
  Future<String> signedUrl(String path, Duration expiresIn) =>
      _client.storage.from(bucket).createSignedUrl(path, expiresIn.inSeconds);
}

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../domain/photo_rules.dart';
import '../domain/repositories/tutor_photo_storage.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Avatar de una persona (tutor o estudiante), igual en toda la app:
/// - con [photoPath] (fotografía elegida por el propio tutor) muestra la foto:
///   ruta de Supabase Storage (URL firmada, Fase 14.10) o archivo local;
/// - sin foto, o si el archivo ya no existe o no se puede abrir, muestra las
///   iniciales en azul principal sobre un círculo azul claro.
/// [rounded] = true → cuadrado redondeado en lugar de círculo.
class TutorAvatar extends StatelessWidget {
  final String name;
  final String? photoPath;
  final double size;
  final bool rounded;

  const TutorAvatar({
    super.key,
    required this.name,
    this.photoPath,
    this.size = 72,
    this.rounded = false,
  });

  /// "Valeria Díaz" → "VD" · "Sofía" → "SO" · "" → "?".
  /// Con más de dos palabras usa las dos primeras ("Ana María López" → "AM").
  static String initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final word = parts.first;
      return (word.length >= 2 ? word.substring(0, 2) : word).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  /// Archivo de la fotografía si existe en el dispositivo; si no, null.
  static File? existingPhoto(String? path) {
    if (kIsWeb || path == null || path.trim().isEmpty) return null;
    final file = File(path);
    return file.existsSync() ? file : null;
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = rounded
        ? BorderRadius.circular(AppRadius.card + 8)
        : BorderRadius.circular(size / 2);
    final path = photoPath;
    final photo = PhotoRules.isStoragePath(path) ? null : existingPhoto(path);
    // Provider opcional: sin él (pruebas, modo local) se muestran iniciales.
    final urls = PhotoRules.isStoragePath(path) ? Provider.of<PhotoUrlResolver?>(context, listen: false) : null;

    final initials = Text(
      initialsOf(name),
      key: const Key('avatar-initials'),
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: AppColors.primary,
            fontSize: size * 0.3,
          ),
    );

    return ClipRRect(
      borderRadius: borderRadius,
      child: Container(
        width: size,
        height: size,
        color: AppColors.primaryLight,
        alignment: Alignment.center,
        child: urls != null
            ? _RemotePhoto(path: path!, urls: urls, size: size, placeholder: initials)
            : photo == null
            ? initials
            : Image.file(
                photo,
                key: const Key('avatar-photo'),
                width: size,
                height: size,
                fit: BoxFit.cover,
                // Archivo dañado o ilegible: vuelve a las iniciales.
                errorBuilder: (_, __, ___) => initials,
              ),
      ),
    );
  }
}

/// Foto en Storage: pide la URL firmada y la muestra; mientras tanto, o si
/// falla, las iniciales.
class _RemotePhoto extends StatefulWidget {
  final String path;
  final PhotoUrlResolver urls;
  final double size;
  final Widget placeholder;
  const _RemotePhoto({required this.path, required this.urls, required this.size, required this.placeholder});

  @override
  State<_RemotePhoto> createState() => _RemotePhotoState();
}

class _RemotePhotoState extends State<_RemotePhoto> {
  late Future<String?> _url;

  @override
  void initState() {
    super.initState();
    _url = _resolve();
  }

  @override
  void didUpdateWidget(_RemotePhoto old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _url = _resolve();
  }

  Future<String?> _resolve() {
    final cached = widget.urls.cachedUrl(widget.path);
    return cached != null ? Future.value(cached) : widget.urls.signedUrl(widget.path);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _url,
      initialData: widget.urls.cachedUrl(widget.path),
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null) return widget.placeholder;
        return Image.network(
          url,
          key: const Key('avatar-photo'),
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => widget.placeholder,
        );
      },
    );
  }
}

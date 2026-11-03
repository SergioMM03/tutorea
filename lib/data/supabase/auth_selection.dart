import 'package:flutter/foundation.dart';

import '../../config/auth_mode.dart';
import '../../domain/repositories/repositories.dart';

/// Elige la autenticación al arrancar (Fase 14.5).
///
/// Supabase Auth solo se usa si se pidió (`TUTOREA_AUTH=supabase`) y Supabase
/// quedó inicializado. En cualquier otro caso, o si no se puede crear el
/// repositorio remoto, se usa [local]: la app conserva el modo local.
AuthRepository selectAuthRepository({
  required AuthMode mode,
  required bool supabaseReady,
  required AuthRepository local,
  required AuthRepository Function() remote,
  void Function(String message)? log,
}) {
  final emit = log ?? debugPrint;
  if (mode != AuthMode.supabase) {
    emit('[Auth] Modo local.');
    return local;
  }
  if (!supabaseReady) {
    emit('[Auth] Se pidió Supabase Auth, pero Supabase no está inicializado. Modo local.');
    return local;
  }
  try {
    final repository = remote();
    emit('[Auth] Supabase Auth activo. Tutores, reservas y catálogo siguen en modo local.');
    return repository;
  } catch (_) {
    emit('[Auth] No se pudo crear Supabase Auth. Modo local.');
    return local;
  }
}

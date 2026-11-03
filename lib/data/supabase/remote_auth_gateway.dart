import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, GoTrueClient, Supabase, SupabaseClient;

import 'supabase_bootstrap.dart';

/// Contratos pequeños entre SupabaseAuthRepository y Supabase, para poder
/// probar el repositorio sin red. Las implementaciones reales están abajo.

/// Usuario de Supabase Auth (solo id y correo; nunca tokens).
class RemoteAuthUser {
  final String id;
  final String email;
  const RemoteAuthUser({required this.id, required this.email});
}

class RemoteSignUpResult {
  final RemoteAuthUser user;

  /// false si el proyecto exige confirmar el correo (no hay sesión todavía).
  final bool hasSession;
  const RemoteSignUpResult({required this.user, required this.hasSession});
}

enum RemoteAuthEvent { signedIn, signedOut, other }

/// Supabase Auth (GoTrue).
abstract class RemoteAuthGateway {
  /// Usuario de la sesión persistida, o null.
  RemoteAuthUser? get currentUser;

  /// Renueva el token si la sesión guardada ya venció.
  Future<void> refreshIfExpired();

  Future<RemoteSignUpResult> signUp({
    required String email,
    required String password,
    required Map<String, Object> data,
  });

  Future<RemoteAuthUser> signIn({required String email, required String password});

  Future<void> signOut();

  Stream<RemoteAuthEvent> get events;
}

/// Lecturas que la autenticación necesita (todas con la sesión del usuario y RLS).
abstract class RemoteProfileSource {
  /// Fila propia de `profiles` (RLS: solo la propia).
  Future<Map<String, dynamic>?> ownProfile(String userId);

  /// Fila de `public_profiles` (misma universidad; sin correo).
  Future<Map<String, dynamic>?> publicProfile(String userId);

  /// slug de una universidad a partir de su uuid.
  Future<String?> universitySlugById(String universityUuid);
}

// ---------------------------------------------------------------------------
// Implementaciones con supabase_flutter 2.18.3
// ---------------------------------------------------------------------------

class SupabaseAuthGateway implements RemoteAuthGateway {
  final GoTrueClient _auth;
  SupabaseAuthGateway(this._auth);

  @override
  RemoteAuthUser? get currentUser {
    final user = _auth.currentUser;
    return user == null ? null : RemoteAuthUser(id: user.id, email: user.email ?? '');
  }

  @override
  Future<void> refreshIfExpired() async {
    final session = _auth.currentSession;
    if (session != null && session.isExpired) await _auth.refreshSession();
  }

  @override
  Future<RemoteSignUpResult> signUp({
    required String email,
    required String password,
    required Map<String, Object> data,
  }) async {
    final response = await _auth.signUp(email: email, password: password, data: data);
    final user = response.user;
    if (user == null) throw StateError('Supabase no devolvió el usuario creado.');
    return RemoteSignUpResult(
      user: RemoteAuthUser(id: user.id, email: user.email ?? email),
      hasSession: response.session != null,
    );
  }

  @override
  Future<RemoteAuthUser> signIn({required String email, required String password}) async {
    final response = await _auth.signInWithPassword(email: email, password: password);
    final user = response.user;
    if (user == null) throw StateError('Supabase no devolvió el usuario.');
    return RemoteAuthUser(id: user.id, email: user.email ?? email);
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Stream<RemoteAuthEvent> get events => _auth.onAuthStateChange.map((state) => switch (state.event) {
        AuthChangeEvent.signedIn => RemoteAuthEvent.signedIn,
        AuthChangeEvent.signedOut => RemoteAuthEvent.signedOut,
        _ => RemoteAuthEvent.other,
      });
}

class SupabaseProfileSource implements RemoteProfileSource {
  final SupabaseClient _client;
  SupabaseProfileSource(this._client);

  @override
  Future<Map<String, dynamic>?> ownProfile(String userId) => _client
      .from('profiles')
      .select('id, university_id, role, full_name, career_id, career_name, academic_year, created_at')
      .eq('id', userId)
      .maybeSingle();

  @override
  Future<Map<String, dynamic>?> publicProfile(String userId) => _client
      .from('public_profiles')
      .select('id, university_id, full_name, career_name, academic_year, role')
      .eq('id', userId)
      .maybeSingle();

  @override
  Future<String?> universitySlugById(String universityUuid) async {
    final row = await _client
        .from('universities')
        .select('slug')
        .eq('id', universityUuid)
        .maybeSingle();
    final slug = row?['slug'];
    return slug is String ? slug : null;
  }
}

/// Cliente global, solo si SupabaseBootstrap confirmó la inicialización.
SupabaseClient initializedSupabaseClient() {
  if (!SupabaseBootstrap.isReady) {
    throw StateError('Supabase no está inicializado.');
  }
  return Supabase.instance.client;
}

import '../models/models.dart';

/// Capacidad opcional de un [AuthRepository]: avisa cuando la sesión termina
/// sin que la app lo haya pedido (por ejemplo, Supabase no pudo renovar el
/// token o la sesión se cerró en el servidor).
///
/// LocalAuthRepository no la implementa: su sesión solo cambia por acciones
/// de la propia app. SessionStore se suscribe solo si el repositorio la tiene.
abstract class AuthSessionChanges {
  /// Emite `Session.empty()` cada vez que la sesión remota termina.
  Stream<Session> get sessionChanges;
}

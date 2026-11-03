import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, AuthRetryableFetchException, AuthWeakPasswordException, PostgrestException;

import '../../domain/repositories/repositories.dart';

/// Traduce errores de Supabase a RepositoryException con mensajes para la UI.
///
/// Los mensajes son fijos: nunca copian el texto del servidor, que podría
/// incluir datos enviados (correo, contraseña) o detalles internos.
RepositoryException describeSupabaseAuthError(Object error) {
  if (error is RepositoryException) return error;
  if (error is TimeoutException) return const RepositoryException(timeoutMessage);
  if (error is AuthRetryableFetchException) return const RepositoryException(connectionMessage);
  if (error is AuthWeakPasswordException) return const RepositoryException(weakPasswordMessage);

  if (error is AuthException) {
    final code = error.code ?? '';
    final message = error.message.toLowerCase();
    if (code == 'invalid_credentials' || message.contains('invalid login credentials')) {
      return const RepositoryException(invalidCredentialsMessage);
    }
    if (code == 'user_already_exists' ||
        code == 'email_exists' ||
        message.contains('already registered')) {
      return const RepositoryException(emailInUseMessage);
    }
    if (code == 'weak_password') return const RepositoryException(weakPasswordMessage);
    if (code == 'email_address_invalid' || code == 'validation_failed') {
      return const RepositoryException(invalidEmailMessage);
    }
    if (code == 'over_request_rate_limit' ||
        code == 'over_email_send_rate_limit' ||
        error.statusCode == '429') {
      return const RepositoryException(rateLimitMessage);
    }
    if (code == 'email_not_confirmed') return const RepositoryException(emailNotConfirmedMessage);
    if (code == 'signup_disabled') return const RepositoryException(signupDisabledMessage);
    // handle_new_user rechazó los datos (universidad, carrera, año o nombre).
    if (code == 'unexpected_failure' || message.contains('database error saving new user')) {
      return const RepositoryException(registrationDataMessage);
    }
    return const RepositoryException(genericAuthMessage);
  }

  if (error is PostgrestException) return const RepositoryException(profileReadMessage);
  // ClientException, SocketException y otros fallos de red.
  return const RepositoryException(connectionMessage);
}

const String invalidCredentialsMessage = 'Correo o contraseña incorrectos.';
const String emailInUseMessage = 'Ya existe una cuenta con ese correo.';
const String weakPasswordMessage =
    'La contraseña es demasiado débil. Usa al menos 6 caracteres.';
const String invalidEmailMessage = 'Escribe un correo válido.';
const String rateLimitMessage = 'Demasiados intentos. Espera unos minutos e intenta de nuevo.';
const String emailNotConfirmedMessage = 'Confirma tu correo antes de iniciar sesión.';
const String signupDisabledMessage = 'El registro no está disponible en este momento.';
const String registrationDataMessage =
    'No se pudo crear la cuenta. Revisa tu universidad, carrera y año académico.';
const String genericAuthMessage = 'No se pudo completar la autenticación. Intenta de nuevo.';
const String profileReadMessage = 'No se pudo leer tu perfil. Intenta de nuevo.';
const String connectionMessage =
    'No se pudo conectar con el servidor. Revisa tu conexión a Internet.';
const String timeoutMessage = 'El servidor tardó demasiado en responder. Intenta de nuevo.';

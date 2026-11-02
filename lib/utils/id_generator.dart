import 'dart:math';

/// Genera ids únicos sin paquetes externos (ej. "bk-lq3x9a-4821").
/// Con Firebase, los ids los asigna Firestore y esto deja de usarse.
class IdGenerator {
  IdGenerator._();

  static final Random _random = Random();

  static String newId(String prefix) {
    final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final rand = _random.nextInt(1 << 20).toRadixString(36).padLeft(4, '0');
    return '$prefix-$time-$rand';
  }
}

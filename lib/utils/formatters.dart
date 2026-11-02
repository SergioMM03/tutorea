/// Formatos de texto compartidos por varios componentes.
class Formatters {
  Formatters._();

  /// 10 → "$10" · 12.5 → "$12.50"
  static String price(double value) {
    final isWhole = value == value.roundToDouble();
    return '\$${isWhole ? value.toStringAsFixed(0) : value.toStringAsFixed(2)}';
  }

  /// 10 → "$10/hora"
  static String pricePerHour(double value) => '${price(value)}/hora';

  static const _weekdaysShort = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
  static const _weekdaysLong = [
    'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'
  ];
  static const _monthsShort = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'
  ];
  static const _monthsLong = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto',
    'septiembre', 'octubre', 'noviembre', 'diciembre'
  ];

  /// Fecha → "Mar"
  static String weekdayShort(DateTime d) => _weekdaysShort[d.weekday - 1];

  /// 1 (lunes) … 7 (domingo) → "Lun" … "Dom"
  static String weekdayShortOf(int diaSemana) => _weekdaysShort[diaSemana - 1];

  /// Fecha → "Oct"
  static String monthShort(DateTime d) => _monthsShort[d.month - 1];

  /// Fecha → "Martes 14 de octubre"
  static String dateLong(DateTime d) =>
      '${_weekdaysLong[d.weekday - 1]} ${d.day} de ${_monthsLong[d.month - 1]}';

  /// Minutos desde medianoche → "8:00 AM" · 840 → "2:00 PM"
  static String time(int minutes) {
    final h24 = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    final period = h24 < 12 ? 'AM' : 'PM';
    return '$h12:${m.toString().padLeft(2, '0')} $period';
  }

  /// 1 → "1 hora" · 1.5 → "1.5 horas"
  static String duration(double hours) {
    final text = hours == hours.roundToDouble()
        ? hours.toStringAsFixed(0)
        : hours.toString();
    return hours == 1 ? '1 hora' : '$text horas';
  }

  /// Minutos → "1 hora" · 90 → "1.5 horas"
  static String durationMinutes(int minutes) => duration(minutes / 60);

  /// "Escuela Superior de Economía y Negocios (ESEN)" → "ESEN".
  /// Sin siglas entre paréntesis devuelve el nombre completo.
  static String universityShortName(String nombre) {
    final match = RegExp(r'\(([^)]+)\)\s*$').firstMatch(nombre);
    return match?.group(1)?.trim() ?? nombre;
  }

  /// ["A", "B", "C"] → "A, B y C"
  static String names(List<String> names) {
    if (names.isEmpty) return '';
    if (names.length == 1) return names.first;
    return '${names.sublist(0, names.length - 1).join(', ')} y ${names.last}';
  }
}

/// Bloque de disponibilidad semanal de un tutor.
/// Ej.: lunes de 8:00 a 12:00 → diaSemana 1, horaInicio 480, horaFin 720.
class AvailabilitySlot {
  /// 1 = lunes … 7 = domingo (igual que DateTime.weekday).
  final int diaSemana;

  /// Minutos desde medianoche (480 = 8:00 AM).
  final int horaInicio;

  /// Minutos desde medianoche (720 = 12:00 PM). Debe ser mayor que [horaInicio].
  final int horaFin;

  const AvailabilitySlot({
    required this.diaSemana,
    required this.horaInicio,
    required this.horaFin,
  }) : assert(diaSemana >= 1 && diaSemana <= 7),
       assert(horaInicio >= 0 && horaFin <= 24 * 60),
       assert(horaInicio < horaFin);

  /// ¿Una sesión que empieza en [inicio] y dura [duracionMinutos] cabe en este bloque?
  bool cubre(DateTime inicio, int duracionMinutos) {
    if (inicio.weekday != diaSemana) return false;
    final desde = inicio.hour * 60 + inicio.minute;
    return desde >= horaInicio && desde + duracionMinutos <= horaFin;
  }

  factory AvailabilitySlot.fromJson(Map<String, dynamic> json) => AvailabilitySlot(
        diaSemana: (json['diaSemana'] as num).toInt(),
        horaInicio: (json['horaInicio'] as num).toInt(),
        horaFin: (json['horaFin'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'diaSemana': diaSemana,
        'horaInicio': horaInicio,
        'horaFin': horaFin,
      };

  @override
  bool operator ==(Object other) =>
      other is AvailabilitySlot &&
      other.diaSemana == diaSemana &&
      other.horaInicio == horaInicio &&
      other.horaFin == horaFin;

  @override
  int get hashCode => Object.hash(diaSemana, horaInicio, horaFin);
}

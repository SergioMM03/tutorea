import 'models/models.dart';
import 'repositories/repositories.dart';

/// Reglas de tutores que comparten el repositorio local y el remoto (Fase 14.7).
class TutorRules {
  TutorRules._();

  /// Tutores visibles para estudiantes: activos y con perfil completo, con los
  /// filtros opcionales; ordenados por calificación (mayor primero). Un tutor
  /// sin reseñas cuenta como 0; los empates conservan el orden recibido.
  /// [categorySubjectIds]: ids de las materias de la categoría elegida.
  static List<TutorProfile> visible(
    Iterable<TutorProfile> profiles, {
    String? universityId,
    String? subjectId,
    Set<String>? categorySubjectIds,
    TutoringModality? modalidad,
    DateTime? disponibleEn,
    int duracionMinutos = 60,
  }) {
    final visibles = profiles.where((p) {
        if (!p.activo || !p.completo) return false;
        if (universityId != null && p.universityId != universityId) return false;
        if (subjectId != null && !p.ensenaMateria(subjectId)) return false;
        if (categorySubjectIds != null && !p.materias.any(categorySubjectIds.contains)) return false;
        if (modalidad != null && !p.ofrece(modalidad)) return false;
        if (disponibleEn != null && !p.disponibleEn(disponibleEn, duracionMinutos)) return false;
        return true;
      }).toList();
    final order = {for (final (i, p) in visibles.indexed) p.id: i};
    return visibles
      ..sort((a, b) {
        final byRating = (b.calificacion ?? 0).compareTo(a.calificacion ?? 0);
        return byRating != 0 ? byRating : order[a.id]!.compareTo(order[b.id]!);
      });
  }

  /// Valida lo que la base también exige antes de guardar un perfil.
  /// Lanza [RepositoryException] con un mensaje para la UI.
  static void validateForSave(TutorProfile profile) {
    if (profile.precioHora < 0) {
      throw const RepositoryException('El precio no puede ser negativo.');
    }
    if (!profile.ofrecePresencial && !profile.ofreceVirtual) {
      throw const RepositoryException('Elige al menos una modalidad: presencial o virtual.');
    }
    if (profile.descripcion.length > 2000) {
      throw const RepositoryException('La descripción es demasiado larga (máximo 2000 caracteres).');
    }
    final problem = slotsProblem(profile.disponibilidad);
    if (problem != null) throw RepositoryException(problem);
  }

  /// Primer problema de los horarios (día, horas o cruces), o null.
  static String? slotsProblem(List<AvailabilitySlot> slots) {
    for (final s in slots) {
      if (s.diaSemana < 1 || s.diaSemana > 7) return 'Hay un día de la semana no válido.';
      if (s.horaInicio < 0 || s.horaFin > 24 * 60 || s.horaInicio >= s.horaFin) {
        return 'La hora de inicio debe ser antes de la hora de fin.';
      }
    }
    for (var i = 0; i < slots.length; i++) {
      for (var j = i + 1; j < slots.length; j++) {
        final a = slots[i];
        final b = slots[j];
        if (a.diaSemana == b.diaSemana && a.horaInicio < b.horaFin && b.horaInicio < a.horaFin) {
          return 'Hay horarios que se cruzan el mismo día.';
        }
      }
    }
    return null;
  }
}

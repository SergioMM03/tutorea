import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/models/models.dart';
import '../state/session_store.dart';
import '../state/tutor_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'booking_status_badge.dart';
import 'tutor_avatar.dart';

/// Datos de una solicitud listos para mostrar al tutor: los ids se
/// resuelven con los stores (estudiante → SessionStore, materia → TutorStore).
class TutorRequestView {
  final Booking booking;
  final String studentName;
  final String university;
  final String career;
  final String subject;

  const TutorRequestView({
    required this.booking,
    required this.studentName,
    required this.university,
    required this.career,
    required this.subject,
  });

  factory TutorRequestView.of(BuildContext context, Booking booking) {
    final session = context.watch<SessionStore>();
    final tutors = context.watch<TutorStore>();
    final student = session.userById(booking.studentId);
    final subject = tutors.subjects.where((s) => s.id == booking.subjectId).firstOrNull;
    return TutorRequestView(
      booking: booking,
      studentName: student?.nombre ?? 'Estudiante',
      university: student == null ? '' : session.universityName(student.universityId),
      career: student?.carrera ?? '',
      subject: subject?.nombre ?? 'Materia',
    );
  }

  String get tema => (booking.tema?.trim().isNotEmpty ?? false) ? booking.tema! : 'Sin tema específico';
  String get fecha => Formatters.dateLong(booking.fechaHora);
  String get hora {
    final s = booking.fechaHora;
    final e = booking.fin;
    return '${Formatters.time(s.hour * 60 + s.minute)} – '
        '${Formatters.time(e.hour * 60 + e.minute)}';
  }

  String get duracion => Formatters.durationMinutes(booking.duracion);
  String get precio => Formatters.price(booking.precio);
}

/// Tarjeta de una solicitud recibida (Dashboard y Solicitudes del tutor).
class TutorRequestCard extends StatelessWidget {
  final Booking booking;
  final VoidCallback? onTap;

  const TutorRequestCard({super.key, required this.booking, this.onTap});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final view = TutorRequestView.of(context, booking);
    final academic = [view.university, view.career].where((t) => t.isNotEmpty).join(' · ');
    final radius = BorderRadius.circular(AppRadius.card);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: radius,
        boxShadow: AppShadows.card,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TutorAvatar(name: view.studentName, size: 48),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(view.studentName,
                              style: textTheme.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          if (academic.isNotEmpty)
                            Text(academic,
                                style: textTheme.bodySmall
                                    ?.copyWith(color: AppColors.textSecondary),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    BookingStatusBadge(status: booking.estado),
                  ],
                ),
                const Divider(height: AppSpacing.lg),
                RequestInfoRow(icon: Icons.menu_book_outlined, label: 'Materia', value: view.subject),
                const SizedBox(height: AppSpacing.sm),
                RequestInfoRow(icon: Icons.notes_rounded, label: 'Tema', value: view.tema),
                const SizedBox(height: AppSpacing.sm),
                RequestInfoRow(icon: Icons.calendar_today_outlined, label: 'Fecha', value: view.fecha),
                const SizedBox(height: AppSpacing.sm),
                RequestInfoRow(icon: Icons.access_time_rounded, label: 'Hora', value: view.hora),
                const SizedBox(height: AppSpacing.sm),
                RequestInfoRow(icon: Icons.timelapse_rounded, label: 'Duración', value: view.duracion),
                const SizedBox(height: AppSpacing.sm),
                RequestInfoRow(icon: Icons.payments_outlined, label: 'Precio', value: view.precio),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fila "ícono · etiqueta · valor".
class RequestInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const RequestInfoRow({super.key, required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 80,
          child: Text(label,
              style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
        ),
        Expanded(
          child: Text(value,
              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

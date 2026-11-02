import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/models/models.dart';
import '../routes/app_navigator.dart';
import '../state/booking_actions.dart';
import '../state/booking_store.dart';
import '../state/tutor_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/app_back_button.dart';
import '../widgets/booking_status_badge.dart';
import '../widgets/bottom_action_bar.dart';
import '../widgets/rating_label.dart';
import '../widgets/secondary_button.dart';
import '../widgets/section_title.dart';
import '../widgets/tutor_avatar.dart';
import '../widgets/tutor_request_card.dart' show RequestInfoRow;

/// Detalle de una reserva del estudiante: sesión, estado y datos del tutor.
/// Lee la reserva de BookingStore por id, así se actualiza al cancelar.
class StudentBookingDetailScreen extends StatefulWidget {
  final String bookingId;
  const StudentBookingDetailScreen({super.key, required this.bookingId});

  @override
  State<StudentBookingDetailScreen> createState() => _StudentBookingDetailScreenState();
}

class _StudentBookingDetailScreenState extends State<StudentBookingDetailScreen> {
  Future<TutorSummary?>? _tutor;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    final booking = context.read<BookingStore>().studentBookingById(widget.bookingId);
    if (booking != null) _tutor = context.read<TutorStore>().getTutor(booking.tutorId);
  }

  Future<void> _cancel(Booking booking) async {
    if (_cancelling) return; // evita dobles pulsaciones
    if (!await confirmCancelBooking(context) || !mounted) return;
    setState(() => _cancelling = true); // indicador solo mientras se guarda
    await cancelBookingWithFeedback(context, booking);
    if (mounted) setState(() => _cancelling = false);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final store = context.watch<BookingStore>();
    final booking = store.studentBookingById(widget.bookingId);

    if (booking == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reserva'), leading: const AppBackButton()),
        body: Center(child: Text('No se encontró la reserva.', style: textTheme.bodyLarge)),
      );
    }

    return FutureBuilder<TutorSummary?>(
      future: _tutor,
      builder: (context, snapshot) {
        final tutor = snapshot.data;
        final catalog = context.watch<TutorStore>().subjects;
        final subject = [...?tutor?.subjects, ...catalog]
            .where((s) => s.id == booking.subjectId)
            .firstOrNull;
        final start = booking.fechaHora;
        final end = booking.fin;
        final hora = '${Formatters.time(start.hour * 60 + start.minute)} – '
            '${Formatters.time(end.hour * 60 + end.minute)}';
        final pending = booking.estado == BookingStatus.pendiente;
        final working = _cancelling || store.isLoading;

        return Scaffold(
          appBar: AppBar(title: const Text('Reserva'), leading: const AppBackButton()),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppLayout.maxContentWidth),
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.screenPadding),
                children: [
                  Row(
                    children: [
                      TutorAvatar(
                        name: tutor?.nombre ?? 'Tutor',
                        photoPath: tutor?.profile.photoPath,
                        size: 64,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Tutor', style: textTheme.bodySmall),
                            Text(tutor?.nombre ?? 'Tutor', style: textTheme.titleLarge),
                            const SizedBox(height: AppSpacing.xs),
                            BookingStatusBadge(status: booking.estado),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const SectionTitle(title: 'Sesión'),
                  const SizedBox(height: AppSpacing.sm),
                  _Card(children: [
                    RequestInfoRow(
                        icon: Icons.menu_book_outlined,
                        label: 'Materia',
                        value: subject?.nombre ?? '—'),
                    RequestInfoRow(
                        icon: Icons.notes_rounded,
                        label: 'Tema',
                        value: (booking.tema?.trim().isNotEmpty ?? false)
                            ? booking.tema!
                            : 'Sin tema específico'),
                    RequestInfoRow(
                        icon: Icons.calendar_today_outlined,
                        label: 'Fecha',
                        value: Formatters.dateLong(start)),
                    RequestInfoRow(icon: Icons.access_time_rounded, label: 'Hora', value: hora),
                    RequestInfoRow(
                        icon: Icons.timelapse_rounded,
                        label: 'Duración',
                        value: Formatters.durationMinutes(booking.duracion)),
                    RequestInfoRow(
                        icon: Icons.payments_outlined,
                        label: 'Total',
                        value: Formatters.price(booking.precio)),
                  ]),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _statusNote(booking.estado),
                    style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                  ),
                  if (tutor != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    const SectionTitle(title: 'Sobre el tutor'),
                    const SizedBox(height: AppSpacing.sm),
                    _Card(children: [
                      RequestInfoRow(
                          icon: Icons.school_outlined,
                          label: 'Carrera',
                          value: tutor.user.carrera.isEmpty ? '—' : tutor.user.carrera),
                      Row(
                        children: [
                          const Icon(Icons.star_outline_rounded,
                              size: 18, color: AppColors.primary),
                          const SizedBox(width: AppSpacing.sm),
                          SizedBox(
                            width: 80,
                            child: Text('Valoración',
                                style: textTheme.bodyMedium
                                    ?.copyWith(color: AppColors.textSecondary)),
                          ),
                          RatingLabel(rating: tutor.rating),
                        ],
                      ),
                      RequestInfoRow(
                          icon: Icons.sell_outlined,
                          label: 'Precio',
                          value: Formatters.pricePerHour(tutor.precioHora)),
                    ]),
                    if (tutor.profile.descripcion.trim().isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(tutor.profile.descripcion,
                          style: textTheme.bodyLarge?.copyWith(height: 1.4)),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    SecondaryButton(
                      label: 'Ver perfil del tutor',
                      icon: Icons.person_outline_rounded,
                      onPressed: () => AppNavigator.toTutorProfile(context, tutor),
                    ),
                  ] else if (snapshot.connectionState == ConnectionState.waiting) ...[
                    const SizedBox(height: AppSpacing.lg),
                    const Center(child: CircularProgressIndicator()),
                  ],
                ],
              ),
            ),
          ),
          // Solo una solicitud pendiente se puede cancelar.
          bottomNavigationBar: !pending
              ? null
              : BottomActionBar(
                  child: SecondaryButton(
                    label: 'Cancelar solicitud',
                    icon: Icons.close_rounded,
                    loading: working,
                    onPressed: working ? null : () => _cancel(booking),
                  ),
                ),
        );
      },
    );
  }

  static String _statusNote(BookingStatus estado) => switch (estado) {
        BookingStatus.pendiente =>
          'El tutor aún no responde. Puedes cancelar la solicitud mientras esté pendiente.',
        BookingStatus.aceptada =>
          'El tutor aceptó la tutoría. Una reserva aceptada ya no se puede cancelar desde la app.',
        BookingStatus.rechazada => 'El tutor rechazó esta solicitud.',
        BookingStatus.cancelada => 'Cancelaste esta solicitud.',
      };
}

/// Tarjeta blanca con filas separadas.
class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
            children[i],
          ],
        ],
      ),
    );
  }
}

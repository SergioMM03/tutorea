import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/models/models.dart';
import '../state/booking_actions.dart';
import '../state/booking_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/booking_follow_up_section.dart';
import '../widgets/booking_status_badge.dart';
import '../widgets/bottom_action_bar.dart';
import '../widgets/form_error_banner.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/section_title.dart';
import '../widgets/tutor_avatar.dart';
import '../widgets/tutor_request_card.dart';

/// Detalle de una solicitud recibida. Si está pendiente, el tutor puede
/// aceptarla o rechazarla (con confirmación). Si está aceptada, puede
/// cancelarla antes de la hora de inicio, con motivo.
class TutorRequestDetailScreen extends StatefulWidget {
  final String bookingId;
  const TutorRequestDetailScreen({super.key, required this.bookingId});

  @override
  State<TutorRequestDetailScreen> createState() => _TutorRequestDetailScreenState();
}

class _TutorRequestDetailScreenState extends State<TutorRequestDetailScreen> {
  /// Evita dobles pulsaciones mientras se guarda el cambio.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<BookingStore>().clearError();
    });
  }

  Booking? _find(BookingStore store) =>
      store.tutorRequests.where((b) => b.id == widget.bookingId).firstOrNull;

  Future<void> _accept() => _change(
        confirmed: true,
        action: (store) => store.accept(widget.bookingId),
        message: 'Solicitud aceptada',
      );

  Future<void> _reject() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Rechazar solicitud?'),
        content: const Text(
            'El estudiante verá la solicitud como rechazada. Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sí, rechazar'),
          ),
        ],
      ),
    );
    await _change(
      confirmed: confirmed == true,
      action: (store) => store.reject(widget.bookingId),
      message: 'Solicitud rechazada',
    );
  }

  Future<void> _cancelAccepted(Booking booking) async {
    if (_busy) return;
    final motivo = await askCancelReason(context);
    if (motivo == null || !mounted) return;
    setState(() => _busy = true);
    await cancelBookingWithFeedback(context, booking, motivo: motivo);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _change({
    required bool confirmed,
    required Future<bool> Function(BookingStore store) action,
    required String message,
  }) async {
    if (!confirmed || _busy || !mounted) return;
    final store = context.read<BookingStore>();
    // Solo se cambian solicitudes pendientes (el repositorio también lo valida).
    if (_find(store)?.estado != BookingStatus.pendiente) return;

    setState(() => _busy = true);
    final ok = await action(store);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return; // el error del store se muestra en pantalla

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    Navigator.maybePop(context);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final store = context.watch<BookingStore>();
    final booking = _find(store);

    if (booking == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Solicitud'), leading: const AppBackButton()),
        body: Center(
          child: store.isLoading
              ? const CircularProgressIndicator()
              : Text('No se encontró la solicitud.', style: textTheme.bodyLarge),
        ),
      );
    }

    final view = TutorRequestView.of(context, booking);
    final pending = booking.estado == BookingStatus.pendiente;
    final cancellable = store.canCancelAsTutor(booking);
    final working = _busy || store.isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Solicitud'), leading: const AppBackButton()),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.maxContentWidth),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            children: [
              Row(
                children: [
                  TutorAvatar(name: view.studentName, size: 64),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(view.studentName, style: textTheme.titleLarge),
                        const SizedBox(height: AppSpacing.xs),
                        BookingStatusBadge(status: booking.estado),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (store.error != null) ...[
                FormErrorBanner(message: store.error!),
                const SizedBox(height: AppSpacing.md),
              ],
              const SectionTitle(title: 'Estudiante'),
              const SizedBox(height: AppSpacing.sm),
              _Card(children: [
                RequestInfoRow(
                    icon: Icons.account_balance_outlined,
                    label: 'Universidad',
                    value: view.university.isEmpty ? '—' : view.university),
                RequestInfoRow(
                    icon: Icons.school_outlined,
                    label: 'Carrera',
                    value: view.career.isEmpty ? '—' : view.career),
              ]),
              const SizedBox(height: AppSpacing.lg),
              const SectionTitle(title: 'Sesión solicitada'),
              const SizedBox(height: AppSpacing.sm),
              _Card(children: [
                RequestInfoRow(icon: Icons.menu_book_outlined, label: 'Materia', value: view.subject),
                RequestInfoRow(icon: Icons.notes_rounded, label: 'Tema', value: view.tema),
                RequestInfoRow(icon: Icons.calendar_today_outlined, label: 'Fecha', value: view.fecha),
                RequestInfoRow(icon: Icons.access_time_rounded, label: 'Hora', value: view.hora),
                RequestInfoRow(icon: Icons.timelapse_rounded, label: 'Duración', value: view.duracion),
                RequestInfoRow(
                    icon: Icons.videocam_outlined,
                    label: 'Modalidad',
                    value: booking.modalidad?.label ?? '—'),
                if (booking.ubicacion != null)
                  RequestInfoRow(
                      icon: Icons.place_outlined,
                      label: booking.modalidad == TutoringModality.virtual ? 'Enlace' : 'Lugar',
                      value: booking.ubicacion!),
                RequestInfoRow(icon: Icons.payments_outlined, label: 'Precio', value: view.precio),
                if (booking.motivoCancelacion != null)
                  RequestInfoRow(
                      icon: Icons.info_outline_rounded,
                      label: 'Motivo',
                      value: booking.motivoCancelacion!),
              ]),
              if (!pending) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Esta solicitud ya está ${booking.estado.label.toLowerCase()} '
                  'y no se puede modificar.'
                  '${cancellable ? ' Puedes cancelarla antes de la hora de inicio indicando el motivo.' : ''}'
                  '${booking.estado == BookingStatus.cancelada ? (booking.canceladaPor == booking.studentId ? ' La canceló el estudiante.' : ' La cancelaste tú.') : ''}',
                  style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                ),
              ],
              // Fase 14.9: confirmación, incidencias y calificación recibida.
              BookingFollowUpSection(booking: booking, party: BookingParty.tutor),
            ],
          ),
        ),
      ),
      // Pendiente: aceptar o rechazar. Aceptada y antes del inicio: cancelar con motivo.
      bottomNavigationBar: cancellable
          ? BottomActionBar(
              child: SecondaryButton(
                label: 'Cancelar sesión',
                icon: Icons.close_rounded,
                loading: working,
                onPressed: working ? null : () => _cancelAccepted(booking),
              ),
            )
          : !pending
          ? null
          : BottomActionBar(
              child: Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: 'Rechazar',
                      onPressed: working ? null : _reject,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: PrimaryButton(
                      label: 'Aceptar',
                      loading: working,
                      onPressed: working ? null : _accept,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
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

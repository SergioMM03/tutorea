import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/models/models.dart';
import '../theme/app_colors.dart';
import 'booking_store.dart';
import 'session_store.dart';

/// Pide confirmación para cancelar una solicitud pendiente. Devuelve true si
/// quien la envió confirmó.
Future<bool> confirmCancelBooking(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('¿Cancelar solicitud?'),
      content: const Text(
          'El tutor verá la solicitud como cancelada. Esta acción no se puede deshacer.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Volver'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Sí, cancelar'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Pide el motivo para cancelar una reserva aceptada (obligatorio, mínimo 3
/// caracteres). Devuelve el motivo, o null si se desistió.
Future<String?> askCancelReason(BuildContext context) => showDialog<String>(
      context: context,
      builder: (_) => const _CancelReasonDialog(),
    );

class _CancelReasonDialog extends StatefulWidget {
  const _CancelReasonDialog();

  @override
  State<_CancelReasonDialog> createState() => _CancelReasonDialogState();
}

class _CancelReasonDialogState extends State<_CancelReasonDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _valid => _reason.text.trim().length >= 3;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('¿Cancelar reserva?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('La otra persona verá la reserva cancelada y el motivo. '
              'Esta acción no se puede deshacer.'),
          const SizedBox(height: 12),
          TextField(
            key: const Key('cancel-reason'),
            controller: _reason,
            autofocus: true,
            maxLength: 500,
            maxLines: 3,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Motivo de la cancelación'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Volver'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          onPressed: _valid ? () => Navigator.pop(context, _reason.text.trim()) : null,
          child: const Text('Sí, cancelar'),
        ),
      ],
    );
  }
}

/// Cancela con BookingStore.cancel() y muestra el resultado (éxito o error).
/// Devuelve true si se canceló.
Future<bool> cancelBookingWithFeedback(BuildContext context, Booking booking,
    {String? motivo}) async {
  final store = context.read<BookingStore>();
  final actorId = context.read<SessionStore>().user?.id;
  final messenger = ScaffoldMessenger.of(context);
  final wasAccepted = booking.estado == BookingStatus.aceptada;
  final ok = await store.cancel(booking.id, motivo: motivo, actorId: actorId);
  messenger.showSnackBar(SnackBar(
    content: Text(ok
        ? (wasAccepted ? 'Reserva cancelada' : 'Solicitud cancelada')
        : (store.error ?? 'No se pudo cancelar la solicitud.')),
  ));
  return ok;
}

/// Mis reservas y los detalles: confirmar (o pedir el motivo, si estaba
/// aceptada) y luego cancelar.
Future<bool> confirmAndCancelBooking(BuildContext context, Booking booking) async {
  String? motivo;
  if (booking.requiereMotivo) {
    motivo = await askCancelReason(context);
    if (motivo == null) return false;
  } else if (!await confirmCancelBooking(context)) {
    return false;
  }
  if (!context.mounted) return false;
  return cancelBookingWithFeedback(context, booking, motivo: motivo);
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/models/models.dart';
import '../theme/app_colors.dart';
import 'booking_store.dart';

/// Pide confirmación para cancelar una solicitud. Devuelve true si el
/// estudiante confirmó.
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

/// Cancela con BookingStore.cancel() y muestra el resultado (éxito o error).
/// Devuelve true si se canceló.
Future<bool> cancelBookingWithFeedback(BuildContext context, Booking booking) async {
  final store = context.read<BookingStore>();
  final messenger = ScaffoldMessenger.of(context);
  final ok = await store.cancel(booking.id);
  messenger.showSnackBar(SnackBar(
    content: Text(ok
        ? 'Solicitud cancelada'
        : (store.error ?? 'No se pudo cancelar la solicitud.')),
  ));
  return ok;
}

/// Mis reservas y Detalle: confirmar y luego cancelar.
Future<bool> confirmAndCancelBooking(BuildContext context, Booking booking) async {
  if (!await confirmCancelBooking(context)) return false;
  if (!context.mounted) return false;
  return cancelBookingWithFeedback(context, booking);
}

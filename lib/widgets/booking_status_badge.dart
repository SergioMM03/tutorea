import 'package:flutter/material.dart';

import '../domain/models/booking_status.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Etiqueta de color según el estado de una solicitud.
class BookingStatusBadge extends StatelessWidget {
  final BookingStatus status;
  const BookingStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (status) {
      BookingStatus.pendiente => (AppColors.warningLight, AppColors.warningDark),
      BookingStatus.aceptada => (AppColors.successLight, AppColors.success),
      BookingStatus.rechazada ||
      BookingStatus.cancelada =>
        (AppColors.errorLight, AppColors.error),
      BookingStatus.pendienteConfirmacion => (AppColors.primaryLight, AppColors.primary),
      BookingStatus.completada => (AppColors.primarySoft, AppColors.primary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        status.label,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: foreground, fontWeight: FontWeight.w600),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Estrella + calificación ("★ 4.9"). Sin reseñas muestra «Nuevo», nunca «0.0».
class RatingLabel extends StatelessWidget {
  /// Promedio de las reseñas; null = todavía no tiene (se muestra «Nuevo»).
  final double? rating;

  /// Cantidad de reseñas; si se indica, se muestra entre paréntesis.
  final int? count;
  final bool large; // true en el perfil, false en tarjetas

  const RatingLabel({super.key, required this.rating, this.count, this.large = false});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final value = rating;
    final style = large ? textTheme.bodyLarge : textTheme.bodyMedium;
    if (value == null || (count != null && count == 0)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text('Nuevo',
            style: style?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: large ? 22 : 18, color: AppColors.textPrimary),
        const SizedBox(width: 2),
        Text(value.toStringAsFixed(1), style: style),
        if (count != null) ...[
          const SizedBox(width: 4),
          Text('($count)', style: style?.copyWith(color: AppColors.textSecondary)),
        ],
      ],
    );
  }
}

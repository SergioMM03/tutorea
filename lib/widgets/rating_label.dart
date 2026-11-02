import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Estrella + calificación ("★ 4.9").
class RatingLabel extends StatelessWidget {
  final double rating;
  final bool large; // true en el perfil, false en tarjetas

  const RatingLabel({super.key, required this.rating, this.large = false});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: large ? 22 : 18, color: AppColors.textPrimary),
        const SizedBox(width: 2),
        Text(
          rating.toStringAsFixed(1),
          style: large ? textTheme.bodyLarge : textTheme.bodyMedium,
        ),
      ],
    );
  }
}

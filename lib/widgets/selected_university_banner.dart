import 'package:flutter/material.dart';

import '../domain/models/models.dart';
import '../routes/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Universidad elegida en la pantalla inicial, con opción de cambiarla.
/// Si no hay ninguna elegida, lo indica y ofrece ir a elegirla.
/// (Login y Registro.)
class SelectedUniversityBanner extends StatelessWidget {
  final University? university;
  const SelectedUniversityBanner({super.key, required this.university});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final selected = university;

    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_balance_outlined, color: AppColors.primary, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              selected?.nombre ?? 'Aún no has elegido tu universidad.',
              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () => AppNavigator.toUniversitySelection(context),
            child: Text(selected == null ? 'Elegir' : 'Cambiar'),
          ),
        ],
      ),
    );
  }
}

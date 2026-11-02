import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Chip en forma de píldora para materias, categorías y opciones.
/// - Solo lectura (perfil del tutor): sin [onTap].
/// - Seleccionable (filtros, hora, duración): con [onTap] y [selected].
class SubjectChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const SubjectChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  static const _duration = Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.pill);
    final interactive = onTap != null;

    return Semantics(
      button: interactive,
      selected: interactive ? selected : null,
      child: AnimatedContainer(
        duration: _duration,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.primarySoft,
          borderRadius: radius,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Padding(
              // Alto ≈ 40 px: área de toque cómoda.
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm + 2,
              ),
              child: AnimatedDefaultTextStyle(
                duration: _duration,
                // Mismo grosor seleccionado o no: el chip no cambia de ancho.
                style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
                    .copyWith(
                  color: selected ? AppColors.textOnPrimary : AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
                child: Text(label),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

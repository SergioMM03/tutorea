import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Barra fija inferior con la acción principal de la pantalla
/// (Reservar sesión, Enviar solicitud). Respeta el área segura y,
/// en tablets, alinea su contenido con el ancho máximo del contenido.
class BottomActionBar extends StatelessWidget {
  final Widget child;
  final double maxContentWidth;

  const BottomActionBar({
    super.key,
    required this.child,
    this.maxContentWidth = AppLayout.maxContentWidth,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxContentWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding,
                vertical: AppSpacing.md,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

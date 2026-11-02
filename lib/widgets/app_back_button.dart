import 'package:flutter/material.dart';

import '../routes/app_navigator.dart';
import '../theme/app_colors.dart';

/// Botón volver de Tutorea (chevron azul), igual en todas las pantallas.
class AppBackButton extends StatelessWidget {
  final VoidCallback? onPressed; // por defecto: cerrar la pantalla

  const AppBackButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Volver',
      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primary),
      onPressed: onPressed ?? () => AppNavigator.back(context),
    );
  }
}

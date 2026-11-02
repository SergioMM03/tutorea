import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Logo de Tutorea: birrete azul + nombre.
/// [size] es la altura del ícono; el texto escala en proporción.
class AppLogo extends StatelessWidget {
  final double size;
  final bool showText;
  final Axis direction; // vertical (bienvenida) u horizontal (encabezados)

  const AppLogo({
    super.key,
    this.size = 48,
    this.showText = true,
    this.direction = Axis.vertical,
  });

  @override
  Widget build(BuildContext context) {
    final icon = Icon(Icons.school_rounded, size: size, color: AppColors.primary);
    if (!showText) return icon;

    final vertical = direction == Axis.vertical;
    final text = Text(
      'Tutorea',
      style: TextStyle(
        fontSize: vertical ? size : size * 0.75,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
        letterSpacing: -0.5,
        height: 1.1,
      ),
    );

    return Flex(
      direction: direction,
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        SizedBox(width: vertical ? 0 : size * 0.2, height: vertical ? size * 0.15 : 0),
        text,
      ],
    );
  }
}

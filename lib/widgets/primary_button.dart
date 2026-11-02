import 'package:flutter/material.dart';

import 'button_content.dart';

/// Botón azul principal. El color, la forma y la tipografía vienen de
/// `elevatedButtonTheme` en app_theme.dart (no se repiten aquí).
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed; // null = deshabilitado
  final IconData? icon;
  final bool loading;
  final bool expanded; // true = ancho completo

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expanded = true,
  });

  @override
  Widget build(BuildContext context) {
    final button = ElevatedButton(
      onPressed: loading ? null : onPressed,
      child: ButtonContent(label: label, icon: icon, loading: loading),
    );
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

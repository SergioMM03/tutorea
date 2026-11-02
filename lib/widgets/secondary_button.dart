import 'package:flutter/material.dart';

import 'button_content.dart';

/// Botón blanco con borde azul. El estilo viene de
/// `outlinedButtonTheme` en app_theme.dart.
class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed; // null = deshabilitado
  final IconData? icon;
  final bool loading;
  final bool expanded; // true = ancho completo

  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expanded = true,
  });

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton(
      onPressed: loading ? null : onPressed,
      child: ButtonContent(label: label, icon: icon, loading: loading),
    );
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

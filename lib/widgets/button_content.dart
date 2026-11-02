import 'package:flutter/material.dart';

/// Contenido interno compartido por PrimaryButton y SecondaryButton:
/// texto, ícono opcional o indicador de carga.
class ButtonContent extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool loading;

  const ButtonContent({super.key, required this.label, this.icon, this.loading = false});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    }
    if (icon == null) return Text(label);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}

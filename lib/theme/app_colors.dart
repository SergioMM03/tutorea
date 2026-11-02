import 'package:flutter/material.dart';

/// Paleta de Tutorea (identidad visual del documento de diseño).
class AppColors {
  AppColors._();

  // Marca
  static const Color primary = Color(0xFF1D4ED8); // acciones importantes
  static const Color primaryLight = Color(0xFFEFF6FF); // acentos
  static const Color primarySoft = Color(0xFFDBEAFE); // chips, avatares

  // Fondos y superficies
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE2E8F0);

  // Texto
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // Estados
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFDC2626);

  // Fondos suaves para etiquetas de estado
  static const Color successLight = Color(0xFFDCFCE7);
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color errorLight = Color(0xFFFEE2E2);
  static const Color warningDark = Color(0xFFB45309); // texto sobre warningLight
  static const Color disabled = Color(0xFFE5E7EB);
}

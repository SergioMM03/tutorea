import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

/// Tema global de Tutorea: fondo blanco, azul para acciones,
/// tipografía sans serif y componentes redondeados.
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.primary,
      onPrimary: AppColors.textOnPrimary,
      secondary: AppColors.primaryLight,
      onSecondary: AppColors.primary,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.error,
      // Sin tinte azul en diálogos, menús y hojas (superficies blancas limpias).
      surfaceTint: Colors.transparent,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,

      textTheme: const TextTheme(
        // Título principal de Bienvenida ("Tutorea").
        displayMedium: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            color: AppColors.textPrimary),
        headlineLarge: TextStyle(
            fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        headlineMedium: TextStyle(
            fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        // Subtítulos de pantalla ("Aprende mejor...", "¿En qué materia...").
        headlineSmall: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w400,
            height: 1.3,
            color: AppColors.textPrimary),
        titleLarge: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        titleMedium: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        bodyLarge: TextStyle(fontSize: 16, color: AppColors.textPrimary),
        bodyMedium: TextStyle(fontSize: 14, color: AppColors.textPrimary),
        bodySmall: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          minimumSize: const Size(64, 52), // alto fijo; el ancho lo decide el widget
          elevation: 0,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          backgroundColor: AppColors.surface,
          minimumSize: const Size(64, 52), // alto fijo; el ancho lo decide el widget
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primary),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.md),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),

      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
    );
  }
}

/// Sombras compartidas (tarjetas).
class AppShadows {
  AppShadows._();

  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x140F172A), blurRadius: 16, offset: Offset(0, 4)),
  ];
}

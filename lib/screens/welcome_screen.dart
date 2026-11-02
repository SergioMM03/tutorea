import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../routes/app_navigator.dart';
import '../state/session_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/formatters.dart';
import '../widgets/app_logo.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';

/// 1. Bienvenida: después de elegir la universidad.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const String _illustration = 'assets/images/welcome_students.png';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final university = context.watch<SessionStore>().selectedUniversity;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // La ilustración se adapta al alto disponible.
            final illustrationHeight =
                (constraints.maxHeight * 0.26).clamp(140.0, 280.0).toDouble();

            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: AppLayout.maxNarrowWidth),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.screenPadding,
                        vertical: AppSpacing.md,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (university != null)
                            _UniversityBadge(
                                label: Formatters.universityShortName(university.nombre)),
                          const SizedBox(height: AppSpacing.md),
                          const AppLogo(size: 56, showText: false),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Tutorea',
                            style: textTheme.displayMedium,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Aprende mejor, con\nestudiantes como tú.',
                            textAlign: TextAlign.center,
                            style: textTheme.headlineSmall,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Image.asset(
                            _illustration,
                            height: illustrationHeight,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          const _BenefitsRow(),
                          const SizedBox(height: AppSpacing.xl),
                          PrimaryButton(
                            label: 'Iniciar sesión',
                            onPressed: () => AppNavigator.signIn(context),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          SecondaryButton(
                            label: 'Crear cuenta',
                            onPressed: () => AppNavigator.toRegister(context),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _TutorSignUpLink(
                            onTap: () => AppNavigator.toTutorRegister(context),
                          ),
                          TextButton(
                            onPressed: () => AppNavigator.toUniversitySelection(context),
                            child: const Text('Cambiar universidad'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Etiqueta con la universidad elegida (ej. "ESEN") en la parte superior.
class _UniversityBadge extends StatelessWidget {
  final String label;
  const _UniversityBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}

/// Fila de beneficios: ícono en círculo azul claro + texto.
class _BenefitsRow extends StatelessWidget {
  const _BenefitsRow();

  static const _benefits = [
    (Icons.school_outlined, 'Tutores de tu\nuniversidad'),
    (Icons.edit_calendar_outlined, 'Reserva fácil\ny rápida'),
    (Icons.menu_book_outlined, 'Apoyo en tus\nmaterias'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final b in _benefits)
          Expanded(child: _BenefitItem(icon: b.$1, label: b.$2)),
      ],
    );
  }
}

class _BenefitItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _BenefitItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            color: AppColors.primaryLight,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.primary, size: 30),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.3),
        ),
      ],
    );
  }
}

/// "¿Eres tutor? Regístrate aquí"
class _TutorSignUpLink extends StatelessWidget {
  final VoidCallback onTap;
  const _TutorSignUpLink({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Text.rich(
          TextSpan(
            text: '¿Eres tutor? ',
            style: style,
            children: [
              TextSpan(
                text: 'Regístrate aquí',
                style: style?.copyWith(color: AppColors.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

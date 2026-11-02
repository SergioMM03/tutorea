import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/models/models.dart';
import '../routes/app_navigator.dart';
import '../state/session_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/form_error_banner.dart';
import '../widgets/primary_button.dart';

/// Pantalla inicial sin sesión: elegir la universidad.
/// Muestra solo las universidades activas de UniversityRepository; la elegida
/// se guarda en el dispositivo y es el contexto de Login y Registro.
class UniversitySelectionScreen extends StatefulWidget {
  const UniversitySelectionScreen({super.key});

  @override
  State<UniversitySelectionScreen> createState() => _UniversitySelectionScreenState();
}

class _UniversitySelectionScreenState extends State<UniversitySelectionScreen> {
  /// Elegida en pantalla (todavía sin guardar hasta "Continuar").
  String? _pickedId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Lista fresca cada vez que se abre (ej. al cerrar sesión).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SessionStore>().loadUniversities();
    });
  }

  Future<void> _continue(String universityId) async {
    if (_saving) return;
    setState(() => _saving = true);
    final ok = await context.read<SessionStore>().selectUniversity(universityId);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) AppNavigator.afterUniversitySelected(context);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final session = context.watch<SessionStore>();
    final universities = session.activeUniversities;

    // Por defecto, la última universidad elegida en este dispositivo.
    final pickedId = _pickedId ?? session.selectedUniversity?.id;
    final picked = universities.where((u) => u.id == pickedId).firstOrNull;

    Widget list;
    if (!session.universitiesLoaded) {
      list = const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (universities.isEmpty) {
      list = _EmptyUniversities(
        onRetry: () => context.read<SessionStore>().loadUniversities(),
      );
    } else {
      list = Column(
        children: [
          for (final u in universities) ...[
            _UniversityCard(
              university: u,
              selected: u.id == picked?.id,
              onTap: () => setState(() => _pickedId = u.id),
            ),
            const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
          ],
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding,
              vertical: AppSpacing.lg,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppLayout.maxNarrowWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: AppLogo(size: 56, showText: false)),
                  const SizedBox(height: AppSpacing.xs),
                  Text('Tutorea', textAlign: TextAlign.center, style: textTheme.displayMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Te damos la bienvenida',
                    textAlign: TextAlign.center,
                    style: textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Encuentra tutores de tu propia universidad y reserva '
                    'sesiones en las materias que necesitas.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text('Selecciona tu universidad', style: textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.md),
                  if (session.error != null && session.universitiesLoaded) ...[
                    FormErrorBanner(message: session.error!),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  list,
                  const SizedBox(height: AppSpacing.lg),
                  if (universities.isNotEmpty)
                    PrimaryButton(
                      label: 'Continuar',
                      loading: _saving,
                      onPressed: picked == null || _saving ? null : () => _continue(picked.id),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tarjeta seleccionable de una universidad.
class _UniversityCard extends StatelessWidget {
  final University university;
  final bool selected;
  final VoidCallback onTap;

  const _UniversityCard({
    required this.university,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(AppRadius.card);

    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : AppColors.surface,
          borderRadius: radius,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected ? null : AppShadows.card,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.surface : AppColors.primaryLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.account_balance_outlined, color: AppColors.primary),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(university.nombre, style: textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          university.pais,
                          style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Icon(
                    selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                    color: selected ? AppColors.primary : AppColors.border,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// No hay universidades activas.
class _EmptyUniversities extends StatelessWidget {
  final VoidCallback onRetry;
  const _EmptyUniversities({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        children: [
          const Icon(Icons.account_balance_outlined, size: 40, color: AppColors.primary),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Por ahora no hay universidades disponibles.',
            textAlign: TextAlign.center,
            style: textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Vuelve a intentarlo más tarde.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}

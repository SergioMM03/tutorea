import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_back_button.dart';

/// Esqueleto temporal para pantallas aún no construidas.
/// Muestra el nombre de la pantalla y botones para probar la navegación.
/// Se elimina cuando todas las pantallas estén completas.
class ScreenPlaceholder extends StatelessWidget {
  final String title;
  final String description;
  final List<Widget> actions;
  final bool showBackButton;

  const ScreenPlaceholder({
    super.key,
    required this.title,
    required this.description,
    this.actions = const [],
    this.showBackButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        automaticallyImplyLeading: false,
        leading: showBackButton && Navigator.canPop(context)
            ? const AppBackButton()
            : null,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Text(description, style: textTheme.bodyLarge),
              ),
              const Spacer(),
              for (final action in actions) ...[
                action,
                const SizedBox(height: AppSpacing.md),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// Pantalla de arranque cuando Supabase no está disponible (Fase 14.10).
/// No muestra datos locales: explica el problema y permite reintentar.
class StartupErrorApp extends StatefulWidget {
  final String message;
  final Future<void> Function() onRetry;

  const StartupErrorApp({super.key, required this.message, required this.onRetry});

  @override
  State<StartupErrorApp> createState() => _StartupErrorAppState();
}

class _StartupErrorAppState extends State<StartupErrorApp> {
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    await widget.onRetry(); // si vuelve a fallar, se muestra de nuevo esta pantalla
    if (mounted) setState(() => _retrying = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tutorea',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 56, color: AppColors.primary),
                  const SizedBox(height: AppSpacing.md),
                  Text('Sin conexión con Tutorea',
                      style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
                  const SizedBox(height: AppSpacing.sm),
                  Text(widget.message,
                      key: const Key('startup-error-message'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: AppSpacing.lg),
                  ElevatedButton.icon(
                    key: const Key('startup-retry'),
                    onPressed: _retrying ? null : _retry,
                    icon: _retrying
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh_rounded),
                    label: const Text('Reintentar'),
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

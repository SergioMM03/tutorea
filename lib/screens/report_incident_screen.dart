import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/follow_up_rules.dart';
import '../domain/models/models.dart';
import '../state/follow_up_stores.dart';
import '../state/session_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_back_button.dart';
import '../widgets/bottom_action_bar.dart';
import '../widgets/form_error_banner.dart';
import '../widgets/primary_button.dart';

/// Reportar un problema de una reserva (Fase 14.9): categoría y descripción.
/// Lo revisa el administrador de la universidad; mientras esté abierta, la
/// reserva no se completa ni se califica. Devuelve true al enviarse.
class ReportIncidentScreen extends StatefulWidget {
  final String bookingId;
  const ReportIncidentScreen({super.key, required this.bookingId});

  @override
  State<ReportIncidentScreen> createState() => _ReportIncidentScreenState();
}

class _ReportIncidentScreenState extends State<ReportIncidentScreen> {
  final _description = TextEditingController();
  IncidentCategory? _category;
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final problem = FollowUpRules.incidentInputProblem(_category, _description.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final store = context.read<IncidentStore>();
    final actorId = context.read<SessionStore>().user?.id;
    setState(() {
      _sending = true;
      _error = null;
    });
    final created = await store.report(
      bookingId: widget.bookingId,
      category: _category!,
      description: _description.text,
      actorId: actorId,
    );
    if (!mounted) return;
    if (created != null) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _sending = false;
        _error = store.error ?? 'No se pudo enviar el reporte.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Reportar un problema'), leading: const AppBackButton()),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        children: [
          Text(
            'Cuéntanos qué pasó. Lo revisará tu universidad; reportar no genera '
            'calificaciones ni sanciones automáticas.',
            style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Categoría', style: textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final c in IncidentCategory.values)
                ChoiceChip(
                  key: Key('incident-category-${c.name}'),
                  label: Text(c.label),
                  selected: _category == c,
                  selectedColor: AppColors.primaryLight,
                  onSelected: (_) => setState(() => _category = c),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Descripción', style: textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: const Key('incident-description'),
            controller: _description,
            maxLength: 2000,
            minLines: 4,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Describe el problema (mínimo 10 caracteres)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            FormErrorBanner(message: _error!),
          ],
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        child: PrimaryButton(
          key: const Key('incident-submit'),
          label: 'Enviar reporte',
          icon: Icons.send_rounded,
          loading: _sending,
          onPressed: _sending ? null : _submit,
        ),
      ),
    );
  }
}

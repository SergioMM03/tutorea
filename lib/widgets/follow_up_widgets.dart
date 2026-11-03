import 'package:flutter/material.dart';

import '../domain/models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// Piezas visuales de la Fase 14.9 (confirmaciones, incidencias y reseñas).

/// Tarjeta blanca redondeada con sombra suave.
class FollowUpCard extends StatelessWidget {
  final List<Widget> children;
  final Color color;
  const FollowUpCard({super.key, required this.children, this.color = AppColors.surface});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: color == AppColors.surface ? AppShadows.card : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Etiqueta redondeada (estado de una incidencia, "Confirmó", etc.).
class FollowUpPill extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  const FollowUpPill({
    super.key,
    required this.label,
    this.background = AppColors.primaryLight,
    this.foreground = AppColors.primary,
  });

  factory FollowUpPill.incident(IncidentStatus status) => switch (status) {
        IncidentStatus.pendienteRevision => FollowUpPill(
            label: status.label, background: AppColors.warningLight, foreground: AppColors.warningDark),
        IncidentStatus.enInvestigacion => FollowUpPill(label: status.label),
        IncidentStatus.resuelta => FollowUpPill(
            label: status.label, background: AppColors.successLight, foreground: AppColors.success),
        IncidentStatus.desestimada => FollowUpPill(
            label: status.label, background: AppColors.disabled, foreground: AppColors.textSecondary),
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: foreground, fontWeight: FontWeight.w600)),
    );
  }
}

/// Estrellas de solo lectura (1 a 5).
class StarRow extends StatelessWidget {
  final int rating;
  final double size;
  const StarRow({super.key, required this.rating, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$rating de 5 estrellas',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 1; i <= 5; i++)
              Icon(i <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: size, color: i <= rating ? AppColors.primary : AppColors.border),
          ],
        ),
      ),
    );
  }
}

/// Una reseña (perfil del tutor o detalle de una reserva).
class ReviewTile extends StatelessWidget {
  final Review review;
  final String? title;
  const ReviewTile({super.key, required this.review, this.title});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final d = review.createdAt;
    return FollowUpCard(children: [
      if (title != null) Text(title!, style: textTheme.titleSmall),
      Row(
        children: [
          StarRow(rating: review.rating),
          const Spacer(),
          Text('${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}',
              style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
        ],
      ),
      if (review.comment != null && review.comment!.trim().isNotEmpty)
        Text(review.comment!, style: textTheme.bodyMedium?.copyWith(height: 1.4)),
    ]);
  }
}

/// Una incidencia: categoría, estado, descripción y resolución.
class IncidentTile extends StatelessWidget {
  final Incident incident;
  final bool mine;
  const IncidentTile({super.key, required this.incident, required this.mine});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return FollowUpCard(children: [
      Row(
        children: [
          Expanded(child: Text(incident.category.label, style: textTheme.titleSmall)),
          FollowUpPill.incident(incident.status),
        ],
      ),
      Text(mine ? 'Reportada por ti' : 'Reportada por el ${incident.reporterParty.label.toLowerCase()}',
          style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
      Text(incident.description, style: textTheme.bodyMedium?.copyWith(height: 1.4)),
      if (incident.resolutionNote != null)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Text('Resolución: ${incident.resolutionNote}',
              style: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary)),
        ),
    ]);
  }
}

/// Datos de una calificación escrita en el diálogo.
typedef ReviewInput = ({int rating, String? comment});

/// Pide de 1 a 5 estrellas y un comentario opcional. null = se desistió.
Future<ReviewInput?> askReview(BuildContext context) =>
    showDialog<ReviewInput>(context: context, builder: (_) => const _ReviewDialog());

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog();

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  final _comment = TextEditingController();
  int _rating = 0;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Calificar al tutor'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Tu calificación es pública y no se puede editar después.'),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  key: Key('review-star-$i'),
                  tooltip: '$i ${i == 1 ? 'estrella' : 'estrellas'}',
                  onPressed: () => setState(() => _rating = i),
                  icon: Icon(i <= _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 32, color: i <= _rating ? AppColors.primary : AppColors.textSecondary),
                ),
            ],
          ),
          TextField(
            key: const Key('review-comment'),
            controller: _comment,
            maxLength: 1000,
            maxLines: 4,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Comentario (opcional)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')),
        TextButton(
          key: const Key('review-submit'),
          onPressed: _rating == 0
              ? null
              : () {
                  final text = _comment.text.trim();
                  Navigator.pop<ReviewInput>(context, (rating: _rating, comment: text.isEmpty ? null : text));
                },
          child: const Text('Enviar'),
        ),
      ],
    );
  }
}

/// Pide confirmar que la sesión se realizó.
Future<bool> askConfirmSession(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('¿La sesión se realizó?'),
      content: const Text('Confirma solo si la tutoría ocurrió. Si hubo un problema, '
          'repórtalo en lugar de confirmar. Esta acción no se puede deshacer.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Volver')),
        TextButton(
          key: const Key('confirm-session-yes'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Sí, se realizó'),
        ),
      ],
    ),
  );
  return ok == true;
}

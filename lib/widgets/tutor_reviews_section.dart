import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/follow_up_stores.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'follow_up_widgets.dart';
import 'section_title.dart';

/// Reseñas públicas de un tutor (sin datos de quién calificó). Fase 14.9.
class TutorReviewsSection extends StatefulWidget {
  final String tutorId;
  final String emptyText;
  const TutorReviewsSection({
    super.key,
    required this.tutorId,
    this.emptyText = 'Todavía no tiene calificaciones.',
  });

  @override
  State<TutorReviewsSection> createState() => _TutorReviewsSectionState();
}

class _TutorReviewsSectionState extends State<TutorReviewsSection> {
  static const int _preview = 5;
  bool _all = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ReviewStore>().loadForTutor(widget.tutorId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reviews = context.watch<ReviewStore>().forTutor(widget.tutorId);
    final shown = _all ? reviews : reviews.take(_preview).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          title: 'Reseñas',
          actionLabel: !_all && reviews.length > _preview ? 'Ver todas' : null,
          onAction: () => setState(() => _all = true),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (reviews.isEmpty)
          Text(widget.emptyText,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary))
        else
          for (final r in shown) ...[
            ReviewTile(review: r),
            const SizedBox(height: AppSpacing.sm),
          ],
      ],
    );
  }
}

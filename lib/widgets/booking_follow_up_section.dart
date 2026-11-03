import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/models/models.dart';
import '../routes/app_navigator.dart';
import '../state/booking_store.dart';
import '../state/follow_up_stores.dart';
import '../state/session_store.dart';
import '../state/tutor_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'follow_up_widgets.dart';
import 'primary_button.dart';
import 'secondary_button.dart';
import 'section_title.dart';

/// Seguimiento de una reserva aceptada (Fase 14.9), para el estudiante y para
/// el tutor: confirmaciones de las dos partes, incidencias y calificación.
///
/// Las pantallas solo deciden qué botones mostrar; las reglas las vuelve a
/// validar el repositorio (en Supabase, las funciones del servidor).
class BookingFollowUpSection extends StatefulWidget {
  final Booking booking;

  /// Papel de la cuenta con sesión en esta reserva.
  final BookingParty party;

  const BookingFollowUpSection({super.key, required this.booking, required this.party});

  static bool appliesTo(Booking b) =>
      b.estado == BookingStatus.aceptada ||
      b.estado == BookingStatus.pendienteConfirmacion ||
      b.estado == BookingStatus.completada;

  @override
  State<BookingFollowUpSection> createState() => _BookingFollowUpSectionState();
}

class _BookingFollowUpSectionState extends State<BookingFollowUpSection> {
  bool _working = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(BookingFollowUpSection old) {
    super.didUpdateWidget(old);
    if (old.booking.estado != widget.booking.estado) _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final id = widget.booking.id;
    final bookings = context.read<BookingStore>();
    final incidents = context.read<IncidentStore>();
    final reviews = context.read<ReviewStore>();
    await Future.wait([
      bookings.loadConfirmations(id),
      incidents.loadForBooking(id),
      if (widget.booking.estado == BookingStatus.completada) reviews.loadForBooking(id),
    ]);
  }

  Future<void> _confirm() async {
    if (_working || !await askConfirmSession(context) || !mounted) return;
    final store = context.read<BookingStore>();
    final actorId = context.read<SessionStore>().user?.id;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _working = true);
    final ok = await store.confirm(widget.booking.id, actorId: actorId);
    if (!mounted) return;
    setState(() => _working = false);
    final status = store.bookingById(widget.booking.id)?.estado;
    messenger.showSnackBar(SnackBar(
      content: Text(!ok
          ? (store.error ?? 'No se pudo confirmar la sesión.')
          : status == BookingStatus.completada
              ? 'Tutoría completada'
              : 'Confirmaste la sesión. Falta la otra parte.'),
    ));
  }

  Future<void> _report() async {
    final reported = await AppNavigator.toReportIncident(context, widget.booking.id);
    if (reported && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Incidencia enviada. La revisará tu universidad.')));
    }
  }

  Future<void> _review() async {
    if (_working) return;
    final input = await askReview(context);
    if (input == null || !mounted) return;
    final reviews = context.read<ReviewStore>();
    final tutors = context.read<TutorStore>();
    final actorId = context.read<SessionStore>().user?.id;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _working = true);
    final review = await reviews.submit(
        bookingId: widget.booking.id, rating: input.rating, comment: input.comment, actorId: actorId);
    if (!mounted) return;
    setState(() => _working = false);
    if (review != null) await tutors.refreshTutor(review.tutorId);
    messenger.showSnackBar(SnackBar(
      content: Text(review != null ? '¡Gracias por tu calificación!' : (reviews.error ?? 'No se pudo calificar.')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    if (!BookingFollowUpSection.appliesTo(b)) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    final userId = context.watch<SessionStore>().user?.id ?? '';
    final bookings = context.watch<BookingStore>();
    final incidentStore = context.watch<IncidentStore>();
    final reviewStore = context.watch<ReviewStore>();

    final party = widget.party;
    final incidents = incidentStore.forBooking(b.id);
    final hasOpen = incidentStore.hasOpen(b.id);
    final iConfirmed = bookings.hasConfirmed(b.id, party);
    final otherConfirmed = bookings.hasConfirmed(b.id, party.other);
    final ended = bookings.sessionEnded(b);
    final canConfirm = ended && !iConfirmed && !(otherConfirmed && hasOpen);
    final canReport = bookings.canReport(b) && !incidentStore.hasOpenBy(b.id, userId);
    final review = reviewStore.forBooking(b.id);
    final completed = b.estado == BookingStatus.completada;

    String confirmText(BookingParty p) {
      final done = bookings.hasConfirmed(b.id, p);
      final who = p == party ? 'Tú' : (p == BookingParty.tutor ? 'Tutor' : 'Estudiante');
      return '$who: ${done ? 'confirmó' : 'pendiente'}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.lg),
        const SectionTitle(title: 'Seguimiento'),
        const SizedBox(height: AppSpacing.sm),
        FollowUpCard(children: [
          Text('Confirmación de la sesión', style: textTheme.titleSmall),
          for (final p in [party, party.other])
            Row(children: [
              Icon(bookings.hasConfirmed(b.id, p) ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                  size: 18,
                  color: bookings.hasConfirmed(b.id, p) ? AppColors.success : AppColors.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Text(confirmText(p), style: textTheme.bodyMedium),
            ]),
          if (!ended && !completed)
            Text('Podrás confirmar cuando termine la sesión.',
                style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
          if (ended && !iConfirmed && otherConfirmed && hasOpen)
            Text('Hay una incidencia abierta; podrás confirmar cuando se resuelva.',
                style: textTheme.bodySmall?.copyWith(color: AppColors.warningDark)),
          if (canConfirm)
            PrimaryButton(
              key: const Key('confirm-session'),
              label: 'Confirmar que se realizó',
              icon: Icons.check_rounded,
              loading: _working,
              onPressed: _working ? null : _confirm,
            ),
        ]),
        if (incidents.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text('Incidencias', style: textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          for (final i in incidents) ...[
            IncidentTile(incident: i, mine: i.reportedBy == userId),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
        if (canReport) ...[
          const SizedBox(height: AppSpacing.sm),
          SecondaryButton(
            key: const Key('report-incident'),
            label: 'Reportar un problema',
            icon: Icons.report_gmailerrorred_rounded,
            onPressed: _report,
          ),
        ],
        if (completed) ...[
          const SizedBox(height: AppSpacing.md),
          if (review != null)
            ReviewTile(
                review: review,
                title: party == BookingParty.estudiante ? 'Tu calificación' : 'Calificación recibida')
          else if (party == BookingParty.estudiante && hasOpen)
            Text('Hay una incidencia abierta; podrás calificar cuando se resuelva.',
                style: textTheme.bodySmall?.copyWith(color: AppColors.warningDark))
          else if (party == BookingParty.estudiante && reviewStore.loadedForBooking(b.id))
            PrimaryButton(
              key: const Key('rate-tutor'),
              label: 'Calificar al tutor',
              icon: Icons.star_outline_rounded,
              loading: _working,
              onPressed: _working ? null : _review,
            )
          else if (party == BookingParty.tutor && reviewStore.loadedForBooking(b.id))
            Text('El estudiante todavía no califica esta tutoría.',
                style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
        ],
      ],
    );
  }
}

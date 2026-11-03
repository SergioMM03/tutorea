import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/models/models.dart';
import '../routes/app_navigator.dart';
import '../state/booking_store.dart';
import '../state/tutor_actions.dart';
import '../state/tutor_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/form_error_banner.dart';
import '../widgets/tutor_bottom_nav.dart';
import '../widgets/tutor_request_card.dart';

/// Solicitudes recibidas por el tutor en cuatro pestañas:
/// Pendientes, Aceptadas, Rechazadas (por el tutor) y Canceladas (por el estudiante).
class TutorRequestsScreen extends StatefulWidget {
  const TutorRequestsScreen({super.key});

  @override
  State<TutorRequestsScreen> createState() => _TutorRequestsScreenState();
}

class _TutorRequestsScreenState extends State<TutorRequestsScreen>
    with TutorWorkspaceLoader<TutorRequestsScreen> {
  @override
  Widget build(BuildContext context) {
    ensureTutorWorkspace();
    final textTheme = Theme.of(context).textTheme;
    final bookings = context.watch<BookingStore>();
    final tutors = context.watch<TutorStore>();

    final pending = bookings.tutorRequestsWith(BookingStatus.pendiente);
    // Aceptadas incluye las que esperan confirmación y las completadas.
    final accepted = bookings.tutorRequestsIn(const {
      BookingStatus.aceptada,
      BookingStatus.pendienteConfirmacion,
      BookingStatus.completada,
    });
    final rejected = bookings.tutorRequestsWith(BookingStatus.rechazada);
    final cancelled = bookings.tutorRequestsWith(BookingStatus.cancelada);

    final loading = !tutorWorkspaceReady && bookings.tutorRequests.isEmpty;
    final error = bookings.tutorRequests.isEmpty ? (tutors.error ?? bookings.error) : null;

    Widget body;
    if (loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (error != null) {
      body = Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: FormErrorBanner(message: error),
      );
    } else {
      body = TabBarView(
        children: [
          _RequestList(
            bookings: pending,
            emptyText: 'No tienes solicitudes pendientes.',
          ),
          _RequestList(
            bookings: accepted,
            emptyText: 'Aún no has aceptado solicitudes.',
          ),
          _RequestList(
            bookings: rejected,
            emptyText: 'No hay solicitudes rechazadas.',
          ),
          _RequestList(
            bookings: cancelled,
            emptyText: 'Ningún estudiante ha cancelado solicitudes.',
          ),
        ],
      );
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Solicitudes'),
          automaticallyImplyLeading: false,
          bottom: TabBar(
            // 4 pestañas: se desplazan si no caben en pantallas angostas.
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: AppColors.border,
            labelStyle: textTheme.titleMedium,
            unselectedLabelStyle: textTheme.titleMedium,
            tabs: [
              Tab(text: 'Pendientes (${pending.length})'),
              Tab(text: 'Aceptadas (${accepted.length})'),
              Tab(text: 'Rechazadas (${rejected.length})'),
              Tab(text: 'Canceladas (${cancelled.length})'),
            ],
          ),
        ),
        body: body,
        bottomNavigationBar: const TutorBottomNav(current: TutorTab.requests),
      ),
    );
  }
}

/// Lista de tarjetas, o un texto si está vacía.
class _RequestList extends StatelessWidget {
  final List<Booking> bookings;
  final String emptyText;

  const _RequestList({required this.bookings, required this.emptyText});

  @override
  Widget build(BuildContext context) {
    if (bookings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(
            emptyText,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppLayout.maxContentWidth),
        child: ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          itemCount: bookings.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (_, i) => TutorRequestCard(
            booking: bookings[i],
            onTap: () => AppNavigator.toTutorRequestDetail(context, bookings[i].id),
          ),
        ),
      ),
    );
  }
}

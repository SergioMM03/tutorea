import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/models/models.dart';
import '../routes/app_navigator.dart';
import '../state/booking_actions.dart';
import '../state/booking_store.dart';
import '../state/session_store.dart';
import '../state/tutor_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/booking_status_badge.dart';
import '../widgets/secondary_button.dart';
import '../widgets/tutor_avatar.dart';

/// Mis reservas: solicitudes del estudiante en dos pestañas,
/// "Próximas" (pendientes y aceptadas) e "Historial" (rechazadas y canceladas).
/// Lee de [BookingStore]; nombres de tutor y materia salen de [TutorStore].
class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  String? _loadedFor;

  /// Carga reservas y tutores una vez por usuario, después del primer cuadro
  /// (también si la sesión guardada termina de cargar más tarde).
  void _ensureLoaded(SessionStore session) {
    final user = session.user;
    if (user == null || user.id == _loadedFor) return;
    _loadedFor = user.id;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final bookings = context.read<BookingStore>();
      final tutors = context.read<TutorStore>();
      await bookings.loadForStudent(user.id);
      if (tutors.subjects.isEmpty || tutors.universityId != user.universityId) {
        await tutors.loadForUniversity(user.universityId);
      }
      // Nombres de los tutores de cada reserva, aunque haya filtros en Inicio.
      await tutors.loadTutors(bookings.studentBookings.map((b) => b.tutorId));
    });
  }

  @override
  Widget build(BuildContext context) {
    _ensureLoaded(context.watch<SessionStore>());
    final textTheme = Theme.of(context).textTheme;
    final store = context.watch<BookingStore>();
    final tutorStore = context.watch<TutorStore>();

    Widget body;
    if (store.isLoading && store.studentBookings.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (store.error != null && store.studentBookings.isEmpty) {
      body = _EmptyBookings(
        title: 'No se pudieron cargar tus reservas',
        message: store.error!,
      );
    } else {
      body = TabBarView(
        children: [
          _BookingList(
            bookings: store.studentUpcoming,
            tutors: tutorStore,
            empty: _EmptyBookings(
              title: 'Aún no tienes reservas',
              message: 'Busca un tutor y envía tu primera solicitud.',
              onSearch: () => AppNavigator.toHome(context),
            ),
          ),
          _BookingList(
            bookings: store.studentHistory,
            tutors: tutorStore,
            empty: const _EmptyBookings(
              title: 'Sin tutorías anteriores',
              message: 'Aquí verás tus solicitudes rechazadas o canceladas.',
            ),
          ),
        ],
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mis reservas'),
          automaticallyImplyLeading: false,
          bottom: TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: AppColors.border,
            labelStyle: textTheme.titleMedium,
            unselectedLabelStyle: textTheme.titleMedium,
            tabs: const [Tab(text: 'Próximas'), Tab(text: 'Historial')],
          ),
        ),
        body: body,
        bottomNavigationBar: const AppBottomNav(current: AppTab.myBookings),
      ),
    );
  }
}

/// Lista de tarjetas, o el estado vacío si no hay reservas.
class _BookingList extends StatelessWidget {
  final List<Booking> bookings;
  final TutorStore tutors;
  final Widget empty;

  const _BookingList({required this.bookings, required this.tutors, required this.empty});

  @override
  Widget build(BuildContext context) {
    if (bookings.isEmpty) return empty;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppLayout.maxContentWidth),
        child: ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          itemCount: bookings.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (_, i) {
            final booking = bookings[i];
            final tutor = tutors.cachedTutor(booking.tutorId);
            final subject = [...?tutor?.subjects, ...tutors.subjects]
                .where((s) => s.id == booking.subjectId)
                .firstOrNull;
            return _BookingCard(
              booking: booking,
              tutorName: tutor?.nombre ?? 'Tutor',
              tutorPhotoPath: tutor?.profile.photoPath,
              subjectName: subject?.nombre ?? booking.subjectId,
            );
          },
        ),
      ),
    );
  }
}

/// Tarjeta de una reserva: tutor, materia, fecha, hora y estado.
class _BookingCard extends StatelessWidget {
  final Booking booking;
  final String tutorName;
  final String? tutorPhotoPath; // fotografía del tutor, si eligió una
  final String subjectName;

  const _BookingCard({
    required this.booking,
    required this.tutorName,
    this.tutorPhotoPath,
    required this.subjectName,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final start = booking.fechaHora;
    final end = booking.fin;
    final hora = '${Formatters.time(start.hour * 60 + start.minute)} – '
        '${Formatters.time(end.hour * 60 + end.minute)}';

    final radius = BorderRadius.circular(AppRadius.card);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: radius,
        boxShadow: AppShadows.card,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          // Toda la tarjeta abre el detalle de la reserva.
          onTap: () => AppNavigator.toStudentBookingDetail(context, booking.id),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TutorAvatar(
                      name: tutorName,
                      photoPath: tutorPhotoPath,
                      size: 56,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tutor', style: textTheme.bodySmall),
                          Text(
                            tutorName,
                            style: textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    BookingStatusBadge(status: booking.estado),
                  ],
                ),
                const Divider(height: AppSpacing.lg),
                _InfoRow(
                  icon: Icons.menu_book_outlined,
                  label: 'Materia',
                  value: subjectName,
                ),
                const SizedBox(height: AppSpacing.sm),
                _InfoRow(
                  icon: Icons.calendar_today_outlined,
                  label: 'Fecha',
                  value: Formatters.dateLong(start),
                ),
                const SizedBox(height: AppSpacing.sm),
                _InfoRow(
                  icon: Icons.access_time_rounded,
                  label: 'Hora',
                  value: hora,
                ),
                // Solo una solicitud pendiente se puede cancelar.
                if (booking.estado == BookingStatus.pendiente) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: AppColors.error),
                      onPressed: () => confirmAndCancelBooking(context, booking),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Cancelar solicitud'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fila "ícono · etiqueta · valor" dentro de la tarjeta.
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// Estado vacío de una pestaña.
class _EmptyBookings extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onSearch;

  const _EmptyBookings({required this.title, required this.message, this.onSearch});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.maxNarrowWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.event_note_outlined,
                    size: 40, color: AppColors.primary),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(title, textAlign: TextAlign.center, style: textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary),
              ),
              if (onSearch != null) ...[
                const SizedBox(height: AppSpacing.lg),
                SecondaryButton(label: 'Buscar tutores', onPressed: onSearch),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

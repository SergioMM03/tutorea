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
import '../utils/formatters.dart';
import '../widgets/app_back_button.dart';

/// Notificaciones de la cuenta (Fase 14.9). Las crea el sistema; aquí solo se
/// leen y se marcan como leídas. Tocar una abre la reserva relacionada.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final userId = context.read<SessionStore>().user?.id;
    if (userId == null) return;
    final notifications = context.read<NotificationStore>();
    final bookings = context.read<BookingStore>();
    final tutors = context.read<TutorStore>();
    await notifications.load(userId);
    // Las reservas relacionadas, para poder abrirlas (en sus dos papeles).
    await bookings.loadForStudent(userId);
    if (tutors.myProfile == null) await tutors.loadMyProfile(userId);
    final profile = tutors.myProfile;
    if (profile != null) await bookings.loadForTutor(profile.id);
  }

  Future<void> _open(AppNotification n) async {
    final notifications = context.read<NotificationStore>();
    final bookings = context.read<BookingStore>();
    await notifications.markRead(n.id);
    if (!mounted) return;
    final bookingId = n.bookingId;
    if (bookingId == null) return;
    if (bookings.studentBookingById(bookingId) != null) {
      AppNavigator.toStudentBookingDetail(context, bookingId);
    } else if (bookings.tutorRequests.any((b) => b.id == bookingId)) {
      AppNavigator.toTutorRequestDetail(context, bookingId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final store = context.watch<NotificationStore>();
    final items = store.items;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        leading: const AppBackButton(),
        actions: [
          if (store.hasUnread)
            TextButton(
              key: const Key('mark-all-read'),
              onPressed: store.isLoading ? null : store.markAllRead,
              child: const Text('Marcar todas'),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.maxContentWidth),
          child: RefreshIndicator(
            onRefresh: _load,
            child: items.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(AppSpacing.screenPadding),
                    children: [
                      const SizedBox(height: AppSpacing.xl),
                      if (store.isLoading)
                        const Center(child: CircularProgressIndicator())
                      else ...[
                        const Icon(Icons.notifications_none_rounded, size: 48, color: AppColors.textSecondary),
                        const SizedBox(height: AppSpacing.md),
                        Text('No tienes notificaciones.',
                            textAlign: TextAlign.center,
                            style: textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary)),
                      ],
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.screenPadding),
                    itemCount: items.length,
                    separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) => _NotificationTile(
                      notification: items[i],
                      onTap: () => _open(items[i]),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;
  const _NotificationTile({required this.notification, required this.onTap});

  static IconData _icon(NotificationType t) => switch (t) {
        NotificationType.reservaSolicitada => Icons.mark_email_unread_outlined,
        NotificationType.reservaAceptada => Icons.event_available_rounded,
        NotificationType.reservaRechazada => Icons.event_busy_rounded,
        NotificationType.reservaCancelada => Icons.cancel_outlined,
        NotificationType.confirmacionPendiente => Icons.fact_check_outlined,
        NotificationType.reservaCompletada => Icons.verified_outlined,
        NotificationType.incidenciaReportada => Icons.report_gmailerrorred_rounded,
        NotificationType.incidenciaActualizada => Icons.update_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final n = notification;
    final d = n.createdAt;
    final when = '${Formatters.dateLong(d)} · ${Formatters.time(d.hour * 60 + d.minute)}';
    return Material(
      color: n.leida ? AppColors.surface : AppColors.primaryLight,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: n.leida ? AppColors.border : AppColors.primarySoft),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: n.leida ? AppColors.primaryLight : AppColors.surface,
                child: Icon(_icon(n.type), color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.type.title,
                        style: textTheme.titleSmall
                            ?.copyWith(fontWeight: n.leida ? FontWeight.w500 : FontWeight.w700)),
                    const SizedBox(height: AppSpacing.xs),
                    Text(when, style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              if (!n.leida)
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

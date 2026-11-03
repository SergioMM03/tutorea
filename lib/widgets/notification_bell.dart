import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../routes/app_navigator.dart';
import '../state/follow_up_stores.dart';
import '../state/session_store.dart';
import '../theme/app_colors.dart';

/// Campana de notificaciones con indicador de no leídas (Fase 14.9).
/// Carga las notificaciones de la cuenta con sesión al aparecer (consulta
/// inicial); en Supabase, Realtime las mantiene al día.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  String? _loadedFor;

  void _ensureLoaded(String? userId) {
    if (userId == null || userId == _loadedFor) return;
    _loadedFor = userId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<NotificationStore>().load(userId);
    });
  }

  @override
  Widget build(BuildContext context) {
    _ensureLoaded(context.watch<SessionStore>().user?.id);
    final unread = context.watch<NotificationStore>().unreadCount;
    return IconButton(
      key: const Key('notification-bell'),
      tooltip: unread == 0 ? 'Notificaciones' : 'Notificaciones: $unread sin leer',
      onPressed: () => AppNavigator.toNotifications(context),
      icon: Badge(
        isLabelVisible: unread > 0,
        backgroundColor: AppColors.primary,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: const Icon(Icons.notifications_none_rounded, size: 28, color: AppColors.textPrimary),
      ),
    );
  }
}

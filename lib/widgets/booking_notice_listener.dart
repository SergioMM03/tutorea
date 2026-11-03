import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/booking_store.dart';

/// Muestra en un SnackBar los avisos de BookingStore: cambios que hizo la otra
/// parte de una reserva (Supabase Realtime): solicitud nueva, aceptada,
/// rechazada o cancelada. No guarda nada: las notificaciones con historial son
/// de una fase posterior.
class BookingNoticeListener extends StatefulWidget {
  final Widget child;
  const BookingNoticeListener({super.key, required this.child});

  @override
  State<BookingNoticeListener> createState() => _BookingNoticeListenerState();
}

class _BookingNoticeListenerState extends State<BookingNoticeListener> {
  int _shown = 0;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<BookingStore>();
    final message = store.notice;
    if (message != null && store.noticeSerial != _shown) {
      _shown = store.noticeSerial;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        store.clearNotice();
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
      });
    }
    return widget.child;
  }
}

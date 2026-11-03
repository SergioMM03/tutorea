/// Capacidad opcional de un [BookingRepository]: avisa cuando cambian las
/// reservas en el servidor (otra cuenta solicitó, aceptó, rechazó o canceló).
///
/// RemoteBookingRepository la implementa con Supabase Realtime (respeta RLS:
/// cada cuenta solo recibe cambios de sus reservas). LocalBookingRepository no:
/// en el dispositivo nada cambia fuera de la app. BookingStore se suscribe
/// solo si el repositorio la tiene y vuelve a leer las listas.
abstract class BookingChanges {
  /// Emite un evento por cada cambio recibido.
  Stream<void> get bookingChanges;
}

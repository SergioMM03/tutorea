import '../models/models.dart';

/// Reseñas del estudiante al tutor (Fase 14.9).
///
/// Implementaciones: LocalReviewRepository y RemoteReviewRepository (tabla
/// reviews, vista public_reviews y función submit_review, migración 22).
/// El promedio y el total del tutor los calcula el servidor (o el repositorio
/// local) a partir de las reseñas; la app nunca los escribe.
abstract class ReviewRepository {
  /// Califica al tutor de una reserva completada (1 a 5 estrellas), una sola vez.
  /// [actorId]: cuenta que califica (Supabase usa la sesión: auth.uid()).
  Future<Review> submit({
    required String bookingId,
    required int rating,
    String? comment,
    String? actorId,
  });

  /// Reseñas públicas de un tutor (sin estudiante ni reserva), la más reciente primero.
  Future<List<Review>> getForTutor(String tutorId);

  /// Reseña de una reserva (la propia o la recibida), o null.
  Future<Review?> getForBooking(String bookingId);
}

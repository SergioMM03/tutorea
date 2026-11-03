/// Reseña del estudiante al tutor de una reserva completada (1 a 5 estrellas).
/// No se edita ni se borra en el MVP.
///
/// En el perfil público del tutor llega sin [studentId] ni [bookingId]
/// (vista public_reviews): no se expone quién calificó.
class Review {
  final String id;
  final String tutorId; // TutorProfile.id
  final int rating; // 1 – 5
  final String? comment;
  final DateTime createdAt;

  /// Solo en las reseñas propias o recibidas (no en el perfil público).
  final String? bookingId;
  final String? studentId;

  const Review({
    required this.id,
    required this.tutorId,
    required this.rating,
    this.comment,
    required this.createdAt,
    this.bookingId,
    this.studentId,
  });

  /// Versión para el perfil público: sin estudiante ni reserva.
  Review get public => Review(id: id, tutorId: tutorId, rating: rating, comment: comment, createdAt: createdAt);

  factory Review.fromJson(Map<String, dynamic> json) => Review(
        id: json['id'] as String,
        tutorId: json['tutorId'] as String,
        rating: (json['rating'] as num).toInt(),
        comment: json['comment'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        bookingId: json['bookingId'] as String?,
        studentId: json['studentId'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tutorId': tutorId,
        'rating': rating,
        if (comment != null) 'comment': comment,
        'createdAt': createdAt.toIso8601String(),
        if (bookingId != null) 'bookingId': bookingId,
        if (studentId != null) 'studentId': studentId,
      };
}

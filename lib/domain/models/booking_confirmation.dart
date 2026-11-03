import 'booking_party.dart';

/// Confirmación de que una sesión se realizó, de una de las partes.
/// Historial: no se modifica ni se borra (tabla booking_confirmations,
/// migración 19).
class BookingConfirmation {
  final String bookingId;
  final BookingParty party;
  final String userId;
  final DateTime confirmedAt; // hora de pared de El Salvador

  const BookingConfirmation({
    required this.bookingId,
    required this.party,
    required this.userId,
    required this.confirmedAt,
  });

  factory BookingConfirmation.fromJson(Map<String, dynamic> json) => BookingConfirmation(
        bookingId: json['bookingId'] as String,
        party: BookingParty.fromJson(json['party'] as String),
        userId: json['userId'] as String,
        confirmedAt: DateTime.parse(json['confirmedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'bookingId': bookingId,
        'party': party.name,
        'userId': userId,
        'confirmedAt': confirmedAt.toIso8601String(),
      };
}

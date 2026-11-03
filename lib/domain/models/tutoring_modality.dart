/// Modalidad de una tutoría (igual que el enum booking_modality de la base).
enum TutoringModality {
  presencial,
  virtual;

  String get label => switch (this) {
        TutoringModality.presencial => 'Presencial',
        TutoringModality.virtual => 'Virtual',
      };
}

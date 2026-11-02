/// Error de negocio con un mensaje listo para mostrar al usuario.
/// Las implementaciones (local o Firebase) lanzan este mismo tipo.
class RepositoryException implements Exception {
  final String message;
  const RepositoryException(this.message);

  @override
  String toString() => message;
}

/// Inicio de sesión con una cuenta de otra universidad distinta a la
/// seleccionada. La UI ofrece volver a elegir la universidad.
class UniversityMismatchException extends RepositoryException {
  const UniversityMismatchException()
      : super('Esta cuenta pertenece a otra universidad. '
            'Vuelve a seleccionar tu universidad para iniciar sesión.');
}

import 'package:flutter/material.dart';

import '../routes/app_navigator.dart';
import '../widgets/primary_button.dart';
import '../widgets/screen_placeholder.dart';

/// Se muestra si se navega a una ruta inexistente o sin sus argumentos.
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenPlaceholder(
      title: 'Página no encontrada',
      description: 'La pantalla solicitada no existe o le faltan datos.',
      actions: [
        PrimaryButton(
          label: 'Volver al inicio',
          onPressed: () => AppNavigator.toHome(context),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../routes/app_navigator.dart';

/// Barra inferior del tutor: Inicio, Solicitudes, Mi perfil.
/// Mismo estilo que la del estudiante (`bottomNavigationBarTheme`).
class TutorBottomNav extends StatelessWidget {
  final TutorTab current;

  const TutorBottomNav({super.key, required this.current});

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: current.index,
      onTap: (i) {
        final tab = TutorTab.values[i];
        if (tab != current) AppNavigator.toTutorTab(context, tab);
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home_rounded),
          label: 'Inicio',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.inbox_outlined),
          activeIcon: Icon(Icons.inbox_rounded),
          label: 'Solicitudes',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outline_rounded),
          activeIcon: Icon(Icons.person_rounded),
          label: 'Mi perfil',
        ),
      ],
    );
  }
}

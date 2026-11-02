import 'package:flutter/material.dart';

import '../routes/app_navigator.dart';

/// Barra inferior del estudiante: Inicio, Mis reservas, Perfil.
/// El estilo viene de `bottomNavigationBarTheme` en app_theme.dart.
class AppBottomNav extends StatelessWidget {
  final AppTab current;

  const AppBottomNav({super.key, required this.current});

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: current.index,
      onTap: (i) {
        final tab = AppTab.values[i];
        if (tab != current) AppNavigator.toTab(context, tab);
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home_rounded),
          label: 'Inicio',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.calendar_today_outlined),
          activeIcon: Icon(Icons.calendar_today_rounded),
          label: 'Mis reservas',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outline_rounded),
          activeIcon: Icon(Icons.person_rounded),
          label: 'Perfil',
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../routes/app_navigator.dart';
import '../state/session_actions.dart';
import '../state/session_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/secondary_button.dart';
import '../widgets/section_title.dart';
import '../widgets/tutor_avatar.dart';

/// Perfil del estudiante que inició sesión (datos de SessionStore).
class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  String? _loadedFor;

  /// Carga el nombre de la universidad del usuario (una vez por usuario;
  /// también cuando la sesión guardada termina de cargar al abrir la app).
  void _ensureUniversityName(SessionStore session) {
    final user = session.user;
    if (user == null || user.id == _loadedFor) return;
    _loadedFor = user.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SessionStore>().loadUsers([user.id]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final session = context.watch<SessionStore>();
    _ensureUniversityName(session);
    final user = session.user;
    final name = user?.nombre ?? '';
    final university = user == null ? '' : session.universityName(user.universityId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.maxContentWidth),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            children: [
              Center(child: TutorAvatar(name: name, size: 96)),
              const SizedBox(height: AppSpacing.md),
              Text(name, textAlign: TextAlign.center, style: textTheme.headlineMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                user?.correo ?? '',
                textAlign: TextAlign.center,
                style: textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              const SectionTitle(title: 'Información académica'),
              const SizedBox(height: AppSpacing.sm),
              _InfoCard(
                rows: [
                  ('Universidad', university),
                  ('Carrera', user?.carrera ?? ''),
                  ('Año académico', user == null ? '' : '${user.anioAcademico}.º año'),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              _MenuTile(
                icon: Icons.edit_outlined,
                label: 'Editar perfil',
                onTap: () => AppNavigator.toEditStudentProfile(context),
              ),
              const SizedBox(height: AppSpacing.sm),
              _MenuTile(
                icon: Icons.calendar_today_outlined,
                label: 'Mis reservas',
                onTap: () => AppNavigator.toMyBookings(context),
              ),
              const SizedBox(height: AppSpacing.xl),
              SecondaryButton(
                label: 'Cerrar sesión',
                onPressed: () => signOutUser(context),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.profile),
    );
  }
}

/// Tarjeta con pares etiqueta / valor.
class _InfoCard extends StatelessWidget {
  final List<(String, String)> rows;
  const _InfoCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Row(
                children: [
                  // Flexible: la etiqueta pasa a dos líneas si no cabe.
                  Flexible(
                    child: Text(rows[i].$1,
                        style: textTheme.bodyLarge
                            ?.copyWith(color: AppColors.textSecondary)),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(rows[i].$2,
                        textAlign: TextAlign.end, style: textTheme.titleMedium),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Opción de menú con ícono y flecha.
class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.card);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: radius,
        boxShadow: AppShadows.card,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: radius),
          leading: Icon(icon, color: AppColors.primary),
          title: Text(label, style: Theme.of(context).textTheme.titleMedium),
          trailing: const Icon(Icons.chevron_right_rounded,
              color: AppColors.textSecondary),
          onTap: onTap,
        ),
      ),
    );
  }
}

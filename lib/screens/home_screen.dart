import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../routes/app_navigator.dart';
import '../state/session_store.dart';
import '../state/tutor_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_logo.dart';
import '../widgets/notification_bell.dart';
import '../widgets/section_title.dart';
import '../widgets/subject_chip.dart';
import '../widgets/tutor_card.dart';

/// 2. Inicio del estudiante (MVP).
/// Tutores reales de la universidad del usuario, vía TutorStore.
/// Los chips de categoría filtran de verdad; el buscador abre la Búsqueda.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _allLabel = 'Todas';

  String? _loadedFor;

  /// Carga los tutores de la universidad del usuario una vez que se conoce
  /// (al reabrir la app la sesión guardada llega después del primer cuadro).
  /// Sin usuario no se carga nada: así nunca se mezclan otras universidades.
  void _ensureLoaded(String? userId) {
    if (userId == null || userId == _loadedFor) return;
    _loadedFor = userId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() {
    if (!mounted) return Future.value();
    final universityId = context.read<SessionStore>().user?.universityId;
    if (universityId == null) return Future.value();
    // Su propio perfil de tutor no aparece para reservar.
    final viewerId = context.read<SessionStore>().user?.id;
    return context.read<TutorStore>().loadForUniversity(universityId, viewerId: viewerId);
  }

  void _selectFilter(String label) {
    context.read<TutorStore>().filterByCategory(label == _allLabel ? null : label);
  }

  void _openSearch() => AppNavigator.toSearch(context);

  void _openTutor(TutorSummary tutor) => AppNavigator.toTutorProfile(context, tutor);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final user = context.watch<SessionStore>().user;
    _ensureLoaded(user?.id);
    final tutorStore = context.watch<TutorStore>();

    final firstName = (user?.nombre ?? '').trim().split(' ').first;
    final filters = [_allLabel, ...tutorStore.categories];
    final selectedFilter = tutorStore.categoryFilter ?? _allLabel;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // En tablets el contenido se centra con un ancho máximo.
            final hPad = math.max(
              AppSpacing.screenPadding,
              (constraints.maxWidth - AppLayout.maxContentWidth) / 2 +
                  AppSpacing.screenPadding,
            );

            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(hPad, AppSpacing.sm, hPad, 0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _HomeHeader(onSearch: _openSearch),
                      const SizedBox(height: AppSpacing.lg),
                      Text(firstName.isEmpty ? 'Hola' : 'Hola, $firstName',
                          style: textTheme.headlineLarge),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '¿En qué materia necesitas apoyo?',
                        style: textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _SearchField(onTap: _openSearch),
                      const SizedBox(height: AppSpacing.md),
                    ]),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _FilterChips(
                    filters: filters,
                    selected: selectedFilter,
                    horizontalPadding: hPad,
                    onSelected: _selectFilter,
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                      hPad, AppSpacing.lg, hPad, AppSpacing.md),
                  sliver: const SliverToBoxAdapter(
                    child: SectionTitle(title: 'Tutores recomendados'),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(hPad, 0, hPad, AppSpacing.lg),
                  sliver: _RecommendedTutors(
                    store: tutorStore,
                    onTutorTap: _openTutor,
                    onRetry: _load,
                  ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.home),
    );
  }
}

/// Logo pequeño a la izquierda; notificaciones (Fase 14.9) y búsqueda a la derecha.
class _HomeHeader extends StatelessWidget {
  final VoidCallback onSearch;

  const _HomeHeader({required this.onSearch});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const AppLogo(size: 36, direction: Axis.horizontal),
        const Spacer(),
        const NotificationBell(),
        // El IconButton tiene relleno interno; se corre a la derecha para
        // que el borde del ícono quede alineado con el contenido (20 px).
        Transform.translate(
          offset: const Offset(AppSpacing.sm, 0),
          child: IconButton(
            onPressed: onSearch,
            tooltip: 'Buscar',
            icon: const Icon(Icons.search, size: 28, color: AppColors.textPrimary),
          ),
        ),
      ],
    );
  }
}

/// Buscador de solo lectura: al tocarlo abre la pantalla de búsqueda.
class _SearchField extends StatelessWidget {
  final VoidCallback onTap;
  const _SearchField({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextField(
      readOnly: true,
      onTap: onTap,
      decoration: const InputDecoration(
        hintText: 'Buscar materia, tema o tutor...',
        prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
      ),
    );
  }
}

/// Fila horizontal de filtros (Todas, Matemáticas, Economía, Negocios).
/// Sin alto fijo: se adapta si el usuario agranda el texto del sistema.
class _FilterChips extends StatelessWidget {
  final List<String> filters;
  final String selected;
  final double horizontalPadding;
  final ValueChanged<String> onSelected;

  const _FilterChips({
    required this.filters,
    required this.selected,
    required this.horizontalPadding,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Row(
        children: [
          for (var i = 0; i < filters.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            SubjectChip(
              label: filters[i],
              selected: filters[i] == selected,
              onTap: () => onSelected(filters[i]),
            ),
          ],
        ],
      ),
    );
  }
}

/// Lista de tutores con estados de carga, error y vacío.
class _RecommendedTutors extends StatelessWidget {
  final TutorStore store;
  final ValueChanged<TutorSummary> onTutorTap;
  final VoidCallback onRetry;

  const _RecommendedTutors({
    required this.store,
    required this.onTutorTap,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final tutors = store.availableTutors;

    // Primera carga (o cambio de filtro sin resultados previos).
    if (store.isLoading && tutors.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (store.error != null) {
      return SliverToBoxAdapter(
        child: _Message(
          icon: Icons.cloud_off_rounded,
          text: store.error!,
          actionLabel: 'Reintentar',
          onAction: onRetry,
        ),
      );
    }

    if (tutors.isEmpty) {
      return SliverToBoxAdapter(
        child: _Message(
          icon: Icons.person_search_rounded,
          text: store.categoryFilter == null
              ? 'Aún no hay tutores disponibles en tu universidad.'
              : 'No hay tutores de ${store.categoryFilter} por ahora.',
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          final tutor = tutors[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: TutorCard(
              tutor: tutor,
              onTap: () => onTutorTap(tutor),
            ),
          );
        },
        childCount: tutors.length,
      ),
    );
  }
}

/// Mensaje centrado con ícono y acción opcional (error o lista vacía).
class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _Message({required this.icon, required this.text, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppColors.textSecondary),
          const SizedBox(height: AppSpacing.sm),
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: AppColors.textSecondary),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../routes/app_navigator.dart';
import '../routes/routes.dart';
import '../state/session_store.dart';
import '../state/tutor_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_back_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/subject_chip.dart';
import '../widgets/tutor_card.dart';

/// 3. Búsqueda de tutores de la universidad del estudiante.
/// - Texto: nombre del tutor o materia que imparte (se actualiza al escribir).
/// - Filtros: categoría de materia y carrera (solo las que existen en los datos).
/// Todo se combina y se guarda en TutorStore, así al volver no se pierde.
class TutorSearchScreen extends StatefulWidget {
  final SearchArgs args;
  const TutorSearchScreen({super.key, required this.args});

  @override
  State<TutorSearchScreen> createState() => _TutorSearchScreenState();
}

class _TutorSearchScreenState extends State<TutorSearchScreen> {
  static const String _allLabel = 'Todas';

  late final TextEditingController _controller;
  String? _loadedFor;

  @override
  void initState() {
    super.initState();
    final store = context.read<TutorStore>();
    final initial = widget.args.initialQuery.trim();
    _controller = TextEditingController(text: initial.isEmpty ? store.query : initial);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (initial.isNotEmpty) store.search(initial);
      if (widget.args.category != null) store.filterByCategory(widget.args.category);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Carga los tutores de la universidad del usuario (una vez por usuario).
  void _ensureLoaded(String? userId) {
    if (userId == null || userId == _loadedFor) return;
    _loadedFor = userId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() {
    if (!mounted) return Future.value();
    final universityId = context.read<SessionStore>().user?.universityId;
    if (universityId == null) return Future.value();
    return context.read<TutorStore>().loadForUniversity(universityId);
  }

  Future<void> _clearAll() {
    _controller.clear();
    return context.read<TutorStore>().clearSearch();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    _ensureLoaded(context.watch<SessionStore>().user?.id);
    final store = context.watch<TutorStore>();
    final results = store.searchResults;
    final careers = store.careers;

    Widget resultsView;
    if (store.isLoading && store.availableTutors.isEmpty) {
      resultsView = const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (store.error != null) {
      resultsView = _Message(
        icon: Icons.cloud_off_rounded,
        text: store.error!,
        action: TextButton(onPressed: _load, child: const Text('Reintentar')),
      );
    } else if (results.isEmpty) {
      resultsView = _Message(
        icon: Icons.person_search_rounded,
        text: store.hasSearchOrFilters
            ? 'No encontramos tutores con esa búsqueda.'
            : 'Aún no hay tutores disponibles en tu universidad.',
        action: store.hasSearchOrFilters
            ? SecondaryButton(
                label: 'Limpiar búsqueda y filtros',
                expanded: false,
                onPressed: _clearAll,
              )
            : null,
      );
    } else {
      resultsView = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            results.length == 1 ? '1 tutor' : '${results.length} tutores',
            style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final tutor in results) ...[
            TutorCard(
              tutor: tutor,
              onTap: () => AppNavigator.toTutorProfile(context, tutor),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Buscar tutores'),
        leading: const AppBackButton(),
        actions: [
          if (store.hasSearchOrFilters)
            TextButton(onPressed: _clearAll, child: const Text('Limpiar')),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.maxContentWidth),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            children: [
              TextField(
                key: const Key('tutor-search-field'),
                controller: _controller,
                autofocus: widget.args.initialQuery.isEmpty,
                textInputAction: TextInputAction.search,
                onChanged: store.search,
                decoration: InputDecoration(
                  hintText: 'Buscar por tutor o materia...',
                  prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                  suffixIcon: store.query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Borrar texto',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _controller.clear();
                            store.search('');
                          },
                        ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Categoría', style: textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              _ChipRow(
                options: [(null, _allLabel), for (final c in store.categories) (c, c)],
                selected: store.categoryFilter,
                onSelected: store.filterByCategory,
              ),
              if (careers.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text('Carrera', style: textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                _ChipRow(
                  options: [(null, _allLabel), for (final c in careers) (c.id, c.nombre)],
                  selected: store.careerFilter,
                  onSelected: store.filterByCareer,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              resultsView,
            ],
          ),
        ),
      ),
    );
  }
}

/// Fila desplazable de chips: (valor, etiqueta). Valor null = "Todas".
class _ChipRow extends StatelessWidget {
  final List<(String?, String)> options;
  final String? selected;
  final ValueChanged<String?> onSelected;

  const _ChipRow({required this.options, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            SubjectChip(
              label: options[i].$2,
              selected: options[i].$1 == selected,
              onTap: () => onSelected(options[i].$1),
            ),
          ],
        ],
      ),
    );
  }
}

/// Mensaje centrado con ícono y acción opcional (error o sin resultados).
class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;

  const _Message({required this.icon, required this.text, this.action});

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
          if (action != null) ...[
            const SizedBox(height: AppSpacing.md),
            action!,
          ],
        ],
      ),
    );
  }
}

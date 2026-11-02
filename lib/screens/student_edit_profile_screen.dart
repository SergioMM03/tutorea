import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/models/models.dart';
import '../state/session_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_back_button.dart';
import '../widgets/bottom_action_bar.dart';
import '../widgets/form_error_banner.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/section_title.dart';

/// Editar perfil del estudiante (SessionStore.updateProfile).
/// Editables: nombre, carrera (de su universidad) y año académico.
/// Correo y universidad se muestran, pero no se pueden cambiar en el MVP.
class StudentEditProfileScreen extends StatefulWidget {
  const StudentEditProfileScreen({super.key});

  @override
  State<StudentEditProfileScreen> createState() => _StudentEditProfileScreenState();
}

class _StudentEditProfileScreenState extends State<StudentEditProfileScreen> {
  static const List<int> _baseYears = [1, 2, 3, 4, 5];

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  int? _year;
  String? _careerId;
  List<Career> _careers = const [];
  bool _loadingCareers = true;

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionStore>();
    final user = session.user;
    if (user != null) {
      _name.text = user.nombre;
      _year = user.anioAcademico;
      _careerId = user.careerId;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      session.clearError();
      final careers = await session.careersOfCurrentUser();
      if (!mounted) return;
      setState(() {
        _careers = careers;
        _loadingCareers = false;
        // Cuentas antiguas sin careerId: se busca su carrera por nombre.
        if (_careerId == null && user != null) {
          _careerId = careers
              .where((c) => c.nombre.toLowerCase() == user.carrera.trim().toLowerCase())
              .firstOrNull
              ?.id;
        }
        // Una carrera que ya no está en la lista no se puede preseleccionar.
        if (!careers.any((c) => c.id == _careerId)) _careerId = null;
      });
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final session = context.read<SessionStore>();
    final ok = await session.updateProfile(
      nombre: _name.text,
      careerId: _careerId!,
      anioAcademico: _year!,
    );
    if (!mounted || !ok) return; // el error se muestra arriba
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Perfil actualizado')));
    Navigator.maybePop(context);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final session = context.watch<SessionStore>();
    final user = session.user;
    final university = user == null ? '' : session.universityName(user.universityId);
    // Si el año guardado es mayor que 5, también se ofrece.
    final years = {..._baseYears, if (_year != null) _year!}.toList()..sort();

    return Scaffold(
      appBar: AppBar(title: const Text('Editar perfil'), leading: const AppBackButton()),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppLayout.maxNarrowWidth),
            child: Form(
              key: _formKey,
              child: ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.all(AppSpacing.screenPadding),
                children: [
                  if (session.error != null) ...[
                    FormErrorBanner(message: session.error!),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  const SectionTitle(title: 'Tus datos'),
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Nombre completo',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    validator: (v) => (v == null || v.trim().length < 2)
                        ? 'Escribe tu nombre.'
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_loadingCareers)
                    const Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    DropdownButtonFormField<String>(
                      key: const Key('student-career'),
                      initialValue: _careerId,
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      decoration: const InputDecoration(
                        labelText: 'Carrera',
                        prefixIcon: Icon(Icons.school_outlined),
                      ),
                      items: [
                        for (final c in _careers)
                          DropdownMenuItem(
                            value: c.id,
                            child: Text(c.nombre, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (id) => setState(() => _careerId = id),
                      validator: (id) => id == null ? 'Elige tu carrera.' : null,
                    ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<int>(
                    key: const Key('student-year'),
                    initialValue: _year,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    decoration: const InputDecoration(
                      labelText: 'Año académico',
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    items: [
                      for (final y in years) DropdownMenuItem(value: y, child: Text('$y.º año')),
                    ],
                    onChanged: (y) => setState(() => _year = y),
                    validator: (y) => y == null ? 'Elige tu año.' : null,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const SectionTitle(title: 'Cuenta'),
                  const SizedBox(height: AppSpacing.sm),
                  _ReadOnlyField(
                    icon: Icons.mail_outline_rounded,
                    label: 'Correo',
                    value: user?.correo ?? '',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _ReadOnlyField(
                    icon: Icons.account_balance_outlined,
                    label: 'Universidad',
                    value: university,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'El correo y la universidad no se pueden cambiar por ahora.',
                    style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: BottomActionBar(
        maxContentWidth: AppLayout.maxNarrowWidth,
        child: Row(
          children: [
            Expanded(
              child: SecondaryButton(
                label: 'Cancelar',
                onPressed: session.isLoading ? null : () => Navigator.maybePop(context),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: PrimaryButton(
                label: 'Guardar cambios',
                loading: session.isLoading,
                onPressed: _loadingCareers ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dato que se muestra pero no se puede editar.
class _ReadOnlyField extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ReadOnlyField({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm + AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 22),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                Text(value.isEmpty ? '—' : value, style: textTheme.bodyLarge),
              ],
            ),
          ),
          const Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}

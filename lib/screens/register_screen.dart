import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/models/models.dart';
import '../routes/app_navigator.dart';
import '../state/session_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_back_button.dart';
import '../widgets/form_error_banner.dart';
import '../widgets/primary_button.dart';
import '../widgets/section_title.dart';
import '../widgets/selected_university_banner.dart';
import '../widgets/subject_chip.dart';

/// Crear cuenta de estudiante o tutor (SessionStore.register).
/// La cuenta se crea en la universidad elegida en la pantalla inicial y la
/// carrera se elige entre las carreras de esa universidad.
/// Un tutor queda registrado sin TutorProfile: lo completa en su panel.
class RegisterScreen extends StatefulWidget {
  final UserRole initialRole;

  const RegisterScreen({super.key, this.initialRole = UserRole.estudiante});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const List<int> _years = [1, 2, 3, 4, 5];

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  Career? _career;
  int? _year;
  late UserRole _role = widget.initialRole;
  bool _hidePassword = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SessionStore>().clearError();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _required(String? value, String message) =>
      (value == null || value.trim().isEmpty) ? message : null;

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final session = context.read<SessionStore>();
    final university = session.selectedUniversity;
    if (university == null) return; // el botón está deshabilitado sin universidad
    final ok = await session.register(
      nombre: _name.text,
      correo: _email.text,
      password: _password.text,
      universityId: university.id,
      careerId: _career!.id,
      carrera: _career!.nombre,
      anioAcademico: _year!,
      rol: _role,
    );
    if (!mounted || !ok) return;
    AppNavigator.afterAuth(context, _role);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    final textTheme = Theme.of(context).textTheme;
    final university = session.selectedUniversity;
    final careers = session.selectedUniversityCareers;

    return Scaffold(
      appBar: AppBar(leading: const AppBackButton(), title: const Text('Crear cuenta')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.sm,
              AppSpacing.screenPadding,
              AppSpacing.lg,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppLayout.maxNarrowWidth),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SelectedUniversityBanner(university: university),
                    if (university == null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      const FormErrorBanner(
                          message: 'Elige tu universidad para poder crear tu cuenta.'),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    const SectionTitle(title: '¿Cómo usarás Tutorea?'),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      children: [
                        for (final role in UserRole.values)
                          SubjectChip(
                            label: role == UserRole.estudiante
                                ? 'Soy estudiante'
                                : 'Quiero ser tutor',
                            selected: _role == role,
                            onTap: () => setState(() => _role = role),
                          ),
                      ],
                    ),
                    if (_role == UserRole.tutor) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Después de registrarte completarás tu perfil de tutor: '
                        'materias, precio y disponibilidad.',
                        style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    const SectionTitle(title: 'Tus datos'),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Nombre completo',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                      validator: (v) => _required(v, 'Escribe tu nombre.'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Correo',
                        hintText: 'Tu correo institucional',
                        prefixIcon: Icon(Icons.mail_outline_rounded),
                      ),
                      validator: (v) {
                        final empty = _required(v, 'Escribe tu correo.');
                        if (empty != null) return empty;
                        return v!.contains('@') ? null : 'Escribe un correo válido.';
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _password,
                      obscureText: _hidePassword,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        helperText: 'Mínimo 6 caracteres',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          tooltip: _hidePassword ? 'Mostrar' : 'Ocultar',
                          icon: Icon(_hidePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _hidePassword = !_hidePassword),
                        ),
                      ),
                      validator: (v) => (v == null || v.length < 6)
                          ? 'La contraseña debe tener al menos 6 caracteres.'
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // Solo carreras de la universidad elegida.
                    DropdownButtonFormField<Career>(
                      key: ValueKey('career-${university?.id}'),
                      initialValue: _career,
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      decoration: const InputDecoration(
                        labelText: 'Carrera',
                        prefixIcon: Icon(Icons.school_outlined),
                      ),
                      items: [
                        for (final c in careers)
                          DropdownMenuItem(
                            value: c,
                            child: Text(c.nombre, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (c) => setState(() => _career = c),
                      validator: (c) => c == null ? 'Elige tu carrera.' : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<int>(
                      initialValue: _year,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      decoration: const InputDecoration(
                        labelText: 'Año académico',
                        prefixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                      items: [
                        for (final y in _years)
                          DropdownMenuItem(value: y, child: Text('$y.º año')),
                      ],
                      onChanged: (y) => setState(() => _year = y),
                      validator: (y) => y == null ? 'Elige tu año.' : null,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (session.error != null) ...[
                      FormErrorBanner(message: session.error!),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    PrimaryButton(
                      label: 'Crear cuenta',
                      loading: session.isLoading,
                      onPressed: university == null ? null : _submit,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextButton(
                      onPressed: () => AppNavigator.toLogin(context),
                      child: const Text('¿Ya tienes cuenta? Iniciar sesión'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

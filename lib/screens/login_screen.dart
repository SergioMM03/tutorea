import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../routes/app_navigator.dart';
import '../state/session_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/formatters.dart';
import '../widgets/app_back_button.dart';
import '../widgets/app_logo.dart';
import '../widgets/primary_button.dart';
import '../widgets/form_error_banner.dart';
import '../widgets/secondary_button.dart';
import '../widgets/selected_university_banner.dart';

/// Iniciar sesión con correo y contraseña (SessionStore.login).
/// Usa la universidad elegida en la pantalla inicial: la cuenta debe
/// pertenecer a esa universidad.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _hidePassword = true;

  @override
  void initState() {
    super.initState();
    // No mostrar un error de un intento anterior.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SessionStore>().clearError();
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final session = context.read<SessionStore>();
    final ok = await session.login(correo: _email.text, password: _password.text);
    if (!mounted || !ok) return; // si falló, el error se muestra arriba del botón
    AppNavigator.afterAuth(context, session.role!);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    final textTheme = Theme.of(context).textTheme;
    final university = session.selectedUniversity;

    return Scaffold(
      appBar: AppBar(leading: const AppBackButton()),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppLayout.maxNarrowWidth),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: AppLogo(size: 48, showText: false)),
                    const SizedBox(height: AppSpacing.md),
                    Text('Iniciar sesión',
                        textAlign: TextAlign.center, style: textTheme.headlineLarge),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      university == null
                          ? 'Elige tu universidad para iniciar sesión.'
                          : 'Entra con tu cuenta de '
                              '${Formatters.universityShortName(university.nombre)}.',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    SelectedUniversityBanner(university: university),
                    const SizedBox(height: AppSpacing.lg),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Correo',
                        hintText: 'Tu correo institucional',
                        prefixIcon: Icon(Icons.mail_outline_rounded),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Escribe tu correo.' : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _password,
                      obscureText: _hidePassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          tooltip: _hidePassword ? 'Mostrar' : 'Ocultar',
                          icon: Icon(_hidePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _hidePassword = !_hidePassword),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Escribe tu contraseña.' : null,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (session.error != null) ...[
                      FormErrorBanner(message: session.error!),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    // La cuenta es de otra universidad: ofrecer elegirla de nuevo.
                    if (session.universityMismatch) ...[
                      SecondaryButton(
                        label: 'Volver a seleccionar universidad',
                        onPressed: () => AppNavigator.toUniversitySelection(context),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    PrimaryButton(
                      label: 'Iniciar sesión',
                      loading: session.isLoading,
                      onPressed: university == null ? null : _submit,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextButton(
                      onPressed: () => AppNavigator.toRegister(context),
                      child: const Text('¿No tienes cuenta? Crear cuenta'),
                    ),
                    const SizedBox(height: AppSpacing.lg),
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

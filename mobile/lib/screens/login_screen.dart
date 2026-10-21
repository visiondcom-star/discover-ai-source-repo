import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController(text: AppConfig.demoEmail);
  final _passwordController = TextEditingController(text: 'demo1234');
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.login(
      _emailController.text.trim(),
      _passwordController.text,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!ok) {
      final loc = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _loginErrorText(loc, auth.loginError),
            key: const Key('login_error'),
          ),
        ),
      );
    }
    // On success the AuthGate switches to HomeShell automatically.
  }

  /// Translates the provider's locale-agnostic [AuthError] into a
  /// user-facing string. The provider has no `BuildContext`, so the mapping
  /// lives here — and the `null` case (login returned false without setting
  /// a code, e.g. an empty token) falls back to the generic message.
  String _loginErrorText(AppLocalizations loc, AuthError? error) {
    switch (error) {
      case AuthError.invalidCredentials:
        return loc.loginErrorInvalidCredentials;
      case AuthError.network:
        return loc.loginErrorNetwork;
      case AuthError.generic:
      case null:
        return loc.loginErrorGeneric;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(loc.appName)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.travel_explore, size: 72),
                const SizedBox(height: 24),
                TextFormField(
                  key: const Key('login_email'),
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: loc.loginEmailLabel,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => (v == null || !v.contains('@'))
                      ? loc.loginEmailInvalid
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('login_password'),
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: loc.loginPasswordLabel,
                    border: const OutlineInputBorder(),
                  ),
                  enableSuggestions: false,
                  autocorrect: false,
                  validator: (v) => (v == null || v.isEmpty)
                      ? loc.loginPasswordRequired
                      : null,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('login_submit'),
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(loc.loginSubmit),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

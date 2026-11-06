import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _identity = TextEditingController();
  final TextEditingController _code = TextEditingController();

  @override
  void dispose() {
    _identity.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final awaitingCode = state.status == AuthStatus.awaitingCode || state.status == AuthStatus.submitting && state.identity != null;
    final loading = state.status == AuthStatus.submitting;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Icon(
                        Icons.volunteer_activism_outlined,
                        size: 64,
                        color: Theme.of(context).colorScheme.primary,
                        semanticLabel: 'Go-Ye',
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Welcome to Go-Ye',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        awaitingCode
                            ? 'Enter the six-digit code sent to your approved contact.'
                            : 'Sign in with your approved phone number or email address.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      if (!awaitingCode) ...<Widget>[
                        TextField(
                          controller: _identity,
                          autofocus: true,
                          enabled: !loading,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const <String>[AutofillHints.email, AutofillHints.telephoneNumber],
                          decoration: const InputDecoration(
                            labelText: 'Phone number or email',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _requestCode(),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: loading ? null : _requestCode,
                          child: loading
                              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator())
                              : const Text('Send sign-in code'),
                        ),
                      ] else ...<Widget>[
                        Text(
                          state.identity ?? '',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _code,
                          autofocus: true,
                          enabled: !loading,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          autofillHints: const <String>[AutofillHints.oneTimeCode],
                          decoration: const InputDecoration(
                            labelText: 'Six-digit code',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _verifyCode(),
                        ),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: loading ? null : _verifyCode,
                          child: loading
                              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator())
                              : const Text('Sign in securely'),
                        ),
                        TextButton(
                          onPressed: loading ? null : _startOver,
                          child: const Text('Use a different contact'),
                        ),
                      ],
                      if (state.message != null) ...<Widget>[
                        const SizedBox(height: 16),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            state.message!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _requestCode() {
    ref.read(authControllerProvider.notifier).requestCode(_identity.text);
  }

  void _verifyCode() {
    ref.read(authControllerProvider.notifier).verifyCode(_code.text);
  }

  void _startOver() {
    _code.clear();
    ref.read(authControllerProvider.notifier).signOut();
  }
}

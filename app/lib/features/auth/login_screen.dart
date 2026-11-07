import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_providers.dart';
import '../../core/branding.dart';
import '../../l10n/app_localizations.dart';
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
    final awaitingCode = state.status == AuthStatus.awaitingCode ||
        state.status == AuthStatus.submitting && state.identity != null;
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
                      Align(
                        alignment: Alignment.centerRight,
                        child: _LanguageButton(ref: ref),
                      ),
                      const GoYeLogo(size: 72),
                      const SizedBox(height: 20),
                      Text(
                        context.l10n.welcome,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        awaitingCode
                            ? context.l10n.codePrompt
                            : context.l10n.signInPrompt,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      if (!awaitingCode) ...<Widget>[
                        TextField(
                          controller: _identity,
                          autofocus: true,
                          enabled: !loading,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const <String>[
                            AutofillHints.email,
                            AutofillHints.telephoneNumber,
                          ],
                          decoration: InputDecoration(
                            labelText: context.l10n.phoneOrEmail,
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _requestCode(),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: loading ? null : _requestCode,
                          child: loading
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(),
                                )
                              : Text(context.l10n.sendCode),
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
                          autofillHints: const <String>[
                            AutofillHints.oneTimeCode,
                          ],
                          decoration: InputDecoration(
                            labelText: context.l10n.sixDigitCode,
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _verifyCode(),
                        ),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: loading ? null : _verifyCode,
                          child: loading
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(),
                                )
                              : Text(context.l10n.signInSecurely),
                        ),
                        TextButton(
                          onPressed: loading ? null : _startOver,
                          child: Text(context.l10n.useDifferentContact),
                        ),
                      ],
                      if (state.message != null) ...<Widget>[
                        const SizedBox(height: 16),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            state.message!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
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

class _LanguageButton extends StatelessWidget {
  const _LanguageButton({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    return PopupMenuButton<Locale>(
      tooltip: context.l10n.language,
      initialValue: locale,
      onSelected: (Locale value) =>
          ref.read(localeProvider.notifier).state = value,
      itemBuilder: (BuildContext context) => <PopupMenuEntry<Locale>>[
        PopupMenuItem<Locale>(
          value: const Locale('en'),
          child: Text(context.l10n.english),
        ),
        PopupMenuItem<Locale>(
          value: const Locale('yo'),
          child: Text(context.l10n.yoruba),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(locale.languageCode.toUpperCase()),
      ),
    );
  }
}

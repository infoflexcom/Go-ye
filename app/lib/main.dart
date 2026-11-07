import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_providers.dart';
import 'core/branding.dart';
import 'features/auth/auth_controller.dart';
import 'l10n/app_localizations.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_shell.dart';

void main() {
  runApp(const ProviderScope(child: GoYeApp()));
}

class GoYeApp extends ConsumerWidget {
  const GoYeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final lightScheme = ColorScheme.fromSeed(
      seedColor: GoYeBrand.green,
      brightness: Brightness.light,
    );
    final darkScheme = ColorScheme.fromSeed(
      seedColor: GoYeBrand.green,
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'Go-Ye',
      locale: locale,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        AppLocalizations.yorubaMaterialFallbackDelegate,
        AppLocalizations.yorubaCupertinoFallbackDelegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData(colorScheme: lightScheme, useMaterial3: true),
      darkTheme: ThemeData(colorScheme: darkScheme, useMaterial3: true),
      home: switch (auth.status) {
        AuthStatus.restoring => const _RestoringSessionScreen(),
        AuthStatus.signedIn when auth.session != null => HomeShell(
            session: auth.session!,
          ),
        _ => const LoginScreen(),
      },
    );
  }
}

class _RestoringSessionScreen extends StatelessWidget {
  const _RestoringSessionScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            GoYeLogo(size: 96),
            SizedBox(height: 24),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

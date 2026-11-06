import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/auth_controller.dart';
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
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0C5C35),
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: 'Go-Ye',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: colorScheme, useMaterial3: true),
      home: switch (auth.status) {
        AuthStatus.restoring => const _RestoringSessionScreen(),
        AuthStatus.signedIn when auth.session != null => HomeShell(session: auth.session!),
        _ => const LoginScreen(),
      },
    );
  }
}

class _RestoringSessionScreen extends StatelessWidget {
  const _RestoringSessionScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

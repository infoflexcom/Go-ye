import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goye/l10n/app_localizations.dart';

void main() {
  testWidgets('switches the client catalog from English to Yoruba', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('yo'),
        localizationsDelegates: <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: _LocalizedText(),
      ),
    );

    expect(find.text('Káàbọ̀ sí Go-Ye'), findsOneWidget);
  });
}

class _LocalizedText extends StatelessWidget {
  const _LocalizedText();

  @override
  Widget build(BuildContext context) => Text(context.l10n.welcome);
}

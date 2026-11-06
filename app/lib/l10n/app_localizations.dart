import 'package:flutter/material.dart';

/// Compact, data-led localisation catalog for the first client increment.
/// Add another locale by adding a key-complete entry to [_messages]; widgets do
/// not contain locale-specific text.
class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();
  static const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('yo')];

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  String text(String key) {
    final selected = _messages[locale.languageCode] ?? _messages['en']!;
    return selected[key] ?? _messages['en']![key] ?? key;
  }

  String get appName => text('appName');
  String get welcome => text('welcome');
  String get signInPrompt => text('signInPrompt');
  String get codePrompt => text('codePrompt');
  String get phoneOrEmail => text('phoneOrEmail');
  String get sendCode => text('sendCode');
  String get sixDigitCode => text('sixDigitCode');
  String get signInSecurely => text('signInSecurely');
  String get useDifferentContact => text('useDifferentContact');
  String get signOut => text('signOut');
  String get dashboard => text('dashboard');
  String get newDecision => text('newDecision');
  String get converts => text('converts');
  String get unassigned => text('unassigned');
  String get countries => text('countries');
  String get signedInSecurely => text('signedInSecurely');
  String get noActiveRole => text('noActiveRole');
  String get workspaceReady => text('workspaceReady');
  String get about => text('about');
  String get aboutGoYe => text('aboutGoYe');
  String get aboutBody => text('aboutBody');
  String get builtBy => text('builtBy');
  String get close => text('close');
  String get toggleDarkMode => text('toggleDarkMode');
  String get language => text('language');
  String get english => text('english');
  String get yoruba => text('yoruba');
  String get enterIdentity => text('enterIdentity');
  String get enterCode => text('enterCode');
  String get networkError => text('networkError');

  static const Map<String, Map<String, String>> _messages = <String, Map<String, String>>{
    'en': <String, String>{
      'appName': 'Go-Ye',
      'welcome': 'Welcome to Go-Ye',
      'signInPrompt': 'Sign in with your approved phone number or email address.',
      'codePrompt': 'Enter the six-digit code sent to your approved contact.',
      'phoneOrEmail': 'Phone number or email',
      'sendCode': 'Send sign-in code',
      'sixDigitCode': 'Six-digit code',
      'signInSecurely': 'Sign in securely',
      'useDifferentContact': 'Use a different contact',
      'signOut': 'Sign out',
      'dashboard': 'Dashboard',
      'newDecision': 'New decision',
      'converts': 'Converts',
      'unassigned': 'Unassigned',
      'countries': 'Countries',
      'signedInSecurely': 'Signed in securely',
      'noActiveRole': 'No active role is assigned.',
      'workspaceReady': 'Role-aware workspace navigation is ready.',
      'about': 'About Go-Ye',
      'aboutGoYe': 'About Go-Ye',
      'aboutBody': 'Go-Ye helps authorised RCCG workers register decisions and provide follow-up with care.',
      'builtBy': 'Built by',
      'close': 'Close',
      'toggleDarkMode': 'Toggle dark mode',
      'language': 'Language',
      'english': 'English',
      'yoruba': 'Yorùbá',
      'enterIdentity': 'Enter your approved phone number or email address.',
      'enterCode': 'Enter the six-digit code.',
      'networkError': 'Unable to reach Go-Ye. Check the server connection and try again.',
    },
    'yo': <String, String>{
      'appName': 'Go-Ye',
      'welcome': 'Káàbọ̀ sí Go-Ye',
      'signInPrompt': 'Wọlé pẹ̀lú nọ́ńbà fóònù tàbí íméèlì tí a ti fọwọ́sí.',
      'codePrompt': 'Tẹ kóòdù oní-nọ́ńbà mẹ́fà tí a rán sí ọ.',
      'phoneOrEmail': 'Nọ́ńbà fóònù tàbí íméèlì',
      'sendCode': 'Firanṣẹ́ kóòdù ìwọlé',
      'sixDigitCode': 'Kóòdù oní-nọ́ńbà mẹ́fà',
      'signInSecurely': 'Wọlé ní ààbò',
      'useDifferentContact': 'Lo ìbánisọ̀rọ̀ mìíràn',
      'signOut': 'Jáde',
      'dashboard': 'Àkójọ ìwòye',
      'newDecision': 'Ìpinnu tuntun',
      'converts': 'Àwọn olùyípadà',
      'unassigned': 'Tí a kò pín',
      'countries': 'Àwọn orílẹ̀-èdè',
      'signedInSecurely': 'O ti wọlé ní ààbò',
      'noActiveRole': 'A kò fi ipa kan sílẹ̀ fún ọ.',
      'workspaceReady': 'Ìtọ́sọ́nà ibi iṣẹ́ gẹ́gẹ́ bí ipa ti ṣetán.',
      'about': 'Nípa Go-Ye',
      'aboutGoYe': 'Nípa Go-Ye',
      'aboutBody': 'Go-Ye ń ran àwọn òṣìṣẹ́ RCCG tí a fọwọ́sí lọ́wọ́ láti forúkọsílẹ̀ àwọn ìpinnu àti láti tọ́ wọn lẹ́yìn pẹ̀lú ìfẹ́.',
      'builtBy': 'Ẹni tí ó kọ́ ọ',
      'close': 'Pàdé',
      'toggleDarkMode': 'Yí ìmólẹ̀ dúdú padà',
      'language': 'Èdè',
      'english': 'Gẹ̀ẹ́sì',
      'yoruba': 'Yorùbá',
      'enterIdentity': 'Tẹ nọ́ńbà fóònù tàbí íméèlì tí a fọwọ́sí.',
      'enterCode': 'Tẹ kóòdù oní-nọ́ńbà mẹ́fà.',
      'networkError': 'A kò lè dé Go-Ye. Ṣàyẹ̀wò ìsopọ̀ olupin kí o tún gbìyànjú.',
    },
  };
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales.contains(Locale(locale.languageCode));

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(Locale(locale.languageCode));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Compact, data-led localisation catalog for the first client increment.
/// Add another locale by adding a key-complete entry to [_messages]; widgets do
/// not contain locale-specific text.
class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();
  static const LocalizationsDelegate<MaterialLocalizations>
      yorubaMaterialFallbackDelegate = _YorubaMaterialLocalizationsDelegate();
  static const LocalizationsDelegate<CupertinoLocalizations>
      yorubaCupertinoFallbackDelegate = _YorubaCupertinoLocalizationsDelegate();
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('yo'),
  ];

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

  static const Map<String, Map<String, String>> _messages =
      <String, Map<String, String>>{
    'en': <String, String>{
      'appName': 'Go-Ye',
      'welcome': 'Welcome to Go-Ye',
      'signInPrompt':
          'Sign in with your approved phone number or email address.',
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
      'hierarchy': 'Hierarchy',
      'signedInSecurely': 'Signed in securely',
      'noActiveRole': 'No active role is assigned.',
      'workspaceReady': 'Role-aware workspace navigation is ready.',
      'about': 'About Go-Ye',
      'aboutGoYe': 'About Go-Ye',
      'aboutBody':
          'Go-Ye helps authorised RCCG workers register decisions and provide follow-up with care.',
      'builtBy': 'Built by',
      'close': 'Close',
      'toggleDarkMode': 'Toggle dark mode',
      'language': 'Language',
      'english': 'English',
      'yoruba': 'Yorùbá',
      'enterIdentity': 'Enter your approved phone number or email address.',
      'enterCode': 'Enter the six-digit code.',
      'networkError':
          'Unable to reach Go-Ye. Check the server connection and try again.',
      'decisionFormHelp':
          'Record the decision only after the person has given clear consent.',
      'fullName': 'Full name',
      'required': 'This field is required.',
      'phoneOptional': 'Phone number (optional)',
      'addressOptional': 'Address (optional)',
      'unitLoadError': 'Could not load organisation units.',
      'registrationUnit': 'Registration unit',
      'selectRegistrationUnit': 'Select a registration unit.',
      'consentMethod': 'Consent method',
      'consentStatement':
          'The person has affirmatively agreed to this information being recorded for follow-up.',
      'consentRequired': 'Consent is required before saving.',
      'saveDecision': 'Save decision',
      'decisionSaved': 'was saved.',
      'tryAgain': 'Try again',
      'visibleRecords': 'visible records',
      'convertDetail': 'Convert details',
      'convertLoadError': 'Could not load this convert.',
      'stage': 'Stage',
      'phone': 'Phone',
      'address': 'Address',
      'parish': 'Parish',
      'notAssigned': 'Not assigned',
      'poolEmpty': 'There are no converts waiting for parish assignment.',
      'daysWaiting': 'days waiting',
      'assign': 'Assign',
      'assignedTo': 'was assigned to',
      'assignToParish': 'Assign to parish',
      'noParishAvailable': 'No eligible parish is available in your scope.',
      'countUnavailable': 'Counts are not available for this active role.',
      'yourScope': 'Your scope',
      'activeConverts': 'active converts',
      'todayFollowUp': 'Today',
      'followUpRisks': 'Follow-up risks',
      'escalations': 'Escalations',
      'neglected': 'Neglected',
      'overdueEscalations': 'overdue escalations',
      'neglectedConverts': 'neglected converts',
      'escalationsEmpty':
          'There are no overdue follow-up actions in your scope.',
      'neglectedEmpty': 'There are no neglected converts in your scope.',
      'followUpRiskLoadError': 'Could not load follow-up risk lists.',
      'escalationResolved': 'Overdue follow-up marked done.',
      'overdueTasks': 'overdue tasks',
      'overdue': 'overdue',
      'shortDays': 'd',
      'shortHours': 'h',
      'shortMinutes': 'm',
      'todayEmpty': 'There are no follow-up tasks due today.',
      'todayLoadError': 'Could not load today’s follow-up tasks.',
      'refresh': 'Refresh',
      'done': 'DONE',
      'markedDone': 'marked done.',
      'outcomeNote': 'Outcome / note',
      'recordOutcome': 'Record outcome',
      'outcome': 'Outcome',
      'noteOptional': 'Note (optional)',
      'outcomeSaved': 'Follow-up outcome saved.',
      'call24h': '24-hour call',
      'prayerDay3': 'Day 3 prayer',
      'visitDay7': 'Day 7 visit',
      'weeklyCheckIn': 'Weekly check-in',
      'outcomeCompleted': 'Completed',
      'outcomeNoContact': 'No contact',
      'outcomeRescheduled': 'Rescheduled',
      'outcomeDeclined': 'Declined',
      'outcomeOther': 'Other',
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
      'hierarchy': 'Àtòjọ ìjọ',
      'signedInSecurely': 'O ti wọlé ní ààbò',
      'noActiveRole': 'A kò fi ipa kan sílẹ̀ fún ọ.',
      'workspaceReady': 'Ìtọ́sọ́nà ibi iṣẹ́ gẹ́gẹ́ bí ipa ti ṣetán.',
      'about': 'Nípa Go-Ye',
      'aboutGoYe': 'Nípa Go-Ye',
      'aboutBody':
          'Go-Ye ń ran àwọn òṣìṣẹ́ RCCG tí a fọwọ́sí lọ́wọ́ láti forúkọsílẹ̀ àwọn ìpinnu àti láti tọ́ wọn lẹ́yìn pẹ̀lú ìfẹ́.',
      'builtBy': 'Ẹni tí ó kọ́ ọ',
      'close': 'Pàdé',
      'toggleDarkMode': 'Yí ìmólẹ̀ dúdú padà',
      'language': 'Èdè',
      'english': 'Gẹ̀ẹ́sì',
      'yoruba': 'Yorùbá',
      'enterIdentity': 'Tẹ nọ́ńbà fóònù tàbí íméèlì tí a fọwọ́sí.',
      'enterCode': 'Tẹ kóòdù oní-nọ́ńbà mẹ́fà.',
      'networkError':
          'A kò lè dé Go-Ye. Ṣàyẹ̀wò ìsopọ̀ olupin kí o tún gbìyànjú.',
      'decisionFormHelp':
          'Forúkọsílẹ̀ ìpinnu náà lẹ́yìn tí ẹni náà bá ti fọwọ́ sí i ní kedere.',
      'fullName': 'Orúkọ kíkún',
      'required': 'A nílò ibi yìí.',
      'phoneOptional': 'Nọ́ńbà fóònù (aṣàyàn)',
      'addressOptional': 'Àdírẹ́sì (aṣàyàn)',
      'unitLoadError': 'A kò lè gba àwọn ẹ̀ka ìjọ.',
      'registrationUnit': 'Ẹ̀ka ìforúkọsílẹ̀',
      'selectRegistrationUnit': 'Yan ẹ̀ka ìforúkọsílẹ̀.',
      'consentMethod': 'Ọ̀nà ìfọwọ́sí',
      'consentStatement':
          'Ẹni náà ti fọwọ́ sí i pé a lè kọ ìwífún yìí sílẹ̀ fún ìtọ́lẹ́yìn.',
      'consentRequired': 'Ìfọwọ́sí yẹ kí ó wà kí a tó fipamọ́.',
      'saveDecision': 'Fi ìpinnu pamọ́',
      'decisionSaved': 'ti wa ní fífipamọ́.',
      'tryAgain': 'Tún gbìyànjú',
      'visibleRecords': 'àwọn àkọsílẹ̀ tí a rí',
      'convertDetail': 'Àlàyé olùyípadà',
      'convertLoadError': 'A kò lè gba olùyípadà yìí.',
      'stage': 'Ìpínlẹ̀',
      'phone': 'Fóònù',
      'address': 'Àdírẹ́sì',
      'parish': 'Páríṣì',
      'notAssigned': 'A kò pín sílẹ̀',
      'poolEmpty': 'Kò sí olùyípadà tí ń dúró de pípín sí páríṣì.',
      'daysWaiting': 'ọjọ́ ìdúró',
      'assign': 'Pín',
      'assignedTo': 'ti pín sí',
      'assignToParish': 'Pín sí páríṣì',
      'noParishAvailable': 'Kò sí páríṣì tí ó yẹ nínú ìwọ̀n rẹ.',
      'countUnavailable': 'Àwọn iye kò wà fún ipa tí ó ń ṣiṣẹ́ yìí.',
      'yourScope': 'Ìwọ̀n rẹ',
      'activeConverts': 'àwọn olùyípadà tí ń ṣiṣẹ́',
      'todayFollowUp': 'Òní',
      'followUpRisks': 'Àwọn ewu ìtọ́lẹ́yìn',
      'escalations': 'Ìgbésíwájú',
      'neglected': 'Àwọn tí a kò tọ́jú',
      'overdueEscalations': 'àwọn ìgbésíwájú tí ó ti péjọ́',
      'neglectedConverts': 'àwọn olùyípadà tí a kò tọ́jú',
      'escalationsEmpty':
          'Kò sí iṣẹ́ ìtọ́lẹ́yìn tí ó ti kọjá àkókò nínú ìwọ̀n rẹ.',
      'neglectedEmpty': 'Kò sí olùyípadà tí a kò tọ́jú nínú ìwọ̀n rẹ.',
      'followUpRiskLoadError': 'A kò lè gba àkọsílẹ̀ ewu ìtọ́lẹ́yìn.',
      'escalationResolved':
          'A ti samisi iṣẹ́ ìtọ́lẹ́yìn tó ti péjọ́ pé ó parí.',
      'overdueTasks': 'àwọn iṣẹ́ tí ó ti péjọ́',
      'overdue': 'ti péjọ́',
      'shortDays': 'ọ',
      'shortHours': 'w',
      'shortMinutes': 'ì',
      'todayEmpty': 'Kò sí iṣẹ́ ìtọ́lẹ́yìn tí ó yẹ fún òní.',
      'todayLoadError': 'A kò lè gba àwọn iṣẹ́ ìtọ́lẹ́yìn òní.',
      'refresh': 'Tún gbìyànjú',
      'done': 'ṢE É',
      'markedDone': 'ti parí.',
      'outcomeNote': 'Àbájáde / àkọsílẹ̀',
      'recordOutcome': 'Kọ àbájáde sílẹ̀',
      'outcome': 'Àbájáde',
      'noteOptional': 'Àkọsílẹ̀ (àṣàyàn)',
      'outcomeSaved': 'A ti fi àbájáde ìtọ́lẹ́yìn pamọ́.',
      'call24h': 'Ìpè wákàtí 24',
      'prayerDay3': 'Àdúrà ọjọ́ kẹta',
      'visitDay7': 'Ìbẹ̀wò ọjọ́ keje',
      'weeklyCheckIn': 'Àyẹ̀wò ọ̀sẹ̀',
      'outcomeCompleted': 'Ti parí',
      'outcomeNoContact': 'A kò rí ẹni náà',
      'outcomeRescheduled': 'A tún ṣètò rẹ̀',
      'outcomeDeclined': 'Ó kọ̀',
      'outcomeOther': 'Mìíràn',
    },
  };
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.supportedLocales.contains(Locale(locale.languageCode));

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(Locale(locale.languageCode));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

/// Flutter does not provide a Yoruba Material catalog. The client still
/// supplies its complete Yoruba catalog while stock Material controls use the
/// English fallback instead of making the locale unavailable.
class _YorubaMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _YorubaMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'yo';

  @override
  Future<MaterialLocalizations> load(Locale locale) async {
    return const DefaultMaterialLocalizations();
  }

  @override
  bool shouldReload(_YorubaMaterialLocalizationsDelegate old) => false;
}

/// MaterialApp also supplies Cupertino localizations for shared platform
/// behavior. Use Flutter's English default for those stock strings until a
/// Yoruba Cupertino catalog becomes available.
class _YorubaCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _YorubaCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'yo';

  @override
  Future<CupertinoLocalizations> load(Locale locale) async {
    return const DefaultCupertinoLocalizations();
  }

  @override
  bool shouldReload(_YorubaCupertinoLocalizationsDelegate old) => false;
}

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

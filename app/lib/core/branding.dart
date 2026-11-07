import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

class GoYeBrand {
  static const Color green = Color(0xFF0C5C35);
  static const Color gold = Color(0xFFD8A84A);
  static const String logoAsset = 'assets/branding/logo.jpg';
  static const String infoflexLogoAsset = 'assets/branding/infoflex-logo.png';
}

class GoYeLogo extends StatelessWidget {
  const GoYeLogo({this.size = 56, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'RCCG Go-Ye',
      child: ClipOval(
        child: Image.asset(
          GoYeBrand.logoAsset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.volunteer_activism, size: size),
        ),
      ),
    );
  }
}

class AboutGoYeDialog extends StatelessWidget {
  const AboutGoYeDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const GoYeLogo(size: 56),
      title: Text(context.l10n.aboutGoYe),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(context.l10n.aboutBody, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          Text(
            context.l10n.builtBy,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Image.asset(
            GoYeBrand.infoflexLogoAsset,
            height: 38,
            fit: BoxFit.contain,
            semanticLabel: 'INFOFLEX',
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }
}

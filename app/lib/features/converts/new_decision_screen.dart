import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/app_providers.dart';
import '../../core/models.dart';
import '../../l10n/app_localizations.dart';

class NewDecisionScreen extends ConsumerStatefulWidget {
  const NewDecisionScreen({required this.isGlobalAdmin, super.key});

  final bool isGlobalAdmin;

  @override
  ConsumerState<NewDecisionScreen> createState() => _NewDecisionScreenState();
}

class _NewDecisionScreenState extends ConsumerState<NewDecisionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  var _consentGranted = false;
  var _consentMethod = 'DIGITAL';
  String? _registrationUnitId;
  var _submitting = false;

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final units = ref.watch(orgUnitsProvider);
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            context.l10n.text('newDecision'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(context.l10n.text('decisionFormHelp')),
          const SizedBox(height: 20),
          TextFormField(
            controller: _fullName,
            textCapitalization: TextCapitalization.words,
            autofillHints: const <String>[AutofillHints.name],
            decoration: InputDecoration(
              labelText: context.l10n.text('fullName'),
              border: const OutlineInputBorder(),
            ),
            validator: (String? value) => value == null || value.trim().isEmpty
                ? context.l10n.text('required')
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofillHints: const <String>[AutofillHints.telephoneNumber],
            decoration: InputDecoration(
              labelText: context.l10n.text('phoneOptional'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _address,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: context.l10n.text('addressOptional'),
              border: const OutlineInputBorder(),
            ),
          ),
          if (widget.isGlobalAdmin) ...<Widget>[
            const SizedBox(height: 16),
            units.when(
              loading: () => const LinearProgressIndicator(),
              error: (Object error, StackTrace stackTrace) =>
                  Text(context.l10n.text('unitLoadError')),
              data: (List<OrgUnit> values) => DropdownButtonFormField<String>(
                value: _registrationUnitId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.l10n.text('registrationUnit'),
                  border: const OutlineInputBorder(),
                ),
                items: values
                    .where((OrgUnit unit) => unit.isActive)
                    .map(
                      (OrgUnit unit) => DropdownMenuItem<String>(
                        value: unit.id,
                        child: Text(
                          '${unit.name} (${unit.type})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _submitting
                    ? null
                    : (String? value) =>
                        setState(() => _registrationUnitId = value),
                validator: (String? value) => value == null
                    ? context.l10n.text('selectRegistrationUnit')
                    : null,
              ),
            ),
          ],
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _consentMethod,
            decoration: InputDecoration(
              labelText: context.l10n.text('consentMethod'),
              border: const OutlineInputBorder(),
            ),
            items: <String>['DIGITAL', 'VERBAL', 'WRITTEN']
                .map(
                  (String method) => DropdownMenuItem<String>(
                    value: method,
                    child: Text(method),
                  ),
                )
                .toList(growable: false),
            onChanged: _submitting
                ? null
                : (String? value) =>
                    setState(() => _consentMethod = value ?? 'DIGITAL'),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _consentGranted,
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.text('consentStatement')),
            onChanged: _submitting
                ? null
                : (bool? value) =>
                    setState(() => _consentGranted = value ?? false),
          ),
          if (!_consentGranted)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                context.l10n.text('consentRequired'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          FilledButton.icon(
            onPressed: _submitting ? null : _save,
            icon: _submitting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(context.l10n.text('saveDecision')),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || !_consentGranted) {
      setState(() {});
      return;
    }
    setState(() => _submitting = true);
    try {
      final saved = await ref.read(convertsRepositoryProvider).create(
            fullName: _fullName.text.trim(),
            phone: _phone.text.trim(),
            address: _address.text.trim(),
            registeredAtUnitId: _registrationUnitId,
            consentMethod: _consentMethod,
          );
      ref.invalidate(convertsProvider);
      ref.invalidate(unassignedConvertsProvider);
      if (!mounted) {
        return;
      }
      _formKey.currentState!.reset();
      _fullName.clear();
      _phone.clear();
      _address.clear();
      setState(() => _consentGranted = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${saved.fullName} ${context.l10n.text('decisionSaved')}',
          ),
        ),
      );
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}

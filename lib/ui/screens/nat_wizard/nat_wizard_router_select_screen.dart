/// NAT-Troubleshooting-Wizard — Step 2: Router identification (§27.9.2).
///
/// Full Scaffold with dropdown + detected-router preselect + "Anderes Modell"
/// fallback to the generic entry.
library;

import 'package:flutter/material.dart';

import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/network/network_stats.dart' show UpnpRouterInfo;
import 'package:cleona/core/network/router_db.dart';

class NatWizardRouterSelectScreen extends StatefulWidget {
  final RouterDb routerDb;
  final UpnpRouterInfo? detectedInfo;
  final void Function(RouterDbEntry entry) onEntrySelected;

  const NatWizardRouterSelectScreen({
    super.key,
    required this.routerDb,
    required this.detectedInfo,
    required this.onEntrySelected,
  });

  @override
  State<NatWizardRouterSelectScreen> createState() =>
      _NatWizardRouterSelectScreenState();
}

class _NatWizardRouterSelectScreenState
    extends State<NatWizardRouterSelectScreen> {
  /// Sentinel for the "Other model" dropdown option — falls through to the
  /// generic DB entry.
  static const RouterDbEntry _otherModelSentinel = RouterDbEntry(
    id: '__other__',
    displayName: '',
    manufacturerContains: <String>[],
    modelContains: <String>[],
    adminUrlHints: <String>[],
    deeplinkPath: null,
    stepsI18nKey: 'nat_wizard_steps_generic',
    notesI18nKey: 'nat_wizard_notes_generic',
  );

  RouterDbEntry? _selected;

  @override
  void initState() {
    super.initState();
    final detected = widget.detectedInfo;
    if (detected != null && !detected.isEmpty) {
      // Preselect the first matching DB entry (excluding the generic fallback
      // — match() returns it last; we want a concrete hit here).
      for (final entry in widget.routerDb.selectableEntries) {
        if (entry.matches(detected)) {
          _selected = entry;
          return;
        }
      }
    }
    // No detection → nothing preselected; user picks from dropdown.
    _selected = null;
  }

  /// Resolve the DB entry that onEntrySelected should be called with.
  /// "Other model" sentinel routes to the generic fallback entry.
  RouterDbEntry _resolveGeneric() {
    for (final entry in widget.routerDb.entries) {
      if (entry.manufacturerContains.isEmpty &&
          entry.modelContains.isEmpty) {
        return entry;
      }
    }
    // No generic entry present → fall back to the sentinel (still has
    // generic i18n keys so the next screen renders).
    return _otherModelSentinel;
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.of(context);
    final theme = Theme.of(context);
    final detected = widget.detectedInfo;
    final hasDetected = detected != null && !detected.isEmpty;

    final entries = widget.routerDb.selectableEntries;

    return Scaffold(
      appBar: AppBar(title: Text(locale.get('nat_wizard_title'))),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                locale.get('nat_wizard_router_question'),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              if (hasDetected)
                Card(
                  color: theme.colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.router,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            locale.tr('nat_wizard_detected', {
                              'manufacturer': detected.manufacturer ?? '',
                              'model': detected.modelName ?? '',
                            }).trim(),
                            style: TextStyle(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (hasDetected) const SizedBox(height: 16),
              DropdownButtonFormField<RouterDbEntry>(
                initialValue: _selected,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: locale.get('nat_wizard_router_question'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  ...entries.map(
                    (e) => DropdownMenuItem<RouterDbEntry>(
                      value: e,
                      child: Text(e.displayName, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  DropdownMenuItem<RouterDbEntry>(
                    value: _otherModelSentinel,
                    child: Text(locale.get('nat_wizard_other_model')),
                  ),
                ],
                onChanged: (v) => setState(() => _selected = v),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _selected == null
                      ? null
                      : () {
                          final target = identical(_selected, _otherModelSentinel)
                              ? _resolveGeneric()
                              : _selected!;
                          widget.onEntrySelected(target);
                        },
                  child: Text(locale.get('nat_wizard_continue')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:cleona/core/i18n/app_locale.dart';

/// Language selector button for the AppBar.
/// Shows the current locale's flag, opens a popup to switch languages.
class LanguageSelector extends StatelessWidget {
  const LanguageSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = AppLocale.read(context);

    return PopupMenuButton<String>(
      onSelected: (code) => locale.setLocale(code),
      tooltip: '',
      offset: const Offset(0, 40),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          locale.current.flag,
          style: const TextStyle(fontSize: 20),
        ),
      ),
      itemBuilder: (_) => supportedLocales.map((info) {
        final isSelected = info.code == locale.currentLocale;
        return PopupMenuItem<String>(
          value: info.code,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(info.flag, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Text(
                info.nativeName,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 8),
                Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }
}

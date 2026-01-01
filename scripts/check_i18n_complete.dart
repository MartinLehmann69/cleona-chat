#!/usr/bin/env dart
// Verifies that every translation key in lib/core/i18n/translations.dart
// covers all 33 supported locales. Exits 1 on the first missing coverage.
//
// Usage:
//   dart scripts/check_i18n_complete.dart
//
// The Cleona project deliberately does not support an EN-fallback pattern for
// new i18n keys: every key must carry a real translation in every supported
// locale. See Cleona_Chat_Architecture_v2_2.md §13.
//
// Add this as a pre-commit / pre-push hook and a CI gate to prevent the
// regression where new keys ship with only DE/EN (or DE/EN/ES/FR).

import 'dart:io';

const List<String> expectedLocales = [
  'de', 'en', 'es', 'hu', 'sv', 'ar', 'he', 'fa', 'fr', 'it', 'pt', 'nl',
  'pl', 'ro', 'cs', 'sk', 'hr', 'bg', 'el', 'da', 'fi', 'no', 'uk', 'ru',
  'tr', 'zh', 'ja', 'ko', 'hi', 'th', 'vi', 'id', 'ms',
];

void main(List<String> args) {
  final path = args.isNotEmpty ? args.first : 'lib/core/i18n/translations.dart';
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('ERROR: $path not found');
    exit(2);
  }
  final expectedSet = expectedLocales.toSet();
  final keyLinePattern = RegExp(r"^\s*'([a-z_]+)':\s*\{(.*)\},?\s*$");
  final localePattern = RegExp(r"'([a-z]{2})'\s*:");

  final issues = <String>[];
  var keyCount = 0;
  var lineNo = 0;
  for (final line in file.readAsLinesSync()) {
    lineNo++;
    final m = keyLinePattern.firstMatch(line);
    if (m == null) continue;
    keyCount++;
    final key = m.group(1)!;
    final body = m.group(2)!;
    final found = localePattern.allMatches(body).map((mm) => mm.group(1)!).toSet();
    final unknown = found.difference(expectedSet);
    if (unknown.isNotEmpty) {
      issues.add('$path:$lineNo: $key has unknown locale(s): ${unknown.toList()..sort()}');
    }
    final missing = expectedSet.difference(found);
    if (missing.isNotEmpty) {
      issues.add('$path:$lineNo: $key is missing ${missing.length} locale(s): ${missing.toList()..sort()}');
    }
  }

  stdout.writeln('Checked $keyCount keys across ${expectedLocales.length} locales.');
  if (issues.isEmpty) {
    stdout.writeln('OK: every key has all ${expectedLocales.length} locales.');
    exit(0);
  }
  stderr.writeln('i18n coverage check FAILED with ${issues.length} issue(s):\n');
  for (final issue in issues) {
    stderr.writeln('  $issue');
  }
  stderr.writeln('\nCleona does not permit EN-fallback for new keys. Add real translations');
  stderr.writeln('for every supported locale (see Cleona_Chat_Architecture_v2_2.md §13).');
  exit(1);
}

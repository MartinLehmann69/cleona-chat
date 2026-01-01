#!/usr/bin/env dart
// Verifies that every translation key in lib/core/i18n/translations.dart
// covers all 34 supported locales. Exits 1 on the first missing coverage.
//
// Usage:
//   dart scripts/check_i18n_complete.dart
//
// The Cleona project deliberately does not support an EN-fallback pattern for
// new i18n keys: every key must carry a real translation in every supported
// locale. See Cleona_Chat_Architecture_v3_0.md §17.
//
// Add this as a pre-commit / pre-push hook and a CI gate to prevent the
// regression where new keys ship with only DE/EN (or DE/EN/ES/FR).

import 'dart:io';

const List<String> expectedLocales = [
  'de', 'en', 'es', 'hu', 'sv', 'ar', 'he', 'fa', 'fr', 'it', 'pt', 'nl',
  'pl', 'ro', 'cs', 'sk', 'hr', 'sr', 'bg', 'el', 'da', 'fi', 'no', 'uk', 'ru',
  'tr', 'zh', 'ja', 'ko', 'hi', 'th', 'vi', 'id', 'ms',
];

/// Bracket balance of a line, strings excluded.
///
/// Without the string exception every `{name}` placeholder in a value counts
/// as an opening bracket and the entry seems never to end. Single
/// quotation marks delimit the values, `\\` escapes the next character.
int _braceDepth(String line) {
  var depth = 0;
  String? quote; // which quote character delimits the open string
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (quote != null) {
      if (c == '\\') {
        i++; // skip escaped character
      } else if (c == quote) {
        quote = null;
      }
      continue;
    }
    if (c == "'" || c == '"') {
      // BOTH forms. Dart allows them equivalently, and the file uses that:
      // 20 values are in double quotation marks because they themselves contain an
      // apostrophe (e.g. uk \"З\'єднання\"). A scanner that only knows
      // the single form counts one quotation mark too many there,
      // takes the rest of the line for an open string and loses
      // the bracket balance — measured: 540 of 1074 entries were lost
      // that way.
      quote = c;
    } else if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
    }
  }
  return depth;
}

void main(List<String> args) {
  final path = args.isNotEmpty ? args.first : 'lib/core/i18n/translations.dart';
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('ERROR: $path not found');
    exit(2);
  }
  final expectedSet = expectedLocales.toSet();
  // DIGITS BELONG IN THE CLASS (2026-08-17). Previously this read
  // `[a-z_]+` — every key with a digit in its name was invisible to this
  // linter. Measured, that was 49 keys (`weekday_1` ff.,
  // `nat_wizard_notes_fritzbox_7590` ff.), and 15 of them actually had
  // only 5 of the 34 locales. The gate that is meant to enforce working rule 7 thus
  // never looked at this spot — and nevertheless reported "OK".
  // UPPERCASE LETTERS LIKEWISE BELONG IN THE CLASS (2026-08-17). The tree
  // contains exactly ONE camelCase key, `updateInNetworkButton` — and
  // that one of all was missing `sr`. A class that only knows lowercase letters
  // overlooks it completely.
  final keyLinePattern = RegExp(r"^\s*'([A-Za-z0-9_]+)':\s*\{(.*)\},?\s*$", dotAll: true);
  final localePattern = RegExp(r"'([a-z]{2})'\s*:");
  // Value per locale, for the emptiness check below. Escaped characters (\' , \n)
  // must be read along, otherwise the value breaks off at the first apostrophe.
  final localeValuePattern = RegExp(r"'([a-z]{2})': '((?:[^'\\]|\\.)*)'");

  final issues = <String>[];
  var keyCount = 0;

  // MULTI-LINE ENTRIES (2026-08-17). Previously this linter read line by
  // line and required key AND closing bracket in the same one —
  // an entry whose values are wrapped over several lines was thus
  // invisible. Measured: 1074 entries in the file, 974 single-line, so
  // **100 never checked**, and in exactly these 100 lay all 27 entries
  // incomplete at the time (the NAT wizard instructions with 5 instead of 34
  // locales). The linter nevertheless reported "OK".
  //
  // Joining starts at the header line, until the curly braces are
  // balanced. The count ignores brackets INSIDE
  // strings — `{name}`/`{count}` placeholders occur 2263 times in values,
  // a naive counter would have broken on them immediately.
  final lines = file.readAsLinesSync();
  for (var i = 0; i < lines.length; i++) {
    final head = RegExp(r"^\s*'([A-Za-z0-9_]+)':\s*\{").firstMatch(lines[i]);
    if (head == null) continue;
    final startLine = i + 1;
    final buf = StringBuffer(lines[i]);
    var depth = _braceDepth(lines[i]);
    while (depth > 0 && i + 1 < lines.length) {
      i++;
      buf.write(lines[i]);
      depth += _braceDepth(lines[i]);
    }
    final joined = buf.toString();
    final m = keyLinePattern.firstMatch(joined);
    if (m == null) {
      issues.add('$path:$startLine: ${head.group(1)} — Eintrag nicht lesbar '
          '(Klammern ausgeglichen, aber Form unerwartet)');
      continue;
    }
    final lineNo = startLine;
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
    // MIXED EMPTINESS (2026-08-17). An empty value is permissible if it is empty in
    // EVERY language — the NAT wizard notes use that as
    // "this router model has no additional notes", and the consumer
    // explicitly evaluates it that way (`hasNotes = notesRaw.isNotEmpty && ...`,
    // `nat_wizard_instructions_screen.dart`). Impermissible is the mix:
    // text in one language, empty in another, is exactly the
    // EN fallback that working rule 7 forbids — only invisible to a
    // pure completeness check. Without this rule "fill up with empty
    // strings" would be a way to get the gate green without
    // translating. Measured on installation: 0 occurrences in the tree.
    final values = <String, String>{};
    for (final vm in localeValuePattern.allMatches(body)) {
      values[vm.group(1)!] = vm.group(2)!;
    }
    final empty = values.entries.where((e) => e.value.isEmpty).map((e) => e.key).toList()
      ..sort();
    if (empty.isNotEmpty && empty.length != values.length) {
      issues.add('$path:$lineNo: $key is empty in ${empty.length} of ${values.length} '
          'locale(s) but has text in the rest: $empty — either translate all or leave all empty');
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
  stderr.writeln('for every supported locale (see Cleona_Chat_Architecture_v3_0.md §17).');
  exit(1);
}

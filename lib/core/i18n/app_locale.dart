import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cleona/core/i18n/translations.dart';

/// Supported locales with their flag emoji and native name.
class LocaleInfo {
  final String code;
  final String flag;
  final String nativeName;
  final bool isRtl;
  const LocaleInfo(this.code, this.flag, this.nativeName, {this.isRtl = false});
}

const supportedLocales = [
  // ── Original 5 ──
  LocaleInfo('de', '\u{1F1E9}\u{1F1EA}', 'Deutsch'),
  LocaleInfo('en', '\u{1F1EC}\u{1F1E7}', 'English'),
  LocaleInfo('es', '\u{1F1EA}\u{1F1F8}', 'Español'),
  LocaleInfo('hu', '\u{1F1ED}\u{1F1FA}', 'Magyar'),
  LocaleInfo('sv', '\u{1F1F8}\u{1F1EA}', 'Svenska'),
  // ── RTL ──
  LocaleInfo('ar', '\u{1F1F8}\u{1F1E6}', '\u0627\u0644\u0639\u0631\u0628\u064A\u0629', isRtl: true),
  LocaleInfo('he', '\u{1F1EE}\u{1F1F1}', '\u05E2\u05D1\u05E8\u05D9\u05EA', isRtl: true),
  LocaleInfo('fa', '\u{1F1EE}\u{1F1F7}', '\u0641\u0627\u0631\u0633\u06CC', isRtl: true),
  // ── Europe ──
  LocaleInfo('fr', '\u{1F1EB}\u{1F1F7}', 'Fran\u00E7ais'),
  LocaleInfo('it', '\u{1F1EE}\u{1F1F9}', 'Italiano'),
  LocaleInfo('pt', '\u{1F1E7}\u{1F1F7}', 'Portugu\u00EAs'),
  LocaleInfo('nl', '\u{1F1F3}\u{1F1F1}', 'Nederlands'),
  LocaleInfo('pl', '\u{1F1F5}\u{1F1F1}', 'Polski'),
  LocaleInfo('ro', '\u{1F1F7}\u{1F1F4}', 'Rom\u00E2n\u0103'),
  LocaleInfo('cs', '\u{1F1E8}\u{1F1FF}', '\u010Ce\u0161tina'),
  LocaleInfo('sk', '\u{1F1F8}\u{1F1F0}', 'Sloven\u010Dina'),
  LocaleInfo('hr', '\u{1F1ED}\u{1F1F7}', 'Hrvatski'),
  LocaleInfo('bg', '\u{1F1E7}\u{1F1EC}', '\u0411\u044A\u043B\u0433\u0430\u0440\u0441\u043A\u0438'),
  LocaleInfo('el', '\u{1F1EC}\u{1F1F7}', '\u0395\u03BB\u03BB\u03B7\u03BD\u03B9\u03BA\u03AC'),
  LocaleInfo('da', '\u{1F1E9}\u{1F1F0}', 'Dansk'),
  LocaleInfo('fi', '\u{1F1EB}\u{1F1EE}', 'Suomi'),
  LocaleInfo('no', '\u{1F1F3}\u{1F1F4}', 'Norsk'),
  LocaleInfo('uk', '\u{1F1FA}\u{1F1E6}', '\u0423\u043A\u0440\u0430\u0457\u043D\u0441\u044C\u043A\u0430'),
  LocaleInfo('ru', '\u{1F1F7}\u{1F1FA}', '\u0420\u0443\u0441\u0441\u043A\u0438\u0439'),
  LocaleInfo('tr', '\u{1F1F9}\u{1F1F7}', 'T\u00FCrk\u00E7e'),
  // ── Asia ──
  LocaleInfo('zh', '\u{1F1E8}\u{1F1F3}', '\u4E2D\u6587'),
  LocaleInfo('ja', '\u{1F1EF}\u{1F1F5}', '\u65E5\u672C\u8A9E'),
  LocaleInfo('ko', '\u{1F1F0}\u{1F1F7}', '\u{D55C}\u{AD6D}\u{C5B4}'),
  LocaleInfo('hi', '\u{1F1EE}\u{1F1F3}', '\u0939\u093F\u0928\u094D\u0926\u0940'),
  LocaleInfo('th', '\u{1F1F9}\u{1F1ED}', '\u0E44\u0E17\u0E22'),
  LocaleInfo('vi', '\u{1F1FB}\u{1F1F3}', 'Ti\u1EBFng Vi\u1EC7t'),
  LocaleInfo('id', '\u{1F1EE}\u{1F1E9}', 'Bahasa Indonesia'),
  LocaleInfo('ms', '\u{1F1F2}\u{1F1FE}', 'Bahasa Melayu'),
];

const _prefsKey = 'cleona_locale';

/// Locale manager with ChangeNotifier for live UI updates.
class AppLocale extends ChangeNotifier {
  String _locale;

  AppLocale._(this._locale);

  /// Create with system language detection.
  /// Falls back to 'en' if system language is not supported.
  factory AppLocale() {
    final systemLocale = _detectSystemLocale();
    return AppLocale._(systemLocale);
  }

  /// Detect system locale code. Returns supported code or 'en'.
  static String _detectSystemLocale() {
    try {
      final lang = Platform.localeName.split('_').first.split('.').first.toLowerCase();
      if (supportedLocales.any((l) => l.code == lang)) return lang;
    } catch (_) {}
    return 'en';
  }

  /// Load saved locale from SharedPreferences (call once at startup).
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null && supportedLocales.any((l) => l.code == saved)) {
      _locale = saved;
      notifyListeners();
    }
  }

  String get currentLocale => _locale;

  /// Current locale info (flag + name).
  LocaleInfo get current => supportedLocales.firstWhere((l) => l.code == _locale);

  /// Whether the current locale is right-to-left (Arabic, Hebrew, Farsi).
  bool get isRtl => current.isRtl;

  /// TextDirection for the current locale (used by Directionality widget).
  TextDirection get textDirection => isRtl ? TextDirection.rtl : TextDirection.ltr;

  /// Switch locale and persist.
  Future<void> setLocale(String code) async {
    if (code == _locale) return;
    if (!supportedLocales.any((l) => l.code == code)) return;
    _locale = code;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, code);
  }

  /// Get translated string. Falls back: current locale → 'en' → 'de' → key.
  String get(String key) {
    final entry = translations[key];
    if (entry == null) return key;
    return entry[_locale] ?? entry['en'] ?? entry['de'] ?? key;
  }

  /// Get translated string with placeholder substitution.
  /// Replaces {name}, {count}, {size}, {error}, {summary} etc.
  String tr(String key, [Map<String, String>? params]) {
    var text = get(key);
    if (params != null) {
      for (final e in params.entries) {
        text = text.replaceAll('{${e.key}}', e.value);
      }
    }
    return text;
  }

  /// Access with rebuild on locale change — use in build() methods.
  static AppLocale of(BuildContext context) {
    return context.watch<AppLocale>();
  }

  /// Read-only access (no rebuild) — use in callbacks, async methods.
  static AppLocale read(BuildContext context) {
    return context.read<AppLocale>();
  }
}

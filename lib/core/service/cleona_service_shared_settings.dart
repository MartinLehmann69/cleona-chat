// Twin-sync Type 8 SETTINGS_CHANGED (v4_2 §14.7, D-71, D-72) and the
// "shared settings" of the enrolment handover (§14.6.2): what the identity
// decides and a contact notices holds on every own device — the
// transcription language (§21.7), per contact "allow calls" (§17, RL-7),
// the self-declaration `isAdult` and the opt-in "evaluate channel reports"
// (§15.10). Each value travels with the time of its change, and the later
// change wins. Nothing else travels here: never a path, a model, a sound or
// a network setting, and not "never a fixed neighbour" (D-26, local).
//
// The values stay where they always lived (transcription settings, the
// identity record of the device database, the contact record); this part
// keeps only the time of each value's last change, in the identity's store.
//
// Wire form (JSON), one message per change, only the changed values:
//   {"transcriptionLanguage": "de", "isAdult": true, "reviewEnabled": false,
//    "callsAllowed": {"<contact hex>": false},
//    "at": {"transcriptionLanguage": <ms>, "callsAllowed:<contact hex>": <ms>}}
// A v4.2.3 device reads `transcriptionLanguage` only and discards the rest
// (`398a6e40:lib/core/service/cleona_service.dart:9844-9859`); it sends the
// language without `at`.

part of 'cleona_service.dart';

/// The store area holding the time of each shared value's last change.
const String _kSharedSettingsArea = 'shared_settings';

const String _kSharedLanguage = 'transcriptionLanguage';
const String _kSharedAdult = 'isAdult';
const String _kSharedReview = 'reviewEnabled';
const String _kSharedCalls = 'callsAllowed';
const String _kSharedAt = 'at';

extension CleonaServiceSharedSettings on CleonaService {
  /// The key under which the time of "allow calls" for [contactHex] is kept
  /// and travels in `at`.
  static String _callsKey(String contactHex) => '$_kSharedCalls:$contactHex';

  /// Sets the self-declaration `isAdult` of this identity (§15.10) and tells
  /// the other own devices (Type 8). Switching it off switches the opt-in
  /// "evaluate channel reports" off as well, in the same message — the
  /// opt-in is offered only to an adult (identity screen).
  bool _sharedIsAdultSet(bool adult) {
    final changed = <String, dynamic>{};
    if (identity.isAdult != adult) changed[_kSharedAdult] = adult;
    if (!adult && identity.reviewEnabled) changed[_kSharedReview] = false;
    if (changed.isEmpty) return true;
    _identityFlagsStore(
        adult: changed[_kSharedAdult] as bool?,
        review: changed[_kSharedReview] as bool?);
    _sharedSend(changed);
    onStateChanged?.call();
    return true;
  }

  /// Sets the opt-in "evaluate channel reports" of this identity (§15.10,
  /// §16.5) and tells the other own devices (Type 8).
  bool _sharedReviewSet(bool enabled) {
    if (identity.reviewEnabled == enabled) return true;
    _identityFlagsStore(review: enabled);
    _sharedSend({_kSharedReview: enabled});
    onStateChanged?.call();
    return true;
  }

  /// Tells the other own devices that "allow calls" for [contactHex] is now
  /// [allowed] (D-71). The caller has stored it already.
  void _sharedCallsAllowedSend(String contactHex, bool allowed) =>
      _sharedSend({
        _kSharedCalls: {contactHex: allowed}
      });

  /// Tells the other own devices the transcription language [language]
  /// (§21.7). The caller has stored it already.
  void _sharedLanguageSend(String language) {
    if (sharedSettingsAs423) {
      // A v4.2.3 device sends the language alone, without a time.
      _sendTwinSync(proto.TwinSyncType.SETTINGS_CHANGED,
          Uint8List.fromList(
              utf8.encode(jsonEncode({_kSharedLanguage: language}))));
      return;
    }
    _sharedSend({_kSharedLanguage: language});
  }

  /// Keeps the time of the change of every value in [values] and sends them
  /// as one Type 8. `_sendTwinSync` sends nothing while this is the only
  /// device; the time is kept anyway — it travels with the handover.
  void _sharedSend(Map<String, dynamic> values) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final at = <String, int>{for (final k in _sharedKeysOf(values)) k: now};
    for (final e in at.entries) {
      store.putEntry(_kSharedSettingsArea, e.key, {_kSharedAt: e.value});
    }
    _sendTwinSync(proto.TwinSyncType.SETTINGS_CHANGED,
        Uint8List.fromList(utf8.encode(jsonEncode({
      ...values,
      _kSharedAt: at,
    }))));
  }

  /// The time keys of the values in [values] (`callsAllowed` per contact).
  Iterable<String> _sharedKeysOf(Map<String, dynamic> values) sync* {
    for (final k in const [_kSharedLanguage, _kSharedAdult, _kSharedReview]) {
      if (values.containsKey(k)) yield k;
    }
    final calls = values[_kSharedCalls];
    if (calls is Map) {
      for (final hex in calls.keys) {
        yield _callsKey(hex as String);
      }
    }
  }

  /// §14.6.2 "shared settings": every shared value this device holds, each
  /// with the time of its last change (0 = never changed here), in the form
  /// of Type 8 — the new device takes it with [_sharedApply].
  Map<String, dynamic> _sharedSnapshot() {
    final times = store.loadArea(_kSharedSettingsArea);
    int timeOf(String k) => (times[k]?[_kSharedAt] as num?)?.toInt() ?? 0;
    final calls = <String, bool>{
      for (final c in _contacts.values)
        if (times.containsKey(_callsKey(c.nodeIdHex)) || !c.callsAllowed)
          c.nodeIdHex: c.callsAllowed,
    };
    final values = <String, dynamic>{
      _kSharedLanguage:
          VoiceTranscriptionSettings.readFrom(store)?.defaultLanguage ?? 'auto',
      _kSharedAdult: identity.isAdult,
      _kSharedReview: identity.reviewEnabled,
      if (calls.isNotEmpty) _kSharedCalls: calls,
    };
    return {
      ...values,
      _kSharedAt: {for (final k in _sharedKeysOf(values)) k: timeOf(k)},
    };
  }

  /// Takes the shared values of [json] (Type 8 or the handover's `shared`)
  /// where each is later than the change this device holds; a value without
  /// a time (a v4.2.3 sender) counts as changed at its arrival. Returns the
  /// number of values taken. Only field names are logged, never values.
  int _sharedApply(Map<String, dynamic> json, {required String from}) {
    final atRaw = json[_kSharedAt];
    final at = atRaw is Map ? atRaw.cast<String, dynamic>() : const {};
    final times = store.loadArea(_kSharedSettingsArea);
    final arrival = DateTime.now().millisecondsSinceEpoch;
    final taken = <String>[];
    final older = <String>[];
    bool later(String key) {
      final incoming = (at[key] as num?)?.toInt() ?? arrival;
      final held = (times[key]?[_kSharedAt] as num?)?.toInt();
      if (held != null && incoming <= held) {
        older.add(key);
        return false;
      }
      store.putEntry(_kSharedSettingsArea, key, {_kSharedAt: incoming});
      taken.add(key);
      return true;
    }

    final language = json[_kSharedLanguage];
    if (language is String && later(_kSharedLanguage)) {
      _transcriptionLanguageStore(language);
    }
    final adult = json[_kSharedAdult];
    final review = json[_kSharedReview];
    final adultTaken = adult is bool && later(_kSharedAdult);
    final reviewTaken = review is bool && later(_kSharedReview);
    if (adultTaken || reviewTaken) {
      _identityFlagsStore(
          adult: adultTaken ? adult : null,
          review: reviewTaken ? review : null);
    }
    final calls = json[_kSharedCalls];
    var contactsChanged = false;
    final unknownContacts = <String>[];
    if (calls is Map) {
      for (final e in calls.entries) {
        final hex = e.key as String;
        final allowed = e.value;
        final contact = _contacts[hex];
        if (allowed is! bool) continue;
        if (contact == null) {
          unknownContacts.add(CleonaService._hexShort(hexToBytes(hex)));
          continue;
        }
        if (!later(_callsKey(hex))) continue;
        if (contact.callsAllowed != allowed) {
          contact.callsAllowed = allowed;
          contactsChanged = true;
        }
      }
    }
    if (contactsChanged) _saveContacts();
    final unknownFields = json.keys
        .where((k) => !const {
              _kSharedLanguage,
              _kSharedAdult,
              _kSharedReview,
              _kSharedCalls,
              _kSharedAt,
            }.contains(k))
        .toList();
    _log.info('Shared settings from $from: ${taken.length} taken'
        '${taken.isEmpty ? '' : ' (${taken.map(_sharedFieldName).join(', ')})'}'
        '${older.isEmpty ? '' : ', ${older.length} older than held'}'
        '${unknownContacts.isEmpty ? '' : ', ${unknownContacts.length} for '
            'contacts not held here'}'
        '${unknownFields.isEmpty ? '' : ', unknown: ${unknownFields.join(', ')}'}');
    if (taken.isNotEmpty) onStateChanged?.call();
    return taken.length;
  }

  /// A time key without the contact it names (the log names fields only).
  static String _sharedFieldName(String key) =>
      key.startsWith('$_kSharedCalls:') ? _kSharedCalls : key;

  /// Stores `isAdult` / `reviewEnabled` of this identity: in the running
  /// service and in the identity record of the device database, which the
  /// identity screen and the daemon's state report read.
  void _identityFlagsStore({bool? adult, bool? review}) {
    if (adult != null) identity.isAdult = adult;
    if (review != null) identity.reviewEnabled = review;
    final mgr = IdentityManager();
    final record = mgr
        .loadIdentities()
        .where((i) => i.profileDir == identity.profileDir)
        .firstOrNull;
    if (record == null) {
      _log.warn('Shared settings: no identity record for this profile — '
          'isAdult/reviewEnabled held in the running service only');
      return;
    }
    if (adult != null) mgr.setIsAdult(record.id, adult);
    if (review != null) mgr.setReviewEnabled(record.id, review);
  }
}

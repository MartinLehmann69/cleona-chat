/// Typed view of `cleona_voice_report_t` — the verification report that
/// architecture §10.4 makes a **normative part of the voice ABI** (I11).
///
/// ## Why this file exists
///
/// The superseded audio stack could not answer "is the AEC actually running?"
/// even in principle. Four rounds of echo fixes (S252, S268, S278, S281) never
/// converged because every one of them was verified against the same
/// assumption it was built on. A gate derived from the same assumption as the
/// thing it checks is worthless.
///
/// So the replacement reports what it *observed*, per session, and
/// [VoiceEffectState.notDeterminable] is a legitimate answer. Nothing here ever
/// upgrades "we asked for it" to "it is enabled".
///
/// ## Deliberately free of `dart:ffi`
///
/// This file is pure Dart. `voice_session.dart` owns the FFI structs and
/// converts them into a [VoiceReport]; everything downstream — RoutePolicy
/// (V1.5), the in-call UI (V1.6), the report assertion (V1.7) — can therefore
/// be unit-tested without a native library present.
library;

import 'package:cleona/core/network/clogger.dart';

/// State of one OS voice effect, as **read back** from the platform.
///
/// Never inferred from a successful "enable" call: asking is not evidence.
enum VoiceEffectState {
  /// The chain does not offer this effect on this device.
  unavailable(0, 'unavailable'),

  /// The effect exists and was verifiably read back as NOT running.
  availableOff(1, 'available_off'),

  /// The effect exists and was verifiably read back as running.
  enabled(2, 'enabled'),

  /// The platform offers no way to read the state back.
  ///
  /// Architecture §10.4 names this value `not_determinable` and permits it
  /// explicitly. It is not an error and must never be reported as
  /// [VoiceEffectState.enabled].
  notDeterminable(3, 'not_determinable'),

  /// The backend returned a value outside the four defined states. That is a
  /// conformance defect of the backend, surfaced rather than laundered into
  /// one of the legitimate answers.
  invalid(-1, 'invalid');

  const VoiceEffectState(this.wireValue, this.logName);

  /// Value of the matching `CLEONA_VOICE_FX_*` constant.
  final int wireValue;

  /// Token used in the one-line report. Stable — E2E asserts on it (V1.7).
  final String logName;

  static VoiceEffectState fromWire(int v) {
    for (final s in values) {
      if (s != invalid && s.wireValue == v) return s;
    }
    return invalid;
  }
}

/// Where the voice chain comes from (`CLEONA_VOICE_CHAIN_*`).
enum VoiceChainOrigin {
  none(0, 'none'),
  androidHal(1, 'android_hal'),
  appleVpio(2, 'apple_vpio'),
  windowsEndpoint(3, 'win_endpoint'),
  windowsVoiceDsp(4, 'win_voice_dsp'),
  pipewireFilter(5, 'pipewire_filter'),
  linkedApm(6, 'linked_apm'),

  /// The hardware-free mock. Deliberately out of band (100) so that a mock can
  /// never impersonate a real chain in a report, and so that
  /// "no shipped build reports a mock chain" is a checkable release gate.
  mock(100, 'mock'),

  invalid(-1, 'invalid');

  const VoiceChainOrigin(this.wireValue, this.logName);
  final int wireValue;
  final String logName;

  static VoiceChainOrigin fromWire(int v) {
    for (final c in values) {
      if (c != invalid && c.wireValue == v) return c;
    }
    return invalid;
  }
}

/// Which native implementation produced the report (`CLEONA_VOICE_BACKEND_*`).
enum VoiceBackend {
  unknown(0, 'unknown'),
  pipewire(1, 'pipewire'),
  androidAudioRecord(2, 'android_audiorecord'),
  appleVpio(3, 'apple_vpio'),
  wasapi(4, 'wasapi'),
  mock(100, 'mock'),
  invalid(-1, 'invalid');

  const VoiceBackend(this.wireValue, this.logName);
  final int wireValue;
  final String logName;

  /// True for backends that must never appear in a shipped build.
  bool get isTestOnly => wireValue >= 100;

  static VoiceBackend fromWire(int v) {
    for (final b in values) {
      if (b != invalid && b.wireValue == v) return b;
    }
    return invalid;
  }
}

/// Audio route (`CLEONA_VOICE_ROUTE_*`).
enum VoiceRoute {
  /// Not resolved. Legitimate before `start()`, a defect afterwards.
  unknown(0, 'unknown'),
  earpiece(1, 'earpiece'),
  speaker(2, 'speaker'),
  wired(3, 'wired'),
  bluetooth(4, 'bluetooth'),
  invalid(-1, 'invalid');

  const VoiceRoute(this.wireValue, this.logName);
  final int wireValue;
  final String logName;

  /// Bit of this route inside `routes_available_mask`.
  int get bit => wireValue < 0 ? 0 : 1 << wireValue;

  static VoiceRoute fromWire(int v) {
    for (final r in values) {
      if (r != invalid && r.wireValue == v) return r;
    }
    return invalid;
  }

  /// Decodes a `routes_available_mask`. [VoiceRoute.unknown] is a state, not a
  /// route, and is never part of the set even if bit 0 happens to be set — a
  /// backend that sets it is reported by [VoiceReport.contractViolations].
  static Set<VoiceRoute> decodeMask(int mask) {
    final out = <VoiceRoute>{};
    for (final r in const [earpiece, speaker, wired, bluetooth]) {
      if (mask & r.bit != 0) out.add(r);
    }
    return out;
  }

  static int encodeMask(Iterable<VoiceRoute> routes) {
    var m = 0;
    for (final r in routes) {
      if (r != unknown && r != invalid) m |= r.bit;
    }
    return m;
  }
}

/// Mute state as reported by the backend (`mic_muted` / `output_muted`,
/// erratum E6a, architecture §10.4).
///
/// Unlike [VoiceEffectState], this has no legitimate "unknown" answer: per
/// `cleona_voice.h` ("A backend does not get to answer 'unknown' here the
/// way it may for an effect state: it was told the value, so it knows it"),
/// the backend was explicitly told the mute state through
/// `cleona_voice_set_mic_muted()` / `cleona_voice_set_output_muted()`, so a
/// wire value other than exactly 0 or exactly 1 is a conformance defect, not
/// a legitimate third state.
///
/// Deliberately says nothing about whether the underlying stream keeps
/// running while muted (I6) — that is `cleona_voice.h`'s conformance check
/// C5, enforced by the native harness (V0.4), not something a single report
/// snapshot can observe. [VoiceReport.contractViolations] only checks what a
/// single report can attest to.
enum VoiceMuteState {
  /// Wire value 0 — not muted.
  off(0, 'off'),

  /// Wire value 1 — muted. I6: the stream stays open regardless; this is a
  /// content flag, not a liveness signal.
  muted(1, 'muted'),

  /// The backend reported something other than 0 or 1 (erratum E6a: "exactly
  /// 0 or exactly 1"). Surfaced rather than laundered into [off] or [muted].
  invalid(-1, 'invalid');

  const VoiceMuteState(this.wireValue, this.logName);

  /// The wire value from `cleona_voice_report_t.mic_muted` /
  /// `.output_muted`. Always exactly 0 or 1 on a conformant backend.
  final int wireValue;

  /// Token used in the one-line report. Stable — E2E asserts on it.
  final String logName;

  static VoiceMuteState fromWire(int v) {
    if (v == 0) return off;
    if (v == 1) return muted;
    return invalid;
  }
}

/// The negotiated frame contract (`cleona_voice_format_t`).
///
/// Every field is what the platform **reported**. Nothing in Cleona may derive
/// these from a constant (I3, I4).
class VoiceFormat {
  const VoiceFormat({
    required this.sampleRate,
    required this.channels,
    required this.frameSamples,
    required this.frameBytes,
  });

  final int sampleRate;
  final int channels;
  final int frameSamples;
  final int frameBytes;

  /// Bounds from `cleona_voice.h` (SPEC §6 check 1). Used to *validate* what
  /// the platform reported — never as a default.
  static const int rateMin = 8000;
  static const int rateMax = 48000;
  static const int frameHz = 50; // 20 ms frames

  bool get isSelfConsistent =>
      sampleRate >= rateMin &&
      sampleRate <= rateMax &&
      channels == 1 &&
      frameSamples == sampleRate ~/ frameHz &&
      frameBytes == frameSamples * channels * 2;

  Duration get frameDuration =>
      Duration(microseconds: sampleRate == 0 ? 0 : frameSamples * 1000000 ~/ sampleRate);

  @override
  String toString() =>
      'VoiceFormat(rate: $sampleRate, ch: $channels, '
      'frameSamples: $frameSamples, frameBytes: $frameBytes)';
}

/// One session's verification report.
class VoiceReport {
  /// Not `const`: [micMuted] and [outputMuted] (erratum E6a) are derived from
  /// [rawWireValues] rather than passed as separate named parameters, so that
  /// `voice_session.dart` — which already writes `mic_muted` / `output_muted`
  /// into `rawWireValues` — needs no call-site change to feed the typed
  /// fields this class exposes.
  VoiceReport({
    required this.format,
    required this.aec,
    required this.ns,
    required this.agc,
    required this.chainOrigin,
    required this.backend,
    required this.duplex,
    required this.routeActiveIn,
    required this.routeActiveOut,
    required this.routesAvailable,
    required this.underruns,
    required this.overruns,
    this.rawWireValues = const {},
  })  : micMuted = VoiceMuteState.fromWire(rawWireValues['mic_muted'] ?? -1),
        outputMuted =
            VoiceMuteState.fromWire(rawWireValues['output_muted'] ?? -1);

  final VoiceFormat format;
  final VoiceEffectState aec;
  final VoiceEffectState ns;
  final VoiceEffectState agc;
  final VoiceChainOrigin chainOrigin;
  final VoiceBackend backend;

  /// I2: capture and playback in **one** OS session. Anything else is not
  /// acceptance-capable — without it there is no AEC.
  final bool duplex;

  final VoiceRoute routeActiveIn;
  final VoiceRoute routeActiveOut;
  final Set<VoiceRoute> routesAvailable;
  final int underruns;
  final int overruns;

  /// Microphone mute, as last set through `cleona_voice_set_mic_muted()` and
  /// read back from the backend (erratum E6a). [VoiceMuteState.muted] is a
  /// legitimate steady state, not a defect — I6 requires the capture stream
  /// to keep running regardless.
  final VoiceMuteState micMuted;

  /// Output mute, as last set through `cleona_voice_set_output_muted()` and
  /// read back from the backend (erratum E6a). [VoiceMuteState.muted] means
  /// the playback stream renders silence; it keeps running (I6).
  final VoiceMuteState outputMuted;

  /// Raw integers as they came off the ABI. Populated by the FFI layer so that
  /// a value outside the defined range can be *named* in a violation message
  /// instead of merely being called invalid. Empty for hand-built reports.
  final Map<String, int> rawWireValues;

  /// The effects that are not [VoiceEffectState.enabled].
  ///
  /// Architecture §10.4: accepting a backend means "conformance test green +
  /// report logged + **for every effect that is not enabled, a documented
  /// reason**". This getter is what that checklist is built from.
  Map<String, VoiceEffectState> get effectsNeedingJustification => {
        if (aec != VoiceEffectState.enabled) 'aec': aec,
        if (ns != VoiceEffectState.enabled) 'ns': ns,
        if (agc != VoiceEffectState.enabled) 'agc': agc,
      };

  /// Contract checks that can be made from the report alone.
  ///
  /// Returns an empty list when the report is conformant. Mirrors the parts of
  /// SPEC §6 that do not need a live session, so that V0.4's C harness and the
  /// Dart side cannot drift apart on what "conformant" means.
  List<String> contractViolations() {
    final v = <String>[];

    if (!duplex) {
      v.add('duplex=0: capture and playback are not in one OS session (I2)');
    }
    if (!format.isSelfConsistent) {
      v.add('format not self-consistent: $format '
          '(expected 1 channel, ${VoiceFormat.rateMin}-${VoiceFormat.rateMax} Hz, '
          'frameSamples == rate/${VoiceFormat.frameHz}, frameBytes == frameSamples*ch*2)');
    }
    for (final e in {'aec': aec, 'ns': ns, 'agc': agc}.entries) {
      if (e.value == VoiceEffectState.invalid) {
        final raw = rawWireValues[e.key];
        v.add('${e.key}_state is outside the four defined states'
            '${raw == null ? '' : ' (raw=$raw)'}');
      }
    }
    final anyEnabled = aec == VoiceEffectState.enabled ||
        ns == VoiceEffectState.enabled ||
        agc == VoiceEffectState.enabled;
    if (anyEnabled && chainOrigin == VoiceChainOrigin.none) {
      v.add('an effect is ENABLED but chain_origin is none — an enabled effect '
          'with no stated origin is exactly the unfalsifiable claim this '
          'report exists to eliminate');
    }
    if (chainOrigin == VoiceChainOrigin.invalid) {
      final raw = rawWireValues['chain_origin'];
      v.add('chain_origin is not a defined value${raw == null ? '' : ' (raw=$raw)'}');
    }
    if (backend == VoiceBackend.invalid) {
      final raw = rawWireValues['backend'];
      v.add('backend is not a defined value${raw == null ? '' : ' (raw=$raw)'}');
    }
    if (routeActiveOut == VoiceRoute.unknown) {
      v.add('route_active_out is unknown on a reporting session');
    } else if (routeActiveOut != VoiceRoute.invalid &&
        !routesAvailable.contains(routeActiveOut)) {
      v.add('active output route ${routeActiveOut.logName} is not in the '
          'available mask (SPEC §6 check 8)');
    }
    final rawMask = rawWireValues['routes_available_mask'];
    if (rawMask != null && rawMask & VoiceRoute.unknown.bit != 0) {
      v.add('routes_available_mask contains ROUTE_UNKNOWN — unknown is a '
          'state, not a route');
    }
    // Erratum E6a: mic_muted / output_muted must be exactly 0 or 1 — the
    // backend was told the value, so unlike the effect states above it has no
    // legitimate "unknown" answer here (cleona_voice.h). VoiceMuteState.muted
    // itself is NOT a violation: I6 requires the stream to stay open while
    // muted, so a muted-but-running session is the correct state.
    if (micMuted == VoiceMuteState.invalid) {
      final raw = rawWireValues['mic_muted'];
      v.add('mic_muted is outside {0,1}${raw == null ? '' : ' (raw=$raw)'}');
    }
    if (outputMuted == VoiceMuteState.invalid) {
      final raw = rawWireValues['output_muted'];
      v.add(
          'output_muted is outside {0,1}${raw == null ? '' : ' (raw=$raw)'}');
    }
    return v;
  }

  bool get isConformant => contractViolations().isEmpty;

  /// Prefix of the single log line. E2E (V1.7) greps for this.
  static const String logTag = 'VOICE_REPORT';

  /// Renders the report as **one** line of stable `key=value` pairs.
  ///
  /// One line per call, no more: the report is diagnostic, not a stream. The
  /// format is machine-parseable ([parseLogLine]) so V1.7 can assert the field
  /// structure without re-implementing it here.
  String toLogLine({required String callId}) {
    final routes = routesAvailable.isEmpty
        ? 'none'
        : (routesAvailable.toList()
              ..sort((a, b) => a.wireValue.compareTo(b.wireValue)))
            .map((r) => r.logName)
            .join('|');
    final violations = contractViolations();
    return '$logTag '
        'call=${_sanitize(callId)} '
        'backend=${backend.logName} '
        'chain=${chainOrigin.logName} '
        'duplex=${duplex ? 1 : 0} '
        'rate=${format.sampleRate} '
        'ch=${format.channels} '
        'frame_samples=${format.frameSamples} '
        'frame_bytes=${format.frameBytes} '
        'aec=${aec.logName} '
        'ns=${ns.logName} '
        'agc=${agc.logName} '
        'route_in=${routeActiveIn.logName} '
        'route_out=${routeActiveOut.logName} '
        'routes=$routes '
        'mic_muted=${micMuted.logName} '
        'output_muted=${outputMuted.logName} '
        'underruns=$underruns '
        'overruns=$overruns '
        'conformant=${violations.isEmpty ? 'yes' : 'no'} '
        'violations=${violations.isEmpty ? 0 : violations.length}';
  }

  /// Parses a line produced by [toLogLine] into its key/value pairs.
  ///
  /// Returns `null` when the line is not a report line. Provided so the E2E
  /// assertion in V1.7 checks the *agreed* structure rather than a copy of it
  /// that can drift.
  static Map<String, String>? parseLogLine(String line) {
    final idx = line.indexOf('$logTag ');
    if (idx < 0) return null;
    final body = line.substring(idx + logTag.length + 1);
    final out = <String, String>{};
    for (final token in body.split(' ')) {
      if (token.isEmpty) continue;
      final eq = token.indexOf('=');
      if (eq <= 0) continue;
      out[token.substring(0, eq)] = token.substring(eq + 1);
    }
    return out.isEmpty ? null : out;
  }

  /// Keys every report line carries. V1.7 asserts against this set.
  static const List<String> logLineKeys = [
    'call', 'backend', 'chain', 'duplex', 'rate', 'ch',
    'frame_samples', 'frame_bytes', 'aec', 'ns', 'agc',
    'route_in', 'route_out', 'routes', 'mic_muted', 'output_muted',
    'underruns', 'overruns', 'conformant', 'violations',
  ];

  static String _sanitize(String s) {
    final cleaned = s.replaceAll(RegExp(r'[\s=]+'), '_');
    return cleaned.isEmpty ? 'unknown' : cleaned;
  }

  @override
  String toString() => toLogLine(callId: '-');
}

/// Emits **exactly one** report line per call, into the profile's log file.
///
/// ## The mistake this class exists to make impossible
///
/// `CLogger` only writes to a file when it was given a `profileDir`
/// (`clogger.dart:187`): without one, a line reaches the console and the crash
/// ring and **no log file at all**. The old `VideoEngine` constructed
/// `CLogger('VideoEngine')` with no `profileDir`
/// (`video_engine.dart:272`), so every line it ever produced was invisible in
/// the field — which is why video was, in principle, not diagnosable.
///
/// Repeating that here would be worse: the verification report is the *only*
/// evidence that the OS voice chain is engaged. A report that lands nowhere is
/// indistinguishable from a report that was never produced.
///
/// The defence is structural, not a convention:
/// * [profileDir] is a **required, non-nullable** constructor argument;
/// * there is **no** constructor or setter that accepts a pre-built `CLogger`,
///   so a caller cannot smuggle in a `profileDir`-less one;
/// * an empty [profileDir] trips an assertion in debug and is rejected in
///   release, because `CLogger` would treat `''` as a distinct sink rather
///   than as "no profile".
///
/// V1.7 builds the E2E assertion on top of this: it finds the line in
/// `files/.cleona/logs/` and checks the field structure via
/// [VoiceReport.parseLogLine].
class VoiceReportLogger {
  VoiceReportLogger({required String profileDir, required this.callId})
      : assert(profileDir.isNotEmpty,
            'profileDir must not be empty — an empty sink key writes nowhere '
            'useful and reproduces the VideoEngine defect'),
        _profileDir = profileDir,
        _log = CLogger.get(logModule, profileDir: profileDir) {
    if (_profileDir.isEmpty) {
      throw ArgumentError.value(
        profileDir,
        'profileDir',
        'VoiceReportLogger requires a real profile directory: without it the '
            'verification report never reaches a log file (clogger.dart:187)',
      );
    }
  }

  /// Module name in the log line. Stable — E2E greps for it.
  static const String logModule = 'voice-report';

  final String _profileDir;

  /// Identifies the call this report belongs to. One logger per call.
  final String callId;

  final CLogger _log;

  bool _emitted = false;
  int _suppressed = 0;

  /// The profile directory this logger writes into. Exposed for diagnostics.
  String get profileDir => _profileDir;

  /// Whether the single line for this call has already been written.
  bool get hasEmitted => _emitted;

  /// How many additional attempts were suppressed. Non-zero means a caller is
  /// reporting per frame instead of per call — a bug worth seeing.
  int get suppressedCount => _suppressed;

  /// Writes the one report line for this call. Subsequent calls are ignored.
  ///
  /// Returns the line that was written, or `null` if it had already been
  /// written. Uses [CLogger.event] rather than `info` so the line survives
  /// transport noise in bug reports (§9.5.8) — it is rare and
  /// diagnostic-critical, which is exactly what the event ring is for.
  String? logOnce(VoiceReport report) {
    if (_emitted) {
      _suppressed++;
      return null;
    }
    _emitted = true;
    final line = report.toLogLine(callId: callId);
    _log.event(line);

    // Violations are logged separately and at warn level: the single report
    // line stays one line (and stays parseable), while a non-conformant
    // backend is impossible to overlook.
    for (final violation in report.contractViolations()) {
      _log.warn('$logModule call=${VoiceReport._sanitize(callId)} '
          'contract violation: $violation');
    }
    return line;
  }
}

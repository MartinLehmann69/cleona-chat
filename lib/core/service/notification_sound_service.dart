import 'dart:async';
import 'dart:io';

import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/platform/app_paths.dart';
import 'package:cleona/core/storage/message_store.dart';

/// The area of the encrypted store for the notification settings
/// (§21.4.1).
///
/// S366: up to here they lay NAKED in the profile as
/// `notification_settings.json` — listed in neither of the two plaintext
/// inventories (S363). The content is measured and not presumed
/// ([NotificationSettings]): ringtone, volume and three switches for
/// whether direct, group and channel messages are notified at all. No
/// message content and no contact identifier — but a behavioural profile,
/// and §21.4 permits no unencrypted accessories next to the store ("a
/// 'cache directory' … outside encryption is explicitly impermissible").
const String kNotificationSettingsArea = 'notification_settings';

/// The key of the ONE record.
const String kNotificationSettingsKey = '_';

/// Available ringtones for incoming calls.
enum Ringtone {
  gentle('Gentle', 'ringtone_gentle.ogg'),
  classic('Classic', 'ringtone_classic.ogg'),
  pulse('Pulse', 'ringtone_pulse.ogg'),
  chime('Chime', 'ringtone_chime.ogg'),
  echo('Echo', 'ringtone_echo.ogg'),
  bright('Bright', 'ringtone_bright.ogg');

  const Ringtone(this.displayName, this.filename);
  final String displayName;
  final String filename;

  static Ringtone fromName(String name) {
    return Ringtone.values.firstWhere(
      (r) => r.name == name,
      orElse: () => Ringtone.gentle,
    );
  }
}

/// Vibration patterns.
enum VibrationType { message, call }

/// Notification settings persisted per identity.
class NotificationSettings {
  bool soundEnabled;
  bool vibrationEnabled;
  bool messageSoundEnabled;
  Ringtone callRingtone;
  double callVolume;
  bool defaultDirectNotify;
  bool defaultGroupNotify;
  bool defaultChannelNotify;

  NotificationSettings({
    this.soundEnabled = true,
    this.vibrationEnabled = true,
    this.messageSoundEnabled = true,
    this.callRingtone = Ringtone.gentle,
    this.callVolume = 0.8,
    this.defaultDirectNotify = true,
    this.defaultGroupNotify = true,
    this.defaultChannelNotify = false,
  });

  factory NotificationSettings.fromJson(Map<String, dynamic> json) {
    return NotificationSettings(
      soundEnabled: json['soundEnabled'] as bool? ?? true,
      vibrationEnabled: json['vibrationEnabled'] as bool? ?? true,
      messageSoundEnabled: json['messageSoundEnabled'] as bool? ?? true,
      callRingtone: Ringtone.fromName(json['callRingtone'] as String? ?? 'gentle'),
      callVolume: (json['callVolume'] as num?)?.toDouble() ?? 0.8,
      defaultDirectNotify: json['defaultDirectNotify'] as bool? ?? true,
      defaultGroupNotify: json['defaultGroupNotify'] as bool? ?? true,
      defaultChannelNotify: json['defaultChannelNotify'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'soundEnabled': soundEnabled,
    'vibrationEnabled': vibrationEnabled,
    'messageSoundEnabled': messageSoundEnabled,
    'callRingtone': callRingtone.name,
    'callVolume': callVolume,
    'defaultDirectNotify': defaultDirectNotify,
    'defaultGroupNotify': defaultGroupNotify,
    'defaultChannelNotify': defaultChannelNotify,
  };

  bool defaultForType({bool isGroup = false, bool isChannel = false}) {
    if (isChannel) return defaultChannelNotify;
    if (isGroup) return defaultGroupNotify;
    return defaultDirectNotify;
  }
}

/// Manages notification sounds and vibration (§22.8).
///
/// Linux: `pw-play` (PipeWire) with `paplay` (PulseAudio) as fallback
/// (§22.6) — no Flutter dependency. Android: via platform channel.
/// Windows: the bundled helper program `cleona-play.exe`
/// (`windows/cleona_play/`), one process per sound like under Linux.
class NotificationSoundService {
  // Process log as default: until [init] runs with the real per-identity
  // profileDir, this service belongs to no identity. The daemon path calls
  // [init] and overwrites `_log` with the correct value (self-heal, see
  // below); the second construction site (`ipc_client.dart`, which never
  // calls [init] because it only MIRRORS the daemon's settings for the GUI
  // to read — it plays nothing and stores nothing; changes and previews go
  // to the daemon over IPC) stays on the process log and thus writes at
  // least into ONE file instead of none.
  CLogger _log = CLogger.get('notification_sound', profileDir: AppPaths.dataDir);

  NotificationSettings _settings = NotificationSettings();
  String? _soundsDir;

  /// The identity's encrypted store, set by [init].
  ///
  /// S366: next to it stood `_profileDir` here, and after the switch-over
  /// it was only the address of the plaintext file — it has remained in
  /// `_log` (the log path still hangs on the profile).
  MessageStore? _store;

  /// Looping playback is driven from Dart, not from a shell/PowerShell loop:
  /// each iteration spawns exactly ONE player process whose PID we own, so
  /// [Process.kill] actually reaches the player. A `bash -c 'while true; ...'`
  /// wrapper could not be stopped reliably — Dart starts children without
  /// setpgid, so the shell is no process-group leader and a hung player
  /// survived kill() as well as a SIGKILL of the daemon.
  bool _loopActive = false;
  int _loopGeneration = 0;
  Process? _currentPlayer;

  bool _vibrateLoopActive = false;

  /// Android: callback for one-shot sound playback via platform channel.
  Future<void> Function(String filename)? onPlaySoundAndroid;

  /// Android: callback for looping sound playback (ringtone/ringback).
  Future<void> Function(String filename)? onStartLoopSoundAndroid;

  /// Android: callback to stop looping sound immediately.
  Future<void> Function()? onStopSoundAndroid;

  /// Android: callback for vibration via platform channel (set by Flutter app).
  Future<void> Function(int durationMs)? onVibrateAndroid;

  NotificationSettings get settings => _settings;

  /// Initialize with profile directory for settings persistence.
  ///
  /// [store] is the identity's encrypted store. It may be `null` — that is
  /// the settings mirror in `ipc_client.dart`, which never calls [init]
  /// anyway, and the path for guards that only measure playback. Without a store
  /// nothing is loaded and nothing written; the setting then applies only
  /// for this run.
  Future<void> init(String profileDir, {MessageStore? store}) async {
    _store = store;
    _log = CLogger.get('notification_sound', profileDir: profileDir);
    await _loadSettings();
    _soundsDir = await _findSoundsDir();
  }

  /// Find the sounds directory (Flutter asset bundle or project assets).
  Future<String?> _findSoundsDir() async {
    // Primary: in the bundle (canonical ~/cleona-app/data/...).
    //
    // `AppPaths.bundleDir` instead of `File(exe).parent.path` (S367): the
    // daemon — and it is precisely the one that plays the sounds — has
    // lived in `<bundleDir>/bin/` since the rebuild. Its own directory
    // carries no `data/`, the bundle root does. Up to here that was masked
    // by the `~/cleona-app` fallback below; on a normal installation,
    // however, that path does not exist.
    final bundleSounds =
        '${AppPaths.bundleDir}/data/flutter_assets/assets/sounds';
    if (Directory(bundleSounds).existsSync()) return bundleSounds;
    // Fallback: binary may run from non-canonical path (e.g. ~/cleona-daemon);
    // look for the bundle in the user's standard cleona-app directory.
    final home = Platform.environment['HOME'] ?? '';
    if (home.isNotEmpty) {
      final appBundle = '$home/cleona-app/data/flutter_assets/assets/sounds';
      if (Directory(appBundle).existsSync()) return appBundle;
    }
    // Development: check project assets
    final projectSounds = '${Directory.current.path}/assets/sounds';
    if (Directory(projectSounds).existsSync()) return projectSounds;
    return null;
  }

  /// S366: from the store (area [kNotificationSettingsArea]) instead of
  /// from `notification_settings.json`.
  ///
  /// NO DATA-LOSS LATCH, and that is a decision, not a gap: the record
  /// carries exactly one setting that the user restores in ten seconds.
  /// If it is lost, it rings with the default sound again — annoying, but
  /// nothing is gone that could not be set again. A latch here would not
  /// be a safeguard, just an additional source of errors (the same
  /// trade-off as with the NAT wizard in `cleona_service_pure.dart`).
  Future<void> _loadSettings() async {
    final s = _store;
    if (s == null) return;
    try {
      final j = s.loadArea(kNotificationSettingsArea)
          [kNotificationSettingsKey];
      if (j != null) _settings = NotificationSettings.fromJson(j);
    } catch (e) {
      _log.warn('Failed to load notification settings: $e');
    }
  }

  Future<void> saveSettings() async {
    final s = _store;
    if (s == null) return;
    try {
      s.replaceArea(kNotificationSettingsArea,
          {kNotificationSettingsKey: _settings.toJson()});
    } catch (e) {
      _log.warn('Failed to save notification settings: $e');
    }
  }

  /// Update settings and persist.
  Future<void> updateSettings(NotificationSettings newSettings) async {
    _settings = newSettings;
    await saveSettings();
  }

  /// File name of the Windows sound player in the bundle root. The Windows
  /// build fails when it is missing (`windows/verify_bundle_dlls.cmake`,
  /// `-DEXPECTED_PROGRAMS`).
  static const String windowsPlayerName = 'cleona-play.exe';

  /// Path of the Windows sound player for a bundle root. Next to the GUI
  /// binary, where the MSVC runtime DLLs it needs are bundled as well.
  static String windowsPlayerPath(String bundleDir) =>
      '$bundleDir\\$windowsPlayerName';

  /// Argument list of the Windows sound player for one file. [volume] is the
  /// linear gain 0..1; it applies to every sound, as in the `paplay` branch.
  static List<String> windowsPlayerArgs(String path, double volume) =>
      [path, '--volume', volume.clamp(0.0, 1.0).toStringAsFixed(3)];

  /// Player program and argument list for one sound file on the desktop —
  /// a real argument list, no shell interpolation. The one place that
  /// decides how a sound is started; [_playOnce], [_startLoop] and
  /// [_playOnceSync] all go through it.
  (String, List<String>) _playerCommand(String path) {
    if (Platform.isWindows) {
      return (
        windowsPlayerPath(AppPaths.bundleDir),
        windowsPlayerArgs(path, _settings.callVolume),
      );
    }
    final player = _getAudioPlayer();
    return (
      player,
      player == 'paplay'
          ? ['--volume=${(_settings.callVolume * 65536).round()}', path]
          : [path], // pw-play doesn't support --volume
    );
  }

  /// Detect available audio player under Linux: pw-play (PipeWire) or
  /// paplay (PulseAudio).
  static String? _audioPlayer;
  static String _getAudioPlayer() {
    if (_audioPlayer != null) return _audioPlayer!;
    // Prefer pw-play (Ubuntu 24.04 default), fall back to paplay
    for (final cmd in ['pw-play', 'paplay']) {
      try {
        final result = Process.runSync('which', [cmd]);
        if (result.exitCode == 0) {
          _audioPlayer = cmd;
          return cmd;
        }
      } catch (_) {}
    }
    _audioPlayer = 'paplay'; // fallback
    return _audioPlayer!;
  }

  /// Test seam: when set, [_playOnce] reports the file it was asked to play
  /// here instead of starting a player. Never set in the product.
  void Function(String filename)? playProbe;

  /// Play a sound file once — fire and forget.
  Future<void> _playOnce(String filename) async {
    final probe = playProbe;
    if (probe != null) {
      probe(filename);
      return;
    }

    // Android: play via platform channel (assets, not filesystem)
    if (Platform.isAndroid) {
      if (onPlaySoundAndroid != null) {
        try { await onPlaySoundAndroid!(filename); } catch (_) {}
      }
      return;
    }

    if (_soundsDir == null) return;
    final path = '$_soundsDir/$filename';
    if (!File(path).existsSync()) return;
    try {
      final (player, args) = _playerCommand(path);
      _log.debug('_playOnce: player=$player path=$path');
      Process.start(player, args).then((p) {
        p.exitCode.then((code) => _log.debug('_playOnce: exit=$code player=$player'));
        return p.exitCode;
      }).catchError((_) => -1);
    } catch (_) {}
  }

  /// Start looping a sound file. Kills any previous loop.
  Future<void> _startLoop(String filename) async {
    await _stopLoop();
    if (Platform.isAndroid) {
      if (onStartLoopSoundAndroid != null) {
        try {
          await onStartLoopSoundAndroid!('assets/sounds/$filename');
        } catch (_) {}
      }
      return;
    }
    if (_soundsDir == null) return;
    final path = '$_soundsDir/$filename';
    if (!File(path).existsSync()) return;

    // One player process per iteration on every desktop platform — the
    // repetition happens in Dart.
    final (executable, args) = _playerCommand(path);

    _loopActive = true;
    final generation = ++_loopGeneration;
    _log.debug('_startLoop: player=$executable path=$path gen=$generation');
    unawaited(_runPlaybackLoop(executable, args, generation));
  }

  /// Repeat playback until [_stopLoop] clears the flag or a newer loop starts.
  /// [generation] guards against two loops running in parallel when
  /// [_startLoop] is called again while an older iteration is still sleeping.
  Future<void> _runPlaybackLoop(
      String executable, List<String> args, int generation) async {
    while (_loopActive && generation == _loopGeneration) {
      try {
        final proc = await Process.start(executable, args);
        if (!_loopActive || generation != _loopGeneration) {
          // Stopped while the process was starting — don't leave it playing.
          proc.kill();
          return;
        }
        _currentPlayer = proc;
        await proc.exitCode;
        if (identical(_currentPlayer, proc)) _currentPlayer = null;
      } catch (e) {
        // Player binary missing or not startable — do not spin on it.
        _log.warn('_runPlaybackLoop: start failed player=$executable error=$e');
        return;
      }
      if (!_loopActive || generation != _loopGeneration) return;
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Stop the looping sound.
  Future<void> _stopLoop() async {
    _vibrateLoopActive = false;
    if (Platform.isAndroid) {
      if (onStopSoundAndroid != null) {
        try { await onStopSoundAndroid!(); } catch (_) {}
      }
      return;
    }
    _loopActive = false;
    _loopGeneration++; // invalidate any loop iteration still in flight
    final proc = _currentPlayer;
    _currentPlayer = null;
    proc?.kill();
  }

  /// Play short message notification sound.
  /// If [soundName] is provided, play the corresponding ringtone file instead.
  Future<void> playMessageSound({String? soundName}) async {
    if (!_settings.soundEnabled || !_settings.messageSoundEnabled) return;
    if (soundName != null) {
      final rt = Ringtone.fromName(soundName);
      await _playOnce(rt.filename);
    } else {
      await _playOnce('message.ogg');
    }
  }

  /// Play message sound synchronously and return the process exit code.
  /// Used by test IPC to verify actual playback without race conditions
  /// (message.ogg is only 280ms — too short for process-polling).
  Future<int> playMessageSoundSync() async {
    if (!_settings.soundEnabled || !_settings.messageSoundEnabled) return -2;
    return await _playOnceSync('message.ogg');
  }

  /// Like [_playOnce] but awaits the process exit code for testability.
  Future<int> _playOnceSync(String filename) async {
    if (Platform.isAndroid) {
      if (onPlaySoundAndroid != null) {
        try { await onPlaySoundAndroid!(filename); return 0; } catch (_) { return -1; }
      }
      return -3;
    }
    if (_soundsDir == null) return -4;
    final path = '$_soundsDir/$filename';
    if (!File(path).existsSync()) return -5;
    try {
      final (player, args) = _playerCommand(path);
      _log.debug('_playOnceSync: player=$player path=$path');
      final p = await Process.start(player, args);
      final code = await p.exitCode;
      _log.debug('_playOnceSync: exit=$code player=$player');
      return code;
    } catch (e) {
      _log.warn('_playOnceSync: error=$e');
      return -1;
    }
  }

  /// Start looping ringtone for incoming call.
  Future<void> startRingtone({Ringtone? ringtone}) async {
    if (!_settings.soundEnabled) return;
    final rt = ringtone ?? _settings.callRingtone;
    await _startLoop(rt.filename);
  }

  /// Stop ringtone.
  Future<void> stopRingtone() async {
    _vibrateLoopActive = false;
    await _stopLoop();
  }

  /// Play ringback tone for outgoing call (loops until stopped).
  Future<void> playRingback() async {
    if (!_settings.soundEnabled) return;
    await _startLoop('ringback.ogg');
  }

  /// Stop ringback tone.
  Future<void> stopRingback() async {
    await _stopLoop();
  }

  /// Play short "connected" confirmation beep.
  Future<void> playConnected() async {
    if (!_settings.soundEnabled) return;
    await _playOnce('connected.ogg');
  }

  /// Play short tone when a participant joins a group call.
  /// Reuses connected.ogg — a dedicated sound file can be added later.
  Future<void> playParticipantJoined() async {
    if (!_settings.soundEnabled) return;
    await _playOnce('connected.ogg');
  }

  /// Play short tone when a participant leaves a group call.
  /// Reuses connected.ogg — a dedicated sound file can be added later.
  Future<void> playParticipantLeft() async {
    if (!_settings.soundEnabled) return;
    await _playOnce('connected.ogg');
  }

  /// Preview a ringtone (for settings UI).
  Future<void> previewRingtone(Ringtone ringtone) async {
    _log.debug('previewRingtone: ${ringtone.name} → ${ringtone.filename}');
    await _stopLoop();
    await _playOnce(ringtone.filename);
  }

  /// Stop ringtone preview.
  Future<void> stopPreview() async {
    await _stopLoop();
  }

  /// Trigger vibration (Android only — no-op on Linux/Windows).
  Future<void> vibrate(VibrationType type) async {
    if (!_settings.vibrationEnabled) return;
    if (!Platform.isAndroid) return;
    if (type == VibrationType.call) {
      _vibrateLoopActive = true;
      _runVibrateLoop();
    } else {
      if (onVibrateAndroid != null) {
        try { await onVibrateAndroid!(200); } catch (_) {}
      }
    }
  }

  void _runVibrateLoop() async {
    while (_vibrateLoopActive) {
      if (onVibrateAndroid != null) {
        try { await onVibrateAndroid!(500); } catch (_) {}
      }
      if (!_vibrateLoopActive) break;
      await Future.delayed(const Duration(milliseconds: 1000));
    }
  }

  /// Stop all sounds (for cleanup).
  Future<void> stopAll() async {
    _vibrateLoopActive = false;
    await _stopLoop();
  }

  /// Dispose resources.
  Future<void> dispose() async {
    await stopAll();
  }
}

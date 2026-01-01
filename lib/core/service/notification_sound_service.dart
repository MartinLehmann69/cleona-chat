import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cleona/core/network/clogger.dart';

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

/// Manages notification sounds and vibration (Architecture 18.8).
///
/// Uses paplay (PulseAudio) on Linux for audio playback — no Flutter dependency.
/// On Android, sounds are played via platform channel.
class NotificationSoundService {
  CLogger _log = CLogger.get('notification_sound');

  NotificationSettings _settings = NotificationSettings();
  String? _profileDir;
  String? _soundsDir;

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
  Future<void> init(String profileDir) async {
    _profileDir = profileDir;
    _log = CLogger.get('notification_sound', profileDir: profileDir);
    await _loadSettings();
    _soundsDir = await _findSoundsDir();
  }

  /// Find the sounds directory (Flutter asset bundle or project assets).
  Future<String?> _findSoundsDir() async {
    // Primary: adjacent to binary (canonical ~/cleona-app/data/...)
    final execDir = File(Platform.resolvedExecutable).parent.path;
    final bundleSounds = '$execDir/data/flutter_assets/assets/sounds';
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

  Future<void> _loadSettings() async {
    if (_profileDir == null) return;
    final file = File('$_profileDir/notification_settings.json');
    if (file.existsSync()) {
      try {
        final json = jsonDecode(file.readAsStringSync());
        _settings = NotificationSettings.fromJson(json as Map<String, dynamic>);
      } catch (_) {}
    }
  }

  Future<void> saveSettings() async {
    if (_profileDir == null) return;
    final file = File('$_profileDir/notification_settings.json');
    file.writeAsStringSync(jsonEncode(_settings.toJson()));
  }

  /// Update settings and persist.
  Future<void> updateSettings(NotificationSettings newSettings) async {
    _settings = newSettings;
    await saveSettings();
  }

  /// Detect available audio player.
  /// Linux: pw-play (PipeWire) or paplay (PulseAudio).
  /// Windows: PowerShell with SoundPlayer (built-in, no external deps).
  static String? _audioPlayer;
  static String _getAudioPlayer() {
    if (_audioPlayer != null) return _audioPlayer!;
    if (Platform.isWindows) {
      _audioPlayer = 'powershell';
      return _audioPlayer!;
    }
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

  /// Play a sound file once — fire and forget.
  Future<void> _playOnce(String filename) async {
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
      final player = _getAudioPlayer();
      if (Platform.isWindows) {
        // Windows: use PowerShell SoundPlayer (.wav) — .ogg not supported natively,
        // but SoundPlayer handles WAV. For .ogg, silently no-op until we add a converter.
        final wavPath = path.replaceAll('.ogg', '.wav');
        if (File(wavPath).existsSync()) {
          Process.start('powershell', ['-NoProfile', '-Command',
            '(New-Object Media.SoundPlayer "$wavPath").PlaySync()'])
            .then((p) => p.exitCode).catchError((_) => -1);
        }
        return;
      }
      final args = player == 'paplay'
          ? ['--volume=${(_settings.callVolume * 65536).round()}', path]
          : [path]; // pw-play doesn't support --volume
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

    final String executable;
    final List<String> args;
    if (Platform.isWindows) {
      // Windows: one PlaySync() per iteration — the repetition happens in Dart.
      final wavPath = path.replaceAll('.ogg', '.wav');
      if (!File(wavPath).existsSync()) return;
      executable = 'powershell';
      args = ['-NoProfile', '-Command',
        '(New-Object Media.SoundPlayer "$wavPath").PlaySync()'];
    } else {
      final player = _getAudioPlayer();
      executable = player;
      // Same argument construction as _playOnce/_playOnceSync — a real argument
      // list, no shell interpolation.
      args = player == 'paplay'
          ? ['--volume=${(_settings.callVolume * 65536).round()}', path]
          : [path]; // pw-play doesn't support --volume
    }

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
      final player = _getAudioPlayer();
      if (Platform.isWindows) {
        final wavPath = path.replaceAll('.ogg', '.wav');
        if (!File(wavPath).existsSync()) return -6;
        final p = await Process.start('powershell', ['-NoProfile', '-Command',
          '(New-Object Media.SoundPlayer "$wavPath").PlaySync()']);
        return await p.exitCode;
      }
      final args = player == 'paplay'
          ? ['--volume=${(_settings.callVolume * 65536).round()}', path]
          : [path];
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

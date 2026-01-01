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

  NotificationSettings({
    this.soundEnabled = true,
    this.vibrationEnabled = true,
    this.messageSoundEnabled = true,
    this.callRingtone = Ringtone.gentle,
    this.callVolume = 0.8,
  });

  factory NotificationSettings.fromJson(Map<String, dynamic> json) {
    return NotificationSettings(
      soundEnabled: json['soundEnabled'] as bool? ?? true,
      vibrationEnabled: json['vibrationEnabled'] as bool? ?? true,
      messageSoundEnabled: json['messageSoundEnabled'] as bool? ?? true,
      callRingtone: Ringtone.fromName(json['callRingtone'] as String? ?? 'gentle'),
      callVolume: (json['callVolume'] as num?)?.toDouble() ?? 0.8,
    );
  }

  Map<String, dynamic> toJson() => {
    'soundEnabled': soundEnabled,
    'vibrationEnabled': vibrationEnabled,
    'messageSoundEnabled': messageSoundEnabled,
    'callRingtone': callRingtone.name,
    'callVolume': callVolume,
  };
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
  Process? _loopingProcess;
  bool _androidLoopActive = false;
  bool _vibrateLoopActive = false;

  /// Android: callback for sound playback via platform channel (set by Flutter app).
  Future<void> Function(String filename)? onPlaySoundAndroid;

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
      _androidLoopActive = true;
      _runAndroidSoundLoop(filename);
      return;
    }
    if (_soundsDir == null) return;
    final path = '$_soundsDir/$filename';
    if (!File(path).existsSync()) return;
    try {
      if (Platform.isWindows) {
        // Windows: loop via PowerShell
        final wavPath = path.replaceAll('.ogg', '.wav');
        if (File(wavPath).existsSync()) {
          _loopingProcess = await Process.start('powershell', ['-NoProfile', '-Command',
            'while(\$true){(New-Object Media.SoundPlayer "$wavPath").PlaySync();Start-Sleep -Milliseconds 500}']);
        }
        return;
      }
      final player = _getAudioPlayer();
      final args = player == 'paplay'
          ? '--volume=${(_settings.callVolume * 65536).round()} "$path"'
          : '"$path"';
      _loopingProcess = await Process.start('bash', ['-c',
        'while true; do $player $args; sleep 0.5; done']);
    } catch (_) {}
  }

  void _runAndroidSoundLoop(String filename) async {
    while (_androidLoopActive) {
      if (onPlaySoundAndroid != null) {
        try {
          await onPlaySoundAndroid!(filename);
        } catch (_) {}
      }
      if (!_androidLoopActive) break;
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Stop the looping sound.
  Future<void> _stopLoop() async {
    _androidLoopActive = false;
    _vibrateLoopActive = false;
    if (_loopingProcess != null) {
      _loopingProcess!.kill();
      _loopingProcess = null;
    }
  }

  /// Play short message notification sound.
  Future<void> playMessageSound() async {
    if (!_settings.soundEnabled || !_settings.messageSoundEnabled) return;
    await _playOnce('message.ogg');
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

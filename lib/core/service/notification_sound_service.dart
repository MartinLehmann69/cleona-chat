import 'dart:convert';
import 'dart:io';

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
  NotificationSettings _settings = NotificationSettings();
  String? _profileDir;
  String? _soundsDir;
  Process? _loopingProcess;

  /// Android: callback for sound playback via platform channel (set by Flutter app).
  Future<void> Function(String filename)? onPlaySoundAndroid;

  /// Android: callback for vibration via platform channel (set by Flutter app).
  Future<void> Function(int durationMs)? onVibrateAndroid;

  NotificationSettings get settings => _settings;

  /// Initialize with profile directory for settings persistence.
  Future<void> init(String profileDir) async {
    _profileDir = profileDir;
    await _loadSettings();
    _soundsDir = await _findSoundsDir();
  }

  /// Find the sounds directory (Flutter asset bundle or project assets).
  Future<String?> _findSoundsDir() async {
    // Check Flutter bundle path (Linux desktop)
    final execDir = File(Platform.resolvedExecutable).parent.path;
    final bundleSounds = '$execDir/data/flutter_assets/assets/sounds';
    if (Directory(bundleSounds).existsSync()) return bundleSounds;
    // Check project assets directly (development)
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
      Process.start(player, args).then((p) => p.exitCode).catchError((_) => -1);
    } catch (_) {}
  }

  /// Start looping a sound file. Kills any previous loop.
  Future<void> _startLoop(String filename) async {
    await _stopLoop();
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

  /// Stop the looping sound.
  Future<void> _stopLoop() async {
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

  /// Start looping ringtone for incoming call.
  Future<void> startRingtone({Ringtone? ringtone}) async {
    if (!_settings.soundEnabled) return;
    final rt = ringtone ?? _settings.callRingtone;
    await _startLoop(rt.filename);
  }

  /// Stop ringtone.
  Future<void> stopRingtone() async {
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
    final duration = type == VibrationType.call ? 1000 : 200;
    if (onVibrateAndroid != null) {
      try { await onVibrateAndroid!(duration); } catch (_) {}
    }
  }

  /// Stop all sounds (for cleanup).
  Future<void> stopAll() async {
    await _stopLoop();
  }

  /// Dispose resources.
  Future<void> dispose() async {
    await stopAll();
  }
}

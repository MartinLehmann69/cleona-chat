import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cleona/main.dart';
import 'package:cleona/core/service/service_types.dart';

/// In-Call Screen — shows audio/video call with PiP layout and controls.
class CallScreen extends StatefulWidget {
  final CallInfo callInfo;
  final String peerDisplayName;

  const CallScreen({
    super.key,
    required this.callInfo,
    required this.peerDisplayName,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  Timer? _durationTimer;
  Duration _duration = Duration.zero;
  bool _muted = false;
  bool _speaker = false;
  bool _videoEnabled = true;
  bool _frontCamera = true;

  // Video frames (set by VideoEngine callbacks via CleonaAppState)
  ui.Image? _remoteVideoFrame;
  ui.Image? _localVideoFrame;

  @override
  void initState() {
    super.initState();
    if (widget.callInfo.state == CallState.inCall) {
      _startDurationTimer();
    }
  }

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _duration += const Duration(seconds: 1);
      });
    });
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<CleonaAppState>();
    final currentCall = appState.service?.currentCall;

    // Call ended while screen is open
    if (currentCall == null || currentCall.state == CallState.ended) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }

    // Call just got accepted → start timer
    if (currentCall?.state == CallState.inCall && _durationTimer == null) {
      _startDurationTimer();
    }

    final isRinging = currentCall?.state == CallState.ringing;
    final isIncoming = currentCall?.direction == CallDirection.incoming;
    final isVideo = currentCall?.isVideo ?? widget.callInfo.isVideo;

    // Video call layout
    if (isVideo && !isRinging) {
      return _buildVideoCallLayout(context, appState, currentCall, isRinging, isIncoming);
    }

    // Audio-only call layout (same as before)
    return _buildAudioCallLayout(context, appState, isRinging, isIncoming);
  }

  Widget _buildVideoCallLayout(BuildContext context, CleonaAppState appState,
      CallInfo? currentCall, bool isRinging, bool isIncoming) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Remote video (fullscreen)
          Positioned.fill(
            child: _remoteVideoFrame != null
                ? RawImage(
                    image: _remoteVideoFrame,
                    fit: BoxFit.contain,
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 48,
                          backgroundColor: Colors.grey[800],
                          child: Text(
                            widget.peerDisplayName.isNotEmpty
                                ? widget.peerDisplayName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                                fontSize: 40, color: Colors.white),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.peerDisplayName,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 20),
                        ),
                      ],
                    ),
                  ),
          ),

          // Top bar: duration + encryption
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.lock, size: 14, color: Colors.green),
                    const SizedBox(width: 4),
                    Text(
                      _formatDuration(_duration),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const Spacer(),
                    Text(
                      widget.peerDisplayName,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Local video (PiP — bottom right corner)
          Positioned(
            right: 16,
            bottom: 140,
            child: GestureDetector(
              onTap: _toggleCamera,
              child: Container(
                width: 120,
                height: 160,
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24, width: 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: _localVideoFrame != null && _videoEnabled
                    ? RawImage(
                        image: _localVideoFrame,
                        fit: BoxFit.cover,
                      )
                    : Center(
                        child: Icon(
                          _videoEnabled ? Icons.videocam : Icons.videocam_off,
                          color: Colors.white54,
                          size: 32,
                        ),
                      ),
              ),
            ),
          ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _VideoCallButton(
                      icon: _muted ? Icons.mic_off : Icons.mic,
                      label: _muted ? 'Stumm' : 'Mikrofon',
                      active: _muted,
                      onPressed: () => setState(() => _muted = !_muted),
                    ),
                    _VideoCallButton(
                      icon: _videoEnabled ? Icons.videocam : Icons.videocam_off,
                      label: _videoEnabled ? 'Video' : 'Video aus',
                      active: !_videoEnabled,
                      onPressed: _toggleVideo,
                    ),
                    _VideoCallButton(
                      icon: Icons.cameraswitch,
                      label: 'Kamera',
                      onPressed: _toggleCamera,
                    ),
                    _VideoCallButton(
                      icon: _speaker ? Icons.volume_up : Icons.volume_down,
                      label: 'Lautsprecher',
                      active: _speaker,
                      onPressed: () => setState(() => _speaker = !_speaker),
                    ),
                    _VideoCallButton(
                      icon: Icons.call_end,
                      label: 'Auflegen',
                      color: Colors.red,
                      onPressed: () {
                        appState.service?.hangup();
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioCallLayout(BuildContext context, CleonaAppState appState,
      bool isRinging, bool isIncoming) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),

            // Peer avatar
            CircleAvatar(
              radius: 60,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                widget.peerDisplayName.isNotEmpty
                    ? widget.peerDisplayName[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  fontSize: 48,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Peer name
            Text(
              widget.peerDisplayName,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),

            // Status text
            Text(
              isRinging
                  ? (isIncoming ? 'Eingehender Anruf...' : 'Klingelt...')
                  : _formatDuration(_duration),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),

            // Encryption indicator
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock, size: 14,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  'Ende-zu-Ende verschluesselt',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),

            const Spacer(flex: 3),

            // Controls
            if (!isRinging) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallButton(
                    icon: _muted ? Icons.mic_off : Icons.mic,
                    label: _muted ? 'Stumm' : 'Mikrofon',
                    active: _muted,
                    onPressed: () => setState(() => _muted = !_muted),
                  ),
                  _CallButton(
                    icon: _speaker ? Icons.volume_up : Icons.volume_down,
                    label: 'Lautsprecher',
                    active: _speaker,
                    onPressed: () => setState(() => _speaker = !_speaker),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],

            // Action buttons
            if (isRinging && isIncoming) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallButton(
                    icon: Icons.call_end,
                    label: 'Ablehnen',
                    color: Colors.red,
                    onPressed: () {
                      appState.service?.rejectCall();
                      Navigator.of(context).pop();
                    },
                  ),
                  _CallButton(
                    icon: Icons.call,
                    label: 'Annehmen',
                    color: Colors.green,
                    onPressed: () {
                      appState.service?.acceptCall();
                    },
                  ),
                ],
              ),
            ] else ...[
              _CallButton(
                icon: Icons.call_end,
                label: 'Auflegen',
                color: Colors.red,
                size: 72,
                onPressed: () {
                  appState.service?.hangup();
                  Navigator.of(context).pop();
                },
              ),
            ],

            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  void _toggleVideo() {
    setState(() {
      _videoEnabled = !_videoEnabled;
    });
    // TODO: Signal VideoEngine to mute/unmute video capture
  }

  void _toggleCamera() {
    setState(() {
      _frontCamera = !_frontCamera;
    });
    // TODO: Signal VideoEngine to switch camera (front/back on mobile)
  }

  /// Called externally to update the remote video frame.
  void updateRemoteFrame(ui.Image frame) {
    if (mounted) {
      setState(() {
        _remoteVideoFrame?.dispose();
        _remoteVideoFrame = frame;
      });
    }
  }

  /// Called externally to update the local preview frame.
  void updateLocalFrame(ui.Image frame) {
    if (mounted) {
      setState(() {
        _localVideoFrame?.dispose();
        _localVideoFrame = frame;
      });
    }
  }
}

// ── Button Widgets ──────────────────────────────────────────────────

class _VideoCallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final bool active;
  final VoidCallback onPressed;

  const _VideoCallButton({
    required this.icon,
    required this.label,
    this.color,
    this.active = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = color ?? (active ? Colors.white24 : Colors.white12);
    final fgColor = color != null ? Colors.white : (active ? Colors.white : Colors.white70);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: FloatingActionButton(
            heroTag: 'video_$label',
            backgroundColor: bgColor,
            elevation: 0,
            onPressed: onPressed,
            child: Icon(icon, color: fgColor, size: 22),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final bool active;
  final double size;
  final VoidCallback onPressed;

  const _CallButton({
    required this.icon,
    required this.label,
    this.color,
    this.active = false,
    this.size = 56,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = color ??
        (active
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest);
    final fgColor = color != null
        ? Colors.white
        : (active
            ? Theme.of(context).colorScheme.onPrimaryContainer
            : Theme.of(context).colorScheme.onSurface);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: FloatingActionButton(
            heroTag: label,
            backgroundColor: bgColor,
            onPressed: onPressed,
            child: Icon(icon, color: fgColor, size: size * 0.45),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

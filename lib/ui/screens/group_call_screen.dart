import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cleona/main.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/service/service_types.dart';

/// Group Call Screen — shows participant video grid, timer, and controls.
///
/// Phase 3c UI features:
///   * Adaptive grid layout (1=fullscreen, 2-4=2x2, 5+=3-column)
///   * Active speaker highlighting (green border on highest audio level)
///   * Per-participant mute indicator (mic_off icon overlay)
///   * Service-wired mute/speaker/video toggles
///   * Health dashboard (RTT per participant)
///   * i18n for all visible strings
class GroupCallScreen extends StatefulWidget {
  final GroupCallInfo callInfo;
  final String groupName;

  const GroupCallScreen({
    super.key,
    required this.callInfo,
    required this.groupName,
  });

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  Timer? _durationTimer;
  Duration _duration = Duration.zero;
  bool _muted = false;
  bool _speaker = false;
  bool _videoEnabled = true;
  bool _autoPopScheduled = false;
  bool _showHealthDashboard = false;

  /// Remote video frames: senderHex -> latest ui.Image
  final Map<String, ui.Image> _remoteFrames = {};

  @override
  void initState() {
    super.initState();
    if (widget.callInfo.state == GroupCallState.inCall) {
      _startDurationTimer();
    }
  }

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _duration += const Duration(seconds: 1);
      });
    });
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    for (final img in _remoteFrames.values) {
      img.dispose();
    }
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  /// Called by parent to update a participant's video frame.
  void updateRemoteFrame(String senderHex, ui.Image frame) {
    if (mounted) {
      setState(() {
        _remoteFrames[senderHex]?.dispose();
        _remoteFrames[senderHex] = frame;
      });
    }
  }

  /// Determine the active speaker: the joined participant with the highest
  /// audio level above a threshold (0.05 = ~1600 on int16 scale).
  String? _activeSpeakerHex(List<GroupCallParticipantInfo> participants) {
    String? bestHex;
    double bestLevel = 0.05; // minimum threshold
    for (final p in participants) {
      if (p.audioLevel > bestLevel) {
        bestLevel = p.audioLevel;
        bestHex = p.nodeIdHex;
      }
    }
    return bestHex;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<CleonaAppState>();
    final currentCall = appState.service?.currentGroupCall;
    final locale = AppLocale.read(context);

    if (currentCall == null || currentCall.state == GroupCallState.ended) {
      if (!_autoPopScheduled) {
        _autoPopScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        });
      }
    }

    // Call just got accepted -> start timer
    if (currentCall?.state == GroupCallState.inCall && _durationTimer == null) {
      _startDurationTimer();
    }

    final isRinging = currentCall?.state == GroupCallState.ringing;
    final isInviting = currentCall?.state == GroupCallState.inviting;
    final joinedParticipants = currentCall?.participants
            .where((p) => p.state == ParticipantState.joined)
            .toList() ??
        [];
    final allParticipants = currentCall?.participants ?? [];
    final activeSpeaker = _activeSpeakerHex(joinedParticipants);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Header: group name + status
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.lock, size: 14,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(
                    _formatDuration(_duration),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(width: 8),
                  // Health dashboard toggle
                  if (currentCall?.state == GroupCallState.inCall)
                    GestureDetector(
                      onTap: () => setState(() =>
                          _showHealthDashboard = !_showHealthDashboard),
                      child: Icon(
                        Icons.monitor_heart_outlined,
                        size: 18,
                        color: _showHealthDashboard
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  const Spacer(),
                  Text(
                    '${widget.groupName}  ·  ${locale.get('group_call_participants_count').replaceAll('{count}', '${joinedParticipants.length}')}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),

            // Health dashboard (RTT per participant)
            if (_showHealthDashboard && currentCall?.state == GroupCallState.inCall)
              _buildHealthDashboard(context, locale, joinedParticipants),

            // Main content: video grid or participant list
            Expanded(
              child: (isRinging || isInviting)
                  ? _buildRingingLayout(context, locale, isRinging, allParticipants)
                  : _buildVideoGrid(context, locale, joinedParticipants, activeSpeaker),
            ),

            // Controls
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: _buildControls(context, locale, appState, isRinging),
            ),
          ],
        ),
      ),
    );
  }

  /// Health dashboard: shows RTT and audio level per participant.
  Widget _buildHealthDashboard(BuildContext context, AppLocale locale,
      List<GroupCallParticipantInfo> participants) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            locale.get('group_call_health'),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          ...participants.map((p) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        p.displayName,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: _AudioLevelBar(level: p.audioLevel),
                    ),
                    const SizedBox(width: 8),
                    if (p.isMuted)
                      Icon(Icons.mic_off, size: 12,
                          color: Colors.red.shade300)
                    else
                      const SizedBox(width: 12),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  /// Ringing/inviting layout: group icon + participant list.
  Widget _buildRingingLayout(BuildContext context, AppLocale locale,
      bool isRinging, List<GroupCallParticipantInfo> participants) {
    return Column(
      children: [
        const SizedBox(height: 24),
        CircleAvatar(
          radius: 48,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(Icons.group, size: 48,
              color: Theme.of(context).colorScheme.onPrimaryContainer),
        ),
        const SizedBox(height: 16),
        Text(
          widget.groupName,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        Text(
          isRinging ? locale.get('group_call_incoming') : locale.get('group_call_waiting'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: participants.length,
            itemBuilder: (_, i) => _ParticipantTile(participant: participants[i]),
          ),
        ),
      ],
    );
  }

  /// Video grid: 1=fullscreen, 2-4=2x2, 5+=3-column scrollable grid.
  Widget _buildVideoGrid(BuildContext context, AppLocale locale,
      List<GroupCallParticipantInfo> joinedParticipants, String? activeSpeaker) {
    if (joinedParticipants.isEmpty) {
      return Center(child: Text(locale.get('group_call_no_participants')));
    }

    final count = joinedParticipants.length;

    if (count <= 1) {
      // Single participant: fullscreen
      return _buildParticipantVideo(
          context, joinedParticipants.first,
          isActiveSpeaker: activeSpeaker == joinedParticipants.first.nodeIdHex);
    }

    // Grid layout
    final crossAxisCount = count <= 4 ? 2 : 3;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
          childAspectRatio: 4 / 3,
        ),
        itemCount: count,
        itemBuilder: (_, i) {
          final p = joinedParticipants[i];
          return _buildParticipantVideo(context, p,
              isActiveSpeaker: activeSpeaker == p.nodeIdHex);
        },
      ),
    );
  }

  /// Single participant video tile: shows video frame or avatar, with active
  /// speaker highlighting and mute indicator.
  Widget _buildParticipantVideo(BuildContext context,
      GroupCallParticipantInfo participant,
      {bool isActiveSpeaker = false}) {
    final frame = _remoteFrames[participant.nodeIdHex];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
        border: isActiveSpeaker
            ? Border.all(color: Colors.green, width: 2.5)
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video frame or avatar
          if (frame != null)
            RawImage(image: frame, fit: BoxFit.contain)
          else
            Center(
              child: CircleAvatar(
                radius: 28,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  participant.displayName.isNotEmpty
                      ? participant.displayName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontSize: 24,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          // Name + mute indicator overlay at bottom
          Positioned(
            bottom: 4,
            left: 4,
            right: 4,
            child: Row(
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      participant.displayName,
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (participant.isMuted) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.mic_off, color: Colors.red, size: 14),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context, AppLocale locale,
      CleonaAppState appState, bool isRinging) {
    if (isRinging) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _GroupCallButton(
            icon: Icons.call_end,
            label: locale.get('reject'),
            color: Colors.red,
            onPressed: () {
              appState.service?.rejectGroupCall();
              Navigator.of(context).pop();
            },
          ),
          _GroupCallButton(
            icon: Icons.call,
            label: locale.get('accept'),
            color: Colors.green,
            onPressed: () {
              appState.service?.acceptGroupCall();
            },
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _GroupCallButton(
          icon: _muted ? Icons.mic_off : Icons.mic,
          label: _muted ? locale.get('group_call_muted') : locale.get('group_call_microphone'),
          active: _muted,
          onPressed: () {
            setState(() => _muted = !_muted);
            appState.service?.toggleMute();
          },
        ),
        _GroupCallButton(
          icon: _videoEnabled ? Icons.videocam : Icons.videocam_off,
          label: _videoEnabled ? locale.get('group_call_video_on') : locale.get('group_call_video_off'),
          active: !_videoEnabled,
          onPressed: () {
            setState(() => _videoEnabled = !_videoEnabled);
          },
        ),
        _GroupCallButton(
          icon: _speaker ? Icons.volume_up : Icons.volume_down,
          label: locale.get('group_call_speaker'),
          active: _speaker,
          onPressed: () {
            setState(() => _speaker = !_speaker);
            appState.service?.toggleSpeaker();
          },
        ),
        _GroupCallButton(
          icon: Icons.call_end,
          label: locale.get('leave'),
          color: Colors.red,
          onPressed: () {
            appState.service?.leaveGroupCall();
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}

// ── Audio Level Bar ─────────────────────────────────────────────────────

class _AudioLevelBar extends StatelessWidget {
  final double level;
  const _AudioLevelBar({required this.level});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 6,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: level.clamp(0.0, 1.0),
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          valueColor: AlwaysStoppedAnimation<Color>(
            level > 0.5
                ? Colors.green
                : level > 0.1
                    ? Colors.yellow.shade700
                    : Theme.of(context).colorScheme.outline,
          ),
        ),
      ),
    );
  }
}

// ── Participant Tile (for ringing state) ─────────────────────────────

class _ParticipantTile extends StatelessWidget {
  final GroupCallParticipantInfo participant;

  const _ParticipantTile({required this.participant});

  @override
  Widget build(BuildContext context) {
    final stateIcon = switch (participant.state) {
      ParticipantState.joined => Icons.check_circle,
      ParticipantState.ringing || ParticipantState.invited => Icons.ring_volume,
      ParticipantState.left => Icons.call_end,
      ParticipantState.crashed => Icons.error_outline,
    };
    final stateColor = switch (participant.state) {
      ParticipantState.joined => Colors.green,
      ParticipantState.ringing || ParticipantState.invited => Colors.orange,
      ParticipantState.left => Colors.grey,
      ParticipantState.crashed => Colors.red,
    };

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Text(
          participant.displayName.isNotEmpty
              ? participant.displayName[0].toUpperCase()
              : '?',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
      ),
      title: Text(participant.displayName),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (participant.isMuted && participant.state == ParticipantState.joined)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.mic_off, color: Colors.red.shade300, size: 16),
            ),
          Icon(stateIcon, color: stateColor, size: 20),
        ],
      ),
    );
  }
}

// ── Button Widget ─────────────────────────────────────────────────────

class _GroupCallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final bool active;
  final VoidCallback onPressed;

  const _GroupCallButton({
    required this.icon,
    required this.label,
    this.color,
    this.active = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    const size = 48.0;
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
        Semantics(
          button: true,
          label: label,
          child: SizedBox(
            width: size,
            height: size,
            child: FloatingActionButton(
              heroTag: 'gc_$label',
              backgroundColor: bgColor,
              onPressed: onPressed,
              child: Icon(icon, color: fgColor, size: size * 0.45),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

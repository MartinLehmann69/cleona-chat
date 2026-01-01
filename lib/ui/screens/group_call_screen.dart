import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cleona/main.dart';
import 'package:cleona/core/service/service_types.dart';

/// Group Call Screen — shows participant video grid, timer, and controls.
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

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<CleonaAppState>();
    final currentCall = appState.service?.currentGroupCall;

    // Call ended while screen is open
    if (currentCall == null || currentCall.state == GroupCallState.ended) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }

    // Call just got accepted → start timer
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
                  const Spacer(),
                  Text(
                    '${widget.groupName}  ·  ${joinedParticipants.length} Teilnehmer',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),

            // Main content: video grid or participant list
            Expanded(
              child: (isRinging || isInviting)
                  ? _buildRingingLayout(context, isRinging, allParticipants)
                  : _buildVideoGrid(context, joinedParticipants),
            ),

            // Controls
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: _buildControls(context, appState, isRinging),
            ),
          ],
        ),
      ),
    );
  }

  /// Ringing/inviting layout: group icon + participant list.
  Widget _buildRingingLayout(BuildContext context, bool isRinging,
      List<GroupCallParticipantInfo> participants) {
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
          isRinging ? 'Eingehender Gruppenanruf...' : 'Warte auf Teilnehmer...',
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

  /// Video grid: 1=fullscreen, 2=vertical split, 3-4=2x2, 5+=scrollable grid.
  Widget _buildVideoGrid(BuildContext context,
      List<GroupCallParticipantInfo> joinedParticipants) {
    if (joinedParticipants.isEmpty) {
      return const Center(child: Text('Keine Teilnehmer'));
    }

    // Filter out self — we show self in PiP
    final remoteParticipants = joinedParticipants;
    final count = remoteParticipants.length;

    if (count <= 1) {
      // Single participant: fullscreen
      return _buildParticipantVideo(
          context, remoteParticipants.first, double.infinity, double.infinity);
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
          return _buildParticipantVideo(context, remoteParticipants[i], 0, 0);
        },
      ),
    );
  }

  /// Single participant video tile: shows video frame or avatar.
  Widget _buildParticipantVideo(BuildContext context,
      GroupCallParticipantInfo participant, double w, double h) {
    final frame = _remoteFrames[participant.nodeIdHex];

    return Container(
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
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
          // Name overlay at bottom
          Positioned(
            bottom: 4,
            left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                participant.displayName,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(
      BuildContext context, CleonaAppState appState, bool isRinging) {
    if (isRinging) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _GroupCallButton(
            icon: Icons.call_end,
            label: 'Ablehnen',
            color: Colors.red,
            onPressed: () {
              appState.service?.rejectGroupCall();
              Navigator.of(context).pop();
            },
          ),
          _GroupCallButton(
            icon: Icons.call,
            label: 'Annehmen',
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
          label: _muted ? 'Stumm' : 'Mikrofon',
          active: _muted,
          onPressed: () => setState(() => _muted = !_muted),
        ),
        _GroupCallButton(
          icon: _videoEnabled ? Icons.videocam : Icons.videocam_off,
          label: _videoEnabled ? 'Video' : 'Video aus',
          active: !_videoEnabled,
          onPressed: () => setState(() => _videoEnabled = !_videoEnabled),
        ),
        _GroupCallButton(
          icon: _speaker ? Icons.volume_up : Icons.volume_down,
          label: 'Lautsprecher',
          active: _speaker,
          onPressed: () => setState(() => _speaker = !_speaker),
        ),
        _GroupCallButton(
          icon: Icons.call_end,
          label: 'Verlassen',
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
      trailing: Icon(stateIcon, color: stateColor, size: 20),
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
        SizedBox(
          width: size,
          height: size,
          child: FloatingActionButton(
            heroTag: 'gc_$label',
            backgroundColor: bgColor,
            onPressed: onPressed,
            child: Icon(icon, color: fgColor, size: size * 0.45),
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

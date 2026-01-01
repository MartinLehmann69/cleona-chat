// The running media transfers of this surface (§22.5.1, S398-W4).
//
// §22.5.1: "The running transfer itself is a parallel `TransferPhase`
// (`negotiating` → `streaming n %` | `seeding n %` → `available`), shown as
// progress and never folded into the delivery state." The service reports
// it (`ICleonaService.onMediaTransferProgress`, over IPC the event
// `media_transfer_progress`); until S398 nothing in `lib/ui` listened, and a
// lane 2/3 transfer showed no progress at all.
//
// This holder is the listening, and nothing else: a map from message id to
// the last phase and percent. It does not decide the delivery state — the
// bubble keeps drawing its status icon from `UiMessage.status` beside it.
//
// A singleton for the same reason as `ArchiveRetrievalState`: the bubble is
// rebuilt per message inside a list, and the callback that feeds it is set
// where the service is created (`main.dart`).

import 'package:flutter/material.dart';

import 'package:cleona/core/service/service_types.dart' show TransferPhase;

/// Per-message transfer progress for the chat view.
class TransferProgressState extends ChangeNotifier {
  /// The one instance the chat view reads.
  static final TransferProgressState instance = TransferProgressState.forTest();

  /// A fresh, unshared holder — for probes.
  TransferProgressState.forTest();

  /// Bounded like the IPC client's own buffer: a surface that is open for
  /// days must not collect every transfer it ever saw.
  static const int atMost = 256;

  final Map<String, ({TransferPhase phase, int percent})> _running = {};

  /// The last progress of [messageId], or `null` when no transfer runs.
  ({TransferPhase phase, int percent})? of(String messageId) =>
      _running[messageId];

  /// Fed from `onMediaTransferProgress`.
  ///
  /// A transfer that has ENDED leaves the map: `available` (the sender is
  /// done) and `collecting 100` (the recipient has every stripe). `seeding
  /// 100` / `streaming 100` stay — `available` follows them.
  void report(String messageId, TransferPhase phase, int percent) {
    if (messageId.isEmpty) return;
    final p = percent.clamp(0, 100);
    final ended = phase == TransferPhase.available ||
        (phase == TransferPhase.collecting && p >= 100);
    if (ended) {
      if (_running.remove(messageId) != null) notifyListeners();
      return;
    }
    final before = _running[messageId];
    if (before != null && before.phase == phase && before.percent == p) {
      return;
    }
    _running.remove(messageId); // re-insert: newest last, oldest gives way
    _running[messageId] = (phase: phase, percent: p);
    while (_running.length > atMost) {
      _running.remove(_running.keys.first);
    }
    notifyListeners();
  }

  /// Forgets every transfer — the connection to the service dropped, no
  /// further report will arrive for them.
  void reset() {
    if (_running.isEmpty) return;
    _running.clear();
    notifyListeners();
  }
}

/// The i18n key naming [phase] (all five exist in 34 languages).
String transferPhaseKey(TransferPhase phase) => switch (phase) {
      TransferPhase.negotiating => 'transfer_phase_negotiating',
      TransferPhase.streaming => 'transfer_phase_streaming',
      TransferPhase.seeding => 'transfer_phase_seeding',
      TransferPhase.available => 'transfer_phase_available',
      TransferPhase.collecting => 'transfer_phase_collecting',
    };

/// One line under a media bubble: the phase in words, the percent, a bar.
///
/// `negotiating` has no meaningful fraction yet (waiting for a request, a
/// volunteer or holders) — the bar is then indeterminate instead of a
/// made-up 0 %.
class TransferProgressLine extends StatelessWidget {
  const TransferProgressLine({
    super.key,
    required this.messageId,
    required this.translate,
    this.holder,
  });

  final String messageId;

  /// The wording — `AppLocale.get` satisfies this.
  final String Function(String key) translate;

  /// Defaults to [TransferProgressState.instance].
  final TransferProgressState? holder;

  @override
  Widget build(BuildContext context) {
    final h = holder ?? TransferProgressState.instance;
    return AnimatedBuilder(
      animation: h,
      builder: (context, _) {
        final p = h.of(messageId);
        if (p == null) return const SizedBox.shrink();
        final determinate = p.phase != TransferPhase.negotiating;
        final label = determinate
            ? '${translate(transferPhaseKey(p.phase))} ${p.percent} %'
            : translate(transferPhaseKey(p.phase));
        return Padding(
          key: ValueKey('transfer-progress-$messageId'),
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11)),
              const SizedBox(height: 2),
              SizedBox(
                width: 160,
                child: LinearProgressIndicator(
                  value: determinate ? p.percent / 100 : null,
                  minHeight: 3,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

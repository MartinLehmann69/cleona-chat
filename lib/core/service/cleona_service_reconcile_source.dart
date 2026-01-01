// V4.2 §14.6.3 (D-42) — the initial reconciliation of own devices, the
// SOURCE side: the device that holds the history and serves it to a newly
// enrolled device of its own set.

part of 'cleona_service.dart';

extension CleonaServiceReconcileSource on CleonaService {
  /// Test-only: the handover body exactly as [enrolDecide] builds it
  /// (§14.6.2) — to measure its size (proposal S398 §7 item 3).
  @visibleForTesting
  Uint8List reconcileHandoverBodyForTesting() =>
      enrolBodyOf(_enrolHandoverBuild());
}

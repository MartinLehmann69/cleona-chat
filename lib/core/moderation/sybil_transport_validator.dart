/// Anti-Sybil Transport-Layer Validator.
///
/// Validates incoming CHANNEL_REPORTs at the network level:
/// 1. Selects K random validator nodes from the DHT
/// 2. Sends reachability queries to validators
/// 3. Validators check via Bloom filter whether reporter is reachable
/// 4. Report is only accepted when >= 60% of validators confirm
///
/// Core principle: The network validates, not the app.
/// A modified client can submit reports,
/// but the network ignores them if criteria are not met.
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:cleona/core/moderation/moderation_config.dart';
import 'package:cleona/core/moderation/reachability_check.dart';
import 'package:cleona/core/network/clogger.dart';

/// Result of a transport-layer validation.
class TransportValidationResult {
  /// Reporter-Node-ID (Hex).
  final String reporterNodeIdHex;

  /// Number of validators that reached the reporter.
  final int validatorsReached;

  /// Total number of validators contacted.
  final int validatorsContacted;

  /// Validators that did not respond (timeout).
  final int validatorsTimedOut;

  /// Whether the report was accepted.
  final bool accepted;

  /// Reason for rejection.
  final String? rejectionReason;

  /// Duration of the validation.
  final Duration validationDuration;

  TransportValidationResult({
    required this.reporterNodeIdHex,
    required this.validatorsReached,
    required this.validatorsContacted,
    this.validatorsTimedOut = 0,
    required this.accepted,
    this.rejectionReason,
    required this.validationDuration,
  });

  double get reachabilityScore =>
      validatorsContacted > 0 ? validatorsReached / validatorsContacted : 0.0;

  @override
  String toString() =>
      'TransportValidation($reporterNodeIdHex: '
      '$validatorsReached/$validatorsContacted reachable, '
      '$validatorsTimedOut timed out, '
      '${(reachabilityScore * 100).toStringAsFixed(0)}% '
      '${accepted ? "ACCEPTED" : "REJECTED"}'
      '${rejectionReason != null ? " — $rejectionReason" : ""})';
}

/// Pending validation request.
class _PendingValidation {
  final String reportId;
  final String reporterNodeIdHex;
  final Completer<TransportValidationResult> completer;
  final Map<String, bool?> validatorResponses; // nodeIdHex -> reached? (null = pending)
  final DateTime startedAt;
  final Timer timeoutTimer;

  _PendingValidation({
    required this.reportId,
    required this.reporterNodeIdHex,
    required this.completer,
    required this.validatorResponses,
    required this.timeoutTimer,
  }) : startedAt = DateTime.now();
}

/// Callback to send a reachability query to a validator.
/// The transport layer uses existing Cleona messages for this.
typedef SendValidationRequestCallback = Future<void> Function(
  String validatorNodeIdHex,
  String reportId,
  String reporterNodeIdHex,
  Uint8List bloomFilter,
);

/// Callback to determine available validator candidates.
/// Returns a list of node IDs (from DHT/routing table).
typedef GetValidatorCandidatesCallback = Future<List<String>> Function();

/// Anti-Sybil Transport-Layer Validator.
///
/// Integrates into the message handler:
/// - On incoming CHANNEL_REPORT → call validateReport()
/// - On incoming REACHABILITY_RESPONSE → call handleValidatorResponse()
///
/// Uses existing network infrastructure (no new protocol).
class SybilTransportValidator {
  final ModerationConfig config;
  final CLogger _log;
  final Random _random = Random.secure();

  /// Callback: send validation request to validator.
  SendValidationRequestCallback? onSendValidationRequest;

  /// Callback: determine validator candidates.
  GetValidatorCandidatesCallback? onGetValidatorCandidates;

  /// Pending validations.
  final Map<String, _PendingValidation> _pending = {};

  /// Bloom filter cache per known node (for local validation).
  final Map<String, ReachabilityBloomFilter> _bloomFilterCache = {};

  /// Own Bloom filter (periodically updated).
  ReachabilityBloomFilter? _ownBloomFilter;

  /// Timeout for validator responses.
  final Duration validatorTimeout;

  SybilTransportValidator({
    required this.config,
    this.validatorTimeout = const Duration(seconds: 30),
    CLogger? log,
  }) : _log = log ?? CLogger('SybilTransport');

  // -- Manage own Bloom filter ------------------------------------

  /// Build own Bloom filter from contact list.
  ///
  /// [contacts]: Own direct contacts (nodeIdHex -> nodeId bytes).
  /// [depth]: Depth for transitive contacts (default: 1 = direct only).
  void updateOwnBloomFilter(Map<String, Uint8List> contacts) {
    _ownBloomFilter = ReachabilityBloomFilter();
    for (final nodeId in contacts.values) {
      _ownBloomFilter!.add(nodeId);
    }
    _log.info('Own Bloom filter updated with ${contacts.length} contacts');
  }

  /// Own Bloom filter as bytes (for network transmission).
  Uint8List? get ownBloomFilterBytes => _ownBloomFilter?.bytes;

  /// Cache another node's Bloom filter (received via network).
  void cacheBloomFilter(String nodeIdHex, Uint8List bloomBytes) {
    _bloomFilterCache[nodeIdHex] =
        ReachabilityBloomFilter.fromBytes(bloomBytes);
  }

  // -- Report validation ------------------------------------------------

  /// Validate an incoming report at the transport level.
  ///
  /// Selects K random validators, sends reachability queries,
  /// waits for responses and returns the result.
  ///
  /// Called asynchronously — the report is buffered until the result is ready.
  Future<TransportValidationResult> validateReport({
    required String reportId,
    required String reporterNodeIdHex,
    required Uint8List reporterBloomFilter,
  }) async {
    if (!config.reachabilityEnabled) {
      return TransportValidationResult(
        reporterNodeIdHex: reporterNodeIdHex,
        validatorsReached: 1,
        validatorsContacted: 1,
        accepted: true,
        validationDuration: Duration.zero,
      );
    }

    // Determine validator candidates.
    final candidates = await _getValidatorCandidates();
    if (candidates.isEmpty) {
      _log.warn('No validator candidates available');
      return TransportValidationResult(
        reporterNodeIdHex: reporterNodeIdHex,
        validatorsReached: 0,
        validatorsContacted: 0,
        accepted: false,
        rejectionReason: 'No validators available',
        validationDuration: Duration.zero,
      );
    }

    // Select K random validators (excluding reporter).
    final validators = _selectValidators(
      candidates.where((c) => c != reporterNodeIdHex).toList(),
      config.reachabilityValidatorCount,
    );

    if (validators.isEmpty) {
      return TransportValidationResult(
        reporterNodeIdHex: reporterNodeIdHex,
        validatorsReached: 0,
        validatorsContacted: 0,
        accepted: false,
        rejectionReason: 'No independent validators',
        validationDuration: Duration.zero,
      );
    }

    // Send queries to validators.
    final completer = Completer<TransportValidationResult>();
    final responses = <String, bool?>{};
    for (final v in validators) {
      responses[v] = null; // pending
    }

    final timeoutTimer = Timer(validatorTimeout, () {
      _resolveValidation(reportId);
    });

    _pending[reportId] = _PendingValidation(
      reportId: reportId,
      reporterNodeIdHex: reporterNodeIdHex,
      completer: completer,
      validatorResponses: responses,
      timeoutTimer: timeoutTimer,
    );

    // Send queries.
    // Note: onSendValidationRequest may synchronously call handleValidatorResponse.
    // _resolveValidation is then fired during the loop.
    for (final validatorId in validators) {
      if (completer.isCompleted) break; // Already resolved
      try {
        await onSendValidationRequest?.call(
          validatorId,
          reportId,
          reporterNodeIdHex,
          reporterBloomFilter,
        );
      } catch (e) {
        _log.warn('Could not send validation request to $validatorId: $e');
        responses[validatorId] = false;
      }
    }

    // Check if all have already responded (synchronous callbacks).
    if (!completer.isCompleted && responses.values.every((v) => v != null)) {
      _resolveValidation(reportId);
    }

    return completer.future;
  }

  /// Process a validator's response.
  ///
  /// Called when a validator responds with its reachability result.
  void handleValidatorResponse({
    required String reportId,
    required String validatorNodeIdHex,
    required bool reporterReachable,
  }) {
    final pending = _pending[reportId];
    if (pending == null) {
      _log.warn('Validator response for unknown report $reportId');
      return;
    }

    if (!pending.validatorResponses.containsKey(validatorNodeIdHex)) {
      _log.warn('Response from non-requested validator $validatorNodeIdHex');
      return;
    }

    pending.validatorResponses[validatorNodeIdHex] = reporterReachable;
    _log.info('Validator $validatorNodeIdHex: Reporter ${reporterReachable ? "REACHABLE" : "NOT REACHABLE"}');

    // All responded?
    if (pending.validatorResponses.values.every((v) => v != null)) {
      _resolveValidation(reportId);
    }
  }

  /// Local reachability check (as validator).
  ///
  /// Called when THIS node is queried as a validator.
  /// Checks via Bloom filter whether the reporter is reachable
  /// in our social graph.
  bool checkReachabilityLocally({
    required String reporterNodeIdHex,
    required Uint8List reporterBloomFilter,
  }) {
    if (_ownBloomFilter == null) return false;

    // Check: Is the reporter in our Bloom filter?
    // (Do we know the reporter through our contacts?)
    final reporterBytes = _hexToBytes(reporterNodeIdHex);
    if (_ownBloomFilter!.mightContain(reporterBytes)) {
      return true;
    }

    // Check: Is one of our contacts in the reporter's Bloom filter?
    // (Does the reporter have a mutual contact with us?)
    final reporterFilter = ReachabilityBloomFilter.fromBytes(reporterBloomFilter);
    for (final cachedFilter in _bloomFilterCache.values) {
      // Heuristic: If the reporter has contacts that are also
      // in our cache, they are probably well-connected.
      if (cachedFilter.bytes.length == reporterFilter.bytes.length) {
        var overlap = 0;
        for (var i = 0; i < cachedFilter.bytes.length; i++) {
          overlap += popcount(cachedFilter.bytes[i] & reporterFilter.bytes[i]);
        }
        // Significant overlap indicates network connectivity.
        if (overlap > ReachabilityBloomFilter.filterBits * 0.05) {
          return true;
        }
      }
    }

    return false;
  }

  // -- Internal methods --------------------------------------------------

  Future<List<String>> _getValidatorCandidates() async {
    if (onGetValidatorCandidates != null) {
      return onGetValidatorCandidates!();
    }
    return [];
  }

  List<String> _selectValidators(List<String> candidates, int count) {
    if (candidates.length <= count) return List.from(candidates);
    final selected = <String>[];
    final available = List<String>.from(candidates);
    for (var i = 0; i < count && available.isNotEmpty; i++) {
      final idx = _random.nextInt(available.length);
      selected.add(available.removeAt(idx));
    }
    return selected;
  }

  void _resolveValidation(String reportId) {
    final pending = _pending.remove(reportId);
    if (pending == null || pending.completer.isCompleted) return;

    pending.timeoutTimer.cancel();

    final duration = DateTime.now().difference(pending.startedAt);
    final reached = pending.validatorResponses.values.where((v) => v == true).length;
    final contacted = pending.validatorResponses.length;
    final timedOut = pending.validatorResponses.values.where((v) => v == null).length;
    final respondedTotal = contacted - timedOut;

    // Calculate score based on responses (not timeouts).
    final score = respondedTotal > 0 ? reached / respondedTotal : 0.0;
    final accepted = score >= config.reachabilityThreshold;

    final result = TransportValidationResult(
      reporterNodeIdHex: pending.reporterNodeIdHex,
      validatorsReached: reached,
      validatorsContacted: contacted,
      validatorsTimedOut: timedOut,
      accepted: accepted,
      rejectionReason: accepted ? null : 'Reachability ${(score * 100).toStringAsFixed(0)}% < ${(config.reachabilityThreshold * 100).toStringAsFixed(0)}%',
      validationDuration: duration,
    );

    _log.info('Transport validation completed: $result');
    pending.completer.complete(result);
  }

  /// Clean up pending validations.
  void dispose() {
    for (final pending in _pending.values) {
      pending.timeoutTimer.cancel();
      if (!pending.completer.isCompleted) {
        pending.completer.complete(TransportValidationResult(
          reporterNodeIdHex: pending.reporterNodeIdHex,
          validatorsReached: 0,
          validatorsContacted: 0,
          accepted: false,
          rejectionReason: 'Validator disposed',
          validationDuration: DateTime.now().difference(pending.startedAt),
        ));
      }
    }
    _pending.clear();
  }

  /// Bit count (population count) for Bloom filter overlap.
  static int popcount(int byte) {
    var b = byte;
    b = b - ((b >> 1) & 0x55);
    b = (b & 0x33) + ((b >> 2) & 0x33);
    return (b + (b >> 4)) & 0x0F;
  }

  static Uint8List _hexToBytes(String hex) {
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}

/// Periodic Bloom filter exchange.
///
/// Distributes the own Bloom filter to random peers,
/// so validators can perform local reachability checks.
class BloomFilterExchange {
  final SybilTransportValidator validator;
  final ModerationConfig config;
  final CLogger _log;
  Timer? _exchangeTimer;

  /// Callback: send Bloom filter to a peer.
  Future<void> Function(String peerNodeIdHex, Uint8List bloomBytes)? onSendBloomFilter;

  /// Callback: get random peers from DHT/routing table.
  Future<List<String>> Function()? onGetRandomPeers;

  BloomFilterExchange({
    required this.validator,
    required this.config,
    CLogger? log,
  }) : _log = log ?? CLogger('BloomExchange');

  /// Start periodic exchange (every 5 minutes).
  void start({Duration interval = const Duration(minutes: 5)}) {
    _exchangeTimer?.cancel();
    _exchangeTimer = Timer.periodic(interval, (_) => _exchange());
    _log.info('Bloom filter exchange started (interval: ${interval.inMinutes} min)');
  }

  /// Stop exchange.
  void stop() {
    _exchangeTimer?.cancel();
    _exchangeTimer = null;
  }

  Future<void> _exchange() async {
    final bloomBytes = validator.ownBloomFilterBytes;
    if (bloomBytes == null) return;

    final peers = await onGetRandomPeers?.call() ?? [];
    if (peers.isEmpty) return;

    // Send to 3 random peers (like channel index gossip).
    final random = Random.secure();
    final targets = peers.length <= 3
        ? peers
        : List.generate(3, (_) => peers[random.nextInt(peers.length)]);

    for (final peer in targets) {
      try {
        await onSendBloomFilter?.call(peer, bloomBytes);
      } catch (e) {
        _log.warn('Failed to send Bloom filter to $peer: $e');
      }
    }

    _log.info('Bloom filter sent to ${targets.length} peers');
  }
}

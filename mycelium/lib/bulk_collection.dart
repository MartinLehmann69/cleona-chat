/// One open collection of lane 3 (§9.4 "Lane 3, collection") — what the
/// announcement says about the transfer, and how far the recipient is.
///
/// Its own file since S401: `bulk_collect.dart` is at its line budget. It
/// lives in memory only. That a collection is open stands in the store of
/// its identity (the layer above), never on the delivery layer's disk; the
/// stripes already complete stand in that identity's folder
/// (`bulk_disk.dart`).
library;

import 'dart:typed_data';

import 'package:mycelium/bulk_piece.dart';
import 'package:mycelium/card.dart' show CardAddress;
import 'package:mycelium/media.dart' show stripeNumber;

typedef OnBulkObject = void Function(Uint8List tag, Uint8List object);
typedef OnBulkFailure = void Function(Uint8List tag, String reason);

/// Stripes complete of all stripes — for the transfer phase of the app.
typedef OnBulkProgress = void Function(Uint8List tag, int complete, int stripes);

class BulkCollection {
  /// The identifier `HKDF(K_T, "bulk/tag")` and the key the pieces open
  /// under, `HKDF(K_T, "bulk/seal")` (§9.4 "The transfer key").
  final Uint8List tag;
  final Uint8List seal;

  /// Length and SHA-256 of the object, as announced.
  final int length;
  final Uint8List sha256;

  /// When the announcement came: `TTL_media` runs from there (§9.4
  /// "Holding time"), also across a restart.
  final DateTime started;

  /// The holders the announcement names, at most eleven.
  final List<CardAddress> holders;

  final int stripes;

  /// Stripe -> piece number -> opened block.
  final Map<int, Map<int, Uint8List>> per = {};

  /// Holders that answered "nothing here" / ended their pass, this round.
  final Set<String> nothing = {};
  final Set<String> ended = {};

  /// Complete stripes not yet written to disk.
  final Set<int> unsaved = {};
  final Map<String, int> fromHolder = {};
  final DateTime began = DateTime.now();
  int complete = 0;
  int roundStart = 0;
  int rounds = 0;
  int received = 0;
  int decile = 0;
  OnBulkObject? onObject;
  OnBulkFailure? onFailure;
  OnBulkProgress? progress;

  BulkCollection({
    required Uint8List transferKey,
    required this.length,
    required this.sha256,
    required this.started,
    required this.holders,
  })  : tag = bulkTag(transferKey),
        seal = bulkSealKey(transferKey),
        stripes = stripeNumber(length);

  String get short => tagHex(tag).substring(0, 8);
}

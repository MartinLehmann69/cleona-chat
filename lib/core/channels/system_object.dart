/// The objects of the system channels (v4_2 §16.0, §16.7): report, +1
/// entry, vote and retraction. S407 SK-2.
///
/// An object is public and self-verifying: it carries the Ed25519 public key
/// of its author's report pseudonym and a signature over everything but the
/// beta field (§4.4.3, D-56). It carries NO `author_user_id`, NO identity
/// key and NO rotation chain — the report pseudonym never rotates (D-57).
///
/// ── THE FORMAT (version 1) ────────────────────────────────────────────────
///
/// ```
/// version (1) = 1 | kind (1) | channel (1) | created (4, BE, minutes since
/// 1970-01-01 UTC) | pseudonym (32) | body | signature (64) | stated
/// UserID: length (1, 0 or 32) | bytes
///
/// body, per kind:
///   report  : fingerprint length (1, 0 or 32) | fingerprint | text length
///             (4, BE) | text (UTF-8)
///   plusOne : fingerprint (32)
///   vote    : target (16) | option (1: 0 yes, 1 no, 2 don't care)
///   retract : target (16)
/// ```
///
/// The creation time is in minutes, not hours: a newer vote of the same
/// pseudonym replaces the older (§16.7), and a user who changes a vote
/// within the hour must be "newer". The rate limits count per hour and per
/// day of this stated time.
///
/// The signature covers bytes 0 up to the signature. The trailing UserID is
/// the author's statement, unsigned, and only a beta build sets it (§16.7
/// "Beta builds only", D-57); a live build writes length 0 and a live
/// holder rejects an object whose length is not 0 ([admissibleOn]).
///
/// A target is the 16 B hash part of the target object's identifier (§16.0)
/// — the first 16 B of the SHA-256 of the whole target object.
///
/// The fingerprint of a crash report is the 32 B SHA-256 of
/// `computeCrashFingerprint` (exception type and stack, §16.7 "Dedup and
/// +1"); reports without a fingerprint (log reports, feature requests) carry
/// length 0. Only Bug Log reports may carry one, only Bug Log has +1
/// entries, only Feature Requests have votes.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cleona/core/channels/report_pseudonym.dart';
import 'package:cleona/core/config/network_channel.dart';
import 'package:mycelium/durable_id.dart';

/// The kinds of a system-channel object.
class SystemObjectKind {
  SystemObjectKind._();
  static const int report = 1;
  static const int plusOne = 2;
  static const int vote = 3;
  static const int retract = 4;

  static bool valid(int k) => k >= report && k <= retract;
}

/// The options of a Feature Request vote (§16.7: yes/no/don't care).
class SystemVote {
  SystemVote._();
  static const int yes = 0;
  static const int no = 1;
  static const int dontCare = 2;
}

const int _kVersion = 1;
const int _kHeader = 1 + 1 + 1 + 4 + 32;
const int _kSignature = 64;
const int _kFingerprint = 32;
const int _kUserId = 32;

/// A parsed system-channel object. [bytes] are the exact bytes as carried;
/// the identifier is computed over them (§16.0).
class SystemObject {
  final Uint8List bytes;
  final int kind;
  final int channel;

  /// Creation time as stated by the author, in minutes since the epoch (UTC).
  final int createdMinutes;
  final Uint8List pseudonym;

  /// Report: crash fingerprint or `null`; +1: the fingerprint it adds to.
  final Uint8List? fingerprint;

  /// Report: the structured report text (JSON, as the reporters write it).
  final String text;

  /// Vote / retract: the hash part of the target's identifier.
  final Uint8List? target;
  final int option;

  /// The UserID the author stated (beta only, unsigned), or `null`.
  final Uint8List? statedUserId;

  /// Bytes 0 up to the signature, and the signature.
  final Uint8List signed;
  final Uint8List signature;

  SystemObject._(
      this.bytes,
      this.kind,
      this.channel,
      this.createdMinutes,
      this.pseudonym,
      this.fingerprint,
      this.text,
      this.target,
      this.option,
      this.statedUserId,
      this.signed,
      this.signature);

  /// The 16 B hash part of this object's identifier.
  Uint8List get hash => objectHash(bytes);

  /// The kind-and-size-class byte of the identifier (§16.0): kind in the
  /// high nibble, size class in the low one — 0 up to 128 B, then doubling
  /// (1 ≤ 256 B, 2 ≤ 512 B, …, 15 ≤ 4 MB).
  int get kindSize => (kind << 4) | sizeClassOf(bytes.length);

  /// The identifier this node names, [ageHours] old.
  DurableId id({int ageHours = 0}) =>
      DurableId(channel, ageHours.clamp(0, 0xFFFF), kindSize, hash);

  bool get verifies => ReportPseudonym.verify(signed, signature, pseudonym);

  /// Parses [bytes]; `null` when malformed (truncated, trailing bytes,
  /// unknown version or kind, a field of a length the format does not have).
  /// The signature is NOT checked here — see [verifies].
  static SystemObject? parse(Uint8List bytes) {
    try {
      final b = ByteData.sublistView(bytes);
      var p = 0;
      if (bytes.length < _kHeader + _kSignature + 1) return null;
      if (bytes[p++] != _kVersion) return null;
      final kind = bytes[p++];
      if (!SystemObjectKind.valid(kind)) return null;
      final channel = bytes[p++];
      final created = b.getUint32(p);
      p += 4;
      final pseudonym = Uint8List.fromList(bytes.sublist(p, p + 32));
      p += 32;
      Uint8List? fingerprint;
      var text = '';
      Uint8List? target;
      var option = 0;
      switch (kind) {
        case SystemObjectKind.report:
          final fl = bytes[p++];
          if (fl != 0 && fl != _kFingerprint) return null;
          if (fl > 0) {
            fingerprint = Uint8List.fromList(bytes.sublist(p, p + fl));
            p += fl;
          }
          final tl = b.getUint32(p);
          p += 4;
          if (p + tl > bytes.length) return null;
          text = utf8.decode(bytes.sublist(p, p + tl));
          p += tl;
        case SystemObjectKind.plusOne:
          fingerprint = Uint8List.fromList(bytes.sublist(p, p + _kFingerprint));
          p += _kFingerprint;
        case SystemObjectKind.vote:
          target = Uint8List.fromList(
              bytes.sublist(p, p + kIdentifierHashBytes));
          p += kIdentifierHashBytes;
          option = bytes[p++];
          if (option > SystemVote.dontCare) return null;
        case SystemObjectKind.retract:
          target = Uint8List.fromList(
              bytes.sublist(p, p + kIdentifierHashBytes));
          p += kIdentifierHashBytes;
      }
      final signedEnd = p;
      if (signedEnd + _kSignature + 1 > bytes.length) return null;
      final signature =
          Uint8List.fromList(bytes.sublist(signedEnd, signedEnd + _kSignature));
      p = signedEnd + _kSignature;
      final ul = bytes[p++];
      if (ul != 0 && ul != _kUserId) return null;
      Uint8List? userId;
      if (ul > 0) {
        if (p + ul > bytes.length) return null;
        userId = Uint8List.fromList(bytes.sublist(p, p + ul));
        p += ul;
      }
      if (p != bytes.length) return null;
      return SystemObject._(
          Uint8List.fromList(bytes),
          kind,
          channel,
          created,
          pseudonym,
          fingerprint,
          text,
          target,
          option,
          userId,
          Uint8List.fromList(bytes.sublist(0, signedEnd)),
          signature);
    } on RangeError {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Whether this object may exist on [network] at all (§16.7, D-57): a
  /// live holder rejects an object that names a UserID; on beta the field
  /// is optional.
  bool admissibleOn(NetworkChannel network) =>
      network == NetworkChannel.beta || statedUserId == null;

  /// Whether the kind belongs to the channel: +1 entries and crash
  /// fingerprints only in the Bug Log, votes only in Feature Requests.
  bool get fitsChannel {
    switch (kind) {
      case SystemObjectKind.report:
        return channel == kChannelBugLog ||
            (channel == kChannelFeatureRequests && fingerprint == null);
      case SystemObjectKind.plusOne:
        return channel == kChannelBugLog;
      case SystemObjectKind.vote:
        return channel == kChannelFeatureRequests;
      case SystemObjectKind.retract:
        return channel == kChannelBugLog || channel == kChannelFeatureRequests;
    }
    return false;
  }
}

/// Size class of an object of [length] bytes (see [SystemObject.kindSize]).
int sizeClassOf(int length) {
  var c = 0;
  var limit = 128;
  while (length > limit && c < 15) {
    c++;
    limit <<= 1;
  }
  return c;
}

/// Minutes since the epoch (UTC) — the clock of [SystemObject.createdMinutes].
int minutesOf(DateTime t) =>
    t.toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute;

/// Builds and signs system-channel objects under one report pseudonym.
///
/// [network] decides the beta field: on beta a report names [userId] (as
/// stated by the author, unsigned); on live it is never written, whatever
/// the caller passes (§16.7, D-57). Default: the channel this build runs on
/// ([activeNetworkChannel], the source of `kNetworkChannel`).
class SystemObjectAuthor {
  final ReportPseudonym pseudonym;
  final NetworkChannel network;

  /// The UserID a beta report names; ignored on live.
  final Uint8List? userId;

  SystemObjectAuthor(this.pseudonym, {NetworkChannel? network, this.userId})
      : network = network ?? activeNetworkChannel {
    if (userId != null && userId!.length != _kUserId) {
      throw ArgumentError('UserID must be $_kUserId B');
    }
  }

  Uint8List report(int channel, String text,
      {Uint8List? fingerprint, DateTime? at}) {
    if (fingerprint != null && fingerprint.length != _kFingerprint) {
      throw ArgumentError('fingerprint must be $_kFingerprint B');
    }
    final t = utf8.encode(text);
    final body = BytesBuilder(copy: false)
      ..addByte(fingerprint == null ? 0 : _kFingerprint);
    if (fingerprint != null) body.add(fingerprint);
    body
      ..add(_be32(t.length))
      ..add(t);
    return _sign(SystemObjectKind.report, channel, body.toBytes(), at,
        withUserId: true);
  }

  Uint8List plusOne(Uint8List fingerprint, {DateTime? at}) {
    if (fingerprint.length != _kFingerprint) {
      throw ArgumentError('fingerprint must be $_kFingerprint B');
    }
    return _sign(SystemObjectKind.plusOne, kChannelBugLog, fingerprint, at);
  }

  Uint8List vote(Uint8List target, int option, {DateTime? at}) {
    if (target.length != kIdentifierHashBytes) {
      throw ArgumentError('target must be $kIdentifierHashBytes B');
    }
    if (option < SystemVote.yes || option > SystemVote.dontCare) {
      throw ArgumentError.value(option, 'option');
    }
    return _sign(SystemObjectKind.vote, kChannelFeatureRequests,
        Uint8List.fromList([...target, option]), at);
  }

  Uint8List retract(int channel, Uint8List target, {DateTime? at}) {
    if (target.length != kIdentifierHashBytes) {
      throw ArgumentError('target must be $kIdentifierHashBytes B');
    }
    return _sign(SystemObjectKind.retract, channel, target, at);
  }

  Uint8List _sign(int kind, int channel, Uint8List body, DateTime? at,
      {bool withUserId = false}) {
    final signed = BytesBuilder(copy: false)
      ..addByte(_kVersion)
      ..addByte(kind)
      ..addByte(channel)
      ..add(_be32(minutesOf(at ?? DateTime.now())))
      ..add(pseudonym.publicKey)
      ..add(body);
    final s = signed.toBytes();
    final uid = withUserId && network == NetworkChannel.beta ? userId : null;
    final out = BytesBuilder(copy: false)
      ..add(s)
      ..add(pseudonym.sign(s))
      ..addByte(uid == null ? 0 : _kUserId);
    if (uid != null) out.add(uid);
    return out.toBytes();
  }
}

Uint8List _be32(int v) {
  final b = Uint8List(4);
  ByteData.view(b.buffer).setUint32(0, v, Endian.big);
  return b;
}

/// The invitation card at the service boundary (V4.2 §15.2, §15.3, §15.6).
///
/// This file carries only VALUES — what travels across [ICleonaService]
/// and the IPC boundary. It knows no network and no card as a byte format;
/// reading a card is in `contact/invitation_card_reader.dart`, issuing and
/// redeeming belong to the delivery layer (`mycelium`, attached via the
/// seam in `cleona_service*.dart`).
///
/// Every class has `toJson`/`fromJson`, because every one travels over the
/// Unix socket (Windows: TCP + token) between UI and daemon. The
/// enumerations travel under their `name`, so that a renaming fails loudly
/// on reading instead of silently falling onto an index.
library;

import 'dart:convert';
import 'dart:typed_data';

/// §15.3 — the two kinds the user chooses when issuing.
enum InvitationKind {
  /// A particular person; used up after the first ACCEPTED request.
  /// Default (§15.3 "single (default)").
  single,

  /// To a group; up to `n` acceptances (default 20) or until expiry.
  open;

  static InvitationKind? byName(String? n) {
    for (final k in values) {
      if (k.name == n) return k;
    }
    return null;
  }
}

/// §15.3 — the four validity levels. "Unlimited is written as
/// `0xFFFFFFFF`" stands in the card, not here.
enum InvitationValidity {
  days7(7),
  days30(30),
  days90(90),
  unlimited(null);

  const InvitationValidity(this.days);

  /// `null` = unlimited.
  final int? days;

  /// §15.3: „default 90 d for the single kind, 7 d for the open kind".
  static InvitationValidity defaultFor(InvitationKind kind) =>
      kind == InvitationKind.single ? days90 : days7;

  static InvitationValidity? byName(String? n) {
    for (final v in values) {
      if (v.name == n) return v;
    }
    return null;
  }
}

/// §15.12: the expiry value for "unlimited".
const int kInvitationExpiryUnlimited = 0xFFFFFFFF;

/// §15.12: „standing invitations per node — max. 10".
const int kInvitationStandingCap = 10;

/// An issued card, as the UI shows it.
class InvitationCard {
  const InvitationCard({
    required this.id,
    required this.text,
    required this.packed,
    required this.kind,
    required this.expiryUnixSeconds,
    this.faceToFace = false,
  });

  /// §15.5 "Automatic acceptance, for two paths only": the card was issued
  /// for personal handover (QR shown, NFC). Then [text] is EMPTY — the same
  /// invitation is not additionally offered as a text line, otherwise a
  /// passed-on line would obtain acceptance without a question
  /// (S388-BAU-KONTAKT).
  final bool faceToFace;

  /// The same opaque identifier as [StandingInvitation.id] — so that the UI
  /// knows whether a revocation hit the card currently SHOWN, and then does
  /// not offer it any further.
  final String id;

  /// §15.6: `cleona:1:<base64url>` — the line to copy.
  final String text;

  /// §15.2: the packed card, 90–380 B — the content of the QR code
  /// ("90–380 B binary") and of the NFC record.
  final Uint8List packed;

  final InvitationKind kind;

  /// u32 Unix seconds; [kInvitationExpiryUnlimited] = unlimited.
  final int expiryUnixSeconds;

  bool get unlimited => expiryUnixSeconds == kInvitationExpiryUnlimited;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'packedB64': base64.encode(packed),
        'kind': kind.name,
        'expiry': expiryUnixSeconds,
        if (faceToFace) 'faceToFace': true,
      };

  /// Throws [FormatException] if a mandatory field is missing — showing half
  /// a card would be worse than none.
  static InvitationCard fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final text = j['text'];
    final packed = j['packedB64'];
    final kind = InvitationKind.byName(j['kind'] as String?);
    final expiry = j['expiry'];
    if (id is! String ||
        text is! String ||
        packed is! String ||
        kind == null ||
        expiry is! int) {
      throw FormatException('InvitationCard incomplete: $j');
    }
    return InvitationCard(
      id: id,
      text: text,
      packed: Uint8List.fromList(base64.decode(packed)),
      kind: kind,
      expiryUnixSeconds: expiry,
      faceToFace: j['faceToFace'] == true,
    );
  }
}

/// Why no card was issued. Every reason has its own sentence in the UI —
/// the UI guesses none.
enum InvitationIssueRefusal {
  /// The delivery layer is not attached (yet).
  notConnected,

  /// §15.3: ten invitations already exist.
  capReached,

  /// §15.3: "on one node they all belong to one identity" — invitations are
  /// still standing for another identity of this node.
  otherIdentityStanding,

  /// Every other failure; [InvitationIssueResult.detail] names it for the
  /// log.
  failed;

  static InvitationIssueRefusal? byName(String? n) {
    for (final r in values) {
      if (r.name == n) return r;
    }
    return null;
  }
}

/// Result of `ICleonaService.issueInvitationCard`: exactly one of [card]
/// and [refusal] is set.
class InvitationIssueResult {
  const InvitationIssueResult.issued(InvitationCard this.card)
      : refusal = null,
        detail = null;

  const InvitationIssueResult.refused(InvitationIssueRefusal this.refusal,
      [this.detail])
      : card = null;

  final InvitationCard? card;
  final InvitationIssueRefusal? refusal;
  final String? detail;

  Map<String, dynamic> toJson() => {
        if (card != null) 'card': card!.toJson(),
        if (refusal != null) 'refusal': refusal!.name,
        if (detail != null) 'detail': detail,
      };

  static InvitationIssueResult fromJson(Map<String, dynamic> j) {
    final c = j['card'];
    if (c is Map<String, dynamic>) {
      return InvitationIssueResult.issued(InvitationCard.fromJson(c));
    }
    return InvitationIssueResult.refused(
        InvitationIssueRefusal.byName(j['refusal'] as String?) ??
            InvitationIssueRefusal.failed,
        j['detail'] as String?);
  }
}

/// What goes wrong when READING a card — before any packet (§15.2,
/// §15.3 "before any packet leaves", §15.6).
///
/// The first five are the five findings of the table in §15.6 and
/// correspond one to one to `CardTextErrorKind` from
/// `mycelium/lib/card_text.dart`. [wrongChannel] and [expired] are the two
/// rejections that §15.2 and §15.3 respectively require with a sentence of
/// their own that names them.
enum InvitationReadError {
  notFound,
  truncated,
  corrupted,
  wrongVersion,
  badCharacters,
  wrongChannel,
  expired;

  static InvitationReadError? byName(String? n) {
    for (final e in values) {
      if (e.name == n) return e;
    }
    return null;
  }
}

/// How the redemption turned out.
enum InvitationRedeemOutcome {
  /// The request is out; the contact only stands once the inviter accepts
  /// (§12.5, §15.1 "asks the user, user accepts").
  requestSent,

  /// The card was not readable or was rejected before any packet;
  /// [InvitationRedeemResult.readError] names the finding.
  readError,

  /// The own card of this identity.
  ownCard,

  /// The card's identifier already belongs to a contact.
  alreadyContact,

  /// The inviter did not answer (package (1) did not arrive).
  noAnswer,

  /// The delivery layer is not attached (yet).
  notConnected,

  /// Every other failure; `detail` names it for the log.
  failed;

  static InvitationRedeemOutcome? byName(String? n) {
    for (final o in values) {
      if (o.name == n) return o;
    }
    return null;
  }
}

class InvitationRedeemResult {
  const InvitationRedeemResult(this.outcome,
      {this.readError, this.cardChannel, this.detail});

  final InvitationRedeemOutcome outcome;

  /// Only with [InvitationRedeemOutcome.readError].
  final InvitationReadError? readError;

  /// Only with [InvitationReadError.wrongChannel]: the channel value of the
  /// card (`0x00` live, `0x01` beta, §15.2).
  final int? cardChannel;

  final String? detail;

  Map<String, dynamic> toJson() => {
        'outcome': outcome.name,
        if (readError != null) 'readError': readError!.name,
        if (cardChannel != null) 'cardChannel': cardChannel,
        if (detail != null) 'detail': detail,
      };

  static InvitationRedeemResult fromJson(Map<String, dynamic> j) =>
      InvitationRedeemResult(
        InvitationRedeemOutcome.byName(j['outcome'] as String?) ??
            InvitationRedeemOutcome.failed,
        readError: InvitationReadError.byName(j['readError'] as String?),
        cardChannel: j['cardChannel'] as int?,
        detail: j['detail'] as String?,
      );
}

/// A standing invitation, as the list shows it (§15.3 "The count is
/// shown in the interface, with revocation as the one-click remedy").
class StandingInvitation {
  const StandingInvitation({
    required this.id,
    required this.kind,
    required this.expiryUnixSeconds,
    required this.accepted,
    required this.maxAcceptances,
    this.label = '',
    this.atBufferLimit = false,
  });

  /// Opaque, local identifier for the revocation. NOT the code — that
  /// belongs in no list that travels across a process boundary.
  final String id;
  final InvitationKind kind;
  final int expiryUnixSeconds;
  final int accepted;
  final int maxAcceptances;
  final String label;

  /// §15.4 point 2 "This invitation is at its buffer limit" (ES-9, S388):
  /// the buffer of waiting requests of THIS invitation is full, the next
  /// one displaces the oldest. Source: `InvitationBuffer.atBufferThreshold`
  /// in mycelium — a getter, not a packet. Waiting requests do not survive
  /// a restart; after that the value is `false`.
  final bool atBufferLimit;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'expiry': expiryUnixSeconds,
        'accepted': accepted,
        'max': maxAcceptances,
        'label': label,
        'bufferLimit': atBufferLimit,
      };

  static StandingInvitation fromJson(Map<String, dynamic> j) =>
      StandingInvitation(
        id: j['id'] as String,
        kind: InvitationKind.byName(j['kind'] as String?) ??
            (throw FormatException('StandingInvitation without kind: $j')),
        expiryUnixSeconds: j['expiry'] as int,
        accepted: j['accepted'] as int? ?? 0,
        maxAcceptances: j['max'] as int? ?? 1,
        label: j['label'] as String? ?? '',
        atBufferLimit: j['bufferLimit'] == true,
      );
}

/// Result of `ICleonaService.standingInvitations`.
///
/// [items] is `null` if the list could not be read — that is NOT "no
/// invitations" and gets a sentence of its own.
class StandingInvitationsResult {
  const StandingInvitationsResult(this.items, {this.notConnected = false});
  const StandingInvitationsResult.unavailable({this.notConnected = false})
      : items = null;

  final List<StandingInvitation>? items;
  final bool notConnected;

  Map<String, dynamic> toJson() => {
        if (items != null) 'items': items!.map((i) => i.toJson()).toList(),
        'notConnected': notConnected,
      };

  static StandingInvitationsResult fromJson(Map<String, dynamic> j) {
    final raw = j['items'];
    final nc = j['notConnected'] == true;
    if (raw is! List) return StandingInvitationsResult.unavailable(notConnected: nc);
    return StandingInvitationsResult(
      raw
          .whereType<Map<String, dynamic>>()
          .map(StandingInvitation.fromJson)
          .toList(growable: false),
      notConnected: nc,
    );
  }
}

/// How a revocation turned out.
enum InvitationRevokeOutcome {
  revoked,

  /// There is no standing invitation with this identifier (any more).
  unknown,

  notConnected;

  static InvitationRevokeOutcome? byName(String? n) {
    for (final o in values) {
      if (o.name == n) return o;
    }
    return null;
  }
}

/// Result of `ICleonaService.revokeAllInvitationCards` (§15.3 „Bulk
/// revocation").
class InvitationRevokeAllResult {
  const InvitationRevokeAllResult(this.count) : notConnected = false;
  const InvitationRevokeAllResult.notConnected()
      : count = 0,
        notConnected = true;

  final int count;
  final bool notConnected;

  Map<String, dynamic> toJson() => {'count': count, 'notConnected': notConnected};

  static InvitationRevokeAllResult fromJson(Map<String, dynamic> j) =>
      j['notConnected'] == true
          ? const InvitationRevokeAllResult.notConnected()
          : InvitationRevokeAllResult(j['count'] as int? ?? 0);
}

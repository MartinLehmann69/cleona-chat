import 'dart:convert';
import 'dart:typed_data';

import '../crypto/sodium_ffi.dart';
import 'cold_start.dart';
import 'entry_record.dart';

/// The external rendezvous (§11.3, stage A) — the substrate-independent part.
///
/// WHAT IS HERE AND WHAT NOT. The design from V4.0 has two halves:
/// a FORM (an encrypted endpoint record under a tag derived from
/// the channel constant and the time epoch) and a SUBSTRATE (back then public
/// Nostr relays). The form is here; the substrate is not, and
/// for a hard reason: Nostr signs its events with
/// secp256k1 Schnorr, and this tree does not carry that — neither as a package
/// nor as a native library. Taking on a crypto dependency is
/// a decision about the supply chain, not a programming task.
///
/// Therefore: [ExternalRendezvous] is the seam. Whoever hooks in a substrate
/// implements it — and does not have to invent the form again.
///
/// WHY THE FORM IS GOOD FOR ANYTHING AT ALL. The record lies
/// encrypted under a tag that only someone who has the
/// channel constant can derive. A third party sees opaque lumps under opaque
/// tags. That does NOT protect against someone with the app — the constant
/// is shipped with it, and channel separation is explicitly
/// operational, not a security boundary (§11). It protects against the
/// operator of the substrate and against casual reading along. The rest
/// is listed as B-24 in the declared limits.
abstract interface class ExternalRendezvous {
  /// Stores a lump under a tag.
  Future<void> publish(Uint8List lookupTag, Uint8List blob);

  /// Fetches what lies under a tag. Empty is a valid answer.
  Future<List<Uint8List>> resolve(Uint8List lookupTag);

  /// Whether the substrate is there at all.
  bool get isAvailable;
}

/// Tag and key of the external rendezvous.
///
/// Both derived from the channel constant and the day — no directory,
/// no publication to third parties, no agreement.
abstract final class ExternalTag {
  /// The tag of the day. It moves daily so that an observer of the
  /// substrate cannot follow a single tag over months.
  static Uint8List forDay(String channel, int day) => SodiumFFI().hkdfSha256(
        Uint8List.fromList(utf8.encode(channel)),
        salt: Uint8List.fromList(utf8.encode('cleona-entry-rendezvous/v1')),
        info: Uint8List.fromList(utf8.encode('tag/$day')),
        length: 32,
      );

  /// The key under which the record lies.
  static Uint8List keyForDay(String channel, int day) =>
      SodiumFFI().hkdfSha256(
        Uint8List.fromList(utf8.encode(channel)),
        salt: Uint8List.fromList(utf8.encode('cleona-entry-rendezvous/v1')),
        info: Uint8List.fromList(utf8.encode('key/$day')),
        length: 32,
      );

  static int dayOf(DateTime utc) => utc.millisecondsSinceEpoch ~/ 86400000;

  /// Encrypts an entry record: `nonce(12) ‖ chiffrat`.
  static Uint8List seal(EntryRecord r, Uint8List key) {
    final nonce = SodiumFFI().randomBytes(12);
    final ct = SodiumFFI().aesGcmEncrypt(r.encode(), key, nonce);
    final out = Uint8List(12 + ct.length);
    out.setRange(0, 12, nonce);
    out.setRange(12, out.length, ct);
    return out;
  }

  /// Opens a lump. `null` if it does not hold — silently (E-83).
  static EntryRecord? open(Uint8List blob, Uint8List key) {
    if (blob.length <= 12 + 16) return null;
    try {
      final clear = SodiumFFI().aesGcmDecrypt(
          Uint8List.fromList(blob.sublist(12)),
          key,
          Uint8List.fromList(blob.sublist(0, 12)));
      // The record checks itself — also and especially here, because the
      // substrate belongs to a stranger.
      return EntryRecord.decodeAt(clear, 0)?.record;
    } catch (_) {
      return null;
    }
  }
}

/// The external source for the cold-start cascade.
final class ExternalEntrySource implements EntrySource {
  final ExternalRendezvous rendezvous;
  final String channel;
  final DateTime Function() now;

  /// How many days back are searched.
  ///
  /// Two, not one: the tag moves at midnight UTC, and whoever
  /// starts shortly after would otherwise find an empty tag although yesterday
  /// everything was there.
  final int daysBack;

  ExternalEntrySource({
    required this.rendezvous,
    this.channel = 'cleona-beta',
    DateTime Function()? clock,
    this.daysBack = 2,
  }) : now = clock ?? (() => DateTime.now().toUtc());

  @override
  EntrySourceKind get kind => EntrySourceKind.external;

  @override
  bool get available => rendezvous.isAvailable;

  /// ── DEDUPLICATION, AND HERE (S362) ────────────────────────────────
  ///
  /// Until S362 the fetch ran without any deduplication, on NEITHER of the two
  /// axes:
  ///
  ///   * across RELAYS — `NostrProvider.resolveRaw` concatenates the answers
  ///     of all relays (`nostr_provider.dart:225-231`).
  ///     The same event, accepted by 7 relays, comes back 7 times.
  ///   * across DAYS — the loop below queries `daysBack` tags. A
  ///     node that runs past midnight UTC lies under
  ///     both.
  ///
  /// Measured in the field (29.08. 12:26:48, Pixel 8 Pro): "86 records, 86
  /// new". The upper bound of the DIFFERENT nodes behind them is
  /// `86 / (2 x 7) ≈ 6`, if every relay held every event.
  ///
  /// WHY AT THIS PLACE AND NOT IN THE PROVIDER. Here both
  /// axes come together; the provider knows only one. And deduplication is over
  /// the LUMP, before unsealing — that is the cheapest comparison
  /// (one byte field against one byte field instead of an AES-GCM run per
  /// repetition) and the only one that also applies to lumps that
  /// cannot be opened at all.
  ///
  /// What that does NOT fix: the bytes are already off the wire by then. That is
  /// the job of `kRelayEventLimit`.
  @override
  Future<List<EntryRecord>> fetch() async {
    final today = ExternalTag.dayOf(now());
    final out = <EntryRecord>[];
    final seen = <String>{};
    for (var d = today; d > today - daysBack; d--) {
      final blobs = await rendezvous.resolve(ExternalTag.forDay(channel, d));
      final key = ExternalTag.keyForDay(channel, d);
      for (final b in blobs) {
        if (!seen.add(base64Encode(b))) continue;
        final r = ExternalTag.open(b, key);
        if (r != null) out.add(r);
      }
    }
    return out;
  }

  /// Stores the own record — only whoever is reachable does that
  /// (E-63: being reachable and publishing oneself are two
  /// decisions).
  Future<void> publishOwn(EntryRecord own) async {
    final d = ExternalTag.dayOf(now());
    await rendezvous.publish(ExternalTag.forDay(channel, d),
        ExternalTag.seal(own, ExternalTag.keyForDay(channel, d)));
  }
}

/// When the own entry record should be stored anew.
///
/// ── THE FINDING THAT MAKES THIS CLASS NECESSARY (S362) ───────────────
///
/// `_appointmentMaintain` (`v41_attach.dart`) held the day last stored
/// in a PROCESS-LOCAL variable that stood at `-1` on every start.
/// The condition "only store if the day has moved" could
/// therefore never apply at start: **every process start stored**.
///
/// That is expensive, because the external entry stores with a THROWAWAY KEY
/// per event — v4_1 §11.3 explicitly wants it so, so that "a
/// query returns *every* publisher rather than the last one". The price
/// of this design is that under NIP-33 no placement replaces its own previous one
/// (a relay replaces only with the same `(pubkey, kind, d-Tag)`).
/// A phone that starts the app ten times a day thus left under the
/// network-wide shared day tag ten records instead of one —
/// nine of them with an address that may already be dead.
///
/// ── WHY THE DAY ALONE DOES NOT SUFFICE ───────────────────────────────
///
/// The obvious fix — remembering the day across restarts — would be
/// too coarse and would break something more important: on mobile and behind CGNAT
/// the address changes constantly, and **a new placement after an
/// address change is necessary**, otherwise a dead address stands under the day tag
/// until midnight UTC. The mark therefore holds BOTH: the day
/// and a fingerprint of the announced addresses. It is stored when
/// either of the two has changed — and otherwise not.
///
/// ── WHY A FINGERPRINT AND NOT THE ADDRESSES ──────────────────────────
///
/// The mark lies on disk. A fingerprint has a fixed length, makes
/// the comparison a string comparison, and the file does not name the
/// own public addresses in plain text — even though it
/// is written encrypted anyway.
final class DepositMark {
  /// UTC day of the last placement (`ExternalTag.dayOf`), `-1` = never yet.
  final int tag;

  /// Fingerprint of the addresses announced back then.
  final String addresses;

  const DepositMark({required this.tag, required this.addresses});

  /// Never stored yet. Stands explicitly there instead of being `null`:
  /// "never yet" and "not readable" are to take the same path.
  static const DepositMark never = DepositMark(tag: -1, addresses: '');

  /// The fingerprint of the addresses of a record.
  ///
  /// Over host AND port, in the order of the record: a
  /// port change (`drawDataPort` at the first start, a
  /// runtime port change) is just as much a reason to store anew as a
  /// new IP. The order counts too, because it counts in the record —
  /// `EntryRecord.host` is the FIRST address.
  static String fingerprintFrom(EntryRecord r) {
    final text = r.addresses.map((a) => '${a.host}:${a.port}').join('|');
    return SodiumFFI()
        .sha256(Uint8List.fromList(utf8.encode(text)))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Must it be stored under the tag of [today] with these addresses?
  bool demandsDeposit(int today, String fingerprint) =>
      tag != today || addresses != fingerprint;

  Map<String, dynamic> toJson() => {'tag': tag, 'adressen': addresses};

  /// Value equality, explicit and not incidental.
  ///
  /// The caller decides by `neu != alt` whether the mark must go to disk.
  /// Without this operator it would decide by object identity —
  /// which TODAY would come out right by chance, because
  /// `_depositWennNecessary` returns the same object in the nothing-to-do case.
  /// Exactly this kind of proxy is not to stand here:
  /// the question is "has the mark changed", not "is it the same
  /// object".
  @override
  bool operator ==(Object other) =>
      other is DepositMark && other.tag == tag && other.addresses == addresses;

  @override
  int get hashCode => Object.hash(tag, addresses);

  /// Reads a mark. Everything that does not fit is [never] — an
  /// unreadable mark may cost at most one placement too many, never one
  /// too few.
  static DepositMark fromJson(Map<String, dynamic>? j) {
    if (j == null) return never;
    final t = j['tag'];
    final a = j['adressen'];
    if (t is! int || a is! String) return never;
    return DepositMark(tag: t, addresses: a);
  }
}

/// No substrate hooked in.
///
/// Stands explicitly there instead of being absent: a cascade whose last
/// step is silently missing looks like a complete one that found
/// nothing.
final class NoRendezvous implements ExternalRendezvous {
  const NoRendezvous();

  @override
  bool get isAvailable => false;

  @override
  Future<void> publish(Uint8List lookupTag, Uint8List blob) async {}

  @override
  Future<List<Uint8List>> resolve(Uint8List lookupTag) async =>
      const <Uint8List>[];
}

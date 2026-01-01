import 'dart:convert';
import 'dart:typed_data';

import 'package:mycelium/kinds.dart' as kinds;

import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:mycelium/first_contact.dart' show Send, Report;
import 'package:mycelium/message.dart' show DeliveryState;
import 'package:mycelium/envelope.dart';
import 'package:mycelium/group_data.dart';
export 'package:mycelium/group_data.dart';

/// A message to a group — out ONCE, not once per member.
///
/// ```
/// ALICE                       STORAGE                  BOB/CAROL/DAVE
///  closed with K_G,       ->   under depositIdentifier -> collect there,
///  signed Ed+ML-DSA            three neighbours         open with K_G
/// ```
///
/// Four decisions of the owner are in it:
///
/// * **ALWAYS a group key** (E-15), no threshold. Pairwise, "hello
///   everyone" cost the sender 386,350 B at 50 members.
/// * **Post-quantum signed** (E-16): Ed25519 AND ML-DSA-65. The
///   key only proves "someone from the group"; WHO wrote is
///   proven by the signature alone. 3373 B per message, paid deliberately.
/// * **On joining, the inviter decides** (E-14): without change one
///   delivery (the new member reads older messages), with change N.
/// * **On leaving there is ALWAYS a change**, without choice: the one leaving knows
///   the old key, everything later must be closed to them.
///
/// **The deposit identifier is DERIVED from the key:**
/// `SHA-256(K_G ‖ generation ‖ "gruppe")`. If it were fixed (say the 8 B
/// group identifier), a departed member would keep collecting every piece
/// — it could read nothing, but it would see how much traffic there is and
/// when. This way the deposit place moves along with EVERY change.
///
/// **Symmetric closing uses XSalsa20-Poly1305**
/// (`SodiumFFI.secretBoxEncrypt`, like `history.dart`): its 24 B nonce may
/// be drawn randomly, while the 12 B of AES-GCM with a key in
/// N hands would need counter bookkeeping that does not exist here.
///
/// No network: the pairwise key delivery ([Send]) and the one
/// deposit ([Deposit]) come in as callbacks. What is displayed is the
/// WEAKEST state across all legs — the four values from
/// `message.dart`, no fifth.

const int kGroupsIdentifierLength = 8;
const int kGroupsKeyLength = 32;

/// A deposited group message (0x60), a sealed key for
/// exactly one member (0x61).
/// From the registry, not set here.
const int kKindGroupsMessage = kinds.kGroupsMessage;
const int kKindKeyDelivery = kinds.kKeyDelivery;

/// Header code: a signature from here passes nowhere else.
final Uint8List kGroupsHeaderCode =
    Uint8List.fromList(<int>[0x4d, 0x59, 0x5a, 0x47]);

/// Deposits [content] under [underIdentifier] and says whether it sufficed — fits onto
/// `PostBoxDeposit.deposit` (three neighbours, two receipts suffice).
typedef Deposit = Future<(bool done, int acknowledged)> Function(
    Uint8List content, Uint8List underIdentifier);

class GroupsError implements Exception {
  final String reason;
  GroupsError(this.reason);
  @override
  String toString() => 'GruppenFehler: $reason';
}

/// A group as ONE side sees it. Who may do what: `group_data.dart`.
class Group {
  String name;
  final PostBox me;
  final Deposit deposit;
  final void Function(GroupsInbound)? onInbound;
  final Report? report;
  final Send _out;
  Uint8List? _identifier;
  int _generation = 0;
  /// Every generation that this side has ever held. Whoever was admitted
  /// without a change has only the current one — and therefore reads nothing
  /// older once a change has happened.
  final Map<int, Uint8List> _key = {};
  final List<Member> _members = [];
  /// What THIS side may do. The creator is owner; every other side
  /// learns its role with the key delivery, not from itself.
  Role _myRole = Role.member;
  /// Who may issue keys in this group — the Ed25519 part of their
  /// address (32 B). Set at creation or at the first admission, afterwards
  /// immutable. See [keyCame].
  Uint8List? _issuerPk;
  final List<GroupsOutbound> sent = [];
  final List<GroupsInbound> incoming = [];
  /// [create] `true`: identifier and first key are drawn randomly
  /// (generation 0). `false`: the view of an invitee — both come in with
  /// the first sealed delivery. There are no members
  /// here: whoever is in is in via [memberAdmit] — otherwise they would
  /// never have got the key.
  Group(
      {required this.me,
      required Send send,
      required this.deposit,
      this.name = '',
      bool create = false,
      this.onInbound,
      this.report})
      : _out = send {
    if (!create) return;
    final sodium = SodiumFFI();
    _identifier = sodium.randomBytes(kGroupsIdentifierLength);
    _key[0] = sodium.randomBytes(kGroupsKeyLength);
    _myRole = Role.owner;
    _issuerPk = me.address.ed25519Pk;
  }

  bool get hasKey => _identifier != null && _key.isNotEmpty;
  int get generation => _generation;
  Role get myRole => _myRole;
  List<Member> get members => List.unmodifiable(_members);
  Uint8List get identifier =>
      _identifier ?? (throw GroupsError('no key received yet'));
  Uint8List get _now =>
      keyFrom(_generation) ??
      (throw GroupsError('no key received yet'));

  /// The key of a generation, or `null`. Narrow access for
  /// `group_read.dart` — like `PostBox.secretParts` it exists only
  /// because Dart knows no visibility between two files of the same layer.
  /// It gives away nothing that this side does not hold anyway.
  Uint8List? keyFrom(int gen) => _key[gen];

  /// Where it lies: `SHA-256(K_G ‖ generation ‖ "gruppe")`, file header.
  Uint8List get depositIdentifier => SodiumFFI().sha256((BytesBuilder()
        ..add(_now)
        ..add(_u32(_generation))
        ..add(utf8.encode('group')))
      .toBytes());

  /// Closed once, signed once, deposited once — whether three or
  /// fifty are listening changes nothing about that. Sending needs no list.
  Future<GroupsOutbound> send(String text) async {
    final packet = _pack(text);
    final leg = GroupsLeg(null);
    final outbound = GroupsOutbound(
        groupsIdentifier: identifier, generation: _generation, text: text,
        legs: [leg], at: DateTime.now());
    sent.add(outbound);
    leg.state = DeliveryState.inTransit;
    final (done, acknowledged) = await deposit(packet, depositIdentifier);
    leg.state = done ? DeliveryState.delivered : DeliveryState.failed;
    report?.call('Group message G$_generation: ${packet.length} B, one '
        'deposit, $acknowledged receipt(s) -> ${outbound.state.name}');
    return outbound;
  }

  /// Admits [m]. **E-14: the inviter decides.** [withChange]
  /// `false`: only [m] gets the current key — one delivery,
  /// [m] reads older messages. `true`: new key to all — N deliveries,
  /// nothing earlier readable.
  GroupsOutbound memberAdmit(Member m, {required bool withChange}) {
    _check(mayAdmit(_myRole, m.role, withChange));
    if (_members.any((x) => x.address.sameIdentity(m.address))) {
      throw GroupsError('is already a member');
    }
    _members.add(m);
    return withChange ? _change() : _deliver([m]);
  }

  /// Removes the member with this [Address]. **No choice:** there is
  /// always a change, otherwise the one leaving would keep reading along. N-1 deliveries.
  GroupsOutbound memberRemove(Address address) {
    _check(mayRemove(_myRole));
    // The last owner cannot leave: afterwards nobody could
    // change any more, and the group would be stuck forever on its generation.
    // Whoever really wants to end it takes [dissolve].
    if (address.sameIdentity(me.address) &&
        !_members.any((m) => m.role == Role.owner)) {
      throw GroupsError('the only owner cannot remove themselves '
          '— dissolve the group');
    }
    final before = _members.length;
    _members.removeWhere((m) => m.address.sameIdentity(address));
    if (_members.length == before) throw GroupsError('was not a member');
    return _change();
  }

  /// Gives a member a different role. Only the owner, and
  /// [Role.owner] is not assigned — reasoning in
  /// `group_data.dart`. No change: the current key stays, exactly
  /// one delivery goes to the one affected.
  GroupsOutbound roleChange(Address address, Role newRole) {
    _check(mayRoleChange(_myRole, newRole));
    final i = _members.indexWhere((m) => m.address.sameIdentity(address));
    if (i < 0) throw GroupsError('was not a member');
    _members[i] = _members[i].withRole(newRole);
    return _deliver([_members[i]]);
  }

  /// A member has changed its KEM generation: its copy is
  /// replaced — only by the adoption rule, never for a different
  /// identity. Otherwise the next key delivery would seal against
  /// a generation that it no longer holds after seven days.
  void memberAddressAdopt(Address fresh) {
    for (var i = 0; i < _members.length; i++) {
      final m = _members[i];
      if (Address.adopt(m.address, fresh)) {
        _members[i] = Member(address: fresh, destination: m.destination, role: m.role);
      }
    }
  }

  /// Dissolves the group — only the owner. Acts LOCALLY: keys,
  /// identifier and members are gone, nothing goes out and nothing
  /// opens any more. Deliberately no packet goes out: that would need a
  /// new kind, and numbers are assigned solely in `kinds.dart`.
  void dissolve() {
    _check(mayDissolve(_myRole));
    _key.clear();
    _members.clear();
    _identifier = null;
    _issuerPk = null;
    _myRole = Role.member;
  }

  void _check(String? no) {
    if (no != null) throw GroupsError(no);
  }

  GroupsOutbound _change() {
    _generation += 1;
    _key[_generation] = SodiumFFI().randomBytes(kGroupsKeyLength);
    return _deliver(_members);
  }

  /// The only part that costs per member: a sealed envelope with
  /// identifier, generation, key, role, issuer, name. Nobody sends
  /// anything to themselves.
  ///
  /// Role and issuer stand INSIDE the seal, packed anew per recipient:
  /// the role is theirs, not that of the group. The issuer is
  /// 32 B (Ed25519 part) instead of a whole address (3208 B) — the
  /// counter-check in [keyCame] needs no more, it compares exactly this
  /// field with the authenticated sender of the envelope.
  GroupsOutbound _deliver(List<Member> to) {
    final namedBytes = Uint8List.fromList(utf8.encode(name));
    if (namedBytes.length > 255) throw GroupsError('Name zu lang');
    final issuer = _issuerPk ?? me.address.ed25519Pk;
    final legs = <GroupsLeg>[];
    for (final m in to.where((m) => !m.address.sameIdentity(me.address))) {
      final content = (BytesBuilder()
            ..add(identifier)
            ..add(_u32(_generation))
            ..add(_now)
            ..addByte(m.role.index)
            ..add(issuer)
            ..addByte(namedBytes.length)
            ..add(namedBytes))
          .toBytes();
      final envelope = Envelope.seal(
          plaintext: content, recipient: m.address, sender: me);
      _out((BytesBuilder()
            ..addByte(kKindKeyDelivery)
            ..add(envelope))
          .toBytes(), m.destination);
      legs.add(GroupsLeg(m.address, DeliveryState.inTransit));
    }
    report?.call('key G$_generation sealed to ${legs.length} '
        'member(s)');
    return GroupsOutbound(
        groupsIdentifier: identifier, generation: _generation, text: null,
        legs: legs, at: DateTime.now());
  }

  /// A sealed key delivery (0x61) comes in — called from
  /// `group_read.dart`.
  ///
  /// The sender is CHECKED, not discarded: [Envelope.unseal] returns
  /// it authenticated, and only the remembered issuer may send a
  /// key. Without this check anyone who knows the
  /// group identifier could slip a key to a member.
  void keyCame(Uint8List packet) {
    final (plaintext, sender) = Envelope.unseal(
        envelope: cut(packet, 1, packet.length), recipient: me);
    const header =
        kGroupsIdentifierLength + 4 + kGroupsKeyLength + 1 + 32 + 1;
    if (plaintext.length < header) throw GroupsError('Key too short');
    var p = 0;
    final found = cut(plaintext, p, p += kGroupsIdentifierLength);
    final gen = ByteData.sublistView(plaintext).getUint32(p, Endian.big);
    p += 4;
    final k = cut(plaintext, p, p += kGroupsKeyLength);
    final roleByte = plaintext[p];
    p += 1;
    if (roleByte >= Role.values.length) throw GroupsError('Role unknown');
    final issuer = cut(plaintext, p, p += 32);
    final namedLength = plaintext[p];
    p += 1;
    if (p + namedLength > plaintext.length) {
      throw GroupsError('Name does not fit');
    }
    if (_identifier == null) {
      // FIRST ADMISSION — the only place where a sender unknown until then
      // gets through, and deliberately so: this side knows at
      // this moment neither identifier nor key nor a single
      // member. There is nothing against which it could measure the sender.
      // If it rejected anyway, nobody could ever join a
      // group. What it does instead: it remembers whom the
      // delivery names as issuer, and from the SECOND packet on it is bound
      // to that — a stranger can afterwards neither exchange the key
      // nor fast-forward a generation nor change the role.
      // This is carried outside: the envelope is sealed to the own
      // address, and one gives that only to someone from whom one expects an
      // invitation.
      _identifier = found;
      _issuerPk = issuer;
      name = utf8.decode(cut(plaintext, p, p + namedLength));
    } else {
      if (!byteEqual(found, identifier)) {
        throw GroupsError('Key of a different group');
      }
      if (_issuerPk == null ||
          !byteEqual(sender.ed25519Pk, _issuerPk!)) {
        throw GroupsError(
            'Key from someone who was not allowed to send it');
      }
    }
    final first = _key.isEmpty;
    _key[gen] = k;
    _myRole = Role.values[roleByte];
    if (first || gen > _generation) _generation = gen;
    report?.call('key G$gen adopted (${_myRole.name})');
  }

  Uint8List _pack(String text) {
    final sodium = SodiumFFI();
    final oqs = OqsFFI()..init();
    final textBytes = Uint8List.fromList(utf8.encode(text));
    final signed = charsData(_generation, me.address, textBytes);
    // The envelope signs only for ONE recipient; a
    // group message has none — so it is signed directly here.
    final secret = me.secretParts();
    final edSig = sodium.signEd25519(signed, secret.ed25519Sk);
    final dsaSig = oqs.mlDsaSign(signed, secret.mlDsaSk);
    final inside = (BytesBuilder()
          ..add(identifier)
          ..add(me.address.toBytes())
          ..add(_u16(dsaSig.length))
          ..add(edSig)
          ..add(dsaSig)
          ..add(textBytes))
        .toBytes();
    final nonce = sodium.randomBytes(cryptoSecretBoxNonceBytes);
    return (BytesBuilder()
          ..addByte(kKindGroupsMessage)
          ..add(_u32(_generation))
          ..add(nonce)
          ..add(sodium.secretBoxEncrypt(inside, _now, nonce)))
        .toBytes();
  }

  /// What is signed is header code, identifier, generation, the complete
  /// sender address and the text — the generation belongs in it, otherwise
  /// the same signature would still hold after a change.
  Uint8List charsData(int gen, Address sender, Uint8List text) =>
      (BytesBuilder()
            ..add(kGroupsHeaderCode)
            ..add(identifier)
            ..add(_u32(gen))
            ..add(sender.toBytes())
            ..add(text))
          .toBytes();
}

Uint8List _u32(int v) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.big);
Uint8List _u16(int v) =>
    Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.big);

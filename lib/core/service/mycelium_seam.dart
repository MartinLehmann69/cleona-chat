/// The seam between the app and the delivery layer V4.2 (`package:mycelium`).
///
/// It replaces `attachV41` from `lib/core/tagline/v41_attach.dart`. The
/// difference is not the size, but that almost nothing stands here: the
/// old seam had to plug together prekeys, sealer, opener, host and LAN
/// entry by hand (3275 lines). mycelium does all of that itself —
/// `Envelope` seals per message, `PostBox` holds the keys, `Node` finds
/// neighbours. What remains to be done is a translation.
///
/// ── AND THE TRANSLATION IS LOSSLESS ─────────────────────────────
///
/// Measured on 14.09.2026, and it is the finding on which the whole
/// replacement hangs: both sides match one to one.
///
/// | App | mycelium |
/// |---|---|
/// | `IdentityContext.ed25519PublicKey`/`…SecretKey` | `Address.ed25519Pk` / `ed25519Sk` |
/// | `…mlKemPublicKey`/`…SecretKey` | `Address.mlKemPk` / `mlKemSk` |
/// | `…mlDsaPublicKey`/`…SecretKey` | `Address.mlDsaPk` / `mlDsaSk` |
/// | `ContactInfo.ed25519Pk`/`mlDsaPk`/`mlKemPk` | `Address` of the counterpart |
///
/// **No key migration, no renewed first contact.** Since S385 (E1)
/// mycelium keeps X25519 separately and the generation as `state` — like
/// the app (`x25519PublicKey`, `keyRotatedAt`/`keysCreatedAt`,
/// `ContactInfo.x25519Pk`/`kemSeenAt`). The complete connection of the
/// rotation is part of the later seam; here stands only the translation.
///
/// Since S385 (cut F) the delivery layer is a [Host] with N mailboxes:
/// ONE port for all identities of the daemon (V4.2 §4.5.1). Since S387
/// the app hangs on it: [hostStart] at the three start paths,
/// [serviceRegister]/[serviceDeregister] at runtime.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/config/rendezvous_relays.dart';
import 'package:cleona/core/crypto/constant_time.dart';
import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/crypto/hd_wallet.dart';
import 'package:cleona/core/identity/identity_context.dart';
import 'package:cleona/core/service/cleona_service.dart';
import 'package:cleona/core/service/port_mapping.dart';
import 'package:cleona/core/service/port_mapping_setting.dart';
import 'package:cleona/core/update/binary_http_server.dart';
import 'package:cleona/core/update/data_port_http.dart';
import 'package:cleona/core/util/network_metered.dart' show coverMeteredRead;
import 'package:mycelium/update.dart' show updateAttach;
import 'package:mycelium/readiness.dart' show ReadinessState;
import 'package:mycelium/card_address.dart' show CardAddress;
import 'package:mycelium/node_helpers.dart' show cardChannel;
import 'package:mycelium/node_cover.dart' show NodeCover;
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/mailbox_start.dart';
import 'package:mycelium/envelope.dart';
import 'package:mycelium/update_cover_route.dart' show updateCoverRouteAttach;
import 'package:mycelium/host.dart';

/// The contact does not carry all three keys — then there is no address,
/// and a fallback would be worse than the error: it would seal against the
/// wrong recipient.
class SeamError implements Exception {
  final String reason;
  SeamError(this.reason);
  @override
  String toString() => 'NahtFehler: $reason';
}

// ── THE MAPPING UserID <-> mycelium ADDRESS, IN ONE PLACE ────────────
//
// THERE IS ONE IDENTIFIER (owner decision "Kennung = A", 15.09.2026, S388).
// V4.2 §4.1: `userId = SHA-256(kIdentityDomain ‖ Ed25519 ‖ ML-DSA-65)`;
// §15.2: the card fingerprint is "the identifier of §4.1". Thus
//   * the app UserID (`HdWallet.computeUserId`, `IdentityContext.userId`),
//   * the mycelium identifier (`Address.identifier`) and
//   * the fingerprint of the card
// are THE SAME value. Until S388 three different calculations stood here
// and a translation between them. The seam therefore no longer computes
// anything: [userIdFrom] IS the identifier, and [addressHeardTo] compares
// by the anchor Ed25519 + ML-DSA — the same keys from which the
// identifier follows.

/// The app's UserID for the identity behind [a] — the mycelium identifier
/// itself, no second calculation path.
///
/// LIMIT, named (step C, not to be decided here): the app computes its
/// OWN UserID via the FOUNDING keys (rotation chain, v4.2 §4.1 "stable
/// anchor"), mycelium keeps a NEW identifier after a change of the signing
/// keys (owner decision 14.09.2026, `address.dart`). After an emergency
/// rotation [a] returns the current keys and thus a different identifier
/// than the pinned UserID. For the routine rotation (§4.5.4) that does not
/// apply: it only changes X25519 + ML-KEM, and those do not belong in the
/// identifier.
Uint8List userIdFrom(Address a) => a.identifier;

/// Does [a] belong to [k]? The anchor is compared — Ed25519 AND ML-DSA —,
/// not the KEM generation (it rotates, the identity stays). `false` if the
/// contact record does not carry the anchor.
bool addressHeardTo(Address a, ContactInfo k) {
  final ed = k.ed25519Pk;
  final dsa = k.mlDsaPk;
  if (ed == null || ed.isEmpty || dsa == null || dsa.isEmpty) return false;
  return constantTimeEquals(a.ed25519Pk, ed) &&
      constantTimeEquals(a.mlDsaPk, dsa);
}

/// The mycelium address of a counterpart from the app's contact record.
///
/// All three keys are nullable in `ContactInfo`, because a contact can
/// come about there already before first contact (`status: pending`). If
/// one is missing, the counterpart is not addressable — that is a
/// statement about the contact, not an error of the seam.
Address addressFrom(ContactInfo k) {
  final ed = k.ed25519Pk;
  final x = k.x25519Pk;
  final kem = k.mlKemPk;
  final dsa = k.mlDsaPk;
  final state = k.kemSeenAt;
  if (ed == null || x == null || kem == null || dsa == null || state == null) {
    throw SeamError('Contact ${k.displayName} has no complete '
        'address (ed25519: ${ed != null}, x25519: ${x != null}, '
        'mlKem: ${kem != null}, mlDsa: ${dsa != null}, '
        'state: ${state != null}) — before first contact this is normal');
  }
  return Address(
      ed25519Pk: ed,
      mlDsaPk: dsa,
      x25519Pk: x,
      mlKemPk: kem,
      state: state.millisecondsSinceEpoch);
}

/// The own post box from the app's identity.
///
/// The identity stays where it is. mycelium is handed it and creates NO
/// second one — if it were otherwise, the same person would have two
/// identities after the switch-over, and the cards of the one would not be
/// answered by the other.
PostBox postBoxFrom(IdentityContext id) {
  final state = id.keyRotatedAt ?? id.keysCreatedAt;
  if (state == null) {
    throw SeamError('Identity without the time of its KEM generation');
  }
  return PostBox.outSplit(
    address: Address(
      ed25519Pk: id.ed25519PublicKey,
      mlDsaPk: id.mlDsaPublicKey,
      x25519Pk: id.x25519PublicKey,
      mlKemPk: id.mlKemPublicKey,
      state: state.millisecondsSinceEpoch,
    ),
    ed25519Sk: id.ed25519SecretKey,
    x25519Sk: id.x25519SecretKey,
    mlKemSk: id.mlKemSecretKey,
    mlDsaSk: id.mlDsaSecretKey,
    // The app keeps the previous generation for 32 d; mycelium only uses it
    // within its own deadline from `state` (7 d) and discards it itself
    // afterwards.
    previous: id.previousX25519Sk == null || id.previousMlKemSk == null
        ? null
        : (x25519Sk: id.previousX25519Sk!, mlKemSk: id.previousMlKemSk!),
  );
}

/// The host's directory: `<baseDir>/mycelium` — `host.enc` (fixed port,
/// neighbours) and `post_box.enc` (what this node holds for third
/// parties). It belongs to the DEVICE, not to an identity (V4.2 §4.5.1).
Directory hostDirectoryIn(String baseDir) =>
    Directory('$baseDir/mycelium')..createSync(recursive: true);

/// The directory of an identity's mailbox: `<profileDir>/mycelium` — memory
/// (post box, contacts, invitations) and histories.
Directory mailboxDirectoryIn(String profileDir) =>
    Directory('$profileDir/mycelium')..createSync(recursive: true);

/// The host's file key. THE SAME device-wide, seed-derived key under which
/// the app protects its other files per node
/// (`HdWallet.deriveSharedFileEncKey`, S362) — mycelium derives no key of
/// its own, so that there is no second secret someone would have to back
/// up. `masterSeed == null` falls back, as there, to the legacy path of
/// `FileEncryption`.
Uint8List hostKey(String baseDir, Uint8List? masterSeed) =>
    FileEncryption(
      baseDir: baseDir,
      key: masterSeed == null ? null : HdWallet.deriveSharedFileEncKey(masterSeed),
    ).effectiveKey;

/// What mycelium needs to register the mailbox of [service].
///
/// The key is the file key of THIS identity (`CleonaService.fileEnc`) — the
/// same class as `conversations.json.enc`.
/// [CleonaServiceMycelium.takeMyceliumInbound] carries every inbound into
/// the same receive path that the UI gets today (`handleApplicationFrame`).
///
/// ── THE ACCEPTANCE (S388): ONE decision, and it is made in the app ──
///
/// V4.2 §12.5: "A contact exists only after an explicit acceptance. The
/// delivery layer exposes this as a single decision point and holds no
/// policy of its own." mycelium buffers every request (re-contact and a
/// card handed over in person excepted) and reports it ONCE via
/// `onContactRequest`; a callback that decides immediately has not existed
/// since ES-10. The seam hangs on it:
///   * [CleonaServiceMycelium.takeMyceliumContactRequest] creates the
///     `pending` contact and asks the user (`onContactRequestReceived`);
///   * `acceptContactRequest` decides with `accept: true` BEFORE the
///     CONTACT_REQUEST_RESPONSE goes out;
///   * `deleteContact` on a `pending` contact (inbox "Ablehnen") decides
///     with `accept: false`.
/// Until S387 it said here that mycelium accepts by itself (`?? true`) —
/// that only held before `029c2c55` and after the merge made every join
/// wait without end.
MailboxDetails mailboxDetailsFor(CleonaService service) => MailboxDetails(
      mailboxDirectoryIn(service.profileDir),
      service.fileEnc.effectiveKey,
      me: postBoxFrom(service.identity),
      onContactRequest: service.takeMyceliumContactRequest,
      onMessage: service.takeMyceliumInbound,
    );

/// The services per host — for the ONE readiness edge the host has
/// (`Host.onReadiness`, one receiver). An `Expando`, because the host
/// belongs to mycelium and carries no field for the app.
final Expando<Set<CleonaService>> _servicesPerHost = Expando('mycelium-services');

/// Starts the ONE host of this process with one mailbox per service.
///
/// Replaces `startV41Node` + `attachV41` (per identity) at the three start
/// paths `service_daemon.dart`, `main.dart`, `ios_background_fetch.dart`.
/// The services must be STARTED (`startService`) before the host starts:
/// at start it collects and delivers immediately, and an inbound to a
/// service that has not yet loaded its conversations would be an
/// acknowledged but lost message.
///
/// [port] 0 means: mycelium chooses the fixed port itself and remembers it
/// (`HostMemory.portSet`). A named port wins and is not remembered — the
/// app names its device port (`deviceDataPort`).
///
/// READINESS (V4.2 §22.7.1): `CleonaService.readinessState` reads
/// `Host.readiness` live; the EDGE for it is carried by this callback to
/// every attached service as `onStateChanged` — the same edge that the IPC
/// broadcast and the tray hang on. Set AT start (the callback never fires
/// when being set), no clock.
///
/// NO ENTRY POINT (V4.2 §11.7, owner decision 15.09.2026): until S388 a
/// parameter `bootstrap` stood here, together with reading an environment
/// variable with entry addresses. Both are removed — there is no address,
/// no port and no variable that prescribes an entry. The node finds
/// neighbours via the sources of §11.8: remembered, call, cards, and only
/// when those yield nothing, the external entries (§11.9).
Future<Host> hostStart({
  required List<CleonaService> services,
  required String baseDir,
  required Uint8List key,
  int port = 0,
  void Function(String)? report,
}) async {
  if (services.isEmpty) {
    throw StateError('a host needs at least one service — without a '
        'mailbox the node would start up mute');
  }
  final attached = <CleonaService>{};
  void readinessChanged(ReadinessState state, int responding) {
    report?.call('mycelium:readiness ${state.name} '
        '($responding responding neighbours)');
    for (final d in List.of(attached)) {
      d.onStateChanged?.call();
    }
  }

  // §4.5.4/S363 — THE COLD-START ROTATION GATE GETS ITS EDGE BACK.
  //
  // The gate reverses the order: first harvest, then announce. Otherwise a
  // device that comes up after days seals its rotation announcement
  // against exactly the contact keys it did not keep up to date during its
  // absence. Derivation and calculated price:
  // `cold_start_rotation_gate.dart`.
  //
  // Until S392 the reporter was set exclusively by `attachV41`
  // (`runtime.node.addHarvestRunListener(service.reportHarvestRun)`), and
  // `attachV41` has had no caller since the replacement. mycelium has had
  // the substitute ready since S385 (`Host.start(onFirstCollection:)` ->
  // `NodePostBox.onFirstCollection`), but it stayed unset: the gate
  // therefore ALWAYS opened via the fallback period (one hour, ~120 empty
  // checks on the 30 s clock) and logged in the process "es gibt kein
  // erreichbares zustaendiges Relais" — even when collection ran
  // flawlessly. With this line the fallback message is true again.
  //
  // NO NEW CLOCK (working rule 5): the callback fires on the collection run
  // that §8.2 runs at its edges anyway (start, new neighbour, network
  // change). No packet, no timer — on the contrary, it REPLACES the
  // waiting time of the fallback period.
  //
  // TO EVERY ATTACHED SERVICE, not only to the first: the host has ONE
  // node and N mailboxes (§4.5.1), every identity keeps its own gate. The
  // same distribution as [readinessChanged], and for the same reason via
  // the living set instead of via a copy: `attached` is only filled after
  // `Host.start`, and the first completed run needs at least one network
  // round — it cannot overtake the filling below (between
  // `await Host.start` and the `return` there is no further `await`).
  void firstCollection() {
    for (final d in List.of(attached)) {
      d.reportHarvestRun();
    }
  }

  final first = services.first;
  final host = await Host.start(
    hostDirectoryIn(baseDir),
    key,
    port: port,
    onFirstCollection: firstCollection,
    // The relays of the own card (V4.2 §11.9 "which relays"). The ONE
    // existing relay configuration of the app is `RendezvousRelays`
    // (environment, file in the device folder, built-in list); the card
    // takes the first three of it (§15.2).
    relay: RendezvousRelays.forNode(baseDir, onNote: report),
    report: report,
    first: mailboxDetailsFor(first),
    onReadiness: readinessChanged,
  );
  _servicesPerHost[host] = attached;
  // The cover rate follows the network kind (V4.2 §5.3, W1): read now and
  // at every `Host.networkChanged` (`node_cover.dart`), never on a clock.
  host.node.coverAttach(coverMeteredRead);
  first.myceliumAttach(host.mailboxes.first);
  attached.add(first);
  for (final d in services.skip(1)) {
    serviceRegister(host, d);
  }
  return host;
}

/// Binds the public update (M1+/P1, §26.5.4/§26.6.1) to the host — for ONE
/// service per process, [service] (the start paths pass the first: it
/// reports a cached manifest first and thus becomes the source of
/// `UpdateOffer`).
///
/// The channel comes from `cardChannel` — the same place that computes card
/// and identifier; there is no second determination here.
///
/// The four moments, each once, no additional traffic:
/// * start: setting `updateCarrier` asks (behind the start collection of
///   `Host.start` in the same sequence).
/// * new neighbour: [Host.onNewNeighbours], set here.
/// * network change and app open: the start paths call
///   `updateManifestAsk()` after the end of `networkChanged` or
///   `collect` respectively.
void attachUpdateToService(Host host, CleonaService service,
    {void Function(String)? report}) {
  final a = updateAttach(host, channel: cardChannel, report: report);
  service.updateCarrier = a;
  // §5.5 rule 2: a drawn cover packet carries a piece of the update instead
  // of filling. That is NOT a delivery path — the fetch path above runs
  // unchanged, even with the cover stream switched off (§3.1, §26.6.1:
  // "Push makes fetching cheaper; it does not replace it").
  //
  // The gate is the tier from §22.6: the reserve-limited one (Android,
  // iOS) TAKES pieces, but puts none into its own cover packets. The same
  // limit was kept by the replaced layer as `UpdateCoverFill.pushes`
  // (`cleona_service_update.dart`: `pushes: !mobil`); it stands here
  // because the delivery layer reads no platform.
  final mobil = Platform.isAndroid || Platform.isIOS;
  updateCoverRouteAttach(host.node.coverStream, a.holder, a.assembler,
      pushes: () => !mobil);
  host.onNewNeighbours = () => unawaited(service.updateManifestAsk());
}

/// Registers the mailbox of [service] at runtime at the running host —
/// the same port, the same node (new identity, recovered identity).
Mailbox serviceRegister(Host host, CleonaService service) {
  final p = host.register(mailboxDetailsFor(service));
  service.myceliumAttach(p);
  _servicesPerHost[host]?.add(service);
  return p;
}

/// Deregisters the mailbox of [service]. The LAST mailbox stays at the
/// node (`Node.deregister` throws otherwise): then the caller has to stop
/// the whole host anyway, and its [Host.stop] saves.
void serviceDeregister(Host host, CleonaService service,
    {void Function(String)? report}) {
  _servicesPerHost[host]?.remove(service);
  final p = service.myceliumDetach();
  if (p == null) return;
  if (host.mailboxes.length <= 1) {
    report?.call('mycelium:last mailbox stays until the host is stopped');
    return;
  }
  host.deregister(p);
}

/// Binds the HTTP delivery (§26.6.5) to the host's port number.
///
/// Replaces the HTTP switch from `attachV41` (`v41_attach.dart`), which
/// falls with `tagline/`. Without this call the node has neither LAN link
/// (§26.6.6) nor invitation link (§26.6.3). If an address family does not
/// bind, it is reported and carried on — delivery does not hang on it.
Future<DataPortHttp> deliveryStart(
  Host host,
  BinaryHttpServer http, {
  void Function(String)? report,
}) async {
  final d = DataPortHttp(port: host.port, http: http, log: report ?? (_) {});
  await d.start();
  return d;
}

/// Binds the HTTP delivery to the host port with the delivery server of
/// the FIRST service that has one — the same choice that `attachV41` made
/// ("one port, one switch"; the running binary is the same for all
/// identities).
Future<DataPortHttp?> deliveryForServices(
  Host host,
  Iterable<CleonaService> services, {
  void Function(String)? report,
}) async {
  for (final d in services) {
    final http = d.binaryHttpServer;
    if (http != null) return deliveryStart(host, http, report: report);
  }
  report?.call('mycelium:no service with delivery server — no '
      'HTTP delivery at the host port (§26.6.5)');
  return null;
}

// ── THE PORT MAPPING (task D, V4.2 §7.3, §5.4) ─────────────────────
//
// An `Expando`, for the same reason as `_servicesPerHost` above: the port
// mapping belongs to the HOST (one router, one port), not to an identity,
// and `Host` gets no field of its own for it — it is a property of the
// APP seam, not of the delivery layer.

final Expando<PortMapping> _portMappingPerHost = Expando('port_mapping');

/// The port mapping of this host, or `null` as long as [portMappingToEdge]
/// has not yet seen it. An integrator who wants to publish a confirmed
/// mapping (§11.9, the board) attaches to [PortMapping.onMapping] here.
PortMapping? portMappingFrom(Host host) => _portMappingPerHost[host];

/// Binds the port mapping to [host] and triggers it — at start AND at every
/// network change (§7.3: the same call at both edges, [PortMapping.toEdge]
/// decides itself whether it is the first or a later one).
/// [baseDir]/[key] are the same as for [hostStart] — the setting W9 lies
/// device-wide, under the same key as the host, no second secret.
///
/// Does NOT query the router (no `await` on the result) — the RFC 6886
/// backoff takes eight and a half minutes in the worst case, and neither a
/// node start nor a network change may wait for it.
Future<PortMapping> portMappingToEdge(
  Host host, {
  required String baseDir,
  required Uint8List key,
  void Function(String)? report,
}) async {
  var p = _portMappingPerHost[host];
  if (p == null) {
    final active = portMappingConfigured(baseDir, key);
    if (!active) {
      report?.call('mycelium:port mapping off by setting (W9) — '
          'no router is asked');
    }
    p = PortMapping(port: host.port, active: active, log: report);
    _portMappingPerHost[host] = p;
    // S391: the proof goes to the board (§11.8a, W6), and a granted mapping
    // is a reachable address that is published (§11.9). An IPv4 mapping IS
    // the public address; an IPv6 pinhole opens the own address, which
    // already stands in the interface list — only republish there.
    final pa = p;
    host.network.mappingProven = () => pa.mappingProven;
    host.network.keepAlive
      ..ipv4Mapped = (() => pa.ipv4Proven)
      ..ipv6Mapped = (() => pa.ipv6Proven);
    pa.onMapping = (outside, outsidePort) {
      if (outside.type == InternetAddressType.IPv4) {
        host.node.publicAddress =
            CardAddress(Uint8List.fromList(outside.rawAddress), outsidePort);
      }
      host.addressLearned();
    };
  }
  await p.toEdge();
  return p;
}

/// MANDATORY when shutting down [host]. Without this call the
/// coordinator's renewal timer keeps the Dart VM alive for up to an hour
/// (see `port_mapping.dart`). A host without port mapping
/// (`active: false`, or [portMappingToEdge] never called) makes this call a
/// no-op.
Future<void> portMappingLayDown(Host host) async {
  final p = _portMappingPerHost[host];
  if (p == null) return;
  await p.layDown();
  _portMappingPerHost[host] = null;
}

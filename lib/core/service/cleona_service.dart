import 'package:cleona/core/service/twin_sync_wire.dart';
import 'package:cleona/core/bulk/bulk_block_seal.dart'
    show kSealedBulkBlockBytes;
import 'package:cleona/core/bulk/bulk_control.dart';
import 'package:cleona/core/bulk/bulk_sender.dart' show plannedBlocksFor;
import 'package:cleona/core/bulk/bulk_keys.dart'
    show bulkContentHash, bytesEqualConstantTime;
import 'package:cleona/core/bulk/bulk_lane.dart';
import 'package:cleona/core/bulk/bulk_params.dart' show kFountainWorthwhileBytes;
import 'package:cleona/core/service/media_bulk_lane.dart';
import 'package:cleona/core/service/media_bulk_transport.dart';
import 'package:cleona/core/service/v41_routing.dart';
import 'package:cleona/core/service/v41_outbox.dart';
import 'package:cleona/core/bulk/responsibility.dart' show kResponsibleRelays;
import 'package:cleona/core/sync/cover_stream.dart'
    show CoverSaver, CoverSaverOutcome;
import 'package:cleona/core/tagline/entry_sources.dart' show personEntryHints;
import 'package:cleona/core/tagline/pair_registry.dart';
import 'package:cleona/core/tagline/message_seal.dart';
import 'package:cleona/core/tagline/device_line.dart';
import 'package:cleona/core/tagline/own_line.dart';
import 'package:cleona/core/tagline/delivery_api.dart';
import 'package:cleona/core/tagline/delivery_state.dart';
import 'package:cleona/core/sync/delivery_params.dart' show kDeliveryFamilies;
import 'package:cleona/core/tagline/v41_host.dart';
import 'package:cleona/core/tagline/frame_split.dart';
import 'package:cleona/core/tagline/invite_line.dart';
import 'package:cleona/core/link_io/port_mapper.dart' show PortMapper;
import 'package:cleona/core/util/local_addresses.dart'
    show dialableLocalAddresses;
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:cleona/core/crypto/constant_time.dart';
import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/crypto/plaintext_sweep.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/per_message_kem.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/crypto/pq_isolate.dart';
import 'package:cleona/core/crypto/hd_wallet.dart';
import 'package:cleona/core/recovery/legacy_guardian_state.dart';
import 'package:cleona/core/recovery/recovery_bundle_content.dart';
import 'package:cleona/core/tagline/recovery_line.dart';
import 'package:cleona/core/recovery/recovery_keys.dart';
import 'package:cleona/core/crypto/network_secret.dart';
import 'package:cleona/core/crypto/seed_phrase.dart';
import 'package:cleona/core/storage/channel_index.dart';
import 'package:cleona/core/storage/mailbox_store.dart';
import 'package:cleona/core/storage/message_store.dart';
import 'package:cleona/core/media/media_store.dart';
import 'package:cleona/core/media/media_sweep.dart';
import 'package:cleona/core/media/media_vault.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/identity/kem_generation.dart';
import 'package:cleona/core/service/cold_start_rotation_gate.dart';
import 'package:cleona/core/identity/device_delegation.dart';
import 'package:cleona/core/identity/rotation_co_auth.dart';
import 'package:cleona/core/identity/linked_device_keys.dart';
import 'package:cleona/core/identity/linked_device_keys_store.dart';
import 'package:cleona/core/service/device_pairing_service.dart';
import 'package:cleona/core/moderation/moderation_config.dart';
import 'package:cleona/core/contact/contact_seed.dart'
    show ContactSeedBuilder, ContactSeedDataSource, EntrySeedCandidate;
import 'package:cleona/core/contact/invite_class.dart';
import 'package:cleona/core/contact/invite_ledger.dart';
import 'package:cleona/core/contact/invite_store.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/link/data_port.dart';
import 'package:cleona/core/calls/call_transport_v41.dart' show CallPlaneD;
import 'package:cleona/core/service/multi_interface_mode.dart';
import 'package:cleona/core/util/hex.dart';
import 'package:cleona/core/rendezvous/peer_rescue_bundle.dart';
import 'package:cleona/core/service/sender_identity_snapshot.dart';
import 'package:cleona/core/identity/identity_context.dart';
import 'package:cleona/core/codec/reed_solomon.dart';
import 'package:cleona/core/service/app_version.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/core/service/service_context.dart';
import 'package:cleona/core/service/channel_moderation_service.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/stats/network_stats.dart';
import 'package:cleona/core/calls/call_integration.dart';
import 'package:cleona/core/calls/call_manager.dart';
import 'package:cleona/core/calls/group_call_manager.dart';
import 'package:cleona/core/calls/voice_session.dart' show VoiceEventRecord;
import 'package:cleona/core/platform/app_paths.dart';
import 'package:cleona/core/service/key_rotation_retry_manager.dart';
import 'package:cleona/core/service/notification_sound_service.dart';
import 'package:cleona/core/archive/voice_transcription_service.dart';
import 'package:cleona/core/archive/voice_transcription_config.dart';
import 'package:cleona/core/archive/voice_transcription_types.dart';
import 'package:cleona/core/archive/archive_config.dart';
import 'package:cleona/core/archive/archive_manager.dart';
import 'package:cleona/core/archive/archive_network.dart';
import 'package:cleona/core/archive/archive_transport.dart';
import 'package:cleona/core/archive/share_identity.dart';
import 'package:cleona/core/update/update_manifest.dart';
import 'package:cleona/core/update/binary_fetch_client.dart';
import 'package:cleona/core/update/binary_fountain.dart';
import 'package:cleona/core/update/cover_fill_blocks.dart';
import 'package:cleona/core/update/binary_fragment_store.dart';
import 'package:cleona/core/update/binary_http_server.dart';
import 'package:cleona/core/update/binary_update_manager.dart';
import 'package:cleona/core/update/bootstrap_web_app.dart';
import 'package:cleona/core/update/delta_update_manager.dart';
import 'package:cleona/core/update/foreign_binary_acquirer.dart';
import 'package:cleona/core/update/invite_link.dart';
import 'package:cleona/core/update/invite_link_service.dart';
import 'package:cleona/core/update/physical_transfer_helper.dart';
import 'package:cleona/core/update/install_source.dart';
import 'package:cleona/core/update/binary_seeder.dart';
import 'package:cleona/core/update/update_carrier.dart';
import 'package:cleona/core/rendezvous/binary_rendezvous_manager.dart';
import 'package:cleona/core/media/link_preview_fetcher.dart';
import 'package:cleona/core/calendar/calendar_manager.dart';
import 'package:cleona/core/calendar/sync/calendar_sync_service.dart';
import 'package:cleona/core/polls/poll_manager.dart';
import 'package:cleona/core/service/calendar_protocol_service.dart';
import 'package:cleona/core/service/harvest_event.dart';
import 'package:cleona/core/service/poll_service.dart';
import 'package:cleona/core/service/call_service.dart';
import 'package:cleona/core/services/key_change_policy.dart';
import 'package:cleona/core/channels/system_channels.dart';
import 'package:cleona/core/channels/system_channel_records.dart';
import 'package:cleona/core/channels/contact_issue_reporter.dart';
import 'package:cleona/core/channels/crash_reporter.dart';
import 'package:cleona/core/rendezvous/rendezvous_types.dart';
import 'package:cleona/core/rendezvous/rendezvous_provider.dart'
    show EndpointAddress;
import 'package:fixnum/fixnum.dart';
import 'package:cleona/generated/proto/app_payloads.pb.dart' as proto;
import 'package:cleona/generated/proto/transport_v3.pb.dart' as proto;
import 'package:cleona/core/config/network_channel.dart'
    show activeNetworkChannel, NetworkChannel;
import 'package:cleona/core/contact/invitation_card_reader.dart';
import 'package:cleona/core/service/mycelium_seam.dart'
    show addressFrom, addressHeardTo, userIdFrom, SeamError;
import 'package:mycelium/invitation.dart' as mycelium
    show Kind, kLabelAtMostBytes, kAtMostStanding;
import 'package:mycelium/first_contact.dart' as mycelium
    show ContactRequest, Introduction, IntroductionError;
import 'package:mycelium/memory.dart' as mycelium show Contact;
import 'package:mycelium/card.dart' as mycelium show Card;
// §7.1: "no route" means NONE of the three addresses — `routesEmpty` is the one
// place that decides that (S390, finding B-1).
import 'package:mycelium/card_address.dart' as mycelium show routesEmpty;
import 'package:mycelium/card_text.dart' as mycelium
    show CardTextError, asInvitationText;
// Without prefix: an extension from an `as mycelium show` import is reported by the
// analyzer as "shown, but isn't used", and without the import the getter is missing.
import 'package:mycelium/node_invitation.dart' show InvitationBuffer;
import 'package:mycelium/node_helpers.dart' as mycelium show hexFrom;
import 'package:mycelium/message.dart' as mycelium show Outbound, Inbound, DeliveryState;
import 'package:mycelium/mailbox.dart' as mycelium
    show Mailbox, MailboxError, identifierFrom, contactPlaceholderName;
import 'package:mycelium/mailbox_outbound.dart' as mycelium show MailboxOutbound;
import 'package:mycelium/mailbox_inbound.dart' as mycelium show MailboxInbound;
import 'package:mycelium/mailbox_invitation.dart' as mycelium show MailboxInvitation;
import 'package:mycelium/envelope.dart' as mycelium show Address;
// Without prefix, for the same reason as `node_invitation.dart` above.
import 'package:mycelium/host_contact_seats.dart' show HostContactSeats;

// Re-export types so existing imports still work
export 'package:cleona/core/service/service_types.dart';

// The ten `cleona_service_v3_*.dart` parts fell with the CUT
// (31.08.2026, 4 022 lines). What of it was NOT V3 stands in
// `cleona_service_pure.dart` — the cut was file-granular, and that is
// justified there.
part 'cleona_service_pure.dart';
part 'cleona_service_receive.dart';
part 'cleona_service_recovery.dart';
part 'cleona_service_restore.dart';
part 'cleona_service_update.dart';
part 'cleona_service_contact_request.dart';
part 'cleona_service_media.dart';
part 'cleona_service_identity.dart';
part 'cleona_service_state.dart';
part 'cleona_service_msgstate.dart';
part 'cleona_service_identity_deletion.dart';
part 'cleona_service_lockout.dart';
part 'cleona_service_deviceset.dart';
part 'cleona_service_rotation_window.dart';
part 'cleona_service_recovery_bundle.dart';
part 'cleona_service_mycelium.dart';

// `AppFrameDispatchOutcome` STOOD HERE — REMOVED ON 2026-09-03.
//
// The enum was the return value of
// `CleonaService.handleIncomingApplicationPacket` and controlled the
// multi-identity loop in `service_daemon.onApplicationFramePayload`
// (§2.4 step 9). BOTH ends fell with the CUT of 2026-08-31:
// the V3 receive entry point (justification in `cleona_service_receive.dart`,
// header of the extension `V3ReceivePathOps`) and the callback of the deleted
// `CleonaNode`. What remained was a type without producer and without consumer.
//
// SEARCH SET (2026-09-03, across `lib/ test/ scripts/ proto/ android/ ios/
// macos/ windows/ linux/`): `AppFrameDispatchOutcome` as a word — 1 hit,
// the declaration itself. Each of the three values individually as a word —
// 1 hit each, likewise only the declaration. As a string in
// quotation marks — 0. In `snake_case` — 0. In `proto/` — 0. As
// `export ... show` — 0. An unqualified value in a `switch` is
// ruled out, because the TYPE would have to be named for that.
//
// NO BLOCKER: the enum prevented nothing. The V4.1 receive side
// (`V41Host.accept` -> `MessageSealer.open` -> `acceptV41Frame` ->
// `handleApplicationFrame`) has no counterpart and needs none — it
// has no multi-identity loop, because the cell already arrives
// pair-bound.

// `_liveMediaFastPathTypes` stood here — the allow list of the
// live media fast path. It fell with its only reader
// (`_tryLiveMediaFastPath`); justification in
// `cleona_service_receive.dart` (gap G-13, plane D).

/// Why a peer is not sending video right now (§10.6, Spec-Erratum E2).
///
/// The Dart-side mirror of the wire enum `VideoOffReason`. It exists so that
/// nothing above the protocol layer has to import the generated protobuf —
/// `lib/ui/` imports none today and should not start here.
///
/// **Invariante I12.** Every value describes the *sender's own* transmission.
/// None of them is an instruction, a permission or a prohibition aimed at the
/// peer, and no such value may be added: Cleona has no message with which one
/// side can switch the other side's camera off.
enum CallVideoOffReason {
  /// No reason was given, or the peer sent a reason this build does not know.
  ///
  /// Treated as "no picture, and we cannot say why". It is deliberately **not**
  /// folded into [userDisabled]: claiming the peer chose this, when the wire
  /// said something we could not read, would state intent as fact. Forward
  /// compatibility depends on this staying distinct — see the extension rule
  /// in `proto/app_payloads.proto::VideoOffReason`.
  unspecified,

  /// The peer switched their own video off. A deliberate act, not a fault.
  userDisabled,

  /// The peer cannot send: no supported encoder step produces frames that fit
  /// under the current per-frame ceiling. Wire form of
  /// `CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE` (`native/cleona_video/cleona_video.h`,
  /// Spec-Erratum E1), raised by the rate control of V1.17.
  ///
  /// The display for this must differ from [userDisabled] — that difference is
  /// the entire point of E2.
  bandwidthInsufficient,
}

/// What a peer last told us about **its own** video in a call (§10.6, V1.12).
///
/// Immutable on purpose. It is a report about the far side, never a lever on
/// the near side: holding one of these must not change what this device sends
/// (I12).
class PeerCallMediaState {
  const PeerCallMediaState({
    required this.callIdHex,
    required this.peerUserIdHex,
    required this.sendingVideo,
    required this.videoOffReason,
    required this.stateSeq,
    required this.receivedAt,
  });

  /// Call this state belongs to (hex of the 16-byte call id).
  final String callIdHex;

  /// The peer that announced it (hex of its 32-byte user id).
  final String peerUserIdHex;

  /// True while the peer says it is sending video.
  final bool sendingVideo;

  /// Only meaningful while [sendingVideo] is false;
  /// `CallVideoOffReason.unspecified` otherwise.
  final CallVideoOffReason videoOffReason;

  /// Monotonic per (call, peer). Kept so a caller can tell a fresh state from
  /// a repeat.
  final int stateSeq;

  final DateTime receivedAt;

  @override
  String toString() => 'PeerCallMediaState(call=${callIdHex.length >= 8 ? callIdHex.substring(0, 8) : callIdHex}, '
      'peer=${peerUserIdHex.length >= 8 ? peerUserIdHex.substring(0, 8) : peerUserIdHex}, '
      'sendingVideo=$sendingVideo, reason=${videoOffReason.name}, seq=$stateSeq)';
}

/// Central orchestrator: wires node, contacts, messaging, and manages state.
/// Now takes a shared CleonaNode + IdentityContext instead of creating its own node.
class CleonaService implements ICleonaService, ContactSeedDataSource, ServiceContext {
  @override
  final String profileDir;
  @override
  String displayName;
  @override
  int port;
  final String networkChannel;
  final CLogger _log;

  late final ContactSeedBuilder _contactSeedBuilder = ContactSeedBuilder(this);
  @override
  ContactSeedBuilder get contactSeedBuilder => _contactSeedBuilder;

  /// The identity this service operates on behalf of.
  @override
  final IdentityContext identity;

  // ── `node` IS GONE (CUT, 31.08.2026) ────────────────────────────────
  //
  // Here stood `final CleonaNode node` — transport, routing table, DHT,
  // NAT, AckTracker, statistics collector in one field. `lib/core/node/` is
  // deleted; a replacement field does NOT exist and is not supposed to.
  //
  // What the service needs from the network it gets via the V4.1 handles it
  // already holds anyway: [v41Host] (sending, pair keys) and
  // [v41Delivery] (delivery state, readiness, partners). Both are set by
  // `attachV41`. Whoever introduces a new network field here builds the
  // seam a second time — exactly the duplication that `NodeHost`
  // was supposed to eliminate.

  /// The statistics collector of this service.
  ///
  /// FORMERLY `node.statsCollector` — ONE per node, shared by all
  /// hosted identities. With the node the shared holder is
  /// gone; the collector itself (`lib/core/stats/`) lives on
  /// unchanged. It now sits at the service, i.e. per identity.
  ///
  /// WHAT THIS CHANGES, so that nobody takes it for an oversight: the
  /// MESSAGE counters thereby become more precise (they were always
  /// identity-related and were only booked jointly). The
  /// WIRE BYTES on the other hand are node-wide and no longer have a feeder —
  /// `NodeHost.wireBytesSent/Received` passed them on to `attachV41`,
  /// and `NodeHost` no longer holds a node.
  /// **Gap G-10 — CLOSED on 01.09.2026 (S360).** The sentence above
  /// described the state until then and remains as a correction.
  /// It is now wired via [v41NodeCounters], which `attachV41`
  /// sets; reading happens on looking, not booked via callback
  /// (justification at `NetworkStatsCollector.noteNodeCounters`).
  final NetworkStatsCollector statsCollector = NetworkStatsCollector();

  /// The counters of the V4.1 NODE, on demand (§25.5).
  ///
  /// Set by `attachV41` — the only place where node and service
  /// are present at the same time. `null` as long as no node hangs; then
  /// the four numbers stay at their last state instead of jumping to 0.
  ///
  /// ONE READ POINT, NO FIELD SET. Four `int` fields would be frozen after the
  /// first look — exactly the error that the comment at
  /// `V41Node.wireBytesSent` describes: a display that looks like
  /// a measurement and is none.
  ({int wireSent, int wireReceived, int relayBytes, int relayCells})
      Function()? v41NodeCounters;

  /// What is to be done at the V4.1 NODE on a network change (§22.6).
  ///
  /// Set by `attachV41`, for the same reason as [v41NodeCounters]:
  /// the node belongs to the process, this service to an identity, and
  /// `attachV41` is the only place where both are present. The body
  /// stands there because it needs the address determiner with which the node
  /// was started — the delivery layer knows no network interfaces
  /// and is not supposed to know any.
  ///
  /// `null` if no node hangs (`CLEONA_V41=0`). Then on a
  /// network change the same happens as before: nothing.
  Future<void> Function()? v41OnNetworkChanged;

  /// The app has returned to the foreground — edge for the
  /// catch-up harvest of the V4.1 delivery layer (variant C, S362).
  ///
  /// SEPARATE from [v41OnNetworkChanged], because the two edges
  /// do different things: the network change throws sessions away and
  /// re-announces (that would be wrong here — the network is the same), the
  /// foreground return only catches up. Common to them is only the
  /// trigger type.
  void Function()? v41OnForeground;

  /// Enters the OWN line (§14.7, `own_line.dart`) into the
  /// pair registry of the node — the twin reconciliation.
  ///
  /// Set by `attachV41`, for the same reason as
  /// [v41NodeCounters]: the registry belongs to the NODE, the
  /// user KEM secrets to the IDENTITY, and `attachV41` is the
  /// only place where both are present.
  ///
  /// WHY NOT VIA `V41Delivery.rememberPeer`: the own line
  /// needs an INCOMING DIRECTION that equals the outgoing direction
  /// (justification in the header of `own_line.dart`), and the interface
  /// only knows the outgoing direction. Extending it for this would have broken nine
  /// mocks in `test/`, without any of them handling the own
  /// line.
  ///
  /// CALLED FROM [primeV41Pairs], not only on attaching: `K_own`
  /// falls out of the user KEM secrets, and they rotate on
  /// locking out a device (§14.4). After a rotation the line must
  /// be re-entered under the NEW key — otherwise the
  /// remaining twins continue to harvest under the old tag, i.e. where
  /// nobody stores any more. The call is idempotent and cheap.
  void Function()? v41ArmOwnLine;

  /// How deep the control queue of the cover stream currently is (§5.1).
  ///
  /// Set by `attachV41`, for the same reason as [v41NodeCounters]:
  /// the queue belongs to the NODE, the outbox to the IDENTITY, and
  /// `attachV41` is the only place where both are present.
  ///
  /// THE DRAIN OF THE OUTBOX DEPENDS ON IT, and not cosmetically. A
  /// secure resubmission enqueues `m x R` = 60 frames at once
  /// (§9.2), the queue holds `kMaxControlBacklog` = 120, and on
  /// overflow `CoverStream` discards the OLDEST whole group. A
  /// drain that enqueues three messages at once would thus put 180
  /// frames into a queue of 120 and possibly wipe out a
  /// message that was just regularly in transit — it would create
  /// a defect instead of fixing one.
  ///
  /// `null` means "no node": then nothing drains, because without a node
  /// nothing goes out anyway.
  int Function()? v41PendingControl;

  /// The cap of the control queue, likewise from the node
  /// (`kMaxControlBacklog`). As a function and not as a constant, because
  /// `core/service/` would otherwise have to import the constant from `core/sync/`
  /// — the same layering rule that `cover_stream.dart` draws for
  /// itself ("pulling the constants from there in here
  /// would reverse the layering").
  int Function()? v41ControlBacklogLimit;

  /// The snapshots of the V4.1 node, on demand (§25.4).
  ///
  /// HERE STOOD UNTIL S361 "gap G-2" — a wrong number. G-2 is the
  /// distribution of the system channels; the metrics of the display are
  /// G-10, and G-10 has been closed since S360 (see [statsCollector]).
  ///
  /// SEPARATE FROM [v41NodeCounters], because the two sets are
  /// READ differently: there it is booked (difference, two periods), here
  /// it is passed through. A difference on "waiting for pieces" or
  /// "control queue" would be no quantity — the state falls
  /// again too.
  ///
  /// Set by `attachV41`. `null` as long as no node hangs; then
  /// the last state stays in the collector instead of jumping to 0 —
  /// a jump to 0 would look like "the cover stream has stopped", but would only be
  /// "nobody is looking right now".
  V41NodeGauges Function()? v41NodeGauges;

  /// The entry store of the node as start peer candidates (§11) — the
  /// SEND side of the entry bridge, gap G-11.
  ///
  /// Set by `attachV41`, for the same reason as [v41NodeCounters]:
  /// the STORE belongs to the node (`V41Node.entries`, one instance per
  /// process), the ContactSeed to an IDENTITY, and `attachV41` is the
  /// only place where both are present.
  ///
  /// WHY A CALLBACK AND NO IMPORT EDGE. `core/contact/` lies
  /// below the delivery layer and is also used by the IPC client, which
  /// has no node at all. If `contact_seed.dart` pulled in
  /// `core/tagline/entry_record.dart`, that would reverse the
  /// layering — the same boundary that `smoke_link_io_milestone`
  /// (section 5) guards. The store therefore travels in as a flat record
  /// ([EntrySeedCandidate]) via [ContactSeedDataSource].
  ///
  /// THE SELECTION LIES AT THE SOURCE, not with the builder: which address
  /// is dialable from outside is known by `isExternallyReachable`
  /// (`core/tagline/local_addresses.dart`), and there also stands the
  /// justification why `IpAddressClass.isPrivate` is not enough for that.
  ///
  /// `null` as long as no node hangs — then the ContactSeed carries no
  /// `s=`, and that is the right answer: invented start peers
  /// would wander into foreign codes and send third parties into the void.
  List<EntrySeedCandidate> Function()? v41EntrySeedCandidates;

  /// §19.6.5: does this node hold binary data worth announcing?
  ///
  /// FORMERLY `node.binaryHasContentToShare` — node-wide, because the
  /// fragment store is. But it lies in the PROFILE DIRECTORY and thus
  /// per identity; the flag was already in the wrong place before. Now
  /// it stands where the store stands.
  bool binaryHasContentToShare = false;

  /// True from [stop] — this service is cleared away (e.g. because the identity
  /// was removed via `removeIdentity`).
  ///
  /// SINCE THE CUT IT HAS NO READER ANY MORE, and that is not an oversight: the
  /// chain closures it was built for all hung on the shared
  /// `CleonaNode` (`onFirstCrStoreAck`, `onDiscoveryComplete`,
  /// `ackTracker.onAckReceived`, the four delivery callbacks) and fell with
  /// it. It remains because the pattern comes back as soon as
  /// the V4.1 delivery layer in turn needs cross-identity
  /// callbacks — and because a guard added later without a
  /// set flag would be silently wrong.
  ///
  /// The callbacks this service registers on the shared [node] are
  /// chain closures (`final prev = node.onXxx; node.onXxx = (...) { prev?.call(...); ... }`).
  /// They cannot be unhooked individually without tearing the chain of the still
  /// living services, and therefore keep this instance
  /// alive. Each of these closures therefore still calls `prev?.call(...)` —
  /// the chain stays intact — and then aborts at `_disposed`, so that
  /// a removed identity no longer triggers work (pushes, retries,
  /// `_saveContacts()` into its profile directory).
  ///
  /// SINCE THE CUT IT HAS NO READER ANY MORE, and that is not an oversight: the
  /// chain closures it was built for ALL hung on the shared
  /// `CleonaNode` (`onFirstCrStoreAck`, `onDiscoveryComplete`,
  /// `ackTracker.onAckReceived`, the four delivery callbacks) and fell with
  /// it. It nonetheless remains and continues to be set:
  /// as soon as the V4.1 delivery layer in turn needs cross-identity
  /// callbacks, the pattern comes back — and a guard added later
  /// on a flag that nobody sets any more would be
  /// silently wrong.
  // ignore: unused_field
  bool _disposed = false;

  late MailboxStore mailboxStore;
  late final CallService _calls;
  /// True once [_calls] has been assigned in [startService]. Guards the
  /// buffered call-video accessors below, which must be settable before
  /// startService runs (main.dart's `_wireServiceCallbacks` wires them
  /// ahead of `await service.startService()`).
  bool _callsReady = false;
  CallManager get callManager => _calls.callManager;
  GroupCallManager get groupCallManager => _calls.groupCallManager;
  // §2.2.4: per-identity Auth+Liveness Publisher. One per CleonaService instance
  // (a multi-identity daemon has N services; shared since the CUT of
  // 2026-08-31 is the ONE V4.1 node, no longer a `CleonaNode`).
  // ── `_identityPublisher` IS GONE — AND IT CARRIED TWO THINGS ────────────
  //
  // `lib/core/identity_resolution/` was deleted with the CUT. The
  // publisher had two tasks, and only ONE of them is without replacement:
  //
  //   1. PUBLISHING into the 2D DHT (AuthManifest, LivenessRecord,
  //      DeviceKemRecord). That is §4.3, and the paragraph bridge in
  //      CLAUDE.md expressly says about it "**replaced**, not
  //      renumbered": V4.1 has no pollable third-party knowledge,
  //      liveness is pairwise (§6, §8). Thus (T).
  //
  //   2. HOLDING the device delegations and device signing keys
  //      (`delegations`, `deviceSigKeyCount`, `addLinkedDeviceSigKeys`).
  //      That is §7.1/§7.5 — multi-device, in v4_1 chapter §14 — and has
  //      nothing to do with the DHT. It only fell along because it lay in the same
  //      object. **Gap G-9.**
  //
  // WHY THIS MUST NOT BECOME "SIMPLY AN EMPTY LIST": every read side
  // of `delegations` decides on a SECURITY procedure. An
  // empty list means there "a single device", and thus the
  // §7.5 quorum falls away without anyone noticing — an attacker with the
  // seed could rotate, although exactly that was supposed to be prevented.
  // Each of these places therefore reports the gap individually and takes the
  // branch that does NOT silently claim security.
  @override
  final NotificationSoundService notificationSound = NotificationSoundService();

  /// Conversation the user is currently looking at (set by ChatScreen.initState,
  /// cleared on dispose). Used together with [_isAppResumed] to suppress
  /// in-app notifications for the active chat.
  String? _activeConversationId;
  /// Mirrors AppLifecycleState.resumed (set by main.dart's lifecycle observer).
  /// Defaults to true so the app behaves like „foreground" before the first
  /// lifecycle event arrives.
  bool _isAppResumed = true;

  // `_suppressReceiptForCurrentFrame` (V3.2 §8.1, suppressing the receipt of a silently
  // discarded CONTACT_REQUEST) was dropped with
  // `_handleContactRequestV3`, its only setter.

  /// True when the user has skipped the UpdateRequiredScreen into limited mode
  /// (sec-h5 §8.2 / T13). Per-session only — NOT persisted; every restart
  /// re-shows the splash.
  ///
  /// While active, [handleMessage] drops incoming user-message types and the
  /// public send-methods short-circuit before encrypting/transmitting any user
  /// payload. DHT participation, peer-list-push, presence, ACKs, contact
  /// establishment and call signaling are unaffected.
  bool _reducedMode = false;
  @override
  bool get reducedMode => _reducedMode;
  set reducedMode(bool v) {
    if (_reducedMode == v) return;
    _reducedMode = v;
    _log.warn('reducedMode = $v');
  }
  /// Wall-clock of the most recent fired notification per conversation.
  /// Used for the per-conv 2s debounce that protects against group-chat bursts.
  final Map<String, DateTime> _lastNotifiedAt = {};
  /// Maximum age (ms) of an incoming message that still triggers a notification
  /// during the startup catch-up phase. After catch-up ends, no age-based
  /// suppression applies — Doze-delayed and S&F messages notify normally.
  static const int _notificationStaleThresholdMs = 60000;
  /// Minimum spacing (ms) between two notifications for the same conversation.
  static const int _notificationDebounceMs = 2000;
  /// True during the first 30s after init — startup backlog is age-filtered.
  /// After catch-up, stale suppression is disabled (Doze/S&F messages pass).
  bool _inStartupCatchUp = true;

  /// Extracted moderation sub-service (§9.3 jury, §9.4 reports, channel index gossip).
  late final ChannelModerationService _moderation;
  @override
  ModerationConfig get moderationConfig => _moderation.moderationConfig;
  set moderationConfig(ModerationConfig value) {
    _moderation.moderationConfig = value;
  }

  /// Voice transcription service (whisper.cpp).
  VoiceTranscriptionService? _voiceTranscription;

  /// Public accessor for transcription service (used by settings UI).
  VoiceTranscriptionService? get voiceTranscriptionService => _voiceTranscription;

  /// Media auto-archive manager.
  ArchiveManager? _archiveManager;

  /// Public accessor for archive manager (used by settings UI + IPC).
  ArchiveManager? get archiveManager => _archiveManager;

  /// Guards only: sets the archive manager from outside.
  ///
  /// THERE IS EXACTLY ONE CASE THAT NEEDS IT, and it is not a
  /// convenience. The only producer in operation is [_initArchive],
  /// and that only runs from within [startService]; it builds its
  /// transport hard via `ArchiveTransport.forProtocol(...)`, i.e. a
  /// real `smbclient`/`sftp`/`curl`. A suite that measures the path of
  /// retrieval via IPC (§21.6: from the share, never over the
  /// network) would thus need a real NAS — and would then measure the NAS.
  ///
  /// The way out without this path would be to call the retrieval
  /// directly on the manager, bypassing the dispatcher. That is exactly the
  /// stand-in that S391 measured at the six commands of the invitation card:
  /// the case was implemented, never routed, and the
  /// guard green (`scripts/check_ipc_dispatch_reachable.dart`).
  ///
  /// In operation there is no caller.
  @visibleForTesting
  set archiveManagerForTesting(ArchiveManager? m) => _archiveManager = m;

  /// Inject platform-specific audio decoder (Android: MediaCodec).
  void setPlatformAudioDecoder(AudioDecoderCallback decoder) {
    _voiceTranscription?.platformAudioDecoder = decoder;
    _platformAudioDecoder = decoder;
  }
  AudioDecoderCallback? _platformAudioDecoder;

  // State
  @override
  final Map<String, Conversation> conversations = {};

  /// Receive-side dedup for V3 ApplicationFrame: bounded LRU keyed on
  /// inner.messageId-hex. Catches the same logical message arriving via
  /// multiple paths (Direct + Reed-Solomon reassembly + S&F mutual peer)
  /// and prevents double-dispatch / double-DELIVERY_RECEIPT-emit.
  /// Insertion order is preserved by `LinkedHashSet`; eviction is FIFO
  /// when the cap is reached.
  static const int _processedMessageIdsCap = 4096;
  final LinkedHashSet<String> _processedMessageIds = LinkedHashSet<String>();

  /// Finding 1 (§8.1): inner.messageId-hex of frames whose DELIVERY_RECEIPT was
  /// deliberately suppressed (silent CR drop, F12-A deadlock fix).
  /// `_suppressReceiptForCurrentFrame` is frame-local and therefore invisible
  /// to the dedup branch above, which runs BEFORE dispatch and re-acks
  /// unconditionally. An AckTracker L1 retry replays the SAME inner messageId
  /// (`refreshTimestampAndSign` renews only timestamp + outer sigs), so the
  /// retry would hit dedup and emit exactly the receipt the drop suppressed —
  /// the sender sets `lastAckedAt`, its CR retry loop skips 24h, and the
  /// deadlock is back. Same FIFO cap semantics as `_processedMessageIds`.
  static const int _suppressedReceiptMsgIdsCap = 1024;
  final LinkedHashSet<String> _suppressedReceiptMsgIds = LinkedHashSet<String>();

  // Callbacks for GUI
  @override
  void Function()? onStateChanged;

  /// E-9: a DIFFERENT own device has deleted this identity.
  ///
  /// The service has already cleared its own stores at this point
  /// (`_wipeLocalIdentityData`). What is still outstanding here lies
  /// one layer higher and does not belong to the service: the entry in
  /// `identities.json` and the profile directory itself
  /// (`IdentityManager.deleteIdentity`). The host — `service_daemon.dart`
  /// or the in-process path in `main.dart` — hooks in here.
  ///
  /// NOT declared in `service_interface.dart`: the interface
  /// belongs to a different package of this session; the wiring proposal
  /// for host and interface stands in the session report.
  void Function(String nodeIdHex)? onIdentityDeletedRemotely;
  @override
  void Function(String conversationId, UiMessage message)? onNewMessage;
  @override
  void Function(String nodeIdHex, String displayName)? onContactRequestReceived;
  @override
  void Function(String nodeIdHex)? onContactAccepted;
  @override
  void Function(CallInfo call)? onIncomingCall;
  @override
  void Function(CallInfo call)? onCallAccepted;
  @override
  void Function(CallInfo call, String reason)? onCallRejected;
  @override
  void Function(CallInfo call)? onCallEnded;

  /// IPC push: immediate read-receipt notification (bypasses state_changed debounce).
  void Function(String conversationId, String messageId)? onReadReceiptReceived;

  /// Android: post a system notification for incoming messages (set by Flutter app).
  Future<void> Function(String title, String body, String conversationId)? onPostNotificationAndroid;

  /// Android: cancel notification when conversation is read (set by Flutter app).
  void Function(String conversationId)? onCancelNotificationAndroid;

  /// Badge count changed — update launcher badge / tray icon (set by Flutter app or daemon).
  void Function(int totalUnread)? onBadgeCountChanged;

  /// Android: post/cancel incoming call notification with fullScreenIntent.
  void Function(String callerName, String callId)? onPostCallNotificationAndroid;
  void Function()? onCancelCallNotificationAndroid;
  void Function(bool speaker)? onSetCallAudioModeAndroid;
  void Function()? onResetCallAudioModeAndroid;
  void Function(String reason)? onVideoUnavailable;

  /// §10.4 "Session behaviour" (V1.10, S367) — see CallService's own field
  /// docs for the full contract. Forwarded to `_calls` once constructed
  /// (below); `main.dart` may set these before or after that happens, the
  /// forwarding closures read the field at call time either way.
  Future<bool> Function()? onRequestAudioFocus;
  Future<void> Function()? onAbandonAudioFocus;
  void Function(bool enabled)? onSetProximityMonitoring;
  void Function(bool interrupted)? onCallInterruptionChanged;

  // Contact storage
  final Map<String, ContactInfo> _contacts = {};
  // Persistent deletion flag: prevents re-import of deleted contacts
  final Set<String> _deletedContacts = {};

  // Calendar (§23) — protocol layer delegated to CalendarProtocolService
  late final CalendarProtocolService _calendarProto;
  @override
  CalendarManager get calendarManager => _calendarProto.calendarManager;
  late CalendarSyncService calendarSyncService;

  void Function(String senderNodeIdHex, String eventId, String title)? onCalendarInviteReceived;
  void Function(String eventId, String responderNodeIdHex, RsvpStatus status)? onCalendarRsvpReceived;
  void Function(String eventId)? onCalendarEventUpdated;
  void Function(String eventId, String title, int minutesBefore)? onCalendarReminderDue;

  // Polls (§24) — delegated to PollService
  late final PollService _polls;

  // §4.11 External Rendezvous — REMOVED (S362, owner decision
  // 02.09.2026: "V3 compatibility is no longer necessary").
  //
  // Here stood `RendezvousManager? _rendezvousManager` — a field that was
  // DECLARED and DISPOSED in the whole tree, but never assigned.
  //
  // S388: the first contact rendezvous (v3 §4.11.10, `_fcRendezvous`)
  // is removed too. V4.2 §11.9 lets the public relay network carry EXACTLY ONE
  // thing: the address entries of the fourth neighbour source
  // (`mycelium/lib/host_outside.dart`). First contact goes via the card
  // (§15.2). Measured before removal: the IPC command
  // `rendezvous_uri_shared` had no handler in the server,
  // `notifyContactSeedUriShared` no caller in `lib/ui`, and the
  // scanner session hung solely on the V3 ContactSeed reader.

  // §19.6 Censorship-Resistant Distribution: in-network binary updates.
  // Node-wide singletons — only the first identity's service on a daemon
  // wires these onto the shared node (same first-wins pattern as
  // node.rendezvousManager above).
  BinaryFragmentStore? _binaryFragmentStore;
  BinaryUpdateManager? _binaryUpdateManager;
  BinaryHttpServer? _binaryHttpServer;
  BinaryRendezvousManager? _binaryRendezvousManager;
  DeltaUpdateManager? _deltaUpdateManager;
  InviteLinkService? _inviteLinkService;
  ForeignBinaryAcquirer? _foreignBinaryAcquirer;
  PhysicalTransferHelper? _physicalTransferHelper;
  BinarySeeder? _binarySeeder;
  // §5.5 — the cover fill. Source and acceptance point of the fountain blocks
  // that are put into cover slots that are due anyway. Wired in
  // `attachV41` to `DeliveryNode.coverFill`/`onCoverFillBlock`; registration
  // happens from the signed manifest (`reportUpdateObjectsTo`).
  UpdateCoverFill? _updateCoverFill;
  // §19.6.2 — periodic housekeeping on the fragment store (prunes
  // superseded versions + enforces the platform storage budget).
  Timer? _binaryGcTimer;
  Timer? _registryRepublishTimer;
  // Fetches fragments/binaries from other nodes' embedded HTTP servers
  // (§19.6.6) — the `fetchFragment` callback for BinaryUpdateManager /
  // DeltaUpdateManager downloads.
  BinaryFetchClient? _binaryFetchClient;
  // §26.6.4 — the entry points of the V4.1 node as binary sources.
  //
  // Set in `attachV41` (`tagline/v41_attach.dart`), because only there
  // node and service are present at the same time; `null` as long as V4.1 does not
  // hang. Carries the second source class of the update download next to
  // the Nostr rendezvous — justification and measurement at
  // `entryBinarySources`.
  List<EndpointAddress> Function()? binarySourcesOutEntry;
  InviteLinkService? get inviteLinkService => _inviteLinkService;
  PhysicalTransferHelper? get physicalTransferHelper => _physicalTransferHelper;
  @override
  PollManager get pollManager => _polls.pollManager;
  @override
  void Function(String pollId, String groupId, String question)? onPollCreated;
  @override
  void Function(String pollId)? onPollTallyUpdated;
  @override
  void Function(String pollId)? onPollStateChanged;

  // §26.6.2 package C
  @override
  void Function(String contactNodeIdHex, int pendingCount)?
      onKeyRotationPendingExpired;

  // SR-1 (§7.4b step 6 / §8.3)
  @override
  void Function(
          String contactNodeIdHex, String displayName, bool wasVerified)?
      onContactIdentityRotated;

  // §7.5 Co-Auth warning callbacks
  @override
  void Function(String contactNodeIdHex, String displayName,
      int tokensPresent, int tokensRequired)? onRotationCoAuthWarning;
  @override
  void Function(String contactNodeIdHex, String displayName)?
      onRotationRejectionAlert;

  /// §7.5: fires on a Linked Device when the Primary asks for a rotation
  /// countersignature. The UI MUST ask the user and then call
  /// [approveRotation] or [rejectRotation] with the same `rotationHashHex`.
  /// If nobody answers, the daemon sends NOTHING — silence is not consent
  /// (see [_handleRotationApprovalRequest]). The `kind` argument says which
  /// of the two occasions is being asked about and must drive the dialog
  /// text — see [RotationApprovalKind].
  @override
  void Function(String rotationHashHex, String requestingDeviceIdHex,
          RotationApprovalKind kind, List<String> newDeviceNodeIdHexes)?
      onRotationApprovalRequest;

  // H-2 (§6.3.5)
  @override
  void Function(
          String contactNodeIdHex, String displayName, bool identityKeyChanged)?
      onContactRestoreDetected;

  /// §26: fires whenever the twin-device list changes (add/remove/rename).
  /// GUI listens via IPC to refresh the Device Management screen.
  void Function()? onDevicesUpdated;

  /// §7.1 LD-2: fires when a new Linked-Device pairing request arrives.
  /// The GUI shows a confirmation dialog; on approval, call approvePairRequest().
  @override
  void Function(String requestingDeviceIdHex)? onDevicePairRequest;

  // Multi-Device (§26): twin device list + deduplication
  final Map<String, DeviceRecord> _devices = {};
  bool _devicesLoaded = false;
  late final String _localDeviceId; // UUID, generated once on first launch
  /// Rolling dedup window for TWIN_SYNC syncIds. Maps syncIdHex → firstSeen
  /// epoch-ms. Entries older than 7 days are garbage-collected on every save.
  final Map<String, int> _processedSyncIds = {};
  /// 7-day TTL for TWIN_SYNC dedup entries (matches S&F TTL per architecture).
  static const int _syncDedupTtlMs = 7 * 24 * 60 * 60 * 1000;
  // Key Rotation ACK tracking (§26.6.2, package C): per-contact retry state,
  // persisted, re-sends broadcast on 24h-tick until ACK or expiry.
  //
  // ── LAZY, NOT ASSIGNED IN `startService()` (S360) ─────────────────
  //
  // Here stood a bare `late final … ;` with the assignment in
  // `startService()`. Measured on 2026-09-01, as soon as `rotateIdentityKeys()`
  // got to step 5 at all:
  //
  //     LateInitializationError: Field '_keyRotationRetry@…' has not been
  //     initialized.
  //
  // The path there needs no `startService()`: the UI calls
  // `revokeDevice()` via IPC, that calls `rotateIdentityKeys()` UNAWAITED,
  // and the throw thus lands in the zone handler — after sending the
  // broadcast and after `rotateIdentityFull()`, i.e. AFTER the keys
  // had already been replaced. Lost would have been the resubmission
  // bookkeeping (step 5) AND the device set announcement (step 6).
  // In production `startService()` today always runs before — that makes
  // the defect latent, not harmless.
  //
  // The manager depends on nothing that `startService()` only establishes:
  // `profileDir` is a constructor parameter, `identity` a field, `_fileEnc`
  // a getter. A lazy initializer is therefore not a makeshift,
  // but the right lifetime — it arises on first access,
  // no matter which path gets there first, and `load()` belongs in the same
  // line, because a manager without loaded state would silently
  // lose every resubmission.
  late final KeyRotationRetryManager _keyRotationRetry = (() {
    final m = KeyRotationRetryManager(
      profileDir: profileDir,
      identityId: identity.userIdHex,
      store: store,
    );
    m.load();
    return m;
  })();
  // Guard: tracks whether each data type was successfully loaded from disk.
  // Prevents _save*() from overwriting existing data with empty maps
  // if _load*() failed (e.g. decryption error, missing key).
  bool _contactsLoaded = false;
  bool _conversationsLoaded = false;
  bool _groupsLoaded = false;
  bool _channelsLoaded = false;
  // Rate limiter: last CR retry time per contact (nodeIdHex -> timestamp)
  //
  // DEAD CODE, RE-MEASURED (S361) — both maps here get a `[key] = …` assignment
  // at NO place in `lib/` any more, since the CUT
  // (2026-08-31) removed `cleona_service_v3_retry.dart` and with it the
  // `onPeerAdded` callback that triggered `_retryPendingContactRequests`
  // (`cleona_service_identity.dart:_initIdentityPublisher`,
  // detailed derivation there and in
  // `docs/v4-redesign/S361-lueckenbuch.md`, line "CR-Wiedervorlage").
  // NOT REMOVED, because the resubmission of unanswered
  // contact requests (§5.1) is a real, promised property that only
  // does not yet have its V4.1 trigger — removing would be wrong here,
  // because the code has a purpose that it just does not reach (yet).
  final Map<String, DateTime> _lastCrRetryPerContact = {};
  // Exponential backoff counter for CR retries to unreachable contacts.
  // Backoff: 10s, 20s, 40s, 80s, 160s, 320s, then capped at 600s (10min).
  // Keeps retrying forever so eventually-online contacts still get through,
  // but at low frequency after the initial burst (~10 attempts in 20min).
  //
  // Likewise without a writer (see above) — the backoff CURVE
  // (`crRetryBackoffSeconds`) nonetheless remains as a contract and is
  // guarded by `smoke_cr_backoff_edge.dart`, so that it can be reused unchanged
  // when the trigger is retrofitted.
  final Map<String, int> _crRetryCountPerContact = {};
  // §5.1 CR edge: last edge-triggered backoff shortening per contact
  // (nodeIdHex -> timestamp). Own throttling, because `peer-came-online` fires per
  // newly confirmed peer — without a gate a node that confirms
  // thirty peers at start would trigger thirty CR sends (working rule 5).
  final Map<String, DateTime> _crEdgeShortenAt = {};
  // §8.1.1 rev3 step 1b: pending DEVICE_KEM_OFFER completers.
  // Contacts for which the sender-side stale warning has already been written
  // into the conversation. Prevents duplicate warnings; cleared on the next
  // ACK (contact is alive) or re-acceptance.
  final Set<String> _staleWarningWrittenFor = {};
  // §5.5 receiver-side: per-sender PEER_STORE rate limit (max 10/hour).
  final Map<String, List<DateTime>> _peerStoreRateLog = {};
  // GM-2 (§9.1.4): track per-group last epoch for which a RESYNC_REQUEST was sent
  // to avoid flooding the owner. Key = groupIdHex, value = epoch that triggered it.
  final Map<String, int> _resyncRequestedAtEpoch = {};
  Timer? _keyRotationTimer;
  // §26.6.2 package C: drives _keyRotationRetry re-sends every 24h.
  Timer? _keyRotationRetryTimer;
  Timer? _expiryTimer;
  int _processedMsgIdsSaveCounter = 0;
  // ── §27.9 NAT wizard: only the SETTING remains ────────────────────
  //
  // `NatWizardTrigger? _natWizardTrigger` stood here until 01.09.2026
  // (S360). The class was deleted with `lib/core/service/nat_wizard_trigger.dart`,
  // namely for two independent reasons:
  //
  //  1. Its trigger condition was `stats.directConnections == 0 &&
  //     stats.activePeerCount > 0` — two numbers that have been
  //     constantly 0 since the CUT. The condition could NEVER become true; the
  //     wizard has not fired by itself a single time since 31.08.
  //  2. It no longer had any constructor caller in `lib/` at all.
  //     The only producer was its own smoke test — a test that IS the
  //     only use of its subject measures nothing about the
  //     application.
  //
  // The SETTING stays (line below): `dismissNatWizard`,
  // `requestNatWizard` and the two test hooks write it, and the
  // user expects a "never again" to survive a restart. The
  // wizard is thus user-driven — tap on the connection icon —
  // and that is the only path that manages without the dropped numbers.
  // Unix-ms until which the NAT wizard is suppressed. 0 = never dismissed.
  // Persisted in nat_wizard_settings.json alongside the profile.
  int _natWizardDismissedUntilMs = 0;
  // Own profile picture (base64 JPEG, max 64KB)
  String? _profilePictureBase64;
  // Own profile description (max 500 chars)
  String? _profileDescription;
  // Media download settings (auto-download thresholds + download dir)
  MediaSettings _mediaSettings = MediaSettings();
  // Link preview settings + fetcher (sender-side)
  LinkPreviewSettings _linkPreviewSettings = LinkPreviewSettings();
  late LinkPreviewFetcher _linkPreviewFetcher;
  // Multi-interface send mode (Architecture §23.2)
  MultiInterfaceMode _multiInterfaceMode = MultiInterfaceMode.auto;
  // Guardian service (Shamir SSS): FALLEN. `guardian_service.dart` was
  // deleted with the CUT (v4_1 §13.8 — no social recovery; §6.8 is
  // the same place in the OLD v4_0 numbering and stood here wrongly until
  // S361). The four members of the interface remain and report
  // the refusal; see [isGuardianSetUp].
  // Groups
  final Map<String, GroupInfo> _groups = {};
  /// Pending config updates for groups not yet known (arrive before GROUP_INVITE).
  final Map<String, ({ChatConfig config, String senderHex})> _pendingGroupConfigs = {};
  @override
  void Function(String groupIdHex, String groupName)? onGroupInviteReceived;

  // Channels
  final Map<String, ChannelInfo> _channels = {};
  @override
  void Function(String channelIdHex, String channelName)? onChannelInviteReceived;
  @override
  void Function(JuryRequest request)? onJuryRequestReceived;

  // Channel index (public channel discovery)
  late ChannelIndex _channelIndex;

  // System channels (§9.5)
  DateTime serviceStartedAt = DateTime.now();
  CrashReporter? _crashReporter;
  ContactIssueReporter? _contactIssueReporter;
  Timer? _systemChannelEvictionTimer;

  CrashReporter get crashReporter => _crashReporter ??= CrashReporter(this);
  ContactIssueReporter get contactIssueReporter =>
      _contactIssueReporter ??= ContactIssueReporter(this);

  // Guardian restore callback
  @override
  void Function(String ownerName, String triggeringGuardianName, String ownerNodeIdHex, String recoveryMailboxIdHex)? onGuardianRestoreRequest;

  // Update checking (Architecture Section 17.5.5)
  Timer? _updateCheckTimer;
  UpdateManifest? _latestManifest;
  /// Callback when a new version is available. UI should show banner/prompt.
  /// [inNetworkAvailable] is true when the update can additionally be
  /// fetched via §19.6 in-network binary distribution (not just the
  /// external `manifest.downloadUrl`).
  void Function(UpdateManifest manifest, bool inNetworkAvailable)? onUpdateAvailable;

  void Function(BinaryUpdateState state, double progress)? onUpdateStateChanged;

  /// The current app version string, also consumed by `lib/main.dart` for
  /// the Sec H-5 hard-block startup check (T13).
  ///
  /// S368: the source now lies in `app_version.dart` — a leaf without
  /// imports that every layer can include. Here the string formerly stood
  /// literally; it was thus only reachable for everything that imports this
  /// large library, and `call_service.dart` did not.
  /// Exactly there an own number was therefore kept (`3002`), with which
  /// V4.1 introduced itself in the network as 3.2.0.
  static const String kCurrentAppVersion = kAppVersion;

  static Future<String?> Function()? apkPathResolver;

  String get currentAppVersion => kCurrentAppVersion;

  // Recovery state
  @override
  void Function(int phase, int contactsRestored, int messagesRestored)? onRestoreProgress;
  DateTime? _lastRestoreBroadcast;

  /// Receiver-side acceptance limit for RESTORE_BROADCAST (§13.5.4).
  ///
  /// Per sender UserID: the `timestamp` of the most recently HONORED broadcast and
  /// the time at which we honored it.
  ///
  /// WHY THIS LIES HERE AND NOT WITH THE SENDER. §13.5.4 says "at most 1
  /// broadcast per UserID per 5 min is **honored**" — honoring happens at the
  /// receiver. Until S370 the limit was built only in the SENDER
  /// (`sendRestoreBroadcast`, `_lastRestoreBroadcast`), and a limit in the
  /// sender binds exactly the one who observes it anyway. The receiver accepted
  /// every broadcast: no deadline, no counter, no look at
  /// `rb.timestamp` — the value lay in the signed body and was never held against
  /// a clock.
  ///
  /// WHAT THAT COST, measured. A RESTORE_BROADCAST is a
  /// self-carrying, signed packet. In the DOMINANT case — the
  /// deterministic recovery from the same seed phrase — the
  /// newly derived key is identical to the old one
  /// (`sendRestoreBroadcast` says so itself), so `oldNodeId ==
  /// newNodeId`. Thus the re-registration `_contacts.remove(old)` +
  /// `_contacts[new]` does not act as protection: the contact stays under the same
  /// key, the signature keeps verifying against the same
  /// `ed25519Pk` — and every resubmission triggered again the three
  /// response phases, the third of which sends the FULL message history.
  /// Whoever has a copy of the packet could trigger that arbitrarily often;
  /// §13.5.3 estimates a full history at ~30 MB, and the
  /// output is capped at `R_cover = 1/8 s`.
  ///
  /// TWO GATES, and the first is the load-bearing one:
  ///   1. `timestamp` must STRICTLY INCREASE. A resubmission of the same
  ///      packet carries the same value and thus falls out — the
  ///      timestamp lies in the signed body, so it cannot be forged.
  ///   2. Additionally at most one honored broadcast per 5 minutes, exactly
  ///      the number from §13.5.4.
  ///
  /// DELIBERATE LIMIT: the state is process-local. A restart of the daemon
  /// resets it, after which a single resubmission is possible again. That is
  /// noted and not fixed — persistence belongs in the
  /// storage and is a separate decision, not a side effect of this fix.
  final Map<String, ({Int64 stamp, DateTime honoredAt})>
      _restoreBroadcastSeen = {};

  /// How far a `timestamp` may lie in the FUTURE (clock skew).
  static const Duration kRestoreBroadcastFutureSkew = Duration(minutes: 15);

  /// Minimum interval between two honoured broadcasts of the same sender (§13.5.4).
  static const Duration kRestoreBroadcastMinGap = Duration(minutes: 5);
  Timer? _restoreRetryTimer;
  Timer? _restorePollingTimer;

  // `_postDiscoveryPolledPeers` stood here: the set of peers that the
  // catch-up run after the discovery cascade had already queried. The run
  // itself (`_onPostDiscoveryRetrieve`, `_onPeerNewlyConfirmed`) has
  // fallen. `_restorePollCount` next to it counted the aggressive
  // mailbox queries after a recovery — the same fate.
  Timer? _postDiscoverySecondSweep;
  Timer? _delegationRenewalTimer;
  Timer? _crRetryTimer;

  // `_crRateTracker` (§8.1 "5 CRs/hour per sender") was dropped with
  // `_handleContactRequestV3`: V4.2 §15.10 "No rate limit per
  // sender" — the load is limited by proof of work, invitation type and revocation.

  // §5.6 Key-rotation transition: previous primary mailbox ID, polled for 7
  // days after key rotation so messages stored under the old pubkey are found.
  // ── §14.4 transition window (owner decision 01.09.2026) ──────────
  //
  // One record per contact, key is its UserID hex. It keeps the
  // OLD pair line alive until the contact has the new keys —
  // at most [_rotationWindowDays]. Derivation, evidence and the calculated
  // price: `cleona_service_rotation_window.dart`.
  final Map<String, RotationWindow> _rotationWindows = {};
  bool _rotationWindowsLoaded = false;

  /// Owner, 01.09.2026: "But max. 14 days. After that the
  /// loss of contact is acceptable." The same number as
  /// [_lockoutDeadlineDays], but deliberately an OWN constant: the one
  /// caps the lockout transition (when does the lockout count as completed),
  /// the other the old pair line (how long is it still harvested).
  /// Merging them would mean binding two decisions to one number.
  static const _rotationWindowDays = 14;

  /// §14.5 path 2: counter of the own device set announcements, monotonic
  /// and persisted (in `devices.json` under `_deviceSetSeq`, see
  /// [DeviceSetAnnouncementOps._nextDeviceSetSeq]).
  int _deviceSetSeq = 0;

  Uint8List? _previousMailboxPrimary;
  DateTime? _previousMailboxPrimarySetAt;
  /// S366: "the stored state of the mailbox transition is authoritative".
  /// Carries the data-loss latch in `_saveMailboxTransition` — without
  /// it a failed load would be indistinguishable from an expired transition.
  bool _mailboxTransitionLoaded = false;
  static const _mailboxTransitionDays = 7;

  // ── E-7 lockout transition (v4_1 §14.4/§24.4.3) ──────────────────────
  //
  // One record per locked device, key is the device UUID.
  // Complete justification, measurement and deadline situation:
  // `cleona_service_lockout.dart`.
  final Map<String, LockoutTransition> _lockouts = {};
  bool _lockoutsLoaded = false;

  /// §14.4, normative: "at the latest after the delivery window (one
  /// recovery-epoch lifetime, **14 days**)". Not the same number as
  /// [_mailboxTransitionDays] — that applies to the ordinary rotation without
  /// a locked-out device (§5.6).
  static const _lockoutDeadlineDays = 14;

  // ── §5.8 One-Shot-Outbox ─────────────────────────────────────────────
  // Messages that could NOT be placed into L3 (Erasure + S&F) because the
  // sender had 0 connectivity at send time.  Each entry holds the serialized
  // canonical NetworkPacketV3 bytes plus routing metadata so the edge-triggered
  // flush (_flushOutbox) can retry the single L3 placement attempt exactly once.
  //
  // IMPORTANT: This is NOT a retry queue. There is NO timer, NO periodic flush.
  // The flush fires exactly once, edge-triggered by onNetworkChanged (= the
  // first time the sender gets a network interface back after being offline).
  // If the flush itself still finds 0 DHT peers (which is possible in the
  // split-second before Kademlia finds neighbours), the entry stays until the
  // NEXT onNetworkChanged edge — guaranteeing liveness without polling.
  //
  // S368: here stood `_outbox` (Map<String, _OutboxEntry>) and
  // `_outboxLoaded` — the V3 outbox. Fallen, because it had EXACTLY ONE
  // write access and that stood in its own load path: the book
  // filled only from itself and never brought anything out. Its
  // task is carried by the V4.1 outbox (`v41Outbox`, §21.2).

  // §5.1 F3′ (fourth outbox edge): last user-scoped flush attempt per sender.
  // Gates the verified-inbound edge so a chatty sender cannot re-trigger a
  // still-failing flush on every frame. NOT a timer — consulted only when an
  // inbound frame arrives while entries for that sender are parked.
  final Map<String, DateTime> _outboxInboundFlushAt = {};
  static const Duration _outboxInboundFlushGate = Duration(seconds: 60);
  /// §5.1 CR edge: minimum interval between two edge-triggered
  /// backoff shortenings for the same contact. Deliberately the same value as
  /// [_outboxInboundFlushGate] — the same task (a frequently firing edge
  /// must not produce a send stream), hence the same order of magnitude.
  static const Duration _crEdgeShortenGate = Duration(seconds: 60);

  // §5.8 extension: pending membership update resends.
  // When _broadcastGroupUpdate / _broadcastChannelUpdate fails for a member
  // (sendToUser returned false), the (entityId, recipientHex) pair is parked
  // here. On the next onNetworkChanged edge, the CURRENT group/channel state
  // is re-sent to pending recipients only (not all members). Successful
  // re-sends are removed; stale entries (member removed, entity deleted) are
  // cleaned up during flush.
  // Structure: entityIdHex (group or channel) → Set<recipientUserIdHex>
  final Map<String, Set<String>> _pendingMembershipResends = {};
  /// S366: the same task as [_mailboxTransitionLoaded], for the
  /// pending membership resends.
  bool _membershipResendsLoaded = false;

  // §5.5b First-CR ACK gate: after sendToDevice, wait 15s for a
  // DELIVERY_RECEIPT before firing FIRST_CR_STORE to seed peers.
  // Key = messageIdHex of the First-CR ApplicationFrameV3.
  final Map<String, Timer> _firstCrAckGates = {};

  /// [port] is now PASSED instead of derived from `node.port` (CUT,
  /// 31.08.2026). The node that knew the port is gone; whoever builds the service
  /// knows it — in the daemon the V4.1 node, in-process `main.dart`.
  CleonaService({
    required this.identity,
    required this.displayName,
    required this.port,
    this.networkChannel = 'beta',
  })  : profileDir = identity.profileDir,
        _log = CLogger.get('service', profileDir: identity.profileDir);

  /// Start service-level components (contacts, conversations, mailbox).
  /// The node must already be started externally.
  Future<void> startService() async {
    // This instance is alive (again) from now on — cancels a previous
    // [stop], so that the chain closures registered further below do not
    // immediately run into their _disposed guard.
    _disposed = false;
    serviceStartedAt = DateTime.now();
    _log.debug('Starting CleonaService displayName="$displayName"');
    _log.info('Starting CleonaService...');

    // §12.5 S254: startup catch-up phase — age-based notification suppression
    // only applies during the first 30s. After that, Doze-delayed and S&F
    // messages trigger notifications normally.
    _inStartupCatchUp = true;
    Future.delayed(const Duration(seconds: 30), () => _inStartupCatchUp = false);

    // Ensure profile dir exists
    Directory(profileDir).createSync(recursive: true);

    // Init mailbox store
    mailboxStore = MailboxStore(profileDir: profileDir);
    await mailboxStore.load();

    // Init channel index (public channel discovery cache)
    // S366: from the encrypted storage (area `channel_index`)
    // instead of from `channel_index.json.enc`.
    _channelIndex = ChannelIndex(dataDir: profileDir, store: store);
    _channelIndex.load();

    // Init moderation sub-service
    _moderation = ChannelModerationService(this);
    _moderation.onJuryRequestReceived = (req) => onJuryRequestReceived?.call(req);

    // Init call service (call/group-call managers, audio/video engine)
    _calls = CallService(this, notificationSound: notificationSound, log: _log);
    _callsReady = true;
    _calls.onIncomingCall = (info) => onIncomingCall?.call(info);
    _calls.onCallAccepted = (info) => onCallAccepted?.call(info);
    _calls.onCallRejected = (info, reason) => onCallRejected?.call(info, reason);
    _calls.onCallEnded = (info) => onCallEnded?.call(info);
    _calls.onIncomingGroupCall = (info) => onIncomingGroupCall?.call(info);
    _calls.onGroupCallStarted = (info) => onGroupCallStarted?.call(info);
    _calls.onGroupCallEnded = (info) => onGroupCallEnded?.call(info);
    _calls.onStateChanged = () => onStateChanged?.call();
    _calls.onPostCallNotificationAndroid = (name, id) => onPostCallNotificationAndroid?.call(name, id);
    _calls.onCancelCallNotificationAndroid = () => onCancelCallNotificationAndroid?.call();
    _calls.onSetCallAudioModeAndroid = (speaker) => onSetCallAudioModeAndroid?.call(speaker);
    _calls.onResetCallAudioModeAndroid = () => onResetCallAudioModeAndroid?.call();
    _calls.onVideoUnavailable = (reason) => onVideoUnavailable?.call(reason);
    _calls.onRequestAudioFocus = () async => await onRequestAudioFocus?.call() ?? false;
    _calls.onAbandonAudioFocus = () async => await onAbandonAudioFocus?.call();
    _calls.onSetProximityMonitoring = (enabled) => onSetProximityMonitoring?.call(enabled);
    _calls.onCallInterruptionChanged = (interrupted) => onCallInterruptionChanged?.call(interrupted);
    // Forward whatever was buffered on the plain fields below (set by
    // callers that ran before startService, e.g. main.dart's
    // _wireServiceCallbacks) to the now-constructed CallService.
    _calls.onGroupVideoTexture = _bufferedOnGroupVideoTexture;
    _calls.createVideoEngine = _bufferedCreateVideoEngine;
    if (_bufferedCallIntegration != null) {
      _calls.callIntegration = _bufferedCallIntegration!;
    }
    _calls.onVideoFrameReceived = _bufferedOnVideoFrameReceived;
    _calls.onKeyframeRequested = _bufferedOnKeyframeRequested;
    _calls.init();

    // ── §5.5b FIRST_CR_STORE_ACK: FALLEN (CUT, 31.08.2026) ──────────
    //
    // Here the service hooked onto `node.onFirstCrStoreAck` and set
    // a contact to `storedForDelivery` as soon as a PROTECTED SEED had stored the
    // first request. Both are V3 store-and-forward:
    // the callback belonged to `CleonaNode`, and the counter-check
    // (`routingTable.getPeer(...).isProtectedSeed`) does not exist without
    // a routing table. §5.5b as a whole is gone with the V3 line —
    // V4.1 does not store first requests with seeds, but with the
    // responsible relays of the tag line (§9.1).
    //
    // Consequence for the UI: the intermediate state `storedForDelivery`
    // is no longer reached. A pending request stays
    // `pending_outgoing` until it is answered.
    //
    // HERE UNTIL S361 IT SAID "this is the visible part of G-1
    // (first contact)". That has not been accurate since S360: G-1 is
    // closed, the request DOES go out (§15.3.2). What is missing here
    // is not a carrier, but an INTERMEDIATE STATE in the display — the
    // V4.1 equivalent would be `placed` from §22.5.1 (>= 2 receipts
    // of independent relays), and that is not kept for contact requests.
    // The user therefore sees "requested" until the response
    // instead of "stored". Not a delivery error, a missing intermediate step.

    // ── GUARDIAN SERVICE: FALLEN (CUT, 31.08.2026) ───────────────────
    //
    // `_initGuardianService()` stood here. `GuardianService` was passed the
    // `CleonaNode` and sent Shamir shares as
    // `FRAGMENT_STORE` infrastructure frames. v4_1 §13.8 records that there is
    // no social recovery any more; the file itself lies outside
    // this package. The four public guardian members now report the
    // gap individually (see [isGuardianSetUp]).

    // Load contacts
    _loadContacts();

    // Init local device (§26 Multi-Device)
    _initLocalDevice();

    // §7.1: Restore linked-device delegation keys (if this is a Linked Device)
    //
    // [storeOrNull] and not [store]: the two cases are different,
    // and only one of them is an error. WITHOUT A STORE there never was a
    // pairing — a linked device arises exclusively via
    // `_handleDevicePairApproveV3`, and that writes INTO the store; an
    // identity without a seed-derived key thus cannot have any at all.
    // A STORE WITHOUT A READABLE RECORD on the other hand very much is
    // one, and that is caught by the latch in `LinkedDeviceKeysStore.load`.
    final ldDeposit = storeOrNull;
    final restoredLinkedKeys = ldDeposit == null
        ? null
        : LinkedDeviceKeysStore.load(
            profileDir: profileDir,
            store: ldDeposit,
          );
    if (restoredLinkedKeys != null) {
      applyLinkedDeviceKeys(restoredLinkedKeys);
      _log.info('Restored linked-device keys from disk');
    }

    // S362: one-time sweeper BEFORE any reading of the affected files.
    // It must run before `_loadProfilePicture`, because that from now on only
    // knows the ciphertext — without the run before it an existing
    // profile would have lost its picture, its description and its transcripts
    // (they would continue to lie in plaintext on the disk, only unused).
    _sweepPlaintextUserContent();

    // S362 variant B: the attachments. First register the key, then
    // the sweeper — in this order, otherwise it would find no
    // key and (rightly) leave everything lying.
    //
    // `_fileEnc.effectiveKey` and NOT an own derivation: the
    // attachments must lie under the same base key as the
    // messages they hang on. The separation of the uses
    // is done by `MediaCipher` via HKDF one level deeper.
    MediaStore.instance.register(profileDir, _fileEnc.effectiveKey);
    _sweepPlaintextMedia();

    // The decrypting reader on `127.0.0.1`. It is needed in THIS process,
    // because the transcription feeds `ffmpeg` or the Android decoder
    // with a source (`voice_transcription_service.dart:354`,
    // `:376`), and in the UI process for display and playback
    // (started there in `main.dart`). Loopback only, an ephemeral
    // port, one path secret per process start — justification and
    // threat model stand in `MediaVault`.
    unawaited(MediaVault.instance
        .start(profileDir: profileDir)
        .catchError((Object e) {
      _log.warn('Media reader could not be started: $e — attachments are '
          'not playable in this run (but they stay stored '
          'readably).');
    }));

    // Load own profile picture
    _loadProfilePicture();

    // Load own profile description
    _loadProfileDescription();

    // Load groups
    _loadGroups();

    // Load channels
    _loadChannels();

    // NOTE: _seedSystemChannels() is intentionally NOT called here. It seeds
    // entries into `conversations`, which is not loaded until _loadConversations()
    // further down. Seeding before the load made _seedSystemChannels' own
    // _saveConversations() write a conversations.json containing ONLY the two
    // system channels — overwriting all real chats before they were ever read
    // back (catastrophic data loss on every restart). It now runs right after
    // _loadConversations(), mirroring _loadGroups/_loadChannels above.

    // Load moderation state
    _moderation.loadModeration();

    // Load calendar (§23)
    final calMgr = CalendarManager(
      profileDir: profileDir,
      identityId: identity.userIdHex,
      store: store,
    );
    calMgr.load();
    _calendarProto = CalendarProtocolService(this, calMgr);
    _calendarProto.onCalendarInviteReceived = (s, e, t) => onCalendarInviteReceived?.call(s, e, t);
    _calendarProto.onCalendarRsvpReceived = (e, s, st) => onCalendarRsvpReceived?.call(e, s, st);
    _calendarProto.onCalendarEventUpdated = (e) => onCalendarEventUpdated?.call(e);
    _calendarProto.init();

    // Load external calendar sync (§23.8 — CalDAV + Google)
    calendarSyncService = CalendarSyncService(
      profileDir: profileDir,
      identityId: identity.userIdHex,
      calendar: calMgr,
      store: store,
    );
    calendarSyncService.load();

    // Polls (§24)
    _polls = PollService(this);
    _polls.onPollCreated = (id, gid, q) => onPollCreated?.call(id, gid, q);
    _polls.onPollTallyUpdated = (id) => onPollTallyUpdated?.call(id);
    _polls.onPollStateChanged = (id) => onPollStateChanged?.call(id);
    _polls.init();

    // Key rotation retry manager (§26.6.2 package C): persisted per-contact
    // retry state so offline contacts still receive KEY_ROTATION_BROADCAST
    // after S&F TTL expiry.
    //
    // The access SUFFICES — the initializer at the field builds and loads it
    // (justified there). The former assignment at this place was the
    // reason why every path without `startService()` ran into a
    // LateInitializationError.
    _keyRotationRetry.pendingCount;

    // Birthday auto-sync (§23.4): derive yearly birthday events from
    // contacts that carry birthday metadata. Runs once at startup and is
    // refreshed from acceptContactRequest / setContactBirthday.
    _syncCalendarBirthdays();

    // Load media settings
    _loadMediaSettings();

    // Load link preview settings
    _loadLinkPreviewSettings();
    _linkPreviewFetcher = LinkPreviewFetcher(
      settings: _linkPreviewSettings,
      log: (msg) => _log.debug(msg),
    );

    // Load multi-interface settings and apply to transport (§23.2)
    _loadMultiInterfaceMode();
    // The setting is READ (the UI shows it), but no longer
    // applied: `node.transport.setMultiInterfaceMode` belonged to the
    // V3 transport. Gap G-6 — see [setMultiInterfaceMode].

    // `_syncTierRegistration()` stood here: it entered contact and
    // channel device identifiers into the tier registry of the DV routing table.
    // Without distance-vector routing it has no subject (T).

    // ── RENDEZVOUS: BOTH FALLEN ────────────────────────────────────
    //
    // Here `_initRendezvous()` built two managers. The general
    // `RendezvousManager` (§4.11) fell in S362, the first contact rendezvous
    // (§4.11.10) in S388 — justification at the field block above (V4.2 §11.9: the
    // relay network only carries the fourth neighbour source any more, and that lies in
    // mycelium).

    await _initInNetworkUpdate();

    // Identity registry DHT republish (P4-Publish): keep fragments alive
    // across DHT TTL (7d). Republish every 24h — low traffic, idempotent.
    _registryRepublishTimer = Timer.periodic(const Duration(hours: 24), (_) {
      _publishIdentityRegistryIfPossible();
    });

    // Load conversations
    _loadConversations();
    _recoverStuckMedia();
    _loadPendingMediaSends();

    // Seed system channels (§9.5) — MUST run after _loadConversations() so the
    // real chats are already in `conversations`; seeding then only adds the two
    // system-channel entries if missing and the subsequent save persists the
    // FULL set. (Running this before the load destroyed all chats — see note
    // next to _loadChannels above.)
    _seedSystemChannels();
    // §9.5.7 (S119 D1): load the gossip record set for the system channels.
    _loadSysChanRecords();

    // After load: surface the persisted unreadCount to the system badge so
    // the Launcher-Badge matches the on-disk truth right after daemon-start.
    _updateBadgeCount();

    // Load persisted message-ID dedup set (H12 replay-window fix).
    _loadProcessedMessageIds();

    // §21.2: and the V4.1 outbox next to it. It is the only one that
    // really brings something out; the drain hangs on the
    // readiness edge (`flushV41Outbox`), NOT on this start.
    // At start `readiness = searching` and `placeSecure` would return 0
    // — a drain here would only use up attempts.
    loadV41Outbox();
    _loadMailboxTransition();
    _loadPendingMembershipResends();

    // V3.1.44: Migrate self-entries from deviceNodeId to userIdHex in groups/channels/messages.
    // §26 Phase 2 temporarily stored deviceNodeId as member keys, but service-level
    // identification must use the stable userId (same across all devices).

    // Clean up stale group/channel conversations
    final staleConvs = conversations.keys
        .where((id) {
          final c = conversations[id]!;
          if (c.isGroup && !_groups.containsKey(id)) return true;
          if (c.isChannel && !_channels.containsKey(id)) return true;
          return false;
        })
        .toList();
    for (final id in staleConvs) {
      conversations.remove(id);
      _log.info('Removed stale conversation: $id');
    }
    if (staleConvs.isNotEmpty) _saveConversations();

    // ── #U1 EDGE-TRIGGERED CATCH-UP: FALLEN (CUT) ──────────────
    //
    // `node.onDiscoveryComplete` -> `_onPostDiscoveryRetrieve()` caught up after
    // the Kademlia bootstrap cascade on S&F messages, erasure fragments and
    // pending first requests. All three subjects are gone with the
    // V3 line; the harvest in V4.1 has its own tick and its
    // own edge (`lib/core/tagline/` — readiness, partner choice,
    // sampling), which does not hang on the service (T).

    // §26: TWIN_ANNOUNCE at startup so existing twins learn about this device.
    // 6 seconds lets the first peers come up first. Fire-and-forget; a no-op
    // when we have no known twins yet (first twin learns us when its own
    // announce arrives here — our handler echoes _sendTwinAnnounce back).
    Timer(const Duration(seconds: 6), _sendTwinAnnounce);

    // Key rotation: check on startup and schedule daily check
    //
    // ── FIRST HARVEST, THEN ANNOUNCE (§4.5.4, S363) ─────────────────
    //
    // Here stood `if (identity.needsRotation()) _performKeyRotation();`
    // — a circular that seals against the stored contact keys
    // BEFORE a single harvest run has run. A device
    // that comes up after days thus seals against exactly the copies
    // it did not update during its absence, although the
    // announcements of the other side lie at this moment with the responsible
    // relay. Derivation and calculated price:
    // `cold_start_rotation_gate.dart`.
    //
    // NO SECOND TICK (working rule 5): the harvest run reports
    // via `reportHarvestRun` (called by `mycelium_seam.dart`/`hostStart`
    // via `Host.start(onFirstCollection:)`; until S392 by `attachV41`,
    // which no longer has a caller), and the fallback deadline rides along on the
    // 30 s tick further below.
    identity.discardPreviousKeysIfExpired();
    if (identity.needsRotation()) {
      _coldStartRotationsTor.defer(DateTime.now());
      _log.info('Key rotation due, but DEFERRED until the first '
          'harvest run (§4.5.4/S363: harvest first, then announce; '
          'fallback period '
          '${_coldStartRotationsTor.fallbackPeriod.inMinutes} min)');
    } else {
      _coldStartRotationsTor.withoutDeferralConsume();
    }
    _keyRotationTimer = Timer.periodic(const Duration(hours: 6), (_) {
      identity.discardPreviousKeysIfExpired();
      // The gate is dead after the first pass; from then on the
      // rotation runs immediately as before. If it is still armed, the
      // due rotation already hangs in it anyway — a second call here
      // would lead it past the gate.
      if (!_coldStartRotationsTor.consumed) return;
      if (identity.needsRotation()) _performKeyRotation();
    });

    // §26.6.2 package C: re-sends pending KEY_ROTATION_BROADCAST every 24h
    // until every contact either ACKs or expires (default 90d / 3 attempts).
    // Fire once on startup so a long-offline sender resumes retries at boot.
    _retryPendingKeyRotations();
    _keyRotationRetryTimer = Timer.periodic(
        const Duration(hours: 24), (_) => _retryPendingKeyRotations());

    // Message expiry: check every 30 seconds for expired messages
    // E-7: the lockout transition rides along on THIS tick instead of opening
    // its own timer (working rule #5). Once immediately, so that a
    // restart within the deadline does not close the expired lockout only 30 s
    // later — and so that the loaded set is held against the clock
    // at least once.
    _sweepLockouts();
    // §14.4 transition window on THE SAME tick — no second rhythm
    // (working rule #5). Once immediately, so that a restart does not close an
    // expired old line only 30 s later.
    _sweepRotationWindows();
    // And the still open old lines back into the harvest register: they
    // live on the disk, the pair register does not. Without this line
    // a restart within the window would only harvest the new line —
    // and the messages of contacts not yet switched over would lie
    // unreachable at the relay.
    _registerOldLines();
    _expiryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkMessageExpiry();
      _sweepLockouts();
      _sweepRotationWindows();
      // §4.5.4/S363 on THE SAME tick — no second rhythm
      // (working rule 5). Costs nothing as long as the gate is not armed.
      _checkRotationsTorDeadline();
      _processedMsgIdsSaveCounter++;
      if (_processedMsgIdsSaveCounter >= 2) {
        _processedMsgIdsSaveCounter = 0;
        _saveProcessedMessageIds();
      }
    });

    // ── CHANNEL INDEX GOSSIP: FALLEN, AND THAT IS A GAIN ───────────
    //
    // Here stood `_moderation.startChannelIndexGossip(5 min)` with
    // `onGossipTargets = sendSysChanDigests` as passenger (§9.5.7). The
    // carrier (`sendSysChanDigests`, `_sysChanPickReachablePeers`) lay in
    // `cleona_service_v3_syschan.dart` and fell along.
    //
    // MEASURED (S356/S357): this loop produced **3.17 GB/day with
    // useful share ZERO** — it did not converge, because every pass
    // offered the same summaries again. It does NOT come back in this form;
    // §16.0 carries the same germ and is noted with the
    // owner.
    //
    // CONSEQUENCE, expressly named instead of concealed (gap G-2): the
    // two system channels (bug log, feature requests, §9.5) thus have
    // no distribution any more. Locally written reports stay local.
    _channelIndex.prune();
    _moderation.startModerationTimer();

    // System channel eviction (§9.5.5)
    _systemChannelEvictionTimer = Timer.periodic(
        const Duration(minutes: 30), (_) => _evictSystemChannels());

    // §7.1 LD-9: delegation cert renewal check (hourly)
    _delegationRenewalTimer = Timer.periodic(
        const Duration(hours: 1), (_) => _checkDelegationRenewal());

    // Stats wiring: **HISTORIC.** Here it said "lives on CleonaNode now
    // (single shared collector across all identities)". `CleonaNode` was
    // deleted with the CUT of 2026-08-31. The collector
    // (`NetworkStatsCollector`, `lib/core/stats/network_stats.dart:378`)
    // has been wired at the composition point since S357 — `service_daemon.dart`
    // and `main.dart` pass the bare byte callbacks into
    // `V41Node.start` (`tagline/v41_node.dart:601-605`). The reason stays
    // the same: #U5, the former per-service `??=` let only the first
    // started service win the callbacks; all later ones saw
    // 0 received bytes.

    // ── FOUR CHAINED NODE CALLBACKS: FALLEN (CUT) ──────────────
    //
    // `_wireDeliveryRetryCallbacks()` hooked onto four callbacks of the
    // node: `ackTracker.onAckTimeout`, `onMessageRetryNeeded`,
    // `onMessageRetryExhausted` and the outbox edge. `AckTracker` fell
    // with `lib/core/network/`, and with it the whole
    // RUDP-light resubmission. In V4.1 the storage signal acknowledges
    // (`PlacementAck` -> `V41Delivery.bindPlacementAcked`), not a
    // timer at the transport.
    //
    // `_wireDeviceKemRetrigger()` likewise stood here (§5.10.2): a newly
    // arrived `DeviceKemRecord` triggered S&F and fragment pushes
    // again. Neither push exists any more.
    //
    // `node.ackTracker.onAckReceived` moreover maintained
    // `contact.lastAckedAt` and reported a confirmed request to the first contact
    // rendezvous. THIS BOOKKEEPING SURVIVES — it has always
    // also hung on the receive path (`handleApplicationFrame` sets
    // `lastAckedAt` on every verified frame) and does not need the
    // transport callback.
    //
    // `node.resolveContactDeviceIds = getContactDeviceIds` served the
    // userId->device fallback on route failure and the IPv6 refresh
    // of the peer list — both V3 routing (T).

    _wireTrustAnchorLookup();

    // Uptime clock. FORMERLY it ran on `node._startBase`, so that a
    // multi-identity daemon did not reset it with every further identity.
    // The collector now sits at the service (see
    // [statsCollector]); every service has its own, so none can
    // reset that of another.
    statsCollector.markStarted();

    // The own reachable addresses — V4.1 counterpart of
    // `node.localIps` (`lib/core/tagline/local_addresses.dart`). Once
    // at start; a network change rewrites them in [onNetworkChanged].
    await _refreshLocalAddresses();

    // S366: `store` along, otherwise the service would continue to write its setting
    // to `notification_settings.json` — the last bare
    // plaintext writer in the profile (in none of the S363 inventories).
    await notificationSound.init(identity.profileDir, store: store);

    _initIdentityPublisher();

    // Init voice transcription service (whisper.cpp)
    //
    // S366: the chosen language, the retention period and the
    // model size come from the area `transcription_config` of the
    // storage, no longer from `transcription_config.json`. The reader MUST
    // migrate along: if it stayed at the file, it would never find it again after the
    // switch, silently fall back to `production()` —
    // language `auto`, 30 days, `base` — and nobody would see that the
    // user's choice no longer arrives at all.
    var vtConfig = VoiceTranscriptionConfig.production();
    try {
      final vts = VoiceTranscriptionSettings.readFrom(store);
      if (vts != null) {
        vtConfig = VoiceTranscriptionConfig(
          defaultLanguage: vts.defaultLanguage,
          audioRetentionDays: vts.audioRetentionDays,
          modelSize: _parseModelSize(vts.modelSize),
        );
        _log.info('Voice transcription config loaded: lang=${vtConfig.defaultLanguage}');
      }
    } catch (e) {
      _log.warn('Failed to load transcription config: $e');
    }
    _voiceTranscription = VoiceTranscriptionService(
      config: vtConfig,
      profileDir: profileDir,
      // S366: the wording lies in the area `voice_transcriptions` of the
      // storage, no longer in `voice_transcriptions.json.enc` — hence
      // `store` instead of `fileEnc`.
      store: store,
    );
    _voiceTranscription!.onTranscriptionComplete = _onLocalTranscriptionComplete;
    if (_platformAudioDecoder != null) {
      _voiceTranscription!.platformAudioDecoder = _platformAudioDecoder;
    }
    await _voiceTranscription!.start();

    // Init media auto-archive manager (if configured)
    await _initArchive();

    _initUpdateChecking();

    // Of the NAT wizard the SETTING remains, not the trigger: the
    // `NatWizardTrigger` read `getNetworkStats()` and
    // `statsCollector.uptime`, both without V4.1 counterpart. A
    // "never show again" must nonetheless survive the restart, so
    // the file continues to be read (justification in
    // `cleona_service_pure.dart`).
    _loadNatWizardSettings();

    _log.info('CleonaService started. User-ID: ${identity.userIdHex.substring(0, 16)}... '
        'Device-Node-ID: ${identity.deviceNodeIdHex.substring(0, 16)}...');
  }

  /// Initialize media auto-archive if configured.
  Future<void> _initArchive() async {
    try {
      // S366: from the area `archive_config` of the storage instead of from
      // `archive_config.json`. The same reason as with the transcription
      // one screen page further up — a reader that stayed hanging on the
      // file would silently leave out the archive after the switch.
      final config = ArchiveConfig.readFrom(store);
      if (config == null) return;
      if (!config.enabledByDefault || config.archiveHost.isEmpty) return;

      final transport = ArchiveTransport.forProtocol(config.defaultProtocol,
          profileDir: profileDir);
      await transport.connect(
        host: config.archiveHost,
        path: config.archivePath,
        username: config.archiveUsername,
        password: config.archivePassword,
        port: config.archivePort,
      );

      _archiveManager = ArchiveManager(
        config: config,
        transport: transport,
        profileDir: profileDir,
        // S366: the archive index lies in the area `archive_entries` of the
        // storage, no longer in `archive_entries.json`.
        store: store,
      );
      // S392 — **this is where the tick is wired to the conversations.**
      // Up to here the scheduler called `runArchiveCheck()` without them;
      // the loop that searches for archivable media was therefore skipped
      // on EVERY tick. The archive only worked when the surface sent
      // `archive_trigger_check`.
      //
      // `ensureAllLoaded()` belongs TO the source, not beside it: after
      // start-up a conversation carries only its most recent message
      // (§21.4.1, S366 stage B), and the archive run searches by AGE.
      // Without the loading it would walk a one-line window per
      // conversation and find practically nothing — silently, because "no
      // archivable media" looks exactly like "nothing was loaded".
      // `ipc_server.dart` does the same before its own `runArchiveCheck`;
      // the guard `smoke_lazy_load_deckung` holds both call sites to it.
      await _archiveManager!.startScheduler(
        conversationSource: () {
          ensureAllLoaded();
          return conversations;
        },
      );
      _log.info('ArchiveManager started (${config.defaultProtocol.name}://${config.archiveHost})');
    } catch (e) {
      _log.warn('ArchiveManager init failed: $e');
      _archiveManager = null;
    }
  }

  // ── Media archive: share identity and narrowing (§21.6, S394) ──────────
  //
  // One implementation for both surfaces: Android/iOS call it in-process,
  // the desktop surface reaches it through `archive_status`,
  // `archive_rebind_share`, `archive_capture_network` and
  // `archive_clear_networks`. None of them carries the archive password.

  /// The status map of [getArchiveShareStatus]; also the answer of the
  /// IPC command `archive_status`.
  Map<String, dynamic> archiveShareStatus() {
    final mgr = _archiveManager;
    ArchiveConfig? cfg = mgr?.config;
    if (cfg == null) {
      try {
        cfg = ArchiveConfig.readFrom(store);
      } catch (_) {}
    }
    final pin = cfg?.activeShareIdentity;
    return {
      'active': mgr != null,
      'entriesCount': mgr?.entries.length ?? 0,
      'pendingCount': mgr?.pendingEntries.length ?? 0,
      'identityState': mgr?.shareIdentityState?.name,
      'identityDetail': mgr?.shareIdentityDetail ?? '',
      'identityPin': pin == null ? null : shortShareIdentity(pin),
      'networks': [
        for (final n in cfg?.allowedNetworks ?? const <ArchiveNetwork>[])
          n.toJson(),
      ],
      'ssidSupported': ssidReadableHere,
    };
  }

  @override
  Future<Map<String, dynamic>?> getArchiveShareStatus() async =>
      archiveShareStatus();

  @override
  Future<bool> rebindArchiveShare() async {
    final mgr = _archiveManager;
    if (mgr != null) {
      mgr.rebindShareIdentity();
      return true;
    }
    try {
      final c = ArchiveConfig.readFrom(store);
      if (c != null) c.withShareIdentity(null).writeTo(store);
      ArchiveManager.forgetSftpHostKey(profileDir);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>?> captureArchiveNetwork() async {
    final n = (await readCurrentNetwork()).capture();
    if (n == null) return null;
    final ok = _changeArchiveNetworks((l) => l.contains(n) ? l : [...l, n]);
    return ok ? n.toJson() : null;
  }

  @override
  Future<bool> clearArchiveNetworks() async =>
      _changeArchiveNetworks((_) => const []);

  bool _changeArchiveNetworks(
      List<ArchiveNetwork> Function(List<ArchiveNetwork>) change) {
    final mgr = _archiveManager;
    if (mgr != null) {
      mgr.setAllowedNetworks(change(mgr.config.allowedNetworks));
      return true;
    }
    try {
      final c = ArchiveConfig.readFrom(store) ?? ArchiveConfig.production();
      c.withAllowedNetworks(change(c.allowedNetworks)).writeTo(store);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Legacy: Full start creating its own node. Used by daemon / in-process fallback.
  Future<void> start() async {
    await startService();
  }

  // ── Message Handling ───────────────────────────────────────────────
  //
  // V3 receive routes via `handleApplicationFrame` (User-KEM-decap) and
  // `handleIncoming*Infra` (Device-KEM-decap), both wired in
  // `service_daemon.dart`.

  /// Tracks when each contact last sent a typing indicator.
  final Map<String, DateTime> _typingTimestamps = {};

  /// Returns true if the given contact is currently typing (within last 5 seconds).
  bool isTyping(String nodeIdHex) {
    final ts = _typingTimestamps[nodeIdHex];
    if (ts == null) return false;
    return DateTime.now().difference(ts).inSeconds < 5;
  }

  // ── §5.4 RE-ARM ON RETURN OF THE OWNER: FALLEN (CUT) ──────
  //
  // `_onPeerNewlyConfirmed(deviceHex)` stood here. Its body was
  // completely V3: get the peer from the routing table, re-request fragments and
  // S&F messages for the own mailbox IDs, let parked
  // outbox entries drain, re-arm expired pushes.
  // Not a single one of these subjects exists any more.
  //
  // The caller was the node. Re-measured on 31.08.2026: there is no other
  // in `lib/` (T).
  //
  // `_lastRearmAt` falls with it — it exclusively throttled
  // `_rearmExpiredPushes`.

  // Pending media: maps messageIdHex -> local file path (sender keeps file until accepted).
  // Persisted to $profileDir/pending_media_sends.json so Two-Stage transfers
  // survive app restarts (the receiver's MEDIA_REQUEST may arrive hours later
  // via S&F, and the in-memory map would be empty after a restart).
  final Map<String, String> _pendingMediaSends = {};

  // Receiver-side Stage-2 reassembly buffer. Keyed by mediaIdHex (the original
  // MEDIA_ANNOUNCE messageId). Holds the partial chunk-array; finalised by
  // MEDIA_COMPLETE → file write + UiMessage state-bump to completed.
  final Map<String, _MediaChunkBuffer> _mediaChunkBuffers = {};

  /// Send a media file (image, file, etc.) to a contact or group.
  /// Two-Stage: sends MEDIA_ANNOUNCEMENT first, actual content on MEDIA_ACCEPT.
  @override
  Future<UiMessage?> sendMediaMessage(
      String conversationId, String filePath) async {
    _log.info('sendMediaMessage: convId=$conversationId path=$filePath');
    if (_reducedMode) {
      _log.warn('sendMediaMessage blocked: reducedMode active');
      return null;
    }
    // ── TWO KINDS OF SOURCE (S362) ──────────────────────────────────
    //
    // (1) a file that the user has just chosen — it lies
    //     outside the profile and in plaintext;
    // (2) an attachment that already lies in the storage — forwarding
    //     (`forwardMessage`) and resending pass `msg.filePath`
    //     in here, and that has been encrypted since S362.
    //
    // Whoever only knows (1) breaks the forwarding of media: `File(...)`
    // on the plaintext path finds nothing any more after the transfer.
    final file = File(filePath);
    final bool outTheDeposit =
        !file.existsSync() && MediaStore.instance.exists(filePath);
    if (!file.existsSync() && !outTheDeposit) {
      _log.warn('sendMediaMessage: file does not exist at $filePath');
      return null;
    }

    const maxFileSize = 500 * 1024 * 1024; // 500 MB
    final fileSizeOnDisk = outTheDeposit
        ? (MediaStore.instance.plainLength(filePath) ?? 0)
        : file.lengthSync();
    if (fileSizeOnDisk > maxFileSize) {
      _log.warn('sendMediaMessage: file too large (${fileSizeOnDisk ~/ (1024 * 1024)} MB), max ${maxFileSize ~/ (1024 * 1024)} MB');
      return null;
    }

    final audioBytes = outTheDeposit
        ? MediaStore.instance.readAll(filePath)!
        : await file.readAsBytes();
    final filename = p.basename(filePath);
    final mimeType = _guessMimeType(filename);
    final fileSize = audioBytes.length;
    final isVoice = _isVoiceFromMime(mimeType);
    final isGroup = _groups.containsKey(conversationId);
    final isChannel = !isGroup && _channels.containsKey(conversationId);

    if (!isGroup && !isChannel) _maybeWriteStaleContactWarning(conversationId);

    // ── THE COPY INTO THE PROFILE GOES ENCRYPTED (S362) ───────────────
    //
    // Until S362 three `file.copySync(persistentPath)` stood here. They were
    // the fourth write place of the finding and the only one on the
    // SEND SIDE: what the user sent then lay in plaintext in the
    // own profile — even if he deleted the source file.
    //
    // The bytes are already present as `audioBytes` (they are needed anyway
    // for hash and sending), hence `writeBytes` instead of a
    // second read from the disk.
    final mediaDir = Directory('$profileDir/media');
    if (!mediaDir.existsSync()) mediaDir.createSync(recursive: true);
    var persistentPath = '${mediaDir.path}/$filename';
    if (filePath != persistentPath) {
      String fallbackNames() {
        final dot = filename.lastIndexOf('.');
        final base = dot > 0 ? filename.substring(0, dot) : filename;
        final ext = dot > 0 ? filename.substring(dot) : '';
        return '${mediaDir.path}/${base}_${DateTime.now().millisecondsSinceEpoch}$ext';
      }

      if (MediaStore.instance.existsEitherWay(persistentPath)) {
        // Same name already taken. If it carries the same content,
        // there is nothing to do; otherwise the new attachment moves to a different
        // name, so that it does not overwrite the old one.
        final present = MediaStore.instance.readAll(persistentPath);
        final equal = present != null &&
            present.length == fileSize &&
            constantTimeEquals(
                SodiumFFI().sha256(present), SodiumFFI().sha256(audioBytes));
        if (!equal) {
          persistentPath = fallbackNames();
          MediaStore.instance.writeBytes(persistentPath, audioBytes);
        }
      } else {
        MediaStore.instance.writeBytes(persistentPath, audioBytes);
      }
    }

    // ── Show message in UI IMMEDIATELY (optimistic update) ──
    // Optimistic UI msg.id is the wire messageId so DELIVERY_RECEIPT
    // (which carries inner.messageId) can match this local message and
    // upgrade `sent → delivered` in `_handleDeliveryReceiptV3`. Mirrors
    // the alignment pattern from `sendTextMessage` (commit 145e24d).
    final messageIdBytes = SodiumFFI().randomBytes(16);
    final tempId = bytesToHex(messageIdBytes);
    final msg = UiMessage(
      id: tempId,
      conversationId: conversationId,
      senderNodeIdHex: identity.userIdHex,
      text: filename,
      timestamp: DateTime.now(),
      type: _msgTypeFromMime(mimeType),
      status: MessageStatus.resting,
      isOutgoing: true,
      filePath: persistentPath,
      mimeType: mimeType,
      fileSize: fileSize,
      filename: filename,
      mediaState: MediaDownloadState.completed,
    );
    _addMessageToConversation(conversationId, msg, isGroup: isGroup, isChannel: isChannel);

    // Yield to let UI repaint before heavy crypto/transcription work
    await Future.delayed(Duration.zero);

    // ── Voice transcription (source-side, non-blocking for UI) ──
    VoiceTranscription? senderTranscript;
    if (isVoice) {
      senderTranscript = await _voiceTranscription?.transcribeNow(filePath);
      if (senderTranscript != null) {
        msg.transcriptText = senderTranscript.text;
        msg.transcriptLanguage = senderTranscript.language;
        msg.transcriptConfidence = senderTranscript.confidence;
        onStateChanged?.call(); // Update UI with transcript
        // S362: HERE STOOD THE WORDING. The first 40 characters of the
        // transcript went into the log in plaintext — while the
        // transcript file itself was encrypted in the same session.
        // Length and language suffice for diagnostics; whoever
        // wants to know WHAT was spoken has the message.
        _log.info('Voice transcribed: ${senderTranscript.text.length} chars');
      }
    }

    // ── Build payload ──
    Uint8List bytes;
    if (isVoice) {
      final voicePayload = proto.VoicePayload()..audioData = audioBytes;
      if (senderTranscript != null) {
        voicePayload.transcriptText = senderTranscript.text;
        voicePayload.transcriptLanguage = senderTranscript.language;
        voicePayload.transcriptConfidence = senderTranscript.confidence;
      }
      bytes = Uint8List.fromList(voicePayload.writeToBuffer());
    } else {
      bytes = audioBytes;
    }

    // Compute content hash
    final sodium = SodiumFFI();
    final contentHash = sodium.sha256(audioBytes);

    // Generate thumbnail for images. Architecture §3.4.1: "compressed thumbnail
    // (max 100 KB)". Earlier versions used `bytes.sublist(0, 100*1024)` which
    // produced TRUNCATED image bytes (header + partial data) — receiver's
    // Image.memory then crashed with "Codec failed to produce an image" on every
    // image > 100KB. Now: real decode → resize to 320×320 max → JPEG-encode at
    // q=70. Falls back to original bytes if decode fails or already small enough.
    Uint8List? thumbnail;
    if (mimeType.startsWith('image/') && bytes.isNotEmpty) {
      if (bytes.length <= 100 * 1024) {
        // Already small — use original bytes (likely valid as-is).
        thumbnail = bytes;
      } else {
        try {
          final decoded = img.decodeImage(bytes);
          if (decoded != null) {
            // Maintain aspect ratio, fit into 320×320.
            final resized = img.copyResize(
              decoded,
              width: decoded.width >= decoded.height ? 320 : null,
              height: decoded.height > decoded.width ? 320 : null,
              interpolation: img.Interpolation.linear,
            );
            final encoded = Uint8List.fromList(img.encodeJpg(resized, quality: 70));
            // Cap final at 100KB for §3.4.1 compliance — drop quality if needed.
            thumbnail = encoded.length <= 100 * 1024
                ? encoded
                : Uint8List.fromList(img.encodeJpg(resized, quality: 50));
            // If even q=50 is over 100KB (very rare), drop thumbnail entirely
            // rather than ship invalid bytes.
            if (thumbnail.length > 100 * 1024) thumbnail = null;
          }
        } catch (e) {
          _log.warn('Thumbnail generation failed for $filename: $e — '
              'shipping no thumbnail rather than truncated bytes');
          thumbnail = null;
        }
      }
    }

    // Build MEDIA_ANNOUNCEMENT metadata
    final metadata = proto.ContentMetadata()
      ..mimeType = mimeType
      ..fileSize = Int64(fileSize)
      ..filename = filename
      ..contentHash = contentHash;
    if (thumbnail != null) metadata.thumbnail = thumbnail;
    // Transcript also into the metadata (§14.9). Inline it is additionally carried in the
    // VoicePayload; in the two-stage path the metadata is the only carrier,
    // because MEDIA_ANNOUNCE sends without payload and the stage 2 chunks are raw
    // file bytes. Without this every voice message >256KB (~16s at
    // 128kbps AAC) arrived at the recipient without text.
    if (senderTranscript != null) {
      metadata.transcriptText = senderTranscript.text;
      metadata.transcriptLanguage = senderTranscript.language;
      metadata.transcriptConfidence = senderTranscript.confidence;
    }

    final announcementBytes = metadata.writeToBuffer();

    // Determine recipients
    List<ContactInfo> recipients;
    if (isGroup) {
      final group = _groups[conversationId];
      if (group == null) return null;
      recipients = [];
      for (final m in group.members.values) {
        if (m.nodeIdHex == identity.userIdHex) continue;
        final (x25519Pk, mlKemPk, ed25519Pk) = _resolveMemberKeys(m.nodeIdHex,
            memberX25519Pk: m.x25519Pk, memberMlKemPk: m.mlKemPk, memberEd25519Pk: m.ed25519Pk);
        if (x25519Pk == null || mlKemPk == null) continue;
        recipients.add(ContactInfo(
          nodeId: hexToBytes(m.nodeIdHex),
          displayName: m.displayName,
          x25519Pk: x25519Pk,
          mlKemPk: mlKemPk,
          ed25519Pk: ed25519Pk,
          status: 'accepted',
          // §15.2: this record is a throwaway image for ONE sending,
          // and `ed25519Pk` in it comes from `_resolveMemberKeys` — i.e.
          // the CURRENT key of the member. Without the anchor of the
          // real contact record the group leg would compute after a
          // rotation of the member under a different tag than the
          // 1:1 path to the same human.
          peerFoundingEd25519Pk: v41PeerFoundingPk(_contacts[m.nodeIdHex]),
        ));
      }
    } else if (isChannel) {
      final channel = _channels[conversationId];
      if (channel == null) return null;
      if (!_hasChannelPermission(channel, 'post')) {
        _log.warn('sendMediaMessage: no post permission in channel $conversationId');
        return null;
      }
      recipients = [];
      for (final member in channel.members.values) {
        if (member.nodeIdHex == identity.userIdHex) continue;
        final (x25519Pk, mlKemPk, ed25519Pk) = _resolveMemberKeys(member.nodeIdHex,
            memberX25519Pk: member.x25519Pk, memberMlKemPk: member.mlKemPk, memberEd25519Pk: member.ed25519Pk);
        if (x25519Pk == null || mlKemPk == null) continue;
        recipients.add(ContactInfo(
          nodeId: hexToBytes(member.nodeIdHex),
          displayName: member.displayName,
          x25519Pk: x25519Pk,
          mlKemPk: mlKemPk,
          ed25519Pk: ed25519Pk,
          status: 'accepted',
          // §15.2, see the group branch above: the anchor comes from
          // the real contact record, not from the throwaway image.
          peerFoundingEd25519Pk:
              v41PeerFoundingPk(_contacts[member.nodeIdHex]),
        ));
      }
    } else {
      final contact = _contacts[conversationId];
      if (contact == null || contact.status != 'accepted') {
        _log.warn('sendMediaMessage: cannot send to non-accepted contact convId=$conversationId '
            'contact=${contact != null ? "exists status=${contact.status}" : "MISSING"} '
            '(contacts loaded: ${_contacts.length})');
        return null;
      }
      recipients = [contact];
    }

    // ── STEP 1 OF THE CUT (31.08.2026): THE LANE CHOICE FROM §9.3 ────────
    //
    // Until the cut here stood `final twoStage = fileSize > 256 * 1024;`
    // and sent everything above it on the V3 two-stage path
    // (MEDIA_ANNOUNCE -> MEDIA_REQUEST -> MEDIA_CHUNK -> MEDIA_COMPLETE).
    // The 256 KB were the same number as §9.3's lower limit at the time and
    // meant something different: there they separated "inline" from
    // "two-stage", here "cell path" from "media lane". The lower limit
    // has stood at 32 KB since 31.08.2026 ([kFountainWorthwhileBytes]);
    // the 256 KB of this line are thus finally history.
    //
    // THE DECISION IS MADE IN A FUNCTION, NOT IN A `?:`.
    // §9.3: the lane is "decided per transfer by the viability cascade
    // of §17.6, **never by silent preference**". A decision that is to be
    // made that way must be exhaustively testable — hence
    // `chooseMediaLane` (`lib/core/bulk/bulk_lane.dart`) and not a
    // condition in this line.
    //
    // ONE INPUT IS FIXED TO `false` TODAY, with reason (D-4, S372: until
    // then this said "TWO inputs" — the paragraph had been outdated since
    // 02.09.2026, see "THE SEAM..." below):
    //
    // **ADDENDUM 31.08.2026 on the order:** `chooseMediaLane` has since
    // checked the SIZE before the consent. Whoever builds the path for
    // `perTransferConsent` must therefore show the dialog only from
    // [kFountainWorthwhileBytes] on — below that the object does not enter
    // any media lane at all, there is nothing to downgrade, and a
    // dialog appearing for no reason is clicked away.
    //
    //   * `bothOnline`/`volunteerViable` — the stream lane (§17.6) runs
    //     via plane D, and that does not exist. As long as no volunteer
    //     can commit, "both online" is not a condition that
    //     selects anything. §9.3 covers exactly that: "Otherwise → the bulk lane."
    //
    // NO MODE AT THIS PLACE ANY MORE (S389, §3.3/§12.1). Here
    // `secureChat` read until S389 `Contact.secureMode`/`Group.secureMode` — the
    // switch from the chat settings dialog that §12.1 excludes —
    // and `perTransferConsent` carried the answer of the consent dialog,
    // i.e. a second choice of the send path, this time per file. Both are
    // gone. The lane choice is thus solely a question of SIZE, as §9.4
    // keeps it anyway: "Media take one of three lanes, first
    // by size."
    //
    // `chooseMediaLane` keeps its two parameters — the file lies
    // in `lib/core/bulk/` and belongs to the superseded layer, whose
    // teardown is not the subject of this task. They get here the
    // value that means "no mode".
    final lane = chooseMediaLane(
      payloadBytes: fileSize,
      secureChat: false,
      perTransferConsent: false,
      isGroup: isGroup || isChannel,
      bothOnline: false,
      volunteerViable: false,
    );
    // WHAT IS MEASURED IS THE OBJECT, not the frame — unlike in
    // `routeFor`. The two gates carry the same number
    // (`kFountainWorthwhileBytes`) and see different quantities; neither
    // replaces the other.
    //
    // ── TWO LANES, ONE PATH (S372, decision E-3 = D) ───────────────
    //
    // `MediaLane.reedSolomon` and `MediaLane.bulk` take THE SAME
    // send path: the same tag, the same seal, the same `0x05` frame,
    // the same holder, the same harvest. Different is only the codec,
    // and that is chosen by `MediaBulkLane.beginSend` from the object size
    // (`mediaCodecFor`). That is why an OR stands here and no third
    // branch — a second send loop would be a second
    // wire format with the same bytes.
    final onMediaLane =
        lane.lane == MediaLane.bulk || lane.lane == MediaLane.reedSolomon;
    _log.info('[E2E media-send-path-v41] entscheidung=$lane '
        'fileSize=$fileSize '
        'recipients=${recipients.length} '
        'convId=${conversationId.substring(0, 8)}');
    if (lane.refusal == MediaRefusal.secureWithoutConsent) {
      _log.warn('sendMediaMessage: Secure chat without consent for THIS '
          'transfer (§9.3 „Mode coupling", §12) — ALL media lanes '
          'are speed class or weaker (B-29), and a remembered '
          'blanket consent would be the silent mode switch. Not '
          'sent.');
      return null;
    }
    if (lane.refusal == MediaRefusal.aboveCodecLimit) {
      _log.warn('sendMediaMessage: $fileSize B exceed the '
          'block format (objectLength is 4 B wide) — not sent.');
      return null;
    }
    if (lane.lane == MediaLane.stream) {
      // Unreachable today (`volunteerViable: false`). Stands here
      // nonetheless, so that the stream lane later steps NEXT to the bulk lane and
      // not in its place — §9.3: "Blocks are lane-neutral."
      _log.warn('sendMediaMessage: stream lane (§17.6) chosen, but it '
          'needs Layer D and is not built — not sent.');
      return null;
    }
    // GM-1 (§9.1.4): group/channel media must carry groupId + membership tag
    final groupForMedia = isGroup ? _groups[conversationId] : null;
    final channelForMedia = isChannel ? _channels[conversationId] : null;
    final mediaGroupId = (isGroup || isChannel) ? hexToBytes(conversationId) : null;
    final mediaGmEpoch = groupForMedia?.membershipEpoch ?? channelForMedia?.membershipEpoch;
    final mediaGmHash = groupForMedia != null
        ? _computeMembershipHash(groupForMedia.membershipEpoch, conversationId, groupForMedia.members)
        : channelForMedia != null
            ? _computeChannelMembershipHash(channelForMedia.membershipEpoch, conversationId, channelForMedia.members)
            : null;
    String? firstMsgId;
    if (!onMediaLane) {
      // BELOW THE LOWER LIMIT (§9.3, normative): "neither lane is
      // used … Small media therefore ride the cell path like any
      // message." Exactly that happens here — MEDIA_INLINE goes through
      // `sendToUser`, and `routeFor` leads it onto the cell path.
      //
      // THE GAP THAT STOOD HERE IS CLOSED — AND SINCE S372 WITHOUT A
      // SIDE EFFECT. The cell path splits up to `kMaxSplitPayloadBytes` =
      // 32768 B; §9.3 set the lower limit of the lanes to 262144 B, and
      // in between the document named no path — a photo of 200 KB
      // simply did not go out. On 31.08.2026 the gap was
      // closed by the lower limit dropping to 32 KB; thereby the
      // band 32..256 KB however rode the RATELESS lane, i.e. exactly the one that the
      // measurement in appendix A shows there as the worst. Since
      // decision E-3 = D this band is carried by Reed-Solomon
      // (`codec/erasure_stripes.dart`), and both limits still
      // abut each other. What reaches THIS branch is really
      // small enough for the cell path.
      for (final recipient in recipients) {
        if (recipient.x25519Pk == null || recipient.mlKemPk == null) continue;
        final ok = await sendToUser(
          recipientUserId: recipient.nodeId,
          messageType: proto.MessageTypeV3.MTV3_MEDIA_INLINE,
          payload: bytes,
          contentMetadata: metadata,
          messageId: messageIdBytes,
          groupId: mediaGroupId,
          groupMembershipEpoch: mediaGmEpoch,
          groupMembershipHash: mediaGmHash,
          recipientX25519PkOverride: recipient.x25519Pk,
          recipientMlKemPkOverride: recipient.mlKemPk,
          recipientEd25519PkOverride: recipient.ed25519Pk,
        );
        if (ok) statsCollector.addMessageSent();
      }
      firstMsgId = tempId;
    } else {
      // ── THE BULK LANE (§9.3) ────────────────────────────────────────
      //
      // No MEDIA_CHUNK, no `_pendingMediaSends`, no waiting for a
      // MEDIA_REQUEST of the recipient: the object is encoded ratelessly,
      // EVERY BLOCK stored EXACTLY ONCE with a responsible always-on holder,
      // and the recipient SAMPLES. "No block is special, no
      // index is allocated."
      final offer = await _sendOnBulkLane(
        conversationId: conversationId,
        messageId: tempId,
        object: bytes,
        isGroupOrChannel: isGroup || isChannel,
        preview: _microPreview(thumbnail, mimeType),
        metadata: metadata,
        recipients: recipients,
        messageIdBytes: messageIdBytes,
        groupId: mediaGroupId,
        groupMembershipEpoch: mediaGmEpoch,
        groupMembershipHash: mediaGmHash,
      );
      if (!offer) {
        // NO FALLBACK TO V3. The message stays lying visibly with the
        // user; a secret second path would be the
        // dual stack from §7 and would be invisible, because both
        // "work".
        _log.warn('[E2E media-send-path-v41] bulk lane stored '
            'nothing — not sent, no fallback to V3');
      }
      firstMsgId = tempId;
      // `announcementBytes` carries the V3 metadata and is not the carrier on the
      // bulk lane: there the offer travels as
      // `BulkAnnounce` (full content hash, object length, drawn
      // root, micro preview <= kAnnouncePreviewBudgetBytes). The value
      // remains computed for the application's stores (preview in the chat).
      // ignore: unnecessary_statements
      announcementBytes;
    }

    // Update message with final ID and status
    //
    // THE IDENTIFIER CHANGES HERE (§21.4.1). The message was already
    // inserted further up with its provisional identifier and thus
    // also stored; without the reversal an orphan row would remain under the old identifier
    // that would appear as a second hit in every full-text search.
    // It must be saved BEFORE overwriting.
    final previousId = msg.id;
    msg.id = firstMsgId;
    final thumbnailB64 = thumbnail != null ? base64Encode(thumbnail) : null;
    msg.thumbnailBase64 = thumbnailB64;
    // AP-4 (§5.1c K2): here stood `msg.status = MessageStatus.sent` — without
    // taking back a return value, without `l3Result`, without any
    // observation. The statement has been dropped without replacement with `sent` (v4_1
    // §22.5.1: "Neither a socket write, nor an address, nor a counter sets
    // a delivery state").
    //
    // NOT EVEN AFTER THE CUT. On the bulk lane `delivered` flips
    // exclusively on the DECODED receipt of the recipient (§9.3, D2)
    // — storage receipts and relay signals are transport diagnostics and
    // flip nothing. The message stays at `placing` until exactly this
    // receipt comes (`MediaBulkLane.acceptReceipt`).
    if (previousId != msg.id) forgetMessage(previousId);
    persistMessage(conversationId, msg);
    _saveConversations();
    onStateChanged?.call();

    _log.info('[E2E media-send-done] msgId=${msg.id.substring(0, 8)} '
        'filename=$filename size=$fileSize recipient=${conversationId.substring(0, 8)} '
        'mode=${onMediaLane ? "${lane.lane!.name} lane (§9.3)" : "cell path (§9.3 lower bound)"}');
    return msg;
  }

  /// The micro preview of the offer — at most
  /// [kAnnouncePreviewBudgetBytes] (969 B, "one cell").
  ///
  /// ── WHY NOT SIMPLY `thumbnail` (31.08.2026) ────────────────────
  ///
  /// `thumbnail` is the V3 preview image according to §3.4.1 and may be **100 KB**
  /// large (320x320 JPEG q=70, built at the top of this method). Until
  /// today exactly this buffer was passed as micro preview, and
  /// `MediaBulkLane.beginSend` cut it off at byte 979. A JPEG cut off at
  /// byte 979 is however not a smaller image, but a
  /// header without a body: at the recipient it landed as
  /// `thumbnailBase64` in the bubble, and `Image.memory` failed on it
  /// — the same error that §3.4.1 already had once ("Codec failed to
  /// produce an image", justification of the real thumbnail further up).
  ///
  /// Here instead an OWN, tiny image is encoded: 48x48,
  /// q=40, and if that still does not fit, q=25. If it then
  /// still does not fit, there is no preview — that costs an image in
  /// the bubble, not the transfer.
  ///
  /// Non-images get none at all: a file has no preview image,
  /// and a prefix of its bytes would not be one.
  Uint8List? _microPreview(Uint8List? thumbnail, String mimeType) {
    if (thumbnail == null || thumbnail.isEmpty) return null;
    if (!mimeType.startsWith('image/')) return null;
    if (thumbnail.length <= kAnnouncePreviewBudgetBytes) return thumbnail;
    try {
      final decoded = img.decodeImage(thumbnail);
      if (decoded == null) return null;
      final small = img.copyResize(
        decoded,
        width: decoded.width >= decoded.height ? 48 : null,
        height: decoded.height > decoded.width ? 48 : null,
        interpolation: img.Interpolation.average,
      );
      for (final q in <int>[40, 25]) {
        final bytes = Uint8List.fromList(img.encodeJpg(small, quality: q));
        if (bytes.length <= kAnnouncePreviewBudgetBytes) return bytes;
      }
      _log.warn('Bulk offer: micro preview does not fit even at q=25 into '
          'one cell ($kAnnouncePreviewBudgetBytes B) — offer without '
          'preview. The transfer runs anyway.');
      return null;
    } catch (e) {
      _log.warn('Bulk offer: micro preview cannot be built ($e) — '
          'offer without preview');
      return null;
    }
  }

  /// Submits an object on the bulk lane (§9.3).
  ///
  /// ── THE ORDER IS ESSENTIAL ─────────────────────────────────
  ///
  /// FIRST STORE, THEN ANNOUNCE. The offer names the full
  /// content hash and the object length; as soon as the recipient has it,
  /// he computes the same transfer tag and starts to sample
  /// (§9.3: "the recipient **scans** the holding relais"). If it came
  /// first, he would sample an empty line and produce a
  /// re-request for something that is not even in transit yet.
  ///
  /// ── WHAT DOES *NOT* HAPPEN HERE ──────────────────────────────────────
  ///
  /// No `m x R`. [MediaBulkLane.emit] hands the transport a
  /// list of blocks, and the length of this list is the number of
  /// cells that may go out. §9.3: "Each block is placed
  /// **once** … per-block `m × R` would cost a factor of **60** on the
  /// wire and buys nothing a rateless code does not already provide."
  ///
  /// No `_pendingMediaSends`. That was the V3 two-stage path: the
  /// sender held the file ready and waited for a MEDIA_REQUEST. On
  /// the bulk lane the blocks lie in the network and the recipient fetches them
  /// himself — that is the offline promise (j).
  ///
  /// Returns `true` if at least one store was accepted AND the
  /// offer went out to at least one recipient.
  Future<bool> _sendOnBulkLane({
    required String conversationId,
    required String messageId,
    required Uint8List object,
    required bool isGroupOrChannel,
    required Uint8List? preview,
    required proto.ContentMetadata metadata,
    required List<ContactInfo> recipients,
    required Uint8List messageIdBytes,
    Uint8List? groupId,
    int? groupMembershipEpoch,
    Uint8List? groupMembershipHash,
  }) async {
    final lane = mediaBulkLane;
    if (lane.transport == null) {
      // THE HOLDER SIDE HAS BEEN BUILT SINCE 02.09.2026, so this
      // branch is no longer the normal case, but the exceptional case: it
      // now means "no V4.1 node hangs on this identity".
      // `attachV41` assembles the transport (`media_bulk_transport_v41.dart`)
      // together with plane D; without a node — `CLEONA_V41=0`, a pure
      // service setup in the test — it does not exist.
      //
      // REFUSED AND NOT FALLEN BACK TO V3, unchanged since
      // S349: a silent V3 path would be the dual stack from §7 and would be
      // invisible, because both "work".
      _log.warn('Bulk lane (§9.3): no MediaBulkTransport attached — '
          'no V4.1 node is attached to this identity (attachV41 sets '
          'it together with Layer D). No fallback to V3.');
      return false;
    }

    // ── THE TRANSFER KEY IS DRAWN, NOT DERIVED ─────────
    //
    // Until 31.08.2026 a lookup of `K_AB` stood here, from which in the
    // 1:1 case `K_T = HKDF(K_AB, "media/<hash>")` fell. The branch is
    // struck: `K_AB` falls out of pure X25519
    // (`tagline/pair_registry.dart:99-114`, no ML-KEM), thus the
    // media content was the ONLY payload stream without PQ coverage — and because
    // §15.2 keeps `K_AB` rotation-stable, without any forward secrecy.
    //
    // `K_T` is now drawn per transfer and travels along in the offer.
    // The offer goes below through `sendToUser` -> `routeFor` ->
    // `DeliveryRoute.v41` -> `MessageSealer.seal`, and there
    // `_combine` mixes the ML-KEM-768 daily capsule with the X25519 DH
    // (`message_seal.dart:374`). Exactly there the PQ coverage
    // of the media content has lain since then.
    //
    // A side effect that should expressly stand here: the bulk lane
    // thus no longer needs a pair key for 1:1. Where previously a
    // sending failed on a missing `K_AB`, it now goes through —
    // failure only happens when the offer is not deliverable.
    final started = lane.beginSend(
      conversationId: conversationId,
      messageId: messageId,
      object: object,
      preview: preview,
    );
    if (started == null) {
      _log.warn('Bulk lane: the object cannot be encoded '
          '(${lane.lastError}) — not sent, no fallback to V3.');
      return false;
    }

    // ── THE PARTIAL LOSS BECOMES VISIBLE (S363) ──────────────────────────
    //
    // Until 03.09.2026 only `deposited == 0` stood here, and that was the
    // ONLY question this caller could ask. A PARTIAL loss was
    // thus invisible: at 200 MB 98.4 % of the planned
    // blocks were lost before a cell went out, and this method
    // reported success (B-1). The callback says it now — it comes when
    // the storing is through, and in the pull model that is only hours after
    // this line.
    lane.onPlacementDone = _bulkShipmentDonePlaced;
    final deposited = lane.emit(started.ticket);
    if (deposited == 0) {
      // §9.3: "`failed` is reserved for 'no volunteer and no holder
      // accepted anything'." Exactly this case.
      lane.endSend(started.ticket);
      return false;
    }
    _log.event('V4.1 BULK ${started.ticket.sender.sourceBlocks} source blocks, '
        '${started.ticket.sender.plannedBlocks} planned, $deposited deposited, '
        '${started.ticket.blocksRemaining} follow at the pace of the egress '
        '(EXACTLY ONE per block, §9.3)');

    // ── THE OFFER: AN ORDINARY MESSAGE ───────────────────────
    //
    // §9.3: "Control flow — announce with a one-cell micro-preview,
    // request, refill, DECODED receipt — rides the delivery layer in the
    // chat's mode." It therefore goes through `sendToUser` like any text.
    //
    // WITHOUT THE V3 PREVIEW IMAGE. `metadata.thumbnail` carries up to 100 KB
    // (§3.4.1) and would thus burst every cell and also the
    // split limit. On the bulk lane the preview is part of the
    // offer and capped at [kAnnouncePreviewBudgetBytes] ("one
    // cell"); it is built in [_microPreview]. The large
    // preview image stays locally attached to `msg.thumbnailBase64`.
    final lean = proto.ContentMetadata()
      ..mergeFromMessage(metadata)
      ..clearThumbnail();
    final offer = started.announce.encode();
    var delivered = 0;
    for (final recipient in recipients) {
      if (recipient.x25519Pk == null || recipient.mlKemPk == null) continue;
      final ok = await sendToUser(
        recipientUserId: recipient.nodeId,
        messageType: proto.MessageTypeV3.MTV3_MEDIA_ANNOUNCE,
        payload: offer,
        contentMetadata: lean,
        messageId: messageIdBytes,
        groupId: groupId,
        groupMembershipEpoch: groupMembershipEpoch,
        groupMembershipHash: groupMembershipHash,
        recipientX25519PkOverride: recipient.x25519Pk,
        recipientMlKemPkOverride: recipient.mlKemPk,
        recipientEd25519PkOverride: recipient.ed25519Pk,
      );
      if (ok) delivered++;
    }
    if (delivered == 0) {
      lane.endSend(started.ticket);
      return false;
    }
    return true;
  }

  /// Accept a media download (Two-Stage: send MEDIA_ACCEPT).
  @override
  Future<bool> acceptMediaDownload(String conversationId, String messageId) async {
    _log.info('[E2E media-accept-send] msgId=${messageId.substring(0, 8)} convId=${conversationId.substring(0, 8)}');
    // ── ON THE BULK LANE "ACCEPTING" IS A SAMPLING (§9.3) ─────────
    //
    // The V3 path sent a MEDIA_REQUEST here, which the sender answered with
    // MEDIA_CHUNKs — he had to hold the file ready for that
    // (`_pendingMediaSends`). On the bulk lane the blocks lie in the
    // network, and the recipient fetches them himself: "the recipient
    // **scans** the holding relays". There is thus nobody left to whom
    // a request would have to be addressed.
    //
    // THE CHECK IS MADE ON THE RUNNING HARVEST, not on a switch: only
    // if `_handleBulkAnnounce` has created a harvest for this identifier
    // is it a bulk message. Everything else falls unchanged
    // through into the previous path.
    final harvest = mediaBulkLane.receiveFor(messageId);
    if (harvest != null) {
      final ok = mediaBulkLane.scan(harvest);
      _log.info('[E2E media-accept-bulk] msgId=${messageId.substring(0, 8)} '
          'scanned=$ok (run ${harvest.scans}) — no MEDIA_REQUEST, the '
          'blocks are in the network (§9.3)');
      return ok;
    }
    final conv = conversations[conversationId];
    if (conv == null) {
      _log.warn('[E2E media-accept-send] ABORT: conversation not found');
      return false;
    }

    // Enforce allowDownloads policy
    if (!conv.config.allowDownloads) {
      _log.warn('[E2E media-accept-send] BLOCKED: allowDownloads=false for $conversationId');
      return false;
    }

    ensureLoaded(conversationId);
    final msg = conv.messages.where((m) => m.id == messageId).firstOrNull;
    if (msg == null || msg.mediaState != MediaDownloadState.announced) {
      _log.warn('[E2E media-accept-send] ABORT: msg=${msg != null ? "exists state=${msg.mediaState.name}" : "MISSING"} '
          '(expected mediaState=announced)');
      return false;
    }

    // For now, just mark as downloading (the actual content delivery is handled
    // when we receive the IMAGE/FILE response from sender)
    msg.mediaState = MediaDownloadState.downloading;
    persistMessage(conversationId, msg);
    onStateChanged?.call();
    _saveConversations();

    // Send V3 MEDIA_REQUEST to the original sender. Payload = original
    // messageId bytes (16 bytes). Sender (C4 — see _handleMediaRequestV3)
    // looks up _pendingMediaSends[msgIdHex] and starts the bulk push.
    final contact = _contacts[msg.senderNodeIdHex];
    if (contact == null ||
        contact.x25519Pk == null ||
        contact.mlKemPk == null) {
      _log.warn('[E2E media-accept-send-v3] ABORT: contact=${contact != null ? "exists" : "MISSING"}');
      return false;
    }
    final ok = await sendToUser(
      recipientUserId: contact.nodeId,
      messageType: proto.MessageTypeV3.MTV3_MEDIA_REQUEST,
      payload: hexToBytes(messageId),
    );
    _log.info('[E2E media-accept-send-v3] msgId=${messageId.substring(0, 8)} '
        'sender=${msg.senderNodeIdHex.substring(0, 8)} → MEDIA_REQUEST sendToUser ok=$ok');
    return ok;
  }

  /// A not yet used name in the media directory.
  ///
  /// **`existsEitherWay` and not `File(...).existsSync()` (S362).** The
  /// attachment now lies under `<name>.cmenc`; whoever only checks the plaintext name
  /// considers EVERY taken name free and overwrites on the
  /// next receipt of the same name the previous attachment. Both versions
  /// are asked, because during the transfer both occur.
  static String _uniqueMediaPath(String dirPath, String filename) {
    var path = '$dirPath/$filename';
    if (!MediaStore.instance.existsEitherWay(path)) return path;
    final dot = filename.lastIndexOf('.');
    final base = dot > 0 ? filename.substring(0, dot) : filename;
    final ext = dot > 0 ? filename.substring(dot) : '';
    for (var i = 1; i < 1000; i++) {
      path = '$dirPath/${base}_$i$ext';
      if (!MediaStore.instance.existsEitherWay(path)) return path;
    }
    return '$dirPath/${DateTime.now().millisecondsSinceEpoch}$ext';
  }

  /// Maps MIME type to the correct MessageType.
  ///
  /// V3 has no media-subtype enum — `MTV3_MEDIA_INLINE` covers
  /// image/video/audio/file uniformly. This helper produces the
  /// UI-side [UiMessageType] tag for the chat-card row only; the wire
  /// layer always emits `MTV3_MEDIA_INLINE`.
  /// For voice-vs-non-voice branching see [_isVoiceFromMime].
  UiMessageType _msgTypeFromMime(String mimeType) {
    if (mimeType.startsWith('image/')) return UiMessageType.image;
    if (mimeType.startsWith('audio/')) return UiMessageType.voiceMessage;
    if (mimeType.startsWith('video/')) return UiMessageType.video;
    return UiMessageType.file;
  }

  /// Whether this V3 message type carries user-authored content that must
  /// be dropped while reduced-mode (sec-h5 §8.2 / T11) is active. Returning
  /// false means the type is infrastructure / DHT / signaling and should
  /// keep flowing even when the local user has skipped a hard-block update.
  ///
  /// Mirrors the user-initiated send-paths gated in T11. V3 collapses
  /// IMAGE/VIDEO/GIF/FILE into `MTV3_MEDIA_INLINE`; voice has its own
  /// `MTV3_VOICE_MESSAGE`. `MTV3_MEDIA_REQUEST` carries
  /// request-the-upload semantics. `MTV3_REPLY` is classified as
  /// user-content.
  static bool _isUserMessage(proto.MessageTypeV3 type) {
    switch (type) {
      case proto.MessageTypeV3.MTV3_TEXT:
      case proto.MessageTypeV3.MTV3_MEDIA_INLINE:
      case proto.MessageTypeV3.MTV3_VOICE_MESSAGE:
      case proto.MessageTypeV3.MTV3_MEDIA_ANNOUNCE:
      case proto.MessageTypeV3.MTV3_MEDIA_REQUEST:
      case proto.MessageTypeV3.MTV3_MEDIA_REJECT:
      case proto.MessageTypeV3.MTV3_MEDIA_CHUNK:
      case proto.MessageTypeV3.MTV3_REACTION:
      case proto.MessageTypeV3.MTV3_REPLY:
      case proto.MessageTypeV3.MTV3_EDIT:
      case proto.MessageTypeV3.MTV3_DELETE:
      case proto.MessageTypeV3.MTV3_CHANNEL_POST:
      case proto.MessageTypeV3.MTV3_CALENDAR_INVITE:
      case proto.MessageTypeV3.MTV3_CALENDAR_RSVP:
      case proto.MessageTypeV3.MTV3_CALENDAR_UPDATE:
      case proto.MessageTypeV3.MTV3_CALENDAR_DELETE:
      case proto.MessageTypeV3.MTV3_FREE_BUSY_REQUEST:
      case proto.MessageTypeV3.MTV3_FREE_BUSY_RESPONSE:
      case proto.MessageTypeV3.MTV3_POLL_CREATE:
      case proto.MessageTypeV3.MTV3_POLL_VOTE:
      case proto.MessageTypeV3.MTV3_POLL_VOTE_ANONYMOUS:
      case proto.MessageTypeV3.MTV3_POLL_REVOKE:
      case proto.MessageTypeV3.MTV3_POLL_UPDATE:
      case proto.MessageTypeV3.MTV3_POLL_SNAPSHOT:
        return true;
      default:
        return false;
    }
  }

  /// Test-only accessor for the private user-message classifier.
  /// Used by `test/smoke/smoke_reduced_mode.dart`. Not for production callers —
  /// the gate is enforced inside [handleMessage], not at call sites.
  static bool isUserMessageForTest(proto.MessageTypeV3 type) => _isUserMessage(type);


  /// Sender-side edit window: 15 minutes (UI hides edit button after this).
  static const int _defaultEditWindowMs = 15 * 60 * 1000;

  /// Receiver-side tolerance: accept edits up to 60 min to avoid rejecting
  /// edits from older nodes that still use the previous 60-min default.
  static const int _receiverEditToleranceMs = 60 * 60 * 1000;

  // ── Emoji Reactions (Architecture Section 14.3) ──────────────────────

  /// Send an emoji reaction to a message.
  @override
  Future<void> sendReaction({
    required String conversationId,
    required String messageId,
    required String emoji,
    required bool remove,
  }) async {
    if (_reducedMode) {
      _log.warn('sendReaction blocked: reducedMode active');
      return;
    }
    final conv = conversations[conversationId];
    if (conv == null) return;

    // Apply locally
    ensureLoaded(conversationId);
    final msgIndex = conv.messages.indexWhere((m) => m.id == messageId);
    if (msgIndex >= 0) {
      final msg = conv.messages[msgIndex];
      if (remove) {
        msg.reactions[emoji]?.remove(identity.userIdHex);
        if (msg.reactions[emoji]?.isEmpty ?? false) msg.reactions.remove(emoji);
      } else {
        msg.reactions.putIfAbsent(emoji, () => {});
        msg.reactions[emoji]!.add(identity.userIdHex);
      }
      // BEHIND both branches, not in one: an added reaction
      // belongs in the storage just as much as a removed one. When the call stood
      // only in the `remove` branch, the coverage for the more frequent case was
      // open — and the guard saw it as covered, because it only checks
      // whether storing happens ANYWHERE in the method.
      persistMessage(conversationId, msg);
    }

    // Build reaction payload
    final reaction = proto.EmojiReaction()
      ..messageId = hexToBytes(messageId)
      ..emoji = emoji
      ..remove = remove;
    final basePayload = Uint8List.fromList(reaction.writeToBuffer());

    // V3: pairwise fan-out via sendToUser. The group conversation ID on the
    // wire side moves with C4 groups; until then the reaction lands at the
    // recipient as a DM reaction on his sender tab.
    final group = _groups[conversationId];
    if (group != null) {
      final groupIdBytes = hexToBytes(conversationId);
      final gmEpoch = group.membershipEpoch;
      final gmHash = _computeMembershipHash(gmEpoch, conversationId, group.members);
      for (final member in group.members.values) {
        if (member.nodeIdHex == identity.userIdHex) continue;
        final (x25519Pk, mlKemPk, ed25519Pk) = _resolveMemberKeys(member.nodeIdHex,
            memberX25519Pk: member.x25519Pk, memberMlKemPk: member.mlKemPk, memberEd25519Pk: member.ed25519Pk);
        if (x25519Pk == null || mlKemPk == null) continue;
        await sendToUser(
          recipientUserId: hexToBytes(member.nodeIdHex),
          messageType: proto.MessageTypeV3.MTV3_REACTION,
          payload: basePayload,
          groupId: groupIdBytes,
          groupMembershipEpoch: gmEpoch,
          groupMembershipHash: gmHash,
          recipientX25519PkOverride: x25519Pk,
          recipientMlKemPkOverride: mlKemPk,
          recipientEd25519PkOverride: ed25519Pk,
        );
      }
    } else {
      final contact = _contacts[conversationId];
      if (contact == null ||
          contact.x25519Pk == null ||
          contact.mlKemPk == null) {
        return;
      }
      await sendToUser(
        recipientUserId: contact.nodeId,
        messageType: proto.MessageTypeV3.MTV3_REACTION,
        payload: basePayload,
      );
    }

    if (msgIndex >= 0) {
      onStateChanged?.call();
      _saveConversations();
      // WITHOUT the emoji: it is user content, and "no user content in
      // logs" is an owner decision (02.09.2026). A stand-in
      // does not help here — what diagnostics need is "on which
      // message was a reaction made", and that stands next to it.
      _log.info('Reaction ${remove ? "removed" : "added"} '
          'on ${messageId.substring(0, 8)}');
    } else {
      _log.warn('sendReaction: message ${messageId.substring(0, 8)} not found locally, sent to network only');
    }
  }

  /// Broadcast IDENTITY_DELETED to all accepted contacts before deletion.
  /// V3: per-contact sendToUser fan-out; KEM/Sig handled inside sendToUser.
  /// §7.1 LD-5: only the Primary may delete an identity.
  Future<void> broadcastIdentityDeleted() async {
    if (identity.isLinkedDevice) {
      _log.warn('broadcastIdentityDeleted: blocked — Linked Device cannot delete identity');
      return;
    }
    final notification = proto.IdentityDeletedNotification()
      ..identityEd25519Pk = identity.ed25519PublicKey
      ..deletedAtMs = Int64(DateTime.now().millisecondsSinceEpoch)
      ..displayName = displayName;
    final payload = Uint8List.fromList(notification.writeToBuffer());
    var sent = 0;
    for (final contact in _contacts.values) {
      if (contact.status != 'accepted') continue;
      if (contact.x25519Pk == null || contact.mlKemPk == null) continue;
      try {
        final ok = await sendToUser(
          recipientUserId: contact.nodeId,
          messageType: proto.MessageTypeV3.MTV3_IDENTITY_DELETED,
          payload: payload,
        );
        if (ok) sent++;
      } catch (e) {
        _log.debug('IDENTITY_DELETED send to ${contact.displayName} failed: $e');
      }
    }
    _log.info('IDENTITY_DELETED broadcast sent to $sent contacts');

    // ── AND TO THE OWN DEVICES (E-9, v4_1 §14.7 / §21.5.2) ────────
    //
    // THE FINDING: the loop above runs over `_contacts.values` and
    // never touched `_devices`. A second device of the same identity
    // kept contacts, keys and the whole history INDEFINITELY and
    // never learned that deletion happened.
    //
    // WHY THIS IS SOMETHING DIFFERENT FROM §21.5.2/B-9. There it says deleting is
    // local and at foreign RELAYS ciphertext lies until the deadline — ciphertext
    // without key. On the second phone of THE SAME user lies
    // PLAINTEXT, because this device has the key. Exactly this
    // difference is what someone who deletes means.
    //
    // THE SAME MESSAGE AS FOR THE CONTACTS, no second format: the
    // payload is the same `IdentityDeletedNotification` buffer. Two
    // formats for the same fact would drift apart.
    //
    // `_sendTwinSync` bails out itself at `_devices.length <= 1` — the
    // single-device case thus costs no frame.
    _sendTwinSync(proto.TwinSyncType.TWIN_IDENTITY_DELETED, payload);
    _log.info('TWIN_IDENTITY_DELETED queued for ${_devices.isEmpty ? 0 : _devices.length - 1} '
        'own devices');
  }


  // `firstCrPickDeviceKem(...)` stood here: the §8.1.1 selector that took
  // from the devices resolved by the `IdentityResolver` the one with the
  // freshest device KEM. `ResolvedDevice` came from
  // `lib/core/identity_resolution/`, and the only caller was the
  // first contact branch in the then `sendContactRequest`. HERE UNTIL
  // S361 IT SAID "which today ends at gap G-1"; that had been wrong since S360 —
  // that branch no longer ended, it delivered via the invitation line
  // (§15.3.2).
  //
  // S389: `sendContactRequest` has not existed since S388-BAU-KONTAKT.
  // On V4.2 the request is packet (2) of first contact in mycelium (§15.5);
  // it arises on redeeming an invitation card and leaves the
  // device via the one seam `sendToUser` (§22.5, `mycelium_seam.dart`).
  // This changes nothing about the (T), on the contrary: there are no resolved
  // devices any more to choose from — the card carries the
  // key bundle itself (§15.2).

  // ── Sending ────────────────────────────────────────────────────────

  /// Send a text message to a contact.
  @override
  Future<UiMessage?> sendTextMessage(String recipientUserIdHex, String text, {String? forwardedFrom, String? replyToMessageId, String? replyToText, String? replyToSender}) async {
    if (_reducedMode) {
      _log.warn('sendTextMessage blocked: reducedMode active');
      return null;
    }
    final contact = _contacts[recipientUserIdHex];
    if (contact == null || contact.status != 'accepted') {
      _log.warn('Cannot send to non-accepted contact: $recipientUserIdHex (contact=${contact != null}, status=${contact?.status})');
      return null;
    }

    _maybeWriteStaleContactWarning(recipientUserIdHex);

    // S368: see `_isWireFaehigeNachrichtenkennung`. If the reference falls,
    // it falls on BOTH sides — before building the local message.
    if (replyToMessageId != null &&
        replyToMessageId.isNotEmpty &&
        !_isWireCapableMessageIdentifier(replyToMessageId)) {
      _log.warn('sendTextMessage: replyToMessageId is not a 32-digit '
          'hex identifier — the reply reference is dropped entirely, locally too. On '
          'this line that can only come from a damaged store.');
      replyToMessageId = null;
      replyToText = null;
      replyToSender = null;
    }

    // Optimistic UI msg.id is the wire messageId so DELIVERY_RECEIPT
    // (which carries inner.messageId) can match this local message and
    // upgrade `sent → delivered` in `_handleDeliveryReceiptV3`.
    final messageIdBytes = SodiumFFI().randomBytes(16);
    final messageIdHex = bytesToHex(messageIdBytes);
    final msg = UiMessage(
      id: messageIdHex,
      conversationId: recipientUserIdHex,
      senderNodeIdHex: identity.userIdHex,
      text: text,
      timestamp: DateTime.now(),
      type: UiMessageType.text,
      status: MessageStatus.resting,
      isOutgoing: true,
      forwardedFrom: forwardedFrom,
      replyToMessageId: replyToMessageId,
      replyToText: replyToText,
      replyToSender: replyToSender,
    );
    _addMessageToConversation(recipientUserIdHex, msg);

    // Yield to let UI repaint before heavy crypto work
    await Future.delayed(Duration.zero);

    // V3 sender path: build TextMessageV3 sub-message, hand to sendToUser
    // which does Inner-build/User-Sign/zstd/KEM-encrypt + Outer-build/
    // Device-Sign + per-device fan-out. Reply-fields and the sender-side
    // link-preview are wire-tagged on TextMessageV3 itself.

    // Sender-side link preview: fetched AFTER the message is sent, then
    // delivered as an edit/update so the send path is never blocked by DNS
    // or HTTP timeouts. The receiver-MUST-NOT-fetch invariant (CLAUDE.md)
    // is preserved — the preview still comes from the sender, just async.
    final hasUrl = _linkPreviewSettings.enabled && extractFirstUrl(text) != null;

    final tm = proto.TextMessageV3()
      ..text = text
      ..formatHint = 'plain';
    if (replyToMessageId != null && replyToMessageId.isNotEmpty) {
      // S368: checked above — here `hexToBytes` can no longer throw, and
      // a silent fallback to "locally yes, on the wire no" is no longer
      // possible.
      tm.replyToMessageId = hexToBytes(replyToMessageId);
      if (replyToText != null && replyToText.isNotEmpty) {
        // Bound the snippet so we don't bloat the frame.
        tm.replyToSnippet = replyToText.length > 120
            ? '${replyToText.substring(0, 120)}…'
            : replyToText;
      }
    }
    // Enter the leg in the index BEFORE sending (S393): the mailbox sets
    // `inTransit` synchronously when the packet goes out, and
    // `_myceliumSend` carries that over at once (`_v41ReflectStatus`). Without
    // the entry the display only learned the state after `sendToUser`
    // returned — and a receipt that arrived before that let the ONE tick of
    // §12.2 be skipped (resting -> delivered, `smoke_four_states_run`).
    _v41ApplyOutgoingStatus(msg, <String>[messageIdHex]);
    await sendToUser(
      recipientUserId: contact.nodeId,
      messageType: proto.MessageTypeV3.MTV3_TEXT,
      payload: tm.writeToBuffer(),
      messageId: messageIdBytes,
    );
    statsCollector.addMessageSent();

    // AP-4 (§5.1b/§5.1c K2): here stood the ternary
    //   `sent ? sent : (l3Out[0] ? queuedOffline : failed)`
    // including the comment "sent=true → direct UDP dispatch succeeded".
    // It has been dropped WITHOUT REPLACEMENT, not renamed: its trigger was a
    // successful socket write or a completed L3 placement, and neither
    // is a delivery event in V4.1 any more (v4_1 §22.5.1). The
    // return value of `sendToUser` is therefore no longer read at all.
    //
    // What moves the status now is solely the delivery register (§9.2, D2).
    _v41ApplyOutgoingStatus(msg, <String>[messageIdHex]);
    _saveConversations();
    onStateChanged?.call();

    // Twin-Sync: notify other devices about sent message (§26)
    _sendTwinSync(proto.TwinSyncType.MESSAGE_SENT, Uint8List.fromList(utf8.encode(jsonEncode({
      'conversationId': recipientUserIdHex,
      'text': text,
      // V3: per-device fan-out generates messageIds inside sendToUser; for
      // twin-sync we use the optimistic temp-ID — twin receivers just dedup
      // on (conversationId, text, timestamp) anyway.
      'messageId': msg.id,
      'timestamp': msg.timestamp.millisecondsSinceEpoch,
    }))));

    // Async link-preview fetch: runs AFTER the message is sent so the
    // send path is never blocked by DNS/HTTP timeouts. On success, the
    // local UiMessage is updated and an EDIT envelope patches the preview
    // onto the already-delivered message at the receiver.
    if (hasUrl) {
      unawaited(_fetchAndDeliverLinkPreview(
        recipientUserIdHex, contact, msg, messageIdBytes, text,
      ));
    }

    return msg;
  }

  Future<void> _fetchAndDeliverLinkPreview(
    String recipientUserIdHex,
    ContactInfo contact,
    UiMessage msg,
    Uint8List messageIdBytes,
    String text,
  ) async {
    try {
      final preview = await _linkPreviewFetcher.fetchPreview(text);
      if (preview == null) return;
      msg.linkPreviewUrl = preview.url;
      msg.linkPreviewTitle = preview.title;
      msg.linkPreviewDescription = preview.description;
      msg.linkPreviewSiteName = preview.siteName;
      if (preview.thumbnail != null) {
        msg.linkPreviewThumbnailBase64 = base64Encode(preview.thumbnail!);
      }
      onStateChanged?.call();
      _saveConversations();
    } catch (e) {
      _log.debug('Async link preview fetch failed: $e');
    }
  }

  // `checkExpiredMessages` stood here and called `_checkAndMarkExpired`.
  // Both fell with S390 (§9.3: "There is no timer that expires
  // messages"); the justification stands at the deleted method in
  // `cleona_service_msgstate.dart`.

  /// §9.3: send the message [messageId] once more, after the
  /// user has given up.
  ///
  /// **Only from [MessageStatus.failed]**, because §12.2 offers the
  /// action "again" for exactly this one state. Until S390 it hung
  /// on `expired` — a state that a clock produced; thus the
  /// decision "give up" lay with a timer instead of with the application, and
  /// §9.3 expressly puts it in the application.
  ///
  /// §9.3 on the procedure: "Where a user retries, the message is sent again
  /// under a new identifier; the old one is closed as `failed`." Exactly
  /// that happens here — the old entry is taken out of the conversation
  /// and [sendTextMessage] creates a new one with a new identifier.
  @override
  Future<UiMessage?> resendFailedMessage(
      String conversationId, String messageId) async {
    if (_reducedMode) {
      _log.warn('resendFailedMessage blocked: reducedMode active');
      return null;
    }
    final conv = conversations[conversationId];
    if (conv == null) return null;
    ensureLoaded(conversationId);
    final idx = conv.messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return null;
    final original = conv.messages[idx];
    if (original.status != MessageStatus.failed) return null;
    if (!original.isOutgoing) return null;
    // Take out the abandoned entry, then send anew via the normal path.
    // (S368: here additionally stood `_outbox.remove` — the
    // V3 outbox has fallen, it could never carry the entry anyway.)
    conv.messages.removeAt(idx);
    _saveConversations();
    return sendTextMessage(
      conversationId,
      original.text,
      replyToMessageId: original.replyToMessageId,
      replyToText: original.replyToText,
      replyToSender: original.replyToSender,
    );
  }

  /// Edit a previously sent message.
  @override
  Future<bool> editMessage(String conversationId, String messageId, String newText) async {
    if (_reducedMode) {
      _log.warn('editMessage blocked: reducedMode active');
      return false;
    }
    final conv = conversations[conversationId];
    if (conv == null) return false;

    ensureLoaded(conversationId);
    final msgIndex = conv.messages.indexWhere((m) => m.id == messageId);
    if (msgIndex < 0) return false;

    final original = conv.messages[msgIndex];

    // Only own messages
    if (!original.isOutgoing) return false;

    // Check edit window (per-chat config or default)
    final editWindowMs = conv.config.editWindowMs ?? _defaultEditWindowMs;
    final ageMs = DateTime.now().millisecondsSinceEpoch - original.timestamp.millisecondsSinceEpoch;
    if (ageMs > editWindowMs) {
      _log.warn('Edit rejected: message too old');
      return false;
    }

    // Cannot edit deleted messages
    if (original.isDeleted) return false;

    // Build edit payload (V3: identical sub-message; only the wrapping
    // changes — sendToUser handles compress/KEM/sign per device).
    final editMsg = proto.MessageEdit()
      ..originalMessageId = hexToBytes(messageId)
      ..newText = newText
      ..editTimestamp = Int64(DateTime.now().millisecondsSinceEpoch);
    final basePayload = Uint8List.fromList(editMsg.writeToBuffer());

    // Wire messageId == originalMessageId. Receiver-side dedup is then
    // idempotent (re-applying the same edit is a no-op), and the sender's
    // `_handleDeliveryReceiptV3` lookup can locate the original UiMessage
    // by the receipt's messageId. Status stays at delivered/read (edits
    // mutate an existing bubble; no `sent → delivered` transition required).
    final wireMessageId = hexToBytes(messageId);

    // Group or DM? V3 keeps pairwise fan-out (one sendToUser per member).
    // ApplicationFrameV3.group_id (Field 17) carries the conversation tag so
    // receivers dispatch the EDIT to the matching group/channel tab.
    final group = _groups[conversationId];
    bool anySent = false;

    if (group != null) {
      final groupIdBytes = hexToBytes(conversationId);
      final gmEpoch = group.membershipEpoch;
      final gmHash = _computeMembershipHash(gmEpoch, conversationId, group.members);
      for (final member in group.members.values) {
        if (member.nodeIdHex == identity.userIdHex) continue;
        final (x25519Pk, mlKemPk, ed25519Pk) = _resolveMemberKeys(member.nodeIdHex,
            memberX25519Pk: member.x25519Pk, memberMlKemPk: member.mlKemPk, memberEd25519Pk: member.ed25519Pk);
        if (x25519Pk == null || mlKemPk == null) continue;
        final ok = await sendToUser(
          recipientUserId: hexToBytes(member.nodeIdHex),
          messageType: proto.MessageTypeV3.MTV3_EDIT,
          payload: basePayload,
          groupId: groupIdBytes,
          messageId: wireMessageId,
          groupMembershipEpoch: gmEpoch,
          groupMembershipHash: gmHash,
          recipientX25519PkOverride: x25519Pk,
          recipientMlKemPkOverride: mlKemPk,
          recipientEd25519PkOverride: ed25519Pk,
        );
        if (ok) anySent = true;
      }
    } else {
      final contact = _contacts[conversationId];
      if (contact == null || contact.status != 'accepted') return false;
      final sent = await sendToUser(
        recipientUserId: contact.nodeId,
        messageType: proto.MessageTypeV3.MTV3_EDIT,
        payload: basePayload,
        messageId: wireMessageId,
      );
      if (sent) anySent = true;
    }

    if (anySent) {
      // Apply locally
      original.text = newText;
      original.editedAt = DateTime.now();
      persistMessage(conversationId, original);
      onStateChanged?.call();
      _saveConversations();
      _log.info('Message edited: $messageId');

      // Twin-Sync (§26)
      _sendTwinSync(proto.TwinSyncType.MESSAGE_EDITED, Uint8List.fromList(utf8.encode(jsonEncode({
        'conversationId': conversationId,
        'messageId': messageId,
        'text': newText,
      }))));
    }

    return anySent;
  }

  /// Delete a previously sent message.
  @override
  Future<bool> deleteMessage(String conversationId, String messageId) async {
    if (_reducedMode) {
      _log.warn('deleteMessage blocked: reducedMode active');
      return false;
    }
    final conv = conversations[conversationId];
    if (conv == null) return false;

    ensureLoaded(conversationId);
    final msgIndex = conv.messages.indexWhere((m) => m.id == messageId);
    if (msgIndex < 0) return false;

    final original = conv.messages[msgIndex];

    // Only own messages
    if (!original.isOutgoing) return false;

    // Already deleted
    if (original.isDeleted) return false;

    // §9.5.7 D2 (S119): system-channel posts are deleted via an author-
    // signed RETRACT tombstone that gossips with the record set (a plain
    // MTV3_DELETE could never reach "all subscribers" — there is no
    // member list). Deletion is unbounded (§14.6 — no time window).
    if (SystemChannels.isSystemChannel(conversationId)) {
      final stored = await _publishSystemChannelRecord(
        channelIdHex: conversationId,
        kind: SysChanKind.retract,
        targetRecordId: hexToBytes(messageId),
      );
      if (stored == null) return false;
      // _applySysChanRetract (inside publish) marked the bridged message;
      // legacy pre-D1 local posts share the id and are covered too.
      if (!original.isDeleted) {
        original.text = '';
        original.isDeleted = true;
        // Tombstone, not removal: the message stays in the list
        // and in the storage, its content is gone (§21.5.1).
        persistMessage(conversationId, original);
        _saveConversations();
      }
      onStateChanged?.call();
      _log.info('System-channel post retracted: $messageId');
      return true;
    }

    // Build delete payload (V3 wraps via sendToUser).
    final deleteMsg = proto.MessageDelete()
      ..messageId = hexToBytes(messageId)
      ..deletedAt = Int64(DateTime.now().millisecondsSinceEpoch);
    final basePayload = Uint8List.fromList(deleteMsg.writeToBuffer());

    // Wire messageId == target messageId. Same rationale as `editMessage`:
    // receiver dedup stays idempotent, and the sender's DELIVERY_RECEIPT
    // handler can find the local UiMessage via the receipt's messageId.
    final wireMessageId = hexToBytes(messageId);

    final group = _groups[conversationId];
    bool anySent = false;

    if (group != null) {
      // Pairwise fan-out per member (V3 keeps the same model).
      final groupIdBytes = hexToBytes(conversationId);
      final gmEpoch = group.membershipEpoch;
      final gmHash = _computeMembershipHash(gmEpoch, conversationId, group.members);
      for (final member in group.members.values) {
        if (member.nodeIdHex == identity.userIdHex) continue;
        final (x25519Pk, mlKemPk, ed25519Pk) = _resolveMemberKeys(member.nodeIdHex,
            memberX25519Pk: member.x25519Pk, memberMlKemPk: member.mlKemPk, memberEd25519Pk: member.ed25519Pk);
        if (x25519Pk == null || mlKemPk == null) continue;
        final ok = await sendToUser(
          recipientUserId: hexToBytes(member.nodeIdHex),
          messageType: proto.MessageTypeV3.MTV3_DELETE,
          payload: basePayload,
          groupId: groupIdBytes,
          messageId: wireMessageId,
          groupMembershipEpoch: gmEpoch,
          groupMembershipHash: gmHash,
          recipientX25519PkOverride: x25519Pk,
          recipientMlKemPkOverride: mlKemPk,
          recipientEd25519PkOverride: ed25519Pk,
        );
        if (ok) anySent = true;
      }
    } else {
      final contact = _contacts[conversationId];
      if (contact == null || contact.status != 'accepted') return false;
      final sent = await sendToUser(
        recipientUserId: contact.nodeId,
        messageType: proto.MessageTypeV3.MTV3_DELETE,
        payload: basePayload,
        messageId: wireMessageId,
      );
      if (sent) anySent = true;
    }

    if (anySent) {
      // Apply locally
      original.text = '';
      original.isDeleted = true;
      persistMessage(conversationId, original);
      onStateChanged?.call();
      _saveConversations();
      _log.info('Message deleted: $messageId');

      // Twin-Sync (§26)
      _sendTwinSync(proto.TwinSyncType.MESSAGE_DELETED, Uint8List.fromList(utf8.encode(jsonEncode({
        'conversationId': conversationId,
        'messageId': messageId,
      }))));
    }

    return anySent;
  }

  @override
  Future<bool> updateChatConfig(String conversationId, ChatConfig config) async {
    final conv = conversations[conversationId];
    if (conv == null) return false;

    // For groups: owner or admin can set directly
    final group = _groups[conversationId];
    if (group != null) {
      if (!_hasGroupPermission(group, 'config')) return false;
      conv.config = config;
      _saveConversations();
      // Broadcast config to all group members
      _broadcastGroupConfigUpdate(group, config);
      onStateChanged?.call();
      _log.info('Group chat config updated for "${group.name}"');
      return true;
    }

    // For channels: owner or admin can set directly
    final channel = _channels[conversationId];
    if (channel != null) {
      if (!_hasChannelPermission(channel, 'config')) return false;
      conv.config = config;
      _saveConversations();
      _broadcastChannelConfigUpdate(channel, config);
      onStateChanged?.call();
      _log.info('Channel chat config updated for "${channel.name}"');
      return true;
    }

    // For DMs: send config update proposal to peer — NOT active until accepted
    final contact = _contacts[conversationId];
    if (contact == null || contact.status != 'accepted') return false;

    // Store as pending on our side too (active only after peer accepts)
    conv.pendingConfigProposal = config;
    conv.pendingConfigProposer = identity.userIdHex;
    _saveConversations();

    _sendChatConfigUpdate(contact, conversationId, config, isRequest: true);
    onStateChanged?.call();
    _log.debug('Chat config proposal — displayName="${contact.displayName}"');
    _log.info('Chat config proposal sent');
    return true;
  }

  /// Accept a pending DM config proposal.
  @override
  Future<bool> acceptConfigProposal(String conversationId) async {
    final conv = conversations[conversationId];
    if (conv == null || conv.pendingConfigProposal == null) return false;
    if (conv.isGroup || conv.isChannel) return false; // Groups/Channels don't use proposals

    final proposedConfig = conv.pendingConfigProposal!;

    // Apply the config locally
    conv.config = proposedConfig;
    conv.pendingConfigProposal = null;
    conv.pendingConfigProposer = null;
    _saveConversations();

    // Send acceptance to the proposer
    final contact = _contacts[conversationId];
    if (contact != null && contact.x25519Pk != null && contact.mlKemPk != null) {
      _sendChatConfigUpdate(contact, conversationId, proposedConfig, isRequest: false, accepted: true);
    }

    onStateChanged?.call();
    _log.debug('DM config accepted — displayName="${contact?.displayName}"');
    _log.info('DM config proposal accepted for '
        '${conversationId.substring(0, 8)}');
    return true;
  }

  /// Reject a pending DM config proposal.
  @override
  Future<bool> rejectConfigProposal(String conversationId) async {
    final conv = conversations[conversationId];
    if (conv == null || conv.pendingConfigProposal == null) return false;
    if (conv.isGroup || conv.isChannel) return false;

    final rejectedConfig = conv.pendingConfigProposal!;

    // Clear the pending proposal
    conv.pendingConfigProposal = null;
    conv.pendingConfigProposer = null;
    _saveConversations();

    // Send rejection to the proposer
    final contact = _contacts[conversationId];
    if (contact != null && contact.x25519Pk != null && contact.mlKemPk != null) {
      _sendChatConfigUpdate(contact, conversationId, rejectedConfig, isRequest: false, accepted: false);
    }

    onStateChanged?.call();
    _log.debug('DM config rejected — displayName="${contact?.displayName}"');
    _log.info('DM config proposal rejected for '
        '${conversationId.substring(0, 8)}');
    return true;
  }

  /// Forward a message to another conversation.
  @override
  Future<UiMessage?> forwardMessage(String sourceConversationId, String messageId, String targetConversationId) async {
    if (_reducedMode) {
      _log.warn('forwardMessage blocked: reducedMode active');
      return null;
    }
    // Check allowForwarding on source conversation
    final sourceConv = conversations[sourceConversationId];
    if (sourceConv != null && !sourceConv.config.allowForwarding) {
      _log.warn('Forward blocked: allowForwarding=false for $sourceConversationId');
      return null;
    }

    // Find the original message
    ensureLoaded(sourceConversationId);
    final msg = sourceConv?.messages.where((m) => m.id == messageId).firstOrNull;
    if (msg == null || msg.isDeleted) return null;

    // Determine original sender name for attribution
    final originalSenderName = msg.isOutgoing
        ? displayName
        : (_contacts[msg.senderNodeIdHex]?.effectiveName ?? msg.senderNodeIdHex.substring(0, 8));

    // Check if this is a media message
    if (msg.isMedia) {
      if (msg.filePath != null &&
          MediaStore.instance.existsEitherWay(msg.filePath!)) {
        final result = await sendMediaMessage(targetConversationId, msg.filePath!);
        if (result != null) {
          result.forwardedFrom = originalSenderName;
          _saveConversations();
        }
        return result;
      }
      // Media not locally available — don't degrade to text
      _log.warn('forwardMessage: media file not available locally for ${messageId.substring(0, 8)}');
      return null;
    }

    // Text-only forward
    final forwardText = msg.text;

    // Send to target with forwardedFrom attribution
    final isGroupTarget = _groups.containsKey(targetConversationId);
    final isChannelTarget = _channels.containsKey(targetConversationId);
    UiMessage? result;
    if (isChannelTarget) {
      result = await sendChannelPost(targetConversationId, forwardText);
      if (result != null) {
        result.forwardedFrom = originalSenderName;
        _saveConversations();
      }
    } else if (isGroupTarget) {
      result = await sendGroupTextMessage(targetConversationId, forwardText);
      if (result != null) {
        result.forwardedFrom = originalSenderName;
        _saveConversations();
      }
    } else {
      result = await sendTextMessage(targetConversationId, forwardText, forwardedFrom: originalSenderName);
    }

    return result;
  }

  /// Send a CHAT_CONFIG_UPDATE message to a contact (V3).
  void _sendChatConfigUpdate(ContactInfo contact, String conversationId,
      ChatConfig config,
      {required bool isRequest, bool accepted = false, String? groupIdHex}) {
    final configMsg = proto.ChatConfigUpdate()
      ..conversationId = conversationId
      ..allowDownloads = config.allowDownloads
      ..allowForwarding = config.allowForwarding
      ..readReceipts = config.readReceipts
      ..typingIndicators = config.typingIndicators
      ..isRequest = isRequest
      ..accepted = accepted;
    if (config.editWindowMs != null) {
      configMsg.editWindowMs = Int64(config.editWindowMs!);
    }
    if (config.expiryDurationMs != null) {
      configMsg.expiryDurationMs = Int64(config.expiryDurationMs!);
    }
    _detachedSend('MTV3_CHAT_CONFIG_UPDATE', sendToUser(
      recipientUserId: contact.nodeId,
      messageType: proto.MessageTypeV3.MTV3_CHAT_CONFIG_UPDATE,
      payload: Uint8List.fromList(configMsg.writeToBuffer()),
      groupId: groupIdHex != null ? hexToBytes(groupIdHex) : null,
    ));
  }

  /// Resolve best available encryption keys for a group/channel member.
  /// Prefers contact keys (most up-to-date), falls back to member keys.
  /// Returns (x25519Pk, mlKemPk, ed25519Pk) — the third element is the
  /// Ed25519 public key for L3 mailbox anchoring (S&F/Erasure).
  (Uint8List?, Uint8List?, Uint8List?) _resolveMemberKeys(String nodeIdHex, {Uint8List? memberX25519Pk, Uint8List? memberMlKemPk, Uint8List? memberEd25519Pk}) {
    final contact = _contacts[nodeIdHex];
    if (contact != null && contact.x25519Pk != null && contact.mlKemPk != null) {
      return (contact.x25519Pk!, contact.mlKemPk!, contact.ed25519Pk);
    }
    if (memberX25519Pk != null && memberX25519Pk.isNotEmpty &&
        memberMlKemPk != null && memberMlKemPk.isNotEmpty) {
      return (memberX25519Pk, memberMlKemPk, memberEd25519Pk);
    }
    return (null, null, null);
  }

  /// Broadcast a config update to all group members (pairwise KEM).
  void _broadcastGroupConfigUpdate(GroupInfo group, ChatConfig config) {
    final configMsg = proto.ChatConfigUpdate()
      ..conversationId = group.groupIdHex
      ..allowDownloads = config.allowDownloads
      ..allowForwarding = config.allowForwarding
      ..readReceipts = config.readReceipts
      ..typingIndicators = config.typingIndicators
      ..isRequest = false
      ..accepted = false;
    if (config.editWindowMs != null) {
      configMsg.editWindowMs = Int64(config.editWindowMs!);
    }
    if (config.expiryDurationMs != null) {
      configMsg.expiryDurationMs = Int64(config.expiryDurationMs!);
    }
    final configPayload = Uint8List.fromList(configMsg.writeToBuffer());
    for (final member in group.members.values) {
      if (member.nodeIdHex == identity.userIdHex) continue;
      final (x25519Pk, mlKemPk, ed25519Pk) = _resolveMemberKeys(member.nodeIdHex,
          memberX25519Pk: member.x25519Pk, memberMlKemPk: member.mlKemPk, memberEd25519Pk: member.ed25519Pk);
      if (x25519Pk == null || mlKemPk == null) continue;
      _detachedSend('MTV3_CHAT_CONFIG_UPDATE', sendToUser(
        recipientUserId: hexToBytes(member.nodeIdHex),
        messageType: proto.MessageTypeV3.MTV3_CHAT_CONFIG_UPDATE,
        payload: configPayload,
        groupId: hexToBytes(group.groupIdHex),
        recipientX25519PkOverride: x25519Pk,
        recipientMlKemPkOverride: mlKemPk,
        recipientEd25519PkOverride: ed25519Pk,
      ));
    }
    _log.info('Broadcast config update for "${group.name}" to ${group.members.length - 1} members');
  }

  /// Broadcast a config update to all channel members (pairwise KEM).
  void _broadcastChannelConfigUpdate(ChannelInfo channel, ChatConfig config) {
    final configMsg = proto.ChatConfigUpdate()
      ..conversationId = channel.channelIdHex
      ..allowDownloads = config.allowDownloads
      ..allowForwarding = config.allowForwarding
      ..readReceipts = config.readReceipts
      ..typingIndicators = config.typingIndicators
      ..isRequest = false
      ..accepted = false;
    if (config.editWindowMs != null) {
      configMsg.editWindowMs = Int64(config.editWindowMs!);
    }
    if (config.expiryDurationMs != null) {
      configMsg.expiryDurationMs = Int64(config.expiryDurationMs!);
    }
    final configPayload = Uint8List.fromList(configMsg.writeToBuffer());
    for (final member in channel.members.values) {
      if (member.nodeIdHex == identity.userIdHex) continue;
      final (x25519Pk, mlKemPk, ed25519Pk) = _resolveMemberKeys(member.nodeIdHex,
          memberX25519Pk: member.x25519Pk, memberMlKemPk: member.mlKemPk, memberEd25519Pk: member.ed25519Pk);
      if (x25519Pk == null || mlKemPk == null) continue;
      _detachedSend('MTV3_CHAT_CONFIG_UPDATE', sendToUser(
        recipientUserId: hexToBytes(member.nodeIdHex),
        messageType: proto.MessageTypeV3.MTV3_CHAT_CONFIG_UPDATE,
        payload: configPayload,
        groupId: hexToBytes(channel.channelIdHex),
        recipientX25519PkOverride: x25519Pk,
        recipientMlKemPkOverride: mlKemPk,
        recipientEd25519PkOverride: ed25519Pk,
      ));
    }
    _log.info('Broadcast config update for channel "${channel.name}" to ${channel.members.length - 1} members');
  }

  // ── FIVE V3 STORAGE CONSTANTS: FALLEN (CUT) ──────────────────────
  //
  // `_pendingFragmentStoreAcks`, `_l3SizeThresholdBytes` (10 KB —
  // below S&F, above Reed-Solomon), `_pendingPeerStoreAcks`,
  // `_peerStoreAckTimeout` and `_safTargetCopies` (three confirmed
  // copies). They exclusively described the layer 3 cascade, and that
  // no longer exists: V4.1 stores with the responsible relays of the
  // tag line (§9.1), with `m x R` as the redundancy measure instead of three copies.

  /// Add peers from a scanned ContactSeed QR code to the routing table.
  /// This ensures the target node and its seed peers are reachable before sending a CR.
  ///
  /// Welle 5/6 (§8.1.1): when [targetDeviceIdHex] + Device-KEM keys are
  /// supplied (newer ContactSeed-URIs include them), the target peer is
  /// indexed by its Device-Node-ID instead of User-ID, and a direct
  /// DV-route is registered. This is what unblocks `sendToDevice` for the
  /// First-CR InfraFrame — without it, `cascade exhausted (routes=0)`
  /// because DV-routing keys on Device-IDs while legacy seeds added the
  /// peer under the User-ID. [targetDxkB64] / [targetDmkB64] (v1 legacy)
  /// or [targetEpB64] (v2 rev3 trust-anchor) from ContactSeed.
  @override
  void addPeersFromContactSeed(
    String targetNodeIdHex,
    List<String> targetAddresses,
    List<({String nodeIdHex, List<String> addresses})> seedPeers, {
    String? targetDeviceIdHex,
    String? targetDxkB64,
    String? targetDmkB64,
    String? targetEpB64,
    String? targetRendezvousNonceB64,
  }) {
    // ── THE V3 HALF OF THIS METHOD HAS FALLEN (CUT) ─────────────
    //
    // Here stood the takeover into `node.routingTable`: register the target node under
    // its device identifier, prime `DeviceKemRecord` from
    // `dxk`/`dmk` into the DHT cache, register seed peers as
    // DV neighbours, choose the default gateway and ping
    // everything. Five V3 subsystems (routing table, 2D DHT,
    // distance vector, NAT ping) — none of them exists any more.
    //
    // The V4.1 half below STAYS and has been the actual
    // purpose of this method since S356.
    final hasDeviceId =
        targetDeviceIdHex != null && targetDeviceIdHex.isNotEmpty;
    // §5.5b: the seed identifiers continue to be noted at the contact. They
    // cost nothing and are the only trace from which it can later be
    // reconstructed which ContactSeed brought this contact.
    _recordContactSeedPeerIds(targetNodeIdHex,
        seedPeers.map((sp) => sp.nodeIdHex).toList(growable: false));
    _log.info('QR seed: target ${targetNodeIdHex.substring(0, 8)}'
        '${hasDeviceId ? " (Geraet ${targetDeviceIdHex.substring(0, 8)})" : ""}'
        ', ${targetAddresses.length} address(es), ${seedPeers.length} '
        'seed peer(s) — only the V4.1 entry is taken over.');

    // ── AND THE SAME ADDRESSES FOR THE V4.1 ENTRY (§11.3 line C) ──
    //
    // Until S356 a read-in ContactSeed ended EXCLUSIVELY in
    // `node.routingTable` — i.e. in V3. The V4.1 entry cascade saw
    // nothing of it: `v41.entries.remember` knew exactly three origins
    // (`extern`, `lan`, `partner/*`), and `person` was none of them.
    //
    // That is the path that §11.3 calls "always, and it is the normal way in"
    // and §15 fixes as "the peer list handed over in the process becomes
    // **entry hints** and serves exclusively the network entry".
    // It had no effect whatsoever on the V4.1 line — a user who
    // scans a QR code to get in thereby only helped the layer
    // that this migration removes.
    //
    // THEY ARE ADDRESSES, NOT RECORDS. From `ip:port` no
    // signed `EntryRecord` can be built, and that should stay so — the
    // hint only says WHERE one can ask; the record is issued by the
    // peer, and it verifies itself on arrival. A
    // slipped-in hint costs at most one request into the void.
    //
    // NODE-WIDE, not per identity: the V4.1 node runs once per
    // process (§3.1, `L_node` belongs to the node). Hence the shared
    // store instead of a field at this service.
    final v41Hints = personEntryHints.add([
      ...targetAddresses,
      for (final sp in seedPeers) ...sp.addresses,
    ]);
    if (v41Hints > 0) {
      _log.info('V4.1 entry: $v41Hints hint(s) from the ContactSeed '
          'adopted (§11.3 step „human")');
    }

    // S388: here an `r` nonce started the scanner session of the
    // first contact rendezvous (§4.11.10). Removed (justification at the
    // field block above); [targetRendezvousNonceB64] has not been read
    // since. The parameter falls with the V3 ContactSeed reader
    // (owner decision 15.09.2026, point 17), not here.
  }

  /// §5.5b: seed-peer node-IDs of the most recently scanned ContactSeed,
  /// keyed by target user-ID (lowercase hex). Bridges the window in which the
  /// contact record does not exist yet: `addPeersFromContactSeed` runs BEFORE
  /// the `pending_outgoing` ContactInfo exists, so the list cannot be written
  /// to the contact at scan time. It is flushed onto the contact by
  /// [_seedPeerIdsForTarget] when that record appears.
  ///
  /// S389: the caller `sendContactRequest` formerly named here has been
  /// dropped (S388-BAU-KONTAKT). On V4.2 the `pending_outgoing` arises
  /// on redeeming an invitation card (§15.5), and the request goes out via
  /// `sendToUser` (§22.5). The order — first addresses, then
  /// contact record — has stayed the same; only the second step is called
  /// differently.
  final Map<String, List<String>> _pendingSeedPeerIdsHex = {};

  /// §5.5b: persist the seed peers of a freshly scanned ContactSeed at the
  /// target's contact record (or park them until that record exists).
  void _recordContactSeedPeerIds(
      String targetUserIdHex, List<String> seedIdsHex) {
    if (seedIdsHex.isEmpty) return;
    final key = targetUserIdHex.toLowerCase();
    final ids = seedIdsHex.toSet().toList();
    _pendingSeedPeerIdsHex[key] = ids;
    final contact = _contacts[targetUserIdHex] ?? _contacts[key];
    if (contact != null) {
      // Re-scan of a known contact: a fresh ContactSeed REPLACES the previous
      // seed list. The generator picked these from its current routing table
      // (freshness < 30 min per §5.5b); the older ones may be long gone.
      contact.seedPeerIdsHex = List<String>.from(ids);
      _saveContacts();
    }
    _log.info('§5.5b: recorded ${ids.length} ContactSeed seed peer(s) for '
        '${key.substring(0, 8)}'
        '${contact != null ? " (persisted)" : " (pending contact creation)"}');
  }

  // `_seedPeerIdsForTarget(...)` stood here: the seed peers on which the
  // first-CR fanout was allowed to store a first request (§5.5b). Its only
  // reader was this fanout. The identifiers themselves continue to be noted at the
  // contact ([_recordContactSeedPeerIds]).
  //
  // HERE UNTIL S361 IT SAID "(gap G-1)". That was a confusion of
  // cause and time: the fanout fell with §5.5b and the
  // routing table, not with the first contact carrier — and first contact
  // has stood since S360 (§15.3.2). V4.1 stores first requests with the
  // responsible relays of the tag line (§9.1), not with seed peers.

  // `notifyContactSeedUriShared` (owner session) and
  // `_onFcEndpointResolved` (result after `personEntryHints`) stood
  // here — the first contact rendezvous, removed in S388 (justification at the
  // field block above).

  // `_parseAddrString` stood here — the parser for "ip:port" or
  // "[v6]:port". Its last reader was the V3 half of
  // [addPeersFromContactSeed]; the V4.1 half passes the strings
  // unparsed to `personEntryHints`, which checks them itself.


  // ── Manual Peer Entry (Architecture Section 2.3.4) ──────────────────

  /// Add a peer by IP:port. Sends a PING to verify reachability.
  ///
  /// This is the "Manual Peer Entry" fallback for advanced users and debugging
  /// (§4.5). It is **asynchronous by nature**: nothing is added to the routing
  /// table by this call, and a DHT_PING is normally not sent either, because
  /// an `InfrastructureFrameV3` needs a recipient deviceId that a bare
  /// `ip:port` does not supply. What this call does is send plaintext
  /// discovery probes. **HISTORIC from 2026-08-31 (CUT):** here it said
  /// "Registration happens later, when the target answers:
  /// `CleonaNode._onDiscoveryReceived` creates the `PeerInfo` and fires the
  /// ping from there." Both subjects — `CleonaNode` and `PeerInfo` —
  /// are deleted; there is no registration any more on which this call
  /// could hang.
  ///
  /// The previous doc claimed "the peer is added to the routing table and
  /// pinged" — measured 2026-07-28, neither half held at call time:
  /// `routingTablePeers` was unchanged and `_sendPing` skipped.
  ///
  /// Returns true if at least one probe was emitted — NOT that the peer was
  /// reached, added, or pinged.
  @override
  bool addManualPeer(String ip, int port) {
    if (ip.isEmpty || port <= 0 || port > 65535) {
      _log.warn('addManualPeer: invalid address $ip:$port');
      return false;
    }

    // ── V4.1: A MANUAL PEER IS AN ENTRY HINT ─────────────
    //
    // FORMERLY two V3 paths stood here side by side: a 38-byte
    // unicast probe to the LAN discovery port (41338) via
    // `node.localDiscovery`, and a `DHT_PING` to the data port via
    // `node.sendPing`. Both subsystems fell with `lib/core/network/`.
    //
    // The V4.1 subject is the same as with the ContactSeed and the
    // rendezvous: §11.3 names an address at which one can ask,
    // a HINT, and the entry store of the node collects them.
    // The entry cascade asks there on its own tick; it
    // needs no probe from this place, and a probe would
    // anyway be a second path to the same thing.
    //
    // WHAT THE RETURN VALUE MEANS NOW: "the hint is in the store",
    // not "a probe is out". The doc comment above already said
    // expressly before that it does NOT mean reachability.
    final fresh = personEntryHints.add([
      ip.contains(':') ? '[$ip]:$port' : '$ip:$port',
    ]);
    _log.info('Manueller Peer $ip:$port — '
        '${fresh > 0 ? "neu im" : "schon im"} V4.1-Eintrittsvorrat (§11.3)');
    return true;
  }

  // ── Peer Rescue Bundle (§8.1.2) ──────────────────────────────────────────

  @override
  Future<Map<String, dynamic>?> exportPeerBundle() async {
    final summaries = peerSummaries;
    final inbound = summaries.where((p) => p.allAddresses.any(_isPublicAddress)).toList();
    final others = summaries.where((p) => !p.allAddresses.any(_isPublicAddress)).toList();
    final selected = <RescuePeer>[];
    for (final p in [...inbound, ...others].take(PeerRescueBundle.maxPeers)) {
      final nodeId = _hexToBytes32(p.nodeIdHex);
      if (nodeId == null) continue;
      selected.add(RescuePeer(nodeId: nodeId, addresses: p.allAddresses));
    }

    final bundle = PeerRescueBundle.build(
      exporterDeviceId: identity.deviceNodeId,
      exporterEd25519Sk: identity.ed25519SecretKey,
      peers: selected,
    );

    final bytes = bundle.toBytes();
    final uri = bundle.toUri();

    return {
      'bundleBase64': base64.encode(bytes),
      'uri': uri,
      'peerCount': selected.length,
      'createdAtMs': bundle.createdAt.millisecondsSinceEpoch,
    };
  }

  @override
  Future<Map<String, dynamic>> importPeerBundle({String? uri, String? bundleBase64}) async {
    assert(uri != null || bundleBase64 != null);

    PeerRescueBundleParseResult result;
    if (uri != null) {
      result = PeerRescueBundle.parseUriAndValidate(uri);
    } else {
      final bytes = base64.decode(bundleBase64!);
      result = PeerRescueBundle.parseAndValidate(bytes);
    }

    if (!result.networkTagValid) {
      return {
        'networkTagValid': false,
        'error': result.errorMessage ?? 'Network tag mismatch',
      };
    }

    final bundle = result.bundle!;
    var contacted = 0;
    for (final peer in bundle.peers) {
      for (final addr in peer.addresses) {
        final parts = _splitHostPort(addr);
        if (parts != null) {
          addManualPeer(parts.$1, parts.$2);
          contacted++;
        }
      }
    }

    unawaited(onNetworkChanged(force: true));

    return {
      'networkTagValid': true,
      'sigValid': result.sigValid,
      'sigUnknownExporter': result.sigUnknownExporter,
      'ageHours': result.ageHours,
      'peerCount': bundle.peers.length,
      'peersContacted': contacted,
      'exporterDeviceIdHex': bytesToHex(bundle.exporterDeviceId),
      'createdAtMs': bundle.createdAt.millisecondsSinceEpoch,
    };
  }

  static bool _isPublicAddress(String addr) {
    final h = _splitHostPort(addr);
    if (h == null) return false;
    final ip = h.$1;
    if (ip == '127.0.0.1' || ip == '::1') return false;
    if (ip.startsWith('10.')) return false;
    if (ip.startsWith('192.168.')) return false;
    final parts = ip.split('.');
    if (parts.length == 4) {
      final b1 = int.tryParse(parts[0]) ?? 0;
      final b2 = int.tryParse(parts[1]) ?? 0;
      if (b1 == 172 && b2 >= 16 && b2 <= 31) return false;
      if (b1 == 169 && b2 == 254) return false;
    }
    if (ip.startsWith('fe80:') || ip.startsWith('fc') || ip.startsWith('fd')) return false;
    return true;
  }

  static (String, int)? _splitHostPort(String addr) {
    try {
      if (addr.startsWith('[')) {
        final closeBracket = addr.indexOf(']');
        if (closeBracket < 0) return null;
        final ip = addr.substring(1, closeBracket);
        final rest = addr.substring(closeBracket + 1);
        if (!rest.startsWith(':')) return null;
        final port = int.tryParse(rest.substring(1));
        if (port == null || port <= 0 || port > 65535) return null;
        return (ip, port);
      } else {
        final lastColon = addr.lastIndexOf(':');
        if (lastColon < 0) return null;
        final ip = addr.substring(0, lastColon);
        final port = int.tryParse(addr.substring(lastColon + 1));
        if (port == null || port <= 0 || port > 65535) return null;
        return (ip, port);
      }
    } catch (_) {
      return null;
    }
  }

  static Uint8List? _hexToBytes32(String hex) {
    if (hex.length != 64) return null;
    try {
      return hexToBytes(hex);
    } catch (_) {
      return null;
    }
  }

  // ── `sendContactRequest` HAS BEEN DROPPED (S388-BAU-KONTAKT, B-1 = A) ──
  //
  // On V4.2 the contact request is packet (2) of first contact in mycelium
  // (§15.5): name and greeting are carried by the introduction, the acceptance follows from
  // the response (3), the profile picture from PROFILE_UPDATE (§15.8). The
  // app message CONTACT_REQUEST, which until S388 went after the acceptance,
  // was answered by the inviter a second time — measured: two
  // CONTACT_REQUEST_RESPONSE per acceptance. The V4.1 branches (invitation line,
  // pair key) were dead as long as a mailbox hangs (l. 4073 old).

  // ── §8.1.1 rev3 Deferred Key Exchange (step 1b) ─────────────────────────
  //
  // v2 ContactSeeds carry only the 32-byte `ep` (userEd25519Pk) trust-anchor,
  // not the 1216-byte Device-KEM-PK pair. When the primary DHT resolution
  // (step 1a) misses — which it always does for a fresh first contact between
  // two isolated networks whose 2D-DHT has not converged — the sender asks the
  // recipient directly for its Device-KEM-PK via a plaintext BOOT
  // DEVICE_KEM_REQUEST. The recipient answers with a DEVICE_KEM_OFFER signed by
  // its user Ed25519 key, which the sender verifies against `ep`. Closed-Network
  // HMAC + Outer Device-Sig (BOOT path) and this `ep`-anchored inner signature
  // carry the security properties; the request/offer themselves cannot be
  // KEM-encrypted because the KEM-PK is precisely what they are discovering.

  // ── DEFERRED KEY EXCHANGE (§8.1.1 rev3, step 1b): FALLEN ───────
  //
  // Three state stores (`_lastKemRequestSent`, `_dkeCompleters`,
  // `_kemRequestTimes`) and the canonical signature input
  // `_kemOfferSigInput`. They belonged to `DEVICE_KEM_REQUEST`/`OFFER` —
  // the plaintext infrastructure frame with which a requester asked for the
  // device KEM key of the peer when the ContactSeed
  // did not carry it. Their producers and consumers lay in
  // `cleona_service_v3_dke.dart` and fell along; the caller was
  // the first contact branch.
  //
  // HERE UNTIL S361 IT SAID "(gap G-1)" — as if first contact bore the
  // blame for the removal. It does not: `DEVICE_KEM_REQUEST`/`OFFER` was
  // a PLAINTEXT infrastructure frame and falls with the CUT, and
  // first contact has not needed it since S360 either — it draws its
  // secret from `ki`/`ep` in the ContactSeed, not from a query
  // to the peer. (T), not a gap.

  /// §15.4: "he … **revokes the QR invitation himself after the first
  /// acceptance**."
  ///
  /// ── WHY AT THIS PLACE AND AT NO EARLIER ONE ──────────────────
  ///
  /// §15.4 ties the revocation to the ACCEPTANCE, not to the arrival, and
  /// the difference is not formal: a refused request must not burn the
  /// invitation, otherwise the photographer with his
  /// request locks out the one for whom the code was shown. `accepted`
  /// is the only state in which §15.4 "first acceptance" is fulfilled,
  /// and this method is the only place that sets it.
  ///
  /// On the self-acceptance path (§15.4, QR/NFC) arrival and acceptance coincide
  /// in the same move; on all other paths minutes or
  /// a restart lie in between — that is why the contact record carries the
  /// assignment persistently ([ContactInfo.viaInviteIndex]).
  ///
  /// ── WHAT IT COSTS IF IT DOES NOT HAPPEN ───────────────────────────
  ///
  /// Until S361 `consumeSingleUse` was **never** called in `lib/`. Thus
  /// the only defence from §15.4 against photographing a
  /// displayed QR code was missing: the line stayed armed until `exp` (default 90 days),
  /// and every holder of the photo could store on it. The
  /// UI promised the defence verbatim the whole time
  /// (`invite_qr_single_use`).
  ///
  /// ── THREE THINGS THAT BELONG TOGETHER HERE ───────────────────────────
  ///
  /// 1. **Consume** — `consumeSingleUse` revokes; `isHarvestedAt`
  ///    then says `false` (§15.3.3: "remove the entry from the
  ///    expectation set, drop the harvest, done").
  /// 2. **Write** — without `inviteStore.save` the invitation would be
  ///    armed again after the next start. The same argument as with
  ///    [issueInvitation], only the other way round.
  /// 3. **Withdraw** — [armV41InviteLines] forgets the
  ///    pseudo-peer and the standing seal secret. Without this
  ///    call the line would keep running until the next tick; it would
  ///    thus keep running while the user has already put the code away.
  ///
  /// Called multiple times it is a no-op: an already revoked
  /// invitation is not written again. `acceptContactRequest` runs
  /// through the same record more often on re-contact.
  void _consumeSingleUseInvitation(ContactInfo contact) {
    final idx = contact.viaInviteIndex;
    if (idx == null) return;
    final gen = contact.viaInviteGeneration;
    final InviteLedger book;
    try {
      book = inviteLedger;
    } catch (e) {
      // An unreadable book must not prevent the acceptance — the
      // contact already stands. But it is a finding: this invitation
      // stays armed.
      _log.error('§15.4: invitation book not readable ($e) — the invitation '
          'i=$idx can NOT be consumed and stays open');
      return;
    }
    final rec = book.byIndex(idx, generation: gen);
    if (rec == null || !rec.singleUse || rec.revoked) return;
    if (!book.consumeSingleUse(idx, DateTime.now(), generation: gen)) return;
    // `consumeSingleUse` changes EXACTLY this record — so exactly
    // it is written too (S366). Point 2 of the paragraph above applies
    // unchanged: without this write the invitation would be armed again after the
    // next start.
    inviteStore.persistRecord(book, rec);
    final lines = armV41InviteLines();
    // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
    _log.debug('§15.4 REDEEMED: invitation i=$idx g=${rec.generation}'
        '${rec.label.isEmpty ? '' : ' "${rec.label}"'} is used up with the acceptance '
        'by ${contact.displayName} and revoked — still '
        '$lines invitation line(s) armed');
  }

  /// Accept a pending (or re-) contact request.
  @override
  Future<bool> acceptContactRequest(String nodeIdHex) async {
    final contact = _contacts[nodeIdHex];
    if (contact == null) return false;
    // Only a waiting question can be accepted (§12.5). Until S388
    // 'accepted' (re-contact response), 'pending_outgoing' and
    // 'storedForDelivery' (silent acceptance of mutual requests) were added —
    // their only caller was `_handleContactRequestV3` (S388-BAU-KONTAKT).
    if (contact.status != 'pending') return false;

    // ── V4.2 §12.5: THE DECISION IN mycelium, BEFORE EVERYTHING ELSE (S388) ──
    //
    // Only the acceptance teaches the mailbox the way to the requester
    // (`Mailbox.requestAccepted`), and only it ends his joining.
    // Hence before the CONTACT_REQUEST_RESPONSE. `false` means mycelium could
    // no longer accept (single-use invitation consumed in the meantime) — then
    // the contact stays as it is, instead of sending a response to someone
    // the mailbox does not know.
    if (_myceliumRequestDecide(contact, accept: true) == false) {
      _log.warn('acceptContactRequest ${nodeIdHex.substring(0, 8)}: mycelium '
          'did not accept the request (invitation consumed) — nothing sent');
      return false;
    }

    contact.status = 'accepted';
    contact.acceptedAt ??= DateTime.now();
    _crRetryCountPerContact.remove(nodeIdHex);
    _staleWarningWrittenFor.remove(nodeIdHex);
    contact.lastAckedAt = DateTime.now();
    _saveContacts();

    // §15.4 — HERE the consumption of the single-use invitation happens. Justification
    // and costs stand at [_consumeSingleUseInvitation].
    _consumeSingleUseInvitation(contact);
    // A newly-accepted contact may carry a birthday set locally; refresh.
    _syncCalendarBirthdays();

    // Create conversation with system message so the contact appears
    // immediately in the "Aktuell" tab after acceptance.
    if (!conversations.containsKey(nodeIdHex)) {
      for (final entry in _contacts.entries) {
        if (entry.key == nodeIdHex) continue;
        if (entry.value.status != 'accepted') continue;
        if (entry.value.displayName == contact.displayName) {
          // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
          _log.debug('DUPLICATE-CONTACT-DIAG: acceptContactRequest creating conversation for '
              '"${contact.displayName}" userId=${nodeIdHex.substring(0, 16)} '
              'but accepted contact with SAME displayName already exists at '
              'userId=${entry.key.substring(0, 16)}');
        }
      }
      _addSystemMessage(nodeIdHex, 'Contact request from ${contact.displayName} accepted.',
          type: UiMessageType.identityDeleted); // system message type
      _saveConversations();
    }

    // On V4.2 THIS is the one decision point (§12.5); the decision
    // in mycelium has already been made above (`_myceliumRequestDecide`, S388).
    final resp = proto.ContactRequestResponse()
      ..accepted = true
      ..ed25519PublicKey = identity.ed25519PublicKey
      ..mlDsaPublicKey = identity.mlDsaPublicKey
      ..x25519PublicKey = identity.x25519PublicKey
      ..mlKemPublicKey = identity.mlKemPublicKey
      ..displayName = displayName;
    if (_profilePictureBase64 != null) {
      resp.profilePicture = base64Decode(_profilePictureBase64!);
    }

    onContactAccepted?.call(nodeIdHex);
    onStateChanged?.call();

    // V3 (Architecture §23.3): at this point we know the recipient's KEM
    // pubkeys (received with the incoming CR and stored on the contact
    // record), so the response goes through sendToUser. A CR_RESPONSE
    // without KEM pubkeys cannot reach a V3 receiver, so we drop with a
    // warning rather than emit something the receiver cannot decap.
    bool sent;
    if (contact.x25519Pk != null && contact.mlKemPk != null) {
      sent = await sendToUser(
        recipientUserId: contact.nodeId,
        messageType: proto.MessageTypeV3.MTV3_CONTACT_REQUEST_RESPONSE,
        payload: Uint8List.fromList(resp.writeToBuffer()),
      );
      // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
      _log.debug('CR ACCEPTED ${contact.displayName} (${nodeIdHex.substring(0, 8)}) — response sent ok=$sent');
    } else {
      sent = false;
      _log.warn('CONTACT_REQUEST_RESPONSE drop: contact ${nodeIdHex.substring(0, 8)} '
          'has no KEM pubkeys — CR-handshake incomplete');
    }

    // If we rotated KEM keys recently, the CR_RESPONSE above already carries
    // our current public keys. But as defence-in-depth, also send a dedicated
    // KEY_ROTATION_BROADCAST so the contact updates even if the CR_RESPONSE
    // was lost or couldn't be decrypted (e.g. stale device-KEM on their side).
    if (identity.previousX25519Sk != null &&
        contact.x25519Pk != null && contact.mlKemPk != null) {
      final rotationMsg = proto.KeyRotation()
        ..newX25519Pk = identity.x25519PublicKey
        ..newMlKemPk = identity.mlKemPublicKey
        ..rotationTimestamp = Int64(DateTime.now().millisecondsSinceEpoch);
      final dataToSign = rotationMsg.writeToBuffer();
      rotationMsg.signature = SodiumFFI().signEd25519(
          dataToSign, identity.ed25519SecretKey);
      _detachedSend('MTV3_KEY_ROTATION_BROADCAST', sendToUser(
        recipientUserId: contact.nodeId,
        messageType: proto.MessageTypeV3.MTV3_KEY_ROTATION_BROADCAST,
        payload: Uint8List.fromList(rotationMsg.writeToBuffer()),
      ));
      // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
      _log.debug('Sent KEY_ROTATION_BROADCAST to newly accepted '
          '${contact.displayName} (${nodeIdHex.substring(0, 8)}) — '
          'rotation pending');
    }

    // Twin-Sync: notify other devices about accepted contact (§26)
    _sendTwinSync(proto.TwinSyncType.CONTACT_ADDED, Uint8List.fromList(utf8.encode(jsonEncode({
      'nodeId': nodeIdHex,
      'displayName': contact.displayName,
      if (contact.ed25519Pk != null) 'ed25519Pk': bytesToHex(contact.ed25519Pk!),
      if (contact.x25519Pk != null) 'x25519Pk': bytesToHex(contact.x25519Pk!),
      if (contact.mlKemPk != null) 'mlKemPk': bytesToHex(contact.mlKemPk!),
      if (contact.mlDsaPk != null) 'mlDsaPk': bytesToHex(contact.mlDsaPk!),
      // §15.2: the founding anchor MUST travel along. The twin cannot
      // reconstruct it from anything — it would only see `ed25519Pk`, i.e. the
      // respective current key, and would compute for the same
      // human a different `K_AB` than this device. Two devices
      // of the same user would talk past the same tag line.
      if (contact.peerFoundingEd25519Pk != null)
        'peerFoundingEd25519Pk': bytesToHex(contact.peerFoundingEd25519Pk!),
      if (contact.deviceNodeIds.isNotEmpty) 'deviceNodeIds': contact.deviceNodeIds.toList(),
    }))));

    return sent;
  }

  /// Delete a contact and its conversation.
  @override
  void deleteContact(String nodeIdHex, {required String source}) {
    // V4.2 §12.5 (S388): a `pending` contact is a waiting question —
    // deleting is the refusal (inbox `inbox_reject`). Without this
    // decision the joiner would wait endlessly for a response.
    final deleted = _contacts[nodeIdHex];
    if (deleted != null && deleted.status == 'pending') {
      _myceliumRequestDecide(deleted, accept: false);
    } else if (deleted != null) {
      // §15.9: deleted also means no contact any more in the delivery layer.
      // Otherwise mycelium would answer the next request as a re-contact
      // WITHOUT a question (`Mailbox.requestCheck`) — measured S388-BAU-KONTAKT
      // E3: the request after deletion was answered silently.
      _myceliumContactForget(deleted);
    }
    _contacts.remove(nodeIdHex);
    _deletedContacts.add(nodeIdHex);
    // ── AND THE DELIVERY LAYER FORGETS HIM TOO (§21.5.1, S354) ─────
    //
    // Until now the pair key stayed in the `V41Node`: the node
    // continued to publish its liveness for this contact (§6 —
    // cost per speed contact and epoch), continued to harvest under its
    // tags, and `K_AB` survived the deletion. `PairRegistry.forget`
    // was built and had not a single caller in `lib/`.
    try {
      v41Delivery?.forgetPeer(_v41PeerKey(hexToBytes(nodeIdHex)));
    } catch (e) {
      // A malformed identifier must not stop the deletion —
      // the contact is already gone above, and that is the part the
      // user sees.
      _log.debug('forgetPeer for $nodeIdHex failed: $e');
    }
    conversations.remove(nodeIdHex);
    _saveContacts();
    _saveConversations();
    onStateChanged?.call();
    _log.event('CONTACT DELETED ${nodeIdHex.substring(0, 8)} (source=$source)');

    // Twin-Sync (§26)
    _sendTwinSync(proto.TwinSyncType.CONTACT_DELETED, Uint8List.fromList(utf8.encode(nodeIdHex)));
  }

  /// §14.7.4: withhold this node's delivery status from a contact or group.
  ///
  /// Unilateral by design — no `CHAT_CONFIG_UPDATE`, no partner confirmation,
  /// no distribution. The value is read when a DELIVERY_RECEIPT is emitted
  /// and travels as a bit on that receipt. [entityIdHex] is a contact nodeId
  /// or a groupId; channels are rejected (§14.7.4 "Channels" — no receipt is
  /// ever emitted for a channel post, so there is nothing to withhold).
  @override
  bool setWithholdDeliveryStatus(String entityIdHex, bool withhold) {
    final group = _groups[entityIdHex];
    if (group != null) {
      group.withholdDeliveryStatus = withhold;
      _saveGroups();
      onStateChanged?.call();
      return true;
    }
    final contact = _contacts[entityIdHex];
    if (contact != null) {
      contact.withholdDeliveryStatus = withhold;
      _saveContacts();
      onStateChanged?.call();
      return true;
    }
    return false;
  }

  // NO SETTER FOR A SEND MODE (S389). Here stood the
  // implementation of `setSecureMode`: it wrote `secureMode` and
  // `secureExplained` onto contact or group and also reported the choice
  // to the V4.1 layer (`v41Delivery?.setChatMode`). Both fields
  // are gone (§12.1 — no switch, no setting per chat), and the
  // layer that was reported to is no longer attached in the 4.2 start
  // (`attachV41` has no caller in `lib/`).

  /// Set or clear a local alias for a contact.
  @override
  void renameContact(String nodeIdHex, String? localAlias) {
    final contact = _contacts[nodeIdHex];
    if (contact == null) return;
    contact.localAlias = (localAlias != null && localAlias.trim().isEmpty) ? null : localAlias?.trim();
    // Also update conversation displayName
    final conv = conversations[nodeIdHex];
    if (conv != null) {
      conv.displayName = contact.effectiveName;
    }
    _saveContacts();
    onStateChanged?.call();
    _log.info('Contact renamed: ${nodeIdHex.substring(0, 8)} → "${contact.effectiveName}"');
  }

  /// Accept or reject a pending contact name change.
  @override
  void acceptContactNameChange(String nodeIdHex, bool accept) {
    final contact = _contacts[nodeIdHex];
    if (contact == null || contact.pendingNameChange == null) return;
    if (accept) {
      contact.displayName = contact.pendingNameChange!;
      // If no local alias, update conversation too
      if (contact.localAlias == null) {
        final conv = conversations[nodeIdHex];
        if (conv != null) {
          conv.displayName = contact.displayName;
        }
      }
    }
    contact.pendingNameChange = null;
    _saveContacts();
    onStateChanged?.call();
  }

  // ── Stale contact sender-side warning ──────────────────────────────
  //
  // V3.1.50 added receiver-side detection: when a reinstalled contact sends
  // a fresh CR, the old conversation gets a "new identity" system message.
  // That only helps if the new identity initiates contact. If the sender
  // (us) has the old userId and keeps writing to it, the receiver-side
  // path never fires and the user sees no warning — messages just silently
  // fail to deliver.
  //
  // This helper writes a one-time warning into the conversation when we're
  // sending to an accepted contact that hasn't ACKed anything for 7 days
  // (or ever, if accepted > 7d ago). Cleared on next ACK or re-accept.
  void _maybeWriteStaleContactWarning(String userIdHex) {
    if (_staleWarningWrittenFor.contains(userIdHex)) return;
    final contact = _contacts[userIdHex];
    if (contact == null || contact.status != 'accepted') return;
    final acceptedAt = contact.acceptedAt;
    if (acceptedAt == null) return;

    const staleThreshold = Duration(days: 7);
    final now = DateTime.now();
    if (now.difference(acceptedAt) < staleThreshold) return;

    final lastAck = contact.lastAckedAt;
    if (lastAck != null && now.difference(lastAck) < staleThreshold) return;

    final conv = conversations[userIdHex];
    if (conv == null) return;

    _staleWarningWrittenFor.add(userIdHex);
    final systemMsg = UiMessage(
      id: bytesToHex(SodiumFFI().randomBytes(16)),
      conversationId: userIdHex,
      senderNodeIdHex: '',
      text: 'No delivery confirmation from ${contact.displayName} in over 7 days. '
          'The contact may have reinstalled the app. '
          'Ask them to send you a new contact request.',
      isOutgoing: false,
      timestamp: now,
      type: UiMessageType.identityDeleted,
      status: MessageStatus.delivered,
    );
    // Route through _addMessageToConversation so badge + Launcher counter
    // pick up the warning (#U15 — direct conv.messages.add bypassed both).
    _addMessageToConversation(userIdHex, systemMsg);
    // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
    _log.debug('Stale sender-side warning for ${userIdHex.substring(0, 8)} (${contact.displayName})');
  }

  // ── CR Retry ───────────────────────────────────────────────────────

  /// §5.8 CR retry backoff in seconds for [attemptCount] previous attempts.
  ///
  /// Extracted so that the curve is testable — without that the
  /// shortening from [shortenCrBackoffOnEdge] would be unguarded.
  ///
  /// Curve: 10s, 20s, 40s, 80s, 160s, 320s, 640s, then capped at 600s
  /// (seed) or 1200s (seedless — the DHT re-resolve is cheaper per attempt,
  /// in exchange a longer tail; §8.1.1 and §5.8 record both caps
  /// normatively).
  ///
  /// The shift limit follows the respective cap. Until S290 it was 6 for both
  /// cases, so the uncapped value was at most 10 * (1 << 6) = 640s —
  /// the seed cap 600 thereby applied, the seedless cap 1200 however NEVER. The
  /// documented difference of a factor of two shrank to 7 % (600 against
  /// 640), and the 1200 were dead code. Presumably the limit was chosen together
  /// with the seed cap (640 is the first value above it) and not carried along
  /// when the seedless case was added later.
  static int crRetryBackoffSeconds(int attemptCount, {required bool isSeedless}) {
    final maxShift = isSeedless ? 7 : 6;
    final shift = attemptCount > maxShift ? maxShift : attemptCount;
    final capSec = isSeedless ? 1200 : 600;
    final uncapped = 10 * (1 << shift);
    return uncapped > capSec ? capSec : uncapped;
  }

  /// §5.1 CR edge: may shortening happen now for this contact?
  ///
  /// Visible for tests. [lastShorten] is the timestamp of the last
  /// shortening or `null` if none has taken place yet.
  static bool crEdgeShortenAllowed(DateTime? lastShorten, DateTime now) =>
      lastShorten == null ||
      now.difference(lastShorten) >= _crEdgeShortenGate;

  // ── Conversation Management ────────────────────────────────────────

  bool _addMessageToConversation(String conversationId, UiMessage msg, {bool isGroup = false, bool isChannel = false}) {
    final contact = _contacts[conversationId];
    final group = _groups[conversationId];
    final channel = _channels[conversationId];
    final conv = conversations.putIfAbsent(conversationId, () {
      final defaults = notificationSound.settings;
      if (isChannel && channel != null) {
        return Conversation(
          id: conversationId,
          displayName: channel.name,
          profilePictureBase64: channel.pictureBase64,
          isChannel: true,
          notificationsEnabled: defaults.defaultChannelNotify,
        );
      }
      if (isGroup && group != null) {
        return Conversation(
          id: conversationId,
          displayName: group.name,
          profilePictureBase64: group.pictureBase64,
          isGroup: true,
          notificationsEnabled: defaults.defaultGroupNotify,
        );
      }
      return Conversation(
        id: conversationId,
        displayName: contact?.displayName ?? conversationId.substring(0, 8),
        profilePictureBase64: contact?.profilePictureBase64,
        notificationsEnabled: defaults.defaultDirectNotify,
      );
    });
    // Keep profile picture in sync
    if (!isGroup && contact?.profilePictureBase64 != null && conv.profilePictureBase64 == null) {
      conv.profilePictureBase64 = contact!.profilePictureBase64;
    }

    // Set readAt for expiry timer: outgoing = read immediately, incoming = read on receipt
    msg.readAt ??= DateTime.now();

    // Dedup by msg.id: Node-level _seenMessageIds is in-memory and resets on
    // every daemon restart, but Store-and-Forward + Erasure replays the same
    // envelope to us whenever we come back online. Without this check, each
    // replay of a MEDIA_ANNOUNCEMENT (or any message) creates a new duplicate
    // row in the conversation with the same msg.id. User-visible symptom:
    // "4× screen_now.png with placeholder" (Bug #R2, 2026-04-18).
    if (msg.id.isNotEmpty) {
      ensureLoaded(conversationId);
      final existingIdx = conv.messages.indexWhere((m) => m.id == msg.id);
      if (existingIdx >= 0) {
        final existing = conv.messages[existingIdx];
        // Upgrade fields conservatively: prefer the newer/stronger state.
        // `mergeRank`, not `index`: AP-4b froze this order as an explicit
        // literal, because V4 §5.5 replaces the media stages and would
        // otherwise reorder this rule along with the enum (MIGRATION §5.1d).
        if (msg.mediaState.mergeRank > existing.mediaState.mergeRank) {
          existing.mediaState = msg.mediaState;
        }
        if (msg.filePath != null && existing.filePath == null) {
          existing.filePath = msg.filePath;
        }
        if (msg.thumbnailBase64 != null && existing.thumbnailBase64 == null) {
          existing.thumbnailBase64 = msg.thumbnailBase64;
        }
        if (existing.status.canTransitionTo(msg.status)) {
          existing.status = msg.status;
        }
        if (msg.readAt != null && existing.readAt == null) {
          existing.readAt = msg.readAt;
        }
        onStateChanged?.call();
        persistMessage(conversationId, existing);
        _saveConversations();
        return false;
      }
    }

    int insertIdx = conv.messages.length;
    for (int i = conv.messages.length - 1; i >= 0; i--) {
      if (conv.messages[i].timestamp.compareTo(msg.timestamp) <= 0) {
        insertIdx = i + 1;
        break;
      }
      if (i == 0) insertIdx = 0;
    }
    conv.messages.insert(insertIdx, msg);
    conv.lastActivity = msg.timestamp;
    if (!msg.isOutgoing &&
        !(_isAppResumed && _activeConversationId == conversationId) &&
        !SystemChannels.isSystemChannel(conversationId)) {
      conv.unreadCount++;
      _updateBadgeCount();
    }

    conv.totalMessages++;
    onNewMessage?.call(conversationId, msg);
    onStateChanged?.call();
    persistMessage(conversationId, msg);
    _saveConversations();
    return true;
  }

  /// Mark a conversation as read — sends READ_RECEIPTs if enabled.
  @override
  void markConversationRead(String conversationId) {
    final conv = conversations[conversationId];
    if (conv == null) return;

    final hadUnread = conv.unreadCount > 0;
    if (hadUnread) {
      conv.unreadCount = 0;
      onCancelNotificationAndroid?.call(conversationId);
      _updateBadgeCount();
    }

    // Send READ_RECEIPTs for unread incoming messages (if readReceipts enabled).
    // Runs regardless of unreadCount — messages may have status != read even
    // when the badge counter was already cleared.
    if (!conv.config.readReceipts) {
      if (hadUnread) {
        _saveConversations();
        onStateChanged?.call();
      }
      return;
    }

    var sentReceipts = false;
    ensureLoaded(conversationId);
    for (final msg in conv.messages) {
      // S390: the flag carries "my read receipt has already gone out",
      // not the delivery state (§9.1 lists four, and a read note
      // is none of them). It prevents the same as before: a second
      // receipt for the same message on every opening (§1.2).
      if (!msg.isOutgoing && !msg.readReceiptSent) {
        msg.readReceiptSent = true;
        persistMessage(conv.id, msg);
        sentReceipts = true;
        if (msg.senderNodeIdHex.isEmpty) continue;
        final senderUserId = hexToBytes(msg.senderNodeIdHex);
        final receipt = proto.ReadReceipt()
          ..messageId = hexToBytes(msg.id)
          ..readAt = Int64(DateTime.now().millisecondsSinceEpoch);
        _detachedSend('MTV3_READ_RECEIPT', sendToUser(
          recipientUserId: senderUserId,
          messageType: proto.MessageTypeV3.MTV3_READ_RECEIPT,
          payload: receipt.writeToBuffer(),
        ));
      }
    }

    if (hadUnread || sentReceipts) {
      _saveConversations();
      onStateChanged?.call();
    }

    if (sentReceipts) {
      _sendTwinSync(proto.TwinSyncType.TWIN_READ_RECEIPT, Uint8List.fromList(utf8.encode(jsonEncode({
        'conversationId': conversationId,
      }))));
    }
  }

  @override
  void setActiveConversationId(String? conversationId) {
    _activeConversationId = conversationId;

    // ── THE CHAT IS OPENED: FETCH LIVENESS (§6, E-E) ────────────
    //
    // "Liveness is fetched lazily when a chat is opened, not at
    // contact-add and not only on first send." Exactly this sentence had
    // no counterpart in the application — the read side of the speed path
    // was missing completely (S353, finding 2), and therefore EVERY
    // message took the secure path to `m x R` cells.
    //
    // HERE AND NOT IN `sendToUser`: the point of this place is that the
    // route already stands when the user types the first line. Fetched in the
    // send path, the first message of every conversation would
    // necessarily be the slow one.
    //
    // ONLY 1:1. For a group it would be one request PER MEMBER — with
    // twenty members twenty slots (~160 s egress) for merely
    // opening a chat in which perhaps nobody writes. The
    // members that matter are covered by the second trigger:
    // whose frame arrives, for him the route is fetched
    // (`acceptV41Frame`) — and exactly there the response goes.
    //
    // FREE WHEN THERE IS NOTHING TO DO: `prepareSpeed` returns immediately
    // if the route for the current epoch already stands, and
    // throttles repetitions via its own counter.
    final v41 = v41Delivery;
    if (v41 == null || conversationId == null) return;
    final conv = conversations[conversationId];
    if (conv == null || conv.isGroup || conv.isChannel) return;
    try {
      v41.prepareSpeed(_v41PeerKey(hexToBytes(conversationId)));
    } catch (e) {
      // A malformed identifier must not crash the opening of a chat
      // — the route then simply stays away, and the
      // message takes secure.
      _log.debug('prepareSpeed for $conversationId failed: $e');
    }
  }

  @override
  void setAppResumed(bool isResumed, {bool triggerNodeHarvest = true}) {
    final before = _isAppResumed;
    _isAppResumed = isResumed;
    // Here stood `_identityPublisher?.setForeground(isResumed)` — the
    // adaptive liveness TTL of the 2D DHT (§2.2.4). V4.1 has no
    // published liveness (T).

    // ── THE FOREGROUND EDGE FOR THE CATCH-UP HARVEST (S362) ───────────
    //
    // ONLY ON THE EDGE, not on every call: the lifecycle
    // observer reports `resumed` even when the app was already in front
    // (dialogs, keyboard, permission prompts). Without the edge an edge
    // would have become a timer — exactly what working rule 5
    // excludes.
    //
    // FREE WITHOUT ABSENCE: `catchUpHarvest` measures itself and returns
    // without a single tag if the node was away for less than one
    // epoch. That is the normal case on every wake-up.
    // ── ONCE PER PROCESS, NOT PER IDENTITY (S376, P5 find. 5) ────
    //
    // `catchUpHarvest` is a matter of the NODE — there is one
    // responsibility set and one have-list. The
    // lifecycle loop in `main.dart` however calls this method per
    // identity; with N = 3 that was three harvest runs for ONE
    // return to the foreground, i.e. three times network traffic for
    // the same information (working rule 5).
    //
    // AS WITH `onNetworkChanged` NEXT TO IT: the default value stays `true`,
    // so that a single caller loses nothing; whoever has already run the node part
    // himself says so.
    if (isResumed && !before && triggerNodeHarvest) {
      try {
        v41OnForeground?.call();
      } catch (e) {
        // A catch-up harvest must not crash the lifecycle
        // — it is a precaution, not a delivery path.
        _log.debug('V4.1-Nachholernte bei Vordergrund-Rueckkehr: $e');
      }
    }
  }

  /// Decide whether the in-app notification (sound + vibrate + Android banner)
  /// for an incoming message should be suppressed. Five layers (§12.5 / §15.5):
  ///
  ///   L1 — Foreground active conversation: chat is already on screen.
  ///   L2 — Per-conversation/type notification setting.
  ///   L3 — Stale backlog (startup only): during the first 30s after init,
  ///        messages older than 60s (sender clock) are suppressed. After
  ///        catch-up, no age-based suppression — Doze-delayed and S&F
  ///        messages notify normally.
  ///   L4 — Per-conversation debounce: at most one notification every
  ///        [_notificationDebounceMs] ms per conversation.
  ///
  /// L5 (_isAppResumed gate) lives in [_postAndroidNotification] and only
  /// affects the Android system notification, not in-app sound/vibrate.
  ///
  /// Badge updates run in a different code path and are NOT gated by this.
  bool _shouldSuppressNotification(String conversationId, int messageTimestampMs) {
    // L1: active conversation on screen
    if (_isAppResumed && _activeConversationId == conversationId) return true;
    // L2: per-conversation/type notification setting
    final conv = conversations[conversationId];
    if (conv != null) {
      final enabled = conv.notificationsEnabled ??
          notificationSound.settings.defaultForType(
              isGroup: conv.isGroup, isChannel: conv.isChannel);
      if (!enabled) return true;
    }
    // L3: stale backlog — only during startup catch-up phase
    if (_inStartupCatchUp) {
      final ageMs = DateTime.now().millisecondsSinceEpoch - messageTimestampMs;
      if (ageMs > _notificationStaleThresholdMs) return true;
    }
    // L4: per-conversation debounce
    final last = _lastNotifiedAt[conversationId];
    if (last != null &&
        DateTime.now().difference(last).inMilliseconds < _notificationDebounceMs) {
      return true;
    }
    return false;
  }

  /// Toggle favorite status of a conversation.
  @override
  void toggleFavorite(String conversationId) {
    final conv = conversations[conversationId];
    if (conv == null) return;
    conv.isFavorite = !conv.isFavorite;
    _saveConversations();
    onStateChanged?.call();
  }

  @override
  void updateConversationNotifications(String conversationId, {bool? enabled, String? soundName}) {
    final conv = conversations[conversationId];
    if (conv == null) return;
    conv.notificationsEnabled = enabled;
    conv.notificationSoundName = soundName;
    _saveConversations();
    onStateChanged?.call();
  }

  /// Send a typing indicator to a DM conversation partner.
  @override
  void sendTypingIndicator(String conversationId) {
    final conv = conversations[conversationId];
    if (conv == null || conv.isGroup) return;
    if (!conv.config.typingIndicators) return;

    final contact = _contacts[conversationId];
    if (contact == null || contact.status != 'accepted') return;

    final indicator = proto.TypingIndicator()
      ..conversationId = conversationId
      ..isTyping = true;
    _detachedSend('MTV3_TYPING_INDICATOR', sendToUser(
      recipientUserId: contact.nodeId,
      messageType: proto.MessageTypeV3.MTV3_TYPING_INDICATOR,
      payload: indicator.writeToBuffer(),
    ));
  }

  // ── Mutual Peer Selection (Architecture Section 3.3.7) ─────────

  /// Compute set of nodeIdHex that the recipient is likely to know.
  /// Sources: shared contacts (bidirectional) + shared group members.
  // ── ServiceContext implementation ───────────────────────────────

  @override
  Map<String, ContactInfo> get contacts => _contacts;
  @override
  ChannelIndex get channelIndex => _channelIndex;
  @override
  void saveChannels() => _saveChannels();
  @override
  void saveConversations() => _saveConversations();
  @override
  void notifyStateChanged() => onStateChanged?.call();
  @override
  bool hasChannelPermission(ChannelInfo channel, String action) =>
      _hasChannelPermission(channel, action);
  @override
  FileEncryption get fileEnc => _fileEnc;
  @override
  Future<void> sendEncryptedPayload(
    Uint8List recipientUserId,
    proto.MessageTypeV3 messageType,
    Uint8List payload, {
    Uint8List? groupId,
  }) => _sendEncryptedPayload(recipientUserId, messageType, payload, groupId: groupId);
  @override
  void addMessageToConversation(String conversationId, UiMessage msg,
      {bool isGroup = false, bool isChannel = false}) =>
      _addMessageToConversation(conversationId, msg, isGroup: isGroup, isChannel: isChannel);

  /// Insert a system message into a conversation.
  /// Replaces the 9-line UiMessage constructor that was copy-pasted at 12+ sites.
  /// Is this identifier fit as a reply reference ON THE WIRE?
  ///
  /// S368 — WHY THIS NEEDS A CHECK AND NOT A try/catch.
  ///
  /// `TextMessageV3.replyToMessageId` is a 16-byte field. Both send paths
  /// converted the identifier with `hexToBytes` and caught the error case with
  /// `catch (_) { _log.debug('… not hex — wire-tag dropped'); }` — the
  /// comment on it called the case "legacy". The consequence was a SILENT
  /// DIVERGENCE: the sender saw a reply in his history,
  /// the recipient an ordinary message, and the only
  /// trace was a debug line.
  ///
  /// MEASURED who creates an identifier on this line at all: all
  /// `UiMessage.id` arise as `bytesToHex(SodiumFFI().randomBytes(16))`
  /// (text, group text, media, system messages) or as `.hex` of a
  /// received `messageId`. There is no path by which a non-hex
  /// identifier arises. The "legacy" case meant legacy profiles — they do not reach
  /// this version (`FirstStartWipe`).
  ///
  /// If the case occurs nonetheless, it is damage to the local stock.
  /// Then the reply reference falls on BOTH sides — not only on the
  /// wire —, so that sender and recipient see the same, and the report
  /// is a warning instead of a debug line.
  static bool _isWireCapableMessageIdentifier(String id) =>
      RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(id);

  /// Test access to EXACTLY the production path — no second mechanism.
  @visibleForTesting
  static bool isWireCapableMessageIdentifierForTest(String id) =>
      _isWireCapableMessageIdentifier(id);

  void _addSystemMessage(String conversationId, String text, {
    bool isGroup = false,
    bool isChannel = false,
    required UiMessageType type,
  }) {
    final sysMsg = UiMessage(
      id: bytesToHex(SodiumFFI().randomBytes(16)),
      conversationId: conversationId,
      senderNodeIdHex: '',
      text: text,
      timestamp: DateTime.now(),
      type: type,
      status: MessageStatus.delivered,
      isOutgoing: false,
    );
    _addMessageToConversation(conversationId, sysMsg, isGroup: isGroup, isChannel: isChannel);
  }

  /// Standard warn-log for a `_handleXxxV3` catch block: `$handler: $messageType: $e`
  /// plus sender (and optionally device) hex prefix. Replaces the copy-pasted
  /// `_log.warn('...: parse fail: $e (sender=${_hexShort(...)})')` blocks.
  /// Uniform error log for handlers. The frame-based version
  /// next to it was dropped with step 5 — it no longer had a caller.
  void _logHandlerErrorEvent(String handler, Object e, HarvestEvent event,
      {String messageType = 'parse fail'}) {
    _log.warn('$handler: $messageType: $e '
        '(sender=${_hexShort(event.senderUserId)} '
        'device=${_hexShort(event.senderDeviceId)})');
  }

  // ── Groups ──────────────────────────────────────────────────────

  @override
  Map<String, GroupInfo> get groups => Map.unmodifiable(_groups);

  @override
  Future<String?> createGroup(String name, List<String> memberNodeIdHexList) async {
    final sodium = SodiumFFI();
    final groupId = sodium.randomBytes(32);
    final groupIdHex = bytesToHex(groupId);

    // Build member list (self + selected contacts)
    final members = <String, GroupMemberInfo>{};

    // Add self as owner
    members[identity.userIdHex] = GroupMemberInfo(
      nodeIdHex: identity.userIdHex,
      displayName: displayName,
      role: 'owner',
      ed25519Pk: identity.ed25519PublicKey,
      x25519Pk: identity.x25519PublicKey,
      mlKemPk: identity.mlKemPublicKey,
    );

    // Add selected contacts
    for (final nodeIdHex in memberNodeIdHexList) {
      final contact = _contacts[nodeIdHex];
      if (contact == null || contact.status != 'accepted') continue;
      members[nodeIdHex] = GroupMemberInfo(
        nodeIdHex: nodeIdHex,
        displayName: contact.displayName,
        role: 'member',
        ed25519Pk: contact.ed25519Pk,
        x25519Pk: contact.x25519Pk,
        mlKemPk: contact.mlKemPk,
      );
    }

    if (members.length < 2) {
      _log.warn('Group needs at least 2 members');
      return null;
    }

    final group = GroupInfo(
      groupIdHex: groupIdHex,
      name: name,
      ownerNodeIdHex: identity.userIdHex,
      members: members,
      membershipEpoch: 1,
    );
    _groups[groupIdHex] = group;
    _saveGroups();

    // Create conversation
    conversations[groupIdHex] = Conversation(
      id: groupIdHex,
      displayName: name,
      isGroup: true,
      notificationsEnabled: notificationSound.settings.defaultGroupNotify,
    );
    _saveConversations();

    // Send GROUP_INVITE to each member (pairwise encrypted)
    final invite = proto.GroupInviteV3()
      ..groupId = groupId
      ..groupName = name
      ..inviterId = identity.nodeId;
    for (final m in members.values) {
      invite.members.add(proto.GroupMemberV3()
        ..nodeId = hexToBytes(m.nodeIdHex)
        ..displayName = m.displayName
        ..role = m.role
        ..ed25519PublicKey = m.ed25519Pk ?? Uint8List(0)
        ..x25519PublicKey = m.x25519Pk ?? Uint8List(0)
        ..mlKemPublicKey = m.mlKemPk ?? Uint8List(0));
    }

    // GM-1 (§9.1.4): attach epoch, hash, and hybrid sig
    invite.membershipEpoch = Int64(group.membershipEpoch);
    final createHash = _computeMembershipHash(group.membershipEpoch, groupIdHex, members);
    invite.membershipHash = createHash;
    invite.membershipSigEd25519 = SodiumFFI().signEd25519(createHash, identity.ed25519SecretKey);
    invite.membershipSigMlDsa = OqsFFI().mlDsaSign(createHash, identity.mlDsaSecretKey);

    final inviteBytes = Uint8List.fromList(invite.writeToBuffer());
    // V3: pairwise sendToUser with groupId for receiver-side conversation routing.
    for (final m in members.values) {
      if (m.nodeIdHex == identity.userIdHex) continue;
      final (x25519Pk, mlKemPk, ed25519Pk) = _resolveMemberKeys(m.nodeIdHex,
          memberX25519Pk: m.x25519Pk, memberMlKemPk: m.mlKemPk, memberEd25519Pk: m.ed25519Pk);
      if (x25519Pk == null || mlKemPk == null) continue;
      final ok = await sendToUser(
        recipientUserId: hexToBytes(m.nodeIdHex),
        messageType: proto.MessageTypeV3.MTV3_GROUP_INVITE,
        payload: inviteBytes,
        groupId: groupId,
        recipientX25519PkOverride: x25519Pk,
        recipientMlKemPkOverride: mlKemPk,
        recipientEd25519PkOverride: ed25519Pk,
      );
      if (!ok) {
        // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
        _log.debug('GROUP_INVITE: no route to ${m.nodeIdHex.substring(0, 8)} (${m.displayName}) — S&F path not yet implemented');
      }
    }

    onStateChanged?.call();
    _log.info('Group "$name" created with ${members.length} members: $groupIdHex');
    return groupIdHex;
  }

  @override
  Future<UiMessage?> sendGroupTextMessage(String groupIdHex, String text, {String? replyToMessageId, String? replyToText, String? replyToSender}) async {
    if (_reducedMode) {
      _log.warn('sendGroupTextMessage blocked: reducedMode active');
      return null;
    }
    final group = _groups[groupIdHex];
    if (group == null) return null;

    // S368: see `_isWireFaehigeNachrichtenkennung`. If the reference falls,
    // it falls on BOTH sides.
    if (replyToMessageId != null &&
        replyToMessageId.isNotEmpty &&
        !_isWireCapableMessageIdentifier(replyToMessageId)) {
      _log.warn('sendGroupTextMessage: replyToMessageId is not a '
          '32-digit hex identifier — the reply reference is dropped entirely, also '
          'locally.');
      replyToMessageId = null;
      replyToText = null;
      replyToSender = null;
    }

    // V3 group fan-out: TextMessageV3 sub-message + sendToUser per member.
    // ApplicationFrameV3.group_id (Field 17) carries the conversation tag so
    // receivers dispatch into the matching group tab.
    final tm = proto.TextMessageV3()
      ..text = text
      ..formatHint = 'plain';
    proto.LinkPreview? wirePreview;
    String? previewUrl, previewTitle, previewDescription, previewSiteName, previewThumbnailBase64;
    if (_linkPreviewSettings.enabled && extractFirstUrl(text) != null) {
      try {
        final preview = await _linkPreviewFetcher.fetchPreview(text);
        if (preview != null) {
          wirePreview = preview.toProto();
          previewUrl = preview.url;
          previewTitle = preview.title;
          previewDescription = preview.description;
          previewSiteName = preview.siteName;
          if (preview.thumbnail != null) previewThumbnailBase64 = base64Encode(preview.thumbnail!);
        }
      } catch (e) {
        _log.debug('Link preview fetch failed: $e');
      }
    }
    if (wirePreview != null) tm.linkPreview = wirePreview;
    if (replyToMessageId != null && replyToMessageId.isNotEmpty) {
      // S368: checked above — `hexToBytes` can no longer throw here.
      tm.replyToMessageId = hexToBytes(replyToMessageId);
      if (replyToText != null && replyToText.isNotEmpty) {
        tm.replyToSnippet = replyToText.length > 120
            ? '${replyToText.substring(0, 120)}…'
            : replyToText;
      }
    }
    final basePayload = tm.writeToBuffer();
    final groupIdBytes = hexToBytes(groupIdHex);
    // GM-1 (§9.1.4): post-tag with sender's local membership state
    final gmEpoch = group.membershipEpoch;
    final gmHash = _computeMembershipHash(gmEpoch, groupIdHex, group.members);

    final localId = bytesToHex(SodiumFFI().randomBytes(16));
    final msg = UiMessage(
      id: localId,
      conversationId: groupIdHex,
      senderNodeIdHex: identity.userIdHex,
      text: text,
      timestamp: DateTime.now(),
      type: UiMessageType.text,
      status: MessageStatus.resting,
      isOutgoing: true,
      replyToMessageId: replyToMessageId,
      replyToText: replyToText,
      replyToSender: replyToSender,
    );
    if (previewUrl != null) {
      msg.linkPreviewUrl = previewUrl;
      msg.linkPreviewTitle = previewTitle;
      msg.linkPreviewDescription = previewDescription;
      msg.linkPreviewSiteName = previewSiteName;
      msg.linkPreviewThumbnailBase64 = previewThumbnailBase64;
    }

    _addMessageToConversation(groupIdHex, msg, isGroup: true);

    await Future.delayed(Duration.zero);

    // §5.8/§14.7.4: every leg gets its OWN wire messageId, recorded on the
    // UiMessage so the incoming DELIVERY_RECEIPT can be attributed to the
    // member that sent it. A shared id would collide in `AckTracker._pending`
    // (keyed by messageId alone) and evict each previous member's timer.
    bool anySent = false;
    for (final member in group.members.values) {
      if (member.nodeIdHex == identity.userIdHex) continue;
      final (x25519Pk, mlKemPk, ed25519Pk) = _resolveMemberKeys(member.nodeIdHex,
          memberX25519Pk: member.x25519Pk, memberMlKemPk: member.mlKemPk, memberEd25519Pk: member.ed25519Pk);
      if (x25519Pk == null || mlKemPk == null) continue;
      final legId = SodiumFFI().randomBytes(16);
      msg.fanoutLegs[member.nodeIdHex] = bytesToHex(legId);
      final ok = await sendToUser(
        recipientUserId: hexToBytes(member.nodeIdHex),
        messageType: proto.MessageTypeV3.MTV3_TEXT,
        payload: basePayload,
        messageId: legId,
        groupId: groupIdBytes,
        groupMembershipEpoch: gmEpoch,
        groupMembershipHash: gmHash,
        recipientX25519PkOverride: x25519Pk,
        recipientMlKemPkOverride: mlKemPk,
        recipientEd25519PkOverride: ed25519Pk,
      );
      if (ok) anySent = true;
    }

    // AP-4 (§5.1b/§5.1c K2): the ternary over `anyPlacedNowhere`/`anyL3Only`
    // has been dropped without replacement — "L3 placed" is no longer an event in V4.1.
    // The aggregate over the WEAKEST leg stays (v4_1 §21.5.5
    // "Aggregation per leg"), but it now reads the delivery register instead
    // of the send result. An offline recipient is still
    // NO error: for him the cell lies on the tag line.
    _v41ApplyOutgoingStatus(msg, msg.fanoutLegs.values.toList());
    if (anySent) statsCollector.addMessageSent();
    onStateChanged?.call();
    _saveConversations();
    return msg;
  }

  @override
  Future<bool> leaveGroup(String groupIdHex) async {
    final group = _groups[groupIdHex];
    if (group == null) return false;

    // If owner leaving, transfer ownership to first admin (or first member)
    if (group.ownerNodeIdHex == identity.userIdHex && group.members.length > 1) {
      final otherMembers = group.members.values.where((m) => m.nodeIdHex != identity.userIdHex);
      final newOwner = otherMembers.where((m) => m.role == 'admin').firstOrNull
          ?? otherMembers.first;
      newOwner.role = 'owner';
      group.ownerNodeIdHex = newOwner.nodeIdHex;
      // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
      _log.debug('Ownership transferred to ${newOwner.displayName} before leaving');
    }

    // Remove self from member list before broadcasting
    group.members.remove(identity.userIdHex);
    group.membershipEpoch++;

    // Broadcast updated group (without us) to remaining members
    if (group.members.isNotEmpty) {
      await _broadcastGroupUpdate(group);
    }

    // V3 GROUP_LEAVE fan-out
    final leaveMsg = proto.GroupLeave()..groupId = hexToBytes(groupIdHex);
    final leaveBytes = Uint8List.fromList(leaveMsg.writeToBuffer());
    final groupIdBytes = hexToBytes(groupIdHex);
    for (final member in group.members.values) {
      final (x25519Pk, mlKemPk, ed25519Pk) = _resolveMemberKeys(member.nodeIdHex,
          memberX25519Pk: member.x25519Pk, memberMlKemPk: member.mlKemPk, memberEd25519Pk: member.ed25519Pk);
      if (x25519Pk == null || mlKemPk == null) continue;
      _detachedSend('MTV3_GROUP_LEAVE', sendToUser(
        recipientUserId: hexToBytes(member.nodeIdHex),
        messageType: proto.MessageTypeV3.MTV3_GROUP_LEAVE,
        payload: leaveBytes,
        groupId: groupIdBytes,
        recipientX25519PkOverride: x25519Pk,
        recipientMlKemPkOverride: mlKemPk,
        recipientEd25519PkOverride: ed25519Pk,
      ));
    }

    _groups.remove(groupIdHex);
    // Remove the conversation too — we're no longer in this group
    conversations.remove(groupIdHex);
    _saveGroups();
    _saveConversations();
    onStateChanged?.call();
    _log.info('Left group $groupIdHex');
    return true;
  }

  @override
  Future<bool> inviteToGroup(String groupIdHex, String memberNodeIdHex) async {
    final group = _groups[groupIdHex];
    if (group == null) return false;

    // Owner or Admin can invite
    if (!_hasGroupPermission(group, 'invite')) return false;

    final contact = _contacts[memberNodeIdHex];
    if (contact == null || contact.status != 'accepted') return false;
    if (contact.x25519Pk == null || contact.mlKemPk == null) return false;

    // Add member to group
    group.members[memberNodeIdHex] = GroupMemberInfo(
      nodeIdHex: memberNodeIdHex,
      displayName: contact.displayName,
      role: 'member',
      ed25519Pk: contact.ed25519Pk,
      x25519Pk: contact.x25519Pk,
      mlKemPk: contact.mlKemPk,
    );
    group.membershipEpoch++;
    _saveGroups();

    // Send GROUP_INVITE to new member AND broadcast updated member list to
    // existing members — otherwise their local state stays stale and they
    // can't target the new member for role changes, messages, etc.
    await _broadcastGroupUpdate(group);

    // System message
    _addSystemMessage(groupIdHex, '${contact.displayName} was invited',
        type: UiMessageType.groupInvite, isGroup: true);

    // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
    _log.debug('Invited ${contact.displayName} to group "${group.name}"');
    return true;
  }

  @override
  Future<bool> removeMemberFromGroup(String groupIdHex, String memberNodeIdHex) async {
    final group = _groups[groupIdHex];
    if (group == null) return false;

    // Owner or Admin can remove
    if (!_hasGroupPermission(group, 'remove')) return false;
    // Can't remove self (use leaveGroup)
    if (memberNodeIdHex == identity.userIdHex) return false;

    final memberName = group.members[memberNodeIdHex]?.displayName ?? memberNodeIdHex.substring(0, 8);
    group.members.remove(memberNodeIdHex);
    group.membershipEpoch++;
    _saveGroups();

    // Broadcast updated member list to all remaining members
    await _broadcastGroupUpdate(group);

    // System message
    _addSystemMessage(groupIdHex, '$memberName was removed',
        type: UiMessageType.groupLeave, isGroup: true);

    onStateChanged?.call();
    _log.info('Removed $memberName from group "${group.name}"');
    return true;
  }

  @override
  Future<bool> setMemberRole(String entityIdHex, String memberNodeIdHex, String role) async {
    // Dual-mode: works for both groups and channels (Architecture v3.0 Section 10.2)
    final group = _groups[entityIdHex];
    final channel = _channels[entityIdHex];
    if (group == null && channel == null) return false;

    final validRoles = group != null
        ? ['owner', 'admin', 'member']
        : ['owner', 'admin', 'subscriber'];
    if (!validRoles.contains(role)) return false;

    // Can't change own role
    if (memberNodeIdHex == identity.userIdHex) return false;

    if (group != null) {
      // Permission: Owner only. Architecture §10.2: "Owner … appoints Admins".
      // Admins can invite/remove members + moderate content, but cannot change roles.
      final myMember = group.members[identity.userIdHex];
      if (myMember == null || myMember.role != 'owner') return false;

      final member = group.members[memberNodeIdHex];
      if (member == null) return false;

      final oldRole = member.role;
      member.role = role;

      if (role == 'owner') {
        group.members[identity.userIdHex]?.role = 'admin';
        group.ownerNodeIdHex = memberNodeIdHex;
      }

      group.membershipEpoch++;
      _saveGroups();
      await _broadcastGroupUpdate(group);
      _broadcastRoleUpdate(entityIdHex, memberNodeIdHex, role, group.members);

      _addSystemMessage(entityIdHex, '${member.displayName}: $oldRole → $role',
          type: UiMessageType.channelRoleUpdate, isGroup: true);
      // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
      _log.debug('Role changed: ${member.displayName} $oldRole -> $role in group "${group.name}"');

    } else {
      // Channel — same rule as groups: Owner only can change roles (§10.2).
      final myMember = channel!.members[identity.userIdHex];
      if (myMember == null || myMember.role != 'owner') return false;

      final member = channel.members[memberNodeIdHex];
      if (member == null) return false;

      final oldRole = member.role;
      member.role = role;

      if (role == 'owner') {
        channel.members[identity.userIdHex]?.role = 'admin';
        channel.ownerNodeIdHex = memberNodeIdHex;
      }

      channel.membershipEpoch++;
      _saveChannels();
      _broadcastRoleUpdate(entityIdHex, memberNodeIdHex, role, channel.members);

      _addSystemMessage(entityIdHex, '${member.displayName}: $oldRole → $role',
          type: UiMessageType.channelRoleUpdate, isChannel: true);
      // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
      _log.debug('Role changed: ${member.displayName} $oldRole -> $role in channel "${channel.name}"');
    }

    onStateChanged?.call();
    return true;
  }

  /// Broadcast CHANNEL_ROLE_UPDATE to all members of a group or channel.
  /// Architecture v3.0: "must be sent to ALL members, not just the affected member"
  void _broadcastRoleUpdate(String entityIdHex, String targetIdHex, String newRole,
      Map<String, dynamic> members) {
    final roleUpdate = proto.ChannelRoleUpdate()
      ..channelId = hexToBytes(entityIdHex)
      ..targetId = hexToBytes(targetIdHex)
      ..newRole = newRole;

    final roleBytes = Uint8List.fromList(roleUpdate.writeToBuffer());
    final entityIdBytes = hexToBytes(entityIdHex);
    for (final entry in members.entries) {
      final mHex = entry.key;
      if (mHex == identity.userIdHex) continue;
      final m = entry.value;
      final (x25519Pk, mlKemPk, ed25519Pk) = _resolveMemberKeys(mHex,
          memberX25519Pk: m.x25519Pk as Uint8List?,
          memberMlKemPk: m.mlKemPk as Uint8List?,
          memberEd25519Pk: m.ed25519Pk as Uint8List?);
      if (x25519Pk == null || mlKemPk == null) continue;
      _detachedSend('MTV3_CHANNEL_ROLE_UPDATE', sendToUser(
        recipientUserId: hexToBytes(mHex),
        messageType: proto.MessageTypeV3.MTV3_CHANNEL_ROLE_UPDATE,
        payload: roleBytes,
        groupId: entityIdBytes,
        recipientX25519PkOverride: x25519Pk,
        recipientMlKemPkOverride: mlKemPk,
        recipientEd25519PkOverride: ed25519Pk,
      ));
    }
  }

  /// GM-1 (§9.1.4): canonical membership hash.
  /// SHA-256(epoch_le64 || groupId_bytes || Σ sorted(nodeId || role_utf8))
  Uint8List _computeMembershipHash(int epoch, String groupIdHex, Map<String, GroupMemberInfo> members) {
    final sorted = members.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final parts = <int>[];
    final epochBytes = ByteData(8)..setUint64(0, epoch, Endian.little);
    parts.addAll(epochBytes.buffer.asUint8List());
    parts.addAll(hexToBytes(groupIdHex));
    for (final e in sorted) {
      parts.addAll(hexToBytes(e.key));
      parts.addAll(utf8.encode(e.value.role));
    }
    return SodiumFFI().sha256(Uint8List.fromList(parts));
  }

  /// Build a signed GROUP_INVITE payload from current group state.
  Uint8List _buildSignedGroupInviteBytes(GroupInfo group) {
    final invite = proto.GroupInviteV3()
      ..groupId = hexToBytes(group.groupIdHex)
      ..groupName = group.name
      ..inviterId = identity.nodeId;
    for (final m in group.members.values) {
      invite.members.add(proto.GroupMemberV3()
        ..nodeId = hexToBytes(m.nodeIdHex)
        ..displayName = m.displayName
        ..role = m.role
        ..ed25519PublicKey = m.ed25519Pk ?? Uint8List(0)
        ..x25519PublicKey = m.x25519Pk ?? Uint8List(0)
        ..mlKemPublicKey = m.mlKemPk ?? Uint8List(0));
    }
    invite.membershipEpoch = Int64(group.membershipEpoch);
    final hash = _computeMembershipHash(group.membershipEpoch, group.groupIdHex, group.members);
    invite.membershipHash = hash;
    invite.membershipSigEd25519 = SodiumFFI().signEd25519(hash, identity.ed25519SecretKey);
    invite.membershipSigMlDsa = OqsFFI().mlDsaSign(hash, identity.mlDsaSecretKey);
    return Uint8List.fromList(invite.writeToBuffer());
  }

  /// Broadcast updated group member list to all members via GROUP_INVITE.
  Future<void> _broadcastGroupUpdate(GroupInfo group) async {
    final groupId = hexToBytes(group.groupIdHex);
    final inviteBytes = _buildSignedGroupInviteBytes(group);
    bool anyFailed = false;
    for (final m in group.members.values.toList()) {
      if (m.nodeIdHex == identity.userIdHex) continue;
      final (x25519Pk, mlKemPk, ed25519Pk) = _resolveMemberKeys(m.nodeIdHex,
          memberX25519Pk: m.x25519Pk, memberMlKemPk: m.mlKemPk, memberEd25519Pk: m.ed25519Pk);
      if (x25519Pk == null || mlKemPk == null) continue;
      final ok = await sendToUser(
        recipientUserId: hexToBytes(m.nodeIdHex),
        messageType: proto.MessageTypeV3.MTV3_GROUP_INVITE,
        payload: inviteBytes,
        groupId: groupId,
        recipientX25519PkOverride: x25519Pk,
        recipientMlKemPkOverride: mlKemPk,
        recipientEd25519PkOverride: ed25519Pk,
      );
      if (!ok) {
        // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
        _log.debug('GROUP_UPDATE broadcast: no route to ${m.nodeIdHex.substring(0, 8)} (${m.displayName})');
        _pendingMembershipResends
            .putIfAbsent(group.groupIdHex, () => {})
            .add(m.nodeIdHex);
        anyFailed = true;
      }
    }
    // S366: ONE row for THIS group instead of the whole stock.
    if (anyFailed) _persistMembershipResend(group.groupIdHex);
    _log.info('Broadcast group update for "${group.name}" to ${group.members.length - 1} members');
  }

  /// Check if caller has permission for group action.
  bool _hasGroupPermission(GroupInfo group, String action) {
    final myMember = group.members[identity.userIdHex];
    if (myMember == null) return false;

    switch (action) {
      case 'invite':
        return myMember.role == 'owner' || myMember.role == 'admin';
      case 'remove':
        return myMember.role == 'owner' || myMember.role == 'admin';
      case 'change_role':
        return myMember.role == 'owner';
      case 'config':
        return myMember.role == 'owner' || myMember.role == 'admin';
      default:
        return false;
    }
  }

  // ── Channels ────────────────────────────────────────────────────

  @override
  Map<String, ChannelInfo> get channels => Map.unmodifiable(_channels);

  @override
  Future<String?> createChannel(String name, List<String> subscriberNodeIdHexList, {
    bool isPublic = false,
    bool isAdult = true,
    String language = 'de',
    String category = 'general',
    String? description,
    String? pictureBase64,
  }) async {
    final sodium = SodiumFFI();
    final channelId = sodium.randomBytes(32);
    final channelIdHex = bytesToHex(channelId);

    // Build member list (self as owner + selected contacts as subscribers)
    final members = <String, ChannelMemberInfo>{};

    // Add self as owner
    members[identity.userIdHex] = ChannelMemberInfo(
      nodeIdHex: identity.userIdHex,
      displayName: displayName,
      role: 'owner',
      ed25519Pk: identity.ed25519PublicKey,
      x25519Pk: identity.x25519PublicKey,
      mlKemPk: identity.mlKemPublicKey,
    );

    // For private channels, require at least 1 subscriber
    // For public channels, subscribers are optional (people join via search)
    if (!isPublic) {
      for (final nodeIdHex in subscriberNodeIdHexList) {
        final contact = _contacts[nodeIdHex];
        if (contact == null || contact.status != 'accepted') continue;
        members[nodeIdHex] = ChannelMemberInfo(
          nodeIdHex: nodeIdHex,
          displayName: contact.displayName,
          role: 'subscriber',
          ed25519Pk: contact.ed25519Pk,
          x25519Pk: contact.x25519Pk,
          mlKemPk: contact.mlKemPk,
        );
      }

      if (members.length < 2) {
        _log.warn('Private channel needs at least 1 subscriber');
        return null;
      }
    } else {
      // Public channels can also pre-invite contacts
      for (final nodeIdHex in subscriberNodeIdHexList) {
        final contact = _contacts[nodeIdHex];
        if (contact == null || contact.status != 'accepted') continue;
        members[nodeIdHex] = ChannelMemberInfo(
          nodeIdHex: nodeIdHex,
          displayName: contact.displayName,
          role: 'subscriber',
          ed25519Pk: contact.ed25519Pk,
          x25519Pk: contact.x25519Pk,
          mlKemPk: contact.mlKemPk,
        );
      }
    }

    final channel = ChannelInfo(
      channelIdHex: channelIdHex,
      name: name,
      description: description,
      pictureBase64: pictureBase64,
      ownerNodeIdHex: identity.userIdHex,
      members: members,
      isPublic: isPublic,
      isAdult: isAdult,
      language: language,
      category: category,
      membershipEpoch: 1,
    );
    _channels[channelIdHex] = channel;
    _saveChannels();

    // Create conversation
    conversations[channelIdHex] = Conversation(
      id: channelIdHex,
      displayName: name,
      isChannel: true,
      notificationsEnabled: notificationSound.settings.defaultChannelNotify,
    );
    _saveConversations();

    // Send CHANNEL_INVITE to each subscriber (pairwise encrypted)
    if (members.length > 1) {
      await _broadcastChannelUpdate(channel);
    }

    // Publish to DHT channel index if public
    if (isPublic) {
      _channelIndex.upsert(ChannelIndexEntry(
        channelIdHex: channelIdHex,
        name: name,
        language: language,
        category: category,
        isAdult: isAdult,
        description: description,
        subscriberCount: members.length,
        ownerNodeIdHex: identity.userIdHex,
        createdAt: channel.createdAt,
      ));
      // S366: `upsert` writes its ONE row itself. The `save()` that formerly
      // stood here would now have rewritten the whole index.
    }

    onStateChanged?.call();
    _log.info('Channel "$name" created (public=$isPublic, adult=$isAdult, lang=$language) with ${members.length} members: $channelIdHex');
    return channelIdHex;
  }

  @override
  Future<UiMessage?> sendChannelPost(String channelIdHex, String text) async {
    if (_reducedMode) {
      _log.warn('sendChannelPost blocked: reducedMode active');
      return null;
    }
    final channel = _channels[channelIdHex];
    if (channel == null) return null;

    // §9.5.7 (S119 D1): system channels are ownerless and have no member
    // fan-out — posts travel as self-signed SystemChannelRecords via the
    // SYSCHAN gossip. The old CHANNEL_POST path fanned out over the always-
    // empty members map (Problem 4/6: posts never left the local node).
    if (SystemChannels.isSystemChannel(channelIdHex)) {
      final stored = await _publishSystemChannelRecord(
          channelIdHex: channelIdHex, kind: SysChanKind.post, text: text);
      if (stored == null) return null;
      statsCollector.addMessageSent();
      final conv = conversations[channelIdHex];
      final recordIdHex =
          stored.record.recordId.hex;
      for (final m in conv?.messages ?? const <UiMessage>[]) {
        if (m.id == recordIdHex) return m;
      }
      return null;
    }

    // Only owner/admin can post
    if (!_hasChannelPermission(channel, 'post')) {
      _log.warn('No permission to post in channel');
      return null;
    }

    // V3 CHANNEL_POST: TextMessageV3 sub-message + sendToUser per member with
    // groupId so receivers route to the channel tab.
    final tm = proto.TextMessageV3()
      ..text = text
      ..formatHint = 'plain';
    proto.LinkPreview? wirePreview;
    String? previewUrl, previewTitle, previewDescription, previewSiteName, previewThumbnailBase64;
    if (_linkPreviewSettings.enabled && extractFirstUrl(text) != null) {
      try {
        final preview = await _linkPreviewFetcher.fetchPreview(text);
        if (preview != null) {
          wirePreview = preview.toProto();
          previewUrl = preview.url;
          previewTitle = preview.title;
          previewDescription = preview.description;
          previewSiteName = preview.siteName;
          if (preview.thumbnail != null) previewThumbnailBase64 = base64Encode(preview.thumbnail!);
        }
      } catch (e) {
        _log.debug('Link preview fetch failed: $e');
      }
    }
    if (wirePreview != null) tm.linkPreview = wirePreview;
    final basePayload = Uint8List.fromList(tm.writeToBuffer());
    final channelIdBytes = hexToBytes(channelIdHex);

    // GM-4 (§9.1.4): tag channel posts with membership epoch+hash
    final chEpoch = channel.membershipEpoch;
    final chHash = _computeChannelMembershipHash(chEpoch, channelIdHex, channel.members);

    String? firstMsgId;

    // §5.8: the fan-out is awaited — not for error handling, but because the
    // post's status is otherwise unknowable. The previous fire-and-forget
    // loop let the UiMessage below claim `sent` even with zero connectivity.
    // No leg tracking here: `CHANNEL_POST` is not ack-worthy
    // (`AckTracker.isAckWorthyV3`), so no receipt ever comes back and a
    // channel post can never reach `delivered` (§14.7.4 "Channels").
    // AP-4 (§5.1c K2): `anyPlacedNowhere`/`anyL3Only` fell away with the ternary.
    // For the channel path there is NO replacement from the
    // delivery register: it does not pass `sendToUser` an own identifier per
    // subscriber (unlike the group fan-out), so the
    // application cannot find the register's records again. The post
    // stays at `placing`. That is more honest than the old `sent`, but it
    // is a reported gap, not a final state.
    for (final member in channel.members.values) {
      if (member.nodeIdHex == identity.userIdHex) continue;
      final (x25519Pk, mlKemPk, ed25519Pk) = _resolveMemberKeys(member.nodeIdHex,
          memberX25519Pk: member.x25519Pk, memberMlKemPk: member.mlKemPk, memberEd25519Pk: member.ed25519Pk);
      if (x25519Pk == null || mlKemPk == null) continue;
      await sendToUser(
        recipientUserId: hexToBytes(member.nodeIdHex),
        messageType: proto.MessageTypeV3.MTV3_CHANNEL_POST,
        payload: basePayload,
        groupId: channelIdBytes,
        groupMembershipEpoch: chEpoch,
        groupMembershipHash: chHash,
        recipientX25519PkOverride: x25519Pk,
        recipientMlKemPkOverride: mlKemPk,
        recipientEd25519PkOverride: ed25519Pk,
      );
    }

    // If no other members received the post, generate a local message ID
    // (e.g. owner-only public channel — post is stored locally for future subscribers)
    firstMsgId ??= bytesToHex(SodiumFFI().randomBytes(16));
    statsCollector.addMessageSent();

    // Create single UI message
    final msg = UiMessage(
      id: firstMsgId,
      conversationId: channelIdHex,
      senderNodeIdHex: identity.userIdHex,
      text: text,
      timestamp: DateTime.now(),
      type: UiMessageType.channelPost,
      status: MessageStatus.resting,
      isOutgoing: true,
    );
    if (previewUrl != null) {
      msg.linkPreviewUrl = previewUrl;
      msg.linkPreviewTitle = previewTitle;
      msg.linkPreviewDescription = previewDescription;
      msg.linkPreviewSiteName = previewSiteName;
      msg.linkPreviewThumbnailBase64 = previewThumbnailBase64;
    }

    _addMessageToConversation(channelIdHex, msg, isChannel: true);

    return msg;
  }

  @override
  Future<bool> leaveChannel(String channelIdHex) async {
    final channel = _channels[channelIdHex];
    if (channel == null) return false;

    // If owner leaving, transfer ownership to first admin (or first member)
    if (channel.ownerNodeIdHex == identity.userIdHex && channel.members.length > 1) {
      final otherMembers = channel.members.values.where((m) => m.nodeIdHex != identity.userIdHex);
      final newOwner = otherMembers.where((m) => m.role == 'admin').firstOrNull
          ?? otherMembers.first;
      newOwner.role = 'owner';
      channel.ownerNodeIdHex = newOwner.nodeIdHex;
      // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
      _log.debug('Channel ownership transferred to ${newOwner.displayName} before leaving');
    }

    // Remove self from member list before broadcasting
    channel.members.remove(identity.userIdHex);
    channel.membershipEpoch++;

    // Broadcast updated channel (without us) to remaining members
    if (channel.members.isNotEmpty) {
      await _broadcastChannelUpdate(channel);
    }

    // V3 CHANNEL_LEAVE fan-out
    final leaveMsg = proto.ChannelLeave()..channelId = hexToBytes(channelIdHex);
    final leaveBytes = Uint8List.fromList(leaveMsg.writeToBuffer());
    final channelIdBytes = hexToBytes(channelIdHex);
    for (final member in channel.members.values) {
      final (x25519Pk, mlKemPk, ed25519Pk) = _resolveMemberKeys(member.nodeIdHex,
          memberX25519Pk: member.x25519Pk, memberMlKemPk: member.mlKemPk, memberEd25519Pk: member.ed25519Pk);
      if (x25519Pk == null || mlKemPk == null) continue;
      _detachedSend('MTV3_CHANNEL_LEAVE', sendToUser(
        recipientUserId: hexToBytes(member.nodeIdHex),
        messageType: proto.MessageTypeV3.MTV3_CHANNEL_LEAVE,
        payload: leaveBytes,
        groupId: channelIdBytes,
        recipientX25519PkOverride: x25519Pk,
        recipientMlKemPkOverride: mlKemPk,
        recipientEd25519PkOverride: ed25519Pk,
      ));
    }

    _channels.remove(channelIdHex);
    conversations.remove(channelIdHex);
    _saveChannels();
    _saveConversations();
    onStateChanged?.call();
    _log.info('Left channel $channelIdHex');
    return true;
  }

  @override
  Future<bool> inviteToChannel(String channelIdHex, String memberNodeIdHex) async {
    final channel = _channels[channelIdHex];
    if (channel == null) return false;

    // Owner or Admin can invite
    if (!_hasChannelPermission(channel, 'invite')) return false;

    final contact = _contacts[memberNodeIdHex];
    if (contact == null || contact.status != 'accepted') return false;
    if (contact.x25519Pk == null || contact.mlKemPk == null) return false;

    // Add as subscriber
    channel.members[memberNodeIdHex] = ChannelMemberInfo(
      nodeIdHex: memberNodeIdHex,
      displayName: contact.displayName,
      role: 'subscriber',
      ed25519Pk: contact.ed25519Pk,
      x25519Pk: contact.x25519Pk,
      mlKemPk: contact.mlKemPk,
    );
    channel.membershipEpoch++;
    _saveChannels();

    // Broadcast updated member list to all members
    await _broadcastChannelUpdate(channel);

    // System message
    _addSystemMessage(channelIdHex, '${contact.displayName} was invited',
        type: UiMessageType.channelInvite, isChannel: true);

    // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
    _log.debug('Invited ${contact.displayName} to channel "${channel.name}"');
    return true;
  }

  @override
  Future<bool> removeFromChannel(String channelIdHex, String memberNodeIdHex) async {
    final channel = _channels[channelIdHex];
    if (channel == null) return false;

    // Owner or Admin can remove
    if (!_hasChannelPermission(channel, 'remove')) return false;
    if (memberNodeIdHex == identity.userIdHex) return false;

    final memberName = channel.members[memberNodeIdHex]?.displayName ?? memberNodeIdHex.substring(0, 8);
    channel.members.remove(memberNodeIdHex);
    channel.membershipEpoch++;
    _saveChannels();

    // Broadcast updated member list
    await _broadcastChannelUpdate(channel);

    // System message
    _addSystemMessage(channelIdHex, '$memberName was removed',
        type: UiMessageType.channelLeave, isChannel: true);

    onStateChanged?.call();
    _log.info('Removed $memberName from channel "${channel.name}"');
    return true;
  }

  @override
  Future<bool> setChannelRole(String channelIdHex, String memberNodeIdHex, String role) async {
    // B-31: delegate to the dual-mode setMemberRole. It broadcasts the atomic
    // MTV3_CHANNEL_ROLE_UPDATE — the receiver patches only the one member's role +
    // ownerNodeIdHex (_handleChannelRoleUpdateV3). The previous body broadcast a
    // CHANNEL_INVITE (full member-list rebuild via _broadcastChannelUpdate), which
    // races on the receiver: after an ownership transfer the freshly-promoted
    // owner's node could fire its first role change before the INVITE rebuilt its
    // local channel, so its owner-guard rejected the change (gui-40 40b.17).
    // Both GUI in-process callers (home_screen, chat_screen) and the IPC path now
    // share this atomic route.
    return setMemberRole(channelIdHex, memberNodeIdHex, role);
  }

  Uint8List _computeChannelMembershipHash(
      int epoch, String channelIdHex, Map<String, ChannelMemberInfo> members) {
    final sorted = members.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final parts = <int>[];
    final epochBytes = ByteData(8)..setUint64(0, epoch, Endian.little);
    parts.addAll(epochBytes.buffer.asUint8List());
    parts.addAll(hexToBytes(channelIdHex));
    for (final e in sorted) {
      parts.addAll(hexToBytes(e.key));
      parts.addAll(utf8.encode(e.value.role));
    }
    return SodiumFFI().sha256(Uint8List.fromList(parts));
  }

  /// Build a signed CHANNEL_INVITE payload from current channel state.
  Uint8List _buildSignedChannelInviteBytes(ChannelInfo channel) {
    final invite = proto.ChannelInvite()
      ..channelId = hexToBytes(channel.channelIdHex)
      ..channelName = channel.name
      ..inviterId = identity.nodeId
      ..isPublic = channel.isPublic
      ..isAdult = channel.isAdult
      ..language = channel.language;
    if (channel.description != null) invite.channelDescription = channel.description!;
    for (final m in channel.members.values) {
      invite.members.add(proto.GroupMemberV3()
        ..nodeId = hexToBytes(m.nodeIdHex)
        ..displayName = m.displayName
        ..role = m.role
        ..ed25519PublicKey = m.ed25519Pk ?? Uint8List(0)
        ..x25519PublicKey = m.x25519Pk ?? Uint8List(0)
        ..mlKemPublicKey = m.mlKemPk ?? Uint8List(0));
    }
    invite.membershipEpoch = Int64(channel.membershipEpoch);
    final hash = _computeChannelMembershipHash(
        channel.membershipEpoch, channel.channelIdHex, channel.members);
    invite.membershipHash = hash;
    invite.membershipSigEd25519 =
        SodiumFFI().signEd25519(hash, identity.ed25519SecretKey);
    invite.membershipSigMlDsa =
        OqsFFI().mlDsaSign(hash, identity.mlDsaSecretKey);
    return Uint8List.fromList(invite.writeToBuffer());
  }

  /// Broadcast updated channel member list to all members via CHANNEL_INVITE.
  Future<void> _broadcastChannelUpdate(ChannelInfo channel) async {
    final channelId = hexToBytes(channel.channelIdHex);
    final inviteBytes = _buildSignedChannelInviteBytes(channel);
    bool anyFailed = false;
    for (final m in channel.members.values.toList()) {
      if (m.nodeIdHex == identity.userIdHex) continue;
      final (x25519Pk, mlKemPk, ed25519Pk) = _resolveMemberKeys(m.nodeIdHex,
          memberX25519Pk: m.x25519Pk, memberMlKemPk: m.mlKemPk, memberEd25519Pk: m.ed25519Pk);
      if (x25519Pk == null || mlKemPk == null) continue;
      final ok = await sendToUser(
        recipientUserId: hexToBytes(m.nodeIdHex),
        messageType: proto.MessageTypeV3.MTV3_CHANNEL_INVITE,
        payload: inviteBytes,
        groupId: channelId,
        recipientX25519PkOverride: x25519Pk,
        recipientMlKemPkOverride: mlKemPk,
        recipientEd25519PkOverride: ed25519Pk,
      );
      if (!ok) {
        // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
        _log.debug('CHANNEL_UPDATE broadcast: no route to ${m.nodeIdHex.substring(0, 8)} (${m.displayName})');
        _pendingMembershipResends
            .putIfAbsent(channel.channelIdHex, () => {})
            .add(m.nodeIdHex);
        anyFailed = true;
      }
    }
    // S366: ONE row for THIS channel instead of the whole stock.
    if (anyFailed) _persistMembershipResend(channel.channelIdHex);
    _log.info('Broadcast channel update for "${channel.name}" to ${channel.members.length - 1} members');
  }

  // ── Public Channel Operations (delegated to ChannelModerationService) ──

  @override
  Future<List<ChannelIndexEntry>> searchPublicChannels({
    String? query,
    String? language,
    bool? includeAdult,
  }) => _moderation.searchPublicChannels(query: query, language: language, includeAdult: includeAdult);

  @override
  Future<bool> publishChannelToIndex(String channelIdHex) async {
    final channel = _channels[channelIdHex];
    if (channel == null || !channel.isPublic) return false;
    if (channel.ownerNodeIdHex != identity.userIdHex) return false;

    _channelIndex.upsert(ChannelIndexEntry(
      channelIdHex: channelIdHex,
      name: channel.name,
      language: channel.language,
      category: channel.category,
      isAdult: channel.isAdult,
      description: channel.description,
      subscriberCount: channel.members.length,
      badBadgeLevel: channel.badBadgeLevel,
      badBadgeSince: channel.badBadgeSince,
      correctionSubmitted: channel.correctionSubmitted,
      ownerNodeIdHex: channel.ownerNodeIdHex,
      createdAt: channel.createdAt,
    ));
    // S366: `upsert` writes its ONE row itself.
    _log.info('Published channel "${channel.name}" to index');
    return true;
  }

  // ── Moderation (delegated to ChannelModerationService) ─────────

  @override
  Future<bool> reportChannel(String channelIdHex, int category, List<String> evidencePostIds, {String? description}) =>
      _moderation.reportChannel(channelIdHex, category, evidencePostIds, description: description);
  @override
  Future<bool> reportPost(String channelIdHex, String postId, int category, {String? description}) =>
      _moderation.reportPost(channelIdHex, postId, category, description: description);
  @override
  List<JuryRequest> get pendingJuryRequests => _moderation.pendingJuryRequestsList;
  @override
  Future<Map<String, dynamic>> getChannelModerationInfo(
          String channelIdHex) async =>
      _moderation.getChannelModerationInfo(channelIdHex);
  @override
  Future<bool> dismissPostReport(String channelIdHex, String reportId) =>
      _moderation.dismissPostReport(channelIdHex, reportId);
  @override
  Future<bool> submitBadgeCorrection(String channelIdHex, {String? newName, String? newDescription}) =>
      _moderation.submitBadgeCorrection(channelIdHex, newName: newName, newDescription: newDescription);
  @override
  Future<bool> contestCsamHide(String channelIdHex) =>
      _moderation.contestCsamHide(channelIdHex);
  @override
  Future<bool> submitJuryVote(String juryId, String reportId, int vote, {String? reason}) =>
      _moderation.submitJuryVote(juryId, reportId, vote, reason: reason);
  @override
  Future<bool> joinPublicChannel(String channelIdHex) =>
      _moderation.joinPublicChannel(channelIdHex);

  // ── End moderation delegation ─────────────────────────────────
  /// Check if caller has permission for channel action.
  bool _hasChannelPermission(ChannelInfo channel, String action) {
    // System channels (§9.5): zero-owner, any member can post
    if (SystemChannels.isSystemChannel(channel.channelIdHex)) {
      if (action == 'post') return true;
      return false;
    }

    final myMember = channel.members[identity.userIdHex];
    if (myMember == null) return false;

    switch (action) {
      case 'post':
        return myMember.role == 'owner' || myMember.role == 'admin';
      case 'invite':
        return myMember.role == 'owner' || myMember.role == 'admin';
      case 'remove':
        return myMember.role == 'owner' || myMember.role == 'admin';
      case 'change_role':
        return myMember.role == 'owner';
      case 'config':
        return myMember.role == 'owner' || myMember.role == 'admin';
      default:
        return false;
    }
  }

  // ── Profile Picture ─────────────────────────────────────────────

  @override
  String? get profilePictureBase64 => _profilePictureBase64;

  @override
  Future<bool> setProfilePicture(String? base64Jpeg) async {
    // Validate size (max 64KB decoded)
    if (base64Jpeg != null) {
      final bytes = base64Decode(base64Jpeg);
      if (bytes.length > 64 * 1024) {
        _log.warn('Profile picture too large: ${bytes.length} bytes (max 64KB)');
        return false;
      }
    }

    _profilePictureBase64 = base64Jpeg;
    _saveProfilePicture();

    // Broadcast PROFILE_UPDATE (picture + description) to all accepted contacts
    _broadcastProfileUpdate();

    onStateChanged?.call();
    _log.info('Profile picture ${base64Jpeg != null ? "set" : "removed"}, broadcast to ${acceptedContacts.length} contacts');
    return true;
  }

  /// One-time sweeper for the at-rest user content from S362.
  ///
  /// Without it the switch only protected what is written from now on —
  /// the profile picture, the self-description and the wording of every already
  /// transcribed voice message would have stayed lying open in the profile.
  ///
  /// The run is cheap and may run at every start: if no
  /// plaintext lies there (any more), it costs three `existsSync`. It is therefore deliberately
  /// NOT secured via a marker file — a marker would skip a
  /// run that failed last time on an unreadable ciphertext,
  /// and the plaintext would stay lying forever.
  ///
  /// Order and abort safety stand in [PlaintextSweep].
  void _sweepPlaintextUserContent() {
    for (final (path, toJson) in <(String, Map<String, dynamic> Function(String))>[
      // The wording of spoken messages. Content is already JSON.
      ('$profileDir/voice_transcriptions.json', PlaintextSweep.asJson),
      // The own profile picture, base64 JPEG, max. 64 KB decoded.
      //
      // S366: picture and self-description now lie in the storage
      // (area `profile`), so there is no writer any more for these two files.
      // The sweeper stays nonetheless,
      // because its statement is a different one from "is still read": it
      // says "under this name there lies no plaintext in this profile".
      // Striking it here would mean leaving a plaintext remnant found
      // from the time before S362 lying open — and precisely
      // the remnant that nobody touches any more and that therefore
      // nobody notices any more either. The paths stand literally, because the
      // getters with the file path have been dropped.
      ('$profileDir/profile_picture.b64', PlaintextSweep.asText('b64')),
      // The own self-description, max. 500 characters.
      ('$profileDir/profile_description.txt', PlaintextSweep.asText('text')),
      // ── S362, section 2.2: the interaction graph ───────────────────
      //
      // `reputation.json` carries an interaction graph: for every ever
      // seen node identifier counters and ban state. Whoever has the disk
      // reads from it WITH WHOM and HOW OFTEN this device had to do
      // — even without being able to decrypt a single message.
      //
      // S366: ITS WRITER IS DELETED.
      // `lib/core/moderation/peer_reputation.dart` had not a single
      // caller in `lib/` and served solely the V3 line; the
      // owner ordered the deletion. The sweeper stays
      // nonetheless, and precisely because of that: WITHOUT a writer no
      // read ever triggers a migration either, a `reputation.json` found in a legacy profile
      // would thus stay lying open forever
      // and nobody would ever find it again. This line is the
      // only reason why that does not happen.
      ('$profileDir/reputation.json', PlaintextSweep.asJson),
    ]) {
      final outcome = PlaintextSweep.sweepOne(
        fileEnc: _fileEnc,
        path: path,
        toJson: toJson,
        log: _log,
      );
      if (outcome == SweepOutcome.failed) {
        _log.warn('S362 sweep: $path could not be moved into the '
            'encrypted store — the plaintext version '
            'still lies open in the profile.');
      }
    }
  }

  /// One-time sweeper for the media attachments (S362 variant B).
  ///
  /// Counterpart of [_sweepPlaintextUserContent], only streaming: an
  /// attachment may be 500 MB large (see `maxFileSize` in
  /// [sendMediaMessage]), so it does not fit into memory as a whole.
  /// Order and abort safety stand in [MediaSweep].
  ///
  /// Like the sister run it is NOT secured via a marker file:
  /// a marker would skip a run that failed last time on a file,
  /// and its plaintext would stay lying forever.
  /// If nothing lies in plaintext any more, the run costs one
  /// `listSync` over one directory.
  void _sweepPlaintextMedia() {
    final dir = '$profileDir/media';
    if (!Directory(dir).existsSync()) return;
    final r = MediaSweep.sweepDirectory(dir, log: _log);
    if (r.touched > 0 || r.tmpRemoved > 0) {
      _log.info('S362 media cleaner: $r');
    }
    if (r.failed > 0) {
      _log.warn('S362 media sweep: ${r.failed} attachments could NOT '
          'be moved into the encrypted store — they still lie '
          'open in $dir.');
    }
  }

  // ── The own profile in the storage (§21.4.1, S366) ─────────────────
  //
  // Picture and self-description share ONE area with TWO
  // keys. That is the reason why `putEntry`/`removeEntry`
  // stand here and not `replaceArea` as with the settings: a
  // `replaceArea('profile', …)` with only one of the two entries
  // would delete the respective other along with it. The user sets picture and text
  // independently of each other.
  //
  // Deleting (`removeEntry`) is the actual improvement here
  // over the file path: there it needed `deleteFile`, because a
  // leftover `.enc.old` side piece would have brought back a removed picture on the
  // next start from crash recovery. A
  // deleted row has no side piece.
  static const String _areaProfile = 'profile';
  static const String _profileKeyImage = 'picture';
  static const String _profileKeyText = 'description';

  void _loadProfilePicture() {
    try {
      // S362: the own profile picture lay as a bare base64 file in the profile.
      // S366: it lies in the encrypted storage, under the same
      // seed-derived key as the conversations.
      final json = store.loadArea(_areaProfile)[_profileKeyImage];
      final b64 = json?['b64'] as String?;
      _profilePictureBase64 = (b64 == null || b64.isEmpty) ? null : b64;
    } catch (e) {
      _log.debug('Failed to load profile picture: $e');
    }
  }

  void _saveProfilePicture() {
    try {
      if (_profilePictureBase64 != null) {
        store.putEntry(_areaProfile, _profileKeyImage,
            {'b64': _profilePictureBase64});
      } else {
        store.removeEntry(_areaProfile, _profileKeyImage);
      }
    } catch (e) {
      _log.debug('Failed to save profile picture: $e');
    }
  }

  // ── Profile Description ─────────────────────────────────────────────

  @override
  String? get profileDescription => _profileDescription;

  @override
  Future<bool> setProfileDescription(String? description) async {
    if (description != null && description.length > 500) {
      _log.warn('Profile description too long: ${description.length} chars (max 500)');
      return false;
    }

    _profileDescription = (description != null && description.isEmpty) ? null : description;
    _saveProfileDescription();

    // Broadcast PROFILE_UPDATE with description to all accepted contacts
    _broadcastProfileUpdate();

    onStateChanged?.call();
    _log.info('Profile description ${_profileDescription != null ? "set" : "removed"}');
    return true;
  }

  void _loadProfileDescription() {
    try {
      // S362: the self-description lay as a bare text file in the profile.
      // S366: it lies in the storage, area `profile`, key
      // `description` — next to the picture, but as its own row.
      final json = store.loadArea(_areaProfile)[_profileKeyText];
      final text = (json?['text'] as String?)?.trim();
      _profileDescription = (text == null || text.isEmpty) ? null : text;
    } catch (e) {
      _log.debug('Failed to load profile description: $e');
    }
  }

  void _saveProfileDescription() {
    try {
      if (_profileDescription != null) {
        store.putEntry(_areaProfile, _profileKeyText,
            {'text': _profileDescription});
      } else {
        store.removeEntry(_areaProfile, _profileKeyText);
      }
    } catch (e) {
      _log.debug('Failed to save profile description: $e');
    }
  }

  // ── Media Settings ──────────────────────────────────────────────────

  @override
  MediaSettings get mediaSettings => _mediaSettings;

  @override
  Future<bool> setPort(int newPort) async {
    // The in-process path — this is what Android and iOS take, where no IPC
    // handler sits in front to reject anything. Until now it checked NOTHING,
    // not even the LAN-discovery port: on mobile the settings dialog was the
    // only guard in existence, and a guard that lives solely in the UI is one
    // refactor away from being gone.
    //
    // S376: `isReservedLanPort` instead of `== lanDiscoveryPort` — both
    // fixed LAN ports (41338 and 41340) are checked via the one
    // place of definition in `link/data_port.dart`.
    if (DataPort.isReservedLanPort(newPort) ||
        IdentityManager.isBrowserBlockedPort(newPort)) {
      _log.warn('setPort refused $newPort: '
          '${DataPort.isReservedLanPort(newPort)
              ? 'reserved for the LAN sockets (§4.5.2)'
              : 'refused by browsers — invitation links would be dead'}');
      return false;
    }
    try {
      // FORMERLY `node.changePort(newPort)` — the V3 transport rebound the
      // socket. Gap G-15: the V4.1 node holds its port
      // (`attachV41`, one port per node) and has no rebind command.
      // The value is saved and takes effect at the next start; the
      // running node stays on its old port.
      _log.warn('setPort: the running node stays on port $port — V4.1 '
          'cannot rebind the socket at runtime (gap G-15). '
          '$newPort applies from the next start.');
      port = newPort;
      IdentityManager().updatePort(newPort);
      onStateChanged?.call();
      return true;
    } on SocketException {
      return false;
    }
  }

  @override
  void updateMediaSettings(MediaSettings settings) {
    _mediaSettings = settings;
    _saveMediaSettings();
    onStateChanged?.call();
    _log.info('Media settings updated');
  }

  // ── The settings areas of the storage (§21.4.1, S366) ─────────────
  //
  // S362, section 2.3: the three settings files lay open in the
  // profile. Individually each is harmless; together they are a DEVICE PROFILE
  // — the auto-download limits reveal whether a mobile contract
  // is being economised on, the link preview setting whether this device
  // may reach into the open network at all, and the
  // multi-interface mode how many network paths it has.
  //
  // S366: they no longer lie each in their own
  // `FileEncryption` file, but in the encrypted storage
  // (`messages.db`, table `state`). Thus one file per setting
  // drops out of the profile — and with it the statement that its mere
  // EXISTENCE already carries: whoever sees the directory reads off the
  // file list which settings this device has ever
  // touched at all. In the storage that is encrypted too.
  //
  // PER AREA EXACTLY ONE ENTRY under the key `_`. That is
  // right here and not the full-state writer that `replaceArea`
  // warns against: a setting is a state with fixed fields, not a
  // growing collection. `replaceArea` writes it in ONE transaction —
  // a crash in the middle leaves either the old or the new
  // state, never a mixture.
  //
  // NO DATA-LOSS LATCH, and that is a decision, not a
  // gap: if one of these settings is lost, the
  // default value applies (`MediaSettings()`, `LinkPreviewSettings()`,
  // `MultiInterfaceMode.auto`), and the user sets it again. With
  // `invites` it is different — there a latch stands
  // (`InviteStore.load`), because an empty book would assign the same
  // invitation key a second time.
  static const String _areaMediaSettings = 'media_settings';
  static const String _areaLinkPreviewSettings = 'link_preview_settings';
  static const String _areaMultiInterfaceMode = 'multi_interface_mode';

  /// The key of the one entry in a settings area.
  static const String _settingKey = '_';

  void _loadMediaSettings() {
    try {
      final json =
          store.loadArea(_areaMediaSettings)[_settingKey];
      if (json != null) {
        _mediaSettings = MediaSettings.fromJson(json);
      }
    } catch (e) {
      _log.debug('Failed to load media settings: $e');
    }
  }

  void _saveMediaSettings() {
    try {
      store.replaceArea(_areaMediaSettings,
          {_settingKey: _mediaSettings.toJson()});
    } catch (e) {
      _log.debug('Failed to save media settings: $e');
    }
  }

  @override
  bool get serveBinaryUpdates => true;

  // ── Link Preview Settings ────────────────────────────────────────────

  @override
  LinkPreviewSettings get linkPreviewSettings => _linkPreviewSettings;

  @override
  void updateLinkPreviewSettings(LinkPreviewSettings settings) {
    _linkPreviewSettings = settings;
    _linkPreviewFetcher = LinkPreviewFetcher(
      settings: _linkPreviewSettings,
      log: (msg) => _log.debug(msg),
    );
    _saveLinkPreviewSettings();
    onStateChanged?.call();
    _log.info('Link preview settings updated');
  }

  void _loadLinkPreviewSettings() {
    try {
      final json =
          store.loadArea(_areaLinkPreviewSettings)[_settingKey];
      if (json != null) {
        _linkPreviewSettings = LinkPreviewSettings.fromJson(json);
      }
    } catch (e) {
      _log.debug('Failed to load link preview settings: $e');
    }
  }

  void _saveLinkPreviewSettings() {
    try {
      store.replaceArea(_areaLinkPreviewSettings,
          {_settingKey: _linkPreviewSettings.toJson()});
    } catch (e) {
      _log.debug('Failed to save link preview settings: $e');
    }
  }

  // ── Multi-Interface Send (Architecture §23.2) ──────────────────────

  @override
  MultiInterfaceMode get multiInterfaceMode => _multiInterfaceMode;

  @override
  Future<void> setMultiInterfaceMode(MultiInterfaceMode mode) async {
    _multiInterfaceMode = mode;
    _saveMultiInterfaceMode();
    // FORMERLY `node.transport.setMultiInterfaceMode(mode)` (§23.2: send
    // over several interfaces simultaneously). The V3 transport has
    // fallen, the V4.1 node holds one socket per family and knows
    // no multi-interface choice. **Gap G-6**: the setting is
    // saved and displayed, but NOT applied.
    _log.warn('Multi-interface mode ${mode.name} saved, but not '
        'applied — V4.1 has no multi-interface choice (gap G-6).');
    onStateChanged?.call();
  }

  void _loadMultiInterfaceMode() {
    try {
      final json =
          store.loadArea(_areaMultiInterfaceMode)[_settingKey];
      if (json != null) {
        _multiInterfaceMode = MultiInterfaceMode.modeFromString(
            json['mode'] as String?);
      }
    } catch (e) {
      _log.debug('Failed to load multi-interface mode: $e');
    }
  }

  void _saveMultiInterfaceMode() {
    try {
      store.replaceArea(_areaMultiInterfaceMode, {
        _settingKey: {
          'mode': MultiInterfaceMode.modeToString(_multiInterfaceMode),
        }
      });
    } catch (e) {
      _log.debug('Failed to save multi-interface mode: $e');
    }
  }

  // ── NFC Contact Exchange ─────────────────────────────────────────────

  @override
  Uint8List? get ed25519PublicKey => identity.ed25519PublicKey;

  @override
  Uint8List? get mlDsaPublicKey => identity.mlDsaPublicKey;

  @override
  Uint8List? get x25519PublicKey => identity.x25519PublicKey;

  @override
  Uint8List? get mlKemPublicKey => identity.mlKemPublicKey;

  @override
  Uint8List? get profilePicture =>
      _profilePictureBase64 != null ? base64Decode(_profilePictureBase64!) : null;

  @override
  Uint8List signEd25519(Uint8List message) =>
      SodiumFFI().signEd25519(message, identity.ed25519SecretKey);

  @override
  bool verifyEd25519(Uint8List message, Uint8List signature, Uint8List publicKey) =>
      SodiumFFI().verifyEd25519(message, signature, publicKey);

  // `addNfcContact` stood here (V3 NFC: `accepted` contact without request and
  // without response, `verified`). Dropped with S388-BAU-KONTAKT — the NFC screen
  // exchanges invitation cards and redeems them (§15.5).

  /// Update own display name and broadcast to all contacts.
  ///
  /// Persists the new name to `identities.json` via [IdentityManager] so it
  /// survives daemon restarts. Matches the Identity record by `profileDir`
  /// (stable, unique per identity). If no matching record is found, the
  /// in-memory + broadcast path still runs so that at least contacts learn
  /// the new name in the current session.
  @override
  void updateDisplayName(String newName) {
    final mgr = IdentityManager();
    final match = mgr.loadIdentities().firstWhere(
          (i) => i.profileDir == identity.profileDir,
          orElse: () => Identity(
            id: '',
            displayName: '',
            profileDir: '',
            port: 0,
            createdAt: DateTime.now(),
          ),
        );
    if (match.id.isNotEmpty) {
      mgr.renameIdentity(match.id, newName);
    } else {
      _log.warn('updateDisplayName: no Identity record for profileDir=${identity.profileDir}; skipping persist');
    }
    displayName = newName;
    _broadcastProfileUpdate();
    _publishIdentityRegistryIfPossible();
    onStateChanged?.call();
    _log.info('Display name updated to "$newName", broadcast sent');
  }

  /// Broadcast profile update (picture + description + name) to all accepted contacts.
  void _broadcastProfileUpdate() {
    final profileData = proto.ProfileData()
      ..updatedAtMs = Int64(DateTime.now().millisecondsSinceEpoch)
      ..displayName = displayName;
    if (_profilePictureBase64 != null) {
      profileData.profilePicture = base64Decode(_profilePictureBase64!);
    }
    if (_profileDescription != null) {
      profileData.description = _profileDescription!;
    }

    final payload = Uint8List.fromList(profileData.writeToBuffer());

    for (final contact in _contacts.values) {
      if (contact.status != 'accepted') continue;
      if (contact.x25519Pk == null || contact.mlKemPk == null) continue;
      _detachedSend('MTV3_PROFILE_UPDATE', sendToUser(
        recipientUserId: contact.nodeId,
        messageType: proto.MessageTypeV3.MTV3_PROFILE_UPDATE,
        payload: payload,
      ));
    }
  }

  // ── Guardian recovery: REFUSED, NOT CONCEALED ────────────────
  //
  // `GuardianService` was deleted with the CUT (v4_1 §13.8: no social
  // recovery; the Shamir shares travelled as `FRAGMENT_STORE` infra
  // frames over the V3 DHT). The four members stand in
  // `ICleonaService` and therefore cannot simply disappear.
  //
  // § NUMBER CORRECTED (S361): here it said "V4 §6.8". That is the
  // v4_0 numbering; on the V4.1 line §6 is "Liveness" and a §6.8
  // does not exist there. The same wording stands in §13.8 "Limits of
  // recovery": "No set of other people can restore an identity — in no
  // number, in no combination, under no threshold."
  //
  // THEY DO NOT RETURN "NO" AS IF NOTHING HAD BEEN SET UP. A
  // hard-wired `false` told the UI "you have no
  // recovery guardians" — for a user who HAS set up five,
  // that was a false statement about his backup (gap G-8).

  /// Measured once and remembered. The stores can no longer arise
  /// anew — the only writer `_saveGuardianList()` fell with
  /// `guardian_service.dart` (`91b566dd`) —, and the getter
  /// runs along on EVERY state snapshot
  /// (`cleona_service_state.dart:82`). Before S361 it wrote an error line into the log there on every
  /// pass.
  LegacyGuardianDeposit? _legacyGuardianDeposit;

  /// The measurement for both readers — state snapshot and guard.
  LegacyGuardianDeposit get legacyGuardianDeposit =>
      _legacyGuardianDeposit ??= LegacyGuardianDeposit.probe(profileDir);

  /// Whether a guardian setup from before the
  /// CUT lies in THIS profile directory — measured, not claimed.
  ///
  /// **That is no promise of a working backup.** Social
  /// recovery does not exist in V4.1 (§13.8); a `true` means
  /// exclusively "legacy data of a setup that
  /// no longer carries still lies here" — exactly the information the UI
  /// needs in order to warn instead of reassure.
  ///
  /// **`false` does not mean "you never had guardians".** The guardian list lay
  /// device-locally and was never reconciled between devices (no
  /// guardian type among the fifteen twin types,
  /// `proto/app_payloads.proto:985-1019`); a second device regularly reports
  /// `false`. Where the measurement was not possible at all, it also falls
  /// to `false` here — the interface is `bool` and cannot
  /// carry the third value.
  ///
  /// **The UI therefore does NOT read this getter**, but
  /// `LegacyGuardianDeposit.probe` directly and distinguishes there
  /// `none` / `present` / `unknown`
  /// (`lib/core/recovery/legacy_guardian_state.dart:36-48`).
  @override
  bool get isGuardianSetUp =>
      legacyGuardianDeposit.ownGuardians == LegacyGuardianTrace.present;

  @override
  Future<bool> setupGuardians(List<String> guardianNodeIds) async {
    _log.error('setupGuardians: refused — v4_1 §13.8 no longer knows social '
        'recovery, and the carrier (Shamir shares over the '
        'V3 DHT) fell with the CUT (gap G-8). The UI '
        'has not offered the path since S361; if this '
        'call reaches us anyway, it comes from a foreign IPC client.');
    return false;
  }

  @override
  Future<Map<String, dynamic>?> triggerGuardianRestore(
      String contactNodeIdHex) async {
    _log.error('triggerGuardianRestore: cancelled — see [setupGuardians] '
        '(gap G-8).');
    return null;
  }

  @override
  Future<bool> confirmGuardianRestore(
      String ownerNodeIdHex, String recoveryMailboxIdHex) async {
    _log.error('confirmGuardianRestore: cancelled — see [setupGuardians] '
        '(gap G-8).');
    return false;
  }

  // ── Calls (delegated to CallService) ──────────────────────────────

  /// Hangs the D socket of the V4.1 NODE onto the call transport of this
  /// identity (§17.4).
  ///
  /// NO `@override` and not in `ICleonaService`: this is not an
  /// application operation, but a seam of the setup. It is called
  /// exactly once per identity, from `attachV41` — the only place where
  /// node and service are present at the same time. The UI and the IPC
  /// do not see it.
  ///
  /// `null` deregisters it; that is the path when shutting down the node.
  void attachCallPlaneD(CallPlaneD? planeD) => _calls.attachPlaneD(planeD);

  @override
  CallInfo? get currentCall => _calls.currentCall;
  @override
  Future<CallInfo?> startCall(String peerNodeIdHex, {bool video = false}) =>
      _calls.startCall(peerNodeIdHex, video: video);
  @override
  Future<void> acceptCall() => _calls.acceptCall();
  @override
  Future<void> rejectCall({String reason = 'busy'}) =>
      _calls.rejectCall(reason: reason);
  @override
  Future<void> hangup() => _calls.hangup();
  @override
  bool get isMuted => _calls.isMuted;
  @override
  void toggleMute() => _calls.toggleMute();
  @override
  bool get isSpeakerEnabled => _calls.isSpeakerEnabled;
  @override
  void toggleSpeaker() => _calls.toggleSpeaker();
  @override
  bool get isVideoMuted => _calls.isVideoMuted;
  @override
  void toggleVideoMute() => _calls.toggleVideoMute();
  @override
  Future<bool> switchCamera() => _calls.switchCamera();

  @override
  void Function(GroupCallInfo info)? onIncomingGroupCall;
  @override
  void Function(GroupCallInfo info)? onGroupCallStarted;
  @override
  void Function(GroupCallInfo info)? onGroupCallEnded;

  @override
  GroupCallInfo? get currentGroupCall => _calls.currentGroupCall;
  @override
  Future<GroupCallInfo?> startGroupCall(String groupIdHex) =>
      _calls.startGroupCall(groupIdHex);
  @override
  Future<void> acceptGroupCall() => _calls.acceptGroupCall();
  @override
  Future<void> rejectGroupCall({String reason = 'busy'}) =>
      _calls.rejectGroupCall(reason: reason);
  @override
  Future<void> leaveGroupCall() => _calls.leaveGroupCall();

  Future<void> rejoinGroupCall() => _calls.rejoinGroupCall();

  // The four accessors below buffer on a plain field instead of delegating
  // straight to `_calls` because `_calls` is `late` and only assigned inside
  // startService(): main.dart's `_wireServiceCallbacks` sets these (at least
  // `createVideoEngine`) before `await service.startService()` runs, which
  // would otherwise throw LateInitializationError. The buffered value is
  // handed to `_calls` in startService (see there) once it exists.
  void Function(String senderHex, int? textureId)? _bufferedOnGroupVideoTexture;
  void Function(String senderHex, int? textureId)? get onGroupVideoTexture =>
      _bufferedOnGroupVideoTexture;
  set onGroupVideoTexture(void Function(String, int?)? v) {
    _bufferedOnGroupVideoTexture = v;
    if (_callsReady) _calls.onGroupVideoTexture = v;
  }

  /// §10.4 stage 7 (V3.2): CallKit / self-managed `ConnectionService`.
  /// Buffered like [createVideoEngine] and for the same reason — the
  /// `MethodChannel` implementation pulls in `dart:ui`, so it is constructed
  /// by a Flutter-context caller and handed down. Leaving it unset keeps
  /// `CallService`'s no-op, which is the correct state in the daemon.
  CallIntegration? _bufferedCallIntegration;
  CallIntegration? get callIntegration => _bufferedCallIntegration;
  set callIntegration(CallIntegration? v) {
    _bufferedCallIntegration = v;
    if (_callsReady && v != null) _calls.callIntegration = v;
  }

  /// §10.4 "Session behaviour" (S367): forwards a `SessionBehaviourChannel
  /// .onInterruption`-sourced event to the active call's `SessionBehaviour`
  /// — see `CallService.feedVoiceInterruptionEvent`'s field doc. A no-op
  /// before `_calls` exists (no call can be active yet) or outside an active
  /// voice session — never throws, the OS bridge has no notion of Cleona's
  /// call state.
  void feedVoiceInterruptionEvent(VoiceEventRecord event) {
    if (_callsReady) _calls.feedVoiceInterruptionEvent(event);
  }

  /// Whether the current call is considered interrupted by the OS audio
  /// session right now (architecture §10.4). `false` before `_calls` exists.
  bool get isCallInterrupted => _callsReady && _calls.isCallInterrupted;

  dynamic Function(Uint8List callKey, void Function(Uint8List) onVideoFrame)?
      _bufferedCreateVideoEngine;
  dynamic Function(Uint8List callKey, void Function(Uint8List) onVideoFrame)?
      get createVideoEngine => _bufferedCreateVideoEngine;
  set createVideoEngine(
      dynamic Function(Uint8List, void Function(Uint8List))? v) {
    _bufferedCreateVideoEngine = v;
    if (_callsReady) _calls.createVideoEngine = v;
  }

  void Function(Uint8List serializedVideoFrame)?
      _bufferedOnVideoFrameReceived;
  void Function(Uint8List serializedVideoFrame)? get onVideoFrameReceived =>
      _bufferedOnVideoFrameReceived;
  set onVideoFrameReceived(void Function(Uint8List)? v) {
    _bufferedOnVideoFrameReceived = v;
    if (_callsReady) _calls.onVideoFrameReceived = v;
  }

  void Function()? _bufferedOnKeyframeRequested;
  void Function()? get onKeyframeRequested => _bufferedOnKeyframeRequested;
  set onKeyframeRequested(void Function()? v) {
    _bufferedOnKeyframeRequested = v;
    if (_callsReady) _calls.onKeyframeRequested = v;
  }

  void sendKeyframeRequest() => _calls.sendKeyframeRequest();

  // ── Network Change ─────────────────────────────────────────────────

  /// Reads the own reachable addresses anew.
  ///
  /// V4.1 counterpart of `node.localIps`. `dialableLocalAddresses()` is
  /// asynchronous (it queries the interfaces), [localIps] must not
  /// be — hence the cache.
  Future<void> _refreshLocalAddresses() async {
    try {
      _localAddresses = await dialableLocalAddresses();
    } catch (e) {
      _log.debug('Local addresses could not be determined: $e');
    }
  }

  @override
  /// [triggerNodeReset] HAS BECOME INEFFECTIVE and only remains in the
  /// call contract (`ICleonaService`, IPC server, `main.dart`).
  ///
  /// It passed through to the node and skipped there the
  /// "already known" guard. The node is gone with the CUT; the
  /// network change is handled in V4.1 by the delivery layer itself
  /// (`lib/core/tagline/` — entry cascade and partner choice run on
  /// their own tick). What remains of it for the SERVICE stands below: reading
  /// the own addresses anew and triggering the edge-triggered resends.
  Future<void> onNetworkChanged(
      {bool triggerNodeReset = true, bool force = false}) async {
    await _refreshLocalAddresses();
    // ── AND THE RUNNING CALLS (§17.4, S376/A-2) ──────────────────
    //
    // BEFORE everything else, and the order is the point: a call is
    // the only thing in this service with a loss deadline of 10 s
    // (§17.4). Everything else here — rendezvous, resends, the
    // node — tolerates seconds; a call does not.
    //
    // Without a running call the call sends nothing (working rule 5).
    if (_callsReady) _calls.onNetworkChanged();
    // §5.1 — edge for the first CR: shorten a running backoff.
    shortenCrBackoffOnEdge('network-change');
    // §5.8: the membership resends go via [sendToUser] and
    // thus via the V4.1 switch — this edge continues to carry.
    unawaited(_flushPendingMembershipResends());
    // The §5.8 outbox drain likewise stood here. It fell with the
    // V3 cascade (gap G-4, see `cleona_service_pure.dart`).

    // ── AND THE V4.1 NODE (§22.6, S360) ───────────────────────────
    //
    // UNTIL NOW IT LEARNED NOTHING. This method refreshed a local
    // address list, reported it to the rendezvous and shortened a
    // backoff — the node kept running unchanged, with sessions into the
    // old network, with observed addresses from the old network and with
    // an announcement pointing to the old network. On a phone
    // that is the normal case, not the special case: WLAN after mobile data and
    // back, several times a day.
    //
    // ── AND `triggerNodeReset` CONTROLS IT AGAIN (S376, P5 find. 5) ──
    //
    // HERE IT SAID: "`triggerNodeReset` does NOT control it. … there is exactly
    // ONE node per process and exactly ONE seam to it. Hanging it here on
    // a parameter that stems from the V3 era would be the
    // drift that the cut has just eliminated."
    //
    // The sentence is right and the conclusion was wrong. There is exactly
    // one seam — but N SERVICES that reach through it. All three
    // entry points call this method IN A LOOP over their
    // identities; without the parameter the node part ran three times with N = 3:
    // three session teardowns, three priority announcements,
    // three LAN calls for ONE event (working rule 5). The second and
    // third pass thereby tore down sessions that the partner choice
    // had just rebuilt after the first.
    //
    // The parameter does exactly what its contract in
    // `service_interface.dart` has always said: "Daemon-style callers
    // that already invoke `node.onNetworkChanged()` once for all
    // identities should pass `false`". The three entry points ALWAYS PASSED
    // it — it was just no longer read.
    //
    // THE DEFAULT VALUE STAYS `true`, and that is essential: a
    // caller that really is single and still needs the node part
    // gets it without doing anything. `importPeerBundle` is exactly
    // such a one — there the one service is the whole occasion.
    final nodeSeam = triggerNodeReset ? v41OnNetworkChanged : null;
    if (nodeSeam != null) {
      // NOT AWAITED, but HANDLED. The body determines
      // network interfaces — that can take seconds on a device with a just
      // changed network, and this method is called from
      // a connectivity event. An uncaught error
      // from an `unawaited` killed the whole daemon in S348 (B-3);
      // hence the `catchError`.
      unawaited(nodeSeam().catchError((Object e) {
        _log.warn('V4.1 network change failed: $e');
      }));
    }
  }

  // ── Persistence ────────────────────────────────────────────────────

  // Cached FileEncryption instance — uses seed-derived key per §3.7 step 5.
  FileEncryption? _fileEncCached;
  FileEncryption get _fileEnc {
    if (_fileEncCached != null) return _fileEncCached!;
    final baseDir = '${AppPaths.home}/.cleona';
    // §3.7: derive per-identity FileEncryption key from master seed
    final seed = identity.masterSeed;
    final idx = identity.hdIndex;
    final Uint8List? key = (seed != null && idx != null)
        ? HdWallet.deriveFileEncKey(seed, idx)
        : null;
    _fileEncCached = FileEncryption(baseDir: baseDir, key: key);
    return _fileEncCached!;
  }

  // ── The storage for messages (S366, §4.5.3 form 1 / §21.4.1) ────
  //
  // EXPRESSLY WITHOUT FALLBACK. `FileEncryption` falls back to a
  // random `db.key` file NEXT TO the ciphertext if no
  // key was passed through — S362 measured eleven such places.
  // For the storage this fallback would be a step backwards:
  // it carries the entire message stock, and a key that lies
  // unencrypted next to it does not protect it. If the seed is missing,
  // it therefore THROWS and does not evade.
  /// S366, second part: THE OPENER HAS LAIN IN THE IDENTITY SINCE `keys.json`.
  /// Here stood `MessageStore.open(...)` — that held as long as
  /// only service collections were switched. `IdentityContext.initKeys`
  /// however runs before this service exists, and needs the same
  /// file. Two openers would have meant two handles on one file;
  /// that is why [IdentityContext.storeOrNull] now owns the storage, and
  /// here only the forwarding stands.
  ///
  /// THE ASSURANCE STAYS UNCHANGED: if the seed is missing, it THROWS
  /// and does not evade to a substitute key (§21.4.1).
  MessageStore? _storeCached;

  /// The storage, or `null` if this identity has no
  /// seed-derived key.
  ///
  /// For the few places where "there is no storage" is a
  /// DIFFERENT statement from "the storage cannot be read". Everywhere
  /// else [store] applies and thus the assurance from §21.4.1.
  MessageStore? get storeOrNull => _storeCached ?? identity.storeOrNull;

  @override
  MessageStore get store {
    if (_storeCached != null) return _storeCached!;
    final s = identity.storeOrNull;
    if (s == null) {
      throw StateError(
          'MessageStore: no master seed for identity ${identity.userIdHex} '
          '— the store is NOT opened with a substitute key '
          '(§21.4.1; the db.key fallback of FileEncryption does not apply here)');
    }
    return s;
  }

  /// Guards only: sets the storage from outside.
  ///
  /// THERE IS EXACTLY ONE CASE THAT NEEDS IT, and it is not a
  /// convenience: a suite that MUST measure an identity WITHOUT an HD wallet.
  /// `smoke_rotation_transition_window` is such a one —
  /// since S361 `v41PairKeyFor` takes the founding secret key,
  /// and that changes on a rotation only if the identity
  /// has no seed. But precisely to this identity [store] refuses
  /// (rightly) opening. Without this path the suite would have to either
  /// take an HD identity — then it measures something other than
  /// what its name says — or rebuild the storage, and a rebuilt
  /// proof checks the rebuild.
  ///
  /// In operation there is no caller: [store] derives its
  /// key from the seed and does not evade (§21.4.1).
  @visibleForTesting
  set storeForTesting(MessageStore s) => _storeCached = s;

  /// Closes the storage. Callable separately from `stop()`, so that an
  /// identity switch does not leave the file open.
  void closeStore() {
    _storeCached?.close();
    _storeCached = null;
    identity.closeStore();
  }

  /// Writes ONE message into the storage (§21.4.1).
  ///
  /// Is called at every place that creates or changes a `UiMessage`.
  /// **That is intentional and not an oversight:** a `dirty` flag
  /// via setters in `UiMessage` would be more convenient, but would not catch the eleven
  /// places that change COLLECTIONS (`msg.deliveredBy.add(...)`,
  /// `msg.reactions[...]`) — there the field is never assigned, only its
  /// content. A tracking that sees 24 of 35 places looks like
  /// completeness and would silently lose the rest.
  void persistMessage(String conversationId, UiMessage msg) {
    if (_disposed) return;
    try {
      final conv = conversations[conversationId];
      if (conv != null) _upsertConversationRow(conversationId, conv);
      store.upsertMessage(
        id: hexToBytes(msg.id),
        convId: hexToBytes(conversationId),
        sender: msg.senderNodeIdHex.isEmpty
            ? null
            : hexToBytes(msg.senderNodeIdHex),
        ts: msg.timestamp.millisecondsSinceEpoch,
        type: msg.type.wireValue,
        status: msg.status.wireName,
        isOutgoing: msg.isOutgoing,
        text: msg.text,
        extra: messageExtraForStore(msg),
      );
    } catch (e) {
      _log.warn('persistMessage($conversationId/${msg.id}): $e');
    }
  }

  /// Removes a message from the storage (§21.5: `SECURE_DELETE` is
  /// compiled in, the pages are overwritten).
  void forgetMessage(String messageId) {
    if (_disposed) return;
    try {
      store.deleteMessage(hexToBytes(messageId));
    } catch (e) {
      _log.warn('forgetMessage($messageId): $e');
    }
  }

  void _upsertConversationRow(String id, Conversation conv) {
    store.upsertConversation(
      id: hexToBytes(id),
      displayName: conv.displayName,
      lastActivity: conv.lastActivity.millisecondsSinceEpoch,
      isGroup: conv.isGroup,
      isChannel: conv.isChannel,
      isFavorite: conv.isFavorite,
      unreadCount: conv.unreadCount,
      profilePicture: conv.profilePictureBase64 == null
          ? null
          : Uint8List.fromList(utf8.encode(conv.profilePictureBase64!)),
      // LEGACY FINDING, fixed along here: `notificationsEnabled` and
      // `notificationSoundName` were read on LOADING and never written on
      // SAVING — the choice per conversation survived
      // no restart. The same held for `config` and the pending
      // proposal. They now lie in `extra` and come along.
      extra: {
        if (conv.notificationsEnabled != null)
          'notificationsEnabled': conv.notificationsEnabled,
        if (conv.notificationSoundName != null)
          'notificationSoundName': conv.notificationSoundName,
        'config': conv.config.toJson(),
        if (conv.pendingConfigProposal != null)
          'pendingConfigProposal': conv.pendingConfigProposal!.toJson(),
        if (conv.pendingConfigProposer != null)
          'pendingConfigProposer': conv.pendingConfigProposer,
      },
    );
  }

  /// Makes sure that [conversationId] has its complete history
  /// in memory (S366, stage B).
  ///
  /// At start a conversation carries only its youngest message. Every
  /// place that needs more than the last row — searching a message by
  /// identifier, running over the history, counting — calls this
  /// beforehand. The second call is free.
  @override
  void ensureLoaded(String conversationId) {
    final conv = conversations[conversationId];
    if (conv == null || conv.messagesLoaded) return;
    try {
      final loaded = store
          .messagesOf(hexToBytes(conversationId))
          .map(messageFromStoreRow)
          .toList();
      conv.messages
        ..clear()
        ..addAll(loaded);
      conv.messagesLoaded = true;
      conv.totalMessages = conv.messages.length;
    } catch (e) {
      // Do NOT mark as loaded: a failed lookup must
      // not lead to the history afterwards COUNTING as empty and
      // a full overwrite fixing it in place.
      _log.warn('ensureLoaded($conversationId): $e');
    }
  }

  /// Load all conversations completely. Only for the few operations
  /// that really need the total stock (expiry check,
  /// recovery response) — not as a convenient substitute for
  /// [ensureLoaded], because here the memory peak comes back.
  @override
  void ensureAllLoaded() {
    for (final id in conversations.keys.toList()) {
      ensureLoaded(id);
    }
  }

  /// Builds a `UiMessage` from a row of the storage. Counterpart of
  /// [_messageExtra]: the columns carry what is searched and sorted
  /// by, `extra` the rest — together they again yield the form that
  /// `UiMessage.fromJson` expects.
  static UiMessage messageFromStoreRow(Map<String, Object?> r) {
    final j = <String, dynamic>{
      'id': bytesToHex(r['id'] as Uint8List),
      'conversationId': bytesToHex(r['convId'] as Uint8List),
      'sender': r['sender'] == null ? '' : bytesToHex(r['sender'] as Uint8List),
      'text': r['text'],
      'timestamp': r['ts'],
      'type': r['type'],
      'status': r['status'],
      'isOutgoing': r['isOutgoing'],
      ...?(r['extra'] as Map<String, dynamic>?),
    };
    return UiMessage.fromJson(j);
  }

  /// The rarer fields as JSON — they lie in the column `extra`
  /// and are compressed there as soon as the probe gains 10 % (§4.5.3).
  /// What is missing here is not forgotten, but has its own column.
  static Map<String, dynamic>? messageExtraForStore(UiMessage msg) {
    final j = msg.toJson();
    for (final field in const [
      'id', 'conversationId', 'sender', 'text', 'timestamp',
      'type', 'status', 'isOutgoing',
      // §21.6/S392-B3: the archive state is a PROJECTION from the
      // archive index and must NOT be written along here. It travels
      // via IPC, because the UI on Linux/Windows/macOS is a
      // separate process — as a second copy in the message storage
      // however it would be a fact with two sources that age
      // separately: after a stage advance the index knows `mini`,
      // the row in `messages` would continue to stand at `thumbnail`, and the
      // UI would show something different depending on the path (snapshot or history).
      // `applyArchiveView` stamps both paths freshly.
      'archiveTier', 'archiveShareUrl', 'archivedAt', 'archiveMiniBase64',
    ]) {
      j.remove(field);
    }
    // Null values out. `UiMessage.toJson` writes `filePath` UNCONDITIONALLY,
    // even if it is null — thereby `extra` was never empty, the
    // short circuit below dead code, and every row carried 17 B JSON for
    // a null value. With 150 000 messages that is around 2.5 MB that
    // carry nothing. `fromJson` reads missing keys as
    // null anyway, so the round trip stays the same.
    j.removeWhere((_, v) => v == null);
    return j.isEmpty ? null : j;
  }

  void _loadContacts() {
    // S366: from the storage. The tombstones lie in an OWN
    // area instead of under the special key `_deleted` of the same
    // map — in a table with (area, key) no
    // namespace trick is needed any more, and the special handling
    // "skip keys with `_`" falls away.
    try {
      for (final id in store.loadArea('contacts_deleted').keys) {
        _deletedContacts.add(id);
      }
      for (final entry in store.loadArea('contacts').entries) {
        _contacts[entry.key] = ContactInfo.fromJson(entry.value);
      }
      _contactsLoaded = true;
      _log.info('Loaded ${_contacts.length} contacts, ${_deletedContacts.length} deleted');
      _auditContactTrustAnchors();
    } catch (e) {
      _log.warn('Failed to load contacts: $e');
    }
  }

  /// §8.3 — load-time audit of every contact's trust anchor.
  ///
  /// Two invariants, both observed as real failure modes:
  ///   1. The anchor must not be one of OUR OWN user keys. There is no state
  ///      in which that is legitimate — you cannot verify a peer's signature
  ///      with your own key — yet S280 produced exactly that via a DhtRpc
  ///      response mix-up, and nothing noticed for days.
  ///   2. The hybrid pair is all-or-nothing. Older code wrote `ed25519Pk`
  ///      without `mlDsaPk`; such a record can never verify again, because
  ///      `decryptAndVerifyInner` requires both.
  ///
  /// Violations quarantine the record (see [ContactInfo.trustAnchorQuarantined])
  /// instead of clearing it — clearing would open the §8.1.1 "Restluecke A"
  /// silent-refill path to the next incoming CR.
  void _auditContactTrustAnchors() {
    // FORMERLY `node.hostedUserEd25519Pks` — ALL identities of this
    // node. Without a shared node a service only knows its own.
    //
    // THE CHECK THEREBY BECOMES NARROWER, NOT WRONG: it is supposed to prevent
    // an OWN key from landing as trust anchor of a CONTACT
    // (§8.3). The frequent case — the own identity with which
    // this service runs — is still caught. No longer caught
    // is the rare case "key of a DIFFERENT own identity
    // of the same daemon"; for that a node-wide
    // view would again be needed. Noted as part of gap G-16.
    final ownPks = <Uint8List>[
      identity.ed25519PublicKey,
      identity.foundingEd25519Pk,
    ];
    var changed = 0;
    for (final entry in _contacts.entries) {
      final c = entry.value;
      if (c.trustAnchorQuarantined) continue;
      final ed = c.ed25519Pk;
      final ml = c.mlDsaPk;

      if (ed != null &&
          ed.isNotEmpty &&
          ownPks.any((own) => constantTimeEquals(ed, own))) {
        c.trustAnchorQuarantined = true;
        c.trustAnchorQuarantineReason = 'anchor equals a locally hosted identity key';
        _log.error('CONTACT ANCHOR CORRUPT: ${entry.key.substring(0, 8)} '
            'carries one of OUR OWN user keys — quarantined. Every message '
            'from this contact would fail user-sig verify silently.');
        changed++;
        continue;
      }

      final edSet = ed != null && ed.isNotEmpty;
      final mlSet = ml != null && ml.isNotEmpty;
      if (edSet != mlSet) {
        c.trustAnchorQuarantined = true;
        c.trustAnchorQuarantineReason =
            'hybrid pair incomplete (ed25519=${edSet ? "set" : "missing"}, '
            'mlDsa=${mlSet ? "set" : "missing"})';
        _log.error('CONTACT ANCHOR CORRUPT: ${entry.key.substring(0, 8)} has '
            'a half-written hybrid key pair — quarantined, it can never '
            'verify.');
        changed++;
      }
    }
    if (changed > 0) {
      _saveContacts();
      _log.warn('§8.3: $changed contact(s) quarantined by the anchor audit — '
          're-verification required before they can be used again.');
    }
  }

  /// §8.3 — the single place that writes a contact's user trust anchor.
  ///
  /// Enforces the same two invariants as [_auditContactTrustAnchors] BEFORE
  /// the write, so a corrupt anchor is never persisted in the first place.
  /// Returns true when the anchor was written.
  ///
  /// [source] names the caller for the log (CR, CRR, key-rotation, restore,
  /// D1 self-heal, …) — the S280 post-mortem could not tell which path had
  /// written the bad record.
  bool _setContactTrustAnchor(
    ContactInfo contact,
    String contactHex,
    Uint8List? edPk,
    Uint8List? mlDsaPk, {
    required String source,
  }) {
    final edOk = edPk != null && edPk.isNotEmpty;
    final mlOk = mlDsaPk != null && mlDsaPk.isNotEmpty;
    if (edOk != mlOk) {
      _log.warn('§8.3: refusing half-written anchor for '
          '${contactHex.substring(0, 8)} from $source '
          '(ed25519=${edOk ? "set" : "missing"}, mlDsa=${mlOk ? "set" : "missing"})');
      return false;
    }
    if (!edOk) return false; // nothing to write

    if (constantTimeEquals(edPk, identity.ed25519PublicKey) ||
        constantTimeEquals(edPk, identity.foundingEd25519Pk)) {
      contact.trustAnchorQuarantined = true;
      contact.trustAnchorQuarantineReason =
          'write attempt with a locally hosted identity key ($source)';
      _log.error('§8.3: BLOCKED anchor write for ${contactHex.substring(0, 8)} '
          'from $source — the key is one of ours. Record quarantined.');
      _saveContacts();
      return false;
    }

    // ── §15.2: THE FOUNDING ANCHOR IS RESCUED HERE ─────────────────
    //
    // This line stands BEFORE the overwrite, and that is the core of
    // path A (S361): `contact.ed25519Pk` is the ONLY place where the
    // founding key of an existing contact still lies, and the
    // next line overwrites it. After an accepted
    // `KEY_ROTATION_BROADCAST` it would be gone without replacement — there is no
    // second local source from which one could retrieve it.
    //
    // WHY AT THIS PLACE AND NOT AT THE SEVEN CALLERS: this is
    // the only writer of `ed25519Pk` (see header of
    // `contact_manager.dart`). An anchor that had to be rescued at every caller individually
    // would be lost again at the eighth caller.
    //
    // At the FIRST labelling `contact.ed25519Pk` is still empty and
    // `edPk` itself is the founding value (a brand-new contact has not rotated before
    // its first message). Every later call
    // bounces off [ContactInfo.rememberFoundingAnchor] — exactly that is
    // the promise there.
    if (contact.rememberFoundingAnchor(contact.ed25519Pk ?? edPk)) {
      _log.info('§15.2: founding anchor for ${contactHex.substring(0, 8)} '
          'recorded ($source) — from now on it survives every rotation');
    }
    contact.ed25519Pk = edPk;
    contact.mlDsaPk = mlDsaPk;
    return true;
  }

  /// Contacts whose pair key already stands in the delivery layer.
  ///
  /// Keeps [primeV41Pairs] incremental: `_saveContacts()` has 43 callers,
  /// and computing over all contacts would be per save operation one
  /// key derivation PER CONTACT. `K_AB` hangs on the
  /// founding keys (§15.2) and no longer changes once it
  /// has been formed — a second entry would carry the same value.
  final Set<String> _v41Primed = <String>{};

  /// The pseudo-peers of the armed invitation lines (§15.3.2).
  ///
  /// They are kept so that `armV41InviteLines` can withdraw them.
  /// Without this set the withdrawal would have to search `pairs.peers` by the
  /// prefix — a second truth about the same thing, and
  /// it would drift apart as soon as another path entered a pseudo-peer.
  final Set<String> _v41InviteLines = <String>{};

  void _saveContacts() {
    // ── AND THE DELIVERY LAYER LEARNS OF IT (30.08.) ──────────────────
    //
    // `primeV41Pairs()` previously ran ONLY on hooking in. A contact that
    // only gets its founding anchor later — on completion of a
    // contact request, via an AuthManifest, after a rotation —, never
    // came into the registry afterwards. The harvest skips a pair
    // without `K_AB` silently, so this identity stayed deaf for incoming
    // messages until it sent itself (whereby `sendToUser` enters
    // the pair in passing).
    //
    // HERE, because every change to a contact runs through this funnel
    // — 43 callers, and the alternative would be to find and supplement every single
    // assignment of `ed25519Pk`. Thanks to `_v41Primed` the call is
    // in O(new contacts), not in O(all).
    if (_contactsLoaded) {
      try {
        primeV41Pairs();
      } catch (_) {
        // The delivery layer must never prevent saving the contacts
        // — it is the beneficiary, not the condition.
      }
    }

    // Guard: don't overwrite existing contacts file with empty data
    // if loading failed (decryption error, wrong key, etc.)
    if (!_contactsLoaded && _contacts.isEmpty && _deletedContacts.isEmpty) {
      // S366: the latch asks the storage. On the file it would never have
      // kicked in again after the switch — the same dead latch as
      // with the conversations and in the `_saveEncMap` funnel.
      var present = false;
      try {
        present = store.countArea('contacts') > 0 ||
            store.countArea('contacts_deleted') > 0;
      } catch (e) {
        _log.warn('REFUSED to save contacts — store unreadable: $e');
        return;
      }
      if (present) {
        _log.warn('REFUSED to save empty contacts — load failed but the '
            'store still holds entries. Would cause data loss!');
        return;
      }
    }
    try {
      final json = <String, Map<String, dynamic>>{};
      for (final entry in _contacts.entries) {
        json[entry.key] = entry.value.toJson();
      }
      // `replaceArea` and not `putEntry`: all 39 callers call
      // "save everything", and the contact count practically stays in the
      // range of dozens to hundreds. For a collection that
      // really goes into the thousands, this would be the old error in
      // new clothes — `putEntry` belongs there.
      store.replaceArea('contacts', json);
      store.replaceArea('contacts_deleted',
          {for (final id in _deletedContacts) id: const <String, dynamic>{}});
      // `_syncTierRegistration()` (DV tier registry) and
      // `_updateRendezvousContacts()` (contact list of the Nostr rendezvous
      // at the service's `RendezvousManager`) stood here. The former is
      // (T) — no distance vector any more. The latter has belonged since S349 to the
      // V4.1 wiring in `attachV41`; the service no longer holds its own
      // rendezvous manager that would have to be updated.
    } catch (e) {
      _log.warn('Failed to save contacts: $e');
    }
  }


  // `_latestWinsTypes` stood here: the kinds for which in the §5.8 outbox
  // only the YOUNGEST entry per (recipient, kind) counted. Its reader was
  // `_addToOutbox`, and that fell with the outbox filler
  // (gap G-4).

  /// AP-4: deadline after which an outgoing, never acknowledged message falls to
  /// `expired`.
  ///
  /// Checked lazily when opening the conversation (chat screen). No
  /// network traffic — pure timestamp comparison.
  ///
  /// **14 days, no longer 7.** The old number was the lifetime of the
  /// S&F/Reed-Solomon fragments; those no longer exist in V4.1. The new one
  /// is the default TTL of the delivery layer: v4_1 §21.8 "Time bound for the
  /// delivery-layer share: **max. 14 days** (default TTL) or **31 days**
  /// (management types)", §22.5.1 `TtlClass ttl = TtlClass.standard // 14 d
  /// default`. Had the check stayed at 7 days, the
  /// UI would have shown `expired` for a week for cells that still
  /// lie on the tag line and can be harvested.
  static const int _placementTtlMs = 14 * 24 * 60 * 60 * 1000; // 14 days

  void _loadConversations() {
    // §21.4.1: from the storage. The latch from before — "file there, but
    // not decryptable, so do NOT overwrite" — is
    // stronger here: `MessageStore.open` throws if the key does not match,
    // and without an open storage `_saveConversationsNow` cannot write anything
    // at all. `_conversationsLoaded` nonetheless stays the guard,
    // so that a load error does not fix an empty conversation picture in place.
    try {
      for (final row in store.allConversations()) {
        final id = bytesToHex(row['id'] as Uint8List);
        final extra = (row['extra'] as Map<String, dynamic>?) ?? const {};
        final pic = row['profilePicture'];
        // STAGE B: only the YOUNGEST message. It is everything the
        // conversation list needs for display; the history comes via
        // `ensureLoaded` as soon as someone needs it.
        final last = store.lastMessageOf(hexToBytes(id));
        conversations[id] = Conversation(
          id: id,
          displayName: row['displayName'] as String,
          messages: last == null ? [] : [messageFromStoreRow(last)],
          lastActivity:
              DateTime.fromMillisecondsSinceEpoch(row['lastActivity'] as int),
          isGroup: row['isGroup'] as bool,
          isChannel: row['isChannel'] as bool,
          isFavorite: row['isFavorite'] as bool,
          unreadCount: row['unreadCount'] as int,
          profilePictureBase64:
              pic == null ? null : utf8.decode(pic as Uint8List),
          config: extra['config'] == null
              ? null
              : ChatConfig.fromJson(extra['config'] as Map<String, dynamic>),
          notificationsEnabled: extra['notificationsEnabled'] as bool?,
          notificationSoundName: extra['notificationSoundName'] as String?,
        );
        final conv = conversations[id]!;
        // The history is still missing — exactly that is the gain of this stage.
        conv.messagesLoaded = false;
        // The NUMBER costs nothing (a `count(*)` in the storage) and
        // spares every statistic the full load.
        conv.totalMessages = store.countMessagesOf(hexToBytes(id));
        if (extra['pendingConfigProposal'] != null) {
          conv.pendingConfigProposal = ChatConfig.fromJson(
              extra['pendingConfigProposal'] as Map<String, dynamic>);
        }
        conv.pendingConfigProposer = extra['pendingConfigProposer'] as String?;
      }
      _conversationsLoaded = true;
      _log.info('Loaded ${conversations.length} conversations from the store');
      return;
    } catch (e) {
      _log.warn('Failed to load conversations from the store: $e');
      return;
    }
  }

  void _recoverStuckMedia() {
    var resetCount = 0;
    for (final conv in conversations.values) {
      ensureAllLoaded();
      for (final msg in conv.messages) {
        if (msg.mediaState == MediaDownloadState.downloading) {
          msg.mediaState = MediaDownloadState.announced;
          msg.filePath = null;
          persistMessage(conv.id, msg);
          resetCount++;
        } else if (msg.mediaState == MediaDownloadState.completed &&
            msg.filePath != null &&
            // S362: `existsEitherWay`. With `File(...).existsSync()` it would
            // be true after the switch for EVERY media message that
            // "the file is missing" — the attachment now lies under
            // `<path>.cmenc`. This branch would have nulled
            // all `filePath` at the first start and marked all media as
            // downloadable again.
            !MediaStore.instance.existsEitherWay(msg.filePath!)) {
          msg.mediaState = MediaDownloadState.announced;
          msg.filePath = null;
          persistMessage(conv.id, msg);
          resetCount++;
        }
      }
    }
    if (resetCount > 0) {
      _log.info('Media recovery: reset $resetCount stuck downloads to announced');
      _saveConversations();
    }
  }

  /// S366: from the area [kPendingMediaSendsArea] of the storage instead of from
  /// `pending_media_sends.json`.
  ///
  /// The file named in PLAINTEXT the storage location and the file name of every
  /// pending attachment. The attachment itself has lain encrypted as `.cmenc`
  /// since S362 — its NAME lay open next to it, and a file name
  /// often says more than the content.
  void _loadPendingMediaSends() {
    try {
      final j = store.loadArea(kPendingMediaSendsArea)
          [kSingleStateKey];
      if (j == null) return;
      for (final entry in j.entries) {
        final filePath = entry.value;
        // A path that no longer exists is not taken over —
        // the same behaviour as before.
        if (filePath is String && File(filePath).existsSync()) {
          _pendingMediaSends[entry.key] = filePath;
        }
      }
      if (_pendingMediaSends.isNotEmpty) {
        _log.info('Loaded ${_pendingMediaSends.length} pending media sends');
      }
    } catch (e) {
      _log.warn('Failed to load pending media sends: $e');
    }
  }

  /// Post an Android system notification for an incoming message.
  /// L5 gate: suppressed when the Flutter Activity is in foreground.
  void _postAndroidNotification(String senderName, String text, String conversationId) {
    if (onPostNotificationAndroid == null) return;
    if (_isAppResumed) return;
    try {
      onPostNotificationAndroid!(senderName, text, conversationId);
    } catch (e) {
      _log.warn('postAndroidNotification failed: $e');
    }
  }

  /// Feed `CalendarManager.syncBirthdaysFromContacts()` from the local
  /// contact book. Produces yearly all-day events for every contact with
  /// birthdayMonth + birthdayDay set. Idempotent — existing birthday events
  /// are updated in place keyed by contactId. §23.4.
  void _syncCalendarBirthdays() {
    final map = <String, Map<String, dynamic>>{};
    for (final entry in _contacts.entries) {
      final c = entry.value;
      if (c.status != 'accepted') continue;
      if (c.birthdayMonth == null || c.birthdayDay == null) continue;
      map[entry.key] = {
        'displayName': c.effectiveName,
        'birthdayMonth': c.birthdayMonth,
        'birthdayDay': c.birthdayDay,
        'birthdayYear': c.birthdayYear,
      };
    }
    if (map.isEmpty) return;
    try {
      calendarManager.syncBirthdaysFromContacts(map);
      _log.info('Birthday calendar sync: ${map.length} contact birthday(s)');
    } catch (e) {
      _log.warn('Birthday calendar sync failed: $e');
    }
  }

  /// Set or clear the birthday metadata on a contact. Triggers an immediate
  /// re-sync of the calendar birthday events.
  @override
  bool setContactBirthday(String nodeIdHex,
      {int? month, int? day, int? year}) {
    final contact = _contacts[nodeIdHex];
    if (contact == null) return false;
    contact.birthdayMonth = month;
    contact.birthdayDay = day;
    contact.birthdayYear = year;
    _saveContacts();
    _syncCalendarBirthdays();
    return true;
  }

  /// §15.10 (D2 = a): "never use as a fixed neighbour". Stored on the
  /// contact record and handed to the delivery layer at once
  /// ([CleonaServiceMycelium.myceliumNeverFixedNeighbourApply]), which
  /// checks the fixed neighbour seats at that edge. Without an attached
  /// mailbox the mark is handed over at the attach.
  @override
  bool setContactNeverFixedNeighbour(String nodeIdHex, bool never) {
    final contact = _contacts[nodeIdHex];
    if (contact == null) return false;
    if (contact.neverFixedNeighbour != never) {
      contact.neverFixedNeighbour = never;
      _saveContacts();
    }
    myceliumNeverFixedNeighbourApply(contact);
    onStateChanged?.call();
    return true;
  }

  /// Recalculate total unread count and notify badge listeners.
  void _updateBadgeCount() {
    if (onBadgeCountChanged == null) return;
    final total = conversations.entries
        .where((e) => !SystemChannels.isSystemChannel(e.key))
        .fold<int>(0, (sum, e) => sum + e.value.unreadCount);
    onBadgeCountChanged!(total);
  }

  /// Save all persistent state (conversations, contacts, groups, channels).
  /// Called by the app lifecycle observer when going to background on Android.
  void saveState() {
    _saveConversationsTimer?.cancel();
    _saveConversationsTimer = null;
    _saveConversationsPending = false;
    _saveConversationsNow();
    _saveContacts();
    _saveGroups();
    _saveChannels();
  }

  /// Finding 1 (§8.1): the suppression set rides in the SAME file as the dedup
  /// set, under a second key. Both must survive a receiver restart together —
  /// a surviving dedup entry paired with a lost suppression entry re-acks the
  /// next L1 retry of a deliberately dropped CONTACT_REQUEST, sets the
  /// sender's `lastAckedAt`, and parks its CR retry for 24h: exactly the
  /// deadlock the drop prevents. Same file, same call sites — no extra
  /// write frequency (working rule #5 applies to disk I/O too).
  /// The area in the table `state` (S366).
  ///
  /// BOTH SETS LIE IN THE SAME AREA, because they already lay in
  /// the same file before — and for the reason the block
  /// above names: a surviving dedup set next to a lost
  /// suppression set is exactly the deadlock case. A shared
  /// area makes this coupling visible in the carrier and allows the
  /// latch below to check it.
  static const String areaProcessedIds = 'processed_msg_ids';
  static const String _keyDedup = 'dedup';
  static const String _keySuppressed = 'suppressed';

  /// S366: snapshot into the storage instead of rewriting a file.
  ///
  /// DELIBERATELY `putEntry` AND NOT `replaceArea`: the two rows are
  /// capped (4096 + 1024), so NOT growing — but `replaceArea`
  /// would first delete the area entirely. Two `putEntry` calls
  /// overwrite in place instead; the area is never
  /// empty in between.
  ///
  /// BOTH ROWS ARE ALWAYS WRITTEN, including the empty one. Thus
  /// the area holds exactly 0 or 2 rows after every write, and
  /// `countArea` is a reliable statement about completeness —
  /// on which the latch below relies.
  void _saveProcessedMessageIds() {
    if (_processedMessageIds.isEmpty && _suppressedReceiptMsgIds.isEmpty) return;
    try {
      store.putEntry(areaProcessedIds, _keyDedup,
          {'ids': _processedMessageIds.toList()});
      store.putEntry(areaProcessedIds, _keySuppressed,
          {'ids': _suppressedReceiptMsgIds.toList()});
    } catch (e) {
      _log.warn('Failed to save processed message IDs: $e');
    }
  }

  /// Loads both sets (§8.1 finding 1).
  ///
  /// ── THE DATA-LOSS LATCH, AND WHY IT DOES NOT THROW HERE ────
  ///
  /// There was none here — a read error fell silently to "empty". For
  /// BOTH sets together that is also defensible: the repeat detection
  /// starts over, in the worst case an old message is processed a
  /// second time.
  ///
  /// For ONE of the two it is not. A surviving dedup row next to a lost
  /// suppression row acknowledges the next L1 repetition of a
  /// deliberately discarded CONTACT_REQUEST, sets `lastAckedAt` at the
  /// sender and parks its repetition for 24 h — the deadlock that the
  /// discard is meant to prevent (§8.1 finding 1).
  ///
  /// The latch therefore measures, at the new carrier, the statement "the
  /// area is COMPLETELY readable": if `countArea` holds more rows than
  /// `loadArea` could unpack, it falls back to the DOCUMENTED SAFE
  /// state — both sets empty — instead of to the half one.
  /// It deliberately does not throw: an unreadable repeat lock must not
  /// prevent a start, and the empty state is the same as at the very
  /// first start.
  void _loadProcessedMessageIds() {
    try {
      final lines = store.loadArea(areaProcessedIds);
      final present = store.countArea(areaProcessedIds);
      if (present == 0) return;

      if (lines.length < present) {
        _log.error(
            'Replay lock: the area `$areaProcessedIds` holds '
            '$present row(s), of which only ${lines.length} '
            'can be unpacked — BOTH sets stay empty. A half '
            'restore (dedup without suppression) would acknowledge the '
            'next repetition of a discarded CONTACT_REQUEST and '
            'park its repetition for 24 h (§8.1 finding 1).');
        _processedMessageIds.clear();
        _suppressedReceiptMsgIds.clear();
        return;
      }

      final ids = lines[_keyDedup]?['ids'] as List<dynamic>?;
      if (ids != null) {
        for (final id in ids) {
          _processedMessageIds.add(id as String);
        }
        while (_processedMessageIds.length > _processedMessageIdsCap) {
          _processedMessageIds.remove(_processedMessageIds.first);
        }
      }
      // Cap also on load, so that a grown or manipulated
      // stock does not hold on to unbounded memory.
      final suppressed =
          lines[_keySuppressed]?['ids'] as List<dynamic>?;
      if (suppressed != null) {
        for (final id in suppressed) {
          _suppressedReceiptMsgIds.add(id as String);
        }
        while (_suppressedReceiptMsgIds.length > _suppressedReceiptMsgIdsCap) {
          _suppressedReceiptMsgIds.remove(_suppressedReceiptMsgIds.first);
        }
      }
      _log.info('Loaded ${_processedMessageIds.length} processed message IDs '
          '(replay protection), ${_suppressedReceiptMsgIds.length} '
          'receipt-suppressed IDs (§8.1 finding 1)');
    } catch (e) {
      _log.warn('Failed to load processed message IDs: $e');
    }
  }

  Timer? _saveConversationsTimer;
  bool _saveConversationsPending = false;

  void _saveConversations() {
    _saveConversationsPending = true;
    _saveConversationsTimer ??= Timer(const Duration(seconds: 2), () {
      _saveConversationsTimer = null;
      if (_saveConversationsPending) {
        _saveConversationsPending = false;
        _saveConversationsNow();
      }
    });
  }

  void _saveConversationsNow() {
    // Safety net: never overwrite an existing conversations file before the
    // load has completed. Before _conversationsLoaded, `conversations` can only
    // ever be a partial/seeded set (e.g. the §9.5 system channels), so
    // persisting it would clobber the real chats still on disk. This is the
    // data-loss root cause (seed-before-load); the ordering is also fixed in
    // start(), and this guard makes any future pre-load save harmless too.
    // NOTE: the guard deliberately does NOT also require `conversations.isEmpty`
    // — the original bug was a pre-load save with a NON-empty (seeded) map.
    if (!_conversationsLoaded) {
      // S366: the latch asks the STORE, no longer the file.
      //
      // Up to here it checked `conversations.json.enc` — which since the
      // switch-over is never written again. So it would never have
      // triggered again, and the protection that once prevented a real
      // data loss (seed-before-load) would have silently vanished.
      // Exactly the class of error a rebuild leaves behind when one only
      // checks whether the NEW works, instead of also what the OLD held.
      var present = false;
      try {
        present = store.conversationCount > 0;
      } catch (e) {
        // Store cannot be opened: fail closed. Not saving is
        // always right when we do not know what is on the disk.
        _log.warn('REFUSED to save conversations — store unreadable: $e');
        return;
      }
      if (present) {
        _log.warn('REFUSED to save conversations before load completed — '
            'the store already holds conversations (prevents pre-load '
            'overwrite)');
        return;
      }
    }
    // §21.4.1: only the CONVERSATIONS now. The messages have lived in the
    // store since S366 and arrive there via `persistMessage` — one row
    // per change instead of the whole file on every change.
    try {
      for (final entry in conversations.entries) {
        _upsertConversationRow(entry.key, entry.value);
      }
    } catch (e) {
      _log.warn('Failed to save conversations: $e');
    }
  }

  // ── Group Persistence ─────────────────────────────────────────

  /// Generic encrypted map loader with data-loss guard: if the `.enc` file
  /// exists but couldn't be decrypted, load is refused (not just skipped) so
  /// a later save can't overwrite still-encrypted-but-unreadable data.
  void _loadEncMap<T>(
    String filename,
    Map<String, T> target,
    T Function(Map<String, dynamic>) fromJson, {
    required void Function(bool) setLoaded,
    String label = 'items',
  }) {
    // S366: from the STORE, no longer from one file per collection.
    // `filename` is now the area name (`groups`, `channels`, …) —
    // it stays the same identifier so that the origin is readable.
    try {
      final entries = store.loadArea(filename);
      for (final entry in entries.entries) {
        target[entry.key] = fromJson(entry.value);
      }
      setLoaded(true);
      _log.info('Loaded ${target.length} $label');
    } catch (e) {
      // Do NOT mark as loaded: otherwise empty counts as stock, and the
      // latch in `_saveEncMap` would let a full overwrite through.
      _log.warn('Failed to load $label: $e');
    }
  }

  /// Generic encrypted map saver with data-loss guard: refuses to overwrite
  /// an on-disk `.enc` file with an empty map when load never succeeded.
  void _saveEncMap<T>(
    String filename,
    Map<String, T> source,
    Map<String, dynamic> Function(T) toJson, {
    required bool loaded,
    String label = 'items',
    void Function()? onSaved,
  }) {
    // S366: the latch asks the STORE, no longer the file.
    //
    // Up to here it checks `File('$filename.json.enc').existsSync()`.
    // These files are no longer written — the latch would thus have
    // silently vanished, just like the one for the conversations. Both
    // times the same error of a rebuild: checking whether the NEW works,
    // and overlooking what the OLD held.
    if (!loaded && source.isEmpty) {
      var present = false;
      try {
        present = store.countArea(filename) > 0;
      } catch (e) {
        _log.warn('REFUSED to save $label — store unreadable: $e');
        return;
      }
      if (present) {
        _log.warn('REFUSED to save empty $label — load failed but the store '
            'still holds entries');
        return;
      }
    }
    try {
      final json = <String, Map<String, dynamic>>{};
      for (final entry in source.entries) {
        json[entry.key] = toJson(entry.value);
      }
      // `replaceArea` and not `putEntry`: the callers of this funnel
      // hold manageable collections (groups, channels) and call
      // "save everything". For GROWING collections that is the wrong
      // way — `putEntry` belongs there, otherwise full writing is
      // back, just in the store instead of in a file.
      store.replaceArea(filename, json);
      onSaved?.call();
    } catch (e) {
      _log.warn('Failed to save $label: $e');
    }
  }

  void _loadGroups() => _loadEncMap<GroupInfo>(
      'groups', _groups, GroupInfo.fromJson,
      setLoaded: (v) => _groupsLoaded = v, label: 'groups');

  void _saveGroups() => _saveEncMap<GroupInfo>(
      'groups', _groups, (g) => g.toJson(),
      loaded: _groupsLoaded, label: 'groups');

  // ── Channel Persistence ──────────────────────────────────────

  void _loadChannels() => _loadEncMap<ChannelInfo>(
      'channels', _channels, ChannelInfo.fromJson,
      setLoaded: (v) => _channelsLoaded = v, label: 'channels');

  void _saveChannels() => _saveEncMap<ChannelInfo>(
      'channels', _channels, (c) => c.toJson(),
      // `onSaved: _syncTierRegistration` entfaellt — DV-Tier-Registry (T).
      loaded: _channelsLoaded, label: 'channels');

  // ── System Channels (§9.5) ────────────────────────────────────────

  void _seedSystemChannels() {
    bool changed = false;

    for (final entry in [
      (SystemChannels.bugLogChannelIdHex, 'Cleona Bug Log'),
      (SystemChannels.featureReqChannelIdHex, 'Feature Requests'),
    ]) {
      final (idHex, name) = entry;
      if (!_channels.containsKey(idHex)) {
        _channels[idHex] = ChannelInfo(
          channelIdHex: idHex,
          name: name,
          ownerNodeIdHex: SystemChannels.zeroOwnerHex,
          isPublic: true,
          isAdult: false,
          language: 'multi',
        );
        changed = true;
        _log.info('Seeded system channel: $name');
      }
      if (!conversations.containsKey(idHex)) {
        conversations[idHex] = Conversation(
          id: idHex,
          displayName: name,
          isChannel: true,
          notificationsEnabled: notificationSound.settings.defaultChannelNotify,
        );
        changed = true;
      }
    }

    // Reset stale unread counts on system channels (F10 fix — they should
    // never contribute to badge count or sort to the top).
    for (final idHex in [SystemChannels.bugLogChannelIdHex, SystemChannels.featureReqChannelIdHex]) {
      final conv = conversations[idHex];
      if (conv != null && conv.unreadCount > 0) {
        conv.unreadCount = 0;
        changed = true;
      }
    }

    if (changed) {
      _saveChannels();
      _saveConversations();
    }
  }

  void _evictSystemChannels() {
    _evictChannel(
      SystemChannels.bugLogChannelIdHex,
      SystemChannels.maxChannelStorageBytes,
      oldestFirst: true,
    );
    _evictChannel(
      SystemChannels.featureReqChannelIdHex,
      SystemChannels.maxChannelStorageBytes,
      oldestFirst: false,
    );
    // §9.5.7: keep the gossip record store under the same 25 MB cap
    // (strategies match §9.5.5: bug log oldest-first, FR fewest-net-votes).
    var evicted = 0;
    evicted += _sysChanStore.evictToLimit(SystemChannels.bugLogChannelIdHex);
    evicted +=
        _sysChanStore.evictToLimit(SystemChannels.featureReqChannelIdHex);
    // S366: here stood `if (evicted > 0) _saveSysChanRecords();`.
    // `evictToLimit` now writes its deletions and tombstones itself,
    // row by row — there is nothing to catch up on. `evicted`
    // remains as the return value of the two calls because it carries
    // the log statement of the expiries.
    if (evicted > 0) {
      _log.info('syschan: $evicted record(s) evicted (§9.5.5)');
    }
  }

  void _evictChannel(String channelIdHex, int maxBytes,
      {required bool oldestFirst}) {
    final conv = conversations[channelIdHex];
    ensureLoaded(channelIdHex);
    if (conv == null || conv.messages.isEmpty) return;

    int totalBytes = 0;
    ensureLoaded(channelIdHex);
    for (final msg in conv.messages) {
      totalBytes += msg.text.length;
    }
    if (totalBytes <= maxBytes) return;

    final sorted = List<UiMessage>.from(conv.messages);
    if (oldestFirst) {
      sorted.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    } else {
      // Feature requests: fewest-votes first, then oldest
      sorted.sort((a, b) {
        final aVotes = _featureVoteScore(a);
        final bVotes = _featureVoteScore(b);
        if (aVotes != bVotes) return aVotes.compareTo(bVotes);
        return a.timestamp.compareTo(b.timestamp);
      });
    }

    int removed = 0;
    while (totalBytes > maxBytes && sorted.isNotEmpty) {
      final victim = sorted.removeAt(0);
      totalBytes -= victim.text.length;
      conv.messages.remove(victim);
      removed++;
    }
    if (removed > 0) {
      _saveConversations();
      _log.info('Evicted $removed messages from $channelIdHex (${totalBytes ~/ 1024}KB remaining)');
    }
  }

  int _featureVoteScore(UiMessage msg) {
    try {
      final json = jsonDecode(msg.text);
      if (json is Map && json['pollId'] != null) {
        final poll = pollManager.polls[json['pollId']];
        if (poll != null) {
          int yes = 0, no = 0;
          for (final v in poll.votes.values) {
            if (v.selectedOptions.contains(0)) yes++;
            if (v.selectedOptions.contains(1)) no++;
          }
          return yes - no;
        }
      }
    } catch (_) {}
    return 0;
  }

  // ── §9.5.7 System-Channel Records & Gossip (S119 D1/D2/D3) ─────────

  /// Local record set for the ownerless system channels. Gossip-converged
  /// (SYSCHAN_DIGEST/SUMMARY/WANT/PUSH, BOOT-path InfrastructureFrames).
  late final SystemChannelRecordStore _sysChanStore =
      SystemChannelRecordStore(profileDir: profileDir, store: store);
  bool _sysChanLoaded = false;

  /// §9.5.7 push budget: eager-flood TTL for freshly created/learned records.
  static const int _sysChanPushTtl = 5;

  // `_sysChanFanout` (k=3 random peers per event), `_sysChanSummaryCap`
  // (4000 fingerprints per summary) and `_sysChanPushBatchBytes`
  // (100 KB per batch) stood here — the three tuning knobs of the
  // system-channel gossip. It has fallen (gap G-2, measured
  // 3.17 GB/day without useful share).

  void _loadSysChanRecords() {
    if (_sysChanLoaded) return;
    _sysChanLoaded = true;
    try {
      // S366: from the store (areas `syschan_records` and
      // `syschan_gone`) instead of from `syschan_records.json` — the
      // second-largest file of the field profile (1 838 533 B), which was
      // rewritten entirely on every change.
      _sysChanStore.loadFromStore();
      // Re-bridge stored POSTs into the conversation (idempotent) so the
      // UI list survives a conversations/records divergence.
      for (final chHex in [
        SystemChannels.bugLogChannelIdHex,
        SystemChannels.featureReqChannelIdHex,
      ]) {
        for (final r in _sysChanStore.allRecords(chHex)) {
          if (r.record.kind == SysChanKind.post) _bridgeSysChanPost(r);
        }
      }
    } catch (e) {
      _log.warn('syschan: load failed: $e');
    }
  }

  /// Create, sign, store, UI-bridge and eager-push a system-channel record.
  /// Returns null when the store's own admission rejected it (e.g. foreign
  /// retract target).
  Future<StoredSysChanRecord?> _publishSystemChannelRecord({
    required String channelIdHex,
    required int kind,
    String text = '',
    Uint8List? targetRecordId,
    int voteOption = 0,
  }) async {
    if (!SystemChannels.isSystemChannel(channelIdHex)) return null;
    final record = SystemChannelRecordStore.buildSigned(
      channelId: hexToBytes(channelIdHex),
      kind: kind,
      // Founding binding (§9.5.7): computeUserId(inline pk) == userId. On
      // linked devices the delegated sub-key would break the binding —
      // records are signed with the identity's user keys.
      authorUserId: identity.userId,
      ed25519Pk: identity.ed25519PublicKey,
      ed25519Sk: identity.ed25519SecretKey,
      mlDsaPk: identity.mlDsaPublicKey,
      mlDsaSk: identity.mlDsaSecretKey,
      text: text,
      targetRecordId: targetRecordId,
      voteOption: voteOption,
      // S392: after a rotation the UserID NO LONGER follows from the
      // inline keys (§4.1) — the proof of it travels with the record, as
      // §14.5 provides for proofs ("proofs accompany the
      // action"). Empty as long as no rotation happened; then it costs nothing.
      rotationChain:
          SystemChannelRecordStore.wireChainOf(identity.rotationChain),
    );
    final bytes = record.writeToBuffer();
    final admission = _sysChanStore.tryAdmit(bytes, parsed: record);
    if (admission == SysChanAdmission.rejected) {
      // The own record does not get through the own admission. Until
      // S392 that was a wordless `null` — i.e. exactly the "silent
      // delivery failure" from §14.5. A foreign revocation target is the
      // one expected reason; every other one deserves to be seen.
      _log.warn('syschan: OWN record rejected by own admission '
          '(kind=$kind, channel=${channelIdHex.substring(0, 8)}, '
          'chain=${identity.rotationChain.length} link(s)) — '
          'nothing was published, not even locally');
      return null;
    }
    final stored = StoredSysChanRecord(
        record: record,
        bytes: bytes,
        fingerprintHex: SystemChannelRecordStore.fingerprintHexOf(bytes));

    switch (kind) {
      case SysChanKind.post:
        _bridgeSysChanPost(stored);
      case SysChanKind.retract:
        _applySysChanRetract(
            channelIdHex, record.targetRecordId.hex);
    }
    // S366: `tryAdmit` above has already written the record into the
    // store. The `_saveSysChanRecords()` that used to stand here batched
    // for two seconds — whoever stopped in this window lost the record
    // just published, because `stop()` cancelled the timer.
    _sysChanEagerPush(channelIdHex, [stored], ttl: _sysChanPushTtl);
    onStateChanged?.call();
    return stored;
  }

  /// D3 (§9.5.3): programmatic Feature-Request submission. Posts a
  /// SystemChannelRecord with an embedded auto-poll (the FR JSON) and the
  /// submitter's implicit "Ja" vote (Auto-Ja embedded).
  @override
  Future<UiMessage?> submitFeatureRequest(String title, String body) async {
    if (_reducedMode) {
      _log.warn('submitFeatureRequest blocked: reducedMode active');
      return null;
    }
    if (title.trim().isEmpty) return null;
    final text = jsonEncode({
      'type': 'feature_request',
      'title': title.trim(),
      'body': body.trim(),
    });
    final stored = await _publishSystemChannelRecord(
      channelIdHex: SystemChannels.featureReqChannelIdHex,
      kind: SysChanKind.post,
      text: text,
    );
    if (stored == null) return null;
    final recordIdHex = stored.record.recordId.hex;
    // Auto-Ja embedded: the submitter implicitly supports their request.
    await voteFeatureRequest(recordIdHex, SysChanVote.yes);
    final conv = conversations[SystemChannels.featureReqChannelIdHex];
    for (final m in conv?.messages ?? const <UiMessage>[]) {
      if (m.id == recordIdHex) return m;
    }
    return null;
  }

  /// D3 (§9.5.3): open vote record on a Feature-Request post. LWW per
  /// author — voting again changes the vote.
  @override
  Future<bool> voteFeatureRequest(String recordIdHex, int option) async {
    if (_reducedMode) return false;
    if (option < SysChanVote.yes || option > SysChanVote.irrelevant) return false;
    final stored = await _publishSystemChannelRecord(
      channelIdHex: SystemChannels.featureReqChannelIdHex,
      kind: SysChanKind.vote,
      targetRecordId: hexToBytes(recordIdHex),
      voteOption: option,
    );
    return stored != null;
  }

  /// D3 (§9.5.3): local tally over the open vote records. Keys: `ja`,
  /// `nein`, `egal`, `net`, `own` (-1 when the caller has not voted).
  @override
  Future<Map<String, int>> featureRequestTally(String recordIdHex) async {
    final chHex = SystemChannels.featureReqChannelIdHex;
    final tally = _sysChanStore.tallyFor(chHex, recordIdHex);
    final own =
        _sysChanStore.ownVote(chHex, recordIdHex, identity.userIdHex) ?? -1;
    return {
      'ja': tally.yes,
      'nein': tally.no,
      'egal': tally.irrelevant,
      'net': tally.net,
      'own': own,
    };
  }

  // ── Multi-Device Persistence (§26) ─────────────────────────────────

  /// Initialize local device ID (generated once, persisted in devices.json).
  void _initLocalDevice() {
    _loadDevices();

    // Check if we already have a local device ID on disk
    final existing = _devices.values.where((d) => d.isThisDevice).toList();
    if (existing.isNotEmpty) {
      _localDeviceId = existing.first.deviceId;
      existing.first.lastSeen = DateTime.now();
      // S368: here stood `deviceNodeIdHex ??= bytesToHex(identity.deviceNodeId)`
      // with the justification "migration from pre-Phase-4". A device row
      // without `deviceNodeIdHex` can only come from a profile before §26
      // Phase 4; such profiles do not exist on this line.
      _saveDevices();
      return;
    }

    // Generate new device ID (UUID v4 as hex)
    final uuid = SodiumFFI().randomBytes(16);
    _localDeviceId = bytesToHex(uuid);

    final now = DateTime.now();
    _devices[_localDeviceId] = DeviceRecord(
      deviceId: _localDeviceId,
      deviceName: Platform.localHostname,
      platform: _detectPlatform(),
      firstSeen: now,
      lastSeen: now,
      isThisDevice: true,
      deviceNodeIdHex: bytesToHex(identity.deviceNodeId),
    );
    _saveDevices();
    _log.info('Local device registered: $_localDeviceId (${Platform.localHostname})');
  }

  static String _detectPlatform() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isLinux) return 'linux';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    return 'unknown';
  }

  /// Areas of the device keeping (S366, formerly `devices.json`).
  ///
  /// THREE AREAS AND NOT ONE, and that is the actual gain here: the file
  /// carried, NEXT TO the (at most five, §26) devices, a dedup window
  /// with cap 10 000. Because both lay in one map, EVERY device change —
  /// a `lastSeen`, a renamed device — wrote all 10 000 rows along.
  /// Separated, a device change no longer touches the window, and a new
  /// dedup identifier costs ONE row instead of the whole collection.
  static const String _areaDevices = 'devices';
  static const String _areaDeviceMeta = 'device_meta';
  static const String _areaSyncDedup = 'device_sync_dedup';

  /// What LAY in the area [_areaSyncDedup] last. The difference to
  /// [_processedSyncIds] is exactly what has to be written —
  /// without this shadow `_saveDevices` would have to write the window
  /// as a whole again, and the rebuild would be for nothing.
  final Set<String> _syncIdsPersisted = <String>{};

  void _loadDevices() {
    try {
      // S366: from the store instead of from `devices.json`.
      for (final entry in store.loadArea(_areaDevices).entries) {
        try {
          _devices[entry.key] = DeviceRecord.fromJson(entry.value);
        } catch (e) {
          _log.warn('Skipping corrupt device ${entry.key}: $e');
        }
      }
      // §14.5 path 2: the announcement counter. It used to lie as the
      // special key `_deviceSetSeq` in the same map; in a table with
      // (area, key) the namespace trick is no longer needed.
      final meta = store.loadArea(_areaDeviceMeta)['seq'];
      _deviceSetSeq = (meta?['v'] as num?)?.toInt() ?? 0;
      // Dedup window: key = syncIdHex, value = firstSeen epoch-ms.
      for (final entry in store.loadArea(_areaSyncDedup).entries) {
        final ts = (entry.value['ts'] as num?)?.toInt();
        if (ts == null) continue;
        _processedSyncIds[entry.key] = ts;
        _syncIdsPersisted.add(entry.key);
      }
      // Prune expired entries (>7 days) on load
      _pruneSyncDedup();
      _devicesLoaded = true;
      _log.info('Loaded ${_devices.length} devices, ${_processedSyncIds.length} sync IDs');
    } catch (e) {
      _log.warn('Failed to load devices: $e');
    }
  }

  void _saveDevices() {
    // THE DATA-LOSS LATCH. It stood on `devices.json.enc` — a file that
    // is never written again after the switch-over. It would thus have
    // been silently dead: never red, just ineffective. It now asks the
    // STORE, and if that is not readable, it fails CLOSED (no writing).
    if (!_devicesLoaded && _devices.isEmpty) {
      var present = false;
      try {
        present = store.countArea(_areaDevices) > 0 ||
            store.countArea(_areaSyncDedup) > 0;
      } catch (e) {
        _log.warn('REFUSED to save devices — store unreadable: $e');
        return;
      }
      if (present) {
        _log.warn('REFUSED to save empty devices — load failed but the store '
            'still holds entries. Would cause data loss!');
        return;
      }
    }
    try {
      // `replaceArea` for the devices: §26 caps them at five, and all 14
      // callers call "save everything". That is the case `replaceArea`
      // exists for.
      store.replaceArea(_areaDevices,
          {for (final e in _devices.entries) e.key: e.value.toJson()});
      store.putEntry(_areaDeviceMeta, 'seq', {'v': _deviceSetSeq});

      // Persist sync dedup IDs with 7-day TTL (matches S&F window, §26 Dedup).
      _pruneSyncDedup();
      // Hard cap on the map size to bound memory (evict oldest first) even if
      // the 7-day window gets flooded. 10k ≈ ~60 entries/hour for a week.
      if (_processedSyncIds.length > 10000) {
        final sorted = _processedSyncIds.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        final evict = sorted.take(_processedSyncIds.length - 10000).map((e) => e.key).toList();
        for (final id in evict) {
          _processedSyncIds.remove(id);
        }
      }
      // ONLY THE DIFFERENCE. `putEntry`/`removeEntry` per changed
      // identifier instead of `replaceArea` over up to 10 000 rows — a
      // pure device change writes NOTHING here from now on.
      for (final id in _processedSyncIds.keys) {
        if (_syncIdsPersisted.contains(id)) continue;
        store.putEntry(_areaSyncDedup, id, {'ts': _processedSyncIds[id]});
        _syncIdsPersisted.add(id);
      }
      final dropped =
          _syncIdsPersisted.where((id) => !_processedSyncIds.containsKey(id))
              .toList();
      for (final id in dropped) {
        store.removeEntry(_areaSyncDedup, id);
        _syncIdsPersisted.remove(id);
      }
    } catch (e) {
      _log.warn('Failed to save devices: $e');
    }
  }

  /// Fire devices-updated + state-changed callbacks. Wrapper so every
  /// device mutation goes through a single place and emits the IPC event.
  void _notifyDevicesChanged() {
    try {
      onDevicesUpdated?.call();
    } catch (e) {
      _log.warn('onDevicesUpdated callback failed: $e');
    }
    onStateChanged?.call();
  }

  /// §7.4 Device Revocation: retract everything the publisher still attests
  /// for a device that just left `_devices`.
  ///
  /// `_syncAuthorizedDevicesToPublisher()` only rebuilds the *addressing* set.
  /// Two device-bound artefacts live outside it and would survive a revocation:
  ///
  ///  - the `DeviceDelegationCert`. `IdentityDhtHandler.getDelegatedKeys`
  ///    hands it to `V3FrameCodec` as a valid User-Sig fallback, so a revoked
  ///    device could keep signing as this user until the cert expires on its
  ///    own — `maxValidUntilMs` is up to 30 days out. That makes revocation
  ///    ineffective as a security measure, which is the only thing it is for.
  ///  - the `DeviceSigInfo`. §7.5 contacts count it as an eligible
  ///    countersigner for the rotation quorum, so a revoked device would keep
  ///    helping to authorise the very Emergency Key Rotation the quorum exists
  ///    to guard.
  ///
  /// [deviceIdKey] is the `_devices` map key, which is the device node id hex
  /// for pairing-created records (`_addDeviceDelegation`,
  /// `_handleDevicePairApproveV3`) but the 16-byte UUID hex once a
  /// DEVICE_ANNOUNCE has superseded them. The delegation and the sig-key entry
  /// are always keyed by the **node** id, so both candidates are tried; the
  /// removals are no-ops for the key that does not match.
  ///
  /// Called from both revocation entry points — local IPC ([revokeDevice]) and
  /// twin-sync ([_handleTwinDeviceRevoked]) — because they are the same state
  /// transition arriving over two channels.
  /// §7.5: remove a device from the published identity, carrying a
  /// `DeviceSetChangeProof` when one can be obtained.
  ///
  /// Wraps the two publisher mutations that used to stand inline in
  /// [revokeDevice] / [_handleTwinDeviceRevoked]. Both of them trigger the
  /// Auth re-publish, and that publish is the ONLY carrier of the proof —
  /// which is why the countersignatures have to be collected before either
  /// call, not after.
  ///
  /// WHY THE PROOF CANNOT BE ADDED LATER. The receiver's shrink check
  /// (`IdentityDhtHandler.handleAuthPublish`) is edge-triggered: it compares
  /// the incoming manifest against the last one it stored. Publishing the
  /// shrunk set first and the proof afterwards means the second manifest is no
  /// longer a shrink relative to the first, so the proof is never looked at
  /// and the warning has already fired. There is exactly one manifest that can
  /// carry it.
  ///
  /// WHAT HAPPENS WHEN CONSENT DOES NOT ARRIVE — decided here, deliberately:
  /// the removal proceeds and the manifest publishes WITHOUT a proof, which
  /// makes contacts raise the §7.5 shrink warning. The removal is never
  /// postponed and never rolled back. Reasons:
  ///
  ///  * Revocation is a security action taken because a device is lost,
  ///    stolen or retired. Gating it on an answer from the remaining devices
  ///    would let anyone holding one of them veto their own removal by simply
  ///    staying silent — the exact inversion of the mechanism's purpose.
  ///  * The alternative failure is loud, not silent: contacts are told that
  ///    devices disappeared and nobody vouched for it, which is a question a
  ///    human can answer. Silently keeping a revoked device published is not.
  ///  * A timeout is not a rejection and not a consent. It produces no token,
  ///    the quorum is missed, and no proof is fabricated (see the provider in
  ///    `_setupIdentityPublisher`).
  ///
  /// Locally the user sees the device disappear from the device list
  /// immediately; contacts additionally receive `MTV3_DEVICE_REVOCATION`
  /// straight away, independently of this path.
  Future<void> _applyDeviceSetRemoval(
      DeviceRecord? device, String deviceIdKey) async {
    // The two mutations this method exists to defer. Every path ends here,
    // exactly once — the removal always takes effect.
    void applyRetraction() {
      _retractDeviceFromPublisher(device, deviceIdKey);
      _syncAuthorizedDevicesToPublisher();
    }

    // ── §7.5 PROOF: GAP G-9 ───────────────────────────────────────
    //
    // Until now it was checked here whether the removal becomes visible
    // to the other side as a SHRINKING at all (`deviceSigKeyCount` before
    // and after), and only then was a quorum of countersignatures collected.
    // Both numbers came from `_identityPublisher`, and the
    // countersignature of this device needed `node.deviceKeyPair` — no
    // holder, no key (see field above).
    //
    // The revocation itself continues UNCHANGED: a removed device must be
    // removed, regardless of whether the proof for it can be built. That
    // matches the `catch` branch this method already had for exactly
    // this case ("A failure here must not strand the revocation").
    if (!identity.isLinkedDevice && _devices.length > 1) {
      _log.error('§7.5: device removal WITHOUT co-signature proof — '
          'neither the delegation list nor the device key has a holder in '
          'V4.1 (gap G-9). Contacts will see the '
          'shrinkage uncovered and show the §7.5 warning. '
          '${_devices.length} device(s) in the set.');
    }
    applyRetraction();
  }

  // ── §7.5 CO-SIGNING OF A DEVICE-SET CHANGE: FALLEN ────────
  //
  // `_collectDeviceSetChangeApprovals(...)` stood here. It created a
  // `_PendingDeviceSetChange`, signed it with the DEVICE key of this
  // device (`node.deviceKeyPair` — and that was exactly the point:
  // "locally generated and NOT seed-derived", which is why even a
  // single token was worth something) and collected the answers of the
  // other devices.
  //
  // Without a holder for the device key this cannot be built
  // (gap G-9), and the only caller ([_applyDeviceSetRemoval]) reports
  // the gap there. A proof with invented or missing tokens would be
  // worse than none: the receiver would read `quorumMet` and stop
  // reporting the shrinking.

  /// Public accessor: list of registered twin devices (for IPC/GUI).
  @override
  List<DeviceRecord> get devices => _devices.values.toList();

  /// Local device ID (UUID hex).
  @override
  String get localDeviceId => _localDeviceId;

  /// §24.4.3 — the transition state of running device lock-outs, for the
  /// display.
  ///
  /// ── WHY THE BODY STANDS HERE AND NOT NEXT TO THE CALCULATION ───────
  ///
  /// The data side lives in `DeviceLockoutOps` — an EXTENSION on
  /// `CleonaService` (`cleona_service_lockout.dart:170`). An extension
  /// method does NOT satisfy an interface member: it is not a class
  /// member, and `CleonaService implements ICleonaService` inherits no
  /// body. Measured on a minimal source, not assumed — the analyzer then
  /// says `non_abstract_class_inherits_abstract_member`, and it does so
  /// even when one tries it via `augment class` in a `part` file.
  /// The class member therefore has to stand in the class body; the
  /// calculation stays over there.
  ///
  /// **AND IT IS NAMED DIFFERENTLY FROM THE METHOD.** A class member
  /// `deviceLockoutStates` would HIDE the extension method of the same
  /// name (class members take precedence), and the eight calls in
  /// `smoke_device_lockout_transition.dart` would then read as a call
  /// of the getter RESULT. The name separates the two roles:
  /// `deviceLockoutStates()` calculates, `deviceLockouts` displays.
  @override
  List<Map<String, dynamic>> get deviceLockouts => deviceLockoutStates();

  /// Rename a twin device and broadcast via TWIN_SYNC.
  @override
  void renameDevice(String deviceId, String newName) {
    final device = _devices[deviceId];
    if (device == null) return;
    device.deviceName = newName;
    _saveDevices();
    _log.info('Device renamed: $deviceId → $newName');

    // Broadcast to twins
    final payload = utf8.encode(jsonEncode({
      'deviceId': deviceId,
      'deviceName': newName,
    }));
    _sendTwinSync(proto.TwinSyncType.DEVICE_RENAMED, Uint8List.fromList(payload));
    _notifyDevicesChanged();
  }

  /// Revoke a twin device: remove from list, notify twins + contacts.
  /// Returns true if the device was found and revoked.
  @override
  Future<bool> revokeDevice(String deviceId) async {
    if (deviceId == _localDeviceId) return false; // Can't revoke self
    final device = _devices[deviceId];
    if (device == null) return false;

    _log.info('Revoking twin device: $deviceId (${device.deviceName})');

    // Notify twins: device has been revoked
    final payload = Uint8List.fromList(utf8.encode(deviceId));
    _sendTwinSync(proto.TwinSyncType.TWIN_DEVICE_REVOKED, payload);

    // Broadcast DEVICE_REVOKED to contacts with DeviceRecord proto (§26.6.1).
    // §26 Phase 4: include deviceNodeId so contacts can remove the specific
    // routing entry from their routing table.
    final revokedRecord = proto.DeviceRecord()
      ..deviceId = hexToBytes(deviceId)
      ..deviceName = device.deviceName;
    if (device.deviceNodeIdHex != null) {
      revokedRecord.deviceNodeId = hexToBytes(device.deviceNodeIdHex!);
    }
    final revokePayload = Uint8List.fromList(revokedRecord.writeToBuffer());

    // ── THE LOCK-OUT TRANSITION STARTS HERE (E-7, §14.4/§24.4.3) ───────
    //
    // UP TO HERE THE ANNOUNCEMENT WAS THROWN AWAY: `_detachedSend`
    // catches the throw and drops the result, and `sendToUser` got no
    // `messageId` — so the delivery register did not create a record
    // that could be assigned to a contact either. Thus there was no
    // "informed", no pending set, no deadline, and the old inbound line
    // expired after a blind timer.
    //
    // EVERY LEG NOW GETS ITS OWN IDENTIFIER. It is exactly the key under
    // which `sendToUser` creates the record in the register
    // (`_v41NoteSend`) and under which the contact's delivery receipt
    // finds it again (`_handleDeliveryReceiptV3`). Without its own
    // identifier a fan-out message would throw all contacts into one
    // record, and "3 of 47 open" could not be calculated.
    final transition = _beginLockout(deviceId, device.deviceName);
    for (final contact in _contacts.values) {
      if (contact.status != 'accepted') continue;
      if (contact.x25519Pk == null || contact.mlKemPk == null) continue;
      final contactHex = bytesToHex(contact.nodeId);
      final legId = SodiumFFI().randomBytes(16);
      try {
        _noteLockoutLeg(
            transition,
            contactHex,
            bytesToHex(legId),
            sendToUser(
              recipientUserId: contact.nodeId,
              messageType: proto.MessageTypeV3.MTV3_DEVICE_REVOCATION,
              payload: revokePayload,
              messageId: legId,
            ));
      } catch (e) {
        // `sendToUser` is `async` and never throws synchronously; this
        // branch remains for a throw BEFORE the call (key derivation in the
        // argument). The contact then counts as not sent, not as
        // informed.
        transition.pendingLegs[contactHex] = bytesToHex(legId);
        transition.notSent.add(contactHex);
        // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
        _log.debug('Failed to send DEVICE_REVOCATION to ${contact.displayName}: $e');
      }
    }
    // S366: ONE row for THIS device instead of the whole stock.
    _persistLockout(deviceId);
    _log.info('Lockout transition opened for ${deviceId.substring(0, 8)}: '
        '${transition.total} contacts to inform, deadline '
        '$_lockoutDeadlineDays days (§14.4)');

    _devices.remove(deviceId);
    // ── AND ITS DEVICE LINE FROM THE REGISTRY (§14.7, §21.5.1) ───
    //
    // A locked-out device must no longer be a deposit target. The
    // entry was created when sending (`sendToUser`, pure deposit line) and
    // would otherwise have survived the lock-out — the same error class as
    // `forgetPeer`, which until S354 had no caller for deleted contacts.
    //
    // WHAT THIS DOES NOT ACHIEVE, and that should be said openly: the
    // device root falls out of `K_own`, and `K_own` keeps holding the
    // locked-out device until the user KEM keys rotate
    // (§14.4, "That is why this rotates along at lock-out too"). It can
    // therefore keep harvesting its line itself. Deleting the entry here
    // only prevents THIS node from still depositing there.
    final lockedOutNodeId = device.deviceNodeIdHex;
    if (lockedOutNodeId != null && lockedOutNodeId.isNotEmpty) {
      v41Delivery?.forgetPeer(
          deviceLineKey(identity.userId, hexToBytes(lockedOutNodeId)));
    }
    _saveDevices();
    // §14.5 path 2: the shrunken device set goes pairwise to the
    // contacts. AFTER `_devices.remove`, so that the announcement carries
    // the state AFTER the change — §14.8 counts the quorum over the
    // REMAINING devices ("On a device-set change, the quorum counts the
    // *remaining* devices `M`, not the state before it").
    _announceDeviceSetToContacts(occasion: 'Geraete-Widerruf');
    // §7.4 + §7.5: retract the device-bound authority (delegation cert +
    // Device-Sig keys) and rebuild the published device set. Both live in
    // [_applyDeviceSetRemoval] now, because the Auth re-publish they trigger
    // is the only manifest that can carry the §7.5 co-auth proof — the
    // countersignatures have to be collected first. Ordering inside is
    // unchanged: retraction before address-set rebuild, so the last mutation
    // carries fully consistent state through the publisher's coalescing gate.
    //
    // Not awaited: collecting consent can take minutes (a human taps
    // "approve" on another device) and the IPC caller must not block on it.
    // The local removal above has already taken effect, and contacts were
    // told via MTV3_DEVICE_REVOCATION before this point.
    unawaited(_applyDeviceSetRemoval(device, deviceId));

    // §14.10: a revoked device still holds every user key it saw before
    // removal — it POSSESSES them, revocation alone only stops it from being
    // ADDRESSED. "A mere inbox rotation would be a label, not a lock." This
    // is the same Emergency Key Rotation the "Identitaet neu schluesseln"
    // IPC path (`rotate_identity_keys`) already triggers by hand — replaces
    // User-Sig (Ed25519+ML-DSA) AND User-KEM (X25519+ML-KEM) together, so
    // the stolen/lost device can neither keep signing as this user nor keep
    // reading what contacts encrypt to it from here on.
    //
    // Safe to fire without waiting for `_applyDeviceSetRemoval` above to
    // finish retracting the delegation: `rotateIdentityKeys()`'s twin-sync
    // fan-out (LD-8 delegation rotation + legacy-twin entropy) resolves
    // recipients from `_devices` (§7.2 self fan-out, see `sendToUser`), not
    // from the publisher's delegation list — and `_devices.remove(deviceId)`
    // above already ran. The revoked device is excluded from that fan-out
    // regardless of how long the §7.5 device-set-change proof above still
    // takes to collect.
    //
    // Not awaited for the same reason as `_applyDeviceSetRemoval`: the
    // rotation's OWN §7.5 co-auth (a Linked Device countersigning the new
    // keys) can wait up to 5 min (`_rotationApprovalWaitWindow`) before it
    // proceeds anyway — see `rotateIdentityKeys()`. No-op with a log line on
    // a Linked Device (`identity.isLinkedDevice` guard); the Primary picks
    // it up via the mirrored call in `_handleTwinDeviceRevoked` when the
    // revocation was initiated from a Linked Device instead.
    unawaited(rotateIdentityKeys());
    _notifyDevicesChanged();
    return true;
  }

  /// Inject a fake twin device for E2E testing (test-only).
  @override
  void injectTestDevice(String deviceId, String name, String platform) {
    final now = DateTime.now();
    _devices[deviceId] = DeviceRecord(
      deviceId: deviceId,
      deviceName: name,
      platform: platform,
      firstSeen: now,
      lastSeen: now,
    );
    _saveDevices();
    _notifyDevicesChanged();
    _log.info('Test device injected: $deviceId ($name)');
  }

  /// Test-only: initialize `_localDeviceId` without running the full
  /// `startService()` chain. `revokeDevice()` reads `_localDeviceId` on its
  /// very first line, so a smoke test that wants to exercise it on a bare,
  /// offline `CleonaService` needs this primed first — no existing smoke
  /// test in this repo calls `startService()` itself (it additionally
  /// needs `node.start()` for `node.transport`/`routingTable`, see
  /// `smoke_service_wiring.dart`), and `_initLocalDevice()` has no network
  /// dependency of its own (disk only), so this is a narrower, offline-safe
  /// substitute — not a shortcut around the fields that DO need the node.
  void testInitLocalDeviceForTesting() => _initLocalDevice();

  /// Test-only: read-only snapshot of the key-rotation retry state. Used by
  /// E2E harness (gui-52-key-rotation-retry) to assert pending/acked counts
  /// after an offline→online contact resurface.
  @override
  Map<String, dynamic> testGetKeyRotationRetryState() {
    final s = _keyRotationRetry.state;
    return {
      'hasActiveRotation': _keyRotationRetry.hasActiveRotation,
      'pendingCount': _keyRotationRetry.pendingCount,
      'ackedCount': _keyRotationRetry.ackedCount,
      'expiredCount': _keyRotationRetry.expiredCount,
      'rotationId': s?.rotationId,
      'pendingHexes': s?.pending.keys.toList() ?? const <String>[],
      'ackedHexes': s?.acked.toList() ?? const <String>[],
      'expiredHexes': s?.expired.toList() ?? const <String>[],
    };
  }

  /// Test-only: ignore the 24h retry interval and trigger the retry loop
  /// immediately for every pending contact. The production code path
  /// (`_retryPendingKeyRotations`) is reused unchanged — we only reset the
  /// per-contact attempt clocks so `duePending` reports them as due.
  @override
  void testForceKeyRotationRetry() {
    _keyRotationRetry.resetAttemptClocksForTesting();
    _retryPendingKeyRotations();
  }

  // ── Getters ────────────────────────────────────────────────────────

  @override
  String get nodeIdHex => identity.userIdHex;
  @override
  String get deviceNodeIdHex => identity.deviceNodeIdHex;
  // ── DEVICE KEM KEY: GAP G-9 ─────────────────────────────
  //
  // `node.deviceKem` was the node-wide, LOCALLY generated (not
  // seed-derived, §3.6 #5) device KEM pair. It was loaded by
  // `DeviceKeysStore` — the file lives on unchanged in
  // `lib/core/crypto/` —, it was held by `CleonaNode`.
  //
  // THE SERVICE MUST NOT LOAD IT ITSELF. `DeviceKeysStore.loadOrCreate`
  // wants a `baseDir`, and the node used `primaryIdentity` for that.
  // Every service with its own `identity.baseDir` would get a
  // DIFFERENT device key pair — and thus a daemon would have as many
  // "devices" as identities. §3.1 C-1 says the opposite: all hosted
  // identities share ONE deviceNodeId. That would not be a stopgap, but
  // the breach of an invariant.
  //
  // ── WHY AN EMPTY FIELD AND NOT A THROW ────────────────────────────
  //
  // The first version threw `UnsupportedError`. That was well thought out
  // at the point of decision and wrong in the result: the two foreign
  // readers are `ipc_server.dart` (in the state snapshot the UI fetches
  // on EVERY tick) and `contact_share_card.dart` (in building a widget).
  // A throw there would not have cancelled the invitation, but torn
  // apart the whole state line or the frame build — a defect at a
  // place that has nothing to do with device keys.
  //
  // AN EMPTY FIELD IS NOT A DUMMY HERE, and that is measured, not hoped:
  // `contact_seed.dart:220` writes `&dxk=` ONLY if
  // `dxk.length == deviceX25519PkLength`. An empty list fails this check
  // and the seed goes out as a v2 seed — with `ep` as trust anchor and
  // WITHOUT device keys. That is a documented form supported by the
  // parser, not a broken one: the receiver sees "this seed carries no
  // device keys" and not "wrong ones stand here".
  //
  // The log line nevertheless stays at `error`: that every issued seed
  // now has the weaker form is a finding and not an operating state.

  /// The public device KEM key (X25519 half).
  ///
  /// ── G-9 CLOSED ON 09.09.2026 (S378) ───────────────────────────
  ///
  /// Here stood an empty list and an `error` log line. The holder was
  /// not missing — it was just not connected: `IdentityContext` has
  /// loaded the bundle itself since S360 (`identity_context.dart:760`,
  /// `DeviceKeysStore.loadOrCreate`) and KEEPS it in `_deviceKeys`.
  ///
  /// WHAT THIS COST, measured on 09.09.2026 on cleona1/cleona2:
  /// `contact_seed.dart:220` writes `&dxk=` only at the correct length,
  /// the empty list failed, and EVERY outgoing seed went out in the
  /// weaker v2 form. The other side could not answer it —
  /// `sendToUser: no KEM pubkeys for … (contact=true,
  /// x25519=false, mlKem=false)`. Result: contacts created, but not
  /// addressable, first contact on NO platform, and the QR code stayed
  /// at 95 % because `ready` never occurred.
  ///
  /// WHY THIS DOES NOT VIOLATE THE OLD JUSTIFICATION. The comment above
  /// forbids ONE thing: that the service calls
  /// `DeviceKeysStore.loadOrCreate` ITSELF. The reason is compelling —
  /// the store wants a `baseDir`, and every service with its own
  /// `identity.baseDir` would get a DIFFERENT pair; a daemon would then
  /// have as many "devices" as identities (§3.1 C-1 says the opposite).
  ///
  /// This path does NOT load. It reads what the context has already
  /// loaded — and it does so device-wide, measured at
  /// `identity_context.dart:742-750`: "all IdentityContexts in this
  /// daemon load the SAME DeviceKeysStore (single file in baseDir) […]
  /// Device keys use the daemon-global SHARED encryption key (not the
  /// per-identity key)". The invariant stays untouched.
  ///
  /// It stays empty only BEFORE `initKeys` — then `deviceKeys` is null,
  /// and the log line says exactly that, instead of claiming a missing
  /// holder. Readers still check the length
  /// (`contact_seed.dart` does).
  @override
  Uint8List get deviceX25519Pk {
    final b = identity.deviceKeys;
    if (b == null) {
      _log.error('deviceX25519Pk: `IdentityContext.deviceKeys` is still null '
          '— initKeys() has not run. The seed falls back to the v2 form '
          'with `ep`.');
      return Uint8List(0);
    }
    return b.kem.x25519PublicKey;
  }

  /// The ML-KEM half of the same bundle. See [deviceX25519Pk].
  @override
  Uint8List get deviceMlKemPk =>
      identity.deviceKeys?.kem.mlKemPublicKey ?? Uint8List(0);

  @override
  Uint8List get userEd25519Pk => identity.ed25519PublicKey;

  /// SR-2 (§8.1.1): founding anchor for the ContactSeed `fp` field.
  @override
  Uint8List get foundingEd25519Pk => identity.foundingEd25519Pk;
  // ── PEER COUNTS: ONE V4.1 QUANTITY INSTEAD OF THREE V3 QUANTITIES ───────────
  //
  // V3 distinguished three sets: everything in the routing table
  // (`peerCount`), bidirectionally confirmed (`confirmedPeerIds`) and
  // reachable via a live relay (`reachablePeerIds`). This distinction
  // presupposes a routing table, and that no longer exists.
  //
  // V4.1 knows exactly one quantity of this kind: the established
  // sessions of the tagline, separated by direction (§25.4). All three
  // getters therefore read THE SAME number. Inventing three different
  // numbers would be the worse answer — the UI shows them side by side,
  // and a difference would claim a distinction that does not exist.
  int get _v41SessionPartner => syncPartnersOutbound + syncPartnersInbound;

  @override
  int get peerCount => _v41SessionPartner;
  @override
  int get confirmedPeerCount => _v41SessionPartner;
  @override
  int get reachablePeerCount => _v41SessionPartner;

  /// The port-mapping coordinator of this PROCESS (UPnP/IGD +
  /// NAT-PMP/PCP), set by `attachV41`.
  ///
  /// `null` as long as no node is attached — then [hasPortMapping] is
  /// false as well, and rightly so: without a node no port is bound that
  /// a mapping could reach.
  ///
  /// ONE COORDINATOR PER PROCESS, but one service per identity: two
  /// identities on one node read the same object here. That is correct
  /// — there is one port and one forwarding.
  PortMapper? v41PortMapper;

  /// Whether an inbound port mapping is open (§25.9, gap G-12).
  ///
  /// ── UNTIL S373 A CONSTANT STOOD HERE ────────────────────────────
  ///
  /// `bool get hasPortMapping => false;`, with the justification "V4.1
  /// requests none". For the period between the CUT (31.08.2026) and
  /// today that was correctly measured, but it was never an architecture
  /// decision: v4_1 §25.9 lists "UPnP/PCP status, router info" as a
  /// metric, §23.4 calls port forwarding "useful — it turns the node
  /// into a point of contact for others", and E-64 presupposes a
  /// `publicPort` assigned by UPnP-IGD for the invitation link.
  /// The carriers had been deleted along with `lib/core/network/`, nothing more.
  ///
  /// As long as the constant stood, FOUR display places permanently
  /// showed "no": `system_channel_post.dart:340/:441` (chip "UPnP"/"kein
  /// UPnP"), `system_channels.dart:282/:300/:396`,
  /// `crash_reporter.dart:273`, `contact_issue_reporter.dart:74`. Every
  /// error report from the field thus carried the same useless line.
  @override
  bool get hasPortMapping => v41PortMapper?.hasMapping ?? false;

  @override
  bool get hasSessionConfirmedPeers => _v41SessionPartner > 0;

  /// In-process: GUI and service are the same binary, so the derivation cannot
  /// disagree with itself. The measurement that matters happens in `IpcClient`,
  /// where the two halves are separately deployed artefacts.
  @override
  IdentityDerivationSkew get identityDerivationSkew =>
      IdentityDerivationSkew.ok;

  /// FORMERLY `node.nodeStartedAt`. The node and the service started in
  /// the same sequence; the display ("since when is this running?") means both.
  @override
  DateTime? get nodeStartedAt => serviceStartedAt;

  /// Filled in [startService] from `dialableLocalAddresses()`
  /// (`lib/core/tagline/local_addresses.dart`) — the V4.1 counterpart of
  /// `node.localIps`. A field and not a getter, because the V4.1 version
  /// is asynchronous and this getter must not be.
  List<String> _localAddresses = const <String>[];

  @override
  List<String> get localIps =>
      _localAddresses.isNotEmpty ? _localAddresses : const ['127.0.0.1'];

  /// `null` here means "unknown", not "none" — the UI already shows an
  /// empty state for it.
  ///
  /// UNTIL S361 THIS SAID: "Gap G-12: without NAT traversal the node does
  /// NOT learn its public address." The first half-sentence is true (no
  /// UPnP/PCP, no port mapping), the second is measured false. The node
  /// DOES learn it, without any NAT traversal and without STUN: flight 2
  /// of the link handshake mirrors the observed source address back in
  /// the AEAD (`link/handshake.dart:151` `kObservedOffset2`, read at `:526`),
  /// `link_io/link_demux.dart:526` reads it from flight 2, and
  /// `link_io/link_host.dart:446` stores it in an `ObservedAddressBook`
  /// — wired in production via `LinkHost.start`
  /// (`tagline/v41_node.dart:644`). The book even answers the right
  /// question: `agreed({required bool ipv6})` (`link_host.dart:166`)
  /// only outputs an address when several observers agree, and
  /// `disagrees` (`:173`) is the finding "symmetric NAT".
  ///
  /// WHAT IS REALLY MISSING is the pass-through TO THIS PLACE: the
  /// service holds `V41Host`, not the `V41Node`/`LinkHost`. That is why
  /// `null` stays here instead of inventing a number. Listed in the gap
  /// book under G-12 (`docs/v4-redesign/S361-lueckenbuch.md`).
  ///
  /// **CORRECTED ON 2026-09-03 — half of the sentence was outdated.**
  /// Here it said: "the only access to the book in all of `lib/` is
  /// `host.observed.clearAll()` on network change (`v41_node.dart:3515`).
  /// No `agreed(`, no `candidates` is read anywhere."
  /// Re-measured on 2026-09-03 over `lib/` and `test/`, separately for
  /// `ObservedAddressBook`, `observed.`, `allCandidates` and `agreed(`:
  ///
  ///   * **Became false:** the book HAS a second reader. The
  ///     call candidates read `observed.allCandidates`
  ///     (`calls/address_candidates.dart:241` in `ownCallCandidates`),
  ///     called from `calls/call_transport_v41.dart:239` and `:327`,
  ///     wired in `tagline/v41_attach.dart:1025`.
  ///   * **Still true:** `agreed(` has ZERO callers in `lib/` — only
  ///     the declaration (`link_host.dart:166`) and smokes. And
  ///     `publicIp`/`publicPort` below have no producer; G-12 is
  ///     open.
  ///   * The line number `v41_node.dart:3515` for `clearAll()` was
  ///     also wrong; today it is at `:4380`.
  @override
  String? get publicIp => null;
  @override
  int? get publicPort => null;
  @override
  int get fragmentCount => mailboxStore.fragmentCount;

  /// "Running" means in V4.1: the delivery layer is attached to the
  /// service. Without it no message goes out, regardless of what else lives.
  @override
  bool get isRunning =>
      myceliumMailbox != null || (v41Host != null && v41Delivery != null);
  @override
  bool get isLinkedDevice => identity.isLinkedDevice;

  @override
  LinkedDeviceStatus get linkedDeviceStatus {
    final ldKeys = identity.linkedDeviceKeys;
    if (!identity.isLinkedDevice || ldKeys == null) {
      return LinkedDeviceStatus(isLinkedDevice: false);
    }
    final cert = ldKeys.delegationCert;
    return LinkedDeviceStatus(
      isLinkedDevice: true,
      capabilities: cert.capabilities,
      issuedAtMs: cert.issuedAtMs,
      maxValidUntilMs: cert.maxValidUntilMs,
      isExpired: cert.isExpired(),
    );
  }

  @override
  Future<bool> requestDelegationRenewal() async {
    if (!identity.isLinkedDevice) {
      _log.warn('requestDelegationRenewal: not a linked device');
      return false;
    }
    _log.info('LD-9: requesting delegation renewal from Primary');
    return sendDevicePairRequest();
  }

  @override
  List<ContactInfo> get acceptedContacts =>
      _contacts.values.where((c) => c.status == 'accepted').toList();

  @override
  List<ContactInfo> get pendingContacts =>
      _contacts.values.where((c) => c.status == 'pending').toList();

  @override
  List<ContactInfo> get pendingOutgoingContacts =>
      _contacts.values.where((c) => c.status == 'pending_outgoing').toList();

  @override
  List<ContactInfo> get storedForDeliveryContacts =>
      _contacts.values.where((c) => c.status == 'storedForDelivery').toList();

  @override
  ContactInfo? getContact(String nodeIdHex) => _contacts[nodeIdHex];

  @override
  List<PeerSummary> get peerSummaries {
    // ── GAP G-11: V4.1 HAS NO ADDRESS LIST PER PARTNER ────────────
    //
    // This list was a projection of the V3 routing table: per peer
    // several `PeerAddress` with type (private/public/IPv6), a
    // `lastSeen`, a stability level, plus the distinction
    // direct/via-relay. V4.1 keeps none of that: `V41Delivery` names
    // partner counts (§25.4), not addresses — and that is intent, not
    // incompleteness (§7: whoever knows the address set of a node can
    // link).
    //
    // WHAT THIS COSTS, explicitly named instead of concealed:
    //   * the connection overview in the UI stays empty;
    //   * `getNetworkStats().reachablePeerCount` drops to 0 — which is why
    //     [getNetworkStats] now reads the partner count directly;
    //   * ContactSeeds no longer carried start peers, because
    //     `ContactSeedBuilder` read exactly this list. **CLOSED on
    //     10.09.2026 (S380):** the builder now reads the
    //     entry pool (`V41Node.entries`, §11) via
    //     [entrySeedCandidates]; the receiving side of the same bridge
    //     already stood (`addPeersFromContactSeed` -> `personEntryHints`).
    //     This list here stays empty and rightly so — it was never the
    //     right source for that.
    //
    //     UNTIL S361 THIS SAID "that belongs to gap G-1". It does NOT
    //     belong there: G-1 (the carrier of the first request) has been
    //     closed since S360, and a seed WITHOUT start peers still triggers
    //     first contact — it carries `ki` and `ep`, and that suffices for
    //     the invitation line. What is missing without start peers is the
    //     ENTRY into the network for a node that has no partner yet:
    //     §11 entry records. That is a separate, open item and listed in
    //     the gap book as G-1/rest
    //     (`docs/v4-redesign/S361-lueckenbuch.md`).
    //
    // An empty list is the only honest answer here. Invented entries —
    // say the own address as a "peer" — would wander into foreign
    // ContactSeeds and send third parties into the void.
    _log.debug('peerSummaries: empty — V4.1 keeps no peer address list '
        '(gap G-11). Session partner: $_v41SessionPartner');
    return const <PeerSummary>[];
  }

  /// Start-peer candidates for the ContactSeed (§11) — the sending side of
  /// the entry bridge, gap G-11.
  ///
  /// The SELECTION (cap, freshness, family diversity) is made by the
  /// builder, not this service: it depends on the format of the code, and
  /// the format is known to `contact_seed.dart`. Here stands only the
  /// forwarding to the node — and the empty list when none is attached.
  @override
  List<EntrySeedCandidate> get entrySeedCandidates =>
      v41EntrySeedCandidates?.call() ?? const <EntrySeedCandidate>[];

  @override
  List<Conversation> get sortedConversations {
    final list = conversations.values.toList();
    list.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
    return list;
  }

  // ── Network Statistics ──────────────────────────────────────────

  /// Collect a full network statistics snapshot.
  @override
  NetworkStats getNetworkStats() {
    // FIRST UPDATE THE NODE'S NUMBERS, then collect (§25.5).
    // Without these two lines `bytesSentTotal`,
    // `bytesReceivedTotal`, `messagesRelayed` and `relayDataVolume`
    // stood permanently at 0 — four tiles showing a zero that looked like
    // a measurement. In the field at the same time it was ~24.5 MB/day
    // out and ~24.9 MB/day in (measured S357).
    final counter = v41NodeCounters?.call();
    if (counter != null) {
      statsCollector.noteNodeCounters(
        wireSent: counter.wireSent,
        wireReceived: counter.wireReceived,
        relayBytes: counter.relayBytes,
        relayCells: counter.relayCells,
      );
    }
    // AND THE SNAPSHOTS (§25.4). Twenty tiles which until 01.09.2026
    // either did not exist at all or sat on a V3 source that has been
    // deleted. They are REMEMBERED and not booked —
    // justification at `NetworkStatsCollector.noteNodeGauges`.
    final states = v41NodeGauges?.call();
    if (states != null) {
      statsCollector.noteNodeGauges(states);
    }
    return statsCollector.collect(
      isRunning: isRunning,
      profileDir: profileDir,
    );
  }

  // ── Contact issue reporting ────────────────────────────────────────
  @override
  Future<ContactIssueReport?> buildContactIssueReport(String contactNodeIdHex) async {
    final contact = _contacts[contactNodeIdHex];
    if (contact == null) return null;
    return contactIssueReporter.buildReport(contact);
  }

  @override
  Future<bool> publishContactIssueReport(String contactNodeIdHex) async {
    final report = await buildContactIssueReport(contactNodeIdHex);
    if (report == null) return false;
    return contactIssueReporter.publishReport(report);
  }

  @override
  Future<LogReport> buildLogReport() async => crashReporter.buildLogReport();

  @override
  Future<bool> publishLogReport() async {
    final report = await buildLogReport();
    return crashReporter.publishLogReport(report);
  }

  // ── NAT-Troubleshooting-Wizard (§27.9) ───────────────────────────────
  @override
  void Function()? onNatWizardTriggered;
  @override
  void Function()? onNatWizardUserRequested;

  @override
  Future<void> dismissNatWizard({required int durationSeconds}) async {
    if (durationSeconds <= 0) {
      // 0 = forever. JavaScript-style "far future" using Dart's int max-safe
      // constant. Practically never revisited.
      _natWizardDismissedUntilMs = 0x7FFFFFFFFFFFFFFF;
    } else {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      _natWizardDismissedUntilMs = nowMs + durationSeconds * 1000;
    }
    _saveNatWizardSettings();
    _log.info('NAT-Wizard dismissed until $_natWizardDismissedUntilMs '
        '(durationSeconds=$durationSeconds)');
  }

  /// Test-only (E2E gui-53): fire [onNatWizardTriggered] directly, bypassing
  /// the 10-min uptime gate, network checks and dismissed-flag from §27.9.1.
  /// The GUI-side `_natWizardShown` latch in `home_screen.dart` still applies,
  /// so a second force-trigger after the dialog has been shown (and not reset)
  /// is a no-op — tests rely on that to verify the dismiss path.
  @override
  void testForceNatWizardTrigger() {
    _log.info('NAT-Wizard: test-force trigger (E2E gui-53)');
    onNatWizardTriggered?.call();
  }

  /// User-initiated trigger via icon-tap in home_screen. Differs from the
  /// auto-trigger in that we also reset the dismiss-until flag (the user
  /// explicitly asked for it, overriding any earlier "Spaeter" click).
  ///
  /// Fires [onNatWizardUserRequested], NOT [onNatWizardTriggered] — the
  /// GUI-side auto-trigger latch must not apply here, otherwise a user who
  /// already saw the auto-dialog once this session could not manually
  /// re-open it via the icon. See home_screen.dart wiring.
  @override
  void requestNatWizard() {
    _natWizardDismissedUntilMs = 0;
    _saveNatWizardSettings();
    _log.info('NAT-Wizard: user-requested trigger (icon tap)');
    onNatWizardUserRequested?.call();
  }

  /// Test-only (E2E gui-53): clear the persistent dismissed-until flag so the
  /// next real trigger can fire again. Pairs with the GUI-level latch reset
  /// via `gui_action('reset_nat_wizard_latch')`.
  @override
  void testResetNatWizardDismissed() {
    _natWizardDismissedUntilMs = 0;
    _saveNatWizardSettings();
    _log.info('NAT-Wizard: test-reset dismissed flag (E2E gui-53)');
  }

  @override
  Future<bool> recheckNatWizard() async {
    // §27.9.2 Step 3: re-run UPnP discovery + hole-punch round + 30s
    // observation of directConnections > 0. No implicit retry — user must
    // have already edited the router rule before clicking "Jetzt pruefen".
    // ── PORT MAPPING RUNS AGAIN (S373) ────────────────────────
    //
    // Between the CUT (31.08.2026) and today only an observation stood
    // here: "without port mapping (gap G-12)". The contract text in
    // `service_interface.dart` promised the whole time "re-run UPnP
    // discovery + hole-punch round" — it was outdated, and this body
    // was half the method.
    //
    // SEARCH AGAIN, NOT JUST WATCH. §27.9.2 step 3 is the button
    // "Jetzt pruefen" that the user presses AFTER changing something at
    // their router. Exactly then a new discovery is the question they
    // ask — the previous one ran before their change.
    //
    // NOT AWAITED: a discovery run can take minutes (RFC 6886 backoff),
    // the observation below runs 30 s. If the mapping comes about in the
    // meantime, the user sees it at the connection icon; the return value
    // of this method stays the observation of inbound sync partners,
    // because THAT is the question a port forwarding answers.
    final mapping = v41PortMapper;
    if (mapping != null) {
      _log.info('NAT wizard recheck: port mapping is searched again '
          '(UPnP/IGD + NAT-PMP/PCP), and it is observed whether an '
          'incoming sync partner comes about.');
      unawaited(mapping.reset().then((_) => mapping.start()).catchError(
          (Object e) {
        _log.warn('NAT-Wizard recheck: port mapping failed: $e');
      }));
    } else {
      _log.info('NAT wizard recheck: no V4.1 node is attached to this '
          'identity (attachV41 sets `v41PortMapper`) — it is only '
          'observed whether a direct connection comes about.');
    }

    // ── WHAT IS OBSERVED HERE, SINCE S360 ───────────────────────────
    //
    // Until 01.09.2026 here stood `getNetworkStats().directConnections
    // > 0`. Since the CUT this number was constantly 0 — the method RAN 30
    // seconds and then necessarily returned `false`, regardless of what
    // the user had set at their router. A spinner that always has the
    // same result is worse than no spinner: it makes the user believe
    // their correct setting is wrong.
    //
    // INBOUND SYNC PARTNERS ARE THE QUESTION A PORT FORWARDING
    // ANSWERS. §25.4 on this number: it "states how much the node
    // contributes for others; a precondition for inbound calls (§17)" —
    // i.e. exactly "does someone reach me from outside". If it rises from
    // 0 to > 0 after the router change, the forwarding worked.
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      final incoming = syncPartnersInbound;
      if (incoming > 0) {
        _log.info('NAT-Wizard recheck: incoming sync partners observed '
            '($incoming)');
        return true;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    _log.info('NAT wizard recheck: no incoming sync partner after 30 s');
    return false;
  }

  // ── Key Rotation ──────────────────────────────────────────────────

  /// Rotate KEM keys and broadcast to all contacts.
  /// Async: ML-KEM keygen runs in background isolate (ANR fix).
  Future<void> _performKeyRotation() async {
    await identity.rotateKemKeys();
    // `node.broadcastAddressUpdate()` stood here (§5.11: the fresh
    // `PeerInfo` with the new KEM key once to all known peers). V4.1 does
    // not distribute peer records; the new key reaches the contacts via
    // the KEY_ROTATION broadcast below, which goes via [sendToUser] and
    // thus via the V4.1 switch (T).

    // Build KEY_ROTATION message
    final rotationMsg = proto.KeyRotation()
      ..newX25519Pk = identity.x25519PublicKey
      ..newMlKemPk = identity.mlKemPublicKey
      ..rotationTimestamp = Int64(DateTime.now().millisecondsSinceEpoch);

    // Sign the rotation data with our identity key
    final dataToSign = rotationMsg.writeToBuffer();
    rotationMsg.signature = SodiumFFI().signEd25519(dataToSign, identity.ed25519SecretKey);

    // Broadcast to all accepted contacts
    final payload = Uint8List.fromList(rotationMsg.writeToBuffer());
    for (final contact in _contacts.values) {
      if (contact.status != 'accepted') continue;
      if (contact.x25519Pk == null || contact.mlKemPk == null) continue;
      _detachedSend('MTV3_KEY_ROTATION_BROADCAST', sendToUser(
        recipientUserId: contact.nodeId,
        messageType: proto.MessageTypeV3.MTV3_KEY_ROTATION_BROADCAST,
        payload: payload,
      ));
    }

    _log.info('Key rotation complete, broadcast to ${acceptedContacts.length} contacts');
  }

  /// Emergency full identity rotation (§26.6.2): new seed, new keys, broadcast to all.
  /// Called from GUI "Identität neu schlüsseln" button.
  /// Generates new master seed, derives all new keys, sends dual-signed
  /// KEY_ROTATION_BROADCAST to all contacts, syncs new seed to twin devices.
  @override
  Future<void> rotateIdentityKeys() async {
    // §7.1 LD-5: only the Primary device (with master seed) may rotate keys.
    if (identity.isLinkedDevice) {
      _log.warn('rotateIdentityKeys: blocked — this is a Linked Device '
          '(no master seed). Rotation must be initiated on the Primary.');
      return;
    }

    // ── WHAT V4.1 ALLOWS HERE, AND WHERE IT STAYS FAIL-CLOSED ───────────
    //
    // Here stood an UNCONDITIONAL abort. It relied on two sentences from
    // the v3_0 line, one of which V4.1 has REPLACED:
    //
    //  * "The KEY_ROTATION_BROADCAST MUST go via the §7.4 infra path."
    //    On the V4 line the opposite applies. v4_1 §14.4, "How contacts
    //    learn of the rotation": "Only **pairwise**: `K_AB` is independent
    //    of the shared key, every contact is reached individually. A public
    //    object is out." The pairwise way IS the prescribed one, and in
    //    this codebase it is called [sendToUser]. The infra receive path
    //    `handleIncomingKeyRotationBroadcastInfra`
    //    (`cleona_service_identity.dart:236`) has had ZERO callers since
    //    the CUT — so there was no path one could have preferred it to;
    //    the abort was not the safe way, but the only one.
    //
    //  * "§7.5 co-signing is missing." That still holds, and exactly there
    //    the abort stays — one condition deeper. For the single-device
    //    case, however, §14.4 says literally: "**At exactly one device, the
    //    rule does not apply** — there, that one device suffices", and
    //    §14.8 repeats it. For these identities rotation without quorum is
    //    not a fallback, but the normative case.
    //
    // WHAT HAS NOT CHANGED ABOUT THE OLD CONCERN: a locally performed
    // rotation that no contact learns of would still be the worst outcome.
    // That is why the work below is done in this order — first send
    // (with the OLD key, which must still be present for it), then apply.
    // Not the other way round.
    if (_devices.length > 1) {
      // ── SINCE S361 THE REASON IS A DIFFERENT ONE AGAIN ─────────────────
      //
      // The justification has moved twice, and both times because the
      // stated reason had gone away. So that it does not stay standing a
      // third time after it is no longer true, here is what has
      // FALLEN and what CARRIES.
      //
      // FALLEN (S360): "without a self-send path the rotation material does
      // not reach the own devices" — the shared twin line is built
      // (`own_line.dart`).
      //
      // FALLEN (S361): "the device-bound line from §14.1 is not built" —
      // it is built (`device_line.dart`) and is entered by `sendToUser`.
      // Addressing a device specifically works.
      //
      // ── WHAT CARRIES, AND IT IS TWO THINGS ────────────────────────
      //
      // **1. There is no package that could be sent.** §14.4 describes
      // kind 16 as "the package of wrapped new keys — one for each
      // remaining device", wrapped "with that device's own device key":
      // `wrap_d = Enc(device_key_d, shared_key(n))`. Exactly that cannot
      // be formed in the build:
      //
      //   * `TwinSyncType.DEVICE_SET_CHANGED` (kind 16) occurs NOWHERE in
      //     `lib/` — neither a producer nor a case in the receive `switch`
      //     (`_handleTwinSync`). A package the receiver does not interpret
      //     is not a delivery.
      //   * The `shared_key` from §14.4 does not exist (measured in
      //     `own_line.dart`; that is why `K_own` falls back to deriving from
      //     the user KEM secrets).
      //   * `device_key_d` of a SIBLING has no holder: `DeviceRecord`
      //     keeps no keys, only `deviceNodeIdHex` (gap G-9, the same one at
      //     which `_announceableDeviceSet` exits with `null` when
      //     `_devices.length > 1`).
      //
      // **2. Without the wrap the lock-out would be ineffective.** §14.4
      // names exactly that as the carrying property: "the exclusion is
      // structural, not rule-based". The device line does NOT achieve it
      // and cannot: its root falls out of `K_own`, and `K_own` still holds
      // a just-locked-out device — it could compute every device line
      // along and open every cell (§14.2). The separation this line
      // achieves is an OPERATIONAL one (who harvests what), not a
      // cryptographic one. Distributing it via the device line would look
      // like a solution and would not be one.
      //
      // **3. The quorum is still missing** (§14.4/§14.8,
      // `max(2, ceil(M/2))`): `approveRotation` cannot co-sign on a
      // sibling device, and `_announceableDeviceSet` cannot prove the
      // set — both gap G-9.
      //
      // The consequence of carrying on would still be the worst possible:
      // the sibling devices would not get their new keys and would be
      // locked out of the own identity after the rotation. Fail-closed
      // remains the right answer.
      _log.error('rotateIdentityKeys: ABORTED — ${_devices.length} '
          'devices on this identity. The DEVICE-BOUND line from '
          '§14.1 has been built and entered since S361; what is missing is the '
          'CONTENT: kind 16 (DEVICE_SET_CHANGED) has in this codebase '
          'neither producer nor receive case, the `shared_key` from §14.4 '
          'does not exist, and the device key of a sibling has '
          'no holder (gap G-9) — without it the lock-out is not '
          'structural, but does not happen at all. Also missing is the quorum '
          'max(2, ceil(M/2)) from §14.4/§14.8 (likewise G-9). '
          'NOTHING was rotated; the existing keys are unchanged. '
          '${_contacts.length} contact(s), ${_devices.length} device(s) '
          'would have had to be notified.');
      onStateChanged?.call();
      return;
    }

    final sodium = SodiumFFI();

    // 1. Form new keys — BEFORE any sending, so that it can be
    //    double-signed (the old signature proves "I am your contact", the
    //    new one proves "I control the new key").
    //
    //    The new keys come from FRESH entropy, not from the existing
    //    seed. §14.4: "Rotated sig keys are — like rotated KEM
    //    keys (§4.5) — random and **not seed-derivable**: the founding key
    //    remains the identity anchor from the seed". The HD path serves
    //    here only as a derivation function over the NEW seed, so that the
    //    PQ keys match it reproducibly — the same mechanism that
    //    `_handleTwinSettingsChanged` runs on the twin side.
    final newEntropy = sodium.randomBytes(32);
    final newMasterSeed = SeedPhrase.entropyToSeed(newEntropy);
    final hdIndex = identity.hdIndex ?? 0;

    final newEd25519 = HdWallet.deriveEd25519(newMasterSeed, hdIndex);
    final newX25519Pk = sodium.ed25519PkToX25519(newEd25519.publicKey);
    final newX25519Sk = sodium.ed25519SkToX25519(newEd25519.secretKey);
    final pqKeys =
        await generatePqKeysDeterministicIsolated(newMasterSeed, hdIndex);

    // 2. Build the broadcast, double-signed.
    final broadcast = proto.KeyRotationBroadcast()
      ..newEd25519Pk = newEd25519.publicKey
      ..newMlDsaPk = pqKeys.mlDsaPk
      ..newX25519Pk = newX25519Pk
      ..newMlKemPk = pqKeys.mlKemPk;
    final dataToSign = broadcast.writeToBuffer();
    broadcast.oldSignatureEd25519 =
        sodium.signEd25519(dataToSign, identity.ed25519SecretKey);
    broadcast.newSignatureEd25519 =
        sodium.signEd25519(dataToSign, newEd25519.secretKey);

    // §7.5/§14.5: the co-signature of THIS device. With exactly one device
    // it forms no quorum (§14.8: "the rule does not apply") — the
    // receiver treats a device set of size 1 as `singleDevice`.
    // It is attached anyway, so that ONE form stands on the wire and not
    // two; as soon as a self-send path exists, further tokens join it
    // without the format changing.
    final rotHash = computeRotationHash(
      newEd25519Pk: newEd25519.publicKey,
      newMlDsaPk: pqKeys.mlDsaPk,
      newX25519Pk: newX25519Pk,
      newMlKemPk: pqKeys.mlKemPk,
      userId: identity.userId,
    );
    final ownToken = _ownApprovalToken(rotHash);
    if (ownToken != null) {
      broadcast.approvalTokens.add(ownToken.toProto());
    }
    broadcast.preRotationDeviceCount = _devices.length;
    final payload = Uint8List.fromList(broadcast.writeToBuffer());

    // 3. Pairwise to every accepted contact (§14.4), signed with the
    //    OLD key — hence BEFORE step 4.
    final recipient = <String>[];
    for (final contact in _contacts.values) {
      if (contact.status != 'accepted') continue;
      if (contact.x25519Pk == null || contact.mlKemPk == null) continue;
      recipient.add(bytesToHex(contact.nodeId));
      // ── THE 31-DAY CLASS, AND HERE ALONE (§21.1, S361) ─────
      //
      // v4_1 lines 1007-1008 name exactly this delivery by name:
      // "**Distribution:** as a delivery of **the 31-day TTL class**,
      // pairwise to contacts, via twin sync to one's own devices."
      //
      // WHY THIS IS MORE THAN A DEADLINE. A contact who does not harvest
      // the announcement keeps writing against the OLD KEM key (§14.4:
      // "Contacts who missed the announcement lose the encryption, but
      // not addressability"). With the ordinary deadline of three days the
      // announcement would expire before a contact is back from a longer
      // holiday — and the rotation, which ran precisely because of a
      // suspected compromise, would stay invisible to them.
      //
      // NOT the routine rotation next door (`_performKeyRotation`, and
      // the latecomer copy in `_acceptContactRequest`): §4.5.4 says
      // explicitly for it "the rotation is announced pairwise as an
      // **ordinary** delivery". Both share the wire kind with this one —
      // the class hangs on the SENDING SITE, not on the type.
      _detachedSend(
          'MTV3_KEY_ROTATION_BROADCAST (emergency)',
          sendToUser(
            recipientUserId: contact.nodeId,
            messageType: proto.MessageTypeV3.MTV3_KEY_ROTATION_BROADCAST,
            payload: payload,
            management: true,
          ));
    }

    // 3b. THE TRANSITION WINDOWS — MANDATORILY BEFORE STEP 4.
    //
    // `K_AB` derives from the OWN current secret key and the founding
    // pubkey of the counterpart (`pair_registry.dart:211`), and step 4
    // overwrites exactly this secret key. After that `K_AB_alt` can no
    // longer be formed. Derivation, proof and the calculated price:
    // `cleona_service_rotation_window.dart`.
    _beginRotationWindows();

    // 4. ONLY NOW apply locally. `rotateIdentityFull` first appends the
    //    continuity proof old->new to the rotation chain
    //    (`identity_context.dart`, `StoredRotationLink`) — that is proof
    //    (i) from §14.4 "Verification levels at sig rotation".
    identity.rotateIdentityFull(
      newEd25519Pk: newEd25519.publicKey,
      newEd25519Sk: newEd25519.secretKey,
      newMlDsaPk: pqKeys.mlDsaPk,
      newMlDsaSk: pqKeys.mlDsaSk,
      newX25519Pk: newX25519Pk,
      newX25519Sk: newX25519Sk,
      newMlKemPk: pqKeys.mlKemPk,
      newMlKemSk: pqKeys.mlKemSk,
    );

    // 4b. THE NEW LINES MUST BE REGISTERED AGAIN — and that was a
    //     separate, silent total failure.
    //
    // `primeV41Pairs` skips every contact that is in `_v41Primed`,
    // with the justification "A pair already registered does not change
    // — `K_AB` hangs on the FOUNDING keys (§15.2), not on the current key
    // state" (`cleona_service_receive.dart`).
    // That holds for the OTHER SIDE of the DH and is correct there. For the
    // OWN side it is wrong: `v41PairKeyFor` takes
    // `identity.ed25519SecretKey` — the CURRENT key that step 4 has just
    // replaced. `_v41Primed` was cleared nowhere.
    //
    // Without this clearing the harvest after a rotation would have
    // listened permanently only on the OLD line and never registered the
    // new one — i.e. exactly the opposite of the decision.
    _v41Primed.clear();
    primeV41Pairs();

    // 4c. And now the old lines ALONGSIDE — under their own identifier,
    //     so that they do not overwrite the new ones.
    _registerOldLines();

    // 5. Bookkeeping for the resubmission (§26.6.2 package C). The manager
    //    holds the double-signed bytes, so that resending is possible
    //    without the just-overwritten old signing key.
    _keyRotationRetry.startNewRotation(
      broadcastBytes: payload,
      contactNodeIdsHex: recipient,
      oldUserIdHex: identity.userIdHex,
      now: DateTime.now().millisecondsSinceEpoch,
    );

    // 6. §14.5 path 2: the device set goes along pairwise. Without it
    //    the receiver would have no device keys after this rotation
    //    against which it could check a quorum next time.
    _announceDeviceSetToContacts(occasion: 'Schluesselrotation');

    // OPEN AND NAMED, not silently omitted:
    //  * §14.4 "The transition (normative)" requires a window in which the
    //    old and new inbound line are valid at the same time. The carrier
    //    for that was `_previousMailboxPrimary = _primaryMailboxId()`;
    //    `_primaryMailboxId()` fell with the CUT and is NOT invented here
    //    as a substitute — v4_1 §21.2 explicitly denies the mark
    //    ("There is no mailbox derivable from a pubkey"). Which mark the
    //    harvest still queries after a rotation is an open
    //    V4.1-INTERNAL design question and belongs to the owner.
    //  * §14.3: the prekey pool is not discarded separately. The reason
    //    is in §14.10 and is measured there: every sealing today falls
    //    back to the long-lived user KEM keys, and step 4 replaces
    //    them.
    _log.info('§14.10: emergency rotation carried out — all four keys '
        'replaced, broadcast to ${recipient.length} contact(s) pairwise '
        '(§14.4), co-signature '
        '${ownToken != null ? "1 eigenes Geraet" : "keine"} (§14.8).');
    onStateChanged?.call();
  }

  /// Handle incoming KEY_ROTATION from a contact.
  /// Periodic KEM-only key rotation (§7.4 Variant a). [payload] is the
  /// already-decrypted+authenticated `KeyRotation` proto bytes (V3 inner
  /// User-Sig + outer Device-Sig + KEM-decap chain verified upstream).
  /// [senderUserId] is the rotating peer's user-id (frame.senderUserId).
  void _handleKeyRotation(Uint8List payload, Uint8List senderUserId) {
    final senderHex = bytesToHex(senderUserId);
    final contact = _contacts[senderHex];
    if (contact == null || contact.status != 'accepted') return;

    try {
      final rotation = proto.KeyRotation.fromBuffer(payload);

      // Verify signature (signed with sender's ed25519 key)
      if (contact.ed25519Pk != null) {
        final dataToVerify = (proto.KeyRotation()
              ..newX25519Pk = rotation.newX25519Pk
              ..newMlKemPk = rotation.newMlKemPk
              ..rotationTimestamp = rotation.rotationTimestamp)
            .writeToBuffer();
        final valid = SodiumFFI().verifyEd25519(
          dataToVerify,
          Uint8List.fromList(rotation.signature),
          contact.ed25519Pk!,
        );
        if (!valid) {
          _log.warn('KEY_ROTATION signature invalid from ${senderHex.substring(0, 8)}');
          return;
        }
      }

      // ── THE ORDER, AND BEFORE WRITING (S363) ─────────
      //
      // `rotationTimestamp` is signed (it stands above in the
      // signature buffer) and was afterwards DISCARDED WITHOUT REPLACEMENT.
      // This place was thus order-blind: the announcement that ARRIVED
      // last won, not the newest.
      //
      // WHY THIS HAS BEEN A FINDING SINCE S361 AND HARDLY SHOWED BEFORE:
      // since S361 the harvest reaches back up to 30 epochs
      // (`harvestEpochsPlan`, `tiefe = kManagementKeepEpochs`). An
      // announcement from a deep backlog therefore regularly arrives AFTER
      // a newer one. Applied, it set the contact back to a generation the
      // counterpart has long stopped keeping — and from then on every
      // message to this contact is sealed against a dead key, silently
      // (§4.5.4: there is exactly ONE predecessor slot).
      //
      // It is at the same time the replay protection: the cell is
      // signed, so it is reusable unchanged as long as nothing checks its
      // order.
      //
      // A TIE is discarded as well — a second copy of the same
      // announcement (m x R = 60 deposits per message, §9.2, several
      // families can arrive) carries nothing new.
      final newState =
          DateTime.fromMillisecondsSinceEpoch(rotation.rotationTimestamp.toInt());
      final soFar = contact.kemRotationAt;
      if (!announcementIsNew(soFar: soFar, fresh: newState)) {
        _log.warn('KEY_ROTATION from ${senderHex.substring(0, 8)} DISCARDED: '
            'announcement of ${newState.toUtc().toIso8601String()} is '
            'not newer than the stored state '
            '${soFar?.toUtc().toIso8601String()} — stale or '
            'replayed announcement (S363).');
        return;
      }

      // Update contact's KEM keys
      contact.x25519Pk = Uint8List.fromList(rotation.newX25519Pk);
      contact.mlKemPk = Uint8List.fromList(rotation.newMlKemPk);
      // §4.5.4: the point in time against which freshness AND order are
      // measured in future. From the ANNOUNCEMENT, not from the own clock:
      // the own clock would treat a deeply late-harvested announcement as
      // brand new.
      contact.kemRotationAt = newState;
      _saveContacts();

      // Update keys in group member entries
      for (final group in _groups.values) {
        final member = group.members[senderHex];
        if (member != null) {
          member.x25519Pk = contact.x25519Pk;
          member.mlKemPk = contact.mlKemPk;
        }
      }
      _saveGroups();

      // Update keys in channel member entries
      for (final channel in _channels.values) {
        final member = channel.members[senderHex];
        if (member != null) {
          member.x25519Pk = contact.x25519Pk;
          member.mlKemPk = contact.mlKemPk;
        }
      }
      _saveChannels();

      // The routing table held a second copy of these keys and was
      // updated here. It has fallen; the contact record above is now the
      // only storage (T).

      // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
      _log.debug('Key rotation received from ${contact.displayName}');
    } on KemVersionRejectedException catch (e) {
      _warnKemVersionRejected('KEY_ROTATION', e);
    } catch (e) {
      _log.error('KEY_ROTATION processing failed: $e');
    }
  }

  // ── Multi-Device Twin-Sync (§26) ───────────────────────────────────

  /// Send a TWIN_SYNC message to all known twin devices.
  /// Encrypted with own pubkey (Per-Message KEM to self).
  /// Fan-out a Twin-Sync to every other device of this user.
  ///
  /// [targetDeviceId] restricts the send to exactly one device (its *device
  /// node id*, i.e. the routing id — not the `_devices` UUID key). Use it for
  /// syncs that are a direct answer to one specific device; broadcasting those
  /// costs a frame per twin and makes every non-addressed device log a
  /// spurious "nothing pending" (Arbeitsregel #5).
  void _sendTwinSync(proto.TwinSyncType syncType, Uint8List payload,
      {Uint8List? targetDeviceId}) {
    final hasTarget = targetDeviceId != null && targetDeviceId.isNotEmpty;
    // The twin-count guard only makes sense for the fan-out case. With an
    // explicit target the peer is known by construction — we are answering a
    // frame it just sent us — and `sendToUser`'s targetDeviceId branch sits
    // ahead of the self fan-out, so it never consults `_devices` at all.
    if (!hasTarget && _devices.length <= 1) return; // No twins to sync to

    final syncId = SodiumFFI().randomBytes(16);
    final syncIdHex = bytesToHex(syncId);
    // Pre-mark with current timestamp to avoid processing our own sync + 7d TTL
    _processedSyncIds[syncIdHex] = DateTime.now().millisecondsSinceEpoch;

    // ONE derivation site (`twin_sync_wire.dart`) — the envelope was built
    // by hand twice, here and in `_sendTwinAnnounce`, and neither of the
    // two places was checkable from outside.
    final syncBytes = buildTwinSyncEnvelope(
      syncId: syncId,
      deviceId: hexToBytes(_localDeviceId),
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      syncType: syncType,
      payload: payload,
    );

    // V3: TWIN_SYNC fan-out to our own user-id resolves all our authorized
    // device-ids — canonical multi-device use case for sendToUser.
    //
    // HERE STOOD A `try { … } catch (e) { _log.warn(…) }` AROUND THE CALL.
    // It never caught anything and was therefore worse than no
    // protection: it made the place LOOK safeguarded. `sendToUser` is
    // `async`, and an `async` function NEVER throws synchronously — every
    // throw in its body lands in the returned `Future`, which was thrown
    // away here, and went from there into the zone
    // (`service_daemon.dart` ~L424) and into `exit(99)`. Measured in
    // `test/smoke/smoke_self_send_v41_guard.dart`. `_detachedSend` is
    // the latch that really takes hold at this place.
    _detachedSend('MTV3_TWIN_SYNC', sendToUser(
      recipientUserId: identity.nodeId,
      messageType: proto.MessageTypeV3.MTV3_TWIN_SYNC,
      payload: syncBytes,
      targetDeviceId: hasTarget ? targetDeviceId : null,
    ));
    _log.debug(hasTarget
        ? 'TWIN_SYNC($syncType) sent to device '
            '${_hexShort(targetDeviceId)}'
        : 'TWIN_SYNC($syncType) sent to ${_devices.length - 1} twins');
  }

  /// Send TWIN_ANNOUNCE to register this device with existing twins.
  void _sendTwinAnnounce() {
    if (_devices.length <= 1) return;

    final record = proto.DeviceRecord()
      ..deviceId = hexToBytes(_localDeviceId)
      ..deviceName = _devices[_localDeviceId]?.deviceName ?? Platform.localHostname
      ..platform = _platformToProto(_detectPlatform())
      ..firstSeen = Int64(_devices[_localDeviceId]?.firstSeen.millisecondsSinceEpoch ?? 0)
      ..lastSeen = Int64(DateTime.now().millisecondsSinceEpoch)
      ..deviceNodeId = identity.deviceNodeId;

    final payload = Uint8List.fromList(record.writeToBuffer());

    // V3: no MTV3_TWIN_ANNOUNCE — wrapped as TWIN_SYNC sub-type DEVICE_ANNOUNCE.
    try {
      final wrapper = buildTwinSyncEnvelope(
        syncId: SodiumFFI().randomBytes(16),
        deviceId: hexToBytes(_localDeviceId),
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        syncType: proto.TwinSyncType.DEVICE_ANNOUNCE,
        payload: payload,
      );
      _detachedSend('MTV3_TWIN_SYNC', sendToUser(
        recipientUserId: identity.nodeId,
        messageType: proto.MessageTypeV3.MTV3_TWIN_SYNC,
        payload: wrapper,
      ));
      _log.info('TWIN_ANNOUNCE (V3 TWIN_SYNC/DEVICE_ANNOUNCE) sent for $_localDeviceId');
    } catch (e) {
      _log.warn('Failed to send TWIN_ANNOUNCE: $e');
    }
  }

  static proto.DevicePlatform _platformToProto(String platform) {
    switch (platform) {
      case 'android': return proto.DevicePlatform.PLATFORM_ANDROID;
      case 'ios': return proto.DevicePlatform.PLATFORM_IOS;
      case 'linux': return proto.DevicePlatform.PLATFORM_LINUX;
      case 'windows': return proto.DevicePlatform.PLATFORM_WINDOWS;
      case 'macos': return proto.DevicePlatform.PLATFORM_MACOS;
      default: return proto.DevicePlatform.PLATFORM_UNKNOWN;
    }
  }

  static String _detectPlatformFromProto(proto.DevicePlatform p) {
    switch (p) {
      case proto.DevicePlatform.PLATFORM_ANDROID: return 'android';
      case proto.DevicePlatform.PLATFORM_IOS: return 'ios';
      case proto.DevicePlatform.PLATFORM_LINUX: return 'linux';
      case proto.DevicePlatform.PLATFORM_WINDOWS: return 'windows';
      case proto.DevicePlatform.PLATFORM_MACOS: return 'macos';
      default: return 'unknown';
    }
  }

  // ── Twin-Sync sub-handlers ─────────────────────────────────────────

  void _handleTwinContactAdded(List<int> payload) {
    try {
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      final nodeIdHex = json['nodeId'] as String;
      if (_contacts.containsKey(nodeIdHex)) return; // Already known

      final contact = ContactInfo(
        nodeId: hexToBytes(nodeIdHex),
        displayName: json['displayName'] as String? ?? '',
        ed25519Pk: json['ed25519Pk'] != null ? hexToBytes(json['ed25519Pk'] as String) : null,
        x25519Pk: json['x25519Pk'] != null ? hexToBytes(json['x25519Pk'] as String) : null,
        mlKemPk: json['mlKemPk'] != null ? hexToBytes(json['mlKemPk'] as String) : null,
        mlDsaPk: json['mlDsaPk'] != null ? hexToBytes(json['mlDsaPk'] as String) : null,
        status: 'accepted',
        acceptedAt: DateTime.now(),
        // §15.2: the twin's anchor, if it sent it along.
        // If it is missing (twin on old version), the initial filling in
        // `v41PeerFoundingPk` falls back to `ed25519Pk` — the same
        // behaviour as before S361, just without the advantage.
        peerFoundingEd25519Pk: json['peerFoundingEd25519Pk'] != null
            ? hexToBytes(json['peerFoundingEd25519Pk'] as String)
            : null,
      );
      final twinDeviceIds = json['deviceNodeIds'];
      if (twinDeviceIds is List) {
        contact.deviceNodeIds.addAll(twinDeviceIds.cast<String>());
      }
      _contacts[nodeIdHex] = contact;
      _saveContacts();
      // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
      _log.debug('Twin-synced contact added: ${json['displayName']}');
      onStateChanged?.call();
    } catch (e) {
      _log.warn('Twin CONTACT_ADDED failed: $e');
    }
  }

  void _handleTwinMessageSent(List<int> payload) {
    try {
      // Payload is a JSON-encoded map: {conversationId, text, messageId, timestamp}
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      final conversationId = json['conversationId'] as String;
      final text = json['text'] as String;
      final messageId = json['messageId'] as String;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int);

      // Avoid duplicate if we already have this message
      final conv = conversations[conversationId];
      ensureLoaded(conversationId);
      if (conv != null && conv.messages.any((m) => m.id == messageId)) return;

      final msg = UiMessage(
        id: messageId,
        conversationId: conversationId,
        senderNodeIdHex: identity.userIdHex,
        text: text,
        timestamp: timestamp,
        type: UiMessageType.text,
        // AP-4: the twin mirrors a message that was never sent on THIS
        // device — there is no observation here, only the other device's
        // notice. `placing` is the only value that claims nothing.
        status: MessageStatus.resting,
        isOutgoing: true,
      );

      if (conv != null) {
        int insertIdx = conv.messages.length;
        ensureLoaded(conversationId);
        for (int i = conv.messages.length - 1; i >= 0; i--) {
          if (conv.messages[i].timestamp.compareTo(msg.timestamp) <= 0) {
            insertIdx = i + 1;
            break;
          }
          if (i == 0) insertIdx = 0;
        }
        conv.messages.insert(insertIdx, msg);
        conv.lastActivity = timestamp;
        _saveConversations();
        onStateChanged?.call();
      }
      _log.debug('Twin-synced outgoing message to $conversationId');
    } catch (e) {
      _log.warn('Twin MESSAGE_SENT failed: $e');
    }
  }

  void _handleTwinMessageEdited(List<int> payload) {
    try {
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      final conversationId = json['conversationId'] as String;
      final messageId = json['messageId'] as String;
      final newText = json['text'] as String;

      final conv = conversations[conversationId];
      if (conv == null) return;
      ensureLoaded(conversationId);
      final msg = conv.messages.where((m) => m.id == messageId).firstOrNull;
      if (msg == null) return;

      msg.text = newText;
      msg.editedAt = DateTime.now();
      persistMessage(conversationId, msg);
      _saveConversations();
      onStateChanged?.call();
      _log.debug('Twin-synced message edit in $conversationId');
    } catch (e) {
      _log.warn('Twin MESSAGE_EDITED failed: $e');
    }
  }

  void _handleTwinMessageDeleted(List<int> payload) {
    try {
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      final conversationId = json['conversationId'] as String;
      final messageId = json['messageId'] as String;

      final conv = conversations[conversationId];
      if (conv == null) return;
      ensureLoaded(conversationId);
      final msg = conv.messages.where((m) => m.id == messageId).firstOrNull;
      if (msg == null) return;

      msg.isDeleted = true;
      msg.text = '';
      persistMessage(conversationId, msg);
      _saveConversations();
      onStateChanged?.call();
      _log.debug('Twin-synced message delete in $conversationId');
    } catch (e) {
      _log.warn('Twin MESSAGE_DELETED failed: $e');
    }
  }

  void _handleTwinReadReceipt(List<int> payload) {
    try {
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      final conversationId = json['conversationId'] as String;

      final conv = conversations[conversationId];
      if (conv == null) return;
      if (conv.unreadCount == 0) return;
      conv.unreadCount = 0;
      // Bug #U3+#U15: twin-device read must also update the Android launcher
      // badge — otherwise the badge stays stuck on the primary, although
      // the user has read on the second device.
      onCancelNotificationAndroid?.call(conversationId);
      _updateBadgeCount();
      _saveConversations();
      onStateChanged?.call();
    } catch (e) {
      _log.warn('Twin READ_RECEIPT failed: $e');
    }
  }

  /// Handle SETTINGS_CHANGED from twin: includes emergency key rotation (§26.6.2)
  /// and §7.1 LD-8 delegation rotation.
  /// Async: PQ keygen runs in background isolate (ANR fix).
  Future<void> _handleTwinSettingsChanged(List<int> payload) async {
    try {
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;

      // §7.1 LD-8: delegation rotation for Linked Devices (no seed transfer)
      if (json['delegationRotation'] == true) {
        await _handleDelegationRotation(json);
        return;
      }

      if (json['emergencyRotation'] == true) {
        // §7.1 LD-5: Linked Devices must NOT process seed entropy —
        // they receive delegation rotation via the path above.
        if (identity.isLinkedDevice) {
          _log.warn('Ignoring emergency rotation entropy — '
              'this is a Linked Device (LD-5 guard)');
          return;
        }
        final newEntropyHex = json['newEntropy'] as String;
        final hdIndex = json['hdIndex'] as int? ?? identity.hdIndex ?? 0;
        final newEntropy = hexToBytes(newEntropyHex);
        final newMasterSeed = SeedPhrase.entropyToSeed(newEntropy);

        final sodium = SodiumFFI();
        final newEd25519 = HdWallet.deriveEd25519(newMasterSeed, hdIndex);
        final newX25519Pk = sodium.ed25519PkToX25519(newEd25519.publicKey);
        final newX25519Sk = sodium.ed25519SkToX25519(newEd25519.secretKey);

        // PQ keygen: deterministic from new seed
        final pqKeys = await generatePqKeysDeterministicIsolated(newMasterSeed, hdIndex);

        identity.rotateIdentityFull(
          newEd25519Pk: newEd25519.publicKey,
          newEd25519Sk: newEd25519.secretKey,
          newMlDsaPk: pqKeys.mlDsaPk,
          newMlDsaSk: pqKeys.mlDsaSk,
          newX25519Pk: newX25519Pk,
          newX25519Sk: newX25519Sk,
          newMlKemPk: pqKeys.mlKemPk,
          newMlKemSk: pqKeys.mlKemSk,
        );
        // §5.11 — same as the originating-device path: push refreshed
        // PeerInfo to all known peers so the mesh heals stale-PK caches
        // without waiting for the §5.12 cold-path 1 h tick.
        // `node.broadcastAddressUpdate()` and the manifest republish
        // stood here — both §4.3/§5.11 and fallen with the CUT (T).
        _log.info('Emergency key rotation applied from twin. '
            'UserID ${identity.userIdHex.substring(0, 16)}... unchanged '
            '(stable anchor)');
        onStateChanged?.call();
      }
    } catch (e) {
      _log.warn('Twin SETTINGS_CHANGED failed: $e');
    }
  }

  void _handleTwinDeviceRevoked(List<int> payload) {
    try {
      final deviceIdHex = utf8.decode(payload);
      if (deviceIdHex == _localDeviceId) {
        // This device has been revoked — wipe and return to welcome
        _log.warn('THIS DEVICE has been revoked by another twin!');
        // Wipe will be handled by the GUI layer via callback
        _notifyDevicesChanged();
        return;
      }
      final revoked = _devices.remove(deviceIdHex);
      _saveDevices();
      // §7.4/§7.5: same state transition as `revokeDevice`, only arriving over
      // twin-sync instead of local IPC — including the co-auth attempt, since
      // this is the path a Primary takes when a Linked Device initiated the
      // revocation. Without it the Primary would keep publishing a device
      // another device revoked. Read the record from the `remove` return
      // value: `deviceNodeIdHex` is needed to key the delegation, and it is
      // gone from the map by now.
      unawaited(_applyDeviceSetRemoval(revoked, deviceIdHex));
      // §14.10: mirror of the call in `revokeDevice` — this is the path the
      // PRIMARY takes when a LINKED DEVICE initiated the revocation over
      // twin-sync. `rotateIdentityKeys()` self-guards on `isLinkedDevice`, so
      // calling it unconditionally here is safe: on the Primary it does the
      // real work, on every other Linked Device this twin-sync message also
      // reaches it just logs and returns.
      unawaited(rotateIdentityKeys());
      _log.info('Twin device revoked: $deviceIdHex');
      _notifyDevicesChanged();
    } catch (e) {
      _log.warn('Twin DEVICE_REVOKED failed: $e');
    }
  }

  /// Emergency full key rotation (§26.6.2): dual-signature verification,
  /// ALL keys updated, Node-ID re-keyed across contacts/groups/channels.
  void _handleEmergencyKeyRotation(
    Uint8List senderUserId,
    ContactInfo contact,
    String senderHex,
    proto.KeyRotationBroadcast broadcast,
  ) {
    final sodium = SodiumFFI();

    // The data that was signed = broadcast without signature fields
    final dataToVerify = (proto.KeyRotationBroadcast()
          ..newEd25519Pk = broadcast.newEd25519Pk
          ..newMlDsaPk = broadcast.newMlDsaPk
          ..newX25519Pk = broadcast.newX25519Pk
          ..newMlKemPk = broadcast.newMlKemPk)
        .writeToBuffer();

    // 1. Verify old signature: proves sender IS our known contact
    if (contact.ed25519Pk == null) {
      _log.warn('KEY_ROTATION_BROADCAST: no Ed25519 key for ${senderHex.substring(0, 8)}');
      return;
    }
    if (!sodium.verifyEd25519(
      dataToVerify,
      Uint8List.fromList(broadcast.oldSignatureEd25519),
      contact.ed25519Pk!,
    )) {
      _log.warn('KEY_ROTATION_BROADCAST: old signature INVALID from ${senderHex.substring(0, 8)}');
      return;
    }

    // 2. Verify new signature: proves sender controls new key
    final newEd25519Pk = Uint8List.fromList(broadcast.newEd25519Pk);
    if (!sodium.verifyEd25519(
      dataToVerify,
      Uint8List.fromList(broadcast.newSignatureEd25519),
      newEd25519Pk,
    )) {
      _log.warn('KEY_ROTATION_BROADCAST: new signature INVALID from ${senderHex.substring(0, 8)}');
      return;
    }

    // Both signatures valid — update ALL contact keys
    final newMlDsaPk = Uint8List.fromList(broadcast.newMlDsaPk);
    final newX25519Pk = Uint8List.fromList(broadcast.newX25519Pk);
    final newMlKemPk = Uint8List.fromList(broadcast.newMlKemPk);

    // §7.5 co-auth: check the co-signatures against the device signing
    // keys that this node has stored for the contact.
    //
    // HERE STOOD `const cachedDeviceSigKeys = <DeviceSigInfo>[]` — a list
    // empty at compile time, because in V4.1 there was no storage place
    // for the device keys of A CONTACT (gap G-9, receiving side).
    // Consequence: the `else` branch below was dead code, the result was
    // without exception `legacy`, and every emergency rotation was applied
    // UNCHECKED — the §7.5 protection against a seed thief was universally
    // absent.
    //
    // The storage place is now `ContactInfo.deviceSigKeys`, filled by the
    // pairwise device-set announcement from §14.5 path 2
    // (`cleona_service_deviceset.dart`).
    //
    // `legacy` REMAINS a valid outcome, and that is not a residual gap,
    // but §14.5 literally: "A brand-new contact does not know `N`, a
    // long-absent one has a stale state. Then: the case counts as a legacy
    // case … and the new key is **applied anyway** — the **visibility
    // principle**." The difference to before is that it is now the
    // exception instead of the rule.
    final cachedDeviceSigKeys = contact.deviceSigKeys
        .map((d) => d.toSigInfo())
        .whereType<DeviceSigInfo>()
        .toList();
    RotationCoAuthResult coAuthResult;

    if (cachedDeviceSigKeys.isEmpty) {
      _log.info('§7.5: no stored device set for '
          '${senderHex.substring(0, 8)} — „legacy" per §14.5 (new or '
          'long absent contact): apply with visible warning.');
      coAuthResult = RotationCoAuthResult.legacy;
    } else {
      final rotHash = computeRotationHash(
        newEd25519Pk: newEd25519Pk,
        newMlDsaPk: newMlDsaPk,
        newX25519Pk: newX25519Pk,
        newMlKemPk: newMlKemPk,
        userId: senderUserId,
      );
      final tokens = broadcast.approvalTokens
          .map(RotationApprovalToken.fromProto)
          .toList();
      coAuthResult = verifyRotationCoAuth(
        tokens: tokens,
        cachedDeviceSigKeys: cachedDeviceSigKeys,
        rotationHash: rotHash,
        // Key rotation keeps the full device set, so the quorum stays
        // `rotationQuorum(cachedDeviceSigKeys.length)` — unchanged §7.5
        // semantics. `broadcast.preRotationDeviceCount` was passed here
        // before and never read; it is the sender's own claim and is left
        // out rather than given a meaning it cannot carry.
        occasion: CoAuthOccasion.keyRotation,
      );
      _log.info('§7.5 Co-Auth result for ${senderHex.substring(0, 8)}: '
          '$coAuthResult (${tokens.length} tokens, '
          '${cachedDeviceSigKeys.length} cached devices, '
          'quorum=${rotationQuorum(cachedDeviceSigKeys.length)})');
    }

    // Keys are applied for every rotation the §8.3 setter ACCEPTS (SR-1:
    // visibility, not prevention). Finding 11: a refused anchor write is the
    // one exception — a rotation onto one of our own hosted identity keys (or
    // a half hybrid pair) must not be applied at all. Writing only the KEM
    // keys would leave the record on its old signing anchor while every
    // outbound message gets encrypted to the rotator's KEM key.
    if (!_setContactTrustAnchor(contact, senderHex, newEd25519Pk, newMlDsaPk,
        source: 'key rotation')) {
      _log.warn('§8.3: KEY_ROTATION_BROADCAST from ${senderHex.substring(0, 8)} '
          '— anchor write REFUSED, rotation NOT applied, contact keys unchanged');
      return;
    }
    contact.x25519Pk = newX25519Pk;
    contact.mlKemPk = newMlKemPk;
    // §4.5.4/S363: the copy is observed NOW. The emergency rotation carries
    // no `rotationTimestamp` (`KeyRotationBroadcast` does not have the
    // field), so the own clock is the only source here — and it is
    // admissible because this path checks the double signature, so it
    // cannot come from an old deposit without both signatures still being
    // valid. Without this line the freshness measurement after an
    // emergency rotation kept using `acceptedAt` and reported a contact
    // that had only just been refreshed as stale.
    contact.kemRotationAt = DateTime.now();

    // SR-1 (§7.4b step 6 / §8.3): route the rotation through Key-Change-
    // Detection (policy in key_change_policy.dart). The dual-sig + chain make
    // the rotation cryptographically valid, so we DO apply the new keys
    // (comms keep working, a legitimate rotation is not blocked) — but a
    // valid chain does NOT prove the rotation was authorized by the
    // legitimate owner vs. a seed-holding thief, so we never follow it
    // silently at full trust. Reset the verification level and surface a
    // key-change warning, exactly like any other identity-key change.
    final prevLevel = contact.verificationLevel;
    // §14.4 "Verification levels at sig rotation (normative)": the level
    // stays if BOTH proofs are present — the continuity proof with the
    // old key (checked above, otherwise we would not be here) and the
    // quorum. Until S360 (ii) never existed, because the device set had no
    // storage place; the level therefore dropped without exception.
    final keyChange = onIdentityRotation(
      prevLevel,
      quorumMet: coAuthResult == RotationCoAuthResult.quorumMet,
      oldSignatureValid: true,
    );
    final wasVerified = keyChange.wasVerified;
    contact.verificationLevel = keyChange.newLevel;

    // SR-2 (§7.4b step 5, stable anchor): the contact's UserID does NOT
    // change — it is pinned to the founding key (§3.1); the rotating side
    // proves continuity via the rotation chain in its Auth-Manifests
    // (§4.3 path 2). Keys are updated IN PLACE; contact entry, groups,
    // channels and conversations are untouched (verification level is reset
    // above per SR-1).
    // (The pre-SR-2 implementation recomputed the UserID here and migrated
    // contact/groups/channels/conversations to the new hex — that
    // contradicted §3.1 and wiped per-identity continuity.)
    // The same for the emergency rotation: the second copy in the
    // routing table including `PkSource.firstParty` fell with it (T).
    for (final group in _groups.values) {
      final member = group.members[senderHex];
      if (member != null) {
        member.ed25519Pk = newEd25519Pk;
        member.x25519Pk = newX25519Pk;
        member.mlKemPk = newMlKemPk;
      }
    }
    _saveGroups();
    for (final channel in _channels.values) {
      final member = channel.members[senderHex];
      if (member != null) {
        member.ed25519Pk = newEd25519Pk;
        member.x25519Pk = newX25519Pk;
        member.mlKemPk = newMlKemPk;
      }
    }
    _saveChannels();

    _saveContacts();

    // §26.6.2 Send KEY_ROTATION_ACK back to the rotator — same UserID as
    // before (stable anchor). Pure ACK — empty payload. V3 inner User-Sig +
    // outer Device-Sig + KEM-decap chain provides package-C-F2 forge defence.
    unawaited(sendToUser(
      recipientUserId: senderUserId,
      messageType: proto.MessageTypeV3.MTV3_KEY_ROTATION_ACK,
      payload: Uint8List(0),
    ));

    // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
    _log.debug('Emergency key rotation from ${contact.displayName}: '
        'all keys updated in place, UserID ${senderHex.substring(0, 8)} '
        'unchanged (stable anchor); verification reset '
        '$prevLevel→${contact.verificationLevel} (SR-1 visibility), '
        'coAuth=$coAuthResult');
    // SR-1: surface the key-change warning to the UI so a soft re-key is
    // never followed silently. Fired for every accepted rotation; the UI
    // decides how loudly to warn based on `wasVerified`.
    try {
      onContactIdentityRotated?.call(
          senderHex, contact.displayName, wasVerified);
    } catch (e) {
      _log.warn('onContactIdentityRotated listener threw: $e');
    }
    // §7.5: escalated warning when co-auth quorum is NOT met on a
    // multi-device identity (possible Primary theft).
    if (coAuthResult == RotationCoAuthResult.quorumNotMet) {
      final tokens = broadcast.approvalTokens.length;
      final required = rotationQuorum(cachedDeviceSigKeys.length);
      try {
        onRotationCoAuthWarning?.call(
            senderHex, contact.displayName, tokens, required);
      } catch (e) {
        _log.warn('onRotationCoAuthWarning listener threw: $e');
      }
    }
    onStateChanged?.call();
  }

  /// V3 handler for MTV3_KEY_ROTATION_ACK (§26.6.2). Pure ACK — frame.payload
  /// is empty. Auth is the §23.3 inner User-Sig + outer Device-Sig + KEM-
  /// decap chain (verified upstream by the V3 receive pipeline), providing
  /// package-C-F2 forge defence.
  void _handleKeyRotationAckV3(HarvestEvent event) {
    final senderHex = event.senderUserId.hex;
    if (!_contacts.containsKey(senderHex)) {
      _log.warn('KEY_ROTATION_ACK V3 from unknown sender ${senderHex.substring(0, 8)} — dropped');
      return;
    }
    _keyRotationRetry.markAcked(senderHex);
    // §14.4 / owner decision 01.09.: THIS ACK IS THE PROOF that the
    // contact has the new keys — it can only authenticate it under
    // `K_AB_neu` once it has adopted the new pubkey, and a frame whose MAC
    // does not hold never arrives here (`verifyV41Sender`, verdict
    // `forged` is discarded). The old pair line of this contact therefore
    // falls IMMEDIATELY, not only at the cap.
    _noteContactHasNewKeys(senderHex);
    final acked = _keyRotationRetry.ackedCount;
    final pending = _keyRotationRetry.pendingCount;
    final expired = _keyRotationRetry.expiredCount;
    _log.info('KEY_ROTATION_ACK V3 from ${senderHex.substring(0, 8)} '
        '(acked=$acked pending=$pending expired=$expired)');
    if (pending == 0 && acked > 0) {
      _log.info('All still-reachable contacts acknowledged key rotation');
    }
    _emitKeyRotationRetryEvents();
  }

  /// §7.5: handle ROTATION_REJECTION_ALERT from a Linked Device of a contact.
  ///
  /// SECURITY — every field of this payload is verified before the callback
  /// fires. This is the strongest theft signal the system has; acting on an
  /// unverified one lets anybody who knows a contact's userId raise it.
  ///
  /// The alert carries exactly the field set of a [RotationApprovalToken]
  /// (deviceNodeId + rotationHash + Ed25519/ML-DSA Device-Sigs), so the token
  /// type verifies it — the same class §7.5 already uses for the countersigs
  /// in a KeyRotationBroadcast. [verifyRotationCoAuth] itself is not reusable
  /// here: it answers a quorum question over a *set* of tokens, while a
  /// rejection alert is a single statement by a single device. Reusing the
  /// token primitive keeps one implementation of this signature class.
  ///
  /// Two conditions, both mandatory:
  ///  1. The signatures verify against the Device-Sig pubkeys the sender's
  ///     AuthManifest published — the same cached manifest the co-auth check
  ///     in the KEY_ROTATION_BROADCAST path reads.
  ///  2. The claimed `deviceNodeId` is actually one of that user's authorized
  ///     devices. Without this a valid signature by *some* key would still be
  ///     accepted as long as it matched whatever pubkey was looked up.
  ///
  /// Anything that fails is dropped with a log and NO callback. Note that a
  /// missing or single-device manifest also means "drop": there is no weaker
  /// fallback check that would be worth anything here, because the whole
  /// point of §7.5 is that Device-Sig keys are the one thing a seed thief
  /// cannot produce.
  void _handleRotationRejectionAlertV3(HarvestEvent event) {
    try {
      final alert = proto.RotationRejectionAlertPayload.fromBuffer(event.payload);
      final alertUserId = Uint8List.fromList(alert.userId);
      final userIdHex = bytesToHex(alertUserId);
      final contact = _contacts[userIdHex];
      if (contact == null) {
        _log.warn('ROTATION_REJECTION_ALERT for unknown user $userIdHex — dropped');
        return;
      }

      // The alert speaks about its own sender's identity. `_sendRotationRejectionAlert`
      // always writes `identity.userId`, and the frame's sender user-id is
      // verified upstream by the V3 pipeline — so a mismatch means someone is
      // making a statement about a *third party*, which this message type
      // cannot do.
      final frameSenderUserId = Uint8List.fromList(event.senderUserId);
      if (!constantTimeEquals(alertUserId, frameSenderUserId)) {
        _log.warn('§7.5 ROTATION_REJECTION_ALERT: payload userId '
            '${userIdHex.substring(0, 8)} != frame sender '
            '${bytesToHex(frameSenderUserId).substring(0, 8)} — dropped');
        return;
      }

      // Device-Sig pubkeys of that user, as published in their AuthManifest.
      // FORMERLY from the AuthManifest cache (§4.3, fallen).
      // The doc comment above says explicitly that a missing manifest
      // means "drop" and that there is no weaker substitute —
      // "the whole point of §7.5 is that Device-Sig keys are the one
      // thing a seed thief cannot produce". Exactly this branch now
      // always applies (gap G-9). A theft alarm is therefore NO LONGER
      // shown; that is the fail-closed outcome and the consequence is in
      // the log.
      // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
      _log.debug('§7.5 ROTATION_REJECTION_ALERT from ${contact.displayName}: '
          'the device signature keys of ${userIdHex.substring(0, 8)} '
          'have no storage location in V4.1 (gap G-9) — not verifiable, '
          'discarded. No unverified theft alarm.');
      return;
    } catch (e) {
      _log.warn('§7.5 ROTATION_REJECTION_ALERT: processing failed: $e');
    }
  }

  /// Send an encrypted payload to a single contact (V3 sendToUser path).
  /// `messageType` is already a V3 `MessageTypeV3` — KEM/Sig/zstd are
  /// handled inside `sendToUser`. Used by the Calendar/Polls/Free-Busy
  /// cluster.
  Future<void> _sendEncryptedPayload(
    Uint8List recipientUserId,
    proto.MessageTypeV3 messageType,
    Uint8List payload, {
    Uint8List? groupId,
  }) async {
    final recipientHex = bytesToHex(recipientUserId);
    final contact = _contacts[recipientHex];
    if (contact == null || contact.x25519Pk == null || contact.mlKemPk == null) {
      _log.warn('Cannot send $messageType to $recipientHex: missing keys');
      return;
    }
    await sendToUser(
      recipientUserId: recipientUserId,
      messageType: messageType,
      payload: payload,
      groupId: groupId,
    );
    statsCollector.addMessageSent();
  }

  // ── Calendar (§23) — forwarded to CalendarProtocolService ─────────

  @override
  Future<String> createCalendarEvent(CalendarEvent event) =>
      _calendarProto.createCalendarEvent(event);
  @override
  Future<bool> updateCalendarEvent(String eventIdHex, {
    String? title, String? description, String? location,
    int? startTime, int? endTime, bool? allDay, bool? hasCall,
    List<int>? reminders, String? recurrenceRule,
    bool? taskCompleted, int? taskPriority, bool? cancelled,
    List<String>? attendeeNodeIds,
  }) => _calendarProto.updateCalendarEvent(eventIdHex,
    title: title, description: description, location: location,
    startTime: startTime, endTime: endTime, allDay: allDay,
    hasCall: hasCall, reminders: reminders, recurrenceRule: recurrenceRule,
    taskCompleted: taskCompleted, taskPriority: taskPriority, cancelled: cancelled);
  @override
  Future<bool> deleteCalendarEvent(String eventIdHex) =>
      _calendarProto.deleteCalendarEvent(eventIdHex);
  @override
  Future<void> sendCalendarInvite(CalendarEvent event) =>
      _calendarProto.sendCalendarInvite(event);
  @override
  Future<void> sendCalendarRsvp(String eventIdHex, RsvpStatus status, {
    int? proposedStart, int? proposedEnd, String? comment,
  }) => _calendarProto.sendCalendarRsvp(eventIdHex, status,
    proposedStart: proposedStart, proposedEnd: proposedEnd, comment: comment);
  @override
  Future<void> sendCalendarUpdate(String eventIdHex) =>
      _calendarProto.sendCalendarUpdate(eventIdHex);
  @override
  Future<void> sendCalendarDelete(String eventIdHex) =>
      _calendarProto.sendCalendarDelete(eventIdHex);
  @override
  Future<String> sendFreeBusyRequest(String contactNodeIdHex, int queryStart, int queryEnd) =>
      _calendarProto.sendFreeBusyRequest(contactNodeIdHex, queryStart, queryEnd);

  // ── Polls (§24) — forwarded to PollService ────────────────────────

  @override
  Future<String> createPoll({
    required String question,
    String description = '',
    required PollType pollType,
    required List<PollOption> options,
    required PollSettings settings,
    required String groupIdHex,
  }) => _polls.createPoll(
    question: question, description: description, pollType: pollType,
    options: options, settings: settings, groupIdHex: groupIdHex);

  @override
  Future<bool> submitPollVote({
    required String pollId,
    List<int>? selectedOptions,
    Map<int, DateAvailability>? dateResponses,
    int? scaleValue,
    String? freeText,
  }) => _polls.submitPollVote(
    pollId: pollId, selectedOptions: selectedOptions,
    dateResponses: dateResponses, scaleValue: scaleValue, freeText: freeText);

  @override
  Future<bool> submitPollVoteAnonymous({
    required String pollId,
    List<int>? selectedOptions,
    Map<int, DateAvailability>? dateResponses,
    int? scaleValue,
    String? freeText,
  }) => _polls.submitPollVoteAnonymous(
    pollId: pollId, selectedOptions: selectedOptions,
    dateResponses: dateResponses, scaleValue: scaleValue, freeText: freeText);

  @override
  Future<bool> revokePollVoteAnonymous(String pollId) =>
      _polls.revokePollVoteAnonymous(pollId);

  @override
  Future<bool> updatePoll(String pollId, {
    bool? close,
    bool? reopen,
    List<PollOption>? addOptions,
    List<int>? removeOptions,
    int? newDeadline,
    bool delete = false,
  }) => _polls.updatePoll(pollId,
    close: close, reopen: reopen, addOptions: addOptions,
    removeOptions: removeOptions, newDeadline: newDeadline, delete: delete);

  @override
  Future<String?> convertDatePollToEvent(String pollId, int winningOptionId) async {
    if (_reducedMode) {
      _log.warn('convertDatePollToEvent blocked: reducedMode active');
      return null;
    }
    final poll = pollManager.polls[pollId];
    if (poll == null || poll.pollType != PollType.datePoll) return null;
    final option = poll.options.firstWhere(
      (o) => o.optionId == winningOptionId,
      orElse: () => PollOption(optionId: -1, label: ''),
    );
    if (option.optionId == -1 || option.dateStart == null || option.dateEnd == null) {
      return null;
    }
    final event = CalendarEvent(
      eventId: PollManager.generateUuid(),
      identityId: identity.userIdHex,
      title: poll.question,
      startTime: option.dateStart!,
      endTime: option.dateEnd!,
      category: EventCategory.meeting,
      groupId: _groups.containsKey(poll.groupId) ? poll.groupId : null,
      createdBy: identity.userIdHex,
    );
    await createCalendarEvent(event);
    return event.eventId;
  }

  /// Send a Restore Broadcast to all known contacts, requesting they re-send
  /// our contact list and recent messages.
  /// [oldEd25519Sk] is the old secret key (derived from seed) to prove ownership.
  /// [oldNodeId] is our previous node ID.
  @override
  Future<bool> sendRestoreBroadcast({
    required Uint8List oldEd25519Sk,
    required Uint8List oldEd25519Pk,
    required Uint8List oldNodeId,
    required List<ContactInfo> oldContacts,
    // H-2: old ML-DSA-65 secret key for the hybrid inner signature. In the
    // dominant deterministic same-seed recovery the re-derived key is
    // identical to the old one (§6.3.5 PQ-handling), so the caller passes
    // `identity.mlDsaSecretKey`. Null → classical-only broadcast (legacy
    // transition; receivers accept it until the Phase-2 gate).
    Uint8List? oldMlDsaSk,
  }) async {
    // Rate limiting: max 1 per 5 minutes
    if (_lastRestoreBroadcast != null &&
        DateTime.now().difference(_lastRestoreBroadcast!).inMinutes < 5) {
      _log.warn('Restore broadcast rate limited');
      return false;
    }
    _lastRestoreBroadcast = DateTime.now();

    final rb = proto.RestoreBroadcast()
      ..oldNodeId = oldNodeId
      ..newNodeId = identity.nodeId
      ..newEd25519Pk = identity.ed25519PublicKey
      ..newX25519Pk = identity.x25519PublicKey
      ..newMlKemPk = identity.mlKemPublicKey
      ..newMlDsaPk = identity.mlDsaPublicKey
      ..displayName = displayName
      ..timestamp = Int64(DateTime.now().millisecondsSinceEpoch);

    // H-2: hybrid inner signature — sign the canonical body with BOTH the
    // old Ed25519 key (classical ownership) AND the old ML-DSA-65 key (PQ
    // ownership). A classical-only forge of the contact's Ed25519 key no
    // longer suffices to forge a restore takeover. Both signature fields are
    // empty while signing so they cover identical canonical bytes.
    final dataToSign = rb.writeToBuffer();
    rb.signature = SodiumFFI().signEd25519(dataToSign, oldEd25519Sk);
    if (oldMlDsaSk != null) {
      rb.signatureMlDsa = OqsFFI().mlDsaSign(dataToSign, oldMlDsaSk);
    }

    final broadcastBytes = rb.writeToBuffer();

    // ── G-17 CLOSED: THE BROADCAST IS ORDINARY PAIR TRAFFIC ───
    //
    // Until S360 a hard `false` stood here, with the justification that
    // falling back to [sendToUser] was "NOT possible … the receiver cannot
    // check a message signed with the NEW user key against its old
    // anchor". **This justification is V3 thinking and wrong in V4.1**,
    // for two independent reasons, both measured against the document and
    // the code:
    //
    //   1. §15.6 lists the broadcast in the table "Every operation that
    //      must reach a recipient rests on its own key relationship"
    //      explicitly as `tag(K_AB)` — the same row as an ordinary
    //      message, NO infrastructure special path. §13.5 says it once
    //      more: "the entire remaining procedure is
    //      **ordinary traffic** … the Restore Broadcast runs under the
    //      pairwise tag `tag(K_AB)` and needs no KEX-gate exception."
    //
    //   2. `K_AB` does not hang on the user keys that can change at all.
    //      It derives from the FOUNDING keys of both sides (§15.2,
    //      `deriveDeliveryPairKeyFromFounding` in `pair_registry.dart`),
    //      and those are seed-derived and rotation-stable — the comment
    //      there says it literally: "`K_AB` survives every key rotation
    //      without a transition window." In a genuine seed recovery,
    //      moreover, NO identity key changes (§13.5.1: "In a genuine
    //      seed recovery, **no** identity key changes (deterministic
    //      derivation)"), because the PQ keys are deterministic too
    //      (`oqs_ffi.dart:372,548`).
    //
    // §13.5.1 requires exactly one delivery per contact ("**One**
    // delivery per contact under `tag(K_AB, A→C)`"), and one delivery
    // serves all devices of the receiver (§14.2) — that is why there is
    // NO device loop here and there must not be one.
    //
    // ── WHAT THIS BROADCAST DOES NOT CARRY YET, OPENLY NAMED ───────────
    //
    // §13.5.1 lists as content: "`oldUserId = newUserId` …, current
    // pubkeys, **new `inbox_key`**, **fresh prekey batch**, and **pool
    // identifier** (§13.4.4), display name, timestamp, hybrid inner
    // signature (H-2)". Of these, built are: identifiers, current public
    // keys, display name, timestamp and the hybrid signature. NOT built
    // are the three in bold:
    //
    //   * `inbox_key` has no consumer in V4.1. The built delivery lies
    //     under `secureTag(K_AB, …)` per pair (`secure_mode.dart`), not
    //     under a mailbox line; apart from `inboxShardPrefix`
    //     (`lib/core/field/field_tag.dart`, a V4.0 remnant without caller
    //     in `lib/`) the quantity does not exist.
    //   * The prekey pool identifier from §13.4.4 does not exist:
    //     `prekey_pool.dart` keeps no `prekey_pool_epoch`. As long as it is
    //     missing, the **silent prekey break** described there applies —
    //     contacts seal for up to 15 days against lost one-time keys, and
    //     the sender only notices it by the missing receipt.
    //   * Consequently a fresh prekey batch does not travel along either.
    //
    // This stands here and not only in the draft, because a caller who
    // sees `true` would otherwise read "the recovery is delivered".
    // What is delivered is the IDENTITY announcement; the prekey part is
    // missing. See `docs/v4-redesign/S360-recovery-entwurf.md`.
    final recipient =
        oldContacts.where((c) => c.status == 'accepted').toList();
    if (recipient.isEmpty) {
      // §13.2.3/§13.9: no contacts is not an error — it is the bundle
      // case before the bundle. But it is not a success either.
      // CORRECTED (S362): here it said "both are not built (G-3)".
      // For §13.3 that has no longer been true since 02.09.2026 — the
      // rescue bundle is deposited, searched and adopted
      // (`cleona_service_recovery_bundle.dart`,
      // `tagline/recovery_line.dart`). Whoever believes the old sentence
      // looks for a gap that is closed. §13.4 stays open.
      _log.warn('Restore broadcast: no accepted contact known — '
          'nothing to send. The contacts come from the rescue bundle '
          '(§13.3, built — the search runs when a seed exists and '
          'no contact is known) or from the emergency call answer (§13.4, '
          'not built — G-3, step 2).');
      return false;
    }

    var delivered = 0;
    for (final c in recipient) {
      try {
        final ok = await sendToUser(
          recipientUserId: c.nodeId,
          messageType: proto.MessageTypeV3.MTV3_RESTORE_BROADCAST,
          payload: Uint8List.fromList(broadcastBytes),
        );
        if (ok) delivered++;
      } catch (e) {
        // ONE contact must not abort the broadcast: §13.5.1 says that in
        // the bundle case zero contacts suffice and nobody has to be
        // online at the same time. A throw at the third of twenty must
        // not cost the remaining seventeen.
        // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
        _log.debug('Restore broadcast to ${c.displayName}: $e');
      }
    }

    // NO RESUBMISSION TIMER. §13.10.5: "There is **no**
    // restore-specific progress state and no timer retry." The cell
    // lies with the responsible relays until the contact harvests.
    _restoreRetryTimer?.cancel();
    _restoreRetryTimer = null;

    _log.info('Restore broadcast (§13.5.1): $delivered of '
        '${recipient.length} contact(s) accepted, '
        '${broadcastBytes.length} B per delivery, '
        'route tag(K_AB) (§15.6)');
    // `false` means "queued at NO contact" — not "not arrived". Whether a
    // delivery arrives is only said by the receipt (§9, D2); a return
    // value claiming that would be the status-line-as-evidence confusion.
    return delivered > 0;
  }

  // ── Voice Transcription ─────────────────────────────────────────────

  static WhisperModelSize _parseModelSize(String s) {
    switch (s) {
      case 'tiny':  return WhisperModelSize.tiny;
      case 'small': return WhisperModelSize.small;
      default:      return WhisperModelSize.base;
    }
  }

  void _onLocalTranscriptionComplete(String messageId, VoiceTranscription transcription) {
    // Find the message and update its transcript fields.
    for (final conv in conversations.values) {
      ensureAllLoaded();
      final msg = conv.messages.where((m) => m.id == messageId).firstOrNull;
      if (msg != null) {
        msg.transcriptText = transcription.text;
        msg.transcriptLanguage = transcription.language;
        msg.transcriptConfidence = transcription.confidence;
        persistMessage(conv.id, msg);
        onStateChanged?.call();
        _saveConversations();
        // S362: see the justification at the receive path — no wording
        // in the log.
        _log.info('Local transcription complete for $messageId: '
            '${transcription.text.length} chars');
        return;
      }
    }
  }

  // ── Shutdown ───────────────────────────────────────────────────────

  @override
  Future<void> stop() async {
    // First: from here on the chain closures registered at the shared
    // node must no longer trigger work for this identity. The explicit
    // saves further below are direct calls and not affected by the
    // flag.
    _disposed = true;
    // ── AND THE BUNDLE LINE FROM THE SLOT CLOCK (§13.3, S362) ──────────────
    //
    // FOR THE SAME REASON as the line above, and it is not tidying up for
    // tidiness' sake: the slot clock belongs to the SHARED node, the line
    // to this identity. If it stayed attached, a stopped identity would
    // keep depositing its rescue bundle every 14 days — with the key state
    // it had when stopping, and without any caller knowing about it.
    // Exactly the class of leak that until S389 `unbindSecureProbe` closed
    // for the secure probe one line higher — the probe no longer exists,
    // this line does.
    v41RecoveryBundle?.detach();
    _saveConversationsTimer?.cancel();
    _saveConversationsTimer = null;
    if (_saveConversationsPending) {
      _saveConversationsPending = false;
      _saveConversationsNow();
    }
    await _calls.dispose();
    _postDiscoverySecondSweep?.cancel();
    _postDiscoverySecondSweep = null;
    _crRetryTimer?.cancel();
    _crRetryTimer = null;
    _keyRotationTimer?.cancel();
    _keyRotationTimer = null;
    _keyRotationRetryTimer?.cancel();
    _keyRotationRetryTimer = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _restoreRetryTimer?.cancel();
    _restoreRetryTimer = null;
    _restorePollingTimer?.cancel();
    _restorePollingTimer = null;
    _moderation.dispose();
    _polls.dispose();
    _systemChannelEvictionTimer?.cancel();
    _systemChannelEvictionTimer = null;
    _updateCheckTimer?.cancel();
    _updateCheckTimer = null;
    _registryRepublishTimer?.cancel();
    _registryRepublishTimer = null;
    _delegationRenewalTimer?.cancel();
    _delegationRenewalTimer = null;
    // FORMERLY three subsystems were detached here from the SHARED node
    // (`node.rendezvousManager`, `node.transport.httpServer`,
    // `node.binaryRendezvousManager` + `binaryRecordProvider` +
    // `binaryHasContentToShare`) — each only by the identity that had
    // attached it. Without a shared node there is nothing to detach;
    // each of these objects now belongs only to this service and is
    // disposed of regularly below (T).
    // (The general `RendezvousManager` stood here until S362 and has been
    // removed — it was never created, so there was nothing to dispose of
    // either.) The first-contact rendezvous followed in S388.
    // §19.6: tear down the binary-distribution subsystem.
    _binaryHttpServer?.dispose();
    _binaryHttpServer = null;
    _binaryGcTimer?.cancel();
    _binaryGcTimer = null;
    _binaryUpdateManager?.dispose();
    _binaryUpdateManager = null;
    _binaryRendezvousManager?.dispose();
    _binaryRendezvousManager = null;
    _deltaUpdateManager?.dispose();
    _deltaUpdateManager = null;
    _inviteLinkService?.dispose();
    _inviteLinkService = null;
    _physicalTransferHelper?.dispose();
    _physicalTransferHelper = null;
    _binarySeeder = null;
    _binaryFetchClient?.dispose();
    _binaryFetchClient = null;
    _binaryFragmentStore = null;
    // §2.2.4: stop Identity Publisher (Auth/Liveness-Refresh-Loops)
    _saveContacts();
    _saveGroups();
    _saveConversations();
    _saveProcessedMessageIds();
    mailboxStore.dispose();
    await _voiceTranscription?.stop();
    await _archiveManager?.stopScheduler();
    // Do NOT stop the shared node here — the daemon manages its lifecycle
    await CLogger.flushAll();
    _log.info('CleonaService stopped');
  }

  void _saveInNetworkFlag(bool available) {
    try {
      final f = File(
          '${AppPaths.dataDir}${Platform.pathSeparator}update_in_network.flag');
      if (available) {
        f.parent.createSync(recursive: true);
        f.writeAsStringSync('1', flush: true);
      } else if (f.existsSync()) {
        f.deleteSync();
      }
    } catch (_) {}
  }

  /// Get the latest known update manifest (null if never checked or no update).
  UpdateManifest? get latestUpdateManifest => _latestManifest;

  // ── Invitation line (§15.3) ─────────────────────────────────────
  //
  // WHY IT LIVES HERE AND NOT IN THE UI. `K_inv(i)` is computed from the
  // master seed (`InviteLedger.keyFor`), and the index `i` must be
  // MONOTONIC per identity (§15.3.1: "i monotonic per invitation").
  // Both together allow exactly ONE writer: if there were two processes
  // calling `issue()` independently, both would read the same
  // `highwater` and assign the same index — two invitations under ONE
  // key, i.e. the same promise for two different people. The daemon is
  // this one writer.

  InviteStore? _inviteStoreCached;

  /// The encrypted storage of this identity's invitation ledger.
  ///
  /// S366: lives in the area `invites` of the store, no longer in
  /// `invites.json.enc`.
  InviteStore get inviteStore =>
      _inviteStoreCached ??= InviteStore(profileDir: profileDir, store: store);

  InviteLedger? _inviteLedgerCached;

  /// The invitation ledger of this identity.
  ///
  /// **There is deliberately no `?? InviteLedger()` here.** `FileEncryption`
  /// returns `null` for two different situations — "file missing" and
  /// "file there, but not decryptable". A fallback to an empty ledger
  /// would silently turn the second case into the first, and the next
  /// [issueInvitation] would start again at index 0. Exactly that is
  /// forbidden by §15.3.1.
  ///
  /// [InviteStore.load] already separates the two cases: after
  /// `readJsonFile == null` it additionally asks whether `invites.json.enc`
  /// (or the unencrypted form) EXISTS in the file system. If it is missing,
  /// a fresh ledger is right — an identity that has never invited is the
  /// normal case. If it is there, `load()` throws a `StateError`.
  /// This access does NOT catch it; it passes it on to the caller, where
  /// it becomes visible as an error instead of as a quiet reset.
  ///
  /// The access is lazy: an unreadable ledger thus does not paralyse the
  /// start of the service, but exactly the invitation function that needs
  /// it.
  InviteLedger get inviteLedger => _inviteLedgerCached ??= inviteStore.load();

  /// Issues an invitation and writes the ledger BEFORE the key leaves the
  /// house.
  ///
  /// The order is not style but the guarantee: if this method returned the
  /// record and only wrote afterwards, a crash in between would lose the
  /// increased `highwater` — the next issuing would assign the same index
  /// a second time. After writing, the index is used up, even if the
  /// caller never uses the record; a burnt number is cheaper than a
  /// duplicate key.
  ///
  /// Throws [InviteIssueException] when the cap is reached (§15.3.2, ten
  /// invitations open at the same time).
  InviteRecord issueInvitation({
    required InviteClass inviteClass,
    required Duration? validity,
    String label = '',
    bool singleUse = false,
    DateTime? now,
  }) {
    final ledger = inviteLedger;
    final rec = ledger.issue(
      inviteClass: inviteClass,
      validity: validity,
      now: now ?? DateTime.now(),
      label: label,
      singleUse: singleUse,
    );
    // S366: ONE row for the new record plus the header, instead of
    // rewriting the whole — monotonically growing — ledger. The guarantee
    // from the paragraph above stays literally the same: it is written
    // BEFORE the return, so that a crash in between does not lose the
    // increased `highwater`.
    inviteStore.persistRecord(ledger, rec);
    // ── THE NEW LINE MUST BE ARMED IMMEDIATELY ───────────────────────
    //
    // Between issuing and the next restart lies the whole benefit: the
    // issuer shows the QR code NOW, and the scanner deposits its request
    // seconds later. If the line were only armed at the next attach, the
    // request would lie at the responsible relays and expire after three
    // epochs without anyone ever having asked for it.
    armV41InviteLines();
    _log.info('§15.3.1 invitation issued: i=${rec.index} g=${rec.generation} '
        'class=${rec.inviteClass.wireChar} '
        'exp=${rec.expiresAtMs ?? "unlimited"} singleUse=${rec.singleUse}');
    return rec;
  }

  /// §15.3/§15.5 via the interface — see
  /// `ICleonaService.issueInviteForSharing` for the justification.
  ///
  /// Here stands only the combination of the three steps that the UI ran
  /// itself until S380: remember the default, issue, derive the key. They
  /// belong together — an issued invitation without `K_inv(i)` would be a
  /// ledger record without a carrier.
  @override
  Future<InviteIssueResult> issueInviteForSharing({
    required String inviteClassCode,
    Duration? validity,
    bool singleUse = false,
    String label = 'qr-card',
  }) async {
    final cls = InviteClass.fromWireChar(inviteClassCode);
    if (cls == null) {
      _log.warn('§15.3: unknown invitation class "$inviteClassCode" — '
          'not issued');
      return const InviteIssueResult.refused(InviteIssueRefusal.unknownClass);
    }
    try {
      setInviteDefaults(
          inviteClass: cls, validity: validity, unlimited: validity == null);
      final rec = issueInvitation(
        inviteClass: cls,
        validity: validity,
        label: label,
        singleUse: singleUse,
      );
      final ki = inviteKeyFor(rec);
      if (ki == null) {
        // §15.3.1: without a master seed there is no carrier. That is not
        // an error one may gloss over — the caller gets the REASON and
        // omits `ki` instead of sending a placeholder.
        return const InviteIssueResult.refused(
            InviteIssueRefusal.noMasterSeed);
      }
      return InviteIssueResult.issued(IssuedInvite(
        inviteClassCode: rec.inviteClass.wireChar,
        index: rec.index,
        inviteKey: ki,
        expiresAtMs: rec.expiresAtMs,
      ));
    } on InviteIssueException catch (e) {
      _log.warn('§15.3.4 invitation not issued: ${e.reason}');
      return const InviteIssueResult.refused(InviteIssueRefusal.capReached);
    } on StateError catch (e) {
      // §21.4: the ledger is there but cannot be decrypted.
      _log.warn('§21.4 invitation book unreadable: $e');
      return const InviteIssueResult.refused(
          InviteIssueRefusal.ledgerUnreadable);
    }
  }

  /// The open invitations of this identity (§15.3.2).
  ///
  /// ── WHY THIS CALL EXISTS (S381, 11.09.2026) ───────────────────
  ///
  /// The cap from §15.3.2 is ten invitations open at the same time.
  /// When it was reached, the UI used to say "Zehn Einladungen sind
  /// bereits offen. Widerrufe eine, bevor du eine neue erstellst." — and
  /// there was **no way to revoke one**. `InviteLedger.revoke` has always
  /// existed and had zero callers in `lib/`. By the S370 rule, needed dead
  /// code is not dead code but a WIRING ERROR.
  ///
  /// A dead end with a signpost is worse than one without: the user
  /// looks for the button the message promises.
  @override
  Future<List<OpenInvitation>> listOpenInvitations({DateTime? now}) async {
    final InviteLedger book;
    try {
      book = inviteLedger;
    } on StateError catch (e) {
      // §21.4: unreadable is not empty. An empty list would here be the
      // false statement "you have no open invitations".
      _log.warn('§21.4 invitation book unreadable: $e');
      rethrow;
    }
    return book
        .openAt(now ?? DateTime.now())
        .map((r) => OpenInvitation(
              index: r.index,
              inviteClassCode: r.inviteClass.wireChar,
              expiresAtMs: r.expiresAtMs,
              label: r.label,
              singleUse: r.singleUse,
            ))
        .toList(growable: false);
  }

  /// §15.3.3 single revocation of an open invitation.
  ///
  /// The three steps are the same as when redeeming a single-use
  /// invitation ([_consumeSingleUseInvitation]) — and deliberately the
  /// same line for line, so that there are not two ways of
  /// decommissioning an invitation:
  ///
  ///   1. **Ledger** — `revoke` sets the marker.
  ///   2. **Write** — without `persistRecord` the invitation would be
  ///      armed again after the next start.
  ///   3. **Withdraw** — `armV41InviteLines` forgets the pseudo
  ///      counterpart and the standing seal secret; without this call the
  ///      line would keep running until the next tick.
  ///
  /// **What this call does NOT achieve, and that stands here instead of a
  /// claim:** §14.7 lists `INVITE_LIST` as twin-sync type 14 of 17,
  /// "carries the revocation of an invitation, which is therefore not a
  /// purely local act". This propagation is as little wired here as in
  /// the existing [_consumeSingleUseInvitation], which also calls
  /// `revoke` with the default value `multiDevice: false`. The revocation
  /// thus takes effect locally at once and on a second device only after
  /// its next sync. That is an open item, not a silent one.
  @override
  Future<bool> revokeInvitation(int index, {DateTime? now}) async {
    final InviteLedger book;
    try {
      book = inviteLedger;
    } on StateError catch (e) {
      _log.warn('§21.4 invitation book unreadable: $e — i=$index NOT '
          'revoked');
      return false;
    }
    final rec = book.byIndex(index);
    if (rec == null || rec.revoked) return false;
    if (!book.revoke(index, now ?? DateTime.now())) return false;
    inviteStore.persistRecord(book, rec);
    final lines = armV41InviteLines();
    _log.info('§15.3.3 REVOKED: invitation i=$index g=${rec.generation}'
        '${rec.label.isEmpty ? '' : ' "${rec.label}"'} — still $lines '
        'invitation line(s) armed');
    return true;
  }

  // ── V4.2 invitation card (§15.2, §15.3, §15.6) — S387 ───────────────
  //
  // Contract: `mycelium/berichte/S387-API-KARTE.md`. The bodies are in
  // the mycelium part (`cleona_service_mycelium.dart`); without an attached
  // mailbox they report `notConnected` — named, not silently empty.
  //
  // [label] has been built since S390: mycelium keeps it as
  // `Invitation.label`, it goes to disk with the invitation
  // (memory version 10) and comes back in [standingInvitations].
  // It NEVER stands in the card and never goes onto the wire (§15.3).

  @override
  Future<InvitationIssueResult> issueInvitationCard({
    InvitationKind kind = InvitationKind.single,
    InvitationValidity? validity,
    String label = '',
    bool faceToFace = false,
  }) async => _cardIssue(
      kind: kind, validity: validity, label: label, faceToFace: faceToFace);

  @override
  Future<InvitationRedeemResult> redeemInvitationText(String text) =>
      _cardRedeem(readInvitationText(text,
          ownChannel: _ownCardChannel,
          nowUnixSeconds: DateTime.now().millisecondsSinceEpoch ~/ 1000));

  @override
  Future<InvitationRedeemResult> redeemInvitationCardBytes(Uint8List packed) =>
      _cardRedeem(readInvitationBytes(packed,
          ownChannel: _ownCardChannel,
          nowUnixSeconds: DateTime.now().millisecondsSinceEpoch ~/ 1000));

  @override
  Future<StandingInvitationsResult> standingInvitations() async =>
      _cardStanding();

  @override
  Future<InvitationRevokeOutcome> revokeInvitationCard(
          String invitationId) async =>
      _cardRevoke(invitationId);

  @override
  Future<InvitationRevokeAllResult> revokeAllInvitationCards() async =>
      _cardAllRevoke();

  /// `K_inv(i)` for [rec] — 32 B, or `null` if this identity carries no
  /// master seed (old profile without HD derivation).
  ///
  /// `null` here is NOT an error one may gloss over: without a seed there
  /// is no invitation key, and a seed without `ki` is the documented
  /// state "the issuer has said nothing". The caller then omits the
  /// field instead of sending a placeholder.
  Uint8List? inviteKeyFor(InviteRecord rec) {
    final seed = identity.masterSeed;
    final idx = identity.hdIndex;
    if (seed == null || idx == null) {
      _log.warn('§15.3.1: no master seed / hd index for this identity — '
          'invitation $rec gets no K_inv(i); the seed goes out without `ki`');
      return null;
    }
    return inviteLedger.keyFor(seed, idx, rec);
  }

  // ── The user's default (§15.3.1, §15.3.3) ──────────────────
  //
  // NO LITERAL. A class set in code would be "a promise that nobody has
  // given" (contact_seed.dart) — §15.3.1 says the class hangs on the WAY,
  // and only the issuer knows it. That is why the default is `null`
  // until the user has chosen it ONCE; until then seeds go out without
  // `cls`/`exp`/`ki`, i.e. exactly as they went out until today.
  //
  // The deadline is the opposite case: §15.3.3 explicitly names "Default
  // **90 days**", so the UI may PRESELECT 90 days. That too does not stand
  // here as a literal, but comes from `kInviteDefaultValidity` and is only
  // stored with the choice.

  bool _invitePrefsLoaded = false;
  InviteClass? _inviteDefaultClass;
  Duration? _inviteDefaultValidity;
  bool _inviteDefaultUnlimited = false;
  int? _inviteLinkIndex;

  /// Area of the store for the invitation defaults (§21.4.1, S366).
  ///
  /// Four scalars with fixed fields — the same construction as the
  /// settings areas above, i.e. one entry under `_` and `replaceArea`.
  /// The area is deliberately NOT `invites`: the invitation ledger grows
  /// and is written row by row (`InviteStore`), this default is a state.
  /// If both lay in the same area, a `replaceArea` on the default would
  /// wipe out the whole ledger.
  static const String _areaInvitePrefs = 'invite_prefs';

  void _loadInvitePrefs() {
    if (_invitePrefsLoaded) return;
    _invitePrefsLoaded = true;
    try {
      final json =
          store.loadArea(_areaInvitePrefs)[_settingKey];
      if (json == null) return;
      _inviteDefaultClass = InviteClass.fromWireChar(json['cls'] as String?);
      _inviteDefaultUnlimited = json['unlimited'] == true;
      final days = json['validityDays'];
      _inviteDefaultValidity =
          (!_inviteDefaultUnlimited && days is int) ? Duration(days: days) : null;
      final li = json['linkIndex'];
      _inviteLinkIndex = li is int ? li : null;
    } catch (e) {
      _log.warn('invite prefs unreadable: $e');
    }
  }

  void _saveInvitePrefs() {
    try {
      store.replaceArea(_areaInvitePrefs, {
        _settingKey: {
          if (_inviteDefaultClass != null) 'cls': _inviteDefaultClass!.wireChar,
          'unlimited': _inviteDefaultUnlimited,
          if (_inviteDefaultValidity != null)
            'validityDays': _inviteDefaultValidity!.inDays,
          if (_inviteLinkIndex != null) 'linkIndex': _inviteLinkIndex,
        }
      });
    } catch (e) {
      _log.warn('invite prefs not saved: $e');
    }
  }

  /// The stored default class, or `null` — "not chosen yet".
  InviteClass? get inviteDefaultClass {
    _loadInvitePrefs();
    return _inviteDefaultClass;
  }

  /// The stored default deadline. `null` means UNLIMITED if
  /// [inviteDefaultUnlimited] holds, otherwise "not chosen yet".
  Duration? get inviteDefaultValidity {
    _loadInvitePrefs();
    return _inviteDefaultValidity;
  }

  bool get inviteDefaultUnlimited {
    _loadInvitePrefs();
    return _inviteDefaultUnlimited;
  }

  /// The user has chosen. Only from here on is there a default.
  void setInviteDefaults({
    required InviteClass inviteClass,
    required Duration? validity,
    required bool unlimited,
  }) {
    _loadInvitePrefs();
    _inviteDefaultClass = inviteClass;
    _inviteDefaultValidity = unlimited ? null : validity;
    _inviteDefaultUnlimited = unlimited;
    _saveInvitePrefs();
  }

  /// The standing invitation for the app invitation link.
  ///
  /// **Why reused and not newly issued per call.**
  /// [generateInviteLinkUrl] runs every time the share dialog opens. One
  /// issuing per call would have reached the cap from §15.3.2 (ten
  /// invitations open at the same time) after ten dialog calls and then
  /// rejected every further one with `capReached` — the link would have
  /// vanished without the user having done anything. That is why
  /// `invite_prefs.json` holds the index of the standing invitation and
  /// returns it as long as it may still be handed out.
  ///
  /// Returns `null` if the user has not chosen a default yet.
  InviteRecord? standingLinkInvitation({DateTime? now}) {
    _loadInvitePrefs();
    final cls = _inviteDefaultClass;
    if (cls == null) return null;
    final t = now ?? DateTime.now();
    final existing =
        _inviteLinkIndex == null ? null : inviteLedger.byIndex(_inviteLinkIndex!);
    if (existing != null && existing.isOfferableAt(t)) return existing;
    try {
      final rec = issueInvitation(
        inviteClass: cls,
        validity: _inviteDefaultUnlimited ? null : _inviteDefaultValidity,
        label: 'app-invite-link',
        now: t,
      );
      _inviteLinkIndex = rec.index;
      _saveInvitePrefs();
      return rec;
    } on InviteIssueException catch (e) {
      _log.warn('§15.3.2 standing link invitation not issued: ${e.reason}');
      return null;
    }
  }

  @override
  Future<String?> generateInviteLinkUrl() async {
    final manifest = _latestManifest;
    if (manifest == null) return null;
    final hashes = manifest.binaryHashes;
    final sigs = manifest.binarySignatures;
    if (hashes == null || hashes.isEmpty ||
        sigs == null || sigs.isEmpty) {
      return null;
    }

    final pip = publicIp;
    final pport = publicPort;
    if (pip == null || pport == null) return null;

    // The link is an HTTP URL the recipient opens in a BROWSER — that is the
    // whole point of it: they do not have Cleona yet, so a `cleona://`
    // ContactSeed would be useless to them. A browser refuses to open certain
    // ports outright (`ERR_UNSAFE_PORT` / "This address is restricted"), and
    // it refuses LOCALLY, before a single packet leaves their machine. This
    // node would therefore never see a request, never log an error, and go on
    // looking perfectly healthy while none of its invitations can be redeemed.
    //
    // The `f=` fallback download does not rescue that case: it travels in the
    // link's hash fragment, so the browser never gets far enough to read it.
    //
    // Why this check cannot live in `drawDataPort` alone (E-64 stopped there):
    // the link does not carry the drawn port, it carries `publicPort` — either
    // UPnP-mapped by the router or STUN-observed through a translating NAT.
    // Neither is constrained by the draw, and both can be any value in
    // 1–65535, which is why the FULL browser list applies here and not just
    // the one member that falls inside the draw range.
    //
    // Returning null suppresses the invitation block in `ShareCleonaDialog`
    // (`share_cleona_dialog.dart`, `if (inviteUrl != null)`) — the same path
    // already taken when no manifest or no public address is known. A missing
    // invitation beats a dead one: the dead link fails at the recipient, where
    // nobody can diagnose it.
    if (IdentityManager.isBrowserBlockedPort(pport)) {
      _log.warn('invite link suppressed: public port $pport is refused by '
          'browsers (ERR_UNSAFE_PORT) — the link would be dead for every '
          'recipient. Change the node port to restore invitation links.');
      return null;
    }

    // §15.3: the invitation fields come from the user's STORED default,
    // not from a literal. If they never chose, `rec` is null and the seed
    // goes out without `cls`/`exp`/`ki` — the documented state "the
    // issuer has said nothing", not a silently claimed promise.
    final rec = standingLinkInvitation();
    // GAP G-9: the ContactSeed in the invitation link CARRIES the device
    // KEM keys (`dxk`/`dmk`) — the receiver encrypts its first request
    // with them. [deviceX25519Pk] throws because there is no holder.
    //
    // Since the CUT both getters return an EMPTY list, and
    // `ContactSeedBuilder` then omits `dxk`/`dmk` (length check in
    // `contact_seed.dart:220`). The invitation link thus carries the
    // v2 form: `ep` as trust anchor, no device keys. That is irrelevant
    // for first contact. UNTIL S361 THIS SAID "as long as G-1 is open" —
    // G-1 has been closed since S360, and the sentence is still true, just
    // for another reason: the invitation line draws `K_inv` from `ki` and
    // `ep`, not from `dxk`/`dmk`. The device keys in the seed have nothing
    // to do with first contact; what is missing about them belongs under
    // G-9 (no holder).
    final seed = contactSeedBuilder.getContactSeedFor(
      nodeIdHex: identity.userIdHex,
      displayName: identity.displayName,
      channelTag: networkChannel == 'live' ? 'l' : 'b',
      userEd25519Pk: identity.ed25519PublicKey,
      foundingEd25519Pk: identity.foundingEd25519Pk,
      // S388 (v4.2 §4.1): the builder's self-check computes the UserID
      // from Ed25519 AND ML-DSA; the seed does not carry the ML-DSA key,
      // so the issuer passes it in here.
      foundingMlDsaPk: identity.foundingMlDsaPk,
      deviceX25519Pk: deviceX25519Pk,
      deviceMlKemPk: deviceMlKemPk,
      inviteClass: rec?.inviteClass,
      inviteExpiresAtMs: rec?.expiresAtMs,
      inviteKey: rec == null ? null : inviteKeyFor(rec),
    );
    if (seed == null) return null;

    final link = InviteLink(
      nodeIp: pip,
      nodePort: pport,
      contactSeed: seed.toUri(),
      binaryHashes: hashes,
      binarySignatures: sigs,
      version: manifest.version,
      fallbackUrl: manifest.downloadUrl,
      // §19.6.4: maintainer-signed per-platform sizes, so the browser
      // assembler can trim Reed-Solomon padding without a HEAD request
      // against this node's complete-binary endpoint.
      binarySizes: manifest.binarySizes,
    );

    return link.toUrl();
  }

  /// The §19.6 binary seeder for this device, if wired (null on the
  /// non-first identity of a multi-identity daemon, or before startup).
  BinarySeeder? get binarySeeder => _binarySeeder;

  static Future<int> _runSeedIsolate(String binaryPath, String profileDir,
      String platform, String version, int maxFragments,
      {String? expectedHash}) {
    return Isolate.run(() => _selfSeedInIsolate(
      binaryPath: binaryPath,
      profileDir: profileDir,
      platform: platform,
      version: version,
      maxFragments: maxFragments,
      expectedHash: expectedHash,
    ));
  }

  // `void selfPublishManifest() => _selfPublishManifest();` STOOD HERE —
  // REMOVED ON 2026-09-03. A public wrapper around a private method,
  // without any reader. The neighbours in this section are IPC entry
  // points and are called from `ipc_server.dart`
  // (`getSeededPlatforms` e.g. from `ipc_server.dart:4221`) — this one
  // was not.
  //
  // SEARCH SET (2026-09-03, over `lib/ test/ scripts/ proto/ android/ ios/
  // macos/ windows/ linux/`): as a word 1 hit (the declaration itself),
  // as a string `'selfPublishManifest'`/`"..."` 0 — so no IPC command
  // name either —, in `snake_case` (`self_publish_manifest`) 0, in
  // `proto/` 0, as `export ... show` 0.
  //
  // `_selfPublishManifest` LIVES and stays untouched:
  // `cleona_service_pure.dart:957` declares it,
  // `cleona_service_update.dart:615` and the IPC entry `reloadManifest`
  // (further down in this file) call it.

  /// IPC entry: list all seeded platforms and versions.
  Map<String, List<String>> getSeededPlatforms() {
    final store = _binaryFragmentStore;
    if (store == null) return {};
    final result = <String, List<String>>{};
    for (final p in ['android', 'linux', 'windows', 'macos', 'ios']) {
      final versions = store.storedVersionsSync(p);
      if (versions.isNotEmpty) result[p] = versions;
    }
    return result;
  }

  /// IPC entry: reload manifest from disk and re-publish.
  Map<String, dynamic> reloadManifest() {
    try {
      _selfPublishManifest();
      final m = _latestManifest;
      if (m == null) return {'error': 'no valid manifest found on disk'};
      return {'version': m.version};
    } catch (e) {
      return {'error': '$e'};
    }
  }

  /// IPC entry: current update state.
  Map<String, dynamic> getUpdateStatus() {
    final mgr = _binaryUpdateManager;
    if (mgr == null) return {'state': 'unavailable'};
    return {
      'state': mgr.state.name,
      'progress': mgr.progress,
      if (mgr.targetVersion != null) 'targetVersion': mgr.targetVersion,
      if (mgr.errorMessage != null) 'error': mgr.errorMessage,
    };
  }

  // ──────────────────────────── V3 Send/Receive (§2.6 + §5) ────────────────────────────
  //
  // V3.0 layered-frames pipeline entry points.

  // `_isCallSignalingV3(...)` stood here: the distinction of whether a
  // frame is call signalling and may therefore go out UNPACED. Its only
  // reader was `node.sendToDeviceTracked(..., paced:)` in the V3 fan-out
  // of [sendToUser]. V4.1 paces differently (cover stream, §5) and knows
  // no paced switch per frame.


  /// The V4.1 delivery (IP-2). If it is `null`, the switch changes nothing.
  V41Delivery? v41Delivery;

  /// The cold-start gate before the routine rotation (§4.5.4, S363).
  ///
  /// See `cold_start_rotation_gate.dart` — the finding, the order and the
  /// calculated price are there.
  final ColdStartRotationsTor _coldStartRotationsTor = ColdStartRotationsTor();

  /// Only for the guard and the status output: whether a cold-start
  /// rotation is currently waiting for the first harvest run.
  bool get coldStartRotationDeferred => _coldStartRotationsTor.sharp;

  /// A harvest run has taken place.
  ///
  /// Called by the seam `mycelium_seam.dart` (`hostStart`, parameter
  /// `Host.start(onFirstCollection:)`) after the first COMPLETED
  /// collection run with at least one neighbour — to EVERY service
  /// attached to the host. Until S392 the call came solely from
  /// `attachV41` (`V41Node` distributor), and `attachV41` has had no
  /// caller since the replacement: in the meantime the gate always opened
  /// only via the fallback period.
  ///
  /// NO OWN CLOCK: the node reports the collection run that §8.2 runs at
  /// its edges anyway (formerly `V41Node.harvestRuns`, today
  /// `NodePostBox.collect`). Without this call the gate would stay closed
  /// until the fallback period, and the reversal would be built and never
  /// entered.
  void reportHarvestRun() {
    if (_coldStartRotationsTor.harvestRun() == null) return;
    _log.info('First harvest run reported — deferred rotation runs '
        'now (§4.5.4/S363).');
    _performKeyRotation();
  }

  /// The fallback period of the cold-start gate, checked on the existing
  /// 30 s clock. See [ColdStartRotationsTor.fallbackPeriod].
  void _checkRotationsTorDeadline() {
    if (_coldStartRotationsTor.deadlineCheck(DateTime.now()) == null) return;
    _log.warn('Cold-start rotation: in '
        '${_coldStartRotationsTor.fallbackPeriod.inMinutes} min not a '
        'single harvest run — there is no reachable responsible '
        'relay. The rotation runs anyway so that the 7-day cycle from '
        '§4.5.4 does not drop out; the announcement is then, however, '
        'probably not deliverable.');
    _performKeyRotation();
  }

  /// How often this service has sealed against a PROVABLY stale KEM copy
  /// (§4.5.4, S363).
  ///
  /// The counterpart counter on the receiver side is
  /// `MessageOpener.sealedForMeButUnopened`. Both together are the
  /// measure of the error that §4.5.4 itself names as silent ("the
  /// loss is silent"): the one counts who causes it, the other whom it
  /// hits.
  int staleKemSeals = 0;

  /// The bundle line of the rescue bundle (§13.3), set by `attachV41`.
  /// `null` in every process without a V4.1 node.
  RecoveryBundleLine? v41RecoveryBundle;

  /// §22.7 at the service boundary — the readiness state as a string.
  ///
  /// **Without V4.1 delivery `searching`, not `ready`.** That is the
  /// cautious direction and the only defensible one: `readinessState`
  /// means "it can be placed with redundancy". Where the delivery layer
  /// does not run at all (`CLEONA_V41=0`, or a process without a node),
  /// that is demonstrably not the case. The reverse fallback would
  /// silently open every gate that depends on it.
  ///
  /// Deliberately NO recourse to `peerCount` as a substitute quantity:
  /// exactly this stand-in is forbidden by §22.7 ("evidence, not
  /// acquaintance").
  ///
  /// S387: if a mycelium mailbox is attached, the source is the host
  /// (`Host.readiness`, V4.2 §22.7.1 — answering neighbours, live, no
  /// flag). The names are the same that IPC and `waitForReady` carry.
  @override
  String get readinessState =>
      _myceliumReadiness ??
      (v41Delivery?.readinessState ?? Readiness.searching).name;

  /// §25.4 at the service boundary — the partner counts SEPARATED by
  /// direction.
  ///
  /// **Why they must not come from `peerCount`.** The three V3 counters
  /// (`peerCount`, `confirmedPeerCount`, `reachablePeerCount`) count
  /// Kademlia peers of the 3.x line. A sync partner of the V4.1 delivery
  /// layer is something else: an open link session over which cells run.
  /// Putting the one number in place of the other would be exactly the
  /// surrogate that §22.7 and the guard
  /// `smoke_ipc_interface_completeness.dart` rule out.
  ///
  /// Without V4.1 delivery the answer is `0` and not a V3 substitute
  /// value: zero sessions IS the truth of this layer when it is not
  /// running.
  @override
  int get syncPartnersOutbound => v41Delivery?.syncPartnersOutbound ?? 0;

  @override
  int get syncPartnersInbound => v41Delivery?.syncPartnersInbound ?? 0;

  @override
  int get independentSyncPartners => v41Delivery?.independentSyncPartners ?? 0;

  /// §9.2 — the MEASURED responsibility set from which the consent dialog
  /// computes its time span.
  ///
  /// `0` means "delivery layer not attached or no relay known". Both are
  /// the same state for the display: there is nothing to deposit, so
  /// there is nothing to estimate.
  @override
  int get reachableResponsibleRelays =>
      v41Delivery?.reachableResponsibleRelays ?? 0;

  // ── DATA SAVER MODE (§24.4.2, §23.1 point 5, §23.7 RL-8, §31.3 Tier 4) ─
  //
  // The state itself lives in `CoverSaver.instance` (lib/core/sync/
  // cover_stream.dart), because the slot clock is decided there and a
  // latch only holds at the place of the action. Here stands only what
  // the service contributes: the PROBE that says whether this identity
  // is currently running a secure chat.

  // NO SECURE PROBE ANY MORE (S389). Here stood `hasSecureChat` and
  // `_ensureCoverSaverProbe`: the probe with which the data saver mode
  // was locked as long as any chat of this identity was set to
  // high-secure. It read `Contact.secureMode`/`Group.secureMode`,
  // and those no longer exist (§12.1 — no switch, no setting
  // per chat).
  //
  // CONSEQUENCE, named instead of concealed: `CoverSaver.lockedBySecure`
  // answers `false` without a registered probe (cover_stream.dart: the
  // loop over an empty set falls through), so the latch never takes hold
  // any more. That is the direction §3.1 leads — "The cover
  // stream … can be switched off without affecting delivery": a latch
  // that prevents switching off the cover presupposes that a delivery
  // hangs on it. The chain below (`lockedBySecure`,
  // `dataSaverLockedBySecure`, `kDataSaverLockedBySecure` and four
  // display places) is thus unreachable and belongs in its own
  // package — finding B-M3 in `mycelium/berichte/S389-BAU-MODUS.md`.

  /// §24.4.2 — whether the saver mode TAKES EFFECT.
  @override
  bool get dataSaverActive {
    return CoverSaver.instance.active;
  }

  /// §24.4.2 — whether the switch is locked because secure is running.
  @override
  bool get dataSaverLockedBySecure {
    return CoverSaver.instance.lockedBySecure;
  }

  /// §24.4.2 — the setter. Only the user calls it.
  ///
  /// Returns [kDataSaverLockedBySecure] if the latch takes hold; the wish
  /// is then NOT remembered (a remembered wish that later strikes by
  /// itself would be the automatic activation that §24.4.2 forbids).
  @override
  String setDataSaver(bool on) {
    final result = CoverSaver.instance.request(on);
    onStateChanged?.call();
    return switch (result) {
      CoverSaverOutcome.refusedSecureActive => kDataSaverLockedBySecure,
      _ => kDataSaverOk,
    };
  }

  // ── SOURCE 4: EXTERNAL ADDRESS ENTRIES (V4.2 §11.9, S388) ────────────
  //
  // A device value: the switch lives in the memory of the ONE host
  // (`wirt.enc`), not per identity — every service of the process reads
  // the same one. Without an attached mailbox there is no host: then the
  // host's default (on) applies, and the setter reports `false` instead
  // of silently doing nothing.

  @override
  bool get externalRecordsEnabled =>
      myceliumMailbox?.host.outsideSourceOn ?? true;

  @override
  bool setExternalRecordsEnabled(bool on) {
    final p = myceliumMailbox;
    if (p == null) return false;
    p.host.outsideSourceOn = on;
    _log.info('Source 4 (external address entries) ${on ? 'an' : 'aus'} — '
        'by the user (§11.9)');
    onStateChanged?.call();
    return true;
  }

  // ── COVER IN THE OWN NETWORK (S373, §5.1 exception) ───────────────────
  //
  // The state is split in two and that is intended: the CONSENT in the
  // node (`V41Node.lanConsent`, because only it knows where its partners
  // sit), the EFFECT in `CoverSaver` (because the slot clock is decided
  // there). Here stands the bridge to the UI and the storage.

  static const String _areaLanConsent = 'lan_consent';
  static const String _keyLanConsent = 'segments';
  bool _lanConsentLoaded = false;

  /// Loads the consents into the node — once, as soon as there is a
  /// node.
  ///
  /// LAZY AND NOT IN THE CONSTRUCTOR: `v41Delivery` is filled in later by
  /// `attachV41` and is `null` when the service is created. A load attempt
  /// there would run into nothing, and the consent would be gone after
  /// every restart — without it being noticed, because the result (full
  /// cover) looks like the normal case.
  void _ensureLanConsentLoaded() {
    if (_lanConsentLoaded) return;
    final n = v41Delivery;
    if (n == null) return;
    _lanConsentLoaded = true;
    try {
      n.lanConsentLoadJson(
          store.loadArea(_areaLanConsent)[_keyLanConsent]);
    } catch (e) {
      // An unreadable consent is NO consent. Do not guess, do not
      // repair — the user is asked again, and that is the only
      // defensible direction.
      _log.warn('lan consent unreadable: $e');
    }
    n.onLanConsentChanged = () {
      try {
        store.replaceArea(
            _areaLanConsent, {_keyLanConsent: n.lanConsentToJson()});
      } catch (e) {
        _log.warn('lan consent not saved: $e');
      }
    };
  }

  @override
  bool get lanShapingActive {
    _ensureLanConsentLoaded();
    return CoverSaver.instance.lanShapingActive;
  }

  @override
  List<String> get lanSegmentIds {
    _ensureLanConsentLoaded();
    return v41Delivery?.lanSegmentIds ?? const <String>[];
  }

  @override
  List<String> get lanSegmentsGrantable {
    _ensureLanConsentLoaded();
    return v41Delivery?.lanSegmentsGrantable ?? const <String>[];
  }

  @override
  bool lanSegmentConsented(String segmentId) {
    _ensureLanConsentLoaded();
    return v41Delivery?.lanSegmentConsented(segmentId) ?? false;
  }

  @override
  bool grantLanShaping(String segmentId) {
    _ensureLanConsentLoaded();
    final ok = v41Delivery?.grantLanShaping(segmentId) ?? false;
    if (ok) onStateChanged?.call();
    return ok;
  }

  @override
  bool revokeLanShaping(String segmentId) {
    _ensureLanConsentLoaded();
    final ok = v41Delivery?.revokeLanShaping(segmentId) ?? false;
    if (ok) onStateChanged?.call();
    return ok;
  }

  /// The V4.1 host (§4.6) — the sealing TOGETHER with the prekey pool.
  ///
  /// FORMERLY ONLY THE SEALING STOOD HERE (`MessageSealer? v41Sealer`),
  /// and the body called `seal()` directly. That skipped `advance()`, i.e.
  /// exactly the step that DRAWS the one-time prekey — §4.6: "The sender
  /// seals every cell against exactly one unused prekey." Without it
  /// `_current[peer]` stayed empty, `x25519PublicFor` threw `StateError`,
  /// and because the send path hangs on an unhandled async error, the
  /// error took the whole daemon with it. Measured on 25.08. on node 2:
  /// the first arriving contact request wanted to send back a
  /// DELIVERY_RECEIPT and killed the process.
  ///
  /// Second, silent damage from the same shortcut: `seal()` alone omitted
  /// the frame kind that `V41Host.accept()` reads on the other side —
  /// a frame sealed like that could not have been assigned there.
  ///
  /// That is why the service now holds the HOST and calls `sendFrame()`.
  /// The order draw-seal-send thus lives in ONE place, not in two that
  /// can drift apart.
  V41Host? v41Host;

  /// The mycelium mailbox of this identity (V4.2, S387) — set by
  /// `myceliumAttach` (`cleona_service_mycelium.dart`) as soon as the
  /// host of the process is up. If it is set, it carries `sendToUser`.
  mycelium.Mailbox? myceliumMailbox;

  /// app `messageId` (hex) -> mycelium outbound: the source of the display
  /// status for messages sent via mycelium. Capped, see
  /// `_kMyceliumOutboundsMax`.
  final Map<String, mycelium.Outbound> _myceliumOutbounds = {};

  /// Identifiers for which a proven delivery receipt of the application came.
  final Set<String> _myceliumAcknowledged = {};

  /// The bulk lane of this identity (§9.3).
  ///
  /// NOT NULLABLE: it costs nothing as long as no transfer runs (two
  /// empty maps), and a nullable field would have forced a branch at every
  /// read site that is never checked. What CAN be missing is its
  /// transport — and that is a separate field.
  final MediaBulkLane mediaBulkLane = MediaBulkLane();

  /// The seam of the media bulk lane to the network (§9.3).
  ///
  /// **Set since 02.09.2026** — `attachV41` attaches a
  /// `V41MediaBulkTransport` here (`media_bulk_transport_v41.dart`) and at
  /// the same time its back side to `DeliveryNode.onBulkScanned`. Before,
  /// the field was `null` because the HOLDER SIDE was missing: no wire
  /// format for a bulk deposit, no constructor for `BulkCache`, and
  /// frame type `0x05` was discarded on assignment.
  ///
  /// `null` REMAINS ADMISSIBLE and still means the same: no V4.1 node at
  /// this identity (tests, `CLEONA_V41=0`). Then a large media send is
  /// REJECTED instead of silently going via V3.
  MediaBulkTransport? mediaBulkTransport;

  /// The delivery status of the messages sent via V4.1 (§9.2, D2).
  ///
  /// NOT NULLABLE and without a switch: the register costs nothing as long
  /// as nothing is put into it, and it is filled exclusively by the
  /// V4.1 send path. A `null` would have forced a second branch at every
  /// read side — and a branch that only the absence of the register
  /// enters is exactly the place where the rule from §9.2 would get lost
  /// again.
  ///
  /// The read sides live in `cleona_service_msgstate.dart` and
  /// `cleona_service_receive.dart`; it also says there why they ASK the
  /// register and do not judge themselves.
  final V41DeliveryRegister v41Deliveries = V41DeliveryRegister();

  /// The LOCAL OUTBOX (§21.2) — the ledger of own, not yet substantiated
  /// messages. **Gap G-4, closed in S360.**
  ///
  /// ── WHAT DISTINGUISHES IT FROM THE REGISTER NEXT TO IT ────────────────────
  ///
  /// [v41Deliveries] keeps the STATE of a delivery (how many independent
  /// relays, which attempt, which piece). It lives only in memory, and
  /// that is right: a proof from an attempt whose cells no longer exist
  /// after a restart would be worthless.
  ///
  /// The outbox, by contrast, keeps what MUST SURVIVE a restart: the
  /// plaintext frame from which a resubmission can seal FRESHLY
  /// (§22.5.1 refinement 3). §21.8 lists it explicitly as an item on
  /// disk — "Own, not-yet-placed cells (outbox) | own messages including
  /// recipient | **under the DB key**".
  ///
  /// Without it every message sent via V4.1 stood permanently on
  /// `placing` after a restart: the display value is written to
  /// `conversations.json` and read back unchanged by
  /// `MessageStatus.fromWire`, but neither the register nor the control
  /// queue survive the process. `service_types.dart` describes exactly
  /// this state as inadmissible: "Behind a record loaded from disk there
  /// is no outbox line and therefore nothing that would ever move it on;
  /// it would stand on a promise that cannot come true."
  ///
  /// NOT the V3 `_outbox` next to it: that carries serialised
  /// `NetworkPacketV3` bytes and since the CUT is only read and written
  /// so that an old profile is not silently overwritten.
  final V41Outbox v41Outbox = V41Outbox();

  /// From the WIRE identifier of a leg to the message it displays.
  ///
  /// ── WHY THIS INDEX EXISTS (S376, P5 finding 2) ────────────────
  ///
  /// A placement receipt (`PlacementAck`) only knows the identifier of
  /// the leg. The DISPLAY hangs on a `UiMessage` in a conversation, and
  /// with a group fan-out the display identifier is NOT the wire
  /// identifier (every leg has its own, `UiMessage.fanoutLegs`). Without
  /// a mapping only the full pass over all conversations and all messages
  /// would remain — that is how `_applyFanoutReceipt` does it for the
  /// delivery receipt, and there one receipt comes per MESSAGE. Here up
  /// to `m x R` = 60 receipts come per message (§9.2); the same pass
  /// would be 60 times as expensive.
  ///
  /// ONLY IN MEMORY, and that is not a backlog but the counterpart of
  /// [v41Deliveries]: the register does not survive the process either,
  /// a receipt for a message from before the restart finds no record
  /// there anyway and returns at once. An index that lived longer than
  /// the register would be a reference to a question nobody asks any more.
  ///
  /// CAPPED like the register: [_v41LegIndexMax]. If it overflows, the
  /// oldest entry is discarded (insertion order — `Map` in Dart keeps
  /// it). The loss costs the display of an update, not a delivery.
  final Map<String, ({String convId, String msgId})> _v41LegIndex = {};

  /// How many legs the index keeps at most.
  ///
  /// THE SAME ORDER OF MAGNITUDE AS THE REGISTER it is fed from: an entry
  /// without a record in the register can no longer have any effect. The
  /// number is deliberately generous — an entry is two short strings.
  static const int _v41LegIndexMax = 4096;

  /// How many frames a secure resubmission costs — `m x R` (§9.2).
  ///
  /// It stands here as a calculation from two constants and not as a
  /// number, so that it grows along when [kResponsibleRelays] changes. The
  /// egress cap of the drain hangs on it; a frozen 60 would be the kind of
  /// silent deviation at which `kMaxControlBacklog` could once already
  /// have broken.
  static const int _v41SecureFramesPerOffer =
      kDeliveryFamilies * kResponsibleRelays;

  static const int _kV41FrameOverhead = 160;

  // `_receiptReturnsOverV41` stood here: the question whether the
  // delivery confirmation travels back in the cover stream instead of on
  // the same path as the message. It answered EXCLUSIVELY the deadline
  // calculation of the `AckTracker` (`returnLegOverCoverStream`) — and in
  // V4.1 there is no deadline on the delivery path any more. The
  // statement itself has become trivially true: there IS only the one way.


  /// A detached send attempt — the result does not matter, but the
  /// ERROR must not escape into the zone.
  ///
  /// ── WHY THIS FUNCTION MUST EXIST ──────────────────────────────
  ///
  /// `sendToUser` has TWO error channels: it returns `false` (no
  /// recipient key, too large, nothing placeable) AND it can throw.
  /// 22 call sites throw away the `Future` because they only send on the
  /// side. They STRUCTURALLY cannot see the second channel:
  ///
  ///   * An `async` function NEVER throws synchronously. Even a throw in
  ///     the first line of its body lands in the returned `Future`.
  ///     A `try { sendToUser(…); } catch (e) { … }` around the call
  ///     therefore catches NOTHING — measured in
  ///     `test/smoke/smoke_self_send_v41_guard.dart`: "call site: try/catch
  ///     hat NICHTS gefangen". `_sendTwinSync` had exactly this
  ///     `try/catch` and thus considered itself safeguarded.
  ///   * A `Future` with an unobserved error goes into the zone handler of
  ///     `service_daemon.dart` (~L424). Its survival list knows
  ///     `TimeoutException`, `SocketException`, `IOException` and one
  ///     named `StateError` — everything else is `exit(99)`.
  ///
  /// So EVERY unexpected exception in `sendToUser` kills the whole
  /// daemon: all identities, all chats, all calls — because ONE side
  /// send could not form a key. The proportion is not right.
  ///
  /// WHAT THIS FUNCTION DOES NOT DO: it does not turn the error into
  /// "successful". It logs at `error` WITH stack — the same level at which
  /// the zone handler would have written. A defect stays visible, it just
  /// no longer takes the daemon with it.
  ///
  /// WHY NO CATCH-ALL `catch` IN THE BODY of `sendToUser`: there it would
  /// also hit the AWAITING callers and sell them a real defect as a plain
  /// `false` — "crashed" would become "silently not sent". The latch
  /// belongs at the place where the result is actually thrown away.
  void _detachedSend(String what, Future<bool> dispatch) {
    dispatch.catchError((Object e, StackTrace s) {
      _log.error('detached send „$what" threw and would have killed '
          'the daemon: $e\n$s');
      return false;
    });
  }

  static String _hexOf(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  /// The identifier of a PAIR for the delivery layer (B-31, S349).
  ///
  /// ── WHY THE OWN IDENTITY MUST BE INCLUDED ─────────────────────
  ///
  /// `K_AB` is pairwise: it hangs on BOTH founding keys (§15.2). The
  /// `PairRegistry`, by contrast, sits in the `V41Node`, and that is
  /// **node-wide** — `L_node` belongs to the node, not to the identity.
  /// Whoever keys there only by the recipient UserID lets two identities
  /// of the same node overwrite the same entry.
  ///
  /// Measured in the field on 28.08.: on a node with the identities
  /// "Bob" and "Charly", which BOTH keep the same contact, the log showed
  /// two different keys for the same counterpart —
  ///
  ///     "Ernte fuer 2708863c: K_AB 1dc44f54, Richtung 1"
  ///     "Ernte fuer 2708863c: K_AB 93b5535e, Richtung 0"
  ///
  /// — and depending on who last called `rememberPeer`, the node
  /// harvested under the wrong mark **and in the wrong direction**.
  /// The other side deposited correctly; nothing was found nonetheless.
  ///
  /// `v41_attach.dart` already describes exactly this trap — for the
  /// prekey pool, which is therefore kept per identity ("`peer` … does not
  /// carry the sender identity"). For the pair registry it was not
  /// applied.
  String _v41PeerKey(Uint8List recipientUserId) =>
      '${identity.userIdHex}/${_hexOf(recipientUserId)}';

  /// The V4.1 application frame — ONE construction for both outputs.
  ///
  /// ── WHY THIS IS A SEPARATE METHOD (S363) ──────────────────────
  ///
  /// It is needed in two places: in the host branch of [sendToUser],
  /// which hands it out sealed, and in the no-host branch at the end of
  /// the same method, which puts it into the outbound compartment. Two
  /// constructions would be two opportunities to forget a field — and
  /// the resubmission would then seal something other than the first attempt.
  proto.ApplicationFrameV3 _v41InnerFrame({
    required Uint8List recipientUserId,
    required Uint8List senderUserId,
    required Uint8List messageId,
    required proto.MessageTypeV3 messageType,
    required Uint8List payload,
    Uint8List? groupId,
    proto.ContentMetadata? contentMetadata,
    proto.EditMetadata? editMetadata,
    proto.ExpiryMetadata? expiryMetadata,
    int? groupMembershipEpoch,
    Uint8List? groupMembershipHash,
  }) {
    final inner = proto.ApplicationFrameV3()
      ..recipientUserId = recipientUserId
      ..senderUserId = senderUserId
      ..timestampMs = Int64(DateTime.now().millisecondsSinceEpoch)
      ..messageId = messageId
      ..messageType = messageType
      ..payload = payload;
    if (groupId != null && groupId.isNotEmpty) inner.groupId = groupId;
    if (contentMetadata != null) inner.contentMetadata = contentMetadata;
    if (editMetadata != null) inner.editMetadata = editMetadata;
    if (expiryMetadata != null) inner.expiryMetadata = expiryMetadata;
    if (groupMembershipEpoch != null && groupMembershipEpoch > 0) {
      inner.groupMembershipEpoch = Int64(groupMembershipEpoch);
    }
    if (groupMembershipHash != null) {
      inner.groupMembershipHash = groupMembershipHash;
    }
    return inner;
  }

  /// Message kinds whose loss is without consequence — they are NOT
  /// parked (§21.2).
  ///
  /// A typing indicator that is resubmitted an hour later claims that
  /// someone is typing right now; it would then not be late, but wrong.
  /// Until S363 it stood as `const vergaenglich` INSIDE the host branch
  /// and was thus invisible to the no-host branch.
  static const kV41Ephemeral = <proto.MessageTypeV3>{
    proto.MessageTypeV3.MTV3_TYPING_INDICATOR,
  };

  @override
  Future<bool> sendToUser({
    required Uint8List recipientUserId,
    required proto.MessageTypeV3 messageType,
    required Uint8List payload,
    Uint8List? groupId,
    Uint8List? messageId,
    proto.ContentMetadata? contentMetadata,
    proto.EditMetadata? editMetadata,
    proto.ExpiryMetadata? expiryMetadata,
    proto.ErasureCodingMetadata? erasureMetadata,
    List<bool>? l3Result,
    int? groupMembershipEpoch,
    Uint8List? groupMembershipHash,
    Uint8List? targetDeviceId,
    bool skipL3 = false,
    // The 31-day retention class (§21.1). Justification and delimitation
    // are at the seam (`service_context.dart`) and at the setting site
    // (`V41Node.placeSecure`).
    bool management = false,
    List<SendLeg>? outLegs,
    Uint8List? recipientX25519PkOverride,
    Uint8List? recipientMlKemPkOverride,
    Uint8List? recipientEd25519PkOverride,
    // NO `speedForThisFrame` ANY MORE (S389). The parameter carried the
    // one-time downgrade to speed from the consent dialog. There is no
    // second send path any more to downgrade to (§3.3, §12.1), and the
    // dialog that produced it has lost its trigger.
  }) async {
    // 1. Sender identity: this CleonaService is bound to a single
    //    IdentityContext (see ipc_server `_resolveService` per-request
    //    routing). Cross-identity sends therefore go through the matching
    //    service instance.
    //
    //    S368: here stood an override parameter `Uint8List? senderUserId`
    //    ("The legacy override parameter is kept for callers that still pass
    //    it explicitly"). MEASURED with a bracket-balancing counter over
    //    `lib/`, `bin/` and `test/`: **zero** `sendToUser(...)` calls pass
    //    it — the 20 `senderUserId:` hits in the tree belong to
    //    `HarvestEvent`, `_v41InnerFrame` and `SenderIdentitySnapshot`, not
    //    here. The callers it was kept for no longer existed, and with it
    //    falls the `assert` line that was meant to catch an error at a
    //    call site that does not exist.
    final effectiveSenderUserId = identity.userId;

    // 2. Resolve KEM-pubkeys for the recipient user.
    //    The Inner ApplicationFrame is KEM-encrypted under the recipient User
    //    keypair (X25519 + ML-KEM-768). For foreign recipients both keys live
    //    on the contact record; callers that haven't completed the CR exchange
    //    cannot reach this user yet — drop with a warn log.
    //
    //    §7.2 SELF-PATH: Twin-Sync, TWIN_ANNOUNCE and Device-Pairing address
    //    the *own* userId ("Twin-Sync routing: via sendToUser(envelope,
    //    ownUserId)"). The own identity is by construction never present in
    //    `_contacts` — every insert site fills foreign user-ids and the
    //    PeerList import skips self explicitly — so the contact lookup would
    //    reject every self-send with `no KEM pubkeys`. Take the recipient KEM
    //    material from the own IdentityContext instead: the User-KEM keypair
    //    is shared by all devices of a user (§7.1.1 — Linked Devices receive
    //    the User-KEM-SK), so a frame encrypted under it decapsulates on
    //    every twin. `ed25519PublicKey` is the User key on Linked Devices too
    //    (delegated Sig-subkeys live behind `signingEd25519Pk`), hence it is
    //    also the correct mailbox anchor for the §5.4/§5.3 L3 fallback:
    //    the own mailbox is SHA-256("mailbox" + identity.ed25519PublicKey).
    final recipientHex = bytesToHex(recipientUserId);
    final isSelfSend = constantTimeEquals(recipientUserId, identity.userId);
    final ContactInfo? contact = isSelfSend ? null : _contacts[recipientHex];
    // `recipientEd25519Pk` went away with the V3 path: it was the anchor
    // of the mailbox identifier for the layer-3 deposit
    // (SHA-256("mailbox" + ed25519Pk)). V4.1 deposits by the tagline,
    // not by a mailbox identifier.
    final Uint8List recipientX25519Pk;
    final Uint8List recipientMlKemPk;
    if (isSelfSend) {
      recipientX25519Pk = identity.x25519PublicKey;
      recipientMlKemPk = identity.mlKemPublicKey;
    } else {
      if (recipientX25519PkOverride != null && recipientMlKemPkOverride != null) {
        // Caller-supplied keys (e.g. from _resolveMemberKeys for non-contact
        // group/channel members whose KEM keys arrived via GROUP_INVITE).
        recipientX25519Pk = recipientX25519PkOverride;
        recipientMlKemPk = recipientMlKemPkOverride;
      } else if (contact != null && contact.x25519Pk != null && contact.mlKemPk != null) {
        recipientX25519Pk = contact.x25519Pk!;
        recipientMlKemPk = contact.mlKemPk!;
        // ── THE FRESHNESS CHECK (§4.5.4, S363) ────────────────────────
        //
        // Until S363 ONLY the null check above stood here. So this place
        // sealed against a generation of which it did not know whether the
        // counterpart still holds it — and §4.5.4 keeps exactly ONE
        // previous one ("Exactly **one** previous generation is
        // retained"). Two rotation intervals old is provably too old.
        //
        // ── WHY IT IS SENT ANYWAY ──────────────────────────────
        //
        // Not sending would be a second silent loss and wrong on top: the
        // copy CAN still be valid (a counterpart that was off longer has
        // not rotated — `needsRotation` only runs while the process runs).
        // §14.5 names the visibility principle for exactly this situation.
        // What was missing was not the lock but the INFORMATION: the
        // failure was mute on both sides (§4.5.4: "the loss is silent —
        // the receiver counts `unopened` and reports nothing"). Hence log
        // and counter, no lock.
        //
        // NO USER CONTENT: eight hex digits of the UserID, an age in
        // days. No display name, no text.
        final fresh = kemCopyFreshness(
          seenAt: contact.kemSeenAt,
          now: DateTime.now(),
        );
        if (isProvablyUnusable(fresh)) {
          staleKemSeals++;
          final days = DateTime.now().difference(contact.kemSeenAt!).inDays;
          _log.warn('sendToUser: ${messageType.name} to '
              '${_hexShort(recipientUserId)} is sealed against a $days days '
              'old KEM copy. §4.5.4 keeps exactly ONE previous '
              'generation (rotation interval '
              '${kKemRotationInterval.inDays} d) — the counterpart can '
              'provably no longer open this cell if it '
              'rotated as scheduled. It is sent anyway '
              '(visibility principle §14.5); from here on the loss is '
              'no longer silent. Counter: $staleKemSeals');
        }
      } else {
        _log.warn('sendToUser: no KEM pubkeys for ${recipientHex.length >= 8 ? recipientHex.substring(0, 8) : recipientHex} '
            '(contact=${contact != null}, x25519=${contact?.x25519Pk != null}, mlKem=${contact?.mlKemPk != null})');
        return false;
      }
    }

    // ── V4.2: THE BODY LIES ON THE MAILBOX (S387) ────────────────
    //
    // If a mycelium mailbox is attached, IT carries the message — the
    // switch below (V4.1) is no longer entered. Without a mailbox
    // everything stays as it was: the no-carrier branch at the end parks,
    // and `myceliumAnschliessen` hands over what is parked on attach.
    if (myceliumMailbox != null) {
      if (l3Result != null && l3Result.isNotEmpty) l3Result[0] = false;
      return _myceliumSendToUser(
        recipientUserId: recipientUserId,
        isSelfSend: isSelfSend,
        contact: contact,
        messageType: messageType,
        payload: payload,
        groupId: groupId,
        messageId: messageId,
        contentMetadata: contentMetadata,
        editMetadata: editMetadata,
        expiryMetadata: expiryMetadata,
        groupMembershipEpoch: groupMembershipEpoch,
        groupMembershipHash: groupMembershipHash,
      );
    }

    // ── 2b. THE SWITCH (IP-3) ─────────────────────────────────────────
    //
    // It is ONLY active if a V4.1 delivery has been attached. Without it
    // everything falls through unchanged — that is the point: the seam is
    // laid before it is switched over.
    //
    // NO FALLBACK. If the V4.1 layer rejects a small message, it does NOT
    // go via V3 as a substitute. A fallback would be exactly the dual
    // stack that §7 rules out — and it would be invisible, because both
    // "work".
    // ── SELF-SEND DOES NOT BELONG ON THIS PATH ────────────────
    //
    // §14.2 is unambiguous here: "One delivery serves all devices. The
    // delivery path has **no device level**: no resolver, no iteration
    // over devices, no per-device delivery states." A twin fan-out over
    // the delivery layer would be exactly this iteration over devices
    // — just built in one level deeper.
    //
    // Nor is it merely "not wired yet"; with today's mechanism it is
    // NOT BUILDABLE, for two independent reasons:
    //
    //   1. `K_AB` is pairwise and comes from the FOUNDING KEYS of BOTH
    //      sides (§15.2). For self-send there is no second side:
    //      `contact` is `null` by construction (the own identity never
    //      stands in `_contacts`, see step 2), and `v41PairKeyFor` then
    //      throws — rightly — `StateError('K_AB nicht bildbar')`, because
    //      a silent substitute key would let both sides talk under
    //      different marks.
    //
    //   2. Even with a key the DIRECTION would not hold.
    //      `outboundDirection` compares two FOUNDING KEYS (S353); with
    //      self-send it is the same one twice, the loop runs through and
    //      yields 0 — on BOTH twins. Both therefore deposit under
    //      direction 0 and harvest per `inDirectionFor` (`1 - 0 = 1`)
    //      under direction 1. No twin would ever find the other's
    //      deposit. That is B-22 in pure form, except that the
    //      lexicographic order CANNOT order a self-relation at all.
    //
    // The V4.1-conformant path for own devices is a different one and is
    // in §14.1: `sendToDevice()` seals under the DEVICE mark
    // `HKDF(K_own, "device" ‖ deviceId ‖ n)` — an OWN mark from `K_own`,
    // not a pair mark from `K_AB`. Since S361 it lives in
    // `lib/core/tagline/device_line.dart`; the sentence "this path has yet
    // to be created" stood here until then and is corrected.
    //
    // NO CONTRADICTION TO "NO FALLBACK". The sentence below forbids sending
    // a message REJECTED by V4.1 via V3 as a substitute. Here nobody
    // rejects: self-send is not a V4.1 delivery class at all — the same
    // category as `kBootstrapTypes` and `kBulkTypes` in `routeFor`, only
    // recognisable by the identifier instead of by the type. It is a
    // route classification, not a fallback.
    //
    // WHAT HAPPENED WITHOUT THIS LINE (measured, see
    // `test/smoke/smoke_self_send_v41_guard.dart`): `_sendTwinSync`
    // runs on EVERY sent message (`MESSAGE_SENT`) and calls
    // `sendToUser(recipientUserId: identity.nodeId, …)`. The throw from
    // `v41PairKeyFor` escaped as an unhandled future error into the zone
    // of `service_daemon.dart` (~L424), and `StateError` is not in its
    // survival allowlist: `exit(99)`. On Android/iOS the same error as a
    // visible crash dialog. It stayed invisible only because
    // `_sendTwinSync` exits earlier at `_devices.length <= 1` — all test
    // identities have one device. From the SECOND device per identity on,
    // the daemon dies on every message.
    final v41 = v41Delivery;
    final v41HostRef = v41Host;
    // ── `!isSelfSend` IS GONE HERE (S360, gap G-14 closed) ────
    //
    // The long comment above describes the state up to here and stays as
    // a correction — it was right on the substance: with `K_AB` and the
    // lexicographic direction a self-send cannot be built. §14.7 does not
    // solve this with a better direction, but with an OWN line under
    // `K_own`, onto which all twins deposit and from which all harvest.
    // It lives in `own_line.dart`; it is registered by `attachV41` via
    // [v41ArmOwnLine].
    if (v41 != null && v41HostRef != null) {
      // The whole FRAME counts, not the payload: MEDIA_ANNOUNCE has an
      // empty payload and carries a preview image of up to 100 KB in
      // contentMetadata.
      final frameBytes = payload.length +
          (contentMetadata?.writeToBuffer().length ?? 0) +
          (editMetadata?.writeToBuffer().length ?? 0) +
          (expiryMetadata?.writeToBuffer().length ?? 0) +
          _kV41FrameOverhead;
      final route = routeFor(
        type: messageType,
        // The full overhead that the delivery layer adds: kind byte
        // (`V41Kind.wrap`), sender MAC, seal including the day capsule.
        // The capsule is the big item and only occurs on the FIRST message
        // of a day — here it is nevertheless always counted: a limit that
        // depended on the time of day would behave one way one time and
        // another way the next.
        //
        // S368: here stood `V41Kind.signatureBytes`. The name had been wrong
        // since S352 — there is no signature any more (§4.4.3) —, the
        // number was right because the constant pointed to `senderMacBytes`.
        // Now the right name stands here; the number is unchanged.
        frameBytes: frameBytes +
            1 +
            V41Kind.senderMacBytes +
            MessageSealer.firstOfDayOverheadBytes,
        // NO LONGER the cell limit — the delivery layer now splits
        // (§15.4 "~11-14 cells", `frame_split.dart`). What breaks here
        // really belongs on the two-stage path.
        cellLimit: kMaxSplitPayloadBytes,
      );
      if (route == DeliveryRoute.refuseTooLarge) {
        _log.warn('sendToUser: $messageType measures ~$frameBytes B and '
            'exceeds even the split limit '
            '($kMaxSplitPayloadBytes B) — no silent detour via V3');
        return false;
      }
      // ── STEP 1 OF THE CUT: LARGE MEDIA GO ON THE BULK LANE ────
      //
      // §9.3: the blocks are "placed once each on always-on bulk
      // holders and harvested by the recipient on its own cadence".
      // `lib/core/bulk/` computes this completely; what is missing are the
      // two actions from [MediaBulkTransport].
      //
      // WHY REJECTED HERE AND NOT FALLEN BACK TO V3. The same reason for
      // which `refuseTooLarge` above rejects: a silent V3 path would be
      // the dual stack from §7, and it would be invisible because both
      // "work". The user sees the message on `failed`, not on a secret
      // second network.
      //
      // WHY IT IS ALWAYS REJECTED HERE, EVEN WITH A SEAM. `sendToUser` is
      // the MESSAGE path; a bulk object is not a message but a transfer
      // with mark, blocks and its own clock. It is submitted in
      // [sendMediaMessage], where the OBJECT size is known — here only
      // the frame is known. A second entry at this place would be a second
      // way to the same thing, and those drift apart (the same reason for
      // which `V41Host.sendFrame` keeps draw-seal-send in ONE place).
      if (route == DeliveryRoute.bulkLane) {
        _log.warn('sendToUser: $messageType measures ~$frameBytes B and '
            'belongs on the bulk lane (§9.3, lower limit '
            '$kFountainWorthwhileBytes B) — the message path does not carry '
            'it. To be submitted via sendMediaMessage. No fallback '
            'to V3.');
        return false;
      }
      // ── THE INVITATION LINE HAS ITS OWN ENTRY ────────────────
      //
      // Until S388 it was submitted in `sendContactRequest` (removed,
      // S388-BAU-KONTAKT: on V4.2 the request is package (2) of first
      // contact in mycelium, §15.5), and for the same reason for which the
      // bulk lane has its own entry: what is missing here is known there.
      // `sendToUser` knows the RECIPIENT; the invitation line, however,
      // hangs on the INVITATION KEY `K_inv(i)` from the read ContactSeed
      // (§15.3.2), and that stands at the contact record, not at the
      // frame. A second entry at this place would be a second way to the
      // same thing — and those drift apart.
      //
      // NO SILENT DETOUR: there is no second way for a contact request,
      // and inventing one would be the dual stack from §7.
      if (route == DeliveryRoute.inviteLine) {
        _log.warn('sendToUser: ${messageType.name} to '
            '${_hexShort(recipientUserId)} belongs on the invitation line '
            '(§15.3.2); this path has had no entry since S388 (the '
            'request is packet 2 of the first contact in mycelium) — the '
            'message path does not know `K_inv(i)`. Not sent.');
        if (l3Result != null && l3Result.isNotEmpty) l3Result[0] = false;
        return false;
      }
      if (route == DeliveryRoute.v41) {
        // ── ADDRESSING A DEVICE SPECIFICALLY WORKS NOW (§14.1, §14.7) ─
        //
        // Until S361 a rejection stood here: "the DEVICE mark from §14.1 is
        // not built". It is built (`device_line.dart`), and so the
        // rejection falls — not the reason it was right. That stays
        // literally: the shared twin line does NOT carry a device-bound
        // payload, it reaches all devices equally. What has changed is
        // that there is now a line that exactly ONE device harvests.
        //
        // Two real paths were affected, and both ended silently:
        // `approvePairRequest` (DEVICE_PAIR_APPROVE — that is §14.6.2,
        // "the delivery of delegated keys" from §14.7) and `rejectRotation`
        // (ROTATION_APPROVAL_RESPONSE, §14.5). Both called `sendToUser`
        // with `targetDeviceId` and got `false`.
        final isDeviceLine =
            isSelfSend && targetDeviceId != null && targetDeviceId.isNotEmpty;
        Uint8List? kDevice;
        if (isDeviceLine) {
          // DERIVED, NOT LOOKED UP (§14.1: "derivable without any
          // lookup"). `K_own` derives from the user KEM secrets of this
          // identity (`own_line.dart`), the device root from `K_own` and
          // the device identifier. If it throws — say because a secret is
          // missing —, the shared line is NOT taken as a substitute: that
          // would be exactly the propagation this line stands against.
          try {
            kDevice = deriveKDevice(
              kOwn: deriveKOwn(
                userX25519Secret: identity.x25519SecretKey,
                userMlKemSecret: identity.mlKemSecretKey,
              ),
              deviceNodeId: targetDeviceId,
            );
          } catch (e) {
            _log.error('sendToUser: ${messageType.name} to the own device '
                '${_hexShort(targetDeviceId)} — device line cannot be built '
                '($e). No fallback to the common line: it reaches '
                'ALL devices. Not sent.');
            if (l3Result != null && l3Result.isNotEmpty) l3Result[0] = false;
            return false;
          }
          // §14.7 gives the device line three uses, and all three ride
          // Secure. An ephemeral indicator or a call signalling is not
          // among them; there is also no caller for that today. Instead
          // of silently raising it to another mode, it is rejected by name
          // — a silent mode switch is exactly what must not happen here.
          if (skipL3) {
            _log.warn('sendToUser: ${messageType.name} to the own device '
                '${_hexShort(targetDeviceId)} requires the signal line '
                '(§17.2). The device line (§14.7) does not carry it — all '
                'three uses there ride Secure. Not sent.');
            if (l3Result != null && l3Result.isNotEmpty) l3Result[0] = false;
            return false;
          }
        }
        // The identifier of the own line carries NO counterpart — there is
        // none. Justification in the header of `own_line.dart`. The
        // identifier of the DEVICE line additionally carries the device
        // identifier, and the identity in it is mandatory (B-31): the
        // registry sits node-wide, the device node ID is daemon-global.
        final peer = isDeviceLine
            ? deviceLineKey(identity.userId, targetDeviceId)
            : isSelfSend
                ? ownPeerKey(identity.userId)
                : _v41PeerKey(recipientUserId);
        final v41MessageId = (messageId != null && messageId.isNotEmpty)
            ? messageId
            : SodiumFFI().randomBytes(16);
        // NOT on self-send: the own line is already registered
        // (`v41ArmOwnLine`, from `primeV41Pairs`), and with the same
        // inbound and outbound direction. A `rememberPeer` here would
        // overwrite it with the default `1 - out` — the twins would then
        // deposit on the one line and harvest from the other. Besides,
        // `v41PairKeyFor` throws for the own identifier, because it needs
        // two founding keys.
        if (isDeviceLine) {
          // ── ONLY SUPPLY, NEVER HARVEST ───────────────────────────────
          //
          // That is the whole effect of the device line. If this device
          // harvested the sibling's line along, it would get material the
          // sibling is meant for — and it could even open it (§14.2: all
          // own devices share the user KEM key, the sealing does not
          // separate here). On top, every foreign line would draw six real
          // marks per harvest run from a budget of six
          // (`kMaxRealHarvestTags`).
          v41.rememberPeer(peer, kDevice!,
              outDirection: kDeviceLineDirection, harvest: false);
        } else if (!isSelfSend) {
          v41.rememberPeer(peer, v41PairKeyFor(recipientUserId, contact),
              outDirection: v41OutDirectionFor(recipientUserId, contact));
        }
        // AGAINST WHOM IT IS SEALED. Until S349 the fallback in
        // `attachV41` took the OWN node key, independent of the recipient
        // (B-19) — the sender sealed to itself, and the other side could
        // never open it. The keys have long been resolved here (step 2,
        // including the overrides for group members without a contact
        // record); looking them up again would mean building a second
        // resolution that can deviate.
        v41HostRef.rememberPeerKeys(peer,
            x25519: recipientX25519Pk, mlKem: recipientMlKemPk);

        // ONE construction of the application frame, not two. The no-host
        // branch at the end of this method parks the same frame; if it had
        // its own construction, the two would drift apart (the same reason
        // for which `V41Host.sendFrame` keeps draw-seal-send in ONE place).
        final inner = _v41InnerFrame(
          recipientUserId: recipientUserId,
          senderUserId: effectiveSenderUserId,
          messageId: v41MessageId,
          messageType: messageType,
          payload: payload,
          groupId: groupId,
          contentMetadata: contentMetadata,
          editMetadata: editMetadata,
          expiryMetadata: expiryMetadata,
          groupMembershipEpoch: groupMembershipEpoch,
          groupMembershipHash: groupMembershipHash,
        );

        // The mode hangs on the conversation switch (§12): one-sided,
        // local, sender-side — like `withholdDeliveryStatus`, and therefore
        // NOT in `ChatConfig` and without a consent flow. It is written in
        // [setSecureMode] — NO LONGER by `chat_screen.dart` directly on the
        // object (30.08.: on desktop the GUI thus mutated its own snapshot,
        // the daemon never saw the choice). Here is its read side.
        //
        // `skipL3` keeps precedence: ephemeral signalling belongs on the
        // fast path, not in a deposit that lies for an hour. The default is
        // speed — secure costs ~1 h and is a deliberate choice of the
        // user, not a standard path.
        final groupsIdHex = (groupId != null && groupId.isNotEmpty)
            ? _hexOf(groupId)
            : null;
        // NOT `_contacts[peer]` — `peer` is the PAIR identifier from
        // `_v41PeerKey` (`<own64>/<foreign64>`, 129 characters), `_contacts`
        // is indexed at all 40 other access sites by the bare 64-digit
        // identifier. The lookup thus ALWAYS ran into nothing from S349 to
        // S351, `secureDesired` was ALWAYS `false` — secure mode was
        // unreachable for 1:1 chats, regardless of what the user had set.
        // The group branch next to it was never affected, because
        // `groupsIdHex` already is the bare identifier. The same error
        // class as with the capsule proof (64 versus 129), both from B-31:
        // `_v41PeerKey` had to include the own identity, and the read
        // sides were not pulled along.
        // ── WHAT EXPIRES WITHOUT VALUE IS NOT DEPOSITED (30.08.) ────
        //
        // A typing indicator only makes sense NOW. Via the secure deposit
        // it costs `m x R` control frames — 18 in the field, just as much
        // as a text — and possibly arrives an hour later; then it claims
        // someone is typing right now, and is not late but wrong.
        //
        // `skipL3` alone does NOT suffice for this: it does choose speed,
        // and `V41Node.send` switches to secure when there is no route
        // (v41_node.dart, branch `SendMode.speed`). In the field it said
        // `Speed-Routen 0` — so the indicator was deposited anyway.
        // `speedOnly` is the mode that discards in this case.
        //
        // ONLY TYPING INDICATORS. Receipts and read confirmations must
        // arrive: the one flips the delivery status and the capsule proof,
        // the other is a promise to the user. Whoever extends this set must
        // justify for each kind individually that its loss is without
        // consequence.
        const ephemeral = kV41Ephemeral;
        // THE DEVICE LINE IS ALWAYS SECURE (§14.7). Not as caution, but
        // because the document lists its three uses there — key packages
        // "ride Secure with the 31-day management TTL", the initial sync is
        // the manifest-and-fetch machinery from §13.5.2, and the delivery
        // of delegated keys belongs to the admission of a device. The path
        // speed -> secure is moreover the only direction the mode invariant
        // allows at all; a lookup in `_contacts` would be pointless here
        // anyway, the own identity never stands there.
        // NO MODE INPUT ANY MORE (S389). Up to here this branch read
        // `Contact.secureMode`/`Group.secureMode`. The switch is gone
        // (§12.1), and with it the V4.1 layer has no mode input from the
        // application any more.
        //
        // WHY `true` AND NOT `false`, although this branch is no longer
        // entered in operation (the mailbox switch further up returns
        // before, and `attachV41` has no caller in `lib/`): of the two
        // possible constants only one is allowed. The hard rule (owner,
        // 30.08.) permits the path speed -> secure and forbids the opposite
        // direction without the user's knowledge. `false` would be exactly
        // that opposite direction, compiled in as a constant.
        const secureDesired = true;
        // THE DELIVERY LAYER NEEDS THIS SETTING OUTSIDE OF SENDING TOO. It
        // decides for whom the node publishes its own return path (§6: the
        // liveness costs are tied to the mode choice per chat,
        // `1.15 + 0.23*S`, S = speed-capable contacts). [setSecureMode]
        // therefore reports it already when the switch is flipped — but
        // only for 1:1, because `setChatMode` is indexed by the PAIR and a
        // group choice would otherwise overwrite the DM choice of the same
        // member. This line here stays: it is the only one that also covers
        // the GROUP case, and it corrects the pair collision per leg
        // immediately before sending.
        // ── A SECURE CHAT IS NEVER SILENTLY DOWNGRADED TO SPEED ────
        //
        // INVARIANT (owner, 30.08.): a fallback from speed to secure is
        // defensible — it costs latency, not anonymity. The reverse
        // direction is NOT: speed is linkable (§7), secure is the user's
        // explicit choice against exactly that. It may only be broken if
        // the user NOTICES it.
        //
        // That is why an ephemeral indicator in a secure chat does NOT go
        // out AT ALL, instead of silently taking the fast path. Sending it
        // via the deposit would be the alternative — `m x R` control frames
        // for an indicator that is lying an hour later anyway. Not sending
        // is the only choice that violates neither anonymity nor the
        // egress budget.
        //
        // NEAR-MISS, recorded so that it does not come back: the first
        // version of this branch chose `speedOnly` for ephemeral kinds
        // REGARDLESS of the mode — in a secure chat the typing indicator
        // would thus have gone via the linkable path without anyone
        // seeing it.
        final chosenMode = sendMode(
          secureDesired: secureDesired,
          skipL3: skipL3,
          ephemeral: ephemeral.contains(messageType),
        );
        if (chosenMode == null) {
          // Ephemeral in a secure chat: do not send. See the invariant
          // at `sendMode`.
          return false;
        }
        v41.setChatMode(peer, secure: secureDesired);
        // SERIALISE ONCE, USE TWICE: the delivery layer seals these bytes,
        // and EXACTLY THESE bytes are put back by the outbox (§21.2). A
        // second call of `writeToBuffer` would be a second serialisation of
        // the same message — protobuf does not guarantee byte equality for
        // that, and the resubmission would then seal something other than
        // the first attempt.
        final frameBytes41 = Uint8List.fromList(inner.writeToBuffer());
        // ONE call, not three steps by hand: `sendFrame` draws the one-time
        // prekey (§4.6), seals against it and hands over to delivery.
        // Whoever called `seal()` directly here again would have skipped
        // the draw — exactly the error that killed the daemon.
        final outcome = v41HostRef.sendFrame(
          peer: peer,
          frame: frameBytes41,
          mode: chosenMode,
          now: DateTime.now().toUtc(),
          // THE IDENTIFIER GOES DOWN ALONG, so that it comes back with the
          // placement receipt. The delivery layer does not read it and does
          // not put it on the wire — it passes it through. Without that
          // `placed` would have no producer: the receipt names a leg, and
          // which message this leg carried is known only to this place.
          messageId: v41MessageId,
          // AND THE RETENTION CLASS. It takes the same path as the
          // identifier — passed through, decided nowhere along the way.
          management: management,
        );
        // THE DELIVERY RECORD OF THIS MESSAGE (§9.2). It is created here
        // because the identifier is created here — `v41MessageId` is the
        // identifier under which the other side later acknowledges.
        // Everything else is in `_v41NoteSend`.
        _v41NoteSend(v41MessageId, outcome);
        // ── AND INTO THE LEDGER (§21.2, gap G-4) ───────────────────────────
        //
        // "A node's own cells stay local until their placement is
        // substantiated." The entry stays until the delivery register
        // proves `placed` (>= 2 independent relays over EVERY piece from
        // ONE attempt), until an E2E receipt flips `delivered`, or until
        // the 14-day deadline carries it to `expired`.
        //
        // WHICH REJECTIONS DO NOT BELONG IN THE LEDGER, and why separately:
        //
        //   * `noPairKey` and `tooLarge` do NOT change by waiting
        //     (`V41Node.send` orders the checks itself by this criterion).
        //     Parking them would mean promising a resubmission that would
        //     always have the same result.
        //   * `notReady` does change — it means "no confirmed relay", and
        //     exactly that flips the readiness edge. That is the V4.1
        //     counterpart of the V3 edge `onNetworkChanged`, and
        //     `MessageStatusGuard` already counts on it above: "failed is
        //     deliberately NOT terminal … the one-shot outbox re-offers the
        //     cell on the next connectivity edge".
        //
        // AND NO EPHEMERAL INDICATOR. A typing indicator that is resubmitted
        // an hour later claims someone is typing right now — it would then
        // not be late but wrong. The same justification for which
        // `sendMode` does not deposit it in the first place.
        final parkable = !ephemeral.contains(messageType) &&
            (outcome.accepted || outcome.refusal == SendRefusal.notReady);
        if (parkable) {
          v41Outbox.add(V41OutboxEntry(
            messageId: v41MessageId,
            recipientUserId: recipientUserId,
            frame: frameBytes41,
            messageType: messageType.name,
            createdAtMs: DateTime.now().millisecondsSinceEpoch,
            groupIdHex: groupsIdHex,
            // THE OVERRIDES MUST COME ALONG. For a group or channel member
            // without its own contact record the KEM keys came via
            // `GROUP_INVITE` and are ONLY in the caller — which is long gone
            // at resubmission time. Without them, precisely these
            // recipients could never be resubmitted.
            x25519Pk: recipientX25519PkOverride,
            mlKemPk: recipientMlKemPkOverride,
            // ── THE CLASS IS STORED, THE MODE IS NOT ──────────
            //
            // The difference is not an oversight. The mode (§12) is an
            // ongoing choice of the user and is read AGAIN at
            // resubmission — a stored speed decision in a chat that has
            // meanwhile been set to secure would be the silent mode
            // switch that the invariant (owner, 30.08.) forbids.
            //
            // The retention class is the opposite: a property of THIS
            // message that no longer changes. And it cannot be
            // reconstructed from the entry — that only keeps
            // `messageType`, and `MTV3_KEY_ROTATION_BROADCAST` carries both
            // the routine and the emergency rotation. If it were dropped
            // here, a resubmitted emergency rotation would silently lie 3
            // instead of 31 days — the promised value would vanish at the
            // first network change.
            management: management,
          ));
          saveV41Outbox();
        }
        if (l3Result != null && l3Result.isNotEmpty) {
          // "Queued" is not "placed" — only the placement confirmation
          // flips that (§22.7). Here it only says that it was accepted.
          l3Result[0] = false;
        }
        // VISIBLE, not on debug. Reception logs every cell
        // ("V4.1 EMPFANG"); without the counterpart on the sending side it
        // is impossible to tell in the field whether a message never went
        // out or got lost on the way. Exactly this question was open on
        // 28.08. and cost a whole measurement run.
        // `shortPairLabel`, NOT `substring(0, 8)`: the identifier is
        // `own/counterpart`, and its first eight digits are always the
        // OWN identity (S350, point 10).
        _log.event('V4.1 SEND ${messageType.name} to '
            '${shortPairLabel(peer)} '
            '(${frameBytes41.length} B, '
            '${chosenMode.name}) — $outcome');
        return outcome.accepted;
      }
      // ── THE PATH ENDS HERE (CUT, 31.08.2026) ────────────────────────
      //
      // `DeliveryRoute.twoStage` "fell through unchanged" — namely into
      // the V3 cascade below. That no longer exists. The rest of this
      // method (around 390 lines) was: device resolution via
      // `node.resolveUserToDevices`, inner KEM + PoW via
      // `V3FrameCodec`, fan-out per device with
      // `node.sendToDeviceTracked`, `AckTracker.trackSend`,
      // Reed-Solomon distribution, store-and-forward on network peers and
      // the §5.8 outbox. Every single one of these pieces lived in
      // `lib/core/network/` or `lib/core/node/`.
      //
      // WHO LANDS HERE (re-measured 2026-09-01, S361) ────────────────
      //
      // Only [kV3InfraTypes] any more, and within it only the erasure
      // fragments (`MTV3_FRAGMENT_*`) and the DHT traffic (`MTV3_DHT_*`).
      // Both die with the V3 line and are (T): they have no subject in
      // V4.1, not merely no carrier. `routeFor` gives them `twoStage`
      // (`v41_routing.dart:234`), and that is the only branch that still
      // falls through to here.
      //
      // UNTIL S361 TWO THINGS STOOD HERE, AND BOTH WERE WRONG.
      //
      //   * "[kBootstrapTypes] … `routeFor` sends them DELIBERATELY to
      //     `twoStage` … That is **gap G-1**." — Measured false:
      //     `v41_routing.dart:200` returns `DeliveryRoute.inviteLine` for
      //     `kBootstrapTypes`, and BEFORE the `twoStage` branch in line 234.
      //     The switch above already catches `inviteLine` (same method,
      //     line 10288) and returns there. First contact therefore cannot
      //     reach this place at all. G-1 has moreover been closed since
      //     S360 — the `sendContactRequest` of that time delivered via the
      //     invitation line. The log line thus named to the reader a cause
      //     that no longer exists. S389: `sendContactRequest` itself has not
      //     existed since S388-BAU-KONTAKT; on V4.2 the request comes from
      //     an invitation card (§15.5) and goes via `sendToUser` like every
      //     send (§22.5).
      //
      //   * "the call frames … are **gap G-13** (`CallTransport` has had no
      //     implementation since the CUT)." — Measured false in two points.
      //     First, there is an implementation:
      //     `call_transport_v41.dart:83` `class CallTransportV41
      //     implements CallTransport`, constructed in production in
      //     `call_service.dart:192`, supplied with the D socket by
      //     `v41_attach.dart:851` (`service.attachCallDSocket`).
      //     Second, live call frames do not run through `sendToUser` at
      //     all: `call_service.dart:915` sends them via
      //     `callTransport.sendMedia(...)` directly on level D. The
      //     `MTV3_CALL_*` entries in [kV3InfraTypes] therefore have no
      //     caller in this path — they stand there as a block, not as a
      //     path. What is really still open at level D belongs under G-13,
      //     but not at THIS line.
      //
      // No silent detour: there is no second way that could be redirected
      // to here, and inventing one would be the dual stack from §7.
      _log.error('sendToUser: ${messageType.name} to '
          '${_hexShort(recipientUserId)} is V3 infrastructure '
          '(erasure fragment or DHT frame) and belongs on the '
          'two-stage path that fell with the CUT. V4.1 has no '
          'object for it (T) — no carrier is missing. Not sent.');
      if (l3Result != null && l3Result.isNotEmpty) l3Result[0] = false;
      return false;
    }

    // ── WITHOUT AN ATTACHED V4.1 DELIVERY NOTHING GOES OUT ───────────
    //
    // Only those get this far who (a) have not attached a V4.1 delivery
    // (`CLEONA_V41=0`, or a process that never calls `attachV41`) or
    // (b) send to the OWN identifier.
    //
    // (a) used to be the normal case — the body then fell into the V3
    // cascade. Now it is the state "no network attached".
    //
    // (b) is NO LONGER the twin sync. Until S360 this said:
    // "§14.1 names the right way — an OWN mark
    // `HKDF(K_own, "device" ‖ deviceId ‖ n)` —, and it has yet to be
    // created in `lib/core/tagline/`. **Gap G-14.**" That was true and
    // stays as a correction; the line is built now (`own_line.dart`), and
    // self-send goes through the switch above like any other delivery.
    // What remains at this place is only (a) — no node attached —, and
    // then it is not down to a mark, but to this process having no network.
    //
    // Since S361 that also holds for a send SPECIFICALLY aimed at a single
    // own device: the second line from §14.1 is built (`device_line.dart`)
    // and is entered in the switch above. Until then this said "that
    // still does not work".
    // ── WITHOUT A HOST IT IS PARKED, NOT DISCARDED (§21.2, S363) ───────
    //
    // ── THE FINDING ─────────────────────────────────────────────────
    //
    // Up to here EVERYTHING fell through that could not enter the host
    // branch — including messages that merely lacked the CARRIER because
    // it was not attached yet. That is not an edge case but the cold
    // start: `service_daemon.dart` calls `await
    // service.startService()` and only AFTERWARDS `attachV41(...)` (line 779
    // -> 790; `main.dart` line 2268 -> 2279 likewise). Everything that
    // `startService` itself still sends — the due key rotation to all
    // contacts was the most expensive case — reached this place with
    // `v41Delivery == null`, ran into the two `_log.error` lines below and
    // ended with `return false` — DISCARDED. Until S363 the outbound
    // compartment was only filled INSIDE the host branch (the only
    // `v41Outbox.add` site in all of `lib/` stood there), so there was no
    // resubmission either: the announcement was gone until the next
    // rotation in SEVEN DAYS (`needsRotation`, `kKemRotationInterval`).
    //
    // ── WHY PARK AND NOT SWAP THE ORDER ──────────────
    //
    // Swapping the order covers exactly one send site. §21.2 already
    // describes the right thing for this situation — "a node's own
    // cells stay local until their placement is substantiated" —, and
    // the compartment already has its drain with `flushV41Outbox`
    // (readiness edge). Parking therefore happens here, where EVERY
    // sender passes by.
    //
    // NO TIMER RETRY (working rule 5): the drain hangs on the readiness
    // edge, not on a clock.
    //
    // WHAT IS NOT PARKED, and why separately:
    //   * [kV41Ephemeral] — their loss is without consequence, their
    //     resubmission would be a lie (see there).
    //   * SELF-SEND — `v41PairKeyFor` cannot be formed for the own
    //     identity, the own line only exists after `v41ArmOwnLine`. An
    //     entry that the resubmission cannot seal would be a compartment
    //     that never drains.
    //   * V3 infrastructure — it has no SUBJECT in V4.1, not merely no
    //     carrier. Waiting changes nothing about that; that is the case
    //     the line below reports.
    final withoutCarrier = v41Delivery == null || v41Host == null;
    if (withoutCarrier &&
        !isSelfSend &&
        !kV41Ephemeral.contains(messageType) &&
        !kV3InfraTypes.contains(messageType)) {
      final parkedId = (messageId != null && messageId.isNotEmpty)
          ? messageId
          : SodiumFFI().randomBytes(16);
      final parked = _v41InnerFrame(
        recipientUserId: recipientUserId,
        senderUserId: effectiveSenderUserId,
        messageId: parkedId,
        messageType: messageType,
        payload: payload,
        groupId: groupId,
        contentMetadata: contentMetadata,
        editMetadata: editMetadata,
        expiryMetadata: expiryMetadata,
        groupMembershipEpoch: groupMembershipEpoch,
        groupMembershipHash: groupMembershipHash,
      );
      v41Outbox.add(V41OutboxEntry(
        messageId: parkedId,
        recipientUserId: recipientUserId,
        frame: Uint8List.fromList(parked.writeToBuffer()),
        messageType: messageType.name,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
        groupIdHex: (groupId != null && groupId.isNotEmpty)
            ? _hexOf(groupId)
            : null,
        x25519Pk: recipientX25519PkOverride,
        mlKemPk: recipientMlKemPkOverride,
        // The same justification as in the host branch: the class is a
        // property of THIS message and cannot be reconstructed from the
        // entry.
        management: management,
      ));
      saveV41Outbox();
      _log.warn('sendToUser: ${messageType.name} to '
          '${_hexShort(recipientUserId)} — NO V4.1 carrier yet '
          '(v41Delivery=${v41Delivery != null}, v41Host=${v41Host != null}). '
          'Put into the outbox (§21.2), drained at the '
          'readiness edge. Until S363 it was discarded here; a '
          'cold-start rotation was thus gone for seven days.');
      if (l3Result != null && l3Result.isNotEmpty) l3Result[0] = false;
      return false;
    }

    if (l3Result != null && l3Result.isNotEmpty) l3Result[0] = false;
    if (isSelfSend) {
      _log.error('sendToUser: self-send ${messageType.name} — no '
          'V4.1 delivery attached (v41Delivery=${v41Delivery != null}, '
          'v41Host=${v41Host != null}). The own line (§14.7) needs '
          'a running node like any other delivery.');
    } else {
      _log.error('sendToUser: ${messageType.name} to '
          '${_hexShort(recipientUserId)} — no V4.1 delivery '
          'attached (v41Delivery=${v41Delivery != null}, '
          'v41Host=${v41Host != null}). There is no second path any more.');
    }
    return false;
  }

  // ── §5.5 store-and-forward: remaining static member ──
  // The rest of the section lives in `cleona_service_v3_sf.dart`.
  // A `static` cannot move into an extension (§4c.5 limit 3):
  // it would then belong to the extension, and `CleonaService.isEmergency…`
  // would no longer resolve — smoke_emergency_rotation_v3_infra
  // calls exactly like that.

  /// Welle 6 §7.4 path-discriminator. Returns true iff [broadcast] carries
  /// the Emergency-variant dual-sig (both `oldSignatureEd25519` and
  /// `newSignatureEd25519` populated). Receivers use this to enforce the
  /// path constraint: Emergency belongs on the InfrastructureFrame path,
  /// Periodic on the ApplicationFrame path. Public so smoke tests can
  /// assert the discriminator behaviour without spinning up a full service.
  static bool isEmergencyKeyRotationBody(
      proto.KeyRotationBroadcast broadcast) {
    return broadcast.oldSignatureEd25519.isNotEmpty &&
        broadcast.newSignatureEd25519.isNotEmpty;
  }

  /// V3 READ_RECEIPT: mark outgoing as `read` and stamp readAt for expiry.
  /// Conversation lookup is DM-style (senderUserId-hex). Backward-compat
  /// with raw-message-ID payloads is dropped in V3 — V3 senders always
  /// emit a structured ReadReceipt protobuf.
  void _handleReadReceiptV3(HarvestEvent event) {
    try {
      final receipt = proto.ReadReceipt.fromBuffer(event.payload);
      if (receipt.messageId.isEmpty) return;
      final msgIdHex = receipt.messageId.hex;
      final readAt = receipt.readAt > 0
          ? DateTime.fromMillisecondsSinceEpoch(receipt.readAt.toInt())
          : DateTime.now();
      final conversationId =
          event.senderUserId.hex;
      final conv = conversations[conversationId];
      if (conv == null) return;
      ensureLoaded(conversationId);
      for (final msg in conv.messages) {
        // S390: the read marker colours the two ticks and does not touch
        // the delivery state. As `MessageStatus.read` it overwrote
        // `delivered` — and because it was terminal, the proof of §9.2
        // got lost in the process.
        if (msg.id == msgIdHex && msg.isOutgoing && !msg.readByRecipient) {
          msg.readByRecipient = true;
          persistMessage(conversationId, msg);
          msg.readAt ??= readAt;
          _saveConversations();
          onReadReceiptReceived?.call(conversationId, msgIdHex);
          break;
        }
      }
      onStateChanged?.call();
    } catch (e) {
      _logHandlerErrorEvent('handleReadReceiptV3', e, event);
    }
  }

  /// V3 TYPING_INDICATOR: animate typing dots in UI. Per-chat config
  /// (`typingIndicators`) gates the indicator on the receiver side.
  /// V3-Neuerung: empty/unparseable payload no longer treated as
  /// is_typing=true — V3 senders always send a structured TypingIndicator.
  void _handleTypingIndicatorV3(HarvestEvent event) {
    try {
      final senderHex = event.senderUserId.hex;
      // Parse first so that the convId-from-payload (group support) lands
      // even when the per-DM conversation hasn't materialised yet.
      bool isTyping = true;
      String convIdFromPayload = '';
      if (event.payload.isNotEmpty) {
        final indicator = proto.TypingIndicator.fromBuffer(event.payload);
        isTyping = indicator.isTyping;
        convIdFromPayload = indicator.conversationId;
      }
      final conversationId =
          convIdFromPayload.isNotEmpty ? convIdFromPayload : senderHex;
      final conv = conversations[conversationId];
      // Per-chat opt-out: receiver suppresses indicator if disabled.
      if (conv != null && !conv.config.typingIndicators) return;

      if (isTyping) {
        _typingTimestamps[senderHex] = DateTime.now();
      } else {
        _typingTimestamps.remove(senderHex);
      }
      onStateChanged?.call();
    } catch (e) {
      _logHandlerErrorEvent('handleTypingIndicatorV3', e, event);
    }
  }

  // C2 — Messaging
  //
  // Pattern (parallel to the C1 migration in _handleDeliveryReceiptV3 etc.):
  //   - Inner KEM decrypt + user sig verify have already been passed by the
  //     frame BEFORE the call (cleona_node.dart). Here only parse
  //     frame.payload + update UI state + notifications.
  //   - Multi-identity / group fan-out: ApplicationFrameV3.group_id (field 17)
  //     carries the group/channel conversation ID for pairwise fan-out (every
  //     member gets its own sendToUser call with identical group_id).
  //     Receiver reads frame.groupId and dispatches into the matching
  //     group/channel tab; empty = DM on sender hex.

  /// GM-2 (§9.1.4): centralized group-post gatekeeper. Returns null if the
  /// post should be dropped (non-member). Returns true if a split-view
  /// anomaly was detected (same/lower epoch, different hash).
  bool? _checkGroupPostMembership(HarvestEvent event, String senderHex) {
    final groupId = event.groupId;
    if (groupId == null) return false;
    final groupIdHex = groupId.hex;
    final group = _groups[groupIdHex];
    if (group == null) return false;

    if (!group.members.containsKey(senderHex)) {
      _log.warn('GM-2: group post from non-member ${senderHex.substring(0, 8)} '
          'in "${group.name}" — dropped');
      return null;
    }

    // `rosterVersion == null` covers BOTH previous exits: the factory
    // sets null exactly when the epoch is <= 0 (legacy sender without tag)
    // OR the hash is empty. Both led to `return false` here.
    final roster = event.rosterVersion;
    if (roster == null) return false;
    final wireEpoch = roster.epoch;
    final wireHash = roster.hash;

    final localEpoch = group.membershipEpoch;
    final localHash = _computeMembershipHash(localEpoch, groupIdHex, group.members);

    if (wireEpoch == localEpoch && constantTimeEquals(Uint8List.fromList(wireHash), localHash)) {
      return false; // match
    }

    if (wireEpoch > localEpoch) {
      // sender has newer membership — edge-triggered resync to owner
      final prevRequested = _resyncRequestedAtEpoch[groupIdHex] ?? 0;
      if (wireEpoch > prevRequested) {
        _resyncRequestedAtEpoch[groupIdHex] = wireEpoch;
        _sendResyncRequest(group);
      }
      return false; // not a split-view, just stale local state
    }

    // same or lower epoch, different hash → split-view anomaly
    _log.warn('GM-2: SPLIT-VIEW in "${group.name}" — '
        'local epoch=$localEpoch hash=${bytesToHex(localHash).substring(0, 16)}, '
        'wire epoch=$wireEpoch hash=${wireHash.hex.substring(0, 16)} '
        'from ${senderHex.substring(0, 8)}');
    return true;
  }

  void _sendResyncRequest(GroupInfo group) {
    final ownerHex = group.ownerNodeIdHex;
    if (ownerHex == identity.userIdHex) return; // we are owner, no need
    final req = proto.GroupMembershipResyncRequest()
      ..groupId = hexToBytes(group.groupIdHex)
      ..localEpoch = Int64(group.membershipEpoch);
    _detachedSend('MTV3_GROUP_MEMBERSHIP_RESYNC_REQUEST', sendToUser(
      recipientUserId: hexToBytes(ownerHex),
      messageType: proto.MessageTypeV3.MTV3_GROUP_MEMBERSHIP_RESYNC_REQUEST,
      payload: req.writeToBuffer(),
      groupId: hexToBytes(group.groupIdHex),
    ));
    _log.info('GM-2: RESYNC_REQUEST sent to owner ${ownerHex.substring(0, 8)} '
        'for group "${group.name}" (local epoch=${group.membershipEpoch})');
  }

  void _sendChannelResyncRequest(ChannelInfo channel) {
    final ownerHex = channel.ownerNodeIdHex;
    if (ownerHex == identity.userIdHex) return;
    final req = proto.GroupMembershipResyncRequest()
      ..groupId = hexToBytes(channel.channelIdHex)
      ..localEpoch = Int64(channel.membershipEpoch);
    _detachedSend('MTV3_GROUP_MEMBERSHIP_RESYNC_REQUEST', sendToUser(
      recipientUserId: hexToBytes(ownerHex),
      messageType: proto.MessageTypeV3.MTV3_GROUP_MEMBERSHIP_RESYNC_REQUEST,
      payload: req.writeToBuffer(),
      groupId: hexToBytes(channel.channelIdHex),
    ));
    _log.info('GM-4: RESYNC_REQUEST sent to channel owner ${ownerHex.substring(0, 8)} '
        'for "${channel.name}" (local epoch=${channel.membershipEpoch})');
  }

  void _handleGroupMembershipResyncRequest(HarvestEvent event) {
    try {
      final req = proto.GroupMembershipResyncRequest.fromBuffer(event.payload);
      final entityIdHex = req.groupId.hex;
      final senderHex = event.senderUserId.hex;

      // GM-4: dual-mode — handle both groups and channels
      final group = _groups[entityIdHex];
      final channel = _channels[entityIdHex];
      if (group == null && channel == null) return;

      if (group != null) {
        if (group.ownerNodeIdHex != identity.userIdHex) {
          _log.debug('GM-2: RESYNC_REQUEST for "$entityIdHex" but we are not owner — ignoring');
          return;
        }
        if (!group.members.containsKey(senderHex)) {
          _log.warn('GM-2: RESYNC_REQUEST from non-member ${senderHex.substring(0, 8)} — dropped');
          return;
        }
        final reqEpoch = req.localEpoch.toInt();
        if (reqEpoch >= group.membershipEpoch) {
          _log.debug('GM-2: RESYNC_REQUEST from ${senderHex.substring(0, 8)} '
              'already at epoch $reqEpoch (ours=${group.membershipEpoch}) — no resync needed');
          return;
        }
        _log.info('GM-2: RESYNC_REQUEST from ${senderHex.substring(0, 8)} '
            'epoch $reqEpoch < ${group.membershipEpoch} — sending GROUP_INVITE');
        unawaited(_broadcastGroupUpdate(group));
      } else {
        if (channel!.ownerNodeIdHex != identity.userIdHex) {
          _log.debug('GM-4: channel RESYNC_REQUEST for "$entityIdHex" but we are not owner — ignoring');
          return;
        }
        if (!channel.members.containsKey(senderHex)) {
          _log.warn('GM-4: channel RESYNC_REQUEST from non-member ${senderHex.substring(0, 8)} — dropped');
          return;
        }
        final reqEpoch = req.localEpoch.toInt();
        if (reqEpoch >= channel.membershipEpoch) {
          _log.debug('GM-4: channel RESYNC_REQUEST from ${senderHex.substring(0, 8)} '
              'already at epoch $reqEpoch (ours=${channel.membershipEpoch}) — no resync needed');
          return;
        }
        _log.info('GM-4: channel RESYNC_REQUEST from ${senderHex.substring(0, 8)} '
            'epoch $reqEpoch < ${channel.membershipEpoch} — sending CHANNEL_INVITE');
        unawaited(_broadcastChannelUpdate(channel));
      }
    } catch (e) {
      _log.warn('GM-2/4: RESYNC_REQUEST parse fail: $e');
    }
  }

  /// V3 TEXT: TextMessageV3-payload. Reply-fields (replyToMessageId +
  /// replyToSnippet) live on the proto sub-message. Link-Preview travels
  /// in `tm.linkPreview` (sender-side only — the receiver renders the card
  /// from the embedded data and MUST NOT issue a network request).
  void _handleTextV3(HarvestEvent event) {
    try {
      final tm = proto.TextMessageV3.fromBuffer(event.payload);
      final senderHex = event.senderUserId.hex;
      final msgId = event.messageId.hex;
      // V3: ApplicationFrameV3.group_id (field 17) carries the group/channel
      // conversation ID for pairwise fan-out. Empty = DM on sender hex.
      final conversationId = event.groupId != null
          ? event.groupId!.hex
          : senderHex;

      // GM-2 (§9.1.4): centralized membership gatekeeper
      final mismatchResult = _checkGroupPostMembership(event, senderHex);
      if (mismatchResult == null) return; // non-member, dropped
      final isMembershipMismatch = mismatchResult;

      // Reply metadata: hex-encode the wire bytes; resolve sender display-
      // name from the local conversation (best-effort; UI falls back to the
      // snippet text if the original bubble is no longer retained).
      String? replyToMessageId;
      String? replyToText;
      String? replyToSender;
      if (tm.replyToMessageId.isNotEmpty) {
        replyToMessageId =
            tm.replyToMessageId.hex;
        if (tm.replyToSnippet.isNotEmpty) replyToText = tm.replyToSnippet;
        final origConv = conversations[conversationId];
        if (origConv != null) {
          final orig = origConv.messages
              .where((m) => m.id == replyToMessageId)
              .firstOrNull;
          if (orig != null) {
            replyToSender = _contacts[orig.senderNodeIdHex]?.displayName ??
                orig.senderNodeIdHex.substring(0, 8);
            // If the snippet on the wire was empty (older sender or trimmed),
            // fall back to the text we still have locally.
            replyToText ??= orig.text.length > 200
                ? orig.text.substring(0, 200)
                : orig.text;
          }
        }
      }

      final msg = UiMessage(
        id: msgId,
        conversationId: conversationId,
        senderNodeIdHex: senderHex,
        text: tm.text,
        timestamp: (event.claimedSentAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
        type: UiMessageType.text,
        status: MessageStatus.delivered,
        isOutgoing: false,
        readAt: DateTime.now(),
        replyToMessageId: replyToMessageId,
        replyToText: replyToText,
        replyToSender: replyToSender,
        membershipMismatch: isMembershipMismatch,
      );

      // Link preview from sender (Architecture §2.3.4). We trust the
      // sender-supplied data and DO NOT fetch — empty url means no preview.
      if (tm.hasLinkPreview() && tm.linkPreview.url.isNotEmpty) {
        final lp = tm.linkPreview;
        msg.linkPreviewUrl = lp.url;
        msg.linkPreviewTitle = lp.title.isNotEmpty ? lp.title : null;
        msg.linkPreviewDescription =
            lp.description.isNotEmpty ? lp.description : null;
        msg.linkPreviewSiteName =
            lp.siteName.isNotEmpty ? lp.siteName : null;
        if (lp.thumbnail.isNotEmpty) {
          msg.linkPreviewThumbnailBase64 = base64Encode(lp.thumbnail);
        }
      }

      final isChannel = _channels.containsKey(conversationId);
      final isGroup = _groups.containsKey(conversationId);
      final isNew = _addMessageToConversation(conversationId, msg,
          isGroup: isGroup, isChannel: isChannel);
      if (isNew && !_shouldSuppressNotification(
          conversationId, msg.timestamp.millisecondsSinceEpoch)) {
        notificationSound.playMessageSound(
            soundName: conversations[conversationId]?.notificationSoundName);
        notificationSound.vibrate(VibrationType.message);
        final senderName =
            _contacts[senderHex]?.displayName ?? senderHex.substring(0, 8);
        _postAndroidNotification(
            senderName,
            tm.text.length > 100 ? '${tm.text.substring(0, 100)}...' : tm.text,
            conversationId);
        _lastNotifiedAt[conversationId] = DateTime.now();
      }
      // ── MESSAGE TEXT BELONGS IN NO LOG LINE (S363) ──────────
      //
      // Here stood the first 50 characters of EVERY received text message.
      // The log file lies unencrypted (`clogger.dart`, `writeAsString`) and
      // is the first thing an error report passes on — the bug log channel
      // (§9.5) and the manual log report send it to third parties. The
      // storage encryption from S362 thus missed exactly the information
      // it is meant to protect.
      //
      // NOT downgraded to `debug`, but CONTENT REMOVED: `debug` is the
      // normal case on the beta channel with seven days of retention
      // (`clogger.dart`), and this is message text, not a name. The owner
      // decision of 02.09.2026 allows "only on debug" for DISPLAY NAMES,
      // not for content.
      //
      // The LENGTH stays: it answers "did something arrive and how big was
      // it" without revealing anything — the same form to which S362
      // switched the three places found at the time.
      _log.info(
          'TEXT-V3 from ${senderHex.substring(0, 8)} (device=${_hexShort(event.senderDeviceId)}): '
          '${tm.text.length} characters');
    } catch (e) {
      _logHandlerErrorEvent('handleTextV3', e, event);
    }
  }

  /// V3 MEDIA_INLINE: ≤256KB inline payload (raw bytes or VoicePayload
  /// proto depending on MIME). frame.contentMetadata carries MIME, filename, size.
  void _handleMediaInlineV3(HarvestEvent event) {
    try {
      final senderHex = event.senderUserId.hex;
      final mismatchResult = _checkGroupPostMembership(event, senderHex);
      if (mismatchResult == null) return;
      final isMembershipMismatch = mismatchResult;
      final msgId = event.messageId.hex;
      final conversationId = event.groupId != null
          ? event.groupId!.hex
          : senderHex;
      final metadata = event.contentMetadata ?? proto.ContentMetadata();

      // Voice: VoicePayload-Wrapper.
      Uint8List actualFileData = Uint8List.fromList(event.payload);
      String? transcriptText;
      String? transcriptLanguage;
      double? transcriptConfidence;
      final isVoice = metadata.mimeType.startsWith('audio/');
      if (isVoice) {
        try {
          final voicePayload = proto.VoicePayload.fromBuffer(event.payload);
          if (voicePayload.audioData.isNotEmpty) {
            actualFileData = Uint8List.fromList(voicePayload.audioData);
            if (voicePayload.transcriptText.isNotEmpty) {
              transcriptText = voicePayload.transcriptText;
              transcriptLanguage = voicePayload.transcriptLanguage;
              transcriptConfidence = voicePayload.transcriptConfidence.toDouble();
            }
          }
        } catch (_) {/* raw audio bytes */}
        // Fallback: transcript from the metadata. Current senders fill both
        // carriers; a sender that only fills the metadata is also
        // understood correctly here.
        if (transcriptText == null && metadata.transcriptText.isNotEmpty) {
          transcriptText = metadata.transcriptText;
          transcriptLanguage = metadata.transcriptLanguage;
          transcriptConfidence = metadata.transcriptConfidence.toDouble();
        }
      }

      final mediaDir = Directory('$profileDir/media');
      if (!mediaDir.existsSync()) mediaDir.createSync(recursive: true);
      final filename =
          metadata.filename.isNotEmpty ? metadata.filename : 'file_$msgId';
      final savePath = _uniqueMediaPath(mediaDir.path, filename);
      // S362: encrypted. Up to here this line wrote the attachment in
      // plaintext next to the encrypted message.
      MediaStore.instance.writeBytes(savePath, actualFileData);

      final thumbnailB64 =
          metadata.thumbnail.isNotEmpty ? base64Encode(metadata.thumbnail) : null;
      final effectiveThumbnail = thumbnailB64 ??
          (metadata.mimeType.startsWith('image/') &&
                  actualFileData.length <= 100 * 1024
              ? base64Encode(actualFileData)
              : null);

      final msg = UiMessage(
        id: msgId,
        conversationId: conversationId,
        senderNodeIdHex: senderHex,
        text: filename,
        timestamp:
            (event.claimedSentAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
        type: _msgTypeFromMime(metadata.mimeType),
        status: MessageStatus.delivered,
        isOutgoing: false,
        filePath: savePath,
        mimeType: metadata.mimeType,
        fileSize: actualFileData.length,
        filename: filename,
        thumbnailBase64: effectiveThumbnail,
        mediaState: MediaDownloadState.completed,
        transcriptText: transcriptText,
        transcriptLanguage: transcriptLanguage,
        transcriptConfidence: transcriptConfidence,
        membershipMismatch: isMembershipMismatch,
      );

      final isGroup = _groups.containsKey(conversationId);
      final isNew = _addMessageToConversation(conversationId, msg, isGroup: isGroup);
      if (isNew && !_shouldSuppressNotification(
          conversationId, msg.timestamp.millisecondsSinceEpoch)) {
        notificationSound.playMessageSound(
            soundName: conversations[conversationId]?.notificationSoundName);
        notificationSound.vibrate(VibrationType.message);
        final senderName =
            _contacts[senderHex]?.displayName ?? senderHex.substring(0, 8);
        final label = metadata.mimeType.startsWith('image/')
            ? '📷 Image'
            : metadata.mimeType.startsWith('video/')
                ? '🎬 Video'
                : metadata.mimeType.startsWith('audio/')
                    ? '🎵 Audio'
                    : '📎 File';
        _postAndroidNotification(senderName, label, conversationId);
        _lastNotifiedAt[conversationId] = DateTime.now();
      }
      _log.info(
          '[E2E media-inline-v3-recv] from=${senderHex.substring(0, 8)} '
          'device=${_hexShort(event.senderDeviceId)} msgId=${msgId.substring(0, 8)} '
          'filename=$filename size=${actualFileData.length} mime=${metadata.mimeType}');

      // Local transcription fallback for voice without source-side transcript.
      if (isVoice && transcriptText == null) {
        _voiceTranscription?.enqueueTranscription(
          messageId: msgId,
          audioFilePath: savePath,
        );
      }
    } catch (e) {
      _logHandlerErrorEvent('handleMediaInlineV3', e, event, messageType: 'failed');
    }
  }

  /// V3 MEDIA_REQUEST: Stage-2 trigger — receiver asks the sender to push
  /// the actual content. payload carries the original message_id (16 bytes)
  /// the requester wants. Sender looks up the pending file and emits a
  /// MediaChunkV3 stream (≤32KB per chunk) + a final MediaCompleteV3 with
  /// SHA-256 of the assembled bytes.
  Future<void> _handleMediaRequestV3(HarvestEvent event) async {
    try {
      // ── THE REFILL REQUEST OF THE BULK LANE (§9.3 "refill", S363) ───────
      //
      // Since the CUT MEDIA_REQUEST carries TWO roles: the V3 request
      // (payload = 16 B message identifier) and the V4.1 refill request
      // (payload = 14 B, marker byte `0xB3`). `v41_routing.dart` has said
      // so since S349 ("§9.3 'request' + 'refill'"), only there was no
      // receive branch for the second role.
      //
      // The distinction is not guessed but enforced:
      // `BulkRefillRequest.decode` requires exactly 14 B, the marker byte
      // and the format version. A 16 B V3 payload already fails on the
      // length. The same pattern stands in `_handleMediaCompleteV3` for
      // the DECODED receipt.
      final missingRequest =
          BulkRefillRequest.decode(Uint8List.fromList(event.payload));
      if (missingRequest != null) {
        _handleBulkRefill(event, missingRequest);
        return;
      }
      final senderHex = event.senderUserId.hex;
      // V3-payload: opaque bytes = original message_id we should ship.
      final originalMsgIdBytes = Uint8List.fromList(event.payload);
      final originalMsgId = bytesToHex(originalMsgIdBytes);
      final filePath = _pendingMediaSends[originalMsgId];
      _log.info(
          '[E2E media-request-v3-recv] from=${senderHex.substring(0, 8)} '
          'device=${_hexShort(event.senderDeviceId)} '
          'wantsMsgId=${originalMsgId.length >= 8 ? originalMsgId.substring(0, 8) : originalMsgId} '
          'pending=${filePath != null}');
      if (filePath == null) {
        final recovered = _recoverPendingMediaPath(originalMsgId);
        if (recovered == null) {
          _log.warn(
              'media-request-v3: no pending media for ${originalMsgId.length >= 8 ? originalMsgId.substring(0, 8) : originalMsgId}');
          return;
        }
        _pendingMediaSends[originalMsgId] = recovered;
        _savePendingMediaSends();
        _log.info('media-request-v3: recovered pending path from conversation history');
      }
      final resolvedPath = _pendingMediaSends[originalMsgId]!;
      final file = File(resolvedPath);
      if (!file.existsSync()) {
        _log.warn('media-request-v3: pending file vanished: $resolvedPath');
        _pendingMediaSends.remove(originalMsgId);
        _savePendingMediaSends();
        return;
      }

      final fileBytes = file.readAsBytesSync();
      final contentHash = SodiumFFI().sha256(fileBytes);

      // Chunk into ≤32KB pieces. Each chunk is its own ApplicationFrameV3
      // shipped via sendToUser → per-chunk KEM-encrypted (Spec §5.7 Stage 2).
      const chunkSize = 32 * 1024;
      final totalChunks = (fileBytes.length + chunkSize - 1) ~/ chunkSize;
      final recipientUserId = Uint8List.fromList(event.senderUserId);

      _log.info(
          '[E2E media-stage2-send-v3] msgId=${originalMsgId.substring(0, 8)} '
          'recipient=${senderHex.substring(0, 8)} size=${fileBytes.length} '
          'chunks=$totalChunks');

      for (var idx = 0; idx < totalChunks; idx++) {
        final start = idx * chunkSize;
        final end = (start + chunkSize > fileBytes.length)
            ? fileBytes.length
            : start + chunkSize;
        final chunkData = fileBytes.sublist(start, end);
        final chunk = proto.MediaChunkV3()
          ..mediaId = originalMsgIdBytes
          ..chunkIndex = idx
          ..totalChunks = totalChunks
          ..data = chunkData;
        final ok = await sendToUser(
          recipientUserId: recipientUserId,
          messageType: proto.MessageTypeV3.MTV3_MEDIA_CHUNK,
          payload: Uint8List.fromList(chunk.writeToBuffer()),
        );
        if (!ok) {
          _log.warn(
              'media-request-v3: chunk $idx/$totalChunks send FAILED — abort');
          return;
        }
      }

      final complete = proto.MediaCompleteV3()
        ..mediaId = originalMsgIdBytes
        ..contentHash = contentHash
        ..totalSize = Int64(fileBytes.length);
      final okComplete = await sendToUser(
        recipientUserId: recipientUserId,
        messageType: proto.MessageTypeV3.MTV3_MEDIA_COMPLETE,
        payload: Uint8List.fromList(complete.writeToBuffer()),
      );
      _log.info(
          '[E2E media-stage2-send-done-v3] msgId=${originalMsgId.substring(0, 8)} '
          'complete-ok=$okComplete');

      // Sender finished — clear pending entry. (Receiver-side hash-check
      // protects against truncation; we don't keep retries here.)
      if (okComplete) {
        _pendingMediaSends.remove(originalMsgId);
        _savePendingMediaSends();
      }
    } catch (e, st) {
      _log.warn('handleMediaRequestV3: failed: $e\n$st '
          '(sender=${_hexShort(Uint8List.fromList(event.senderUserId))})');
    }
  }

  /// V3 MEDIA_REJECT: receiver declined the announce; sender clears pending.
  void _handleMediaRejectV3(HarvestEvent event) {
    try {
      final senderHex = event.senderUserId.hex;
      final originalMsgId = event.payload.hex;
      final removed = _pendingMediaSends.remove(originalMsgId) != null;
      _log.info(
          '[E2E media-reject-v3-recv] from=${senderHex.substring(0, 8)} '
          'device=${_hexShort(event.senderDeviceId)} '
          'msgId=${originalMsgId.length >= 8 ? originalMsgId.substring(0, 8) : originalMsgId} '
          'pending-cleared=$removed');
    } catch (e) {
      _log.warn('handleMediaRejectV3: failed: $e');
    }
  }

  /// V3 REACTION: EmojiReaction proto in frame.payload. Add/remove emoji
  /// on the target message. Conversation lookup is DM-style on sender hex
  /// (group fan-out see class header TODO).
  void _handleReactionV3(HarvestEvent event) {
    try {
      final senderHex = event.senderUserId.hex;
      if (_checkGroupPostMembership(event, senderHex) == null) return;
      final reaction = proto.EmojiReaction.fromBuffer(event.payload);
      final targetMsgId =
          reaction.messageId.hex;
      final emoji = reaction.emoji;
      if (emoji.isEmpty) return;

      final conversationId = event.groupId != null
          ? event.groupId!.hex
          : senderHex;
      final conv = conversations[conversationId];
      if (conv == null) return;
      ensureLoaded(conversationId);
      _log.debug('_handleReactionV3: emoji=$emoji targetMsgId=${targetMsgId.substring(0, 8)} conv.messages.length=${conv.messages.length}');
      ensureLoaded(conversationId);
      final msgIndex = conv.messages.indexWhere((m) => m.id == targetMsgId);
      if (msgIndex < 0) return;
      final msg = conv.messages[msgIndex];

      if (reaction.remove) {
        msg.reactions[emoji]?.remove(senderHex);
        if (msg.reactions[emoji]?.isEmpty ?? false) {
          msg.reactions.remove(emoji);
        }
      } else {
        msg.reactions.putIfAbsent(emoji, () => {});
        msg.reactions[emoji]!.add(senderHex);
      }
      // Behind both branches — the same justification as for the own
      // reaction path: the call used to stand in the INNER `if` and thus
      // only covered the case in which the emoji set became empty.
      persistMessage(conversationId, msg);
      onStateChanged?.call();
      _saveConversations();
      _log.debug(
          'REACTION-V3 ${reaction.remove ? "removed" : "added"}: $emoji on '
          '${targetMsgId.substring(0, 8)} by ${senderHex.substring(0, 8)} '
          'device=${_hexShort(event.senderDeviceId)}');
    } catch (e) {
      _log.warn('handleReactionV3: parse fail: $e');
    }
  }

  /// V3 REPLY: so far there is no dedicated ReplyMessageV3 sub-schema. Reply
  /// travels as TEXT with reply_to_* in ContentMetadata. Until spec §5
  /// defines a ReplyMessageV3 we treat REPLY identically to TEXT —
  /// the reply fields are extracted from ContentMetadata if present.
  void _handleReplyV3(HarvestEvent event) {
    try {
      final senderHex = event.senderUserId.hex;
      final mismatchResult = _checkGroupPostMembership(event, senderHex);
      if (mismatchResult == null) return;
      final isMembershipMismatch = mismatchResult;
      final tm = proto.TextMessageV3.fromBuffer(event.payload);
      final msgId = event.messageId.hex;
      final conversationId = event.groupId != null
          ? event.groupId!.hex
          : senderHex;

      // TODO C4: reply_to_message_id / reply_to_text / reply_to_sender
      // need a ReplyMetadataV3 field. ContentMetadata has no reply slot
      // today — until the spec clarifies, REPLY lands without a reply banner.
      final msg = UiMessage(
        id: msgId,
        conversationId: conversationId,
        senderNodeIdHex: senderHex,
        text: tm.text,
        timestamp:
            (event.claimedSentAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
        type: UiMessageType.text,
        status: MessageStatus.delivered,
        isOutgoing: false,
        readAt: DateTime.now(),
        membershipMismatch: isMembershipMismatch,
      );
      final isChannel = _channels.containsKey(conversationId);
      final isGroup = _groups.containsKey(conversationId);
      _addMessageToConversation(conversationId, msg,
          isGroup: isGroup, isChannel: isChannel);
      _log.info(
          'REPLY-V3 (treated as TEXT — Reply-Schema TODO C4) '
          'from ${senderHex.substring(0, 8)} device=${_hexShort(event.senderDeviceId)}');
    } catch (e) {
      _log.warn('handleReplyV3: parse fail: $e');
    }
  }

  /// V3 EDIT: MessageEdit proto in payload + EditMetadata as standard frame
  /// field. Dual-Enforcement (sender == author + edit-window).
  void _handleEditV3(HarvestEvent event) {
    try {
      final senderHex = event.senderUserId.hex;
      if (_checkGroupPostMembership(event, senderHex) == null) return;
      final editMsg = proto.MessageEdit.fromBuffer(event.payload);
      final originalMsgId =
          editMsg.originalMessageId.hex;
      final conversationId = event.groupId != null
          ? event.groupId!.hex
          : senderHex;
      final conv = conversations[conversationId];
      if (conv == null) return;
      ensureLoaded(conversationId);
      final msgIndex =
          conv.messages.indexWhere((m) => m.id == originalMsgId);
      if (msgIndex < 0) return;
      final original = conv.messages[msgIndex];

      // Dual-Enforcement: only original author can edit.
      if (original.senderNodeIdHex != senderHex) {
        _log.warn(
            'EDIT-V3 rejected: sender ${senderHex.substring(0, 8)} != author '
            '(device=${_hexShort(event.senderDeviceId)})');
        return;
      }

      // Edit-Window check — receiver uses the wider tolerance to avoid
      // rejecting edits from older nodes that still use the 60-min default.
      final chatEditWindowMs =
          conv.config.editWindowMs ?? _receiverEditToleranceMs;
      if (chatEditWindowMs == 0) {
        _log.warn('EDIT-V3 rejected: editing disabled for $conversationId');
        return;
      }
      if (chatEditWindowMs > 0) {
        final ageMs = DateTime.now().millisecondsSinceEpoch -
            original.timestamp.millisecondsSinceEpoch;
        if (ageMs > chatEditWindowMs) {
          _log.warn('EDIT-V3 rejected: too old (${ageMs}ms > ${chatEditWindowMs}ms)');
          return;
        }
      }

      original.text = editMsg.newText;
      original.editedAt = DateTime.fromMillisecondsSinceEpoch(
          editMsg.editTimestamp.toInt());
          persistMessage(conversationId, original);
      onStateChanged?.call();
      _saveConversations();
      _log.info(
          'EDIT-V3 by ${senderHex.substring(0, 8)} on $originalMsgId');
    } catch (e) {
      _log.warn('handleEditV3: parse fail: $e');
    }
  }

  /// V3 DELETE: MessageDelete proto in payload. Soft-delete (clear text +
  /// mark isDeleted).
  void _handleDeleteV3(HarvestEvent event) {
    try {
      final senderHex = event.senderUserId.hex;
      if (_checkGroupPostMembership(event, senderHex) == null) return;
      final deleteMsg = proto.MessageDelete.fromBuffer(event.payload);
      final targetMsgId =
          deleteMsg.messageId.hex;
      final conversationId = event.groupId != null
          ? event.groupId!.hex
          : senderHex;
      final conv = conversations[conversationId];
      if (conv == null) return;
      ensureLoaded(conversationId);
      final msgIndex = conv.messages.indexWhere((m) => m.id == targetMsgId);
      if (msgIndex < 0) return;
      final original = conv.messages[msgIndex];

      if (original.senderNodeIdHex != senderHex) {
        _log.warn(
            'DELETE-V3 rejected: sender ${senderHex.substring(0, 8)} != author '
            '(device=${_hexShort(event.senderDeviceId)})');
        return;
      }
      original.text = '';
      original.isDeleted = true;
      persistMessage(conversationId, original);
      onStateChanged?.call();
      _saveConversations();
      _log.info('DELETE-V3 by ${senderHex.substring(0, 8)} on $targetMsgId');
    } catch (e) {
      _log.warn('handleDeleteV3: parse fail: $e');
    }
  }

  /// V3 VOICE_MESSAGE: alias for MEDIA_INLINE with audio MIME — share the
  /// same code path. The dedicated message type exists so receivers can
  /// route voice through transcription pipelines without sniffing MIME.
  void _handleVoiceMessageV3(HarvestEvent event) {
    // Sender must ensure that contentMetadata.mimeType is audio/*.
    // If empty: default audio/aac (Architecture §5).
    //
    // The default runs via a COPY, not via the received frame.
    // Reason (measured, not derived): if one reads an unset protobuf
    // message field, dart-protobuf returns the READ-ONLY default instance.
    // The old version wrote directly onto it and threw in exactly the case
    // the default was meant for:
    //   UnsupportedError: Attempted to change a read-only message
    //                     (cleona.ContentMetadata)
    // No try/catch on the whole way up to the UDP receive loop catches
    // that (three callers of handleApplicationFrame, plus
    // cleona_node.dart::CleonaNode.onApplicationFramePayload).
    final md = event.contentMetadata;
    if (md == null || md.mimeType.isEmpty) {
      final patched = (md ?? proto.ContentMetadata()).clone()
        ..mimeType = 'audio/aac';
      _handleMediaInlineV3(event.withContentMetadata(patched));
      return;
    }
    _handleMediaInlineV3(event);
  }
  void _handleIdentityDeletedV3(HarvestEvent event) {
    // The inner payload is the IdentityDeletedNotification protobuf,
    // already decrypted + authenticated by the V3 pipeline (outer-sig +
    // inner user-sig + KEM-decap).
    final senderHex = event.senderUserId.hex;

    proto.IdentityDeletedNotification notification;
    try {
      notification = proto.IdentityDeletedNotification.fromBuffer(event.payload);
    } catch (e) {
      _log.error('IDENTITY_DELETED parse failed: $e');
      return;
    }

    final contact = _contacts[senderHex];
    if (contact == null) {
      _log.debug('IDENTITY_DELETED from unknown sender ${senderHex.substring(0, 8)}');
      return;
    }

    final displayName = notification.displayName.isNotEmpty
        ? notification.displayName
        : contact.displayName;
    // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
    _log.debug('Identity deleted: "$displayName" (${senderHex.substring(0, 8)})');

    // Add system message to conversation. Routed through
    // _addMessageToConversation so the badge counter and the system Launcher-
    // Badge stay in sync (#U15 — direct conv.messages.add bypassed both).
    if (conversations.containsKey(senderHex)) {
      final systemMsg = UiMessage(
        id: event.messageId.hex,
        conversationId: senderHex,
        senderNodeIdHex: '',
        text: '$displayName has deleted their identity.',
        isOutgoing: false,
        timestamp: DateTime.now(),
        type: UiMessageType.identityDeleted,
        status: MessageStatus.delivered,
      );
      _addMessageToConversation(senderHex, systemMsg);
    }

    // Mark contact as deleted (prevents re-import)
    _deletedContacts.add(senderHex);

    // Remove from groups/channels
    for (final group in _groups.values) {
      group.members.remove(senderHex);
    }
    for (final channel in _channels.values) {
      channel.members.remove(senderHex);
    }

    // ── THE CONTACT STAYS (§15.7) ──────────────────────────────────────
    //
    // Here stood `_contacts.remove(senderHex)`. §15.7 says the opposite,
    // literally: "The recipient **does not remove the contact**, but marks
    // it 'deleted,' archives the conversation read-only, and continues to
    // show name and picture with a '(deleted)' suffix."
    //
    // WHY THIS IS NOT COSMETIC. With the contact vanished the only place
    // where display name and picture of the counterpart stood. The
    // conversation history stayed (`conversations` is not touched) — but
    // without a contact the UI shows only a hex identifier for every line
    // in it. The user thus lost the attribution of their own past, without
    // anybody having decided that. And the system line directly above
    // ("X has deleted their identity") then stood in a conversation whose
    // counterpart the app could no longer name.
    //
    // `_deletedContacts` prevents re-reading; the contact itself now carries
    // the state in its own `status`, like every other state (§15.9 lists
    // `deleted` and `blocked` as contact states, not as the absence of a
    // contact).
    contact.status = 'deleted';
    _saveContacts();
    _saveGroups();
    _saveChannels();

    onStateChanged?.call();
  }
  void _handleProfileUpdateV3(HarvestEvent event) {
    // Inner payload is the ProfileData protobuf, already decrypted +
    // authenticated by the V3 pipeline.
    final senderHex = event.senderUserId.hex;

    try {
      final profile = proto.ProfileData.fromBuffer(event.payload);
      final contact = _contacts[senderHex];
      if (contact == null) return;

      if (profile.profilePicture.isNotEmpty) {
        contact.profilePictureBase64 = base64Encode(profile.profilePicture);
      } else {
        contact.profilePictureBase64 = null; // Picture removed
      }

      // Update description if present
      if (profile.description.isNotEmpty) {
        contact.message = profile.description;
      } else {
        contact.message = null;
      }

      // Handle display name change
      if (profile.displayName.isNotEmpty && profile.displayName != contact.displayName) {
        if (contact.localAlias != null) {
          // User has a local alias → store as pending, don't auto-override
          contact.pendingNameChange = profile.displayName;
          // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
          _log.debug('Contact ${contact.effectiveName} changed name to "${profile.displayName}" (pending, local alias active)');
        } else {
          // No local alias → update directly
          final oldName = contact.displayName;
          contact.displayName = profile.displayName;
          // Update conversation displayName
          final conv = conversations[senderHex];
          if (conv != null) {
            conv.displayName = profile.displayName;
          }
          // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
          _log.debug('Contact renamed: "$oldName" → "${profile.displayName}"');
        }
      }

      // Update conversation profile picture
      final conv = conversations[senderHex];
      if (conv != null) {
        conv.profilePictureBase64 = contact.profilePictureBase64;
      }

      _saveContacts();
      onStateChanged?.call();
      _log.info('Profile update from ${contact.effectiveName}');
    } catch (e) {
      _log.error('PROFILE_UPDATE parse error: $e');
    }
  }
  void _handleKeyRotationBroadcastV3(HarvestEvent event) {
    // V3-direct: inner payload is the KeyRotationBroadcast (Periodic
    // variant) protobuf, already decrypted + authenticated by the V3
    // pipeline.
    //
    // IN V4.1 THE PATH IS NO LONGER A DISTINGUISHING FEATURE.
    //
    // Here stood the wave-6 switch from v3_0 §7.4: the emergency variant
    // (double signature in the body) belonged on the InfrastructureFrame
    // path, on the application path it was DISCARDED. V4.1 does not have
    // this path: `InfrastructureFrameV3` came about in `CleonaNode`, and the
    // node fell with the CUT;
    // `handleIncomingKeyRotationBroadcastInfra`
    // (`cleona_service_identity.dart:236`) has ZERO callers. The switch
    // thus discarded every emergency rotation without there being a second
    // way on which it could have arrived — a receiver that throws away a
    // message with a pointer to a channel that does not exist.
    //
    // §14.4 PRESCRIBES the pairwise way for V4.1: "How contacts learn
    // of the rotation. Only **pairwise** … A public object is out."
    // The frame arrives here on exactly this way.
    //
    // THE SECURITY CHECK IS NOT LOST THEREBY — it never sat in the path,
    // but in the body: `_handleEmergencyKeyRotation` checks the OLD
    // signature against the contact's stored Ed25519 key and the NEW one
    // against the new key sent along; whoever does not have both gets not
    // one step further. The periodic/emergency distinction is still made
    // by `_handleKeyRotationBroadcast` (`cleona_service_identity.dart`) by
    // the presence of the double signature.
    proto.KeyRotationBroadcast? earlyParse;
    try {
      earlyParse = proto.KeyRotationBroadcast.fromBuffer(event.payload);
    } catch (_) {
      // If the body does not parse the downstream handler will fail in
      // the same way — let it produce its own error log.
    }
    if (earlyParse != null &&
        earlyParse.oldSignatureEd25519.isNotEmpty &&
        earlyParse.newSignatureEd25519.isNotEmpty) {
      _log.info('KEY_ROTATION_BROADCAST: emergency variant received '
          'pairwise (§14.4) '
          '(sender=${_hexShort(Uint8List.fromList(event.senderUserId))} '
          'device=${_hexShort(event.senderDeviceId)})');
    }
    _handleKeyRotationBroadcast(
      Uint8List.fromList(event.payload),
      Uint8List.fromList(event.senderUserId),
    );
  }
  void _handleGroupCreateV3(HarvestEvent event) {
    // GROUP_CREATE shares the GROUP_INVITE payload schema and processing path.
    _handleGroupInviteV3(event);
  }
  void _handleGroupInviteV3(HarvestEvent event) {
    final senderHex = event.senderUserId.hex;

    // V3 payload is already plaintext (decrypted+authenticated by pipeline).
    proto.GroupInviteV3 invite;
    try {
      invite = proto.GroupInviteV3.fromBuffer(event.payload);
    } catch (e) {
      _log.error('GROUP_INVITE parse failed: $e');
      return;
    }

    final groupIdHex = invite.groupId.hex;

    // Build members map
    final members = <String, GroupMemberInfo>{};
    for (final m in invite.members) {
      final nid = m.nodeId.hex;
      members[nid] = GroupMemberInfo(
        nodeIdHex: nid,
        displayName: m.displayName,
        role: m.role,
        ed25519Pk: m.ed25519PublicKey.isEmpty ? null : Uint8List.fromList(m.ed25519PublicKey),
        x25519Pk: m.x25519PublicKey.isEmpty ? null : Uint8List.fromList(m.x25519PublicKey),
        mlKemPk: m.mlKemPublicKey.isEmpty ? null : Uint8List.fromList(m.mlKemPublicKey),
      );
    }

    // Determine owner
    final inviterHex = invite.inviterId.hex;
    final ownerHex = members.values.where((m) => m.role == 'owner').firstOrNull?.nodeIdHex ?? inviterHex;

    final isUpdate = _groups.containsKey(groupIdHex);

    // GM-1 (§9.1.4): authority check for group updates
    int newEpoch;
    if (isUpdate) {
      final oldGroup = _groups[groupIdHex]!;
      final senderMember = oldGroup.members[senderHex];

      if (senderMember == null || (senderMember.role != 'owner' && senderMember.role != 'admin')) {
        _log.warn('GM-1: GROUP_INVITE update from non-admin ${senderHex.substring(0, 8)} '
            'for "${oldGroup.name}" — rejected');
        return;
      }

      final wireEpoch = invite.membershipEpoch.toInt();

      if (wireEpoch > 0 && wireEpoch <= oldGroup.membershipEpoch) {
        _log.warn('GM-1: GROUP_INVITE epoch $wireEpoch <= ${oldGroup.membershipEpoch} '
            'from ${senderHex.substring(0, 8)} — rejected (replay/downgrade)');
        return;
      }

      if (invite.membershipHash.isNotEmpty && invite.membershipSigEd25519.isNotEmpty) {
        final senderEd25519Pk = senderMember.ed25519Pk;
        if (senderEd25519Pk != null && senderEd25519Pk.isNotEmpty) {
          final sigOk = SodiumFFI().verifyEd25519(
              Uint8List.fromList(invite.membershipHash),
              Uint8List.fromList(invite.membershipSigEd25519),
              senderEd25519Pk);
          if (!sigOk) {
            _log.warn('GM-1: GROUP_INVITE Ed25519 sig INVALID from ${senderHex.substring(0, 8)} — rejected');
            return;
          }
        }
        if (invite.membershipSigMlDsa.isNotEmpty) {
          final senderMlDsaPk = _contacts[senderHex]?.mlDsaPk;
          if (senderMlDsaPk != null && senderMlDsaPk.isNotEmpty) {
            final mlDsaOk = OqsFFI().mlDsaVerify(
                Uint8List.fromList(invite.membershipHash),
                Uint8List.fromList(invite.membershipSigMlDsa),
                senderMlDsaPk);
            if (!mlDsaOk) {
              _log.warn('GM-1: GROUP_INVITE ML-DSA sig INVALID from ${senderHex.substring(0, 8)} — rejected');
              return;
            }
          }
        }
        final expectedHash = _computeMembershipHash(wireEpoch, groupIdHex, members);
        if (!constantTimeEquals(Uint8List.fromList(invite.membershipHash), expectedHash)) {
          _log.warn('GM-1: GROUP_INVITE hash mismatch from ${senderHex.substring(0, 8)} — rejected');
          return;
        }
      } else if (wireEpoch == 0) {
        _log.debug('GM-1: GROUP_INVITE without epoch/sig from ${senderHex.substring(0, 8)} — legacy-unverified');
      }

      newEpoch = wireEpoch > 0 ? wireEpoch : oldGroup.membershipEpoch;
    } else {
      newEpoch = invite.membershipEpoch.toInt() > 0
          ? invite.membershipEpoch.toInt()
          : 1;
    }

    final group = GroupInfo(
      groupIdHex: groupIdHex,
      name: invite.groupName,
      description: invite.groupDescription,
      pictureBase64: invite.groupPicture.isNotEmpty ? base64Encode(invite.groupPicture) : null,
      ownerNodeIdHex: ownerHex,
      members: members,
      membershipEpoch: newEpoch,
    );

    _groups[groupIdHex] = group;
    _saveGroups();

    // Create conversation (or update existing)
    final conv = conversations.putIfAbsent(groupIdHex, () => Conversation(
      id: groupIdHex,
      displayName: invite.groupName,
      isGroup: true,
      profilePictureBase64: group.pictureBase64,
    ));
    conv.displayName = invite.groupName;
    _saveConversations();

    if (!isUpdate) {
      onGroupInviteReceived?.call(groupIdHex, invite.groupName);
      _log.info('Group invite received: "${invite.groupName}" from ${senderHex.substring(0, 8)}');
    } else {
      _log.info('Group updated: "${invite.groupName}" from ${senderHex.substring(0, 8)}');
    }

    // Apply any pending config that arrived before the GROUP_INVITE
    final pendingConfig = _pendingGroupConfigs.remove(groupIdHex);
    if (pendingConfig != null) {
      final senderMember = group.members[pendingConfig.senderHex];
      if (senderMember != null && (senderMember.role == 'owner' || senderMember.role == 'admin')) {
        conv.config = pendingConfig.config;
        _saveConversations();
        _log.info('Applied buffered config for "${invite.groupName}" from ${pendingConfig.senderHex.substring(0, 8)}');
      }
    }

    onStateChanged?.call();
  }

  void _handleGroupLeaveV3(HarvestEvent event) {
    final senderHex = event.senderUserId.hex;

    // V3 payload is already plaintext (decrypted+authenticated by pipeline).
    proto.GroupLeave leaveMsg;
    try {
      leaveMsg = proto.GroupLeave.fromBuffer(event.payload);
    } catch (e) {
      _log.error('GROUP_LEAVE parse failed: $e');
      return;
    }

    final groupIdHex = leaveMsg.groupId.hex;
    final group = _groups[groupIdHex];
    if (group == null) return;

    final memberName = group.members[senderHex]?.displayName ?? senderHex.substring(0, 8);
    final wasOwner = group.ownerNodeIdHex == senderHex;
    group.members.remove(senderHex);

    // If the owner left, transfer ownership to first admin or first member
    if (wasOwner && group.members.isNotEmpty) {
      final newOwner = group.members.values.where((m) => m.role == 'admin').firstOrNull
          ?? group.members.values.first;
      newOwner.role = 'owner';
      group.ownerNodeIdHex = newOwner.nodeIdHex;
      // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
      _log.debug('Owner left, transferred to ${newOwner.displayName}');
    }
    _saveGroups();

    // Add system message
    _addSystemMessage(groupIdHex, '$memberName left the group',
        type: UiMessageType.groupLeave, isGroup: true);
    _log.info('$memberName left group "${group.name}"');
  }
  // GROUP_KEY_UPDATE: no shared group key in pairwise-KEM model (§9.1).
  void _handleGroupKeyUpdateV3(HarvestEvent event) {}
  void _handleChannelCreateV3(HarvestEvent event) {
    // CHANNEL_CREATE shares the CHANNEL_INVITE payload schema and processing path.
    _handleChannelInviteV3(event);
  }
  void _handleChannelPostV3(HarvestEvent event) {
    final senderHex = event.senderUserId.hex;

    // Route to channel via groupId field
    final channelIdHex = event.groupId != null
        ? event.groupId!.hex
        : '';
    if (channelIdHex.isEmpty) return;

    final channel = _channels[channelIdHex];
    if (channel == null) {
      _log.warn('CHANNEL_POST for unknown channel $channelIdHex');
      return;
    }

    // Verify sender is owner or admin (post permission)
    final senderMember = channel.members[senderHex];
    if (senderMember == null || (senderMember.role != 'owner' && senderMember.role != 'admin')) {
      _log.warn('CHANNEL_POST from unauthorized sender $senderHex');
      return;
    }

    // GM-4 (§9.1.4): split-view detection on channel posts
    bool isMembershipMismatch = false;
    // `rosterVersion != null` is exactly the previous condition
    // (epoch > 0 AND hash not empty) — the factory sets a value under no
    // other. Both variables live only in this block.
    final roster = event.rosterVersion;
    if (roster != null) {
      final wireEpoch = roster.epoch;
      final wireHash = roster.hash;
      final localEpoch = channel.membershipEpoch;
      final localHash = _computeChannelMembershipHash(
          localEpoch, channelIdHex, channel.members);
      if (wireEpoch == localEpoch && !constantTimeEquals(wireHash, localHash)) {
        // Same epoch, different hash → split-view anomaly
        _log.warn('GM-4: CHANNEL SPLIT-VIEW in "${channel.name}" — '
            'local epoch=$localEpoch, wire epoch=$wireEpoch, hash mismatch '
            'from ${senderHex.substring(0, 8)}');
        isMembershipMismatch = true;
      } else if (wireEpoch > localEpoch) {
        // Sender has newer membership — edge-triggered resync to owner
        final prevRequested = _resyncRequestedAtEpoch[channelIdHex] ?? 0;
        if (wireEpoch > prevRequested) {
          _resyncRequestedAtEpoch[channelIdHex] = wireEpoch;
          _sendChannelResyncRequest(channel);
        }
      } else if (wireEpoch < localEpoch &&
          !constantTimeEquals(wireHash, _computeChannelMembershipHash(
              wireEpoch, channelIdHex, channel.members))) {
        isMembershipMismatch = true;
      }
    }

    // V3 wraps every payload type in its own proto message — CHANNEL_POST is
    // built as a TextMessageV3 by the sender (see _sendChannelPost). This used
    // to be `utf8.decode(event.payload)`, which is the V2 assumption
    // ("V2 packed text as raw UTF-8 in encrypted_payload",
    // proto/app_payloads.proto::TextMessageV3). The old comment said "already
    // plaintext" — true for
    // *decrypted*, false for *unwrapped*. The result was that every channel
    // post rendered as its own protobuf encoding: text="test",
    // format_hint="plain" serialises to 0A 04 t e s t 12 05 p l a i n, which
    // displays as a line break, a box, "test", two boxes, "plain" — exactly
    // what the field screenshot showed. `allowMalformed: true` is why it did
    // that silently instead of throwing.
    final proto.TextMessageV3 tm;
    try {
      tm = proto.TextMessageV3.fromBuffer(event.payload);
    } catch (e) {
      _log.warn('CHANNEL_POST from $senderHex: payload is not a TextMessageV3 '
          '($e) — dropped');
      return;
    }
    final text = tm.text;
    final msgId = event.messageId.hex;

    final msg = UiMessage(
      id: msgId,
      conversationId: channelIdHex,
      senderNodeIdHex: senderHex,
      text: text,
      timestamp: (event.claimedSentAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
      type: UiMessageType.channelPost,
      status: MessageStatus.delivered,
      isOutgoing: false,
      membershipMismatch: isMembershipMismatch,
    );

    _addMessageToConversation(channelIdHex, msg, isChannel: true);
    _log.debug('Channel post received in "${channel.name}" from ${senderMember.displayName}');
  }

  void _handleChannelInviteV3(HarvestEvent event) {
    final senderHex = event.senderUserId.hex;

    // V3 payload is already plaintext (decrypted+authenticated by pipeline).
    proto.ChannelInvite invite;
    try {
      invite = proto.ChannelInvite.fromBuffer(event.payload);
    } catch (e) {
      _log.error('CHANNEL_INVITE parse failed: $e');
      return;
    }

    final channelIdHex = invite.channelId.hex;

    // Build members map from the repeated GroupMemberV3 field
    final members = <String, ChannelMemberInfo>{};
    for (final m in invite.members) {
      final nid = m.nodeId.hex;
      members[nid] = ChannelMemberInfo(
        nodeIdHex: nid,
        displayName: m.displayName,
        role: m.role,
        ed25519Pk: m.ed25519PublicKey.isEmpty ? null : Uint8List.fromList(m.ed25519PublicKey),
        x25519Pk: m.x25519PublicKey.isEmpty ? null : Uint8List.fromList(m.x25519PublicKey),
        mlKemPk: m.mlKemPublicKey.isEmpty ? null : Uint8List.fromList(m.mlKemPublicKey),
      );
    }

    // Determine owner
    final inviterHex = invite.inviterId.hex;
    final ownerHex = members.values.where((m) => m.role == 'owner').firstOrNull?.nodeIdHex ?? inviterHex;

    // GM-4 (§9.1.4): Authority gate for existing channels
    final oldChannel = _channels[channelIdHex];
    final isUpdate = oldChannel != null;
    int newEpoch = 0;

    if (isUpdate) {
      final wireEpoch = invite.membershipEpoch.toInt();

      if (wireEpoch > 0) {
        // Sender must be owner or admin in the OLD state
        final senderOldMember = oldChannel.members[senderHex];
        if (senderOldMember == null ||
            (senderOldMember.role != 'owner' && senderOldMember.role != 'admin')) {
          _log.warn('GM-4: CHANNEL_INVITE from non-admin ${senderHex.substring(0, 8)} '
              'in "${oldChannel.name}" — rejected');
          return;
        }

        // Epoch must be strictly increasing
        if (wireEpoch <= oldChannel.membershipEpoch) {
          _log.warn('GM-4: CHANNEL_INVITE epoch $wireEpoch <= ${oldChannel.membershipEpoch} '
              'in "${oldChannel.name}" — rejected (replay/downgrade)');
          return;
        }

        // Verify hybrid signature over membership hash
        final wireHash = Uint8List.fromList(invite.membershipHash);
        final sigEd = Uint8List.fromList(invite.membershipSigEd25519);
        final sigMl = Uint8List.fromList(invite.membershipSigMlDsa);
        if (wireHash.isNotEmpty && sigEd.isNotEmpty) {
          final senderEd25519Pk = senderOldMember.ed25519Pk;
          if (senderEd25519Pk != null && senderEd25519Pk.isNotEmpty) {
            if (!SodiumFFI().verifyEd25519(wireHash, sigEd, senderEd25519Pk)) {
              _log.warn('GM-4: CHANNEL_INVITE Ed25519 sig invalid from ${senderHex.substring(0, 8)} — rejected');
              return;
            }
          }
          if (sigMl.isNotEmpty) {
            final senderMlDsaPk = _contacts[senderHex]?.mlDsaPk;
            if (senderMlDsaPk != null && senderMlDsaPk.isNotEmpty) {
              if (!OqsFFI().mlDsaVerify(wireHash, sigMl, senderMlDsaPk)) {
                _log.warn('GM-4: CHANNEL_INVITE ML-DSA sig invalid from ${senderHex.substring(0, 8)} — rejected');
                return;
              }
            }
          }
          // Verify hash matches the member list
          final expectedHash = _computeChannelMembershipHash(wireEpoch, channelIdHex, members);
          if (!constantTimeEquals(wireHash, expectedHash)) {
            _log.warn('GM-4: CHANNEL_INVITE hash mismatch — tampered member list? Rejected.');
            return;
          }
        }
        newEpoch = wireEpoch;
      } else {
        // Legacy sender (no epoch) — accept as legacy-unverified
        newEpoch = oldChannel.membershipEpoch;
      }
    } else {
      // New channel — accept with wire epoch
      newEpoch = invite.membershipEpoch.toInt();
      if (newEpoch <= 0) newEpoch = 1;
    }

    final channel = ChannelInfo(
      channelIdHex: channelIdHex,
      name: invite.channelName,
      description: invite.channelDescription.isNotEmpty ? invite.channelDescription : null,
      pictureBase64: invite.channelPicture.isNotEmpty ? base64Encode(invite.channelPicture) : null,
      ownerNodeIdHex: ownerHex,
      members: members,
      isPublic: invite.isPublic,
      isAdult: invite.isAdult,
      language: invite.language.isNotEmpty ? invite.language : 'de',
      membershipEpoch: newEpoch,
    );

    _channels[channelIdHex] = channel;
    _saveChannels();

    // Create conversation (or update existing)
    final conv = conversations.putIfAbsent(channelIdHex, () => Conversation(
      id: channelIdHex,
      displayName: invite.channelName,
      isChannel: true,
      profilePictureBase64: channel.pictureBase64,
    ));
    conv.displayName = invite.channelName;
    _saveConversations();

    if (!isUpdate) {
      onChannelInviteReceived?.call(channelIdHex, invite.channelName);
      _log.info('Channel invite received: "${invite.channelName}" from ${senderHex.substring(0, 8)}');
    } else {
      _log.info('Channel updated: "${invite.channelName}" from ${senderHex.substring(0, 8)}');
    }

    // Apply any pending config that arrived before the CHANNEL_INVITE
    final pendingConfig = _pendingGroupConfigs.remove(channelIdHex);
    if (pendingConfig != null) {
      final senderMember = channel.members[pendingConfig.senderHex];
      if (senderMember != null && (senderMember.role == 'owner' || senderMember.role == 'admin')) {
        conv.config = pendingConfig.config;
        _saveConversations();
        _log.info('Applied buffered config for channel "${invite.channelName}" from ${pendingConfig.senderHex.substring(0, 8)}');
      }
    }

    onStateChanged?.call();
  }

  void _handleChannelLeaveV3(HarvestEvent event) {
    final senderHex = event.senderUserId.hex;

    // V3 payload is already plaintext (decrypted+authenticated by pipeline).
    proto.ChannelLeave leaveMsg;
    try {
      leaveMsg = proto.ChannelLeave.fromBuffer(event.payload);
    } catch (e) {
      _log.error('CHANNEL_LEAVE parse failed: $e');
      return;
    }

    final channelIdHex = leaveMsg.channelId.hex;
    final channel = _channels[channelIdHex];
    if (channel == null) return;

    final memberName = channel.members[senderHex]?.displayName ?? senderHex.substring(0, 8);
    final wasOwner = channel.ownerNodeIdHex == senderHex;
    channel.members.remove(senderHex);

    // If the owner left, transfer ownership
    if (wasOwner && channel.members.isNotEmpty) {
      final newOwner = channel.members.values.where((m) => m.role == 'admin').firstOrNull
          ?? channel.members.values.first;
      newOwner.role = 'owner';
      channel.ownerNodeIdHex = newOwner.nodeIdHex;
      // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
      _log.debug('Channel owner left, transferred to ${newOwner.displayName}');
    }
    _saveChannels();

    // Add system message
    _addSystemMessage(channelIdHex, '$memberName left the channel',
        type: UiMessageType.channelLeave, isChannel: true);
    _log.info('$memberName left channel "${channel.name}"');
  }

  /// Handle CHANNEL_ROLE_UPDATE (type 73): update member role in channel or group.
  /// Architecture v3.0 Section 10.2: sent to ALL members, handler checks both
  /// channelManager and groupManager. Only owner/admin may change roles.
  void _handleChannelRoleUpdateV3(HarvestEvent event) {
    final senderHex = event.senderUserId.hex;

    // V3 payload is already plaintext (decrypted+authenticated by pipeline).
    proto.ChannelRoleUpdate roleMsg;
    try {
      roleMsg = proto.ChannelRoleUpdate.fromBuffer(event.payload);
    } catch (e) {
      _log.error('CHANNEL_ROLE_UPDATE parse failed: $e');
      return;
    }

    final entityIdHex = roleMsg.channelId.hex;
    final targetIdHex = roleMsg.targetId.hex;
    final newRole = roleMsg.newRole;

    // Check both channels and groups (Architecture v3.0: dual-mode handler)
    final channel = _channels[entityIdHex];
    final group = _groups[entityIdHex];

    if (channel != null) {
      // Verify sender is owner — only Owner can change roles (Architecture §10.2).
      final senderMember = channel.members[senderHex];
      if (senderMember == null || senderMember.role != 'owner') {
        _log.warn('CHANNEL_ROLE_UPDATE rejected: $senderHex is not owner in channel $entityIdHex');
        return;
      }

      final target = channel.members[targetIdHex];
      if (target == null) {
        _log.warn('CHANNEL_ROLE_UPDATE: target $targetIdHex not a member of channel $entityIdHex');
        return;
      }

      final oldRole = target.role;
      target.role = newRole;

      // Handle ownership transfer
      if (newRole == 'owner') {
        // Demote previous owner to admin
        final prevOwner = channel.members[channel.ownerNodeIdHex];
        if (prevOwner != null) prevOwner.role = 'admin';
        channel.ownerNodeIdHex = targetIdHex;
      }

      channel.membershipEpoch++;
      _saveChannels();

      _addSystemMessage(entityIdHex, '${target.displayName}: $oldRole → $newRole',
          type: UiMessageType.channelRoleUpdate, isChannel: true);
      // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
      _log.debug('Channel role update: ${target.displayName} $oldRole → $newRole in "${channel.name}"');

    } else if (group != null) {
      // Verify sender is owner — only Owner can change roles (Architecture §10.2).
      final senderMember = group.members[senderHex];
      if (senderMember == null || senderMember.role != 'owner') {
        _log.warn('CHANNEL_ROLE_UPDATE rejected: $senderHex is not owner in group $entityIdHex');
        return;
      }

      final target = group.members[targetIdHex];
      if (target == null) {
        _log.warn('CHANNEL_ROLE_UPDATE: target $targetIdHex not a member of group $entityIdHex');
        return;
      }

      final oldRole = target.role;
      target.role = newRole;

      if (newRole == 'owner') {
        final prevOwner = group.members[group.ownerNodeIdHex];
        if (prevOwner != null) prevOwner.role = 'admin';
        group.ownerNodeIdHex = targetIdHex;
      }

      group.membershipEpoch++;
      _saveGroups();

      _addSystemMessage(entityIdHex, '${target.displayName}: $oldRole → $newRole',
          type: UiMessageType.channelRoleUpdate);
      // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
      _log.debug('Group role update: ${target.displayName} $oldRole → $newRole in "${group.name}"');

    } else {
      _log.debug('CHANNEL_ROLE_UPDATE: entity $entityIdHex not found (not a member)');
    }

    onStateChanged?.call();
  }
  // Wave 2B.3: PEER_LIST_*, DHT_*, FRAGMENT_*, PEER_STORE_* dead-stub
  // declarations removed. PEER_LIST_*/DHT_* are §2.3.5 Infrastructure types
  // dispatched in cleona_node.dart's `_dispatchInfrastructureFrameLocal`.
  // FRAGMENT_*/PEER_STORE_* are dispatched via the service-layer Infra hook
  // (service_daemon.dart `node.onInfrastructureFramePayload`) into
  // `handleIncomingFragmentStoreInfra` etc.
  void _handleChatConfigUpdateV3(HarvestEvent event) {
    // V3 direct: the inner payload is the ChatConfigUpdate protobuf,
    // already decrypted + authenticated by the V3 pipeline.
    final senderHex = event.senderUserId.hex;

    proto.ChatConfigUpdate configMsg;
    try {
      configMsg = proto.ChatConfigUpdate.fromBuffer(event.payload);
    } catch (e) {
      _log.error('CHAT_CONFIG_UPDATE parse failed: $e');
      return;
    }

    final newConfig = ChatConfig(
      allowDownloads: configMsg.allowDownloads,
      allowForwarding: configMsg.allowForwarding,
      editWindowMs: configMsg.hasEditWindowMs() ? configMsg.editWindowMs.toInt() : null,
      expiryDurationMs: configMsg.hasExpiryDurationMs() ? configMsg.expiryDurationMs.toInt() : null,
      readReceipts: configMsg.readReceipts,
      typingIndicators: configMsg.typingIndicators,
    );

    // Check if this is a group config update
    final groupIdHex = event.groupId?.hex;

    if (groupIdHex != null) {
      // Group or channel config: apply directly (sender must be owner or admin)
      final group = _groups[groupIdHex];
      final channel = _channels[groupIdHex];
      if (group != null) {
        final senderMember = group.members[senderHex];
        if (senderMember == null) return;
        if (senderMember.role != 'owner' && senderMember.role != 'admin') {
          _log.warn('Group config rejected: ${senderHex.substring(0, 8)} is ${senderMember.role}');
          return;
        }
        final conv = conversations[groupIdHex];
        if (conv != null) {
          conv.config = newConfig;
          _saveConversations();
        }
        onStateChanged?.call();
        _log.debug('Group config — displayName="${senderMember.displayName}"');
        _log.info('Group config updated for "${group.name}"');
        return;
      }
      if (channel != null) {
        final senderMember = channel.members[senderHex];
        if (senderMember == null) return;
        if (senderMember.role != 'owner' && senderMember.role != 'admin') {
          _log.warn('Channel config rejected: ${senderHex.substring(0, 8)} is ${senderMember.role}');
          return;
        }
        final conv = conversations[groupIdHex];
        if (conv != null) {
          conv.config = newConfig;
          _saveConversations();
        }
        onStateChanged?.call();
        _log.debug('Channel config — '
            'displayName="${senderMember.displayName}"');
        _log.info('Channel config updated for "${channel.name}"');
        return;
      }
      // Unknown group/channel — buffer config for when GROUP_INVITE arrives
      _pendingGroupConfigs[groupIdHex] = (config: newConfig, senderHex: senderHex);
      _log.info('Buffered config for unknown group/channel ${groupIdHex.substring(0, 8)} from ${senderHex.substring(0, 8)}');
      return;
    }

    // DM config: handle proposal/response
    if (configMsg.isRequest) {
      // Peer proposes new config — store as pending, do NOT apply yet
      final conv = conversations[senderHex] ?? conversations.putIfAbsent(
        senderHex,
        () => Conversation(id: senderHex, displayName: _contacts[senderHex]?.displayName ?? ''),
      );
      conv.pendingConfigProposal = newConfig;
      conv.pendingConfigProposer = senderHex;
      conv.unreadCount++;
      _updateBadgeCount();
      _saveConversations();
      onStateChanged?.call();
      _log.debug('DM config received — '
          'displayName="${_contacts[senderHex]?.displayName}"');
      _log.info('DM config proposal received from '
          '${senderHex.substring(0, 8)} — awaiting accept/reject');
    } else if (configMsg.accepted) {
      // Peer accepted our proposal — NOW apply the config on our side
      final conv = conversations[senderHex];
      if (conv != null && conv.pendingConfigProposal != null) {
        conv.config = conv.pendingConfigProposal!;
        conv.pendingConfigProposal = null;
        conv.pendingConfigProposer = null;
        _saveConversations();
      }
      onStateChanged?.call();
      _log.info('DM config accepted by ${senderHex.substring(0, 8)}');
    } else {
      // Peer rejected our proposal — clear pending
      final conv = conversations[senderHex];
      if (conv != null) {
        conv.pendingConfigProposal = null;
        conv.pendingConfigProposer = null;
        _saveConversations();
      }
      onStateChanged?.call();
      _log.info('DM config rejected by ${senderHex.substring(0, 8)}');
    }
  }
  // CHAT_CONFIG_RESPONSE (type 141): dead code — the protocol uses
  // CHAT_CONFIG_UPDATE (type 140) with `accepted` flag for both request
  // and response directions. Type 141 is never sent.
  void _handleChatConfigResponseV3(HarvestEvent event) {}

  // Wave 2B.3: ROUTE_UPDATE, REACHABILITY_*, RELAY_*, HOLE_PUNCH_*
  // dead-stub declarations removed — all dispatched in cleona_node.dart
  // (`_dispatchInfrastructureFrameLocal`, see Wave 2B.3 section). RELAY_*
  // remains on the KEM-path with §5.5 logic (out of Wave 2B.3 scope).

  // IDENTITY_AUTH/LIVE_* (types 170-175): here stood six empty handlers
  // ("kept only for switch-case exhaustiveness"; the reference to
  // `cleona_node.dart` pointed to a file that does not exist on this
  // line). Removed for lack of a sender (S388-BAU-KONTAKT); the switch has
  // a `default`.
  void _handleTwinSyncV3(HarvestEvent event) {
    // The inner payload is the TwinSyncEnvelope protobuf, already
    // decrypted + authenticated by the V3 pipeline. Sub-handlers operate
    // on raw payload bytes.
    try {
      final sync = proto.TwinSyncEnvelope.fromBuffer(event.payload);
      final syncIdHex = sync.syncId.hex;
      final deviceIdHex = sync.deviceId.hex;

      // Deduplication: syncId seen within 7-day TTL window → silent drop.
      if (_processedSyncIds.containsKey(syncIdHex)) return;
      _processedSyncIds[syncIdHex] = DateTime.now().millisecondsSinceEpoch;

      // Update device lastSeen
      if (_devices.containsKey(deviceIdHex)) {
        _devices[deviceIdHex]!.lastSeen = DateTime.now();
      }

      // ── AN UNKNOWN TYPE IS SKIPPED, NOT REINTERPRETED ──────
      //
      // MEASURED, not assumed (2026-08-30, probe against protobuf 4.2.0,
      // `lib/src/protobuf/coded_buffer.dart:74-83`): an enum value that this
      // version does not know lands in `unknownFields` — and the FIELD
      // STAYS UNSET. The generated getter then returns the zero value of
      // the enum, and here that is called `CONTACT_ADDED`:
      //
      //     syncType (getter)        = CONTACT_ADDED
      //     syncType.value           = 0
      //     unknownFields[4] varints = [17]
      //     DISPATCH -> case CONTACT_ADDED (i.e. NOT skipped)
      //
      // Without this gate EVERY future wire extension of the enum would
      // thus be interpreted as CONTACT_ADDED on an older version and its
      // payload read as contact JSON. That does not crash
      // (`_handleTwinContactAdded` catches itself), but "not crashing" is
      // not the same as "skipping": the frame is executed, just with the
      // wrong handler.
      //
      // `hasSyncType()` is NOT suitable as a distinction: proto3 does not
      // serialise the zero value at all, so a real `CONTACT_ADDED` also
      // arrives with `hasSyncType() == false` (measured). The only place
      // where the unknown value still stands at all is `unknownFields`
      // under the field number of `sync_type`.
      if (twinSyncTypeIsUnknown(sync)) {
        final raw = rawUnknownTwinSyncType(sync);
        _log.debug('TWIN_SYNC: unknown type (roh=$raw) from device '
            '${deviceIdHex.substring(0, 8)} — skipped');
        _saveDevices(); // keep the dedup identifier anyway
        return;
      }

      _log.debug('TWIN_SYNC(${sync.syncType}) from device ${deviceIdHex.substring(0, 8)}');

      switch (sync.syncType) {
        case proto.TwinSyncType.CONTACT_ADDED:
          _handleTwinContactAdded(sync.payload);
          break;
        case proto.TwinSyncType.CONTACT_DELETED:
          _handleTwinContactDeleted(sync.payload);
          break;
        case proto.TwinSyncType.MESSAGE_SENT:
          _handleTwinMessageSent(sync.payload);
          break;
        case proto.TwinSyncType.MESSAGE_EDITED:
          _handleTwinMessageEdited(sync.payload);
          break;
        case proto.TwinSyncType.MESSAGE_DELETED:
          _handleTwinMessageDeleted(sync.payload);
          break;
        case proto.TwinSyncType.TWIN_READ_RECEIPT:
          _handleTwinReadReceipt(sync.payload);
          break;
        case proto.TwinSyncType.GROUP_CREATED:
          _handleTwinGroupCreated(sync.payload);
          break;
        case proto.TwinSyncType.PROFILE_CHANGED:
          _handleTwinProfileChanged(sync.payload);
          break;
        case proto.TwinSyncType.SETTINGS_CHANGED:
          _handleTwinSettingsChanged(sync.payload);
          break;
        case proto.TwinSyncType.DEVICE_RENAMED:
          _handleTwinDeviceRenamed(sync.payload);
          break;
        case proto.TwinSyncType.TWIN_DEVICE_REVOKED:
          _handleTwinDeviceRevoked(sync.payload);
          break;
        case proto.TwinSyncType.DEVICE_ANNOUNCE:
          // §26 Multi-Device: V3 carries TWIN_ANNOUNCE as TWIN_SYNC sub-type.
          // sync.payload is the inner DeviceRecord proto.
          //
          // Reciprocal-announce only on the new-device branch — sending it on
          // every announce creates an A→B→A→B amplification loop because
          // each side keeps updating lastSeen and re-announcing.
          // Convergence in two rounds: A announces, B registers + reciprocates,
          // A receives B's announce, A registers (new for A), A reciprocates
          // once more, B updates lastSeen and stops.
          try {
            final record = proto.DeviceRecord.fromBuffer(sync.payload);
            final announcedHex = record.deviceId.hex;
            if (announcedHex == _localDeviceId) break; // ignore self-loop

            final devNodeIdHex = record.deviceNodeId.isNotEmpty
                ? record.deviceNodeId.hex
                : null;

            final now = DateTime.now();
            final isNew = !_devices.containsKey(announcedHex);
            if (isNew) {
              // Collapse any node-id-keyed bootstrap record for the same
              // physical device into this canonical UUID-keyed one. Pairing
              // creates such records on both sides before either device knows
              // the other's UUID (`_addDeviceDelegation` on the Primary,
              // `_handleDevicePairApproveV3` on the linked device); leaving
              // them next to the announced record would list one device twice
              // and send every twin frame to the same node twice.
              if (devNodeIdHex != null) {
                _devices.removeWhere((k, v) =>
                    k != announcedHex &&
                    !v.isThisDevice &&
                    v.deviceNodeIdHex == devNodeIdHex);
              }
              _devices[announcedHex] = DeviceRecord(
                deviceId: announcedHex,
                deviceName: record.deviceName,
                platform: _detectPlatformFromProto(record.platform),
                firstSeen: now,
                lastSeen: now,
                deviceNodeIdHex: devNodeIdHex,
              );
              _log.info('New twin device registered: $announcedHex (${record.deviceName})');
              // §7 (Einleitung): `_devices` is the authorised-device source,
              // so a device that enters it here must reach the manifest too —
              // and immediately, not at the next unrelated device event.
              // Only a frame authenticating as this very UserID reaches this
              // branch (TWIN_SYNC is verified upstream against the User key or
              // an authorised delegate's key), and `sendToUser`'s §7.2 self
              // fan-out already routes to the record, so publishing it states
              // what the service already treats as true.
              _syncAuthorizedDevicesToPublisher();
            } else {
              _devices[announcedHex]!.lastSeen = now;
              _devices[announcedHex]!.deviceName = record.deviceName;
              if (devNodeIdHex != null) {
                _devices[announcedHex]!.deviceNodeIdHex = devNodeIdHex;
              }
            }
            _notifyDevicesChanged();
            if (isNew) _sendTwinAnnounce();
          } catch (e) {
            _log.error('DEVICE_ANNOUNCE processing failed: $e');
          }
          break;
        // §7.5 co-authorization is a DEVICE procedure, not an identity
        // procedure — unlike the rest of §14 the device identifier is not
        // an accessory here, but the subject:
        //   * the request is parked under `requestingDeviceId` and the
        //     approval is later sent back with `targetDeviceId: pending
        //     .requestingDeviceId` EXACTLY to this device
        //     (`approveRotation`, :11290),
        //   * the answer counts against the quorum `max(2, ceil(N/2))` over
        //     the set of known devices.
        // Without an identifier there is neither a target for the answer
        // nor a subject for the count. NOTHING is therefore invented and
        // nothing half executed: the frame is discarded and the reason
        // logged. Until §7 has been brought over to the V4.1 line,
        // co-authorization only runs via V3 frames — that is a known,
        // named backlog, not a silent failure.
        case proto.TwinSyncType.ROTATION_APPROVAL_REQUEST:
          {
            final requestingDevice = event.senderDeviceId;
            if (requestingDevice == null) {
              _log.warn('§7.5 ROTATION_APPROVAL_REQUEST without device identifier '
                  '(delivery without device layer, §14.2) — discarded: the '
                  'approval would not be addressable to any device');
              break;
            }
            _handleRotationApprovalRequest(sync.payload, requestingDevice);
          }
          break;
        case proto.TwinSyncType.ROTATION_APPROVAL_RESPONSE:
          {
            final respondingDevice = event.senderDeviceId;
            if (respondingDevice == null) {
              _log.warn('§7.5 ROTATION_APPROVAL_RESPONSE without device identifier '
                  '(delivery without device layer, §14.2) — discarded: an '
                  'approval without a nameable device counts toward no '
                  'quorum');
              break;
            }
            _handleRotationApprovalResponse(sync.payload, respondingDevice);
          }
          break;
        case proto.TwinSyncType.TWIN_IDENTITY_DELETED:
          _handleTwinIdentityDeleted(sync.payload);
          break;
        default:
          _log.debug('Unhandled TWIN_SYNC type: ${sync.syncType}');
      }
      _saveDevices(); // Persist dedup IDs
    } catch (e) {
      _log.error('TWIN_SYNC processing failed: $e');
    }
  }

  // §7.5: Co-Auth — collect approval tokens from linked devices during rotation.
  Completer<void>? _rotationApprovalCompleter;
  final List<RotationApprovalToken> _collectedApprovalTokens = [];
  Uint8List? _pendingRotationHash;

  /// §7.5: the device-set change currently being co-authorized, if any.
  ///
  /// Deliberately separate state from the key-rotation collection above,
  /// although both travel the same wire channel: the two hashes cover
  /// different things, and a shared bucket would let a token collected for one
  /// occasion be counted towards the other. `_handleRotationApprovalResponse`
  /// routes each token by the hash it actually signed.
  ///
  /// Memory-only and single-slot. A second removal started while one is in
  /// flight replaces it — the older change is then published without a proof
  /// rather than with a stale one.
  _PendingDeviceSetChange? _pendingDeviceSetChange;

  /// §7.5 co-authorization: rotation-approval requests on this Linked Device
  /// that are waiting for an EXPLICIT user decision. Memory-only and
  /// deliberately not persisted — a request that survives a daemon restart
  /// would be a request nobody is watching any more.
  final Map<String, _PendingRotationApproval> _pendingRotationApprovals = {};

  /// §7.5: how long the *Primary* waits for approvals in
  /// [rotateIdentityKeysEmergency] before it gives up on the quorum.
  static const Duration _rotationApprovalWaitWindow = Duration(minutes: 5);

  /// §7.5: grace added on the Linked Device on top of the Primary's wait
  /// window, covering the one-way trip of the response frame.
  static const Duration _rotationApprovalTtlGrace = Duration(minutes: 2);

  /// §7.5: how long a pending rotation-approval request stays answerable on
  /// this Linked Device. After that it is dropped and NOTHING is sent — see
  /// below.
  ///
  /// DERIVED, NOT CHOSEN — and that is the point. The TTL used to be a second
  /// hardcoded `Duration(minutes: 5)`, numerically identical to the Primary's
  /// wait window. That made the two windows close at the same instant: a user
  /// who tapped "approve" at 4:50 produced a perfectly valid countersignature
  /// that the Primary was no longer listening for, so the quorum failed even
  /// though the human had consented. The LD window must therefore *outlive*
  /// the Primary's, never merely match it.
  ///
  /// Keeping the TTL an expression of [_rotationApprovalWaitWindow] means the
  /// next change to the Primary's timeout drags this one along instead of
  /// silently re-opening the same gap. Do not replace this with a literal.
  ///
  /// Enlarging the LD side is the safe direction: a response that arrives
  /// after the Primary stopped waiting is merely ignored (the completer is
  /// null by then), whereas a response that is never produced is a lost
  /// approval. The reverse — an LD window shorter than the Primary's — has no
  /// upside at all.
  /// (`static final`, not `static const`: `Duration.+` is not a const
  /// operator, and a const literal here would be exactly the duplicated
  /// number this comment exists to prevent.)
  static final Duration _rotationApprovalTtl =
      _rotationApprovalWaitWindow + _rotationApprovalTtlGrace;

  /// §7.5: Linked Device receives ROTATION_APPROVAL_REQUEST from the Primary.
  ///
  /// Two occasions share this channel — an Emergency Key Rotation and a
  /// device-set change (§7.5 shrink proof). `approval_kind` says which, and
  /// it is passed on unmodified to [onRotationApprovalRequest] and
  /// [getPendingRotationApprovals]. That is not cosmetic: the
  /// countersignature is byte-identical for both, so a dialog that cannot
  /// distinguish them collects a valid signature for a question the user was
  /// never shown — consent under a false description.
  ///
  /// SECURITY — this handler deliberately does NOT sign.
  ///
  /// §7.5 exists because "a seed thief cannot forge Device-Sig
  /// countersignatures", and it is the *receiving contact* that enforces the
  /// quorum. That guarantee is worth exactly nothing if every Linked Device
  /// countersigns automatically: whoever steals the Primary and triggers an
  /// Emergency Key Rotation would collect the full quorum on his own, and the
  /// contact would read `quorumMet` as "legitimate rotation" — the mechanism
  /// would deliver the opposite of its intended signal in the theft case it
  /// was built for.
  ///
  /// The request is therefore parked and handed to the UI via
  /// [onRotationApprovalRequest]. Only [approveRotation] signs; only
  /// [rejectRotation] answers with `rejected=true` (§7.5 point 5).
  ///
  /// TIMEOUT SEMANTICS (the security-bearing decision here): when the TTL
  /// elapses without a user decision, the entry is dropped and NOTHING is
  /// sent — neither approval nor rejection. Silence must never count as
  /// consent. If a timeout auto-approved, a powered-off Linked Device would
  /// be equivalent to a consenting one and the quorum would be worthless
  /// again. If it auto-rejected, every offline device would raise a theft
  /// alarm on a legitimate rotation. Not answering is the only correct
  /// answer: the Primary simply never reaches the quorum, and the contact
  /// side surfaces that via `onRotationCoAuthWarning`.
  ///
  /// NOTE (state of the wiring): the UI counterpart is not built yet, so
  /// today no approval can come about at all. That is the intentionally safe
  /// side (fail-closed rather than fail-open) — but until the UI is wired,
  /// Emergency Key Rotation reaches no quorum any more.
  void _handleRotationApprovalRequest(List<int> payload, Uint8List senderDeviceId) {
    try {
      final req = proto.RotationApprovalRequestPayload.fromBuffer(payload);
      final rotationHash = Uint8List.fromList(req.rotationHash);
      if (rotationHash.isEmpty) {
        _log.warn('§7.5 ROTATION_APPROVAL_REQUEST without rotationHash — dropped');
        return;
      }
      final hashHex = bytesToHex(rotationHash);
      if (_pendingRotationApprovals.containsKey(hashHex)) {
        // Re-broadcast of the same request (twin fan-out / retry): keep the
        // original TTL, do not prompt the user twice for one rotation.
        _log.debug('§7.5 ROTATION_APPROVAL_REQUEST ${hashHex.substring(0, 8)} '
            'already pending — not re-prompting');
        return;
      }

      // §7.5 (P4): the occasion. A sender that predates the field leaves it at
      // the proto default 0 = APPROVAL_KIND_KEY_ROTATION, which is what such a
      // sender always meant — no legacy request changes meaning here.
      final kind =
          req.approvalKind == proto.ApprovalKindV3.APPROVAL_KIND_DEVICE_SET_CHANGE
              ? RotationApprovalKind.deviceSetChange
              : RotationApprovalKind.keyRotation;
      final newDeviceIds = req.newDeviceNodeIds
          .map((b) => Uint8List.fromList(b))
          .where((b) => b.isNotEmpty)
          .toList();

      final expiryTimer = Timer(_rotationApprovalTtl, () {
        if (_pendingRotationApprovals.remove(hashHex) != null) {
          _log.warn('§7.5 rotation approval ${hashHex.substring(0, 8)} expired '
              'after ${_rotationApprovalTtl.inMinutes} min without a user '
              'decision — nothing sent (silence is not consent)');
        }
      });
      _pendingRotationApprovals[hashHex] = _PendingRotationApproval(
        rotationHash: rotationHash,
        requestingDeviceId: Uint8List.fromList(senderDeviceId),
        receivedAtMs: DateTime.now().millisecondsSinceEpoch,
        expiryTimer: expiryTimer,
        kind: kind,
        newDeviceNodeIds: newDeviceIds,
      );
      _log.info('§7.5 ROTATION_APPROVAL_REQUEST ${hashHex.substring(0, 8)} '
          'kind=${kind.wireName} parked for explicit user decision (TTL '
          '${_rotationApprovalTtl.inMinutes} min) — NOT auto-signed');

      try {
        onRotationApprovalRequest?.call(hashHex, bytesToHex(senderDeviceId),
            kind, newDeviceIds.map(bytesToHex).toList());
      } catch (e) {
        _log.warn('onRotationApprovalRequest listener threw: $e');
      }
    } catch (e) {
      _log.error('§7.5 ROTATION_APPROVAL_REQUEST handling failed: $e');
    }
  }

  /// §7.5: the user explicitly approved the rotation on this Linked Device.
  /// Only here is the Device-Sig countersignature created.
  /// Returns false when the hash is unknown or its TTL already elapsed.
  @override
  Future<bool> approveRotation(String rotationHashHex) async {
    final pending = _pendingRotationApprovals.remove(rotationHashHex);
    if (pending == null) {
      _log.warn('§7.5 approveRotation: no pending request for '
          '$rotationHashHex (unknown or expired)');
      return false;
    }
    pending.expiryTimer.cancel();
    // Gap G-9: the co-signature is made with the DEVICE key, and that has
    // no holder any more (see [deviceX25519Pk]). Without it this device
    // cannot approve — and an approval with the identity key would not be
    // one: §7.5 rests precisely on the device key NOT being derived from
    // the seed. Whoever stole the seed could otherwise co-sign.
    _log.error('§7.5 approveRotation: not possible — the '
        'device key has no holder in V4.1 (gap G-9). '
        'The request $rotationHashHex stays unanswered.');
    return false;
  }

  /// §7.5 point 5: the user explicitly rejected the rotation on this Linked
  /// Device. Answers `rejected=true` and raises the theft alarm with the
  /// contacts directly.
  /// Returns false when the hash is unknown or its TTL already elapsed.
  @override
  Future<bool> rejectRotation(String rotationHashHex) async {
    final pending = _pendingRotationApprovals.remove(rotationHashHex);
    if (pending == null) {
      _log.warn('§7.5 rejectRotation: no pending request for '
          '$rotationHashHex (unknown or expired)');
      return false;
    }
    pending.expiryTimer.cancel();
    try {
      final response = proto.RotationApprovalResponsePayload()..rejected = true;
      // Same reasoning as in `approveRotation`: only the requesting Primary
      // can act on this. The contacts are informed separately below — that
      // path deliberately does NOT go through the Primary.
      _sendTwinSync(proto.TwinSyncType.ROTATION_APPROVAL_RESPONSE,
          Uint8List.fromList(response.writeToBuffer()),
          targetDeviceId: pending.requestingDeviceId);

      // §7.5: the alert goes DIRECTLY to the contacts, bypassing the Primary
      // — which is exactly the device under suspicion. `_pendingRotationHash`
      // is a Primary-side field and is null on this device, so the hash is
      // passed explicitly; otherwise the alert would be signed over empty
      // bytes and could not be matched to the rotation.
      _sendRotationRejectionAlert(identity.deviceNodeId,
          rotationHash: pending.rotationHash);

      _log.warn('§7.5 ROTATION_APPROVAL_RESPONSE sent (REJECTED by user) for '
          '${rotationHashHex.substring(0, 8)} + ROTATION_REJECTION_ALERT to '
          'contacts');
      return true;
    } catch (e) {
      _log.error('§7.5 rejectRotation failed: $e');
      return false;
    }
  }

  /// §7.5: catch-up for [onRotationApprovalRequest] — see the interface doc
  /// for the field contract.
  ///
  /// The event fires exactly once, when the request arrives. A GUI that
  /// starts (or reconnects) afterwards would otherwise never learn about a
  /// parked request, and it would expire unanswered — the user is never asked
  /// and the Primary's rotation silently fails the quorum. Reading the map is
  /// the only way to close that window; the parked entries are memory-only by
  /// design, so nothing else could reconstruct them.
  ///
  /// Expired-but-not-yet-collected entries are filtered out rather than
  /// returned with a past `expiresAtMs`: the expiry timer and this call are
  /// not ordered against each other, and handing the UI a request that
  /// [approveRotation] is about to reject as unknown would be a prompt the
  /// user cannot answer.
  @override
  Future<List<Map<String, dynamic>>> getPendingRotationApprovals() async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final ttlMs = _rotationApprovalTtl.inMilliseconds;
    final out = <Map<String, dynamic>>[];
    for (final entry in _pendingRotationApprovals.entries) {
      final expiresAtMs = entry.value.receivedAtMs + ttlMs;
      if (expiresAtMs <= nowMs) continue;
      out.add({
        'rotationHashHex': entry.key,
        'requestingDeviceIdHex': bytesToHex(entry.value.requestingDeviceId),
        // §7.5 (P4): the catch-up path carries the occasion for the same
        // reason the live event does — a dialog rebuilt from this map must
        // not label a device-set change as a key rotation.
        'approvalKind': entry.value.kind.wireName,
        'newDeviceNodeIdHexes':
            entry.value.newDeviceNodeIds.map(bytesToHex).toList(),
        'receivedAtMs': entry.value.receivedAtMs,
        'expiresAtMs': expiresAtMs,
      });
    }
    out.sort((a, b) =>
        (a['receivedAtMs'] as int).compareTo(b['receivedAtMs'] as int));
    return out;
  }

  /// §7.5: Primary receives ROTATION_APPROVAL_RESPONSE from a Linked Device.
  ///
  /// Two collections can be outstanding on this channel — an Emergency Key
  /// Rotation and a device-set change. An approval is routed by the hash it
  /// actually signed, never by which collection happens to be open: a token
  /// signed over a rotation hash must not be able to satisfy a device-set
  /// quorum, or vice versa.
  void _handleRotationApprovalResponse(List<int> payload, Uint8List senderDeviceId) {
    try {
      final resp = proto.RotationApprovalResponsePayload.fromBuffer(payload);
      final senderHex = bytesToHex(senderDeviceId);
      final pendingChange = _pendingDeviceSetChange;

      // Device-set change approvals: the token must cover exactly the change
      // hash being collected for. `_PendingDeviceSetChange.add` de-duplicates
      // by device, so answering twice does not count twice.
      if (!resp.rejected &&
          resp.hasToken() &&
          pendingChange != null &&
          resp.token.rotationHash.hex ==
              pendingChange.changeHashHex) {
        final isNew =
            pendingChange.add(RotationApprovalToken.fromProto(resp.token));
        _log.info('§7.5 device-set change approval from '
            '${senderHex.substring(0, 8)} '
            '(${isNew ? "new" : "duplicate, ignored"}) — '
            '${pendingChange.approvers.length}/'
            '${pendingChange.requiredApprovers}');
        return;
      }

      if (_pendingRotationHash == null) {
        if (resp.rejected && pendingChange != null) {
          // A Linked Device refuses to co-sign the device-set change. Nothing
          // is forged and nothing is aborted: the bucket simply stays below
          // the quorum, so the manifest publishes without a proof and the
          // contacts raise the §7.5 warning — a rejection must be at least as
          // strong a signal as silence.
          _log.warn('§7.5 device ${senderHex.substring(0, 8)} REJECTED the '
              'device-set change — no proof will be attached');
          return;
        }
        _log.warn('§7.5 ROTATION_APPROVAL_RESPONSE received but no rotation pending');
        return;
      }
      if (resp.rejected) {
        // NOTE — this relayed alert is expected to be DROPPED by every
        // up-to-date receiver, and that is correct, not a regression.
        //
        // `_sendRotationRejectionAlert` signs with THIS device's key
        // (`node.deviceKeyPair`) while stamping the *rejecting* device's id
        // into `deviceNodeId`. The two do not match, so the receiver-side
        // check in `_handleRotationRejectionAlertV3` verifies the Primary's
        // signature against the Linked Device's published pubkey and fails.
        // It cannot be fixed here: the Primary does not hold the Linked
        // Device's Device-Sig secret — that is precisely the §7.5 property
        // that makes co-authorization worth anything.
        //
        // Nothing is lost. The rejecting device already sent its own,
        // correctly self-signed alert straight to the contacts from
        // `rejectRotation`, deliberately bypassing this device. That is the
        // authoritative path, because this device is the one under suspicion
        // — a theft alarm relayed by the suspect was never a trustworthy
        // signal to begin with. The send is kept as a no-op rather than
        // removed so the log below still records what the Primary saw.
        _log.warn('§7.5 Device ${senderHex.substring(0, 8)} REJECTED rotation — '
            'sending ROTATION_REJECTION_ALERT to contacts');
        _sendRotationRejectionAlert(senderDeviceId);
        return;
      }
      if (!resp.hasToken()) {
        _log.warn('§7.5 ROTATION_APPROVAL_RESPONSE without token from '
            '${senderHex.substring(0, 8)} — skipped');
        return;
      }
      _collectedApprovalTokens.add(RotationApprovalToken.fromProto(resp.token));
      _log.info('§7.5 Collected approval ${_collectedApprovalTokens.length} '
          'from ${senderHex.substring(0, 8)}');

      // FORMERLY the device count came from `_identityPublisher.delegations`.
      // Without a publisher `_devices` is the only set this device keeps
      // about its twins — it is not the same (it also counts legacy twins
      // without delegation), but it is the only measured number instead of
      // a guessed one. Gap G-9.
      final totalDevices = _devices.isEmpty ? 1 : _devices.length;
      final required = rotationQuorum(totalDevices);
      if (_collectedApprovalTokens.length + 1 >= required) {
        _rotationApprovalCompleter?.complete();
      }
    } catch (e) {
      _log.error('§7.5 ROTATION_APPROVAL_RESPONSE handling failed: $e');
    }
  }

  /// §7.5: A Linked Device actively rejects the rotation — sends alert
  /// DIRECTLY to all contacts (bypassing Primary, which may be compromised).
  /// [rotationHash] must be passed when this is called on the *rejecting*
  /// Linked Device — `_pendingRotationHash` only exists on the Primary that
  /// started the rotation.
  void _sendRotationRejectionAlert(Uint8List rejectingDeviceId,
      {Uint8List? rotationHash}) {
    // Gap G-9 — the same cause as in [approveRotation]: the rejection is a
    // SIGNED statement of the device, and the key for it has no holder.
    // An unsigned rejection would be worthless (the receiver discards it,
    // see `_handleRotationRejectionAlertV3`).
    _log.error('§7.5: rejection of the rotation cannot be issued '
        '— no holder for the device key (gap G-9). The '
        'contacts learn NOTHING of the rejection.');
    return;
  }

  // §7.1 LD-2: Pending pair requests awaiting user approval on this (Primary) device.
  final Map<String, _PendingPairRequest> _pendingPairRequests = {};

  /// §7.1 LD-2: how long a pending pair request stays visible in
  /// [getPendingPairRequests] after arriving on this Primary.
  ///
  /// NOT a security boundary the way `_rotationApprovalTtl` (§7.5) is:
  /// nothing here is pruned by time — `_pendingPairRequests` itself is never
  /// swept, [approvePairRequest] keeps honouring an entry after it ages out
  /// of the catch-up view, and the requesting device can just tap "Request
  /// Pairing" again (§7.1 LD-9 overwrites the map entry, resetting this
  /// clock). It only bounds what the catch-up getter is willing to present
  /// as "waiting for you right now": a day-old, forgotten request
  /// resurfacing long after the fact invites exactly the autopilot approval
  /// that §7.1 step 2's plain-text device-ID comparison exists to prevent.
  static const Duration _pairRequestDisplayTtl = Duration(hours: 24);

  void _handleDevicePairRequestV3(HarvestEvent event) {
    try {
      final request = proto.DevicePairRequestV3.fromBuffer(event.payload);
      // §7.1 is, like §7.5, a DEVICE procedure: the identifier here is not
      // a note of origin, but the applicant itself. It becomes the key of
      // `_pendingPairRequests`, from which `approvePairRequest` fetches it
      // back via `hexToBytes` and SIGNS it as `newDeviceId` into the
      // delegation certificate (:11802-11806). An invented value would thus
      // not merely be a wrong log entry, but a power of attorney for a
      // device that does not exist.
      //
      // If the identifier is missing, the request is discarded — not parked
      // with a placeholder. Unlike with the branches further below, there is
      // no partial benefit here that could be rescued: without an applicant
      // there is nothing to approve (§14.1: "subject, not a signpost").
      final requestingDevice = event.senderDeviceId;
      if (requestingDevice == null) {
        _log.warn('DEVICE_PAIR_REQUEST without device identifier (delivery without '
            'device layer, §14.2) — discarded: the delegation certificate '
            'needs the requesting device as subject');
        return;
      }
      final deviceIdHex = bytesToHex(requestingDevice);

      // §7.1 LD-11: drop our OWN pairing request when it comes back to us.
      //
      // Mandatory companion to the L3 bootstrap in `sendToUser`: the request
      // is placed in the *shared* user mailbox, and the requesting device
      // polls that very mailbox itself (`_activeMailboxIds` → `_pollMailbox`,
      // run aggressively right after a seed restore). Without this guard the
      // device retrieves its own request, still holds the master seed at this
      // point (the seed is only unused — never wiped — after pairing), passes
      // the Primary check below and self-approves: it would issue itself a
      // delegation cert and register itself as its own twin.
      //
      // Matched on the payload's device signing key, not on the outer
      // `senderDeviceId`: the L3 outer packet is built with
      // `node.primaryIdentity.deviceNodeId`, which is not this identity's
      // device id under multi-identity. `deviceEd25519Pk` is written from
      // `node.deviceKeyPair.ed25519PublicKey` in `sendDevicePairRequest` and
      // is per-node, so the comparison is exact on every identity.
      // FORMERLY the echo of the OWN pairing request was recognised here by
      // comparing the device signing key sent along against the own one.
      // Without a holder for the device key (gap G-9) the comparison cannot
      // be carried out.
      //
      // The echo case cannot occur at present anyway: it arose because the
      // request ran via the shared user mailbox, and that fell with the V3
      // store-and-forward. The gap stays noted so that it is closed
      // together with G-9.

      _log.info('DEVICE_PAIR_REQUEST from device $deviceIdHex');

      if (identity.masterSeed == null) {
        _log.warn('Ignoring pair request: this device is not the Primary (no seed)');
        return;
      }

      // §7.1 LD-9 AUTO-APPROVAL: DROPPED (gap G-9).
      //
      // It recognised an already known linked device by
      // `_identityPublisher.delegations` and approved the renewal without
      // asking. Without this list "already known" cannot be established.
      //
      // THE FAILURE GOES IN THE SAFE DIRECTION and is therefore NOT
      // replaced: the request falls into the ordinary path below and waits
      // for the user's explicit approval. Recognising it via `_devices`
      // instead would be a different yardstick (every device stands there,
      // including one without a valid delegation) — an auto-approval on a
      // weaker basis is not a restoration but a lowering.
      _log.info('LD-9: no auto-approval possible (gap G-9) — '
          'renewal of ${deviceIdHex.substring(0, 8)} goes to '
          'manual approval.');

      _pendingPairRequests[deviceIdHex] = _PendingPairRequest(
        request: request,
        receivedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      onDevicePairRequest?.call(deviceIdHex);
    } catch (e) {
      _log.error('Failed to parse DEVICE_PAIR_REQUEST: $e');
    }
  }

  /// §7.1 LD-11: Initiate pairing from this device (wants to become Linked).
  /// Sends DEVICE_PAIR_REQUEST to our own userId — the Primary picks it up.
  /// Also used for renewal (LD-9): already-linked devices can re-request to
  /// get a fresh cert with a new 30-day window.
  ///
  /// §7.1 P3: targeted addressing instead of blind-drop. Before this device
  /// has ever paired it knows nothing about the Primary — no address, no
  /// device-id — so the naive send falls all the way through `sendToUser`'s
  /// L3 cascade to the shared pre-pairing mailbox (both devices derive the
  /// identical userId from the shared seed, see the §7.2 self-fanout
  /// comment there). That mailbox path stays as the fallback, but on the
  /// very first pairing attempt (not on LD-9 renewals, which already know
  /// the Primary as a twin) we first try to resolve the Primary's real
  /// device-id via the DHT AuthManifest and address it directly through the
  /// `targetDeviceId` fast-path — the same fan-out branch that already
  /// carries the DEVICE_PAIR_APPROVE direction back.
  @override
  Future<bool> sendDevicePairRequest() async {
    // Gap G-9: the pairing request CARRIES the device signing keys of this
    // device — they are its content, not its envelope. Without a holder
    // there is nothing to send, and a request with empty key fields would
    // be admitted by the primary as a half-registered device (§7.5
    // "half-registered").
    _log.error('sendDevicePairRequest: not possible — the '
        'device signature keys have no holder in V4.1 '
        '(gap G-9).');
    return false;
    // ignore: dead_code
    final request = proto.DevicePairRequestV3()
      ..timestampMs = Int64(DateTime.now().millisecondsSinceEpoch);

    // FORMERLY the primary was resolved here via the AuthManifest in the
    // 2D DHT (`node.resolveUserToDevices`), in order to address the pairing
    // request specifically to it. §4.3 is replaced; the resolution no
    // longer exists. Unreachable anyway, because the method above already
    // exits because of gap G-9.
    const Uint8List? targetDeviceId = null;

    // §7.1 P3: `sendToUser` returns `false` by documented contract whenever
    // the frame only reached L3 offline placement (S&F/mailbox) instead of
    // a live direct dispatch — see the `sendToUser` doc (~L13421) and its
    // `l3Result` out-parameter. The LD-11 bootstrap fallback (no twin, no
    // resolved target) ALWAYS takes that L3 branch, so reading only the
    // direct-dispatch return here permanently reported a successfully
    // placed pairing request as "failed". `l3Out[0]` carries the actual
    // placement outcome.
    final l3Out = <bool>[false];
    final directSent = await sendToUser(
      recipientUserId: identity.userId,
      messageType: proto.MessageTypeV3.MTV3_DEVICE_PAIR_REQUEST,
      payload: request.writeToBuffer(),
      targetDeviceId: targetDeviceId,
      l3Result: l3Out,
    );
    final sent = directSent || l3Out[0];

    if (sent) {
      _log.info('DEVICE_PAIR_REQUEST sent to own userId '
          '(${identity.isLinkedDevice ? "renewal" : "initial pairing"})'
          '${targetDeviceId != null ? " via targeted device" : directSent ? "" : " via shared mailbox"}');
    } else {
      _log.warn('DEVICE_PAIR_REQUEST send failed — no route to Primary '
          'and L3 placement failed');
    }
    return sent;
  }

  void _handleDevicePairApproveV3(HarvestEvent event) {
    try {
      final approve = proto.DevicePairApproveV3.fromBuffer(event.payload);
      // Two halves with different needs, hence NOT discarded wholesale
      // here:
      //   [a] check the certificate, store and apply keys — needs no
      //       device. The proof for that is the certificate itself: it
      //       verifies under our OWN user key, which only the seed-holding
      //       primary can form.
      //   [b] register the primary as a twin in `_devices` — that is pure
      //       device bookkeeping and needs the identifier as key, name and
      //       `deviceNodeIdHex`.
      // If it is missing, [a] runs and [b] is skipped — exactly the split
      // that the `senderTrust` branch a few lines further down already
      // makes ("keys applied, but NOT registering ... as Primary twin"). No
      // substitute value: an invented `deviceNodeIdHex` would be a twin
      // entry to which every later `_sendTwinSync` sends.
      final senderDevice = event.senderDeviceId;
      final senderHex =
          senderDevice == null ? null : bytesToHex(senderDevice);
      _log.info('DEVICE_PAIR_APPROVE from '
          '${CleonaService._hexShort(senderDevice)} — storing '
          'linked-device keys');

      final parsed = DevicePairingService().parseApproval(approve);

      if (!parsed.delegationCert.verify(
          identity.ed25519PublicKey, identity.mlDsaPublicKey)) {
        _log.error('DEVICE_PAIR_APPROVE: delegation cert signature INVALID — rejecting');
        return;
      }

      LinkedDeviceKeysStore.save(
        profileDir: profileDir,
        store: store,
        keys: parsed,
      );
      applyLinkedDeviceKeys(parsed);
      _log.info('DEVICE_PAIR_APPROVE accepted — persisted + applied, '
          'caps=${parsed.delegationCert.capabilities}, '
          'expiry=${parsed.delegationCert.maxValidUntilMs > 0 ? "${((parsed.delegationCert.maxValidUntilMs - DateTime.now().millisecondsSinceEpoch) / 86400000).toStringAsFixed(0)}d" : "none"}');

      // §7.1/§7.2 — record the Primary as a twin on THIS device.
      //
      // Without this the pairing stays one-directional: the Primary knows the
      // linked device (`_addDeviceDelegation`), but this device's `_devices`
      // still holds only itself, so `_sendTwinSync` and `_sendTwinAnnounce`
      // both bail out on `_devices.length <= 1` and nothing can ever be sent
      // back to the Primary.
      //
      // Source of the Primary's device id: the outer `event.senderDeviceId`.
      // Deliberate, not a shortcut — `DevicePairApproveV3` carries no device id
      // of its own, and `DeviceDelegationCertProto.device_id` names *this*
      // device (the delegate), not the issuer. `event.senderDeviceId` is the only available
      // source, and it is gated three ways:
      //   [1] the outer packet signature must have verified, which binds `event.senderDeviceId`
      //       to a device that proved possession of the matching device
      //       keypair for this very packet;
      //   [2] the inner frame's `senderUserId` must be our own user id — the
      //       inner frame carries a User-Sig verified upstream, so this is a
      //       claim only a holder of our User signing key can make;
      //   [3] the delegation cert above verified under our own User key, which
      //       only the seed-holding Primary can produce.
      // Residual gap, documented rather than closed here: a captured approval
      // could be re-wrapped in a fresh outer packet signed with an attacker's
      // device key, passing [1] while carrying a foreign `event.senderDeviceId`. The inner
      // messageId dedup in `handleApplicationFrame` blocks the straightforward
      // replay. Closing it properly needs an authenticated primary-device-id
      // field in `DevicePairApproveV3` — a proto change, out of scope here.
      if (senderHex == null) {
        _log.warn('DEVICE_PAIR_APPROVE: delivery without device layer '
            '(§14.2) — keys applied, but NO twin entry '
            'for the primary. Twin sync stays one-sided until the first '
            'TWIN_ANNOUNCE via a V3 frame.');
        return;
      }
      if (event.senderTrust != SenderTrust.verified) {
        _log.warn('DEVICE_PAIR_APPROVE: outerSig=${event.senderTrust.name} — '
            'keys applied, but NOT registering $senderHex as Primary twin');
        return;
      }
      if (!constantTimeEquals(
          Uint8List.fromList(event.senderUserId), identity.userId)) {
        _log.warn('DEVICE_PAIR_APPROVE: senderUserId is not our own user id — '
            'NOT registering $senderHex as Primary twin');
        return;
      }
      if (senderHex == identity.deviceNodeIdHex) {
        _log.warn('DEVICE_PAIR_APPROVE: sender is this very device — '
            'not registering a self-twin');
        return;
      }

      // Idempotency matches on `deviceNodeIdHex`, not on the map key.
      // `_devices` is keyed by the peer's 16-byte UUID (see `_initLocalDevice`),
      // which the approval does not carry — so this bootstrap record is keyed
      // by the node id instead, exactly as `_addDeviceDelegation` does on the
      // Primary side. The Primary's later TWIN_ANNOUNCE carries its real UUID
      // and supersedes this record: the DEVICE_ANNOUNCE branch of
      // `_handleTwinSyncV3` drops any older record holding the same
      // `deviceNodeIdHex`, so the two keyings cannot accumulate into a
      // duplicate that would double every twin-send.
      DeviceRecord? existingPrimary;
      for (final d in _devices.values) {
        if (d.deviceNodeIdHex == senderHex) {
          existingPrimary = d;
          break;
        }
      }
      if (existingPrimary != null) {
        existingPrimary.lastSeen = DateTime.now();
        _saveDevices();
        _log.debug('DEVICE_PAIR_APPROVE: Primary ${senderHex.substring(0, 8)} '
            'already registered — refreshed lastSeen');
      } else {
        final now = DateTime.now();
        // No `isPrimary` flag exists on DeviceRecord; the name follows the
        // 'Linked-xxxxxx' convention `_addDeviceDelegation` uses on the other
        // side, and is replaced by the real hostname on the first TWIN_ANNOUNCE.
        _devices[senderHex] = DeviceRecord(
          deviceId: senderHex,
          deviceName: 'Primary-${senderHex.substring(0, 6)}',
          platform: 'unknown',
          firstSeen: now,
          lastSeen: now,
          deviceNodeIdHex: senderHex,
        );
        _saveDevices();
        _notifyDevicesChanged();
        _log.info('DEVICE_PAIR_APPROVE: registered Primary '
            '${senderHex.substring(0, 8)} as twin — twin-sync is now '
            'bidirectional (${_devices.length} devices)');
      }
    } catch (e) {
      _log.error('Failed to process DEVICE_PAIR_APPROVE: $e');
    }
  }

  /// §7.1 LD-2: Called from IPC when the user approves a pending pair request.
  /// Builds the delegation material and sends DEVICE_PAIR_APPROVE to the requester.
  @override
  Future<bool> approvePairRequest(String requestingDeviceIdHex) async {
    final pending = _pendingPairRequests.remove(requestingDeviceIdHex);
    if (pending == null) {
      _log.warn('approvePairRequest: no pending request for $requestingDeviceIdHex');
      return false;
    }
    // `pending.request` was unpacked here to register the device signing
    // keys of the new device. This registration has no holder any more
    // (gap G-9, noted further below); the certificate itself does not
    // need it.
    final newDeviceId = hexToBytes(requestingDeviceIdHex);
    final result = DevicePairingService().buildApproval(
      identity: identity,
      newDeviceId: newDeviceId,
    );

    // §7.1 LD-2 — register BEFORE sending. Two reasons, both load-bearing:
    //
    // [1] The send below merely *delivers* a decision the user has already
    //     made; the decision itself is local state. Coupling that state
    //     transition to `sent` (as this code did until 2026-08-04) meant a
    //     transient network error silently discarded the approval: the
    //     pending request was already removed above, so nothing could retry
    //     it and the user's confirmation evaporated with nothing but a log
    //     line to show for it.
    // [2] Registering first is what *enables* the retry. `_addDeviceDelegation`
    //     puts the cert into `_identityPublisher.delegations`, which is exactly
    //     what the LD-9 auto-approve branch of `_handleDevicePairRequestV3`
    //     reads. A device whose approval was lost in transit re-sends
    //     DEVICE_PAIR_REQUEST and is re-approved without prompting the user a
    //     second time. Under the old ordering that branch could never fire,
    //     because a failed send left nothing recorded to recognise it by.
    //
    // The delegation cert is fully built and signed at this point and stays
    // valid whether or not the frame arrives, so publishing it in the
    // AuthManifest states the truth: this device is authorized.
    _addDeviceDelegation(newDeviceId, result.delegationCert);
    // §7.5: register the linked device's Device-Sig pubkeys for Co-Auth.
    // Kept immediately adjacent to `_addDeviceDelegation` — a device present in
    // `_devices` but missing from the Co-Auth sig-key set is half-registered
    // and would make the §7.5 rotation quorum under-count.
    // FORMERLY: `_identityPublisher.addLinkedDeviceSigKeys(...)`. Without a
    // holder for the device signing keys the device stays half-registered
    // per §7.5 — it stands in `_devices`, but counts in no quorum. The
    // comment above names exactly this state ("half-registered"); it is
    // now the normal case until gap G-9 is closed.
    _log.warn('§7.5: device signature keys of '
        '${bytesToHex(newDeviceId).substring(0, 8)} have no holder '
        '(gap G-9) — the device does not count in the rotation quorum.');

    // Send the approval (KEM-encrypted, addressed AT the requesting device).
    //
    // `targetDeviceId` is mandatory here: this is a self-send
    // (recipientUserId == our own userId), and the §7.2 self fan-out branch in
    // `sendToUser` builds its recipient list from `_devices` while skipping the
    // local device. Without an explicit target the approval would go to the
    // *other*, already-paired twins instead of the requester — and on a first
    // pairing, where `_devices` holds only this device, the list would be empty
    // and the send would return false. The `targetDeviceId` branch sits ahead
    // of the self branch and addresses the device node id directly.
    final sent = await sendToUser(
      recipientUserId: identity.userId,
      messageType: proto.MessageTypeV3.MTV3_DEVICE_PAIR_APPROVE,
      payload: result.approvePayload.writeToBuffer(),
      targetDeviceId: newDeviceId,
    );

    if (sent) {
      _log.info('DEVICE_PAIR_APPROVE sent to $requestingDeviceIdHex');
    } else {
      _log.warn('DEVICE_PAIR_APPROVE send to $requestingDeviceIdHex failed — '
          'device stays registered; it can re-request and hit LD-9 auto-approve');
    }
    return sent;
  }

  /// §7.1 LD-2: catch-up for [onDevicePairRequest] — see the interface doc
  /// for the field contract.
  ///
  /// Analogous to [getPendingRotationApprovals] (§7.5) in shape, but the TTL
  /// here is purely a display cutoff — see [_pairRequestDisplayTtl] for why
  /// nothing is dropped from [_pendingPairRequests] itself and
  /// [approvePairRequest] keeps working past it.
  @override
  Future<List<Map<String, dynamic>>> getPendingPairRequests() async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final out = <Map<String, dynamic>>[];
    for (final entry in _pendingPairRequests.entries) {
      final expiresAtMs =
          entry.value.receivedAtMs + _pairRequestDisplayTtl.inMilliseconds;
      if (expiresAtMs <= nowMs) continue;
      out.add({
        'deviceIdHex': entry.key,
        'receivedAtMs': entry.value.receivedAtMs,
        'expiresAtMs': expiresAtMs,
      });
    }
    out.sort((a, b) =>
        (a['receivedAtMs'] as int).compareTo(b['receivedAtMs'] as int));
    return out;
  }

  /// §7.1 LD-7: Soft migration — apply LinkedDeviceKeys received via pairing
  /// to this IdentityContext. Called when the user opts to convert a legacy
  /// twin-device (seed-on-every-device) to the delegation model.
  ///
  /// After this call, [identity.isLinkedDevice] becomes true and all
  /// Inner-Sigs use the delegated keys. The master seed is NOT wiped here
  /// (that's a destructive operation requiring explicit user confirmation
  /// in the GUI); it simply becomes unused for signing.
  void applyLinkedDeviceKeys(LinkedDeviceKeys keys) {
    identity.linkedDeviceKeys = keys;
    _log.info('Applied linked-device delegation keys — '
        'isLinkedDevice=${identity.isLinkedDevice}, '
        'caps=${keys.delegationCert.capabilities}');
  }

  /// §7.1 LD-9: Periodic check — request renewal when cert expires within 7 days.
  void _checkDelegationRenewal() {
    if (!identity.isLinkedDevice) return;
    final ldKeys = identity.linkedDeviceKeys;
    if (ldKeys == null) return;
    final cert = ldKeys.delegationCert;
    if (cert.maxValidUntilMs == 0) return;
    final remainingMs =
        cert.maxValidUntilMs - DateTime.now().millisecondsSinceEpoch;
    final remainingDays = remainingMs / (24 * 60 * 60 * 1000);
    if (remainingDays <= 7 && remainingDays > 0) {
      _log.info('LD-9: delegation cert expires in ${remainingDays.toStringAsFixed(1)} days — requesting renewal');
      requestDelegationRenewal();
    } else if (remainingDays <= 0) {
      _log.warn('LD-9: delegation cert EXPIRED — requesting renewal');
      requestDelegationRenewal();
    }
  }

  // `_sendDelegationRotation(...)` stood here: §7.1 LD-8 — after an
  // emergency rotation every linked device gets its own freshly derived
  // delegation material. Both callers are gone: [rotateIdentityKeys]
  // aborts today before the first step (gaps G-3/G-9), and the list of
  // devices to serve came from `_identityPublisher.delegations`, which no
  // longer exists.
  //
  // ── READ THIS BEFORE REBUILDING THE SENDER (S392) ───────────────────
  //
  // The sender arms a second finding that sleeps today, and it is a
  // silent one: after the first LD-8 rotation a Linked Device derives its
  // `K_AB` from the WRONG key.
  //
  // §4.3 is normative and unambiguous:
  //     dh_AB = X25519(founding_sk_A, founding_pk_B)
  // Two further places say it again: "`K_AB` survives every rotation (it
  // is derived from the **founding** keys, §4.3, §15.2)" and "The
  // founding keys are stable across every rotation — they are the anchor
  // `K_AB` falls out of".
  //
  // [IdentityContext.foundingEd25519SecretKey] recomputes the founding
  // key from the HD wallet — and without a seed it falls back to the
  // CURRENT one. A Linked Device has no seed (§14.6.2). Until S392 that
  // was harmless because `rotateDelegation` never replaced
  // `ed25519SecretKey`: the "current" key still WAS the founding key.
  // Since the §14.4 co-rotation the two drift apart.
  //
  // THE PEER CARRIES THE CONSEQUENCE: it derives `dh_AB` from the
  // founding pubkey off the card. Both sides then compute a different
  // `K_AB` — no pair code matches any more, ladder step 3 fails, the post
  // box day values do not line up, and none of it reports an error.
  //
  // The fix is NOT obvious, which is why it is not built: handing the
  // founding SK to every device would undercut §14.4 (a locked-out device
  // could keep signing in the identity's name), and storing `K_AB` per
  // contact and syncing it would leave a locked-out device with every
  // pair code. Three options with computed cost: `BUGFIX_CURRENT.md`,
  // S392-17.

  /// §7.1 LD-8: Handle delegation rotation on a Linked Device.
  Future<void> _handleDelegationRotation(Map<String, dynamic> json) async {
    final targetHex = json['targetDeviceId'] as String;
    if (targetHex != bytesToHex(identity.deviceNodeId)) return;

    if (!identity.isLinkedDevice) {
      _log.warn('LD-8: received delegation rotation but not a Linked Device');
      return;
    }

    final certBytes = hexToBytes(json['delegationCertProto'] as String);
    final cert = DeviceDelegation.fromProtoBytes(certBytes);

    if (!cert.verify(identity.ed25519PublicKey, identity.mlDsaPublicKey)) {
      _log.error('LD-8: delegation rotation cert INVALID — rejecting');
      return;
    }

    final newUserEd25519Pk = hexToBytes(json['newUserEd25519Pk'] as String);
    final newUserMlDsaPk = hexToBytes(json['newUserMlDsaPk'] as String);
    final newUserX25519Pk = hexToBytes(json['newUserX25519Pk'] as String);
    final newUserMlKemPk = hexToBytes(json['newUserMlKemPk'] as String);
    final newUserX25519Sk = hexToBytes(json['newUserX25519Sk'] as String);
    final newUserMlKemSk = hexToBytes(json['newUserMlKemSk'] as String);
    // §14.4: the identity signature keys rotate along at lock-out and "sit
    // under the shared key on every device". They travel in this very
    // message — same channel, same sealing as the two KEM SKs above. Before
    // S392 they were absent and `rotateDelegation` set only the public
    // halves, which locked the device out of its own system channels from
    // the first rotation on (report `mycelium/berichte/S392-FIX-LD8.md`).
    //
    // Checked BEFORE anything is mutated, and rejected as a whole: a
    // rotation that sets the public keys but not the secret ones is exactly
    // the broken state S392 removed. Half a rotation is worse than none —
    // none keeps the device working, half locks it out silently.
    final newUserEd25519SkHex = json['newUserEd25519Sk'];
    final newUserMlDsaSkHex = json['newUserMlDsaSk'];
    if (newUserEd25519SkHex is! String || newUserMlDsaSkHex is! String) {
      _log.error('LD-8: rotation message carries no user signature SKs '
          '(§14.4 co-rotation) — rejecting the whole rotation; applying only '
          'the public halves would lock this device out of its own records');
      return;
    }
    final newUserEd25519Sk = hexToBytes(newUserEd25519SkHex);
    final newUserMlDsaSk = hexToBytes(newUserMlDsaSkHex);

    final newLinkedKeys = LinkedDeviceKeys(
      delegatedEd25519Pk: hexToBytes(json['delegatedEd25519Pk'] as String),
      delegatedEd25519Sk: hexToBytes(json['delegatedEd25519Sk'] as String),
      delegatedMlDsaPk: hexToBytes(json['delegatedMlDsaPk'] as String),
      delegatedMlDsaSk: hexToBytes(json['delegatedMlDsaSk'] as String),
      userX25519Sk: newUserX25519Sk,
      userMlKemSk: newUserMlKemSk,
      delegationCert: cert,
      userId: identity.userId,
      displayName: identity.displayName,
    );

    LinkedDeviceKeysStore.save(
      profileDir: profileDir,
      store: store,
      keys: newLinkedKeys,
    );

    identity.rotateDelegation(
      newUserEd25519Pk: newUserEd25519Pk,
      newUserMlDsaPk: newUserMlDsaPk,
      newUserEd25519Sk: newUserEd25519Sk,
      newUserMlDsaSk: newUserMlDsaSk,
      newUserX25519Pk: newUserX25519Pk,
      newUserMlKemPk: newUserMlKemPk,
      newUserX25519Sk: newUserX25519Sk,
      newUserMlKemSk: newUserMlKemSk,
      newLinkedKeys: newLinkedKeys,
    );

    // `node.broadcastAddressUpdate()` + manifest republish stood here
    // (§4.3/§5.11, fallen with the CUT — T).
    onStateChanged?.call();
    _log.info('LD-8: delegation rotation applied from Primary — '
        'chain length ${identity.rotationChain.length}');
  }

  void _handleDeviceRevocationV3(HarvestEvent event) {
    // V3 direct: inner payload is the DeviceRecord protobuf, already
    // decrypted + authenticated by the V3 pipeline. §26 authorization check
    // preserved: only accepted contacts may revoke their own devices for us.
    final senderHex = event.senderUserId.hex;
    final contact = _contacts[senderHex];
    if (contact == null || contact.status != 'accepted') return;

    try {
      final revokedDevice = proto.DeviceRecord.fromBuffer(event.payload);
      final deviceIdShort = revokedDevice.deviceId.hex.substring(0, 8);

      // §26 Phase 4: remove by deviceNodeId (preferred, precise)
      if (revokedDevice.deviceNodeId.isNotEmpty) {
        final revokedNodeId = Uint8List.fromList(revokedDevice.deviceNodeId);
        final revokedNodeIdHex = bytesToHex(revokedNodeId);
        // The entry in the routing table fell with it (T). What remains
        // and what counts is the device list at the contact record.
        contact.deviceNodeIds.remove(revokedNodeIdHex);
        _saveContacts();
        _log.debug('DEVICE_REVOKED — displayName="${contact.displayName}"');
        _log.info('DEVICE_REVOKED: '
            'device $deviceIdShort, deviceNodeId '
            '${revokedNodeIdHex.substring(0, 8)} removed from the contact '
            'record');
        return;
      }

      // Fallback: remove by addresses (pre-Phase-4 peers without deviceNodeId)
      final revokedAddresses = revokedDevice.addresses
          .map((a) => '${a.ip}:${a.port}')
          .toSet();

      if (revokedAddresses.isEmpty) {
        _log.debug('DEVICE_REVOKED — displayName="${contact.displayName}"');
        _log.info('DEVICE_REVOKED: '
            'device $deviceIdShort revoked (no deviceNodeId or addresses to prune)');
        return;
      }

      // FORMERLY: remove the revoked addresses from the contact's
      // `PeerInfo`. There is no address list per contact any more
      // (see [peerSummaries], gap G-11) — and thus nothing to trim either.
      // The revocation takes effect via the device list above.
      _log.debug('DEVICE_REVOKED — displayName="${contact.displayName}"');
      _log.info('DEVICE_REVOKED: '
          'device $deviceIdShort, ${revokedAddresses.length} address(es) '
          'named — V4.1 keeps no peer address list, nothing to '
          'trim (gap G-11)');
    } catch (e) {
      _log.error('DEVICE_REVOKED processing failed: $e');
    }
  }
  // ─────────────── CALL_MEDIA_STATE — own video on/off (§10.6, V1.12) ───────
  //
  // Scope of this block, deliberately narrow: encode our own state, decode the
  // peer's, keep the latest per (call, peer), and hand it out. It renders
  // nothing and it starts and stops no camera. The display belongs to V1.6
  // (`call_screen.dart`) and V2.3 (`video_engine.dart`), the send call site to
  // V2.1 (`call_service.dart`) — see `BUGFIX_CURRENT.md AV-V1.12`.
  //
  // Invariante I12 runs through the whole block: a received state is a report
  // about the far side. Nothing here may act on the local capture session, and
  // nothing here may be given a code path that would let it.

  /// Fires whenever a peer's own-video state changes (§10.6).
  ///
  /// Only on an actual change or a fresher sequence — a repeated identical
  /// state does not fire, so a UI may rebuild on every call.
  void Function(PeerCallMediaState state)? onPeerCallMediaStateChanged;

  /// Latest state, keyed by `callIdHex` + `/` + `peerUserIdHex`.
  final Map<String, PeerCallMediaState> _peerCallMediaStates = {};

  /// Our own `state_seq` per callIdHex. Monotonic, starts at 1.
  final Map<String, int> _ownCallMediaSeq = {};

  static String _mediaStateKey(String callIdHex, String peerUserIdHex) =>
      '$callIdHex/$peerUserIdHex';

  /// What [peerUserIdHex] last said about its own video in [callIdHex], or
  /// null if it has said nothing yet.
  ///
  /// "Nothing yet" is not "video off". A caller must not turn the absence of a
  /// state into a claim about the peer.
  PeerCallMediaState? peerCallMediaState(String callIdHex, String peerUserIdHex) =>
      _peerCallMediaStates[_mediaStateKey(callIdHex, peerUserIdHex)];

  /// Drops every remembered peer state for a call. To be called when the call
  /// ends, so a later call with a recycled id cannot inherit stale state.
  void clearCallMediaStates(String callIdHex) {
    _peerCallMediaStates.removeWhere((k, _) => k.startsWith('$callIdHex/'));
    _ownCallMediaSeq.remove(callIdHex);
  }

  /// Builds the `MTV3_CALL_MEDIA_STATE` payload announcing **our own** video
  /// state in [callId] (§10.6).
  ///
  /// Owns the monotonic `state_seq` so no call site has to; every invocation
  /// yields the next one for that call. [reason] is ignored — and sent as
  /// unspecified — when [sendingVideo] is true, because a reason for not
  /// sending makes no sense while we are sending.
  ///
  /// I12: there is no parameter for the peer's video, and none may be added.
  Uint8List buildCallMediaStatePayload({
    required Uint8List callId,
    required bool sendingVideo,
    CallVideoOffReason reason = CallVideoOffReason.unspecified,
  }) {
    final callIdHex = bytesToHex(callId);
    final seq = (_ownCallMediaSeq[callIdHex] ?? 0) + 1;
    _ownCallMediaSeq[callIdHex] = seq;

    final msg = proto.CallMediaState()
      ..callId = callId
      ..sendingVideo = sendingVideo
      ..videoOffReason = sendingVideo
          ? proto.VideoOffReason.VIDEO_OFF_REASON_UNSPECIFIED
          : _toWireVideoOffReason(reason)
      ..stateSeq = Int64(seq);

    return msg.writeToBuffer();
  }

  static proto.VideoOffReason _toWireVideoOffReason(CallVideoOffReason r) {
    switch (r) {
      case CallVideoOffReason.userDisabled:
        return proto.VideoOffReason.VIDEO_OFF_REASON_USER_DISABLED;
      case CallVideoOffReason.bandwidthInsufficient:
        return proto.VideoOffReason.VIDEO_OFF_REASON_BANDWIDTH_INSUFFICIENT;
      case CallVideoOffReason.unspecified:
        return proto.VideoOffReason.VIDEO_OFF_REASON_UNSPECIFIED;
    }
  }

  /// Maps a wire reason onto [CallVideoOffReason].
  ///
  /// Anything this build does not know becomes
  /// `CallVideoOffReason.unspecified` — never a known reason. proto3
  /// open-enum decoding already
  /// hands us 0 for an unrecognised number; the explicit default here is the
  /// second lock, so that adding a value to the wire enum without updating
  /// this switch degrades to "reason unknown" instead of a wrong claim.
  static CallVideoOffReason _fromWireVideoOffReason(proto.VideoOffReason r) {
    if (r == proto.VideoOffReason.VIDEO_OFF_REASON_USER_DISABLED) {
      return CallVideoOffReason.userDisabled;
    }
    if (r == proto.VideoOffReason.VIDEO_OFF_REASON_BANDWIDTH_INSUFFICIENT) {
      return CallVideoOffReason.bandwidthInsufficient;
    }
    return CallVideoOffReason.unspecified;
  }

  /// Handles an incoming `MTV3_CALL_MEDIA_STATE` (§10.6, V1.12).
  ///
  /// The frame is already decrypted and its user signature verified by the V3
  /// pipeline, so the sender identity in [proto.ApplicationFrameV3.senderUserId]
  /// is authenticated and is what the state is keyed by.
  ///
  /// Drops, in order: unparseable payloads, malformed call ids, and states that
  /// are not strictly newer than what that peer already told us for that call.
  /// The last one matters because this travels over an unordered datagram
  /// network: a reordered older frame would otherwise reinstate "video off"
  /// while frames are arriving, which is the very picture V1.12 exists to
  /// prevent.
  void handleCallMediaStateV3(HarvestEvent event) {
    proto.CallMediaState msg;
    try {
      msg = proto.CallMediaState.fromBuffer(event.payload);
    } catch (e) {
      _log.error('CALL_MEDIA_STATE parse failed: $e');
      return;
    }

    if (msg.callId.length != 16) {
      _log.warn('CALL_MEDIA_STATE dropped: call_id is '
          '${msg.callId.length} bytes, expected 16');
      return;
    }

    final callIdHex = msg.callId.hex;
    final peerHex = event.senderUserId.hex;
    final key = _mediaStateKey(callIdHex, peerHex);
    final seq = msg.stateSeq.toInt();

    final previous = _peerCallMediaStates[key];
    if (previous != null && seq <= previous.stateSeq) {
      _log.debug('CALL_MEDIA_STATE from ${_shortHex(peerHex)} ignored: '
          'seq $seq is not newer than ${previous.stateSeq}');
      return;
    }

    // A reason alongside "I am sending" is meaningless; drop it here rather
    // than let a UI render "video off because ..." next to a live picture.
    final reason = msg.sendingVideo
        ? CallVideoOffReason.unspecified
        : _fromWireVideoOffReason(msg.videoOffReason);

    final state = PeerCallMediaState(
      callIdHex: callIdHex,
      peerUserIdHex: peerHex,
      sendingVideo: msg.sendingVideo,
      videoOffReason: reason,
      stateSeq: seq,
      receivedAt: event.harvestedAt,
    );
    _peerCallMediaStates[key] = state;

    if (previous != null &&
        previous.sendingVideo == state.sendingVideo &&
        previous.videoOffReason == state.videoOffReason) {
      // Fresher sequence, same content — remembered, but nothing to redraw.
      return;
    }

    _log.info('CALL_MEDIA_STATE from ${_shortHex(peerHex)} in call '
        '${_shortHex(callIdHex)}: sendingVideo=${state.sendingVideo}'
        '${state.sendingVideo ? '' : ', reason=${state.videoOffReason.name}'} '
        '(seq $seq)');

    onPeerCallMediaStateChanged?.call(state);
  }

  static String _shortHex(String hex) =>
      hex.length >= 8 ? hex.substring(0, 8) : hex;

  // ──────────────────────────── V3 Helpers ────────────────────────────

  /// Short hex prefix for log lines (8 chars / 4 bytes).
  /// Short form for log lines. Tolerates `null` since the device identifier
  /// is optional (§14.1: the V4.1 path knows no device) — a log line is
  /// no reason to insert an untruth.
  static String _hexShort(Uint8List? bytes) {
    if (bytes == null) return 'kein-Geraet';
    final n = bytes.length < 4 ? bytes.length : 4;
    final sb = StringBuffer();
    for (var i = 0; i < n; i++) {
      sb.write(bytes[i].toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}

// `_IdentityPublisherSender` stood here — the adapter that took a
// `(MessageTypeV3, payload, peer)` triple off the `IdentityPublisher` and
// passed it on to `CleonaNode.sendInfraTo`. Publisher and node are both
// gone (see the field `_identityPublisher` above, T).

/// Stage-2 reassembly buffer for incoming MEDIA_CHUNK frames.
/// Holds chunks indexed by chunk_index until MEDIA_COMPLETE arrives,
/// at which point the receiver concatenates them, hash-checks against
/// the COMPLETE-payload, writes the file, and bumps the UiMessage's
/// mediaState to completed.
class _MediaChunkBuffer {
  final int totalChunks;
  final List<Uint8List?> chunks;
  final DateTime createdAt;
  _MediaChunkBuffer(this.totalChunks)
      : chunks = List<Uint8List?>.filled(totalChunks, null),
        createdAt = DateTime.now();

  bool get isComplete => chunks.every((c) => c != null);

  Uint8List assemble() {
    final total = chunks.fold<int>(0, (a, c) => a + (c?.length ?? 0));
    final out = Uint8List(total);
    var off = 0;
    for (final c in chunks) {
      if (c == null) continue;
      out.setRange(off, off + c.length, c);
      off += c.length;
    }
    return out;
  }
}

/// §5.8 One-Shot-Outbox entry.
///
/// Holds a canonical serialized [NetworkPacketV3] and the metadata required to
/// retry the single L3 placement attempt once the sender regains connectivity.
/// This is NOT a retry queue — the entry is flushed exactly once per
/// onNetworkChanged edge-trigger and then either removed (L3 placed) or kept
/// for the next edge (still 0 peers).
// S368: here stood `class _OutboxEntry` — the record of the V3 outbox with
// `canonicalPacketB64` (serialised `NetworkPacketV3` bytes). In the whole
// tree it was only created by its own `fromJson`.

/// Top-level entry point for [Isolate.run]: reads the binary, RS-encodes it,
/// and stores fragments to disk — entirely off the main thread.
///
/// Uses raw file I/O instead of [BinaryFragmentStore]/[BinarySeeder] to avoid
/// CLogger's Timer.periodic which is not sendable across isolate boundaries.
Future<int> _selfSeedInIsolate({
  required String binaryPath,
  required String profileDir,
  required String platform,
  required String version,
  required int maxFragments,
  String? expectedHash,
}) async {
  final file = File(binaryPath);
  if (!file.existsSync()) return 0;
  final binary = await file.readAsBytes();

  if (expectedHash != null) {
    final actualHash = bytesToHex(SodiumFFI().sha256(binary));
    if (actualHash != expectedHash) return 0;
  }

  final params = BinarySeeder.paramsFor(platform);
  final rs = ReedSolomon.withParams(params.n, params.k);
  final fragments = rs.encode(binary);

  final storageDir = '$profileDir/binary-updates/$platform/$version';
  Directory(storageDir).createSync(recursive: true);

  final storeCount = maxFragments < fragments.length
      ? maxFragments
      : fragments.length;
  for (var i = 0; i < storeCount; i++) {
    File('$storageDir/fragment-${i.toString().padLeft(3, '0')}.bin')
        .writeAsBytesSync(fragments[i]);
  }
  File('$storageDir/complete.bin').writeAsBytesSync(binary);

  final hash = bytesToHex(SodiumFFI().sha256(binary));
  File('$storageDir/meta.json').writeAsStringSync(
      '{"storedAt":${DateTime.now().millisecondsSinceEpoch},'
      '"fragmentCount":$storeCount,"binaryHash":"$hash"}');

  return storeCount;
}

/// §7.5: a rotation-approval request parked on a Linked Device while it waits
/// for an explicit user decision. Memory-only, dropped by [expiryTimer] after
/// [CleonaService._rotationApprovalTtl] — expiry sends nothing at all,
/// because silence must not count as consent.
class _PendingRotationApproval {
  /// The hash the Primary asked us to countersign.
  final Uint8List rotationHash;

  /// Device-node-id of the requesting (Primary) device — used both for UI
  /// display and as the `targetDeviceId` the response is addressed at.
  ///
  /// This is the OUTER `senderDeviceId` of the V3 frame, not
  /// `TwinSyncEnvelope.deviceId`, for two independent reasons:
  ///  * Authenticity: the outer id is covered by the outer Device-Sig that
  ///    the V3 receive pipeline already verified. `TwinSyncEnvelope.deviceId`
  ///    is an inner payload field — authenticated as "written by some device
  ///    of this user", but not bound to the device that actually sent the
  ///    frame, so it must not decide where a security-relevant answer goes.
  ///  * Routability: `sendToUser`'s `targetDeviceId` expects a device NODE
  ///    id, which is what the outer id is. `TwinSyncEnvelope.deviceId` is the
  ///    device UUID (`_devices` key) and would have to be translated via
  ///    `deviceNodeIdHex` first — a lookup that fails outright if the
  ///    Primary is not (yet) in this device's `_devices` map.
  final Uint8List requestingDeviceId;

  /// Arrival time, epoch-ms — lets the UI show the remaining TTL.
  final int receivedAtMs;

  /// Fires once when the request expires; cancelled on approve/reject.
  final Timer expiryTimer;

  /// §7.5: what the Primary is asking for. Carried all the way to the UI —
  /// the countersignature is identical for both occasions, so the ONLY thing
  /// that keeps a device-set change from being confirmed as a key rotation is
  /// this field reaching the dialog.
  final RotationApprovalKind kind;

  /// §7.5: for [RotationApprovalKind.deviceSetChange], the device node ids
  /// that remain after the change — the dialog derives "what is being
  /// removed" from it. Empty for a key rotation.
  ///
  /// Purely descriptive: the countersignature covers [rotationHash], and the
  /// receiving contact recomputes that hash from the manifest it actually
  /// gets. A Primary that lied here would produce a hash mismatch, not an
  /// accepted proof.
  final List<Uint8List> newDeviceNodeIds;

  _PendingRotationApproval({
    required this.rotationHash,
    required this.requestingDeviceId,
    required this.receivedAtMs,
    required this.expiryTimer,
    required this.kind,
    required this.newDeviceNodeIds,
  });
}

/// §7.5: countersignatures being collected for a device-set change that has
/// not been published yet. Owned by `CleonaService._pendingDeviceSetChange`
/// and read by the publisher's `deviceSetChangeProofProvider`.
class _PendingDeviceSetChange {
  /// The hash the remaining devices are asked to sign. Bound to both the
  /// post-change device list and the sequence number of the manifest that
  /// will carry the proof.
  final Uint8List changeHash;

  /// Hex of [changeHash] — the provider compares against this to check that a
  /// publish actually describes the change these tokens cover.
  final String changeHashHex;

  /// Device count before the change; goes into the proof as
  /// `previous_device_count`.
  final int previousDeviceCount;

  /// `deviceSetChangeQuorum(remaining)` — how many DISTINCT devices must
  /// consent before a proof may be attached.
  final int requiredApprovers;

  final List<RotationApprovalToken> tokens = [];

  /// Device-node-id hexes that have consented. Kept alongside [tokens]
  /// because the quorum counts devices, not signatures: two tokens from one
  /// device are one consent.
  final Set<String> approvers = {};

  /// Completes as soon as [requiredApprovers] distinct devices have consented;
  /// null while nothing is being waited on.
  Completer<void>? completer;

  _PendingDeviceSetChange({
    required this.changeHash,
    required this.changeHashHex,
    required this.previousDeviceCount,
    required this.requiredApprovers,
  });

  /// Record one device's consent. Duplicate tokens from the same device are
  /// dropped, so a device cannot fill a quorum on its own by answering twice.
  /// Returns true when this was a new approver.
  bool add(RotationApprovalToken token) {
    final hex = bytesToHex(token.deviceNodeId);
    if (!approvers.add(hex)) return false;
    tokens.add(token);
    if (approvers.length >= requiredApprovers &&
        completer != null &&
        !completer!.isCompleted) {
      completer!.complete();
    }
    return true;
  }
}

/// §7.1 LD-2: a device-pairing request parked on the Primary while it waits
/// for an explicit user decision. Unlike [_PendingRotationApproval] this is
/// never actively dropped by a timer — see
/// [CleonaService._pairRequestDisplayTtl] for why.
class _PendingPairRequest {
  /// The wire payload as received — carries the requester's Device-Sig
  /// pubkeys, consumed by [CleonaService.approvePairRequest].
  final proto.DevicePairRequestV3 request;

  /// Local arrival time, epoch-ms. Deliberately NOT `request.timestampMs`
  /// (the sender's own clock): [CleonaService.getPendingPairRequests] uses
  /// this to decide what still counts as "just arrived", and that judgement
  /// must not be steerable by whatever timestamp a requesting device chooses
  /// to put in the payload.
  final int receivedAtMs;

  _PendingPairRequest({
    required this.request,
    required this.receivedAtMs,
  });
}

import 'package:cleona/core/service/twin_sync_wire.dart';
import 'package:cleona/core/service/typing_tracker.dart';
import 'package:cleona/core/service/delivery_routing.dart';
import 'package:cleona/core/service/local_outbox.dart';
import 'package:cleona/core/sync/cover_stream.dart'
    show CoverSaver, CoverSaverOutcome;
import 'package:cleona/core/util/local_addresses.dart'
    show dialableFrom;
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:cleona/core/calls/call_consent.dart';
import 'package:cleona/core/crypto/constant_time.dart';
import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/crypto/plaintext_sweep.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/crypto/per_message_kem.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/crypto/pq_isolate.dart';
import 'package:cleona/core/crypto/hd_wallet.dart';
import 'package:cleona/core/recovery/recovery_bundle_content.dart';
import 'package:cleona/core/recovery/recovery_keys.dart';
import 'package:cleona/core/crypto/seed_phrase.dart';
import 'package:cleona/core/storage/channel_index.dart';
import 'package:cleona/core/storage/device_store.dart';
import 'package:cleona/core/storage/device_state_legacy.dart';
import 'package:cleona/core/storage/mailbox_store.dart';
import 'package:cleona/core/storage/message_store.dart';
import 'package:cleona/core/media/media_store.dart';
import 'package:cleona/core/media/media_sweep.dart';
import 'package:cleona/core/media/media_vault.dart';
import 'package:cleona/core/media/transient_files.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/identity/kem_generation.dart';
import 'package:cleona/core/service/cold_start_rotation_gate.dart';
import 'package:cleona/core/identity/rotation_co_auth.dart';
import 'package:cleona/core/moderation/moderation_config.dart';
import 'package:cleona/core/contact/contact_seed.dart'
    show ContactSeedBuilder, ContactSeedDataSource, EntrySeedCandidate;
import 'package:cleona/core/contact/invite_class.dart';
import 'package:cleona/core/contact/invite_ledger.dart';
import 'package:cleona/core/contact/invite_store.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/link/data_port.dart';
import 'package:cleona/core/calls/plane_d_call_transport.dart' show CallPlaneD;
import 'package:cleona/core/service/gui_device_setting.dart';
import 'package:cleona/core/service/notification_silence.dart';
import 'package:cleona/core/tray/tray_status.dart'
    show trayLocaleCode, trayTranslate;
import 'package:cleona/core/util/hex.dart';
import 'package:cleona/core/service/sender_identity_snapshot.dart';
import 'package:cleona/core/identity/identity_context.dart';
import 'package:cleona/core/service/app_version.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/core/service/service_context.dart';
import 'package:cleona/core/service/channel_moderation_service.dart';
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/stats/network_stats.dart';
import 'package:cleona/core/calls/call_integration.dart';
import 'package:cleona/core/calls/call_manager.dart';
import 'package:cleona/core/calls/missed_call.dart';
import 'package:cleona/core/calls/group_call_manager.dart';
import 'package:cleona/core/calls/voice_session.dart' show VoiceEventRecord;
import 'package:cleona/core/platform/app_paths.dart';
import 'package:cleona/core/platform/device_name.dart';
import 'package:cleona/core/service/key_rotation_retry_manager.dart';
import 'package:cleona/core/service/notification_sound_service.dart';
import 'package:cleona/core/archive/voice_transcription_service.dart';
import 'package:cleona/core/archive/whisper_ffi.dart' show WhisperFFI;
import 'package:cleona/core/archive/voice_transcription_config.dart';
import 'package:cleona/core/archive/voice_transcription_types.dart';
import 'package:cleona/core/archive/archive_config.dart';
import 'package:cleona/core/archive/archive_manager.dart';
import 'package:cleona/core/archive/archive_types.dart'
    show ArchiveRetrievalStart;
import 'package:cleona/core/archive/archive_network.dart';
import 'package:cleona/core/archive/archive_transport.dart';
import 'package:cleona/core/archive/share_identity.dart';
import 'package:cleona/core/update/update_manifest.dart';
import 'package:cleona/core/update/update_binary_store.dart';
import 'package:cleona/core/update/update_store_budget.dart';
import 'package:cleona/core/update/installed_binary.dart';
import 'package:cleona/core/update/binary_http_server.dart';
import 'package:cleona/core/update/binary_update_manager.dart';
import 'package:cleona/core/update/bootstrap_web_app.dart';
import 'package:cleona/core/update/foreign_binary_acquirer.dart';
import 'package:cleona/core/update/invite_link.dart';
import 'package:cleona/core/update/invite_link_service.dart';
import 'package:cleona/core/update/physical_transfer_helper.dart';
import 'package:cleona/core/update/install_source.dart';
import 'package:cleona/core/update/binary_seeder.dart';
import 'package:cleona/core/update/update_carrier.dart';
import 'package:cleona/core/update/update_target.dart';
import 'package:cleona/core/media/link_preview_fetcher.dart';
import 'package:cleona/core/calendar/calendar_manager.dart';
import 'package:cleona/core/calendar/sync/calendar_sync_service.dart';
import 'package:cleona/core/polls/poll_manager.dart';
import 'package:cleona/core/service/calendar_protocol_service.dart';
import 'package:cleona/core/service/harvest_event.dart';
import 'package:cleona/core/service/poll_service.dart';
import 'package:cleona/core/service/poll_finality.dart';
import 'package:cleona/core/service/reconcile_wire.dart';
import 'package:cleona/core/service/call_service.dart';
import 'package:cleona/core/services/key_change_policy.dart';
import 'package:cleona/core/channels/system_channels.dart';
import 'package:cleona/core/channels/system_channel_api.dart';
import 'package:cleona/core/channels/report_pseudonym.dart';
import 'package:cleona/core/channels/system_channel_hub.dart';
import 'package:cleona/core/channels/system_channel_service.dart';
import 'package:cleona/core/channels/system_object.dart' show SystemObjectAuthor;
import 'package:cleona/core/channels/contact_issue_reporter.dart';
import 'package:cleona/core/channels/crash_reporter.dart';
import 'package:fixnum/fixnum.dart';
import 'package:cleona/generated/proto/app_payloads.pb.dart' as proto;
import 'package:cleona/generated/proto/transport.pb.dart' as proto;
import 'package:cleona/core/config/network_channel.dart'
    show activeNetworkChannel, NetworkChannel;
import 'package:cleona/core/contact/invitation_card_reader.dart';
import 'package:cleona/core/service/mycelium_seam.dart' as seam
    show
        bulkCacheBytesForPlatform,
        bulkCacheMb,
        bulkCacheSet,
        coverReduceActive,
        coverReduceSet,
        coverReduceSetting,
        portMappingSet,
        portMappingSetting;
import 'package:cleona/core/service/mycelium_seam.dart'
    show
        bulkCacheBytesForPlatform,
        mailboxDetailsFor,
        networkChangeEdge,
        servicesOnHost,
        addressFrom,
        addressHeardTo,
        addressKeysOf,
        postBoxFrom,
        userIdFrom,
        SeamError;
import 'package:mycelium/invitation.dart' as mycelium
    show Kind, kLabelAtMostBytes, kAtMostStanding;
import 'package:mycelium/first_contact.dart' as mycelium
    show ContactRequest, Introduction, IntroductionError;
import 'package:mycelium/memory.dart' as mycelium show Contact;
import 'package:mycelium/neighbour_found_by.dart' show NeighbourFoundBy;
import 'package:mycelium/card.dart' as mycelium show Card;
import 'package:mycelium/board_node.dart' show NodeAnswer;
import 'package:mycelium/card_text.dart' as mycelium
    show CardTextError, asInvitationText, asInvitationLine;
// Without prefix: an extension from an `as mycelium show` import is reported by the
// analyzer as "shown, but isn't used", and without the import the getter is missing.
import 'package:mycelium/node_invitation.dart' show InvitationBuffer;
import 'package:mycelium/update_trace.dart';
import 'package:mycelium/post_box_holder.dart' show PostBoxHolder, kAtMostAge;
import 'package:mycelium/node_helpers.dart' as mycelium show hexFrom, interfaces;
import 'package:mycelium/message.dart' as mycelium show Outbound, Inbound, DeliveryState;
import 'package:mycelium/mailbox.dart' as mycelium
    show Mailbox, MailboxError, MailboxSignal, identifierFrom, contactPlaceholderName;
import 'package:mycelium/mailbox_outbound.dart' as mycelium show MailboxOutbound;
import 'package:mycelium/mailbox_inbound.dart' as mycelium show MailboxInbound;
import 'package:mycelium/mailbox_invitation.dart' as mycelium show MailboxInvitation;
import 'package:mycelium/invitation_way_in.dart' as mycelium
    show MailboxWayIn, invitationWayIn;
import 'package:mycelium/invitation_face_to_face.dart' as mycelium
    show MailboxFaceToFace, faceToFaceLife;
import 'package:mycelium/mailbox_rotation.dart' as mycelium show MailboxRotation;
import 'package:mycelium/mailbox_own_line.dart' as mycelium show MailboxOwnLine;
import 'package:mycelium/mailbox_own_signal.dart' as mycelium
    show MailboxOwnSignal, ownWhereRead, ownWhereWire;
import 'package:mycelium/mailbox_parked.dart' as mycelium show MailboxParked;
// Without prefix, for the same reason as `node_invitation.dart` above.
import 'package:mycelium/mailbox_format_reset.dart'
    show FormatReset, MailboxFormatReset;
import 'package:cleona/core/service/system_notices.dart'
    show
        kNoticeReconnectAfterUpdate,
        kNoticeContactAccepted,
        kNoticeGroupMemberUnreachable,
        kNoticeGroupMemberUnconfirmed,
        kNoticeExpiredBeforeRead,
        noticeWithCount,
        noticeWithName;
// B-3 (§4.3, §16.2.2): group pairs — without prefix, for the same reason as
// `node_invitation.dart` above.
import 'package:mycelium/mailbox_group_pair.dart' show MailboxGroupPair;
import 'package:mycelium/mailbox_pair.dart' show MailboxPair;
import 'package:mycelium/mailbox_envelope_tag.dart' show MailboxEnvelopeTag;
import 'package:mycelium/mailbox_recovery_pairs.dart' show MailboxRecoveryPairs;
import 'package:mycelium/code_registration_former.dart' show CodeRouteFormer;
import 'package:mycelium/neighbour_keys.dart' show NeighbourKeysContact;
import 'package:mycelium/group_member.dart'
    show
        groupMemberSign,
        groupMemberCheck,
        groupMemberNeighboursWire;
import 'package:cleona/core/identity/rotation_chain.dart'
    show ChainKeys, RotationChain, RotationChainError;
import 'package:mycelium/envelope.dart' as mycelium show Address;
// The rescue bundle in the post box (§13.3, B-1,
// `cleona_service_recovery_bundle.dart`). The two node extensions without
// prefix, for the same reason as `node_invitation.dart` above.
import 'package:mycelium/mailbox_recovery_bundle.dart' as mycelium
    show BundleBox, cardHolders, kBundleRenewAfter;
import 'package:mycelium/node_post_box.dart' show NodePostBox;
import 'package:mycelium/media.dart' as mycelium
    show Lane, laneChoose, inlineContainer, inlineObject, MediaBroken, stripeNumber;
// Without prefix, for the same reason as `node_invitation.dart` above.
import 'package:mycelium/host_contact_seats.dart'
    show HostContactSeats, deviceOfContact;
// §16.2.5 groups and channels on the shared key (S407 channel step 2).
import 'package:cleona/core/service/shared_key_state.dart';
import 'package:mycelium/channel_chain.dart' as chain;
import 'package:mycelium/channel_entry.dart' as centry;
import 'package:mycelium/host_channel.dart' show HostChannel;
import 'package:mycelium/mailbox_channel.dart' show MailboxChannel;
// Lane 3 of §9.4 (S398 P2b, `cleona_service_bulk.dart`).
import 'package:mycelium/mailbox_bulk.dart' show MailboxBulk;
import 'package:mycelium/bulk_announce.dart'
    show
        BulkAnnouncement,
        bulkAnnounceUnpack,
        bulkAnnouncePack,
        kAnnouncePreviewAtMost;
import 'package:mycelium/bulk_piece.dart'
    show bulkTag, tagHex, kTtlMedia, kTagLength, kHoldersAtMost, transferKeyDraw;
import 'package:mycelium/bulk_place.dart' show BulkPlaced;
// Lane 2 of §9.4 (§17.6, S398 P3b, `cleona_service_stream.dart`).
import 'package:mycelium/mailbox_stream.dart' show MailboxStream;
import 'package:mycelium/stream_receive.dart' show StreamFallback;
import 'package:mycelium/card_address.dart' show CardAddress;
// B-4b (D-39, D-40, `cleona_service_enrolment.dart`).
import 'package:cleona/core/recovery/enrolment_content.dart';
import 'package:mycelium/enrol_window.dart' as mycelium show EnrolWindow;
import 'package:mycelium/enrol_wait.dart' as mycelium show EnrolWait;
import 'package:mycelium/node_enrolment.dart' show NodeEnrolment;
import 'package:mycelium/node_first_contact_box.dart' show NodeFirstContactBox;
import 'package:mycelium/host_reopen.dart' show HostReopen;
import 'package:mycelium/own_entries.dart' show cardOwnAddresses;
import 'package:mycelium/pair.dart' show dayValue, utcDay;
import 'package:mycelium/memory.dart' show kFileMailbox;
import 'package:mycelium/memory_group_pair.dart' show kFileGroupPairs;
import 'package:mycelium/memory_first_contact.dart' show kFileFirstContact;

// Re-export types so existing imports still work
export 'package:cleona/core/service/service_types.dart';

// The ten `cleona_service_v3_*.dart` parts fell with the CUT
// (31.08.2026, 4 022 lines). What of it was NOT V3 stands in
// `cleona_service_pure.dart` — the cut was file-granular, and that is
// justified there.
part 'cleona_service_pure.dart';
part 'cleona_service_receive.dart';
part 'cleona_service_recovery.dart';
part 'cleona_service_update.dart';
part 'cleona_service_contact_request.dart';
part 'cleona_service_media.dart';
part 'cleona_service_identity.dart';
part 'cleona_service_state.dart';
part 'cleona_service_msgstate.dart';
part 'cleona_service_identity_deletion.dart';
part 'cleona_service_lockout.dart';
part 'cleona_service_deviceset.dart';
part 'cleona_service_recovery_bundle.dart';
part 'cleona_service_mycelium.dart';
part 'cleona_service_own_line.dart';
part 'cleona_service_kem_line.dart';
part 'cleona_service_bulk.dart';
part 'cleona_service_stream.dart';
part 'cleona_service_transfer.dart';
part 'cleona_service_image_again.dart';
part 'cleona_service_group_pairs.dart';
part 'cleona_service_file_order.dart';
part 'cleona_service_enrolment.dart';
part 'cleona_service_deletion_marks.dart';
part 'cleona_service_conversation_end.dart';
part 'cleona_service_reconcile_source.dart';
part 'cleona_service_catch_up.dart';
part 'cleona_service_catch_up_source.dart';
part 'cleona_service_group_gate.dart';
part 'cleona_service_channel_reactions.dart';
part 'cleona_service_channel_pairs.dart';
part 'cleona_service_channel_list.dart';
part 'cleona_service_group_list.dart';
part 'cleona_service_group_announcement.dart';
part 'cleona_service_group_profile.dart';
part 'cleona_service_shared_key.dart';
part 'cleona_service_shared_key_keys.dart';
part 'cleona_service_shared_key_post.dart';
part 'cleona_service_shared_key_take.dart';
part 'cleona_service_pair_tag.dart';
part 'cleona_service_missed_call.dart';
part 'cleona_service_own_ring.dart';
part 'cleona_service_shared_settings.dart';

// `AppFrameDispatchOutcome` STOOD HERE — REMOVED ON 2026-09-03.
//
// The enum was the return value of
// `CleonaService.handleIncomingApplicationPacket` and controlled the
// multi-identity loop in `service_daemon.onApplicationFramePayload`
// (§2.4 step 9). BOTH ends fell with the CUT of 2026-08-31:
// the V3 receive entry point (justification in `cleona_service_receive.dart`,
// header of the extension `ReceivePathOps`) and the callback of the deleted
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

// `CallVideoOffReason` stood here. It lives in `service_types.dart` since
// S399, because `call_service.dart` (the sender side of §17.5) names it and
// must not import this file; the export of `service_types.dart` above keeps
// every existing `import … cleona_service.dart show CallVideoOffReason`.

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
  /// It is now wired via the wire counters of the mycelium node, read on
  /// looking in [getNetworkStats], not booked via callback (justification
  /// at `NetworkStatsCollector.noteNodeCounters`).
  final NetworkStatsCollector statsCollector = NetworkStatsCollector();

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

  // Receive-side dedup lives in the identity's store since S403: the
  // `received_ids` table, keyed on the 8-byte DELIVERY identifier
  // (`cleona_service_receive.dart`, §20.2). Nothing of it lives in this
  // process any more — the ring that stood here (`_processedMessageIds`,
  // 4 096 entries, keyed on the 16-byte app message id) fell short of the
  // memory's span in both directions and is gone.

  /// Finding 1 (§8.1): inner.messageId-hex of frames whose DELIVERY_RECEIPT was
  /// deliberately suppressed (silent CR drop, F12-A deadlock fix).
  /// `_suppressReceiptForCurrentFrame` is frame-local and therefore invisible
  /// to the dedup branch in `cleona_service_receive.dart`, which runs BEFORE
  /// dispatch and re-acks unconditionally. An AckTracker L1 retry replays the
  /// SAME inner messageId (`refreshTimestampAndSign` renews only timestamp +
  /// outer sigs), so the retry would hit dedup and emit exactly the receipt
  /// the drop suppressed — the sender sets `lastAckedAt`, its CR retry loop
  /// skips 24h, and the deadlock is back. Same FIFO cap semantics as before.
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
  /// list of identities and the profile directory itself
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
  @override
  void Function(CallUnavailableReason reason, String diagnostic)?
      onCallUnavailable;

  /// IPC push: immediate read-receipt notification (bypasses state_changed debounce).
  void Function(String conversationId, String messageId)? onReadReceiptReceived;

  @override
  void Function(String conversationId, String messageId, TransferPhase phase,
      int percent)? onMediaTransferProgress;

  /// The running lane 3 transfers and their last progress (§22.5.1),
  /// bounded in `cleona_service_bulk.dart`.
  final Map<String, ({TransferPhase phase, int percent})> _transferProgressMap =
      {};

  /// Announced lane 3 objects of this identity: hex tag -> entry (the
  /// memory image of the store area `kBulkIncomingArea`).
  final Map<String, Map<String, dynamic>> _bulkIncoming = {};

  /// Q1: held mycelium receipts of lane 3 announcements whose bubble does
  /// not exist yet (app message id -> receipt identifier), bounded.
  final Map<String, String> _bulkReceiptsHeld = {};

  /// Lane 2 (§17.6 "Cascade and windows"): how long the sender waits for the
  /// recipient's request after the announcement — 60 s for an announcement
  /// that reached the recipient directly, [streamRequestWaitPlaced] in all
  /// for one delivered via the post box (the delivery layer marks it placed,
  /// `cleona_service_stream.dart`, S408-LEBENSLAUF P21). The application's
  /// limits of §9.3, no repeat. A probe may shorten them; nothing else sets
  /// them.
  Duration streamRequestWait = const Duration(seconds: 60);
  Duration streamRequestWaitPlaced = const Duration(minutes: 20);

  /// Lane 2 candidates in place of `MailboxStream.streamCandidates` — for
  /// probes on loopback, where no neighbour has evidenced reachability
  /// (§11.8a) and the ring order of §17.6 cannot be staged.
  @visibleForTesting
  List<CardAddress> Function()? streamCandidatesForTesting;

  /// The production seeding of the two system channels, which otherwise
  /// only runs in `startService()` — for probes that do not start the
  /// network.
  @visibleForTesting
  void seedSystemChannelsForTesting() => _seedSystemChannels();

  /// The state a fallen-back stream leaves (§17.6, S407 M-2), staged for
  /// probes without driving a lane 2 attempt to its give-up: the sender
  /// places only these stripes on a fresh lane 3 run, the recipient records
  /// them as the ones it named when it gave up — and keeps nothing else, as
  /// if the pieces it kept were lost (D-34 exception,
  /// `cleona_service_image_again.dart`).
  @visibleForTesting
  Set<int>? streamRemainderForTesting;

  /// Lane 2 at the sender: announced transfers waiting for their request,
  /// hex tag -> state (`cleona_service_stream.dart`), bounded.
  final Map<String, _StreamOut> _streamOut = {};

  /// Lane 2 at the recipient: a holder list that arrived before its
  /// announcement (hex tag -> lane 3 announcement), bounded.
  final Map<String, Uint8List> _streamHoldersEarly = {};

  /// ONE stream at a time per node (`StreamSender` keeps one run).
  Future<void> _streamTurn = Future<void>.value();

  /// S398-W1: lane 2/3 transfers running in THIS process (message ids) —
  /// the resume at an edge leaves them alone (`cleona_service_transfer.dart`).
  final Set<String> _transfersRunning = {};

  /// S398-W1: sent transfers by hex tag (memory image of `kMediaSentArea`).
  final Map<String, Map<String, dynamic>> _mediaSent = {};

  /// D-34: the file of a message is completely in the network — streamed to
  /// the end or placed with holders. For W5 ("Nothing overtakes a file");
  /// the state is also queryable (`mediaInNetwork`).
  void Function(String conversationId, String messageId)? onMediaInNetwork;

  /// S398-W5 (§9.4 "Nothing overtakes a file"): the user message kinds that
  /// keep their writing order behind a file — everything that appears in a
  /// conversation or refers to something there. Receipts, typing, the
  /// transfer's own control messages (request, offer, holders, abort) and
  /// all infrastructure are not in it: they belong to no writing order.
  static const kFileOrderKinds = <proto.MessageType>{
    proto.MessageType.MT_TEXT,
    proto.MessageType.MT_MEDIA_INLINE,
    proto.MessageType.MT_MEDIA_ANNOUNCE,
    proto.MessageType.MT_VOICE_MESSAGE,
    proto.MessageType.MT_REPLY,
    proto.MessageType.MT_REACTION,
    proto.MessageType.MT_EDIT,
    proto.MessageType.MT_DELETE,
    proto.MessageType.MT_CHANNEL_POST,
    proto.MessageType.MT_POLL_CREATE,
    proto.MessageType.MT_CALENDAR_INVITE,
  };

  /// S398-W5: the waiting line of every leg, "conversation:recipient" ->
  /// slots in writing order (memory image of `kFileOrderArea`, loaded on
  /// first use).
  final Map<String, List<Map<String, dynamic>>> _fileOrder = {};
  bool _fileOrderLoaded = false;

  /// S398-W5: wire identifiers of messages waiting in a line — they count as
  /// `resting` in the aggregate of their message (§9.1).
  final Set<String> _fileOrderWaiting = {};

  /// S398-W5: lines being handed on right now, and those to look at again.
  final Set<String> _fileOrderDraining = {};
  final Set<String> _fileOrderAgain = {};

  /// S398-W5: wire identifier -> the 8-byte file identifier the frame of that
  /// message carries (`_innerFrame` takes it once).
  final Map<String, Uint8List> _fileOrderAfterFile = {};

  /// S398-W5: hex tags of incoming files already asked for because a message
  /// after them came (once per file and run, bounded).
  final LinkedHashSet<String> _fileOrderAsked = LinkedHashSet<String>();

  @override
  ({TransferPhase phase, int percent})? mediaTransferProgressOf(
          String messageId) =>
      _transferProgressMap[messageId];

  /// Android: post a system notification for incoming messages (set by Flutter app).
  Future<void> Function(String title, String body, String conversationId)? onPostNotificationAndroid;

  /// Desktop: post a system notification (set by the daemon, §22.6). Fired
  /// from the same place and behind the same gates as
  /// [onPostNotificationAndroid], with the same three values (§22.8 "What
  /// a system notification shows. The same on every platform"): title,
  /// text and the identifier under which a later notification replaces
  /// this one. Title and text go to the platform's notification service
  /// and to nothing else — never into a log line, never into the argument
  /// list of a program.
  void Function(String title, String body, String notificationId)?
      onPostDesktopNotification;

  /// The words of a notification the service writes itself (an invitation,
  /// [_announceInvitation]): the host sets the translation in the language
  /// the user chose — the app process through `AppLocale`, the daemon
  /// through `trayTranslate` in the language the GUI reported. Unset: the
  /// language of the operating system (`trayLocaleCode`).
  String Function(String key)? notificationWords;

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
  UpdateBinaryStore? _updateBinaryStore;
  BinaryUpdateManager? _binaryUpdateManager;
  BinaryHttpServer? _binaryHttpServer;
  InviteLinkService? _inviteLinkService;
  ForeignBinaryAcquirer? _foreignBinaryAcquirer;
  PhysicalTransferHelper? _physicalTransferHelper;
  // §19.6.2 — periodic housekeeping on the fragment store (prunes
  // superseded versions + enforces the platform storage budget).
  Timer? _binaryGcTimer;
  Timer? _registryRepublishTimer;
  InviteLinkService? get inviteLinkService => _inviteLinkService;
  PhysicalTransferHelper? get physicalTransferHelper => _physicalTransferHelper;
  @override
  PollManager get pollManager => _polls.pollManager;

  /// §18.3.4 rule 3: whether the tally of [pollId] may be shown as final.
  /// Kept synchronous inside the service; the public interface is [Future]
  /// because the IPC client has to ask the daemon for its catch-up state.
  @override
  Future<bool> isPollFinal(String pollId) async => isPollTallyFinal(
        poll: pollManager.polls[pollId],
        catchUpLastCollection: catchUpLastCollection,
        hasOpenCatchUpRequests: catchUpHasOpenRequests,
        clock: catchUpClock,
      );

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

  // §4.5.4 fork of a contact's rotation chain (S398, E-A9)
  @override
  void Function(String contactNodeIdHex, String displayName)? onContactKeyFork;

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

  /// §26: fires whenever the twin-device list changes (add/remove/rename).
  /// GUI listens via IPC to refresh the Device Management screen.
  void Function()? onDevicesUpdated;

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
  // §5.5 receiver-side: per-sender PEER_STORE rate limit (max 10/hour).
  final Map<String, List<DateTime>> _peerStoreRateLog = {};
  // GM-2 (§9.1.4): track per-group last epoch for which a RESYNC_REQUEST was sent
  // to avoid flooding the owner. Key = groupIdHex, value = epoch that triggered it.
  final Map<String, int> _resyncRequestedAtEpoch = {};
  Timer? _keyRotationTimer;
  Timer? _expiryTimer;
  // Save throttle of the receipt-suppressed set (§8.1 finding 1): the
  // expiry tick writes it only every second tick, as before S403.
  int _suppressedReceiptSaveCounter = 0;
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
  // Guardian service (Shamir SSS): FALLEN with the CUT; its interface
  // stubs fell in S398 P1 (D-17).
  // Groups
  final Map<String, GroupInfo> _groups = {};
  // §21.5.4 (S403, V8): settings for a group the device does not hold yet
  // wait in the identity's store with the posts
  // (`cleona_service_group_gate.dart`) — nothing is kept in memory.
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

  // Update checking (Architecture Section 17.5.5)
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

  // Here stood the state of the V3 restore path (`RESTORE_BROADCAST` /
  // `RESTORE_RESPONSE`, types 30/31): sender rate limit, receiver acceptance
  // limit, two timers and the progress callback. Removed in S398 with the
  // path itself (finding R-1: a contact that signed a broadcast about itself
  // received every conversation of the receiver, also those with third
  // parties). v4_2 Appendix C: the restore broadcast is not yet restated for
  // the post box; the recovery bundle (§13.3) is the only way back after a
  // total loss until then. Report: `mycelium/berichte/S398-V3-RESTORE-RAUS.md`.

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
  // ── §14.4 transition window: FALLEN (S408-P23) ────────────────────
  //
  // Here stood `_rotationWindows`: per contact the OLD V4.1 pair line,
  // harvested until the contact had the new keys, at most 14 days. Its only
  // effect was registering that line in the V4.1 delivery register
  // (`v41Delivery`, set only by `attachV41`). In 4.2 `K_AB` rests on the
  // FOUNDING keys and "survives every rotation" (v4_2 §4.3), so there is no
  // old pair line; the 7 days under the previous day keys (§14.4) belong to
  // the post box (`mycelium/lib/post_box_proof.dart`). The rows a previous
  // 4.2 left in the area `rotation_windows` go at start
  // ([_rotationWindowRows]).

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

  /// The marks of deleted messages, by message identifier, oldest first
  /// (`cleona_service_deletion_marks.dart`).
  final Map<String, DeletionMark> _deletionMarks = {};
  bool _deletionMarksLoaded = false;

  /// The edits that wait for the message they name, by message identifier,
  /// oldest first — the pattern of [_deletionMarks] (§21.5.1: "an edit to
  /// a still-unknown message is buffered instead of discarded";
  /// `cleona_service_deletion_marks.dart`).
  final Map<String, PendingEditMark> _pendingEdits = {};
  bool _pendingEditsLoaded = false;

  /// v4_2 §14.4: "The identity asks under its previous day keys for
  /// **7 days** after the rotation … The limit is fixed and does not wait
  /// for the last contact" (S408 F-4; until then 14 days of v4_1).
  static const _lockoutDeadlineDays = 7;

  // ── §5.8 One-Shot-Outbox ─────────────────────────────────────────────
  // Messages that could NOT be placed into L3 (Erasure + S&F) because the
  // sender had 0 connectivity at send time.  Each entry holds the serialized
  // canonical NetworkPacket bytes plus routing metadata so the edge-triggered
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
  // task is carried by the V4.1 outbox (`localOutbox`, §21.2).

  /// §5.1 CR edge: minimum interval between two edge-triggered
  /// backoff shortenings for the same contact. Deliberately the same value as
  /// the throttle of the former outbox drain on inbound (fallen with
  /// `lib/core/tagline/`, S408-P23) — the same task (a frequently firing
  /// edge must not produce a send stream), hence the same order of
  /// magnitude.
  static const Duration _crEdgeShortenGate = Duration(seconds: 60);

  /// S406-CATCHUP: the membership update of each group still being sent —
  /// the next one waits for it ([_broadcastGroupUpdate]), so every member
  /// is handed the updates of a group in the order of their epochs.
  final Map<String, Future<void>> _groupUpdateSending = {};
  /// §16.2.4: the owner's pending totals per channel, and the one timer per
  /// channel a pending round arms (`cleona_service_channel_reactions.dart`).
  final Map<String, ChannelReactionRound> _channelReactionRounds = {};
  final Map<String, Timer> _channelReactionTimers = {};

  /// The clock of §16.2.4 — the ten minutes of a round and the times in the
  /// totals. A probe moves it instead of waiting.
  @visibleForTesting
  DateTime Function() channelReactionClock = DateTime.now;

  /// §16.2.2 (S407 channel step 1): `true` makes every private channel run
  /// as before the short list — a probe measures old against new with it.
  @visibleForTesting
  bool channelShortListOff = false;

  /// A probe's sink for the payload bytes of membership legs per recipient
  /// (`cleona_service_channel_list.dart`); `null`: not counted.
  @visibleForTesting
  Map<String, int>? channelListBytes;

  /// A probe's stand-in for a v4.2.3-beta subscriber (D-21): the channel
  /// paths read exactly what 4.2.3 reads — the short list as the whole
  /// list, no change message, no fields of a leaving, no acceptance sent.
  /// The rest of those paths is unchanged since `398a6e40` (report
  /// `S407-KANALSCHRITT1.md` §2).
  @visibleForTesting
  bool channelReceiveAs423 = false;

  /// A probe's stand-in for a v4.2.3-beta second device in Type 8 (D-21,
  /// Grundsatz 8): it takes only `transcriptionLanguage` from a received
  /// SETTINGS_CHANGED and discards the rest, and it sends the language
  /// without a time — the code of
  /// `398a6e40:lib/core/service/cleona_service.dart:9844-9859` and of
  /// `398a6e40:lib/core/service/cleona_service_own_line.dart`
  /// (`setTranscriptionLanguage`).
  @visibleForTesting
  bool sharedSettingsAs423 = false;

  /// §16.2.2 (S407 group list): `true` makes every group send its membership
  /// changes as before — the whole list to every member; a probe measures
  /// old against new with it.
  @visibleForTesting
  bool groupListAsChangesOff = false;

  /// A probe's sink for the payload bytes of group membership legs per
  /// recipient (`cleona_service_group_list.dart`); `null`: not counted.
  @visibleForTesting
  Map<String, int>? groupListBytes;

  // ── §16.2.5 groups and channels on the shared key (S407 channel step 2,
  //    `cleona_service_shared_key*.dart`) ─────────────────────────────────
  final Map<String, SharedKeyState> _sharedKeys = {};
  final Map<String, (int, int)> _capabilities = {};
  bool _sharedKeysLoaded = false;
  final Set<String> _skCollecting = {};

  /// A collection asked for while one of the same group or channel runs:
  /// one more run after it, with every object asked for meanwhile
  /// (`_skCollect`). One mark per group or channel, no clock, no count.
  final Map<String, ({String reason, Set<String> objects, Completer<void> done})>
      _skCollectAgain = {};
  final Set<String> _skDepositing = {};

  /// The post line of a group or channel on the shared key (S410
  /// follow-up): while a post with a link waits for its preview, the posts
  /// written after it are sealed and kept (`kSharedKeyOutArea`) but neither
  /// nudged nor deposited — they go after it, in writing order. Memory
  /// only: after a process end every kept post is deposited at the next
  /// edge as before (`_skOutResume`), the link post without its preview.
  final Map<String, List<_SkWaiting>> _skLine = {};
  final Map<String, Uint8List> _skObjectBytes = {};

  /// A probe's stand-in for a 4.2 version that does not build §16.2.5: no
  /// capability bit 2, no keys taken, no nudge opened — pairwise legs only.
  @visibleForTesting
  bool sharedKeyOff = false;

  /// A probe sets the device class of the capability notice.
  @visibleForTesting
  int? sharedKeyDeviceClass;

  /// A probe's sink for the bytes of entries and key deliveries.
  @visibleForTesting
  Map<String, int>? sharedKeyBytes;

  /// The clock of §16.2.5 — the UTC day of the key chain. A probe moves it.
  @visibleForTesting
  DateTime Function() sharedKeyClock = DateTime.now;

  /// A probe holds a collection run open after its keeper answered, so a
  /// second request for the same group or channel meets a running one.
  @visibleForTesting
  Future<void> Function(String gid)? sharedKeyCollectHeld;

  // §5.5b First-CR ACK gate: after sendToDevice, wait 15s for a
  // DELIVERY_RECEIPT before firing FIRST_CR_STORE to seed peers.
  // Key = messageIdHex of the First-CR ApplicationFrame.
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
    // A Plane D handed over before this point (S398-W2) is applied now.
    final planeD = _planeDBeforeStart;
    _planeDBeforeStart = null;
    if (planeD != null) _calls.attachPlaneD(planeD);
    _calls.onIncomingCall = (info) => onIncomingCall?.call(info);
    _calls.onCallAccepted = (info) => onCallAccepted?.call(info);
    // A call that ends forgets what its peer said about its video (§17.5), so
    // nothing outlives the call it describes.
    // ... and its call signals end with it (§17.2, `_myceliumCallEnded`).
    _calls.onCallRejected = (info, reason) {
      clearCallMediaStates(info.callId);
      _myceliumCallEnded();
      onCallRejected?.call(info, reason);
    };
    _calls.onCallEnded = (info) {
      clearCallMediaStates(info.callId);
      _myceliumCallEnded();
      onCallEnded?.call(info);
    };
    // §17.2: an outgoing call that ended unanswered — the missed-call
    // message (`cleona_service_missed_call.dart`).
    _calls.onMissedCall = (peerHex, callId, isVideo) =>
        unawaited(_missedCallSend(peerHex, callId, isVideo));
    // §17.2 in a group call: a member's invitation ended unanswered — the
    // missed-call message as a group message to that member.
    _calls.onMissedGroupCall = (memberHex, groupIdHex, callId) =>
        unawaited(_missedGroupCallSend(memberHex, groupIdHex, callId));
    _calls.onCallUnavailable =
        (reason, diagnostic) => onCallUnavailable?.call(reason, diagnostic);
    _calls.onOwnVideoStateChanged = _announceOwnVideoState;
    _calls.onIncomingGroupCall = (info) => onIncomingGroupCall?.call(info);
    _calls.onGroupCallStarted = (info) => onGroupCallStarted?.call(info);
    _calls.onGroupCallEnded = (info) {
      _myceliumCallEnded();
      onGroupCallEnded?.call(info);
    };
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
    // no social recovery any more (D-17); the public guardian members fell
    // in S398 P1.

    // Load contacts
    _loadContacts();

    // Init local device (§26 Multi-Device)
    _initLocalDevice();

    // S362: one-time sweeper BEFORE any reading of the affected files.
    // It must run before `_loadProfilePicture`, because that from now on only
    // knows the ciphertext — without the run before it an existing
    // profile would have lost its picture, its description and its transcripts
    // (they would continue to lie in plaintext on the disk, only unused).
    _sweepPlaintextUserContent();

    // S403: two settings of the DEVICE lay in the store of each identity
    // until then; they lie in the device database now. What the store of
    // this identity still carries under the old areas goes — before the two
    // loads further down, which read the device database only.
    _removeSupersededDeviceSettings();

    // S401: decrypted intermediate files a crash left behind — the WAV of
    // a transcription, an attachment on its way to or from the archive
    // share. Their `finally` did not run; this start edge is the one place
    // that comes past them again. Before the archive manager and the
    // transcription are set up, so none of their operations runs yet.
    final leftBehind =
        TransientFiles.sweepServiceAtStart(profileDir: profileDir);
    if (leftBehind > 0) {
      _log.info('Removed $leftBehind decrypted intermediate file(s) an '
          'interrupted run left behind');
    }

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

    // When the profile last went to the contacts, and whether a change
    // still waits for the hour of §15.8 to pass
    _loadProfileUpdateState();

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

    // The multi-interface switch is gone (S408-LEBENSLAUF P22): §12.7 gives
    // the network layer exactly three switches, and this one was stored
    // and shown but applied nowhere (gap G-6). Its device row goes.
    _multiInterfaceRowDrop();

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
    // No start-time reset of media states (S399 P2-7): a waiting lane 2/3
    // file is resumed at the mailbox attach (`_bulkResume`), and one without
    // an entry is `failed` there. A received file whose local copy is gone
    // stays `completed` — it was delivered; re-offering it would need the
    // sender to send it again (§9.3), and an archived original (§21.6) is
    // missing on purpose.

    // Seed system channels (§9.5) — MUST run after _loadConversations() so the
    // real chats are already in `conversations`; seeding then only adds the two
    // system-channel entries if missing and the subsequent save persists the
    // FULL set. (Running this before the load destroyed all chats — see note
    // next to _loadChannels above.)
    _seedSystemChannels();
    // §16.7 (S407 SK-4): the own 4.2.3 records go under the report pseudonym.
    _systemChannelsResignLegacy();

    // After load: surface the persisted unreadCount to the system badge so
    // the Launcher-Badge matches the on-disk truth right after daemon-start.
    _updateBadgeCount();

    // Load the receipt-suppressed message ids (§8.1 finding 1). The
    // receive-side dedup itself lives in the identity's store since S403
    // (`received_ids`, §20.2) and needs no loading here.
    _loadSuppressedReceiptIds();

    // §21.2: the parking compartment (`localOutbox`). It is drained when the
    // mailbox attaches (`_myceliumParkedHandedOver`), NOT on this start.
    loadLocalOutbox();
    _loadMailboxTransition();
    _membershipResendRows(); // S408 P19: the app's queue is gone, its rows go
    _rotationWindowRows(); // S408 P23: the V4.1 old pair lines are gone
    _channelReactionRoundsLoad(); // §16.2.4: a pending round keeps its time

    // V3.1.44: Migrate self-entries from deviceNodeId to userIdHex in groups/channels/messages.
    // §26 Phase 2 temporarily stored deviceNodeId as member keys, but service-level
    // identification must use the stable userId (same across all devices).

    // Conversations that have ended and are still in the store (the stock
    // of an earlier build, S401) leave the profile now.
    _sweepOrphanConversations();

    // Posts that wait for the invitation into their group (§16.2.2): the
    // bounds of §20.2 are applied here and where a post is put in — never
    // on a clock.
    _groupWaitingAtStart();

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

    // §26.6.2 package C: who has the emergency rotation follows the
    // delivery state of its broadcast, read at the edges start and network
    // change — no clock of its own (S408-LEBENSLAUF P20, §11.3a, D-47).
    _keyRotationFromDelivery();

    // Message expiry: check every 30 seconds for expired messages
    // E-7: the lockout transition rides along on THIS tick instead of opening
    // its own timer (working rule #5). Once immediately, so that a
    // restart within the deadline does not close the expired lockout only 30 s
    // later — and so that the loaded set is held against the clock
    // at least once.
    _sweepLockouts();
    _expiryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkMessageExpiry();
      _sweepLockouts();
      // §4.5.4/S363 on THE SAME tick — no second rhythm
      // (working rule 5). Costs nothing as long as the gate is not armed.
      _checkRotationsTorDeadline();
      _suppressedReceiptSaveCounter++;
      if (_suppressedReceiptSaveCounter >= 2) {
        _suppressedReceiptSaveCounter = 0;
        _saveSuppressedReceiptIds();
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

    // The hourly LD-9 delegation renewal check is gone with the V3 pairing
    // (B-4b): there is no delegation certificate (§14.6.2).

    // Stats wiring: **HISTORIC.** Here it said "lives on CleonaNode now
    // (single shared collector across all identities)". `CleonaNode` was
    // deleted with the CUT of 2026-08-31. The collector
    // (`NetworkStatsCollector`, `lib/core/stats/network_stats.dart:378`)
    // has been wired at the composition point since S357 — `service_daemon.dart`
    // and `main.dart` pass the bare byte callbacks into
    // `V41Node.start` (`tagline/v41_node.dart`, fallen S408-P23). The reason stays
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
    // S405 A-6: download progress reaches the surface through the
    // interface callback, so the desktop GUI (another process) sees it too.
    _voiceTranscription!.onDownloadStatusChanged =
        (_) => _fireTranscriptionStatus(force: true);
    _voiceTranscription!.onDownloadProgress =
        (_) => _fireTranscriptionStatus();
    // D-64: "ready" arrives only after the model's SHA-256 check, which
    // runs after start — the surface hears it here.
    _voiceTranscription!.onReadinessChanged =
        (_) => _fireTranscriptionStatus(force: true);
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
    // From here on a stored setting takes effect at once
    // (`_archiveSettingChanged`); before the start of the service there is
    // nothing to change — this method reads it.
    _archiveStarted = true;
    try {
      // S366: from the area `archive_config` of the storage instead of from
      // `archive_config.json`. The same reason as with the transcription
      // one screen page further up — a reader that stayed hanging on the
      // file would silently leave out the archive after the switch.
      final config = ArchiveConfig.readFrom(store);
      if (config == null) return;
      if (!config.enabledByDefault || config.archiveHost.isEmpty) return;

      final transport = await _archiveTransportFor(config);

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

  /// Probes only: the archive set up as `startService` does it
  /// (`_initArchive`) — a probe of "a stored setting takes effect at once"
  /// cannot run `startService` without a network.
  @visibleForTesting
  Future<void> archiveStartForTesting() => _initArchive();

  Future<ArchiveTransport> _archiveTransportFor(ArchiveConfig config) async {
    final transport = ArchiveTransport.forProtocol(config.defaultProtocol,
        profileDir: profileDir);
    await transport.connect(
      host: config.archiveHost,
      path: config.archivePath,
      username: config.archiveUsername,
      password: config.archivePassword,
      port: config.archivePort,
    );
    return transport;
  }

  /// `true` once `startService` has set the archive up (`_initArchive`).
  bool _archiveStarted = false;

  /// The manager of an archive the user switched off while the service
  /// runs. Switched on again, it goes on with its index — a second manager
  /// beside a run of the first that has not ended yet would upload the same
  /// medium twice.
  ArchiveManager? _archiveOff;

  /// Changes of the setting one after the other.
  Future<void> _archiveSettingChain = Future<void>.value();

  /// The stored setting takes effect now (S410 follow-up, owner 29.10.2026
  /// "A": without a restart of daemon or app; both surfaces — the desktop
  /// through `archive_settings_set`, Android/iOS in-process — come here
  /// through [setArchiveSettings]). The same three states as at the start
  /// of the service (`_initArchive`): switched off → no manager; switched
  /// on → a manager with the setting; the share changed → its transport
  /// (`ArchiveManager.applySetting`).
  Future<void> _archiveSettingChanged() {
    final next = _archiveSettingChain.then((_) async {
      if (!_archiveStarted || _disposed) return;
      final config = ArchiveConfig.readFrom(store);
      final on = config != null &&
          config.enabledByDefault &&
          config.archiveHost.isNotEmpty;
      final active = _archiveManager;
      if (!on) {
        if (active == null) return;
        await active.suspend();
        _archiveManager = null;
        _archiveOff = active;
        _log.info('ArchiveManager switched off by the setting');
        return;
      }
      final mgr = active ?? _archiveOff;
      if (mgr == null) {
        await _initArchive();
        return;
      }
      final c = mgr.config;
      final sameShare = c.defaultProtocol == config.defaultProtocol &&
          c.archiveHost == config.archiveHost &&
          c.archivePath == config.archivePath &&
          c.archiveUsername == config.archiveUsername &&
          c.archivePassword == config.archivePassword &&
          c.archivePort == config.archivePort;
      mgr.applySetting(config,
          transport: sameShare ? null : await _archiveTransportFor(config));
      if (active == null) {
        _archiveOff = null;
        _archiveManager = mgr;
        // Loading IN the callback, as in `_initArchive`.
        await mgr.startScheduler(
          conversationSource: () {
            ensureAllLoaded();
            return conversations;
          },
        );
        _log.info('ArchiveManager switched on again by the setting');
      }
    });
    _archiveSettingChain = next.catchError((Object e) {
      _log.warn('Archive setting not taken over: $e');
    });
    return _archiveSettingChain;
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

  // ── Media archive: the setting (§21.6, S410 E10) ───────────────────────
  //
  // One implementation for both surfaces: Android/iOS call it in-process,
  // the desktop surface through `archive_settings_get`,
  // `archive_settings_set` and `archive_test_connection`. Until S410 the
  // screen read and wrote the store itself, which it can only in-process —
  // on Linux and Windows the setting was never stored (gui-23 15).

  @override
  Future<ArchiveSettingsView?> getArchiveSettings() async {
    try {
      return ArchiveSettingsView.of(ArchiveConfig.readFrom(store));
    } catch (e) {
      // Unreadable is not "never configured": the screen must not write
      // defaults over a setting that exists.
      _log.warn('Archive setting could not be read: $e');
      return null;
    }
  }

  @override
  Future<bool> setArchiveSettings(ArchiveConfig config,
      {String? password}) async {
    try {
      // Read-modify-write on the STORED record: the pin and the networks
      // belong to the service (the archive run pins, the capture buttons
      // go through the service), the password stays unless the user typed
      // one. A store that cannot be read is not written (fails closed).
      final stored = ArchiveConfig.readFrom(store);
      config
          .withShareIdentity(stored?.shareIdentity)
          .withAllowedNetworks(stored?.allowedNetworks ?? const [])
          .withArchivePassword(password == null
              ? stored?.archivePassword
              : (password.isEmpty ? null : password))
          .writeTo(store);
      _log.info('Archive setting stored: ${config.defaultProtocol.name}, '
          'enabled=${config.enabledByDefault}, share password '
          '${password == null ? 'kept' : password.isEmpty ? 'removed' : 'replaced'}');
      // It takes effect now, not at the next start (S410 follow-up).
      await _archiveSettingChanged();
      return true;
    } catch (e) {
      _log.warn('Archive setting could not be stored: $e');
      return false;
    }
  }

  @override
  Future<({bool reachable, ShareIdentityState? identity})?>
      testArchiveShare() async {
    // S394: a pinned share is identified before it is tested (§21.6) —
    // see `testArchiveConnection`. The password goes into the transport
    // here, in the service, and nowhere else.
    final config = ArchiveConfig.readFrom(store);
    if (config == null || config.archiveHost.isEmpty) return null;
    return testArchiveConnection(config, profileDir: profileDir);
  }

  // ── Retrieval of an archived original (§21.6, S398-W4) ─────────────
  //
  // ONE implementation for both surfaces. Until S398 the lookup lived only
  // in `ipc_server.dart` (`case 'archive_retrieve'`), and the in-process
  // surface (Android/iOS) had no way to it at all; the desktop surface had
  // the command but no client method. The server now calls this.

  @override
  void Function(String messageId, int bytesTransferred, int totalBytes)?
      onArchiveRetrieveProgress;

  @override
  void Function(String messageId, bool ok)? onArchiveRetrieveDone;

  @override
  Future<({ArchiveRetrievalStart start, String? error})>
      requestArchiveRetrieval(String messageId) async {
    final mgr = _archiveManager;
    if (mgr == null) {
      return (start: ArchiveRetrievalStart.unavailable,
          error: 'Archive not active');
    }
    // The target is the path the MESSAGE points to (`media_store.dart`,
    // S362): `filePath` is the identifier of the attachment, not the
    // statement "lies here". `ensureAllLoaded`, because what is sought is an
    // OLD message — without loading the loop would silently find nothing.
    ensureAllLoaded();
    String? path;
    for (final conv in conversations.values) {
      for (final m in conv.messages) {
        if (m.id == messageId) {
          path = m.filePath;
          break;
        }
      }
      if (path != null) break;
    }
    if (path == null || path.isEmpty) {
      return (start: ArchiveRetrievalStart.unavailable,
          error: 'No local path for message $messageId');
    }
    // The question is asked BEFORE the call, and only to colour the answer
    // and to hang the completion on the FIRST requester only. The call
    // itself ALWAYS goes out: the binding latch is the manager's.
    final running = mgr.isRetrieving(messageId);
    final run = mgr.retrieveToMediaStore(
      messageId,
      path,
      onProgress: (mid, sent, total) =>
          onArchiveRetrieveProgress?.call(mid, sent, total),
    );
    if (!running) {
      unawaited(run.then((r) {
        _lastArchiveRetrieval[r.messageId] = r;
        onArchiveRetrieveDone?.call(r.messageId, r.ok);
        // The tier changed in the archive view of the message.
        onStateChanged?.call();
      }));
    }
    return (
      start: running
          ? ArchiveRetrievalStart.alreadyRunning
          : ArchiveRetrievalStart.started,
      error: null,
    );
  }

  @override
  Future<Uint8List?> getArchivePreview(String messageId) async =>
      _archiveManager?.previewOf(messageId)?.bytes;

  /// The last finished retrieval per message — the IPC server sends it as
  /// the payload of `archive_retrieve_done` (bytes, tier, reason).
  final Map<String, ArchiveRetrievalResult> _lastArchiveRetrieval = {};

  /// Reads (and forgets) the last result for [messageId].
  ArchiveRetrievalResult? takeArchiveRetrievalResult(String messageId) =>
      _lastArchiveRetrieval.remove(messageId);

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

  /// Who is typing — an indicator counts 5 s, and its end is announced by
  /// itself (S405 A-3, `typing_tracker.dart`).
  late final TypingTracker _typing =
      TypingTracker(onChanged: () => onStateChanged?.call());

  /// Returns true if the given contact is currently typing (within last 5 seconds).
  bool isTyping(String nodeIdHex) => _typing.isTyping(nodeIdHex);

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

  /// Send a media file (image, file, etc.) to a contact or group.
  /// Below 256 KB as ONE MEDIA_INLINE message (§9.4 lane 1). From 256 KB on
  /// lane 3 (holders, `cleona_service_bulk.dart`) — only with [consent]
  /// (§9.4 "Consent"); without it nothing is sent and the message ends
  /// `failed`. Lane 2 is not built (S398 P3).
  @override
  Future<UiMessage?> sendMediaMessage(String conversationId, String filePath,
      {bool consent = false}) async {
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
    // §16.2.2: in announcement mode only the owner and the admins post.
    if (isGroup && !_groupMayPost(conversationId, identity.userIdHex)) {
      _log.warn('sendMediaMessage refused: announcement mode, this identity '
          'is a member');
      return null;
    }

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
    // upgrade `sent → delivered` in `_handleDeliveryReceipt`. Mirrors
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
      // §16.2: a group post — file and voice message too — carries ONE post
      // identifier in every leg (lane 1 below, lane 3 in `_laneThree`).
      postId: isGroup || isChannel
          ? bytesToHex(SodiumFFI().randomBytes(kPostIdLength))
          : null,
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

    // Determine recipients — the ONE computation the resume of a lane 3
    // transfer uses too (`_mediaTargets`, `cleona_service_transfer.dart`).
    final targets = _mediaTargets(conversationId);
    if (targets == null) {
      _log.warn('sendMediaMessage: no recipients for convId=$conversationId '
          '(unknown group/channel, no post permission, or a contact that is '
          'not accepted; contacts loaded: ${_contacts.length})');
      return null;
    }
    final recipients = targets.recipients;

    // ── THE LANE CHOICE (§9.4, S398 P1) ─────────────────────────────
    //
    // First by size (`laneChoose` in mycelium, the one place that decides
    // it). Measured is the OBJECT that travels — `bytes`, i.e. including the
    // VoicePayload wrapper —, not the file: the container is built from it
    // and must stay below [mycelium.kInlineLimit].
    //
    // Nothing is known yet about the other side: from 256 KB the choice is
    // §9.4 "otherwise" — lane 3 —, unless the cascade of §17.6 finds the
    // recipient online and a volunteer (`cleona_service_stream.dart`, which
    // asks `laneChoose` again with what it found). A group always takes
    // lane 3 (§17.6 last paragraph).
    final lane = mycelium.laneChoose(length: bytes.length);
    _log.info('[E2E media-send-path] lane=${lane.name} '
        'objectSize=${bytes.length} fileSize=$fileSize '
        'recipients=${recipients.length} '
        'convId=${conversationId.substring(0, 8)}');
    var massLane = false;
    // GM-1 (§9.1.4): group/channel media must carry groupId + membership tag
    final mediaGroupId = targets.groupId;
    final mediaGmEpoch = targets.epoch;
    final mediaGmHash = targets.hash;
    if (lane == mycelium.Lane.inline) {
      // LANE 1: ONE ordinary message whose body is the striped object
      // (§9.4 "Reed-Solomon striped, placed like any other packet").
      final container = mycelium.inlineContainer(bytes);
      // The state like text (§9.1, F-3). 1:1: the display identifier is the
      // wire identifier. Group/channel: one wire identifier per member
      // (`fanoutLegs`), so that each receipt is attributed to its leg.
      final isFanout = isGroup || isChannel;
      // §16.2.5: on the shared key the object below 256 KB is deposited once
      // as its own entry with its post; members without the capability get
      // a leg as before.
      final pairwise = isFanout && msg.postId != null
          ? await _skServe(conversationId,
              type: proto.MessageType.MT_MEDIA_INLINE,
              payload: container,
              messageId: hexToBytes(msg.postId!),
              postId: hexToBytes(msg.postId!),
              contentMetadata: metadata,
              epoch: mediaGmEpoch,
              hash: mediaGmHash,
              msg: msg,
              object: container)
          : null;
      final sends = <(ContactInfo, Uint8List)>[];
      for (final recipient in recipients) {
        if (pairwise != null && !pairwise.contains(bytesToHex(recipient.nodeId))) {
          continue;
        }
        if (!isFanout) {
          sends.add((recipient, messageIdBytes));
          continue;
        }
        final legId = SodiumFFI().randomBytes(16);
        msg.fanoutLegs[bytesToHex(recipient.nodeId)] = bytesToHex(legId);
        sends.add((recipient, legId));
      }
      final legs = isFanout ? msg.fanoutLegs.values.toList() : <String>[tempId];
      // Index BEFORE sending, for the reason given in `sendTextMessage`.
      _applyOutgoingLegStatus(msg, legs);
      var handed = 0;
      for (final (recipient, wireId) in sends) {
        final ok = await sendToUser(
          recipientUserId: recipient.nodeId,
          messageType: proto.MessageType.MT_MEDIA_INLINE,
          payload: container,
          contentMetadata: metadata,
          messageId: wireId,
          groupId: mediaGroupId,
          groupMembershipEpoch: mediaGmEpoch,
          groupMembershipHash: mediaGmHash,
          postId: msg.postId == null ? null : hexToBytes(msg.postId!),
        );
        if (ok) {
          handed++;
          statsCollector.addMessageSent();
        }
      }
      _applyOutgoingLegStatus(msg, legs);
      // B-6 (S398-W1): no leg handed over is `failed` with its reason, not
      // a silent "done" (§22.5.1).
      if (handed == 0 && pairwise == null) {
        _mediaFail(msg, FailureReason.noRoute,
            'lane 1: no leg handed to the delivery layer');
      }
    } else if (!consent) {
      // §9.4 "Consent": lanes 2 and 3 are visible, linkable events (B-29);
      // without the user's consent for THIS file nothing is sent (§24.4.5).
      _mediaFail(msg, FailureReason.consentMissing,
          'lane ${lane.name}: consent missing (§9.4) — nothing sent');
    } else {
      massLane = true;
    }

    msg.thumbnailBase64 = thumbnail != null ? base64Encode(thumbnail) : null;
    persistMessage(conversationId, msg);
    _saveConversations();
    onStateChanged?.call();

    if (msg.status == MessageStatus.failed) return msg;
    // Lane 2 is worth trying (§9.4, §17.6): 1:1, from 256 KB up to `C` —
    // "would lane 2 apply if both were online and a volunteer there?".
    final streamWorth = massLane &&
        !isGroup &&
        !isChannel &&
        mycelium.laneChoose(
                length: bytes.length, bothOnline: true, volunteerThere: true) ==
            mycelium.Lane.streamed;
    if (massLane) {
      // NOTHING OVERTAKES A FILE (§9.4, D-34, S398-W5): the file takes its
      // place in the line of every leg — the wire identifier of each leg is
      // fixed here, `_laneThree` keeps it (`??=`).
      final fanout = isGroup || isChannel;
      final legs = <(String, String)>[];
      for (final r in recipients) {
        final hex = bytesToHex(r.nodeId);
        legs.add((
          hex,
          fanout
              ? (msg.fanoutLegs[hex] ??= bytesToHex(SodiumFFI().randomBytes(16)))
              : msg.id
        ));
      }
      if (fanout) persistMessage(conversationId, msg);
      if (_fileOrderFile(msg, legs, fanout: fanout)) {
        // A 1:1 file behind a file still on its way: its transfer starts
        // when its turn comes (`_fileOrderStart`), from this record.
        final r = _transferRecordNew(msg, bytes,
            lane: streamWorth ? 'stream' : 'mass',
            transferKey: transferKeyDraw(),
            metadata: proto.ContentMetadata.fromBuffer(metadata.writeToBuffer())
              ..clearThumbnail(),
            preview: _microPreview(thumbnail, mimeType));
        r['waiting'] = true;
        _transferRecordPut(r);
        _log.info('[E2E media-send-path] lane ${streamWorth ? 'streamed' : 'mass'} '
            'msgId=${msg.id.substring(0, 8)} waits behind an earlier file (§9.4)');
        return msg;
      }
    }
    if (streamWorth) {
      // LANE 2 runs detached: announce, wait for the recipient's request,
      // stream through a volunteer — or fall back to lane 3 under the same
      // `K_T` (`cleona_service_stream.dart`).
      _log.info('[E2E media-send-path] lane streamed msgId=${msg.id.substring(0, 8)} '
          'announcing ${bytes.length} B, waiting for the request');
      unawaited(_streamSend(
        msg: msg,
        object: bytes,
        recipient: recipients.single,
        metadata: proto.ContentMetadata.fromBuffer(metadata.writeToBuffer())
          ..clearThumbnail(),
        preview: _microPreview(thumbnail, mimeType),
        messageIdBytes: messageIdBytes,
      ));
      return msg;
    }
    if (massLane) {
      // LANE 3 runs detached: placing takes about 50 s per MB at `R_bulk`
      // (§9.4); the message stays `resting` until the announcement goes out
      // (`cleona_service_bulk.dart`). The file stays with the sender.
      _log.info('[E2E media-send-path] lane mass msgId=${msg.id.substring(0, 8)} '
          'placing ${bytes.length} B for ${recipients.length} recipient(s)');
      unawaited(_bulkSend(
        msg: msg,
        object: bytes,
        // The announcement carries the micro preview; the metadata travels
        // without the large thumbnail (up to 100 KB) next to it.
        metadata: proto.ContentMetadata.fromBuffer(metadata.writeToBuffer())
          ..clearThumbnail(),
        preview: _microPreview(thumbnail, mimeType),
      ));
      return msg;
    }
    _log.info('[E2E media-send-done] msgId=${msg.id.substring(0, 8)} '
        'filename=$filename size=$fileSize recipient=${conversationId.substring(0, 8)} '
        'lane=${lane.name}');
    return msg;
  }

  /// The micro preview of the offer — at most
  /// [kAnnouncePreviewAtMost] (969 B, "one cell").
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
    if (thumbnail.length <= kAnnouncePreviewAtMost) return thumbnail;
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
        if (bytes.length <= kAnnouncePreviewAtMost) return bytes;
      }
      _log.warn('Bulk offer: micro preview does not fit even at q=25 into '
          'one cell ($kAnnouncePreviewAtMost B) — offer without '
          'preview. The transfer runs anyway.');
      return null;
    } catch (e) {
      _log.warn('Bulk offer: micro preview cannot be built ($e) — '
          'offer without preview');
      return null;
    }
  }

  /// The user asks for an announced file (click on the bubble): lanes 2
  /// and 3 collect from the network what the announcement names (§9.4).
  ///
  /// There is no fetch on request. Until S399 a message without a lane 2/3
  /// entry fell through to the V3 path: `MT_MEDIA_REQUEST` to the sender,
  /// which read the file from its history and sent it again in chunks —
  /// "A file is never sent again" (§9.3, D-34). A message this identity can
  /// no longer collect is `failed` with its reason at once instead.
  @override
  Future<bool> acceptMediaDownload(String conversationId, String messageId) async {
    _log.info('[E2E media-accept-send] msgId=${messageId.substring(0, 8)} convId=${conversationId.substring(0, 8)}');
    // §9.4 "Loading images in a group or channel": an image on the shared
    // key shown as not loaded is collected from the keepers by this tap.
    final kept = _skAcceptDownload(conversationId, messageId);
    if (kept != null) return kept;
    // Lanes 2/3 (§9.4): collecting from the holders the announcement names.
    final mass = _bulkAcceptDownload(messageId);
    if (mass != null) return mass;
    final msg = _bulkMessage(conversationId, messageId);
    if (msg != null &&
        !msg.isOutgoing &&
        (msg.mediaState == MediaDownloadState.announced ||
            msg.mediaState == MediaDownloadState.downloading)) {
      _mediaFail(msg, FailureReason.holdersGone,
          'no lane 2/3 entry to collect from — a file is never sent again');
    } else {
      _log.warn('[E2E media-accept-send] nothing to collect: msg='
          '${msg != null ? "exists state=${msg.mediaState.name}" : "MISSING"}');
    }
    return false;
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
  /// V3 has no media-subtype enum — `MT_MEDIA_INLINE` covers
  /// image/video/audio/file uniformly. This helper produces the
  /// UI-side [UiMessageType] tag for the chat-card row only; the wire
  /// layer always emits `MT_MEDIA_INLINE`.
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
  /// IMAGE/VIDEO/GIF/FILE into `MT_MEDIA_INLINE`; voice has its own
  /// `MT_VOICE_MESSAGE`. `MT_MEDIA_REQUEST` carries
  /// request-the-upload semantics. `MT_REPLY` is classified as
  /// user-content.
  static bool _isUserMessage(proto.MessageType type) {
    switch (type) {
      case proto.MessageType.MT_TEXT:
      case proto.MessageType.MT_MEDIA_INLINE:
      case proto.MessageType.MT_VOICE_MESSAGE:
      case proto.MessageType.MT_MEDIA_ANNOUNCE:
      case proto.MessageType.MT_MEDIA_REQUEST:
      case proto.MessageType.MT_MEDIA_REJECT:
      case proto.MessageType.MT_MEDIA_CHUNK:
      case proto.MessageType.MT_REACTION:
      case proto.MessageType.MT_REPLY:
      case proto.MessageType.MT_EDIT:
      case proto.MessageType.MT_DELETE:
      case proto.MessageType.MT_CHANNEL_POST:
      case proto.MessageType.MT_CALENDAR_INVITE:
      case proto.MessageType.MT_CALENDAR_RSVP:
      case proto.MessageType.MT_CALENDAR_UPDATE:
      case proto.MessageType.MT_CALENDAR_DELETE:
      case proto.MessageType.MT_FREE_BUSY_REQUEST:
      case proto.MessageType.MT_FREE_BUSY_RESPONSE:
      case proto.MessageType.MT_POLL_CREATE:
      case proto.MessageType.MT_POLL_VOTE:
      case proto.MessageType.MT_POLL_VOTE_ANONYMOUS:
      case proto.MessageType.MT_POLL_REVOKE:
      case proto.MessageType.MT_POLL_UPDATE:
      case proto.MessageType.MT_POLL_SNAPSHOT:
      case proto.MessageType.MT_CHANNEL_REACTION_TOTALS:
      case proto.MessageType.MT_CHANNEL_REACTION_HANDOVER:
      // §17.2: an ordinary message in the conversation.
      case proto.MessageType.MT_CALL_MISSED:
        return true;
      default:
        return false;
    }
  }

  /// Test-only accessor for the private user-message classifier.
  /// Used by `test/smoke/smoke_reduced_mode.dart`. Not for production callers —
  /// the gate is enforced inside [handleMessage], not at call sites.
  static bool isUserMessageForTest(proto.MessageType type) => _isUserMessage(type);


  /// Sender-side edit window (§21.5.1), shared with the chat screen.
  static const int _defaultEditWindowMs = kSenderEditWindowMs;

  /// Receiver-side tolerance (§21.5.1): edits arriving more than 60 minutes
  /// after the original are rejected.
  static const int _receiverEditToleranceMs = 60 * 60 * 1000;

  /// The identifier a quote names on the wire for the message kept under
  /// [messageIdHex] in [conversationId] (§16.2): the post identifier of a
  /// group post, otherwise [messageIdHex] itself — also when the message is
  /// not here any more.
  String _referenceIdOf(String conversationId, String messageIdHex) {
    final conv = conversations[conversationId];
    if (conv == null) return messageIdHex;
    ensureLoaded(conversationId);
    for (final m in conv.messages) {
      if (m.id == messageIdHex) return m.referenceId;
    }
    return messageIdHex;
  }

  /// The message of [conversationId] a reference [idHex] from the wire means
  /// (§16.2): kept under that identifier, or a group post with that post
  /// identifier. Searched in the whole history (§21.4.1).
  UiMessage? _referredMessage(String conversationId, String idHex) {
    final conv = conversations[conversationId];
    if (conv == null) return null;
    ensureLoaded(conversationId);
    for (final m in conv.messages) {
      if (m.isReferredToBy(idHex)) return m;
    }
    return null;
  }

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

    // Apply locally. One reaction per person per message: adding [emoji]
    // first takes back every other own reaction on this message, and each
    // taking back goes out as a removal before the addition, so a receiver
    // of any 4.2 version ends with exactly one reaction of ours.
    ensureLoaded(conversationId);
    final msgIndex = conv.messages.indexWhere((m) => m.id == messageId);
    final replaced = <String>[];
    if (msgIndex >= 0) {
      final msg = conv.messages[msgIndex];
      if (remove) {
        msg.reactions[emoji]?.remove(identity.userIdHex);
        if (msg.reactions[emoji]?.isEmpty ?? false) msg.reactions.remove(emoji);
      } else {
        for (final e in msg.reactions.keys.toList()) {
          if (e == emoji) continue;
          if (msg.reactions[e]?.remove(identity.userIdHex) ?? false) {
            replaced.add(e);
            if (msg.reactions[e]?.isEmpty ?? false) msg.reactions.remove(e);
          }
        }
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

    // Build reaction payload. §16.2: a reaction names the post identifier of
    // a group post; everything else is named by the identifier it is kept
    // under (1:1: the wire identifier, as before).
    final referred = hexToBytes(
        msgIndex >= 0 ? conv.messages[msgIndex].referenceId : messageId);
    Uint8List payloadFor(String e, bool rm) =>
        Uint8List.fromList((proto.EmojiReaction()
              ..messageId = referred
              ..emoji = e
              ..remove = rm)
            .writeToBuffer());
    // Removals of the replaced reactions first, then the reaction itself.
    final payloads = [
      for (final e in replaced) payloadFor(e, true),
      payloadFor(emoji, remove),
    ];

    // V3: pairwise fan-out via sendToUser. The group conversation ID on the
    // wire side moves with C4 groups; until then the reaction lands at the
    // recipient as a DM reaction on his sender tab.
    final group = _groups[conversationId];
    final channel = group == null ? _channels[conversationId] : null;
    if (channel != null &&
        !channel.isPublic &&
        !SystemChannels.isSystemChannel(conversationId)) {
      // §16.2.4: to the owner only; the owner's own reaction starts a round.
      await _channelReactionSend(_ReactionEntity.ofChannel(channel),
          msgIndex >= 0 ? conv.messages[msgIndex] : null, payloads,
          bytesToHex(referred));
    } else if (group != null &&
        _groupReactsViaOwner(conversationId) &&
        !_groupMayPost(conversationId, identity.userIdHex)) {
      // §16.2.5: in announcement mode on the shared key a member is no
      // author — its reaction goes 1:1 to the owner, which deposits the
      // totals (§16.2.4).
      await _channelReactionSend(_ReactionEntity.ofGroup(group),
          msgIndex >= 0 ? conv.messages[msgIndex] : null, payloads,
          bytesToHex(referred));
    } else if (group != null) {
      final groupIdBytes = hexToBytes(conversationId);
      final gmEpoch = group.membershipEpoch;
      // §16.2.4: the owner of a group in announcement mode on the shared key
      // counts its own reaction into the next totals.
      if (msgIndex >= 0 &&
          _groupReactsViaOwner(conversationId) &&
          group.ownerNodeIdHex == identity.userIdHex) {
        _channelReactionChanged(conversationId, conv.messages[msgIndex].id);
      }
      final gmHash = _computeMembershipHash(gmEpoch, conversationId, group.members);
      // §16.2.5: on the shared key a reaction is a post of its own, naming
      // the post it concerns by its post identifier.
      Set<String>? pairwise;
      for (final payload in payloads) {
        pairwise = await _skServe(conversationId,
            type: proto.MessageType.MT_REACTION,
            payload: payload,
            messageId: SodiumFFI().randomBytes(16),
            epoch: gmEpoch,
            hash: gmHash);
      }
      for (final member in group.members.values) {
        if (member.nodeIdHex == identity.userIdHex) continue;
        if (pairwise != null && !pairwise.contains(member.nodeIdHex)) continue;
        for (final payload in payloads) {
          await sendToUser(
            recipientUserId: hexToBytes(member.nodeIdHex),
            messageType: proto.MessageType.MT_REACTION,
            payload: payload,
            groupId: groupIdBytes,
            groupMembershipEpoch: gmEpoch,
            groupMembershipHash: gmHash,
          );
        }
      }
    } else {
      final contact = _contacts[conversationId];
      if (contact == null ||
          contact.x25519Pk == null ||
          contact.mlKemPk == null) {
        return;
      }
      for (final payload in payloads) {
        await sendToUser(
          recipientUserId: contact.nodeId,
          messageType: proto.MessageType.MT_REACTION,
          payload: payload,
        );
      }
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
  Future<void> broadcastIdentityDeleted() async {
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
          messageType: proto.MessageType.MT_IDENTITY_DELETED,
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
    // upgrade `sent → delivered` in `_handleDeliveryReceipt`.
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

    // V3 sender path: build TextMessage sub-message, hand to sendToUser
    // which does Inner-build/User-Sign/zstd/KEM-encrypt + Outer-build/
    // Device-Sign + per-device fan-out. Reply-fields and the sender-side
    // link-preview are wire-tagged on TextMessage itself.

    // Sender-side link preview (v4_2 "The sender fetches link previews,
    // embedded and encrypted"; S410 E5 A): the preview travels IN the
    // message (`TextMessage.link_preview`, field 5 — read by every 4.2
    // device). The message is shown at once; it leaves the device once the
    // preview is fetched (or the fetch gave up), and nothing written to this
    // contact afterwards overtakes it — see `_sendWithLinkPreview`.
    final hasUrl = _linkPreviewSettings.enabled && extractFirstUrl(text) != null;

    final tm = proto.TextMessage()
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
    // `_myceliumSend` carries that over at once (`_reflectLegStatus`). Without
    // the entry the display only learned the state after `sendToUser`
    // returned — and a receipt that arrived before that let the ONE tick of
    // §12.2 be skipped (resting -> delivered, `smoke_four_states_run`).
    _applyOutgoingLegStatus(msg, <String>[messageIdHex]);
    final bool handed;
    if (hasUrl) {
      // The message takes its place in the line of its leg NOW, before any
      // await, so that a message written after it waits behind it (§9.4,
      // the line of `cleona_service_file_order.dart`). Taken over: `true`.
      _fileOrderLinkTake(
        recipientUserId: contact.nodeId,
        messageId: messageIdBytes,
        payload: tm.writeToBuffer(),
      );
      unawaited(_sendWithLinkPreview(recipientUserIdHex, msg, tm));
      handed = true;
    } else {
      handed = await sendToUser(
        recipientUserId: contact.nodeId,
        messageType: proto.MessageType.MT_TEXT,
        payload: tm.writeToBuffer(),
        messageId: messageIdBytes,
      );
    }
    // B-5 (S398-W1): `false` means NOTHING was taken over (no address, the
    // mailbox refused) — no rung can ever carry it, so it is `failed` with
    // its reason instead of resting forever (§22.5.1: "`failed` means no
    // rung of the ladder carried the payload at all"). Parked for lack of a
    // mailbox is `true` (S401): it rests and goes out at the attach.
    // A `true` is still no delivery claim; the register below decides.
    if (handed) {
      statsCollector.addMessageSent();
    } else {
      _seamRefused(msg, 'sendTextMessage');
    }

    // AP-4 (§5.1b/§5.1c K2): here stood the ternary
    //   `sent ? sent : (l3Out[0] ? queuedOffline : failed)`
    // including the comment "sent=true → direct UDP dispatch succeeded".
    // It has been dropped WITHOUT REPLACEMENT, not renamed: its trigger was a
    // successful socket write or a completed L3 placement, and neither
    // is a delivery event in V4.1 any more (v4_1 §22.5.1). The return value
    // of `sendToUser` is read only for "nothing handed over" (above, B-5).
    //
    // What moves the status now is solely the delivery register (§9.2, D2).
    _applyOutgoingLegStatus(msg, <String>[messageIdHex]);
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

    return msg;
  }

  /// The whole fetch of one link preview is bounded, not only each step:
  /// a server that trickles its body would otherwise hold the message — and
  /// every message written after it — without end. Three steps of
  /// `fetchTimeoutSec` (name resolution, page, image) is the bound.
  static const int kLinkPreviewFetchSteps = 3;

  /// Fetches the preview of the 1:1 message [msg] (built as [tm]), shows it
  /// on this device and lets the message go with the preview embedded. A
  /// fetch that fails or runs over its bound lets it go without one — the
  /// message is never held back for lack of a preview. It waited in its
  /// line since `sendTextMessage` (`_fileOrderLinkTake`); the line hands it
  /// on in writing order (`_fileOrderLinkReady`).
  Future<void> _sendWithLinkPreview(
      String recipientUserIdHex, UiMessage msg, proto.TextMessage tm) async {
    final withPreview = await _linkPreviewEmbed(msg, tm,
        stillWanted: () => _fileOrderLinkWaits(
            recipientUserIdHex, recipientUserIdHex, msg.id));
    if (withPreview == null) return; // its line is gone
    _fileOrderLinkReady(recipientUserIdHex, recipientUserIdHex, msg.id,
        withPreview.payload);
  }

  /// The fetch of the preview of [msg] (built as [tm]) for every
  /// conversation kind: bounded as a whole ([kLinkPreviewFetchSteps]),
  /// embedded into [tm] and shown on [msg] at this device. `null`: the
  /// conversation ended meanwhile ([stillWanted] said no) — nothing goes,
  /// nothing comes back into the store. Otherwise [payload] is the frame
  /// with the preview embedded, or `null` when the fetch found nothing,
  /// failed or ran over its bound — the message then goes without one; it
  /// is never held back for lack of a preview.
  Future<({Uint8List? payload})?> _linkPreviewEmbed(
      UiMessage msg, proto.TextMessage tm,
      {required bool Function() stillWanted}) async {
    Uint8List? withPreview;
    try {
      final preview = await _linkPreviewFetcher
          .fetchPreview(tm.text)
          .timeout(Duration(
              seconds: _linkPreviewSettings.fetchTimeoutSec *
                  kLinkPreviewFetchSteps));
      // The conversation ended while the preview was fetched: its line is
      // gone, and the message must not come back into the store.
      if (!stillWanted()) {
        _log.info('[E2E link-preview] msgId=${msg.id.substring(0, 8)} '
            'its line is gone — not sent');
        return null;
      }
      if (preview != null) {
        tm.linkPreview = preview.toProto();
        withPreview = tm.writeToBuffer();
        msg
          ..linkPreviewUrl = preview.url
          ..linkPreviewTitle = preview.title
          ..linkPreviewDescription = preview.description
          ..linkPreviewSiteName = preview.siteName
          ..linkPreviewThumbnailBase64 = preview.thumbnail == null
              ? null
              : base64Encode(preview.thumbnail!);
        persistMessage(msg.conversationId, msg);
        onStateChanged?.call();
      }
    } catch (e) {
      // Also a fetcher that was never set up (a service that did not run
      // `startService`): the message goes without a preview.
      _log.debug('Link preview fetch failed: $e');
      if (!stillWanted()) return null;
    }
    _log.info('[E2E link-preview] msgId=${msg.id.substring(0, 8)} '
        '${withPreview != null ? 'preview embedded' : 'no preview'} — '
        'the message goes');
    return (payload: withPreview);
  }

  /// A group post or a channel post [msg] (built as [tm]) with a link: it
  /// was shown at once and holds, while its preview is fetched, the line of
  /// each member leg ([legs]: member hex → wire identifier,
  /// `_fileOrderLinkTake`) and — on the shared key ([onSharedKey]) — the
  /// post line of the group (`_skServe(linkWaits: true)`). Once the fetch
  /// ended it goes with the preview embedded, or without one, and what was
  /// written to the group after it follows (S410 follow-up, owner
  /// 29.10.2026 "A": the same as a 1:1 message).
  Future<void> _sendPostWithLinkPreview(
    UiMessage msg,
    proto.TextMessage tm, {
    required proto.MessageType type,
    required Map<String, String> legs,
    required bool onSharedKey,
    int? epoch,
    Uint8List? hash,
  }) async {
    final gid = msg.conversationId;
    bool wanted() => _groups.containsKey(gid) || _channels.containsKey(gid);
    final r = await _linkPreviewEmbed(msg, tm, stillWanted: wanted);
    if (r == null) {
      if (onSharedKey) _skLinkDrop(gid, msg.id);
      return;
    }
    final payload = r.payload;
    if (onSharedKey) {
      // The post is sealed again with the preview; the copy sealed without
      // it when it was written (kept for a process that ends meanwhile) is
      // dropped. Sealing fails (no step key any more, …): the copy goes.
      final pid = hexToBytes(msg.postId!);
      final again = payload == null
          ? null
          : await _skServe(gid,
              type: type,
              payload: payload,
              messageId: pid,
              postId: pid,
              epoch: epoch,
              hash: hash,
              msg: msg,
              linkResealed: true);
      if (again == null) _skLinkReady(gid, msg.id);
    }
    for (final e in legs.entries) {
      _fileOrderLinkReady(gid, e.key, e.value, payload);
    }
  }

  /// A fetcher whose answers a probe decides (smokes only).
  @visibleForTesting
  set linkPreviewFetcherForTesting(LinkPreviewFetcher f) =>
      _linkPreviewFetcher = f;

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
    // A FILE IS NEVER SENT AGAIN (v4_2 §9.3, §12.2, D-34, S398-W1). Until
    // S398 this fell through to `sendTextMessage(original.text)` and sent
    // the FILE NAME as a text, deleting the file's entry. The failed entry
    // stays as it is, with its reason; nothing is sent.
    if (original.isMedia) {
      _log.warn('resendFailedMessage: ${messageId.substring(0, 8)} is a file '
          '— never sent again (§9.3), stays failed '
          '(${original.failureReason?.wireName ?? 'no reason'})');
      return null;
    }
    // A group or channel post: only the members whose leg failed, under the
    // leg's own identifier — nothing is erased (owner decision 30.10.2026,
    // S410 "B"). Until S410 this fell through to `sendTextMessage(<group>)`,
    // which knows no contact under a group identifier: the post was erased
    // and nothing was sent.
    if (_groups.containsKey(conversationId) ||
        _channels.containsKey(conversationId)) {
      return _resendFailedLegs(conversationId, original);
    }
    // Take out the abandoned entry, then send anew via the normal path.
    // (S368: here additionally stood `_outbox.remove` — the
    // V3 outbox has fallen, it could never carry the entry anyway.)
    //
    // On the ONE route a message leaves this profile (`_eraseMessageLocally`):
    // until S403 the entry left the memory only — its row stayed in the
    // store, came back as `failed` with the next start, and a recipient that
    // caught up later (§9.5) got the old message beside the new one. §9.3:
    // "unless the user has sent it again in the meantime, in which case only
    // the new one counts" (measured: `smoke_catch_up_run`).
    _eraseMessageLocally(conversationId, original);
    _saveConversations();
    return sendTextMessage(
      conversationId,
      original.text,
      replyToMessageId: original.replyToMessageId,
      replyToText: original.replyToText,
      replyToSender: original.replyToSender,
    );
  }

  /// "Retry" for a group or channel post [msg] (§12.2; owner decision
  /// 30.10.2026, S410 "B"): the post goes again ONLY to the members whose
  /// leg failed (`UiMessage.legFailedBy`), each under the identifier of ITS
  /// leg — the identifier the member would hold it under. A member who got
  /// it after all keeps one copy: the receiver drops a message whose
  /// identifier it already holds (`_addMessageToConversation`, "Dedup by
  /// msg.id") and acknowledges it again (`handleApplicationFrame`).
  /// Nothing is erased, no other member receives anything, the wire format
  /// is that of the first sending.
  ///
  /// A member who still has no way (not joined: no contact, no group pair)
  /// fails again at once (`_groupLegWithoutWay`); the post stays `failed`
  /// and the group's line naming the member stays.
  Future<UiMessage?> _resendFailedLegs(
      String conversationId, UiMessage msg) async {
    final group = _groups[conversationId];
    final channel = group == null ? _channels[conversationId] : null;
    final isChannel = channel != null;
    if (msg.type != UiMessageType.text &&
        msg.type != UiMessageType.channelPost) {
      _log.warn('resendFailedMessage: ${msg.id.substring(0, 8)} is no text '
          'post (${msg.type.name}) — not sent again');
      return null;
    }
    if (group != null && !_groupMayPost(conversationId, identity.userIdHex)) {
      _log.warn('resendFailedMessage: announcement mode, this identity is a '
          'member — not sent again');
      return null;
    }
    if (channel != null && !_hasChannelPermission(channel, 'post')) {
      _log.warn('resendFailedMessage: no permission to post in the channel');
      return null;
    }
    final members = isChannel ? channel.members : group!.members;
    final again = <String>[
      for (final m in msg.legFailedBy)
        if (msg.fanoutLegs.containsKey(m) &&
            !msg.deliveredBy.contains(m) &&
            members.containsKey(m))
          m,
    ];
    if (again.isEmpty) {
      _log.warn('resendFailedMessage: ${msg.id.substring(0, 8)} — no failed '
          'leg of a current member known; nothing sent');
      return null;
    }
    final tm = proto.TextMessage()
      ..text = msg.text
      ..formatHint = 'plain';
    final reply = msg.replyToMessageId;
    if (!isChannel && reply != null && reply.isNotEmpty &&
        _isWireCapableMessageIdentifier(reply)) {
      tm.replyToMessageId = hexToBytes(_referenceIdOf(conversationId, reply));
      final snippet = msg.replyToText;
      if (snippet != null && snippet.isNotEmpty) {
        tm.replyToSnippet =
            snippet.length > 120 ? '${snippet.substring(0, 120)}…' : snippet;
      }
    }
    if (msg.hasLinkPreview) {
      // The preview the post went with (`_linkPreviewEmbed`), not a new fetch.
      tm.linkPreview = proto.LinkPreview()
        ..url = msg.linkPreviewUrl!
        ..title = msg.linkPreviewTitle ?? ''
        ..description = msg.linkPreviewDescription ?? ''
        ..siteName = msg.linkPreviewSiteName ?? '';
      final thumb = msg.linkPreviewThumbnailBase64;
      if (thumb != null) tm.linkPreview.thumbnail = base64Decode(thumb);
    }
    final payload = Uint8List.fromList(tm.writeToBuffer());
    final epoch =
        isChannel ? channel.membershipEpoch : group!.membershipEpoch;
    final hash = isChannel
        ? _computeChannelMembershipHash(epoch, conversationId, channel.members)
        : _computeMembershipHash(epoch, conversationId, group!.members);
    final postId = msg.postId == null ? null : hexToBytes(msg.postId!);
    for (final member in again) {
      final leg = msg.fanoutLegs[member]!;
      // The delivery layer's "no way" for this leg is a fact of the last
      // sending; the new one decides afresh.
      _myceliumLegsWithoutWay.remove(leg);
      await sendToUser(
        recipientUserId: hexToBytes(member),
        messageType: isChannel
            ? proto.MessageType.MT_CHANNEL_POST
            : proto.MessageType.MT_TEXT,
        payload: payload,
        messageId: hexToBytes(leg),
        groupId: hexToBytes(conversationId),
        groupMembershipEpoch: epoch,
        groupMembershipHash: hash,
        postId: postId,
      );
    }
    _log.info('resendFailedMessage: ${msg.id.substring(0, 8)} sent again to '
        '${again.length} member(s) whose leg failed (S410 "B")');
    _applyOutgoingLegStatus(msg, msg.fanoutLegs.values.toList());
    persistMessage(conversationId, msg);
    _saveConversations();
    onStateChanged?.call();
    return msg;
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

    // THE EDIT NAMES THE IDENTIFIER UNDER WHICH ITS RECIPIENT HOLDS THE
    // MESSAGE — in the payload and as the wire messageId. 1:1 that is the
    // display identifier. A group post is N ordinary 1:1 deliveries (§16.2),
    // each under an identifier of its own: a member holds the post under
    // the identifier of ITS leg (`fanoutLegs`) and has never seen the
    // display identifier. Until S401 every leg named the display
    // identifier, and no edit of a group post took effect at a member
    // (`test/smoke/smoke_group_delete_edit_run.dart`).
    //
    // Wire messageId == the identifier named: the receiver's dedup key
    // carries it together with the edit's timestamp (a repeated copy of the
    // same edit is dropped, a second edit is taken), the receipt is
    // attributed to the message or to its leg, and a deletion finds the
    // edits in the history of the delivery layer under the identifiers of
    // the message (`_myceliumForget`). Status stays at delivered (edits
    // mutate an existing bubble; no `sent → delivered` transition required).
    final editTimestamp = Int64(DateTime.now().millisecondsSinceEpoch);
    Uint8List editPayload(Uint8List heldAs) => Uint8List.fromList(
        (proto.MessageEdit()
              ..originalMessageId = heldAs
              ..newText = newText
              ..editTimestamp = editTimestamp)
            .writeToBuffer());

    // Group or DM? V3 keeps pairwise fan-out (one sendToUser per member).
    // ApplicationFrame.group_id (Field 17) carries the conversation tag so
    // receivers dispatch the EDIT to the matching group/channel tab.
    final group = _groups[conversationId];
    final channel = group == null ? _channels[conversationId] : null;
    bool anySent = false;

    // §16.2.5: a post on the shared key is edited by a post of its own that
    // names the post identifier; the legs to members on pairwise legs follow
    // below as before (`fanoutLegs` holds only theirs).
    if (original.sharedKey && original.postId != null) {
      final pid = hexToBytes(original.postId!);
      final served = await _skServe(conversationId,
          type: proto.MessageType.MT_EDIT,
          payload: editPayload(pid),
          messageId: pid,
          epoch: group?.membershipEpoch ?? channel?.membershipEpoch,
          hash: group != null
              ? _computeMembershipHash(
                  group.membershipEpoch, conversationId, group.members)
              : null);
      if (served != null) anySent = true;
    }

    if (group != null) {
      final groupIdBytes = hexToBytes(conversationId);
      final gmEpoch = group.membershipEpoch;
      final gmHash = _computeMembershipHash(gmEpoch, conversationId, group.members);
      for (final member in group.members.values) {
        if (member.nodeIdHex == identity.userIdHex) continue;
        // No leg: the member joined after the post was sent and does not
        // have it (§16.2.3 "Members are fixed at the moment of sending").
        final leg = original.fanoutLegs[member.nodeIdHex];
        if (leg == null) continue;
        final legId = hexToBytes(leg);
        final ok = await sendToUser(
          recipientUserId: hexToBytes(member.nodeIdHex),
          messageType: proto.MessageType.MT_EDIT,
          payload: editPayload(legId),
          groupId: groupIdBytes,
          messageId: legId,
          groupMembershipEpoch: gmEpoch,
          groupMembershipHash: gmHash,
        );
        if (ok) anySent = true;
      }
    } else if (channel != null) {
      // S403 (§21.5.2 level 2, §16.2): a private channel post is N
      // ordinary 1:1 deliveries like a group post, and the edit travels
      // "over the same pairwise legs as any other" — per subscriber under
      // the identifier of that subscriber's leg. Until S403 this branch
      // did not exist and `editMessage` refused a channel post at the
      // 1:1 gate below (S401, finding NB-18).
      final channelIdBytes = hexToBytes(conversationId);
      final chEpoch = channel.membershipEpoch;
      final chHash = _computeChannelMembershipHash(chEpoch, conversationId, channel.members);
      for (final member in channel.members.values) {
        if (member.nodeIdHex == identity.userIdHex) continue;
        // No leg: the subscriber joined after the post was sent and does
        // not have it (§16.2.3 "Members are fixed at the moment of
        // sending").
        final leg = original.fanoutLegs[member.nodeIdHex];
        if (leg == null) continue;
        final legId = hexToBytes(leg);
        final ok = await sendToUser(
          recipientUserId: hexToBytes(member.nodeIdHex),
          messageType: proto.MessageType.MT_EDIT,
          payload: editPayload(legId),
          groupId: channelIdBytes,
          messageId: legId,
          groupMembershipEpoch: chEpoch,
          groupMembershipHash: chHash,
        );
        if (ok) anySent = true;
      }
    } else {
      final contact = _contacts[conversationId];
      if (contact == null || contact.status != 'accepted') return false;
      final wireMessageId = hexToBytes(messageId);
      final sent = await sendToUser(
        recipientUserId: contact.nodeId,
        messageType: proto.MessageType.MT_EDIT,
        payload: editPayload(wireMessageId),
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

    // §16.7 (S407 SK-4): a system-channel report is no conversation
    // message; it is retracted through `systemChannelApi.retract` (a
    // tombstone of the report pseudonym). Nothing to delete here.
    if (SystemChannels.isSystemChannel(conversationId)) {
      _log.warn('deleteMessage: system channel — retract via the system '
          'channel view');
      return false;
    }

    // The request names the identifier under which ITS RECIPIENT holds the
    // message — in the payload and as the wire messageId; the rule and its
    // reasons stand at `editMessage`. 1:1 the display identifier, in a group
    // the identifier of the member's leg (§16.2, §21.5.2 level 2: "sent over
    // the same pairwise legs as any other message"). Named by the display
    // identifier, the request met nothing at a member and left a mark there
    // for an identifier no message will ever come under.
    final deletedAt = Int64(DateTime.now().millisecondsSinceEpoch);
    Uint8List deletePayload(Uint8List heldAs) => Uint8List.fromList(
        (proto.MessageDelete()
              ..messageId = heldAs
              ..deletedAt = deletedAt)
            .writeToBuffer());

    final group = _groups[conversationId];
    final channel = group == null ? _channels[conversationId] : null;
    final contact =
        group == null && channel == null ? _contacts[conversationId] : null;
    // §21.5.1: "Deletion is unbounded. The author may delete their message
    // at any time" — no exception for a channel post. Until S403 the gate
    // knew only groups and contacts and refused a channel post outright
    // (S401, finding NB-18).
    if (group == null &&
        channel == null &&
        (contact == null || contact.status != 'accepted')) {
      return false;
    }

    // §21.5.2, level 1: "Locally. … Immediately and completely." The local
    // deletion does not wait for the request to the other side and does not
    // depend on it: that one is best-effort (level 2), and `sendToUser`
    // answers `false` where the request was not taken over (S401: also when
    // the message itself is still parked under the same identifier).
    _eraseMessageLocally(conversationId, original, byAuthor: true);
    onStateChanged?.call();
    _saveConversations();
    _log.info('Message deleted: $messageId');
    _sendTwinSync(proto.TwinSyncType.MESSAGE_DELETED, Uint8List.fromList(utf8.encode(jsonEncode({
      'conversationId': conversationId,
      'messageId': messageId,
    }))));

    // §16.2.5: on the shared key the deletion is a post of its own that
    // names the post identifier; members on pairwise legs get theirs below.
    if (original.sharedKey && original.postId != null) {
      final pid = hexToBytes(original.postId!);
      await _skServe(conversationId,
          type: proto.MessageType.MT_DELETE,
          payload: deletePayload(pid),
          messageId: pid,
          epoch: group?.membershipEpoch ?? channel?.membershipEpoch,
          hash: group != null
              ? _computeMembershipHash(
                  group.membershipEpoch, conversationId, group.members)
              : null);
    }

    if (group != null) {
      // Pairwise fan-out per member (V3 keeps the same model).
      final groupIdBytes = hexToBytes(conversationId);
      final gmEpoch = group.membershipEpoch;
      final gmHash = _computeMembershipHash(gmEpoch, conversationId, group.members);
      // `original` has left the conversation above; its legs are still on
      // the object.
      for (final member in group.members.values) {
        if (member.nodeIdHex == identity.userIdHex) continue;
        // No leg: the member joined after the post was sent and does not
        // have it (§16.2.3) — nothing to delete there, and no mark to leave.
        final leg = original.fanoutLegs[member.nodeIdHex];
        if (leg == null) continue;
        final legId = hexToBytes(leg);
        final ok = await sendToUser(
          recipientUserId: hexToBytes(member.nodeIdHex),
          messageType: proto.MessageType.MT_DELETE,
          payload: deletePayload(legId),
          groupId: groupIdBytes,
          messageId: legId,
          groupMembershipEpoch: gmEpoch,
          groupMembershipHash: gmHash,
        );
        if (!ok) {
          _log.debug('MT_DELETE to a member not handed on at once');
        }
      }
    } else if (channel != null) {
      // S403 (§21.5.2 level 2, §16.2): the deletion of a channel post
      // travels "over the same pairwise legs as any other" — per
      // subscriber under the identifier of that subscriber's leg, the
      // pattern of the group fan-out above.
      final channelIdBytes = hexToBytes(conversationId);
      final chEpoch = channel.membershipEpoch;
      final chHash = _computeChannelMembershipHash(chEpoch, conversationId, channel.members);
      for (final member in channel.members.values) {
        if (member.nodeIdHex == identity.userIdHex) continue;
        final leg = original.fanoutLegs[member.nodeIdHex];
        if (leg == null) continue;
        final legId = hexToBytes(leg);
        final ok = await sendToUser(
          recipientUserId: hexToBytes(member.nodeIdHex),
          messageType: proto.MessageType.MT_DELETE,
          payload: deletePayload(legId),
          groupId: channelIdBytes,
          messageId: legId,
          groupMembershipEpoch: chEpoch,
          groupMembershipHash: chHash,
        );
        if (!ok) {
          _log.debug('MT_DELETE to a subscriber not handed on at once');
        }
      }
    } else {
      final wireMessageId = hexToBytes(messageId);
      final sent = await sendToUser(
        recipientUserId: contact!.nodeId,
        messageType: proto.MessageType.MT_DELETE,
        payload: deletePayload(wireMessageId),
        messageId: wireMessageId,
      );
      if (!sent) {
        _log.debug('MT_DELETE not handed on at once');
      }
    }

    return true;
  }

  @override
  Future<bool> updateGroupProfile(String conversationId,
          {String? name,
          String? description,
          bool setPicture = false,
          String? pictureBase64}) =>
      _groupProfileUpdate(conversationId,
          name: name,
          description: description,
          setPicture: setPicture,
          pictureBase64: pictureBase64);

  @override
  Future<bool> updateChatConfig(String conversationId, ChatConfig config) async {
    final conv = conversations[conversationId];
    if (conv == null) return false;

    // For groups: owner or admin can set directly
    final group = _groups[conversationId];
    if (group != null) {
      if (!_hasGroupPermission(group, 'config')) return false;
      final modeChanged = config.announcementOnly != conv.config.announcementOnly;
      conv.config = config;
      _saveConversations();
      // Broadcast config to all group members
      _broadcastGroupConfigUpdate(group, config);
      // §14.2, D-72: and to the other own devices.
      _ownChatConfigMirror(conversationId, _groupConfigBytes(group, config),
          group: true);
      if (modeChanged) {
        _groupAnnouncementChanged(conversationId, recordedHere: true);
      }
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
      _ownChatConfigMirror(
          conversationId, _channelConfigBytes(channel.channelIdHex, config),
          group: true);
      onStateChanged?.call();
      _log.info('Channel chat config updated for "${channel.name}"');
      return true;
    }

    // For DMs: send config update proposal to peer — NOT active until accepted
    final contact = _contacts[conversationId];
    if (contact == null || contact.status != 'accepted') return false;

    // Store as pending on our side too (active only after peer accepts).
    // A new round: an acceptance kept for an earlier own proposal not seen
    // here is dropped (O-1) — the partner answers this one.
    conv.pendingConfigProposal = config;
    conv.pendingConfigProposer = identity.userIdHex;
    conv.parkedConfigAcceptance = null;
    _saveConversations();

    _sendChatConfigUpdate(contact, conversationId, config, isRequest: true);
    // §14.2, D-72: every own device shows the open proposal.
    _ownChatConfigMirror(conversationId,
        _dmConfigBytes(conversationId, config, isRequest: true));
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
    conv.parkedConfigAcceptance = null; // an own answer ends the round (O-1)
    _saveConversations();

    // Send acceptance to the proposer
    final contact = _contacts[conversationId];
    if (contact != null && contact.x25519Pk != null && contact.mlKemPk != null) {
      _sendChatConfigUpdate(contact, conversationId, proposedConfig, isRequest: false, accepted: true);
    }
    // §14.2, D-72: the other own devices apply it and close the proposal.
    _ownChatConfigMirror(
        conversationId,
        _dmConfigBytes(conversationId, proposedConfig,
            isRequest: false, accepted: true));

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
    conv.parkedConfigAcceptance = null; // an own answer ends the round (O-1)
    _saveConversations();

    // Send rejection to the proposer
    final contact = _contacts[conversationId];
    if (contact != null && contact.x25519Pk != null && contact.mlKemPk != null) {
      _sendChatConfigUpdate(contact, conversationId, rejectedConfig, isRequest: false, accepted: false);
    }
    // §14.2, D-72: the other own devices close the proposal.
    _ownChatConfigMirror(conversationId,
        _dmConfigBytes(conversationId, rejectedConfig, isRequest: false));

    onStateChanged?.call();
    _log.debug('DM config rejected — displayName="${contact?.displayName}"');
    _log.info('DM config proposal rejected for '
        '${conversationId.substring(0, 8)}');
    return true;
  }

  /// Forward a message to another conversation. A file from 256 KB on takes
  /// a media lane and is sent only with [consent] (§9.4 "Consent"); without
  /// it the forwarded message ends `failed`, as in [sendMediaMessage].
  @override
  Future<UiMessage?> forwardMessage(String sourceConversationId, String messageId, String targetConversationId,
      {bool consent = false}) async {
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
    if (msg == null) return null;

    // Determine original sender name for attribution
    final originalSenderName = msg.isOutgoing
        ? displayName
        : (_contacts[msg.senderNodeIdHex]?.effectiveName ?? msg.senderNodeIdHex.substring(0, 8));

    // Check if this is a media message
    if (msg.isMedia) {
      if (msg.filePath != null &&
          MediaStore.instance.existsEitherWay(msg.filePath!)) {
        // The ONE media send path, with the consent the interface collected
        // for this file (§9.4 "Consent").
        final result = await sendMediaMessage(targetConversationId, msg.filePath!,
            consent: consent);
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
    _detachedSend('MT_CHAT_CONFIG_UPDATE', sendToUser(
      recipientUserId: contact.nodeId,
      messageType: proto.MessageType.MT_CHAT_CONFIG_UPDATE,
      payload: _dmConfigBytes(conversationId, config,
          isRequest: isRequest, accepted: accepted),
      groupId: groupIdHex != null ? hexToBytes(groupIdHex) : null,
    ));
  }

  /// A 1:1 proposal ([isRequest]), acceptance or rejection as one
  /// `ChatConfigUpdate` (§21.5.4).
  Uint8List _dmConfigBytes(String conversationId, ChatConfig config,
      {required bool isRequest, bool accepted = false}) {
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
    return Uint8List.fromList(configMsg.writeToBuffer());
  }

  /// The configuration a `ChatConfigUpdate` carries — the announcement mode
  /// is left to the caller (it applies to a group only, and only where the
  /// update names it).
  ChatConfig _chatConfigOf(proto.ChatConfigUpdate m) => ChatConfig(
        allowDownloads: m.allowDownloads,
        allowForwarding: m.allowForwarding,
        editWindowMs: m.hasEditWindowMs() ? m.editWindowMs.toInt() : null,
        expiryDurationMs:
            m.hasExpiryDurationMs() ? m.expiryDurationMs.toInt() : null,
        readReceipts: m.readReceipts,
        typingIndicators: m.typingIndicators,
      );

  /// Whether [a] and [b] carry the same 1:1 values — the fields a
  /// `ChatConfigUpdate` carries for a direct chat ([_dmConfigBytes]); the
  /// announcement mode is a group's.
  bool _sameDmConfig(ChatConfig a, ChatConfig b) =>
      a.allowDownloads == b.allowDownloads &&
      a.allowForwarding == b.allowForwarding &&
      a.expiryDurationMs == b.expiryDurationMs &&
      a.editWindowMs == b.editWindowMs &&
      a.readReceipts == b.readReceipts &&
      a.typingIndicators == b.typingIndicators;

  // `_resolveMemberKeys` stood here: the key overrides of the send seam for
  // members that are not contacts. B-3 (S398, E6; v4_2 §22.5.1 "There are
  // no key overrides"): such a co-member is reached as a group pair (§4.3),
  // which the seam finds by the UserID (`cleona_service_group_pairs.dart`).

  /// Broadcast a config update to all group members (pairwise KEM).
  void _broadcastGroupConfigUpdate(GroupInfo group, ChatConfig config) {
    final configPayload = _groupConfigBytes(group, config);
    for (final member in group.members.values) {
      if (member.nodeIdHex == identity.userIdHex) continue;
      _detachedSend('MT_CHAT_CONFIG_UPDATE', sendToUser(
        recipientUserId: hexToBytes(member.nodeIdHex),
        messageType: proto.MessageType.MT_CHAT_CONFIG_UPDATE,
        payload: configPayload,
        groupId: hexToBytes(group.groupIdHex),
      ));
    }
    _log.info('Broadcast config update for "${group.name}" to ${group.members.length - 1} members');
  }

  /// The settings of [group] as one `ChatConfigUpdate` — the announcement
  /// mode with explicit presence (§16.2.2).
  Uint8List _groupConfigBytes(GroupInfo group, ChatConfig config) {
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
    // A 4.2.3 stand-in of a probe does not know the field and sends none.
    if (!channelReceiveAs423) {
      configMsg.announcementOnly = config.announcementOnly;
    }
    return Uint8List.fromList(configMsg.writeToBuffer());
  }

  /// Broadcast a config update to all channel members (pairwise KEM).
  void _broadcastChannelConfigUpdate(ChannelInfo channel, ChatConfig config) {
    final configPayload = _channelConfigBytes(channel.channelIdHex, config);
    for (final member in channel.members.values) {
      if (member.nodeIdHex == identity.userIdHex) continue;
      _detachedSend('MT_CHAT_CONFIG_UPDATE', sendToUser(
        recipientUserId: hexToBytes(member.nodeIdHex),
        messageType: proto.MessageType.MT_CHAT_CONFIG_UPDATE,
        payload: configPayload,
        groupId: hexToBytes(channel.channelIdHex),
      ));
    }
    _log.info('Broadcast config update for channel "${channel.name}" to ${channel.members.length - 1} members');
  }

  /// The settings of the channel [channelIdHex] as one `ChatConfigUpdate`.
  Uint8List _channelConfigBytes(String channelIdHex, ChatConfig config) {
    final configMsg = proto.ChatConfigUpdate()
      ..conversationId = channelIdHex
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
    return Uint8List.fromList(configMsg.writeToBuffer());
  }

  // ── FIVE V3 STORAGE CONSTANTS: FALLEN (CUT) ──────────────────────
  //
  // `_pendingFragmentStoreAcks`, `_l3SizeThresholdBytes` (10 KB —
  // below S&F, above Reed-Solomon), `_pendingPeerStoreAcks`,
  // `_peerStoreAckTimeout` and `_safTargetCopies` (three confirmed
  // copies). They exclusively described the layer 3 cascade, and that
  // no longer exists: V4.1 stores with the responsible relays of the
  // tag line (§9.1), with `m x R` as the redundancy measure instead of three copies.

  // ── NO HAND-FED ADDRESSES (S399 P1 part C) ─────────────────────────
  //
  // `addPeersFromContactSeed` (IPC `add_seed_peers`), `addManualPeer`
  // (IPC `add_manual_peer`) and the peer rescue bundle
  // (`exportPeerBundle`/`importPeerBundle`) stood here. All of them fed
  // addresses into `personEntryHints` of the replaced tagline layer, whose
  // only reader (`attachV41`) has no caller in 4.2 — so they had no effect
  // on the network. They are also outside the norm: the sources of the
  // first neighbour are closed (§11.8 table, §11.8a "the first pointer is
  // always learned, never built in", D-12). The card of the first contact
  // (§11.8 source 3) is read by mycelium itself.

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
  /// 3. **Withdraw** — until S408-P23 `armV41InviteLines` forgot the
  ///    V4.1 pseudo-peer here; that line was armed only under `attachV41`
  ///    and fell with `lib/core/tagline/`.
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
    // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
    _log.debug('§15.4 REDEEMED: invitation i=$idx g=${rec.generation}'
        '${rec.label.isEmpty ? '' : ' "${rec.label}"'} is used up with the acceptance '
        'by ${contact.displayName} and revoked');
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
        messageType: proto.MessageType.MT_CONTACT_REQUEST_RESPONSE,
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
        ..rotationTimestamp = Int64(DateTime.now().millisecondsSinceEpoch)
        ..mode = proto.KeyRotationMode.KEY_ROTATION_MODE_TAGS_VALID;
      final dataToSign = rotationMsg.writeToBuffer();
      rotationMsg.signature = SodiumFFI().signEd25519(
          dataToSign, identity.ed25519SecretKey);
      _detachedSend('MT_KEY_ROTATION_BROADCAST', sendToUser(
        recipientUserId: contact.nodeId,
        messageType: proto.MessageType.MT_KEY_ROTATION_BROADCAST,
        payload: Uint8List.fromList(rotationMsg.writeToBuffer()),
      ));
      // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
      _log.debug('Sent KEY_ROTATION_BROADCAST to newly accepted '
          '${contact.displayName} (${nodeIdHex.substring(0, 8)}) — '
          'rotation pending');
    }

    // Twin-Sync: notify other devices about accepted contact (§14.7 Type 0,
    // the accepting issuer; D-28). The body is in `cleona_service_own_line.dart`.
    _sendTwinContactAdded(contact);

    return sent;
  }

  /// Delete a contact and its conversation.
  @override
  void deleteContact(String nodeIdHex, {required String source}) {
    // V4.2 §12.5 (S388): a `pending` contact is a waiting question —
    // deleting is the refusal (inbox `inbox_reject`). Without this
    // decision the joiner would wait endlessly for a response.
    final deleted = _contacts[nodeIdHex];
    // The conversation leaves the profile — row, messages, attachments and
    // what the delivery layer's history kept of them, not only the entry in
    // memory (S401, PV-1). First: the history is reached through the
    // contact, which is removed below.
    _conversationLeavesProfile(nodeIdHex, openSendsStop: true);
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

  @override
  bool setAlwaysLoadImages(String entityIdHex, bool on) {
    final group = _groups[entityIdHex];
    final channel = group == null ? _channels[entityIdHex] : null;
    if (group == null && channel == null) return false;
    group?.alwaysLoadImages = on;
    channel?.alwaysLoadImages = on;
    group != null ? _saveGroups() : _saveChannels();
    onStateChanged?.call();
    // Switched on: what waits is collected now (§9.4).
    if (on && _skOn(entityIdHex)) {
      unawaited(_skCollect(entityIdHex, reason: 'always load images'));
    }
    return true;
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

  // NO HINT AFTER 7 DAYS WITHOUT AN ACKNOWLEDGEMENT (owner decision
  // 02.10.2026, decision 11, F4 = a). Until S403 a line was written into the
  // conversation here, once, when the user wrote to a contact that had not
  // acknowledged anything for 7 days; it advised a new contact request. A
  // contact that is away for more than 7 days is an ordinary case (v4_2
  // §9.1: the message "stays `in transit` when the holders have dropped it
  // after 7 days … the recipient asks the sender for it on return", §9.5):
  // the sender sees the single mark and nothing else.

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
    // A deleted message stays deleted (§21.5.2): a copy that arrives after
    // the deletion — or the message itself, where its deletion came first —
    // is not taken, and the file the receive path has just written for it
    // goes again. Before anything else, so that it opens no conversation.
    if (_deletionMarkHolds(msg.id, msg.senderNodeIdHex)) {
      final path = msg.filePath;
      if (path != null) _eraseAttachmentUnlessHeld(path);
      return false;
    }
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

    // §21.5.3: the deadline that applies NOW goes with the message ("existing
    // ones keep their original deadline"). For a received message it runs
    // from the moment it is READ, not from its arrival; it counts as read on
    // arrival only where it is not counted as unread either: the
    // conversation is open in the foreground. An own message runs from the
    // moment it is sent (`UiMessage.sentAt`, set by the status setter).
    msg.expiryMs ??= conv.config.expiryDurationMs ?? 0;
    if (!msg.isOutgoing &&
        _isAppResumed &&
        _activeConversationId == conversationId) {
      msg.readAt ??= DateTime.now();
    }

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
    // §16.2/§16.2.5: a member takes a post once by its post identifier — on
    // the shared key and on a pairwise leg the same post carries the same
    // one (mixed operation within 4.2, a member served both ways while the
    // author learns it is served on the shared key).
    final pid = msg.postId;
    if (pid != null &&
        !msg.isOutgoing &&
        conv.messages.any((m) =>
            m.postId == pid && m.senderNodeIdHex == msg.senderNodeIdHex)) {
      return false;
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
    // §21.5.1: an edit can arrive before the message it names (no
    // transport order, §18.1.3) and is buffered, not discarded — the
    // message that has just been inserted is the moment the buffered edit
    // is applied (`_pendingEditApply`).
    _pendingEditApply(msg, conversationId);
    if ((msg.expiryMs ?? 0) > 0) conv.expiryPending = true;
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

    // A message that arrives into the conversation open in the foreground is
    // read on arrival (§21.5.3, `readAt` above), so its read receipt goes out
    // now — through the one path that also serves the opening, which honours
    // `read_receipts_enabled` (§21.5.4), the group read mark (§16.2) and
    // `readReceiptSent` (no second receipt). Until S405 it went only at the
    // next opening and the sender kept showing `delivered` (R2-4).
    // Event-driven, one receipt per arriving message (working rule 5).
    if (!msg.isOutgoing &&
        _isAppResumed &&
        _activeConversationId == conversationId &&
        !SystemChannels.isSystemChannel(conversationId)) {
      markConversationRead(conversationId);
    }
    return true;
  }

  /// Mark a conversation as read — sends READ_RECEIPTs if enabled.
  @override
  void markConversationRead(String conversationId) {
    final conv = conversations[conversationId];
    if (conv == null) return;

    // §21.5.3: reading starts the expiry deadline — whether or not a read
    // receipt goes out.
    final stampedRead = _stampIncomingRead(conv, DateTime.now());

    final hadUnread = conv.unreadCount > 0 || stampedRead;
    if (conv.unreadCount > 0) {
      conv.unreadCount = 0;
      onCancelNotificationAndroid?.call(conversationId);
      _updateBadgeCount();
    }

    // Send READ_RECEIPTs for unread incoming messages (if readReceipts enabled).
    // Runs regardless of unreadCount — messages may have status != read even
    // when the badge counter was already cleared.
    //
    // §21.5.5 STO-4 (owner decision 14.10.2026: couple): whoever withholds
    // the delivery status (§14.7.4) sends no read receipt either — "read"
    // would reveal the arrival through the stronger signal. Purely local;
    // the peer simply sees no read receipt, as with read receipts off.
    //
    // What is read while suppressed is SETTLED, never confirmed later
    // (§16.2.3 principle: a withholding leg never contributes — otherwise the
    // later receipt would reveal exactly what was concealed). The flag is set
    // without a send; only messages read after switching back on are
    // confirmed.
    // §16.2.3/§16.2.5: on the shared key members send no read marks.
    if (!conv.config.readReceipts ||
        _skOn(conversationId) ||
        _withholdsDeliveryStatusInConversation(conversationId)) {
      ensureLoaded(conversationId);
      for (final msg in conv.messages) {
        if (!msg.isOutgoing && !msg.readReceiptSent) {
          msg.readReceiptSent = true;
          persistMessage(conv.id, msg);
        }
      }
      if (hadUnread) {
        _saveConversations();
        onStateChanged?.call();
      }
      return;
    }

    var sentReceipts = false;
    ensureLoaded(conversationId);
    for (final msg in conv.messages) {
      // S390: the flag carries "my read receipt has already gone out" (or,
      // since STO-4, "was read while suppressed and is settled"),
      // not the delivery state (§9.1 lists four, and a read note
      // is none of them). It prevents the same as before: a second
      // receipt for the same message on every opening (§1.2).
      if (!msg.isOutgoing && !msg.readReceiptSent) {
        msg.readReceiptSent = true;
        persistMessage(conv.id, msg);
        sentReceipts = true;
        if (msg.senderNodeIdHex.isEmpty) continue;
        final senderUserId = hexToBytes(msg.senderNodeIdHex);
        // §16.2: the read mark of a group post names its post identifier
        // and the group, so that the author finds the post in the group. A
        // post that came without a post identifier is marked as before.
        final group = msg.postId == null ? null : _groups[conversationId];
        final receipt = proto.ReadReceipt()
          ..messageId =
              hexToBytes(group == null ? msg.id : msg.referenceId)
          ..readAt = Int64(DateTime.now().millisecondsSinceEpoch);
        _detachedSend('MT_READ_RECEIPT', sendToUser(
          recipientUserId: senderUserId,
          messageType: proto.MessageType.MT_READ_RECEIPT,
          payload: receipt.writeToBuffer(),
          // The group identifier only: a read mark is no post, it carries no
          // membership state (GM-1) — the author checks the sender against
          // its own member list.
          groupId: group == null ? null : hexToBytes(conversationId),
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
    // §16.2.5 step 4: opening a group or channel on the shared key is an
    // edge of its collection.
    if (conversationId != null && _skOn(conversationId)) {
      unawaited(_skCollect(conversationId, reason: 'opened'));
    }
  }

  @override
  void setAppResumed(bool isResumed, {bool triggerNodeHarvest = true}) {
    _isAppResumed = isResumed;
    // Here stood `_identityPublisher?.setForeground(isResumed)` — the
    // adaptive liveness TTL of the 2D DHT (§2.2.4) — and, until S408-P23,
    // the V4.1 catch-up harvest on the foreground edge (`v41OnForeground`,
    // set only by `attachV41`). In 4.2 the foreground return is an edge of
    // the delivery layer itself: `main.dart` calls the node's collection
    // once per process, which is why every caller passes
    // `triggerNodeHarvest: false`.
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
  ///   Quiet — the device's master mute or this identity's quiet hours
  ///        (§22.8, `notification_silence.dart`).
  ///
  /// L5 (_isAppResumed gate) lives in [_postAndroidNotification] and only
  /// affects the Android system notification, not in-app sound/vibrate.
  ///
  /// Badge updates run in a different code path and are NOT gated by this.
  bool _shouldSuppressNotification(String conversationId, int messageTimestampMs) {
    // Quiet hours of this identity, master mute of the device (§22.8).
    if (notificationSilenced(
        masterMute: masterMute,
        settings: notificationSound.settings,
        now: DateTime.now())) {
      return true;
    }
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

  /// The send time [event]'s sender claims, for L3 of
  /// [_shouldSuppressNotification] and nothing else. It is an assertion
  /// without evidence (§22.5.3) and decides neither display nor sorting nor
  /// expiry: all a sender gains by choosing it is whether its own message
  /// rings during the start phase. A message without the claim counts as old.
  int _claimedSendTimeMs(HarvestEvent event) =>
      event.claimedSentAt?.millisecondsSinceEpoch ?? 0;

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

  @override
  void updateNotificationSettings(NotificationSettings settings) {
    unawaited(notificationSound.updateSettings(settings));
  }

  @override
  void previewRingtone(Ringtone ringtone) {
    unawaited(notificationSound.previewRingtone(ringtone));
  }

  @override
  void stopRingtonePreview() {
    unawaited(notificationSound.stopPreview());
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
    _detachedSend('MT_TYPING_INDICATOR', sendToUser(
      recipientUserId: contact.nodeId,
      messageType: proto.MessageType.MT_TYPING_INDICATOR,
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
  void mirrorChannelToOwnDevices(ChannelInfo channel) =>
      _sendTwinChannelJoined(channel);
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
  bool mayPostInGroup(String entityIdHex) =>
      _groupMayPost(entityIdHex, identity.userIdHex);
  @override
  bool tallyAtCreator(String entityIdHex) =>
      _channels.containsKey(entityIdHex) || _groupReactsViaOwner(entityIdHex);
  @override
  bool anonymousPollPossible(String entityIdHex) {
    final n = _groups[entityIdHex]?.members.length ??
        _channels[entityIdHex]?.members.length;
    if (n == null) return true;
    return anonymousPollPossibleFor(members: n, onSharedKey: _skOn(entityIdHex));
  }

  @override
  Future<Set<String>?> sharedKeyServe(String groupIdHex,
          proto.MessageType messageType, Uint8List payload) =>
      _skServe(groupIdHex,
          type: messageType,
          payload: payload,
          messageId: SodiumFFI().randomBytes(16));
  @override
  Future<void> sendEncryptedPayload(
    Uint8List recipientUserId,
    proto.MessageType messageType,
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
  /// `TextMessage.replyToMessageId` is a 16-byte field. Both send paths
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
  bool isRemovedFromGroup(String conversationId) =>
      _groupLeftMark(conversationId)?.removed ?? false;

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

    // §16.2.2: at least two members besides the owner — with one other
    // person the conversation is a direct chat. `members` holds the owner.
    if (!groupCreationAllowed(members.length - 1)) {
      _log.warn('Group needs at least $kGroupMinOtherMembers members besides '
          'its owner (${members.length - 1} given)');
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

    // GROUP_INVITE to each member, one leg each (§16.2.2). The creator is
    // joined and signs its own entry; every other member is NEW, so each leg
    // carries every signed entry there is and the seeds of every pair of the
    // new members (B-3, §4.3) — `_broadcastGroupUpdate`.
    _groupOwnEntrySign(group);
    _saveGroups();
    await _broadcastGroupUpdate(group, newMembers: {
      for (final m in members.keys)
        if (m != identity.userIdHex) m,
    });
    _sendTwinGroupCreated(group);
    // §16.2.1: created with 17 members or more, the group starts on the
    // shared key; members get their keys as they join.
    await _skSizeCheck(groupIdHex);

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
    // §16.2.2: in announcement mode only the owner and the admins post.
    if (!_groupMayPost(groupIdHex, identity.userIdHex)) {
      _log.warn('sendGroupTextMessage refused: announcement mode, this '
          'identity is a member');
      return null;
    }

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

    // V3 group fan-out: TextMessage sub-message + sendToUser per member.
    // ApplicationFrame.group_id (Field 17) carries the conversation tag so
    // receivers dispatch into the matching group tab.
    final tm = proto.TextMessage()
      ..text = text
      ..formatHint = 'plain';
    // Sender-side link preview, as in `sendTextMessage` (S410 follow-up,
    // owner 29.10.2026 "A"): the post is shown at once and holds its legs
    // and its post line while the preview is fetched; it goes with the
    // preview embedded (`TextMessage.link_preview`, field 5, the field a
    // group post carried before too), and nothing written to the group
    // afterwards overtakes it — `_sendPostWithLinkPreview`.
    final hasUrl =
        _linkPreviewSettings.enabled && extractFirstUrl(text) != null;
    if (replyToMessageId != null && replyToMessageId.isNotEmpty) {
      // S368: checked above — `hexToBytes` can no longer throw here.
      // §16.2: a quote names the post identifier of the quoted group post —
      // the one identifier every member holds for it. A quoted post that
      // came without one is named by the identifier it is kept under here.
      tm.replyToMessageId =
          hexToBytes(_referenceIdOf(groupIdHex, replyToMessageId));
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
    // §16.2: ONE post identifier per post, carried in every leg.
    final postId = SodiumFFI().randomBytes(kPostIdLength);
    final msg = UiMessage(
      id: localId,
      conversationId: groupIdHex,
      senderNodeIdHex: identity.userIdHex,
      text: text,
      timestamp: DateTime.now(),
      type: UiMessageType.text,
      status: MessageStatus.resting,
      isOutgoing: true,
      postId: bytesToHex(postId),
      replyToMessageId: replyToMessageId,
      replyToText: replyToText,
      replyToSender: replyToSender,
    );

    _addMessageToConversation(groupIdHex, msg, isGroup: true);

    await Future.delayed(Duration.zero);

    // §5.8/§14.7.4: every leg gets its OWN wire messageId, recorded on the
    // UiMessage so the incoming DELIVERY_RECEIPT can be attributed to the
    // member that sent it. A shared id would collide in `AckTracker._pending`
    // (keyed by messageId alone) and evict each previous member's timer.
    bool anySent = false;
    // §16.2.5: on the shared key the post is encrypted and signed once,
    // deposited and nudged; only members without the capability get a leg.
    // A post with a link is sealed now as it would go without a preview
    // (kept for a process that ends during the fetch) and holds the post
    // line of the group until it is sealed again with the preview.
    final pairwise = await _skServe(groupIdHex,
        type: proto.MessageType.MT_TEXT,
        payload: basePayload,
        messageId: postId,
        postId: postId,
        epoch: gmEpoch,
        hash: gmHash,
        msg: msg,
        linkWaits: hasUrl);
    if (pairwise != null) anySent = true;
    final linkLegs = <String, String>{};
    for (final member in group.members.values) {
      if (member.nodeIdHex == identity.userIdHex) continue;
      if (pairwise != null && !pairwise.contains(member.nodeIdHex)) continue;
      final legId = SodiumFFI().randomBytes(16);
      msg.fanoutLegs[member.nodeIdHex] = bytesToHex(legId);
      if (hasUrl) {
        // The leg takes its place in the line of this member NOW, before
        // any await, so that what is written after it waits behind it.
        _fileOrderLinkTake(
          recipientUserId: hexToBytes(member.nodeIdHex),
          messageId: legId,
          payload: basePayload,
          groupId: groupIdBytes,
          groupMembershipEpoch: gmEpoch,
          groupMembershipHash: gmHash,
          postId: postId,
        );
        linkLegs[member.nodeIdHex] = bytesToHex(legId);
        anySent = true;
        continue;
      }
      final ok = await sendToUser(
        recipientUserId: hexToBytes(member.nodeIdHex),
        messageType: proto.MessageType.MT_TEXT,
        payload: basePayload,
        messageId: legId,
        groupId: groupIdBytes,
        groupMembershipEpoch: gmEpoch,
        groupMembershipHash: gmHash,
        postId: postId,
      );
      if (ok) anySent = true;
    }

    // AP-4 (§5.1b/§5.1c K2): the ternary over `anyPlacedNowhere`/`anyL3Only`
    // has been dropped without replacement — "L3 placed" is no longer an event in V4.1.
    // The aggregate over the WEAKEST leg stays (v4_1 §21.5.5
    // "Aggregation per leg"), but it now reads the delivery register instead
    // of the send result. An offline recipient is still
    // NO error: for him the cell lies on the tag line.
    _applyOutgoingLegStatus(msg, msg.fanoutLegs.values.toList());
    if (anySent) statsCollector.addMessageSent();
    onStateChanged?.call();
    _saveConversations();
    if (hasUrl) {
      unawaited(_sendPostWithLinkPreview(msg, tm,
          type: proto.MessageType.MT_TEXT,
          legs: linkLegs,
          onSharedKey: pairwise != null,
          epoch: gmEpoch,
          hash: gmHash));
    }

    // §14.7, type 2: "mirror a message sent on one device" — the table
    // names no conversation kind. Until S403 only the 1:1 path mirrored
    // (`sendTextMessage`), a group post never reached the own other
    // devices, while `editMessage`/`deleteMessage` DID mirror their
    // requests — they met nothing there and left a mark without a
    // message (S401, finding NB-15).
    _sendTwinSync(proto.TwinSyncType.MESSAGE_SENT, Uint8List.fromList(utf8.encode(jsonEncode({
      'conversationId': groupIdHex,
      'text': text,
      'messageId': msg.id,
      'timestamp': msg.timestamp.millisecondsSinceEpoch,
    }))));
    return msg;
  }

  @override
  Future<bool> joinGroup(String groupIdHex) => _groupJoin(groupIdHex);

  @override
  Future<bool> leaveGroup(String groupIdHex) async {
    final group = _groups[groupIdHex];
    if (group == null) return false;
    // The membership state this device leaves with (§16.2.2): the mark of
    // the leaving keeps it, and only a newer state is a new invitation.
    final epochAtLeaving = group.membershipEpoch;

    // §16.2.2: only an owner or admin changes the membership state — a
    // plain member's update was rejected by every receiver (GM-1), N legs
    // for nothing; its GROUP_LEAVE below is what the others act on.
    final myRole = group.members[identity.userIdHex]?.role;
    final recordsChange = myRole == 'owner' || myRole == 'admin';
    String? heir;
    // If owner leaving, transfer ownership to first admin (or first member)
    if (group.ownerNodeIdHex == identity.userIdHex && group.members.length > 1) {
      final otherMembers = group.members.values.where((m) => m.nodeIdHex != identity.userIdHex);
      final newOwner = otherMembers.where((m) => m.role == 'admin').firstOrNull
          ?? otherMembers.first;
      newOwner.role = 'owner';
      group.ownerNodeIdHex = newOwner.nodeIdHex;
      heir = newOwner.nodeIdHex;
      // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
      _log.debug('Ownership transferred to ${newOwner.displayName} before leaving');
    }

    // Remove self from member list before broadcasting
    group.members.remove(identity.userIdHex);
    group.membershipEpoch++;

    // Broadcast updated group (without us) to remaining members — as a
    // change where the member reads it (§16.2.2).
    if (group.members.isNotEmpty && recordsChange) {
      await _broadcastGroupUpdate(group,
          removed: {identity.userIdHex}, changed: {?heir});
    }

    // V3 GROUP_LEAVE fan-out
    final leaveMsg = proto.GroupLeave()..groupId = hexToBytes(groupIdHex);
    final leaveBytes = Uint8List.fromList(leaveMsg.writeToBuffer());
    final groupIdBytes = hexToBytes(groupIdHex);
    for (final member in group.members.values) {
      _detachedSend('MT_GROUP_LEAVE', sendToUser(
        recipientUserId: hexToBytes(member.nodeIdHex),
        messageType: proto.MessageType.MT_GROUP_LEAVE,
        payload: leaveBytes,
        groupId: groupIdBytes,
      ));
    }

    // §16.2.2: "Leaving removes the local conversation along with the
    // membership record." Before the pairs and the group go: the histories
    // of the delivery layer are reached through them.
    _conversationLeavesProfile(groupIdHex, openSendsStop: false);
    // B-3 (§4.3): this group carries none of our group pairs any more; a
    // pair without another shared group ends with it.
    myceliumMailbox?.groupPairLeave(hexToBytes(groupIdHex));
    _groups.remove(groupIdHex);
    _skForget(groupIdHex); // §16.2.5: the keys leave with the group
    // §16.2.2: "A device that left a group keeps a mark of the group
    // identifier; a post for a group it left is discarded, and a new
    // invitation lifts the mark." (`cleona_service_group_gate.dart`)
    _groupMarkLeft(groupIdHex, epochAtLeaving);
    // §14.7 Type 21 GROUP_LEFT (S403, owner decision 03.10.2026, V1 = A):
    // the own other devices remove the conversation and set the same
    // mark; a post they would mirror from here would be discarded on this
    // device, so they must not show it either.
    _sendTwinGroupLeft(groupIdHex, epochAtLeaving);
    _saveGroups();
    _saveConversations();
    onStateChanged?.call();
    _log.info('Left group $groupIdHex');
    return true;
  }

  /// §16.2.2: "When every other member has left or been removed and the own
  /// identity is the only member, the application asks once whether to
  /// delete the group; deleting removes it as leaving does, and keeping it
  /// leaves the conversation readable." Runs after every change of a member
  /// list (a leave received, a removal, a membership update or resync); the
  /// caller saves. Asked is asked: a kept group is never asked again.
  void _groupAloneCheck(GroupInfo group) {
    final alone = group.members.length == 1 &&
        group.members.containsKey(identity.userIdHex);
    if (alone && group.aloneQuestion == null) {
      group.aloneQuestion = kGroupAloneDue;
      _log.info('Group ${group.groupIdHex.substring(0, 8)}: the own identity '
          'is the only member — the user is asked once whether to delete it');
    } else if (!alone && group.aloneQuestion == kGroupAloneDue) {
      // Members came back before the user answered: nothing left to ask.
      group.aloneQuestion = null;
    }
  }

  @override
  Future<bool> answerGroupAloneQuestion(String groupIdHex,
      {required bool delete}) async {
    final group = _groups[groupIdHex];
    if (group == null || !group.aloneQuestionDue) return false;
    // §16.2.2: "deleting removes it as leaving does".
    if (delete) return leaveGroup(groupIdHex);
    group.aloneQuestion = kGroupAloneAnswered;
    _saveGroups();
    onStateChanged?.call();
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
    _groupAloneCheck(group);
    _saveGroups();

    // Send GROUP_INVITE to new member AND broadcast updated member list to
    // existing members — otherwise their local state stays stale and they
    // can't target the new member for role changes, messages, etc.
    // B-3: the new member gets every signed entry, and every pair it forms
    // with a co-member gets its seed in both legs (§4.3, §16.2.2).
    await _broadcastGroupUpdate(group, newMembers: {memberNodeIdHex});
    await _skSizeCheck(groupIdHex); // §16.2.1: the switch at 17

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
    _groupAloneCheck(group);
    _saveGroups();

    // The change to every remaining member and to the removed one (§16.2.2,
    // S403 V2: "A member removed by the owner or an admin receives the new
    // member list as well") — the list without it, or the change naming it,
    // is its removal (`_handleGroupInvite`, `_groupMembersChangeReceived`).
    await _broadcastGroupUpdate(group,
        removed: {memberNodeIdHex}, extraTo: {memberNodeIdHex});
    _groupPairsSync(group); // B-3: the removed member's pair ends here too
    // §16.2.5: the removal starts a new generation; the removed member
    // receives none.
    await _skDeparted(groupIdHex, removedHere: true);

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
      // §16.2.2: "Role updates go to all members" — the membership update
      // carries the role. No separate CHANNEL_ROLE_UPDATE any more: a
      // receiver that took the update first counted the epoch a second time
      // on it and fell one epoch ahead of the owner — the owner's next
      // update was then "late" and discarded (S407 group list, F-1b).
      await _broadcastGroupUpdate(group, changed: {
        memberNodeIdHex,
        if (role == 'owner') identity.userIdHex,
      });
      // §16.2.5: a new admin or owner holds W_g (the transfer hands the new
      // owner W_g); the notice goes to it as to every owner and admin.
      await _skRoleChanged(entityIdHex, memberNodeIdHex);

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
      final shortBefore = _channelShortList(channel);
      member.role = role;

      if (role == 'owner') {
        channel.members[identity.userIdHex]?.role = 'admin';
        channel.ownerNodeIdHex = memberNodeIdHex;
      }

      channel.membershipEpoch++;
      _saveChannels();
      if (_channelShortList(channel)) {
        // §16.2.2: a change of role goes to every member as a change.
        await _channelShortRole(channel, member, oldRole);
      } else if (shortBefore) {
        // A member that has not shown the capability became owner or
        // admin: the channel goes back to the complete list for everyone.
        await _broadcastChannelUpdate(channel);
      } else {
        _broadcastRoleUpdate(
            entityIdHex, memberNodeIdHex, role, channel.members);
      }
      // §16.2.4: the previous owner hands over who holds which reaction.
      if (role == 'owner') {
        _channelReactionHandoverSend(channel, memberNodeIdHex,
            keepConversation: true);
      }
      // §14.7 Type 22: the own other devices take the changed role too.
      _sendTwinChannelJoined(channel);
      // §16.2.5: a new admin or owner holds W_g (the transfer hands the new
      // owner W_g).
      await _skRoleChanged(entityIdHex, memberNodeIdHex);

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
      _detachedSend('MT_CHANNEL_ROLE_UPDATE', sendToUser(
        recipientUserId: hexToBytes(mHex),
        messageType: proto.MessageType.MT_CHANNEL_ROLE_UPDATE,
        payload: roleBytes,
        groupId: entityIdBytes,
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
  ///
  /// B-3 (§16.2.2, E2 = a + c): built PER LEG for [recipientHex]. Full member
  /// entries (the self-signed address) travel for the members in [fresh],
  /// and for all of them when the receiver itself is in [newMembers]; the
  /// seeds ([seeds], drawn once per update) of the receiver with every
  /// co-member of a pair that involves a new member — never with the inviter
  /// (§4.3). Without [recipientHex] (the membership resend): every full
  /// entry, no seed.
  Uint8List _buildSignedGroupInviteBytes(GroupInfo group,
      {String? recipientHex,
      Set<String> fresh = const {},
      Set<String> newMembers = const {},
      Map<String, Uint8List>? seeds}) {
    final invite = proto.GroupInvite()
      ..groupId = hexToBytes(group.groupIdHex)
      ..groupName = group.name
      ..inviterId = identity.nodeId;
    // §16.2.2 "An invitation contains the group ID, name, optionally an
    // image and description" — every update as well: a receiver that reads
    // the complete list replaces both with what it carries (a v4.2.3 device
    // does, `398a6e40` `_handleGroupInvite`). A 4.2.3 stand-in of a probe
    // sends neither, as 4.2.3 does.
    if (!channelReceiveAs423) {
      final about = group.description;
      if (about != null && about.isNotEmpty) invite.groupDescription = about;
      final picture = _pictureBytes(group.pictureBase64);
      if (picture != null) invite.groupPicture = picture;
    }
    final newReceiver =
        recipientHex == null || newMembers.contains(recipientHex);
    for (final m in group.members.values) {
      invite.members.add(_groupMemberWire(m,
          full: newReceiver || fresh.contains(m.nodeIdHex)));
    }
    if (recipientHex != null && seeds != null) {
      for (final x in group.members.keys) {
        if (x == identity.userIdHex || x == recipientHex) continue;
        if (!newMembers.contains(recipientHex) && !newMembers.contains(x)) {
          continue;
        }
        invite.pairSeeds.add(proto.GroupPairSeed()
          ..memberId = hexToBytes(x)
          ..seed = _groupSeedFor(seeds, recipientHex, x));
      }
    }
    invite.membershipEpoch = Int64(group.membershipEpoch);
    final hash = _computeMembershipHash(group.membershipEpoch, group.groupIdHex, group.members);
    invite.membershipHash = hash;
    invite.membershipSigEd25519 = SodiumFFI().signEd25519(hash, identity.ed25519SecretKey);
    invite.membershipSigMlDsa = OqsFFI().mlDsaSign(hash, identity.mlDsaSecretKey);
    // §16.2.5 "Joining": on the shared key the update carries the step.
    final step = _skStep(_sk(group.groupIdHex));
    if (step != null) invite.sharedKeyStep = step;
    return Uint8List.fromList(invite.writeToBuffer());
  }

  /// Broadcast updated group member list to all members via GROUP_INVITE —
  /// one leg per member, see [_buildSignedGroupInviteBytes] for [fresh] and
  /// [newMembers] (B-3).
  ///
  /// ONE EPOCH, ONE UPDATE (S406-CATCHUP, §16.2.2): every leg is built HERE,
  /// before the first `await`, from the member state of THIS change. Until
  /// S406 each leg was built only when its turn came, after the send of the
  /// previous one: a `GROUP_JOIN` taken in between raised the epoch, and the
  /// later legs carried the NEW epoch with the full entries of the OLD
  /// change. Their receiver then held two different updates under one
  /// epoch, discarded the second as a replay (GM-1) and never learned the
  /// signed entry of the other joiner — no group pair (`smoke_catch_up_run`,
  /// `smoke_group_join_concurrent_run.dart`). The updates of one group are
  /// handed over one after the other ([_groupUpdateSending]): a member gets
  /// them in the order of their epochs, so a later one does not overtake
  /// the earlier one that carries a full entry it lacks.
  Future<void> _broadcastGroupUpdate(GroupInfo group,
      {Set<String> fresh = const {},
      Set<String> newMembers = const {},
      Set<String> changed = const {},
      Set<String> removed = const {},
      Set<String> extraTo = const {}}) async {
    final gid = group.groupIdHex;
    // §16.2.2: the change as a change where the member reads it
    // (`cleona_service_group_list.dart`).
    final legs = _groupUpdateLegs(group,
        fresh: fresh,
        newMembers: newMembers,
        changed: changed,
        removed: removed,
        extraTo: extraTo);
    final before = _groupUpdateSending[gid];
    final turn = Completer<void>();
    _groupUpdateSending[gid] = turn.future;
    try {
      if (before != null) await before;
      await _groupUpdateLegsSend(group, legs);
    } finally {
      turn.complete();
      if (identical(_groupUpdateSending[gid], turn.future)) {
        _groupUpdateSending.remove(gid);
      }
    }
  }

  /// Hands over the [legs] built by [_broadcastGroupUpdate] — all at once
  /// (§16.2 "Fan-out does not serialize"); a leg that found no way waits for
  /// the membership resend.
  Future<void> _groupUpdateLegsSend(
      GroupInfo group, List<_GroupLeg> legs) async {
    final groupId = hexToBytes(group.groupIdHex);
    final results = await Future.wait([
      for (final (to, kind, payload) in legs)
        () {
          _groupListBytesNote(to, payload.length);
          return sendToUser(
            recipientUserId: hexToBytes(to),
            messageType: kind,
            payload: payload,
            groupId: groupId,
          );
        }(),
    ]);
    // A leg the seam took over goes out without the app doing anything more
    // — resting in the delivery layer when it has no way, sent again at its
    // edges and closed after 14 days (§9.3, D-47). A leg it did NOT take
    // over never will be (§22.5.1: no contact and no group pair, no keys):
    // it is failed, and the app sends nothing again (§11.3a; S408-LEBENSLAUF
    // P19 — until then a queue of its own re-sent it at every network change).
    for (var i = 0; i < legs.length; i++) {
      if (results[i]) continue;
      _log.debug('GROUP_UPDATE broadcast: ${legs[i].$1.substring(0, 8)} '
          'not taken over — failed');
    }
    _log.info('Broadcast group update for "${group.name}" to ${legs.length} members');
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
      roleEpoch: 1,
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

    // Send CHANNEL_INVITE to each subscriber (pairwise encrypted); every
    // subscriber is new, so every pair of them gets its `s_AB` (§4.3).
    if (members.length > 1 && _channelShortList(channel)) {
      // §16.2.2: each subscriber gets the owner only, no co-subscriber.
      await _channelShortCreate(channel);
    } else if (members.length > 1) {
      await _broadcastChannelUpdate(channel,
          newMembers: members.keys.toSet()..remove(identity.userIdHex));
    } else {
      // No subscriber yet, so no broadcast that mirrors it (§14.7 Type 22).
      _sendTwinChannelJoined(channel);
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

    // §16.2.1: a private channel created with 17 members or more starts on
    // the shared key; members get their keys as they join.
    if (!isPublic) await _skSizeCheck(channelIdHex);

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

    // §16.7 (S407 SK-4): system channels are ownerless and have no member
    // fan-out — a report is an object of the durable class and goes
    // through `systemChannelApi` (preview, consent, deposit with three
    // holders). Nothing is posted here.
    if (SystemChannels.isSystemChannel(channelIdHex)) {
      _log.warn('sendChannelPost: system channel — deposit via the system '
          'channel view');
      return null;
    }

    // Only owner/admin can post
    if (!_hasChannelPermission(channel, 'post')) {
      _log.warn('No permission to post in channel');
      return null;
    }

    // V3 CHANNEL_POST: TextMessage sub-message + sendToUser per member with
    // groupId so receivers route to the channel tab.
    final tm = proto.TextMessage()
      ..text = text
      ..formatHint = 'plain';
    // Sender-side link preview as for a group post (S410 follow-up, owner
    // 29.10.2026 "A"): shown at once, sent with the preview embedded once
    // it is fetched, nothing overtakes it — `_sendPostWithLinkPreview`.
    final hasUrl =
        _linkPreviewSettings.enabled && extractFirstUrl(text) != null;
    final basePayload = Uint8List.fromList(tm.writeToBuffer());
    final channelIdBytes = hexToBytes(channelIdHex);

    // GM-4 (§9.1.4): tag channel posts with membership epoch+hash
    final chEpoch = channel.membershipEpoch;
    final chHash = _computeChannelMembershipHash(chEpoch, channelIdHex, channel.members);

    // §5.8: the fan-out is awaited — not for error handling, but because the
    // post's status is otherwise unknowable. The previous fire-and-forget
    // loop let the UiMessage below claim `sent` even with zero connectivity.
    // No leg tracking beyond the identifiers: `CHANNEL_POST` is not
    // ack-worthy (`AckTracker.isAckWorthy`), so no receipt ever comes
    // back and a channel post can never reach `delivered` (§14.7.4
    // "Channels"). The post stays at `placing`. That is more honest than
    // the old `sent`, but it is a reported gap, not a final state.
    //
    // S403 (§16.2, §21.5.2 level 2): every subscriber's leg carries its OWN
    // wire identifier now, recorded on the UiMessage — the pattern of the
    // group fan-out. Until S403 no identifier was passed and none recorded,
    // so an edit or a deletion of the post could name nothing per leg and
    // `editMessage`/`deleteMessage` refused a channel post altogether
    // (S401, finding NB-18).
    final msg = UiMessage(
      id: bytesToHex(SodiumFFI().randomBytes(16)),
      conversationId: channelIdHex,
      senderNodeIdHex: identity.userIdHex,
      text: text,
      timestamp: DateTime.now(),
      type: UiMessageType.channelPost,
      status: MessageStatus.resting,
      isOutgoing: true,
      // §16.2: one post identifier in every leg — the reactions of §16.2.4
      // name it at the owner and in the totals. An older 4.2 subscriber
      // ignores the field and keeps naming its leg.
      postId: bytesToHex(SodiumFFI().randomBytes(kPostIdLength)),
    );

    _addMessageToConversation(channelIdHex, msg, isChannel: true);

    // §16.2.5: on the shared key the post is encrypted and signed once,
    // deposited and nudged; only members without the capability get a leg.
    // A post with a link holds the post line until it is sealed again with
    // its preview (see `sendGroupTextMessage`).
    final pairwise = await _skServe(channelIdHex,
        type: proto.MessageType.MT_CHANNEL_POST,
        payload: basePayload,
        messageId: hexToBytes(msg.postId!),
        postId: hexToBytes(msg.postId!),
        epoch: chEpoch,
        hash: chHash,
        msg: msg,
        linkWaits: hasUrl);
    final linkLegs = <String, String>{};
    for (final member in channel.members.values) {
      if (member.nodeIdHex == identity.userIdHex) continue;
      if (pairwise != null && !pairwise.contains(member.nodeIdHex)) continue;
      // §16.2: the identifier of THIS leg — the subscriber holds the post
      // under it, and the author's edit and deletion name it (§21.5.1).
      final legId = SodiumFFI().randomBytes(16);
      msg.fanoutLegs[member.nodeIdHex] = bytesToHex(legId);
      if (hasUrl) {
        // Its place in the line of this subscriber, before any await.
        _fileOrderLinkTake(
          recipientUserId: hexToBytes(member.nodeIdHex),
          messageId: legId,
          payload: basePayload,
          messageType: proto.MessageType.MT_CHANNEL_POST,
          groupId: channelIdBytes,
          groupMembershipEpoch: chEpoch,
          groupMembershipHash: chHash,
          postId: hexToBytes(msg.postId!),
        );
        linkLegs[member.nodeIdHex] = bytesToHex(legId);
        continue;
      }
      await sendToUser(
        recipientUserId: hexToBytes(member.nodeIdHex),
        messageType: proto.MessageType.MT_CHANNEL_POST,
        payload: basePayload,
        groupId: channelIdBytes,
        messageId: legId,
        groupMembershipEpoch: chEpoch,
        groupMembershipHash: chHash,
        postId: hexToBytes(msg.postId!),
      );
    }
    // The row went into the store before its legs existed — write it again
    // with them, so an edit or a deletion after a restart still finds the
    // leg of every subscriber (§21.4.1: every change to a message goes
    // into the store).
    persistMessage(channelIdHex, msg);
    statsCollector.addMessageSent();
    onStateChanged?.call();
    _saveConversations();
    if (hasUrl) {
      unawaited(_sendPostWithLinkPreview(msg, tm,
          type: proto.MessageType.MT_CHANNEL_POST,
          legs: linkLegs,
          onSharedKey: pairwise != null,
          epoch: chEpoch,
          hash: chHash));
    }

    // §14.7, type 2: "mirror a message sent on one device" — no exception
    // for a channel post either. The channel itself reaches the own other
    // devices by no twin type (§14.7 "Deliberately not on the list"); the
    // mirror applies where they hold it, and is dropped where they do not.
    _sendTwinSync(proto.TwinSyncType.MESSAGE_SENT, Uint8List.fromList(utf8.encode(jsonEncode({
      'conversationId': channelIdHex,
      'text': text,
      'messageId': msg.id,
      'timestamp': msg.timestamp.millisecondsSinceEpoch,
    }))));

    return msg;
  }

  @override
  Future<bool> leaveChannel(String channelIdHex) async {
    final channel = _channels[channelIdHex];
    if (channel == null) return false;
    // The membership state this device leaves with (§16.2.2): the mark
    // keeps it, and only a newer state is a new subscription.
    final epochAtLeaving = channel.membershipEpoch;
    final iAmRole = _channelIsRole(channel.members[identity.userIdHex]);

    if (iAmRole && _channelShortList(channel)) {
      // §16.2.2: owner or admin of a channel on the short list — the
      // leaving is a change of the role state to every member.
      await _channelShortLeave(channel);
    } else {
      await _channelLeaveAsBefore(channel, iAmRole);
    }

    // §4.3: the channel no longer carries any pair of this identity.
    myceliumMailbox?.groupPairLeave(hexToBytes(channelIdHex));
    // Like a group (§16.2.2): the conversation goes with the membership.
    _conversationLeavesProfile(channelIdHex, openSendsStop: false);
    _channels.remove(channelIdHex);
    _skForget(channelIdHex); // §16.2.5: the keys leave with the channel
    // §16.2.2 (S403, V7): "The same mark is kept for a channel the device
    // left" — posts of a left channel are discarded, a new subscription
    // lifts the mark. And §14.7 Type 21 GROUP_LEFT carries the leaving of
    // a channel to the own other devices as well: the identity left, the
    // mark and the removal of the conversation are the same there.
    _groupMarkLeft(channelIdHex, epochAtLeaving);
    _sendTwinGroupLeft(channelIdHex, epochAtLeaving);
    _saveChannels();
    _saveConversations();
    onStateChanged?.call();
    _log.info('Left channel $channelIdHex');
    return true;
  }


  /// The leaving of [channel] as before the short list (§16.2.2): a channel
  /// on the complete list, or a subscriber.
  Future<void> _channelLeaveAsBefore(ChannelInfo channel, bool iAmRole) async {
    final channelIdHex = channel.channelIdHex;
    // If owner leaving, transfer ownership to first admin (or first member)
    if (channel.ownerNodeIdHex == identity.userIdHex && channel.members.length > 1) {
      final otherMembers = channel.members.values.where((m) => m.nodeIdHex != identity.userIdHex);
      final newOwner = otherMembers.where((m) => m.role == 'admin').firstOrNull
          ?? otherMembers.first;
      newOwner.role = 'owner';
      channel.ownerNodeIdHex = newOwner.nodeIdHex;
      // §16.2.4: the reactions go with the role, before the conversation goes.
      _channelReactionHandoverSend(channel, newOwner.nodeIdHex,
          keepConversation: false);
      // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
      _log.debug('Channel ownership transferred to ${newOwner.displayName} before leaving');
    }

    // Remove self from member list before broadcasting
    channel.members.remove(identity.userIdHex);
    channel.membershipEpoch++;

    // Broadcast updated channel (without us) to remaining members — only
    // from an owner or admin: everyone else's update fails every
    // receiver's authority gate (§16.2.2) and was N legs for nothing.
    if (channel.members.isNotEmpty && iAmRole) {
      await _broadcastChannelUpdate(channel);
    }

    // V3 CHANNEL_LEAVE fan-out — a subscriber holding the short list
    // reaches exactly the owner and the admins (§16.2.2).
    final leaveMsg = proto.ChannelLeave()..channelId = hexToBytes(channelIdHex);
    final leaveBytes = Uint8List.fromList(leaveMsg.writeToBuffer());
    final channelIdBytes = hexToBytes(channelIdHex);
    final leaving = [
      for (final member in channel.members.values)
        sendToUser(
          recipientUserId: hexToBytes(member.nodeIdHex),
          messageType: proto.MessageType.MT_CHANNEL_LEAVE,
          payload: leaveBytes,
          groupId: channelIdBytes,
        ),
    ];
    // The legs travel over the pairs of the channel, which end below.
    await Future.wait(leaving.map((f) => f.catchError((Object _) => false)));
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

    // §16.2.2: the invitee gets owner and admins, the owner/admins the
    // change; in a channel that does not run the short list, the updated
    // member list to all members.
    if (_channelShortList(channel)) {
      await _channelShortInvite(channel, memberNodeIdHex);
    } else {
      await _broadcastChannelUpdate(channel, newMembers: {memberNodeIdHex});
    }
    await _skSizeCheck(channelIdHex); // §16.2.1: the switch at 17

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
    final removed = channel.members.remove(memberNodeIdHex);
    if (removed == null) return false;
    channel.membershipEpoch++;
    _saveChannels();

    if (_channelShortList(channel)) {
      // §16.2.2: the change to owner/admins, the notice to the removed
      // subscriber; its pair ends after the notice.
      await _channelShortRemove(channel, removed);
    } else {
      _channelPairsSync(channel); // §4.3: the removed member's pair ends here
      // Broadcast updated member list
      await _broadcastChannelUpdate(channel);
    }
    // §16.2.5: the removal starts a new generation; the removed member
    // receives none.
    await _skDeparted(channelIdHex, removedHere: true);

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
    // MT_CHANNEL_ROLE_UPDATE — the receiver patches only the one member's role +
    // ownerNodeIdHex (_handleChannelRoleUpdate). The previous body broadcast a
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
  ///
  /// Per leg (§16.2.2, §4.3, as [_buildSignedGroupInviteBytes]): a receiver
  /// in [newMembers] — or every receiver without [recipientHex] — gets every
  /// member's signed entry, others only those of [fresh]; [seeds] carries
  /// `s_AB` of [recipientHex] with each co-member this invitation makes a
  /// co-member of it.
  Uint8List _buildSignedChannelInviteBytes(ChannelInfo channel,
      {String? recipientHex,
      Set<String> fresh = const {},
      Set<String> newMembers = const {},
      Map<String, Uint8List>? seeds}) {
    final invite = proto.ChannelInvite()
      ..channelId = hexToBytes(channel.channelIdHex)
      ..channelName = channel.name
      ..inviterId = identity.nodeId
      ..isPublic = channel.isPublic
      ..isAdult = channel.isAdult
      ..language = channel.language;
    if (channel.description != null) invite.channelDescription = channel.description!;
    // §16.2.2: the image travels with the invitation, as for a group. A
    // 4.2.3 stand-in sends none, as 4.2.3 does.
    final picture =
        channelReceiveAs423 ? null : _pictureBytes(channel.pictureBase64);
    if (picture != null) invite.channelPicture = picture;
    final newReceiver =
        recipientHex == null || newMembers.contains(recipientHex);
    for (final m in channel.members.values) {
      invite.members.add(_channelMemberWireAll(m,
          full: newReceiver || fresh.contains(m.nodeIdHex)));
    }
    if (recipientHex != null && seeds != null) {
      final toRole = _channelIsRole(channel.members[recipientHex]);
      for (final x in channel.members.keys) {
        if (x == identity.userIdHex || x == recipientHex) continue;
        if (!newMembers.contains(recipientHex) && !newMembers.contains(x)) {
          continue;
        }
        // §16.2.2 (S407 channel step 1): pairs only with the owner and the
        // admins — subscribers never send to each other.
        if (!toRole && !_channelIsRole(channel.members[x])) continue;
        invite.pairSeeds.add(proto.GroupPairSeed()
          ..memberId = hexToBytes(x)
          ..seed = _groupSeedFor(seeds, recipientHex, x));
      }
    }
    // §16.2.2: the role epoch beside the membership epoch; an older 4.2
    // device ignores it.
    if (!channel.isPublic) {
      invite.roleEpoch = Int64(_channelRoleEpoch(channel));
      invite.membersEpoch = Int64(channel.membershipEpoch);
    }
    invite.membershipEpoch = Int64(channel.membershipEpoch);
    final hash = _computeChannelMembershipHash(
        channel.membershipEpoch, channel.channelIdHex, channel.members);
    invite.membershipHash = hash;
    invite.membershipSigEd25519 =
        SodiumFFI().signEd25519(hash, identity.ed25519SecretKey);
    invite.membershipSigMlDsa =
        OqsFFI().mlDsaSign(hash, identity.mlDsaSecretKey);
    // §16.2.5 "Joining": on the shared key the update carries the step.
    final step = _skStep(_sk(channel.channelIdHex));
    if (step != null) invite.sharedKeyStep = step;
    return Uint8List.fromList(invite.writeToBuffer());
  }

  /// Broadcast updated channel member list to all members via CHANNEL_INVITE.
  ///
  /// One leg per member, all built before the first `await` from the member
  /// state of THIS change, and the updates of one channel handed over one
  /// after the other — the rule of [_broadcastGroupUpdate] (S406-CATCHUP).
  Future<void> _broadcastChannelUpdate(ChannelInfo channel,
      {Set<String> fresh = const {}, Set<String> newMembers = const {}}) async {
    final cid = channel.channelIdHex;
    final channelId = hexToBytes(cid);
    // §16.2.2: the own entry travels too; a channel from before it has none.
    final me = channel.members[identity.userIdHex];
    if (me != null && !me.hasSignedEntry && _channelOwnEntrySign(channel)) {
      _saveChannels();
      fresh = {...fresh, identity.userIdHex};
    }
    final seeds = <String, Uint8List>{};
    // Every member holds the complete list from here on (§16.2.2: what a
    // member that has not shown the capability receives).
    for (final m in channel.members.values) {
      m.viewEpoch = 0;
    }
    final legs = <(ChannelMemberInfo, Uint8List)>[
      for (final m in channel.members.values.toList())
        if (m.nodeIdHex != identity.userIdHex)
          (
            m,
            _buildSignedChannelInviteBytes(channel,
                recipientHex: m.nodeIdHex,
                fresh: fresh,
                newMembers: newMembers,
                seeds: seeds)
          ),
    ];
    final before = _groupUpdateSending[cid];
    final turn = Completer<void>();
    _groupUpdateSending[cid] = turn.future;
    try {
      if (before != null) await before;
      // §16.2 "Fan-out does not serialize": every leg is handed over at
      // once; legs to different members do not wait on each other.
      final handed = await Future.wait([
        for (final (m, inviteBytes) in legs)
          () {
            _channelListBytesNote(m.nodeIdHex, inviteBytes.length);
            return sendToUser(
              recipientUserId: hexToBytes(m.nodeIdHex),
              messageType: proto.MessageType.MT_CHANNEL_INVITE,
              payload: inviteBytes,
              groupId: channelId,
            );
          }(),
      ]);
      for (var i = 0; i < legs.length; i++) {
        final (m, _) = legs[i];
        if (!handed[i]) {
          // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
          // Not taken over, and never will be (§22.5.1): failed — no queue
          // of the app sends it again (S408-LEBENSLAUF P19, §9.3, D-47).
          _log.debug('CHANNEL_UPDATE broadcast: not taken over for ${m.nodeIdHex.substring(0, 8)} (${m.displayName}) — failed');
        }
      }
    } finally {
      turn.complete();
      if (identical(_groupUpdateSending[cid], turn.future)) {
        _groupUpdateSending.remove(cid);
      }
    }
    _log.info('Broadcast channel update for "${channel.name}" to ${legs.length} members');
    // §14.7 Type 22: the members above are other identities; this device's
    // own other devices learn the changed channel over the own line.
    _sendTwinChannelJoined(channel);
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
  Future<ChannelReportOutcome> reportChannel(String channelIdHex, int category, List<String> evidencePostIds, {String? description}) =>
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

  /// The bytes of a picture this device holds as base64 (group, channel);
  /// `null` when there is none or it does not decode.
  Uint8List? _pictureBytes(String? b64) {
    if (b64 == null || b64.isEmpty) return null;
    try {
      return base64Decode(b64);
    } on FormatException {
      return null;
    }
  }

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

    // PROFILE_UPDATE (picture + description) to all accepted contacts — now,
    // or once the hour of §15.8 has passed
    _broadcastProfileUpdate();
    _sendTwinProfileChanged({'profilePicture': base64Jpeg});

    onStateChanged?.call();
    _log.info('Profile picture ${base64Jpeg != null ? "set" : "removed"}, '
        'update to the contacts ${_profileUpdatePending ? "held back (§15.8)" : "sent"}');
    return true;
  }

  /// Enforcer for four names under which user content once lay in a file
  /// of the profile: whatever is found under them is REMOVED.
  ///
  /// S401 (02.10.2026): until then this run SEALED a plaintext file it
  /// found (`<name>.enc`). Nothing read the result — the wording of spoken
  /// messages is read from the store area `voice_transcriptions`, picture
  /// and self-description from the area `profile`, the interaction graph
  /// by nobody. A sealed copy of message content next to the store is the
  /// second storage v4_2 §21.4.2 rules out. Why removing loses nothing and
  /// why nothing is taken over stands in [PlaintextSweep].
  ///
  /// The run is cheap and may run at every start: if nothing lies there,
  /// it costs sixteen `existsSync`. It is deliberately NOT secured via a
  /// marker file — a marker would skip a run that could not delete last
  /// time, and the file would stay lying forever.
  void _sweepPlaintextUserContent() {
    for (final path in <String>[
      // The wording of spoken messages — message content.
      '$profileDir/voice_transcriptions.json',
      // The own profile picture and self-description. The paths stand
      // literally, because the getters with the file path have been
      // dropped (S366: both lie in the store, area `profile`).
      '$profileDir/profile_picture.b64',
      '$profileDir/profile_description.txt',
      // The interaction graph: for every node identifier ever seen,
      // counters and ban state — WITH WHOM and HOW OFTEN this device had to
      // do, readable without decrypting a single message. Its writer
      // (`peer_reputation.dart`) was deleted in S366; without this line a
      // file found under the name would lie open for good, because no
      // read ever comes past it.
      '$profileDir/reputation.json',
    ]) {
      PlaintextSweep.removeAllForms(path, log: _log);
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

    // PROFILE_UPDATE with description to all accepted contacts — now, or
    // once the hour of §15.8 has passed
    _broadcastProfileUpdate();
    _sendTwinProfileChanged({'profileDescription': _profileDescription});

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
  // default value applies (`MediaSettings()`, `LinkPreviewSettings()`),
  // and the user sets it again. With
  // `invites` it is different — there a latch stands
  // (`InviteStore.load`), because an empty book would assign the same
  // invitation key a second time.
  static const String _areaMediaSettings = 'media_settings';
  static const String _areaLinkPreviewSettings = 'link_preview_settings';

  /// The device-database row of the former multi-interface switch
  /// (`DeviceStore.areaSettings`); removed at start (S408 P22, §12.7).
  static const String kMultiInterfaceModeSettingKey = 'multi_interface_mode';

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

  // ── The former multi-interface switch (S408-LEBENSLAUF P22) ────────
  //
  // Here stood `multiInterfaceMode`/`setMultiInterfaceMode`: off / on / auto,
  // "send on all interfaces in parallel" (V3 §23.2). Since the CUT it was
  // stored in the device database and shown in the settings, and applied
  // NOWHERE (gap G-6: the mycelium wire holds one socket per family and knows
  // no such choice). v4_2 §12.7: "The network layer has exactly three
  // switches" — external records, router mapping, fewer empty cover
  // packets. A fourth that does nothing is removed, not built.

  /// Removes the row an earlier 4.2 version stored (an older 4.2 reading the
  /// device database again finds no row — its default).
  void _multiInterfaceRowDrop() {
    try {
      identity.deviceStoreOrNull
          ?.removeEntry(DeviceStore.areaSettings, kMultiInterfaceModeSettingKey);
    } catch (e) {
      _log.debug('Multi-interface row not removed: $e');
    }
  }

  // ── GUI device-wide choices (S407, §4.5.3) ─────────────────────────

  /// Read through from the device database: one value for every identity
  /// of the device.
  @override
  Map<String, dynamic> get guiDeviceSettings =>
      guiDeviceSettingsRead(identity.deviceStoreOrNull);

  @override
  Future<bool> setGuiDeviceSetting(String field, Object? value) async {
    try {
      final ok =
          guiDeviceSettingWrite(identity.deviceStoreForWrite(), field, value);
      if (ok) onStateChanged?.call();
      return ok;
    } catch (e) {
      _log.debug('Failed to save GUI device setting $field: $e');
      return false;
    }
  }

  // ── Master mute (§22.8, S407) ───────────────────────────────────────

  /// Read through from the device database, like [guiDeviceSettings]: one
  /// value for every identity of the device.
  @override
  bool get masterMute => masterMuteRead(identity.deviceStoreOrNull);

  @override
  Future<bool> setMasterMute(bool on) async {
    try {
      final ok = masterMuteWrite(identity.deviceStoreForWrite(), on);
      if (ok) onStateChanged?.call();
      return ok;
    } catch (e) {
      _log.debug('Failed to save master mute: $e');
      return false;
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
  /// Persists the new name to the list of identities via [IdentityManager] so it
  /// survives daemon restarts. Matches the Identity record by `profileDir`
  /// (stable, unique per identity). If no matching record is found, the
  /// in-memory + broadcast path still runs so that at least contacts learn
  /// the new name in the current session.
  @override
  void updateDisplayName(String newName) {
    _persistDisplayName(newName);
    displayName = newName;
    _broadcastProfileUpdate();
    _sendTwinProfileChanged({'displayName': newName});
    _publishIdentityRegistryIfPossible();
    onStateChanged?.call();
    _log.info('Display name updated to "$newName", update to the contacts '
        '${_profileUpdatePending ? "held back (§15.8)" : "sent"}');
  }

  /// Writes [newName] to this identity's record in the list of identities — for a
  /// name set here ([updateDisplayName]) and one set on another own device
  /// (Type 7 PROFILE_CHANGED, §14.7).
  void _persistDisplayName(String newName) {
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
  }

  /// §15.8 and the §15 table ("profile updates | max. 1 per hour"): the own
  /// profile goes to the contacts at most once per this span — "the
  /// recipients are what that limit protects".
  static const Duration kProfileUpdateInterval = Duration(hours: 1);

  static const String _profileKeySent = 'sent';

  /// When the last profile update went to the contacts; `null` before the
  /// first one.
  DateTime? _profileUpdateSentAt;

  /// A change made within [kProfileUpdateInterval] of the last update still
  /// has to go out.
  bool _profileUpdatePending = false;

  /// The one-shot wait for a pending update. Without a pending update no
  /// timer exists (§5.4).
  Timer? _profileUpdateTimer;

  /// §15.3 "A face-to-face invitation lives 60 s": the one local clock until
  /// the next shown, unredeemed face-to-face invitation is due. Without one
  /// running no timer exists (`cleona_service_mycelium.dart`
  /// `_faceToFaceArm`).
  Timer? _faceToFaceClock;

  /// The clock of the limit; a probe may replace it.
  @visibleForTesting
  DateTime Function() profileUpdateClockForTesting = DateTime.now;

  /// Whether [kProfileUpdateInterval] has not yet passed since the last
  /// update. A clock that was set back does not hold an update back.
  bool get _profileUpdateTooEarly {
    final last = _profileUpdateSentAt;
    if (last == null) return false;
    final elapsed = profileUpdateClockForTesting().difference(last);
    return !elapsed.isNegative && elapsed < kProfileUpdateInterval;
  }

  /// A change of name, picture or description is to reach the contacts
  /// (§15.8) — at most once per [kProfileUpdateInterval]. A change within
  /// the span is not refused and not lost: the profile as it stands when
  /// the span has passed goes out then, as ONE update
  /// ([_profileUpdateDue]).
  void _broadcastProfileUpdate() {
    if (_profileUpdateTooEarly) {
      _profileUpdatePending = true;
      _saveProfileUpdateState();
      _profileUpdateArm();
      return;
    }
    _profileUpdateSend();
  }

  /// Arms the one-shot wait until the span has passed.
  void _profileUpdateArm() {
    if (_profileUpdateTimer != null || _disposed) return;
    final last = _profileUpdateSentAt;
    if (last == null) return;
    final wait = last
        .add(kProfileUpdateInterval)
        .difference(profileUpdateClockForTesting());
    _profileUpdateTimer = Timer(wait.isNegative ? Duration.zero : wait, () {
      _profileUpdateTimer = null;
      _profileUpdateDue();
    });
  }

  /// Sends a pending update once the span has passed; before that it only
  /// keeps the wait armed. Called by the wait and when the mailbox is
  /// attached (a pending update of the last run).
  void _profileUpdateDue() {
    if (!_profileUpdatePending || _disposed) return;
    if (_profileUpdateTooEarly) {
      _profileUpdateArm();
      return;
    }
    _profileUpdateSend();
  }

  /// [_profileUpdateDue] for probes, which cannot wait an hour.
  @visibleForTesting
  void profileUpdateDueForTesting() => _profileUpdateDue();

  /// [_loadProfileUpdateState] for probes that stage a restart without the
  /// whole start sequence.
  @visibleForTesting
  void profileUpdateStateLoadForTesting() => _loadProfileUpdateState();

  void _loadProfileUpdateState() {
    try {
      final json = store.loadArea(_areaProfile)[_profileKeySent];
      final at = json?['at'] as int?;
      _profileUpdateSentAt =
          at == null ? null : DateTime.fromMillisecondsSinceEpoch(at);
      _profileUpdatePending = json?['pending'] == true;
    } catch (e) {
      _log.debug('Failed to load profile update state: $e');
    }
  }

  void _saveProfileUpdateState() {
    try {
      final at = _profileUpdateSentAt;
      if (at == null && !_profileUpdatePending) {
        store.removeEntry(_areaProfile, _profileKeySent);
      } else {
        store.putEntry(_areaProfile, _profileKeySent, {
          if (at != null) 'at': at.millisecondsSinceEpoch,
          'pending': _profileUpdatePending,
        });
      }
    } catch (e) {
      _log.debug('Failed to save profile update state: $e');
    }
  }

  /// The profile as it stands (picture + description + name) to every
  /// accepted contact, one message each. Only [_broadcastProfileUpdate] and
  /// [_profileUpdateDue] call this — they hold the limit of §15.8.
  void _profileUpdateSend() {
    _profileUpdateTimer?.cancel();
    _profileUpdateTimer = null;
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

    var recipients = 0;
    for (final contact in _contacts.values) {
      if (contact.status != 'accepted') continue;
      if (contact.x25519Pk == null || contact.mlKemPk == null) continue;
      recipients++;
      _detachedSend('MT_PROFILE_UPDATE', sendToUser(
        recipientUserId: contact.nodeId,
        messageType: proto.MessageType.MT_PROFILE_UPDATE,
        payload: payload,
      ));
    }
    _profileUpdatePending = false;
    // An update nobody received used up nothing: the limit protects
    // recipients.
    if (recipients > 0) _profileUpdateSentAt = profileUpdateClockForTesting();
    _saveProfileUpdateState();
  }

  // ── Guardian recovery: REMOVED (S398 P1, D-17) ────────────────
  //
  // The four refusal stubs of the fallen `GuardianService` (setup,
  // trigger, confirm, `isGuardianSetUp`) and their IPC commands are gone:
  // D-17 "No social recovery: no guardians, no split secret" (§13.8). What
  // remains is the settings tile's honest display of an old deposit, which
  // measures directly with `LegacyGuardianDeposit.probe`
  // (`lib/core/recovery/legacy_guardian_state.dart`, owner question U-6).

  // ── Calls (delegated to CallService) ──────────────────────────────

  /// Hangs the host's Plane D onto the call transport of this identity
  /// (§17.4).
  ///
  /// NO `@override` and not in `ICleonaService`: this is not an
  /// application operation, but a seam of the setup. Since S398-W2 it is
  /// called from `plane_d_host.dart` (`planeDAttach`/`planeDRegister`) at
  /// the host start and when an identity joins a running host; until then
  /// its only caller was `attachV41`, which nothing calls any more. The UI
  /// and the IPC do not see it.
  ///
  /// `null` deregisters it; that is the path when shutting down the node.
  void attachCallPlaneD(CallPlaneD? planeD) {
    if (_callsReady) {
      _calls.attachPlaneD(planeD);
    } else {
      // Before `startService` there is no call service yet; the start paths
      // attach after it, but an order that is not enforced is a
      // `LateInitializationError` waiting for its first caller.
      _planeDBeforeStart = planeD;
    }
  }

  CallPlaneD? _planeDBeforeStart;

  @override
  CallInfo? get currentCall => _calls.currentCall;
  @override
  Future<CallInfo?> startCall(String peerNodeIdHex, {bool video = false}) =>
      _calls.startCall(peerNodeIdHex, video: video);
  @override
  Future<void> acceptCall() => _calls.acceptCall();
  @override
  Future<void> rejectCall({String reason = 'declined'}) =>
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
  Future<GroupCallInfo?> startGroupCall(String groupIdHex,
          {Set<String>? invitees}) =>
      _calls.startGroupCall(groupIdHex, invitees: invitees);
  @override
  Future<void> acceptGroupCall() => _calls.acceptGroupCall();
  @override
  Future<void> rejectGroupCall({String reason = 'declined'}) =>
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

  /// The user's "reconnect" (v4_2 §25.7) — in process the connection sheet,
  /// in the daemon the IPC command `manual_reconnect`. It is the edge
  /// "network change" of §11.8.2 and goes through its ONE entry
  /// ([networkChangeEdge]) on the host this identity's mailbox hangs on: the
  /// host part once, every identity on the host as subscriber, the router
  /// mapping (§7.3) and the update moment — not only this one service
  /// (S407-LB-P12, finding A-3). Not awaited, as before: the edge runs behind
  /// the answer, which therefore claims no result. The operator lock
  /// against repeated presses stays where it was (`ipc_server.dart`).
  @override
  Future<Map<String, dynamic>> reconnect() async {
    final host = myceliumMailbox?.host;
    if (host == null) {
      _log.info('Reconnect: no host started — nothing to reconnect');
    } else {
      unawaited(networkChangeEdge(host, reason: 'reconnect', report: _log.info));
    }
    return {'debounced': false};
  }

  /// SUBSCRIBER of the edge "network change" (v4_2 §11.8.2) — the
  /// application consequences of this identity, and only those: the running
  /// calls (§17.4), the first-contact
  /// backoff, the resends of §5.8 and §16.2.5.
  ///
  /// Called by the ONE entry `networkChangeEdge` (`mycelium_seam.dart`) for
  /// every identity on the host, once per edge. It runs NO part of the
  /// network layer (the host part, the router mapping) and never starts the
  /// edge itself: a caller that wants the edge calls the entry, or
  /// [reconnect]. Until S407-LB-P12 this method also ran the host part
  /// behind a switch `triggerNodeReset` (on by default), which the
  /// detection paths turned off and "reconnect" left on — so "reconnect"
  /// reached the host through ONE identity, without the router mapping.
  Future<void> onNetworkChanged() async {
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
    // §26.6.2 package C: the edge reads what the delivery layer closed of
    // the rotation broadcasts (S408-LEBENSLAUF P20; no clock of its own).
    _keyRotationFromDelivery();
    // §16.2.5: a network change is an edge — what is not placed goes out
    // again, and every group or channel on the shared key is collected.
    unawaited(_skEdge(reason: 'network change'));
    // The §5.8 outbox drain likewise stood here. It fell with the
    // V3 cascade (gap G-4, see `cleona_service_pure.dart`).
  }

  // ── Persistence ────────────────────────────────────────────────────

  // Cached FileEncryption instance — uses seed-derived key per §3.7 step 5.
  FileEncryption? _fileEncCached;
  FileEncryption get _fileEnc {
    if (_fileEncCached != null) return _fileEncCached!;
    final baseDir = AppPaths.dataDir;
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

  /// The expiry sweep of §21.5.3 at a moment the guard chooses
  /// (`test/smoke/smoke_delete_expiry.dart`). In operation the 30 s timer
  /// of `startService` runs it.
  @visibleForTesting
  void debugCheckMessageExpiry({required DateTime now}) =>
      _checkMessageExpiry(at: now);

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
        if (conv.parkedConfigAcceptance != null)
          'parkedConfigAcceptance': conv.parkedConfigAcceptance!.toJson(),
        if (conv.expiryPending) 'expiryPending': true,
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
      final rows = store
          .messagesOf(hexToBytes(conversationId))
          .map(messageFromStoreRow)
          .toList();
      final flagged = rows.where((m) => m.isDeleted).toList();
      conv.messages
        ..clear()
        ..addAll(rows.where((m) => !m.isDeleted));
      conv.messagesLoaded = true;
      conv.totalMessages = conv.messages.length;
      // After `messagesLoaded`: the attachment check loads every history.
      if (flagged.isNotEmpty) _sweepFlaggedRows(flagged);
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

  /// §14.4: the verification level a contact held before its keys were
  /// adopted by a rotation chain (`_adoptChainedKeys` lowers it
  /// provisionally); the announcement with the device quorum brings it back
  /// (`_handleEmergencyKeyRotation`). In memory only.
  final Map<String, String> _levelBeforeRotation = {};

  void _saveContacts() {
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
        if (extra['parkedConfigAcceptance'] != null) {
          conv.parkedConfigAcceptance = ChatConfig.fromJson(
              extra['parkedConfigAcceptance'] as Map<String, dynamic>);
        }
        conv.expiryPending = extra['expiryPending'] as bool? ?? false;
      }
      // A conversation whose youngest row is one an earlier build left
      // flagged as deleted: loading its history turns the row into a mark.
      // After the loop — the attachment check needs every conversation.
      for (final conv in conversations.values.toList()) {
        if (conv.messages.any((m) => m.isDeleted)) ensureLoaded(conv.id);
      }
      _conversationsLoaded = true;
      _log.info('Loaded ${conversations.length} conversations from the store');
      return;
    } catch (e) {
      _log.warn('Failed to load conversations from the store: $e');
      return;
    }
  }

  /// Post a system notification for an incoming message: on Android through
  /// [onPostNotificationAndroid], on the desktop through
  /// [onPostDesktopNotification] (whichever the platform has set).
  /// L5 gate: suppressed when the user interface is in the foreground.
  void _postAndroidNotification(String senderName, String text, String conversationId) {
    if (_isAppResumed) return;
    _postSystemNotification(senderName, text, conversationId);
  }

  /// The one place that hands a notification to the platform — and the one
  /// source of what it shows: every platform gets the same [title] and
  /// [body] (§22.8). Never throws, and logs neither of the two.
  void _postSystemNotification(
      String title, String body, String notificationId) {
    try {
      final android = onPostNotificationAndroid;
      if (android != null) {
        unawaited(android(title, body, notificationId).catchError((Object e) {
          _log.warn('postAndroidNotification failed: $e');
        }));
        return;
      }
      onPostDesktopNotification?.call(title, body, notificationId);
    } catch (e) {
      // The type only: the text of an error from the platform side may
      // quote what it was handed.
      _log.warn('postSystemNotification failed: ${e.runtimeType}');
    }
  }

  /// A calendar reminder is due (§18.1.6): system notification, sound and
  /// vibration. Called by whoever runs the `ReminderService`. Not a message:
  /// the layers L1–L5 of §22.8 do not apply to it. [title] is the event's
  /// title, [body] how long until it starts (§22.8 "A reminder shows the
  /// event's title and how long until it starts").
  void notifyReminderDue(String title, String body, String notificationId) {
    _postSystemNotification(title, body, notificationId);
    unawaited(notificationSound.playMessageSound());
    unawaited(notificationSound.vibrate(VibrationType.message));
  }

  /// §16.2.2 "Joining is an explicit act of the invitee" — which needs the
  /// invitee to learn of the invitation (S407 G-2: `onGroupInviteReceived`
  /// had no listener, an invitation stood silently in the list). A new
  /// invitation into a group or channel counts as one unread item until the
  /// conversation is opened, and it rings like a message: quiet hours and
  /// master mute (§22.8), a notification switched off for this conversation,
  /// and the foreground gate L5 apply. The age rule L3 and the type default
  /// of L2 ("channels: off") do not: an invitation is no post of the
  /// conversation, and it arrives as late as a post box holds it — exactly
  /// when it is needed.
  void _announceInvitation(String id, String name, String inviterHex,
      {required bool channel}) {
    final conv = conversations[id];
    if (conv != null &&
        !(_isAppResumed && _activeConversationId == id) &&
        !SystemChannels.isSystemChannel(id)) {
      conv.unreadCount++;
      _updateBadgeCount();
      _saveConversations();
    }
    if (notificationSilenced(
        masterMute: masterMute,
        settings: notificationSound.settings,
        now: DateTime.now())) {
      return;
    }
    if (conv?.notificationsEnabled == false) return;
    final words = notificationWords ??
        (String key) => trayTranslate(key, trayLocaleCode());
    final inviter = _contacts[inviterHex]?.displayName ??
        (inviterHex.length > 8 ? inviterHex.substring(0, 8) : inviterHex);
    final body = words(channel
            ? 'notification_channel_invite_body'
            : 'notification_group_invite_body')
        .replaceAll('{name}', inviter)
        .replaceAll(channel ? '{channel}' : '{group}', name);
    unawaited(notificationSound.playMessageSound(
        soundName: conv?.notificationSoundName));
    unawaited(notificationSound.vibrate(VibrationType.message));
    _postAndroidNotification(words('invitation_label'), body, id);
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

  /// §17 principle, RL-7, D-69: "allow calls = disclose IP" for one contact.
  /// Stored on the contact record; the call paths read it at the moment they
  /// would disclose an address (`call_consent.dart`). Revoking does not take
  /// back an address the contact has already seen (§23.6) and does not end a
  /// call that is already running. Held on every own device (§14.7 Type 8,
  /// D-71): a change goes to the other own devices with its time.
  @override
  bool setContactCallsAllowed(String nodeIdHex, bool allowed) {
    final contact = _contacts[nodeIdHex];
    if (contact == null) return false;
    if (contact.callsAllowed != allowed) {
      contact.callsAllowed = allowed;
      _saveContacts();
      _sharedCallsAllowedSend(nodeIdHex, allowed);
    }
    onStateChanged?.call();
    return true;
  }

  @override
  bool contactCallsAllowed(String nodeIdHex) =>
      callsAllowedWith(_contacts, nodeIdHex);

  /// §15.10, §14.7 Type 8 (D-72): the self-declaration `isAdult` of this
  /// identity, held on every own device
  /// (`cleona_service_shared_settings.dart`).
  @override
  bool setIsAdult(bool adult) => _sharedIsAdultSet(adult);

  /// §15.10, §16.5, §14.7 Type 8 (D-72): the opt-in "evaluate channel
  /// reports" of this identity, held on every own device.
  @override
  bool setReviewEnabled(bool enabled) => _sharedReviewSet(enabled);

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

  /// Finding 1 (§8.1): the suppression set rides in the area
  /// `processed_msg_ids`, which until S403 also carried the receive-side
  /// dedup set. The dedup itself lives in the identity's store since S403
  /// (`received_ids`, §20.2) and needs no carrier here; its row of the
  /// earlier builds is taken out of the area at the load below. What
  /// stays is the set of receipt-suppressed message ids — it must survive
  /// a receiver restart: a lost suppression entry re-acks the next L1
  /// retry of a deliberately dropped CONTACT_REQUEST, sets the sender's
  /// `lastAckedAt`, and parks its CR retry for 24h: exactly the deadlock
  /// the drop prevents. No extra write frequency (working rule #5
  /// applies to disk I/O too).
  /// The area in the table `state` (S366).
  static const String areaProcessedIds = 'processed_msg_ids';

  /// The row of the earlier builds' dedup set — no reader any more. It is
  /// removed at the load; the name stays so that the removal is not a
  /// typed-in string.
  static const String _keyDedupLegacy = 'dedup';
  static const String _keySuppressed = 'suppressed';

  /// S366: snapshot into the storage instead of rewriting a file.
  ///
  /// DELIBERATELY `putEntry` AND NOT `replaceArea`: the row is capped
  /// (1024), so NOT growing — but `replaceArea` would first delete the
  /// area entirely. `putEntry` overwrites in place; the area is never
  /// empty in between.
  ///
  /// THE ROW IS ALWAYS WRITTEN, including the empty one. Thus the area
  /// holds exactly 0 or 1 row after every write, and `countArea` is a
  /// reliable statement about completeness — on which the latch below
  /// relies. (A legacy `dedup` row may still be lying there; the load
  /// removes it.)
  void _saveSuppressedReceiptIds() {
    if (_suppressedReceiptMsgIds.isEmpty) return;
    try {
      store.putEntry(areaProcessedIds, _keySuppressed,
          {'ids': _suppressedReceiptMsgIds.toList()});
    } catch (e) {
      _log.warn('Failed to save receipt-suppressed message IDs: $e');
    }
  }

  /// Loads the suppression set (§8.1 finding 1) and takes the legacy
  /// `dedup` row of the builds before S403 out of the area — its reader
  /// is gone: the receive-side dedup lives in the identity's store since
  /// S403 (`received_ids`, §20.2; this class holds none of it any more).
  ///
  /// ── THE DATA-LOSS LATCH, AND WHY IT DOES NOT THROW HERE ────
  ///
  /// There was none here — a read error fell silently to "empty". An
  /// empty suppression set is also defensible: the suppression starts
  /// over, in the worst case one replay is acknowledged once more.
  ///
  /// A HALF one is not. The latch measures, at the carrier, the
  /// statement "the area is COMPLETELY readable": if `countArea` holds
  /// more rows than `loadArea` could unpack, it falls back to the
  /// DOCUMENTED SAFE state — the set empty — instead of to the part
  /// that happens to be readable. It deliberately does not throw: an
  /// unreadable repeat lock must not prevent a start, and the empty
  /// state is the same as at the very first start. (Until S403 the
  /// dangerous half was the opposite one: a surviving dedup set next to
  /// a lost suppression set acknowledged the next repetition of a
  /// deliberately discarded CONTACT_REQUEST and parked its repetition
  /// for 24 h.)
  void _loadSuppressedReceiptIds() {
    try {
      // The legacy row goes BEFORE the latch and by its KEY, not by its
      // content — an unreadable one must not trip the latch for ever. A
      // DELETE on a key that is not there is a no-op, so this needs no
      // marker and is idempotent by itself.
      store.removeEntry(areaProcessedIds, _keyDedupLegacy);
      final lines = store.loadArea(areaProcessedIds);
      final present = store.countArea(areaProcessedIds);
      if (present == 0) return;

      if (lines.length < present) {
        _log.error(
            'Replay lock: the area `$areaProcessedIds` holds '
            '$present row(s), of which only ${lines.length} '
            'can be unpacked — the suppressed set stays empty. A half '
            'restore could acknowledge the next repetition of a '
            'discarded CONTACT_REQUEST and park its repetition for '
            '24 h (§8.1 finding 1).');
        _suppressedReceiptMsgIds.clear();
        return;
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
      _log.info('Loaded ${_suppressedReceiptMsgIds.length} '
          'receipt-suppressed message IDs (§8.1 finding 1)');
    } catch (e) {
      _log.warn('Failed to load receipt-suppressed message IDs: $e');
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

  void _loadGroups() {
    _loadEncMap<GroupInfo>('groups', _groups, GroupInfo.fromJson,
        setLoaded: (v) => _groupsLoaded = v, label: 'groups');
    // §16.2.2: a group this identity was already alone in before the
    // question existed (a 4.2.3 profile) is asked about too.
    var due = false;
    for (final g in _groups.values) {
      final before = g.aloneQuestion;
      _groupAloneCheck(g);
      due |= g.aloneQuestion != before;
    }
    if (due) _saveGroups();
  }

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
    // S398, B-3: never `Platform.localHostname` alone — on Android that is
    // "localhost" (device_name.dart).
    final name = localDeviceName(_detectPlatform());
    _devices[_localDeviceId] = DeviceRecord(
      deviceId: _localDeviceId,
      deviceName: name,
      platform: _detectPlatform(),
      firstSeen: now,
      lastSeen: now,
      isThisDevice: true,
      deviceNodeIdHex: bytesToHex(identity.deviceNodeId),
    );
    _saveDevices();
    _log.info('Local device registered: $_localDeviceId ($name)');
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
    // The own-device line follows the device set (§14.7, D-37).
    _myceliumOwnLineSync();
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
  /// immediately; contacts additionally receive `MT_DEVICE_REVOCATION`
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
    if (_devices.length > 1) {
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
    // finds it again (`_handleDeliveryReceipt`). Without its own
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
              messageType: proto.MessageType.MT_DEVICE_REVOCATION,
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
    _saveDevices();
    // §14.5 path 2: the shrunken device set goes pairwise to the
    // contacts. AFTER `_devices.remove`, so that the announcement carries
    // the state AFTER the change — §14.8 counts the quorum over the
    // REMAINING devices ("On a device-set change, the quorum counts the
    // *remaining* devices `M`, not the state before it").
    _announceDeviceSetToContacts(occasion: 'device revocation');
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
    // told via MT_DEVICE_REVOCATION before this point.
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
    // proceeds anyway — see `rotateIdentityKeys()`. A revocation initiated
    // on another device arrives via the mirrored call in
    // `_handleTwinDeviceRevoked`.
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

  /// Test-only (E2E gui-52): read the delivery state of the rotation
  /// broadcasts now instead of at the next edge — the production path
  /// (`_keyRotationFromDelivery`) unchanged. Since S408-LEBENSLAUF P20 there
  /// is no retry of the app to force: the delivery layer sends again.
  @override
  void testForceKeyRotationRetry() => _keyRotationFromDelivery();

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
  int get _sessionPartnerCount =>
      (syncPartnersOutbound ?? 0) + (syncPartnersInbound ?? 0);

  @override
  int get peerCount => _sessionPartnerCount;
  @override
  int get confirmedPeerCount => _sessionPartnerCount;
  @override
  int get reachablePeerCount => _sessionPartnerCount;

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
  /// `crash_reporter.dart:104`, `contact_issue_reporter.dart:74`. Every
  /// error report from the field thus carried the same useless line.
  ///
  /// Since S408-LEBENSLAUF P16 (finding A-5) read from the HOST's router
  /// mapping (`host.network.router`, `mycelium/lib/host_router.dart`): a
  /// mapping or pinhole the router granted and that has not expired. The
  /// field [v41PortMapper] was set only by the superseded layer's attach
  /// and stood at `null` in every 4.2 process.
  @override
  bool get hasPortMapping =>
      myceliumMailbox?.host.network.router.proven ?? false;

  @override
  bool get hasSessionConfirmedPeers => _sessionPartnerCount > 0;

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

  /// The own dialable addresses — from the interfaces the delivery layer
  /// read at its edges start and network change (`interfaces`,
  /// `mycelium/lib/node_helpers.dart`), filtered as the NAT assistant needs
  /// them ([dialableFrom]: private IPv4 first). One source: until S408 the
  /// service enumerated the interfaces itself, beside the host, and cached
  /// them (S408-LEBENSLAUF P16, finding A-5).
  @override
  List<String> get localIps {
    final own = dialableFrom(mycelium.interfaces);
    return own.isNotEmpty ? own : const ['127.0.0.1'];
  }

  /// The own public address and port (§7.3) — the host's: the address a
  /// neighbour saw (the mirror, `node_outside.dart`) or the outer address
  /// of a granted IPv4 mapping (`host_network.dart`). `null` means
  /// "unknown", not "none" — the UI shows an empty state for it. Until S408
  /// both stood at a fixed `null`, and with them the invitation link of
  /// §26.6.3 ([generateInviteLinkUrl]) never came about (S408-LEBENSLAUF
  /// P16, finding A-5).
  @override
  String? get publicIp {
    final p = myceliumMailbox?.host.node.publicAddress;
    return p == null
        ? null
        : InternetAddress.fromRawAddress(Uint8List.fromList(p.address)).address;
  }

  @override
  int? get publicPort => myceliumMailbox?.host.node.publicAddress?.port;

  /// "Running" means: the mycelium mailbox is attached to the service.
  /// Without it no message goes out, regardless of what else lives.
  @override
  bool get isRunning =>
      myceliumMailbox != null;

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

  /// The user's verification decision for a contact (v4_2 "Contact
  /// verification and key-change detection"; §15.10 scan / NFC touch;
  /// `set_verification_level`). Reaching `verified`/`trusted` IS the active
  /// re-verification and lifts the re-verify lock
  /// ([ContactInfo.reverifyRequired]). Persisted and announced. Returns
  /// false for an unknown contact or level.
  bool setContactVerificationLevel(String nodeIdHex, String level) {
    const levels = ['unverified', 'seen', 'verified', 'trusted'];
    final contact = _contacts[nodeIdHex];
    if (contact == null || !levels.contains(level)) return false;
    contact.verificationLevel = level;
    if (kVerifiedLevels.contains(level)) contact.reverifyRequired = false;
    _saveContacts();
    onStateChanged?.call();
    return true;
  }

  /// `seen` = "key material used successfully at least once" (v4_2
  /// "Contact verification and key-change detection"; S405 finding A-4):
  /// called for a frame of [contact] this device opened with the contact's
  /// keys. Lifts `unverified` to `seen` — never lowers, and never while the
  /// re-verify lock holds (a fallen-back verified contact waits for the
  /// active re-verification).
  void _markKeyMaterialUsed(ContactInfo contact) {
    if (contact.status != 'accepted' ||
        contact.verificationLevel != 'unverified' ||
        contact.reverifyRequired) {
      return;
    }
    contact.verificationLevel = 'seen';
    _saveContacts();
    onStateChanged?.call();
  }

  /// Start-peer candidates for the ContactSeed (§11) — the sending side of
  /// the entry bridge, gap G-11.
  ///
  /// The SELECTION (cap, freshness, family diversity) is made by the
  /// builder, not this service: it depends on the format of the code, and
  /// the format is known to `contact_seed.dart`. The only source was the
  /// V4.1 entry store (`v41EntrySeedCandidates`, set by `attachV41`, fallen
  /// with `lib/core/tagline/`, S408-P23); in 4.2 the invitation card carries
  /// the addresses (§15.2, D-25), so the list is empty — as it already was
  /// in operation.
  @override
  List<EntrySeedCandidate> get entrySeedCandidates =>
      const <EntrySeedCandidate>[];

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
    if (myceliumMailbox?.host.node.wireCounters case final w?) {
      // S405 A-2: under mycelium the wire counts itself
      // (`mycelium/lib/wire_counters.dart`). The relay figures are left
      // out, not set to 0: the forwarder counts handed-on `0x20` packets
      // (`Forwarder.passed`) but no bytes, and its `detours` counts
      // accepted detours, not packets handed on — neither is "relayed for
      // others" as §25.6 means it.
      statsCollector.noteNodeCounters(
        wireSent: w.bytesSent,
        wireReceived: w.bytesReceived,
      );
    }
    // AND THE SNAPSHOTS (§25.4). Twenty tiles which until 01.09.2026
    // either did not exist at all or sat on a V3 source that has been
    // deleted. They are REMEMBERED and not booked —
    // justification at `NetworkStatsCollector.noteNodeGauges`.
    if (myceliumMailbox?.host.node case final node?) {
      // S407-N2: the V4.1 gauges (`v41NodeGauges`, set only by `attachV41`)
      // fell with `lib/core/tagline/` (S408-P23). The three tiles with
      // an exact counterpart in the 4.2 layer read it here (§25.5 cover,
      // §25.6 post box packets held); the rest is hidden in the view.
      statsCollector.noteDeliveryCounters(
        coverSent: node.coverStream.sent,
        coverSkipped: node.coverStream.skipped,
        postBoxHeld: node.postBoxDeposit.held,
      );
    }
    // §25.7: the answering neighbours as rows, read from the same readiness
    // that yields the count (§22.7.1) — read only, no packet (§25.10).
    final statsHost = myceliumMailbox?.host;
    final hostNode = statsHost?.node;
    statsCollector.noteNeighbours(hostNode == null
        ? const []
        : [
            for (final n in hostNode.neighbourhood.all)
              if (hostNode.readiness.answeringAddress(n) != null)
                () {
                  final answered = [
                    for (final a in n.addresses)
                      if (hostNode.readiness.responding.contains(a.key)) a
                  ];
                  return NeighbourRow(
                    families: {
                      for (final a in answered)
                        a.address.type == InternetAddressType.IPv6
                            ? 'IPv6'
                            : 'IPv4'
                    }.toList(),
                    fixed: n.seated,
                    lastConfirmed: answered
                        .map((a) => a.last)
                        .reduce((x, y) => x.isAfter(y) ? x : y),
                    foundBy: hostNode.neighbourhood.foundBy(n)?.name,
                  );
                }(),
          ],
        statsHost == null
            ? null
            : NeighbourAggregates(
                fixed: hostNode!.neighbourhood.fixedNeighbours.length,
                openSet: hostNode.neighbourhood.openSet().length,
                keepsBoard: hostNode.board?.reachableProven ?? false,
                externalRecordsOn: statsHost.outsideSourceOn,
                ownRecordPublished: statsHost.network.ownRecordPublished,
              ));
    // S398-W4 (§21.3.3 item 4): the evictions of the 4.2 layer. The post
    // box holder sits behind the node's deposit without an outside reader,
    // hence its process total (one host per device); the bulk holder is
    // the host's.
    statsCollector.noteEvictions(
      postBox: PostBoxHolder.evictedInProcess,
      bulk: myceliumMailbox?.host.bulk.holder.evicted ?? 0,
    );
    // D-40: cells parked for another own device's KEM generation and lost
    // unopened — this identity's, persisted by the delivery layer.
    final parked = myceliumMailbox;
    statsCollector.noteParkedLost(
        parked == null ? 0 : mycelium.MailboxParked(parked).parkedLost);
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
  Future<LogReport> buildLogReport() async => crashReporter.buildLogReport();

  /// §16.7 (S407 SK-4): this identity's view of the system channels —
  /// signed by its report pseudonym, over the device-wide hub (store, own
  /// deposits, transport; `system_channel_seam.dart`).
  @override
  SystemChannelApi get systemChannelApi =>
      _systemChannels ??= _systemChannelsBuild();
  SystemChannelService? _systemChannels;

  /// The hub of this device — the same object for every identity on it.
  SystemChannelHub get systemChannelHub => SystemChannelHub.forDevice(
      identity.deviceStoreForWrite(),
      holds: !(Platform.isAndroid || Platform.isIOS),
      profileDir: profileDir);

  SystemChannelService _systemChannelsBuild() {
    final seed = identity.masterSeed;
    final index = identity.hdIndex;
    if (seed == null || index == null) {
      // An identity created without the HD derivation has no report
      // pseudonym of its own; a fresh one per run is what §16.8 declares
      // anyway ("pseudonyms are free") — its reports cannot be retracted
      // after a restart.
      _log.warn('syschan: no master seed/HD index — a fresh report '
          'pseudonym for this run');
    }
    final pseudonym = seed != null && index != null
        ? ReportPseudonym.derive(seed, index)
        : ReportPseudonym.random();
    return SystemChannelService(systemChannelHub,
        SystemObjectAuthor(pseudonym, userId: identity.userId),
        profileDir: profileDir);
  }

  /// The own 4.2.3 records of this identity (they never left the device)
  /// re-signed under the report pseudonym and deposited — once; the old
  /// rows go (SK-2 `system_object_legacy.dart`).
  void _systemChannelsResignLegacy() {
    try {
      final api = systemChannelApi as SystemChannelService;
      systemChannelHub.resignLegacy(store,
          ownUserId: identity.userId, author: api.author);
    } catch (e) {
      _log.warn('syschan: re-signing the 4.2.3 records failed: $e');
    }
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
    // The NAT assistant's "check now": the user pressed it AFTER changing
    // something at their router, so a new discovery is the question.
    // ── S408-LEBENSLAUF P16 (finding A-5): THE HOST'S ROUTER ─────────
    //
    // Until S408 this read `v41PortMapper`, which only the superseded
    // layer's attach set: in every 4.2 process the search never ran, and
    // a one-second loop watched a counter for 30 s. Now the host's router
    // mapping is asked again (§7.3 — the user changed something at the
    // router, the previous answer is from before), and the answer is what
    // the delivery layer holds as evidence: a granted mapping or pinhole,
    // the open check of §8.1 (a neighbour reached this node unasked), or a
    // passive proof (§11.8a). No loop: the method waits for the router's
    // answer, bounded for the button by 30 s (an RFC 6886 backoff takes
    // minutes; its late answer still reaches the evidence).
    final host = myceliumMailbox?.host;
    if (host == null) {
      _log.info('NAT wizard recheck: no host started — nothing to check');
      return false;
    }
    _log.info('NAT wizard recheck: the router is asked again '
        '(UPnP/IGD + NAT-PMP/PCP, §7.3)');
    try {
      await host.network.router.edge().timeout(const Duration(seconds: 30));
    } on TimeoutException {
      _log.info('NAT wizard recheck: the router has not answered within 30 s');
    }
    final open = host.network.router.proven ||
        host.network.openCheck.isOpen(InternetAddressType.IPv4) ||
        host.network.openCheck.isOpen(InternetAddressType.IPv6) ||
        (syncPartnersInbound ?? 0) > 0;
    _log.info('NAT wizard recheck: reachable from outside = $open');
    return open;
  }

  // ── Key Rotation ──────────────────────────────────────────────────

  /// Test access to EXACTLY the production path of the routine rotation
  /// (§4.5.4) — the one the 6-h tick and the cold-start gate call. No
  /// second mechanism: `smoke_kem_rotation_mailbox` measures what this
  /// method does, not a copy of it.
  @visibleForTesting
  Future<void> performKeyRotationForTest() => _performKeyRotation();

  /// Rotate KEM keys and broadcast to all contacts.
  /// Async: ML-KEM keygen runs in background isolate (ANR fix).
  Future<void> _performKeyRotation() async {
    // D-40 (E7 = b1): with more than one device only ONE device rotates —
    // `cleona_service_kem_line.dart`. With one device this is always `true`.
    if (!_kemRotationIsMine()) return;
    await identity.rotateKemKeys();
    // Type 19 to the other own devices BEFORE the mailbox takes the new
    // keys (sealed under the generation they hold) and BEFORE the
    // announcement below. Sends nothing with one device.
    await _kemRotatedToOwnDevices();
    // §4.5.4 — THE RUNNING MAILBOX GETS THE NEW GENERATION (S398).
    //
    // mycelium receives this identity's keys from the app only when the
    // mailbox is registered (`postBoxFrom`, `mycelium_seam.dart`). Until
    // S398 nothing handed a rotation over at runtime: the running post
    // box kept the old keys, every envelope carried the old address, and
    // the contacts' mailboxes never learned the new one — after a second
    // rotation and a restart they sealed against a generation this node
    // no longer holds (measured: `smoke_kem_rotation_mailbox`, 2d/2e RED
    // at `88fbf2b2`). `keyChange` swaps the keys in the post box of THIS
    // identity's mailbox (the previous generation stays as the one
    // previous) — one service, one identity, one mailbox (§4.5.1), so a
    // rotation never touches another identity of the same host.
    //
    // BEFORE the broadcast below, and that order is the point: the
    // broadcast is the ONE announcement (the mailbox sends none of its
    // own). Sealed after `keyChange`, its envelope carries the new
    // address, so ONE packet updates both copies at the contact — the
    // mailbox by the adoption rule, the app contact record from the
    // signed body. `now:` is the app's rotation time, so the state the
    // contacts adopt now is the state `postBoxFrom` rebuilds after a
    // restart.
    //
    // Without a mailbox (rotation before the host is up) there is nothing
    // to swap: the registration takes the keys from the identity.
    myceliumMailbox?.keyChange((
      x25519Pk: identity.x25519PublicKey,
      x25519Sk: identity.x25519SecretKey,
      mlKemPk: identity.mlKemPublicKey,
      mlKemSk: identity.mlKemSecretKey,
    ), now: identity.keyRotatedAt);
    // `node.broadcastAddressUpdate()` stood here (§5.11: the fresh
    // `PeerInfo` with the new KEM key once to all known peers). V4.1 does
    // not distribute peer records; the new key reaches the contacts via
    // the KEY_ROTATION broadcast below, which goes via [sendToUser] and
    // thus via the V4.1 switch (T).

    // Build KEY_ROTATION message. §4.5.4: the notice carries the mode —
    // a routine rotation only renews the KEM material, `K_AB` and the
    // codes stay (they hang on the founding keys, §4.3).
    final rotationMsg = proto.KeyRotation()
      ..newX25519Pk = identity.x25519PublicKey
      ..newMlKemPk = identity.mlKemPublicKey
      ..rotationTimestamp = Int64(DateTime.now().millisecondsSinceEpoch)
      ..mode = proto.KeyRotationMode.KEY_ROTATION_MODE_TAGS_VALID;

    // Sign the rotation data with our identity key
    final dataToSign = rotationMsg.writeToBuffer();
    rotationMsg.signature = SodiumFFI().signEd25519(dataToSign, identity.ed25519SecretKey);

    // Broadcast to all accepted contacts
    final payload = Uint8List.fromList(rotationMsg.writeToBuffer());
    for (final contact in _contacts.values) {
      if (contact.status != 'accepted') continue;
      if (contact.x25519Pk == null || contact.mlKemPk == null) continue;
      _detachedSend('MT_KEY_ROTATION_BROADCAST', sendToUser(
        recipientUserId: contact.nodeId,
        messageType: proto.MessageType.MT_KEY_ROTATION_BROADCAST,
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

    // §4.5.4 (D-33, E-A8): "An identity whose founding secret key cannot
    // be derived from the seed on the rotating device does not rotate —
    // `K_AB` would change silently." After the rotation the delivery layer
    // forms every pair secret from the founding key (§4.3); without it the
    // rotation would cut every pair.
    if (identity.foundingEd25519SecretKeyDerived == null) {
      _log.error('rotateIdentityKeys: ABORTED — the founding secret key of '
          'this identity cannot be derived from the seed here (§4.5.4). '
          'NOTHING was rotated; the existing keys are unchanged.');
      onStateChanged?.call();
      return;
    }

    final sodium = SodiumFFI();

    // 1. Form new keys.
    //
    //    The new keys come from FRESH entropy, not from the existing
    //    seed. §14.4: "Rotated sig keys are — like rotated KEM
    //    keys (§4.5) — random and **not seed-derivable**: the founding key
    //    remains the identity anchor from the seed". The HD path serves
    //    here only as a derivation function over the NEW seed, so that the
    //    PQ keys match it reproducibly.
    final newEntropy = sodium.randomBytes(32);
    final newMasterSeed = SeedPhrase.entropyToSeed(newEntropy);
    final hdIndex = identity.hdIndex ?? 0;

    final newEd25519 = HdWallet.deriveEd25519(newMasterSeed, hdIndex);
    final newX25519Pk = sodium.ed25519PkToX25519(newEd25519.publicKey);
    final newX25519Sk = sodium.ed25519SkToX25519(newEd25519.secretKey);
    final pqKeys =
        await generatePqKeysDeterministicIsolated(newMasterSeed, hdIndex);

    // 2. Build the announcement. It carries no signature of its own any
    //    more (S398, D-33): the envelope that carries it is signed hybrid by
    //    the NEW keys and carries the hybrid rotation chain inside its seal
    //    (§4.4.3, §4.5.4) — the continuity proof the Ed25519-only fields
    //    5/6 stood in for. TAGS_VALID is what the norm states: "`K_AB`
    //    survives every rotation" (§4.3, §4.5.4) — the codes stay.
    final broadcast = proto.KeyRotationBroadcast()
      ..newEd25519Pk = newEd25519.publicKey
      ..newMlDsaPk = pqKeys.mlDsaPk
      ..newX25519Pk = newX25519Pk
      ..newMlKemPk = pqKeys.mlKemPk
      ..mode = proto.KeyRotationMode.KEY_ROTATION_MODE_TAGS_VALID
      ..emergency = true;

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

    // 4. Apply locally. `rotateIdentityFull` first appends the hybrid link
    //    old→new to the rotation chain (`identity_context.dart`) — proof
    //    (i) of §14.4.
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

    // 4a. THE RUNNING MAILBOX TAKES THE ROTATION OVER (S398, proposal A
    //     §2.9 step 4). Until S398 nothing was said to it: it kept signing
    //     with the replaced keys until the next start, and whoever held
    //     them kept reading along (`S398-ROTATION-REST.md`, finding 3).
    //     mycelium swaps all four keys under the same identifier, keeps the
    //     chain, sets every contact back to "chain not acknowledged", sends
    //     the new day keys, re-seals what is open and revokes standing
    //     invitations (`mailbox_rotation.dart`).
    final box = myceliumMailbox;
    if (box != null) {
      try {
        mycelium.MailboxRotation(box).identityRotate(postBoxFrom(identity));
      } catch (e) {
        _log.error('rotateIdentityKeys: the running mailbox did not take the '
            'rotation over ($e) — it takes the new keys at the next start');
      }
    }

    // 5. Pairwise to every accepted contact (§14.4) — AFTER applying: the
    //    envelope is sealed and signed with the NEW keys and carries the
    //    chain inside its seal (§4.5.4 "Where the chain travels: in the
    //    announcement").
    final recipient = <String>[];
    final sendings = <(String, Uint8List, Future<bool>)>[];
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
      final mid = SodiumFFI().randomBytes(16);
      sendings.add((
        bytesToHex(contact.nodeId),
        mid,
        sendToUser(
          recipientUserId: contact.nodeId,
          messageType: proto.MessageType.MT_KEY_ROTATION_BROADCAST,
          payload: payload,
          messageId: mid,
          management: true,
        ),
      ));
    }

    // 6. Bookkeeping for the resubmission (§26.6.2 package C). Every resend
    //    goes out in an envelope under the current keys and carries the
    //    chain until the contact acknowledged one (E-A7).
    _keyRotationRetry.startNewRotation(
      broadcastBytes: payload,
      contactNodeIdsHex: recipient,
      oldUserIdHex: identity.userIdHex,
      now: DateTime.now().millisecondsSinceEpoch,
    );
    //    Each broadcast is noted with the delivery layer's sending it went
    //    out as — its delivery state decides "not reached" (S408 P20, D-47).
    for (final (hex, mid, sent) in sendings) {
      _detachedSend('MT_KEY_ROTATION_BROADCAST (emergency)',
          sent.then((ok) {
        final a = _myceliumOutbounds[bytesToHex(mid)];
        if (ok && a != null) {
          _keyRotationRetry.noteSending(hex, bytesToHex(a.identifier));
        }
        return ok;
      }));
    }

    // 7. §14.5 path 2: the device set goes along pairwise. Without it
    //    the receiver would have no device keys after this rotation
    //    against which it could check a quorum next time.
    _announceDeviceSetToContacts(occasion: 'key rotation');

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
        '${ownToken != null ? "1 own device" : "none"} (§14.8).');
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
              ..rotationTimestamp = rotation.rotationTimestamp
              ..mode = rotation.mode)
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
  /// [deliveryId] is only read by [proto.TwinSyncType.DELIVERY_MIRROR]: the
  /// 8-byte delivery identifier of the delivery that carried the mirrored
  /// frame, so the twin checks and keeps it in the same `received_ids`
  /// table (§20.2) as the device that received it first — no matter in
  /// which order the two collect.
  void _sendTwinSync(proto.TwinSyncType syncType, Uint8List payload,
      {Uint8List? targetDeviceId, Uint8List? deliveryId}) {
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
      deliveryId: deliveryId,
      where: _ownWhereWires(), // §14.7, D-46
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
    // `test/smoke/smoke_self_send_zone_guard.dart`. `_detachedSend` is
    // the latch that really takes hold at this place.
    _detachedSend('MT_TWIN_SYNC', sendToUser(
      recipientUserId: identity.nodeId,
      messageType: proto.MessageType.MT_TWIN_SYNC,
      payload: syncBytes,
      targetDeviceId: hasTarget ? targetDeviceId : null,
    ));
    // Handed over, not sent: whether a deposit was placed is logged by the
    // own line when it is (`cleona_service_own_line.dart`, B-14).
    _log.debug(hasTarget
        ? 'TWIN_SYNC($syncType) handed to the own line for device '
            '${_hexShort(targetDeviceId)}'
        : 'TWIN_SYNC($syncType) handed to the own line for '
            '${_devices.length - 1} twin(s)');
  }

  /// Send TWIN_ANNOUNCE to register this device with existing twins.
  void _sendTwinAnnounce() {
    if (_devices.length <= 1) return;

    final record = proto.DeviceRecord()
      ..deviceId = hexToBytes(_localDeviceId)
      ..deviceName = _devices[_localDeviceId]?.deviceName ??
          localDeviceName(_detectPlatform())
      ..platform = _platformToProto(_detectPlatform())
      ..firstSeen = Int64(_devices[_localDeviceId]?.firstSeen.millisecondsSinceEpoch ?? 0)
      ..lastSeen = Int64(DateTime.now().millisecondsSinceEpoch)
      ..deviceNodeId = identity.deviceNodeId;

    final payload = Uint8List.fromList(record.writeToBuffer());

    // V3: no MT_TWIN_ANNOUNCE — wrapped as TWIN_SYNC sub-type DEVICE_ANNOUNCE.
    try {
      final wrapper = buildTwinSyncEnvelope(
        syncId: SodiumFFI().randomBytes(16),
        deviceId: hexToBytes(_localDeviceId),
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        syncType: proto.TwinSyncType.DEVICE_ANNOUNCE,
        payload: payload,
        where: _ownWhereWires(), // §14.7, D-46
      );
      _detachedSend('MT_TWIN_SYNC', sendToUser(
        recipientUserId: identity.nodeId,
        messageType: proto.MessageType.MT_TWIN_SYNC,
        payload: wrapper,
      ));
      _log.info('TWIN_ANNOUNCE (TWIN_SYNC/DEVICE_ANNOUNCE) handed to the own '
          'line for $_localDeviceId');
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
      final known = _contacts[nodeIdHex];
      if (known != null) {
        // Already known: only the delivery-layer half may be new (a fresh
        // CONTACT_ADDED, §14.7). A deleted contact stays deleted (W-a, E9 open).
        if (!known.isDeleted) _ownLineContactTake(json, known);
        return;
      }

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
        // `peerFoundingPk` falls back to `ed25519Pk` — the same
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
      _ownLineContactTake(json, contact); // s_AB, day keys, neighbours (D-28)
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
      // §21.5.4, D-72: a configuration change sent on the other own device
      // (`_ownChatConfigMirror`) — no message.
      final configBytes = json['chatConfigUpdate'];
      if (configBytes is String) {
        _ownChatConfigApply(
            json['conversationId'] as String, base64Decode(configBytes),
            forGroup: json['group'] == true);
        return;
      }
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
        // §14.7, type 2: "mirror a message sent on one device" — for a
        // channel post the mirror is a channel post too, so the other
        // device shows what this device wrote, in the kind it wrote it in.
        // §17.2: the caller's missed-call entry mirrors as one (its text is
        // the i18n key); every other value of `type` is not taken from the
        // mirror.
        type: _channels.containsKey(conversationId)
            ? UiMessageType.channelPost
            : json['type'] == UiMessageType.callMissed.wireValue &&
                    isMissedCallKey(text)
                ? UiMessageType.callMissed
                : UiMessageType.text,
        // AP-4: the twin mirrors a message that was never sent on THIS
        // device — there is no observation here, only the other device's
        // notice. `placing` is the only value that claims nothing.
        status: MessageStatus.resting,
        isOutgoing: true,
        // §21.5.3 "on the sender's devices it starts when the message is
        // sent": the same moment on every own device — the time stamp of
        // the content, not the arrival of this mirror.
        sentAt: timestamp,
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
      } else if (_contacts.containsKey(conversationId)) {
        // D-37 (E5): a reply written on another own device to a contact
        // whose conversation does not exist here yet — it starts with it.
        // Until B-4 the mirror was dropped here while the log said "synced".
        _addMessageToConversation(conversationId, msg);
        _saveConversations();
        onStateChanged?.call();
      } else if (_groups.containsKey(conversationId)) {
        // §14.7, type 2 names no conversation kind: a group post mirrors
        // too, into the group the other device holds — the group itself
        // arrived with Type 6 (GROUP_CREATED). Until S403 a group post
        // fell through to "unknown … dropped" here (S401, finding NB-15).
        _addMessageToConversation(conversationId, msg, isGroup: true);
        _saveConversations();
        onStateChanged?.call();
      } else if (_channels.containsKey(conversationId)) {
        // Same for a channel the other device holds — channels travel by
        // their own protocols, not by a twin type (§14.7 "Deliberately not
        // on the list"); where the device does not hold the channel the
        // mirror is dropped below, harmlessly.
        _addMessageToConversation(conversationId, msg, isChannel: true);
        _saveConversations();
        onStateChanged?.call();
      } else {
        _log.debug('Twin MESSAGE_SENT to unknown $conversationId — dropped');
        return;
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
      if (conv != null) ensureLoaded(conversationId);
      final msg = conv?.messages.where((m) => m.id == messageId).firstOrNull;
      if (msg == null) {
        // The mirror of the deletion came before the mirror of the message
        // (no transport order): the mark holds the message back when it
        // comes. An own device is the source — nothing to check.
        _markDeleted(messageId);
        return;
      }

      _eraseMessageLocally(conversationId, msg, byAuthor: true);
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
      // §21.5.3: read on an own device is read — the deadline starts here too.
      if (_stampIncomingRead(conv, DateTime.now())) _saveConversations();
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

  /// Type 8 SETTINGS_CHANGED (§14.7): a shared setting of the identity
  /// changed on another own device. Key material never travels in this type
  /// — rotated keys reach the own devices in Type 16 only (§14.4) — so a
  /// payload naming none of the shared settings is discarded. Only its field
  /// names are logged, never its values.
  ///
  /// Shared (D-71, D-72): `transcriptionLanguage` (§21.7), `callsAllowed`
  /// per contact (§17, RL-7), `isAdult` and `reviewEnabled` (§15.10); each
  /// with the time of its change, the later change wins
  /// (`cleona_service_shared_settings.dart`).
  void _handleTwinSettingsChanged(List<int> payload) {
    try {
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      if (sharedSettingsAs423) {
        // The v4.2.3 handler, verbatim in effect (see the flag).
        final language = json['transcriptionLanguage'];
        if (language is String) {
          _transcriptionLanguageStore(language);
          _log.info('Twin-synced transcription language');
          onStateChanged?.call();
          return;
        }
        _log.warn('Twin SETTINGS_CHANGED: no shared setting among '
            '(${json.keys.join(', ')}) — discarded');
        return;
      }
      if (_sharedApply(json, from: 'another own device (Type 8)') == 0 &&
          !json.keys.any(const {
            'transcriptionLanguage',
            'isAdult',
            'reviewEnabled',
            'callsAllowed',
          }.contains)) {
        _log.warn('Twin SETTINGS_CHANGED: no shared setting among '
            '(${json.keys.join(', ')}) — discarded');
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
      // twin-sync instead of local IPC — including the co-auth attempt.
      // Read the record from the `remove` return value: `deviceNodeIdHex` is
      // gone from the map by now.
      unawaited(_applyDeviceSetRemoval(revoked, deviceIdHex));
      // §14.10: mirror of the call in `revokeDevice` for a revocation that
      // another device initiated over twin-sync.
      unawaited(rotateIdentityKeys());
      _log.info('Twin device revoked: $deviceIdHex');
      _notifyDevicesChanged();
    } catch (e) {
      _log.warn('Twin DEVICE_REVOKED failed: $e');
    }
  }

  /// The Emergency Key Rotation announcement of a contact (§4.5.4, §14.4) —
  /// since S398 (proposal A, D-33) ONLY the level, the quorum and the
  /// acknowledgement. The keys are no longer taken from here: the envelope
  /// carrying this notice carried the hybrid rotation chain inside its seal,
  /// mycelium checked it, and the app's drop site adopted the keys with the
  /// same check (`_adoptChainedKeys`, the one overwriting place). What this
  /// notice adds is the second piece of evidence of §14.4 — the device
  /// quorum — and with it whether the level the adoption lowered comes back.
  void _handleEmergencyKeyRotation(
    Uint8List senderUserId,
    ContactInfo contact,
    String senderHex,
    proto.KeyRotationBroadcast broadcast,
  ) {
    final newEd25519Pk = Uint8List.fromList(broadcast.newEd25519Pk);
    final newMlDsaPk = Uint8List.fromList(broadcast.newMlDsaPk);
    final newX25519Pk = Uint8List.fromList(broadcast.newX25519Pk);
    final newMlKemPk = Uint8List.fromList(broadcast.newMlKemPk);
    bool held(Uint8List? stored, Uint8List fresh) =>
        stored != null && constantTimeEquals(stored, fresh);
    // The notice must name the keys the contact now holds — adopted by the
    // chain. A notice naming others proves nothing: continuity is the chain.
    if (!held(contact.ed25519Pk, newEd25519Pk) ||
        !held(contact.mlDsaPk, newMlDsaPk)) {
      _log.warn('KEY_ROTATION_BROADCAST (emergency) from '
          '${senderHex.substring(0, 8)} names keys the contact does not hold '
          '— no chain adopted them (§4.5.4). Ignored, nothing changed.');
      return;
    }

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

    // §14.4 "Verification levels at sig rotation (normative)": the level
    // stays if BOTH proofs are present — (i) the continuity proof (the
    // chain, checked when the keys were adopted) and (ii) the quorum — and
    // falls back otherwise. The adoption lowered it provisionally and kept
    // what it was (`_levelBeforeRotation`); with the quorum it comes back.
    // An adoption this process did not see (a restart in between) leaves the
    // level lowered — the conservative side.
    final prevLevel = _levelBeforeRotation.remove(senderHex);
    if (prevLevel != null) {
      // The adoption set the re-verify lock for a verified level; a level
      // §14.4 retains lifts it again (`ContactInfo.applyKeyChange`).
      contact.applyKeyChange(onIdentityRotation(
        prevLevel,
        quorumMet: coAuthResult == RotationCoAuthResult.quorumMet,
        oldSignatureValid: true,
      ));
      _saveContacts();
    }
    // `newX25519Pk`/`newMlKemPk` entered the co-auth hash above; the keys
    // themselves were set at the adoption.
    if (!held(contact.x25519Pk, newX25519Pk) ||
        !held(contact.mlKemPk, newMlKemPk)) {
      _log.info('KEY_ROTATION_BROADCAST (emergency) from '
          '${senderHex.substring(0, 8)}: KEM keys moved on since (routine '
          'rotation after the emergency one) — level decided, keys kept');
    }

    // §26.6.2 Send KEY_ROTATION_ACK back to the rotator — same UserID as
    // before (stable anchor). Pure ACK — empty payload. V3 inner User-Sig +
    // outer Device-Sig + KEM-decap chain provides package-C-F2 forge defence.
    unawaited(sendToUser(
      recipientUserId: senderUserId,
      messageType: proto.MessageType.MT_KEY_ROTATION_ACK,
      payload: Uint8List(0),
    ));

    // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
    _log.debug('Emergency key rotation from ${contact.displayName}: '
        'announcement taken, UserID ${senderHex.substring(0, 8)} unchanged '
        '(stable anchor); level ${prevLevel ?? '(kept lowered)'}→'
        '${contact.verificationLevel}, coAuth=$coAuthResult');
    // The key-change warning (SR-1) fired at the adoption
    // (`_adoptChainedKeys`) — for every adopted rotation, announced or not.
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

  /// V3 handler for MT_KEY_ROTATION_ACK (§26.6.2). Pure ACK — frame.payload
  /// is empty. Auth is the §23.3 inner User-Sig + outer Device-Sig + KEM-
  /// decap chain (verified upstream by the V3 receive pipeline), providing
  /// package-C-F2 forge defence.
  void _handleKeyRotationAck(HarvestEvent event) {
    final senderHex = event.senderUserId.hex;
    if (!_contacts.containsKey(senderHex)) {
      _log.warn('KEY_ROTATION_ACK V3 from unknown sender ${senderHex.substring(0, 8)} — dropped');
      return;
    }
    _keyRotationRetry.markAcked(senderHex);
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
  void _handleRotationRejectionAlert(HarvestEvent event) {
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
  /// `messageType` is already a V3 `MessageType` — KEM/Sig/zstd are
  /// handled inside `sendToUser`. Used by the Calendar/Polls/Free-Busy
  /// cluster.
  Future<void> _sendEncryptedPayload(
    Uint8List recipientUserId,
    proto.MessageType messageType,
    Uint8List payload, {
    Uint8List? groupId,
  }) async {
    final recipientHex = bytesToHex(recipientUserId);
    final contact = _contacts[recipientHex];
    // B-3 (§4.3): with a group, a co-member who is not a contact is reached
    // as a group pair — the seam decides, and names a leg without a way.
    if ((contact == null || contact.x25519Pk == null || contact.mlKemPk == null) &&
        (groupId == null || groupId.isEmpty)) {
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

  // ── Voice Transcription ─────────────────────────────────────────────

  static WhisperModelSize _parseModelSize(String s) {
    switch (s) {
      case 'tiny':  return WhisperModelSize.tiny;
      case 'small': return WhisperModelSize.small;
      default:      return WhisperModelSize.base;
    }
  }

  /// The names a model size may carry over IPC and in the store.
  static const Set<String> _kModelSizeNames = {'tiny', 'base', 'small'};

  @override
  void Function(TranscriptionStatus status)? onTranscriptionStatusChanged;

  /// Last whole percent handed to [onTranscriptionStatusChanged] — a
  /// download reports every received chunk; the surface needs one step per
  /// percent, not thousands of IPC events.
  int _lastTranscriptionPercent = -1;

  void _fireTranscriptionStatus({bool force = false}) {
    final cb = onTranscriptionStatusChanged;
    if (cb == null) return;
    final pct =
        ((_voiceTranscription?.downloadProgress ?? 0.0) * 100).floor();
    if (!force && pct == _lastTranscriptionPercent) return;
    _lastTranscriptionPercent = pct;
    cb(_transcriptionStatusNow());
  }

  TranscriptionStatus _transcriptionStatusNow() {
    final vt = _voiceTranscription;
    var held = const VoiceTranscriptionSettings();
    try {
      held = VoiceTranscriptionSettings.readFrom(store) ?? held;
    } catch (e) {
      // `store` throws without a master seed (§21.4.1): the defaults are
      // shown, as the screen did before.
      _log.debug('Transcription settings not readable: $e');
    }
    return TranscriptionStatus(
      whisperAvailable: vt?.isWhisperAvailable ?? false,
      modelLoaded: vt?.isModelLoaded ?? false,
      downloadStatus: (vt?.downloadStatus ?? ModelDownloadStatus.idle).name,
      downloadProgress: vt?.downloadProgress ?? 0.0,
      downloadError: vt?.downloadError,
      downloadedModels: [
        for (final s in WhisperModelSize.values)
          if (WhisperFFI.isModelDownloaded(s)) s.name
      ],
      language: vt?.defaultLanguage ?? held.defaultLanguage,
      modelSize: held.modelSize,
      retentionDays: held.audioRetentionDays,
    );
  }

  @override
  Future<TranscriptionStatus?> getTranscriptionStatus() async =>
      _transcriptionStatusNow();

  @override
  Future<bool> setTranscriptionSettings({
    required String language,
    required String modelSize,
    required int retentionDays,
  }) async {
    if (!_kModelSizeNames.contains(modelSize) || retentionDays <= 0) {
      return false;
    }
    if (!VoiceTranscriptionConfig.production()
        .supportedLanguages
        .contains(language)) {
      return false;
    }
    try {
      final languageBefore =
          VoiceTranscriptionSettings.readFrom(store)?.defaultLanguage ??
              'auto';
      VoiceTranscriptionSettings(
        defaultLanguage: language,
        audioRetentionDays: retentionDays,
        modelSize: modelSize,
      ).writeTo(store);
      // The language is shared by the devices of the identity (§14.7
      // Type 8); retention and model size stay on this device.
      if (languageBefore != language) setTranscriptionLanguage(language);
      _voiceTranscription?.defaultLanguage = language;
      // The set size is the one transcription uses and reports ready for.
      _voiceTranscription?.modelSize = _parseModelSize(modelSize);
      return true;
    } catch (e) {
      _log.warn('Transcription settings not stored: $e');
      return false;
    }
  }

  @override
  Future<bool> downloadTranscriptionModel(String modelSize) async {
    final vt = _voiceTranscription;
    if (vt == null || !_kModelSizeNames.contains(modelSize)) return false;
    if (vt.downloadStatus == ModelDownloadStatus.downloading) return false;
    _lastTranscriptionPercent = -1;
    // Not awaited: the download takes minutes, the answer only says that
    // it runs; progress and end come through onTranscriptionStatusChanged.
    unawaited(vt.downloadModel(_parseModelSize(modelSize)));
    return true;
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
    _typing.close(); // S405 A-3: no typing timer outlives the service
    // ── AND THE RESCUE BUNDLE FROM THE COLLECTION EDGES (§13.3, B-1) ───────
    //
    // The edges belong to the SHARED node, the bundle to this identity. If
    // it stayed attached, a stopped identity would keep laying its rescue
    // bundle at every third day's edge — with the key state it had when
    // stopping, and without any caller knowing about it.
    recoveryBox?.detach();
    // A pending profile update stays pending in the store; the next run
    // sends it (`_profileUpdateDue`).
    _profileUpdateTimer?.cancel();
    _profileUpdateTimer = null;
    _faceToFaceClock?.cancel(); // §15.3: the record keeps the moment shown
    // A pending round of §16.2.4 stays in the store; the next run sends it.
    for (final t in _channelReactionTimers.values) {
      t.cancel();
    }
    _channelReactionTimers.clear();
    _faceToFaceClock = null;
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
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _moderation.dispose();
    _polls.dispose();
    _systemChannelEvictionTimer?.cancel();
    _systemChannelEvictionTimer = null;
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
    _inviteLinkService?.dispose();
    _inviteLinkService = null;
    _physicalTransferHelper?.dispose();
    _physicalTransferHelper = null;
    _updateBinaryStore = null;
    // §2.2.4: stop Identity Publisher (Auth/Liveness-Refresh-Loops)
    _saveContacts();
    _saveGroups();
    _saveConversations();
    _saveSuppressedReceiptIds();
    mailboxStore.dispose();
    await _voiceTranscription?.stop();
    await _archiveManager?.stopScheduler();
    // Do NOT stop the shared node here — the daemon manages its lifecycle
    await CLogger.flushAll();
    _log.info('CleonaService stopped');
  }

  void _saveInNetworkFlag(bool available) {
    try {
      final device = identity.deviceStoreForWrite();
      if (device == null) return;
      if (available) {
        device.putEntry(DeviceStore.areaDevice, DeviceStore.keyUpdateInNetwork,
            {'v': true});
      } else {
        device.removeEntry(
            DeviceStore.areaDevice, DeviceStore.keyUpdateInNetwork);
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
  ///   3. **Withdraw** — until S408-P23 `armV41InviteLines` forgot the
  ///      V4.1 pseudo counterpart here (fallen with `lib/core/tagline/`).
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
    _log.info('§15.3.3 REVOKED: invitation i=$index g=${rec.generation}'
        '${rec.label.isEmpty ? '' : ' "${rec.label}"'}');
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
  Future<InvitationIssueResult> awaitInvitationWayIn(String id) =>
      _cardWayIn(id);

  @override
  Future<bool> reportInvitationShown(String invitationId) async =>
      _cardShown(invitationId);

  @override
  Future<InvitationRedeemResult> redeemInvitationText(String text) =>
      _cardRedeem(readInvitationText(text,
          ownChannel: _ownCardChannel,
          nowUnixSeconds: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          // T-a: a `cleona:2:` line is redeemed only with a valid signature.
          verify: SodiumFFI().verifyEd25519));

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
      // v4_2 §26.6.3: `z=` stays in the link — the browser assemblers of
      // earlier 4.2 nodes trim block padding with it (v4.2.3: page code
      // `linkBinarySize`); the current assembler does not read it.
      binarySizes: manifest.binarySizes,
    );

    return link.toUrl();
  }

  static Future<SeedFileResult?> _runSeedIsolate(String binaryPath,
      String profileDir, String platform, String version,
      {String? expectedHash}) {
    return Isolate.run(() => _selfSeedInIsolate(
      binaryPath: binaryPath,
      profileDir: profileDir,
      platform: platform,
      version: version,
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
  // `cleona_service_pure.dart` declares it,
  // `cleona_service_update.dart` and the IPC entry `reloadManifest`
  // (further down in this file) call it.

  /// IPC entry: list all seeded platforms and versions.
  Map<String, List<String>> getSeededPlatforms() {
    final store = _updateBinaryStore;
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

  /// The rescue bundle in the post box (§13.3, B-1), set by `myceliumAttach`
  /// (`cleona_service_recovery_bundle.dart`). `null` without a mailbox or
  /// for an identity without seed/HD index.
  mycelium.BundleBox? recoveryBox;

  /// The enrolment of a further device (B-4b, D-39, D-40) —
  /// `cleona_service_enrolment.dart`.
  final EnrolmentRuntime _enrol = EnrolmentRuntime();

  @override
  EnrolmentView get enrolmentView => enrolViewBuild;
  @override
  Future<bool> enrolmentWindowOpen() => enrolOpenAll();
  @override
  Future<bool> enrolmentWindowCancel() => enrolCancelAll();
  @override
  Future<bool> enrolmentDecide(String requestIdHex, bool accept) =>
      enrolDecide(requestIdHex, accept);
  @override
  Future<bool> enrolmentRecoverNow() => enrolRecover();

  /// Restored contacts waiting for their first envelope (B-1 E7-b): UserID
  /// hex → `s_AB` and fixed neighbours from the bundle. Persisted with the
  /// bundle state, file-encrypted.
  final Map<String,
          ({Uint8List? pairRandom, List<BundleNeighbour> neighbours})>
      _recoveryAnchors = {};

  /// When a found bundle was taken over in this run — for the status line.
  DateTime? _recoveryTaken;

  /// The former fixed neighbours of a taken-over bundle and when it was
  /// taken over: every collection edge asks them until each restored
  /// contact is anchored, at most [kRecoveryFormerAskFor] (§13.2.1, V-RB).
  /// Persisted in the bundle area of the store; `null`: nothing to ask.
  ({DateTime at, List<BundleNeighbour> neighbours})? _recoveryFormer;

  /// The clock of the rescue bundle: the UTC day of a value, the age of the
  /// last deposit. A smoke moves it by days; nothing else sets it.
  DateTime Function() recoveryBundleClock = DateTime.now;

  /// The clock of the catching up (v4_2 §8.2 "After more than 7 days", §9.5,
  /// `cleona_service_catch_up.dart`): the moment a collection ended, and the
  /// age of the stored one. A smoke moves it by days; nothing else sets it.
  DateTime Function() catchUpClock = DateTime.now;

  /// The moment this run named when it last found an absence of more than
  /// 7 days at the end of a collection (§9.5) — `null`: it found none.
  DateTime? catchUpAskedSince;

  /// How many messages this run took from answers to its requests (§9.5) —
  /// for the log line of a completed answer and for the guards.
  int catchUpTaken = 0;

  /// §13.3.4: until when the last deposit lies with its holders, `null`: no
  /// bundle in the network.
  @override
  DateTime? get recoveryBundleValidUntil => recoveryBox?.validUntil;

  /// §22.7 at the service boundary — the readiness state as a string.
  ///
  /// **Without a mailbox `searching`, not `ready`.** That is the
  /// cautious direction and the only defensible one: `readinessState`
  /// means "it can be placed with redundancy". Where the delivery layer
  /// does not run at all (a process without a node), that is demonstrably
  /// not the case. The reverse fallback would
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
      _myceliumReadiness ?? kReadinessSearching;

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
  ///
  /// S405 A-2: under mycelium the two directions are measured, not left
  /// out — the norm keeps partner counts "separately by inbound and
  /// outbound" (v4_2 E-41, §28.7 rule 3). Outbound: neighbours that answer
  /// this node's requests (§22.7.1). Inbound: distinct open-network
  /// addresses that reached this node unasked since start or the last
  /// network change (the passive proof, `board_proof.dart`; E-41: "how much
  /// this node contributes for others"). Until S405 both read the replaced
  /// V4.1 layer and stood at 0.
  @override
  int? get syncPartnersOutbound => myceliumMailbox != null
      ? myceliumMailbox!.host.respondingNeighbours
      : 0;

  @override
  int? get syncPartnersInbound => myceliumMailbox != null
      ? (myceliumMailbox!.host.node.passiveProof?.inbound ?? 0)
      : 0;

  /// §25.4 "Answering neighbours" — the number `ready` hinges on (>= 2).
  /// S405 A-2: under mycelium it is the host's (§22.7.1); until then it
  /// read the replaced V4.1 layer and stood at 0 next to `ready`.
  @override
  int get independentSyncPartners =>
      myceliumMailbox?.host.respondingNeighbours ??
      0;


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

  // ── §12.7: ROUTER MAPPING AND FEWER EMPTY COVER PACKETS (S398-W4) ─────
  //
  // Device values of the ONE host, like source 4 above. Until S398 the
  // cover wish went to `v41Delivery` (the replaced layer, never attached)
  // and router mapping had no setter at all. Now both go to the mycelium
  // host through the seam (`mycelium_seam.dart`: `coverReduceSet`,
  // `portMappingSet`), which also persists them. Without a host: the
  // defaults of §12.7 are shown and the setters report `false`.

  @override
  bool get coverReduceEnabled {
    final p = myceliumMailbox;
    return p == null ? false : seam.coverReduceSetting(p.host);
  }

  @override
  bool get coverReduceActive {
    final p = myceliumMailbox;
    return p == null ? false : seam.coverReduceActive(p.host);
  }

  @override
  bool setCoverReduce(bool on) {
    final p = myceliumMailbox;
    if (p == null || !seam.coverReduceSet(p.host, on)) return false;
    _log.info('Fewer empty cover packets on W/LAN ${on ? 'on' : 'off'} — '
        'by the user (§12.7, §5.1)');
    onStateChanged?.call();
    return true;
  }

  @override
  bool get portMappingEnabled {
    final p = myceliumMailbox;
    return p == null ? true : seam.portMappingSetting(p.host);
  }

  @override
  Future<bool> setPortMappingEnabled(bool on) async {
    final p = myceliumMailbox;
    if (p == null) return false;
    final ok = await seam.portMappingSet(p.host, on, report: _log.info);
    if (!ok) return false;
    _log.info('Router mapping ${on ? 'on' : 'off'} — by the user (§12.7, '
        '§7.3)');
    onStateChanged?.call();
    return true;
  }

  // ── §21.3.3 item 3: THE SIZE OF THE BULK CACHE (S407-MASSENCACHE) ────

  @override
  int get bulkCacheMb {
    final p = myceliumMailbox;
    return p == null
        ? seam.bulkCacheBytesForPlatform() >> 20
        : seam.bulkCacheMb(p.host);
  }

  @override
  Future<bool> setBulkCacheMb(int mb) async {
    final p = myceliumMailbox;
    if (p == null || !seam.bulkCacheSet(p.host, mb)) return false;
    _log.info('Bulk cache set to $mb MB — by the user (§21.3.3)');
    onStateChanged?.call();
    return true;
  }

  /// The mycelium mailbox of this identity (V4.2, S387) — set by
  /// `myceliumAttach` (`cleona_service_mycelium.dart`) as soon as the
  /// host of the process is up. If it is set, it carries `sendToUser`.
  mycelium.Mailbox? myceliumMailbox;

  /// The holders the own-device line deposits at (§14.7, D-37) instead of
  /// the own ranking — ONLY for a probe that must not depend on the nodes
  /// the call of the test machine finds. `null` in operation.
  @visibleForTesting
  List<(InternetAddress, int)>? myceliumOwnLineHolders;

  /// app `messageId` (hex) -> mycelium outbound: the source of the display
  /// status for messages sent via mycelium. Capped, see
  /// `_kMyceliumOutboundsMax`.
  final Map<String, mycelium.Outbound> _myceliumOutbounds = {};

  /// app `messageId` (hex) -> a call signal still running (§17.2,
  /// `_myceliumSignalSend`); emptied at every call end
  /// (`_myceliumCallEnded`), so it holds at most the signals of the calls
  /// since the last end.
  final Map<String, ({mycelium.Outbound sent, bool terminal})>
      _myceliumSignals = {};

  /// The terminal signals that have outlived one call end already
  /// (`_myceliumCallEnded`).
  final Set<String> _myceliumSignalsOutlived = {};

  /// Read only, for probes: how many call signals are noted as running.
  @visibleForTesting
  int get myceliumSignalsRunning => _myceliumSignals.length;

  /// mycelium outbound -> app `messageId` (hex): the reverse of
  /// [_myceliumOutbounds] for the carrying callback of the mailbox (V11,
  /// §9.1, `cleona_service_mycelium.dart`). An `Expando` holds no key of
  /// its own; a displaced entry of the map simply never fires again.
  final Expando<String> _myceliumOutboundIds = Expando('myceliumOutboundId');

  /// Identifiers for which a proven delivery receipt of the application came.
  final Set<String> _myceliumAcknowledged = {};

  /// B-3 stage 0: legs (wire identifiers) that had no way at all — neither
  /// a contact nor a group pair (`cleona_service_group_pairs.dart`). Capped
  /// like [_myceliumOutbounds].
  final Set<String> _myceliumLegsWithoutWay = {};

  /// B-3: which group notices were already written this run
  /// (`group:member:kind`) — once per member and group, not per message.
  final Set<String> _groupNoticesShown = {};

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
  /// `NetworkPacket` bytes and since the CUT is only read and written
  /// so that an old profile is not silently overwritten.
  final LocalOutbox localOutbox = LocalOutbox();

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
  /// CAPPED like the register: [_legIndexMax]. If it overflows, the
  /// oldest entry is discarded (insertion order — `Map` in Dart keeps
  /// it). The loss costs the display of an update, not a delivery.
  final Map<String, ({String convId, String msgId})> _legIndex = {};

  /// How many legs the index keeps at most.
  ///
  /// THE SAME ORDER OF MAGNITUDE AS THE REGISTER it is fed from: an entry
  /// without a record in the register can no longer have any effect. The
  /// number is deliberately generous — an entry is two short strings.
  static const int _legIndexMax = 4096;

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
  ///     therefore catches NOTHING — measured in S351 (the guard is
  ///     `test/smoke/smoke_self_send_zone_guard.dart` today): "call site:
  ///     try/catch hat NICHTS gefangen". `_sendTwinSync` had exactly this
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

  /// The V4.1 application frame — ONE construction for both outputs.
  ///
  /// ── WHY THIS IS A SEPARATE METHOD (S363) ──────────────────────
  ///
  /// It is needed in two places: in the host branch of [sendToUser],
  /// which hands it out sealed, and in the no-host branch at the end of
  /// the same method, which puts it into the outbound compartment. Two
  /// constructions would be two opportunities to forget a field — and
  /// the resubmission would then seal something other than the first attempt.
  proto.ApplicationFrame _innerFrame({
    required Uint8List recipientUserId,
    required Uint8List senderUserId,
    required Uint8List messageId,
    required proto.MessageType messageType,
    required Uint8List payload,
    Uint8List? groupId,
    proto.ContentMetadata? contentMetadata,
    proto.EditMetadata? editMetadata,
    proto.ExpiryMetadata? expiryMetadata,
    int? groupMembershipEpoch,
    Uint8List? groupMembershipHash,
    Uint8List? postId,
  }) {
    final inner = proto.ApplicationFrame()
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
    // §16.2 "A group post carries one post identifier": the same 16 bytes in
    // every leg of the post. Absent for everything that is not a group post.
    if (postId != null && postId.isNotEmpty) inner.postId = postId;
    // §9.4 "Nothing overtakes a file" (S398-W5): the identifier of the file
    // this message waited behind, set by the queue for THIS message
    // identifier just before it hands the message on
    // (`cleona_service_file_order.dart`), taken once.
    final afterFile = _fileOrderAfterFile.remove(bytesToHex(messageId));
    if (afterFile != null) inner.afterFile = afterFile;
    return inner;
  }

  /// Message kinds whose loss is without consequence — they are NOT
  /// parked (§21.2).
  ///
  /// A typing indicator that is resubmitted an hour later claims that
  /// someone is typing right now; it would then not be late, but wrong.
  /// Until S363 it stood as `const vergaenglich` INSIDE the host branch
  /// and was thus invisible to the no-host branch.
  static const kEphemeralTypes = <proto.MessageType>{
    proto.MessageType.MT_TYPING_INDICATOR,
  };

  /// Whether [content] of a history entry is an application frame of a type
  /// in [kEphemeralTypes]. What is no frame is not ours to judge: `false`.
  static bool isEphemeralFrame(Uint8List content) {
    try {
      return kEphemeralTypes
          .contains(proto.ApplicationFrame.fromBuffer(content).messageType);
    } catch (_) {
      return false;
    }
  }

  /// THE SEAM (v4_2 §22.5).
  ///
  /// RETURN — ONE meaning (S401): `true` if the payload was TAKEN OVER and
  /// goes out without the caller doing anything more — handed to the
  /// mailbox (also when it is `resting` there for lack of a way), waiting in
  /// its line behind a file (§9.4), or parked in the outbound compartment
  /// because no mailbox is attached yet (§21.2; handed over at the attach).
  /// `false` if NOTHING was taken over and nothing ever will be: no keys, no
  /// contact and no group pair, a deleted contact, no complete address, the
  /// mailbox refused, a kind that is never parked. Only on `false` may a
  /// caller close its message as `failed` (§9.1: "no rung carried it at
  /// all"). `true` is no delivery claim; the state follows the register.
  ///
  /// Until S401 the no-mailbox branch answered `false` although it had
  /// parked the message. Its readers took that for "nothing handed over":
  /// the message showed the warning mark and went out at the attach.
  @override
  Future<bool> sendToUser({
    required Uint8List recipientUserId,
    required proto.MessageType messageType,
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
    // NO KEY OVERRIDES (B-3, S398, E6; v4_2 §22.5.1): a co-member who is not
    // a contact is reached as a group pair (§4.3), found by the UserID.
    // NO `speedForThisFrame` ANY MORE (S389). The parameter carried the
    // one-time downgrade to speed from the consent dialog. There is no
    // second send path any more to downgrade to (§3.3, §12.1), and the
    // dialog that produced it has lost its trigger.
    //
    // S398-W5: `true` only from the file-order queue itself, which hands on
    // a message whose turn has come (`cleona_service_file_order.dart`).
    bool fileOrderChecked = false,
    // §16.2: the post identifier of a group post — 16 bytes, the same in
    // every leg, set by the send paths of a group post (text, file, voice)
    // and by nothing else.
    Uint8List? postId,
  }) async {
    // §16.2.2 (S407 channel step 1): in a private channel the epoch and hash
    // a leg carries depend on the recipient — a subscriber holding the short
    // list checks the role state, or, before it showed the capability, the
    // short list it was given. ONE place for every channel send path (post,
    // edit, deletion, file, poll), so that none can forget it.
    if (groupId != null && groupMembershipEpoch != null) {
      final ch = _channels[bytesToHex(groupId)];
      final r =
          ch == null ? null : _channelRosterFor(ch, bytesToHex(recipientUserId));
      if (r != null) {
        groupMembershipEpoch = r.$1;
        groupMembershipHash = r.$2;
      }
    }
    // 0. NOTHING OVERTAKES A FILE (§9.4, D-34, S398-W5). A message written by
    //    the user to a leg on which a file is still not completely in the
    //    network waits here, persisted, and goes later in writing order.
    //    ONE place for every user message kind, so that no send path can
    //    forget it.
    if (!fileOrderChecked &&
        CleonaService.kFileOrderKinds.contains(messageType) &&
        !constantTimeEquals(recipientUserId, identity.userId)) {
      messageId = (messageId != null && messageId.isNotEmpty)
          ? messageId
          : SodiumFFI().randomBytes(16);
      if (_fileOrderHold(
        recipientUserId: recipientUserId,
        messageType: messageType,
        payload: payload,
        groupId: groupId,
        messageId: messageId,
        contentMetadata: contentMetadata,
        editMetadata: editMetadata,
        expiryMetadata: expiryMetadata,
        groupMembershipEpoch: groupMembershipEpoch,
        groupMembershipHash: groupMembershipHash,
        management: management,
        postId: postId,
      )) {
        return true; // handed to the queue: `resting` (§9.1)
      }
    }
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
    //    `HarvestEvent`, `_innerFrame` and `SenderIdentitySnapshot`, not
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
    // The V4.2 body (see "THE BODY LIES ON THE MAILBOX" below).
    Future<bool> viaMailbox() {
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
        postId: postId,
      );
    }
    // B-3 (§4.3, §22.5.1): without a contact record the recipient is a
    // group pair or nobody — the mailbox decides by the UserID; no KEM copy
    // of the app is involved (and there are no key overrides any more).
    if (!isSelfSend && contact == null && myceliumMailbox != null) {
      return viaMailbox();
    }
    // A contact without KEM keys cannot be sealed to; one with a provably
    // stale copy is sealed to anyway, but not silently (§4.5.4).
    if (!isSelfSend) {
      if (contact != null && contact.x25519Pk != null && contact.mlKemPk != null) {
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
      if (isSelfSend) {
        if (l3Result != null && l3Result.isNotEmpty) l3Result[0] = false;
        // §22.5.2: the own UserID is the one per-device case (D-37).
        return _myceliumOwnSend(
          messageType: messageType,
          payload: payload,
          messageId: messageId,
          targetDeviceId: targetDeviceId,
        );
      }
      return viaMailbox();
    }

    // ── WITHOUT A MAILBOX: PARK OR REFUSE ─────────────────────────────
    //
    // Only those get this far who have no mycelium mailbox attached — the
    // cold start before `myceliumAttach`, or a process that never attaches
    // one. Until S408-P23 a V4.1 switch stood here (`v41Delivery`,
    // `v41Host`, `routeFor`); its carrier `attachV41` had no caller since
    // S388, and it fell with `lib/core/tagline/`.
    //
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
    // `localOutbox.add` site in all of `lib/` stood there), so there was no
    // resubmission either: the announcement was gone until the next
    // rotation in SEVEN DAYS (`needsRotation`, `kKemRotationInterval`).
    //
    // ── WHY PARK AND NOT SWAP THE ORDER ──────────────
    //
    // Swapping the order covers exactly one send site. §21.2 already
    // describes the right thing for this situation — "a node's own
    // cells stay local until their placement is substantiated" —, and
    // the compartment has its drain at the attach of the mailbox
    // (`_myceliumParkedHandedOver`). Parking therefore happens here, where
    // EVERY sender passes by.
    //
    // NO TIMER RETRY (working rule 5): the drain hangs on the attach, not
    // on a clock.
    //
    // WHAT IS NOT PARKED, and why separately:
    //   * [kEphemeralTypes] — their loss is without consequence, their
    //     resubmission would be a lie (see there).
    //   * SELF-SEND — the hand-over at the attach goes to contacts
    //     (`_myceliumParkedHandedOver`); an own-line entry would be a
    //     compartment that never drains.
    //   * V3 infrastructure — it has no SUBJECT in 4.2, not merely no
    //     carrier. Waiting changes nothing about that; that is the case
    //     the line below reports.
    //   * A CALL SIGNAL (`_kCallSignalTypes`, §17.2, D-45) — handed over at
    //     a later attach it would ring for nobody, or minutes later for a
    //     caller long gone: "A call rings within 10 seconds or not at all."
    //     The compartment is a post box on the own disk. Refused here by
    //     name, before the parking below (S407-B6CALL).
    if (_kCallSignalTypes.contains(messageType)) {
      _log.warn('sendToUser: ${messageType.name} to '
          '${_hexShort(recipientUserId)} — no mailbox attached, and a call '
          'signal is not parked (§17.2: it rings now or not at all). Not '
          'sent.');
      if (l3Result != null && l3Result.isNotEmpty) l3Result[0] = false;
      return false;
    }
    if (!isSelfSend &&
        !kEphemeralTypes.contains(messageType) &&
        !kOffDeliveryTypes.contains(messageType)) {
      final parkedId = (messageId != null && messageId.isNotEmpty)
          ? messageId
          : SodiumFFI().randomBytes(16);
      // The compartment keeps ONE frame per identifier (`LocalOutbox.add` is
      // idempotent). An edit or a deletion carries the identifier of its
      // message; while that message — or an earlier edit of it — is still
      // parked, this frame is NOT taken in, and the answer says so.
      if (localOutbox.lookup(_hexOf(parkedId)) != null) {
        _log.warn('sendToUser: ${messageType.name} to '
            '${_hexShort(recipientUserId)} — no mailbox attached, and a frame '
            'under the identifier ${_hexOf(parkedId).substring(0, 8)} is '
            'parked already. Not taken over.');
        if (l3Result != null && l3Result.isNotEmpty) l3Result[0] = false;
        return false;
      }
      final parked = _innerFrame(
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
        postId: postId,
      );
      localOutbox.add(LocalOutboxEntry(
        messageId: parkedId,
        recipientUserId: recipientUserId,
        frame: Uint8List.fromList(parked.writeToBuffer()),
        messageType: messageType.name,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
        groupIdHex: (groupId != null && groupId.isNotEmpty)
            ? _hexOf(groupId)
            : null,
        // The same justification as in the host branch: the class is a
        // property of THIS message and cannot be reconstructed from the
        // entry.
        management: management,
      ));
      saveLocalOutbox();
      _log.warn('sendToUser: ${messageType.name} to '
          '${_hexShort(recipientUserId)} — no mailbox attached yet. Put '
          'into the parking compartment (§21.2), handed to the mailbox at '
          'the attach. Until S363 it was discarded here; a cold-start '
          'rotation was thus gone for seven days.');
      if (l3Result != null && l3Result.isNotEmpty) l3Result[0] = false;
      // PARKED IS TAKEN OVER (S401): created, not yet sent — `resting`
      // (§9.1) —, handed to the mailbox at the attach
      // (`_myceliumParkedHandedOver`). The same answer the line behind a
      // file gives at the top of this method. What the mailbox refuses at
      // the attach is closed there, where that is observed.
      return true;
    }

    if (l3Result != null && l3Result.isNotEmpty) l3Result[0] = false;
    if (isSelfSend) {
      _log.error('sendToUser: self-send ${messageType.name} — no '
          'mailbox attached. The own line (§14.7) needs a running node like '
          'any other delivery.');
    } else {
      _log.error('sendToUser: ${messageType.name} to '
          '${_hexShort(recipientUserId)} — no mailbox attached, and this '
          'kind is not parked. There is no second path.');
    }
    return false;
  }

  // ── §5.5 store-and-forward: remaining static member ──
  // The rest of the section lives in `cleona_service_v3_sf.dart`.
  // A `static` cannot move into an extension (§4c.5 limit 3):
  // it would then belong to the extension, and `CleonaService.isEmergency…`
  // would no longer resolve — smoke_emergency_rotation_discriminator
  // calls exactly like that.

  /// Welle 6 §7.4 path-discriminator. Returns true iff [broadcast] is the
  /// Emergency variant. Since S398 (proposal A, D-33) that is the explicit
  /// field `emergency` (10): the Ed25519-only dual signature (fields 5/6) is
  /// gone, continuity is the hybrid rotation chain inside the seal. Public so
  /// smoke tests can assert the discriminator without a full service.
  static bool isEmergencyKeyRotationBody(
      proto.KeyRotationBroadcast broadcast) =>
      broadcast.emergency;

  /// V3 READ_RECEIPT: mark outgoing as read by the recipient. It starts no
  /// expiry deadline: the sender's copy runs from the sending (§21.5.3 —
  /// "its deadline hinges on nothing the recipient reports").
  /// Conversation lookup is DM-style (senderUserId-hex). Backward-compat
  /// with raw-message-ID payloads is dropped in V3 — V3 senders always
  /// emit a structured ReadReceipt protobuf.
  void _handleReadReceipt(HarvestEvent event) {
    try {
      final receipt = proto.ReadReceipt.fromBuffer(event.payload);
      if (receipt.messageId.isEmpty) return;
      final msgIdHex = receipt.messageId.hex;
      // §16.2: the read mark of a group post names the group and the post
      // identifier; the author finds the post in the group conversation.
      // Without a group it is a 1:1 read mark, as before.
      final senderHex = event.senderUserId.hex;
      if (_checkGroupPostMembership(event, senderHex) == null) return;
      final conversationId =
          event.groupId != null ? event.groupId!.hex : senderHex;
      final conv = conversations[conversationId];
      if (conv == null) return;
      ensureLoaded(conversationId);
      for (final msg in conv.messages) {
        // S390: the read marker colours the two ticks and does not touch
        // the delivery state. As `MessageStatus.read` it overwrote
        // `delivered` — and because it was terminal, the proof of §9.2
        // got lost in the process.
        if (msg.isReferredToBy(msgIdHex) &&
            msg.isOutgoing &&
            !msg.readByRecipient) {
          msg.readByRecipient = true;
          persistMessage(conversationId, msg);
          _saveConversations();
          onReadReceiptReceived?.call(conversationId, msg.id);
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
  void _handleTypingIndicator(HarvestEvent event) {
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

      _typing.note(senderHex, typing: isTyping);
    } catch (e) {
      _logHandlerErrorEvent('handleTypingIndicatorV3', e, event);
    }
  }

  // C2 — Messaging
  //
  // Pattern (parallel to the C1 migration in _handleDeliveryReceipt etc.):
  //   - Inner KEM decrypt + user sig verify have already been passed by the
  //     frame BEFORE the call (cleona_node.dart). Here only parse
  //     frame.payload + update UI state + notifications.
  //   - Multi-identity / group fan-out: ApplicationFrame.group_id (field 17)
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

  /// [localEpoch] 0 asks the state in full whatever this device holds.
  void _sendResyncRequest(GroupInfo group, {int? localEpoch}) {
    final ownerHex = group.ownerNodeIdHex;
    if (ownerHex == identity.userIdHex) return; // we are owner, no need
    final req = proto.GroupMembershipResyncRequest()
      ..groupId = hexToBytes(group.groupIdHex)
      ..localEpoch = Int64(localEpoch ?? group.membershipEpoch);
    _detachedSend('MT_GROUP_MEMBERSHIP_RESYNC_REQUEST', sendToUser(
      recipientUserId: hexToBytes(ownerHex),
      messageType: proto.MessageType.MT_GROUP_MEMBERSHIP_RESYNC_REQUEST,
      payload: req.writeToBuffer(),
      groupId: hexToBytes(group.groupIdHex),
    ));
    _log.info('GM-2: RESYNC_REQUEST sent to owner ${ownerHex.substring(0, 8)} '
        'for group "${group.name}" (local epoch=${group.membershipEpoch})');
  }

  /// [localEpoch]: what this device holds — a subscriber on the short list
  /// names its role epoch (§16.2.2), 0 asks the state in full.
  void _sendChannelResyncRequest(ChannelInfo channel, {int? localEpoch}) {
    final ownerHex = channel.ownerNodeIdHex;
    if (ownerHex == identity.userIdHex) return;
    final req = proto.GroupMembershipResyncRequest()
      ..groupId = hexToBytes(channel.channelIdHex)
      ..localEpoch = Int64(localEpoch ?? channel.membershipEpoch);
    _detachedSend('MT_GROUP_MEMBERSHIP_RESYNC_REQUEST', sendToUser(
      recipientUserId: hexToBytes(ownerHex),
      messageType: proto.MessageType.MT_GROUP_MEMBERSHIP_RESYNC_REQUEST,
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
            'epoch $reqEpoch < ${group.membershipEpoch} — its state to it alone');
        // §16.2.2: "requests a resync from the owner (who responds with the
        // full signed member state)" — to the one who asked, every entry
        // full, not to every member.
        unawaited(_groupUpdateLegsSend(group, [
          (
            senderHex,
            proto.MessageType.MT_GROUP_INVITE,
            _buildSignedGroupInviteBytes(group),
          ),
        ]));
      } else {
        if (channel!.ownerNodeIdHex != identity.userIdHex) {
          _log.debug('GM-4: channel RESYNC_REQUEST for "$entityIdHex" but we are not owner — ignoring');
          return;
        }
        final requester = channel.members[senderHex];
        if (requester == null) {
          _log.warn('GM-4: channel RESYNC_REQUEST from non-member ${senderHex.substring(0, 8)} — dropped');
          return;
        }
        // §16.2.2: a subscriber on the short list holds the role state (or,
        // before it showed the capability, the short list it was given);
        // everyone else the membership epoch.
        final shortList = !_channelIsRole(requester) &&
            requester.viewEpoch != 0 &&
            _channelShortList(channel);
        final expected = !shortList
            ? channel.membershipEpoch
            : _channelShows(requester)
                ? _channelRoleEpoch(channel)
                : requester.viewEpoch;
        final reqEpoch = req.localEpoch.toInt();
        if (reqEpoch >= expected) {
          _log.debug('GM-4: channel RESYNC_REQUEST from ${senderHex.substring(0, 8)} '
              'already at epoch $reqEpoch (ours=$expected) — no resync needed');
          return;
        }
        _log.info('GM-4: channel RESYNC_REQUEST from ${senderHex.substring(0, 8)} '
            'epoch $reqEpoch < $expected — its state to it alone');
        // The state goes to the one who asked, not to every member.
        unawaited(_channelLegsSend(channel, [
          (
            senderHex,
            proto.MessageType.MT_CHANNEL_INVITE,
            _channelStateBytesFor(channel, senderHex),
          ),
        ]));
      }
    } catch (e) {
      _log.warn('GM-2/4: RESYNC_REQUEST parse fail: $e');
    }
  }

  /// The link preview the sender embedded (v4_2 "The sender fetches link
  /// previews, embedded and encrypted. The recipient makes zero network
  /// requests"): taken as it came, never fetched — an empty url means no
  /// preview. For a text (1:1 and group) and a channel post alike.
  void _takeWirePreview(UiMessage msg, proto.TextMessage tm) {
    if (!tm.hasLinkPreview() || tm.linkPreview.url.isEmpty) return;
    final lp = tm.linkPreview;
    msg.linkPreviewUrl = lp.url;
    msg.linkPreviewTitle = lp.title.isNotEmpty ? lp.title : null;
    msg.linkPreviewDescription =
        lp.description.isNotEmpty ? lp.description : null;
    msg.linkPreviewSiteName = lp.siteName.isNotEmpty ? lp.siteName : null;
    if (lp.thumbnail.isNotEmpty) {
      msg.linkPreviewThumbnailBase64 = base64Encode(lp.thumbnail);
    }
  }

  /// V3 TEXT: TextMessage-payload. Reply-fields (replyToMessageId +
  /// replyToSnippet) live on the proto sub-message. Link-Preview travels
  /// in `tm.linkPreview` (sender-side only — the receiver renders the card
  /// from the embedded data and MUST NOT issue a network request).
  void _handleText(HarvestEvent event) {
    try {
      final tm = proto.TextMessage.fromBuffer(event.payload);
      final senderHex = event.senderUserId.hex;
      final msgId = event.messageId.hex;
      // V3: ApplicationFrame.group_id (field 17) carries the group/channel
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
        // §16.2: in a group the quote names the post identifier; the quoted
        // post is kept here under the identifier of the own leg (or, at its
        // author, under the display identifier). The message keeps the
        // identifier the quoted one has HERE.
        final orig = _referredMessage(conversationId, replyToMessageId);
        if (orig != null) {
          replyToMessageId = orig.id;
          replyToSender = _contacts[orig.senderNodeIdHex]?.displayName ??
              orig.senderNodeIdHex.substring(0, 8);
          // If the snippet on the wire was empty (older sender or trimmed),
          // fall back to the text we still have locally.
          replyToText ??= orig.text.length > 200
              ? orig.text.substring(0, 200)
              : orig.text;
        }
      }

      final msg = UiMessage(
        id: msgId,
        conversationId: conversationId,
        senderNodeIdHex: senderHex,
        text: tm.text,
        // §22.5.3: display and sorting rely on the local arrival time only.
        timestamp: event.harvestedAt,
        type: UiMessageType.text,
        status: MessageStatus.delivered,
        isOutgoing: false,
        postId: event.postIdHex,
        replyToMessageId: replyToMessageId,
        replyToText: replyToText,
        replyToSender: replyToSender,
        membershipMismatch: isMembershipMismatch,
      );

      _takeWirePreview(msg, tm);

      final isChannel = _channels.containsKey(conversationId);
      final isGroup = _groups.containsKey(conversationId);
      final isNew = _addMessageToConversation(conversationId, msg,
          isGroup: isGroup, isChannel: isChannel);
      if (isNew && !_shouldSuppressNotification(
          conversationId, _claimedSendTimeMs(event))) {
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

  /// MEDIA_INLINE, lane 1 of §9.4: the payload is the container of
  /// `inlineContainer` (object < 256 KB, RS-striped); the object inside is
  /// raw bytes or a VoicePayload proto depending on MIME.
  /// frame.contentMetadata carries MIME, filename, size.
  void _handleMediaInline(HarvestEvent event) {
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

      final Uint8List object;
      try {
        object = mycelium.inlineObject(Uint8List.fromList(event.payload));
      } on mycelium.MediaBroken catch (e) {
        // No bubble with bytes that are not the sent object.
        _log.warn('[E2E media-inline-v3-recv] from=${senderHex.substring(0, 8)} '
            'msgId=${msgId.substring(0, 8)} dropped: $e');
        return;
      }

      // Voice: VoicePayload-Wrapper.
      Uint8List actualFileData = object;
      String? transcriptText;
      String? transcriptLanguage;
      double? transcriptConfidence;
      final isVoice = metadata.mimeType.startsWith('audio/');
      if (isVoice) {
        try {
          final voicePayload = proto.VoicePayload.fromBuffer(object);
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
        // §22.5.3: display and sorting rely on the local arrival time only.
        timestamp: event.harvestedAt,
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
        postId: event.postIdHex,
      );

      final isGroup = _groups.containsKey(conversationId);
      final isNew = _addMessageToConversation(conversationId, msg, isGroup: isGroup);
      if (isNew && !_shouldSuppressNotification(
          conversationId, _claimedSendTimeMs(event))) {
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
      // Without the file name: it is content of the message, and what a
      // notification shows of a file "is not written to a log" (§22.8).
      _log.info(
          '[E2E media-inline-v3-recv] from=${senderHex.substring(0, 8)} '
          'device=${_hexShort(event.senderDeviceId)} msgId=${msgId.substring(0, 8)} '
          'size=${actualFileData.length} mime=${metadata.mimeType}');

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

  /// V3 REACTION: EmojiReaction proto in frame.payload. Add/remove emoji
  /// on the target message. Conversation lookup is DM-style on sender hex
  /// (group fan-out see class header TODO).
  void _handleReaction(HarvestEvent event, {bool mirrored = false}) {
    try {
      final senderHex = event.senderUserId.hex;
      // §16.2.4: a reaction in a private channel is counted by its owner.
      final channel = event.groupId == null ? null : _channels[event.groupId!.hex];
      if (channel != null &&
          !channel.isPublic &&
          !SystemChannels.isSystemChannel(channel.channelIdHex)) {
        _channelReactionReceived(
            event, _ReactionEntity.ofChannel(channel), mirrored);
        return;
      }
      // §16.2.5: a member's reaction in a group in announcement mode on the
      // shared key comes 1:1 to the owner, which counts it (§16.2.4).
      final rg = event.groupId == null ? null : _groups[event.groupId!.hex];
      if (rg != null &&
          _groupReactsViaOwner(rg.groupIdHex) &&
          !_groupMayPost(rg.groupIdHex, senderHex)) {
        _channelReactionReceived(event, _ReactionEntity.ofGroup(rg), mirrored);
        return;
      }
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
      _log.debug('_handleReaction: targetMsgId=${targetMsgId.substring(0, 8)} conv.messages.length=${conv.messages.length}');
      ensureLoaded(conversationId);
      // §16.2: the identifier the message is kept under, or the post
      // identifier of a group post.
      final msg = _referredMessage(conversationId, targetMsgId);
      if (msg == null) return;

      // One reaction per person per message: the newest addition of a
      // sender replaces its earlier one — also when an older 4.2 sender
      // added a second reaction without removing the first.
      // Stored inside, behind both branches — the same justification as for
      // the own reaction path: the call used to stand in the INNER `if` and
      // thus only covered the case in which the emoji set became empty.
      _reactionPersonSet(conversationId, msg, senderHex, emoji, reaction.remove);
      // §16.2.4: an author's reaction enters the owner's next totals too.
      if (!mirrored &&
          _groupReactsViaOwner(conversationId) &&
          _groups[conversationId]?.ownerNodeIdHex == identity.userIdHex) {
        _channelReactionChanged(conversationId, msg.id);
      }
      onStateChanged?.call();
      _saveConversations();
      _log.debug(
          'REACTION-V3 ${reaction.remove ? "removed" : "added"} on '
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
  void _handleReply(HarvestEvent event) {
    try {
      final senderHex = event.senderUserId.hex;
      final mismatchResult = _checkGroupPostMembership(event, senderHex);
      if (mismatchResult == null) return;
      final isMembershipMismatch = mismatchResult;
      final tm = proto.TextMessage.fromBuffer(event.payload);
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
        // §22.5.3: display and sorting rely on the local arrival time only.
        timestamp: event.harvestedAt,
        type: UiMessageType.text,
        status: MessageStatus.delivered,
        isOutgoing: false,
        membershipMismatch: isMembershipMismatch,
        postId: event.postIdHex,
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
  void _handleEdit(HarvestEvent event) {
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
      if (conv != null) ensureLoaded(conversationId);
      final msgIndex =
          conv?.messages.indexWhere((m) => m.id == originalMsgId) ?? -1;
      if (msgIndex < 0) {
        // §21.5.1: "…an edit to a still-unknown message is buffered
        // instead of discarded" — without transport order (§18.1.3) the
        // edit can be here before the message. The mark keeps the text and
        // the moment of the edit from the CONTENT, names who asked, and is
        // applied — with the author check repeated — when the message it
        // names is held (`_pendingEditApply`). The pattern of the deletion
        // mark (`_markDeleted`): until S403 only the deletion buffered a
        // request that came too early, the edit was dropped (S401,
        // finding NB-17).
        _markEdited(originalMsgId,
            conversationId: conversationId,
            newText: editMsg.newText,
            editAtMs: editMsg.editTimestamp.toInt(),
            byHex: senderHex);
        return;
      }
      final original = conv!.messages[msgIndex];

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

  /// V3 DELETE: MessageDelete proto in payload. Only the author may delete;
  /// the message then leaves this profile on the one route
  /// (`_eraseMessageLocally`, §21.5.2).
  void _handleDelete(HarvestEvent event) {
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
      if (conv != null) ensureLoaded(conversationId);
      final original =
          conv?.messages.where((m) => m.id == targetMsgId).firstOrNull;
      if (original == null) {
        // No transport order (§18.1.3 "Problem"): the deletion is here
        // before the message. The mark names who asked, and holds the
        // message back only if that is its author.
        _markDeleted(targetMsgId, byHex: senderHex);
        return;
      }

      if (original.senderNodeIdHex != senderHex) {
        _log.warn(
            'DELETE-V3 rejected: sender ${senderHex.substring(0, 8)} != author '
            '(device=${_hexShort(event.senderDeviceId)})');
        return;
      }
      _eraseMessageLocally(conversationId, original);
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
  void _handleVoiceMessage(HarvestEvent event) {
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
      _handleMediaInline(event.withContentMetadata(patched));
      return;
    }
    _handleMediaInline(event);
  }
  void _handleIdentityDeleted(HarvestEvent event) {
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
  void _handleProfileUpdate(HarvestEvent event) {
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
  void _handleKeyRotationBroadcastEvent(HarvestEvent event) {
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
    // THE SECURITY CHECK IS NOT LOST THEREBY — it never sat in the path.
    // Since S398 (D-33) it is the hybrid rotation chain inside the seal,
    // checked by mycelium and again at the app's drop site
    // (`_adoptChainedKeys`); `_handleEmergencyKeyRotation` only decides the
    // level (chain + quorum, §14.4) and acknowledges. The periodic/emergency
    // distinction is made by `_handleKeyRotationBroadcast` on the field
    // `emergency`.
    proto.KeyRotationBroadcast? earlyParse;
    try {
      earlyParse = proto.KeyRotationBroadcast.fromBuffer(event.payload);
    } catch (_) {
      // If the body does not parse the downstream handler will fail in
      // the same way — let it produce its own error log.
    }
    if (earlyParse != null && isEmergencyKeyRotationBody(earlyParse)) {
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
  void _handleGroupCreate(HarvestEvent event) {
    // GROUP_CREATE shares the GROUP_INVITE payload schema and processing path.
    _handleGroupInvite(event);
  }
  void _handleGroupInvite(HarvestEvent event) {
    final senderHex = event.senderUserId.hex;

    // V3 payload is already plaintext (decrypted+authenticated by pipeline).
    proto.GroupInvite invite;
    try {
      invite = proto.GroupInvite.fromBuffer(event.payload);
    } catch (e) {
      _log.error('GROUP_INVITE parse failed: $e');
      return;
    }

    final groupIdHex = invite.groupId.hex;

    // §16.2.2: a group this device left comes back only with a NEW
    // invitation — a membership state that names this identity and is newer
    // than the one it left with. That lifts the mark; a state from before
    // the leaving (a second copy, a membership resend) is discarded.
    if (!_groups.containsKey(groupIdHex) &&
        !_groupMayBeHeld(groupIdHex,
            epoch: invite.membershipEpoch.toInt(),
            namesMe: invite.members
                .any((m) => m.nodeId.hex == identity.userIdHex))) {
      return;
    }

    // Build members map — B-3: a full entry only if it proves itself
    // (`cleona_service_group_pairs.dart`), a compact one keeps what we held.
    final unconfirmed = <String>{};
    final members =
        _groupMembersFromInvite(invite, _groups[groupIdHex], unconfirmed);

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
        // V1 = A (owner 08.10.2026): the late state decides nothing, but the
        // self-signed entries it carries for members held without one count.
        final taken = _groupLateEntriesTake(invite, oldGroup);
        if (taken > 0) {
          _log.info('GROUP_INVITE epoch $wireEpoch late: $taken self-signed '
              'entr${taken == 1 ? 'y' : 'ies'} taken, state stays at '
              '${oldGroup.membershipEpoch}');
          _saveGroups();
          final pairsBefore = _groupPairCount(groupIdHex);
          _groupPairsSync(oldGroup);
          if (oldGroup.joined && _groupPairCount(groupIdHex) > pairsBefore) {
            _sendTwinGroupCreated(oldGroup);
          }
          onStateChanged?.call();
        }
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
          // B-3 (proposal step 9): an admin who is not a contact is checked
          // against the ML-DSA key of its signed member entry — until S398
          // this check fell away silently for it.
          final senderMlDsaPk =
              _contacts[senderHex]?.mlDsaPk ?? _groupMemberMlDsa(senderMember);
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

    // §16.2.2 (S403, owner decision 03.10.2026, V2 = B): "A member removed
    // by the owner or an admin receives the new member list as well; its
    // device keeps the conversation readable, marked as removed, blocks
    // writing and discards later posts of the group, as after leaving."
    // An update that no longer names this identity IS that removal list —
    // GM-1 above has already checked the sender's authority, the epoch and
    // the signatures against the state this device held.
    if (isUpdate && !members.containsKey(identity.userIdHex)) {
      _groupRemovedFrom(groupIdHex, newEpoch);
      return;
    }

    final old = _groups[groupIdHex];
    // §16.2.2: description and image are settings, not part of the member
    // list. An update that carries none keeps what this device holds — a
    // v4.2.3 admin never sends them (`398a6e40`), and until S407 neither
    // did this version. A 4.2.3 stand-in of a probe takes what the update
    // carries, as 4.2.3 does.
    final keep = !channelReceiveAs423;
    final group = GroupInfo(
      groupIdHex: groupIdHex,
      name: invite.groupName,
      description: invite.groupDescription.isNotEmpty || !keep
          ? invite.groupDescription
          : old?.description,
      pictureBase64: invite.groupPicture.isNotEmpty
          ? base64Encode(invite.groupPicture)
          : (keep ? old?.pictureBase64 : null),
      ownerNodeIdHex: ownerHex,
      members: members,
      membershipEpoch: newEpoch,
      // B-3 (§16.2.2, E4): an invitation is not a join — the user joins
      // explicitly (`joinGroup`); an update keeps what we decided.
      joined: old?.joined ?? false,
      inviterNodeIdHex: old?.inviterNodeIdHex ?? senderHex,
      aloneQuestion: old?.aloneQuestion,
      // An update changes the membership and nothing local: the own choices
      // (§14.7.4 withheld delivery status, §9.4 "always load images") and the
      // moment the group arrived here stay (S407 group list, F-4).
      createdAt: old?.createdAt,
      withholdDeliveryStatus: old?.withholdDeliveryStatus ?? false,
      alwaysLoadImages: old?.alwaysLoadImages ?? true,
      profileOwed: old?.profileOwed,
    );
    _groupAloneCheck(group);

    _groups[groupIdHex] = group;
    _saveGroups();
    // B-3: the seeds of this leg wait in the mailbox; the pairs follow the
    // member state (and form only once we joined). A pair that forms with
    // this update goes to the other own devices (§14.7 Type 6).
    final pairsBefore = _groupPairCount(groupIdHex);
    _groupPairSeedsTake(invite, group);
    _groupPairsSync(group, unconfirmed: unconfirmed);
    if (group.joined && _groupPairCount(groupIdHex) > pairsBefore) {
      _sendTwinGroupCreated(group);
    }

    // Create conversation (or update existing)
    final conv = conversations.putIfAbsent(groupIdHex, () => Conversation(
      id: groupIdHex,
      displayName: invite.groupName,
      isGroup: true,
      profilePictureBase64: group.pictureBase64,
    ));
    conv.displayName = invite.groupName;
    conv.profilePictureBase64 = group.pictureBase64;
    _saveConversations();

    if (!isUpdate) {
      onGroupInviteReceived?.call(groupIdHex, invite.groupName);
      if (!group.joined) {
        _announceInvitation(groupIdHex, invite.groupName, senderHex,
            channel: false);
      }
      _log.info('Group invite received: "${invite.groupName}" from ${senderHex.substring(0, 8)}');
    } else {
      _log.info('Group updated: "${invite.groupName}" from ${senderHex.substring(0, 8)}');
    }

    // §16.2.2: "A post for a group the device does not hold yet is buffered
    // and applied when the invitation arrives." What waited here lies in
    // the identity's store — posts AND settings (§21.5.4), applied through
    // their own receive paths, so a post takes the deadline that applies
    // when it is applied.
    if (!isUpdate) _groupWaitingApply(groupIdHex);
    // §16.2.5 "Joining": the step the update reports after a joining.
    if (invite.hasSharedKeyStep()) _skStepHeard(groupIdHex, invite.sharedKeyStep);
    // §16.2.5: an owner or admin new to this device is owed the notice.
    unawaited(_capabilityNoticesDue());

    onStateChanged?.call();
  }

  void _handleGroupLeave(HarvestEvent event) {
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
    // §16.2.2: only a member can leave; anything else leaves no trace.
    if (!group.members.containsKey(senderHex)) {
      _log.warn('GROUP_LEAVE from non-member ${senderHex.substring(0, 8)} '
          'in "${group.name}" — dropped');
      return;
    }

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
    _groupAloneCheck(group);
    _saveGroups();
    _groupPairsSync(group); // B-3 (§4.3): the leaver's pair ends here
    // §16.2.5 "Leaving and removal", "Transfer of ownership": the owner — a
    // new one after the transfer — draws the next generation; the size is
    // checked.
    unawaited(_skDeparted(groupIdHex));

    // Add system message
    _addSystemMessage(groupIdHex, '$memberName left the group',
        type: UiMessageType.groupLeave, isGroup: true);
    _log.info('$memberName left group "${group.name}"');
  }
  // GROUP_KEY_UPDATE: no shared group key in pairwise-KEM model (§9.1).
  void _handleGroupKeyUpdate(HarvestEvent event) {}
  void _handleChannelCreate(HarvestEvent event) {
    // CHANNEL_CREATE shares the CHANNEL_INVITE payload schema and processing path.
    _handleChannelInvite(event);
  }
  void _handleChannelPost(HarvestEvent event) {
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
    if (roster != null && channel.roleView) {
      // §16.2.2: a subscriber on the short list checks the role state.
      isMembershipMismatch = _channelRoleViewMismatch(
          channel, roster.epoch, Uint8List.fromList(roster.hash), senderHex);
    } else if (roster != null) {
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
    // built as a TextMessage by the sender (see _sendChannelPost). This used
    // to be `utf8.decode(event.payload)`, which is the V2 assumption
    // ("V2 packed text as raw UTF-8 in encrypted_payload",
    // proto/app_payloads.proto::TextMessage). The old comment said "already
    // plaintext" — true for
    // *decrypted*, false for *unwrapped*. The result was that every channel
    // post rendered as its own protobuf encoding: text="test",
    // format_hint="plain" serialises to 0A 04 t e s t 12 05 p l a i n, which
    // displays as a line break, a box, "test", two boxes, "plain" — exactly
    // what the field screenshot showed. `allowMalformed: true` is why it did
    // that silently instead of throwing.
    final proto.TextMessage tm;
    try {
      tm = proto.TextMessage.fromBuffer(event.payload);
    } catch (e) {
      _log.warn('CHANNEL_POST from $senderHex: payload is not a TextMessage '
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
      // §22.5.3: display and sorting rely on the local arrival time only.
      timestamp: event.harvestedAt,
      type: UiMessageType.channelPost,
      status: MessageStatus.delivered,
      isOutgoing: false,
      postId: event.postIdHex,
      membershipMismatch: isMembershipMismatch,
    );
    // The preview the author embedded (S410 follow-up): until now a
    // subscriber dropped it, although every channel post with a link
    // carried it — the subscriber showed the bare link.
    _takeWirePreview(msg, tm);

    _addMessageToConversation(channelIdHex, msg, isChannel: true);
    _log.debug('Channel post received in "${channel.name}" from ${senderMember.displayName}');
  }

  void _handleChannelInvite(HarvestEvent event) {
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

    // Build members map from the repeated GroupMember field
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
        // §16.2.2: kept between owner and admins (complete list only).
        capabilities: m.capabilities,
        viewEpoch: m.viewEpoch.toInt(),
      );
    }
    // §16.2.2 (S407 channel step 1): the short list — owner, admins and
    // this subscriber; its epoch is the list's, the membership epoch comes
    // as a number.
    final shortList = invite.roleView && !channelReceiveAs423;
    final membersEpoch = shortList && invite.membersEpoch > 0
        ? invite.membersEpoch.toInt()
        : invite.membershipEpoch.toInt();

    // §16.2.2 (S403, V7): "The same mark is kept for a channel the device
    // left" — the channel comes back only with a NEW subscription, a
    // membership state that names this identity and is newer than the one
    // at the leaving (in a private channel the membership epoch). That
    // lifts the mark; anything else is a state from before and is
    // discarded.
    if (!_channels.containsKey(channelIdHex) &&
        !_groupMayBeHeld(channelIdHex,
            epoch: membersEpoch,
            namesMe:
                invite.members.any((m) => m.nodeId.hex == identity.userIdHex))) {
      return;
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

      // Sender must be owner or admin in the OLD state (§16.2.2 authority
      // gate). It holds with and without an epoch, as for a group: the
      // invitation without epoch (`sendChannelInviteToMember`) comes from
      // the owner too.
      final senderOldMember = oldChannel.members[senderHex];
      if (senderOldMember == null ||
          (senderOldMember.role != 'owner' && senderOldMember.role != 'admin')) {
        _log.warn('GM-4: CHANNEL_INVITE from non-admin ${senderHex.substring(0, 8)} '
            'in "${oldChannel.name}" — rejected');
        return;
      }

      // A short list after a short list is ordered by its own epoch; every
      // other state by the membership epoch (§16.2.2).
      final localEpoch = oldChannel.roleView && shortList
          ? oldChannel.viewEpoch
          : oldChannel.membershipEpoch;
      if (wireEpoch > 0) {
        // Epoch must be strictly increasing
        if (wireEpoch <= localEpoch) {
          _log.warn('GM-4: CHANNEL_INVITE epoch $wireEpoch <= $localEpoch '
              'in "${oldChannel.name}" — rejected (replay/downgrade)');
          // A late update may be the only copy of a member's signed entry
          // (§16.2.2, as for a group): that alone is taken.
          if (_channelLateEntriesTake(invite, oldChannel) > 0) {
            _saveChannels();
            _channelPairsSync(oldChannel);
          }
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
        // No epoch: taken from an owner/admin, without replay protection.
        newEpoch = localEpoch;
      }
    } else {
      // New channel — accept with wire epoch
      newEpoch = invite.membershipEpoch.toInt();
      if (newEpoch <= 0) newEpoch = 1;
    }

    // §16.2.2: the members' self-signed entries (checked), §4.3 base of the
    // group pairs with co-subscribers who are not contacts.
    _channelEntriesTake(invite, members, oldChannel);

    // §16.2.2: description and image are settings — an update that carries
    // none keeps what this device holds (a v4.2.3 owner never sends the
    // image, `398a6e40`), as for a group. The update changes the membership
    // and nothing local: "always load images" (§9.4) and the moment the
    // channel arrived here stay (S407 group profile, as F-4 for a group).
    final channel = ChannelInfo(
      channelIdHex: channelIdHex,
      name: invite.channelName,
      description: invite.channelDescription.isNotEmpty
          ? invite.channelDescription
          : (channelReceiveAs423 ? null : oldChannel?.description),
      pictureBase64: invite.channelPicture.isNotEmpty
          ? base64Encode(invite.channelPicture)
          : (channelReceiveAs423 ? null : oldChannel?.pictureBase64),
      createdAt: oldChannel?.createdAt,
      alwaysLoadImages: oldChannel?.alwaysLoadImages ?? true,
      profileOwed: oldChannel?.profileOwed,
      ownerNodeIdHex: ownerHex,
      members: members,
      isPublic: invite.isPublic,
      isAdult: invite.isAdult,
      language: invite.language.isNotEmpty ? invite.language : 'de',
      membershipEpoch: shortList ? membersEpoch : newEpoch,
      roleEpoch: invite.roleEpoch > 0 && !channelReceiveAs423
          ? invite.roleEpoch.toInt()
          : (oldChannel?.roleEpoch ?? 0),
      roleView: shortList,
      viewEpoch: shortList ? newEpoch : 0,
    );

    _channels[channelIdHex] = channel;
    _saveChannels();

    // §4.3: the seeds of this leg wait for their pairs; a subscriber without
    // its own entry signs it now and sends it to the inviter (§16.2.2).
    _channelPairSeedsTake(invite, channel);
    if (channel.members[identity.userIdHex]?.hasSignedEntry == false &&
        !channelReceiveAs423) {
      unawaited(_channelJoin(channel, senderHex));
    } else {
      _channelPairsSync(channel);
    }

    // Create conversation (or update existing)
    final conv = conversations.putIfAbsent(channelIdHex, () => Conversation(
      id: channelIdHex,
      displayName: invite.channelName,
      isChannel: true,
      profilePictureBase64: channel.pictureBase64,
    ));
    conv.displayName = invite.channelName;
    conv.profilePictureBase64 = channel.pictureBase64;
    _saveConversations();

    if (!isUpdate) {
      onChannelInviteReceived?.call(channelIdHex, invite.channelName);
      _announceInvitation(channelIdHex, invite.channelName,
          invite.inviterId.isEmpty ? senderHex : inviterHex,
          channel: true);
      _log.info('Channel invite received: "${invite.channelName}" from ${senderHex.substring(0, 8)}');
    } else {
      _log.info('Channel updated: "${invite.channelName}" from ${senderHex.substring(0, 8)}');
    }

    // §16.2.2/§21.5.4 (S403, V7/V8): what waited for this channel in the
    // identity's store is applied now, through its own receive path — the
    // posts of a left channel were discarded at the gate, so what waited
    // came before the leaving or between the subscriptions.
    if (!isUpdate) _groupWaitingApply(channelIdHex);
    // §16.2.5 "Joining": the step the update reports after a joining.
    if (invite.hasSharedKeyStep()) {
      _skStepHeard(channelIdHex, invite.sharedKeyStep);
    }
    // §16.2.5: an owner or admin new to this device is owed the notice.
    unawaited(_capabilityNoticesDue());

    onStateChanged?.call();
  }

  void _handleChannelLeave(HarvestEvent event) {
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
    // §16.2.2: only a member can leave; anything else leaves no trace.
    if (!channel.members.containsKey(senderHex)) {
      _log.warn('CHANNEL_LEAVE from non-member ${senderHex.substring(0, 8)} '
          'in "${channel.name}" — dropped');
      return;
    }

    final memberName = channel.members[senderHex]?.displayName ?? senderHex.substring(0, 8);
    final wasOwner = channel.ownerNodeIdHex == senderHex;
    final wasRole = _channelIsRole(channel.members[senderHex]);
    channel.members.remove(senderHex);

    if (wasRole && leaveMsg.roleEpoch > 0 && !channelReceiveAs423) {
      // §16.2.2 (S407 channel step 1): an owner or admin of this build names
      // the epochs after its leaving and, as owner, the new owner itself.
      _channelLeaveApply(channel, leaveMsg);
    } else if (wasOwner && channel.members.isNotEmpty) {
      // If the owner left, transfer ownership. A subscriber on the short
      // list knows no other subscriber: it can only follow an admin.
      final admin =
          channel.members.values.where((m) => m.role == 'admin').firstOrNull;
      final newOwner = admin ??
          (channel.roleView ? null : channel.members.values.first);
      if (newOwner != null) {
        newOwner.role = 'owner';
        channel.ownerNodeIdHex = newOwner.nodeIdHex;
        // Display name: only `debug` (owner decision 02.09.2026, S363/F-2).
        _log.debug('Channel owner left, transferred to ${newOwner.displayName}');
      }
    }
    _saveChannels();
    _channelPairsSync(channel); // §4.3: the pair with the leaver ends here
    // §16.2.5 "Leaving and removal", "Transfer of ownership": the owner — a
    // new one after the transfer — draws the next generation; the size is
    // checked.
    unawaited(_skDeparted(channelIdHex));

    // Add system message
    _addSystemMessage(channelIdHex, '$memberName left the channel',
        type: UiMessageType.channelLeave, isChannel: true);
    _log.info('$memberName left channel "${channel.name}"');
  }

  /// Handle CHANNEL_ROLE_UPDATE (type 73): update member role in channel or group.
  /// Architecture v3.0 Section 10.2: sent to ALL members, handler checks both
  /// channelManager and groupManager. Only owner/admin may change roles.
  void _handleChannelRoleUpdate(HarvestEvent event) {
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
      if (oldRole == newRole) {
        // The membership update that carries the role came first (an older
        // owner sends both): nothing changes, the epoch stays (F-1b).
        _log.debug('CHANNEL_ROLE_UPDATE for group $entityIdHex: role already '
            'held — nothing to change');
        return;
      }
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
    // §16.2.5: a new owner or admin is owed the capability notice.
    unawaited(_capabilityNoticesDue());

    onStateChanged?.call();
  }
  // Wave 2B.3: PEER_LIST_*, DHT_*, FRAGMENT_*, PEER_STORE_* dead-stub
  // declarations removed. PEER_LIST_*/DHT_* are §2.3.5 Infrastructure types
  // dispatched in cleona_node.dart's `_dispatchInfrastructureFrameLocal`.
  // FRAGMENT_*/PEER_STORE_* are dispatched via the service-layer Infra hook
  // (service_daemon.dart `node.onInfrastructureFramePayload`) into
  // `handleIncomingFragmentStoreInfra` etc.
  void _handleChatConfigUpdate(HarvestEvent event) {
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

    final newConfig = _chatConfigOf(configMsg);

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
        // §16.2.2 (S407 group profile): a change of name, description or
        // image and nothing else. A 4.2.3 stand-in does not read it.
        if (configMsg.hasProfile() && !channelReceiveAs423) {
          _groupProfileReceived(groupIdHex, senderHex, configMsg.profile);
          return;
        }
        final conv = conversations[groupIdHex];
        if (conv != null) {
          // §16.2.2: the announcement mode only where the update names it —
          // an older 4.2 admin does not, and its change must not switch the
          // mode off. A 4.2.3 stand-in does not read the field.
          newConfig.announcementOnly =
              configMsg.hasAnnouncementOnly() && !channelReceiveAs423
                  ? configMsg.announcementOnly
                  : conv.config.announcementOnly;
          final modeChanged =
              newConfig.announcementOnly != conv.config.announcementOnly;
          conv.config = newConfig;
          _saveConversations();
          if (modeChanged) _groupAnnouncementChanged(groupIdHex);
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
        if (configMsg.hasProfile() && !channelReceiveAs423) {
          _groupProfileReceived(groupIdHex, senderHex, configMsg.profile);
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
      // A group/channel this device does not hold: the gate has already
      // held the frame in the identity's store (§21.5.4 "posts … and
      // settings for it"), to be applied when the invitation arrives
      // (`_groupWaitingApply`). Reaching this branch means the gate did
      // not run in front of the handler — the frame is dropped and the
      // reason logged, nothing is kept in memory.
      _log.info('CHAT_CONFIG_UPDATE for the unknown group/channel '
          '${groupIdHex.substring(0, 8)} outside the waiting store — dropped');
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
      // Peer accepted a proposal of this identity. §21.5.4 "In 1:1, the
      // change requires consent … the reply comes back … with an `accepted`
      // flag and the original changes. On acceptance, both sides adopt it":
      // the identity consents by proposing, the partner by accepting. What is
      // adopted is the identity's OWN open proposal, and only if the
      // acceptance names exactly its values (a v4.2.3 partner sends them,
      // `proposedConfig` with `accepted: true`). An acceptance without such
      // a proposal here changes nothing; it is kept (one per conversation)
      // because the proposal another own device made may still be on its
      // way (D-72, no ordering between post-box deliveries), and applied
      // when it arrives (`_ownChatConfigApply`). S407-OFFEN-EINST O-1.
      final conv = conversations[senderHex] ??
          (_contacts.containsKey(senderHex)
              ? conversations.putIfAbsent(
                  senderHex,
                  () => Conversation(
                      id: senderHex,
                      displayName: _contacts[senderHex]!.displayName))
              : null);
      final short = senderHex.substring(0, 8);
      if (conv == null) {
        _log.info('DM config acceptance from $short — no conversation, '
            'nothing taken');
        return;
      }
      // An open proposal OF THE PARTNER waits for this side's answer — an
      // acceptance cannot be the reply to it and is not taken.
      if (conv.pendingConfigProposer == senderHex) {
        _log.warn('DM config acceptance from $short while its own proposal '
            'waits here — not taken');
        return;
      }
      final own = conv.pendingConfigProposer == identity.userIdHex
          ? conv.pendingConfigProposal
          : null;
      if (own != null && _sameDmConfig(own, newConfig)) {
        conv.config = own;
        conv.pendingConfigProposal = null;
        conv.pendingConfigProposer = null;
        conv.parkedConfigAcceptance = null;
        _saveConversations();
        onStateChanged?.call();
        _log.info('DM config accepted by $short');
        return;
      }
      if (own == null && _sameDmConfig(conv.config, newConfig)) {
        // Nothing open here and nothing it would change — a second copy of
        // an acceptance already applied.
        _log.info('DM config acceptance from $short names the values in '
            'force — nothing to take');
        return;
      }
      conv.parkedConfigAcceptance = newConfig;
      _saveConversations();
      if (own != null) {
        _log.warn('DM config acceptance from $short names other values than '
            'the open own proposal — not taken, kept until an own proposal '
            'of these values arrives');
      } else {
        _log.info('DM config acceptance from $short without an own proposal '
            'here — not taken, kept until an own proposal of these values '
            'arrives');
      }
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
  void _handleChatConfigResponse(HarvestEvent event) {}

  // Wave 2B.3: ROUTE_UPDATE, REACHABILITY_*, RELAY_*, HOLE_PUNCH_*
  // dead-stub declarations removed — all dispatched in cleona_node.dart
  // (`_dispatchInfrastructureFrameLocal`, see Wave 2B.3 section). RELAY_*
  // remains on the KEM-path with §5.5 logic (out of Wave 2B.3 scope).

  // IDENTITY_AUTH/LIVE_* (types 170-175): here stood six empty handlers
  // ("kept only for switch-case exhaustiveness"; the reference to
  // `cleona_node.dart` pointed to a file that does not exist on this
  // line). Removed for lack of a sender (S388-BAU-KONTAKT); the switch has
  // a `default`.
  void _handleTwinSync(HarvestEvent event) {
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
        case proto.TwinSyncType.DELIVERY_MIRROR:
          // §14.7 Type 18 (D-37, E5) — `cleona_service_own_line.dart`.
          // proto3 bytes: an unset field reads as empty, which is the
          // null of [_handleDeliveryMirror] ("nothing to check or keep").
          unawaited(_handleDeliveryMirror(sync.payload,
              sync.deliveryId.isEmpty ? null : Uint8List.fromList(sync.deliveryId)));
          break;
        case proto.TwinSyncType.KEM_ROTATED:
          // §14.7 Type 19 (D-40) — `cleona_service_kem_line.dart`.
          _handleKemRotated(sync.payload);
          break;
        case proto.TwinSyncType.GROUP_LEFT:
          // §14.7 Type 21 (S403, owner decision 03.10.2026, V1 = A) —
          // `cleona_service_identity.dart`.
          _handleTwinGroupLeft(sync.payload);
          break;
        case proto.TwinSyncType.CHANNEL_JOINED:
          // §14.7 Type 22 (S407, owner decision 08.10.2026, E17 = A) —
          // `cleona_service_identity.dart`.
          _handleTwinChannelJoined(sync.payload);
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
          req.approvalKind == proto.ApprovalKind.APPROVAL_KIND_DEVICE_SET_CHANGE
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
    // Countersigning is not available yet with more than one device (§14.5,
    // open work of Appendix C). This device could sign — its device signing
    // key exists ([_ownApprovalToken]) — but nothing could use the token:
    // no device sends a request (Type 12), the devices do not hold each
    // other's device signing public keys, and the rotated keys have no way
    // to the other devices (Type 16). An approval with the identity key
    // would not be one: whoever stole the seed could co-sign.
    _log.error('§14.5 approveRotation: countersigning is not available yet '
        'with more than one device (Types 12 and 16 are not built). '
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
        // check in `_handleRotationRejectionAlert` verifies the Primary's
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
    // see `_handleRotationRejectionAlert`).
    _log.error('§7.5: rejection of the rotation cannot be issued '
        '— no holder for the device key (gap G-9). The '
        'contacts learn NOTHING of the rejection.');
    return;
  }

  // B-4b (D-39): the V3 pairing path — Primary issues a delegation
  // certificate on DEVICE_PAIR_REQUEST/_APPROVE — is removed. A further device
  // is enrolled over the 24 words and approved in the Requests tab
  // (§14.6.1, `cleona_service_enrolment.dart`); there is no primary (§14.4).
  // With it went the linked-device key set, the delegation certificate and
  // the LD-8 delegation rotation (S398 P1): every device holds the seed and
  // signs with the identity signing keys (§14.6.2).

  void _handleDeviceRevocation(HarvestEvent event) {
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
      // (gap G-11) — and thus nothing to trim either.
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
  // ─────────────── CALL_MEDIA_STATE — own video on/off (§17.5, V1.12) ───────
  //
  // Scope of this block, deliberately narrow: encode our own state, decode the
  // peer's, keep the latest per (call, peer), and hand it out. It renders
  // nothing and it starts and stops no camera. The display is `call_screen.dart`
  // (`PeerVideoOffOverlay`); WHEN our own state changes is decided by
  // `call_service.dart` (`onOwnVideoStateChanged`, S399), and
  // [_announceOwnVideoState] below sends it.
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

  /// Builds the `MT_CALL_MEDIA_STATE` payload announcing **our own** video
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

  /// Sends our own video state of [session] to its peer — exactly one
  /// `CALL_MEDIA_STATE` per change (§17.5), called by
  /// `CallService.onOwnVideoStateChanged`.
  ///
  /// THE WAY IS THE SIGNALLING WAY (§17.2), `CallTransport.sendSignal`: an
  /// ordinary 1:1 message under the pair tags, the same way INVITE, ANSWER
  /// and HANGUP take, and like them placed ONCE. Not Plane D: the control
  /// frame of §17.1.1 carries only what it enumerates (speech level,
  /// readiness, presentation role, layout size, tree updates, RTT), and a 1:1
  /// call has no control plane at all.
  ///
  /// DETACHED, BUT OBSERVED — same reason as `CallService.sendKeyframeRequest`:
  /// an undeliverable state must not reach the daemon's zone handler.
  void _announceOwnVideoState(
      CallSession session, bool sendingVideo, CallVideoOffReason reason) {
    final Uint8List payload;
    try {
      payload = buildCallMediaStatePayload(
        callId: session.callId,
        sendingVideo: sendingVideo,
        reason: reason,
      );
    } catch (e) {
      _log.error('CALL_MEDIA_STATE build failed: $e');
      return;
    }
    _log.info('CALL_MEDIA_STATE to ${_shortHex(session.peerNodeIdHex)} in '
        'call ${_shortHex(session.callIdHex)}: sendingVideo=$sendingVideo'
        '${sendingVideo ? '' : ', reason=${reason.name}'}');
    _calls.callTransport
        .sendSignal(
          recipientUserId: hexToBytes(session.peerNodeIdHex),
          type: proto.MessageType.MT_CALL_MEDIA_STATE,
          payload: payload,
        )
        .catchError((Object e, StackTrace st) {
      _log.error('CALL_MEDIA_STATE threw (detached): $e\n$st');
      return false;
    });
  }

  static proto.VideoOffReason _toWireVideoOffReason(CallVideoOffReason r) {
    switch (r) {
      case CallVideoOffReason.userDisabled:
        return proto.VideoOffReason.VIDEO_OFF_REASON_USER_DISABLED;
      case CallVideoOffReason.bandwidthInsufficient:
        return proto.VideoOffReason.VIDEO_OFF_REASON_BANDWIDTH_INSUFFICIENT;
      case CallVideoOffReason.notSupported:
        return proto.VideoOffReason.VIDEO_OFF_REASON_NOT_SUPPORTED;
      case CallVideoOffReason.startFailed:
        return proto.VideoOffReason.VIDEO_OFF_REASON_START_FAILED;
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
    if (r == proto.VideoOffReason.VIDEO_OFF_REASON_NOT_SUPPORTED) {
      return CallVideoOffReason.notSupported;
    }
    if (r == proto.VideoOffReason.VIDEO_OFF_REASON_START_FAILED) {
      return CallVideoOffReason.startFailed;
    }
    return CallVideoOffReason.unspecified;
  }

  /// Handles an incoming `MT_CALL_MEDIA_STATE` (§10.6, V1.12).
  ///
  /// The frame is already decrypted and its user signature verified by the V3
  /// pipeline, so the sender identity in [proto.ApplicationFrame.senderUserId]
  /// is authenticated and is what the state is keyed by.
  ///
  /// Drops, in order: unparseable payloads, malformed call ids, and states that
  /// are not strictly newer than what that peer already told us for that call.
  /// The last one matters because this travels over an unordered datagram
  /// network: a reordered older frame would otherwise reinstate "video off"
  /// while frames are arriving, which is the very picture V1.12 exists to
  /// prevent.
  void handleCallMediaState(HarvestEvent event) {
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
    if (bytes == null) return 'no-device';
    final n = bytes.length < 4 ? bytes.length : 4;
    final sb = StringBuffer();
    for (var i = 0; i < n; i++) {
      sb.write(bytes[i].toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}

// `_IdentityPublisherSender` stood here — the adapter that took a
// `(MessageType, payload, peer)` triple off the `IdentityPublisher` and
// passed it on to `CleonaNode.sendInfraTo`. Publisher and node are both
// gone (see the field `_identityPublisher` above, T).

/// §5.8 One-Shot-Outbox entry.
///
/// Holds a canonical serialized [NetworkPacket] and the metadata required to
/// retry the single L3 placement attempt once the sender regains connectivity.
/// This is NOT a retry queue — the entry is flushed exactly once per
/// onNetworkChanged edge-trigger and then either removed (L3 placed) or kept
/// for the next edge (still 0 peers).
// S368: here stood `class _OutboxEntry` — the record of the V3 outbox with
// `canonicalPacketB64` (serialised `NetworkPacket` bytes). In the whole
// tree it was only created by its own `fromJson`.

/// Top-level entry point for [Isolate.run]: stores the binary from disk as
/// the complete object — entirely off the main thread, with bounded memory.
///
/// The body lives in [seedBinaryFileToStore]
/// (`lib/core/update/binary_seeder.dart`) since S404: it streams the file
/// (the old body read it whole and Reed-Solomon-encoded it in memory —
/// OOM at 515.7 MB peak on a 200 MB APK) and is directly testable; since
/// S407-UPDATEFRAGMENTE it writes no fragments. Uses raw file I/O instead
/// of [UpdateBinaryStore] to avoid CLogger's Timer.periodic which is not
/// sendable across isolate boundaries.
Future<SeedFileResult?> _selfSeedInIsolate({
  required String binaryPath,
  required String profileDir,
  required String platform,
  required String version,
  String? expectedHash,
}) async {
  return seedBinaryFileToStore(
    binaryPath: binaryPath,
    profileDir: profileDir,
    platform: platform,
    version: version,
    expectedHash: expectedHash,
  );
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


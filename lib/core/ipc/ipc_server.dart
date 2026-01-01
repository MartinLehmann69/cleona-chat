import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cleona/core/crypto/constant_time.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/ipc/ipc_messages.dart';
import 'package:cleona/core/moderation/moderation_config.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/link/data_port.dart';
import 'package:cleona/core/service/multi_interface_mode.dart';
import 'package:cleona/core/util/hex.dart' show hexToBytes, bytesToHex;
import 'package:cleona/core/service/cleona_service.dart';
import 'package:cleona/core/service/service_interface.dart'
    show kDataSaverOk;
// The refusal identifier travels as a value across the process boundary
// (S381). The getter `wireCode` lies in an extension — that does not come
// in via the `show` list above, hence a separate import here.
import 'package:cleona/core/contact/invite_issue_refusal.dart';
import 'package:cleona/core/service/invitation_card_types.dart';
import 'package:cleona/core/service/notification_sound_service.dart';
import 'package:cleona/core/archive/archive_config.dart';
import 'package:cleona/core/archive/archive_transport.dart';
import 'package:cleona/core/calendar/sync/sync_types.dart';
import 'package:cleona/core/calendar/sync/caldav_client.dart';
import 'package:cleona/core/calendar/sync/ews_client.dart';
import 'package:cleona/core/calendar/sync/google_calendar_client.dart';
import 'package:cleona/core/rendezvous/peer_rescue_bundle.dart';
import 'package:cleona/core/tray/tray_status.dart' show isTrayLanguage;

/// Per-client state tracking active identity.
class _ClientState {
  final Socket socket;
  String activeIdentityId;
  StreamSubscription<String>? subscription;
  bool removed = false;
  /// TCP clients (Windows) must authenticate before sending commands.
  bool authenticated;

  _ClientState({required this.socket, required this.activeIdentityId, this.authenticated = true});
}

/// The directory in which the IPC endpoint lies.
///
/// ── THE FINDING (13a, S370) ───────────────────────────────────────────
///
/// Here stood
///
///     socketPath.substring(0, socketPath.lastIndexOf(
///         Platform.isWindows ? '\\' : '/'))
///
/// — ONE separator, depending on the platform. The real Windows path,
/// however, is MIXED: `main.dart` forms `_baseDir` as `'$home/.cleona'`
/// with a SLASH and passes it via `--base-dir`, `service_daemon.dart`
/// appends `/cleona.sock`. What comes out is
///
///     C:\Users\Cleona/.cleona/cleona.sock
///
/// and `lastIndexOf('\\')` hit the backslash before `Cleona` — the parent
/// directory was `C:\Users`, i.e. the GRANDPARENT directory.
/// Without consequence, because `service_daemon.dart` creates the base
/// directory beforehand; but the line did not do what it was supposed to,
/// and the only reason why this never stood out was a different code path.
String ipcParentDir(String socketPath) {
  final a = socketPath.lastIndexOf('/');
  final b = socketPath.lastIndexOf('\\');
  final i = a > b ? a : b;
  if (i <= 0) return socketPath;
  return socketPath.substring(0, i);
}

/// IPC server: listens on a Unix Domain Socket (Linux) or TCP loopback
/// with auth token (Windows), dispatches commands to the correct
/// CleonaService based on identityId, and broadcasts events.
class IpcServer {
  final Map<String, CleonaService> _services; // nodeIdHex → service
  final String socketPath;
  final String _defaultIdentityId;
  final CLogger _log;

  ServerSocket? _server;
  final List<_ClientState> _clients = [];
  bool get hasClients => _clients.isNotEmpty;
  ModerationConfig _moderationConfig = ModerationConfig.production();

  /// Shared secret for TCP loopback auth (Windows only). Null on Unix socket.
  String? _authToken;

  /// Debug callback: fires for every dispatched command so the daemon logger can trace IPC.
  void Function(String command)? onCommandDispatched;

  /// The GUI has reported its language (owner decision V-10-a = b,
  /// 09.09.2026). The daemon hangs `NativeTray.setLocale` on it.
  ///
  /// There is NO command for this and no round trip of its own — the code
  /// travels as the field `uiLocale` along with a request the client makes
  /// anyway (`ipc_messages.dart`, `ipc_client.dart:_sendRequest`).
  void Function(String localeCode)? onUiLocale;

  /// What was passed on last — so that a field that COULD hang on every
  /// request does not trigger a menu rebuild on every request.
  String? _lastUiLocale;

  /// Callback to create a new identity at runtime (returns nodeIdHex or null).
  Future<String?> Function(String displayName)? onCreateIdentity;
  /// Callback to delete an identity at runtime.
  Future<bool> Function(String nodeIdHex)? onDeleteIdentity;
  /// Callback to start a recovered identity (from DHT registry).
  Future<void> Function(Identity identity)? onRecoveredIdentity;

  /// Rate-limit for `get_seed_phrase` — defence-in-depth against local scraping.
  DateTime? _lastSeedPhraseAccess;

  /// Debounce state for `manual_reconnect` IPC command (§12.3.1 tier 2).
  /// Sits between the 10 s spec-minimum and the §5.10 Stage-4/5 cooldown so
  /// consecutive taps cannot trigger a burst storm, while keeping the button
  /// responsive enough for a user who suspects a connection loss.
  DateTime? _lastManualReconnect;
  static const Duration _manualReconnectCooldown = Duration(seconds: 30);

  /// Callback to apply a downloaded update and restart (daemon-side).
  Future<void> Function()? onApplyUpdate;

  /// Local CalDAV server control — wired by the daemon. All four are fired
  /// by the `caldav_server_*` IPC commands.
  Map<String, dynamic> Function()? onCalDAVServerGetState;
  Future<Map<String, dynamic>> Function(bool enabled)? onCalDAVServerSetEnabled;
  Future<Map<String, dynamic>> Function()? onCalDAVServerRegenerateToken;
  Future<Map<String, dynamic>> Function(int port)? onCalDAVServerSetPort;

  IpcServer({
    required Map<String, CleonaService> services,
    required this.socketPath,
    required this._defaultIdentityId,
    String? profileDir,
  })  : _services = Map.of(services),
        _log = CLogger.get('ipc-server', profileDir: profileDir);

  Future<void> start() async {
    // Ensure parent directory exists with owner-only permissions.
    final parentDir = ipcParentDir(socketPath);
    Directory(parentDir).createSync(recursive: true);
    if (!Platform.isWindows) {
      Process.runSync('chmod', ['700', parentDir]);
    }

    if (Platform.isWindows) {
      // Windows: Unix Domain Sockets not supported in Dart — use TCP loopback.
      // Bind to port 0 (OS picks a free port), generate auth token, write both
      // to cleona.port file. Token prevents other local processes from connecting.
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = _server!.port;
      _authToken = _generateToken();
      final portFile = File(socketPath.replaceAll('.sock', '.port'));
      portFile.writeAsStringSync('$port:$_authToken');
      _log.info('IPC server listening on 127.0.0.1:$port (auth token required)');
    } else {
      // Linux/macOS: Unix Domain Socket
      final socketFile = File(socketPath);
      if (socketFile.existsSync()) {
        socketFile.deleteSync();
      }
      _server = await ServerSocket.bind(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      );
      Process.runSync('chmod', ['600', socketPath]);
      _log.info('IPC server listening on $socketPath');
    }

    _server!.listen(
      _onClientConnected,
      onError: (e) => _log.error('IPC server error: $e'),
    );

    // Hook into all service callbacks to broadcast events
    for (final entry in _services.entries) {
      _hookServiceCallbacks(entry.key, entry.value);
    }
  }

  /// Re-create the Unix socket on the same path. Called by the daemon's socket
  /// watchdog when the inode is deleted externally. Existing connected clients
  /// keep their fd; only new connections use the fresh socket.
  Future<void> rebindSocket() async {
    if (Platform.isWindows) return;
    try {
      final oldServer = _server;
      final socketFile = File(socketPath);
      if (socketFile.existsSync()) socketFile.deleteSync();
      _server = await ServerSocket.bind(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      );
      Process.runSync('chmod', ['600', socketPath]);
      _server!.listen(
        _onClientConnected,
        onError: (e) => _log.error('IPC server error: $e'),
      );
      _log.info('IPC socket re-created on $socketPath');
      oldServer?.close();
    } catch (e) {
      _log.error('IPC socket rebind failed: $e');
    }
  }

  /// Add a service at runtime (new identity created).
  void addService(String identityId, CleonaService service) {
    _services[identityId] = service;
    _hookServiceCallbacks(identityId, service);
  }

  /// Remove a service at runtime (identity deleted).
  void removeService(String identityId) {
    _services.remove(identityId);
  }

  void _hookServiceCallbacks(String identityId, CleonaService service) {
    final originalOnStateChanged = service.onStateChanged;
    service.onStateChanged = () {
      originalOnStateChanged?.call();
      // Send lightweight notification — client fetches full state if needed
      _broadcastEvent(IpcEvent(
        event: 'state_changed',
        data: {
          'nodeIdHex': service.nodeIdHex,
          'displayName': service.displayName,
          // §22.7.2: the transition searching/connecting -> ready is what
          // the GUI MUST see. If it only came in the next full snapshot, it
          // would be lost in exactly the layer that is meant to make it
          // visible.
          'readiness': service.readinessState,
          // §25.4: together with the state, not only in the next full
          // snapshot — the display shows both side by side (readiness as a
          // statement, partner numbers as progress), and two different ages
          // side by side read as an error.
          'syncPartnersOutbound': service.syncPartnersOutbound,
          'syncPartnersInbound': service.syncPartnersInbound,
          'independentSyncPartners': service.independentSyncPartners,
          // §24.4.2: a switch changes AT RUNTIME. If it only came in the
          // next full snapshot, the UI would keep showing the old state
          // after flipping it — and "a visible state" would be a delayed
          // one.
          'dataSaverActive': service.dataSaverActive,
          'dataSaverLockedBySecure': service.dataSaverLockedBySecure,
          // S388, §11.9: the switch of source 4 — the same reasoning.
          'externalRecordsEnabled': service.externalRecordsEnabled,
          // S373: the same reasoning as one line above — the consent and
          // its EFFECT change at runtime (a partner is added, a Secure chat
          // arises), and a UI that only learns of it in the next full
          // snapshot shows a state that no longer exists.
          'lanShapingActive': service.lanShapingActive,
          'lanSegmentIds': service.lanSegmentIds,
          'lanSegmentsGrantable': service.lanSegmentsGrantable,
          'lanSegmentsConsented': <String>[
            for (final id in service.lanSegmentIds)
              if (service.lanSegmentConsented(id)) id
          ],
          'peerCount': service.peerCount,
          'confirmedPeerCount': service.confirmedPeerCount,
          'reachablePeerCount': service.reachablePeerCount,
          'hasPortMapping': service.hasPortMapping,
          // AP-5a: the latch must reach the GUI while the session runs,
          // not only on the next full snapshot — it is what PEER-GATE G-3
          // keys off. NOT the gap G-3 (§13 recovery): that is a different
          // number range (gate inventory in
          // `docs/MIGRATION_V3_TO_V4_0_MYZEL.md:8639`). See the detailed
          // note at `ipc_client.dart:hasSessionConfirmedPeers`.
          'hasSessionConfirmedPeers': service.hasSessionConfirmedPeers,
          'isRunning': service.isRunning,
          // `mobileFallbackActive` IS DROPPED (2026-08-31, CUT). The value
          // came from `node.transport.isMobileFallbackActive` — the
          // substitute socket that V3 opened when the Wi-Fi was connected
          // but dead. V4.1 does not have this transport, and no component
          // in the tree can answer the question.
          // The key is therefore OMITTED instead of set to `false`:
          // `ipc_client.dart:421` reads it as
          // `as bool? ?? _mobileFallbackActive` and keeps its state when it
          // is absent — an invented number would be worse than none here.
        },
        identityId: identityId,
      ));
    };

    final originalOnNewMessage = service.onNewMessage;
    service.onNewMessage = (conversationId, message) {
      originalOnNewMessage?.call(conversationId, message);
      // §21.6/S392-B3: a freshly arrived message normally has no archive
      // entry — the stamp then sets `null` and costs one map lookup. It
      // stands here nevertheless, because the same feedback also carries a
      // RESTORED or subsequently delivered message, and because a path to
      // the UI without the stamp produces exactly the silent deviation the
      // projection is built against.
      service.archiveManager?.applyArchiveView([message]);
      _broadcastEvent(IpcEvent(
        event: 'new_message',
        data: {
          'conversationId': conversationId,
          'message': message.toJson(),
        },
        identityId: identityId,
      ));
    };

    service.onReadReceiptReceived = (conversationId, messageId) {
      _broadcastEvent(IpcEvent(
        event: 'read_receipt',
        data: {
          'conversationId': conversationId,
          'messageId': messageId,
        },
        identityId: identityId,
      ));
    };

    final originalOnContactRequest = service.onContactRequestReceived;
    service.onContactRequestReceived = (nodeIdHex, displayName) {
      originalOnContactRequest?.call(nodeIdHex, displayName);
      _broadcastEvent(IpcEvent(
        event: 'contact_request',
        data: {'nodeIdHex': nodeIdHex, 'displayName': displayName},
        identityId: identityId,
      ));
    };

    final originalOnContactAccepted = service.onContactAccepted;
    service.onContactAccepted = (nodeIdHex) {
      originalOnContactAccepted?.call(nodeIdHex);
      _broadcastEvent(IpcEvent(
        event: 'contact_accepted',
        data: {'nodeIdHex': nodeIdHex},
        identityId: identityId,
      ));
    };

    final originalOnGroupInvite = service.onGroupInviteReceived;
    service.onGroupInviteReceived = (groupIdHex, groupName) {
      originalOnGroupInvite?.call(groupIdHex, groupName);
      _broadcastEvent(IpcEvent(
        event: 'group_invite',
        data: {'groupIdHex': groupIdHex, 'groupName': groupName},
        identityId: identityId,
      ));
    };

    final originalOnChannelInvite = service.onChannelInviteReceived;
    service.onChannelInviteReceived = (channelIdHex, channelName) {
      originalOnChannelInvite?.call(channelIdHex, channelName);
      _broadcastEvent(IpcEvent(
        event: 'channel_invite',
        data: {'channelIdHex': channelIdHex, 'channelName': channelName},
        identityId: identityId,
      ));
    };

    // AP-5a: without this hook the daemon never told the GUI about a jury
    // request. `IpcClient.onJuryRequestReceived` was declared and assigned
    // (main.dart) but could not fire, so the jury banner only appeared on the
    // next coalesced `refreshState()`. Same shape as `incoming_call`: one
    // domain object, serialised via its own toJson().
    final originalOnJuryRequest = service.onJuryRequestReceived;
    service.onJuryRequestReceived = (request) {
      originalOnJuryRequest?.call(request);
      _broadcastEvent(IpcEvent(
        event: 'jury_request',
        data: request.toJson(),
        identityId: identityId,
      ));
    };

    final originalOnIncomingCall = service.onIncomingCall;
    service.onIncomingCall = (call) {
      originalOnIncomingCall?.call(call);
      _broadcastEvent(IpcEvent(
        event: 'incoming_call',
        data: call.toJson(),
        identityId: identityId,
      ));
    };

    final originalOnCallAccepted = service.onCallAccepted;
    service.onCallAccepted = (call) {
      originalOnCallAccepted?.call(call);
      _broadcastEvent(IpcEvent(
        event: 'call_accepted',
        data: call.toJson(),
        identityId: identityId,
      ));
    };

    final originalOnCallRejected = service.onCallRejected;
    service.onCallRejected = (call, reason) {
      originalOnCallRejected?.call(call, reason);
      _broadcastEvent(IpcEvent(
        event: 'call_rejected',
        data: {...call.toJson(), 'reason': reason},
        identityId: identityId,
      ));
    };

    final originalOnCallEnded = service.onCallEnded;
    service.onCallEnded = (call) {
      originalOnCallEnded?.call(call);
      _broadcastEvent(IpcEvent(
        event: 'call_ended',
        data: call.toJson(),
        identityId: identityId,
      ));
    };

    // Group Call events
    final originalOnIncomingGroupCall = service.onIncomingGroupCall;
    service.onIncomingGroupCall = (info) {
      originalOnIncomingGroupCall?.call(info);
      _broadcastEvent(IpcEvent(
        event: 'incoming_group_call',
        data: info.toJson(),
        identityId: identityId,
      ));
    };

    final originalOnGroupCallStarted = service.onGroupCallStarted;
    service.onGroupCallStarted = (info) {
      originalOnGroupCallStarted?.call(info);
      _broadcastEvent(IpcEvent(
        event: 'group_call_started',
        data: info.toJson(),
        identityId: identityId,
      ));
    };

    final originalOnGroupCallEnded = service.onGroupCallEnded;
    service.onGroupCallEnded = (info) {
      originalOnGroupCallEnded?.call(info);
      _broadcastEvent(IpcEvent(
        event: 'group_call_ended',
        data: info.toJson(),
        identityId: identityId,
      ));
    };

    final originalOnRestoreProgress = service.onRestoreProgress;
    service.onRestoreProgress = (phase, contactsRestored, messagesRestored) {
      originalOnRestoreProgress?.call(phase, contactsRestored, messagesRestored);
      _broadcastEvent(IpcEvent(
        event: 'restore_progress',
        data: {
          'phase': phase,
          'contactsRestored': contactsRestored,
          'messagesRestored': messagesRestored,
        },
        identityId: identityId,
      ));
    };

    // Calendar (§23) events
    final originalOnCalendarInvite = service.onCalendarInviteReceived;
    service.onCalendarInviteReceived = (senderHex, eventId, title) {
      originalOnCalendarInvite?.call(senderHex, eventId, title);
      _broadcastEvent(IpcEvent(
        event: 'calendar_invite',
        data: {'senderNodeIdHex': senderHex, 'eventId': eventId, 'title': title},
        identityId: identityId,
      ));
    };

    final originalOnCalendarRsvp = service.onCalendarRsvpReceived;
    service.onCalendarRsvpReceived = (eventId, responderHex, status) {
      originalOnCalendarRsvp?.call(eventId, responderHex, status);
      _broadcastEvent(IpcEvent(
        event: 'calendar_rsvp',
        data: {'eventId': eventId, 'responderNodeIdHex': responderHex, 'status': status.index},
        identityId: identityId,
      ));
    };

    final originalOnCalendarUpdate = service.onCalendarEventUpdated;
    service.onCalendarEventUpdated = (eventId) {
      originalOnCalendarUpdate?.call(eventId);
      _broadcastEvent(IpcEvent(
        event: 'calendar_event_updated',
        data: {'eventId': eventId},
        identityId: identityId,
      ));
    };

    final originalOnCalendarReminder = service.onCalendarReminderDue;
    service.onCalendarReminderDue = (eventId, title, minutesBefore) {
      originalOnCalendarReminder?.call(eventId, title, minutesBefore);
      _broadcastEvent(IpcEvent(
        event: 'calendar_reminder',
        data: {'eventId': eventId, 'title': title, 'minutesBefore': minutesBefore},
        identityId: identityId,
      ));
    };

    // Pending-conflict broadcast: the sync service queues user-decision
    // requests; the UI reacts by showing a dialog. Only wires once per
    // service instance (subsequent re-wires preserve the original hook).
    service.calendarSyncService.onPendingConflictQueued = (conflict) {
      _broadcastEvent(IpcEvent(
        event: 'calendar_sync_conflict_pending',
        data: conflict.toJson(),
        identityId: identityId,
      ));
    };

    // Polls (§24) events
    final originalOnPollCreated = service.onPollCreated;
    service.onPollCreated = (pollId, groupId, question) {
      originalOnPollCreated?.call(pollId, groupId, question);
      _broadcastEvent(IpcEvent(
        event: 'poll_created',
        data: {'pollId': pollId, 'groupId': groupId, 'question': question},
        identityId: identityId,
      ));
    };

    final originalOnPollTally = service.onPollTallyUpdated;
    service.onPollTallyUpdated = (pollId) {
      originalOnPollTally?.call(pollId);
      _broadcastEvent(IpcEvent(
        event: 'poll_tally_updated',
        data: {'pollId': pollId},
        identityId: identityId,
      ));
    };

    final originalOnPollStateChanged = service.onPollStateChanged;
    service.onPollStateChanged = (pollId) {
      originalOnPollStateChanged?.call(pollId);
      _broadcastEvent(IpcEvent(
        event: 'poll_state_changed',
        data: {'pollId': pollId},
        identityId: identityId,
      ));
    };

    // §26.6.2 package C: dedicated event when an emergency-key-rotation retry
    // gives up on a contact. GUI can warn the user that re-verification is
    // required (contact was unreachable for 90d or 3 attempts).
    final originalOnKeyRotationExpired = service.onKeyRotationPendingExpired;
    service.onKeyRotationPendingExpired = (contactNodeIdHex, pendingCount) {
      originalOnKeyRotationExpired?.call(contactNodeIdHex, pendingCount);
      _broadcastEvent(IpcEvent(
        event: 'key_rotation_pending_contact',
        data: {
          'contactNodeIdHex': contactNodeIdHex,
          'pendingCount': pendingCount,
        },
        identityId: identityId,
      ));
    };

    // SR-1 (§7.4b step 6 / §8.3): a contact emergency-rotated their identity
    // key. The receiver applied the new keys but reset the verification
    // level — the GUI must surface a key-change warning so the soft re-key
    // is not followed silently.
    final originalOnContactRotated = service.onContactIdentityRotated;
    service.onContactIdentityRotated =
        (contactNodeIdHex, displayName, wasVerified) {
      originalOnContactRotated?.call(
          contactNodeIdHex, displayName, wasVerified);
      _broadcastEvent(IpcEvent(
        event: 'contact_identity_rotated',
        data: {
          'contactNodeIdHex': contactNodeIdHex,
          'displayName': displayName,
          'wasVerified': wasVerified,
        },
        identityId: identityId,
      ));
    };

    // H-2 (§6.3.5): a contact restored their identity (set up a new device).
    // The GUI shows a notification; if the identity key changed, it escalates
    // to a key-change warning (verification was reset daemon-side).
    final originalOnRestoreDetected = service.onContactRestoreDetected;
    service.onContactRestoreDetected =
        (contactNodeIdHex, displayName, identityKeyChanged) {
      originalOnRestoreDetected?.call(
          contactNodeIdHex, displayName, identityKeyChanged);
      _broadcastEvent(IpcEvent(
        event: 'contact_restore_detected',
        data: {
          'contactNodeIdHex': contactNodeIdHex,
          'displayName': displayName,
          'identityKeyChanged': identityKeyChanged,
        },
        identityId: identityId,
      ));
    };

    // §7.5: escalated warning when rotation Co-Auth quorum is not met.
    final originalOnCoAuthWarning = service.onRotationCoAuthWarning;
    service.onRotationCoAuthWarning =
        (contactNodeIdHex, displayName, tokensPresent, tokensRequired) {
      originalOnCoAuthWarning?.call(
          contactNodeIdHex, displayName, tokensPresent, tokensRequired);
      _broadcastEvent(IpcEvent(
        event: 'rotation_co_auth_warning',
        data: {
          'contactNodeIdHex': contactNodeIdHex,
          'displayName': displayName,
          'tokensPresent': tokensPresent,
          'tokensRequired': tokensRequired,
        },
        identityId: identityId,
      ));
    };

    // §7.5: a linked device actively rejected a rotation — strongest theft signal.
    final originalOnRejectionAlert = service.onRotationRejectionAlert;
    service.onRotationRejectionAlert = (contactNodeIdHex, displayName) {
      originalOnRejectionAlert?.call(contactNodeIdHex, displayName);
      _broadcastEvent(IpcEvent(
        event: 'rotation_rejection_alert',
        data: {
          'contactNodeIdHex': contactNodeIdHex,
          'displayName': displayName,
        },
        identityId: identityId,
      ));
    };

    // §27.9 NAT-Troubleshooting-Wizard: push event when the 10-min trigger
    // fires so the GUI can show the wizard dialog. The event carries no
    // payload — the GUI fetches current stats via get_network_stats if it
    // wants to display port / local IP / router info.
    //
    // Multi-Identity note: the `identityId` field gates the client-side
    // dispatcher — only the active identity's GUI will act on it, but the
    // event is broadcast to all connected GUI clients so a tray-click can
    // still switch identities and see the dialog state afterwards.
    final originalOnNatWizardTriggered = service.onNatWizardTriggered;
    service.onNatWizardTriggered = () {
      originalOnNatWizardTriggered?.call();
      _broadcastEvent(IpcEvent(
        event: 'nat_wizard_triggered',
        data: const {},
        identityId: identityId,
      ));
    };
    final originalOnNatWizardUserRequested = service.onNatWizardUserRequested;
    service.onNatWizardUserRequested = () {
      originalOnNatWizardUserRequested?.call();
      _broadcastEvent(IpcEvent(
        event: 'nat_wizard_user_requested',
        data: const {},
        identityId: identityId,
      ));
    };

    // Multi-Device (§26): push dedicated event whenever the twin device list
    // changes. GUI listens to refresh the Device Management screen without a
    // full state fetch.
    final originalOnDevicesUpdated = service.onDevicesUpdated;
    service.onDevicesUpdated = () {
      originalOnDevicesUpdated?.call();
      _broadcastEvent(IpcEvent(
        event: 'devices_updated',
        data: {
          'devices': service.devices.map((d) => d.toJson()).toList(),
          'localDeviceId': service.localDeviceId,
        },
        identityId: identityId,
      ));
    };

    // §19.6: push update availability to GUI (desktop: daemon detects, GUI shows banner)
    final originalOnUpdateAvailable = service.onUpdateAvailable;
    service.onUpdateAvailable = (manifest, inNetworkAvailable) {
      originalOnUpdateAvailable?.call(manifest, inNetworkAvailable);
      _broadcastEvent(IpcEvent(
        event: 'update_available',
        data: {
          'manifest': manifest.toJson(),
          'inNetworkAvailable': inNetworkAvailable,
        },
        identityId: identityId,
      ));
    };

    final originalOnUpdateStateChanged = service.onUpdateStateChanged;
    service.onUpdateStateChanged = (state, progress) {
      originalOnUpdateStateChanged?.call(state, progress);
      _broadcastEvent(IpcEvent(
        event: 'update_state_changed',
        data: {
          'state': state.index,
          'progress': progress,
        },
        identityId: identityId,
      ));
    };

    // §7.1 Linked-Device: push event when a pairing request arrives
    final originalOnDevicePairRequest = service.onDevicePairRequest;
    service.onDevicePairRequest = (requestingDeviceIdHex) {
      originalOnDevicePairRequest?.call(requestingDeviceIdHex);
      _broadcastEvent(IpcEvent(
        event: 'device_pair_request',
        data: {'deviceIdHex': requestingDeviceIdHex},
        identityId: identityId,
      ));
    };

    // §7.5: the Primary asks this Linked Device to countersign — either an
    // Emergency Key Rotation or a device-set change. The daemon does NOT
    // decide — it only asks. Without an explicit `approve_rotation` /
    // `reject_rotation` from the user nothing is ever sent back (fail-closed;
    // see _handleRotationApprovalRequest).
    //
    // `approvalKind` and `newDeviceNodeIdHexes` cross the socket with the
    // event because the GUI is the component that phrases the question. An
    // event without them forces the dialog to guess, and the only guess it
    // can make ("key rotation") is wrong for exactly the case the device-set
    // proof was built for.
    final originalOnRotationApprovalRequest = service.onRotationApprovalRequest;
    service.onRotationApprovalRequest =
        (rotationHashHex, requestingDeviceIdHex, kind, newDeviceNodeIdHexes) {
      originalOnRotationApprovalRequest?.call(
          rotationHashHex, requestingDeviceIdHex, kind, newDeviceNodeIdHexes);
      _broadcastEvent(IpcEvent(
        event: 'rotation_approval_request',
        data: {
          'rotationHashHex': rotationHashHex,
          'requestingDeviceIdHex': requestingDeviceIdHex,
          'approvalKind': kind.wireName,
          'newDeviceNodeIdHexes': newDeviceNodeIdHexes,
        },
        identityId: identityId,
      ));
    };
  }

  /// Generate a cryptographically secure 32-char hex token.
  static String _generateToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  void _onClientConnected(Socket socket) {
    // TCP clients (Windows) start unauthenticated — must send auth token first.
    final needsAuth = _authToken != null;
    final client = _ClientState(
      socket: socket,
      activeIdentityId: _defaultIdentityId,
      authenticated: !needsAuth,
    );
    _clients.add(client);
    _log.info('IPC client connected (${_clients.length} total${needsAuth ? ", awaiting auth" : ""})');


    // Catch async write errors (broken pipe, connection reset) that
    // Socket.write() doesn't throw synchronously.
    socket.done.catchError((e) {
      _log.debug('IPC client socket write error: $e');
      _removeClient(client);
    });

    final buffer = StringBuffer();
    client.subscription = socket.cast<List<int>>().transform(utf8.decoder).listen(
      (data) {
        if (client.removed) return;
        buffer.write(data);
        // Process complete lines
        var content = buffer.toString();
        while (content.contains('\n')) {
          final idx = content.indexOf('\n');
          final line = content.substring(0, idx).trim();
          content = content.substring(idx + 1);
          if (line.isNotEmpty) {
            _handleRequest(client, line);
          }
        }
        buffer.clear();
        if (content.isNotEmpty) buffer.write(content);
      },
      onError: (e) {
        _log.debug('IPC client error: $e');
        _removeClient(client);
      },
      onDone: () {
        _log.info('IPC client disconnected');
        _removeClient(client);
      },
    );
  }

  void _removeClient(_ClientState client) {
    if (client.removed) return;
    client.removed = true;
    _clients.remove(client);
    client.subscription?.cancel();
    client.subscription = null;
    try {
      client.socket.destroy();
    } catch (_) {}
  }

  void _handleRequest(_ClientState client, String line) {
    // TCP clients (Windows) must authenticate before sending commands.
    if (!client.authenticated) {
      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        if (json['type'] == 'auth' && json['token'] is String && constantTimeStringEquals(json['token'] as String, _authToken!)) {
          client.authenticated = true;
          _log.info('IPC client authenticated');
          return;
        }
      } catch (_) {}
      _log.warn('IPC client sent invalid auth — disconnecting');
      _removeClient(client);
      return;
    }

    try {
      final msg = parseIpcMessage(line);
      if (msg is IpcRequest) {
        // ── GUI LANGUAGE (V-10-a = b) ───────────────────────────────────
        //
        // Before execution, because the field can be carried by EVERY
        // command and does not hang on a particular one. It is checked
        // here: the value comes from a foreign message, and what the tray
        // does not know is not set — otherwise the state text would stand
        // on a key name after a mangled line.
        final loc = msg.uiLocale;
        if (loc != null && loc != _lastUiLocale && isTrayLanguage(loc)) {
          _lastUiLocale = loc;
          onUiLocale?.call(loc);
        }
        // _dispatchCommand is async — attach error handler to prevent
        // unhandled Future errors that can crash the isolate.
        _dispatchCommand(client, msg).catchError((e, st) {
          _log.error('IPC dispatch error for "${msg.command}": $e');
        });
      } else {
        _log.debug('Unexpected IPC message type from client');
      }
    } catch (e) {
      _log.debug('IPC parse error: $e');
      _sendResponse(client, IpcResponse(id: -1, success: false, error: 'Parse error: $e'));
    }
  }

  /// Parse a category string like 'false_content' to its enum index.
  int? _parseCategoryString(String? s) {
    const map = {
      'not_safe_for_work': 0,
      'false_content': 1,
      'illegal_drugs': 2,
      'illegal_weapons': 3,
      'illegal_csam': 4,
      'illegal_other': 5,
    };
    return s != null ? map[s] : null;
  }

  /// Resolve the target service for a request.
  CleonaService? _resolveService(_ClientState client, IpcRequest req) {
    final targetId = req.identityId ?? client.activeIdentityId;
    return _services[targetId];
  }

  /// Resolve the IdentityManager identity ID for the active client identity.
  String? _resolveIdentityId(_ClientState client, IpcRequest req) {
    final service = _resolveService(client, req);
    if (service == null) return null;
    // Find identity by nodeIdHex
    final identities = IdentityManager().loadIdentities();
    return identities.where((i) => i.nodeIdHex == service.nodeIdHex).firstOrNull?.id;
  }

  Future<void> _dispatchCommand(_ClientState client, IpcRequest req) async {
    onCommandDispatched?.call(req.command);
    try {
      switch (req.command) {
        // ── Identity management commands ─────────────────────────────
        case 'list_identities':
          final guiActiveNodeId = IdentityManager().getActiveIdentity()?.nodeIdHex;
          final identities = _services.entries.map((e) => {
            'identityId': e.key,
            'displayName': e.value.displayName,
            'nodeIdHex': e.value.nodeIdHex,
            'isActive': e.key == client.activeIdentityId,
            'isGuiActive': e.key == guiActiveNodeId,
          }).toList();
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: true,
            data: {'identities': identities},
          ));
          break;

        case 'switch_active':
          final identityId = req.params['identityId'] as String?;
          if (identityId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: identityId'));
            break;
          }
          if (_services.containsKey(identityId)) {
            client.activeIdentityId = identityId;
            final service = _services[identityId]!;
            _log.debug('switch_active displayName="${service.displayName}"');
            _log.info('switch_active OK: ${identityId.substring(0, 8)}');
            _sendResponse(client, IpcResponse(
              id: req.id,
              success: true,
              data: service.getStateSnapshot(),
            ));
          } else {
            _log.warn('switch_active FAIL: ${identityId.substring(0, 8)} '
                'not in services [${_services.keys.map((k) => k.substring(0, 8)).join(", ")}]');
            _sendResponse(client, IpcResponse(
              id: req.id,
              success: false,
              error: 'Unknown identity: $identityId',
            ));
          }
          break;

        case 'create_identity':
          final name = req.params['displayName'] as String?;
          if (name == null || name.isEmpty) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'displayName required'));
            break;
          }
          if (onCreateIdentity == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Not supported'));
            break;
          }
          final newNodeIdHex = await onCreateIdentity!(name);
          if (newNodeIdHex != null) {
            client.activeIdentityId = newNodeIdHex;
            final newService = _services[newNodeIdHex];
            _sendResponse(client, IpcResponse(
              id: req.id,
              success: true,
              data: {
                'identityId': newNodeIdHex,
                if (newService != null) ...newService.getStateSnapshot(),
              },
            ));
          } else {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Create failed'));
          }
          break;

        case 'delete_identity':
          final targetId = req.params['identityId'] as String?;
          if (targetId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'identityId required'));
            break;
          }
          if (_services.length <= 1) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Cannot delete last identity'));
            break;
          }
          if (onDeleteIdentity == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Not supported'));
            break;
          }
          final deleted = await onDeleteIdentity!(targetId);
          if (deleted && client.activeIdentityId == targetId) {
            // Switch to first remaining identity
            client.activeIdentityId = _services.keys.first;
          }
          _sendResponse(client, IpcResponse(id: req.id, success: deleted));
          break;

        case 'set_reduced_mode_session':
          // sec-h5 §8.2 / follow-up task 2026-04-26: GUI splash on Desktop
          // sets reducedMode here; we propagate to every per-identity
          // CleonaService so user-message Send/Receive is gated daemon-side
          // until restart. Per-session, not persisted.
          final enabled = req.params['enabled'];
          if (enabled is! bool) {
            _sendResponse(client, IpcResponse(
              id: req.id, success: false,
              error: 'Missing/invalid bool param: enabled'));
            break;
          }
          for (final service in _services.values) {
            service.reducedMode = enabled;
          }
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'get_state':
          final service = _resolveService(client, req);
          if (service != null) {
            final state = service.getStateSnapshot();
            // Update fields always come from the primary service (the one
            // that owns the BinaryUpdateManager).  Without this, a
            // get_state while the active identity differs from the primary
            // returns updateState=idle, clobbering in-progress GUI state.
            final primarySvc = _services[_defaultIdentityId];
            if (primarySvc != null && primarySvc != service) {
              final primarySnap = primarySvc.getStateSnapshot();
              if (primarySnap.containsKey('updateState')) {
                state['updateState'] = primarySnap['updateState'];
                state['updateProgress'] = primarySnap['updateProgress'];
                state['updateTargetVersion'] = primarySnap['updateTargetVersion'];
              }
              if (primarySnap.containsKey('updateManifest')) {
                state['updateManifest'] = primarySnap['updateManifest'];
              }
            }
            // Add identities list to state
            state['identities'] = _services.entries.map((e) => {
              'identityId': e.key,
              'displayName': e.value.displayName,
              'nodeIdHex': e.value.nodeIdHex,
            }).toList();
            state['activeIdentityId'] = client.activeIdentityId;
            // GUI-global active identity — from IdentityManager (last_profile.json),
            // independent of this IPC connection's routing state.
            final guiActive = IdentityManager().getActiveIdentity();
            state['guiActiveIdentityId'] = guiActive?.nodeIdHex ?? '';
            // Add isAdult and canReviewReports from IdentityManager
            final identityId = _resolveIdentityId(client, req);
            if (identityId != null) {
              final identities = IdentityManager().loadIdentities();
              final identity = identities.where((i) => i.id == identityId).firstOrNull;
              if (identity != null) {
                state['isAdult'] = identity.isAdult;
                state['canReviewReports'] = identity.isAdult ? identity.reviewEnabled : false;
              }
            }
            // Include unread counts for ALL identities (for badge display)
            final unreadPerIdentity = <String, int>{};
            for (final entry in _services.entries) {
              if (entry.key == client.activeIdentityId) continue;
              final total = entry.value.conversations.values
                  .fold<int>(0, (sum, c) => sum + c.unreadCount);
              if (total > 0) unreadPerIdentity[entry.key] = total;
            }
            state['identityUnreadCounts'] = unreadPerIdentity;
            // Network info for QR code generation
            state['localIps'] = service.localIps;
            if (service.publicIp != null) {
              state['publicIp'] = service.publicIp;
              state['publicPort'] = service.publicPort;
            }
            // Welle 5/6: device identity bits for ContactSeed-URI generation
            // (avoids 2D-DHT DeviceKemRecord lookup for First-CR — §8.1.1).
            state['deviceNodeIdHex'] = service.deviceNodeIdHex;
            state['deviceX25519PkB64'] = base64Encode(service.deviceX25519Pk);
            state['deviceMlKemPkB64'] = base64Encode(service.deviceMlKemPk);
            // S368: the trust anchor belongs in here, otherwise a caller
            // cannot build a VALID ContactSeed from this information.
            // `scripts/ci-export-seeds.py` did exactly that until today — it
            // assembled the URI from the fields here and left out `ep`. The
            // seed built that way cannot be recomputed by the other side
            // (§8.1.1) and has been rejected since S368; the contact request
            // on it never went out anyway (the then `sendContactRequest`
            // aborted without `ep`), it just was not visible. S389: that
            // path no longer exists — the request arises when redeeming an
            // invitation card (§15.5) and leaves the device via `sendToUser`
            // (§22.5).
            //
            // Both are PUBLIC keys: they stand as `ep` and `fp` in every
            // ContactSeed this node issues.
            state['userEd25519PkB64'] = base64Encode(service.userEd25519Pk);
            state['foundingEd25519PkB64'] =
                base64Encode(service.foundingEd25519Pk);
            _sendResponse(client, IpcResponse(
              id: req.id,
              success: true,
              data: state,
            ));
          } else {
            _sendResponse(client, IpcResponse(
              id: req.id,
              success: false,
              error: 'No active service',
            ));
          }
          break;

        case 'send_text':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final recipientId = req.params['recipientId'] as String?;
          final text = req.params['text'] as String?;
          if (recipientId == null || text == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: recipientId or text'));
            break;
          }
          // Reply/quote params
          final replyToMessageId = req.params['replyToMessageId'] as String?;
          final replyToText = req.params['replyToText'] as String?;
          final replyToSender = req.params['replyToSender'] as String?;
          // Route to group or DM based on whether recipientId is a group
          final isGroupMsg = service.groups.containsKey(recipientId);
          final result = isGroupMsg
              ? await service.sendGroupTextMessage(recipientId, text, replyToMessageId: replyToMessageId, replyToText: replyToText, replyToSender: replyToSender)
              : await service.sendTextMessage(recipientId, text, replyToMessageId: replyToMessageId, replyToText: replyToText, replyToSender: replyToSender);
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: result != null,
            data: result != null ? {'messageId': result.id} : {},
            error: result == null ? 'Send failed' : null,
          ));
          break;

        case 'set_profile_picture':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final base64Jpeg = req.params['base64Jpeg'] as String?;
          final picResult = await service.setProfilePicture(base64Jpeg);
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: picResult,
            error: picResult ? null : 'Profile picture too large (max 64KB)',
          ));
          break;

        case 'send_media':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final mediaConvId = req.params['conversationId'] as String?;
          final mediaFilePath = req.params['filePath'] as String?;
          if (mediaConvId == null || mediaFilePath == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: conversationId or filePath'));
            break;
          }
          final mediaResult =
              await service.sendMediaMessage(mediaConvId, mediaFilePath);
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: mediaResult != null,
            data: mediaResult != null ? {'messageId': mediaResult.id} : {},
            error: mediaResult == null ? 'Send media failed' : null,
          ));
          break;

        case 'accept_media_download':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final dlConvId = req.params['conversationId'] as String?;
          final dlMsgId = req.params['messageId'] as String?;
          if (dlConvId == null || dlMsgId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: conversationId or messageId'));
            break;
          }
          final dlResult = await service.acceptMediaDownload(dlConvId, dlMsgId);
          _sendResponse(client, IpcResponse(id: req.id, success: dlResult));
          break;

        case 'edit_message':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final editConvId = req.params['conversationId'] as String?;
          final editMsgId = req.params['messageId'] as String?;
          final editNewText = req.params['newText'] as String?;
          if (editConvId == null || editMsgId == null || editNewText == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: conversationId, messageId, or newText'));
            break;
          }
          final editResult = await service.editMessage(editConvId, editMsgId, editNewText);
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: editResult,
            error: editResult ? null : 'Edit failed',
          ));
          break;

        case 'delete_message':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final delConvId = req.params['conversationId'] as String?;
          final delMsgId = req.params['messageId'] as String?;
          if (delConvId == null || delMsgId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: conversationId or messageId'));
            break;
          }
          final delResult = await service.deleteMessage(delConvId, delMsgId);
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: delResult,
            error: delResult ? null : 'Delete failed',
          ));
          break;

        case 'toggle_favorite':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final favConvId = req.params['conversationId'] as String?;
          if (favConvId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: conversationId'));
            break;
          }
          service.toggleFavorite(favConvId);
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'send_typing':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final typingConvId = req.params['conversationId'] as String?;
          if (typingConvId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: conversationId'));
            break;
          }
          service.sendTypingIndicator(typingConvId);
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'mark_read':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final markReadConvId = req.params['conversationId'] as String?;
          if (markReadConvId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: conversationId'));
            break;
          }
          service.markConversationRead(markReadConvId);
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        // S366, stage B: deliver the history of a conversation afterwards.
        //
        // The state that the service sends of its own accord now carries
        // only the MOST RECENT message per conversation — otherwise the
        // serialisation hangs on the whole inventory again, and exactly
        // that is what the switch is meant to get away from. Whoever opens
        // a chat fetches the history here.
        case 'load_history':
          final service = _resolveService(client, req);
          if (service == null) break;
          final histConvId = req.params['conversationId'] as String?;
          if (histConvId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false,
                error: 'Missing param: conversationId'));
            break;
          }
          service.ensureLoaded(histConvId);
          final histConv = service.conversations[histConvId];
          // §21.6/S392-B3: the history comes fresh from the storage, and
          // the storage explicitly does NOT carry the archive state (it is a
          // projection, `messageExtraForStore`). Without this stamp an
          // opened chat would show archived media differently from the same
          // chat in the snapshot.
          if (histConv != null) {
            service.archiveManager?.applyArchiveView(histConv.messages);
          }
          _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
            'conversationId': histConvId,
            'messages':
                histConv?.messages.map((m) => m.toJson()).toList() ?? const [],
          }));
          break;

        case 'forward_message':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final fwdSourceConvId = req.params['sourceConversationId'] as String?;
          final fwdMessageId = req.params['messageId'] as String?;
          final fwdTargetConvId = req.params['targetConversationId'] as String?;
          if (fwdSourceConvId == null || fwdMessageId == null || fwdTargetConvId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: sourceConversationId, messageId, or targetConversationId'));
            break;
          }
          final fwdResult = await service.forwardMessage(fwdSourceConvId, fwdMessageId, fwdTargetConvId);
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: fwdResult != null,
            data: fwdResult != null ? {'messageId': fwdResult.id} : {},
            error: fwdResult == null ? 'Forward failed' : null,
          ));
          break;

        case 'update_chat_config':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final cfgConvId = req.params['conversationId'] as String?;
          if (cfgConvId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: conversationId'));
            break;
          }
          final cfgData = req.params['config'] as Map<String, dynamic>?;
          if (cfgData == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: config'));
            break;
          }
          final chatConfig = ChatConfig.fromJson(cfgData);
          final cfgResult = await service.updateChatConfig(cfgConvId, chatConfig);
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: cfgResult,
            error: cfgResult ? null : 'Config update failed',
          ));
          break;

        case 'update_conversation_notifications':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final notifConvId = req.params['conversationId'] as String?;
          if (notifConvId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: conversationId'));
            break;
          }
          service.updateConversationNotifications(notifConvId,
              enabled: req.params['enabled'] as bool?,
              soundName: req.params['soundName'] as String?);
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'accept_config_proposal':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final acceptCfgConvId = req.params['conversationId'] as String?;
          if (acceptCfgConvId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: conversationId'));
            break;
          }
          final acceptCfgResult = await service.acceptConfigProposal(acceptCfgConvId);
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: acceptCfgResult,
            error: acceptCfgResult ? null : 'No pending proposal',
          ));
          break;

        case 'reject_config_proposal':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final rejectCfgConvId = req.params['conversationId'] as String?;
          if (rejectCfgConvId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: conversationId'));
            break;
          }
          final rejectCfgResult = await service.rejectConfigProposal(rejectCfgConvId);
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: rejectCfgResult,
            error: rejectCfgResult ? null : 'No pending proposal',
          ));
          break;

        // `send_contact_request` has been dropped (S388-BAU-KONTAKT): no
        // caller in the UI, and on V4.2 the request arises when redeeming a
        // card (`invitation_card_redeem_*`, §15.5).

        case 'add_seed_peers':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final targetHex = req.params['targetNodeIdHex'] as String? ?? '';
          final targetAddrs = (req.params['targetAddresses'] as List?)?.cast<String>() ?? [];
          final seedPeersRaw = (req.params['seedPeers'] as List?) ?? [];
          final seedPeers = seedPeersRaw.map((p) {
            final m = p as Map<String, dynamic>;
            return (
              nodeIdHex: m['nodeIdHex'] as String? ?? '',
              addresses: (m['addresses'] as List?)?.cast<String>() ?? <String>[],
            );
          }).toList();
          service.addPeersFromContactSeed(
            targetHex,
            targetAddrs,
            seedPeers,
            targetDeviceIdHex: req.params['targetDeviceIdHex'] as String?,
            targetDxkB64: req.params['targetDxkB64'] as String?,
            targetDmkB64: req.params['targetDmkB64'] as String?,
            targetEpB64: req.params['targetEpB64'] as String?,
          );
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'accept_contact':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final nodeIdHex = req.params['nodeIdHex'] as String?;
          if (nodeIdHex == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: nodeIdHex'));
            break;
          }
          final success = await service.acceptContactRequest(nodeIdHex);
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: success,
          ));
          break;

        case 'delete_contact':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final nodeIdHex = req.params['nodeIdHex'] as String?;
          if (nodeIdHex == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: nodeIdHex'));
            break;
          }
          service.deleteContact(nodeIdHex, source: 'ipc');
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: true,
          ));
          break;

        case 'build_contact_issue_report':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final ciNodeIdHex = req.params['nodeIdHex'] as String?;
          if (ciNodeIdHex == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: nodeIdHex'));
            break;
          }
          final ciReport = await service.buildContactIssueReport(ciNodeIdHex);
          if (ciReport == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Contact not found'));
            break;
          }
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: true,
            data: {'report': ciReport.toJson()},
          ));
          break;

        case 'publish_contact_issue_report':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final pubNodeIdHex = req.params['nodeIdHex'] as String?;
          if (pubNodeIdHex == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: nodeIdHex'));
            break;
          }
          final pubOk = await service.publishContactIssueReport(pubNodeIdHex);
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: pubOk,
          ));
          break;

        case 'build_log_report':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final logReport = await service.buildLogReport();
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: true,
            data: {'report': logReport.toJson()},
          ));
          break;

        case 'publish_log_report':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final logPubOk = await service.publishLogReport();
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: logPubOk,
          ));
          break;

        case 'rename_contact':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final renameNodeIdHex = req.params['nodeIdHex'] as String?;
          if (renameNodeIdHex == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: nodeIdHex'));
            break;
          }
          service.renameContact(
            renameNodeIdHex,
            req.params['localAlias'] as String?,
          );
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        // §15.10 (D2 = a): "never use as a fixed neighbour" — a local mark
        // on the contact; the service hands it to the delivery layer.
        case 'contact_set_never_fixed_neighbour':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final neverContactHex = req.params['nodeIdHex'] as String?;
          final neverValue = req.params['never'] as bool?;
          if (neverContactHex == null || neverValue == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false,
                error: 'Missing param: nodeIdHex or never'));
            break;
          }
          final neverOk =
              service.setContactNeverFixedNeighbour(neverContactHex, neverValue);
          _sendResponse(client, IpcResponse(id: req.id, success: neverOk,
              error: neverOk ? null : 'Contact not found'));
          break;

        // §14.7.4: unilateral, receiver-side. Deliberately NOT routed through
        // the CHAT_CONFIG_UPDATE consent flow (§14.7.1) — a partner must not
        // be able to veto this node's own visibility.
        case 'set_withhold_delivery_status':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final withholdEntityId = req.params['entityIdHex'] as String?;
          final withholdValue = req.params['withhold'] as bool?;
          if (withholdEntityId == null || withholdValue == null) {
            _sendResponse(client, IpcResponse(
                id: req.id, success: false,
                error: 'Missing param: entityIdHex or withhold'));
            break;
          }
          final withholdOk =
              service.setWithholdDeliveryStatus(withholdEntityId, withholdValue);
          _sendResponse(client, IpcResponse(id: req.id, success: withholdOk));
          break;

        // NO VERB FOR A SEND MODE (S389). Here stood `set_secure_mode`.
        // §12.1 allows no per-chat setting of the send path, so the UI
        // does not pass one over the socket either.
        // §24.4.2 — data saver mode. The daemon keeps the state, because
        // the cover stream runs there; the GUI is only the trigger.
        //
        // The answer carries the REASON (`reason`), not merely
        // success/failure: the latch ("a chat is set to High-Secure") must
        // reach the user, otherwise he sees a switch that snaps back
        // without saying why.
        case 'set_data_saver':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final saverOn = req.params['on'] as bool?;
          if (saverOn == null) {
            _sendResponse(client, IpcResponse(
                id: req.id, success: false, error: 'Missing param: on'));
            break;
          }
          final saverReason = service.setDataSaver(saverOn);
          _sendResponse(client, IpcResponse(
              id: req.id,
              success: saverReason == kDataSaverOk,
              data: {
                'reason': saverReason,
                'active': service.dataSaverActive,
                'lockedBySecure': service.dataSaverLockedBySecure,
              }));
          break;

        case 'set_external_records':
          // S388, V4.2 §11.9 — source 4 on/off, ONLY by the user. A device
          // value (the host is one per daemon); every service sets the
          // same switch.
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final externalOn = req.params['on'] as bool?;
          if (externalOn == null) {
            _sendResponse(client, IpcResponse(
                id: req.id, success: false, error: 'Missing param: on'));
            break;
          }
          final externalOk = service.setExternalRecordsEnabled(externalOn);
          _sendResponse(client, IpcResponse(
              id: req.id,
              success: externalOk,
              data: {'enabled': service.externalRecordsEnabled}));
          break;

        case 'set_lan_shaping':
          // S373 — the consent to suspend the cover in the own network.
          // AUTHORITATIVE HERE: the daemon knows its partners and their
          // endpoints, the UI does not.
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final lanSegment = req.params['segment'] as String?;
          final lanGrant = req.params['grant'] as bool?;
          if (lanSegment == null || lanGrant == null) {
            _sendResponse(client, IpcResponse(
                id: req.id, success: false, error: 'Missing param: segment/grant'));
            break;
          }
          final lanOk = lanGrant
              ? service.grantLanShaping(lanSegment)
              : service.revokeLanShaping(lanSegment);
          _sendResponse(client, IpcResponse(
              id: req.id,
              success: lanOk,
              data: {
                'granted': service.lanSegmentConsented(lanSegment),
                'active': service.lanShapingActive,
              }));
          break;

        case 'accept_name_change':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final nameChangeNodeIdHex = req.params['nodeIdHex'] as String?;
          if (nameChangeNodeIdHex == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: nodeIdHex'));
            break;
          }
          service.acceptContactNameChange(
            nameChangeNodeIdHex,
            req.params['accept'] as bool? ?? false,
          );
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'update_display_name':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final newDisplayName = req.params['newName'] as String?;
          if (newDisplayName == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: newName'));
            break;
          }
          service.updateDisplayName(newDisplayName);
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'create_group':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final groupName = req.params['name'] as String?;
          if (groupName == null || groupName.trim().isEmpty) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing or empty param: name'));
            break;
          }
          final memberIds = (req.params['memberIds'] as List<dynamic>?)?.cast<String>() ?? <String>[];
          final groupIdHex = await service.createGroup(groupName, memberIds);
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: groupIdHex != null,
            data: groupIdHex != null ? {'groupIdHex': groupIdHex} : {},
            error: groupIdHex == null ? 'Create group failed' : null,
          ));
          break;

        case 'send_group_text':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final groupId = req.params['groupIdHex'] as String?;
          final groupText = req.params['text'] as String?;
          if (groupId == null || groupText == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: groupIdHex or text'));
            break;
          }
          final groupMsg = await service.sendGroupTextMessage(groupId, groupText,
            replyToMessageId: req.params['replyToMessageId'] as String?,
            replyToText: req.params['replyToText'] as String?,
            replyToSender: req.params['replyToSender'] as String?,
          );
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: groupMsg != null,
            data: groupMsg != null ? {'messageId': groupMsg.id} : {},
            error: groupMsg == null ? 'Send failed' : null,
          ));
          break;

        case 'leave_group':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final leaveGroupId = req.params['groupIdHex'] as String?;
          if (leaveGroupId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: groupIdHex'));
            break;
          }
          final leaveResult = await service.leaveGroup(leaveGroupId);
          _sendResponse(client, IpcResponse(id: req.id, success: leaveResult));
          break;

        case 'invite_to_group':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final invGroupId = req.params['groupIdHex'] as String?;
          final invMemberId = req.params['memberNodeIdHex'] as String?;
          if (invGroupId == null || invMemberId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: groupIdHex or memberNodeIdHex'));
            break;
          }
          final invResult = await service.inviteToGroup(invGroupId, invMemberId);
          _sendResponse(client, IpcResponse(id: req.id, success: invResult));
          break;

        case 'remove_member':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final rmGroupId = req.params['groupIdHex'] as String?;
          final rmMemberId = req.params['memberNodeIdHex'] as String?;
          if (rmGroupId == null || rmMemberId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: groupIdHex or memberNodeIdHex'));
            break;
          }
          final rmResult = await service.removeMemberFromGroup(rmGroupId, rmMemberId);
          _sendResponse(client, IpcResponse(id: req.id, success: rmResult));
          break;

        case 'set_member_role':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final roleGroupId = req.params['groupIdHex'] as String?;
          final roleMemberId = req.params['memberNodeIdHex'] as String?;
          final newRole = req.params['role'] as String?;
          if (roleGroupId == null || roleMemberId == null || newRole == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: groupIdHex, memberNodeIdHex, or role'));
            break;
          }
          final roleResult = await service.setMemberRole(roleGroupId, roleMemberId, newRole);
          _sendResponse(client, IpcResponse(id: req.id, success: roleResult));
          break;

        // ── Channel commands ──────────────────────────────────────
        case 'create_channel':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final chName = req.params['name'] as String?;
          if (chName == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: name'));
            break;
          }
          final subscriberIds = (req.params['subscriberIds'] as List<dynamic>?)?.cast<String>() ?? <String>[];
          final chIsPublic = req.params['isPublic'] as bool? ?? false;
          final chIsAdult = req.params['isAdult'] as bool? ?? true;
          final chLanguage = req.params['language'] as String? ?? 'de';
          final chCategory = req.params['category'] as String? ?? 'general';
          final chDescription = req.params['description'] as String?;
          final chPicture = req.params['pictureBase64'] as String?;
          final channelIdHex = await service.createChannel(chName, subscriberIds,
            isPublic: chIsPublic, isAdult: chIsAdult, language: chLanguage,
            category: chCategory,
            description: chDescription, pictureBase64: chPicture);
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: channelIdHex != null,
            data: channelIdHex != null ? {'channelIdHex': channelIdHex} : {},
            error: channelIdHex == null ? 'Create channel failed' : null,
          ));
          break;

        case 'send_channel_post':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final chPostId = req.params['channelIdHex'] as String?;
          final chPostText = req.params['text'] as String?;
          if (chPostId == null || chPostText == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: channelIdHex or text'));
            break;
          }
          final chPostMsg = await service.sendChannelPost(chPostId, chPostText);
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: chPostMsg != null,
            data: chPostMsg != null ? {'messageId': chPostMsg.id} : {},
            error: chPostMsg == null ? 'Send failed' : null,
          ));
          break;

        case 'leave_channel':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final leaveChId = req.params['channelIdHex'] as String?;
          if (leaveChId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: channelIdHex'));
            break;
          }
          final leaveChResult = await service.leaveChannel(leaveChId);
          _sendResponse(client, IpcResponse(id: req.id, success: leaveChResult));
          break;

        case 'invite_to_channel':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final invChId = req.params['channelIdHex'] as String?;
          final invChMemberId = req.params['memberNodeIdHex'] as String?;
          if (invChId == null || invChMemberId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: channelIdHex or memberNodeIdHex'));
            break;
          }
          final invChResult = await service.inviteToChannel(invChId, invChMemberId);
          _sendResponse(client, IpcResponse(id: req.id, success: invChResult));
          break;

        case 'remove_from_channel':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final rmChId = req.params['channelIdHex'] as String?;
          final rmChMemberId = req.params['memberNodeIdHex'] as String?;
          if (rmChId == null || rmChMemberId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: channelIdHex or memberNodeIdHex'));
            break;
          }
          final rmChResult = await service.removeFromChannel(rmChId, rmChMemberId);
          _sendResponse(client, IpcResponse(id: req.id, success: rmChResult));
          break;

        case 'set_channel_role':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final roleChId = req.params['channelIdHex'] as String?;
          final roleChMemberId = req.params['memberNodeIdHex'] as String?;
          final newChRole = req.params['role'] as String?;
          if (roleChId == null || roleChMemberId == null || newChRole == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: channelIdHex, memberNodeIdHex, or role'));
            break;
          }
          final roleChResult = await service.setChannelRole(roleChId, roleChMemberId, newChRole);
          _sendResponse(client, IpcResponse(id: req.id, success: roleChResult));
          break;

        case 'search_public_channels':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final searchQuery = req.params['query'] as String?;
          final searchLang = req.params['language'] as String?;
          final searchAdult = req.params['includeAdult'] as bool?;
          final searchResults = await service.searchPublicChannels(
            query: searchQuery, language: searchLang, includeAdult: searchAdult);
          _sendResponse(client, IpcResponse(
            id: req.id, success: true,
            data: {'channels': searchResults.map((e) => e.toJson()).toList()},
          ));
          break;

        case 'publish_channel_to_index':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final pubChId = req.params['channelIdHex'] as String?;
          if (pubChId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: channelIdHex'));
            break;
          }
          final pubResult = await service.publishChannelToIndex(pubChId);
          _sendResponse(client, IpcResponse(id: req.id, success: pubResult));
          break;

        case 'join_public_channel':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final joinChId = req.params['channelIdHex'] as String?;
          if (joinChId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: channelIdHex'));
            break;
          }
          final joinResult = await service.joinPublicChannel(joinChId);
          _sendResponse(client, IpcResponse(id: req.id, success: joinResult));
          break;

        // ── Moderation (§9) ──────────────────────────────────
        case 'report_channel':
        case 'report_post':
        case 'submit_jury_vote':
        case 'set_is_adult':
        case 'set_can_review_reports':
        case 'get_moderation_config':
        case 'set_moderation_config':
        case 'get_channel_moderation_info':
        case 'get_jury_requests':
        case 'dismiss_post_report':
        case 'submit_badge_correction':
        case 'contest_csam_hide':
          await _handleModeration(client, req);
          break;

        // ── Calls (§10) ──────────────────────────────────────
        case 'start_call':
        case 'accept_call':
        case 'reject_call':
        case 'hangup':
        case 'get_call_state':
        case 'toggle_mute':
        case 'toggle_speaker':
        case 'start_group_call':
        case 'accept_group_call':
        case 'reject_group_call':
        case 'leave_group_call':
        case 'get_group_call_state':
          await _handleCalls(client, req);
          break;

        case 'get_network_stats':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final stats = service.getNetworkStats();
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: true,
            data: {'stats': stats.toJson()},
          ));
          break;

        case 'nat_wizard_dismiss':
          // §27.9.1 item 5: persist the dismiss timestamp. durationSeconds=0
          // means "Nicht mehr zeigen" (forever), a positive value is a soft
          // dismiss (typically 7d = 604800).
          final svcDismiss = _resolveService(client, req);
          if (svcDismiss == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final durationSeconds =
              (req.params['durationSeconds'] as num?)?.toInt() ?? 0;
          await svcDismiss.dismissNatWizard(durationSeconds: durationSeconds);
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'nat_wizard_recheck':
          // §27.9.2 Step 3: port-mapper reset + 30s direct-connection probe.
          // Blocks up to 30s before returning — the GUI shows a spinner.
          final svcRecheck = _resolveService(client, req);
          if (svcRecheck == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final hasDirect = await svcRecheck.recheckNatWizard();
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: true,
            data: {'hasDirect': hasDirect},
          ));
          break;

        case 'request_nat_wizard':
          // User-initiated (connection-icon tap). Bypasses dismiss-until flag
          // and fires onNatWizardTriggered. Desktop GUI also resets its local
          // `_natWizardShown` latch via bumpNatWizardResetCounter() before
          // sending this, so the wizard dialog actually opens.
          {
            final service = _resolveService(client, req);
            if (service == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
              break;
            }
            service.requestNatWizard();
            _sendResponse(client, IpcResponse(id: req.id, success: true));
          }
          break;

        case 'test_force_nat_wizard_trigger':
          // Test-only (E2E gui-53): bypass the 10-min uptime + network-condition
          // gate and fire the wizard-trigger callback immediately. The GUI-side
          // `_natWizardShown` latch still applies — repeated calls with the
          // latch set are no-ops (tests rely on that for the dismiss-path
          // assertions).
          {
            final service = _resolveService(client, req);
            if (service == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
              break;
            }
            service.testForceNatWizardTrigger();
            _sendResponse(client, IpcResponse(id: req.id, success: true));
          }
          break;

        case 'test_reset_nat_wizard_dismissed':
          // Test-only (E2E gui-53): clear BOTH the service-side
          // `nat_wizard_dismissed_until` flag AND the GUI-side
          // `_natWizardShown` latch in one atomic IPC call.
          {
            final service = _resolveService(client, req);
            if (service == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
              break;
            }
            service.testResetNatWizardDismissed();
            _broadcastEvent(IpcEvent(event: 'gui_action', data: {'action': 'reset_nat_wizard_latch'}));
            _sendResponse(client, IpcResponse(id: req.id, success: true));
          }
          break;

        case 'recover_identities_from_registry':
          {
            final service = _resolveService(client, req);
            if (service == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
              break;
            }
            final created = await service.recoverIdentitiesFromRegistry();
            if (created.isNotEmpty && onRecoveredIdentity != null) {
              for (final id in created) {
                await onRecoveredIdentity!(id);
              }
            }
            _sendResponse(client, IpcResponse(
              id: req.id,
              success: true,
              data: {'count': created.length},
            ));
          }
          break;

        case 'trigger_self_restore_broadcast':
          // Welle 6 §6.3 self-trigger variant: post-restore the daemon
          // already holds the (regenerated, HD-Wallet-derived) User-Sig-Keys
          // identical to the pre-wipe ones, so the GUI can fire-and-forget
          // without re-supplying old-Sk via IPC. oldContacts come from the
          // current `_contacts` registry (populated during the post-restore
          // re-seeding step). Used by the live-verify scaffolding and any
          // future GUI flow where the pre-wipe Sk was not preserved out of
          // process. The legacy `restore_broadcast` case below stays for
          // GUI flows that DO snapshot the pre-wipe Sk.
          {
            final service = _resolveService(client, req);
            if (service == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
              break;
            }
            final ok = await service.sendRestoreBroadcast(
              oldEd25519Sk: service.identity.ed25519SecretKey,
              oldEd25519Pk: service.identity.ed25519PublicKey,
              oldNodeId: service.identity.userId,
              oldContacts: service.acceptedContacts,
              // H-2: deterministic same-seed recovery → re-derived ML-DSA
              // key equals the old one (§6.3.5), so the current secret key
              // is the correct hybrid signer.
              oldMlDsaSk: service.identity.mlDsaSecretKey,
            );
            _sendResponse(client, IpcResponse(id: req.id, success: ok));
          }
          break;

        case 'restore_broadcast':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final oldSkHex = req.params['oldEd25519Sk'] as String?;
          final oldPkHex = req.params['oldEd25519Pk'] as String?;
          final oldNidHex = req.params['oldNodeId'] as String?;
          if (oldSkHex == null || oldPkHex == null || oldNidHex == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: oldEd25519Sk, oldEd25519Pk, or oldNodeId'));
            break;
          }
          final contactsJson = req.params['oldContacts'] as List<dynamic>? ?? <dynamic>[];
          final oldContacts = contactsJson
              .map((c) => ContactInfo.fromJson(c as Map<String, dynamic>))
              .toList();
          // H-2: optional explicit old ML-DSA sk (hex); default to the
          // current re-derived key (identical on deterministic same-seed
          // recovery, §6.3.5).
          final oldMlDsaSkHex = req.params['oldMlDsaSk'] as String?;
          final rbResult = await service.sendRestoreBroadcast(
            oldEd25519Sk: hexToBytes(oldSkHex),
            oldEd25519Pk: hexToBytes(oldPkHex),
            oldNodeId: hexToBytes(oldNidHex),
            oldContacts: oldContacts,
            oldMlDsaSk: oldMlDsaSkHex != null
                ? hexToBytes(oldMlDsaSkHex)
                : service.identity.mlDsaSecretKey,
          );
          _sendResponse(client, IpcResponse(id: req.id, success: rbResult));
          break;

        case 'set_profile_description':
          final descService = _resolveService(client, req);
          if (descService == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final description = req.params['description'] as String?;
          final descResult = await descService.setProfileDescription(description);
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: descResult,
            error: descResult ? null : 'Description too long (max 500 chars)',
          ));
          break;

        case 'set_port':
          final portService = _resolveService(client, req);
          if (portService == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final newPort = req.params['port'] as int?;
          if (newPort == null || newPort < 1024 || newPort > 65535) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Port must be 1024-65535'));
            break;
          }
          // §4.5.2 invariant `nodePort != discoveryPort`: binding the data
          // port on a fixed LAN port makes the data socket and the LAN
          // sockets share it. All of them set SO_REUSEADDR, so the bind
          // succeeds without an error and the kernel then splits inbound
          // datagrams between them — a share of all traffic is dropped
          // silently while sending keeps working, which makes the node look
          // healthy to its peers.
          //
          // S376: BOTH fixed LAN ports are checked via the one place of
          // definition. Until then `== lanDiscoveryPort` stood here, i.e.
          // only the V3 port 41338; 41340, which the V4.1 call sequence
          // really binds, got through.
          if (DataPort.isReservedLanPort(newPort)) {
            _sendResponse(client, IpcResponse(id: req.id, success: false,
                error: 'Port $newPort is reserved for the LAN sockets'));
            break;
          }
          // Browsers refuse this port, so every invitation link built on it
          // would be dead at the recipient — locally, before a request ever
          // reaches this node. English like every other IPC error string:
          // these are protocol diagnostics. The user-facing reason lives in
          // the port dialog (`port_browser_blocked`), because setPort only
          // returns a bare bool and this text never reaches the GUI.
          if (IdentityManager.isBrowserBlockedPort(newPort)) {
            _sendResponse(client, IpcResponse(id: req.id, success: false,
                error: 'Port $newPort is refused by browsers — invitation '
                    'links would be dead for every recipient'));
            break;
          }
          // ── RE-HUNG ONTO THE SERVICE ON 2026-08-31 (CUT) ───────────
          //
          // Here stood `portService.node.changePort(newPort)` plus its own
          // persistence (`IdentityManager().updatePort`). The IPC server
          // thereby reached directly into the node BYPASSING THE SERVICE —
          // exactly the seam that AP-1 step 7 closed, and
          // `CleonaService.node` has not existed since the V3 cut.
          //
          // `ServiceInterface.setPort` does the same and more: it checks
          // both port rules once more (§4.5.2 LAN discovery,
          // browser-blocked ports), updates `identities.json` and reports
          // the state change. The in-process path of Android and iOS
          // already takes it anyway (`cleona_service.dart:5342`).
          //
          // THE GAP DOES NOT THEREBY GO AWAY, IT MOVES TO ITS PLACE:
          // `setPort` internally calls `node.changePort` and thus remains
          // open in `cleona_service.dart`. The V4.1 delivery layer knows no
          // port change at runtime — `V41Node.start` takes the port once.
          // The information about that belongs in ONE place, not in two.
          final ok = await portService.setPort(newPort);
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: ok,
            data: ok ? {'port': newPort} : const <String, dynamic>{},
            error: ok ? null : 'Port $newPort unavailable',
          ));
          break;

        case 'update_media_settings':
          final msService = _resolveService(client, req);
          if (msService == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          msService.updateMediaSettings(MediaSettings.fromJson(req.params));
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'set_multi_interface_mode':
          final miService = _resolveService(client, req);
          if (miService == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final mode = MultiInterfaceMode.modeFromString(req.params['mode'] as String?);
          await miService.setMultiInterfaceMode(mode);
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'update_notification_settings':
          final nsService = _resolveService(client, req);
          if (nsService == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          nsService.notificationSound.updateSettings(
            NotificationSettings.fromJson(req.params),
          );
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'preview_ringtone':
          final prService = _resolveService(client, req);
          if (prService == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final rtName = req.params['ringtone'] as String? ?? 'gentle';
          prService.notificationSound.previewRingtone(Ringtone.fromName(rtName));
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'stop_ringtone_preview':
          final spService = _resolveService(client, req);
          if (spService == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          spService.notificationSound.stopPreview();
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'setup_guardians':
          final gService = _resolveService(client, req);
          if (gService == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final guardianIds = (req.params['guardianNodeIds'] as List<dynamic>?)?.cast<String>() ?? <String>[];
          final gResult = await gService.setupGuardians(guardianIds);
          _sendResponse(client, IpcResponse(id: req.id, success: gResult));
          break;

        case 'trigger_guardian_restore':
          final trService = _resolveService(client, req);
          if (trService == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final trNodeIdHex = req.params['contactNodeIdHex'] as String?;
          if (trNodeIdHex == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: contactNodeIdHex'));
            break;
          }
          final qrData = await trService.triggerGuardianRestore(trNodeIdHex);
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: qrData != null,
            data: qrData ?? {},
          ));
          break;

        case 'confirm_guardian_restore':
          final crService = _resolveService(client, req);
          if (crService == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final crOwnerHex = req.params['ownerNodeIdHex'] as String?;
          final crMailboxHex = req.params['recoveryMailboxIdHex'] as String?;
          if (crOwnerHex == null || crMailboxHex == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: ownerNodeIdHex or recoveryMailboxIdHex'));
            break;
          }
          final crResult = await crService.confirmGuardianRestore(crOwnerHex, crMailboxHex);
          _sendResponse(client, IpcResponse(id: req.id, success: crResult));
          break;

        case 'ping':
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: true,
            data: {'pong': true},
          ));
          break;

        case 'gui_action':
          _broadcastEvent(IpcEvent(event: 'gui_action', data: req.params));
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        // ── v3.1.26 Features ──────────────────────────────────────────

        case 'send_reaction':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final reactConvId = req.params['conversationId'] as String?;
          final reactMsgId = req.params['messageId'] as String?;
          final reactEmoji = req.params['emoji'] as String?;
          final reactRemove = req.params['remove'] as bool? ?? false;
          if (reactConvId == null || reactMsgId == null || reactEmoji == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param'));
            break;
          }
          await service.sendReaction(
            conversationId: reactConvId,
            messageId: reactMsgId,
            emoji: reactEmoji,
            remove: reactRemove,
          );
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'add_manual_peer':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final peerIp = req.params['ip'] as String? ?? '';
          final peerPort = req.params['port'] as int? ?? 0;
          final peerResult = service.addManualPeer(peerIp, peerPort);
          _sendResponse(client, IpcResponse(id: req.id, success: peerResult));
          break;

        // ── Feature ②: Manual Reconnect (§12.3.1) ────────────────────────────
        case 'manual_reconnect':
          {
            final service = _resolveService(client, req);
            if (service == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
              break;
            }
            // Debounce: reuse §5.10.5 Re-Discovery cooldown (60 s ≥ spec minimum 10 s).
            final now = DateTime.now();
            final last = _lastManualReconnect;
            if (last != null && now.difference(last) < _manualReconnectCooldown) {
              final remaining = _manualReconnectCooldown.inSeconds - now.difference(last).inSeconds;
              _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
                'debounced': true,
                'remainingSeconds': remaining,
                'peersFound': 0,
              }));
              break;
            }
            _lastManualReconnect = now;
            // Trigger the full §12.3 recovery sequence via onNetworkChanged(force:true).
            unawaited(service.onNetworkChanged(force: true));
            final peerCount = service.peerCount;
            _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
              'debounced': false,
              'peersFound': peerCount,
            }));
          }
          break;

        // ── Feature ③: Peer Rescue Bundle export (§8.1.2) ────────────────────
        case 'export_peer_bundle':
          {
            final service = _resolveService(client, req);
            if (service == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
              break;
            }
            try {
              final identity = service.identity;
              final summaries = service.peerSummaries;

              // Select peers: inbound-reachable (have public address) first,
              // then the rest — up to PeerRescueBundle.maxPeers.
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

              _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
                'bundleBase64': base64.encode(bytes),
                'uri': uri,
                'peerCount': selected.length,
                'createdAtMs': bundle.createdAt.millisecondsSinceEpoch,
              }));
            } catch (e) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'export_peer_bundle: $e'));
            }
          }
          break;

        // ── Feature ③: Peer Rescue Bundle import (§8.1.2) ────────────────────
        case 'import_peer_bundle':
          {
            final service = _resolveService(client, req);
            if (service == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
              break;
            }
            try {
              // Accept either raw Base64-encoded bytes or a URI string.
              final uriParam = req.params['uri'] as String?;
              final b64Param = req.params['bundleBase64'] as String?;

              PeerRescueBundleParseResult result;
              if (uriParam != null) {
                result = PeerRescueBundle.parseUriAndValidate(uriParam);
              } else if (b64Param != null) {
                final bytes = base64.decode(b64Param);
                result = PeerRescueBundle.parseAndValidate(bytes);
              } else {
                _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing uri or bundleBase64 param'));
                break;
              }

              if (!result.networkTagValid) {
                _sendResponse(client, IpcResponse(id: req.id, success: false, data: {
                  'networkTagValid': false,
                  'error': result.errorMessage ?? 'Network tag mismatch',
                }));
                break;
              }

              final bundle = result.bundle!;

              // Contact peer addresses from the bundle and enter §12.3 recovery.
              var contacted = 0;
              for (final peer in bundle.peers) {
                for (final addr in peer.addresses) {
                  final parts = _splitHostPort(addr);
                  if (parts != null) {
                    service.addManualPeer(parts.$1, parts.$2);
                    contacted++;
                  }
                }
              }

              // Trigger recovery sequence if we haven't done so too recently.
              final now = DateTime.now();
              final last = _lastManualReconnect;
              if (last == null || now.difference(last) >= _manualReconnectCooldown) {
                _lastManualReconnect = now;
                unawaited(service.onNetworkChanged(force: true));
              }

              _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
                'networkTagValid': true,
                'sigValid': result.sigValid,
                'sigUnknownExporter': result.sigUnknownExporter,
                'ageHours': result.ageHours,
                'peerCount': bundle.peers.length,
                'peersContacted': contacted,
                'exporterDeviceIdHex': bytesToHex(bundle.exporterDeviceId),
                'createdAtMs': bundle.createdAt.millisecondsSinceEpoch,
              }));
            } catch (e) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'import_peer_bundle: $e'));
            }
          }
          break;

        case 'get_verification_level':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final verNodeIdHex = req.params['nodeIdHex'] as String?;
          if (verNodeIdHex == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: nodeIdHex'));
            break;
          }
          final verContact = service.getContact(verNodeIdHex);
          _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
            'level': verContact?.verificationLevel ?? 'unverified',
          }));
          break;

        case 'set_verification_level':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final setVerNodeIdHex = req.params['nodeIdHex'] as String?;
          final setVerLevel = req.params['level'] as String?;
          if (setVerNodeIdHex == null || setVerLevel == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param'));
            break;
          }
          final setVerContact = service.getContact(setVerNodeIdHex);
          if (setVerContact == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Contact not found'));
            break;
          }
          const validLevels = ['unverified', 'seen', 'verified', 'trusted'];
          if (!validLevels.contains(setVerLevel)) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Invalid level: $setVerLevel'));
            break;
          }
          setVerContact.verificationLevel = setVerLevel;
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        // ── `get_reputation` IS GONE (2026-08-31, CUT) ──────────────
        //
        // The command read `CleonaService.reputationOf(nodeIdHex)` and
        // returned score, good/bad counters and ban state of a node. The
        // carrier lay in `cleona_service_v3_retire.dart:79` and was deleted
        // with the V3 cut; it counted events that exist only in V3
        // (packet violations on the UDP wire, relay abuse, network ban
        // list, DoS layer 3 of 5).
        //
        // NO REPLACEMENT, AND THAT IS INTENDED: v4_1 §10 relies against
        // Sybil on redundancy m=3 and the KEX gate, not on a reputation
        // number per foreign node — "the leverage against Sybil is
        // redundancy m=3 and the KEX gate, not PoW" (§10). §10 names a
        // weighted relay reputation as a draft, it is not built, and the
        // OLD counter would be no replacement for it.
        //
        // THE COMMAND IS NOT REPLACED BY A DUMMY: it drops out entirely and
        // thus runs into the `default` branch -> "Unknown command".
        // Callers, measured 2026-08-31: `test/e2e/lib/ipc-client.ts:1312`.
        // The test then fails loudly, and that is the right message.
        case 'get_rate_limiter_stats':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
            'droppedPackets': service.droppedPackets,
          }));
          break;

        case 'archive_status':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          // S394: plus share identity and narrowing (§21.6) — the path on
          // which a mismatch reaches the surface. No password, no full pin.
          _sendResponse(client, IpcResponse(id: req.id, success: true,
              data: service.archiveShareStatus()));
          break;

        case 'archive_rebind_share':
        case 'archive_capture_network':
        case 'archive_clear_networks':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          if (req.command == 'archive_capture_network') {
            final n = await service.captureArchiveNetwork();
            _sendResponse(client, IpcResponse(id: req.id, success: n != null,
                data: n ?? const {}, error: n == null ? 'No IPv4 network' : null));
          } else {
            final ok = req.command == 'archive_rebind_share'
                ? await service.rebindArchiveShare()
                : await service.clearArchiveNetworks();
            _sendResponse(client, IpcResponse(id: req.id, success: ok));
          }
          break;

        case 'archive_test_connection':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          try {
            // S366: from the area `archive_config` of the storage instead of
            // from `archive_config.json`. The call runs in the DAEMON, i.e.
            // where the storage and its key lie.
            //
            // THE PASSWORD STAYS HERE. It goes into `transport.connect` and
            // from there into an environment variable of the helper process;
            // the answer below carries `reachable`, `protocol` and `host`
            // — not a word of it. That is intent and not carelessness: the
            // archive password does not cross the IPC boundary.
            final config = ArchiveConfig.readFrom(service.store);
            if (config == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No archive config'));
              break;
            }
            if (config.archiveHost.isEmpty) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No host configured'));
              break;
            }
            // S394: a pinned share is identified before it is tested
            // (§21.6) — see `testArchiveConnection`.
            final r = await testArchiveConnection(config,
                profileDir: service.profileDir);
            final ok = r.reachable;
            _sendResponse(client, IpcResponse(id: req.id, success: ok, data: {
              'reachable': ok,
              'identity': r.identity?.name,
              'protocol': config.defaultProtocol.name,
              'host': config.archiveHost,
            }));
          } catch (e) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'archive_test_connection: $e'));
          }
          break;

        case 'archive_trigger_check':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final mgr = service.archiveManager;
          if (mgr == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Archive not active'));
            break;
          }
          // The archive run looks for archivable media by AGE — it needs
          // every message, not the most recent one (S366, stage B). Without
          // this call it would find practically nothing any more, and
          // silently: "no archivable media" looks exactly like "found
          // nothing, because nothing was loaded".
          service.ensureAllLoaded();
          final result = await mgr.runArchiveCheck(conversations: service.conversations);
          _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
            'archived': result.archived,
            'failed': result.failed,
            'tierChecked': result.tierChecked,
            'evicted': result.evicted,
            'skippedReason': result.skippedReason,
          }));
          break;

        // ── Retrieval of an archived attachment (§21.6) ────────────
        //
        // FROM THE SHARE, NEVER VIA THE NETWORK. §21.6, touch point 3:
        // "archive placeholders fetch from the **share**, never from the
        // network." The only way out is the manager's `ArchiveTransport`
        // — SMB/SFTP/FTPS/HTTP to the NAS in the home network. This branch
        // calls neither `sendToUser()` (the seam, §22.5) nor anything from
        // `mycelium/`; a retrieval produces no packet, no receipt and no post
        // box entry.
        //
        // THE ANSWER IS NOT THE RESULT. Over SMB a large file can take
        // minutes (`ArchiveTransport.downloadTimeout` stands at ~34 min).
        // If this waited for the end, the answer would block the command
        // stream of EXACTLY THIS client until the download is through —
        // the UI would be frozen. The answer therefore only says whether a
        // fetch IS RUNNING; the progress comes as the event
        // `archive_retrieve_progress`, the end as `archive_retrieve_done`.
        //
        // TAPPED TWICE = ONE FETCH. The binding latch sits in the manager
        // (`retrieveToMediaStore`, one entry per message in `_retrievals`);
        // `isRetrieving` here only colours the answer and decides nothing.
        case 'archive_retrieve':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final mgr = service.archiveManager;
          if (mgr == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Archive not active'));
            break;
          }
          final retrieveId = req.params['messageId'] as String?;
          if (retrieveId == null || retrieveId.isEmpty) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: messageId'));
            break;
          }
          // The target is the path the MESSAGE points to. It stays when the
          // archive removes the original — `filePath` is the identifier of
          // the attachment, not the statement "lies here"
          // (`media_store.dart`, S362). A second path from the archive entry
          // would be a second truth about the same attachment; there is
          // exactly one.
          //
          // `ensureAllLoaded` for the same reason as with
          // `archive_trigger_check`: what is sought is an OLD message, and
          // without loading the loop would silently find nothing.
          service.ensureAllLoaded();
          String? retrievePath;
          for (final conv in service.conversations.values) {
            for (final m in conv.messages) {
              if (m.id == retrieveId) {
                retrievePath = m.filePath;
                break;
              }
            }
            if (retrievePath != null) break;
          }
          if (retrievePath == null || retrievePath.isEmpty) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No local path for message $retrieveId'));
            break;
          }
          final retrieveIdentity = service.nodeIdHex;
          // The question is asked BEFORE the call, and only to colour the
          // answer. The call itself ALWAYS goes out — otherwise
          // `isRetrieving` would be the actual latch and the one in the
          // manager mere decoration. A mutation test showed exactly that:
          // with the latch in the manager taken out the suite stayed green,
          // because here there was no second call in the first place.
          final retrieveRunning = mgr.isRetrieving(retrieveId);
          final retrieveRun = mgr.retrieveToMediaStore(
            retrieveId,
            retrievePath,
            onProgress: (mid, sent, total) {
              _broadcastEvent(IpcEvent(
                event: 'archive_retrieve_progress',
                identityId: retrieveIdentity,
                data: {
                  'messageId': mid,
                  'bytesTransferred': sent,
                  'totalBytes': total,
                },
              ));
            },
          );
          // The completion event hangs only on the FIRST requester. Both
          // get the same future; attached twice would mean reported twice,
          // and the UI would count one operation double.
          if (!retrieveRunning) {
            unawaited(retrieveRun.then((r) {
              _broadcastEvent(IpcEvent(
                event: 'archive_retrieve_done',
                identityId: retrieveIdentity,
                data: r.toJson(),
              ));
            }));
          }
          _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
            'messageId': retrieveId,
            'started': !retrieveRunning,
            'alreadyRunning': retrieveRunning,
          }));
          break;

        // ── Multi-Device (§26) ─────────────────────────────────────────

        case 'list_devices':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: true,
            data: {
              'devices': service.devices.map((d) => d.toJson()).toList(),
              'localDeviceId': service.localDeviceId,
            },
          ));
          break;

        case 'rename_device':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final deviceId = req.params['deviceId'] as String?;
          final newName = req.params['newName'] as String?;
          if (deviceId == null || newName == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: deviceId or newName'));
            break;
          }
          service.renameDevice(deviceId, newName);
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'revoke_device':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final revokeDeviceId = req.params['deviceId'] as String?;
          if (revokeDeviceId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: deviceId'));
            break;
          }
          final revoked = await service.revokeDevice(revokeDeviceId);
          _sendResponse(client, IpcResponse(id: req.id, success: revoked));
          break;

        case 'approve_device_pair':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final pairDeviceId = req.params['deviceIdHex'] as String?;
          if (pairDeviceId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: deviceIdHex'));
            break;
          }
          final approved = await service.approvePairRequest(pairDeviceId);
          _sendResponse(client, IpcResponse(id: req.id, success: approved));
          break;

        case 'get_linked_device_status':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final isLinked = service.identity.isLinkedDevice;
          final ldKeys = service.identity.linkedDeviceKeys;
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: true,
            data: {
              'isLinkedDevice': isLinked,
              if (isLinked && ldKeys != null) ...{
                'capabilities': ldKeys.delegationCert.capabilities,
                'issuedAtMs': ldKeys.delegationCert.issuedAtMs,
                'maxValidUntilMs': ldKeys.delegationCert.maxValidUntilMs,
                'isExpired': ldKeys.delegationCert.isExpired(),
              },
            },
          ));
          break;

        case 'send_device_pair_request':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final pairSent = await service.sendDevicePairRequest();
          _sendResponse(client, IpcResponse(id: req.id, success: pairSent));
          break;

        // §7.5: explicit user decision on a pending rotation-approval
        // request. These two commands are the ONLY way a Device-Sig
        // countersignature (or a rejection) is ever produced — the daemon
        // never decides on its own, and a timeout decides nothing either.
        case 'approve_rotation':
        case 'reject_rotation':
          {
            final service = _resolveService(client, req);
            if (service == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
              break;
            }
            final rotationHashHex = req.params['rotationHashHex'] as String?;
            if (rotationHashHex == null || rotationHashHex.isEmpty) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'rotationHashHex required'));
              break;
            }
            final ok = req.command == 'approve_rotation'
                ? await service.approveRotation(rotationHashHex)
                : await service.rejectRotation(rotationHashHex);
            _sendResponse(client, IpcResponse(
              id: req.id,
              success: ok,
              error: ok ? null : 'Unknown or expired rotation request',
            ));
          }
          break;

        // §7.5: catch-up for rotation-approval requests. The
        // `onRotationApprovalRequest` event fires once and is lost on a GUI
        // that starts or reconnects after it — without this the request
        // expires without the user ever being asked. Expired entries are
        // filtered service-side.
        case 'get_pending_rotation_approvals':
          {
            final service = _resolveService(client, req);
            if (service == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
              break;
            }
            final pending = await service.getPendingRotationApprovals();
            _sendResponse(client, IpcResponse(
              id: req.id,
              success: true,
              data: {'pendingRotationApprovals': pending},
            ));
          }
          break;

        // §7.1 LD-2: catch-up for pending device-pairing requests. The
        // `device_pair_request` event fires once and is lost on a GUI that
        // starts or reconnects after it — without this the Primary has no
        // way to show the request as pending until the requester asks again.
        case 'get_pending_pair_requests':
          {
            final service = _resolveService(client, req);
            if (service == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
              break;
            }
            final pending = await service.getPendingPairRequests();
            _sendResponse(client, IpcResponse(
              id: req.id,
              success: true,
              data: {'pendingPairRequests': pending},
            ));
          }
          break;

        case 'rotate_identity_keys':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          // Fire-and-forget: PQ keygen runs in background isolate.
          // Respond immediately — rotation completes asynchronously.
          service.rotateIdentityKeys();
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'test_key_rotation_state':
          {
            final service = _resolveService(client, req);
            if (service == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
              break;
            }
            final data = service.testGetKeyRotationRetryState();
            _sendResponse(client, IpcResponse(id: req.id, success: true, data: data));
          }
          break;

        case 'test_key_rotation_force_retry':
          {
            final service = _resolveService(client, req);
            if (service == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
              break;
            }
            service.testForceKeyRotationRetry();
            _sendResponse(client, IpcResponse(id: req.id, success: true));
          }
          break;

        case 'test_inject_device':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final testDeviceId = req.params['deviceId'] as String?;
          final testDeviceName = req.params['name'] as String? ?? 'TestDevice';
          final testPlatform = req.params['platform'] as String? ?? 'linux';
          if (testDeviceId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: deviceId'));
            break;
          }
          service.injectTestDevice(testDeviceId, testDeviceName, testPlatform);
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'test_play_message_sound':
          final svcSound = _resolveService(client, req);
          if (svcSound == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          // Use sync variant: awaits the pw-play/paplay process exit so the
          // test can verify actual playback from the exit code (message.ogg is
          // only 280ms — too short for process-polling in the test).
          final exitCode = await svcSound.notificationSound.playMessageSoundSync();
          _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
            'exitCode': exitCode,
          }));
          break;

        case 'get_seed_phrase':
          final now = DateTime.now();
          if (_lastSeedPhraseAccess != null &&
              now.difference(_lastSeedPhraseAccess!).inSeconds < 10) {
            _log.warn('get_seed_phrase rate-limited');
            _sendResponse(client, IpcResponse(
                id: req.id, success: false, error: 'Rate limited — wait 10s'));
            break;
          }
          _lastSeedPhraseAccess = now;
          _log.warn('get_seed_phrase accessed');
          // `ipcParentDir`, NOT `lastIndexOf(isWindows ? '\\' : '/')`
          // (13a, S370). The Windows socket path is MIXED — measured on
          // 06.09.2026 in the production log of the build VM:
          //   `[daemon] Dienst gestartet. Socket: C:\Users\Cleona/.cleona/cleona.sock`
          // The old computation hit the backslash before `Cleona` and gave
          // `C:\Users`. `IdentityManager` then looked for the 24 words in
          // `C:\Users\seed_phrase.json` — i.e. nowhere, while
          // `C:\Users\Cleona\.cleona\seed_phrase.json.enc` lay right next to
          // it. The keyring path above (`loadSeedPhrase`, first half) stayed
          // intact; what was broken was the FILE FALLBACK, and that exists
          // precisely for the case that DPAPI does not open.
          final cleonaDir = ipcParentDir(socketPath);
          final identityMgr = IdentityManager(baseDir: cleonaDir);
          final words = identityMgr.loadSeedPhrase();
          if (words == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No seed phrase stored'));
            break;
          }
          _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
            'words': words,
          }));
          break;

        // ── Calendar (§23) ───────────────────────────────────
        case 'calendar_create_event':
        case 'calendar_update_event':
        case 'calendar_delete_event':
        case 'calendar_list_events':
        case 'calendar_list_tasks':
        case 'calendar_list_birthdays':
        case 'calendar_send_rsvp':
        case 'calendar_query_free_busy':
        case 'calendar_get_free_busy_settings':
        case 'calendar_set_free_busy_settings':
        case 'calendar_sync_status':
        case 'calendar_sync_trigger':
        case 'calendar_sync_configure_caldav':
        case 'calendar_sync_caldav_list_calendars':
        case 'calendar_sync_remove_caldav':
        case 'calendar_sync_google_oauth_start':
        case 'calendar_sync_remove_google':
        case 'calendar_sync_configure_exchange':
        case 'calendar_sync_exchange_oauth_start':
        case 'calendar_sync_remove_exchange':
        case 'calendar_sync_ews_autodiscover':
        case 'calendar_sync_configure_local_ics':
        case 'calendar_sync_remove_local_ics':
        case 'calendar_sync_list_conflicts':
        case 'calendar_sync_clear_conflicts':
        case 'calendar_sync_restore_conflict':
        case 'calendar_sync_resolve_pending':
        case 'caldav_server_state':
        case 'caldav_server_set_enabled':
        case 'caldav_server_regenerate_token':
        case 'caldav_server_set_port':
        case 'calendar_sync_set_foreground':
        case 'contact_set_birthday':
          await _handleCalendar(client, req);
          break;

        // ── Polls (§24) ──────────────────────────────────────
        case 'poll_create':
        case 'poll_vote':
        case 'poll_vote_anonymous':
        case 'poll_vote_revoke':
        case 'poll_update':
        case 'poll_list':
        case 'poll_convert_to_event':
          await _handlePolls(client, req);
          break;

        // ── §19.6 In-network update ─────────────────────────
        //
        // ── `seed_binary` IS BACK (02.09.2026) ────────────────
        //
        // Since the CUT (2026-08-31) here stood the reasoning why the
        // command had been dropped without replacement: its body had lain
        // in `cleona_service_v3_binary.dart`, the successor was the unbuilt
        // fountain content layer (AP-7), "WITHOUT REPLACEMENT UNTIL AP-7".
        //
        // RE-MEASURED ON 02.09.2026 — THE PREMISE WAS NOT RIGHT.
        // The file fell, but its local halves did NOT disappear with the
        // CUT: they lie in `cleona_service_pure.dart` ("§19.6 binary
        // distribution: the local halves", explicitly rescued as a CUT
        // addendum). The encoding path `_runSeedIsolate` ->
        // `_selfSeedInIsolate` stands in `cleona_service.dart`, the
        // fragment store is built on every start
        // (`cleona_service_update.dart:485`), and `_selfSeedCurrentBinary`
        // takes exactly this path at start. So only the public entry with a
        // freely named file was missing — that has been restored.
        //
        // THE WAY OUT IS ALIVE TOO. The announcement runs via
        // `BinaryRendezvousManager` (`cleona_service_update.dart:562`) and
        // thus via Nostr, the explicit exception of the CUT decision. What
        // AP-7 will replace in future is the fountain path for the contents
        // themselves, not this command.
        //
        // `export_binary` stands next to it and was NEVER a CUT decision: it
        // disappeared on 08.07.2026 in `1d8e29de` during the move of this
        // whole block, while the same diff took `seed_binary` along —
        // collateral damage of a relocation, without a word in the commit
        // message, while its carrier `PhysicalTransferHelper.exportBinary`
        // stayed untouched.

        case 'seed_binary':
        case 'export_binary':
        case 'get_seeded_platforms':
        case 'reload_manifest':
        case 'get_update_status':
        case 'start_in_network_update':
        case 'apply_update':
        // AP-5a: the invite link embeds the signed binary hashes from the
        // update manifest, so it belongs to the §19.6 group.
        case 'generate_invite_link_url':
        case 'issue_invitation':
        // ── THE INVITATION CARD (§15.2/§15.3) — ADDED S391 ──────
        //
        // These six were fully IMPLEMENTED in `_handlePolls` and never
        // ROUTED here. The dispatcher did not know them and answered with
        // "Unknown command"; `ipc_client.dart:2199-2201` maps every
        // `success: false` to `notConnected`, and the UI showed
        // "Einladungen sind in dieser Version noch nicht angeschlossen"
        // (`card_not_connected`).
        //
        // Thus on EVERY daemon platform — Linux, Windows, macOS — no
        // invitation could be issued since the card has existed (S387).
        // Android and iOS were never affected: there the service runs in
        // the same process, the UI calls `CleonaService` directly and does
        // not pass this dispatcher at all.
        //
        // Measured on 17.09.2026 on Node2 against the current build
        // (SHA f2bc46f4, identical to the local one):
        //   {"success": false, "error": "Unknown command: invitation_card_issue"}
        case 'invitation_card_issue':
        case 'invitation_card_redeem_text':
        case 'invitation_card_redeem_bytes':
        case 'invitation_card_standing':
        case 'invitation_card_revoke':
        case 'invitation_card_revoke_all':
        // The same gap, two commands older: `ipc_client.dart:2157` and
        // `:2176` both send, `_handlePolls` implements both
        // (`:4491`, `:4517`), neither was routed. Found by
        // `scripts/check_ipc_dispatch_reachable.dart`, not by hand —
        // the gate found it in the same run in which it was built.
        case 'list_open_invitations':
        case 'revoke_invitation':
          await _handlePolls(client, req);
          break;

        default:
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: false,
            error: 'Unknown command: ${req.command}',
          ));
      }
    } catch (e, st) {
      _log.error('IPC command "${req.command}" failed: $e\n$st');
      _sendResponse(client, IpcResponse(
        id: req.id,
        success: false,
        error: '$e',
      ));
    }
  }


  Future<void> _handleModeration(_ClientState client, IpcRequest req) async {
    switch (req.command) {
        case 'report_channel':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final rptChId = req.params['channelIdHex'] as String?;
          final rptCatRaw = req.params['category'];
          final rptCat = rptCatRaw is int ? rptCatRaw : _parseCategoryString(rptCatRaw as String?);
          final rptEvidence = (req.params['evidencePostIds'] as List<dynamic>?)?.cast<String>() ?? [];
          final rptDesc = req.params['description'] as String?;
          if (rptChId == null || rptCat == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing params: channelIdHex or category'));
            break;
          }
          final rptResult = await service.reportChannel(rptChId, rptCat, rptEvidence, description: rptDesc);
          _sendResponse(client, IpcResponse(id: req.id, success: rptResult));
          break;

        case 'report_post':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final rptpChId = req.params['channelIdHex'] as String?;
          final rptpPostId = req.params['postId'] as String?;
          final rptpCatRaw = req.params['category'];
          final rptpCat = rptpCatRaw is int ? rptpCatRaw : _parseCategoryString(rptpCatRaw as String?);
          final rptpDesc = req.params['description'] as String?;
          if (rptpChId == null || rptpPostId == null || rptpCat == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing params: channelIdHex, postId, or category'));
            break;
          }
          final rptpResult = await service.reportPost(rptpChId, rptpPostId, rptpCat, description: rptpDesc);
          _sendResponse(client, IpcResponse(id: req.id, success: rptpResult));
          break;

        case 'submit_jury_vote':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final voteJuryId = req.params['juryId'] as String?;
          final voteReportId = req.params['reportId'] as String?;
          final voteValue = req.params['vote'] as int?;
          final voteReason = req.params['reason'] as String?;
          if (voteJuryId == null || voteReportId == null || voteValue == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing params: juryId, reportId, or vote'));
            break;
          }
          final voteResult = await service.submitJuryVote(voteJuryId, voteReportId, voteValue, reason: voteReason);
          _sendResponse(client, IpcResponse(id: req.id, success: voteResult));
          break;

        case 'set_is_adult':
          final identityId = _resolveIdentityId(client, req);
          if (identityId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active identity'));
            break;
          }
          final isAdultVal = req.params['value'] as bool? ?? false;
          IdentityManager().setIsAdult(identityId, isAdultVal);
          // Propagate to runtime IdentityContext
          final adultService = _resolveService(client, req);
          if (adultService != null) {
            adultService.identity.isAdult = isAdultVal;
          }
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'set_can_review_reports':
          final identityId = _resolveIdentityId(client, req);
          if (identityId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active identity'));
            break;
          }
          final reviewVal = req.params['value'] as bool? ?? true;
          IdentityManager().setReviewEnabled(identityId, reviewVal);
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'get_moderation_config':
          _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
            'juryVoteTimeoutMs': _moderationConfig.juryVoteTimeout.inMilliseconds,
            'juryMinSize': _moderationConfig.juryMinSize,
            'juryMaxSize': _moderationConfig.juryMaxSize,
            'juryMajority': _moderationConfig.juryMajority,
            'reportThresholdForJury': _moderationConfig.reportThresholdForJury,
            'maxReportsPerIdentityPerDay': _moderationConfig.maxReportsPerIdentityPerDay,
            'singlePostEscalationTimeoutMs': _moderationConfig.singlePostEscalationTimeout.inMilliseconds,
            'badgeProbationLevel1Ms': _moderationConfig.badgeProbationLevel1.inMilliseconds,
            'badgeProbationLevel2Ms': _moderationConfig.badgeProbationLevel2.inMilliseconds,
            'csamStage2Min': _moderationConfig.csamStage2Min,
            'csamStage3Min': _moderationConfig.csamStage3Min,
            'csamTempHideDurationMs': _moderationConfig.csamTempHideDuration.inMilliseconds,
            'csamReporterCooldownMs': _moderationConfig.csamReporterCooldown.inMilliseconds,
            'identityMinAgeMs': _moderationConfig.identityMinAge.inMilliseconds,
            'identityMinAgeCsamMs': _moderationConfig.identityMinAgeCSAM.inMilliseconds,
            'reachabilityEnabled': _moderationConfig.reachabilityEnabled,
            'reachabilityThreshold': _moderationConfig.reachabilityThreshold,
            'channelCreationMinAgeMs': _moderationConfig.channelCreationMinAge.inMilliseconds,
          }));
          break;

        case 'set_moderation_config':
          final preset = req.params['preset'] as String? ?? 'production';
          switch (preset) {
            case 'test':
              _moderationConfig = ModerationConfig.test();
            case 'lab':
              _moderationConfig = ModerationConfig.lab();
            default:
              _moderationConfig = ModerationConfig.production();
          }
          // Propagate to all services
          for (final service in _services.values) {
            service.moderationConfig = _moderationConfig;
          }
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'get_channel_moderation_info':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final modChId = req.params['channelIdHex'] as String?;
          if (modChId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: channelIdHex'));
            break;
          }
          final modInfo = await service.getChannelModerationInfo(modChId);
          _sendResponse(client, IpcResponse(id: req.id, success: true, data: modInfo));
          break;

        case 'get_jury_requests':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final juryRequests = service.pendingJuryRequests.map((r) => r.toJson()).toList();
          _sendResponse(client, IpcResponse(id: req.id, success: true, data: {'requests': juryRequests}));
          break;

        case 'dismiss_post_report':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final dprChId = req.params['channelIdHex'] as String?;
          final dprReportId = req.params['reportId'] as String?;
          if (dprChId == null || dprReportId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing params: channelIdHex or reportId'));
            break;
          }
          final dprResult = await service.dismissPostReport(dprChId, dprReportId);
          _sendResponse(client, IpcResponse(id: req.id, success: dprResult));
          break;

        case 'submit_badge_correction':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final sbcChId = req.params['channelIdHex'] as String?;
          if (sbcChId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: channelIdHex'));
            break;
          }
          final sbcName = req.params['newName'] as String?;
          final sbcDesc = req.params['newDescription'] as String?;
          final sbcResult = await service.submitBadgeCorrection(sbcChId, newName: sbcName, newDescription: sbcDesc);
          _sendResponse(client, IpcResponse(id: req.id, success: sbcResult));
          break;

        case 'contest_csam_hide':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final cchChId = req.params['channelIdHex'] as String?;
          if (cchChId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: channelIdHex'));
            break;
          }
          final cchResult = await service.contestCsamHide(cchChId);
          _sendResponse(client, IpcResponse(id: req.id, success: cchResult));
          break;

    }
  }


  Future<void> _handleCalls(_ClientState client, IpcRequest req) async {
    switch (req.command) {
        case 'start_call':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final peerNodeIdHex = req.params['peerNodeIdHex'] as String?;
          if (peerNodeIdHex == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: peerNodeIdHex'));
            break;
          }
          final video = req.params['video'] as bool? ?? false;
          final callInfo = await service.startCall(peerNodeIdHex, video: video);
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: callInfo != null,
            data: callInfo != null ? callInfo.toJson() : {},
            error: callInfo == null ? 'Call failed' : null,
          ));
          break;

        case 'accept_call':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          await service.acceptCall();
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: true,
          ));
          break;

        case 'reject_call':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final reason = req.params['reason'] as String? ?? 'busy';
          await service.rejectCall(reason: reason);
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: true,
          ));
          break;

        case 'hangup':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          await service.hangup();
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: true,
          ));
          break;

        case 'get_call_state':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final call = service.currentCall;
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: true,
            data: {
              'currentCall': call?.toJson(),
              'isMuted': service.isMuted,
              'isSpeakerEnabled': service.isSpeakerEnabled,
            },
          ));
          break;

        case 'toggle_mute':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          service.toggleMute();
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: true,
            data: {'isMuted': service.isMuted},
          ));
          break;

        case 'toggle_speaker':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          service.toggleSpeaker();
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: true,
            data: {'isSpeakerEnabled': service.isSpeakerEnabled},
          ));
          break;

        // ── Group Calls (Phase 3c) ─────────────────────────────────

        case 'start_group_call':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final gcGroupId = req.params['groupIdHex'] as String?;
          if (gcGroupId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing groupIdHex'));
            break;
          }
          final gcInfo = await service.startGroupCall(gcGroupId);
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: gcInfo != null,
            data: gcInfo != null ? gcInfo.toJson() : {},
            error: gcInfo == null ? 'Failed to start group call' : null,
          ));
          break;

        case 'accept_group_call':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          await service.acceptGroupCall();
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'reject_group_call':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final gcRejectReason = req.params['reason'] as String? ?? 'busy';
          await service.rejectGroupCall(reason: gcRejectReason);
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'leave_group_call':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          await service.leaveGroupCall();
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'get_group_call_state':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final gcState = service.currentGroupCall;
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: true,
            data: {
              'currentGroupCall': gcState?.toJson(),
              'isMuted': service.isMuted,
              'isSpeakerEnabled': service.isSpeakerEnabled,
            },
          ));
          break;

    }
  }


  Future<void> _handleCalendar(_ClientState client, IpcRequest req) async {
    switch (req.command) {
        // ── Calendar (§23) ───────────────────────────────────────────────

        case 'calendar_create_event':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final event = CalendarEvent.fromJson(req.params['event'] as Map<String, dynamic>);
          final eventId = await service.createCalendarEvent(event);
          _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
            'eventId': eventId,
          }));
          break;

        case 'calendar_update_event':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final eventId = req.params['eventId'] as String?;
          if (eventId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: eventId'));
            break;
          }
          final updates = req.params['updates'] as Map<String, dynamic>? ?? {};
          final ok = await service.updateCalendarEvent(eventId,
            title: updates['title'] as String?,
            description: updates['description'] as String?,
            location: updates['location'] as String?,
            startTime: updates['startTime'] as int?,
            endTime: updates['endTime'] as int?,
            allDay: updates['allDay'] as bool?,
            hasCall: updates['hasCall'] as bool?,
            reminders: (updates['reminders'] as List?)?.cast<int>(),
            recurrenceRule: updates['recurrenceRule'] as String?,
            taskCompleted: updates['taskCompleted'] as bool?,
            taskPriority: updates['taskPriority'] as int?,
            cancelled: updates['cancelled'] as bool?,
          );
          _sendResponse(client, IpcResponse(id: req.id, success: ok));
          break;

        case 'calendar_delete_event':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final delEventId = req.params['eventId'] as String?;
          if (delEventId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: eventId'));
            break;
          }
          await service.deleteCalendarEvent(delEventId);
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'calendar_list_events':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final windowStart = req.params['windowStart'] as int? ?? DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
          final windowEnd = req.params['windowEnd'] as int? ?? DateTime.now().add(const Duration(days: 90)).millisecondsSinceEpoch;
          final occurrences = service.calendarManager.getEventsInRange(windowStart, windowEnd);
          _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
            'events': occurrences.map((o) => o.toJson()).toList(),
          }));
          break;

        case 'calendar_list_tasks':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final includeCompleted = req.params['includeCompleted'] as bool? ?? false;
          final tasks = service.calendarManager.getTasks(includeCompleted: includeCompleted);
          _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
            'tasks': tasks.map((t) => t.toJson()).toList(),
          }));
          break;

        case 'calendar_list_birthdays':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final birthdays = service.calendarManager.getBirthdays();
          _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
            'birthdays': birthdays.map((b) => b.toJson()).toList(),
          }));
          break;

        case 'calendar_send_rsvp':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final rsvpEventId = req.params['eventId'] as String?;
          final rsvpStatusIdx = req.params['status'] as int?;
          if (rsvpEventId == null || rsvpStatusIdx == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: eventId or status'));
            break;
          }
          await service.sendCalendarRsvp(
            rsvpEventId,
            RsvpStatus.values[rsvpStatusIdx.clamp(0, RsvpStatus.values.length - 1)],
            proposedStart: req.params['proposedStart'] as int?,
            proposedEnd: req.params['proposedEnd'] as int?,
            comment: req.params['comment'] as String?,
          );
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'calendar_query_free_busy':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final fbContactId = req.params['contactNodeIdHex'] as String?;
          final fbStart = req.params['queryStart'] as int?;
          final fbEnd = req.params['queryEnd'] as int?;
          if (fbContactId == null || fbStart == null || fbEnd == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param'));
            break;
          }
          final requestIdHex = await service.sendFreeBusyRequest(fbContactId, fbStart, fbEnd);
          _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
            'requestId': requestIdHex,
          }));
          break;

        case 'calendar_get_free_busy_settings':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
            'settings': service.calendarManager.freeBusySettings.toJson(),
          }));
          break;

        case 'calendar_set_free_busy_settings':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final settingsJson = req.params['settings'] as Map<String, dynamic>?;
          if (settingsJson == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: settings'));
            break;
          }
          service.calendarManager.freeBusySettings = FreeBusySettings.fromJson(settingsJson);
          service.calendarManager.saveSettings();
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        // ── Calendar Sync (§23.8 — CalDAV + Google) ───────────────────────

        case 'calendar_sync_status':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
            'status': service.calendarSyncService.publicStatusJson(),
          }));
          break;

        case 'calendar_sync_trigger':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          // Fire-and-forget — the client polls calendar_sync_status for progress.
          unawaited(service.calendarSyncService.syncAll().then((r) {
            _broadcastEvent(IpcEvent(
              event: 'calendar_sync_completed',
              identityId: service.identity.userIdHex,
              data: {
                'ok': !r.hasErrors,
                'pulledNew': r.pulledNew,
                'pulledUpdated': r.pulledUpdated,
                'pulledDeleted': r.pulledDeleted,
                'pushedNew': r.pushedNew,
                'pushedUpdated': r.pushedUpdated,
                'pushedDeleted': r.pushedDeleted,
                'errors': r.errors,
              },
            ));
          }).catchError((e) {
            _log.warn('calendar_sync_trigger error: $e');
          }));
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'calendar_sync_configure_caldav':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final cfgJson = req.params['config'] as Map<String, dynamic>?;
          if (cfgJson == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: config'));
            break;
          }
          try {
            final cfg = CalDAVConfig.fromJson(cfgJson);
            await service.calendarSyncService.configureCalDAV(cfg);
            _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
              'status': service.calendarSyncService.publicStatusJson(),
            }));
          } catch (e) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'calendar_sync_configure_caldav: $e'));
          }
          break;

        case 'calendar_sync_caldav_list_calendars':
          // Helper command: probe a CalDAV server with given credentials and
          // return the discovered calendar list. Used by the UI during setup
          // before the user commits configuration.
          final cfgJson = req.params['config'] as Map<String, dynamic>?;
          if (cfgJson == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: config'));
            break;
          }
          try {
            final cfg = CalDAVConfig.fromJson(cfgJson);
            final calendars = await CalDAVClient.discoverAndList(cfg);
            _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
              'calendars': calendars.map((c) => c.toJson()).toList(),
            }));
          } catch (e) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'calendar_sync_caldav_list_calendars: $e'));
          }
          break;

        case 'calendar_sync_remove_caldav':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          service.calendarSyncService.removeCalDAV();
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'calendar_sync_google_oauth_start':
          // Begin Google OAuth2 flow. Daemon opens a loopback HTTP server and
          // returns the auth URL. Client opens that URL in the system browser.
          // Daemon watches the callback; once user consents, configureGoogle
          // is applied automatically.
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final clientId = req.params['clientId'] as String?;
          if (clientId == null || clientId.isEmpty) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: clientId'));
            break;
          }
          try {
            final handle = await GoogleCalendarClient.startOAuthFlow(clientId: clientId);
            // Listen for completion — when done, apply the config.
            final serviceRef = service;
            unawaited(handle.waitForCompletion.then((cfg) {
              serviceRef.calendarSyncService.configureGoogle(cfg);
              _broadcastEvent(IpcEvent(
                event: 'calendar_sync_google_connected',
                identityId: serviceRef.identity.userIdHex,
                data: {
                  'accountEmail': cfg.accountEmail,
                  'calendarId': cfg.calendarId,
                },
              ));
            }).catchError((e) {
              _log.warn('Google OAuth failed: $e');
              _broadcastEvent(IpcEvent(
                event: 'calendar_sync_google_error',
                identityId: serviceRef.identity.userIdHex,
                data: {'error': '$e'},
              ));
            }));
            _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
              'authUrl': handle.authUrl,
              'port': handle.port,
            }));
          } catch (e) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'calendar_sync_google_oauth_start: $e'));
          }
          break;

        case 'calendar_sync_remove_google':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          service.calendarSyncService.removeGoogle();
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'calendar_sync_configure_exchange':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final cfgJson = req.params['config'] as Map<String, dynamic>?;
          if (cfgJson == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: config'));
            break;
          }
          try {
            final cfg = EWSConfig.fromJson(cfgJson);
            await service.calendarSyncService.configureEWS(cfg);
            _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
              'status': service.calendarSyncService.publicStatusJson(),
            }));
          } catch (e) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'calendar_sync_configure_exchange: $e'));
          }
          break;

        case 'calendar_sync_exchange_oauth_start':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final ewsClientId = req.params['clientId'] as String?;
          final ewsEmail = req.params['email'] as String?;
          final ewsDirection = req.params['direction'] as String? ?? 'bidirectional';
          if (ewsClientId == null || ewsClientId.isEmpty || ewsEmail == null || ewsEmail.isEmpty) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing params: clientId, email'));
            break;
          }
          try {
            final handle = await EWSClient.startOAuthFlow(
              clientId: ewsClientId,
              email: ewsEmail,
              direction: CalendarSyncDirectionX.parse(ewsDirection),
            );
            final serviceRef = service;
            unawaited(handle.waitForCompletion.then((cfg) {
              serviceRef.calendarSyncService.configureEWS(cfg);
              _broadcastEvent(IpcEvent(
                event: 'calendar_sync_exchange_connected',
                identityId: serviceRef.identity.userIdHex,
                data: {'email': cfg.email},
              ));
            }).catchError((e) {
              _log.warn('Exchange OAuth failed: $e');
              _broadcastEvent(IpcEvent(
                event: 'calendar_sync_exchange_error',
                identityId: serviceRef.identity.userIdHex,
                data: {'error': '$e'},
              ));
            }));
            _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
              'authUrl': handle.authUrl,
              'port': handle.port,
            }));
          } catch (e) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'calendar_sync_exchange_oauth_start: $e'));
          }
          break;

        case 'calendar_sync_remove_exchange':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          service.calendarSyncService.removeEWS();
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'calendar_sync_ews_autodiscover':
          final ewsDiscoverEmail = req.params['email'] as String?;
          if (ewsDiscoverEmail == null || ewsDiscoverEmail.isEmpty) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: email'));
            break;
          }
          try {
            final serverUrl = await EWSClient.autodiscover(ewsDiscoverEmail);
            _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
              'serverUrl': serverUrl,
            }));
          } catch (e) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'ews_autodiscover: $e'));
          }
          break;

        case 'calendar_sync_configure_local_ics':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final cfgJson = req.params['config'] as Map<String, dynamic>?;
          if (cfgJson == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: config'));
            break;
          }
          try {
            final cfg = LocalIcsConfig.fromJson(cfgJson);
            await service.calendarSyncService.configureLocalIcs(cfg);
            _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
              'status': service.calendarSyncService.publicStatusJson(),
            }));
          } catch (e) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'calendar_sync_configure_local_ics: $e'));
          }
          break;

        case 'calendar_sync_remove_local_ics':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          service.calendarSyncService.removeLocalIcs();
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'calendar_sync_list_conflicts':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
            'conflicts':
                service.calendarSyncService.conflicts.map((c) => c.toJson()).toList(),
            'pending': service.calendarSyncService.pendingConflicts
                .map((c) => c.toJson())
                .toList(),
          }));
          break;

        case 'calendar_sync_clear_conflicts':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          service.calendarSyncService.clearConflicts();
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'calendar_sync_restore_conflict':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final conflictId = req.params['conflictId'] as String?;
          if (conflictId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: conflictId'));
            break;
          }
          final ok = service.calendarSyncService.restoreConflict(conflictId);
          _sendResponse(client, IpcResponse(id: req.id, success: ok,
              error: ok ? null : 'Conflict not found'));
          break;

        case 'calendar_sync_resolve_pending':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final conflictId = req.params['conflictId'] as String?;
          final keep = req.params['keep'] as String?;
          if (conflictId == null || keep == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: conflictId or keep'));
            break;
          }
          final ok =
              service.calendarSyncService.resolvePendingConflict(conflictId, keep);
          _sendResponse(client, IpcResponse(id: req.id, success: ok,
              error: ok ? null : 'Pending conflict not found'));
          break;

        // ── Local CalDAV server (§23.8.7) ─────────────────────────────
        //
        // Daemon-wide feature (not per-identity), so these commands don't
        // use `_resolveService`. The daemon wires the four callbacks
        // below in its `_MultiServiceDaemon`.

        case 'caldav_server_state':
          if (onCalDAVServerGetState == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false,
                error: 'CalDAV server not wired'));
            break;
          }
          _sendResponse(client, IpcResponse(id: req.id, success: true,
              data: onCalDAVServerGetState!()));
          break;

        case 'caldav_server_set_enabled':
          if (onCalDAVServerSetEnabled == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false,
                error: 'CalDAV server not wired'));
            break;
          }
          final enabled = req.params['enabled'] as bool?;
          if (enabled == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false,
                error: 'Missing param: enabled'));
            break;
          }
          try {
            final state = await onCalDAVServerSetEnabled!(enabled);
            _sendResponse(client, IpcResponse(id: req.id, success: true,
                data: state));
          } catch (e) {
            _sendResponse(client, IpcResponse(id: req.id, success: false,
                error: 'caldav_server_set_enabled: $e'));
          }
          break;

        case 'caldav_server_regenerate_token':
          if (onCalDAVServerRegenerateToken == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false,
                error: 'CalDAV server not wired'));
            break;
          }
          final state = await onCalDAVServerRegenerateToken!();
          _sendResponse(client, IpcResponse(id: req.id, success: true,
              data: state));
          break;

        case 'caldav_server_set_port':
          if (onCalDAVServerSetPort == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false,
                error: 'CalDAV server not wired'));
            break;
          }
          final port = req.params['port'] as int?;
          if (port == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false,
                error: 'Missing param: port'));
            break;
          }
          try {
            final state = await onCalDAVServerSetPort!(port);
            _sendResponse(client, IpcResponse(id: req.id, success: true,
                data: state));
          } catch (e) {
            _sendResponse(client, IpcResponse(id: req.id, success: false,
                error: 'caldav_server_set_port: $e'));
          }
          break;

        case 'calendar_sync_set_foreground':
          // Client signals whether the app is currently in the foreground.
          // The daemon uses this to switch between aggressive (~3 min) and
          // conservative (~15 min) polling — the honest P2P alternative
          // to Google FCM push (which requires a central webhook we don't have).
          // Applies to all identities so any active calendar view benefits.
          final foreground = req.params['foreground'] as bool? ?? false;
          for (final svc in _services.values) {
            svc.calendarSyncService.setForeground(foreground);
          }
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'contact_set_birthday':
          // Set the birthday metadata for a contact (stored locally only).
          // Triggers an immediate rebuild of the calendar's birthday events.
          // Passing null for month/day clears the birthday.
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final contactHex = req.params['nodeIdHex'] as String?;
          if (contactHex == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: nodeIdHex'));
            break;
          }
          final ok = service.setContactBirthday(
            contactHex,
            month: req.params['month'] as int?,
            day: req.params['day'] as int?,
            year: req.params['year'] as int?,
          );
          _sendResponse(client, IpcResponse(id: req.id, success: ok,
              error: ok ? null : 'Contact not found'));
          break;

    }
  }


  Future<void> _handlePolls(_ClientState client, IpcRequest req) async {
    switch (req.command) {
        // ── Polls (§24) ────────────────────────────────────────────────

        case 'poll_create':
          {
            final service = _resolveService(client, req);
            if (service == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
              break;
            }
            final question = req.params['question'] as String?;
            final groupId = req.params['groupId'] as String?;
            final typeIdx = req.params['pollType'] as int? ?? 0;
            if (question == null || groupId == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing question/groupId'));
              break;
            }
            final optionsRaw = req.params['options'] as List<dynamic>? ?? [];
            final options = optionsRaw
                .map((e) => PollOption.fromJson((e as Map).cast<String, dynamic>()))
                .toList();
            final settingsJson = (req.params['settings'] as Map?)?.cast<String, dynamic>() ?? const {};
            final pollId = await service.createPoll(
              question: question,
              description: req.params['description'] as String? ?? '',
              pollType: PollType.values[typeIdx.clamp(0, PollType.values.length - 1)],
              options: options,
              settings: PollSettings.fromJson(settingsJson),
              groupIdHex: groupId,
            );
            _sendResponse(client, IpcResponse(id: req.id, success: true, data: {'pollId': pollId}));
          }
          break;

        case 'poll_vote':
          {
            final service = _resolveService(client, req);
            if (service == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
              break;
            }
            final pollId = req.params['pollId'] as String?;
            if (pollId == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing pollId'));
              break;
            }
            Map<int, DateAvailability>? dateResponses;
            final drRaw = req.params['dateResponses'];
            if (drRaw is Map) {
              dateResponses = drRaw.map((k, v) =>
                  MapEntry(int.parse(k as String),
                      DateAvailability.values[(v as int).clamp(0, DateAvailability.values.length - 1)]));
            }
            final ok = await service.submitPollVote(
              pollId: pollId,
              selectedOptions: (req.params['selectedOptions'] as List?)?.cast<int>(),
              dateResponses: dateResponses,
              scaleValue: req.params['scaleValue'] as int?,
              freeText: req.params['freeText'] as String?,
            );
            _sendResponse(client, IpcResponse(id: req.id, success: ok));
          }
          break;

        case 'poll_vote_anonymous':
          {
            final service = _resolveService(client, req);
            if (service == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
              break;
            }
            final pollId = req.params['pollId'] as String?;
            if (pollId == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing pollId'));
              break;
            }
            Map<int, DateAvailability>? dateResponses;
            final drRaw = req.params['dateResponses'];
            if (drRaw is Map) {
              dateResponses = drRaw.map((k, v) =>
                  MapEntry(int.parse(k as String),
                      DateAvailability.values[(v as int).clamp(0, DateAvailability.values.length - 1)]));
            }
            final ok = await service.submitPollVoteAnonymous(
              pollId: pollId,
              selectedOptions: (req.params['selectedOptions'] as List?)?.cast<int>(),
              dateResponses: dateResponses,
              scaleValue: req.params['scaleValue'] as int?,
              freeText: req.params['freeText'] as String?,
            );
            _sendResponse(client, IpcResponse(id: req.id, success: ok));
          }
          break;

        case 'poll_vote_revoke':
          {
            final service = _resolveService(client, req);
            if (service == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
              break;
            }
            final pollId = req.params['pollId'] as String?;
            if (pollId == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing pollId'));
              break;
            }
            final ok = await service.revokePollVoteAnonymous(pollId);
            _sendResponse(client, IpcResponse(id: req.id, success: ok));
          }
          break;

        case 'poll_update':
          {
            final service = _resolveService(client, req);
            if (service == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
              break;
            }
            final pollId = req.params['pollId'] as String?;
            if (pollId == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing pollId'));
              break;
            }
            final addOptsRaw = req.params['addOptions'] as List<dynamic>?;
            final ok = await service.updatePoll(pollId,
              close: req.params['close'] as bool?,
              reopen: req.params['reopen'] as bool?,
              addOptions: addOptsRaw
                  ?.map((e) => PollOption.fromJson((e as Map).cast<String, dynamic>()))
                  .toList(),
              removeOptions: (req.params['removeOptions'] as List?)?.cast<int>(),
              newDeadline: req.params['newDeadline'] as int?,
              delete: req.params['delete'] as bool? ?? false,
            );
            _sendResponse(client, IpcResponse(id: req.id, success: ok));
          }
          break;

        case 'poll_list':
          {
            final service = _resolveService(client, req);
            if (service == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
              break;
            }
            final groupId = req.params['groupId'] as String?;
            final polls = service.pollManager.polls.values
                .where((p) => groupId == null || p.groupId == groupId)
                .map((p) => p.toJson())
                .toList();
            _sendResponse(client, IpcResponse(id: req.id, success: true, data: {'polls': polls}));
          }
          break;

        case 'poll_convert_to_event':
          {
            final service = _resolveService(client, req);
            if (service == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
              break;
            }
            final pollId = req.params['pollId'] as String?;
            final winning = req.params['winningOptionId'] as int?;
            if (pollId == null || winning == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing pollId/winningOptionId'));
              break;
            }
            final evId = await service.convertDatePollToEvent(pollId, winning);
            _sendResponse(client, IpcResponse(
                id: req.id, success: evId != null, data: {'eventId': evId ?? ''}));
          }
          break;

        // §19.6 — In-network update IPC commands
        // Binary-update subsystem lives on the primary identity's service
        // only (first service to start gets node.binaryRendezvousManager).
        // Always resolve to primary, never to the client's active identity.
        //
        // `seed_binary` and `export_binary` are back since 02.09.2026.
        // Both carriers lie in this tree and run exclusively locally — the
        // reasoning stands at `CleonaService.seedBinaryFromFile`
        // (`cleona_service_pure.dart`). In short: the CUT comment that stood
        // here justified the deletion with an unbuilt successor
        // (fountain/AP-7), but the deleted body touches nothing the CUT
        // removed, and `_selfSeedCurrentBinary` uses the same apparatus on
        // EVERY start.

        case 'seed_binary':
          {
            final service = _services[_defaultIdentityId];
            if (service == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No primary service'));
              break;
            }
            final platform = req.params['platform'] as String?;
            final version = req.params['version'] as String?;
            final filePath = req.params['filePath'] as String?;
            if (platform == null || version == null || filePath == null) {
              _sendResponse(client, IpcResponse(
                  id: req.id, success: false,
                  error: 'Missing platform/version/filePath'));
              break;
            }
            // `maxFragments` is optional; if it is missing, the service's
            // default applies (50, §19.6.2 "bootstrap=all"). An unusable
            // value (<= 0) is NOT passed through as 0 — that would silently
            // have stored nothing and still reported success.
            final rawMax = req.params['maxFragments'];
            final maxFragments = rawMax is int && rawMax > 0 ? rawMax : null;
            final result = maxFragments == null
                ? await service.seedBinaryFromFile(platform, version, filePath)
                : await service.seedBinaryFromFile(platform, version, filePath,
                    maxFragments: maxFragments);
            final hasError = result.containsKey('error');
            _sendResponse(client, IpcResponse(
                id: req.id, success: !hasError, data: result,
                error: hasError ? result['error'] as String : null));
          }
          break;

        // `export_binary` writes a binary that is COMPLETELY present in the
        // fragment store onto the disk (§19.6.7, physical transfer via
        // USB/NFC). The carrier is `PhysicalTransferHelper.exportBinary`
        // (`lib/core/update/physical_transfer_helper.dart:32`) and is built
        // continuously (`cleona_service_update.dart:498`) — since the
        // command disappeared it simply had no caller.
        //
        // Resolution via the PRIMARY identity, like the neighbouring
        // commands. The original resolved via `_resolveService`, i.e. via
        // the client's active identity; thus `seed_binary` would have
        // written into one fragment store and `export_binary` read from
        // another (the store hangs on the profile directory,
        // `cleona_service_update.dart:485`). One resolution rule per group,
        // not per command.
        case 'export_binary':
          {
            final service = _services[_defaultIdentityId];
            if (service == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No primary service'));
              break;
            }
            final helper = service.physicalTransferHelper;
            if (helper == null) {
              _sendResponse(client, IpcResponse(
                  id: req.id, success: false,
                  error: 'Binary-update subsystem not initialized'));
              break;
            }
            final platform = req.params['platform'] as String?;
            final version = req.params['version'] as String?;
            final outputPath = req.params['outputPath'] as String?;
            if (platform == null || version == null || outputPath == null) {
              _sendResponse(client, IpcResponse(
                  id: req.id, success: false,
                  error: 'Missing param: platform, version or outputPath'));
              break;
            }
            final exportedHash = await helper.exportBinary(
                platform: platform, version: version, outputPath: outputPath);
            _sendResponse(client, IpcResponse(
                id: req.id,
                success: exportedHash != null,
                data: exportedHash != null ? {'hash': exportedHash} : {},
                error: exportedHash == null
                    ? 'Export failed — no complete binary stored for $platform/$version'
                    : null));
          }
          break;

        case 'get_seeded_platforms':
          {
            final service = _services[_defaultIdentityId];
            if (service == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No primary service'));
              break;
            }
            _sendResponse(client, IpcResponse(
                id: req.id, success: true, data: {'platforms': service.getSeededPlatforms()}));
          }
          break;

        case 'reload_manifest':
          {
            final service = _services[_defaultIdentityId];
            if (service == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No primary service'));
              break;
            }
            final result = service.reloadManifest();
            final hasError = result.containsKey('error');
            _sendResponse(client, IpcResponse(
                id: req.id, success: !hasError, data: result,
                error: hasError ? result['error'] as String : null));
          }
          break;

        case 'generate_invite_link_url':
          {
            // Resolved against the ACTIVE identity, not the primary: the link
            // carries that identity's contact seed. The update manifest it
            // also needs is bootstrapped per service from the shared on-disk
            // cache (cleona_service.dart `_initUpdateChecking`), so the
            // active service has it too.
            final service = _resolveService(client, req);
            if (service == null) {
              _sendResponse(client, IpcResponse(
                  id: req.id, success: false, error: 'No active service'));
              break;
            }
            final url = await service.generateInviteLinkUrl();
            _sendResponse(client, IpcResponse(
                id: req.id, success: true, data: {'url': url}));
          }
          break;

        case 'issue_invitation':
          {
            // ── THE ISSUER IS THIS PROCESS (§15.3) ─────────────
            //
            // "Invitations can only be issued by the device that holds the
            // identity." The daemon holds the master seed, keeps the ledger
            // and harvests the invitation line (§15.3.2) — the UI can do
            // none of the three. Until S380 this path did not exist, and on
            // every daemon platform the ContactSeed therefore never carried
            // `ki`; every first request was rejected at the sender. Resolved
            // against the ACTIVE identity, like `generate_invite_link_url`
            // next to it: the invitation belongs to the identity whose seed
            // is being shown right now.
            final service = _resolveService(client, req);
            if (service == null) {
              _sendResponse(client, IpcResponse(
                  id: req.id, success: false, error: 'No active service'));
              break;
            }
            final code = req.params['class'] as String?;
            if (code == null || code.isEmpty) {
              _sendResponse(client, IpcResponse(
                  id: req.id, success: false, error: 'class missing'));
              break;
            }
            final ms = req.params['validityMs'] as int?;
            final invite = await service.issueInviteForSharing(
              inviteClassCode: code,
              validity: ms == null ? null : Duration(milliseconds: ms),
              singleUse: req.params['singleUse'] as bool? ?? false,
              label: req.params['label'] as String? ?? 'qr-card',
            );
            final issued = invite.invite;
            if (issued == null) {
              // ── THE REASON TRAVELS ALONG (S381, 11.09.2026) ──────────────
              //
              // Here stood: "The REASON stands in the issuer's log (cap,
              // ledger, seed). Repeating it here would mean maintaining it in
              // two places; the UI only needs 'not issued'."
              //
              // The UI does need it: it cannot read the daemon's log and
              // therefore GUESSED the most frequent one
              // (`invite_cap_reached`). A guessed reason sends the user down
              // the wrong path — whoever reads "cap reached" revokes
              // invitations, although in truth the master seed was missing.
              // §15.3.1: "the UI must name the consequence".
              //
              // This is NOT a second maintenance place: the reason is
              // maintained exactly once, in `invite_issue_refusal.dart`; here
              // only its stable identifier travels.
              _sendResponse(client, IpcResponse(
                  id: req.id,
                  success: false,
                  error: 'not issued',
                  data: {
                    kInviteRefusalField:
                        (invite.refusal ?? InviteIssueRefusal.unknownReason)
                            .wireCode
                  }));
              break;
            }
            _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
              'class': issued.inviteClassCode,
              'index': issued.index,
              'expiresAtMs': issued.expiresAtMs,
              'kiB64': base64.encode(issued.inviteKey),
            }));
          }
          break;

        // §15.3.2 / §15.3.3 — list and revoke (S381). Both lie with the
        // ONE writer: the ledger stands in the daemon.
        case 'list_open_invitations':
          {
            final service = _services[_defaultIdentityId];
            if (service == null) {
              _sendResponse(client, IpcResponse(
                  id: req.id, success: false, error: 'No active service'));
              break;
            }
            try {
              final open = await service.listOpenInvitations();
              _sendResponse(client, IpcResponse(
                  id: req.id,
                  success: true,
                  data: {
                    'invitations': open.map((i) => i.toJson()).toList()
                  }));
            } on StateError catch (e) {
              // §21.4: unreadable is not empty — that goes out as an ERROR,
              // so that the UI does not claim "no open invitations".
              _sendResponse(client, IpcResponse(
                  id: req.id, success: false, error: 'ledger unreadable: $e'));
            }
          }
          break;

        case 'revoke_invitation':
          {
            final service = _services[_defaultIdentityId];
            if (service == null) {
              _sendResponse(client, IpcResponse(
                  id: req.id, success: false, error: 'No active service'));
              break;
            }
            final idx = req.params['index'] as int?;
            if (idx == null) {
              _sendResponse(client, IpcResponse(
                  id: req.id, success: false, error: 'index missing'));
              break;
            }
            final route = await service.revokeInvitation(idx);
            _sendResponse(client, IpcResponse(
                id: req.id, success: true, data: {'revoked': route}));
          }
          break;

        // ── V4.2 invitation card (S387, `mycelium/berichte/S387-API-KARTE.md`) ──
        //
        // Resolved against the active identity of the CALLING client: the
        // UI is a client of its own, and the card belongs to the identity
        // it is showing there right now (§15.3). Domain outcomes travel as a
        // value with `success: true`.
        case 'invitation_card_issue':
          {
            final service = _resolveService(client, req);
            if (service == null) {
              _sendResponse(client, IpcResponse(
                  id: req.id, success: false, error: 'No active service'));
              break;
            }
            final kind = InvitationKind.byName(req.params['kind'] as String?);
            if (kind == null) {
              _sendResponse(client, IpcResponse(
                  id: req.id, success: false, error: 'kind missing'));
              break;
            }
            final outcome = await service.issueInvitationCard(
              kind: kind,
              validity:
                  InvitationValidity.byName(req.params['validity'] as String?),
              label: req.params['label'] as String? ?? '',
              faceToFace: req.params['faceToFace'] == true,
            );
            _sendResponse(client, IpcResponse(
                id: req.id, success: true, data: outcome.toJson()));
          }
          break;

        case 'invitation_card_redeem_text':
          {
            final service = _resolveService(client, req);
            final text = req.params['text'] as String?;
            if (service == null || text == null) {
              _sendResponse(client, IpcResponse(
                  id: req.id,
                  success: false,
                  error: service == null ? 'No active service' : 'text missing'));
              break;
            }
            final outcome = await service.redeemInvitationText(text);
            _sendResponse(client, IpcResponse(
                id: req.id, success: true, data: outcome.toJson()));
          }
          break;

        case 'invitation_card_redeem_bytes':
          {
            final service = _resolveService(client, req);
            final b64 = req.params['packedB64'] as String?;
            if (service == null || b64 == null) {
              _sendResponse(client, IpcResponse(
                  id: req.id,
                  success: false,
                  error: service == null
                      ? 'No active service'
                      : 'packedB64 missing'));
              break;
            }
            final Uint8List packed;
            try {
              packed = Uint8List.fromList(base64.decode(b64));
            } on FormatException catch (e) {
              _sendResponse(client, IpcResponse(
                  id: req.id, success: false, error: 'packedB64: $e'));
              break;
            }
            final outcome = await service.redeemInvitationCardBytes(packed);
            _sendResponse(client, IpcResponse(
                id: req.id, success: true, data: outcome.toJson()));
          }
          break;

        case 'invitation_card_standing':
          {
            final service = _resolveService(client, req);
            if (service == null) {
              _sendResponse(client, IpcResponse(
                  id: req.id, success: false, error: 'No active service'));
              break;
            }
            final outcome = await service.standingInvitations();
            _sendResponse(client, IpcResponse(
                id: req.id, success: true, data: outcome.toJson()));
          }
          break;

        case 'invitation_card_revoke':
          {
            final service = _resolveService(client, req);
            final id = req.params['id'] as String?;
            if (service == null || id == null) {
              _sendResponse(client, IpcResponse(
                  id: req.id,
                  success: false,
                  error: service == null ? 'No active service' : 'id missing'));
              break;
            }
            final outbound = await service.revokeInvitationCard(id);
            _sendResponse(client, IpcResponse(
                id: req.id, success: true, data: {'outcome': outbound.name}));
          }
          break;

        case 'invitation_card_revoke_all':
          {
            final service = _resolveService(client, req);
            if (service == null) {
              _sendResponse(client, IpcResponse(
                  id: req.id, success: false, error: 'No active service'));
              break;
            }
            final outcome = await service.revokeAllInvitationCards();
            _sendResponse(client, IpcResponse(
                id: req.id, success: true, data: outcome.toJson()));
          }
          break;

        case 'get_update_status':
          {
            final service = _services[_defaultIdentityId];
            if (service == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No primary service'));
              break;
            }
            _sendResponse(client, IpcResponse(
                id: req.id, success: true, data: service.getUpdateStatus()));
          }
          break;

        case 'start_in_network_update':
          {
            final service = _services[_defaultIdentityId];
            _log.info('IPC: start_in_network_update received '
                '(activeId=${client.activeIdentityId}, primaryId=$_defaultIdentityId, '
                'service=${service != null})');
            if (service == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No primary service'));
              break;
            }
            final manifest = service.latestManifest;
            if (manifest == null) {
              _log.warn('IPC: start_in_network_update — no manifest on primary service');
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No update manifest available'));
              break;
            }
            _log.info('IPC: start_in_network_update — starting download v${manifest.version}');
            _sendResponse(client, IpcResponse(id: req.id, success: true));
            service.startInNetworkUpdate(manifest);
          }
          break;

        case 'apply_update':
          _log.info('IPC: apply_update received — triggering daemon-side apply');
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          onApplyUpdate?.call();
          break;

    }
  }

  // ── Rescue-bundle helpers ────────────────────────────────────────────────

  /// Returns true if [addr] ("ip:port" or "[ipv6]:port") has a globally
  /// routable / public address (not link-local, loopback, or RFC-1918).
  static bool _isPublicAddress(String addr) {
    final h = _splitHostPort(addr);
    if (h == null) return false;
    final ip = h.$1;
    // Loopback / link-local / RFC-1918 / ULA → not public
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

  /// Split "ip:port" or "[ipv6]:port" into (host, port). Returns null on failure.
  static (String, int)? _splitHostPort(String addr) {
    try {
      if (addr.startsWith('[')) {
        // IPv6: [ip]:port
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

  /// Convert a 64-char hex string to a 32-byte Uint8List.
  /// Returns null if the string is malformed.
  static Uint8List? _hexToBytes32(String hex) {
    if (hex.length != 64) return null;
    try {
      return hexToBytes(hex);
    } catch (_) {
      return null;
    }
  }

  void _sendResponse(_ClientState client, IpcResponse response) {
    if (client.removed) return;
    try {
      client.socket.write(response.toJsonLine());
    } catch (e) {
      _log.debug('Failed to send IPC response: $e');
      _removeClient(client);
    }
  }

  void _broadcastEvent(IpcEvent event) {
    final line = event.toJsonLine();
    for (final client in List.of(_clients)) {
      if (client.removed) continue;
      try {
        client.socket.write(line);
      } catch (e) {
        _log.debug('Failed to broadcast to client: $e');
        _removeClient(client);
      }
    }
  }

  Future<void> stop() async {
    for (final client in List.of(_clients)) {
      client.removed = true;
      client.subscription?.cancel();
      client.subscription = null;
      try {
        client.socket.destroy();
      } catch (_) {}
    }
    _clients.clear();

    await _server?.close();
    _server = null;

    // Remove socket/port file
    if (Platform.isWindows) {
      final portFile = File(socketPath.replaceAll('.sock', '.port'));
      if (portFile.existsSync()) portFile.deleteSync();
    } else {
      final socketFile = File(socketPath);
      if (socketFile.existsSync()) socketFile.deleteSync();
    }

    _log.info('IPC server stopped');
  }
}

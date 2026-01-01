import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/channels/system_channels.dart';
import 'package:cleona/core/ipc/ipc_messages.dart';
import 'package:cleona/core/util/hex.dart' show bytesToHex;
import 'package:cleona/core/crypto/hd_wallet.dart' show HdWallet;
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/contact/contact_seed.dart'
    show ContactSeedBuilder, ContactSeedDataSource, EntrySeedCandidate;
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/core/stats/network_stats.dart';
import 'package:cleona/core/service/notification_sound_service.dart';
import 'package:cleona/core/media/link_preview_fetcher.dart';
import 'package:cleona/core/service/multi_interface_mode.dart';
import 'package:cleona/core/calendar/calendar_manager.dart';
import 'package:cleona/core/polls/poll_manager.dart';
import 'package:cleona/core/identity/identity_context.dart';
import 'package:cleona/core/update/update_manifest.dart';
import 'package:cleona/core/update/binary_update_manager.dart' show BinaryUpdateState;

/// IPC client that connects to the cleona-daemon via Unix Domain Socket.
/// Implements ICleonaService so the GUI can use it transparently.
class IpcClient implements ICleonaService, ContactSeedDataSource {
  final String socketPath;

  Socket? _socket;
  int _nextRequestId = 1;
  final Map<int, Completer<IpcResponse>> _pendingRequests = {};
  final StringBuffer _buffer = StringBuffer();
  bool _connected = false;

  /// Called when the daemon process is genuinely gone (lock file missing or
  /// PID dead) and reconnect retries are exhausted. GUI should exit — daemon
  /// and GUI act as one unit per CLAUDE.md §1.
  void Function()? onDaemonDied;

  /// Called when reconnect retries are exhausted but the daemon process is
  /// still alive (lock file present, PID still reachable). This typically
  /// means the daemon is mid-restart or doing slow PQ keygen. The GUI should
  /// re-arm a longer-window retry instead of exiting; otherwise a transient
  /// stall would tear down the GUI even though the daemon will be back in
  /// seconds. Architecturally distinct from `onDaemonDied`.
  void Function()? onIpcStalled;

  // Active identity for this client connection
  String? activeIdentityId;

  late final ContactSeedBuilder _contactSeedBuilder = ContactSeedBuilder(this);
  @override
  ContactSeedBuilder get contactSeedBuilder => _contactSeedBuilder;

  // Cached state from daemon
  String _nodeIdHex = '';
  // C1: the active identity's profileDir, filled from `get_state`. Needed
  // so GUI-side bridges (AndroidCalendarBridge) can log to the SAME file
  // the daemon writes to instead of falling back to the process-log.
  String _profileDir = '';
  // Welle 5/6: device identity bits (= deviceNodeIdHex + Device-KEM-PKs).
  // Filled from `get_state` snapshot; required by ContactSeed-URI generation
  // (identity_detail_screen.dart) so the receiver can run First-CR without
  // a 2D-DHT DeviceKemRecord lookup (Architecture §8.1.1).
  String _deviceNodeIdHex = '';
  Uint8List _deviceX25519Pk = Uint8List(0);
  Uint8List _deviceMlKemPk = Uint8List(0);
  Uint8List _userEd25519Pk = Uint8List(0);
  Uint8List _foundingEd25519Pk = Uint8List(0);
  String _displayName = '';
  int _port = 0;
  /// §22.7 — initial value `searching`, NOT `ready`. Before the first
  /// answer of the daemon this client knows nothing; the cautious
  /// direction is the only one that silently opens no gate.
  String _readinessState = 'searching';

  // §25.4: the partner numbers by direction. Initial value 0 and not a
  // substitute computed from `peerCount` — as long as the daemon has
  // reported nothing, "zero known" is the truth, and a surrogate would be
  // exactly the defect that `smoke_ipc_interface_completeness.dart` looks for.
  int _syncPartnersOutbound = 0;
  int _syncPartnersInbound = 0;
  int _independentSyncPartners = 0;
  int _reachableResponsibleRelays = 0;

  /// §24.4.2 — data saver mode, transmitted by the daemon.
  ///
  /// Initial values `false`/`false` and NO local recomputation: the state
  /// arises in the daemon's cover stream, this process cannot know it
  /// before it has heard it. A substitute value computed here would be
  /// exactly the constant that
  /// `smoke_ipc_interface_completeness.dart` looks for.
  bool _dataSaverActive = false;
  bool _dataSaverLockedBySecure = false;

  /// V4.2 §11.9 — source 4 on/off, transmitted by the daemon (S388). Initial
  /// value as in the host (on); the first state packet overwrites it.
  bool _externalRecordsEnabled = true;

  // ── S373: COVER IN THE OWN NETWORK, ACROSS THE IPC BOUNDARY ────────────
  //
  // Four quantities, because the UI must show four different things and
  // cannot derive them from one another:
  //   * is it currently IN EFFECT (`_lanShapingActive`) — that is the state
  //     that §24.4.2 requires to be visible;
  //   * WHICH segments exist (`_lanSegmentIds`) — empty means "no own
  //     network", and that is a statement of its own;
  //   * for which is there a CONSENT (`_lanSegmentsConsented`)
  //     — not the same as "in effect", a Secure chat overrules it;
  //   * for which COULD one be granted (`_lanSegmentsGrantable`)
  //     — without witnesses there is no button, but the reasoning.
  bool _lanShapingActive = false;
  List<String> _lanSegmentIds = const <String>[];
  List<String> _lanSegmentsConsented = const <String>[];
  List<String> _lanSegmentsGrantable = const <String>[];

  /// Reads the four quantities from a state packet. A missing entry leaves
  /// the previous value standing — the same pattern as with the
  /// neighbouring lines, so that a partial packet deletes nothing.
  void _readLanShaping(Map<String, dynamic> d) {
    _lanShapingActive = d['lanShapingActive'] as bool? ?? _lanShapingActive;
    final ids = d['lanSegmentIds'];
    if (ids is List) _lanSegmentIds = ids.whereType<String>().toList();
    final con = d['lanSegmentsConsented'];
    if (con is List) _lanSegmentsConsented = con.whereType<String>().toList();
    final gr = d['lanSegmentsGrantable'];
    if (gr is List) _lanSegmentsGrantable = gr.whereType<String>().toList();
  }
  int _peerCount = 0;
  int _confirmedPeerCount = 0;
  int _reachablePeerCount = 0;
  bool _hasPortMapping = false;
  bool _mobileFallbackActive = false;
  int _fragmentCount = 0;
  bool _isRunning = false;
  String? _profilePictureBase64;
  String? _profileDescription;
  bool _isGuardianSetUp = false;

  @override
  final Map<String, Conversation> conversations = {};
  List<ContactInfo> _acceptedContacts = [];
  List<ContactInfo> _pendingContacts = [];
  List<ContactInfo> _pendingOutgoingContacts = [];
  List<ContactInfo> _storedForDeliveryContacts = [];

  // Cached call state
  CallInfo? _currentCall;

  // Typing indicator state
  final Set<String> _typingContacts = {};
  List<PeerSummary> _peerSummaries = [];

  // Cached groups
  final Map<String, GroupInfo> _groups = {};

  // Cached channels
  final Map<String, ChannelInfo> _channels = {};

  // Cached identities list
  List<Map<String, dynamic>> _identities = [];

  /// Unread message counts per identity (identityId → count).
  /// Tracks incoming messages for non-active identities.
  final Map<String, int> identityUnreadCounts = {};

  /// Callback for GUI navigation actions triggered via IPC.
  void Function(Map<String, dynamic> data)? onGuiAction;

  // Callbacks
  @override
  void Function()? onStateChanged;
  @override
  void Function(String conversationId, UiMessage message)? onNewMessage;
  @override
  void Function(String nodeIdHex, String displayName)? onContactRequestReceived;
  @override
  void Function(String nodeIdHex)? onContactAccepted;
  @override
  void Function(String groupIdHex, String groupName)? onGroupInviteReceived;
  @override
  void Function(String channelIdHex, String channelName)? onChannelInviteReceived;
  @override
  void Function(CallInfo call)? onIncomingCall;
  @override
  void Function(CallInfo call)? onCallAccepted;
  @override
  void Function(CallInfo call, String reason)? onCallRejected;
  @override
  void Function(CallInfo call)? onCallEnded;

  IpcClient({required this.socketPath});

  bool get isConnected => _connected;
  List<Map<String, dynamic>> get identities => _identities;

  /// Connect to the daemon's IPC socket.
  /// Linux/macOS: Unix Domain Socket at socketPath.
  /// Windows: TCP loopback — port and auth token read from cleona.port file.
  Future<bool> connect() async {
    try {
      if (Platform.isWindows) {
        final portFile = File(socketPath.replaceAll('.sock', '.port'));
        if (!portFile.existsSync()) return false;
        final contents = portFile.readAsStringSync().trim();
        final parts = contents.split(':');
        final port = int.parse(parts[0]);
        final token = parts.length > 1 ? parts[1] : null;
        _socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
        // Authenticate with shared secret before any IPC traffic
        if (token != null) {
          _socket!.write('${jsonEncode({"type": "auth", "token": token})}\n');
        }
      } else {
        _socket = await Socket.connect(
          InternetAddress(socketPath, type: InternetAddressType.unix),
          0,
        );
      }
      _connected = true;
      _attachSocketListener();

      // Fetch initial state. Apply a hard timeout so a half-open socket
      // (kernel `bind()` happened, but the daemon's accept-loop hasn't started
      // serving yet — observed during PQ keygen on slow VMs) cannot leave the
      // GUI in a deaf "_connected=true but no responses" state. On timeout,
      // tear the connection down and let the caller fall through to
      // `_scheduleRetryConnect()`.
      try {
        await refreshState().timeout(const Duration(seconds: 5));
      } on TimeoutException {
        _connected = false;
        try { _socket?.destroy(); } catch (_) {}
        _socket = null;
        return false;
      }
      return true;
    } catch (e) {
      _connected = false;
      return false;
    }
  }

  void _attachSocketListener() {
    // New connection, new recipient: a daemon restarted in the meantime
    // no longer knows the reported language. Without this reset its tray
    // would stay on the system language, because the client would
    // consider the language "already reported".
    _reportedLocale = null;
    _socket!.cast<List<int>>().transform(utf8.decoder).listen(
      _onData,
      onError: (e) => _handleDisconnect('error: $e'),
      onDone: () => _handleDisconnect('done'),
    );
  }

  /// Transient socket blips (systemd restart, kernel scheduling, a brief
  /// ip-monitor pause) otherwise tear the GUI down unnecessarily. Retry the
  /// connect up to 3 times with a 500 ms / 1 s / 2 s backoff before giving
  /// up and firing [onDaemonDied].
  bool _reconnecting = false;
  Future<void> _handleDisconnect(String reason) async {
    if (_reconnecting) return;
    _reconnecting = true;
    _connected = false;
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        await Future<void>.delayed(
            Duration(milliseconds: 500 * (1 << attempt)));
        try {
          if (Platform.isWindows) {
            final portFile =
                File(socketPath.replaceAll('.sock', '.port'));
            if (!portFile.existsSync()) continue;
            final contents = portFile.readAsStringSync().trim();
            final parts = contents.split(':');
            final port = int.parse(parts[0]);
            final token = parts.length > 1 ? parts[1] : null;
            _socket = await Socket.connect(
                InternetAddress.loopbackIPv4, port);
            if (token != null) {
              _socket!.write(
                  '${jsonEncode({"type": "auth", "token": token})}\n');
            }
          } else {
            _socket = await Socket.connect(
              InternetAddress(socketPath,
                  type: InternetAddressType.unix),
              0,
            );
          }
          _connected = true;
          _attachSocketListener();
          // Resync state after reconnect so UI doesn't lag behind any
          // changes that landed while the socket was down.
          await refreshState();
          return;
        } catch (_) {
          // try next iteration
        }
      }
      // All 3 fast-retries exhausted. Distinguish "daemon really gone"
      // (lock file missing or PID dead → onDaemonDied) from "daemon alive
      // but IPC unreachable" (mid-restart, slow PQ keygen → onIpcStalled).
      // The 3-attempt × 3.5 s backoff is too short for PQ keygen on slow
      // VMs (15–30 s observed); on a transient stall we want the higher-
      // level `_scheduleRetryConnect` (5 s × 24 = 2 min window) to take over,
      // not an immediate `exit(0)`.
      if (_isDaemonProcessAlive()) {
        onIpcStalled?.call();
      } else {
        onDaemonDied?.call();
      }
    } finally {
      _reconnecting = false;
    }
  }

  /// Is the daemon process still running according to the lock file?
  /// Best-effort: missing lock file → daemon gone; lock-file PID alive → daemon up.
  bool _isDaemonProcessAlive() {
    final lockPath = socketPath.replaceAll(
        RegExp(r'cleona\.sock$'), 'cleona.lock');
    final lockFile = File(lockPath);
    if (!lockFile.existsSync()) return false;

    int? pid;
    try {
      pid = int.tryParse(lockFile.readAsStringSync().trim());
    } catch (_) {
      // Windows: daemon holds cleona.lock with mandatory exclusive lock
      // (LockFileEx) that blocks reads → readAsStringSync throws. Fall
      // back to cleona.pid which is not locked.
      try {
        final pidPath = socketPath.replaceAll(
            RegExp(r'cleona\.sock$'), 'cleona.pid');
        pid = int.tryParse(File(pidPath).readAsStringSync().trim());
      } catch (_) {}
      if (pid == null || pid <= 0) return true; // lock exists → daemon owns it
    }
    if (pid == null || pid <= 0) return false;

    try {
      if (Platform.isLinux || Platform.isMacOS) {
        return Process.runSync('kill', ['-0', '$pid']).exitCode == 0;
      }
      if (Platform.isWindows) {
        // Avoid Process.runSync('tasklist') — it costs 0.5-2s and blocks
        // the Flutter UI isolate on every reconnect attempt (5s timer).
        // Instead check if the lock file is still exclusively held by the
        // daemon. If opening for write throws (ERROR_SHARING_VIOLATION),
        // the daemon is alive.
        try {
          final f = File(lockPath).openSync(mode: FileMode.writeOnlyAppend);
          f.closeSync();
          return false; // lock not held → daemon dead
        } on FileSystemException {
          return true; // lock held → daemon alive
        }
      }
    } catch (_) {
      return true;
    }
    return true;
  }

  void _onData(String data) {
    _buffer.write(data);
    var content = _buffer.toString();
    while (content.contains('\n')) {
      final idx = content.indexOf('\n');
      final line = content.substring(0, idx).trim();
      content = content.substring(idx + 1);
      if (line.isNotEmpty) {
        _handleMessage(line);
      }
    }
    _buffer.clear();
    if (content.isNotEmpty) _buffer.write(content);
  }

  void _handleMessage(String line) {
    try {
      final msg = parseIpcMessage(line);
      if (msg is IpcResponse) {
        final completer = _pendingRequests.remove(msg.id);
        if (completer != null) {
          completer.complete(msg);
        }
      } else if (msg is IpcEvent) {
        _handleEvent(msg);
      }
    } catch (e) {
      // Ignore parse errors
    }
  }

  void _handleEvent(IpcEvent event) {
    // Binary updates live on the primary identity's service — never filter.
    final isGlobalEvent = event.event == 'update_state_changed' ||
        event.event == 'update_available';
    // Event for a different identity — track unread counts, handle calls
    if (!isGlobalEvent &&
        event.identityId != null &&
        activeIdentityId != null &&
        event.identityId != activeIdentityId) {
      if (event.event == 'incoming_call') {
        final call = CallInfo.fromJson(event.data);
        _currentCall = call;
        onIncomingCall?.call(call);
        onStateChanged?.call();
      } else if (event.event == 'incoming_group_call') {
        final call = GroupCallInfo.fromJson(event.data);
        _currentGroupCall = call;
        onIncomingGroupCall?.call(call);
        onStateChanged?.call();
      } else if (event.event == 'new_message') {
        // Track unread for non-active identity
        final msgData = event.data['message'] as Map<String, dynamic>?;
        final isOutgoing = msgData?['isOutgoing'] as bool? ?? true;
        if (!isOutgoing) {
          identityUnreadCounts[event.identityId!] =
              (identityUnreadCounts[event.identityId!] ?? 0) + 1;
          onStateChanged?.call(); // Trigger UI refresh for badge update
        }
      } else if (event.event == 'contact_request' ||
                 event.event == 'contact_accepted') {
        // V3.1.52: Track pending CR / acceptance for non-active identity so
        // the badge counter updates and switchIdentity shows fresh state.
        identityUnreadCounts[event.identityId!] =
            (identityUnreadCounts[event.identityId!] ?? 0) + 1;
        onStateChanged?.call();
      }
      return;
    }

    switch (event.event) {
      case 'state_changed':
        // Lightweight notification — update basic fields, schedule coalesced refresh
        _readinessState =
            event.data['readiness'] as String? ?? _readinessState;
        _syncPartnersOutbound =
            event.data['syncPartnersOutbound'] as int? ?? _syncPartnersOutbound;
        _syncPartnersInbound =
            event.data['syncPartnersInbound'] as int? ?? _syncPartnersInbound;
        _independentSyncPartners = event.data['independentSyncPartners']
                as int? ??
            _independentSyncPartners;
        _reachableResponsibleRelays =
            event.data['reachableResponsibleRelays'] as int? ??
                _reachableResponsibleRelays;
        _dataSaverActive =
            event.data['dataSaverActive'] as bool? ?? _dataSaverActive;
        _dataSaverLockedBySecure = event.data['dataSaverLockedBySecure']
                as bool? ??
            _dataSaverLockedBySecure;
        _externalRecordsEnabled =
            event.data['externalRecordsEnabled'] as bool? ??
                _externalRecordsEnabled;
        _readLanShaping(event.data);
        _peerCount = event.data['peerCount'] as int? ?? _peerCount;
        _confirmedPeerCount = event.data['confirmedPeerCount'] as int? ?? _confirmedPeerCount;
        _reachablePeerCount = event.data['reachablePeerCount'] as int? ?? _reachablePeerCount;
        _hasPortMapping = event.data['hasPortMapping'] as bool? ?? _hasPortMapping;
        _hasSessionConfirmedPeers = event.data['hasSessionConfirmedPeers']
                as bool? ??
            _hasSessionConfirmedPeers;
        _mobileFallbackActive = event.data['mobileFallbackActive'] as bool? ?? _mobileFallbackActive;
        _isRunning = event.data['isRunning'] as bool? ?? _isRunning;
        onStateChanged?.call();
        _scheduleRefresh();
        break;
      case 'new_message':
        final convId = event.data['conversationId'] as String;
        final msgData = event.data['message'] as Map<String, dynamic>;
        final message = UiMessage.fromJson(msgData);
        // Update local state. Mirror daemon's `_addMessageToConversation`
        // pattern (cleona_service.dart:4400 — `conversations.putIfAbsent`):
        // if the conversation doesn't exist yet on the GUI side because the
        // initial `refreshState()` is still pending or this is a brand-new
        // contact whose conversation hasn't been pulled, create a placeholder
        // entry so the incoming message is not silently dropped from the
        // GUI cache. Display fields (displayName, profile picture) get
        // populated by the next `refreshState()` triggered via _scheduleRefresh.
        final conv = conversations.putIfAbsent(convId, () => Conversation(
          id: convId,
          displayName: convId.length >= 8 ? convId.substring(0, 8) : convId,
        ));
        conv.messages.add(message);
        conv.lastActivity = message.timestamp;
        if (!message.isOutgoing) conv.unreadCount++;
        onNewMessage?.call(convId, message);
        onStateChanged?.call();
        // Pull authoritative state so the placeholder gets the real
        // displayName / profile picture / config from the daemon.
        _scheduleRefresh();
        break;
      case 'read_receipt':
        final rrConvId = event.data['conversationId'] as String;
        final rrMsgId = event.data['messageId'] as String;
        final rrConv = conversations[rrConvId];
        if (rrConv != null) {
          for (final m in rrConv.messages) {
            if (m.id == rrMsgId && m.isOutgoing) {
              // S390: read marker, not a delivery state (§9.1 lists four).
              m.readByRecipient = true;
              m.readAt ??= DateTime.now();
              break;
            }
          }
        }
        onStateChanged?.call();
        break;
      case 'contact_request':
        onContactRequestReceived?.call(
          event.data['nodeIdHex'] as String,
          event.data['displayName'] as String,
        );
        refreshState();
        break;
      case 'contact_accepted':
        onContactAccepted?.call(event.data['nodeIdHex'] as String);
        refreshState();
        break;
      case 'group_invite':
        final gid = event.data['groupIdHex'] as String;
        final gname = event.data['groupName'] as String;
        onGroupInviteReceived?.call(gid, gname);
        refreshState();
        break;
      case 'channel_invite':
        final chid = event.data['channelIdHex'] as String;
        final chname = event.data['channelName'] as String;
        onChannelInviteReceived?.call(chid, chname);
        refreshState();
        break;
      case 'jury_request':
        // AP-5a: the list itself also rides getStateSnapshot(); this case only
        // makes it IMMEDIATE and finally fires the declared callback. Merging
        // by juryId (not append) keeps a repeated event idempotent and keeps
        // the entry consistent with what the next snapshot will bring.
        final jr = JuryRequest.fromJson(Map<String, dynamic>.from(event.data));
        final merged = List<JuryRequest>.from(_pendingJuryRequests);
        final at = merged.indexWhere((r) => r.juryId == jr.juryId);
        if (at >= 0) {
          merged[at] = jr;
        } else {
          merged.add(jr);
        }
        _pendingJuryRequests = List<JuryRequest>.unmodifiable(merged);
        onJuryRequestReceived?.call(jr);
        onStateChanged?.call();
        break;
      case 'restore_progress':
        final phase = event.data['phase'] as int;
        final contactsRestored = event.data['contactsRestored'] as int? ?? 0;
        final messagesRestored = event.data['messagesRestored'] as int? ?? 0;
        onRestoreProgress?.call(phase, contactsRestored, messagesRestored);
        refreshState();
        break;
      case 'incoming_call':
        _currentCall = CallInfo.fromJson(event.data);
        onIncomingCall?.call(_currentCall!);
        onStateChanged?.call();
        break;
      case 'call_accepted':
        _currentCall = CallInfo.fromJson(event.data);
        onCallAccepted?.call(_currentCall!);
        onStateChanged?.call();
        break;
      case 'call_rejected':
        final call = CallInfo.fromJson(event.data);
        final reason = event.data['reason'] as String? ?? 'rejected';
        _currentCall = null;
        onCallRejected?.call(call, reason);
        onStateChanged?.call();
        break;
      case 'call_ended':
        final call = CallInfo.fromJson(event.data);
        _currentCall = null;
        onCallEnded?.call(call);
        onStateChanged?.call();
        break;
      case 'incoming_group_call':
        _currentGroupCall = GroupCallInfo.fromJson(event.data);
        onIncomingGroupCall?.call(_currentGroupCall!);
        onStateChanged?.call();
        break;
      case 'group_call_started':
        _currentGroupCall = GroupCallInfo.fromJson(event.data);
        onGroupCallStarted?.call(_currentGroupCall!);
        onStateChanged?.call();
        break;
      case 'group_call_ended':
        final call = GroupCallInfo.fromJson(event.data);
        _currentGroupCall = null;
        onGroupCallEnded?.call(call);
        onStateChanged?.call();
        break;
      case 'gui_action':
        onGuiAction?.call(event.data);
        break;
      case 'calendar_invite':
        final senderHex = event.data['senderNodeIdHex'] as String;
        final eventId = event.data['eventId'] as String;
        final title = event.data['title'] as String;
        onCalendarInviteReceived?.call(senderHex, eventId, title);
        fetchCalendarEvents(); // Refresh cache
        onStateChanged?.call();
        break;
      case 'calendar_rsvp':
        final eventId = event.data['eventId'] as String;
        final responderHex = event.data['responderNodeIdHex'] as String;
        final statusIdx = event.data['status'] as int? ?? 0;
        final status = RsvpStatus.values[statusIdx.clamp(0, RsvpStatus.values.length - 1)];
        onCalendarRsvpReceived?.call(eventId, responderHex, status);
        onStateChanged?.call();
        break;
      case 'calendar_event_updated':
        final eventId = event.data['eventId'] as String;
        onCalendarEventUpdated?.call(eventId);
        fetchCalendarEvents(); // Refresh cache
        onStateChanged?.call();
        break;
      case 'calendar_reminder':
        final eventId = event.data['eventId'] as String;
        final title = event.data['title'] as String;
        final minutesBefore = event.data['minutesBefore'] as int;
        onCalendarReminderDue?.call(eventId, title, minutesBefore);
        break;
      case 'calendar_sync_completed':
        onCalendarSyncCompleted?.call(event.data);
        break;
      case 'calendar_sync_google_connected':
        onCalendarSyncGoogleConnected?.call(
            event.data['accountEmail'] as String? ?? '');
        break;
      case 'calendar_sync_google_error':
        onCalendarSyncGoogleError?.call(
            event.data['error'] as String? ?? 'unknown error');
        break;
      case 'calendar_sync_conflict_pending':
        onCalendarSyncConflictPending?.call(event.data);
        break;
      case 'poll_created':
        final pollId = event.data['pollId'] as String? ?? '';
        final groupId = event.data['groupId'] as String? ?? '';
        final question = event.data['question'] as String? ?? '';
        onPollCreated?.call(pollId, groupId, question);
        fetchPolls(groupIdHex: groupId);
        onStateChanged?.call();
        break;
      case 'poll_tally_updated':
        final pollId = event.data['pollId'] as String? ?? '';
        onPollTallyUpdated?.call(pollId);
        fetchPolls();
        onStateChanged?.call();
        break;
      case 'poll_state_changed':
        final pollId = event.data['pollId'] as String? ?? '';
        onPollStateChanged?.call(pollId);
        fetchPolls();
        onStateChanged?.call();
        break;
      case 'devices_updated':
        final devList = event.data['devices'] as List<dynamic>? ?? const [];
        _devices = devList
            .map((d) => DeviceRecord.fromJson(d as Map<String, dynamic>))
            .toList();
        _localDeviceId = event.data['localDeviceId'] as String? ?? _localDeviceId;
        onDevicesUpdated?.call();
        onStateChanged?.call();
        break;
      case 'key_rotation_pending_contact':
        final contactHex = event.data['contactNodeIdHex'] as String? ?? '';
        final pendingCount = (event.data['pendingCount'] as num?)?.toInt() ?? 0;
        onKeyRotationPendingExpired?.call(contactHex, pendingCount);
        break;
      case 'contact_identity_rotated':
        // SR-1 (§7.4b step 6 / §8.3): a contact emergency-rotated; the
        // verification level was reset. Surface the key-change warning.
        final contactHex = event.data['contactNodeIdHex'] as String? ?? '';
        final displayName = event.data['displayName'] as String? ?? '';
        final wasVerified = event.data['wasVerified'] as bool? ?? false;
        onContactIdentityRotated?.call(contactHex, displayName, wasVerified);
        onStateChanged?.call();
        break;
      case 'contact_restore_detected':
        // H-2 (§6.3.5): a contact restored their identity (new device).
        final contactHex = event.data['contactNodeIdHex'] as String? ?? '';
        final displayName = event.data['displayName'] as String? ?? '';
        final keyChanged = event.data['identityKeyChanged'] as bool? ?? false;
        onContactRestoreDetected?.call(contactHex, displayName, keyChanged);
        onStateChanged?.call();
        break;
      case 'rotation_co_auth_warning':
        // §7.5: rotation without device quorum — possible Primary theft.
        final coAuthContactHex = event.data['contactNodeIdHex'] as String? ?? '';
        final coAuthDisplayName = event.data['displayName'] as String? ?? '';
        final tokensPresent = event.data['tokensPresent'] as int? ?? 0;
        final tokensRequired = event.data['tokensRequired'] as int? ?? 0;
        onRotationCoAuthWarning?.call(
            coAuthContactHex, coAuthDisplayName, tokensPresent, tokensRequired);
        onStateChanged?.call();
        break;
      case 'rotation_rejection_alert':
        // §7.5: a linked device actively rejected a rotation.
        final rejectContactHex = event.data['contactNodeIdHex'] as String? ?? '';
        final rejectDisplayName = event.data['displayName'] as String? ?? '';
        onRotationRejectionAlert?.call(rejectContactHex, rejectDisplayName);
        onStateChanged?.call();
        break;
      case 'nat_wizard_triggered':
        // §27.9: daemon detected sustained relay-only state. GUI decides
        // whether to show the dialog (home_screen listens).
        onNatWizardTriggered?.call();
        break;
      case 'nat_wizard_user_requested':
        // User-initiated (connection-icon tap) — bypass the GUI's
        // auto-trigger latch so the dialog always opens on demand.
        onNatWizardUserRequested?.call();
        break;
      case 'device_pair_request':
        final pairDeviceHex = event.data['deviceIdHex'] as String? ?? '';
        onDevicePairRequest?.call(pairDeviceHex);
        break;
      case 'rotation_approval_request':
        // §7.5: the Primary wants a Device-Sig countersignature — for an
        // Emergency Key Rotation or for a device-set change, told apart by
        // `approvalKind`. The GUI must ask the user, naming the right
        // occasion; ignoring the event means nothing is sent back, which is
        // the safe default.
        final rotationHashHex = event.data['rotationHashHex'] as String? ?? '';
        final rotationRequesterHex =
            event.data['requestingDeviceIdHex'] as String? ?? '';
        // A daemon that predates the field sends no `approvalKind`;
        // `fromWireName` maps that to `keyRotation`, which is what such a
        // daemon could only ever have meant.
        final approvalKind = RotationApprovalKind.fromWireName(
            event.data['approvalKind'] as String?);
        final newDeviceNodeIdHexes =
            (event.data['newDeviceNodeIdHexes'] as List<dynamic>? ?? const [])
                .whereType<String>()
                .toList();
        if (rotationHashHex.isNotEmpty) {
          onRotationApprovalRequest?.call(rotationHashHex,
              rotationRequesterHex, approvalKind, newDeviceNodeIdHexes);
        }
        break;
      case 'update_available':
        final manifestData = event.data['manifest'] as Map<String, dynamic>?;
        final inNetwork = event.data['inNetworkAvailable'] as bool? ?? false;
        if (manifestData != null) {
          final manifest = UpdateManifest.fromJson(manifestData);
          if (manifest != null) {
            onUpdateAvailable?.call(manifest, inNetwork);
          }
        }
        break;
      case 'update_state_changed':
        final stateIdx = event.data['state'] as int? ?? 0;
        final progress = (event.data['progress'] as num?)?.toDouble() ?? 0.0;
        if (stateIdx >= 0 && stateIdx < BinaryUpdateState.values.length) {
          onUpdateStateChanged?.call(BinaryUpdateState.values[stateIdx], progress);
        }
        break;
    }
  }

  void _applyStateSnapshot(Map<String, dynamic> state) {
    _nodeIdHex = state['nodeIdHex'] as String? ?? _nodeIdHex;
    _profileDir = state['profileDir'] as String? ?? _profileDir;
    _deviceNodeIdHex = state['deviceNodeIdHex'] as String? ?? _deviceNodeIdHex;
    final dxkB64 = state['deviceX25519PkB64'] as String? ?? state['dxkB64'] as String?;
    if (dxkB64 != null && dxkB64.isNotEmpty) {
      try { _deviceX25519Pk = base64Decode(dxkB64); } catch (_) {}
    }
    final dmkB64 = state['deviceMlKemPkB64'] as String? ?? state['dmkB64'] as String?;
    if (dmkB64 != null && dmkB64.isNotEmpty) {
      try { _deviceMlKemPk = base64Decode(dmkB64); } catch (_) {}
    }
    final epB64 = state['userEd25519PkB64'] as String?;
    if (epB64 != null && epB64.isNotEmpty) {
      try { _userEd25519Pk = base64Decode(epB64); } catch (_) {}
    }
    // SR-2: founding anchor; old daemons without the field → getter falls
    // back to ep (correct for never-rotated identities, which is all a
    // pre-SR-2 daemon can host under the stable-anchor model).
    final fpB64 = state['foundingEd25519PkB64'] as String?;
    if (fpB64 != null && fpB64.isNotEmpty) {
      try { _foundingEd25519Pk = base64Decode(fpB64); } catch (_) {}
    }
    _displayName = state['displayName'] as String? ?? _displayName;
    _port = state['port'] as int? ?? _port;
    _readinessState = state['readiness'] as String? ?? _readinessState;
    _syncPartnersOutbound =
        state['syncPartnersOutbound'] as int? ?? _syncPartnersOutbound;
    _syncPartnersInbound =
        state['syncPartnersInbound'] as int? ?? _syncPartnersInbound;
    _independentSyncPartners =
        state['independentSyncPartners'] as int? ?? _independentSyncPartners;
    _dataSaverActive = state['dataSaverActive'] as bool? ?? _dataSaverActive;
    _dataSaverLockedBySecure =
        state['dataSaverLockedBySecure'] as bool? ?? _dataSaverLockedBySecure;
    _externalRecordsEnabled =
        state['externalRecordsEnabled'] as bool? ?? _externalRecordsEnabled;
    _readLanShaping(state);
    _peerCount = state['peerCount'] as int? ?? _peerCount;
    _confirmedPeerCount = state['confirmedPeerCount'] as int? ?? _confirmedPeerCount;
    _reachablePeerCount = state['reachablePeerCount'] as int? ?? _reachablePeerCount;
    // AP-5a: sticky — a daemon without the field must not clear the latch.
    _hasSessionConfirmedPeers =
        state['hasSessionConfirmedPeers'] as bool? ?? _hasSessionConfirmedPeers;
    final startedMs = state['nodeStartedAtMs'] as int?;
    if (startedMs != null) {
      _nodeStartedAt = DateTime.fromMillisecondsSinceEpoch(startedMs);
    }
    _mobileFallbackActive = state['mobileFallbackActive'] as bool? ?? _mobileFallbackActive;
    _fragmentCount = state['fragmentCount'] as int? ?? _fragmentCount;
    _isRunning = state['isRunning'] as bool? ?? _isRunning;
    _isLinkedDevice = state['isLinkedDevice'] as bool? ?? _isLinkedDevice;
    final lds = state['linkedDeviceStatus'] as Map<String, dynamic>?;
    if (lds != null) _cachedLinkedDeviceStatus = LinkedDeviceStatus.fromJson(lds);
    _profilePictureBase64 = state['profilePicture'] as String?;
    _profileDescription = state['profileDescription'] as String?;
    _isGuardianSetUp = state['isGuardianSetUp'] as bool? ?? false;
    // AP-5a: absent on a pre-AP-5a daemon -> keep the previous list rather
    // than clearing it, so an older daemon degrades to today's empty list
    // instead of dropping entries the event path may have delivered.
    final juryList = state['pendingJuryRequests'] as List<dynamic>?;
    if (juryList != null) {
      _pendingJuryRequests = juryList
          .map((e) => JuryRequest.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
    }
    final ms = state['mediaSettings'] as Map<String, dynamic>?;
    if (ms != null) _mediaSettings = MediaSettings.fromJson(ms);
    final lps = state['linkPreviewSettings'] as Map<String, dynamic>?;
    if (lps != null) _linkPreviewSettings = LinkPreviewSettings.fromJson(lps);
    final mim = state['multiInterfaceMode'] as String?;
    if (mim != null) _multiInterfaceMode = MultiInterfaceMode.modeFromString(mim);
    final ns = state['notificationSettings'] as Map<String, dynamic>?;
    if (ns != null) _notificationSoundService.updateSettings(NotificationSettings.fromJson(ns));

    // Network info for QR code generation
    final ips = state['localIps'] as List<dynamic>?;
    if (ips != null) _localIps = ips.cast<String>();
    _publicIp = state['publicIp'] as String?;

    // Identity-derivation skew (see HdWallet.identityDerivationFingerprint).
    // A daemon that predates the field leaves this `unknown` — absence is not
    // disagreement, and reporting it as one would cry wolf on every rollout
    // where the daemon lags by one build.
    final daemonFp = state['identityDerivationFp'] as String?;
    _identityDerivationSkew = IdentityDerivationSkew.classify(daemonFp);
    if (_identityDerivationSkew == IdentityDerivationSkew.mismatch) {
      // Once, not per snapshot: state_changed arrives continuously and this
      // condition does not clear by itself — it needs a redeploy.
      if (!_skewLoggedOnce) {
        _skewLoggedOnce = true;
        CLogger.get('ipc-client', profileDir: profileDir).error(
            'Identity derivation skew: daemon mints UserIDs as $daemonFp, this '
            'GUI as ${HdWallet.identityDerivationFingerprint}. The two halves '
            'of the app are from different builds; every UserID the daemon '
            'reports is one this GUI cannot reproduce. No ContactSeed can be '
            'vouched for until both halves are redeployed together.');
      }
    }
    _publicPort = state['publicPort'] as int?;

    // Multi-Device (§26)
    final devList = state['devices'] as List<dynamic>?;
    if (devList != null) {
      _devices = devList
          .map((d) => DeviceRecord.fromJson(d as Map<String, dynamic>))
          .toList();
    }
    _localDeviceId = state['localDeviceId'] as String? ?? _localDeviceId;
    // §24.4.3: the transition state of the device lockouts. If the field
    // is missing, the daemon is older than this change — then KEEP the
    // previous list instead of emptying it: in the display an empty list
    // means "no transition is running", and that would be a statement an
    // old daemon never made.
    final lockJson = state['deviceLockouts'] as List<dynamic>?;
    if (lockJson != null) {
      _deviceLockouts = lockJson
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
    }

    // Update active identity
    if (state['activeIdentityId'] != null) {
      activeIdentityId = state['activeIdentityId'] as String;
    }

    // Update identities list
    final idList = state['identities'] as List<dynamic>?;
    if (idList != null) {
      _identities = idList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }

    // Initialize unread counts from server snapshot (don't overwrite higher local counts)
    final serverUnread = state['identityUnreadCounts'] as Map<String, dynamic>?;
    if (serverUnread != null) {
      for (final entry in serverUnread.entries) {
        final serverCount = entry.value as int? ?? 0;
        final localCount = identityUnreadCounts[entry.key] ?? 0;
        if (serverCount > localCount) {
          identityUnreadCounts[entry.key] = serverCount;
        }
      }
    }

    // Catch up on pending update state from daemon
    final manifestData = state['updateManifest'] as Map<String, dynamic>?;
    if (manifestData != null) {
      final manifest = UpdateManifest.fromJson(manifestData);
      if (manifest != null) {
        final stateIdx = state['updateState'] as int? ?? 0;
        final progress = (state['updateProgress'] as num?)?.toDouble() ?? 0.0;
        final inNetwork = stateIdx >= BinaryUpdateState.downloading.index;
        onUpdateAvailable?.call(manifest, inNetwork);
        if (stateIdx >= 0 && stateIdx < BinaryUpdateState.values.length) {
          onUpdateStateChanged?.call(BinaryUpdateState.values[stateIdx], progress);
        }
      }
    }

    // Update conversations
    final convMap = state['conversations'] as Map<String, dynamic>?;
    if (convMap != null) {
      conversations.clear();
      for (final entry in convMap.entries) {
        conversations[entry.key] = Conversation.fromJson(
          {'id': entry.key, ...(entry.value as Map<String, dynamic>)},
        );
      }
    }

    // Update contacts
    final accepted = state['acceptedContacts'] as List<dynamic>?;
    if (accepted != null) {
      _acceptedContacts = accepted
          .map((c) => ContactInfo.fromJson(c as Map<String, dynamic>))
          .toList();
    }

    final pending = state['pendingContacts'] as List<dynamic>?;
    if (pending != null) {
      _pendingContacts = pending
          .map((c) => ContactInfo.fromJson(c as Map<String, dynamic>))
          .toList();
    }

    final pendingOut = state['pendingOutgoingContacts'] as List<dynamic>?;
    if (pendingOut != null) {
      _pendingOutgoingContacts = pendingOut
          .map((c) => ContactInfo.fromJson(c as Map<String, dynamic>))
          .toList();
    }

    final storedForDelivery =
        state['storedForDeliveryContacts'] as List<dynamic>?;
    if (storedForDelivery != null) {
      _storedForDeliveryContacts = storedForDelivery
          .map((c) => ContactInfo.fromJson(c as Map<String, dynamic>))
          .toList();
    }

    // Update groups
    final groupsData = state['groups'] as Map<String, dynamic>?;
    if (groupsData != null) {
      _groups.clear();
      for (final e in groupsData.entries) {
        _groups[e.key] = GroupInfo.fromJson(e.value as Map<String, dynamic>);
      }
    }

    // Update channels
    final channelsData = state['channels'] as Map<String, dynamic>?;
    if (channelsData != null) {
      _channels.clear();
      for (final e in channelsData.entries) {
        _channels[e.key] = ChannelInfo.fromJson(e.value as Map<String, dynamic>);
      }
    }

    final callData = state['currentCall'] as Map<String, dynamic>?;
    _currentCall = callData != null ? CallInfo.fromJson(callData) : null;

    final groupCallData = state['currentGroupCall'] as Map<String, dynamic>?;
    _currentGroupCall = groupCallData != null ? GroupCallInfo.fromJson(groupCallData) : null;

    final peers = state['peerSummaries'] as List<dynamic>?;
    if (peers != null) {
      _peerSummaries = peers
          .map((p) => PeerSummary.fromJson(p as Map<String, dynamic>))
          .toList();
    }

    // §11/G-11: the start peer candidates of the NODE. If the key is
    // missing, the last state stays instead of jumping to empty — a
    // partial snapshot must not rob the QR code of its `s=`.
    final candidates = state['entrySeedCandidates'] as List<dynamic>?;
    if (candidates != null) {
      _entrySeedCandidates = <EntrySeedCandidate>[
        for (final k in candidates)
          if (k is Map<String, dynamic>)
            EntrySeedCandidate(
              nodeIdHex: k['n'] as String? ?? '',
              addresses: (k['a'] as List<dynamic>? ?? const [])
                  .whereType<String>()
                  .toList(growable: false),
              expiryMs: k['x'] as int? ?? 0,
            ),
      ];
    }

    // Update typing contacts
    final typing = state['typingContacts'] as List<dynamic>?;
    if (typing != null) {
      _typingContacts.clear();
      _typingContacts.addAll(typing.cast<String>());
    }
  }

  /// Check if a contact is currently typing.
  bool isContactTyping(String nodeIdHex) => _typingContacts.contains(nodeIdHex);

  /// The language chosen in the GUI, as `main.dart` reports it.
  ///
  /// Owner decision V-10-a = b (09.09.2026): the daemon is to show the
  /// tray state text in THIS language, not in that of the operating
  /// system.
  String? _uiLocale;

  /// What of it has already arrived at the daemon.
  ///
  /// The comparison is the whole reason why no additional traffic arises
  /// here: the field hangs on the next request that the client makes
  /// anyway, and after that on none any more. On a new connection it is
  /// reset ([_attachSocketListener]) — a newly started daemon does not
  /// have the old state.
  String? _reportedLocale;

  String? get uiLocale => _uiLocale;

  /// Reports the GUI language. Costs NOTHING in itself — it travels with
  /// the next request that is due anyway.
  ///
  /// MEASURED LIMIT, explicitly named (price of variant b): until the next
  /// request the tray stays on the old state, and until the first GUI
  /// start on the system language — permanently on a server without a
  /// GUI. That is the accepted price for no round trip of its own and no
  /// timer being added (work rule 5).
  set uiLocale(String? code) {
    if (code == _uiLocale) return;
    _uiLocale = code;
  }

  Future<IpcResponse> _sendRequest(String command, {
    Map<String, dynamic> params = const {},
    String? identityId,
  }) async {
    if (!_connected || _socket == null) {
      return IpcResponse(id: -1, success: false, error: 'Not connected');
    }

    final id = _nextRequestId++;
    // Only as long as the daemon does not yet have the state — after that
    // the field is `null` and the request as long as before.
    final locale = _uiLocale != _reportedLocale ? _uiLocale : null;
    final request = IpcRequest(
      id: id,
      command: command,
      params: params,
      identityId: identityId,
      uiLocale: locale,
    );
    final completer = Completer<IpcResponse>();
    _pendingRequests[id] = completer;

    try {
      _socket!.write(request.toJsonLine());
      // ONLY after the successful write — otherwise a language would count
      // as reported that never left the socket.
      if (locale != null) _reportedLocale = locale;
    } catch (e) {
      _pendingRequests.remove(id);
      return IpcResponse(id: id, success: false, error: '$e');
    }

    // Timeout after 10 seconds
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _pendingRequests.remove(id);
        return IpcResponse(id: id, success: false, error: 'Timeout');
      },
    );
  }

  /// Fetch full state from daemon.
  Timer? _refreshTimer;
  DateTime _lastRefreshAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _refreshDebounce = Duration(seconds: 1);
  static const Duration _refreshMaxStaleness = Duration(seconds: 2);

  /// Debounced refresh: coalesces multiple state_changed events into one
  /// get_state call. B-33: the debounce was reset by every state_changed event,
  /// so a continuous traffic storm could starve refreshState() indefinitely and
  /// leave `conversations` stale. Cap it — once it has been >2s since the last
  /// actual refresh, fire immediately instead of rescheduling.
  void _scheduleRefresh() {
    if (DateTime.now().difference(_lastRefreshAt) >= _refreshMaxStaleness) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
      unawaited(refreshState());
      return;
    }
    _refreshTimer?.cancel();
    _refreshTimer = Timer(_refreshDebounce, () async {
      await refreshState();
    });
  }

  /// Fetch full state from daemon.
  Future<void> refreshState() async {
    _lastRefreshAt = DateTime.now(); // B-33: advance the staleness clock
    final resp = await _sendRequest('get_state');
    if (resp.success) {
      _applyStateSnapshot(resp.data);
      onStateChanged?.call();
    }
  }

  /// Switch to a different identity — instant, no reconnect needed.
  Future<bool> switchIdentity(String identityId) async {
    final resp = await _sendRequest('switch_active', params: {
      'identityId': identityId,
    });
    if (resp.success) {
      activeIdentityId = identityId;
      identityUnreadCounts.remove(identityId); // Clear badge for now-active identity
      _applyStateSnapshot(resp.data);
      onStateChanged?.call();
      return true;
    }
    return false;
  }

  /// Create a new identity at runtime via daemon IPC.
  /// Returns the new identity's nodeIdHex, or null on failure.
  Future<String?> createIdentity(String displayName) async {
    final resp = await _sendRequest('create_identity', params: {
      'displayName': displayName,
    });
    if (resp.success) {
      final newId = resp.data['identityId'] as String?;
      if (newId != null) {
        activeIdentityId = newId;
        _applyStateSnapshot(resp.data);
        onStateChanged?.call();
      }
      return newId;
    }
    return null;
  }

  /// Delete an identity at runtime (stops service, unregisters from node).
  Future<bool> deleteIdentity(String nodeIdHex) async {
    final resp = await _sendRequest('delete_identity', params: {
      'identityId': nodeIdHex,
    });
    if (resp.success) {
      if (activeIdentityId == nodeIdHex) {
        final newActiveId = resp.data['activeIdentityId'] as String?;
        if (newActiveId != null) activeIdentityId = newActiveId;
      }
      _applyStateSnapshot(resp.data);
      onStateChanged?.call();
    }
    return resp.success;
  }

  /// §6.4.3: Recover multi-identity list from DHT registry.
  /// Returns the number of newly created + started identities.
  Future<int> recoverIdentitiesFromRegistry() async {
    final resp = await _sendRequest('recover_identities_from_registry');
    if (resp.success) {
      return resp.data['count'] as int? ?? 0;
    }
    return 0;
  }

  /// List all identities with their status.
  Future<List<Map<String, dynamic>>> listIdentities() async {
    final resp = await _sendRequest('list_identities');
    if (resp.success) {
      final list = resp.data['identities'] as List<dynamic>? ?? [];
      _identities = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      return _identities;
    }
    return [];
  }


  // ── ICleonaService implementation ─────────────────────────────────

  @override
  String get nodeIdHex => _nodeIdHex;
  @override
  String get profileDir => _profileDir;
  @override
  String get deviceNodeIdHex => _deviceNodeIdHex;
  @override
  Uint8List get deviceX25519Pk => _deviceX25519Pk;
  @override
  Uint8List get deviceMlKemPk => _deviceMlKemPk;
  @override
  Uint8List get userEd25519Pk => _userEd25519Pk;
  @override
  Uint8List get foundingEd25519Pk =>
      _foundingEd25519Pk.isNotEmpty ? _foundingEd25519Pk : _userEd25519Pk;
  @override
  String get displayName => _displayName;
  @override
  int get port => _port;
  /// §22.7.2, normative: the same value as in the daemon, fed from the
  /// state — no constant, no `null`, no local recomputation from
  /// `peerCount`. The guard
  /// `smoke_ipc_interface_completeness.dart` checks exactly that.
  @override
  String get readinessState => _readinessState;
  @override
  int get syncPartnersOutbound => _syncPartnersOutbound;
  @override
  int get syncPartnersInbound => _syncPartnersInbound;
  @override
  int get independentSyncPartners => _independentSyncPartners;

  /// §9.2 — the measured responsibility set, from the daemon's
  /// `state_changed`. Before the first event `0`: "nothing measured yet"
  /// and "no relays known" are the same state for the display.
  @override
  int get reachableResponsibleRelays => _reachableResponsibleRelays;

  /// §24.4.2, transmitted — no constant, no local recomputation.
  @override
  bool get dataSaverActive => _dataSaverActive;
  @override
  bool get dataSaverLockedBySecure => _dataSaverLockedBySecure;

  /// §11.9, transmitted — no constant.
  @override
  bool get externalRecordsEnabled => _externalRecordsEnabled;

  @override
  bool get lanShapingActive => _lanShapingActive;

  @override
  List<String> get lanSegmentIds => _lanSegmentIds;

  @override
  List<String> get lanSegmentsGrantable => _lanSegmentsGrantable;

  @override
  bool lanSegmentConsented(String segmentId) =>
      _lanSegmentsConsented.contains(segmentId);

  @override
  int get peerCount => _peerCount;
  @override
  int get confirmedPeerCount => _confirmedPeerCount;
  @override
  int get reachablePeerCount => _reachablePeerCount;
  @override
  bool get hasPortMapping => _hasPortMapping;
  // AP-5a: the daemon holds a monotonic latch (cleona_node.dart:577, only
  // ever set to true). `_confirmedPeerCount > 0` was a live comparison and a
  // different predicate: when the counter fell back to 0, PEER-GATE G-3
  // flipped back on daemon platforms while it stayed latched in-process. The
  // `||` keeps a pre-AP-5a daemon (which does not send the field) at exactly
  // today's behaviour instead of regressing it to a constant false.
  //
  // NUMBER RANGE, added in S361. This "G-3" is NOT the gap G-3
  // (§13 recovery) from the gap bookkeeping. It is the peer gate G-3 from
  // the gate inventory in `docs/MIGRATION_V3_TO_V4_0_MYZEL.md`
  // (line 8639: `contact_seed.dart isReady`) — a different number range
  // that uses the same digits. Distinguishing mark: the gap bookkeeping
  // always writes the word "Luecke" (gap) in front. This peer gate has
  // meanwhile been done: `contact_seed.dart:970` today reads
  // `isReady => _source.readinessState == kReadinessReady`, without an
  // address condition — exactly the target state required in the table.
  IdentityDerivationSkew _identityDerivationSkew = IdentityDerivationSkew.unknown;
  bool _skewLoggedOnce = false;
  @override
  IdentityDerivationSkew get identityDerivationSkew => _identityDerivationSkew;
  bool _hasSessionConfirmedPeers = false;
  @override
  bool get hasSessionConfirmedPeers =>
      _hasSessionConfirmedPeers || _confirmedPeerCount > 0;
  DateTime? _nodeStartedAt;
  @override
  DateTime? get nodeStartedAt => _nodeStartedAt;
  bool get mobileFallbackActive => _mobileFallbackActive;
  @override
  int get fragmentCount => _fragmentCount;
  @override
  bool get isRunning => _isRunning;
  @override
  bool get isLinkedDevice => _isLinkedDevice;
  bool _isLinkedDevice = false;

  @override
  LinkedDeviceStatus get linkedDeviceStatus {
    if (!_isLinkedDevice) return LinkedDeviceStatus(isLinkedDevice: false);
    return _cachedLinkedDeviceStatus ?? LinkedDeviceStatus(isLinkedDevice: true);
  }
  LinkedDeviceStatus? _cachedLinkedDeviceStatus;

  @override
  Future<bool> requestDelegationRenewal() async {
    final resp = await _sendRequest('send_device_pair_request');
    return resp.success;
  }
  // sec-h5 §8.2 / T11 + follow-up task 2026-04-26: reducedMode is a per-session
  // flag toggled by the GUI splash. On Desktop the splash runs in this GUI
  // process while CleonaService lives in the daemon — we mirror the bool
  // locally (so the [ReducedModeBanner] in home_screen renders) AND push it
  // to the daemon via [setReducedModeSession] so user-message Send/Receive
  // is gated daemon-side. Reset by daemon restart (splash will re-show).
  bool _reducedMode = false;
  @override
  bool get reducedMode => _reducedMode;

  /// Tell the daemon to enter/leave reducedMode for this session and mirror
  /// the flag locally. Returns true on success.
  Future<bool> setReducedModeSession(bool enabled) async {
    final resp = await _sendRequest('set_reduced_mode_session',
        params: {'enabled': enabled});
    if (resp.success) {
      _reducedMode = enabled;
    }
    return resp.success;
  }

  @override
  List<ContactInfo> get acceptedContacts => _acceptedContacts;
  @override
  List<ContactInfo> get pendingContacts => _pendingContacts;
  @override
  List<ContactInfo> get pendingOutgoingContacts => _pendingOutgoingContacts;

  @override
  List<ContactInfo> get storedForDeliveryContacts => _storedForDeliveryContacts;

  @override
  ContactInfo? getContact(String nodeIdHex) {
    // S299: _storedForDeliveryContacts belongs in this aggregation. Without
    // it a contact whose CR a seed peer had accepted was not resolvable in
    // the GUI process at all — not merely missing from a list.
    for (final c in [
      ..._acceptedContacts,
      ..._pendingContacts,
      ..._pendingOutgoingContacts,
      ..._storedForDeliveryContacts
    ]) {
      if (c.nodeIdHex == nodeIdHex) return c;
    }
    return null;
  }

  @override
  List<Conversation> get sortedConversations {
    final list = conversations.values.toList();
    list.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
    return list;
  }

  @override
  Future<UiMessage?> sendTextMessage(String recipientUserIdHex, String text, {String? replyToMessageId, String? replyToText, String? replyToSender}) async {
    final resp = await _sendRequest('send_text', params: {
      'recipientId': recipientUserIdHex,
      'text': text,
      'replyToMessageId': ?replyToMessageId,
      'replyToText': ?replyToText,
      'replyToSender': ?replyToSender,
    });
    if (resp.success) {
      final msg = UiMessage(
        id: resp.data['messageId'] as String? ?? '',
        conversationId: recipientUserIdHex,
        senderNodeIdHex: _nodeIdHex,
        text: text,
        timestamp: DateTime.now(),
        type: UiMessageType.text,
        // AP-4 (§5.1c, finding 1): here stood `MessageStatus.sent` — derived
        // from the success of an IPC round trip, i.e. from an observation
        // about the own socket connection to the daemon and not about the
        // network. `sent` has been dropped; the switch does not end at the
        // IPC boundary. The authoritative value comes anyway with the next
        // `refreshState()`/`new_message` from the daemon.
        status: MessageStatus.resting,
        isOutgoing: true,
      );
      return msg;
    }
    return null;
  }

  @override
  Future<UiMessage?> sendMediaMessage(
      String conversationId, String filePath) async {
    final resp = await _sendRequest('send_media', params: {
      'conversationId': conversationId,
      'filePath': filePath,
    });
    if (resp.success) {
      await refreshState();
      return UiMessage(
        id: resp.data['messageId'] as String? ?? '',
        conversationId: conversationId,
        senderNodeIdHex: _nodeIdHex,
        text: filePath.split('/').last,
        timestamp: DateTime.now(),
        type: UiMessageType.file,
        // AP-4 (§5.1c, finding 1): here stood `MessageStatus.sent` — derived
        // from the success of an IPC round trip, i.e. from an observation
        // about the own socket connection to the daemon and not about the
        // network. `sent` has been dropped; the switch does not end at the
        // IPC boundary. The authoritative value comes anyway with the next
        // `refreshState()`/`new_message` from the daemon.
        status: MessageStatus.resting,
        isOutgoing: true,
        filePath: filePath,
        mediaState: MediaDownloadState.completed,
      );
    }
    return null;
  }

  @override
  Future<bool> acceptMediaDownload(String conversationId, String messageId) async {
    final resp = await _sendRequest('accept_media_download', params: {
      'conversationId': conversationId,
      'messageId': messageId,
    });
    return resp.success;
  }

  @override
  Future<bool> editMessage(String conversationId, String messageId, String newText) async {
    final resp = await _sendRequest('edit_message', params: {
      'conversationId': conversationId,
      'messageId': messageId,
      'newText': newText,
    });
    if (resp.success) {
      // Apply locally
      ensureLoaded(conversationId);
      final conv = conversations[conversationId];
      if (conv != null) {
        final msg = conv.messages.where((m) => m.id == messageId).firstOrNull;
        if (msg != null) {
          msg.text = newText;
          msg.editedAt = DateTime.now();
        }
      }
      onStateChanged?.call();
    }
    return resp.success;
  }

  @override
  Future<bool> deleteMessage(String conversationId, String messageId) async {
    final resp = await _sendRequest('delete_message', params: {
      'conversationId': conversationId,
      'messageId': messageId,
    });
    if (resp.success) {
      // Apply locally
      final conv = conversations[conversationId];
      if (conv != null) {
        ensureLoaded(conversationId);
        final msg = conv.messages.where((m) => m.id == messageId).firstOrNull;
        if (msg != null) {
          msg.text = '';
          msg.isDeleted = true;
        }
      }
      onStateChanged?.call();
    }
    return resp.success;
  }

  // ── THE SECOND CLOCK HAS FALLEN (S390, finding B-4) ─────────────────
  //
  // Here stood `checkExpiredMessages`, word for word the same check as in
  // `cleona_service_msgstate.dart::_checkAndMarkExpired` — built twice,
  // once in the daemon and once in the UI, and the comment next to it
  // itself warned that both halves had to carry the same deadline and
  // the same set of states. Both are gone: §9.3 allows no clock that
  // gives up a message, and `expired` as a fifth state next to the four
  // of §9.1 has been dropped without replacement.

  @override
  Future<UiMessage?> resendFailedMessage(
      String conversationId, String messageId) async {
    // Find the original text, then re-send via sendTextMessage.
    final conv = conversations[conversationId];
    if (conv == null) return null;
    ensureLoaded(conversationId);
    final original =
        conv.messages.where((m) => m.id == messageId).firstOrNull;
    if (original == null || original.status != MessageStatus.failed) {
      return null;
    }
    // §9.3: the old entry goes out, the new attempt gets a new identifier
    // via sendTextMessage.
    ensureLoaded(conversationId);
    conv.messages.removeWhere((m) => m.id == messageId);
    onStateChanged?.call();
    return sendTextMessage(
      conversationId,
      original.text,
      replyToMessageId: original.replyToMessageId,
      replyToText: original.replyToText,
      replyToSender: original.replyToSender,
    );
  }

  @override
  Future<void> sendReaction({required String conversationId, required String messageId, required String emoji, required bool remove}) async {
    await _sendRequest('send_reaction', params: {
      'conversationId': conversationId,
      'messageId': messageId,
      'emoji': emoji,
      'remove': remove,
    });
    onStateChanged?.call();
  }

  @override
  bool addManualPeer(String ip, int port) {
    _sendRequest('add_manual_peer', params: {'ip': ip, 'port': port});
    return true; // Fire-and-forget via IPC
  }

  @override
  Future<bool> updateChatConfig(String conversationId, ChatConfig config) async {
    final resp = await _sendRequest('update_chat_config', params: {
      'conversationId': conversationId,
      'config': config.toJson(),
    });
    if (resp.success) {
      // Don't set config locally — state refresh from daemon will provide correct state
      // (for DMs: pending proposal, for groups: directly applied)
      onStateChanged?.call();
    }
    return resp.success;
  }

  @override
  void updateConversationNotifications(String conversationId, {bool? enabled, String? soundName}) {
    _sendRequest('update_conversation_notifications', params: {
      'conversationId': conversationId,
      'enabled': ?enabled,
      'soundName': ?soundName,
    });
  }

  @override
  Future<bool> acceptConfigProposal(String conversationId) async {
    final resp = await _sendRequest('accept_config_proposal', params: {
      'conversationId': conversationId,
    });
    if (resp.success) onStateChanged?.call();
    return resp.success;
  }

  @override
  Future<bool> rejectConfigProposal(String conversationId) async {
    final resp = await _sendRequest('reject_config_proposal', params: {
      'conversationId': conversationId,
    });
    if (resp.success) onStateChanged?.call();
    return resp.success;
  }

  @override
  void toggleFavorite(String conversationId) {
    _sendRequest('toggle_favorite', params: {'conversationId': conversationId});
    final conv = conversations[conversationId];
    if (conv != null) {
      conv.isFavorite = !conv.isFavorite;
      onStateChanged?.call();
    }
  }

  @override
  void sendTypingIndicator(String conversationId) {
    _sendRequest('send_typing', params: {'conversationId': conversationId});
  }

  @override
  void markConversationRead(String conversationId) {
    _sendRequest('mark_read', params: {'conversationId': conversationId});
    final conv = conversations[conversationId];
    if (conv != null) conv.unreadCount = 0;
  }

  /// Fetches the history of a conversation from the service (S366, stage B).
  ///
  /// The state that the service sends of its own accord carries only the
  /// most recent message per conversation — that is the preview for the
  /// list. Whoever opens the chat calls this once; afterwards the history
  /// stands in `conversations[id].messages` as before.
  ///
  /// The second call is cheap, but not free (one round over the socket):
  /// `messagesLoaded` records that it has already happened.
  // NO @override: `ensureLoadedAsync` stands in NO interface —
  // `ICleonaService` only declares `ensureLoaded`/`ensureAllLoaded`. The
  // method is the client's own promise to wait for the socket.
  Future<void> ensureLoadedAsync(String conversationId) async {
    final conv = conversations[conversationId];
    if (conv == null || conv.messagesLoaded) return;
    final answer = await _sendRequest('load_history',
        params: {'conversationId': conversationId});
    if (!answer.success) {
      CLogger.get('ipc-client', profileDir: profileDir)
          .warn('load_history($conversationId): ${answer.error}');
      return; // Do NOT mark as loaded — otherwise empty counts as history.
    }
    final list = (answer.data['messages'] as List<dynamic>?) ?? const [];
    conv.messages
      ..clear()
      ..addAll(list
          .map((m) => UiMessage.fromJson(m as Map<String, dynamic>)));
    conv.messagesLoaded = true;
    onStateChanged?.call();
  }

  /// The synchronous version of the interface. On the client side the
  /// history cannot come synchronously — it lies at the other end of a
  /// socket. The call triggers the reloading and returns immediately; the
  /// UI redraws as soon as it is there (`onStateChanged`). Whoever NEEDS
  /// the history for certain takes [ensureLoadedAsync].
  @override
  void ensureLoaded(String conversationId) {
    unawaited(ensureLoadedAsync(conversationId));
  }

  @override
  void ensureAllLoaded() {
    // On the client that is N rounds over the socket. Today there is no
    // caller for it — the two operations that need the whole inventory
    // (archive run, recovery answer) run in the SERVICE. The body
    // nevertheless stands here and does the right thing instead of
    // throwing: an interface whose fulfilment depends on the side would
    // be harder to use than one that costs N rounds.
    for (final id in conversations.keys.toList()) {
      ensureLoaded(id);
    }
  }

  @override
  void setActiveConversationId(String? conversationId) {
    // Daemon-side notifications (sound/vibrate/Android-banner) are emitted in
    // the daemon process; the GUI tracking lives in CleonaService directly on
    // Android (in-process). On desktop the daemon has no Android-banner path
    // and desktop foreground tracking is out of scope for #U18 — no-op here.
  }

  @override
  void setAppResumed(bool isResumed, {bool triggerNodeHarvest = true}) {
    // No-op (see setActiveConversationId). `triggerNodeHarvest` has no
    // subject here: the node stands in the DAEMON, not in this process —
    // the UI has none on which it could harvest.
  }

  @override
  Future<UiMessage?> forwardMessage(String sourceConversationId, String messageId, String targetConversationId) async {
    final resp = await _sendRequest('forward_message', params: {
      'sourceConversationId': sourceConversationId,
      'messageId': messageId,
      'targetConversationId': targetConversationId,
    });
    if (resp.success) onStateChanged?.call();
    return resp.success ? UiMessage(
      id: resp.data['messageId'] as String? ?? '',
      conversationId: targetConversationId,
      senderNodeIdHex: nodeIdHex,
      text: '',
      timestamp: DateTime.now(),
      type: UiMessageType.text,
      isOutgoing: true,
    ) : null;
  }

  @override
  Map<String, GroupInfo> get groups => _groups;

  @override
  Map<String, ChannelInfo> get channels => _channels;

  @override
  Future<String?> createGroup(String name, List<String> memberNodeIdHexList) async {
    final resp = await _sendRequest('create_group', params: {
      'name': name,
      'memberIds': memberNodeIdHexList,
    });
    if (resp.success) {
      await refreshState();
      return resp.data['groupIdHex'] as String?;
    }
    return null;
  }

  @override
  Future<UiMessage?> sendGroupTextMessage(String groupIdHex, String text, {String? replyToMessageId, String? replyToText, String? replyToSender}) async {
    final resp = await _sendRequest('send_group_text', params: {
      'groupIdHex': groupIdHex,
      'text': text,
      'replyToMessageId': ?replyToMessageId,
      'replyToText': ?replyToText,
      'replyToSender': ?replyToSender,
    });
    if (resp.success) {
      return UiMessage(
        id: resp.data['messageId'] as String? ?? '',
        conversationId: groupIdHex,
        senderNodeIdHex: _nodeIdHex,
        text: text,
        timestamp: DateTime.now(),
        type: UiMessageType.text,
        // AP-4 (§5.1c, finding 1): here stood `MessageStatus.sent` — derived
        // from the success of an IPC round trip, i.e. from an observation
        // about the own socket connection to the daemon and not about the
        // network. `sent` has been dropped; the switch does not end at the
        // IPC boundary. The authoritative value comes anyway with the next
        // `refreshState()`/`new_message` from the daemon.
        status: MessageStatus.resting,
        isOutgoing: true,
      );
    }
    return null;
  }

  @override
  Future<bool> leaveGroup(String groupIdHex) async {
    final resp = await _sendRequest('leave_group', params: {
      'groupIdHex': groupIdHex,
    });
    if (resp.success) await refreshState();
    return resp.success;
  }

  @override
  Future<bool> inviteToGroup(String groupIdHex, String memberNodeIdHex) async {
    final resp = await _sendRequest('invite_to_group', params: {
      'groupIdHex': groupIdHex,
      'memberNodeIdHex': memberNodeIdHex,
    });
    if (resp.success) await refreshState();
    return resp.success;
  }

  @override
  Future<bool> setMemberRole(String groupIdHex, String memberNodeIdHex, String role) async {
    final resp = await _sendRequest('set_member_role', params: {
      'groupIdHex': groupIdHex,
      'memberNodeIdHex': memberNodeIdHex,
      'role': role,
    });
    if (resp.success) await refreshState();
    return resp.success;
  }

  @override
  Future<bool> removeMemberFromGroup(String groupIdHex, String memberNodeIdHex) async {
    final resp = await _sendRequest('remove_member', params: {
      'groupIdHex': groupIdHex,
      'memberNodeIdHex': memberNodeIdHex,
    });
    if (resp.success) await refreshState();
    return resp.success;
  }

  // ── Channel IPC methods ───────────────────────────────────────

  @override
  Future<String?> createChannel(String name, List<String> subscriberNodeIdHexList, {
    bool isPublic = false,
    bool isAdult = true,
    String language = 'de',
    String category = 'general',
    String? description,
    String? pictureBase64,
  }) async {
    final resp = await _sendRequest('create_channel', params: {
      'name': name,
      'subscriberIds': subscriberNodeIdHexList,
      'isPublic': isPublic,
      'isAdult': isAdult,
      'language': language,
      if (category != 'general') 'category': category,
      'description': ?description,
      'pictureBase64': ?pictureBase64,
    });
    if (resp.success) {
      await refreshState();
      return resp.data['channelIdHex'] as String?;
    }
    return null;
  }

  @override
  Future<UiMessage?> sendChannelPost(String channelIdHex, String text) async {
    final resp = await _sendRequest('send_channel_post', params: {
      'channelIdHex': channelIdHex,
      'text': text,
    });
    if (resp.success) {
      return UiMessage(
        id: resp.data['messageId'] as String? ?? '',
        conversationId: channelIdHex,
        senderNodeIdHex: _nodeIdHex,
        text: text,
        timestamp: DateTime.now(),
        type: UiMessageType.channelPost,
        // AP-4 (§5.1c, finding 1): here stood `MessageStatus.sent` — derived
        // from the success of an IPC round trip, i.e. from an observation
        // about the own socket connection to the daemon and not about the
        // network. `sent` has been dropped; the switch does not end at the
        // IPC boundary. The authoritative value comes anyway with the next
        // `refreshState()`/`new_message` from the daemon.
        status: MessageStatus.resting,
        isOutgoing: true,
      );
    }
    return null;
  }

  @override
  Future<UiMessage?> submitFeatureRequest(String title, String body) async {
    final resp = await _sendRequest('submit_feature_request', params: {
      'title': title,
      'body': body,
    });
    if (resp.success) {
      return UiMessage(
        id: resp.data['messageId'] as String? ?? '',
        conversationId: resp.data['channelIdHex'] as String? ?? '',
        senderNodeIdHex: _nodeIdHex,
        text: resp.data['text'] as String? ?? '',
        timestamp: DateTime.now(),
        type: UiMessageType.channelPost,
        // AP-4 (§5.1c, finding 1): here stood `MessageStatus.sent` — derived
        // from the success of an IPC round trip, i.e. from an observation
        // about the own socket connection to the daemon and not about the
        // network. `sent` has been dropped; the switch does not end at the
        // IPC boundary. The authoritative value comes anyway with the next
        // `refreshState()`/`new_message` from the daemon.
        status: MessageStatus.resting,
        isOutgoing: true,
      );
    }
    return null;
  }

  @override
  Future<bool> voteFeatureRequest(String recordIdHex, int option) async {
    final resp = await _sendRequest('vote_feature_request', params: {
      'recordIdHex': recordIdHex,
      'option': option,
    });
    return resp.success;
  }

  @override
  Future<Map<String, int>> featureRequestTally(String recordIdHex) async {
    final resp = await _sendRequest('feature_request_tally', params: {
      'recordIdHex': recordIdHex,
    });
    if (!resp.success) return const {'ja': 0, 'nein': 0, 'egal': 0, 'net': 0, 'own': -1};
    return (resp.data).map((k, v) => MapEntry(k, (v as num).toInt()));
  }

  @override
  Future<bool> leaveChannel(String channelIdHex) async {
    final resp = await _sendRequest('leave_channel', params: {
      'channelIdHex': channelIdHex,
    });
    if (resp.success) await refreshState();
    return resp.success;
  }

  @override
  Future<bool> inviteToChannel(String channelIdHex, String memberNodeIdHex) async {
    final resp = await _sendRequest('invite_to_channel', params: {
      'channelIdHex': channelIdHex,
      'memberNodeIdHex': memberNodeIdHex,
    });
    if (resp.success) await refreshState();
    return resp.success;
  }

  @override
  Future<bool> removeFromChannel(String channelIdHex, String memberNodeIdHex) async {
    final resp = await _sendRequest('remove_from_channel', params: {
      'channelIdHex': channelIdHex,
      'memberNodeIdHex': memberNodeIdHex,
    });
    if (resp.success) await refreshState();
    return resp.success;
  }

  @override
  Future<bool> setChannelRole(String channelIdHex, String memberNodeIdHex, String role) async {
    final resp = await _sendRequest('set_channel_role', params: {
      'channelIdHex': channelIdHex,
      'memberNodeIdHex': memberNodeIdHex,
      'role': role,
    });
    if (resp.success) await refreshState();
    return resp.success;
  }

  // ── Public Channel IPC methods ──────────────────────────────────

  @override
  Future<List<ChannelIndexEntry>> searchPublicChannels({
    String? query,
    String? language,
    bool? includeAdult,
  }) async {
    final resp = await _sendRequest('search_public_channels', params: {
      'query': ?query,
      'language': ?language,
      'includeAdult': ?includeAdult,
    });
    if (resp.success) {
      final list = resp.data['channels'] as List<dynamic>? ?? [];
      return list.map((e) => ChannelIndexEntry.fromJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  @override
  Future<bool> publishChannelToIndex(String channelIdHex) async {
    final resp = await _sendRequest('publish_channel_to_index', params: {
      'channelIdHex': channelIdHex,
    });
    return resp.success;
  }

  @override
  Future<bool> joinPublicChannel(String channelIdHex) async {
    final resp = await _sendRequest('join_public_channel', params: {
      'channelIdHex': channelIdHex,
    });
    if (resp.success) await refreshState();
    return resp.success;
  }

  @override
  Future<bool> reportChannel(String channelIdHex, int category, List<String> evidencePostIds, {String? description}) async {
    final resp = await _sendRequest('report_channel', params: {
      'channelIdHex': channelIdHex,
      'category': category,
      'evidencePostIds': evidencePostIds,
      'description': ?description,
    });
    return resp.success;
  }

  @override
  Future<bool> reportPost(String channelIdHex, String postId, int category, {String? description}) async {
    final resp = await _sendRequest('report_post', params: {
      'channelIdHex': channelIdHex,
      'postId': postId,
      'category': category,
      'description': ?description,
    });
    return resp.success;
  }

  @override
  Future<bool> submitJuryVote(String juryId, String reportId, int vote, {String? reason}) async {
    final resp = await _sendRequest('submit_jury_vote', params: {
      'juryId': juryId,
      'reportId': reportId,
      'vote': vote,
      'reason': ?reason,
    });
    return resp.success;
  }

  @override
  void Function(JuryRequest request)? onJuryRequestReceived;

  List<JuryRequest> _pendingJuryRequests = const [];
  @override
  List<JuryRequest> get pendingJuryRequests =>
      List.unmodifiable(_pendingJuryRequests);

  @override
  Future<Map<String, dynamic>> getChannelModerationInfo(
      String channelIdHex) async {
    final resp = await _sendRequest('get_channel_moderation_info',
        params: {'channelIdHex': channelIdHex});
    if (!resp.success) return {};
    return Map<String, dynamic>.from(resp.data);
  }

  @override
  Future<bool> dismissPostReport(String channelIdHex, String reportId) async {
    final resp = await _sendRequest('dismiss_post_report', params: {
      'channelIdHex': channelIdHex,
      'reportId': reportId,
    });
    return resp.success;
  }

  @override
  Future<bool> submitBadgeCorrection(String channelIdHex, {String? newName, String? newDescription}) async {
    final resp = await _sendRequest('submit_badge_correction', params: {
      'channelIdHex': channelIdHex,
      'newName': ?newName,
      'newDescription': ?newDescription,
    });
    return resp.success;
  }

  @override
  Future<bool> contestCsamHide(String channelIdHex) async {
    final resp = await _sendRequest('contest_csam_hide', params: {
      'channelIdHex': channelIdHex,
    });
    return resp.success;
  }

  @override
  String? get profilePictureBase64 => _profilePictureBase64;

  @override
  void updateDisplayName(String newName) {
    _sendRequest('update_display_name', params: {'newName': newName});
    _displayName = newName;
    onStateChanged?.call();
  }

  @override
  Future<bool> setProfilePicture(String? base64Jpeg) async {
    final resp = await _sendRequest('set_profile_picture', params: {
      'base64Jpeg': base64Jpeg,
    });
    if (resp.success) {
      _profilePictureBase64 = base64Jpeg;
      onStateChanged?.call();
    }
    return resp.success;
  }

  // ── Profile Description ─────────────────────────────────────────

  @override
  String? get profileDescription => _profileDescription;

  @override
  Future<bool> setProfileDescription(String? description) async {
    final resp = await _sendRequest('set_profile_description', params: {
      'description': description,
    });
    if (resp.success) {
      _profileDescription = description;
      onStateChanged?.call();
    }
    return resp.success;
  }

  // ── Media Settings ───────────────────────────────────────────────

  MediaSettings _mediaSettings = MediaSettings();

  @override
  MediaSettings get mediaSettings => _mediaSettings;

  @override
  void updateMediaSettings(MediaSettings settings) {
    _mediaSettings = settings;
    _sendRequest('update_media_settings', params: settings.toJson());
    onStateChanged?.call();
  }

  @override
  bool get serveBinaryUpdates => true;

  @override
  Future<String?> generateInviteLinkUrl() async {
    // A pre-AP-5a daemon does not know the verb and answers
    // `Unknown command` -> success=false -> null, i.e. exactly the previous
    // behaviour (invite block hidden) instead of an exception.
    final resp = await _sendRequest('generate_invite_link_url');
    if (!resp.success) return null;
    return resp.data['url'] as String?;
  }

  /// §15.3/§15.5 — issuing happens IN THE DAEMON, not here.
  ///
  /// The daemon holds the master seed, keeps the invitation ledger and
  /// harvests the invitation line (§15.3.2). This side only passes the
  /// user's choice there and the key back; it creates nothing.
  @override
  Future<InviteIssueResult> issueInviteForSharing({
    required String inviteClassCode,
    Duration? validity,
    bool singleUse = false,
    String label = 'qr-card',
  }) async {
    final resp = await _sendRequest('issue_invitation', params: {
      'class': inviteClassCode,
      'validityMs': validity?.inMilliseconds,
      'singleUse': singleUse,
      'label': label,
    });
    // ── REBUILD THE REASON, DO NOT GUESS (S381) ──────────────────
    //
    // If this version does not know the reason named — older or newer
    // other side —, then `fromWire` says so too
    // ([InviteIssueRefusal.unknownReason]) and does NOT fall back to the
    // most frequent neighbour. Exactly this fallback was the defect: the
    // card showed "cap reached" where in truth the master seed was
    // missing.
    if (!resp.success) {
      return InviteIssueResult.refused(
          refusalFromWire(resp.data[kInviteRefusalField] as String?));
    }
    final kiB64 = resp.data['kiB64'] as String?;
    if (kiB64 == null || kiB64.isEmpty) {
      // Success reported, but without a carrier — that is no success (§15.5).
      return const InviteIssueResult.refused(InviteIssueRefusal.noMasterSeed);
    }
    return InviteIssueResult.issued(IssuedInvite(
      inviteClassCode: resp.data['class'] as String? ?? inviteClassCode,
      index: resp.data['index'] as int? ?? 0,
      inviteKey: Uint8List.fromList(base64.decode(kiB64)),
      expiresAtMs: resp.data['expiresAtMs'] as int?,
    ));
  }

  /// §15.3.2 — the daemon fetches the open invitations from its ledger.
  @override
  Future<List<OpenInvitation>> listOpenInvitations({DateTime? now}) async {
    final resp = await _sendRequest('list_open_invitations');
    if (!resp.success) {
      // §21.4: unreadable is not empty. An empty list here would be the
      // false statement "you have no open invitations" — and the user
      // would keep searching for the invitation that fills the cap.
      throw StateError(
          'list_open_invitations failed: ${resp.error ?? "no reason given"}');
    }
    final raw = (resp.data['invitations'] as List?) ?? const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(OpenInvitation.fromJson)
        .toList(growable: false);
  }

  /// §15.3.3 — revocation happens IN THE DAEMON, the ledger lies there.
  @override
  Future<bool> revokeInvitation(int index, {DateTime? now}) async {
    final resp =
        await _sendRequest('revoke_invitation', params: {'index': index});
    return resp.success && resp.data['revoked'] == true;
  }

  // ── V4.2 invitation card (S387, `mycelium/berichte/S387-API-KARTE.md`) ──
  //
  // A `success: false` here means: no service in the daemon or a missing
  // parameter. It is mapped to `notConnected` or `failed` respectively —
  // never to an empty list or a silent zero.

  @override
  Future<InvitationIssueResult> issueInvitationCard({
    InvitationKind kind = InvitationKind.single,
    InvitationValidity? validity,
    String label = '',
    bool faceToFace = false,
  }) async {
    final resp = await _sendRequest('invitation_card_issue', params: {
      'kind': kind.name,
      if (validity != null) 'validity': validity.name,
      'label': label,
      if (faceToFace) 'faceToFace': true,
    });
    if (!resp.success) {
      return InvitationIssueResult.refused(
          InvitationIssueRefusal.notConnected, resp.error);
    }
    return InvitationIssueResult.fromJson(resp.data);
  }

  @override
  Future<InvitationRedeemResult> redeemInvitationText(String text) async {
    final resp = await _sendRequest('invitation_card_redeem_text',
        params: {'text': text});
    if (!resp.success) {
      return InvitationRedeemResult(InvitationRedeemOutcome.notConnected,
          detail: resp.error);
    }
    return InvitationRedeemResult.fromJson(resp.data);
  }

  @override
  Future<InvitationRedeemResult> redeemInvitationCardBytes(
      Uint8List packed) async {
    final resp = await _sendRequest('invitation_card_redeem_bytes',
        params: {'packedB64': base64.encode(packed)});
    if (!resp.success) {
      return InvitationRedeemResult(InvitationRedeemOutcome.notConnected,
          detail: resp.error);
    }
    return InvitationRedeemResult.fromJson(resp.data);
  }

  @override
  Future<StandingInvitationsResult> standingInvitations() async {
    final resp = await _sendRequest('invitation_card_standing');
    if (!resp.success) {
      return const StandingInvitationsResult.unavailable(notConnected: true);
    }
    return StandingInvitationsResult.fromJson(resp.data);
  }

  @override
  Future<InvitationRevokeOutcome> revokeInvitationCard(
      String invitationId) async {
    final resp = await _sendRequest('invitation_card_revoke',
        params: {'id': invitationId});
    if (!resp.success) return InvitationRevokeOutcome.notConnected;
    return InvitationRevokeOutcome.byName(resp.data['outcome'] as String?) ??
        InvitationRevokeOutcome.unknown;
  }

  @override
  Future<InvitationRevokeAllResult> revokeAllInvitationCards() async {
    final resp = await _sendRequest('invitation_card_revoke_all');
    if (!resp.success) return const InvitationRevokeAllResult.notConnected();
    return InvitationRevokeAllResult.fromJson(resp.data);
  }

  @override
  Future<bool> setPort(int newPort) async {
    final resp = await _sendRequest('set_port', params: {'port': newPort});
    if (resp.success) {
      _port = newPort;
      onStateChanged?.call();
      return true;
    }
    return false;
  }

  // ── Link Preview Settings ──────────────────────────────────────

  LinkPreviewSettings _linkPreviewSettings = LinkPreviewSettings();

  @override
  LinkPreviewSettings get linkPreviewSettings => _linkPreviewSettings;

  @override
  void updateLinkPreviewSettings(LinkPreviewSettings settings) {
    _linkPreviewSettings = settings;
    _sendRequest('update_link_preview_settings', params: settings.toJson());
    onStateChanged?.call();
  }

  // ── Multi-Interface Send (Architecture §23.2) ────────────────────

  MultiInterfaceMode _multiInterfaceMode = MultiInterfaceMode.auto;

  @override
  MultiInterfaceMode get multiInterfaceMode => _multiInterfaceMode;

  @override
  Future<void> setMultiInterfaceMode(MultiInterfaceMode mode) async {
    _multiInterfaceMode = mode;
    _sendRequest('set_multi_interface_mode', params: {'mode': MultiInterfaceMode.modeToString(mode)});
    onStateChanged?.call();
  }

  // ── NFC Contact Exchange (not supported via IPC — NFC runs in-process) ──

  @override
  Uint8List? get ed25519PublicKey => null;
  @override
  Uint8List? get mlDsaPublicKey => null;
  @override
  Uint8List? get x25519PublicKey => null;
  @override
  Uint8List? get mlKemPublicKey => null;
  @override
  Uint8List? get profilePicture => null;
  @override
  Uint8List signEd25519(Uint8List message) => throw UnsupportedError('NFC signing not available via IPC');
  @override
  bool verifyEd25519(Uint8List message, Uint8List signature, Uint8List publicKey) => false;

  // ── Notification Sound Service ──────────────────────────────────

  final NotificationSoundService _notificationSoundService = NotificationSoundService();

  @override
  NotificationSoundService get notificationSound => _notificationSoundService;

  // ── Guardian Recovery ─────────────────────────────────────────────

  @override
  bool get isGuardianSetUp => _isGuardianSetUp;

  @override
  void Function(String ownerName, String triggeringGuardianName, String ownerNodeIdHex, String recoveryMailboxIdHex)? onGuardianRestoreRequest;

  @override
  Future<bool> setupGuardians(List<String> guardianNodeIds) async {
    final resp = await _sendRequest('setup_guardians', params: {
      'guardianNodeIds': guardianNodeIds,
    });
    if (resp.success) {
      _isGuardianSetUp = true;
      onStateChanged?.call();
    }
    return resp.success;
  }

  @override
  Future<Map<String, dynamic>?> triggerGuardianRestore(String contactNodeIdHex) async {
    final resp = await _sendRequest('trigger_guardian_restore', params: {
      'contactNodeIdHex': contactNodeIdHex,
    });
    if (resp.success && resp.data.isNotEmpty) {
      return resp.data;
    }
    return null;
  }

  @override
  Future<bool> confirmGuardianRestore(String ownerNodeIdHex, String recoveryMailboxIdHex) async {
    final resp = await _sendRequest('confirm_guardian_restore', params: {
      'ownerNodeIdHex': ownerNodeIdHex,
      'recoveryMailboxIdHex': recoveryMailboxIdHex,
    });
    return resp.success;
  }

  // `sendContactRequest` has been dropped (S388-BAU-KONTAKT) — see
  // `ICleonaService`.

  List<String> _localIps = [];
  String? _publicIp;
  int? _publicPort;

  @override
  List<String> get localIps => _localIps;
  @override
  String? get publicIp => _publicIp;
  @override
  int? get publicPort => _publicPort;

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
    _sendRequest('add_seed_peers', params: {
      'targetNodeIdHex': targetNodeIdHex,
      'targetAddresses': targetAddresses,
      'seedPeers': seedPeers.map((p) => {
        'nodeIdHex': p.nodeIdHex,
        'addresses': p.addresses,
      }).toList(),
      'targetDeviceIdHex': ?targetDeviceIdHex,
      'targetDxkB64': ?targetDxkB64,
      'targetDmkB64': ?targetDmkB64,
      'targetEpB64': ?targetEpB64,
      'targetRendezvousNonceB64': ?targetRendezvousNonceB64,
    });
  }

  @override
  Future<bool> acceptContactRequest(String nodeIdHex) async {
    final resp = await _sendRequest('accept_contact', params: {
      'nodeIdHex': nodeIdHex,
    });
    return resp.success;
  }

  @override
  void deleteContact(String nodeIdHex, {required String source}) {
    _sendRequest('delete_contact', params: {'nodeIdHex': nodeIdHex});
  }

  @override
  void renameContact(String nodeIdHex, String? localAlias) {
    _sendRequest('rename_contact', params: {
      'nodeIdHex': nodeIdHex,
      'localAlias': ?localAlias,
    });
  }

  @override
  bool setContactBirthday(String nodeIdHex,
      {int? month, int? day, int? year}) {
    // Update the cached contact so the UI reflects the change immediately;
    // the authoritative update happens daemon-side via IPC.
    final contact = getContact(nodeIdHex);
    if (contact != null) {
      contact.birthdayMonth = month;
      contact.birthdayDay = day;
      contact.birthdayYear = year;
      onStateChanged?.call();
    }
    _sendRequest('contact_set_birthday', params: {
      'nodeIdHex': nodeIdHex,
      'month': ?month,
      'day': ?day,
      'year': ?year,
    });
    return contact != null;
  }

  @override
  bool setContactNeverFixedNeighbour(String nodeIdHex, bool never) {
    // Cached copy first so the switch follows at once; the daemon holds the
    // authoritative record and hands the mark to the delivery layer.
    final contact = getContact(nodeIdHex);
    if (contact != null) {
      contact.neverFixedNeighbour = never;
      onStateChanged?.call();
    }
    _sendRequest('contact_set_never_fixed_neighbour', params: {
      'nodeIdHex': nodeIdHex,
      'never': never,
    });
    return contact != null;
  }

  /// §14.7.4: withhold this node's delivery status from a contact or group.
  /// Mirrors the daemon-side setting into the local cache so the toggle
  /// reflects immediately; the daemon remains authoritative.
  @override
  bool setWithholdDeliveryStatus(String entityIdHex, bool withhold) {
    final group = _groups[entityIdHex];
    final contact = group == null ? getContact(entityIdHex) : null;
    if (group == null && contact == null) return false;
    group?.withholdDeliveryStatus = withhold;
    contact?.withholdDeliveryStatus = withhold;
    onStateChanged?.call();
    _sendRequest('set_withhold_delivery_status', params: {
      'entityIdHex': entityIdHex,
      'withhold': withhold,
    });
    return true;
  }

  /// §12 V4.1: Secure/Speed choice for a chat.
  ///
  /// THIS METHOD IS THE ACTUAL FIX. Until 30.08. `chat_screen.dart`
  /// mutated the fields directly on the object from [getContact] — and in
  /// here that is an entry from the GUI process's state snapshot, not the
  /// daemon's contact. The choice fizzled out and was gone again at the
  /// next `state_changed`. The snapshot is still pulled along, but now
  /// only as optimism for the display; the daemon is authoritative.
  // NO `setSecureMode` ANY MORE (S389). The path over the socket
  // (`set_secure_mode`) has been dropped with the switch: §12.1 allows no
  // per-chat setting of the send path, so there is also no IPC verb with
  // which the UI passes it to the daemon.

  /// §24.4.2 — the setter across the IPC boundary.
  ///
  /// THE LATCH IS NOT REINVENTED HERE, but PULLED A SECOND TIME. The
  /// daemon is authoritative (`CoverSaver.instance.request`); this side
  /// knows only the transmitted [dataSaverLockedBySecure]. It nevertheless
  /// aborts itself if that is set — otherwise the switch in the UI would
  /// only snap back at the next `state_changed`, and the user would for a
  /// moment see an active saver mode that does not exist.
  ///
  /// The optimistic anticipation applies ONLY to switching on without a
  /// latch and is overwritten by the next snapshot — the same pattern as
  /// [setSecureMode].
  @override
  String setDataSaver(bool on) {
    if (on && _dataSaverLockedBySecure) return kDataSaverLockedBySecure;
    _dataSaverActive = on;
    onStateChanged?.call();
    _sendRequest('set_data_saver', params: {'on': on});
    return kDataSaverOk;
  }

  /// §11.9 — optimistic like [setDataSaver]: the switch has no latch, and
  /// the daemon's next state packet overwrites the anticipation. What is
  /// reported is that the request went out.
  @override
  bool setExternalRecordsEnabled(bool on) {
    _externalRecordsEnabled = on;
    onStateChanged?.call();
    _sendRequest('set_external_records', params: {'on': on});
    return true;
  }

  /// S373 — the consent across the IPC boundary.
  ///
  /// THE SAME CONSTRUCTION AS [setDataSaver], and for the same reason: the
  /// rule is not reinvented here but PULLED A SECOND TIME. The daemon is
  /// authoritative — only it knows its partners and their endpoints. This
  /// side knows the transmitted list [lanSegmentsGrantable] and aborts
  /// itself if the segment is not in it; otherwise the UI would report a
  /// success and silently take it back at the next state packet.
  ///
  /// **No optimistic anticipation when GRANTING.** Unlike the saver mode,
  /// where a wrongly displayed "on" is only ugly: here it would mean
  /// making the UI believe for a moment that the cover is off, although it
  /// is running — and that is exactly the kind of statement a user must
  /// not get wrong. Only what the daemon has confirmed is displayed.
  ///
  /// On REVOCATION the anticipation is harmless and therefore allowed: it
  /// leads to MORE cover, never to less.
  @override
  bool grantLanShaping(String segmentId) {
    if (!_lanSegmentsGrantable.contains(segmentId)) return false;
    _sendRequest('set_lan_shaping',
        params: {'segment': segmentId, 'grant': true});
    return true;
  }

  @override
  bool revokeLanShaping(String segmentId) {
    if (!_lanSegmentsConsented.contains(segmentId)) return false;
    _lanSegmentsConsented =
        _lanSegmentsConsented.where((e) => e != segmentId).toList();
    _lanShapingActive = false;
    onStateChanged?.call();
    _sendRequest('set_lan_shaping',
        params: {'segment': segmentId, 'grant': false});
    return true;
  }

  @override
  void acceptContactNameChange(String nodeIdHex, bool accept) {
    _sendRequest('accept_name_change', params: {
      'nodeIdHex': nodeIdHex,
      'accept': accept,
    });
  }

  @override
  List<PeerSummary> get peerSummaries => _peerSummaries;

  List<EntrySeedCandidate> _entrySeedCandidates = const [];

  /// §11/G-11 — passed through from the daemon's snapshot. The builder
  /// makes the selection, not this client.
  @override
  List<EntrySeedCandidate> get entrySeedCandidates => _entrySeedCandidates;

  @override
  CallInfo? get currentCall => _currentCall;

  @override
  Future<CallInfo?> startCall(String peerNodeIdHex, {bool video = false}) async {
    final resp = await _sendRequest('start_call', params: {
      'peerNodeIdHex': peerNodeIdHex,
      'video': video,
    });
    if (resp.success) {
      _currentCall = CallInfo.fromJson(resp.data);
      return _currentCall;
    }
    return null;
  }

  @override
  Future<void> acceptCall() async {
    await _sendRequest('accept_call');
  }

  @override
  Future<void> rejectCall({String reason = 'busy'}) async {
    await _sendRequest('reject_call', params: {'reason': reason});
    _currentCall = null;
  }

  @override
  Future<void> hangup() async {
    await _sendRequest('hangup');
    _currentCall = null;
  }

  // ── Group Calls ──────────────────────────────────────────────────

  @override
  GroupCallInfo? get currentGroupCall => _currentGroupCall;
  GroupCallInfo? _currentGroupCall;

  @override
  void Function(GroupCallInfo info)? onIncomingGroupCall;
  @override
  void Function(GroupCallInfo info)? onGroupCallStarted;
  @override
  void Function(GroupCallInfo info)? onGroupCallEnded;

  @override
  Future<GroupCallInfo?> startGroupCall(String groupIdHex) async {
    final resp = await _sendRequest('start_group_call', params: {'groupIdHex': groupIdHex});
    if (resp.success && resp.data.containsKey('callId')) {
      _currentGroupCall = GroupCallInfo.fromJson(resp.data);
      return _currentGroupCall;
    }
    return null;
  }

  @override
  Future<void> acceptGroupCall() async {
    await _sendRequest('accept_group_call');
  }

  @override
  Future<void> rejectGroupCall({String reason = 'busy'}) async {
    await _sendRequest('reject_group_call', params: {'reason': reason});
    _currentGroupCall = null;
  }

  @override
  Future<void> leaveGroupCall() async {
    await _sendRequest('leave_group_call');
    _currentGroupCall = null;
  }

  @override
  bool get isMuted => _isMuted;
  bool _isMuted = false;

  @override
  void toggleMute() {
    _sendRequest('toggle_mute').then((resp) {
      if (resp.success) {
        _isMuted = resp.data['isMuted'] as bool? ?? false;
      }
    });
  }

  @override
  bool get isSpeakerEnabled => _isSpeakerEnabled;
  bool _isSpeakerEnabled = true;

  @override
  void toggleSpeaker() {
    _sendRequest('toggle_speaker').then((resp) {
      if (resp.success) {
        _isSpeakerEnabled = resp.data['isSpeakerEnabled'] as bool? ?? true;
      }
    });
  }

  @override
  bool get isVideoMuted => _isVideoMuted;
  bool _isVideoMuted = false;

  @override
  void toggleVideoMute() {
    _sendRequest('toggle_video_mute').then((resp) {
      if (resp.success) {
        _isVideoMuted = resp.data['isVideoMuted'] as bool? ?? false;
      }
    });
  }

  @override
  Future<bool> switchCamera() async {
    // Desktop (Linux/Windows) has no camera capture integration — the
    // daemon-side video engine either runs isolate-captured gray frames
    // (Linux) or nothing at all. Rather than a round-trip that always
    // answers false, short-circuit locally (CLAUDE.md §5: no unnecessary
    // network traffic).
    return false;
  }

  // Network statistics
  @override
  NetworkStats getNetworkStats() => _cachedStats ?? const NetworkStats();
  NetworkStats? _cachedStats;

  /// Fetch fresh network stats from the daemon.
  Future<NetworkStats> fetchNetworkStats() async {
    final resp = await _sendRequest('get_network_stats');
    if (resp.success && resp.data.containsKey('stats')) {
      _cachedStats = NetworkStats.fromJson(resp.data['stats'] as Map<String, dynamic>);
    }
    return _cachedStats ?? const NetworkStats();
  }

  // ── Contact issue reporting ────────────────────────────────────────
  @override
  Future<ContactIssueReport?> buildContactIssueReport(
      String contactNodeIdHex) async {
    final resp = await _sendRequest('build_contact_issue_report',
        params: {'nodeIdHex': contactNodeIdHex});
    if (resp.success && resp.data.containsKey('report')) {
      return ContactIssueReport.fromJson(
          resp.data['report'] as Map<String, dynamic>);
    }
    return null;
  }

  @override
  Future<bool> publishContactIssueReport(String contactNodeIdHex) async {
    final resp = await _sendRequest('publish_contact_issue_report',
        params: {'nodeIdHex': contactNodeIdHex});
    return resp.success;
  }

  /// S368 — AN EMPTY REPORT STOOD HERE.
  ///
  /// The implementation returned `appVersion: ''`, `platform: ''`,
  /// `logTail: ''`, `peerCount: 0` — a completely empty `LogReport`,
  /// because the interface was synchronous and nothing can be fetched
  /// synchronously over the IPC socket. The preview dialog (§9.5.2b,
  /// "Preview + Consent") thus showed an EMPTY report on desktop, and
  /// `publishLogReport()` then sent the REAL one from the daemon. The user
  /// did not see what he was consenting to.
  ///
  /// `fetchLogReport()` — the right path — stood directly below the whole
  /// time and had ZERO callers.
  ///
  /// Now: the real report, or an error. No third outcome. An empty preview
  /// would be worse than none at all, because it looks like a result.
  @override
  Future<LogReport> buildLogReport() async {
    final report = await fetchLogReport();
    if (report == null) {
      throw StateError(
          'Log report not retrievable: the daemon did not answer '
          'build_log_report. No empty substitute report — the preview must '
          'show what is sent.');
    }
    return report;
  }

  Future<LogReport?> fetchLogReport() async {
    final resp = await _sendRequest('build_log_report');
    if (resp.success && resp.data.containsKey('report')) {
      return LogReport.fromJson(
          resp.data['report'] as Map<String, dynamic>);
    }
    return null;
  }

  @override
  Future<bool> publishLogReport() async {
    final resp = await _sendRequest('publish_log_report');
    return resp.success;
  }

  // ── NAT-Troubleshooting-Wizard (§27.9) — IPC proxy ──────────────────
  @override
  void Function()? onNatWizardTriggered;
  @override
  void Function()? onNatWizardUserRequested;

  @override
  Future<void> dismissNatWizard({required int durationSeconds}) async {
    await _sendRequest('nat_wizard_dismiss',
        params: {'durationSeconds': durationSeconds});
  }

  @override
  Future<bool> recheckNatWizard() async {
    final resp = await _sendRequest('nat_wizard_recheck');
    return resp.success && (resp.data['hasDirect'] as bool? ?? false);
  }

  @override
  void testForceNatWizardTrigger() {
    // Proxy stub: GUI never calls this (E2E harness talks direct IPC).
    _sendRequest('test_force_nat_wizard_trigger');
  }

  @override
  void requestNatWizard() {
    // User-initiated trigger (connection-icon tap). Desktop path: GUI asks
    // the daemon to fire onNatWizardTriggered; the daemon dispatches it
    // directly on the service side, and the GUI's home_screen latch is
    // reset via CleonaAppState.bumpNatWizardResetCounter() (called from
    // the tap handler before this).
    _sendRequest('request_nat_wizard');
  }

  @override
  void testResetNatWizardDismissed() {
    // Proxy stub: GUI never calls this (E2E harness talks direct IPC).
    _sendRequest('test_reset_nat_wizard_dismissed');
  }

  // Recovery
  @override
  void Function(int phase, int contactsRestored, int messagesRestored)? onRestoreProgress;

  @override
  Future<bool> sendRestoreBroadcast({
    required Uint8List oldEd25519Sk,
    required Uint8List oldEd25519Pk,
    required Uint8List oldNodeId,
    required List<ContactInfo> oldContacts,
  }) async {
    final contactsJson = oldContacts.map((c) => c.toJson()).toList();
    final resp = await _sendRequest('restore_broadcast', params: {
      'oldEd25519Sk': bytesToHex(oldEd25519Sk),
      'oldEd25519Pk': bytesToHex(oldEd25519Pk),
      'oldNodeId': bytesToHex(oldNodeId),
      'oldContacts': contactsJson,
    });
    return resp.success;
  }

  // ── Multi-Device (§26) ─────────────────────────────────────────────

  List<DeviceRecord> _devices = [];
  String _localDeviceId = '';

  @override
  List<DeviceRecord> get devices => _devices;

  /// §24.4.3 — transition state last transmitted by the daemon.
  ///
  /// Initial value empty, because nothing is known before the first
  /// answer. The value is set in `_applyStateSnapshot` and NOT computed
  /// here: the numbers stand in the daemon's `_lockouts`, the client does
  /// not have them.
  List<Map<String, dynamic>> _deviceLockouts = const [];

  @override
  String get localDeviceId => _localDeviceId;

  @override
  List<Map<String, dynamic>> get deviceLockouts => _deviceLockouts;

  void Function()? onDevicesUpdated;
  @override
  void Function(String deviceIdHex)? onDevicePairRequest;

  // §19.6: Update availability (daemon→GUI via IPC)
  void Function(UpdateManifest manifest, bool inNetworkAvailable)? onUpdateAvailable;
  void Function(BinaryUpdateState state, double progress)? onUpdateStateChanged;

  Future<bool> startInNetworkUpdate() async {
    final resp = await _sendRequest('start_in_network_update');
    return resp.success;
  }

  Future<bool> applyUpdate() async {
    final resp = await _sendRequest('apply_update');
    return resp.success;
  }

  @override
  void renameDevice(String deviceId, String newName) {
    _sendRequest('rename_device', params: {
      'deviceId': deviceId,
      'newName': newName,
    });
    // Optimistic update
    final d = _devices.where((d) => d.deviceId == deviceId).firstOrNull;
    if (d != null) d.deviceName = newName;
  }

  @override
  Future<bool> revokeDevice(String deviceId) async {
    final resp = await _sendRequest('revoke_device', params: {
      'deviceId': deviceId,
    });
    if (resp.success) {
      _devices.removeWhere((d) => d.deviceId == deviceId);
    }
    return resp.success;
  }

  /// §7.1: Approve a pending device-pairing request (Primary → Linked Device).
  Future<bool> approveDevicePair(String deviceIdHex) async {
    final resp = await _sendRequest('approve_device_pair', params: {
      'deviceIdHex': deviceIdHex,
    });
    return resp.success;
  }

  /// §7.1 LD-2: [ICleonaService] surface for [approveDevicePair] — same call,
  /// named to match the interface so callers typed against `ICleonaService`
  /// (desktop IPC and in-process alike) can use it without knowing which
  /// transport they are on.
  @override
  Future<bool> approvePairRequest(String requestingDeviceIdHex) =>
      approveDevicePair(requestingDeviceIdHex);

  /// §7.1 LD-2: catch-up for pending device-pairing requests — see
  /// [ICleonaService.getPendingPairRequests] for the field contract.
  @override
  Future<List<Map<String, dynamic>>> getPendingPairRequests() async {
    final resp = await _sendRequest('get_pending_pair_requests');
    if (!resp.success) return const [];
    final list =
        resp.data['pendingPairRequests'] as List<dynamic>? ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// §7.1: Query whether this identity runs as a Linked Device.
  Future<Map<String, dynamic>> getLinkedDeviceStatus() async {
    final resp = await _sendRequest('get_linked_device_status');
    return resp.data;
  }

  /// §7.1: Initiate pairing (this device wants to become a Linked Device).
  @override
  Future<bool> sendDevicePairRequest() async {
    final resp = await _sendRequest('send_device_pair_request');
    return resp.success;
  }

  @override
  Future<void> rotateIdentityKeys() async {
    await _sendRequest('rotate_identity_keys');
  }

  @override
  void injectTestDevice(String deviceId, String name, String platform) {
    _sendRequest('test_inject_device', params: {
      'deviceId': deviceId,
      'name': name,
      'platform': platform,
    });
  }

  @override
  Map<String, dynamic> testGetKeyRotationRetryState() {
    // Proxy stub: GUI never calls this (E2E harness talks direct IPC).
    return const <String, dynamic>{};
  }

  @override
  void testForceKeyRotationRetry() {
    _sendRequest('test_key_rotation_force_retry');
  }

  // ── Polls (§24) ───────────────────────────────────────────────────

  /// Proxy PollManager — holds cached state from daemon, no local persistence.
  late final PollManager _pollManager = PollManager(
    profileDir: '',
    identityId: _nodeIdHex,
  );

  @override
  PollManager get pollManager => _pollManager;

  @override
  void Function(String pollId, String groupId, String question)? onPollCreated;
  @override
  void Function(String pollId)? onPollTallyUpdated;
  @override
  void Function(String pollId)? onPollStateChanged;

  @override
  void Function(String contactNodeIdHex, int pendingCount)?
      onKeyRotationPendingExpired;

  @override
  void Function(
          String contactNodeIdHex, String displayName, bool wasVerified)?
      onContactIdentityRotated;

  @override
  void Function(
          String contactNodeIdHex, String displayName, bool identityKeyChanged)?
      onContactRestoreDetected;

  @override
  void Function(String contactNodeIdHex, String displayName,
      int tokensPresent, int tokensRequired)? onRotationCoAuthWarning;
  @override
  void Function(String contactNodeIdHex, String displayName)?
      onRotationRejectionAlert;

  /// §7.5: the daemon parked a rotation-approval request and waits for an
  /// explicit user decision. Answer with [approveRotation] / [rejectRotation]
  /// — not answering sends nothing (silence is not consent). `kind` says
  /// whether this is a key rotation or a device-set change and MUST be shown
  /// to the user; the last argument lists the devices remaining after a
  /// device-set change.
  @override
  void Function(String rotationHashHex, String requestingDeviceIdHex,
          RotationApprovalKind kind, List<String> newDeviceNodeIdHexes)?
      onRotationApprovalRequest;

  @override
  Future<bool> approveRotation(String rotationHashHex) async {
    final resp = await _sendRequest('approve_rotation',
        params: {'rotationHashHex': rotationHashHex});
    return resp.success;
  }

  @override
  Future<bool> rejectRotation(String rotationHashHex) async {
    final resp = await _sendRequest('reject_rotation',
        params: {'rotationHashHex': rotationHashHex});
    return resp.success;
  }

  @override
  Future<List<Map<String, dynamic>>> getPendingRotationApprovals() async {
    final resp = await _sendRequest('get_pending_rotation_approvals');
    if (!resp.success) return const [];
    final list =
        resp.data['pendingRotationApprovals'] as List<dynamic>? ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  @override
  Future<String> createPoll({
    required String question,
    String description = '',
    required PollType pollType,
    required List<PollOption> options,
    required PollSettings settings,
    required String groupIdHex,
  }) async {
    final resp = await _sendRequest('poll_create', params: {
      'question': question,
      'description': description,
      'pollType': pollType.index,
      'options': options.map((o) => o.toJson()).toList(),
      'settings': settings.toJson(),
      'groupId': groupIdHex,
    });
    return resp.data['pollId'] as String? ?? '';
  }

  @override
  Future<bool> submitPollVote({
    required String pollId,
    List<int>? selectedOptions,
    Map<int, DateAvailability>? dateResponses,
    int? scaleValue,
    String? freeText,
  }) async {
    final resp = await _sendRequest('poll_vote', params: {
      'pollId': pollId,
      'selectedOptions': ?selectedOptions,
      'dateResponses':
          dateResponses?.map((k, v) => MapEntry(k.toString(), v.index)),
      'scaleValue': ?scaleValue,
      'freeText': ?freeText,
    });
    return resp.success;
  }

  @override
  Future<bool> submitPollVoteAnonymous({
    required String pollId,
    List<int>? selectedOptions,
    Map<int, DateAvailability>? dateResponses,
    int? scaleValue,
    String? freeText,
  }) async {
    final resp = await _sendRequest('poll_vote_anonymous', params: {
      'pollId': pollId,
      'selectedOptions': ?selectedOptions,
      'dateResponses':
          dateResponses?.map((k, v) => MapEntry(k.toString(), v.index)),
      'scaleValue': ?scaleValue,
      'freeText': ?freeText,
    });
    return resp.success;
  }

  @override
  Future<bool> revokePollVoteAnonymous(String pollId) async {
    final resp = await _sendRequest('poll_vote_revoke', params: {
      'pollId': pollId,
    });
    return resp.success;
  }

  @override
  Future<bool> updatePoll(String pollId, {
    bool? close,
    bool? reopen,
    List<PollOption>? addOptions,
    List<int>? removeOptions,
    int? newDeadline,
    bool delete = false,
  }) async {
    final resp = await _sendRequest('poll_update', params: {
      'pollId': pollId,
      'close': ?close,
      'reopen': ?reopen,
      'addOptions': addOptions?.map((o) => o.toJson()).toList(),
      'removeOptions': ?removeOptions,
      'newDeadline': ?newDeadline,
      'delete': delete,
    });
    return resp.success;
  }

  @override
  Future<String?> convertDatePollToEvent(String pollId, int winningOptionId) async {
    final resp = await _sendRequest('poll_convert_to_event', params: {
      'pollId': pollId,
      'winningOptionId': winningOptionId,
    });
    if (!resp.success) return null;
    return resp.data['eventId'] as String?;
  }

  /// Refresh poll state from the daemon (used on open_chat / Settings entry).
  Future<void> fetchPolls({String? groupIdHex}) async {
    final resp = await _sendRequest('poll_list', params: {
      'groupId': ?groupIdHex,
    });
    if (!resp.success) return;
    _pollManager.polls.clear();
    final list = resp.data['polls'] as List<dynamic>? ?? [];
    for (final p in list) {
      try {
        final poll = Poll.fromJson((p as Map).cast<String, dynamic>());
        _pollManager.polls[poll.pollId] = poll;
      } catch (_) {}
    }
  }

  /// Compute the local tally for a given poll. Returns an empty tally if
  /// the poll is unknown.
  PollTally pollTally(String pollId) => _pollManager.computeTally(pollId);

  // ── Calendar (§23) ──────────────────────────────────────────────

  /// Proxy CalendarManager — holds cached state from daemon, no local persistence.
  late final CalendarManager _calendarManager = CalendarManager(
    profileDir: '',
    identityId: _nodeIdHex,
  );

  @override
  CalendarManager get calendarManager => _calendarManager;

  @override
  IdentityContext get identity =>
      throw UnsupportedError('IdentityContext not available via IPC — use nodeIdHex');

  /// Calendar callbacks (forwarded from daemon events).
  void Function(String senderNodeIdHex, String eventId, String title)? onCalendarInviteReceived;
  void Function(String eventId, String responderNodeIdHex, RsvpStatus status)? onCalendarRsvpReceived;
  void Function(String eventId)? onCalendarEventUpdated;
  void Function(String eventId, String title, int minutesBefore)? onCalendarReminderDue;

  /// Fired after a sync run finishes. Payload contains pull/push counters.
  void Function(Map<String, dynamic> payload)? onCalendarSyncCompleted;
  /// Fired after the user successfully completes the Google OAuth2 flow.
  void Function(String accountEmail)? onCalendarSyncGoogleConnected;
  /// Fired when the Google OAuth2 flow fails (timeout, user denied, etc).
  void Function(String error)? onCalendarSyncGoogleError;
  /// Fired when a provider queues a conflict for user decision
  /// (askOnConflict=true). Payload matches PendingConflict.toJson().
  void Function(Map<String, dynamic> conflict)? onCalendarSyncConflictPending;

  @override
  Future<String> createCalendarEvent(CalendarEvent event) async {
    final resp = await _sendRequest('calendar_create_event', params: {
      'event': event.toJson(),
    });
    if (resp.success) {
      // Optimistic update: add to local proxy cache
      _calendarManager.events[event.eventId] = event;
    }
    return event.eventId;
  }

  @override
  Future<bool> updateCalendarEvent(String eventIdHex, {
    String? title, String? description, String? location,
    int? startTime, int? endTime, bool? allDay, bool? hasCall,
    List<int>? reminders, String? recurrenceRule,
    bool? taskCompleted, int? taskPriority, bool? cancelled,
    List<String>? attendeeNodeIds,
  }) async {
    final resp = await _sendRequest('calendar_update_event', params: {
      'eventId': eventIdHex,
      'updates': {
        'title': ?title,
        'description': ?description,
        'location': ?location,
        'startTime': ?startTime,
        'endTime': ?endTime,
        'allDay': ?allDay,
        'hasCall': ?hasCall,
        'reminders': ?reminders,
        'recurrenceRule': ?recurrenceRule,
        'taskCompleted': ?taskCompleted,
        'taskPriority': ?taskPriority,
        'cancelled': ?cancelled,
        'attendeeNodeIds': ?attendeeNodeIds,
      },
    });
    if (resp.success) {
      // Optimistic update: apply to local proxy cache
      _calendarManager.updateEvent(eventIdHex,
        title: title, description: description, location: location,
        startTime: startTime, endTime: endTime, allDay: allDay,
        hasCall: hasCall, reminders: reminders, recurrenceRule: recurrenceRule,
        taskCompleted: taskCompleted, taskPriority: taskPriority,
      );
    }
    return resp.success;
  }

  @override
  Future<bool> deleteCalendarEvent(String eventIdHex) async {
    final resp = await _sendRequest('calendar_delete_event', params: {
      'eventId': eventIdHex,
    });
    if (resp.success) {
      _calendarManager.events.remove(eventIdHex);
    }
    return resp.success;
  }

  @override
  Future<void> sendCalendarInvite(CalendarEvent event) async {
    // In IPC context, createCalendarEvent already handles group invites
    await createCalendarEvent(event);
  }

  @override
  Future<void> sendCalendarRsvp(String eventIdHex, RsvpStatus status, {int? proposedStart, int? proposedEnd, String? comment}) async {
    await _sendRequest('calendar_send_rsvp', params: {
      'eventId': eventIdHex,
      'status': status.index,
      'proposedStart': ?proposedStart,
      'proposedEnd': ?proposedEnd,
      'comment': ?comment,
    });
  }

  @override
  Future<void> sendCalendarUpdate(String eventIdHex) async {
    final event = _calendarManager.events[eventIdHex];
    if (event == null) return;
    await _sendRequest('calendar_update_event', params: {
      'eventId': eventIdHex,
      'updates': {
        'title': event.title,
        'description': event.description,
        'location': event.location,
        'startTime': event.startTime,
        'endTime': event.endTime,
        'allDay': event.allDay,
        'recurrenceRule': event.recurrenceRule,
        'hasCall': event.hasCall,
        'reminders': event.reminders,
        'taskCompleted': event.taskCompleted,
        'taskPriority': event.taskPriority,
      },
    });
  }

  @override
  Future<void> sendCalendarDelete(String eventIdHex) async {
    await _sendRequest('calendar_delete_event', params: {
      'eventId': eventIdHex,
    });
    _calendarManager.events.remove(eventIdHex);
  }

  @override
  Future<String> sendFreeBusyRequest(String contactNodeIdHex, int queryStart, int queryEnd) async {
    final resp = await _sendRequest('calendar_query_free_busy', params: {
      'contactNodeIdHex': contactNodeIdHex,
      'queryStart': queryStart,
      'queryEnd': queryEnd,
    });
    return resp.data['requestId'] as String? ?? '';
  }

  /// Fetch calendar events from daemon and populate proxy CalendarManager.
  Future<void> fetchCalendarEvents({int? windowStart, int? windowEnd}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final resp = await _sendRequest('calendar_list_events', params: {
      'windowStart': windowStart ?? now - 30 * 24 * 60 * 60 * 1000,
      'windowEnd': windowEnd ?? now + 90 * 24 * 60 * 60 * 1000,
    });
    if (resp.success) {
      _calendarManager.events.clear();
      final eventsList = resp.data['events'] as List<dynamic>? ?? [];
      for (final e in eventsList) {
        final eventJson = e as Map<String, dynamic>;
        try {
          final event = CalendarEvent.fromJson(eventJson);
          _calendarManager.events[event.eventId] = event;
        } catch (_) {}
      }
    }
  }

  // ── Calendar Sync (§23.8) ─────────────────────────────────────────

  /// Get current sync status (providers, last sync, errors).
  Future<Map<String, dynamic>> getCalendarSyncStatus() async {
    final resp = await _sendRequest('calendar_sync_status');
    if (!resp.success) return {};
    return (resp.data['status'] as Map?)?.cast<String, dynamic>() ?? {};
  }

  /// Trigger an immediate sync. Returns true if accepted; actual result
  /// arrives via the 'calendar_sync_completed' event.
  Future<bool> triggerCalendarSync() async {
    final resp = await _sendRequest('calendar_sync_trigger');
    return resp.success;
  }

  /// Probe a CalDAV server with the given credentials and return the
  /// discovered calendar list. Does not persist anything.
  Future<List<Map<String, dynamic>>> caldavListCalendars({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final resp = await _sendRequest('calendar_sync_caldav_list_calendars', params: {
      'config': {
        'serverUrl': serverUrl,
        'username': username,
        'password': password,
      },
    });
    if (!resp.success) throw Exception(resp.error ?? 'discovery failed');
    return ((resp.data['calendars'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// Save a CalDAV configuration for the active identity.
  Future<Map<String, dynamic>> configureCaldav({
    required String serverUrl,
    required String username,
    required String password,
    String? calendarUrl,
    String direction = 'bidirectional',
  }) async {
    final resp = await _sendRequest('calendar_sync_configure_caldav', params: {
      'config': <String, dynamic>{
        'serverUrl': serverUrl,
        'username': username,
        'password': password,
        // ignore: use_null_aware_elements
        if (calendarUrl != null) 'calendarUrl': calendarUrl,
        'direction': direction,
      },
    });
    if (!resp.success) throw Exception(resp.error ?? 'configure failed');
    return (resp.data['status'] as Map?)?.cast<String, dynamic>() ?? {};
  }

  Future<void> removeCaldavSync() async {
    final resp = await _sendRequest('calendar_sync_remove_caldav');
    if (!resp.success) throw Exception(resp.error ?? 'remove failed');
  }

  /// Begin Google OAuth2 consent flow. Returns the auth URL to open in the
  /// system browser. The daemon listens for the callback and fires a
  /// 'calendar_sync_google_connected' event on success.
  Future<String> startGoogleOauth({required String clientId}) async {
    final resp = await _sendRequest('calendar_sync_google_oauth_start', params: {
      'clientId': clientId,
    });
    if (!resp.success) throw Exception(resp.error ?? 'oauth start failed');
    return resp.data['authUrl'] as String;
  }

  Future<void> removeGoogleSync() async {
    final resp = await _sendRequest('calendar_sync_remove_google');
    if (!resp.success) throw Exception(resp.error ?? 'remove failed');
  }

  // ── Exchange (EWS) sync ───────────────────────────────────────────

  /// Configure Exchange sync with Basic auth (on-premise).
  Future<Map<String, dynamic>> configureExchange({
    required String serverUrl,
    required String email,
    required String username,
    required String password,
    String direction = 'bidirectional',
  }) async {
    final resp = await _sendRequest('calendar_sync_configure_exchange', params: {
      'config': <String, dynamic>{
        'serverUrl': serverUrl,
        'email': email,
        'username': username,
        'password': password,
        'direction': direction,
      },
    });
    if (!resp.success) throw Exception(resp.error ?? 'configure failed');
    return (resp.data['status'] as Map?)?.cast<String, dynamic>() ?? {};
  }

  /// Begin Exchange OAuth2 consent flow (Microsoft 365). Returns the auth
  /// URL to open in the system browser.
  Future<String> startExchangeOauth({
    required String clientId,
    required String email,
    String direction = 'bidirectional',
  }) async {
    final resp = await _sendRequest('calendar_sync_exchange_oauth_start', params: {
      'clientId': clientId,
      'email': email,
      'direction': direction,
    });
    if (!resp.success) throw Exception(resp.error ?? 'oauth start failed');
    return resp.data['authUrl'] as String;
  }

  /// Remove Exchange sync configuration for the active identity.
  Future<void> removeExchangeSync() async {
    final resp = await _sendRequest('calendar_sync_remove_exchange');
    if (!resp.success) throw Exception(resp.error ?? 'remove failed');
  }

  /// Run EWS Autodiscover for the given email to find the server URL.
  Future<String> ewsAutodiscover({required String email}) async {
    final resp = await _sendRequest('calendar_sync_ews_autodiscover', params: {
      'email': email,
    });
    if (!resp.success) throw Exception(resp.error ?? 'autodiscover failed');
    return resp.data['serverUrl'] as String;
  }

  /// Tell the daemon whether the calendar UI is in the foreground. Switches
  /// sync cadence between aggressive (foreground, ~3 min) and conservative
  /// (background, ~15 min).
  Future<void> setCalendarSyncForeground(bool foreground) async {
    await _sendRequest('calendar_sync_set_foreground', params: {
      'foreground': foreground,
    });
  }

  // ── Local CalDAV server (§23.8.7) ─────────────────────────────────

  /// Current state of the embedded CalDAV server.
  /// Shape: `{enabled, running, port, hasToken, token, baseUrl,
  /// identities: [{shortId, displayName, calendarUrl}, ...]}`.
  Future<Map<String, dynamic>> getCalDAVServerState() async {
    final resp = await _sendRequest('caldav_server_state');
    if (!resp.success) return {};
    return resp.data.cast<String, dynamic>();
  }

  /// Enable or disable the embedded CalDAV server. Returns the new state.
  Future<Map<String, dynamic>> setCalDAVServerEnabled(bool enabled) async {
    final resp = await _sendRequest('caldav_server_set_enabled', params: {
      'enabled': enabled,
    });
    if (!resp.success) {
      throw Exception(resp.error ?? 'caldav_server_set_enabled failed');
    }
    return resp.data.cast<String, dynamic>();
  }

  /// Generate a new random auth token for the embedded CalDAV server.
  /// Returns the new state (including the new token).
  Future<Map<String, dynamic>> regenerateCalDAVServerToken() async {
    final resp = await _sendRequest('caldav_server_regenerate_token');
    if (!resp.success) {
      throw Exception(
          resp.error ?? 'caldav_server_regenerate_token failed');
    }
    return resp.data.cast<String, dynamic>();
  }

  /// Change the listening port of the embedded CalDAV server. Returns
  /// the new state.
  Future<Map<String, dynamic>> setCalDAVServerPort(int port) async {
    final resp = await _sendRequest('caldav_server_set_port', params: {
      'port': port,
    });
    if (!resp.success) {
      throw Exception(resp.error ?? 'caldav_server_set_port failed');
    }
    return resp.data.cast<String, dynamic>();
  }

  /// Configure a local `.ics` file bridge (for Thunderbird/Outlook/Apple
  /// Calendar subscription). [direction] is `export`, `import`, or
  /// `bidirectional`.
  Future<void> configureLocalIcs({
    required String filePath,
    String direction = 'export',
    bool askOnConflict = false,
  }) async {
    final resp = await _sendRequest('calendar_sync_configure_local_ics', params: {
      'config': <String, dynamic>{
        'filePath': filePath,
        'direction': direction,
        'askOnConflict': askOnConflict,
      },
    });
    if (!resp.success) throw Exception(resp.error ?? 'configure failed');
  }

  Future<void> removeLocalIcsSync() async {
    final resp = await _sendRequest('calendar_sync_remove_local_ics');
    if (!resp.success) throw Exception(resp.error ?? 'remove failed');
  }

  /// Fetch the conflict log (resolved + pending).
  Future<Map<String, List<Map<String, dynamic>>>> listCalendarConflicts() async {
    final resp = await _sendRequest('calendar_sync_list_conflicts');
    if (!resp.success) return {'conflicts': [], 'pending': []};
    return {
      'conflicts': ((resp.data['conflicts'] as List?) ?? [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList(),
      'pending': ((resp.data['pending'] as List?) ?? [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList(),
    };
  }

  Future<void> clearCalendarConflicts() async {
    await _sendRequest('calendar_sync_clear_conflicts');
  }

  /// Restore the losing event from a recorded conflict.
  Future<bool> restoreCalendarConflict(String conflictId) async {
    final resp = await _sendRequest('calendar_sync_restore_conflict', params: {
      'conflictId': conflictId,
    });
    return resp.success;
  }

  /// Resolve a pending conflict by choosing which side to keep.
  /// [keep] must be `"local"` or `"external"`.
  Future<bool> resolvePendingCalendarConflict(
      String conflictId, String keep) async {
    final resp = await _sendRequest('calendar_sync_resolve_pending', params: {
      'conflictId': conflictId,
      'keep': keep,
    });
    return resp.success;
  }

  // ── Feature ②: Manual Reconnect (§12.3.1) ───────────────────────────────

  /// Trigger the full §12.3 recovery sequence on demand.
  ///
  /// The server enforces a 60-second debounce (mirrors Stage-5 cooldown).
  /// Returns a map with:
  ///   - `debounced` (bool): true if the call was suppressed by the cooldown
  ///   - `remainingSeconds` (int): seconds until the next call is allowed
  ///     (only meaningful when `debounced == true`)
  ///   - `peersFound` (int): number of currently active peers at call time
  Future<Map<String, dynamic>> manualReconnect() async {
    final resp = await _sendRequest('manual_reconnect');
    if (!resp.success) return {'debounced': false, 'peersFound': 0};
    return {
      'debounced': resp.data['debounced'] as bool? ?? false,
      'remainingSeconds': resp.data['remainingSeconds'] as int? ?? 0,
      'peersFound': resp.data['peersFound'] as int? ?? 0,
    };
  }

  // ── Media archive: share identity and narrowing (§21.6, S394) ──────────

  @override
  Future<Map<String, dynamic>?> getArchiveShareStatus() async {
    final resp = await _sendRequest('archive_status');
    return resp.success ? Map<String, dynamic>.from(resp.data) : null;
  }

  @override
  Future<bool> rebindArchiveShare() async =>
      (await _sendRequest('archive_rebind_share')).success;

  @override
  Future<Map<String, dynamic>?> captureArchiveNetwork() async {
    final resp = await _sendRequest('archive_capture_network');
    return resp.success ? Map<String, dynamic>.from(resp.data) : null;
  }

  @override
  Future<bool> clearArchiveNetworks() async =>
      (await _sendRequest('archive_clear_networks')).success;

  // ── Feature ③: Peer Rescue Bundle (§8.1.2) ──────────────────────────────

  /// Export a Peer Rescue Bundle for the active identity.
  ///
  /// Returns a map with:
  ///   - `bundleBase64` (String): raw bundle bytes encoded as Base64
  ///   - `uri` (String): `cleona://reconnect?b=<base64url>` URI
  ///   - `peerCount` (int): number of peers included in the bundle
  ///   - `createdAtMs` (int): creation timestamp in milliseconds since epoch
  @override
  Future<Map<String, dynamic>?> exportPeerBundle() async {
    final resp = await _sendRequest('export_peer_bundle');
    if (!resp.success) return null;
    return {
      'bundleBase64': resp.data['bundleBase64'] as String? ?? '',
      'uri': resp.data['uri'] as String? ?? '',
      'peerCount': resp.data['peerCount'] as int? ?? 0,
      'createdAtMs': resp.data['createdAtMs'] as int? ?? 0,
    };
  }

  /// Import and validate a Peer Rescue Bundle, then contact the listed peers
  /// and trigger the §12.3 recovery sequence.
  ///
  /// [uri] — a `cleona://reconnect?b=...` URI string.
  /// [bundleBase64] — alternatively, raw bundle bytes as Base64.
  /// Exactly one of the two must be provided.
  ///
  /// Returns a map with:
  ///   - `networkTagValid` (bool): true when the HMAC/network tag passed
  ///   - `sigValid` (bool): true when the exporter's Ed25519 sig verified
  ///   - `sigUnknownExporter` (bool): true when HMAC passed but no ed25519 pubkey was available
  ///   - `ageHours` (double): bundle age in hours
  ///   - `peerCount` (int): number of peers in the bundle
  ///   - `peersContacted` (int): number of peer addresses contacted
  @override
  Future<Map<String, dynamic>> importPeerBundle({
    String? uri,
    String? bundleBase64,
  }) async {
    assert(uri != null || bundleBase64 != null,
        'importPeerBundle: provide either uri or bundleBase64');
    final params = <String, dynamic>{};
    if (uri != null) params['uri'] = uri;
    if (bundleBase64 != null) params['bundleBase64'] = bundleBase64;

    final resp = await _sendRequest('import_peer_bundle', params: params);
    return {
      'networkTagValid': resp.data['networkTagValid'] as bool? ?? false,
      'sigValid': resp.data['sigValid'] as bool? ?? false,
      'sigUnknownExporter': resp.data['sigUnknownExporter'] as bool? ?? false,
      'ageHours': (resp.data['ageHours'] as num?)?.toDouble() ?? 0.0,
      'peerCount': resp.data['peerCount'] as int? ?? 0,
      'peersContacted': resp.data['peersContacted'] as int? ?? 0,
      'error': resp.data['error'] as String?,
    };
  }

  // ── Binary Seeding (§19.6.2) ─────────────────────────────────────────────

  /// WITHOUT CALLER, RE-MEASURED (S361) — but its counterpart answers
  /// again (02.09.2026).
  ///
  /// Here stood that `seed_binary` had been dropped server-side with the
  /// CUT (2026-08-31) and fell into the `default` branch ("Unknown
  /// command"). That applied until 02.09.2026 and no longer applies: the
  /// case is back in `ipc_server.dart`, the body lies as
  /// `CleonaService.seedBinaryFromFile` in `cleona_service_pure.dart`.
  /// The reasoning there in short: the deleted body only touches the local
  /// fragment store, and `_selfSeedCurrentBinary` takes the same path at
  /// start anyway.
  ///
  /// STILL APPLIES UNCHANGED: this method has no caller in `lib/` or
  /// `test/`. The callers of the WIRE COMMAND
  /// (`test/e2e/tests/binary-update.spec.ts`,
  /// `scripts/publish-in-network-update.sh:191`) bypass the client here
  /// and go directly via the raw IPC string. It stays nevertheless — it is
  /// the typed connection for GUI code, and since 02.09.2026 [maxFragments]
  /// is also evaluated server-side instead of thrown away.
  Future<Map<String, dynamic>> seedBinary({
    required String platform,
    required String version,
    required String filePath,
    int? maxFragments,
  }) async {
    final resp = await _sendRequest('seed_binary', params: {
      'platform': platform,
      'version': version,
      'filePath': filePath,
      'maxFragments': ?maxFragments,
    });
    return resp.data;
  }

  Future<Map<String, dynamic>> getSeededPlatforms() async {
    final resp = await _sendRequest('get_seeded_platforms');
    return resp.data;
  }

  @override
  Future<void> onNetworkChanged({bool triggerNodeReset = true}) async {
    // Network changes are handled by the daemon — IPC client is a no-op.
    // The `triggerNodeReset` flag is accepted for interface conformance only.
  }

  @override
  Future<void> stop() async {
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
    _connected = false;
  }

  /// Disconnect GUI client (does NOT stop the daemon).
  Future<void> disconnect() async {
    await stop();
  }
}

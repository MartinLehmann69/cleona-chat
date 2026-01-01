import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cleona/core/ipc/ipc_messages.dart';
import 'package:cleona/core/network/peer_info.dart' show bytesToHex;
import 'package:cleona/core/service/service_interface.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/core/network/network_stats.dart';
import 'package:cleona/core/service/notification_sound_service.dart';
import 'package:cleona/core/media/link_preview_fetcher.dart';
import 'package:cleona/core/services/contact_manager.dart' show Contact;
import 'package:cleona/core/calendar/calendar_manager.dart';
import 'package:cleona/core/polls/poll_manager.dart';
import 'package:cleona/core/node/identity_context.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// IPC client that connects to the cleona-daemon via Unix Domain Socket.
/// Implements ICleonaService so the GUI can use it transparently.
class IpcClient implements ICleonaService {
  final String socketPath;

  Socket? _socket;
  int _nextRequestId = 1;
  final Map<int, Completer<IpcResponse>> _pendingRequests = {};
  final StringBuffer _buffer = StringBuffer();
  bool _connected = false;

  /// Called when the daemon socket closes unexpectedly.
  /// GUI should exit — daemon and GUI act as one unit.
  void Function()? onDaemonDied;

  // Active identity for this client connection
  String? activeIdentityId;

  // Cached state from daemon
  String _nodeIdHex = '';
  String _displayName = '';
  int _port = 0;
  int _peerCount = 0;
  int _confirmedPeerCount = 0;
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

      // Fetch initial state
      await refreshState();
      return true;
    } catch (e) {
      _connected = false;
      return false;
    }
  }

  void _attachSocketListener() {
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
      // All retries exhausted — daemon really is gone.
      onDaemonDied?.call();
    } finally {
      _reconnecting = false;
    }
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
    // Event for a different identity — track unread counts, handle calls
    if (event.identityId != null &&
        activeIdentityId != null &&
        event.identityId != activeIdentityId) {
      if (event.event == 'incoming_call') {
        final call = CallInfo.fromJson(event.data);
        _currentCall = call;
        onIncomingCall?.call(call);
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
        _peerCount = event.data['peerCount'] as int? ?? _peerCount;
        _confirmedPeerCount = event.data['confirmedPeerCount'] as int? ?? _confirmedPeerCount;
        _hasPortMapping = event.data['hasPortMapping'] as bool? ?? _hasPortMapping;
        _mobileFallbackActive = event.data['mobileFallbackActive'] as bool? ?? _mobileFallbackActive;
        _isRunning = event.data['isRunning'] as bool? ?? _isRunning;
        onStateChanged?.call();
        _scheduleRefresh();
        break;
      case 'new_message':
        final convId = event.data['conversationId'] as String;
        final msgData = event.data['message'] as Map<String, dynamic>;
        final message = UiMessage.fromJson(msgData);
        // Update local state
        final conv = conversations[convId];
        if (conv != null) {
          conv.messages.add(message);
          conv.lastActivity = message.timestamp;
          if (!message.isOutgoing) conv.unreadCount++;
        }
        onNewMessage?.call(convId, message);
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
    }
  }

  void _applyStateSnapshot(Map<String, dynamic> state) {
    _nodeIdHex = state['nodeIdHex'] as String? ?? _nodeIdHex;
    _displayName = state['displayName'] as String? ?? _displayName;
    _port = state['port'] as int? ?? _port;
    _peerCount = state['peerCount'] as int? ?? _peerCount;
    _confirmedPeerCount = state['confirmedPeerCount'] as int? ?? _confirmedPeerCount;
    _mobileFallbackActive = state['mobileFallbackActive'] as bool? ?? _mobileFallbackActive;
    _fragmentCount = state['fragmentCount'] as int? ?? _fragmentCount;
    _isRunning = state['isRunning'] as bool? ?? _isRunning;
    _profilePictureBase64 = state['profilePicture'] as String?;
    _profileDescription = state['profileDescription'] as String?;
    _isGuardianSetUp = state['isGuardianSetUp'] as bool? ?? false;
    final ms = state['mediaSettings'] as Map<String, dynamic>?;
    if (ms != null) _mediaSettings = MediaSettings.fromJson(ms);
    final lps = state['linkPreviewSettings'] as Map<String, dynamic>?;
    if (lps != null) _linkPreviewSettings = LinkPreviewSettings.fromJson(lps);
    final ns = state['notificationSettings'] as Map<String, dynamic>?;
    if (ns != null) _notificationSoundService.updateSettings(NotificationSettings.fromJson(ns));

    // Network info for QR code generation
    final ips = state['localIps'] as List<dynamic>?;
    if (ips != null) _localIps = ips.cast<String>();
    _publicIp = state['publicIp'] as String?;
    _publicPort = state['publicPort'] as int?;

    // Multi-Device (§26)
    final devList = state['devices'] as List<dynamic>?;
    if (devList != null) {
      _devices = devList
          .map((d) => DeviceRecord.fromJson(d as Map<String, dynamic>))
          .toList();
    }
    _localDeviceId = state['localDeviceId'] as String? ?? _localDeviceId;

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

    final peers = state['peerSummaries'] as List<dynamic>?;
    if (peers != null) {
      _peerSummaries = peers
          .map((p) => PeerSummary.fromJson(p as Map<String, dynamic>))
          .toList();
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

  Future<IpcResponse> _sendRequest(String command, {
    Map<String, dynamic> params = const {},
    String? identityId,
  }) async {
    if (!_connected || _socket == null) {
      return IpcResponse(id: -1, success: false, error: 'Not connected');
    }

    final id = _nextRequestId++;
    final request = IpcRequest(
      id: id,
      command: command,
      params: params,
      identityId: identityId,
    );
    final completer = Completer<IpcResponse>();
    _pendingRequests[id] = completer;

    try {
      _socket!.write(request.toJsonLine());
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

  /// Debounced refresh: coalesces multiple state_changed events into one get_state call.
  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(seconds: 1), () async {
      await refreshState();
    });
  }

  /// Fetch full state from daemon.
  Future<void> refreshState() async {
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
  String get displayName => _displayName;
  @override
  int get port => _port;
  @override
  int get peerCount => _peerCount;
  @override
  int get confirmedPeerCount => _confirmedPeerCount;
  @override
  bool get hasPortMapping => _hasPortMapping;
  bool get mobileFallbackActive => _mobileFallbackActive;
  @override
  int get fragmentCount => _fragmentCount;
  @override
  bool get isRunning => _isRunning;
  // sec-h5 §8.2 / T11 + Folge-Task 2026-04-26: reducedMode is a per-session
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
  ContactInfo? getContact(String nodeIdHex) {
    for (final c in [..._acceptedContacts, ..._pendingContacts]) {
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
  Future<UiMessage?> sendTextMessage(String recipientNodeIdHex, String text, {String? replyToMessageId, String? replyToText, String? replyToSender}) async {
    final resp = await _sendRequest('send_text', params: {
      'recipientId': recipientNodeIdHex,
      'text': text,
      'replyToMessageId': ?replyToMessageId,
      'replyToText': ?replyToText,
      'replyToSender': ?replyToSender,
    });
    if (resp.success) {
      final msg = UiMessage(
        id: resp.data['messageId'] as String? ?? '',
        conversationId: recipientNodeIdHex,
        senderNodeIdHex: _nodeIdHex,
        text: text,
        timestamp: DateTime.now(),
        type: proto.MessageType.TEXT,
        status: MessageStatus.sent,
        isOutgoing: true,
      );
      return msg;
    }
    return null;
  }

  @override
  Future<UiMessage?> sendMediaMessage(String conversationId, String filePath) async {
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
        type: proto.MessageType.FILE,
        status: MessageStatus.sent,
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

  @override
  void setActiveConversationId(String? conversationId) {
    // Daemon-side notifications (sound/vibrate/Android-banner) are emitted in
    // the daemon process; the GUI tracking lives in CleonaService directly on
    // Android (in-process). On desktop the daemon has no Android-banner path
    // and desktop foreground tracking is out of scope for #U18 — no-op here.
  }

  @override
  void setAppResumed(bool isResumed) {
    // No-op (see setActiveConversationId).
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
      type: proto.MessageType.TEXT,
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
  Future<UiMessage?> sendGroupTextMessage(String groupIdHex, String text) async {
    final resp = await _sendRequest('send_group_text', params: {
      'groupIdHex': groupIdHex,
      'text': text,
    });
    if (resp.success) {
      return UiMessage(
        id: resp.data['messageId'] as String? ?? '',
        conversationId: groupIdHex,
        senderNodeIdHex: _nodeIdHex,
        text: text,
        timestamp: DateTime.now(),
        type: proto.MessageType.TEXT,
        status: MessageStatus.sent,
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
    String? description,
    String? pictureBase64,
  }) async {
    final resp = await _sendRequest('create_channel', params: {
      'name': name,
      'subscriberIds': subscriberNodeIdHexList,
      'isPublic': isPublic,
      'isAdult': isAdult,
      'language': language,
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
        type: proto.MessageType.CHANNEL_POST,
        status: MessageStatus.sent,
        isOutgoing: true,
      );
    }
    return null;
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

  @override
  List<JuryRequest> get pendingJuryRequests => [];

  @override
  Map<String, dynamic> getChannelModerationInfo(String channelIdHex) => {};

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

  /// Change the daemon's listening port at runtime.
  /// Returns true on success, false on failure (port in use, invalid range).
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
  @override
  void addNfcContact(Contact contact) {
    // NFC contacts are added via the daemon's in-process service, not IPC
    throw UnsupportedError('NFC contact add not available via IPC');
  }

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

  @override
  Future<bool> sendContactRequest(String recipientNodeIdHex, {String message = ''}) async {
    final resp = await _sendRequest('send_contact_request', params: {
      'recipientId': recipientNodeIdHex,
    });
    return resp.success;
  }

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
    List<({String nodeIdHex, List<String> addresses})> seedPeers,
  ) {
    // On GUI side: send seed peers via IPC to daemon for routing table injection
    _sendRequest('add_seed_peers', params: {
      'targetNodeIdHex': targetNodeIdHex,
      'targetAddresses': targetAddresses,
      'seedPeers': seedPeers.map((p) => {
        'nodeIdHex': p.nodeIdHex,
        'addresses': p.addresses,
      }).toList(),
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
  void deleteContact(String nodeIdHex) {
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
  void acceptContactNameChange(String nodeIdHex, bool accept) {
    _sendRequest('accept_name_change', params: {
      'nodeIdHex': nodeIdHex,
      'accept': accept,
    });
  }

  @override
  List<PeerSummary> get peerSummaries => _peerSummaries;

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

  @override
  String get localDeviceId => _localDeviceId;

  void Function()? onDevicesUpdated;

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
    bool? taskCompleted, int? taskPriority,
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

  @override
  Future<void> onNetworkChanged() async {
    // Network changes are handled by the daemon
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

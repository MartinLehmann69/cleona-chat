import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/ipc/ipc_messages.dart';
import 'package:cleona/core/moderation/moderation_config.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/network/peer_info.dart' show hexToBytes;
import 'package:cleona/core/service/cleona_service.dart';
import 'package:cleona/core/service/notification_sound_service.dart';
import 'package:cleona/core/archive/archive_config.dart';
import 'package:cleona/core/archive/archive_transport.dart';
import 'package:cleona/core/calendar/sync/sync_types.dart';
import 'package:cleona/core/calendar/sync/caldav_client.dart';
import 'package:cleona/core/calendar/sync/google_calendar_client.dart';

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
  ModerationConfig _moderationConfig = ModerationConfig.production();

  /// Shared secret for TCP loopback auth (Windows only). Null on Unix socket.
  String? _authToken;

  /// Callback to create a new identity at runtime (returns nodeIdHex or null).
  Future<String?> Function(String displayName)? onCreateIdentity;
  /// Callback to delete an identity at runtime.
  Future<bool> Function(String nodeIdHex)? onDeleteIdentity;

  /// Local CalDAV server control — wired by the daemon. All four are fired
  /// by the `caldav_server_*` IPC commands.
  Map<String, dynamic> Function()? onCalDAVServerGetState;
  Future<Map<String, dynamic>> Function(bool enabled)? onCalDAVServerSetEnabled;
  Future<Map<String, dynamic>> Function()? onCalDAVServerRegenerateToken;
  Future<Map<String, dynamic>> Function(int port)? onCalDAVServerSetPort;

  IpcServer({
    required Map<String, CleonaService> services,
    required this.socketPath,
    required String defaultIdentityId,
  })  : _services = Map.of(services),
        _defaultIdentityId = defaultIdentityId,
        _log = CLogger.get('ipc-server');

  Future<void> start() async {
    // Ensure parent directory exists
    final parentDir = socketPath.substring(0, socketPath.lastIndexOf(Platform.isWindows ? '\\' : '/'));
    Directory(parentDir).createSync(recursive: true);

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
          'peerCount': service.peerCount,
          'confirmedPeerCount': service.confirmedPeerCount,
          'hasPortMapping': service.hasPortMapping,
          'isRunning': service.isRunning,
          'mobileFallbackActive': service.node.transport.isMobileFallbackActive,
        },
        identityId: identityId,
      ));
    };

    final originalOnNewMessage = service.onNewMessage;
    service.onNewMessage = (conversationId, message) {
      originalOnNewMessage?.call(conversationId, message);
      _broadcastEvent(IpcEvent(
        event: 'new_message',
        data: {
          'conversationId': conversationId,
          'message': message.toJson(),
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

    // §26.6.2 Paket C: dedicated event when an emergency-key-rotation retry
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
        if (json['type'] == 'auth' && json['token'] == _authToken) {
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
    try {
      switch (req.command) {
        // ── Identity management commands ─────────────────────────────
        case 'list_identities':
          final identities = _services.entries.map((e) => {
            'identityId': e.key,
            'displayName': e.value.displayName,
            'nodeIdHex': e.value.nodeIdHex,
            'isActive': e.key == client.activeIdentityId,
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
            _sendResponse(client, IpcResponse(
              id: req.id,
              success: true,
              data: service.getStateSnapshot(),
            ));
          } else {
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
          // sec-h5 §8.2 / Folge-Task 2026-04-26: GUI splash on Desktop
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
            // Add identities list to state
            state['identities'] = _services.entries.map((e) => {
              'identityId': e.key,
              'displayName': e.value.displayName,
              'nodeIdHex': e.value.nodeIdHex,
            }).toList();
            state['activeIdentityId'] = client.activeIdentityId;
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
              ? await service.sendGroupTextMessage(recipientId, text)
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
          final mediaResult = await service.sendMediaMessage(mediaConvId, mediaFilePath);
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
          final favConvId = req.params['conversationId'] as String?;
          if (favConvId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: conversationId'));
            break;
          }
          if (service != null) {
            service.toggleFavorite(favConvId);
          }
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'send_typing':
          final service = _resolveService(client, req);
          final typingConvId = req.params['conversationId'] as String?;
          if (typingConvId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: conversationId'));
            break;
          }
          if (service != null) {
            service.sendTypingIndicator(typingConvId);
          }
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'mark_read':
          final service = _resolveService(client, req);
          final markReadConvId = req.params['conversationId'] as String?;
          if (markReadConvId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: conversationId'));
            break;
          }
          if (service != null) {
            service.markConversationRead(markReadConvId);
          }
          _sendResponse(client, IpcResponse(id: req.id, success: true));
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

        case 'send_contact_request':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final recipientId = req.params['recipientId'] as String?;
          if (recipientId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: recipientId'));
            break;
          }
          final success = await service.sendContactRequest(recipientId);
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: success,
          ));
          break;

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
          service.addPeersFromContactSeed(targetHex, targetAddrs, seedPeers);
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
          service.deleteContact(nodeIdHex);
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: true,
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
          if (groupName == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: name'));
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
          final groupMsg = await service.sendGroupTextMessage(groupId, groupText);
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
          final chDescription = req.params['description'] as String?;
          final chPicture = req.params['pictureBase64'] as String?;
          final channelIdHex = await service.createChannel(chName, subscriberIds,
            isPublic: chIsPublic, isAdult: chIsAdult, language: chLanguage,
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

        case 'report_channel':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final rptChId = (req.params['channelIdHex'] ?? req.params['channelId']) as String?;
          final rptCatRaw = req.params['category'];
          final rptCat = rptCatRaw is int ? rptCatRaw : _parseCategoryString(rptCatRaw as String?);
          final rptEvidence = (req.params['evidencePostIds'] as List<dynamic>?)?.cast<String>() ?? [];
          final rptDesc = req.params['description'] as String?;
          if (rptChId == null || rptCat == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing params'));
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
          final rptpChId = (req.params['channelIdHex'] ?? req.params['channelId']) as String?;
          final rptpPostId = req.params['postId'] as String?;
          final rptpCatRaw = req.params['category'];
          final rptpCat = rptpCatRaw is int ? rptpCatRaw : _parseCategoryString(rptpCatRaw as String?);
          final rptpDesc = req.params['description'] as String?;
          if (rptpChId == null || rptpPostId == null || rptpCat == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing params'));
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
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing params'));
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
          _moderationConfig = preset == 'test'
              ? ModerationConfig.test()
              : ModerationConfig.production();
          // Propagate to all services
          for (final service in _services.values) {
            service.moderationConfig = _moderationConfig;
          }
          _sendResponse(client, IpcResponse(id: req.id, success: true));
          break;

        case 'create_public_channel':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final pubChName = req.params['name'] as String?;
          if (pubChName == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: name'));
            break;
          }
          final pubChLang = req.params['language'] as String? ?? 'de';
          final pubChAdult = req.params['isAdultContent'] as bool? ?? true;
          final pubChDesc = req.params['description'] as String?;
          final pubChId = await service.createChannel(pubChName, [],
            isPublic: true, isAdult: pubChAdult, language: pubChLang, description: pubChDesc);
          _sendResponse(client, IpcResponse(
            id: req.id,
            success: pubChId != null,
            data: pubChId != null ? {'channelIdHex': pubChId} : {},
          ));
          break;

        case 'subscribe_to_channel':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final subChId = req.params['channelId'] as String?;
          if (subChId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: channelId'));
            break;
          }
          final subResult = await service.joinPublicChannel(subChId);
          _sendResponse(client, IpcResponse(id: req.id, success: subResult));
          break;

        case 'get_channel_moderation_info':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final modChId = req.params['channelId'] as String?;
          if (modChId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: channelId'));
            break;
          }
          final modInfo = service.getChannelModerationInfo(modChId);
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

        case 'vote_on_jury':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final vjRequestId = req.params['requestId'] as String?;
          final vjVote = req.params['vote'] as String?;
          if (vjRequestId == null || vjVote == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing params'));
            break;
          }
          final vjVoteIdx = vjVote == 'approve' ? 0 : (vjVote == 'reject' ? 1 : 2);
          final vjResult = await service.submitJuryVote(vjRequestId, vjRequestId, vjVoteIdx);
          _sendResponse(client, IpcResponse(id: req.id, success: vjResult));
          break;

        case 'dismiss_post_report':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final dprChId = req.params['channelId'] as String?;
          final dprReportId = req.params['reportId'] as String?;
          if (dprChId == null || dprReportId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing params'));
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
          final sbcChId = req.params['channelId'] as String?;
          if (sbcChId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: channelId'));
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
          final cchChId = req.params['channelId'] as String?;
          if (cchChId == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: channelId'));
            break;
          }
          final cchResult = await service.contestCsamHide(cchChId);
          _sendResponse(client, IpcResponse(id: req.id, success: cchResult));
          break;

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
            data: gcInfo != null ? gcInfo.toJson() : {'error': 'Failed to start group call'},
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
          // Test-only (E2E gui-53): clear the persistent
          // `nat_wizard_dismissed_until` flag so the next trigger can fire
          // again. Pair with the GUI-level latch reset via
          // `gui_action('reset_nat_wizard_latch')`.
          {
            final service = _resolveService(client, req);
            if (service == null) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
              break;
            }
            service.testResetNatWizardDismissed();
            _sendResponse(client, IpcResponse(id: req.id, success: true));
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
          final rbResult = await service.sendRestoreBroadcast(
            oldEd25519Sk: hexToBytes(oldSkHex),
            oldEd25519Pk: hexToBytes(oldPkHex),
            oldNodeId: hexToBytes(oldNidHex),
            oldContacts: oldContacts,
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
          try {
            await portService.node.changePort(newPort);
            // Persist in identities.json so daemon uses new port on restart
            final mgr = IdentityManager();
            mgr.updatePort(newPort);
            _sendResponse(client, IpcResponse(id: req.id, success: true, data: {'port': newPort}));
          } on SocketException catch (e) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Port $newPort nicht verfügbar: $e'));
          }
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

        case 'get_reputation':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final repNodeIdHex = req.params['nodeIdHex'] as String?;
          if (repNodeIdHex == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'Missing param: nodeIdHex'));
            break;
          }
          final rep = service.node.reputationManager.getReputation(repNodeIdHex);
          _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
            'score': rep?.score ?? 0.5,
            'goodActions': rep?.goodActions ?? 0,
            'badActions': rep?.badActions ?? 0,
            'isBanned': rep?.isBanned ?? false,
          }));
          break;

        case 'get_rate_limiter_stats':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
            'droppedPackets': service.node.rateLimiter.droppedPackets,
          }));
          break;

        case 'archive_status':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          final mgr = service.archiveManager;
          _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
            'active': mgr != null,
            'entriesCount': mgr?.entries.length ?? 0,
            'pendingCount': mgr?.pendingEntries.length ?? 0,
          }));
          break;

        case 'archive_test_connection':
          final service = _resolveService(client, req);
          if (service == null) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No active service'));
            break;
          }
          try {
            final configFile = File('${service.profileDir}/archive_config.json');
            if (!configFile.existsSync()) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No archive config'));
              break;
            }
            final config = ArchiveConfig.fromJson(
                json.decode(configFile.readAsStringSync()) as Map<String, dynamic>);
            if (config.archiveHost.isEmpty) {
              _sendResponse(client, IpcResponse(id: req.id, success: false, error: 'No host configured'));
              break;
            }
            final transport = ArchiveTransport.forProtocol(config.defaultProtocol);
            await transport.connect(
              host: config.archiveHost,
              path: config.archivePath,
              username: config.archiveUsername,
              password: config.archivePassword,
              port: config.archivePort,
            );
            final ok = await transport.testConnectivity(timeout: const Duration(seconds: 5));
            await transport.disconnect();
            _sendResponse(client, IpcResponse(id: req.id, success: ok, data: {
              'reachable': ok,
              'protocol': config.defaultProtocol.name,
              'host': config.archiveHost,
            }));
          } catch (e) {
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: '$e'));
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
          final result = await mgr.runArchiveCheck(conversations: service.conversations);
          _sendResponse(client, IpcResponse(id: req.id, success: true, data: {
            'archived': result.archived,
            'failed': result.failed,
            'tierChecked': result.tierChecked,
            'evicted': result.evicted,
            'skippedReason': result.skippedReason,
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

        case 'get_seed_phrase':
          final cleonaDir = socketPath.substring(0, socketPath.lastIndexOf(Platform.isWindows ? '\\' : '/'));
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
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: '$e'));
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
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: '$e'));
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
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: '$e'));
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
            _sendResponse(client, IpcResponse(id: req.id, success: false, error: '$e'));
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
                error: '$e'));
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
                error: '$e'));
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

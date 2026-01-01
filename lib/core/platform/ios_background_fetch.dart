import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:cleona/core/node/cleona_node.dart';
import 'package:cleona/core/node/identity_context.dart';
import 'package:cleona/core/service/cleona_service.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/crypto/network_secret.dart';
import 'package:cleona/core/network/sender_identity_snapshot.dart';
import 'package:cleona/core/platform/app_paths.dart';
import 'package:cleona/generated/proto/cleona.pb.dart' as proto;

/// iOS Background Fetch integration via BGTaskScheduler (Architecture S12.5).
///
/// Communicates with the native Swift `BackgroundFetchHandler` via
/// `MethodChannel('cleona/background_fetch')`. The Dart side handles the
/// heavy P2P work (node startup, peer contact, message retrieval, decryption),
/// while the Swift side manages OS task lifecycle and local notifications.
///
/// NO APNs, NO Firebase, NO push -- pure OS-controlled pull.
class IosBackgroundFetch {
  static const _channel = MethodChannel('cleona/background_fetch');

  /// Whether a background fetch is currently in progress.
  static bool _isFetching = false;

  /// Initialize the MethodChannel handler. Called once during app startup
  /// from `_initAndroidInProcess()` (which also handles iOS). Sets up the
  /// handler for incoming `performBackgroundFetch` calls from the native side.
  static void init() {
    _channel.setMethodCallHandler(_handleMethodCall);
    debugPrint('[ios-bg-fetch] MethodChannel handler registered');
  }

  /// Schedule the next background fetch via the native side.
  /// Called when the app transitions to background (AppLifecycleState.paused).
  static Future<void> scheduleBackgroundFetch() async {
    try {
      await _channel.invokeMethod('scheduleBackgroundFetch');
      debugPrint('[ios-bg-fetch] Scheduled background fetch');
    } catch (e) {
      debugPrint('[ios-bg-fetch] Failed to schedule: $e');
    }
  }

  /// Cancel any pending background fetch tasks.
  static Future<void> cancelBackgroundFetch() async {
    try {
      await _channel.invokeMethod('cancelBackgroundFetch');
      debugPrint('[ios-bg-fetch] Cancelled background fetch');
    } catch (e) {
      debugPrint('[ios-bg-fetch] Failed to cancel: $e');
    }
  }

  /// Handle incoming method calls from the native Swift side.
  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'performBackgroundFetch':
        final args = call.arguments as Map<Object?, Object?>?;
        final taskType = (args?['taskType'] as String?) ?? 'refresh';
        return _performBackgroundFetch(taskType: taskType);
      default:
        throw MissingPluginException('Unknown method: ${call.method}');
    }
  }

  /// Execute the background fetch: start a minimal node, contact known peers,
  /// retrieve pending messages, and return results to the native side.
  ///
  /// [taskType] is "refresh" (BGAppRefreshTask, ~30s window, peer budget 3)
  /// or "processing" (BGProcessingTask, minutes-long window, peer budget 10).
  ///
  /// Returns a map: {messageCount: int, senderNames: [String], previews: [String]}
  ///
  /// The 9-step wakeup chain (S12.5):
  /// 1. Load saved routing state
  /// 2. Open UDP socket (CleonaNode.startQuick())
  /// 3. Contact known peers (budget depends on taskType)
  /// 4. Retrieve Store-and-Forward messages
  /// 5. Retrieve Reed-Solomon fragments
  /// 6. Decrypt & notify
  /// 7. Persist state (saveNetworkState)
  /// 8. Close socket (node shutdown)
  /// 9. Return results (native side schedules next task)
  static Future<Map<String, dynamic>> _performBackgroundFetch({
    String taskType = 'refresh',
  }) async {
    if (_isFetching) {
      debugPrint('[ios-bg-fetch] Already fetching, returning empty');
      return {'messageCount': 0, 'senderNames': <String>[], 'previews': <String>[]};
    }

    final isProcessing = taskType == 'processing';
    final peerContactBudget = isProcessing ? 10 : 3;
    // BGProcessingTask gives minutes; BGAppRefreshTask ~30s (20s effective).
    final waitSeconds = isProcessing ? 120 : 20;

    _isFetching = true;
    debugPrint('[ios-bg-fetch] Starting background fetch '
        '(type=$taskType, peerBudget=$peerContactBudget, wait=${waitSeconds}s)...');

    CleonaNode? node;
    final services = <CleonaService>[];
    final newMessages = <_FetchedMessage>[];

    try {
      // Step 1: Load identities and routing state
      final mgr = IdentityManager();
      final identities = mgr.loadIdentities();
      if (identities.isEmpty) {
        debugPrint('[ios-bg-fetch] No identities, aborting');
        return {'messageCount': 0, 'senderNames': <String>[], 'previews': <String>[]};
      }

      final masterSeed = mgr.loadMasterSeed();
      final firstId = identities.first;
      final baseDir = '${AppPaths.home}/.cleona';

      // Create identity contexts for all identities
      final contexts = <String, IdentityContext>{};
      for (final id in identities) {
        final ctx = IdentityContext(
          profileDir: id.profileDir,
          displayName: id.displayName,
          networkChannel: NetworkSecret.channel.name,
          hdIndex: id.hdIndex,
          masterSeed: masterSeed,
          createdAt: id.createdAt,
          isAdult: id.isAdult,
        );
        await ctx.initKeys();
        id.nodeIdHex = ctx.userIdHex;
        contexts[ctx.userIdHex] = ctx;
      }

      // Step 2: Create and start the node (quick start -- no discovery burst)
      node = CleonaNode(
        profileDir: baseDir,
        port: firstId.port,
        networkChannel: NetworkSecret.channel.name,
      );

      final primaryCtx = contexts.values.first;
      node.primaryIdentity = primaryCtx;

      // Register all identities with the node
      for (final ctx in contexts.values) {
        node.registerIdentity(ctx);
      }

      await node.startQuick();
      debugPrint('[ios-bg-fetch] Node started on port ${firstId.port}');

      // Step 3-5: Create services and poll for messages.
      // Track message counts before and after polling.
      for (final ctx in contexts.values) {
        final service = CleonaService(
          identity: ctx,
          node: node,
          displayName: ctx.displayName,
        );
        await service.startService();
        services.add(service);
      }

      // Record baseline unread counts per conversation
      final baselineUnread = <String, Map<String, int>>{};
      for (final service in services) {
        final counts = <String, int>{};
        for (final entry in service.conversations.entries) {
          counts[entry.key] = entry.value.unreadCount;
        }
        baselineUnread[service.nodeIdHex] = counts;
      }

      // Wire the KEM-Try-Loop for incoming application frames (same as main.dart)
      node.onApplicationFramePayload = (packet, from, port, snapshot) async {
        for (final service in services) {
          final outcome = await service.handleIncomingApplicationPacket(
              packet, from, port, snapshot);
          if (outcome == AppFrameDispatchOutcome.delivered ||
              outcome == AppFrameDispatchOutcome.droppedAfterDecap) {
            return;
          }
        }
      };

      // Wire infrastructure frame handler.
      // Capture node as non-null local for the closure.
      final nodeRef = node;
      node.onInfrastructureFramePayload = (frame, senderDeviceId, from, port, snapshot) {
        // Simplified: route to all services (background fetch is short-lived)
        for (final service in services) {
          _routeInfraFrame(service, nodeRef, frame, senderDeviceId, from, port, snapshot);
        }
      };

      // BGAppRefreshTask: ~30s window → 20s for messages, rest for state save.
      // BGProcessingTask: minutes-long window → 120s for broader peer contact.
      debugPrint('[ios-bg-fetch] Waiting for message retrieval (${waitSeconds}s)...');
      await Future<void>.delayed(Duration(seconds: waitSeconds));

      // Step 6: Collect new messages
      for (final service in services) {
        final baseline = baselineUnread[service.nodeIdHex] ?? {};
        for (final entry in service.conversations.entries) {
          final convId = entry.key;
          final conv = entry.value;
          final previousUnread = baseline[convId] ?? 0;
          final newCount = conv.unreadCount - previousUnread;
          if (newCount > 0) {
            // Get the latest incoming messages
            final incomingMsgs = conv.messages
                .where((m) => !m.isOutgoing)
                .toList();
            if (incomingMsgs.isNotEmpty) {
              final latest = incomingMsgs.last;
              newMessages.add(_FetchedMessage(
                senderName: conv.displayName,
                preview: _messagePreview(latest),
              ));
            }
          }
        }
      }

      debugPrint('[ios-bg-fetch] Found ${newMessages.length} new message(s)');

      // Step 7: Persist state
      for (final service in services) {
        service.saveState();
      }
      node.saveNetworkState();

    } catch (e, stack) {
      debugPrint('[ios-bg-fetch] Error: $e\n$stack');
    } finally {
      // Step 8: Clean shutdown
      for (final service in services) {
        try {
          await service.stop();
        } catch (_) {}
      }
      if (node != null) {
        try {
          await node.stop();
        } catch (_) {}
      }
      _isFetching = false;
      debugPrint('[ios-bg-fetch] Background fetch complete');
    }

    // Step 9: Return results to native side (native handles scheduling + notifications)
    final totalCount = newMessages.length;
    return {
      'messageCount': totalCount,
      'senderNames': newMessages.map((m) => m.senderName).toList(),
      'previews': newMessages.map((m) => m.preview).toList(),
    };
  }

  /// Route an infrastructure frame to the appropriate service handler.
  /// During background fetch only message-retrieval-related frame types
  /// are relevant (FRAGMENT_RETRIEVE_RESPONSE, PEER_RETRIEVE_RESPONSE,
  /// and their store counterparts).
  static void _routeInfraFrame(
    CleonaService service,
    CleonaNode node,
    proto.InfrastructureFrameV3 frame,
    Uint8List senderDeviceId,
    InternetAddress from,
    int port,
    SenderIdentitySnapshot snapshot,
  ) {
    try {
      final mt = frame.messageType;
      switch (mt) {
        case proto.MessageTypeV3.MTV3_FRAGMENT_RETRIEVE_RESPONSE:
          service.handleIncomingFragmentRetrieveResponseInfra(frame, senderDeviceId);
          break;
        case proto.MessageTypeV3.MTV3_PEER_RETRIEVE_RESPONSE:
          service.handleIncomingPeerRetrieveResponseInfra(
              frame, senderDeviceId, from, port, snapshot);
          break;
        case proto.MessageTypeV3.MTV3_FRAGMENT_STORE:
          service.handleIncomingFragmentStoreInfra(
              frame, senderDeviceId, from, port, snapshot);
          break;
        case proto.MessageTypeV3.MTV3_PEER_STORE:
          service.handleIncomingPeerStoreInfra(
              frame, senderDeviceId, from, port, snapshot);
          break;
        default:
          // Other infra types are not relevant during background fetch
          break;
      }
    } catch (_) {
      // Non-fatal: skip unhandled frame types
    }
  }

  /// Generate a short preview string from a message.
  static String _messagePreview(dynamic msg) {
    try {
      final text = msg.text as String?;
      if (text != null && text.isNotEmpty) {
        return text.length > 100 ? '${text.substring(0, 100)}...' : text;
      }
      // Fallback for media messages
      if (msg.mediaPath != null) return '[Media]';
      if (msg.isVoiceMessage == true) return '[Sprachnachricht]';
      return '[Nachricht]';
    } catch (_) {
      return '[Nachricht]';
    }
  }
}

/// Internal helper to collect fetched message info for notification posting.
class _FetchedMessage {
  final String senderName;
  final String preview;

  _FetchedMessage({required this.senderName, required this.preview});
}

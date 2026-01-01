import 'dart:async';
import 'dart:io';
import 'package:cleona/core/crypto/network_secret.dart';
import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/crypto/oqs_ffi.dart';
import 'package:cleona/core/node/cleona_node.dart';
import 'package:cleona/core/node/identity_context.dart';
import 'package:cleona/core/service/cleona_service.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/platform/app_paths.dart';

/// Headless entry point for bootstrap nodes and VM testing.
///
/// Usage:
///   cleona-headless --profile `dir` --port `port` [--name `name`]
///                   [--bootstrap-peer `ip:port`]
///                   [--send-cr <nodeIdHex>]      # send contact request after startup
///                   [--send-msg <nodeIdHex:text>] # send message after CR accepted
void main(List<String> args) {
  runZonedGuarded(() async {
    final config = _parseArgs(args);
    final log = CLogger.get('headless', profileDir: config.profileDir);

    log.info('Starting Cleona headless node...');
    log.info('Profile: ${config.profileDir}');
    log.info('Port: ${config.port}');
    log.info('Name: ${config.name}');

    // Init crypto
    SodiumFFI();
    OqsFFI().init();

    // Create identity context
    final identity = IdentityContext(
      profileDir: config.profileDir,
      displayName: config.name,
    );
    await identity.initKeys();

    // Create shared node
    final node = CleonaNode(
      profileDir: config.profileDir,
      port: config.port,
    );
    node.primaryIdentity = identity;
    node.registerIdentity(identity);

    // Create service
    final service = CleonaService(
      identity: identity,
      node: node,
      displayName: config.name,
    );

    service.onNewMessage = (convId, msg) {
      log.info('MSG [${msg.senderNodeIdHex.substring(0, 8)}]: ${msg.text}');
    };

    service.onContactRequestReceived = (nodeId, name) {
      log.info('Contact request from $name ($nodeId)');
      // Auto-accept in headless mode
      service.acceptContactRequest(nodeId);
      log.info('Auto-accepted contact $name');
    };

    service.onContactAccepted = (nodeId) {
      log.info('Contact accepted: $nodeId');
      // If we have a pending --send-msg for this contact, send it now
      if (config.sendMsg != null && config.sendMsg!.startsWith(nodeId)) {
        final text = config.sendMsg!.substring(nodeId.length + 1);
        Timer(const Duration(seconds: 2), () async {
          final result = await service.sendTextMessage(nodeId, text);
          log.info('Sent test message to ${nodeId.substring(0, 8)}: ${result != null ? "OK" : "FAILED"}');
        });
      }
    };

    // Route messages to service
    node.onMessageForIdentity = (envelope, from, port, identityCtx) {
      service.handleMessage(envelope, from, port);
    };

    // Start node (blocking bootstrap)
    await node.start(bootstrapPeers: config.bootstrapPeers);

    // Start service (contacts, conversations, mailbox)
    await service.startService();

    log.info('Node started. User-ID: ${identity.userIdHex.substring(0, 16)}... '
        'Device: ${identity.deviceNodeIdHex.substring(0, 16)}...');
    log.info('Peers: ${service.peerCount}');

    // Write PID file
    final pidFile = File('${config.profileDir}/cleona.pid');
    pidFile.writeAsStringSync('$pid');

    // Network change detection via IP polling
    _startNetworkChangeHandler(node, log);

    // Periodic status logging
    Timer.periodic(const Duration(seconds: 60), (_) {
      log.info('Status: peers=${service.peerCount}, fragments=${service.fragmentCount}, conversations=${service.conversations.length}');
    });

    // Auto-send contact request after delay (wait for peer discovery)
    if (config.sendCr != null) {
      Timer(const Duration(seconds: 10), () async {
        log.info('Sending contact request to ${config.sendCr!.substring(0, 16)}...');
        final sent = await service.sendContactRequest(config.sendCr!);
        log.info('Contact request ${sent ? "sent" : "FAILED"}');
      });
    }

    // Handle SIGINT/SIGTERM
    ProcessSignal.sigint.watch().listen((_) async {
      log.info('SIGINT received, stopping...');
      _networkMonitor?.kill();
      await service.stop();
      await node.stop();
      if (pidFile.existsSync()) pidFile.deleteSync();
      exit(0);
    });
    ProcessSignal.sigterm.watch().listen((_) async {
      log.info('SIGTERM received, stopping...');
      _networkMonitor?.kill();
      await service.stop();
      await node.stop();
      if (pidFile.existsSync()) pidFile.deleteSync();
      exit(0);
    });

    // Stdin command loop for interactive use
    _startStdinHandler(service, log);

    log.info('Headless node running. Commands: /peers /contacts /send <id> <msg> /cr <id> /quit');
  }, (error, stack) {
    final log = CLogger.get('headless');
    log.error('Unhandled error: $error');
    log.error('Stack: $stack');
  });
}

/// Stdin command handler for interactive headless mode.
void _startStdinHandler(CleonaService service, CLogger log) {
  stdin.transform(const SystemEncoding().decoder).listen((input) async {
    final line = input.trim();
    if (line.isEmpty) return;

    if (line == '/peers') {
      final peers = service.peerSummaries;
      log.info('Peers (${peers.length}):');
      for (final p in peers) {
        log.info('  ${p.nodeIdHex.substring(0, 16)} ${p.address}:${p.port} (${p.lastSeen})');
      }
    } else if (line == '/contacts') {
      final accepted = service.acceptedContacts;
      final pending = service.pendingContacts;
      log.info('Contacts: ${accepted.length} accepted, ${pending.length} pending');
      for (final c in accepted) {
        log.info('  [accepted] ${c.displayName} (${c.nodeIdHex.substring(0, 16)})');
      }
      for (final c in pending) {
        log.info('  [pending] ${c.displayName} (${c.nodeIdHex.substring(0, 16)})');
      }
    } else if (line.startsWith('/cr ')) {
      final nodeId = line.substring(4).trim();
      if (nodeId.length == 64) {
        final sent = await service.sendContactRequest(nodeId);
        log.info('Contact request ${sent ? "sent" : "FAILED"} to ${nodeId.substring(0, 16)}');
      } else {
        log.warn('Invalid node ID (need 64 hex chars)');
      }
    } else if (line.startsWith('/send ')) {
      final parts = line.substring(6).trim();
      final spaceIdx = parts.indexOf(' ');
      if (spaceIdx > 0) {
        final nodeId = parts.substring(0, spaceIdx);
        final text = parts.substring(spaceIdx + 1);
        final result = await service.sendTextMessage(nodeId, text);
        log.info('Message ${result != null ? "sent" : "FAILED"} to ${nodeId.substring(0, 16)}');
      }
    } else if (line == '/id') {
      log.info('Node ID: ${service.nodeIdHex}');
    } else if (line == '/quit' || line == '/exit') {
      await service.stop();
      exit(0);
    } else {
      log.info('Unknown command: $line');
    }
  });
}

/// Network change handler for headless mode.
Process? _networkMonitor;

/// Event-driven network change detection via `ip monitor address`.
/// On change: onNetworkChanged() resets PortMapper → re-acquires public IP
/// via NAT-PMP/UPnP → event triggers broadcastAddressUpdate().
/// If NAT-PMP/UPnP fail, _queryPublicIpFallback fires once via ipify.
void _startNetworkChangeHandler(CleonaNode node, CLogger log) {
  // Event-driven: `ip monitor address` fires on every address add/delete
  () async {
    try {
      // Kill orphaned `ip monitor address` from prior crashes (kill -9, segfault)
      await Process.run('pkill', ['-f', 'ip monitor address']);
      final proc = await Process.start('ip', ['monitor', 'address']);
      _networkMonitor = proc;
      Timer? debounce;
      proc.stdout.transform(const SystemEncoding().decoder).listen((line) {
        debounce?.cancel();
        debounce = Timer(const Duration(seconds: 2), () async {
          log.info('Network change detected (ip monitor)');
          await node.onNetworkChanged();
          // onNetworkChanged starts PortMapper. If NAT-PMP/UPnP fail,
          // fall back to ipify after a delay.
          _queryPublicIpFallback(node, log, delay: const Duration(seconds: 10));
        });
      });
      proc.exitCode.then((code) {
        log.debug('ip monitor exited with $code');
        _networkMonitor = null;
      });
    } catch (e) {
      log.warn('ip monitor not available: $e');
    }
  }();

  // Initial public IP discovery: PortMapper runs at startup (CleonaNode._startBase).
  // If it fails (no NAT-PMP/UPnP on router), ipify fallback after 10s.
  _queryPublicIpFallback(node, log, delay: const Duration(seconds: 10));

  // Re-query public IP on any network change (mass route-down, ip monitor, etc.).
  // This catches DS-Lite/CGNAT IP reassignment where local IPs don't change.
  node.onNetworkChangeDetected = () {
    _queryPublicIpFallback(node, log, delay: const Duration(seconds: 3), force: true);
  };
}

/// ipify fallback — queries public IP from external service.
/// [force]: re-query even if a public IP is already known (detects IP change).
void _queryPublicIpFallback(CleonaNode node, CLogger log, {Duration delay = Duration.zero, bool force = false}) {
  Timer(delay, () async {
    // Skip if PortMapper already found the public IP (unless forced)
    if (!force && node.natTraversal.hasPublicIp) {
      log.info('ipify fallback: skipped (public IP already known)');
      return;
    }

    log.info('ipify${force ? " recheck" : " fallback"}: querying public IP...');
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(Uri.parse('https://api.ipify.org'));
      final response = await request.close().timeout(const Duration(seconds: 10));
      final ip = (await response.transform(const SystemEncoding().decoder).join()).trim();
      client.close(force: true);

      if (ip.isEmpty || !ip.contains('.')) {
        log.warn('ipify fallback: empty or invalid response: "$ip"');
        return;
      }

      // Double-check — PortMapper may have succeeded while ipify was in flight
      if (node.natTraversal.hasPublicIp) return;

      log.info('Public IP via ipify: $ip — starting port probe');
      node.natTraversal.setExternalIpOnly(ip);
      node.probePublicPort(ip);
      node.broadcastAddressUpdate();
    } catch (e) {
      log.warn('ipify fallback failed: $e');
    }

    // IPv6 public IP discovery (§27 — DS-Lite/CGNAT bypass)
    try {
      final client6 = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final req6 = await client6.getUrl(Uri.parse('https://api6.ipify.org'));
      final resp6 = await req6.close().timeout(const Duration(seconds: 10));
      final ipv6 = (await resp6.transform(const SystemEncoding().decoder).join()).trim();
      client6.close(force: true);
      if (ipv6.isNotEmpty && ipv6.contains(':')) {
        log.info('Public IPv6 via ipify: $ipv6');
        node.natTraversal.setPublicIpv6(ipv6);
        node.broadcastAddressUpdate();
      }
    } catch (e) {
      log.debug('ipify IPv6 query failed (expected if no IPv6): $e');
    }
  });
}


class _HeadlessConfig {
  final String profileDir;
  final int port;
  final String name;
  final List<String> bootstrapPeers;
  final String? sendCr;
  final String? sendMsg;

  _HeadlessConfig({
    required this.profileDir,
    required this.port,
    required this.name,
    this.bootstrapPeers = const [],
    this.sendCr,
    this.sendMsg,
  });
}

_HeadlessConfig _parseArgs(List<String> args) {
  String? profileDir;
  int? port;
  String name = 'Headless';
  final bootstrapPeers = <String>[];
  String? sendCr;
  String? sendMsg;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--profile':
        if (i + 1 < args.length) profileDir = args[++i];
        break;
      case '--port':
        if (i + 1 < args.length) port = int.tryParse(args[++i]);
        break;
      case '--name':
        if (i + 1 < args.length) name = args[++i];
        break;
      case '--bootstrap-peer':
        if (i + 1 < args.length) bootstrapPeers.add(args[++i]);
        break;
      case '--send-cr':
        if (i + 1 < args.length) sendCr = args[++i];
        break;
      case '--send-msg':
        if (i + 1 < args.length) sendMsg = args[++i];
        break;
    }
  }

  final home = AppPaths.home;
  profileDir ??= '$home/.cleona/$name';
  // Default bootstrap port based on network channel (Architecture 17.5):
  // Live = 8080, Beta = 8081
  port ??= NetworkSecret.channel.defaultBootstrapPort;

  return _HeadlessConfig(
    profileDir: profileDir,
    port: port,
    name: name,
    bootstrapPeers: bootstrapPeers,
    sendCr: sendCr,
    sendMsg: sendMsg,
  );
}

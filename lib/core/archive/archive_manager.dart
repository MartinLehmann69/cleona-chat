// Orchestrates the Media Auto-Archive system.
//
// Responsible for:
// - Periodic archive checks (based on config interval)
// - Network state verification (optional narrowings, share identity,
//   share reachability — §21.6)
// - Tier transitions (Original -> Thumbnail -> Mini -> MetadataOnly)
// - Storage budget enforcement (eviction when exceeded)
// - Security rule: Never delete without confirmed archival

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/archive/archive_config.dart';
import 'package:cleona/core/archive/archive_network.dart';
import 'package:cleona/core/archive/archive_transport.dart';
import 'package:cleona/core/archive/share_identity.dart';
import 'package:cleona/core/archive/archive_types.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/core/storage/message_store.dart';
import 'package:cleona/core/media/media_store.dart';

/// Callback for archive status changes.
typedef ArchiveStatusCallback = void Function(
    String messageId, ArchiveStatus status);

/// Supplies the conversations a scheduled archive run scans.
///
/// S392 — **this is the piece that was missing.** The periodic timer used
/// to call `runArchiveCheck()` with no conversations at all, so the scan
/// loop in [ArchiveManager.runArchiveCheck] was skipped on every single
/// tick and the whole archive chain (upload, delete, tier) only ever ran
/// when the UI sent `archive_trigger_check` by hand.
///
/// **The supplier owes two things, and the second one is easy to miss:**
///
///  1. the conversation map, and
///  2. a **fully loaded** history. A conversation carries only its most
///     recent message after start-up (§21.4.1, lazy loading from S366);
///     the archive run searches by **age**, so without
///     `ensureAllLoaded()` it walks a one-element window and finds
///     nothing — silently, because "no archivable media" looks exactly
///     like "nothing was loaded". `ipc_server.dart` calls
///     `ensureAllLoaded()` for the same reason before its own
///     `runArchiveCheck`; the guard `smoke_lazy_load_deckung` holds both
///     call sites to it.
///
/// A callback and not the map itself: the manager must not pin a snapshot
/// of every conversation for the lifetime of the daemon, and it must not
/// import the service (the service imports the manager).
typedef ArchiveConversationSource = Map<String, Conversation> Function();

/// Progress of a retrieval from the share.
///
/// The manager reports, it does not store: a retrieval can take minutes over
/// SMB, and the UI process is on the other
/// side of the IPC socket. Hence a callback per piece instead of a
/// return value at the end (§22.6 — service and UI are two processes on Linux,
/// Windows and macOS).
typedef ArchiveRetrievalProgress = void Function(
    String messageId, int bytesTransferred, int totalBytes);

/// Manages automatic media archival.
class ArchiveManager {
  /// The setting. Not `final` since S394: the run writes the share pin into
  /// it, and "only in this network" is changed while the manager runs.
  ArchiveConfig _config;
  ArchiveConfig get config => _config;

  final ArchiveTransport transport;
  final String profileDir;

  /// The encrypted store of the identity (§21.4).
  ///
  /// S366: until now the archive index lay as `archive_entries.json`
  /// NAKED in the profile. It is a directory of one's own media history
  /// — which attachment moved when to which machine on the network,
  /// together with conversation identifier, file name, MIME type and size. Whoever
  /// finds it has the media biography without opening a single file.
  ///
  /// May be `null` — then nothing is loaded and nothing written.
  /// That is the path for guards that only measure the tiering and
  /// eviction logic and need no store for it.
  final MessageStore? _store;

  /// The area in the table `state`.
  ///
  /// **[MessageStore.putEntry] and not `replaceArea`**: the index
  /// grows with EVERY offload and never gets smaller. A
  /// full-state writer would thus bring back exactly the pattern
  /// the table is built against — for a user with years of
  /// media, every archive run would rewrite the whole index.
  static const String kEntriesArea = 'archive_entries';

  Timer? _scheduler;
  bool _running = false;

  /// Is a run in progress right now? The latch against overlap — see
  /// [runArchiveCheck].
  bool _checkInFlight = false;

  /// Has the existing state been read? Carries the data-loss latch further
  /// below — see [_persistMessage].
  bool _loaded = false;

  late final CLogger _log =
      CLogger.get('ArchiveManager', profileDir: profileDir);

  /// Persisted archive entries, indexed by messageId.
  final Map<String, ArchiveEntry> _entries = {};

  /// Pin status per message.
  final Map<String, bool> _pinned = {};

  /// Current archive status per message.
  final Map<String, ArchiveStatus> _statusMap = {};

  /// Running retrievals, at most ONE per message.
  ///
  /// The value is the future of the running operation, not a `bool`:
  /// so the second request gets not just "already running" but
  /// the same result as the first, and nobody has to poll.
  final Map<String, Future<ArchiveRetrievalResult>> _retrievals = {};

  /// Callback on status changes.
  ArchiveStatusCallback? onStatusChanged;

  // `store:` stays the name at the call site. Dart maps the private
  // field name to the public one, therefore `this._store` is
  // possible here without touching a single call site — verified in S366 against a
  // throwaway package. Until then there was a
  // `// ignore: prefer_initializing_formals` here with the rationale that a
  // `this._store` turns it into a private name in the signature; that
  // is not so. Moreover the `ignore` sat one line above the finding
  // (the analyzer reports the initializer list, not the head) and therefore
  // did not take effect anyway.
  ArchiveManager({
    required this._config,
    required this.transport,
    required this.profileDir,
    // ignore: library_private_types_in_public_api
    this._store,
  });

  // -- Lifecycle -----------------------------------------------------------

  /// Starts the periodic archive scheduler.
  ///
  /// S392 — **[conversationSource] is required on purpose.** The previous
  /// signature took no arguments and the timer body was
  /// `(_) => runArchiveCheck()`, i.e. without `conversations:`. The scan
  /// loop hangs off that one parameter, so every tick skipped it and only
  /// ran `_enforceStorageBudget`: nothing was ever uploaded, no tier ever
  /// advanced, no original ever left the device on its own. The whole
  /// chain was built and dead.
  ///
  /// Required rather than a settable field, because a field that may be
  /// `null` reproduces exactly that failure — it compiles, it starts, and
  /// it silently does nothing. This way a caller that starts the
  /// scheduler without saying where the conversations come from does not
  /// build.
  Future<void> startScheduler({
    required ArchiveConversationSource conversationSource,
  }) async {
    if (_running) return;
    _running = true;
    await _loadEntries();

    _scheduler = Timer.periodic(
      Duration(minutes: config.archiveCheckIntervalMinutes),
      (_) => _runScheduled(conversationSource),
    );
  }

  /// A run started by the scheduler.
  ///
  /// The scheduler survives EVERY failure. An exception out of the source
  /// (the service is shutting down, the store does not answer) or out of
  /// the run itself must not tear down the hour after it as well — it would
  /// come out of a `Timer` callback, hence unattended out of the zone, and
  /// nobody would catch it.
  Future<void> _runScheduled(ArchiveConversationSource source) async {
    final Map<String, Conversation> convs;
    try {
      convs = source();
    } catch (e) {
      _log.warn('Scheduled archive run skipped: the conversation source '
          'threw ($e). The scheduler keeps running.');
      return;
    }
    try {
      final r = await runArchiveCheck(conversations: convs);
      _log.info('Scheduled archive run over ${convs.length} '
          'conversation(s): $r');
    } catch (e) {
      _log.warn('Scheduled archive run failed: $e');
    }
  }

  /// Stops the scheduler.
  Future<void> stopScheduler() async {
    _running = false;
    _scheduler?.cancel();
    _scheduler = null;
  }

  /// Performs a single archive check.
  ///
  /// 1. Checks network conditions (SSID, share reachability)
  /// 2. Scans conversations for archivable media
  /// 3. Archives and performs tier transitions
  /// 4. Evicts when budget is exceeded
  /// **At most ONE run at a time.**
  ///
  /// S392 — this only became sharp with the scheduler. As long as only the
  /// surface sent `archive_trigger_check`, there was a human between two
  /// runs. The tick is set to 60 minutes, but a first run on an existing
  /// profile uploads every attachment older than the first deadline onto
  /// the share and can take longer than an hour. Without a latch the second
  /// tick would then run into the same set:
  ///
  ///   * `_archiveMessage` would upload the same file a second time, and
  ///   * two `_checkTierTransition` for the same message would both come
  ///     through [_shareHoldsFile]; the second would call
  ///     `deleteEitherWay` on an already deleted file, get `false` back
  ///     and write a warning about a file that had "resisted deletion".
  ///
  /// The skipped run is not an error and is reported as such
  /// ([ArchiveCheckResult.skippedReason]) — the same path on which
  /// "network not ready" already travels upwards.
  Future<ArchiveCheckResult> runArchiveCheck({
    String? currentSSID,
    Map<String, Conversation>? conversations,
  }) async {
    if (_checkInFlight) {
      return ArchiveCheckResult()
        ..skippedReason = 'another archive check is still running';
    }
    _checkInFlight = true;
    try {
      return await _runCheck(
          currentSSID: currentSSID, conversations: conversations);
    } finally {
      _checkInFlight = false;
    }
  }

  Future<ArchiveCheckResult> _runCheck({
    String? currentSSID,
    Map<String, Conversation>? conversations,
  }) async {
    final result = ArchiveCheckResult();

    // §21.6, in this order: the optional narrowings first (they cost no
    // packet), then the share's identity, then reachability. Nothing below
    // this block writes to or deletes from the share unless all three hold.
    final readable = ssidReadable;
    final ssid = readable ? (currentSSID ?? await getCurrentSSID()) : null;
    final net =
        config.allowedNetworks.isEmpty ? null : await currentNetwork();
    final narrowed = config.narrowingAllows(
        current: net, currentSSID: ssid, ssidReadable: readable);
    ShareIdentityState? identity;
    var shareReachable = false;
    if (narrowed) {
      identity = await establishShareIdentity();
      if (shareIdentityAllowsAccess(identity)) {
        shareReachable = await checkShareReachability();
      }
    }
    final ready = config.isArchiveReady(
      narrowingAllows: narrowed,
      identity: identity,
      shareReachable: shareReachable,
    );

    if (!ready) {
      result.skippedReason = !narrowed
          ? 'Outside the configured network (SSID: $ssid, '
              'subnets: ${net?.subnets}, gateway: ${net?.gateway})'
          : identity == ShareIdentityState.mismatch
              ? 'Share identity mismatch — nothing written, nothing deleted '
                  '($_identityDetail)'
              : 'Share not ready (identity: ${identity?.name}, '
                  'reachable: $shareReachable)';
      return result;
    }

    // Scan conversations
    if (conversations != null) {
      for (final conv in conversations.values) {
        if (!ArchiveConfig.isConversationEligible(conv)) continue;

        for (final msg in conv.messages) {
          if (!msg.isMedia) continue;
          if (!ArchiveConfig.isMediaArchivable(msg.mimeType)) continue;

          final age = DateTime.now().difference(msg.timestamp);
          if (!config.shouldArchive(age, pinned: isPinned(msg.id))) continue;

          // Already archived?
          if (_entries.containsKey(msg.id)) {
            // Check tier transition
            await _checkTierTransition(msg.id, age, filePath: msg.filePath);
            result.tierChecked++;
            continue;
          }

          // Archive
          final success = await _archiveMessage(msg, conv);
          if (success) {
            result.archived++;
          } else {
            result.failed++;
          }
        }
      }
    }

    // Budget-Enforcement
    final evicted = await _enforceStorageBudget();
    result.evicted = evicted;

    // No more full-state writing at the end of the run: each of the four
    // places of change (`_archiveMessage`, `_checkTierTransition`,
    // `_enforceStorageBudget`, `setPin`) writes its own row
    // as soon as it changes it. An abort in the middle of the run thus costs
    // at most the offload currently in progress instead of all of them.
    return result;
  }

  // -- Network detection ---------------------------------------------------

  /// Does this platform read the SSID without a location permission
  /// (§21.6: Linux, Windows)? Where not, the SSID list is not applied.
  bool get ssidReadable => ssidReadableHere;

  /// Current Wi-Fi SSID — Linux (nmcli/iwgetid) and Windows (netsh) only.
  Future<String?> getCurrentSSID() => readCurrentSsid();

  /// Subnets and gateway as this device sees them now.
  Future<CurrentNetwork> currentNetwork() => readCurrentNetwork();

  // -- Share identity (§21.6 security rules, S394) -------------------------

  ShareIdentityState? _identityState;
  String _identityDetail = '';

  /// Outcome of the last identity check; `null` before the first.
  ShareIdentityState? get shareIdentityState => _identityState;

  /// Why — for the log and the surface, never a secret.
  String get shareIdentityDetail => _identityDetail;

  /// Asks the share who it is and decides: unknown is pinned, a changed one
  /// refused (§21.6). Binds the transport only on confirmed/newly pinned —
  /// every transport operation refuses without that binding.
  Future<ShareIdentityState> establishShareIdentity() async {
    final pinned = config.activeShareIdentity;
    ShareIdentityProbe probe;
    try {
      probe = await transport.probeIdentity(pinned: pinned);
    } catch (e) {
      probe = ShareIdentityProbe.unavailable('$e');
    }
    final state = decideShareIdentity(pinned: pinned, probe: probe);
    _identityState = state;
    _identityDetail = probe.detail;
    switch (state) {
      case ShareIdentityState.confirmed:
        transport.bindIdentity(pinned);
      case ShareIdentityState.newlyPinned:
        final pin = probe.presented!;
        _updateConfig((c) => c.withShareIdentity(
            ShareIdentityPin(target: c.shareTarget, value: pin)));
        transport.bindIdentity(pin);
        _log.info('Archive share pinned on first use: '
            '${shortShareIdentity(pin)} (${config.shareTarget})');
      case ShareIdentityState.mismatch:
        transport.bindIdentity(null);
        _log.warn('Archive share identity MISMATCH for ${config.shareTarget}: '
            '${probe.detail} presented=${probe.presented} pinned=$pinned. '
            'Nothing is written or deleted until the user rebinds.');
      case ShareIdentityState.unavailable:
        transport.bindIdentity(null);
    }
    return state;
  }

  /// "Rebind": forgets the pin. The next run pins whatever the configured
  /// share presents then. Deletes nothing on the share.
  void rebindShareIdentity() {
    transport.bindIdentity(null);
    _identityState = null;
    _identityDetail = '';
    _updateConfig((c) => c.withShareIdentity(null));
    forgetSftpHostKey(profileDir);
    _log.info('Archive share identity released by the user; the next run '
        'pins anew.');
  }

  /// Rebind for SFTP means deleting the identity's host-key file.
  static void forgetSftpHostKey(String profileDir) {
    try {
      final f = File(archiveKnownHostsPath(profileDir));
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  /// Replaces "only in this network".
  void setAllowedNetworks(List<ArchiveNetwork> networks) =>
      _updateConfig((c) => c.withAllowedNetworks(networks));

  /// Changes the setting in memory and in the store — read-modify-write on
  /// the STORED record, so that a field the surface changed meanwhile is
  /// not overwritten with this manager's older copy.
  void _updateConfig(ArchiveConfig Function(ArchiveConfig) change) {
    _config = change(_config);
    final s = _store;
    if (s == null) return;
    try {
      final stored = ArchiveConfig.readFrom(s);
      (stored == null ? _config : change(stored)).writeTo(s);
    } catch (e) {
      _log.warn('Archive setting could not be written: $e');
    }
  }

  /// Check share reachability.
  Future<bool> checkShareReachability() async {
    try {
      return await transport.testConnectivity(
        timeout: Duration(seconds: config.shareReachabilityTimeoutSec),
      );
    } catch (_) {
      return false;
    }
  }

  // -- Archival ------------------------------------------------------------

  /// Archive a single media item.
  Future<bool> _archiveMessage(UiMessage msg, Conversation conv) async {
    if (msg.filePath == null) return false;
    // S362: the attachment lies encrypted in the store. The ARCHIVE
    // itself stays plaintext — it writes to the NAS/share chosen by the user,
    // an explicit export (S362 report section 5).
    // Only the READ path from the profile must go through decryption.
    if (!MediaStore.instance.existsEitherWay(msg.filePath!)) return false;

    _updateStatus(msg.id, ArchiveStatus.uploading);

    try {
      final data = MediaStore.instance.readAll(msg.filePath!);
      if (data == null) {
        _updateStatus(msg.id, ArchiveStatus.failed);
        return false;
      }
      final contentHashHex = _computeSimpleHash(data);
      final archiveFilename = generateArchiveFilename(contentHashHex, msg.mimeType);

      // Remote path: <Identity>/<Chat>/<YYYY-MM>/<filename>
      final monthDir = _monthDir(msg.timestamp);
      final chatName = _sanitizeName(conv.displayName);
      final remoteDir = '$chatName/$monthDir';
      final remotePath = '$remoteDir/$archiveFilename';

      // Create directory and upload.
      await transport.createDirectory(remoteDir);
      await transport.uploadFile(data, remotePath, onProgress: (sent, total) {
        // Progress could be forwarded to UI.
      });

      // Verify: file exists on share.
      final exists = await transport.fileExists(remotePath);
      if (!exists) {
        _updateStatus(msg.id, ArchiveStatus.failed);
        return false;
      }

      // Generate share URL.
      //
      // S392 — **the file name was in here twice**, and two
      // independent build tasks (B2 and B4) found the same error on the
      // same day. `remotePath`, which already carries the
      // file name, was passed as the `path` argument; `generateShareUrl`
      // appends the `filename` argument ONCE MORE:
      //
      //     smb:///Chat/2026-09/228d5a18db560325.jpg/228d5a18db560325.jpg
      //
      // while the file lies under `Chat/2026-09/228d5a18db560325.jpg`.
      //
      // Why it stayed invisible so long: `fileExists` checks
      // `remotePath`, not the identifier — so the offload was green.
      // Until today NOBODY READ the identifier. Both new consumers
      // stumbled over it, and with different consequences:
      //
      //   B2  `_shareHoldsFile` computed back via `_shareUrlToRemotePath`,
      //       the share reported "not there", and the
      //       deletion was — correctly — skipped.
      //   B4  `retrieveArchivedMedia` asked the share for a path
      //       that was NEVER written there; every retrieval would have
      //       failed, and its `catch (_) { return null; }` would have
      //       swallowed the reason.
      //
      // Hence the DIRECTORY, not the path; the name is set by
      // `generateShareUrl` itself. After that
      // `_shareUrlToRemotePath(shareUrl) == remotePath` holds, and exactly that is
      // the condition under which a deletion can be justified at all.
      //
      // The stock from old runs carries the wrong address on;
      // it thus falls into the safe branch — no deletion, warning
      // in the log.
      final shareUrl = ArchiveConfig.generateShareUrl(
        config.defaultProtocol,
        '', // Host is set on connect
        remoteDir,
        archiveFilename,
      );

      // Create entry.
      final entry = ArchiveEntry(
        messageId: msg.id,
        conversationId: msg.conversationId,
        shareUrl: shareUrl,
        archivedAt: DateTime.now(),
        tier: isPinned(msg.id)
            ? config.archivedTierForPinned()
            : config.tierForAge(DateTime.now().difference(msg.timestamp)),
        contentHash: contentHashHex,
        pinned: isPinned(msg.id),
        fileSizeBytes: data.length,
        mimeType: msg.mimeType,
        originalFilename: msg.filename,
      );

      _entries[msg.id] = entry;
      _persistMessage(msg.id);
      _updateStatus(msg.id, ArchiveStatus.confirmed);
      return true;
    } catch (e) {
      _updateStatus(msg.id, ArchiveStatus.failed);
      return false;
    }
  }

  /// Check and perform tier transition.
  ///
  /// S392/B2 — **here the original leaves the device.** §21.6: "after a
  /// configurable deadline, the originals disappear from the device —
  /// **never without confirmed archiving**". Until S392 this method
  /// only wrote a number into the index record; the file stayed, and the
  /// space saving promised in 34 languages never materialised.
  ///
  /// The order is NOT arbitrary: first check, then delete, then
  /// advance the tier. Whoever wrote the tier first would, on
  /// a failure, have an index record claiming "lies only on the
  /// share" while the file is still there — and the next
  /// run would never come here again because of `targetTier.index <= entry.tier.index`.
  Future<void> _checkTierTransition(String messageId, Duration age,
      {String? filePath}) async {
    final entry = _entries[messageId];
    if (entry == null) return;

    // §21.6: a retrieved original counts as new — its age runs from the
    // retrieval (S392-15). Without this the run after a retrieval computed
    // the tier from the message age again and deleted the file within the
    // hour.
    final targetTier = config.tierForAge(
        entry.tierAge(age, DateTime.now()), pinned: entry.pinned);
    if (targetTier.index <= entry.tier.index) return; // No downgrade needed

    // Security rule: only downgrade if archived
    if (!config.canDeleteLocal(getStatus(messageId))) return;

    // §21.6: "pinned media is archived but never deleted from the device".
    //
    // `tierForAge(pinned: true)` already returns `original`, so the line
    // above would catch a pinned entry anyway. It stays
    // nevertheless: a DELETION must not rely on
    // ANOTHER function returning a certain number. Whoever changes `tierForAge`
    // one day would otherwise unnoticed also change what disappears from the device
    // here.
    if (entry.pinned) return;

    // The original only goes away if the share still holds it NOW.
    // If that fails, both stay: file and tier.
    if (filePath != null && MediaStore.instance.existsEitherWay(filePath)) {
      final released = await _shareHoldsFile(entry, filePath);
      if (!released) return; // begruendet in `_shareHoldsFile`

      if (!MediaStore.instance.deleteEitherWay(filePath)) {
        _log.warn('Tier transition for $messageId held back: the local '
            'original resisted deletion ($filePath). The share copy is '
            'confirmed, but advancing the tier now would show a placeholder '
            'for a file that is still on the device.');
        return;
      }
      _log.info('Local original removed after confirmed archiving: '
          '$messageId -> ${entry.tier.name}>${targetTier.name} '
          '(${entry.fileSizeBytes} B freed)');
    }

    // Create new entry with updated tier
    _entries[messageId] = ArchiveEntry(
      messageId: entry.messageId,
      conversationId: entry.conversationId,
      shareUrl: entry.shareUrl,
      archivedAt: entry.archivedAt,
      tier: targetTier,
      contentHash: entry.contentHash,
      pinned: entry.pinned,
      fileSizeBytes: entry.fileSizeBytes,
      mimeType: entry.mimeType,
      originalFilename: entry.originalFilename,
      retrievedAt: entry.retrievedAt,
    );
    _persistMessage(messageId);
  }

  /// Does the share hold the file RIGHT NOW and with EXACTLY THIS content?
  ///
  /// S392/B2 — the only evidence that justifies a deletion. What
  /// explicitly does NOT count as evidence here:
  ///
  /// * **The tier in the index record.** It says that an upload happened
  ///   at some point. Whether the file still lies on the NAS it does
  ///   not say — the user tidies up their NAS, a disk fails, a
  ///   cleanup script goes through.
  /// * **[ArchiveStatus.confirmed].** The same objection: the status comes
  ///   from the run that uploaded, and survives restarts
  ///   (`_loadEntries` sets it for every loaded record).
  /// * **[checkShareReachability].** It is asked once per run, before
  ///   the loop. Between it and this line lie arbitrarily many
  ///   files and arbitrarily much time; a Wi-Fi drop midway would
  ///   otherwise delete every following file unchecked.
  ///
  /// Two questions, both must say yes:
  ///
  /// 1. **Do the local bytes still hash to `entry.contentHash`?** The
  ///    file name on the share IS this hash
  ///    (`generateArchiveFilename`). If it no longer matches, a
  ///    DIFFERENT version lies there, and a `fileExists` on the old path would prove
  ///    nothing about the file that would be deleted here.
  /// 2. **Does the share report the file under exactly this path?** Freshly
  ///    asked, not remembered.
  ///
  /// If anything fails — exception, timeout, `null`, `false`
  /// —, the answer is `false`. Fail closed: when in doubt the file stays.
  ///
  /// **What this evidence does not provide** (open, tracked in the report): the
  /// interface [ArchiveTransport] knows no size query. An
  /// aborted upload that leaves behind a too-short file with the right name
  /// would pass here. `_archiveMessage` checks directly
  /// after the upload, therefore the window is narrow, but it is there.
  Future<bool> _shareHoldsFile(ArchiveEntry entry, String filePath) async {
    // (1) Are they still the same bytes?
    final Uint8List? local;
    try {
      local = MediaStore.instance.readAll(filePath);
    } catch (e) {
      _log.warn('Refusing to delete ${entry.messageId}: local original '
          'could not be read for verification: $e');
      return false;
    }
    if (local == null) {
      _log.warn('Refusing to delete ${entry.messageId}: local original '
          'unreadable (no key registered, or file vanished mid-check).');
      return false;
    }
    final hash = _computeSimpleHash(local);
    if (hash != entry.contentHash) {
      _log.warn('Refusing to delete ${entry.messageId}: the local original '
          'hashes to $hash, the archive entry was written for '
          '${entry.contentHash}. The share holds a different version of '
          'this attachment.');
      return false;
    }

    // (2) Does it lie there — asked now, not remembered?
    final String remotePath;
    try {
      remotePath = _shareUrlToRemotePath(entry.shareUrl);
    } catch (e) {
      _log.warn('Refusing to delete ${entry.messageId}: share URL '
          '"${entry.shareUrl}" is not a usable path: $e');
      return false;
    }
    try {
      final there = await transport.fileExists(remotePath);
      if (!there) {
        _log.warn('Refusing to delete ${entry.messageId}: the share does '
            'NOT hold $remotePath any more. Original stays on the device.');
        return false;
      }
    } catch (e) {
      _log.warn('Refusing to delete ${entry.messageId}: the share did not '
          'answer for $remotePath ($e). Original stays on the device.');
      return false;
    }
    return true;
  }

  /// Budget enforcement: evict oldest unpinned media.
  Future<int> _enforceStorageBudget() async {
    final usedMB = await getUsedStorageMB();
    if (!config.needsEviction(usedMB: usedMB)) return 0;

    // Sort by archivedAt (oldest first), only unpinned.
    final evictable = _entries.values
        .where((e) => config.isEvictableForBudget(pinned: e.pinned))
        .where((e) => config.evictionAction(e.tier) == EvictionAction.downgrade)
        .toList()
      ..sort((a, b) => a.archivedAt.compareTo(b.archivedAt));

    var evicted = 0;
    for (final entry in evictable) {
      if (!config.needsEviction(usedMB: await getUsedStorageMB())) break;

      // Downgrade to next tier.
      final nextTier = ArchiveTier.values[entry.tier.index + 1];
      _entries[entry.messageId] = ArchiveEntry(
        messageId: entry.messageId,
        conversationId: entry.conversationId,
        shareUrl: entry.shareUrl,
        archivedAt: entry.archivedAt,
        tier: nextTier,
        contentHash: entry.contentHash,
        pinned: entry.pinned,
        fileSizeBytes: entry.fileSizeBytes,
        mimeType: entry.mimeType,
        originalFilename: entry.originalFilename,
        retrievedAt: entry.retrievedAt,
      );
      _persistMessage(entry.messageId);
      evicted++;
    }

    return evicted;
  }

  // -- Projection for the UI process ----------------------------

  /// Stamps the archive state (§21.6) onto the messages that are about to go to the
  /// UI process.
  ///
  /// S392/B3. **Why a stamp and not a stored field.** The
  /// leading stock is [_entries]. If the state were written along into the
  /// message store, the same fact would exist in two
  /// places with two agings — and the UI would show something different depending on the path
  /// (snapshot or reloaded history).
  /// `messageExtraForStore` therefore strips the four fields out
  /// again; here they are set immediately before serialisation.
  ///
  /// Idempotent and resetting: a message without an entry gets the
  /// fields explicitly back to `null`. An object once stamped
  /// whose entry disappears would otherwise keep a tier that
  /// no longer exists.
  void applyArchiveView(Iterable<UiMessage> msgs) {
    for (final m in msgs) {
      final e = _entries[m.id];
      if (e == null) {
        if (m.archiveTier == null) continue;
        m.archiveTier = null;
        m.archiveShareUrl = null;
        m.archivedAt = null;
        m.archiveMiniBase64 = null;
        continue;
      }
      m.archiveTier = e.tier.name;
      m.archiveShareUrl = e.shareUrl;
      m.archivedAt = e.archivedAt;
      // `archiveMiniBase64` stays UNTOUCHED. The mini bytes are produced by
      // S392/B1 (`archive_thumbnail.dart`) and stored in the index record;
      // as long as [ArchiveEntry] does not carry them, there is nothing to
      // stamp here — and writing `null` where B1 later has something
      // would be the line one then overlooks.
    }
  }

  // -- Pin management ------------------------------------------------------

  /// Pin/unpin a media item.
  ///
  /// S366: now writes ITSELF. Before, the pin only lay in
  /// memory until at some point an archive run called `_saveEntries` — whoever
  /// pinned and closed the app before the next run happened (interval
  /// 60 minutes by default) did not find the pin again, and the
  /// pinned medium would have been downgraded at the next eviction.
  void setPin(String messageId, bool pinned) {
    _pinned[messageId] = pinned;
    final entry = _entries[messageId];
    if (entry != null) {
      _entries[messageId] = ArchiveEntry(
        messageId: entry.messageId,
        conversationId: entry.conversationId,
        shareUrl: entry.shareUrl,
        archivedAt: entry.archivedAt,
        tier: pinned ? ArchiveTier.original : entry.tier,
        contentHash: entry.contentHash,
        pinned: pinned,
        fileSizeBytes: entry.fileSizeBytes,
        mimeType: entry.mimeType,
        originalFilename: entry.originalFilename,
        retrievedAt: entry.retrievedAt,
      );
    }
    _persistMessage(messageId);
  }

  /// Whether a media item is pinned.
  bool isPinned(String messageId) => _pinned[messageId] ?? false;

  // -- Status tracking -----------------------------------------------------

  /// Query the current archive status of a message.
  ArchiveStatus getStatus(String messageId) =>
      _statusMap[messageId] ?? ArchiveStatus.pending;

  void _updateStatus(String messageId, ArchiveStatus status) {
    _statusMap[messageId] = status;
    onStatusChanged?.call(messageId, status);
  }

  // -- Storage tracking ----------------------------------------------------

  /// Used media storage in MB (local media files).
  Future<int> getUsedStorageMB() async {
    final mediaDir = Directory('$profileDir/media');
    if (!mediaDir.existsSync()) return 0;

    var totalBytes = 0;
    await for (final entity in mediaDir.list()) {
      if (entity is File) {
        totalBytes += await entity.length();
      }
    }
    return totalBytes ~/ (1024 * 1024);
  }

  /// Return all archive entries.
  List<ArchiveEntry> get entries => _entries.values.toList();

  /// Pending archivals.
  List<ArchiveEntry> get pendingEntries =>
      _entries.values.where((e) => getStatus(e.messageId) == ArchiveStatus.pending).toList();

  /// Filter entries (delegates to archive_types.dart).
  List<ArchiveEntry> queryEntries({
    DateTime? from,
    DateTime? to,
    String? conversationId,
    int? maxItems,
  }) {
    return filterArchiveEntries(
      _entries.values.toList(),
      from: from,
      to: to,
      conversationId: conversationId,
      maxItems: maxItems ?? config.batchRetrievalMaxItems,
    );
  }

  // -- Batch-Retrieval ----------------------------------------------------

  /// Fetches the bytes of an offloaded attachment FROM THE SHARE.
  ///
  /// §21.6, touch point 3: "archive placeholders fetch from the
  /// **share**, never from the network." The only way out is
  /// [transport] — SMB/SFTP/FTPS/HTTP to the NAS. There is no path here to the
  /// delivery layer and none to `sendToUser()`; the archive works on
  /// finished local files and with home network infrastructure.
  ///
  /// `null` means EXACTLY ONE thing: there is no archive entry for this message.
  /// Every other failure THROWS.
  ///
  /// **The swallowing is gone** (S392, open point 5 from
  /// `S392-BAU-PLATZHALTER.md` §6). Here stood
  /// `catch (_) { return null; }` — with it "no entry",
  /// "share not reachable", "file deleted there" and
  /// "wrong password" looked identical to the caller, and the user
  /// would never have learned why their picture does not come back.
  /// `docs/ARCHIVE.md:38-39` requires exactly this information.
  Future<Uint8List?> retrieveArchivedMedia(
    String messageId, {
    ProgressCallback? onProgress,
  }) async {
    final entry = _entries[messageId];
    if (entry == null) return null;

    // §21.6: no login with the archive credentials at a share that is not
    // the pinned one — a retrieval asks first, like a run.
    final identity = await establishShareIdentity();
    if (!shareIdentityAllowsAccess(identity)) {
      throw ArchiveTransportException('share identity ${identity.name}'
          '${_identityDetail.isEmpty ? '' : ' ($_identityDetail)'}');
    }

    // Convert share URL to remote path.
    final remotePath = _shareUrlToRemotePath(entry.shareUrl);
    return await transport.downloadFile(remotePath, onProgress: onProgress);
  }

  /// Is a retrieval currently running for [messageId]?
  bool isRetrieving(String messageId) => _retrievals.containsKey(messageId);

  /// Number of retrievals currently running.
  int get activeRetrievals => _retrievals.length;

  /// Fetches the attachment back from the share and places it again under
  /// [targetPath] in the [MediaStore]; if that fully succeeds, the
  /// tier falls back to [ArchiveTier.original].
  ///
  /// ── ONE FETCH PER MESSAGE ──────────────────────────────────────
  ///
  /// Tapping the same message twice must not load twice. The
  /// second request gets back the **same** future as the first
  /// (`_retrievals`), not a second trip. That is not only a question
  /// of network traffic to the NAS: two runs would write simultaneously to
  /// the same path, and the loser of the race would lay its bytes over
  /// an already finished file.
  ///
  /// ── NO HALF STATE ──────────────────────────────────────────────
  ///
  /// The order is binding, and every step is a latch:
  ///
  ///   1. download — if the share fails, NOTHING is written
  ///      and the tier unchanged;
  ///   2. length against `fileSizeBytes` and content stamp against
  ///      `contentHash` — a truncated download does not get through;
  ///   3. write; if that throws (full disk, no key registered),
  ///      the started remainder is cleaned up
  ///      (`MediaStore.delete` deletes `.cmenc` AND `.cmenc.tmp`);
  ///   4. read back — `plainLength` opens the AEAD frame, that is the
  ///      evidence "complete AND readable"; if it fails, the file just
  ///      written is removed again;
  ///   5. **only now** the tier. It is the last step because it is the
  ///      statement "the file is back". If it came first, after a failure
  ///      the conversation would point to a file that does not
  ///      exist — the more expensive error, because it is silent.
  ///
  /// A cancellation by the user (conversation closed, UI
  /// exited) does NOT end the run: it runs to completion in the service, the
  /// progress reports go nowhere, and the file then lies there
  /// complete. That is intentional — the bytes are paid for anyway, and
  /// an abort midway would be exactly the half state that the
  /// order above prevents.
  Future<ArchiveRetrievalResult> retrieveToMediaStore(
    String messageId,
    String targetPath, {
    ArchiveRetrievalProgress? onProgress,
  }) {
    final running = _retrievals[messageId];
    if (running != null) return running;

    late final Future<ArchiveRetrievalResult> run;
    run = _retrieveOnce(messageId, targetPath, onProgress).whenComplete(() {
      // Only remove the OWN entry. If this were a bare
      // `remove`, a late-returning old run would delete the
      // placeholder of a new one started long ago.
      if (identical(_retrievals[messageId], run)) {
        _retrievals.remove(messageId);
      }
    });
    _retrievals[messageId] = run;
    return run;
  }

  Future<ArchiveRetrievalResult> _retrieveOnce(
    String messageId,
    String targetPath,
    ArchiveRetrievalProgress? onProgress,
  ) async {
    final entry = _entries[messageId];
    if (entry == null) {
      return ArchiveRetrievalResult._(
        messageId: messageId,
        ok: false,
        tier: ArchiveTier.original,
        error: 'no archive entry for $messageId',
      );
    }
    if (targetPath.isEmpty) {
      return ArchiveRetrievalResult._(
        messageId: messageId,
        ok: false,
        tier: entry.tier,
        error: 'no local path for $messageId',
      );
    }

    // Already there and already on tier 1 — nothing to fetch. This catches the
    // second tap AFTER a finished run; the latch in
    // [retrieveToMediaStore] only catches the one during a running run.
    if (entry.tier == ArchiveTier.original &&
        MediaStore.instance.existsEitherWay(targetPath)) {
      return ArchiveRetrievalResult._(
        messageId: messageId,
        ok: true,
        tier: ArchiveTier.original,
        bytes: 0,
        alreadyLocal: true,
      );
    }

    Uint8List? data;
    try {
      data = await retrieveArchivedMedia(
        messageId,
        onProgress: onProgress == null
            ? null
            : (sent, total) => onProgress(messageId, sent, total),
      );
    } catch (e) {
      _log.warn('Archive retrieval failed for $messageId: $e');
      return ArchiveRetrievalResult._(
        messageId: messageId,
        ok: false,
        tier: entry.tier,
        error: 'share unreachable: $e',
      );
    }
    if (data == null) {
      return ArchiveRetrievalResult._(
        messageId: messageId,
        ok: false,
        tier: entry.tier,
        error: 'no archive entry for $messageId',
      );
    }

    // Completeness, before anything is written.
    if (entry.fileSizeBytes > 0 && data.length != entry.fileSizeBytes) {
      return ArchiveRetrievalResult._(
        messageId: messageId,
        ok: false,
        tier: entry.tier,
        error: 'incomplete: ${data.length} B of ${entry.fileSizeBytes} B',
      );
    }
    if (entry.contentHash.isNotEmpty &&
        _computeSimpleHash(data) != entry.contentHash) {
      return ArchiveRetrievalResult._(
        messageId: messageId,
        ok: false,
        tier: entry.tier,
        error: 'content hash mismatch',
      );
    }

    try {
      MediaStore.instance.writeBytes(targetPath, data);
    } catch (e) {
      MediaStore.instance.delete(targetPath);
      _log.warn('Archive retrieval could not store $messageId: $e');
      return ArchiveRetrievalResult._(
        messageId: messageId,
        ok: false,
        tier: entry.tier,
        error: 'store failed: $e',
      );
    }

    final read = MediaStore.instance.plainLength(targetPath);
    if (read != data.length) {
      MediaStore.instance.delete(targetPath);
      return ArchiveRetrievalResult._(
        messageId: messageId,
        ok: false,
        tier: entry.tier,
        error: 'readback failed: $read of ${data.length} B',
      );
    }

    // The entry may have changed during the download (an
    // archive run downgrades further, the user pins). Therefore the
    // FRESH state is read, not the one from the start.
    //
    // §21.6: "A retrieved original counts as new" — `retrievedAt` is set on
    // every successful retrieval, so the tiers count from now (S392-15).
    final fresh = _entries[messageId] ?? entry;
    _entries[messageId] = ArchiveEntry(
      messageId: fresh.messageId,
      conversationId: fresh.conversationId,
      shareUrl: fresh.shareUrl,
      archivedAt: fresh.archivedAt,
      tier: ArchiveTier.original,
      contentHash: fresh.contentHash,
      pinned: fresh.pinned,
      fileSizeBytes: fresh.fileSizeBytes,
      mimeType: fresh.mimeType,
      originalFilename: fresh.originalFilename,
      retrievedAt: DateTime.now(),
    );
    _persistMessage(messageId);

    return ArchiveRetrievalResult._(
      messageId: messageId,
      ok: true,
      tier: ArchiveTier.original,
      bytes: data.length,
    );
  }

  // -- Persistence ---------------------------------------------------------

  /// Loads the archive index from the store (area [kEntriesArea]).
  ///
  /// ONE RECORD PER MESSAGE, and the record carries both: the archive entry
  /// (`e`) and the pin (`p`). They lie together because they
  /// apply together — but are stored separately, because a pin can also
  /// exist without an entry (`setPin` on a not yet
  /// offloaded medium) and an entry without a pin is the normal case.
  /// A single damaged record costs exactly this one
  /// message, not the index.
  Future<void> _loadEntries() async {
    final s = _store;
    if (s == null) {
      // Without a store there is nothing to load AND nothing to write; the
      // latch below thus does not need `_loaded` at all.
      _loaded = true;
      return;
    }
    try {
      for (final row in s.loadArea(kEntriesArea).entries) {
        final e = row.value['e'];
        if (e is Map<String, dynamic>) {
          try {
            final entry = ArchiveEntry.fromJson(e);
            _entries[entry.messageId] = entry;
            _statusMap[entry.messageId] = ArchiveStatus.confirmed;
          } catch (_) {
            // Damaged record — only this one message is lost.
          }
        }
        final p = row.value['p'];
        if (p is bool) _pinned[row.key] = p;
      }
      _loaded = true;
      _log.info('Archive index loaded: ${_entries.length} entries, '
          '${_pinned.length} pins');
    } catch (e) {
      // NOT `_loaded = true`. Whoever falls through here has NOT seen a
      // possibly full index and therefore must not
      // touch it either — the latch in [_persistMessage] holds it.
      _log.warn('Failed to load archive index: $e');
    }
  }

  /// Writes EXACTLY ONE message. That is the only write path.
  ///
  /// ── THE DATA-LOSS LATCH ─────────────────────────────────────────
  ///
  /// Until S366 there was none here. The old `_loadEntries` caught every
  /// error with the comment "Corrupt file — start fresh" and left
  /// the empty stock in place; the full-state writer `_saveEntries`
  /// laid it over the full one at the next archive run. For
  /// THIS collection that is the most expensive loss in the whole profile: the index is
  /// the only mapping of message to storage location on the
  /// network storage. If it is gone, nobody knows anymore which medium was
  /// offloaded where — the files still lie on the NAS, but
  /// under `<Monat>/<bereinigter Name>` and without a way back to the message;
  /// the placeholders in the conversation point into nothing, and
  /// [retrieveArchivedMedia] returns `null` for each of them.
  ///
  /// The latch asks the STORE and not the file — never
  /// written again after the switchover: as long as nothing was loaded and the
  /// area holds rows, NOTHING is written. If the store itself is
  /// not readable, it fails CLOSED (no writing).
  void _persistMessage(String messageId) {
    final s = _store;
    if (s == null) return;
    if (!_loaded) {
      int present;
      try {
        present = s.countArea(kEntriesArea);
      } catch (e) {
        _log.warn('REFUSED to persist archive entry $messageId — '
            'store unreadable: $e');
        return;
      }
      if (present > 0) {
        _log.warn('REFUSED to persist archive entry $messageId — load '
            'failed but the store still holds $present row(s). '
            'Overwriting would lose the mapping message -> share URL '
            'for every archived attachment. Data loss risk!');
        return;
      }
    }
    final entry = _entries[messageId];
    final pinned = _pinned[messageId];
    try {
      if (entry == null && pinned == null) {
        s.removeEntry(kEntriesArea, messageId);
        return;
      }
      s.putEntry(kEntriesArea, messageId, {
        'e': ?entry?.toJson(),
        'p': ?pinned,
      });
    } catch (e) {
      _log.warn('Failed to persist archive entry $messageId: $e');
    }
  }

  // -- Helper methods ------------------------------------------------------

  String _monthDir(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}';

  String _sanitizeName(String name) =>
      name.replaceAll(RegExp(r'[^\w\-. ]'), '_').trim();

  String _computeSimpleHash(Uint8List data) {
    // Simple hash for deduplication (FNV-1a 64-bit as hex).
    // In production, SodiumFFI.sha256 would be used.
    var hash = 0xcbf29ce484222325;
    for (final byte in data) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  String _shareUrlToRemotePath(String shareUrl) {
    // Remove protocol prefix, remove host.
    //
    // S392/B4: read via `uri.path`, the path came back
    // PERCENT-ENCODED. `_sanitizeName` explicitly leaves the space
    // (`[^\w\-. ]`), so a conversation is quite normally called
    // "Alice Bob" — and `Uri.parse('smb:///Alice Bob/…').path` returns
    // `Alice%20Bob/…`. This text would go as a file name to `smbclient`,
    // `sftp` or `curl`; there is no `%20` there, and every retrieval
    // from a conversation with a space in its name failed.
    // `pathSegments` are decoded.
    return Uri.parse(shareUrl).pathSegments.join('/');
  }
}

/// Outcome of a retrieval from the share.
///
/// [tier] is the tier AFTER the attempt — so for `ok == false` the
/// unchanged old one. With it the caller can tell without a second question
/// whether the message has its original again.
class ArchiveRetrievalResult {
  final String messageId;
  final bool ok;
  final ArchiveTier tier;

  /// Written payload in bytes. `0` if nothing had to be fetched
  /// ([alreadyLocal]) or the attempt failed.
  final int bytes;

  /// The file was already local and the tier was already at `original` —
  /// it was NOT fetched from the share.
  final bool alreadyLocal;

  /// Reason for the failure, machine-level and untranslated. This is not
  /// UI text: the core layer runs in the service, the language choice lies in the
  /// UI process (working rule 7). The UI chooses its
  /// own sentence and appends this one at most as a detail.
  final String? error;

  const ArchiveRetrievalResult._({
    required this.messageId,
    required this.ok,
    required this.tier,
    this.bytes = 0,
    this.alreadyLocal = false,
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'messageId': messageId,
        'ok': ok,
        'tier': tier.name,
        'bytes': bytes,
        if (alreadyLocal) 'alreadyLocal': true,
        if (error != null) 'error': error,
      };

  @override
  String toString() => ok
      ? 'ArchiveRetrieval($messageId): ok, $bytes B, tier=${tier.name}'
          '${alreadyLocal ? ' (already local)' : ''}'
      : 'ArchiveRetrieval($messageId): failed ($error), tier=${tier.name}';
}

/// Result of an archive check.
class ArchiveCheckResult {
  int archived = 0;
  int failed = 0;
  int tierChecked = 0;
  int evicted = 0;
  String? skippedReason;

  bool get wasSkipped => skippedReason != null;

  @override
  String toString() => wasSkipped
      ? 'ArchiveCheck: skipped ($skippedReason)'
      : 'ArchiveCheck: $archived archived, $failed failed, '
          '$tierChecked tier checks, $evicted evicted';
}

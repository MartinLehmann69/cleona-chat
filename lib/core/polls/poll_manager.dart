import 'dart:math';
import 'package:cleona/core/storage/message_store.dart';
import 'package:cleona/core/log/clogger.dart';
import 'package:cleona/core/service/service_types.dart';
import 'package:cleona/core/util/hex.dart';

/// PollManager — local poll CRUD, vote aggregation, persistence (§24).
///
/// One instance per identity (same pattern as CalendarManager). Polls are
/// persisted as encrypted JSON, keyed by pollId. Votes are stored inside
/// each poll's `votes` map.
class PollManager {
  final String profileDir;
  final String identityId;
  final MessageStore? _store;
  final CLogger _log;

  /// All polls owned or known by this identity, keyed by pollId.
  final Map<String, Poll> polls = {};

  bool _loaded = false;

  PollManager({
    required this.profileDir,
    required this.identityId,
    this._store,
  })  : // profileDir is a constructor parameter (per identity) -> directly usable.
        _log = CLogger.get('polls[${shortHex(identityId)}]',
            profileDir: profileDir);

  // ── Persistence ────────────────────────────────────────────────────────

  void load() {
    if (_store == null) {
      _loaded = true;
      return; // Proxy mode (IPC client)
    }
    try {
      // S366: from the storage (area `polls`) instead of from `polls.json`.
      for (final entry in _store.loadArea('polls').entries) {
        try {
          polls[entry.key] = Poll.fromJson(entry.value);
        } catch (e) {
          _log.warn('Skipping corrupt poll ${entry.key}: $e');
        }
      }
      _log.info('Loaded ${polls.length} polls');
      _loaded = true;
    } catch (e) {
      _log.warn('Failed to load polls: $e');
    }
  }

  void save() {
    if (_store == null) return;
    if (!_loaded && polls.isEmpty) {
      _log.warn('REFUSED to save empty poll store — load may have failed');
      return;
    }
    try {
      _store.replaceArea('polls', {
        for (final e in polls.entries) e.key: e.value.toJson(),
      });
    } catch (e) {
      _log.warn('Failed to save polls: $e');
    }
  }

  /// Writes ONE poll. §21.4.1: `polls.json` was rewritten entirely
  /// on every vote — 11 triggers, no cap, no deadline. That
  /// is the same pattern that led to the quadratic curve for the messages,
  /// only on a small scale. Whoever changes a single poll
  /// calls this instead of [save].
  void persistPoll(String pollId) {
    final s = _store;
    if (s == null) return;
    final poll = polls[pollId];
    if (poll == null) {
      s.removeEntry('polls', pollId);
      return;
    }
    try {
      s.putEntry('polls', pollId, poll.toJson());
    } catch (e) {
      _log.warn('Failed to persist poll $pollId: $e');
    }
  }

  // ── CRUD ───────────────────────────────────────────────────────────────

  String createPoll(Poll poll) {
    polls[poll.pollId] = poll;
    persistPoll(poll.pollId);
    _log.info('Created poll ${poll.pollId}: ${poll.question}');
    return poll.pollId;
  }

  bool deletePoll(String pollId) {
    final removed = polls.remove(pollId);
    if (removed != null) {
      persistPoll(pollId);
      _log.info('Deleted poll $pollId');
      return true;
    }
    return false;
  }

  /// Close a poll (either by creator action or automatic deadline).
  bool closePoll(String pollId) {
    final poll = polls[pollId];
    if (poll == null || poll.closed) return false;
    poll.closed = true;
    poll.updatedAt = DateTime.now().millisecondsSinceEpoch;
    persistPoll(pollId);
    return true;
  }

  bool reopenPoll(String pollId) {
    final poll = polls[pollId];
    if (poll == null || !poll.closed) return false;
    poll.closed = false;
    poll.updatedAt = DateTime.now().millisecondsSinceEpoch;
    persistPoll(pollId);
    return true;
  }

  bool addOptions(String pollId, List<PollOption> newOptions) {
    final poll = polls[pollId];
    if (poll == null) return false;
    final maxId = poll.options.isEmpty
        ? -1
        : poll.options.map((o) => o.optionId).reduce(max);
    var next = maxId + 1;
    for (final opt in newOptions) {
      poll.options.add(PollOption(
        optionId: next++,
        label: opt.label,
        dateStart: opt.dateStart,
        dateEnd: opt.dateEnd,
      ));
    }
    poll.updatedAt = DateTime.now().millisecondsSinceEpoch;
    persistPoll(pollId);
    return true;
  }

  bool removeOptions(String pollId, List<int> optionIds) {
    final poll = polls[pollId];
    if (poll == null) return false;
    poll.options.removeWhere((o) => optionIds.contains(o.optionId));
    // Also scrub removed selections from votes
    for (final v in poll.votes.values) {
      v.selectedOptions.removeWhere(optionIds.contains);
      for (final id in optionIds) {
        v.dateResponses.remove(id);
      }
    }
    poll.updatedAt = DateTime.now().millisecondsSinceEpoch;
    persistPoll(pollId);
    return true;
  }

  bool extendDeadline(String pollId, int newDeadline) {
    final poll = polls[pollId];
    if (poll == null) return false;
    poll.settings.deadline = newDeadline;
    poll.updatedAt = DateTime.now().millisecondsSinceEpoch;
    persistPoll(pollId);
    return true;
  }

  // ── Voting ─────────────────────────────────────────────────────────────

  /// Record a vote. Rejects duplicate if [allowVoteChange] is false, or if
  /// the poll is closed. Returns true if the vote was accepted.
  bool recordVote(PollVoteRecord vote) {
    final poll = polls[vote.pollId];
    if (poll == null) {
      _log.debug('Vote for unknown poll ${vote.pollId}');
      return false;
    }
    if (poll.closed) {
      _log.debug('Vote for closed poll ${vote.pollId} rejected');
      return false;
    }
    final key = vote.voterIdHex;
    final existing = poll.votes[key];
    if (existing != null) {
      if (!poll.settings.allowVoteChange) {
        _log.debug('Vote change disabled for ${vote.pollId}, keeping existing');
        return false;
      }
      if (vote.votedAt <= existing.votedAt) {
        // Older or equal → ignore (LWW)
        return false;
      }
    }
    poll.votes[key] = vote;
    poll.updatedAt = DateTime.now().millisecondsSinceEpoch;
    // The most frequent change of all — and the one that formerly
    // rewrote all polls on EVERY vote.
    persistPoll(vote.pollId);
    return true;
  }

  /// Remove an anonymous vote by key image (§24.4.5).
  bool revokeAnonymousVote(String pollId, String keyImageHex) {
    final poll = polls[pollId];
    if (poll == null) return false;
    final removed = poll.votes.remove(keyImageHex);
    if (removed != null) {
      poll.updatedAt = DateTime.now().millisecondsSinceEpoch;
      save();
      return true;
    }
    return false;
  }

  // ── Aggregation ────────────────────────────────────────────────────────

  /// Compute a local tally from stored votes (groups).
  PollTally computeTally(String pollId) {
    final poll = polls[pollId];
    if (poll == null) {
      return PollTally(totalVotes: 0);
    }

    final optionCounts = <int, int>{};
    final dateCounts = <int, Map<DateAvailability, int>>{};
    var scaleSum = 0;
    var scaleCount = 0;
    final freeTextResponses = <String>[];

    for (final v in poll.votes.values) {
      switch (poll.pollType) {
        case PollType.singleChoice:
        case PollType.multipleChoice:
          for (final id in v.selectedOptions) {
            optionCounts[id] = (optionCounts[id] ?? 0) + 1;
          }
          break;
        case PollType.datePoll:
          for (final entry in v.dateResponses.entries) {
            final bucket = dateCounts.putIfAbsent(entry.key, () => {});
            bucket[entry.value] = (bucket[entry.value] ?? 0) + 1;
          }
          break;
        case PollType.scale:
          if (v.scaleValue >= poll.settings.scaleMin &&
              v.scaleValue <= poll.settings.scaleMax) {
            scaleSum += v.scaleValue;
            scaleCount += 1;
          }
          break;
        case PollType.freeText:
          if (v.freeText.isNotEmpty) freeTextResponses.add(v.freeText);
          break;
      }
    }

    return PollTally(
      totalVotes: poll.votes.length,
      optionCounts: optionCounts,
      dateCounts: dateCounts,
      scaleAverage: scaleCount == 0 ? 0.0 : scaleSum / scaleCount,
      scaleCount: scaleCount,
      freeTextResponses: freeTextResponses,
    );
  }

  // ── Deadline enforcement ───────────────────────────────────────────────

  /// Close polls whose deadline has passed. Returns the IDs closed.
  List<String> enforceDeadlines() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final closed = <String>[];
    for (final poll in polls.values) {
      if (!poll.closed &&
          poll.settings.deadline > 0 &&
          now >= poll.settings.deadline) {
        poll.closed = true;
        poll.updatedAt = now;
        closed.add(poll.pollId);
      }
    }
    if (closed.isNotEmpty) save();
    return closed;
  }

  // ── Utility ────────────────────────────────────────────────────────────

  static String generateUuid() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

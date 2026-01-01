import 'dart:math';
import 'package:cleona/core/crypto/file_encryption.dart';
import 'package:cleona/core/network/clogger.dart';
import 'package:cleona/core/service/service_types.dart';

/// PollManager — local poll CRUD, vote aggregation, persistence (§24).
///
/// One instance per identity (same pattern as CalendarManager). Polls are
/// persisted as encrypted JSON, keyed by pollId. Votes are stored inside
/// each poll's `votes` map.
class PollManager {
  final String profileDir;
  final String identityId;
  final FileEncryption? _fileEnc;
  final CLogger _log;

  /// All polls owned or known by this identity, keyed by pollId.
  final Map<String, Poll> polls = {};

  bool _loaded = false;

  PollManager({
    required this.profileDir,
    required this.identityId,
    FileEncryption? fileEnc,
  })  : _fileEnc = fileEnc,
        _log = CLogger.get('polls[$identityId]');

  // ── Persistence ────────────────────────────────────────────────────────

  void load() {
    if (_fileEnc == null) {
      _loaded = true;
      return; // Proxy mode (IPC client)
    }
    try {
      final json = _fileEnc.readJsonFile('$profileDir/polls.json');
      if (json != null) {
        for (final entry in json.entries) {
          try {
            polls[entry.key] =
                Poll.fromJson(entry.value as Map<String, dynamic>);
          } catch (e) {
            _log.warn('Skipping corrupt poll ${entry.key}: $e');
          }
        }
        _log.info('Loaded ${polls.length} polls');
      }
    } catch (e) {
      _log.warn('Failed to load polls: $e');
    }
    _loaded = true;
  }

  void save() {
    if (_fileEnc == null) return;
    if (!_loaded && polls.isEmpty) {
      _log.warn('REFUSED to save empty poll store — load may have failed');
      return;
    }
    try {
      final json = <String, dynamic>{};
      for (final entry in polls.entries) {
        json[entry.key] = entry.value.toJson();
      }
      _fileEnc.writeJsonFile('$profileDir/polls.json', json);
    } catch (e) {
      _log.warn('Failed to save polls: $e');
    }
  }

  // ── CRUD ───────────────────────────────────────────────────────────────

  String createPoll(Poll poll) {
    polls[poll.pollId] = poll;
    save();
    _log.info('Created poll ${poll.pollId}: ${poll.question}');
    return poll.pollId;
  }

  bool deletePoll(String pollId) {
    final removed = polls.remove(pollId);
    if (removed != null) {
      save();
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
    save();
    return true;
  }

  bool reopenPoll(String pollId) {
    final poll = polls[pollId];
    if (poll == null || !poll.closed) return false;
    poll.closed = false;
    poll.updatedAt = DateTime.now().millisecondsSinceEpoch;
    save();
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
    save();
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
    save();
    return true;
  }

  bool extendDeadline(String pollId, int newDeadline) {
    final poll = polls[pollId];
    if (poll == null) return false;
    poll.settings.deadline = newDeadline;
    poll.updatedAt = DateTime.now().millisecondsSinceEpoch;
    save();
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
    save();
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

import '../network/clogger.dart';
import '../service/cleona_service.dart';
import 'system_channels.dart';

/// Helper for posting feature requests with auto-attached polls (§9.5.3).
class FeatureRequestHelper {
  final CleonaService _service;
  final CLogger _log = CLogger.get('FeatureReq');

  /// Tracks posts-per-day for rate limiting.
  final List<DateTime> _postTimestamps = [];

  FeatureRequestHelper(this._service);

  bool get isRateLimited {
    final now = DateTime.now();
    _postTimestamps.removeWhere((t) => now.difference(t).inHours >= 24);
    return _postTimestamps.length >= SystemChannels.maxFeaturePostsPerDay;
  }

  /// Posts a feature request to the Feature Request channel and
  /// automatically creates a poll attached to it.
  ///
  /// Returns the poll ID on success, null on failure.
  Future<String?> submitFeatureRequest(String description) async {
    if (isRateLimited) {
      _log.warn('Feature request rate limit reached');
      return null;
    }

    if (description.trim().isEmpty) return null;

    final textBytes = description.codeUnits.length;
    if (textBytes > SystemChannels.maxManualPostBytes) {
      _log.warn('Feature request exceeds size limit');
      return null;
    }

    // Post to the channel
    final post = await _service.sendChannelPost(
      SystemChannels.featureReqChannelIdHex,
      description,
    );
    if (post == null) {
      _log.warn('Failed to post feature request to channel');
      return null;
    }

    // Auto-create poll with the first line as question
    final firstLine = description.split('\n').first.trim();
    final question = firstLine.length > 100
        ? '${firstLine.substring(0, 97)}...'
        : firstLine;

    try {
      final pollId = await _service.createPoll(
        question: question,
        pollType: PollType.singleChoice,
        options: [
          PollOption(optionId: 0, label: 'Ja, umsetzen'),
          PollOption(optionId: 1, label: 'Nein'),
          PollOption(optionId: 2, label: 'Egal'),
        ],
        settings: PollSettings(
          anonymous: false,
          allowVoteChange: true,
          showResultsBeforeClose: true,
        ),
        groupIdHex: SystemChannels.featureReqChannelIdHex,
      );

      _postTimestamps.add(DateTime.now());
      _log.info('Feature request posted with poll $pollId');
      return pollId;
    } catch (e) {
      _log.warn('Failed to create auto-poll for feature request: $e');
      _postTimestamps.add(DateTime.now());
      return null;
    }
  }
}

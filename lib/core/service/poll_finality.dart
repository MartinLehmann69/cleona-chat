import 'package:cleona/core/service/service_types.dart';

/// §18.3.4 rule 3: how long a poll tally stays provisional.
const Duration kPollFinalityWindow = Duration(days: 21);

/// §8.2 / §9.5: a collection that ended more than this long ago is treated
/// as an absence when deciding whether unanswered catch-up requests block
/// finality.
const Duration kPollCatchUpStaleThreshold = Duration(days: 7);

/// Whether the tally of [poll] may be presented as final.
///
/// A tally is final iff:
///   * the poll is closed, and
///   * the current [clock] time is at least [kPollFinalityWindow] after the
///     effective deadline (the stored deadline if set, otherwise the moment
///     the poll was closed, i.e. [Poll.updatedAt]), and
///   * it is NOT the case that the device's last collection lies more than
///     [kPollCatchUpStaleThreshold] in the past and there are still open
///     catch-up requests (§9.5).
///
/// The helper is stateless so it can be used both from the service extension
/// and from unit/smoke tests without building a full [CleonaService].
bool isPollTallyFinal({
  required Poll? poll,
  required DateTime? catchUpLastCollection,
  required bool hasOpenCatchUpRequests,
  required DateTime Function() clock,
}) {
  if (poll == null) return false;
  if (!poll.closed) return false;

  final effectiveDeadlineMs =
      poll.settings.deadline > 0 ? poll.settings.deadline : poll.updatedAt;
  final effectiveDeadline = DateTime.fromMillisecondsSinceEpoch(effectiveDeadlineMs);
  if (clock().isBefore(effectiveDeadline.add(kPollFinalityWindow))) {
    return false;
  }

  final stale = catchUpLastCollection != null &&
      clock().difference(catchUpLastCollection) > kPollCatchUpStaleThreshold;
  if (stale && hasOpenCatchUpRequests) return false;

  return true;
}

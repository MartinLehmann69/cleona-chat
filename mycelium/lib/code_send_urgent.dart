/// Signals of a running call reach the last resort at once (v4_2 §8.1
/// "Signals of a running call", D-127, owner 18.11.2026; finding
/// `berichte/S427-RCA-VOLLLAUF-34T06.md`).
///
/// Step 3 tries silent candidates one after the other before the last
/// resort (06.10.2026 variant B, `code_send_retry.dart`): four answer
/// deadlines each, 3.2 s. A call signal — a new sending key after a leave or
/// join, a join or leave — cannot wait that long; in gui-34 34.T06 a new key
/// was 6.43 s on its way behind two dead open neighbours and the call was
/// deaf meanwhile. For such a signal ([urgent]: the ladder's [Target.signal])
/// the `0x20` also goes to the last resort at once when the first hop is not
/// live — live in the sense the open set is ordered by (`linkLive`, OP-23).
/// Every other sending keeps the order of variant B.
library;

import 'package:mycelium/card_address.dart';

/// Whether the inner `0x20` goes to [resort] now, beside [hop].
bool resortAtOnce(
        bool urgent, CardAddress hop, CardAddress? resort, bool Function(CardAddress) live) =>
    urgent && resort != null && !resort.equal(hop) && !live(hop);

/// The log line of such a sending (§8.1: each is reported).
String resortAtOnceLine(CardAddress resort, CardAddress hop) =>
    'Step 3: call signal also to the last resort $resort at once — the first '
    'hop $hop is not live (§8.1 "Signals of a running call", D-127); this node '
    'sees both ends of this signal';

/// Two numbers of the delivery layer that have consumers OUTSIDE
/// `tagline/` — and that therefore must not fall with `tagline/`.
///
/// ## Why this file exists
///
/// `tagline/` is replaced by the V4.2 delivery layer (`package:mycelium`)
/// — `Cleona_Chat_Architecture_v4_2.md` §22.4.1 (l. 7492) calls
/// it `delivery/` and describes it as "wire, parts, envelope,
/// ladder", literally wire, parts, envelope, ladder. During the tear-down it
/// turned out that two constants from `tagline/delivery_state.dart` and
/// `tagline/delivery_api.dart` are read by modules that per §22.4
/// STAY (`sync/`, `calls/`, `bulk/`).
///
/// They cannot live in mycelium: its word ban forbids
/// "Familie", and a call deadline has no business in the delivery layer
/// anyway (§17.2).
///
/// They live here and not in `partition.dart` because they have nothing
/// to do with the independence question treated there — and in
/// `sync/` because §22.4.1 lists it as a remaining module and the two
/// largest consumers (`cover_stream.dart`, `cleona_service.dart`)
/// lie here or next to it.
///
/// **NO STATE, NO I/O.**
library;

/// How many address families a delivery carries (D1).
///
/// Was in `tagline/delivery_state.dart` until the tear-down. Consumers
/// that STAY: `sync/cover_stream.dart`,
/// `service/cleona_service_rotation_window.dart`,
/// `service/media_send_estimate.dart` (as factor m in `m x R`),
/// `service/cleona_service.dart`, `calls/call_manager.dart`.
const int kDeliveryFamilies = 3;

/// How long an interactive frame may be in transit (§17.2).
///
/// Was in `tagline/delivery_api.dart` until the tear-down. The only
/// remaining consumer is `calls/call_manager.dart` — there the
/// reachability deadline of a call is held against it, so that it does not
/// run longer than the frame itself lives. `bulk/responsibility.dart`
/// names it in a justification without reading it.
const Duration kInteractiveDeliveryTtl = Duration(seconds: 120);

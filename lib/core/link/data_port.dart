/// Data-port draw — which UDP/TCP port a node's link layer binds
/// (AP-3a stage 1, docs/MIGRATION_V3_TO_V4_0_MYZEL.md §4d.2/§4d.9).
///
/// Moved here from `IdentityManager.drawDataPort`
/// (lib/core/identity/identity_manager.dart) in AP-3a stage 1: the port a
/// node listens on is a property of the link layer, not of identity
/// management — every later stage (transport parametrization, escalation)
/// builds on it from inside `lib/core/link/`. Moved **completely**, no
/// delegate left behind: a forwarding shim would create a second access
/// path to the same function, the exact pattern AP-1b documented as harmful
/// ("five accesses instead of one", §3b). Guarded by
/// `test/smoke/smoke_data_port_draw.dart`.
library;

import 'dart:math';

abstract final class DataPort {
  /// Draw a random UDP data port for a new identity.
  ///
  /// §4.5.2 invariant `nodePort != discoveryPort`: the LAN-discovery sockets
  /// bind the fixed port 41338. If a node's *data* port were the same value,
  /// Transport and LocalDiscovery/MulticastDiscovery would all bind 41338 —
  /// and because every one of them sets `SO_REUSEADDR`, the bind succeeds
  /// silently instead of failing. From then on the kernel splits inbound
  /// traffic between the sockets: V3 packets landing on a discovery socket
  /// die at the 38-byte length check, discovery frames landing on the
  /// transport socket die at the HMAC check. Sending stays intact, so the
  /// node looks healthy to everyone else while its own reception is lossy.
  ///
  /// The exclusion costs one value out of 55 000 — the port stays random per
  /// node, which is what keeps Cleona from being blockable by a single port
  /// rule. It also removes a fingerprinting surface: a node whose data port
  /// equals the publicly documented discovery port announces itself as
  /// Cleona to any scanner.
  ///
  /// **FOLLOWED UP 2026-09-08 (S376, finding P2-3).** Until then the draw
  /// excluded only [lanDiscoveryPort] (41338) — the fixed port of the
  /// **V3** LAN discovery. On the V4.1 line nobody binds this port any
  /// more: `lib/core/network/` has carried zero files since the CUT
  /// (2026-08-31). What is bound instead is [lanEntryPort] (41340), the
  /// port of the V4.1 call sequence (`tagline/lan_entry_wiring.dart` binds
  /// it on the multicast group and the limited broadcast, in the fallback
  /// on the wildcard — all three with `reuseAddress`/`reusePort`). The
  /// exclusion thus protected exactly the value on which nothing hangs any
  /// more, and left free the value at which the described damage really
  /// arises: if a node draws 41340, data port and entry listener bind the
  /// same port, the bind succeeds silently, and the kernel distributes the
  /// inbound datagrams between both.
  ///
  /// Since then **both** values are excluded ([isReservedLanPort]).
  /// 41338 stays in although it has no binder here any more: the price is
  /// one value out of 55 000, and the draw wanders into profiles that live
  /// longer than a branch.
  ///
  /// The second exclusion is [browserUnsafePort] (E-64, V4 §19.6.5): 10080 is
  /// the only value in 10000–64999 that every browser refuses with
  /// `ERR_UNSAFE_PORT`. A node that happened to draw it would serve its
  /// invitation links (§19.6.5 browser assembler) on a port no browser will
  /// ever open — the links would be dead in every browser, permanently and
  /// without any error the node could see. Same price as the discovery-port
  /// exclusion: one value out of 55 000.
  static int drawDataPort() {
    int port;
    do {
      port = 10000 + Random().nextInt(55000);
    } while (isReservedLanPort(port) || port == browserUnsafePort);
    return port;
  }

  /// The fixed port the LAN-discovery sockets bind, and the first value
  /// [drawDataPort] excludes.
  ///
  /// **The definition lives here, not in `lib/core/network/lan_discovery.dart`
  /// (D-5).** The invariant `nodePort != discoveryPort` is a property of the
  /// link layer's port draw, so the value belongs where the draw is. The
  /// direction used to be the other way round, and it was the **only** import
  /// edge from any of the twelve `lib/core/link/` modules into
  /// `lib/core/network/` — one `static const int` that pulled the whole V3
  /// transport in behind it (`lan_discovery.dart` imports `transport.dart`)
  /// and with it broke the milestone "two V4 hosts without a single V3
  /// module". Reversing it keeps **one** definition site — a second one would
  /// be the pattern AP-1b recorded as harmful — and lets the edge die on its
  /// own when `lib/core/network/` is deleted at the lab gate. **That happened
  /// on 2026-08-31** (CUT); `lib/core/network/` has zero files, measured
  /// 2026-09-03.
  ///
  /// `LocalDiscovery.discoveryPort` (lib/core/network/lan_discovery.dart:22)
  /// was a pure forwarder onto this constant and remained the access path
  /// for the V3 transport's own call sites — thirteen reads inside
  /// `lan_discovery.dart` itself. The file fell with the CUT; since then
  /// this constant is the ONLY definition site **and** the only access.
  ///
  /// **FOLLOWED UP ON 2026-08-31 (CUT, step 0).** The sentence above read
  /// "stays the access path for every V3 call site, of which there are ten"
  /// and was wrong from that day. Four callers outside of
  /// `lib/core/network/` read the constant via the detour
  /// `LocalDiscovery.discoveryPort` — `service/cleona_service.dart`,
  /// `ipc/ipc_server.dart`, `ui/screens/settings_screen.dart` and
  /// `identity/identity_manager.dart`. Each of them thereby pulled
  /// `lan_discovery.dart` and with it `transport.dart` into the application
  /// layer: four import edges onto the V3 tree for one `static const int`.
  /// It was the same trap that D-5 above describes for `lib/core/link/`,
  /// only one floor higher.
  ///
  /// All four now read `DataPort.lanDiscoveryPort` directly. Thus outside
  /// of `lib/core/network/` `lan_discovery.dart` only had
  /// `lib/core/node/cleona_node.dart` as an importer (which instantiated the
  /// class itself) and two smokes that checked the collision invariant
  /// against the V3 shim itself. The guard for this is section 8 in
  /// `test/smoke/smoke_link_io_milestone.dart`.
  ///
  /// **RE-MEASURED 2026-09-03.** Both V3 trees are empty; the readers in
  /// `lib/` today are `identity/identity_manager.dart:416` and `:715`,
  /// `ipc/ipc_server.dart:2082`, `service/cleona_service.dart:6181`,
  /// `ui/screens/settings_screen.dart:107` as well as the draw in this
  /// file (`:47`) — all directly on this constant, no detour any more.
  static const int lanDiscoveryPort = 41338;

  /// The fixed port of the **V4.1** call sequence in the own segment
  /// (appendix A of the architecture document: "LAN entry port — **41340**,
  /// and **only inside the own segment**", §11.1).
  ///
  /// **HERE, NOT IN `tagline/lan_entry.dart` — one definition site.** The
  /// value is needed at two places that belong to different layers: the
  /// call sequence binds it, and the port draw of this file must exclude
  /// it. Two literals would be exactly the pattern that D-5 (above) and
  /// AP-1b record as harmful — the one value wanders, the other stays, and
  /// the exclusion protects the wrong port. Exactly this case was measured
  /// on 2026-09-08, only with 41338/41340 instead of two versions of the
  /// same value.
  ///
  /// The direction of the edge is the only possible one: `tagline/` imports
  /// `link/` at thirteen places, `link/` imports `tagline/` at none.
  /// `tagline/lan_entry.dart` therefore forwards `kLanEntryPort` to this
  /// constant — the name stays, because about twenty places read it; the
  /// VALUE stands only here.
  static const int lanEntryPort = 41340;

  /// Does [port] coincide with one of the two fixed LAN ports?
  ///
  /// **The only access for the rejection paths.** Five places besides the
  /// draw check a port coming from the user or from a profile against the
  /// reserved range: `identity/identity_manager.dart` (self-healing on
  /// load, `updatePort`), `ipc/ipc_server.dart` (`set_port`),
  /// `service/cleona_service.dart` (`setPort`, the in-process path of
  /// Android and iOS) and `ui/screens/settings_screen.dart` (the dialog).
  /// Until 2026-09-08 they each compared against [lanDiscoveryPort] on
  /// their own. A list that is repeated at five places is not a list but
  /// five — that is why it stands here and is only asked there.
  static bool isReservedLanPort(int port) =>
      port == lanDiscoveryPort || port == lanEntryPort;

  /// The single `ERR_UNSAFE_PORT` value inside the data-port range
  /// 10000–64999 (E-64, V4 §19.6.5). Browsers refuse to open any URL on this
  /// port, which would silently kill this node's invitation links.
  ///
  /// The other blocked ports of the browser lists (21, 25, 110, 6667, …) all
  /// lie below 10000 and are therefore already out of range.
  static const int browserUnsafePort = 10080;
}

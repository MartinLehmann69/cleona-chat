/// Value types of the rendezvous layer.
///
/// ── WHAT STOOD HERE UNTIL S362 ──────────────────────────────────────────
///
/// The file arose in AP-1a as an extraction from
/// `network/rendezvous/rendezvous_manager.dart`, so that the teardown of
/// `lib/core/network/` does not take the V4 survivors along. Of the three
/// types only one ever had callers outside the since
/// removed `RendezvousManager`:
///
///   `RendezvousContact`  — contact descriptor with `deviceNodeIds`.
///   `ResolvedEndpoint`   — result of `resolveContacts`.
///
/// Both have been removed with it (S362, owner decision 02.09.2026: "V3
/// compatibility is no longer necessary"). The contact-related
/// rendezvous according to §4.11 is replaced on the V4.1 line by the pairwise
/// liveness (§6, §8) and the entry cascade (§11); what
/// carries an address in V4.1 is `EntryRecord`
/// (`tagline/entry_record.dart`), not `ResolvedEndpoint`.
///
/// [RendezvousAddress] stays: `binary_rendezvous_manager.dart` and
/// `first_contact_rendezvous_manager.dart` obtain their address list
/// through it.
library;

/// Address descriptor for the current endpoint.
class RendezvousAddress {
  final String ip;
  final int port;

  const RendezvousAddress(this.ip, this.port);
}

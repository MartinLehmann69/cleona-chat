/// Who is admitted on a stream transport, and who is not.
///
/// **Why this file exists at all.** On UDP the MAC check is the first
/// thing that happens — a sender without `L_node` produces **zero** state
/// (measured: 2.29 million garbage cells at 1.88 Gbit/s -> zero sessions,
/// zero descriptors, healing in under a second). On TCP exactly that is
/// **structurally impossible**: `accept()` IS the state creation. The node
/// must own a socket and a file descriptor **before** it may look at a
/// single byte.
///
/// What happens at the descriptor limit is no gentle tailing off:
/// measured, the listener **silently** stops accepting (`onError` never
/// fires — proven three times independently), and **every** file
/// operation in the process fails from that moment: log file, key file,
/// encrypted DB. In one measurement run an uninvolved `Directory.listSync`
/// tore down the daemon with `errno 24`. It does not heal by itself.
///
/// **What is NOT attempted here, and why.** Before the first byte the node
/// knows **exclusively the source address** of the other end. On IPv6 an
/// attacker controls this quantity completely (an end-customer /56
/// contains 256 own /64s), and an honest user under CGNAT shares it with
/// up to 128 strangers. A quantity that the attacker can choose freely and
/// the honest one cannot is no good for separation. RFC 6269 §13.1 says
/// the same for the whole class: "In the presence of widespread
/// large-scale address sharing, **penalty box solutions to service abuse
/// simply will not work**."
///
/// Both were measured. A cap "4 per source address" fired **zero times**
/// against an attacker with 60 000 source addresses, while an honest peer
/// with a 300 ms path stood at **0 %**; and in the CGNAT case it hit
/// exclusively the honest one.
///
/// **The inversion is the design: do not recognise the attacker, but
/// protect the friends.** That is the same axis that E-114 already chose
/// one layer higher.
///
/// **Pot B (known).** A source address goes in **if and only if** under it
/// a flight 1 once arrived completely, passed the MAC and the responder
/// built flight 2. Not on mere connection setup, not on a valid MAC alone.
/// Pot B shares **nothing** with pot U — therein lies the whole effect: a
/// flood that fills pot U cannot reach pot B.
///
/// **Why the way in cannot be flooded.** A complete handshake costs the
/// attacker, as measured, 0.304 ms and 1 200 B per attempt — about
/// **31 Mbit/s** to saturate a core, versus the **0.58 Mbit/s** with which
/// he brings a pure cap down to zero. The way in is about **50 times more
/// expensive** than the attack that pot B fends off.
///
/// Measured, both roles in the same run, at about 8 300 attacker
/// connections per second: known partner **100 %**, unknown newcomer
/// **8 %** — versus **0 % in both roles** with a pure cap.
///
/// **What this design explicitly does NOT achieve:**
/// - **Cold start.** A node without known partners has an empty pot B
///   and is as well protected as a pure cap. The protection grows with
///   the age of the node.
/// - **The `L_node` MAC is no proof of strangeness.** §2.6a: "Whoever knows
///   the receiver's `L_node` — **every one of its peers does**, since it is
///   one value per node and not one per partner", plus RL-13: "**Entry nodes
///   are enumerable**". A censor who looks up the node in the rendezvous
///   HAS `L_node`. The MAC keeps blind scanners away (E-58, and that is
///   valuable) — it does not carry the security property. Pot B does.
/// - **An attacker with several /56s** undermines the rate counter too.
///   He moves the bar, he does not tear it down.
///
/// I/O-free: this file opens no socket and reads no clock it has not been
/// given.
library;

/// Where an offered connection belongs.
enum LinkAdmissionSlot {
  /// Known partner — own pot, unreachable by any flood.
  known,

  /// Unknown — pot U, capped and rate-limited.
  unknown,

  /// No room. **Rejecting means accepting and closing immediately (FIN)**,
  /// not swallowing the SYN.
  ///
  /// Measured: with a full accept queue the kernel silently discards the
  /// SYN, and the caller sees **`ETIMEDOUT`** after eight seconds — not
  /// `ECONNREFUSED`. But `kLinkRefusedErrno` deliberately excludes
  /// `ETIMEDOUT` (E-116(6): "the network is silent"). An overloaded node
  /// would thus be indistinguishable from a **dead** one, and the honest
  /// peer burns its full step timeout instead of escalating immediately.
  /// A FIN is distinguishable from silence; a swallowed SYN is not.
  refused,
}

/// The prefixes on which the rate counter keys.
///
/// **Two-tiered, and that is a correction.** The obvious choice —
/// WireGuard's `/32` and `/64` — falls short at both ends:
/// - **`/64` is undermined by every normal connection.** RIPE-690 §1
///   calls prefixes longer than `/56` "strongly discouraged"; an
///   evaluation of the RIPE database finds `/56` in over 81 % of `inet6num`.
///   A `/56` holder owns **256 own `/64`s** and rotates for free.
/// - **`/64` at the same time locks out uninvolved parties.** RFC 9663 §1,
///   first sentence: "**Often, broadcast networks such as enterprise or
///   public Wi-Fi deployments place many devices on a shared link with a
///   single on-link prefix.**" A company or hotel `/64` carries hundreds of
///   strangers.
///
/// M3AAWG named the conflict of objectives: "must aggregate a sufficiently
/// large range … **However, selecting too large an address range will
/// result in false positives**". The proven state of the art is therefore
/// two-tiered — Let's Encrypt keeps `/48` coarse and `/64` fine, with RFC
/// reasoning in the source code.
///
/// **Never `/128`.** That is the OpenSSH default (`32:128`), and it is
/// justified in no release note and no source code comment.
abstract final class LinkPrefix {
  /// Fine limit: IPv4 `/32`, IPv6 `/64`.
  ///
  /// `/64` is right as fine, because 3GPP guarantees it: RFC 6459 §5.2 —
  /// "the /64 prefix is **unique for the UE**". A cellular subscriber
  /// shares it with nobody.
  static String fine(String address) => _mask(address, 64);

  /// Coarse limit: IPv4 `/32` (there is no coarser sensible unit for a
  /// single address), IPv6 `/56` — the end-customer limit from RIPE-690.
  static String coarse(String address) => _mask(address, 56);

  static String _mask(String address, int bits) {
    if (!address.contains(':')) return address; // IPv4: /32 == the address
    final groups = _expandV6(address);
    if (groups == null) return address;
    final keep = bits ~/ 16;
    final rest = bits % 16;
    final out = <String>[];
    for (var i = 0; i < keep; i++) {
      out.add(groups[i].toRadixString(16));
    }
    if (rest != 0 && keep < 8) {
      final mask = (0xFFFF << (16 - rest)) & 0xFFFF;
      out.add((groups[keep] & mask).toRadixString(16));
    }
    return '${out.join(':')}::/$bits';
  }

  /// Splits an IPv6 address into eight 16-bit groups, `::` resolved.
  ///
  /// Returns `null` if the address is not readable — the caller then
  /// falls back to the full address. **Not** to an empty string: that would
  /// throw all unreadable addresses into the same rate counter and would
  /// thus be a lock-out primitive.
  static List<int>? _expandV6(String address) {
    var a = address;
    final zone = a.indexOf('%');
    if (zone >= 0) a = a.substring(0, zone);
    if (a.contains('.')) return null; // IPv4-mapped: do not mask
    final halves = a.split('::');
    if (halves.length > 2) return null;
    List<int>? parse(String part) {
      if (part.isEmpty) return <int>[];
      final out = <int>[];
      for (final g in part.split(':')) {
        if (g.isEmpty) return null;
        final v = int.tryParse(g, radix: 16);
        if (v == null || v < 0 || v > 0xFFFF) return null;
        out.add(v);
      }
      return out;
    }

    final head = parse(halves[0]);
    if (head == null) return null;
    if (halves.length == 1) return head.length == 8 ? head : null;
    final tail = parse(halves[1]);
    if (tail == null) return null;
    final fill = 8 - head.length - tail.length;
    if (fill < 0) return null;
    return <int>[...head, ...List<int>.filled(fill, 0), ...tail];
  }
}

/// One token bucket per prefix.
///
/// **A rate, not concurrency — and that is the core.** An honest peer
/// handshakes **rarely**: a session lives one hour (§2.6a), sync partners
/// are two per family (§4.6 rule 1). An attacker handshakes
/// **constantly**. A concurrency cap does not see this difference — both
/// occupy one slot. A rate counter sees it.
final class _Bucket {
  double tokens;
  DateTime last;
  _Bucket(this.tokens, this.last);
}

/// A slot in the pot.
final class _Slot {
  final LinkAdmissionSlot pot;
  DateTime deadline;
  bool macChecked = false;
  _Slot(this.pot, this.deadline);
}

/// The admission rule of a stream listener.
final class LinkAdmission {
  /// Cap for known partners.
  ///
  /// **256, because the neighbour table carries 256.**
  /// `LinkDemux.maxSessions` stands at 256, and the comment there
  /// explicitly forbids "two answers to one question in neighbouring code"
  /// (E-89). The size itself follows from §4.6 rule 1 (two sync partners
  /// per family) with plenty of room for incoming ones.
  final int capKnown;

  /// Cap for unknown candidates.
  ///
  /// **Derived from `C ≥ A · F`.** Measured, an attacker setup costs two
  /// sent segments, about 180 B including framing; at **1 Mbit/s** that is
  /// about **694 setups per second**. With the deadline of 1.5 s that gives
  /// 1 041 — rounded **1 024**.
  ///
  /// **What is set here is only the design point 1 Mbit/s**, not the
  /// computation. Cost: 1 024 descriptors, measured about 10 MB.
  ///
  /// **Platform caveat.** 1 024 undecided connections need 1 024 free
  /// descriptors. Measured on the device: Android inherits from zygote64
  /// **32 768** soft (524 288 hard) — a factor of 32 headroom. Linux desktop
  /// measured 1 048 576. **Windows and macOS are unmeasured**; if the budget
  /// there is lower, the NUMBER is to be chosen smaller, not the rule
  /// changed.
  final int capUnknown;

  /// How many ADDRESSES pot B carries at most.
  ///
  /// ── WHY THIS CAP MUST EXIST ─────────────────────────────
  ///
  /// Until now pot B was a set without an exit: an address came in with
  /// [handshakeCompleted] and never out again, and [forget] had **zero
  /// callers** in the whole tree. That was not merely a memory leak.
  /// **Pot B IS the protective effect** — whoever stands in it goes past
  /// the rate counter and past [capUnknown] —, and a pot that only grows
  /// becomes over time indistinguishable from "everyone is known".
  ///
  /// Computed with the numbers that stand in the header of this file: a
  /// complete handshake costs the attacker, as measured, 0.304 ms and
  /// 1 200 B, a saturated core thus about **3 289 addresses per second**
  /// — just under **200 000 in one minute**. After that his whole address
  /// set stands in pot B, goes past the rate counter and occupies the
  /// [capKnown] slots that are there for known partners. The effect
  /// reverses: the attacker sits in the protected pot, the honest partner
  /// gets `refused`.
  ///
  /// **That is NOT only effective with the outgoing half of
  /// `tcpOwnPort`.** The pot is filled by the LISTENER
  /// (`tcp_listener.dart`, `handshakeCompleted` at handshake completion),
  /// and that has been wired since S361. That no Cleona node dials over
  /// TCP today says nothing about an attacker who is not a Cleona node.
  ///
  /// ── WHY THIS NUMBER ──────────────────────────────────────────────
  ///
  /// **[capKnown], the same 256.** An entry in pot B is only of use if
  /// there is also a slot for it; if the [capKnown] slots are occupied,
  /// the 257th remembered address gets `refused` anyway. A larger pot would
  /// thus serve no honest partner and would only dilute the statement
  /// "known".
  ///
  /// ── WHAT HAPPENS ON OVERFLOW: REMEMBER NOTHING MORE ──────────────
  ///
  /// **No eviction.** [_expire] explains one line further down why
  /// eviction is a kill primitive here, and for pot B it would be even
  /// more clearly so: a full-speed attacker empties an LRU eviction in
  /// **78 ms** (256 entries at 3 289/s) and thereby pushes **every existing
  /// partner** into pot U. Fail-closed makes nobody worse off than today:
  /// a NEW partner who is not remembered with a full pot stands exactly
  /// where he would stand without pot B.
  ///
  /// **The residual price is not talked away:** an attacker who pays the
  /// handshake costs can occupy the pot and for the duration of
  /// [knownLifetime] prevent NEW partners from getting in. Existing ones
  /// he does not touch. That is the same class of statement as the one in
  /// the header: he moves the bar, he does not tear it down.
  final int capKnownSources;

  /// How long an address stays in pot B after its last connection ENDED.
  ///
  /// ── ONE HOUR, AND THE ONE ALREADY ASSIGNED ─────────────────────
  ///
  /// `LinkDemux.sessionIdleLifetime` and `TcpLinkChannel.idleLifetime`
  /// both stand at one hour: that is how long a session may stay silent
  /// before the link layer considers this partner gone. A pot B entry
  /// that lives longer says the opposite about THE SAME partner. The same
  /// question, the same number — no new one.
  ///
  /// The number is written out instead of imported, for the same reason
  /// as with [macCheckedLifetime]: `LinkDemux` lies in `link_io/`, this
  /// file in `link/`, and `link_io/` imports `link/`. An import back would
  /// reverse the layering. The coupling is CHECKED instead
  /// (`smoke_link_admission.dart`).
  ///
  /// ── THE DEADLINE RUNS FROM THE END, NOT FROM THE START ─────────────
  ///
  /// A deadline from [handshakeCompleted] would be wrong, namely for
  /// exactly the partners for whom this pot exists: a healthy session runs
  /// on indefinitely (the cover stream keeps it awake) and during this time
  /// handshakes **not a second time**. It would be forgotten after an hour
  /// and would stand in pot U at the next connection break — i.e. exactly
  /// when it needs the pot.
  ///
  /// That is why an entry **does not age as long as a connection from
  /// this address is open**, and the deadline starts only with [release].
  /// That is the version in which the pot measures what it claims to
  /// measure: "with this address there was a real connection recently".
  final Duration knownLifetime;

  /// Deadline for an unknown candidate that has not shown anything yet.
  ///
  /// **`kLinkStageTimeout` = 1.5 s, and that is derived:** if flight 1 is
  /// not there after a step timeout, the initiator has **already given up
  /// this step itself** (§4.8). Holding the slot after that serves nobody.
  final Duration unknownLifetime;

  /// Deadline after the `L_node` MAC has been passed.
  ///
  /// **`LinkDemux.defaultPendingLifetime` = 4 × 1.5 s**, already derived in
  /// the tree as "one full cascade run". The same question, the same
  /// number — no new one.
  final Duration macCheckedLifetime;

  /// Refill rate and bucket size of the rate counter, per prefix.
  ///
  /// **20/s with burst 5 — WireGuard's default, taken over unchanged.**
  /// A Cleona handshake is due at most hourly per partner (session
  /// lifetime one hour); 20/s leaves three-digit headroom. A tighter choice
  /// (2/s, burst 4) was tried during measurement and hit an **honest** peer
  /// three times there — it is therefore rejected.
  final double bucketRate;
  final double bucketBurst;

  final Map<String, _Slot> _slots = <String, _Slot>{};

  /// Pot B: address -> deadline until which it counts as known.
  ///
  /// A deadline in the past does not mean "already gone": as long as
  /// [_openPerAddress] records an open connection for this address, the
  /// entry does not age (see [knownLifetime]).
  final Map<String, DateTime> _known = <String, DateTime>{};

  /// Connection key -> address, for the connections whose handshake
  /// completed and which are still standing.
  ///
  /// It is the reason why [release] knows the address at all:
  /// [handshakeCompleted] clears the slot out of [_slots], and without this
  /// mapping it would no longer be determinable afterwards WHOSE connection
  /// is ending there. It does not grow without bound — it is capped by the
  /// open connections, i.e. by the descriptors.
  final Map<String, String> _open = <String, String>{};

  /// How many open connections per address — the counter from which
  /// [_expire] can read whether an entry may age. As a counter and not as
  /// `containsValue`, because that would run over the whole map per entry.
  final Map<String, int> _openPerAddress = <String, int>{};

  final Map<String, _Bucket> _fine = <String, _Bucket>{};
  final Map<String, _Bucket> _coarse = <String, _Bucket>{};

  LinkAdmission({
    this.capKnown = 256,
    this.capUnknown = 1024,
    int? capKnownSources,
    this.knownLifetime = const Duration(hours: 1),
    this.unknownLifetime = const Duration(milliseconds: 1500),
    this.macCheckedLifetime = const Duration(milliseconds: 6000),
    this.bucketRate = 20,
    this.bucketBurst = 5,
  }) : capKnownSources = capKnownSources ?? capKnown;

  int get openKnown =>
      _slots.values.where((s) => s.pot == LinkAdmissionSlot.known).length;
  int get openUnknown =>
      _slots.values.where((s) => s.pot == LinkAdmissionSlot.unknown).length;
  int get knownSources => _known.length;

  /// Is [address] a partner with whom a handshake has already completed here?
  bool isKnown(String address) => _known.containsKey(address);

  /// Decides on a connection just accepted.
  ///
  /// [key] identifies the connection (on a stream the four-tuple or a
  /// running number — **not** the address, because several connections of
  /// the same address are the normal case).
  LinkAdmissionSlot offer(String key, String address, DateTime now) {
    _expire(now);

    if (_known.containsKey(address)) {
      // **Known ones NEVER go through the rate counter and never over the
      // U cap.** Exactly that is the mechanism: a flood in pot U must not
      // reach an existing partner.
      if (openKnown >= capKnown) return LinkAdmissionSlot.refused;
      // USE REFRESHES. A partner who dials again is exactly what the pot is
      // meant to hold on to; the deadline from the end of the LAST
      // connection would otherwise already be half expired while the new
      // one is still standing.
      _known[address] = now.add(knownLifetime);
      _slots[key] = _Slot(LinkAdmissionSlot.known, now.add(unknownLifetime));
      return LinkAdmissionSlot.known;
    }

    if (openUnknown >= capUnknown) return LinkAdmissionSlot.refused;
    if (!_spend(_fine, LinkPrefix.fine(address), now)) {
      return LinkAdmissionSlot.refused;
    }
    // The coarse limit gets 256 times the budget — the number of /64s in
    // a /56 —, so that an ordinary household never touches it.
    if (!_spend(_coarse, LinkPrefix.coarse(address), now, factor: 256)) {
      return LinkAdmissionSlot.refused;
    }
    _slots[key] = _Slot(LinkAdmissionSlot.unknown, now.add(unknownLifetime));
    return LinkAdmissionSlot.unknown;
  }

  /// The `L_node` MAC of this connection has checked out (byte 48).
  ///
  /// **Byte 48, not 1 200 — and that is the second big lever.** The field
  /// layout of flight 1 is `E2(eph_pub)` 32 B from offset 0, then
  /// `MAC(L_node, …)` 16 B from offset 32; the expensive AEAD only begins at
  /// 48. Measured, the abort after a failed MAC costs **~5.7 µs**, the full
  /// responder path **0.310 ms** — ratio **54 : 1**. Whoever sets the
  /// threshold at 1 200 B holds the descriptor 25 times longer than
  /// necessary.
  void macPassed(String key, DateTime now) {
    final s = _slots[key];
    if (s == null) return;
    s.macChecked = true;
    s.deadline = now.add(macCheckedLifetime);
  }

  /// The handshake is complete — the responder has built flight 2.
  ///
  /// **Only here** does the source address move into pot B. Not on
  /// connection setup, not on a valid MAC alone: only a complete,
  /// expensive, valid handshake counts.
  /// **The cap takes effect here, not on rejection.** If pot B is full
  /// ([capKnownSources]), the address is **not remembered** — and the
  /// connection nevertheless keeps running. It has come about; what falls
  /// away is only the promise to treat it preferentially next time.
  /// Nothing is evicted (see [capKnownSources] and [_expire]).
  void handshakeCompleted(String key, String address, DateTime now) {
    _expire(now);
    if (_known.containsKey(address) || _known.length < capKnownSources) {
      _known[address] = now.add(knownLifetime);
      _open[key] = address;
      _openPerAddress[address] = (_openPerAddress[address] ?? 0) + 1;
    }
    _slots.remove(key);
  }

  /// The connection is closed.
  ///
  /// **Here the deadline of pot B starts to run** — see [knownLifetime]:
  /// as long as the connection stood, the entry has not aged.
  void release(String key, DateTime now) {
    _slots.remove(key);
    final address = _open.remove(key);
    if (address == null) return;
    final open = (_openPerAddress[address] ?? 1) - 1;
    if (open <= 0) {
      _openPerAddress.remove(address);
    } else {
      _openPerAddress[address] = open;
    }
    if (_known.containsKey(address)) {
      _known[address] = now.add(knownLifetime);
    }
  }

  /// Forgets a known partner (e.g. when its address wanders).
  ///
  /// Remains the explicit handle for a caller who KNOWS that an address no
  /// longer belongs to this partner. The regular case no longer needs it:
  /// since [knownLifetime] the deadline takes care of the forgetting, and
  /// for that nobody has to know anything.
  void forget(String address) {
    _known.remove(address);
    _openPerAddress.remove(address);
    _open.removeWhere((_, a) => a == address);
  }

  /// **Expired slots are released, NOT evicted.**
  ///
  /// Evicting — throwing out the oldest candidate to make room — is, as
  /// measured, a **kill primitive**: with cap C and attacker rate A a slot
  /// survives C/A seconds, and every peer with a longer path drops out
  /// deterministically. The tree has already rejected the same class of
  /// rule one layer higher ("whoever can forge produces targeted failures
  /// and throws out foreign sessions").
  ///
  /// **The same applies to pot B, and there additionally: an address with
  /// an OPEN connection does not age.** Its deadline only runs from
  /// [release] — see [knownLifetime] for the reason (a healthy session
  /// does not handshake a second time and would otherwise be forgotten
  /// exactly when it needs the pot).
  void _expire(DateTime now) {
    _slots.removeWhere((_, s) => !s.deadline.isAfter(now));
    _known.removeWhere((address, deadline) =>
        !_openPerAddress.containsKey(address) && !deadline.isAfter(now));
  }

  bool _spend(Map<String, _Bucket> buckets, String key, DateTime now,
      {int factor = 1}) {
    final cap = bucketBurst * factor;
    final rate = bucketRate * factor;
    final b = buckets.putIfAbsent(key, () => _Bucket(cap, now));
    final dt = now.difference(b.last).inMicroseconds / 1e6;
    if (dt > 0) {
      b.tokens = (b.tokens + dt * rate).clamp(0, cap);
      b.last = now;
    }
    if (b.tokens < 1) return false;
    b.tokens -= 1;
    return true;
  }
}

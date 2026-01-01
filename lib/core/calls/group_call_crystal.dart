/// The crystal of §17.7 from 7 participants on — a spanning tree over media
/// pairs only, built by the participants themselves (S408, package P6 of
/// `mycelium/berichte/S407-GRUPPENANRUF.md`, A.6).
///
/// §17.7: "The crystal, from 7 participants on, is built over media pairs
/// only. Its root is the participant highest by the ranking below and its
/// free capacity under `f_i`, not the one that started the call; every node
/// takes as its parent the media pair nearest the root that still has room
/// under its `f_i`, the one with the most free capacity among equals, so
/// that the load spreads over several forwarders. A node forwards a frame
/// over every tree link except the one it came by. Two participants with no
/// common contact are joined through any chain of media pairs the tree runs
/// along; one that no tree link reaches is shown "No common contact in the
/// call"."
///
/// ── WHY DISTRIBUTED, AND WHICH PROCEDURE ─────────────────────────────
///
/// A participant knows only its own media pairs, and the control plane runs
/// over media pairs only (§17.1.1) — the initiator has no way to a
/// participant that is no contact of it, and learning everybody's media
/// pairs would hand it the contact graph of the call (S407-GRUPPENANRUF
/// §2.3, "Variante zentral (nicht empfohlen)"). So every node builds its own
/// place, as in IEEE 802.1D (spanning tree): it tells each media pair the
/// root it believes in and how far that is (`treeOffer`), asks the media
/// pair it chose for a place (`treeJoin`), and the chosen one confirms or
/// refuses by its room (`treeAccept`). The distance is carried as the PATH
/// to the root — a path vector as in BGP (RFC 4271 §9.1.2: a route whose
/// path holds oneself is not taken) —, so no node ever takes a parent below
/// itself and no count to infinity arises when a branch breaks; the path is
/// at most the depth of the tree (≈ 3 at 25 participants).
///
/// No clock and no repetition here (§11.3a, rule 5): every record answers an
/// edge — a join or leave, a media pair that starts or ends (§17.4), a limit
/// the line has shown — and goes in the 1-Hz control frame (§17.1.1). Each
/// record expects its `treeAccept`; repeating an unanswered one is the
/// transport's (`CallTransport.requestControl`). A record that would say
/// nothing new is not sent.
///
/// ── `f_i` WHILE THE LINE HAS SHOWN NO LIMIT ─────────────────────────
///
/// `f_i = floor(usable_upload_i / (K x bitrate_per_stream))` needs the
/// usable upload, and the upload probe knows it only after the line showed
/// a limit (`BrokerCapacity.fromProbe`, P5-4). Until then the node's room is
/// unbounded, as §17.7 says it for the broker ("Until its line has shown a
/// limit, a broker's free capacity is unbounded and the one carrying fewer
/// forwarded streams has more of it"): [kCrystalNoKnownLimit] minus the
/// children it carries. The price, named in the S408 report: until a loss
/// report shows the root's limit (§17.1.1, S407-GALOSS), every participant
/// holding a media pair with the root hangs directly below it.
library;

import 'dart:typed_data';

import 'package:cleona/core/calls/call_control_frame.dart';
import 'package:cleona/core/calls/upload_probe.dart' show NetworkForm, PowerSource;

/// §17.7: `K` — "the number of streams forwarded concurrently (the loudest
/// speakers, typically 3–4)"; 4 as in the load table of S407-GRUPPENANRUF B.
const int kCrystalStreamsPerLink = 4;

/// The room of a node whose line has shown no limit — "unbounded", as large
/// as the one byte of `free` in `treeOffer` can say; fewer children, more
/// room.
const int kCrystalNoKnownLimit = 255;

/// `treeJoin` flags.
const int kTreeLeave = 0, kTreeJoin = 1, kTreeUpdate = 2;

/// `treeAccept` codes.
const int kTreeRefused = 0, kTreeAccepted = 1, kTreeOfferSeen = 2;

// ── The three records (§17.1.1), all behind the roster checksum ─────────

/// What a media pair said in its last `treeOffer`, indices resolved.
typedef CrystalOffer = ({
  String root,
  int rootRank,
  int free,
  List<String> path,
});

/// `roster(2) ‖ root(1) ‖ rank(1) ‖ free(1) ‖ path(…)` — the path names
/// the sender's parent first and the root last; it is empty at the root.
ControlRecord buildTreeOffer(List<String> list, CrystalOffer o) {
  final h = rosterHash(list);
  return ControlRecord(
      ControlRecordType.treeOffer,
      Uint8List.fromList([
        h >> 8,
        h & 0xFF,
        list.indexOf(o.root),
        o.rootRank,
        o.free.clamp(0, 255),
        for (final p in o.path) list.indexOf(p),
      ]));
}

CrystalOffer? readTreeOffer(ControlRecord r, List<String> list) {
  final v = r.value;
  if (r.type != ControlRecordType.treeOffer ||
      v.length < 5 ||
      ((v[0] << 8) | v[1]) != rosterHash(list) ||
      v.skip(2).take(1).followedBy(v.skip(5)).any((i) => i >= list.length)) {
    return null;
  }
  return (
    root: list[v[2]],
    rootRank: v[3],
    free: v[4],
    path: [for (final i in v.skip(5)) list[i]],
  );
}

/// `roster(2) ‖ flag(1) ‖ bitmap of the sender's subtree below it`.
ControlRecord buildTreeJoin(List<String> list, int flag, Set<String> below) {
  final h = rosterHash(list);
  final v = Uint8List(3 + subtreeBitmapBytes(list.length))
    ..[0] = h >> 8
    ..[1] = h & 0xFF
    ..[2] = flag;
  for (final m in below) {
    final i = list.indexOf(m);
    if (i >= 0) v[3 + (i >> 3)] |= 1 << (i & 7);
  }
  return ControlRecord(ControlRecordType.treeJoin, v);
}

(int, Set<String>)? readTreeJoin(ControlRecord r, List<String> list) {
  final v = r.value;
  if (r.type != ControlRecordType.treeJoin ||
      v.length != 3 + subtreeBitmapBytes(list.length) ||
      ((v[0] << 8) | v[1]) != rosterHash(list) ||
      v[2] > kTreeUpdate) {
    return null;
  }
  return (
    v[2],
    <String>{
      for (var i = 0; i < list.length; i++)
        if (v[3 + (i >> 3)] & (1 << (i & 7)) != 0) list[i],
    }
  );
}

/// `roster(2) ‖ code(1) ‖ tag(1)` — the tag names what is answered: the
/// flag of a `treeJoin`, or the checksum of a `treeOffer` ([offerTag]).
ControlRecord buildTreeAccept(List<String> list, int code, int tag) {
  final h = rosterHash(list);
  return ControlRecord(ControlRecordType.treeAccept,
      Uint8List.fromList([h >> 8, h & 0xFF, code, tag & 0xFF]));
}

(int, int)? readTreeAccept(ControlRecord r) {
  final v = r.value;
  if (r.type != ControlRecordType.treeAccept || v.length != 4) return null;
  return (v[2], v[3]);
}

int offerTag(ControlRecord offer) =>
    offer.value.fold<int>(0, (a, b) => a + b) & 0xFF;

/// The rank by which roots compare (§17.7: "reachable at all → link type
/// (wired/WLAN before cellular) → power source (mains before battery) →
/// measured usable upload"): link score in bits 4–5, power score in bits
/// 2–3, the fan-out class in bits 0–1. Higher is better; equal ranks fall to
/// the smaller identifier. Only a participant that is reached at all sends
/// an offer, so the first step of the ranking is the offer itself.
int crystalRank(NetworkForm form, PowerSource power, int fanOut) {
  final link = switch (form) {
    NetworkForm.wired || NetworkForm.wifi => 2,
    NetworkForm.unknown => 1,
    NetworkForm.cellular => 0,
  };
  final mains = switch (power) {
    PowerSource.mains => 2,
    PowerSource.unknown => 1,
    PowerSource.battery => 0,
  };
  final room = fanOut >= 6
      ? 3
      : fanOut >= 3
          ? 2
          : fanOut >= 1
              ? 1
              : 0;
  return (link << 4) | (mains << 2) | room;
}

/// `f_i = floor(usable_upload_i / (K x bitrate_per_stream))` (§17.7) from
/// the usable upload the line has shown, [kCrystalNoKnownLimit] while it has
/// shown none (`BrokerCapacity.fromProbe`).
int crystalFanOut(int? usableBps, int streamBps) => usableBps == null
    ? kCrystalNoKnownLimit
    : (usableBps ~/ (kCrystalStreamsPerLink * streamBps))
        .clamp(0, kCrystalNoKnownLimit - 1);

// ── The node ──────────────────────────────────────────────────────────

/// One participant's place in the crystal.
class GroupCallCrystal {
  GroupCallCrystal({
    required this.ownHex,
    required this.roster,
    required this.mediaPairs,
    required this.isJoined,
    required this.fanOut,
    required this.ownRank,
    required this.request,
    this.onChanged,
    this.log,
  });

  final String ownHex;

  /// The sorted participant list every index points into.
  final List<String> Function() roster;

  /// The participants this device holds a carrying media pair with.
  final Set<String> Function() mediaPairs;
  final bool Function(String hex) isJoined;

  /// `f_i` — how many children this node may carry.
  final int Function() fanOut;
  final int Function() ownRank;

  /// Sends a record that expects its answer; [onFailed] once the transport
  /// gave up on it (§11.3a). `null` [answeredBy]: an answer, expecting none.
  final void Function(String toHex, ControlRecord record,
      bool Function(ControlRecord)? answeredBy, void Function() onFailed) request;

  /// The own place changed: parent, children or what lies below them.
  final void Function()? onChanged;
  final void Function(String line)? log;

  final Map<String, CrystalOffer> _offers = {};
  String? _parent;
  String? _joining;
  final Map<String, Set<String>> _children = {};
  final Set<String> _refusedBy = {};
  final Map<String, String> _sentOffer = {};
  String _joinBelow = '';
  String? _sentBelow;

  String? get parent => _parent;

  /// A place below a media pair is asked for and not answered yet.
  bool get seekingPlace => _joining != null;

  /// child → the participants below it (the child itself not included).
  Map<String, Set<String>> get children => Map.unmodifiable(_children);

  /// The root this node believes in.
  String get root => _offers[_parent]?.root ?? ownHex;

  /// Everyone in this node's subtree below it.
  Set<String> get below => <String>{
        for (final MapEntry(key: c, value: b) in _children.entries) ...{c, ...b},
      };

  // ── records ────────────────────────────────────────────────────────

  void handle(String fromHex, ControlRecord r) {
    final list = roster();
    switch (r.type) {
      case ControlRecordType.treeOffer:
        final o = readTreeOffer(r, list);
        if (o == null) return _drop(fromHex, r);
        _answer(fromHex, kTreeOfferSeen, offerTag(r));
        _offers[fromHex] = o;
        _refusedBy.remove(fromHex);
      case ControlRecordType.treeJoin:
        final j = readTreeJoin(r, list);
        if (j == null) return _drop(fromHex, r);
        _joinFrom(fromHex, j.$1, j.$2..remove(fromHex));
      case ControlRecordType.treeAccept:
        final a = readTreeAccept(r);
        if (a == null || a.$1 == kTreeOfferSeen || a.$2 != kTreeJoin) return;
        if (fromHex != _joining) {
          // A place given where this node no longer asks for one.
          if (a.$1 == kTreeAccepted && fromHex != _parent) {
            _sendJoin(fromHex, kTreeLeave);
          }
          return;
        }
        _joining = null;
        if (a.$1 == kTreeAccepted) {
          final old = _parent;
          _parent = fromHex;
          _sentBelow = '$fromHex|$_joinBelow';
          if (old != null && old != fromHex) _sendJoin(old, kTreeLeave);
          _log('parent ${_s(fromHex)} (root ${_s(root)})');
          onChanged?.call();
        } else {
          _refusedBy.add(fromHex);
        }
      default:
        return;
    }
    reconsider();
  }

  void _joinFrom(String c, int flag, Set<String> belowC) {
    if (flag == kTreeLeave) {
      _answer(c, kTreeAccepted, flag);
      if (_children.remove(c) != null) onChanged?.call();
      return;
    }
    final isChild = _children.containsKey(c);
    final loop = c == _parent || _pathOf(_parent).contains(c);
    if (!mediaPairs().contains(c) ||
        loop ||
        (!isChild && (flag != kTreeJoin || _children.length >= fanOut()))) {
      _answer(c, kTreeRefused, flag);
      return;
    }
    _answer(c, kTreeAccepted, flag);
    _children[c] = belowC;
    if (!isChild) _log('child ${_s(c)} (${_children.length}/${fanOut()})');
    onChanged?.call();
  }

  // ── edges ──────────────────────────────────────────────────────────

  /// A media pair started or ended, a participant came or left, or the line
  /// showed its limit: decide the own place again and tell what changed.
  void reconsider() {
    final pairs = mediaPairs();
    // An offer from a participant whose media pair is not decided HERE yet
    // is kept: the other side's window may carry first, and its offer is
    // not sent twice. It counts once the pair carries here ([_valid]).
    _offers.removeWhere((p, _) => !isJoined(p));
    var changed = false;
    for (final c in _children.keys.toList()) {
      if (!pairs.contains(c)) {
        _children.remove(c);
        changed = true;
      }
    }
    if (_joining != null && !pairs.contains(_joining)) _joining = null;
    if (_parent != null && !_valid(_parent!)) {
      _log('parent ${_s(_parent!)} gone or below us — the place is open');
      if (pairs.contains(_parent)) _sendJoin(_parent!, kTreeLeave);
      _parent = null;
      _sentBelow = null;
      changed = true;
    }
    final best = _bestRoot();
    if (best == ownHex) {
      _joining = null;
      if (_parent != null) {
        _sendJoin(_parent!, kTreeLeave);
        _parent = null;
        _sentBelow = null;
        changed = true;
      }
    } else {
      final want = _chooseParent(best);
      if (want != null && want != _parent && want != _joining) {
        // A place asked for elsewhere and not answered yet is given back:
        // its answer may still come, and a place nobody takes would be
        // forwarded to.
        final asked = _joining;
        if (asked != null && pairs.contains(asked)) {
          _sendJoin(asked, kTreeLeave);
        }
        _joining = want;
        _joinBelow = _belowKey(roster());
        _sendJoin(want, kTreeJoin);
      }
    }
    if (changed) onChanged?.call();
    _tell(pairs);
  }

  /// The call ended or left the crystal.
  void clear() {
    _offers.clear();
    _children.clear();
    _refusedBy.clear();
    _sentOffer.clear();
    _parent = null;
    _joining = null;
    _sentBelow = null;
  }

  // ── choices ────────────────────────────────────────────────────────

  List<String> _pathOf(String? p) =>
      p == null ? const <String>[] : [p, ...?_offers[p]?.path];

  /// An offer is a way to its root if the root and every hop are still in
  /// the call and the way does not run through this node.
  bool _valid(String p) {
    final o = _offers[p];
    return o != null &&
        mediaPairs().contains(p) &&
        o.root != ownHex &&
        isJoined(p) &&
        isJoined(o.root) &&
        !o.path.contains(ownHex) &&
        o.path.every(isJoined);
  }

  /// "Its root is the participant highest by the ranking … and its free
  /// capacity under `f_i`" — among this node and every root a valid offer
  /// names.
  String _bestRoot() {
    var best = ownHex;
    var rank = ownRank();
    for (final MapEntry(key: p, value: o) in _offers.entries) {
      if (!_valid(p)) continue;
      if (o.rootRank > rank ||
          (o.rootRank == rank && o.root.compareTo(best) < 0)) {
        best = o.root;
        rank = o.rootRank;
      }
    }
    return best;
  }

  /// "the media pair nearest the root that still has room under its `f_i`,
  /// the one with the most free capacity among equals", then the smaller
  /// identifier. A present parent at the nearest distance is kept: a place
  /// that carries is not moved for room alone (§17.7 says it of the broker,
  /// "A binding that carries is not moved") — otherwise every node that saw
  /// the same room elsewhere would move at once, and back.
  String? _chooseParent(String rootHex) {
    final c = <(String, int, int)>[
      for (final MapEntry(key: p, value: o) in _offers.entries)
        if (o.root == rootHex &&
            _valid(p) &&
            !_refusedBy.contains(p) &&
            (p == _parent || o.free > 0))
          (p, o.path.length, o.free),
    ]..sort((a, b) {
        if (a.$2 != b.$2) return a.$2.compareTo(b.$2);
        if (a.$3 != b.$3) return b.$3.compareTo(a.$3);
        return a.$1.compareTo(b.$1);
      });
    if (c.isEmpty) return null;
    final keep = c.where((e) => e.$1 == _parent && e.$2 == c.first.$2);
    return keep.isNotEmpty ? _parent : c.first.$1;
  }

  // ── telling ────────────────────────────────────────────────────────

  String _belowKey(List<String> list) =>
      (below.map(list.indexOf).toList()..sort()).join(',');

  void _answer(String to, int code, int tag) =>
      request(to, buildTreeAccept(roster(), code, tag), null, () {});

  void _sendJoin(String to, int flag) {
    request(to, buildTreeJoin(roster(), flag, below), (a) {
      final r = readTreeAccept(a);
      return r != null && r.$1 != kTreeOfferSeen && r.$2 == flag;
    }, () {
      // The transport gave up (§11.3a): the place was not given.
      if (flag != kTreeJoin || _joining != to) return;
      _joining = null;
      _refusedBy.add(to);
      reconsider();
    });
  }

  /// The own offer to every media pair whose last one differs, and the own
  /// subtree to the parent when it changed.
  void _tell(Set<String> pairs) {
    final list = roster();
    final rootHex = root;
    final path = _pathOf(_parent);
    if (!list.contains(rootHex) || !path.every(list.contains)) return;
    final rec = buildTreeOffer(list, (
      root: rootHex,
      rootRank: _offers[_parent]?.rootRank ?? ownRank(),
      free: fanOut() - _children.length,
      path: path,
    ));
    final key = rec.value.join(',');
    final tag = offerTag(rec);
    for (final p in pairs) {
      if (_sentOffer[p] == key) continue;
      _sentOffer[p] = key;
      request(p, rec, (a) {
        final r = readTreeAccept(a);
        return r != null && r.$1 == kTreeOfferSeen && r.$2 == tag;
      }, () {});
    }
    _sentOffer.removeWhere((p, _) => !pairs.contains(p));
    final parent = _parent;
    if (parent == null) return;
    final k = '$parent|${_belowKey(list)}';
    if (_sentBelow != k) {
      _sentBelow = k;
      _sendJoin(parent, kTreeUpdate);
    }
  }

  void _drop(String fromHex, ControlRecord r) =>
      _log('${r.type.name} from ${_s(fromHex)} dropped — not well-formed or '
          'for another participant list');

  void _log(String line) => log?.call(line);

  static String _s(String hex) => hex.length > 8 ? hex.substring(0, 8) : hex;
}

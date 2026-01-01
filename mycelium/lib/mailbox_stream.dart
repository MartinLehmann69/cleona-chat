/// Lane 2 for one identity (§9.4, §17.6): stream an object to a contact
/// through a volunteer, join an offered stream. The seam P3b calls.
///
/// A separate file like `mailbox_bulk.dart`: the line budget of
/// `mailbox.dart`. It gets by with the public side of [Mailbox] and
/// [HostStreamOn.stream].
///
/// What is NOT here: sending the announcement and the STREAM_OFFER. Both are
/// ordinary sealed messages (§4.3, §9.4, §17.6) — the layer above sends them
/// like text. The offer's bytes come from [MailboxStream.streamSend]'s
/// `offer` callback; the recipient passes them to [MailboxStream.streamJoin].
/// Consent (§24.4.5) is asked before, by the app.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:mycelium/card_address.dart';
import 'package:mycelium/host_stream.dart';
import 'package:mycelium/mailbox.dart';
import 'package:mycelium/neighbour.dart';
import 'package:mycelium/neighbourhood_seat.dart' show reachableNeighbour;
import 'package:mycelium/stream_frame.dart';
import 'package:mycelium/stream_receive.dart';
import 'package:mycelium/stream_send.dart';

extension MailboxStream on Mailbox {
  bool _public(NeighbourAddress a) => node.neighbourhood.openNetwork(a.address);

  bool _usable(NeighbourAddress a) =>
      a.confirmedEver && _public(a) && node.speaks(a.address);

  bool _dual(Neighbour n) =>
      n.addresses.any((a) => a.confirmedEver && _public(a) &&
          a.address.type == InternetAddressType.IPv4) &&
      n.addresses.any((a) => a.confirmedEver && _public(a) &&
          a.address.type == InternetAddressType.IPv6);

  /// Volunteer candidates in the order of §17.6 "two rings", translated to
  /// 4.2: ring 1 the own fixed neighbours (§5.2; devices of contacts, the
  /// ask adds no metadata a fixed neighbour does not already have, RL-1),
  /// ring 2 every other neighbour — both only with evidenced reachability
  /// (§11.8a). Dual-stack first within a ring. Whether a candidate is
  /// always-on is learned from its answer: a phone refuses and the sender
  /// moves on (one 37 B ask).
  List<CardAddress> streamCandidates() {
    final hood = node.neighbourhood;
    final out = <CardAddress>[];
    void ring(Iterable<Neighbour> ns) {
      final ok = ns
          .where((n) => reachableNeighbour(n, _public) && n.addresses.any(_usable))
          .toList();
      for (final n in [...ok.where(_dual), ...ok.where((n) => !_dual(n))]) {
        final c = n.addresses.firstWhere(_usable).asCardAddress;
        if (!out.any((x) => x.equal(c))) out.add(c);
      }
    }

    ring(hood.fixedNeighbours);
    ring(hood.all);
    return out;
  }

  /// The addresses an offer names for the volunteer at [asked]: [asked],
  /// and its confirmed public address of the other family if it has one —
  /// so that a recipient of either family can join.
  List<CardAddress> streamVolunteerAddresses(CardAddress asked) {
    final out = [asked];
    for (final n in node.neighbourhood.all) {
      if (!n.knows(asked)) continue;
      for (final a in n.addresses) {
        final c = a.asCardAddress;
        if (a.confirmedEver && _public(a) && c.kind != asked.kind) {
          out.add(c);
          break;
        }
      }
      break;
    }
    return out;
  }

  /// Streams [object] (sealed under [transferKey], the `K_T` of the
  /// announcement) through a volunteer from [streamCandidates]. [offer]
  /// receives the STREAM_OFFER bytes for the recipient ([streamOfferPack])
  /// — once, or twice if the first volunteer is lost. A result with
  /// `fallback` means: lane 3 for the stripes it names (all if `null`).
  Future<StreamResult> streamSend(Uint8List object, Uint8List transferKey,
          {required Future<void> Function(Uint8List offer) offer,
          List<CardAddress>? candidates,
          void Function(int sent, int total)? progress}) =>
      host.stream.sender.streamSend(
          object: object,
          transferKey: transferKey,
          candidates: candidates ?? streamCandidates(),
          offer: (v, cookie) => offer(streamOfferPack(
              (volunteer: streamVolunteerAddresses(v), cookie: cookie))),
          progress: progress);

  /// Joins the stream an offer names, for the object the announcement
  /// describes. Returns the transfer identifier, or `null` if the offer is
  /// unreadable or names no address of a family this node speaks.
  Uint8List? streamJoin(
    Uint8List offerBytes, {
    required Uint8List transferKey,
    required int length,
    required Uint8List sha256,
    OnStreamObject? onObject,
    OnStreamFallback? onFallback,
    OnStreamProgress? progress,
  }) {
    final o = streamOfferRead(offerBytes);
    if (o == null) return null;
    CardAddress? v;
    for (final a in o.volunteer) {
      if (node.speaks(InternetAddress.fromRawAddress(a.address))) {
        v = a;
        break;
      }
    }
    if (v == null) return null;
    return host.stream.receiver.join(
        volunteer: v,
        cookie: o.cookie,
        transferKey: transferKey,
        length: length,
        sha256: sha256,
        onObject: onObject,
        onFallback: onFallback,
        progress: progress);
  }
}

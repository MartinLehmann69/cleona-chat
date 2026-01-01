// S407 A2 — the one exception of D-34 (v4_2 §9.3, owner 08.10.2026): "an
// image whose recipient lost the pieces it kept asks the sender once for
// its missing stripes, and the sender places only those; video, audio and
// every other file stay `failed`".
//
// WHEN. Only after a stream fell back (§17.6, S407 M-2): the recipient
// named the stripes it could not decode — those the sender placed on lane 3
// — and kept the pieces of all the others on disk (S407-N4: the give-up
// names what it cannot keep). If its collection still ends `incomplete`
// AND a kept stripe is no longer on disk (lost from outside — the failed
// collection itself leaves its blocks), it asks for the stripes still
// missing; if every kept stripe is there, the holders lacked the rest and
// the image is `failed` without a request. There is no timer —
// the request goes where the collection ended, through the delivery ladder
// (§3.4) — and it goes once: the entry carries [kImageAgainKey] across a
// restart.
//
// WIRE. `MT_MEDIA_REQUEST` = tag 16 ‖ count u32 ‖ count × stripe u32.
//
// SENDER. Once per tag ([kImageAgainKey] in its sent entry): the message is
// an image and the object still lies where the transfer took it, checked
// against its SHA-256 — then a lane 3 record, announced, with `only` = the
// asked stripes: `_laneThree` places them and hands `MT_MEDIA_HOLDERS`
// over, as after a fallen-back stream. Otherwise `MT_MEDIA_ABORT`
// `senderGaveUp`, and the image is `failed` at the recipient.
//
// RECIPIENT, again. The new holder list names the holders of the lost
// stripes; the earlier ones still hold the rest, so both lists are merged
// ([_imageHoldersMerged]) and the collection starts anew. Should it end
// `incomplete` once more, the image is `failed` (§9.3 "If that fails too").
part of 'cleona_service.dart';

/// Key in the recipient's lane 2/3 entry: the stripes it named when its
/// stream gave up (S407 M-2) — exactly those the sender placed.
const String kStreamGaveUpKey = 'gaveUp';

/// Key in the entries of both ends: the one D-34 request for this tag
/// happened.
const String kImageAgainKey = 'again';

/// `MT_MEDIA_REQUEST` of [tagHex] naming [stripes].
Uint8List imageAgainPack(String tagHex, List<int> stripes) {
  final b = Uint8List(kTagLength + 4 + 4 * stripes.length)
    ..setRange(0, kTagLength, hexToBytes(tagHex));
  final d = ByteData.sublistView(b)
    ..setUint32(kTagLength, stripes.length, Endian.big);
  for (var i = 0; i < stripes.length; i++) {
    d.setUint32(kTagLength + 4 + 4 * i, stripes[i], Endian.big);
  }
  return b;
}

/// The tag and stripes of a request; `null` for a payload of another
/// shape.
(String, List<int>)? imageAgainRead(Uint8List b) {
  if (b.length < kTagLength + 4) return null;
  final d = ByteData.sublistView(b);
  final count = d.getUint32(kTagLength, Endian.big);
  if (count == 0 || b.length != kTagLength + 4 + 4 * count) return null;
  return (
    bytesToHex(Uint8List.sublistView(b, 0, kTagLength)),
    [for (var i = 0; i < count; i++) d.getUint32(kTagLength + 4 + 4 * i, Endian.big)],
  );
}

extension CleonaServiceImageAgain on CleonaService {
  /// At the recipient, where the collection of [key] ended without an
  /// object ([why]). `true` when the request went out — the entry stays and
  /// the image keeps waiting; `false` when the file fails as before.
  bool _imageAskAgain(String key, Map<String, dynamic> e, String why) {
    final mime = e['mime'] as String?;
    if (mime == null || !mime.startsWith('image/')) return false;
    if (e[kImageAgainKey] == true) return false; // once (§9.3)
    final named = (e[kStreamGaveUpKey] as List?)?.cast<int>().toSet();
    if (named == null) return false; // no stream fell back: nothing was kept
    if (_collectionFailureReason(why).$1 != FailureReason.incomplete) {
      return false;
    }
    final a = bulkAnnounceUnpack(hexToBytes(e['announce'] as String));
    if (a == null) return false;
    final total = mycelium.stripeNumber(a.length);
    // The failed collection left what it opened on disk (S407-N4): whether
    // the kept pieces are lost is measured there, not assumed. Kept stripes
    // all there — the holders lacked the rest: no request, `failed`.
    final p = myceliumMailbox;
    if (p == null) return false;
    final held = p.bulkCollector.held(hexToBytes(key));
    if (!List.generate(total, (s) => s)
        .any((s) => !named.contains(s) && !held.contains(s))) {
      return false;
    }
    // The stripes still missing, and only those (selective, like `0x54`).
    final lost = [
      for (var s = 0; s < total; s++)
        if (!held.contains(s)) s,
    ];
    final from = e['from'] as String;
    final c = _contacts[from];
    if (lost.isEmpty || c == null) return false;
    e[kImageAgainKey] = true;
    _bulkIncomingPut(key, e);
    final msgId = e['msg'] as String;
    _log.info('[E2E media-image-again-ask] msgId=${msgId.substring(0, 8)} '
        '${lost.length} of $total stripes — $why');
    unawaited(sendToUser(
      recipientUserId: c.nodeId,
      messageType: proto.MessageType.MT_MEDIA_REQUEST,
      payload: imageAgainPack(key, lost),
    ).then((ok) {
      if (ok) return;
      _log.warn('[E2E media-image-again-ask] msgId=${msgId.substring(0, 8)} '
          'not handed to the delivery layer');
      // Asked is asked: this ends the image the way D-34 says.
      bulkCollectionFailed(hexToBytes(key), why);
    }));
    return true;
  }

  /// The holder list after the request: the new holders first (they hold
  /// the lost stripes), then the earlier ones, at most [kHoldersAtMost].
  Uint8List _imageHoldersMerged(BulkAnnouncement was, BulkAnnouncement now) {
    final seen = <String>{};
    final holders = [
      for (final h in [...now.holders, ...was.holders])
        if (seen.add('$h')) h,
    ];
    return bulkAnnouncePack(
        transferKey: now.transferKey,
        length: now.length,
        sha256: now.sha256,
        holders: holders.take(kHoldersAtMost).toList(),
        preview: was.preview);
  }

  /// `MT_MEDIA_REQUEST` at the sender (D-34 exception).
  void _imageAgainReceived(HarvestEvent event) {
    final from = event.senderUserId.hex;
    final asked = imageAgainRead(Uint8List.fromList(event.payload));
    if (asked == null) {
      _log.warn('[E2E media-image-again] from=${from.substring(0, 8)} '
          'dropped: ${event.payload.length} B, not a request');
      return;
    }
    final (tag, stripes) = asked;
    final s = _mediaSent[tag];
    final to = (s?['to'] as List?)?.cast<String>() ?? const <String>[];
    if (s == null || !to.contains(from)) {
      _log.info('[E2E media-image-again] from=${from.substring(0, 8)} tag '
          '${tag.substring(0, 8)}: no transfer of this party');
      return;
    }
    if (s[kImageAgainKey] == true) {
      _log.info('[E2E media-image-again] tag ${tag.substring(0, 8)}: asked '
          'before — an image is asked for once (D-34)');
      return;
    }
    s[kImageAgainKey] = true;
    _mediaSentPut(tag, s);
    final msg = _bulkMessage(s['conv'] as String, s['msg'] as String);
    final isImage = msg?.mimeType?.startsWith('image/') ?? false;
    final kt = s['kt'] as String?;
    final path = s['object'] as String?;
    Uint8List? object;
    if (isImage && kt != null && path != null && s['own'] != true) {
      object = MediaStore.instance.readAll(path);
      if (object != null &&
          bytesToHex(SodiumFFI().sha256(object)) != s['sha']) {
        object = null;
      }
    }
    final total = object == null ? 0 : mycelium.stripeNumber(object.length);
    if (msg == null || object == null || stripes.any((x) => x >= total)) {
      _log.info('[E2E media-image-again] tag ${tag.substring(0, 8)}: '
          '${isImage ? 'the image is no longer held' : 'not an image — '
              'never sent again'} (D-34)');
      _mediaAbortSend(from, tag, FailureReason.senderGaveUp);
      if (msg != null && isImage) {
        _mediaFail(msg, FailureReason.senderGaveUp,
            'asked again, but the image is no longer held');
      }
      return;
    }
    final r = <String, dynamic>{
      'conv': msg.conversationId,
      'msg': msg.id,
      'lane': 'mass',
      'kt': kt,
      'object': path,
      'own': false,
      'sha': s['sha'],
      'announced': true,
      'meta': base64Encode(proto.ContentMetadata().writeToBuffer()),
      'only': ([...stripes]..sort()),
      'at': DateTime.now().millisecondsSinceEpoch,
    };
    _transferRecordPut(r);
    _log.info('[E2E media-image-again] msgId=${msg.id.substring(0, 8)} '
        'places ${stripes.length} of $total stripes again (D-34)');
    _transfersRunning.add(msg.id);
    unawaited(_laneThree(msg, object, r)
        .whenComplete(() => _transfersRunning.remove(msg.id)));
  }
}

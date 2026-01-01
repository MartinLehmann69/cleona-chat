// D-46 — the app on the mirror of a call signal to the other own devices
// (V4.2 §14.7, §17.2).
//
// WHERE A SIBLING IS. "Every own-line deposit carries, sealed, the depositing
// device's fixed neighbours and its segment addresses — the way a message
// carries them to a contact (§9.2) — so that a device knows where its
// siblings are reachable; a change of fixed neighbours with no deposit
// pending costs one deposit per other own device" (§14.7). They ride in the
// twin-sync envelope (fields 7 and 8), which the own line seals; this device
// keeps the last ones per DeviceID with its device records and hands them to
// the delivery layer (`mycelium/lib/mailbox_own_signal.dart`).

part of 'cleona_service.dart';

extension CleonaServiceOwnRing on CleonaService {
  /// Where THIS device is reachable, in the wire form of the twin-sync
  /// envelope — `null` before the mailbox is attached.
  ({Uint8List neighbours, Uint8List segment})? _ownWhereWires() {
    final p = myceliumMailbox;
    if (p == null) return null;
    final here = mycelium.MailboxOwnSignal(p).ownWhereHere();
    return (
      neighbours: mycelium.ownWhereWire(here.neighbours),
      segment: mycelium.ownWhereWire(here.segment),
    );
  }

  /// The depositing device [device] (already checked to be in the own set)
  /// named where it is in [envelope]: kept with its record and handed to the
  /// delivery layer. A deposit without the fields (a 4.2.3 device, or one
  /// that knew no neighbour yet) changes nothing.
  void _ownWhereFrom(Uint8List device, proto.TwinSyncEnvelope envelope) {
    final record = _devices[bytesToHex(device)];
    if (record == null || record.isThisDevice) return;
    final n = Uint8List.fromList(envelope.neighbours);
    final s = Uint8List.fromList(envelope.segmentAddresses);
    if (mycelium.ownWhereRead(n).isEmpty && mycelium.ownWhereRead(s).isEmpty) {
      return;
    }
    final nHex = bytesToHex(n);
    final sHex = bytesToHex(s);
    if (record.whereNeighboursHex == nHex && record.whereSegmentHex == sHex) {
      return;
    }
    record
      ..whereNeighboursHex = nHex
      ..whereSegmentHex = sHex;
    _saveDevices();
    _ownWhereHand(device, record);
    _log.info('own line: device ${CleonaService._hexShort(device)} is at '
        '${mycelium.ownWhereRead(s).length} segment address(es), '
        '${mycelium.ownWhereRead(n).length} fixed neighbour(s) (§14.7)');
  }

  /// Hands what [record] keeps of where it is to the delivery layer.
  void _ownWhereHand(Uint8List device, DeviceRecord record) {
    final p = myceliumMailbox;
    if (p == null) return;
    final n = record.whereNeighboursHex;
    final s = record.whereSegmentHex;
    if (n == null && s == null) return;
    mycelium.MailboxOwnSignal(p).ownWhereTake(device, (
      neighbours: n == null ? const [] : mycelium.ownWhereRead(hexToBytes(n)),
      segment: s == null ? const [] : mycelium.ownWhereRead(hexToBytes(s)),
    ));
  }

  /// §17.2, D-46: THIS device received the call signal [content] (a contact's
  /// or a group pair's frame, delivery identifier [identifier]) — it mirrors
  /// it at once to each other own device as Type 18 `DELIVERY_MIRROR`, on
  /// steps 1 and 3 only, under the own-device code (§14.7). Every signal the
  /// caller sends to the identity for a call reaches this device the same
  /// way, so it keeps mirroring them until the call has ended. The mirror
  /// carries the contact delivery's identifier: a device that meets the
  /// same delivery both directly and mirrored takes it once (§20.2). It is
  /// not acknowledged to the caller (twin sync, §9.2); the mirrored device
  /// answers the caller directly.
  void _ownCallMirror(Uint8List content, Uint8List identifier) {
    final p = myceliumMailbox;
    if (p == null || _devices.length <= 1) return;
    final syncId = SodiumFFI().randomBytes(16);
    // Our own sync is never processed here again.
    _processedSyncIds[bytesToHex(syncId)] =
        DateTime.now().millisecondsSinceEpoch;
    final envelope = buildTwinSyncEnvelope(
      syncId: syncId,
      deviceId: hexToBytes(_localDeviceId),
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      syncType: proto.TwinSyncType.DELIVERY_MIRROR,
      payload: content,
      deliveryId: identifier,
      where: _ownWhereWires(),
    );
    final frame = _innerFrame(
      recipientUserId: identity.userId,
      senderUserId: identity.userId,
      messageId: SodiumFFI().randomBytes(16),
      messageType: proto.MessageType.MT_TWIN_SYNC,
      payload: envelope,
    );
    final sent = mycelium.MailboxOwnSignal(p)
        .ownSignal(Uint8List.fromList(frame.writeToBuffer()));
    _log.event('mycelium MIRROR call signal to $sent own device(s) — '
        'steps 1 and 3 only (§17.2, D-46)');
  }

  /// At attachment and at every change of the device set: the delivery layer
  /// learns where the other own devices were last, and this device watches
  /// its own fixed neighbours — a change costs one deposit per other own
  /// device (§14.7), the device announcement (Type 9), which carries the new
  /// ones like every own-line deposit.
  void _ownWhereSync() {
    final p = myceliumMailbox;
    if (p == null) return;
    for (final d in _devices.values) {
      if (d.isThisDevice) continue;
      final id = _ownLineDeviceId(d.deviceId);
      if (id != null) _ownWhereHand(id, d);
    }
    mycelium.MailboxOwnSignal(p).ownWhereWatch(() {
      _log.info('own line: the fixed neighbours of this device changed — '
          'one deposit per other own device (§14.7)');
      _sendTwinAnnounce();
    });
  }
}

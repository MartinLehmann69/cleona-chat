// Name, description and image of a group or private channel (v4_2 §16.2.2
// "Settings (name, description, image, posting policy, message expiry) are
// changed by the owner or admin", "An invitation contains the group ID,
// name, optionally an image and description"; D-21; S407 group profile,
// report `mycelium/berichte/S407-GRUPPENPROFIL.md`).
//
// WHAT HAPPENS WHERE:
//  * The owner or an admin changes them ([CleonaService.updateGroupProfile]).
//    The change is a settings change of §16.2.2: `ChatConfigUpdate` with
//    `profile`, carrying only the fields that changed, one 1:1 delivery to
//    every member that has shown the capability [kCapGroupProfile]
//    (`CapabilityNotice`, §16.2.5) — over the pair it holds with that
//    member, as every settings change.
//  * A member that has not shown it gets nothing now and is noted in
//    `profileOwed` of the device that made the change. Its capability
//    notice — sent with its acceptance of an invitation and after a role
//    change (§16.2.5) — brings it the whole profile from that device
//    ([_profileOwedNotice]); so does a member invited before the change.
//  * A v4.2.3 device (checked on `398a6e40`) never shows the capability. It
//    reads `ChatConfigUpdate` fields 1–9 only and would take the settings
//    the update carries; it takes name, description and image from the next
//    invitation or complete member list it reads (`GroupInvite` fields
//    2/5/6, `ChannelInvite` 2/6/7), which carry them since S407.
//  * The bounds are those of the profile update (§15.8): description ≤ 500
//    characters, image ≤ 64 KB ([kGroupDescriptionAtMost],
//    [kGroupPictureAtMost]); a change beyond them is refused on both sides.
//  * No repetition, no deadline: the transport carries each delivery
//    (§11.3a).

part of 'cleona_service.dart';

extension CleonaServiceGroupProfile on CleonaService {
  /// Whether [hex] reads a change of name, description and image.
  bool _takesGroupProfile(String hex) {
    _skLoadAll();
    return (_capabilities[hex]?.$1 ?? 0) & kCapGroupProfile != 0;
  }

  /// The change of [CleonaService.updateGroupProfile] — see there.
  Future<bool> _groupProfileUpdate(String id,
      {String? name,
      String? description,
      bool setPicture = false,
      String? pictureBase64}) async {
    final g = _groups[id];
    final c = g == null ? _channels[id] : null;
    if (g == null && (c == null || c.isPublic)) return false;
    final may = g != null
        ? _hasGroupPermission(g, 'config')
        : _hasChannelPermission(c!, 'config');
    if (!may) {
      _log.warn('group profile ${id.substring(0, 8)}: not owner or admin');
      return false;
    }
    final heldName = g != null ? g.name : c!.name;
    final heldAbout = g != null ? g.description : c!.description;
    final heldPicture = g != null ? g.pictureBase64 : c!.pictureBase64;
    final change = proto.GroupProfile();
    if (name != null) {
      final t = name.trim();
      if (t.isEmpty) return false;
      if (t != heldName) change.name = t;
    }
    if (description != null) {
      final t = description.trim();
      if (t.length > kGroupDescriptionAtMost) {
        _log.warn('group profile ${id.substring(0, 8)}: description of '
            '${t.length} characters (at most $kGroupDescriptionAtMost)');
        return false;
      }
      if (t != (heldAbout ?? '')) change.description = t;
    }
    if (setPicture) {
      final bytes = _pictureBytes(pictureBase64);
      if (pictureBase64 != null && pictureBase64.isNotEmpty && bytes == null) {
        return false;
      }
      if (bytes != null && bytes.length > kGroupPictureAtMost) {
        _log.warn('group profile ${id.substring(0, 8)}: image of '
            '${bytes.length} B (at most $kGroupPictureAtMost B)');
        return false;
      }
      if (bytes == null) {
        if (heldPicture != null) change.pictureRemoved = true;
      } else if (base64Encode(bytes) != heldPicture) {
        change.picture = bytes;
      }
    }
    if (!change.hasName() &&
        !change.hasDescription() &&
        !change.hasPicture() &&
        !change.pictureRemoved) {
      return true;
    }
    _groupProfileApply(id, change);

    final payload = _groupProfileBytes(id, change);
    final members = g?.members.keys ?? c!.members.keys;
    final owed = g?.profileOwed ?? c!.profileOwed;
    var sent = 0;
    for (final hex in members.toList()) {
      if (hex == identity.userIdHex) continue;
      if (!_takesGroupProfile(hex)) {
        owed.add(hex);
        continue;
      }
      sent++;
      _detachedSend('MT_CHAT_CONFIG_UPDATE', sendToUser(
        recipientUserId: hexToBytes(hex),
        messageType: proto.MessageType.MT_CHAT_CONFIG_UPDATE,
        payload: payload,
        groupId: hexToBytes(id),
      ));
    }
    owed.removeWhere((h) => !members.contains(h));
    if (g != null) {
      _saveGroups();
      _sendTwinGroupCreated(g);
    } else {
      _saveChannels();
      _sendTwinChannelJoined(c!);
    }
    _log.info('group profile ${id.substring(0, 8)} changed '
        '(${[
      if (change.hasName()) 'name',
      if (change.hasDescription()) 'description',
      if (change.hasPicture()) 'image ${change.picture.length} B',
      if (change.pictureRemoved) 'image removed',
    ].join(', ')}): to $sent member(s); ${owed.length} owed until they '
        'show the capability');
    return true;
  }

  /// The settings change that carries [change]. The settings in force ride
  /// along (proto comment on `profile`): a device that does not read
  /// `profile` would only take them again.
  Uint8List _groupProfileBytes(String id, proto.GroupProfile change) {
    final g = _groups[id];
    final config = conversations[id]?.config ?? ChatConfig();
    final carrier = proto.ChatConfigUpdate.fromBuffer(g != null
        ? _groupConfigBytes(g, config)
        : _channelConfigBytes(id, config))
      ..profile = change;
    return Uint8List.fromList(carrier.writeToBuffer());
  }

  /// `ChatConfigUpdate` with `profile` from [senderHex], whose authority
  /// over [id] the caller has checked against this device's state.
  void _groupProfileReceived(
      String id, String senderHex, proto.GroupProfile p) {
    if (p.hasName() && p.name.trim().isEmpty ||
        p.hasDescription() && p.description.length > kGroupDescriptionAtMost ||
        p.hasPicture() && p.picture.length > kGroupPictureAtMost) {
      _log.warn('group profile ${id.substring(0, 8)} from '
          '${senderHex.substring(0, 8)}: beyond the bounds — refused');
      return;
    }
    _groupProfileApply(id, p);
    final g = _groups[id];
    if (g != null) {
      _saveGroups();
    } else {
      _saveChannels();
    }
    _log.info('group profile ${id.substring(0, 8)} changed by '
        '${senderHex.substring(0, 8)}');
  }

  /// Takes the fields present in [p] into the group or channel [id] and its
  /// conversation; the caller saves the group or channel.
  void _groupProfileApply(String id, proto.GroupProfile p) {
    final g = _groups[id];
    final c = _channels[id];
    if (g == null && c == null) return;
    final name = p.hasName() ? p.name.trim() : null;
    final hasPicture = p.hasPicture() || p.pictureRemoved;
    final picture = p.hasPicture() ? base64Encode(p.picture) : null;
    if (g != null) {
      if (name != null) g.name = name;
      if (p.hasDescription()) {
        g.description = p.description.isEmpty ? null : p.description;
      }
      if (hasPicture) g.pictureBase64 = picture;
    } else {
      if (name != null) c!.name = name;
      if (p.hasDescription()) {
        c!.description = p.description.isEmpty ? null : p.description;
      }
      if (hasPicture) c!.pictureBase64 = picture;
    }
    final conv = conversations[id];
    if (conv != null) {
      if (name != null) conv.displayName = name;
      if (hasPicture) conv.profilePictureBase64 = picture;
      _saveConversations();
    }
    onStateChanged?.call();
  }

  /// §16.2.5 capability notice from [fromHex]: where a change of the
  /// profile made here could not reach it, it now shows the capability and
  /// is told the whole profile, one 1:1 delivery per group or channel.
  void _profileOwedNotice(String fromHex) {
    if (!_takesGroupProfile(fromHex)) return;
    void tell(String id, String name, String? about, String? pic) {
      final full = proto.GroupProfile()
        ..name = name
        ..description = about ?? '';
      final bytes = _pictureBytes(pic);
      if (bytes != null) {
        full.picture = bytes;
      } else {
        full.pictureRemoved = true;
      }
      _detachedSend('MT_CHAT_CONFIG_UPDATE', sendToUser(
        recipientUserId: hexToBytes(fromHex),
        messageType: proto.MessageType.MT_CHAT_CONFIG_UPDATE,
        payload: _groupProfileBytes(id, full),
        groupId: hexToBytes(id),
      ));
      _log.info('group profile ${id.substring(0, 8)} told to '
          '${fromHex.substring(0, 8)}, which showed the capability now');
    }

    for (final g in _groups.values) {
      if (!g.profileOwed.remove(fromHex)) continue;
      _saveGroups();
      if (g.members.containsKey(fromHex)) {
        tell(g.groupIdHex, g.name, g.description, g.pictureBase64);
      }
    }
    for (final c in _channels.values) {
      if (!c.profileOwed.remove(fromHex)) continue;
      _saveChannels();
      if (c.members.containsKey(fromHex)) {
        tell(c.channelIdHex, c.name, c.description, c.pictureBase64);
      }
    }
  }
}

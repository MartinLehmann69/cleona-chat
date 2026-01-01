// Discussion and announcement mode of a group (v4_2 §16.2.2 "The owner
// decides whether members may post (discussion vs. announcement mode).
// Settings (name, description, image, posting policy, message expiry) are
// changed by the owner or admin."; §16.2.5 "Authors", "Edits, deletions,
// reactions and votes"; D-21; S407 group list, report
// `mycelium/berichte/S407-GRUPPENLISTE.md`).
//
// WHAT HAPPENS WHERE:
//  * The setting is part of the group's chat settings (`ChatConfig.
//    announcementOnly`) and travels with them (`CHAT_CONFIG_UPDATE`, field
//    `announcement_only` with explicit presence); a member that joins later
//    is told them at its joining ([_settingsToNewcomer]).
//  * A member does not post: the send paths refuse ([_groupMayPost]), the
//    interface locks the input field, and on receipt a member's post is
//    discarded in front of the dispatcher ([_groupAnnouncementRefuses]) —
//    on pairwise legs and on the shared key alike, since a post on the
//    shared key reaches the same dispatcher.
//  * On the shared key a member is no author: it gets no certificate
//    (`_skMayPost`), its post is refused at the check, and its reaction and
//    vote go 1:1 to the owner (the poll's creator for a vote), which
//    deposits the totals and the tally ([_groupReactsViaOwner],
//    `cleona_service_channel_reactions.dart`, `PollService`).
//  * Reactions, votes, edits and deletions of own earlier posts are no
//    posts; on pairwise legs members keep them.
//
// MIXED OPERATION (checked on `398a6e40`): a v4.2.3 device reads the
// `ChatConfigUpdate` without the unknown field 10 and keeps working; it does
// not know the mode, so a 4.2.3 member still posts, and every newer member
// discards that post — the 4.2.3 member sees its own post, nobody else
// does. A 4.2.3 admin's settings change carries no field 10 and leaves the
// mode as it was.

part of 'cleona_service.dart';

/// The kinds that are a post of their own (§16.2.2 "The group types"):
/// group post, file, voice message, poll, calendar entry of a group event.
const Set<proto.MessageType> kGroupPostKinds = {
  proto.MessageType.MT_TEXT,
  proto.MessageType.MT_REPLY,
  proto.MessageType.MT_MEDIA_INLINE,
  proto.MessageType.MT_MEDIA_ANNOUNCE,
  proto.MessageType.MT_VOICE_MESSAGE,
  proto.MessageType.MT_POLL_CREATE,
  proto.MessageType.MT_CALENDAR_INVITE,
};

extension CleonaServiceGroupAnnouncement on CleonaService {
  /// Whether the group [gid] runs in announcement mode on this device.
  bool _groupAnnouncement(String gid) =>
      _groups.containsKey(gid) &&
      (conversations[gid]?.config.announcementOnly ?? false);

  /// Whether [hex] may post into the group [gid] (§16.2.2): every member in
  /// discussion mode, the owner and the admins in announcement mode.
  bool _groupMayPost(String gid, String hex) {
    final role = _groups[gid]?.members[hex]?.role;
    if (role == null) return false;
    if (!_groupAnnouncement(gid)) return true;
    return role == 'owner' || role == 'admin';
  }

  /// §16.2.5: in a group in announcement mode on the shared key a member's
  /// reaction and vote go 1:1 to the owner, which deposits the totals.
  bool _groupReactsViaOwner(String gid) =>
      _groupAnnouncement(gid) && _skOn(gid);

  /// `true`: [event] is a member's post into a group in announcement mode
  /// — discarded, as a post from a non-member is (§16.2.2).
  bool _groupAnnouncementRefuses(HarvestEvent event) {
    if (!kGroupPostKinds.contains(event.type)) return false;
    final named = event.groupId;
    if (named == null) return false;
    final gid = bytesToHex(named);
    if (!_groupAnnouncement(gid)) return false;
    final sender = event.senderUserId.hex;
    final role = _groups[gid]?.members[sender]?.role;
    // A non-member is the membership gate's (GM-2) to discard.
    if (role == null || role == 'owner' || role == 'admin') return false;
    _log.info('${event.type.name} from the member '
        '${sender.length > 8 ? sender.substring(0, 8) : sender} in a group in '
        'announcement mode — discarded (§16.2.2)');
    return true;
  }

  /// The mode of [gid] changed. [recordedHere]: this owner or admin
  /// switched it.
  ///
  /// §16.2.5 "A member that may not post holds no certified author key": on
  /// the shared key, switching to announcement mode draws the next
  /// generation here — its certificates go to the owner and the admins only
  /// (`_skGive` asks `_skMayPost`), so a member holds none for the
  /// generation in force (one 1:1 delivery per member served, as after a
  /// leaving). Switching back, a member that may post again names an author
  /// key to the owner and the admins (§16.2.5 "Authors").
  void _groupAnnouncementChanged(String gid, {bool recordedHere = false}) {
    _log.info('group ${gid.substring(0, 8)}: '
        '${_groupAnnouncement(gid) ? 'announcement' : 'discussion'} mode');
    if (recordedHere && _groupAnnouncement(gid) && _skOn(gid) && _skRecords(gid)) {
      unawaited(_skNewGeneration(gid));
      return;
    }
    if (!_skOn(gid) || !_skMayPost(gid, identity.userIdHex)) return;
    final gen = _sk(gid)?.current;
    if (gen != null && gen.certificate == null) unawaited(_skAuthorAsk(gid));
  }

  /// §16.2.2, §21.5.3/§21.5.4: [toHex] joined the group or private channel
  /// [convId]; it is told the settings in force — expiry, downloads,
  /// forwarding, edit window, read receipts, typing indicators and, in a
  /// group, the announcement mode — in one 1:1 delivery, since an invitation
  /// does not carry them and its conversation starts on the defaults. On the
  /// defaults nothing is sent (working rule 5: every message counts).
  ///
  /// Until S407 (group settings) only the announcement mode went, so a
  /// newcomer kept no expiry and the other defaults while every other member
  /// held the owner's settings (`smoke_group_settings_newcomer_run`).
  void _settingsToNewcomer(String convId, String toHex) {
    final conv = conversations[convId];
    if (conv == null) return;
    final c = conv.config;
    final d = ChatConfig();
    if (c.allowDownloads == d.allowDownloads &&
        c.allowForwarding == d.allowForwarding &&
        c.expiryDurationMs == d.expiryDurationMs &&
        c.editWindowMs == d.editWindowMs &&
        c.readReceipts == d.readReceipts &&
        c.typingIndicators == d.typingIndicators &&
        c.announcementOnly == d.announcementOnly) {
      return;
    }
    final g = _groups[convId];
    final payload = g != null
        ? _groupConfigBytes(g, c)
        : _channelConfigBytes(convId, c);
    _detachedSend('MT_CHAT_CONFIG_UPDATE', sendToUser(
      recipientUserId: hexToBytes(toHex),
      messageType: proto.MessageType.MT_CHAT_CONFIG_UPDATE,
      payload: payload,
      groupId: hexToBytes(convId),
    ));
  }
}

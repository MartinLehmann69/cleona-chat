//
//  Generated code. Do not modify.
//  source: transport.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class CompressionType extends $pb.ProtobufEnum {
  static const CompressionType NONE = CompressionType._(0, _omitEnumNames ? '' : 'NONE');
  static const CompressionType ZSTD = CompressionType._(1, _omitEnumNames ? '' : 'ZSTD');

  static const $core.List<CompressionType> values = <CompressionType> [
    NONE,
    ZSTD,
  ];

  static final $core.Map<$core.int, CompressionType> _byValue = $pb.ProtobufEnum.initByValue(values);
  static CompressionType? valueOf($core.int value) => _byValue[value];

  const CompressionType._($core.int v, $core.String n) : super(v, n);
}

class NatType extends $pb.ProtobufEnum {
  static const NatType NAT_UNKNOWN = NatType._(0, _omitEnumNames ? '' : 'NAT_UNKNOWN');
  static const NatType NAT_PUBLIC = NatType._(1, _omitEnumNames ? '' : 'NAT_PUBLIC');
  static const NatType NAT_FULL_CONE = NatType._(2, _omitEnumNames ? '' : 'NAT_FULL_CONE');
  static const NatType NAT_SYMMETRIC = NatType._(3, _omitEnumNames ? '' : 'NAT_SYMMETRIC');

  static const $core.List<NatType> values = <NatType> [
    NAT_UNKNOWN,
    NAT_PUBLIC,
    NAT_FULL_CONE,
    NAT_SYMMETRIC,
  ];

  static final $core.Map<$core.int, NatType> _byValue = $pb.ProtobufEnum.initByValue(values);
  static NatType? valueOf($core.int value) => _byValue[value];

  const NatType._($core.int v, $core.String n) : super(v, n);
}

class ConnectionTypeProto extends $pb.ProtobufEnum {
  static const ConnectionTypeProto CT_LAN_SAME_SUBNET = ConnectionTypeProto._(0, _omitEnumNames ? '' : 'CT_LAN_SAME_SUBNET');
  static const ConnectionTypeProto CT_LAN_OTHER_SUBNET = ConnectionTypeProto._(1, _omitEnumNames ? '' : 'CT_LAN_OTHER_SUBNET');
  static const ConnectionTypeProto CT_WIFI_DIRECT = ConnectionTypeProto._(2, _omitEnumNames ? '' : 'CT_WIFI_DIRECT');
  static const ConnectionTypeProto CT_PUBLIC_UDP = ConnectionTypeProto._(3, _omitEnumNames ? '' : 'CT_PUBLIC_UDP');
  static const ConnectionTypeProto CT_HOLE_PUNCH = ConnectionTypeProto._(4, _omitEnumNames ? '' : 'CT_HOLE_PUNCH');
  static const ConnectionTypeProto CT_RELAY = ConnectionTypeProto._(5, _omitEnumNames ? '' : 'CT_RELAY');
  static const ConnectionTypeProto CT_MOBILE = ConnectionTypeProto._(6, _omitEnumNames ? '' : 'CT_MOBILE');
  static const ConnectionTypeProto CT_MOBILE_RELAY = ConnectionTypeProto._(7, _omitEnumNames ? '' : 'CT_MOBILE_RELAY');

  static const $core.List<ConnectionTypeProto> values = <ConnectionTypeProto> [
    CT_LAN_SAME_SUBNET,
    CT_LAN_OTHER_SUBNET,
    CT_WIFI_DIRECT,
    CT_PUBLIC_UDP,
    CT_HOLE_PUNCH,
    CT_RELAY,
    CT_MOBILE,
    CT_MOBILE_RELAY,
  ];

  static final $core.Map<$core.int, ConnectionTypeProto> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ConnectionTypeProto? valueOf($core.int value) => _byValue[value];

  const ConnectionTypeProto._($core.int v, $core.String n) : super(v, n);
}

class PayloadType extends $pb.ProtobufEnum {
  static const PayloadType PAYLOAD_APPLICATION_FRAME = PayloadType._(0, _omitEnumNames ? '' : 'PAYLOAD_APPLICATION_FRAME');
  static const PayloadType PAYLOAD_ONION_LAYER = PayloadType._(1, _omitEnumNames ? '' : 'PAYLOAD_ONION_LAYER');

  static const $core.List<PayloadType> values = <PayloadType> [
    PAYLOAD_APPLICATION_FRAME,
    PAYLOAD_ONION_LAYER,
  ];

  static final $core.Map<$core.int, PayloadType> _byValue = $pb.ProtobufEnum.initByValue(values);
  static PayloadType? valueOf($core.int value) => _byValue[value];

  const PayloadType._($core.int v, $core.String n) : super(v, n);
}

///  ── Infrastructure frame V3 — S368 REMOVED ──────────────────────
///
///  Here stood `message InfrastructureFrameV3` (device-addressed inner layer,
///  §2.3.5) with the fields version(1), recipient_device_id(2),
///  sender_device_id(3), timestamp_ms(4), message_id(5), message_type(6),
///  payload(7), in_reply_to(8).
///
///  MEASURED before it fell: its FOUR receiving sites
///    handleChannelIndexExchangeInfra         (channel_moderation_service.dart)
///    handleIncomingFirstContactRequest       (cleona_service_contact_request.dart)
///    handleIncomingKeyRotationBroadcastInfra (cleona_service_identity.dart)
///    handleIncomingRestoreBroadcastInfra     (cleona_service_restore.dart)
///  each had ZERO callers in `lib/`+`bin/`, on `s368/kompat-inventur` as
///  on `v4/knoten-host`, and the frame was constructed NOWHERE in `lib/`
///  — the only constructions were in a smoke suite.
///
///  TWO OF ITS FIELDS WERE ALREADY THE FINDING ON THEIR OWN:
///    version(1)      -- V3.0 = 1 -- never set, always 0 on the wire.
///    in_reply_to(8)  The associated paragraph was the only literally
///                    spelled-out rolling stage in the whole schema:
///                    -- The fallback is the rolling-upgrade path for peers
///                    before V3.1.159 and remains until all nodes set the field.
///                    A path for older peers — on this line
///                    there are none.
///
///  The FACTUAL reason `in_reply_to` once came about still holds and
///  therefore stands here, so that it is not lost with the frame: without a
///  correlator, two simultaneous requests of the same type to
///  the same peer swap their answers. In S280 exactly that overwrote a
///  contact trust anchor. Whoever builds a request/response pair on this
///  line again needs a correlator — but one that is
///  MANDATORY, not one with a fallback to the (peer, type) tuple.
///  ── MessageType (numbering from Appendix A.4) ───────────────────────────
///
///  CAUTION: numbers DIFFER FROM the pre-4.2 MessageType. Examples:
///    old: RESTORE_BROADCAST=13   → now: MT_RESTORE_BROADCAST=30 (reserved, S398)
///    old: TWIN_SYNC=131          → now: MT_TWIN_SYNC=180
///
///  Names carry no product version (working rule 12, S409): enum and values
///  were `MessageTypeV3` / `MTV3_*` up to 4.2.3. Only names changed; every
///  field number stays, so the wire is unchanged. The local outbox stores the
///  value NAME as text and reads an old name into the current one (D-82).
class MessageType extends $pb.ProtobufEnum {
  static const MessageType MT_TEXT = MessageType._(0, _omitEnumNames ? '' : 'MT_TEXT');
  static const MessageType MT_MEDIA_INLINE = MessageType._(1, _omitEnumNames ? '' : 'MT_MEDIA_INLINE');
  static const MessageType MT_MEDIA_ANNOUNCE = MessageType._(2, _omitEnumNames ? '' : 'MT_MEDIA_ANNOUNCE');
  static const MessageType MT_MEDIA_REQUEST = MessageType._(3, _omitEnumNames ? '' : 'MT_MEDIA_REQUEST');
  static const MessageType MT_MEDIA_CHUNK = MessageType._(4, _omitEnumNames ? '' : 'MT_MEDIA_CHUNK');
  static const MessageType MT_MEDIA_COMPLETE = MessageType._(5, _omitEnumNames ? '' : 'MT_MEDIA_COMPLETE');
  static const MessageType MT_MEDIA_REJECT = MessageType._(6, _omitEnumNames ? '' : 'MT_MEDIA_REJECT');
  static const MessageType MT_REACTION = MessageType._(7, _omitEnumNames ? '' : 'MT_REACTION');
  static const MessageType MT_REPLY = MessageType._(8, _omitEnumNames ? '' : 'MT_REPLY');
  static const MessageType MT_EDIT = MessageType._(9, _omitEnumNames ? '' : 'MT_EDIT');
  static const MessageType MT_DELETE = MessageType._(10, _omitEnumNames ? '' : 'MT_DELETE');
  static const MessageType MT_MEDIA_STREAM_REQUEST = MessageType._(11, _omitEnumNames ? '' : 'MT_MEDIA_STREAM_REQUEST');
  static const MessageType MT_MEDIA_STREAM_OFFER = MessageType._(12, _omitEnumNames ? '' : 'MT_MEDIA_STREAM_OFFER');
  static const MessageType MT_MEDIA_HOLDERS = MessageType._(13, _omitEnumNames ? '' : 'MT_MEDIA_HOLDERS');
  static const MessageType MT_MEDIA_ABORT = MessageType._(14, _omitEnumNames ? '' : 'MT_MEDIA_ABORT');
  static const MessageType MT_TYPING_INDICATOR = MessageType._(15, _omitEnumNames ? '' : 'MT_TYPING_INDICATOR');
  static const MessageType MT_READ_RECEIPT = MessageType._(16, _omitEnumNames ? '' : 'MT_READ_RECEIPT');
  static const MessageType MT_DELIVERY_RECEIPT = MessageType._(17, _omitEnumNames ? '' : 'MT_DELIVERY_RECEIPT');
  static const MessageType MT_CATCH_UP = MessageType._(18, _omitEnumNames ? '' : 'MT_CATCH_UP');
  static const MessageType MT_VOICE_MESSAGE = MessageType._(22, _omitEnumNames ? '' : 'MT_VOICE_MESSAGE');
  static const MessageType MT_IDENTITY_DELETED = MessageType._(32, _omitEnumNames ? '' : 'MT_IDENTITY_DELETED');
  static const MessageType MT_PROFILE_UPDATE = MessageType._(33, _omitEnumNames ? '' : 'MT_PROFILE_UPDATE');
  static const MessageType MT_KEY_ROTATION_BROADCAST = MessageType._(34, _omitEnumNames ? '' : 'MT_KEY_ROTATION_BROADCAST');
  static const MessageType MT_KEY_ROTATION_ACK = MessageType._(38, _omitEnumNames ? '' : 'MT_KEY_ROTATION_ACK');
  static const MessageType MT_CONTACT_REQUEST = MessageType._(40, _omitEnumNames ? '' : 'MT_CONTACT_REQUEST');
  static const MessageType MT_CONTACT_REQUEST_RESPONSE = MessageType._(41, _omitEnumNames ? '' : 'MT_CONTACT_REQUEST_RESPONSE');
  static const MessageType MT_GROUP_CREATE = MessageType._(50, _omitEnumNames ? '' : 'MT_GROUP_CREATE');
  static const MessageType MT_GROUP_INVITE = MessageType._(51, _omitEnumNames ? '' : 'MT_GROUP_INVITE');
  static const MessageType MT_GROUP_LEAVE = MessageType._(52, _omitEnumNames ? '' : 'MT_GROUP_LEAVE');
  static const MessageType MT_GROUP_KEY_UPDATE = MessageType._(53, _omitEnumNames ? '' : 'MT_GROUP_KEY_UPDATE');
  static const MessageType MT_GROUP_MEMBERSHIP_RESYNC_REQUEST = MessageType._(54, _omitEnumNames ? '' : 'MT_GROUP_MEMBERSHIP_RESYNC_REQUEST');
  static const MessageType MT_GROUP_JOIN = MessageType._(55, _omitEnumNames ? '' : 'MT_GROUP_JOIN');
  static const MessageType MT_CHANNEL_CREATE = MessageType._(60, _omitEnumNames ? '' : 'MT_CHANNEL_CREATE');
  static const MessageType MT_CHANNEL_POST = MessageType._(61, _omitEnumNames ? '' : 'MT_CHANNEL_POST');
  static const MessageType MT_CHANNEL_INVITE = MessageType._(62, _omitEnumNames ? '' : 'MT_CHANNEL_INVITE');
  static const MessageType MT_CHANNEL_LEAVE = MessageType._(63, _omitEnumNames ? '' : 'MT_CHANNEL_LEAVE');
  static const MessageType MT_CHANNEL_ROLE_UPDATE = MessageType._(64, _omitEnumNames ? '' : 'MT_CHANNEL_ROLE_UPDATE');
  static const MessageType MT_CHANNEL_BAD_BADGE_REPORT = MessageType._(65, _omitEnumNames ? '' : 'MT_CHANNEL_BAD_BADGE_REPORT');
  static const MessageType MT_CHANNEL_JURY_VOTE = MessageType._(66, _omitEnumNames ? '' : 'MT_CHANNEL_JURY_VOTE');
  static const MessageType MT_CHANNEL_MOD_DECISION = MessageType._(67, _omitEnumNames ? '' : 'MT_CHANNEL_MOD_DECISION');
  static const MessageType MT_CHANNEL_SUBSCRIBE_PROBE = MessageType._(68, _omitEnumNames ? '' : 'MT_CHANNEL_SUBSCRIBE_PROBE');
  static const MessageType MT_CALL_MISSED = MessageType._(69, _omitEnumNames ? '' : 'MT_CALL_MISSED');
  static const MessageType MT_CALL_INVITE = MessageType._(70, _omitEnumNames ? '' : 'MT_CALL_INVITE');
  static const MessageType MT_CALL_ANSWER = MessageType._(71, _omitEnumNames ? '' : 'MT_CALL_ANSWER');
  static const MessageType MT_CALL_REJECT = MessageType._(72, _omitEnumNames ? '' : 'MT_CALL_REJECT');
  static const MessageType MT_CALL_HANGUP = MessageType._(73, _omitEnumNames ? '' : 'MT_CALL_HANGUP');
  static const MessageType MT_ICE_CANDIDATE = MessageType._(74, _omitEnumNames ? '' : 'MT_ICE_CANDIDATE');
  static const MessageType MT_CALL_REJOIN = MessageType._(75, _omitEnumNames ? '' : 'MT_CALL_REJOIN');
  static const MessageType MT_CALL_AUDIO = MessageType._(76, _omitEnumNames ? '' : 'MT_CALL_AUDIO');
  static const MessageType MT_CALL_VIDEO = MessageType._(77, _omitEnumNames ? '' : 'MT_CALL_VIDEO');
  static const MessageType MT_CALL_GROUP_AUDIO = MessageType._(78, _omitEnumNames ? '' : 'MT_CALL_GROUP_AUDIO');
  static const MessageType MT_CALL_GROUP_VIDEO = MessageType._(79, _omitEnumNames ? '' : 'MT_CALL_GROUP_VIDEO');
  static const MessageType MT_CALL_GROUP_LEAVE = MessageType._(80, _omitEnumNames ? '' : 'MT_CALL_GROUP_LEAVE');
  static const MessageType MT_CALL_RTT_PING = MessageType._(82, _omitEnumNames ? '' : 'MT_CALL_RTT_PING');
  static const MessageType MT_CALL_RTT_PONG = MessageType._(83, _omitEnumNames ? '' : 'MT_CALL_RTT_PONG');
  static const MessageType MT_CALL_TREE_UPDATE = MessageType._(84, _omitEnumNames ? '' : 'MT_CALL_TREE_UPDATE');
  static const MessageType MT_CALL_KEYFRAME_REQUEST = MessageType._(85, _omitEnumNames ? '' : 'MT_CALL_KEYFRAME_REQUEST');
  static const MessageType MT_CALL_GROUP_SENDER_KEY = MessageType._(86, _omitEnumNames ? '' : 'MT_CALL_GROUP_SENDER_KEY');
  static const MessageType MT_CALL_MEDIA_STATE = MessageType._(87, _omitEnumNames ? '' : 'MT_CALL_MEDIA_STATE');
  static const MessageType MT_CALL_CANCEL_OTHERS = MessageType._(88, _omitEnumNames ? '' : 'MT_CALL_CANCEL_OTHERS');
  static const MessageType MT_CALL_RING_ACK = MessageType._(89, _omitEnumNames ? '' : 'MT_CALL_RING_ACK');
  static const MessageType MT_CHANNEL_INDEX_EXCHANGE = MessageType._(90, _omitEnumNames ? '' : 'MT_CHANNEL_INDEX_EXCHANGE');
  static const MessageType MT_CHANNEL_JOIN_REQUEST = MessageType._(91, _omitEnumNames ? '' : 'MT_CHANNEL_JOIN_REQUEST');
  static const MessageType MT_CHANNEL_REPORT = MessageType._(92, _omitEnumNames ? '' : 'MT_CHANNEL_REPORT');
  static const MessageType MT_CHANNEL_REACTION_TOTALS = MessageType._(93, _omitEnumNames ? '' : 'MT_CHANNEL_REACTION_TOTALS');
  static const MessageType MT_CHANNEL_REACTION_HANDOVER = MessageType._(94, _omitEnumNames ? '' : 'MT_CHANNEL_REACTION_HANDOVER');
  static const MessageType MT_CHANNEL_MEMBERS_CHANGE = MessageType._(95, _omitEnumNames ? '' : 'MT_CHANNEL_MEMBERS_CHANGE');
  static const MessageType MT_CAPABILITY_NOTICE = MessageType._(96, _omitEnumNames ? '' : 'MT_CAPABILITY_NOTICE');
  static const MessageType MT_SHARED_KEY = MessageType._(97, _omitEnumNames ? '' : 'MT_SHARED_KEY');
  static const MessageType MT_SHARED_KEY_AUTHOR = MessageType._(98, _omitEnumNames ? '' : 'MT_SHARED_KEY_AUTHOR');
  static const MessageType MT_GROUP_MEMBERS_CHANGE = MessageType._(99, _omitEnumNames ? '' : 'MT_GROUP_MEMBERS_CHANGE');
  static const MessageType MT_DHT_PING = MessageType._(110, _omitEnumNames ? '' : 'MT_DHT_PING');
  static const MessageType MT_DHT_PONG = MessageType._(111, _omitEnumNames ? '' : 'MT_DHT_PONG');
  static const MessageType MT_DHT_FIND_NODE = MessageType._(112, _omitEnumNames ? '' : 'MT_DHT_FIND_NODE');
  static const MessageType MT_DHT_FIND_NODE_RESPONSE = MessageType._(113, _omitEnumNames ? '' : 'MT_DHT_FIND_NODE_RESPONSE');
  static const MessageType MT_DHT_STORE = MessageType._(114, _omitEnumNames ? '' : 'MT_DHT_STORE');
  static const MessageType MT_DHT_STORE_RESPONSE = MessageType._(115, _omitEnumNames ? '' : 'MT_DHT_STORE_RESPONSE');
  static const MessageType MT_DHT_FIND_VALUE = MessageType._(116, _omitEnumNames ? '' : 'MT_DHT_FIND_VALUE');
  static const MessageType MT_DHT_FIND_VALUE_RESPONSE = MessageType._(117, _omitEnumNames ? '' : 'MT_DHT_FIND_VALUE_RESPONSE');
  static const MessageType MT_FRAGMENT_STORE = MessageType._(120, _omitEnumNames ? '' : 'MT_FRAGMENT_STORE');
  static const MessageType MT_FRAGMENT_STORE_ACK = MessageType._(121, _omitEnumNames ? '' : 'MT_FRAGMENT_STORE_ACK');
  static const MessageType MT_FRAGMENT_RETRIEVE = MessageType._(122, _omitEnumNames ? '' : 'MT_FRAGMENT_RETRIEVE');
  static const MessageType MT_FRAGMENT_RETRIEVE_RESPONSE = MessageType._(123, _omitEnumNames ? '' : 'MT_FRAGMENT_RETRIEVE_RESPONSE');
  static const MessageType MT_FRAGMENT_DELETE = MessageType._(124, _omitEnumNames ? '' : 'MT_FRAGMENT_DELETE');
  static const MessageType MT_CHAT_CONFIG_UPDATE = MessageType._(140, _omitEnumNames ? '' : 'MT_CHAT_CONFIG_UPDATE');
  static const MessageType MT_CHAT_CONFIG_RESPONSE = MessageType._(141, _omitEnumNames ? '' : 'MT_CHAT_CONFIG_RESPONSE');
  static const MessageType MT_IDENTITY_AUTH_PUBLISH = MessageType._(170, _omitEnumNames ? '' : 'MT_IDENTITY_AUTH_PUBLISH');
  static const MessageType MT_IDENTITY_AUTH_RETRIEVE = MessageType._(171, _omitEnumNames ? '' : 'MT_IDENTITY_AUTH_RETRIEVE');
  static const MessageType MT_IDENTITY_AUTH_RESPONSE = MessageType._(172, _omitEnumNames ? '' : 'MT_IDENTITY_AUTH_RESPONSE');
  static const MessageType MT_IDENTITY_LIVE_PUBLISH = MessageType._(173, _omitEnumNames ? '' : 'MT_IDENTITY_LIVE_PUBLISH');
  static const MessageType MT_IDENTITY_LIVE_RETRIEVE = MessageType._(174, _omitEnumNames ? '' : 'MT_IDENTITY_LIVE_RETRIEVE');
  static const MessageType MT_IDENTITY_LIVE_RESPONSE = MessageType._(175, _omitEnumNames ? '' : 'MT_IDENTITY_LIVE_RESPONSE');
  static const MessageType MT_TWIN_SYNC = MessageType._(180, _omitEnumNames ? '' : 'MT_TWIN_SYNC');
  static const MessageType MT_DEVICE_REVOCATION = MessageType._(183, _omitEnumNames ? '' : 'MT_DEVICE_REVOCATION');
  static const MessageType MT_ROTATION_REJECTION_ALERT = MessageType._(184, _omitEnumNames ? '' : 'MT_ROTATION_REJECTION_ALERT');
  static const MessageType MT_DEVICE_SET_ANNOUNCE = MessageType._(185, _omitEnumNames ? '' : 'MT_DEVICE_SET_ANNOUNCE');
  static const MessageType MT_CALENDAR_INVITE = MessageType._(190, _omitEnumNames ? '' : 'MT_CALENDAR_INVITE');
  static const MessageType MT_CALENDAR_RSVP = MessageType._(191, _omitEnumNames ? '' : 'MT_CALENDAR_RSVP');
  static const MessageType MT_CALENDAR_UPDATE = MessageType._(192, _omitEnumNames ? '' : 'MT_CALENDAR_UPDATE');
  static const MessageType MT_CALENDAR_DELETE = MessageType._(193, _omitEnumNames ? '' : 'MT_CALENDAR_DELETE');
  static const MessageType MT_FREE_BUSY_REQUEST = MessageType._(194, _omitEnumNames ? '' : 'MT_FREE_BUSY_REQUEST');
  static const MessageType MT_FREE_BUSY_RESPONSE = MessageType._(195, _omitEnumNames ? '' : 'MT_FREE_BUSY_RESPONSE');
  static const MessageType MT_POLL_CREATE = MessageType._(200, _omitEnumNames ? '' : 'MT_POLL_CREATE');
  static const MessageType MT_POLL_VOTE = MessageType._(201, _omitEnumNames ? '' : 'MT_POLL_VOTE');
  static const MessageType MT_POLL_VOTE_ANONYMOUS = MessageType._(202, _omitEnumNames ? '' : 'MT_POLL_VOTE_ANONYMOUS');
  static const MessageType MT_POLL_UPDATE = MessageType._(203, _omitEnumNames ? '' : 'MT_POLL_UPDATE');
  static const MessageType MT_POLL_SNAPSHOT = MessageType._(204, _omitEnumNames ? '' : 'MT_POLL_SNAPSHOT');
  static const MessageType MT_POLL_REVOKE = MessageType._(205, _omitEnumNames ? '' : 'MT_POLL_REVOKE');
  static const MessageType MT_WHITEBOARD_STROKE = MessageType._(210, _omitEnumNames ? '' : 'MT_WHITEBOARD_STROKE');
  static const MessageType MT_WHITEBOARD_PAGE = MessageType._(211, _omitEnumNames ? '' : 'MT_WHITEBOARD_PAGE');
  static const MessageType MT_FILE_EXCHANGE = MessageType._(212, _omitEnumNames ? '' : 'MT_FILE_EXCHANGE');
  static const MessageType MT_CLIPBOARD_EXCHANGE = MessageType._(213, _omitEnumNames ? '' : 'MT_CLIPBOARD_EXCHANGE');
  static const MessageType MT_SCREEN_SHARE_FRAME = MessageType._(214, _omitEnumNames ? '' : 'MT_SCREEN_SHARE_FRAME');
  static const MessageType MT_CALL_CHAT = MessageType._(215, _omitEnumNames ? '' : 'MT_CALL_CHAT');
  static const MessageType MT_REMOTE_CONTROL_INPUT = MessageType._(216, _omitEnumNames ? '' : 'MT_REMOTE_CONTROL_INPUT');

  static const $core.List<MessageType> values = <MessageType> [
    MT_TEXT,
    MT_MEDIA_INLINE,
    MT_MEDIA_ANNOUNCE,
    MT_MEDIA_REQUEST,
    MT_MEDIA_CHUNK,
    MT_MEDIA_COMPLETE,
    MT_MEDIA_REJECT,
    MT_REACTION,
    MT_REPLY,
    MT_EDIT,
    MT_DELETE,
    MT_MEDIA_STREAM_REQUEST,
    MT_MEDIA_STREAM_OFFER,
    MT_MEDIA_HOLDERS,
    MT_MEDIA_ABORT,
    MT_TYPING_INDICATOR,
    MT_READ_RECEIPT,
    MT_DELIVERY_RECEIPT,
    MT_CATCH_UP,
    MT_VOICE_MESSAGE,
    MT_IDENTITY_DELETED,
    MT_PROFILE_UPDATE,
    MT_KEY_ROTATION_BROADCAST,
    MT_KEY_ROTATION_ACK,
    MT_CONTACT_REQUEST,
    MT_CONTACT_REQUEST_RESPONSE,
    MT_GROUP_CREATE,
    MT_GROUP_INVITE,
    MT_GROUP_LEAVE,
    MT_GROUP_KEY_UPDATE,
    MT_GROUP_MEMBERSHIP_RESYNC_REQUEST,
    MT_GROUP_JOIN,
    MT_CHANNEL_CREATE,
    MT_CHANNEL_POST,
    MT_CHANNEL_INVITE,
    MT_CHANNEL_LEAVE,
    MT_CHANNEL_ROLE_UPDATE,
    MT_CHANNEL_BAD_BADGE_REPORT,
    MT_CHANNEL_JURY_VOTE,
    MT_CHANNEL_MOD_DECISION,
    MT_CHANNEL_SUBSCRIBE_PROBE,
    MT_CALL_MISSED,
    MT_CALL_INVITE,
    MT_CALL_ANSWER,
    MT_CALL_REJECT,
    MT_CALL_HANGUP,
    MT_ICE_CANDIDATE,
    MT_CALL_REJOIN,
    MT_CALL_AUDIO,
    MT_CALL_VIDEO,
    MT_CALL_GROUP_AUDIO,
    MT_CALL_GROUP_VIDEO,
    MT_CALL_GROUP_LEAVE,
    MT_CALL_RTT_PING,
    MT_CALL_RTT_PONG,
    MT_CALL_TREE_UPDATE,
    MT_CALL_KEYFRAME_REQUEST,
    MT_CALL_GROUP_SENDER_KEY,
    MT_CALL_MEDIA_STATE,
    MT_CALL_CANCEL_OTHERS,
    MT_CALL_RING_ACK,
    MT_CHANNEL_INDEX_EXCHANGE,
    MT_CHANNEL_JOIN_REQUEST,
    MT_CHANNEL_REPORT,
    MT_CHANNEL_REACTION_TOTALS,
    MT_CHANNEL_REACTION_HANDOVER,
    MT_CHANNEL_MEMBERS_CHANGE,
    MT_CAPABILITY_NOTICE,
    MT_SHARED_KEY,
    MT_SHARED_KEY_AUTHOR,
    MT_GROUP_MEMBERS_CHANGE,
    MT_DHT_PING,
    MT_DHT_PONG,
    MT_DHT_FIND_NODE,
    MT_DHT_FIND_NODE_RESPONSE,
    MT_DHT_STORE,
    MT_DHT_STORE_RESPONSE,
    MT_DHT_FIND_VALUE,
    MT_DHT_FIND_VALUE_RESPONSE,
    MT_FRAGMENT_STORE,
    MT_FRAGMENT_STORE_ACK,
    MT_FRAGMENT_RETRIEVE,
    MT_FRAGMENT_RETRIEVE_RESPONSE,
    MT_FRAGMENT_DELETE,
    MT_CHAT_CONFIG_UPDATE,
    MT_CHAT_CONFIG_RESPONSE,
    MT_IDENTITY_AUTH_PUBLISH,
    MT_IDENTITY_AUTH_RETRIEVE,
    MT_IDENTITY_AUTH_RESPONSE,
    MT_IDENTITY_LIVE_PUBLISH,
    MT_IDENTITY_LIVE_RETRIEVE,
    MT_IDENTITY_LIVE_RESPONSE,
    MT_TWIN_SYNC,
    MT_DEVICE_REVOCATION,
    MT_ROTATION_REJECTION_ALERT,
    MT_DEVICE_SET_ANNOUNCE,
    MT_CALENDAR_INVITE,
    MT_CALENDAR_RSVP,
    MT_CALENDAR_UPDATE,
    MT_CALENDAR_DELETE,
    MT_FREE_BUSY_REQUEST,
    MT_FREE_BUSY_RESPONSE,
    MT_POLL_CREATE,
    MT_POLL_VOTE,
    MT_POLL_VOTE_ANONYMOUS,
    MT_POLL_UPDATE,
    MT_POLL_SNAPSHOT,
    MT_POLL_REVOKE,
    MT_WHITEBOARD_STROKE,
    MT_WHITEBOARD_PAGE,
    MT_FILE_EXCHANGE,
    MT_CLIPBOARD_EXCHANGE,
    MT_SCREEN_SHARE_FRAME,
    MT_CALL_CHAT,
    MT_REMOTE_CONTROL_INPUT,
  ];

  static final $core.Map<$core.int, MessageType> _byValue = $pb.ProtobufEnum.initByValue(values);
  static MessageType? valueOf($core.int value) => _byValue[value];

  const MessageType._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');

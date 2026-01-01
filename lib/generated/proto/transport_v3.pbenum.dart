//
//  Generated code. Do not modify.
//  source: transport_v3.proto
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

class PayloadTypeV3 extends $pb.ProtobufEnum {
  static const PayloadTypeV3 PAYLOAD_APPLICATION_FRAME = PayloadTypeV3._(0, _omitEnumNames ? '' : 'PAYLOAD_APPLICATION_FRAME');
  static const PayloadTypeV3 PAYLOAD_ONION_LAYER = PayloadTypeV3._(1, _omitEnumNames ? '' : 'PAYLOAD_ONION_LAYER');

  static const $core.List<PayloadTypeV3> values = <PayloadTypeV3> [
    PAYLOAD_APPLICATION_FRAME,
    PAYLOAD_ONION_LAYER,
  ];

  static final $core.Map<$core.int, PayloadTypeV3> _byValue = $pb.ProtobufEnum.initByValue(values);
  static PayloadTypeV3? valueOf($core.int value) => _byValue[value];

  const PayloadTypeV3._($core.int v, $core.String n) : super(v, n);
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
///  ── MessageType V3 (numbering from Appendix A.4) ────────────────────────
///
///  CAUTION: numbers DIFFER FROM MessageType (old). Examples:
///    old: RESTORE_BROADCAST=13   → V3: MTV3_RESTORE_BROADCAST=30
///    old: TWIN_SYNC=131          → V3: MTV3_TWIN_SYNC=180
///  Hard cut in wave 2 (profile reset, §23.2). Until then both
///  enums coexist without problems because they have different names.
///
///  Prefix MTV3_ to avoid symbol collision with MessageType (old).
///  In wave 2 the prefix is removed + enum renamed to MessageType.
class MessageTypeV3 extends $pb.ProtobufEnum {
  static const MessageTypeV3 MTV3_TEXT = MessageTypeV3._(0, _omitEnumNames ? '' : 'MTV3_TEXT');
  static const MessageTypeV3 MTV3_MEDIA_INLINE = MessageTypeV3._(1, _omitEnumNames ? '' : 'MTV3_MEDIA_INLINE');
  static const MessageTypeV3 MTV3_MEDIA_ANNOUNCE = MessageTypeV3._(2, _omitEnumNames ? '' : 'MTV3_MEDIA_ANNOUNCE');
  static const MessageTypeV3 MTV3_MEDIA_REQUEST = MessageTypeV3._(3, _omitEnumNames ? '' : 'MTV3_MEDIA_REQUEST');
  static const MessageTypeV3 MTV3_MEDIA_CHUNK = MessageTypeV3._(4, _omitEnumNames ? '' : 'MTV3_MEDIA_CHUNK');
  static const MessageTypeV3 MTV3_MEDIA_COMPLETE = MessageTypeV3._(5, _omitEnumNames ? '' : 'MTV3_MEDIA_COMPLETE');
  static const MessageTypeV3 MTV3_MEDIA_REJECT = MessageTypeV3._(6, _omitEnumNames ? '' : 'MTV3_MEDIA_REJECT');
  static const MessageTypeV3 MTV3_REACTION = MessageTypeV3._(7, _omitEnumNames ? '' : 'MTV3_REACTION');
  static const MessageTypeV3 MTV3_REPLY = MessageTypeV3._(8, _omitEnumNames ? '' : 'MTV3_REPLY');
  static const MessageTypeV3 MTV3_EDIT = MessageTypeV3._(9, _omitEnumNames ? '' : 'MTV3_EDIT');
  static const MessageTypeV3 MTV3_DELETE = MessageTypeV3._(10, _omitEnumNames ? '' : 'MTV3_DELETE');
  static const MessageTypeV3 MTV3_TYPING_INDICATOR = MessageTypeV3._(15, _omitEnumNames ? '' : 'MTV3_TYPING_INDICATOR');
  static const MessageTypeV3 MTV3_READ_RECEIPT = MessageTypeV3._(16, _omitEnumNames ? '' : 'MTV3_READ_RECEIPT');
  static const MessageTypeV3 MTV3_DELIVERY_RECEIPT = MessageTypeV3._(17, _omitEnumNames ? '' : 'MTV3_DELIVERY_RECEIPT');
  static const MessageTypeV3 MTV3_VOICE_MESSAGE = MessageTypeV3._(22, _omitEnumNames ? '' : 'MTV3_VOICE_MESSAGE');
  static const MessageTypeV3 MTV3_RESTORE_BROADCAST = MessageTypeV3._(30, _omitEnumNames ? '' : 'MTV3_RESTORE_BROADCAST');
  static const MessageTypeV3 MTV3_RESTORE_RESPONSE = MessageTypeV3._(31, _omitEnumNames ? '' : 'MTV3_RESTORE_RESPONSE');
  static const MessageTypeV3 MTV3_IDENTITY_DELETED = MessageTypeV3._(32, _omitEnumNames ? '' : 'MTV3_IDENTITY_DELETED');
  static const MessageTypeV3 MTV3_PROFILE_UPDATE = MessageTypeV3._(33, _omitEnumNames ? '' : 'MTV3_PROFILE_UPDATE');
  static const MessageTypeV3 MTV3_KEY_ROTATION_BROADCAST = MessageTypeV3._(34, _omitEnumNames ? '' : 'MTV3_KEY_ROTATION_BROADCAST');
  static const MessageTypeV3 MTV3_KEY_ROTATION_ACK = MessageTypeV3._(38, _omitEnumNames ? '' : 'MTV3_KEY_ROTATION_ACK');
  static const MessageTypeV3 MTV3_CONTACT_REQUEST = MessageTypeV3._(40, _omitEnumNames ? '' : 'MTV3_CONTACT_REQUEST');
  static const MessageTypeV3 MTV3_CONTACT_REQUEST_RESPONSE = MessageTypeV3._(41, _omitEnumNames ? '' : 'MTV3_CONTACT_REQUEST_RESPONSE');
  static const MessageTypeV3 MTV3_GROUP_CREATE = MessageTypeV3._(50, _omitEnumNames ? '' : 'MTV3_GROUP_CREATE');
  static const MessageTypeV3 MTV3_GROUP_INVITE = MessageTypeV3._(51, _omitEnumNames ? '' : 'MTV3_GROUP_INVITE');
  static const MessageTypeV3 MTV3_GROUP_LEAVE = MessageTypeV3._(52, _omitEnumNames ? '' : 'MTV3_GROUP_LEAVE');
  static const MessageTypeV3 MTV3_GROUP_KEY_UPDATE = MessageTypeV3._(53, _omitEnumNames ? '' : 'MTV3_GROUP_KEY_UPDATE');
  static const MessageTypeV3 MTV3_GROUP_MEMBERSHIP_RESYNC_REQUEST = MessageTypeV3._(54, _omitEnumNames ? '' : 'MTV3_GROUP_MEMBERSHIP_RESYNC_REQUEST');
  static const MessageTypeV3 MTV3_CHANNEL_CREATE = MessageTypeV3._(60, _omitEnumNames ? '' : 'MTV3_CHANNEL_CREATE');
  static const MessageTypeV3 MTV3_CHANNEL_POST = MessageTypeV3._(61, _omitEnumNames ? '' : 'MTV3_CHANNEL_POST');
  static const MessageTypeV3 MTV3_CHANNEL_INVITE = MessageTypeV3._(62, _omitEnumNames ? '' : 'MTV3_CHANNEL_INVITE');
  static const MessageTypeV3 MTV3_CHANNEL_LEAVE = MessageTypeV3._(63, _omitEnumNames ? '' : 'MTV3_CHANNEL_LEAVE');
  static const MessageTypeV3 MTV3_CHANNEL_ROLE_UPDATE = MessageTypeV3._(64, _omitEnumNames ? '' : 'MTV3_CHANNEL_ROLE_UPDATE');
  static const MessageTypeV3 MTV3_CHANNEL_BAD_BADGE_REPORT = MessageTypeV3._(65, _omitEnumNames ? '' : 'MTV3_CHANNEL_BAD_BADGE_REPORT');
  static const MessageTypeV3 MTV3_CHANNEL_JURY_VOTE = MessageTypeV3._(66, _omitEnumNames ? '' : 'MTV3_CHANNEL_JURY_VOTE');
  static const MessageTypeV3 MTV3_CHANNEL_MOD_DECISION = MessageTypeV3._(67, _omitEnumNames ? '' : 'MTV3_CHANNEL_MOD_DECISION');
  static const MessageTypeV3 MTV3_CHANNEL_SUBSCRIBE_PROBE = MessageTypeV3._(68, _omitEnumNames ? '' : 'MTV3_CHANNEL_SUBSCRIBE_PROBE');
  static const MessageTypeV3 MTV3_CALL_INVITE = MessageTypeV3._(70, _omitEnumNames ? '' : 'MTV3_CALL_INVITE');
  static const MessageTypeV3 MTV3_CALL_ANSWER = MessageTypeV3._(71, _omitEnumNames ? '' : 'MTV3_CALL_ANSWER');
  static const MessageTypeV3 MTV3_CALL_REJECT = MessageTypeV3._(72, _omitEnumNames ? '' : 'MTV3_CALL_REJECT');
  static const MessageTypeV3 MTV3_CALL_HANGUP = MessageTypeV3._(73, _omitEnumNames ? '' : 'MTV3_CALL_HANGUP');
  static const MessageTypeV3 MTV3_ICE_CANDIDATE = MessageTypeV3._(74, _omitEnumNames ? '' : 'MTV3_ICE_CANDIDATE');
  static const MessageTypeV3 MTV3_CALL_REJOIN = MessageTypeV3._(75, _omitEnumNames ? '' : 'MTV3_CALL_REJOIN');
  static const MessageTypeV3 MTV3_CALL_AUDIO = MessageTypeV3._(76, _omitEnumNames ? '' : 'MTV3_CALL_AUDIO');
  static const MessageTypeV3 MTV3_CALL_VIDEO = MessageTypeV3._(77, _omitEnumNames ? '' : 'MTV3_CALL_VIDEO');
  static const MessageTypeV3 MTV3_CALL_GROUP_AUDIO = MessageTypeV3._(78, _omitEnumNames ? '' : 'MTV3_CALL_GROUP_AUDIO');
  static const MessageTypeV3 MTV3_CALL_GROUP_VIDEO = MessageTypeV3._(79, _omitEnumNames ? '' : 'MTV3_CALL_GROUP_VIDEO');
  static const MessageTypeV3 MTV3_CALL_GROUP_LEAVE = MessageTypeV3._(80, _omitEnumNames ? '' : 'MTV3_CALL_GROUP_LEAVE');
  static const MessageTypeV3 MTV3_CALL_RTT_PING = MessageTypeV3._(82, _omitEnumNames ? '' : 'MTV3_CALL_RTT_PING');
  static const MessageTypeV3 MTV3_CALL_RTT_PONG = MessageTypeV3._(83, _omitEnumNames ? '' : 'MTV3_CALL_RTT_PONG');
  static const MessageTypeV3 MTV3_CALL_TREE_UPDATE = MessageTypeV3._(84, _omitEnumNames ? '' : 'MTV3_CALL_TREE_UPDATE');
  static const MessageTypeV3 MTV3_CALL_KEYFRAME_REQUEST = MessageTypeV3._(85, _omitEnumNames ? '' : 'MTV3_CALL_KEYFRAME_REQUEST');
  static const MessageTypeV3 MTV3_CALL_GROUP_SENDER_KEY = MessageTypeV3._(86, _omitEnumNames ? '' : 'MTV3_CALL_GROUP_SENDER_KEY');
  static const MessageTypeV3 MTV3_CALL_MEDIA_STATE = MessageTypeV3._(87, _omitEnumNames ? '' : 'MTV3_CALL_MEDIA_STATE');
  static const MessageTypeV3 MTV3_CALL_CANCEL_OTHERS = MessageTypeV3._(88, _omitEnumNames ? '' : 'MTV3_CALL_CANCEL_OTHERS');
  static const MessageTypeV3 MTV3_CALL_RING_ACK = MessageTypeV3._(89, _omitEnumNames ? '' : 'MTV3_CALL_RING_ACK');
  static const MessageTypeV3 MTV3_CHANNEL_INDEX_EXCHANGE = MessageTypeV3._(90, _omitEnumNames ? '' : 'MTV3_CHANNEL_INDEX_EXCHANGE');
  static const MessageTypeV3 MTV3_CHANNEL_JOIN_REQUEST = MessageTypeV3._(91, _omitEnumNames ? '' : 'MTV3_CHANNEL_JOIN_REQUEST');
  static const MessageTypeV3 MTV3_CHANNEL_REPORT = MessageTypeV3._(92, _omitEnumNames ? '' : 'MTV3_CHANNEL_REPORT');
  static const MessageTypeV3 MTV3_DHT_PING = MessageTypeV3._(110, _omitEnumNames ? '' : 'MTV3_DHT_PING');
  static const MessageTypeV3 MTV3_DHT_PONG = MessageTypeV3._(111, _omitEnumNames ? '' : 'MTV3_DHT_PONG');
  static const MessageTypeV3 MTV3_DHT_FIND_NODE = MessageTypeV3._(112, _omitEnumNames ? '' : 'MTV3_DHT_FIND_NODE');
  static const MessageTypeV3 MTV3_DHT_FIND_NODE_RESPONSE = MessageTypeV3._(113, _omitEnumNames ? '' : 'MTV3_DHT_FIND_NODE_RESPONSE');
  static const MessageTypeV3 MTV3_DHT_STORE = MessageTypeV3._(114, _omitEnumNames ? '' : 'MTV3_DHT_STORE');
  static const MessageTypeV3 MTV3_DHT_STORE_RESPONSE = MessageTypeV3._(115, _omitEnumNames ? '' : 'MTV3_DHT_STORE_RESPONSE');
  static const MessageTypeV3 MTV3_DHT_FIND_VALUE = MessageTypeV3._(116, _omitEnumNames ? '' : 'MTV3_DHT_FIND_VALUE');
  static const MessageTypeV3 MTV3_DHT_FIND_VALUE_RESPONSE = MessageTypeV3._(117, _omitEnumNames ? '' : 'MTV3_DHT_FIND_VALUE_RESPONSE');
  static const MessageTypeV3 MTV3_FRAGMENT_STORE = MessageTypeV3._(120, _omitEnumNames ? '' : 'MTV3_FRAGMENT_STORE');
  static const MessageTypeV3 MTV3_FRAGMENT_STORE_ACK = MessageTypeV3._(121, _omitEnumNames ? '' : 'MTV3_FRAGMENT_STORE_ACK');
  static const MessageTypeV3 MTV3_FRAGMENT_RETRIEVE = MessageTypeV3._(122, _omitEnumNames ? '' : 'MTV3_FRAGMENT_RETRIEVE');
  static const MessageTypeV3 MTV3_FRAGMENT_RETRIEVE_RESPONSE = MessageTypeV3._(123, _omitEnumNames ? '' : 'MTV3_FRAGMENT_RETRIEVE_RESPONSE');
  static const MessageTypeV3 MTV3_FRAGMENT_DELETE = MessageTypeV3._(124, _omitEnumNames ? '' : 'MTV3_FRAGMENT_DELETE');
  static const MessageTypeV3 MTV3_CHAT_CONFIG_UPDATE = MessageTypeV3._(140, _omitEnumNames ? '' : 'MTV3_CHAT_CONFIG_UPDATE');
  static const MessageTypeV3 MTV3_CHAT_CONFIG_RESPONSE = MessageTypeV3._(141, _omitEnumNames ? '' : 'MTV3_CHAT_CONFIG_RESPONSE');
  static const MessageTypeV3 MTV3_IDENTITY_AUTH_PUBLISH = MessageTypeV3._(170, _omitEnumNames ? '' : 'MTV3_IDENTITY_AUTH_PUBLISH');
  static const MessageTypeV3 MTV3_IDENTITY_AUTH_RETRIEVE = MessageTypeV3._(171, _omitEnumNames ? '' : 'MTV3_IDENTITY_AUTH_RETRIEVE');
  static const MessageTypeV3 MTV3_IDENTITY_AUTH_RESPONSE = MessageTypeV3._(172, _omitEnumNames ? '' : 'MTV3_IDENTITY_AUTH_RESPONSE');
  static const MessageTypeV3 MTV3_IDENTITY_LIVE_PUBLISH = MessageTypeV3._(173, _omitEnumNames ? '' : 'MTV3_IDENTITY_LIVE_PUBLISH');
  static const MessageTypeV3 MTV3_IDENTITY_LIVE_RETRIEVE = MessageTypeV3._(174, _omitEnumNames ? '' : 'MTV3_IDENTITY_LIVE_RETRIEVE');
  static const MessageTypeV3 MTV3_IDENTITY_LIVE_RESPONSE = MessageTypeV3._(175, _omitEnumNames ? '' : 'MTV3_IDENTITY_LIVE_RESPONSE');
  static const MessageTypeV3 MTV3_TWIN_SYNC = MessageTypeV3._(180, _omitEnumNames ? '' : 'MTV3_TWIN_SYNC');
  static const MessageTypeV3 MTV3_DEVICE_PAIR_REQUEST = MessageTypeV3._(181, _omitEnumNames ? '' : 'MTV3_DEVICE_PAIR_REQUEST');
  static const MessageTypeV3 MTV3_DEVICE_PAIR_APPROVE = MessageTypeV3._(182, _omitEnumNames ? '' : 'MTV3_DEVICE_PAIR_APPROVE');
  static const MessageTypeV3 MTV3_DEVICE_REVOCATION = MessageTypeV3._(183, _omitEnumNames ? '' : 'MTV3_DEVICE_REVOCATION');
  static const MessageTypeV3 MTV3_ROTATION_REJECTION_ALERT = MessageTypeV3._(184, _omitEnumNames ? '' : 'MTV3_ROTATION_REJECTION_ALERT');
  static const MessageTypeV3 MTV3_DEVICE_SET_ANNOUNCE = MessageTypeV3._(185, _omitEnumNames ? '' : 'MTV3_DEVICE_SET_ANNOUNCE');
  static const MessageTypeV3 MTV3_CALENDAR_INVITE = MessageTypeV3._(190, _omitEnumNames ? '' : 'MTV3_CALENDAR_INVITE');
  static const MessageTypeV3 MTV3_CALENDAR_RSVP = MessageTypeV3._(191, _omitEnumNames ? '' : 'MTV3_CALENDAR_RSVP');
  static const MessageTypeV3 MTV3_CALENDAR_UPDATE = MessageTypeV3._(192, _omitEnumNames ? '' : 'MTV3_CALENDAR_UPDATE');
  static const MessageTypeV3 MTV3_CALENDAR_DELETE = MessageTypeV3._(193, _omitEnumNames ? '' : 'MTV3_CALENDAR_DELETE');
  static const MessageTypeV3 MTV3_FREE_BUSY_REQUEST = MessageTypeV3._(194, _omitEnumNames ? '' : 'MTV3_FREE_BUSY_REQUEST');
  static const MessageTypeV3 MTV3_FREE_BUSY_RESPONSE = MessageTypeV3._(195, _omitEnumNames ? '' : 'MTV3_FREE_BUSY_RESPONSE');
  static const MessageTypeV3 MTV3_POLL_CREATE = MessageTypeV3._(200, _omitEnumNames ? '' : 'MTV3_POLL_CREATE');
  static const MessageTypeV3 MTV3_POLL_VOTE = MessageTypeV3._(201, _omitEnumNames ? '' : 'MTV3_POLL_VOTE');
  static const MessageTypeV3 MTV3_POLL_VOTE_ANONYMOUS = MessageTypeV3._(202, _omitEnumNames ? '' : 'MTV3_POLL_VOTE_ANONYMOUS');
  static const MessageTypeV3 MTV3_POLL_UPDATE = MessageTypeV3._(203, _omitEnumNames ? '' : 'MTV3_POLL_UPDATE');
  static const MessageTypeV3 MTV3_POLL_SNAPSHOT = MessageTypeV3._(204, _omitEnumNames ? '' : 'MTV3_POLL_SNAPSHOT');
  static const MessageTypeV3 MTV3_POLL_REVOKE = MessageTypeV3._(205, _omitEnumNames ? '' : 'MTV3_POLL_REVOKE');
  static const MessageTypeV3 MTV3_WHITEBOARD_STROKE = MessageTypeV3._(210, _omitEnumNames ? '' : 'MTV3_WHITEBOARD_STROKE');
  static const MessageTypeV3 MTV3_WHITEBOARD_PAGE = MessageTypeV3._(211, _omitEnumNames ? '' : 'MTV3_WHITEBOARD_PAGE');
  static const MessageTypeV3 MTV3_FILE_EXCHANGE = MessageTypeV3._(212, _omitEnumNames ? '' : 'MTV3_FILE_EXCHANGE');
  static const MessageTypeV3 MTV3_CLIPBOARD_EXCHANGE = MessageTypeV3._(213, _omitEnumNames ? '' : 'MTV3_CLIPBOARD_EXCHANGE');
  static const MessageTypeV3 MTV3_SCREEN_SHARE_FRAME = MessageTypeV3._(214, _omitEnumNames ? '' : 'MTV3_SCREEN_SHARE_FRAME');
  static const MessageTypeV3 MTV3_CALL_CHAT = MessageTypeV3._(215, _omitEnumNames ? '' : 'MTV3_CALL_CHAT');
  static const MessageTypeV3 MTV3_REMOTE_CONTROL_INPUT = MessageTypeV3._(216, _omitEnumNames ? '' : 'MTV3_REMOTE_CONTROL_INPUT');

  static const $core.List<MessageTypeV3> values = <MessageTypeV3> [
    MTV3_TEXT,
    MTV3_MEDIA_INLINE,
    MTV3_MEDIA_ANNOUNCE,
    MTV3_MEDIA_REQUEST,
    MTV3_MEDIA_CHUNK,
    MTV3_MEDIA_COMPLETE,
    MTV3_MEDIA_REJECT,
    MTV3_REACTION,
    MTV3_REPLY,
    MTV3_EDIT,
    MTV3_DELETE,
    MTV3_TYPING_INDICATOR,
    MTV3_READ_RECEIPT,
    MTV3_DELIVERY_RECEIPT,
    MTV3_VOICE_MESSAGE,
    MTV3_RESTORE_BROADCAST,
    MTV3_RESTORE_RESPONSE,
    MTV3_IDENTITY_DELETED,
    MTV3_PROFILE_UPDATE,
    MTV3_KEY_ROTATION_BROADCAST,
    MTV3_KEY_ROTATION_ACK,
    MTV3_CONTACT_REQUEST,
    MTV3_CONTACT_REQUEST_RESPONSE,
    MTV3_GROUP_CREATE,
    MTV3_GROUP_INVITE,
    MTV3_GROUP_LEAVE,
    MTV3_GROUP_KEY_UPDATE,
    MTV3_GROUP_MEMBERSHIP_RESYNC_REQUEST,
    MTV3_CHANNEL_CREATE,
    MTV3_CHANNEL_POST,
    MTV3_CHANNEL_INVITE,
    MTV3_CHANNEL_LEAVE,
    MTV3_CHANNEL_ROLE_UPDATE,
    MTV3_CHANNEL_BAD_BADGE_REPORT,
    MTV3_CHANNEL_JURY_VOTE,
    MTV3_CHANNEL_MOD_DECISION,
    MTV3_CHANNEL_SUBSCRIBE_PROBE,
    MTV3_CALL_INVITE,
    MTV3_CALL_ANSWER,
    MTV3_CALL_REJECT,
    MTV3_CALL_HANGUP,
    MTV3_ICE_CANDIDATE,
    MTV3_CALL_REJOIN,
    MTV3_CALL_AUDIO,
    MTV3_CALL_VIDEO,
    MTV3_CALL_GROUP_AUDIO,
    MTV3_CALL_GROUP_VIDEO,
    MTV3_CALL_GROUP_LEAVE,
    MTV3_CALL_RTT_PING,
    MTV3_CALL_RTT_PONG,
    MTV3_CALL_TREE_UPDATE,
    MTV3_CALL_KEYFRAME_REQUEST,
    MTV3_CALL_GROUP_SENDER_KEY,
    MTV3_CALL_MEDIA_STATE,
    MTV3_CALL_CANCEL_OTHERS,
    MTV3_CALL_RING_ACK,
    MTV3_CHANNEL_INDEX_EXCHANGE,
    MTV3_CHANNEL_JOIN_REQUEST,
    MTV3_CHANNEL_REPORT,
    MTV3_DHT_PING,
    MTV3_DHT_PONG,
    MTV3_DHT_FIND_NODE,
    MTV3_DHT_FIND_NODE_RESPONSE,
    MTV3_DHT_STORE,
    MTV3_DHT_STORE_RESPONSE,
    MTV3_DHT_FIND_VALUE,
    MTV3_DHT_FIND_VALUE_RESPONSE,
    MTV3_FRAGMENT_STORE,
    MTV3_FRAGMENT_STORE_ACK,
    MTV3_FRAGMENT_RETRIEVE,
    MTV3_FRAGMENT_RETRIEVE_RESPONSE,
    MTV3_FRAGMENT_DELETE,
    MTV3_CHAT_CONFIG_UPDATE,
    MTV3_CHAT_CONFIG_RESPONSE,
    MTV3_IDENTITY_AUTH_PUBLISH,
    MTV3_IDENTITY_AUTH_RETRIEVE,
    MTV3_IDENTITY_AUTH_RESPONSE,
    MTV3_IDENTITY_LIVE_PUBLISH,
    MTV3_IDENTITY_LIVE_RETRIEVE,
    MTV3_IDENTITY_LIVE_RESPONSE,
    MTV3_TWIN_SYNC,
    MTV3_DEVICE_PAIR_REQUEST,
    MTV3_DEVICE_PAIR_APPROVE,
    MTV3_DEVICE_REVOCATION,
    MTV3_ROTATION_REJECTION_ALERT,
    MTV3_DEVICE_SET_ANNOUNCE,
    MTV3_CALENDAR_INVITE,
    MTV3_CALENDAR_RSVP,
    MTV3_CALENDAR_UPDATE,
    MTV3_CALENDAR_DELETE,
    MTV3_FREE_BUSY_REQUEST,
    MTV3_FREE_BUSY_RESPONSE,
    MTV3_POLL_CREATE,
    MTV3_POLL_VOTE,
    MTV3_POLL_VOTE_ANONYMOUS,
    MTV3_POLL_UPDATE,
    MTV3_POLL_SNAPSHOT,
    MTV3_POLL_REVOKE,
    MTV3_WHITEBOARD_STROKE,
    MTV3_WHITEBOARD_PAGE,
    MTV3_FILE_EXCHANGE,
    MTV3_CLIPBOARD_EXCHANGE,
    MTV3_SCREEN_SHARE_FRAME,
    MTV3_CALL_CHAT,
    MTV3_REMOTE_CONTROL_INPUT,
  ];

  static final $core.Map<$core.int, MessageTypeV3> _byValue = $pb.ProtobufEnum.initByValue(values);
  static MessageTypeV3? valueOf($core.int value) => _byValue[value];

  const MessageTypeV3._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');

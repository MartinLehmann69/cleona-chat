//
//  Generated code. Do not modify.
//  source: cleona.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class MessageType extends $pb.ProtobufEnum {
  static const MessageType TEXT = MessageType._(0, _omitEnumNames ? '' : 'TEXT');
  static const MessageType IMAGE = MessageType._(1, _omitEnumNames ? '' : 'IMAGE');
  static const MessageType VIDEO = MessageType._(2, _omitEnumNames ? '' : 'VIDEO');
  static const MessageType GIF = MessageType._(3, _omitEnumNames ? '' : 'GIF');
  static const MessageType EMOJI_REACTION = MessageType._(4, _omitEnumNames ? '' : 'EMOJI_REACTION');
  static const MessageType MEDIA_ANNOUNCEMENT = MessageType._(5, _omitEnumNames ? '' : 'MEDIA_ANNOUNCEMENT');
  static const MessageType MEDIA_ACCEPT = MessageType._(6, _omitEnumNames ? '' : 'MEDIA_ACCEPT');
  static const MessageType MEDIA_REJECT = MessageType._(7, _omitEnumNames ? '' : 'MEDIA_REJECT');
  static const MessageType MESSAGE_EDIT = MessageType._(8, _omitEnumNames ? '' : 'MESSAGE_EDIT');
  static const MessageType MESSAGE_EXPIRE_CONFIG = MessageType._(9, _omitEnumNames ? '' : 'MESSAGE_EXPIRE_CONFIG');
  static const MessageType RESTORE_BROADCAST = MessageType._(13, _omitEnumNames ? '' : 'RESTORE_BROADCAST');
  static const MessageType RESTORE_RESPONSE = MessageType._(14, _omitEnumNames ? '' : 'RESTORE_RESPONSE');
  static const MessageType TYPING_INDICATOR = MessageType._(15, _omitEnumNames ? '' : 'TYPING_INDICATOR');
  static const MessageType READ_RECEIPT = MessageType._(16, _omitEnumNames ? '' : 'READ_RECEIPT');
  static const MessageType GROUP_CREATE = MessageType._(17, _omitEnumNames ? '' : 'GROUP_CREATE');
  static const MessageType GROUP_INVITE = MessageType._(18, _omitEnumNames ? '' : 'GROUP_INVITE');
  static const MessageType GROUP_LEAVE = MessageType._(19, _omitEnumNames ? '' : 'GROUP_LEAVE');
  static const MessageType GROUP_KEY_UPDATE = MessageType._(20, _omitEnumNames ? '' : 'GROUP_KEY_UPDATE');
  static const MessageType MESSAGE_DELETE = MessageType._(21, _omitEnumNames ? '' : 'MESSAGE_DELETE');
  static const MessageType VOICE_MESSAGE = MessageType._(22, _omitEnumNames ? '' : 'VOICE_MESSAGE');
  static const MessageType FILE = MessageType._(23, _omitEnumNames ? '' : 'FILE');
  static const MessageType CALL_INVITE = MessageType._(30, _omitEnumNames ? '' : 'CALL_INVITE');
  static const MessageType CALL_ANSWER = MessageType._(31, _omitEnumNames ? '' : 'CALL_ANSWER');
  static const MessageType CALL_REJECT = MessageType._(32, _omitEnumNames ? '' : 'CALL_REJECT');
  static const MessageType CALL_HANGUP = MessageType._(33, _omitEnumNames ? '' : 'CALL_HANGUP');
  static const MessageType ICE_CANDIDATE = MessageType._(34, _omitEnumNames ? '' : 'ICE_CANDIDATE');
  static const MessageType CALL_REJOIN = MessageType._(35, _omitEnumNames ? '' : 'CALL_REJOIN');
  static const MessageType CALL_AUDIO = MessageType._(36, _omitEnumNames ? '' : 'CALL_AUDIO');
  static const MessageType PEER_LIST_SUMMARY = MessageType._(50, _omitEnumNames ? '' : 'PEER_LIST_SUMMARY');
  static const MessageType PEER_LIST_WANT = MessageType._(51, _omitEnumNames ? '' : 'PEER_LIST_WANT');
  static const MessageType PEER_LIST_PUSH = MessageType._(52, _omitEnumNames ? '' : 'PEER_LIST_PUSH');
  static const MessageType CONTACT_REQUEST = MessageType._(62, _omitEnumNames ? '' : 'CONTACT_REQUEST');
  static const MessageType CONTACT_REQUEST_RESPONSE = MessageType._(63, _omitEnumNames ? '' : 'CONTACT_REQUEST_RESPONSE');
  static const MessageType CHANNEL_CREATE = MessageType._(70, _omitEnumNames ? '' : 'CHANNEL_CREATE');
  static const MessageType CHANNEL_POST = MessageType._(71, _omitEnumNames ? '' : 'CHANNEL_POST');
  static const MessageType CHANNEL_INVITE = MessageType._(72, _omitEnumNames ? '' : 'CHANNEL_INVITE');
  static const MessageType CHANNEL_ROLE_UPDATE = MessageType._(73, _omitEnumNames ? '' : 'CHANNEL_ROLE_UPDATE');
  static const MessageType CHANNEL_LEAVE = MessageType._(74, _omitEnumNames ? '' : 'CHANNEL_LEAVE');
  static const MessageType CHANNEL_JOIN_REQUEST = MessageType._(75, _omitEnumNames ? '' : 'CHANNEL_JOIN_REQUEST');
  static const MessageType CHANNEL_REPORT = MessageType._(76, _omitEnumNames ? '' : 'CHANNEL_REPORT');
  static const MessageType CHANNEL_REPORT_RESPONSE = MessageType._(77, _omitEnumNames ? '' : 'CHANNEL_REPORT_RESPONSE');
  static const MessageType JURY_REQUEST = MessageType._(78, _omitEnumNames ? '' : 'JURY_REQUEST');
  static const MessageType JURY_VOTE_MSG = MessageType._(79, _omitEnumNames ? '' : 'JURY_VOTE_MSG');
  static const MessageType JURY_RESULT = MessageType._(88, _omitEnumNames ? '' : 'JURY_RESULT');
  static const MessageType CHANNEL_INDEX_EXCHANGE = MessageType._(89, _omitEnumNames ? '' : 'CHANNEL_INDEX_EXCHANGE');
  static const MessageType DHT_PING = MessageType._(80, _omitEnumNames ? '' : 'DHT_PING');
  static const MessageType DHT_PONG = MessageType._(81, _omitEnumNames ? '' : 'DHT_PONG');
  static const MessageType DHT_FIND_NODE = MessageType._(82, _omitEnumNames ? '' : 'DHT_FIND_NODE');
  static const MessageType DHT_FIND_NODE_RESPONSE = MessageType._(83, _omitEnumNames ? '' : 'DHT_FIND_NODE_RESPONSE');
  static const MessageType DHT_STORE = MessageType._(84, _omitEnumNames ? '' : 'DHT_STORE');
  static const MessageType DHT_STORE_RESPONSE = MessageType._(85, _omitEnumNames ? '' : 'DHT_STORE_RESPONSE');
  static const MessageType DHT_FIND_VALUE = MessageType._(86, _omitEnumNames ? '' : 'DHT_FIND_VALUE');
  static const MessageType DHT_FIND_VALUE_RESPONSE = MessageType._(87, _omitEnumNames ? '' : 'DHT_FIND_VALUE_RESPONSE');
  static const MessageType FRAGMENT_STORE = MessageType._(90, _omitEnumNames ? '' : 'FRAGMENT_STORE');
  static const MessageType FRAGMENT_STORE_ACK = MessageType._(91, _omitEnumNames ? '' : 'FRAGMENT_STORE_ACK');
  static const MessageType FRAGMENT_RETRIEVE = MessageType._(92, _omitEnumNames ? '' : 'FRAGMENT_RETRIEVE');
  static const MessageType FRAGMENT_DELETE = MessageType._(93, _omitEnumNames ? '' : 'FRAGMENT_DELETE');
  static const MessageType DELIVERY_RECEIPT = MessageType._(94, _omitEnumNames ? '' : 'DELIVERY_RECEIPT');
  static const MessageType CHAT_CONFIG_UPDATE = MessageType._(100, _omitEnumNames ? '' : 'CHAT_CONFIG_UPDATE');
  static const MessageType CHAT_CONFIG_RESPONSE = MessageType._(101, _omitEnumNames ? '' : 'CHAT_CONFIG_RESPONSE');
  static const MessageType IDENTITY_DELETED = MessageType._(102, _omitEnumNames ? '' : 'IDENTITY_DELETED');
  static const MessageType PROFILE_UPDATE = MessageType._(103, _omitEnumNames ? '' : 'PROFILE_UPDATE');
  static const MessageType GUARDIAN_SHARE_STORE = MessageType._(104, _omitEnumNames ? '' : 'GUARDIAN_SHARE_STORE');
  static const MessageType GUARDIAN_RESTORE_REQUEST = MessageType._(105, _omitEnumNames ? '' : 'GUARDIAN_RESTORE_REQUEST');
  static const MessageType GUARDIAN_RESTORE_RESPONSE = MessageType._(106, _omitEnumNames ? '' : 'GUARDIAN_RESTORE_RESPONSE');
  static const MessageType RELAY_FORWARD = MessageType._(110, _omitEnumNames ? '' : 'RELAY_FORWARD');
  static const MessageType RELAY_ACK = MessageType._(111, _omitEnumNames ? '' : 'RELAY_ACK');
  static const MessageType REACHABILITY_QUERY = MessageType._(112, _omitEnumNames ? '' : 'REACHABILITY_QUERY');
  static const MessageType REACHABILITY_RESPONSE = MessageType._(113, _omitEnumNames ? '' : 'REACHABILITY_RESPONSE');
  static const MessageType PEER_STORE = MessageType._(114, _omitEnumNames ? '' : 'PEER_STORE');
  static const MessageType PEER_STORE_ACK = MessageType._(115, _omitEnumNames ? '' : 'PEER_STORE_ACK');
  static const MessageType PEER_RETRIEVE = MessageType._(116, _omitEnumNames ? '' : 'PEER_RETRIEVE');
  static const MessageType PEER_RETRIEVE_RESPONSE = MessageType._(117, _omitEnumNames ? '' : 'PEER_RETRIEVE_RESPONSE');
  static const MessageType ROUTE_UPDATE = MessageType._(120, _omitEnumNames ? '' : 'ROUTE_UPDATE');
  static const MessageType HOLE_PUNCH_REQUEST = MessageType._(121, _omitEnumNames ? '' : 'HOLE_PUNCH_REQUEST');
  static const MessageType HOLE_PUNCH_NOTIFY = MessageType._(122, _omitEnumNames ? '' : 'HOLE_PUNCH_NOTIFY');
  static const MessageType HOLE_PUNCH_PING = MessageType._(123, _omitEnumNames ? '' : 'HOLE_PUNCH_PING');
  static const MessageType HOLE_PUNCH_PONG = MessageType._(124, _omitEnumNames ? '' : 'HOLE_PUNCH_PONG');
  static const MessageType MEDIA_CHUNK = MessageType._(125, _omitEnumNames ? '' : 'MEDIA_CHUNK');
  static const MessageType TWIN_ANNOUNCE = MessageType._(130, _omitEnumNames ? '' : 'TWIN_ANNOUNCE');
  static const MessageType TWIN_SYNC = MessageType._(131, _omitEnumNames ? '' : 'TWIN_SYNC');
  static const MessageType DEVICE_REVOKED = MessageType._(132, _omitEnumNames ? '' : 'DEVICE_REVOKED');
  static const MessageType KEY_ROTATION_BROADCAST = MessageType._(133, _omitEnumNames ? '' : 'KEY_ROTATION_BROADCAST');
  static const MessageType KEY_ROTATION_ACK = MessageType._(134, _omitEnumNames ? '' : 'KEY_ROTATION_ACK');
  static const MessageType CALENDAR_INVITE = MessageType._(140, _omitEnumNames ? '' : 'CALENDAR_INVITE');
  static const MessageType CALENDAR_RSVP = MessageType._(141, _omitEnumNames ? '' : 'CALENDAR_RSVP');
  static const MessageType CALENDAR_UPDATE = MessageType._(142, _omitEnumNames ? '' : 'CALENDAR_UPDATE');
  static const MessageType CALENDAR_DELETE = MessageType._(143, _omitEnumNames ? '' : 'CALENDAR_DELETE');
  static const MessageType FREE_BUSY_REQUEST = MessageType._(144, _omitEnumNames ? '' : 'FREE_BUSY_REQUEST');
  static const MessageType FREE_BUSY_RESPONSE = MessageType._(145, _omitEnumNames ? '' : 'FREE_BUSY_RESPONSE');
  static const MessageType POLL_CREATE = MessageType._(146, _omitEnumNames ? '' : 'POLL_CREATE');
  static const MessageType POLL_VOTE = MessageType._(147, _omitEnumNames ? '' : 'POLL_VOTE');
  static const MessageType POLL_UPDATE = MessageType._(148, _omitEnumNames ? '' : 'POLL_UPDATE');
  static const MessageType POLL_SNAPSHOT = MessageType._(149, _omitEnumNames ? '' : 'POLL_SNAPSHOT');
  static const MessageType POLL_VOTE_ANONYMOUS = MessageType._(150, _omitEnumNames ? '' : 'POLL_VOTE_ANONYMOUS');
  static const MessageType POLL_VOTE_REVOKE = MessageType._(151, _omitEnumNames ? '' : 'POLL_VOTE_REVOKE');
  static const MessageType CALL_RTT_PING = MessageType._(37, _omitEnumNames ? '' : 'CALL_RTT_PING');
  static const MessageType CALL_RTT_PONG = MessageType._(38, _omitEnumNames ? '' : 'CALL_RTT_PONG');
  static const MessageType CALL_TREE_UPDATE = MessageType._(39, _omitEnumNames ? '' : 'CALL_TREE_UPDATE');
  static const MessageType CALL_VIDEO = MessageType._(40, _omitEnumNames ? '' : 'CALL_VIDEO');
  static const MessageType CALL_KEYFRAME_REQUEST = MessageType._(41, _omitEnumNames ? '' : 'CALL_KEYFRAME_REQUEST');
  static const MessageType CALL_GROUP_AUDIO = MessageType._(42, _omitEnumNames ? '' : 'CALL_GROUP_AUDIO');
  static const MessageType CALL_GROUP_LEAVE = MessageType._(43, _omitEnumNames ? '' : 'CALL_GROUP_LEAVE');
  static const MessageType CALL_GROUP_KEY_ROTATE = MessageType._(44, _omitEnumNames ? '' : 'CALL_GROUP_KEY_ROTATE');
  static const MessageType CALL_GROUP_VIDEO = MessageType._(45, _omitEnumNames ? '' : 'CALL_GROUP_VIDEO');

  static const $core.List<MessageType> values = <MessageType> [
    TEXT,
    IMAGE,
    VIDEO,
    GIF,
    EMOJI_REACTION,
    MEDIA_ANNOUNCEMENT,
    MEDIA_ACCEPT,
    MEDIA_REJECT,
    MESSAGE_EDIT,
    MESSAGE_EXPIRE_CONFIG,
    RESTORE_BROADCAST,
    RESTORE_RESPONSE,
    TYPING_INDICATOR,
    READ_RECEIPT,
    GROUP_CREATE,
    GROUP_INVITE,
    GROUP_LEAVE,
    GROUP_KEY_UPDATE,
    MESSAGE_DELETE,
    VOICE_MESSAGE,
    FILE,
    CALL_INVITE,
    CALL_ANSWER,
    CALL_REJECT,
    CALL_HANGUP,
    ICE_CANDIDATE,
    CALL_REJOIN,
    CALL_AUDIO,
    PEER_LIST_SUMMARY,
    PEER_LIST_WANT,
    PEER_LIST_PUSH,
    CONTACT_REQUEST,
    CONTACT_REQUEST_RESPONSE,
    CHANNEL_CREATE,
    CHANNEL_POST,
    CHANNEL_INVITE,
    CHANNEL_ROLE_UPDATE,
    CHANNEL_LEAVE,
    CHANNEL_JOIN_REQUEST,
    CHANNEL_REPORT,
    CHANNEL_REPORT_RESPONSE,
    JURY_REQUEST,
    JURY_VOTE_MSG,
    JURY_RESULT,
    CHANNEL_INDEX_EXCHANGE,
    DHT_PING,
    DHT_PONG,
    DHT_FIND_NODE,
    DHT_FIND_NODE_RESPONSE,
    DHT_STORE,
    DHT_STORE_RESPONSE,
    DHT_FIND_VALUE,
    DHT_FIND_VALUE_RESPONSE,
    FRAGMENT_STORE,
    FRAGMENT_STORE_ACK,
    FRAGMENT_RETRIEVE,
    FRAGMENT_DELETE,
    DELIVERY_RECEIPT,
    CHAT_CONFIG_UPDATE,
    CHAT_CONFIG_RESPONSE,
    IDENTITY_DELETED,
    PROFILE_UPDATE,
    GUARDIAN_SHARE_STORE,
    GUARDIAN_RESTORE_REQUEST,
    GUARDIAN_RESTORE_RESPONSE,
    RELAY_FORWARD,
    RELAY_ACK,
    REACHABILITY_QUERY,
    REACHABILITY_RESPONSE,
    PEER_STORE,
    PEER_STORE_ACK,
    PEER_RETRIEVE,
    PEER_RETRIEVE_RESPONSE,
    ROUTE_UPDATE,
    HOLE_PUNCH_REQUEST,
    HOLE_PUNCH_NOTIFY,
    HOLE_PUNCH_PING,
    HOLE_PUNCH_PONG,
    MEDIA_CHUNK,
    TWIN_ANNOUNCE,
    TWIN_SYNC,
    DEVICE_REVOKED,
    KEY_ROTATION_BROADCAST,
    KEY_ROTATION_ACK,
    CALENDAR_INVITE,
    CALENDAR_RSVP,
    CALENDAR_UPDATE,
    CALENDAR_DELETE,
    FREE_BUSY_REQUEST,
    FREE_BUSY_RESPONSE,
    POLL_CREATE,
    POLL_VOTE,
    POLL_UPDATE,
    POLL_SNAPSHOT,
    POLL_VOTE_ANONYMOUS,
    POLL_VOTE_REVOKE,
    CALL_RTT_PING,
    CALL_RTT_PONG,
    CALL_TREE_UPDATE,
    CALL_VIDEO,
    CALL_KEYFRAME_REQUEST,
    CALL_GROUP_AUDIO,
    CALL_GROUP_LEAVE,
    CALL_GROUP_KEY_ROTATE,
    CALL_GROUP_VIDEO,
  ];

  static final $core.Map<$core.int, MessageType> _byValue = $pb.ProtobufEnum.initByValue(values);
  static MessageType? valueOf($core.int value) => _byValue[value];

  const MessageType._($core.int v, $core.String n) : super(v, n);
}

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

class AddressType extends $pb.ProtobufEnum {
  static const AddressType IPV4_PUBLIC = AddressType._(0, _omitEnumNames ? '' : 'IPV4_PUBLIC');
  static const AddressType IPV4_PRIVATE = AddressType._(1, _omitEnumNames ? '' : 'IPV4_PRIVATE');
  static const AddressType IPV6_GLOBAL = AddressType._(2, _omitEnumNames ? '' : 'IPV6_GLOBAL');

  static const $core.List<AddressType> values = <AddressType> [
    IPV4_PUBLIC,
    IPV4_PRIVATE,
    IPV6_GLOBAL,
  ];

  static final $core.Map<$core.int, AddressType> _byValue = $pb.ProtobufEnum.initByValue(values);
  static AddressType? valueOf($core.int value) => _byValue[value];

  const AddressType._($core.int v, $core.String n) : super(v, n);
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

class TwinSyncType extends $pb.ProtobufEnum {
  static const TwinSyncType CONTACT_ADDED = TwinSyncType._(0, _omitEnumNames ? '' : 'CONTACT_ADDED');
  static const TwinSyncType CONTACT_DELETED = TwinSyncType._(1, _omitEnumNames ? '' : 'CONTACT_DELETED');
  static const TwinSyncType MESSAGE_SENT = TwinSyncType._(2, _omitEnumNames ? '' : 'MESSAGE_SENT');
  static const TwinSyncType MESSAGE_EDITED = TwinSyncType._(3, _omitEnumNames ? '' : 'MESSAGE_EDITED');
  static const TwinSyncType MESSAGE_DELETED = TwinSyncType._(4, _omitEnumNames ? '' : 'MESSAGE_DELETED');
  static const TwinSyncType TWIN_READ_RECEIPT = TwinSyncType._(5, _omitEnumNames ? '' : 'TWIN_READ_RECEIPT');
  static const TwinSyncType GROUP_CREATED = TwinSyncType._(6, _omitEnumNames ? '' : 'GROUP_CREATED');
  static const TwinSyncType PROFILE_CHANGED = TwinSyncType._(7, _omitEnumNames ? '' : 'PROFILE_CHANGED');
  static const TwinSyncType SETTINGS_CHANGED = TwinSyncType._(8, _omitEnumNames ? '' : 'SETTINGS_CHANGED');
  static const TwinSyncType DEVICE_ANNOUNCE = TwinSyncType._(9, _omitEnumNames ? '' : 'DEVICE_ANNOUNCE');
  static const TwinSyncType DEVICE_RENAMED = TwinSyncType._(10, _omitEnumNames ? '' : 'DEVICE_RENAMED');
  static const TwinSyncType TWIN_DEVICE_REVOKED = TwinSyncType._(11, _omitEnumNames ? '' : 'TWIN_DEVICE_REVOKED');

  static const $core.List<TwinSyncType> values = <TwinSyncType> [
    CONTACT_ADDED,
    CONTACT_DELETED,
    MESSAGE_SENT,
    MESSAGE_EDITED,
    MESSAGE_DELETED,
    TWIN_READ_RECEIPT,
    GROUP_CREATED,
    PROFILE_CHANGED,
    SETTINGS_CHANGED,
    DEVICE_ANNOUNCE,
    DEVICE_RENAMED,
    TWIN_DEVICE_REVOKED,
  ];

  static final $core.Map<$core.int, TwinSyncType> _byValue = $pb.ProtobufEnum.initByValue(values);
  static TwinSyncType? valueOf($core.int value) => _byValue[value];

  const TwinSyncType._($core.int v, $core.String n) : super(v, n);
}

class DevicePlatform extends $pb.ProtobufEnum {
  static const DevicePlatform PLATFORM_UNKNOWN = DevicePlatform._(0, _omitEnumNames ? '' : 'PLATFORM_UNKNOWN');
  static const DevicePlatform PLATFORM_ANDROID = DevicePlatform._(1, _omitEnumNames ? '' : 'PLATFORM_ANDROID');
  static const DevicePlatform PLATFORM_IOS = DevicePlatform._(2, _omitEnumNames ? '' : 'PLATFORM_IOS');
  static const DevicePlatform PLATFORM_LINUX = DevicePlatform._(3, _omitEnumNames ? '' : 'PLATFORM_LINUX');
  static const DevicePlatform PLATFORM_WINDOWS = DevicePlatform._(4, _omitEnumNames ? '' : 'PLATFORM_WINDOWS');
  static const DevicePlatform PLATFORM_MACOS = DevicePlatform._(5, _omitEnumNames ? '' : 'PLATFORM_MACOS');

  static const $core.List<DevicePlatform> values = <DevicePlatform> [
    PLATFORM_UNKNOWN,
    PLATFORM_ANDROID,
    PLATFORM_IOS,
    PLATFORM_LINUX,
    PLATFORM_WINDOWS,
    PLATFORM_MACOS,
  ];

  static final $core.Map<$core.int, DevicePlatform> _byValue = $pb.ProtobufEnum.initByValue(values);
  static DevicePlatform? valueOf($core.int value) => _byValue[value];

  const DevicePlatform._($core.int v, $core.String n) : super(v, n);
}

class EventCategory extends $pb.ProtobufEnum {
  static const EventCategory APPOINTMENT = EventCategory._(0, _omitEnumNames ? '' : 'APPOINTMENT');
  static const EventCategory TASK = EventCategory._(1, _omitEnumNames ? '' : 'TASK');
  static const EventCategory BIRTHDAY = EventCategory._(2, _omitEnumNames ? '' : 'BIRTHDAY');
  static const EventCategory REMINDER = EventCategory._(3, _omitEnumNames ? '' : 'REMINDER');
  static const EventCategory MEETING = EventCategory._(4, _omitEnumNames ? '' : 'MEETING');

  static const $core.List<EventCategory> values = <EventCategory> [
    APPOINTMENT,
    TASK,
    BIRTHDAY,
    REMINDER,
    MEETING,
  ];

  static final $core.Map<$core.int, EventCategory> _byValue = $pb.ProtobufEnum.initByValue(values);
  static EventCategory? valueOf($core.int value) => _byValue[value];

  const EventCategory._($core.int v, $core.String n) : super(v, n);
}

class FreeBusyLevel extends $pb.ProtobufEnum {
  static const FreeBusyLevel FB_FULL = FreeBusyLevel._(0, _omitEnumNames ? '' : 'FB_FULL');
  static const FreeBusyLevel FB_TIME_ONLY = FreeBusyLevel._(1, _omitEnumNames ? '' : 'FB_TIME_ONLY');
  static const FreeBusyLevel FB_HIDDEN = FreeBusyLevel._(2, _omitEnumNames ? '' : 'FB_HIDDEN');

  static const $core.List<FreeBusyLevel> values = <FreeBusyLevel> [
    FB_FULL,
    FB_TIME_ONLY,
    FB_HIDDEN,
  ];

  static final $core.Map<$core.int, FreeBusyLevel> _byValue = $pb.ProtobufEnum.initByValue(values);
  static FreeBusyLevel? valueOf($core.int value) => _byValue[value];

  const FreeBusyLevel._($core.int v, $core.String n) : super(v, n);
}

class RsvpStatus extends $pb.ProtobufEnum {
  static const RsvpStatus RSVP_ACCEPTED = RsvpStatus._(0, _omitEnumNames ? '' : 'RSVP_ACCEPTED');
  static const RsvpStatus RSVP_DECLINED = RsvpStatus._(1, _omitEnumNames ? '' : 'RSVP_DECLINED');
  static const RsvpStatus RSVP_TENTATIVE = RsvpStatus._(2, _omitEnumNames ? '' : 'RSVP_TENTATIVE');
  static const RsvpStatus RSVP_PROPOSE_NEW_TIME = RsvpStatus._(3, _omitEnumNames ? '' : 'RSVP_PROPOSE_NEW_TIME');

  static const $core.List<RsvpStatus> values = <RsvpStatus> [
    RSVP_ACCEPTED,
    RSVP_DECLINED,
    RSVP_TENTATIVE,
    RSVP_PROPOSE_NEW_TIME,
  ];

  static final $core.Map<$core.int, RsvpStatus> _byValue = $pb.ProtobufEnum.initByValue(values);
  static RsvpStatus? valueOf($core.int value) => _byValue[value];

  const RsvpStatus._($core.int v, $core.String n) : super(v, n);
}

class PollType extends $pb.ProtobufEnum {
  static const PollType POLL_SINGLE_CHOICE = PollType._(0, _omitEnumNames ? '' : 'POLL_SINGLE_CHOICE');
  static const PollType POLL_MULTIPLE_CHOICE = PollType._(1, _omitEnumNames ? '' : 'POLL_MULTIPLE_CHOICE');
  static const PollType POLL_DATE = PollType._(2, _omitEnumNames ? '' : 'POLL_DATE');
  static const PollType POLL_SCALE = PollType._(3, _omitEnumNames ? '' : 'POLL_SCALE');
  static const PollType POLL_FREE_TEXT = PollType._(4, _omitEnumNames ? '' : 'POLL_FREE_TEXT');

  static const $core.List<PollType> values = <PollType> [
    POLL_SINGLE_CHOICE,
    POLL_MULTIPLE_CHOICE,
    POLL_DATE,
    POLL_SCALE,
    POLL_FREE_TEXT,
  ];

  static final $core.Map<$core.int, PollType> _byValue = $pb.ProtobufEnum.initByValue(values);
  static PollType? valueOf($core.int value) => _byValue[value];

  const PollType._($core.int v, $core.String n) : super(v, n);
}

class PollAction extends $pb.ProtobufEnum {
  static const PollAction POLL_ACTION_CLOSE = PollAction._(0, _omitEnumNames ? '' : 'POLL_ACTION_CLOSE');
  static const PollAction POLL_ACTION_REOPEN = PollAction._(1, _omitEnumNames ? '' : 'POLL_ACTION_REOPEN');
  static const PollAction POLL_ACTION_ADD_OPTIONS = PollAction._(2, _omitEnumNames ? '' : 'POLL_ACTION_ADD_OPTIONS');
  static const PollAction POLL_ACTION_REMOVE_OPTIONS = PollAction._(3, _omitEnumNames ? '' : 'POLL_ACTION_REMOVE_OPTIONS');
  static const PollAction POLL_ACTION_EXTEND_DEADLINE = PollAction._(4, _omitEnumNames ? '' : 'POLL_ACTION_EXTEND_DEADLINE');
  static const PollAction POLL_ACTION_DELETE = PollAction._(5, _omitEnumNames ? '' : 'POLL_ACTION_DELETE');

  static const $core.List<PollAction> values = <PollAction> [
    POLL_ACTION_CLOSE,
    POLL_ACTION_REOPEN,
    POLL_ACTION_ADD_OPTIONS,
    POLL_ACTION_REMOVE_OPTIONS,
    POLL_ACTION_EXTEND_DEADLINE,
    POLL_ACTION_DELETE,
  ];

  static final $core.Map<$core.int, PollAction> _byValue = $pb.ProtobufEnum.initByValue(values);
  static PollAction? valueOf($core.int value) => _byValue[value];

  const PollAction._($core.int v, $core.String n) : super(v, n);
}

class DateAvailability extends $pb.ProtobufEnum {
  static const DateAvailability DATE_AVAIL_YES = DateAvailability._(0, _omitEnumNames ? '' : 'DATE_AVAIL_YES');
  static const DateAvailability DATE_AVAIL_NO = DateAvailability._(1, _omitEnumNames ? '' : 'DATE_AVAIL_NO');
  static const DateAvailability DATE_AVAIL_MAYBE = DateAvailability._(2, _omitEnumNames ? '' : 'DATE_AVAIL_MAYBE');

  static const $core.List<DateAvailability> values = <DateAvailability> [
    DATE_AVAIL_YES,
    DATE_AVAIL_NO,
    DATE_AVAIL_MAYBE,
  ];

  static final $core.Map<$core.int, DateAvailability> _byValue = $pb.ProtobufEnum.initByValue(values);
  static DateAvailability? valueOf($core.int value) => _byValue[value];

  const DateAvailability._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');

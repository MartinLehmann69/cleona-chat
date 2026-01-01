//
//  Generated code. Do not modify.
//  source: proto/cleona.proto
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

class AddressType extends $pb.ProtobufEnum {
  static const AddressType IPV4_PUBLIC = AddressType._(0, _omitEnumNames ? '' : 'IPV4_PUBLIC');
  static const AddressType IPV4_PRIVATE = AddressType._(1, _omitEnumNames ? '' : 'IPV4_PRIVATE');
  static const AddressType IPV6_GLOBAL = AddressType._(2, _omitEnumNames ? '' : 'IPV6_GLOBAL');
  static const AddressType IPV6_ULA = AddressType._(3, _omitEnumNames ? '' : 'IPV6_ULA');
  static const AddressType IPV6_LINK_LOCAL = AddressType._(4, _omitEnumNames ? '' : 'IPV6_LINK_LOCAL');
  static const AddressType IPV6_SITE_LOCAL = AddressType._(5, _omitEnumNames ? '' : 'IPV6_SITE_LOCAL');

  static const $core.List<AddressType> values = <AddressType> [
    IPV4_PUBLIC,
    IPV4_PRIVATE,
    IPV6_GLOBAL,
    IPV6_ULA,
    IPV6_LINK_LOCAL,
    IPV6_SITE_LOCAL,
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

/// Capabilities bitmask for DeviceDelegationCert. Primary-only ops (rotate,
/// revoke, pair, sign-manifest) are NOT representable — they require the
/// master seed which linked devices never hold.
class DeviceDelegationCapability extends $pb.ProtobufEnum {
  static const DeviceDelegationCapability DDC_UNSPECIFIED = DeviceDelegationCapability._(0, _omitEnumNames ? '' : 'DDC_UNSPECIFIED');
  static const DeviceDelegationCapability DDC_SEND_MESSAGES = DeviceDelegationCapability._(1, _omitEnumNames ? '' : 'DDC_SEND_MESSAGES');
  static const DeviceDelegationCapability DDC_MANAGE_CONTACTS = DeviceDelegationCapability._(2, _omitEnumNames ? '' : 'DDC_MANAGE_CONTACTS');
  static const DeviceDelegationCapability DDC_MANAGE_GROUPS = DeviceDelegationCapability._(4, _omitEnumNames ? '' : 'DDC_MANAGE_GROUPS');
  static const DeviceDelegationCapability DDC_MANAGE_CHANNELS = DeviceDelegationCapability._(8, _omitEnumNames ? '' : 'DDC_MANAGE_CHANNELS');
  static const DeviceDelegationCapability DDC_ALL_STANDARD = DeviceDelegationCapability._(15, _omitEnumNames ? '' : 'DDC_ALL_STANDARD');

  static const $core.List<DeviceDelegationCapability> values = <DeviceDelegationCapability> [
    DDC_UNSPECIFIED,
    DDC_SEND_MESSAGES,
    DDC_MANAGE_CONTACTS,
    DDC_MANAGE_GROUPS,
    DDC_MANAGE_CHANNELS,
    DDC_ALL_STANDARD,
  ];

  static final $core.Map<$core.int, DeviceDelegationCapability> _byValue = $pb.ProtobufEnum.initByValue(values);
  static DeviceDelegationCapability? valueOf($core.int value) => _byValue[value];

  const DeviceDelegationCapability._($core.int v, $core.String n) : super(v, n);
}

class PayloadTypeV3 extends $pb.ProtobufEnum {
  static const PayloadTypeV3 PAYLOAD_APPLICATION_FRAME = PayloadTypeV3._(0, _omitEnumNames ? '' : 'PAYLOAD_APPLICATION_FRAME');
  static const PayloadTypeV3 PAYLOAD_ONION_LAYER = PayloadTypeV3._(1, _omitEnumNames ? '' : 'PAYLOAD_ONION_LAYER');
  static const PayloadTypeV3 PAYLOAD_INFRASTRUCTURE_FRAME = PayloadTypeV3._(2, _omitEnumNames ? '' : 'PAYLOAD_INFRASTRUCTURE_FRAME');
  static const PayloadTypeV3 PAYLOAD_BOOTSTRAP_INFRASTRUCTURE_FRAME = PayloadTypeV3._(3, _omitEnumNames ? '' : 'PAYLOAD_BOOTSTRAP_INFRASTRUCTURE_FRAME');

  static const $core.List<PayloadTypeV3> values = <PayloadTypeV3> [
    PAYLOAD_APPLICATION_FRAME,
    PAYLOAD_ONION_LAYER,
    PAYLOAD_INFRASTRUCTURE_FRAME,
    PAYLOAD_BOOTSTRAP_INFRASTRUCTURE_FRAME,
  ];

  static final $core.Map<$core.int, PayloadTypeV3> _byValue = $pb.ProtobufEnum.initByValue(values);
  static PayloadTypeV3? valueOf($core.int value) => _byValue[value];

  const PayloadTypeV3._($core.int v, $core.String n) : super(v, n);
}

///  ── MessageType V3 (Numbering aus Appendix A.4) ─────────────────────────
///
///  ACHTUNG: Numbers WEICHEN VON MessageType (alt) AB. Beispiele:
///    alt: RESTORE_BROADCAST=13   → V3: MTV3_RESTORE_BROADCAST=30
///    alt: TWIN_SYNC=131          → V3: MTV3_TWIN_SYNC=180
///  Hard-Cut in Welle 2 (Profile-Reset, §23.2). Bis dahin koexistieren beide
///  Enums problemlos weil sie verschiedene Namen haben.
///
///  Prefix MTV3_ um Symbol-Kollision mit MessageType (alt) zu vermeiden.
///  In Welle 2 wird Prefix entfernt + Enum auf MessageType umbenannt.
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
  static const MessageTypeV3 MTV3_GUARDIAN_SHARE_STORE = MessageTypeV3._(35, _omitEnumNames ? '' : 'MTV3_GUARDIAN_SHARE_STORE');
  static const MessageTypeV3 MTV3_GUARDIAN_RESTORE_REQUEST = MessageTypeV3._(36, _omitEnumNames ? '' : 'MTV3_GUARDIAN_RESTORE_REQUEST');
  static const MessageTypeV3 MTV3_GUARDIAN_RESTORE_RESPONSE = MessageTypeV3._(37, _omitEnumNames ? '' : 'MTV3_GUARDIAN_RESTORE_RESPONSE');
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
  static const MessageTypeV3 MTV3_CALL_GROUP_KEY_ROTATE = MessageTypeV3._(81, _omitEnumNames ? '' : 'MTV3_CALL_GROUP_KEY_ROTATE');
  static const MessageTypeV3 MTV3_CALL_RTT_PING = MessageTypeV3._(82, _omitEnumNames ? '' : 'MTV3_CALL_RTT_PING');
  static const MessageTypeV3 MTV3_CALL_RTT_PONG = MessageTypeV3._(83, _omitEnumNames ? '' : 'MTV3_CALL_RTT_PONG');
  static const MessageTypeV3 MTV3_CALL_TREE_UPDATE = MessageTypeV3._(84, _omitEnumNames ? '' : 'MTV3_CALL_TREE_UPDATE');
  static const MessageTypeV3 MTV3_CALL_KEYFRAME_REQUEST = MessageTypeV3._(85, _omitEnumNames ? '' : 'MTV3_CALL_KEYFRAME_REQUEST');
  static const MessageTypeV3 MTV3_CALL_GROUP_SENDER_KEY = MessageTypeV3._(86, _omitEnumNames ? '' : 'MTV3_CALL_GROUP_SENDER_KEY');
  static const MessageTypeV3 MTV3_CHANNEL_INDEX_EXCHANGE = MessageTypeV3._(90, _omitEnumNames ? '' : 'MTV3_CHANNEL_INDEX_EXCHANGE');
  static const MessageTypeV3 MTV3_CHANNEL_JOIN_REQUEST = MessageTypeV3._(91, _omitEnumNames ? '' : 'MTV3_CHANNEL_JOIN_REQUEST');
  static const MessageTypeV3 MTV3_CHANNEL_REPORT = MessageTypeV3._(92, _omitEnumNames ? '' : 'MTV3_CHANNEL_REPORT');
  static const MessageTypeV3 MTV3_PEER_LIST_PUSH = MessageTypeV3._(100, _omitEnumNames ? '' : 'MTV3_PEER_LIST_PUSH');
  static const MessageTypeV3 MTV3_PEER_LIST_SUMMARY = MessageTypeV3._(101, _omitEnumNames ? '' : 'MTV3_PEER_LIST_SUMMARY');
  static const MessageTypeV3 MTV3_PEER_LIST_WANT = MessageTypeV3._(102, _omitEnumNames ? '' : 'MTV3_PEER_LIST_WANT');
  static const MessageTypeV3 MTV3_PEER_KEY_REQUEST = MessageTypeV3._(103, _omitEnumNames ? '' : 'MTV3_PEER_KEY_REQUEST');
  static const MessageTypeV3 MTV3_PEER_KEY_RESPONSE = MessageTypeV3._(104, _omitEnumNames ? '' : 'MTV3_PEER_KEY_RESPONSE');
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
  static const MessageTypeV3 MTV3_PEER_STORE = MessageTypeV3._(130, _omitEnumNames ? '' : 'MTV3_PEER_STORE');
  static const MessageTypeV3 MTV3_PEER_STORE_ACK = MessageTypeV3._(131, _omitEnumNames ? '' : 'MTV3_PEER_STORE_ACK');
  static const MessageTypeV3 MTV3_PEER_RETRIEVE = MessageTypeV3._(132, _omitEnumNames ? '' : 'MTV3_PEER_RETRIEVE');
  static const MessageTypeV3 MTV3_PEER_RETRIEVE_RESPONSE = MessageTypeV3._(133, _omitEnumNames ? '' : 'MTV3_PEER_RETRIEVE_RESPONSE');
  static const MessageTypeV3 MTV3_CHAT_CONFIG_UPDATE = MessageTypeV3._(140, _omitEnumNames ? '' : 'MTV3_CHAT_CONFIG_UPDATE');
  static const MessageTypeV3 MTV3_CHAT_CONFIG_RESPONSE = MessageTypeV3._(141, _omitEnumNames ? '' : 'MTV3_CHAT_CONFIG_RESPONSE');
  static const MessageTypeV3 MTV3_ROUTE_UPDATE = MessageTypeV3._(150, _omitEnumNames ? '' : 'MTV3_ROUTE_UPDATE');
  static const MessageTypeV3 MTV3_REACHABILITY_QUERY = MessageTypeV3._(151, _omitEnumNames ? '' : 'MTV3_REACHABILITY_QUERY');
  static const MessageTypeV3 MTV3_REACHABILITY_RESPONSE = MessageTypeV3._(152, _omitEnumNames ? '' : 'MTV3_REACHABILITY_RESPONSE');
  static const MessageTypeV3 MTV3_RELAY_FORWARD = MessageTypeV3._(153, _omitEnumNames ? '' : 'MTV3_RELAY_FORWARD');
  static const MessageTypeV3 MTV3_RELAY_ACK = MessageTypeV3._(154, _omitEnumNames ? '' : 'MTV3_RELAY_ACK');
  static const MessageTypeV3 MTV3_HOLE_PUNCH_REQUEST = MessageTypeV3._(160, _omitEnumNames ? '' : 'MTV3_HOLE_PUNCH_REQUEST');
  static const MessageTypeV3 MTV3_HOLE_PUNCH_NOTIFY = MessageTypeV3._(161, _omitEnumNames ? '' : 'MTV3_HOLE_PUNCH_NOTIFY');
  static const MessageTypeV3 MTV3_HOLE_PUNCH_PING = MessageTypeV3._(162, _omitEnumNames ? '' : 'MTV3_HOLE_PUNCH_PING');
  static const MessageTypeV3 MTV3_HOLE_PUNCH_PONG = MessageTypeV3._(163, _omitEnumNames ? '' : 'MTV3_HOLE_PUNCH_PONG');
  static const MessageTypeV3 MTV3_IDENTITY_AUTH_PUBLISH = MessageTypeV3._(170, _omitEnumNames ? '' : 'MTV3_IDENTITY_AUTH_PUBLISH');
  static const MessageTypeV3 MTV3_IDENTITY_AUTH_RETRIEVE = MessageTypeV3._(171, _omitEnumNames ? '' : 'MTV3_IDENTITY_AUTH_RETRIEVE');
  static const MessageTypeV3 MTV3_IDENTITY_AUTH_RESPONSE = MessageTypeV3._(172, _omitEnumNames ? '' : 'MTV3_IDENTITY_AUTH_RESPONSE');
  static const MessageTypeV3 MTV3_IDENTITY_LIVE_PUBLISH = MessageTypeV3._(173, _omitEnumNames ? '' : 'MTV3_IDENTITY_LIVE_PUBLISH');
  static const MessageTypeV3 MTV3_IDENTITY_LIVE_RETRIEVE = MessageTypeV3._(174, _omitEnumNames ? '' : 'MTV3_IDENTITY_LIVE_RETRIEVE');
  static const MessageTypeV3 MTV3_IDENTITY_LIVE_RESPONSE = MessageTypeV3._(175, _omitEnumNames ? '' : 'MTV3_IDENTITY_LIVE_RESPONSE');
  static const MessageTypeV3 MTV3_IDENTITY_KEM_PUBLISH = MessageTypeV3._(176, _omitEnumNames ? '' : 'MTV3_IDENTITY_KEM_PUBLISH');
  static const MessageTypeV3 MTV3_IDENTITY_KEM_RETRIEVE = MessageTypeV3._(177, _omitEnumNames ? '' : 'MTV3_IDENTITY_KEM_RETRIEVE');
  static const MessageTypeV3 MTV3_IDENTITY_KEM_RESPONSE = MessageTypeV3._(178, _omitEnumNames ? '' : 'MTV3_IDENTITY_KEM_RESPONSE');
  static const MessageTypeV3 MTV3_TWIN_SYNC = MessageTypeV3._(180, _omitEnumNames ? '' : 'MTV3_TWIN_SYNC');
  static const MessageTypeV3 MTV3_DEVICE_PAIR_REQUEST = MessageTypeV3._(181, _omitEnumNames ? '' : 'MTV3_DEVICE_PAIR_REQUEST');
  static const MessageTypeV3 MTV3_DEVICE_PAIR_APPROVE = MessageTypeV3._(182, _omitEnumNames ? '' : 'MTV3_DEVICE_PAIR_APPROVE');
  static const MessageTypeV3 MTV3_DEVICE_REVOCATION = MessageTypeV3._(183, _omitEnumNames ? '' : 'MTV3_DEVICE_REVOCATION');
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
  static const MessageTypeV3 MTV3_DEVICE_KEM_REQUEST = MessageTypeV3._(220, _omitEnumNames ? '' : 'MTV3_DEVICE_KEM_REQUEST');
  static const MessageTypeV3 MTV3_DEVICE_KEM_OFFER = MessageTypeV3._(221, _omitEnumNames ? '' : 'MTV3_DEVICE_KEM_OFFER');
  static const MessageTypeV3 MTV3_FIRST_CR_STORE = MessageTypeV3._(222, _omitEnumNames ? '' : 'MTV3_FIRST_CR_STORE');
  static const MessageTypeV3 MTV3_FIRST_CR_STORE_ACK = MessageTypeV3._(223, _omitEnumNames ? '' : 'MTV3_FIRST_CR_STORE_ACK');
  static const MessageTypeV3 MTV3_FIRST_CR_DELIVER = MessageTypeV3._(224, _omitEnumNames ? '' : 'MTV3_FIRST_CR_DELIVER');
  static const MessageTypeV3 MTV3_POLL_ANON_SUBMIT = MessageTypeV3._(225, _omitEnumNames ? '' : 'MTV3_POLL_ANON_SUBMIT');
  static const MessageTypeV3 MTV3_POLL_ANON_SUBMIT_ACK = MessageTypeV3._(226, _omitEnumNames ? '' : 'MTV3_POLL_ANON_SUBMIT_ACK');

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
    MTV3_GUARDIAN_SHARE_STORE,
    MTV3_GUARDIAN_RESTORE_REQUEST,
    MTV3_GUARDIAN_RESTORE_RESPONSE,
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
    MTV3_CALL_GROUP_KEY_ROTATE,
    MTV3_CALL_RTT_PING,
    MTV3_CALL_RTT_PONG,
    MTV3_CALL_TREE_UPDATE,
    MTV3_CALL_KEYFRAME_REQUEST,
    MTV3_CALL_GROUP_SENDER_KEY,
    MTV3_CHANNEL_INDEX_EXCHANGE,
    MTV3_CHANNEL_JOIN_REQUEST,
    MTV3_CHANNEL_REPORT,
    MTV3_PEER_LIST_PUSH,
    MTV3_PEER_LIST_SUMMARY,
    MTV3_PEER_LIST_WANT,
    MTV3_PEER_KEY_REQUEST,
    MTV3_PEER_KEY_RESPONSE,
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
    MTV3_PEER_STORE,
    MTV3_PEER_STORE_ACK,
    MTV3_PEER_RETRIEVE,
    MTV3_PEER_RETRIEVE_RESPONSE,
    MTV3_CHAT_CONFIG_UPDATE,
    MTV3_CHAT_CONFIG_RESPONSE,
    MTV3_ROUTE_UPDATE,
    MTV3_REACHABILITY_QUERY,
    MTV3_REACHABILITY_RESPONSE,
    MTV3_RELAY_FORWARD,
    MTV3_RELAY_ACK,
    MTV3_HOLE_PUNCH_REQUEST,
    MTV3_HOLE_PUNCH_NOTIFY,
    MTV3_HOLE_PUNCH_PING,
    MTV3_HOLE_PUNCH_PONG,
    MTV3_IDENTITY_AUTH_PUBLISH,
    MTV3_IDENTITY_AUTH_RETRIEVE,
    MTV3_IDENTITY_AUTH_RESPONSE,
    MTV3_IDENTITY_LIVE_PUBLISH,
    MTV3_IDENTITY_LIVE_RETRIEVE,
    MTV3_IDENTITY_LIVE_RESPONSE,
    MTV3_IDENTITY_KEM_PUBLISH,
    MTV3_IDENTITY_KEM_RETRIEVE,
    MTV3_IDENTITY_KEM_RESPONSE,
    MTV3_TWIN_SYNC,
    MTV3_DEVICE_PAIR_REQUEST,
    MTV3_DEVICE_PAIR_APPROVE,
    MTV3_DEVICE_REVOCATION,
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
    MTV3_DEVICE_KEM_REQUEST,
    MTV3_DEVICE_KEM_OFFER,
    MTV3_FIRST_CR_STORE,
    MTV3_FIRST_CR_STORE_ACK,
    MTV3_FIRST_CR_DELIVER,
    MTV3_POLL_ANON_SUBMIT,
    MTV3_POLL_ANON_SUBMIT_ACK,
  ];

  static final $core.Map<$core.int, MessageTypeV3> _byValue = $pb.ProtobufEnum.initByValue(values);
  static MessageTypeV3? valueOf($core.int value) => _byValue[value];

  const MessageTypeV3._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');

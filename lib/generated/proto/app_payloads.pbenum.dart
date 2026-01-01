//
//  Generated code. Do not modify.
//  source: app_payloads.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

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

///  ── Own-video state (§10.6, Spec-Erratum E2) ──────────────────────────
///
///  Why a sender is currently not sending video. Meaningful ONLY while
///  CallMediaState.sending_video == false.
///
///  Invariante I12 — this is a statement about the SENDER'S OWN transmission.
///  It is not an instruction to the peer and grants no control over the peer's
///  camera. No value here may ever mean "switch your video off"; a message with
///  that meaning does not exist in this protocol and must not be added.
///
///  OPEN enumeration. The extension rule is binding for every future change:
///    * a new reason gets a NEW number. Existing numbers are never reused,
///      never renumbered, never redefined.
///    * a receiver that does not recognise a value MUST fall back to
///      VIDEO_OFF_REASON_UNSPECIFIED — "no picture, and this build does not
///      know why" — and MUST NOT map it onto a reason it does know. Folding an
///      unknown reason into USER_DISABLED would state the peer's intent as a
///      fact without evidence, which is the exact confusion E2 exists to
///      remove.
///  proto3 open-enum decoding already yields that fallback: an unrecognised
///  value is kept in the unknown fields and the getter returns 0.
class VideoOffReason extends $pb.ProtobufEnum {
  static const VideoOffReason VIDEO_OFF_REASON_UNSPECIFIED = VideoOffReason._(0, _omitEnumNames ? '' : 'VIDEO_OFF_REASON_UNSPECIFIED');
  static const VideoOffReason VIDEO_OFF_REASON_USER_DISABLED = VideoOffReason._(1, _omitEnumNames ? '' : 'VIDEO_OFF_REASON_USER_DISABLED');
  static const VideoOffReason VIDEO_OFF_REASON_BANDWIDTH_INSUFFICIENT = VideoOffReason._(2, _omitEnumNames ? '' : 'VIDEO_OFF_REASON_BANDWIDTH_INSUFFICIENT');

  static const $core.List<VideoOffReason> values = <VideoOffReason> [
    VIDEO_OFF_REASON_UNSPECIFIED,
    VIDEO_OFF_REASON_USER_DISABLED,
    VIDEO_OFF_REASON_BANDWIDTH_INSUFFICIENT,
  ];

  static final $core.Map<$core.int, VideoOffReason> _byValue = $pb.ProtobufEnum.initByValue(values);
  static VideoOffReason? valueOf($core.int value) => _byValue[value];

  const VideoOffReason._($core.int v, $core.String n) : super(v, n);
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
  static const TwinSyncType ROTATION_APPROVAL_REQUEST = TwinSyncType._(12, _omitEnumNames ? '' : 'ROTATION_APPROVAL_REQUEST');
  static const TwinSyncType ROTATION_APPROVAL_RESPONSE = TwinSyncType._(13, _omitEnumNames ? '' : 'ROTATION_APPROVAL_RESPONSE');
  static const TwinSyncType TWIN_IDENTITY_DELETED = TwinSyncType._(17, _omitEnumNames ? '' : 'TWIN_IDENTITY_DELETED');

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
    ROTATION_APPROVAL_REQUEST,
    ROTATION_APPROVAL_RESPONSE,
    TWIN_IDENTITY_DELETED,
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

/// TwinSync payload for ROTATION_APPROVAL_REQUEST (Primary → Linked).
/// Occasion of an approval request. Without the discriminator the
/// linked device reports every request as "Emergency Key Rotation genehmigen?" —
/// a device set change would thus be confirmed under a false description
/// (§7.5). Field 6 default 0 = rotation, so that old senders
/// are interpreted unchanged.
class ApprovalKindV3 extends $pb.ProtobufEnum {
  static const ApprovalKindV3 APPROVAL_KIND_KEY_ROTATION = ApprovalKindV3._(0, _omitEnumNames ? '' : 'APPROVAL_KIND_KEY_ROTATION');
  static const ApprovalKindV3 APPROVAL_KIND_DEVICE_SET_CHANGE = ApprovalKindV3._(1, _omitEnumNames ? '' : 'APPROVAL_KIND_DEVICE_SET_CHANGE');

  static const $core.List<ApprovalKindV3> values = <ApprovalKindV3> [
    APPROVAL_KIND_KEY_ROTATION,
    APPROVAL_KIND_DEVICE_SET_CHANGE,
  ];

  static final $core.Map<$core.int, ApprovalKindV3> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ApprovalKindV3? valueOf($core.int value) => _byValue[value];

  const ApprovalKindV3._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');

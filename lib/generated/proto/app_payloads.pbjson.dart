//
//  Generated code. Do not modify.
//  source: app_payloads.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use addressTypeDescriptor instead')
const AddressType$json = {
  '1': 'AddressType',
  '2': [
    {'1': 'IPV4_PUBLIC', '2': 0},
    {'1': 'IPV4_PRIVATE', '2': 1},
    {'1': 'IPV6_GLOBAL', '2': 2},
    {'1': 'IPV6_ULA', '2': 3},
    {'1': 'IPV6_LINK_LOCAL', '2': 4},
    {'1': 'IPV6_SITE_LOCAL', '2': 5},
  ],
};

/// Descriptor for `AddressType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List addressTypeDescriptor = $convert.base64Decode(
    'CgtBZGRyZXNzVHlwZRIPCgtJUFY0X1BVQkxJQxAAEhAKDElQVjRfUFJJVkFURRABEg8KC0lQVj'
    'ZfR0xPQkFMEAISDAoISVBWNl9VTEEQAxITCg9JUFY2X0xJTktfTE9DQUwQBBITCg9JUFY2X1NJ'
    'VEVfTE9DQUwQBQ==');

@$core.Deprecated('Use videoOffReasonDescriptor instead')
const VideoOffReason$json = {
  '1': 'VideoOffReason',
  '2': [
    {'1': 'VIDEO_OFF_REASON_UNSPECIFIED', '2': 0},
    {'1': 'VIDEO_OFF_REASON_USER_DISABLED', '2': 1},
    {'1': 'VIDEO_OFF_REASON_BANDWIDTH_INSUFFICIENT', '2': 2},
  ],
};

/// Descriptor for `VideoOffReason`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List videoOffReasonDescriptor = $convert.base64Decode(
    'Cg5WaWRlb09mZlJlYXNvbhIgChxWSURFT19PRkZfUkVBU09OX1VOU1BFQ0lGSUVEEAASIgoeVk'
    'lERU9fT0ZGX1JFQVNPTl9VU0VSX0RJU0FCTEVEEAESKwonVklERU9fT0ZGX1JFQVNPTl9CQU5E'
    'V0lEVEhfSU5TVUZGSUNJRU5UEAI=');

@$core.Deprecated('Use twinSyncTypeDescriptor instead')
const TwinSyncType$json = {
  '1': 'TwinSyncType',
  '2': [
    {'1': 'CONTACT_ADDED', '2': 0},
    {'1': 'CONTACT_DELETED', '2': 1},
    {'1': 'MESSAGE_SENT', '2': 2},
    {'1': 'MESSAGE_EDITED', '2': 3},
    {'1': 'MESSAGE_DELETED', '2': 4},
    {'1': 'TWIN_READ_RECEIPT', '2': 5},
    {'1': 'GROUP_CREATED', '2': 6},
    {'1': 'PROFILE_CHANGED', '2': 7},
    {'1': 'SETTINGS_CHANGED', '2': 8},
    {'1': 'DEVICE_ANNOUNCE', '2': 9},
    {'1': 'DEVICE_RENAMED', '2': 10},
    {'1': 'TWIN_DEVICE_REVOKED', '2': 11},
    {'1': 'ROTATION_APPROVAL_REQUEST', '2': 12},
    {'1': 'ROTATION_APPROVAL_RESPONSE', '2': 13},
    {'1': 'TWIN_IDENTITY_DELETED', '2': 17},
  ],
  '4': [
    {'1': 14, '2': 14},
    {'1': 15, '2': 15},
    {'1': 16, '2': 16},
  ],
};

/// Descriptor for `TwinSyncType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List twinSyncTypeDescriptor = $convert.base64Decode(
    'CgxUd2luU3luY1R5cGUSEQoNQ09OVEFDVF9BRERFRBAAEhMKD0NPTlRBQ1RfREVMRVRFRBABEh'
    'AKDE1FU1NBR0VfU0VOVBACEhIKDk1FU1NBR0VfRURJVEVEEAMSEwoPTUVTU0FHRV9ERUxFVEVE'
    'EAQSFQoRVFdJTl9SRUFEX1JFQ0VJUFQQBRIRCg1HUk9VUF9DUkVBVEVEEAYSEwoPUFJPRklMRV'
    '9DSEFOR0VEEAcSFAoQU0VUVElOR1NfQ0hBTkdFRBAIEhMKD0RFVklDRV9BTk5PVU5DRRAJEhIK'
    'DkRFVklDRV9SRU5BTUVEEAoSFwoTVFdJTl9ERVZJQ0VfUkVWT0tFRBALEh0KGVJPVEFUSU9OX0'
    'FQUFJPVkFMX1JFUVVFU1QQDBIeChpST1RBVElPTl9BUFBST1ZBTF9SRVNQT05TRRANEhkKFVRX'
    'SU5fSURFTlRJVFlfREVMRVRFRBARIgQIDhAOIgQIDxAPIgQIEBAQ');

@$core.Deprecated('Use devicePlatformDescriptor instead')
const DevicePlatform$json = {
  '1': 'DevicePlatform',
  '2': [
    {'1': 'PLATFORM_UNKNOWN', '2': 0},
    {'1': 'PLATFORM_ANDROID', '2': 1},
    {'1': 'PLATFORM_IOS', '2': 2},
    {'1': 'PLATFORM_LINUX', '2': 3},
    {'1': 'PLATFORM_WINDOWS', '2': 4},
    {'1': 'PLATFORM_MACOS', '2': 5},
  ],
};

/// Descriptor for `DevicePlatform`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List devicePlatformDescriptor = $convert.base64Decode(
    'Cg5EZXZpY2VQbGF0Zm9ybRIUChBQTEFURk9STV9VTktOT1dOEAASFAoQUExBVEZPUk1fQU5EUk'
    '9JRBABEhAKDFBMQVRGT1JNX0lPUxACEhIKDlBMQVRGT1JNX0xJTlVYEAMSFAoQUExBVEZPUk1f'
    'V0lORE9XUxAEEhIKDlBMQVRGT1JNX01BQ09TEAU=');

@$core.Deprecated('Use eventCategoryDescriptor instead')
const EventCategory$json = {
  '1': 'EventCategory',
  '2': [
    {'1': 'APPOINTMENT', '2': 0},
    {'1': 'TASK', '2': 1},
    {'1': 'BIRTHDAY', '2': 2},
    {'1': 'REMINDER', '2': 3},
    {'1': 'MEETING', '2': 4},
  ],
};

/// Descriptor for `EventCategory`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List eventCategoryDescriptor = $convert.base64Decode(
    'Cg1FdmVudENhdGVnb3J5Eg8KC0FQUE9JTlRNRU5UEAASCAoEVEFTSxABEgwKCEJJUlRIREFZEA'
    'ISDAoIUkVNSU5ERVIQAxILCgdNRUVUSU5HEAQ=');

@$core.Deprecated('Use freeBusyLevelDescriptor instead')
const FreeBusyLevel$json = {
  '1': 'FreeBusyLevel',
  '2': [
    {'1': 'FB_FULL', '2': 0},
    {'1': 'FB_TIME_ONLY', '2': 1},
    {'1': 'FB_HIDDEN', '2': 2},
  ],
};

/// Descriptor for `FreeBusyLevel`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List freeBusyLevelDescriptor = $convert.base64Decode(
    'Cg1GcmVlQnVzeUxldmVsEgsKB0ZCX0ZVTEwQABIQCgxGQl9USU1FX09OTFkQARINCglGQl9ISU'
    'RERU4QAg==');

@$core.Deprecated('Use rsvpStatusDescriptor instead')
const RsvpStatus$json = {
  '1': 'RsvpStatus',
  '2': [
    {'1': 'RSVP_ACCEPTED', '2': 0},
    {'1': 'RSVP_DECLINED', '2': 1},
    {'1': 'RSVP_TENTATIVE', '2': 2},
    {'1': 'RSVP_PROPOSE_NEW_TIME', '2': 3},
  ],
};

/// Descriptor for `RsvpStatus`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List rsvpStatusDescriptor = $convert.base64Decode(
    'CgpSc3ZwU3RhdHVzEhEKDVJTVlBfQUNDRVBURUQQABIRCg1SU1ZQX0RFQ0xJTkVEEAESEgoOUl'
    'NWUF9URU5UQVRJVkUQAhIZChVSU1ZQX1BST1BPU0VfTkVXX1RJTUUQAw==');

@$core.Deprecated('Use pollTypeDescriptor instead')
const PollType$json = {
  '1': 'PollType',
  '2': [
    {'1': 'POLL_SINGLE_CHOICE', '2': 0},
    {'1': 'POLL_MULTIPLE_CHOICE', '2': 1},
    {'1': 'POLL_DATE', '2': 2},
    {'1': 'POLL_SCALE', '2': 3},
    {'1': 'POLL_FREE_TEXT', '2': 4},
  ],
};

/// Descriptor for `PollType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List pollTypeDescriptor = $convert.base64Decode(
    'CghQb2xsVHlwZRIWChJQT0xMX1NJTkdMRV9DSE9JQ0UQABIYChRQT0xMX01VTFRJUExFX0NIT0'
    'lDRRABEg0KCVBPTExfREFURRACEg4KClBPTExfU0NBTEUQAxISCg5QT0xMX0ZSRUVfVEVYVBAE');

@$core.Deprecated('Use pollActionDescriptor instead')
const PollAction$json = {
  '1': 'PollAction',
  '2': [
    {'1': 'POLL_ACTION_CLOSE', '2': 0},
    {'1': 'POLL_ACTION_REOPEN', '2': 1},
    {'1': 'POLL_ACTION_ADD_OPTIONS', '2': 2},
    {'1': 'POLL_ACTION_REMOVE_OPTIONS', '2': 3},
    {'1': 'POLL_ACTION_EXTEND_DEADLINE', '2': 4},
    {'1': 'POLL_ACTION_DELETE', '2': 5},
  ],
};

/// Descriptor for `PollAction`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List pollActionDescriptor = $convert.base64Decode(
    'CgpQb2xsQWN0aW9uEhUKEVBPTExfQUNUSU9OX0NMT1NFEAASFgoSUE9MTF9BQ1RJT05fUkVPUE'
    'VOEAESGwoXUE9MTF9BQ1RJT05fQUREX09QVElPTlMQAhIeChpQT0xMX0FDVElPTl9SRU1PVkVf'
    'T1BUSU9OUxADEh8KG1BPTExfQUNUSU9OX0VYVEVORF9ERUFETElORRAEEhYKElBPTExfQUNUSU'
    '9OX0RFTEVURRAF');

@$core.Deprecated('Use dateAvailabilityDescriptor instead')
const DateAvailability$json = {
  '1': 'DateAvailability',
  '2': [
    {'1': 'DATE_AVAIL_YES', '2': 0},
    {'1': 'DATE_AVAIL_NO', '2': 1},
    {'1': 'DATE_AVAIL_MAYBE', '2': 2},
  ],
};

/// Descriptor for `DateAvailability`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List dateAvailabilityDescriptor = $convert.base64Decode(
    'ChBEYXRlQXZhaWxhYmlsaXR5EhIKDkRBVEVfQVZBSUxfWUVTEAASEQoNREFURV9BVkFJTF9OTx'
    'ABEhQKEERBVEVfQVZBSUxfTUFZQkUQAg==');

@$core.Deprecated('Use deviceDelegationCapabilityDescriptor instead')
const DeviceDelegationCapability$json = {
  '1': 'DeviceDelegationCapability',
  '2': [
    {'1': 'DDC_UNSPECIFIED', '2': 0},
    {'1': 'DDC_SEND_MESSAGES', '2': 1},
    {'1': 'DDC_MANAGE_CONTACTS', '2': 2},
    {'1': 'DDC_MANAGE_GROUPS', '2': 4},
    {'1': 'DDC_MANAGE_CHANNELS', '2': 8},
    {'1': 'DDC_ALL_STANDARD', '2': 15},
  ],
};

/// Descriptor for `DeviceDelegationCapability`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List deviceDelegationCapabilityDescriptor = $convert.base64Decode(
    'ChpEZXZpY2VEZWxlZ2F0aW9uQ2FwYWJpbGl0eRITCg9ERENfVU5TUEVDSUZJRUQQABIVChFERE'
    'NfU0VORF9NRVNTQUdFUxABEhcKE0REQ19NQU5BR0VfQ09OVEFDVFMQAhIVChFERENfTUFOQUdF'
    'X0dST1VQUxAEEhcKE0REQ19NQU5BR0VfQ0hBTk5FTFMQCBIUChBERENfQUxMX1NUQU5EQVJEEA'
    '8=');

@$core.Deprecated('Use approvalKindV3Descriptor instead')
const ApprovalKindV3$json = {
  '1': 'ApprovalKindV3',
  '2': [
    {'1': 'APPROVAL_KIND_KEY_ROTATION', '2': 0},
    {'1': 'APPROVAL_KIND_DEVICE_SET_CHANGE', '2': 1},
  ],
};

/// Descriptor for `ApprovalKindV3`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List approvalKindV3Descriptor = $convert.base64Decode(
    'Cg5BcHByb3ZhbEtpbmRWMxIeChpBUFBST1ZBTF9LSU5EX0tFWV9ST1RBVElPThAAEiMKH0FQUF'
    'JPVkFMX0tJTkRfREVWSUNFX1NFVF9DSEFOR0UQAQ==');

@$core.Deprecated('Use contentMetadataDescriptor instead')
const ContentMetadata$json = {
  '1': 'ContentMetadata',
  '2': [
    {'1': 'mime_type', '3': 1, '4': 1, '5': 9, '10': 'mimeType'},
    {'1': 'file_size', '3': 2, '4': 1, '5': 4, '10': 'fileSize'},
    {'1': 'filename', '3': 3, '4': 1, '5': 9, '10': 'filename'},
    {'1': 'duration_ms', '3': 4, '4': 1, '5': 13, '10': 'durationMs'},
    {'1': 'thumbnail', '3': 5, '4': 1, '5': 12, '10': 'thumbnail'},
    {'1': 'content_hash', '3': 6, '4': 1, '5': 12, '10': 'contentHash'},
    {'1': 'transcript_text', '3': 7, '4': 1, '5': 9, '10': 'transcriptText'},
    {'1': 'transcript_language', '3': 8, '4': 1, '5': 9, '10': 'transcriptLanguage'},
    {'1': 'transcript_confidence', '3': 9, '4': 1, '5': 2, '10': 'transcriptConfidence'},
  ],
};

/// Descriptor for `ContentMetadata`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List contentMetadataDescriptor = $convert.base64Decode(
    'Cg9Db250ZW50TWV0YWRhdGESGwoJbWltZV90eXBlGAEgASgJUghtaW1lVHlwZRIbCglmaWxlX3'
    'NpemUYAiABKARSCGZpbGVTaXplEhoKCGZpbGVuYW1lGAMgASgJUghmaWxlbmFtZRIfCgtkdXJh'
    'dGlvbl9tcxgEIAEoDVIKZHVyYXRpb25NcxIcCgl0aHVtYm5haWwYBSABKAxSCXRodW1ibmFpbB'
    'IhCgxjb250ZW50X2hhc2gYBiABKAxSC2NvbnRlbnRIYXNoEicKD3RyYW5zY3JpcHRfdGV4dBgH'
    'IAEoCVIOdHJhbnNjcmlwdFRleHQSLwoTdHJhbnNjcmlwdF9sYW5ndWFnZRgIIAEoCVISdHJhbn'
    'NjcmlwdExhbmd1YWdlEjMKFXRyYW5zY3JpcHRfY29uZmlkZW5jZRgJIAEoAlIUdHJhbnNjcmlw'
    'dENvbmZpZGVuY2U=');

@$core.Deprecated('Use linkPreviewDescriptor instead')
const LinkPreview$json = {
  '1': 'LinkPreview',
  '2': [
    {'1': 'url', '3': 1, '4': 1, '5': 9, '10': 'url'},
    {'1': 'title', '3': 2, '4': 1, '5': 9, '10': 'title'},
    {'1': 'description', '3': 3, '4': 1, '5': 9, '10': 'description'},
    {'1': 'site_name', '3': 4, '4': 1, '5': 9, '10': 'siteName'},
    {'1': 'thumbnail', '3': 5, '4': 1, '5': 12, '10': 'thumbnail'},
    {'1': 'fetched_at_ms', '3': 6, '4': 1, '5': 4, '10': 'fetchedAtMs'},
  ],
};

/// Descriptor for `LinkPreview`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List linkPreviewDescriptor = $convert.base64Decode(
    'CgtMaW5rUHJldmlldxIQCgN1cmwYASABKAlSA3VybBIUCgV0aXRsZRgCIAEoCVIFdGl0bGUSIA'
    'oLZGVzY3JpcHRpb24YAyABKAlSC2Rlc2NyaXB0aW9uEhsKCXNpdGVfbmFtZRgEIAEoCVIIc2l0'
    'ZU5hbWUSHAoJdGh1bWJuYWlsGAUgASgMUgl0aHVtYm5haWwSIgoNZmV0Y2hlZF9hdF9tcxgGIA'
    'EoBFILZmV0Y2hlZEF0TXM=');

@$core.Deprecated('Use expiryMetadataDescriptor instead')
const ExpiryMetadata$json = {
  '1': 'ExpiryMetadata',
  '2': [
    {'1': 'expiry_duration_ms', '3': 1, '4': 1, '5': 4, '10': 'expiryDurationMs'},
    {'1': 'edit_window_ms', '3': 2, '4': 1, '5': 4, '10': 'editWindowMs'},
  ],
};

/// Descriptor for `ExpiryMetadata`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List expiryMetadataDescriptor = $convert.base64Decode(
    'Cg5FeHBpcnlNZXRhZGF0YRIsChJleHBpcnlfZHVyYXRpb25fbXMYASABKARSEGV4cGlyeUR1cm'
    'F0aW9uTXMSJAoOZWRpdF93aW5kb3dfbXMYAiABKARSDGVkaXRXaW5kb3dNcw==');

@$core.Deprecated('Use editMetadataDescriptor instead')
const EditMetadata$json = {
  '1': 'EditMetadata',
  '2': [
    {'1': 'original_message_id', '3': 1, '4': 1, '5': 12, '10': 'originalMessageId'},
    {'1': 'edit_timestamp', '3': 2, '4': 1, '5': 4, '10': 'editTimestamp'},
  ],
};

/// Descriptor for `EditMetadata`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List editMetadataDescriptor = $convert.base64Decode(
    'CgxFZGl0TWV0YWRhdGESLgoTb3JpZ2luYWxfbWVzc2FnZV9pZBgBIAEoDFIRb3JpZ2luYWxNZX'
    'NzYWdlSWQSJQoOZWRpdF90aW1lc3RhbXAYAiABKARSDWVkaXRUaW1lc3RhbXA=');

@$core.Deprecated('Use peerAddressProtoDescriptor instead')
const PeerAddressProto$json = {
  '1': 'PeerAddressProto',
  '2': [
    {'1': 'ip', '3': 1, '4': 1, '5': 9, '10': 'ip'},
    {'1': 'port', '3': 2, '4': 1, '5': 13, '10': 'port'},
    {'1': 'address_type', '3': 3, '4': 1, '5': 14, '6': '.cleona.AddressType', '10': 'addressType'},
    {'1': 'score', '3': 4, '4': 1, '5': 1, '10': 'score'},
    {'1': 'last_success', '3': 5, '4': 1, '5': 4, '10': 'lastSuccess'},
    {'1': 'last_attempt', '3': 6, '4': 1, '5': 4, '10': 'lastAttempt'},
    {'1': 'success_count', '3': 7, '4': 1, '5': 13, '10': 'successCount'},
    {'1': 'fail_count', '3': 8, '4': 1, '5': 13, '10': 'failCount'},
  ],
};

/// Descriptor for `PeerAddressProto`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List peerAddressProtoDescriptor = $convert.base64Decode(
    'ChBQZWVyQWRkcmVzc1Byb3RvEg4KAmlwGAEgASgJUgJpcBISCgRwb3J0GAIgASgNUgRwb3J0Ej'
    'YKDGFkZHJlc3NfdHlwZRgDIAEoDjITLmNsZW9uYS5BZGRyZXNzVHlwZVILYWRkcmVzc1R5cGUS'
    'FAoFc2NvcmUYBCABKAFSBXNjb3JlEiEKDGxhc3Rfc3VjY2VzcxgFIAEoBFILbGFzdFN1Y2Nlc3'
    'MSIQoMbGFzdF9hdHRlbXB0GAYgASgEUgtsYXN0QXR0ZW1wdBIjCg1zdWNjZXNzX2NvdW50GAcg'
    'ASgNUgxzdWNjZXNzQ291bnQSHQoKZmFpbF9jb3VudBgIIAEoDVIJZmFpbENvdW50');

@$core.Deprecated('Use contactRequestMsgDescriptor instead')
const ContactRequestMsg$json = {
  '1': 'ContactRequestMsg',
  '2': [
    {'1': 'display_name', '3': 1, '4': 1, '5': 9, '10': 'displayName'},
    {'1': 'ed25519_public_key', '3': 2, '4': 1, '5': 12, '10': 'ed25519PublicKey'},
    {'1': 'ml_dsa_public_key', '3': 3, '4': 1, '5': 12, '10': 'mlDsaPublicKey'},
    {'1': 'x25519_public_key', '3': 4, '4': 1, '5': 12, '10': 'x25519PublicKey'},
    {'1': 'ml_kem_public_key', '3': 5, '4': 1, '5': 12, '10': 'mlKemPublicKey'},
    {'1': 'message', '3': 6, '4': 1, '5': 9, '10': 'message'},
    {'1': 'profile_picture', '3': 7, '4': 1, '5': 12, '10': 'profilePicture'},
    {'1': 'description', '3': 8, '4': 1, '5': 9, '10': 'description'},
  ],
};

/// Descriptor for `ContactRequestMsg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List contactRequestMsgDescriptor = $convert.base64Decode(
    'ChFDb250YWN0UmVxdWVzdE1zZxIhCgxkaXNwbGF5X25hbWUYASABKAlSC2Rpc3BsYXlOYW1lEi'
    'wKEmVkMjU1MTlfcHVibGljX2tleRgCIAEoDFIQZWQyNTUxOVB1YmxpY0tleRIpChFtbF9kc2Ff'
    'cHVibGljX2tleRgDIAEoDFIObWxEc2FQdWJsaWNLZXkSKgoReDI1NTE5X3B1YmxpY19rZXkYBC'
    'ABKAxSD3gyNTUxOVB1YmxpY0tleRIpChFtbF9rZW1fcHVibGljX2tleRgFIAEoDFIObWxLZW1Q'
    'dWJsaWNLZXkSGAoHbWVzc2FnZRgGIAEoCVIHbWVzc2FnZRInCg9wcm9maWxlX3BpY3R1cmUYBy'
    'ABKAxSDnByb2ZpbGVQaWN0dXJlEiAKC2Rlc2NyaXB0aW9uGAggASgJUgtkZXNjcmlwdGlvbg==');

@$core.Deprecated('Use contactRequestResponseDescriptor instead')
const ContactRequestResponse$json = {
  '1': 'ContactRequestResponse',
  '2': [
    {'1': 'accepted', '3': 1, '4': 1, '5': 8, '10': 'accepted'},
    {'1': 'rejection_reason', '3': 2, '4': 1, '5': 9, '10': 'rejectionReason'},
    {'1': 'ed25519_public_key', '3': 3, '4': 1, '5': 12, '10': 'ed25519PublicKey'},
    {'1': 'ml_dsa_public_key', '3': 4, '4': 1, '5': 12, '10': 'mlDsaPublicKey'},
    {'1': 'x25519_public_key', '3': 5, '4': 1, '5': 12, '10': 'x25519PublicKey'},
    {'1': 'ml_kem_public_key', '3': 6, '4': 1, '5': 12, '10': 'mlKemPublicKey'},
    {'1': 'display_name', '3': 7, '4': 1, '5': 9, '10': 'displayName'},
    {'1': 'profile_picture', '3': 8, '4': 1, '5': 12, '10': 'profilePicture'},
    {'1': 'description', '3': 9, '4': 1, '5': 9, '10': 'description'},
  ],
};

/// Descriptor for `ContactRequestResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List contactRequestResponseDescriptor = $convert.base64Decode(
    'ChZDb250YWN0UmVxdWVzdFJlc3BvbnNlEhoKCGFjY2VwdGVkGAEgASgIUghhY2NlcHRlZBIpCh'
    'ByZWplY3Rpb25fcmVhc29uGAIgASgJUg9yZWplY3Rpb25SZWFzb24SLAoSZWQyNTUxOV9wdWJs'
    'aWNfa2V5GAMgASgMUhBlZDI1NTE5UHVibGljS2V5EikKEW1sX2RzYV9wdWJsaWNfa2V5GAQgAS'
    'gMUg5tbERzYVB1YmxpY0tleRIqChF4MjU1MTlfcHVibGljX2tleRgFIAEoDFIPeDI1NTE5UHVi'
    'bGljS2V5EikKEW1sX2tlbV9wdWJsaWNfa2V5GAYgASgMUg5tbEtlbVB1YmxpY0tleRIhCgxkaX'
    'NwbGF5X25hbWUYByABKAlSC2Rpc3BsYXlOYW1lEicKD3Byb2ZpbGVfcGljdHVyZRgIIAEoDFIO'
    'cHJvZmlsZVBpY3R1cmUSIAoLZGVzY3JpcHRpb24YCSABKAlSC2Rlc2NyaXB0aW9u');

@$core.Deprecated('Use profileDataDescriptor instead')
const ProfileData$json = {
  '1': 'ProfileData',
  '2': [
    {'1': 'profile_picture', '3': 1, '4': 1, '5': 12, '10': 'profilePicture'},
    {'1': 'description', '3': 2, '4': 1, '5': 9, '10': 'description'},
    {'1': 'updated_at_ms', '3': 3, '4': 1, '5': 4, '10': 'updatedAtMs'},
    {'1': 'display_name', '3': 4, '4': 1, '5': 9, '10': 'displayName'},
  ],
};

/// Descriptor for `ProfileData`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List profileDataDescriptor = $convert.base64Decode(
    'CgtQcm9maWxlRGF0YRInCg9wcm9maWxlX3BpY3R1cmUYASABKAxSDnByb2ZpbGVQaWN0dXJlEi'
    'AKC2Rlc2NyaXB0aW9uGAIgASgJUgtkZXNjcmlwdGlvbhIiCg11cGRhdGVkX2F0X21zGAMgASgE'
    'Ugt1cGRhdGVkQXRNcxIhCgxkaXNwbGF5X25hbWUYBCABKAlSC2Rpc3BsYXlOYW1l');

@$core.Deprecated('Use groupCreateDescriptor instead')
const GroupCreate$json = {
  '1': 'GroupCreate',
  '2': [
    {'1': 'group_id', '3': 1, '4': 1, '5': 12, '10': 'groupId'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'description', '3': 3, '4': 1, '5': 9, '10': 'description'},
    {'1': 'member_ids', '3': 4, '4': 3, '5': 12, '10': 'memberIds'},
    {'1': 'picture', '3': 5, '4': 1, '5': 12, '10': 'picture'},
  ],
};

/// Descriptor for `GroupCreate`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List groupCreateDescriptor = $convert.base64Decode(
    'CgtHcm91cENyZWF0ZRIZCghncm91cF9pZBgBIAEoDFIHZ3JvdXBJZBISCgRuYW1lGAIgASgJUg'
    'RuYW1lEiAKC2Rlc2NyaXB0aW9uGAMgASgJUgtkZXNjcmlwdGlvbhIdCgptZW1iZXJfaWRzGAQg'
    'AygMUgltZW1iZXJJZHMSGAoHcGljdHVyZRgFIAEoDFIHcGljdHVyZQ==');

@$core.Deprecated('Use groupInviteV3Descriptor instead')
const GroupInviteV3$json = {
  '1': 'GroupInviteV3',
  '2': [
    {'1': 'group_id', '3': 1, '4': 1, '5': 12, '10': 'groupId'},
    {'1': 'group_name', '3': 2, '4': 1, '5': 9, '10': 'groupName'},
    {'1': 'inviter_id', '3': 3, '4': 1, '5': 12, '10': 'inviterId'},
    {'1': 'members', '3': 4, '4': 3, '5': 11, '6': '.cleona.GroupMemberV3', '10': 'members'},
    {'1': 'group_picture', '3': 5, '4': 1, '5': 12, '10': 'groupPicture'},
    {'1': 'group_description', '3': 6, '4': 1, '5': 9, '10': 'groupDescription'},
    {'1': 'membership_epoch', '3': 7, '4': 1, '5': 4, '10': 'membershipEpoch'},
    {'1': 'membership_hash', '3': 8, '4': 1, '5': 12, '10': 'membershipHash'},
    {'1': 'membership_sig_ed25519', '3': 9, '4': 1, '5': 12, '10': 'membershipSigEd25519'},
    {'1': 'membership_sig_ml_dsa', '3': 10, '4': 1, '5': 12, '10': 'membershipSigMlDsa'},
  ],
};

/// Descriptor for `GroupInviteV3`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List groupInviteV3Descriptor = $convert.base64Decode(
    'Cg1Hcm91cEludml0ZVYzEhkKCGdyb3VwX2lkGAEgASgMUgdncm91cElkEh0KCmdyb3VwX25hbW'
    'UYAiABKAlSCWdyb3VwTmFtZRIdCgppbnZpdGVyX2lkGAMgASgMUglpbnZpdGVySWQSLwoHbWVt'
    'YmVycxgEIAMoCzIVLmNsZW9uYS5Hcm91cE1lbWJlclYzUgdtZW1iZXJzEiMKDWdyb3VwX3BpY3'
    'R1cmUYBSABKAxSDGdyb3VwUGljdHVyZRIrChFncm91cF9kZXNjcmlwdGlvbhgGIAEoCVIQZ3Jv'
    'dXBEZXNjcmlwdGlvbhIpChBtZW1iZXJzaGlwX2Vwb2NoGAcgASgEUg9tZW1iZXJzaGlwRXBvY2'
    'gSJwoPbWVtYmVyc2hpcF9oYXNoGAggASgMUg5tZW1iZXJzaGlwSGFzaBI0ChZtZW1iZXJzaGlw'
    'X3NpZ19lZDI1NTE5GAkgASgMUhRtZW1iZXJzaGlwU2lnRWQyNTUxORIxChVtZW1iZXJzaGlwX3'
    'NpZ19tbF9kc2EYCiABKAxSEm1lbWJlcnNoaXBTaWdNbERzYQ==');

@$core.Deprecated('Use groupMemberV3Descriptor instead')
const GroupMemberV3$json = {
  '1': 'GroupMemberV3',
  '2': [
    {'1': 'node_id', '3': 1, '4': 1, '5': 12, '10': 'nodeId'},
    {'1': 'display_name', '3': 2, '4': 1, '5': 9, '10': 'displayName'},
    {'1': 'role', '3': 3, '4': 1, '5': 9, '10': 'role'},
    {'1': 'ed25519_public_key', '3': 4, '4': 1, '5': 12, '10': 'ed25519PublicKey'},
    {'1': 'x25519_public_key', '3': 5, '4': 1, '5': 12, '10': 'x25519PublicKey'},
    {'1': 'ml_kem_public_key', '3': 6, '4': 1, '5': 12, '10': 'mlKemPublicKey'},
  ],
};

/// Descriptor for `GroupMemberV3`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List groupMemberV3Descriptor = $convert.base64Decode(
    'Cg1Hcm91cE1lbWJlclYzEhcKB25vZGVfaWQYASABKAxSBm5vZGVJZBIhCgxkaXNwbGF5X25hbW'
    'UYAiABKAlSC2Rpc3BsYXlOYW1lEhIKBHJvbGUYAyABKAlSBHJvbGUSLAoSZWQyNTUxOV9wdWJs'
    'aWNfa2V5GAQgASgMUhBlZDI1NTE5UHVibGljS2V5EioKEXgyNTUxOV9wdWJsaWNfa2V5GAUgAS'
    'gMUg94MjU1MTlQdWJsaWNLZXkSKQoRbWxfa2VtX3B1YmxpY19rZXkYBiABKAxSDm1sS2VtUHVi'
    'bGljS2V5');

@$core.Deprecated('Use groupMembershipResyncRequestDescriptor instead')
const GroupMembershipResyncRequest$json = {
  '1': 'GroupMembershipResyncRequest',
  '2': [
    {'1': 'group_id', '3': 1, '4': 1, '5': 12, '10': 'groupId'},
    {'1': 'local_epoch', '3': 2, '4': 1, '5': 4, '10': 'localEpoch'},
  ],
};

/// Descriptor for `GroupMembershipResyncRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List groupMembershipResyncRequestDescriptor = $convert.base64Decode(
    'ChxHcm91cE1lbWJlcnNoaXBSZXN5bmNSZXF1ZXN0EhkKCGdyb3VwX2lkGAEgASgMUgdncm91cE'
    'lkEh8KC2xvY2FsX2Vwb2NoGAIgASgEUgpsb2NhbEVwb2No');

@$core.Deprecated('Use groupKeyUpdateDescriptor instead')
const GroupKeyUpdate$json = {
  '1': 'GroupKeyUpdate',
  '2': [
    {'1': 'group_id', '3': 1, '4': 1, '5': 12, '10': 'groupId'},
    {'1': 'new_group_key', '3': 2, '4': 1, '5': 12, '10': 'newGroupKey'},
  ],
};

/// Descriptor for `GroupKeyUpdate`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List groupKeyUpdateDescriptor = $convert.base64Decode(
    'Cg5Hcm91cEtleVVwZGF0ZRIZCghncm91cF9pZBgBIAEoDFIHZ3JvdXBJZBIiCg1uZXdfZ3JvdX'
    'Bfa2V5GAIgASgMUgtuZXdHcm91cEtleQ==');

@$core.Deprecated('Use groupLeaveDescriptor instead')
const GroupLeave$json = {
  '1': 'GroupLeave',
  '2': [
    {'1': 'group_id', '3': 1, '4': 1, '5': 12, '10': 'groupId'},
  ],
};

/// Descriptor for `GroupLeave`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List groupLeaveDescriptor = $convert.base64Decode(
    'CgpHcm91cExlYXZlEhkKCGdyb3VwX2lkGAEgASgMUgdncm91cElk');

@$core.Deprecated('Use channelCreateDescriptor instead')
const ChannelCreate$json = {
  '1': 'ChannelCreate',
  '2': [
    {'1': 'channel_id', '3': 1, '4': 1, '5': 12, '10': 'channelId'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'description', '3': 3, '4': 1, '5': 9, '10': 'description'},
    {'1': 'announcement_only', '3': 4, '4': 1, '5': 8, '10': 'announcementOnly'},
    {'1': 'default_expiry', '3': 5, '4': 1, '5': 11, '6': '.cleona.ExpiryMetadata', '10': 'defaultExpiry'},
    {'1': 'picture', '3': 6, '4': 1, '5': 12, '10': 'picture'},
    {'1': 'is_public', '3': 7, '4': 1, '5': 8, '10': 'isPublic'},
    {'1': 'is_adult', '3': 8, '4': 1, '5': 8, '10': 'isAdult'},
    {'1': 'language', '3': 9, '4': 1, '5': 9, '10': 'language'},
  ],
};

/// Descriptor for `ChannelCreate`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List channelCreateDescriptor = $convert.base64Decode(
    'Cg1DaGFubmVsQ3JlYXRlEh0KCmNoYW5uZWxfaWQYASABKAxSCWNoYW5uZWxJZBISCgRuYW1lGA'
    'IgASgJUgRuYW1lEiAKC2Rlc2NyaXB0aW9uGAMgASgJUgtkZXNjcmlwdGlvbhIrChFhbm5vdW5j'
    'ZW1lbnRfb25seRgEIAEoCFIQYW5ub3VuY2VtZW50T25seRI9Cg5kZWZhdWx0X2V4cGlyeRgFIA'
    'EoCzIWLmNsZW9uYS5FeHBpcnlNZXRhZGF0YVINZGVmYXVsdEV4cGlyeRIYCgdwaWN0dXJlGAYg'
    'ASgMUgdwaWN0dXJlEhsKCWlzX3B1YmxpYxgHIAEoCFIIaXNQdWJsaWMSGQoIaXNfYWR1bHQYCC'
    'ABKAhSB2lzQWR1bHQSGgoIbGFuZ3VhZ2UYCSABKAlSCGxhbmd1YWdl');

@$core.Deprecated('Use channelPostDescriptor instead')
const ChannelPost$json = {
  '1': 'ChannelPost',
  '2': [
    {'1': 'channel_id', '3': 1, '4': 1, '5': 12, '10': 'channelId'},
    {'1': 'post_id', '3': 2, '4': 1, '5': 12, '10': 'postId'},
    {'1': 'text', '3': 3, '4': 1, '5': 9, '10': 'text'},
    {'1': 'media', '3': 4, '4': 1, '5': 11, '6': '.cleona.ContentMetadata', '10': 'media'},
    {'1': 'content_data', '3': 5, '4': 1, '5': 12, '10': 'contentData'},
  ],
};

/// Descriptor for `ChannelPost`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List channelPostDescriptor = $convert.base64Decode(
    'CgtDaGFubmVsUG9zdBIdCgpjaGFubmVsX2lkGAEgASgMUgljaGFubmVsSWQSFwoHcG9zdF9pZB'
    'gCIAEoDFIGcG9zdElkEhIKBHRleHQYAyABKAlSBHRleHQSLQoFbWVkaWEYBCABKAsyFy5jbGVv'
    'bmEuQ29udGVudE1ldGFkYXRhUgVtZWRpYRIhCgxjb250ZW50X2RhdGEYBSABKAxSC2NvbnRlbn'
    'REYXRh');

@$core.Deprecated('Use channelInviteDescriptor instead')
const ChannelInvite$json = {
  '1': 'ChannelInvite',
  '2': [
    {'1': 'channel_id', '3': 1, '4': 1, '5': 12, '10': 'channelId'},
    {'1': 'channel_name', '3': 2, '4': 1, '5': 9, '10': 'channelName'},
    {'1': 'inviter_id', '3': 3, '4': 1, '5': 12, '10': 'inviterId'},
    {'1': 'role', '3': 4, '4': 1, '5': 9, '10': 'role'},
    {'1': 'welcome_message', '3': 5, '4': 1, '5': 12, '10': 'welcomeMessage'},
    {'1': 'channel_picture', '3': 6, '4': 1, '5': 12, '10': 'channelPicture'},
    {'1': 'channel_description', '3': 7, '4': 1, '5': 9, '10': 'channelDescription'},
    {'1': 'members', '3': 8, '4': 3, '5': 11, '6': '.cleona.GroupMemberV3', '10': 'members'},
    {'1': 'is_public', '3': 9, '4': 1, '5': 8, '10': 'isPublic'},
    {'1': 'is_adult', '3': 10, '4': 1, '5': 8, '10': 'isAdult'},
    {'1': 'language', '3': 11, '4': 1, '5': 9, '10': 'language'},
    {'1': 'membership_epoch', '3': 12, '4': 1, '5': 4, '10': 'membershipEpoch'},
    {'1': 'membership_hash', '3': 13, '4': 1, '5': 12, '10': 'membershipHash'},
    {'1': 'membership_sig_ed25519', '3': 14, '4': 1, '5': 12, '10': 'membershipSigEd25519'},
    {'1': 'membership_sig_ml_dsa', '3': 15, '4': 1, '5': 12, '10': 'membershipSigMlDsa'},
  ],
};

/// Descriptor for `ChannelInvite`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List channelInviteDescriptor = $convert.base64Decode(
    'Cg1DaGFubmVsSW52aXRlEh0KCmNoYW5uZWxfaWQYASABKAxSCWNoYW5uZWxJZBIhCgxjaGFubm'
    'VsX25hbWUYAiABKAlSC2NoYW5uZWxOYW1lEh0KCmludml0ZXJfaWQYAyABKAxSCWludml0ZXJJ'
    'ZBISCgRyb2xlGAQgASgJUgRyb2xlEicKD3dlbGNvbWVfbWVzc2FnZRgFIAEoDFIOd2VsY29tZU'
    '1lc3NhZ2USJwoPY2hhbm5lbF9waWN0dXJlGAYgASgMUg5jaGFubmVsUGljdHVyZRIvChNjaGFu'
    'bmVsX2Rlc2NyaXB0aW9uGAcgASgJUhJjaGFubmVsRGVzY3JpcHRpb24SLwoHbWVtYmVycxgIIA'
    'MoCzIVLmNsZW9uYS5Hcm91cE1lbWJlclYzUgdtZW1iZXJzEhsKCWlzX3B1YmxpYxgJIAEoCFII'
    'aXNQdWJsaWMSGQoIaXNfYWR1bHQYCiABKAhSB2lzQWR1bHQSGgoIbGFuZ3VhZ2UYCyABKAlSCG'
    'xhbmd1YWdlEikKEG1lbWJlcnNoaXBfZXBvY2gYDCABKARSD21lbWJlcnNoaXBFcG9jaBInCg9t'
    'ZW1iZXJzaGlwX2hhc2gYDSABKAxSDm1lbWJlcnNoaXBIYXNoEjQKFm1lbWJlcnNoaXBfc2lnX2'
    'VkMjU1MTkYDiABKAxSFG1lbWJlcnNoaXBTaWdFZDI1NTE5EjEKFW1lbWJlcnNoaXBfc2lnX21s'
    'X2RzYRgPIAEoDFISbWVtYmVyc2hpcFNpZ01sRHNh');

@$core.Deprecated('Use channelRoleUpdateDescriptor instead')
const ChannelRoleUpdate$json = {
  '1': 'ChannelRoleUpdate',
  '2': [
    {'1': 'channel_id', '3': 1, '4': 1, '5': 12, '10': 'channelId'},
    {'1': 'target_id', '3': 2, '4': 1, '5': 12, '10': 'targetId'},
    {'1': 'new_role', '3': 3, '4': 1, '5': 9, '10': 'newRole'},
  ],
};

/// Descriptor for `ChannelRoleUpdate`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List channelRoleUpdateDescriptor = $convert.base64Decode(
    'ChFDaGFubmVsUm9sZVVwZGF0ZRIdCgpjaGFubmVsX2lkGAEgASgMUgljaGFubmVsSWQSGwoJdG'
    'FyZ2V0X2lkGAIgASgMUgh0YXJnZXRJZBIZCghuZXdfcm9sZRgDIAEoCVIHbmV3Um9sZQ==');

@$core.Deprecated('Use channelLeaveDescriptor instead')
const ChannelLeave$json = {
  '1': 'ChannelLeave',
  '2': [
    {'1': 'channel_id', '3': 1, '4': 1, '5': 12, '10': 'channelId'},
  ],
};

/// Descriptor for `ChannelLeave`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List channelLeaveDescriptor = $convert.base64Decode(
    'CgxDaGFubmVsTGVhdmUSHQoKY2hhbm5lbF9pZBgBIAEoDFIJY2hhbm5lbElk');

@$core.Deprecated('Use chatConfigUpdateDescriptor instead')
const ChatConfigUpdate$json = {
  '1': 'ChatConfigUpdate',
  '2': [
    {'1': 'conversation_id', '3': 1, '4': 1, '5': 9, '10': 'conversationId'},
    {'1': 'allow_downloads', '3': 2, '4': 1, '5': 8, '10': 'allowDownloads'},
    {'1': 'allow_forwarding', '3': 3, '4': 1, '5': 8, '10': 'allowForwarding'},
    {'1': 'is_request', '3': 4, '4': 1, '5': 8, '10': 'isRequest'},
    {'1': 'accepted', '3': 5, '4': 1, '5': 8, '10': 'accepted'},
    {'1': 'expiry_duration_ms', '3': 6, '4': 1, '5': 18, '10': 'expiryDurationMs'},
    {'1': 'edit_window_ms', '3': 7, '4': 1, '5': 18, '10': 'editWindowMs'},
    {'1': 'read_receipts', '3': 8, '4': 1, '5': 8, '10': 'readReceipts'},
    {'1': 'typing_indicators', '3': 9, '4': 1, '5': 8, '10': 'typingIndicators'},
  ],
};

/// Descriptor for `ChatConfigUpdate`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chatConfigUpdateDescriptor = $convert.base64Decode(
    'ChBDaGF0Q29uZmlnVXBkYXRlEicKD2NvbnZlcnNhdGlvbl9pZBgBIAEoCVIOY29udmVyc2F0aW'
    '9uSWQSJwoPYWxsb3dfZG93bmxvYWRzGAIgASgIUg5hbGxvd0Rvd25sb2FkcxIpChBhbGxvd19m'
    'b3J3YXJkaW5nGAMgASgIUg9hbGxvd0ZvcndhcmRpbmcSHQoKaXNfcmVxdWVzdBgEIAEoCFIJaX'
    'NSZXF1ZXN0EhoKCGFjY2VwdGVkGAUgASgIUghhY2NlcHRlZBIsChJleHBpcnlfZHVyYXRpb25f'
    'bXMYBiABKBJSEGV4cGlyeUR1cmF0aW9uTXMSJAoOZWRpdF93aW5kb3dfbXMYByABKBJSDGVkaX'
    'RXaW5kb3dNcxIjCg1yZWFkX3JlY2VpcHRzGAggASgIUgxyZWFkUmVjZWlwdHMSKwoRdHlwaW5n'
    'X2luZGljYXRvcnMYCSABKAhSEHR5cGluZ0luZGljYXRvcnM=');

@$core.Deprecated('Use identityDeletedNotificationDescriptor instead')
const IdentityDeletedNotification$json = {
  '1': 'IdentityDeletedNotification',
  '2': [
    {'1': 'identity_ed25519_pk', '3': 1, '4': 1, '5': 12, '10': 'identityEd25519Pk'},
    {'1': 'deleted_at_ms', '3': 2, '4': 1, '5': 4, '10': 'deletedAtMs'},
    {'1': 'display_name', '3': 3, '4': 1, '5': 9, '10': 'displayName'},
  ],
};

/// Descriptor for `IdentityDeletedNotification`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List identityDeletedNotificationDescriptor = $convert.base64Decode(
    'ChtJZGVudGl0eURlbGV0ZWROb3RpZmljYXRpb24SLgoTaWRlbnRpdHlfZWQyNTUxOV9waxgBIA'
    'EoDFIRaWRlbnRpdHlFZDI1NTE5UGsSIgoNZGVsZXRlZF9hdF9tcxgCIAEoBFILZGVsZXRlZEF0'
    'TXMSIQoMZGlzcGxheV9uYW1lGAMgASgJUgtkaXNwbGF5TmFtZQ==');

@$core.Deprecated('Use restoreBroadcastDescriptor instead')
const RestoreBroadcast$json = {
  '1': 'RestoreBroadcast',
  '2': [
    {'1': 'old_node_id', '3': 1, '4': 1, '5': 12, '10': 'oldNodeId'},
    {'1': 'new_node_id', '3': 2, '4': 1, '5': 12, '10': 'newNodeId'},
    {'1': 'new_ed25519_pk', '3': 3, '4': 1, '5': 12, '10': 'newEd25519Pk'},
    {'1': 'new_x25519_pk', '3': 4, '4': 1, '5': 12, '10': 'newX25519Pk'},
    {'1': 'new_ml_kem_pk', '3': 5, '4': 1, '5': 12, '10': 'newMlKemPk'},
    {'1': 'new_ml_dsa_pk', '3': 6, '4': 1, '5': 12, '10': 'newMlDsaPk'},
    {'1': 'display_name', '3': 7, '4': 1, '5': 9, '10': 'displayName'},
    {'1': 'timestamp', '3': 8, '4': 1, '5': 4, '10': 'timestamp'},
    {'1': 'signature', '3': 9, '4': 1, '5': 12, '10': 'signature'},
    {'1': 'signature_ml_dsa', '3': 10, '4': 1, '5': 12, '10': 'signatureMlDsa'},
  ],
};

/// Descriptor for `RestoreBroadcast`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List restoreBroadcastDescriptor = $convert.base64Decode(
    'ChBSZXN0b3JlQnJvYWRjYXN0Eh4KC29sZF9ub2RlX2lkGAEgASgMUglvbGROb2RlSWQSHgoLbm'
    'V3X25vZGVfaWQYAiABKAxSCW5ld05vZGVJZBIkCg5uZXdfZWQyNTUxOV9waxgDIAEoDFIMbmV3'
    'RWQyNTUxOVBrEiIKDW5ld194MjU1MTlfcGsYBCABKAxSC25ld1gyNTUxOVBrEiEKDW5ld19tbF'
    '9rZW1fcGsYBSABKAxSCm5ld01sS2VtUGsSIQoNbmV3X21sX2RzYV9waxgGIAEoDFIKbmV3TWxE'
    'c2FQaxIhCgxkaXNwbGF5X25hbWUYByABKAlSC2Rpc3BsYXlOYW1lEhwKCXRpbWVzdGFtcBgIIA'
    'EoBFIJdGltZXN0YW1wEhwKCXNpZ25hdHVyZRgJIAEoDFIJc2lnbmF0dXJlEigKEHNpZ25hdHVy'
    'ZV9tbF9kc2EYCiABKAxSDnNpZ25hdHVyZU1sRHNh');

@$core.Deprecated('Use restoreResponseDescriptor instead')
const RestoreResponse$json = {
  '1': 'RestoreResponse',
  '2': [
    {'1': 'phase', '3': 1, '4': 1, '5': 13, '10': 'phase'},
    {'1': 'contacts', '3': 2, '4': 3, '5': 11, '6': '.cleona.ContactEntry', '10': 'contacts'},
    {'1': 'messages', '3': 3, '4': 3, '5': 11, '6': '.cleona.StoredMessage', '10': 'messages'},
    {'1': 'groups', '3': 4, '4': 3, '5': 11, '6': '.cleona.RestoreGroupInfo', '10': 'groups'},
    {'1': 'channels', '3': 5, '4': 3, '5': 11, '6': '.cleona.RestoreChannelInfo', '10': 'channels'},
  ],
};

/// Descriptor for `RestoreResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List restoreResponseDescriptor = $convert.base64Decode(
    'Cg9SZXN0b3JlUmVzcG9uc2USFAoFcGhhc2UYASABKA1SBXBoYXNlEjAKCGNvbnRhY3RzGAIgAy'
    'gLMhQuY2xlb25hLkNvbnRhY3RFbnRyeVIIY29udGFjdHMSMQoIbWVzc2FnZXMYAyADKAsyFS5j'
    'bGVvbmEuU3RvcmVkTWVzc2FnZVIIbWVzc2FnZXMSMAoGZ3JvdXBzGAQgAygLMhguY2xlb25hLl'
    'Jlc3RvcmVHcm91cEluZm9SBmdyb3VwcxI2CghjaGFubmVscxgFIAMoCzIaLmNsZW9uYS5SZXN0'
    'b3JlQ2hhbm5lbEluZm9SCGNoYW5uZWxz');

@$core.Deprecated('Use restoreGroupInfoDescriptor instead')
const RestoreGroupInfo$json = {
  '1': 'RestoreGroupInfo',
  '2': [
    {'1': 'group_id', '3': 1, '4': 1, '5': 12, '10': 'groupId'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'description', '3': 3, '4': 1, '5': 9, '10': 'description'},
    {'1': 'owner_node_id_hex', '3': 4, '4': 1, '5': 9, '10': 'ownerNodeIdHex'},
    {'1': 'members', '3': 5, '4': 3, '5': 11, '6': '.cleona.RestoreGroupMember', '10': 'members'},
  ],
};

/// Descriptor for `RestoreGroupInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List restoreGroupInfoDescriptor = $convert.base64Decode(
    'ChBSZXN0b3JlR3JvdXBJbmZvEhkKCGdyb3VwX2lkGAEgASgMUgdncm91cElkEhIKBG5hbWUYAi'
    'ABKAlSBG5hbWUSIAoLZGVzY3JpcHRpb24YAyABKAlSC2Rlc2NyaXB0aW9uEikKEW93bmVyX25v'
    'ZGVfaWRfaGV4GAQgASgJUg5vd25lck5vZGVJZEhleBI0CgdtZW1iZXJzGAUgAygLMhouY2xlb2'
    '5hLlJlc3RvcmVHcm91cE1lbWJlclIHbWVtYmVycw==');

@$core.Deprecated('Use restoreGroupMemberDescriptor instead')
const RestoreGroupMember$json = {
  '1': 'RestoreGroupMember',
  '2': [
    {'1': 'node_id_hex', '3': 1, '4': 1, '5': 9, '10': 'nodeIdHex'},
    {'1': 'display_name', '3': 2, '4': 1, '5': 9, '10': 'displayName'},
    {'1': 'role', '3': 3, '4': 1, '5': 9, '10': 'role'},
    {'1': 'ed25519_pk', '3': 4, '4': 1, '5': 12, '10': 'ed25519Pk'},
    {'1': 'x25519_pk', '3': 5, '4': 1, '5': 12, '10': 'x25519Pk'},
    {'1': 'ml_kem_pk', '3': 6, '4': 1, '5': 12, '10': 'mlKemPk'},
  ],
};

/// Descriptor for `RestoreGroupMember`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List restoreGroupMemberDescriptor = $convert.base64Decode(
    'ChJSZXN0b3JlR3JvdXBNZW1iZXISHgoLbm9kZV9pZF9oZXgYASABKAlSCW5vZGVJZEhleBIhCg'
    'xkaXNwbGF5X25hbWUYAiABKAlSC2Rpc3BsYXlOYW1lEhIKBHJvbGUYAyABKAlSBHJvbGUSHQoK'
    'ZWQyNTUxOV9waxgEIAEoDFIJZWQyNTUxOVBrEhsKCXgyNTUxOV9waxgFIAEoDFIIeDI1NTE5UG'
    'sSGgoJbWxfa2VtX3BrGAYgASgMUgdtbEtlbVBr');

@$core.Deprecated('Use restoreChannelInfoDescriptor instead')
const RestoreChannelInfo$json = {
  '1': 'RestoreChannelInfo',
  '2': [
    {'1': 'channel_id', '3': 1, '4': 1, '5': 12, '10': 'channelId'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'description', '3': 3, '4': 1, '5': 9, '10': 'description'},
    {'1': 'owner_node_id_hex', '3': 4, '4': 1, '5': 9, '10': 'ownerNodeIdHex'},
    {'1': 'members', '3': 5, '4': 3, '5': 11, '6': '.cleona.RestoreChannelMember', '10': 'members'},
    {'1': 'is_adult', '3': 6, '4': 1, '5': 8, '10': 'isAdult'},
  ],
};

/// Descriptor for `RestoreChannelInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List restoreChannelInfoDescriptor = $convert.base64Decode(
    'ChJSZXN0b3JlQ2hhbm5lbEluZm8SHQoKY2hhbm5lbF9pZBgBIAEoDFIJY2hhbm5lbElkEhIKBG'
    '5hbWUYAiABKAlSBG5hbWUSIAoLZGVzY3JpcHRpb24YAyABKAlSC2Rlc2NyaXB0aW9uEikKEW93'
    'bmVyX25vZGVfaWRfaGV4GAQgASgJUg5vd25lck5vZGVJZEhleBI2CgdtZW1iZXJzGAUgAygLMh'
    'wuY2xlb25hLlJlc3RvcmVDaGFubmVsTWVtYmVyUgdtZW1iZXJzEhkKCGlzX2FkdWx0GAYgASgI'
    'Ugdpc0FkdWx0');

@$core.Deprecated('Use restoreChannelMemberDescriptor instead')
const RestoreChannelMember$json = {
  '1': 'RestoreChannelMember',
  '2': [
    {'1': 'node_id_hex', '3': 1, '4': 1, '5': 9, '10': 'nodeIdHex'},
    {'1': 'display_name', '3': 2, '4': 1, '5': 9, '10': 'displayName'},
    {'1': 'role', '3': 3, '4': 1, '5': 9, '10': 'role'},
    {'1': 'ed25519_pk', '3': 4, '4': 1, '5': 12, '10': 'ed25519Pk'},
    {'1': 'x25519_pk', '3': 5, '4': 1, '5': 12, '10': 'x25519Pk'},
    {'1': 'ml_kem_pk', '3': 6, '4': 1, '5': 12, '10': 'mlKemPk'},
  ],
};

/// Descriptor for `RestoreChannelMember`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List restoreChannelMemberDescriptor = $convert.base64Decode(
    'ChRSZXN0b3JlQ2hhbm5lbE1lbWJlchIeCgtub2RlX2lkX2hleBgBIAEoCVIJbm9kZUlkSGV4Ei'
    'EKDGRpc3BsYXlfbmFtZRgCIAEoCVILZGlzcGxheU5hbWUSEgoEcm9sZRgDIAEoCVIEcm9sZRId'
    'CgplZDI1NTE5X3BrGAQgASgMUgllZDI1NTE5UGsSGwoJeDI1NTE5X3BrGAUgASgMUgh4MjU1MT'
    'lQaxIaCgltbF9rZW1fcGsYBiABKAxSB21sS2VtUGs=');

@$core.Deprecated('Use contactEntryDescriptor instead')
const ContactEntry$json = {
  '1': 'ContactEntry',
  '2': [
    {'1': 'node_id', '3': 1, '4': 1, '5': 12, '10': 'nodeId'},
    {'1': 'display_name', '3': 2, '4': 1, '5': 9, '10': 'displayName'},
    {'1': 'ed25519_pk', '3': 3, '4': 1, '5': 12, '10': 'ed25519Pk'},
    {'1': 'x25519_pk', '3': 4, '4': 1, '5': 12, '10': 'x25519Pk'},
    {'1': 'ml_kem_pk', '3': 5, '4': 1, '5': 12, '10': 'mlKemPk'},
    {'1': 'ml_dsa_pk', '3': 6, '4': 1, '5': 12, '10': 'mlDsaPk'},
    {'1': 'profile_picture', '3': 7, '4': 1, '5': 12, '10': 'profilePicture'},
    {'1': 'description', '3': 8, '4': 1, '5': 9, '10': 'description'},
  ],
};

/// Descriptor for `ContactEntry`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List contactEntryDescriptor = $convert.base64Decode(
    'CgxDb250YWN0RW50cnkSFwoHbm9kZV9pZBgBIAEoDFIGbm9kZUlkEiEKDGRpc3BsYXlfbmFtZR'
    'gCIAEoCVILZGlzcGxheU5hbWUSHQoKZWQyNTUxOV9waxgDIAEoDFIJZWQyNTUxOVBrEhsKCXgy'
    'NTUxOV9waxgEIAEoDFIIeDI1NTE5UGsSGgoJbWxfa2VtX3BrGAUgASgMUgdtbEtlbVBrEhoKCW'
    '1sX2RzYV9waxgGIAEoDFIHbWxEc2FQaxInCg9wcm9maWxlX3BpY3R1cmUYByABKAxSDnByb2Zp'
    'bGVQaWN0dXJlEiAKC2Rlc2NyaXB0aW9uGAggASgJUgtkZXNjcmlwdGlvbg==');

@$core.Deprecated('Use storedMessageDescriptor instead')
const StoredMessage$json = {
  '1': 'StoredMessage',
  '2': [
    {'1': 'message_id', '3': 1, '4': 1, '5': 12, '10': 'messageId'},
    {'1': 'sender_id', '3': 2, '4': 1, '5': 12, '10': 'senderId'},
    {'1': 'recipient_id', '3': 3, '4': 1, '5': 12, '10': 'recipientId'},
    {'1': 'conversation_id', '3': 4, '4': 1, '5': 9, '10': 'conversationId'},
    {'1': 'timestamp', '3': 5, '4': 1, '5': 4, '10': 'timestamp'},
    {'1': 'ui_message_type', '3': 6, '4': 1, '5': 5, '10': 'uiMessageType'},
    {'1': 'payload', '3': 7, '4': 1, '5': 12, '10': 'payload'},
  ],
};

/// Descriptor for `StoredMessage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List storedMessageDescriptor = $convert.base64Decode(
    'Cg1TdG9yZWRNZXNzYWdlEh0KCm1lc3NhZ2VfaWQYASABKAxSCW1lc3NhZ2VJZBIbCglzZW5kZX'
    'JfaWQYAiABKAxSCHNlbmRlcklkEiEKDHJlY2lwaWVudF9pZBgDIAEoDFILcmVjaXBpZW50SWQS'
    'JwoPY29udmVyc2F0aW9uX2lkGAQgASgJUg5jb252ZXJzYXRpb25JZBIcCgl0aW1lc3RhbXAYBS'
    'ABKARSCXRpbWVzdGFtcBImCg91aV9tZXNzYWdlX3R5cGUYBiABKAVSDXVpTWVzc2FnZVR5cGUS'
    'GAoHcGF5bG9hZBgHIAEoDFIHcGF5bG9hZA==');

@$core.Deprecated('Use callInviteDescriptor instead')
const CallInvite$json = {
  '1': 'CallInvite',
  '2': [
    {'1': 'call_id', '3': 1, '4': 1, '5': 12, '10': 'callId'},
    {'1': 'caller_eph_x25519_pk', '3': 2, '4': 1, '5': 12, '10': 'callerEphX25519Pk'},
    {'1': 'caller_kem_ciphertext', '3': 3, '4': 1, '5': 12, '10': 'callerKemCiphertext'},
    {'1': 'is_video', '3': 4, '4': 1, '5': 8, '10': 'isVideo'},
    {'1': 'is_group_call', '3': 5, '4': 1, '5': 8, '10': 'isGroupCall'},
    {'1': 'group_id', '3': 6, '4': 1, '5': 12, '10': 'groupId'},
    {'1': 'caller_app_major_minor', '3': 8, '4': 1, '5': 13, '10': 'callerAppMajorMinor'},
    {'1': 'caller_audio_format_min', '3': 9, '4': 1, '5': 13, '10': 'callerAudioFormatMin'},
    {'1': 'caller_audio_format_max', '3': 10, '4': 1, '5': 13, '10': 'callerAudioFormatMax'},
    {'1': 'caller_video_format_min', '3': 11, '4': 1, '5': 13, '10': 'callerVideoFormatMin'},
    {'1': 'caller_video_format_max', '3': 12, '4': 1, '5': 13, '10': 'callerVideoFormatMax'},
    {'1': 'caller_candidates', '3': 13, '4': 1, '5': 12, '10': 'callerCandidates'},
    {'1': 'caller_d_cookie', '3': 14, '4': 1, '5': 12, '10': 'callerDCookie'},
  ],
  '9': [
    {'1': 7, '2': 8},
  ],
};

/// Descriptor for `CallInvite`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List callInviteDescriptor = $convert.base64Decode(
    'CgpDYWxsSW52aXRlEhcKB2NhbGxfaWQYASABKAxSBmNhbGxJZBIvChRjYWxsZXJfZXBoX3gyNT'
    'UxOV9waxgCIAEoDFIRY2FsbGVyRXBoWDI1NTE5UGsSMgoVY2FsbGVyX2tlbV9jaXBoZXJ0ZXh0'
    'GAMgASgMUhNjYWxsZXJLZW1DaXBoZXJ0ZXh0EhkKCGlzX3ZpZGVvGAQgASgIUgdpc1ZpZGVvEi'
    'IKDWlzX2dyb3VwX2NhbGwYBSABKAhSC2lzR3JvdXBDYWxsEhkKCGdyb3VwX2lkGAYgASgMUgdn'
    'cm91cElkEjMKFmNhbGxlcl9hcHBfbWFqb3JfbWlub3IYCCABKA1SE2NhbGxlckFwcE1ham9yTW'
    'lub3ISNQoXY2FsbGVyX2F1ZGlvX2Zvcm1hdF9taW4YCSABKA1SFGNhbGxlckF1ZGlvRm9ybWF0'
    'TWluEjUKF2NhbGxlcl9hdWRpb19mb3JtYXRfbWF4GAogASgNUhRjYWxsZXJBdWRpb0Zvcm1hdE'
    '1heBI1ChdjYWxsZXJfdmlkZW9fZm9ybWF0X21pbhgLIAEoDVIUY2FsbGVyVmlkZW9Gb3JtYXRN'
    'aW4SNQoXY2FsbGVyX3ZpZGVvX2Zvcm1hdF9tYXgYDCABKA1SFGNhbGxlclZpZGVvRm9ybWF0TW'
    'F4EisKEWNhbGxlcl9jYW5kaWRhdGVzGA0gASgMUhBjYWxsZXJDYW5kaWRhdGVzEiYKD2NhbGxl'
    'cl9kX2Nvb2tpZRgOIAEoDFINY2FsbGVyRENvb2tpZUoECAcQCA==');

@$core.Deprecated('Use callAnswerDescriptor instead')
const CallAnswer$json = {
  '1': 'CallAnswer',
  '2': [
    {'1': 'call_id', '3': 1, '4': 1, '5': 12, '10': 'callId'},
    {'1': 'callee_eph_x25519_pk', '3': 2, '4': 1, '5': 12, '10': 'calleeEphX25519Pk'},
    {'1': 'callee_kem_ciphertext', '3': 3, '4': 1, '5': 12, '10': 'calleeKemCiphertext'},
    {'1': 'selected_audio_format', '3': 4, '4': 1, '5': 13, '10': 'selectedAudioFormat'},
    {'1': 'selected_video_format', '3': 5, '4': 1, '5': 13, '10': 'selectedVideoFormat'},
    {'1': 'callee_candidates', '3': 6, '4': 1, '5': 12, '10': 'calleeCandidates'},
    {'1': 'callee_d_cookie', '3': 7, '4': 1, '5': 12, '10': 'calleeDCookie'},
  ],
};

/// Descriptor for `CallAnswer`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List callAnswerDescriptor = $convert.base64Decode(
    'CgpDYWxsQW5zd2VyEhcKB2NhbGxfaWQYASABKAxSBmNhbGxJZBIvChRjYWxsZWVfZXBoX3gyNT'
    'UxOV9waxgCIAEoDFIRY2FsbGVlRXBoWDI1NTE5UGsSMgoVY2FsbGVlX2tlbV9jaXBoZXJ0ZXh0'
    'GAMgASgMUhNjYWxsZWVLZW1DaXBoZXJ0ZXh0EjIKFXNlbGVjdGVkX2F1ZGlvX2Zvcm1hdBgEIA'
    'EoDVITc2VsZWN0ZWRBdWRpb0Zvcm1hdBIyChVzZWxlY3RlZF92aWRlb19mb3JtYXQYBSABKA1S'
    'E3NlbGVjdGVkVmlkZW9Gb3JtYXQSKwoRY2FsbGVlX2NhbmRpZGF0ZXMYBiABKAxSEGNhbGxlZU'
    'NhbmRpZGF0ZXMSJgoPY2FsbGVlX2RfY29va2llGAcgASgMUg1jYWxsZWVEQ29va2ll');

@$core.Deprecated('Use callRejectDescriptor instead')
const CallReject$json = {
  '1': 'CallReject',
  '2': [
    {'1': 'call_id', '3': 1, '4': 1, '5': 12, '10': 'callId'},
    {'1': 'reason', '3': 2, '4': 1, '5': 9, '10': 'reason'},
  ],
};

/// Descriptor for `CallReject`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List callRejectDescriptor = $convert.base64Decode(
    'CgpDYWxsUmVqZWN0EhcKB2NhbGxfaWQYASABKAxSBmNhbGxJZBIWCgZyZWFzb24YAiABKAlSBn'
    'JlYXNvbg==');

@$core.Deprecated('Use callCancelOthersDescriptor instead')
const CallCancelOthers$json = {
  '1': 'CallCancelOthers',
  '2': [
    {'1': 'call_id', '3': 1, '4': 1, '5': 12, '10': 'callId'},
    {'1': 'bound_answer_key', '3': 2, '4': 1, '5': 12, '10': 'boundAnswerKey'},
  ],
};

/// Descriptor for `CallCancelOthers`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List callCancelOthersDescriptor = $convert.base64Decode(
    'ChBDYWxsQ2FuY2VsT3RoZXJzEhcKB2NhbGxfaWQYASABKAxSBmNhbGxJZBIoChBib3VuZF9hbn'
    'N3ZXJfa2V5GAIgASgMUg5ib3VuZEFuc3dlcktleQ==');

@$core.Deprecated('Use callRingAckDescriptor instead')
const CallRingAck$json = {
  '1': 'CallRingAck',
  '2': [
    {'1': 'call_id', '3': 1, '4': 1, '5': 12, '10': 'callId'},
    {'1': 'device_marker', '3': 2, '4': 1, '5': 12, '10': 'deviceMarker'},
  ],
};

/// Descriptor for `CallRingAck`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List callRingAckDescriptor = $convert.base64Decode(
    'CgtDYWxsUmluZ0FjaxIXCgdjYWxsX2lkGAEgASgMUgZjYWxsSWQSIwoNZGV2aWNlX21hcmtlch'
    'gCIAEoDFIMZGV2aWNlTWFya2Vy');

@$core.Deprecated('Use callHangupDescriptor instead')
const CallHangup$json = {
  '1': 'CallHangup',
  '2': [
    {'1': 'call_id', '3': 1, '4': 1, '5': 12, '10': 'callId'},
  ],
};

/// Descriptor for `CallHangup`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List callHangupDescriptor = $convert.base64Decode(
    'CgpDYWxsSGFuZ3VwEhcKB2NhbGxfaWQYASABKAxSBmNhbGxJZA==');

@$core.Deprecated('Use iceCandidateDescriptor instead')
const IceCandidate$json = {
  '1': 'IceCandidate',
  '2': [
    {'1': 'call_id', '3': 1, '4': 1, '5': 12, '10': 'callId'},
    {'1': 'candidate', '3': 2, '4': 1, '5': 9, '10': 'candidate'},
    {'1': 'sdp_mid', '3': 3, '4': 1, '5': 9, '10': 'sdpMid'},
    {'1': 'sdp_m_line_index', '3': 4, '4': 1, '5': 13, '10': 'sdpMLineIndex'},
  ],
};

/// Descriptor for `IceCandidate`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List iceCandidateDescriptor = $convert.base64Decode(
    'CgxJY2VDYW5kaWRhdGUSFwoHY2FsbF9pZBgBIAEoDFIGY2FsbElkEhwKCWNhbmRpZGF0ZRgCIA'
    'EoCVIJY2FuZGlkYXRlEhcKB3NkcF9taWQYAyABKAlSBnNkcE1pZBInChBzZHBfbV9saW5lX2lu'
    'ZGV4GAQgASgNUg1zZHBNTGluZUluZGV4');

@$core.Deprecated('Use callRejoinDescriptor instead')
const CallRejoin$json = {
  '1': 'CallRejoin',
  '2': [
    {'1': 'call_id', '3': 1, '4': 1, '5': 12, '10': 'callId'},
  ],
};

/// Descriptor for `CallRejoin`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List callRejoinDescriptor = $convert.base64Decode(
    'CgpDYWxsUmVqb2luEhcKB2NhbGxfaWQYASABKAxSBmNhbGxJZA==');

@$core.Deprecated('Use keyRotationDescriptor instead')
const KeyRotation$json = {
  '1': 'KeyRotation',
  '2': [
    {'1': 'new_x25519_pk', '3': 1, '4': 1, '5': 12, '10': 'newX25519Pk'},
    {'1': 'new_ml_kem_pk', '3': 2, '4': 1, '5': 12, '10': 'newMlKemPk'},
    {'1': 'rotation_timestamp', '3': 3, '4': 1, '5': 4, '10': 'rotationTimestamp'},
    {'1': 'signature', '3': 4, '4': 1, '5': 12, '10': 'signature'},
  ],
};

/// Descriptor for `KeyRotation`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List keyRotationDescriptor = $convert.base64Decode(
    'CgtLZXlSb3RhdGlvbhIiCg1uZXdfeDI1NTE5X3BrGAEgASgMUgtuZXdYMjU1MTlQaxIhCg1uZX'
    'dfbWxfa2VtX3BrGAIgASgMUgpuZXdNbEtlbVBrEi0KEnJvdGF0aW9uX3RpbWVzdGFtcBgDIAEo'
    'BFIRcm90YXRpb25UaW1lc3RhbXASHAoJc2lnbmF0dXJlGAQgASgMUglzaWduYXR1cmU=');

@$core.Deprecated('Use channelJoinRequestDescriptor instead')
const ChannelJoinRequest$json = {
  '1': 'ChannelJoinRequest',
  '2': [
    {'1': 'channel_id', '3': 1, '4': 1, '5': 12, '10': 'channelId'},
    {'1': 'display_name', '3': 2, '4': 1, '5': 9, '10': 'displayName'},
    {'1': 'ed25519_pk', '3': 3, '4': 1, '5': 12, '10': 'ed25519Pk'},
    {'1': 'x25519_pk', '3': 4, '4': 1, '5': 12, '10': 'x25519Pk'},
    {'1': 'ml_kem_pk', '3': 5, '4': 1, '5': 12, '10': 'mlKemPk'},
  ],
};

/// Descriptor for `ChannelJoinRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List channelJoinRequestDescriptor = $convert.base64Decode(
    'ChJDaGFubmVsSm9pblJlcXVlc3QSHQoKY2hhbm5lbF9pZBgBIAEoDFIJY2hhbm5lbElkEiEKDG'
    'Rpc3BsYXlfbmFtZRgCIAEoCVILZGlzcGxheU5hbWUSHQoKZWQyNTUxOV9waxgDIAEoDFIJZWQy'
    'NTUxOVBrEhsKCXgyNTUxOV9waxgEIAEoDFIIeDI1NTE5UGsSGgoJbWxfa2VtX3BrGAUgASgMUg'
    'dtbEtlbVBr');

@$core.Deprecated('Use channelIndexExchangeDescriptor instead')
const ChannelIndexExchange$json = {
  '1': 'ChannelIndexExchange',
  '2': [
    {'1': 'entries', '3': 1, '4': 3, '5': 11, '6': '.cleona.ChannelIndexEntryProto', '10': 'entries'},
  ],
};

/// Descriptor for `ChannelIndexExchange`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List channelIndexExchangeDescriptor = $convert.base64Decode(
    'ChRDaGFubmVsSW5kZXhFeGNoYW5nZRI4CgdlbnRyaWVzGAEgAygLMh4uY2xlb25hLkNoYW5uZW'
    'xJbmRleEVudHJ5UHJvdG9SB2VudHJpZXM=');

@$core.Deprecated('Use channelReportMsgDescriptor instead')
const ChannelReportMsg$json = {
  '1': 'ChannelReportMsg',
  '2': [
    {'1': 'report_id', '3': 1, '4': 1, '5': 12, '10': 'reportId'},
    {'1': 'channel_id', '3': 2, '4': 1, '5': 12, '10': 'channelId'},
    {'1': 'category', '3': 3, '4': 1, '5': 13, '10': 'category'},
    {'1': 'evidence_post_ids', '3': 4, '4': 3, '5': 12, '10': 'evidencePostIds'},
    {'1': 'description', '3': 5, '4': 1, '5': 9, '10': 'description'},
    {'1': 'created_at_ms', '3': 6, '4': 1, '5': 4, '10': 'createdAtMs'},
    {'1': 'is_post_report', '3': 7, '4': 1, '5': 8, '10': 'isPostReport'},
    {'1': 'post_id', '3': 8, '4': 1, '5': 12, '10': 'postId'},
  ],
};

/// Descriptor for `ChannelReportMsg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List channelReportMsgDescriptor = $convert.base64Decode(
    'ChBDaGFubmVsUmVwb3J0TXNnEhsKCXJlcG9ydF9pZBgBIAEoDFIIcmVwb3J0SWQSHQoKY2hhbm'
    '5lbF9pZBgCIAEoDFIJY2hhbm5lbElkEhoKCGNhdGVnb3J5GAMgASgNUghjYXRlZ29yeRIqChFl'
    'dmlkZW5jZV9wb3N0X2lkcxgEIAMoDFIPZXZpZGVuY2VQb3N0SWRzEiAKC2Rlc2NyaXB0aW9uGA'
    'UgASgJUgtkZXNjcmlwdGlvbhIiCg1jcmVhdGVkX2F0X21zGAYgASgEUgtjcmVhdGVkQXRNcxIk'
    'Cg5pc19wb3N0X3JlcG9ydBgHIAEoCFIMaXNQb3N0UmVwb3J0EhcKB3Bvc3RfaWQYCCABKAxSBn'
    'Bvc3RJZA==');

@$core.Deprecated('Use channelReportResponseDescriptor instead')
const ChannelReportResponse$json = {
  '1': 'ChannelReportResponse',
  '2': [
    {'1': 'report_id', '3': 1, '4': 1, '5': 12, '10': 'reportId'},
    {'1': 'accepted', '3': 2, '4': 1, '5': 8, '10': 'accepted'},
    {'1': 'rejection_reason', '3': 3, '4': 1, '5': 9, '10': 'rejectionReason'},
  ],
};

/// Descriptor for `ChannelReportResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List channelReportResponseDescriptor = $convert.base64Decode(
    'ChVDaGFubmVsUmVwb3J0UmVzcG9uc2USGwoJcmVwb3J0X2lkGAEgASgMUghyZXBvcnRJZBIaCg'
    'hhY2NlcHRlZBgCIAEoCFIIYWNjZXB0ZWQSKQoQcmVqZWN0aW9uX3JlYXNvbhgDIAEoCVIPcmVq'
    'ZWN0aW9uUmVhc29u');

@$core.Deprecated('Use juryRequestMsgDescriptor instead')
const JuryRequestMsg$json = {
  '1': 'JuryRequestMsg',
  '2': [
    {'1': 'jury_id', '3': 1, '4': 1, '5': 12, '10': 'juryId'},
    {'1': 'channel_id', '3': 2, '4': 1, '5': 12, '10': 'channelId'},
    {'1': 'report_id', '3': 3, '4': 1, '5': 12, '10': 'reportId'},
    {'1': 'category', '3': 4, '4': 1, '5': 13, '10': 'category'},
    {'1': 'evidence_post_ids', '3': 5, '4': 3, '5': 12, '10': 'evidencePostIds'},
    {'1': 'report_description', '3': 6, '4': 1, '5': 9, '10': 'reportDescription'},
    {'1': 'channel_name', '3': 7, '4': 1, '5': 9, '10': 'channelName'},
    {'1': 'channel_language', '3': 8, '4': 1, '5': 9, '10': 'channelLanguage'},
    {'1': 'epoch_day', '3': 9, '4': 1, '5': 13, '10': 'epochDay'},
    {'1': 'jury_round', '3': 10, '4': 1, '5': 13, '10': 'juryRound'},
    {'1': 'eligibility_snapshot_hash', '3': 11, '4': 1, '5': 12, '10': 'eligibilitySnapshotHash'},
  ],
};

/// Descriptor for `JuryRequestMsg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List juryRequestMsgDescriptor = $convert.base64Decode(
    'Cg5KdXJ5UmVxdWVzdE1zZxIXCgdqdXJ5X2lkGAEgASgMUgZqdXJ5SWQSHQoKY2hhbm5lbF9pZB'
    'gCIAEoDFIJY2hhbm5lbElkEhsKCXJlcG9ydF9pZBgDIAEoDFIIcmVwb3J0SWQSGgoIY2F0ZWdv'
    'cnkYBCABKA1SCGNhdGVnb3J5EioKEWV2aWRlbmNlX3Bvc3RfaWRzGAUgAygMUg9ldmlkZW5jZV'
    'Bvc3RJZHMSLQoScmVwb3J0X2Rlc2NyaXB0aW9uGAYgASgJUhFyZXBvcnREZXNjcmlwdGlvbhIh'
    'CgxjaGFubmVsX25hbWUYByABKAlSC2NoYW5uZWxOYW1lEikKEGNoYW5uZWxfbGFuZ3VhZ2UYCC'
    'ABKAlSD2NoYW5uZWxMYW5ndWFnZRIbCgllcG9jaF9kYXkYCSABKA1SCGVwb2NoRGF5Eh0KCmp1'
    'cnlfcm91bmQYCiABKA1SCWp1cnlSb3VuZBI6ChllbGlnaWJpbGl0eV9zbmFwc2hvdF9oYXNoGA'
    'sgASgMUhdlbGlnaWJpbGl0eVNuYXBzaG90SGFzaA==');

@$core.Deprecated('Use juryVoteMsgDescriptor instead')
const JuryVoteMsg$json = {
  '1': 'JuryVoteMsg',
  '2': [
    {'1': 'jury_id', '3': 1, '4': 1, '5': 12, '10': 'juryId'},
    {'1': 'report_id', '3': 2, '4': 1, '5': 12, '10': 'reportId'},
    {'1': 'vote', '3': 3, '4': 1, '5': 13, '10': 'vote'},
    {'1': 'reason', '3': 4, '4': 1, '5': 9, '10': 'reason'},
    {'1': 'sig_ed25519', '3': 5, '4': 1, '5': 12, '10': 'sigEd25519'},
    {'1': 'sig_ml_dsa', '3': 6, '4': 1, '5': 12, '10': 'sigMlDsa'},
    {'1': 'jury_round', '3': 7, '4': 1, '5': 13, '10': 'juryRound'},
    {'1': 'epoch_day', '3': 8, '4': 1, '5': 13, '10': 'epochDay'},
  ],
};

/// Descriptor for `JuryVoteMsg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List juryVoteMsgDescriptor = $convert.base64Decode(
    'CgtKdXJ5Vm90ZU1zZxIXCgdqdXJ5X2lkGAEgASgMUgZqdXJ5SWQSGwoJcmVwb3J0X2lkGAIgAS'
    'gMUghyZXBvcnRJZBISCgR2b3RlGAMgASgNUgR2b3RlEhYKBnJlYXNvbhgEIAEoCVIGcmVhc29u'
    'Eh8KC3NpZ19lZDI1NTE5GAUgASgMUgpzaWdFZDI1NTE5EhwKCnNpZ19tbF9kc2EYBiABKAxSCH'
    'NpZ01sRHNhEh0KCmp1cnlfcm91bmQYByABKA1SCWp1cnlSb3VuZBIbCgllcG9jaF9kYXkYCCAB'
    'KA1SCGVwb2NoRGF5');

@$core.Deprecated('Use juryResultMsgDescriptor instead')
const JuryResultMsg$json = {
  '1': 'JuryResultMsg',
  '2': [
    {'1': 'jury_id', '3': 1, '4': 1, '5': 12, '10': 'juryId'},
    {'1': 'report_id', '3': 2, '4': 1, '5': 12, '10': 'reportId'},
    {'1': 'channel_id', '3': 3, '4': 1, '5': 12, '10': 'channelId'},
    {'1': 'consequence', '3': 4, '4': 1, '5': 13, '10': 'consequence'},
    {'1': 'votes_approve', '3': 5, '4': 1, '5': 13, '10': 'votesApprove'},
    {'1': 'votes_reject', '3': 6, '4': 1, '5': 13, '10': 'votesReject'},
    {'1': 'votes_abstain', '3': 7, '4': 1, '5': 13, '10': 'votesAbstain'},
    {'1': 'new_bad_badge_level', '3': 8, '4': 1, '5': 13, '10': 'newBadBadgeLevel'},
    {'1': 'juror_sigs', '3': 9, '4': 3, '5': 11, '6': '.cleona.JurorVerdictSig', '10': 'jurorSigs'},
    {'1': 'eligibility_snapshot_hash', '3': 10, '4': 1, '5': 12, '10': 'eligibilitySnapshotHash'},
    {'1': 'epoch_day', '3': 11, '4': 1, '5': 13, '10': 'epochDay'},
    {'1': 'jury_round', '3': 12, '4': 1, '5': 13, '10': 'juryRound'},
  ],
};

/// Descriptor for `JuryResultMsg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List juryResultMsgDescriptor = $convert.base64Decode(
    'Cg1KdXJ5UmVzdWx0TXNnEhcKB2p1cnlfaWQYASABKAxSBmp1cnlJZBIbCglyZXBvcnRfaWQYAi'
    'ABKAxSCHJlcG9ydElkEh0KCmNoYW5uZWxfaWQYAyABKAxSCWNoYW5uZWxJZBIgCgtjb25zZXF1'
    'ZW5jZRgEIAEoDVILY29uc2VxdWVuY2USIwoNdm90ZXNfYXBwcm92ZRgFIAEoDVIMdm90ZXNBcH'
    'Byb3ZlEiEKDHZvdGVzX3JlamVjdBgGIAEoDVILdm90ZXNSZWplY3QSIwoNdm90ZXNfYWJzdGFp'
    'bhgHIAEoDVIMdm90ZXNBYnN0YWluEi0KE25ld19iYWRfYmFkZ2VfbGV2ZWwYCCABKA1SEG5ld0'
    'JhZEJhZGdlTGV2ZWwSNgoKanVyb3Jfc2lncxgJIAMoCzIXLmNsZW9uYS5KdXJvclZlcmRpY3RT'
    'aWdSCWp1cm9yU2lncxI6ChllbGlnaWJpbGl0eV9zbmFwc2hvdF9oYXNoGAogASgMUhdlbGlnaW'
    'JpbGl0eVNuYXBzaG90SGFzaBIbCgllcG9jaF9kYXkYCyABKA1SCGVwb2NoRGF5Eh0KCmp1cnlf'
    'cm91bmQYDCABKA1SCWp1cnlSb3VuZA==');

@$core.Deprecated('Use jurorVerdictSigDescriptor instead')
const JurorVerdictSig$json = {
  '1': 'JurorVerdictSig',
  '2': [
    {'1': 'juror_user_id', '3': 1, '4': 1, '5': 12, '10': 'jurorUserId'},
    {'1': 'sig_ed25519', '3': 2, '4': 1, '5': 12, '10': 'sigEd25519'},
    {'1': 'sig_ml_dsa', '3': 3, '4': 1, '5': 12, '10': 'sigMlDsa'},
    {'1': 'vote', '3': 4, '4': 1, '5': 13, '10': 'vote'},
  ],
};

/// Descriptor for `JurorVerdictSig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List jurorVerdictSigDescriptor = $convert.base64Decode(
    'Cg9KdXJvclZlcmRpY3RTaWcSIgoNanVyb3JfdXNlcl9pZBgBIAEoDFILanVyb3JVc2VySWQSHw'
    'oLc2lnX2VkMjU1MTkYAiABKAxSCnNpZ0VkMjU1MTkSHAoKc2lnX21sX2RzYRgDIAEoDFIIc2ln'
    'TWxEc2ESEgoEdm90ZRgEIAEoDVIEdm90ZQ==');

@$core.Deprecated('Use jurorAvailabilityRecordDescriptor instead')
const JurorAvailabilityRecord$json = {
  '1': 'JurorAvailabilityRecord',
  '2': [
    {'1': 'user_pub_key_ed25519', '3': 1, '4': 1, '5': 12, '10': 'userPubKeyEd25519'},
    {'1': 'user_pub_key_ml_dsa', '3': 2, '4': 1, '5': 12, '10': 'userPubKeyMlDsa'},
    {'1': 'creation_epoch_ms', '3': 3, '4': 1, '5': 4, '10': 'creationEpochMs'},
    {'1': 'self_sig_ed25519', '3': 4, '4': 1, '5': 12, '10': 'selfSigEd25519'},
    {'1': 'self_sig_ml_dsa', '3': 5, '4': 1, '5': 12, '10': 'selfSigMlDsa'},
    {'1': 'published_at_ms', '3': 6, '4': 1, '5': 4, '10': 'publishedAtMs'},
  ],
};

/// Descriptor for `JurorAvailabilityRecord`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List jurorAvailabilityRecordDescriptor = $convert.base64Decode(
    'ChdKdXJvckF2YWlsYWJpbGl0eVJlY29yZBIvChR1c2VyX3B1Yl9rZXlfZWQyNTUxORgBIAEoDF'
    'IRdXNlclB1YktleUVkMjU1MTkSLAoTdXNlcl9wdWJfa2V5X21sX2RzYRgCIAEoDFIPdXNlclB1'
    'YktleU1sRHNhEioKEWNyZWF0aW9uX2Vwb2NoX21zGAMgASgEUg9jcmVhdGlvbkVwb2NoTXMSKA'
    'oQc2VsZl9zaWdfZWQyNTUxORgEIAEoDFIOc2VsZlNpZ0VkMjU1MTkSJQoPc2VsZl9zaWdfbWxf'
    'ZHNhGAUgASgMUgxzZWxmU2lnTWxEc2ESJgoPcHVibGlzaGVkX2F0X21zGAYgASgEUg1wdWJsaX'
    'NoZWRBdE1z');

@$core.Deprecated('Use moderationProofRecordDescriptor instead')
const ModerationProofRecord$json = {
  '1': 'ModerationProofRecord',
  '2': [
    {'1': 'channel_id', '3': 1, '4': 1, '5': 12, '10': 'channelId'},
    {'1': 'jury_id', '3': 2, '4': 1, '5': 12, '10': 'juryId'},
    {'1': 'report_id', '3': 3, '4': 1, '5': 12, '10': 'reportId'},
    {'1': 'consequence', '3': 4, '4': 1, '5': 13, '10': 'consequence'},
    {'1': 'epoch_day', '3': 5, '4': 1, '5': 13, '10': 'epochDay'},
    {'1': 'jury_round', '3': 6, '4': 1, '5': 13, '10': 'juryRound'},
    {'1': 'juror_sigs', '3': 7, '4': 3, '5': 11, '6': '.cleona.JurorVerdictSig', '10': 'jurorSigs'},
    {'1': 'eligibility_snapshot_hash', '3': 8, '4': 1, '5': 12, '10': 'eligibilitySnapshotHash'},
  ],
};

/// Descriptor for `ModerationProofRecord`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List moderationProofRecordDescriptor = $convert.base64Decode(
    'ChVNb2RlcmF0aW9uUHJvb2ZSZWNvcmQSHQoKY2hhbm5lbF9pZBgBIAEoDFIJY2hhbm5lbElkEh'
    'cKB2p1cnlfaWQYAiABKAxSBmp1cnlJZBIbCglyZXBvcnRfaWQYAyABKAxSCHJlcG9ydElkEiAK'
    'C2NvbnNlcXVlbmNlGAQgASgNUgtjb25zZXF1ZW5jZRIbCgllcG9jaF9kYXkYBSABKA1SCGVwb2'
    'NoRGF5Eh0KCmp1cnlfcm91bmQYBiABKA1SCWp1cnlSb3VuZBI2CgpqdXJvcl9zaWdzGAcgAygL'
    'MhcuY2xlb25hLkp1cm9yVmVyZGljdFNpZ1IJanVyb3JTaWdzEjoKGWVsaWdpYmlsaXR5X3NuYX'
    'BzaG90X2hhc2gYCCABKAxSF2VsaWdpYmlsaXR5U25hcHNob3RIYXNo');

@$core.Deprecated('Use csamReporterQuorumProofDescriptor instead')
const CsamReporterQuorumProof$json = {
  '1': 'CsamReporterQuorumProof',
  '2': [
    {'1': 'channel_id', '3': 1, '4': 1, '5': 12, '10': 'channelId'},
    {'1': 'reporter_sigs', '3': 2, '4': 3, '5': 11, '6': '.cleona.CsamReportSig', '10': 'reporterSigs'},
  ],
};

/// Descriptor for `CsamReporterQuorumProof`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List csamReporterQuorumProofDescriptor = $convert.base64Decode(
    'ChdDc2FtUmVwb3J0ZXJRdW9ydW1Qcm9vZhIdCgpjaGFubmVsX2lkGAEgASgMUgljaGFubmVsSW'
    'QSOgoNcmVwb3J0ZXJfc2lncxgCIAMoCzIVLmNsZW9uYS5Dc2FtUmVwb3J0U2lnUgxyZXBvcnRl'
    'clNpZ3M=');

@$core.Deprecated('Use csamReportSigDescriptor instead')
const CsamReportSig$json = {
  '1': 'CsamReportSig',
  '2': [
    {'1': 'reporter_user_id', '3': 1, '4': 1, '5': 12, '10': 'reporterUserId'},
    {'1': 'sig_ed25519', '3': 2, '4': 1, '5': 12, '10': 'sigEd25519'},
    {'1': 'sig_ml_dsa', '3': 3, '4': 1, '5': 12, '10': 'sigMlDsa'},
    {'1': 'report_id', '3': 4, '4': 1, '5': 12, '10': 'reportId'},
    {'1': 'reported_at_ms', '3': 5, '4': 1, '5': 4, '10': 'reportedAtMs'},
  ],
};

/// Descriptor for `CsamReportSig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List csamReportSigDescriptor = $convert.base64Decode(
    'Cg1Dc2FtUmVwb3J0U2lnEigKEHJlcG9ydGVyX3VzZXJfaWQYASABKAxSDnJlcG9ydGVyVXNlck'
    'lkEh8KC3NpZ19lZDI1NTE5GAIgASgMUgpzaWdFZDI1NTE5EhwKCnNpZ19tbF9kc2EYAyABKAxS'
    'CHNpZ01sRHNhEhsKCXJlcG9ydF9pZBgEIAEoDFIIcmVwb3J0SWQSJAoOcmVwb3J0ZWRfYXRfbX'
    'MYBSABKARSDHJlcG9ydGVkQXRNcw==');

@$core.Deprecated('Use channelIndexEntryProtoDescriptor instead')
const ChannelIndexEntryProto$json = {
  '1': 'ChannelIndexEntryProto',
  '2': [
    {'1': 'channel_id', '3': 1, '4': 1, '5': 12, '10': 'channelId'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'language', '3': 3, '4': 1, '5': 9, '10': 'language'},
    {'1': 'is_adult', '3': 4, '4': 1, '5': 8, '10': 'isAdult'},
    {'1': 'description', '3': 5, '4': 1, '5': 9, '10': 'description'},
    {'1': 'subscriber_count', '3': 6, '4': 1, '5': 13, '10': 'subscriberCount'},
    {'1': 'bad_badge_level', '3': 7, '4': 1, '5': 13, '10': 'badBadgeLevel'},
    {'1': 'bad_badge_since_ms', '3': 8, '4': 1, '5': 4, '10': 'badBadgeSinceMs'},
    {'1': 'correction_submitted', '3': 9, '4': 1, '5': 8, '10': 'correctionSubmitted'},
    {'1': 'owner_node_id', '3': 10, '4': 1, '5': 12, '10': 'ownerNodeId'},
    {'1': 'created_at_ms', '3': 11, '4': 1, '5': 4, '10': 'createdAtMs'},
    {'1': 'owner_signature', '3': 12, '4': 1, '5': 12, '10': 'ownerSignature'},
    {'1': 'moderation_proof_hash', '3': 13, '4': 1, '5': 12, '10': 'moderationProofHash'},
  ],
};

/// Descriptor for `ChannelIndexEntryProto`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List channelIndexEntryProtoDescriptor = $convert.base64Decode(
    'ChZDaGFubmVsSW5kZXhFbnRyeVByb3RvEh0KCmNoYW5uZWxfaWQYASABKAxSCWNoYW5uZWxJZB'
    'ISCgRuYW1lGAIgASgJUgRuYW1lEhoKCGxhbmd1YWdlGAMgASgJUghsYW5ndWFnZRIZCghpc19h'
    'ZHVsdBgEIAEoCFIHaXNBZHVsdBIgCgtkZXNjcmlwdGlvbhgFIAEoCVILZGVzY3JpcHRpb24SKQ'
    'oQc3Vic2NyaWJlcl9jb3VudBgGIAEoDVIPc3Vic2NyaWJlckNvdW50EiYKD2JhZF9iYWRnZV9s'
    'ZXZlbBgHIAEoDVINYmFkQmFkZ2VMZXZlbBIrChJiYWRfYmFkZ2Vfc2luY2VfbXMYCCABKARSD2'
    'JhZEJhZGdlU2luY2VNcxIxChRjb3JyZWN0aW9uX3N1Ym1pdHRlZBgJIAEoCFITY29ycmVjdGlv'
    'blN1Ym1pdHRlZBIiCg1vd25lcl9ub2RlX2lkGAogASgMUgtvd25lck5vZGVJZBIiCg1jcmVhdG'
    'VkX2F0X21zGAsgASgEUgtjcmVhdGVkQXRNcxInCg9vd25lcl9zaWduYXR1cmUYDCABKAxSDm93'
    'bmVyU2lnbmF0dXJlEjIKFW1vZGVyYXRpb25fcHJvb2ZfaGFzaBgNIAEoDFITbW9kZXJhdGlvbl'
    'Byb29mSGFzaA==');

@$core.Deprecated('Use readReceiptDescriptor instead')
const ReadReceipt$json = {
  '1': 'ReadReceipt',
  '2': [
    {'1': 'message_id', '3': 1, '4': 1, '5': 12, '10': 'messageId'},
    {'1': 'read_at', '3': 2, '4': 1, '5': 4, '10': 'readAt'},
  ],
};

/// Descriptor for `ReadReceipt`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List readReceiptDescriptor = $convert.base64Decode(
    'CgtSZWFkUmVjZWlwdBIdCgptZXNzYWdlX2lkGAEgASgMUgltZXNzYWdlSWQSFwoHcmVhZF9hdB'
    'gCIAEoBFIGcmVhZEF0');

@$core.Deprecated('Use typingIndicatorDescriptor instead')
const TypingIndicator$json = {
  '1': 'TypingIndicator',
  '2': [
    {'1': 'conversation_id', '3': 1, '4': 1, '5': 9, '10': 'conversationId'},
    {'1': 'is_typing', '3': 2, '4': 1, '5': 8, '10': 'isTyping'},
  ],
};

/// Descriptor for `TypingIndicator`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List typingIndicatorDescriptor = $convert.base64Decode(
    'Cg9UeXBpbmdJbmRpY2F0b3ISJwoPY29udmVyc2F0aW9uX2lkGAEgASgJUg5jb252ZXJzYXRpb2'
    '5JZBIbCglpc190eXBpbmcYAiABKAhSCGlzVHlwaW5n');

@$core.Deprecated('Use messageEditDescriptor instead')
const MessageEdit$json = {
  '1': 'MessageEdit',
  '2': [
    {'1': 'original_message_id', '3': 1, '4': 1, '5': 12, '10': 'originalMessageId'},
    {'1': 'new_text', '3': 2, '4': 1, '5': 9, '10': 'newText'},
    {'1': 'edit_timestamp', '3': 3, '4': 1, '5': 4, '10': 'editTimestamp'},
  ],
};

/// Descriptor for `MessageEdit`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List messageEditDescriptor = $convert.base64Decode(
    'CgtNZXNzYWdlRWRpdBIuChNvcmlnaW5hbF9tZXNzYWdlX2lkGAEgASgMUhFvcmlnaW5hbE1lc3'
    'NhZ2VJZBIZCghuZXdfdGV4dBgCIAEoCVIHbmV3VGV4dBIlCg5lZGl0X3RpbWVzdGFtcBgDIAEo'
    'BFINZWRpdFRpbWVzdGFtcA==');

@$core.Deprecated('Use messageDeleteDescriptor instead')
const MessageDelete$json = {
  '1': 'MessageDelete',
  '2': [
    {'1': 'message_id', '3': 1, '4': 1, '5': 12, '10': 'messageId'},
    {'1': 'deleted_at', '3': 2, '4': 1, '5': 4, '10': 'deletedAt'},
  ],
};

/// Descriptor for `MessageDelete`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List messageDeleteDescriptor = $convert.base64Decode(
    'Cg1NZXNzYWdlRGVsZXRlEh0KCm1lc3NhZ2VfaWQYASABKAxSCW1lc3NhZ2VJZBIdCgpkZWxldG'
    'VkX2F0GAIgASgEUglkZWxldGVkQXQ=');

@$core.Deprecated('Use emojiReactionDescriptor instead')
const EmojiReaction$json = {
  '1': 'EmojiReaction',
  '2': [
    {'1': 'message_id', '3': 1, '4': 1, '5': 12, '10': 'messageId'},
    {'1': 'emoji', '3': 2, '4': 1, '5': 9, '10': 'emoji'},
    {'1': 'remove', '3': 3, '4': 1, '5': 8, '10': 'remove'},
  ],
};

/// Descriptor for `EmojiReaction`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List emojiReactionDescriptor = $convert.base64Decode(
    'Cg1FbW9qaVJlYWN0aW9uEh0KCm1lc3NhZ2VfaWQYASABKAxSCW1lc3NhZ2VJZBIUCgVlbW9qaR'
    'gCIAEoCVIFZW1vamkSFgoGcmVtb3ZlGAMgASgIUgZyZW1vdmU=');

@$core.Deprecated('Use mediaChunkDescriptor instead')
const MediaChunk$json = {
  '1': 'MediaChunk',
  '2': [
    {'1': 'transfer_id', '3': 1, '4': 1, '5': 12, '10': 'transferId'},
    {'1': 'chunk_index', '3': 2, '4': 1, '5': 13, '10': 'chunkIndex'},
    {'1': 'total_chunks', '3': 3, '4': 1, '5': 13, '10': 'totalChunks'},
    {'1': 'chunk_data', '3': 4, '4': 1, '5': 12, '10': 'chunkData'},
    {'1': 'original_recipient_id', '3': 5, '4': 1, '5': 12, '10': 'originalRecipientId'},
  ],
};

/// Descriptor for `MediaChunk`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mediaChunkDescriptor = $convert.base64Decode(
    'CgpNZWRpYUNodW5rEh8KC3RyYW5zZmVyX2lkGAEgASgMUgp0cmFuc2ZlcklkEh8KC2NodW5rX2'
    'luZGV4GAIgASgNUgpjaHVua0luZGV4EiEKDHRvdGFsX2NodW5rcxgDIAEoDVILdG90YWxDaHVu'
    'a3MSHQoKY2h1bmtfZGF0YRgEIAEoDFIJY2h1bmtEYXRhEjIKFW9yaWdpbmFsX3JlY2lwaWVudF'
    '9pZBgFIAEoDFITb3JpZ2luYWxSZWNpcGllbnRJZA==');

@$core.Deprecated('Use mediaChunkV3Descriptor instead')
const MediaChunkV3$json = {
  '1': 'MediaChunkV3',
  '2': [
    {'1': 'media_id', '3': 1, '4': 1, '5': 12, '10': 'mediaId'},
    {'1': 'chunk_index', '3': 2, '4': 1, '5': 13, '10': 'chunkIndex'},
    {'1': 'total_chunks', '3': 3, '4': 1, '5': 13, '10': 'totalChunks'},
    {'1': 'data', '3': 4, '4': 1, '5': 12, '10': 'data'},
  ],
};

/// Descriptor for `MediaChunkV3`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mediaChunkV3Descriptor = $convert.base64Decode(
    'CgxNZWRpYUNodW5rVjMSGQoIbWVkaWFfaWQYASABKAxSB21lZGlhSWQSHwoLY2h1bmtfaW5kZX'
    'gYAiABKA1SCmNodW5rSW5kZXgSIQoMdG90YWxfY2h1bmtzGAMgASgNUgt0b3RhbENodW5rcxIS'
    'CgRkYXRhGAQgASgMUgRkYXRh');

@$core.Deprecated('Use mediaCompleteV3Descriptor instead')
const MediaCompleteV3$json = {
  '1': 'MediaCompleteV3',
  '2': [
    {'1': 'media_id', '3': 1, '4': 1, '5': 12, '10': 'mediaId'},
    {'1': 'content_hash', '3': 2, '4': 1, '5': 12, '10': 'contentHash'},
    {'1': 'total_size', '3': 3, '4': 1, '5': 4, '10': 'totalSize'},
  ],
};

/// Descriptor for `MediaCompleteV3`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mediaCompleteV3Descriptor = $convert.base64Decode(
    'Cg9NZWRpYUNvbXBsZXRlVjMSGQoIbWVkaWFfaWQYASABKAxSB21lZGlhSWQSIQoMY29udGVudF'
    '9oYXNoGAIgASgMUgtjb250ZW50SGFzaBIdCgp0b3RhbF9zaXplGAMgASgEUgl0b3RhbFNpemU=');

@$core.Deprecated('Use callRttPingDescriptor instead')
const CallRttPing$json = {
  '1': 'CallRttPing',
  '2': [
    {'1': 'call_id', '3': 1, '4': 1, '5': 12, '10': 'callId'},
    {'1': 'timestamp_us', '3': 2, '4': 1, '5': 3, '10': 'timestampUs'},
  ],
};

/// Descriptor for `CallRttPing`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List callRttPingDescriptor = $convert.base64Decode(
    'CgtDYWxsUnR0UGluZxIXCgdjYWxsX2lkGAEgASgMUgZjYWxsSWQSIQoMdGltZXN0YW1wX3VzGA'
    'IgASgDUgt0aW1lc3RhbXBVcw==');

@$core.Deprecated('Use callRttPongDescriptor instead')
const CallRttPong$json = {
  '1': 'CallRttPong',
  '2': [
    {'1': 'call_id', '3': 1, '4': 1, '5': 12, '10': 'callId'},
    {'1': 'echo_timestamp_us', '3': 2, '4': 1, '5': 3, '10': 'echoTimestampUs'},
    {'1': 'responder_timestamp_us', '3': 3, '4': 1, '5': 3, '10': 'responderTimestampUs'},
  ],
};

/// Descriptor for `CallRttPong`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List callRttPongDescriptor = $convert.base64Decode(
    'CgtDYWxsUnR0UG9uZxIXCgdjYWxsX2lkGAEgASgMUgZjYWxsSWQSKgoRZWNob190aW1lc3RhbX'
    'BfdXMYAiABKANSD2VjaG9UaW1lc3RhbXBVcxI0ChZyZXNwb25kZXJfdGltZXN0YW1wX3VzGAMg'
    'ASgDUhRyZXNwb25kZXJUaW1lc3RhbXBVcw==');

@$core.Deprecated('Use overlayTreeNodeDescriptor instead')
const OverlayTreeNode$json = {
  '1': 'OverlayTreeNode',
  '2': [
    {'1': 'node_id', '3': 1, '4': 1, '5': 12, '10': 'nodeId'},
    {'1': 'parent_node_id', '3': 2, '4': 1, '5': 12, '10': 'parentNodeId'},
    {'1': 'child_node_ids', '3': 3, '4': 3, '5': 12, '10': 'childNodeIds'},
    {'1': 'is_lan_cluster_head', '3': 4, '4': 1, '5': 8, '10': 'isLanClusterHead'},
    {'1': 'lan_member_ids', '3': 5, '4': 3, '5': 12, '10': 'lanMemberIds'},
  ],
};

/// Descriptor for `OverlayTreeNode`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List overlayTreeNodeDescriptor = $convert.base64Decode(
    'Cg9PdmVybGF5VHJlZU5vZGUSFwoHbm9kZV9pZBgBIAEoDFIGbm9kZUlkEiQKDnBhcmVudF9ub2'
    'RlX2lkGAIgASgMUgxwYXJlbnROb2RlSWQSJAoOY2hpbGRfbm9kZV9pZHMYAyADKAxSDGNoaWxk'
    'Tm9kZUlkcxItChNpc19sYW5fY2x1c3Rlcl9oZWFkGAQgASgIUhBpc0xhbkNsdXN0ZXJIZWFkEi'
    'QKDmxhbl9tZW1iZXJfaWRzGAUgAygMUgxsYW5NZW1iZXJJZHM=');

@$core.Deprecated('Use callTreeUpdateDescriptor instead')
const CallTreeUpdate$json = {
  '1': 'CallTreeUpdate',
  '2': [
    {'1': 'call_id', '3': 1, '4': 1, '5': 12, '10': 'callId'},
    {'1': 'nodes', '3': 2, '4': 3, '5': 11, '6': '.cleona.OverlayTreeNode', '10': 'nodes'},
    {'1': 'initiator_node_id', '3': 3, '4': 1, '5': 12, '10': 'initiatorNodeId'},
    {'1': 'version', '3': 4, '4': 1, '5': 13, '10': 'version'},
  ],
};

/// Descriptor for `CallTreeUpdate`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List callTreeUpdateDescriptor = $convert.base64Decode(
    'Cg5DYWxsVHJlZVVwZGF0ZRIXCgdjYWxsX2lkGAEgASgMUgZjYWxsSWQSLQoFbm9kZXMYAiADKA'
    'syFy5jbGVvbmEuT3ZlcmxheVRyZWVOb2RlUgVub2RlcxIqChFpbml0aWF0b3Jfbm9kZV9pZBgD'
    'IAEoDFIPaW5pdGlhdG9yTm9kZUlkEhgKB3ZlcnNpb24YBCABKA1SB3ZlcnNpb24=');

@$core.Deprecated('Use videoFrameDescriptor instead')
const VideoFrame$json = {
  '1': 'VideoFrame',
  '2': [
    {'1': 'call_id', '3': 1, '4': 1, '5': 12, '10': 'callId'},
    {'1': 'sequence_number', '3': 2, '4': 1, '5': 13, '10': 'sequenceNumber'},
    {'1': 'flags', '3': 3, '4': 1, '5': 13, '10': 'flags'},
    {'1': 'fragment_index', '3': 4, '4': 1, '5': 13, '10': 'fragmentIndex'},
    {'1': 'fragment_total', '3': 5, '4': 1, '5': 13, '10': 'fragmentTotal'},
    {'1': 'width', '3': 6, '4': 1, '5': 13, '10': 'width'},
    {'1': 'height', '3': 7, '4': 1, '5': 13, '10': 'height'},
    {'1': 'nonce', '3': 8, '4': 1, '5': 12, '10': 'nonce'},
    {'1': 'encrypted_data', '3': 9, '4': 1, '5': 12, '10': 'encryptedData'},
    {'1': 'timestamp_ms', '3': 10, '4': 1, '5': 13, '10': 'timestampMs'},
  ],
};

/// Descriptor for `VideoFrame`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List videoFrameDescriptor = $convert.base64Decode(
    'CgpWaWRlb0ZyYW1lEhcKB2NhbGxfaWQYASABKAxSBmNhbGxJZBInCg9zZXF1ZW5jZV9udW1iZX'
    'IYAiABKA1SDnNlcXVlbmNlTnVtYmVyEhQKBWZsYWdzGAMgASgNUgVmbGFncxIlCg5mcmFnbWVu'
    'dF9pbmRleBgEIAEoDVINZnJhZ21lbnRJbmRleBIlCg5mcmFnbWVudF90b3RhbBgFIAEoDVINZn'
    'JhZ21lbnRUb3RhbBIUCgV3aWR0aBgGIAEoDVIFd2lkdGgSFgoGaGVpZ2h0GAcgASgNUgZoZWln'
    'aHQSFAoFbm9uY2UYCCABKAxSBW5vbmNlEiUKDmVuY3J5cHRlZF9kYXRhGAkgASgMUg1lbmNyeX'
    'B0ZWREYXRhEiEKDHRpbWVzdGFtcF9tcxgKIAEoDVILdGltZXN0YW1wTXM=');

@$core.Deprecated('Use keyframeRequestDescriptor instead')
const KeyframeRequest$json = {
  '1': 'KeyframeRequest',
  '2': [
    {'1': 'call_id', '3': 1, '4': 1, '5': 12, '10': 'callId'},
  ],
};

/// Descriptor for `KeyframeRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List keyframeRequestDescriptor = $convert.base64Decode(
    'Cg9LZXlmcmFtZVJlcXVlc3QSFwoHY2FsbF9pZBgBIAEoDFIGY2FsbElk');

@$core.Deprecated('Use callMediaStateDescriptor instead')
const CallMediaState$json = {
  '1': 'CallMediaState',
  '2': [
    {'1': 'call_id', '3': 1, '4': 1, '5': 12, '10': 'callId'},
    {'1': 'sending_video', '3': 2, '4': 1, '5': 8, '10': 'sendingVideo'},
    {'1': 'video_off_reason', '3': 3, '4': 1, '5': 14, '6': '.cleona.VideoOffReason', '10': 'videoOffReason'},
    {'1': 'state_seq', '3': 4, '4': 1, '5': 4, '10': 'stateSeq'},
  ],
};

/// Descriptor for `CallMediaState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List callMediaStateDescriptor = $convert.base64Decode(
    'Cg5DYWxsTWVkaWFTdGF0ZRIXCgdjYWxsX2lkGAEgASgMUgZjYWxsSWQSIwoNc2VuZGluZ192aW'
    'RlbxgCIAEoCFIMc2VuZGluZ1ZpZGVvEkAKEHZpZGVvX29mZl9yZWFzb24YAyABKA4yFi5jbGVv'
    'bmEuVmlkZW9PZmZSZWFzb25SDnZpZGVvT2ZmUmVhc29uEhsKCXN0YXRlX3NlcRgEIAEoBFIIc3'
    'RhdGVTZXE=');

@$core.Deprecated('Use groupCallAudioDescriptor instead')
const GroupCallAudio$json = {
  '1': 'GroupCallAudio',
  '2': [
    {'1': 'call_id', '3': 1, '4': 1, '5': 12, '10': 'callId'},
    {'1': 'sender_node_id', '3': 2, '4': 1, '5': 12, '10': 'senderNodeId'},
    {'1': 'sequence_number', '3': 3, '4': 1, '5': 13, '10': 'sequenceNumber'},
    {'1': 'encrypted_audio', '3': 4, '4': 1, '5': 12, '10': 'encryptedAudio'},
  ],
};

/// Descriptor for `GroupCallAudio`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List groupCallAudioDescriptor = $convert.base64Decode(
    'Cg5Hcm91cENhbGxBdWRpbxIXCgdjYWxsX2lkGAEgASgMUgZjYWxsSWQSJAoOc2VuZGVyX25vZG'
    'VfaWQYAiABKAxSDHNlbmRlck5vZGVJZBInCg9zZXF1ZW5jZV9udW1iZXIYAyABKA1SDnNlcXVl'
    'bmNlTnVtYmVyEicKD2VuY3J5cHRlZF9hdWRpbxgEIAEoDFIOZW5jcnlwdGVkQXVkaW8=');

@$core.Deprecated('Use groupCallLeaveDescriptor instead')
const GroupCallLeave$json = {
  '1': 'GroupCallLeave',
  '2': [
    {'1': 'call_id', '3': 1, '4': 1, '5': 12, '10': 'callId'},
  ],
};

/// Descriptor for `GroupCallLeave`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List groupCallLeaveDescriptor = $convert.base64Decode(
    'Cg5Hcm91cENhbGxMZWF2ZRIXCgdjYWxsX2lkGAEgASgMUgZjYWxsSWQ=');

@$core.Deprecated('Use groupCallVideoDescriptor instead')
const GroupCallVideo$json = {
  '1': 'GroupCallVideo',
  '2': [
    {'1': 'call_id', '3': 1, '4': 1, '5': 12, '10': 'callId'},
    {'1': 'sender_node_id', '3': 2, '4': 1, '5': 12, '10': 'senderNodeId'},
    {'1': 'video_frame_data', '3': 3, '4': 1, '5': 12, '10': 'videoFrameData'},
  ],
};

/// Descriptor for `GroupCallVideo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List groupCallVideoDescriptor = $convert.base64Decode(
    'Cg5Hcm91cENhbGxWaWRlbxIXCgdjYWxsX2lkGAEgASgMUgZjYWxsSWQSJAoOc2VuZGVyX25vZG'
    'VfaWQYAiABKAxSDHNlbmRlck5vZGVJZBIoChB2aWRlb19mcmFtZV9kYXRhGAMgASgMUg52aWRl'
    'b0ZyYW1lRGF0YQ==');

@$core.Deprecated('Use groupCallSenderKeyDescriptor instead')
const GroupCallSenderKey$json = {
  '1': 'GroupCallSenderKey',
  '2': [
    {'1': 'call_id', '3': 1, '4': 1, '5': 12, '10': 'callId'},
    {'1': 'sender_node_id', '3': 2, '4': 1, '5': 12, '10': 'senderNodeId'},
    {'1': 'send_key', '3': 3, '4': 1, '5': 12, '10': 'sendKey'},
    {'1': 'key_version', '3': 4, '4': 1, '5': 13, '10': 'keyVersion'},
    {'1': 'd_eph_x25519_pk', '3': 5, '4': 1, '5': 12, '10': 'dEphX25519Pk'},
    {'1': 'd_kem_ciphertext', '3': 6, '4': 1, '5': 12, '10': 'dKemCiphertext'},
    {'1': 'd_cookie', '3': 7, '4': 1, '5': 12, '10': 'dCookie'},
    {'1': 'd_candidates', '3': 8, '4': 1, '5': 12, '10': 'dCandidates'},
    {'1': 'joined_participants', '3': 9, '4': 3, '5': 12, '10': 'joinedParticipants'},
  ],
};

/// Descriptor for `GroupCallSenderKey`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List groupCallSenderKeyDescriptor = $convert.base64Decode(
    'ChJHcm91cENhbGxTZW5kZXJLZXkSFwoHY2FsbF9pZBgBIAEoDFIGY2FsbElkEiQKDnNlbmRlcl'
    '9ub2RlX2lkGAIgASgMUgxzZW5kZXJOb2RlSWQSGQoIc2VuZF9rZXkYAyABKAxSB3NlbmRLZXkS'
    'HwoLa2V5X3ZlcnNpb24YBCABKA1SCmtleVZlcnNpb24SJQoPZF9lcGhfeDI1NTE5X3BrGAUgAS'
    'gMUgxkRXBoWDI1NTE5UGsSKAoQZF9rZW1fY2lwaGVydGV4dBgGIAEoDFIOZEtlbUNpcGhlcnRl'
    'eHQSGQoIZF9jb29raWUYByABKAxSB2RDb29raWUSIQoMZF9jYW5kaWRhdGVzGAggASgMUgtkQ2'
    'FuZGlkYXRlcxIvChNqb2luZWRfcGFydGljaXBhbnRzGAkgAygMUhJqb2luZWRQYXJ0aWNpcGFu'
    'dHM=');

@$core.Deprecated('Use whiteboardStrokeDescriptor instead')
const WhiteboardStroke$json = {
  '1': 'WhiteboardStroke',
  '2': [
    {'1': 'stroke_id', '3': 1, '4': 1, '5': 12, '10': 'strokeId'},
    {'1': 'author_id', '3': 2, '4': 1, '5': 12, '10': 'authorId'},
    {'1': 'author_name', '3': 3, '4': 1, '5': 9, '10': 'authorName'},
    {'1': 'tool', '3': 4, '4': 1, '5': 5, '10': 'tool'},
    {'1': 'color', '3': 5, '4': 1, '5': 5, '10': 'color'},
    {'1': 'stroke_width', '3': 6, '4': 1, '5': 2, '10': 'strokeWidth'},
    {'1': 'points', '3': 7, '4': 3, '5': 2, '10': 'points'},
    {'1': 'text', '3': 8, '4': 1, '5': 9, '10': 'text'},
    {'1': 'shape_type', '3': 9, '4': 1, '5': 5, '10': 'shapeType'},
    {'1': 'timestamp', '3': 10, '4': 1, '5': 3, '10': 'timestamp'},
    {'1': 'action_type', '3': 11, '4': 1, '5': 5, '10': 'actionType'},
    {'1': 'page_index', '3': 12, '4': 1, '5': 5, '10': 'pageIndex'},
  ],
};

/// Descriptor for `WhiteboardStroke`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List whiteboardStrokeDescriptor = $convert.base64Decode(
    'ChBXaGl0ZWJvYXJkU3Ryb2tlEhsKCXN0cm9rZV9pZBgBIAEoDFIIc3Ryb2tlSWQSGwoJYXV0aG'
    '9yX2lkGAIgASgMUghhdXRob3JJZBIfCgthdXRob3JfbmFtZRgDIAEoCVIKYXV0aG9yTmFtZRIS'
    'CgR0b29sGAQgASgFUgR0b29sEhQKBWNvbG9yGAUgASgFUgVjb2xvchIhCgxzdHJva2Vfd2lkdG'
    'gYBiABKAJSC3N0cm9rZVdpZHRoEhYKBnBvaW50cxgHIAMoAlIGcG9pbnRzEhIKBHRleHQYCCAB'
    'KAlSBHRleHQSHQoKc2hhcGVfdHlwZRgJIAEoBVIJc2hhcGVUeXBlEhwKCXRpbWVzdGFtcBgKIA'
    'EoA1IJdGltZXN0YW1wEh8KC2FjdGlvbl90eXBlGAsgASgFUgphY3Rpb25UeXBlEh0KCnBhZ2Vf'
    'aW5kZXgYDCABKAVSCXBhZ2VJbmRleA==');

@$core.Deprecated('Use whiteboardPageDescriptor instead')
const WhiteboardPage$json = {
  '1': 'WhiteboardPage',
  '2': [
    {'1': 'action', '3': 1, '4': 1, '5': 5, '10': 'action'},
    {'1': 'page_index', '3': 2, '4': 1, '5': 5, '10': 'pageIndex'},
    {'1': 'total_pages', '3': 3, '4': 1, '5': 5, '10': 'totalPages'},
    {'1': 'strokes', '3': 4, '4': 3, '5': 11, '6': '.cleona.WhiteboardStroke', '10': 'strokes'},
    {'1': 'requester_id', '3': 5, '4': 1, '5': 12, '10': 'requesterId'},
  ],
};

/// Descriptor for `WhiteboardPage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List whiteboardPageDescriptor = $convert.base64Decode(
    'Cg5XaGl0ZWJvYXJkUGFnZRIWCgZhY3Rpb24YASABKAVSBmFjdGlvbhIdCgpwYWdlX2luZGV4GA'
    'IgASgFUglwYWdlSW5kZXgSHwoLdG90YWxfcGFnZXMYAyABKAVSCnRvdGFsUGFnZXMSMgoHc3Ry'
    'b2tlcxgEIAMoCzIYLmNsZW9uYS5XaGl0ZWJvYXJkU3Ryb2tlUgdzdHJva2VzEiEKDHJlcXVlc3'
    'Rlcl9pZBgFIAEoDFILcmVxdWVzdGVySWQ=');

@$core.Deprecated('Use callFileShareDescriptor instead')
const CallFileShare$json = {
  '1': 'CallFileShare',
  '2': [
    {'1': 'file_id', '3': 1, '4': 1, '5': 12, '10': 'fileId'},
    {'1': 'file_name', '3': 2, '4': 1, '5': 9, '10': 'fileName'},
    {'1': 'file_size', '3': 3, '4': 1, '5': 3, '10': 'fileSize'},
    {'1': 'mime_type', '3': 4, '4': 1, '5': 9, '10': 'mimeType'},
    {'1': 'thumbnail_data', '3': 5, '4': 1, '5': 12, '10': 'thumbnailData'},
    {'1': 'shared_by', '3': 6, '4': 1, '5': 12, '10': 'sharedBy'},
    {'1': 'shared_by_name', '3': 7, '4': 1, '5': 9, '10': 'sharedByName'},
    {'1': 'action', '3': 8, '4': 1, '5': 5, '10': 'action'},
  ],
};

/// Descriptor for `CallFileShare`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List callFileShareDescriptor = $convert.base64Decode(
    'Cg1DYWxsRmlsZVNoYXJlEhcKB2ZpbGVfaWQYASABKAxSBmZpbGVJZBIbCglmaWxlX25hbWUYAi'
    'ABKAlSCGZpbGVOYW1lEhsKCWZpbGVfc2l6ZRgDIAEoA1IIZmlsZVNpemUSGwoJbWltZV90eXBl'
    'GAQgASgJUghtaW1lVHlwZRIlCg50aHVtYm5haWxfZGF0YRgFIAEoDFINdGh1bWJuYWlsRGF0YR'
    'IbCglzaGFyZWRfYnkYBiABKAxSCHNoYXJlZEJ5EiQKDnNoYXJlZF9ieV9uYW1lGAcgASgJUgxz'
    'aGFyZWRCeU5hbWUSFgoGYWN0aW9uGAggASgFUgZhY3Rpb24=');

@$core.Deprecated('Use callClipboardExchangeDescriptor instead')
const CallClipboardExchange$json = {
  '1': 'CallClipboardExchange',
  '2': [
    {'1': 'sender_id', '3': 1, '4': 1, '5': 12, '10': 'senderId'},
    {'1': 'sender_name', '3': 2, '4': 1, '5': 9, '10': 'senderName'},
    {'1': 'text_content', '3': 3, '4': 1, '5': 9, '10': 'textContent'},
    {'1': 'image_data', '3': 4, '4': 1, '5': 12, '10': 'imageData'},
    {'1': 'content_type', '3': 5, '4': 1, '5': 9, '10': 'contentType'},
    {'1': 'timestamp', '3': 6, '4': 1, '5': 3, '10': 'timestamp'},
  ],
};

/// Descriptor for `CallClipboardExchange`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List callClipboardExchangeDescriptor = $convert.base64Decode(
    'ChVDYWxsQ2xpcGJvYXJkRXhjaGFuZ2USGwoJc2VuZGVyX2lkGAEgASgMUghzZW5kZXJJZBIfCg'
    'tzZW5kZXJfbmFtZRgCIAEoCVIKc2VuZGVyTmFtZRIhCgx0ZXh0X2NvbnRlbnQYAyABKAlSC3Rl'
    'eHRDb250ZW50Eh0KCmltYWdlX2RhdGEYBCABKAxSCWltYWdlRGF0YRIhCgxjb250ZW50X3R5cG'
    'UYBSABKAlSC2NvbnRlbnRUeXBlEhwKCXRpbWVzdGFtcBgGIAEoA1IJdGltZXN0YW1w');

@$core.Deprecated('Use screenShareControlDescriptor instead')
const ScreenShareControl$json = {
  '1': 'ScreenShareControl',
  '2': [
    {'1': 'is_sharing', '3': 1, '4': 1, '5': 8, '10': 'isSharing'},
    {'1': 'width', '3': 2, '4': 1, '5': 5, '10': 'width'},
    {'1': 'height', '3': 3, '4': 1, '5': 5, '10': 'height'},
    {'1': 'fps', '3': 4, '4': 1, '5': 5, '10': 'fps'},
    {'1': 'optimize_for_text', '3': 5, '4': 1, '5': 8, '10': 'optimizeForText'},
    {'1': 'sharer_id', '3': 6, '4': 1, '5': 12, '10': 'sharerId'},
  ],
};

/// Descriptor for `ScreenShareControl`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List screenShareControlDescriptor = $convert.base64Decode(
    'ChJTY3JlZW5TaGFyZUNvbnRyb2wSHQoKaXNfc2hhcmluZxgBIAEoCFIJaXNTaGFyaW5nEhQKBX'
    'dpZHRoGAIgASgFUgV3aWR0aBIWCgZoZWlnaHQYAyABKAVSBmhlaWdodBIQCgNmcHMYBCABKAVS'
    'A2ZwcxIqChFvcHRpbWl6ZV9mb3JfdGV4dBgFIAEoCFIPb3B0aW1pemVGb3JUZXh0EhsKCXNoYX'
    'Jlcl9pZBgGIAEoDFIIc2hhcmVySWQ=');

@$core.Deprecated('Use callChatMessageDescriptor instead')
const CallChatMessage$json = {
  '1': 'CallChatMessage',
  '2': [
    {'1': 'message_id', '3': 1, '4': 1, '5': 12, '10': 'messageId'},
    {'1': 'sender_id', '3': 2, '4': 1, '5': 12, '10': 'senderId'},
    {'1': 'sender_name', '3': 3, '4': 1, '5': 9, '10': 'senderName'},
    {'1': 'text', '3': 4, '4': 1, '5': 9, '10': 'text'},
    {'1': 'timestamp', '3': 5, '4': 1, '5': 3, '10': 'timestamp'},
    {'1': 'reply_to_id', '3': 6, '4': 1, '5': 12, '10': 'replyToId'},
  ],
};

/// Descriptor for `CallChatMessage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List callChatMessageDescriptor = $convert.base64Decode(
    'Cg9DYWxsQ2hhdE1lc3NhZ2USHQoKbWVzc2FnZV9pZBgBIAEoDFIJbWVzc2FnZUlkEhsKCXNlbm'
    'Rlcl9pZBgCIAEoDFIIc2VuZGVySWQSHwoLc2VuZGVyX25hbWUYAyABKAlSCnNlbmRlck5hbWUS'
    'EgoEdGV4dBgEIAEoCVIEdGV4dBIcCgl0aW1lc3RhbXAYBSABKANSCXRpbWVzdGFtcBIeCgtyZX'
    'BseV90b19pZBgGIAEoDFIJcmVwbHlUb0lk');

@$core.Deprecated('Use voicePayloadDescriptor instead')
const VoicePayload$json = {
  '1': 'VoicePayload',
  '2': [
    {'1': 'audio_data', '3': 1, '4': 1, '5': 12, '10': 'audioData'},
    {'1': 'transcript_text', '3': 2, '4': 1, '5': 9, '10': 'transcriptText'},
    {'1': 'transcript_language', '3': 3, '4': 1, '5': 9, '10': 'transcriptLanguage'},
    {'1': 'transcript_confidence', '3': 4, '4': 1, '5': 2, '10': 'transcriptConfidence'},
  ],
};

/// Descriptor for `VoicePayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List voicePayloadDescriptor = $convert.base64Decode(
    'CgxWb2ljZVBheWxvYWQSHQoKYXVkaW9fZGF0YRgBIAEoDFIJYXVkaW9EYXRhEicKD3RyYW5zY3'
    'JpcHRfdGV4dBgCIAEoCVIOdHJhbnNjcmlwdFRleHQSLwoTdHJhbnNjcmlwdF9sYW5ndWFnZRgD'
    'IAEoCVISdHJhbnNjcmlwdExhbmd1YWdlEjMKFXRyYW5zY3JpcHRfY29uZmlkZW5jZRgEIAEoAl'
    'IUdHJhbnNjcmlwdENvbmZpZGVuY2U=');

@$core.Deprecated('Use twinSyncEnvelopeDescriptor instead')
const TwinSyncEnvelope$json = {
  '1': 'TwinSyncEnvelope',
  '2': [
    {'1': 'sync_id', '3': 1, '4': 1, '5': 12, '10': 'syncId'},
    {'1': 'device_id', '3': 2, '4': 1, '5': 12, '10': 'deviceId'},
    {'1': 'timestamp', '3': 3, '4': 1, '5': 4, '10': 'timestamp'},
    {'1': 'sync_type', '3': 4, '4': 1, '5': 14, '6': '.cleona.TwinSyncType', '10': 'syncType'},
    {'1': 'payload', '3': 5, '4': 1, '5': 12, '10': 'payload'},
  ],
};

/// Descriptor for `TwinSyncEnvelope`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List twinSyncEnvelopeDescriptor = $convert.base64Decode(
    'ChBUd2luU3luY0VudmVsb3BlEhcKB3N5bmNfaWQYASABKAxSBnN5bmNJZBIbCglkZXZpY2VfaW'
    'QYAiABKAxSCGRldmljZUlkEhwKCXRpbWVzdGFtcBgDIAEoBFIJdGltZXN0YW1wEjEKCXN5bmNf'
    'dHlwZRgEIAEoDjIULmNsZW9uYS5Ud2luU3luY1R5cGVSCHN5bmNUeXBlEhgKB3BheWxvYWQYBS'
    'ABKAxSB3BheWxvYWQ=');

@$core.Deprecated('Use deviceRecordDescriptor instead')
const DeviceRecord$json = {
  '1': 'DeviceRecord',
  '2': [
    {'1': 'device_id', '3': 1, '4': 1, '5': 12, '10': 'deviceId'},
    {'1': 'device_name', '3': 2, '4': 1, '5': 9, '10': 'deviceName'},
    {'1': 'platform', '3': 3, '4': 1, '5': 14, '6': '.cleona.DevicePlatform', '10': 'platform'},
    {'1': 'first_seen', '3': 4, '4': 1, '5': 4, '10': 'firstSeen'},
    {'1': 'last_seen', '3': 5, '4': 1, '5': 4, '10': 'lastSeen'},
    {'1': 'addresses', '3': 6, '4': 3, '5': 11, '6': '.cleona.PeerAddressProto', '10': 'addresses'},
    {'1': 'is_this_device', '3': 7, '4': 1, '5': 8, '10': 'isThisDevice'},
    {'1': 'device_node_id', '3': 8, '4': 1, '5': 12, '10': 'deviceNodeId'},
  ],
};

/// Descriptor for `DeviceRecord`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deviceRecordDescriptor = $convert.base64Decode(
    'CgxEZXZpY2VSZWNvcmQSGwoJZGV2aWNlX2lkGAEgASgMUghkZXZpY2VJZBIfCgtkZXZpY2Vfbm'
    'FtZRgCIAEoCVIKZGV2aWNlTmFtZRIyCghwbGF0Zm9ybRgDIAEoDjIWLmNsZW9uYS5EZXZpY2VQ'
    'bGF0Zm9ybVIIcGxhdGZvcm0SHQoKZmlyc3Rfc2VlbhgEIAEoBFIJZmlyc3RTZWVuEhsKCWxhc3'
    'Rfc2VlbhgFIAEoBFIIbGFzdFNlZW4SNgoJYWRkcmVzc2VzGAYgAygLMhguY2xlb25hLlBlZXJB'
    'ZGRyZXNzUHJvdG9SCWFkZHJlc3NlcxIkCg5pc190aGlzX2RldmljZRgHIAEoCFIMaXNUaGlzRG'
    'V2aWNlEiQKDmRldmljZV9ub2RlX2lkGAggASgMUgxkZXZpY2VOb2RlSWQ=');

@$core.Deprecated('Use keyRotationBroadcastDescriptor instead')
const KeyRotationBroadcast$json = {
  '1': 'KeyRotationBroadcast',
  '2': [
    {'1': 'new_ed25519_pk', '3': 1, '4': 1, '5': 12, '10': 'newEd25519Pk'},
    {'1': 'new_ml_dsa_pk', '3': 2, '4': 1, '5': 12, '10': 'newMlDsaPk'},
    {'1': 'new_x25519_pk', '3': 3, '4': 1, '5': 12, '10': 'newX25519Pk'},
    {'1': 'new_ml_kem_pk', '3': 4, '4': 1, '5': 12, '10': 'newMlKemPk'},
    {'1': 'old_signature_ed25519', '3': 5, '4': 1, '5': 12, '10': 'oldSignatureEd25519'},
    {'1': 'new_signature_ed25519', '3': 6, '4': 1, '5': 12, '10': 'newSignatureEd25519'},
    {'1': 'approval_tokens', '3': 7, '4': 3, '5': 11, '6': '.cleona.RotationApprovalToken', '10': 'approvalTokens'},
    {'1': 'pre_rotation_device_count', '3': 8, '4': 1, '5': 13, '10': 'preRotationDeviceCount'},
  ],
};

/// Descriptor for `KeyRotationBroadcast`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List keyRotationBroadcastDescriptor = $convert.base64Decode(
    'ChRLZXlSb3RhdGlvbkJyb2FkY2FzdBIkCg5uZXdfZWQyNTUxOV9waxgBIAEoDFIMbmV3RWQyNT'
    'UxOVBrEiEKDW5ld19tbF9kc2FfcGsYAiABKAxSCm5ld01sRHNhUGsSIgoNbmV3X3gyNTUxOV9w'
    'axgDIAEoDFILbmV3WDI1NTE5UGsSIQoNbmV3X21sX2tlbV9waxgEIAEoDFIKbmV3TWxLZW1Qax'
    'IyChVvbGRfc2lnbmF0dXJlX2VkMjU1MTkYBSABKAxSE29sZFNpZ25hdHVyZUVkMjU1MTkSMgoV'
    'bmV3X3NpZ25hdHVyZV9lZDI1NTE5GAYgASgMUhNuZXdTaWduYXR1cmVFZDI1NTE5EkYKD2FwcH'
    'JvdmFsX3Rva2VucxgHIAMoCzIdLmNsZW9uYS5Sb3RhdGlvbkFwcHJvdmFsVG9rZW5SDmFwcHJv'
    'dmFsVG9rZW5zEjkKGXByZV9yb3RhdGlvbl9kZXZpY2VfY291bnQYCCABKA1SFnByZVJvdGF0aW'
    '9uRGV2aWNlQ291bnQ=');

@$core.Deprecated('Use calendarReminderOffsetDescriptor instead')
const CalendarReminderOffset$json = {
  '1': 'CalendarReminderOffset',
  '2': [
    {'1': 'minutes_before', '3': 1, '4': 1, '5': 5, '10': 'minutesBefore'},
  ],
};

/// Descriptor for `CalendarReminderOffset`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List calendarReminderOffsetDescriptor = $convert.base64Decode(
    'ChZDYWxlbmRhclJlbWluZGVyT2Zmc2V0EiUKDm1pbnV0ZXNfYmVmb3JlGAEgASgFUg1taW51dG'
    'VzQmVmb3Jl');

@$core.Deprecated('Use calendarInviteMsgDescriptor instead')
const CalendarInviteMsg$json = {
  '1': 'CalendarInviteMsg',
  '2': [
    {'1': 'event_id', '3': 1, '4': 1, '5': 12, '10': 'eventId'},
    {'1': 'title', '3': 2, '4': 1, '5': 9, '10': 'title'},
    {'1': 'description', '3': 3, '4': 1, '5': 9, '10': 'description'},
    {'1': 'location', '3': 4, '4': 1, '5': 9, '10': 'location'},
    {'1': 'start_time', '3': 5, '4': 1, '5': 3, '10': 'startTime'},
    {'1': 'end_time', '3': 6, '4': 1, '5': 3, '10': 'endTime'},
    {'1': 'all_day', '3': 7, '4': 1, '5': 8, '10': 'allDay'},
    {'1': 'time_zone', '3': 8, '4': 1, '5': 9, '10': 'timeZone'},
    {'1': 'recurrence_rule', '3': 9, '4': 1, '5': 9, '10': 'recurrenceRule'},
    {'1': 'has_call', '3': 10, '4': 1, '5': 8, '10': 'hasCall'},
    {'1': 'group_id', '3': 11, '4': 1, '5': 12, '10': 'groupId'},
    {'1': 'created_by', '3': 12, '4': 1, '5': 12, '10': 'createdBy'},
    {'1': 'created_by_name', '3': 13, '4': 1, '5': 9, '10': 'createdByName'},
    {'1': 'rsvp_deadline', '3': 14, '4': 1, '5': 3, '10': 'rsvpDeadline'},
    {'1': 'category', '3': 15, '4': 1, '5': 14, '6': '.cleona.EventCategory', '10': 'category'},
    {'1': 'reminders', '3': 16, '4': 3, '5': 11, '6': '.cleona.CalendarReminderOffset', '10': 'reminders'},
    {'1': 'attendee_node_ids', '3': 17, '4': 3, '5': 12, '10': 'attendeeNodeIds'},
  ],
};

/// Descriptor for `CalendarInviteMsg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List calendarInviteMsgDescriptor = $convert.base64Decode(
    'ChFDYWxlbmRhckludml0ZU1zZxIZCghldmVudF9pZBgBIAEoDFIHZXZlbnRJZBIUCgV0aXRsZR'
    'gCIAEoCVIFdGl0bGUSIAoLZGVzY3JpcHRpb24YAyABKAlSC2Rlc2NyaXB0aW9uEhoKCGxvY2F0'
    'aW9uGAQgASgJUghsb2NhdGlvbhIdCgpzdGFydF90aW1lGAUgASgDUglzdGFydFRpbWUSGQoIZW'
    '5kX3RpbWUYBiABKANSB2VuZFRpbWUSFwoHYWxsX2RheRgHIAEoCFIGYWxsRGF5EhsKCXRpbWVf'
    'em9uZRgIIAEoCVIIdGltZVpvbmUSJwoPcmVjdXJyZW5jZV9ydWxlGAkgASgJUg5yZWN1cnJlbm'
    'NlUnVsZRIZCghoYXNfY2FsbBgKIAEoCFIHaGFzQ2FsbBIZCghncm91cF9pZBgLIAEoDFIHZ3Jv'
    'dXBJZBIdCgpjcmVhdGVkX2J5GAwgASgMUgljcmVhdGVkQnkSJgoPY3JlYXRlZF9ieV9uYW1lGA'
    '0gASgJUg1jcmVhdGVkQnlOYW1lEiMKDXJzdnBfZGVhZGxpbmUYDiABKANSDHJzdnBEZWFkbGlu'
    'ZRIxCghjYXRlZ29yeRgPIAEoDjIVLmNsZW9uYS5FdmVudENhdGVnb3J5UghjYXRlZ29yeRI8Cg'
    'lyZW1pbmRlcnMYECADKAsyHi5jbGVvbmEuQ2FsZW5kYXJSZW1pbmRlck9mZnNldFIJcmVtaW5k'
    'ZXJzEioKEWF0dGVuZGVlX25vZGVfaWRzGBEgAygMUg9hdHRlbmRlZU5vZGVJZHM=');

@$core.Deprecated('Use calendarRsvpMsgDescriptor instead')
const CalendarRsvpMsg$json = {
  '1': 'CalendarRsvpMsg',
  '2': [
    {'1': 'event_id', '3': 1, '4': 1, '5': 12, '10': 'eventId'},
    {'1': 'response', '3': 2, '4': 1, '5': 14, '6': '.cleona.RsvpStatus', '10': 'response'},
    {'1': 'proposed_start', '3': 3, '4': 1, '5': 3, '10': 'proposedStart'},
    {'1': 'proposed_end', '3': 4, '4': 1, '5': 3, '10': 'proposedEnd'},
    {'1': 'comment', '3': 5, '4': 1, '5': 9, '10': 'comment'},
  ],
};

/// Descriptor for `CalendarRsvpMsg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List calendarRsvpMsgDescriptor = $convert.base64Decode(
    'Cg9DYWxlbmRhclJzdnBNc2cSGQoIZXZlbnRfaWQYASABKAxSB2V2ZW50SWQSLgoIcmVzcG9uc2'
    'UYAiABKA4yEi5jbGVvbmEuUnN2cFN0YXR1c1IIcmVzcG9uc2USJQoOcHJvcG9zZWRfc3RhcnQY'
    'AyABKANSDXByb3Bvc2VkU3RhcnQSIQoMcHJvcG9zZWRfZW5kGAQgASgDUgtwcm9wb3NlZEVuZB'
    'IYCgdjb21tZW50GAUgASgJUgdjb21tZW50');

@$core.Deprecated('Use calendarUpdateMsgDescriptor instead')
const CalendarUpdateMsg$json = {
  '1': 'CalendarUpdateMsg',
  '2': [
    {'1': 'event_id', '3': 1, '4': 1, '5': 12, '10': 'eventId'},
    {'1': 'title', '3': 2, '4': 1, '5': 9, '10': 'title'},
    {'1': 'description', '3': 3, '4': 1, '5': 9, '10': 'description'},
    {'1': 'location', '3': 4, '4': 1, '5': 9, '10': 'location'},
    {'1': 'start_time', '3': 5, '4': 1, '5': 3, '10': 'startTime'},
    {'1': 'end_time', '3': 6, '4': 1, '5': 3, '10': 'endTime'},
    {'1': 'all_day', '3': 7, '4': 1, '5': 8, '10': 'allDay'},
    {'1': 'time_zone', '3': 8, '4': 1, '5': 9, '10': 'timeZone'},
    {'1': 'recurrence_rule', '3': 9, '4': 1, '5': 9, '10': 'recurrenceRule'},
    {'1': 'has_call', '3': 10, '4': 1, '5': 8, '10': 'hasCall'},
    {'1': 'cancelled', '3': 11, '4': 1, '5': 8, '10': 'cancelled'},
    {'1': 'updated_at', '3': 12, '4': 1, '5': 3, '10': 'updatedAt'},
    {'1': 'reminders', '3': 13, '4': 3, '5': 11, '6': '.cleona.CalendarReminderOffset', '10': 'reminders'},
  ],
};

/// Descriptor for `CalendarUpdateMsg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List calendarUpdateMsgDescriptor = $convert.base64Decode(
    'ChFDYWxlbmRhclVwZGF0ZU1zZxIZCghldmVudF9pZBgBIAEoDFIHZXZlbnRJZBIUCgV0aXRsZR'
    'gCIAEoCVIFdGl0bGUSIAoLZGVzY3JpcHRpb24YAyABKAlSC2Rlc2NyaXB0aW9uEhoKCGxvY2F0'
    'aW9uGAQgASgJUghsb2NhdGlvbhIdCgpzdGFydF90aW1lGAUgASgDUglzdGFydFRpbWUSGQoIZW'
    '5kX3RpbWUYBiABKANSB2VuZFRpbWUSFwoHYWxsX2RheRgHIAEoCFIGYWxsRGF5EhsKCXRpbWVf'
    'em9uZRgIIAEoCVIIdGltZVpvbmUSJwoPcmVjdXJyZW5jZV9ydWxlGAkgASgJUg5yZWN1cnJlbm'
    'NlUnVsZRIZCghoYXNfY2FsbBgKIAEoCFIHaGFzQ2FsbBIcCgljYW5jZWxsZWQYCyABKAhSCWNh'
    'bmNlbGxlZBIdCgp1cGRhdGVkX2F0GAwgASgDUgl1cGRhdGVkQXQSPAoJcmVtaW5kZXJzGA0gAy'
    'gLMh4uY2xlb25hLkNhbGVuZGFyUmVtaW5kZXJPZmZzZXRSCXJlbWluZGVycw==');

@$core.Deprecated('Use calendarDeleteMsgDescriptor instead')
const CalendarDeleteMsg$json = {
  '1': 'CalendarDeleteMsg',
  '2': [
    {'1': 'event_id', '3': 1, '4': 1, '5': 12, '10': 'eventId'},
    {'1': 'deleted_at', '3': 2, '4': 1, '5': 3, '10': 'deletedAt'},
  ],
};

/// Descriptor for `CalendarDeleteMsg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List calendarDeleteMsgDescriptor = $convert.base64Decode(
    'ChFDYWxlbmRhckRlbGV0ZU1zZxIZCghldmVudF9pZBgBIAEoDFIHZXZlbnRJZBIdCgpkZWxldG'
    'VkX2F0GAIgASgDUglkZWxldGVkQXQ=');

@$core.Deprecated('Use freeBusyRequestMsgDescriptor instead')
const FreeBusyRequestMsg$json = {
  '1': 'FreeBusyRequestMsg',
  '2': [
    {'1': 'query_start', '3': 1, '4': 1, '5': 3, '10': 'queryStart'},
    {'1': 'query_end', '3': 2, '4': 1, '5': 3, '10': 'queryEnd'},
    {'1': 'request_id', '3': 3, '4': 1, '5': 12, '10': 'requestId'},
  ],
};

/// Descriptor for `FreeBusyRequestMsg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List freeBusyRequestMsgDescriptor = $convert.base64Decode(
    'ChJGcmVlQnVzeVJlcXVlc3RNc2cSHwoLcXVlcnlfc3RhcnQYASABKANSCnF1ZXJ5U3RhcnQSGw'
    'oJcXVlcnlfZW5kGAIgASgDUghxdWVyeUVuZBIdCgpyZXF1ZXN0X2lkGAMgASgMUglyZXF1ZXN0'
    'SWQ=');

@$core.Deprecated('Use freeBusyResponseMsgDescriptor instead')
const FreeBusyResponseMsg$json = {
  '1': 'FreeBusyResponseMsg',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 12, '10': 'requestId'},
    {'1': 'blocks', '3': 2, '4': 3, '5': 11, '6': '.cleona.FreeBusyBlock', '10': 'blocks'},
  ],
};

/// Descriptor for `FreeBusyResponseMsg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List freeBusyResponseMsgDescriptor = $convert.base64Decode(
    'ChNGcmVlQnVzeVJlc3BvbnNlTXNnEh0KCnJlcXVlc3RfaWQYASABKAxSCXJlcXVlc3RJZBItCg'
    'ZibG9ja3MYAiADKAsyFS5jbGVvbmEuRnJlZUJ1c3lCbG9ja1IGYmxvY2tz');

@$core.Deprecated('Use freeBusyBlockDescriptor instead')
const FreeBusyBlock$json = {
  '1': 'FreeBusyBlock',
  '2': [
    {'1': 'start', '3': 1, '4': 1, '5': 3, '10': 'start'},
    {'1': 'end', '3': 2, '4': 1, '5': 3, '10': 'end'},
    {'1': 'level', '3': 3, '4': 1, '5': 14, '6': '.cleona.FreeBusyLevel', '10': 'level'},
    {'1': 'title', '3': 4, '4': 1, '5': 9, '10': 'title'},
    {'1': 'location', '3': 5, '4': 1, '5': 9, '10': 'location'},
  ],
};

/// Descriptor for `FreeBusyBlock`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List freeBusyBlockDescriptor = $convert.base64Decode(
    'Cg1GcmVlQnVzeUJsb2NrEhQKBXN0YXJ0GAEgASgDUgVzdGFydBIQCgNlbmQYAiABKANSA2VuZB'
    'IrCgVsZXZlbBgDIAEoDjIVLmNsZW9uYS5GcmVlQnVzeUxldmVsUgVsZXZlbBIUCgV0aXRsZRgE'
    'IAEoCVIFdGl0bGUSGgoIbG9jYXRpb24YBSABKAlSCGxvY2F0aW9u');

@$core.Deprecated('Use pollOptionMsgDescriptor instead')
const PollOptionMsg$json = {
  '1': 'PollOptionMsg',
  '2': [
    {'1': 'option_id', '3': 1, '4': 1, '5': 5, '10': 'optionId'},
    {'1': 'label', '3': 2, '4': 1, '5': 9, '10': 'label'},
    {'1': 'date_start', '3': 3, '4': 1, '5': 3, '10': 'dateStart'},
    {'1': 'date_end', '3': 4, '4': 1, '5': 3, '10': 'dateEnd'},
  ],
};

/// Descriptor for `PollOptionMsg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pollOptionMsgDescriptor = $convert.base64Decode(
    'Cg1Qb2xsT3B0aW9uTXNnEhsKCW9wdGlvbl9pZBgBIAEoBVIIb3B0aW9uSWQSFAoFbGFiZWwYAi'
    'ABKAlSBWxhYmVsEh0KCmRhdGVfc3RhcnQYAyABKANSCWRhdGVTdGFydBIZCghkYXRlX2VuZBgE'
    'IAEoA1IHZGF0ZUVuZA==');

@$core.Deprecated('Use pollSettingsMsgDescriptor instead')
const PollSettingsMsg$json = {
  '1': 'PollSettingsMsg',
  '2': [
    {'1': 'anonymous', '3': 1, '4': 1, '5': 8, '10': 'anonymous'},
    {'1': 'deadline', '3': 2, '4': 1, '5': 3, '10': 'deadline'},
    {'1': 'allow_vote_change', '3': 3, '4': 1, '5': 8, '10': 'allowVoteChange'},
    {'1': 'show_results_before_close', '3': 4, '4': 1, '5': 8, '10': 'showResultsBeforeClose'},
    {'1': 'max_choices', '3': 5, '4': 1, '5': 5, '10': 'maxChoices'},
    {'1': 'scale_min', '3': 6, '4': 1, '5': 5, '10': 'scaleMin'},
    {'1': 'scale_max', '3': 7, '4': 1, '5': 5, '10': 'scaleMax'},
    {'1': 'only_members_can_vote', '3': 8, '4': 1, '5': 8, '10': 'onlyMembersCanVote'},
  ],
};

/// Descriptor for `PollSettingsMsg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pollSettingsMsgDescriptor = $convert.base64Decode(
    'Cg9Qb2xsU2V0dGluZ3NNc2cSHAoJYW5vbnltb3VzGAEgASgIUglhbm9ueW1vdXMSGgoIZGVhZG'
    'xpbmUYAiABKANSCGRlYWRsaW5lEioKEWFsbG93X3ZvdGVfY2hhbmdlGAMgASgIUg9hbGxvd1Zv'
    'dGVDaGFuZ2USOQoZc2hvd19yZXN1bHRzX2JlZm9yZV9jbG9zZRgEIAEoCFIWc2hvd1Jlc3VsdH'
    'NCZWZvcmVDbG9zZRIfCgttYXhfY2hvaWNlcxgFIAEoBVIKbWF4Q2hvaWNlcxIbCglzY2FsZV9t'
    'aW4YBiABKAVSCHNjYWxlTWluEhsKCXNjYWxlX21heBgHIAEoBVIIc2NhbGVNYXgSMQoVb25seV'
    '9tZW1iZXJzX2Nhbl92b3RlGAggASgIUhJvbmx5TWVtYmVyc0NhblZvdGU=');

@$core.Deprecated('Use pollCreateMsgDescriptor instead')
const PollCreateMsg$json = {
  '1': 'PollCreateMsg',
  '2': [
    {'1': 'poll_id', '3': 1, '4': 1, '5': 12, '10': 'pollId'},
    {'1': 'question', '3': 2, '4': 1, '5': 9, '10': 'question'},
    {'1': 'description', '3': 3, '4': 1, '5': 9, '10': 'description'},
    {'1': 'poll_type', '3': 4, '4': 1, '5': 14, '6': '.cleona.PollType', '10': 'pollType'},
    {'1': 'options', '3': 5, '4': 3, '5': 11, '6': '.cleona.PollOptionMsg', '10': 'options'},
    {'1': 'settings', '3': 6, '4': 1, '5': 11, '6': '.cleona.PollSettingsMsg', '10': 'settings'},
    {'1': 'group_id', '3': 7, '4': 1, '5': 12, '10': 'groupId'},
    {'1': 'created_by', '3': 8, '4': 1, '5': 12, '10': 'createdBy'},
    {'1': 'created_by_name', '3': 9, '4': 1, '5': 9, '10': 'createdByName'},
    {'1': 'created_at', '3': 10, '4': 1, '5': 3, '10': 'createdAt'},
  ],
};

/// Descriptor for `PollCreateMsg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pollCreateMsgDescriptor = $convert.base64Decode(
    'Cg1Qb2xsQ3JlYXRlTXNnEhcKB3BvbGxfaWQYASABKAxSBnBvbGxJZBIaCghxdWVzdGlvbhgCIA'
    'EoCVIIcXVlc3Rpb24SIAoLZGVzY3JpcHRpb24YAyABKAlSC2Rlc2NyaXB0aW9uEi0KCXBvbGxf'
    'dHlwZRgEIAEoDjIQLmNsZW9uYS5Qb2xsVHlwZVIIcG9sbFR5cGUSLwoHb3B0aW9ucxgFIAMoCz'
    'IVLmNsZW9uYS5Qb2xsT3B0aW9uTXNnUgdvcHRpb25zEjMKCHNldHRpbmdzGAYgASgLMhcuY2xl'
    'b25hLlBvbGxTZXR0aW5nc01zZ1IIc2V0dGluZ3MSGQoIZ3JvdXBfaWQYByABKAxSB2dyb3VwSW'
    'QSHQoKY3JlYXRlZF9ieRgIIAEoDFIJY3JlYXRlZEJ5EiYKD2NyZWF0ZWRfYnlfbmFtZRgJIAEo'
    'CVINY3JlYXRlZEJ5TmFtZRIdCgpjcmVhdGVkX2F0GAogASgDUgljcmVhdGVkQXQ=');

@$core.Deprecated('Use dateResponseMsgDescriptor instead')
const DateResponseMsg$json = {
  '1': 'DateResponseMsg',
  '2': [
    {'1': 'option_id', '3': 1, '4': 1, '5': 5, '10': 'optionId'},
    {'1': 'availability', '3': 2, '4': 1, '5': 14, '6': '.cleona.DateAvailability', '10': 'availability'},
  ],
};

/// Descriptor for `DateResponseMsg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List dateResponseMsgDescriptor = $convert.base64Decode(
    'Cg9EYXRlUmVzcG9uc2VNc2cSGwoJb3B0aW9uX2lkGAEgASgFUghvcHRpb25JZBI8CgxhdmFpbG'
    'FiaWxpdHkYAiABKA4yGC5jbGVvbmEuRGF0ZUF2YWlsYWJpbGl0eVIMYXZhaWxhYmlsaXR5');

@$core.Deprecated('Use pollVoteMsgDescriptor instead')
const PollVoteMsg$json = {
  '1': 'PollVoteMsg',
  '2': [
    {'1': 'poll_id', '3': 1, '4': 1, '5': 12, '10': 'pollId'},
    {'1': 'voter_id', '3': 2, '4': 1, '5': 12, '10': 'voterId'},
    {'1': 'voter_name', '3': 3, '4': 1, '5': 9, '10': 'voterName'},
    {'1': 'selected_options', '3': 4, '4': 3, '5': 5, '10': 'selectedOptions'},
    {'1': 'date_responses', '3': 5, '4': 3, '5': 11, '6': '.cleona.DateResponseMsg', '10': 'dateResponses'},
    {'1': 'scale_value', '3': 6, '4': 1, '5': 5, '10': 'scaleValue'},
    {'1': 'free_text', '3': 7, '4': 1, '5': 9, '10': 'freeText'},
    {'1': 'voted_at', '3': 8, '4': 1, '5': 3, '10': 'votedAt'},
  ],
};

/// Descriptor for `PollVoteMsg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pollVoteMsgDescriptor = $convert.base64Decode(
    'CgtQb2xsVm90ZU1zZxIXCgdwb2xsX2lkGAEgASgMUgZwb2xsSWQSGQoIdm90ZXJfaWQYAiABKA'
    'xSB3ZvdGVySWQSHQoKdm90ZXJfbmFtZRgDIAEoCVIJdm90ZXJOYW1lEikKEHNlbGVjdGVkX29w'
    'dGlvbnMYBCADKAVSD3NlbGVjdGVkT3B0aW9ucxI+Cg5kYXRlX3Jlc3BvbnNlcxgFIAMoCzIXLm'
    'NsZW9uYS5EYXRlUmVzcG9uc2VNc2dSDWRhdGVSZXNwb25zZXMSHwoLc2NhbGVfdmFsdWUYBiAB'
    'KAVSCnNjYWxlVmFsdWUSGwoJZnJlZV90ZXh0GAcgASgJUghmcmVlVGV4dBIZCgh2b3RlZF9hdB'
    'gIIAEoA1IHdm90ZWRBdA==');

@$core.Deprecated('Use pollUpdateMsgDescriptor instead')
const PollUpdateMsg$json = {
  '1': 'PollUpdateMsg',
  '2': [
    {'1': 'poll_id', '3': 1, '4': 1, '5': 12, '10': 'pollId'},
    {'1': 'action', '3': 2, '4': 1, '5': 14, '6': '.cleona.PollAction', '10': 'action'},
    {'1': 'updated_by', '3': 3, '4': 1, '5': 12, '10': 'updatedBy'},
    {'1': 'added_options', '3': 4, '4': 3, '5': 11, '6': '.cleona.PollOptionMsg', '10': 'addedOptions'},
    {'1': 'removed_options', '3': 5, '4': 3, '5': 5, '10': 'removedOptions'},
    {'1': 'new_deadline', '3': 6, '4': 1, '5': 3, '10': 'newDeadline'},
    {'1': 'updated_at', '3': 7, '4': 1, '5': 3, '10': 'updatedAt'},
  ],
};

/// Descriptor for `PollUpdateMsg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pollUpdateMsgDescriptor = $convert.base64Decode(
    'Cg1Qb2xsVXBkYXRlTXNnEhcKB3BvbGxfaWQYASABKAxSBnBvbGxJZBIqCgZhY3Rpb24YAiABKA'
    '4yEi5jbGVvbmEuUG9sbEFjdGlvblIGYWN0aW9uEh0KCnVwZGF0ZWRfYnkYAyABKAxSCXVwZGF0'
    'ZWRCeRI6Cg1hZGRlZF9vcHRpb25zGAQgAygLMhUuY2xlb25hLlBvbGxPcHRpb25Nc2dSDGFkZG'
    'VkT3B0aW9ucxInCg9yZW1vdmVkX29wdGlvbnMYBSADKAVSDnJlbW92ZWRPcHRpb25zEiEKDG5l'
    'd19kZWFkbGluZRgGIAEoA1ILbmV3RGVhZGxpbmUSHQoKdXBkYXRlZF9hdBgHIAEoA1IJdXBkYX'
    'RlZEF0');

@$core.Deprecated('Use optionCountMsgDescriptor instead')
const OptionCountMsg$json = {
  '1': 'OptionCountMsg',
  '2': [
    {'1': 'option_id', '3': 1, '4': 1, '5': 5, '10': 'optionId'},
    {'1': 'count', '3': 2, '4': 1, '5': 5, '10': 'count'},
    {'1': 'yes_count', '3': 3, '4': 1, '5': 5, '10': 'yesCount'},
    {'1': 'maybe_count', '3': 4, '4': 1, '5': 5, '10': 'maybeCount'},
    {'1': 'no_count', '3': 5, '4': 1, '5': 5, '10': 'noCount'},
  ],
};

/// Descriptor for `OptionCountMsg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List optionCountMsgDescriptor = $convert.base64Decode(
    'Cg5PcHRpb25Db3VudE1zZxIbCglvcHRpb25faWQYASABKAVSCG9wdGlvbklkEhQKBWNvdW50GA'
    'IgASgFUgVjb3VudBIbCgl5ZXNfY291bnQYAyABKAVSCHllc0NvdW50Eh8KC21heWJlX2NvdW50'
    'GAQgASgFUgptYXliZUNvdW50EhkKCG5vX2NvdW50GAUgASgFUgdub0NvdW50');

@$core.Deprecated('Use pollSnapshotMsgDescriptor instead')
const PollSnapshotMsg$json = {
  '1': 'PollSnapshotMsg',
  '2': [
    {'1': 'poll_id', '3': 1, '4': 1, '5': 12, '10': 'pollId'},
    {'1': 'total_votes', '3': 2, '4': 1, '5': 5, '10': 'totalVotes'},
    {'1': 'option_counts', '3': 3, '4': 3, '5': 11, '6': '.cleona.OptionCountMsg', '10': 'optionCounts'},
    {'1': 'scale_average', '3': 4, '4': 1, '5': 1, '10': 'scaleAverage'},
    {'1': 'scale_count', '3': 5, '4': 1, '5': 5, '10': 'scaleCount'},
    {'1': 'closed', '3': 6, '4': 1, '5': 8, '10': 'closed'},
    {'1': 'snapshot_at', '3': 7, '4': 1, '5': 3, '10': 'snapshotAt'},
  ],
};

/// Descriptor for `PollSnapshotMsg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pollSnapshotMsgDescriptor = $convert.base64Decode(
    'Cg9Qb2xsU25hcHNob3RNc2cSFwoHcG9sbF9pZBgBIAEoDFIGcG9sbElkEh8KC3RvdGFsX3ZvdG'
    'VzGAIgASgFUgp0b3RhbFZvdGVzEjsKDW9wdGlvbl9jb3VudHMYAyADKAsyFi5jbGVvbmEuT3B0'
    'aW9uQ291bnRNc2dSDG9wdGlvbkNvdW50cxIjCg1zY2FsZV9hdmVyYWdlGAQgASgBUgxzY2FsZU'
    'F2ZXJhZ2USHwoLc2NhbGVfY291bnQYBSABKAVSCnNjYWxlQ291bnQSFgoGY2xvc2VkGAYgASgI'
    'UgZjbG9zZWQSHwoLc25hcHNob3RfYXQYByABKANSCnNuYXBzaG90QXQ=');

@$core.Deprecated('Use pollVoteAnonymousMsgDescriptor instead')
const PollVoteAnonymousMsg$json = {
  '1': 'PollVoteAnonymousMsg',
  '2': [
    {'1': 'poll_id', '3': 1, '4': 1, '5': 12, '10': 'pollId'},
    {'1': 'encrypted_choice', '3': 2, '4': 1, '5': 12, '10': 'encryptedChoice'},
    {'1': 'key_image', '3': 3, '4': 1, '5': 12, '10': 'keyImage'},
    {'1': 'ring_signature', '3': 4, '4': 1, '5': 12, '10': 'ringSignature'},
    {'1': 'ring_members', '3': 5, '4': 3, '5': 12, '10': 'ringMembers'},
    {'1': 'voted_at', '3': 6, '4': 1, '5': 3, '10': 'votedAt'},
  ],
};

/// Descriptor for `PollVoteAnonymousMsg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pollVoteAnonymousMsgDescriptor = $convert.base64Decode(
    'ChRQb2xsVm90ZUFub255bW91c01zZxIXCgdwb2xsX2lkGAEgASgMUgZwb2xsSWQSKQoQZW5jcn'
    'lwdGVkX2Nob2ljZRgCIAEoDFIPZW5jcnlwdGVkQ2hvaWNlEhsKCWtleV9pbWFnZRgDIAEoDFII'
    'a2V5SW1hZ2USJQoOcmluZ19zaWduYXR1cmUYBCABKAxSDXJpbmdTaWduYXR1cmUSIQoMcmluZ1'
    '9tZW1iZXJzGAUgAygMUgtyaW5nTWVtYmVycxIZCgh2b3RlZF9hdBgGIAEoA1IHdm90ZWRBdA==');

@$core.Deprecated('Use pollVoteRevokeMsgDescriptor instead')
const PollVoteRevokeMsg$json = {
  '1': 'PollVoteRevokeMsg',
  '2': [
    {'1': 'poll_id', '3': 1, '4': 1, '5': 12, '10': 'pollId'},
    {'1': 'key_image', '3': 2, '4': 1, '5': 12, '10': 'keyImage'},
    {'1': 'ring_signature', '3': 3, '4': 1, '5': 12, '10': 'ringSignature'},
    {'1': 'ring_members', '3': 4, '4': 3, '5': 12, '10': 'ringMembers'},
    {'1': 'revoked_at', '3': 5, '4': 1, '5': 3, '10': 'revokedAt'},
  ],
};

/// Descriptor for `PollVoteRevokeMsg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pollVoteRevokeMsgDescriptor = $convert.base64Decode(
    'ChFQb2xsVm90ZVJldm9rZU1zZxIXCgdwb2xsX2lkGAEgASgMUgZwb2xsSWQSGwoJa2V5X2ltYW'
    'dlGAIgASgMUghrZXlJbWFnZRIlCg5yaW5nX3NpZ25hdHVyZRgDIAEoDFINcmluZ1NpZ25hdHVy'
    'ZRIhCgxyaW5nX21lbWJlcnMYBCADKAxSC3JpbmdNZW1iZXJzEh0KCnJldm9rZWRfYXQYBSABKA'
    'NSCXJldm9rZWRBdA==');

@$core.Deprecated('Use pollAnonSubmitEntryDescriptor instead')
const PollAnonSubmitEntry$json = {
  '1': 'PollAnonSubmitEntry',
  '2': [
    {'1': 'recipient_user_id', '3': 1, '4': 1, '5': 12, '10': 'recipientUserId'},
    {'1': 'kem_blob', '3': 2, '4': 1, '5': 12, '10': 'kemBlob'},
    {'1': 'device_ids', '3': 3, '4': 3, '5': 12, '10': 'deviceIds'},
  ],
};

/// Descriptor for `PollAnonSubmitEntry`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pollAnonSubmitEntryDescriptor = $convert.base64Decode(
    'ChNQb2xsQW5vblN1Ym1pdEVudHJ5EioKEXJlY2lwaWVudF91c2VyX2lkGAEgASgMUg9yZWNpcG'
    'llbnRVc2VySWQSGQoIa2VtX2Jsb2IYAiABKAxSB2tlbUJsb2ISHQoKZGV2aWNlX2lkcxgDIAMo'
    'DFIJZGV2aWNlSWRz');

@$core.Deprecated('Use pollAnonSubmitMsgDescriptor instead')
const PollAnonSubmitMsg$json = {
  '1': 'PollAnonSubmitMsg',
  '2': [
    {'1': 'poll_id', '3': 1, '4': 1, '5': 12, '10': 'pollId'},
    {'1': 'entries', '3': 2, '4': 3, '5': 11, '6': '.cleona.PollAnonSubmitEntry', '10': 'entries'},
    {'1': 'pow_nonce', '3': 3, '4': 1, '5': 4, '10': 'powNonce'},
  ],
};

/// Descriptor for `PollAnonSubmitMsg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pollAnonSubmitMsgDescriptor = $convert.base64Decode(
    'ChFQb2xsQW5vblN1Ym1pdE1zZxIXCgdwb2xsX2lkGAEgASgMUgZwb2xsSWQSNQoHZW50cmllcx'
    'gCIAMoCzIbLmNsZW9uYS5Qb2xsQW5vblN1Ym1pdEVudHJ5UgdlbnRyaWVzEhsKCXBvd19ub25j'
    'ZRgDIAEoBFIIcG93Tm9uY2U=');

@$core.Deprecated('Use pollAnonSubmitAckMsgDescriptor instead')
const PollAnonSubmitAckMsg$json = {
  '1': 'PollAnonSubmitAckMsg',
  '2': [
    {'1': 'poll_id', '3': 1, '4': 1, '5': 12, '10': 'pollId'},
    {'1': 'accepted', '3': 2, '4': 1, '5': 8, '10': 'accepted'},
    {'1': 'reject_reason', '3': 3, '4': 1, '5': 9, '10': 'rejectReason'},
  ],
};

/// Descriptor for `PollAnonSubmitAckMsg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pollAnonSubmitAckMsgDescriptor = $convert.base64Decode(
    'ChRQb2xsQW5vblN1Ym1pdEFja01zZxIXCgdwb2xsX2lkGAEgASgMUgZwb2xsSWQSGgoIYWNjZX'
    'B0ZWQYAiABKAhSCGFjY2VwdGVkEiMKDXJlamVjdF9yZWFzb24YAyABKAlSDHJlamVjdFJlYXNv'
    'bg==');

@$core.Deprecated('Use deviceDelegationCertProtoDescriptor instead')
const DeviceDelegationCertProto$json = {
  '1': 'DeviceDelegationCertProto',
  '2': [
    {'1': 'device_id', '3': 1, '4': 1, '5': 12, '10': 'deviceId'},
    {'1': 'delegated_ed25519_pk', '3': 2, '4': 1, '5': 12, '10': 'delegatedEd25519Pk'},
    {'1': 'delegated_ml_dsa_pk', '3': 3, '4': 1, '5': 12, '10': 'delegatedMlDsaPk'},
    {'1': 'capabilities', '3': 4, '4': 1, '5': 13, '10': 'capabilities'},
    {'1': 'issued_at_ms', '3': 5, '4': 1, '5': 4, '10': 'issuedAtMs'},
    {'1': 'max_valid_until_ms', '3': 6, '4': 1, '5': 4, '10': 'maxValidUntilMs'},
    {'1': 'user_ed25519_sig', '3': 7, '4': 1, '5': 12, '10': 'userEd25519Sig'},
    {'1': 'user_ml_dsa_sig', '3': 8, '4': 1, '5': 12, '10': 'userMlDsaSig'},
  ],
};

/// Descriptor for `DeviceDelegationCertProto`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deviceDelegationCertProtoDescriptor = $convert.base64Decode(
    'ChlEZXZpY2VEZWxlZ2F0aW9uQ2VydFByb3RvEhsKCWRldmljZV9pZBgBIAEoDFIIZGV2aWNlSW'
    'QSMAoUZGVsZWdhdGVkX2VkMjU1MTlfcGsYAiABKAxSEmRlbGVnYXRlZEVkMjU1MTlQaxItChNk'
    'ZWxlZ2F0ZWRfbWxfZHNhX3BrGAMgASgMUhBkZWxlZ2F0ZWRNbERzYVBrEiIKDGNhcGFiaWxpdG'
    'llcxgEIAEoDVIMY2FwYWJpbGl0aWVzEiAKDGlzc3VlZF9hdF9tcxgFIAEoBFIKaXNzdWVkQXRN'
    'cxIrChJtYXhfdmFsaWRfdW50aWxfbXMYBiABKARSD21heFZhbGlkVW50aWxNcxIoChB1c2VyX2'
    'VkMjU1MTlfc2lnGAcgASgMUg51c2VyRWQyNTUxOVNpZxIlCg91c2VyX21sX2RzYV9zaWcYCCAB'
    'KAxSDHVzZXJNbERzYVNpZw==');

@$core.Deprecated('Use textMessageV3Descriptor instead')
const TextMessageV3$json = {
  '1': 'TextMessageV3',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    {'1': 'format_hint', '3': 2, '4': 1, '5': 9, '10': 'formatHint'},
    {'1': 'reply_to_message_id', '3': 3, '4': 1, '5': 12, '10': 'replyToMessageId'},
    {'1': 'reply_to_snippet', '3': 4, '4': 1, '5': 9, '10': 'replyToSnippet'},
    {'1': 'link_preview', '3': 5, '4': 1, '5': 11, '6': '.cleona.LinkPreview', '10': 'linkPreview'},
  ],
};

/// Descriptor for `TextMessageV3`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List textMessageV3Descriptor = $convert.base64Decode(
    'Cg1UZXh0TWVzc2FnZVYzEhIKBHRleHQYASABKAlSBHRleHQSHwoLZm9ybWF0X2hpbnQYAiABKA'
    'lSCmZvcm1hdEhpbnQSLQoTcmVwbHlfdG9fbWVzc2FnZV9pZBgDIAEoDFIQcmVwbHlUb01lc3Nh'
    'Z2VJZBIoChByZXBseV90b19zbmlwcGV0GAQgASgJUg5yZXBseVRvU25pcHBldBI2CgxsaW5rX3'
    'ByZXZpZXcYBSABKAsyEy5jbGVvbmEuTGlua1ByZXZpZXdSC2xpbmtQcmV2aWV3');

@$core.Deprecated('Use devicePairRequestV3Descriptor instead')
const DevicePairRequestV3$json = {
  '1': 'DevicePairRequestV3',
  '2': [
    {'1': 'device_ed25519_pk', '3': 1, '4': 1, '5': 12, '10': 'deviceEd25519Pk'},
    {'1': 'device_ml_dsa_pk', '3': 2, '4': 1, '5': 12, '10': 'deviceMlDsaPk'},
    {'1': 'pair_token_signature', '3': 3, '4': 1, '5': 12, '10': 'pairTokenSignature'},
    {'1': 'timestamp_ms', '3': 4, '4': 1, '5': 4, '10': 'timestampMs'},
  ],
};

/// Descriptor for `DevicePairRequestV3`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List devicePairRequestV3Descriptor = $convert.base64Decode(
    'ChNEZXZpY2VQYWlyUmVxdWVzdFYzEioKEWRldmljZV9lZDI1NTE5X3BrGAEgASgMUg9kZXZpY2'
    'VFZDI1NTE5UGsSJwoQZGV2aWNlX21sX2RzYV9waxgCIAEoDFINZGV2aWNlTWxEc2FQaxIwChRw'
    'YWlyX3Rva2VuX3NpZ25hdHVyZRgDIAEoDFIScGFpclRva2VuU2lnbmF0dXJlEiEKDHRpbWVzdG'
    'FtcF9tcxgEIAEoBFILdGltZXN0YW1wTXM=');

@$core.Deprecated('Use devicePairApproveV3Descriptor instead')
const DevicePairApproveV3$json = {
  '1': 'DevicePairApproveV3',
  '2': [
    {'1': 'delegated_ed25519_pk', '3': 1, '4': 1, '5': 12, '10': 'delegatedEd25519Pk'},
    {'1': 'delegated_ed25519_sk', '3': 2, '4': 1, '5': 12, '10': 'delegatedEd25519Sk'},
    {'1': 'delegated_ml_dsa_pk', '3': 3, '4': 1, '5': 12, '10': 'delegatedMlDsaPk'},
    {'1': 'delegated_ml_dsa_sk', '3': 4, '4': 1, '5': 12, '10': 'delegatedMlDsaSk'},
    {'1': 'user_x25519_sk', '3': 5, '4': 1, '5': 12, '10': 'userX25519Sk'},
    {'1': 'user_ml_kem_sk', '3': 6, '4': 1, '5': 12, '10': 'userMlKemSk'},
    {'1': 'delegation_cert', '3': 7, '4': 1, '5': 11, '6': '.cleona.DeviceDelegationCertProto', '10': 'delegationCert'},
    {'1': 'user_id', '3': 8, '4': 1, '5': 12, '10': 'userId'},
    {'1': 'display_name', '3': 9, '4': 1, '5': 9, '10': 'displayName'},
    {'1': 'profile_picture', '3': 10, '4': 1, '5': 12, '10': 'profilePicture'},
  ],
};

/// Descriptor for `DevicePairApproveV3`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List devicePairApproveV3Descriptor = $convert.base64Decode(
    'ChNEZXZpY2VQYWlyQXBwcm92ZVYzEjAKFGRlbGVnYXRlZF9lZDI1NTE5X3BrGAEgASgMUhJkZW'
    'xlZ2F0ZWRFZDI1NTE5UGsSMAoUZGVsZWdhdGVkX2VkMjU1MTlfc2sYAiABKAxSEmRlbGVnYXRl'
    'ZEVkMjU1MTlTaxItChNkZWxlZ2F0ZWRfbWxfZHNhX3BrGAMgASgMUhBkZWxlZ2F0ZWRNbERzYV'
    'BrEi0KE2RlbGVnYXRlZF9tbF9kc2Ffc2sYBCABKAxSEGRlbGVnYXRlZE1sRHNhU2sSJAoOdXNl'
    'cl94MjU1MTlfc2sYBSABKAxSDHVzZXJYMjU1MTlTaxIjCg51c2VyX21sX2tlbV9zaxgGIAEoDF'
    'ILdXNlck1sS2VtU2sSSgoPZGVsZWdhdGlvbl9jZXJ0GAcgASgLMiEuY2xlb25hLkRldmljZURl'
    'bGVnYXRpb25DZXJ0UHJvdG9SDmRlbGVnYXRpb25DZXJ0EhcKB3VzZXJfaWQYCCABKAxSBnVzZX'
    'JJZBIhCgxkaXNwbGF5X25hbWUYCSABKAlSC2Rpc3BsYXlOYW1lEicKD3Byb2ZpbGVfcGljdHVy'
    'ZRgKIAEoDFIOcHJvZmlsZVBpY3R1cmU=');

@$core.Deprecated('Use authorizedDeviceSigningKeysDescriptor instead')
const AuthorizedDeviceSigningKeys$json = {
  '1': 'AuthorizedDeviceSigningKeys',
  '2': [
    {'1': 'device_node_id', '3': 1, '4': 1, '5': 12, '10': 'deviceNodeId'},
    {'1': 'device_ed25519_pk', '3': 2, '4': 1, '5': 12, '10': 'deviceEd25519Pk'},
    {'1': 'device_ml_dsa_pk', '3': 3, '4': 1, '5': 12, '10': 'deviceMlDsaPk'},
    {'1': 'is_primary', '3': 4, '4': 1, '5': 8, '10': 'isPrimary'},
  ],
};

/// Descriptor for `AuthorizedDeviceSigningKeys`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List authorizedDeviceSigningKeysDescriptor = $convert.base64Decode(
    'ChtBdXRob3JpemVkRGV2aWNlU2lnbmluZ0tleXMSJAoOZGV2aWNlX25vZGVfaWQYASABKAxSDG'
    'RldmljZU5vZGVJZBIqChFkZXZpY2VfZWQyNTUxOV9waxgCIAEoDFIPZGV2aWNlRWQyNTUxOVBr'
    'EicKEGRldmljZV9tbF9kc2FfcGsYAyABKAxSDWRldmljZU1sRHNhUGsSHQoKaXNfcHJpbWFyeR'
    'gEIAEoCFIJaXNQcmltYXJ5');

@$core.Deprecated('Use rotationApprovalTokenDescriptor instead')
const RotationApprovalToken$json = {
  '1': 'RotationApprovalToken',
  '2': [
    {'1': 'device_node_id', '3': 1, '4': 1, '5': 12, '10': 'deviceNodeId'},
    {'1': 'rotation_hash', '3': 2, '4': 1, '5': 12, '10': 'rotationHash'},
    {'1': 'device_ed25519_sig', '3': 3, '4': 1, '5': 12, '10': 'deviceEd25519Sig'},
    {'1': 'device_ml_dsa_sig', '3': 4, '4': 1, '5': 12, '10': 'deviceMlDsaSig'},
  ],
};

/// Descriptor for `RotationApprovalToken`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rotationApprovalTokenDescriptor = $convert.base64Decode(
    'ChVSb3RhdGlvbkFwcHJvdmFsVG9rZW4SJAoOZGV2aWNlX25vZGVfaWQYASABKAxSDGRldmljZU'
    '5vZGVJZBIjCg1yb3RhdGlvbl9oYXNoGAIgASgMUgxyb3RhdGlvbkhhc2gSLAoSZGV2aWNlX2Vk'
    'MjU1MTlfc2lnGAMgASgMUhBkZXZpY2VFZDI1NTE5U2lnEikKEWRldmljZV9tbF9kc2Ffc2lnGA'
    'QgASgMUg5kZXZpY2VNbERzYVNpZw==');

@$core.Deprecated('Use rotationApprovalRequestPayloadDescriptor instead')
const RotationApprovalRequestPayload$json = {
  '1': 'RotationApprovalRequestPayload',
  '2': [
    {'1': 'rotation_hash', '3': 1, '4': 1, '5': 12, '10': 'rotationHash'},
    {'1': 'new_ed25519_pk', '3': 2, '4': 1, '5': 12, '10': 'newEd25519Pk'},
    {'1': 'new_ml_dsa_pk', '3': 3, '4': 1, '5': 12, '10': 'newMlDsaPk'},
    {'1': 'new_x25519_pk', '3': 4, '4': 1, '5': 12, '10': 'newX25519Pk'},
    {'1': 'new_ml_kem_pk', '3': 5, '4': 1, '5': 12, '10': 'newMlKemPk'},
    {'1': 'approval_kind', '3': 6, '4': 1, '5': 14, '6': '.cleona.ApprovalKindV3', '10': 'approvalKind'},
    {'1': 'new_device_node_ids', '3': 7, '4': 3, '5': 12, '10': 'newDeviceNodeIds'},
  ],
};

/// Descriptor for `RotationApprovalRequestPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rotationApprovalRequestPayloadDescriptor = $convert.base64Decode(
    'Ch5Sb3RhdGlvbkFwcHJvdmFsUmVxdWVzdFBheWxvYWQSIwoNcm90YXRpb25faGFzaBgBIAEoDF'
    'IMcm90YXRpb25IYXNoEiQKDm5ld19lZDI1NTE5X3BrGAIgASgMUgxuZXdFZDI1NTE5UGsSIQoN'
    'bmV3X21sX2RzYV9waxgDIAEoDFIKbmV3TWxEc2FQaxIiCg1uZXdfeDI1NTE5X3BrGAQgASgMUg'
    'tuZXdYMjU1MTlQaxIhCg1uZXdfbWxfa2VtX3BrGAUgASgMUgpuZXdNbEtlbVBrEjsKDWFwcHJv'
    'dmFsX2tpbmQYBiABKA4yFi5jbGVvbmEuQXBwcm92YWxLaW5kVjNSDGFwcHJvdmFsS2luZBItCh'
    'NuZXdfZGV2aWNlX25vZGVfaWRzGAcgAygMUhBuZXdEZXZpY2VOb2RlSWRz');

@$core.Deprecated('Use rotationApprovalResponsePayloadDescriptor instead')
const RotationApprovalResponsePayload$json = {
  '1': 'RotationApprovalResponsePayload',
  '2': [
    {'1': 'token', '3': 1, '4': 1, '5': 11, '6': '.cleona.RotationApprovalToken', '10': 'token'},
    {'1': 'rejected', '3': 2, '4': 1, '5': 8, '10': 'rejected'},
  ],
};

/// Descriptor for `RotationApprovalResponsePayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rotationApprovalResponsePayloadDescriptor = $convert.base64Decode(
    'Ch9Sb3RhdGlvbkFwcHJvdmFsUmVzcG9uc2VQYXlsb2FkEjMKBXRva2VuGAEgASgLMh0uY2xlb2'
    '5hLlJvdGF0aW9uQXBwcm92YWxUb2tlblIFdG9rZW4SGgoIcmVqZWN0ZWQYAiABKAhSCHJlamVj'
    'dGVk');

@$core.Deprecated('Use rotationRejectionAlertPayloadDescriptor instead')
const RotationRejectionAlertPayload$json = {
  '1': 'RotationRejectionAlertPayload',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 12, '10': 'userId'},
    {'1': 'device_node_id', '3': 2, '4': 1, '5': 12, '10': 'deviceNodeId'},
    {'1': 'rotation_hash', '3': 3, '4': 1, '5': 12, '10': 'rotationHash'},
    {'1': 'device_ed25519_sig', '3': 4, '4': 1, '5': 12, '10': 'deviceEd25519Sig'},
    {'1': 'device_ml_dsa_sig', '3': 5, '4': 1, '5': 12, '10': 'deviceMlDsaSig'},
  ],
};

/// Descriptor for `RotationRejectionAlertPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rotationRejectionAlertPayloadDescriptor = $convert.base64Decode(
    'Ch1Sb3RhdGlvblJlamVjdGlvbkFsZXJ0UGF5bG9hZBIXCgd1c2VyX2lkGAEgASgMUgZ1c2VySW'
    'QSJAoOZGV2aWNlX25vZGVfaWQYAiABKAxSDGRldmljZU5vZGVJZBIjCg1yb3RhdGlvbl9oYXNo'
    'GAMgASgMUgxyb3RhdGlvbkhhc2gSLAoSZGV2aWNlX2VkMjU1MTlfc2lnGAQgASgMUhBkZXZpY2'
    'VFZDI1NTE5U2lnEikKEWRldmljZV9tbF9kc2Ffc2lnGAUgASgMUg5kZXZpY2VNbERzYVNpZw==');

@$core.Deprecated('Use deviceSetChangeProofDescriptor instead')
const DeviceSetChangeProof$json = {
  '1': 'DeviceSetChangeProof',
  '2': [
    {'1': 'previous_device_count', '3': 1, '4': 1, '5': 13, '10': 'previousDeviceCount'},
    {'1': 'change_hash', '3': 2, '4': 1, '5': 12, '10': 'changeHash'},
    {'1': 'approvals', '3': 3, '4': 3, '5': 11, '6': '.cleona.RotationApprovalToken', '10': 'approvals'},
  ],
};

/// Descriptor for `DeviceSetChangeProof`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deviceSetChangeProofDescriptor = $convert.base64Decode(
    'ChREZXZpY2VTZXRDaGFuZ2VQcm9vZhIyChVwcmV2aW91c19kZXZpY2VfY291bnQYASABKA1SE3'
    'ByZXZpb3VzRGV2aWNlQ291bnQSHwoLY2hhbmdlX2hhc2gYAiABKAxSCmNoYW5nZUhhc2gSOwoJ'
    'YXBwcm92YWxzGAMgAygLMh0uY2xlb25hLlJvdGF0aW9uQXBwcm92YWxUb2tlblIJYXBwcm92YW'
    'xz');

@$core.Deprecated('Use deviceSetAnnounceV3Descriptor instead')
const DeviceSetAnnounceV3$json = {
  '1': 'DeviceSetAnnounceV3',
  '2': [
    {'1': 'seq', '3': 1, '4': 1, '5': 13, '10': 'seq'},
    {'1': 'issued_at_ms', '3': 2, '4': 1, '5': 4, '10': 'issuedAtMs'},
    {'1': 'previous_device_count', '3': 3, '4': 1, '5': 13, '10': 'previousDeviceCount'},
    {'1': 'device_sig_keys', '3': 4, '4': 3, '5': 11, '6': '.cleona.AuthorizedDeviceSigningKeys', '10': 'deviceSigKeys'},
    {'1': 'change_hash', '3': 5, '4': 1, '5': 12, '10': 'changeHash'},
    {'1': 'approvals', '3': 6, '4': 3, '5': 11, '6': '.cleona.RotationApprovalToken', '10': 'approvals'},
    {'1': 'user_signature_ed25519', '3': 7, '4': 1, '5': 12, '10': 'userSignatureEd25519'},
  ],
};

/// Descriptor for `DeviceSetAnnounceV3`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deviceSetAnnounceV3Descriptor = $convert.base64Decode(
    'ChNEZXZpY2VTZXRBbm5vdW5jZVYzEhAKA3NlcRgBIAEoDVIDc2VxEiAKDGlzc3VlZF9hdF9tcx'
    'gCIAEoBFIKaXNzdWVkQXRNcxIyChVwcmV2aW91c19kZXZpY2VfY291bnQYAyABKA1SE3ByZXZp'
    'b3VzRGV2aWNlQ291bnQSSwoPZGV2aWNlX3NpZ19rZXlzGAQgAygLMiMuY2xlb25hLkF1dGhvcm'
    'l6ZWREZXZpY2VTaWduaW5nS2V5c1INZGV2aWNlU2lnS2V5cxIfCgtjaGFuZ2VfaGFzaBgFIAEo'
    'DFIKY2hhbmdlSGFzaBI7CglhcHByb3ZhbHMYBiADKAsyHS5jbGVvbmEuUm90YXRpb25BcHByb3'
    'ZhbFRva2VuUglhcHByb3ZhbHMSNAoWdXNlcl9zaWduYXR1cmVfZWQyNTUxORgHIAEoDFIUdXNl'
    'clNpZ25hdHVyZUVkMjU1MTk=');

@$core.Deprecated('Use sysChanRotationLinkDescriptor instead')
const SysChanRotationLink$json = {
  '1': 'SysChanRotationLink',
  '2': [
    {'1': 'old_ed25519_pk', '3': 1, '4': 1, '5': 12, '10': 'oldEd25519Pk'},
    {'1': 'old_ml_dsa_pk', '3': 2, '4': 1, '5': 12, '10': 'oldMlDsaPk'},
    {'1': 'new_ed25519_pk', '3': 3, '4': 1, '5': 12, '10': 'newEd25519Pk'},
    {'1': 'new_ml_dsa_pk', '3': 4, '4': 1, '5': 12, '10': 'newMlDsaPk'},
    {'1': 'sig_ed25519', '3': 5, '4': 1, '5': 12, '10': 'sigEd25519'},
    {'1': 'sig_ml_dsa', '3': 6, '4': 1, '5': 12, '10': 'sigMlDsa'},
  ],
};

/// Descriptor for `SysChanRotationLink`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sysChanRotationLinkDescriptor = $convert.base64Decode(
    'ChNTeXNDaGFuUm90YXRpb25MaW5rEiQKDm9sZF9lZDI1NTE5X3BrGAEgASgMUgxvbGRFZDI1NT'
    'E5UGsSIQoNb2xkX21sX2RzYV9waxgCIAEoDFIKb2xkTWxEc2FQaxIkCg5uZXdfZWQyNTUxOV9w'
    'axgDIAEoDFIMbmV3RWQyNTUxOVBrEiEKDW5ld19tbF9kc2FfcGsYBCABKAxSCm5ld01sRHNhUG'
    'sSHwoLc2lnX2VkMjU1MTkYBSABKAxSCnNpZ0VkMjU1MTkSHAoKc2lnX21sX2RzYRgGIAEoDFII'
    'c2lnTWxEc2E=');

@$core.Deprecated('Use systemChannelRecordDescriptor instead')
const SystemChannelRecord$json = {
  '1': 'SystemChannelRecord',
  '2': [
    {'1': 'channel_id', '3': 1, '4': 1, '5': 12, '10': 'channelId'},
    {'1': 'record_id', '3': 2, '4': 1, '5': 12, '10': 'recordId'},
    {'1': 'kind', '3': 3, '4': 1, '5': 13, '10': 'kind'},
    {'1': 'author_user_id', '3': 4, '4': 1, '5': 12, '10': 'authorUserId'},
    {'1': 'author_ed25519_pk', '3': 5, '4': 1, '5': 12, '10': 'authorEd25519Pk'},
    {'1': 'author_ml_dsa_pk', '3': 6, '4': 1, '5': 12, '10': 'authorMlDsaPk'},
    {'1': 'timestamp_ms', '3': 7, '4': 1, '5': 4, '10': 'timestampMs'},
    {'1': 'text', '3': 8, '4': 1, '5': 9, '10': 'text'},
    {'1': 'target_record_id', '3': 9, '4': 1, '5': 12, '10': 'targetRecordId'},
    {'1': 'vote_option', '3': 10, '4': 1, '5': 13, '10': 'voteOption'},
    {'1': 'sig_ed25519', '3': 11, '4': 1, '5': 12, '10': 'sigEd25519'},
    {'1': 'sig_ml_dsa', '3': 12, '4': 1, '5': 12, '10': 'sigMlDsa'},
    {'1': 'rotation_chain', '3': 13, '4': 3, '5': 11, '6': '.cleona.SysChanRotationLink', '10': 'rotationChain'},
  ],
};

/// Descriptor for `SystemChannelRecord`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List systemChannelRecordDescriptor = $convert.base64Decode(
    'ChNTeXN0ZW1DaGFubmVsUmVjb3JkEh0KCmNoYW5uZWxfaWQYASABKAxSCWNoYW5uZWxJZBIbCg'
    'lyZWNvcmRfaWQYAiABKAxSCHJlY29yZElkEhIKBGtpbmQYAyABKA1SBGtpbmQSJAoOYXV0aG9y'
    'X3VzZXJfaWQYBCABKAxSDGF1dGhvclVzZXJJZBIqChFhdXRob3JfZWQyNTUxOV9waxgFIAEoDF'
    'IPYXV0aG9yRWQyNTUxOVBrEicKEGF1dGhvcl9tbF9kc2FfcGsYBiABKAxSDWF1dGhvck1sRHNh'
    'UGsSIQoMdGltZXN0YW1wX21zGAcgASgEUgt0aW1lc3RhbXBNcxISCgR0ZXh0GAggASgJUgR0ZX'
    'h0EigKEHRhcmdldF9yZWNvcmRfaWQYCSABKAxSDnRhcmdldFJlY29yZElkEh8KC3ZvdGVfb3B0'
    'aW9uGAogASgNUgp2b3RlT3B0aW9uEh8KC3NpZ19lZDI1NTE5GAsgASgMUgpzaWdFZDI1NTE5Eh'
    'wKCnNpZ19tbF9kc2EYDCABKAxSCHNpZ01sRHNhEkIKDnJvdGF0aW9uX2NoYWluGA0gAygLMhsu'
    'Y2xlb25hLlN5c0NoYW5Sb3RhdGlvbkxpbmtSDXJvdGF0aW9uQ2hhaW4=');

@$core.Deprecated('Use sysChanDigestDescriptor instead')
const SysChanDigest$json = {
  '1': 'SysChanDigest',
  '2': [
    {'1': 'channel_id', '3': 1, '4': 1, '5': 12, '10': 'channelId'},
    {'1': 'record_count', '3': 2, '4': 1, '5': 13, '10': 'recordCount'},
    {'1': 'set_hash', '3': 3, '4': 1, '5': 12, '10': 'setHash'},
  ],
};

/// Descriptor for `SysChanDigest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sysChanDigestDescriptor = $convert.base64Decode(
    'Cg1TeXNDaGFuRGlnZXN0Eh0KCmNoYW5uZWxfaWQYASABKAxSCWNoYW5uZWxJZBIhCgxyZWNvcm'
    'RfY291bnQYAiABKA1SC3JlY29yZENvdW50EhkKCHNldF9oYXNoGAMgASgMUgdzZXRIYXNo');

@$core.Deprecated('Use sysChanSummaryDescriptor instead')
const SysChanSummary$json = {
  '1': 'SysChanSummary',
  '2': [
    {'1': 'channel_id', '3': 1, '4': 1, '5': 12, '10': 'channelId'},
    {'1': 'fingerprints', '3': 2, '4': 3, '5': 12, '10': 'fingerprints'},
  ],
};

/// Descriptor for `SysChanSummary`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sysChanSummaryDescriptor = $convert.base64Decode(
    'Cg5TeXNDaGFuU3VtbWFyeRIdCgpjaGFubmVsX2lkGAEgASgMUgljaGFubmVsSWQSIgoMZmluZ2'
    'VycHJpbnRzGAIgAygMUgxmaW5nZXJwcmludHM=');

@$core.Deprecated('Use sysChanWantDescriptor instead')
const SysChanWant$json = {
  '1': 'SysChanWant',
  '2': [
    {'1': 'channel_id', '3': 1, '4': 1, '5': 12, '10': 'channelId'},
    {'1': 'fingerprints', '3': 2, '4': 3, '5': 12, '10': 'fingerprints'},
  ],
};

/// Descriptor for `SysChanWant`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sysChanWantDescriptor = $convert.base64Decode(
    'CgtTeXNDaGFuV2FudBIdCgpjaGFubmVsX2lkGAEgASgMUgljaGFubmVsSWQSIgoMZmluZ2VycH'
    'JpbnRzGAIgAygMUgxmaW5nZXJwcmludHM=');

@$core.Deprecated('Use sysChanPushDescriptor instead')
const SysChanPush$json = {
  '1': 'SysChanPush',
  '2': [
    {'1': 'channel_id', '3': 1, '4': 1, '5': 12, '10': 'channelId'},
    {'1': 'records', '3': 2, '4': 3, '5': 12, '10': 'records'},
    {'1': 'ttl', '3': 3, '4': 1, '5': 13, '10': 'ttl'},
  ],
};

/// Descriptor for `SysChanPush`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sysChanPushDescriptor = $convert.base64Decode(
    'CgtTeXNDaGFuUHVzaBIdCgpjaGFubmVsX2lkGAEgASgMUgljaGFubmVsSWQSGAoHcmVjb3Jkcx'
    'gCIAMoDFIHcmVjb3JkcxIQCgN0dGwYAyABKA1SA3R0bA==');


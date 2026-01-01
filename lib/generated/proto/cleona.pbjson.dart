//
//  Generated code. Do not modify.
//  source: cleona.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use messageTypeDescriptor instead')
const MessageType$json = {
  '1': 'MessageType',
  '2': [
    {'1': 'TEXT', '2': 0},
    {'1': 'IMAGE', '2': 1},
    {'1': 'VIDEO', '2': 2},
    {'1': 'GIF', '2': 3},
    {'1': 'EMOJI_REACTION', '2': 4},
    {'1': 'MEDIA_ANNOUNCEMENT', '2': 5},
    {'1': 'MEDIA_ACCEPT', '2': 6},
    {'1': 'MEDIA_REJECT', '2': 7},
    {'1': 'MESSAGE_EDIT', '2': 8},
    {'1': 'MESSAGE_EXPIRE_CONFIG', '2': 9},
    {'1': 'RESTORE_BROADCAST', '2': 13},
    {'1': 'RESTORE_RESPONSE', '2': 14},
    {'1': 'TYPING_INDICATOR', '2': 15},
    {'1': 'READ_RECEIPT', '2': 16},
    {'1': 'GROUP_CREATE', '2': 17},
    {'1': 'GROUP_INVITE', '2': 18},
    {'1': 'GROUP_LEAVE', '2': 19},
    {'1': 'GROUP_KEY_UPDATE', '2': 20},
    {'1': 'MESSAGE_DELETE', '2': 21},
    {'1': 'VOICE_MESSAGE', '2': 22},
    {'1': 'FILE', '2': 23},
    {'1': 'CALL_INVITE', '2': 30},
    {'1': 'CALL_ANSWER', '2': 31},
    {'1': 'CALL_REJECT', '2': 32},
    {'1': 'CALL_HANGUP', '2': 33},
    {'1': 'ICE_CANDIDATE', '2': 34},
    {'1': 'CALL_REJOIN', '2': 35},
    {'1': 'CALL_AUDIO', '2': 36},
    {'1': 'PEER_LIST_SUMMARY', '2': 50},
    {'1': 'PEER_LIST_WANT', '2': 51},
    {'1': 'PEER_LIST_PUSH', '2': 52},
    {'1': 'CONTACT_REQUEST', '2': 62},
    {'1': 'CONTACT_REQUEST_RESPONSE', '2': 63},
    {'1': 'CHANNEL_CREATE', '2': 70},
    {'1': 'CHANNEL_POST', '2': 71},
    {'1': 'CHANNEL_INVITE', '2': 72},
    {'1': 'CHANNEL_ROLE_UPDATE', '2': 73},
    {'1': 'CHANNEL_LEAVE', '2': 74},
    {'1': 'CHANNEL_JOIN_REQUEST', '2': 75},
    {'1': 'CHANNEL_REPORT', '2': 76},
    {'1': 'CHANNEL_REPORT_RESPONSE', '2': 77},
    {'1': 'JURY_REQUEST', '2': 78},
    {'1': 'JURY_VOTE_MSG', '2': 79},
    {'1': 'JURY_RESULT', '2': 88},
    {'1': 'CHANNEL_INDEX_EXCHANGE', '2': 89},
    {'1': 'DHT_PING', '2': 80},
    {'1': 'DHT_PONG', '2': 81},
    {'1': 'DHT_FIND_NODE', '2': 82},
    {'1': 'DHT_FIND_NODE_RESPONSE', '2': 83},
    {'1': 'DHT_STORE', '2': 84},
    {'1': 'DHT_STORE_RESPONSE', '2': 85},
    {'1': 'DHT_FIND_VALUE', '2': 86},
    {'1': 'DHT_FIND_VALUE_RESPONSE', '2': 87},
    {'1': 'FRAGMENT_STORE', '2': 90},
    {'1': 'FRAGMENT_STORE_ACK', '2': 91},
    {'1': 'FRAGMENT_RETRIEVE', '2': 92},
    {'1': 'FRAGMENT_DELETE', '2': 93},
    {'1': 'DELIVERY_RECEIPT', '2': 94},
    {'1': 'CHAT_CONFIG_UPDATE', '2': 100},
    {'1': 'CHAT_CONFIG_RESPONSE', '2': 101},
    {'1': 'IDENTITY_DELETED', '2': 102},
    {'1': 'PROFILE_UPDATE', '2': 103},
    {'1': 'GUARDIAN_SHARE_STORE', '2': 104},
    {'1': 'GUARDIAN_RESTORE_REQUEST', '2': 105},
    {'1': 'GUARDIAN_RESTORE_RESPONSE', '2': 106},
    {'1': 'RELAY_FORWARD', '2': 110},
    {'1': 'RELAY_ACK', '2': 111},
    {'1': 'REACHABILITY_QUERY', '2': 112},
    {'1': 'REACHABILITY_RESPONSE', '2': 113},
    {'1': 'PEER_STORE', '2': 114},
    {'1': 'PEER_STORE_ACK', '2': 115},
    {'1': 'PEER_RETRIEVE', '2': 116},
    {'1': 'PEER_RETRIEVE_RESPONSE', '2': 117},
    {'1': 'ROUTE_UPDATE', '2': 120},
    {'1': 'HOLE_PUNCH_REQUEST', '2': 121},
    {'1': 'HOLE_PUNCH_NOTIFY', '2': 122},
    {'1': 'HOLE_PUNCH_PING', '2': 123},
    {'1': 'HOLE_PUNCH_PONG', '2': 124},
    {'1': 'MEDIA_CHUNK', '2': 125},
    {'1': 'TWIN_ANNOUNCE', '2': 130},
    {'1': 'TWIN_SYNC', '2': 131},
    {'1': 'DEVICE_REVOKED', '2': 132},
    {'1': 'KEY_ROTATION_BROADCAST', '2': 133},
    {'1': 'KEY_ROTATION_ACK', '2': 134},
    {'1': 'CALENDAR_INVITE', '2': 140},
    {'1': 'CALENDAR_RSVP', '2': 141},
    {'1': 'CALENDAR_UPDATE', '2': 142},
    {'1': 'CALENDAR_DELETE', '2': 143},
    {'1': 'FREE_BUSY_REQUEST', '2': 144},
    {'1': 'FREE_BUSY_RESPONSE', '2': 145},
    {'1': 'POLL_CREATE', '2': 146},
    {'1': 'POLL_VOTE', '2': 147},
    {'1': 'POLL_UPDATE', '2': 148},
    {'1': 'POLL_SNAPSHOT', '2': 149},
    {'1': 'POLL_VOTE_ANONYMOUS', '2': 150},
    {'1': 'POLL_VOTE_REVOKE', '2': 151},
    {'1': 'IDENTITY_AUTH_PUBLISH', '2': 152},
    {'1': 'IDENTITY_AUTH_RETRIEVE', '2': 153},
    {'1': 'IDENTITY_AUTH_RESPONSE', '2': 154},
    {'1': 'IDENTITY_LIVE_PUBLISH', '2': 155},
    {'1': 'IDENTITY_LIVE_RETRIEVE', '2': 156},
    {'1': 'IDENTITY_LIVE_RESPONSE', '2': 157},
    {'1': 'CALL_RTT_PING', '2': 37},
    {'1': 'CALL_RTT_PONG', '2': 38},
    {'1': 'CALL_TREE_UPDATE', '2': 39},
    {'1': 'CALL_VIDEO', '2': 40},
    {'1': 'CALL_KEYFRAME_REQUEST', '2': 41},
    {'1': 'CALL_GROUP_AUDIO', '2': 42},
    {'1': 'CALL_GROUP_LEAVE', '2': 43},
    {'1': 'CALL_GROUP_KEY_ROTATE', '2': 44},
    {'1': 'CALL_GROUP_VIDEO', '2': 45},
  ],
  '4': [
    {'1': 10, '2': 10},
    {'1': 11, '2': 11},
    {'1': 12, '2': 12},
    {'1': 60, '2': 60},
    {'1': 61, '2': 61},
  ],
};

/// Descriptor for `MessageType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List messageTypeDescriptor = $convert.base64Decode(
    'CgtNZXNzYWdlVHlwZRIICgRURVhUEAASCQoFSU1BR0UQARIJCgVWSURFTxACEgcKA0dJRhADEh'
    'IKDkVNT0pJX1JFQUNUSU9OEAQSFgoSTUVESUFfQU5OT1VOQ0VNRU5UEAUSEAoMTUVESUFfQUND'
    'RVBUEAYSEAoMTUVESUFfUkVKRUNUEAcSEAoMTUVTU0FHRV9FRElUEAgSGQoVTUVTU0FHRV9FWF'
    'BJUkVfQ09ORklHEAkSFQoRUkVTVE9SRV9CUk9BRENBU1QQDRIUChBSRVNUT1JFX1JFU1BPTlNF'
    'EA4SFAoQVFlQSU5HX0lORElDQVRPUhAPEhAKDFJFQURfUkVDRUlQVBAQEhAKDEdST1VQX0NSRU'
    'FURRAREhAKDEdST1VQX0lOVklURRASEg8KC0dST1VQX0xFQVZFEBMSFAoQR1JPVVBfS0VZX1VQ'
    'REFURRAUEhIKDk1FU1NBR0VfREVMRVRFEBUSEQoNVk9JQ0VfTUVTU0FHRRAWEggKBEZJTEUQFx'
    'IPCgtDQUxMX0lOVklURRAeEg8KC0NBTExfQU5TV0VSEB8SDwoLQ0FMTF9SRUpFQ1QQIBIPCgtD'
    'QUxMX0hBTkdVUBAhEhEKDUlDRV9DQU5ESURBVEUQIhIPCgtDQUxMX1JFSk9JThAjEg4KCkNBTE'
    'xfQVVESU8QJBIVChFQRUVSX0xJU1RfU1VNTUFSWRAyEhIKDlBFRVJfTElTVF9XQU5UEDMSEgoO'
    'UEVFUl9MSVNUX1BVU0gQNBITCg9DT05UQUNUX1JFUVVFU1QQPhIcChhDT05UQUNUX1JFUVVFU1'
    'RfUkVTUE9OU0UQPxISCg5DSEFOTkVMX0NSRUFURRBGEhAKDENIQU5ORUxfUE9TVBBHEhIKDkNI'
    'QU5ORUxfSU5WSVRFEEgSFwoTQ0hBTk5FTF9ST0xFX1VQREFURRBJEhEKDUNIQU5ORUxfTEVBVk'
    'UQShIYChRDSEFOTkVMX0pPSU5fUkVRVUVTVBBLEhIKDkNIQU5ORUxfUkVQT1JUEEwSGwoXQ0hB'
    'Tk5FTF9SRVBPUlRfUkVTUE9OU0UQTRIQCgxKVVJZX1JFUVVFU1QQThIRCg1KVVJZX1ZPVEVfTV'
    'NHEE8SDwoLSlVSWV9SRVNVTFQQWBIaChZDSEFOTkVMX0lOREVYX0VYQ0hBTkdFEFkSDAoIREhU'
    'X1BJTkcQUBIMCghESFRfUE9ORxBREhEKDURIVF9GSU5EX05PREUQUhIaChZESFRfRklORF9OT0'
    'RFX1JFU1BPTlNFEFMSDQoJREhUX1NUT1JFEFQSFgoSREhUX1NUT1JFX1JFU1BPTlNFEFUSEgoO'
    'REhUX0ZJTkRfVkFMVUUQVhIbChdESFRfRklORF9WQUxVRV9SRVNQT05TRRBXEhIKDkZSQUdNRU'
    '5UX1NUT1JFEFoSFgoSRlJBR01FTlRfU1RPUkVfQUNLEFsSFQoRRlJBR01FTlRfUkVUUklFVkUQ'
    'XBITCg9GUkFHTUVOVF9ERUxFVEUQXRIUChBERUxJVkVSWV9SRUNFSVBUEF4SFgoSQ0hBVF9DT0'
    '5GSUdfVVBEQVRFEGQSGAoUQ0hBVF9DT05GSUdfUkVTUE9OU0UQZRIUChBJREVOVElUWV9ERUxF'
    'VEVEEGYSEgoOUFJPRklMRV9VUERBVEUQZxIYChRHVUFSRElBTl9TSEFSRV9TVE9SRRBoEhwKGE'
    'dVQVJESUFOX1JFU1RPUkVfUkVRVUVTVBBpEh0KGUdVQVJESUFOX1JFU1RPUkVfUkVTUE9OU0UQ'
    'ahIRCg1SRUxBWV9GT1JXQVJEEG4SDQoJUkVMQVlfQUNLEG8SFgoSUkVBQ0hBQklMSVRZX1FVRV'
    'JZEHASGQoVUkVBQ0hBQklMSVRZX1JFU1BPTlNFEHESDgoKUEVFUl9TVE9SRRByEhIKDlBFRVJf'
    'U1RPUkVfQUNLEHMSEQoNUEVFUl9SRVRSSUVWRRB0EhoKFlBFRVJfUkVUUklFVkVfUkVTUE9OU0'
    'UQdRIQCgxST1VURV9VUERBVEUQeBIWChJIT0xFX1BVTkNIX1JFUVVFU1QQeRIVChFIT0xFX1BV'
    'TkNIX05PVElGWRB6EhMKD0hPTEVfUFVOQ0hfUElORxB7EhMKD0hPTEVfUFVOQ0hfUE9ORxB8Eg'
    '8KC01FRElBX0NIVU5LEH0SEgoNVFdJTl9BTk5PVU5DRRCCARIOCglUV0lOX1NZTkMQgwESEwoO'
    'REVWSUNFX1JFVk9LRUQQhAESGwoWS0VZX1JPVEFUSU9OX0JST0FEQ0FTVBCFARIVChBLRVlfUk'
    '9UQVRJT05fQUNLEIYBEhQKD0NBTEVOREFSX0lOVklURRCMARISCg1DQUxFTkRBUl9SU1ZQEI0B'
    'EhQKD0NBTEVOREFSX1VQREFURRCOARIUCg9DQUxFTkRBUl9ERUxFVEUQjwESFgoRRlJFRV9CVV'
    'NZX1JFUVVFU1QQkAESFwoSRlJFRV9CVVNZX1JFU1BPTlNFEJEBEhAKC1BPTExfQ1JFQVRFEJIB'
    'Eg4KCVBPTExfVk9URRCTARIQCgtQT0xMX1VQREFURRCUARISCg1QT0xMX1NOQVBTSE9UEJUBEh'
    'gKE1BPTExfVk9URV9BTk9OWU1PVVMQlgESFQoQUE9MTF9WT1RFX1JFVk9LRRCXARIaChVJREVO'
    'VElUWV9BVVRIX1BVQkxJU0gQmAESGwoWSURFTlRJVFlfQVVUSF9SRVRSSUVWRRCZARIbChZJRE'
    'VOVElUWV9BVVRIX1JFU1BPTlNFEJoBEhoKFUlERU5USVRZX0xJVkVfUFVCTElTSBCbARIbChZJ'
    'REVOVElUWV9MSVZFX1JFVFJJRVZFEJwBEhsKFklERU5USVRZX0xJVkVfUkVTUE9OU0UQnQESEQ'
    'oNQ0FMTF9SVFRfUElORxAlEhEKDUNBTExfUlRUX1BPTkcQJhIUChBDQUxMX1RSRUVfVVBEQVRF'
    'ECcSDgoKQ0FMTF9WSURFTxAoEhkKFUNBTExfS0VZRlJBTUVfUkVRVUVTVBApEhQKEENBTExfR1'
    'JPVVBfQVVESU8QKhIUChBDQUxMX0dST1VQX0xFQVZFECsSGQoVQ0FMTF9HUk9VUF9LRVlfUk9U'
    'QVRFECwSFAoQQ0FMTF9HUk9VUF9WSURFTxAtIgQIChAKIgQICxALIgQIDBAMIgQIPBA8IgQIPR'
    'A9');

@$core.Deprecated('Use compressionTypeDescriptor instead')
const CompressionType$json = {
  '1': 'CompressionType',
  '2': [
    {'1': 'NONE', '2': 0},
    {'1': 'ZSTD', '2': 1},
  ],
};

/// Descriptor for `CompressionType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List compressionTypeDescriptor = $convert.base64Decode(
    'Cg9Db21wcmVzc2lvblR5cGUSCAoETk9ORRAAEggKBFpTVEQQAQ==');

@$core.Deprecated('Use addressTypeDescriptor instead')
const AddressType$json = {
  '1': 'AddressType',
  '2': [
    {'1': 'IPV4_PUBLIC', '2': 0},
    {'1': 'IPV4_PRIVATE', '2': 1},
    {'1': 'IPV6_GLOBAL', '2': 2},
  ],
};

/// Descriptor for `AddressType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List addressTypeDescriptor = $convert.base64Decode(
    'CgtBZGRyZXNzVHlwZRIPCgtJUFY0X1BVQkxJQxAAEhAKDElQVjRfUFJJVkFURRABEg8KC0lQVj'
    'ZfR0xPQkFMEAI=');

@$core.Deprecated('Use natTypeDescriptor instead')
const NatType$json = {
  '1': 'NatType',
  '2': [
    {'1': 'NAT_UNKNOWN', '2': 0},
    {'1': 'NAT_PUBLIC', '2': 1},
    {'1': 'NAT_FULL_CONE', '2': 2},
    {'1': 'NAT_SYMMETRIC', '2': 3},
  ],
};

/// Descriptor for `NatType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List natTypeDescriptor = $convert.base64Decode(
    'CgdOYXRUeXBlEg8KC05BVF9VTktOT1dOEAASDgoKTkFUX1BVQkxJQxABEhEKDU5BVF9GVUxMX0'
    'NPTkUQAhIRCg1OQVRfU1lNTUVUUklDEAM=');

@$core.Deprecated('Use connectionTypeProtoDescriptor instead')
const ConnectionTypeProto$json = {
  '1': 'ConnectionTypeProto',
  '2': [
    {'1': 'CT_LAN_SAME_SUBNET', '2': 0},
    {'1': 'CT_LAN_OTHER_SUBNET', '2': 1},
    {'1': 'CT_WIFI_DIRECT', '2': 2},
    {'1': 'CT_PUBLIC_UDP', '2': 3},
    {'1': 'CT_HOLE_PUNCH', '2': 4},
    {'1': 'CT_RELAY', '2': 5},
    {'1': 'CT_MOBILE', '2': 6},
    {'1': 'CT_MOBILE_RELAY', '2': 7},
  ],
};

/// Descriptor for `ConnectionTypeProto`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List connectionTypeProtoDescriptor = $convert.base64Decode(
    'ChNDb25uZWN0aW9uVHlwZVByb3RvEhYKEkNUX0xBTl9TQU1FX1NVQk5FVBAAEhcKE0NUX0xBTl'
    '9PVEhFUl9TVUJORVQQARISCg5DVF9XSUZJX0RJUkVDVBACEhEKDUNUX1BVQkxJQ19VRFAQAxIR'
    'Cg1DVF9IT0xFX1BVTkNIEAQSDAoIQ1RfUkVMQVkQBRINCglDVF9NT0JJTEUQBhITCg9DVF9NT0'
    'JJTEVfUkVMQVkQBw==');

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
  ],
};

/// Descriptor for `TwinSyncType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List twinSyncTypeDescriptor = $convert.base64Decode(
    'CgxUd2luU3luY1R5cGUSEQoNQ09OVEFDVF9BRERFRBAAEhMKD0NPTlRBQ1RfREVMRVRFRBABEh'
    'AKDE1FU1NBR0VfU0VOVBACEhIKDk1FU1NBR0VfRURJVEVEEAMSEwoPTUVTU0FHRV9ERUxFVEVE'
    'EAQSFQoRVFdJTl9SRUFEX1JFQ0VJUFQQBRIRCg1HUk9VUF9DUkVBVEVEEAYSEwoPUFJPRklMRV'
    '9DSEFOR0VEEAcSFAoQU0VUVElOR1NfQ0hBTkdFRBAIEhMKD0RFVklDRV9BTk5PVU5DRRAJEhIK'
    'DkRFVklDRV9SRU5BTUVEEAoSFwoTVFdJTl9ERVZJQ0VfUkVWT0tFRBAL');

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

@$core.Deprecated('Use messageEnvelopeDescriptor instead')
const MessageEnvelope$json = {
  '1': 'MessageEnvelope',
  '2': [
    {'1': 'version', '3': 1, '4': 1, '5': 13, '10': 'version'},
    {'1': 'sender_id', '3': 2, '4': 1, '5': 12, '10': 'senderId'},
    {'1': 'recipient_id', '3': 3, '4': 1, '5': 12, '10': 'recipientId'},
    {'1': 'timestamp', '3': 4, '4': 1, '5': 4, '10': 'timestamp'},
    {'1': 'message_type', '3': 5, '4': 1, '5': 14, '6': '.cleona.MessageType', '10': 'messageType'},
    {'1': 'encrypted_payload', '3': 6, '4': 1, '5': 12, '10': 'encryptedPayload'},
    {'1': 'signature_ed25519', '3': 7, '4': 1, '5': 12, '10': 'signatureEd25519'},
    {'1': 'signature_ml_dsa', '3': 8, '4': 1, '5': 12, '10': 'signatureMlDsa'},
    {'1': 'content_metadata', '3': 9, '4': 1, '5': 11, '6': '.cleona.ContentMetadata', '10': 'contentMetadata'},
    {'1': 'edit_metadata', '3': 10, '4': 1, '5': 11, '6': '.cleona.EditMetadata', '10': 'editMetadata'},
    {'1': 'expiry_metadata', '3': 11, '4': 1, '5': 11, '6': '.cleona.ExpiryMetadata', '10': 'expiryMetadata'},
    {'1': 'erasure_metadata', '3': 12, '4': 1, '5': 11, '6': '.cleona.ErasureCodingMetadata', '10': 'erasureMetadata'},
    {'1': 'pow', '3': 13, '4': 1, '5': 11, '6': '.cleona.ProofOfWork', '10': 'pow'},
    {'1': 'kem_header', '3': 14, '4': 1, '5': 11, '6': '.cleona.PerMessageKem', '10': 'kemHeader'},
    {'1': 'compression', '3': 16, '4': 1, '5': 14, '6': '.cleona.CompressionType', '10': 'compression'},
    {'1': 'network_tag', '3': 17, '4': 1, '5': 9, '10': 'networkTag'},
    {'1': 'message_id', '3': 18, '4': 1, '5': 12, '10': 'messageId'},
    {'1': 'group_id', '3': 19, '4': 1, '5': 12, '10': 'groupId'},
    {'1': 'reply_to_message_id', '3': 20, '4': 1, '5': 12, '10': 'replyToMessageId'},
    {'1': 'reply_to_text', '3': 21, '4': 1, '5': 9, '10': 'replyToText'},
    {'1': 'reply_to_sender', '3': 22, '4': 1, '5': 9, '10': 'replyToSender'},
    {'1': 'link_preview', '3': 23, '4': 1, '5': 11, '6': '.cleona.LinkPreview', '10': 'linkPreview'},
    {'1': 'sender_device_node_id', '3': 24, '4': 1, '5': 12, '10': 'senderDeviceNodeId'},
  ],
  '9': [
    {'1': 15, '2': 16},
  ],
};

/// Descriptor for `MessageEnvelope`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List messageEnvelopeDescriptor = $convert.base64Decode(
    'Cg9NZXNzYWdlRW52ZWxvcGUSGAoHdmVyc2lvbhgBIAEoDVIHdmVyc2lvbhIbCglzZW5kZXJfaW'
    'QYAiABKAxSCHNlbmRlcklkEiEKDHJlY2lwaWVudF9pZBgDIAEoDFILcmVjaXBpZW50SWQSHAoJ'
    'dGltZXN0YW1wGAQgASgEUgl0aW1lc3RhbXASNgoMbWVzc2FnZV90eXBlGAUgASgOMhMuY2xlb2'
    '5hLk1lc3NhZ2VUeXBlUgttZXNzYWdlVHlwZRIrChFlbmNyeXB0ZWRfcGF5bG9hZBgGIAEoDFIQ'
    'ZW5jcnlwdGVkUGF5bG9hZBIrChFzaWduYXR1cmVfZWQyNTUxORgHIAEoDFIQc2lnbmF0dXJlRW'
    'QyNTUxORIoChBzaWduYXR1cmVfbWxfZHNhGAggASgMUg5zaWduYXR1cmVNbERzYRJCChBjb250'
    'ZW50X21ldGFkYXRhGAkgASgLMhcuY2xlb25hLkNvbnRlbnRNZXRhZGF0YVIPY29udGVudE1ldG'
    'FkYXRhEjkKDWVkaXRfbWV0YWRhdGEYCiABKAsyFC5jbGVvbmEuRWRpdE1ldGFkYXRhUgxlZGl0'
    'TWV0YWRhdGESPwoPZXhwaXJ5X21ldGFkYXRhGAsgASgLMhYuY2xlb25hLkV4cGlyeU1ldGFkYX'
    'RhUg5leHBpcnlNZXRhZGF0YRJIChBlcmFzdXJlX21ldGFkYXRhGAwgASgLMh0uY2xlb25hLkVy'
    'YXN1cmVDb2RpbmdNZXRhZGF0YVIPZXJhc3VyZU1ldGFkYXRhEiUKA3BvdxgNIAEoCzITLmNsZW'
    '9uYS5Qcm9vZk9mV29ya1IDcG93EjQKCmtlbV9oZWFkZXIYDiABKAsyFS5jbGVvbmEuUGVyTWVz'
    'c2FnZUtlbVIJa2VtSGVhZGVyEjkKC2NvbXByZXNzaW9uGBAgASgOMhcuY2xlb25hLkNvbXByZX'
    'NzaW9uVHlwZVILY29tcHJlc3Npb24SHwoLbmV0d29ya190YWcYESABKAlSCm5ldHdvcmtUYWcS'
    'HQoKbWVzc2FnZV9pZBgSIAEoDFIJbWVzc2FnZUlkEhkKCGdyb3VwX2lkGBMgASgMUgdncm91cE'
    'lkEi0KE3JlcGx5X3RvX21lc3NhZ2VfaWQYFCABKAxSEHJlcGx5VG9NZXNzYWdlSWQSIgoNcmVw'
    'bHlfdG9fdGV4dBgVIAEoCVILcmVwbHlUb1RleHQSJgoPcmVwbHlfdG9fc2VuZGVyGBYgASgJUg'
    '1yZXBseVRvU2VuZGVyEjYKDGxpbmtfcHJldmlldxgXIAEoCzITLmNsZW9uYS5MaW5rUHJldmll'
    'd1ILbGlua1ByZXZpZXcSMQoVc2VuZGVyX2RldmljZV9ub2RlX2lkGBggASgMUhJzZW5kZXJEZX'
    'ZpY2VOb2RlSWRKBAgPEBA=');

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
  ],
};

/// Descriptor for `ContentMetadata`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List contentMetadataDescriptor = $convert.base64Decode(
    'Cg9Db250ZW50TWV0YWRhdGESGwoJbWltZV90eXBlGAEgASgJUghtaW1lVHlwZRIbCglmaWxlX3'
    'NpemUYAiABKARSCGZpbGVTaXplEhoKCGZpbGVuYW1lGAMgASgJUghmaWxlbmFtZRIfCgtkdXJh'
    'dGlvbl9tcxgEIAEoDVIKZHVyYXRpb25NcxIcCgl0aHVtYm5haWwYBSABKAxSCXRodW1ibmFpbB'
    'IhCgxjb250ZW50X2hhc2gYBiABKAxSC2NvbnRlbnRIYXNo');

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

@$core.Deprecated('Use erasureCodingMetadataDescriptor instead')
const ErasureCodingMetadata$json = {
  '1': 'ErasureCodingMetadata',
  '2': [
    {'1': 'mailbox_id', '3': 1, '4': 1, '5': 12, '10': 'mailboxId'},
    {'1': 'original_message_id', '3': 2, '4': 1, '5': 12, '10': 'originalMessageId'},
    {'1': 'fragment_index', '3': 3, '4': 1, '5': 13, '10': 'fragmentIndex'},
    {'1': 'total_fragments', '3': 4, '4': 1, '5': 13, '10': 'totalFragments'},
    {'1': 'required_fragments', '3': 5, '4': 1, '5': 13, '10': 'requiredFragments'},
    {'1': 'original_size', '3': 6, '4': 1, '5': 13, '10': 'originalSize'},
  ],
};

/// Descriptor for `ErasureCodingMetadata`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List erasureCodingMetadataDescriptor = $convert.base64Decode(
    'ChVFcmFzdXJlQ29kaW5nTWV0YWRhdGESHQoKbWFpbGJveF9pZBgBIAEoDFIJbWFpbGJveElkEi'
    '4KE29yaWdpbmFsX21lc3NhZ2VfaWQYAiABKAxSEW9yaWdpbmFsTWVzc2FnZUlkEiUKDmZyYWdt'
    'ZW50X2luZGV4GAMgASgNUg1mcmFnbWVudEluZGV4EicKD3RvdGFsX2ZyYWdtZW50cxgEIAEoDV'
    'IOdG90YWxGcmFnbWVudHMSLQoScmVxdWlyZWRfZnJhZ21lbnRzGAUgASgNUhFyZXF1aXJlZEZy'
    'YWdtZW50cxIjCg1vcmlnaW5hbF9zaXplGAYgASgNUgxvcmlnaW5hbFNpemU=');

@$core.Deprecated('Use proofOfWorkDescriptor instead')
const ProofOfWork$json = {
  '1': 'ProofOfWork',
  '2': [
    {'1': 'nonce', '3': 1, '4': 1, '5': 4, '10': 'nonce'},
    {'1': 'difficulty', '3': 2, '4': 1, '5': 13, '10': 'difficulty'},
    {'1': 'hash', '3': 3, '4': 1, '5': 12, '10': 'hash'},
  ],
};

/// Descriptor for `ProofOfWork`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List proofOfWorkDescriptor = $convert.base64Decode(
    'CgtQcm9vZk9mV29yaxIUCgVub25jZRgBIAEoBFIFbm9uY2USHgoKZGlmZmljdWx0eRgCIAEoDV'
    'IKZGlmZmljdWx0eRISCgRoYXNoGAMgASgMUgRoYXNo');

@$core.Deprecated('Use perMessageKemDescriptor instead')
const PerMessageKem$json = {
  '1': 'PerMessageKem',
  '2': [
    {'1': 'ephemeral_x25519_pk', '3': 1, '4': 1, '5': 12, '10': 'ephemeralX25519Pk'},
    {'1': 'ml_kem_ciphertext', '3': 2, '4': 1, '5': 12, '10': 'mlKemCiphertext'},
    {'1': 'aes_nonce', '3': 3, '4': 1, '5': 12, '10': 'aesNonce'},
    {'1': 'version', '3': 4, '4': 1, '5': 13, '10': 'version'},
  ],
};

/// Descriptor for `PerMessageKem`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List perMessageKemDescriptor = $convert.base64Decode(
    'Cg1QZXJNZXNzYWdlS2VtEi4KE2VwaGVtZXJhbF94MjU1MTlfcGsYASABKAxSEWVwaGVtZXJhbF'
    'gyNTUxOVBrEioKEW1sX2tlbV9jaXBoZXJ0ZXh0GAIgASgMUg9tbEtlbUNpcGhlcnRleHQSGwoJ'
    'YWVzX25vbmNlGAMgASgMUghhZXNOb25jZRIYCgd2ZXJzaW9uGAQgASgNUgd2ZXJzaW9u');

@$core.Deprecated('Use peerInfoProtoDescriptor instead')
const PeerInfoProto$json = {
  '1': 'PeerInfoProto',
  '2': [
    {'1': 'node_id', '3': 1, '4': 1, '5': 12, '10': 'nodeId'},
    {'1': 'public_ip', '3': 2, '4': 1, '5': 9, '10': 'publicIp'},
    {'1': 'public_port', '3': 3, '4': 1, '5': 13, '10': 'publicPort'},
    {'1': 'local_ip', '3': 4, '4': 1, '5': 9, '10': 'localIp'},
    {'1': 'local_port', '3': 5, '4': 1, '5': 13, '10': 'localPort'},
    {'1': 'addresses', '3': 6, '4': 3, '5': 11, '6': '.cleona.PeerAddressProto', '10': 'addresses'},
    {'1': 'network_tag', '3': 7, '4': 1, '5': 9, '10': 'networkTag'},
    {'1': 'last_seen', '3': 8, '4': 1, '5': 4, '10': 'lastSeen'},
    {'1': 'nat_type', '3': 9, '4': 1, '5': 14, '6': '.cleona.NatType', '10': 'natType'},
    {'1': 'capabilities', '3': 10, '4': 1, '5': 13, '10': 'capabilities'},
    {'1': 'ed25519_public_key', '3': 11, '4': 1, '5': 12, '10': 'ed25519PublicKey'},
    {'1': 'ml_dsa_public_key', '3': 12, '4': 1, '5': 12, '10': 'mlDsaPublicKey'},
    {'1': 'ed25519_signature', '3': 13, '4': 1, '5': 12, '10': 'ed25519Signature'},
    {'1': 'ml_dsa_signature', '3': 14, '4': 1, '5': 12, '10': 'mlDsaSignature'},
    {'1': 'x25519_public_key', '3': 15, '4': 1, '5': 12, '10': 'x25519PublicKey'},
    {'1': 'ml_kem_public_key', '3': 16, '4': 1, '5': 12, '10': 'mlKemPublicKey'},
    {'1': 'user_id', '3': 17, '4': 1, '5': 12, '10': 'userId'},
  ],
};

/// Descriptor for `PeerInfoProto`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List peerInfoProtoDescriptor = $convert.base64Decode(
    'Cg1QZWVySW5mb1Byb3RvEhcKB25vZGVfaWQYASABKAxSBm5vZGVJZBIbCglwdWJsaWNfaXAYAi'
    'ABKAlSCHB1YmxpY0lwEh8KC3B1YmxpY19wb3J0GAMgASgNUgpwdWJsaWNQb3J0EhkKCGxvY2Fs'
    'X2lwGAQgASgJUgdsb2NhbElwEh0KCmxvY2FsX3BvcnQYBSABKA1SCWxvY2FsUG9ydBI2CglhZG'
    'RyZXNzZXMYBiADKAsyGC5jbGVvbmEuUGVlckFkZHJlc3NQcm90b1IJYWRkcmVzc2VzEh8KC25l'
    'dHdvcmtfdGFnGAcgASgJUgpuZXR3b3JrVGFnEhsKCWxhc3Rfc2VlbhgIIAEoBFIIbGFzdFNlZW'
    '4SKgoIbmF0X3R5cGUYCSABKA4yDy5jbGVvbmEuTmF0VHlwZVIHbmF0VHlwZRIiCgxjYXBhYmls'
    'aXRpZXMYCiABKA1SDGNhcGFiaWxpdGllcxIsChJlZDI1NTE5X3B1YmxpY19rZXkYCyABKAxSEG'
    'VkMjU1MTlQdWJsaWNLZXkSKQoRbWxfZHNhX3B1YmxpY19rZXkYDCABKAxSDm1sRHNhUHVibGlj'
    'S2V5EisKEWVkMjU1MTlfc2lnbmF0dXJlGA0gASgMUhBlZDI1NTE5U2lnbmF0dXJlEigKEG1sX2'
    'RzYV9zaWduYXR1cmUYDiABKAxSDm1sRHNhU2lnbmF0dXJlEioKEXgyNTUxOV9wdWJsaWNfa2V5'
    'GA8gASgMUg94MjU1MTlQdWJsaWNLZXkSKQoRbWxfa2VtX3B1YmxpY19rZXkYECABKAxSDm1sS2'
    'VtUHVibGljS2V5EhcKB3VzZXJfaWQYESABKAxSBnVzZXJJZA==');

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

@$core.Deprecated('Use dhtPingDescriptor instead')
const DhtPing$json = {
  '1': 'DhtPing',
  '2': [
    {'1': 'sender_id', '3': 1, '4': 1, '5': 12, '10': 'senderId'},
    {'1': 'timestamp', '3': 2, '4': 1, '5': 4, '10': 'timestamp'},
  ],
};

/// Descriptor for `DhtPing`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List dhtPingDescriptor = $convert.base64Decode(
    'CgdEaHRQaW5nEhsKCXNlbmRlcl9pZBgBIAEoDFIIc2VuZGVySWQSHAoJdGltZXN0YW1wGAIgAS'
    'gEUgl0aW1lc3RhbXA=');

@$core.Deprecated('Use dhtPongDescriptor instead')
const DhtPong$json = {
  '1': 'DhtPong',
  '2': [
    {'1': 'sender_id', '3': 1, '4': 1, '5': 12, '10': 'senderId'},
    {'1': 'timestamp', '3': 2, '4': 1, '5': 4, '10': 'timestamp'},
    {'1': 'observed_ip', '3': 3, '4': 1, '5': 9, '10': 'observedIp'},
    {'1': 'observed_port', '3': 4, '4': 1, '5': 13, '10': 'observedPort'},
    {'1': 'additional_node_ids', '3': 5, '4': 3, '5': 12, '10': 'additionalNodeIds'},
  ],
};

/// Descriptor for `DhtPong`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List dhtPongDescriptor = $convert.base64Decode(
    'CgdEaHRQb25nEhsKCXNlbmRlcl9pZBgBIAEoDFIIc2VuZGVySWQSHAoJdGltZXN0YW1wGAIgAS'
    'gEUgl0aW1lc3RhbXASHwoLb2JzZXJ2ZWRfaXAYAyABKAlSCm9ic2VydmVkSXASIwoNb2JzZXJ2'
    'ZWRfcG9ydBgEIAEoDVIMb2JzZXJ2ZWRQb3J0Ei4KE2FkZGl0aW9uYWxfbm9kZV9pZHMYBSADKA'
    'xSEWFkZGl0aW9uYWxOb2RlSWRz');

@$core.Deprecated('Use dhtFindNodeDescriptor instead')
const DhtFindNode$json = {
  '1': 'DhtFindNode',
  '2': [
    {'1': 'target_id', '3': 1, '4': 1, '5': 12, '10': 'targetId'},
    {'1': 'sender_id', '3': 2, '4': 1, '5': 12, '10': 'senderId'},
  ],
};

/// Descriptor for `DhtFindNode`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List dhtFindNodeDescriptor = $convert.base64Decode(
    'CgtEaHRGaW5kTm9kZRIbCgl0YXJnZXRfaWQYASABKAxSCHRhcmdldElkEhsKCXNlbmRlcl9pZB'
    'gCIAEoDFIIc2VuZGVySWQ=');

@$core.Deprecated('Use dhtFindNodeResponseDescriptor instead')
const DhtFindNodeResponse$json = {
  '1': 'DhtFindNodeResponse',
  '2': [
    {'1': 'closest_peers', '3': 1, '4': 3, '5': 11, '6': '.cleona.PeerInfoProto', '10': 'closestPeers'},
  ],
};

/// Descriptor for `DhtFindNodeResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List dhtFindNodeResponseDescriptor = $convert.base64Decode(
    'ChNEaHRGaW5kTm9kZVJlc3BvbnNlEjoKDWNsb3Nlc3RfcGVlcnMYASADKAsyFS5jbGVvbmEuUG'
    'VlckluZm9Qcm90b1IMY2xvc2VzdFBlZXJz');

@$core.Deprecated('Use dhtStoreDescriptor instead')
const DhtStore$json = {
  '1': 'DhtStore',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 12, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 12, '10': 'value'},
    {'1': 'ttl_ms', '3': 3, '4': 1, '5': 4, '10': 'ttlMs'},
  ],
};

/// Descriptor for `DhtStore`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List dhtStoreDescriptor = $convert.base64Decode(
    'CghEaHRTdG9yZRIQCgNrZXkYASABKAxSA2tleRIUCgV2YWx1ZRgCIAEoDFIFdmFsdWUSFQoGdH'
    'RsX21zGAMgASgEUgV0dGxNcw==');

@$core.Deprecated('Use dhtStoreResponseDescriptor instead')
const DhtStoreResponse$json = {
  '1': 'DhtStoreResponse',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
  ],
};

/// Descriptor for `DhtStoreResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List dhtStoreResponseDescriptor = $convert.base64Decode(
    'ChBEaHRTdG9yZVJlc3BvbnNlEhgKB3N1Y2Nlc3MYASABKAhSB3N1Y2Nlc3M=');

@$core.Deprecated('Use dhtFindValueDescriptor instead')
const DhtFindValue$json = {
  '1': 'DhtFindValue',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 12, '10': 'key'},
  ],
};

/// Descriptor for `DhtFindValue`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List dhtFindValueDescriptor = $convert.base64Decode(
    'CgxEaHRGaW5kVmFsdWUSEAoDa2V5GAEgASgMUgNrZXk=');

@$core.Deprecated('Use dhtFindValueResponseDescriptor instead')
const DhtFindValueResponse$json = {
  '1': 'DhtFindValueResponse',
  '2': [
    {'1': 'value', '3': 1, '4': 1, '5': 12, '10': 'value'},
    {'1': 'closest_peers', '3': 2, '4': 3, '5': 11, '6': '.cleona.PeerInfoProto', '10': 'closestPeers'},
    {'1': 'found', '3': 3, '4': 1, '5': 8, '10': 'found'},
  ],
};

/// Descriptor for `DhtFindValueResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List dhtFindValueResponseDescriptor = $convert.base64Decode(
    'ChREaHRGaW5kVmFsdWVSZXNwb25zZRIUCgV2YWx1ZRgBIAEoDFIFdmFsdWUSOgoNY2xvc2VzdF'
    '9wZWVycxgCIAMoCzIVLmNsZW9uYS5QZWVySW5mb1Byb3RvUgxjbG9zZXN0UGVlcnMSFAoFZm91'
    'bmQYAyABKAhSBWZvdW5k');

@$core.Deprecated('Use peerListSummaryDescriptor instead')
const PeerListSummary$json = {
  '1': 'PeerListSummary',
  '2': [
    {'1': 'entries', '3': 1, '4': 3, '5': 11, '6': '.cleona.PeerSummaryEntry', '10': 'entries'},
  ],
};

/// Descriptor for `PeerListSummary`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List peerListSummaryDescriptor = $convert.base64Decode(
    'Cg9QZWVyTGlzdFN1bW1hcnkSMgoHZW50cmllcxgBIAMoCzIYLmNsZW9uYS5QZWVyU3VtbWFyeU'
    'VudHJ5UgdlbnRyaWVz');

@$core.Deprecated('Use peerSummaryEntryDescriptor instead')
const PeerSummaryEntry$json = {
  '1': 'PeerSummaryEntry',
  '2': [
    {'1': 'node_id', '3': 1, '4': 1, '5': 12, '10': 'nodeId'},
    {'1': 'last_seen', '3': 2, '4': 1, '5': 4, '10': 'lastSeen'},
  ],
};

/// Descriptor for `PeerSummaryEntry`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List peerSummaryEntryDescriptor = $convert.base64Decode(
    'ChBQZWVyU3VtbWFyeUVudHJ5EhcKB25vZGVfaWQYASABKAxSBm5vZGVJZBIbCglsYXN0X3NlZW'
    '4YAiABKARSCGxhc3RTZWVu');

@$core.Deprecated('Use peerListWantDescriptor instead')
const PeerListWant$json = {
  '1': 'PeerListWant',
  '2': [
    {'1': 'wanted_node_ids', '3': 1, '4': 3, '5': 12, '10': 'wantedNodeIds'},
  ],
};

/// Descriptor for `PeerListWant`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List peerListWantDescriptor = $convert.base64Decode(
    'CgxQZWVyTGlzdFdhbnQSJgoPd2FudGVkX25vZGVfaWRzGAEgAygMUg13YW50ZWROb2RlSWRz');

@$core.Deprecated('Use peerListPushDescriptor instead')
const PeerListPush$json = {
  '1': 'PeerListPush',
  '2': [
    {'1': 'peers', '3': 1, '4': 3, '5': 11, '6': '.cleona.PeerInfoProto', '10': 'peers'},
  ],
};

/// Descriptor for `PeerListPush`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List peerListPushDescriptor = $convert.base64Decode(
    'CgxQZWVyTGlzdFB1c2gSKwoFcGVlcnMYASADKAsyFS5jbGVvbmEuUGVlckluZm9Qcm90b1IFcG'
    'VlcnM=');

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

@$core.Deprecated('Use groupInviteDescriptor instead')
const GroupInvite$json = {
  '1': 'GroupInvite',
  '2': [
    {'1': 'group_id', '3': 1, '4': 1, '5': 12, '10': 'groupId'},
    {'1': 'group_name', '3': 2, '4': 1, '5': 9, '10': 'groupName'},
    {'1': 'inviter_id', '3': 3, '4': 1, '5': 12, '10': 'inviterId'},
    {'1': 'members', '3': 4, '4': 3, '5': 11, '6': '.cleona.GroupMember', '10': 'members'},
    {'1': 'group_picture', '3': 5, '4': 1, '5': 12, '10': 'groupPicture'},
    {'1': 'group_description', '3': 6, '4': 1, '5': 9, '10': 'groupDescription'},
  ],
};

/// Descriptor for `GroupInvite`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List groupInviteDescriptor = $convert.base64Decode(
    'CgtHcm91cEludml0ZRIZCghncm91cF9pZBgBIAEoDFIHZ3JvdXBJZBIdCgpncm91cF9uYW1lGA'
    'IgASgJUglncm91cE5hbWUSHQoKaW52aXRlcl9pZBgDIAEoDFIJaW52aXRlcklkEi0KB21lbWJl'
    'cnMYBCADKAsyEy5jbGVvbmEuR3JvdXBNZW1iZXJSB21lbWJlcnMSIwoNZ3JvdXBfcGljdHVyZR'
    'gFIAEoDFIMZ3JvdXBQaWN0dXJlEisKEWdyb3VwX2Rlc2NyaXB0aW9uGAYgASgJUhBncm91cERl'
    'c2NyaXB0aW9u');

@$core.Deprecated('Use groupMemberDescriptor instead')
const GroupMember$json = {
  '1': 'GroupMember',
  '2': [
    {'1': 'node_id', '3': 1, '4': 1, '5': 12, '10': 'nodeId'},
    {'1': 'display_name', '3': 2, '4': 1, '5': 9, '10': 'displayName'},
    {'1': 'role', '3': 3, '4': 1, '5': 9, '10': 'role'},
    {'1': 'ed25519_public_key', '3': 4, '4': 1, '5': 12, '10': 'ed25519PublicKey'},
    {'1': 'x25519_public_key', '3': 5, '4': 1, '5': 12, '10': 'x25519PublicKey'},
    {'1': 'ml_kem_public_key', '3': 6, '4': 1, '5': 12, '10': 'mlKemPublicKey'},
  ],
};

/// Descriptor for `GroupMember`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List groupMemberDescriptor = $convert.base64Decode(
    'CgtHcm91cE1lbWJlchIXCgdub2RlX2lkGAEgASgMUgZub2RlSWQSIQoMZGlzcGxheV9uYW1lGA'
    'IgASgJUgtkaXNwbGF5TmFtZRISCgRyb2xlGAMgASgJUgRyb2xlEiwKEmVkMjU1MTlfcHVibGlj'
    'X2tleRgEIAEoDFIQZWQyNTUxOVB1YmxpY0tleRIqChF4MjU1MTlfcHVibGljX2tleRgFIAEoDF'
    'IPeDI1NTE5UHVibGljS2V5EikKEW1sX2tlbV9wdWJsaWNfa2V5GAYgASgMUg5tbEtlbVB1Ymxp'
    'Y0tleQ==');

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
    {'1': 'members', '3': 8, '4': 3, '5': 11, '6': '.cleona.GroupMember', '10': 'members'},
    {'1': 'is_public', '3': 9, '4': 1, '5': 8, '10': 'isPublic'},
    {'1': 'is_adult', '3': 10, '4': 1, '5': 8, '10': 'isAdult'},
    {'1': 'language', '3': 11, '4': 1, '5': 9, '10': 'language'},
  ],
};

/// Descriptor for `ChannelInvite`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List channelInviteDescriptor = $convert.base64Decode(
    'Cg1DaGFubmVsSW52aXRlEh0KCmNoYW5uZWxfaWQYASABKAxSCWNoYW5uZWxJZBIhCgxjaGFubm'
    'VsX25hbWUYAiABKAlSC2NoYW5uZWxOYW1lEh0KCmludml0ZXJfaWQYAyABKAxSCWludml0ZXJJ'
    'ZBISCgRyb2xlGAQgASgJUgRyb2xlEicKD3dlbGNvbWVfbWVzc2FnZRgFIAEoDFIOd2VsY29tZU'
    '1lc3NhZ2USJwoPY2hhbm5lbF9waWN0dXJlGAYgASgMUg5jaGFubmVsUGljdHVyZRIvChNjaGFu'
    'bmVsX2Rlc2NyaXB0aW9uGAcgASgJUhJjaGFubmVsRGVzY3JpcHRpb24SLQoHbWVtYmVycxgIIA'
    'MoCzITLmNsZW9uYS5Hcm91cE1lbWJlclIHbWVtYmVycxIbCglpc19wdWJsaWMYCSABKAhSCGlz'
    'UHVibGljEhkKCGlzX2FkdWx0GAogASgIUgdpc0FkdWx0EhoKCGxhbmd1YWdlGAsgASgJUghsYW'
    '5ndWFnZQ==');

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
  ],
};

/// Descriptor for `RestoreBroadcast`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List restoreBroadcastDescriptor = $convert.base64Decode(
    'ChBSZXN0b3JlQnJvYWRjYXN0Eh4KC29sZF9ub2RlX2lkGAEgASgMUglvbGROb2RlSWQSHgoLbm'
    'V3X25vZGVfaWQYAiABKAxSCW5ld05vZGVJZBIkCg5uZXdfZWQyNTUxOV9waxgDIAEoDFIMbmV3'
    'RWQyNTUxOVBrEiIKDW5ld194MjU1MTlfcGsYBCABKAxSC25ld1gyNTUxOVBrEiEKDW5ld19tbF'
    '9rZW1fcGsYBSABKAxSCm5ld01sS2VtUGsSIQoNbmV3X21sX2RzYV9waxgGIAEoDFIKbmV3TWxE'
    'c2FQaxIhCgxkaXNwbGF5X25hbWUYByABKAlSC2Rpc3BsYXlOYW1lEhwKCXRpbWVzdGFtcBgIIA'
    'EoBFIJdGltZXN0YW1wEhwKCXNpZ25hdHVyZRgJIAEoDFIJc2lnbmF0dXJl');

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
  ],
};

/// Descriptor for `RestoreChannelInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List restoreChannelInfoDescriptor = $convert.base64Decode(
    'ChJSZXN0b3JlQ2hhbm5lbEluZm8SHQoKY2hhbm5lbF9pZBgBIAEoDFIJY2hhbm5lbElkEhIKBG'
    '5hbWUYAiABKAlSBG5hbWUSIAoLZGVzY3JpcHRpb24YAyABKAlSC2Rlc2NyaXB0aW9uEikKEW93'
    'bmVyX25vZGVfaWRfaGV4GAQgASgJUg5vd25lck5vZGVJZEhleBI2CgdtZW1iZXJzGAUgAygLMh'
    'wuY2xlb25hLlJlc3RvcmVDaGFubmVsTWVtYmVyUgdtZW1iZXJz');

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
    {'1': 'message_type', '3': 6, '4': 1, '5': 14, '6': '.cleona.MessageType', '10': 'messageType'},
    {'1': 'payload', '3': 7, '4': 1, '5': 12, '10': 'payload'},
  ],
};

/// Descriptor for `StoredMessage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List storedMessageDescriptor = $convert.base64Decode(
    'Cg1TdG9yZWRNZXNzYWdlEh0KCm1lc3NhZ2VfaWQYASABKAxSCW1lc3NhZ2VJZBIbCglzZW5kZX'
    'JfaWQYAiABKAxSCHNlbmRlcklkEiEKDHJlY2lwaWVudF9pZBgDIAEoDFILcmVjaXBpZW50SWQS'
    'JwoPY29udmVyc2F0aW9uX2lkGAQgASgJUg5jb252ZXJzYXRpb25JZBIcCgl0aW1lc3RhbXAYBS'
    'ABKARSCXRpbWVzdGFtcBI2CgxtZXNzYWdlX3R5cGUYBiABKA4yEy5jbGVvbmEuTWVzc2FnZVR5'
    'cGVSC21lc3NhZ2VUeXBlEhgKB3BheWxvYWQYByABKAxSB3BheWxvYWQ=');

@$core.Deprecated('Use fragmentStoreDescriptor instead')
const FragmentStore$json = {
  '1': 'FragmentStore',
  '2': [
    {'1': 'mailbox_id', '3': 1, '4': 1, '5': 12, '10': 'mailboxId'},
    {'1': 'message_id', '3': 2, '4': 1, '5': 12, '10': 'messageId'},
    {'1': 'fragment_index', '3': 3, '4': 1, '5': 13, '10': 'fragmentIndex'},
    {'1': 'total_fragments', '3': 4, '4': 1, '5': 13, '10': 'totalFragments'},
    {'1': 'required_fragments', '3': 5, '4': 1, '5': 13, '10': 'requiredFragments'},
    {'1': 'fragment_data', '3': 6, '4': 1, '5': 12, '10': 'fragmentData'},
    {'1': 'original_size', '3': 7, '4': 1, '5': 13, '10': 'originalSize'},
    {'1': 'ttl_ms', '3': 8, '4': 1, '5': 4, '10': 'ttlMs'},
  ],
};

/// Descriptor for `FragmentStore`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fragmentStoreDescriptor = $convert.base64Decode(
    'Cg1GcmFnbWVudFN0b3JlEh0KCm1haWxib3hfaWQYASABKAxSCW1haWxib3hJZBIdCgptZXNzYW'
    'dlX2lkGAIgASgMUgltZXNzYWdlSWQSJQoOZnJhZ21lbnRfaW5kZXgYAyABKA1SDWZyYWdtZW50'
    'SW5kZXgSJwoPdG90YWxfZnJhZ21lbnRzGAQgASgNUg50b3RhbEZyYWdtZW50cxItChJyZXF1aX'
    'JlZF9mcmFnbWVudHMYBSABKA1SEXJlcXVpcmVkRnJhZ21lbnRzEiMKDWZyYWdtZW50X2RhdGEY'
    'BiABKAxSDGZyYWdtZW50RGF0YRIjCg1vcmlnaW5hbF9zaXplGAcgASgNUgxvcmlnaW5hbFNpem'
    'USFQoGdHRsX21zGAggASgEUgV0dGxNcw==');

@$core.Deprecated('Use fragmentStoreAckDescriptor instead')
const FragmentStoreAck$json = {
  '1': 'FragmentStoreAck',
  '2': [
    {'1': 'message_id', '3': 1, '4': 1, '5': 12, '10': 'messageId'},
    {'1': 'fragment_index', '3': 2, '4': 1, '5': 13, '10': 'fragmentIndex'},
  ],
};

/// Descriptor for `FragmentStoreAck`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fragmentStoreAckDescriptor = $convert.base64Decode(
    'ChBGcmFnbWVudFN0b3JlQWNrEh0KCm1lc3NhZ2VfaWQYASABKAxSCW1lc3NhZ2VJZBIlCg5mcm'
    'FnbWVudF9pbmRleBgCIAEoDVINZnJhZ21lbnRJbmRleA==');

@$core.Deprecated('Use fragmentRetrieveDescriptor instead')
const FragmentRetrieve$json = {
  '1': 'FragmentRetrieve',
  '2': [
    {'1': 'mailbox_id', '3': 1, '4': 1, '5': 12, '10': 'mailboxId'},
  ],
};

/// Descriptor for `FragmentRetrieve`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fragmentRetrieveDescriptor = $convert.base64Decode(
    'ChBGcmFnbWVudFJldHJpZXZlEh0KCm1haWxib3hfaWQYASABKAxSCW1haWxib3hJZA==');

@$core.Deprecated('Use fragmentDeleteDescriptor instead')
const FragmentDelete$json = {
  '1': 'FragmentDelete',
  '2': [
    {'1': 'mailbox_id', '3': 1, '4': 1, '5': 12, '10': 'mailboxId'},
    {'1': 'message_id', '3': 2, '4': 1, '5': 12, '10': 'messageId'},
  ],
};

/// Descriptor for `FragmentDelete`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fragmentDeleteDescriptor = $convert.base64Decode(
    'Cg5GcmFnbWVudERlbGV0ZRIdCgptYWlsYm94X2lkGAEgASgMUgltYWlsYm94SWQSHQoKbWVzc2'
    'FnZV9pZBgCIAEoDFIJbWVzc2FnZUlk');

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
    {'1': 'group_call_key', '3': 7, '4': 1, '5': 12, '10': 'groupCallKey'},
  ],
};

/// Descriptor for `CallInvite`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List callInviteDescriptor = $convert.base64Decode(
    'CgpDYWxsSW52aXRlEhcKB2NhbGxfaWQYASABKAxSBmNhbGxJZBIvChRjYWxsZXJfZXBoX3gyNT'
    'UxOV9waxgCIAEoDFIRY2FsbGVyRXBoWDI1NTE5UGsSMgoVY2FsbGVyX2tlbV9jaXBoZXJ0ZXh0'
    'GAMgASgMUhNjYWxsZXJLZW1DaXBoZXJ0ZXh0EhkKCGlzX3ZpZGVvGAQgASgIUgdpc1ZpZGVvEi'
    'IKDWlzX2dyb3VwX2NhbGwYBSABKAhSC2lzR3JvdXBDYWxsEhkKCGdyb3VwX2lkGAYgASgMUgdn'
    'cm91cElkEiQKDmdyb3VwX2NhbGxfa2V5GAcgASgMUgxncm91cENhbGxLZXk=');

@$core.Deprecated('Use callAnswerDescriptor instead')
const CallAnswer$json = {
  '1': 'CallAnswer',
  '2': [
    {'1': 'call_id', '3': 1, '4': 1, '5': 12, '10': 'callId'},
    {'1': 'callee_eph_x25519_pk', '3': 2, '4': 1, '5': 12, '10': 'calleeEphX25519Pk'},
    {'1': 'callee_kem_ciphertext', '3': 3, '4': 1, '5': 12, '10': 'calleeKemCiphertext'},
  ],
};

/// Descriptor for `CallAnswer`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List callAnswerDescriptor = $convert.base64Decode(
    'CgpDYWxsQW5zd2VyEhcKB2NhbGxfaWQYASABKAxSBmNhbGxJZBIvChRjYWxsZWVfZXBoX3gyNT'
    'UxOV9waxgCIAEoDFIRY2FsbGVlRXBoWDI1NTE5UGsSMgoVY2FsbGVlX2tlbV9jaXBoZXJ0ZXh0'
    'GAMgASgMUhNjYWxsZWVLZW1DaXBoZXJ0ZXh0');

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
  ],
};

/// Descriptor for `JuryRequestMsg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List juryRequestMsgDescriptor = $convert.base64Decode(
    'Cg5KdXJ5UmVxdWVzdE1zZxIXCgdqdXJ5X2lkGAEgASgMUgZqdXJ5SWQSHQoKY2hhbm5lbF9pZB'
    'gCIAEoDFIJY2hhbm5lbElkEhsKCXJlcG9ydF9pZBgDIAEoDFIIcmVwb3J0SWQSGgoIY2F0ZWdv'
    'cnkYBCABKA1SCGNhdGVnb3J5EioKEWV2aWRlbmNlX3Bvc3RfaWRzGAUgAygMUg9ldmlkZW5jZV'
    'Bvc3RJZHMSLQoScmVwb3J0X2Rlc2NyaXB0aW9uGAYgASgJUhFyZXBvcnREZXNjcmlwdGlvbhIh'
    'CgxjaGFubmVsX25hbWUYByABKAlSC2NoYW5uZWxOYW1lEikKEGNoYW5uZWxfbGFuZ3VhZ2UYCC'
    'ABKAlSD2NoYW5uZWxMYW5ndWFnZQ==');

@$core.Deprecated('Use juryVoteMsgDescriptor instead')
const JuryVoteMsg$json = {
  '1': 'JuryVoteMsg',
  '2': [
    {'1': 'jury_id', '3': 1, '4': 1, '5': 12, '10': 'juryId'},
    {'1': 'report_id', '3': 2, '4': 1, '5': 12, '10': 'reportId'},
    {'1': 'vote', '3': 3, '4': 1, '5': 13, '10': 'vote'},
    {'1': 'reason', '3': 4, '4': 1, '5': 9, '10': 'reason'},
  ],
};

/// Descriptor for `JuryVoteMsg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List juryVoteMsgDescriptor = $convert.base64Decode(
    'CgtKdXJ5Vm90ZU1zZxIXCgdqdXJ5X2lkGAEgASgMUgZqdXJ5SWQSGwoJcmVwb3J0X2lkGAIgAS'
    'gMUghyZXBvcnRJZBISCgR2b3RlGAMgASgNUgR2b3RlEhYKBnJlYXNvbhgEIAEoCVIGcmVhc29u');

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
  ],
};

/// Descriptor for `JuryResultMsg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List juryResultMsgDescriptor = $convert.base64Decode(
    'Cg1KdXJ5UmVzdWx0TXNnEhcKB2p1cnlfaWQYASABKAxSBmp1cnlJZBIbCglyZXBvcnRfaWQYAi'
    'ABKAxSCHJlcG9ydElkEh0KCmNoYW5uZWxfaWQYAyABKAxSCWNoYW5uZWxJZBIgCgtjb25zZXF1'
    'ZW5jZRgEIAEoDVILY29uc2VxdWVuY2USIwoNdm90ZXNfYXBwcm92ZRgFIAEoDVIMdm90ZXNBcH'
    'Byb3ZlEiEKDHZvdGVzX3JlamVjdBgGIAEoDVILdm90ZXNSZWplY3QSIwoNdm90ZXNfYWJzdGFp'
    'bhgHIAEoDVIMdm90ZXNBYnN0YWluEi0KE25ld19iYWRfYmFkZ2VfbGV2ZWwYCCABKA1SEG5ld0'
    'JhZEJhZGdlTGV2ZWw=');

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
    'bmVyU2lnbmF0dXJl');

@$core.Deprecated('Use reachabilityCheckDescriptor instead')
const ReachabilityCheck$json = {
  '1': 'ReachabilityCheck',
  '2': [
    {'1': 'target_node_id', '3': 1, '4': 1, '5': 12, '10': 'targetNodeId'},
    {'1': 'bloom_filter', '3': 2, '4': 1, '5': 12, '10': 'bloomFilter'},
    {'1': 'hops_remaining', '3': 3, '4': 1, '5': 13, '10': 'hopsRemaining'},
    {'1': 'request_id', '3': 4, '4': 1, '5': 12, '10': 'requestId'},
  ],
};

/// Descriptor for `ReachabilityCheck`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List reachabilityCheckDescriptor = $convert.base64Decode(
    'ChFSZWFjaGFiaWxpdHlDaGVjaxIkCg50YXJnZXRfbm9kZV9pZBgBIAEoDFIMdGFyZ2V0Tm9kZU'
    'lkEiEKDGJsb29tX2ZpbHRlchgCIAEoDFILYmxvb21GaWx0ZXISJQoOaG9wc19yZW1haW5pbmcY'
    'AyABKA1SDWhvcHNSZW1haW5pbmcSHQoKcmVxdWVzdF9pZBgEIAEoDFIJcmVxdWVzdElk');

@$core.Deprecated('Use reachabilityResponseDescriptor instead')
const ReachabilityResponse$json = {
  '1': 'ReachabilityResponse',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 12, '10': 'requestId'},
    {'1': 'reached', '3': 2, '4': 1, '5': 8, '10': 'reached'},
  ],
};

/// Descriptor for `ReachabilityResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List reachabilityResponseDescriptor = $convert.base64Decode(
    'ChRSZWFjaGFiaWxpdHlSZXNwb25zZRIdCgpyZXF1ZXN0X2lkGAEgASgMUglyZXF1ZXN0SWQSGA'
    'oHcmVhY2hlZBgCIAEoCFIHcmVhY2hlZA==');

@$core.Deprecated('Use deliveryReceiptDescriptor instead')
const DeliveryReceipt$json = {
  '1': 'DeliveryReceipt',
  '2': [
    {'1': 'message_id', '3': 1, '4': 1, '5': 12, '10': 'messageId'},
    {'1': 'delivered_at', '3': 2, '4': 1, '5': 4, '10': 'deliveredAt'},
  ],
};

/// Descriptor for `DeliveryReceipt`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deliveryReceiptDescriptor = $convert.base64Decode(
    'Cg9EZWxpdmVyeVJlY2VpcHQSHQoKbWVzc2FnZV9pZBgBIAEoDFIJbWVzc2FnZUlkEiEKDGRlbG'
    'l2ZXJlZF9hdBgCIAEoBFILZGVsaXZlcmVkQXQ=');

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

@$core.Deprecated('Use guardianShareStoreDescriptor instead')
const GuardianShareStore$json = {
  '1': 'GuardianShareStore',
  '2': [
    {'1': 'share_data', '3': 1, '4': 1, '5': 12, '10': 'shareData'},
    {'1': 'owner_node_id', '3': 2, '4': 1, '5': 12, '10': 'ownerNodeId'},
    {'1': 'owner_display_name', '3': 3, '4': 1, '5': 9, '10': 'ownerDisplayName'},
  ],
};

/// Descriptor for `GuardianShareStore`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List guardianShareStoreDescriptor = $convert.base64Decode(
    'ChJHdWFyZGlhblNoYXJlU3RvcmUSHQoKc2hhcmVfZGF0YRgBIAEoDFIJc2hhcmVEYXRhEiIKDW'
    '93bmVyX25vZGVfaWQYAiABKAxSC293bmVyTm9kZUlkEiwKEm93bmVyX2Rpc3BsYXlfbmFtZRgD'
    'IAEoCVIQb3duZXJEaXNwbGF5TmFtZQ==');

@$core.Deprecated('Use guardianRestoreRequestDescriptor instead')
const GuardianRestoreRequest$json = {
  '1': 'GuardianRestoreRequest',
  '2': [
    {'1': 'owner_node_id', '3': 1, '4': 1, '5': 12, '10': 'ownerNodeId'},
    {'1': 'owner_display_name', '3': 2, '4': 1, '5': 9, '10': 'ownerDisplayName'},
    {'1': 'triggering_guardian_node_id', '3': 3, '4': 1, '5': 12, '10': 'triggeringGuardianNodeId'},
    {'1': 'triggering_guardian_name', '3': 4, '4': 1, '5': 9, '10': 'triggeringGuardianName'},
    {'1': 'recovery_mailbox_id', '3': 5, '4': 1, '5': 12, '10': 'recoveryMailboxId'},
  ],
};

/// Descriptor for `GuardianRestoreRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List guardianRestoreRequestDescriptor = $convert.base64Decode(
    'ChZHdWFyZGlhblJlc3RvcmVSZXF1ZXN0EiIKDW93bmVyX25vZGVfaWQYASABKAxSC293bmVyTm'
    '9kZUlkEiwKEm93bmVyX2Rpc3BsYXlfbmFtZRgCIAEoCVIQb3duZXJEaXNwbGF5TmFtZRI9Cht0'
    'cmlnZ2VyaW5nX2d1YXJkaWFuX25vZGVfaWQYAyABKAxSGHRyaWdnZXJpbmdHdWFyZGlhbk5vZG'
    'VJZBI4Chh0cmlnZ2VyaW5nX2d1YXJkaWFuX25hbWUYBCABKAlSFnRyaWdnZXJpbmdHdWFyZGlh'
    'bk5hbWUSLgoTcmVjb3ZlcnlfbWFpbGJveF9pZBgFIAEoDFIRcmVjb3ZlcnlNYWlsYm94SWQ=');

@$core.Deprecated('Use guardianRestoreResponseDescriptor instead')
const GuardianRestoreResponse$json = {
  '1': 'GuardianRestoreResponse',
  '2': [
    {'1': 'share_data', '3': 1, '4': 1, '5': 12, '10': 'shareData'},
    {'1': 'owner_node_id', '3': 2, '4': 1, '5': 12, '10': 'ownerNodeId'},
  ],
};

/// Descriptor for `GuardianRestoreResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List guardianRestoreResponseDescriptor = $convert.base64Decode(
    'ChdHdWFyZGlhblJlc3RvcmVSZXNwb25zZRIdCgpzaGFyZV9kYXRhGAEgASgMUglzaGFyZURhdG'
    'ESIgoNb3duZXJfbm9kZV9pZBgCIAEoDFILb3duZXJOb2RlSWQ=');

@$core.Deprecated('Use relayForwardDescriptor instead')
const RelayForward$json = {
  '1': 'RelayForward',
  '2': [
    {'1': 'relay_id', '3': 1, '4': 1, '5': 12, '10': 'relayId'},
    {'1': 'final_recipient_id', '3': 2, '4': 1, '5': 12, '10': 'finalRecipientId'},
    {'1': 'wrapped_envelope', '3': 3, '4': 1, '5': 12, '10': 'wrappedEnvelope'},
    {'1': 'hop_count', '3': 4, '4': 1, '5': 13, '10': 'hopCount'},
    {'1': 'max_hops', '3': 5, '4': 1, '5': 13, '10': 'maxHops'},
    {'1': 'visited_nodes', '3': 6, '4': 3, '5': 12, '10': 'visitedNodes'},
    {'1': 'origin_node_id', '3': 7, '4': 1, '5': 12, '10': 'originNodeId'},
    {'1': 'created_at_ms', '3': 8, '4': 1, '5': 4, '10': 'createdAtMs'},
    {'1': 'ttl', '3': 9, '4': 1, '5': 13, '10': 'ttl'},
  ],
};

/// Descriptor for `RelayForward`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List relayForwardDescriptor = $convert.base64Decode(
    'CgxSZWxheUZvcndhcmQSGQoIcmVsYXlfaWQYASABKAxSB3JlbGF5SWQSLAoSZmluYWxfcmVjaX'
    'BpZW50X2lkGAIgASgMUhBmaW5hbFJlY2lwaWVudElkEikKEHdyYXBwZWRfZW52ZWxvcGUYAyAB'
    'KAxSD3dyYXBwZWRFbnZlbG9wZRIbCglob3BfY291bnQYBCABKA1SCGhvcENvdW50EhkKCG1heF'
    '9ob3BzGAUgASgNUgdtYXhIb3BzEiMKDXZpc2l0ZWRfbm9kZXMYBiADKAxSDHZpc2l0ZWROb2Rl'
    'cxIkCg5vcmlnaW5fbm9kZV9pZBgHIAEoDFIMb3JpZ2luTm9kZUlkEiIKDWNyZWF0ZWRfYXRfbX'
    'MYCCABKARSC2NyZWF0ZWRBdE1zEhAKA3R0bBgJIAEoDVIDdHRs');

@$core.Deprecated('Use relayAckDescriptor instead')
const RelayAck$json = {
  '1': 'RelayAck',
  '2': [
    {'1': 'relay_id', '3': 1, '4': 1, '5': 12, '10': 'relayId'},
    {'1': 'delivered', '3': 2, '4': 1, '5': 8, '10': 'delivered'},
    {'1': 'relayed_by', '3': 3, '4': 1, '5': 12, '10': 'relayedBy'},
  ],
};

/// Descriptor for `RelayAck`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List relayAckDescriptor = $convert.base64Decode(
    'CghSZWxheUFjaxIZCghyZWxheV9pZBgBIAEoDFIHcmVsYXlJZBIcCglkZWxpdmVyZWQYAiABKA'
    'hSCWRlbGl2ZXJlZBIdCgpyZWxheWVkX2J5GAMgASgMUglyZWxheWVkQnk=');

@$core.Deprecated('Use peerReachabilityQueryDescriptor instead')
const PeerReachabilityQuery$json = {
  '1': 'PeerReachabilityQuery',
  '2': [
    {'1': 'target_node_id', '3': 1, '4': 1, '5': 12, '10': 'targetNodeId'},
    {'1': 'query_id', '3': 2, '4': 1, '5': 12, '10': 'queryId'},
    {'1': 'probe_ip', '3': 3, '4': 1, '5': 9, '10': 'probeIp'},
    {'1': 'probe_port', '3': 4, '4': 1, '5': 13, '10': 'probePort'},
  ],
};

/// Descriptor for `PeerReachabilityQuery`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List peerReachabilityQueryDescriptor = $convert.base64Decode(
    'ChVQZWVyUmVhY2hhYmlsaXR5UXVlcnkSJAoOdGFyZ2V0X25vZGVfaWQYASABKAxSDHRhcmdldE'
    '5vZGVJZBIZCghxdWVyeV9pZBgCIAEoDFIHcXVlcnlJZBIZCghwcm9iZV9pcBgDIAEoCVIHcHJv'
    'YmVJcBIdCgpwcm9iZV9wb3J0GAQgASgNUglwcm9iZVBvcnQ=');

@$core.Deprecated('Use peerReachabilityResponseDescriptor instead')
const PeerReachabilityResponse$json = {
  '1': 'PeerReachabilityResponse',
  '2': [
    {'1': 'target_node_id', '3': 1, '4': 1, '5': 12, '10': 'targetNodeId'},
    {'1': 'query_id', '3': 2, '4': 1, '5': 12, '10': 'queryId'},
    {'1': 'can_reach', '3': 3, '4': 1, '5': 8, '10': 'canReach'},
    {'1': 'last_seen_ms', '3': 4, '4': 1, '5': 4, '10': 'lastSeenMs'},
  ],
};

/// Descriptor for `PeerReachabilityResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List peerReachabilityResponseDescriptor = $convert.base64Decode(
    'ChhQZWVyUmVhY2hhYmlsaXR5UmVzcG9uc2USJAoOdGFyZ2V0X25vZGVfaWQYASABKAxSDHRhcm'
    'dldE5vZGVJZBIZCghxdWVyeV9pZBgCIAEoDFIHcXVlcnlJZBIbCgljYW5fcmVhY2gYAyABKAhS'
    'CGNhblJlYWNoEiAKDGxhc3Rfc2Vlbl9tcxgEIAEoBFIKbGFzdFNlZW5Ncw==');

@$core.Deprecated('Use peerStoreDescriptor instead')
const PeerStore$json = {
  '1': 'PeerStore',
  '2': [
    {'1': 'recipient_node_id', '3': 1, '4': 1, '5': 12, '10': 'recipientNodeId'},
    {'1': 'wrapped_envelope', '3': 2, '4': 1, '5': 12, '10': 'wrappedEnvelope'},
    {'1': 'store_id', '3': 3, '4': 1, '5': 12, '10': 'storeId'},
    {'1': 'ttl_ms', '3': 4, '4': 1, '5': 4, '10': 'ttlMs'},
  ],
};

/// Descriptor for `PeerStore`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List peerStoreDescriptor = $convert.base64Decode(
    'CglQZWVyU3RvcmUSKgoRcmVjaXBpZW50X25vZGVfaWQYASABKAxSD3JlY2lwaWVudE5vZGVJZB'
    'IpChB3cmFwcGVkX2VudmVsb3BlGAIgASgMUg93cmFwcGVkRW52ZWxvcGUSGQoIc3RvcmVfaWQY'
    'AyABKAxSB3N0b3JlSWQSFQoGdHRsX21zGAQgASgEUgV0dGxNcw==');

@$core.Deprecated('Use peerStoreAckDescriptor instead')
const PeerStoreAck$json = {
  '1': 'PeerStoreAck',
  '2': [
    {'1': 'store_id', '3': 1, '4': 1, '5': 12, '10': 'storeId'},
    {'1': 'accepted', '3': 2, '4': 1, '5': 8, '10': 'accepted'},
  ],
};

/// Descriptor for `PeerStoreAck`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List peerStoreAckDescriptor = $convert.base64Decode(
    'CgxQZWVyU3RvcmVBY2sSGQoIc3RvcmVfaWQYASABKAxSB3N0b3JlSWQSGgoIYWNjZXB0ZWQYAi'
    'ABKAhSCGFjY2VwdGVk');

@$core.Deprecated('Use peerRetrieveDescriptor instead')
const PeerRetrieve$json = {
  '1': 'PeerRetrieve',
  '2': [
    {'1': 'requester_node_id', '3': 1, '4': 1, '5': 12, '10': 'requesterNodeId'},
  ],
};

/// Descriptor for `PeerRetrieve`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List peerRetrieveDescriptor = $convert.base64Decode(
    'CgxQZWVyUmV0cmlldmUSKgoRcmVxdWVzdGVyX25vZGVfaWQYASABKAxSD3JlcXVlc3Rlck5vZG'
    'VJZA==');

@$core.Deprecated('Use peerRetrieveResponseDescriptor instead')
const PeerRetrieveResponse$json = {
  '1': 'PeerRetrieveResponse',
  '2': [
    {'1': 'stored_envelopes', '3': 1, '4': 3, '5': 12, '10': 'storedEnvelopes'},
    {'1': 'remaining', '3': 2, '4': 1, '5': 13, '10': 'remaining'},
  ],
};

/// Descriptor for `PeerRetrieveResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List peerRetrieveResponseDescriptor = $convert.base64Decode(
    'ChRQZWVyUmV0cmlldmVSZXNwb25zZRIpChBzdG9yZWRfZW52ZWxvcGVzGAEgAygMUg9zdG9yZW'
    'RFbnZlbG9wZXMSHAoJcmVtYWluaW5nGAIgASgNUglyZW1haW5pbmc=');

@$core.Deprecated('Use routeEntryProtoDescriptor instead')
const RouteEntryProto$json = {
  '1': 'RouteEntryProto',
  '2': [
    {'1': 'destination', '3': 1, '4': 1, '5': 12, '10': 'destination'},
    {'1': 'hop_count', '3': 2, '4': 1, '5': 5, '10': 'hopCount'},
    {'1': 'cost', '3': 3, '4': 1, '5': 5, '10': 'cost'},
    {'1': 'conn_type', '3': 4, '4': 1, '5': 14, '6': '.cleona.ConnectionTypeProto', '10': 'connType'},
    {'1': 'last_confirmed_ms', '3': 5, '4': 1, '5': 3, '10': 'lastConfirmedMs'},
    {'1': 'capabilities', '3': 6, '4': 1, '5': 13, '10': 'capabilities'},
  ],
};

/// Descriptor for `RouteEntryProto`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List routeEntryProtoDescriptor = $convert.base64Decode(
    'Cg9Sb3V0ZUVudHJ5UHJvdG8SIAoLZGVzdGluYXRpb24YASABKAxSC2Rlc3RpbmF0aW9uEhsKCW'
    'hvcF9jb3VudBgCIAEoBVIIaG9wQ291bnQSEgoEY29zdBgDIAEoBVIEY29zdBI4Cgljb25uX3R5'
    'cGUYBCABKA4yGy5jbGVvbmEuQ29ubmVjdGlvblR5cGVQcm90b1IIY29ublR5cGUSKgoRbGFzdF'
    '9jb25maXJtZWRfbXMYBSABKANSD2xhc3RDb25maXJtZWRNcxIiCgxjYXBhYmlsaXRpZXMYBiAB'
    'KA1SDGNhcGFiaWxpdGllcw==');

@$core.Deprecated('Use routeUpdateMsgDescriptor instead')
const RouteUpdateMsg$json = {
  '1': 'RouteUpdateMsg',
  '2': [
    {'1': 'routes', '3': 1, '4': 3, '5': 11, '6': '.cleona.RouteEntryProto', '10': 'routes'},
  ],
};

/// Descriptor for `RouteUpdateMsg`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List routeUpdateMsgDescriptor = $convert.base64Decode(
    'Cg5Sb3V0ZVVwZGF0ZU1zZxIvCgZyb3V0ZXMYASADKAsyFy5jbGVvbmEuUm91dGVFbnRyeVByb3'
    'RvUgZyb3V0ZXM=');

@$core.Deprecated('Use holePunchRequestDescriptor instead')
const HolePunchRequest$json = {
  '1': 'HolePunchRequest',
  '2': [
    {'1': 'target_node_id', '3': 1, '4': 1, '5': 12, '10': 'targetNodeId'},
    {'1': 'my_public_ip', '3': 2, '4': 1, '5': 9, '10': 'myPublicIp'},
    {'1': 'my_public_port', '3': 3, '4': 1, '5': 5, '10': 'myPublicPort'},
    {'1': 'request_id', '3': 4, '4': 1, '5': 12, '10': 'requestId'},
  ],
};

/// Descriptor for `HolePunchRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List holePunchRequestDescriptor = $convert.base64Decode(
    'ChBIb2xlUHVuY2hSZXF1ZXN0EiQKDnRhcmdldF9ub2RlX2lkGAEgASgMUgx0YXJnZXROb2RlSW'
    'QSIAoMbXlfcHVibGljX2lwGAIgASgJUgpteVB1YmxpY0lwEiQKDm15X3B1YmxpY19wb3J0GAMg'
    'ASgFUgxteVB1YmxpY1BvcnQSHQoKcmVxdWVzdF9pZBgEIAEoDFIJcmVxdWVzdElk');

@$core.Deprecated('Use holePunchNotifyDescriptor instead')
const HolePunchNotify$json = {
  '1': 'HolePunchNotify',
  '2': [
    {'1': 'requester_node_id', '3': 1, '4': 1, '5': 12, '10': 'requesterNodeId'},
    {'1': 'requester_ip', '3': 2, '4': 1, '5': 9, '10': 'requesterIp'},
    {'1': 'requester_port', '3': 3, '4': 1, '5': 5, '10': 'requesterPort'},
    {'1': 'request_id', '3': 4, '4': 1, '5': 12, '10': 'requestId'},
  ],
};

/// Descriptor for `HolePunchNotify`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List holePunchNotifyDescriptor = $convert.base64Decode(
    'Cg9Ib2xlUHVuY2hOb3RpZnkSKgoRcmVxdWVzdGVyX25vZGVfaWQYASABKAxSD3JlcXVlc3Rlck'
    '5vZGVJZBIhCgxyZXF1ZXN0ZXJfaXAYAiABKAlSC3JlcXVlc3RlcklwEiUKDnJlcXVlc3Rlcl9w'
    'b3J0GAMgASgFUg1yZXF1ZXN0ZXJQb3J0Eh0KCnJlcXVlc3RfaWQYBCABKAxSCXJlcXVlc3RJZA'
    '==');

@$core.Deprecated('Use holePunchPingDescriptor instead')
const HolePunchPing$json = {
  '1': 'HolePunchPing',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 12, '10': 'requestId'},
    {'1': 'sender_node_id', '3': 2, '4': 1, '5': 12, '10': 'senderNodeId'},
    {'1': 'timestamp_ms', '3': 3, '4': 1, '5': 3, '10': 'timestampMs'},
  ],
};

/// Descriptor for `HolePunchPing`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List holePunchPingDescriptor = $convert.base64Decode(
    'Cg1Ib2xlUHVuY2hQaW5nEh0KCnJlcXVlc3RfaWQYASABKAxSCXJlcXVlc3RJZBIkCg5zZW5kZX'
    'Jfbm9kZV9pZBgCIAEoDFIMc2VuZGVyTm9kZUlkEiEKDHRpbWVzdGFtcF9tcxgDIAEoA1ILdGlt'
    'ZXN0YW1wTXM=');

@$core.Deprecated('Use holePunchPongDescriptor instead')
const HolePunchPong$json = {
  '1': 'HolePunchPong',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 12, '10': 'requestId'},
    {'1': 'sender_node_id', '3': 2, '4': 1, '5': 12, '10': 'senderNodeId'},
    {'1': 'ping_timestamp_ms', '3': 3, '4': 1, '5': 3, '10': 'pingTimestampMs'},
  ],
};

/// Descriptor for `HolePunchPong`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List holePunchPongDescriptor = $convert.base64Decode(
    'Cg1Ib2xlUHVuY2hQb25nEh0KCnJlcXVlc3RfaWQYASABKAxSCXJlcXVlc3RJZBIkCg5zZW5kZX'
    'Jfbm9kZV9pZBgCIAEoDFIMc2VuZGVyTm9kZUlkEioKEXBpbmdfdGltZXN0YW1wX21zGAMgASgD'
    'Ug9waW5nVGltZXN0YW1wTXM=');

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

@$core.Deprecated('Use groupCallKeyRotateDescriptor instead')
const GroupCallKeyRotate$json = {
  '1': 'GroupCallKeyRotate',
  '2': [
    {'1': 'call_id', '3': 1, '4': 1, '5': 12, '10': 'callId'},
    {'1': 'new_call_key', '3': 2, '4': 1, '5': 12, '10': 'newCallKey'},
    {'1': 'key_version', '3': 3, '4': 1, '5': 13, '10': 'keyVersion'},
  ],
};

/// Descriptor for `GroupCallKeyRotate`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List groupCallKeyRotateDescriptor = $convert.base64Decode(
    'ChJHcm91cENhbGxLZXlSb3RhdGUSFwoHY2FsbF9pZBgBIAEoDFIGY2FsbElkEiAKDG5ld19jYW'
    'xsX2tleRgCIAEoDFIKbmV3Q2FsbEtleRIfCgtrZXlfdmVyc2lvbhgDIAEoDVIKa2V5VmVyc2lv'
    'bg==');

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
  ],
};

/// Descriptor for `KeyRotationBroadcast`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List keyRotationBroadcastDescriptor = $convert.base64Decode(
    'ChRLZXlSb3RhdGlvbkJyb2FkY2FzdBIkCg5uZXdfZWQyNTUxOV9waxgBIAEoDFIMbmV3RWQyNT'
    'UxOVBrEiEKDW5ld19tbF9kc2FfcGsYAiABKAxSCm5ld01sRHNhUGsSIgoNbmV3X3gyNTUxOV9w'
    'axgDIAEoDFILbmV3WDI1NTE5UGsSIQoNbmV3X21sX2tlbV9waxgEIAEoDFIKbmV3TWxLZW1Qax'
    'IyChVvbGRfc2lnbmF0dXJlX2VkMjU1MTkYBSABKAxSE29sZFNpZ25hdHVyZUVkMjU1MTkSMgoV'
    'bmV3X3NpZ25hdHVyZV9lZDI1NTE5GAYgASgMUhNuZXdTaWduYXR1cmVFZDI1NTE5');

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
    'ZXJz');

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

@$core.Deprecated('Use authManifestProtoDescriptor instead')
const AuthManifestProto$json = {
  '1': 'AuthManifestProto',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 12, '10': 'userId'},
    {'1': 'authorized_device_node_ids', '3': 2, '4': 3, '5': 12, '10': 'authorizedDeviceNodeIds'},
    {'1': 'ttl_seconds', '3': 3, '4': 1, '5': 5, '10': 'ttlSeconds'},
    {'1': 'sequence_number', '3': 4, '4': 1, '5': 3, '10': 'sequenceNumber'},
    {'1': 'published_at_ms', '3': 5, '4': 1, '5': 3, '10': 'publishedAtMs'},
    {'1': 'ed25519_sig', '3': 6, '4': 1, '5': 12, '10': 'ed25519Sig'},
    {'1': 'ml_dsa_sig', '3': 7, '4': 1, '5': 12, '10': 'mlDsaSig'},
  ],
};

/// Descriptor for `AuthManifestProto`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List authManifestProtoDescriptor = $convert.base64Decode(
    'ChFBdXRoTWFuaWZlc3RQcm90bxIXCgd1c2VyX2lkGAEgASgMUgZ1c2VySWQSOwoaYXV0aG9yaX'
    'plZF9kZXZpY2Vfbm9kZV9pZHMYAiADKAxSF2F1dGhvcml6ZWREZXZpY2VOb2RlSWRzEh8KC3R0'
    'bF9zZWNvbmRzGAMgASgFUgp0dGxTZWNvbmRzEicKD3NlcXVlbmNlX251bWJlchgEIAEoA1IOc2'
    'VxdWVuY2VOdW1iZXISJgoPcHVibGlzaGVkX2F0X21zGAUgASgDUg1wdWJsaXNoZWRBdE1zEh8K'
    'C2VkMjU1MTlfc2lnGAYgASgMUgplZDI1NTE5U2lnEhwKCm1sX2RzYV9zaWcYByABKAxSCG1sRH'
    'NhU2ln');

@$core.Deprecated('Use livenessRecordProtoDescriptor instead')
const LivenessRecordProto$json = {
  '1': 'LivenessRecordProto',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 12, '10': 'userId'},
    {'1': 'device_node_id', '3': 2, '4': 1, '5': 12, '10': 'deviceNodeId'},
    {'1': 'addresses', '3': 3, '4': 3, '5': 11, '6': '.cleona.PeerAddressProto', '10': 'addresses'},
    {'1': 'ttl_seconds', '3': 4, '4': 1, '5': 5, '10': 'ttlSeconds'},
    {'1': 'sequence_number', '3': 5, '4': 1, '5': 3, '10': 'sequenceNumber'},
    {'1': 'published_at_ms', '3': 6, '4': 1, '5': 3, '10': 'publishedAtMs'},
    {'1': 'ed25519_sig', '3': 7, '4': 1, '5': 12, '10': 'ed25519Sig'},
  ],
};

/// Descriptor for `LivenessRecordProto`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List livenessRecordProtoDescriptor = $convert.base64Decode(
    'ChNMaXZlbmVzc1JlY29yZFByb3RvEhcKB3VzZXJfaWQYASABKAxSBnVzZXJJZBIkCg5kZXZpY2'
    'Vfbm9kZV9pZBgCIAEoDFIMZGV2aWNlTm9kZUlkEjYKCWFkZHJlc3NlcxgDIAMoCzIYLmNsZW9u'
    'YS5QZWVyQWRkcmVzc1Byb3RvUglhZGRyZXNzZXMSHwoLdHRsX3NlY29uZHMYBCABKAVSCnR0bF'
    'NlY29uZHMSJwoPc2VxdWVuY2VfbnVtYmVyGAUgASgDUg5zZXF1ZW5jZU51bWJlchImCg9wdWJs'
    'aXNoZWRfYXRfbXMYBiABKANSDXB1Ymxpc2hlZEF0TXMSHwoLZWQyNTUxOV9zaWcYByABKAxSCm'
    'VkMjU1MTlTaWc=');

@$core.Deprecated('Use identityAuthRetrieveRequestDescriptor instead')
const IdentityAuthRetrieveRequest$json = {
  '1': 'IdentityAuthRetrieveRequest',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 12, '10': 'userId'},
    {'1': 'minimum_seq', '3': 2, '4': 1, '5': 3, '10': 'minimumSeq'},
  ],
};

/// Descriptor for `IdentityAuthRetrieveRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List identityAuthRetrieveRequestDescriptor = $convert.base64Decode(
    'ChtJZGVudGl0eUF1dGhSZXRyaWV2ZVJlcXVlc3QSFwoHdXNlcl9pZBgBIAEoDFIGdXNlcklkEh'
    '8KC21pbmltdW1fc2VxGAIgASgDUgptaW5pbXVtU2Vx');

@$core.Deprecated('Use identityLiveRetrieveRequestDescriptor instead')
const IdentityLiveRetrieveRequest$json = {
  '1': 'IdentityLiveRetrieveRequest',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 12, '10': 'userId'},
    {'1': 'device_node_id', '3': 2, '4': 1, '5': 12, '10': 'deviceNodeId'},
  ],
};

/// Descriptor for `IdentityLiveRetrieveRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List identityLiveRetrieveRequestDescriptor = $convert.base64Decode(
    'ChtJZGVudGl0eUxpdmVSZXRyaWV2ZVJlcXVlc3QSFwoHdXNlcl9pZBgBIAEoDFIGdXNlcklkEi'
    'QKDmRldmljZV9ub2RlX2lkGAIgASgMUgxkZXZpY2VOb2RlSWQ=');


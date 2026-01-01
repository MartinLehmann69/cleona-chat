//
//  Generated code. Do not modify.
//  source: transport.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

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

@$core.Deprecated('Use payloadTypeDescriptor instead')
const PayloadType$json = {
  '1': 'PayloadType',
  '2': [
    {'1': 'PAYLOAD_APPLICATION_FRAME', '2': 0},
    {'1': 'PAYLOAD_ONION_LAYER', '2': 1},
  ],
  '4': [
    {'1': 2, '2': 2},
    {'1': 3, '2': 3},
  ],
  '5': ['PAYLOAD_INFRASTRUCTURE_FRAME', 'PAYLOAD_BOOTSTRAP_INFRASTRUCTURE_FRAME'],
};

/// Descriptor for `PayloadType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List payloadTypeDescriptor = $convert.base64Decode(
    'CgtQYXlsb2FkVHlwZRIdChlQQVlMT0FEX0FQUExJQ0FUSU9OX0ZSQU1FEAASFwoTUEFZTE9BRF'
    '9PTklPTl9MQVlFUhABIgQIAhACIgQIAxADKhxQQVlMT0FEX0lORlJBU1RSVUNUVVJFX0ZSQU1F'
    'KiZQQVlMT0FEX0JPT1RTVFJBUF9JTkZSQVNUUlVDVFVSRV9GUkFNRQ==');

@$core.Deprecated('Use messageTypeDescriptor instead')
const MessageType$json = {
  '1': 'MessageType',
  '2': [
    {'1': 'MT_TEXT', '2': 0},
    {'1': 'MT_MEDIA_INLINE', '2': 1},
    {'1': 'MT_MEDIA_ANNOUNCE', '2': 2},
    {'1': 'MT_MEDIA_REQUEST', '2': 3},
    {'1': 'MT_MEDIA_CHUNK', '2': 4},
    {'1': 'MT_MEDIA_COMPLETE', '2': 5},
    {'1': 'MT_MEDIA_REJECT', '2': 6},
    {'1': 'MT_REACTION', '2': 7},
    {'1': 'MT_REPLY', '2': 8},
    {'1': 'MT_EDIT', '2': 9},
    {'1': 'MT_DELETE', '2': 10},
    {'1': 'MT_MEDIA_STREAM_REQUEST', '2': 11},
    {'1': 'MT_MEDIA_STREAM_OFFER', '2': 12},
    {'1': 'MT_MEDIA_HOLDERS', '2': 13},
    {'1': 'MT_MEDIA_ABORT', '2': 14},
    {'1': 'MT_TYPING_INDICATOR', '2': 15},
    {'1': 'MT_READ_RECEIPT', '2': 16},
    {'1': 'MT_DELIVERY_RECEIPT', '2': 17},
    {'1': 'MT_CATCH_UP', '2': 18},
    {'1': 'MT_VOICE_MESSAGE', '2': 22},
    {'1': 'MT_IDENTITY_DELETED', '2': 32},
    {'1': 'MT_PROFILE_UPDATE', '2': 33},
    {'1': 'MT_KEY_ROTATION_BROADCAST', '2': 34},
    {'1': 'MT_KEY_ROTATION_ACK', '2': 38},
    {'1': 'MT_CONTACT_REQUEST', '2': 40},
    {'1': 'MT_CONTACT_REQUEST_RESPONSE', '2': 41},
    {'1': 'MT_GROUP_CREATE', '2': 50},
    {'1': 'MT_GROUP_INVITE', '2': 51},
    {'1': 'MT_GROUP_LEAVE', '2': 52},
    {'1': 'MT_GROUP_KEY_UPDATE', '2': 53},
    {'1': 'MT_GROUP_MEMBERSHIP_RESYNC_REQUEST', '2': 54},
    {'1': 'MT_GROUP_JOIN', '2': 55},
    {'1': 'MT_CHANNEL_CREATE', '2': 60},
    {'1': 'MT_CHANNEL_POST', '2': 61},
    {'1': 'MT_CHANNEL_INVITE', '2': 62},
    {'1': 'MT_CHANNEL_LEAVE', '2': 63},
    {'1': 'MT_CHANNEL_ROLE_UPDATE', '2': 64},
    {'1': 'MT_CHANNEL_BAD_BADGE_REPORT', '2': 65},
    {'1': 'MT_CHANNEL_JURY_VOTE', '2': 66},
    {'1': 'MT_CHANNEL_MOD_DECISION', '2': 67},
    {'1': 'MT_CHANNEL_SUBSCRIBE_PROBE', '2': 68},
    {'1': 'MT_CALL_MISSED', '2': 69},
    {'1': 'MT_CALL_INVITE', '2': 70},
    {'1': 'MT_CALL_ANSWER', '2': 71},
    {'1': 'MT_CALL_REJECT', '2': 72},
    {'1': 'MT_CALL_HANGUP', '2': 73},
    {'1': 'MT_ICE_CANDIDATE', '2': 74},
    {'1': 'MT_CALL_REJOIN', '2': 75},
    {'1': 'MT_CALL_AUDIO', '2': 76},
    {'1': 'MT_CALL_VIDEO', '2': 77},
    {'1': 'MT_CALL_GROUP_AUDIO', '2': 78},
    {'1': 'MT_CALL_GROUP_VIDEO', '2': 79},
    {'1': 'MT_CALL_GROUP_LEAVE', '2': 80},
    {'1': 'MT_CALL_RTT_PING', '2': 82},
    {'1': 'MT_CALL_RTT_PONG', '2': 83},
    {'1': 'MT_CALL_TREE_UPDATE', '2': 84},
    {'1': 'MT_CALL_KEYFRAME_REQUEST', '2': 85},
    {'1': 'MT_CALL_GROUP_SENDER_KEY', '2': 86},
    {'1': 'MT_CALL_MEDIA_STATE', '2': 87},
    {'1': 'MT_CALL_CANCEL_OTHERS', '2': 88},
    {'1': 'MT_CALL_RING_ACK', '2': 89},
    {'1': 'MT_CHANNEL_INDEX_EXCHANGE', '2': 90},
    {'1': 'MT_CHANNEL_JOIN_REQUEST', '2': 91},
    {'1': 'MT_CHANNEL_REPORT', '2': 92},
    {'1': 'MT_CHANNEL_REACTION_TOTALS', '2': 93},
    {'1': 'MT_CHANNEL_REACTION_HANDOVER', '2': 94},
    {'1': 'MT_CHANNEL_MEMBERS_CHANGE', '2': 95},
    {'1': 'MT_CAPABILITY_NOTICE', '2': 96},
    {'1': 'MT_SHARED_KEY', '2': 97},
    {'1': 'MT_SHARED_KEY_AUTHOR', '2': 98},
    {'1': 'MT_GROUP_MEMBERS_CHANGE', '2': 99},
    {'1': 'MT_DHT_PING', '2': 110},
    {'1': 'MT_DHT_PONG', '2': 111},
    {'1': 'MT_DHT_FIND_NODE', '2': 112},
    {'1': 'MT_DHT_FIND_NODE_RESPONSE', '2': 113},
    {'1': 'MT_DHT_STORE', '2': 114},
    {'1': 'MT_DHT_STORE_RESPONSE', '2': 115},
    {'1': 'MT_DHT_FIND_VALUE', '2': 116},
    {'1': 'MT_DHT_FIND_VALUE_RESPONSE', '2': 117},
    {'1': 'MT_FRAGMENT_STORE', '2': 120},
    {'1': 'MT_FRAGMENT_STORE_ACK', '2': 121},
    {'1': 'MT_FRAGMENT_RETRIEVE', '2': 122},
    {'1': 'MT_FRAGMENT_RETRIEVE_RESPONSE', '2': 123},
    {'1': 'MT_FRAGMENT_DELETE', '2': 124},
    {'1': 'MT_CHAT_CONFIG_UPDATE', '2': 140},
    {'1': 'MT_CHAT_CONFIG_RESPONSE', '2': 141},
    {'1': 'MT_IDENTITY_AUTH_PUBLISH', '2': 170},
    {'1': 'MT_IDENTITY_AUTH_RETRIEVE', '2': 171},
    {'1': 'MT_IDENTITY_AUTH_RESPONSE', '2': 172},
    {'1': 'MT_IDENTITY_LIVE_PUBLISH', '2': 173},
    {'1': 'MT_IDENTITY_LIVE_RETRIEVE', '2': 174},
    {'1': 'MT_IDENTITY_LIVE_RESPONSE', '2': 175},
    {'1': 'MT_TWIN_SYNC', '2': 180},
    {'1': 'MT_DEVICE_REVOCATION', '2': 183},
    {'1': 'MT_ROTATION_REJECTION_ALERT', '2': 184},
    {'1': 'MT_DEVICE_SET_ANNOUNCE', '2': 185},
    {'1': 'MT_CALENDAR_INVITE', '2': 190},
    {'1': 'MT_CALENDAR_RSVP', '2': 191},
    {'1': 'MT_CALENDAR_UPDATE', '2': 192},
    {'1': 'MT_CALENDAR_DELETE', '2': 193},
    {'1': 'MT_FREE_BUSY_REQUEST', '2': 194},
    {'1': 'MT_FREE_BUSY_RESPONSE', '2': 195},
    {'1': 'MT_POLL_CREATE', '2': 200},
    {'1': 'MT_POLL_VOTE', '2': 201},
    {'1': 'MT_POLL_VOTE_ANONYMOUS', '2': 202},
    {'1': 'MT_POLL_UPDATE', '2': 203},
    {'1': 'MT_POLL_SNAPSHOT', '2': 204},
    {'1': 'MT_POLL_REVOKE', '2': 205},
    {'1': 'MT_WHITEBOARD_STROKE', '2': 210},
    {'1': 'MT_WHITEBOARD_PAGE', '2': 211},
    {'1': 'MT_FILE_EXCHANGE', '2': 212},
    {'1': 'MT_CLIPBOARD_EXCHANGE', '2': 213},
    {'1': 'MT_SCREEN_SHARE_FRAME', '2': 214},
    {'1': 'MT_CALL_CHAT', '2': 215},
    {'1': 'MT_REMOTE_CONTROL_INPUT', '2': 216},
  ],
  '4': [
    {'1': 30, '2': 30},
    {'1': 31, '2': 31},
    {'1': 35, '2': 35},
    {'1': 36, '2': 36},
    {'1': 37, '2': 37},
    {'1': 81, '2': 81},
    {'1': 100, '2': 100},
    {'1': 101, '2': 101},
    {'1': 102, '2': 102},
    {'1': 103, '2': 103},
    {'1': 104, '2': 104},
    {'1': 130, '2': 130},
    {'1': 131, '2': 131},
    {'1': 132, '2': 132},
    {'1': 133, '2': 133},
    {'1': 150, '2': 150},
    {'1': 151, '2': 151},
    {'1': 152, '2': 152},
    {'1': 153, '2': 153},
    {'1': 154, '2': 154},
    {'1': 160, '2': 160},
    {'1': 161, '2': 161},
    {'1': 162, '2': 162},
    {'1': 163, '2': 163},
    {'1': 176, '2': 176},
    {'1': 177, '2': 177},
    {'1': 178, '2': 178},
    {'1': 181, '2': 181},
    {'1': 182, '2': 182},
    {'1': 220, '2': 220},
    {'1': 221, '2': 221},
    {'1': 222, '2': 222},
    {'1': 223, '2': 223},
    {'1': 224, '2': 224},
    {'1': 225, '2': 225},
    {'1': 226, '2': 226},
    {'1': 230, '2': 230},
    {'1': 231, '2': 231},
    {'1': 232, '2': 232},
    {'1': 233, '2': 233},
  ],
  '5': ['MT_RESTORE_BROADCAST', 'MT_RESTORE_RESPONSE', 'MT_GUARDIAN_SHARE_STORE', 'MT_GUARDIAN_RESTORE_REQUEST', 'MT_GUARDIAN_RESTORE_RESPONSE', 'MT_PEER_LIST_PUSH', 'MT_PEER_LIST_SUMMARY', 'MT_PEER_LIST_WANT', 'MT_PEER_KEY_REQUEST', 'MT_PEER_KEY_RESPONSE', 'MT_PEER_STORE', 'MT_PEER_STORE_ACK', 'MT_PEER_RETRIEVE', 'MT_PEER_RETRIEVE_RESPONSE', 'MT_ROUTE_UPDATE', 'MT_REACHABILITY_QUERY', 'MT_REACHABILITY_RESPONSE', 'MT_RELAY_FORWARD', 'MT_RELAY_ACK', 'MT_HOLE_PUNCH_REQUEST', 'MT_HOLE_PUNCH_NOTIFY', 'MT_HOLE_PUNCH_PING', 'MT_HOLE_PUNCH_PONG', 'MT_IDENTITY_KEM_PUBLISH', 'MT_IDENTITY_KEM_RETRIEVE', 'MT_IDENTITY_KEM_RESPONSE', 'MT_DEVICE_PAIR_REQUEST', 'MT_DEVICE_PAIR_APPROVE', 'MT_DEVICE_KEM_REQUEST', 'MT_DEVICE_KEM_OFFER', 'MT_FIRST_CR_STORE', 'MT_FIRST_CR_STORE_ACK', 'MT_FIRST_CR_DELIVER', 'MT_POLL_ANON_SUBMIT', 'MT_POLL_ANON_SUBMIT_ACK', 'MT_SYSCHAN_DIGEST', 'MT_SYSCHAN_SUMMARY', 'MT_SYSCHAN_WANT', 'MT_SYSCHAN_PUSH'],
};

/// Descriptor for `MessageType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List messageTypeDescriptor = $convert.base64Decode(
    'CgtNZXNzYWdlVHlwZRILCgdNVF9URVhUEAASEwoPTVRfTUVESUFfSU5MSU5FEAESFQoRTVRfTU'
    'VESUFfQU5OT1VOQ0UQAhIUChBNVF9NRURJQV9SRVFVRVNUEAMSEgoOTVRfTUVESUFfQ0hVTksQ'
    'BBIVChFNVF9NRURJQV9DT01QTEVURRAFEhMKD01UX01FRElBX1JFSkVDVBAGEg8KC01UX1JFQU'
    'NUSU9OEAcSDAoITVRfUkVQTFkQCBILCgdNVF9FRElUEAkSDQoJTVRfREVMRVRFEAoSGwoXTVRf'
    'TUVESUFfU1RSRUFNX1JFUVVFU1QQCxIZChVNVF9NRURJQV9TVFJFQU1fT0ZGRVIQDBIUChBNVF'
    '9NRURJQV9IT0xERVJTEA0SEgoOTVRfTUVESUFfQUJPUlQQDhIXChNNVF9UWVBJTkdfSU5ESUNB'
    'VE9SEA8SEwoPTVRfUkVBRF9SRUNFSVBUEBASFwoTTVRfREVMSVZFUllfUkVDRUlQVBAREg8KC0'
    '1UX0NBVENIX1VQEBISFAoQTVRfVk9JQ0VfTUVTU0FHRRAWEhcKE01UX0lERU5USVRZX0RFTEVU'
    'RUQQIBIVChFNVF9QUk9GSUxFX1VQREFURRAhEh0KGU1UX0tFWV9ST1RBVElPTl9CUk9BRENBU1'
    'QQIhIXChNNVF9LRVlfUk9UQVRJT05fQUNLECYSFgoSTVRfQ09OVEFDVF9SRVFVRVNUECgSHwob'
    'TVRfQ09OVEFDVF9SRVFVRVNUX1JFU1BPTlNFECkSEwoPTVRfR1JPVVBfQ1JFQVRFEDISEwoPTV'
    'RfR1JPVVBfSU5WSVRFEDMSEgoOTVRfR1JPVVBfTEVBVkUQNBIXChNNVF9HUk9VUF9LRVlfVVBE'
    'QVRFEDUSJgoiTVRfR1JPVVBfTUVNQkVSU0hJUF9SRVNZTkNfUkVRVUVTVBA2EhEKDU1UX0dST1'
    'VQX0pPSU4QNxIVChFNVF9DSEFOTkVMX0NSRUFURRA8EhMKD01UX0NIQU5ORUxfUE9TVBA9EhUK'
    'EU1UX0NIQU5ORUxfSU5WSVRFED4SFAoQTVRfQ0hBTk5FTF9MRUFWRRA/EhoKFk1UX0NIQU5ORU'
    'xfUk9MRV9VUERBVEUQQBIfChtNVF9DSEFOTkVMX0JBRF9CQURHRV9SRVBPUlQQQRIYChRNVF9D'
    'SEFOTkVMX0pVUllfVk9URRBCEhsKF01UX0NIQU5ORUxfTU9EX0RFQ0lTSU9OEEMSHgoaTVRfQ0'
    'hBTk5FTF9TVUJTQ1JJQkVfUFJPQkUQRBISCg5NVF9DQUxMX01JU1NFRBBFEhIKDk1UX0NBTExf'
    'SU5WSVRFEEYSEgoOTVRfQ0FMTF9BTlNXRVIQRxISCg5NVF9DQUxMX1JFSkVDVBBIEhIKDk1UX0'
    'NBTExfSEFOR1VQEEkSFAoQTVRfSUNFX0NBTkRJREFURRBKEhIKDk1UX0NBTExfUkVKT0lOEEsS'
    'EQoNTVRfQ0FMTF9BVURJTxBMEhEKDU1UX0NBTExfVklERU8QTRIXChNNVF9DQUxMX0dST1VQX0'
    'FVRElPEE4SFwoTTVRfQ0FMTF9HUk9VUF9WSURFTxBPEhcKE01UX0NBTExfR1JPVVBfTEVBVkUQ'
    'UBIUChBNVF9DQUxMX1JUVF9QSU5HEFISFAoQTVRfQ0FMTF9SVFRfUE9ORxBTEhcKE01UX0NBTE'
    'xfVFJFRV9VUERBVEUQVBIcChhNVF9DQUxMX0tFWUZSQU1FX1JFUVVFU1QQVRIcChhNVF9DQUxM'
    'X0dST1VQX1NFTkRFUl9LRVkQVhIXChNNVF9DQUxMX01FRElBX1NUQVRFEFcSGQoVTVRfQ0FMTF'
    '9DQU5DRUxfT1RIRVJTEFgSFAoQTVRfQ0FMTF9SSU5HX0FDSxBZEh0KGU1UX0NIQU5ORUxfSU5E'
    'RVhfRVhDSEFOR0UQWhIbChdNVF9DSEFOTkVMX0pPSU5fUkVRVUVTVBBbEhUKEU1UX0NIQU5ORU'
    'xfUkVQT1JUEFwSHgoaTVRfQ0hBTk5FTF9SRUFDVElPTl9UT1RBTFMQXRIgChxNVF9DSEFOTkVM'
    'X1JFQUNUSU9OX0hBTkRPVkVSEF4SHQoZTVRfQ0hBTk5FTF9NRU1CRVJTX0NIQU5HRRBfEhgKFE'
    '1UX0NBUEFCSUxJVFlfTk9USUNFEGASEQoNTVRfU0hBUkVEX0tFWRBhEhgKFE1UX1NIQVJFRF9L'
    'RVlfQVVUSE9SEGISGwoXTVRfR1JPVVBfTUVNQkVSU19DSEFOR0UQYxIPCgtNVF9ESFRfUElORx'
    'BuEg8KC01UX0RIVF9QT05HEG8SFAoQTVRfREhUX0ZJTkRfTk9ERRBwEh0KGU1UX0RIVF9GSU5E'
    'X05PREVfUkVTUE9OU0UQcRIQCgxNVF9ESFRfU1RPUkUQchIZChVNVF9ESFRfU1RPUkVfUkVTUE'
    '9OU0UQcxIVChFNVF9ESFRfRklORF9WQUxVRRB0Eh4KGk1UX0RIVF9GSU5EX1ZBTFVFX1JFU1BP'
    'TlNFEHUSFQoRTVRfRlJBR01FTlRfU1RPUkUQeBIZChVNVF9GUkFHTUVOVF9TVE9SRV9BQ0sQeR'
    'IYChRNVF9GUkFHTUVOVF9SRVRSSUVWRRB6EiEKHU1UX0ZSQUdNRU5UX1JFVFJJRVZFX1JFU1BP'
    'TlNFEHsSFgoSTVRfRlJBR01FTlRfREVMRVRFEHwSGgoVTVRfQ0hBVF9DT05GSUdfVVBEQVRFEI'
    'wBEhwKF01UX0NIQVRfQ09ORklHX1JFU1BPTlNFEI0BEh0KGE1UX0lERU5USVRZX0FVVEhfUFVC'
    'TElTSBCqARIeChlNVF9JREVOVElUWV9BVVRIX1JFVFJJRVZFEKsBEh4KGU1UX0lERU5USVRZX0'
    'FVVEhfUkVTUE9OU0UQrAESHQoYTVRfSURFTlRJVFlfTElWRV9QVUJMSVNIEK0BEh4KGU1UX0lE'
    'RU5USVRZX0xJVkVfUkVUUklFVkUQrgESHgoZTVRfSURFTlRJVFlfTElWRV9SRVNQT05TRRCvAR'
    'IRCgxNVF9UV0lOX1NZTkMQtAESGQoUTVRfREVWSUNFX1JFVk9DQVRJT04QtwESIAobTVRfUk9U'
    'QVRJT05fUkVKRUNUSU9OX0FMRVJUELgBEhsKFk1UX0RFVklDRV9TRVRfQU5OT1VOQ0UQuQESFw'
    'oSTVRfQ0FMRU5EQVJfSU5WSVRFEL4BEhUKEE1UX0NBTEVOREFSX1JTVlAQvwESFwoSTVRfQ0FM'
    'RU5EQVJfVVBEQVRFEMABEhcKEk1UX0NBTEVOREFSX0RFTEVURRDBARIZChRNVF9GUkVFX0JVU1'
    'lfUkVRVUVTVBDCARIaChVNVF9GUkVFX0JVU1lfUkVTUE9OU0UQwwESEwoOTVRfUE9MTF9DUkVB'
    'VEUQyAESEQoMTVRfUE9MTF9WT1RFEMkBEhsKFk1UX1BPTExfVk9URV9BTk9OWU1PVVMQygESEw'
    'oOTVRfUE9MTF9VUERBVEUQywESFQoQTVRfUE9MTF9TTkFQU0hPVBDMARITCg5NVF9QT0xMX1JF'
    'Vk9LRRDNARIZChRNVF9XSElURUJPQVJEX1NUUk9LRRDSARIXChJNVF9XSElURUJPQVJEX1BBR0'
    'UQ0wESFQoQTVRfRklMRV9FWENIQU5HRRDUARIaChVNVF9DTElQQk9BUkRfRVhDSEFOR0UQ1QES'
    'GgoVTVRfU0NSRUVOX1NIQVJFX0ZSQU1FENYBEhEKDE1UX0NBTExfQ0hBVBDXARIcChdNVF9SRU'
    '1PVEVfQ09OVFJPTF9JTlBVVBDYASIECB4QHiIECB8QHyIECCMQIyIECCQQJCIECCUQJSIECFEQ'
    'USIECGQQZCIECGUQZSIECGYQZiIECGcQZyIECGgQaCIGCIIBEIIBIgYIgwEQgwEiBgiEARCEAS'
    'IGCIUBEIUBIgYIlgEQlgEiBgiXARCXASIGCJgBEJgBIgYImQEQmQEiBgiaARCaASIGCKABEKAB'
    'IgYIoQEQoQEiBgiiARCiASIGCKMBEKMBIgYIsAEQsAEiBgixARCxASIGCLIBELIBIgYItQEQtQ'
    'EiBgi2ARC2ASIGCNwBENwBIgYI3QEQ3QEiBgjeARDeASIGCN8BEN8BIgYI4AEQ4AEiBgjhARDh'
    'ASIGCOIBEOIBIgYI5gEQ5gEiBgjnARDnASIGCOgBEOgBIgYI6QEQ6QEqFE1UX1JFU1RPUkVfQl'
    'JPQURDQVNUKhNNVF9SRVNUT1JFX1JFU1BPTlNFKhdNVF9HVUFSRElBTl9TSEFSRV9TVE9SRSob'
    'TVRfR1VBUkRJQU5fUkVTVE9SRV9SRVFVRVNUKhxNVF9HVUFSRElBTl9SRVNUT1JFX1JFU1BPTl'
    'NFKhFNVF9QRUVSX0xJU1RfUFVTSCoUTVRfUEVFUl9MSVNUX1NVTU1BUlkqEU1UX1BFRVJfTElT'
    'VF9XQU5UKhNNVF9QRUVSX0tFWV9SRVFVRVNUKhRNVF9QRUVSX0tFWV9SRVNQT05TRSoNTVRfUE'
    'VFUl9TVE9SRSoRTVRfUEVFUl9TVE9SRV9BQ0sqEE1UX1BFRVJfUkVUUklFVkUqGU1UX1BFRVJf'
    'UkVUUklFVkVfUkVTUE9OU0UqD01UX1JPVVRFX1VQREFURSoVTVRfUkVBQ0hBQklMSVRZX1FVRV'
    'JZKhhNVF9SRUFDSEFCSUxJVFlfUkVTUE9OU0UqEE1UX1JFTEFZX0ZPUldBUkQqDE1UX1JFTEFZ'
    'X0FDSyoVTVRfSE9MRV9QVU5DSF9SRVFVRVNUKhRNVF9IT0xFX1BVTkNIX05PVElGWSoSTVRfSE'
    '9MRV9QVU5DSF9QSU5HKhJNVF9IT0xFX1BVTkNIX1BPTkcqF01UX0lERU5USVRZX0tFTV9QVUJM'
    'SVNIKhhNVF9JREVOVElUWV9LRU1fUkVUUklFVkUqGE1UX0lERU5USVRZX0tFTV9SRVNQT05TRS'
    'oWTVRfREVWSUNFX1BBSVJfUkVRVUVTVCoWTVRfREVWSUNFX1BBSVJfQVBQUk9WRSoVTVRfREVW'
    'SUNFX0tFTV9SRVFVRVNUKhNNVF9ERVZJQ0VfS0VNX09GRkVSKhFNVF9GSVJTVF9DUl9TVE9SRS'
    'oVTVRfRklSU1RfQ1JfU1RPUkVfQUNLKhNNVF9GSVJTVF9DUl9ERUxJVkVSKhNNVF9QT0xMX0FO'
    'T05fU1VCTUlUKhdNVF9QT0xMX0FOT05fU1VCTUlUX0FDSyoRTVRfU1lTQ0hBTl9ESUdFU1QqEk'
    '1UX1NZU0NIQU5fU1VNTUFSWSoPTVRfU1lTQ0hBTl9XQU5UKg9NVF9TWVNDSEFOX1BVU0g=');

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
    {'1': 'device_ed25519_public_key', '3': 18, '4': 1, '5': 12, '10': 'deviceEd25519PublicKey'},
    {'1': 'device_ml_dsa_public_key', '3': 19, '4': 1, '5': 12, '10': 'deviceMlDsaPublicKey'},
    {'1': 'key_fingerprint', '3': 20, '4': 1, '5': 12, '10': 'keyFingerprint'},
    {'1': 'device_id_pow_nonce', '3': 21, '4': 1, '5': 12, '10': 'deviceIdPowNonce'},
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
    'VtUHVibGljS2V5EhcKB3VzZXJfaWQYESABKAxSBnVzZXJJZBI5ChlkZXZpY2VfZWQyNTUxOV9w'
    'dWJsaWNfa2V5GBIgASgMUhZkZXZpY2VFZDI1NTE5UHVibGljS2V5EjYKGGRldmljZV9tbF9kc2'
    'FfcHVibGljX2tleRgTIAEoDFIUZGV2aWNlTWxEc2FQdWJsaWNLZXkSJwoPa2V5X2ZpbmdlcnBy'
    'aW50GBQgASgMUg5rZXlGaW5nZXJwcmludBItChNkZXZpY2VfaWRfcG93X25vbmNlGBUgASgMUh'
    'BkZXZpY2VJZFBvd05vbmNl');

@$core.Deprecated('Use dhtPingDescriptor instead')
const DhtPing$json = {
  '1': 'DhtPing',
  '2': [
    {'1': 'sender_id', '3': 1, '4': 1, '5': 12, '10': 'senderId'},
    {'1': 'timestamp', '3': 2, '4': 1, '5': 4, '10': 'timestamp'},
    {'1': 'pk_recovery_hint', '3': 3, '4': 1, '5': 8, '10': 'pkRecoveryHint'},
    {'1': 'want_kem_record', '3': 4, '4': 1, '5': 8, '10': 'wantKemRecord'},
  ],
};

/// Descriptor for `DhtPing`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List dhtPingDescriptor = $convert.base64Decode(
    'CgdEaHRQaW5nEhsKCXNlbmRlcl9pZBgBIAEoDFIIc2VuZGVySWQSHAoJdGltZXN0YW1wGAIgAS'
    'gEUgl0aW1lc3RhbXASKAoQcGtfcmVjb3ZlcnlfaGludBgDIAEoCFIOcGtSZWNvdmVyeUhpbnQS'
    'JgoPd2FudF9rZW1fcmVjb3JkGAQgASgIUg13YW50S2VtUmVjb3Jk');

@$core.Deprecated('Use dhtPongDescriptor instead')
const DhtPong$json = {
  '1': 'DhtPong',
  '2': [
    {'1': 'sender_id', '3': 1, '4': 1, '5': 12, '10': 'senderId'},
    {'1': 'timestamp', '3': 2, '4': 1, '5': 4, '10': 'timestamp'},
    {'1': 'observed_ip', '3': 3, '4': 1, '5': 9, '10': 'observedIp'},
    {'1': 'observed_port', '3': 4, '4': 1, '5': 13, '10': 'observedPort'},
    {'1': 'additional_node_ids', '3': 5, '4': 3, '5': 12, '10': 'additionalNodeIds'},
    {'1': 'kem_record', '3': 6, '4': 1, '5': 11, '6': '.cleona.DeviceKemRecord', '10': 'kemRecord'},
  ],
};

/// Descriptor for `DhtPong`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List dhtPongDescriptor = $convert.base64Decode(
    'CgdEaHRQb25nEhsKCXNlbmRlcl9pZBgBIAEoDFIIc2VuZGVySWQSHAoJdGltZXN0YW1wGAIgAS'
    'gEUgl0aW1lc3RhbXASHwoLb2JzZXJ2ZWRfaXAYAyABKAlSCm9ic2VydmVkSXASIwoNb2JzZXJ2'
    'ZWRfcG9ydBgEIAEoDVIMb2JzZXJ2ZWRQb3J0Ei4KE2FkZGl0aW9uYWxfbm9kZV9pZHMYBSADKA'
    'xSEWFkZGl0aW9uYWxOb2RlSWRzEjYKCmtlbV9yZWNvcmQYBiABKAsyFy5jbGVvbmEuRGV2aWNl'
    'S2VtUmVjb3JkUglrZW1SZWNvcmQ=');

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
  '9': [
    {'1': 2, '2': 3},
    {'1': 3, '2': 4},
  ],
  '10': ['hops_from_sender', 'cost_from_sender'],
};

/// Descriptor for `PeerListPush`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List peerListPushDescriptor = $convert.base64Decode(
    'CgxQZWVyTGlzdFB1c2gSKwoFcGVlcnMYASADKAsyFS5jbGVvbmEuUGVlckluZm9Qcm90b1IFcG'
    'VlcnNKBAgCEANKBAgDEARSEGhvcHNfZnJvbV9zZW5kZXJSEGNvc3RfZnJvbV9zZW5kZXI=');

@$core.Deprecated('Use peerKeyRequestDescriptor instead')
const PeerKeyRequest$json = {
  '1': 'PeerKeyRequest',
};

/// Descriptor for `PeerKeyRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List peerKeyRequestDescriptor = $convert.base64Decode(
    'Cg5QZWVyS2V5UmVxdWVzdA==');

@$core.Deprecated('Use peerKeyResponseDescriptor instead')
const PeerKeyResponse$json = {
  '1': 'PeerKeyResponse',
  '2': [
    {'1': 'peers', '3': 1, '4': 3, '5': 11, '6': '.cleona.PeerInfoProto', '10': 'peers'},
  ],
};

/// Descriptor for `PeerKeyResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List peerKeyResponseDescriptor = $convert.base64Decode(
    'Cg9QZWVyS2V5UmVzcG9uc2USKwoFcGVlcnMYASADKAsyFS5jbGVvbmEuUGVlckluZm9Qcm90b1'
    'IFcGVlcnM=');

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

@$core.Deprecated('Use fragmentRetrieveResponseDescriptor instead')
const FragmentRetrieveResponse$json = {
  '1': 'FragmentRetrieveResponse',
  '2': [
    {'1': 'mailbox_id', '3': 1, '4': 1, '5': 12, '10': 'mailboxId'},
    {'1': 'fragment_count', '3': 2, '4': 1, '5': 13, '10': 'fragmentCount'},
  ],
};

/// Descriptor for `FragmentRetrieveResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fragmentRetrieveResponseDescriptor = $convert.base64Decode(
    'ChhGcmFnbWVudFJldHJpZXZlUmVzcG9uc2USHQoKbWFpbGJveF9pZBgBIAEoDFIJbWFpbGJveE'
    'lkEiUKDmZyYWdtZW50X2NvdW50GAIgASgNUg1mcmFnbWVudENvdW50');

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
    {'1': 'withhold_delivery_status', '3': 3, '4': 1, '5': 8, '10': 'withholdDeliveryStatus'},
  ],
};

/// Descriptor for `DeliveryReceipt`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deliveryReceiptDescriptor = $convert.base64Decode(
    'Cg9EZWxpdmVyeVJlY2VpcHQSHQoKbWVzc2FnZV9pZBgBIAEoDFIJbWVzc2FnZUlkEiEKDGRlbG'
    'l2ZXJlZF9hdBgCIAEoBFILZGVsaXZlcmVkQXQSOAoYd2l0aGhvbGRfZGVsaXZlcnlfc3RhdHVz'
    'GAMgASgIUhZ3aXRoaG9sZERlbGl2ZXJ5U3RhdHVz');

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
    {'1': 'origin_user_id', '3': 10, '4': 1, '5': 12, '10': 'originUserId'},
  ],
};

/// Descriptor for `RelayForward`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List relayForwardDescriptor = $convert.base64Decode(
    'CgxSZWxheUZvcndhcmQSGQoIcmVsYXlfaWQYASABKAxSB3JlbGF5SWQSLAoSZmluYWxfcmVjaX'
    'BpZW50X2lkGAIgASgMUhBmaW5hbFJlY2lwaWVudElkEikKEHdyYXBwZWRfZW52ZWxvcGUYAyAB'
    'KAxSD3dyYXBwZWRFbnZlbG9wZRIbCglob3BfY291bnQYBCABKA1SCGhvcENvdW50EhkKCG1heF'
    '9ob3BzGAUgASgNUgdtYXhIb3BzEiMKDXZpc2l0ZWRfbm9kZXMYBiADKAxSDHZpc2l0ZWROb2Rl'
    'cxIkCg5vcmlnaW5fbm9kZV9pZBgHIAEoDFIMb3JpZ2luTm9kZUlkEiIKDWNyZWF0ZWRfYXRfbX'
    'MYCCABKARSC2NyZWF0ZWRBdE1zEhAKA3R0bBgJIAEoDVIDdHRsEiQKDm9yaWdpbl91c2VyX2lk'
    'GAogASgMUgxvcmlnaW5Vc2VySWQ=');

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

@$core.Deprecated('Use rotationChainLinkProtoDescriptor instead')
const RotationChainLinkProto$json = {
  '1': 'RotationChainLinkProto',
  '2': [
    {'1': 'old_ed25519_pk', '3': 1, '4': 1, '5': 12, '10': 'oldEd25519Pk'},
    {'1': 'new_ed25519_pk', '3': 2, '4': 1, '5': 12, '10': 'newEd25519Pk'},
    {'1': 'new_ml_dsa_pk', '3': 3, '4': 1, '5': 12, '10': 'newMlDsaPk'},
    {'1': 'old_signature_ed25519', '3': 4, '4': 1, '5': 12, '10': 'oldSignatureEd25519'},
  ],
};

/// Descriptor for `RotationChainLinkProto`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rotationChainLinkProtoDescriptor = $convert.base64Decode(
    'ChZSb3RhdGlvbkNoYWluTGlua1Byb3RvEiQKDm9sZF9lZDI1NTE5X3BrGAEgASgMUgxvbGRFZD'
    'I1NTE5UGsSJAoObmV3X2VkMjU1MTlfcGsYAiABKAxSDG5ld0VkMjU1MTlQaxIhCg1uZXdfbWxf'
    'ZHNhX3BrGAMgASgMUgpuZXdNbERzYVBrEjIKFW9sZF9zaWduYXR1cmVfZWQyNTUxORgEIAEoDF'
    'ITb2xkU2lnbmF0dXJlRWQyNTUxOQ==');

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
    {'1': 'user_ed25519_pk', '3': 8, '4': 1, '5': 12, '10': 'userEd25519Pk'},
    {'1': 'user_ml_dsa_pk', '3': 9, '4': 1, '5': 12, '10': 'userMlDsaPk'},
    {'1': 'rotation_chain', '3': 10, '4': 3, '5': 11, '6': '.cleona.RotationChainLinkProto', '10': 'rotationChain'},
    {'1': 'device_delegations', '3': 11, '4': 3, '5': 11, '6': '.cleona.DeviceDelegationCertProto', '10': 'deviceDelegations'},
    {'1': 'device_sig_keys', '3': 12, '4': 3, '5': 11, '6': '.cleona.AuthorizedDeviceSigningKeys', '10': 'deviceSigKeys'},
    {'1': 'device_set_change_proof', '3': 13, '4': 1, '5': 11, '6': '.cleona.DeviceSetChangeProof', '10': 'deviceSetChangeProof'},
  ],
};

/// Descriptor for `AuthManifestProto`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List authManifestProtoDescriptor = $convert.base64Decode(
    'ChFBdXRoTWFuaWZlc3RQcm90bxIXCgd1c2VyX2lkGAEgASgMUgZ1c2VySWQSOwoaYXV0aG9yaX'
    'plZF9kZXZpY2Vfbm9kZV9pZHMYAiADKAxSF2F1dGhvcml6ZWREZXZpY2VOb2RlSWRzEh8KC3R0'
    'bF9zZWNvbmRzGAMgASgFUgp0dGxTZWNvbmRzEicKD3NlcXVlbmNlX251bWJlchgEIAEoA1IOc2'
    'VxdWVuY2VOdW1iZXISJgoPcHVibGlzaGVkX2F0X21zGAUgASgDUg1wdWJsaXNoZWRBdE1zEh8K'
    'C2VkMjU1MTlfc2lnGAYgASgMUgplZDI1NTE5U2lnEhwKCm1sX2RzYV9zaWcYByABKAxSCG1sRH'
    'NhU2lnEiYKD3VzZXJfZWQyNTUxOV9waxgIIAEoDFINdXNlckVkMjU1MTlQaxIjCg51c2VyX21s'
    'X2RzYV9waxgJIAEoDFILdXNlck1sRHNhUGsSRQoOcm90YXRpb25fY2hhaW4YCiADKAsyHi5jbG'
    'VvbmEuUm90YXRpb25DaGFpbkxpbmtQcm90b1INcm90YXRpb25DaGFpbhJQChJkZXZpY2VfZGVs'
    'ZWdhdGlvbnMYCyADKAsyIS5jbGVvbmEuRGV2aWNlRGVsZWdhdGlvbkNlcnRQcm90b1IRZGV2aW'
    'NlRGVsZWdhdGlvbnMSSwoPZGV2aWNlX3NpZ19rZXlzGAwgAygLMiMuY2xlb25hLkF1dGhvcml6'
    'ZWREZXZpY2VTaWduaW5nS2V5c1INZGV2aWNlU2lnS2V5cxJTChdkZXZpY2Vfc2V0X2NoYW5nZV'
    '9wcm9vZhgNIAEoCzIcLmNsZW9uYS5EZXZpY2VTZXRDaGFuZ2VQcm9vZlIUZGV2aWNlU2V0Q2hh'
    'bmdlUHJvb2Y=');

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
    {'1': 'signer_ed25519_pk', '3': 8, '4': 1, '5': 12, '10': 'signerEd25519Pk'},
  ],
  '9': [
    {'1': 9, '2': 10},
  ],
};

/// Descriptor for `LivenessRecordProto`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List livenessRecordProtoDescriptor = $convert.base64Decode(
    'ChNMaXZlbmVzc1JlY29yZFByb3RvEhcKB3VzZXJfaWQYASABKAxSBnVzZXJJZBIkCg5kZXZpY2'
    'Vfbm9kZV9pZBgCIAEoDFIMZGV2aWNlTm9kZUlkEjYKCWFkZHJlc3NlcxgDIAMoCzIYLmNsZW9u'
    'YS5QZWVyQWRkcmVzc1Byb3RvUglhZGRyZXNzZXMSHwoLdHRsX3NlY29uZHMYBCABKAVSCnR0bF'
    'NlY29uZHMSJwoPc2VxdWVuY2VfbnVtYmVyGAUgASgDUg5zZXF1ZW5jZU51bWJlchImCg9wdWJs'
    'aXNoZWRfYXRfbXMYBiABKANSDXB1Ymxpc2hlZEF0TXMSHwoLZWQyNTUxOV9zaWcYByABKAxSCm'
    'VkMjU1MTlTaWcSKgoRc2lnbmVyX2VkMjU1MTlfcGsYCCABKAxSD3NpZ25lckVkMjU1MTlQa0oE'
    'CAkQCg==');

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

@$core.Deprecated('Use identityKemRetrieveRequestDescriptor instead')
const IdentityKemRetrieveRequest$json = {
  '1': 'IdentityKemRetrieveRequest',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 12, '10': 'userId'},
    {'1': 'device_id', '3': 2, '4': 1, '5': 12, '10': 'deviceId'},
    {'1': 'minimum_seq', '3': 3, '4': 1, '5': 4, '10': 'minimumSeq'},
  ],
};

/// Descriptor for `IdentityKemRetrieveRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List identityKemRetrieveRequestDescriptor = $convert.base64Decode(
    'ChpJZGVudGl0eUtlbVJldHJpZXZlUmVxdWVzdBIXCgd1c2VyX2lkGAEgASgMUgZ1c2VySWQSGw'
    'oJZGV2aWNlX2lkGAIgASgMUghkZXZpY2VJZBIfCgttaW5pbXVtX3NlcRgDIAEoBFIKbWluaW11'
    'bVNlcQ==');

@$core.Deprecated('Use networkPacketDescriptor instead')
const NetworkPacket$json = {
  '1': 'NetworkPacket',
  '2': [
    {'1': 'version', '3': 1, '4': 1, '5': 13, '10': 'version'},
    {'1': 'flags', '3': 2, '4': 1, '5': 13, '10': 'flags'},
    {'1': 'next_hop_device_id', '3': 3, '4': 1, '5': 12, '10': 'nextHopDeviceId'},
    {'1': 'sender_device_id', '3': 4, '4': 1, '5': 12, '10': 'senderDeviceId'},
    {'1': 'timestamp_ms', '3': 5, '4': 1, '5': 4, '10': 'timestampMs'},
    {'1': 'ttl', '3': 6, '4': 1, '5': 13, '10': 'ttl'},
    {'1': 'hop_count', '3': 7, '4': 1, '5': 13, '10': 'hopCount'},
    {'1': 'network_tag', '3': 8, '4': 1, '5': 12, '10': 'networkTag'},
    {'1': 'pow', '3': 9, '4': 1, '5': 11, '6': '.cleona.ProofOfWork', '10': 'pow'},
    {'1': 'device_ed25519_sig', '3': 10, '4': 1, '5': 12, '10': 'deviceEd25519Sig'},
    {'1': 'device_ml_dsa_sig', '3': 11, '4': 1, '5': 12, '10': 'deviceMlDsaSig'},
    {'1': 'payload_type', '3': 12, '4': 1, '5': 14, '6': '.cleona.PayloadType', '10': 'payloadType'},
    {'1': 'payload', '3': 13, '4': 1, '5': 12, '10': 'payload'},
  ],
  '9': [
    {'1': 14, '2': 15},
    {'1': 15, '2': 16},
  ],
  '10': ['visited_device_ids', 'sender_data_port'],
};

/// Descriptor for `NetworkPacket`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List networkPacketDescriptor = $convert.base64Decode(
    'Cg1OZXR3b3JrUGFja2V0EhgKB3ZlcnNpb24YASABKA1SB3ZlcnNpb24SFAoFZmxhZ3MYAiABKA'
    '1SBWZsYWdzEisKEm5leHRfaG9wX2RldmljZV9pZBgDIAEoDFIPbmV4dEhvcERldmljZUlkEigK'
    'EHNlbmRlcl9kZXZpY2VfaWQYBCABKAxSDnNlbmRlckRldmljZUlkEiEKDHRpbWVzdGFtcF9tcx'
    'gFIAEoBFILdGltZXN0YW1wTXMSEAoDdHRsGAYgASgNUgN0dGwSGwoJaG9wX2NvdW50GAcgASgN'
    'Ughob3BDb3VudBIfCgtuZXR3b3JrX3RhZxgIIAEoDFIKbmV0d29ya1RhZxIlCgNwb3cYCSABKA'
    'syEy5jbGVvbmEuUHJvb2ZPZldvcmtSA3BvdxIsChJkZXZpY2VfZWQyNTUxOV9zaWcYCiABKAxS'
    'EGRldmljZUVkMjU1MTlTaWcSKQoRZGV2aWNlX21sX2RzYV9zaWcYCyABKAxSDmRldmljZU1sRH'
    'NhU2lnEjYKDHBheWxvYWRfdHlwZRgMIAEoDjITLmNsZW9uYS5QYXlsb2FkVHlwZVILcGF5bG9h'
    'ZFR5cGUSGAoHcGF5bG9hZBgNIAEoDFIHcGF5bG9hZEoECA4QD0oECA8QEFISdmlzaXRlZF9kZX'
    'ZpY2VfaWRzUhBzZW5kZXJfZGF0YV9wb3J0');

@$core.Deprecated('Use applicationFrameDescriptor instead')
const ApplicationFrame$json = {
  '1': 'ApplicationFrame',
  '2': [
    {'1': 'recipient_user_id', '3': 2, '4': 1, '5': 12, '10': 'recipientUserId'},
    {'1': 'sender_user_id', '3': 3, '4': 1, '5': 12, '10': 'senderUserId'},
    {'1': 'timestamp_ms', '3': 4, '4': 1, '5': 4, '10': 'timestampMs'},
    {'1': 'message_id', '3': 5, '4': 1, '5': 12, '10': 'messageId'},
    {'1': 'message_type', '3': 6, '4': 1, '5': 14, '6': '.cleona.MessageType', '10': 'messageType'},
    {'1': 'payload', '3': 7, '4': 1, '5': 12, '10': 'payload'},
    {'1': 'user_ed25519_sig', '3': 10, '4': 1, '5': 12, '10': 'userEd25519Sig'},
    {'1': 'user_ml_dsa_sig', '3': 11, '4': 1, '5': 12, '10': 'userMlDsaSig'},
    {'1': 'content_metadata', '3': 12, '4': 1, '5': 11, '6': '.cleona.ContentMetadata', '10': 'contentMetadata'},
    {'1': 'edit_metadata', '3': 13, '4': 1, '5': 11, '6': '.cleona.EditMetadata', '10': 'editMetadata'},
    {'1': 'expiry_metadata', '3': 14, '4': 1, '5': 11, '6': '.cleona.ExpiryMetadata', '10': 'expiryMetadata'},
    {'1': 'erasure_metadata', '3': 15, '4': 1, '5': 11, '6': '.cleona.ErasureCodingMetadata', '10': 'erasureMetadata'},
    {'1': 'compression', '3': 16, '4': 1, '5': 14, '6': '.cleona.CompressionType', '10': 'compression'},
    {'1': 'group_id', '3': 17, '4': 1, '5': 12, '10': 'groupId'},
    {'1': 'group_membership_epoch', '3': 18, '4': 1, '5': 4, '10': 'groupMembershipEpoch'},
    {'1': 'group_membership_hash', '3': 19, '4': 1, '5': 12, '10': 'groupMembershipHash'},
    {'1': 'after_file', '3': 20, '4': 1, '5': 12, '10': 'afterFile'},
    {'1': 'post_id', '3': 21, '4': 1, '5': 12, '10': 'postId'},
  ],
  '9': [
    {'1': 1, '2': 2},
  ],
  '10': ['version'],
};

/// Descriptor for `ApplicationFrame`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List applicationFrameDescriptor = $convert.base64Decode(
    'ChBBcHBsaWNhdGlvbkZyYW1lEioKEXJlY2lwaWVudF91c2VyX2lkGAIgASgMUg9yZWNpcGllbn'
    'RVc2VySWQSJAoOc2VuZGVyX3VzZXJfaWQYAyABKAxSDHNlbmRlclVzZXJJZBIhCgx0aW1lc3Rh'
    'bXBfbXMYBCABKARSC3RpbWVzdGFtcE1zEh0KCm1lc3NhZ2VfaWQYBSABKAxSCW1lc3NhZ2VJZB'
    'I2CgxtZXNzYWdlX3R5cGUYBiABKA4yEy5jbGVvbmEuTWVzc2FnZVR5cGVSC21lc3NhZ2VUeXBl'
    'EhgKB3BheWxvYWQYByABKAxSB3BheWxvYWQSKAoQdXNlcl9lZDI1NTE5X3NpZxgKIAEoDFIOdX'
    'NlckVkMjU1MTlTaWcSJQoPdXNlcl9tbF9kc2Ffc2lnGAsgASgMUgx1c2VyTWxEc2FTaWcSQgoQ'
    'Y29udGVudF9tZXRhZGF0YRgMIAEoCzIXLmNsZW9uYS5Db250ZW50TWV0YWRhdGFSD2NvbnRlbn'
    'RNZXRhZGF0YRI5Cg1lZGl0X21ldGFkYXRhGA0gASgLMhQuY2xlb25hLkVkaXRNZXRhZGF0YVIM'
    'ZWRpdE1ldGFkYXRhEj8KD2V4cGlyeV9tZXRhZGF0YRgOIAEoCzIWLmNsZW9uYS5FeHBpcnlNZX'
    'RhZGF0YVIOZXhwaXJ5TWV0YWRhdGESSAoQZXJhc3VyZV9tZXRhZGF0YRgPIAEoCzIdLmNsZW9u'
    'YS5FcmFzdXJlQ29kaW5nTWV0YWRhdGFSD2VyYXN1cmVNZXRhZGF0YRI5Cgtjb21wcmVzc2lvbh'
    'gQIAEoDjIXLmNsZW9uYS5Db21wcmVzc2lvblR5cGVSC2NvbXByZXNzaW9uEhkKCGdyb3VwX2lk'
    'GBEgASgMUgdncm91cElkEjQKFmdyb3VwX21lbWJlcnNoaXBfZXBvY2gYEiABKARSFGdyb3VwTW'
    'VtYmVyc2hpcEVwb2NoEjIKFWdyb3VwX21lbWJlcnNoaXBfaGFzaBgTIAEoDFITZ3JvdXBNZW1i'
    'ZXJzaGlwSGFzaBIdCgphZnRlcl9maWxlGBQgASgMUglhZnRlckZpbGUSFwoHcG9zdF9pZBgVIA'
    'EoDFIGcG9zdElkSgQIARACUgd2ZXJzaW9u');

@$core.Deprecated('Use perMessageKemEnvelopeDescriptor instead')
const PerMessageKemEnvelope$json = {
  '1': 'PerMessageKemEnvelope',
  '2': [
    {'1': 'x25519_ciphertext', '3': 1, '4': 1, '5': 12, '10': 'x25519Ciphertext'},
    {'1': 'ml_kem_ciphertext', '3': 2, '4': 1, '5': 12, '10': 'mlKemCiphertext'},
    {'1': 'aead_ciphertext', '3': 3, '4': 1, '5': 12, '10': 'aeadCiphertext'},
    {'1': 'aead_nonce', '3': 4, '4': 1, '5': 12, '10': 'aeadNonce'},
    {'1': 'version', '3': 5, '4': 1, '5': 13, '10': 'version'},
  ],
};

/// Descriptor for `PerMessageKemEnvelope`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List perMessageKemEnvelopeDescriptor = $convert.base64Decode(
    'ChVQZXJNZXNzYWdlS2VtRW52ZWxvcGUSKwoReDI1NTE5X2NpcGhlcnRleHQYASABKAxSEHgyNT'
    'UxOUNpcGhlcnRleHQSKgoRbWxfa2VtX2NpcGhlcnRleHQYAiABKAxSD21sS2VtQ2lwaGVydGV4'
    'dBInCg9hZWFkX2NpcGhlcnRleHQYAyABKAxSDmFlYWRDaXBoZXJ0ZXh0Eh0KCmFlYWRfbm9uY2'
    'UYBCABKAxSCWFlYWROb25jZRIYCgd2ZXJzaW9uGAUgASgNUgd2ZXJzaW9u');

@$core.Deprecated('Use authManifestDescriptor instead')
const AuthManifest$json = {
  '1': 'AuthManifest',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 12, '10': 'userId'},
    {'1': 'authorized_device_ids', '3': 2, '4': 3, '5': 12, '10': 'authorizedDeviceIds'},
    {'1': 'ttl_seconds', '3': 3, '4': 1, '5': 4, '10': 'ttlSeconds'},
    {'1': 'sequence_number', '3': 4, '4': 1, '5': 4, '10': 'sequenceNumber'},
    {'1': 'published_at_ms', '3': 5, '4': 1, '5': 4, '10': 'publishedAtMs'},
    {'1': 'ed25519_sig', '3': 6, '4': 1, '5': 12, '10': 'ed25519Sig'},
    {'1': 'ml_dsa_sig', '3': 7, '4': 1, '5': 12, '10': 'mlDsaSig'},
    {'1': 'user_ed25519_pk', '3': 8, '4': 1, '5': 12, '10': 'userEd25519Pk'},
    {'1': 'user_ml_dsa_pk', '3': 9, '4': 1, '5': 12, '10': 'userMlDsaPk'},
  ],
};

/// Descriptor for `AuthManifest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List authManifestDescriptor = $convert.base64Decode(
    'CgxBdXRoTWFuaWZlc3QSFwoHdXNlcl9pZBgBIAEoDFIGdXNlcklkEjIKFWF1dGhvcml6ZWRfZG'
    'V2aWNlX2lkcxgCIAMoDFITYXV0aG9yaXplZERldmljZUlkcxIfCgt0dGxfc2Vjb25kcxgDIAEo'
    'BFIKdHRsU2Vjb25kcxInCg9zZXF1ZW5jZV9udW1iZXIYBCABKARSDnNlcXVlbmNlTnVtYmVyEi'
    'YKD3B1Ymxpc2hlZF9hdF9tcxgFIAEoBFINcHVibGlzaGVkQXRNcxIfCgtlZDI1NTE5X3NpZxgG'
    'IAEoDFIKZWQyNTUxOVNpZxIcCgptbF9kc2Ffc2lnGAcgASgMUghtbERzYVNpZxImCg91c2VyX2'
    'VkMjU1MTlfcGsYCCABKAxSDXVzZXJFZDI1NTE5UGsSIwoOdXNlcl9tbF9kc2FfcGsYCSABKAxS'
    'C3VzZXJNbERzYVBr');

@$core.Deprecated('Use livenessRecordDescriptor instead')
const LivenessRecord$json = {
  '1': 'LivenessRecord',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 12, '10': 'userId'},
    {'1': 'device_node_id', '3': 2, '4': 1, '5': 12, '10': 'deviceNodeId'},
    {'1': 'addresses', '3': 3, '4': 3, '5': 11, '6': '.cleona.PeerAddressProto', '10': 'addresses'},
    {'1': 'ttl_seconds', '3': 4, '4': 1, '5': 4, '10': 'ttlSeconds'},
    {'1': 'sequence_number', '3': 5, '4': 1, '5': 4, '10': 'sequenceNumber'},
    {'1': 'published_at_ms', '3': 6, '4': 1, '5': 4, '10': 'publishedAtMs'},
    {'1': 'ed25519_sig', '3': 7, '4': 1, '5': 12, '10': 'ed25519Sig'},
    {'1': 'device_ed25519_pk', '3': 8, '4': 1, '5': 12, '10': 'deviceEd25519Pk'},
  ],
};

/// Descriptor for `LivenessRecord`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List livenessRecordDescriptor = $convert.base64Decode(
    'Cg5MaXZlbmVzc1JlY29yZBIXCgd1c2VyX2lkGAEgASgMUgZ1c2VySWQSJAoOZGV2aWNlX25vZG'
    'VfaWQYAiABKAxSDGRldmljZU5vZGVJZBI2CglhZGRyZXNzZXMYAyADKAsyGC5jbGVvbmEuUGVl'
    'ckFkZHJlc3NQcm90b1IJYWRkcmVzc2VzEh8KC3R0bF9zZWNvbmRzGAQgASgEUgp0dGxTZWNvbm'
    'RzEicKD3NlcXVlbmNlX251bWJlchgFIAEoBFIOc2VxdWVuY2VOdW1iZXISJgoPcHVibGlzaGVk'
    'X2F0X21zGAYgASgEUg1wdWJsaXNoZWRBdE1zEh8KC2VkMjU1MTlfc2lnGAcgASgMUgplZDI1NT'
    'E5U2lnEioKEWRldmljZV9lZDI1NTE5X3BrGAggASgMUg9kZXZpY2VFZDI1NTE5UGs=');

@$core.Deprecated('Use deviceKemRecordDescriptor instead')
const DeviceKemRecord$json = {
  '1': 'DeviceKemRecord',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 12, '10': 'userId'},
    {'1': 'device_id', '3': 2, '4': 1, '5': 12, '10': 'deviceId'},
    {'1': 'device_x25519_pk', '3': 3, '4': 1, '5': 12, '10': 'deviceX25519Pk'},
    {'1': 'device_ml_kem_pk', '3': 4, '4': 1, '5': 12, '10': 'deviceMlKemPk'},
    {'1': 'ttl_seconds', '3': 5, '4': 1, '5': 4, '10': 'ttlSeconds'},
    {'1': 'sequence_number', '3': 6, '4': 1, '5': 4, '10': 'sequenceNumber'},
    {'1': 'published_at_ms', '3': 7, '4': 1, '5': 4, '10': 'publishedAtMs'},
    {'1': 'ed25519_sig', '3': 8, '4': 1, '5': 12, '10': 'ed25519Sig'},
    {'1': 'user_ed25519_pk', '3': 9, '4': 1, '5': 12, '10': 'userEd25519Pk'},
    {'1': 'signer_ed25519_pk', '3': 10, '4': 1, '5': 12, '10': 'signerEd25519Pk'},
  ],
  '9': [
    {'1': 11, '2': 12},
  ],
};

/// Descriptor for `DeviceKemRecord`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deviceKemRecordDescriptor = $convert.base64Decode(
    'Cg9EZXZpY2VLZW1SZWNvcmQSFwoHdXNlcl9pZBgBIAEoDFIGdXNlcklkEhsKCWRldmljZV9pZB'
    'gCIAEoDFIIZGV2aWNlSWQSKAoQZGV2aWNlX3gyNTUxOV9waxgDIAEoDFIOZGV2aWNlWDI1NTE5'
    'UGsSJwoQZGV2aWNlX21sX2tlbV9waxgEIAEoDFINZGV2aWNlTWxLZW1QaxIfCgt0dGxfc2Vjb2'
    '5kcxgFIAEoBFIKdHRsU2Vjb25kcxInCg9zZXF1ZW5jZV9udW1iZXIYBiABKARSDnNlcXVlbmNl'
    'TnVtYmVyEiYKD3B1Ymxpc2hlZF9hdF9tcxgHIAEoBFINcHVibGlzaGVkQXRNcxIfCgtlZDI1NT'
    'E5X3NpZxgIIAEoDFIKZWQyNTUxOVNpZxImCg91c2VyX2VkMjU1MTlfcGsYCSABKAxSDXVzZXJF'
    'ZDI1NTE5UGsSKgoRc2lnbmVyX2VkMjU1MTlfcGsYCiABKAxSD3NpZ25lckVkMjU1MTlQa0oECA'
    'sQDA==');

@$core.Deprecated('Use peerListEntryDescriptor instead')
const PeerListEntry$json = {
  '1': 'PeerListEntry',
  '2': [
    {'1': 'device_id', '3': 1, '4': 1, '5': 12, '10': 'deviceId'},
    {'1': 'addresses', '3': 2, '4': 3, '5': 11, '6': '.cleona.PeerAddressProto', '10': 'addresses'},
    {'1': 'last_seen_ms', '3': 3, '4': 1, '5': 4, '10': 'lastSeenMs'},
    {'1': 'age_hours', '3': 4, '4': 1, '5': 4, '10': 'ageHours'},
    {'1': 'connection_type', '3': 5, '4': 1, '5': 14, '6': '.cleona.ConnectionTypeProto', '10': 'connectionType'},
  ],
};

/// Descriptor for `PeerListEntry`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List peerListEntryDescriptor = $convert.base64Decode(
    'Cg1QZWVyTGlzdEVudHJ5EhsKCWRldmljZV9pZBgBIAEoDFIIZGV2aWNlSWQSNgoJYWRkcmVzc2'
    'VzGAIgAygLMhguY2xlb25hLlBlZXJBZGRyZXNzUHJvdG9SCWFkZHJlc3NlcxIgCgxsYXN0X3Nl'
    'ZW5fbXMYAyABKARSCmxhc3RTZWVuTXMSGwoJYWdlX2hvdXJzGAQgASgEUghhZ2VIb3VycxJECg'
    '9jb25uZWN0aW9uX3R5cGUYBSABKA4yGy5jbGVvbmEuQ29ubmVjdGlvblR5cGVQcm90b1IOY29u'
    'bmVjdGlvblR5cGU=');

@$core.Deprecated('Use packetRelayForwardDescriptor instead')
const PacketRelayForward$json = {
  '1': 'PacketRelayForward',
  '2': [
    {'1': 'relay_id', '3': 1, '4': 1, '5': 12, '10': 'relayId'},
    {'1': 'final_recipient_id', '3': 2, '4': 1, '5': 12, '10': 'finalRecipientId'},
    {'1': 'wrapped_packet', '3': 3, '4': 1, '5': 12, '10': 'wrappedPacket'},
    {'1': 'hop_count', '3': 4, '4': 1, '5': 13, '10': 'hopCount'},
    {'1': 'max_hops', '3': 5, '4': 1, '5': 13, '10': 'maxHops'},
    {'1': 'ttl', '3': 6, '4': 1, '5': 13, '10': 'ttl'},
    {'1': 'origin_device_id', '3': 7, '4': 1, '5': 12, '10': 'originDeviceId'},
    {'1': 'created_at_ms', '3': 8, '4': 1, '5': 4, '10': 'createdAtMs'},
    {'1': 'visited', '3': 9, '4': 3, '5': 12, '10': 'visited'},
  ],
};

/// Descriptor for `PacketRelayForward`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List packetRelayForwardDescriptor = $convert.base64Decode(
    'ChJQYWNrZXRSZWxheUZvcndhcmQSGQoIcmVsYXlfaWQYASABKAxSB3JlbGF5SWQSLAoSZmluYW'
    'xfcmVjaXBpZW50X2lkGAIgASgMUhBmaW5hbFJlY2lwaWVudElkEiUKDndyYXBwZWRfcGFja2V0'
    'GAMgASgMUg13cmFwcGVkUGFja2V0EhsKCWhvcF9jb3VudBgEIAEoDVIIaG9wQ291bnQSGQoIbW'
    'F4X2hvcHMYBSABKA1SB21heEhvcHMSEAoDdHRsGAYgASgNUgN0dGwSKAoQb3JpZ2luX2Rldmlj'
    'ZV9pZBgHIAEoDFIOb3JpZ2luRGV2aWNlSWQSIgoNY3JlYXRlZF9hdF9tcxgIIAEoBFILY3JlYX'
    'RlZEF0TXMSGAoHdmlzaXRlZBgJIAMoDFIHdmlzaXRlZA==');

@$core.Deprecated('Use deviceKemRequestDescriptor instead')
const DeviceKemRequest$json = {
  '1': 'DeviceKemRequest',
  '2': [
    {'1': 'target_user_id', '3': 1, '4': 1, '5': 12, '10': 'targetUserId'},
    {'1': 'target_device_id', '3': 2, '4': 1, '5': 12, '10': 'targetDeviceId'},
    {'1': 'nonce', '3': 3, '4': 1, '5': 12, '10': 'nonce'},
    {'1': 'timestamp_ms', '3': 4, '4': 1, '5': 4, '10': 'timestampMs'},
  ],
};

/// Descriptor for `DeviceKemRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deviceKemRequestDescriptor = $convert.base64Decode(
    'ChBEZXZpY2VLZW1SZXF1ZXN0EiQKDnRhcmdldF91c2VyX2lkGAEgASgMUgx0YXJnZXRVc2VySW'
    'QSKAoQdGFyZ2V0X2RldmljZV9pZBgCIAEoDFIOdGFyZ2V0RGV2aWNlSWQSFAoFbm9uY2UYAyAB'
    'KAxSBW5vbmNlEiEKDHRpbWVzdGFtcF9tcxgEIAEoBFILdGltZXN0YW1wTXM=');

@$core.Deprecated('Use deviceKemOfferDescriptor instead')
const DeviceKemOffer$json = {
  '1': 'DeviceKemOffer',
  '2': [
    {'1': 'device_x25519_pk', '3': 1, '4': 1, '5': 12, '10': 'deviceX25519Pk'},
    {'1': 'device_ml_kem_pk', '3': 2, '4': 1, '5': 12, '10': 'deviceMlKemPk'},
    {'1': 'nonce', '3': 3, '4': 1, '5': 12, '10': 'nonce'},
    {'1': 'user_ed25519_sig', '3': 4, '4': 1, '5': 12, '10': 'userEd25519Sig'},
    {'1': 'timestamp_ms', '3': 5, '4': 1, '5': 4, '10': 'timestampMs'},
  ],
};

/// Descriptor for `DeviceKemOffer`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deviceKemOfferDescriptor = $convert.base64Decode(
    'Cg5EZXZpY2VLZW1PZmZlchIoChBkZXZpY2VfeDI1NTE5X3BrGAEgASgMUg5kZXZpY2VYMjU1MT'
    'lQaxInChBkZXZpY2VfbWxfa2VtX3BrGAIgASgMUg1kZXZpY2VNbEtlbVBrEhQKBW5vbmNlGAMg'
    'ASgMUgVub25jZRIoChB1c2VyX2VkMjU1MTlfc2lnGAQgASgMUg51c2VyRWQyNTUxOVNpZxIhCg'
    'x0aW1lc3RhbXBfbXMYBSABKARSC3RpbWVzdGFtcE1z');

@$core.Deprecated('Use firstCrStoreDescriptor instead')
const FirstCrStore$json = {
  '1': 'FirstCrStore',
  '2': [
    {'1': 'recipient_user_id', '3': 1, '4': 1, '5': 12, '10': 'recipientUserId'},
    {'1': 'recipient_device_id', '3': 2, '4': 1, '5': 12, '10': 'recipientDeviceId'},
    {'1': 'encrypted_cr_blob', '3': 3, '4': 1, '5': 12, '10': 'encryptedCrBlob'},
    {'1': 'sender_device_id', '3': 4, '4': 1, '5': 12, '10': 'senderDeviceId'},
    {'1': 'timestamp_ms', '3': 5, '4': 1, '5': 4, '10': 'timestampMs'},
    {'1': 'ttl_ms', '3': 6, '4': 1, '5': 4, '10': 'ttlMs'},
  ],
};

/// Descriptor for `FirstCrStore`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List firstCrStoreDescriptor = $convert.base64Decode(
    'CgxGaXJzdENyU3RvcmUSKgoRcmVjaXBpZW50X3VzZXJfaWQYASABKAxSD3JlY2lwaWVudFVzZX'
    'JJZBIuChNyZWNpcGllbnRfZGV2aWNlX2lkGAIgASgMUhFyZWNpcGllbnREZXZpY2VJZBIqChFl'
    'bmNyeXB0ZWRfY3JfYmxvYhgDIAEoDFIPZW5jcnlwdGVkQ3JCbG9iEigKEHNlbmRlcl9kZXZpY2'
    'VfaWQYBCABKAxSDnNlbmRlckRldmljZUlkEiEKDHRpbWVzdGFtcF9tcxgFIAEoBFILdGltZXN0'
    'YW1wTXMSFQoGdHRsX21zGAYgASgEUgV0dGxNcw==');

@$core.Deprecated('Use firstCrStoreAckDescriptor instead')
const FirstCrStoreAck$json = {
  '1': 'FirstCrStoreAck',
  '2': [
    {'1': 'accepted', '3': 1, '4': 1, '5': 8, '10': 'accepted'},
    {'1': 'reject_reason', '3': 2, '4': 1, '5': 9, '10': 'rejectReason'},
    {'1': 'recipient_user_id', '3': 3, '4': 1, '5': 12, '10': 'recipientUserId'},
  ],
};

/// Descriptor for `FirstCrStoreAck`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List firstCrStoreAckDescriptor = $convert.base64Decode(
    'Cg9GaXJzdENyU3RvcmVBY2sSGgoIYWNjZXB0ZWQYASABKAhSCGFjY2VwdGVkEiMKDXJlamVjdF'
    '9yZWFzb24YAiABKAlSDHJlamVjdFJlYXNvbhIqChFyZWNpcGllbnRfdXNlcl9pZBgDIAEoDFIP'
    'cmVjaXBpZW50VXNlcklk');

@$core.Deprecated('Use firstCrDeliverDescriptor instead')
const FirstCrDeliver$json = {
  '1': 'FirstCrDeliver',
  '2': [
    {'1': 'encrypted_cr_blob', '3': 1, '4': 1, '5': 12, '10': 'encryptedCrBlob'},
    {'1': 'sender_device_id', '3': 2, '4': 1, '5': 12, '10': 'senderDeviceId'},
    {'1': 'stored_at_ms', '3': 3, '4': 1, '5': 4, '10': 'storedAtMs'},
  ],
};

/// Descriptor for `FirstCrDeliver`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List firstCrDeliverDescriptor = $convert.base64Decode(
    'Cg5GaXJzdENyRGVsaXZlchIqChFlbmNyeXB0ZWRfY3JfYmxvYhgBIAEoDFIPZW5jcnlwdGVkQ3'
    'JCbG9iEigKEHNlbmRlcl9kZXZpY2VfaWQYAiABKAxSDnNlbmRlckRldmljZUlkEiAKDHN0b3Jl'
    'ZF9hdF9tcxgDIAEoBFIKc3RvcmVkQXRNcw==');


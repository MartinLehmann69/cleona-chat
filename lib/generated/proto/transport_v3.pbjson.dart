//
//  Generated code. Do not modify.
//  source: transport_v3.proto
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

@$core.Deprecated('Use payloadTypeV3Descriptor instead')
const PayloadTypeV3$json = {
  '1': 'PayloadTypeV3',
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

/// Descriptor for `PayloadTypeV3`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List payloadTypeV3Descriptor = $convert.base64Decode(
    'Cg1QYXlsb2FkVHlwZVYzEh0KGVBBWUxPQURfQVBQTElDQVRJT05fRlJBTUUQABIXChNQQVlMT0'
    'FEX09OSU9OX0xBWUVSEAEiBAgCEAIiBAgDEAMqHFBBWUxPQURfSU5GUkFTVFJVQ1RVUkVfRlJB'
    'TUUqJlBBWUxPQURfQk9PVFNUUkFQX0lORlJBU1RSVUNUVVJFX0ZSQU1F');

@$core.Deprecated('Use messageTypeV3Descriptor instead')
const MessageTypeV3$json = {
  '1': 'MessageTypeV3',
  '2': [
    {'1': 'MTV3_TEXT', '2': 0},
    {'1': 'MTV3_MEDIA_INLINE', '2': 1},
    {'1': 'MTV3_MEDIA_ANNOUNCE', '2': 2},
    {'1': 'MTV3_MEDIA_REQUEST', '2': 3},
    {'1': 'MTV3_MEDIA_CHUNK', '2': 4},
    {'1': 'MTV3_MEDIA_COMPLETE', '2': 5},
    {'1': 'MTV3_MEDIA_REJECT', '2': 6},
    {'1': 'MTV3_REACTION', '2': 7},
    {'1': 'MTV3_REPLY', '2': 8},
    {'1': 'MTV3_EDIT', '2': 9},
    {'1': 'MTV3_DELETE', '2': 10},
    {'1': 'MTV3_MEDIA_STREAM_REQUEST', '2': 11},
    {'1': 'MTV3_MEDIA_STREAM_OFFER', '2': 12},
    {'1': 'MTV3_MEDIA_HOLDERS', '2': 13},
    {'1': 'MTV3_MEDIA_ABORT', '2': 14},
    {'1': 'MTV3_TYPING_INDICATOR', '2': 15},
    {'1': 'MTV3_READ_RECEIPT', '2': 16},
    {'1': 'MTV3_DELIVERY_RECEIPT', '2': 17},
    {'1': 'MTV3_CATCH_UP', '2': 18},
    {'1': 'MTV3_VOICE_MESSAGE', '2': 22},
    {'1': 'MTV3_IDENTITY_DELETED', '2': 32},
    {'1': 'MTV3_PROFILE_UPDATE', '2': 33},
    {'1': 'MTV3_KEY_ROTATION_BROADCAST', '2': 34},
    {'1': 'MTV3_KEY_ROTATION_ACK', '2': 38},
    {'1': 'MTV3_CONTACT_REQUEST', '2': 40},
    {'1': 'MTV3_CONTACT_REQUEST_RESPONSE', '2': 41},
    {'1': 'MTV3_GROUP_CREATE', '2': 50},
    {'1': 'MTV3_GROUP_INVITE', '2': 51},
    {'1': 'MTV3_GROUP_LEAVE', '2': 52},
    {'1': 'MTV3_GROUP_KEY_UPDATE', '2': 53},
    {'1': 'MTV3_GROUP_MEMBERSHIP_RESYNC_REQUEST', '2': 54},
    {'1': 'MTV3_GROUP_JOIN', '2': 55},
    {'1': 'MTV3_CHANNEL_CREATE', '2': 60},
    {'1': 'MTV3_CHANNEL_POST', '2': 61},
    {'1': 'MTV3_CHANNEL_INVITE', '2': 62},
    {'1': 'MTV3_CHANNEL_LEAVE', '2': 63},
    {'1': 'MTV3_CHANNEL_ROLE_UPDATE', '2': 64},
    {'1': 'MTV3_CHANNEL_BAD_BADGE_REPORT', '2': 65},
    {'1': 'MTV3_CHANNEL_JURY_VOTE', '2': 66},
    {'1': 'MTV3_CHANNEL_MOD_DECISION', '2': 67},
    {'1': 'MTV3_CHANNEL_SUBSCRIBE_PROBE', '2': 68},
    {'1': 'MTV3_CALL_INVITE', '2': 70},
    {'1': 'MTV3_CALL_ANSWER', '2': 71},
    {'1': 'MTV3_CALL_REJECT', '2': 72},
    {'1': 'MTV3_CALL_HANGUP', '2': 73},
    {'1': 'MTV3_ICE_CANDIDATE', '2': 74},
    {'1': 'MTV3_CALL_REJOIN', '2': 75},
    {'1': 'MTV3_CALL_AUDIO', '2': 76},
    {'1': 'MTV3_CALL_VIDEO', '2': 77},
    {'1': 'MTV3_CALL_GROUP_AUDIO', '2': 78},
    {'1': 'MTV3_CALL_GROUP_VIDEO', '2': 79},
    {'1': 'MTV3_CALL_GROUP_LEAVE', '2': 80},
    {'1': 'MTV3_CALL_RTT_PING', '2': 82},
    {'1': 'MTV3_CALL_RTT_PONG', '2': 83},
    {'1': 'MTV3_CALL_TREE_UPDATE', '2': 84},
    {'1': 'MTV3_CALL_KEYFRAME_REQUEST', '2': 85},
    {'1': 'MTV3_CALL_GROUP_SENDER_KEY', '2': 86},
    {'1': 'MTV3_CALL_MEDIA_STATE', '2': 87},
    {'1': 'MTV3_CALL_CANCEL_OTHERS', '2': 88},
    {'1': 'MTV3_CALL_RING_ACK', '2': 89},
    {'1': 'MTV3_CHANNEL_INDEX_EXCHANGE', '2': 90},
    {'1': 'MTV3_CHANNEL_JOIN_REQUEST', '2': 91},
    {'1': 'MTV3_CHANNEL_REPORT', '2': 92},
    {'1': 'MTV3_DHT_PING', '2': 110},
    {'1': 'MTV3_DHT_PONG', '2': 111},
    {'1': 'MTV3_DHT_FIND_NODE', '2': 112},
    {'1': 'MTV3_DHT_FIND_NODE_RESPONSE', '2': 113},
    {'1': 'MTV3_DHT_STORE', '2': 114},
    {'1': 'MTV3_DHT_STORE_RESPONSE', '2': 115},
    {'1': 'MTV3_DHT_FIND_VALUE', '2': 116},
    {'1': 'MTV3_DHT_FIND_VALUE_RESPONSE', '2': 117},
    {'1': 'MTV3_FRAGMENT_STORE', '2': 120},
    {'1': 'MTV3_FRAGMENT_STORE_ACK', '2': 121},
    {'1': 'MTV3_FRAGMENT_RETRIEVE', '2': 122},
    {'1': 'MTV3_FRAGMENT_RETRIEVE_RESPONSE', '2': 123},
    {'1': 'MTV3_FRAGMENT_DELETE', '2': 124},
    {'1': 'MTV3_CHAT_CONFIG_UPDATE', '2': 140},
    {'1': 'MTV3_CHAT_CONFIG_RESPONSE', '2': 141},
    {'1': 'MTV3_IDENTITY_AUTH_PUBLISH', '2': 170},
    {'1': 'MTV3_IDENTITY_AUTH_RETRIEVE', '2': 171},
    {'1': 'MTV3_IDENTITY_AUTH_RESPONSE', '2': 172},
    {'1': 'MTV3_IDENTITY_LIVE_PUBLISH', '2': 173},
    {'1': 'MTV3_IDENTITY_LIVE_RETRIEVE', '2': 174},
    {'1': 'MTV3_IDENTITY_LIVE_RESPONSE', '2': 175},
    {'1': 'MTV3_TWIN_SYNC', '2': 180},
    {'1': 'MTV3_DEVICE_REVOCATION', '2': 183},
    {'1': 'MTV3_ROTATION_REJECTION_ALERT', '2': 184},
    {'1': 'MTV3_DEVICE_SET_ANNOUNCE', '2': 185},
    {'1': 'MTV3_CALENDAR_INVITE', '2': 190},
    {'1': 'MTV3_CALENDAR_RSVP', '2': 191},
    {'1': 'MTV3_CALENDAR_UPDATE', '2': 192},
    {'1': 'MTV3_CALENDAR_DELETE', '2': 193},
    {'1': 'MTV3_FREE_BUSY_REQUEST', '2': 194},
    {'1': 'MTV3_FREE_BUSY_RESPONSE', '2': 195},
    {'1': 'MTV3_POLL_CREATE', '2': 200},
    {'1': 'MTV3_POLL_VOTE', '2': 201},
    {'1': 'MTV3_POLL_VOTE_ANONYMOUS', '2': 202},
    {'1': 'MTV3_POLL_UPDATE', '2': 203},
    {'1': 'MTV3_POLL_SNAPSHOT', '2': 204},
    {'1': 'MTV3_POLL_REVOKE', '2': 205},
    {'1': 'MTV3_WHITEBOARD_STROKE', '2': 210},
    {'1': 'MTV3_WHITEBOARD_PAGE', '2': 211},
    {'1': 'MTV3_FILE_EXCHANGE', '2': 212},
    {'1': 'MTV3_CLIPBOARD_EXCHANGE', '2': 213},
    {'1': 'MTV3_SCREEN_SHARE_FRAME', '2': 214},
    {'1': 'MTV3_CALL_CHAT', '2': 215},
    {'1': 'MTV3_REMOTE_CONTROL_INPUT', '2': 216},
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
  '5': ['MTV3_RESTORE_BROADCAST', 'MTV3_RESTORE_RESPONSE', 'MTV3_GUARDIAN_SHARE_STORE', 'MTV3_GUARDIAN_RESTORE_REQUEST', 'MTV3_GUARDIAN_RESTORE_RESPONSE', 'MTV3_PEER_LIST_PUSH', 'MTV3_PEER_LIST_SUMMARY', 'MTV3_PEER_LIST_WANT', 'MTV3_PEER_KEY_REQUEST', 'MTV3_PEER_KEY_RESPONSE', 'MTV3_PEER_STORE', 'MTV3_PEER_STORE_ACK', 'MTV3_PEER_RETRIEVE', 'MTV3_PEER_RETRIEVE_RESPONSE', 'MTV3_ROUTE_UPDATE', 'MTV3_REACHABILITY_QUERY', 'MTV3_REACHABILITY_RESPONSE', 'MTV3_RELAY_FORWARD', 'MTV3_RELAY_ACK', 'MTV3_HOLE_PUNCH_REQUEST', 'MTV3_HOLE_PUNCH_NOTIFY', 'MTV3_HOLE_PUNCH_PING', 'MTV3_HOLE_PUNCH_PONG', 'MTV3_IDENTITY_KEM_PUBLISH', 'MTV3_IDENTITY_KEM_RETRIEVE', 'MTV3_IDENTITY_KEM_RESPONSE', 'MTV3_DEVICE_PAIR_REQUEST', 'MTV3_DEVICE_PAIR_APPROVE', 'MTV3_DEVICE_KEM_REQUEST', 'MTV3_DEVICE_KEM_OFFER', 'MTV3_FIRST_CR_STORE', 'MTV3_FIRST_CR_STORE_ACK', 'MTV3_FIRST_CR_DELIVER', 'MTV3_POLL_ANON_SUBMIT', 'MTV3_POLL_ANON_SUBMIT_ACK', 'MTV3_SYSCHAN_DIGEST', 'MTV3_SYSCHAN_SUMMARY', 'MTV3_SYSCHAN_WANT', 'MTV3_SYSCHAN_PUSH'],
};

/// Descriptor for `MessageTypeV3`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List messageTypeV3Descriptor = $convert.base64Decode(
    'Cg1NZXNzYWdlVHlwZVYzEg0KCU1UVjNfVEVYVBAAEhUKEU1UVjNfTUVESUFfSU5MSU5FEAESFw'
    'oTTVRWM19NRURJQV9BTk5PVU5DRRACEhYKEk1UVjNfTUVESUFfUkVRVUVTVBADEhQKEE1UVjNf'
    'TUVESUFfQ0hVTksQBBIXChNNVFYzX01FRElBX0NPTVBMRVRFEAUSFQoRTVRWM19NRURJQV9SRU'
    'pFQ1QQBhIRCg1NVFYzX1JFQUNUSU9OEAcSDgoKTVRWM19SRVBMWRAIEg0KCU1UVjNfRURJVBAJ'
    'Eg8KC01UVjNfREVMRVRFEAoSHQoZTVRWM19NRURJQV9TVFJFQU1fUkVRVUVTVBALEhsKF01UVj'
    'NfTUVESUFfU1RSRUFNX09GRkVSEAwSFgoSTVRWM19NRURJQV9IT0xERVJTEA0SFAoQTVRWM19N'
    'RURJQV9BQk9SVBAOEhkKFU1UVjNfVFlQSU5HX0lORElDQVRPUhAPEhUKEU1UVjNfUkVBRF9SRU'
    'NFSVBUEBASGQoVTVRWM19ERUxJVkVSWV9SRUNFSVBUEBESEQoNTVRWM19DQVRDSF9VUBASEhYK'
    'Ek1UVjNfVk9JQ0VfTUVTU0FHRRAWEhkKFU1UVjNfSURFTlRJVFlfREVMRVRFRBAgEhcKE01UVj'
    'NfUFJPRklMRV9VUERBVEUQIRIfChtNVFYzX0tFWV9ST1RBVElPTl9CUk9BRENBU1QQIhIZChVN'
    'VFYzX0tFWV9ST1RBVElPTl9BQ0sQJhIYChRNVFYzX0NPTlRBQ1RfUkVRVUVTVBAoEiEKHU1UVj'
    'NfQ09OVEFDVF9SRVFVRVNUX1JFU1BPTlNFECkSFQoRTVRWM19HUk9VUF9DUkVBVEUQMhIVChFN'
    'VFYzX0dST1VQX0lOVklURRAzEhQKEE1UVjNfR1JPVVBfTEVBVkUQNBIZChVNVFYzX0dST1VQX0'
    'tFWV9VUERBVEUQNRIoCiRNVFYzX0dST1VQX01FTUJFUlNISVBfUkVTWU5DX1JFUVVFU1QQNhIT'
    'Cg9NVFYzX0dST1VQX0pPSU4QNxIXChNNVFYzX0NIQU5ORUxfQ1JFQVRFEDwSFQoRTVRWM19DSE'
    'FOTkVMX1BPU1QQPRIXChNNVFYzX0NIQU5ORUxfSU5WSVRFED4SFgoSTVRWM19DSEFOTkVMX0xF'
    'QVZFED8SHAoYTVRWM19DSEFOTkVMX1JPTEVfVVBEQVRFEEASIQodTVRWM19DSEFOTkVMX0JBRF'
    '9CQURHRV9SRVBPUlQQQRIaChZNVFYzX0NIQU5ORUxfSlVSWV9WT1RFEEISHQoZTVRWM19DSEFO'
    'TkVMX01PRF9ERUNJU0lPThBDEiAKHE1UVjNfQ0hBTk5FTF9TVUJTQ1JJQkVfUFJPQkUQRBIUCh'
    'BNVFYzX0NBTExfSU5WSVRFEEYSFAoQTVRWM19DQUxMX0FOU1dFUhBHEhQKEE1UVjNfQ0FMTF9S'
    'RUpFQ1QQSBIUChBNVFYzX0NBTExfSEFOR1VQEEkSFgoSTVRWM19JQ0VfQ0FORElEQVRFEEoSFA'
    'oQTVRWM19DQUxMX1JFSk9JThBLEhMKD01UVjNfQ0FMTF9BVURJTxBMEhMKD01UVjNfQ0FMTF9W'
    'SURFTxBNEhkKFU1UVjNfQ0FMTF9HUk9VUF9BVURJTxBOEhkKFU1UVjNfQ0FMTF9HUk9VUF9WSU'
    'RFTxBPEhkKFU1UVjNfQ0FMTF9HUk9VUF9MRUFWRRBQEhYKEk1UVjNfQ0FMTF9SVFRfUElORxBS'
    'EhYKEk1UVjNfQ0FMTF9SVFRfUE9ORxBTEhkKFU1UVjNfQ0FMTF9UUkVFX1VQREFURRBUEh4KGk'
    '1UVjNfQ0FMTF9LRVlGUkFNRV9SRVFVRVNUEFUSHgoaTVRWM19DQUxMX0dST1VQX1NFTkRFUl9L'
    'RVkQVhIZChVNVFYzX0NBTExfTUVESUFfU1RBVEUQVxIbChdNVFYzX0NBTExfQ0FOQ0VMX09USE'
    'VSUxBYEhYKEk1UVjNfQ0FMTF9SSU5HX0FDSxBZEh8KG01UVjNfQ0hBTk5FTF9JTkRFWF9FWENI'
    'QU5HRRBaEh0KGU1UVjNfQ0hBTk5FTF9KT0lOX1JFUVVFU1QQWxIXChNNVFYzX0NIQU5ORUxfUk'
    'VQT1JUEFwSEQoNTVRWM19ESFRfUElORxBuEhEKDU1UVjNfREhUX1BPTkcQbxIWChJNVFYzX0RI'
    'VF9GSU5EX05PREUQcBIfChtNVFYzX0RIVF9GSU5EX05PREVfUkVTUE9OU0UQcRISCg5NVFYzX0'
    'RIVF9TVE9SRRByEhsKF01UVjNfREhUX1NUT1JFX1JFU1BPTlNFEHMSFwoTTVRWM19ESFRfRklO'
    'RF9WQUxVRRB0EiAKHE1UVjNfREhUX0ZJTkRfVkFMVUVfUkVTUE9OU0UQdRIXChNNVFYzX0ZSQU'
    'dNRU5UX1NUT1JFEHgSGwoXTVRWM19GUkFHTUVOVF9TVE9SRV9BQ0sQeRIaChZNVFYzX0ZSQUdN'
    'RU5UX1JFVFJJRVZFEHoSIwofTVRWM19GUkFHTUVOVF9SRVRSSUVWRV9SRVNQT05TRRB7EhgKFE'
    '1UVjNfRlJBR01FTlRfREVMRVRFEHwSHAoXTVRWM19DSEFUX0NPTkZJR19VUERBVEUQjAESHgoZ'
    'TVRWM19DSEFUX0NPTkZJR19SRVNQT05TRRCNARIfChpNVFYzX0lERU5USVRZX0FVVEhfUFVCTE'
    'lTSBCqARIgChtNVFYzX0lERU5USVRZX0FVVEhfUkVUUklFVkUQqwESIAobTVRWM19JREVOVElU'
    'WV9BVVRIX1JFU1BPTlNFEKwBEh8KGk1UVjNfSURFTlRJVFlfTElWRV9QVUJMSVNIEK0BEiAKG0'
    '1UVjNfSURFTlRJVFlfTElWRV9SRVRSSUVWRRCuARIgChtNVFYzX0lERU5USVRZX0xJVkVfUkVT'
    'UE9OU0UQrwESEwoOTVRWM19UV0lOX1NZTkMQtAESGwoWTVRWM19ERVZJQ0VfUkVWT0NBVElPTh'
    'C3ARIiCh1NVFYzX1JPVEFUSU9OX1JFSkVDVElPTl9BTEVSVBC4ARIdChhNVFYzX0RFVklDRV9T'
    'RVRfQU5OT1VOQ0UQuQESGQoUTVRWM19DQUxFTkRBUl9JTlZJVEUQvgESFwoSTVRWM19DQUxFTk'
    'RBUl9SU1ZQEL8BEhkKFE1UVjNfQ0FMRU5EQVJfVVBEQVRFEMABEhkKFE1UVjNfQ0FMRU5EQVJf'
    'REVMRVRFEMEBEhsKFk1UVjNfRlJFRV9CVVNZX1JFUVVFU1QQwgESHAoXTVRWM19GUkVFX0JVU1'
    'lfUkVTUE9OU0UQwwESFQoQTVRWM19QT0xMX0NSRUFURRDIARITCg5NVFYzX1BPTExfVk9URRDJ'
    'ARIdChhNVFYzX1BPTExfVk9URV9BTk9OWU1PVVMQygESFQoQTVRWM19QT0xMX1VQREFURRDLAR'
    'IXChJNVFYzX1BPTExfU05BUFNIT1QQzAESFQoQTVRWM19QT0xMX1JFVk9LRRDNARIbChZNVFYz'
    'X1dISVRFQk9BUkRfU1RST0tFENIBEhkKFE1UVjNfV0hJVEVCT0FSRF9QQUdFENMBEhcKEk1UVj'
    'NfRklMRV9FWENIQU5HRRDUARIcChdNVFYzX0NMSVBCT0FSRF9FWENIQU5HRRDVARIcChdNVFYz'
    'X1NDUkVFTl9TSEFSRV9GUkFNRRDWARITCg5NVFYzX0NBTExfQ0hBVBDXARIeChlNVFYzX1JFTU'
    '9URV9DT05UUk9MX0lOUFVUENgBIgQIHhAeIgQIHxAfIgQIIxAjIgQIJBAkIgQIJRAlIgQIURBR'
    'IgQIZBBkIgQIZRBlIgQIZhBmIgQIZxBnIgQIaBBoIgYIggEQggEiBgiDARCDASIGCIQBEIQBIg'
    'YIhQEQhQEiBgiWARCWASIGCJcBEJcBIgYImAEQmAEiBgiZARCZASIGCJoBEJoBIgYIoAEQoAEi'
    'BgihARChASIGCKIBEKIBIgYIowEQowEiBgiwARCwASIGCLEBELEBIgYIsgEQsgEiBgi1ARC1AS'
    'IGCLYBELYBIgYI3AEQ3AEiBgjdARDdASIGCN4BEN4BIgYI3wEQ3wEiBgjgARDgASIGCOEBEOEB'
    'IgYI4gEQ4gEiBgjmARDmASIGCOcBEOcBIgYI6AEQ6AEiBgjpARDpASoWTVRWM19SRVNUT1JFX0'
    'JST0FEQ0FTVCoVTVRWM19SRVNUT1JFX1JFU1BPTlNFKhlNVFYzX0dVQVJESUFOX1NIQVJFX1NU'
    'T1JFKh1NVFYzX0dVQVJESUFOX1JFU1RPUkVfUkVRVUVTVCoeTVRWM19HVUFSRElBTl9SRVNUT1'
    'JFX1JFU1BPTlNFKhNNVFYzX1BFRVJfTElTVF9QVVNIKhZNVFYzX1BFRVJfTElTVF9TVU1NQVJZ'
    'KhNNVFYzX1BFRVJfTElTVF9XQU5UKhVNVFYzX1BFRVJfS0VZX1JFUVVFU1QqFk1UVjNfUEVFUl'
    '9LRVlfUkVTUE9OU0UqD01UVjNfUEVFUl9TVE9SRSoTTVRWM19QRUVSX1NUT1JFX0FDSyoSTVRW'
    'M19QRUVSX1JFVFJJRVZFKhtNVFYzX1BFRVJfUkVUUklFVkVfUkVTUE9OU0UqEU1UVjNfUk9VVE'
    'VfVVBEQVRFKhdNVFYzX1JFQUNIQUJJTElUWV9RVUVSWSoaTVRWM19SRUFDSEFCSUxJVFlfUkVT'
    'UE9OU0UqEk1UVjNfUkVMQVlfRk9SV0FSRCoOTVRWM19SRUxBWV9BQ0sqF01UVjNfSE9MRV9QVU'
    '5DSF9SRVFVRVNUKhZNVFYzX0hPTEVfUFVOQ0hfTk9USUZZKhRNVFYzX0hPTEVfUFVOQ0hfUElO'
    'RyoUTVRWM19IT0xFX1BVTkNIX1BPTkcqGU1UVjNfSURFTlRJVFlfS0VNX1BVQkxJU0gqGk1UVj'
    'NfSURFTlRJVFlfS0VNX1JFVFJJRVZFKhpNVFYzX0lERU5USVRZX0tFTV9SRVNQT05TRSoYTVRW'
    'M19ERVZJQ0VfUEFJUl9SRVFVRVNUKhhNVFYzX0RFVklDRV9QQUlSX0FQUFJPVkUqF01UVjNfRE'
    'VWSUNFX0tFTV9SRVFVRVNUKhVNVFYzX0RFVklDRV9LRU1fT0ZGRVIqE01UVjNfRklSU1RfQ1Jf'
    'U1RPUkUqF01UVjNfRklSU1RfQ1JfU1RPUkVfQUNLKhVNVFYzX0ZJUlNUX0NSX0RFTElWRVIqFU'
    '1UVjNfUE9MTF9BTk9OX1NVQk1JVCoZTVRWM19QT0xMX0FOT05fU1VCTUlUX0FDSyoTTVRWM19T'
    'WVNDSEFOX0RJR0VTVCoUTVRWM19TWVNDSEFOX1NVTU1BUlkqEU1UVjNfU1lTQ0hBTl9XQU5UKh'
    'FNVFYzX1NZU0NIQU5fUFVTSA==');

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
    {'1': 'kem_record', '3': 6, '4': 1, '5': 11, '6': '.cleona.DeviceKemRecordV3', '10': 'kemRecord'},
  ],
};

/// Descriptor for `DhtPong`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List dhtPongDescriptor = $convert.base64Decode(
    'CgdEaHRQb25nEhsKCXNlbmRlcl9pZBgBIAEoDFIIc2VuZGVySWQSHAoJdGltZXN0YW1wGAIgAS'
    'gEUgl0aW1lc3RhbXASHwoLb2JzZXJ2ZWRfaXAYAyABKAlSCm9ic2VydmVkSXASIwoNb2JzZXJ2'
    'ZWRfcG9ydBgEIAEoDVIMb2JzZXJ2ZWRQb3J0Ei4KE2FkZGl0aW9uYWxfbm9kZV9pZHMYBSADKA'
    'xSEWFkZGl0aW9uYWxOb2RlSWRzEjgKCmtlbV9yZWNvcmQYBiABKAsyGS5jbGVvbmEuRGV2aWNl'
    'S2VtUmVjb3JkVjNSCWtlbVJlY29yZA==');

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

@$core.Deprecated('Use networkPacketV3Descriptor instead')
const NetworkPacketV3$json = {
  '1': 'NetworkPacketV3',
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
    {'1': 'payload_type', '3': 12, '4': 1, '5': 14, '6': '.cleona.PayloadTypeV3', '10': 'payloadType'},
    {'1': 'payload', '3': 13, '4': 1, '5': 12, '10': 'payload'},
  ],
  '9': [
    {'1': 14, '2': 15},
    {'1': 15, '2': 16},
  ],
  '10': ['visited_device_ids', 'sender_data_port'],
};

/// Descriptor for `NetworkPacketV3`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List networkPacketV3Descriptor = $convert.base64Decode(
    'Cg9OZXR3b3JrUGFja2V0VjMSGAoHdmVyc2lvbhgBIAEoDVIHdmVyc2lvbhIUCgVmbGFncxgCIA'
    'EoDVIFZmxhZ3MSKwoSbmV4dF9ob3BfZGV2aWNlX2lkGAMgASgMUg9uZXh0SG9wRGV2aWNlSWQS'
    'KAoQc2VuZGVyX2RldmljZV9pZBgEIAEoDFIOc2VuZGVyRGV2aWNlSWQSIQoMdGltZXN0YW1wX2'
    '1zGAUgASgEUgt0aW1lc3RhbXBNcxIQCgN0dGwYBiABKA1SA3R0bBIbCglob3BfY291bnQYByAB'
    'KA1SCGhvcENvdW50Eh8KC25ldHdvcmtfdGFnGAggASgMUgpuZXR3b3JrVGFnEiUKA3BvdxgJIA'
    'EoCzITLmNsZW9uYS5Qcm9vZk9mV29ya1IDcG93EiwKEmRldmljZV9lZDI1NTE5X3NpZxgKIAEo'
    'DFIQZGV2aWNlRWQyNTUxOVNpZxIpChFkZXZpY2VfbWxfZHNhX3NpZxgLIAEoDFIOZGV2aWNlTW'
    'xEc2FTaWcSOAoMcGF5bG9hZF90eXBlGAwgASgOMhUuY2xlb25hLlBheWxvYWRUeXBlVjNSC3Bh'
    'eWxvYWRUeXBlEhgKB3BheWxvYWQYDSABKAxSB3BheWxvYWRKBAgOEA9KBAgPEBBSEnZpc2l0ZW'
    'RfZGV2aWNlX2lkc1IQc2VuZGVyX2RhdGFfcG9ydA==');

@$core.Deprecated('Use applicationFrameV3Descriptor instead')
const ApplicationFrameV3$json = {
  '1': 'ApplicationFrameV3',
  '2': [
    {'1': 'recipient_user_id', '3': 2, '4': 1, '5': 12, '10': 'recipientUserId'},
    {'1': 'sender_user_id', '3': 3, '4': 1, '5': 12, '10': 'senderUserId'},
    {'1': 'timestamp_ms', '3': 4, '4': 1, '5': 4, '10': 'timestampMs'},
    {'1': 'message_id', '3': 5, '4': 1, '5': 12, '10': 'messageId'},
    {'1': 'message_type', '3': 6, '4': 1, '5': 14, '6': '.cleona.MessageTypeV3', '10': 'messageType'},
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

/// Descriptor for `ApplicationFrameV3`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List applicationFrameV3Descriptor = $convert.base64Decode(
    'ChJBcHBsaWNhdGlvbkZyYW1lVjMSKgoRcmVjaXBpZW50X3VzZXJfaWQYAiABKAxSD3JlY2lwaW'
    'VudFVzZXJJZBIkCg5zZW5kZXJfdXNlcl9pZBgDIAEoDFIMc2VuZGVyVXNlcklkEiEKDHRpbWVz'
    'dGFtcF9tcxgEIAEoBFILdGltZXN0YW1wTXMSHQoKbWVzc2FnZV9pZBgFIAEoDFIJbWVzc2FnZU'
    'lkEjgKDG1lc3NhZ2VfdHlwZRgGIAEoDjIVLmNsZW9uYS5NZXNzYWdlVHlwZVYzUgttZXNzYWdl'
    'VHlwZRIYCgdwYXlsb2FkGAcgASgMUgdwYXlsb2FkEigKEHVzZXJfZWQyNTUxOV9zaWcYCiABKA'
    'xSDnVzZXJFZDI1NTE5U2lnEiUKD3VzZXJfbWxfZHNhX3NpZxgLIAEoDFIMdXNlck1sRHNhU2ln'
    'EkIKEGNvbnRlbnRfbWV0YWRhdGEYDCABKAsyFy5jbGVvbmEuQ29udGVudE1ldGFkYXRhUg9jb2'
    '50ZW50TWV0YWRhdGESOQoNZWRpdF9tZXRhZGF0YRgNIAEoCzIULmNsZW9uYS5FZGl0TWV0YWRh'
    'dGFSDGVkaXRNZXRhZGF0YRI/Cg9leHBpcnlfbWV0YWRhdGEYDiABKAsyFi5jbGVvbmEuRXhwaX'
    'J5TWV0YWRhdGFSDmV4cGlyeU1ldGFkYXRhEkgKEGVyYXN1cmVfbWV0YWRhdGEYDyABKAsyHS5j'
    'bGVvbmEuRXJhc3VyZUNvZGluZ01ldGFkYXRhUg9lcmFzdXJlTWV0YWRhdGESOQoLY29tcHJlc3'
    'Npb24YECABKA4yFy5jbGVvbmEuQ29tcHJlc3Npb25UeXBlUgtjb21wcmVzc2lvbhIZCghncm91'
    'cF9pZBgRIAEoDFIHZ3JvdXBJZBI0ChZncm91cF9tZW1iZXJzaGlwX2Vwb2NoGBIgASgEUhRncm'
    '91cE1lbWJlcnNoaXBFcG9jaBIyChVncm91cF9tZW1iZXJzaGlwX2hhc2gYEyABKAxSE2dyb3Vw'
    'TWVtYmVyc2hpcEhhc2gSHQoKYWZ0ZXJfZmlsZRgUIAEoDFIJYWZ0ZXJGaWxlEhcKB3Bvc3RfaW'
    'QYFSABKAxSBnBvc3RJZEoECAEQAlIHdmVyc2lvbg==');

@$core.Deprecated('Use perMessageKemV3Descriptor instead')
const PerMessageKemV3$json = {
  '1': 'PerMessageKemV3',
  '2': [
    {'1': 'x25519_ciphertext', '3': 1, '4': 1, '5': 12, '10': 'x25519Ciphertext'},
    {'1': 'ml_kem_ciphertext', '3': 2, '4': 1, '5': 12, '10': 'mlKemCiphertext'},
    {'1': 'aead_ciphertext', '3': 3, '4': 1, '5': 12, '10': 'aeadCiphertext'},
    {'1': 'aead_nonce', '3': 4, '4': 1, '5': 12, '10': 'aeadNonce'},
    {'1': 'version', '3': 5, '4': 1, '5': 13, '10': 'version'},
  ],
};

/// Descriptor for `PerMessageKemV3`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List perMessageKemV3Descriptor = $convert.base64Decode(
    'Cg9QZXJNZXNzYWdlS2VtVjMSKwoReDI1NTE5X2NpcGhlcnRleHQYASABKAxSEHgyNTUxOUNpcG'
    'hlcnRleHQSKgoRbWxfa2VtX2NpcGhlcnRleHQYAiABKAxSD21sS2VtQ2lwaGVydGV4dBInCg9h'
    'ZWFkX2NpcGhlcnRleHQYAyABKAxSDmFlYWRDaXBoZXJ0ZXh0Eh0KCmFlYWRfbm9uY2UYBCABKA'
    'xSCWFlYWROb25jZRIYCgd2ZXJzaW9uGAUgASgNUgd2ZXJzaW9u');

@$core.Deprecated('Use authManifestV3Descriptor instead')
const AuthManifestV3$json = {
  '1': 'AuthManifestV3',
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

/// Descriptor for `AuthManifestV3`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List authManifestV3Descriptor = $convert.base64Decode(
    'Cg5BdXRoTWFuaWZlc3RWMxIXCgd1c2VyX2lkGAEgASgMUgZ1c2VySWQSMgoVYXV0aG9yaXplZF'
    '9kZXZpY2VfaWRzGAIgAygMUhNhdXRob3JpemVkRGV2aWNlSWRzEh8KC3R0bF9zZWNvbmRzGAMg'
    'ASgEUgp0dGxTZWNvbmRzEicKD3NlcXVlbmNlX251bWJlchgEIAEoBFIOc2VxdWVuY2VOdW1iZX'
    'ISJgoPcHVibGlzaGVkX2F0X21zGAUgASgEUg1wdWJsaXNoZWRBdE1zEh8KC2VkMjU1MTlfc2ln'
    'GAYgASgMUgplZDI1NTE5U2lnEhwKCm1sX2RzYV9zaWcYByABKAxSCG1sRHNhU2lnEiYKD3VzZX'
    'JfZWQyNTUxOV9waxgIIAEoDFINdXNlckVkMjU1MTlQaxIjCg51c2VyX21sX2RzYV9waxgJIAEo'
    'DFILdXNlck1sRHNhUGs=');

@$core.Deprecated('Use livenessRecordV3Descriptor instead')
const LivenessRecordV3$json = {
  '1': 'LivenessRecordV3',
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

/// Descriptor for `LivenessRecordV3`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List livenessRecordV3Descriptor = $convert.base64Decode(
    'ChBMaXZlbmVzc1JlY29yZFYzEhcKB3VzZXJfaWQYASABKAxSBnVzZXJJZBIkCg5kZXZpY2Vfbm'
    '9kZV9pZBgCIAEoDFIMZGV2aWNlTm9kZUlkEjYKCWFkZHJlc3NlcxgDIAMoCzIYLmNsZW9uYS5Q'
    'ZWVyQWRkcmVzc1Byb3RvUglhZGRyZXNzZXMSHwoLdHRsX3NlY29uZHMYBCABKARSCnR0bFNlY2'
    '9uZHMSJwoPc2VxdWVuY2VfbnVtYmVyGAUgASgEUg5zZXF1ZW5jZU51bWJlchImCg9wdWJsaXNo'
    'ZWRfYXRfbXMYBiABKARSDXB1Ymxpc2hlZEF0TXMSHwoLZWQyNTUxOV9zaWcYByABKAxSCmVkMj'
    'U1MTlTaWcSKgoRZGV2aWNlX2VkMjU1MTlfcGsYCCABKAxSD2RldmljZUVkMjU1MTlQaw==');

@$core.Deprecated('Use deviceKemRecordV3Descriptor instead')
const DeviceKemRecordV3$json = {
  '1': 'DeviceKemRecordV3',
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

/// Descriptor for `DeviceKemRecordV3`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deviceKemRecordV3Descriptor = $convert.base64Decode(
    'ChFEZXZpY2VLZW1SZWNvcmRWMxIXCgd1c2VyX2lkGAEgASgMUgZ1c2VySWQSGwoJZGV2aWNlX2'
    'lkGAIgASgMUghkZXZpY2VJZBIoChBkZXZpY2VfeDI1NTE5X3BrGAMgASgMUg5kZXZpY2VYMjU1'
    'MTlQaxInChBkZXZpY2VfbWxfa2VtX3BrGAQgASgMUg1kZXZpY2VNbEtlbVBrEh8KC3R0bF9zZW'
    'NvbmRzGAUgASgEUgp0dGxTZWNvbmRzEicKD3NlcXVlbmNlX251bWJlchgGIAEoBFIOc2VxdWVu'
    'Y2VOdW1iZXISJgoPcHVibGlzaGVkX2F0X21zGAcgASgEUg1wdWJsaXNoZWRBdE1zEh8KC2VkMj'
    'U1MTlfc2lnGAggASgMUgplZDI1NTE5U2lnEiYKD3VzZXJfZWQyNTUxOV9waxgJIAEoDFINdXNl'
    'ckVkMjU1MTlQaxIqChFzaWduZXJfZWQyNTUxOV9waxgKIAEoDFIPc2lnbmVyRWQyNTUxOVBrSg'
    'QICxAM');

@$core.Deprecated('Use peerListEntryV3Descriptor instead')
const PeerListEntryV3$json = {
  '1': 'PeerListEntryV3',
  '2': [
    {'1': 'device_id', '3': 1, '4': 1, '5': 12, '10': 'deviceId'},
    {'1': 'addresses', '3': 2, '4': 3, '5': 11, '6': '.cleona.PeerAddressProto', '10': 'addresses'},
    {'1': 'last_seen_ms', '3': 3, '4': 1, '5': 4, '10': 'lastSeenMs'},
    {'1': 'age_hours', '3': 4, '4': 1, '5': 4, '10': 'ageHours'},
    {'1': 'connection_type', '3': 5, '4': 1, '5': 14, '6': '.cleona.ConnectionTypeProto', '10': 'connectionType'},
  ],
};

/// Descriptor for `PeerListEntryV3`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List peerListEntryV3Descriptor = $convert.base64Decode(
    'Cg9QZWVyTGlzdEVudHJ5VjMSGwoJZGV2aWNlX2lkGAEgASgMUghkZXZpY2VJZBI2CglhZGRyZX'
    'NzZXMYAiADKAsyGC5jbGVvbmEuUGVlckFkZHJlc3NQcm90b1IJYWRkcmVzc2VzEiAKDGxhc3Rf'
    'c2Vlbl9tcxgDIAEoBFIKbGFzdFNlZW5NcxIbCglhZ2VfaG91cnMYBCABKARSCGFnZUhvdXJzEk'
    'QKD2Nvbm5lY3Rpb25fdHlwZRgFIAEoDjIbLmNsZW9uYS5Db25uZWN0aW9uVHlwZVByb3RvUg5j'
    'b25uZWN0aW9uVHlwZQ==');

@$core.Deprecated('Use relayForwardV3Descriptor instead')
const RelayForwardV3$json = {
  '1': 'RelayForwardV3',
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

/// Descriptor for `RelayForwardV3`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List relayForwardV3Descriptor = $convert.base64Decode(
    'Cg5SZWxheUZvcndhcmRWMxIZCghyZWxheV9pZBgBIAEoDFIHcmVsYXlJZBIsChJmaW5hbF9yZW'
    'NpcGllbnRfaWQYAiABKAxSEGZpbmFsUmVjaXBpZW50SWQSJQoOd3JhcHBlZF9wYWNrZXQYAyAB'
    'KAxSDXdyYXBwZWRQYWNrZXQSGwoJaG9wX2NvdW50GAQgASgNUghob3BDb3VudBIZCghtYXhfaG'
    '9wcxgFIAEoDVIHbWF4SG9wcxIQCgN0dGwYBiABKA1SA3R0bBIoChBvcmlnaW5fZGV2aWNlX2lk'
    'GAcgASgMUg5vcmlnaW5EZXZpY2VJZBIiCg1jcmVhdGVkX2F0X21zGAggASgEUgtjcmVhdGVkQX'
    'RNcxIYCgd2aXNpdGVkGAkgAygMUgd2aXNpdGVk');

@$core.Deprecated('Use deviceKemRequestV3Descriptor instead')
const DeviceKemRequestV3$json = {
  '1': 'DeviceKemRequestV3',
  '2': [
    {'1': 'target_user_id', '3': 1, '4': 1, '5': 12, '10': 'targetUserId'},
    {'1': 'target_device_id', '3': 2, '4': 1, '5': 12, '10': 'targetDeviceId'},
    {'1': 'nonce', '3': 3, '4': 1, '5': 12, '10': 'nonce'},
    {'1': 'timestamp_ms', '3': 4, '4': 1, '5': 4, '10': 'timestampMs'},
  ],
};

/// Descriptor for `DeviceKemRequestV3`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deviceKemRequestV3Descriptor = $convert.base64Decode(
    'ChJEZXZpY2VLZW1SZXF1ZXN0VjMSJAoOdGFyZ2V0X3VzZXJfaWQYASABKAxSDHRhcmdldFVzZX'
    'JJZBIoChB0YXJnZXRfZGV2aWNlX2lkGAIgASgMUg50YXJnZXREZXZpY2VJZBIUCgVub25jZRgD'
    'IAEoDFIFbm9uY2USIQoMdGltZXN0YW1wX21zGAQgASgEUgt0aW1lc3RhbXBNcw==');

@$core.Deprecated('Use deviceKemOfferV3Descriptor instead')
const DeviceKemOfferV3$json = {
  '1': 'DeviceKemOfferV3',
  '2': [
    {'1': 'device_x25519_pk', '3': 1, '4': 1, '5': 12, '10': 'deviceX25519Pk'},
    {'1': 'device_ml_kem_pk', '3': 2, '4': 1, '5': 12, '10': 'deviceMlKemPk'},
    {'1': 'nonce', '3': 3, '4': 1, '5': 12, '10': 'nonce'},
    {'1': 'user_ed25519_sig', '3': 4, '4': 1, '5': 12, '10': 'userEd25519Sig'},
    {'1': 'timestamp_ms', '3': 5, '4': 1, '5': 4, '10': 'timestampMs'},
  ],
};

/// Descriptor for `DeviceKemOfferV3`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deviceKemOfferV3Descriptor = $convert.base64Decode(
    'ChBEZXZpY2VLZW1PZmZlclYzEigKEGRldmljZV94MjU1MTlfcGsYASABKAxSDmRldmljZVgyNT'
    'UxOVBrEicKEGRldmljZV9tbF9rZW1fcGsYAiABKAxSDWRldmljZU1sS2VtUGsSFAoFbm9uY2UY'
    'AyABKAxSBW5vbmNlEigKEHVzZXJfZWQyNTUxOV9zaWcYBCABKAxSDnVzZXJFZDI1NTE5U2lnEi'
    'EKDHRpbWVzdGFtcF9tcxgFIAEoBFILdGltZXN0YW1wTXM=');

@$core.Deprecated('Use firstCrStoreV3Descriptor instead')
const FirstCrStoreV3$json = {
  '1': 'FirstCrStoreV3',
  '2': [
    {'1': 'recipient_user_id', '3': 1, '4': 1, '5': 12, '10': 'recipientUserId'},
    {'1': 'recipient_device_id', '3': 2, '4': 1, '5': 12, '10': 'recipientDeviceId'},
    {'1': 'encrypted_cr_blob', '3': 3, '4': 1, '5': 12, '10': 'encryptedCrBlob'},
    {'1': 'sender_device_id', '3': 4, '4': 1, '5': 12, '10': 'senderDeviceId'},
    {'1': 'timestamp_ms', '3': 5, '4': 1, '5': 4, '10': 'timestampMs'},
    {'1': 'ttl_ms', '3': 6, '4': 1, '5': 4, '10': 'ttlMs'},
  ],
};

/// Descriptor for `FirstCrStoreV3`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List firstCrStoreV3Descriptor = $convert.base64Decode(
    'Cg5GaXJzdENyU3RvcmVWMxIqChFyZWNpcGllbnRfdXNlcl9pZBgBIAEoDFIPcmVjaXBpZW50VX'
    'NlcklkEi4KE3JlY2lwaWVudF9kZXZpY2VfaWQYAiABKAxSEXJlY2lwaWVudERldmljZUlkEioK'
    'EWVuY3J5cHRlZF9jcl9ibG9iGAMgASgMUg9lbmNyeXB0ZWRDckJsb2ISKAoQc2VuZGVyX2Rldm'
    'ljZV9pZBgEIAEoDFIOc2VuZGVyRGV2aWNlSWQSIQoMdGltZXN0YW1wX21zGAUgASgEUgt0aW1l'
    'c3RhbXBNcxIVCgZ0dGxfbXMYBiABKARSBXR0bE1z');

@$core.Deprecated('Use firstCrStoreAckV3Descriptor instead')
const FirstCrStoreAckV3$json = {
  '1': 'FirstCrStoreAckV3',
  '2': [
    {'1': 'accepted', '3': 1, '4': 1, '5': 8, '10': 'accepted'},
    {'1': 'reject_reason', '3': 2, '4': 1, '5': 9, '10': 'rejectReason'},
    {'1': 'recipient_user_id', '3': 3, '4': 1, '5': 12, '10': 'recipientUserId'},
  ],
};

/// Descriptor for `FirstCrStoreAckV3`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List firstCrStoreAckV3Descriptor = $convert.base64Decode(
    'ChFGaXJzdENyU3RvcmVBY2tWMxIaCghhY2NlcHRlZBgBIAEoCFIIYWNjZXB0ZWQSIwoNcmVqZW'
    'N0X3JlYXNvbhgCIAEoCVIMcmVqZWN0UmVhc29uEioKEXJlY2lwaWVudF91c2VyX2lkGAMgASgM'
    'Ug9yZWNpcGllbnRVc2VySWQ=');

@$core.Deprecated('Use firstCrDeliverV3Descriptor instead')
const FirstCrDeliverV3$json = {
  '1': 'FirstCrDeliverV3',
  '2': [
    {'1': 'encrypted_cr_blob', '3': 1, '4': 1, '5': 12, '10': 'encryptedCrBlob'},
    {'1': 'sender_device_id', '3': 2, '4': 1, '5': 12, '10': 'senderDeviceId'},
    {'1': 'stored_at_ms', '3': 3, '4': 1, '5': 4, '10': 'storedAtMs'},
  ],
};

/// Descriptor for `FirstCrDeliverV3`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List firstCrDeliverV3Descriptor = $convert.base64Decode(
    'ChBGaXJzdENyRGVsaXZlclYzEioKEWVuY3J5cHRlZF9jcl9ibG9iGAEgASgMUg9lbmNyeXB0ZW'
    'RDckJsb2ISKAoQc2VuZGVyX2RldmljZV9pZBgCIAEoDFIOc2VuZGVyRGV2aWNlSWQSIAoMc3Rv'
    'cmVkX2F0X21zGAMgASgEUgpzdG9yZWRBdE1z');


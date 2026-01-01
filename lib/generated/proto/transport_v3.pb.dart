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

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'app_payloads.pb.dart' as $0;
import 'transport_v3.pbenum.dart';

export 'transport_v3.pbenum.dart';

class ErasureCodingMetadata extends $pb.GeneratedMessage {
  factory ErasureCodingMetadata({
    $core.List<$core.int>? mailboxId,
    $core.List<$core.int>? originalMessageId,
    $core.int? fragmentIndex,
    $core.int? totalFragments,
    $core.int? requiredFragments,
    $core.int? originalSize,
  }) {
    final $result = create();
    if (mailboxId != null) {
      $result.mailboxId = mailboxId;
    }
    if (originalMessageId != null) {
      $result.originalMessageId = originalMessageId;
    }
    if (fragmentIndex != null) {
      $result.fragmentIndex = fragmentIndex;
    }
    if (totalFragments != null) {
      $result.totalFragments = totalFragments;
    }
    if (requiredFragments != null) {
      $result.requiredFragments = requiredFragments;
    }
    if (originalSize != null) {
      $result.originalSize = originalSize;
    }
    return $result;
  }
  ErasureCodingMetadata._() : super();
  factory ErasureCodingMetadata.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ErasureCodingMetadata.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ErasureCodingMetadata', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'mailboxId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'originalMessageId', $pb.PbFieldType.OY)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'fragmentIndex', $pb.PbFieldType.OU3)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'totalFragments', $pb.PbFieldType.OU3)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'requiredFragments', $pb.PbFieldType.OU3)
    ..a<$core.int>(6, _omitFieldNames ? '' : 'originalSize', $pb.PbFieldType.OU3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ErasureCodingMetadata clone() => ErasureCodingMetadata()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ErasureCodingMetadata copyWith(void Function(ErasureCodingMetadata) updates) => super.copyWith((message) => updates(message as ErasureCodingMetadata)) as ErasureCodingMetadata;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ErasureCodingMetadata create() => ErasureCodingMetadata._();
  ErasureCodingMetadata createEmptyInstance() => create();
  static $pb.PbList<ErasureCodingMetadata> createRepeated() => $pb.PbList<ErasureCodingMetadata>();
  @$core.pragma('dart2js:noInline')
  static ErasureCodingMetadata getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ErasureCodingMetadata>(create);
  static ErasureCodingMetadata? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get mailboxId => $_getN(0);
  @$pb.TagNumber(1)
  set mailboxId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMailboxId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMailboxId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get originalMessageId => $_getN(1);
  @$pb.TagNumber(2)
  set originalMessageId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasOriginalMessageId() => $_has(1);
  @$pb.TagNumber(2)
  void clearOriginalMessageId() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get fragmentIndex => $_getIZ(2);
  @$pb.TagNumber(3)
  set fragmentIndex($core.int v) { $_setUnsignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasFragmentIndex() => $_has(2);
  @$pb.TagNumber(3)
  void clearFragmentIndex() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get totalFragments => $_getIZ(3);
  @$pb.TagNumber(4)
  set totalFragments($core.int v) { $_setUnsignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTotalFragments() => $_has(3);
  @$pb.TagNumber(4)
  void clearTotalFragments() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get requiredFragments => $_getIZ(4);
  @$pb.TagNumber(5)
  set requiredFragments($core.int v) { $_setUnsignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasRequiredFragments() => $_has(4);
  @$pb.TagNumber(5)
  void clearRequiredFragments() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get originalSize => $_getIZ(5);
  @$pb.TagNumber(6)
  set originalSize($core.int v) { $_setUnsignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasOriginalSize() => $_has(5);
  @$pb.TagNumber(6)
  void clearOriginalSize() => clearField(6);
}

class ProofOfWork extends $pb.GeneratedMessage {
  factory ProofOfWork({
    $fixnum.Int64? nonce,
    $core.int? difficulty,
    $core.List<$core.int>? hash,
  }) {
    final $result = create();
    if (nonce != null) {
      $result.nonce = nonce;
    }
    if (difficulty != null) {
      $result.difficulty = difficulty;
    }
    if (hash != null) {
      $result.hash = hash;
    }
    return $result;
  }
  ProofOfWork._() : super();
  factory ProofOfWork.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ProofOfWork.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ProofOfWork', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'nonce', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.int>(2, _omitFieldNames ? '' : 'difficulty', $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'hash', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ProofOfWork clone() => ProofOfWork()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ProofOfWork copyWith(void Function(ProofOfWork) updates) => super.copyWith((message) => updates(message as ProofOfWork)) as ProofOfWork;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ProofOfWork create() => ProofOfWork._();
  ProofOfWork createEmptyInstance() => create();
  static $pb.PbList<ProofOfWork> createRepeated() => $pb.PbList<ProofOfWork>();
  @$core.pragma('dart2js:noInline')
  static ProofOfWork getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ProofOfWork>(create);
  static ProofOfWork? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get nonce => $_getI64(0);
  @$pb.TagNumber(1)
  set nonce($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasNonce() => $_has(0);
  @$pb.TagNumber(1)
  void clearNonce() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get difficulty => $_getIZ(1);
  @$pb.TagNumber(2)
  set difficulty($core.int v) { $_setUnsignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDifficulty() => $_has(1);
  @$pb.TagNumber(2)
  void clearDifficulty() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get hash => $_getN(2);
  @$pb.TagNumber(3)
  set hash($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasHash() => $_has(2);
  @$pb.TagNumber(3)
  void clearHash() => clearField(3);
}

class PeerInfoProto extends $pb.GeneratedMessage {
  factory PeerInfoProto({
    $core.List<$core.int>? nodeId,
    $core.String? publicIp,
    $core.int? publicPort,
    $core.String? localIp,
    $core.int? localPort,
    $core.Iterable<$0.PeerAddressProto>? addresses,
    $core.String? networkTag,
    $fixnum.Int64? lastSeen,
    NatType? natType,
    $core.int? capabilities,
    $core.List<$core.int>? ed25519PublicKey,
    $core.List<$core.int>? mlDsaPublicKey,
    $core.List<$core.int>? ed25519Signature,
    $core.List<$core.int>? mlDsaSignature,
    $core.List<$core.int>? x25519PublicKey,
    $core.List<$core.int>? mlKemPublicKey,
    $core.List<$core.int>? userId,
    $core.List<$core.int>? deviceEd25519PublicKey,
    $core.List<$core.int>? deviceMlDsaPublicKey,
    $core.List<$core.int>? keyFingerprint,
    $core.List<$core.int>? deviceIdPowNonce,
  }) {
    final $result = create();
    if (nodeId != null) {
      $result.nodeId = nodeId;
    }
    if (publicIp != null) {
      $result.publicIp = publicIp;
    }
    if (publicPort != null) {
      $result.publicPort = publicPort;
    }
    if (localIp != null) {
      $result.localIp = localIp;
    }
    if (localPort != null) {
      $result.localPort = localPort;
    }
    if (addresses != null) {
      $result.addresses.addAll(addresses);
    }
    if (networkTag != null) {
      $result.networkTag = networkTag;
    }
    if (lastSeen != null) {
      $result.lastSeen = lastSeen;
    }
    if (natType != null) {
      $result.natType = natType;
    }
    if (capabilities != null) {
      $result.capabilities = capabilities;
    }
    if (ed25519PublicKey != null) {
      $result.ed25519PublicKey = ed25519PublicKey;
    }
    if (mlDsaPublicKey != null) {
      $result.mlDsaPublicKey = mlDsaPublicKey;
    }
    if (ed25519Signature != null) {
      $result.ed25519Signature = ed25519Signature;
    }
    if (mlDsaSignature != null) {
      $result.mlDsaSignature = mlDsaSignature;
    }
    if (x25519PublicKey != null) {
      $result.x25519PublicKey = x25519PublicKey;
    }
    if (mlKemPublicKey != null) {
      $result.mlKemPublicKey = mlKemPublicKey;
    }
    if (userId != null) {
      $result.userId = userId;
    }
    if (deviceEd25519PublicKey != null) {
      $result.deviceEd25519PublicKey = deviceEd25519PublicKey;
    }
    if (deviceMlDsaPublicKey != null) {
      $result.deviceMlDsaPublicKey = deviceMlDsaPublicKey;
    }
    if (keyFingerprint != null) {
      $result.keyFingerprint = keyFingerprint;
    }
    if (deviceIdPowNonce != null) {
      $result.deviceIdPowNonce = deviceIdPowNonce;
    }
    return $result;
  }
  PeerInfoProto._() : super();
  factory PeerInfoProto.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PeerInfoProto.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PeerInfoProto', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'nodeId', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'publicIp')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'publicPort', $pb.PbFieldType.OU3)
    ..aOS(4, _omitFieldNames ? '' : 'localIp')
    ..a<$core.int>(5, _omitFieldNames ? '' : 'localPort', $pb.PbFieldType.OU3)
    ..pc<$0.PeerAddressProto>(6, _omitFieldNames ? '' : 'addresses', $pb.PbFieldType.PM, subBuilder: $0.PeerAddressProto.create)
    ..aOS(7, _omitFieldNames ? '' : 'networkTag')
    ..a<$fixnum.Int64>(8, _omitFieldNames ? '' : 'lastSeen', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..e<NatType>(9, _omitFieldNames ? '' : 'natType', $pb.PbFieldType.OE, defaultOrMaker: NatType.NAT_UNKNOWN, valueOf: NatType.valueOf, enumValues: NatType.values)
    ..a<$core.int>(10, _omitFieldNames ? '' : 'capabilities', $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(11, _omitFieldNames ? '' : 'ed25519PublicKey', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(12, _omitFieldNames ? '' : 'mlDsaPublicKey', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(13, _omitFieldNames ? '' : 'ed25519Signature', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(14, _omitFieldNames ? '' : 'mlDsaSignature', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(15, _omitFieldNames ? '' : 'x25519PublicKey', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(16, _omitFieldNames ? '' : 'mlKemPublicKey', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(17, _omitFieldNames ? '' : 'userId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(18, _omitFieldNames ? '' : 'deviceEd25519PublicKey', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(19, _omitFieldNames ? '' : 'deviceMlDsaPublicKey', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(20, _omitFieldNames ? '' : 'keyFingerprint', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(21, _omitFieldNames ? '' : 'deviceIdPowNonce', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PeerInfoProto clone() => PeerInfoProto()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PeerInfoProto copyWith(void Function(PeerInfoProto) updates) => super.copyWith((message) => updates(message as PeerInfoProto)) as PeerInfoProto;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PeerInfoProto create() => PeerInfoProto._();
  PeerInfoProto createEmptyInstance() => create();
  static $pb.PbList<PeerInfoProto> createRepeated() => $pb.PbList<PeerInfoProto>();
  @$core.pragma('dart2js:noInline')
  static PeerInfoProto getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PeerInfoProto>(create);
  static PeerInfoProto? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get nodeId => $_getN(0);
  @$pb.TagNumber(1)
  set nodeId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasNodeId() => $_has(0);
  @$pb.TagNumber(1)
  void clearNodeId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get publicIp => $_getSZ(1);
  @$pb.TagNumber(2)
  set publicIp($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasPublicIp() => $_has(1);
  @$pb.TagNumber(2)
  void clearPublicIp() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get publicPort => $_getIZ(2);
  @$pb.TagNumber(3)
  set publicPort($core.int v) { $_setUnsignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasPublicPort() => $_has(2);
  @$pb.TagNumber(3)
  void clearPublicPort() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get localIp => $_getSZ(3);
  @$pb.TagNumber(4)
  set localIp($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasLocalIp() => $_has(3);
  @$pb.TagNumber(4)
  void clearLocalIp() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get localPort => $_getIZ(4);
  @$pb.TagNumber(5)
  set localPort($core.int v) { $_setUnsignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasLocalPort() => $_has(4);
  @$pb.TagNumber(5)
  void clearLocalPort() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$0.PeerAddressProto> get addresses => $_getList(5);

  @$pb.TagNumber(7)
  $core.String get networkTag => $_getSZ(6);
  @$pb.TagNumber(7)
  set networkTag($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasNetworkTag() => $_has(6);
  @$pb.TagNumber(7)
  void clearNetworkTag() => clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get lastSeen => $_getI64(7);
  @$pb.TagNumber(8)
  set lastSeen($fixnum.Int64 v) { $_setInt64(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasLastSeen() => $_has(7);
  @$pb.TagNumber(8)
  void clearLastSeen() => clearField(8);

  @$pb.TagNumber(9)
  NatType get natType => $_getN(8);
  @$pb.TagNumber(9)
  set natType(NatType v) { setField(9, v); }
  @$pb.TagNumber(9)
  $core.bool hasNatType() => $_has(8);
  @$pb.TagNumber(9)
  void clearNatType() => clearField(9);

  @$pb.TagNumber(10)
  $core.int get capabilities => $_getIZ(9);
  @$pb.TagNumber(10)
  set capabilities($core.int v) { $_setUnsignedInt32(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasCapabilities() => $_has(9);
  @$pb.TagNumber(10)
  void clearCapabilities() => clearField(10);

  @$pb.TagNumber(11)
  $core.List<$core.int> get ed25519PublicKey => $_getN(10);
  @$pb.TagNumber(11)
  set ed25519PublicKey($core.List<$core.int> v) { $_setBytes(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasEd25519PublicKey() => $_has(10);
  @$pb.TagNumber(11)
  void clearEd25519PublicKey() => clearField(11);

  @$pb.TagNumber(12)
  $core.List<$core.int> get mlDsaPublicKey => $_getN(11);
  @$pb.TagNumber(12)
  set mlDsaPublicKey($core.List<$core.int> v) { $_setBytes(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasMlDsaPublicKey() => $_has(11);
  @$pb.TagNumber(12)
  void clearMlDsaPublicKey() => clearField(12);

  @$pb.TagNumber(13)
  $core.List<$core.int> get ed25519Signature => $_getN(12);
  @$pb.TagNumber(13)
  set ed25519Signature($core.List<$core.int> v) { $_setBytes(12, v); }
  @$pb.TagNumber(13)
  $core.bool hasEd25519Signature() => $_has(12);
  @$pb.TagNumber(13)
  void clearEd25519Signature() => clearField(13);

  @$pb.TagNumber(14)
  $core.List<$core.int> get mlDsaSignature => $_getN(13);
  @$pb.TagNumber(14)
  set mlDsaSignature($core.List<$core.int> v) { $_setBytes(13, v); }
  @$pb.TagNumber(14)
  $core.bool hasMlDsaSignature() => $_has(13);
  @$pb.TagNumber(14)
  void clearMlDsaSignature() => clearField(14);

  @$pb.TagNumber(15)
  $core.List<$core.int> get x25519PublicKey => $_getN(14);
  @$pb.TagNumber(15)
  set x25519PublicKey($core.List<$core.int> v) { $_setBytes(14, v); }
  @$pb.TagNumber(15)
  $core.bool hasX25519PublicKey() => $_has(14);
  @$pb.TagNumber(15)
  void clearX25519PublicKey() => clearField(15);

  @$pb.TagNumber(16)
  $core.List<$core.int> get mlKemPublicKey => $_getN(15);
  @$pb.TagNumber(16)
  set mlKemPublicKey($core.List<$core.int> v) { $_setBytes(15, v); }
  @$pb.TagNumber(16)
  $core.bool hasMlKemPublicKey() => $_has(15);
  @$pb.TagNumber(16)
  void clearMlKemPublicKey() => clearField(16);

  @$pb.TagNumber(17)
  $core.List<$core.int> get userId => $_getN(16);
  @$pb.TagNumber(17)
  set userId($core.List<$core.int> v) { $_setBytes(16, v); }
  @$pb.TagNumber(17)
  $core.bool hasUserId() => $_has(16);
  @$pb.TagNumber(17)
  void clearUserId() => clearField(17);

  /// §17.3 Welle 3 — Device-Sig PK (per-device, persisted in device_keys.json).
  /// Distinct from ed25519_public_key/ml_dsa_public_key (User-Sig, identity-wide):
  /// outer NetworkPacketV3 device_sig is signed with the Device-Sig keypair, so
  /// verifyOuterDeviceSig must use *these* fields, not the User-Sig PKs above.
  /// Empty/absent = receiver falls back to lenient-bootstrap path until learned.
  @$pb.TagNumber(18)
  $core.List<$core.int> get deviceEd25519PublicKey => $_getN(17);
  @$pb.TagNumber(18)
  set deviceEd25519PublicKey($core.List<$core.int> v) { $_setBytes(17, v); }
  @$pb.TagNumber(18)
  $core.bool hasDeviceEd25519PublicKey() => $_has(17);
  @$pb.TagNumber(18)
  void clearDeviceEd25519PublicKey() => clearField(18);

  @$pb.TagNumber(19)
  $core.List<$core.int> get deviceMlDsaPublicKey => $_getN(18);
  @$pb.TagNumber(19)
  set deviceMlDsaPublicKey($core.List<$core.int> v) { $_setBytes(18, v); }
  @$pb.TagNumber(19)
  $core.bool hasDeviceMlDsaPublicKey() => $_has(18);
  @$pb.TagNumber(19)
  void clearDeviceMlDsaPublicKey() => clearField(19);

  @$pb.TagNumber(20)
  $core.List<$core.int> get keyFingerprint => $_getN(19);
  @$pb.TagNumber(20)
  set keyFingerprint($core.List<$core.int> v) { $_setBytes(19, v); }
  @$pb.TagNumber(20)
  $core.bool hasKeyFingerprint() => $_has(19);
  @$pb.TagNumber(20)
  void clearKeyFingerprint() => clearField(20);

  /// D3 Admission-PoW (§13.1.2): 8-byte nonce certifying device_ed25519_public_key
  /// (SHA-256("cleona-id-pow-v1" || pk || nonce) >= 22 leading zero bits).
  /// Travels alongside the key it certifies; part of the slim field set (8 B).
  /// Legacy builds ignore it; legacy gossipers drop it on re-serialization.
  @$pb.TagNumber(21)
  $core.List<$core.int> get deviceIdPowNonce => $_getN(20);
  @$pb.TagNumber(21)
  set deviceIdPowNonce($core.List<$core.int> v) { $_setBytes(20, v); }
  @$pb.TagNumber(21)
  $core.bool hasDeviceIdPowNonce() => $_has(20);
  @$pb.TagNumber(21)
  void clearDeviceIdPowNonce() => clearField(21);
}

class DhtPing extends $pb.GeneratedMessage {
  factory DhtPing({
    $core.List<$core.int>? senderId,
    $fixnum.Int64? timestamp,
    $core.bool? pkRecoveryHint,
    $core.bool? wantKemRecord,
  }) {
    final $result = create();
    if (senderId != null) {
      $result.senderId = senderId;
    }
    if (timestamp != null) {
      $result.timestamp = timestamp;
    }
    if (pkRecoveryHint != null) {
      $result.pkRecoveryHint = pkRecoveryHint;
    }
    if (wantKemRecord != null) {
      $result.wantKemRecord = wantKemRecord;
    }
    return $result;
  }
  DhtPing._() : super();
  factory DhtPing.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DhtPing.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DhtPing', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'senderId', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'timestamp', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(3, _omitFieldNames ? '' : 'pkRecoveryHint')
    ..aOB(4, _omitFieldNames ? '' : 'wantKemRecord')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DhtPing clone() => DhtPing()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DhtPing copyWith(void Function(DhtPing) updates) => super.copyWith((message) => updates(message as DhtPing)) as DhtPing;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DhtPing create() => DhtPing._();
  DhtPing createEmptyInstance() => create();
  static $pb.PbList<DhtPing> createRepeated() => $pb.PbList<DhtPing>();
  @$core.pragma('dart2js:noInline')
  static DhtPing getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DhtPing>(create);
  static DhtPing? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get senderId => $_getN(0);
  @$pb.TagNumber(1)
  set senderId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSenderId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSenderId() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestamp => $_getI64(1);
  @$pb.TagNumber(2)
  set timestamp($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTimestamp() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestamp() => clearField(2);

  /// Welle 5.12 Stage-2 hot-path heal hint (§5.10.2 / §5.12). When true, the
  /// ping is a Stale-PK recovery probe — the responder MUST answer with the
  /// normal DHT_PONG *and* an unsolicited firstParty PEER_LIST_PUSH carrying
  /// its own PeerInfo (current signing keys), so the prober heals the cached
  /// PK in 1 RTT instead of waiting for a periodic peer exchange.
  @$pb.TagNumber(3)
  $core.bool get pkRecoveryHint => $_getBF(2);
  @$pb.TagNumber(3)
  set pkRecoveryHint($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasPkRecoveryHint() => $_has(2);
  @$pb.TagNumber(3)
  void clearPkRecoveryHint() => clearField(3);

  /// §5.10.2 First-contact KEM bootstrap. Set ONLY when our own
  /// DeviceKemRecord lookup for this device just missed — a peer that already
  /// holds the record never asks. The responder then attaches its signed
  /// DeviceKemRecord to the DHT_PONG, which is the only way a peer known by
  /// address alone can ever send a KEM-path message: that record is otherwise
  /// distributed through the 2D-DHT only, and the DHT is precisely what such a
  /// peer cannot reach yet. Opt-in rather than unconditional because the record
  /// is ~1.4 KB and pushes the PONG onto the fragmentation path (§2.6).
  @$pb.TagNumber(4)
  $core.bool get wantKemRecord => $_getBF(3);
  @$pb.TagNumber(4)
  set wantKemRecord($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasWantKemRecord() => $_has(3);
  @$pb.TagNumber(4)
  void clearWantKemRecord() => clearField(4);
}

class DhtPong extends $pb.GeneratedMessage {
  factory DhtPong({
    $core.List<$core.int>? senderId,
    $fixnum.Int64? timestamp,
    $core.String? observedIp,
    $core.int? observedPort,
    $core.Iterable<$core.List<$core.int>>? additionalNodeIds,
    DeviceKemRecordV3? kemRecord,
  }) {
    final $result = create();
    if (senderId != null) {
      $result.senderId = senderId;
    }
    if (timestamp != null) {
      $result.timestamp = timestamp;
    }
    if (observedIp != null) {
      $result.observedIp = observedIp;
    }
    if (observedPort != null) {
      $result.observedPort = observedPort;
    }
    if (additionalNodeIds != null) {
      $result.additionalNodeIds.addAll(additionalNodeIds);
    }
    if (kemRecord != null) {
      $result.kemRecord = kemRecord;
    }
    return $result;
  }
  DhtPong._() : super();
  factory DhtPong.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DhtPong.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DhtPong', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'senderId', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'timestamp', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(3, _omitFieldNames ? '' : 'observedIp')
    ..a<$core.int>(4, _omitFieldNames ? '' : 'observedPort', $pb.PbFieldType.OU3)
    ..p<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'additionalNodeIds', $pb.PbFieldType.PY)
    ..aOM<DeviceKemRecordV3>(6, _omitFieldNames ? '' : 'kemRecord', subBuilder: DeviceKemRecordV3.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DhtPong clone() => DhtPong()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DhtPong copyWith(void Function(DhtPong) updates) => super.copyWith((message) => updates(message as DhtPong)) as DhtPong;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DhtPong create() => DhtPong._();
  DhtPong createEmptyInstance() => create();
  static $pb.PbList<DhtPong> createRepeated() => $pb.PbList<DhtPong>();
  @$core.pragma('dart2js:noInline')
  static DhtPong getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DhtPong>(create);
  static DhtPong? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get senderId => $_getN(0);
  @$pb.TagNumber(1)
  set senderId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSenderId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSenderId() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestamp => $_getI64(1);
  @$pb.TagNumber(2)
  set timestamp($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTimestamp() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestamp() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get observedIp => $_getSZ(2);
  @$pb.TagNumber(3)
  set observedIp($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasObservedIp() => $_has(2);
  @$pb.TagNumber(3)
  void clearObservedIp() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get observedPort => $_getIZ(3);
  @$pb.TagNumber(4)
  set observedPort($core.int v) { $_setUnsignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasObservedPort() => $_has(3);
  @$pb.TagNumber(4)
  void clearObservedPort() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.List<$core.int>> get additionalNodeIds => $_getList(4);

  /// §5.10.2 — present only when the ping carried want_kem_record.
  /// Self-authenticating (§4.3): verified against the claimed user master
  /// Ed25519 key exactly like a DHT-fetched record, and cached in the same
  /// replica cache. No transport condition is needed: DHT_PING is in the BOOT
  /// allow-list and is therefore always plaintext.
  @$pb.TagNumber(6)
  DeviceKemRecordV3 get kemRecord => $_getN(5);
  @$pb.TagNumber(6)
  set kemRecord(DeviceKemRecordV3 v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasKemRecord() => $_has(5);
  @$pb.TagNumber(6)
  void clearKemRecord() => clearField(6);
  @$pb.TagNumber(6)
  DeviceKemRecordV3 ensureKemRecord() => $_ensure(5);
}

class DhtFindNode extends $pb.GeneratedMessage {
  factory DhtFindNode({
    $core.List<$core.int>? targetId,
    $core.List<$core.int>? senderId,
  }) {
    final $result = create();
    if (targetId != null) {
      $result.targetId = targetId;
    }
    if (senderId != null) {
      $result.senderId = senderId;
    }
    return $result;
  }
  DhtFindNode._() : super();
  factory DhtFindNode.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DhtFindNode.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DhtFindNode', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'targetId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'senderId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DhtFindNode clone() => DhtFindNode()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DhtFindNode copyWith(void Function(DhtFindNode) updates) => super.copyWith((message) => updates(message as DhtFindNode)) as DhtFindNode;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DhtFindNode create() => DhtFindNode._();
  DhtFindNode createEmptyInstance() => create();
  static $pb.PbList<DhtFindNode> createRepeated() => $pb.PbList<DhtFindNode>();
  @$core.pragma('dart2js:noInline')
  static DhtFindNode getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DhtFindNode>(create);
  static DhtFindNode? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get targetId => $_getN(0);
  @$pb.TagNumber(1)
  set targetId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTargetId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTargetId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get senderId => $_getN(1);
  @$pb.TagNumber(2)
  set senderId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSenderId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSenderId() => clearField(2);
}

class DhtFindNodeResponse extends $pb.GeneratedMessage {
  factory DhtFindNodeResponse({
    $core.Iterable<PeerInfoProto>? closestPeers,
  }) {
    final $result = create();
    if (closestPeers != null) {
      $result.closestPeers.addAll(closestPeers);
    }
    return $result;
  }
  DhtFindNodeResponse._() : super();
  factory DhtFindNodeResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DhtFindNodeResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DhtFindNodeResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..pc<PeerInfoProto>(1, _omitFieldNames ? '' : 'closestPeers', $pb.PbFieldType.PM, subBuilder: PeerInfoProto.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DhtFindNodeResponse clone() => DhtFindNodeResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DhtFindNodeResponse copyWith(void Function(DhtFindNodeResponse) updates) => super.copyWith((message) => updates(message as DhtFindNodeResponse)) as DhtFindNodeResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DhtFindNodeResponse create() => DhtFindNodeResponse._();
  DhtFindNodeResponse createEmptyInstance() => create();
  static $pb.PbList<DhtFindNodeResponse> createRepeated() => $pb.PbList<DhtFindNodeResponse>();
  @$core.pragma('dart2js:noInline')
  static DhtFindNodeResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DhtFindNodeResponse>(create);
  static DhtFindNodeResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<PeerInfoProto> get closestPeers => $_getList(0);
}

class DhtStore extends $pb.GeneratedMessage {
  factory DhtStore({
    $core.List<$core.int>? key,
    $core.List<$core.int>? value,
    $fixnum.Int64? ttlMs,
  }) {
    final $result = create();
    if (key != null) {
      $result.key = key;
    }
    if (value != null) {
      $result.value = value;
    }
    if (ttlMs != null) {
      $result.ttlMs = ttlMs;
    }
    return $result;
  }
  DhtStore._() : super();
  factory DhtStore.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DhtStore.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DhtStore', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'key', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'value', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(3, _omitFieldNames ? '' : 'ttlMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DhtStore clone() => DhtStore()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DhtStore copyWith(void Function(DhtStore) updates) => super.copyWith((message) => updates(message as DhtStore)) as DhtStore;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DhtStore create() => DhtStore._();
  DhtStore createEmptyInstance() => create();
  static $pb.PbList<DhtStore> createRepeated() => $pb.PbList<DhtStore>();
  @$core.pragma('dart2js:noInline')
  static DhtStore getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DhtStore>(create);
  static DhtStore? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get key => $_getN(0);
  @$pb.TagNumber(1)
  set key($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get value => $_getN(1);
  @$pb.TagNumber(2)
  set value($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasValue() => $_has(1);
  @$pb.TagNumber(2)
  void clearValue() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get ttlMs => $_getI64(2);
  @$pb.TagNumber(3)
  set ttlMs($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTtlMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearTtlMs() => clearField(3);
}

class DhtStoreResponse extends $pb.GeneratedMessage {
  factory DhtStoreResponse({
    $core.bool? success,
  }) {
    final $result = create();
    if (success != null) {
      $result.success = success;
    }
    return $result;
  }
  DhtStoreResponse._() : super();
  factory DhtStoreResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DhtStoreResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DhtStoreResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DhtStoreResponse clone() => DhtStoreResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DhtStoreResponse copyWith(void Function(DhtStoreResponse) updates) => super.copyWith((message) => updates(message as DhtStoreResponse)) as DhtStoreResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DhtStoreResponse create() => DhtStoreResponse._();
  DhtStoreResponse createEmptyInstance() => create();
  static $pb.PbList<DhtStoreResponse> createRepeated() => $pb.PbList<DhtStoreResponse>();
  @$core.pragma('dart2js:noInline')
  static DhtStoreResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DhtStoreResponse>(create);
  static DhtStoreResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => clearField(1);
}

class DhtFindValue extends $pb.GeneratedMessage {
  factory DhtFindValue({
    $core.List<$core.int>? key,
  }) {
    final $result = create();
    if (key != null) {
      $result.key = key;
    }
    return $result;
  }
  DhtFindValue._() : super();
  factory DhtFindValue.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DhtFindValue.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DhtFindValue', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'key', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DhtFindValue clone() => DhtFindValue()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DhtFindValue copyWith(void Function(DhtFindValue) updates) => super.copyWith((message) => updates(message as DhtFindValue)) as DhtFindValue;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DhtFindValue create() => DhtFindValue._();
  DhtFindValue createEmptyInstance() => create();
  static $pb.PbList<DhtFindValue> createRepeated() => $pb.PbList<DhtFindValue>();
  @$core.pragma('dart2js:noInline')
  static DhtFindValue getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DhtFindValue>(create);
  static DhtFindValue? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get key => $_getN(0);
  @$pb.TagNumber(1)
  set key($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => clearField(1);
}

class DhtFindValueResponse extends $pb.GeneratedMessage {
  factory DhtFindValueResponse({
    $core.List<$core.int>? value,
    $core.Iterable<PeerInfoProto>? closestPeers,
    $core.bool? found,
  }) {
    final $result = create();
    if (value != null) {
      $result.value = value;
    }
    if (closestPeers != null) {
      $result.closestPeers.addAll(closestPeers);
    }
    if (found != null) {
      $result.found = found;
    }
    return $result;
  }
  DhtFindValueResponse._() : super();
  factory DhtFindValueResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DhtFindValueResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DhtFindValueResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'value', $pb.PbFieldType.OY)
    ..pc<PeerInfoProto>(2, _omitFieldNames ? '' : 'closestPeers', $pb.PbFieldType.PM, subBuilder: PeerInfoProto.create)
    ..aOB(3, _omitFieldNames ? '' : 'found')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DhtFindValueResponse clone() => DhtFindValueResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DhtFindValueResponse copyWith(void Function(DhtFindValueResponse) updates) => super.copyWith((message) => updates(message as DhtFindValueResponse)) as DhtFindValueResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DhtFindValueResponse create() => DhtFindValueResponse._();
  DhtFindValueResponse createEmptyInstance() => create();
  static $pb.PbList<DhtFindValueResponse> createRepeated() => $pb.PbList<DhtFindValueResponse>();
  @$core.pragma('dart2js:noInline')
  static DhtFindValueResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DhtFindValueResponse>(create);
  static DhtFindValueResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get value => $_getN(0);
  @$pb.TagNumber(1)
  set value($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasValue() => $_has(0);
  @$pb.TagNumber(1)
  void clearValue() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<PeerInfoProto> get closestPeers => $_getList(1);

  @$pb.TagNumber(3)
  $core.bool get found => $_getBF(2);
  @$pb.TagNumber(3)
  set found($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasFound() => $_has(2);
  @$pb.TagNumber(3)
  void clearFound() => clearField(3);
}

class PeerListSummary extends $pb.GeneratedMessage {
  factory PeerListSummary({
    $core.Iterable<PeerSummaryEntry>? entries,
  }) {
    final $result = create();
    if (entries != null) {
      $result.entries.addAll(entries);
    }
    return $result;
  }
  PeerListSummary._() : super();
  factory PeerListSummary.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PeerListSummary.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PeerListSummary', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..pc<PeerSummaryEntry>(1, _omitFieldNames ? '' : 'entries', $pb.PbFieldType.PM, subBuilder: PeerSummaryEntry.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PeerListSummary clone() => PeerListSummary()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PeerListSummary copyWith(void Function(PeerListSummary) updates) => super.copyWith((message) => updates(message as PeerListSummary)) as PeerListSummary;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PeerListSummary create() => PeerListSummary._();
  PeerListSummary createEmptyInstance() => create();
  static $pb.PbList<PeerListSummary> createRepeated() => $pb.PbList<PeerListSummary>();
  @$core.pragma('dart2js:noInline')
  static PeerListSummary getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PeerListSummary>(create);
  static PeerListSummary? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<PeerSummaryEntry> get entries => $_getList(0);
}

class PeerSummaryEntry extends $pb.GeneratedMessage {
  factory PeerSummaryEntry({
    $core.List<$core.int>? nodeId,
    $fixnum.Int64? lastSeen,
  }) {
    final $result = create();
    if (nodeId != null) {
      $result.nodeId = nodeId;
    }
    if (lastSeen != null) {
      $result.lastSeen = lastSeen;
    }
    return $result;
  }
  PeerSummaryEntry._() : super();
  factory PeerSummaryEntry.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PeerSummaryEntry.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PeerSummaryEntry', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'nodeId', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'lastSeen', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PeerSummaryEntry clone() => PeerSummaryEntry()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PeerSummaryEntry copyWith(void Function(PeerSummaryEntry) updates) => super.copyWith((message) => updates(message as PeerSummaryEntry)) as PeerSummaryEntry;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PeerSummaryEntry create() => PeerSummaryEntry._();
  PeerSummaryEntry createEmptyInstance() => create();
  static $pb.PbList<PeerSummaryEntry> createRepeated() => $pb.PbList<PeerSummaryEntry>();
  @$core.pragma('dart2js:noInline')
  static PeerSummaryEntry getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PeerSummaryEntry>(create);
  static PeerSummaryEntry? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get nodeId => $_getN(0);
  @$pb.TagNumber(1)
  set nodeId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasNodeId() => $_has(0);
  @$pb.TagNumber(1)
  void clearNodeId() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get lastSeen => $_getI64(1);
  @$pb.TagNumber(2)
  set lastSeen($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasLastSeen() => $_has(1);
  @$pb.TagNumber(2)
  void clearLastSeen() => clearField(2);
}

class PeerListWant extends $pb.GeneratedMessage {
  factory PeerListWant({
    $core.Iterable<$core.List<$core.int>>? wantedNodeIds,
  }) {
    final $result = create();
    if (wantedNodeIds != null) {
      $result.wantedNodeIds.addAll(wantedNodeIds);
    }
    return $result;
  }
  PeerListWant._() : super();
  factory PeerListWant.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PeerListWant.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PeerListWant', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..p<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'wantedNodeIds', $pb.PbFieldType.PY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PeerListWant clone() => PeerListWant()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PeerListWant copyWith(void Function(PeerListWant) updates) => super.copyWith((message) => updates(message as PeerListWant)) as PeerListWant;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PeerListWant create() => PeerListWant._();
  PeerListWant createEmptyInstance() => create();
  static $pb.PbList<PeerListWant> createRepeated() => $pb.PbList<PeerListWant>();
  @$core.pragma('dart2js:noInline')
  static PeerListWant getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PeerListWant>(create);
  static PeerListWant? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.List<$core.int>> get wantedNodeIds => $_getList(0);
}

class PeerListPush extends $pb.GeneratedMessage {
  factory PeerListPush({
    $core.Iterable<PeerInfoProto>? peers,
  }) {
    final $result = create();
    if (peers != null) {
      $result.peers.addAll(peers);
    }
    return $result;
  }
  PeerListPush._() : super();
  factory PeerListPush.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PeerListPush.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PeerListPush', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..pc<PeerInfoProto>(1, _omitFieldNames ? '' : 'peers', $pb.PbFieldType.PM, subBuilder: PeerInfoProto.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PeerListPush clone() => PeerListPush()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PeerListPush copyWith(void Function(PeerListPush) updates) => super.copyWith((message) => updates(message as PeerListPush)) as PeerListPush;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PeerListPush create() => PeerListPush._();
  PeerListPush createEmptyInstance() => create();
  static $pb.PbList<PeerListPush> createRepeated() => $pb.PbList<PeerListPush>();
  @$core.pragma('dart2js:noInline')
  static PeerListPush getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PeerListPush>(create);
  static PeerListPush? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<PeerInfoProto> get peers => $_getList(0);
}

class PeerKeyRequest extends $pb.GeneratedMessage {
  factory PeerKeyRequest() => create();
  PeerKeyRequest._() : super();
  factory PeerKeyRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PeerKeyRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PeerKeyRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PeerKeyRequest clone() => PeerKeyRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PeerKeyRequest copyWith(void Function(PeerKeyRequest) updates) => super.copyWith((message) => updates(message as PeerKeyRequest)) as PeerKeyRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PeerKeyRequest create() => PeerKeyRequest._();
  PeerKeyRequest createEmptyInstance() => create();
  static $pb.PbList<PeerKeyRequest> createRepeated() => $pb.PbList<PeerKeyRequest>();
  @$core.pragma('dart2js:noInline')
  static PeerKeyRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PeerKeyRequest>(create);
  static PeerKeyRequest? _defaultInstance;
}

class PeerKeyResponse extends $pb.GeneratedMessage {
  factory PeerKeyResponse({
    $core.Iterable<PeerInfoProto>? peers,
  }) {
    final $result = create();
    if (peers != null) {
      $result.peers.addAll(peers);
    }
    return $result;
  }
  PeerKeyResponse._() : super();
  factory PeerKeyResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PeerKeyResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PeerKeyResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..pc<PeerInfoProto>(1, _omitFieldNames ? '' : 'peers', $pb.PbFieldType.PM, subBuilder: PeerInfoProto.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PeerKeyResponse clone() => PeerKeyResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PeerKeyResponse copyWith(void Function(PeerKeyResponse) updates) => super.copyWith((message) => updates(message as PeerKeyResponse)) as PeerKeyResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PeerKeyResponse create() => PeerKeyResponse._();
  PeerKeyResponse createEmptyInstance() => create();
  static $pb.PbList<PeerKeyResponse> createRepeated() => $pb.PbList<PeerKeyResponse>();
  @$core.pragma('dart2js:noInline')
  static PeerKeyResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PeerKeyResponse>(create);
  static PeerKeyResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<PeerInfoProto> get peers => $_getList(0);
}

class FragmentStore extends $pb.GeneratedMessage {
  factory FragmentStore({
    $core.List<$core.int>? mailboxId,
    $core.List<$core.int>? messageId,
    $core.int? fragmentIndex,
    $core.int? totalFragments,
    $core.int? requiredFragments,
    $core.List<$core.int>? fragmentData,
    $core.int? originalSize,
    $fixnum.Int64? ttlMs,
  }) {
    final $result = create();
    if (mailboxId != null) {
      $result.mailboxId = mailboxId;
    }
    if (messageId != null) {
      $result.messageId = messageId;
    }
    if (fragmentIndex != null) {
      $result.fragmentIndex = fragmentIndex;
    }
    if (totalFragments != null) {
      $result.totalFragments = totalFragments;
    }
    if (requiredFragments != null) {
      $result.requiredFragments = requiredFragments;
    }
    if (fragmentData != null) {
      $result.fragmentData = fragmentData;
    }
    if (originalSize != null) {
      $result.originalSize = originalSize;
    }
    if (ttlMs != null) {
      $result.ttlMs = ttlMs;
    }
    return $result;
  }
  FragmentStore._() : super();
  factory FragmentStore.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory FragmentStore.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FragmentStore', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'mailboxId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'messageId', $pb.PbFieldType.OY)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'fragmentIndex', $pb.PbFieldType.OU3)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'totalFragments', $pb.PbFieldType.OU3)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'requiredFragments', $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(6, _omitFieldNames ? '' : 'fragmentData', $pb.PbFieldType.OY)
    ..a<$core.int>(7, _omitFieldNames ? '' : 'originalSize', $pb.PbFieldType.OU3)
    ..a<$fixnum.Int64>(8, _omitFieldNames ? '' : 'ttlMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  FragmentStore clone() => FragmentStore()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  FragmentStore copyWith(void Function(FragmentStore) updates) => super.copyWith((message) => updates(message as FragmentStore)) as FragmentStore;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FragmentStore create() => FragmentStore._();
  FragmentStore createEmptyInstance() => create();
  static $pb.PbList<FragmentStore> createRepeated() => $pb.PbList<FragmentStore>();
  @$core.pragma('dart2js:noInline')
  static FragmentStore getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FragmentStore>(create);
  static FragmentStore? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get mailboxId => $_getN(0);
  @$pb.TagNumber(1)
  set mailboxId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMailboxId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMailboxId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get messageId => $_getN(1);
  @$pb.TagNumber(2)
  set messageId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMessageId() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessageId() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get fragmentIndex => $_getIZ(2);
  @$pb.TagNumber(3)
  set fragmentIndex($core.int v) { $_setUnsignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasFragmentIndex() => $_has(2);
  @$pb.TagNumber(3)
  void clearFragmentIndex() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get totalFragments => $_getIZ(3);
  @$pb.TagNumber(4)
  set totalFragments($core.int v) { $_setUnsignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTotalFragments() => $_has(3);
  @$pb.TagNumber(4)
  void clearTotalFragments() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get requiredFragments => $_getIZ(4);
  @$pb.TagNumber(5)
  set requiredFragments($core.int v) { $_setUnsignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasRequiredFragments() => $_has(4);
  @$pb.TagNumber(5)
  void clearRequiredFragments() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get fragmentData => $_getN(5);
  @$pb.TagNumber(6)
  set fragmentData($core.List<$core.int> v) { $_setBytes(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasFragmentData() => $_has(5);
  @$pb.TagNumber(6)
  void clearFragmentData() => clearField(6);

  @$pb.TagNumber(7)
  $core.int get originalSize => $_getIZ(6);
  @$pb.TagNumber(7)
  set originalSize($core.int v) { $_setUnsignedInt32(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasOriginalSize() => $_has(6);
  @$pb.TagNumber(7)
  void clearOriginalSize() => clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get ttlMs => $_getI64(7);
  @$pb.TagNumber(8)
  set ttlMs($fixnum.Int64 v) { $_setInt64(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasTtlMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearTtlMs() => clearField(8);
}

class FragmentStoreAck extends $pb.GeneratedMessage {
  factory FragmentStoreAck({
    $core.List<$core.int>? messageId,
    $core.int? fragmentIndex,
  }) {
    final $result = create();
    if (messageId != null) {
      $result.messageId = messageId;
    }
    if (fragmentIndex != null) {
      $result.fragmentIndex = fragmentIndex;
    }
    return $result;
  }
  FragmentStoreAck._() : super();
  factory FragmentStoreAck.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory FragmentStoreAck.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FragmentStoreAck', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'messageId', $pb.PbFieldType.OY)
    ..a<$core.int>(2, _omitFieldNames ? '' : 'fragmentIndex', $pb.PbFieldType.OU3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  FragmentStoreAck clone() => FragmentStoreAck()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  FragmentStoreAck copyWith(void Function(FragmentStoreAck) updates) => super.copyWith((message) => updates(message as FragmentStoreAck)) as FragmentStoreAck;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FragmentStoreAck create() => FragmentStoreAck._();
  FragmentStoreAck createEmptyInstance() => create();
  static $pb.PbList<FragmentStoreAck> createRepeated() => $pb.PbList<FragmentStoreAck>();
  @$core.pragma('dart2js:noInline')
  static FragmentStoreAck getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FragmentStoreAck>(create);
  static FragmentStoreAck? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get messageId => $_getN(0);
  @$pb.TagNumber(1)
  set messageId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMessageId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessageId() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get fragmentIndex => $_getIZ(1);
  @$pb.TagNumber(2)
  set fragmentIndex($core.int v) { $_setUnsignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasFragmentIndex() => $_has(1);
  @$pb.TagNumber(2)
  void clearFragmentIndex() => clearField(2);
}

class FragmentRetrieve extends $pb.GeneratedMessage {
  factory FragmentRetrieve({
    $core.List<$core.int>? mailboxId,
  }) {
    final $result = create();
    if (mailboxId != null) {
      $result.mailboxId = mailboxId;
    }
    return $result;
  }
  FragmentRetrieve._() : super();
  factory FragmentRetrieve.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory FragmentRetrieve.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FragmentRetrieve', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'mailboxId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  FragmentRetrieve clone() => FragmentRetrieve()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  FragmentRetrieve copyWith(void Function(FragmentRetrieve) updates) => super.copyWith((message) => updates(message as FragmentRetrieve)) as FragmentRetrieve;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FragmentRetrieve create() => FragmentRetrieve._();
  FragmentRetrieve createEmptyInstance() => create();
  static $pb.PbList<FragmentRetrieve> createRepeated() => $pb.PbList<FragmentRetrieve>();
  @$core.pragma('dart2js:noInline')
  static FragmentRetrieve getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FragmentRetrieve>(create);
  static FragmentRetrieve? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get mailboxId => $_getN(0);
  @$pb.TagNumber(1)
  set mailboxId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMailboxId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMailboxId() => clearField(1);
}

class FragmentRetrieveResponse extends $pb.GeneratedMessage {
  factory FragmentRetrieveResponse({
    $core.List<$core.int>? mailboxId,
    $core.int? fragmentCount,
  }) {
    final $result = create();
    if (mailboxId != null) {
      $result.mailboxId = mailboxId;
    }
    if (fragmentCount != null) {
      $result.fragmentCount = fragmentCount;
    }
    return $result;
  }
  FragmentRetrieveResponse._() : super();
  factory FragmentRetrieveResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory FragmentRetrieveResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FragmentRetrieveResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'mailboxId', $pb.PbFieldType.OY)
    ..a<$core.int>(2, _omitFieldNames ? '' : 'fragmentCount', $pb.PbFieldType.OU3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  FragmentRetrieveResponse clone() => FragmentRetrieveResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  FragmentRetrieveResponse copyWith(void Function(FragmentRetrieveResponse) updates) => super.copyWith((message) => updates(message as FragmentRetrieveResponse)) as FragmentRetrieveResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FragmentRetrieveResponse create() => FragmentRetrieveResponse._();
  FragmentRetrieveResponse createEmptyInstance() => create();
  static $pb.PbList<FragmentRetrieveResponse> createRepeated() => $pb.PbList<FragmentRetrieveResponse>();
  @$core.pragma('dart2js:noInline')
  static FragmentRetrieveResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FragmentRetrieveResponse>(create);
  static FragmentRetrieveResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get mailboxId => $_getN(0);
  @$pb.TagNumber(1)
  set mailboxId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMailboxId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMailboxId() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get fragmentCount => $_getIZ(1);
  @$pb.TagNumber(2)
  set fragmentCount($core.int v) { $_setUnsignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasFragmentCount() => $_has(1);
  @$pb.TagNumber(2)
  void clearFragmentCount() => clearField(2);
}

class FragmentDelete extends $pb.GeneratedMessage {
  factory FragmentDelete({
    $core.List<$core.int>? mailboxId,
    $core.List<$core.int>? messageId,
  }) {
    final $result = create();
    if (mailboxId != null) {
      $result.mailboxId = mailboxId;
    }
    if (messageId != null) {
      $result.messageId = messageId;
    }
    return $result;
  }
  FragmentDelete._() : super();
  factory FragmentDelete.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory FragmentDelete.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FragmentDelete', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'mailboxId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'messageId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  FragmentDelete clone() => FragmentDelete()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  FragmentDelete copyWith(void Function(FragmentDelete) updates) => super.copyWith((message) => updates(message as FragmentDelete)) as FragmentDelete;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FragmentDelete create() => FragmentDelete._();
  FragmentDelete createEmptyInstance() => create();
  static $pb.PbList<FragmentDelete> createRepeated() => $pb.PbList<FragmentDelete>();
  @$core.pragma('dart2js:noInline')
  static FragmentDelete getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FragmentDelete>(create);
  static FragmentDelete? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get mailboxId => $_getN(0);
  @$pb.TagNumber(1)
  set mailboxId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMailboxId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMailboxId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get messageId => $_getN(1);
  @$pb.TagNumber(2)
  set messageId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMessageId() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessageId() => clearField(2);
}

/// Reachability check for anti-Sybil
class ReachabilityCheck extends $pb.GeneratedMessage {
  factory ReachabilityCheck({
    $core.List<$core.int>? targetNodeId,
    $core.List<$core.int>? bloomFilter,
    $core.int? hopsRemaining,
    $core.List<$core.int>? requestId,
  }) {
    final $result = create();
    if (targetNodeId != null) {
      $result.targetNodeId = targetNodeId;
    }
    if (bloomFilter != null) {
      $result.bloomFilter = bloomFilter;
    }
    if (hopsRemaining != null) {
      $result.hopsRemaining = hopsRemaining;
    }
    if (requestId != null) {
      $result.requestId = requestId;
    }
    return $result;
  }
  ReachabilityCheck._() : super();
  factory ReachabilityCheck.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ReachabilityCheck.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ReachabilityCheck', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'targetNodeId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'bloomFilter', $pb.PbFieldType.OY)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'hopsRemaining', $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'requestId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ReachabilityCheck clone() => ReachabilityCheck()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ReachabilityCheck copyWith(void Function(ReachabilityCheck) updates) => super.copyWith((message) => updates(message as ReachabilityCheck)) as ReachabilityCheck;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ReachabilityCheck create() => ReachabilityCheck._();
  ReachabilityCheck createEmptyInstance() => create();
  static $pb.PbList<ReachabilityCheck> createRepeated() => $pb.PbList<ReachabilityCheck>();
  @$core.pragma('dart2js:noInline')
  static ReachabilityCheck getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ReachabilityCheck>(create);
  static ReachabilityCheck? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get targetNodeId => $_getN(0);
  @$pb.TagNumber(1)
  set targetNodeId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTargetNodeId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTargetNodeId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get bloomFilter => $_getN(1);
  @$pb.TagNumber(2)
  set bloomFilter($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasBloomFilter() => $_has(1);
  @$pb.TagNumber(2)
  void clearBloomFilter() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get hopsRemaining => $_getIZ(2);
  @$pb.TagNumber(3)
  set hopsRemaining($core.int v) { $_setUnsignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasHopsRemaining() => $_has(2);
  @$pb.TagNumber(3)
  void clearHopsRemaining() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get requestId => $_getN(3);
  @$pb.TagNumber(4)
  set requestId($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasRequestId() => $_has(3);
  @$pb.TagNumber(4)
  void clearRequestId() => clearField(4);
}

class ReachabilityResponse extends $pb.GeneratedMessage {
  factory ReachabilityResponse({
    $core.List<$core.int>? requestId,
    $core.bool? reached,
  }) {
    final $result = create();
    if (requestId != null) {
      $result.requestId = requestId;
    }
    if (reached != null) {
      $result.reached = reached;
    }
    return $result;
  }
  ReachabilityResponse._() : super();
  factory ReachabilityResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ReachabilityResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ReachabilityResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'requestId', $pb.PbFieldType.OY)
    ..aOB(2, _omitFieldNames ? '' : 'reached')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ReachabilityResponse clone() => ReachabilityResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ReachabilityResponse copyWith(void Function(ReachabilityResponse) updates) => super.copyWith((message) => updates(message as ReachabilityResponse)) as ReachabilityResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ReachabilityResponse create() => ReachabilityResponse._();
  ReachabilityResponse createEmptyInstance() => create();
  static $pb.PbList<ReachabilityResponse> createRepeated() => $pb.PbList<ReachabilityResponse>();
  @$core.pragma('dart2js:noInline')
  static ReachabilityResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ReachabilityResponse>(create);
  static ReachabilityResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get requestId => $_getN(0);
  @$pb.TagNumber(1)
  set requestId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => clearField(1);

  @$pb.TagNumber(2)
  $core.bool get reached => $_getBF(1);
  @$pb.TagNumber(2)
  set reached($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasReached() => $_has(1);
  @$pb.TagNumber(2)
  void clearReached() => clearField(2);
}

class DeliveryReceipt extends $pb.GeneratedMessage {
  factory DeliveryReceipt({
    $core.List<$core.int>? messageId,
    $fixnum.Int64? deliveredAt,
    $core.bool? withholdDeliveryStatus,
  }) {
    final $result = create();
    if (messageId != null) {
      $result.messageId = messageId;
    }
    if (deliveredAt != null) {
      $result.deliveredAt = deliveredAt;
    }
    if (withholdDeliveryStatus != null) {
      $result.withholdDeliveryStatus = withholdDeliveryStatus;
    }
    return $result;
  }
  DeliveryReceipt._() : super();
  factory DeliveryReceipt.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DeliveryReceipt.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DeliveryReceipt', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'messageId', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'deliveredAt', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(3, _omitFieldNames ? '' : 'withholdDeliveryStatus')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DeliveryReceipt clone() => DeliveryReceipt()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DeliveryReceipt copyWith(void Function(DeliveryReceipt) updates) => super.copyWith((message) => updates(message as DeliveryReceipt)) as DeliveryReceipt;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeliveryReceipt create() => DeliveryReceipt._();
  DeliveryReceipt createEmptyInstance() => create();
  static $pb.PbList<DeliveryReceipt> createRepeated() => $pb.PbList<DeliveryReceipt>();
  @$core.pragma('dart2js:noInline')
  static DeliveryReceipt getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DeliveryReceipt>(create);
  static DeliveryReceipt? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get messageId => $_getN(0);
  @$pb.TagNumber(1)
  set messageId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMessageId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessageId() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get deliveredAt => $_getI64(1);
  @$pb.TagNumber(2)
  set deliveredAt($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDeliveredAt() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeliveredAt() => clearField(2);

  /// §14.7.4: receiver withholds its delivery status from the sender's UI.
  /// Encoded as "withhold", not "disclose", on purpose: proto3 scalars default
  /// to false when absent, so a receipt from a node that predates this field
  /// (or any future encoder that omits it) means "disclose" — the behaviour
  /// that was in place before the flag existed. The inverse naming would turn
  /// every legacy receipt into a suppressed status.
  @$pb.TagNumber(3)
  $core.bool get withholdDeliveryStatus => $_getBF(2);
  @$pb.TagNumber(3)
  set withholdDeliveryStatus($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasWithholdDeliveryStatus() => $_has(2);
  @$pb.TagNumber(3)
  void clearWithholdDeliveryStatus() => clearField(3);
}

class GuardianShareStore extends $pb.GeneratedMessage {
  factory GuardianShareStore({
    $core.List<$core.int>? shareData,
    $core.List<$core.int>? ownerNodeId,
    $core.String? ownerDisplayName,
  }) {
    final $result = create();
    if (shareData != null) {
      $result.shareData = shareData;
    }
    if (ownerNodeId != null) {
      $result.ownerNodeId = ownerNodeId;
    }
    if (ownerDisplayName != null) {
      $result.ownerDisplayName = ownerDisplayName;
    }
    return $result;
  }
  GuardianShareStore._() : super();
  factory GuardianShareStore.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GuardianShareStore.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GuardianShareStore', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'shareData', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'ownerNodeId', $pb.PbFieldType.OY)
    ..aOS(3, _omitFieldNames ? '' : 'ownerDisplayName')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GuardianShareStore clone() => GuardianShareStore()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GuardianShareStore copyWith(void Function(GuardianShareStore) updates) => super.copyWith((message) => updates(message as GuardianShareStore)) as GuardianShareStore;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GuardianShareStore create() => GuardianShareStore._();
  GuardianShareStore createEmptyInstance() => create();
  static $pb.PbList<GuardianShareStore> createRepeated() => $pb.PbList<GuardianShareStore>();
  @$core.pragma('dart2js:noInline')
  static GuardianShareStore getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GuardianShareStore>(create);
  static GuardianShareStore? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get shareData => $_getN(0);
  @$pb.TagNumber(1)
  set shareData($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasShareData() => $_has(0);
  @$pb.TagNumber(1)
  void clearShareData() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get ownerNodeId => $_getN(1);
  @$pb.TagNumber(2)
  set ownerNodeId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasOwnerNodeId() => $_has(1);
  @$pb.TagNumber(2)
  void clearOwnerNodeId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get ownerDisplayName => $_getSZ(2);
  @$pb.TagNumber(3)
  set ownerDisplayName($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasOwnerDisplayName() => $_has(2);
  @$pb.TagNumber(3)
  void clearOwnerDisplayName() => clearField(3);
}

class GuardianRestoreRequest extends $pb.GeneratedMessage {
  factory GuardianRestoreRequest({
    $core.List<$core.int>? ownerNodeId,
    $core.String? ownerDisplayName,
    $core.List<$core.int>? triggeringGuardianNodeId,
    $core.String? triggeringGuardianName,
    $core.List<$core.int>? recoveryMailboxId,
  }) {
    final $result = create();
    if (ownerNodeId != null) {
      $result.ownerNodeId = ownerNodeId;
    }
    if (ownerDisplayName != null) {
      $result.ownerDisplayName = ownerDisplayName;
    }
    if (triggeringGuardianNodeId != null) {
      $result.triggeringGuardianNodeId = triggeringGuardianNodeId;
    }
    if (triggeringGuardianName != null) {
      $result.triggeringGuardianName = triggeringGuardianName;
    }
    if (recoveryMailboxId != null) {
      $result.recoveryMailboxId = recoveryMailboxId;
    }
    return $result;
  }
  GuardianRestoreRequest._() : super();
  factory GuardianRestoreRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GuardianRestoreRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GuardianRestoreRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'ownerNodeId', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'ownerDisplayName')
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'triggeringGuardianNodeId', $pb.PbFieldType.OY)
    ..aOS(4, _omitFieldNames ? '' : 'triggeringGuardianName')
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'recoveryMailboxId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GuardianRestoreRequest clone() => GuardianRestoreRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GuardianRestoreRequest copyWith(void Function(GuardianRestoreRequest) updates) => super.copyWith((message) => updates(message as GuardianRestoreRequest)) as GuardianRestoreRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GuardianRestoreRequest create() => GuardianRestoreRequest._();
  GuardianRestoreRequest createEmptyInstance() => create();
  static $pb.PbList<GuardianRestoreRequest> createRepeated() => $pb.PbList<GuardianRestoreRequest>();
  @$core.pragma('dart2js:noInline')
  static GuardianRestoreRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GuardianRestoreRequest>(create);
  static GuardianRestoreRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get ownerNodeId => $_getN(0);
  @$pb.TagNumber(1)
  set ownerNodeId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasOwnerNodeId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOwnerNodeId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get ownerDisplayName => $_getSZ(1);
  @$pb.TagNumber(2)
  set ownerDisplayName($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasOwnerDisplayName() => $_has(1);
  @$pb.TagNumber(2)
  void clearOwnerDisplayName() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get triggeringGuardianNodeId => $_getN(2);
  @$pb.TagNumber(3)
  set triggeringGuardianNodeId($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTriggeringGuardianNodeId() => $_has(2);
  @$pb.TagNumber(3)
  void clearTriggeringGuardianNodeId() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get triggeringGuardianName => $_getSZ(3);
  @$pb.TagNumber(4)
  set triggeringGuardianName($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTriggeringGuardianName() => $_has(3);
  @$pb.TagNumber(4)
  void clearTriggeringGuardianName() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get recoveryMailboxId => $_getN(4);
  @$pb.TagNumber(5)
  set recoveryMailboxId($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasRecoveryMailboxId() => $_has(4);
  @$pb.TagNumber(5)
  void clearRecoveryMailboxId() => clearField(5);
}

class GuardianRestoreResponse extends $pb.GeneratedMessage {
  factory GuardianRestoreResponse({
    $core.List<$core.int>? shareData,
    $core.List<$core.int>? ownerNodeId,
  }) {
    final $result = create();
    if (shareData != null) {
      $result.shareData = shareData;
    }
    if (ownerNodeId != null) {
      $result.ownerNodeId = ownerNodeId;
    }
    return $result;
  }
  GuardianRestoreResponse._() : super();
  factory GuardianRestoreResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GuardianRestoreResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GuardianRestoreResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'shareData', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'ownerNodeId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GuardianRestoreResponse clone() => GuardianRestoreResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GuardianRestoreResponse copyWith(void Function(GuardianRestoreResponse) updates) => super.copyWith((message) => updates(message as GuardianRestoreResponse)) as GuardianRestoreResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GuardianRestoreResponse create() => GuardianRestoreResponse._();
  GuardianRestoreResponse createEmptyInstance() => create();
  static $pb.PbList<GuardianRestoreResponse> createRepeated() => $pb.PbList<GuardianRestoreResponse>();
  @$core.pragma('dart2js:noInline')
  static GuardianRestoreResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GuardianRestoreResponse>(create);
  static GuardianRestoreResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get shareData => $_getN(0);
  @$pb.TagNumber(1)
  set shareData($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasShareData() => $_has(0);
  @$pb.TagNumber(1)
  void clearShareData() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get ownerNodeId => $_getN(1);
  @$pb.TagNumber(2)
  set ownerNodeId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasOwnerNodeId() => $_has(1);
  @$pb.TagNumber(2)
  void clearOwnerNodeId() => clearField(2);
}

class RelayForward extends $pb.GeneratedMessage {
  factory RelayForward({
    $core.List<$core.int>? relayId,
    $core.List<$core.int>? finalRecipientId,
    $core.List<$core.int>? wrappedEnvelope,
    $core.int? hopCount,
    $core.int? maxHops,
    $core.Iterable<$core.List<$core.int>>? visitedNodes,
    $core.List<$core.int>? originNodeId,
    $fixnum.Int64? createdAtMs,
    $core.int? ttl,
    $core.List<$core.int>? originUserId,
  }) {
    final $result = create();
    if (relayId != null) {
      $result.relayId = relayId;
    }
    if (finalRecipientId != null) {
      $result.finalRecipientId = finalRecipientId;
    }
    if (wrappedEnvelope != null) {
      $result.wrappedEnvelope = wrappedEnvelope;
    }
    if (hopCount != null) {
      $result.hopCount = hopCount;
    }
    if (maxHops != null) {
      $result.maxHops = maxHops;
    }
    if (visitedNodes != null) {
      $result.visitedNodes.addAll(visitedNodes);
    }
    if (originNodeId != null) {
      $result.originNodeId = originNodeId;
    }
    if (createdAtMs != null) {
      $result.createdAtMs = createdAtMs;
    }
    if (ttl != null) {
      $result.ttl = ttl;
    }
    if (originUserId != null) {
      $result.originUserId = originUserId;
    }
    return $result;
  }
  RelayForward._() : super();
  factory RelayForward.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RelayForward.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RelayForward', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'relayId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'finalRecipientId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'wrappedEnvelope', $pb.PbFieldType.OY)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'hopCount', $pb.PbFieldType.OU3)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'maxHops', $pb.PbFieldType.OU3)
    ..p<$core.List<$core.int>>(6, _omitFieldNames ? '' : 'visitedNodes', $pb.PbFieldType.PY)
    ..a<$core.List<$core.int>>(7, _omitFieldNames ? '' : 'originNodeId', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(8, _omitFieldNames ? '' : 'createdAtMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.int>(9, _omitFieldNames ? '' : 'ttl', $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(10, _omitFieldNames ? '' : 'originUserId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RelayForward clone() => RelayForward()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RelayForward copyWith(void Function(RelayForward) updates) => super.copyWith((message) => updates(message as RelayForward)) as RelayForward;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RelayForward create() => RelayForward._();
  RelayForward createEmptyInstance() => create();
  static $pb.PbList<RelayForward> createRepeated() => $pb.PbList<RelayForward>();
  @$core.pragma('dart2js:noInline')
  static RelayForward getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RelayForward>(create);
  static RelayForward? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get relayId => $_getN(0);
  @$pb.TagNumber(1)
  set relayId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasRelayId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRelayId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get finalRecipientId => $_getN(1);
  @$pb.TagNumber(2)
  set finalRecipientId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasFinalRecipientId() => $_has(1);
  @$pb.TagNumber(2)
  void clearFinalRecipientId() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get wrappedEnvelope => $_getN(2);
  @$pb.TagNumber(3)
  set wrappedEnvelope($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasWrappedEnvelope() => $_has(2);
  @$pb.TagNumber(3)
  void clearWrappedEnvelope() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get hopCount => $_getIZ(3);
  @$pb.TagNumber(4)
  set hopCount($core.int v) { $_setUnsignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasHopCount() => $_has(3);
  @$pb.TagNumber(4)
  void clearHopCount() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get maxHops => $_getIZ(4);
  @$pb.TagNumber(5)
  set maxHops($core.int v) { $_setUnsignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasMaxHops() => $_has(4);
  @$pb.TagNumber(5)
  void clearMaxHops() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.List<$core.int>> get visitedNodes => $_getList(5);

  @$pb.TagNumber(7)
  $core.List<$core.int> get originNodeId => $_getN(6);
  @$pb.TagNumber(7)
  set originNodeId($core.List<$core.int> v) { $_setBytes(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasOriginNodeId() => $_has(6);
  @$pb.TagNumber(7)
  void clearOriginNodeId() => clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get createdAtMs => $_getI64(7);
  @$pb.TagNumber(8)
  set createdAtMs($fixnum.Int64 v) { $_setInt64(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasCreatedAtMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearCreatedAtMs() => clearField(8);

  @$pb.TagNumber(9)
  $core.int get ttl => $_getIZ(8);
  @$pb.TagNumber(9)
  set ttl($core.int v) { $_setUnsignedInt32(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasTtl() => $_has(8);
  @$pb.TagNumber(9)
  void clearTtl() => clearField(9);

  @$pb.TagNumber(10)
  $core.List<$core.int> get originUserId => $_getN(9);
  @$pb.TagNumber(10)
  set originUserId($core.List<$core.int> v) { $_setBytes(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasOriginUserId() => $_has(9);
  @$pb.TagNumber(10)
  void clearOriginUserId() => clearField(10);
}

class RelayAck extends $pb.GeneratedMessage {
  factory RelayAck({
    $core.List<$core.int>? relayId,
    $core.bool? delivered,
    $core.List<$core.int>? relayedBy,
  }) {
    final $result = create();
    if (relayId != null) {
      $result.relayId = relayId;
    }
    if (delivered != null) {
      $result.delivered = delivered;
    }
    if (relayedBy != null) {
      $result.relayedBy = relayedBy;
    }
    return $result;
  }
  RelayAck._() : super();
  factory RelayAck.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RelayAck.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RelayAck', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'relayId', $pb.PbFieldType.OY)
    ..aOB(2, _omitFieldNames ? '' : 'delivered')
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'relayedBy', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RelayAck clone() => RelayAck()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RelayAck copyWith(void Function(RelayAck) updates) => super.copyWith((message) => updates(message as RelayAck)) as RelayAck;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RelayAck create() => RelayAck._();
  RelayAck createEmptyInstance() => create();
  static $pb.PbList<RelayAck> createRepeated() => $pb.PbList<RelayAck>();
  @$core.pragma('dart2js:noInline')
  static RelayAck getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RelayAck>(create);
  static RelayAck? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get relayId => $_getN(0);
  @$pb.TagNumber(1)
  set relayId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasRelayId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRelayId() => clearField(1);

  @$pb.TagNumber(2)
  $core.bool get delivered => $_getBF(1);
  @$pb.TagNumber(2)
  set delivered($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDelivered() => $_has(1);
  @$pb.TagNumber(2)
  void clearDelivered() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get relayedBy => $_getN(2);
  @$pb.TagNumber(3)
  set relayedBy($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasRelayedBy() => $_has(2);
  @$pb.TagNumber(3)
  void clearRelayedBy() => clearField(3);
}

class PeerReachabilityQuery extends $pb.GeneratedMessage {
  factory PeerReachabilityQuery({
    $core.List<$core.int>? targetNodeId,
    $core.List<$core.int>? queryId,
    $core.String? probeIp,
    $core.int? probePort,
  }) {
    final $result = create();
    if (targetNodeId != null) {
      $result.targetNodeId = targetNodeId;
    }
    if (queryId != null) {
      $result.queryId = queryId;
    }
    if (probeIp != null) {
      $result.probeIp = probeIp;
    }
    if (probePort != null) {
      $result.probePort = probePort;
    }
    return $result;
  }
  PeerReachabilityQuery._() : super();
  factory PeerReachabilityQuery.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PeerReachabilityQuery.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PeerReachabilityQuery', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'targetNodeId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'queryId', $pb.PbFieldType.OY)
    ..aOS(3, _omitFieldNames ? '' : 'probeIp')
    ..a<$core.int>(4, _omitFieldNames ? '' : 'probePort', $pb.PbFieldType.OU3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PeerReachabilityQuery clone() => PeerReachabilityQuery()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PeerReachabilityQuery copyWith(void Function(PeerReachabilityQuery) updates) => super.copyWith((message) => updates(message as PeerReachabilityQuery)) as PeerReachabilityQuery;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PeerReachabilityQuery create() => PeerReachabilityQuery._();
  PeerReachabilityQuery createEmptyInstance() => create();
  static $pb.PbList<PeerReachabilityQuery> createRepeated() => $pb.PbList<PeerReachabilityQuery>();
  @$core.pragma('dart2js:noInline')
  static PeerReachabilityQuery getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PeerReachabilityQuery>(create);
  static PeerReachabilityQuery? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get targetNodeId => $_getN(0);
  @$pb.TagNumber(1)
  set targetNodeId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTargetNodeId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTargetNodeId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get queryId => $_getN(1);
  @$pb.TagNumber(2)
  set queryId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasQueryId() => $_has(1);
  @$pb.TagNumber(2)
  void clearQueryId() => clearField(2);

  /// V3.1.33: Port probe — ask responder to send a CPRB probe packet
  /// to this address. Used to verify port forwarding (manual DNAT, UPnP)
  /// without relying on UPnP AddPortMapping success.
  @$pb.TagNumber(3)
  $core.String get probeIp => $_getSZ(2);
  @$pb.TagNumber(3)
  set probeIp($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasProbeIp() => $_has(2);
  @$pb.TagNumber(3)
  void clearProbeIp() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get probePort => $_getIZ(3);
  @$pb.TagNumber(4)
  set probePort($core.int v) { $_setUnsignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasProbePort() => $_has(3);
  @$pb.TagNumber(4)
  void clearProbePort() => clearField(4);
}

class PeerReachabilityResponse extends $pb.GeneratedMessage {
  factory PeerReachabilityResponse({
    $core.List<$core.int>? targetNodeId,
    $core.List<$core.int>? queryId,
    $core.bool? canReach,
    $fixnum.Int64? lastSeenMs,
  }) {
    final $result = create();
    if (targetNodeId != null) {
      $result.targetNodeId = targetNodeId;
    }
    if (queryId != null) {
      $result.queryId = queryId;
    }
    if (canReach != null) {
      $result.canReach = canReach;
    }
    if (lastSeenMs != null) {
      $result.lastSeenMs = lastSeenMs;
    }
    return $result;
  }
  PeerReachabilityResponse._() : super();
  factory PeerReachabilityResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PeerReachabilityResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PeerReachabilityResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'targetNodeId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'queryId', $pb.PbFieldType.OY)
    ..aOB(3, _omitFieldNames ? '' : 'canReach')
    ..a<$fixnum.Int64>(4, _omitFieldNames ? '' : 'lastSeenMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PeerReachabilityResponse clone() => PeerReachabilityResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PeerReachabilityResponse copyWith(void Function(PeerReachabilityResponse) updates) => super.copyWith((message) => updates(message as PeerReachabilityResponse)) as PeerReachabilityResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PeerReachabilityResponse create() => PeerReachabilityResponse._();
  PeerReachabilityResponse createEmptyInstance() => create();
  static $pb.PbList<PeerReachabilityResponse> createRepeated() => $pb.PbList<PeerReachabilityResponse>();
  @$core.pragma('dart2js:noInline')
  static PeerReachabilityResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PeerReachabilityResponse>(create);
  static PeerReachabilityResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get targetNodeId => $_getN(0);
  @$pb.TagNumber(1)
  set targetNodeId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTargetNodeId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTargetNodeId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get queryId => $_getN(1);
  @$pb.TagNumber(2)
  set queryId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasQueryId() => $_has(1);
  @$pb.TagNumber(2)
  void clearQueryId() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get canReach => $_getBF(2);
  @$pb.TagNumber(3)
  set canReach($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasCanReach() => $_has(2);
  @$pb.TagNumber(3)
  void clearCanReach() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get lastSeenMs => $_getI64(3);
  @$pb.TagNumber(4)
  set lastSeenMs($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasLastSeenMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearLastSeenMs() => clearField(4);
}

class PeerStore extends $pb.GeneratedMessage {
  factory PeerStore({
    $core.List<$core.int>? recipientNodeId,
    $core.List<$core.int>? wrappedEnvelope,
    $core.List<$core.int>? storeId,
    $fixnum.Int64? ttlMs,
  }) {
    final $result = create();
    if (recipientNodeId != null) {
      $result.recipientNodeId = recipientNodeId;
    }
    if (wrappedEnvelope != null) {
      $result.wrappedEnvelope = wrappedEnvelope;
    }
    if (storeId != null) {
      $result.storeId = storeId;
    }
    if (ttlMs != null) {
      $result.ttlMs = ttlMs;
    }
    return $result;
  }
  PeerStore._() : super();
  factory PeerStore.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PeerStore.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PeerStore', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'recipientNodeId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'wrappedEnvelope', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'storeId', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(4, _omitFieldNames ? '' : 'ttlMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PeerStore clone() => PeerStore()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PeerStore copyWith(void Function(PeerStore) updates) => super.copyWith((message) => updates(message as PeerStore)) as PeerStore;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PeerStore create() => PeerStore._();
  PeerStore createEmptyInstance() => create();
  static $pb.PbList<PeerStore> createRepeated() => $pb.PbList<PeerStore>();
  @$core.pragma('dart2js:noInline')
  static PeerStore getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PeerStore>(create);
  static PeerStore? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get recipientNodeId => $_getN(0);
  @$pb.TagNumber(1)
  set recipientNodeId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasRecipientNodeId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRecipientNodeId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get wrappedEnvelope => $_getN(1);
  @$pb.TagNumber(2)
  set wrappedEnvelope($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasWrappedEnvelope() => $_has(1);
  @$pb.TagNumber(2)
  void clearWrappedEnvelope() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get storeId => $_getN(2);
  @$pb.TagNumber(3)
  set storeId($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasStoreId() => $_has(2);
  @$pb.TagNumber(3)
  void clearStoreId() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get ttlMs => $_getI64(3);
  @$pb.TagNumber(4)
  set ttlMs($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTtlMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearTtlMs() => clearField(4);
}

class PeerStoreAck extends $pb.GeneratedMessage {
  factory PeerStoreAck({
    $core.List<$core.int>? storeId,
    $core.bool? accepted,
  }) {
    final $result = create();
    if (storeId != null) {
      $result.storeId = storeId;
    }
    if (accepted != null) {
      $result.accepted = accepted;
    }
    return $result;
  }
  PeerStoreAck._() : super();
  factory PeerStoreAck.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PeerStoreAck.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PeerStoreAck', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'storeId', $pb.PbFieldType.OY)
    ..aOB(2, _omitFieldNames ? '' : 'accepted')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PeerStoreAck clone() => PeerStoreAck()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PeerStoreAck copyWith(void Function(PeerStoreAck) updates) => super.copyWith((message) => updates(message as PeerStoreAck)) as PeerStoreAck;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PeerStoreAck create() => PeerStoreAck._();
  PeerStoreAck createEmptyInstance() => create();
  static $pb.PbList<PeerStoreAck> createRepeated() => $pb.PbList<PeerStoreAck>();
  @$core.pragma('dart2js:noInline')
  static PeerStoreAck getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PeerStoreAck>(create);
  static PeerStoreAck? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get storeId => $_getN(0);
  @$pb.TagNumber(1)
  set storeId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasStoreId() => $_has(0);
  @$pb.TagNumber(1)
  void clearStoreId() => clearField(1);

  @$pb.TagNumber(2)
  $core.bool get accepted => $_getBF(1);
  @$pb.TagNumber(2)
  set accepted($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasAccepted() => $_has(1);
  @$pb.TagNumber(2)
  void clearAccepted() => clearField(2);
}

class PeerRetrieve extends $pb.GeneratedMessage {
  factory PeerRetrieve({
    $core.List<$core.int>? requesterNodeId,
  }) {
    final $result = create();
    if (requesterNodeId != null) {
      $result.requesterNodeId = requesterNodeId;
    }
    return $result;
  }
  PeerRetrieve._() : super();
  factory PeerRetrieve.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PeerRetrieve.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PeerRetrieve', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'requesterNodeId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PeerRetrieve clone() => PeerRetrieve()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PeerRetrieve copyWith(void Function(PeerRetrieve) updates) => super.copyWith((message) => updates(message as PeerRetrieve)) as PeerRetrieve;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PeerRetrieve create() => PeerRetrieve._();
  PeerRetrieve createEmptyInstance() => create();
  static $pb.PbList<PeerRetrieve> createRepeated() => $pb.PbList<PeerRetrieve>();
  @$core.pragma('dart2js:noInline')
  static PeerRetrieve getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PeerRetrieve>(create);
  static PeerRetrieve? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get requesterNodeId => $_getN(0);
  @$pb.TagNumber(1)
  set requesterNodeId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasRequesterNodeId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequesterNodeId() => clearField(1);
}

class PeerRetrieveResponse extends $pb.GeneratedMessage {
  factory PeerRetrieveResponse({
    $core.Iterable<$core.List<$core.int>>? storedEnvelopes,
    $core.int? remaining,
  }) {
    final $result = create();
    if (storedEnvelopes != null) {
      $result.storedEnvelopes.addAll(storedEnvelopes);
    }
    if (remaining != null) {
      $result.remaining = remaining;
    }
    return $result;
  }
  PeerRetrieveResponse._() : super();
  factory PeerRetrieveResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PeerRetrieveResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PeerRetrieveResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..p<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'storedEnvelopes', $pb.PbFieldType.PY)
    ..a<$core.int>(2, _omitFieldNames ? '' : 'remaining', $pb.PbFieldType.OU3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PeerRetrieveResponse clone() => PeerRetrieveResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PeerRetrieveResponse copyWith(void Function(PeerRetrieveResponse) updates) => super.copyWith((message) => updates(message as PeerRetrieveResponse)) as PeerRetrieveResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PeerRetrieveResponse create() => PeerRetrieveResponse._();
  PeerRetrieveResponse createEmptyInstance() => create();
  static $pb.PbList<PeerRetrieveResponse> createRepeated() => $pb.PbList<PeerRetrieveResponse>();
  @$core.pragma('dart2js:noInline')
  static PeerRetrieveResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PeerRetrieveResponse>(create);
  static PeerRetrieveResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.List<$core.int>> get storedEnvelopes => $_getList(0);

  @$pb.TagNumber(2)
  $core.int get remaining => $_getIZ(1);
  @$pb.TagNumber(2)
  set remaining($core.int v) { $_setUnsignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasRemaining() => $_has(1);
  @$pb.TagNumber(2)
  void clearRemaining() => clearField(2);
}

class RouteEntryProto extends $pb.GeneratedMessage {
  factory RouteEntryProto({
    $core.List<$core.int>? destination,
    $core.int? hopCount,
    $core.int? cost,
    ConnectionTypeProto? connType,
    $fixnum.Int64? lastConfirmedMs,
    $core.int? capabilities,
  }) {
    final $result = create();
    if (destination != null) {
      $result.destination = destination;
    }
    if (hopCount != null) {
      $result.hopCount = hopCount;
    }
    if (cost != null) {
      $result.cost = cost;
    }
    if (connType != null) {
      $result.connType = connType;
    }
    if (lastConfirmedMs != null) {
      $result.lastConfirmedMs = lastConfirmedMs;
    }
    if (capabilities != null) {
      $result.capabilities = capabilities;
    }
    return $result;
  }
  RouteEntryProto._() : super();
  factory RouteEntryProto.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RouteEntryProto.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RouteEntryProto', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'destination', $pb.PbFieldType.OY)
    ..a<$core.int>(2, _omitFieldNames ? '' : 'hopCount', $pb.PbFieldType.O3)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'cost', $pb.PbFieldType.O3)
    ..e<ConnectionTypeProto>(4, _omitFieldNames ? '' : 'connType', $pb.PbFieldType.OE, defaultOrMaker: ConnectionTypeProto.CT_LAN_SAME_SUBNET, valueOf: ConnectionTypeProto.valueOf, enumValues: ConnectionTypeProto.values)
    ..aInt64(5, _omitFieldNames ? '' : 'lastConfirmedMs')
    ..a<$core.int>(6, _omitFieldNames ? '' : 'capabilities', $pb.PbFieldType.OU3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RouteEntryProto clone() => RouteEntryProto()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RouteEntryProto copyWith(void Function(RouteEntryProto) updates) => super.copyWith((message) => updates(message as RouteEntryProto)) as RouteEntryProto;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RouteEntryProto create() => RouteEntryProto._();
  RouteEntryProto createEmptyInstance() => create();
  static $pb.PbList<RouteEntryProto> createRepeated() => $pb.PbList<RouteEntryProto>();
  @$core.pragma('dart2js:noInline')
  static RouteEntryProto getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RouteEntryProto>(create);
  static RouteEntryProto? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get destination => $_getN(0);
  @$pb.TagNumber(1)
  set destination($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasDestination() => $_has(0);
  @$pb.TagNumber(1)
  void clearDestination() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get hopCount => $_getIZ(1);
  @$pb.TagNumber(2)
  set hopCount($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasHopCount() => $_has(1);
  @$pb.TagNumber(2)
  void clearHopCount() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get cost => $_getIZ(2);
  @$pb.TagNumber(3)
  set cost($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasCost() => $_has(2);
  @$pb.TagNumber(3)
  void clearCost() => clearField(3);

  @$pb.TagNumber(4)
  ConnectionTypeProto get connType => $_getN(3);
  @$pb.TagNumber(4)
  set connType(ConnectionTypeProto v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasConnType() => $_has(3);
  @$pb.TagNumber(4)
  void clearConnType() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get lastConfirmedMs => $_getI64(4);
  @$pb.TagNumber(5)
  set lastConfirmedMs($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasLastConfirmedMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearLastConfirmedMs() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get capabilities => $_getIZ(5);
  @$pb.TagNumber(6)
  set capabilities($core.int v) { $_setUnsignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasCapabilities() => $_has(5);
  @$pb.TagNumber(6)
  void clearCapabilities() => clearField(6);
}

class RouteUpdateMsg extends $pb.GeneratedMessage {
  factory RouteUpdateMsg({
    $core.Iterable<RouteEntryProto>? routes,
  }) {
    final $result = create();
    if (routes != null) {
      $result.routes.addAll(routes);
    }
    return $result;
  }
  RouteUpdateMsg._() : super();
  factory RouteUpdateMsg.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RouteUpdateMsg.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RouteUpdateMsg', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..pc<RouteEntryProto>(1, _omitFieldNames ? '' : 'routes', $pb.PbFieldType.PM, subBuilder: RouteEntryProto.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RouteUpdateMsg clone() => RouteUpdateMsg()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RouteUpdateMsg copyWith(void Function(RouteUpdateMsg) updates) => super.copyWith((message) => updates(message as RouteUpdateMsg)) as RouteUpdateMsg;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RouteUpdateMsg create() => RouteUpdateMsg._();
  RouteUpdateMsg createEmptyInstance() => create();
  static $pb.PbList<RouteUpdateMsg> createRepeated() => $pb.PbList<RouteUpdateMsg>();
  @$core.pragma('dart2js:noInline')
  static RouteUpdateMsg getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RouteUpdateMsg>(create);
  static RouteUpdateMsg? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<RouteEntryProto> get routes => $_getList(0);
}

class HolePunchRequest extends $pb.GeneratedMessage {
  factory HolePunchRequest({
    $core.List<$core.int>? targetNodeId,
    $core.String? myPublicIp,
    $core.int? myPublicPort,
    $core.List<$core.int>? requestId,
  }) {
    final $result = create();
    if (targetNodeId != null) {
      $result.targetNodeId = targetNodeId;
    }
    if (myPublicIp != null) {
      $result.myPublicIp = myPublicIp;
    }
    if (myPublicPort != null) {
      $result.myPublicPort = myPublicPort;
    }
    if (requestId != null) {
      $result.requestId = requestId;
    }
    return $result;
  }
  HolePunchRequest._() : super();
  factory HolePunchRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory HolePunchRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'HolePunchRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'targetNodeId', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'myPublicIp')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'myPublicPort', $pb.PbFieldType.O3)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'requestId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  HolePunchRequest clone() => HolePunchRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  HolePunchRequest copyWith(void Function(HolePunchRequest) updates) => super.copyWith((message) => updates(message as HolePunchRequest)) as HolePunchRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HolePunchRequest create() => HolePunchRequest._();
  HolePunchRequest createEmptyInstance() => create();
  static $pb.PbList<HolePunchRequest> createRepeated() => $pb.PbList<HolePunchRequest>();
  @$core.pragma('dart2js:noInline')
  static HolePunchRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<HolePunchRequest>(create);
  static HolePunchRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get targetNodeId => $_getN(0);
  @$pb.TagNumber(1)
  set targetNodeId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTargetNodeId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTargetNodeId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get myPublicIp => $_getSZ(1);
  @$pb.TagNumber(2)
  set myPublicIp($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMyPublicIp() => $_has(1);
  @$pb.TagNumber(2)
  void clearMyPublicIp() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get myPublicPort => $_getIZ(2);
  @$pb.TagNumber(3)
  set myPublicPort($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMyPublicPort() => $_has(2);
  @$pb.TagNumber(3)
  void clearMyPublicPort() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get requestId => $_getN(3);
  @$pb.TagNumber(4)
  set requestId($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasRequestId() => $_has(3);
  @$pb.TagNumber(4)
  void clearRequestId() => clearField(4);
}

class HolePunchNotify extends $pb.GeneratedMessage {
  factory HolePunchNotify({
    $core.List<$core.int>? requesterNodeId,
    $core.String? requesterIp,
    $core.int? requesterPort,
    $core.List<$core.int>? requestId,
  }) {
    final $result = create();
    if (requesterNodeId != null) {
      $result.requesterNodeId = requesterNodeId;
    }
    if (requesterIp != null) {
      $result.requesterIp = requesterIp;
    }
    if (requesterPort != null) {
      $result.requesterPort = requesterPort;
    }
    if (requestId != null) {
      $result.requestId = requestId;
    }
    return $result;
  }
  HolePunchNotify._() : super();
  factory HolePunchNotify.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory HolePunchNotify.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'HolePunchNotify', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'requesterNodeId', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'requesterIp')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'requesterPort', $pb.PbFieldType.O3)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'requestId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  HolePunchNotify clone() => HolePunchNotify()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  HolePunchNotify copyWith(void Function(HolePunchNotify) updates) => super.copyWith((message) => updates(message as HolePunchNotify)) as HolePunchNotify;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HolePunchNotify create() => HolePunchNotify._();
  HolePunchNotify createEmptyInstance() => create();
  static $pb.PbList<HolePunchNotify> createRepeated() => $pb.PbList<HolePunchNotify>();
  @$core.pragma('dart2js:noInline')
  static HolePunchNotify getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<HolePunchNotify>(create);
  static HolePunchNotify? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get requesterNodeId => $_getN(0);
  @$pb.TagNumber(1)
  set requesterNodeId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasRequesterNodeId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequesterNodeId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get requesterIp => $_getSZ(1);
  @$pb.TagNumber(2)
  set requesterIp($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasRequesterIp() => $_has(1);
  @$pb.TagNumber(2)
  void clearRequesterIp() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get requesterPort => $_getIZ(2);
  @$pb.TagNumber(3)
  set requesterPort($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasRequesterPort() => $_has(2);
  @$pb.TagNumber(3)
  void clearRequesterPort() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get requestId => $_getN(3);
  @$pb.TagNumber(4)
  set requestId($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasRequestId() => $_has(3);
  @$pb.TagNumber(4)
  void clearRequestId() => clearField(4);
}

class HolePunchPing extends $pb.GeneratedMessage {
  factory HolePunchPing({
    $core.List<$core.int>? requestId,
    $core.List<$core.int>? senderNodeId,
    $fixnum.Int64? timestampMs,
  }) {
    final $result = create();
    if (requestId != null) {
      $result.requestId = requestId;
    }
    if (senderNodeId != null) {
      $result.senderNodeId = senderNodeId;
    }
    if (timestampMs != null) {
      $result.timestampMs = timestampMs;
    }
    return $result;
  }
  HolePunchPing._() : super();
  factory HolePunchPing.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory HolePunchPing.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'HolePunchPing', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'requestId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'senderNodeId', $pb.PbFieldType.OY)
    ..aInt64(3, _omitFieldNames ? '' : 'timestampMs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  HolePunchPing clone() => HolePunchPing()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  HolePunchPing copyWith(void Function(HolePunchPing) updates) => super.copyWith((message) => updates(message as HolePunchPing)) as HolePunchPing;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HolePunchPing create() => HolePunchPing._();
  HolePunchPing createEmptyInstance() => create();
  static $pb.PbList<HolePunchPing> createRepeated() => $pb.PbList<HolePunchPing>();
  @$core.pragma('dart2js:noInline')
  static HolePunchPing getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<HolePunchPing>(create);
  static HolePunchPing? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get requestId => $_getN(0);
  @$pb.TagNumber(1)
  set requestId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get senderNodeId => $_getN(1);
  @$pb.TagNumber(2)
  set senderNodeId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSenderNodeId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSenderNodeId() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get timestampMs => $_getI64(2);
  @$pb.TagNumber(3)
  set timestampMs($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTimestampMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearTimestampMs() => clearField(3);
}

class HolePunchPong extends $pb.GeneratedMessage {
  factory HolePunchPong({
    $core.List<$core.int>? requestId,
    $core.List<$core.int>? senderNodeId,
    $fixnum.Int64? pingTimestampMs,
  }) {
    final $result = create();
    if (requestId != null) {
      $result.requestId = requestId;
    }
    if (senderNodeId != null) {
      $result.senderNodeId = senderNodeId;
    }
    if (pingTimestampMs != null) {
      $result.pingTimestampMs = pingTimestampMs;
    }
    return $result;
  }
  HolePunchPong._() : super();
  factory HolePunchPong.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory HolePunchPong.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'HolePunchPong', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'requestId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'senderNodeId', $pb.PbFieldType.OY)
    ..aInt64(3, _omitFieldNames ? '' : 'pingTimestampMs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  HolePunchPong clone() => HolePunchPong()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  HolePunchPong copyWith(void Function(HolePunchPong) updates) => super.copyWith((message) => updates(message as HolePunchPong)) as HolePunchPong;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HolePunchPong create() => HolePunchPong._();
  HolePunchPong createEmptyInstance() => create();
  static $pb.PbList<HolePunchPong> createRepeated() => $pb.PbList<HolePunchPong>();
  @$core.pragma('dart2js:noInline')
  static HolePunchPong getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<HolePunchPong>(create);
  static HolePunchPong? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get requestId => $_getN(0);
  @$pb.TagNumber(1)
  set requestId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get senderNodeId => $_getN(1);
  @$pb.TagNumber(2)
  set senderNodeId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSenderNodeId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSenderNodeId() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get pingTimestampMs => $_getI64(2);
  @$pb.TagNumber(3)
  set pingTimestampMs($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasPingTimestampMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearPingTimestampMs() => clearField(3);
}

/// D1 (§4.3 Trust anchor): one soft-re-key link old→new. Link shape mirrors
/// KeyRotationBroadcast — the OLD key signs the successor pubkeys, proving
/// continuity from the founding key (whose hash is the userId) to the
/// currently embedded manifest keys.
class RotationChainLinkProto extends $pb.GeneratedMessage {
  factory RotationChainLinkProto({
    $core.List<$core.int>? oldEd25519Pk,
    $core.List<$core.int>? newEd25519Pk,
    $core.List<$core.int>? newMlDsaPk,
    $core.List<$core.int>? oldSignatureEd25519,
  }) {
    final $result = create();
    if (oldEd25519Pk != null) {
      $result.oldEd25519Pk = oldEd25519Pk;
    }
    if (newEd25519Pk != null) {
      $result.newEd25519Pk = newEd25519Pk;
    }
    if (newMlDsaPk != null) {
      $result.newMlDsaPk = newMlDsaPk;
    }
    if (oldSignatureEd25519 != null) {
      $result.oldSignatureEd25519 = oldSignatureEd25519;
    }
    return $result;
  }
  RotationChainLinkProto._() : super();
  factory RotationChainLinkProto.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RotationChainLinkProto.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RotationChainLinkProto', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'oldEd25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'newEd25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'newMlDsaPk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'oldSignatureEd25519', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RotationChainLinkProto clone() => RotationChainLinkProto()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RotationChainLinkProto copyWith(void Function(RotationChainLinkProto) updates) => super.copyWith((message) => updates(message as RotationChainLinkProto)) as RotationChainLinkProto;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RotationChainLinkProto create() => RotationChainLinkProto._();
  RotationChainLinkProto createEmptyInstance() => create();
  static $pb.PbList<RotationChainLinkProto> createRepeated() => $pb.PbList<RotationChainLinkProto>();
  @$core.pragma('dart2js:noInline')
  static RotationChainLinkProto getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RotationChainLinkProto>(create);
  static RotationChainLinkProto? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get oldEd25519Pk => $_getN(0);
  @$pb.TagNumber(1)
  set oldEd25519Pk($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasOldEd25519Pk() => $_has(0);
  @$pb.TagNumber(1)
  void clearOldEd25519Pk() => clearField(1);

  /// old pk MUST hash to the userId (founding
  /// anchor); link[i>0]'s old pk MUST equal
  /// link[i-1].new_ed25519_pk
  @$pb.TagNumber(2)
  $core.List<$core.int> get newEd25519Pk => $_getN(1);
  @$pb.TagNumber(2)
  set newEd25519Pk($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasNewEd25519Pk() => $_has(1);
  @$pb.TagNumber(2)
  void clearNewEd25519Pk() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get newMlDsaPk => $_getN(2);
  @$pb.TagNumber(3)
  set newMlDsaPk($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasNewMlDsaPk() => $_has(2);
  @$pb.TagNumber(3)
  void clearNewMlDsaPk() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get oldSignatureEd25519 => $_getN(3);
  @$pb.TagNumber(4)
  set oldSignatureEd25519($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasOldSignatureEd25519() => $_has(3);
  @$pb.TagNumber(4)
  void clearOldSignatureEd25519() => clearField(4);
}

class AuthManifestProto extends $pb.GeneratedMessage {
  factory AuthManifestProto({
    $core.List<$core.int>? userId,
    $core.Iterable<$core.List<$core.int>>? authorizedDeviceNodeIds,
    $core.int? ttlSeconds,
    $fixnum.Int64? sequenceNumber,
    $fixnum.Int64? publishedAtMs,
    $core.List<$core.int>? ed25519Sig,
    $core.List<$core.int>? mlDsaSig,
    $core.List<$core.int>? userEd25519Pk,
    $core.List<$core.int>? userMlDsaPk,
    $core.Iterable<RotationChainLinkProto>? rotationChain,
    $core.Iterable<$0.DeviceDelegationCertProto>? deviceDelegations,
    $core.Iterable<$0.AuthorizedDeviceSigningKeys>? deviceSigKeys,
    $0.DeviceSetChangeProof? deviceSetChangeProof,
  }) {
    final $result = create();
    if (userId != null) {
      $result.userId = userId;
    }
    if (authorizedDeviceNodeIds != null) {
      $result.authorizedDeviceNodeIds.addAll(authorizedDeviceNodeIds);
    }
    if (ttlSeconds != null) {
      $result.ttlSeconds = ttlSeconds;
    }
    if (sequenceNumber != null) {
      $result.sequenceNumber = sequenceNumber;
    }
    if (publishedAtMs != null) {
      $result.publishedAtMs = publishedAtMs;
    }
    if (ed25519Sig != null) {
      $result.ed25519Sig = ed25519Sig;
    }
    if (mlDsaSig != null) {
      $result.mlDsaSig = mlDsaSig;
    }
    if (userEd25519Pk != null) {
      $result.userEd25519Pk = userEd25519Pk;
    }
    if (userMlDsaPk != null) {
      $result.userMlDsaPk = userMlDsaPk;
    }
    if (rotationChain != null) {
      $result.rotationChain.addAll(rotationChain);
    }
    if (deviceDelegations != null) {
      $result.deviceDelegations.addAll(deviceDelegations);
    }
    if (deviceSigKeys != null) {
      $result.deviceSigKeys.addAll(deviceSigKeys);
    }
    if (deviceSetChangeProof != null) {
      $result.deviceSetChangeProof = deviceSetChangeProof;
    }
    return $result;
  }
  AuthManifestProto._() : super();
  factory AuthManifestProto.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AuthManifestProto.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'AuthManifestProto', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'userId', $pb.PbFieldType.OY)
    ..p<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'authorizedDeviceNodeIds', $pb.PbFieldType.PY)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'ttlSeconds', $pb.PbFieldType.O3)
    ..aInt64(4, _omitFieldNames ? '' : 'sequenceNumber')
    ..aInt64(5, _omitFieldNames ? '' : 'publishedAtMs')
    ..a<$core.List<$core.int>>(6, _omitFieldNames ? '' : 'ed25519Sig', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(7, _omitFieldNames ? '' : 'mlDsaSig', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(8, _omitFieldNames ? '' : 'userEd25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(9, _omitFieldNames ? '' : 'userMlDsaPk', $pb.PbFieldType.OY)
    ..pc<RotationChainLinkProto>(10, _omitFieldNames ? '' : 'rotationChain', $pb.PbFieldType.PM, subBuilder: RotationChainLinkProto.create)
    ..pc<$0.DeviceDelegationCertProto>(11, _omitFieldNames ? '' : 'deviceDelegations', $pb.PbFieldType.PM, subBuilder: $0.DeviceDelegationCertProto.create)
    ..pc<$0.AuthorizedDeviceSigningKeys>(12, _omitFieldNames ? '' : 'deviceSigKeys', $pb.PbFieldType.PM, subBuilder: $0.AuthorizedDeviceSigningKeys.create)
    ..aOM<$0.DeviceSetChangeProof>(13, _omitFieldNames ? '' : 'deviceSetChangeProof', subBuilder: $0.DeviceSetChangeProof.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AuthManifestProto clone() => AuthManifestProto()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AuthManifestProto copyWith(void Function(AuthManifestProto) updates) => super.copyWith((message) => updates(message as AuthManifestProto)) as AuthManifestProto;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AuthManifestProto create() => AuthManifestProto._();
  AuthManifestProto createEmptyInstance() => create();
  static $pb.PbList<AuthManifestProto> createRepeated() => $pb.PbList<AuthManifestProto>();
  @$core.pragma('dart2js:noInline')
  static AuthManifestProto getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AuthManifestProto>(create);
  static AuthManifestProto? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get userId => $_getN(0);
  @$pb.TagNumber(1)
  set userId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.List<$core.int>> get authorizedDeviceNodeIds => $_getList(1);

  @$pb.TagNumber(3)
  $core.int get ttlSeconds => $_getIZ(2);
  @$pb.TagNumber(3)
  set ttlSeconds($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTtlSeconds() => $_has(2);
  @$pb.TagNumber(3)
  void clearTtlSeconds() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get sequenceNumber => $_getI64(3);
  @$pb.TagNumber(4)
  set sequenceNumber($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasSequenceNumber() => $_has(3);
  @$pb.TagNumber(4)
  void clearSequenceNumber() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get publishedAtMs => $_getI64(4);
  @$pb.TagNumber(5)
  set publishedAtMs($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasPublishedAtMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearPublishedAtMs() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get ed25519Sig => $_getN(5);
  @$pb.TagNumber(6)
  set ed25519Sig($core.List<$core.int> v) { $_setBytes(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasEd25519Sig() => $_has(5);
  @$pb.TagNumber(6)
  void clearEd25519Sig() => clearField(6);

  @$pb.TagNumber(7)
  $core.List<$core.int> get mlDsaSig => $_getN(6);
  @$pb.TagNumber(7)
  set mlDsaSig($core.List<$core.int> v) { $_setBytes(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasMlDsaSig() => $_has(6);
  @$pb.TagNumber(7)
  void clearMlDsaSig() => clearField(7);

  /// D1 (§4.3 Trust anchor): self-certifying embedded user pubkeys, covered by
  /// the hybrid signature.
  /// S368: this used to say that a record WITHOUT these keys ("legacy records,
  /// pre-D1 builds") would be treated as "legacy-unverified". This milder
  /// level no longer exists — `AnchorStatus.legacy` is removed, and a
  /// record without embedded keys counts as `forged`. The fields are
  /// therefore mandatory, not optional-with-leniency.
  @$pb.TagNumber(8)
  $core.List<$core.int> get userEd25519Pk => $_getN(7);
  @$pb.TagNumber(8)
  set userEd25519Pk($core.List<$core.int> v) { $_setBytes(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasUserEd25519Pk() => $_has(7);
  @$pb.TagNumber(8)
  void clearUserEd25519Pk() => clearField(8);

  @$pb.TagNumber(9)
  $core.List<$core.int> get userMlDsaPk => $_getN(8);
  @$pb.TagNumber(9)
  set userMlDsaPk($core.List<$core.int> v) { $_setBytes(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasUserMlDsaPk() => $_has(8);
  @$pb.TagNumber(9)
  void clearUserMlDsaPk() => clearField(9);

  /// Founding-key → current-key continuity after soft re-key (§7.4b). Empty
  /// unless the identity has rotated.
  @$pb.TagNumber(10)
  $core.List<RotationChainLinkProto> get rotationChain => $_getList(9);

  /// LD-1 (§7.1 Linked-Device): delegation certificates for linked devices.
  /// Empty on single-device identities and pre-LD builds. A device present in
  /// authorized_device_node_ids but NOT in device_delegations is the Primary
  /// (seed-holder) or a legacy full-authority device. A device present in BOTH
  /// is a Linked Device with bounded capabilities. Old builds silently ignore
  /// this field (unknown proto field).
  @$pb.TagNumber(11)
  $core.List<$0.DeviceDelegationCertProto> get deviceDelegations => $_getList(10);

  /// §7.5: Device-Sig pubkeys for all authorized devices (Primary + Linked).
  /// Enables receiver-enforced co-authorization of emergency key rotations.
  @$pb.TagNumber(12)
  $core.List<$0.AuthorizedDeviceSigningKeys> get deviceSigKeys => $_getList(11);

  /// §7.5: Proof that device-set shrinks were co-authorized by remaining devices.
  @$pb.TagNumber(13)
  $0.DeviceSetChangeProof get deviceSetChangeProof => $_getN(12);
  @$pb.TagNumber(13)
  set deviceSetChangeProof($0.DeviceSetChangeProof v) { setField(13, v); }
  @$pb.TagNumber(13)
  $core.bool hasDeviceSetChangeProof() => $_has(12);
  @$pb.TagNumber(13)
  void clearDeviceSetChangeProof() => clearField(13);
  @$pb.TagNumber(13)
  $0.DeviceSetChangeProof ensureDeviceSetChangeProof() => $_ensure(12);
}

class LivenessRecordProto extends $pb.GeneratedMessage {
  factory LivenessRecordProto({
    $core.List<$core.int>? userId,
    $core.List<$core.int>? deviceNodeId,
    $core.Iterable<$0.PeerAddressProto>? addresses,
    $core.int? ttlSeconds,
    $fixnum.Int64? sequenceNumber,
    $fixnum.Int64? publishedAtMs,
    $core.List<$core.int>? ed25519Sig,
    $core.List<$core.int>? signerEd25519Pk,
  }) {
    final $result = create();
    if (userId != null) {
      $result.userId = userId;
    }
    if (deviceNodeId != null) {
      $result.deviceNodeId = deviceNodeId;
    }
    if (addresses != null) {
      $result.addresses.addAll(addresses);
    }
    if (ttlSeconds != null) {
      $result.ttlSeconds = ttlSeconds;
    }
    if (sequenceNumber != null) {
      $result.sequenceNumber = sequenceNumber;
    }
    if (publishedAtMs != null) {
      $result.publishedAtMs = publishedAtMs;
    }
    if (ed25519Sig != null) {
      $result.ed25519Sig = ed25519Sig;
    }
    if (signerEd25519Pk != null) {
      $result.signerEd25519Pk = signerEd25519Pk;
    }
    return $result;
  }
  LivenessRecordProto._() : super();
  factory LivenessRecordProto.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LivenessRecordProto.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LivenessRecordProto', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'userId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'deviceNodeId', $pb.PbFieldType.OY)
    ..pc<$0.PeerAddressProto>(3, _omitFieldNames ? '' : 'addresses', $pb.PbFieldType.PM, subBuilder: $0.PeerAddressProto.create)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'ttlSeconds', $pb.PbFieldType.O3)
    ..aInt64(5, _omitFieldNames ? '' : 'sequenceNumber')
    ..aInt64(6, _omitFieldNames ? '' : 'publishedAtMs')
    ..a<$core.List<$core.int>>(7, _omitFieldNames ? '' : 'ed25519Sig', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(8, _omitFieldNames ? '' : 'signerEd25519Pk', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LivenessRecordProto clone() => LivenessRecordProto()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LivenessRecordProto copyWith(void Function(LivenessRecordProto) updates) => super.copyWith((message) => updates(message as LivenessRecordProto)) as LivenessRecordProto;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LivenessRecordProto create() => LivenessRecordProto._();
  LivenessRecordProto createEmptyInstance() => create();
  static $pb.PbList<LivenessRecordProto> createRepeated() => $pb.PbList<LivenessRecordProto>();
  @$core.pragma('dart2js:noInline')
  static LivenessRecordProto getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LivenessRecordProto>(create);
  static LivenessRecordProto? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get userId => $_getN(0);
  @$pb.TagNumber(1)
  set userId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get deviceNodeId => $_getN(1);
  @$pb.TagNumber(2)
  set deviceNodeId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDeviceNodeId() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeviceNodeId() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$0.PeerAddressProto> get addresses => $_getList(2);

  @$pb.TagNumber(4)
  $core.int get ttlSeconds => $_getIZ(3);
  @$pb.TagNumber(4)
  set ttlSeconds($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTtlSeconds() => $_has(3);
  @$pb.TagNumber(4)
  void clearTtlSeconds() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get sequenceNumber => $_getI64(4);
  @$pb.TagNumber(5)
  set sequenceNumber($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasSequenceNumber() => $_has(4);
  @$pb.TagNumber(5)
  void clearSequenceNumber() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get publishedAtMs => $_getI64(5);
  @$pb.TagNumber(6)
  set publishedAtMs($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasPublishedAtMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearPublishedAtMs() => clearField(6);

  @$pb.TagNumber(7)
  $core.List<$core.int> get ed25519Sig => $_getN(6);
  @$pb.TagNumber(7)
  set ed25519Sig($core.List<$core.int> v) { $_setBytes(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasEd25519Sig() => $_has(6);
  @$pb.TagNumber(7)
  void clearEd25519Sig() => clearField(7);

  ///  P5 (§7.1.4 vs §4.3): a linked device does not hold the user SK and
  ///  can no longer sign under the user anchor after a rotation. It
  ///  therefore signs with its delegated device key and names the used PK
  ///  here. Empty = signed directly under the user key as before
  ///  (primary path).
  ///
  ///  P6 (working rule #5): the delegation certificate is NOT sent along.
  ///  It cost ~5.3 KB per record (ML-DSA-PK 1952 B + ML-DSA-Sig 3309 B) and
  ///  fragmented every liveness republish (every 15 min to up to 10
  ///  replicators). Instead, the receiver takes the certificate from the
  ///  AuthManifest it holds for this user anyway
  ///  (`AuthManifest.delegationFor(deviceId)`). This weakens nothing: P5
  ///  was already fail-closed without an anchor, because the ML-DSA half of the
  ///  certificate cannot be checked otherwise — the manifest dependency already
  ///  existed and is only made explicit here. Field 9 stays reserved.
  @$pb.TagNumber(8)
  $core.List<$core.int> get signerEd25519Pk => $_getN(7);
  @$pb.TagNumber(8)
  set signerEd25519Pk($core.List<$core.int> v) { $_setBytes(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasSignerEd25519Pk() => $_has(7);
  @$pb.TagNumber(8)
  void clearSignerEd25519Pk() => clearField(8);
}

class IdentityAuthRetrieveRequest extends $pb.GeneratedMessage {
  factory IdentityAuthRetrieveRequest({
    $core.List<$core.int>? userId,
    $fixnum.Int64? minimumSeq,
  }) {
    final $result = create();
    if (userId != null) {
      $result.userId = userId;
    }
    if (minimumSeq != null) {
      $result.minimumSeq = minimumSeq;
    }
    return $result;
  }
  IdentityAuthRetrieveRequest._() : super();
  factory IdentityAuthRetrieveRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory IdentityAuthRetrieveRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'IdentityAuthRetrieveRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'userId', $pb.PbFieldType.OY)
    ..aInt64(2, _omitFieldNames ? '' : 'minimumSeq')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  IdentityAuthRetrieveRequest clone() => IdentityAuthRetrieveRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  IdentityAuthRetrieveRequest copyWith(void Function(IdentityAuthRetrieveRequest) updates) => super.copyWith((message) => updates(message as IdentityAuthRetrieveRequest)) as IdentityAuthRetrieveRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static IdentityAuthRetrieveRequest create() => IdentityAuthRetrieveRequest._();
  IdentityAuthRetrieveRequest createEmptyInstance() => create();
  static $pb.PbList<IdentityAuthRetrieveRequest> createRepeated() => $pb.PbList<IdentityAuthRetrieveRequest>();
  @$core.pragma('dart2js:noInline')
  static IdentityAuthRetrieveRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<IdentityAuthRetrieveRequest>(create);
  static IdentityAuthRetrieveRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get userId => $_getN(0);
  @$pb.TagNumber(1)
  set userId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get minimumSeq => $_getI64(1);
  @$pb.TagNumber(2)
  set minimumSeq($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMinimumSeq() => $_has(1);
  @$pb.TagNumber(2)
  void clearMinimumSeq() => clearField(2);
}

class IdentityLiveRetrieveRequest extends $pb.GeneratedMessage {
  factory IdentityLiveRetrieveRequest({
    $core.List<$core.int>? userId,
    $core.List<$core.int>? deviceNodeId,
  }) {
    final $result = create();
    if (userId != null) {
      $result.userId = userId;
    }
    if (deviceNodeId != null) {
      $result.deviceNodeId = deviceNodeId;
    }
    return $result;
  }
  IdentityLiveRetrieveRequest._() : super();
  factory IdentityLiveRetrieveRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory IdentityLiveRetrieveRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'IdentityLiveRetrieveRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'userId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'deviceNodeId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  IdentityLiveRetrieveRequest clone() => IdentityLiveRetrieveRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  IdentityLiveRetrieveRequest copyWith(void Function(IdentityLiveRetrieveRequest) updates) => super.copyWith((message) => updates(message as IdentityLiveRetrieveRequest)) as IdentityLiveRetrieveRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static IdentityLiveRetrieveRequest create() => IdentityLiveRetrieveRequest._();
  IdentityLiveRetrieveRequest createEmptyInstance() => create();
  static $pb.PbList<IdentityLiveRetrieveRequest> createRepeated() => $pb.PbList<IdentityLiveRetrieveRequest>();
  @$core.pragma('dart2js:noInline')
  static IdentityLiveRetrieveRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<IdentityLiveRetrieveRequest>(create);
  static IdentityLiveRetrieveRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get userId => $_getN(0);
  @$pb.TagNumber(1)
  set userId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get deviceNodeId => $_getN(1);
  @$pb.TagNumber(2)
  set deviceNodeId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDeviceNodeId() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeviceNodeId() => clearField(2);
}

/// Welle 5 (§4.3): pull DeviceKemRecordV3 from K=10 closest replicators per
/// (userId, deviceId). Storage-Key SHA-256("kem" || user_id || device_id).
class IdentityKemRetrieveRequest extends $pb.GeneratedMessage {
  factory IdentityKemRetrieveRequest({
    $core.List<$core.int>? userId,
    $core.List<$core.int>? deviceId,
    $fixnum.Int64? minimumSeq,
  }) {
    final $result = create();
    if (userId != null) {
      $result.userId = userId;
    }
    if (deviceId != null) {
      $result.deviceId = deviceId;
    }
    if (minimumSeq != null) {
      $result.minimumSeq = minimumSeq;
    }
    return $result;
  }
  IdentityKemRetrieveRequest._() : super();
  factory IdentityKemRetrieveRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory IdentityKemRetrieveRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'IdentityKemRetrieveRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'userId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'deviceId', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(3, _omitFieldNames ? '' : 'minimumSeq', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  IdentityKemRetrieveRequest clone() => IdentityKemRetrieveRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  IdentityKemRetrieveRequest copyWith(void Function(IdentityKemRetrieveRequest) updates) => super.copyWith((message) => updates(message as IdentityKemRetrieveRequest)) as IdentityKemRetrieveRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static IdentityKemRetrieveRequest create() => IdentityKemRetrieveRequest._();
  IdentityKemRetrieveRequest createEmptyInstance() => create();
  static $pb.PbList<IdentityKemRetrieveRequest> createRepeated() => $pb.PbList<IdentityKemRetrieveRequest>();
  @$core.pragma('dart2js:noInline')
  static IdentityKemRetrieveRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<IdentityKemRetrieveRequest>(create);
  static IdentityKemRetrieveRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get userId => $_getN(0);
  @$pb.TagNumber(1)
  set userId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get deviceId => $_getN(1);
  @$pb.TagNumber(2)
  set deviceId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDeviceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeviceId() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get minimumSeq => $_getI64(2);
  @$pb.TagNumber(3)
  set minimumSeq($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMinimumSeq() => $_has(2);
  @$pb.TagNumber(3)
  void clearMinimumSeq() => clearField(3);
}

///  ── Outer Layer (NetworkPacket) — what relays see ───────────────────────
///
///  Subject of the sigs = device keypair (NOT user keypair). Application frames
///  hybrid (Ed25519+ML-DSA), infrastructure frames (DHT pings, RTT, hole punch)
///  only Ed25519 to save bandwidth — deviceMlDsaSig then empty.
class NetworkPacketV3 extends $pb.GeneratedMessage {
  factory NetworkPacketV3({
    $core.int? version,
    $core.int? flags,
    $core.List<$core.int>? nextHopDeviceId,
    $core.List<$core.int>? senderDeviceId,
    $fixnum.Int64? timestampMs,
    $core.int? ttl,
    $core.int? hopCount,
    $core.List<$core.int>? networkTag,
    ProofOfWork? pow,
    $core.List<$core.int>? deviceEd25519Sig,
    $core.List<$core.int>? deviceMlDsaSig,
    PayloadTypeV3? payloadType,
    $core.List<$core.int>? payload,
  }) {
    final $result = create();
    if (version != null) {
      $result.version = version;
    }
    if (flags != null) {
      $result.flags = flags;
    }
    if (nextHopDeviceId != null) {
      $result.nextHopDeviceId = nextHopDeviceId;
    }
    if (senderDeviceId != null) {
      $result.senderDeviceId = senderDeviceId;
    }
    if (timestampMs != null) {
      $result.timestampMs = timestampMs;
    }
    if (ttl != null) {
      $result.ttl = ttl;
    }
    if (hopCount != null) {
      $result.hopCount = hopCount;
    }
    if (networkTag != null) {
      $result.networkTag = networkTag;
    }
    if (pow != null) {
      $result.pow = pow;
    }
    if (deviceEd25519Sig != null) {
      $result.deviceEd25519Sig = deviceEd25519Sig;
    }
    if (deviceMlDsaSig != null) {
      $result.deviceMlDsaSig = deviceMlDsaSig;
    }
    if (payloadType != null) {
      $result.payloadType = payloadType;
    }
    if (payload != null) {
      $result.payload = payload;
    }
    return $result;
  }
  NetworkPacketV3._() : super();
  factory NetworkPacketV3.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory NetworkPacketV3.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'NetworkPacketV3', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'version', $pb.PbFieldType.OU3)
    ..a<$core.int>(2, _omitFieldNames ? '' : 'flags', $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'nextHopDeviceId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'senderDeviceId', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(5, _omitFieldNames ? '' : 'timestampMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.int>(6, _omitFieldNames ? '' : 'ttl', $pb.PbFieldType.OU3)
    ..a<$core.int>(7, _omitFieldNames ? '' : 'hopCount', $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(8, _omitFieldNames ? '' : 'networkTag', $pb.PbFieldType.OY)
    ..aOM<ProofOfWork>(9, _omitFieldNames ? '' : 'pow', subBuilder: ProofOfWork.create)
    ..a<$core.List<$core.int>>(10, _omitFieldNames ? '' : 'deviceEd25519Sig', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(11, _omitFieldNames ? '' : 'deviceMlDsaSig', $pb.PbFieldType.OY)
    ..e<PayloadTypeV3>(12, _omitFieldNames ? '' : 'payloadType', $pb.PbFieldType.OE, defaultOrMaker: PayloadTypeV3.PAYLOAD_APPLICATION_FRAME, valueOf: PayloadTypeV3.valueOf, enumValues: PayloadTypeV3.values)
    ..a<$core.List<$core.int>>(13, _omitFieldNames ? '' : 'payload', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  NetworkPacketV3 clone() => NetworkPacketV3()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  NetworkPacketV3 copyWith(void Function(NetworkPacketV3) updates) => super.copyWith((message) => updates(message as NetworkPacketV3)) as NetworkPacketV3;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static NetworkPacketV3 create() => NetworkPacketV3._();
  NetworkPacketV3 createEmptyInstance() => create();
  static $pb.PbList<NetworkPacketV3> createRepeated() => $pb.PbList<NetworkPacketV3>();
  @$core.pragma('dart2js:noInline')
  static NetworkPacketV3 getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<NetworkPacketV3>(create);
  static NetworkPacketV3? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get version => $_getIZ(0);
  @$pb.TagNumber(1)
  set version($core.int v) { $_setUnsignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearVersion() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get flags => $_getIZ(1);
  @$pb.TagNumber(2)
  set flags($core.int v) { $_setUnsignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasFlags() => $_has(1);
  @$pb.TagNumber(2)
  void clearFlags() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get nextHopDeviceId => $_getN(2);
  @$pb.TagNumber(3)
  set nextHopDeviceId($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasNextHopDeviceId() => $_has(2);
  @$pb.TagNumber(3)
  void clearNextHopDeviceId() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get senderDeviceId => $_getN(3);
  @$pb.TagNumber(4)
  set senderDeviceId($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasSenderDeviceId() => $_has(3);
  @$pb.TagNumber(4)
  void clearSenderDeviceId() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get timestampMs => $_getI64(4);
  @$pb.TagNumber(5)
  set timestampMs($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasTimestampMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearTimestampMs() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get ttl => $_getIZ(5);
  @$pb.TagNumber(6)
  set ttl($core.int v) { $_setUnsignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasTtl() => $_has(5);
  @$pb.TagNumber(6)
  void clearTtl() => clearField(6);

  @$pb.TagNumber(7)
  $core.int get hopCount => $_getIZ(6);
  @$pb.TagNumber(7)
  set hopCount($core.int v) { $_setUnsignedInt32(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasHopCount() => $_has(6);
  @$pb.TagNumber(7)
  void clearHopCount() => clearField(7);

  @$pb.TagNumber(8)
  $core.List<$core.int> get networkTag => $_getN(7);
  @$pb.TagNumber(8)
  set networkTag($core.List<$core.int> v) { $_setBytes(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasNetworkTag() => $_has(7);
  @$pb.TagNumber(8)
  void clearNetworkTag() => clearField(8);

  @$pb.TagNumber(9)
  ProofOfWork get pow => $_getN(8);
  @$pb.TagNumber(9)
  set pow(ProofOfWork v) { setField(9, v); }
  @$pb.TagNumber(9)
  $core.bool hasPow() => $_has(8);
  @$pb.TagNumber(9)
  void clearPow() => clearField(9);
  @$pb.TagNumber(9)
  ProofOfWork ensurePow() => $_ensure(8);

  /// Sigs (Subjekt = Device-Keypair)
  @$pb.TagNumber(10)
  $core.List<$core.int> get deviceEd25519Sig => $_getN(9);
  @$pb.TagNumber(10)
  set deviceEd25519Sig($core.List<$core.int> v) { $_setBytes(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasDeviceEd25519Sig() => $_has(9);
  @$pb.TagNumber(10)
  void clearDeviceEd25519Sig() => clearField(10);

  @$pb.TagNumber(11)
  $core.List<$core.int> get deviceMlDsaSig => $_getN(10);
  @$pb.TagNumber(11)
  set deviceMlDsaSig($core.List<$core.int> v) { $_setBytes(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasDeviceMlDsaSig() => $_has(10);
  @$pb.TagNumber(11)
  void clearDeviceMlDsaSig() => clearField(11);

  /// Payload-Discriminator
  @$pb.TagNumber(12)
  PayloadTypeV3 get payloadType => $_getN(11);
  @$pb.TagNumber(12)
  set payloadType(PayloadTypeV3 v) { setField(12, v); }
  @$pb.TagNumber(12)
  $core.bool hasPayloadType() => $_has(11);
  @$pb.TagNumber(12)
  void clearPayloadType() => clearField(12);

  @$pb.TagNumber(13)
  $core.List<$core.int> get payload => $_getN(12);
  @$pb.TagNumber(13)
  set payload($core.List<$core.int> v) { $_setBytes(12, v); }
  @$pb.TagNumber(13)
  $core.bool hasPayload() => $_has(12);
  @$pb.TagNumber(13)
  void clearPayload() => clearField(13);
}

///  ── Inner Layer (ApplicationFrame) — KEM-encrypted under recipient user PK ─
///
///  Transported in NetworkPacketV3.payload as KEM ciphertext via PerMessageKemV3.
///  Subject of the sigs = user keypair (for end-to-end identity authentication).
class ApplicationFrameV3 extends $pb.GeneratedMessage {
  factory ApplicationFrameV3({
    $core.List<$core.int>? recipientUserId,
    $core.List<$core.int>? senderUserId,
    $fixnum.Int64? timestampMs,
    $core.List<$core.int>? messageId,
    MessageTypeV3? messageType,
    $core.List<$core.int>? payload,
    $core.List<$core.int>? userEd25519Sig,
    $core.List<$core.int>? userMlDsaSig,
    $0.ContentMetadata? contentMetadata,
    $0.EditMetadata? editMetadata,
    $0.ExpiryMetadata? expiryMetadata,
    ErasureCodingMetadata? erasureMetadata,
    CompressionType? compression,
    $core.List<$core.int>? groupId,
    $fixnum.Int64? groupMembershipEpoch,
    $core.List<$core.int>? groupMembershipHash,
  }) {
    final $result = create();
    if (recipientUserId != null) {
      $result.recipientUserId = recipientUserId;
    }
    if (senderUserId != null) {
      $result.senderUserId = senderUserId;
    }
    if (timestampMs != null) {
      $result.timestampMs = timestampMs;
    }
    if (messageId != null) {
      $result.messageId = messageId;
    }
    if (messageType != null) {
      $result.messageType = messageType;
    }
    if (payload != null) {
      $result.payload = payload;
    }
    if (userEd25519Sig != null) {
      $result.userEd25519Sig = userEd25519Sig;
    }
    if (userMlDsaSig != null) {
      $result.userMlDsaSig = userMlDsaSig;
    }
    if (contentMetadata != null) {
      $result.contentMetadata = contentMetadata;
    }
    if (editMetadata != null) {
      $result.editMetadata = editMetadata;
    }
    if (expiryMetadata != null) {
      $result.expiryMetadata = expiryMetadata;
    }
    if (erasureMetadata != null) {
      $result.erasureMetadata = erasureMetadata;
    }
    if (compression != null) {
      $result.compression = compression;
    }
    if (groupId != null) {
      $result.groupId = groupId;
    }
    if (groupMembershipEpoch != null) {
      $result.groupMembershipEpoch = groupMembershipEpoch;
    }
    if (groupMembershipHash != null) {
      $result.groupMembershipHash = groupMembershipHash;
    }
    return $result;
  }
  ApplicationFrameV3._() : super();
  factory ApplicationFrameV3.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ApplicationFrameV3.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ApplicationFrameV3', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'recipientUserId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'senderUserId', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(4, _omitFieldNames ? '' : 'timestampMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'messageId', $pb.PbFieldType.OY)
    ..e<MessageTypeV3>(6, _omitFieldNames ? '' : 'messageType', $pb.PbFieldType.OE, defaultOrMaker: MessageTypeV3.MTV3_TEXT, valueOf: MessageTypeV3.valueOf, enumValues: MessageTypeV3.values)
    ..a<$core.List<$core.int>>(7, _omitFieldNames ? '' : 'payload', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(10, _omitFieldNames ? '' : 'userEd25519Sig', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(11, _omitFieldNames ? '' : 'userMlDsaSig', $pb.PbFieldType.OY)
    ..aOM<$0.ContentMetadata>(12, _omitFieldNames ? '' : 'contentMetadata', subBuilder: $0.ContentMetadata.create)
    ..aOM<$0.EditMetadata>(13, _omitFieldNames ? '' : 'editMetadata', subBuilder: $0.EditMetadata.create)
    ..aOM<$0.ExpiryMetadata>(14, _omitFieldNames ? '' : 'expiryMetadata', subBuilder: $0.ExpiryMetadata.create)
    ..aOM<ErasureCodingMetadata>(15, _omitFieldNames ? '' : 'erasureMetadata', subBuilder: ErasureCodingMetadata.create)
    ..e<CompressionType>(16, _omitFieldNames ? '' : 'compression', $pb.PbFieldType.OE, defaultOrMaker: CompressionType.NONE, valueOf: CompressionType.valueOf, enumValues: CompressionType.values)
    ..a<$core.List<$core.int>>(17, _omitFieldNames ? '' : 'groupId', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(18, _omitFieldNames ? '' : 'groupMembershipEpoch', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(19, _omitFieldNames ? '' : 'groupMembershipHash', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ApplicationFrameV3 clone() => ApplicationFrameV3()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ApplicationFrameV3 copyWith(void Function(ApplicationFrameV3) updates) => super.copyWith((message) => updates(message as ApplicationFrameV3)) as ApplicationFrameV3;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ApplicationFrameV3 create() => ApplicationFrameV3._();
  ApplicationFrameV3 createEmptyInstance() => create();
  static $pb.PbList<ApplicationFrameV3> createRepeated() => $pb.PbList<ApplicationFrameV3>();
  @$core.pragma('dart2js:noInline')
  static ApplicationFrameV3 getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ApplicationFrameV3>(create);
  static ApplicationFrameV3? _defaultInstance;

  @$pb.TagNumber(2)
  $core.List<$core.int> get recipientUserId => $_getN(0);
  @$pb.TagNumber(2)
  set recipientUserId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(2)
  $core.bool hasRecipientUserId() => $_has(0);
  @$pb.TagNumber(2)
  void clearRecipientUserId() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get senderUserId => $_getN(1);
  @$pb.TagNumber(3)
  set senderUserId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(3)
  $core.bool hasSenderUserId() => $_has(1);
  @$pb.TagNumber(3)
  void clearSenderUserId() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get timestampMs => $_getI64(2);
  @$pb.TagNumber(4)
  set timestampMs($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(4)
  $core.bool hasTimestampMs() => $_has(2);
  @$pb.TagNumber(4)
  void clearTimestampMs() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get messageId => $_getN(3);
  @$pb.TagNumber(5)
  set messageId($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(5)
  $core.bool hasMessageId() => $_has(3);
  @$pb.TagNumber(5)
  void clearMessageId() => clearField(5);

  @$pb.TagNumber(6)
  MessageTypeV3 get messageType => $_getN(4);
  @$pb.TagNumber(6)
  set messageType(MessageTypeV3 v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasMessageType() => $_has(4);
  @$pb.TagNumber(6)
  void clearMessageType() => clearField(6);

  @$pb.TagNumber(7)
  $core.List<$core.int> get payload => $_getN(5);
  @$pb.TagNumber(7)
  set payload($core.List<$core.int> v) { $_setBytes(5, v); }
  @$pb.TagNumber(7)
  $core.bool hasPayload() => $_has(5);
  @$pb.TagNumber(7)
  void clearPayload() => clearField(7);

  /// Sigs (Subjekt = User-Keypair) — End-to-End-Identity-Authenticity
  @$pb.TagNumber(10)
  $core.List<$core.int> get userEd25519Sig => $_getN(6);
  @$pb.TagNumber(10)
  set userEd25519Sig($core.List<$core.int> v) { $_setBytes(6, v); }
  @$pb.TagNumber(10)
  $core.bool hasUserEd25519Sig() => $_has(6);
  @$pb.TagNumber(10)
  void clearUserEd25519Sig() => clearField(10);

  @$pb.TagNumber(11)
  $core.List<$core.int> get userMlDsaSig => $_getN(7);
  @$pb.TagNumber(11)
  set userMlDsaSig($core.List<$core.int> v) { $_setBytes(7, v); }
  @$pb.TagNumber(11)
  $core.bool hasUserMlDsaSig() => $_has(7);
  @$pb.TagNumber(11)
  void clearUserMlDsaSig() => clearField(11);

  /// Optional metadata (reuse of existing sub-messages)
  @$pb.TagNumber(12)
  $0.ContentMetadata get contentMetadata => $_getN(8);
  @$pb.TagNumber(12)
  set contentMetadata($0.ContentMetadata v) { setField(12, v); }
  @$pb.TagNumber(12)
  $core.bool hasContentMetadata() => $_has(8);
  @$pb.TagNumber(12)
  void clearContentMetadata() => clearField(12);
  @$pb.TagNumber(12)
  $0.ContentMetadata ensureContentMetadata() => $_ensure(8);

  @$pb.TagNumber(13)
  $0.EditMetadata get editMetadata => $_getN(9);
  @$pb.TagNumber(13)
  set editMetadata($0.EditMetadata v) { setField(13, v); }
  @$pb.TagNumber(13)
  $core.bool hasEditMetadata() => $_has(9);
  @$pb.TagNumber(13)
  void clearEditMetadata() => clearField(13);
  @$pb.TagNumber(13)
  $0.EditMetadata ensureEditMetadata() => $_ensure(9);

  @$pb.TagNumber(14)
  $0.ExpiryMetadata get expiryMetadata => $_getN(10);
  @$pb.TagNumber(14)
  set expiryMetadata($0.ExpiryMetadata v) { setField(14, v); }
  @$pb.TagNumber(14)
  $core.bool hasExpiryMetadata() => $_has(10);
  @$pb.TagNumber(14)
  void clearExpiryMetadata() => clearField(14);
  @$pb.TagNumber(14)
  $0.ExpiryMetadata ensureExpiryMetadata() => $_ensure(10);

  @$pb.TagNumber(15)
  ErasureCodingMetadata get erasureMetadata => $_getN(11);
  @$pb.TagNumber(15)
  set erasureMetadata(ErasureCodingMetadata v) { setField(15, v); }
  @$pb.TagNumber(15)
  $core.bool hasErasureMetadata() => $_has(11);
  @$pb.TagNumber(15)
  void clearErasureMetadata() => clearField(15);
  @$pb.TagNumber(15)
  ErasureCodingMetadata ensureErasureMetadata() => $_ensure(11);

  @$pb.TagNumber(16)
  CompressionType get compression => $_getN(12);
  @$pb.TagNumber(16)
  set compression(CompressionType v) { setField(16, v); }
  @$pb.TagNumber(16)
  $core.bool hasCompression() => $_has(12);
  @$pb.TagNumber(16)
  void clearCompression() => clearField(16);

  /// Conversation routing — empty for DM; set for group/channel pairwise fan-out.
  /// Receiver dispatches to the matching group/channel conversation. Calendar/Polls
  /// payload-internal group_ids are semantically distinct (linked-event association).
  @$pb.TagNumber(17)
  $core.List<$core.int> get groupId => $_getN(13);
  @$pb.TagNumber(17)
  set groupId($core.List<$core.int> v) { $_setBytes(13, v); }
  @$pb.TagNumber(17)
  $core.bool hasGroupId() => $_has(13);
  @$pb.TagNumber(17)
  void clearGroupId() => clearField(17);

  /// GM-1 (§9.1.4): sender's local group membership state for split-view detection
  @$pb.TagNumber(18)
  $fixnum.Int64 get groupMembershipEpoch => $_getI64(14);
  @$pb.TagNumber(18)
  set groupMembershipEpoch($fixnum.Int64 v) { $_setInt64(14, v); }
  @$pb.TagNumber(18)
  $core.bool hasGroupMembershipEpoch() => $_has(14);
  @$pb.TagNumber(18)
  void clearGroupMembershipEpoch() => clearField(18);

  @$pb.TagNumber(19)
  $core.List<$core.int> get groupMembershipHash => $_getN(15);
  @$pb.TagNumber(19)
  set groupMembershipHash($core.List<$core.int> v) { $_setBytes(15, v); }
  @$pb.TagNumber(19)
  $core.bool hasGroupMembershipHash() => $_has(15);
  @$pb.TagNumber(19)
  void clearGroupMembershipHash() => clearField(19);
}

///  ── KEM header v3 (Sec H-5 v2) ──────────────────────────────────────────
///
///  Carries the ApplicationFrameV3 ciphertext + KEM material. Sits in
///  NetworkPacketV3.payload (with payload_type = PAYLOAD_APPLICATION_FRAME).
class PerMessageKemV3 extends $pb.GeneratedMessage {
  factory PerMessageKemV3({
    $core.List<$core.int>? x25519Ciphertext,
    $core.List<$core.int>? mlKemCiphertext,
    $core.List<$core.int>? aeadCiphertext,
    $core.List<$core.int>? aeadNonce,
    $core.int? version,
  }) {
    final $result = create();
    if (x25519Ciphertext != null) {
      $result.x25519Ciphertext = x25519Ciphertext;
    }
    if (mlKemCiphertext != null) {
      $result.mlKemCiphertext = mlKemCiphertext;
    }
    if (aeadCiphertext != null) {
      $result.aeadCiphertext = aeadCiphertext;
    }
    if (aeadNonce != null) {
      $result.aeadNonce = aeadNonce;
    }
    if (version != null) {
      $result.version = version;
    }
    return $result;
  }
  PerMessageKemV3._() : super();
  factory PerMessageKemV3.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PerMessageKemV3.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PerMessageKemV3', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'x25519Ciphertext', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'mlKemCiphertext', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'aeadCiphertext', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'aeadNonce', $pb.PbFieldType.OY)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'version', $pb.PbFieldType.OU3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PerMessageKemV3 clone() => PerMessageKemV3()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PerMessageKemV3 copyWith(void Function(PerMessageKemV3) updates) => super.copyWith((message) => updates(message as PerMessageKemV3)) as PerMessageKemV3;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PerMessageKemV3 create() => PerMessageKemV3._();
  PerMessageKemV3 createEmptyInstance() => create();
  static $pb.PbList<PerMessageKemV3> createRepeated() => $pb.PbList<PerMessageKemV3>();
  @$core.pragma('dart2js:noInline')
  static PerMessageKemV3 getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PerMessageKemV3>(create);
  static PerMessageKemV3? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get x25519Ciphertext => $_getN(0);
  @$pb.TagNumber(1)
  set x25519Ciphertext($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasX25519Ciphertext() => $_has(0);
  @$pb.TagNumber(1)
  void clearX25519Ciphertext() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get mlKemCiphertext => $_getN(1);
  @$pb.TagNumber(2)
  set mlKemCiphertext($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMlKemCiphertext() => $_has(1);
  @$pb.TagNumber(2)
  void clearMlKemCiphertext() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get aeadCiphertext => $_getN(2);
  @$pb.TagNumber(3)
  set aeadCiphertext($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAeadCiphertext() => $_has(2);
  @$pb.TagNumber(3)
  void clearAeadCiphertext() => clearField(3);

  /// [S368: the addition -- OR InfrastructureFrameV3 -- is dropped, the type no longer exists]
  @$pb.TagNumber(4)
  $core.List<$core.int> get aeadNonce => $_getN(3);
  @$pb.TagNumber(4)
  set aeadNonce($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasAeadNonce() => $_has(3);
  @$pb.TagNumber(4)
  void clearAeadNonce() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get version => $_getIZ(4);
  @$pb.TagNumber(5)
  set version($core.int v) { $_setUnsignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasVersion() => $_has(4);
  @$pb.TagNumber(5)
  void clearVersion() => clearField(5);
}

///  ── Identity resolution V3 (§4.3) ───────────────────────────────────────
///
///  AuthManifestV3 extends AuthManifestProto (old) with the user pubkeys,
///  so that the receiver can verify the sig WITHOUT a separate identity lookup.
///  Spec: Appendix A.5 AuthManifest.
class AuthManifestV3 extends $pb.GeneratedMessage {
  factory AuthManifestV3({
    $core.List<$core.int>? userId,
    $core.Iterable<$core.List<$core.int>>? authorizedDeviceIds,
    $fixnum.Int64? ttlSeconds,
    $fixnum.Int64? sequenceNumber,
    $fixnum.Int64? publishedAtMs,
    $core.List<$core.int>? ed25519Sig,
    $core.List<$core.int>? mlDsaSig,
    $core.List<$core.int>? userEd25519Pk,
    $core.List<$core.int>? userMlDsaPk,
  }) {
    final $result = create();
    if (userId != null) {
      $result.userId = userId;
    }
    if (authorizedDeviceIds != null) {
      $result.authorizedDeviceIds.addAll(authorizedDeviceIds);
    }
    if (ttlSeconds != null) {
      $result.ttlSeconds = ttlSeconds;
    }
    if (sequenceNumber != null) {
      $result.sequenceNumber = sequenceNumber;
    }
    if (publishedAtMs != null) {
      $result.publishedAtMs = publishedAtMs;
    }
    if (ed25519Sig != null) {
      $result.ed25519Sig = ed25519Sig;
    }
    if (mlDsaSig != null) {
      $result.mlDsaSig = mlDsaSig;
    }
    if (userEd25519Pk != null) {
      $result.userEd25519Pk = userEd25519Pk;
    }
    if (userMlDsaPk != null) {
      $result.userMlDsaPk = userMlDsaPk;
    }
    return $result;
  }
  AuthManifestV3._() : super();
  factory AuthManifestV3.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AuthManifestV3.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'AuthManifestV3', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'userId', $pb.PbFieldType.OY)
    ..p<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'authorizedDeviceIds', $pb.PbFieldType.PY)
    ..a<$fixnum.Int64>(3, _omitFieldNames ? '' : 'ttlSeconds', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(4, _omitFieldNames ? '' : 'sequenceNumber', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(5, _omitFieldNames ? '' : 'publishedAtMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(6, _omitFieldNames ? '' : 'ed25519Sig', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(7, _omitFieldNames ? '' : 'mlDsaSig', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(8, _omitFieldNames ? '' : 'userEd25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(9, _omitFieldNames ? '' : 'userMlDsaPk', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AuthManifestV3 clone() => AuthManifestV3()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AuthManifestV3 copyWith(void Function(AuthManifestV3) updates) => super.copyWith((message) => updates(message as AuthManifestV3)) as AuthManifestV3;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AuthManifestV3 create() => AuthManifestV3._();
  AuthManifestV3 createEmptyInstance() => create();
  static $pb.PbList<AuthManifestV3> createRepeated() => $pb.PbList<AuthManifestV3>();
  @$core.pragma('dart2js:noInline')
  static AuthManifestV3 getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AuthManifestV3>(create);
  static AuthManifestV3? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get userId => $_getN(0);
  @$pb.TagNumber(1)
  set userId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.List<$core.int>> get authorizedDeviceIds => $_getList(1);

  @$pb.TagNumber(3)
  $fixnum.Int64 get ttlSeconds => $_getI64(2);
  @$pb.TagNumber(3)
  set ttlSeconds($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTtlSeconds() => $_has(2);
  @$pb.TagNumber(3)
  void clearTtlSeconds() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get sequenceNumber => $_getI64(3);
  @$pb.TagNumber(4)
  set sequenceNumber($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasSequenceNumber() => $_has(3);
  @$pb.TagNumber(4)
  void clearSequenceNumber() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get publishedAtMs => $_getI64(4);
  @$pb.TagNumber(5)
  set publishedAtMs($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasPublishedAtMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearPublishedAtMs() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get ed25519Sig => $_getN(5);
  @$pb.TagNumber(6)
  set ed25519Sig($core.List<$core.int> v) { $_setBytes(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasEd25519Sig() => $_has(5);
  @$pb.TagNumber(6)
  void clearEd25519Sig() => clearField(6);

  @$pb.TagNumber(7)
  $core.List<$core.int> get mlDsaSig => $_getN(6);
  @$pb.TagNumber(7)
  set mlDsaSig($core.List<$core.int> v) { $_setBytes(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasMlDsaSig() => $_has(6);
  @$pb.TagNumber(7)
  void clearMlDsaSig() => clearField(7);

  @$pb.TagNumber(8)
  $core.List<$core.int> get userEd25519Pk => $_getN(7);
  @$pb.TagNumber(8)
  set userEd25519Pk($core.List<$core.int> v) { $_setBytes(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasUserEd25519Pk() => $_has(7);
  @$pb.TagNumber(8)
  void clearUserEd25519Pk() => clearField(8);

  @$pb.TagNumber(9)
  $core.List<$core.int> get userMlDsaPk => $_getN(8);
  @$pb.TagNumber(9)
  set userMlDsaPk($core.List<$core.int> v) { $_setBytes(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasUserMlDsaPk() => $_has(8);
  @$pb.TagNumber(9)
  void clearUserMlDsaPk() => clearField(9);
}

class LivenessRecordV3 extends $pb.GeneratedMessage {
  factory LivenessRecordV3({
    $core.List<$core.int>? userId,
    $core.List<$core.int>? deviceNodeId,
    $core.Iterable<$0.PeerAddressProto>? addresses,
    $fixnum.Int64? ttlSeconds,
    $fixnum.Int64? sequenceNumber,
    $fixnum.Int64? publishedAtMs,
    $core.List<$core.int>? ed25519Sig,
    $core.List<$core.int>? deviceEd25519Pk,
  }) {
    final $result = create();
    if (userId != null) {
      $result.userId = userId;
    }
    if (deviceNodeId != null) {
      $result.deviceNodeId = deviceNodeId;
    }
    if (addresses != null) {
      $result.addresses.addAll(addresses);
    }
    if (ttlSeconds != null) {
      $result.ttlSeconds = ttlSeconds;
    }
    if (sequenceNumber != null) {
      $result.sequenceNumber = sequenceNumber;
    }
    if (publishedAtMs != null) {
      $result.publishedAtMs = publishedAtMs;
    }
    if (ed25519Sig != null) {
      $result.ed25519Sig = ed25519Sig;
    }
    if (deviceEd25519Pk != null) {
      $result.deviceEd25519Pk = deviceEd25519Pk;
    }
    return $result;
  }
  LivenessRecordV3._() : super();
  factory LivenessRecordV3.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LivenessRecordV3.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LivenessRecordV3', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'userId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'deviceNodeId', $pb.PbFieldType.OY)
    ..pc<$0.PeerAddressProto>(3, _omitFieldNames ? '' : 'addresses', $pb.PbFieldType.PM, subBuilder: $0.PeerAddressProto.create)
    ..a<$fixnum.Int64>(4, _omitFieldNames ? '' : 'ttlSeconds', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(5, _omitFieldNames ? '' : 'sequenceNumber', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(6, _omitFieldNames ? '' : 'publishedAtMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(7, _omitFieldNames ? '' : 'ed25519Sig', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(8, _omitFieldNames ? '' : 'deviceEd25519Pk', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LivenessRecordV3 clone() => LivenessRecordV3()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LivenessRecordV3 copyWith(void Function(LivenessRecordV3) updates) => super.copyWith((message) => updates(message as LivenessRecordV3)) as LivenessRecordV3;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LivenessRecordV3 create() => LivenessRecordV3._();
  LivenessRecordV3 createEmptyInstance() => create();
  static $pb.PbList<LivenessRecordV3> createRepeated() => $pb.PbList<LivenessRecordV3>();
  @$core.pragma('dart2js:noInline')
  static LivenessRecordV3 getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LivenessRecordV3>(create);
  static LivenessRecordV3? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get userId => $_getN(0);
  @$pb.TagNumber(1)
  set userId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get deviceNodeId => $_getN(1);
  @$pb.TagNumber(2)
  set deviceNodeId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDeviceNodeId() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeviceNodeId() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$0.PeerAddressProto> get addresses => $_getList(2);

  @$pb.TagNumber(4)
  $fixnum.Int64 get ttlSeconds => $_getI64(3);
  @$pb.TagNumber(4)
  set ttlSeconds($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTtlSeconds() => $_has(3);
  @$pb.TagNumber(4)
  void clearTtlSeconds() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get sequenceNumber => $_getI64(4);
  @$pb.TagNumber(5)
  set sequenceNumber($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasSequenceNumber() => $_has(4);
  @$pb.TagNumber(5)
  void clearSequenceNumber() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get publishedAtMs => $_getI64(5);
  @$pb.TagNumber(6)
  set publishedAtMs($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasPublishedAtMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearPublishedAtMs() => clearField(6);

  @$pb.TagNumber(7)
  $core.List<$core.int> get ed25519Sig => $_getN(6);
  @$pb.TagNumber(7)
  set ed25519Sig($core.List<$core.int> v) { $_setBytes(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasEd25519Sig() => $_has(6);
  @$pb.TagNumber(7)
  void clearEd25519Sig() => clearField(7);

  @$pb.TagNumber(8)
  $core.List<$core.int> get deviceEd25519Pk => $_getN(7);
  @$pb.TagNumber(8)
  set deviceEd25519Pk($core.List<$core.int> v) { $_setBytes(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasDeviceEd25519Pk() => $_has(7);
  @$pb.TagNumber(8)
  void clearDeviceEd25519Pk() => clearField(8);
}

///  ── DeviceKemRecord V3 (2D-DHT, wave 5, §4.3) ───────────────────────────
///
///  Third 2D-DHT record next to AuthManifestV3 and LivenessRecordV3. Carries
///  the device KEM pubkeys (X25519 + ML-KEM-768) that were needed for the KEM encap on
///  InfrastructureFrameV3 (and later ONION_LAYER).
///  S368: `InfrastructureFrameV3` no longer exists (see above). This
///  sentence stays as a statement of origin — it explains WHAT the record
///  was once built for, and is no statement about what runs today.
///
///  Lifecycle separation: KEM PK changes only on device key reset (multi-
///  year cadence), liveness flips every 15min. Separate records avoid
///  unnecessary DHT traffic from the joint republish.
///
///  Trust anchor: signed by user master Ed25519 key (same chain as
///  AuthManifestV3 — the user vouches for the device KEM PK of their
///  authorised device).
///
///  Storage key: SHA-256("kem" || user_id || device_id) — own key space,
///  independent of "auth"+userId and "live"+userId+deviceId.
class DeviceKemRecordV3 extends $pb.GeneratedMessage {
  factory DeviceKemRecordV3({
    $core.List<$core.int>? userId,
    $core.List<$core.int>? deviceId,
    $core.List<$core.int>? deviceX25519Pk,
    $core.List<$core.int>? deviceMlKemPk,
    $fixnum.Int64? ttlSeconds,
    $fixnum.Int64? sequenceNumber,
    $fixnum.Int64? publishedAtMs,
    $core.List<$core.int>? ed25519Sig,
    $core.List<$core.int>? userEd25519Pk,
    $core.List<$core.int>? signerEd25519Pk,
  }) {
    final $result = create();
    if (userId != null) {
      $result.userId = userId;
    }
    if (deviceId != null) {
      $result.deviceId = deviceId;
    }
    if (deviceX25519Pk != null) {
      $result.deviceX25519Pk = deviceX25519Pk;
    }
    if (deviceMlKemPk != null) {
      $result.deviceMlKemPk = deviceMlKemPk;
    }
    if (ttlSeconds != null) {
      $result.ttlSeconds = ttlSeconds;
    }
    if (sequenceNumber != null) {
      $result.sequenceNumber = sequenceNumber;
    }
    if (publishedAtMs != null) {
      $result.publishedAtMs = publishedAtMs;
    }
    if (ed25519Sig != null) {
      $result.ed25519Sig = ed25519Sig;
    }
    if (userEd25519Pk != null) {
      $result.userEd25519Pk = userEd25519Pk;
    }
    if (signerEd25519Pk != null) {
      $result.signerEd25519Pk = signerEd25519Pk;
    }
    return $result;
  }
  DeviceKemRecordV3._() : super();
  factory DeviceKemRecordV3.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DeviceKemRecordV3.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DeviceKemRecordV3', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'userId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'deviceId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'deviceX25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'deviceMlKemPk', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(5, _omitFieldNames ? '' : 'ttlSeconds', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(6, _omitFieldNames ? '' : 'sequenceNumber', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(7, _omitFieldNames ? '' : 'publishedAtMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(8, _omitFieldNames ? '' : 'ed25519Sig', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(9, _omitFieldNames ? '' : 'userEd25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(10, _omitFieldNames ? '' : 'signerEd25519Pk', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DeviceKemRecordV3 clone() => DeviceKemRecordV3()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DeviceKemRecordV3 copyWith(void Function(DeviceKemRecordV3) updates) => super.copyWith((message) => updates(message as DeviceKemRecordV3)) as DeviceKemRecordV3;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeviceKemRecordV3 create() => DeviceKemRecordV3._();
  DeviceKemRecordV3 createEmptyInstance() => create();
  static $pb.PbList<DeviceKemRecordV3> createRepeated() => $pb.PbList<DeviceKemRecordV3>();
  @$core.pragma('dart2js:noInline')
  static DeviceKemRecordV3 getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DeviceKemRecordV3>(create);
  static DeviceKemRecordV3? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get userId => $_getN(0);
  @$pb.TagNumber(1)
  set userId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get deviceId => $_getN(1);
  @$pb.TagNumber(2)
  set deviceId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDeviceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeviceId() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get deviceX25519Pk => $_getN(2);
  @$pb.TagNumber(3)
  set deviceX25519Pk($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDeviceX25519Pk() => $_has(2);
  @$pb.TagNumber(3)
  void clearDeviceX25519Pk() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get deviceMlKemPk => $_getN(3);
  @$pb.TagNumber(4)
  set deviceMlKemPk($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasDeviceMlKemPk() => $_has(3);
  @$pb.TagNumber(4)
  void clearDeviceMlKemPk() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get ttlSeconds => $_getI64(4);
  @$pb.TagNumber(5)
  set ttlSeconds($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasTtlSeconds() => $_has(4);
  @$pb.TagNumber(5)
  void clearTtlSeconds() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get sequenceNumber => $_getI64(5);
  @$pb.TagNumber(6)
  set sequenceNumber($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasSequenceNumber() => $_has(5);
  @$pb.TagNumber(6)
  void clearSequenceNumber() => clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get publishedAtMs => $_getI64(6);
  @$pb.TagNumber(7)
  set publishedAtMs($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasPublishedAtMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearPublishedAtMs() => clearField(7);

  @$pb.TagNumber(8)
  $core.List<$core.int> get ed25519Sig => $_getN(7);
  @$pb.TagNumber(8)
  set ed25519Sig($core.List<$core.int> v) { $_setBytes(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasEd25519Sig() => $_has(7);
  @$pb.TagNumber(8)
  void clearEd25519Sig() => clearField(8);

  @$pb.TagNumber(9)
  $core.List<$core.int> get userEd25519Pk => $_getN(8);
  @$pb.TagNumber(9)
  set userEd25519Pk($core.List<$core.int> v) { $_setBytes(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasUserEd25519Pk() => $_has(8);
  @$pb.TagNumber(9)
  void clearUserEd25519Pk() => clearField(9);

  /// P5: see LivenessRecordProto — delegated signature of a linked
  /// device. Empty = signed directly under the user key.
  /// P6: the certificate is not sent along, the receiver takes it from
  /// the AuthManifest (see LivenessRecordProto). Field 11 stays reserved.
  @$pb.TagNumber(10)
  $core.List<$core.int> get signerEd25519Pk => $_getN(9);
  @$pb.TagNumber(10)
  set signerEd25519Pk($core.List<$core.int> v) { $_setBytes(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasSignerEd25519Pk() => $_has(9);
  @$pb.TagNumber(10)
  void clearSignerEd25519Pk() => clearField(10);
}

///  ── PeerListEntry V3 (§5.x PEER_LIST_PUSH) ──────────────────────────────
///
///  Replaces PeerInfoProto in the V3 PEER_LIST_* frames. Narrower because
///  identity fields (pubkeys, user ID) now come from the 2D-DHT resolver.
class PeerListEntryV3 extends $pb.GeneratedMessage {
  factory PeerListEntryV3({
    $core.List<$core.int>? deviceId,
    $core.Iterable<$0.PeerAddressProto>? addresses,
    $fixnum.Int64? lastSeenMs,
    $fixnum.Int64? ageHours,
    ConnectionTypeProto? connectionType,
  }) {
    final $result = create();
    if (deviceId != null) {
      $result.deviceId = deviceId;
    }
    if (addresses != null) {
      $result.addresses.addAll(addresses);
    }
    if (lastSeenMs != null) {
      $result.lastSeenMs = lastSeenMs;
    }
    if (ageHours != null) {
      $result.ageHours = ageHours;
    }
    if (connectionType != null) {
      $result.connectionType = connectionType;
    }
    return $result;
  }
  PeerListEntryV3._() : super();
  factory PeerListEntryV3.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PeerListEntryV3.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PeerListEntryV3', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'deviceId', $pb.PbFieldType.OY)
    ..pc<$0.PeerAddressProto>(2, _omitFieldNames ? '' : 'addresses', $pb.PbFieldType.PM, subBuilder: $0.PeerAddressProto.create)
    ..a<$fixnum.Int64>(3, _omitFieldNames ? '' : 'lastSeenMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(4, _omitFieldNames ? '' : 'ageHours', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..e<ConnectionTypeProto>(5, _omitFieldNames ? '' : 'connectionType', $pb.PbFieldType.OE, defaultOrMaker: ConnectionTypeProto.CT_LAN_SAME_SUBNET, valueOf: ConnectionTypeProto.valueOf, enumValues: ConnectionTypeProto.values)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PeerListEntryV3 clone() => PeerListEntryV3()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PeerListEntryV3 copyWith(void Function(PeerListEntryV3) updates) => super.copyWith((message) => updates(message as PeerListEntryV3)) as PeerListEntryV3;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PeerListEntryV3 create() => PeerListEntryV3._();
  PeerListEntryV3 createEmptyInstance() => create();
  static $pb.PbList<PeerListEntryV3> createRepeated() => $pb.PbList<PeerListEntryV3>();
  @$core.pragma('dart2js:noInline')
  static PeerListEntryV3 getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PeerListEntryV3>(create);
  static PeerListEntryV3? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get deviceId => $_getN(0);
  @$pb.TagNumber(1)
  set deviceId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasDeviceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$0.PeerAddressProto> get addresses => $_getList(1);

  @$pb.TagNumber(3)
  $fixnum.Int64 get lastSeenMs => $_getI64(2);
  @$pb.TagNumber(3)
  set lastSeenMs($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasLastSeenMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearLastSeenMs() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get ageHours => $_getI64(3);
  @$pb.TagNumber(4)
  set ageHours($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasAgeHours() => $_has(3);
  @$pb.TagNumber(4)
  void clearAgeHours() => clearField(4);

  @$pb.TagNumber(5)
  ConnectionTypeProto get connectionType => $_getN(4);
  @$pb.TagNumber(5)
  set connectionType(ConnectionTypeProto v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasConnectionType() => $_has(4);
  @$pb.TagNumber(5)
  void clearConnectionType() => clearField(5);
}

///  ── RelayForward V3 ─────────────────────────────────────────────────────
///
///  Close in content to RelayForward (old), but:
///    - wrappedPacket = NetworkPacketV3 (instead of MessageEnvelope)
///    - origin_device_id replaces origin_node_id (terminology hygiene)
///    - no more origin_user_id (user identity sits in the inner frame)
class RelayForwardV3 extends $pb.GeneratedMessage {
  factory RelayForwardV3({
    $core.List<$core.int>? relayId,
    $core.List<$core.int>? finalRecipientId,
    $core.List<$core.int>? wrappedPacket,
    $core.int? hopCount,
    $core.int? maxHops,
    $core.int? ttl,
    $core.List<$core.int>? originDeviceId,
    $fixnum.Int64? createdAtMs,
    $core.Iterable<$core.List<$core.int>>? visited,
  }) {
    final $result = create();
    if (relayId != null) {
      $result.relayId = relayId;
    }
    if (finalRecipientId != null) {
      $result.finalRecipientId = finalRecipientId;
    }
    if (wrappedPacket != null) {
      $result.wrappedPacket = wrappedPacket;
    }
    if (hopCount != null) {
      $result.hopCount = hopCount;
    }
    if (maxHops != null) {
      $result.maxHops = maxHops;
    }
    if (ttl != null) {
      $result.ttl = ttl;
    }
    if (originDeviceId != null) {
      $result.originDeviceId = originDeviceId;
    }
    if (createdAtMs != null) {
      $result.createdAtMs = createdAtMs;
    }
    if (visited != null) {
      $result.visited.addAll(visited);
    }
    return $result;
  }
  RelayForwardV3._() : super();
  factory RelayForwardV3.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RelayForwardV3.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RelayForwardV3', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'relayId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'finalRecipientId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'wrappedPacket', $pb.PbFieldType.OY)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'hopCount', $pb.PbFieldType.OU3)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'maxHops', $pb.PbFieldType.OU3)
    ..a<$core.int>(6, _omitFieldNames ? '' : 'ttl', $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(7, _omitFieldNames ? '' : 'originDeviceId', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(8, _omitFieldNames ? '' : 'createdAtMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..p<$core.List<$core.int>>(9, _omitFieldNames ? '' : 'visited', $pb.PbFieldType.PY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RelayForwardV3 clone() => RelayForwardV3()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RelayForwardV3 copyWith(void Function(RelayForwardV3) updates) => super.copyWith((message) => updates(message as RelayForwardV3)) as RelayForwardV3;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RelayForwardV3 create() => RelayForwardV3._();
  RelayForwardV3 createEmptyInstance() => create();
  static $pb.PbList<RelayForwardV3> createRepeated() => $pb.PbList<RelayForwardV3>();
  @$core.pragma('dart2js:noInline')
  static RelayForwardV3 getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RelayForwardV3>(create);
  static RelayForwardV3? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get relayId => $_getN(0);
  @$pb.TagNumber(1)
  set relayId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasRelayId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRelayId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get finalRecipientId => $_getN(1);
  @$pb.TagNumber(2)
  set finalRecipientId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasFinalRecipientId() => $_has(1);
  @$pb.TagNumber(2)
  void clearFinalRecipientId() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get wrappedPacket => $_getN(2);
  @$pb.TagNumber(3)
  set wrappedPacket($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasWrappedPacket() => $_has(2);
  @$pb.TagNumber(3)
  void clearWrappedPacket() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get hopCount => $_getIZ(3);
  @$pb.TagNumber(4)
  set hopCount($core.int v) { $_setUnsignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasHopCount() => $_has(3);
  @$pb.TagNumber(4)
  void clearHopCount() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get maxHops => $_getIZ(4);
  @$pb.TagNumber(5)
  set maxHops($core.int v) { $_setUnsignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasMaxHops() => $_has(4);
  @$pb.TagNumber(5)
  void clearMaxHops() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get ttl => $_getIZ(5);
  @$pb.TagNumber(6)
  set ttl($core.int v) { $_setUnsignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasTtl() => $_has(5);
  @$pb.TagNumber(6)
  void clearTtl() => clearField(6);

  @$pb.TagNumber(7)
  $core.List<$core.int> get originDeviceId => $_getN(6);
  @$pb.TagNumber(7)
  set originDeviceId($core.List<$core.int> v) { $_setBytes(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasOriginDeviceId() => $_has(6);
  @$pb.TagNumber(7)
  void clearOriginDeviceId() => clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get createdAtMs => $_getI64(7);
  @$pb.TagNumber(8)
  set createdAtMs($fixnum.Int64 v) { $_setInt64(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasCreatedAtMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearCreatedAtMs() => clearField(8);

  @$pb.TagNumber(9)
  $core.List<$core.List<$core.int>> get visited => $_getList(8);
}

class DeviceKemRequestV3 extends $pb.GeneratedMessage {
  factory DeviceKemRequestV3({
    $core.List<$core.int>? targetUserId,
    $core.List<$core.int>? targetDeviceId,
    $core.List<$core.int>? nonce,
    $fixnum.Int64? timestampMs,
  }) {
    final $result = create();
    if (targetUserId != null) {
      $result.targetUserId = targetUserId;
    }
    if (targetDeviceId != null) {
      $result.targetDeviceId = targetDeviceId;
    }
    if (nonce != null) {
      $result.nonce = nonce;
    }
    if (timestampMs != null) {
      $result.timestampMs = timestampMs;
    }
    return $result;
  }
  DeviceKemRequestV3._() : super();
  factory DeviceKemRequestV3.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DeviceKemRequestV3.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DeviceKemRequestV3', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'targetUserId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'targetDeviceId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'nonce', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(4, _omitFieldNames ? '' : 'timestampMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DeviceKemRequestV3 clone() => DeviceKemRequestV3()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DeviceKemRequestV3 copyWith(void Function(DeviceKemRequestV3) updates) => super.copyWith((message) => updates(message as DeviceKemRequestV3)) as DeviceKemRequestV3;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeviceKemRequestV3 create() => DeviceKemRequestV3._();
  DeviceKemRequestV3 createEmptyInstance() => create();
  static $pb.PbList<DeviceKemRequestV3> createRepeated() => $pb.PbList<DeviceKemRequestV3>();
  @$core.pragma('dart2js:noInline')
  static DeviceKemRequestV3 getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DeviceKemRequestV3>(create);
  static DeviceKemRequestV3? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get targetUserId => $_getN(0);
  @$pb.TagNumber(1)
  set targetUserId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTargetUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTargetUserId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get targetDeviceId => $_getN(1);
  @$pb.TagNumber(2)
  set targetDeviceId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTargetDeviceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearTargetDeviceId() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get nonce => $_getN(2);
  @$pb.TagNumber(3)
  set nonce($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasNonce() => $_has(2);
  @$pb.TagNumber(3)
  void clearNonce() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get timestampMs => $_getI64(3);
  @$pb.TagNumber(4)
  set timestampMs($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTimestampMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearTimestampMs() => clearField(4);
}

class DeviceKemOfferV3 extends $pb.GeneratedMessage {
  factory DeviceKemOfferV3({
    $core.List<$core.int>? deviceX25519Pk,
    $core.List<$core.int>? deviceMlKemPk,
    $core.List<$core.int>? nonce,
    $core.List<$core.int>? userEd25519Sig,
    $fixnum.Int64? timestampMs,
  }) {
    final $result = create();
    if (deviceX25519Pk != null) {
      $result.deviceX25519Pk = deviceX25519Pk;
    }
    if (deviceMlKemPk != null) {
      $result.deviceMlKemPk = deviceMlKemPk;
    }
    if (nonce != null) {
      $result.nonce = nonce;
    }
    if (userEd25519Sig != null) {
      $result.userEd25519Sig = userEd25519Sig;
    }
    if (timestampMs != null) {
      $result.timestampMs = timestampMs;
    }
    return $result;
  }
  DeviceKemOfferV3._() : super();
  factory DeviceKemOfferV3.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DeviceKemOfferV3.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DeviceKemOfferV3', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'deviceX25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'deviceMlKemPk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'nonce', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'userEd25519Sig', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(5, _omitFieldNames ? '' : 'timestampMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DeviceKemOfferV3 clone() => DeviceKemOfferV3()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DeviceKemOfferV3 copyWith(void Function(DeviceKemOfferV3) updates) => super.copyWith((message) => updates(message as DeviceKemOfferV3)) as DeviceKemOfferV3;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeviceKemOfferV3 create() => DeviceKemOfferV3._();
  DeviceKemOfferV3 createEmptyInstance() => create();
  static $pb.PbList<DeviceKemOfferV3> createRepeated() => $pb.PbList<DeviceKemOfferV3>();
  @$core.pragma('dart2js:noInline')
  static DeviceKemOfferV3 getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DeviceKemOfferV3>(create);
  static DeviceKemOfferV3? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get deviceX25519Pk => $_getN(0);
  @$pb.TagNumber(1)
  set deviceX25519Pk($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasDeviceX25519Pk() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceX25519Pk() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get deviceMlKemPk => $_getN(1);
  @$pb.TagNumber(2)
  set deviceMlKemPk($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDeviceMlKemPk() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeviceMlKemPk() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get nonce => $_getN(2);
  @$pb.TagNumber(3)
  set nonce($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasNonce() => $_has(2);
  @$pb.TagNumber(3)
  void clearNonce() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get userEd25519Sig => $_getN(3);
  @$pb.TagNumber(4)
  set userEd25519Sig($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasUserEd25519Sig() => $_has(3);
  @$pb.TagNumber(4)
  void clearUserEd25519Sig() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get timestampMs => $_getI64(4);
  @$pb.TagNumber(5)
  set timestampMs($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasTimestampMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearTimestampMs() => clearField(5);
}

class FirstCrStoreV3 extends $pb.GeneratedMessage {
  factory FirstCrStoreV3({
    $core.List<$core.int>? recipientUserId,
    $core.List<$core.int>? recipientDeviceId,
    $core.List<$core.int>? encryptedCrBlob,
    $core.List<$core.int>? senderDeviceId,
    $fixnum.Int64? timestampMs,
    $fixnum.Int64? ttlMs,
  }) {
    final $result = create();
    if (recipientUserId != null) {
      $result.recipientUserId = recipientUserId;
    }
    if (recipientDeviceId != null) {
      $result.recipientDeviceId = recipientDeviceId;
    }
    if (encryptedCrBlob != null) {
      $result.encryptedCrBlob = encryptedCrBlob;
    }
    if (senderDeviceId != null) {
      $result.senderDeviceId = senderDeviceId;
    }
    if (timestampMs != null) {
      $result.timestampMs = timestampMs;
    }
    if (ttlMs != null) {
      $result.ttlMs = ttlMs;
    }
    return $result;
  }
  FirstCrStoreV3._() : super();
  factory FirstCrStoreV3.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory FirstCrStoreV3.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FirstCrStoreV3', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'recipientUserId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'recipientDeviceId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'encryptedCrBlob', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'senderDeviceId', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(5, _omitFieldNames ? '' : 'timestampMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(6, _omitFieldNames ? '' : 'ttlMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  FirstCrStoreV3 clone() => FirstCrStoreV3()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  FirstCrStoreV3 copyWith(void Function(FirstCrStoreV3) updates) => super.copyWith((message) => updates(message as FirstCrStoreV3)) as FirstCrStoreV3;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FirstCrStoreV3 create() => FirstCrStoreV3._();
  FirstCrStoreV3 createEmptyInstance() => create();
  static $pb.PbList<FirstCrStoreV3> createRepeated() => $pb.PbList<FirstCrStoreV3>();
  @$core.pragma('dart2js:noInline')
  static FirstCrStoreV3 getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FirstCrStoreV3>(create);
  static FirstCrStoreV3? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get recipientUserId => $_getN(0);
  @$pb.TagNumber(1)
  set recipientUserId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasRecipientUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRecipientUserId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get recipientDeviceId => $_getN(1);
  @$pb.TagNumber(2)
  set recipientDeviceId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasRecipientDeviceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearRecipientDeviceId() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get encryptedCrBlob => $_getN(2);
  @$pb.TagNumber(3)
  set encryptedCrBlob($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasEncryptedCrBlob() => $_has(2);
  @$pb.TagNumber(3)
  void clearEncryptedCrBlob() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get senderDeviceId => $_getN(3);
  @$pb.TagNumber(4)
  set senderDeviceId($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasSenderDeviceId() => $_has(3);
  @$pb.TagNumber(4)
  void clearSenderDeviceId() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get timestampMs => $_getI64(4);
  @$pb.TagNumber(5)
  set timestampMs($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasTimestampMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearTimestampMs() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get ttlMs => $_getI64(5);
  @$pb.TagNumber(6)
  set ttlMs($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasTtlMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearTtlMs() => clearField(6);
}

class FirstCrStoreAckV3 extends $pb.GeneratedMessage {
  factory FirstCrStoreAckV3({
    $core.bool? accepted,
    $core.String? rejectReason,
    $core.List<$core.int>? recipientUserId,
  }) {
    final $result = create();
    if (accepted != null) {
      $result.accepted = accepted;
    }
    if (rejectReason != null) {
      $result.rejectReason = rejectReason;
    }
    if (recipientUserId != null) {
      $result.recipientUserId = recipientUserId;
    }
    return $result;
  }
  FirstCrStoreAckV3._() : super();
  factory FirstCrStoreAckV3.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory FirstCrStoreAckV3.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FirstCrStoreAckV3', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'accepted')
    ..aOS(2, _omitFieldNames ? '' : 'rejectReason')
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'recipientUserId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  FirstCrStoreAckV3 clone() => FirstCrStoreAckV3()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  FirstCrStoreAckV3 copyWith(void Function(FirstCrStoreAckV3) updates) => super.copyWith((message) => updates(message as FirstCrStoreAckV3)) as FirstCrStoreAckV3;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FirstCrStoreAckV3 create() => FirstCrStoreAckV3._();
  FirstCrStoreAckV3 createEmptyInstance() => create();
  static $pb.PbList<FirstCrStoreAckV3> createRepeated() => $pb.PbList<FirstCrStoreAckV3>();
  @$core.pragma('dart2js:noInline')
  static FirstCrStoreAckV3 getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FirstCrStoreAckV3>(create);
  static FirstCrStoreAckV3? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get accepted => $_getBF(0);
  @$pb.TagNumber(1)
  set accepted($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccepted() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccepted() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get rejectReason => $_getSZ(1);
  @$pb.TagNumber(2)
  set rejectReason($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasRejectReason() => $_has(1);
  @$pb.TagNumber(2)
  void clearRejectReason() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get recipientUserId => $_getN(2);
  @$pb.TagNumber(3)
  set recipientUserId($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasRecipientUserId() => $_has(2);
  @$pb.TagNumber(3)
  void clearRecipientUserId() => clearField(3);
}

class FirstCrDeliverV3 extends $pb.GeneratedMessage {
  factory FirstCrDeliverV3({
    $core.List<$core.int>? encryptedCrBlob,
    $core.List<$core.int>? senderDeviceId,
    $fixnum.Int64? storedAtMs,
  }) {
    final $result = create();
    if (encryptedCrBlob != null) {
      $result.encryptedCrBlob = encryptedCrBlob;
    }
    if (senderDeviceId != null) {
      $result.senderDeviceId = senderDeviceId;
    }
    if (storedAtMs != null) {
      $result.storedAtMs = storedAtMs;
    }
    return $result;
  }
  FirstCrDeliverV3._() : super();
  factory FirstCrDeliverV3.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory FirstCrDeliverV3.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FirstCrDeliverV3', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'encryptedCrBlob', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'senderDeviceId', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(3, _omitFieldNames ? '' : 'storedAtMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  FirstCrDeliverV3 clone() => FirstCrDeliverV3()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  FirstCrDeliverV3 copyWith(void Function(FirstCrDeliverV3) updates) => super.copyWith((message) => updates(message as FirstCrDeliverV3)) as FirstCrDeliverV3;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FirstCrDeliverV3 create() => FirstCrDeliverV3._();
  FirstCrDeliverV3 createEmptyInstance() => create();
  static $pb.PbList<FirstCrDeliverV3> createRepeated() => $pb.PbList<FirstCrDeliverV3>();
  @$core.pragma('dart2js:noInline')
  static FirstCrDeliverV3 getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FirstCrDeliverV3>(create);
  static FirstCrDeliverV3? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get encryptedCrBlob => $_getN(0);
  @$pb.TagNumber(1)
  set encryptedCrBlob($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasEncryptedCrBlob() => $_has(0);
  @$pb.TagNumber(1)
  void clearEncryptedCrBlob() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get senderDeviceId => $_getN(1);
  @$pb.TagNumber(2)
  set senderDeviceId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSenderDeviceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSenderDeviceId() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get storedAtMs => $_getI64(2);
  @$pb.TagNumber(3)
  set storedAtMs($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasStoredAtMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearStoredAtMs() => clearField(3);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');

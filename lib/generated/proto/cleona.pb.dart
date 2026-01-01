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

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'cleona.pbenum.dart';

export 'cleona.pbenum.dart';

class MessageEnvelope extends $pb.GeneratedMessage {
  factory MessageEnvelope({
    $core.int? version,
    $core.List<$core.int>? senderId,
    $core.List<$core.int>? recipientId,
    $fixnum.Int64? timestamp,
    MessageType? messageType,
    $core.List<$core.int>? encryptedPayload,
    $core.List<$core.int>? signatureEd25519,
    $core.List<$core.int>? signatureMlDsa,
    ContentMetadata? contentMetadata,
    EditMetadata? editMetadata,
    ExpiryMetadata? expiryMetadata,
    ErasureCodingMetadata? erasureMetadata,
    ProofOfWork? pow,
    PerMessageKem? kemHeader,
    CompressionType? compression,
    $core.String? networkTag,
    $core.List<$core.int>? messageId,
    $core.List<$core.int>? groupId,
    $core.List<$core.int>? replyToMessageId,
    $core.String? replyToText,
    $core.String? replyToSender,
    LinkPreview? linkPreview,
    $core.List<$core.int>? senderDeviceNodeId,
  }) {
    final $result = create();
    if (version != null) {
      $result.version = version;
    }
    if (senderId != null) {
      $result.senderId = senderId;
    }
    if (recipientId != null) {
      $result.recipientId = recipientId;
    }
    if (timestamp != null) {
      $result.timestamp = timestamp;
    }
    if (messageType != null) {
      $result.messageType = messageType;
    }
    if (encryptedPayload != null) {
      $result.encryptedPayload = encryptedPayload;
    }
    if (signatureEd25519 != null) {
      $result.signatureEd25519 = signatureEd25519;
    }
    if (signatureMlDsa != null) {
      $result.signatureMlDsa = signatureMlDsa;
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
    if (pow != null) {
      $result.pow = pow;
    }
    if (kemHeader != null) {
      $result.kemHeader = kemHeader;
    }
    if (compression != null) {
      $result.compression = compression;
    }
    if (networkTag != null) {
      $result.networkTag = networkTag;
    }
    if (messageId != null) {
      $result.messageId = messageId;
    }
    if (groupId != null) {
      $result.groupId = groupId;
    }
    if (replyToMessageId != null) {
      $result.replyToMessageId = replyToMessageId;
    }
    if (replyToText != null) {
      $result.replyToText = replyToText;
    }
    if (replyToSender != null) {
      $result.replyToSender = replyToSender;
    }
    if (linkPreview != null) {
      $result.linkPreview = linkPreview;
    }
    if (senderDeviceNodeId != null) {
      $result.senderDeviceNodeId = senderDeviceNodeId;
    }
    return $result;
  }
  MessageEnvelope._() : super();
  factory MessageEnvelope.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MessageEnvelope.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MessageEnvelope', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'version', $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'senderId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'recipientId', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(4, _omitFieldNames ? '' : 'timestamp', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..e<MessageType>(5, _omitFieldNames ? '' : 'messageType', $pb.PbFieldType.OE, defaultOrMaker: MessageType.TEXT, valueOf: MessageType.valueOf, enumValues: MessageType.values)
    ..a<$core.List<$core.int>>(6, _omitFieldNames ? '' : 'encryptedPayload', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(7, _omitFieldNames ? '' : 'signatureEd25519', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(8, _omitFieldNames ? '' : 'signatureMlDsa', $pb.PbFieldType.OY)
    ..aOM<ContentMetadata>(9, _omitFieldNames ? '' : 'contentMetadata', subBuilder: ContentMetadata.create)
    ..aOM<EditMetadata>(10, _omitFieldNames ? '' : 'editMetadata', subBuilder: EditMetadata.create)
    ..aOM<ExpiryMetadata>(11, _omitFieldNames ? '' : 'expiryMetadata', subBuilder: ExpiryMetadata.create)
    ..aOM<ErasureCodingMetadata>(12, _omitFieldNames ? '' : 'erasureMetadata', subBuilder: ErasureCodingMetadata.create)
    ..aOM<ProofOfWork>(13, _omitFieldNames ? '' : 'pow', subBuilder: ProofOfWork.create)
    ..aOM<PerMessageKem>(14, _omitFieldNames ? '' : 'kemHeader', subBuilder: PerMessageKem.create)
    ..e<CompressionType>(16, _omitFieldNames ? '' : 'compression', $pb.PbFieldType.OE, defaultOrMaker: CompressionType.NONE, valueOf: CompressionType.valueOf, enumValues: CompressionType.values)
    ..aOS(17, _omitFieldNames ? '' : 'networkTag')
    ..a<$core.List<$core.int>>(18, _omitFieldNames ? '' : 'messageId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(19, _omitFieldNames ? '' : 'groupId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(20, _omitFieldNames ? '' : 'replyToMessageId', $pb.PbFieldType.OY)
    ..aOS(21, _omitFieldNames ? '' : 'replyToText')
    ..aOS(22, _omitFieldNames ? '' : 'replyToSender')
    ..aOM<LinkPreview>(23, _omitFieldNames ? '' : 'linkPreview', subBuilder: LinkPreview.create)
    ..a<$core.List<$core.int>>(24, _omitFieldNames ? '' : 'senderDeviceNodeId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MessageEnvelope clone() => MessageEnvelope()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MessageEnvelope copyWith(void Function(MessageEnvelope) updates) => super.copyWith((message) => updates(message as MessageEnvelope)) as MessageEnvelope;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MessageEnvelope create() => MessageEnvelope._();
  MessageEnvelope createEmptyInstance() => create();
  static $pb.PbList<MessageEnvelope> createRepeated() => $pb.PbList<MessageEnvelope>();
  @$core.pragma('dart2js:noInline')
  static MessageEnvelope getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MessageEnvelope>(create);
  static MessageEnvelope? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get version => $_getIZ(0);
  @$pb.TagNumber(1)
  set version($core.int v) { $_setUnsignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearVersion() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get senderId => $_getN(1);
  @$pb.TagNumber(2)
  set senderId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSenderId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSenderId() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get recipientId => $_getN(2);
  @$pb.TagNumber(3)
  set recipientId($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasRecipientId() => $_has(2);
  @$pb.TagNumber(3)
  void clearRecipientId() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get timestamp => $_getI64(3);
  @$pb.TagNumber(4)
  set timestamp($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTimestamp() => $_has(3);
  @$pb.TagNumber(4)
  void clearTimestamp() => clearField(4);

  @$pb.TagNumber(5)
  MessageType get messageType => $_getN(4);
  @$pb.TagNumber(5)
  set messageType(MessageType v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasMessageType() => $_has(4);
  @$pb.TagNumber(5)
  void clearMessageType() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get encryptedPayload => $_getN(5);
  @$pb.TagNumber(6)
  set encryptedPayload($core.List<$core.int> v) { $_setBytes(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasEncryptedPayload() => $_has(5);
  @$pb.TagNumber(6)
  void clearEncryptedPayload() => clearField(6);

  @$pb.TagNumber(7)
  $core.List<$core.int> get signatureEd25519 => $_getN(6);
  @$pb.TagNumber(7)
  set signatureEd25519($core.List<$core.int> v) { $_setBytes(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasSignatureEd25519() => $_has(6);
  @$pb.TagNumber(7)
  void clearSignatureEd25519() => clearField(7);

  @$pb.TagNumber(8)
  $core.List<$core.int> get signatureMlDsa => $_getN(7);
  @$pb.TagNumber(8)
  set signatureMlDsa($core.List<$core.int> v) { $_setBytes(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasSignatureMlDsa() => $_has(7);
  @$pb.TagNumber(8)
  void clearSignatureMlDsa() => clearField(8);

  @$pb.TagNumber(9)
  ContentMetadata get contentMetadata => $_getN(8);
  @$pb.TagNumber(9)
  set contentMetadata(ContentMetadata v) { setField(9, v); }
  @$pb.TagNumber(9)
  $core.bool hasContentMetadata() => $_has(8);
  @$pb.TagNumber(9)
  void clearContentMetadata() => clearField(9);
  @$pb.TagNumber(9)
  ContentMetadata ensureContentMetadata() => $_ensure(8);

  @$pb.TagNumber(10)
  EditMetadata get editMetadata => $_getN(9);
  @$pb.TagNumber(10)
  set editMetadata(EditMetadata v) { setField(10, v); }
  @$pb.TagNumber(10)
  $core.bool hasEditMetadata() => $_has(9);
  @$pb.TagNumber(10)
  void clearEditMetadata() => clearField(10);
  @$pb.TagNumber(10)
  EditMetadata ensureEditMetadata() => $_ensure(9);

  @$pb.TagNumber(11)
  ExpiryMetadata get expiryMetadata => $_getN(10);
  @$pb.TagNumber(11)
  set expiryMetadata(ExpiryMetadata v) { setField(11, v); }
  @$pb.TagNumber(11)
  $core.bool hasExpiryMetadata() => $_has(10);
  @$pb.TagNumber(11)
  void clearExpiryMetadata() => clearField(11);
  @$pb.TagNumber(11)
  ExpiryMetadata ensureExpiryMetadata() => $_ensure(10);

  @$pb.TagNumber(12)
  ErasureCodingMetadata get erasureMetadata => $_getN(11);
  @$pb.TagNumber(12)
  set erasureMetadata(ErasureCodingMetadata v) { setField(12, v); }
  @$pb.TagNumber(12)
  $core.bool hasErasureMetadata() => $_has(11);
  @$pb.TagNumber(12)
  void clearErasureMetadata() => clearField(12);
  @$pb.TagNumber(12)
  ErasureCodingMetadata ensureErasureMetadata() => $_ensure(11);

  @$pb.TagNumber(13)
  ProofOfWork get pow => $_getN(12);
  @$pb.TagNumber(13)
  set pow(ProofOfWork v) { setField(13, v); }
  @$pb.TagNumber(13)
  $core.bool hasPow() => $_has(12);
  @$pb.TagNumber(13)
  void clearPow() => clearField(13);
  @$pb.TagNumber(13)
  ProofOfWork ensurePow() => $_ensure(12);

  @$pb.TagNumber(14)
  PerMessageKem get kemHeader => $_getN(13);
  @$pb.TagNumber(14)
  set kemHeader(PerMessageKem v) { setField(14, v); }
  @$pb.TagNumber(14)
  $core.bool hasKemHeader() => $_has(13);
  @$pb.TagNumber(14)
  void clearKemHeader() => clearField(14);
  @$pb.TagNumber(14)
  PerMessageKem ensureKemHeader() => $_ensure(13);

  @$pb.TagNumber(16)
  CompressionType get compression => $_getN(14);
  @$pb.TagNumber(16)
  set compression(CompressionType v) { setField(16, v); }
  @$pb.TagNumber(16)
  $core.bool hasCompression() => $_has(14);
  @$pb.TagNumber(16)
  void clearCompression() => clearField(16);

  @$pb.TagNumber(17)
  $core.String get networkTag => $_getSZ(15);
  @$pb.TagNumber(17)
  set networkTag($core.String v) { $_setString(15, v); }
  @$pb.TagNumber(17)
  $core.bool hasNetworkTag() => $_has(15);
  @$pb.TagNumber(17)
  void clearNetworkTag() => clearField(17);

  @$pb.TagNumber(18)
  $core.List<$core.int> get messageId => $_getN(16);
  @$pb.TagNumber(18)
  set messageId($core.List<$core.int> v) { $_setBytes(16, v); }
  @$pb.TagNumber(18)
  $core.bool hasMessageId() => $_has(16);
  @$pb.TagNumber(18)
  void clearMessageId() => clearField(18);

  @$pb.TagNumber(19)
  $core.List<$core.int> get groupId => $_getN(17);
  @$pb.TagNumber(19)
  set groupId($core.List<$core.int> v) { $_setBytes(17, v); }
  @$pb.TagNumber(19)
  $core.bool hasGroupId() => $_has(17);
  @$pb.TagNumber(19)
  void clearGroupId() => clearField(19);

  @$pb.TagNumber(20)
  $core.List<$core.int> get replyToMessageId => $_getN(18);
  @$pb.TagNumber(20)
  set replyToMessageId($core.List<$core.int> v) { $_setBytes(18, v); }
  @$pb.TagNumber(20)
  $core.bool hasReplyToMessageId() => $_has(18);
  @$pb.TagNumber(20)
  void clearReplyToMessageId() => clearField(20);

  @$pb.TagNumber(21)
  $core.String get replyToText => $_getSZ(19);
  @$pb.TagNumber(21)
  set replyToText($core.String v) { $_setString(19, v); }
  @$pb.TagNumber(21)
  $core.bool hasReplyToText() => $_has(19);
  @$pb.TagNumber(21)
  void clearReplyToText() => clearField(21);

  @$pb.TagNumber(22)
  $core.String get replyToSender => $_getSZ(20);
  @$pb.TagNumber(22)
  set replyToSender($core.String v) { $_setString(20, v); }
  @$pb.TagNumber(22)
  $core.bool hasReplyToSender() => $_has(20);
  @$pb.TagNumber(22)
  void clearReplyToSender() => clearField(22);

  @$pb.TagNumber(23)
  LinkPreview get linkPreview => $_getN(21);
  @$pb.TagNumber(23)
  set linkPreview(LinkPreview v) { setField(23, v); }
  @$pb.TagNumber(23)
  $core.bool hasLinkPreview() => $_has(21);
  @$pb.TagNumber(23)
  void clearLinkPreview() => clearField(23);
  @$pb.TagNumber(23)
  LinkPreview ensureLinkPreview() => $_ensure(21);

  @$pb.TagNumber(24)
  $core.List<$core.int> get senderDeviceNodeId => $_getN(22);
  @$pb.TagNumber(24)
  set senderDeviceNodeId($core.List<$core.int> v) { $_setBytes(22, v); }
  @$pb.TagNumber(24)
  $core.bool hasSenderDeviceNodeId() => $_has(22);
  @$pb.TagNumber(24)
  void clearSenderDeviceNodeId() => clearField(24);
}

class ContentMetadata extends $pb.GeneratedMessage {
  factory ContentMetadata({
    $core.String? mimeType,
    $fixnum.Int64? fileSize,
    $core.String? filename,
    $core.int? durationMs,
    $core.List<$core.int>? thumbnail,
    $core.List<$core.int>? contentHash,
  }) {
    final $result = create();
    if (mimeType != null) {
      $result.mimeType = mimeType;
    }
    if (fileSize != null) {
      $result.fileSize = fileSize;
    }
    if (filename != null) {
      $result.filename = filename;
    }
    if (durationMs != null) {
      $result.durationMs = durationMs;
    }
    if (thumbnail != null) {
      $result.thumbnail = thumbnail;
    }
    if (contentHash != null) {
      $result.contentHash = contentHash;
    }
    return $result;
  }
  ContentMetadata._() : super();
  factory ContentMetadata.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ContentMetadata.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ContentMetadata', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'mimeType')
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'fileSize', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(3, _omitFieldNames ? '' : 'filename')
    ..a<$core.int>(4, _omitFieldNames ? '' : 'durationMs', $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'thumbnail', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(6, _omitFieldNames ? '' : 'contentHash', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ContentMetadata clone() => ContentMetadata()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ContentMetadata copyWith(void Function(ContentMetadata) updates) => super.copyWith((message) => updates(message as ContentMetadata)) as ContentMetadata;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ContentMetadata create() => ContentMetadata._();
  ContentMetadata createEmptyInstance() => create();
  static $pb.PbList<ContentMetadata> createRepeated() => $pb.PbList<ContentMetadata>();
  @$core.pragma('dart2js:noInline')
  static ContentMetadata getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ContentMetadata>(create);
  static ContentMetadata? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get mimeType => $_getSZ(0);
  @$pb.TagNumber(1)
  set mimeType($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMimeType() => $_has(0);
  @$pb.TagNumber(1)
  void clearMimeType() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get fileSize => $_getI64(1);
  @$pb.TagNumber(2)
  set fileSize($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasFileSize() => $_has(1);
  @$pb.TagNumber(2)
  void clearFileSize() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get filename => $_getSZ(2);
  @$pb.TagNumber(3)
  set filename($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasFilename() => $_has(2);
  @$pb.TagNumber(3)
  void clearFilename() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get durationMs => $_getIZ(3);
  @$pb.TagNumber(4)
  set durationMs($core.int v) { $_setUnsignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasDurationMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearDurationMs() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get thumbnail => $_getN(4);
  @$pb.TagNumber(5)
  set thumbnail($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasThumbnail() => $_has(4);
  @$pb.TagNumber(5)
  void clearThumbnail() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get contentHash => $_getN(5);
  @$pb.TagNumber(6)
  set contentHash($core.List<$core.int> v) { $_setBytes(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasContentHash() => $_has(5);
  @$pb.TagNumber(6)
  void clearContentHash() => clearField(6);
}

class LinkPreview extends $pb.GeneratedMessage {
  factory LinkPreview({
    $core.String? url,
    $core.String? title,
    $core.String? description,
    $core.String? siteName,
    $core.List<$core.int>? thumbnail,
    $fixnum.Int64? fetchedAtMs,
  }) {
    final $result = create();
    if (url != null) {
      $result.url = url;
    }
    if (title != null) {
      $result.title = title;
    }
    if (description != null) {
      $result.description = description;
    }
    if (siteName != null) {
      $result.siteName = siteName;
    }
    if (thumbnail != null) {
      $result.thumbnail = thumbnail;
    }
    if (fetchedAtMs != null) {
      $result.fetchedAtMs = fetchedAtMs;
    }
    return $result;
  }
  LinkPreview._() : super();
  factory LinkPreview.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LinkPreview.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LinkPreview', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'url')
    ..aOS(2, _omitFieldNames ? '' : 'title')
    ..aOS(3, _omitFieldNames ? '' : 'description')
    ..aOS(4, _omitFieldNames ? '' : 'siteName')
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'thumbnail', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(6, _omitFieldNames ? '' : 'fetchedAtMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LinkPreview clone() => LinkPreview()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LinkPreview copyWith(void Function(LinkPreview) updates) => super.copyWith((message) => updates(message as LinkPreview)) as LinkPreview;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LinkPreview create() => LinkPreview._();
  LinkPreview createEmptyInstance() => create();
  static $pb.PbList<LinkPreview> createRepeated() => $pb.PbList<LinkPreview>();
  @$core.pragma('dart2js:noInline')
  static LinkPreview getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LinkPreview>(create);
  static LinkPreview? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get url => $_getSZ(0);
  @$pb.TagNumber(1)
  set url($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasUrl() => $_has(0);
  @$pb.TagNumber(1)
  void clearUrl() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get title => $_getSZ(1);
  @$pb.TagNumber(2)
  set title($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTitle() => $_has(1);
  @$pb.TagNumber(2)
  void clearTitle() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get description => $_getSZ(2);
  @$pb.TagNumber(3)
  set description($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDescription() => $_has(2);
  @$pb.TagNumber(3)
  void clearDescription() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get siteName => $_getSZ(3);
  @$pb.TagNumber(4)
  set siteName($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasSiteName() => $_has(3);
  @$pb.TagNumber(4)
  void clearSiteName() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get thumbnail => $_getN(4);
  @$pb.TagNumber(5)
  set thumbnail($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasThumbnail() => $_has(4);
  @$pb.TagNumber(5)
  void clearThumbnail() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get fetchedAtMs => $_getI64(5);
  @$pb.TagNumber(6)
  set fetchedAtMs($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasFetchedAtMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearFetchedAtMs() => clearField(6);
}

class EditMetadata extends $pb.GeneratedMessage {
  factory EditMetadata({
    $core.List<$core.int>? originalMessageId,
    $fixnum.Int64? editTimestamp,
  }) {
    final $result = create();
    if (originalMessageId != null) {
      $result.originalMessageId = originalMessageId;
    }
    if (editTimestamp != null) {
      $result.editTimestamp = editTimestamp;
    }
    return $result;
  }
  EditMetadata._() : super();
  factory EditMetadata.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EditMetadata.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EditMetadata', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'originalMessageId', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'editTimestamp', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EditMetadata clone() => EditMetadata()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EditMetadata copyWith(void Function(EditMetadata) updates) => super.copyWith((message) => updates(message as EditMetadata)) as EditMetadata;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EditMetadata create() => EditMetadata._();
  EditMetadata createEmptyInstance() => create();
  static $pb.PbList<EditMetadata> createRepeated() => $pb.PbList<EditMetadata>();
  @$core.pragma('dart2js:noInline')
  static EditMetadata getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EditMetadata>(create);
  static EditMetadata? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get originalMessageId => $_getN(0);
  @$pb.TagNumber(1)
  set originalMessageId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasOriginalMessageId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOriginalMessageId() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get editTimestamp => $_getI64(1);
  @$pb.TagNumber(2)
  set editTimestamp($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasEditTimestamp() => $_has(1);
  @$pb.TagNumber(2)
  void clearEditTimestamp() => clearField(2);
}

class ExpiryMetadata extends $pb.GeneratedMessage {
  factory ExpiryMetadata({
    $fixnum.Int64? expiryDurationMs,
    $fixnum.Int64? editWindowMs,
  }) {
    final $result = create();
    if (expiryDurationMs != null) {
      $result.expiryDurationMs = expiryDurationMs;
    }
    if (editWindowMs != null) {
      $result.editWindowMs = editWindowMs;
    }
    return $result;
  }
  ExpiryMetadata._() : super();
  factory ExpiryMetadata.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ExpiryMetadata.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ExpiryMetadata', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'expiryDurationMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'editWindowMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ExpiryMetadata clone() => ExpiryMetadata()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ExpiryMetadata copyWith(void Function(ExpiryMetadata) updates) => super.copyWith((message) => updates(message as ExpiryMetadata)) as ExpiryMetadata;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ExpiryMetadata create() => ExpiryMetadata._();
  ExpiryMetadata createEmptyInstance() => create();
  static $pb.PbList<ExpiryMetadata> createRepeated() => $pb.PbList<ExpiryMetadata>();
  @$core.pragma('dart2js:noInline')
  static ExpiryMetadata getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ExpiryMetadata>(create);
  static ExpiryMetadata? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get expiryDurationMs => $_getI64(0);
  @$pb.TagNumber(1)
  set expiryDurationMs($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasExpiryDurationMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearExpiryDurationMs() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get editWindowMs => $_getI64(1);
  @$pb.TagNumber(2)
  set editWindowMs($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasEditWindowMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearEditWindowMs() => clearField(2);
}

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

class PerMessageKem extends $pb.GeneratedMessage {
  factory PerMessageKem({
    $core.List<$core.int>? ephemeralX25519Pk,
    $core.List<$core.int>? mlKemCiphertext,
    $core.List<$core.int>? aesNonce,
  }) {
    final $result = create();
    if (ephemeralX25519Pk != null) {
      $result.ephemeralX25519Pk = ephemeralX25519Pk;
    }
    if (mlKemCiphertext != null) {
      $result.mlKemCiphertext = mlKemCiphertext;
    }
    if (aesNonce != null) {
      $result.aesNonce = aesNonce;
    }
    return $result;
  }
  PerMessageKem._() : super();
  factory PerMessageKem.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PerMessageKem.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PerMessageKem', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'ephemeralX25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'mlKemCiphertext', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'aesNonce', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PerMessageKem clone() => PerMessageKem()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PerMessageKem copyWith(void Function(PerMessageKem) updates) => super.copyWith((message) => updates(message as PerMessageKem)) as PerMessageKem;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PerMessageKem create() => PerMessageKem._();
  PerMessageKem createEmptyInstance() => create();
  static $pb.PbList<PerMessageKem> createRepeated() => $pb.PbList<PerMessageKem>();
  @$core.pragma('dart2js:noInline')
  static PerMessageKem getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PerMessageKem>(create);
  static PerMessageKem? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get ephemeralX25519Pk => $_getN(0);
  @$pb.TagNumber(1)
  set ephemeralX25519Pk($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasEphemeralX25519Pk() => $_has(0);
  @$pb.TagNumber(1)
  void clearEphemeralX25519Pk() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get mlKemCiphertext => $_getN(1);
  @$pb.TagNumber(2)
  set mlKemCiphertext($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMlKemCiphertext() => $_has(1);
  @$pb.TagNumber(2)
  void clearMlKemCiphertext() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get aesNonce => $_getN(2);
  @$pb.TagNumber(3)
  set aesNonce($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAesNonce() => $_has(2);
  @$pb.TagNumber(3)
  void clearAesNonce() => clearField(3);
}

class PeerInfoProto extends $pb.GeneratedMessage {
  factory PeerInfoProto({
    $core.List<$core.int>? nodeId,
    $core.String? publicIp,
    $core.int? publicPort,
    $core.String? localIp,
    $core.int? localPort,
    $core.Iterable<PeerAddressProto>? addresses,
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
    ..pc<PeerAddressProto>(6, _omitFieldNames ? '' : 'addresses', $pb.PbFieldType.PM, subBuilder: PeerAddressProto.create)
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
  $core.List<PeerAddressProto> get addresses => $_getList(5);

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
}

class PeerAddressProto extends $pb.GeneratedMessage {
  factory PeerAddressProto({
    $core.String? ip,
    $core.int? port,
    AddressType? addressType,
    $core.double? score,
    $fixnum.Int64? lastSuccess,
    $fixnum.Int64? lastAttempt,
    $core.int? successCount,
    $core.int? failCount,
  }) {
    final $result = create();
    if (ip != null) {
      $result.ip = ip;
    }
    if (port != null) {
      $result.port = port;
    }
    if (addressType != null) {
      $result.addressType = addressType;
    }
    if (score != null) {
      $result.score = score;
    }
    if (lastSuccess != null) {
      $result.lastSuccess = lastSuccess;
    }
    if (lastAttempt != null) {
      $result.lastAttempt = lastAttempt;
    }
    if (successCount != null) {
      $result.successCount = successCount;
    }
    if (failCount != null) {
      $result.failCount = failCount;
    }
    return $result;
  }
  PeerAddressProto._() : super();
  factory PeerAddressProto.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PeerAddressProto.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PeerAddressProto', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'ip')
    ..a<$core.int>(2, _omitFieldNames ? '' : 'port', $pb.PbFieldType.OU3)
    ..e<AddressType>(3, _omitFieldNames ? '' : 'addressType', $pb.PbFieldType.OE, defaultOrMaker: AddressType.IPV4_PUBLIC, valueOf: AddressType.valueOf, enumValues: AddressType.values)
    ..a<$core.double>(4, _omitFieldNames ? '' : 'score', $pb.PbFieldType.OD)
    ..a<$fixnum.Int64>(5, _omitFieldNames ? '' : 'lastSuccess', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(6, _omitFieldNames ? '' : 'lastAttempt', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.int>(7, _omitFieldNames ? '' : 'successCount', $pb.PbFieldType.OU3)
    ..a<$core.int>(8, _omitFieldNames ? '' : 'failCount', $pb.PbFieldType.OU3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PeerAddressProto clone() => PeerAddressProto()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PeerAddressProto copyWith(void Function(PeerAddressProto) updates) => super.copyWith((message) => updates(message as PeerAddressProto)) as PeerAddressProto;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PeerAddressProto create() => PeerAddressProto._();
  PeerAddressProto createEmptyInstance() => create();
  static $pb.PbList<PeerAddressProto> createRepeated() => $pb.PbList<PeerAddressProto>();
  @$core.pragma('dart2js:noInline')
  static PeerAddressProto getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PeerAddressProto>(create);
  static PeerAddressProto? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get ip => $_getSZ(0);
  @$pb.TagNumber(1)
  set ip($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasIp() => $_has(0);
  @$pb.TagNumber(1)
  void clearIp() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get port => $_getIZ(1);
  @$pb.TagNumber(2)
  set port($core.int v) { $_setUnsignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasPort() => $_has(1);
  @$pb.TagNumber(2)
  void clearPort() => clearField(2);

  @$pb.TagNumber(3)
  AddressType get addressType => $_getN(2);
  @$pb.TagNumber(3)
  set addressType(AddressType v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasAddressType() => $_has(2);
  @$pb.TagNumber(3)
  void clearAddressType() => clearField(3);

  @$pb.TagNumber(4)
  $core.double get score => $_getN(3);
  @$pb.TagNumber(4)
  set score($core.double v) { $_setDouble(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasScore() => $_has(3);
  @$pb.TagNumber(4)
  void clearScore() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get lastSuccess => $_getI64(4);
  @$pb.TagNumber(5)
  set lastSuccess($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasLastSuccess() => $_has(4);
  @$pb.TagNumber(5)
  void clearLastSuccess() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get lastAttempt => $_getI64(5);
  @$pb.TagNumber(6)
  set lastAttempt($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasLastAttempt() => $_has(5);
  @$pb.TagNumber(6)
  void clearLastAttempt() => clearField(6);

  @$pb.TagNumber(7)
  $core.int get successCount => $_getIZ(6);
  @$pb.TagNumber(7)
  set successCount($core.int v) { $_setUnsignedInt32(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasSuccessCount() => $_has(6);
  @$pb.TagNumber(7)
  void clearSuccessCount() => clearField(7);

  @$pb.TagNumber(8)
  $core.int get failCount => $_getIZ(7);
  @$pb.TagNumber(8)
  set failCount($core.int v) { $_setUnsignedInt32(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasFailCount() => $_has(7);
  @$pb.TagNumber(8)
  void clearFailCount() => clearField(8);
}

class DhtPing extends $pb.GeneratedMessage {
  factory DhtPing({
    $core.List<$core.int>? senderId,
    $fixnum.Int64? timestamp,
  }) {
    final $result = create();
    if (senderId != null) {
      $result.senderId = senderId;
    }
    if (timestamp != null) {
      $result.timestamp = timestamp;
    }
    return $result;
  }
  DhtPing._() : super();
  factory DhtPing.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DhtPing.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DhtPing', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'senderId', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'timestamp', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
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
}

class DhtPong extends $pb.GeneratedMessage {
  factory DhtPong({
    $core.List<$core.int>? senderId,
    $fixnum.Int64? timestamp,
    $core.String? observedIp,
    $core.int? observedPort,
    $core.Iterable<$core.List<$core.int>>? additionalNodeIds,
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

class ContactRequestMsg extends $pb.GeneratedMessage {
  factory ContactRequestMsg({
    $core.String? displayName,
    $core.List<$core.int>? ed25519PublicKey,
    $core.List<$core.int>? mlDsaPublicKey,
    $core.List<$core.int>? x25519PublicKey,
    $core.List<$core.int>? mlKemPublicKey,
    $core.String? message,
    $core.List<$core.int>? profilePicture,
    $core.String? description,
  }) {
    final $result = create();
    if (displayName != null) {
      $result.displayName = displayName;
    }
    if (ed25519PublicKey != null) {
      $result.ed25519PublicKey = ed25519PublicKey;
    }
    if (mlDsaPublicKey != null) {
      $result.mlDsaPublicKey = mlDsaPublicKey;
    }
    if (x25519PublicKey != null) {
      $result.x25519PublicKey = x25519PublicKey;
    }
    if (mlKemPublicKey != null) {
      $result.mlKemPublicKey = mlKemPublicKey;
    }
    if (message != null) {
      $result.message = message;
    }
    if (profilePicture != null) {
      $result.profilePicture = profilePicture;
    }
    if (description != null) {
      $result.description = description;
    }
    return $result;
  }
  ContactRequestMsg._() : super();
  factory ContactRequestMsg.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ContactRequestMsg.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ContactRequestMsg', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'displayName')
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'ed25519PublicKey', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'mlDsaPublicKey', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'x25519PublicKey', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'mlKemPublicKey', $pb.PbFieldType.OY)
    ..aOS(6, _omitFieldNames ? '' : 'message')
    ..a<$core.List<$core.int>>(7, _omitFieldNames ? '' : 'profilePicture', $pb.PbFieldType.OY)
    ..aOS(8, _omitFieldNames ? '' : 'description')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ContactRequestMsg clone() => ContactRequestMsg()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ContactRequestMsg copyWith(void Function(ContactRequestMsg) updates) => super.copyWith((message) => updates(message as ContactRequestMsg)) as ContactRequestMsg;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ContactRequestMsg create() => ContactRequestMsg._();
  ContactRequestMsg createEmptyInstance() => create();
  static $pb.PbList<ContactRequestMsg> createRepeated() => $pb.PbList<ContactRequestMsg>();
  @$core.pragma('dart2js:noInline')
  static ContactRequestMsg getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ContactRequestMsg>(create);
  static ContactRequestMsg? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get displayName => $_getSZ(0);
  @$pb.TagNumber(1)
  set displayName($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasDisplayName() => $_has(0);
  @$pb.TagNumber(1)
  void clearDisplayName() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get ed25519PublicKey => $_getN(1);
  @$pb.TagNumber(2)
  set ed25519PublicKey($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasEd25519PublicKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearEd25519PublicKey() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get mlDsaPublicKey => $_getN(2);
  @$pb.TagNumber(3)
  set mlDsaPublicKey($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMlDsaPublicKey() => $_has(2);
  @$pb.TagNumber(3)
  void clearMlDsaPublicKey() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get x25519PublicKey => $_getN(3);
  @$pb.TagNumber(4)
  set x25519PublicKey($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasX25519PublicKey() => $_has(3);
  @$pb.TagNumber(4)
  void clearX25519PublicKey() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get mlKemPublicKey => $_getN(4);
  @$pb.TagNumber(5)
  set mlKemPublicKey($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasMlKemPublicKey() => $_has(4);
  @$pb.TagNumber(5)
  void clearMlKemPublicKey() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get message => $_getSZ(5);
  @$pb.TagNumber(6)
  set message($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasMessage() => $_has(5);
  @$pb.TagNumber(6)
  void clearMessage() => clearField(6);

  @$pb.TagNumber(7)
  $core.List<$core.int> get profilePicture => $_getN(6);
  @$pb.TagNumber(7)
  set profilePicture($core.List<$core.int> v) { $_setBytes(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasProfilePicture() => $_has(6);
  @$pb.TagNumber(7)
  void clearProfilePicture() => clearField(7);

  @$pb.TagNumber(8)
  $core.String get description => $_getSZ(7);
  @$pb.TagNumber(8)
  set description($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasDescription() => $_has(7);
  @$pb.TagNumber(8)
  void clearDescription() => clearField(8);
}

class ContactRequestResponse extends $pb.GeneratedMessage {
  factory ContactRequestResponse({
    $core.bool? accepted,
    $core.String? rejectionReason,
    $core.List<$core.int>? ed25519PublicKey,
    $core.List<$core.int>? mlDsaPublicKey,
    $core.List<$core.int>? x25519PublicKey,
    $core.List<$core.int>? mlKemPublicKey,
    $core.String? displayName,
    $core.List<$core.int>? profilePicture,
    $core.String? description,
  }) {
    final $result = create();
    if (accepted != null) {
      $result.accepted = accepted;
    }
    if (rejectionReason != null) {
      $result.rejectionReason = rejectionReason;
    }
    if (ed25519PublicKey != null) {
      $result.ed25519PublicKey = ed25519PublicKey;
    }
    if (mlDsaPublicKey != null) {
      $result.mlDsaPublicKey = mlDsaPublicKey;
    }
    if (x25519PublicKey != null) {
      $result.x25519PublicKey = x25519PublicKey;
    }
    if (mlKemPublicKey != null) {
      $result.mlKemPublicKey = mlKemPublicKey;
    }
    if (displayName != null) {
      $result.displayName = displayName;
    }
    if (profilePicture != null) {
      $result.profilePicture = profilePicture;
    }
    if (description != null) {
      $result.description = description;
    }
    return $result;
  }
  ContactRequestResponse._() : super();
  factory ContactRequestResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ContactRequestResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ContactRequestResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'accepted')
    ..aOS(2, _omitFieldNames ? '' : 'rejectionReason')
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'ed25519PublicKey', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'mlDsaPublicKey', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'x25519PublicKey', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(6, _omitFieldNames ? '' : 'mlKemPublicKey', $pb.PbFieldType.OY)
    ..aOS(7, _omitFieldNames ? '' : 'displayName')
    ..a<$core.List<$core.int>>(8, _omitFieldNames ? '' : 'profilePicture', $pb.PbFieldType.OY)
    ..aOS(9, _omitFieldNames ? '' : 'description')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ContactRequestResponse clone() => ContactRequestResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ContactRequestResponse copyWith(void Function(ContactRequestResponse) updates) => super.copyWith((message) => updates(message as ContactRequestResponse)) as ContactRequestResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ContactRequestResponse create() => ContactRequestResponse._();
  ContactRequestResponse createEmptyInstance() => create();
  static $pb.PbList<ContactRequestResponse> createRepeated() => $pb.PbList<ContactRequestResponse>();
  @$core.pragma('dart2js:noInline')
  static ContactRequestResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ContactRequestResponse>(create);
  static ContactRequestResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get accepted => $_getBF(0);
  @$pb.TagNumber(1)
  set accepted($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccepted() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccepted() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get rejectionReason => $_getSZ(1);
  @$pb.TagNumber(2)
  set rejectionReason($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasRejectionReason() => $_has(1);
  @$pb.TagNumber(2)
  void clearRejectionReason() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get ed25519PublicKey => $_getN(2);
  @$pb.TagNumber(3)
  set ed25519PublicKey($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasEd25519PublicKey() => $_has(2);
  @$pb.TagNumber(3)
  void clearEd25519PublicKey() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get mlDsaPublicKey => $_getN(3);
  @$pb.TagNumber(4)
  set mlDsaPublicKey($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasMlDsaPublicKey() => $_has(3);
  @$pb.TagNumber(4)
  void clearMlDsaPublicKey() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get x25519PublicKey => $_getN(4);
  @$pb.TagNumber(5)
  set x25519PublicKey($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasX25519PublicKey() => $_has(4);
  @$pb.TagNumber(5)
  void clearX25519PublicKey() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get mlKemPublicKey => $_getN(5);
  @$pb.TagNumber(6)
  set mlKemPublicKey($core.List<$core.int> v) { $_setBytes(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasMlKemPublicKey() => $_has(5);
  @$pb.TagNumber(6)
  void clearMlKemPublicKey() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get displayName => $_getSZ(6);
  @$pb.TagNumber(7)
  set displayName($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasDisplayName() => $_has(6);
  @$pb.TagNumber(7)
  void clearDisplayName() => clearField(7);

  @$pb.TagNumber(8)
  $core.List<$core.int> get profilePicture => $_getN(7);
  @$pb.TagNumber(8)
  set profilePicture($core.List<$core.int> v) { $_setBytes(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasProfilePicture() => $_has(7);
  @$pb.TagNumber(8)
  void clearProfilePicture() => clearField(8);

  @$pb.TagNumber(9)
  $core.String get description => $_getSZ(8);
  @$pb.TagNumber(9)
  set description($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasDescription() => $_has(8);
  @$pb.TagNumber(9)
  void clearDescription() => clearField(9);
}

class ProfileData extends $pb.GeneratedMessage {
  factory ProfileData({
    $core.List<$core.int>? profilePicture,
    $core.String? description,
    $fixnum.Int64? updatedAtMs,
    $core.String? displayName,
  }) {
    final $result = create();
    if (profilePicture != null) {
      $result.profilePicture = profilePicture;
    }
    if (description != null) {
      $result.description = description;
    }
    if (updatedAtMs != null) {
      $result.updatedAtMs = updatedAtMs;
    }
    if (displayName != null) {
      $result.displayName = displayName;
    }
    return $result;
  }
  ProfileData._() : super();
  factory ProfileData.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ProfileData.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ProfileData', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'profilePicture', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'description')
    ..a<$fixnum.Int64>(3, _omitFieldNames ? '' : 'updatedAtMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(4, _omitFieldNames ? '' : 'displayName')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ProfileData clone() => ProfileData()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ProfileData copyWith(void Function(ProfileData) updates) => super.copyWith((message) => updates(message as ProfileData)) as ProfileData;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ProfileData create() => ProfileData._();
  ProfileData createEmptyInstance() => create();
  static $pb.PbList<ProfileData> createRepeated() => $pb.PbList<ProfileData>();
  @$core.pragma('dart2js:noInline')
  static ProfileData getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ProfileData>(create);
  static ProfileData? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get profilePicture => $_getN(0);
  @$pb.TagNumber(1)
  set profilePicture($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasProfilePicture() => $_has(0);
  @$pb.TagNumber(1)
  void clearProfilePicture() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get description => $_getSZ(1);
  @$pb.TagNumber(2)
  set description($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDescription() => $_has(1);
  @$pb.TagNumber(2)
  void clearDescription() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get updatedAtMs => $_getI64(2);
  @$pb.TagNumber(3)
  set updatedAtMs($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasUpdatedAtMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearUpdatedAtMs() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get displayName => $_getSZ(3);
  @$pb.TagNumber(4)
  set displayName($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasDisplayName() => $_has(3);
  @$pb.TagNumber(4)
  void clearDisplayName() => clearField(4);
}

class GroupCreate extends $pb.GeneratedMessage {
  factory GroupCreate({
    $core.List<$core.int>? groupId,
    $core.String? name,
    $core.String? description,
    $core.Iterable<$core.List<$core.int>>? memberIds,
    $core.List<$core.int>? picture,
  }) {
    final $result = create();
    if (groupId != null) {
      $result.groupId = groupId;
    }
    if (name != null) {
      $result.name = name;
    }
    if (description != null) {
      $result.description = description;
    }
    if (memberIds != null) {
      $result.memberIds.addAll(memberIds);
    }
    if (picture != null) {
      $result.picture = picture;
    }
    return $result;
  }
  GroupCreate._() : super();
  factory GroupCreate.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GroupCreate.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GroupCreate', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'groupId', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'description')
    ..p<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'memberIds', $pb.PbFieldType.PY)
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'picture', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GroupCreate clone() => GroupCreate()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GroupCreate copyWith(void Function(GroupCreate) updates) => super.copyWith((message) => updates(message as GroupCreate)) as GroupCreate;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GroupCreate create() => GroupCreate._();
  GroupCreate createEmptyInstance() => create();
  static $pb.PbList<GroupCreate> createRepeated() => $pb.PbList<GroupCreate>();
  @$core.pragma('dart2js:noInline')
  static GroupCreate getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GroupCreate>(create);
  static GroupCreate? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get groupId => $_getN(0);
  @$pb.TagNumber(1)
  set groupId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasGroupId() => $_has(0);
  @$pb.TagNumber(1)
  void clearGroupId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get description => $_getSZ(2);
  @$pb.TagNumber(3)
  set description($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDescription() => $_has(2);
  @$pb.TagNumber(3)
  void clearDescription() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.List<$core.int>> get memberIds => $_getList(3);

  @$pb.TagNumber(5)
  $core.List<$core.int> get picture => $_getN(4);
  @$pb.TagNumber(5)
  set picture($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasPicture() => $_has(4);
  @$pb.TagNumber(5)
  void clearPicture() => clearField(5);
}

class GroupInvite extends $pb.GeneratedMessage {
  factory GroupInvite({
    $core.List<$core.int>? groupId,
    $core.String? groupName,
    $core.List<$core.int>? inviterId,
    $core.Iterable<GroupMember>? members,
    $core.List<$core.int>? groupPicture,
    $core.String? groupDescription,
  }) {
    final $result = create();
    if (groupId != null) {
      $result.groupId = groupId;
    }
    if (groupName != null) {
      $result.groupName = groupName;
    }
    if (inviterId != null) {
      $result.inviterId = inviterId;
    }
    if (members != null) {
      $result.members.addAll(members);
    }
    if (groupPicture != null) {
      $result.groupPicture = groupPicture;
    }
    if (groupDescription != null) {
      $result.groupDescription = groupDescription;
    }
    return $result;
  }
  GroupInvite._() : super();
  factory GroupInvite.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GroupInvite.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GroupInvite', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'groupId', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'groupName')
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'inviterId', $pb.PbFieldType.OY)
    ..pc<GroupMember>(4, _omitFieldNames ? '' : 'members', $pb.PbFieldType.PM, subBuilder: GroupMember.create)
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'groupPicture', $pb.PbFieldType.OY)
    ..aOS(6, _omitFieldNames ? '' : 'groupDescription')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GroupInvite clone() => GroupInvite()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GroupInvite copyWith(void Function(GroupInvite) updates) => super.copyWith((message) => updates(message as GroupInvite)) as GroupInvite;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GroupInvite create() => GroupInvite._();
  GroupInvite createEmptyInstance() => create();
  static $pb.PbList<GroupInvite> createRepeated() => $pb.PbList<GroupInvite>();
  @$core.pragma('dart2js:noInline')
  static GroupInvite getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GroupInvite>(create);
  static GroupInvite? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get groupId => $_getN(0);
  @$pb.TagNumber(1)
  set groupId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasGroupId() => $_has(0);
  @$pb.TagNumber(1)
  void clearGroupId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get groupName => $_getSZ(1);
  @$pb.TagNumber(2)
  set groupName($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasGroupName() => $_has(1);
  @$pb.TagNumber(2)
  void clearGroupName() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get inviterId => $_getN(2);
  @$pb.TagNumber(3)
  set inviterId($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasInviterId() => $_has(2);
  @$pb.TagNumber(3)
  void clearInviterId() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<GroupMember> get members => $_getList(3);

  @$pb.TagNumber(5)
  $core.List<$core.int> get groupPicture => $_getN(4);
  @$pb.TagNumber(5)
  set groupPicture($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasGroupPicture() => $_has(4);
  @$pb.TagNumber(5)
  void clearGroupPicture() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get groupDescription => $_getSZ(5);
  @$pb.TagNumber(6)
  set groupDescription($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasGroupDescription() => $_has(5);
  @$pb.TagNumber(6)
  void clearGroupDescription() => clearField(6);
}

class GroupMember extends $pb.GeneratedMessage {
  factory GroupMember({
    $core.List<$core.int>? nodeId,
    $core.String? displayName,
    $core.String? role,
    $core.List<$core.int>? ed25519PublicKey,
    $core.List<$core.int>? x25519PublicKey,
    $core.List<$core.int>? mlKemPublicKey,
  }) {
    final $result = create();
    if (nodeId != null) {
      $result.nodeId = nodeId;
    }
    if (displayName != null) {
      $result.displayName = displayName;
    }
    if (role != null) {
      $result.role = role;
    }
    if (ed25519PublicKey != null) {
      $result.ed25519PublicKey = ed25519PublicKey;
    }
    if (x25519PublicKey != null) {
      $result.x25519PublicKey = x25519PublicKey;
    }
    if (mlKemPublicKey != null) {
      $result.mlKemPublicKey = mlKemPublicKey;
    }
    return $result;
  }
  GroupMember._() : super();
  factory GroupMember.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GroupMember.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GroupMember', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'nodeId', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'displayName')
    ..aOS(3, _omitFieldNames ? '' : 'role')
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'ed25519PublicKey', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'x25519PublicKey', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(6, _omitFieldNames ? '' : 'mlKemPublicKey', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GroupMember clone() => GroupMember()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GroupMember copyWith(void Function(GroupMember) updates) => super.copyWith((message) => updates(message as GroupMember)) as GroupMember;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GroupMember create() => GroupMember._();
  GroupMember createEmptyInstance() => create();
  static $pb.PbList<GroupMember> createRepeated() => $pb.PbList<GroupMember>();
  @$core.pragma('dart2js:noInline')
  static GroupMember getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GroupMember>(create);
  static GroupMember? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get nodeId => $_getN(0);
  @$pb.TagNumber(1)
  set nodeId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasNodeId() => $_has(0);
  @$pb.TagNumber(1)
  void clearNodeId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get displayName => $_getSZ(1);
  @$pb.TagNumber(2)
  set displayName($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDisplayName() => $_has(1);
  @$pb.TagNumber(2)
  void clearDisplayName() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get role => $_getSZ(2);
  @$pb.TagNumber(3)
  set role($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasRole() => $_has(2);
  @$pb.TagNumber(3)
  void clearRole() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get ed25519PublicKey => $_getN(3);
  @$pb.TagNumber(4)
  set ed25519PublicKey($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasEd25519PublicKey() => $_has(3);
  @$pb.TagNumber(4)
  void clearEd25519PublicKey() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get x25519PublicKey => $_getN(4);
  @$pb.TagNumber(5)
  set x25519PublicKey($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasX25519PublicKey() => $_has(4);
  @$pb.TagNumber(5)
  void clearX25519PublicKey() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get mlKemPublicKey => $_getN(5);
  @$pb.TagNumber(6)
  set mlKemPublicKey($core.List<$core.int> v) { $_setBytes(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasMlKemPublicKey() => $_has(5);
  @$pb.TagNumber(6)
  void clearMlKemPublicKey() => clearField(6);
}

class GroupKeyUpdate extends $pb.GeneratedMessage {
  factory GroupKeyUpdate({
    $core.List<$core.int>? groupId,
    $core.List<$core.int>? newGroupKey,
  }) {
    final $result = create();
    if (groupId != null) {
      $result.groupId = groupId;
    }
    if (newGroupKey != null) {
      $result.newGroupKey = newGroupKey;
    }
    return $result;
  }
  GroupKeyUpdate._() : super();
  factory GroupKeyUpdate.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GroupKeyUpdate.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GroupKeyUpdate', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'groupId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'newGroupKey', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GroupKeyUpdate clone() => GroupKeyUpdate()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GroupKeyUpdate copyWith(void Function(GroupKeyUpdate) updates) => super.copyWith((message) => updates(message as GroupKeyUpdate)) as GroupKeyUpdate;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GroupKeyUpdate create() => GroupKeyUpdate._();
  GroupKeyUpdate createEmptyInstance() => create();
  static $pb.PbList<GroupKeyUpdate> createRepeated() => $pb.PbList<GroupKeyUpdate>();
  @$core.pragma('dart2js:noInline')
  static GroupKeyUpdate getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GroupKeyUpdate>(create);
  static GroupKeyUpdate? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get groupId => $_getN(0);
  @$pb.TagNumber(1)
  set groupId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasGroupId() => $_has(0);
  @$pb.TagNumber(1)
  void clearGroupId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get newGroupKey => $_getN(1);
  @$pb.TagNumber(2)
  set newGroupKey($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasNewGroupKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearNewGroupKey() => clearField(2);
}

class GroupLeave extends $pb.GeneratedMessage {
  factory GroupLeave({
    $core.List<$core.int>? groupId,
  }) {
    final $result = create();
    if (groupId != null) {
      $result.groupId = groupId;
    }
    return $result;
  }
  GroupLeave._() : super();
  factory GroupLeave.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GroupLeave.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GroupLeave', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'groupId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GroupLeave clone() => GroupLeave()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GroupLeave copyWith(void Function(GroupLeave) updates) => super.copyWith((message) => updates(message as GroupLeave)) as GroupLeave;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GroupLeave create() => GroupLeave._();
  GroupLeave createEmptyInstance() => create();
  static $pb.PbList<GroupLeave> createRepeated() => $pb.PbList<GroupLeave>();
  @$core.pragma('dart2js:noInline')
  static GroupLeave getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GroupLeave>(create);
  static GroupLeave? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get groupId => $_getN(0);
  @$pb.TagNumber(1)
  set groupId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasGroupId() => $_has(0);
  @$pb.TagNumber(1)
  void clearGroupId() => clearField(1);
}

class ChannelCreate extends $pb.GeneratedMessage {
  factory ChannelCreate({
    $core.List<$core.int>? channelId,
    $core.String? name,
    $core.String? description,
    $core.bool? announcementOnly,
    ExpiryMetadata? defaultExpiry,
    $core.List<$core.int>? picture,
    $core.bool? isPublic,
    $core.bool? isAdult,
    $core.String? language,
  }) {
    final $result = create();
    if (channelId != null) {
      $result.channelId = channelId;
    }
    if (name != null) {
      $result.name = name;
    }
    if (description != null) {
      $result.description = description;
    }
    if (announcementOnly != null) {
      $result.announcementOnly = announcementOnly;
    }
    if (defaultExpiry != null) {
      $result.defaultExpiry = defaultExpiry;
    }
    if (picture != null) {
      $result.picture = picture;
    }
    if (isPublic != null) {
      $result.isPublic = isPublic;
    }
    if (isAdult != null) {
      $result.isAdult = isAdult;
    }
    if (language != null) {
      $result.language = language;
    }
    return $result;
  }
  ChannelCreate._() : super();
  factory ChannelCreate.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ChannelCreate.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ChannelCreate', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'channelId', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'description')
    ..aOB(4, _omitFieldNames ? '' : 'announcementOnly')
    ..aOM<ExpiryMetadata>(5, _omitFieldNames ? '' : 'defaultExpiry', subBuilder: ExpiryMetadata.create)
    ..a<$core.List<$core.int>>(6, _omitFieldNames ? '' : 'picture', $pb.PbFieldType.OY)
    ..aOB(7, _omitFieldNames ? '' : 'isPublic')
    ..aOB(8, _omitFieldNames ? '' : 'isAdult')
    ..aOS(9, _omitFieldNames ? '' : 'language')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ChannelCreate clone() => ChannelCreate()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ChannelCreate copyWith(void Function(ChannelCreate) updates) => super.copyWith((message) => updates(message as ChannelCreate)) as ChannelCreate;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChannelCreate create() => ChannelCreate._();
  ChannelCreate createEmptyInstance() => create();
  static $pb.PbList<ChannelCreate> createRepeated() => $pb.PbList<ChannelCreate>();
  @$core.pragma('dart2js:noInline')
  static ChannelCreate getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChannelCreate>(create);
  static ChannelCreate? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get channelId => $_getN(0);
  @$pb.TagNumber(1)
  set channelId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasChannelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChannelId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get description => $_getSZ(2);
  @$pb.TagNumber(3)
  set description($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDescription() => $_has(2);
  @$pb.TagNumber(3)
  void clearDescription() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get announcementOnly => $_getBF(3);
  @$pb.TagNumber(4)
  set announcementOnly($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasAnnouncementOnly() => $_has(3);
  @$pb.TagNumber(4)
  void clearAnnouncementOnly() => clearField(4);

  @$pb.TagNumber(5)
  ExpiryMetadata get defaultExpiry => $_getN(4);
  @$pb.TagNumber(5)
  set defaultExpiry(ExpiryMetadata v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasDefaultExpiry() => $_has(4);
  @$pb.TagNumber(5)
  void clearDefaultExpiry() => clearField(5);
  @$pb.TagNumber(5)
  ExpiryMetadata ensureDefaultExpiry() => $_ensure(4);

  @$pb.TagNumber(6)
  $core.List<$core.int> get picture => $_getN(5);
  @$pb.TagNumber(6)
  set picture($core.List<$core.int> v) { $_setBytes(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasPicture() => $_has(5);
  @$pb.TagNumber(6)
  void clearPicture() => clearField(6);

  @$pb.TagNumber(7)
  $core.bool get isPublic => $_getBF(6);
  @$pb.TagNumber(7)
  set isPublic($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasIsPublic() => $_has(6);
  @$pb.TagNumber(7)
  void clearIsPublic() => clearField(7);

  @$pb.TagNumber(8)
  $core.bool get isAdult => $_getBF(7);
  @$pb.TagNumber(8)
  set isAdult($core.bool v) { $_setBool(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasIsAdult() => $_has(7);
  @$pb.TagNumber(8)
  void clearIsAdult() => clearField(8);

  @$pb.TagNumber(9)
  $core.String get language => $_getSZ(8);
  @$pb.TagNumber(9)
  set language($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasLanguage() => $_has(8);
  @$pb.TagNumber(9)
  void clearLanguage() => clearField(9);
}

class ChannelPost extends $pb.GeneratedMessage {
  factory ChannelPost({
    $core.List<$core.int>? channelId,
    $core.List<$core.int>? postId,
    $core.String? text,
    ContentMetadata? media,
    $core.List<$core.int>? contentData,
  }) {
    final $result = create();
    if (channelId != null) {
      $result.channelId = channelId;
    }
    if (postId != null) {
      $result.postId = postId;
    }
    if (text != null) {
      $result.text = text;
    }
    if (media != null) {
      $result.media = media;
    }
    if (contentData != null) {
      $result.contentData = contentData;
    }
    return $result;
  }
  ChannelPost._() : super();
  factory ChannelPost.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ChannelPost.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ChannelPost', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'channelId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'postId', $pb.PbFieldType.OY)
    ..aOS(3, _omitFieldNames ? '' : 'text')
    ..aOM<ContentMetadata>(4, _omitFieldNames ? '' : 'media', subBuilder: ContentMetadata.create)
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'contentData', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ChannelPost clone() => ChannelPost()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ChannelPost copyWith(void Function(ChannelPost) updates) => super.copyWith((message) => updates(message as ChannelPost)) as ChannelPost;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChannelPost create() => ChannelPost._();
  ChannelPost createEmptyInstance() => create();
  static $pb.PbList<ChannelPost> createRepeated() => $pb.PbList<ChannelPost>();
  @$core.pragma('dart2js:noInline')
  static ChannelPost getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChannelPost>(create);
  static ChannelPost? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get channelId => $_getN(0);
  @$pb.TagNumber(1)
  set channelId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasChannelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChannelId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get postId => $_getN(1);
  @$pb.TagNumber(2)
  set postId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasPostId() => $_has(1);
  @$pb.TagNumber(2)
  void clearPostId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get text => $_getSZ(2);
  @$pb.TagNumber(3)
  set text($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasText() => $_has(2);
  @$pb.TagNumber(3)
  void clearText() => clearField(3);

  @$pb.TagNumber(4)
  ContentMetadata get media => $_getN(3);
  @$pb.TagNumber(4)
  set media(ContentMetadata v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasMedia() => $_has(3);
  @$pb.TagNumber(4)
  void clearMedia() => clearField(4);
  @$pb.TagNumber(4)
  ContentMetadata ensureMedia() => $_ensure(3);

  @$pb.TagNumber(5)
  $core.List<$core.int> get contentData => $_getN(4);
  @$pb.TagNumber(5)
  set contentData($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasContentData() => $_has(4);
  @$pb.TagNumber(5)
  void clearContentData() => clearField(5);
}

class ChannelInvite extends $pb.GeneratedMessage {
  factory ChannelInvite({
    $core.List<$core.int>? channelId,
    $core.String? channelName,
    $core.List<$core.int>? inviterId,
    $core.String? role,
    $core.List<$core.int>? welcomeMessage,
    $core.List<$core.int>? channelPicture,
    $core.String? channelDescription,
    $core.Iterable<GroupMember>? members,
    $core.bool? isPublic,
    $core.bool? isAdult,
    $core.String? language,
  }) {
    final $result = create();
    if (channelId != null) {
      $result.channelId = channelId;
    }
    if (channelName != null) {
      $result.channelName = channelName;
    }
    if (inviterId != null) {
      $result.inviterId = inviterId;
    }
    if (role != null) {
      $result.role = role;
    }
    if (welcomeMessage != null) {
      $result.welcomeMessage = welcomeMessage;
    }
    if (channelPicture != null) {
      $result.channelPicture = channelPicture;
    }
    if (channelDescription != null) {
      $result.channelDescription = channelDescription;
    }
    if (members != null) {
      $result.members.addAll(members);
    }
    if (isPublic != null) {
      $result.isPublic = isPublic;
    }
    if (isAdult != null) {
      $result.isAdult = isAdult;
    }
    if (language != null) {
      $result.language = language;
    }
    return $result;
  }
  ChannelInvite._() : super();
  factory ChannelInvite.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ChannelInvite.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ChannelInvite', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'channelId', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'channelName')
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'inviterId', $pb.PbFieldType.OY)
    ..aOS(4, _omitFieldNames ? '' : 'role')
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'welcomeMessage', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(6, _omitFieldNames ? '' : 'channelPicture', $pb.PbFieldType.OY)
    ..aOS(7, _omitFieldNames ? '' : 'channelDescription')
    ..pc<GroupMember>(8, _omitFieldNames ? '' : 'members', $pb.PbFieldType.PM, subBuilder: GroupMember.create)
    ..aOB(9, _omitFieldNames ? '' : 'isPublic')
    ..aOB(10, _omitFieldNames ? '' : 'isAdult')
    ..aOS(11, _omitFieldNames ? '' : 'language')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ChannelInvite clone() => ChannelInvite()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ChannelInvite copyWith(void Function(ChannelInvite) updates) => super.copyWith((message) => updates(message as ChannelInvite)) as ChannelInvite;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChannelInvite create() => ChannelInvite._();
  ChannelInvite createEmptyInstance() => create();
  static $pb.PbList<ChannelInvite> createRepeated() => $pb.PbList<ChannelInvite>();
  @$core.pragma('dart2js:noInline')
  static ChannelInvite getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChannelInvite>(create);
  static ChannelInvite? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get channelId => $_getN(0);
  @$pb.TagNumber(1)
  set channelId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasChannelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChannelId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get channelName => $_getSZ(1);
  @$pb.TagNumber(2)
  set channelName($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChannelName() => $_has(1);
  @$pb.TagNumber(2)
  void clearChannelName() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get inviterId => $_getN(2);
  @$pb.TagNumber(3)
  set inviterId($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasInviterId() => $_has(2);
  @$pb.TagNumber(3)
  void clearInviterId() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get role => $_getSZ(3);
  @$pb.TagNumber(4)
  set role($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasRole() => $_has(3);
  @$pb.TagNumber(4)
  void clearRole() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get welcomeMessage => $_getN(4);
  @$pb.TagNumber(5)
  set welcomeMessage($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasWelcomeMessage() => $_has(4);
  @$pb.TagNumber(5)
  void clearWelcomeMessage() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get channelPicture => $_getN(5);
  @$pb.TagNumber(6)
  set channelPicture($core.List<$core.int> v) { $_setBytes(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasChannelPicture() => $_has(5);
  @$pb.TagNumber(6)
  void clearChannelPicture() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get channelDescription => $_getSZ(6);
  @$pb.TagNumber(7)
  set channelDescription($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasChannelDescription() => $_has(6);
  @$pb.TagNumber(7)
  void clearChannelDescription() => clearField(7);

  @$pb.TagNumber(8)
  $core.List<GroupMember> get members => $_getList(7);

  @$pb.TagNumber(9)
  $core.bool get isPublic => $_getBF(8);
  @$pb.TagNumber(9)
  set isPublic($core.bool v) { $_setBool(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasIsPublic() => $_has(8);
  @$pb.TagNumber(9)
  void clearIsPublic() => clearField(9);

  @$pb.TagNumber(10)
  $core.bool get isAdult => $_getBF(9);
  @$pb.TagNumber(10)
  set isAdult($core.bool v) { $_setBool(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasIsAdult() => $_has(9);
  @$pb.TagNumber(10)
  void clearIsAdult() => clearField(10);

  @$pb.TagNumber(11)
  $core.String get language => $_getSZ(10);
  @$pb.TagNumber(11)
  set language($core.String v) { $_setString(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasLanguage() => $_has(10);
  @$pb.TagNumber(11)
  void clearLanguage() => clearField(11);
}

class ChannelRoleUpdate extends $pb.GeneratedMessage {
  factory ChannelRoleUpdate({
    $core.List<$core.int>? channelId,
    $core.List<$core.int>? targetId,
    $core.String? newRole,
  }) {
    final $result = create();
    if (channelId != null) {
      $result.channelId = channelId;
    }
    if (targetId != null) {
      $result.targetId = targetId;
    }
    if (newRole != null) {
      $result.newRole = newRole;
    }
    return $result;
  }
  ChannelRoleUpdate._() : super();
  factory ChannelRoleUpdate.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ChannelRoleUpdate.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ChannelRoleUpdate', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'channelId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'targetId', $pb.PbFieldType.OY)
    ..aOS(3, _omitFieldNames ? '' : 'newRole')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ChannelRoleUpdate clone() => ChannelRoleUpdate()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ChannelRoleUpdate copyWith(void Function(ChannelRoleUpdate) updates) => super.copyWith((message) => updates(message as ChannelRoleUpdate)) as ChannelRoleUpdate;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChannelRoleUpdate create() => ChannelRoleUpdate._();
  ChannelRoleUpdate createEmptyInstance() => create();
  static $pb.PbList<ChannelRoleUpdate> createRepeated() => $pb.PbList<ChannelRoleUpdate>();
  @$core.pragma('dart2js:noInline')
  static ChannelRoleUpdate getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChannelRoleUpdate>(create);
  static ChannelRoleUpdate? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get channelId => $_getN(0);
  @$pb.TagNumber(1)
  set channelId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasChannelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChannelId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get targetId => $_getN(1);
  @$pb.TagNumber(2)
  set targetId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTargetId() => $_has(1);
  @$pb.TagNumber(2)
  void clearTargetId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get newRole => $_getSZ(2);
  @$pb.TagNumber(3)
  set newRole($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasNewRole() => $_has(2);
  @$pb.TagNumber(3)
  void clearNewRole() => clearField(3);
}

class ChannelLeave extends $pb.GeneratedMessage {
  factory ChannelLeave({
    $core.List<$core.int>? channelId,
  }) {
    final $result = create();
    if (channelId != null) {
      $result.channelId = channelId;
    }
    return $result;
  }
  ChannelLeave._() : super();
  factory ChannelLeave.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ChannelLeave.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ChannelLeave', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'channelId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ChannelLeave clone() => ChannelLeave()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ChannelLeave copyWith(void Function(ChannelLeave) updates) => super.copyWith((message) => updates(message as ChannelLeave)) as ChannelLeave;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChannelLeave create() => ChannelLeave._();
  ChannelLeave createEmptyInstance() => create();
  static $pb.PbList<ChannelLeave> createRepeated() => $pb.PbList<ChannelLeave>();
  @$core.pragma('dart2js:noInline')
  static ChannelLeave getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChannelLeave>(create);
  static ChannelLeave? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get channelId => $_getN(0);
  @$pb.TagNumber(1)
  set channelId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasChannelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChannelId() => clearField(1);
}

class ChatConfigUpdate extends $pb.GeneratedMessage {
  factory ChatConfigUpdate({
    $core.String? conversationId,
    $core.bool? allowDownloads,
    $core.bool? allowForwarding,
    $core.bool? isRequest,
    $core.bool? accepted,
    $fixnum.Int64? expiryDurationMs,
    $fixnum.Int64? editWindowMs,
    $core.bool? readReceipts,
    $core.bool? typingIndicators,
  }) {
    final $result = create();
    if (conversationId != null) {
      $result.conversationId = conversationId;
    }
    if (allowDownloads != null) {
      $result.allowDownloads = allowDownloads;
    }
    if (allowForwarding != null) {
      $result.allowForwarding = allowForwarding;
    }
    if (isRequest != null) {
      $result.isRequest = isRequest;
    }
    if (accepted != null) {
      $result.accepted = accepted;
    }
    if (expiryDurationMs != null) {
      $result.expiryDurationMs = expiryDurationMs;
    }
    if (editWindowMs != null) {
      $result.editWindowMs = editWindowMs;
    }
    if (readReceipts != null) {
      $result.readReceipts = readReceipts;
    }
    if (typingIndicators != null) {
      $result.typingIndicators = typingIndicators;
    }
    return $result;
  }
  ChatConfigUpdate._() : super();
  factory ChatConfigUpdate.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ChatConfigUpdate.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ChatConfigUpdate', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'conversationId')
    ..aOB(2, _omitFieldNames ? '' : 'allowDownloads')
    ..aOB(3, _omitFieldNames ? '' : 'allowForwarding')
    ..aOB(4, _omitFieldNames ? '' : 'isRequest')
    ..aOB(5, _omitFieldNames ? '' : 'accepted')
    ..a<$fixnum.Int64>(6, _omitFieldNames ? '' : 'expiryDurationMs', $pb.PbFieldType.OS6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(7, _omitFieldNames ? '' : 'editWindowMs', $pb.PbFieldType.OS6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(8, _omitFieldNames ? '' : 'readReceipts')
    ..aOB(9, _omitFieldNames ? '' : 'typingIndicators')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ChatConfigUpdate clone() => ChatConfigUpdate()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ChatConfigUpdate copyWith(void Function(ChatConfigUpdate) updates) => super.copyWith((message) => updates(message as ChatConfigUpdate)) as ChatConfigUpdate;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChatConfigUpdate create() => ChatConfigUpdate._();
  ChatConfigUpdate createEmptyInstance() => create();
  static $pb.PbList<ChatConfigUpdate> createRepeated() => $pb.PbList<ChatConfigUpdate>();
  @$core.pragma('dart2js:noInline')
  static ChatConfigUpdate getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChatConfigUpdate>(create);
  static ChatConfigUpdate? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get conversationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set conversationId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasConversationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearConversationId() => clearField(1);

  @$pb.TagNumber(2)
  $core.bool get allowDownloads => $_getBF(1);
  @$pb.TagNumber(2)
  set allowDownloads($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasAllowDownloads() => $_has(1);
  @$pb.TagNumber(2)
  void clearAllowDownloads() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get allowForwarding => $_getBF(2);
  @$pb.TagNumber(3)
  set allowForwarding($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAllowForwarding() => $_has(2);
  @$pb.TagNumber(3)
  void clearAllowForwarding() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get isRequest => $_getBF(3);
  @$pb.TagNumber(4)
  set isRequest($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasIsRequest() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsRequest() => clearField(4);

  @$pb.TagNumber(5)
  $core.bool get accepted => $_getBF(4);
  @$pb.TagNumber(5)
  set accepted($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAccepted() => $_has(4);
  @$pb.TagNumber(5)
  void clearAccepted() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get expiryDurationMs => $_getI64(5);
  @$pb.TagNumber(6)
  set expiryDurationMs($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasExpiryDurationMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearExpiryDurationMs() => clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get editWindowMs => $_getI64(6);
  @$pb.TagNumber(7)
  set editWindowMs($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasEditWindowMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearEditWindowMs() => clearField(7);

  @$pb.TagNumber(8)
  $core.bool get readReceipts => $_getBF(7);
  @$pb.TagNumber(8)
  set readReceipts($core.bool v) { $_setBool(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasReadReceipts() => $_has(7);
  @$pb.TagNumber(8)
  void clearReadReceipts() => clearField(8);

  @$pb.TagNumber(9)
  $core.bool get typingIndicators => $_getBF(8);
  @$pb.TagNumber(9)
  set typingIndicators($core.bool v) { $_setBool(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasTypingIndicators() => $_has(8);
  @$pb.TagNumber(9)
  void clearTypingIndicators() => clearField(9);
}

class IdentityDeletedNotification extends $pb.GeneratedMessage {
  factory IdentityDeletedNotification({
    $core.List<$core.int>? identityEd25519Pk,
    $fixnum.Int64? deletedAtMs,
    $core.String? displayName,
  }) {
    final $result = create();
    if (identityEd25519Pk != null) {
      $result.identityEd25519Pk = identityEd25519Pk;
    }
    if (deletedAtMs != null) {
      $result.deletedAtMs = deletedAtMs;
    }
    if (displayName != null) {
      $result.displayName = displayName;
    }
    return $result;
  }
  IdentityDeletedNotification._() : super();
  factory IdentityDeletedNotification.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory IdentityDeletedNotification.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'IdentityDeletedNotification', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'identityEd25519Pk', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'deletedAtMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(3, _omitFieldNames ? '' : 'displayName')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  IdentityDeletedNotification clone() => IdentityDeletedNotification()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  IdentityDeletedNotification copyWith(void Function(IdentityDeletedNotification) updates) => super.copyWith((message) => updates(message as IdentityDeletedNotification)) as IdentityDeletedNotification;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static IdentityDeletedNotification create() => IdentityDeletedNotification._();
  IdentityDeletedNotification createEmptyInstance() => create();
  static $pb.PbList<IdentityDeletedNotification> createRepeated() => $pb.PbList<IdentityDeletedNotification>();
  @$core.pragma('dart2js:noInline')
  static IdentityDeletedNotification getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<IdentityDeletedNotification>(create);
  static IdentityDeletedNotification? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get identityEd25519Pk => $_getN(0);
  @$pb.TagNumber(1)
  set identityEd25519Pk($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasIdentityEd25519Pk() => $_has(0);
  @$pb.TagNumber(1)
  void clearIdentityEd25519Pk() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get deletedAtMs => $_getI64(1);
  @$pb.TagNumber(2)
  set deletedAtMs($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDeletedAtMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeletedAtMs() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get displayName => $_getSZ(2);
  @$pb.TagNumber(3)
  set displayName($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDisplayName() => $_has(2);
  @$pb.TagNumber(3)
  void clearDisplayName() => clearField(3);
}

class RestoreBroadcast extends $pb.GeneratedMessage {
  factory RestoreBroadcast({
    $core.List<$core.int>? oldNodeId,
    $core.List<$core.int>? newNodeId,
    $core.List<$core.int>? newEd25519Pk,
    $core.List<$core.int>? newX25519Pk,
    $core.List<$core.int>? newMlKemPk,
    $core.List<$core.int>? newMlDsaPk,
    $core.String? displayName,
    $fixnum.Int64? timestamp,
    $core.List<$core.int>? signature,
  }) {
    final $result = create();
    if (oldNodeId != null) {
      $result.oldNodeId = oldNodeId;
    }
    if (newNodeId != null) {
      $result.newNodeId = newNodeId;
    }
    if (newEd25519Pk != null) {
      $result.newEd25519Pk = newEd25519Pk;
    }
    if (newX25519Pk != null) {
      $result.newX25519Pk = newX25519Pk;
    }
    if (newMlKemPk != null) {
      $result.newMlKemPk = newMlKemPk;
    }
    if (newMlDsaPk != null) {
      $result.newMlDsaPk = newMlDsaPk;
    }
    if (displayName != null) {
      $result.displayName = displayName;
    }
    if (timestamp != null) {
      $result.timestamp = timestamp;
    }
    if (signature != null) {
      $result.signature = signature;
    }
    return $result;
  }
  RestoreBroadcast._() : super();
  factory RestoreBroadcast.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RestoreBroadcast.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RestoreBroadcast', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'oldNodeId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'newNodeId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'newEd25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'newX25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'newMlKemPk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(6, _omitFieldNames ? '' : 'newMlDsaPk', $pb.PbFieldType.OY)
    ..aOS(7, _omitFieldNames ? '' : 'displayName')
    ..a<$fixnum.Int64>(8, _omitFieldNames ? '' : 'timestamp', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(9, _omitFieldNames ? '' : 'signature', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RestoreBroadcast clone() => RestoreBroadcast()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RestoreBroadcast copyWith(void Function(RestoreBroadcast) updates) => super.copyWith((message) => updates(message as RestoreBroadcast)) as RestoreBroadcast;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RestoreBroadcast create() => RestoreBroadcast._();
  RestoreBroadcast createEmptyInstance() => create();
  static $pb.PbList<RestoreBroadcast> createRepeated() => $pb.PbList<RestoreBroadcast>();
  @$core.pragma('dart2js:noInline')
  static RestoreBroadcast getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RestoreBroadcast>(create);
  static RestoreBroadcast? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get oldNodeId => $_getN(0);
  @$pb.TagNumber(1)
  set oldNodeId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasOldNodeId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOldNodeId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get newNodeId => $_getN(1);
  @$pb.TagNumber(2)
  set newNodeId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasNewNodeId() => $_has(1);
  @$pb.TagNumber(2)
  void clearNewNodeId() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get newEd25519Pk => $_getN(2);
  @$pb.TagNumber(3)
  set newEd25519Pk($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasNewEd25519Pk() => $_has(2);
  @$pb.TagNumber(3)
  void clearNewEd25519Pk() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get newX25519Pk => $_getN(3);
  @$pb.TagNumber(4)
  set newX25519Pk($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasNewX25519Pk() => $_has(3);
  @$pb.TagNumber(4)
  void clearNewX25519Pk() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get newMlKemPk => $_getN(4);
  @$pb.TagNumber(5)
  set newMlKemPk($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasNewMlKemPk() => $_has(4);
  @$pb.TagNumber(5)
  void clearNewMlKemPk() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get newMlDsaPk => $_getN(5);
  @$pb.TagNumber(6)
  set newMlDsaPk($core.List<$core.int> v) { $_setBytes(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasNewMlDsaPk() => $_has(5);
  @$pb.TagNumber(6)
  void clearNewMlDsaPk() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get displayName => $_getSZ(6);
  @$pb.TagNumber(7)
  set displayName($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasDisplayName() => $_has(6);
  @$pb.TagNumber(7)
  void clearDisplayName() => clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get timestamp => $_getI64(7);
  @$pb.TagNumber(8)
  set timestamp($fixnum.Int64 v) { $_setInt64(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasTimestamp() => $_has(7);
  @$pb.TagNumber(8)
  void clearTimestamp() => clearField(8);

  @$pb.TagNumber(9)
  $core.List<$core.int> get signature => $_getN(8);
  @$pb.TagNumber(9)
  set signature($core.List<$core.int> v) { $_setBytes(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasSignature() => $_has(8);
  @$pb.TagNumber(9)
  void clearSignature() => clearField(9);
}

class RestoreResponse extends $pb.GeneratedMessage {
  factory RestoreResponse({
    $core.int? phase,
    $core.Iterable<ContactEntry>? contacts,
    $core.Iterable<StoredMessage>? messages,
    $core.Iterable<RestoreGroupInfo>? groups,
    $core.Iterable<RestoreChannelInfo>? channels,
  }) {
    final $result = create();
    if (phase != null) {
      $result.phase = phase;
    }
    if (contacts != null) {
      $result.contacts.addAll(contacts);
    }
    if (messages != null) {
      $result.messages.addAll(messages);
    }
    if (groups != null) {
      $result.groups.addAll(groups);
    }
    if (channels != null) {
      $result.channels.addAll(channels);
    }
    return $result;
  }
  RestoreResponse._() : super();
  factory RestoreResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RestoreResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RestoreResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'phase', $pb.PbFieldType.OU3)
    ..pc<ContactEntry>(2, _omitFieldNames ? '' : 'contacts', $pb.PbFieldType.PM, subBuilder: ContactEntry.create)
    ..pc<StoredMessage>(3, _omitFieldNames ? '' : 'messages', $pb.PbFieldType.PM, subBuilder: StoredMessage.create)
    ..pc<RestoreGroupInfo>(4, _omitFieldNames ? '' : 'groups', $pb.PbFieldType.PM, subBuilder: RestoreGroupInfo.create)
    ..pc<RestoreChannelInfo>(5, _omitFieldNames ? '' : 'channels', $pb.PbFieldType.PM, subBuilder: RestoreChannelInfo.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RestoreResponse clone() => RestoreResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RestoreResponse copyWith(void Function(RestoreResponse) updates) => super.copyWith((message) => updates(message as RestoreResponse)) as RestoreResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RestoreResponse create() => RestoreResponse._();
  RestoreResponse createEmptyInstance() => create();
  static $pb.PbList<RestoreResponse> createRepeated() => $pb.PbList<RestoreResponse>();
  @$core.pragma('dart2js:noInline')
  static RestoreResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RestoreResponse>(create);
  static RestoreResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get phase => $_getIZ(0);
  @$pb.TagNumber(1)
  set phase($core.int v) { $_setUnsignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPhase() => $_has(0);
  @$pb.TagNumber(1)
  void clearPhase() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<ContactEntry> get contacts => $_getList(1);

  @$pb.TagNumber(3)
  $core.List<StoredMessage> get messages => $_getList(2);

  @$pb.TagNumber(4)
  $core.List<RestoreGroupInfo> get groups => $_getList(3);

  @$pb.TagNumber(5)
  $core.List<RestoreChannelInfo> get channels => $_getList(4);
}

class RestoreGroupInfo extends $pb.GeneratedMessage {
  factory RestoreGroupInfo({
    $core.List<$core.int>? groupId,
    $core.String? name,
    $core.String? description,
    $core.String? ownerNodeIdHex,
    $core.Iterable<RestoreGroupMember>? members,
  }) {
    final $result = create();
    if (groupId != null) {
      $result.groupId = groupId;
    }
    if (name != null) {
      $result.name = name;
    }
    if (description != null) {
      $result.description = description;
    }
    if (ownerNodeIdHex != null) {
      $result.ownerNodeIdHex = ownerNodeIdHex;
    }
    if (members != null) {
      $result.members.addAll(members);
    }
    return $result;
  }
  RestoreGroupInfo._() : super();
  factory RestoreGroupInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RestoreGroupInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RestoreGroupInfo', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'groupId', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'description')
    ..aOS(4, _omitFieldNames ? '' : 'ownerNodeIdHex')
    ..pc<RestoreGroupMember>(5, _omitFieldNames ? '' : 'members', $pb.PbFieldType.PM, subBuilder: RestoreGroupMember.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RestoreGroupInfo clone() => RestoreGroupInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RestoreGroupInfo copyWith(void Function(RestoreGroupInfo) updates) => super.copyWith((message) => updates(message as RestoreGroupInfo)) as RestoreGroupInfo;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RestoreGroupInfo create() => RestoreGroupInfo._();
  RestoreGroupInfo createEmptyInstance() => create();
  static $pb.PbList<RestoreGroupInfo> createRepeated() => $pb.PbList<RestoreGroupInfo>();
  @$core.pragma('dart2js:noInline')
  static RestoreGroupInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RestoreGroupInfo>(create);
  static RestoreGroupInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get groupId => $_getN(0);
  @$pb.TagNumber(1)
  set groupId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasGroupId() => $_has(0);
  @$pb.TagNumber(1)
  void clearGroupId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get description => $_getSZ(2);
  @$pb.TagNumber(3)
  set description($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDescription() => $_has(2);
  @$pb.TagNumber(3)
  void clearDescription() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get ownerNodeIdHex => $_getSZ(3);
  @$pb.TagNumber(4)
  set ownerNodeIdHex($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasOwnerNodeIdHex() => $_has(3);
  @$pb.TagNumber(4)
  void clearOwnerNodeIdHex() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<RestoreGroupMember> get members => $_getList(4);
}

class RestoreGroupMember extends $pb.GeneratedMessage {
  factory RestoreGroupMember({
    $core.String? nodeIdHex,
    $core.String? displayName,
    $core.String? role,
    $core.List<$core.int>? ed25519Pk,
    $core.List<$core.int>? x25519Pk,
    $core.List<$core.int>? mlKemPk,
  }) {
    final $result = create();
    if (nodeIdHex != null) {
      $result.nodeIdHex = nodeIdHex;
    }
    if (displayName != null) {
      $result.displayName = displayName;
    }
    if (role != null) {
      $result.role = role;
    }
    if (ed25519Pk != null) {
      $result.ed25519Pk = ed25519Pk;
    }
    if (x25519Pk != null) {
      $result.x25519Pk = x25519Pk;
    }
    if (mlKemPk != null) {
      $result.mlKemPk = mlKemPk;
    }
    return $result;
  }
  RestoreGroupMember._() : super();
  factory RestoreGroupMember.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RestoreGroupMember.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RestoreGroupMember', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'nodeIdHex')
    ..aOS(2, _omitFieldNames ? '' : 'displayName')
    ..aOS(3, _omitFieldNames ? '' : 'role')
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'ed25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'x25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(6, _omitFieldNames ? '' : 'mlKemPk', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RestoreGroupMember clone() => RestoreGroupMember()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RestoreGroupMember copyWith(void Function(RestoreGroupMember) updates) => super.copyWith((message) => updates(message as RestoreGroupMember)) as RestoreGroupMember;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RestoreGroupMember create() => RestoreGroupMember._();
  RestoreGroupMember createEmptyInstance() => create();
  static $pb.PbList<RestoreGroupMember> createRepeated() => $pb.PbList<RestoreGroupMember>();
  @$core.pragma('dart2js:noInline')
  static RestoreGroupMember getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RestoreGroupMember>(create);
  static RestoreGroupMember? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get nodeIdHex => $_getSZ(0);
  @$pb.TagNumber(1)
  set nodeIdHex($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasNodeIdHex() => $_has(0);
  @$pb.TagNumber(1)
  void clearNodeIdHex() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get displayName => $_getSZ(1);
  @$pb.TagNumber(2)
  set displayName($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDisplayName() => $_has(1);
  @$pb.TagNumber(2)
  void clearDisplayName() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get role => $_getSZ(2);
  @$pb.TagNumber(3)
  set role($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasRole() => $_has(2);
  @$pb.TagNumber(3)
  void clearRole() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get ed25519Pk => $_getN(3);
  @$pb.TagNumber(4)
  set ed25519Pk($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasEd25519Pk() => $_has(3);
  @$pb.TagNumber(4)
  void clearEd25519Pk() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get x25519Pk => $_getN(4);
  @$pb.TagNumber(5)
  set x25519Pk($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasX25519Pk() => $_has(4);
  @$pb.TagNumber(5)
  void clearX25519Pk() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get mlKemPk => $_getN(5);
  @$pb.TagNumber(6)
  set mlKemPk($core.List<$core.int> v) { $_setBytes(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasMlKemPk() => $_has(5);
  @$pb.TagNumber(6)
  void clearMlKemPk() => clearField(6);
}

class RestoreChannelInfo extends $pb.GeneratedMessage {
  factory RestoreChannelInfo({
    $core.List<$core.int>? channelId,
    $core.String? name,
    $core.String? description,
    $core.String? ownerNodeIdHex,
    $core.Iterable<RestoreChannelMember>? members,
  }) {
    final $result = create();
    if (channelId != null) {
      $result.channelId = channelId;
    }
    if (name != null) {
      $result.name = name;
    }
    if (description != null) {
      $result.description = description;
    }
    if (ownerNodeIdHex != null) {
      $result.ownerNodeIdHex = ownerNodeIdHex;
    }
    if (members != null) {
      $result.members.addAll(members);
    }
    return $result;
  }
  RestoreChannelInfo._() : super();
  factory RestoreChannelInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RestoreChannelInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RestoreChannelInfo', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'channelId', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'description')
    ..aOS(4, _omitFieldNames ? '' : 'ownerNodeIdHex')
    ..pc<RestoreChannelMember>(5, _omitFieldNames ? '' : 'members', $pb.PbFieldType.PM, subBuilder: RestoreChannelMember.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RestoreChannelInfo clone() => RestoreChannelInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RestoreChannelInfo copyWith(void Function(RestoreChannelInfo) updates) => super.copyWith((message) => updates(message as RestoreChannelInfo)) as RestoreChannelInfo;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RestoreChannelInfo create() => RestoreChannelInfo._();
  RestoreChannelInfo createEmptyInstance() => create();
  static $pb.PbList<RestoreChannelInfo> createRepeated() => $pb.PbList<RestoreChannelInfo>();
  @$core.pragma('dart2js:noInline')
  static RestoreChannelInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RestoreChannelInfo>(create);
  static RestoreChannelInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get channelId => $_getN(0);
  @$pb.TagNumber(1)
  set channelId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasChannelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChannelId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get description => $_getSZ(2);
  @$pb.TagNumber(3)
  set description($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDescription() => $_has(2);
  @$pb.TagNumber(3)
  void clearDescription() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get ownerNodeIdHex => $_getSZ(3);
  @$pb.TagNumber(4)
  set ownerNodeIdHex($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasOwnerNodeIdHex() => $_has(3);
  @$pb.TagNumber(4)
  void clearOwnerNodeIdHex() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<RestoreChannelMember> get members => $_getList(4);
}

class RestoreChannelMember extends $pb.GeneratedMessage {
  factory RestoreChannelMember({
    $core.String? nodeIdHex,
    $core.String? displayName,
    $core.String? role,
    $core.List<$core.int>? ed25519Pk,
    $core.List<$core.int>? x25519Pk,
    $core.List<$core.int>? mlKemPk,
  }) {
    final $result = create();
    if (nodeIdHex != null) {
      $result.nodeIdHex = nodeIdHex;
    }
    if (displayName != null) {
      $result.displayName = displayName;
    }
    if (role != null) {
      $result.role = role;
    }
    if (ed25519Pk != null) {
      $result.ed25519Pk = ed25519Pk;
    }
    if (x25519Pk != null) {
      $result.x25519Pk = x25519Pk;
    }
    if (mlKemPk != null) {
      $result.mlKemPk = mlKemPk;
    }
    return $result;
  }
  RestoreChannelMember._() : super();
  factory RestoreChannelMember.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RestoreChannelMember.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RestoreChannelMember', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'nodeIdHex')
    ..aOS(2, _omitFieldNames ? '' : 'displayName')
    ..aOS(3, _omitFieldNames ? '' : 'role')
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'ed25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'x25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(6, _omitFieldNames ? '' : 'mlKemPk', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RestoreChannelMember clone() => RestoreChannelMember()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RestoreChannelMember copyWith(void Function(RestoreChannelMember) updates) => super.copyWith((message) => updates(message as RestoreChannelMember)) as RestoreChannelMember;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RestoreChannelMember create() => RestoreChannelMember._();
  RestoreChannelMember createEmptyInstance() => create();
  static $pb.PbList<RestoreChannelMember> createRepeated() => $pb.PbList<RestoreChannelMember>();
  @$core.pragma('dart2js:noInline')
  static RestoreChannelMember getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RestoreChannelMember>(create);
  static RestoreChannelMember? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get nodeIdHex => $_getSZ(0);
  @$pb.TagNumber(1)
  set nodeIdHex($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasNodeIdHex() => $_has(0);
  @$pb.TagNumber(1)
  void clearNodeIdHex() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get displayName => $_getSZ(1);
  @$pb.TagNumber(2)
  set displayName($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDisplayName() => $_has(1);
  @$pb.TagNumber(2)
  void clearDisplayName() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get role => $_getSZ(2);
  @$pb.TagNumber(3)
  set role($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasRole() => $_has(2);
  @$pb.TagNumber(3)
  void clearRole() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get ed25519Pk => $_getN(3);
  @$pb.TagNumber(4)
  set ed25519Pk($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasEd25519Pk() => $_has(3);
  @$pb.TagNumber(4)
  void clearEd25519Pk() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get x25519Pk => $_getN(4);
  @$pb.TagNumber(5)
  set x25519Pk($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasX25519Pk() => $_has(4);
  @$pb.TagNumber(5)
  void clearX25519Pk() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get mlKemPk => $_getN(5);
  @$pb.TagNumber(6)
  set mlKemPk($core.List<$core.int> v) { $_setBytes(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasMlKemPk() => $_has(5);
  @$pb.TagNumber(6)
  void clearMlKemPk() => clearField(6);
}

class ContactEntry extends $pb.GeneratedMessage {
  factory ContactEntry({
    $core.List<$core.int>? nodeId,
    $core.String? displayName,
    $core.List<$core.int>? ed25519Pk,
    $core.List<$core.int>? x25519Pk,
    $core.List<$core.int>? mlKemPk,
    $core.List<$core.int>? mlDsaPk,
    $core.List<$core.int>? profilePicture,
    $core.String? description,
  }) {
    final $result = create();
    if (nodeId != null) {
      $result.nodeId = nodeId;
    }
    if (displayName != null) {
      $result.displayName = displayName;
    }
    if (ed25519Pk != null) {
      $result.ed25519Pk = ed25519Pk;
    }
    if (x25519Pk != null) {
      $result.x25519Pk = x25519Pk;
    }
    if (mlKemPk != null) {
      $result.mlKemPk = mlKemPk;
    }
    if (mlDsaPk != null) {
      $result.mlDsaPk = mlDsaPk;
    }
    if (profilePicture != null) {
      $result.profilePicture = profilePicture;
    }
    if (description != null) {
      $result.description = description;
    }
    return $result;
  }
  ContactEntry._() : super();
  factory ContactEntry.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ContactEntry.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ContactEntry', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'nodeId', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'displayName')
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'ed25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'x25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'mlKemPk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(6, _omitFieldNames ? '' : 'mlDsaPk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(7, _omitFieldNames ? '' : 'profilePicture', $pb.PbFieldType.OY)
    ..aOS(8, _omitFieldNames ? '' : 'description')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ContactEntry clone() => ContactEntry()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ContactEntry copyWith(void Function(ContactEntry) updates) => super.copyWith((message) => updates(message as ContactEntry)) as ContactEntry;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ContactEntry create() => ContactEntry._();
  ContactEntry createEmptyInstance() => create();
  static $pb.PbList<ContactEntry> createRepeated() => $pb.PbList<ContactEntry>();
  @$core.pragma('dart2js:noInline')
  static ContactEntry getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ContactEntry>(create);
  static ContactEntry? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get nodeId => $_getN(0);
  @$pb.TagNumber(1)
  set nodeId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasNodeId() => $_has(0);
  @$pb.TagNumber(1)
  void clearNodeId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get displayName => $_getSZ(1);
  @$pb.TagNumber(2)
  set displayName($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDisplayName() => $_has(1);
  @$pb.TagNumber(2)
  void clearDisplayName() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get ed25519Pk => $_getN(2);
  @$pb.TagNumber(3)
  set ed25519Pk($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasEd25519Pk() => $_has(2);
  @$pb.TagNumber(3)
  void clearEd25519Pk() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get x25519Pk => $_getN(3);
  @$pb.TagNumber(4)
  set x25519Pk($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasX25519Pk() => $_has(3);
  @$pb.TagNumber(4)
  void clearX25519Pk() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get mlKemPk => $_getN(4);
  @$pb.TagNumber(5)
  set mlKemPk($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasMlKemPk() => $_has(4);
  @$pb.TagNumber(5)
  void clearMlKemPk() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get mlDsaPk => $_getN(5);
  @$pb.TagNumber(6)
  set mlDsaPk($core.List<$core.int> v) { $_setBytes(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasMlDsaPk() => $_has(5);
  @$pb.TagNumber(6)
  void clearMlDsaPk() => clearField(6);

  @$pb.TagNumber(7)
  $core.List<$core.int> get profilePicture => $_getN(6);
  @$pb.TagNumber(7)
  set profilePicture($core.List<$core.int> v) { $_setBytes(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasProfilePicture() => $_has(6);
  @$pb.TagNumber(7)
  void clearProfilePicture() => clearField(7);

  @$pb.TagNumber(8)
  $core.String get description => $_getSZ(7);
  @$pb.TagNumber(8)
  set description($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasDescription() => $_has(7);
  @$pb.TagNumber(8)
  void clearDescription() => clearField(8);
}

class StoredMessage extends $pb.GeneratedMessage {
  factory StoredMessage({
    $core.List<$core.int>? messageId,
    $core.List<$core.int>? senderId,
    $core.List<$core.int>? recipientId,
    $core.String? conversationId,
    $fixnum.Int64? timestamp,
    MessageType? messageType,
    $core.List<$core.int>? payload,
  }) {
    final $result = create();
    if (messageId != null) {
      $result.messageId = messageId;
    }
    if (senderId != null) {
      $result.senderId = senderId;
    }
    if (recipientId != null) {
      $result.recipientId = recipientId;
    }
    if (conversationId != null) {
      $result.conversationId = conversationId;
    }
    if (timestamp != null) {
      $result.timestamp = timestamp;
    }
    if (messageType != null) {
      $result.messageType = messageType;
    }
    if (payload != null) {
      $result.payload = payload;
    }
    return $result;
  }
  StoredMessage._() : super();
  factory StoredMessage.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StoredMessage.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StoredMessage', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'messageId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'senderId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'recipientId', $pb.PbFieldType.OY)
    ..aOS(4, _omitFieldNames ? '' : 'conversationId')
    ..a<$fixnum.Int64>(5, _omitFieldNames ? '' : 'timestamp', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..e<MessageType>(6, _omitFieldNames ? '' : 'messageType', $pb.PbFieldType.OE, defaultOrMaker: MessageType.TEXT, valueOf: MessageType.valueOf, enumValues: MessageType.values)
    ..a<$core.List<$core.int>>(7, _omitFieldNames ? '' : 'payload', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StoredMessage clone() => StoredMessage()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StoredMessage copyWith(void Function(StoredMessage) updates) => super.copyWith((message) => updates(message as StoredMessage)) as StoredMessage;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StoredMessage create() => StoredMessage._();
  StoredMessage createEmptyInstance() => create();
  static $pb.PbList<StoredMessage> createRepeated() => $pb.PbList<StoredMessage>();
  @$core.pragma('dart2js:noInline')
  static StoredMessage getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StoredMessage>(create);
  static StoredMessage? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get messageId => $_getN(0);
  @$pb.TagNumber(1)
  set messageId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMessageId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessageId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get senderId => $_getN(1);
  @$pb.TagNumber(2)
  set senderId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSenderId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSenderId() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get recipientId => $_getN(2);
  @$pb.TagNumber(3)
  set recipientId($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasRecipientId() => $_has(2);
  @$pb.TagNumber(3)
  void clearRecipientId() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get conversationId => $_getSZ(3);
  @$pb.TagNumber(4)
  set conversationId($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasConversationId() => $_has(3);
  @$pb.TagNumber(4)
  void clearConversationId() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get timestamp => $_getI64(4);
  @$pb.TagNumber(5)
  set timestamp($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasTimestamp() => $_has(4);
  @$pb.TagNumber(5)
  void clearTimestamp() => clearField(5);

  @$pb.TagNumber(6)
  MessageType get messageType => $_getN(5);
  @$pb.TagNumber(6)
  set messageType(MessageType v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasMessageType() => $_has(5);
  @$pb.TagNumber(6)
  void clearMessageType() => clearField(6);

  @$pb.TagNumber(7)
  $core.List<$core.int> get payload => $_getN(6);
  @$pb.TagNumber(7)
  set payload($core.List<$core.int> v) { $_setBytes(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasPayload() => $_has(6);
  @$pb.TagNumber(7)
  void clearPayload() => clearField(7);
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

class CallInvite extends $pb.GeneratedMessage {
  factory CallInvite({
    $core.List<$core.int>? callId,
    $core.List<$core.int>? callerEphX25519Pk,
    $core.List<$core.int>? callerKemCiphertext,
    $core.bool? isVideo,
    $core.bool? isGroupCall,
    $core.List<$core.int>? groupId,
    $core.List<$core.int>? groupCallKey,
  }) {
    final $result = create();
    if (callId != null) {
      $result.callId = callId;
    }
    if (callerEphX25519Pk != null) {
      $result.callerEphX25519Pk = callerEphX25519Pk;
    }
    if (callerKemCiphertext != null) {
      $result.callerKemCiphertext = callerKemCiphertext;
    }
    if (isVideo != null) {
      $result.isVideo = isVideo;
    }
    if (isGroupCall != null) {
      $result.isGroupCall = isGroupCall;
    }
    if (groupId != null) {
      $result.groupId = groupId;
    }
    if (groupCallKey != null) {
      $result.groupCallKey = groupCallKey;
    }
    return $result;
  }
  CallInvite._() : super();
  factory CallInvite.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CallInvite.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CallInvite', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'callId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'callerEphX25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'callerKemCiphertext', $pb.PbFieldType.OY)
    ..aOB(4, _omitFieldNames ? '' : 'isVideo')
    ..aOB(5, _omitFieldNames ? '' : 'isGroupCall')
    ..a<$core.List<$core.int>>(6, _omitFieldNames ? '' : 'groupId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(7, _omitFieldNames ? '' : 'groupCallKey', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CallInvite clone() => CallInvite()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CallInvite copyWith(void Function(CallInvite) updates) => super.copyWith((message) => updates(message as CallInvite)) as CallInvite;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CallInvite create() => CallInvite._();
  CallInvite createEmptyInstance() => create();
  static $pb.PbList<CallInvite> createRepeated() => $pb.PbList<CallInvite>();
  @$core.pragma('dart2js:noInline')
  static CallInvite getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CallInvite>(create);
  static CallInvite? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get callId => $_getN(0);
  @$pb.TagNumber(1)
  set callId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCallId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCallId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get callerEphX25519Pk => $_getN(1);
  @$pb.TagNumber(2)
  set callerEphX25519Pk($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasCallerEphX25519Pk() => $_has(1);
  @$pb.TagNumber(2)
  void clearCallerEphX25519Pk() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get callerKemCiphertext => $_getN(2);
  @$pb.TagNumber(3)
  set callerKemCiphertext($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasCallerKemCiphertext() => $_has(2);
  @$pb.TagNumber(3)
  void clearCallerKemCiphertext() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get isVideo => $_getBF(3);
  @$pb.TagNumber(4)
  set isVideo($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasIsVideo() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsVideo() => clearField(4);

  @$pb.TagNumber(5)
  $core.bool get isGroupCall => $_getBF(4);
  @$pb.TagNumber(5)
  set isGroupCall($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasIsGroupCall() => $_has(4);
  @$pb.TagNumber(5)
  void clearIsGroupCall() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get groupId => $_getN(5);
  @$pb.TagNumber(6)
  set groupId($core.List<$core.int> v) { $_setBytes(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasGroupId() => $_has(5);
  @$pb.TagNumber(6)
  void clearGroupId() => clearField(6);

  @$pb.TagNumber(7)
  $core.List<$core.int> get groupCallKey => $_getN(6);
  @$pb.TagNumber(7)
  set groupCallKey($core.List<$core.int> v) { $_setBytes(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasGroupCallKey() => $_has(6);
  @$pb.TagNumber(7)
  void clearGroupCallKey() => clearField(7);
}

class CallAnswer extends $pb.GeneratedMessage {
  factory CallAnswer({
    $core.List<$core.int>? callId,
    $core.List<$core.int>? calleeEphX25519Pk,
    $core.List<$core.int>? calleeKemCiphertext,
  }) {
    final $result = create();
    if (callId != null) {
      $result.callId = callId;
    }
    if (calleeEphX25519Pk != null) {
      $result.calleeEphX25519Pk = calleeEphX25519Pk;
    }
    if (calleeKemCiphertext != null) {
      $result.calleeKemCiphertext = calleeKemCiphertext;
    }
    return $result;
  }
  CallAnswer._() : super();
  factory CallAnswer.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CallAnswer.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CallAnswer', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'callId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'calleeEphX25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'calleeKemCiphertext', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CallAnswer clone() => CallAnswer()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CallAnswer copyWith(void Function(CallAnswer) updates) => super.copyWith((message) => updates(message as CallAnswer)) as CallAnswer;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CallAnswer create() => CallAnswer._();
  CallAnswer createEmptyInstance() => create();
  static $pb.PbList<CallAnswer> createRepeated() => $pb.PbList<CallAnswer>();
  @$core.pragma('dart2js:noInline')
  static CallAnswer getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CallAnswer>(create);
  static CallAnswer? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get callId => $_getN(0);
  @$pb.TagNumber(1)
  set callId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCallId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCallId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get calleeEphX25519Pk => $_getN(1);
  @$pb.TagNumber(2)
  set calleeEphX25519Pk($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasCalleeEphX25519Pk() => $_has(1);
  @$pb.TagNumber(2)
  void clearCalleeEphX25519Pk() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get calleeKemCiphertext => $_getN(2);
  @$pb.TagNumber(3)
  set calleeKemCiphertext($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasCalleeKemCiphertext() => $_has(2);
  @$pb.TagNumber(3)
  void clearCalleeKemCiphertext() => clearField(3);
}

class CallReject extends $pb.GeneratedMessage {
  factory CallReject({
    $core.List<$core.int>? callId,
    $core.String? reason,
  }) {
    final $result = create();
    if (callId != null) {
      $result.callId = callId;
    }
    if (reason != null) {
      $result.reason = reason;
    }
    return $result;
  }
  CallReject._() : super();
  factory CallReject.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CallReject.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CallReject', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'callId', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'reason')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CallReject clone() => CallReject()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CallReject copyWith(void Function(CallReject) updates) => super.copyWith((message) => updates(message as CallReject)) as CallReject;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CallReject create() => CallReject._();
  CallReject createEmptyInstance() => create();
  static $pb.PbList<CallReject> createRepeated() => $pb.PbList<CallReject>();
  @$core.pragma('dart2js:noInline')
  static CallReject getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CallReject>(create);
  static CallReject? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get callId => $_getN(0);
  @$pb.TagNumber(1)
  set callId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCallId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCallId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get reason => $_getSZ(1);
  @$pb.TagNumber(2)
  set reason($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasReason() => $_has(1);
  @$pb.TagNumber(2)
  void clearReason() => clearField(2);
}

class CallHangup extends $pb.GeneratedMessage {
  factory CallHangup({
    $core.List<$core.int>? callId,
  }) {
    final $result = create();
    if (callId != null) {
      $result.callId = callId;
    }
    return $result;
  }
  CallHangup._() : super();
  factory CallHangup.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CallHangup.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CallHangup', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'callId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CallHangup clone() => CallHangup()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CallHangup copyWith(void Function(CallHangup) updates) => super.copyWith((message) => updates(message as CallHangup)) as CallHangup;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CallHangup create() => CallHangup._();
  CallHangup createEmptyInstance() => create();
  static $pb.PbList<CallHangup> createRepeated() => $pb.PbList<CallHangup>();
  @$core.pragma('dart2js:noInline')
  static CallHangup getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CallHangup>(create);
  static CallHangup? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get callId => $_getN(0);
  @$pb.TagNumber(1)
  set callId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCallId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCallId() => clearField(1);
}

class IceCandidate extends $pb.GeneratedMessage {
  factory IceCandidate({
    $core.List<$core.int>? callId,
    $core.String? candidate,
    $core.String? sdpMid,
    $core.int? sdpMLineIndex,
  }) {
    final $result = create();
    if (callId != null) {
      $result.callId = callId;
    }
    if (candidate != null) {
      $result.candidate = candidate;
    }
    if (sdpMid != null) {
      $result.sdpMid = sdpMid;
    }
    if (sdpMLineIndex != null) {
      $result.sdpMLineIndex = sdpMLineIndex;
    }
    return $result;
  }
  IceCandidate._() : super();
  factory IceCandidate.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory IceCandidate.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'IceCandidate', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'callId', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'candidate')
    ..aOS(3, _omitFieldNames ? '' : 'sdpMid')
    ..a<$core.int>(4, _omitFieldNames ? '' : 'sdpMLineIndex', $pb.PbFieldType.OU3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  IceCandidate clone() => IceCandidate()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  IceCandidate copyWith(void Function(IceCandidate) updates) => super.copyWith((message) => updates(message as IceCandidate)) as IceCandidate;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static IceCandidate create() => IceCandidate._();
  IceCandidate createEmptyInstance() => create();
  static $pb.PbList<IceCandidate> createRepeated() => $pb.PbList<IceCandidate>();
  @$core.pragma('dart2js:noInline')
  static IceCandidate getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<IceCandidate>(create);
  static IceCandidate? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get callId => $_getN(0);
  @$pb.TagNumber(1)
  set callId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCallId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCallId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get candidate => $_getSZ(1);
  @$pb.TagNumber(2)
  set candidate($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasCandidate() => $_has(1);
  @$pb.TagNumber(2)
  void clearCandidate() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get sdpMid => $_getSZ(2);
  @$pb.TagNumber(3)
  set sdpMid($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSdpMid() => $_has(2);
  @$pb.TagNumber(3)
  void clearSdpMid() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get sdpMLineIndex => $_getIZ(3);
  @$pb.TagNumber(4)
  set sdpMLineIndex($core.int v) { $_setUnsignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasSdpMLineIndex() => $_has(3);
  @$pb.TagNumber(4)
  void clearSdpMLineIndex() => clearField(4);
}

class CallRejoin extends $pb.GeneratedMessage {
  factory CallRejoin({
    $core.List<$core.int>? callId,
  }) {
    final $result = create();
    if (callId != null) {
      $result.callId = callId;
    }
    return $result;
  }
  CallRejoin._() : super();
  factory CallRejoin.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CallRejoin.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CallRejoin', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'callId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CallRejoin clone() => CallRejoin()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CallRejoin copyWith(void Function(CallRejoin) updates) => super.copyWith((message) => updates(message as CallRejoin)) as CallRejoin;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CallRejoin create() => CallRejoin._();
  CallRejoin createEmptyInstance() => create();
  static $pb.PbList<CallRejoin> createRepeated() => $pb.PbList<CallRejoin>();
  @$core.pragma('dart2js:noInline')
  static CallRejoin getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CallRejoin>(create);
  static CallRejoin? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get callId => $_getN(0);
  @$pb.TagNumber(1)
  set callId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCallId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCallId() => clearField(1);
}

class KeyRotation extends $pb.GeneratedMessage {
  factory KeyRotation({
    $core.List<$core.int>? newX25519Pk,
    $core.List<$core.int>? newMlKemPk,
    $fixnum.Int64? rotationTimestamp,
    $core.List<$core.int>? signature,
  }) {
    final $result = create();
    if (newX25519Pk != null) {
      $result.newX25519Pk = newX25519Pk;
    }
    if (newMlKemPk != null) {
      $result.newMlKemPk = newMlKemPk;
    }
    if (rotationTimestamp != null) {
      $result.rotationTimestamp = rotationTimestamp;
    }
    if (signature != null) {
      $result.signature = signature;
    }
    return $result;
  }
  KeyRotation._() : super();
  factory KeyRotation.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory KeyRotation.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'KeyRotation', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'newX25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'newMlKemPk', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(3, _omitFieldNames ? '' : 'rotationTimestamp', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'signature', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  KeyRotation clone() => KeyRotation()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  KeyRotation copyWith(void Function(KeyRotation) updates) => super.copyWith((message) => updates(message as KeyRotation)) as KeyRotation;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static KeyRotation create() => KeyRotation._();
  KeyRotation createEmptyInstance() => create();
  static $pb.PbList<KeyRotation> createRepeated() => $pb.PbList<KeyRotation>();
  @$core.pragma('dart2js:noInline')
  static KeyRotation getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<KeyRotation>(create);
  static KeyRotation? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get newX25519Pk => $_getN(0);
  @$pb.TagNumber(1)
  set newX25519Pk($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasNewX25519Pk() => $_has(0);
  @$pb.TagNumber(1)
  void clearNewX25519Pk() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get newMlKemPk => $_getN(1);
  @$pb.TagNumber(2)
  set newMlKemPk($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasNewMlKemPk() => $_has(1);
  @$pb.TagNumber(2)
  void clearNewMlKemPk() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get rotationTimestamp => $_getI64(2);
  @$pb.TagNumber(3)
  set rotationTimestamp($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasRotationTimestamp() => $_has(2);
  @$pb.TagNumber(3)
  void clearRotationTimestamp() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get signature => $_getN(3);
  @$pb.TagNumber(4)
  set signature($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasSignature() => $_has(3);
  @$pb.TagNumber(4)
  void clearSignature() => clearField(4);
}

class ChannelJoinRequest extends $pb.GeneratedMessage {
  factory ChannelJoinRequest({
    $core.List<$core.int>? channelId,
    $core.String? displayName,
    $core.List<$core.int>? ed25519Pk,
    $core.List<$core.int>? x25519Pk,
    $core.List<$core.int>? mlKemPk,
  }) {
    final $result = create();
    if (channelId != null) {
      $result.channelId = channelId;
    }
    if (displayName != null) {
      $result.displayName = displayName;
    }
    if (ed25519Pk != null) {
      $result.ed25519Pk = ed25519Pk;
    }
    if (x25519Pk != null) {
      $result.x25519Pk = x25519Pk;
    }
    if (mlKemPk != null) {
      $result.mlKemPk = mlKemPk;
    }
    return $result;
  }
  ChannelJoinRequest._() : super();
  factory ChannelJoinRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ChannelJoinRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ChannelJoinRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'channelId', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'displayName')
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'ed25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'x25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'mlKemPk', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ChannelJoinRequest clone() => ChannelJoinRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ChannelJoinRequest copyWith(void Function(ChannelJoinRequest) updates) => super.copyWith((message) => updates(message as ChannelJoinRequest)) as ChannelJoinRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChannelJoinRequest create() => ChannelJoinRequest._();
  ChannelJoinRequest createEmptyInstance() => create();
  static $pb.PbList<ChannelJoinRequest> createRepeated() => $pb.PbList<ChannelJoinRequest>();
  @$core.pragma('dart2js:noInline')
  static ChannelJoinRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChannelJoinRequest>(create);
  static ChannelJoinRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get channelId => $_getN(0);
  @$pb.TagNumber(1)
  set channelId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasChannelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChannelId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get displayName => $_getSZ(1);
  @$pb.TagNumber(2)
  set displayName($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDisplayName() => $_has(1);
  @$pb.TagNumber(2)
  void clearDisplayName() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get ed25519Pk => $_getN(2);
  @$pb.TagNumber(3)
  set ed25519Pk($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasEd25519Pk() => $_has(2);
  @$pb.TagNumber(3)
  void clearEd25519Pk() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get x25519Pk => $_getN(3);
  @$pb.TagNumber(4)
  set x25519Pk($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasX25519Pk() => $_has(3);
  @$pb.TagNumber(4)
  void clearX25519Pk() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get mlKemPk => $_getN(4);
  @$pb.TagNumber(5)
  set mlKemPk($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasMlKemPk() => $_has(4);
  @$pb.TagNumber(5)
  void clearMlKemPk() => clearField(5);
}

class ChannelIndexExchange extends $pb.GeneratedMessage {
  factory ChannelIndexExchange({
    $core.Iterable<ChannelIndexEntryProto>? entries,
  }) {
    final $result = create();
    if (entries != null) {
      $result.entries.addAll(entries);
    }
    return $result;
  }
  ChannelIndexExchange._() : super();
  factory ChannelIndexExchange.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ChannelIndexExchange.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ChannelIndexExchange', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..pc<ChannelIndexEntryProto>(1, _omitFieldNames ? '' : 'entries', $pb.PbFieldType.PM, subBuilder: ChannelIndexEntryProto.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ChannelIndexExchange clone() => ChannelIndexExchange()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ChannelIndexExchange copyWith(void Function(ChannelIndexExchange) updates) => super.copyWith((message) => updates(message as ChannelIndexExchange)) as ChannelIndexExchange;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChannelIndexExchange create() => ChannelIndexExchange._();
  ChannelIndexExchange createEmptyInstance() => create();
  static $pb.PbList<ChannelIndexExchange> createRepeated() => $pb.PbList<ChannelIndexExchange>();
  @$core.pragma('dart2js:noInline')
  static ChannelIndexExchange getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChannelIndexExchange>(create);
  static ChannelIndexExchange? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<ChannelIndexEntryProto> get entries => $_getList(0);
}

class ChannelReportMsg extends $pb.GeneratedMessage {
  factory ChannelReportMsg({
    $core.List<$core.int>? reportId,
    $core.List<$core.int>? channelId,
    $core.int? category,
    $core.Iterable<$core.List<$core.int>>? evidencePostIds,
    $core.String? description,
    $fixnum.Int64? createdAtMs,
    $core.bool? isPostReport,
    $core.List<$core.int>? postId,
  }) {
    final $result = create();
    if (reportId != null) {
      $result.reportId = reportId;
    }
    if (channelId != null) {
      $result.channelId = channelId;
    }
    if (category != null) {
      $result.category = category;
    }
    if (evidencePostIds != null) {
      $result.evidencePostIds.addAll(evidencePostIds);
    }
    if (description != null) {
      $result.description = description;
    }
    if (createdAtMs != null) {
      $result.createdAtMs = createdAtMs;
    }
    if (isPostReport != null) {
      $result.isPostReport = isPostReport;
    }
    if (postId != null) {
      $result.postId = postId;
    }
    return $result;
  }
  ChannelReportMsg._() : super();
  factory ChannelReportMsg.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ChannelReportMsg.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ChannelReportMsg', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'reportId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'channelId', $pb.PbFieldType.OY)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'category', $pb.PbFieldType.OU3)
    ..p<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'evidencePostIds', $pb.PbFieldType.PY)
    ..aOS(5, _omitFieldNames ? '' : 'description')
    ..a<$fixnum.Int64>(6, _omitFieldNames ? '' : 'createdAtMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(7, _omitFieldNames ? '' : 'isPostReport')
    ..a<$core.List<$core.int>>(8, _omitFieldNames ? '' : 'postId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ChannelReportMsg clone() => ChannelReportMsg()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ChannelReportMsg copyWith(void Function(ChannelReportMsg) updates) => super.copyWith((message) => updates(message as ChannelReportMsg)) as ChannelReportMsg;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChannelReportMsg create() => ChannelReportMsg._();
  ChannelReportMsg createEmptyInstance() => create();
  static $pb.PbList<ChannelReportMsg> createRepeated() => $pb.PbList<ChannelReportMsg>();
  @$core.pragma('dart2js:noInline')
  static ChannelReportMsg getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChannelReportMsg>(create);
  static ChannelReportMsg? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get reportId => $_getN(0);
  @$pb.TagNumber(1)
  set reportId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasReportId() => $_has(0);
  @$pb.TagNumber(1)
  void clearReportId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get channelId => $_getN(1);
  @$pb.TagNumber(2)
  set channelId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChannelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChannelId() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get category => $_getIZ(2);
  @$pb.TagNumber(3)
  set category($core.int v) { $_setUnsignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasCategory() => $_has(2);
  @$pb.TagNumber(3)
  void clearCategory() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.List<$core.int>> get evidencePostIds => $_getList(3);

  @$pb.TagNumber(5)
  $core.String get description => $_getSZ(4);
  @$pb.TagNumber(5)
  set description($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasDescription() => $_has(4);
  @$pb.TagNumber(5)
  void clearDescription() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get createdAtMs => $_getI64(5);
  @$pb.TagNumber(6)
  set createdAtMs($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasCreatedAtMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearCreatedAtMs() => clearField(6);

  @$pb.TagNumber(7)
  $core.bool get isPostReport => $_getBF(6);
  @$pb.TagNumber(7)
  set isPostReport($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasIsPostReport() => $_has(6);
  @$pb.TagNumber(7)
  void clearIsPostReport() => clearField(7);

  @$pb.TagNumber(8)
  $core.List<$core.int> get postId => $_getN(7);
  @$pb.TagNumber(8)
  set postId($core.List<$core.int> v) { $_setBytes(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasPostId() => $_has(7);
  @$pb.TagNumber(8)
  void clearPostId() => clearField(8);
}

class ChannelReportResponse extends $pb.GeneratedMessage {
  factory ChannelReportResponse({
    $core.List<$core.int>? reportId,
    $core.bool? accepted,
    $core.String? rejectionReason,
  }) {
    final $result = create();
    if (reportId != null) {
      $result.reportId = reportId;
    }
    if (accepted != null) {
      $result.accepted = accepted;
    }
    if (rejectionReason != null) {
      $result.rejectionReason = rejectionReason;
    }
    return $result;
  }
  ChannelReportResponse._() : super();
  factory ChannelReportResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ChannelReportResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ChannelReportResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'reportId', $pb.PbFieldType.OY)
    ..aOB(2, _omitFieldNames ? '' : 'accepted')
    ..aOS(3, _omitFieldNames ? '' : 'rejectionReason')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ChannelReportResponse clone() => ChannelReportResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ChannelReportResponse copyWith(void Function(ChannelReportResponse) updates) => super.copyWith((message) => updates(message as ChannelReportResponse)) as ChannelReportResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChannelReportResponse create() => ChannelReportResponse._();
  ChannelReportResponse createEmptyInstance() => create();
  static $pb.PbList<ChannelReportResponse> createRepeated() => $pb.PbList<ChannelReportResponse>();
  @$core.pragma('dart2js:noInline')
  static ChannelReportResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChannelReportResponse>(create);
  static ChannelReportResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get reportId => $_getN(0);
  @$pb.TagNumber(1)
  set reportId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasReportId() => $_has(0);
  @$pb.TagNumber(1)
  void clearReportId() => clearField(1);

  @$pb.TagNumber(2)
  $core.bool get accepted => $_getBF(1);
  @$pb.TagNumber(2)
  set accepted($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasAccepted() => $_has(1);
  @$pb.TagNumber(2)
  void clearAccepted() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get rejectionReason => $_getSZ(2);
  @$pb.TagNumber(3)
  set rejectionReason($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasRejectionReason() => $_has(2);
  @$pb.TagNumber(3)
  void clearRejectionReason() => clearField(3);
}

class JuryRequestMsg extends $pb.GeneratedMessage {
  factory JuryRequestMsg({
    $core.List<$core.int>? juryId,
    $core.List<$core.int>? channelId,
    $core.List<$core.int>? reportId,
    $core.int? category,
    $core.Iterable<$core.List<$core.int>>? evidencePostIds,
    $core.String? reportDescription,
    $core.String? channelName,
    $core.String? channelLanguage,
  }) {
    final $result = create();
    if (juryId != null) {
      $result.juryId = juryId;
    }
    if (channelId != null) {
      $result.channelId = channelId;
    }
    if (reportId != null) {
      $result.reportId = reportId;
    }
    if (category != null) {
      $result.category = category;
    }
    if (evidencePostIds != null) {
      $result.evidencePostIds.addAll(evidencePostIds);
    }
    if (reportDescription != null) {
      $result.reportDescription = reportDescription;
    }
    if (channelName != null) {
      $result.channelName = channelName;
    }
    if (channelLanguage != null) {
      $result.channelLanguage = channelLanguage;
    }
    return $result;
  }
  JuryRequestMsg._() : super();
  factory JuryRequestMsg.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory JuryRequestMsg.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'JuryRequestMsg', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'juryId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'channelId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'reportId', $pb.PbFieldType.OY)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'category', $pb.PbFieldType.OU3)
    ..p<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'evidencePostIds', $pb.PbFieldType.PY)
    ..aOS(6, _omitFieldNames ? '' : 'reportDescription')
    ..aOS(7, _omitFieldNames ? '' : 'channelName')
    ..aOS(8, _omitFieldNames ? '' : 'channelLanguage')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  JuryRequestMsg clone() => JuryRequestMsg()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  JuryRequestMsg copyWith(void Function(JuryRequestMsg) updates) => super.copyWith((message) => updates(message as JuryRequestMsg)) as JuryRequestMsg;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static JuryRequestMsg create() => JuryRequestMsg._();
  JuryRequestMsg createEmptyInstance() => create();
  static $pb.PbList<JuryRequestMsg> createRepeated() => $pb.PbList<JuryRequestMsg>();
  @$core.pragma('dart2js:noInline')
  static JuryRequestMsg getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<JuryRequestMsg>(create);
  static JuryRequestMsg? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get juryId => $_getN(0);
  @$pb.TagNumber(1)
  set juryId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasJuryId() => $_has(0);
  @$pb.TagNumber(1)
  void clearJuryId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get channelId => $_getN(1);
  @$pb.TagNumber(2)
  set channelId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChannelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChannelId() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get reportId => $_getN(2);
  @$pb.TagNumber(3)
  set reportId($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasReportId() => $_has(2);
  @$pb.TagNumber(3)
  void clearReportId() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get category => $_getIZ(3);
  @$pb.TagNumber(4)
  set category($core.int v) { $_setUnsignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasCategory() => $_has(3);
  @$pb.TagNumber(4)
  void clearCategory() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.List<$core.int>> get evidencePostIds => $_getList(4);

  @$pb.TagNumber(6)
  $core.String get reportDescription => $_getSZ(5);
  @$pb.TagNumber(6)
  set reportDescription($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasReportDescription() => $_has(5);
  @$pb.TagNumber(6)
  void clearReportDescription() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get channelName => $_getSZ(6);
  @$pb.TagNumber(7)
  set channelName($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasChannelName() => $_has(6);
  @$pb.TagNumber(7)
  void clearChannelName() => clearField(7);

  @$pb.TagNumber(8)
  $core.String get channelLanguage => $_getSZ(7);
  @$pb.TagNumber(8)
  set channelLanguage($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasChannelLanguage() => $_has(7);
  @$pb.TagNumber(8)
  void clearChannelLanguage() => clearField(8);
}

class JuryVoteMsg extends $pb.GeneratedMessage {
  factory JuryVoteMsg({
    $core.List<$core.int>? juryId,
    $core.List<$core.int>? reportId,
    $core.int? vote,
    $core.String? reason,
  }) {
    final $result = create();
    if (juryId != null) {
      $result.juryId = juryId;
    }
    if (reportId != null) {
      $result.reportId = reportId;
    }
    if (vote != null) {
      $result.vote = vote;
    }
    if (reason != null) {
      $result.reason = reason;
    }
    return $result;
  }
  JuryVoteMsg._() : super();
  factory JuryVoteMsg.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory JuryVoteMsg.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'JuryVoteMsg', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'juryId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'reportId', $pb.PbFieldType.OY)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'vote', $pb.PbFieldType.OU3)
    ..aOS(4, _omitFieldNames ? '' : 'reason')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  JuryVoteMsg clone() => JuryVoteMsg()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  JuryVoteMsg copyWith(void Function(JuryVoteMsg) updates) => super.copyWith((message) => updates(message as JuryVoteMsg)) as JuryVoteMsg;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static JuryVoteMsg create() => JuryVoteMsg._();
  JuryVoteMsg createEmptyInstance() => create();
  static $pb.PbList<JuryVoteMsg> createRepeated() => $pb.PbList<JuryVoteMsg>();
  @$core.pragma('dart2js:noInline')
  static JuryVoteMsg getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<JuryVoteMsg>(create);
  static JuryVoteMsg? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get juryId => $_getN(0);
  @$pb.TagNumber(1)
  set juryId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasJuryId() => $_has(0);
  @$pb.TagNumber(1)
  void clearJuryId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get reportId => $_getN(1);
  @$pb.TagNumber(2)
  set reportId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasReportId() => $_has(1);
  @$pb.TagNumber(2)
  void clearReportId() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get vote => $_getIZ(2);
  @$pb.TagNumber(3)
  set vote($core.int v) { $_setUnsignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasVote() => $_has(2);
  @$pb.TagNumber(3)
  void clearVote() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get reason => $_getSZ(3);
  @$pb.TagNumber(4)
  set reason($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasReason() => $_has(3);
  @$pb.TagNumber(4)
  void clearReason() => clearField(4);
}

class JuryResultMsg extends $pb.GeneratedMessage {
  factory JuryResultMsg({
    $core.List<$core.int>? juryId,
    $core.List<$core.int>? reportId,
    $core.List<$core.int>? channelId,
    $core.int? consequence,
    $core.int? votesApprove,
    $core.int? votesReject,
    $core.int? votesAbstain,
    $core.int? newBadBadgeLevel,
  }) {
    final $result = create();
    if (juryId != null) {
      $result.juryId = juryId;
    }
    if (reportId != null) {
      $result.reportId = reportId;
    }
    if (channelId != null) {
      $result.channelId = channelId;
    }
    if (consequence != null) {
      $result.consequence = consequence;
    }
    if (votesApprove != null) {
      $result.votesApprove = votesApprove;
    }
    if (votesReject != null) {
      $result.votesReject = votesReject;
    }
    if (votesAbstain != null) {
      $result.votesAbstain = votesAbstain;
    }
    if (newBadBadgeLevel != null) {
      $result.newBadBadgeLevel = newBadBadgeLevel;
    }
    return $result;
  }
  JuryResultMsg._() : super();
  factory JuryResultMsg.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory JuryResultMsg.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'JuryResultMsg', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'juryId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'reportId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'channelId', $pb.PbFieldType.OY)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'consequence', $pb.PbFieldType.OU3)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'votesApprove', $pb.PbFieldType.OU3)
    ..a<$core.int>(6, _omitFieldNames ? '' : 'votesReject', $pb.PbFieldType.OU3)
    ..a<$core.int>(7, _omitFieldNames ? '' : 'votesAbstain', $pb.PbFieldType.OU3)
    ..a<$core.int>(8, _omitFieldNames ? '' : 'newBadBadgeLevel', $pb.PbFieldType.OU3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  JuryResultMsg clone() => JuryResultMsg()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  JuryResultMsg copyWith(void Function(JuryResultMsg) updates) => super.copyWith((message) => updates(message as JuryResultMsg)) as JuryResultMsg;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static JuryResultMsg create() => JuryResultMsg._();
  JuryResultMsg createEmptyInstance() => create();
  static $pb.PbList<JuryResultMsg> createRepeated() => $pb.PbList<JuryResultMsg>();
  @$core.pragma('dart2js:noInline')
  static JuryResultMsg getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<JuryResultMsg>(create);
  static JuryResultMsg? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get juryId => $_getN(0);
  @$pb.TagNumber(1)
  set juryId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasJuryId() => $_has(0);
  @$pb.TagNumber(1)
  void clearJuryId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get reportId => $_getN(1);
  @$pb.TagNumber(2)
  set reportId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasReportId() => $_has(1);
  @$pb.TagNumber(2)
  void clearReportId() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get channelId => $_getN(2);
  @$pb.TagNumber(3)
  set channelId($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasChannelId() => $_has(2);
  @$pb.TagNumber(3)
  void clearChannelId() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get consequence => $_getIZ(3);
  @$pb.TagNumber(4)
  set consequence($core.int v) { $_setUnsignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasConsequence() => $_has(3);
  @$pb.TagNumber(4)
  void clearConsequence() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get votesApprove => $_getIZ(4);
  @$pb.TagNumber(5)
  set votesApprove($core.int v) { $_setUnsignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasVotesApprove() => $_has(4);
  @$pb.TagNumber(5)
  void clearVotesApprove() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get votesReject => $_getIZ(5);
  @$pb.TagNumber(6)
  set votesReject($core.int v) { $_setUnsignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasVotesReject() => $_has(5);
  @$pb.TagNumber(6)
  void clearVotesReject() => clearField(6);

  @$pb.TagNumber(7)
  $core.int get votesAbstain => $_getIZ(6);
  @$pb.TagNumber(7)
  set votesAbstain($core.int v) { $_setUnsignedInt32(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasVotesAbstain() => $_has(6);
  @$pb.TagNumber(7)
  void clearVotesAbstain() => clearField(7);

  @$pb.TagNumber(8)
  $core.int get newBadBadgeLevel => $_getIZ(7);
  @$pb.TagNumber(8)
  set newBadBadgeLevel($core.int v) { $_setUnsignedInt32(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasNewBadBadgeLevel() => $_has(7);
  @$pb.TagNumber(8)
  void clearNewBadBadgeLevel() => clearField(8);
}

class ChannelIndexEntryProto extends $pb.GeneratedMessage {
  factory ChannelIndexEntryProto({
    $core.List<$core.int>? channelId,
    $core.String? name,
    $core.String? language,
    $core.bool? isAdult,
    $core.String? description,
    $core.int? subscriberCount,
    $core.int? badBadgeLevel,
    $fixnum.Int64? badBadgeSinceMs,
    $core.bool? correctionSubmitted,
    $core.List<$core.int>? ownerNodeId,
    $fixnum.Int64? createdAtMs,
    $core.List<$core.int>? ownerSignature,
  }) {
    final $result = create();
    if (channelId != null) {
      $result.channelId = channelId;
    }
    if (name != null) {
      $result.name = name;
    }
    if (language != null) {
      $result.language = language;
    }
    if (isAdult != null) {
      $result.isAdult = isAdult;
    }
    if (description != null) {
      $result.description = description;
    }
    if (subscriberCount != null) {
      $result.subscriberCount = subscriberCount;
    }
    if (badBadgeLevel != null) {
      $result.badBadgeLevel = badBadgeLevel;
    }
    if (badBadgeSinceMs != null) {
      $result.badBadgeSinceMs = badBadgeSinceMs;
    }
    if (correctionSubmitted != null) {
      $result.correctionSubmitted = correctionSubmitted;
    }
    if (ownerNodeId != null) {
      $result.ownerNodeId = ownerNodeId;
    }
    if (createdAtMs != null) {
      $result.createdAtMs = createdAtMs;
    }
    if (ownerSignature != null) {
      $result.ownerSignature = ownerSignature;
    }
    return $result;
  }
  ChannelIndexEntryProto._() : super();
  factory ChannelIndexEntryProto.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ChannelIndexEntryProto.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ChannelIndexEntryProto', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'channelId', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'language')
    ..aOB(4, _omitFieldNames ? '' : 'isAdult')
    ..aOS(5, _omitFieldNames ? '' : 'description')
    ..a<$core.int>(6, _omitFieldNames ? '' : 'subscriberCount', $pb.PbFieldType.OU3)
    ..a<$core.int>(7, _omitFieldNames ? '' : 'badBadgeLevel', $pb.PbFieldType.OU3)
    ..a<$fixnum.Int64>(8, _omitFieldNames ? '' : 'badBadgeSinceMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(9, _omitFieldNames ? '' : 'correctionSubmitted')
    ..a<$core.List<$core.int>>(10, _omitFieldNames ? '' : 'ownerNodeId', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(11, _omitFieldNames ? '' : 'createdAtMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(12, _omitFieldNames ? '' : 'ownerSignature', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ChannelIndexEntryProto clone() => ChannelIndexEntryProto()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ChannelIndexEntryProto copyWith(void Function(ChannelIndexEntryProto) updates) => super.copyWith((message) => updates(message as ChannelIndexEntryProto)) as ChannelIndexEntryProto;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChannelIndexEntryProto create() => ChannelIndexEntryProto._();
  ChannelIndexEntryProto createEmptyInstance() => create();
  static $pb.PbList<ChannelIndexEntryProto> createRepeated() => $pb.PbList<ChannelIndexEntryProto>();
  @$core.pragma('dart2js:noInline')
  static ChannelIndexEntryProto getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChannelIndexEntryProto>(create);
  static ChannelIndexEntryProto? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get channelId => $_getN(0);
  @$pb.TagNumber(1)
  set channelId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasChannelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChannelId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get language => $_getSZ(2);
  @$pb.TagNumber(3)
  set language($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasLanguage() => $_has(2);
  @$pb.TagNumber(3)
  void clearLanguage() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get isAdult => $_getBF(3);
  @$pb.TagNumber(4)
  set isAdult($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasIsAdult() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsAdult() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get description => $_getSZ(4);
  @$pb.TagNumber(5)
  set description($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasDescription() => $_has(4);
  @$pb.TagNumber(5)
  void clearDescription() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get subscriberCount => $_getIZ(5);
  @$pb.TagNumber(6)
  set subscriberCount($core.int v) { $_setUnsignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasSubscriberCount() => $_has(5);
  @$pb.TagNumber(6)
  void clearSubscriberCount() => clearField(6);

  @$pb.TagNumber(7)
  $core.int get badBadgeLevel => $_getIZ(6);
  @$pb.TagNumber(7)
  set badBadgeLevel($core.int v) { $_setUnsignedInt32(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasBadBadgeLevel() => $_has(6);
  @$pb.TagNumber(7)
  void clearBadBadgeLevel() => clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get badBadgeSinceMs => $_getI64(7);
  @$pb.TagNumber(8)
  set badBadgeSinceMs($fixnum.Int64 v) { $_setInt64(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasBadBadgeSinceMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearBadBadgeSinceMs() => clearField(8);

  @$pb.TagNumber(9)
  $core.bool get correctionSubmitted => $_getBF(8);
  @$pb.TagNumber(9)
  set correctionSubmitted($core.bool v) { $_setBool(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasCorrectionSubmitted() => $_has(8);
  @$pb.TagNumber(9)
  void clearCorrectionSubmitted() => clearField(9);

  @$pb.TagNumber(10)
  $core.List<$core.int> get ownerNodeId => $_getN(9);
  @$pb.TagNumber(10)
  set ownerNodeId($core.List<$core.int> v) { $_setBytes(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasOwnerNodeId() => $_has(9);
  @$pb.TagNumber(10)
  void clearOwnerNodeId() => clearField(10);

  @$pb.TagNumber(11)
  $fixnum.Int64 get createdAtMs => $_getI64(10);
  @$pb.TagNumber(11)
  set createdAtMs($fixnum.Int64 v) { $_setInt64(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasCreatedAtMs() => $_has(10);
  @$pb.TagNumber(11)
  void clearCreatedAtMs() => clearField(11);

  @$pb.TagNumber(12)
  $core.List<$core.int> get ownerSignature => $_getN(11);
  @$pb.TagNumber(12)
  set ownerSignature($core.List<$core.int> v) { $_setBytes(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasOwnerSignature() => $_has(11);
  @$pb.TagNumber(12)
  void clearOwnerSignature() => clearField(12);
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
  }) {
    final $result = create();
    if (messageId != null) {
      $result.messageId = messageId;
    }
    if (deliveredAt != null) {
      $result.deliveredAt = deliveredAt;
    }
    return $result;
  }
  DeliveryReceipt._() : super();
  factory DeliveryReceipt.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DeliveryReceipt.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DeliveryReceipt', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'messageId', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'deliveredAt', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
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
}

class ReadReceipt extends $pb.GeneratedMessage {
  factory ReadReceipt({
    $core.List<$core.int>? messageId,
    $fixnum.Int64? readAt,
  }) {
    final $result = create();
    if (messageId != null) {
      $result.messageId = messageId;
    }
    if (readAt != null) {
      $result.readAt = readAt;
    }
    return $result;
  }
  ReadReceipt._() : super();
  factory ReadReceipt.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ReadReceipt.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ReadReceipt', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'messageId', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'readAt', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ReadReceipt clone() => ReadReceipt()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ReadReceipt copyWith(void Function(ReadReceipt) updates) => super.copyWith((message) => updates(message as ReadReceipt)) as ReadReceipt;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ReadReceipt create() => ReadReceipt._();
  ReadReceipt createEmptyInstance() => create();
  static $pb.PbList<ReadReceipt> createRepeated() => $pb.PbList<ReadReceipt>();
  @$core.pragma('dart2js:noInline')
  static ReadReceipt getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ReadReceipt>(create);
  static ReadReceipt? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get messageId => $_getN(0);
  @$pb.TagNumber(1)
  set messageId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMessageId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessageId() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get readAt => $_getI64(1);
  @$pb.TagNumber(2)
  set readAt($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasReadAt() => $_has(1);
  @$pb.TagNumber(2)
  void clearReadAt() => clearField(2);
}

class TypingIndicator extends $pb.GeneratedMessage {
  factory TypingIndicator({
    $core.String? conversationId,
    $core.bool? isTyping,
  }) {
    final $result = create();
    if (conversationId != null) {
      $result.conversationId = conversationId;
    }
    if (isTyping != null) {
      $result.isTyping = isTyping;
    }
    return $result;
  }
  TypingIndicator._() : super();
  factory TypingIndicator.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TypingIndicator.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TypingIndicator', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'conversationId')
    ..aOB(2, _omitFieldNames ? '' : 'isTyping')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TypingIndicator clone() => TypingIndicator()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TypingIndicator copyWith(void Function(TypingIndicator) updates) => super.copyWith((message) => updates(message as TypingIndicator)) as TypingIndicator;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TypingIndicator create() => TypingIndicator._();
  TypingIndicator createEmptyInstance() => create();
  static $pb.PbList<TypingIndicator> createRepeated() => $pb.PbList<TypingIndicator>();
  @$core.pragma('dart2js:noInline')
  static TypingIndicator getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TypingIndicator>(create);
  static TypingIndicator? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get conversationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set conversationId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasConversationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearConversationId() => clearField(1);

  @$pb.TagNumber(2)
  $core.bool get isTyping => $_getBF(1);
  @$pb.TagNumber(2)
  set isTyping($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasIsTyping() => $_has(1);
  @$pb.TagNumber(2)
  void clearIsTyping() => clearField(2);
}

class MessageEdit extends $pb.GeneratedMessage {
  factory MessageEdit({
    $core.List<$core.int>? originalMessageId,
    $core.String? newText,
    $fixnum.Int64? editTimestamp,
  }) {
    final $result = create();
    if (originalMessageId != null) {
      $result.originalMessageId = originalMessageId;
    }
    if (newText != null) {
      $result.newText = newText;
    }
    if (editTimestamp != null) {
      $result.editTimestamp = editTimestamp;
    }
    return $result;
  }
  MessageEdit._() : super();
  factory MessageEdit.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MessageEdit.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MessageEdit', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'originalMessageId', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'newText')
    ..a<$fixnum.Int64>(3, _omitFieldNames ? '' : 'editTimestamp', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MessageEdit clone() => MessageEdit()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MessageEdit copyWith(void Function(MessageEdit) updates) => super.copyWith((message) => updates(message as MessageEdit)) as MessageEdit;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MessageEdit create() => MessageEdit._();
  MessageEdit createEmptyInstance() => create();
  static $pb.PbList<MessageEdit> createRepeated() => $pb.PbList<MessageEdit>();
  @$core.pragma('dart2js:noInline')
  static MessageEdit getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MessageEdit>(create);
  static MessageEdit? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get originalMessageId => $_getN(0);
  @$pb.TagNumber(1)
  set originalMessageId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasOriginalMessageId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOriginalMessageId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get newText => $_getSZ(1);
  @$pb.TagNumber(2)
  set newText($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasNewText() => $_has(1);
  @$pb.TagNumber(2)
  void clearNewText() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get editTimestamp => $_getI64(2);
  @$pb.TagNumber(3)
  set editTimestamp($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasEditTimestamp() => $_has(2);
  @$pb.TagNumber(3)
  void clearEditTimestamp() => clearField(3);
}

class MessageDelete extends $pb.GeneratedMessage {
  factory MessageDelete({
    $core.List<$core.int>? messageId,
    $fixnum.Int64? deletedAt,
  }) {
    final $result = create();
    if (messageId != null) {
      $result.messageId = messageId;
    }
    if (deletedAt != null) {
      $result.deletedAt = deletedAt;
    }
    return $result;
  }
  MessageDelete._() : super();
  factory MessageDelete.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MessageDelete.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MessageDelete', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'messageId', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'deletedAt', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MessageDelete clone() => MessageDelete()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MessageDelete copyWith(void Function(MessageDelete) updates) => super.copyWith((message) => updates(message as MessageDelete)) as MessageDelete;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MessageDelete create() => MessageDelete._();
  MessageDelete createEmptyInstance() => create();
  static $pb.PbList<MessageDelete> createRepeated() => $pb.PbList<MessageDelete>();
  @$core.pragma('dart2js:noInline')
  static MessageDelete getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MessageDelete>(create);
  static MessageDelete? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get messageId => $_getN(0);
  @$pb.TagNumber(1)
  set messageId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMessageId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessageId() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get deletedAt => $_getI64(1);
  @$pb.TagNumber(2)
  set deletedAt($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDeletedAt() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeletedAt() => clearField(2);
}

class EmojiReaction extends $pb.GeneratedMessage {
  factory EmojiReaction({
    $core.List<$core.int>? messageId,
    $core.String? emoji,
    $core.bool? remove,
  }) {
    final $result = create();
    if (messageId != null) {
      $result.messageId = messageId;
    }
    if (emoji != null) {
      $result.emoji = emoji;
    }
    if (remove != null) {
      $result.remove = remove;
    }
    return $result;
  }
  EmojiReaction._() : super();
  factory EmojiReaction.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EmojiReaction.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EmojiReaction', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'messageId', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'emoji')
    ..aOB(3, _omitFieldNames ? '' : 'remove')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EmojiReaction clone() => EmojiReaction()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EmojiReaction copyWith(void Function(EmojiReaction) updates) => super.copyWith((message) => updates(message as EmojiReaction)) as EmojiReaction;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EmojiReaction create() => EmojiReaction._();
  EmojiReaction createEmptyInstance() => create();
  static $pb.PbList<EmojiReaction> createRepeated() => $pb.PbList<EmojiReaction>();
  @$core.pragma('dart2js:noInline')
  static EmojiReaction getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EmojiReaction>(create);
  static EmojiReaction? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get messageId => $_getN(0);
  @$pb.TagNumber(1)
  set messageId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMessageId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessageId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get emoji => $_getSZ(1);
  @$pb.TagNumber(2)
  set emoji($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasEmoji() => $_has(1);
  @$pb.TagNumber(2)
  void clearEmoji() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get remove => $_getBF(2);
  @$pb.TagNumber(3)
  set remove($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasRemove() => $_has(2);
  @$pb.TagNumber(3)
  void clearRemove() => clearField(3);
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

class MediaChunk extends $pb.GeneratedMessage {
  factory MediaChunk({
    $core.List<$core.int>? transferId,
    $core.int? chunkIndex,
    $core.int? totalChunks,
    $core.List<$core.int>? chunkData,
    $core.List<$core.int>? originalRecipientId,
  }) {
    final $result = create();
    if (transferId != null) {
      $result.transferId = transferId;
    }
    if (chunkIndex != null) {
      $result.chunkIndex = chunkIndex;
    }
    if (totalChunks != null) {
      $result.totalChunks = totalChunks;
    }
    if (chunkData != null) {
      $result.chunkData = chunkData;
    }
    if (originalRecipientId != null) {
      $result.originalRecipientId = originalRecipientId;
    }
    return $result;
  }
  MediaChunk._() : super();
  factory MediaChunk.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MediaChunk.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MediaChunk', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'transferId', $pb.PbFieldType.OY)
    ..a<$core.int>(2, _omitFieldNames ? '' : 'chunkIndex', $pb.PbFieldType.OU3)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'totalChunks', $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'chunkData', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'originalRecipientId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MediaChunk clone() => MediaChunk()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MediaChunk copyWith(void Function(MediaChunk) updates) => super.copyWith((message) => updates(message as MediaChunk)) as MediaChunk;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MediaChunk create() => MediaChunk._();
  MediaChunk createEmptyInstance() => create();
  static $pb.PbList<MediaChunk> createRepeated() => $pb.PbList<MediaChunk>();
  @$core.pragma('dart2js:noInline')
  static MediaChunk getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MediaChunk>(create);
  static MediaChunk? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get transferId => $_getN(0);
  @$pb.TagNumber(1)
  set transferId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTransferId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTransferId() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get chunkIndex => $_getIZ(1);
  @$pb.TagNumber(2)
  set chunkIndex($core.int v) { $_setUnsignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChunkIndex() => $_has(1);
  @$pb.TagNumber(2)
  void clearChunkIndex() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get totalChunks => $_getIZ(2);
  @$pb.TagNumber(3)
  set totalChunks($core.int v) { $_setUnsignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTotalChunks() => $_has(2);
  @$pb.TagNumber(3)
  void clearTotalChunks() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get chunkData => $_getN(3);
  @$pb.TagNumber(4)
  set chunkData($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasChunkData() => $_has(3);
  @$pb.TagNumber(4)
  void clearChunkData() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get originalRecipientId => $_getN(4);
  @$pb.TagNumber(5)
  set originalRecipientId($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasOriginalRecipientId() => $_has(4);
  @$pb.TagNumber(5)
  void clearOriginalRecipientId() => clearField(5);
}

class CallRttPing extends $pb.GeneratedMessage {
  factory CallRttPing({
    $core.List<$core.int>? callId,
    $fixnum.Int64? timestampUs,
  }) {
    final $result = create();
    if (callId != null) {
      $result.callId = callId;
    }
    if (timestampUs != null) {
      $result.timestampUs = timestampUs;
    }
    return $result;
  }
  CallRttPing._() : super();
  factory CallRttPing.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CallRttPing.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CallRttPing', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'callId', $pb.PbFieldType.OY)
    ..aInt64(2, _omitFieldNames ? '' : 'timestampUs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CallRttPing clone() => CallRttPing()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CallRttPing copyWith(void Function(CallRttPing) updates) => super.copyWith((message) => updates(message as CallRttPing)) as CallRttPing;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CallRttPing create() => CallRttPing._();
  CallRttPing createEmptyInstance() => create();
  static $pb.PbList<CallRttPing> createRepeated() => $pb.PbList<CallRttPing>();
  @$core.pragma('dart2js:noInline')
  static CallRttPing getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CallRttPing>(create);
  static CallRttPing? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get callId => $_getN(0);
  @$pb.TagNumber(1)
  set callId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCallId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCallId() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampUs => $_getI64(1);
  @$pb.TagNumber(2)
  set timestampUs($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTimestampUs() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestampUs() => clearField(2);
}

class CallRttPong extends $pb.GeneratedMessage {
  factory CallRttPong({
    $core.List<$core.int>? callId,
    $fixnum.Int64? echoTimestampUs,
    $fixnum.Int64? responderTimestampUs,
  }) {
    final $result = create();
    if (callId != null) {
      $result.callId = callId;
    }
    if (echoTimestampUs != null) {
      $result.echoTimestampUs = echoTimestampUs;
    }
    if (responderTimestampUs != null) {
      $result.responderTimestampUs = responderTimestampUs;
    }
    return $result;
  }
  CallRttPong._() : super();
  factory CallRttPong.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CallRttPong.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CallRttPong', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'callId', $pb.PbFieldType.OY)
    ..aInt64(2, _omitFieldNames ? '' : 'echoTimestampUs')
    ..aInt64(3, _omitFieldNames ? '' : 'responderTimestampUs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CallRttPong clone() => CallRttPong()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CallRttPong copyWith(void Function(CallRttPong) updates) => super.copyWith((message) => updates(message as CallRttPong)) as CallRttPong;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CallRttPong create() => CallRttPong._();
  CallRttPong createEmptyInstance() => create();
  static $pb.PbList<CallRttPong> createRepeated() => $pb.PbList<CallRttPong>();
  @$core.pragma('dart2js:noInline')
  static CallRttPong getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CallRttPong>(create);
  static CallRttPong? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get callId => $_getN(0);
  @$pb.TagNumber(1)
  set callId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCallId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCallId() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get echoTimestampUs => $_getI64(1);
  @$pb.TagNumber(2)
  set echoTimestampUs($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasEchoTimestampUs() => $_has(1);
  @$pb.TagNumber(2)
  void clearEchoTimestampUs() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get responderTimestampUs => $_getI64(2);
  @$pb.TagNumber(3)
  set responderTimestampUs($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasResponderTimestampUs() => $_has(2);
  @$pb.TagNumber(3)
  void clearResponderTimestampUs() => clearField(3);
}

class OverlayTreeNode extends $pb.GeneratedMessage {
  factory OverlayTreeNode({
    $core.List<$core.int>? nodeId,
    $core.List<$core.int>? parentNodeId,
    $core.Iterable<$core.List<$core.int>>? childNodeIds,
    $core.bool? isLanClusterHead,
    $core.Iterable<$core.List<$core.int>>? lanMemberIds,
  }) {
    final $result = create();
    if (nodeId != null) {
      $result.nodeId = nodeId;
    }
    if (parentNodeId != null) {
      $result.parentNodeId = parentNodeId;
    }
    if (childNodeIds != null) {
      $result.childNodeIds.addAll(childNodeIds);
    }
    if (isLanClusterHead != null) {
      $result.isLanClusterHead = isLanClusterHead;
    }
    if (lanMemberIds != null) {
      $result.lanMemberIds.addAll(lanMemberIds);
    }
    return $result;
  }
  OverlayTreeNode._() : super();
  factory OverlayTreeNode.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory OverlayTreeNode.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'OverlayTreeNode', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'nodeId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'parentNodeId', $pb.PbFieldType.OY)
    ..p<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'childNodeIds', $pb.PbFieldType.PY)
    ..aOB(4, _omitFieldNames ? '' : 'isLanClusterHead')
    ..p<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'lanMemberIds', $pb.PbFieldType.PY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  OverlayTreeNode clone() => OverlayTreeNode()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  OverlayTreeNode copyWith(void Function(OverlayTreeNode) updates) => super.copyWith((message) => updates(message as OverlayTreeNode)) as OverlayTreeNode;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static OverlayTreeNode create() => OverlayTreeNode._();
  OverlayTreeNode createEmptyInstance() => create();
  static $pb.PbList<OverlayTreeNode> createRepeated() => $pb.PbList<OverlayTreeNode>();
  @$core.pragma('dart2js:noInline')
  static OverlayTreeNode getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<OverlayTreeNode>(create);
  static OverlayTreeNode? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get nodeId => $_getN(0);
  @$pb.TagNumber(1)
  set nodeId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasNodeId() => $_has(0);
  @$pb.TagNumber(1)
  void clearNodeId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get parentNodeId => $_getN(1);
  @$pb.TagNumber(2)
  set parentNodeId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasParentNodeId() => $_has(1);
  @$pb.TagNumber(2)
  void clearParentNodeId() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.List<$core.int>> get childNodeIds => $_getList(2);

  @$pb.TagNumber(4)
  $core.bool get isLanClusterHead => $_getBF(3);
  @$pb.TagNumber(4)
  set isLanClusterHead($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasIsLanClusterHead() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsLanClusterHead() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.List<$core.int>> get lanMemberIds => $_getList(4);
}

class CallTreeUpdate extends $pb.GeneratedMessage {
  factory CallTreeUpdate({
    $core.List<$core.int>? callId,
    $core.Iterable<OverlayTreeNode>? nodes,
    $core.List<$core.int>? initiatorNodeId,
    $core.int? version,
  }) {
    final $result = create();
    if (callId != null) {
      $result.callId = callId;
    }
    if (nodes != null) {
      $result.nodes.addAll(nodes);
    }
    if (initiatorNodeId != null) {
      $result.initiatorNodeId = initiatorNodeId;
    }
    if (version != null) {
      $result.version = version;
    }
    return $result;
  }
  CallTreeUpdate._() : super();
  factory CallTreeUpdate.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CallTreeUpdate.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CallTreeUpdate', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'callId', $pb.PbFieldType.OY)
    ..pc<OverlayTreeNode>(2, _omitFieldNames ? '' : 'nodes', $pb.PbFieldType.PM, subBuilder: OverlayTreeNode.create)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'initiatorNodeId', $pb.PbFieldType.OY)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'version', $pb.PbFieldType.OU3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CallTreeUpdate clone() => CallTreeUpdate()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CallTreeUpdate copyWith(void Function(CallTreeUpdate) updates) => super.copyWith((message) => updates(message as CallTreeUpdate)) as CallTreeUpdate;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CallTreeUpdate create() => CallTreeUpdate._();
  CallTreeUpdate createEmptyInstance() => create();
  static $pb.PbList<CallTreeUpdate> createRepeated() => $pb.PbList<CallTreeUpdate>();
  @$core.pragma('dart2js:noInline')
  static CallTreeUpdate getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CallTreeUpdate>(create);
  static CallTreeUpdate? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get callId => $_getN(0);
  @$pb.TagNumber(1)
  set callId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCallId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCallId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<OverlayTreeNode> get nodes => $_getList(1);

  @$pb.TagNumber(3)
  $core.List<$core.int> get initiatorNodeId => $_getN(2);
  @$pb.TagNumber(3)
  set initiatorNodeId($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasInitiatorNodeId() => $_has(2);
  @$pb.TagNumber(3)
  void clearInitiatorNodeId() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get version => $_getIZ(3);
  @$pb.TagNumber(4)
  set version($core.int v) { $_setUnsignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasVersion() => $_has(3);
  @$pb.TagNumber(4)
  void clearVersion() => clearField(4);
}

/// Video frame flags (bitmask in flags field):
///   0x01 = keyframe
///   0x02 = last fragment of this frame
///   0x04 = frame is a fragment (not complete)
class VideoFrame extends $pb.GeneratedMessage {
  factory VideoFrame({
    $core.List<$core.int>? callId,
    $core.int? sequenceNumber,
    $core.int? flags,
    $core.int? fragmentIndex,
    $core.int? fragmentTotal,
    $core.int? width,
    $core.int? height,
    $core.List<$core.int>? nonce,
    $core.List<$core.int>? encryptedData,
    $core.int? timestampMs,
  }) {
    final $result = create();
    if (callId != null) {
      $result.callId = callId;
    }
    if (sequenceNumber != null) {
      $result.sequenceNumber = sequenceNumber;
    }
    if (flags != null) {
      $result.flags = flags;
    }
    if (fragmentIndex != null) {
      $result.fragmentIndex = fragmentIndex;
    }
    if (fragmentTotal != null) {
      $result.fragmentTotal = fragmentTotal;
    }
    if (width != null) {
      $result.width = width;
    }
    if (height != null) {
      $result.height = height;
    }
    if (nonce != null) {
      $result.nonce = nonce;
    }
    if (encryptedData != null) {
      $result.encryptedData = encryptedData;
    }
    if (timestampMs != null) {
      $result.timestampMs = timestampMs;
    }
    return $result;
  }
  VideoFrame._() : super();
  factory VideoFrame.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VideoFrame.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'VideoFrame', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'callId', $pb.PbFieldType.OY)
    ..a<$core.int>(2, _omitFieldNames ? '' : 'sequenceNumber', $pb.PbFieldType.OU3)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'flags', $pb.PbFieldType.OU3)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'fragmentIndex', $pb.PbFieldType.OU3)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'fragmentTotal', $pb.PbFieldType.OU3)
    ..a<$core.int>(6, _omitFieldNames ? '' : 'width', $pb.PbFieldType.OU3)
    ..a<$core.int>(7, _omitFieldNames ? '' : 'height', $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(8, _omitFieldNames ? '' : 'nonce', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(9, _omitFieldNames ? '' : 'encryptedData', $pb.PbFieldType.OY)
    ..a<$core.int>(10, _omitFieldNames ? '' : 'timestampMs', $pb.PbFieldType.OU3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VideoFrame clone() => VideoFrame()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VideoFrame copyWith(void Function(VideoFrame) updates) => super.copyWith((message) => updates(message as VideoFrame)) as VideoFrame;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VideoFrame create() => VideoFrame._();
  VideoFrame createEmptyInstance() => create();
  static $pb.PbList<VideoFrame> createRepeated() => $pb.PbList<VideoFrame>();
  @$core.pragma('dart2js:noInline')
  static VideoFrame getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VideoFrame>(create);
  static VideoFrame? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get callId => $_getN(0);
  @$pb.TagNumber(1)
  set callId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCallId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCallId() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get sequenceNumber => $_getIZ(1);
  @$pb.TagNumber(2)
  set sequenceNumber($core.int v) { $_setUnsignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSequenceNumber() => $_has(1);
  @$pb.TagNumber(2)
  void clearSequenceNumber() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get flags => $_getIZ(2);
  @$pb.TagNumber(3)
  set flags($core.int v) { $_setUnsignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasFlags() => $_has(2);
  @$pb.TagNumber(3)
  void clearFlags() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get fragmentIndex => $_getIZ(3);
  @$pb.TagNumber(4)
  set fragmentIndex($core.int v) { $_setUnsignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasFragmentIndex() => $_has(3);
  @$pb.TagNumber(4)
  void clearFragmentIndex() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get fragmentTotal => $_getIZ(4);
  @$pb.TagNumber(5)
  set fragmentTotal($core.int v) { $_setUnsignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasFragmentTotal() => $_has(4);
  @$pb.TagNumber(5)
  void clearFragmentTotal() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get width => $_getIZ(5);
  @$pb.TagNumber(6)
  set width($core.int v) { $_setUnsignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasWidth() => $_has(5);
  @$pb.TagNumber(6)
  void clearWidth() => clearField(6);

  @$pb.TagNumber(7)
  $core.int get height => $_getIZ(6);
  @$pb.TagNumber(7)
  set height($core.int v) { $_setUnsignedInt32(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasHeight() => $_has(6);
  @$pb.TagNumber(7)
  void clearHeight() => clearField(7);

  @$pb.TagNumber(8)
  $core.List<$core.int> get nonce => $_getN(7);
  @$pb.TagNumber(8)
  set nonce($core.List<$core.int> v) { $_setBytes(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasNonce() => $_has(7);
  @$pb.TagNumber(8)
  void clearNonce() => clearField(8);

  @$pb.TagNumber(9)
  $core.List<$core.int> get encryptedData => $_getN(8);
  @$pb.TagNumber(9)
  set encryptedData($core.List<$core.int> v) { $_setBytes(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasEncryptedData() => $_has(8);
  @$pb.TagNumber(9)
  void clearEncryptedData() => clearField(9);

  @$pb.TagNumber(10)
  $core.int get timestampMs => $_getIZ(9);
  @$pb.TagNumber(10)
  set timestampMs($core.int v) { $_setUnsignedInt32(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasTimestampMs() => $_has(9);
  @$pb.TagNumber(10)
  void clearTimestampMs() => clearField(10);
}

class KeyframeRequest extends $pb.GeneratedMessage {
  factory KeyframeRequest({
    $core.List<$core.int>? callId,
  }) {
    final $result = create();
    if (callId != null) {
      $result.callId = callId;
    }
    return $result;
  }
  KeyframeRequest._() : super();
  factory KeyframeRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory KeyframeRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'KeyframeRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'callId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  KeyframeRequest clone() => KeyframeRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  KeyframeRequest copyWith(void Function(KeyframeRequest) updates) => super.copyWith((message) => updates(message as KeyframeRequest)) as KeyframeRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static KeyframeRequest create() => KeyframeRequest._();
  KeyframeRequest createEmptyInstance() => create();
  static $pb.PbList<KeyframeRequest> createRepeated() => $pb.PbList<KeyframeRequest>();
  @$core.pragma('dart2js:noInline')
  static KeyframeRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<KeyframeRequest>(create);
  static KeyframeRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get callId => $_getN(0);
  @$pb.TagNumber(1)
  set callId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCallId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCallId() => clearField(1);
}

class GroupCallAudio extends $pb.GeneratedMessage {
  factory GroupCallAudio({
    $core.List<$core.int>? callId,
    $core.List<$core.int>? senderNodeId,
    $core.int? sequenceNumber,
    $core.List<$core.int>? encryptedAudio,
  }) {
    final $result = create();
    if (callId != null) {
      $result.callId = callId;
    }
    if (senderNodeId != null) {
      $result.senderNodeId = senderNodeId;
    }
    if (sequenceNumber != null) {
      $result.sequenceNumber = sequenceNumber;
    }
    if (encryptedAudio != null) {
      $result.encryptedAudio = encryptedAudio;
    }
    return $result;
  }
  GroupCallAudio._() : super();
  factory GroupCallAudio.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GroupCallAudio.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GroupCallAudio', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'callId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'senderNodeId', $pb.PbFieldType.OY)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'sequenceNumber', $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'encryptedAudio', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GroupCallAudio clone() => GroupCallAudio()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GroupCallAudio copyWith(void Function(GroupCallAudio) updates) => super.copyWith((message) => updates(message as GroupCallAudio)) as GroupCallAudio;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GroupCallAudio create() => GroupCallAudio._();
  GroupCallAudio createEmptyInstance() => create();
  static $pb.PbList<GroupCallAudio> createRepeated() => $pb.PbList<GroupCallAudio>();
  @$core.pragma('dart2js:noInline')
  static GroupCallAudio getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GroupCallAudio>(create);
  static GroupCallAudio? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get callId => $_getN(0);
  @$pb.TagNumber(1)
  set callId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCallId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCallId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get senderNodeId => $_getN(1);
  @$pb.TagNumber(2)
  set senderNodeId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSenderNodeId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSenderNodeId() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get sequenceNumber => $_getIZ(2);
  @$pb.TagNumber(3)
  set sequenceNumber($core.int v) { $_setUnsignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSequenceNumber() => $_has(2);
  @$pb.TagNumber(3)
  void clearSequenceNumber() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get encryptedAudio => $_getN(3);
  @$pb.TagNumber(4)
  set encryptedAudio($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasEncryptedAudio() => $_has(3);
  @$pb.TagNumber(4)
  void clearEncryptedAudio() => clearField(4);
}

class GroupCallLeave extends $pb.GeneratedMessage {
  factory GroupCallLeave({
    $core.List<$core.int>? callId,
  }) {
    final $result = create();
    if (callId != null) {
      $result.callId = callId;
    }
    return $result;
  }
  GroupCallLeave._() : super();
  factory GroupCallLeave.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GroupCallLeave.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GroupCallLeave', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'callId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GroupCallLeave clone() => GroupCallLeave()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GroupCallLeave copyWith(void Function(GroupCallLeave) updates) => super.copyWith((message) => updates(message as GroupCallLeave)) as GroupCallLeave;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GroupCallLeave create() => GroupCallLeave._();
  GroupCallLeave createEmptyInstance() => create();
  static $pb.PbList<GroupCallLeave> createRepeated() => $pb.PbList<GroupCallLeave>();
  @$core.pragma('dart2js:noInline')
  static GroupCallLeave getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GroupCallLeave>(create);
  static GroupCallLeave? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get callId => $_getN(0);
  @$pb.TagNumber(1)
  set callId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCallId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCallId() => clearField(1);
}

class GroupCallKeyRotate extends $pb.GeneratedMessage {
  factory GroupCallKeyRotate({
    $core.List<$core.int>? callId,
    $core.List<$core.int>? newCallKey,
    $core.int? keyVersion,
  }) {
    final $result = create();
    if (callId != null) {
      $result.callId = callId;
    }
    if (newCallKey != null) {
      $result.newCallKey = newCallKey;
    }
    if (keyVersion != null) {
      $result.keyVersion = keyVersion;
    }
    return $result;
  }
  GroupCallKeyRotate._() : super();
  factory GroupCallKeyRotate.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GroupCallKeyRotate.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GroupCallKeyRotate', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'callId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'newCallKey', $pb.PbFieldType.OY)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'keyVersion', $pb.PbFieldType.OU3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GroupCallKeyRotate clone() => GroupCallKeyRotate()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GroupCallKeyRotate copyWith(void Function(GroupCallKeyRotate) updates) => super.copyWith((message) => updates(message as GroupCallKeyRotate)) as GroupCallKeyRotate;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GroupCallKeyRotate create() => GroupCallKeyRotate._();
  GroupCallKeyRotate createEmptyInstance() => create();
  static $pb.PbList<GroupCallKeyRotate> createRepeated() => $pb.PbList<GroupCallKeyRotate>();
  @$core.pragma('dart2js:noInline')
  static GroupCallKeyRotate getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GroupCallKeyRotate>(create);
  static GroupCallKeyRotate? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get callId => $_getN(0);
  @$pb.TagNumber(1)
  set callId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCallId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCallId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get newCallKey => $_getN(1);
  @$pb.TagNumber(2)
  set newCallKey($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasNewCallKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearNewCallKey() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get keyVersion => $_getIZ(2);
  @$pb.TagNumber(3)
  set keyVersion($core.int v) { $_setUnsignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasKeyVersion() => $_has(2);
  @$pb.TagNumber(3)
  void clearKeyVersion() => clearField(3);
}

class GroupCallVideo extends $pb.GeneratedMessage {
  factory GroupCallVideo({
    $core.List<$core.int>? callId,
    $core.List<$core.int>? senderNodeId,
    $core.List<$core.int>? videoFrameData,
  }) {
    final $result = create();
    if (callId != null) {
      $result.callId = callId;
    }
    if (senderNodeId != null) {
      $result.senderNodeId = senderNodeId;
    }
    if (videoFrameData != null) {
      $result.videoFrameData = videoFrameData;
    }
    return $result;
  }
  GroupCallVideo._() : super();
  factory GroupCallVideo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GroupCallVideo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GroupCallVideo', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'callId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'senderNodeId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'videoFrameData', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GroupCallVideo clone() => GroupCallVideo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GroupCallVideo copyWith(void Function(GroupCallVideo) updates) => super.copyWith((message) => updates(message as GroupCallVideo)) as GroupCallVideo;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GroupCallVideo create() => GroupCallVideo._();
  GroupCallVideo createEmptyInstance() => create();
  static $pb.PbList<GroupCallVideo> createRepeated() => $pb.PbList<GroupCallVideo>();
  @$core.pragma('dart2js:noInline')
  static GroupCallVideo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GroupCallVideo>(create);
  static GroupCallVideo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get callId => $_getN(0);
  @$pb.TagNumber(1)
  set callId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCallId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCallId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get senderNodeId => $_getN(1);
  @$pb.TagNumber(2)
  set senderNodeId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSenderNodeId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSenderNodeId() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get videoFrameData => $_getN(2);
  @$pb.TagNumber(3)
  set videoFrameData($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasVideoFrameData() => $_has(2);
  @$pb.TagNumber(3)
  void clearVideoFrameData() => clearField(3);
}

class VoicePayload extends $pb.GeneratedMessage {
  factory VoicePayload({
    $core.List<$core.int>? audioData,
    $core.String? transcriptText,
    $core.String? transcriptLanguage,
    $core.double? transcriptConfidence,
  }) {
    final $result = create();
    if (audioData != null) {
      $result.audioData = audioData;
    }
    if (transcriptText != null) {
      $result.transcriptText = transcriptText;
    }
    if (transcriptLanguage != null) {
      $result.transcriptLanguage = transcriptLanguage;
    }
    if (transcriptConfidence != null) {
      $result.transcriptConfidence = transcriptConfidence;
    }
    return $result;
  }
  VoicePayload._() : super();
  factory VoicePayload.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VoicePayload.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'VoicePayload', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'audioData', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'transcriptText')
    ..aOS(3, _omitFieldNames ? '' : 'transcriptLanguage')
    ..a<$core.double>(4, _omitFieldNames ? '' : 'transcriptConfidence', $pb.PbFieldType.OF)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VoicePayload clone() => VoicePayload()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VoicePayload copyWith(void Function(VoicePayload) updates) => super.copyWith((message) => updates(message as VoicePayload)) as VoicePayload;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VoicePayload create() => VoicePayload._();
  VoicePayload createEmptyInstance() => create();
  static $pb.PbList<VoicePayload> createRepeated() => $pb.PbList<VoicePayload>();
  @$core.pragma('dart2js:noInline')
  static VoicePayload getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VoicePayload>(create);
  static VoicePayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get audioData => $_getN(0);
  @$pb.TagNumber(1)
  set audioData($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAudioData() => $_has(0);
  @$pb.TagNumber(1)
  void clearAudioData() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get transcriptText => $_getSZ(1);
  @$pb.TagNumber(2)
  set transcriptText($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTranscriptText() => $_has(1);
  @$pb.TagNumber(2)
  void clearTranscriptText() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get transcriptLanguage => $_getSZ(2);
  @$pb.TagNumber(3)
  set transcriptLanguage($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTranscriptLanguage() => $_has(2);
  @$pb.TagNumber(3)
  void clearTranscriptLanguage() => clearField(3);

  @$pb.TagNumber(4)
  $core.double get transcriptConfidence => $_getN(3);
  @$pb.TagNumber(4)
  set transcriptConfidence($core.double v) { $_setFloat(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTranscriptConfidence() => $_has(3);
  @$pb.TagNumber(4)
  void clearTranscriptConfidence() => clearField(4);
}

class TwinSyncEnvelope extends $pb.GeneratedMessage {
  factory TwinSyncEnvelope({
    $core.List<$core.int>? syncId,
    $core.List<$core.int>? deviceId,
    $fixnum.Int64? timestamp,
    TwinSyncType? syncType,
    $core.List<$core.int>? payload,
  }) {
    final $result = create();
    if (syncId != null) {
      $result.syncId = syncId;
    }
    if (deviceId != null) {
      $result.deviceId = deviceId;
    }
    if (timestamp != null) {
      $result.timestamp = timestamp;
    }
    if (syncType != null) {
      $result.syncType = syncType;
    }
    if (payload != null) {
      $result.payload = payload;
    }
    return $result;
  }
  TwinSyncEnvelope._() : super();
  factory TwinSyncEnvelope.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TwinSyncEnvelope.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TwinSyncEnvelope', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'syncId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'deviceId', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(3, _omitFieldNames ? '' : 'timestamp', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..e<TwinSyncType>(4, _omitFieldNames ? '' : 'syncType', $pb.PbFieldType.OE, defaultOrMaker: TwinSyncType.CONTACT_ADDED, valueOf: TwinSyncType.valueOf, enumValues: TwinSyncType.values)
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'payload', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TwinSyncEnvelope clone() => TwinSyncEnvelope()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TwinSyncEnvelope copyWith(void Function(TwinSyncEnvelope) updates) => super.copyWith((message) => updates(message as TwinSyncEnvelope)) as TwinSyncEnvelope;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TwinSyncEnvelope create() => TwinSyncEnvelope._();
  TwinSyncEnvelope createEmptyInstance() => create();
  static $pb.PbList<TwinSyncEnvelope> createRepeated() => $pb.PbList<TwinSyncEnvelope>();
  @$core.pragma('dart2js:noInline')
  static TwinSyncEnvelope getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TwinSyncEnvelope>(create);
  static TwinSyncEnvelope? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get syncId => $_getN(0);
  @$pb.TagNumber(1)
  set syncId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSyncId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSyncId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get deviceId => $_getN(1);
  @$pb.TagNumber(2)
  set deviceId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDeviceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeviceId() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get timestamp => $_getI64(2);
  @$pb.TagNumber(3)
  set timestamp($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTimestamp() => $_has(2);
  @$pb.TagNumber(3)
  void clearTimestamp() => clearField(3);

  @$pb.TagNumber(4)
  TwinSyncType get syncType => $_getN(3);
  @$pb.TagNumber(4)
  set syncType(TwinSyncType v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasSyncType() => $_has(3);
  @$pb.TagNumber(4)
  void clearSyncType() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get payload => $_getN(4);
  @$pb.TagNumber(5)
  set payload($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasPayload() => $_has(4);
  @$pb.TagNumber(5)
  void clearPayload() => clearField(5);
}

class DeviceRecord extends $pb.GeneratedMessage {
  factory DeviceRecord({
    $core.List<$core.int>? deviceId,
    $core.String? deviceName,
    DevicePlatform? platform,
    $fixnum.Int64? firstSeen,
    $fixnum.Int64? lastSeen,
    $core.Iterable<PeerAddressProto>? addresses,
    $core.bool? isThisDevice,
    $core.List<$core.int>? deviceNodeId,
  }) {
    final $result = create();
    if (deviceId != null) {
      $result.deviceId = deviceId;
    }
    if (deviceName != null) {
      $result.deviceName = deviceName;
    }
    if (platform != null) {
      $result.platform = platform;
    }
    if (firstSeen != null) {
      $result.firstSeen = firstSeen;
    }
    if (lastSeen != null) {
      $result.lastSeen = lastSeen;
    }
    if (addresses != null) {
      $result.addresses.addAll(addresses);
    }
    if (isThisDevice != null) {
      $result.isThisDevice = isThisDevice;
    }
    if (deviceNodeId != null) {
      $result.deviceNodeId = deviceNodeId;
    }
    return $result;
  }
  DeviceRecord._() : super();
  factory DeviceRecord.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DeviceRecord.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DeviceRecord', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'deviceId', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'deviceName')
    ..e<DevicePlatform>(3, _omitFieldNames ? '' : 'platform', $pb.PbFieldType.OE, defaultOrMaker: DevicePlatform.PLATFORM_UNKNOWN, valueOf: DevicePlatform.valueOf, enumValues: DevicePlatform.values)
    ..a<$fixnum.Int64>(4, _omitFieldNames ? '' : 'firstSeen', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(5, _omitFieldNames ? '' : 'lastSeen', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..pc<PeerAddressProto>(6, _omitFieldNames ? '' : 'addresses', $pb.PbFieldType.PM, subBuilder: PeerAddressProto.create)
    ..aOB(7, _omitFieldNames ? '' : 'isThisDevice')
    ..a<$core.List<$core.int>>(8, _omitFieldNames ? '' : 'deviceNodeId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DeviceRecord clone() => DeviceRecord()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DeviceRecord copyWith(void Function(DeviceRecord) updates) => super.copyWith((message) => updates(message as DeviceRecord)) as DeviceRecord;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeviceRecord create() => DeviceRecord._();
  DeviceRecord createEmptyInstance() => create();
  static $pb.PbList<DeviceRecord> createRepeated() => $pb.PbList<DeviceRecord>();
  @$core.pragma('dart2js:noInline')
  static DeviceRecord getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DeviceRecord>(create);
  static DeviceRecord? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get deviceId => $_getN(0);
  @$pb.TagNumber(1)
  set deviceId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasDeviceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get deviceName => $_getSZ(1);
  @$pb.TagNumber(2)
  set deviceName($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDeviceName() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeviceName() => clearField(2);

  @$pb.TagNumber(3)
  DevicePlatform get platform => $_getN(2);
  @$pb.TagNumber(3)
  set platform(DevicePlatform v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasPlatform() => $_has(2);
  @$pb.TagNumber(3)
  void clearPlatform() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get firstSeen => $_getI64(3);
  @$pb.TagNumber(4)
  set firstSeen($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasFirstSeen() => $_has(3);
  @$pb.TagNumber(4)
  void clearFirstSeen() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get lastSeen => $_getI64(4);
  @$pb.TagNumber(5)
  set lastSeen($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasLastSeen() => $_has(4);
  @$pb.TagNumber(5)
  void clearLastSeen() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<PeerAddressProto> get addresses => $_getList(5);

  @$pb.TagNumber(7)
  $core.bool get isThisDevice => $_getBF(6);
  @$pb.TagNumber(7)
  set isThisDevice($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasIsThisDevice() => $_has(6);
  @$pb.TagNumber(7)
  void clearIsThisDevice() => clearField(7);

  @$pb.TagNumber(8)
  $core.List<$core.int> get deviceNodeId => $_getN(7);
  @$pb.TagNumber(8)
  set deviceNodeId($core.List<$core.int> v) { $_setBytes(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasDeviceNodeId() => $_has(7);
  @$pb.TagNumber(8)
  void clearDeviceNodeId() => clearField(8);
}

class KeyRotationBroadcast extends $pb.GeneratedMessage {
  factory KeyRotationBroadcast({
    $core.List<$core.int>? newEd25519Pk,
    $core.List<$core.int>? newMlDsaPk,
    $core.List<$core.int>? newX25519Pk,
    $core.List<$core.int>? newMlKemPk,
    $core.List<$core.int>? oldSignatureEd25519,
    $core.List<$core.int>? newSignatureEd25519,
  }) {
    final $result = create();
    if (newEd25519Pk != null) {
      $result.newEd25519Pk = newEd25519Pk;
    }
    if (newMlDsaPk != null) {
      $result.newMlDsaPk = newMlDsaPk;
    }
    if (newX25519Pk != null) {
      $result.newX25519Pk = newX25519Pk;
    }
    if (newMlKemPk != null) {
      $result.newMlKemPk = newMlKemPk;
    }
    if (oldSignatureEd25519 != null) {
      $result.oldSignatureEd25519 = oldSignatureEd25519;
    }
    if (newSignatureEd25519 != null) {
      $result.newSignatureEd25519 = newSignatureEd25519;
    }
    return $result;
  }
  KeyRotationBroadcast._() : super();
  factory KeyRotationBroadcast.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory KeyRotationBroadcast.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'KeyRotationBroadcast', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'newEd25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'newMlDsaPk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'newX25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'newMlKemPk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'oldSignatureEd25519', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(6, _omitFieldNames ? '' : 'newSignatureEd25519', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  KeyRotationBroadcast clone() => KeyRotationBroadcast()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  KeyRotationBroadcast copyWith(void Function(KeyRotationBroadcast) updates) => super.copyWith((message) => updates(message as KeyRotationBroadcast)) as KeyRotationBroadcast;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static KeyRotationBroadcast create() => KeyRotationBroadcast._();
  KeyRotationBroadcast createEmptyInstance() => create();
  static $pb.PbList<KeyRotationBroadcast> createRepeated() => $pb.PbList<KeyRotationBroadcast>();
  @$core.pragma('dart2js:noInline')
  static KeyRotationBroadcast getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<KeyRotationBroadcast>(create);
  static KeyRotationBroadcast? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get newEd25519Pk => $_getN(0);
  @$pb.TagNumber(1)
  set newEd25519Pk($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasNewEd25519Pk() => $_has(0);
  @$pb.TagNumber(1)
  void clearNewEd25519Pk() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get newMlDsaPk => $_getN(1);
  @$pb.TagNumber(2)
  set newMlDsaPk($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasNewMlDsaPk() => $_has(1);
  @$pb.TagNumber(2)
  void clearNewMlDsaPk() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get newX25519Pk => $_getN(2);
  @$pb.TagNumber(3)
  set newX25519Pk($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasNewX25519Pk() => $_has(2);
  @$pb.TagNumber(3)
  void clearNewX25519Pk() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get newMlKemPk => $_getN(3);
  @$pb.TagNumber(4)
  set newMlKemPk($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasNewMlKemPk() => $_has(3);
  @$pb.TagNumber(4)
  void clearNewMlKemPk() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get oldSignatureEd25519 => $_getN(4);
  @$pb.TagNumber(5)
  set oldSignatureEd25519($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasOldSignatureEd25519() => $_has(4);
  @$pb.TagNumber(5)
  void clearOldSignatureEd25519() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get newSignatureEd25519 => $_getN(5);
  @$pb.TagNumber(6)
  set newSignatureEd25519($core.List<$core.int> v) { $_setBytes(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasNewSignatureEd25519() => $_has(5);
  @$pb.TagNumber(6)
  void clearNewSignatureEd25519() => clearField(6);
}

class CalendarReminderOffset extends $pb.GeneratedMessage {
  factory CalendarReminderOffset({
    $core.int? minutesBefore,
  }) {
    final $result = create();
    if (minutesBefore != null) {
      $result.minutesBefore = minutesBefore;
    }
    return $result;
  }
  CalendarReminderOffset._() : super();
  factory CalendarReminderOffset.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CalendarReminderOffset.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CalendarReminderOffset', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'minutesBefore', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CalendarReminderOffset clone() => CalendarReminderOffset()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CalendarReminderOffset copyWith(void Function(CalendarReminderOffset) updates) => super.copyWith((message) => updates(message as CalendarReminderOffset)) as CalendarReminderOffset;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CalendarReminderOffset create() => CalendarReminderOffset._();
  CalendarReminderOffset createEmptyInstance() => create();
  static $pb.PbList<CalendarReminderOffset> createRepeated() => $pb.PbList<CalendarReminderOffset>();
  @$core.pragma('dart2js:noInline')
  static CalendarReminderOffset getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CalendarReminderOffset>(create);
  static CalendarReminderOffset? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get minutesBefore => $_getIZ(0);
  @$pb.TagNumber(1)
  set minutesBefore($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMinutesBefore() => $_has(0);
  @$pb.TagNumber(1)
  void clearMinutesBefore() => clearField(1);
}

class CalendarInviteMsg extends $pb.GeneratedMessage {
  factory CalendarInviteMsg({
    $core.List<$core.int>? eventId,
    $core.String? title,
    $core.String? description,
    $core.String? location,
    $fixnum.Int64? startTime,
    $fixnum.Int64? endTime,
    $core.bool? allDay,
    $core.String? timeZone,
    $core.String? recurrenceRule,
    $core.bool? hasCall,
    $core.List<$core.int>? groupId,
    $core.List<$core.int>? createdBy,
    $core.String? createdByName,
    $fixnum.Int64? rsvpDeadline,
    EventCategory? category,
    $core.Iterable<CalendarReminderOffset>? reminders,
  }) {
    final $result = create();
    if (eventId != null) {
      $result.eventId = eventId;
    }
    if (title != null) {
      $result.title = title;
    }
    if (description != null) {
      $result.description = description;
    }
    if (location != null) {
      $result.location = location;
    }
    if (startTime != null) {
      $result.startTime = startTime;
    }
    if (endTime != null) {
      $result.endTime = endTime;
    }
    if (allDay != null) {
      $result.allDay = allDay;
    }
    if (timeZone != null) {
      $result.timeZone = timeZone;
    }
    if (recurrenceRule != null) {
      $result.recurrenceRule = recurrenceRule;
    }
    if (hasCall != null) {
      $result.hasCall = hasCall;
    }
    if (groupId != null) {
      $result.groupId = groupId;
    }
    if (createdBy != null) {
      $result.createdBy = createdBy;
    }
    if (createdByName != null) {
      $result.createdByName = createdByName;
    }
    if (rsvpDeadline != null) {
      $result.rsvpDeadline = rsvpDeadline;
    }
    if (category != null) {
      $result.category = category;
    }
    if (reminders != null) {
      $result.reminders.addAll(reminders);
    }
    return $result;
  }
  CalendarInviteMsg._() : super();
  factory CalendarInviteMsg.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CalendarInviteMsg.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CalendarInviteMsg', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'eventId', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'title')
    ..aOS(3, _omitFieldNames ? '' : 'description')
    ..aOS(4, _omitFieldNames ? '' : 'location')
    ..aInt64(5, _omitFieldNames ? '' : 'startTime')
    ..aInt64(6, _omitFieldNames ? '' : 'endTime')
    ..aOB(7, _omitFieldNames ? '' : 'allDay')
    ..aOS(8, _omitFieldNames ? '' : 'timeZone')
    ..aOS(9, _omitFieldNames ? '' : 'recurrenceRule')
    ..aOB(10, _omitFieldNames ? '' : 'hasCall')
    ..a<$core.List<$core.int>>(11, _omitFieldNames ? '' : 'groupId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(12, _omitFieldNames ? '' : 'createdBy', $pb.PbFieldType.OY)
    ..aOS(13, _omitFieldNames ? '' : 'createdByName')
    ..aInt64(14, _omitFieldNames ? '' : 'rsvpDeadline')
    ..e<EventCategory>(15, _omitFieldNames ? '' : 'category', $pb.PbFieldType.OE, defaultOrMaker: EventCategory.APPOINTMENT, valueOf: EventCategory.valueOf, enumValues: EventCategory.values)
    ..pc<CalendarReminderOffset>(16, _omitFieldNames ? '' : 'reminders', $pb.PbFieldType.PM, subBuilder: CalendarReminderOffset.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CalendarInviteMsg clone() => CalendarInviteMsg()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CalendarInviteMsg copyWith(void Function(CalendarInviteMsg) updates) => super.copyWith((message) => updates(message as CalendarInviteMsg)) as CalendarInviteMsg;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CalendarInviteMsg create() => CalendarInviteMsg._();
  CalendarInviteMsg createEmptyInstance() => create();
  static $pb.PbList<CalendarInviteMsg> createRepeated() => $pb.PbList<CalendarInviteMsg>();
  @$core.pragma('dart2js:noInline')
  static CalendarInviteMsg getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CalendarInviteMsg>(create);
  static CalendarInviteMsg? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get eventId => $_getN(0);
  @$pb.TagNumber(1)
  set eventId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasEventId() => $_has(0);
  @$pb.TagNumber(1)
  void clearEventId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get title => $_getSZ(1);
  @$pb.TagNumber(2)
  set title($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTitle() => $_has(1);
  @$pb.TagNumber(2)
  void clearTitle() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get description => $_getSZ(2);
  @$pb.TagNumber(3)
  set description($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDescription() => $_has(2);
  @$pb.TagNumber(3)
  void clearDescription() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get location => $_getSZ(3);
  @$pb.TagNumber(4)
  set location($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasLocation() => $_has(3);
  @$pb.TagNumber(4)
  void clearLocation() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get startTime => $_getI64(4);
  @$pb.TagNumber(5)
  set startTime($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasStartTime() => $_has(4);
  @$pb.TagNumber(5)
  void clearStartTime() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get endTime => $_getI64(5);
  @$pb.TagNumber(6)
  set endTime($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasEndTime() => $_has(5);
  @$pb.TagNumber(6)
  void clearEndTime() => clearField(6);

  @$pb.TagNumber(7)
  $core.bool get allDay => $_getBF(6);
  @$pb.TagNumber(7)
  set allDay($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasAllDay() => $_has(6);
  @$pb.TagNumber(7)
  void clearAllDay() => clearField(7);

  @$pb.TagNumber(8)
  $core.String get timeZone => $_getSZ(7);
  @$pb.TagNumber(8)
  set timeZone($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasTimeZone() => $_has(7);
  @$pb.TagNumber(8)
  void clearTimeZone() => clearField(8);

  @$pb.TagNumber(9)
  $core.String get recurrenceRule => $_getSZ(8);
  @$pb.TagNumber(9)
  set recurrenceRule($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasRecurrenceRule() => $_has(8);
  @$pb.TagNumber(9)
  void clearRecurrenceRule() => clearField(9);

  @$pb.TagNumber(10)
  $core.bool get hasCall => $_getBF(9);
  @$pb.TagNumber(10)
  set hasCall($core.bool v) { $_setBool(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasHasCall() => $_has(9);
  @$pb.TagNumber(10)
  void clearHasCall() => clearField(10);

  @$pb.TagNumber(11)
  $core.List<$core.int> get groupId => $_getN(10);
  @$pb.TagNumber(11)
  set groupId($core.List<$core.int> v) { $_setBytes(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasGroupId() => $_has(10);
  @$pb.TagNumber(11)
  void clearGroupId() => clearField(11);

  @$pb.TagNumber(12)
  $core.List<$core.int> get createdBy => $_getN(11);
  @$pb.TagNumber(12)
  set createdBy($core.List<$core.int> v) { $_setBytes(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasCreatedBy() => $_has(11);
  @$pb.TagNumber(12)
  void clearCreatedBy() => clearField(12);

  @$pb.TagNumber(13)
  $core.String get createdByName => $_getSZ(12);
  @$pb.TagNumber(13)
  set createdByName($core.String v) { $_setString(12, v); }
  @$pb.TagNumber(13)
  $core.bool hasCreatedByName() => $_has(12);
  @$pb.TagNumber(13)
  void clearCreatedByName() => clearField(13);

  @$pb.TagNumber(14)
  $fixnum.Int64 get rsvpDeadline => $_getI64(13);
  @$pb.TagNumber(14)
  set rsvpDeadline($fixnum.Int64 v) { $_setInt64(13, v); }
  @$pb.TagNumber(14)
  $core.bool hasRsvpDeadline() => $_has(13);
  @$pb.TagNumber(14)
  void clearRsvpDeadline() => clearField(14);

  @$pb.TagNumber(15)
  EventCategory get category => $_getN(14);
  @$pb.TagNumber(15)
  set category(EventCategory v) { setField(15, v); }
  @$pb.TagNumber(15)
  $core.bool hasCategory() => $_has(14);
  @$pb.TagNumber(15)
  void clearCategory() => clearField(15);

  @$pb.TagNumber(16)
  $core.List<CalendarReminderOffset> get reminders => $_getList(15);
}

class CalendarRsvpMsg extends $pb.GeneratedMessage {
  factory CalendarRsvpMsg({
    $core.List<$core.int>? eventId,
    RsvpStatus? response,
    $fixnum.Int64? proposedStart,
    $fixnum.Int64? proposedEnd,
    $core.String? comment,
  }) {
    final $result = create();
    if (eventId != null) {
      $result.eventId = eventId;
    }
    if (response != null) {
      $result.response = response;
    }
    if (proposedStart != null) {
      $result.proposedStart = proposedStart;
    }
    if (proposedEnd != null) {
      $result.proposedEnd = proposedEnd;
    }
    if (comment != null) {
      $result.comment = comment;
    }
    return $result;
  }
  CalendarRsvpMsg._() : super();
  factory CalendarRsvpMsg.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CalendarRsvpMsg.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CalendarRsvpMsg', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'eventId', $pb.PbFieldType.OY)
    ..e<RsvpStatus>(2, _omitFieldNames ? '' : 'response', $pb.PbFieldType.OE, defaultOrMaker: RsvpStatus.RSVP_ACCEPTED, valueOf: RsvpStatus.valueOf, enumValues: RsvpStatus.values)
    ..aInt64(3, _omitFieldNames ? '' : 'proposedStart')
    ..aInt64(4, _omitFieldNames ? '' : 'proposedEnd')
    ..aOS(5, _omitFieldNames ? '' : 'comment')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CalendarRsvpMsg clone() => CalendarRsvpMsg()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CalendarRsvpMsg copyWith(void Function(CalendarRsvpMsg) updates) => super.copyWith((message) => updates(message as CalendarRsvpMsg)) as CalendarRsvpMsg;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CalendarRsvpMsg create() => CalendarRsvpMsg._();
  CalendarRsvpMsg createEmptyInstance() => create();
  static $pb.PbList<CalendarRsvpMsg> createRepeated() => $pb.PbList<CalendarRsvpMsg>();
  @$core.pragma('dart2js:noInline')
  static CalendarRsvpMsg getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CalendarRsvpMsg>(create);
  static CalendarRsvpMsg? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get eventId => $_getN(0);
  @$pb.TagNumber(1)
  set eventId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasEventId() => $_has(0);
  @$pb.TagNumber(1)
  void clearEventId() => clearField(1);

  @$pb.TagNumber(2)
  RsvpStatus get response => $_getN(1);
  @$pb.TagNumber(2)
  set response(RsvpStatus v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasResponse() => $_has(1);
  @$pb.TagNumber(2)
  void clearResponse() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get proposedStart => $_getI64(2);
  @$pb.TagNumber(3)
  set proposedStart($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasProposedStart() => $_has(2);
  @$pb.TagNumber(3)
  void clearProposedStart() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get proposedEnd => $_getI64(3);
  @$pb.TagNumber(4)
  set proposedEnd($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasProposedEnd() => $_has(3);
  @$pb.TagNumber(4)
  void clearProposedEnd() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get comment => $_getSZ(4);
  @$pb.TagNumber(5)
  set comment($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasComment() => $_has(4);
  @$pb.TagNumber(5)
  void clearComment() => clearField(5);
}

class CalendarUpdateMsg extends $pb.GeneratedMessage {
  factory CalendarUpdateMsg({
    $core.List<$core.int>? eventId,
    $core.String? title,
    $core.String? description,
    $core.String? location,
    $fixnum.Int64? startTime,
    $fixnum.Int64? endTime,
    $core.bool? allDay,
    $core.String? timeZone,
    $core.String? recurrenceRule,
    $core.bool? hasCall,
    $core.bool? cancelled,
    $fixnum.Int64? updatedAt,
    $core.Iterable<CalendarReminderOffset>? reminders,
  }) {
    final $result = create();
    if (eventId != null) {
      $result.eventId = eventId;
    }
    if (title != null) {
      $result.title = title;
    }
    if (description != null) {
      $result.description = description;
    }
    if (location != null) {
      $result.location = location;
    }
    if (startTime != null) {
      $result.startTime = startTime;
    }
    if (endTime != null) {
      $result.endTime = endTime;
    }
    if (allDay != null) {
      $result.allDay = allDay;
    }
    if (timeZone != null) {
      $result.timeZone = timeZone;
    }
    if (recurrenceRule != null) {
      $result.recurrenceRule = recurrenceRule;
    }
    if (hasCall != null) {
      $result.hasCall = hasCall;
    }
    if (cancelled != null) {
      $result.cancelled = cancelled;
    }
    if (updatedAt != null) {
      $result.updatedAt = updatedAt;
    }
    if (reminders != null) {
      $result.reminders.addAll(reminders);
    }
    return $result;
  }
  CalendarUpdateMsg._() : super();
  factory CalendarUpdateMsg.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CalendarUpdateMsg.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CalendarUpdateMsg', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'eventId', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'title')
    ..aOS(3, _omitFieldNames ? '' : 'description')
    ..aOS(4, _omitFieldNames ? '' : 'location')
    ..aInt64(5, _omitFieldNames ? '' : 'startTime')
    ..aInt64(6, _omitFieldNames ? '' : 'endTime')
    ..aOB(7, _omitFieldNames ? '' : 'allDay')
    ..aOS(8, _omitFieldNames ? '' : 'timeZone')
    ..aOS(9, _omitFieldNames ? '' : 'recurrenceRule')
    ..aOB(10, _omitFieldNames ? '' : 'hasCall')
    ..aOB(11, _omitFieldNames ? '' : 'cancelled')
    ..aInt64(12, _omitFieldNames ? '' : 'updatedAt')
    ..pc<CalendarReminderOffset>(13, _omitFieldNames ? '' : 'reminders', $pb.PbFieldType.PM, subBuilder: CalendarReminderOffset.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CalendarUpdateMsg clone() => CalendarUpdateMsg()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CalendarUpdateMsg copyWith(void Function(CalendarUpdateMsg) updates) => super.copyWith((message) => updates(message as CalendarUpdateMsg)) as CalendarUpdateMsg;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CalendarUpdateMsg create() => CalendarUpdateMsg._();
  CalendarUpdateMsg createEmptyInstance() => create();
  static $pb.PbList<CalendarUpdateMsg> createRepeated() => $pb.PbList<CalendarUpdateMsg>();
  @$core.pragma('dart2js:noInline')
  static CalendarUpdateMsg getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CalendarUpdateMsg>(create);
  static CalendarUpdateMsg? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get eventId => $_getN(0);
  @$pb.TagNumber(1)
  set eventId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasEventId() => $_has(0);
  @$pb.TagNumber(1)
  void clearEventId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get title => $_getSZ(1);
  @$pb.TagNumber(2)
  set title($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTitle() => $_has(1);
  @$pb.TagNumber(2)
  void clearTitle() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get description => $_getSZ(2);
  @$pb.TagNumber(3)
  set description($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDescription() => $_has(2);
  @$pb.TagNumber(3)
  void clearDescription() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get location => $_getSZ(3);
  @$pb.TagNumber(4)
  set location($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasLocation() => $_has(3);
  @$pb.TagNumber(4)
  void clearLocation() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get startTime => $_getI64(4);
  @$pb.TagNumber(5)
  set startTime($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasStartTime() => $_has(4);
  @$pb.TagNumber(5)
  void clearStartTime() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get endTime => $_getI64(5);
  @$pb.TagNumber(6)
  set endTime($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasEndTime() => $_has(5);
  @$pb.TagNumber(6)
  void clearEndTime() => clearField(6);

  @$pb.TagNumber(7)
  $core.bool get allDay => $_getBF(6);
  @$pb.TagNumber(7)
  set allDay($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasAllDay() => $_has(6);
  @$pb.TagNumber(7)
  void clearAllDay() => clearField(7);

  @$pb.TagNumber(8)
  $core.String get timeZone => $_getSZ(7);
  @$pb.TagNumber(8)
  set timeZone($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasTimeZone() => $_has(7);
  @$pb.TagNumber(8)
  void clearTimeZone() => clearField(8);

  @$pb.TagNumber(9)
  $core.String get recurrenceRule => $_getSZ(8);
  @$pb.TagNumber(9)
  set recurrenceRule($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasRecurrenceRule() => $_has(8);
  @$pb.TagNumber(9)
  void clearRecurrenceRule() => clearField(9);

  @$pb.TagNumber(10)
  $core.bool get hasCall => $_getBF(9);
  @$pb.TagNumber(10)
  set hasCall($core.bool v) { $_setBool(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasHasCall() => $_has(9);
  @$pb.TagNumber(10)
  void clearHasCall() => clearField(10);

  @$pb.TagNumber(11)
  $core.bool get cancelled => $_getBF(10);
  @$pb.TagNumber(11)
  set cancelled($core.bool v) { $_setBool(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasCancelled() => $_has(10);
  @$pb.TagNumber(11)
  void clearCancelled() => clearField(11);

  @$pb.TagNumber(12)
  $fixnum.Int64 get updatedAt => $_getI64(11);
  @$pb.TagNumber(12)
  set updatedAt($fixnum.Int64 v) { $_setInt64(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasUpdatedAt() => $_has(11);
  @$pb.TagNumber(12)
  void clearUpdatedAt() => clearField(12);

  @$pb.TagNumber(13)
  $core.List<CalendarReminderOffset> get reminders => $_getList(12);
}

class CalendarDeleteMsg extends $pb.GeneratedMessage {
  factory CalendarDeleteMsg({
    $core.List<$core.int>? eventId,
    $fixnum.Int64? deletedAt,
  }) {
    final $result = create();
    if (eventId != null) {
      $result.eventId = eventId;
    }
    if (deletedAt != null) {
      $result.deletedAt = deletedAt;
    }
    return $result;
  }
  CalendarDeleteMsg._() : super();
  factory CalendarDeleteMsg.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CalendarDeleteMsg.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CalendarDeleteMsg', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'eventId', $pb.PbFieldType.OY)
    ..aInt64(2, _omitFieldNames ? '' : 'deletedAt')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CalendarDeleteMsg clone() => CalendarDeleteMsg()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CalendarDeleteMsg copyWith(void Function(CalendarDeleteMsg) updates) => super.copyWith((message) => updates(message as CalendarDeleteMsg)) as CalendarDeleteMsg;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CalendarDeleteMsg create() => CalendarDeleteMsg._();
  CalendarDeleteMsg createEmptyInstance() => create();
  static $pb.PbList<CalendarDeleteMsg> createRepeated() => $pb.PbList<CalendarDeleteMsg>();
  @$core.pragma('dart2js:noInline')
  static CalendarDeleteMsg getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CalendarDeleteMsg>(create);
  static CalendarDeleteMsg? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get eventId => $_getN(0);
  @$pb.TagNumber(1)
  set eventId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasEventId() => $_has(0);
  @$pb.TagNumber(1)
  void clearEventId() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get deletedAt => $_getI64(1);
  @$pb.TagNumber(2)
  set deletedAt($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDeletedAt() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeletedAt() => clearField(2);
}

class FreeBusyRequestMsg extends $pb.GeneratedMessage {
  factory FreeBusyRequestMsg({
    $fixnum.Int64? queryStart,
    $fixnum.Int64? queryEnd,
    $core.List<$core.int>? requestId,
  }) {
    final $result = create();
    if (queryStart != null) {
      $result.queryStart = queryStart;
    }
    if (queryEnd != null) {
      $result.queryEnd = queryEnd;
    }
    if (requestId != null) {
      $result.requestId = requestId;
    }
    return $result;
  }
  FreeBusyRequestMsg._() : super();
  factory FreeBusyRequestMsg.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory FreeBusyRequestMsg.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FreeBusyRequestMsg', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'queryStart')
    ..aInt64(2, _omitFieldNames ? '' : 'queryEnd')
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'requestId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  FreeBusyRequestMsg clone() => FreeBusyRequestMsg()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  FreeBusyRequestMsg copyWith(void Function(FreeBusyRequestMsg) updates) => super.copyWith((message) => updates(message as FreeBusyRequestMsg)) as FreeBusyRequestMsg;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FreeBusyRequestMsg create() => FreeBusyRequestMsg._();
  FreeBusyRequestMsg createEmptyInstance() => create();
  static $pb.PbList<FreeBusyRequestMsg> createRepeated() => $pb.PbList<FreeBusyRequestMsg>();
  @$core.pragma('dart2js:noInline')
  static FreeBusyRequestMsg getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FreeBusyRequestMsg>(create);
  static FreeBusyRequestMsg? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get queryStart => $_getI64(0);
  @$pb.TagNumber(1)
  set queryStart($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasQueryStart() => $_has(0);
  @$pb.TagNumber(1)
  void clearQueryStart() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get queryEnd => $_getI64(1);
  @$pb.TagNumber(2)
  set queryEnd($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasQueryEnd() => $_has(1);
  @$pb.TagNumber(2)
  void clearQueryEnd() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get requestId => $_getN(2);
  @$pb.TagNumber(3)
  set requestId($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasRequestId() => $_has(2);
  @$pb.TagNumber(3)
  void clearRequestId() => clearField(3);
}

class FreeBusyResponseMsg extends $pb.GeneratedMessage {
  factory FreeBusyResponseMsg({
    $core.List<$core.int>? requestId,
    $core.Iterable<FreeBusyBlock>? blocks,
  }) {
    final $result = create();
    if (requestId != null) {
      $result.requestId = requestId;
    }
    if (blocks != null) {
      $result.blocks.addAll(blocks);
    }
    return $result;
  }
  FreeBusyResponseMsg._() : super();
  factory FreeBusyResponseMsg.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory FreeBusyResponseMsg.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FreeBusyResponseMsg', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'requestId', $pb.PbFieldType.OY)
    ..pc<FreeBusyBlock>(2, _omitFieldNames ? '' : 'blocks', $pb.PbFieldType.PM, subBuilder: FreeBusyBlock.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  FreeBusyResponseMsg clone() => FreeBusyResponseMsg()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  FreeBusyResponseMsg copyWith(void Function(FreeBusyResponseMsg) updates) => super.copyWith((message) => updates(message as FreeBusyResponseMsg)) as FreeBusyResponseMsg;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FreeBusyResponseMsg create() => FreeBusyResponseMsg._();
  FreeBusyResponseMsg createEmptyInstance() => create();
  static $pb.PbList<FreeBusyResponseMsg> createRepeated() => $pb.PbList<FreeBusyResponseMsg>();
  @$core.pragma('dart2js:noInline')
  static FreeBusyResponseMsg getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FreeBusyResponseMsg>(create);
  static FreeBusyResponseMsg? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get requestId => $_getN(0);
  @$pb.TagNumber(1)
  set requestId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<FreeBusyBlock> get blocks => $_getList(1);
}

class FreeBusyBlock extends $pb.GeneratedMessage {
  factory FreeBusyBlock({
    $fixnum.Int64? start,
    $fixnum.Int64? end,
    FreeBusyLevel? level,
    $core.String? title,
    $core.String? location,
  }) {
    final $result = create();
    if (start != null) {
      $result.start = start;
    }
    if (end != null) {
      $result.end = end;
    }
    if (level != null) {
      $result.level = level;
    }
    if (title != null) {
      $result.title = title;
    }
    if (location != null) {
      $result.location = location;
    }
    return $result;
  }
  FreeBusyBlock._() : super();
  factory FreeBusyBlock.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory FreeBusyBlock.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FreeBusyBlock', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'start')
    ..aInt64(2, _omitFieldNames ? '' : 'end')
    ..e<FreeBusyLevel>(3, _omitFieldNames ? '' : 'level', $pb.PbFieldType.OE, defaultOrMaker: FreeBusyLevel.FB_FULL, valueOf: FreeBusyLevel.valueOf, enumValues: FreeBusyLevel.values)
    ..aOS(4, _omitFieldNames ? '' : 'title')
    ..aOS(5, _omitFieldNames ? '' : 'location')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  FreeBusyBlock clone() => FreeBusyBlock()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  FreeBusyBlock copyWith(void Function(FreeBusyBlock) updates) => super.copyWith((message) => updates(message as FreeBusyBlock)) as FreeBusyBlock;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FreeBusyBlock create() => FreeBusyBlock._();
  FreeBusyBlock createEmptyInstance() => create();
  static $pb.PbList<FreeBusyBlock> createRepeated() => $pb.PbList<FreeBusyBlock>();
  @$core.pragma('dart2js:noInline')
  static FreeBusyBlock getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FreeBusyBlock>(create);
  static FreeBusyBlock? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get start => $_getI64(0);
  @$pb.TagNumber(1)
  set start($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasStart() => $_has(0);
  @$pb.TagNumber(1)
  void clearStart() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get end => $_getI64(1);
  @$pb.TagNumber(2)
  set end($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasEnd() => $_has(1);
  @$pb.TagNumber(2)
  void clearEnd() => clearField(2);

  @$pb.TagNumber(3)
  FreeBusyLevel get level => $_getN(2);
  @$pb.TagNumber(3)
  set level(FreeBusyLevel v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasLevel() => $_has(2);
  @$pb.TagNumber(3)
  void clearLevel() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get title => $_getSZ(3);
  @$pb.TagNumber(4)
  set title($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTitle() => $_has(3);
  @$pb.TagNumber(4)
  void clearTitle() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get location => $_getSZ(4);
  @$pb.TagNumber(5)
  set location($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasLocation() => $_has(4);
  @$pb.TagNumber(5)
  void clearLocation() => clearField(5);
}

class PollOptionMsg extends $pb.GeneratedMessage {
  factory PollOptionMsg({
    $core.int? optionId,
    $core.String? label,
    $fixnum.Int64? dateStart,
    $fixnum.Int64? dateEnd,
  }) {
    final $result = create();
    if (optionId != null) {
      $result.optionId = optionId;
    }
    if (label != null) {
      $result.label = label;
    }
    if (dateStart != null) {
      $result.dateStart = dateStart;
    }
    if (dateEnd != null) {
      $result.dateEnd = dateEnd;
    }
    return $result;
  }
  PollOptionMsg._() : super();
  factory PollOptionMsg.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PollOptionMsg.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PollOptionMsg', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'optionId', $pb.PbFieldType.O3)
    ..aOS(2, _omitFieldNames ? '' : 'label')
    ..aInt64(3, _omitFieldNames ? '' : 'dateStart')
    ..aInt64(4, _omitFieldNames ? '' : 'dateEnd')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PollOptionMsg clone() => PollOptionMsg()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PollOptionMsg copyWith(void Function(PollOptionMsg) updates) => super.copyWith((message) => updates(message as PollOptionMsg)) as PollOptionMsg;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PollOptionMsg create() => PollOptionMsg._();
  PollOptionMsg createEmptyInstance() => create();
  static $pb.PbList<PollOptionMsg> createRepeated() => $pb.PbList<PollOptionMsg>();
  @$core.pragma('dart2js:noInline')
  static PollOptionMsg getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PollOptionMsg>(create);
  static PollOptionMsg? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get optionId => $_getIZ(0);
  @$pb.TagNumber(1)
  set optionId($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasOptionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOptionId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get label => $_getSZ(1);
  @$pb.TagNumber(2)
  set label($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasLabel() => $_has(1);
  @$pb.TagNumber(2)
  void clearLabel() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get dateStart => $_getI64(2);
  @$pb.TagNumber(3)
  set dateStart($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDateStart() => $_has(2);
  @$pb.TagNumber(3)
  void clearDateStart() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get dateEnd => $_getI64(3);
  @$pb.TagNumber(4)
  set dateEnd($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasDateEnd() => $_has(3);
  @$pb.TagNumber(4)
  void clearDateEnd() => clearField(4);
}

class PollSettingsMsg extends $pb.GeneratedMessage {
  factory PollSettingsMsg({
    $core.bool? anonymous,
    $fixnum.Int64? deadline,
    $core.bool? allowVoteChange,
    $core.bool? showResultsBeforeClose,
    $core.int? maxChoices,
    $core.int? scaleMin,
    $core.int? scaleMax,
    $core.bool? onlyMembersCanVote,
  }) {
    final $result = create();
    if (anonymous != null) {
      $result.anonymous = anonymous;
    }
    if (deadline != null) {
      $result.deadline = deadline;
    }
    if (allowVoteChange != null) {
      $result.allowVoteChange = allowVoteChange;
    }
    if (showResultsBeforeClose != null) {
      $result.showResultsBeforeClose = showResultsBeforeClose;
    }
    if (maxChoices != null) {
      $result.maxChoices = maxChoices;
    }
    if (scaleMin != null) {
      $result.scaleMin = scaleMin;
    }
    if (scaleMax != null) {
      $result.scaleMax = scaleMax;
    }
    if (onlyMembersCanVote != null) {
      $result.onlyMembersCanVote = onlyMembersCanVote;
    }
    return $result;
  }
  PollSettingsMsg._() : super();
  factory PollSettingsMsg.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PollSettingsMsg.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PollSettingsMsg', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'anonymous')
    ..aInt64(2, _omitFieldNames ? '' : 'deadline')
    ..aOB(3, _omitFieldNames ? '' : 'allowVoteChange')
    ..aOB(4, _omitFieldNames ? '' : 'showResultsBeforeClose')
    ..a<$core.int>(5, _omitFieldNames ? '' : 'maxChoices', $pb.PbFieldType.O3)
    ..a<$core.int>(6, _omitFieldNames ? '' : 'scaleMin', $pb.PbFieldType.O3)
    ..a<$core.int>(7, _omitFieldNames ? '' : 'scaleMax', $pb.PbFieldType.O3)
    ..aOB(8, _omitFieldNames ? '' : 'onlyMembersCanVote')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PollSettingsMsg clone() => PollSettingsMsg()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PollSettingsMsg copyWith(void Function(PollSettingsMsg) updates) => super.copyWith((message) => updates(message as PollSettingsMsg)) as PollSettingsMsg;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PollSettingsMsg create() => PollSettingsMsg._();
  PollSettingsMsg createEmptyInstance() => create();
  static $pb.PbList<PollSettingsMsg> createRepeated() => $pb.PbList<PollSettingsMsg>();
  @$core.pragma('dart2js:noInline')
  static PollSettingsMsg getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PollSettingsMsg>(create);
  static PollSettingsMsg? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get anonymous => $_getBF(0);
  @$pb.TagNumber(1)
  set anonymous($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAnonymous() => $_has(0);
  @$pb.TagNumber(1)
  void clearAnonymous() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get deadline => $_getI64(1);
  @$pb.TagNumber(2)
  set deadline($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDeadline() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeadline() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get allowVoteChange => $_getBF(2);
  @$pb.TagNumber(3)
  set allowVoteChange($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAllowVoteChange() => $_has(2);
  @$pb.TagNumber(3)
  void clearAllowVoteChange() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get showResultsBeforeClose => $_getBF(3);
  @$pb.TagNumber(4)
  set showResultsBeforeClose($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasShowResultsBeforeClose() => $_has(3);
  @$pb.TagNumber(4)
  void clearShowResultsBeforeClose() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get maxChoices => $_getIZ(4);
  @$pb.TagNumber(5)
  set maxChoices($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasMaxChoices() => $_has(4);
  @$pb.TagNumber(5)
  void clearMaxChoices() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get scaleMin => $_getIZ(5);
  @$pb.TagNumber(6)
  set scaleMin($core.int v) { $_setSignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasScaleMin() => $_has(5);
  @$pb.TagNumber(6)
  void clearScaleMin() => clearField(6);

  @$pb.TagNumber(7)
  $core.int get scaleMax => $_getIZ(6);
  @$pb.TagNumber(7)
  set scaleMax($core.int v) { $_setSignedInt32(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasScaleMax() => $_has(6);
  @$pb.TagNumber(7)
  void clearScaleMax() => clearField(7);

  @$pb.TagNumber(8)
  $core.bool get onlyMembersCanVote => $_getBF(7);
  @$pb.TagNumber(8)
  set onlyMembersCanVote($core.bool v) { $_setBool(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasOnlyMembersCanVote() => $_has(7);
  @$pb.TagNumber(8)
  void clearOnlyMembersCanVote() => clearField(8);
}

class PollCreateMsg extends $pb.GeneratedMessage {
  factory PollCreateMsg({
    $core.List<$core.int>? pollId,
    $core.String? question,
    $core.String? description,
    PollType? pollType,
    $core.Iterable<PollOptionMsg>? options,
    PollSettingsMsg? settings,
    $core.List<$core.int>? groupId,
    $core.List<$core.int>? createdBy,
    $core.String? createdByName,
    $fixnum.Int64? createdAt,
  }) {
    final $result = create();
    if (pollId != null) {
      $result.pollId = pollId;
    }
    if (question != null) {
      $result.question = question;
    }
    if (description != null) {
      $result.description = description;
    }
    if (pollType != null) {
      $result.pollType = pollType;
    }
    if (options != null) {
      $result.options.addAll(options);
    }
    if (settings != null) {
      $result.settings = settings;
    }
    if (groupId != null) {
      $result.groupId = groupId;
    }
    if (createdBy != null) {
      $result.createdBy = createdBy;
    }
    if (createdByName != null) {
      $result.createdByName = createdByName;
    }
    if (createdAt != null) {
      $result.createdAt = createdAt;
    }
    return $result;
  }
  PollCreateMsg._() : super();
  factory PollCreateMsg.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PollCreateMsg.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PollCreateMsg', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'pollId', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'question')
    ..aOS(3, _omitFieldNames ? '' : 'description')
    ..e<PollType>(4, _omitFieldNames ? '' : 'pollType', $pb.PbFieldType.OE, defaultOrMaker: PollType.POLL_SINGLE_CHOICE, valueOf: PollType.valueOf, enumValues: PollType.values)
    ..pc<PollOptionMsg>(5, _omitFieldNames ? '' : 'options', $pb.PbFieldType.PM, subBuilder: PollOptionMsg.create)
    ..aOM<PollSettingsMsg>(6, _omitFieldNames ? '' : 'settings', subBuilder: PollSettingsMsg.create)
    ..a<$core.List<$core.int>>(7, _omitFieldNames ? '' : 'groupId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(8, _omitFieldNames ? '' : 'createdBy', $pb.PbFieldType.OY)
    ..aOS(9, _omitFieldNames ? '' : 'createdByName')
    ..aInt64(10, _omitFieldNames ? '' : 'createdAt')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PollCreateMsg clone() => PollCreateMsg()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PollCreateMsg copyWith(void Function(PollCreateMsg) updates) => super.copyWith((message) => updates(message as PollCreateMsg)) as PollCreateMsg;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PollCreateMsg create() => PollCreateMsg._();
  PollCreateMsg createEmptyInstance() => create();
  static $pb.PbList<PollCreateMsg> createRepeated() => $pb.PbList<PollCreateMsg>();
  @$core.pragma('dart2js:noInline')
  static PollCreateMsg getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PollCreateMsg>(create);
  static PollCreateMsg? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get pollId => $_getN(0);
  @$pb.TagNumber(1)
  set pollId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPollId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPollId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get question => $_getSZ(1);
  @$pb.TagNumber(2)
  set question($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasQuestion() => $_has(1);
  @$pb.TagNumber(2)
  void clearQuestion() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get description => $_getSZ(2);
  @$pb.TagNumber(3)
  set description($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDescription() => $_has(2);
  @$pb.TagNumber(3)
  void clearDescription() => clearField(3);

  @$pb.TagNumber(4)
  PollType get pollType => $_getN(3);
  @$pb.TagNumber(4)
  set pollType(PollType v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasPollType() => $_has(3);
  @$pb.TagNumber(4)
  void clearPollType() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<PollOptionMsg> get options => $_getList(4);

  @$pb.TagNumber(6)
  PollSettingsMsg get settings => $_getN(5);
  @$pb.TagNumber(6)
  set settings(PollSettingsMsg v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasSettings() => $_has(5);
  @$pb.TagNumber(6)
  void clearSettings() => clearField(6);
  @$pb.TagNumber(6)
  PollSettingsMsg ensureSettings() => $_ensure(5);

  @$pb.TagNumber(7)
  $core.List<$core.int> get groupId => $_getN(6);
  @$pb.TagNumber(7)
  set groupId($core.List<$core.int> v) { $_setBytes(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasGroupId() => $_has(6);
  @$pb.TagNumber(7)
  void clearGroupId() => clearField(7);

  @$pb.TagNumber(8)
  $core.List<$core.int> get createdBy => $_getN(7);
  @$pb.TagNumber(8)
  set createdBy($core.List<$core.int> v) { $_setBytes(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasCreatedBy() => $_has(7);
  @$pb.TagNumber(8)
  void clearCreatedBy() => clearField(8);

  @$pb.TagNumber(9)
  $core.String get createdByName => $_getSZ(8);
  @$pb.TagNumber(9)
  set createdByName($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasCreatedByName() => $_has(8);
  @$pb.TagNumber(9)
  void clearCreatedByName() => clearField(9);

  @$pb.TagNumber(10)
  $fixnum.Int64 get createdAt => $_getI64(9);
  @$pb.TagNumber(10)
  set createdAt($fixnum.Int64 v) { $_setInt64(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasCreatedAt() => $_has(9);
  @$pb.TagNumber(10)
  void clearCreatedAt() => clearField(10);
}

class DateResponseMsg extends $pb.GeneratedMessage {
  factory DateResponseMsg({
    $core.int? optionId,
    DateAvailability? availability,
  }) {
    final $result = create();
    if (optionId != null) {
      $result.optionId = optionId;
    }
    if (availability != null) {
      $result.availability = availability;
    }
    return $result;
  }
  DateResponseMsg._() : super();
  factory DateResponseMsg.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DateResponseMsg.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DateResponseMsg', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'optionId', $pb.PbFieldType.O3)
    ..e<DateAvailability>(2, _omitFieldNames ? '' : 'availability', $pb.PbFieldType.OE, defaultOrMaker: DateAvailability.DATE_AVAIL_YES, valueOf: DateAvailability.valueOf, enumValues: DateAvailability.values)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DateResponseMsg clone() => DateResponseMsg()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DateResponseMsg copyWith(void Function(DateResponseMsg) updates) => super.copyWith((message) => updates(message as DateResponseMsg)) as DateResponseMsg;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DateResponseMsg create() => DateResponseMsg._();
  DateResponseMsg createEmptyInstance() => create();
  static $pb.PbList<DateResponseMsg> createRepeated() => $pb.PbList<DateResponseMsg>();
  @$core.pragma('dart2js:noInline')
  static DateResponseMsg getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DateResponseMsg>(create);
  static DateResponseMsg? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get optionId => $_getIZ(0);
  @$pb.TagNumber(1)
  set optionId($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasOptionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOptionId() => clearField(1);

  @$pb.TagNumber(2)
  DateAvailability get availability => $_getN(1);
  @$pb.TagNumber(2)
  set availability(DateAvailability v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasAvailability() => $_has(1);
  @$pb.TagNumber(2)
  void clearAvailability() => clearField(2);
}

class PollVoteMsg extends $pb.GeneratedMessage {
  factory PollVoteMsg({
    $core.List<$core.int>? pollId,
    $core.List<$core.int>? voterId,
    $core.String? voterName,
    $core.Iterable<$core.int>? selectedOptions,
    $core.Iterable<DateResponseMsg>? dateResponses,
    $core.int? scaleValue,
    $core.String? freeText,
    $fixnum.Int64? votedAt,
  }) {
    final $result = create();
    if (pollId != null) {
      $result.pollId = pollId;
    }
    if (voterId != null) {
      $result.voterId = voterId;
    }
    if (voterName != null) {
      $result.voterName = voterName;
    }
    if (selectedOptions != null) {
      $result.selectedOptions.addAll(selectedOptions);
    }
    if (dateResponses != null) {
      $result.dateResponses.addAll(dateResponses);
    }
    if (scaleValue != null) {
      $result.scaleValue = scaleValue;
    }
    if (freeText != null) {
      $result.freeText = freeText;
    }
    if (votedAt != null) {
      $result.votedAt = votedAt;
    }
    return $result;
  }
  PollVoteMsg._() : super();
  factory PollVoteMsg.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PollVoteMsg.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PollVoteMsg', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'pollId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'voterId', $pb.PbFieldType.OY)
    ..aOS(3, _omitFieldNames ? '' : 'voterName')
    ..p<$core.int>(4, _omitFieldNames ? '' : 'selectedOptions', $pb.PbFieldType.K3)
    ..pc<DateResponseMsg>(5, _omitFieldNames ? '' : 'dateResponses', $pb.PbFieldType.PM, subBuilder: DateResponseMsg.create)
    ..a<$core.int>(6, _omitFieldNames ? '' : 'scaleValue', $pb.PbFieldType.O3)
    ..aOS(7, _omitFieldNames ? '' : 'freeText')
    ..aInt64(8, _omitFieldNames ? '' : 'votedAt')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PollVoteMsg clone() => PollVoteMsg()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PollVoteMsg copyWith(void Function(PollVoteMsg) updates) => super.copyWith((message) => updates(message as PollVoteMsg)) as PollVoteMsg;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PollVoteMsg create() => PollVoteMsg._();
  PollVoteMsg createEmptyInstance() => create();
  static $pb.PbList<PollVoteMsg> createRepeated() => $pb.PbList<PollVoteMsg>();
  @$core.pragma('dart2js:noInline')
  static PollVoteMsg getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PollVoteMsg>(create);
  static PollVoteMsg? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get pollId => $_getN(0);
  @$pb.TagNumber(1)
  set pollId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPollId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPollId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get voterId => $_getN(1);
  @$pb.TagNumber(2)
  set voterId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasVoterId() => $_has(1);
  @$pb.TagNumber(2)
  void clearVoterId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get voterName => $_getSZ(2);
  @$pb.TagNumber(3)
  set voterName($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasVoterName() => $_has(2);
  @$pb.TagNumber(3)
  void clearVoterName() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get selectedOptions => $_getList(3);

  @$pb.TagNumber(5)
  $core.List<DateResponseMsg> get dateResponses => $_getList(4);

  @$pb.TagNumber(6)
  $core.int get scaleValue => $_getIZ(5);
  @$pb.TagNumber(6)
  set scaleValue($core.int v) { $_setSignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasScaleValue() => $_has(5);
  @$pb.TagNumber(6)
  void clearScaleValue() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get freeText => $_getSZ(6);
  @$pb.TagNumber(7)
  set freeText($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasFreeText() => $_has(6);
  @$pb.TagNumber(7)
  void clearFreeText() => clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get votedAt => $_getI64(7);
  @$pb.TagNumber(8)
  set votedAt($fixnum.Int64 v) { $_setInt64(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasVotedAt() => $_has(7);
  @$pb.TagNumber(8)
  void clearVotedAt() => clearField(8);
}

class PollUpdateMsg extends $pb.GeneratedMessage {
  factory PollUpdateMsg({
    $core.List<$core.int>? pollId,
    PollAction? action,
    $core.List<$core.int>? updatedBy,
    $core.Iterable<PollOptionMsg>? addedOptions,
    $core.Iterable<$core.int>? removedOptions,
    $fixnum.Int64? newDeadline,
    $fixnum.Int64? updatedAt,
  }) {
    final $result = create();
    if (pollId != null) {
      $result.pollId = pollId;
    }
    if (action != null) {
      $result.action = action;
    }
    if (updatedBy != null) {
      $result.updatedBy = updatedBy;
    }
    if (addedOptions != null) {
      $result.addedOptions.addAll(addedOptions);
    }
    if (removedOptions != null) {
      $result.removedOptions.addAll(removedOptions);
    }
    if (newDeadline != null) {
      $result.newDeadline = newDeadline;
    }
    if (updatedAt != null) {
      $result.updatedAt = updatedAt;
    }
    return $result;
  }
  PollUpdateMsg._() : super();
  factory PollUpdateMsg.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PollUpdateMsg.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PollUpdateMsg', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'pollId', $pb.PbFieldType.OY)
    ..e<PollAction>(2, _omitFieldNames ? '' : 'action', $pb.PbFieldType.OE, defaultOrMaker: PollAction.POLL_ACTION_CLOSE, valueOf: PollAction.valueOf, enumValues: PollAction.values)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'updatedBy', $pb.PbFieldType.OY)
    ..pc<PollOptionMsg>(4, _omitFieldNames ? '' : 'addedOptions', $pb.PbFieldType.PM, subBuilder: PollOptionMsg.create)
    ..p<$core.int>(5, _omitFieldNames ? '' : 'removedOptions', $pb.PbFieldType.K3)
    ..aInt64(6, _omitFieldNames ? '' : 'newDeadline')
    ..aInt64(7, _omitFieldNames ? '' : 'updatedAt')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PollUpdateMsg clone() => PollUpdateMsg()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PollUpdateMsg copyWith(void Function(PollUpdateMsg) updates) => super.copyWith((message) => updates(message as PollUpdateMsg)) as PollUpdateMsg;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PollUpdateMsg create() => PollUpdateMsg._();
  PollUpdateMsg createEmptyInstance() => create();
  static $pb.PbList<PollUpdateMsg> createRepeated() => $pb.PbList<PollUpdateMsg>();
  @$core.pragma('dart2js:noInline')
  static PollUpdateMsg getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PollUpdateMsg>(create);
  static PollUpdateMsg? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get pollId => $_getN(0);
  @$pb.TagNumber(1)
  set pollId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPollId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPollId() => clearField(1);

  @$pb.TagNumber(2)
  PollAction get action => $_getN(1);
  @$pb.TagNumber(2)
  set action(PollAction v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasAction() => $_has(1);
  @$pb.TagNumber(2)
  void clearAction() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get updatedBy => $_getN(2);
  @$pb.TagNumber(3)
  set updatedBy($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasUpdatedBy() => $_has(2);
  @$pb.TagNumber(3)
  void clearUpdatedBy() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<PollOptionMsg> get addedOptions => $_getList(3);

  @$pb.TagNumber(5)
  $core.List<$core.int> get removedOptions => $_getList(4);

  @$pb.TagNumber(6)
  $fixnum.Int64 get newDeadline => $_getI64(5);
  @$pb.TagNumber(6)
  set newDeadline($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasNewDeadline() => $_has(5);
  @$pb.TagNumber(6)
  void clearNewDeadline() => clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get updatedAt => $_getI64(6);
  @$pb.TagNumber(7)
  set updatedAt($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasUpdatedAt() => $_has(6);
  @$pb.TagNumber(7)
  void clearUpdatedAt() => clearField(7);
}

class OptionCountMsg extends $pb.GeneratedMessage {
  factory OptionCountMsg({
    $core.int? optionId,
    $core.int? count,
    $core.int? yesCount,
    $core.int? maybeCount,
    $core.int? noCount,
  }) {
    final $result = create();
    if (optionId != null) {
      $result.optionId = optionId;
    }
    if (count != null) {
      $result.count = count;
    }
    if (yesCount != null) {
      $result.yesCount = yesCount;
    }
    if (maybeCount != null) {
      $result.maybeCount = maybeCount;
    }
    if (noCount != null) {
      $result.noCount = noCount;
    }
    return $result;
  }
  OptionCountMsg._() : super();
  factory OptionCountMsg.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory OptionCountMsg.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'OptionCountMsg', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'optionId', $pb.PbFieldType.O3)
    ..a<$core.int>(2, _omitFieldNames ? '' : 'count', $pb.PbFieldType.O3)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'yesCount', $pb.PbFieldType.O3)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'maybeCount', $pb.PbFieldType.O3)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'noCount', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  OptionCountMsg clone() => OptionCountMsg()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  OptionCountMsg copyWith(void Function(OptionCountMsg) updates) => super.copyWith((message) => updates(message as OptionCountMsg)) as OptionCountMsg;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static OptionCountMsg create() => OptionCountMsg._();
  OptionCountMsg createEmptyInstance() => create();
  static $pb.PbList<OptionCountMsg> createRepeated() => $pb.PbList<OptionCountMsg>();
  @$core.pragma('dart2js:noInline')
  static OptionCountMsg getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<OptionCountMsg>(create);
  static OptionCountMsg? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get optionId => $_getIZ(0);
  @$pb.TagNumber(1)
  set optionId($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasOptionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOptionId() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get count => $_getIZ(1);
  @$pb.TagNumber(2)
  set count($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasCount() => $_has(1);
  @$pb.TagNumber(2)
  void clearCount() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get yesCount => $_getIZ(2);
  @$pb.TagNumber(3)
  set yesCount($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasYesCount() => $_has(2);
  @$pb.TagNumber(3)
  void clearYesCount() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get maybeCount => $_getIZ(3);
  @$pb.TagNumber(4)
  set maybeCount($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasMaybeCount() => $_has(3);
  @$pb.TagNumber(4)
  void clearMaybeCount() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get noCount => $_getIZ(4);
  @$pb.TagNumber(5)
  set noCount($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasNoCount() => $_has(4);
  @$pb.TagNumber(5)
  void clearNoCount() => clearField(5);
}

class PollSnapshotMsg extends $pb.GeneratedMessage {
  factory PollSnapshotMsg({
    $core.List<$core.int>? pollId,
    $core.int? totalVotes,
    $core.Iterable<OptionCountMsg>? optionCounts,
    $core.double? scaleAverage,
    $core.int? scaleCount,
    $core.bool? closed,
    $fixnum.Int64? snapshotAt,
  }) {
    final $result = create();
    if (pollId != null) {
      $result.pollId = pollId;
    }
    if (totalVotes != null) {
      $result.totalVotes = totalVotes;
    }
    if (optionCounts != null) {
      $result.optionCounts.addAll(optionCounts);
    }
    if (scaleAverage != null) {
      $result.scaleAverage = scaleAverage;
    }
    if (scaleCount != null) {
      $result.scaleCount = scaleCount;
    }
    if (closed != null) {
      $result.closed = closed;
    }
    if (snapshotAt != null) {
      $result.snapshotAt = snapshotAt;
    }
    return $result;
  }
  PollSnapshotMsg._() : super();
  factory PollSnapshotMsg.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PollSnapshotMsg.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PollSnapshotMsg', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'pollId', $pb.PbFieldType.OY)
    ..a<$core.int>(2, _omitFieldNames ? '' : 'totalVotes', $pb.PbFieldType.O3)
    ..pc<OptionCountMsg>(3, _omitFieldNames ? '' : 'optionCounts', $pb.PbFieldType.PM, subBuilder: OptionCountMsg.create)
    ..a<$core.double>(4, _omitFieldNames ? '' : 'scaleAverage', $pb.PbFieldType.OD)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'scaleCount', $pb.PbFieldType.O3)
    ..aOB(6, _omitFieldNames ? '' : 'closed')
    ..aInt64(7, _omitFieldNames ? '' : 'snapshotAt')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PollSnapshotMsg clone() => PollSnapshotMsg()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PollSnapshotMsg copyWith(void Function(PollSnapshotMsg) updates) => super.copyWith((message) => updates(message as PollSnapshotMsg)) as PollSnapshotMsg;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PollSnapshotMsg create() => PollSnapshotMsg._();
  PollSnapshotMsg createEmptyInstance() => create();
  static $pb.PbList<PollSnapshotMsg> createRepeated() => $pb.PbList<PollSnapshotMsg>();
  @$core.pragma('dart2js:noInline')
  static PollSnapshotMsg getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PollSnapshotMsg>(create);
  static PollSnapshotMsg? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get pollId => $_getN(0);
  @$pb.TagNumber(1)
  set pollId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPollId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPollId() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get totalVotes => $_getIZ(1);
  @$pb.TagNumber(2)
  set totalVotes($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTotalVotes() => $_has(1);
  @$pb.TagNumber(2)
  void clearTotalVotes() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<OptionCountMsg> get optionCounts => $_getList(2);

  @$pb.TagNumber(4)
  $core.double get scaleAverage => $_getN(3);
  @$pb.TagNumber(4)
  set scaleAverage($core.double v) { $_setDouble(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasScaleAverage() => $_has(3);
  @$pb.TagNumber(4)
  void clearScaleAverage() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get scaleCount => $_getIZ(4);
  @$pb.TagNumber(5)
  set scaleCount($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasScaleCount() => $_has(4);
  @$pb.TagNumber(5)
  void clearScaleCount() => clearField(5);

  @$pb.TagNumber(6)
  $core.bool get closed => $_getBF(5);
  @$pb.TagNumber(6)
  set closed($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasClosed() => $_has(5);
  @$pb.TagNumber(6)
  void clearClosed() => clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get snapshotAt => $_getI64(6);
  @$pb.TagNumber(7)
  set snapshotAt($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasSnapshotAt() => $_has(6);
  @$pb.TagNumber(7)
  void clearSnapshotAt() => clearField(7);
}

/// Anonymous vote (§24.4): ring signature over all group member keys.
/// Contains no voter_id/voter_name — identity is hidden by the ring, while
/// key_image prevents double-voting.
class PollVoteAnonymousMsg extends $pb.GeneratedMessage {
  factory PollVoteAnonymousMsg({
    $core.List<$core.int>? pollId,
    $core.List<$core.int>? encryptedChoice,
    $core.List<$core.int>? keyImage,
    $core.List<$core.int>? ringSignature,
    $core.Iterable<$core.List<$core.int>>? ringMembers,
    $fixnum.Int64? votedAt,
  }) {
    final $result = create();
    if (pollId != null) {
      $result.pollId = pollId;
    }
    if (encryptedChoice != null) {
      $result.encryptedChoice = encryptedChoice;
    }
    if (keyImage != null) {
      $result.keyImage = keyImage;
    }
    if (ringSignature != null) {
      $result.ringSignature = ringSignature;
    }
    if (ringMembers != null) {
      $result.ringMembers.addAll(ringMembers);
    }
    if (votedAt != null) {
      $result.votedAt = votedAt;
    }
    return $result;
  }
  PollVoteAnonymousMsg._() : super();
  factory PollVoteAnonymousMsg.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PollVoteAnonymousMsg.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PollVoteAnonymousMsg', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'pollId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'encryptedChoice', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'keyImage', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'ringSignature', $pb.PbFieldType.OY)
    ..p<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'ringMembers', $pb.PbFieldType.PY)
    ..aInt64(6, _omitFieldNames ? '' : 'votedAt')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PollVoteAnonymousMsg clone() => PollVoteAnonymousMsg()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PollVoteAnonymousMsg copyWith(void Function(PollVoteAnonymousMsg) updates) => super.copyWith((message) => updates(message as PollVoteAnonymousMsg)) as PollVoteAnonymousMsg;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PollVoteAnonymousMsg create() => PollVoteAnonymousMsg._();
  PollVoteAnonymousMsg createEmptyInstance() => create();
  static $pb.PbList<PollVoteAnonymousMsg> createRepeated() => $pb.PbList<PollVoteAnonymousMsg>();
  @$core.pragma('dart2js:noInline')
  static PollVoteAnonymousMsg getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PollVoteAnonymousMsg>(create);
  static PollVoteAnonymousMsg? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get pollId => $_getN(0);
  @$pb.TagNumber(1)
  set pollId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPollId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPollId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get encryptedChoice => $_getN(1);
  @$pb.TagNumber(2)
  set encryptedChoice($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasEncryptedChoice() => $_has(1);
  @$pb.TagNumber(2)
  void clearEncryptedChoice() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get keyImage => $_getN(2);
  @$pb.TagNumber(3)
  set keyImage($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasKeyImage() => $_has(2);
  @$pb.TagNumber(3)
  void clearKeyImage() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get ringSignature => $_getN(3);
  @$pb.TagNumber(4)
  set ringSignature($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasRingSignature() => $_has(3);
  @$pb.TagNumber(4)
  void clearRingSignature() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.List<$core.int>> get ringMembers => $_getList(4);

  @$pb.TagNumber(6)
  $fixnum.Int64 get votedAt => $_getI64(5);
  @$pb.TagNumber(6)
  set votedAt($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasVotedAt() => $_has(5);
  @$pb.TagNumber(6)
  void clearVotedAt() => clearField(6);
}

/// Anonymous vote-revocation: owner proves ownership of a key image by
/// re-signing a fixed "revoke" marker with the same ring.
class PollVoteRevokeMsg extends $pb.GeneratedMessage {
  factory PollVoteRevokeMsg({
    $core.List<$core.int>? pollId,
    $core.List<$core.int>? keyImage,
    $core.List<$core.int>? ringSignature,
    $core.Iterable<$core.List<$core.int>>? ringMembers,
    $fixnum.Int64? revokedAt,
  }) {
    final $result = create();
    if (pollId != null) {
      $result.pollId = pollId;
    }
    if (keyImage != null) {
      $result.keyImage = keyImage;
    }
    if (ringSignature != null) {
      $result.ringSignature = ringSignature;
    }
    if (ringMembers != null) {
      $result.ringMembers.addAll(ringMembers);
    }
    if (revokedAt != null) {
      $result.revokedAt = revokedAt;
    }
    return $result;
  }
  PollVoteRevokeMsg._() : super();
  factory PollVoteRevokeMsg.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PollVoteRevokeMsg.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PollVoteRevokeMsg', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'pollId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'keyImage', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'ringSignature', $pb.PbFieldType.OY)
    ..p<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'ringMembers', $pb.PbFieldType.PY)
    ..aInt64(5, _omitFieldNames ? '' : 'revokedAt')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PollVoteRevokeMsg clone() => PollVoteRevokeMsg()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PollVoteRevokeMsg copyWith(void Function(PollVoteRevokeMsg) updates) => super.copyWith((message) => updates(message as PollVoteRevokeMsg)) as PollVoteRevokeMsg;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PollVoteRevokeMsg create() => PollVoteRevokeMsg._();
  PollVoteRevokeMsg createEmptyInstance() => create();
  static $pb.PbList<PollVoteRevokeMsg> createRepeated() => $pb.PbList<PollVoteRevokeMsg>();
  @$core.pragma('dart2js:noInline')
  static PollVoteRevokeMsg getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PollVoteRevokeMsg>(create);
  static PollVoteRevokeMsg? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get pollId => $_getN(0);
  @$pb.TagNumber(1)
  set pollId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPollId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPollId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get keyImage => $_getN(1);
  @$pb.TagNumber(2)
  set keyImage($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasKeyImage() => $_has(1);
  @$pb.TagNumber(2)
  void clearKeyImage() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get ringSignature => $_getN(2);
  @$pb.TagNumber(3)
  set ringSignature($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasRingSignature() => $_has(2);
  @$pb.TagNumber(3)
  void clearRingSignature() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.List<$core.int>> get ringMembers => $_getList(3);

  @$pb.TagNumber(5)
  $fixnum.Int64 get revokedAt => $_getI64(4);
  @$pb.TagNumber(5)
  set revokedAt($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasRevokedAt() => $_has(4);
  @$pb.TagNumber(5)
  void clearRevokedAt() => clearField(5);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');

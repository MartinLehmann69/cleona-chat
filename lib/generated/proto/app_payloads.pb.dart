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

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'app_payloads.pbenum.dart';

export 'app_payloads.pbenum.dart';

class ContentMetadata extends $pb.GeneratedMessage {
  factory ContentMetadata({
    $core.String? mimeType,
    $fixnum.Int64? fileSize,
    $core.String? filename,
    $core.int? durationMs,
    $core.List<$core.int>? thumbnail,
    $core.List<$core.int>? contentHash,
    $core.String? transcriptText,
    $core.String? transcriptLanguage,
    $core.double? transcriptConfidence,
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
    ..aOS(7, _omitFieldNames ? '' : 'transcriptText')
    ..aOS(8, _omitFieldNames ? '' : 'transcriptLanguage')
    ..a<$core.double>(9, _omitFieldNames ? '' : 'transcriptConfidence', $pb.PbFieldType.OF)
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

  /// Source-side transcript (§14.9). Inline voice additionally carries it in the
  /// VoicePayload; in the two-stage path (>256KB) the metadata is the ONLY
  /// carrier, because MEDIA_ANNOUNCE has no payload and the stage-2 chunks
  /// are raw file bytes.
  @$pb.TagNumber(7)
  $core.String get transcriptText => $_getSZ(6);
  @$pb.TagNumber(7)
  set transcriptText($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasTranscriptText() => $_has(6);
  @$pb.TagNumber(7)
  void clearTranscriptText() => clearField(7);

  @$pb.TagNumber(8)
  $core.String get transcriptLanguage => $_getSZ(7);
  @$pb.TagNumber(8)
  set transcriptLanguage($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasTranscriptLanguage() => $_has(7);
  @$pb.TagNumber(8)
  void clearTranscriptLanguage() => clearField(8);

  @$pb.TagNumber(9)
  $core.double get transcriptConfidence => $_getN(8);
  @$pb.TagNumber(9)
  set transcriptConfidence($core.double v) { $_setFloat(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasTranscriptConfidence() => $_has(8);
  @$pb.TagNumber(9)
  void clearTranscriptConfidence() => clearField(9);
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

class GroupInviteV3 extends $pb.GeneratedMessage {
  factory GroupInviteV3({
    $core.List<$core.int>? groupId,
    $core.String? groupName,
    $core.List<$core.int>? inviterId,
    $core.Iterable<GroupMemberV3>? members,
    $core.List<$core.int>? groupPicture,
    $core.String? groupDescription,
    $fixnum.Int64? membershipEpoch,
    $core.List<$core.int>? membershipHash,
    $core.List<$core.int>? membershipSigEd25519,
    $core.List<$core.int>? membershipSigMlDsa,
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
    if (membershipEpoch != null) {
      $result.membershipEpoch = membershipEpoch;
    }
    if (membershipHash != null) {
      $result.membershipHash = membershipHash;
    }
    if (membershipSigEd25519 != null) {
      $result.membershipSigEd25519 = membershipSigEd25519;
    }
    if (membershipSigMlDsa != null) {
      $result.membershipSigMlDsa = membershipSigMlDsa;
    }
    return $result;
  }
  GroupInviteV3._() : super();
  factory GroupInviteV3.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GroupInviteV3.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GroupInviteV3', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'groupId', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'groupName')
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'inviterId', $pb.PbFieldType.OY)
    ..pc<GroupMemberV3>(4, _omitFieldNames ? '' : 'members', $pb.PbFieldType.PM, subBuilder: GroupMemberV3.create)
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'groupPicture', $pb.PbFieldType.OY)
    ..aOS(6, _omitFieldNames ? '' : 'groupDescription')
    ..a<$fixnum.Int64>(7, _omitFieldNames ? '' : 'membershipEpoch', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(8, _omitFieldNames ? '' : 'membershipHash', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(9, _omitFieldNames ? '' : 'membershipSigEd25519', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(10, _omitFieldNames ? '' : 'membershipSigMlDsa', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GroupInviteV3 clone() => GroupInviteV3()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GroupInviteV3 copyWith(void Function(GroupInviteV3) updates) => super.copyWith((message) => updates(message as GroupInviteV3)) as GroupInviteV3;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GroupInviteV3 create() => GroupInviteV3._();
  GroupInviteV3 createEmptyInstance() => create();
  static $pb.PbList<GroupInviteV3> createRepeated() => $pb.PbList<GroupInviteV3>();
  @$core.pragma('dart2js:noInline')
  static GroupInviteV3 getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GroupInviteV3>(create);
  static GroupInviteV3? _defaultInstance;

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
  $core.List<GroupMemberV3> get members => $_getList(3);

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

  /// GM-1 (§9.1.4): monotonic epoch + canonical membership hash + hybrid sig
  @$pb.TagNumber(7)
  $fixnum.Int64 get membershipEpoch => $_getI64(6);
  @$pb.TagNumber(7)
  set membershipEpoch($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasMembershipEpoch() => $_has(6);
  @$pb.TagNumber(7)
  void clearMembershipEpoch() => clearField(7);

  @$pb.TagNumber(8)
  $core.List<$core.int> get membershipHash => $_getN(7);
  @$pb.TagNumber(8)
  set membershipHash($core.List<$core.int> v) { $_setBytes(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasMembershipHash() => $_has(7);
  @$pb.TagNumber(8)
  void clearMembershipHash() => clearField(8);

  @$pb.TagNumber(9)
  $core.List<$core.int> get membershipSigEd25519 => $_getN(8);
  @$pb.TagNumber(9)
  set membershipSigEd25519($core.List<$core.int> v) { $_setBytes(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasMembershipSigEd25519() => $_has(8);
  @$pb.TagNumber(9)
  void clearMembershipSigEd25519() => clearField(9);

  @$pb.TagNumber(10)
  $core.List<$core.int> get membershipSigMlDsa => $_getN(9);
  @$pb.TagNumber(10)
  set membershipSigMlDsa($core.List<$core.int> v) { $_setBytes(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasMembershipSigMlDsa() => $_has(9);
  @$pb.TagNumber(10)
  void clearMembershipSigMlDsa() => clearField(10);
}

class GroupMemberV3 extends $pb.GeneratedMessage {
  factory GroupMemberV3({
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
  GroupMemberV3._() : super();
  factory GroupMemberV3.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GroupMemberV3.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GroupMemberV3', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
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
  GroupMemberV3 clone() => GroupMemberV3()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GroupMemberV3 copyWith(void Function(GroupMemberV3) updates) => super.copyWith((message) => updates(message as GroupMemberV3)) as GroupMemberV3;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GroupMemberV3 create() => GroupMemberV3._();
  GroupMemberV3 createEmptyInstance() => create();
  static $pb.PbList<GroupMemberV3> createRepeated() => $pb.PbList<GroupMemberV3>();
  @$core.pragma('dart2js:noInline')
  static GroupMemberV3 getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GroupMemberV3>(create);
  static GroupMemberV3? _defaultInstance;

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

/// GM-2 (§9.1.4): requester sends local epoch so owner knows whether a resync is needed
class GroupMembershipResyncRequest extends $pb.GeneratedMessage {
  factory GroupMembershipResyncRequest({
    $core.List<$core.int>? groupId,
    $fixnum.Int64? localEpoch,
  }) {
    final $result = create();
    if (groupId != null) {
      $result.groupId = groupId;
    }
    if (localEpoch != null) {
      $result.localEpoch = localEpoch;
    }
    return $result;
  }
  GroupMembershipResyncRequest._() : super();
  factory GroupMembershipResyncRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GroupMembershipResyncRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GroupMembershipResyncRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'groupId', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'localEpoch', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GroupMembershipResyncRequest clone() => GroupMembershipResyncRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GroupMembershipResyncRequest copyWith(void Function(GroupMembershipResyncRequest) updates) => super.copyWith((message) => updates(message as GroupMembershipResyncRequest)) as GroupMembershipResyncRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GroupMembershipResyncRequest create() => GroupMembershipResyncRequest._();
  GroupMembershipResyncRequest createEmptyInstance() => create();
  static $pb.PbList<GroupMembershipResyncRequest> createRepeated() => $pb.PbList<GroupMembershipResyncRequest>();
  @$core.pragma('dart2js:noInline')
  static GroupMembershipResyncRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GroupMembershipResyncRequest>(create);
  static GroupMembershipResyncRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get groupId => $_getN(0);
  @$pb.TagNumber(1)
  set groupId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasGroupId() => $_has(0);
  @$pb.TagNumber(1)
  void clearGroupId() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get localEpoch => $_getI64(1);
  @$pb.TagNumber(2)
  set localEpoch($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasLocalEpoch() => $_has(1);
  @$pb.TagNumber(2)
  void clearLocalEpoch() => clearField(2);
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
    $core.Iterable<GroupMemberV3>? members,
    $core.bool? isPublic,
    $core.bool? isAdult,
    $core.String? language,
    $fixnum.Int64? membershipEpoch,
    $core.List<$core.int>? membershipHash,
    $core.List<$core.int>? membershipSigEd25519,
    $core.List<$core.int>? membershipSigMlDsa,
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
    if (membershipEpoch != null) {
      $result.membershipEpoch = membershipEpoch;
    }
    if (membershipHash != null) {
      $result.membershipHash = membershipHash;
    }
    if (membershipSigEd25519 != null) {
      $result.membershipSigEd25519 = membershipSigEd25519;
    }
    if (membershipSigMlDsa != null) {
      $result.membershipSigMlDsa = membershipSigMlDsa;
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
    ..pc<GroupMemberV3>(8, _omitFieldNames ? '' : 'members', $pb.PbFieldType.PM, subBuilder: GroupMemberV3.create)
    ..aOB(9, _omitFieldNames ? '' : 'isPublic')
    ..aOB(10, _omitFieldNames ? '' : 'isAdult')
    ..aOS(11, _omitFieldNames ? '' : 'language')
    ..a<$fixnum.Int64>(12, _omitFieldNames ? '' : 'membershipEpoch', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(13, _omitFieldNames ? '' : 'membershipHash', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(14, _omitFieldNames ? '' : 'membershipSigEd25519', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(15, _omitFieldNames ? '' : 'membershipSigMlDsa', $pb.PbFieldType.OY)
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
  $core.List<GroupMemberV3> get members => $_getList(7);

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

  /// GM-4 (§9.1.4): monotonic epoch + canonical membership hash + hybrid sig
  @$pb.TagNumber(12)
  $fixnum.Int64 get membershipEpoch => $_getI64(11);
  @$pb.TagNumber(12)
  set membershipEpoch($fixnum.Int64 v) { $_setInt64(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasMembershipEpoch() => $_has(11);
  @$pb.TagNumber(12)
  void clearMembershipEpoch() => clearField(12);

  @$pb.TagNumber(13)
  $core.List<$core.int> get membershipHash => $_getN(12);
  @$pb.TagNumber(13)
  set membershipHash($core.List<$core.int> v) { $_setBytes(12, v); }
  @$pb.TagNumber(13)
  $core.bool hasMembershipHash() => $_has(12);
  @$pb.TagNumber(13)
  void clearMembershipHash() => clearField(13);

  @$pb.TagNumber(14)
  $core.List<$core.int> get membershipSigEd25519 => $_getN(13);
  @$pb.TagNumber(14)
  set membershipSigEd25519($core.List<$core.int> v) { $_setBytes(13, v); }
  @$pb.TagNumber(14)
  $core.bool hasMembershipSigEd25519() => $_has(13);
  @$pb.TagNumber(14)
  void clearMembershipSigEd25519() => clearField(14);

  @$pb.TagNumber(15)
  $core.List<$core.int> get membershipSigMlDsa => $_getN(14);
  @$pb.TagNumber(15)
  set membershipSigMlDsa($core.List<$core.int> v) { $_setBytes(14, v); }
  @$pb.TagNumber(15)
  $core.bool hasMembershipSigMlDsa() => $_has(14);
  @$pb.TagNumber(15)
  void clearMembershipSigMlDsa() => clearField(15);
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
    $core.List<$core.int>? signatureMlDsa,
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
    if (signatureMlDsa != null) {
      $result.signatureMlDsa = signatureMlDsa;
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
    ..a<$core.List<$core.int>>(10, _omitFieldNames ? '' : 'signatureMlDsa', $pb.PbFieldType.OY)
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

  @$pb.TagNumber(10)
  $core.List<$core.int> get signatureMlDsa => $_getN(9);
  @$pb.TagNumber(10)
  set signatureMlDsa($core.List<$core.int> v) { $_setBytes(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasSignatureMlDsa() => $_has(9);
  @$pb.TagNumber(10)
  void clearSignatureMlDsa() => clearField(10);
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
    $core.bool? isAdult,
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
    if (isAdult != null) {
      $result.isAdult = isAdult;
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
    ..aOB(6, _omitFieldNames ? '' : 'isAdult')
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

  /// NSFW rating. Without this field the restore path could not carry the flag
  /// at all, so a recovered channel always fell back to the ChannelInfo
  /// constructor default. Per architecture §9.2.2 a channel marked not safe for
  /// minors is invisible to identities without the isAdult flag, so losing the
  /// flag on recovery would expose an adult channel to exactly those users.
  /// Field 6 is additive: old senders leave it unset and new readers see the
  /// protobuf default false, which is the pre-existing behaviour.
  @$pb.TagNumber(6)
  $core.bool get isAdult => $_getBF(5);
  @$pb.TagNumber(6)
  set isAdult($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasIsAdult() => $_has(5);
  @$pb.TagNumber(6)
  void clearIsAdult() => clearField(6);
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
    $core.int? uiMessageType,
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
    if (uiMessageType != null) {
      $result.uiMessageType = uiMessageType;
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
    ..a<$core.int>(6, _omitFieldNames ? '' : 'uiMessageType', $pb.PbFieldType.O3)
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

  /// V3 (2026-05-05 Wave 7): UI-tag carrying `UiMessageType.wireValue` (sequential
  /// 0..N, see lib/core/service/service_types.dart). Detached from the V2
  /// `MessageType` wire enum so RESTORE_RESPONSE no longer drags V2-numbering
  /// into the inner-frame payload.
  @$pb.TagNumber(6)
  $core.int get uiMessageType => $_getIZ(5);
  @$pb.TagNumber(6)
  set uiMessageType($core.int v) { $_setSignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasUiMessageType() => $_has(5);
  @$pb.TagNumber(6)
  void clearUiMessageType() => clearField(6);

  @$pb.TagNumber(7)
  $core.List<$core.int> get payload => $_getN(6);
  @$pb.TagNumber(7)
  set payload($core.List<$core.int> v) { $_setBytes(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasPayload() => $_has(6);
  @$pb.TagNumber(7)
  void clearPayload() => clearField(7);
}

class CallInvite extends $pb.GeneratedMessage {
  factory CallInvite({
    $core.List<$core.int>? callId,
    $core.List<$core.int>? callerEphX25519Pk,
    $core.List<$core.int>? callerKemCiphertext,
    $core.bool? isVideo,
    $core.bool? isGroupCall,
    $core.List<$core.int>? groupId,
    $core.int? callerAppMajorMinor,
    $core.int? callerAudioFormatMin,
    $core.int? callerAudioFormatMax,
    $core.int? callerVideoFormatMin,
    $core.int? callerVideoFormatMax,
    $core.List<$core.int>? callerCandidates,
    $core.List<$core.int>? callerDCookie,
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
    if (callerAppMajorMinor != null) {
      $result.callerAppMajorMinor = callerAppMajorMinor;
    }
    if (callerAudioFormatMin != null) {
      $result.callerAudioFormatMin = callerAudioFormatMin;
    }
    if (callerAudioFormatMax != null) {
      $result.callerAudioFormatMax = callerAudioFormatMax;
    }
    if (callerVideoFormatMin != null) {
      $result.callerVideoFormatMin = callerVideoFormatMin;
    }
    if (callerVideoFormatMax != null) {
      $result.callerVideoFormatMax = callerVideoFormatMax;
    }
    if (callerCandidates != null) {
      $result.callerCandidates = callerCandidates;
    }
    if (callerDCookie != null) {
      $result.callerDCookie = callerDCookie;
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
    ..a<$core.int>(8, _omitFieldNames ? '' : 'callerAppMajorMinor', $pb.PbFieldType.OU3)
    ..a<$core.int>(9, _omitFieldNames ? '' : 'callerAudioFormatMin', $pb.PbFieldType.OU3)
    ..a<$core.int>(10, _omitFieldNames ? '' : 'callerAudioFormatMax', $pb.PbFieldType.OU3)
    ..a<$core.int>(11, _omitFieldNames ? '' : 'callerVideoFormatMin', $pb.PbFieldType.OU3)
    ..a<$core.int>(12, _omitFieldNames ? '' : 'callerVideoFormatMax', $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(13, _omitFieldNames ? '' : 'callerCandidates', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(14, _omitFieldNames ? '' : 'callerDCookie', $pb.PbFieldType.OY)
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

  ///  ── Version gate (§10.4, spec erratum E5) ────────────────────────────
  ///
  ///  The app version of the caller, encoded as `major * 1000 + minor`.
  ///  3.1.x -> 3001, 3.2.0 -> 3002, 4.0.0 -> 4000. Monotonic across every
  ///  version jump, also across a major change.
  ///
  ///  WHAT FOR. §10.4 specifies that sample rate, codec and frame format all three
  ///  change with 3.2.0 and that a 3.1.x client therefore cannot hold a call with a 3.2.x client.
  ///  For that the recipient needs a
  ///  statement about which voice stack the caller speaks.
  ///
  ///  A MISSING FIELD IS A STATEMENT, NOT A GAP. proto3 delivers 0, and
  ///  a recipient must NOT derive from the absence "unknown, so probably
  ///  fine".
  ///
  ///  S368: here it said that 0 meant "defines 'sender older than 3.2.0,
  ///  superseded voice stack'". This interpretation is gone, and with it
  ///  the 0 no longer needs a special case: since S368 the evaluation asks for
  ///  EQUALITY with the own version (`call_service.dart`,
  ///  `isCompatibleCallerVersion`), and 0 is never equal to the own version.
  ///  A statement about WHICH older line the sender speaks thus
  ///  no longer has an addressee — on this line there are no older
  ///  counterparts (owner, 05.09.2026: "V4.1 is not backwards compatible",
  ///  "Neither data - nor in the network!").
  ///
  ///  WHY major+minor AND NOT ONLY THE MINOR. §10.4 formulates the gate as
  ///  `minor >= 2`. The minor alone does not survive a major jump: 4.0.0 has
  ///  minor 0, and a check `minor >= 2` would reject every 4.0 client,
  ///  although it has the newer stack. The field therefore carries both. Thus
  ///  both the literal rule from §10.4 can be formed (`(v % 1000) >= 2`) and
  ///  a rollover-proof one (`v >= 3002`) — the choice between them is a
  ///  decision about the evaluation, not about the wire format, and is therefore
  ///  not made here. See the finding on §10.4 in package report V1.12.
  ///
  ///  S368, so that the next reader does not build the wrong one: the evaluation
  ///  of this line takes NEITHER of the two. It asks for EQUALITY
  ///  (`v == own version`), because a lower bound accepts every FUTURE
  ///  version unchecked — the same defect, only one generation
  ///  later. The wire format still carries both readings; the
  ///  reasoning stands in `call_service.dart` at
  ///  `isCompatibleCallerVersion`.
  ///
  ///  WHY WITHOUT PATCH. A patch release does not change the voice stack (semver),
  ///  and the patch counter of this project runs to well over 99 (v3.1.160).
  ///  Every encoding that packs it into a fixed position would have
  ///  overflowed there and would have made 3.1.160 look larger than 3.2.0.
  ///  Capping: minor < 1000.
  ///
  ///  THE CHECK ITSELF DOES NOT LIE HERE. It belongs to V2.1
  ///  (`call_service.dart`, `handleCallInviteV3`), together with the rejection reason visible to the
  ///  user and its translation. §10.4: a
  ///  call between incompatible versions is explicitly rejected,
  ///  "never allowed to fail silently".
  @$pb.TagNumber(8)
  $core.int get callerAppMajorMinor => $_getIZ(6);
  @$pb.TagNumber(8)
  set callerAppMajorMinor($core.int v) { $_setUnsignedInt32(6, v); }
  @$pb.TagNumber(8)
  $core.bool hasCallerAppMajorMinor() => $_has(6);
  @$pb.TagNumber(8)
  void clearCallerAppMajorMinor() => clearField(8);

  ///  ── Media format negotiation (§10.3.1/§10.4/§10.6, V1.18) ────────────
  ///
  ///  The range of media formats that the caller can speak. Separated
  ///  for audio and video, because both have separate ABIs (`cleona_voice.h`,
  ///  `cleona_video.h`), separate codecs and separate step plans —
  ///  §10.4 step 5 exchanges the audio codec (Opus), §10.6 step 4/5 the
  ///  video codec, independently of each other. A shared counter would
  ///  force a video change to downgrade audio along with it, although nothing has changed
  ///  in the audio format.
  ///
  ///  WHAT A COUNTER COVERS. For its media kind: the wire framing of the
  ///  media message, the codec including parameters, the frame layout and the
  ///  AEAD construction on this payload. These four change together in this
  ///  project, not individually: §10.4 changes with 3.2.0 sample rate,
  ///  codec AND frame format and calls that ONE incompatibility. Four
  ///  separate counters would make combinations describable that no
  ///  build ever produces and that nobody can test.
  ///
  ///  WHAT FOR — AND EXPLICITLY NOT WHAT FOR. There is no backwards compatibility
  ///  with 3.1, and that stays so (§10.4 "Compatibility: none,
  ///  by decision"). These fields do not establish it. They exist for
  ///  the reverse case: so that a FUTURE version (3.3, 4.0, ...) can still speak with
  ///  3.2, instead of forcing a second hard cut.
  ///
  ///  RELATION TO FIELD 8. Field 8 is a one-sided floor ("is the peer
  ///  at least 3.2.0") and is not negotiated. It cannot
  ///  express what the other side speaks, and a 3.2 client shipped today
  ///  carries `>= 3002` set in concrete: it accepts every future
  ///  version unconditionally and can never learn that 3.4 media are
  ///  undecodable for it. Exactly this gap is closed by these fields. The
  ///  two do not overlap — field 8 answers "can we talk
  ///  at all", these fields "in which dialect", and they act
  ///  exclusively above the floor of field 8.
  ///
  ///  A MISSING FIELD IS A STATEMENT, NOT A GAP. proto3 delivers 0.
  ///  These fields can only be omitted by a build from 3.2.0 on that
  ///  was made before V1.18 — and that one speaks exactly base format 1. 0 here
  ///  therefore means by definition "range [1,1], only the 3.2.0 base format", not
  ///  "unknown, so probably fine". That is deliberately the OTHER conclusion
  ///  than with field 8, where 0 leads to rejection: there the 0 stems from a
  ///  3.1.x client that cannot hold a call at all, here from a
  ///  3.2.0 client that can. Same rule, different facts — the
  ///  conclusion is derived, not chosen.
  ///
  ///  WHY A RANGE AND NOT ONLY A MAXIMUM. Old formats are dropped,
  ///  not dragged along forever: `PerMessageKem.acceptKemVersions`
  ///  has changed from {1} to {2} (v1 removed in V3.1.72). Without the
  ///  minimum the callee could choose a format that the caller
  ///  has long stopped speaking; the abort would only take place one round later
  ///  at the caller, with a worse reason. A contiguous
  ///  range suffices — the acceptance set of this project was always
  ///  contiguous.
  ///
  ///  WHY NOT PER FRAME. A field in every audio frame costs at 50
  ///  frames/s permanently roughly 100 B/s per direction, against the Opus target of
  ///  24-32 kbps (§10.4) thus ~2.7 % — for a property that
  ///  never changes during the session. Work rule 5 and the hard
  ///  size bounds from §10.3.1/I9 forbid recurring costs without
  ///  benefit. What does change in the middle of the call is resolution
  ///  and bitrate (V1.17); those already stand in `VideoFrame.width/height`
  ///  and are a preset, not a format. A change of the format itself
  ///  requires a rebuild (`MTV3_CALL_REJOIN`), which renegotiates.
  ///  The negotiation is reliable: `CALL_INVITE`/`CALL_ANSWER` are
  ///  setup frames with ML-DSA, zstd and the normal delivery cascade, not
  ///  live media — they cannot get lost silently.
  ///
  ///  THE EVALUATION DOES NOT LIE HERE. The negotiation rule stands in
  ///  `lib/core/calls/media_format_version.dart`; the wiring in
  ///  `call_service.dart` including visible rejection reason belongs to V2.1
  ///  (BUGFIX_CURRENT.md AV-V1.18).
  @$pb.TagNumber(9)
  $core.int get callerAudioFormatMin => $_getIZ(7);
  @$pb.TagNumber(9)
  set callerAudioFormatMin($core.int v) { $_setUnsignedInt32(7, v); }
  @$pb.TagNumber(9)
  $core.bool hasCallerAudioFormatMin() => $_has(7);
  @$pb.TagNumber(9)
  void clearCallerAudioFormatMin() => clearField(9);

  @$pb.TagNumber(10)
  $core.int get callerAudioFormatMax => $_getIZ(8);
  @$pb.TagNumber(10)
  set callerAudioFormatMax($core.int v) { $_setUnsignedInt32(8, v); }
  @$pb.TagNumber(10)
  $core.bool hasCallerAudioFormatMax() => $_has(8);
  @$pb.TagNumber(10)
  void clearCallerAudioFormatMax() => clearField(10);

  @$pb.TagNumber(11)
  $core.int get callerVideoFormatMin => $_getIZ(9);
  @$pb.TagNumber(11)
  set callerVideoFormatMin($core.int v) { $_setUnsignedInt32(9, v); }
  @$pb.TagNumber(11)
  $core.bool hasCallerVideoFormatMin() => $_has(9);
  @$pb.TagNumber(11)
  void clearCallerVideoFormatMin() => clearField(11);

  @$pb.TagNumber(12)
  $core.int get callerVideoFormatMax => $_getIZ(10);
  @$pb.TagNumber(12)
  set callerVideoFormatMax($core.int v) { $_setUnsignedInt32(10, v); }
  @$pb.TagNumber(12)
  $core.bool hasCallerVideoFormatMax() => $_has(10);
  @$pb.TagNumber(12)
  void clearCallerVideoFormatMax() => clearField(12);

  ///  ── Address candidates and session cookie of level D (§17.3/§17.4) ───
  ///
  ///  §17.3 verbatim: "Candidates in signaling: INVITE and ANSWER carry the
  ///  address candidates of both sides (local addresses + observed
  ///  addresses, both families kept separate - a narrow ICE without TURN)."
  ///
  ///  ONE PACKED FIELD AND NOT `repeated bytes`, and the reason is the
  ///  cell limit. A `repeated bytes` costs 2 B of framing per candidate
  ///  (field header + length); eight candidates are 16 B of framing alone. The
  ///  INVITE already carries the 1088 B large ML-KEM ciphertext and thus lies
  ///  close to the piece limit of the delivery (1026 B payload per
  ///  cell, `frame_split.dart`) - every additional byte can cost a
  ///  further cell, and one cell on the signal line is
  ///  m x R_signal = 15 placements = 120 s egress (§17.2), i.e. a
  ///  full TTL. The packed form is therefore not a micro-optimisation.
  ///
  ///  FORMAT, self-delimiting, see `lib/core/calls/address_candidates.dart`:
  ///
  ///      per candidate:  fam(1) = 4 | 6  ||  addr(4 | 16)  ||  port(2, big endian)
  ///
  ///  i.e. 7 B for IPv4 and 19 B for IPv6. The family stands in front, because
  ///  only it says how many bytes follow. An unknown family value
  ///  ends the reading - a reader that keeps guessing assembles candidates from
  ///  foreign leftovers.
  ///
  ///  ORDER IS A STATEMENT: the observations stand in the order
  ///  of the address book, the youngest last. The port prediction from §17.3
  ///  ("within a window of +/-10 ports around the most recently observed
  ///  port") reads exactly this promise.
  ///
  ///  A MISSING FIELD IS A STATEMENT: empty means "no candidates
  ///  named", and the recipient then starts no punch window instead of
  ///  sending to `0.0.0.0`.
  @$pb.TagNumber(13)
  $core.List<$core.int> get callerCandidates => $_getN(11);
  @$pb.TagNumber(13)
  set callerCandidates($core.List<$core.int> v) { $_setBytes(11, v); }
  @$pb.TagNumber(13)
  $core.bool hasCallerCandidates() => $_has(11);
  @$pb.TagNumber(13)
  void clearCallerCandidates() => clearField(13);

  ///  The session cookie that the CALLER hands out (§17.4: "a valid AEAD
  ///  under `call_key` plus a session cookie"). 8 B. Frames that arrive AT THE
  ///  CALLER carry it; the callee stamps it on everything
  ///  he sends. §17.6: "the volunteer hands out two session cookies" -
  ///  two, not one, so that the two directions cannot be linked via a
  ///  single observed value.
  ///
  ///  Empty means: this caller sets up no level-D window. The
  ///  callee then admits no session instead of opening one with a
  ///  null cookie - eight zero bytes would be a cookie that anyone can
  ///  guess.
  @$pb.TagNumber(14)
  $core.List<$core.int> get callerDCookie => $_getN(12);
  @$pb.TagNumber(14)
  set callerDCookie($core.List<$core.int> v) { $_setBytes(12, v); }
  @$pb.TagNumber(14)
  $core.bool hasCallerDCookie() => $_has(12);
  @$pb.TagNumber(14)
  void clearCallerDCookie() => clearField(14);
}

class CallAnswer extends $pb.GeneratedMessage {
  factory CallAnswer({
    $core.List<$core.int>? callId,
    $core.List<$core.int>? calleeEphX25519Pk,
    $core.List<$core.int>? calleeKemCiphertext,
    $core.int? selectedAudioFormat,
    $core.int? selectedVideoFormat,
    $core.List<$core.int>? calleeCandidates,
    $core.List<$core.int>? calleeDCookie,
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
    if (selectedAudioFormat != null) {
      $result.selectedAudioFormat = selectedAudioFormat;
    }
    if (selectedVideoFormat != null) {
      $result.selectedVideoFormat = selectedVideoFormat;
    }
    if (calleeCandidates != null) {
      $result.calleeCandidates = calleeCandidates;
    }
    if (calleeDCookie != null) {
      $result.calleeDCookie = calleeDCookie;
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
    ..a<$core.int>(4, _omitFieldNames ? '' : 'selectedAudioFormat', $pb.PbFieldType.OU3)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'selectedVideoFormat', $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(6, _omitFieldNames ? '' : 'calleeCandidates', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(7, _omitFieldNames ? '' : 'calleeDCookie', $pb.PbFieldType.OY)
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

  ///  ── Media format negotiation, result (§10.4, V1.18) ────────────────
  ///
  ///  The format CHOSEN by the callee per media kind — the highest
  ///  that both sides speak. Before V1.18 `CallAnswer` carried no
  ///  version information at all (fields 1-3), so the capabilities of the callee
  ///  never reached the caller. Without this back channel the caller cannot
  ///  switch down, and "future backwards compatibility" stays
  ///  unreachable — regardless of how the format is encoded.
  ///
  ///  The caller checks the value against its own range and against what
  ///  it itself offered, and aborts on deviation with a visible reason.
  ///  A broken or malicious peer can thus not force a format
  ///  that the caller never offered.
  ///
  ///  If the field is missing (0), the same rule applies as with `CallInvite`: the
  ///  callee is a 3.2.0 build before V1.18 and has thus chosen base format 1.
  ///  A statement, not a gap.
  @$pb.TagNumber(4)
  $core.int get selectedAudioFormat => $_getIZ(3);
  @$pb.TagNumber(4)
  set selectedAudioFormat($core.int v) { $_setUnsignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasSelectedAudioFormat() => $_has(3);
  @$pb.TagNumber(4)
  void clearSelectedAudioFormat() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get selectedVideoFormat => $_getIZ(4);
  @$pb.TagNumber(5)
  set selectedVideoFormat($core.int v) { $_setUnsignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasSelectedVideoFormat() => $_has(4);
  @$pb.TagNumber(5)
  void clearSelectedVideoFormat() => clearField(5);

  ///  ── Address candidates and session cookie of the CALLEE (§17.3/§17.4)
  ///
  ///  Same form and same reasoning as `CallInvite.caller_candidates`
  ///  / `caller_d_cookie`; the ANSWER is the second half of the exchange.
  ///  Only with it do BOTH sides have `call_key` (which falls out of the
  ///  ephemeral DH plus KEM), both cookies and both candidate lists -
  ///  that is the point in time from which the punch window from §17.3 can run,
  ///  and on both sides at the same time.
  @$pb.TagNumber(6)
  $core.List<$core.int> get calleeCandidates => $_getN(5);
  @$pb.TagNumber(6)
  set calleeCandidates($core.List<$core.int> v) { $_setBytes(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasCalleeCandidates() => $_has(5);
  @$pb.TagNumber(6)
  void clearCalleeCandidates() => clearField(6);

  @$pb.TagNumber(7)
  $core.List<$core.int> get calleeDCookie => $_getN(6);
  @$pb.TagNumber(7)
  set calleeDCookie($core.List<$core.int> v) { $_setBytes(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasCalleeDCookie() => $_has(6);
  @$pb.TagNumber(7)
  void clearCalleeDCookie() => clearField(7);
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

///  CANCEL_OTHERS (§17.2) — the arbitration of the CALLER with several
///  devices of one identity.
///
///  §17.2: „an INVITE is **one** cell — all of the callee's devices harvest
///  the same tag line and ring … the first `ANSWER` binds the session to one
///  device, `CANCEL_OTHERS` (TTL 120 s) ends the ringing of the others."
///
///  Why the CALLER and not the answering device sends, and why the
///  ephemeral key is the recognition value: the file header of
///  `lib/core/calls/call_arbitration.dart`.
class CallCancelOthers extends $pb.GeneratedMessage {
  factory CallCancelOthers({
    $core.List<$core.int>? callId,
    $core.List<$core.int>? boundAnswerKey,
  }) {
    final $result = create();
    if (callId != null) {
      $result.callId = callId;
    }
    if (boundAnswerKey != null) {
      $result.boundAnswerKey = boundAnswerKey;
    }
    return $result;
  }
  CallCancelOthers._() : super();
  factory CallCancelOthers.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CallCancelOthers.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CallCancelOthers', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'callId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'boundAnswerKey', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CallCancelOthers clone() => CallCancelOthers()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CallCancelOthers copyWith(void Function(CallCancelOthers) updates) => super.copyWith((message) => updates(message as CallCancelOthers)) as CallCancelOthers;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CallCancelOthers create() => CallCancelOthers._();
  CallCancelOthers createEmptyInstance() => create();
  static $pb.PbList<CallCancelOthers> createRepeated() => $pb.PbList<CallCancelOthers>();
  @$core.pragma('dart2js:noInline')
  static CallCancelOthers getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CallCancelOthers>(create);
  static CallCancelOthers? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get callId => $_getN(0);
  @$pb.TagNumber(1)
  set callId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCallId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCallId() => clearField(1);

  ///  The ephemeral X25519 key of the callee from that ANSWER
  ///  which bound the session — 32 bytes.
  ///
  ///  It is the value by which the WINNING device recognises itself:
  ///  the cell goes to the identity and therefore also reaches the winner
  ///  (§14.2 — „One delivery serves all devices"). Without this value the
  ///  winner would hang up its own call.
  ///
  ///  NO device identifier. §14.1: the DeviceID is „not an addressing means";
  ///  keeping it here would mean writing it into a message to a CONTACT.
  ///  The ephemeral key says the same and reveals nothing that
  ///  the contact does not already know from the ANSWER — it is drawn fresh per call AND
  ///  per device and worthless after the call.
  ///
  ///  Empty is not a valid value: a CANCEL_OTHERS without binding key
  ///  would also take the call away from the winner. The recipient discards it.
  @$pb.TagNumber(2)
  $core.List<$core.int> get boundAnswerKey => $_getN(1);
  @$pb.TagNumber(2)
  set boundAnswerKey($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasBoundAnswerKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearBoundAnswerKey() => clearField(2);
}

///  RING_ACK (§17.2) — „it is really ringing at their end".
///
///  §17.2, paragraph „Caller state `reaching`": „After placing the INVITE, the
///  caller shows ,reaching …' — **no** ringtone. Ringtone and the 60-s answer
///  timeout start only once the callee's `RING_ACK` cell has been harvested."
///
///  Every ringing device of the callee sends one — the INVITE is ONE
///  cell to the identity and makes all devices ring (§14.2), so the
///  feedback comes N-fold. The caller needs only the first to switch from
///  state `reaching` to ringback tone; he counts the others.
class CallRingAck extends $pb.GeneratedMessage {
  factory CallRingAck({
    $core.List<$core.int>? callId,
    $core.List<$core.int>? deviceMarker,
  }) {
    final $result = create();
    if (callId != null) {
      $result.callId = callId;
    }
    if (deviceMarker != null) {
      $result.deviceMarker = deviceMarker;
    }
    return $result;
  }
  CallRingAck._() : super();
  factory CallRingAck.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CallRingAck.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CallRingAck', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'callId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'deviceMarker', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CallRingAck clone() => CallRingAck()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CallRingAck copyWith(void Function(CallRingAck) updates) => super.copyWith((message) => updates(message as CallRingAck)) as CallRingAck;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CallRingAck create() => CallRingAck._();
  CallRingAck createEmptyInstance() => create();
  static $pb.PbList<CallRingAck> createRepeated() => $pb.PbList<CallRingAck>();
  @$core.pragma('dart2js:noInline')
  static CallRingAck getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CallRingAck>(create);
  static CallRingAck? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get callId => $_getN(0);
  @$pb.TagNumber(1)
  set callId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCallId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCallId() => clearField(1);

  ///  Which device of the callee is ringing — 32 bytes, drawn fresh per call AND per
  ///  device.
  ///
  ///  §17.2 says verbatim at this place „`RING_ACK` carries the
  ///  `deviceId`". Here stands **no** DeviceID, and that is a deliberate,
  ///  justified deviation, not carelessness:
  ///
  ///    * §14.1 lists the DeviceID as „not an addressing means"; writing it into a
  ///      message to a CONTACT would contradict that.
  ///    * On the V4.1 delivery route there is none at all: §14.2 — „The delivery
  ///      path has **no device level**", and `HarvestEvent.senderDeviceId` is
  ///      `null` there (B-32, S349). A field that cannot be filled would be
  ///      a lie in the schema.
  ///    * What the clause is supposed to ACHIEVE, this value achieves completely: letting the
  ///      caller count how many different devices are ringing,
  ///      without him learning WHICH.
  ///
  ///  It is the same value that the later `CallAnswer` carries as
  ///  `callee_eph_x25519_pk` and that `CallCancelOthers` names — the
  ///  ephemeral X25519 key of this device for this call. One mark
  ///  across the whole call, not three.
  @$pb.TagNumber(2)
  $core.List<$core.int> get deviceMarker => $_getN(1);
  @$pb.TagNumber(2)
  set deviceMarker($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDeviceMarker() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeviceMarker() => clearField(2);
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
    $core.int? epochDay,
    $core.int? juryRound,
    $core.List<$core.int>? eligibilitySnapshotHash,
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
    if (epochDay != null) {
      $result.epochDay = epochDay;
    }
    if (juryRound != null) {
      $result.juryRound = juryRound;
    }
    if (eligibilitySnapshotHash != null) {
      $result.eligibilitySnapshotHash = eligibilitySnapshotHash;
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
    ..a<$core.int>(9, _omitFieldNames ? '' : 'epochDay', $pb.PbFieldType.OU3)
    ..a<$core.int>(10, _omitFieldNames ? '' : 'juryRound', $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(11, _omitFieldNames ? '' : 'eligibilitySnapshotHash', $pb.PbFieldType.OY)
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

  @$pb.TagNumber(9)
  $core.int get epochDay => $_getIZ(8);
  @$pb.TagNumber(9)
  set epochDay($core.int v) { $_setUnsignedInt32(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasEpochDay() => $_has(8);
  @$pb.TagNumber(9)
  void clearEpochDay() => clearField(9);

  @$pb.TagNumber(10)
  $core.int get juryRound => $_getIZ(9);
  @$pb.TagNumber(10)
  set juryRound($core.int v) { $_setUnsignedInt32(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasJuryRound() => $_has(9);
  @$pb.TagNumber(10)
  void clearJuryRound() => clearField(10);

  @$pb.TagNumber(11)
  $core.List<$core.int> get eligibilitySnapshotHash => $_getN(10);
  @$pb.TagNumber(11)
  set eligibilitySnapshotHash($core.List<$core.int> v) { $_setBytes(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasEligibilitySnapshotHash() => $_has(10);
  @$pb.TagNumber(11)
  void clearEligibilitySnapshotHash() => clearField(11);
}

class JuryVoteMsg extends $pb.GeneratedMessage {
  factory JuryVoteMsg({
    $core.List<$core.int>? juryId,
    $core.List<$core.int>? reportId,
    $core.int? vote,
    $core.String? reason,
    $core.List<$core.int>? sigEd25519,
    $core.List<$core.int>? sigMlDsa,
    $core.int? juryRound,
    $core.int? epochDay,
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
    if (sigEd25519 != null) {
      $result.sigEd25519 = sigEd25519;
    }
    if (sigMlDsa != null) {
      $result.sigMlDsa = sigMlDsa;
    }
    if (juryRound != null) {
      $result.juryRound = juryRound;
    }
    if (epochDay != null) {
      $result.epochDay = epochDay;
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
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'sigEd25519', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(6, _omitFieldNames ? '' : 'sigMlDsa', $pb.PbFieldType.OY)
    ..a<$core.int>(7, _omitFieldNames ? '' : 'juryRound', $pb.PbFieldType.OU3)
    ..a<$core.int>(8, _omitFieldNames ? '' : 'epochDay', $pb.PbFieldType.OU3)
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

  @$pb.TagNumber(5)
  $core.List<$core.int> get sigEd25519 => $_getN(4);
  @$pb.TagNumber(5)
  set sigEd25519($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasSigEd25519() => $_has(4);
  @$pb.TagNumber(5)
  void clearSigEd25519() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get sigMlDsa => $_getN(5);
  @$pb.TagNumber(6)
  set sigMlDsa($core.List<$core.int> v) { $_setBytes(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasSigMlDsa() => $_has(5);
  @$pb.TagNumber(6)
  void clearSigMlDsa() => clearField(6);

  @$pb.TagNumber(7)
  $core.int get juryRound => $_getIZ(6);
  @$pb.TagNumber(7)
  set juryRound($core.int v) { $_setUnsignedInt32(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasJuryRound() => $_has(6);
  @$pb.TagNumber(7)
  void clearJuryRound() => clearField(7);

  @$pb.TagNumber(8)
  $core.int get epochDay => $_getIZ(7);
  @$pb.TagNumber(8)
  set epochDay($core.int v) { $_setUnsignedInt32(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasEpochDay() => $_has(7);
  @$pb.TagNumber(8)
  void clearEpochDay() => clearField(8);
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
    $core.Iterable<JurorVerdictSig>? jurorSigs,
    $core.List<$core.int>? eligibilitySnapshotHash,
    $core.int? epochDay,
    $core.int? juryRound,
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
    if (jurorSigs != null) {
      $result.jurorSigs.addAll(jurorSigs);
    }
    if (eligibilitySnapshotHash != null) {
      $result.eligibilitySnapshotHash = eligibilitySnapshotHash;
    }
    if (epochDay != null) {
      $result.epochDay = epochDay;
    }
    if (juryRound != null) {
      $result.juryRound = juryRound;
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
    ..pc<JurorVerdictSig>(9, _omitFieldNames ? '' : 'jurorSigs', $pb.PbFieldType.PM, subBuilder: JurorVerdictSig.create)
    ..a<$core.List<$core.int>>(10, _omitFieldNames ? '' : 'eligibilitySnapshotHash', $pb.PbFieldType.OY)
    ..a<$core.int>(11, _omitFieldNames ? '' : 'epochDay', $pb.PbFieldType.OU3)
    ..a<$core.int>(12, _omitFieldNames ? '' : 'juryRound', $pb.PbFieldType.OU3)
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

  @$pb.TagNumber(9)
  $core.List<JurorVerdictSig> get jurorSigs => $_getList(8);

  @$pb.TagNumber(10)
  $core.List<$core.int> get eligibilitySnapshotHash => $_getN(9);
  @$pb.TagNumber(10)
  set eligibilitySnapshotHash($core.List<$core.int> v) { $_setBytes(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasEligibilitySnapshotHash() => $_has(9);
  @$pb.TagNumber(10)
  void clearEligibilitySnapshotHash() => clearField(10);

  @$pb.TagNumber(11)
  $core.int get epochDay => $_getIZ(10);
  @$pb.TagNumber(11)
  set epochDay($core.int v) { $_setUnsignedInt32(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasEpochDay() => $_has(10);
  @$pb.TagNumber(11)
  void clearEpochDay() => clearField(11);

  @$pb.TagNumber(12)
  $core.int get juryRound => $_getIZ(11);
  @$pb.TagNumber(12)
  set juryRound($core.int v) { $_setUnsignedInt32(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasJuryRound() => $_has(11);
  @$pb.TagNumber(12)
  void clearJuryRound() => clearField(12);
}

class JurorVerdictSig extends $pb.GeneratedMessage {
  factory JurorVerdictSig({
    $core.List<$core.int>? jurorUserId,
    $core.List<$core.int>? sigEd25519,
    $core.List<$core.int>? sigMlDsa,
    $core.int? vote,
  }) {
    final $result = create();
    if (jurorUserId != null) {
      $result.jurorUserId = jurorUserId;
    }
    if (sigEd25519 != null) {
      $result.sigEd25519 = sigEd25519;
    }
    if (sigMlDsa != null) {
      $result.sigMlDsa = sigMlDsa;
    }
    if (vote != null) {
      $result.vote = vote;
    }
    return $result;
  }
  JurorVerdictSig._() : super();
  factory JurorVerdictSig.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory JurorVerdictSig.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'JurorVerdictSig', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'jurorUserId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'sigEd25519', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'sigMlDsa', $pb.PbFieldType.OY)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'vote', $pb.PbFieldType.OU3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  JurorVerdictSig clone() => JurorVerdictSig()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  JurorVerdictSig copyWith(void Function(JurorVerdictSig) updates) => super.copyWith((message) => updates(message as JurorVerdictSig)) as JurorVerdictSig;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static JurorVerdictSig create() => JurorVerdictSig._();
  JurorVerdictSig createEmptyInstance() => create();
  static $pb.PbList<JurorVerdictSig> createRepeated() => $pb.PbList<JurorVerdictSig>();
  @$core.pragma('dart2js:noInline')
  static JurorVerdictSig getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<JurorVerdictSig>(create);
  static JurorVerdictSig? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get jurorUserId => $_getN(0);
  @$pb.TagNumber(1)
  set jurorUserId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasJurorUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearJurorUserId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get sigEd25519 => $_getN(1);
  @$pb.TagNumber(2)
  set sigEd25519($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSigEd25519() => $_has(1);
  @$pb.TagNumber(2)
  void clearSigEd25519() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get sigMlDsa => $_getN(2);
  @$pb.TagNumber(3)
  set sigMlDsa($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSigMlDsa() => $_has(2);
  @$pb.TagNumber(3)
  void clearSigMlDsa() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get vote => $_getIZ(3);
  @$pb.TagNumber(4)
  set vote($core.int v) { $_setUnsignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasVote() => $_has(3);
  @$pb.TagNumber(4)
  void clearVote() => clearField(4);
}

class JurorAvailabilityRecord extends $pb.GeneratedMessage {
  factory JurorAvailabilityRecord({
    $core.List<$core.int>? userPubKeyEd25519,
    $core.List<$core.int>? userPubKeyMlDsa,
    $fixnum.Int64? creationEpochMs,
    $core.List<$core.int>? selfSigEd25519,
    $core.List<$core.int>? selfSigMlDsa,
    $fixnum.Int64? publishedAtMs,
  }) {
    final $result = create();
    if (userPubKeyEd25519 != null) {
      $result.userPubKeyEd25519 = userPubKeyEd25519;
    }
    if (userPubKeyMlDsa != null) {
      $result.userPubKeyMlDsa = userPubKeyMlDsa;
    }
    if (creationEpochMs != null) {
      $result.creationEpochMs = creationEpochMs;
    }
    if (selfSigEd25519 != null) {
      $result.selfSigEd25519 = selfSigEd25519;
    }
    if (selfSigMlDsa != null) {
      $result.selfSigMlDsa = selfSigMlDsa;
    }
    if (publishedAtMs != null) {
      $result.publishedAtMs = publishedAtMs;
    }
    return $result;
  }
  JurorAvailabilityRecord._() : super();
  factory JurorAvailabilityRecord.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory JurorAvailabilityRecord.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'JurorAvailabilityRecord', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'userPubKeyEd25519', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'userPubKeyMlDsa', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(3, _omitFieldNames ? '' : 'creationEpochMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'selfSigEd25519', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'selfSigMlDsa', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(6, _omitFieldNames ? '' : 'publishedAtMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  JurorAvailabilityRecord clone() => JurorAvailabilityRecord()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  JurorAvailabilityRecord copyWith(void Function(JurorAvailabilityRecord) updates) => super.copyWith((message) => updates(message as JurorAvailabilityRecord)) as JurorAvailabilityRecord;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static JurorAvailabilityRecord create() => JurorAvailabilityRecord._();
  JurorAvailabilityRecord createEmptyInstance() => create();
  static $pb.PbList<JurorAvailabilityRecord> createRepeated() => $pb.PbList<JurorAvailabilityRecord>();
  @$core.pragma('dart2js:noInline')
  static JurorAvailabilityRecord getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<JurorAvailabilityRecord>(create);
  static JurorAvailabilityRecord? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get userPubKeyEd25519 => $_getN(0);
  @$pb.TagNumber(1)
  set userPubKeyEd25519($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasUserPubKeyEd25519() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserPubKeyEd25519() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get userPubKeyMlDsa => $_getN(1);
  @$pb.TagNumber(2)
  set userPubKeyMlDsa($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasUserPubKeyMlDsa() => $_has(1);
  @$pb.TagNumber(2)
  void clearUserPubKeyMlDsa() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get creationEpochMs => $_getI64(2);
  @$pb.TagNumber(3)
  set creationEpochMs($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasCreationEpochMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearCreationEpochMs() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get selfSigEd25519 => $_getN(3);
  @$pb.TagNumber(4)
  set selfSigEd25519($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasSelfSigEd25519() => $_has(3);
  @$pb.TagNumber(4)
  void clearSelfSigEd25519() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get selfSigMlDsa => $_getN(4);
  @$pb.TagNumber(5)
  set selfSigMlDsa($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasSelfSigMlDsa() => $_has(4);
  @$pb.TagNumber(5)
  void clearSelfSigMlDsa() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get publishedAtMs => $_getI64(5);
  @$pb.TagNumber(6)
  set publishedAtMs($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasPublishedAtMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearPublishedAtMs() => clearField(6);
}

class ModerationProofRecord extends $pb.GeneratedMessage {
  factory ModerationProofRecord({
    $core.List<$core.int>? channelId,
    $core.List<$core.int>? juryId,
    $core.List<$core.int>? reportId,
    $core.int? consequence,
    $core.int? epochDay,
    $core.int? juryRound,
    $core.Iterable<JurorVerdictSig>? jurorSigs,
    $core.List<$core.int>? eligibilitySnapshotHash,
  }) {
    final $result = create();
    if (channelId != null) {
      $result.channelId = channelId;
    }
    if (juryId != null) {
      $result.juryId = juryId;
    }
    if (reportId != null) {
      $result.reportId = reportId;
    }
    if (consequence != null) {
      $result.consequence = consequence;
    }
    if (epochDay != null) {
      $result.epochDay = epochDay;
    }
    if (juryRound != null) {
      $result.juryRound = juryRound;
    }
    if (jurorSigs != null) {
      $result.jurorSigs.addAll(jurorSigs);
    }
    if (eligibilitySnapshotHash != null) {
      $result.eligibilitySnapshotHash = eligibilitySnapshotHash;
    }
    return $result;
  }
  ModerationProofRecord._() : super();
  factory ModerationProofRecord.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModerationProofRecord.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ModerationProofRecord', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'channelId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'juryId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'reportId', $pb.PbFieldType.OY)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'consequence', $pb.PbFieldType.OU3)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'epochDay', $pb.PbFieldType.OU3)
    ..a<$core.int>(6, _omitFieldNames ? '' : 'juryRound', $pb.PbFieldType.OU3)
    ..pc<JurorVerdictSig>(7, _omitFieldNames ? '' : 'jurorSigs', $pb.PbFieldType.PM, subBuilder: JurorVerdictSig.create)
    ..a<$core.List<$core.int>>(8, _omitFieldNames ? '' : 'eligibilitySnapshotHash', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModerationProofRecord clone() => ModerationProofRecord()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModerationProofRecord copyWith(void Function(ModerationProofRecord) updates) => super.copyWith((message) => updates(message as ModerationProofRecord)) as ModerationProofRecord;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModerationProofRecord create() => ModerationProofRecord._();
  ModerationProofRecord createEmptyInstance() => create();
  static $pb.PbList<ModerationProofRecord> createRepeated() => $pb.PbList<ModerationProofRecord>();
  @$core.pragma('dart2js:noInline')
  static ModerationProofRecord getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModerationProofRecord>(create);
  static ModerationProofRecord? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get channelId => $_getN(0);
  @$pb.TagNumber(1)
  set channelId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasChannelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChannelId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get juryId => $_getN(1);
  @$pb.TagNumber(2)
  set juryId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasJuryId() => $_has(1);
  @$pb.TagNumber(2)
  void clearJuryId() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get reportId => $_getN(2);
  @$pb.TagNumber(3)
  set reportId($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasReportId() => $_has(2);
  @$pb.TagNumber(3)
  void clearReportId() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get consequence => $_getIZ(3);
  @$pb.TagNumber(4)
  set consequence($core.int v) { $_setUnsignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasConsequence() => $_has(3);
  @$pb.TagNumber(4)
  void clearConsequence() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get epochDay => $_getIZ(4);
  @$pb.TagNumber(5)
  set epochDay($core.int v) { $_setUnsignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasEpochDay() => $_has(4);
  @$pb.TagNumber(5)
  void clearEpochDay() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get juryRound => $_getIZ(5);
  @$pb.TagNumber(6)
  set juryRound($core.int v) { $_setUnsignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasJuryRound() => $_has(5);
  @$pb.TagNumber(6)
  void clearJuryRound() => clearField(6);

  @$pb.TagNumber(7)
  $core.List<JurorVerdictSig> get jurorSigs => $_getList(6);

  @$pb.TagNumber(8)
  $core.List<$core.int> get eligibilitySnapshotHash => $_getN(7);
  @$pb.TagNumber(8)
  set eligibilitySnapshotHash($core.List<$core.int> v) { $_setBytes(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasEligibilitySnapshotHash() => $_has(7);
  @$pb.TagNumber(8)
  void clearEligibilitySnapshotHash() => clearField(8);
}

class CsamReporterQuorumProof extends $pb.GeneratedMessage {
  factory CsamReporterQuorumProof({
    $core.List<$core.int>? channelId,
    $core.Iterable<CsamReportSig>? reporterSigs,
  }) {
    final $result = create();
    if (channelId != null) {
      $result.channelId = channelId;
    }
    if (reporterSigs != null) {
      $result.reporterSigs.addAll(reporterSigs);
    }
    return $result;
  }
  CsamReporterQuorumProof._() : super();
  factory CsamReporterQuorumProof.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CsamReporterQuorumProof.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CsamReporterQuorumProof', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'channelId', $pb.PbFieldType.OY)
    ..pc<CsamReportSig>(2, _omitFieldNames ? '' : 'reporterSigs', $pb.PbFieldType.PM, subBuilder: CsamReportSig.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CsamReporterQuorumProof clone() => CsamReporterQuorumProof()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CsamReporterQuorumProof copyWith(void Function(CsamReporterQuorumProof) updates) => super.copyWith((message) => updates(message as CsamReporterQuorumProof)) as CsamReporterQuorumProof;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CsamReporterQuorumProof create() => CsamReporterQuorumProof._();
  CsamReporterQuorumProof createEmptyInstance() => create();
  static $pb.PbList<CsamReporterQuorumProof> createRepeated() => $pb.PbList<CsamReporterQuorumProof>();
  @$core.pragma('dart2js:noInline')
  static CsamReporterQuorumProof getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CsamReporterQuorumProof>(create);
  static CsamReporterQuorumProof? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get channelId => $_getN(0);
  @$pb.TagNumber(1)
  set channelId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasChannelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChannelId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<CsamReportSig> get reporterSigs => $_getList(1);
}

class CsamReportSig extends $pb.GeneratedMessage {
  factory CsamReportSig({
    $core.List<$core.int>? reporterUserId,
    $core.List<$core.int>? sigEd25519,
    $core.List<$core.int>? sigMlDsa,
    $core.List<$core.int>? reportId,
    $fixnum.Int64? reportedAtMs,
  }) {
    final $result = create();
    if (reporterUserId != null) {
      $result.reporterUserId = reporterUserId;
    }
    if (sigEd25519 != null) {
      $result.sigEd25519 = sigEd25519;
    }
    if (sigMlDsa != null) {
      $result.sigMlDsa = sigMlDsa;
    }
    if (reportId != null) {
      $result.reportId = reportId;
    }
    if (reportedAtMs != null) {
      $result.reportedAtMs = reportedAtMs;
    }
    return $result;
  }
  CsamReportSig._() : super();
  factory CsamReportSig.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CsamReportSig.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CsamReportSig', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'reporterUserId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'sigEd25519', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'sigMlDsa', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'reportId', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(5, _omitFieldNames ? '' : 'reportedAtMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CsamReportSig clone() => CsamReportSig()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CsamReportSig copyWith(void Function(CsamReportSig) updates) => super.copyWith((message) => updates(message as CsamReportSig)) as CsamReportSig;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CsamReportSig create() => CsamReportSig._();
  CsamReportSig createEmptyInstance() => create();
  static $pb.PbList<CsamReportSig> createRepeated() => $pb.PbList<CsamReportSig>();
  @$core.pragma('dart2js:noInline')
  static CsamReportSig getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CsamReportSig>(create);
  static CsamReportSig? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get reporterUserId => $_getN(0);
  @$pb.TagNumber(1)
  set reporterUserId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasReporterUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearReporterUserId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get sigEd25519 => $_getN(1);
  @$pb.TagNumber(2)
  set sigEd25519($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSigEd25519() => $_has(1);
  @$pb.TagNumber(2)
  void clearSigEd25519() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get sigMlDsa => $_getN(2);
  @$pb.TagNumber(3)
  set sigMlDsa($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSigMlDsa() => $_has(2);
  @$pb.TagNumber(3)
  void clearSigMlDsa() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get reportId => $_getN(3);
  @$pb.TagNumber(4)
  set reportId($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasReportId() => $_has(3);
  @$pb.TagNumber(4)
  void clearReportId() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get reportedAtMs => $_getI64(4);
  @$pb.TagNumber(5)
  set reportedAtMs($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasReportedAtMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearReportedAtMs() => clearField(5);
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
    $core.List<$core.int>? moderationProofHash,
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
    if (moderationProofHash != null) {
      $result.moderationProofHash = moderationProofHash;
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
    ..a<$core.List<$core.int>>(13, _omitFieldNames ? '' : 'moderationProofHash', $pb.PbFieldType.OY)
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

  @$pb.TagNumber(13)
  $core.List<$core.int> get moderationProofHash => $_getN(12);
  @$pb.TagNumber(13)
  set moderationProofHash($core.List<$core.int> v) { $_setBytes(12, v); }
  @$pb.TagNumber(13)
  $core.bool hasModerationProofHash() => $_has(12);
  @$pb.TagNumber(13)
  void clearModerationProofHash() => clearField(13);
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

///  ── Two-Stage Media Stage-2 (V3) ────────────────────────────────────
///
///  MEDIA_ANNOUNCE (Stage 1) carries metadata + thumbnail. The receiver
///  then asks for the actual content via MTV3_MEDIA_REQUEST (payload =
///  original messageId bytes). The sender splits the file into
///  MediaChunkV3 frames, each shipped as its own ApplicationFrameV3
///  (per-chunk KEM-encrypted via sendToUser), and finalises with a
///  MediaCompleteV3 carrying the SHA-256 of the assembled bytes for
///  receiver-side integrity-check. Architecture §5.7 + §1797.
class MediaChunkV3 extends $pb.GeneratedMessage {
  factory MediaChunkV3({
    $core.List<$core.int>? mediaId,
    $core.int? chunkIndex,
    $core.int? totalChunks,
    $core.List<$core.int>? data,
  }) {
    final $result = create();
    if (mediaId != null) {
      $result.mediaId = mediaId;
    }
    if (chunkIndex != null) {
      $result.chunkIndex = chunkIndex;
    }
    if (totalChunks != null) {
      $result.totalChunks = totalChunks;
    }
    if (data != null) {
      $result.data = data;
    }
    return $result;
  }
  MediaChunkV3._() : super();
  factory MediaChunkV3.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MediaChunkV3.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MediaChunkV3', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'mediaId', $pb.PbFieldType.OY)
    ..a<$core.int>(2, _omitFieldNames ? '' : 'chunkIndex', $pb.PbFieldType.OU3)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'totalChunks', $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MediaChunkV3 clone() => MediaChunkV3()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MediaChunkV3 copyWith(void Function(MediaChunkV3) updates) => super.copyWith((message) => updates(message as MediaChunkV3)) as MediaChunkV3;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MediaChunkV3 create() => MediaChunkV3._();
  MediaChunkV3 createEmptyInstance() => create();
  static $pb.PbList<MediaChunkV3> createRepeated() => $pb.PbList<MediaChunkV3>();
  @$core.pragma('dart2js:noInline')
  static MediaChunkV3 getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MediaChunkV3>(create);
  static MediaChunkV3? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get mediaId => $_getN(0);
  @$pb.TagNumber(1)
  set mediaId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMediaId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMediaId() => clearField(1);

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
  $core.List<$core.int> get data => $_getN(3);
  @$pb.TagNumber(4)
  set data($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasData() => $_has(3);
  @$pb.TagNumber(4)
  void clearData() => clearField(4);
}

class MediaCompleteV3 extends $pb.GeneratedMessage {
  factory MediaCompleteV3({
    $core.List<$core.int>? mediaId,
    $core.List<$core.int>? contentHash,
    $fixnum.Int64? totalSize,
  }) {
    final $result = create();
    if (mediaId != null) {
      $result.mediaId = mediaId;
    }
    if (contentHash != null) {
      $result.contentHash = contentHash;
    }
    if (totalSize != null) {
      $result.totalSize = totalSize;
    }
    return $result;
  }
  MediaCompleteV3._() : super();
  factory MediaCompleteV3.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MediaCompleteV3.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MediaCompleteV3', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'mediaId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'contentHash', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(3, _omitFieldNames ? '' : 'totalSize', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MediaCompleteV3 clone() => MediaCompleteV3()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MediaCompleteV3 copyWith(void Function(MediaCompleteV3) updates) => super.copyWith((message) => updates(message as MediaCompleteV3)) as MediaCompleteV3;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MediaCompleteV3 create() => MediaCompleteV3._();
  MediaCompleteV3 createEmptyInstance() => create();
  static $pb.PbList<MediaCompleteV3> createRepeated() => $pb.PbList<MediaCompleteV3>();
  @$core.pragma('dart2js:noInline')
  static MediaCompleteV3 getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MediaCompleteV3>(create);
  static MediaCompleteV3? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get mediaId => $_getN(0);
  @$pb.TagNumber(1)
  set mediaId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMediaId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMediaId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get contentHash => $_getN(1);
  @$pb.TagNumber(2)
  set contentHash($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasContentHash() => $_has(1);
  @$pb.TagNumber(2)
  void clearContentHash() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get totalSize => $_getI64(2);
  @$pb.TagNumber(3)
  set totalSize($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTotalSize() => $_has(2);
  @$pb.TagNumber(3)
  void clearTotalSize() => clearField(3);
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

/// The sender's own media state inside a call (§10.6). Sent whenever the
/// sender's own video starts or stops, and never on the peer's behalf (I12).
class CallMediaState extends $pb.GeneratedMessage {
  factory CallMediaState({
    $core.List<$core.int>? callId,
    $core.bool? sendingVideo,
    VideoOffReason? videoOffReason,
    $fixnum.Int64? stateSeq,
  }) {
    final $result = create();
    if (callId != null) {
      $result.callId = callId;
    }
    if (sendingVideo != null) {
      $result.sendingVideo = sendingVideo;
    }
    if (videoOffReason != null) {
      $result.videoOffReason = videoOffReason;
    }
    if (stateSeq != null) {
      $result.stateSeq = stateSeq;
    }
    return $result;
  }
  CallMediaState._() : super();
  factory CallMediaState.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CallMediaState.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CallMediaState', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'callId', $pb.PbFieldType.OY)
    ..aOB(2, _omitFieldNames ? '' : 'sendingVideo')
    ..e<VideoOffReason>(3, _omitFieldNames ? '' : 'videoOffReason', $pb.PbFieldType.OE, defaultOrMaker: VideoOffReason.VIDEO_OFF_REASON_UNSPECIFIED, valueOf: VideoOffReason.valueOf, enumValues: VideoOffReason.values)
    ..a<$fixnum.Int64>(4, _omitFieldNames ? '' : 'stateSeq', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CallMediaState clone() => CallMediaState()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CallMediaState copyWith(void Function(CallMediaState) updates) => super.copyWith((message) => updates(message as CallMediaState)) as CallMediaState;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CallMediaState create() => CallMediaState._();
  CallMediaState createEmptyInstance() => create();
  static $pb.PbList<CallMediaState> createRepeated() => $pb.PbList<CallMediaState>();
  @$core.pragma('dart2js:noInline')
  static CallMediaState getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CallMediaState>(create);
  static CallMediaState? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get callId => $_getN(0);
  @$pb.TagNumber(1)
  set callId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCallId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCallId() => clearField(1);

  /// "I am sending video." False means the peer should render the state in
  /// video_off_reason instead of the last received frame — the frozen picture
  /// is what this message exists to prevent.
  @$pb.TagNumber(2)
  $core.bool get sendingVideo => $_getBF(1);
  @$pb.TagNumber(2)
  set sendingVideo($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSendingVideo() => $_has(1);
  @$pb.TagNumber(2)
  void clearSendingVideo() => clearField(2);

  /// Only meaningful while sending_video == false. Senders set
  /// VIDEO_OFF_REASON_UNSPECIFIED while sending_video == true, and receivers
  /// ignore the field in that case.
  @$pb.TagNumber(3)
  VideoOffReason get videoOffReason => $_getN(2);
  @$pb.TagNumber(3)
  set videoOffReason(VideoOffReason v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasVideoOffReason() => $_has(2);
  @$pb.TagNumber(3)
  void clearVideoOffReason() => clearField(3);

  /// Monotonic per (call_id, sender), starting at 1. The state travels over an
  /// unordered datagram network, so a reordered older frame would otherwise
  /// reinstate a stale "video off" while frames are arriving — precisely the
  /// wrong picture. Receivers accept strictly greater values only. Same role
  /// as GroupCallKeyRotate.key_version and CallTreeUpdate.version.
  @$pb.TagNumber(4)
  $fixnum.Int64 get stateSeq => $_getI64(3);
  @$pb.TagNumber(4)
  set stateSeq($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasStateSeq() => $_has(3);
  @$pb.TagNumber(4)
  void clearStateSeq() => clearField(4);
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

/// S368: `message GroupCallKeyRotate` has been removed. It carried the rotating
/// SHARED group key that §10.2.1 replaced with per-sender keys;
/// its receive handler has since been a no-op that only
/// existed so that an older counterpart may send the type.
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

/// Per-sender media key announcement (Architecture §10.2.1). Each participant
/// generates a secret 256-bit send_key known only to itself and announces it,
/// dual-signed + KEM-encrypted (setup-class ApplicationFrame), to every other
/// participant. Receivers map sender_node_id -> send_key and decrypt that
/// sender's media frames with it. Because send_key is secret to its owner, a
/// relaying co-participant cannot forge frames as another sender. Replaces the
/// shared group_call_key media role (CallInvite.group_call_key, deprecated for
/// group media). key_version bumps on rotation (membership change / rejoin).
class GroupCallSenderKey extends $pb.GeneratedMessage {
  factory GroupCallSenderKey({
    $core.List<$core.int>? callId,
    $core.List<$core.int>? senderNodeId,
    $core.List<$core.int>? sendKey,
    $core.int? keyVersion,
    $core.List<$core.int>? dEphX25519Pk,
    $core.List<$core.int>? dKemCiphertext,
    $core.List<$core.int>? dCookie,
    $core.List<$core.int>? dCandidates,
    $core.Iterable<$core.List<$core.int>>? joinedParticipants,
  }) {
    final $result = create();
    if (callId != null) {
      $result.callId = callId;
    }
    if (senderNodeId != null) {
      $result.senderNodeId = senderNodeId;
    }
    if (sendKey != null) {
      $result.sendKey = sendKey;
    }
    if (keyVersion != null) {
      $result.keyVersion = keyVersion;
    }
    if (dEphX25519Pk != null) {
      $result.dEphX25519Pk = dEphX25519Pk;
    }
    if (dKemCiphertext != null) {
      $result.dKemCiphertext = dKemCiphertext;
    }
    if (dCookie != null) {
      $result.dCookie = dCookie;
    }
    if (dCandidates != null) {
      $result.dCandidates = dCandidates;
    }
    if (joinedParticipants != null) {
      $result.joinedParticipants.addAll(joinedParticipants);
    }
    return $result;
  }
  GroupCallSenderKey._() : super();
  factory GroupCallSenderKey.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GroupCallSenderKey.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GroupCallSenderKey', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'callId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'senderNodeId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'sendKey', $pb.PbFieldType.OY)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'keyVersion', $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'dEphX25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(6, _omitFieldNames ? '' : 'dKemCiphertext', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(7, _omitFieldNames ? '' : 'dCookie', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(8, _omitFieldNames ? '' : 'dCandidates', $pb.PbFieldType.OY)
    ..p<$core.List<$core.int>>(9, _omitFieldNames ? '' : 'joinedParticipants', $pb.PbFieldType.PY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GroupCallSenderKey clone() => GroupCallSenderKey()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GroupCallSenderKey copyWith(void Function(GroupCallSenderKey) updates) => super.copyWith((message) => updates(message as GroupCallSenderKey)) as GroupCallSenderKey;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GroupCallSenderKey create() => GroupCallSenderKey._();
  GroupCallSenderKey createEmptyInstance() => create();
  static $pb.PbList<GroupCallSenderKey> createRepeated() => $pb.PbList<GroupCallSenderKey>();
  @$core.pragma('dart2js:noInline')
  static GroupCallSenderKey getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GroupCallSenderKey>(create);
  static GroupCallSenderKey? _defaultInstance;

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
  $core.List<$core.int> get sendKey => $_getN(2);
  @$pb.TagNumber(3)
  set sendKey($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSendKey() => $_has(2);
  @$pb.TagNumber(3)
  void clearSendKey() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get keyVersion => $_getIZ(3);
  @$pb.TagNumber(4)
  set keyVersion($core.int v) { $_setUnsignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasKeyVersion() => $_has(3);
  @$pb.TagNumber(4)
  void clearKeyVersion() => clearField(4);

  /// The ephemeral X25519 share of the sender for THIS call. One per
  /// call and device, not one per pair: every pair nevertheless gets its own
  /// DH result, because the counter-share differs per pair.
  /// The same value as `CallAnswer.callee_eph_x25519_pk` (17.2) -- it is
  /// at the same time the binding mark of the multi-device arbitration.
  @$pb.TagNumber(5)
  $core.List<$core.int> get dEphX25519Pk => $_getN(4);
  @$pb.TagNumber(5)
  set dEphX25519Pk($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasDEphX25519Pk() => $_has(4);
  @$pb.TagNumber(5)
  void clearDEphX25519Pk() => clearField(5);

  /// ML-KEM-768 ciphertext, encapsulated to the STATIC ML-KEM key of the
  /// recipient (`ContactInfo.mlKemPk`), exactly as in the 1:1 path
  /// (`CallInvite.caller_kem_ciphertext`). The static share is the
  /// reason why a third party cannot form the pair key -- not even
  /// the initiator, through whose hands the round below runs:
  /// only the recipient can decapsulate.
  @$pb.TagNumber(6)
  $core.List<$core.int> get dKemCiphertext => $_getN(5);
  @$pb.TagNumber(6)
  set dKemCiphertext($core.List<$core.int> v) { $_setBytes(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasDKemCiphertext() => $_has(5);
  @$pb.TagNumber(6)
  void clearDKemCiphertext() => clearField(6);

  /// The session cookie (17.4, 8 B) that the SENDER expects for this pair.
  /// ONE OF ITS OWN PER PAIR: the D socket keeps its
  /// session table by the local cookie and throws on reuse
  /// ("is already admitted"). A call with one cookie for all would have
  /// exactly one session, and the demux would assign the frames of all participants
  /// to the same counterpart.
  @$pb.TagNumber(7)
  $core.List<$core.int> get dCookie => $_getN(6);
  @$pb.TagNumber(7)
  set dCookie($core.List<$core.int> v) { $_setBytes(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasDCookie() => $_has(6);
  @$pb.TagNumber(7)
  void clearDCookie() => clearField(7);

  /// The packed address candidates of the sender (17.3), the same format
  /// as `CallInvite.caller_candidates`.
  @$pb.TagNumber(8)
  $core.List<$core.int> get dCandidates => $_getN(7);
  @$pb.TagNumber(8)
  set dCandidates($core.List<$core.int> v) { $_setBytes(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasDCandidates() => $_has(7);
  @$pb.TagNumber(8)
  void clearDCandidates() => clearField(8);

  ///  == THE ROUND THAT THE SENDER KNOWS AS JOINED ==============
  ///
  ///  Only the INITIATOR fills the field; for all others it is empty.
  ///
  ///  WHAT FOR. Measured on 06.09.2026 at state 11c1756b: a participant who is
  ///  not the initiator NEVER learns that another non-initiator
  ///  has joined. The INVITE reception sets all members except the
  ///  sender to `invited`; the ANSWER reaches exclusively the
  ///  initiator; and the forwarding tree does carry the round, but arrives
  ///  nowhere, because its carrier hard-returns `noCarrier`.
  ///  Thus the set of those joined stayed at every non-initiator
  ///  forever {me, initiator} -- and 10.2.1 itself breaks on that: in a
  ///  probe with three participants the second did not have the `send_key` of the third
  ///  and could not decrypt their frames at all. Without the
  ///  round there is neither the sender key meshing nor the
  ///  pair keys of this decision.
  ///
  ///  WHY HERE AND NOT IN THE TREE UPDATE. Because this message arrives and
  ///  that one does not. The forwarding tree is moreover a statement about
  ///  the MEDIA FORM (17.7) and changes with every speaker or
  ///  presentation change; the round is a statement about the
  ///  MEMBERSHIP and changes only on joining and leaving.
  ///
  ///  TRUST. The list is a third-party statement of the initiator -- he is
  ///  the arbiter anyway per 17.2 and the root per 17.7. It
  ///  carries no authorisation: a wrongly named participant
  ///  merely gets an address that ends in no pair key,
  ///  because he cannot deliver the counter-material. The OPPOSITE direction
  ///  -- "I have joined" -- does not stand here at all: it is the
  ///  self-statement that EVERY authenticated cell of this kind makes anyway,
  ///  and the receive path already checks it against the outer identifier.
  @$pb.TagNumber(9)
  $core.List<$core.List<$core.int>> get joinedParticipants => $_getList(8);
}

/// Whiteboard stroke data — real-time streaming via Overlay Multicast Tree.
/// MTV3_WHITEBOARD_STROKE = 210
class WhiteboardStroke extends $pb.GeneratedMessage {
  factory WhiteboardStroke({
    $core.List<$core.int>? strokeId,
    $core.List<$core.int>? authorId,
    $core.String? authorName,
    $core.int? tool,
    $core.int? color,
    $core.double? strokeWidth,
    $core.Iterable<$core.double>? points,
    $core.String? text,
    $core.int? shapeType,
    $fixnum.Int64? timestamp,
    $core.int? actionType,
    $core.int? pageIndex,
  }) {
    final $result = create();
    if (strokeId != null) {
      $result.strokeId = strokeId;
    }
    if (authorId != null) {
      $result.authorId = authorId;
    }
    if (authorName != null) {
      $result.authorName = authorName;
    }
    if (tool != null) {
      $result.tool = tool;
    }
    if (color != null) {
      $result.color = color;
    }
    if (strokeWidth != null) {
      $result.strokeWidth = strokeWidth;
    }
    if (points != null) {
      $result.points.addAll(points);
    }
    if (text != null) {
      $result.text = text;
    }
    if (shapeType != null) {
      $result.shapeType = shapeType;
    }
    if (timestamp != null) {
      $result.timestamp = timestamp;
    }
    if (actionType != null) {
      $result.actionType = actionType;
    }
    if (pageIndex != null) {
      $result.pageIndex = pageIndex;
    }
    return $result;
  }
  WhiteboardStroke._() : super();
  factory WhiteboardStroke.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory WhiteboardStroke.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'WhiteboardStroke', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'strokeId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'authorId', $pb.PbFieldType.OY)
    ..aOS(3, _omitFieldNames ? '' : 'authorName')
    ..a<$core.int>(4, _omitFieldNames ? '' : 'tool', $pb.PbFieldType.O3)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'color', $pb.PbFieldType.O3)
    ..a<$core.double>(6, _omitFieldNames ? '' : 'strokeWidth', $pb.PbFieldType.OF)
    ..p<$core.double>(7, _omitFieldNames ? '' : 'points', $pb.PbFieldType.KF)
    ..aOS(8, _omitFieldNames ? '' : 'text')
    ..a<$core.int>(9, _omitFieldNames ? '' : 'shapeType', $pb.PbFieldType.O3)
    ..aInt64(10, _omitFieldNames ? '' : 'timestamp')
    ..a<$core.int>(11, _omitFieldNames ? '' : 'actionType', $pb.PbFieldType.O3)
    ..a<$core.int>(12, _omitFieldNames ? '' : 'pageIndex', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  WhiteboardStroke clone() => WhiteboardStroke()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  WhiteboardStroke copyWith(void Function(WhiteboardStroke) updates) => super.copyWith((message) => updates(message as WhiteboardStroke)) as WhiteboardStroke;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static WhiteboardStroke create() => WhiteboardStroke._();
  WhiteboardStroke createEmptyInstance() => create();
  static $pb.PbList<WhiteboardStroke> createRepeated() => $pb.PbList<WhiteboardStroke>();
  @$core.pragma('dart2js:noInline')
  static WhiteboardStroke getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<WhiteboardStroke>(create);
  static WhiteboardStroke? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get strokeId => $_getN(0);
  @$pb.TagNumber(1)
  set strokeId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasStrokeId() => $_has(0);
  @$pb.TagNumber(1)
  void clearStrokeId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get authorId => $_getN(1);
  @$pb.TagNumber(2)
  set authorId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasAuthorId() => $_has(1);
  @$pb.TagNumber(2)
  void clearAuthorId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get authorName => $_getSZ(2);
  @$pb.TagNumber(3)
  set authorName($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAuthorName() => $_has(2);
  @$pb.TagNumber(3)
  void clearAuthorName() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get tool => $_getIZ(3);
  @$pb.TagNumber(4)
  set tool($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTool() => $_has(3);
  @$pb.TagNumber(4)
  void clearTool() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get color => $_getIZ(4);
  @$pb.TagNumber(5)
  set color($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasColor() => $_has(4);
  @$pb.TagNumber(5)
  void clearColor() => clearField(5);

  @$pb.TagNumber(6)
  $core.double get strokeWidth => $_getN(5);
  @$pb.TagNumber(6)
  set strokeWidth($core.double v) { $_setFloat(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasStrokeWidth() => $_has(5);
  @$pb.TagNumber(6)
  void clearStrokeWidth() => clearField(6);

  @$pb.TagNumber(7)
  $core.List<$core.double> get points => $_getList(6);

  @$pb.TagNumber(8)
  $core.String get text => $_getSZ(7);
  @$pb.TagNumber(8)
  set text($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasText() => $_has(7);
  @$pb.TagNumber(8)
  void clearText() => clearField(8);

  @$pb.TagNumber(9)
  $core.int get shapeType => $_getIZ(8);
  @$pb.TagNumber(9)
  set shapeType($core.int v) { $_setSignedInt32(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasShapeType() => $_has(8);
  @$pb.TagNumber(9)
  void clearShapeType() => clearField(9);

  @$pb.TagNumber(10)
  $fixnum.Int64 get timestamp => $_getI64(9);
  @$pb.TagNumber(10)
  set timestamp($fixnum.Int64 v) { $_setInt64(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasTimestamp() => $_has(9);
  @$pb.TagNumber(10)
  void clearTimestamp() => clearField(10);

  @$pb.TagNumber(11)
  $core.int get actionType => $_getIZ(10);
  @$pb.TagNumber(11)
  set actionType($core.int v) { $_setSignedInt32(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasActionType() => $_has(10);
  @$pb.TagNumber(11)
  void clearActionType() => clearField(11);

  @$pb.TagNumber(12)
  $core.int get pageIndex => $_getIZ(11);
  @$pb.TagNumber(12)
  set pageIndex($core.int v) { $_setSignedInt32(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasPageIndex() => $_has(11);
  @$pb.TagNumber(12)
  void clearPageIndex() => clearField(12);
}

/// Whiteboard page management — add/switch pages, snapshot for late joiners.
/// MTV3_WHITEBOARD_PAGE = 211
class WhiteboardPage extends $pb.GeneratedMessage {
  factory WhiteboardPage({
    $core.int? action,
    $core.int? pageIndex,
    $core.int? totalPages,
    $core.Iterable<WhiteboardStroke>? strokes,
    $core.List<$core.int>? requesterId,
  }) {
    final $result = create();
    if (action != null) {
      $result.action = action;
    }
    if (pageIndex != null) {
      $result.pageIndex = pageIndex;
    }
    if (totalPages != null) {
      $result.totalPages = totalPages;
    }
    if (strokes != null) {
      $result.strokes.addAll(strokes);
    }
    if (requesterId != null) {
      $result.requesterId = requesterId;
    }
    return $result;
  }
  WhiteboardPage._() : super();
  factory WhiteboardPage.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory WhiteboardPage.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'WhiteboardPage', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'action', $pb.PbFieldType.O3)
    ..a<$core.int>(2, _omitFieldNames ? '' : 'pageIndex', $pb.PbFieldType.O3)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'totalPages', $pb.PbFieldType.O3)
    ..pc<WhiteboardStroke>(4, _omitFieldNames ? '' : 'strokes', $pb.PbFieldType.PM, subBuilder: WhiteboardStroke.create)
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'requesterId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  WhiteboardPage clone() => WhiteboardPage()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  WhiteboardPage copyWith(void Function(WhiteboardPage) updates) => super.copyWith((message) => updates(message as WhiteboardPage)) as WhiteboardPage;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static WhiteboardPage create() => WhiteboardPage._();
  WhiteboardPage createEmptyInstance() => create();
  static $pb.PbList<WhiteboardPage> createRepeated() => $pb.PbList<WhiteboardPage>();
  @$core.pragma('dart2js:noInline')
  static WhiteboardPage getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<WhiteboardPage>(create);
  static WhiteboardPage? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get action => $_getIZ(0);
  @$pb.TagNumber(1)
  set action($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAction() => $_has(0);
  @$pb.TagNumber(1)
  void clearAction() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get pageIndex => $_getIZ(1);
  @$pb.TagNumber(2)
  set pageIndex($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasPageIndex() => $_has(1);
  @$pb.TagNumber(2)
  void clearPageIndex() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get totalPages => $_getIZ(2);
  @$pb.TagNumber(3)
  set totalPages($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTotalPages() => $_has(2);
  @$pb.TagNumber(3)
  void clearTotalPages() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<WhiteboardStroke> get strokes => $_getList(3);

  @$pb.TagNumber(5)
  $core.List<$core.int> get requesterId => $_getN(4);
  @$pb.TagNumber(5)
  set requesterId($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasRequesterId() => $_has(4);
  @$pb.TagNumber(5)
  void clearRequesterId() => clearField(5);
}

/// File sharing within a call — metadata announcement via Overlay Multicast Tree.
/// MTV3_FILE_EXCHANGE = 212
class CallFileShare extends $pb.GeneratedMessage {
  factory CallFileShare({
    $core.List<$core.int>? fileId,
    $core.String? fileName,
    $fixnum.Int64? fileSize,
    $core.String? mimeType,
    $core.List<$core.int>? thumbnailData,
    $core.List<$core.int>? sharedBy,
    $core.String? sharedByName,
    $core.int? action,
  }) {
    final $result = create();
    if (fileId != null) {
      $result.fileId = fileId;
    }
    if (fileName != null) {
      $result.fileName = fileName;
    }
    if (fileSize != null) {
      $result.fileSize = fileSize;
    }
    if (mimeType != null) {
      $result.mimeType = mimeType;
    }
    if (thumbnailData != null) {
      $result.thumbnailData = thumbnailData;
    }
    if (sharedBy != null) {
      $result.sharedBy = sharedBy;
    }
    if (sharedByName != null) {
      $result.sharedByName = sharedByName;
    }
    if (action != null) {
      $result.action = action;
    }
    return $result;
  }
  CallFileShare._() : super();
  factory CallFileShare.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CallFileShare.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CallFileShare', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'fileId', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'fileName')
    ..aInt64(3, _omitFieldNames ? '' : 'fileSize')
    ..aOS(4, _omitFieldNames ? '' : 'mimeType')
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'thumbnailData', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(6, _omitFieldNames ? '' : 'sharedBy', $pb.PbFieldType.OY)
    ..aOS(7, _omitFieldNames ? '' : 'sharedByName')
    ..a<$core.int>(8, _omitFieldNames ? '' : 'action', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CallFileShare clone() => CallFileShare()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CallFileShare copyWith(void Function(CallFileShare) updates) => super.copyWith((message) => updates(message as CallFileShare)) as CallFileShare;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CallFileShare create() => CallFileShare._();
  CallFileShare createEmptyInstance() => create();
  static $pb.PbList<CallFileShare> createRepeated() => $pb.PbList<CallFileShare>();
  @$core.pragma('dart2js:noInline')
  static CallFileShare getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CallFileShare>(create);
  static CallFileShare? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get fileId => $_getN(0);
  @$pb.TagNumber(1)
  set fileId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasFileId() => $_has(0);
  @$pb.TagNumber(1)
  void clearFileId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get fileName => $_getSZ(1);
  @$pb.TagNumber(2)
  set fileName($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasFileName() => $_has(1);
  @$pb.TagNumber(2)
  void clearFileName() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get fileSize => $_getI64(2);
  @$pb.TagNumber(3)
  set fileSize($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasFileSize() => $_has(2);
  @$pb.TagNumber(3)
  void clearFileSize() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get mimeType => $_getSZ(3);
  @$pb.TagNumber(4)
  set mimeType($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasMimeType() => $_has(3);
  @$pb.TagNumber(4)
  void clearMimeType() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get thumbnailData => $_getN(4);
  @$pb.TagNumber(5)
  set thumbnailData($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasThumbnailData() => $_has(4);
  @$pb.TagNumber(5)
  void clearThumbnailData() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get sharedBy => $_getN(5);
  @$pb.TagNumber(6)
  set sharedBy($core.List<$core.int> v) { $_setBytes(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasSharedBy() => $_has(5);
  @$pb.TagNumber(6)
  void clearSharedBy() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get sharedByName => $_getSZ(6);
  @$pb.TagNumber(7)
  set sharedByName($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasSharedByName() => $_has(6);
  @$pb.TagNumber(7)
  void clearSharedByName() => clearField(7);

  @$pb.TagNumber(8)
  $core.int get action => $_getIZ(7);
  @$pb.TagNumber(8)
  set action($core.int v) { $_setSignedInt32(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasAction() => $_has(7);
  @$pb.TagNumber(8)
  void clearAction() => clearField(8);
}

/// Clipboard exchange within a call.
/// MTV3_CLIPBOARD_EXCHANGE = 213
class CallClipboardExchange extends $pb.GeneratedMessage {
  factory CallClipboardExchange({
    $core.List<$core.int>? senderId,
    $core.String? senderName,
    $core.String? textContent,
    $core.List<$core.int>? imageData,
    $core.String? contentType,
    $fixnum.Int64? timestamp,
  }) {
    final $result = create();
    if (senderId != null) {
      $result.senderId = senderId;
    }
    if (senderName != null) {
      $result.senderName = senderName;
    }
    if (textContent != null) {
      $result.textContent = textContent;
    }
    if (imageData != null) {
      $result.imageData = imageData;
    }
    if (contentType != null) {
      $result.contentType = contentType;
    }
    if (timestamp != null) {
      $result.timestamp = timestamp;
    }
    return $result;
  }
  CallClipboardExchange._() : super();
  factory CallClipboardExchange.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CallClipboardExchange.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CallClipboardExchange', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'senderId', $pb.PbFieldType.OY)
    ..aOS(2, _omitFieldNames ? '' : 'senderName')
    ..aOS(3, _omitFieldNames ? '' : 'textContent')
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'imageData', $pb.PbFieldType.OY)
    ..aOS(5, _omitFieldNames ? '' : 'contentType')
    ..aInt64(6, _omitFieldNames ? '' : 'timestamp')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CallClipboardExchange clone() => CallClipboardExchange()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CallClipboardExchange copyWith(void Function(CallClipboardExchange) updates) => super.copyWith((message) => updates(message as CallClipboardExchange)) as CallClipboardExchange;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CallClipboardExchange create() => CallClipboardExchange._();
  CallClipboardExchange createEmptyInstance() => create();
  static $pb.PbList<CallClipboardExchange> createRepeated() => $pb.PbList<CallClipboardExchange>();
  @$core.pragma('dart2js:noInline')
  static CallClipboardExchange getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CallClipboardExchange>(create);
  static CallClipboardExchange? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get senderId => $_getN(0);
  @$pb.TagNumber(1)
  set senderId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSenderId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSenderId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get senderName => $_getSZ(1);
  @$pb.TagNumber(2)
  set senderName($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSenderName() => $_has(1);
  @$pb.TagNumber(2)
  void clearSenderName() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get textContent => $_getSZ(2);
  @$pb.TagNumber(3)
  set textContent($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTextContent() => $_has(2);
  @$pb.TagNumber(3)
  void clearTextContent() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get imageData => $_getN(3);
  @$pb.TagNumber(4)
  set imageData($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasImageData() => $_has(3);
  @$pb.TagNumber(4)
  void clearImageData() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get contentType => $_getSZ(4);
  @$pb.TagNumber(5)
  set contentType($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasContentType() => $_has(4);
  @$pb.TagNumber(5)
  void clearContentType() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get timestamp => $_getI64(5);
  @$pb.TagNumber(6)
  set timestamp($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasTimestamp() => $_has(5);
  @$pb.TagNumber(6)
  void clearTimestamp() => clearField(6);
}

/// Screen share control — start/stop/quality negotiation.
/// MTV3_SCREEN_SHARE_FRAME = 214
class ScreenShareControl extends $pb.GeneratedMessage {
  factory ScreenShareControl({
    $core.bool? isSharing,
    $core.int? width,
    $core.int? height,
    $core.int? fps,
    $core.bool? optimizeForText,
    $core.List<$core.int>? sharerId,
  }) {
    final $result = create();
    if (isSharing != null) {
      $result.isSharing = isSharing;
    }
    if (width != null) {
      $result.width = width;
    }
    if (height != null) {
      $result.height = height;
    }
    if (fps != null) {
      $result.fps = fps;
    }
    if (optimizeForText != null) {
      $result.optimizeForText = optimizeForText;
    }
    if (sharerId != null) {
      $result.sharerId = sharerId;
    }
    return $result;
  }
  ScreenShareControl._() : super();
  factory ScreenShareControl.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ScreenShareControl.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ScreenShareControl', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'isSharing')
    ..a<$core.int>(2, _omitFieldNames ? '' : 'width', $pb.PbFieldType.O3)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'height', $pb.PbFieldType.O3)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'fps', $pb.PbFieldType.O3)
    ..aOB(5, _omitFieldNames ? '' : 'optimizeForText')
    ..a<$core.List<$core.int>>(6, _omitFieldNames ? '' : 'sharerId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ScreenShareControl clone() => ScreenShareControl()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ScreenShareControl copyWith(void Function(ScreenShareControl) updates) => super.copyWith((message) => updates(message as ScreenShareControl)) as ScreenShareControl;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ScreenShareControl create() => ScreenShareControl._();
  ScreenShareControl createEmptyInstance() => create();
  static $pb.PbList<ScreenShareControl> createRepeated() => $pb.PbList<ScreenShareControl>();
  @$core.pragma('dart2js:noInline')
  static ScreenShareControl getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ScreenShareControl>(create);
  static ScreenShareControl? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get isSharing => $_getBF(0);
  @$pb.TagNumber(1)
  set isSharing($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasIsSharing() => $_has(0);
  @$pb.TagNumber(1)
  void clearIsSharing() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get width => $_getIZ(1);
  @$pb.TagNumber(2)
  set width($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasWidth() => $_has(1);
  @$pb.TagNumber(2)
  void clearWidth() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get height => $_getIZ(2);
  @$pb.TagNumber(3)
  set height($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasHeight() => $_has(2);
  @$pb.TagNumber(3)
  void clearHeight() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get fps => $_getIZ(3);
  @$pb.TagNumber(4)
  set fps($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasFps() => $_has(3);
  @$pb.TagNumber(4)
  void clearFps() => clearField(4);

  @$pb.TagNumber(5)
  $core.bool get optimizeForText => $_getBF(4);
  @$pb.TagNumber(5)
  set optimizeForText($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasOptimizeForText() => $_has(4);
  @$pb.TagNumber(5)
  void clearOptimizeForText() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get sharerId => $_getN(5);
  @$pb.TagNumber(6)
  set sharerId($core.List<$core.int> v) { $_setBytes(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasSharerId() => $_has(5);
  @$pb.TagNumber(6)
  void clearSharerId() => clearField(6);
}

/// Ephemeral in-call chat message — NOT persisted after call ends.
/// MTV3_CALL_CHAT = 215
class CallChatMessage extends $pb.GeneratedMessage {
  factory CallChatMessage({
    $core.List<$core.int>? messageId,
    $core.List<$core.int>? senderId,
    $core.String? senderName,
    $core.String? text,
    $fixnum.Int64? timestamp,
    $core.List<$core.int>? replyToId,
  }) {
    final $result = create();
    if (messageId != null) {
      $result.messageId = messageId;
    }
    if (senderId != null) {
      $result.senderId = senderId;
    }
    if (senderName != null) {
      $result.senderName = senderName;
    }
    if (text != null) {
      $result.text = text;
    }
    if (timestamp != null) {
      $result.timestamp = timestamp;
    }
    if (replyToId != null) {
      $result.replyToId = replyToId;
    }
    return $result;
  }
  CallChatMessage._() : super();
  factory CallChatMessage.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CallChatMessage.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CallChatMessage', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'messageId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'senderId', $pb.PbFieldType.OY)
    ..aOS(3, _omitFieldNames ? '' : 'senderName')
    ..aOS(4, _omitFieldNames ? '' : 'text')
    ..aInt64(5, _omitFieldNames ? '' : 'timestamp')
    ..a<$core.List<$core.int>>(6, _omitFieldNames ? '' : 'replyToId', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CallChatMessage clone() => CallChatMessage()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CallChatMessage copyWith(void Function(CallChatMessage) updates) => super.copyWith((message) => updates(message as CallChatMessage)) as CallChatMessage;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CallChatMessage create() => CallChatMessage._();
  CallChatMessage createEmptyInstance() => create();
  static $pb.PbList<CallChatMessage> createRepeated() => $pb.PbList<CallChatMessage>();
  @$core.pragma('dart2js:noInline')
  static CallChatMessage getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CallChatMessage>(create);
  static CallChatMessage? _defaultInstance;

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
  $core.String get senderName => $_getSZ(2);
  @$pb.TagNumber(3)
  set senderName($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSenderName() => $_has(2);
  @$pb.TagNumber(3)
  void clearSenderName() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get text => $_getSZ(3);
  @$pb.TagNumber(4)
  set text($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasText() => $_has(3);
  @$pb.TagNumber(4)
  void clearText() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get timestamp => $_getI64(4);
  @$pb.TagNumber(5)
  set timestamp($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasTimestamp() => $_has(4);
  @$pb.TagNumber(5)
  void clearTimestamp() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get replyToId => $_getN(5);
  @$pb.TagNumber(6)
  set replyToId($core.List<$core.int> v) { $_setBytes(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasReplyToId() => $_has(5);
  @$pb.TagNumber(6)
  void clearReplyToId() => clearField(6);
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
    $core.Iterable<RotationApprovalToken>? approvalTokens,
    $core.int? preRotationDeviceCount,
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
    if (approvalTokens != null) {
      $result.approvalTokens.addAll(approvalTokens);
    }
    if (preRotationDeviceCount != null) {
      $result.preRotationDeviceCount = preRotationDeviceCount;
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
    ..pc<RotationApprovalToken>(7, _omitFieldNames ? '' : 'approvalTokens', $pb.PbFieldType.PM, subBuilder: RotationApprovalToken.create)
    ..a<$core.int>(8, _omitFieldNames ? '' : 'preRotationDeviceCount', $pb.PbFieldType.OU3)
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

  /// §7.5 Device Co-Authorization: Device-Sig countersigs from authorized devices
  @$pb.TagNumber(7)
  $core.List<RotationApprovalToken> get approvalTokens => $_getList(6);

  @$pb.TagNumber(8)
  $core.int get preRotationDeviceCount => $_getIZ(7);
  @$pb.TagNumber(8)
  set preRotationDeviceCount($core.int v) { $_setUnsignedInt32(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasPreRotationDeviceCount() => $_has(7);
  @$pb.TagNumber(8)
  void clearPreRotationDeviceCount() => clearField(8);
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
    $core.Iterable<$core.List<$core.int>>? attendeeNodeIds,
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
    if (attendeeNodeIds != null) {
      $result.attendeeNodeIds.addAll(attendeeNodeIds);
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
    ..p<$core.List<$core.int>>(17, _omitFieldNames ? '' : 'attendeeNodeIds', $pb.PbFieldType.PY)
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

  @$pb.TagNumber(17)
  $core.List<$core.List<$core.int>> get attendeeNodeIds => $_getList(16);
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

///  ── Anonymous Vote Re-Broadcaster (§11.4.8) ──────────────────────────
///
///  Voter bundles pre-encrypted per-recipient KEM blobs and sends them to
///  a random DHT peer R via InfrastructureFrame. R re-originates each entry
///  as a fresh APPLICATION_FRAME under its own device identity.
class PollAnonSubmitEntry extends $pb.GeneratedMessage {
  factory PollAnonSubmitEntry({
    $core.List<$core.int>? recipientUserId,
    $core.List<$core.int>? kemBlob,
    $core.Iterable<$core.List<$core.int>>? deviceIds,
  }) {
    final $result = create();
    if (recipientUserId != null) {
      $result.recipientUserId = recipientUserId;
    }
    if (kemBlob != null) {
      $result.kemBlob = kemBlob;
    }
    if (deviceIds != null) {
      $result.deviceIds.addAll(deviceIds);
    }
    return $result;
  }
  PollAnonSubmitEntry._() : super();
  factory PollAnonSubmitEntry.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PollAnonSubmitEntry.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PollAnonSubmitEntry', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'recipientUserId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'kemBlob', $pb.PbFieldType.OY)
    ..p<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'deviceIds', $pb.PbFieldType.PY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PollAnonSubmitEntry clone() => PollAnonSubmitEntry()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PollAnonSubmitEntry copyWith(void Function(PollAnonSubmitEntry) updates) => super.copyWith((message) => updates(message as PollAnonSubmitEntry)) as PollAnonSubmitEntry;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PollAnonSubmitEntry create() => PollAnonSubmitEntry._();
  PollAnonSubmitEntry createEmptyInstance() => create();
  static $pb.PbList<PollAnonSubmitEntry> createRepeated() => $pb.PbList<PollAnonSubmitEntry>();
  @$core.pragma('dart2js:noInline')
  static PollAnonSubmitEntry getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PollAnonSubmitEntry>(create);
  static PollAnonSubmitEntry? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get recipientUserId => $_getN(0);
  @$pb.TagNumber(1)
  set recipientUserId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasRecipientUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRecipientUserId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get kemBlob => $_getN(1);
  @$pb.TagNumber(2)
  set kemBlob($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasKemBlob() => $_has(1);
  @$pb.TagNumber(2)
  void clearKemBlob() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.List<$core.int>> get deviceIds => $_getList(2);
}

class PollAnonSubmitMsg extends $pb.GeneratedMessage {
  factory PollAnonSubmitMsg({
    $core.List<$core.int>? pollId,
    $core.Iterable<PollAnonSubmitEntry>? entries,
    $fixnum.Int64? powNonce,
  }) {
    final $result = create();
    if (pollId != null) {
      $result.pollId = pollId;
    }
    if (entries != null) {
      $result.entries.addAll(entries);
    }
    if (powNonce != null) {
      $result.powNonce = powNonce;
    }
    return $result;
  }
  PollAnonSubmitMsg._() : super();
  factory PollAnonSubmitMsg.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PollAnonSubmitMsg.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PollAnonSubmitMsg', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'pollId', $pb.PbFieldType.OY)
    ..pc<PollAnonSubmitEntry>(2, _omitFieldNames ? '' : 'entries', $pb.PbFieldType.PM, subBuilder: PollAnonSubmitEntry.create)
    ..a<$fixnum.Int64>(3, _omitFieldNames ? '' : 'powNonce', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PollAnonSubmitMsg clone() => PollAnonSubmitMsg()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PollAnonSubmitMsg copyWith(void Function(PollAnonSubmitMsg) updates) => super.copyWith((message) => updates(message as PollAnonSubmitMsg)) as PollAnonSubmitMsg;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PollAnonSubmitMsg create() => PollAnonSubmitMsg._();
  PollAnonSubmitMsg createEmptyInstance() => create();
  static $pb.PbList<PollAnonSubmitMsg> createRepeated() => $pb.PbList<PollAnonSubmitMsg>();
  @$core.pragma('dart2js:noInline')
  static PollAnonSubmitMsg getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PollAnonSubmitMsg>(create);
  static PollAnonSubmitMsg? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get pollId => $_getN(0);
  @$pb.TagNumber(1)
  set pollId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPollId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPollId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<PollAnonSubmitEntry> get entries => $_getList(1);

  @$pb.TagNumber(3)
  $fixnum.Int64 get powNonce => $_getI64(2);
  @$pb.TagNumber(3)
  set powNonce($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasPowNonce() => $_has(2);
  @$pb.TagNumber(3)
  void clearPowNonce() => clearField(3);
}

class PollAnonSubmitAckMsg extends $pb.GeneratedMessage {
  factory PollAnonSubmitAckMsg({
    $core.List<$core.int>? pollId,
    $core.bool? accepted,
    $core.String? rejectReason,
  }) {
    final $result = create();
    if (pollId != null) {
      $result.pollId = pollId;
    }
    if (accepted != null) {
      $result.accepted = accepted;
    }
    if (rejectReason != null) {
      $result.rejectReason = rejectReason;
    }
    return $result;
  }
  PollAnonSubmitAckMsg._() : super();
  factory PollAnonSubmitAckMsg.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PollAnonSubmitAckMsg.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PollAnonSubmitAckMsg', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'pollId', $pb.PbFieldType.OY)
    ..aOB(2, _omitFieldNames ? '' : 'accepted')
    ..aOS(3, _omitFieldNames ? '' : 'rejectReason')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PollAnonSubmitAckMsg clone() => PollAnonSubmitAckMsg()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PollAnonSubmitAckMsg copyWith(void Function(PollAnonSubmitAckMsg) updates) => super.copyWith((message) => updates(message as PollAnonSubmitAckMsg)) as PollAnonSubmitAckMsg;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PollAnonSubmitAckMsg create() => PollAnonSubmitAckMsg._();
  PollAnonSubmitAckMsg createEmptyInstance() => create();
  static $pb.PbList<PollAnonSubmitAckMsg> createRepeated() => $pb.PbList<PollAnonSubmitAckMsg>();
  @$core.pragma('dart2js:noInline')
  static PollAnonSubmitAckMsg getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PollAnonSubmitAckMsg>(create);
  static PollAnonSubmitAckMsg? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get pollId => $_getN(0);
  @$pb.TagNumber(1)
  set pollId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPollId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPollId() => clearField(1);

  @$pb.TagNumber(2)
  $core.bool get accepted => $_getBF(1);
  @$pb.TagNumber(2)
  set accepted($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasAccepted() => $_has(1);
  @$pb.TagNumber(2)
  void clearAccepted() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get rejectReason => $_getSZ(2);
  @$pb.TagNumber(3)
  set rejectReason($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasRejectReason() => $_has(2);
  @$pb.TagNumber(3)
  void clearRejectReason() => clearField(3);
}

///  ── Linked-Device Delegation (§7.1 LD-1) ───────────────────────────────
///
///  A DeviceDelegationCert authorizes a Linked Device to act for the user
///  identity with bounded capabilities. The cert is signed by the User-Key
///  (hybrid Ed25519 + ML-DSA) and carried inside the AuthManifest so
///  receivers can verify delegated Inner-Frame signatures.
///
///  Security model: the Linked Device holds a per-device delegated Sig-Key
///  (derived via HKDF from the master seed, deterministic per device_id) +
///  the User-KEM-SK for message decryption. It does NOT hold the master
///  seed, the User-Sig-SK, or the ability to rotate/revoke.
class DeviceDelegationCertProto extends $pb.GeneratedMessage {
  factory DeviceDelegationCertProto({
    $core.List<$core.int>? deviceId,
    $core.List<$core.int>? delegatedEd25519Pk,
    $core.List<$core.int>? delegatedMlDsaPk,
    $core.int? capabilities,
    $fixnum.Int64? issuedAtMs,
    $fixnum.Int64? maxValidUntilMs,
    $core.List<$core.int>? userEd25519Sig,
    $core.List<$core.int>? userMlDsaSig,
  }) {
    final $result = create();
    if (deviceId != null) {
      $result.deviceId = deviceId;
    }
    if (delegatedEd25519Pk != null) {
      $result.delegatedEd25519Pk = delegatedEd25519Pk;
    }
    if (delegatedMlDsaPk != null) {
      $result.delegatedMlDsaPk = delegatedMlDsaPk;
    }
    if (capabilities != null) {
      $result.capabilities = capabilities;
    }
    if (issuedAtMs != null) {
      $result.issuedAtMs = issuedAtMs;
    }
    if (maxValidUntilMs != null) {
      $result.maxValidUntilMs = maxValidUntilMs;
    }
    if (userEd25519Sig != null) {
      $result.userEd25519Sig = userEd25519Sig;
    }
    if (userMlDsaSig != null) {
      $result.userMlDsaSig = userMlDsaSig;
    }
    return $result;
  }
  DeviceDelegationCertProto._() : super();
  factory DeviceDelegationCertProto.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DeviceDelegationCertProto.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DeviceDelegationCertProto', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'deviceId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'delegatedEd25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'delegatedMlDsaPk', $pb.PbFieldType.OY)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'capabilities', $pb.PbFieldType.OU3)
    ..a<$fixnum.Int64>(5, _omitFieldNames ? '' : 'issuedAtMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(6, _omitFieldNames ? '' : 'maxValidUntilMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(7, _omitFieldNames ? '' : 'userEd25519Sig', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(8, _omitFieldNames ? '' : 'userMlDsaSig', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DeviceDelegationCertProto clone() => DeviceDelegationCertProto()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DeviceDelegationCertProto copyWith(void Function(DeviceDelegationCertProto) updates) => super.copyWith((message) => updates(message as DeviceDelegationCertProto)) as DeviceDelegationCertProto;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeviceDelegationCertProto create() => DeviceDelegationCertProto._();
  DeviceDelegationCertProto createEmptyInstance() => create();
  static $pb.PbList<DeviceDelegationCertProto> createRepeated() => $pb.PbList<DeviceDelegationCertProto>();
  @$core.pragma('dart2js:noInline')
  static DeviceDelegationCertProto getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DeviceDelegationCertProto>(create);
  static DeviceDelegationCertProto? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get deviceId => $_getN(0);
  @$pb.TagNumber(1)
  set deviceId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasDeviceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get delegatedEd25519Pk => $_getN(1);
  @$pb.TagNumber(2)
  set delegatedEd25519Pk($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDelegatedEd25519Pk() => $_has(1);
  @$pb.TagNumber(2)
  void clearDelegatedEd25519Pk() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get delegatedMlDsaPk => $_getN(2);
  @$pb.TagNumber(3)
  set delegatedMlDsaPk($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDelegatedMlDsaPk() => $_has(2);
  @$pb.TagNumber(3)
  void clearDelegatedMlDsaPk() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get capabilities => $_getIZ(3);
  @$pb.TagNumber(4)
  set capabilities($core.int v) { $_setUnsignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasCapabilities() => $_has(3);
  @$pb.TagNumber(4)
  void clearCapabilities() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get issuedAtMs => $_getI64(4);
  @$pb.TagNumber(5)
  set issuedAtMs($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasIssuedAtMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearIssuedAtMs() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get maxValidUntilMs => $_getI64(5);
  @$pb.TagNumber(6)
  set maxValidUntilMs($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasMaxValidUntilMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearMaxValidUntilMs() => clearField(6);

  @$pb.TagNumber(7)
  $core.List<$core.int> get userEd25519Sig => $_getN(6);
  @$pb.TagNumber(7)
  set userEd25519Sig($core.List<$core.int> v) { $_setBytes(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasUserEd25519Sig() => $_has(6);
  @$pb.TagNumber(7)
  void clearUserEd25519Sig() => clearField(7);

  @$pb.TagNumber(8)
  $core.List<$core.int> get userMlDsaSig => $_getN(7);
  @$pb.TagNumber(8)
  set userMlDsaSig($core.List<$core.int> v) { $_setBytes(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasUserMlDsaSig() => $_has(7);
  @$pb.TagNumber(8)
  void clearUserMlDsaSig() => clearField(8);
}

///  ── Payload type TEXT (new): explicit TextMessage instead of raw bytes ──────
///
///  V2 packed text as raw UTF-8 into encrypted_payload. V3 wraps every
///  payload type into a proto message of its own — gives us version fields per
///  type and a clear schema for future extensions (formatHint etc.).
class TextMessageV3 extends $pb.GeneratedMessage {
  factory TextMessageV3({
    $core.String? text,
    $core.String? formatHint,
    $core.List<$core.int>? replyToMessageId,
    $core.String? replyToSnippet,
    LinkPreview? linkPreview,
  }) {
    final $result = create();
    if (text != null) {
      $result.text = text;
    }
    if (formatHint != null) {
      $result.formatHint = formatHint;
    }
    if (replyToMessageId != null) {
      $result.replyToMessageId = replyToMessageId;
    }
    if (replyToSnippet != null) {
      $result.replyToSnippet = replyToSnippet;
    }
    if (linkPreview != null) {
      $result.linkPreview = linkPreview;
    }
    return $result;
  }
  TextMessageV3._() : super();
  factory TextMessageV3.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TextMessageV3.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TextMessageV3', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aOS(2, _omitFieldNames ? '' : 'formatHint')
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'replyToMessageId', $pb.PbFieldType.OY)
    ..aOS(4, _omitFieldNames ? '' : 'replyToSnippet')
    ..aOM<LinkPreview>(5, _omitFieldNames ? '' : 'linkPreview', subBuilder: LinkPreview.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TextMessageV3 clone() => TextMessageV3()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TextMessageV3 copyWith(void Function(TextMessageV3) updates) => super.copyWith((message) => updates(message as TextMessageV3)) as TextMessageV3;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TextMessageV3 create() => TextMessageV3._();
  TextMessageV3 createEmptyInstance() => create();
  static $pb.PbList<TextMessageV3> createRepeated() => $pb.PbList<TextMessageV3>();
  @$core.pragma('dart2js:noInline')
  static TextMessageV3 getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TextMessageV3>(create);
  static TextMessageV3? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get formatHint => $_getSZ(1);
  @$pb.TagNumber(2)
  set formatHint($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasFormatHint() => $_has(1);
  @$pb.TagNumber(2)
  void clearFormatHint() => clearField(2);

  /// Reply / Quote (V3 reply schema). Empty when this is not a reply.
  /// - reply_to_message_id: 16-byte messageId of the quoted bubble. Receivers
  ///   can resolve it locally (it lives in the same conversation) to render
  ///   the inline-quote header. UI falls back to reply_to_snippet if the
  ///   referenced message is not retained locally.
  /// - reply_to_snippet:    short text excerpt sender renders at compose-time.
  ///   Bounded to ~120 chars by sender-side trimming.
  @$pb.TagNumber(3)
  $core.List<$core.int> get replyToMessageId => $_getN(2);
  @$pb.TagNumber(3)
  set replyToMessageId($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasReplyToMessageId() => $_has(2);
  @$pb.TagNumber(3)
  void clearReplyToMessageId() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get replyToSnippet => $_getSZ(3);
  @$pb.TagNumber(4)
  set replyToSnippet($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasReplyToSnippet() => $_has(3);
  @$pb.TagNumber(4)
  void clearReplyToSnippet() => clearField(4);

  /// Sender-side link preview (Architecture §2.3.4). Sender fetches the
  /// preview (HTTPS-only, SSRF-guarded) and embeds the result so the
  /// receiver renders it WITHOUT performing any network request — the
  /// receiver-MUST-NOT-fetch invariant is what makes link previews
  /// privacy-safe. Empty when the message has no URL or fetch failed.
  @$pb.TagNumber(5)
  LinkPreview get linkPreview => $_getN(4);
  @$pb.TagNumber(5)
  set linkPreview(LinkPreview v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasLinkPreview() => $_has(4);
  @$pb.TagNumber(5)
  void clearLinkPreview() => clearField(5);
  @$pb.TagNumber(5)
  LinkPreview ensureLinkPreview() => $_ensure(4);
}

/// New device → Primary: "I want to pair, here are my device keys"
class DevicePairRequestV3 extends $pb.GeneratedMessage {
  factory DevicePairRequestV3({
    $core.List<$core.int>? deviceEd25519Pk,
    $core.List<$core.int>? deviceMlDsaPk,
    $core.List<$core.int>? pairTokenSignature,
    $fixnum.Int64? timestampMs,
  }) {
    final $result = create();
    if (deviceEd25519Pk != null) {
      $result.deviceEd25519Pk = deviceEd25519Pk;
    }
    if (deviceMlDsaPk != null) {
      $result.deviceMlDsaPk = deviceMlDsaPk;
    }
    if (pairTokenSignature != null) {
      $result.pairTokenSignature = pairTokenSignature;
    }
    if (timestampMs != null) {
      $result.timestampMs = timestampMs;
    }
    return $result;
  }
  DevicePairRequestV3._() : super();
  factory DevicePairRequestV3.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DevicePairRequestV3.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DevicePairRequestV3', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'deviceEd25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'deviceMlDsaPk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'pairTokenSignature', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(4, _omitFieldNames ? '' : 'timestampMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DevicePairRequestV3 clone() => DevicePairRequestV3()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DevicePairRequestV3 copyWith(void Function(DevicePairRequestV3) updates) => super.copyWith((message) => updates(message as DevicePairRequestV3)) as DevicePairRequestV3;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DevicePairRequestV3 create() => DevicePairRequestV3._();
  DevicePairRequestV3 createEmptyInstance() => create();
  static $pb.PbList<DevicePairRequestV3> createRepeated() => $pb.PbList<DevicePairRequestV3>();
  @$core.pragma('dart2js:noInline')
  static DevicePairRequestV3 getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DevicePairRequestV3>(create);
  static DevicePairRequestV3? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get deviceEd25519Pk => $_getN(0);
  @$pb.TagNumber(1)
  set deviceEd25519Pk($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasDeviceEd25519Pk() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceEd25519Pk() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get deviceMlDsaPk => $_getN(1);
  @$pb.TagNumber(2)
  set deviceMlDsaPk($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDeviceMlDsaPk() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeviceMlDsaPk() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get pairTokenSignature => $_getN(2);
  @$pb.TagNumber(3)
  set pairTokenSignature($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasPairTokenSignature() => $_has(2);
  @$pb.TagNumber(3)
  void clearPairTokenSignature() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get timestampMs => $_getI64(3);
  @$pb.TagNumber(4)
  set timestampMs($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTimestampMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearTimestampMs() => clearField(4);
}

/// Primary → New device: delegation material (KEM-encrypted end-to-end)
class DevicePairApproveV3 extends $pb.GeneratedMessage {
  factory DevicePairApproveV3({
    $core.List<$core.int>? delegatedEd25519Pk,
    $core.List<$core.int>? delegatedEd25519Sk,
    $core.List<$core.int>? delegatedMlDsaPk,
    $core.List<$core.int>? delegatedMlDsaSk,
    $core.List<$core.int>? userX25519Sk,
    $core.List<$core.int>? userMlKemSk,
    DeviceDelegationCertProto? delegationCert,
    $core.List<$core.int>? userId,
    $core.String? displayName,
    $core.List<$core.int>? profilePicture,
  }) {
    final $result = create();
    if (delegatedEd25519Pk != null) {
      $result.delegatedEd25519Pk = delegatedEd25519Pk;
    }
    if (delegatedEd25519Sk != null) {
      $result.delegatedEd25519Sk = delegatedEd25519Sk;
    }
    if (delegatedMlDsaPk != null) {
      $result.delegatedMlDsaPk = delegatedMlDsaPk;
    }
    if (delegatedMlDsaSk != null) {
      $result.delegatedMlDsaSk = delegatedMlDsaSk;
    }
    if (userX25519Sk != null) {
      $result.userX25519Sk = userX25519Sk;
    }
    if (userMlKemSk != null) {
      $result.userMlKemSk = userMlKemSk;
    }
    if (delegationCert != null) {
      $result.delegationCert = delegationCert;
    }
    if (userId != null) {
      $result.userId = userId;
    }
    if (displayName != null) {
      $result.displayName = displayName;
    }
    if (profilePicture != null) {
      $result.profilePicture = profilePicture;
    }
    return $result;
  }
  DevicePairApproveV3._() : super();
  factory DevicePairApproveV3.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DevicePairApproveV3.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DevicePairApproveV3', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'delegatedEd25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'delegatedEd25519Sk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'delegatedMlDsaPk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'delegatedMlDsaSk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'userX25519Sk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(6, _omitFieldNames ? '' : 'userMlKemSk', $pb.PbFieldType.OY)
    ..aOM<DeviceDelegationCertProto>(7, _omitFieldNames ? '' : 'delegationCert', subBuilder: DeviceDelegationCertProto.create)
    ..a<$core.List<$core.int>>(8, _omitFieldNames ? '' : 'userId', $pb.PbFieldType.OY)
    ..aOS(9, _omitFieldNames ? '' : 'displayName')
    ..a<$core.List<$core.int>>(10, _omitFieldNames ? '' : 'profilePicture', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DevicePairApproveV3 clone() => DevicePairApproveV3()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DevicePairApproveV3 copyWith(void Function(DevicePairApproveV3) updates) => super.copyWith((message) => updates(message as DevicePairApproveV3)) as DevicePairApproveV3;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DevicePairApproveV3 create() => DevicePairApproveV3._();
  DevicePairApproveV3 createEmptyInstance() => create();
  static $pb.PbList<DevicePairApproveV3> createRepeated() => $pb.PbList<DevicePairApproveV3>();
  @$core.pragma('dart2js:noInline')
  static DevicePairApproveV3 getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DevicePairApproveV3>(create);
  static DevicePairApproveV3? _defaultInstance;

  /// Delegated Sig keys (per-device, derived from seed via HKDF)
  @$pb.TagNumber(1)
  $core.List<$core.int> get delegatedEd25519Pk => $_getN(0);
  @$pb.TagNumber(1)
  set delegatedEd25519Pk($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasDelegatedEd25519Pk() => $_has(0);
  @$pb.TagNumber(1)
  void clearDelegatedEd25519Pk() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get delegatedEd25519Sk => $_getN(1);
  @$pb.TagNumber(2)
  set delegatedEd25519Sk($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDelegatedEd25519Sk() => $_has(1);
  @$pb.TagNumber(2)
  void clearDelegatedEd25519Sk() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get delegatedMlDsaPk => $_getN(2);
  @$pb.TagNumber(3)
  set delegatedMlDsaPk($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDelegatedMlDsaPk() => $_has(2);
  @$pb.TagNumber(3)
  void clearDelegatedMlDsaPk() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get delegatedMlDsaSk => $_getN(3);
  @$pb.TagNumber(4)
  set delegatedMlDsaSk($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasDelegatedMlDsaSk() => $_has(3);
  @$pb.TagNumber(4)
  void clearDelegatedMlDsaSk() => clearField(4);

  /// User-KEM secret keys (for decrypting incoming Per-Message-KEM)
  @$pb.TagNumber(5)
  $core.List<$core.int> get userX25519Sk => $_getN(4);
  @$pb.TagNumber(5)
  set userX25519Sk($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasUserX25519Sk() => $_has(4);
  @$pb.TagNumber(5)
  void clearUserX25519Sk() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get userMlKemSk => $_getN(5);
  @$pb.TagNumber(6)
  set userMlKemSk($core.List<$core.int> v) { $_setBytes(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasUserMlKemSk() => $_has(5);
  @$pb.TagNumber(6)
  void clearUserMlKemSk() => clearField(6);

  /// The signed delegation certificate (to be embedded in AuthManifest)
  @$pb.TagNumber(7)
  DeviceDelegationCertProto get delegationCert => $_getN(6);
  @$pb.TagNumber(7)
  set delegationCert(DeviceDelegationCertProto v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasDelegationCert() => $_has(6);
  @$pb.TagNumber(7)
  void clearDelegationCert() => clearField(7);
  @$pb.TagNumber(7)
  DeviceDelegationCertProto ensureDelegationCert() => $_ensure(6);

  /// Identity metadata for the linked device to display
  @$pb.TagNumber(8)
  $core.List<$core.int> get userId => $_getN(7);
  @$pb.TagNumber(8)
  set userId($core.List<$core.int> v) { $_setBytes(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasUserId() => $_has(7);
  @$pb.TagNumber(8)
  void clearUserId() => clearField(8);

  @$pb.TagNumber(9)
  $core.String get displayName => $_getSZ(8);
  @$pb.TagNumber(9)
  set displayName($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasDisplayName() => $_has(8);
  @$pb.TagNumber(9)
  void clearDisplayName() => clearField(9);

  @$pb.TagNumber(10)
  $core.List<$core.int> get profilePicture => $_getN(9);
  @$pb.TagNumber(10)
  set profilePicture($core.List<$core.int> v) { $_setBytes(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasProfilePicture() => $_has(9);
  @$pb.TagNumber(10)
  void clearProfilePicture() => clearField(10);
}

/// Device-Sig pubkeys embedded in AuthManifest for all authorized devices.
/// Enables contacts to verify Device-Sig countersigs on rotation broadcasts.
/// Device-Sig keys are locally generated (NOT seed-derived) — a seed thief
/// cannot forge them.
class AuthorizedDeviceSigningKeys extends $pb.GeneratedMessage {
  factory AuthorizedDeviceSigningKeys({
    $core.List<$core.int>? deviceNodeId,
    $core.List<$core.int>? deviceEd25519Pk,
    $core.List<$core.int>? deviceMlDsaPk,
    $core.bool? isPrimary,
  }) {
    final $result = create();
    if (deviceNodeId != null) {
      $result.deviceNodeId = deviceNodeId;
    }
    if (deviceEd25519Pk != null) {
      $result.deviceEd25519Pk = deviceEd25519Pk;
    }
    if (deviceMlDsaPk != null) {
      $result.deviceMlDsaPk = deviceMlDsaPk;
    }
    if (isPrimary != null) {
      $result.isPrimary = isPrimary;
    }
    return $result;
  }
  AuthorizedDeviceSigningKeys._() : super();
  factory AuthorizedDeviceSigningKeys.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AuthorizedDeviceSigningKeys.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'AuthorizedDeviceSigningKeys', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'deviceNodeId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'deviceEd25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'deviceMlDsaPk', $pb.PbFieldType.OY)
    ..aOB(4, _omitFieldNames ? '' : 'isPrimary')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AuthorizedDeviceSigningKeys clone() => AuthorizedDeviceSigningKeys()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AuthorizedDeviceSigningKeys copyWith(void Function(AuthorizedDeviceSigningKeys) updates) => super.copyWith((message) => updates(message as AuthorizedDeviceSigningKeys)) as AuthorizedDeviceSigningKeys;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AuthorizedDeviceSigningKeys create() => AuthorizedDeviceSigningKeys._();
  AuthorizedDeviceSigningKeys createEmptyInstance() => create();
  static $pb.PbList<AuthorizedDeviceSigningKeys> createRepeated() => $pb.PbList<AuthorizedDeviceSigningKeys>();
  @$core.pragma('dart2js:noInline')
  static AuthorizedDeviceSigningKeys getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AuthorizedDeviceSigningKeys>(create);
  static AuthorizedDeviceSigningKeys? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get deviceNodeId => $_getN(0);
  @$pb.TagNumber(1)
  set deviceNodeId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasDeviceNodeId() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceNodeId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get deviceEd25519Pk => $_getN(1);
  @$pb.TagNumber(2)
  set deviceEd25519Pk($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDeviceEd25519Pk() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeviceEd25519Pk() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get deviceMlDsaPk => $_getN(2);
  @$pb.TagNumber(3)
  set deviceMlDsaPk($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDeviceMlDsaPk() => $_has(2);
  @$pb.TagNumber(3)
  void clearDeviceMlDsaPk() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get isPrimary => $_getBF(3);
  @$pb.TagNumber(4)
  set isPrimary($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasIsPrimary() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsPrimary() => clearField(4);
}

/// A single device's countersig on an emergency key rotation.
class RotationApprovalToken extends $pb.GeneratedMessage {
  factory RotationApprovalToken({
    $core.List<$core.int>? deviceNodeId,
    $core.List<$core.int>? rotationHash,
    $core.List<$core.int>? deviceEd25519Sig,
    $core.List<$core.int>? deviceMlDsaSig,
  }) {
    final $result = create();
    if (deviceNodeId != null) {
      $result.deviceNodeId = deviceNodeId;
    }
    if (rotationHash != null) {
      $result.rotationHash = rotationHash;
    }
    if (deviceEd25519Sig != null) {
      $result.deviceEd25519Sig = deviceEd25519Sig;
    }
    if (deviceMlDsaSig != null) {
      $result.deviceMlDsaSig = deviceMlDsaSig;
    }
    return $result;
  }
  RotationApprovalToken._() : super();
  factory RotationApprovalToken.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RotationApprovalToken.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RotationApprovalToken', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'deviceNodeId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'rotationHash', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'deviceEd25519Sig', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'deviceMlDsaSig', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RotationApprovalToken clone() => RotationApprovalToken()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RotationApprovalToken copyWith(void Function(RotationApprovalToken) updates) => super.copyWith((message) => updates(message as RotationApprovalToken)) as RotationApprovalToken;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RotationApprovalToken create() => RotationApprovalToken._();
  RotationApprovalToken createEmptyInstance() => create();
  static $pb.PbList<RotationApprovalToken> createRepeated() => $pb.PbList<RotationApprovalToken>();
  @$core.pragma('dart2js:noInline')
  static RotationApprovalToken getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RotationApprovalToken>(create);
  static RotationApprovalToken? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get deviceNodeId => $_getN(0);
  @$pb.TagNumber(1)
  set deviceNodeId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasDeviceNodeId() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceNodeId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get rotationHash => $_getN(1);
  @$pb.TagNumber(2)
  set rotationHash($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasRotationHash() => $_has(1);
  @$pb.TagNumber(2)
  void clearRotationHash() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get deviceEd25519Sig => $_getN(2);
  @$pb.TagNumber(3)
  set deviceEd25519Sig($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDeviceEd25519Sig() => $_has(2);
  @$pb.TagNumber(3)
  void clearDeviceEd25519Sig() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get deviceMlDsaSig => $_getN(3);
  @$pb.TagNumber(4)
  set deviceMlDsaSig($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasDeviceMlDsaSig() => $_has(3);
  @$pb.TagNumber(4)
  void clearDeviceMlDsaSig() => clearField(4);
}

class RotationApprovalRequestPayload extends $pb.GeneratedMessage {
  factory RotationApprovalRequestPayload({
    $core.List<$core.int>? rotationHash,
    $core.List<$core.int>? newEd25519Pk,
    $core.List<$core.int>? newMlDsaPk,
    $core.List<$core.int>? newX25519Pk,
    $core.List<$core.int>? newMlKemPk,
    ApprovalKindV3? approvalKind,
    $core.Iterable<$core.List<$core.int>>? newDeviceNodeIds,
  }) {
    final $result = create();
    if (rotationHash != null) {
      $result.rotationHash = rotationHash;
    }
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
    if (approvalKind != null) {
      $result.approvalKind = approvalKind;
    }
    if (newDeviceNodeIds != null) {
      $result.newDeviceNodeIds.addAll(newDeviceNodeIds);
    }
    return $result;
  }
  RotationApprovalRequestPayload._() : super();
  factory RotationApprovalRequestPayload.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RotationApprovalRequestPayload.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RotationApprovalRequestPayload', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'rotationHash', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'newEd25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'newMlDsaPk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'newX25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'newMlKemPk', $pb.PbFieldType.OY)
    ..e<ApprovalKindV3>(6, _omitFieldNames ? '' : 'approvalKind', $pb.PbFieldType.OE, defaultOrMaker: ApprovalKindV3.APPROVAL_KIND_KEY_ROTATION, valueOf: ApprovalKindV3.valueOf, enumValues: ApprovalKindV3.values)
    ..p<$core.List<$core.int>>(7, _omitFieldNames ? '' : 'newDeviceNodeIds', $pb.PbFieldType.PY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RotationApprovalRequestPayload clone() => RotationApprovalRequestPayload()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RotationApprovalRequestPayload copyWith(void Function(RotationApprovalRequestPayload) updates) => super.copyWith((message) => updates(message as RotationApprovalRequestPayload)) as RotationApprovalRequestPayload;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RotationApprovalRequestPayload create() => RotationApprovalRequestPayload._();
  RotationApprovalRequestPayload createEmptyInstance() => create();
  static $pb.PbList<RotationApprovalRequestPayload> createRepeated() => $pb.PbList<RotationApprovalRequestPayload>();
  @$core.pragma('dart2js:noInline')
  static RotationApprovalRequestPayload getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RotationApprovalRequestPayload>(create);
  static RotationApprovalRequestPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get rotationHash => $_getN(0);
  @$pb.TagNumber(1)
  set rotationHash($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasRotationHash() => $_has(0);
  @$pb.TagNumber(1)
  void clearRotationHash() => clearField(1);

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
  ApprovalKindV3 get approvalKind => $_getN(5);
  @$pb.TagNumber(6)
  set approvalKind(ApprovalKindV3 v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasApprovalKind() => $_has(5);
  @$pb.TagNumber(6)
  void clearApprovalKind() => clearField(6);

  /// Only set with APPROVAL_KIND_DEVICE_SET_CHANGE — the device list after
  /// the change, so that the dialog can name what is being removed.
  @$pb.TagNumber(7)
  $core.List<$core.List<$core.int>> get newDeviceNodeIds => $_getList(6);
}

/// TwinSync payload for ROTATION_APPROVAL_RESPONSE (Linked → Primary).
class RotationApprovalResponsePayload extends $pb.GeneratedMessage {
  factory RotationApprovalResponsePayload({
    RotationApprovalToken? token,
    $core.bool? rejected,
  }) {
    final $result = create();
    if (token != null) {
      $result.token = token;
    }
    if (rejected != null) {
      $result.rejected = rejected;
    }
    return $result;
  }
  RotationApprovalResponsePayload._() : super();
  factory RotationApprovalResponsePayload.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RotationApprovalResponsePayload.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RotationApprovalResponsePayload', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..aOM<RotationApprovalToken>(1, _omitFieldNames ? '' : 'token', subBuilder: RotationApprovalToken.create)
    ..aOB(2, _omitFieldNames ? '' : 'rejected')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RotationApprovalResponsePayload clone() => RotationApprovalResponsePayload()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RotationApprovalResponsePayload copyWith(void Function(RotationApprovalResponsePayload) updates) => super.copyWith((message) => updates(message as RotationApprovalResponsePayload)) as RotationApprovalResponsePayload;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RotationApprovalResponsePayload create() => RotationApprovalResponsePayload._();
  RotationApprovalResponsePayload createEmptyInstance() => create();
  static $pb.PbList<RotationApprovalResponsePayload> createRepeated() => $pb.PbList<RotationApprovalResponsePayload>();
  @$core.pragma('dart2js:noInline')
  static RotationApprovalResponsePayload getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RotationApprovalResponsePayload>(create);
  static RotationApprovalResponsePayload? _defaultInstance;

  @$pb.TagNumber(1)
  RotationApprovalToken get token => $_getN(0);
  @$pb.TagNumber(1)
  set token(RotationApprovalToken v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasToken() => $_has(0);
  @$pb.TagNumber(1)
  void clearToken() => clearField(1);
  @$pb.TagNumber(1)
  RotationApprovalToken ensureToken() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.bool get rejected => $_getBF(1);
  @$pb.TagNumber(2)
  set rejected($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasRejected() => $_has(1);
  @$pb.TagNumber(2)
  void clearRejected() => clearField(2);
}

/// Linked device → all contacts: "I am actively rejecting a rotation"
class RotationRejectionAlertPayload extends $pb.GeneratedMessage {
  factory RotationRejectionAlertPayload({
    $core.List<$core.int>? userId,
    $core.List<$core.int>? deviceNodeId,
    $core.List<$core.int>? rotationHash,
    $core.List<$core.int>? deviceEd25519Sig,
    $core.List<$core.int>? deviceMlDsaSig,
  }) {
    final $result = create();
    if (userId != null) {
      $result.userId = userId;
    }
    if (deviceNodeId != null) {
      $result.deviceNodeId = deviceNodeId;
    }
    if (rotationHash != null) {
      $result.rotationHash = rotationHash;
    }
    if (deviceEd25519Sig != null) {
      $result.deviceEd25519Sig = deviceEd25519Sig;
    }
    if (deviceMlDsaSig != null) {
      $result.deviceMlDsaSig = deviceMlDsaSig;
    }
    return $result;
  }
  RotationRejectionAlertPayload._() : super();
  factory RotationRejectionAlertPayload.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RotationRejectionAlertPayload.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RotationRejectionAlertPayload', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'userId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'deviceNodeId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'rotationHash', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'deviceEd25519Sig', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'deviceMlDsaSig', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RotationRejectionAlertPayload clone() => RotationRejectionAlertPayload()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RotationRejectionAlertPayload copyWith(void Function(RotationRejectionAlertPayload) updates) => super.copyWith((message) => updates(message as RotationRejectionAlertPayload)) as RotationRejectionAlertPayload;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RotationRejectionAlertPayload create() => RotationRejectionAlertPayload._();
  RotationRejectionAlertPayload createEmptyInstance() => create();
  static $pb.PbList<RotationRejectionAlertPayload> createRepeated() => $pb.PbList<RotationRejectionAlertPayload>();
  @$core.pragma('dart2js:noInline')
  static RotationRejectionAlertPayload getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RotationRejectionAlertPayload>(create);
  static RotationRejectionAlertPayload? _defaultInstance;

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
  $core.List<$core.int> get rotationHash => $_getN(2);
  @$pb.TagNumber(3)
  set rotationHash($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasRotationHash() => $_has(2);
  @$pb.TagNumber(3)
  void clearRotationHash() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get deviceEd25519Sig => $_getN(3);
  @$pb.TagNumber(4)
  set deviceEd25519Sig($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasDeviceEd25519Sig() => $_has(3);
  @$pb.TagNumber(4)
  void clearDeviceEd25519Sig() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get deviceMlDsaSig => $_getN(4);
  @$pb.TagNumber(5)
  set deviceMlDsaSig($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasDeviceMlDsaSig() => $_has(4);
  @$pb.TagNumber(5)
  void clearDeviceMlDsaSig() => clearField(5);
}

/// Proof that a device-set shrink was co-authorized by remaining devices.
/// Embedded in AuthManifest (field 13) when devices are removed.
class DeviceSetChangeProof extends $pb.GeneratedMessage {
  factory DeviceSetChangeProof({
    $core.int? previousDeviceCount,
    $core.List<$core.int>? changeHash,
    $core.Iterable<RotationApprovalToken>? approvals,
  }) {
    final $result = create();
    if (previousDeviceCount != null) {
      $result.previousDeviceCount = previousDeviceCount;
    }
    if (changeHash != null) {
      $result.changeHash = changeHash;
    }
    if (approvals != null) {
      $result.approvals.addAll(approvals);
    }
    return $result;
  }
  DeviceSetChangeProof._() : super();
  factory DeviceSetChangeProof.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DeviceSetChangeProof.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DeviceSetChangeProof', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'previousDeviceCount', $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'changeHash', $pb.PbFieldType.OY)
    ..pc<RotationApprovalToken>(3, _omitFieldNames ? '' : 'approvals', $pb.PbFieldType.PM, subBuilder: RotationApprovalToken.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DeviceSetChangeProof clone() => DeviceSetChangeProof()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DeviceSetChangeProof copyWith(void Function(DeviceSetChangeProof) updates) => super.copyWith((message) => updates(message as DeviceSetChangeProof)) as DeviceSetChangeProof;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeviceSetChangeProof create() => DeviceSetChangeProof._();
  DeviceSetChangeProof createEmptyInstance() => create();
  static $pb.PbList<DeviceSetChangeProof> createRepeated() => $pb.PbList<DeviceSetChangeProof>();
  @$core.pragma('dart2js:noInline')
  static DeviceSetChangeProof getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DeviceSetChangeProof>(create);
  static DeviceSetChangeProof? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get previousDeviceCount => $_getIZ(0);
  @$pb.TagNumber(1)
  set previousDeviceCount($core.int v) { $_setUnsignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPreviousDeviceCount() => $_has(0);
  @$pb.TagNumber(1)
  void clearPreviousDeviceCount() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get changeHash => $_getN(1);
  @$pb.TagNumber(2)
  set changeHash($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChangeHash() => $_has(1);
  @$pb.TagNumber(2)
  void clearChangeHash() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<RotationApprovalToken> get approvals => $_getList(2);
}

///  ═══════════════════════════════════════════════════════════════════════
///  §14.5 path 2 — THE PAIRWISE DEVICE-SET ANNOUNCEMENT
///  ═══════════════════════════════════════════════════════════════════════
///
///  v4_1 §14.5, verbatim: "**The device set is announced pairwise.** Changes
///  go out to contacts as an ordinary delivery; the contact holds the state.
///  The announcement carries the previous device count and the
///  countersignatures of the remaining devices, so that a **shrinking of the
///  device set** requires proof. These very countersignatures are the quorum
///  from §14.4."
///
///  WHY THIS TYPE HAD TO EXIST. Before it, `verifyRotationCoAuth` was fed a
///  `const cachedDeviceSigKeys = <DeviceSigInfo>[]` — a compile-time empty
///  list — so every emergency rotation resolved to `RotationCoAuthResult
///  .legacy` and was applied unchecked. §14.5 DOES prescribe the legacy
///  branch, but as the exception for a brand-new or long-absent contact; with
///  no carrier for the device set it was the rule, for every contact, always.
///  The §7.5 protection against a seed thief was therefore universally
///  absent.
///
///  WHY NOT A PUBLIC OBJECT. §14.5: "A public durable object was explicitly
///  rejected. It would be formally permissible … but would make the device
///  set of every identity enumerable network-wide and turn the identity
///  itself into a discoverable object — a breach of the no-directory
///  property at the person level."
///
///  PRIVACY (§5.1, §23.6 row 1 / RL-1). This rides the ordinary delivery
///  path, so at the egress it is cells of the fixed size at the constant
///  rate to slot-drawn partners — indistinguishable from cover, and the
///  observable graph stays the sync graph, decoupled from the social graph.
///  The only party that learns anything is the contact, who already holds
///  the contact relation; the announcement adds the device COUNT and the
///  device-sig pubkeys of a person they already correspond with. It does not
///  widen the social graph by one edge.
class DeviceSetAnnounceV3 extends $pb.GeneratedMessage {
  factory DeviceSetAnnounceV3({
    $core.int? seq,
    $fixnum.Int64? issuedAtMs,
    $core.int? previousDeviceCount,
    $core.Iterable<AuthorizedDeviceSigningKeys>? deviceSigKeys,
    $core.List<$core.int>? changeHash,
    $core.Iterable<RotationApprovalToken>? approvals,
    $core.List<$core.int>? userSignatureEd25519,
  }) {
    final $result = create();
    if (seq != null) {
      $result.seq = seq;
    }
    if (issuedAtMs != null) {
      $result.issuedAtMs = issuedAtMs;
    }
    if (previousDeviceCount != null) {
      $result.previousDeviceCount = previousDeviceCount;
    }
    if (deviceSigKeys != null) {
      $result.deviceSigKeys.addAll(deviceSigKeys);
    }
    if (changeHash != null) {
      $result.changeHash = changeHash;
    }
    if (approvals != null) {
      $result.approvals.addAll(approvals);
    }
    if (userSignatureEd25519 != null) {
      $result.userSignatureEd25519 = userSignatureEd25519;
    }
    return $result;
  }
  DeviceSetAnnounceV3._() : super();
  factory DeviceSetAnnounceV3.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DeviceSetAnnounceV3.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DeviceSetAnnounceV3', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.OU3)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'issuedAtMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'previousDeviceCount', $pb.PbFieldType.OU3)
    ..pc<AuthorizedDeviceSigningKeys>(4, _omitFieldNames ? '' : 'deviceSigKeys', $pb.PbFieldType.PM, subBuilder: AuthorizedDeviceSigningKeys.create)
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'changeHash', $pb.PbFieldType.OY)
    ..pc<RotationApprovalToken>(6, _omitFieldNames ? '' : 'approvals', $pb.PbFieldType.PM, subBuilder: RotationApprovalToken.create)
    ..a<$core.List<$core.int>>(7, _omitFieldNames ? '' : 'userSignatureEd25519', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DeviceSetAnnounceV3 clone() => DeviceSetAnnounceV3()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DeviceSetAnnounceV3 copyWith(void Function(DeviceSetAnnounceV3) updates) => super.copyWith((message) => updates(message as DeviceSetAnnounceV3)) as DeviceSetAnnounceV3;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeviceSetAnnounceV3 create() => DeviceSetAnnounceV3._();
  DeviceSetAnnounceV3 createEmptyInstance() => create();
  static $pb.PbList<DeviceSetAnnounceV3> createRepeated() => $pb.PbList<DeviceSetAnnounceV3>();
  @$core.pragma('dart2js:noInline')
  static DeviceSetAnnounceV3 getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DeviceSetAnnounceV3>(create);
  static DeviceSetAnnounceV3? _defaultInstance;

  /// Monotonic per announcing identity. Replay defence: a receiver keeps the
  /// highest seq it has accepted per contact and refuses anything <=.
  /// Without it a captured older announcement — with a LARGER device set —
  /// could be replayed to restore a locked-out device's key as a valid
  /// countersigner.
  @$pb.TagNumber(1)
  $core.int get seq => $_getIZ(0);
  @$pb.TagNumber(1)
  set seq($core.int v) { $_setUnsignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSeq() => $_has(0);
  @$pb.TagNumber(1)
  void clearSeq() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get issuedAtMs => $_getI64(1);
  @$pb.TagNumber(2)
  set issuedAtMs($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasIssuedAtMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearIssuedAtMs() => clearField(2);

  /// §14.5 "carries the previous device count". The receiver does NOT trust
  /// this for the quorum denominator (it is the suspect's own claim); it
  /// counts over its own CACHED set. The field is kept because §14.8 makes
  /// it visible: "contacts see the device count in the announcement, and a
  /// jump stands out".
  @$pb.TagNumber(3)
  $core.int get previousDeviceCount => $_getIZ(2);
  @$pb.TagNumber(3)
  set previousDeviceCount($core.int v) { $_setUnsignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasPreviousDeviceCount() => $_has(2);
  @$pb.TagNumber(3)
  void clearPreviousDeviceCount() => clearField(3);

  /// The device set as it stands AFTER the change.
  @$pb.TagNumber(4)
  $core.List<AuthorizedDeviceSigningKeys> get deviceSigKeys => $_getList(3);

  /// SHA-256(userId || sorted(device_node_ids) || seq) — what the approvals
  /// below sign. Recomputed by the receiver; never taken from the wire.
  @$pb.TagNumber(5)
  $core.List<$core.int> get changeHash => $_getN(4);
  @$pb.TagNumber(5)
  set changeHash($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasChangeHash() => $_has(4);
  @$pb.TagNumber(5)
  void clearChangeHash() => clearField(5);

  /// §14.5: "the countersignatures of the remaining devices, so that a
  /// shrinking of the device set requires proof. These very
  /// countersignatures are the quorum from §14.4."
  @$pb.TagNumber(6)
  $core.List<RotationApprovalToken> get approvals => $_getList(5);

  /// The identity (User-Sig) signature over fields 1-6, under the CURRENT
  /// identity key. Proves the announcement came from the contact and not
  /// from a relay; the contact's stored trust anchor verifies it.
  @$pb.TagNumber(7)
  $core.List<$core.int> get userSignatureEd25519 => $_getN(6);
  @$pb.TagNumber(7)
  set userSignatureEd25519($core.List<$core.int> v) { $_setBytes(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasUserSignatureEd25519() => $_has(6);
  @$pb.TagNumber(7)
  void clearUserSignatureEd25519() => clearField(7);
}

/// Self-contained, self-signed system-channel record. Distinct wire type
/// from CHANNEL_POST (D1-S1): system channels are ownerless and carry no
/// subscriber registry, so every record must be verifiable stand-alone via
/// the inline pubkeys (KEX-Gate context-proof, §8.2/§9.5.6).
/// One link of the founding->current rotation chain (v4.2 §4.5.4). The OLD
/// key pair signs `new_ed25519_pk || new_ml_dsa_pk`; the signature is hybrid
/// because the chain is "a long-lived verifiable artifact" (§4.5.4) — an
/// Ed25519-only link would leave the founding binding of every rotated
/// author on classical security alone.
/// Persisted counterpart: `StoredRotationLink` (`identity/identity_context.dart`).
class SysChanRotationLink extends $pb.GeneratedMessage {
  factory SysChanRotationLink({
    $core.List<$core.int>? oldEd25519Pk,
    $core.List<$core.int>? oldMlDsaPk,
    $core.List<$core.int>? newEd25519Pk,
    $core.List<$core.int>? newMlDsaPk,
    $core.List<$core.int>? sigEd25519,
    $core.List<$core.int>? sigMlDsa,
  }) {
    final $result = create();
    if (oldEd25519Pk != null) {
      $result.oldEd25519Pk = oldEd25519Pk;
    }
    if (oldMlDsaPk != null) {
      $result.oldMlDsaPk = oldMlDsaPk;
    }
    if (newEd25519Pk != null) {
      $result.newEd25519Pk = newEd25519Pk;
    }
    if (newMlDsaPk != null) {
      $result.newMlDsaPk = newMlDsaPk;
    }
    if (sigEd25519 != null) {
      $result.sigEd25519 = sigEd25519;
    }
    if (sigMlDsa != null) {
      $result.sigMlDsa = sigMlDsa;
    }
    return $result;
  }
  SysChanRotationLink._() : super();
  factory SysChanRotationLink.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SysChanRotationLink.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SysChanRotationLink', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'oldEd25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'oldMlDsaPk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'newEd25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'newMlDsaPk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'sigEd25519', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(6, _omitFieldNames ? '' : 'sigMlDsa', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SysChanRotationLink clone() => SysChanRotationLink()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SysChanRotationLink copyWith(void Function(SysChanRotationLink) updates) => super.copyWith((message) => updates(message as SysChanRotationLink)) as SysChanRotationLink;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SysChanRotationLink create() => SysChanRotationLink._();
  SysChanRotationLink createEmptyInstance() => create();
  static $pb.PbList<SysChanRotationLink> createRepeated() => $pb.PbList<SysChanRotationLink>();
  @$core.pragma('dart2js:noInline')
  static SysChanRotationLink getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SysChanRotationLink>(create);
  static SysChanRotationLink? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get oldEd25519Pk => $_getN(0);
  @$pb.TagNumber(1)
  set oldEd25519Pk($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasOldEd25519Pk() => $_has(0);
  @$pb.TagNumber(1)
  void clearOldEd25519Pk() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get oldMlDsaPk => $_getN(1);
  @$pb.TagNumber(2)
  set oldMlDsaPk($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasOldMlDsaPk() => $_has(1);
  @$pb.TagNumber(2)
  void clearOldMlDsaPk() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get newEd25519Pk => $_getN(2);
  @$pb.TagNumber(3)
  set newEd25519Pk($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasNewEd25519Pk() => $_has(2);
  @$pb.TagNumber(3)
  void clearNewEd25519Pk() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get newMlDsaPk => $_getN(3);
  @$pb.TagNumber(4)
  set newMlDsaPk($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasNewMlDsaPk() => $_has(3);
  @$pb.TagNumber(4)
  void clearNewMlDsaPk() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get sigEd25519 => $_getN(4);
  @$pb.TagNumber(5)
  set sigEd25519($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasSigEd25519() => $_has(4);
  @$pb.TagNumber(5)
  void clearSigEd25519() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get sigMlDsa => $_getN(5);
  @$pb.TagNumber(6)
  set sigMlDsa($core.List<$core.int> v) { $_setBytes(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasSigMlDsa() => $_has(5);
  @$pb.TagNumber(6)
  void clearSigMlDsa() => clearField(6);
}

class SystemChannelRecord extends $pb.GeneratedMessage {
  factory SystemChannelRecord({
    $core.List<$core.int>? channelId,
    $core.List<$core.int>? recordId,
    $core.int? kind,
    $core.List<$core.int>? authorUserId,
    $core.List<$core.int>? authorEd25519Pk,
    $core.List<$core.int>? authorMlDsaPk,
    $fixnum.Int64? timestampMs,
    $core.String? text,
    $core.List<$core.int>? targetRecordId,
    $core.int? voteOption,
    $core.List<$core.int>? sigEd25519,
    $core.List<$core.int>? sigMlDsa,
    $core.Iterable<SysChanRotationLink>? rotationChain,
  }) {
    final $result = create();
    if (channelId != null) {
      $result.channelId = channelId;
    }
    if (recordId != null) {
      $result.recordId = recordId;
    }
    if (kind != null) {
      $result.kind = kind;
    }
    if (authorUserId != null) {
      $result.authorUserId = authorUserId;
    }
    if (authorEd25519Pk != null) {
      $result.authorEd25519Pk = authorEd25519Pk;
    }
    if (authorMlDsaPk != null) {
      $result.authorMlDsaPk = authorMlDsaPk;
    }
    if (timestampMs != null) {
      $result.timestampMs = timestampMs;
    }
    if (text != null) {
      $result.text = text;
    }
    if (targetRecordId != null) {
      $result.targetRecordId = targetRecordId;
    }
    if (voteOption != null) {
      $result.voteOption = voteOption;
    }
    if (sigEd25519 != null) {
      $result.sigEd25519 = sigEd25519;
    }
    if (sigMlDsa != null) {
      $result.sigMlDsa = sigMlDsa;
    }
    if (rotationChain != null) {
      $result.rotationChain.addAll(rotationChain);
    }
    return $result;
  }
  SystemChannelRecord._() : super();
  factory SystemChannelRecord.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SystemChannelRecord.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SystemChannelRecord', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'channelId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'recordId', $pb.PbFieldType.OY)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'kind', $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'authorUserId', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'authorEd25519Pk', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(6, _omitFieldNames ? '' : 'authorMlDsaPk', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(7, _omitFieldNames ? '' : 'timestampMs', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(8, _omitFieldNames ? '' : 'text')
    ..a<$core.List<$core.int>>(9, _omitFieldNames ? '' : 'targetRecordId', $pb.PbFieldType.OY)
    ..a<$core.int>(10, _omitFieldNames ? '' : 'voteOption', $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(11, _omitFieldNames ? '' : 'sigEd25519', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(12, _omitFieldNames ? '' : 'sigMlDsa', $pb.PbFieldType.OY)
    ..pc<SysChanRotationLink>(13, _omitFieldNames ? '' : 'rotationChain', $pb.PbFieldType.PM, subBuilder: SysChanRotationLink.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SystemChannelRecord clone() => SystemChannelRecord()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SystemChannelRecord copyWith(void Function(SystemChannelRecord) updates) => super.copyWith((message) => updates(message as SystemChannelRecord)) as SystemChannelRecord;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SystemChannelRecord create() => SystemChannelRecord._();
  SystemChannelRecord createEmptyInstance() => create();
  static $pb.PbList<SystemChannelRecord> createRepeated() => $pb.PbList<SystemChannelRecord>();
  @$core.pragma('dart2js:noInline')
  static SystemChannelRecord getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SystemChannelRecord>(create);
  static SystemChannelRecord? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get channelId => $_getN(0);
  @$pb.TagNumber(1)
  set channelId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasChannelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChannelId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get recordId => $_getN(1);
  @$pb.TagNumber(2)
  set recordId($core.List<$core.int> v) { $_setBytes(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasRecordId() => $_has(1);
  @$pb.TagNumber(2)
  void clearRecordId() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get kind => $_getIZ(2);
  @$pb.TagNumber(3)
  set kind($core.int v) { $_setUnsignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasKind() => $_has(2);
  @$pb.TagNumber(3)
  void clearKind() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get authorUserId => $_getN(3);
  @$pb.TagNumber(4)
  set authorUserId($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasAuthorUserId() => $_has(3);
  @$pb.TagNumber(4)
  void clearAuthorUserId() => clearField(4);

  /// The author's CURRENT signing keys, inline for stand-alone verify. They
  /// equal the founding keys only as long as the author never rotated; after
  /// a rotation `rotation_chain` (13) carries founding -> these.
  @$pb.TagNumber(5)
  $core.List<$core.int> get authorEd25519Pk => $_getN(4);
  @$pb.TagNumber(5)
  set authorEd25519Pk($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAuthorEd25519Pk() => $_has(4);
  @$pb.TagNumber(5)
  void clearAuthorEd25519Pk() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get authorMlDsaPk => $_getN(5);
  @$pb.TagNumber(6)
  set authorMlDsaPk($core.List<$core.int> v) { $_setBytes(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasAuthorMlDsaPk() => $_has(5);
  @$pb.TagNumber(6)
  void clearAuthorMlDsaPk() => clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get timestampMs => $_getI64(6);
  @$pb.TagNumber(7)
  set timestampMs($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasTimestampMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearTimestampMs() => clearField(7);

  @$pb.TagNumber(8)
  $core.String get text => $_getSZ(7);
  @$pb.TagNumber(8)
  set text($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasText() => $_has(7);
  @$pb.TagNumber(8)
  void clearText() => clearField(8);

  /// VOTE (§9.5.3 embedded FR poll — open records, tallied locally) and
  /// RETRACT (D2 tombstone) reference their target here:
  @$pb.TagNumber(9)
  $core.List<$core.int> get targetRecordId => $_getN(8);
  @$pb.TagNumber(9)
  set targetRecordId($core.List<$core.int> v) { $_setBytes(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasTargetRecordId() => $_has(8);
  @$pb.TagNumber(9)
  void clearTargetRecordId() => clearField(9);

  @$pb.TagNumber(10)
  $core.int get voteOption => $_getIZ(9);
  @$pb.TagNumber(10)
  set voteOption($core.int v) { $_setUnsignedInt32(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasVoteOption() => $_has(9);
  @$pb.TagNumber(10)
  void clearVoteOption() => clearField(10);

  /// Hybrid self-signature (H-2 pattern) over the canonical content
  /// (this message serialized with both sig fields empty):
  @$pb.TagNumber(11)
  $core.List<$core.int> get sigEd25519 => $_getN(10);
  @$pb.TagNumber(11)
  set sigEd25519($core.List<$core.int> v) { $_setBytes(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasSigEd25519() => $_has(10);
  @$pb.TagNumber(11)
  void clearSigEd25519() => clearField(11);

  @$pb.TagNumber(12)
  $core.List<$core.int> get sigMlDsa => $_getN(11);
  @$pb.TagNumber(12)
  set sigMlDsa($core.List<$core.int> v) { $_setBytes(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasSigMlDsa() => $_has(11);
  @$pb.TagNumber(12)
  void clearSigMlDsa() => clearField(12);

  /// Continuity proof for a rotated author (v4.2 §4.1/§4.5.4/§14.5): empty
  /// for a never-rotated identity, otherwise founding -> current, oldest
  /// link first. It rides ALONG WITH the record — "proofs accompany the
  /// action" (§14.5 path 1) — because a system channel is ownerless and its
  /// authors are mostly not contacts (§16.7), so there is no pairwise cache
  /// to look the chain up in, and §14.5 rejected a public directory.
  /// It is part of the canonical bytes, so the self-signature covers it.
  @$pb.TagNumber(13)
  $core.List<SysChanRotationLink> get rotationChain => $_getList(12);
}

/// Hourly anti-entropy Digest → Summary → Want → Push (§9.5.7 D1-S2),
/// piggy-backed on the channel-index gossip slot. BOOT-path
/// InfrastructureFrames (§2.3.5): HMAC + inner record self-signature.
class SysChanDigest extends $pb.GeneratedMessage {
  factory SysChanDigest({
    $core.List<$core.int>? channelId,
    $core.int? recordCount,
    $core.List<$core.int>? setHash,
  }) {
    final $result = create();
    if (channelId != null) {
      $result.channelId = channelId;
    }
    if (recordCount != null) {
      $result.recordCount = recordCount;
    }
    if (setHash != null) {
      $result.setHash = setHash;
    }
    return $result;
  }
  SysChanDigest._() : super();
  factory SysChanDigest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SysChanDigest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SysChanDigest', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'channelId', $pb.PbFieldType.OY)
    ..a<$core.int>(2, _omitFieldNames ? '' : 'recordCount', $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'setHash', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SysChanDigest clone() => SysChanDigest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SysChanDigest copyWith(void Function(SysChanDigest) updates) => super.copyWith((message) => updates(message as SysChanDigest)) as SysChanDigest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SysChanDigest create() => SysChanDigest._();
  SysChanDigest createEmptyInstance() => create();
  static $pb.PbList<SysChanDigest> createRepeated() => $pb.PbList<SysChanDigest>();
  @$core.pragma('dart2js:noInline')
  static SysChanDigest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SysChanDigest>(create);
  static SysChanDigest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get channelId => $_getN(0);
  @$pb.TagNumber(1)
  set channelId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasChannelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChannelId() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get recordCount => $_getIZ(1);
  @$pb.TagNumber(2)
  set recordCount($core.int v) { $_setUnsignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasRecordCount() => $_has(1);
  @$pb.TagNumber(2)
  void clearRecordCount() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get setHash => $_getN(2);
  @$pb.TagNumber(3)
  set setHash($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSetHash() => $_has(2);
  @$pb.TagNumber(3)
  void clearSetHash() => clearField(3);
}

class SysChanSummary extends $pb.GeneratedMessage {
  factory SysChanSummary({
    $core.List<$core.int>? channelId,
    $core.Iterable<$core.List<$core.int>>? fingerprints,
  }) {
    final $result = create();
    if (channelId != null) {
      $result.channelId = channelId;
    }
    if (fingerprints != null) {
      $result.fingerprints.addAll(fingerprints);
    }
    return $result;
  }
  SysChanSummary._() : super();
  factory SysChanSummary.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SysChanSummary.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SysChanSummary', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'channelId', $pb.PbFieldType.OY)
    ..p<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'fingerprints', $pb.PbFieldType.PY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SysChanSummary clone() => SysChanSummary()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SysChanSummary copyWith(void Function(SysChanSummary) updates) => super.copyWith((message) => updates(message as SysChanSummary)) as SysChanSummary;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SysChanSummary create() => SysChanSummary._();
  SysChanSummary createEmptyInstance() => create();
  static $pb.PbList<SysChanSummary> createRepeated() => $pb.PbList<SysChanSummary>();
  @$core.pragma('dart2js:noInline')
  static SysChanSummary getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SysChanSummary>(create);
  static SysChanSummary? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get channelId => $_getN(0);
  @$pb.TagNumber(1)
  set channelId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasChannelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChannelId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.List<$core.int>> get fingerprints => $_getList(1);
}

class SysChanWant extends $pb.GeneratedMessage {
  factory SysChanWant({
    $core.List<$core.int>? channelId,
    $core.Iterable<$core.List<$core.int>>? fingerprints,
  }) {
    final $result = create();
    if (channelId != null) {
      $result.channelId = channelId;
    }
    if (fingerprints != null) {
      $result.fingerprints.addAll(fingerprints);
    }
    return $result;
  }
  SysChanWant._() : super();
  factory SysChanWant.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SysChanWant.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SysChanWant', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'channelId', $pb.PbFieldType.OY)
    ..p<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'fingerprints', $pb.PbFieldType.PY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SysChanWant clone() => SysChanWant()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SysChanWant copyWith(void Function(SysChanWant) updates) => super.copyWith((message) => updates(message as SysChanWant)) as SysChanWant;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SysChanWant create() => SysChanWant._();
  SysChanWant createEmptyInstance() => create();
  static $pb.PbList<SysChanWant> createRepeated() => $pb.PbList<SysChanWant>();
  @$core.pragma('dart2js:noInline')
  static SysChanWant getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SysChanWant>(create);
  static SysChanWant? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get channelId => $_getN(0);
  @$pb.TagNumber(1)
  set channelId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasChannelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChannelId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.List<$core.int>> get fingerprints => $_getList(1);
}

class SysChanPush extends $pb.GeneratedMessage {
  factory SysChanPush({
    $core.List<$core.int>? channelId,
    $core.Iterable<$core.List<$core.int>>? records,
    $core.int? ttl,
  }) {
    final $result = create();
    if (channelId != null) {
      $result.channelId = channelId;
    }
    if (records != null) {
      $result.records.addAll(records);
    }
    if (ttl != null) {
      $result.ttl = ttl;
    }
    return $result;
  }
  SysChanPush._() : super();
  factory SysChanPush.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SysChanPush.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SysChanPush', package: const $pb.PackageName(_omitMessageNames ? '' : 'cleona'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'channelId', $pb.PbFieldType.OY)
    ..p<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'records', $pb.PbFieldType.PY)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'ttl', $pb.PbFieldType.OU3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SysChanPush clone() => SysChanPush()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SysChanPush copyWith(void Function(SysChanPush) updates) => super.copyWith((message) => updates(message as SysChanPush)) as SysChanPush;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SysChanPush create() => SysChanPush._();
  SysChanPush createEmptyInstance() => create();
  static $pb.PbList<SysChanPush> createRepeated() => $pb.PbList<SysChanPush>();
  @$core.pragma('dart2js:noInline')
  static SysChanPush getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SysChanPush>(create);
  static SysChanPush? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get channelId => $_getN(0);
  @$pb.TagNumber(1)
  set channelId($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasChannelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearChannelId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.List<$core.int>> get records => $_getList(1);

  @$pb.TagNumber(3)
  $core.int get ttl => $_getIZ(2);
  @$pb.TagNumber(3)
  set ttl($core.int v) { $_setUnsignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTtl() => $_has(2);
  @$pb.TagNumber(3)
  void clearTtl() => clearField(3);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');

// The media archive's downscaler — §21.6, tier 2 and tier 3.
//
// §21.6 defines four tiers: 0-30 d original, 30-90 d a preview
// (~20-50 KB), 90-365 d a mini (~2-5 KB, 64 px), after that only date,
// size and a type icon. The moment the original leaves the device, the
// preview is the ONLY thing the chat can still show. This file produces
// both images; they are stored in the index record
// (`ArchiveEntry.previewBytes` / `.miniBytes`), and that record lives in
// the encrypted store (`MessageStore`, SQLite3 Multiple Ciphers, §4.5.3
// form 1, §21.4.2 destination 1). **No plaintext file appears next to
// the attachment** — the `MediaCipher`/`MediaVault` route is deliberately
// not taken here: it would be a second storage form for 5 KB, with its
// own sweeper and its own orphan question.
//
// **No video.** §21.6 names videos explicitly, but there is no frame
// grab anywhere in the tree: `native/cleona_video/` is the LIVE call
// path (`cleona_video_open`/`_read_encoded`/`_submit_encoded`/
// `_get_texture_id`, `native/cleona_video/cleona_video.h`) — it has
// neither a container reader (mp4/mov/webm) nor a way back from decoded
// pixels into main memory. `ffmpeg` exists on Linux only and only
// optionally (`voice_transcription_service.dart:383`, for transcription;
// on Android it is replaced by a platform channel). A downscaler that
// shows a picture on one of the five ranks and nothing on the other four
// is worse than none. Video therefore gets a clean
// [ArchiveThumbnailRefusal.videoNoFrameGrab] and falls back in the chat
// to the metadata tile (date, size, type icon) — the same rendering as
// tier 4.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Why no images were produced. [none] means both are there.
enum ArchiveThumbnailRefusal {
  none,

  /// Zero bytes of input.
  empty,

  /// The MIME type says: not a still image (audio, text, PDF, ZIP, …).
  notAnImage,

  /// Video — the frame grab is missing from the tree, see the file header.
  videoNoFrameGrab,

  /// No decoder recognises the bytes, or decoding failed.
  undecodable,

  /// More pixels than [ArchiveThumbnails.maxSourcePixels].
  tooManyPixels,
}

/// The outcome of one downscaling run.
class ArchiveThumbnailResult {
  /// Tier 2, ~20-50 KB. `null` when [refusal] is not
  /// [ArchiveThumbnailRefusal.none].
  final Uint8List? preview;

  /// Tier 3, longest edge [ArchiveThumbnails.miniEdge], ~2-5 KB.
  final Uint8List? mini;

  /// `image/jpeg` or `image/png` — applies to BOTH images.
  final String? mimeType;

  final int sourceWidth;
  final int sourceHeight;
  final ArchiveThumbnailRefusal refusal;

  const ArchiveThumbnailResult._({
    this.preview,
    this.mini,
    this.mimeType,
    this.sourceWidth = 0,
    this.sourceHeight = 0,
    this.refusal = ArchiveThumbnailRefusal.none,
  });

  factory ArchiveThumbnailResult.refused(ArchiveThumbnailRefusal r,
          {int width = 0, int height = 0}) =>
      ArchiveThumbnailResult._(
          refusal: r, sourceWidth: width, sourceHeight: height);

  bool get ok => refusal == ArchiveThumbnailRefusal.none;
}

/// Produces the preview (tier 2) and the mini (tier 3) from an original.
class ArchiveThumbnails {
  ArchiveThumbnails._();

  /// Longest edge of the preview.
  static const int previewMaxEdge = 512;

  /// Ceiling for the preview. §21.6 says ~20-50 KB; 50 KB is the ceiling
  /// the quality ladder has to land under. There is no floor — a flat
  /// image yields a few hundred bytes, and that is correct.
  static const int previewCeilingBytes = 50 * 1024;

  /// §21.6 tier 3: 64 px.
  static const int miniEdge = 64;
  static const int miniCeilingBytes = 5 * 1024;

  /// Source ceiling: 12 megapixels.
  ///
  /// **Why there is a ceiling, and why it sits exactly here.**
  /// `package:image` (4.8.0) has no downscaling JPEG decoder. It stores
  /// the coefficients of every 8x8 block as its own `Int32List(64)` —
  /// `JpegFrame.prepareComponents` in the package's own
  /// `lib/src/formats/jpeg/jpeg_frame.dart`, byte-for-byte the same file
  /// in 4.10.1 — and only then builds the image. Measured via `VmHWM`
  /// against the Dart process baseline (S392,
  /// `test/smoke/smoke_archive_thumbnail.dart`, Linux x64):
  ///
  /// | Source | Peak over baseline | per pixel |
  /// |---|---|---|
  /// | 1600x1200 (1.9 MP) | 49 MB | 26.8 B |
  /// | 3000x2000 (6.0 MP) | 133 MB | 23.2 B |
  /// | 4000x3000 (12.0 MP) | 288 MB | 25.2 B |
  /// | 5000x4000 (20.0 MP) | 421 MB | 22.1 B |
  /// | 7360x5440 (40.0 MP) | 814 MB | 21.3 B |
  ///
  /// So roughly **24 bytes per pixel, linear** — a 40 MP photo costs
  /// 0.8 GB. The app carries no `largeHeap`
  /// (`android/app/src/main/AndroidManifest.xml`, measured: the string
  /// does not occur there), and on Android and iOS the archive runs IN
  /// the application process (§22.6). The same arithmetic already
  /// justified `MediaCipher` (§21.4.2: "0 kB peak memory against six
  /// times the file size").
  ///
  /// 12 MP is the default capture resolution of practically every phone
  /// camera — even 48 MP sensors emit 12 MP in their standard mode.
  /// Above it nothing is decoded; the file is **refused at the header**
  /// ([ArchiveThumbnailRefusal.tooManyPixels], peak stays at the file
  /// size), and the tile then shows date, size and type icon, exactly as
  /// for video. Lifting the ceiling needs a platform downscaler (Android
  /// `BitmapFactory.inSampleSize`, Apple
  /// `CGImageSourceCreateThumbnailAtIndex`, Windows WIC) — native work of
  /// the same kind as the missing video frame grab, and it is not built
  /// here on the quiet.
  static const int maxSourcePixels = 12 * 1000 * 1000;

  /// Descending JPEG quality. The first value that fits under the
  /// ceiling wins.
  static const List<int> _jpegLadder = <int>[82, 74, 66, 58, 50, 42, 35];

  /// Downscales [bytes]. [mimeType] may be absent — then the content
  /// decides. Never throws; every failure comes back as an
  /// [ArchiveThumbnailRefusal], because an archive run must not fail on
  /// one broken file.
  static ArchiveThumbnailResult fromBytes(Uint8List bytes, {String? mimeType}) {
    if (bytes.isEmpty) {
      return ArchiveThumbnailResult.refused(ArchiveThumbnailRefusal.empty);
    }
    final refusalByType = _refuseByMime(mimeType);
    if (refusalByType != null) {
      return ArchiveThumbnailResult.refused(refusalByType);
    }

    try {
      final decoder = img.findDecoderForData(bytes);
      if (decoder == null) {
        return ArchiveThumbnailResult.refused(
            ArchiveThumbnailRefusal.undecodable);
      }
      // Read the dimensions first. An oversized image is never decoded.
      final size = _dimensions(bytes, decoder);
      if (size == null || size[0] <= 0 || size[1] <= 0) {
        return ArchiveThumbnailResult.refused(
            ArchiveThumbnailRefusal.undecodable);
      }
      if (size[0] * size[1] > maxSourcePixels) {
        return ArchiveThumbnailResult.refused(
            ArchiveThumbnailRefusal.tooManyPixels,
            width: size[0],
            height: size[1]);
      }

      var source = decoder.decode(bytes);
      if (source == null) {
        return ArchiveThumbnailResult.refused(
            ArchiveThumbnailRefusal.undecodable);
      }
      // Animated GIF/WebP: first frame only. Otherwise `copyResize`
      // would scale every frame and the peak would depend on the
      // animation's length.
      if (source.numFrames > 1) source = source.frames.first;

      final srcW = source.width;
      final srcH = source.height;
      final preview = _scaleTo(source, previewMaxEdge);
      source = null; // let the big one go before encoding starts

      final alpha = _usesAlpha(preview);
      final previewBytes =
          _encodeUnder(preview, alpha: alpha, ceiling: previewCeilingBytes);
      // The mini comes from the PREVIEW, not from the original: 512 px
      // -> 64 px costs nothing, 6000 px -> 64 px would be a second full
      // pass over the source.
      final miniImage = _scaleTo(preview, miniEdge);
      final miniBytes =
          _encodeUnder(miniImage, alpha: alpha, ceiling: miniCeilingBytes);

      return ArchiveThumbnailResult._(
        preview: previewBytes,
        mini: miniBytes,
        mimeType: alpha ? 'image/png' : 'image/jpeg',
        sourceWidth: srcW,
        sourceHeight: srcH,
      );
    } catch (_) {
      return ArchiveThumbnailResult.refused(
          ArchiveThumbnailRefusal.undecodable);
    }
  }

  // -- Internals -------------------------------------------------------

  static ArchiveThumbnailRefusal? _refuseByMime(String? mimeType) {
    if (mimeType == null || mimeType.isEmpty) return null;
    final m = mimeType.toLowerCase();
    if (m.startsWith('video/')) {
      return ArchiveThumbnailRefusal.videoNoFrameGrab;
    }
    if (!m.startsWith('image/')) return ArchiveThumbnailRefusal.notAnImage;
    return null;
  }

  /// Width and height without decoding.
  ///
  /// **Why JPEG gets its own path.** `Decoder.startDecode` sounds like
  /// "read the header only", but for JPEG it is not:
  /// `JpegData.readInfo` — in the package's own
  /// `lib/src/formats/jpeg/jpeg_data.dart` — runs all the
  /// way to the EOI marker and on the way calls `_readFrame` ->
  /// `prepareComponents`, which allocates the coefficient blocks of the
  /// WHOLE image. Measured (S392): a 40 MP JPEG cost 496 MB through
  /// `startDecode` alone — so refusing it for having too many pixels
  /// would have cost exactly the memory the refusal is meant to avoid.
  /// The 30 lines of SOF search below cost the file itself. For PNG,
  /// GIF, WebP, BMP and TIFF, `startDecode` really does read headers
  /// only.
  static List<int>? _dimensions(Uint8List b, img.Decoder decoder) {
    final jpeg = _jpegDimensions(b);
    if (jpeg != null) return jpeg;
    final info = decoder.startDecode(b);
    return info == null ? null : <int>[info.width, info.height];
  }

  /// SOF0..SOF15 from the JPEG marker stream. `null` if this is no JPEG.
  static List<int>? _jpegDimensions(Uint8List b) {
    if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
    var i = 2;
    while (i + 3 < b.length) {
      if (b[i] != 0xFF) {
        i++;
        continue;
      }
      final m = b[i + 1];
      // Fill byte, TEM, RSTn, SOI, EOI: no length field.
      if (m == 0xFF) {
        i++;
        continue;
      }
      if (m == 0x01 || (m >= 0xD0 && m <= 0xD9)) {
        i += 2;
        continue;
      }
      final segment = (b[i + 2] << 8) | b[i + 3];
      if (segment < 2) return null;
      // SOFn = 0xC0..0xCF except DHT (C4), JPG (C8) and DAC (CC).
      if (m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC) {
        if (i + 8 >= b.length) return null;
        return <int>[(b[i + 7] << 8) | b[i + 8], (b[i + 5] << 8) | b[i + 6]];
      }
      if (m == 0xDA) return null; // scan data starts, no SOF seen
      i += 2 + segment;
    }
    return null;
  }

  /// Scales down to [maxEdge] on the longest edge. An image that is
  /// already smaller is left alone.
  static img.Image _scaleTo(img.Image src, int maxEdge) {
    final longest = math.max(src.width, src.height);
    if (longest <= maxEdge) return src;
    final scale = maxEdge / longest;
    final w = math.max(1, (src.width * scale).round());
    final h = math.max(1, (src.height * scale).round());
    return img.copyResize(src,
        width: w, height: h, interpolation: img.Interpolation.average);
  }

  /// Does the image really carry transparency — or just a fourth channel
  /// full of 255? Asked on the SMALL image, so at most 512x512 pixels.
  static bool _usesAlpha(img.Image inside) {
    if (inside.numChannels < 4) return false;
    final max = inside.maxChannelValue;
    for (final p in inside) {
      if (p.a < max) return true;
    }
    return false;
  }

  /// Encodes under [ceiling]. The ceiling is a PROMISE, not a hope: when
  /// the quality knob is not enough, the edge is shortened.
  ///
  /// Without transparency this runs over the JPEG quality ladder. With
  /// transparency there is no knob, and **colour reduction is out**:
  /// `img.quantize` returns a palette image with THREE channels in all
  /// three methods (`neuralNet`, `octree`, `binary`) — the transparency
  /// is gone afterwards (measured S392, `package:image` 4.8.0). A sticker
  /// inside a black box is worse than a smaller image.
  static Uint8List _encodeUnder(img.Image inside,
      {required bool alpha, required int ceiling}) {
    var current = inside;
    var last = _encodeOnce(current, alpha, ceiling);
    for (var attempt = 0; attempt < 5 && last.length > ceiling; attempt++) {
      final edge = math.max(current.width, current.height);
      // The measured size gives the area factor needed. 0.92 as a safety
      // margin, because neither JPEG nor PNG scales exactly with area
      // (header, tables, one filter byte per row).
      final nextEdge = math.max(
          16, (edge * math.sqrt(ceiling / last.length) * 0.92).round());
      if (nextEdge >= edge) break;
      current = _scaleTo(current, nextEdge);
      last = _encodeOnce(current, alpha, ceiling);
    }
    return last;
  }

  static Uint8List _encodeOnce(img.Image inside, bool alpha, int ceiling) {
    if (alpha) return img.encodePng(inside, level: 9);
    Uint8List? last;
    for (final q in _jpegLadder) {
      last = img.encodeJpg(inside, quality: q);
      if (last.length <= ceiling) return last;
    }
    return last!;
  }
}

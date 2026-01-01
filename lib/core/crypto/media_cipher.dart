import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/sodium_ffi.dart';
import 'package:cleona/core/storage/atomic_replace.dart';

/// Framed AEAD format for media attachments at rest (S362, variant B).
///
/// ## Why not `FileEncryption`
///
/// [FileEncryption] holds the payload several times in memory at once.
/// Measured on 02.09.2026 via `VmHWM` (`/proc/self/status`), base load
/// 195 244 kB subtracted, exactly linear over 32/128/256 MB:
///
/// | File | Writing | Reading |
/// |---|---|---|
/// | 32 MB | 120 332 kB (3.67x) | 217 024 kB (6.62x) |
/// | 128 MB | 512 500 kB (3.91x) | 775 872 kB (5.92x) |
/// | 256 MB | 1 036 220 kB (3.95x) | 1 559 620 kB (5.95x) |
///
/// The slope between 128 and 256 MB is 3.996x on writing and
/// 5.98x on reading — i.e. **4.00x and 6.00x**. The upper limit for an
/// attachment is 500 MB (`cleona_service.dart:1655`) and the app carries
/// **no** `largeHeap` (`android/app/src/main/AndroidManifest.xml`,
/// measured: the string does not occur there). A 100 MB video thus cost
/// 400 MB on receipt and 600 MB on viewing.
///
/// ## The frame
///
/// Header, 72 bytes, little-endian:
///
/// ```text
/// 0   8   magic        "CLEONAM1"
/// 8   1   version      = 1
/// 9   3   free         = 0
/// 12  4   frame size (uint32)  = 65536
/// 16  8   plaintext length (uint64)
/// 24  16  nonce base   (random, new per file)
/// 40  32  header MAC = HMAC-SHA256(macKey, bytes 0..40)
/// ```
///
/// Then `n = ceil(len / 65536)` frames. Frame `i` carries
/// `min(65536, len - i*65536)` plaintext bytes, sealed with
/// `crypto_secretbox_easy` (XSalsa20-Poly1305) under
/// `nonce_i = nonce base (16 B) || uint64LE(i) (8 B)` — together exactly
/// the 24 bytes that `crypto_secretbox` requires. The ciphertext of a
/// frame is `plaintext + 16` bytes (Poly1305 tag).
///
/// **What the frame index in the nonce achieves.** `crypto_secretbox`
/// knows no additional data (no AAD), so the position of the frame must
/// be bound elsewhere. It sits in the nonce: a swapped or duplicated
/// frame does not decrypt. The **nonce base** is freshly drawn per file,
/// so that the same frame index never occurs twice under the same key
/// with different content (nonce reuse would be total loss with a stream
/// cipher).
///
/// **What the header MAC achieves.** It authenticates version, frame
/// size, plaintext length and nonce base. Without it someone could write
/// a smaller plaintext length and thus cut off the file at the end
/// without a single frame MAC objecting — the remaining frames are
/// intact, after all. With it the frame count is authenticated and every
/// truncation is noticed.
///
/// ## What it costs
///
/// * **Space:** `72 + 16 * ceil(len / 65536)`. For 100 MB that is
///   `72 + 16 * 1600 = 25 672` bytes on 104 857 600 — **0.0245 %**.
/// * **Memory:** one frame at a time. Plaintext (64 KiB) + ciphertext
///   (64 KiB + 16 B) + the copy that `secretBoxDecrypt` pulls from the
///   native buffer (64 KiB) — **about 192 KiB, independent of the file
///   size.** The guard in `test/smoke/smoke_media_at_rest.dart`
///   measures exactly that against a fixed limit.
class MediaCipher {
  MediaCipher._();

  /// Extension of the encrypted version. The path WITHOUT this extension
  /// is still the identifier that stands in `UiMessage.filePath` — just as
  /// [FileEncryption] appends `.enc` itself.
  static const String suffix = '.cmenc';

  static const List<int> _magic = [0x43, 0x4c, 0x45, 0x4f, 0x4e, 0x41, 0x4d, 0x31]; // "CLEONAM1"
  static const int version = 1;
  static const int headerLength = 72;
  static const int macLength = 16;

  /// 64 KiB. Larger hardly saves space (the overhead already falls below
  /// 0.03 % at 64 KiB) and costs linearly more memory per frame.
  static const int frameSize = 64 * 1024;

  static Uint8List _fileKey(Uint8List baseKey) => SodiumFFI().hkdfSha256(
        baseKey,
        info: Uint8List.fromList('cleona-media-enc-v1'.codeUnits),
        length: 32,
      );

  static Uint8List _macKey(Uint8List baseKey) => SodiumFFI().hkdfSha256(
        baseKey,
        info: Uint8List.fromList('cleona-media-hdr-v1'.codeUnits),
        length: 32,
      );

  static Uint8List _nonce(Uint8List base, int frameIndex) {
    final n = Uint8List(24);
    n.setRange(0, 16, base);
    final bd = ByteData.sublistView(n, 16, 24);
    bd.setUint64(0, frameIndex, Endian.little);
    return n;
  }

  /// How large will the file be on disk?
  static int cipherLengthFor(int plainLength) {
    final frames = plainLength == 0 ? 0 : (plainLength + frameSize - 1) ~/ frameSize;
    return headerLength + plainLength + macLength * frames;
  }

  // ── Writing ─────────────────────────────────────────────────────────

  /// Seals [plaintext] to `[destPath].cmenc`. Atomically via
  /// `.cmenc.tmp` + ONE `renameSync` ([atomicReplace]), so that an abort
  /// leaves either no file or a complete one — and so that `.cmenc`
  /// exists continuously during an overwrite.
  static void encryptBytes(String destPath, Uint8List plaintext, Uint8List baseKey) {
    _encrypt(destPath, baseKey, plaintext.length, (buf, offset, len) {
      buf.setRange(0, len, plaintext, offset);
    });
  }

  /// Seals the content of [srcPath] to `[destPath].cmenc`, **without**
  /// ever holding the whole file in memory. The cleaner and the send path
  /// need that: the upper limit is 500 MB.
  static void encryptFile(String destPath, String srcPath, Uint8List baseKey) {
    final src = File(srcPath).openSync(mode: FileMode.read);
    try {
      final len = src.lengthSync();
      _encrypt(destPath, baseKey, len, (buf, offset, l) {
        var got = 0;
        while (got < l) {
          final n = src.readIntoSync(buf, got, l);
          if (n <= 0) {
            throw StateError('encryptFile: $srcPath ended after ${offset + got} '
                'of $len bytes');
          }
          got += n;
        }
      });
    } finally {
      src.closeSync();
    }
  }

  static void _encrypt(
    String destPath,
    Uint8List baseKey,
    int plainLength,
    void Function(Uint8List buf, int offset, int len) fill,
  ) {
    final sodium = SodiumFFI();
    final fileKey = _fileKey(baseKey);
    final nonceBase = sodium.randomBytes(16);

    final header = Uint8List(headerLength);
    header.setRange(0, 8, _magic);
    header[8] = version;
    final hd = ByteData.sublistView(header);
    hd.setUint32(12, frameSize, Endian.little);
    hd.setUint64(16, plainLength, Endian.little);
    header.setRange(24, 40, nonceBase);
    header.setRange(40, 72,
        sodium.hmacSha256(_macKey(baseKey), Uint8List.sublistView(header, 0, 40)));

    final enc = File('$destPath$suffix');
    final tmp = File('$destPath$suffix.tmp');
    enc.parent.createSync(recursive: true);

    RandomAccessFile? out;
    try {
      out = tmp.openSync(mode: FileMode.write);
      out.writeFromSync(header);

      final buf = Uint8List(frameSize);
      var offset = 0;
      var frame = 0;
      while (offset < plainLength) {
        final len = plainLength - offset < frameSize ? plainLength - offset : frameSize;
        fill(buf, offset, len);
        final chunk = len == frameSize ? buf : Uint8List.sublistView(buf, 0, len);
        out.writeFromSync(
            sodium.secretBoxEncrypt(chunk, fileKey, _nonce(nonceBase, frame)));
        offset += len;
        frame++;
      }
      out.flushSync();
      out.closeSync();
      out = null;
      // ── A TWO-STEP STOOD HERE, AND IT COULD COST DATA ──────
      //
      // Until S371: `if (Platform.isWindows && enc.existsSync())
      // enc.deleteSync();` before the renaming, justified with "Windows
      // cannot rename over an existing file". **The claim is refuted by
      // measurement** — `MoveFileExW` with `MOVEFILE_REPLACE_EXISTING`
      // replaces (Windows machine, 05.09.2026, 8 of 8 runs complete and
      // valid).
      //
      // The two-step weighed more heavily here than the three-step in
      // `atomic_json_writer.dart`/`file_encryption.dart`: for `.cmenc`
      // there is NO sidecar rescue ([MediaSweep] cleans away a leftover
      // `.cmenc.tmp` instead of promoting it). When overwriting an already
      // encrypted attachment — the path of `MediaStore.writeBytes`, where
      // no plaintext lies next to it — an abort between deleting and
      // renaming destroyed the only ciphertext. Measurement table and
      // reasoning for the retry: [atomicReplace].
      atomicReplace(tmp, enc);
    } catch (e) {
      try {
        out?.closeSync();
      } catch (_) {}
      if (tmp.existsSync()) {
        try {
          tmp.deleteSync();
        } catch (_) {}
      }
      rethrow;
    }
  }

  // ── Reading ─────────────────────────────────────────────────────────

  /// Opens `[path].cmenc`. Throws if magic, version or header MAC do not
  /// match — **fail-loud**: an unreadable media file is a finding, not a
  /// silent empty content.
  static MediaReader open(String path, Uint8List baseKey) {
    final f = File('$path$suffix').openSync(mode: FileMode.read);
    try {
      final header = Uint8List(headerLength);
      if (f.readIntoSync(header) != headerLength) {
        throw StateError('$path$suffix: header incomplete');
      }
      for (var i = 0; i < 8; i++) {
        if (header[i] != _magic[i]) {
          throw StateError('$path$suffix: foreign magic');
        }
      }
      if (header[8] != version) {
        throw StateError('$path$suffix: version ${header[8]}, expected $version');
      }
      final want = SodiumFFI()
          .hmacSha256(_macKey(baseKey), Uint8List.sublistView(header, 0, 40));
      if (!_constantTimeEquals(want, Uint8List.sublistView(header, 40, 72))) {
        throw StateError('$path$suffix: header MAC does not match — header tampered '
            'or wrong key');
      }
      final hd = ByteData.sublistView(header);
      final fs = hd.getUint32(12, Endian.little);
      if (fs <= 0 || fs > 1 << 24) {
        throw StateError('$path$suffix: unglaubwuerdige Rahmengroesse $fs');
      }
      return MediaReader._(
        f,
        Uint8List.sublistView(header, 24, 40),
        _fileKey(baseKey),
        frameSize: fs,
        length: hd.getUint64(16, Endian.little),
        path: '$path$suffix',
      );
    } catch (_) {
      f.closeSync();
      rethrow;
    }
  }

  /// Whole file in one piece. **Only** for consumers that need the content
  /// completely anyway (clipboard, archive upload). Whoever wants to
  /// display or play takes [MediaVault] and pays 192 KiB.
  static Uint8List decryptAll(String path, Uint8List baseKey) {
    final r = open(path, baseKey);
    try {
      return r.readRange(0, r.length);
    } finally {
      r.close();
    }
  }

  static bool exists(String path) => File('$path$suffix').existsSync();

  /// Does the file under [fullPath] carry the header of this format?
  ///
  /// **What for, if the extension is `.cmenc` anyway.** Because the
  /// extension proves nothing. An attachment that a user received BEFORE
  /// S362 and that happens to be called `bericht.cmenc` lies in plaintext
  /// in the media directory — and a cleaner that decides by the NAME
  /// would consider it already converted and would leave it lying open
  /// permanently. The question is therefore asked of the content.
  static bool hasMagic(String fullPath) {
    final f = File(fullPath);
    if (!f.existsSync()) return false;
    RandomAccessFile? raf;
    try {
      raf = f.openSync(mode: FileMode.read);
      final head = Uint8List(8);
      if (raf.readIntoSync(head) != 8) return false;
      for (var i = 0; i < 8; i++) {
        if (head[i] != _magic[i]) return false;
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        raf?.closeSync();
      } catch (_) {}
    }
  }

  /// Deletes ciphertext AND the sidecar from an aborted write. Whoever
  /// removes only `.cmenc` leaves a `.cmenc.tmp` lying around that
  /// carries the same content.
  static void delete(String path) {
    for (final s in [suffix, '$suffix.tmp']) {
      final f = File('$path$s');
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
  }

  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// What the reader (`MediaVault`) needs from a source — nothing more.
///
/// There are two variants: [MediaReader] over a ciphertext, and
/// `PlainMediaSource` over a plaintext file not yet converted.
/// The second is the reason why this interface exists: a cleanup run
/// that fails on ONE file (key missing, contradictory ciphertext) must
/// not cause exactly this message to disappear from the conversation.
/// Both are read; **only encrypted is written** ([MediaStore.writeBytes]
/// throws without a key, there is no plaintext write path any more).
abstract class MediaSource {
  /// Length of the PLAINTEXT.
  int get length;

  /// Streams `[start, end)` without holding more than one frame.
  Stream<List<int>> streamRange(int start, int end);

  void close();
}

/// Source over a file still lying in plaintext (legacy holdings that the
/// cleaner could not yet, or no longer, get hold of).
class PlainMediaSource implements MediaSource {
  PlainMediaSource(this.path) : _file = File(path);

  final String path;
  final File _file;

  @override
  int get length => _file.lengthSync();

  @override
  Stream<List<int>> streamRange(int start, int end) =>
      _file.openRead(start, end);

  @override
  void close() {}
}

/// Random access to a framed media file. Holds exactly one frame at a
/// time — hence the fixed memory peak.
class MediaReader implements MediaSource {
  MediaReader._(
    this._raf,
    this._nonceBase,
    this._fileKey, {
    required this.frameSize,
    required this.length,
    required this.path,
  });

  final RandomAccessFile _raf;
  final int frameSize;

  /// Length of the PLAINTEXT — exactly the number `Content-Length` needs.
  @override
  final int length;
  final Uint8List _nonceBase;
  final Uint8List _fileKey;
  final String path;
  bool _closed = false;

  int get frameCount =>
      length == 0 ? 0 : (length + frameSize - 1) ~/ frameSize;

  /// Decrypts frame [i]. The return buffer belongs to the caller.
  Uint8List frame(int i) {
    if (_closed) throw StateError('MediaReader is closed: $path');
    if (i < 0 || i >= frameCount) {
      throw RangeError('Frame $i outside of 0..${frameCount - 1} ($path)');
    }
    final plainLen = i == frameCount - 1 ? length - i * frameSize : frameSize;
    final cipherLen = plainLen + MediaCipher.macLength;
    _raf.setPositionSync(
        MediaCipher.headerLength + i * (frameSize + MediaCipher.macLength));
    final buf = Uint8List(cipherLen);
    var got = 0;
    while (got < cipherLen) {
      final n = _raf.readIntoSync(buf, got, cipherLen);
      if (n <= 0) {
        throw StateError('$path: frame $i truncated ($got of $cipherLen)');
      }
      got += n;
    }
    return SodiumFFI()
        .secretBoxDecrypt(buf, _fileKey, MediaCipher._nonce(_nonceBase, i));
  }

  /// Plaintext from [start] (inclusive) to [end] (exclusive).
  /// Only the touched frames are decrypted — that is the basis for
  /// seeking in a video.
  Uint8List readRange(int start, int end) {
    if (start < 0 || end > length || start > end) {
      throw RangeError('Range $start..$end outside of 0..$length ($path)');
    }
    final out = Uint8List(end - start);
    var written = 0;
    var pos = start;
    while (pos < end) {
      final idx = pos ~/ frameSize;
      final f = frame(idx);
      final inFrame = pos - idx * frameSize;
      final take = (f.length - inFrame) < (end - pos) ? f.length - inFrame : end - pos;
      out.setRange(written, written + take, f, inFrame);
      written += take;
      pos += take;
    }
    return out;
  }

  /// Streams [start]..[end] frame by frame. The HTTP reader takes this
  /// path: it never holds more than one frame, no matter how large the
  /// range is.
  @override
  Stream<List<int>> streamRange(int start, int end) async* {
    var pos = start;
    while (pos < end) {
      final idx = pos ~/ frameSize;
      final f = frame(idx);
      final inFrame = pos - idx * frameSize;
      final take = (f.length - inFrame) < (end - pos) ? f.length - inFrame : end - pos;
      yield (inFrame == 0 && take == f.length)
          ? f
          : Uint8List.sublistView(f, inFrame, inFrame + take);
      pos += take;
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    try {
      _raf.closeSync();
    } catch (_) {}
  }
}

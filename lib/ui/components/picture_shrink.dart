// Shrinks a picked picture below a byte bound — the own profile picture
// (§15.8, 64 KB) and the image of a group or private channel (§16.2.2, the
// same bound, `kGroupPictureAtMost`). One place for both screens.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// [bytes] as they are when they fit into [atMost] bytes; otherwise scaled
/// to 200 px, then to 128 px on the longer side. The result may still be
/// larger than [atMost] — the caller checks and tells the user.
Future<Uint8List> pictureWithin(Uint8List bytes, int atMost) async {
  var out = bytes;
  if (out.length > atMost) out = await resizePicture(out, 200);
  if (out.length > atMost) out = await resizePicture(out, 128);
  return out;
}

/// [bytes] decoded and drawn again with [maxSize] px on the longer side.
Future<Uint8List> resizePicture(Uint8List bytes, int maxSize) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;

  final scale =
      maxSize / (image.width > image.height ? image.width : image.height);
  final newW = (image.width * scale).round();
  final newH = (image.height * scale).round();

  final recorder = ui.PictureRecorder();
  final canvas =
      ui.Canvas(recorder, Rect.fromLTWH(0, 0, newW.toDouble(), newH.toDouble()));
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    Rect.fromLTWH(0, 0, newW.toDouble(), newH.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );
  final picture = recorder.endRecording();
  final resized = await picture.toImage(newW, newH);
  final byteData = await resized.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  resized.dispose();
  return byteData!.buffer.asUint8List();
}

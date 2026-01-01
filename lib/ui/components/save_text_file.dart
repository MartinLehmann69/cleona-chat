import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

enum SaveTextOutcome { saved, cancelled, failed }

/// What [saveTextFile] did: the outcome, the chosen path when saved, and the
/// error when it failed.
typedef SaveTextResult = ({SaveTextOutcome outcome, String? path, Object? error});

/// True on the platforms where `file_picker` writes the file itself.
bool get pickerWritesFile => Platform.isAndroid || Platform.isIOS;

/// Lets the user pick a file and saves [text] there — the ONE way the app
/// calls `FilePicker.saveFile` (S407-BUGREPORT B-3).
///
/// On Android and iOS `file_picker` 8.3.7 writes the file itself and
/// REQUIRES the bytes — without them `saveFile` throws `ArgumentError`
/// (pub.dev `file_picker-8.3.7`, `lib/src/file_picker_io.dart`, `saveFile`,
/// lines 148-151). On desktop it ignores the bytes and only returns the
/// chosen path, so the file is written here — unless [writeOnDesktop] is
/// false because the caller writes the path itself.
///
/// Never throws: a picker or file error is returned as
/// [SaveTextOutcome.failed].
Future<SaveTextResult> saveTextFile({
  required String text,
  required String fileName,
  required String dialogTitle,
  FileType type = FileType.any,
  List<String>? allowedExtensions,
  bool writeOnDesktop = true,
  @visibleForTesting FilePicker? picker,
  @visibleForTesting bool? isMobile,
}) async {
  try {
    final path = await (picker ?? FilePicker.platform).saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: type,
      allowedExtensions: allowedExtensions,
      bytes: Uint8List.fromList(utf8.encode(text)),
    );
    if (path == null) {
      return (outcome: SaveTextOutcome.cancelled, path: null, error: null);
    }
    if (!(isMobile ?? pickerWritesFile) && writeOnDesktop) {
      await File(path).writeAsString(text);
    }
    return (outcome: SaveTextOutcome.saved, path: path, error: null);
  } catch (e) {
    debugPrint('Saving $fileName failed: $e');
    return (outcome: SaveTextOutcome.failed, path: null, error: e);
  }
}

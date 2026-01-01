/// WHERE THE NODE'S OWN STATE LIES — handed in, not chosen here.
///
/// Three records belong to the device and to no identity: the host's
/// memory (fixed port, device code, remembered neighbours, relays from
/// cards), what this node holds for others in its post box, and the key of
/// its own address record (V4.2 §11.1, §8.2, §11.9). V4.2 §4.5.3 form 2
/// puts them into the device database of the app (D-51, owner 02.10.2026;
/// S403 decision G-1 = A).
///
/// This package does not know that database and must not: it is the app's
/// (`lib/core/storage/device_store.dart`), and a delivery layer that opened
/// it would carry the app's storage inside. So the three stores of the host
/// write through this interface, and whoever starts the host says where the
/// bytes go — the app with its device database (`mycelium_seam.dart`,
/// `MyceliumDeviceRecords`), a probe or a smoke with [FileDeviceRecords].
///
/// The interface holds BYTES under a NAME. Format, version and what an
/// unreadable record means stay with each store (`host_memory.dart`,
/// `post_box_disk.dart`, `outside_state.dart`) — exactly as when they wrote
/// files.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/file_encryption.dart';

/// The three names, as the stores use them.
const String kRecordHost = 'host';
const String kRecordPostBox = 'post_box';
const String kRecordOutside = 'outside';

abstract interface class DeviceRecords {
  /// Is a record [name] there — also one that cannot be read?
  bool holds(String name);

  /// The bytes of [name]; `null` if there is none OR it cannot be read.
  /// [holds] tells the two apart; each store decides what that means.
  Uint8List? read(String name);

  /// Replaces [name] as a whole. Either the new bytes are there afterwards
  /// or the old ones — never a mixture.
  void write(String name, Uint8List bytes);

  /// Removes [name], with whatever a broken write left of it.
  void remove(String name);

  /// Where [name] lies — for reports.
  String where(String name);
}

/// The records as encrypted files in [directory] (`<name>.enc`), under
/// [key] — what the stores did before S403, for probes and smokes, and for
/// a node without the app.
class FileDeviceRecords implements DeviceRecords {
  final Directory directory;
  final FileEncryption _enc;

  FileDeviceRecords(this.directory, Uint8List key)
      : _enc = FileEncryption(baseDir: directory.path, key: key) {
    directory.createSync(recursive: true);
  }

  String _path(String name) => '${directory.path}/$name';

  /// The side files count: [FileEncryption.readBinaryFile] recovers from
  /// them what a crash in the middle of a write left.
  @override
  bool holds(String name) => const ['.enc', '.enc.tmp', '.enc.old']
      .any((ending) => File('${_path(name)}$ending').existsSync());

  @override
  Uint8List? read(String name) =>
      holds(name) ? _enc.readBinaryFile(_path(name)) : null;

  /// Encrypted and atomic: `.enc.tmp`, then renamed.
  @override
  void write(String name, Uint8List bytes) =>
      _enc.writeBinaryFile(_path(name), bytes);

  /// Through [FileEncryption.deleteFile], so that an `.enc.old` of an
  /// aborted write does not bring the record back on the next read.
  @override
  void remove(String name) => _enc.deleteFile(_path(name));

  @override
  String where(String name) => '${_path(name)}.enc';
}

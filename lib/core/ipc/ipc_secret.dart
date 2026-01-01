// Where the two programs find the secret of their connection (S403, step 2;
// v4_2 §22.1: "daemon and GUI both read it from the database").
//
// The secret is ONE row of the device database (`DeviceStore
// .connectionSecret`, drawn when the database is created). The database
// opens under `deriveSharedFileEncKey(master_seed)`; the master seed comes
// from the keyring of the OS, which both the daemon and the GUI open
// (`main.dart`: "THE UI DOES NEED THE KEYRING AFTER ALL").
//
// Both read it at every connection, not once per process: the daemon's
// watchdog creates the device database anew when it was deleted from
// outside (`service_daemon.dart`, `_checkProfileIntegrity`), and with it a
// new secret. A client that connects after that reads the new one, as does
// the daemon for that connection; a connection made before keeps the keys
// it derived.

import 'dart:io';
import 'dart:typed_data';

import 'package:cleona/core/crypto/hd_wallet.dart';
import 'package:cleona/core/identity/identity_manager.dart';
import 'package:cleona/core/ipc/ipc_channel.dart';
import 'package:cleona/core/storage/device_store.dart';

/// The profile directory of an IPC endpoint: the directory the socket (or,
/// on Windows, `cleona.port`) lies in.
String ipcBaseDirOf(String socketPath) => File(socketPath).parent.path;

/// The secret as a CLIENT reads it: from an existing device database of
/// [baseDir]. Throws [IpcChannelException] if there is no master seed or no
/// device database — a client does not create one.
Uint8List ipcConnectionSecretForClient(String baseDir) {
  final seed = IdentityManager(baseDir: baseDir).loadMasterSeed();
  if (seed == null) {
    throw IpcChannelException('no master seed for $baseDir in the keyring — '
        'the device database, and with it the secret of the connection, '
        'cannot be opened');
  }
  final store =
      DeviceStore.atIfPresent(baseDir, HdWallet.deriveSharedFileEncKey(seed));
  if (store == null) {
    throw IpcChannelException('no device database in $baseDir — there is no '
        'profile to connect to');
  }
  return store.connectionSecret();
}

/// The secret as the DAEMON reads it: from the device database of
/// [baseDir], created if it is missing (the watchdog's case — then the
/// secret is a new one).
Uint8List ipcConnectionSecretForDaemon(String baseDir, Uint8List masterSeed) =>
    DeviceStore.at(baseDir, HdWallet.deriveSharedFileEncKey(masterSeed))
        .connectionSecret();

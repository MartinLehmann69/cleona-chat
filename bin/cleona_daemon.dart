// Entry point of the daemon for `dart build cli` (S366).
//
// WHY THIS FILE EXISTS — and why it is not an end in itself.
//
// The daemon used to be built with `dart compile exe lib/service_daemon.dart`
// (`scripts/release-build.sh:863` and `:736` for Windows). Since
// the store (§21.4.1) depends on a code asset, this build path no longer
// holds:
//
//   `dart compile exe` RUNS NO BUILD HOOKS. The Dart
//   documentation says the command should fail in that case; for
//   us it instead silently produces a binary WITHOUT the
//   library. Measured on 04.09.: the daemon starts, and then the log
//   says
//
//       Failed to load contacts: Couldn't resolve native function
//       'sqlite3_libversion' … No available native assets.
//
//   for contacts, groups and channels — as a WARNING. The service keeps
//   running, with empty collections. No crash, no error code.
//
// `dart build cli` runs the hooks and places `lib/libsqlite3.so`
// next to the binary. But it builds exclusively what lies under `bin/`
// — and `service_daemon.dart` lies in `lib/`. This file is the
// missing entry point, nothing more: it passes `main` through.
//
// `lib/service_daemon.dart` stays unchanged, so that `dart run` and
// every existing call site keep working.

import 'package:cleona/service_daemon.dart' as daemon;

void main(List<String> args) => daemon.main(args);

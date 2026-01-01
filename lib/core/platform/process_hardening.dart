import 'dart:ffi';
import 'dart:io';

import 'package:cleona/core/config/network_channel.dart';
import 'package:cleona/core/log/redacted_console.dart';

// `prctl` is variadic in glibc (`int prctl(int option, ...)`, prctl(2)); the
// wrapper reads four further `unsigned long` arguments. Declared as varargs
// so that every one of them is passed defined, on every ABI.
typedef _PrctlNative = Int32 Function(
    Int32 option,
    VarArgs<(UnsignedLong, UnsignedLong, UnsignedLong, UnsignedLong)>);
typedef _PrctlDart = int Function(
    int option, int arg2, int arg3, int arg4, int arg5);

// prctl(2): PR_GET_DUMPABLE = 3, PR_SET_DUMPABLE = 4.
const int _prGetDumpable = 3;
const int _prSetDumpable = 4;

_PrctlDart _prctl() => DynamicLibrary.process()
    .lookupFunction<_PrctlNative, _PrctlDart>('prctl');

/// The "dumpable" attribute of this process as the kernel reports it
/// (`PR_GET_DUMPABLE`): 1 = dumpable, 0 = not. `null` where it cannot be
/// asked (not Linux, or the call failed).
int? processDumpable() {
  if (!Platform.isLinux) return null;
  try {
    final value = _prctl()(_prGetDumpable, 0, 0, 0, 0);
    return value < 0 ? null : value;
  } catch (_) {
    return null;
  }
}

/// Clears the "dumpable" attribute of this process
/// (`prctl(PR_SET_DUMPABLE, 0)`): another process of the same user can then
/// neither attach to it nor read its memory, and no core dump is written.
/// Returns whether the kernel accepted it. Linux only; elsewhere `false`.
bool setProcessNotDumpable() {
  if (!Platform.isLinux) return false;
  return _prctl()(_prSetDumpable, 0, 0, 0, 0) == 0;
}

/// Linux live-build hardening (architecture §23.10): daemon and GUI call
/// this at start. Only the live build does it; the beta build stays
/// debuggable. A failure is logged and ignored — the process must not
/// refuse to start. Root reads on.
///
/// Logging goes to stderr (through [RedactedConsole]) because this function
/// runs before `CLogger` has a profile directory on either entry point.
void hardenLinuxProcessMemory({String context = 'process'}) {
  if (!Platform.isLinux) return;
  if (activeNetworkChannel != NetworkChannel.live) return;

  try {
    if (setProcessNotDumpable()) {
      RedactedConsole.err('[hardening] Linux live build: $context is not dumpable '
          '(no core dump, no attach by the same user)');
    } else {
      RedactedConsole.err('[hardening] Linux live build: prctl(PR_SET_DUMPABLE, 0) '
          'was refused for $context — continuing');
    }
  } catch (e) {
    RedactedConsole.err('[hardening] Linux live build: could not clear dumpable '
        'for $context: $e — continuing');
  }
}

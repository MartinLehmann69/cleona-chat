/// Which address family a wire may send on (S427, owner 18.11.2026 „A“).
///
/// v4_2 §11.1 (a node speaks only the address kinds it holds a socket for), and §22.4.4/§27: on
/// Windows the data port sends through the native `WSASendTo` shim, because
/// Dart's own IOCP send path crashes the VM below any Dart-level try/catch
/// when an IPv6 destination has no valid route
/// (`lib/core/link_io/native_send_path.dart`). Until S427 the wire fell back
/// to Dart's socket when the shim's IPv6 side could not be opened
/// (S418-W1-NACHSTELLPLAN.md D2) — the one remaining way for that crash
/// (field report 18.11.2026, `S427-RCA-FREUND-WER.md`). A family that cannot
/// be served safely is not used: no IPv6 socket without its native side on
/// Windows, and no send over Dart's socket there.
library;

import 'package:cleona/core/link_io/native_send_path.dart';

/// Whether a side of [kind] must not send over Dart's own socket — the
/// IPv6 side on Windows (IPv4 over Dart only loses, it does not crash, §27).
bool dartSendForbidden(String kind) =>
    kind == 'IPv6' && NativeSendPath.usesNativeSendPath;

/// The line when the IPv6 socket is given up for want of its native side.
String noNativeIpv6Line(int port) => 'wire: IPv6 socket on port $port given up — '
    'the native send path for IPv6 did not open, and on Windows Dart\'s own '
    'socket must not send to IPv6 (§22.4.4, §27). This node speaks IPv4 '
    'alone (§11.1).';

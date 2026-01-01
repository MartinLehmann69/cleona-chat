// lib/ui/components/call_status.dart
//
// The status line of the 1:1 call screen before the call runs (§17.2).
import 'package:cleona/core/service/service_types.dart';

/// i18n key of the status line for [call] while it is not yet answered, or
/// `null` once it runs (the screen shows the duration then) or there is no
/// call.
///
/// §17.2: "From the moment the user starts the call the caller shows
/// "reaching …" — no ringtone. When the callee's `RING_ACK` arrives, it
/// really is ringing on their end". So the caller sees "ringing" only after
/// the RING_ACK; before it, `call_reaching`.
String? callStatusKey(CallInfo? call) {
  if (call == null || call.state != CallState.ringing) return null;
  if (call.direction == CallDirection.incoming) return 'call_incoming';
  return call.reaching ? 'call_reaching' : 'call_ringing';
}

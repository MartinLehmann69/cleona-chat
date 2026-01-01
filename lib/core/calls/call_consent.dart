// lib/core/calls/call_consent.dart
//
// "Allow calls = disclose IP" (v4_2 §17 principle, §23.6, RL-7; D-69).
//
// A call is the only place where two devices disclose their addresses to
// each other, and only with consent per contact — on unless switched off,
// revocable. This file holds the ONE question every call path asks before
// an address could leave the device: may this device hold a media pair
// with that peer?
//
// What it answers is the OWN side only. The other side holds its own switch
// and enforces it on its own device (it does not ring, or it does not call);
// nothing about the switch travels.
import 'package:cleona/core/service/service_types.dart';

/// Whether this device may call [peerHex] and ring for it.
///
/// True only for an accepted contact (not pending, not deleted, §15.7) whose
/// switch "allow calls" is on ([ContactInfo.callsAllowed]). A non-contact is
/// never allowed: two participants that are not contacts with that consent
/// never disclose their addresses to each other (§17 principle, §17.7).
///
/// The 1:1 call (`CallService`) and the media pairs of a group call (§17.7,
/// "media pair" in report S407-GRUPPENANRUF A.1) use this same predicate.
bool callsAllowedWith(Map<String, ContactInfo> contacts, String peerHex) {
  final c = contacts[peerHex];
  return c != null && c.status == 'accepted' && c.callsAllowed;
}

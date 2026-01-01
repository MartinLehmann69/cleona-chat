// The identity of the archive share (§21.6, security rules).
//
// §21.6: "never write to an unidentified share — on first use the share's
// identity is pinned (SFTP: the host key; FTPS/HTTPS: the server
// certificate; SMB: a marker file `Cleona/.cleona-share-id` with 32 random
// bytes), and a mismatch stops the run and asks the user instead of
// authenticating. Unknown is not mismatched: an unpinned share is pinned, a
// changed one is refused."
//
// Background (S392-19): until S394 the archive addressed its share by
// address and share name only. `192.168.1.50` names a different machine in
// every network of the world, and the files on the share are plaintext on
// purpose — whoever answered under the configured address received the
// originals.
//
// This file holds what all four transports share: the vocabulary of the
// outcome, the ONE decision "unknown is not mismatched", and the two pure
// helpers that turn what a server presents into a pin (TLS: SPKI SHA-256 in
// curl's `--pinnedpubkey` notation; SSH: the OpenSSH `SHA256:` fingerprint).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

/// Where the SMB marker lives, relative to the share root (§21.6).
const String kShareMarkerPath = 'Cleona/.cleona-share-id';

/// Length of the SMB marker in bytes (§21.6: "32 random bytes").
const int kShareMarkerBytes = 32;

/// Outcome of establishing the share's identity before a run.
enum ShareIdentityState {
  /// The share presented the identity pinned on first use.
  confirmed,

  /// Nothing was pinned for this share; what it presented is pinned now.
  newlyPinned,

  /// The share presents a DIFFERENT identity (or the pinned marker is
  /// gone). The run stops: nothing is written, nothing deleted, and the
  /// user is asked.
  mismatch,

  /// The identity could not be established at all — share unreachable,
  /// login refused, TLS handshake failed. Not a mismatch; the run skips.
  unavailable,
}

/// Is a run allowed to touch the share after this outcome?
bool shareIdentityAllowsAccess(ShareIdentityState? s) =>
    s == ShareIdentityState.confirmed || s == ShareIdentityState.newlyPinned;

/// What a transport learned when it asked the share who it is.
class ShareIdentityProbe {
  /// The identity the share presented, in the pin notation of its protocol;
  /// `null` if it presented none.
  final String? presented;

  /// The transport ITSELF saw a changed identity: ssh refused a changed host
  /// key, or the SMB marker is missing although a pin exists.
  final bool refused;

  /// For the log and the user — never a secret.
  final String detail;

  const ShareIdentityProbe.presented(String this.presented, {this.detail = ''})
      : refused = false;
  const ShareIdentityProbe.refused(this.detail)
      : presented = null,
        refused = true;
  const ShareIdentityProbe.unavailable(this.detail)
      : presented = null,
        refused = false;
}

/// THE decision, in one place: unknown is not mismatched.
ShareIdentityState decideShareIdentity({
  required String? pinned,
  required ShareIdentityProbe probe,
}) {
  if (probe.refused) return ShareIdentityState.mismatch;
  final presented = probe.presented;
  if (presented == null) return ShareIdentityState.unavailable;
  if (pinned == null) return ShareIdentityState.newlyPinned;
  return presented == pinned
      ? ShareIdentityState.confirmed
      : ShareIdentityState.mismatch;
}

/// A pin together with the share it was taken from.
///
/// The target is part of the pin on purpose: a user who types a NEW address
/// has named a new share — that is "unknown", not "changed". Only the same
/// target presenting a different identity is a mismatch.
class ShareIdentityPin {
  final String target;
  final String value;
  const ShareIdentityPin({required this.target, required this.value});

  Map<String, dynamic> toJson() => {'target': target, 'value': value};

  static ShareIdentityPin? fromJson(Object? j) {
    if (j is! Map) return null;
    final t = j['target'], v = j['value'];
    if (t is! String || v is! String || v.isEmpty) return null;
    return ShareIdentityPin(target: t, value: v);
  }
}

/// A pin shortened for display: enough to compare by eye, not the whole.
String shortShareIdentity(String pin) =>
    pin.length <= 24 ? pin : '${pin.substring(0, 20)}…';

// ── TLS: SPKI SHA-256 ────────────────────────────────────────────────────

/// Error while talking to a share whose TLS key is not the pinned one.
class ShareIdentityMismatchException implements Exception {
  final String message;
  ShareIdentityMismatchException(this.message);
  @override
  String toString() => 'ShareIdentityMismatchException: $message';
}

/// The pin of a TLS server: `sha256//<base64>` over the DER of its
/// SubjectPublicKeyInfo — byte for byte the notation curl's
/// `--pinnedpubkey` expects, so FTPS (curl) and HTTPS (dart:io) share one
/// value. `null` if the certificate cannot be parsed.
String? tlsPinOf(X509Certificate? cert) {
  if (cert == null) return null;
  final spki = spkiFromEncodedCertificate(cert.der);
  if (spki == null) return null;
  return 'sha256//${base64.encode(crypto.sha256.convert(spki).bytes)}';
}

/// Extracts the SubjectPublicKeyInfo TLV from an X.509 certificate (DER).
///
/// Certificate ::= SEQUENCE { tbsCertificate SEQUENCE { [0] version
/// OPTIONAL, serialNumber, signature, issuer, validity, subject,
/// subjectPublicKeyInfo, ... }, ... } — RFC 5280 §4.1.
Uint8List? spkiFromEncodedCertificate(Uint8List bytes) {
  try {
    final cert = _tlv(bytes, 0);
    if (bytes[0] != 0x30) return null;
    final tbs = _tlv(bytes, cert.contentStart);
    if (bytes[cert.contentStart] != 0x30) return null;
    var p = tbs.contentStart;
    if (bytes[p] == 0xa0) p = _tlv(bytes, p).end; // explicit [0] version
    // serialNumber, signature, issuer, validity, subject
    for (var i = 0; i < 5; i++) {
      p = _tlv(bytes, p).end;
    }
    if (bytes[p] != 0x30) return null;
    final spki = _tlv(bytes, p);
    return Uint8List.sublistView(bytes, p, spki.end);
  } catch (_) {
    return null;
  }
}

class _Tlv {
  final int contentStart, end;
  _Tlv(this.contentStart, this.end);
}

_Tlv _tlv(Uint8List b, int at) {
  var p = at + 1;
  var len = b[p++];
  if (len & 0x80 != 0) {
    final n = len & 0x7f;
    if (n == 0 || n > 4) throw const FormatException('DER length');
    len = 0;
    for (var i = 0; i < n; i++) {
      len = (len << 8) | b[p++];
    }
  }
  if (p + len > b.length) throw const FormatException('DER overrun');
  return _Tlv(p, p + len);
}

// ── SSH: the host key as pinned in the per-identity known_hosts ──────────

/// The name ssh writes into known_hosts for [host] and [port].
String knownHostsName(String host, int port) =>
    port == 22 ? host : '[$host]:$port';

/// The OpenSSH fingerprint (`SHA256:<base64 without padding>`) of the key
/// for [host]:[port] in a known_hosts text, or `null`.
///
/// Reads plain host names only; the transport forces `HashKnownHosts=no`
/// on its own file, so a hashed line there would be foreign.
String? sshFingerprintFromKnownHosts(String text, String host, int port) {
  final name = knownHostsName(host, port);
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('@')) continue;
    final f = line.split(RegExp(r'\s+'));
    if (f.length < 3 || !f[0].split(',').contains(name)) continue;
    try {
      final digest = crypto.sha256.convert(base64.decode(f[2])).bytes;
      return 'SHA256:${base64.encode(digest).replaceAll('=', '')}';
    } catch (_) {
      return null;
    }
  }
  return null;
}

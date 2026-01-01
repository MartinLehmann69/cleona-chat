/// Constant-time comparison utilities for cryptographic code (Sec-hardening).
///
/// Centralizes the constant-time comparison pattern that was previously
/// duplicated across multiple files. All security-sensitive byte comparisons
/// (HMAC tags, signatures, user IDs, key images) MUST use these functions
/// instead of Dart's == operator or listEquals(), which may short-circuit
/// on the first differing byte and leak timing information.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Constant-time byte array comparison.
///
/// Returns true iff [a] and [b] have equal length and identical contents.
/// Execution time depends only on the length of the inputs, not on where
/// (or whether) they differ. This prevents timing side-channels that could
/// allow an attacker to recover secret material byte-by-byte.
///
/// Implementation: XOR-accumulation with no early exit. Each byte pair
/// contributes to a diff accumulator via bitwise OR; the final result is
/// checked only once after the full scan. This is the standard
/// constant-time comparison pattern (cf. OpenSSL CRYPTO_memcmp,
/// libsodium sodium_memcmp).
bool constantTimeEquals(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Constant-time string comparison.
///
/// Prevents timing-based extraction of auth tokens or passwords by ensuring
/// the comparison time depends only on the maximum input length, never on
/// the position of the first differing character.
///
/// Both strings are UTF-8 encoded before comparison. If lengths differ,
/// the shorter input is implicitly zero-padded (the length difference is
/// accumulated into the diff to ensure unequal-length inputs always fail).
bool constantTimeStringEquals(String a, String b) {
  final ab = utf8.encode(a);
  final bb = utf8.encode(b);
  final len = ab.length > bb.length ? ab.length : bb.length;
  var diff = ab.length ^ bb.length;
  for (var i = 0; i < len; i++) {
    final av = i < ab.length ? ab[i] : 0;
    final bv = i < bb.length ? bb[i] : 0;
    diff |= av ^ bv;
  }
  return diff == 0;
}

/// Annotation for code paths that have been audited for side-channel safety.
///
/// Applied to functions or methods where timing-sensitive operations
/// (signature verification, HMAC comparison, key comparison) have been
/// reviewed and confirmed to use constant-time patterns.
///
/// Usage:
/// ```dart
/// @SecAudited('2026-07-10', 'Initial constant-time audit')
/// bool verifySignature(...) { ... }
/// ```
class SecAudited {
  /// ISO 8601 date of the last audit.
  final String date;

  /// Brief description of what was audited.
  final String note;

  const SecAudited(this.date, [this.note = '']);
}

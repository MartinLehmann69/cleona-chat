// The invitation class of a ContactSeed (§15.3.1, §15.5 field `cls`).
//
// WHAT THE CLASS IS AND WHAT IT IS NOT. It is not a property of the
// FORMAT but of the PATH by which an invitation goes out — §15.3.1:
// "The commitment an invitation can give depends on whether `K_inv(i)`
// remained confidential. That is not a property of the format, but of the
// path — so the issuer must **choose the class at creation time**, and the
// UI must name the consequence."
//
// That is why nobody can compute it. A QR code on a poster and a QR code
// that two people hold out to each other look the same byte for byte;
// what distinguishes them only the issuer knows. The field `cls` carries
// this information to the scanner, so that its UI can name the promise
// the invitation can give at all.
//
// TWO CLASSES, NOT THREE. §15.3.1 normatively lists exactly two
// (`handed over confidentially` / `published`). The user level in §15.10
// names a third word next to them ("passed on"); whether that is a class
// of its own or just a description of the path is **§24-O I-2 open**. As
// long as that is open, nothing is invented here: the enumeration has the
// two normative values. If a third were added, that would be a wire
// format change, and that must be decided, not derived.
//
// THE FIELD IS A DISPLAY, NOT AN ENFORCEMENT. §15.5: "makes the class
// visible to the scanner's UI; **enforced at the issuer** (§15.4)." A
// scanner must not derive from it any security it has not checked
// itself — the promise of the class "handed over confidentially" hangs on
// the secrecy of `K_inv(i)`, and that is a fact at the issuer, not one in
// the seed.
library;

enum InviteClass {
  /// **Handed over confidentially** — NFC touch, QR from person to person,
  /// 1:1 via a trustworthy third-party channel.
  ///
  /// `K_inv(i)` stays secret, so the symmetric part of the sealing (§15.4)
  /// holds against a relay archivist with a CRQC.
  confidential('c'),

  /// **Published** — business card, notice board, profile, channel post.
  ///
  /// `K_inv(i)` is public, the symmetric part does NOT hold.
  /// PQ confidentiality then exists only via the ML-KEM material in the
  /// seed — and the compact QR profile lacks that (§15.5). The last row of
  /// the channel matrix from §15.3.1 ("QR printed/published") is
  /// therefore explicitly an invitation WITHOUT a PQ promise.
  published('p');

  const InviteClass(this.wireChar);

  /// One character on the wire — in the URI parameter `cls` and as one
  /// byte in the binary QR profile.
  ///
  /// Deliberately NOT the enumeration index: a class inserted later would
  /// shift all following indices, and an old seed would silently get a
  /// different meaning. The same reasoning as with
  /// `RotationApprovalKind.wireName`.
  final String wireChar;

  /// Reads the class from a wire character.
  ///
  /// Unknown or missing gives `null` — NOT [published] as a default.
  /// A missing field means "the issuer said nothing", and that is
  /// something other than "he said published". The UI must be able to
  /// tell the two apart, otherwise it claims information that nobody
  /// gave.
  static InviteClass? fromWireChar(String? c) {
    if (c == null || c.isEmpty) return null;
    for (final v in InviteClass.values) {
      if (v.wireChar == c) return v;
    }
    return null;
  }

  /// One byte for the binary QR profile. `0` means "not set".
  int get wireByte => wireChar.codeUnitAt(0);

  static InviteClass? fromWireByte(int b) =>
      b == 0 ? null : fromWireChar(String.fromCharCode(b));

  /// i18n key of the class name (§24.4.4).
  String get labelKey => switch (this) {
        InviteClass.confidential => 'invite_class_confidential',
        InviteClass.published => 'invite_class_published',
      };

  /// i18n key of the PROMISE — what §15.3.1 "the UI must name the
  /// consequence" requires. The name alone says nothing.
  String get consequenceKey => switch (this) {
        InviteClass.confidential => 'invite_class_confidential_desc',
        InviteClass.published => 'invite_class_published_desc',
      };
}

/// Default validity of an invitation (§15.3.3: "Default **90 days**").
const Duration kInviteDefaultValidity = Duration(days: 90);

/// The selectable validities from §15.3.3 ("selectable 7 d / 30 d /
/// 90 d / unlimited"). `null` stands for unlimited.
const List<Duration?> kInviteValidityChoices = <Duration?>[
  Duration(days: 7),
  Duration(days: 30),
  kInviteDefaultValidity,
  null,
];

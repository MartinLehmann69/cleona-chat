// The budget class of a node and its network storage caps.
//
// WHY THIS FILE EXISTS.
//
// V4 §4.4 lists two budget classes — Harvester (Android, iOS) and Carrier
// (Linux, Windows, macOS) — and §14.3.1 quantifies their caps. In the
// production code both had **zero declaration sites** on 2026-08-21
// (measured over `Harvester`, `harvester`, `Carrier`, `carrier`,
// `BudgetClass`, `budgetClass`, `deviceClass`): the classes existed only
// as prose in comments and as `enum Role { harvester, carrier }` in the
// simulator (`scripts/sim/attic/sim_field.dart:237`). Thus the
// simulator computed against numbers the product did not know — exactly the gap
// that §21.9.1 point 9 wants to close ("a shared core with the product
// code").
//
// WHAT IS DELIBERATELY NOT DERIVED HERE.
//
// §14.2 (E-125) sets the transit pool at "5 % of the field quota of the
// respective class, **carved out, not added**". The caps
// are therefore here as the numbers §14.3.1 names (8 MB / 1.6 MB),
// and are NOT computed from the field quota. Reason: whether the
// field quota after the carve-out is 160 MB or 152 MB is not resolved in the
// leading document — §4.2 still derives the target shard size
// from the UNREDUCED budget ("160 MB / 8 = 20 MB", E-76),
// while §14.3.3 already lists the carve-out ("~160 MB (of which ~8 MB
// transit pool, carved out)"). A derivation computed here would silently decide this
// open question in one direction. It is recorded as a
// finding and belongs in the document, not in a constant.
//
// NO STATE, NO I/O.
library;

/// The budget class of a node (§4.4).
///
/// The class follows the platform, not the user's choice: it describes
/// what a device may do in the background, not what it would like to.
enum FieldBudgetClass {
  /// Android, iOS. Burst sync ~5 min in the background, field store with
  /// double rule 48 h / 32 MB — whichever binds first applies (E-53).
  harvester,

  /// Linux, Windows, macOS. Epoch tick ~10 s, full TTL, bulk cache.
  carrier,
}

/// Transit pool cap per class, in bytes (§14.2/§14.3.1, E-125).
///
/// Carrier ~8 MB, Harvester ~1.6 MB. Both are **carved out** of the existing
/// field quota; the pool neither lends to nor borrows from
/// another class (§14.3.3 point 2).
///
/// Decimal MB — not MiB. (The former reference quantities from
/// `field_shard`/`field_pricing` were dropped with the field model, V4.1
/// §9.1/§22.4.1.) The tilde in
/// §14.3.1 says that the number is not sharp; the difference between
/// 8e6 and 8 MiB is 4.9 % and thus well within that.
int transitPoolCapacityBytes(FieldBudgetClass cls) => switch (cls) {
      FieldBudgetClass.carrier => 8000000,
      FieldBudgetClass.harvester => 1600000,
    };

/// How many standard spores (§2.3a, 590 B) fit into the pool.
///
/// Only for orientation and for guards — the pool computes in bytes, not
/// in spores. The unit is ambiguous in the document: §14.2 caps in
/// bytes, while the metric in §18.6 counts "spores held in the transit pool
/// … against its cap". Bytes win because the cap is cut from a
/// storage quota and spores have no fixed size
/// (§2.3a: 36 B header plus padded payload).
int transitPoolStandardSporeCapacity(FieldBudgetClass cls) =>
    transitPoolCapacityBytes(cls) ~/ 590;

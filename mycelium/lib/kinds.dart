/// The registry of the kind bytes — the ONLY place where a
/// number is assigned.
///
/// Every packet begins with a byte that says what it is. Whoever needs a
/// new kind enters it HERE and nowhere else.
///
/// That this file exists has a measured cause: three modules
/// had independently of each other claimed 0x40 and 0x41 for themselves —
/// the outside route, the media lane and the groups. On the same socket
/// that means a packet lands at the wrong recipient. It was
/// found only during wiring; as long as every module was an island,
/// nobody could see it.
///
/// Ranges, so that a new module does not have to guess again:
///
/// | Range | Subject |
/// |---|---|
/// | 0x01-0x0F | first contact |
/// | 0x10-0x1F | messages |
/// | 0x20-0x2F | forwarding |
/// | 0x30-0x3F | post box |
/// | 0x40-0x4F | outside route |
/// | 0x50-0x5F | media |
/// | 0x60-0x6F | groups |
/// | 0x70-0x7F | update (software update) |
/// | 0x80-0xFF | free |
///
/// The neighbour search (`neighbours.dart`) does NOT belong here: it has its
/// own socket on port 41341 and thus its own number space.
library;

// ── First contact (first_contact.dart) ──────────────────────────────────
const int kBundlePlea = 0x01;
const int kBundle = 0x02;
const int kRequest = 0x03;
const int kAnswer = 0x04;
const int kReceiptFirstContact = 0x05;

// ── Messages (message.dart) ─────────────────────────────────────────
const int kMessage = 0x10;
const int kDeliveryReceipt = 0x11;

/// Publication of a new KEM generation (V4.2 §4.5.4, E1): an
/// ordinary envelope to ONE contact whose sender address carries the new
/// generation; plaintext = identifier 8 B ‖ mode 1 B. No broadcast.
const int kKeyRotation = 0x15;

/// Mode byte in the plaintext of a publication (§4.5.4 "must carry the mode"):
/// identifier and routes continue to apply for the new keys. Not a kind,
/// but a number on the wire — therefore likewise assigned only here.
const int kModeRoutesApplyFurther = 0x01;

/// Pair notices (proposal M, S391): ordinary sealed
/// messages to ONE contact, receipted like any, without a history entry.
/// Plaintext = identifier 8 B ‖ payload (`mailbox_pair.dart`).
///
/// The public day keys of the next 31 days (§8.2 of the
/// proposal): count 1 B, per day u32 ‖ 32 B.
const int kDayKey = 0x16;

// 0x17 (the notice "my new fixed neighbour") is gone: the fixed neighbours
// ride sealed in every message and acknowledgement (`message.dart`,
// proposal "contacts as fixed neighbours" rule 5). Not reused.

// ── Amendments to an existing message (amendment.dart) ─────────
//
// All three refer to a message that already exists, and
// carry its identifier. They are NOT delivery states: there are four,
// and that is how it stays. A read mark is a mark, not a state —
// delivery and reading are two different statements, and a
// read mark not sent is not a delivery error.
const int kReaction = 0x12;
const int kEdit = 0x13;
const int kReadMark = 0x14;

// ── Passing on (forward.dart) ───────────────────────────────────
const int kForward = 0x20;
const int kUnknownCode = 0x21;

// ── Post box (briefkasten_ablage.dart) ────────────────────────────────
const int kDeposit = 0x30;
const int kDeposited = 0x31;
const int kCollect = 0x32;
const int kHereItIs = 0x33;
const int kNothingThere = 0x34;
/// The holder's task to a collector: 16 B random (S385, F1 = A2).
const int kCollectTask = 0x35;
/// The collector's answer: identifier, random value, bundle, Ed25519 signature.
const int kCollectProof = 0x36;

// ── Outside route (outside_route.dart) ────────────────────────────────────
const int kWhatIsMyAddress = 0x40;
const int kYourAddressIs = 0x41;
const int kKnock = 0x42;

// ── Board (board.dart, §11.8a, W5) ──────────────────────────
/// Question: kind | random 16 B. 17 B.
const int kAnswerQuestion = 0x43;
/// Answer: kind | random 16 B | address entries. At most 690 B — on
/// the wire exactly one packet like the question, so no amplification.
const int kAnswerAnswer = 0x44;

// ── Keep-alive measurement (mapping_echo.dart, mapping_probe.dart, §8.1) ──
/// Echo request, from the data port: kind | the 16 random bytes of a `0x40`
/// the neighbour answered within the last 180 s. 17 B.
const int kEchoRequest = 0x45;
/// The echo, once, to where that `0x40` came from: kind | the same 16 B.
/// 17 B — not larger than the request, so no amplification.
const int kEcho = 0x46;
/// The neighbour saw a keep-alive under a new address: kind | the 8 B token
/// of that keep-alive. 9 B.
const int kMoved = 0x47;

// ── Open check (open_check.dart, open_check_answer.dart, §8.1) ────────────
/// Is my family open? From the data port to the fixed neighbour: kind |
/// untouched port u16 LE 2 B | random 16 B. 19 B.
const int kIsMyFamilyOpen = 0x48;
/// Try it from here, fixed neighbour to one other open neighbour: kind |
/// type + OBSERVED address 4/16 + port u16 LE (the codec of
/// `card_address.dart`) | the same 16 B. 24 or 36 B.
const int kTryFromHere = 0x49;
/// Open, once, to the observed address and the untouched port: kind | the
/// same 16 B. 17 B.
const int kOpen = 0x4A;

// ── Media (media.dart) ───────────────────────────────────────────────
const int kMediaAnnouncement = 0x50;
const int kMediaPiece = 0x51;

// ── Groups (group.dart) ──────────────────────────────────────────────
const int kGroupsMessage = 0x60;
const int kKeyDelivery = 0x61;

// ── Update (update_piece.dart) ───────────────────────────────
//
// The fetch path of the public update (V4.2 §26.6.1): a node asks
// a holder for pieces of ONE object — never for individual pieces. S387.

/// Plea: kind | object (SHA-256) 32 B | task 16 B (zeros the first
/// time). 49 B.
const int kPiecePlea = 0x70;

/// The holder's task to a source without a valid task: kind | object
/// 32 B | task 16 B. 49 B — not larger than the plea, so no
/// amplification toward a forged sender address.
const int kPieceTask = 0x71;

/// A piece: kind | fountain block (`fountain_block.dart`) 1041 B.
const int kUpdatePiece = 0x72;

/// The holder does not have this object: kind | object 32 B.
const int kNoPieces = 0x73;

/// All assigned numbers — the self-test records that none
/// occurs twice.
const List<int> allKinds = [
  kBundlePlea, kBundle, kRequest, kAnswer, kReceiptFirstContact,
  kMessage, kDeliveryReceipt, kReaction, kEdit, kReadMark,
  kKeyRotation, kDayKey,
  kForward, kUnknownCode, kDetour, kWhereAreYou,
  kDeposit, kDeposited, kCollect, kHereItIs, kNothingThere,
  kCollectTask, kCollectProof,
  kWhatIsMyAddress, kYourAddressIs, kKnock,
  kAnswerQuestion, kAnswerAnswer,
  kEchoRequest, kEcho, kMoved,
  kIsMyFamilyOpen, kTryFromHere, kOpen,
  kMediaAnnouncement, kMediaPiece,
  kGroupsMessage, kKeyDelivery,
  kPiecePlea, kPieceTask, kUpdatePiece, kNoPieces,
];

// ── Groups of kinds ────────────────────────────────────────────────
//
// Whoever dispatches a packet asks HERE where it belongs — and not with
// an enumeration of numbers of their own. Otherwise the ranges from
// the table above would stand in the tree a second time, and the table would again
// be only a claim.

bool isFirstContact(int s) => s >= 0x01 && s <= 0x0F;
bool isMessage(int s) =>
    s == kMessage ||
    s == kDeliveryReceipt ||
    s == kKeyRotation ||
    isPairNotice(s);
bool isPairNotice(int s) => s == kDayKey;
bool isAmendment(int s) =>
    s == kReaction || s == kEdit || s == kReadMark;
bool isForward(int s) => s >= 0x20 && s <= 0x2F;
bool isPostBox(int s) => s >= 0x30 && s <= 0x3F;
bool isOutsideRoute(int s) => s >= 0x40 && s <= 0x4F;
/// Subset of [isOutsideRoute] — whoever dispatches asks THIS first.
bool isBoard(int s) =>
    s == kAnswerQuestion || s == kAnswerAnswer;
/// Subset of [isOutsideRoute] — the keep-alive measurement (§8.1).
bool isMappingProbe(int s) => s >= kEchoRequest && s <= kMoved;
/// Subset of [isOutsideRoute] — the open check (§8.1).
bool isOpenCheck(int s) => s >= kIsMyFamilyOpen && s <= kOpen;
bool isMedia(int s) => s >= 0x50 && s <= 0x5F;
bool isGroup(int s) => s >= 0x60 && s <= 0x6F;
bool isUpdate(int s) => s >= 0x70 && s <= 0x7F;

// ── Content bytes of the cover packet (cover_stream_content.dart, S391) ─────────
//
// NOT kinds and not in [allKinds]: the content bytes from §5.5 stand
// INSIDE the sealed payload of a cover packet, behind its
// feature, and never reach the kind dispatch. A separate number space —
// but a number on the wire, therefore assigned here.
const int kCoverFill = 0x00;
const int kCoverPiece = 0x01;
const int kCoverEntries = 0x02;

/// The codes for which this node answers (§5.5, §8.1) — only in
/// packets to the fixed neighbour (`code_registration.dart`).
const int kCoverRegistration = 0x03;

/// Keep-alive (§8.1): device code 16 B | token 8 B — so that the fixed
/// neighbour can follow a move and report it (`mapping_echo.dart`).
const int kCoverKeepAlive = 0x04;

// ── Forwarding via codes (forward.dart, S391 proposal M, §8.1) ──
//
// Since S391 0x20 and 0x21 carry a code (16 B) instead of the identifier; the
// numbers stay, the format is new (4.2: no legacy format).

/// Pass the inner packet to this address: kind | hop count | next
/// address (type, address, port) | inner `0x20`.
const int kDetour = 0x22;

/// Where are you: kind | hop count (start 2) | code 16 B | ONE part of content.
const int kWhereAreYou = 0x23;

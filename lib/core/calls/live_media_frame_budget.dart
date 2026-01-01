/// The delivery ceiling for ONE live-media frame, in bytes.
///
/// This is the single source of the value. Nothing else in the tree may keep
/// a second copy — the three production consumers
/// (`video_engine.dart`, `group_video_receiver.dart`, `video_rate_control.dart`)
/// read it from here and pass it on unchanged as `VideoConfig.maxFrameBytes`.
///
/// ## Where the number comes from
///
/// | Factor | Value | Source |
/// |---|---|---|
/// | part size on the wire | 1200 B | §11.2, and §17.1 puts one video fragment in exactly this size class |
/// | part header | 12 B | §11.2 (identifier 8 + count u16 + index u16) |
/// | payload per part | **1188 B** | §11.2, `1200 - 12` |
/// | parts per frame | **204** | *not from the norm* — see below |
///
/// `204 * 1188 = 242'352`.
///
/// ## Why 1188 and not 1187
///
/// §17.1 says, in the rationale column of its size-class table, "video is
/// fragmented anyway at 1187 B of payload, and §11 already fixes this class".
/// That sentence **defers to §11** for the fragmentation; it does not fix a
/// payload of its own. §11.2 is the fixture, and its table reads header 12 B,
/// payload 1188 B. The 1187 is `1200 - 13`, the header of the retired CFRL
/// wire format, left standing in a rationale line when the part layer moved to
/// a 12 B header; the identical sentence appears in v4_1 (where §11 was still
/// called "appendix A") and the number does not occur in v4_0 or v3_0 at all.
/// Owner ruling of 22.09.2026: **1188 holds.**
///
/// ## Why 204 — and what is open about it
///
/// **v4_2 names no ceiling for a live-media frame.** §17.5 requires the
/// behaviour ("the encoder scales down through the presets, and only once no
/// preset fits anymore does the video stream end — with a reason"), but it
/// names no number to compare against, and neither does §17.6. `maxFrameBytes`,
/// "frame ceiling" and "delivery envelope" have zero occurrences in the
/// document.
///
/// 204 is therefore **inherited stock, not a derivation**. Until S392 the value
/// lived as `UdpFragmenter.liveMediaMaxFrameBytes` in
/// `lib/core/codec/udp_fragmenter.dart` and read `204 * 1187 = 242'148`, where
/// 204 was the largest number of data fragments that still fitted a **one-byte**
/// fragment index together with its 25 % XOR parity share. 4.2 has neither: the
/// part index of §11.2 is u16, and §17.6 is explicit that there is "no special
/// fragment". Keeping the count while correcting the payload moves the ceiling
/// by 204 B (+0.08 %) instead of by a factor; a different count needs an owner
/// ruling and a measurement, not a fresh calculation.
///
/// **The structural maximum of §11.2 is deliberately NOT used here.** 65535
/// parts of 1188 B would be 77'845'580 B, and that is not an admissible
/// production value for two measured reasons:
///
///   * the number is not only a comparison threshold. `VideoPipeline` allocates
///     `calloc<Uint8>(negotiated.maxFrameBytes)` as its read buffer — one per
///     open session, and in a group call one per peer.
///   * §17.6 gives live media **no re-request** ("a live frame is worthless
///     once its playback moment has passed"). A frame that a too-generous
///     ceiling lets through and the wire then drops is gone without
///     replacement; raising the ceiling shifts silently at which resolution
///     video is switched off.
library;

/// Largest live-media frame the delivery path is allowed to carry, in bytes.
///
/// 204 parts x 1188 B of payload per part (§11.2). See the library doc for the
/// derivation and for what is still open about the part count.
const int kLiveMediaMaxFrameBytes = 204 * 1188;

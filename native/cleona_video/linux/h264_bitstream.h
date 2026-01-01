/* h264_bitstream.h — a minimal H.264 Annex-B bit reader/writer.
 *
 * Work package: docs/SPEC_VOICE_VIDEO_REWORK.md V1.13 (Linux video backend).
 *
 * WHY THIS EXISTS. VAAPI's low-level encode/decode entry points (VAAPI does
 * not synthesise or parse SPS/PPS/slice headers for the caller — see
 * va_enc_h264.h and the picture/slice parameter structs) leave two jobs to the
 * application:
 *
 *   ENCODE SIDE: build the SPS/PPS Annex-B NAL units by hand and submit them
 *   as VAEncPackedHeaderParameterBuffer / VAEncPackedHeaderDataBuffer pairs,
 *   because the exact bytes on the wire (profile/level, cropping, VUI or its
 *   absence) are what the peer's decoder parses. Handing the driver only the
 *   VAEncSequenceParameterBufferH264 struct and hoping it reconstructs
 *   identical bytes is not how any VAAPI driver on this platform works.
 *
 *   DECODE SIDE: the wire only carries Annex-B NAL units (cleona_video.h,
 *   cleona_video_submit_encoded: "the bitstream as it came off the wire").
 *   VAPictureParameterBufferH264 / VASliceParameterBufferH264 need fields that
 *   only exist by parsing the SPS/PPS/slice header that arrived, not by
 *   guessing them from this session's own encoder state — a real peer's
 *   encoder is a different process (SPEC §4b, codec field: "the codec the
 *   backend will actually produce" is a per-side negotiation, and so is every
 *   other field the peer's encoder settled on).
 *
 * SCOPE, ON PURPOSE. Not a general H.264 parser. It supports exactly the
 * subset this backend's own encoder produces and needs to decode back:
 *
 *   - profile_idc in {66 (Baseline/Constrained Baseline), 77 (Main), 100 (High)}
 *   - frame_mbs_only_flag == 1 (progressive, no interlace — a call has none)
 *   - pic_order_cnt_type == 2 (POC derived from frame_num; no explicit POC
 *     syntax anywhere, which removes an entire class of slice-header fields —
 *     see cleona_video_linux_encoder.c for why this is the right default for a
 *     single-reference, no-B-frame, low-latency call stream, not a shortcut)
 *   - entropy_coding_mode_flag == 0 (CAVLC — mandatory for the Baseline and
 *     Constrained Baseline profiles this backend negotiates by default; see
 *     cleona_video_linux_encoder.c for the profile decision)
 *   - one slice per picture, no multiple slice groups, no arbitrary slice
 *     order, no redundant pictures, no scaling lists (flat, the profile
 *     default), no weighted prediction, sliding-window reference marking only
 *     (no explicit MMCO) — the encoder never produces any of these, so the
 *     decoder does not have to accept them from a well-behaved peer running
 *     the same backend.
 *
 * A bitstream outside this subset is rejected as CLEONA_VIDEO_ERR_DECODE
 * (cleona_video.h: "a backend that also inspects the bitstream and finds a
 * contradiction returns ERR_DECODE rather than feeding its decoder a lie") —
 * never misparsed and never silently ignored. This is intentionally narrower
 * than what an interoperable H.264 decoder must accept in general; broadening
 * it to also decode a differently-configured peer encoder (B-frames, CABAC,
 * multiple slices) is follow-up work, not a defect in this file — see the
 * report filed with this package's acceptance for the explicit scope note.
 */

#ifndef CLEONA_VIDEO_LINUX_H264_BITSTREAM_H
#define CLEONA_VIDEO_LINUX_H264_BITSTREAM_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ==========================================================================
 * Writer — used only to build SPS/PPS RBSPs for the packed headers.
 * ==========================================================================
 * Slice data itself is never hand-written: VAAPI's encoder produces the slice
 * bitstream in the coded buffer. Only the two parameter-set NAL units are
 * ours to construct, so the writer's surface is deliberately small.
 */
typedef struct {
    uint8_t* buf;      /* RBSP bytes, no emulation prevention yet */
    int32_t  cap;
    int32_t  byte_pos;
    int32_t  bit_pos;  /* 0..7, next bit to write within buf[byte_pos], MSB first */
} h264_bw_t;

void    h264_bw_init(h264_bw_t* w, uint8_t* buf, int32_t cap);
void    h264_bw_put_bit(h264_bw_t* w, int32_t bit);
void    h264_bw_put_bits(h264_bw_t* w, uint32_t value, int32_t n_bits);
void    h264_bw_put_ue(h264_bw_t* w, uint32_t value);   /* ue(v), Exp-Golomb unsigned */
void    h264_bw_put_se(h264_bw_t* w, int32_t value);    /* se(v), Exp-Golomb signed */
/* rbsp_trailing_bits(): one stop bit '1', then zero-pad to the next byte. */
void    h264_bw_trailing_bits(h264_bw_t* w);
/* Bytes written so far, rounded up — call only after h264_bw_trailing_bits. */
int32_t h264_bw_byte_len(const h264_bw_t* w);

/* Wraps an already-built RBSP (h264_bw_t's buf/byte_len) in an Annex-B NAL
 * unit: start code, NAL header byte, RBSP bytes with emulation prevention
 * (0x03) inserted per Annex B of the spec. Returns the number of bytes
 * written to out, or -1 if out_cap is too small. start_code_len is 4 for the
 * first NAL of an access unit (00 00 00 01) and may be 3 (00 00 01) for
 * later ones — this backend always uses 4, the form every decoder accepts. */
int32_t h264_annexb_wrap(uint8_t* out, int32_t out_cap,
                         int32_t nal_ref_idc, int32_t nal_unit_type,
                         const uint8_t* rbsp, int32_t rbsp_len);

/* ==========================================================================
 * Reader — used to parse an incoming SPS, PPS and slice header.
 * ==========================================================================
 * Constructed from an RBSP with emulation prevention ALREADY REMOVED
 * (h264_ebsp_to_rbsp does that step); the reader itself only ever sees clean
 * RBSP bits, matching every textbook description of the Exp-Golomb syntax
 * elements (there is no "skip 0x03" logic hiding inside ue()/se() here, which
 * is a common source of off-by-one bugs in ad hoc parsers).
 */
typedef struct {
    const uint8_t* buf;
    int32_t byte_len;
    int32_t byte_pos;
    int32_t bit_pos;   /* 0..7, next bit to read within buf[byte_pos], MSB first */
    int32_t overrun;   /* set once a read runs past byte_len; every further
                        * read returns 0 rather than reading out of bounds.
                        * The caller checks this once at the end instead of
                        * threading an error return through every call. */
} h264_br_t;

void     h264_br_init(h264_br_t* r, const uint8_t* buf, int32_t byte_len);
uint32_t h264_br_get_bit(h264_br_t* r);
uint32_t h264_br_get_bits(h264_br_t* r, int32_t n_bits);
uint32_t h264_br_get_ue(h264_br_t* r);
int32_t  h264_br_get_se(h264_br_t* r);
/* 1 if a read ran past the end of the buffer at any point so far. */
int32_t  h264_br_overrun(const h264_br_t* r);

/* Finds the last Annex-B start code (00 00 01, optionally preceded by another
 * 00) in [data, data+size) and returns the offset of the byte AFTER the start
 * code (i.e. the NAL header byte), or -1 if none is found. Mirrors
 * cleona_video_mock.c's last_start_code() convention: the decoder always acts
 * on the LAST NAL unit of a submitted buffer, because this backend's own
 * encoder (and the mock before it) only ever emits one NAL unit's worth of
 * slice data per submit — SPS/PPS arrive as separate submit_encoded calls
 * when this backend is the peer (see cleona_video_linux_encoder.c on how
 * packed headers reach read_encoded). A general multi-NAL Annex-B buffer is
 * out of scope, matching the file doc's scope statement. */
int32_t  h264_last_start_code(const uint8_t* data, int32_t size);

/* Removes emulation-prevention 0x03 bytes from an EBSP (the raw bytes after
 * the NAL header, as they arrive on the wire) into an RBSP the reader can
 * consume directly. out_cap must be >= in_len (the RBSP is never longer than
 * the EBSP). Returns the RBSP length, or -1 if out_cap is too small. */
int32_t  h264_ebsp_to_rbsp(const uint8_t* in, int32_t in_len,
                          uint8_t* out, int32_t out_cap);

/* ==========================================================================
 * Parsed parameter sets — only the fields this backend's decoder needs.
 * ========================================================================== */

typedef struct {
    int32_t seq_parameter_set_id;
    int32_t profile_idc;
    int32_t level_idc;
    int32_t log2_max_frame_num;              /* log2_max_frame_num_minus4 + 4 */
    int32_t pic_order_cnt_type;              /* must be 2 — see file doc */
    int32_t max_num_ref_frames;
    int32_t gaps_in_frame_num_value_allowed_flag;
    int32_t pic_width_in_mbs;                /* pic_width_in_mbs_minus1 + 1 */
    int32_t pic_height_in_map_units;         /* pic_height_in_map_units_minus1 + 1 */
    int32_t frame_mbs_only_flag;             /* must be 1 — see file doc */
    int32_t direct_8x8_inference_flag;
    int32_t frame_cropping_flag;
    int32_t crop_left, crop_right, crop_top, crop_bottom;
    int32_t valid;
} h264_sps_t;

typedef struct {
    int32_t pic_parameter_set_id;
    int32_t seq_parameter_set_id;
    int32_t entropy_coding_mode_flag;        /* must be 0 (CAVLC) — see file doc */
    int32_t pic_order_present_flag;          /* bottom_field_pic_order_in_frame_present_flag */
    int32_t num_ref_idx_l0_default_active;   /* _minus1 + 1 */
    int32_t num_ref_idx_l1_default_active;   /* _minus1 + 1 */
    int32_t weighted_pred_flag;
    int32_t weighted_bipred_idc;
    int32_t pic_init_qp;                     /* pic_init_qp_minus26 + 26 */
    int32_t deblocking_filter_control_present_flag;
    int32_t redundant_pic_cnt_present_flag;
    int32_t transform_8x8_mode_flag;
    int32_t valid;
} h264_pps_t;

/* Parses SPS/PPS RBSP (already emulation-prevention-stripped) into the
 * structs above. Returns 1 on success, 0 if the bitstream is outside this
 * file's scope (see the file doc) or truncated — never partially fills the
 * struct: on failure ->valid stays 0. */
int32_t h264_parse_sps(const uint8_t* rbsp, int32_t rbsp_len, h264_sps_t* out);
int32_t h264_parse_pps(const uint8_t* rbsp, int32_t rbsp_len, h264_pps_t* out);

typedef struct {
    int32_t first_mb_in_slice;
    int32_t slice_type;              /* 0/5 = P, 2/7 = I (the two this backend emits) */
    int32_t pic_parameter_set_id;
    int32_t frame_num;
    int32_t idr_pic_id;              /* only meaningful if this is an IDR slice */
    int32_t no_output_of_prior_pics_flag;
    int32_t long_term_reference_flag;
    int32_t adaptive_ref_pic_marking_mode_flag;  /* must be 0 for non-IDR — see file doc */
    int32_t num_ref_idx_active_override_flag;
    int32_t num_ref_idx_l0_active;
    int32_t slice_qp_delta;
    int32_t disable_deblocking_filter_idc;
    int32_t slice_alpha_c0_offset_div2;
    int32_t slice_beta_offset_div2;
    /* byte offset of the first bit of slice_data() within the RBSP — VAAPI
     * wants the raw EBSP slice data pointer/size, not the parsed fields, so
     * this is recorded to hand the original (pre-strip) bytes back rather
     * than re-encoding them. */
    int32_t header_bit_len;
    int32_t valid;
} h264_slice_header_t;

/* is_idr must be supplied by the caller (it comes from the NAL unit type, not
 * from inside the slice header itself). sps/pps must be the ones this slice's
 * pic_parameter_set_id / seq_parameter_set_id resolve to — the caller looks
 * them up (this backend keeps exactly one active SPS/PPS pair, see file doc). */
int32_t h264_parse_slice_header(const uint8_t* rbsp, int32_t rbsp_len,
                                int32_t is_idr, const h264_sps_t* sps,
                                const h264_pps_t* pps, h264_slice_header_t* out);

#ifdef __cplusplus
}
#endif

#endif /* CLEONA_VIDEO_LINUX_H264_BITSTREAM_H */

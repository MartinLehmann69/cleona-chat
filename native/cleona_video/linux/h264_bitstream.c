/* h264_bitstream.c — see h264_bitstream.h for scope and rationale. */

#include "h264_bitstream.h"

#include <string.h>

/* ==========================================================================
 * Writer
 * ========================================================================== */

void h264_bw_init(h264_bw_t* w, uint8_t* buf, int32_t cap) {
    w->buf = buf;
    w->cap = cap;
    w->byte_pos = 0;
    w->bit_pos = 0;
    if (cap > 0) buf[0] = 0;
}

void h264_bw_put_bit(h264_bw_t* w, int32_t bit) {
    if (w->byte_pos >= w->cap) return; /* fail-safe: caller sizes buffers generously */
    if (bit) w->buf[w->byte_pos] |= (uint8_t)(1u << (7 - w->bit_pos));
    w->bit_pos++;
    if (w->bit_pos == 8) {
        w->bit_pos = 0;
        w->byte_pos++;
        if (w->byte_pos < w->cap) w->buf[w->byte_pos] = 0;
    }
}

void h264_bw_put_bits(h264_bw_t* w, uint32_t value, int32_t n_bits) {
    for (int32_t i = n_bits - 1; i >= 0; i--) {
        h264_bw_put_bit(w, (int32_t)((value >> i) & 1u));
    }
}

void h264_bw_put_ue(h264_bw_t* w, uint32_t value) {
    /* Exp-Golomb: codeNum -> leadingZeroBits '0's, a '1', then the low
     * leadingZeroBits bits of (codeNum + 1). */
    uint32_t v = value + 1;
    int32_t bits = 0;
    uint32_t t = v;
    while (t > 1) { t >>= 1; bits++; }
    for (int32_t i = 0; i < bits; i++) h264_bw_put_bit(w, 0);
    h264_bw_put_bits(w, v, bits + 1);
}

void h264_bw_put_se(h264_bw_t* w, int32_t value) {
    /* se(v) per Table 9-3: codeNum = 2*|v| - (v>0 ? 1 : 0), i.e.
     * 0,1,-1,2,-2,3,-3,... map to codeNum 0,1,2,3,4,5,6,... */
    uint32_t codeNum;
    if (value <= 0) codeNum = (uint32_t)(-value) * 2u;
    else            codeNum = (uint32_t)value * 2u - 1u;
    h264_bw_put_ue(w, codeNum);
}

void h264_bw_trailing_bits(h264_bw_t* w) {
    h264_bw_put_bit(w, 1);
    while (w->bit_pos != 0) h264_bw_put_bit(w, 0);
}

int32_t h264_bw_byte_len(const h264_bw_t* w) {
    return w->byte_pos + (w->bit_pos > 0 ? 1 : 0);
}

int32_t h264_annexb_wrap(uint8_t* out, int32_t out_cap,
                         int32_t nal_ref_idc, int32_t nal_unit_type,
                         const uint8_t* rbsp, int32_t rbsp_len) {
    /* start code (4) + NAL header (1) + emulation-prevented RBSP, worst case
     * one 0x03 inserted for every 2 RBSP bytes. */
    int32_t pos = 0;
    if (out_cap < 5) return -1;
    out[pos++] = 0x00;
    out[pos++] = 0x00;
    out[pos++] = 0x00;
    out[pos++] = 0x01;
    out[pos++] = (uint8_t)(((nal_ref_idc & 0x3) << 5) | (nal_unit_type & 0x1F));

    int32_t zero_run = 0;
    for (int32_t i = 0; i < rbsp_len; i++) {
        uint8_t b = rbsp[i];
        if (zero_run >= 2 && b <= 0x03) {
            if (pos >= out_cap) return -1;
            out[pos++] = 0x03;
            zero_run = 0;
        }
        if (pos >= out_cap) return -1;
        out[pos++] = b;
        zero_run = (b == 0x00) ? zero_run + 1 : 0;
    }
    return pos;
}

/* ==========================================================================
 * Reader
 * ========================================================================== */

void h264_br_init(h264_br_t* r, const uint8_t* buf, int32_t byte_len) {
    r->buf = buf;
    r->byte_len = byte_len;
    r->byte_pos = 0;
    r->bit_pos = 0;
    r->overrun = 0;
}

uint32_t h264_br_get_bit(h264_br_t* r) {
    if (r->byte_pos >= r->byte_len) { r->overrun = 1; return 0; }
    uint32_t bit = (r->buf[r->byte_pos] >> (7 - r->bit_pos)) & 1u;
    r->bit_pos++;
    if (r->bit_pos == 8) { r->bit_pos = 0; r->byte_pos++; }
    return bit;
}

uint32_t h264_br_get_bits(h264_br_t* r, int32_t n_bits) {
    uint32_t v = 0;
    for (int32_t i = 0; i < n_bits; i++) v = (v << 1) | h264_br_get_bit(r);
    return v;
}

uint32_t h264_br_get_ue(h264_br_t* r) {
    int32_t leading_zeros = 0;
    while (h264_br_get_bit(r) == 0) {
        leading_zeros++;
        if (leading_zeros > 32 || r->overrun) return 0; /* malformed: bail, caller sees overrun/valid=0 */
    }
    if (leading_zeros == 0) return 0;
    uint32_t rest = h264_br_get_bits(r, leading_zeros);
    return (1u << leading_zeros) - 1u + rest;
}

int32_t h264_br_get_se(h264_br_t* r) {
    uint32_t codeNum = h264_br_get_ue(r);
    int32_t k = (int32_t)((codeNum + 1) / 2);
    return (codeNum & 1u) ? k : -k;
}

int32_t h264_br_overrun(const h264_br_t* r) {
    return r->overrun;
}

int32_t h264_last_start_code(const uint8_t* data, int32_t size) {
    int32_t found = -1;
    for (int32_t i = 0; i + 3 <= size; i++) {
        if (data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 1) {
            found = i + 3;
        } else if (i + 4 <= size && data[i] == 0 && data[i + 1] == 0 &&
                  data[i + 2] == 0 && data[i + 3] == 1) {
            found = i + 4;
        }
    }
    return found;
}

int32_t h264_ebsp_to_rbsp(const uint8_t* in, int32_t in_len,
                         uint8_t* out, int32_t out_cap) {
    if (out_cap < in_len) return -1;
    int32_t o = 0;
    int32_t zero_run = 0;
    for (int32_t i = 0; i < in_len; i++) {
        uint8_t b = in[i];
        if (zero_run >= 2 && b == 0x03) {
            /* Emulation prevention byte: drop it, do not count it towards a
             * new zero run (per spec, the byte after 0x03 is the "real" next
             * byte and the run resets). */
            zero_run = 0;
            continue;
        }
        out[o++] = b;
        zero_run = (b == 0x00) ? zero_run + 1 : 0;
    }
    return o;
}

/* ==========================================================================
 * SPS / PPS parsing
 * ========================================================================== */

int32_t h264_parse_sps(const uint8_t* rbsp, int32_t rbsp_len, h264_sps_t* out) {
    memset(out, 0, sizeof(*out));
    h264_br_t r;
    h264_br_init(&r, rbsp, rbsp_len);

    out->profile_idc = (int32_t)h264_br_get_bits(&r, 8);
    h264_br_get_bits(&r, 8);   /* constraint_set flags + reserved */
    out->level_idc = (int32_t)h264_br_get_bits(&r, 8);
    out->seq_parameter_set_id = (int32_t)h264_br_get_ue(&r);

    /* High-profile-only extension fields (chroma_format_idc etc.) — this
     * backend never negotiates a profile that carries them (see file doc),
     * but a defensive parser still has to skip them correctly rather than
     * mis-align every field that follows if it ever sees profile_idc==100. */
    if (out->profile_idc == 100 || out->profile_idc == 110 ||
        out->profile_idc == 122 || out->profile_idc == 244 ||
        out->profile_idc == 44  || out->profile_idc == 83  ||
        out->profile_idc == 86  || out->profile_idc == 118 ||
        out->profile_idc == 128) {
        uint32_t chroma_format_idc = h264_br_get_ue(&r);
        if (chroma_format_idc == 3) h264_br_get_bit(&r); /* separate_colour_plane_flag */
        h264_br_get_ue(&r); /* bit_depth_luma_minus8 */
        h264_br_get_ue(&r); /* bit_depth_chroma_minus8 */
        h264_br_get_bit(&r); /* qpprime_y_zero_transform_bypass_flag */
        uint32_t seq_scaling_matrix_present = h264_br_get_bit(&r);
        if (seq_scaling_matrix_present) {
            /* Out of scope (file doc: flat scaling lists only) — a stream
             * that sets this flag is not one this backend produced. */
            return 0;
        }
    }

    out->log2_max_frame_num = (int32_t)h264_br_get_ue(&r) + 4;
    out->pic_order_cnt_type = (int32_t)h264_br_get_ue(&r);
    if (out->pic_order_cnt_type == 0) {
        h264_br_get_ue(&r); /* log2_max_pic_order_cnt_lsb_minus4 */
    } else if (out->pic_order_cnt_type == 1) {
        /* Out of scope (file doc requires type 2). Still parse enough to stay
         * aligned in case a caller wants the profile/level even so, but the
         * caller must check pic_order_cnt_type == 2 before trusting anything
         * else — done at the call site in cleona_video_linux.c. */
        h264_br_get_bit(&r);
        h264_br_get_se(&r);
        h264_br_get_se(&r);
        uint32_t n = h264_br_get_ue(&r);
        for (uint32_t i = 0; i < n; i++) h264_br_get_se(&r);
    }
    out->max_num_ref_frames = (int32_t)h264_br_get_ue(&r);
    out->gaps_in_frame_num_value_allowed_flag = (int32_t)h264_br_get_bit(&r);
    out->pic_width_in_mbs = (int32_t)h264_br_get_ue(&r) + 1;
    out->pic_height_in_map_units = (int32_t)h264_br_get_ue(&r) + 1;
    out->frame_mbs_only_flag = (int32_t)h264_br_get_bit(&r);
    if (!out->frame_mbs_only_flag) {
        h264_br_get_bit(&r); /* mb_adaptive_frame_field_flag */
    }
    out->direct_8x8_inference_flag = (int32_t)h264_br_get_bit(&r);
    out->frame_cropping_flag = (int32_t)h264_br_get_bit(&r);
    if (out->frame_cropping_flag) {
        out->crop_left   = (int32_t)h264_br_get_ue(&r);
        out->crop_right  = (int32_t)h264_br_get_ue(&r);
        out->crop_top    = (int32_t)h264_br_get_ue(&r);
        out->crop_bottom = (int32_t)h264_br_get_ue(&r);
    }
    /* vui_parameters_present_flag and beyond: not needed by this decoder
     * (negotiated geometry/fps come from cleona_video_config_t, not from the
     * peer's VUI) and deliberately not parsed. */

    if (h264_br_overrun(&r)) return 0;
    out->valid = 1;
    return 1;
}

int32_t h264_parse_pps(const uint8_t* rbsp, int32_t rbsp_len, h264_pps_t* out) {
    memset(out, 0, sizeof(*out));
    h264_br_t r;
    h264_br_init(&r, rbsp, rbsp_len);

    out->pic_parameter_set_id = (int32_t)h264_br_get_ue(&r);
    out->seq_parameter_set_id = (int32_t)h264_br_get_ue(&r);
    out->entropy_coding_mode_flag = (int32_t)h264_br_get_bit(&r);
    out->pic_order_present_flag = (int32_t)h264_br_get_bit(&r);

    uint32_t num_slice_groups_minus1 = h264_br_get_ue(&r);
    if (num_slice_groups_minus1 > 0) {
        /* Multiple slice groups: out of scope (file doc). */
        return 0;
    }
    out->num_ref_idx_l0_default_active = (int32_t)h264_br_get_ue(&r) + 1;
    out->num_ref_idx_l1_default_active = (int32_t)h264_br_get_ue(&r) + 1;
    out->weighted_pred_flag = (int32_t)h264_br_get_bit(&r);
    out->weighted_bipred_idc = (int32_t)h264_br_get_bits(&r, 2);
    out->pic_init_qp = (int32_t)h264_br_get_se(&r) + 26;
    h264_br_get_se(&r); /* pic_init_qs_minus26 */
    h264_br_get_se(&r); /* chroma_qp_index_offset */
    out->deblocking_filter_control_present_flag = (int32_t)h264_br_get_bit(&r);
    out->redundant_pic_cnt_present_flag = (int32_t)h264_br_get_bit(&r);
    /* transform_8x8_mode_flag and the pps_extension only exist if more_rbsp_data();
     * this backend never sets them (Baseline/Constrained Baseline profile has
     * no 8x8 transform), so a truncated PPS here is the expected, in-scope
     * case, not an error. */
    out->transform_8x8_mode_flag = 0;

    if (h264_br_overrun(&r)) return 0;
    out->valid = 1;
    return 1;
}

int32_t h264_parse_slice_header(const uint8_t* rbsp, int32_t rbsp_len,
                                int32_t is_idr, const h264_sps_t* sps,
                                const h264_pps_t* pps, h264_slice_header_t* out) {
    memset(out, 0, sizeof(*out));
    if (!sps->valid || !pps->valid) return 0;
    if (sps->pic_order_cnt_type != 2) return 0;          /* file doc: mandatory */
    if (pps->entropy_coding_mode_flag != 0) return 0;     /* file doc: CAVLC only */
    if (!sps->frame_mbs_only_flag) return 0;               /* file doc: progressive only */

    h264_br_t r;
    h264_br_init(&r, rbsp, rbsp_len);

    out->first_mb_in_slice = (int32_t)h264_br_get_ue(&r);
    out->slice_type = (int32_t)h264_br_get_ue(&r);
    out->pic_parameter_set_id = (int32_t)h264_br_get_ue(&r);
    out->frame_num = (int32_t)h264_br_get_bits(&r, sps->log2_max_frame_num);

    /* field_pic_flag / bottom_field_flag do not exist: frame_mbs_only_flag == 1
     * (checked above) removes them from the syntax entirely. */

    if (is_idr) {
        out->idr_pic_id = (int32_t)h264_br_get_ue(&r);
    }
    /* pic_order_cnt_type == 2 (checked above): no pic_order_cnt_lsb, no
     * delta_pic_order_cnt_bottom, no delta_pic_order_cnt[] — this is the
     * simplification the file doc names. */

    /* redundant_pic_cnt: only if pps->redundant_pic_cnt_present_flag, which
     * this backend's own PPS never sets. */
    if (pps->redundant_pic_cnt_present_flag) {
        uint32_t redundant = h264_br_get_ue(&r);
        if (redundant != 0) return 0; /* out of scope */
    }

    /* slice_type % 5: 0/5 = P, 2/7 = I, 1/6 = B (never produced/accepted here) */
    int32_t st = out->slice_type % 5;
    if (st != 0 && st != 2) return 0; /* only P and I, matching the encoder */

    if (st == 0) { /* P slice */
        out->num_ref_idx_active_override_flag = (int32_t)h264_br_get_bit(&r);
        out->num_ref_idx_l0_active = out->num_ref_idx_active_override_flag
            ? (int32_t)h264_br_get_ue(&r) + 1 : pps->num_ref_idx_l0_default_active;

        /* ref_pic_list_modification (P/SP only in this profile subset). This
         * backend's encoder never reorders (single reference, frame_num order
         * already matches decode order), so ref_pic_list_modification_flag_l0
         * must be 0 for a stream this decoder accepts. */
        uint32_t ref_pic_list_modification_flag_l0 = h264_br_get_bit(&r);
        if (ref_pic_list_modification_flag_l0) return 0; /* out of scope */
    }

    /* weighted_pred / weighted_bipred_idc: this backend's PPS always sets
     * weighted_pred_flag = 0, so no pred_weight_table() here for a
     * conformant stream. */

    if (pps->weighted_pred_flag) return 0; /* out of scope, see above */

    /* dec_ref_pic_marking */
    if (is_idr) {
        out->no_output_of_prior_pics_flag = (int32_t)h264_br_get_bit(&r);
        out->long_term_reference_flag = (int32_t)h264_br_get_bit(&r);
    } else {
        /* This backend's encoder always uses sliding-window marking
         * (adaptive_ref_pic_marking_mode_flag == 0) — a single-reference
         * stream never needs MMCO. */
        out->adaptive_ref_pic_marking_mode_flag = (int32_t)h264_br_get_bit(&r);
        if (out->adaptive_ref_pic_marking_mode_flag) return 0; /* out of scope */
    }

    /* cabac_init_idc: only if entropy_coding_mode_flag, already excluded above. */

    out->slice_qp_delta = h264_br_get_se(&r);

    if (pps->deblocking_filter_control_present_flag) {
        out->disable_deblocking_filter_idc = (int32_t)h264_br_get_ue(&r);
        if (out->disable_deblocking_filter_idc != 1) {
            out->slice_alpha_c0_offset_div2 = h264_br_get_se(&r);
            out->slice_beta_offset_div2 = h264_br_get_se(&r);
        }
    }

    /* slice_group_change_cycle: only with slice group map types 3-5, which
     * pps->num_slice_groups_minus1 > 0 (excluded in h264_parse_pps) already
     * rules out. */

    if (h264_br_overrun(&r)) return 0;

    /* header_bit_len records where slice_data() begins, in case a future
     * caller wants it; not consumed by this backend today (VAAPI decode gets
     * the whole EBSP as VASliceDataBufferType and locates slice_data() itself
     * via VASliceParameterBufferH264::slice_data_bit_offset, computed at the
     * call site from this same value). */
    out->header_bit_len = r.byte_pos * 8 + r.bit_pos;
    out->valid = 1;
    return 1;
}

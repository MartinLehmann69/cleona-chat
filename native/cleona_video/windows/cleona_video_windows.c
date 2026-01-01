/* cleona_video_windows.c — Media Foundation backend for cleona_video.h.
 *
 * Work package: docs/SPEC_VOICE_VIDEO_REWORK.md V1.16 (Windows-Video-Backend).
 * Architecture:  Cleona_Chat_Architecture_v3_0.md §10.6 (normative), "Platform
 *                matrix" row Windows: capture via IMFSourceReader, encode/
 *                decode via a Media Foundation Transform (hardware MFT
 *                preferred, software MFT as the documented fallback).
 *
 * ---------------------------------------------------------------------------
 * DESIGN
 * ---------------------------------------------------------------------------
 * I10 (no pixels in Dart): the camera writes into buffers Media Foundation
 * owns, the H.264 encoder MFT reads those buffers directly (NV12, the format
 * every MF video pipeline agrees on without a manual conversion step), and
 * only the resulting Annex-B bitstream crosses into this ABI's
 * read_encoded()/submit_encoded(). On the receive side the decoder MFT writes
 * NV12 into a system-memory buffer, which this backend uploads into a D3D11
 * texture (BGRA8) — the one place this backend performs pixel conversion, and
 * it happens entirely below the ABI, in native code, never in Dart (matching
 * the "NV12/I420 converter remains only as a fallback... native, never in
 * Dart" language in Architecture §10.6). Dart is handed an opaque texture id,
 * never a pixel.
 *
 * WHEN THIS BACKEND TOUCHES THE CAMERA. cleona_video.h says open() "does NOT
 * touch the camera or the encoder yet — that is start()". Read literally that
 * would make it impossible for open() to answer the one question it has to
 * answer honestly: does a capture/encode path exist at all (ERR_UNSUPPORTED),
 * and what resolution/frame rate does the hardware actually offer (the
 * negotiated answer, never invented)? Neither is knowable without querying
 * the real device — there is no software model of "what cameras exist on this
 * machine" the way the mock invents one. This backend therefore reads
 * "does not touch" as "does not start the data flow": open() enumerates
 * capture devices, activates one, creates the IMFSourceReader, picks a native
 * format, and creates+configures the encoder and decoder MFTs and the D3D11
 * device — all of which determine the TRUTH the caller is owed at open() time
 * — but never calls ReadSample, ProcessInput or ProcessOutput. Those begin
 * only in start(), matching its own doc ("Start capture, encoder and
 * decoder."). The same split the mock makes (open() decides the final
 * configuration; start() is what makes read_encoded() start returning
 * frames) is preserved; only the *means* of deciding differ, because this
 * backend has real hardware to ask instead of a formula.
 *
 * ERROR CODE SELECTION (SPEC §13 Erratum E6b's documented, UNENFORCED blind
 * spot — read before touching any `return` in this file). E6b's own text
 * says ERR_RATE_UNACHIEVABLE and ERR_BACKEND "are not sharp on real hardware
 * ... and the conformance test cannot catch it" and asks every Windows/
 * Android/Apple/Linux backend to reason the split out explicitly rather than
 * trust a green test. This backend's rule, applied at every fallible call:
 *
 *   - Argument validity (wv_negotiate, called before any device is touched)
 *     -> ERR_INVALID. Decided first, always, exactly as cleona_video.h
 *     requires (max_frame_bytes <= 0 is ERR_INVALID and never
 *     ERR_RATE_UNACHIEVABLE, matching V1/V1b/V15).
 *   - wv_negotiate's own byte-budget arithmetic says no supported bitrate
 *     step fits under cfg->max_frame_bytes -> ERR_RATE_UNACHIEVABLE. This is
 *     a pure computation over already-known numbers (the picked native
 *     geometry/fps and the requested ceiling); it never calls into MF or a
 *     driver, so it cannot be confused with a device failure — the two
 *     failure classes literally cannot alias here, which is the strongest
 *     answer this codebase can give to E6b's blind spot: not "we were
 *     careful", but "the two paths do not share a call site".
 *   - MFEnumDeviceSources returns zero capture devices, or MFTEnumEx returns
 *     zero encoder/decoder MFTs of ANY kind (hardware or software — Windows
 *     always ships a software H.264 encoder and decoder MFT, so an empty
 *     result here means Media Foundation itself is unavailable, not merely
 *     slow) -> ERR_UNSUPPORTED. A property of the device, not of this call;
 *     confirmed by hand on the acceptance VM (Get-PnpDevice -Class Camera —
 *     no camera exists at all, see BUILD_REQUEST_V1.16.md).
 *   - Any other MF/D3D11 call fails (IMFMediaSource activation refused,
 *     IMFSourceReader::SetCurrentMediaType refused for every native format
 *     tried, IMFTransform::SetInputType/SetOutputType/ProcessMessage
 *     refused, ID3D11Device creation failed even with WARP) -> ERR_BACKEND.
 *     The device enumeration already succeeded (so ERR_UNSUPPORTED does not
 *     apply — a device exists), and no ceiling arithmetic was involved (so
 *     ERR_RATE_UNACHIEVABLE does not apply either): what is left is "this
 *     attempt failed", which is exactly ERR_BACKEND's definition and
 *     retryable in principle (camera freed up, driver reset).
 *
 * I11 (verification report, never guessed): hardware_encode/hardware_decode
 * reflect exactly which MFT MFTEnumEx handed back — MFT_ENUM_FLAG_HARDWARE
 * succeeded and was activated -> HW_YES; only the unfiltered (software)
 * enumeration produced a usable MFT -> HW_NO; enumeration itself could not be
 * run at all (MFStartup failed) -> NOT_DETERMINABLE. Never upgraded because a
 * hardware-flagged enumeration was merely *attempted*.
 *
 * THREADING. One dedicated capture+encode thread, created in start() and
 * joined in stop() — the same shape as the voice backend's render thread
 * (native/cleona_voice/windows/cleona_voice_windows.c). It owns ReadSample,
 * ProcessInput/ProcessOutput on the encoder, and applies pending
 * reconfigure()/set_capture_enabled()/request_keyframe() requests
 * cooperatively at the top of each loop iteration rather than racing another
 * thread for the same COM objects — cleona_video_reconfigure() posts a
 * request and waits (bounded) for the capture thread to pick it up and signal
 * completion. submit_encoded() (decode direction) touches only the decoder
 * MFT and never the capture/encoder objects, so it needs no coordination with
 * the capture thread beyond the session lock.
 * ---------------------------------------------------------------------------
 */

#define INITGUID
#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#define _CRT_SECURE_NO_WARNINGS

#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mftransform.h>
#include <mferror.h>
#include <codecapi.h>
#include <icodecapi.h>  /* the ICodecAPI interface itself; codecapi.h only has the property GUIDs */
#include <d3d11.h>
#include <dxgi1_2.h>    /* IDXGIResource1::CreateSharedHandle, used by cleona_video_get_texture_id */

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "../cleona_video.h"

/* ==========================================================================
 * CODECAPI_* property GUIDs — storage gap, same class of issue V1.4 already
 * found and documented (native/cleona_voice/windows/cleona_voice_windows.c:
 * "the KS type GUIDs in ksmedia.h expand ... through ks.h's OWN
 * DEFINE_GUIDEX(n) -> EXTERN_C const CDECL GUID n -- a macro ... that ignores
 * INITGUID entirely"). codecapi.h's DEFINE_CODECAPI_GUID macro routes through
 * exactly that same ks.h/mmreg.h DEFINE_GUIDEX in plain-C translation units
 * (mfobjects.h/mfidl.h/mfreadwrite.h GUIDs are a DIFFERENT family — EXTERN_GUID,
 * which DOES respect INITGUID and is additionally satisfied by mfuuid.lib —
 * so this gap is specific to codecapi.h, verified by reading both macro
 * definitions on this build VM's Windows Kit (10.0.26100.0), not assumed by
 * analogy). No codecapi.lib ships to provide storage for a plain-C consumer.
 * The five values below are transcribed byte-for-byte from
 * `um\codecapi.h`'s own DEFINE_CODECAPI_GUID invocations (grepped on the
 * build VM), not recalled from memory. */
DEFINE_GUID(CODECAPI_AVEncCommonRateControlMode, 0x1c0608e9, 0x370c, 0x4710, 0x8a, 0x58, 0xcb, 0x61, 0x81, 0xc4, 0x24, 0x23);
DEFINE_GUID(CODECAPI_AVEncCommonMeanBitRate,      0xf7222374, 0x2144, 0x4815, 0xb5, 0x50, 0xa3, 0x7f, 0x8e, 0x12, 0xee, 0x52);
DEFINE_GUID(CODECAPI_AVEncMPVGOPSize,             0x95f31b26, 0x95a4, 0x41aa, 0x93, 0x03, 0x24, 0x6a, 0x7f, 0xc6, 0xee, 0xf1);
DEFINE_GUID(CODECAPI_AVEncVideoForceKeyFrame,     0x398c1b98, 0x8353, 0x475a, 0x9e, 0xf2, 0x8f, 0x26, 0x5d, 0x26, 0x03, 0x45);
DEFINE_GUID(CODECAPI_AVLowLatencyMode,            0x9c27891a, 0xed7a, 0x40e1, 0x88, 0xe8, 0xb2, 0x27, 0x27, 0xa0, 0x24, 0xee);

/* ==========================================================================
 * Negotiation constants and policy — mirrors the shape of
 * mock/cleona_video_mock.c's negotiate() (same conceptual algorithm: clamp
 * down, then shrink the bitrate to fit the ceiling, then fail closed) so that
 * a Dart caller sees the same negotiation SHAPE from every backend. The
 * numeric estimate of bytes-per-frame is necessarily a formula, not a
 * measurement, because it has to answer BEFORE a single frame has been
 * encoded (Erratum 6b: open() must already know whether the request is
 * achievable). It is deliberately conservative (a keyframe several times
 * larger than a delta frame is typical for H.264 at these presets) so that
 * "accepted" under-promises rather than over-promises; the real encoder
 * still enforces the I9 backstop (wv_process_encoder_output below) against
 * whatever the hardware/software encoder actually produces, so a wrong
 * estimate here costs throughput, never correctness. */
#define CLEONA_VIDEO_WIN_MIN_BITRATE_KBPS   64
#define CLEONA_VIDEO_WIN_KEYFRAME_FACTOR    8
#define CLEONA_VIDEO_WIN_MIN_KEY_BYTES      256   /* Annex-B SPS+PPS+IDR floor */
#define CLEONA_VIDEO_WIN_MAX_WIDTH          1920
#define CLEONA_VIDEO_WIN_MAX_HEIGHT         1080
#define CLEONA_VIDEO_WIN_MAX_FPS            60
#define CLEONA_VIDEO_WIN_RING_FRAMES        8     /* backpressure tolerance, see read_encoded */

static int32_t clamp_down_i32(int32_t requested, int32_t ceiling) {
    return requested > ceiling ? ceiling : requested;
}

static int32_t wv_nominal_delta_bytes(int32_t kbps, int32_t fps) {
    int64_t b = (int64_t)kbps * 125 / fps;   /* kbps*1000/8/fps, same formula as the mock */
    if (b < CLEONA_VIDEO_WIN_MIN_KEY_BYTES) b = CLEONA_VIDEO_WIN_MIN_KEY_BYTES;
    return (int32_t)b;
}

/* Validates and settles a request into an accepted configuration WITHOUT
 * touching any device — see the file doc's "WHEN THIS BACKEND TOUCHES THE
 * CAMERA". Codec/geometry/fps are settled against static upper bounds here;
 * the ACTUAL achievable geometry/fps additionally gets clamped to whatever
 * the picked native camera mode turns out to be once a device is available
 * (wv_setup_capture, called only from cleona_video_open and only after this
 * function already said the request is well-formed). Returns CLEONA_VIDEO_OK,
 * CLEONA_VIDEO_ERR_INVALID or CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE — never
 * ERR_UNSUPPORTED/ERR_BACKEND, which are device-contact outcomes decided
 * elsewhere (file doc, "ERROR CODE SELECTION"). */
static int32_t wv_negotiate(const cleona_video_config_t* cfg, int32_t min_bitrate_kbps,
                             cleona_video_config_t* out) {
    if (!cfg || !out) return CLEONA_VIDEO_ERR_INVALID;
    if (cfg->width <= 0 || cfg->height <= 0 || cfg->fps <= 0) return CLEONA_VIDEO_ERR_INVALID;
    if (cfg->target_bitrate_kbps <= 0) return CLEONA_VIDEO_ERR_INVALID;
    if (cfg->max_frame_bytes <= 0) return CLEONA_VIDEO_ERR_INVALID;
    if (cfg->keyframe_interval_frames < 0) return CLEONA_VIDEO_ERR_INVALID;

    int32_t codec = cfg->codec;
    if (codec <= 0) {
        codec = CLEONA_VIDEO_CODEC_H264;
    } else if (codec > CLEONA_VIDEO_CODEC_VP9) {
        return CLEONA_VIDEO_ERR_INVALID; /* unknown positive value: caller bug */
    } else if (codec != CLEONA_VIDEO_CODEC_H264) {
        /* This backend implements H.264 only (the mandatory interop level);
         * HEVC/AV1/VP9 negotiation is future work, not required for
         * acceptance (cleona_video.h: "every backend MUST support H264 ...
         * negotiates down to H264 rather than failing"). */
        codec = CLEONA_VIDEO_CODEC_H264;
    }

    int32_t width  = clamp_down_i32(cfg->width,  CLEONA_VIDEO_WIN_MAX_WIDTH);
    int32_t height = clamp_down_i32(cfg->height, CLEONA_VIDEO_WIN_MAX_HEIGHT);
    int32_t fps    = clamp_down_i32(cfg->fps,    CLEONA_VIDEO_WIN_MAX_FPS);
    int32_t kbps   = cfg->target_bitrate_kbps;

    int32_t nominal_budget = cfg->max_frame_bytes / CLEONA_VIDEO_WIN_KEYFRAME_FACTOR;
    if (nominal_budget < CLEONA_VIDEO_WIN_MIN_KEY_BYTES) {
        return CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE;
    }
    if (wv_nominal_delta_bytes(kbps, fps) > nominal_budget) {
        int64_t fit_kbps = (int64_t)nominal_budget * fps / 125;
        if (fit_kbps < min_bitrate_kbps) return CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE;
        if (fit_kbps < kbps) kbps = (int32_t)fit_kbps;
    }

    out->codec                    = codec;
    out->width                    = width;
    out->height                   = height;
    out->fps                      = fps;
    out->target_bitrate_kbps      = kbps;
    out->max_frame_bytes          = cfg->max_frame_bytes; /* never raised */
    out->keyframe_interval_frames =
        cfg->keyframe_interval_frames > 0 ? cfg->keyframe_interval_frames : fps * 2;
    return CLEONA_VIDEO_OK;
}

/* Erratum 6b in-band error channel — identical construction to the mock and
 * to cleona_voice_open's out_format->sample_rate. */
static void wv_write_open_error(cleona_video_config_t* out, int32_t code) {
    if (!out) return;
    memset(out, 0, sizeof(*out));
    out->max_frame_bytes = code;
}

/* ==========================================================================
 * MFGetAttributeSize/MFSetAttributeSize/...Ratio replacements.
 *
 * mfapi.h's own versions of these four helpers exist ONLY inside an
 * `#ifdef __cplusplus` block (verified on the build VM's Windows Kit
 * 10.0.26100.0: `#ifdef __cplusplus` at mfapi.h:4288, the helpers themselves
 * at :4406-4470, and their bodies call `pAttributes->GetUINT64(...)` — C++
 * member-call syntax, not the COBJMACROS `IMFAttributes_GetUINT64(...)` this
 * translation unit uses everywhere else). A plain-C build never sees them
 * declared at all — this is not a storage gap like the CODECAPI_* GUIDs
 * above (an extern with no definition); the symbols do not exist in C mode
 * in this SDK, full stop. Reimplemented here from the same 32:32 UINT64
 * packing mfapi.h's own C++ versions use (MF_MT_FRAME_SIZE/MF_MT_FRAME_RATE/
 * MF_MT_PIXEL_ASPECT_RATIO are documented as high32:low32 packed UINT64
 * attributes), against IMFAttributes via COBJMACROS. IMFMediaType inherits
 * IMFAttributes; the cast below is the ordinary, safe COM idiom for calling a
 * base interface's methods through COBJMACROS on a derived pointer. */
static HRESULT wv_get_attr_size(IMFMediaType* t, REFGUID key, UINT32* w, UINT32* h) {
    UINT64 packed = 0;
    HRESULT hr = IMFAttributes_GetUINT64((IMFAttributes*)t, key, &packed);
    if (FAILED(hr)) return hr;
    *w = (UINT32)(packed >> 32);
    *h = (UINT32)(packed & 0xFFFFFFFFu);
    return S_OK;
}
static HRESULT wv_set_attr_size(IMFMediaType* t, REFGUID key, UINT32 w, UINT32 h) {
    UINT64 packed = (((UINT64)w) << 32) | (UINT64)h;
    return IMFAttributes_SetUINT64((IMFAttributes*)t, key, packed);
}
static HRESULT wv_get_attr_ratio(IMFMediaType* t, REFGUID key, UINT32* num, UINT32* den) {
    return wv_get_attr_size(t, key, num, den); /* identical packing scheme */
}
static HRESULT wv_set_attr_ratio(IMFMediaType* t, REFGUID key, UINT32 num, UINT32 den) {
    return wv_set_attr_size(t, key, num, den);
}

/* ==========================================================================
 * Small helpers
 * ========================================================================== */
static __declspec(thread) int g_com_inited = 0;
static void wv_com_ensure(void) {
    if (g_com_inited) return;
    HRESULT hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    if (SUCCEEDED(hr) || hr == RPC_E_CHANGED_MODE) g_com_inited = 1;
}
static void wv_com_thread_exit(void) {
    if (g_com_inited) { CoUninitialize(); g_com_inited = 0; }
}

/* Annex-B helpers, mirroring the scan mock/cleona_video_mock.c already uses
 * (last start code, NAL type byte immediately after it). Used to (a) detect
 * whether an encoder output sample is a keyframe when MFSampleExtension_
 * CleanPoint is absent, and (b) validate what the peer claims in
 * submit_encoded against what the bitstream actually contains, exactly as
 * cleona_video.h documents: "a backend that also inspects the bitstream and
 * finds a contradiction returns ERR_DECODE rather than feeding its decoder a
 * lie." */
static int32_t wv_last_start_code(const uint8_t* d, int32_t n) {
    int32_t found = -1;
    for (int32_t i = 0; i + 4 <= n; i++) {
        if (d[i] == 0 && d[i + 1] == 0 && d[i + 2] == 0 && d[i + 3] == 1) found = i;
    }
    return found;
}
static int wv_bitstream_has_idr(const uint8_t* d, int32_t n) {
    /* Scan every start code (not just the last) — a keyframe access unit is
     * SPS(0x67)+PPS(0x68)+IDR(0x65), and the IDR slice is what carries the
     * type-5 NAL, not necessarily the trailing NAL of the sample. */
    for (int32_t i = 0; i + 5 <= n; i++) {
        if (d[i] == 0 && d[i + 1] == 0 && d[i + 2] == 0 && d[i + 3] == 1) {
            if ((d[i + 4] & 0x1F) == 5) return 1;
        }
    }
    return 0;
}

/* ==========================================================================
 * Ring buffer of encoded frames — the capture+encode thread produces into
 * this, cleona_video_read_encoded drains it. Sized at
 * CLEONA_VIDEO_WIN_RING_FRAMES (~250-500ms at typical presets) so that normal
 * reader latency never loses a frame; a reader that falls further behind than
 * that drops the oldest queued frame. This is NOT the I9 backstop
 * (frames_dropped_oversize is reserved for a frame that violates
 * max_frame_bytes, cleona_video.h) — a ring-full drop is ordinary real-time
 * backpressure handling, the same principle live media is exempt from
 * retransmission for at the transport layer (§10.3.1): a frame that arrives
 * late is worth less than a frame that arrives on time, so it is not worth
 * queuing forever. */
typedef struct {
    uint8_t* buf;
    int32_t  cap;
    int32_t  size;
    int32_t  flags;
    int64_t  pts_us;
} wv_frame_slot_t;

/* ==========================================================================
 * Session
 * ========================================================================== */
#define ST_OPEN    0
#define ST_RUNNING 1
#define ST_CLOSED  2

typedef struct {
    int32_t pending;         /* a reconfigure request is waiting for the capture thread */
    cleona_video_config_t cfg;
    int32_t result;          /* filled by the capture thread once applied */
    cleona_video_config_t applied;
    HANDLE done_event;
} wv_reconfig_req_t;

struct cleona_video_session {
    CRITICAL_SECTION lock;
    int32_t state;
    cleona_video_config_t cfg;   /* negotiated, authoritative */

    /* capture */
    IMFActivate** cap_activates;
    UINT32        cap_activate_count;
    UINT32        cap_activate_index;
    IMFMediaSource*   cap_source;
    IMFSourceReader*  cap_reader;

    /* encode */
    IMFTransform* enc;
    ICodecAPI*    enc_codec_api;
    int32_t       enc_is_hw;
    DWORD         enc_in_stream_id, enc_out_stream_id;
    int32_t       enc_out_provides_samples;

    /* decode */
    IMFTransform* dec;
    int32_t       dec_is_hw;
    DWORD         dec_in_stream_id, dec_out_stream_id;
    int32_t       dec_out_provides_samples;
    int32_t       awaiting_keyframe;

    /* D3D11 render target for decoded frames (I10's one legitimate native
     * pixel conversion — NV12 -> BGRA8, see wv_upload_nv12_to_texture) */
    ID3D11Device*        d3d_device;
    ID3D11DeviceContext* d3d_ctx;
    ID3D11Texture2D*     tex;
    int32_t              tex_w, tex_h;

    /* capture+encode thread */
    HANDLE   capenc_thread;
    HANDLE   stop_event;
    int32_t  running;
    int32_t  capture_enabled;
    int32_t  force_keyframe;
    int64_t  frame_index;
    LONGLONG pts_base_100ns;    /* first sample's raw MF timestamp, normalised to ~0 */
    int32_t  have_pts_base;

    wv_reconfig_req_t reconfig;

    /* output ring, protected by `lock`; capenc thread pushes, read_encoded pops */
    wv_frame_slot_t ring[CLEONA_VIDEO_WIN_RING_FRAMES];
    int32_t ring_head, ring_count;
    HANDLE  ring_event;         /* auto-reset, signalled on push */

    /* report counters */
    int64_t frames_captured, frames_encoded, frames_dropped_oversize;
    int64_t frames_decoded, decode_failures;
};

/* ==========================================================================
 * Capture device enumeration and native-format selection
 * ========================================================================== */
static HRESULT wv_enum_capture_devices(IMFActivate*** out_list, UINT32* out_count) {
    IMFAttributes* attrs = NULL;
    HRESULT hr = MFCreateAttributes(&attrs, 1);
    if (FAILED(hr)) return hr;
    hr = IMFAttributes_SetGUID(attrs, &MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                                &MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
    if (SUCCEEDED(hr)) {
        hr = MFEnumDeviceSources(attrs, out_list, out_count);
    }
    IMFAttributes_Release(attrs);
    return hr;
}

/* Picks the native type on stream 0 whose frame size is closest to
 * (req_w,req_h) and whose frame rate is the highest not exceeding req_fps (or
 * the lowest available, if none is <= req_fps) — never inventing a mode the
 * hardware did not report. Returns the winning index, or -1. */
static int32_t wv_pick_native_type(IMFSourceReader* reader, int32_t req_w, int32_t req_h,
                                    int32_t req_fps, UINT32* out_w, UINT32* out_h,
                                    UINT32* out_num, UINT32* out_den) {
    int32_t best_idx = -1;
    int64_t best_geom_cost = -1;
    UINT32 best_fps_num = 0, best_fps_den = 1;

    for (DWORD i = 0; ; i++) {
        IMFMediaType* t = NULL;
        HRESULT hr = IMFSourceReader_GetNativeMediaType(
            reader, (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, i, &t);
        if (hr == MF_E_NO_MORE_TYPES || !t) break;
        if (FAILED(hr)) break;

        UINT32 w = 0, h = 0, num = 0, den = 1;
        if (SUCCEEDED(wv_get_attr_size(t, &MF_MT_FRAME_SIZE, &w, &h)) &&
            SUCCEEDED(wv_get_attr_ratio(t, &MF_MT_FRAME_RATE, &num, &den)) &&
            w > 0 && h > 0 && den > 0 && num > 0) {
            int64_t geom_cost = (int64_t)llabs((long long)w - req_w) +
                                 (int64_t)llabs((long long)h - req_h);
            double fps = (double)num / (double)den;
            int fits_fps = fps <= (double)req_fps + 0.01;
            int is_better;
            if (best_idx < 0) {
                is_better = 1;
            } else if (geom_cost != best_geom_cost) {
                is_better = geom_cost < best_geom_cost;
            } else {
                double best_fps = (double)best_fps_num / (double)best_fps_den;
                int best_fits = best_fps <= (double)req_fps + 0.01;
                if (fits_fps != best_fits) {
                    is_better = fits_fps; /* prefer a mode that meets the request */
                } else if (fits_fps) {
                    is_better = fps > best_fps; /* both fit: prefer the higher one */
                } else {
                    is_better = fps < best_fps; /* neither fits: prefer the lower one */
                }
            }
            if (is_better) {
                best_idx = (int32_t)i;
                best_geom_cost = geom_cost;
                *out_w = w; *out_h = h; *out_num = num; *out_den = den;
                best_fps_num = num; best_fps_den = den;
            }
        }
        IMFMediaType_Release(t);
    }
    return best_idx;
}

/* Activates the capture device at cap_activate_index, picks the closest
 * native mode to (req), sets it current, then requests NV12 conversion on
 * top of it. Fills *out_w/*out_h/*out_num/*out_den with what was actually
 * applied (read back via GetCurrentMediaType, never assumed). Touches real
 * hardware — callable only from cleona_video_open/switch_camera, never
 * concurrently with the capture thread's ReadSample. */
static HRESULT wv_setup_capture(cleona_video_session_t* s, int32_t req_w, int32_t req_h,
                                 int32_t req_fps, UINT32* out_w, UINT32* out_h,
                                 UINT32* out_num, UINT32* out_den) {
    HRESULT hr = IMFActivate_ActivateObject(s->cap_activates[s->cap_activate_index],
                                             &IID_IMFMediaSource, (void**)&s->cap_source);
    if (FAILED(hr) || !s->cap_source) return FAILED(hr) ? hr : E_FAIL;

    IMFAttributes* rattrs = NULL;
    hr = MFCreateAttributes(&rattrs, 2);
    if (SUCCEEDED(hr)) {
        IMFAttributes_SetUINT32(rattrs, &MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, TRUE);
        IMFAttributes_SetUINT32(rattrs, &MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE);
    }
    hr = MFCreateSourceReaderFromMediaSource(s->cap_source, rattrs, &s->cap_reader);
    if (rattrs) IMFAttributes_Release(rattrs);
    if (FAILED(hr) || !s->cap_reader) {
        IMFMediaSource_Release(s->cap_source);
        s->cap_source = NULL;
        return FAILED(hr) ? hr : E_FAIL;
    }

    UINT32 nw = 0, nh = 0, nnum = 0, nden = 1;
    int32_t idx = wv_pick_native_type(s->cap_reader, req_w, req_h, req_fps, &nw, &nh, &nnum, &nden);
    if (idx < 0) {
        IMFSourceReader_Release(s->cap_reader); s->cap_reader = NULL;
        IMFMediaSource_Release(s->cap_source);  s->cap_source = NULL;
        return E_FAIL;
    }

    IMFMediaType* native = NULL;
    hr = IMFSourceReader_GetNativeMediaType(s->cap_reader,
        (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, (DWORD)idx, &native);
    if (SUCCEEDED(hr)) {
        hr = IMFSourceReader_SetCurrentMediaType(s->cap_reader,
            (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, NULL, native);
        IMFMediaType_Release(native);
    }
    if (FAILED(hr)) goto fail;

    /* Request NV12 output on top of the now-current native type. MF's
     * built-in video processor (enabled above) performs the colour-space
     * conversion transparently; frame size/rate are left as the native
     * values just picked, so no resampling happens here — only format
     * conversion, which is exactly what §10.6 allows natively. */
    IMFMediaType* desired = NULL;
    hr = MFCreateMediaType(&desired);
    if (SUCCEEDED(hr)) {
        IMFMediaType_SetGUID(desired, &MF_MT_MAJOR_TYPE, &MFMediaType_Video);
        IMFMediaType_SetGUID(desired, &MF_MT_SUBTYPE, &MFVideoFormat_NV12);
        wv_set_attr_size(desired, &MF_MT_FRAME_SIZE, nw, nh);
        wv_set_attr_ratio(desired, &MF_MT_FRAME_RATE, nnum, nden);
        hr = IMFSourceReader_SetCurrentMediaType(s->cap_reader,
            (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, NULL, desired);
        IMFMediaType_Release(desired);
    }
    if (FAILED(hr)) goto fail;

    IMFMediaType* applied = NULL;
    hr = IMFSourceReader_GetCurrentMediaType(s->cap_reader,
        (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, &applied);
    if (SUCCEEDED(hr)) {
        UINT32 aw = 0, ah = 0, anum = 0, aden = 1;
        wv_get_attr_size(applied, &MF_MT_FRAME_SIZE, &aw, &ah);
        wv_get_attr_ratio(applied, &MF_MT_FRAME_RATE, &anum, &aden);
        IMFMediaType_Release(applied);
        if (aw > 0 && ah > 0 && anum > 0 && aden > 0) {
            *out_w = aw; *out_h = ah; *out_num = anum; *out_den = aden;
        } else {
            *out_w = nw; *out_h = nh; *out_num = nnum; *out_den = nden;
        }
    } else {
        *out_w = nw; *out_h = nh; *out_num = nnum; *out_den = nden;
    }
    return S_OK;

fail:
    IMFSourceReader_Release(s->cap_reader); s->cap_reader = NULL;
    IMFMediaSource_Release(s->cap_source);  s->cap_source = NULL;
    return hr;
}

static void wv_teardown_capture(cleona_video_session_t* s) {
    if (s->cap_reader) { IMFSourceReader_Release(s->cap_reader); s->cap_reader = NULL; }
    if (s->cap_source) {
        IMFMediaSource_Shutdown(s->cap_source);
        IMFMediaSource_Release(s->cap_source);
        s->cap_source = NULL;
    }
}

/* ==========================================================================
 * MFT enumeration — shared by encoder and decoder setup. hardware-first,
 * software fallback; *out_is_hw records honestly which one actually got used
 * (I11 — never guessed).
 * ========================================================================== */
static HRESULT wv_enum_mft(GUID category, int input_is_h264 /* 0=encoder(H264 out), 1=decoder(H264 in) */,
                            IMFTransform** out_mft, int32_t* out_is_hw) {
    MFT_REGISTER_TYPE_INFO h264_type = { MFMediaType_Video, MFVideoFormat_H264 };
    MFT_REGISTER_TYPE_INFO* in_type  = input_is_h264 ? &h264_type : NULL;
    MFT_REGISTER_TYPE_INFO* out_type = input_is_h264 ? NULL : &h264_type;

    IMFActivate** acts = NULL;
    UINT32 n = 0;
    HRESULT hr = MFTEnumEx(category,
                            MFT_ENUM_FLAG_HARDWARE | MFT_ENUM_FLAG_SORTANDFILTER,
                            in_type, out_type, &acts, &n);
    int is_hw = 1;
    if (FAILED(hr) || n == 0) {
        if (acts) { for (UINT32 i = 0; i < n; i++) IMFActivate_Release(acts[i]); CoTaskMemFree(acts); }
        acts = NULL; n = 0;
        hr = MFTEnumEx(category, MFT_ENUM_FLAG_SYNCMFT, in_type, out_type, &acts, &n);
        is_hw = 0;
    }
    if (FAILED(hr) || n == 0) {
        if (acts) { for (UINT32 i = 0; i < n; i++) IMFActivate_Release(acts[i]); CoTaskMemFree(acts); }
        return FAILED(hr) ? hr : MF_E_NOT_FOUND; /* -> caller maps to ERR_UNSUPPORTED */
    }

    IMFTransform* mft = NULL;
    hr = IMFActivate_ActivateObject(acts[0], &IID_IMFTransform, (void**)&mft);
    for (UINT32 i = 0; i < n; i++) IMFActivate_Release(acts[i]);
    CoTaskMemFree(acts);
    if (FAILED(hr) || !mft) return FAILED(hr) ? hr : E_FAIL;

    *out_mft = mft;
    *out_is_hw = is_hw;
    return S_OK;
}

static HRESULT wv_setup_encoder(cleona_video_session_t* s, UINT32 w, UINT32 h,
                                 UINT32 fps_num, UINT32 fps_den,
                                 int32_t bitrate_kbps, int32_t keyframe_interval) {
    int32_t is_hw = 0;
    HRESULT hr = wv_enum_mft(MFT_CATEGORY_VIDEO_ENCODER, /*input_is_h264=*/0, &s->enc, &is_hw);
    if (FAILED(hr)) return hr;
    s->enc_is_hw = is_hw;

    IMFMediaType* out_t = NULL;
    hr = MFCreateMediaType(&out_t);
    if (SUCCEEDED(hr)) {
        IMFMediaType_SetGUID(out_t, &MF_MT_MAJOR_TYPE, &MFMediaType_Video);
        IMFMediaType_SetGUID(out_t, &MF_MT_SUBTYPE, &MFVideoFormat_H264);
        IMFMediaType_SetUINT32(out_t, &MF_MT_AVG_BITRATE, (UINT32)(bitrate_kbps * 1000));
        IMFMediaType_SetUINT32(out_t, &MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
        /* Constrained Baseline — §10.6 "Codec decision": the mandatory
         * interop level, chosen so a peer with the least capable decoder can
         * always play this stream back. */
        IMFMediaType_SetUINT32(out_t, &MF_MT_MPEG2_PROFILE, eAVEncH264VProfile_Base);
        wv_set_attr_size(out_t, &MF_MT_FRAME_SIZE, w, h);
        wv_set_attr_ratio(out_t, &MF_MT_FRAME_RATE, fps_num, fps_den);
        wv_set_attr_ratio(out_t, &MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
        hr = IMFTransform_SetOutputType(s->enc, 0, out_t, 0);
        IMFMediaType_Release(out_t);
    }
    if (FAILED(hr)) { IMFTransform_Release(s->enc); s->enc = NULL; return hr; }

    IMFMediaType* in_t = NULL;
    hr = MFCreateMediaType(&in_t);
    if (SUCCEEDED(hr)) {
        IMFMediaType_SetGUID(in_t, &MF_MT_MAJOR_TYPE, &MFMediaType_Video);
        IMFMediaType_SetGUID(in_t, &MF_MT_SUBTYPE, &MFVideoFormat_NV12);
        IMFMediaType_SetUINT32(in_t, &MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
        wv_set_attr_size(in_t, &MF_MT_FRAME_SIZE, w, h);
        wv_set_attr_ratio(in_t, &MF_MT_FRAME_RATE, fps_num, fps_den);
        wv_set_attr_ratio(in_t, &MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
        hr = IMFTransform_SetInputType(s->enc, 0, in_t, 0);
        IMFMediaType_Release(in_t);
    }
    if (FAILED(hr)) { IMFTransform_Release(s->enc); s->enc = NULL; return hr; }

    /* Best-effort tuning via ICodecAPI. None of these failing is fatal — the
     * encoder already has a valid input/output type without them; they only
     * shape rate control and GOP structure. */
    if (SUCCEEDED(IMFTransform_QueryInterface(s->enc, &IID_ICodecAPI, (void**)&s->enc_codec_api))
        && s->enc_codec_api) {
        VARIANT v;
        VariantInit(&v);
        v.vt = VT_UI4; v.ulVal = eAVEncCommonRateControlMode_CBR;
        ICodecAPI_SetValue(s->enc_codec_api, &CODECAPI_AVEncCommonRateControlMode, &v);
        VariantClear(&v);

        VariantInit(&v);
        v.vt = VT_UI4; v.ulVal = (ULONG)(bitrate_kbps * 1000);
        ICodecAPI_SetValue(s->enc_codec_api, &CODECAPI_AVEncCommonMeanBitRate, &v);
        VariantClear(&v);

        if (keyframe_interval > 0) {
            VariantInit(&v);
            v.vt = VT_UI4; v.ulVal = (ULONG)keyframe_interval;
            ICodecAPI_SetValue(s->enc_codec_api, &CODECAPI_AVEncMPVGOPSize, &v);
            VariantClear(&v);
        }

        VariantInit(&v);
        v.vt = VT_BOOL; v.boolVal = VARIANT_TRUE;
        ICodecAPI_SetValue(s->enc_codec_api, &CODECAPI_AVLowLatencyMode, &v);
        VariantClear(&v);
    }

    MFT_OUTPUT_STREAM_INFO osi;
    memset(&osi, 0, sizeof(osi));
    if (SUCCEEDED(IMFTransform_GetOutputStreamInfo(s->enc, 0, &osi))) {
        s->enc_out_provides_samples =
            (osi.dwFlags & (MFT_OUTPUT_STREAM_PROVIDES_SAMPLES | MFT_OUTPUT_STREAM_CAN_PROVIDE_SAMPLES)) != 0;
    }

    IMFTransform_ProcessMessage(s->enc, MFT_MESSAGE_COMMAND_FLUSH, 0);
    IMFTransform_ProcessMessage(s->enc, MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0);
    IMFTransform_ProcessMessage(s->enc, MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0);
    return S_OK;
}

static HRESULT wv_setup_decoder(cleona_video_session_t* s, UINT32 w, UINT32 h) {
    int32_t is_hw = 0;
    HRESULT hr = wv_enum_mft(MFT_CATEGORY_VIDEO_DECODER, /*input_is_h264=*/1, &s->dec, &is_hw);
    if (FAILED(hr)) return hr;
    s->dec_is_hw = is_hw;

    IMFMediaType* in_t = NULL;
    hr = MFCreateMediaType(&in_t);
    if (SUCCEEDED(hr)) {
        IMFMediaType_SetGUID(in_t, &MF_MT_MAJOR_TYPE, &MFMediaType_Video);
        IMFMediaType_SetGUID(in_t, &MF_MT_SUBTYPE, &MFVideoFormat_H264);
        wv_set_attr_size(in_t, &MF_MT_FRAME_SIZE, w, h);
        hr = IMFTransform_SetInputType(s->dec, 0, in_t, 0);
        IMFMediaType_Release(in_t);
    }
    if (FAILED(hr)) { IMFTransform_Release(s->dec); s->dec = NULL; return hr; }

    /* Enumerate available output types and pick NV12 — decoders offer several
     * (NV12, YV12, IYUV, ...) and do not default to a fixed one the way the
     * encoder's output type is fixed to H264. */
    IMFMediaType* out_t = NULL;
    HRESULT pick = MF_E_INVALIDTYPE;
    for (DWORD i = 0; ; i++) {
        IMFMediaType* cand = NULL;
        HRESULT ghr = IMFTransform_GetOutputAvailableType(s->dec, 0, i, &cand);
        if (ghr == MF_E_NO_MORE_TYPES || !cand) break;
        if (FAILED(ghr)) break;
        GUID sub;
        if (SUCCEEDED(IMFMediaType_GetGUID(cand, &MF_MT_SUBTYPE, &sub)) &&
            IsEqualGUID(&sub, &MFVideoFormat_NV12)) {
            wv_set_attr_size(cand, &MF_MT_FRAME_SIZE, w, h);
            pick = IMFTransform_SetOutputType(s->dec, 0, cand, 0);
            IMFMediaType_Release(cand);
            if (SUCCEEDED(pick)) break;
            continue;
        }
        IMFMediaType_Release(cand);
    }
    (void)out_t;
    if (FAILED(pick)) { IMFTransform_Release(s->dec); s->dec = NULL; return pick; }

    MFT_OUTPUT_STREAM_INFO osi;
    memset(&osi, 0, sizeof(osi));
    if (SUCCEEDED(IMFTransform_GetOutputStreamInfo(s->dec, 0, &osi))) {
        s->dec_out_provides_samples =
            (osi.dwFlags & (MFT_OUTPUT_STREAM_PROVIDES_SAMPLES | MFT_OUTPUT_STREAM_CAN_PROVIDE_SAMPLES)) != 0;
    }

    IMFTransform_ProcessMessage(s->dec, MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0);
    IMFTransform_ProcessMessage(s->dec, MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0);
    return S_OK;
}

/* ==========================================================================
 * D3D11 render target (I10's one legitimate pixel conversion, native side)
 * ========================================================================== */
static HRESULT wv_d3d11_init(cleona_video_session_t* s) {
    D3D_FEATURE_LEVEL got;
    D3D_DRIVER_TYPE tries[2] = { D3D_DRIVER_TYPE_HARDWARE, D3D_DRIVER_TYPE_WARP };
    HRESULT hr = E_FAIL;
    for (int i = 0; i < 2; i++) {
        hr = D3D11CreateDevice(NULL, tries[i], NULL, 0, NULL, 0, D3D11_SDK_VERSION,
                                &s->d3d_device, &got, &s->d3d_ctx);
        if (SUCCEEDED(hr)) break;
    }
    /* WARP (software rasteriser, shipped with every Windows install) is the
     * expected outcome on this acceptance VM: "Microsoft Basic Display
     * Adapter", AdapterRAM 0 — see BUILD_REQUEST_V1.16.md. A real texture
     * object either way; not a fabrication of GPU support that is not
     * there. */
    return hr;
}

static HRESULT wv_ensure_texture(cleona_video_session_t* s, UINT32 w, UINT32 h) {
    if (s->tex && s->tex_w == (int32_t)w && s->tex_h == (int32_t)h) return S_OK;
    if (s->tex) { ID3D11Texture2D_Release(s->tex); s->tex = NULL; }
    D3D11_TEXTURE2D_DESC desc;
    memset(&desc, 0, sizeof(desc));
    desc.Width = w; desc.Height = h;
    desc.MipLevels = 1; desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    HRESULT hr = ID3D11Device_CreateTexture2D(s->d3d_device, &desc, NULL, &s->tex);
    if (SUCCEEDED(hr)) { s->tex_w = (int32_t)w; s->tex_h = (int32_t)h; }
    return hr;
}

/* Plain BT.601 NV12 -> BGRA8, CPU-side. The only pixel-format conversion this
 * backend performs, and it happens entirely below the ABI (I10) — on a VM
 * with no GPU acceleration (this acceptance environment) a CPU upload is
 * also the honest choice: a "hardware colour convert" claim would not be
 * true here. */
static void wv_nv12_to_bgra_upload(cleona_video_session_t* s, const uint8_t* nv12,
                                    UINT32 w, UINT32 h, UINT32 y_stride, UINT32 uv_stride) {
    uint8_t* row = (uint8_t*)malloc((size_t)w * 4);
    if (!row) return;
    const uint8_t* y_plane  = nv12;
    const uint8_t* uv_plane = nv12 + (size_t)y_stride * h;
    for (UINT32 y = 0; y < h; y++) {
        const uint8_t* yrow = y_plane + (size_t)y_stride * y;
        const uint8_t* uvrow = uv_plane + (size_t)uv_stride * (y / 2);
        for (UINT32 x = 0; x < w; x++) {
            int Y = yrow[x];
            int U = uvrow[(x / 2) * 2 + 0] - 128;
            int V = uvrow[(x / 2) * 2 + 1] - 128;
            int r = Y + ((91881 * V) >> 16);
            int g = Y - ((22554 * U + 46802 * V) >> 16);
            int b = Y + ((116130 * U) >> 16);
            r = r < 0 ? 0 : (r > 255 ? 255 : r);
            g = g < 0 ? 0 : (g > 255 ? 255 : g);
            b = b < 0 ? 0 : (b > 255 ? 255 : b);
            row[x * 4 + 0] = (uint8_t)b;
            row[x * 4 + 1] = (uint8_t)g;
            row[x * 4 + 2] = (uint8_t)r;
            row[x * 4 + 3] = 0xFF;
        }
        D3D11_BOX box;
        box.left = 0; box.right = w; box.top = y; box.bottom = y + 1; box.front = 0; box.back = 1;
        ID3D11DeviceContext_UpdateSubresource(s->d3d_ctx, (ID3D11Resource*)s->tex, 0, &box,
                                               row, w * 4, 0);
    }
    free(row);
}

/* ==========================================================================
 * Ring buffer helpers — caller holds s->lock
 * ========================================================================== */
static void wv_ring_push_locked(cleona_video_session_t* s, const uint8_t* data, int32_t size,
                                 int32_t flags, int64_t pts_us) {
    int32_t idx;
    if (s->ring_count == CLEONA_VIDEO_WIN_RING_FRAMES) {
        /* Drop the oldest queued frame — see the ring's doc comment. */
        s->ring_head = (s->ring_head + 1) % CLEONA_VIDEO_WIN_RING_FRAMES;
        s->ring_count--;
    }
    idx = (s->ring_head + s->ring_count) % CLEONA_VIDEO_WIN_RING_FRAMES;
    wv_frame_slot_t* slot = &s->ring[idx];
    if (slot->cap < size) {
        uint8_t* nb = (uint8_t*)realloc(slot->buf, (size_t)size);
        if (!nb) return; /* drop silently on OOM; nothing else to do */
        slot->buf = nb;
        slot->cap = size;
    }
    memcpy(slot->buf, data, (size_t)size);
    slot->size = size;
    slot->flags = flags;
    slot->pts_us = pts_us;
    s->ring_count++;
    SetEvent(s->ring_event);
}

static int wv_ring_pop_locked(cleona_video_session_t* s, uint8_t* out, int32_t out_cap,
                               int32_t* out_size, int32_t* out_flags, int64_t* out_pts,
                               int32_t* out_needed) {
    if (s->ring_count == 0) return 0;
    wv_frame_slot_t* slot = &s->ring[s->ring_head];
    if (slot->size > out_cap) {
        if (out_needed) *out_needed = slot->size;
        return -1; /* ERR_BUFFER_TOO_SMALL; frame stays queued */
    }
    memcpy(out, slot->buf, (size_t)slot->size);
    *out_size = slot->size;
    *out_flags = slot->flags;
    *out_pts = slot->pts_us;
    s->ring_head = (s->ring_head + 1) % CLEONA_VIDEO_WIN_RING_FRAMES;
    s->ring_count--;
    return 1;
}

/* ==========================================================================
 * Encoder drive loop — pull output samples, enforce I9, push to the ring.
 * Caller holds s->lock is NOT assumed; this touches only s->enc/s->ring, and
 * is called exclusively from the capture+encode thread, so no lock is taken
 * around the MF calls themselves — only around the ring push (wv_ring_push_
 * locked requires it) and the counters.
 * ========================================================================== */
static void wv_drain_encoder(cleona_video_session_t* s) {
    for (;;) {
        MFT_OUTPUT_DATA_BUFFER odb;
        memset(&odb, 0, sizeof(odb));
        IMFSample* out_sample = NULL;
        if (!s->enc_out_provides_samples) {
            MFT_OUTPUT_STREAM_INFO osi;
            memset(&osi, 0, sizeof(osi));
            IMFTransform_GetOutputStreamInfo(s->enc, 0, &osi);
            IMFMediaBuffer* buf = NULL;
            if (FAILED(MFCreateMemoryBuffer(osi.cbSize > 0 ? osi.cbSize : (1 << 20), &buf))) return;
            if (FAILED(MFCreateSample(&out_sample))) { IMFMediaBuffer_Release(buf); return; }
            IMFSample_AddBuffer(out_sample, buf);
            IMFMediaBuffer_Release(buf);
            odb.pSample = out_sample;
        }
        odb.dwStreamID = 0;

        DWORD status = 0;
        HRESULT hr = IMFTransform_ProcessOutput(s->enc, 0, 1, &odb, &status);
        if (odb.pEvents) IMFCollection_Release(odb.pEvents);

        if (hr == MF_E_TRANSFORM_NEED_MORE_INPUT) {
            if (out_sample) IMFSample_Release(out_sample);
            return;
        }
        if (hr == MF_E_TRANSFORM_STREAM_CHANGE) {
            if (out_sample) IMFSample_Release(out_sample);
            if (odb.pSample) IMFSample_Release(odb.pSample);
            continue; /* output type renegotiation not needed for this ABI's fixed H264 out */
        }
        if (FAILED(hr)) {
            if (out_sample) IMFSample_Release(out_sample);
            return;
        }

        IMFSample* sample = s->enc_out_provides_samples ? odb.pSample : out_sample;
        if (!sample) return;

        IMFMediaBuffer* mb = NULL;
        if (SUCCEEDED(IMFSample_ConvertToContiguousBuffer(sample, &mb)) && mb) {
            BYTE* data = NULL; DWORD len = 0;
            if (SUCCEEDED(IMFMediaBuffer_Lock(mb, &data, NULL, &len))) {
                UINT32 clean = 0;
                int is_key = SUCCEEDED(IMFSample_GetUINT32(sample, &MFSampleExtension_CleanPoint, &clean))
                             ? (clean != 0) : wv_bitstream_has_idr(data, (int32_t)len);
                int32_t flags = is_key ? CLEONA_VIDEO_FLAG_KEYFRAME : 0;

                LONGLONG raw_pts = 0;
                IMFSample_GetSampleTime(sample, &raw_pts);
                EnterCriticalSection(&s->lock);
                if (!s->have_pts_base) { s->pts_base_100ns = raw_pts; s->have_pts_base = 1; }
                int64_t pts_us = (raw_pts - s->pts_base_100ns) / 10;
                if (pts_us < 0) pts_us = 0;

                s->frames_encoded++;
                if ((int32_t)len > s->cfg.max_frame_bytes) {
                    /* I9 backstop — defect counter, cleona_video.h. */
                    s->frames_dropped_oversize++;
                } else {
                    wv_ring_push_locked(s, data, (int32_t)len, flags, pts_us);
                }
                LeaveCriticalSection(&s->lock);
                IMFMediaBuffer_Unlock(mb);
            }
            IMFMediaBuffer_Release(mb);
        }
        IMFSample_Release(sample);
    }
}

/* ==========================================================================
 * Reconfiguration application — runs ONLY on the capture+encode thread
 * (start()ed sessions) or synchronously under the lock (not-yet-started
 * sessions, where there is no thread to hand this to yet). geometry_changed
 * forces a keyframe (cleona_video.h). Returns an ABI return code.
 * ========================================================================== */
static int32_t wv_apply_reconfig(cleona_video_session_t* s, const cleona_video_config_t* accepted) {
    int geometry_changed = accepted->width != s->cfg.width || accepted->height != s->cfg.height;

    if (geometry_changed && s->cap_reader) {
        UINT32 aw = 0, ah = 0, anum = 0, aden = 1;
        HRESULT hr = wv_setup_capture(s, accepted->width, accepted->height, accepted->fps,
                                       &aw, &ah, &anum, &aden);
        /* wv_setup_capture tears down and rebuilds cap_source/cap_reader
         * against the SAME activated device; on failure the session has no
         * capture path left, which the caller must treat as ERR_BACKEND
         * (device was capable a moment ago; this specific attempt failed). */
        if (FAILED(hr)) return CLEONA_VIDEO_ERR_BACKEND;

        if (s->enc) { IMFTransform_Release(s->enc); s->enc = NULL; }
        if (s->enc_codec_api) { ICodecAPI_Release(s->enc_codec_api); s->enc_codec_api = NULL; }
        hr = wv_setup_encoder(s, aw, ah, anum, aden, accepted->target_bitrate_kbps,
                               accepted->keyframe_interval_frames);
        if (FAILED(hr)) return CLEONA_VIDEO_ERR_BACKEND;

        if (s->dec) { IMFTransform_Release(s->dec); s->dec = NULL; }
        hr = wv_setup_decoder(s, aw, ah);
        if (FAILED(hr)) return CLEONA_VIDEO_ERR_BACKEND;

        wv_ensure_texture(s, aw, ah);
        s->force_keyframe = 1;
    } else if (s->enc_codec_api) {
        /* Rate-only change: adjust the running encoder live, no keyframe forced. */
        VARIANT v;
        VariantInit(&v);
        v.vt = VT_UI4; v.ulVal = (ULONG)(accepted->target_bitrate_kbps * 1000);
        ICodecAPI_SetValue(s->enc_codec_api, &CODECAPI_AVEncCommonMeanBitRate, &v);
        VariantClear(&v);
    }

    EnterCriticalSection(&s->lock);
    s->cfg = *accepted;
    LeaveCriticalSection(&s->lock);
    return CLEONA_VIDEO_OK;
}

/* ==========================================================================
 * Capture + encode thread
 * ========================================================================== */
static DWORD WINAPI wv_capenc_thread_proc(LPVOID arg) {
    cleona_video_session_t* s = (cleona_video_session_t*)arg;
    wv_com_ensure();

    for (;;) {
        if (WaitForSingleObject(s->stop_event, 0) == WAIT_OBJECT_0) break;

        EnterCriticalSection(&s->lock);
        int32_t reconfig_pending = s->reconfig.pending;
        cleona_video_config_t reconfig_cfg = s->reconfig.cfg;
        int32_t want_keyframe = s->force_keyframe;
        int32_t capture_on = s->capture_enabled;
        LeaveCriticalSection(&s->lock);

        if (reconfig_pending) {
            int32_t rc = wv_apply_reconfig(s, &reconfig_cfg);
            EnterCriticalSection(&s->lock);
            s->reconfig.result = rc;
            if (rc == CLEONA_VIDEO_OK) s->reconfig.applied = s->cfg;
            s->reconfig.pending = 0;
            LeaveCriticalSection(&s->lock);
            SetEvent(s->reconfig.done_event);
            continue;
        }

        if (want_keyframe && s->enc_codec_api) {
            VARIANT v; VariantInit(&v);
            v.vt = VT_BOOL; v.boolVal = VARIANT_TRUE;
            ICodecAPI_SetValue(s->enc_codec_api, &CODECAPI_AVEncVideoForceKeyFrame, &v);
            VariantClear(&v);
            EnterCriticalSection(&s->lock);
            s->force_keyframe = 0;
            LeaveCriticalSection(&s->lock);
        }

        if (!capture_on) {
            /* Own video off (I12): stop pulling frames entirely, so
             * frames_captured does not advance, but leave every object
             * alive — the decoder/texture keep serving the peer's picture. */
            WaitForSingleObject(s->stop_event, 10);
            continue;
        }

        IMFSample* sample = NULL;
        DWORD stream_flags = 0;
        LONGLONG ts = 0;
        HRESULT hr = IMFSourceReader_ReadSample(s->cap_reader,
            (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, NULL, &stream_flags, &ts, &sample);
        if (FAILED(hr)) {
            WaitForSingleObject(s->stop_event, 5);
            continue;
        }
        if (!sample) continue; /* end-of-stream / gap; nothing captured this tick */

        EnterCriticalSection(&s->lock);
        s->frames_captured++;
        LeaveCriticalSection(&s->lock);

        HRESULT feed = IMFTransform_ProcessInput(s->enc, 0, sample, 0);
        IMFSample_Release(sample);
        if (feed == MF_E_NOTACCEPTING) {
            /* Encoder's input queue is full: drain what it already has, then
             * this sample is lost for this tick — a live-media backend does
             * not block the capture cadence to force one specific frame
             * through (same principle as §10.3.1's "a frame that arrives
             * late is worth less than one that arrives on time"). */
            wv_drain_encoder(s);
            continue;
        }
        wv_drain_encoder(s);
    }

    wv_com_thread_exit();
    return 0;
}

/* ==========================================================================
 * Lifecycle
 * ========================================================================== */
CLEONA_VIDEO_API cleona_video_session_t* cleona_video_open(const cleona_video_config_t* cfg,
                                                             cleona_video_config_t* out_negotiated) {
    if (!cfg) { wv_write_open_error(out_negotiated, CLEONA_VIDEO_ERR_INVALID); return NULL; }

    cleona_video_config_t accepted;
    int32_t rc = wv_negotiate(cfg, CLEONA_VIDEO_WIN_MIN_BITRATE_KBPS, &accepted);
    if (rc != CLEONA_VIDEO_OK) { wv_write_open_error(out_negotiated, rc); return NULL; }

    wv_com_ensure();
    HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_LITE);
    if (FAILED(hr)) { wv_write_open_error(out_negotiated, CLEONA_VIDEO_ERR_BACKEND); return NULL; }

    cleona_video_session_t* s = (cleona_video_session_t*)calloc(1, sizeof(cleona_video_session_t));
    if (!s) { MFShutdown(); wv_write_open_error(out_negotiated, CLEONA_VIDEO_ERR_BACKEND); return NULL; }
    InitializeCriticalSection(&s->lock);
    s->state = ST_OPEN;
    s->cfg = accepted;
    s->capture_enabled = 1;
    s->awaiting_keyframe = 1;

    /* Device enumeration — "no capture path at all" is a property of the
     * device (ERR_UNSUPPORTED), verified by hand on this acceptance VM
     * (Get-PnpDevice -Class Camera: none). See BUILD_REQUEST_V1.16.md. */
    hr = wv_enum_capture_devices(&s->cap_activates, &s->cap_activate_count);
    if (FAILED(hr) || s->cap_activate_count == 0) {
        DeleteCriticalSection(&s->lock);
        free(s);
        MFShutdown();
        wv_write_open_error(out_negotiated, CLEONA_VIDEO_ERR_UNSUPPORTED);
        return NULL;
    }
    s->cap_activate_index = 0;

    UINT32 aw = 0, ah = 0, anum = 0, aden = 1;
    hr = wv_setup_capture(s, accepted.width, accepted.height, accepted.fps, &aw, &ah, &anum, &aden);
    if (FAILED(hr)) {
        for (UINT32 i = 0; i < s->cap_activate_count; i++) IMFActivate_Release(s->cap_activates[i]);
        CoTaskMemFree(s->cap_activates);
        DeleteCriticalSection(&s->lock);
        free(s);
        MFShutdown();
        wv_write_open_error(out_negotiated, CLEONA_VIDEO_ERR_BACKEND);
        return NULL;
    }
    s->cfg.width = (int32_t)aw;
    s->cfg.height = (int32_t)ah;
    s->cfg.fps = aden > 0 ? (int32_t)(anum / aden) : accepted.fps;
    if (s->cfg.fps <= 0) s->cfg.fps = accepted.fps;

    hr = wv_setup_encoder(s, aw, ah, anum, aden, s->cfg.target_bitrate_kbps,
                           s->cfg.keyframe_interval_frames);
    if (SUCCEEDED(hr)) hr = wv_setup_decoder(s, aw, ah);
    if (SUCCEEDED(hr)) hr = wv_d3d11_init(s);
    if (SUCCEEDED(hr)) hr = wv_ensure_texture(s, aw, ah);

    if (FAILED(hr)) {
        if (s->tex) ID3D11Texture2D_Release(s->tex);
        if (s->d3d_ctx) ID3D11DeviceContext_Release(s->d3d_ctx);
        if (s->d3d_device) ID3D11Device_Release(s->d3d_device);
        if (s->dec) IMFTransform_Release(s->dec);
        if (s->enc_codec_api) ICodecAPI_Release(s->enc_codec_api);
        if (s->enc) IMFTransform_Release(s->enc);
        wv_teardown_capture(s);
        for (UINT32 i = 0; i < s->cap_activate_count; i++) IMFActivate_Release(s->cap_activates[i]);
        CoTaskMemFree(s->cap_activates);
        DeleteCriticalSection(&s->lock);
        free(s);
        MFShutdown();
        wv_write_open_error(out_negotiated, CLEONA_VIDEO_ERR_BACKEND);
        return NULL;
    }

    s->ring_event = CreateEventW(NULL, FALSE, FALSE, NULL);
    s->reconfig.done_event = CreateEventW(NULL, FALSE, FALSE, NULL);

    if (out_negotiated) *out_negotiated = s->cfg;
    return s;
}

CLEONA_VIDEO_API int32_t cleona_video_reconfigure(cleona_video_session_t* s,
                                                   const cleona_video_config_t* cfg,
                                                   cleona_video_config_t* out_negotiated) {
    if (!s || !cfg) return CLEONA_VIDEO_ERR_INVALID;

    EnterCriticalSection(&s->lock);
    if (s->state == ST_CLOSED) { LeaveCriticalSection(&s->lock); return CLEONA_VIDEO_ERR_STATE; }
    int32_t min_bitrate = CLEONA_VIDEO_WIN_MIN_BITRATE_KBPS;
    int32_t running = s->running;
    LeaveCriticalSection(&s->lock);

    cleona_video_config_t accepted;
    int32_t rc = wv_negotiate(cfg, min_bitrate, &accepted);
    if (rc != CLEONA_VIDEO_OK) return rc; /* side-effect free (cleona_video.h) */

    if (!running) {
        /* Not started yet: no capture thread exists to hand this to. Apply
         * directly — the same objects reconfigure would touch on the
         * capture thread, just called from the caller's own thread since
         * nothing else can be racing them before start(). */
        int32_t arc = wv_apply_reconfig(s, &accepted);
        if (arc != CLEONA_VIDEO_OK) return arc;
        if (out_negotiated) *out_negotiated = s->cfg;
        return CLEONA_VIDEO_OK;
    }

    EnterCriticalSection(&s->lock);
    s->reconfig.cfg = accepted;
    s->reconfig.pending = 1;
    ResetEvent(s->reconfig.done_event);
    LeaveCriticalSection(&s->lock);

    DWORD w = WaitForSingleObject(s->reconfig.done_event, 5000);
    if (w != WAIT_OBJECT_0) return CLEONA_VIDEO_ERR_BACKEND;

    EnterCriticalSection(&s->lock);
    int32_t result = s->reconfig.result;
    cleona_video_config_t applied = s->reconfig.applied;
    LeaveCriticalSection(&s->lock);

    if (result == CLEONA_VIDEO_OK && out_negotiated) *out_negotiated = applied;
    return result;
}

CLEONA_VIDEO_API int32_t cleona_video_start(cleona_video_session_t* s) {
    if (!s) return CLEONA_VIDEO_ERR_INVALID;
    EnterCriticalSection(&s->lock);
    if (s->state != ST_OPEN) { LeaveCriticalSection(&s->lock); return CLEONA_VIDEO_ERR_STATE; }
    s->stop_event = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (!s->stop_event) { LeaveCriticalSection(&s->lock); return CLEONA_VIDEO_ERR_BACKEND; }
    s->state = ST_RUNNING;
    s->force_keyframe = 1;
    s->have_pts_base = 0;
    s->awaiting_keyframe = 1;
    LeaveCriticalSection(&s->lock);

    s->capenc_thread = CreateThread(NULL, 0, wv_capenc_thread_proc, s, 0, NULL);
    if (!s->capenc_thread) {
        EnterCriticalSection(&s->lock);
        s->state = ST_OPEN;
        LeaveCriticalSection(&s->lock);
        CloseHandle(s->stop_event);
        s->stop_event = NULL;
        return CLEONA_VIDEO_ERR_BACKEND;
    }
    return CLEONA_VIDEO_OK;
}

CLEONA_VIDEO_API void cleona_video_stop(cleona_video_session_t* s) {
    if (!s) return;
    EnterCriticalSection(&s->lock);
    if (s->state != ST_RUNNING) { LeaveCriticalSection(&s->lock); return; }
    s->state = ST_OPEN;
    HANDLE stop_event = s->stop_event;
    LeaveCriticalSection(&s->lock);

    if (stop_event) SetEvent(stop_event);
    if (s->capenc_thread) {
        WaitForSingleObject(s->capenc_thread, 3000);
        CloseHandle(s->capenc_thread);
        s->capenc_thread = NULL;
    }
    if (stop_event) { CloseHandle(stop_event); s->stop_event = NULL; }

    EnterCriticalSection(&s->lock);
    s->ring_head = s->ring_count = 0;
    s->awaiting_keyframe = 1; /* decoder keyframe state resets on stop (cleona_video.h) */
    LeaveCriticalSection(&s->lock);
    if (s->ring_event) SetEvent(s->ring_event); /* release any waiting reader */
}

CLEONA_VIDEO_API void cleona_video_close(cleona_video_session_t* s) {
    if (!s) return;
    cleona_video_stop(s);

    if (s->tex) { ID3D11Texture2D_Release(s->tex); s->tex = NULL; }
    if (s->d3d_ctx) { ID3D11DeviceContext_Release(s->d3d_ctx); s->d3d_ctx = NULL; }
    if (s->d3d_device) { ID3D11Device_Release(s->d3d_device); s->d3d_device = NULL; }
    if (s->dec) { IMFTransform_Release(s->dec); s->dec = NULL; }
    if (s->enc_codec_api) { ICodecAPI_Release(s->enc_codec_api); s->enc_codec_api = NULL; }
    if (s->enc) { IMFTransform_Release(s->enc); s->enc = NULL; }
    wv_teardown_capture(s);
    if (s->cap_activates) {
        for (UINT32 i = 0; i < s->cap_activate_count; i++) IMFActivate_Release(s->cap_activates[i]);
        CoTaskMemFree(s->cap_activates);
    }
    for (int i = 0; i < CLEONA_VIDEO_WIN_RING_FRAMES; i++) free(s->ring[i].buf);
    if (s->ring_event) CloseHandle(s->ring_event);
    if (s->reconfig.done_event) CloseHandle(s->reconfig.done_event);

    s->state = ST_CLOSED;
    DeleteCriticalSection(&s->lock);
    free(s);
    MFShutdown();
}

/* ==========================================================================
 * Data path
 * ========================================================================== */
CLEONA_VIDEO_API int32_t cleona_video_read_encoded(cleona_video_session_t* s,
                                                    uint8_t* buf, int32_t buf_cap,
                                                    int32_t* out_size, int32_t* out_flags,
                                                    int64_t* out_pts_us, int32_t timeout_ms) {
    if (!s || !buf || buf_cap <= 0 || !out_size || !out_flags || !out_pts_us) {
        return CLEONA_VIDEO_ERR_INVALID;
    }
    DWORD start_tick = GetTickCount();
    const int blocking = timeout_ms < 0;

    for (;;) {
        EnterCriticalSection(&s->lock);
        if (s->state != ST_RUNNING) { LeaveCriticalSection(&s->lock); return CLEONA_VIDEO_READ_CLOSED; }
        int32_t needed = 0;
        int r = wv_ring_pop_locked(s, buf, buf_cap, out_size, out_flags, out_pts_us, &needed);
        LeaveCriticalSection(&s->lock);
        if (r == 1) return CLEONA_VIDEO_READ_FRAME;
        if (r == -1) { *out_size = needed; return CLEONA_VIDEO_ERR_BUFFER_TOO_SMALL; }

        DWORD elapsed = GetTickCount() - start_tick;
        DWORD remaining = blocking ? INFINITE
                         : (elapsed >= (DWORD)timeout_ms ? 0 : (DWORD)timeout_ms - elapsed);
        if (!blocking && remaining == 0) return CLEONA_VIDEO_READ_TIMEOUT;
        WaitForSingleObject(s->ring_event, remaining == 0 ? 1 : remaining);
    }
}

CLEONA_VIDEO_API int32_t cleona_video_submit_encoded(cleona_video_session_t* s,
                                                      const uint8_t* data, int32_t size,
                                                      int32_t flags) {
    if (!s || !data || size <= 0) return CLEONA_VIDEO_ERR_INVALID;

    EnterCriticalSection(&s->lock);
    if (s->state != ST_RUNNING) { LeaveCriticalSection(&s->lock); return CLEONA_VIDEO_ERR_STATE; }
    IMFTransform* dec = s->dec;

    int32_t sc = wv_last_start_code(data, size);
    int is_idr = (sc >= 0 && sc + 5 <= size) ? ((data[sc + 4] & 0x1F) == 5) : wv_bitstream_has_idr(data, size);
    int claims_key = (flags & CLEONA_VIDEO_FLAG_KEYFRAME) != 0;
    if (claims_key != is_idr) {
        s->decode_failures++;
        LeaveCriticalSection(&s->lock);
        return CLEONA_VIDEO_ERR_DECODE; /* peer's flag contradicts its own bitstream */
    }
    if (s->awaiting_keyframe && !is_idr) {
        LeaveCriticalSection(&s->lock);
        return CLEONA_VIDEO_SUBMIT_AWAITING_KEYFRAME;
    }
    LeaveCriticalSection(&s->lock);

    IMFMediaBuffer* mb = NULL;
    HRESULT hr = MFCreateMemoryBuffer((DWORD)size, &mb);
    if (FAILED(hr)) return CLEONA_VIDEO_ERR_DECODE;
    BYTE* p = NULL;
    IMFMediaBuffer_Lock(mb, &p, NULL, NULL);
    memcpy(p, data, (size_t)size);
    IMFMediaBuffer_Unlock(mb);
    IMFMediaBuffer_SetCurrentLength(mb, (DWORD)size);

    IMFSample* sample = NULL;
    hr = MFCreateSample(&sample);
    if (SUCCEEDED(hr)) IMFSample_AddBuffer(sample, mb);
    IMFMediaBuffer_Release(mb);
    if (FAILED(hr)) { if (sample) IMFSample_Release(sample); return CLEONA_VIDEO_ERR_DECODE; }

    hr = IMFTransform_ProcessInput(dec, 0, sample, 0);
    IMFSample_Release(sample);
    if (FAILED(hr)) {
        EnterCriticalSection(&s->lock);
        s->decode_failures++;
        LeaveCriticalSection(&s->lock);
        return CLEONA_VIDEO_ERR_DECODE;
    }

    int accepted_ok = 1;
    for (;;) {
        MFT_OUTPUT_DATA_BUFFER odb;
        memset(&odb, 0, sizeof(odb));
        IMFSample* out_sample = NULL;
        if (!s->dec_out_provides_samples) {
            MFT_OUTPUT_STREAM_INFO osi;
            memset(&osi, 0, sizeof(osi));
            IMFTransform_GetOutputStreamInfo(dec, 0, &osi);
            IMFMediaBuffer* obuf = NULL;
            if (FAILED(MFCreateMemoryBuffer(osi.cbSize > 0 ? osi.cbSize : (1 << 21), &obuf))) break;
            if (FAILED(MFCreateSample(&out_sample))) { IMFMediaBuffer_Release(obuf); break; }
            IMFSample_AddBuffer(out_sample, obuf);
            IMFMediaBuffer_Release(obuf);
            odb.pSample = out_sample;
        }
        odb.dwStreamID = 0;
        DWORD status = 0;
        HRESULT phr = IMFTransform_ProcessOutput(dec, 0, 1, &odb, &status);
        if (odb.pEvents) IMFCollection_Release(odb.pEvents);
        if (phr == MF_E_TRANSFORM_NEED_MORE_INPUT) { if (out_sample) IMFSample_Release(out_sample); break; }
        if (phr == MF_E_TRANSFORM_STREAM_CHANGE) {
            if (out_sample) IMFSample_Release(out_sample);
            if (odb.pSample) IMFSample_Release(odb.pSample);
            continue;
        }
        if (FAILED(phr)) { if (out_sample) IMFSample_Release(out_sample); accepted_ok = 0; break; }

        IMFSample* got = s->dec_out_provides_samples ? odb.pSample : out_sample;
        if (got) {
            IMFMediaBuffer* gb = NULL;
            if (SUCCEEDED(IMFSample_ConvertToContiguousBuffer(got, &gb)) && gb) {
                BYTE* gp = NULL; DWORD glen = 0;
                if (SUCCEEDED(IMFMediaBuffer_Lock(gb, &gp, NULL, &glen))) {
                    EnterCriticalSection(&s->lock);
                    UINT32 tw = (UINT32)s->cfg.width, th = (UINT32)s->cfg.height;
                    wv_ensure_texture(s, tw, th);
                    if (s->tex) {
                        UINT32 y_stride = tw;   /* NV12 tightly packed, as requested from the decoder */
                        wv_nv12_to_bgra_upload(s, gp, tw, th, y_stride, y_stride);
                    }
                    LeaveCriticalSection(&s->lock);
                    IMFMediaBuffer_Unlock(gb);
                }
                IMFMediaBuffer_Release(gb);
            }
            IMFSample_Release(got);
        }
    }

    EnterCriticalSection(&s->lock);
    if (accepted_ok) {
        s->awaiting_keyframe = 0;
        s->frames_decoded++;
    } else {
        s->decode_failures++;
    }
    LeaveCriticalSection(&s->lock);
    return accepted_ok ? CLEONA_VIDEO_SUBMIT_ACCEPTED : CLEONA_VIDEO_ERR_DECODE;
}

CLEONA_VIDEO_API int32_t cleona_video_get_texture_id(cleona_video_session_t* s, int64_t* out_id) {
    if (!s || !out_id) return CLEONA_VIDEO_ERR_INVALID;
    EnterCriticalSection(&s->lock);
    if (s->state != ST_RUNNING) { LeaveCriticalSection(&s->lock); return CLEONA_VIDEO_ERR_STATE; }
    if (!s->tex) { LeaveCriticalSection(&s->lock); return CLEONA_VIDEO_ERR_UNSUPPORTED; }
    /* A DXGI shared NT handle, not a raw pointer: it survives being handed to
     * a different D3D11 device via IDXGIResource1::CreateSharedHandle /
     * OpenSharedResource1, which is the realistic cross-process shape on
     * Windows Desktop (daemon + GUI as separate processes, project structure
     * "Windows Desktop (Daemon + GUI via IPC/TCP...)"). Wiring that handle
     * through to the Flutter engine's external-texture registry is V2.3's
     * job (lib/main.dart video factory, out of this package's ownership,
     * SPEC §7 "V2.3 — Video-Integration"); this ABI only has to hand back a
     * stable, meaningful id while running, which it does. */
    IDXGIResource1* dxgi_res = NULL;
    HANDLE shared = NULL;
    if (SUCCEEDED(ID3D11Texture2D_QueryInterface(s->tex, &IID_IDXGIResource1, (void**)&dxgi_res)) && dxgi_res) {
        IDXGIResource1_CreateSharedHandle(dxgi_res, NULL, DXGI_SHARED_RESOURCE_READ, NULL, &shared);
        IDXGIResource1_Release(dxgi_res);
    }
    LeaveCriticalSection(&s->lock);
    if (!shared) return CLEONA_VIDEO_ERR_UNSUPPORTED;
    *out_id = (int64_t)(intptr_t)shared;
    return CLEONA_VIDEO_OK;
}

CLEONA_VIDEO_API int32_t cleona_video_request_keyframe(cleona_video_session_t* s) {
    if (!s) return CLEONA_VIDEO_ERR_INVALID;
    EnterCriticalSection(&s->lock);
    if (s->state != ST_RUNNING) { LeaveCriticalSection(&s->lock); return CLEONA_VIDEO_ERR_STATE; }
    s->force_keyframe = 1;
    LeaveCriticalSection(&s->lock);
    return CLEONA_VIDEO_OK;
}

CLEONA_VIDEO_API void cleona_video_set_capture_enabled(cleona_video_session_t* s, int32_t on) {
    if (!s) return;
    EnterCriticalSection(&s->lock);
    int32_t want = on ? 1 : 0;
    if (want && !s->capture_enabled) {
        /* Peer's decoder has been starved; a P-frame now would be
         * undecodable there — unconditional, not a heuristic (I12). */
        s->force_keyframe = 1;
    }
    s->capture_enabled = want;
    LeaveCriticalSection(&s->lock);
}

CLEONA_VIDEO_API int32_t cleona_video_switch_camera(cleona_video_session_t* s) {
    if (!s) return CLEONA_VIDEO_ERR_INVALID;
    EnterCriticalSection(&s->lock);
    if (s->state != ST_RUNNING) { LeaveCriticalSection(&s->lock); return CLEONA_VIDEO_ERR_STATE; }
    if (s->cap_activate_count < 2) { LeaveCriticalSection(&s->lock); return CLEONA_VIDEO_ERR_UNSUPPORTED; }
    UINT32 next = (s->cap_activate_index + 1) % s->cap_activate_count;
    LeaveCriticalSection(&s->lock);

    UINT32 old_index = s->cap_activate_index;
    wv_teardown_capture(s);
    s->cap_activate_index = next;
    UINT32 aw = 0, ah = 0, anum = 0, aden = 1;
    HRESULT hr = wv_setup_capture(s, s->cfg.width, s->cfg.height, s->cfg.fps, &aw, &ah, &anum, &aden);
    if (FAILED(hr) || (int32_t)aw != s->cfg.width || (int32_t)ah != s->cfg.height) {
        /* Cannot deliver the negotiated format on the new camera: stay on
         * the current one (cleona_video.h). */
        wv_teardown_capture(s);
        s->cap_activate_index = old_index;
        UINT32 rw = 0, rh = 0, rnum = 0, rden = 1;
        wv_setup_capture(s, s->cfg.width, s->cfg.height, s->cfg.fps, &rw, &rh, &rnum, &rden);
        return CLEONA_VIDEO_ERR_UNSUPPORTED;
    }
    EnterCriticalSection(&s->lock);
    s->force_keyframe = 1;
    LeaveCriticalSection(&s->lock);
    return CLEONA_VIDEO_OK;
}

CLEONA_VIDEO_API void cleona_video_get_report(cleona_video_session_t* s, cleona_video_report_t* out) {
    if (!out) return;
    if (!s) {
        memset(out, 0, sizeof(*out));
        out->hardware_encode = CLEONA_VIDEO_HW_NOT_DETERMINABLE;
        out->hardware_decode = CLEONA_VIDEO_HW_NOT_DETERMINABLE;
        return;
    }
    EnterCriticalSection(&s->lock);
    out->codec_in_use      = s->cfg.codec;
    out->hardware_encode   = s->enc ? (s->enc_is_hw ? CLEONA_VIDEO_HW_YES : CLEONA_VIDEO_HW_NO)
                                     : CLEONA_VIDEO_HW_NOT_DETERMINABLE;
    out->hardware_decode   = s->dec ? (s->dec_is_hw ? CLEONA_VIDEO_HW_YES : CLEONA_VIDEO_HW_NO)
                                     : CLEONA_VIDEO_HW_NOT_DETERMINABLE;
    out->negotiated_width  = s->cfg.width;
    out->negotiated_height = s->cfg.height;
    out->negotiated_fps    = s->cfg.fps;
    out->capture_backend   = CLEONA_VIDEO_BACKEND_WIN_MF_SOURCEREADER;
    out->encode_backend    = CLEONA_VIDEO_BACKEND_WIN_MF_TRANSFORM;
    out->frames_captured         = s->frames_captured;
    out->frames_encoded          = s->frames_encoded;
    out->frames_dropped_oversize = s->frames_dropped_oversize;
    out->frames_decoded          = s->frames_decoded;
    out->decode_failures         = s->decode_failures;
    LeaveCriticalSection(&s->lock);
}

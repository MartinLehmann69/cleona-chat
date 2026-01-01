/* cleona_video_apple.m — the Apple backend of the cleona_video ABI.
 *
 * Work package: docs/SPEC_VOICE_VIDEO_REWORK.md V1.15.
 * Contract:     native/cleona_video/cleona_video.h (frozen).
 * Architecture: Cleona_Chat_Architecture_v3_0.md §10.6 (normative).
 *
 * ---------------------------------------------------------------------------
 * WHAT THIS FILE IS AND IS NOT
 * ---------------------------------------------------------------------------
 * A self-contained Objective-C implementation using Apple's native frameworks:
 *
 *   AVFoundation   — camera capture (AVCaptureSession + AVCaptureVideoDataOutput)
 *   VideoToolbox   — hardware H.264 encode (VTCompressionSession) and decode
 *                    (VTDecompressionSession)
 *   CoreMedia      — CMSampleBuffer / CMFormatDescription / CMTime
 *   CoreVideo      — CVPixelBuffer / CVPixelBufferPool
 *
 * Unlike Android (V1.14), all platform APIs needed here have C or Objective-C
 * bindings available directly — no JNI facade, no Kotlin counterpart. The
 * texture id path still requires Flutter's TextureRegistry, which is the one
 * piece not available below this ABI; see cleona_video_get_texture_id().
 *
 * ---------------------------------------------------------------------------
 * iOS vs macOS
 * ---------------------------------------------------------------------------
 * Both platforms share the same VideoToolbox and AVFoundation APIs. Differences:
 *
 *   - Camera device discovery: iOS uses AVCaptureDeviceDiscoverySession with
 *     .builtInWideAngleCamera; macOS uses the same discovery API but camera
 *     positions (.front/.back) are not meaningful on most Macs.
 *   - Torch / flash: not used here (video calls, not photography).
 *   - Preview layer: not used (pixels never cross the ABI — I10).
 *
 * Conditional compilation is limited to camera enumeration. Everything else
 * compiles identically on both targets.
 *
 * ---------------------------------------------------------------------------
 * NO PIXELS CROSS THIS FILE (I10)
 * ---------------------------------------------------------------------------
 * The capture callback receives CVPixelBuffers and feeds them directly to
 * VTCompressionSession. The decoder's output callback receives CVPixelBuffers
 * and (when a texture path exists) pushes them to a CVMetalTextureCache or
 * IOSurface-backed buffer for Flutter's external texture. Dart never sees a
 * pixel; only the encoded bitstream (Annex-B H.264) and a texture id cross.
 *
 * ---------------------------------------------------------------------------
 * ANNEX-B / AVCC CONVERSION
 * ---------------------------------------------------------------------------
 * VideoToolbox produces AVCC-format output (4-byte length-prefixed NAL units).
 * The ABI's wire format is Annex-B (00 00 00 01 start codes). This file
 * converts in both directions:
 *   - Encode output (AVCC) → Annex-B before handing to cleona_video_read_encoded
 *   - Decode input (Annex-B from peer) → AVCC before feeding VTDecompressionSession
 *
 * ---------------------------------------------------------------------------
 * THREADING
 * ---------------------------------------------------------------------------
 * AVCaptureVideoDataOutput delivers frames on its own serial queue.
 * VTCompressionSession's output callback fires on an internal VideoToolbox
 * thread. VTDecompressionSession's output callback fires on the calling thread
 * or an internal thread depending on the session configuration.
 *
 * All state is protected by pthread_mutex_t. The session struct owns a single
 * mutex; every ABI entry point acquires it. The capture callback and
 * compression output callback acquire it to deposit frames.
 */

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>

#include <pthread.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "../cleona_video.h"

/* ---- compile-time ABI checks (same rationale as Android backend) ---- */
#define CFG_INTS 7
_Static_assert(sizeof(cleona_video_config_t) == CFG_INTS * sizeof(int32_t),
               "cleona_video_config_t gained/lost a field");

#define REPORT_INTS  8
#define REPORT_LONGS 5
_Static_assert(offsetof(cleona_video_report_t, encode_backend) ==
                   (REPORT_INTS - 1) * (int)sizeof(int32_t),
               "REPORT_INTS no longer matches the int32 block of "
               "cleona_video_report_t");
_Static_assert(offsetof(cleona_video_report_t, frames_captured) ==
                   ((REPORT_INTS * (int)sizeof(int32_t) + 7) / 8) * 8,
               "cleona_video_report_t gained an int32 field that "
               "REPORT_INTS does not account for");

/* ---- lifecycle states ---- */
#define ST_OPEN    0
#define ST_RUNNING 1
#define ST_CLOSED  2

/* ---- internal constants ---- */

/* Minimum bitrate the backend will accept (kbps). Below this, even the
 * smallest keyframe cannot be produced reliably by VideoToolbox. */
#define APPLE_MIN_BITRATE_KBPS  50

/* Keyframe-to-delta size ratio estimate. VideoToolbox IDR frames with
 * SPS/PPS are typically 3-5x a P-frame. Conservative estimate for the
 * negotiation budget. */
#define APPLE_KEYFRAME_FACTOR   4

/* Maximum capture dimensions. VideoToolbox H.264 Baseline supports up to
 * 1920x1080 in hardware on all modern Apple SoCs. Clamped down, never up. */
#define APPLE_MAX_WIDTH   1920
#define APPLE_MAX_HEIGHT  1080
#define APPLE_MAX_FPS     60

/* Smallest Annex-B frame we can construct: 4 (start code) + 1 (NAL header).
 * Real frames are always larger; this is the floor for the negotiation. */
#define APPLE_MIN_FRAME_BYTES 64

/* ---- forward declarations ---- */
@class CleonaVideoCaptureDelegate;

/* ==========================================================================
 * Session structure
 * ========================================================================== */

struct cleona_video_session {
    pthread_mutex_t lock;
    pthread_cond_t  frame_cond;  /* signalled when a frame is deposited or session stops */

    int32_t state;
    cleona_video_config_t cfg;   /* negotiated, authoritative */

    /* ----- capture ----- */
    AVCaptureSession            *captureSession;
    AVCaptureDevice             *captureDevice;
    AVCaptureDeviceInput        *captureInput;
    AVCaptureVideoDataOutput    *captureOutput;
    CleonaVideoCaptureDelegate  *captureDelegate;
    dispatch_queue_t             captureQueue;

    NSArray<AVCaptureDevice *>  *cameras;
    int32_t                      cameraIndex;

    int32_t capture_enabled;

    /* ----- encode ----- */
    VTCompressionSessionRef compressionSession;
    int32_t force_keyframe;
    int32_t hw_encode_verified;   /* CLEONA_VIDEO_HW_* */

    /* Pending encoded frame (Annex-B). Protected by lock. */
    uint8_t *pending_buf;
    int32_t  pending_cap;
    int32_t  pending_size;
    int32_t  pending_flags;
    int64_t  pending_pts_us;
    int32_t  has_pending;

    /* Presentation clock — accumulated, not computed from index * 1/fps,
     * so fps changes at reconfigure do not cause pts to jump backwards
     * (Erratum 1). */
    int64_t pts_next_us;
    int64_t frame_index;

    /* ----- decode ----- */
    VTDecompressionSessionRef decompressionSession;
    CMVideoFormatDescriptionRef decoderFormatDesc;
    int32_t awaiting_keyframe;
    int32_t hw_decode_verified;

    /* Decoded CVPixelBuffer for texture path (latest decoded frame). */
    CVPixelBufferRef decodedPixelBuffer;

    /* Texture id. On Apple, the actual Flutter texture registration happens
     * outside this ABI (requires FlutterTextureRegistry), so we store a
     * placeholder until wired up. A real integration sets this via a
     * platform-channel callback from Dart. */
    int64_t texture_id;
    int32_t texture_id_valid;

    /* ----- counters (monotonic, never reset) ----- */
    int64_t frames_captured;
    int64_t frames_encoded;
    int64_t frames_dropped_oversize;
    int64_t frames_decoded;
    int64_t decode_failures;
};

/* ==========================================================================
 * AVCaptureVideoDataOutput delegate
 * ========================================================================== */

@interface CleonaVideoCaptureDelegate : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, assign) cleona_video_session_t *session;
@end

@implementation CleonaVideoCaptureDelegate

- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    (void)output;
    (void)connection;

    cleona_video_session_t *s = self.session;
    if (!s) return;

    pthread_mutex_lock(&s->lock);
    if (s->state != ST_RUNNING || !s->capture_enabled || !s->compressionSession) {
        pthread_mutex_unlock(&s->lock);
        return;
    }
    s->frames_captured++;

    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!imageBuffer) {
        pthread_mutex_unlock(&s->lock);
        return;
    }

    /* Build frame properties — force keyframe if requested. */
    NSDictionary *frameProps = nil;
    if (s->force_keyframe ||
        s->frame_index == 0 ||
        (s->cfg.keyframe_interval_frames > 0 &&
         (s->frame_index % s->cfg.keyframe_interval_frames) == 0)) {
        frameProps = @{
            (__bridge NSString *)kVTEncodeFrameOptionKey_ForceKeyFrame: @YES
        };
        s->force_keyframe = 0;
    }

    /* Presentation timestamp — accumulated to survive fps changes. */
    CMTime pts = CMTimeMake(s->pts_next_us, 1000000);
    CMTime dur = CMTimeMake(1000000 / s->cfg.fps, 1000000);
    s->pts_next_us += 1000000LL / s->cfg.fps;
    s->frame_index++;

    VTCompressionSessionRef comp = s->compressionSession;
    pthread_mutex_unlock(&s->lock);

    /* VTCompressionSessionEncodeFrame is thread-safe on its own session.
     * We do NOT hold the lock during encode — the output callback will
     * acquire it to deposit the result. */
    OSStatus status = VTCompressionSessionEncodeFrame(
        comp, imageBuffer, pts, dur,
        (__bridge CFDictionaryRef)frameProps,
        NULL, NULL);

    if (status != noErr) {
        /* Encode failed — counted as encoded but dropped (the camera
         * delivered a frame, the encoder refused it). */
    }
}

- (void)captureOutput:(AVCaptureOutput *)output
  didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    /* Dropped frames are expected under load. Not counted as
     * frames_captured — the camera never delivered them to us. */
    (void)output;
    (void)sampleBuffer;
    (void)connection;
}

@end

/* ==========================================================================
 * Annex-B / AVCC conversion helpers
 * ========================================================================== */

/* Convert AVCC (4-byte length prefix) NAL units to Annex-B (00 00 00 01).
 * Returns the number of bytes written, or -1 on error.
 * SPS and PPS from the format description are prepended for keyframes. */
static int32_t avcc_to_annexb(const uint8_t *avcc, int32_t avcc_len,
                              CMFormatDescriptionRef fmt, int32_t is_keyframe,
                              uint8_t *out, int32_t out_cap) {
    int32_t pos = 0;

    /* For keyframes, prepend SPS and PPS from the format description. */
    if (is_keyframe && fmt) {
        size_t paramCount = 0;
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            fmt, 0, NULL, NULL, &paramCount, NULL);

        for (size_t i = 0; i < paramCount; i++) {
            const uint8_t *paramData = NULL;
            size_t paramSize = 0;
            OSStatus st = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                fmt, i, &paramData, &paramSize, NULL, NULL);
            if (st != noErr || !paramData) continue;

            if (pos + 4 + (int32_t)paramSize > out_cap) return -1;
            out[pos++] = 0x00;
            out[pos++] = 0x00;
            out[pos++] = 0x00;
            out[pos++] = 0x01;
            memcpy(out + pos, paramData, paramSize);
            pos += (int32_t)paramSize;
        }
    }

    /* Convert each AVCC NAL unit. AVCC uses a 4-byte big-endian length
     * prefix; we replace each with an Annex-B start code. */
    int32_t offset = 0;
    while (offset + 4 <= avcc_len) {
        uint32_t nal_len = ((uint32_t)avcc[offset] << 24) |
                           ((uint32_t)avcc[offset + 1] << 16) |
                           ((uint32_t)avcc[offset + 2] << 8) |
                           ((uint32_t)avcc[offset + 3]);
        offset += 4;

        if ((int32_t)nal_len <= 0 || offset + (int32_t)nal_len > avcc_len) {
            return -1;  /* malformed */
        }

        if (pos + 4 + (int32_t)nal_len > out_cap) return -1;
        out[pos++] = 0x00;
        out[pos++] = 0x00;
        out[pos++] = 0x00;
        out[pos++] = 0x01;
        memcpy(out + pos, avcc + offset, nal_len);
        pos += (int32_t)nal_len;
        offset += (int32_t)nal_len;
    }

    return pos;
}

/* Convert Annex-B (00 00 00 01 start codes) to AVCC (4-byte length prefix).
 * Returns the number of bytes written, or -1 on error.
 * Also extracts SPS and PPS NAL units if out_sps/out_pps are non-NULL. */
static int32_t annexb_to_avcc(const uint8_t *annexb, int32_t annexb_len,
                              uint8_t *out, int32_t out_cap,
                              const uint8_t **out_sps, size_t *out_sps_size,
                              const uint8_t **out_pps, size_t *out_pps_size) {
    if (out_sps) { *out_sps = NULL; *out_sps_size = 0; }
    if (out_pps) { *out_pps = NULL; *out_pps_size = 0; }

    int32_t pos = 0;

    /* Find all NAL unit boundaries (00 00 00 01 or 00 00 01). */
    int32_t i = 0;
    while (i < annexb_len) {
        /* Skip to the next start code. */
        int32_t sc_start = -1;
        int32_t sc_len = 0;
        for (int32_t j = i; j + 3 <= annexb_len; j++) {
            if (annexb[j] == 0x00 && annexb[j + 1] == 0x00) {
                if (j + 3 < annexb_len &&
                    annexb[j + 2] == 0x00 && annexb[j + 3] == 0x01) {
                    sc_start = j;
                    sc_len = 4;
                    break;
                } else if (annexb[j + 2] == 0x01) {
                    sc_start = j;
                    sc_len = 3;
                    break;
                }
            }
        }
        if (sc_start < 0) break;

        int32_t nal_start = sc_start + sc_len;

        /* Find the end of this NAL (next start code, or end of data). */
        int32_t nal_end = annexb_len;
        for (int32_t j = nal_start; j + 3 <= annexb_len; j++) {
            if (annexb[j] == 0x00 && annexb[j + 1] == 0x00) {
                if ((j + 3 < annexb_len && annexb[j + 2] == 0x00 && annexb[j + 3] == 0x01) ||
                    annexb[j + 2] == 0x01) {
                    nal_end = j;
                    break;
                }
            }
        }

        int32_t nal_size = nal_end - nal_start;
        if (nal_size <= 0) {
            i = nal_start;
            continue;
        }

        uint8_t nal_type = annexb[nal_start] & 0x1F;

        /* Extract SPS (type 7) and PPS (type 8) for format description. */
        if (out_sps && nal_type == 7 && *out_sps == NULL) {
            *out_sps = annexb + nal_start;
            *out_sps_size = (size_t)nal_size;
        }
        if (out_pps && nal_type == 8 && *out_pps == NULL) {
            *out_pps = annexb + nal_start;
            *out_pps_size = (size_t)nal_size;
        }

        /* Skip SPS/PPS in the AVCC output — they are conveyed via the
         * CMFormatDescription, not inline. But include all other NAL types
         * (IDR slice, non-IDR slice, SEI, etc.). */
        if (nal_type != 7 && nal_type != 8) {
            if (pos + 4 + nal_size > out_cap) return -1;
            out[pos++] = (uint8_t)((nal_size >> 24) & 0xFF);
            out[pos++] = (uint8_t)((nal_size >> 16) & 0xFF);
            out[pos++] = (uint8_t)((nal_size >> 8) & 0xFF);
            out[pos++] = (uint8_t)(nal_size & 0xFF);
            memcpy(out + pos, annexb + nal_start, (size_t)nal_size);
            pos += nal_size;
        }

        i = nal_end;
    }

    return pos;
}

/* ==========================================================================
 * VTCompressionSession output callback
 * ========================================================================== */

static void compression_output_callback(void *outputCallbackRefCon,
                                         void *sourceFrameRefCon,
                                         OSStatus status,
                                         VTEncodeInfoFlags infoFlags,
                                         CMSampleBufferRef sampleBuffer) {
    (void)sourceFrameRefCon;
    (void)infoFlags;

    cleona_video_session_t *s = (cleona_video_session_t *)outputCallbackRefCon;
    if (!s || status != noErr || !sampleBuffer) return;

    /* Check if this is a keyframe. */
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, false);
    int32_t is_keyframe = 0;
    if (attachments && CFArrayGetCount(attachments) > 0) {
        CFDictionaryRef dict = CFArrayGetValueAtIndex(attachments, 0);
        CFBooleanRef notSync = NULL;
        if (dict) {
            notSync = CFDictionaryGetValue(dict, kCMSampleAttachmentKey_NotSync);
        }
        is_keyframe = (!notSync || !CFBooleanGetValue(notSync)) ? 1 : 0;
    }

    /* Get the encoded data block. */
    CMBlockBufferRef blockBuf = CMSampleBufferGetDataBuffer(sampleBuffer);
    if (!blockBuf) return;

    size_t totalLen = 0;
    char *dataPtr = NULL;
    OSStatus bst = CMBlockBufferGetDataPointer(blockBuf, 0, NULL, &totalLen, &dataPtr);
    if (bst != noErr || !dataPtr || totalLen == 0) return;

    /* Get the format description for SPS/PPS extraction on keyframes. */
    CMFormatDescriptionRef fmt = CMSampleBufferGetFormatDescription(sampleBuffer);

    /* Get the presentation timestamp. */
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    int64_t pts_us = (int64_t)(CMTimeGetSeconds(pts) * 1000000.0);

    /* Convert AVCC to Annex-B. Worst case: every 4-byte prefix stays 4 bytes,
     * plus SPS+PPS overhead for keyframes (~64 bytes typically). */
    int32_t conv_cap = (int32_t)totalLen + 256;
    uint8_t *conv_buf = (uint8_t *)malloc((size_t)conv_cap);
    if (!conv_buf) return;

    int32_t annexb_size = avcc_to_annexb(
        (const uint8_t *)dataPtr, (int32_t)totalLen,
        fmt, is_keyframe, conv_buf, conv_cap);

    if (annexb_size <= 0) {
        free(conv_buf);
        return;
    }

    pthread_mutex_lock(&s->lock);

    s->frames_encoded++;

    /* I9 backstop: drop frames exceeding the ceiling. */
    if (annexb_size > s->cfg.max_frame_bytes) {
        s->frames_dropped_oversize++;
        pthread_mutex_unlock(&s->lock);
        free(conv_buf);
        return;
    }

    /* Deposit the frame. If a previous frame is still pending, it is replaced
     * (latest frame wins — there is no queue, just one slot). */
    if (s->pending_cap < annexb_size) {
        uint8_t *nb = (uint8_t *)realloc(s->pending_buf, (size_t)annexb_size);
        if (!nb) {
            pthread_mutex_unlock(&s->lock);
            free(conv_buf);
            return;
        }
        s->pending_buf = nb;
        s->pending_cap = annexb_size;
    }
    memcpy(s->pending_buf, conv_buf, (size_t)annexb_size);
    s->pending_size = annexb_size;
    s->pending_flags = is_keyframe ? CLEONA_VIDEO_FLAG_KEYFRAME : 0;
    s->pending_pts_us = pts_us;
    s->has_pending = 1;

    pthread_cond_signal(&s->frame_cond);
    pthread_mutex_unlock(&s->lock);

    free(conv_buf);
}

/* ==========================================================================
 * VTDecompressionSession output callback
 * ========================================================================== */

static void decompression_output_callback(void *decompressionOutputRefCon,
                                           void *sourceFrameRefCon,
                                           OSStatus status,
                                           VTDecodeInfoFlags infoFlags,
                                           CVImageBufferRef imageBuffer,
                                           CMTime presentationTimeStamp,
                                           CMTime presentationDuration) {
    (void)sourceFrameRefCon;
    (void)infoFlags;
    (void)presentationTimeStamp;
    (void)presentationDuration;

    cleona_video_session_t *s = (cleona_video_session_t *)decompressionOutputRefCon;
    if (!s || status != noErr || !imageBuffer) return;

    pthread_mutex_lock(&s->lock);
    /* Replace the latest decoded pixel buffer. */
    if (s->decodedPixelBuffer) {
        CVPixelBufferRelease(s->decodedPixelBuffer);
    }
    s->decodedPixelBuffer = CVPixelBufferRetain(imageBuffer);
    s->frames_decoded++;
    pthread_mutex_unlock(&s->lock);
}

/* ==========================================================================
 * Camera enumeration
 * ========================================================================== */

static NSArray<AVCaptureDevice *> *enumerate_cameras(void) {
    NSMutableArray<AVCaptureDevice *> *result = [NSMutableArray array];

#if TARGET_OS_IPHONE
    /* iOS: enumerate front and back cameras. */
    AVCaptureDeviceDiscoverySession *discovery =
        [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:
            @[AVCaptureDeviceTypeBuiltInWideAngleCamera]
                                        mediaType:AVMediaTypeVideo
                                        position:AVCaptureDevicePositionUnspecified];
    if (discovery) {
        /* Sort: back camera first, then front. */
        for (AVCaptureDevice *dev in discovery.devices) {
            if (dev.position == AVCaptureDevicePositionBack) {
                [result insertObject:dev atIndex:0];
            } else {
                [result addObject:dev];
            }
        }
    }
#else
    /* macOS: enumerate all video devices. AVCaptureDeviceTypeExternalUnknown was
     * deprecated in macOS 14 / iOS 17 in favour of AVCaptureDeviceTypeExternal.
     * Use the newer symbol where available; fall back to the deprecated one for
     * pre-14 SDK builds. */
    NSArray *deviceTypes;
    if (@available(macOS 14.0, *)) {
        deviceTypes = @[AVCaptureDeviceTypeBuiltInWideAngleCamera,
                        AVCaptureDeviceTypeExternal];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        deviceTypes = @[AVCaptureDeviceTypeBuiltInWideAngleCamera,
                        AVCaptureDeviceTypeExternalUnknown];
#pragma clang diagnostic pop
    }
    AVCaptureDeviceDiscoverySession *discovery =
        [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:deviceTypes
                                        mediaType:AVMediaTypeVideo
                                        position:AVCaptureDevicePositionUnspecified];
    if (discovery) {
        [result addObjectsFromArray:discovery.devices];
    }
#endif

    /* If discovery yielded nothing, try the default video device. */
    if (result.count == 0) {
        AVCaptureDevice *def = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if (def) [result addObject:def];
    }

    return [result copy];
}

/* ==========================================================================
 * VTCompressionSession creation helper
 * ========================================================================== */

static VTCompressionSessionRef create_compression_session(
    cleona_video_session_t *s,
    const cleona_video_config_t *cfg) {

    VTCompressionSessionRef session = NULL;

    /* Prefer hardware encoder. */
    CFMutableDictionaryRef encoderSpec =
        CFDictionaryCreateMutable(NULL, 0,
                                  &kCFTypeDictionaryKeyCallBacks,
                                  &kCFTypeDictionaryValueCallBacks);
#if !TARGET_OS_SIMULATOR
    /* On simulator builds there is no hardware encoder. */
    CFDictionarySetValue(encoderSpec,
        kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder,
        kCFBooleanTrue);
#endif

    /* Source pixel format: 420v (kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
     * is what AVCaptureVideoDataOutput delivers by default on Apple platforms. */
    CFMutableDictionaryRef sourceAttrs =
        CFDictionaryCreateMutable(NULL, 0,
                                  &kCFTypeDictionaryKeyCallBacks,
                                  &kCFTypeDictionaryValueCallBacks);
    int32_t pixFmt = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
    CFNumberRef pixFmtRef = CFNumberCreate(NULL, kCFNumberSInt32Type, &pixFmt);
    CFDictionarySetValue(sourceAttrs,
        kCVPixelBufferPixelFormatTypeKey, pixFmtRef);
    CFRelease(pixFmtRef);

    OSStatus status = VTCompressionSessionCreate(
        NULL,                           /* allocator */
        cfg->width, cfg->height,
        kCMVideoCodecType_H264,
        encoderSpec,
        sourceAttrs,
        NULL,                           /* compressedDataAllocator */
        compression_output_callback,
        s,                              /* outputCallbackRefCon */
        &session);

    CFRelease(encoderSpec);
    CFRelease(sourceAttrs);

    if (status != noErr || !session) return NULL;

    /* Set encoder properties. */

    /* H.264 Baseline Profile for maximum compatibility. */
    VTSessionSetProperty(session,
        kVTCompressionPropertyKey_ProfileLevel,
        kVTProfileLevel_H264_Baseline_AutoLevel);

    /* Real-time encoding. */
    VTSessionSetProperty(session,
        kVTCompressionPropertyKey_RealTime,
        kCFBooleanTrue);

    /* Average bitrate. */
    int32_t bps = cfg->target_bitrate_kbps * 1000;
    CFNumberRef bitrateRef = CFNumberCreate(NULL, kCFNumberSInt32Type, &bps);
    VTSessionSetProperty(session,
        kVTCompressionPropertyKey_AverageBitRate, bitrateRef);
    CFRelease(bitrateRef);

    /* Data rate limits — enforce I9 max_frame_bytes.
     * DataRateLimits takes an array of [bytes, seconds] pairs.
     * We limit to max_frame_bytes per frame interval. */
    double frameDuration = 1.0 / cfg->fps;
    CFNumberRef limitBytes = CFNumberCreate(NULL, kCFNumberSInt32Type,
                                            &cfg->max_frame_bytes);
    CFNumberRef limitSecs = CFNumberCreate(NULL, kCFNumberFloat64Type,
                                           &frameDuration);
    CFNumberRef limits[] = { limitBytes, limitSecs };
    CFArrayRef limitsArray = CFArrayCreate(NULL, (const void **)limits, 2,
                                           &kCFTypeArrayCallBacks);
    VTSessionSetProperty(session,
        kVTCompressionPropertyKey_DataRateLimits, limitsArray);
    CFRelease(limitBytes);
    CFRelease(limitSecs);
    CFRelease(limitsArray);

    /* Max keyframe interval. */
    int32_t kfInterval = cfg->keyframe_interval_frames > 0
        ? cfg->keyframe_interval_frames : cfg->fps * 2;
    CFNumberRef kfRef = CFNumberCreate(NULL, kCFNumberSInt32Type, &kfInterval);
    VTSessionSetProperty(session,
        kVTCompressionPropertyKey_MaxKeyFrameInterval, kfRef);
    CFRelease(kfRef);

    /* Allow frame reordering OFF — Baseline has no B-frames. */
    VTSessionSetProperty(session,
        kVTCompressionPropertyKey_AllowFrameReordering,
        kCFBooleanFalse);

    /* Prepare to encode. */
    status = VTCompressionSessionPrepareToEncodeFrames(session);
    if (status != noErr) {
        VTCompressionSessionInvalidate(session);
        CFRelease(session);
        return NULL;
    }

    return session;
}

/* ==========================================================================
 * Hardware acceleration query (I11)
 * ========================================================================== */

/* Query whether the compression session is using hardware acceleration.
 * Returns CLEONA_VIDEO_HW_YES, HW_NO, or HW_NOT_DETERMINABLE. */
static int32_t query_hw_encode(VTCompressionSessionRef session) {
    if (!session) return CLEONA_VIDEO_HW_NOT_DETERMINABLE;

    CFBooleanRef hwAccel = NULL;
    OSStatus status = VTSessionCopyProperty(session,
        kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder,
        NULL, &hwAccel);

    if (status != noErr || !hwAccel) {
        return CLEONA_VIDEO_HW_NOT_DETERMINABLE;
    }

    int32_t result = CFBooleanGetValue(hwAccel)
        ? CLEONA_VIDEO_HW_YES : CLEONA_VIDEO_HW_NO;
    CFRelease(hwAccel);
    return result;
}

/* ==========================================================================
 * Negotiation (shared between open and reconfigure — Erratum 1)
 * ========================================================================== */

static int32_t clamp_down(int32_t requested, int32_t ceiling) {
    return requested > ceiling ? ceiling : requested;
}

static int32_t negotiate(const cleona_video_config_t *cfg,
                         cleona_video_config_t *out) {
    if (!cfg || !out) return CLEONA_VIDEO_ERR_INVALID;

    /* Validity checks — decided FIRST per Erratum 6b. */
    if (cfg->width <= 0 || cfg->height <= 0 || cfg->fps <= 0)
        return CLEONA_VIDEO_ERR_INVALID;
    if (cfg->target_bitrate_kbps <= 0)
        return CLEONA_VIDEO_ERR_INVALID;
    if (cfg->max_frame_bytes <= 0)
        return CLEONA_VIDEO_ERR_INVALID;
    if (cfg->keyframe_interval_frames < 0)
        return CLEONA_VIDEO_ERR_INVALID;

    int32_t codec = cfg->codec;
    if (codec <= 0) {
        codec = CLEONA_VIDEO_CODEC_H264;
    } else if (codec > CLEONA_VIDEO_CODEC_VP9) {
        return CLEONA_VIDEO_ERR_INVALID;  /* unknown: caller bug */
    } else if (codec != CLEONA_VIDEO_CODEC_H264 && codec != CLEONA_VIDEO_CODEC_HEVC) {
        /* VP9 and AV1: VideoToolbox has no encoder for these. Negotiate down
         * to H.264 rather than failing — the ABI requires H.264 in both
         * directions from every backend. */
        codec = CLEONA_VIDEO_CODEC_H264;
    }

    int32_t width  = clamp_down(cfg->width,  APPLE_MAX_WIDTH);
    int32_t height = clamp_down(cfg->height, APPLE_MAX_HEIGHT);
    int32_t fps    = clamp_down(cfg->fps,    APPLE_MAX_FPS);
    int32_t kbps   = cfg->target_bitrate_kbps;

    /* Estimate the nominal delta frame size at this bitrate/fps. */
    int64_t nominal = (int64_t)kbps * 125 / fps;  /* kbps * 1000 / 8 / fps */
    if (nominal < APPLE_MIN_FRAME_BYTES) nominal = APPLE_MIN_FRAME_BYTES;

    /* Check if a keyframe fits under the ceiling. */
    int32_t key_budget = cfg->max_frame_bytes / APPLE_KEYFRAME_FACTOR;
    if (key_budget < APPLE_MIN_FRAME_BYTES) {
        return CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE;
    }

    /* If the nominal frame is too large, scale the bitrate down. */
    if (nominal > key_budget) {
        int64_t fit_kbps = (int64_t)key_budget * fps / 125;
        if (fit_kbps < APPLE_MIN_BITRATE_KBPS) {
            return CLEONA_VIDEO_ERR_RATE_UNACHIEVABLE;
        }
        if (fit_kbps < kbps) kbps = (int32_t)fit_kbps;
    }

    out->codec                    = codec;
    out->width                    = width;
    out->height                   = height;
    out->fps                      = fps;
    out->target_bitrate_kbps      = kbps;
    out->max_frame_bytes          = cfg->max_frame_bytes;  /* never raised */
    out->keyframe_interval_frames = cfg->keyframe_interval_frames > 0
        ? cfg->keyframe_interval_frames : fps * 2;

    return CLEONA_VIDEO_OK;
}

/* Erratum 6b in-band error channel. */
static void write_open_error(cleona_video_config_t *out, int32_t code) {
    if (!out) return;
    memset(out, 0, sizeof(*out));
    out->max_frame_bytes = code;
}

/* ==========================================================================
 * AVCaptureSession setup / teardown
 * ========================================================================== */

static int setup_capture_session(cleona_video_session_t *s) {
    /* Must be called on the main thread or with appropriate serialization. */
    s->captureSession = [[AVCaptureSession alloc] init];

    /* Choose a session preset that accommodates our negotiated resolution. */
    if (s->cfg.width <= 352 && s->cfg.height <= 288) {
        if ([s->captureSession canSetSessionPreset:AVCaptureSessionPreset352x288])
            s->captureSession.sessionPreset = AVCaptureSessionPreset352x288;
    } else if (s->cfg.width <= 640 && s->cfg.height <= 480) {
        if ([s->captureSession canSetSessionPreset:AVCaptureSessionPreset640x480])
            s->captureSession.sessionPreset = AVCaptureSessionPreset640x480;
    } else if (s->cfg.width <= 1280 && s->cfg.height <= 720) {
        if ([s->captureSession canSetSessionPreset:AVCaptureSessionPreset1280x720])
            s->captureSession.sessionPreset = AVCaptureSessionPreset1280x720;
    } else {
        if ([s->captureSession canSetSessionPreset:AVCaptureSessionPreset1920x1080])
            s->captureSession.sessionPreset = AVCaptureSessionPreset1920x1080;
    }

    /* Set up camera input. */
    s->cameras = enumerate_cameras();
    if (s->cameras.count == 0) {
        s->captureSession = nil;
        return -1;
    }
    s->cameraIndex = 0;
    s->captureDevice = s->cameras[0];

    NSError *error = nil;
    s->captureInput = [AVCaptureDeviceInput deviceInputWithDevice:s->captureDevice
                                                           error:&error];
    if (!s->captureInput || error) {
        s->captureSession = nil;
        return -1;
    }

    if (![s->captureSession canAddInput:s->captureInput]) {
        s->captureSession = nil;
        return -1;
    }
    [s->captureSession addInput:s->captureInput];

    /* Set up video data output. */
    s->captureOutput = [[AVCaptureVideoDataOutput alloc] init];
    s->captureOutput.alwaysDiscardsLateVideoFrames = YES;

    /* Request NV12 pixel format (420v) — matches what VideoToolbox expects. */
    s->captureOutput.videoSettings = @{
        (NSString *)kCVPixelBufferPixelFormatTypeKey:
            @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
    };

    s->captureDelegate = [[CleonaVideoCaptureDelegate alloc] init];
    s->captureDelegate.session = s;

    s->captureQueue = dispatch_queue_create("chat.cleona.video.capture",
                                            DISPATCH_QUEUE_SERIAL);
    [s->captureOutput setSampleBufferDelegate:s->captureDelegate
                                        queue:s->captureQueue];

    if (![s->captureSession canAddOutput:s->captureOutput]) {
        s->captureSession = nil;
        return -1;
    }
    [s->captureSession addOutput:s->captureOutput];

    /* Configure frame rate on the capture device. */
    if ([s->captureDevice lockForConfiguration:&error]) {
        s->captureDevice.activeVideoMinFrameDuration =
            CMTimeMake(1, s->cfg.fps);
        s->captureDevice.activeVideoMaxFrameDuration =
            CMTimeMake(1, s->cfg.fps);
        [s->captureDevice unlockForConfiguration];
    }

    return 0;
}

static void teardown_capture_session(cleona_video_session_t *s) {
    if (s->captureSession) {
        if (s->captureSession.isRunning) {
            [s->captureSession stopRunning];
        }
        s->captureSession = nil;
    }
    s->captureInput = nil;
    s->captureOutput = nil;
    if (s->captureDelegate) {
        s->captureDelegate.session = NULL;
        s->captureDelegate = nil;
    }
    s->captureDevice = nil;
    s->cameras = nil;
    s->captureQueue = nil;
}

/* ==========================================================================
 * Lifecycle — ABI entry points
 * ========================================================================== */

CLEONA_VIDEO_API cleona_video_session_t *cleona_video_open(
    const cleona_video_config_t *cfg,
    cleona_video_config_t *out_negotiated) {

    if (!cfg) {
        write_open_error(out_negotiated, CLEONA_VIDEO_ERR_INVALID);
        return NULL;
    }

    cleona_video_config_t accepted;
    int32_t rc = negotiate(cfg, &accepted);
    if (rc != CLEONA_VIDEO_OK) {
        write_open_error(out_negotiated, rc);
        return NULL;
    }

    cleona_video_session_t *s =
        (cleona_video_session_t *)calloc(1, sizeof(cleona_video_session_t));
    if (!s) {
        write_open_error(out_negotiated, CLEONA_VIDEO_ERR_BACKEND);
        return NULL;
    }

    pthread_mutex_init(&s->lock, NULL);
    pthread_cond_init(&s->frame_cond, NULL);

    s->state = ST_OPEN;
    s->cfg = accepted;
    s->capture_enabled = 1;
    s->awaiting_keyframe = 1;
    s->hw_encode_verified = CLEONA_VIDEO_HW_NOT_DETERMINABLE;
    s->hw_decode_verified = CLEONA_VIDEO_HW_NOT_DETERMINABLE;
    s->texture_id = -1;
    s->texture_id_valid = 0;

    if (out_negotiated) *out_negotiated = s->cfg;
    return s;
}

CLEONA_VIDEO_API int32_t cleona_video_reconfigure(cleona_video_session_t *s,
                                                   const cleona_video_config_t *cfg,
                                                   cleona_video_config_t *out_negotiated) {
    if (!s || !cfg) return CLEONA_VIDEO_ERR_INVALID;

    pthread_mutex_lock(&s->lock);
    if (s->state == ST_CLOSED) {
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_STATE;
    }

    cleona_video_config_t accepted;
    int32_t rc = negotiate(cfg, &accepted);
    if (rc != CLEONA_VIDEO_OK) {
        /* Side-effect free on failure (Erratum 1). */
        pthread_mutex_unlock(&s->lock);
        return rc;
    }

    const int32_t geometry_changed =
        accepted.width != s->cfg.width || accepted.height != s->cfg.height;

    s->cfg = accepted;

    if (geometry_changed) {
        s->force_keyframe = 1;

        /* If running, recreate the compression session with new dimensions.
         * Invalidate the old session outside the lock to avoid deadlock:
         * VTCompressionSessionInvalidate may flush pending encode callbacks
         * that try to acquire our lock. */
        if (s->state == ST_RUNNING && s->compressionSession) {
            VTCompressionSessionRef oldComp = s->compressionSession;
            s->compressionSession = NULL;
            pthread_mutex_unlock(&s->lock);

            VTCompressionSessionInvalidate(oldComp);
            CFRelease(oldComp);

            VTCompressionSessionRef newComp = create_compression_session(s, &accepted);

            pthread_mutex_lock(&s->lock);
            if (!newComp) {
                pthread_mutex_unlock(&s->lock);
                return CLEONA_VIDEO_ERR_BACKEND;
            }
            s->compressionSession = newComp;
            s->hw_encode_verified = query_hw_encode(s->compressionSession);
        }
    } else if (s->state == ST_RUNNING && s->compressionSession) {
        /* Pure rate change: update properties without recreating the session. */
        int32_t bps = s->cfg.target_bitrate_kbps * 1000;
        CFNumberRef bitrateRef = CFNumberCreate(NULL, kCFNumberSInt32Type, &bps);
        VTSessionSetProperty(s->compressionSession,
            kVTCompressionPropertyKey_AverageBitRate, bitrateRef);
        CFRelease(bitrateRef);

        /* Update data rate limits. */
        double frameDuration = 1.0 / s->cfg.fps;
        CFNumberRef limitBytes = CFNumberCreate(NULL, kCFNumberSInt32Type,
                                                &s->cfg.max_frame_bytes);
        CFNumberRef limitSecs = CFNumberCreate(NULL, kCFNumberFloat64Type,
                                               &frameDuration);
        CFNumberRef limits[] = { limitBytes, limitSecs };
        CFArrayRef limitsArray = CFArrayCreate(NULL, (const void **)limits, 2,
                                               &kCFTypeArrayCallBacks);
        VTSessionSetProperty(s->compressionSession,
            kVTCompressionPropertyKey_DataRateLimits, limitsArray);
        CFRelease(limitBytes);
        CFRelease(limitSecs);
        CFRelease(limitsArray);
    }

    /* Drop a pending frame that exceeds the new ceiling (Erratum 1). */
    if (s->has_pending && s->pending_size > s->cfg.max_frame_bytes) {
        s->has_pending = 0;
        s->pending_size = 0;
        s->frames_dropped_oversize++;
    }

    if (out_negotiated) *out_negotiated = s->cfg;
    pthread_mutex_unlock(&s->lock);
    return CLEONA_VIDEO_OK;
}

CLEONA_VIDEO_API int32_t cleona_video_start(cleona_video_session_t *s) {
    if (!s) return CLEONA_VIDEO_ERR_INVALID;

    pthread_mutex_lock(&s->lock);
    if (s->state != ST_OPEN) {
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_STATE;
    }

    /* Set up AVCaptureSession. */
    @autoreleasepool {
        if (setup_capture_session(s) != 0) {
            pthread_mutex_unlock(&s->lock);
            return CLEONA_VIDEO_ERR_BACKEND;
        }
    }

    /* Create the VTCompressionSession. */
    s->compressionSession = create_compression_session(s, &s->cfg);
    if (!s->compressionSession) {
        teardown_capture_session(s);
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_BACKEND;
    }

    s->hw_encode_verified = query_hw_encode(s->compressionSession);

    /* Reset state for this run. */
    s->force_keyframe = 1;
    s->frame_index = 0;
    s->pts_next_us = 0;
    s->has_pending = 0;
    s->pending_size = 0;
    s->awaiting_keyframe = 1;

    s->state = ST_RUNNING;

    /* Start capture. */
    @autoreleasepool {
        [s->captureSession startRunning];
    }

    pthread_mutex_unlock(&s->lock);
    return CLEONA_VIDEO_OK;
}

CLEONA_VIDEO_API void cleona_video_stop(cleona_video_session_t *s) {
    if (!s) return;

    pthread_mutex_lock(&s->lock);
    if (s->state != ST_RUNNING) {
        pthread_mutex_unlock(&s->lock);
        return;
    }

    s->state = ST_OPEN;

    /* Signal any waiting reader. */
    pthread_cond_broadcast(&s->frame_cond);

    /* Snapshot the VideoToolbox sessions under the lock, then NULL the pointers
     * so neither the capture callback nor a concurrent submit can use them.
     * The actual invalidation/release happens OUTSIDE the lock to avoid
     * deadlock: VTCompressionSessionInvalidate may flush pending callbacks
     * that themselves try to acquire our lock. */
    VTCompressionSessionRef compToRelease = s->compressionSession;
    VTDecompressionSessionRef decToRelease = s->decompressionSession;
    CMVideoFormatDescriptionRef fmtToRelease = s->decoderFormatDesc;
    CVPixelBufferRef pixBufToRelease = s->decodedPixelBuffer;

    s->compressionSession = NULL;
    s->decompressionSession = NULL;
    s->decoderFormatDesc = NULL;
    s->decodedPixelBuffer = NULL;

    s->has_pending = 0;
    s->pending_size = 0;
    s->awaiting_keyframe = 1;

    pthread_mutex_unlock(&s->lock);

    /* Tear down capture outside the lock to avoid deadlock with the
     * capture callback's attempt to lock. */
    @autoreleasepool {
        teardown_capture_session(s);
    }

    /* Invalidate and release VideoToolbox sessions outside the lock. */
    if (compToRelease) {
        VTCompressionSessionInvalidate(compToRelease);
        CFRelease(compToRelease);
    }
    if (decToRelease) {
        VTDecompressionSessionInvalidate(decToRelease);
        CFRelease(decToRelease);
    }
    if (fmtToRelease) {
        CFRelease(fmtToRelease);
    }
    if (pixBufToRelease) {
        CVPixelBufferRelease(pixBufToRelease);
    }
}

CLEONA_VIDEO_API void cleona_video_close(cleona_video_session_t *s) {
    if (!s) return;

    cleona_video_stop(s);

    pthread_mutex_lock(&s->lock);
    s->state = ST_CLOSED;

    free(s->pending_buf);
    s->pending_buf = NULL;
    s->pending_cap = 0;

    pthread_mutex_unlock(&s->lock);

    pthread_mutex_destroy(&s->lock);
    pthread_cond_destroy(&s->frame_cond);
    free(s);
}

/* ==========================================================================
 * Data path — Dart never sees pixels (I10)
 * ========================================================================== */

CLEONA_VIDEO_API int32_t cleona_video_read_encoded(cleona_video_session_t *s,
                                                    uint8_t *buf, int32_t buf_cap,
                                                    int32_t *out_size, int32_t *out_flags,
                                                    int64_t *out_pts_us, int32_t timeout_ms) {
    if (!s || !buf || buf_cap <= 0 || !out_size || !out_flags || !out_pts_us)
        return CLEONA_VIDEO_ERR_INVALID;

    pthread_mutex_lock(&s->lock);

    /* Calculate absolute deadline for the wait. */
    struct timespec deadline;
    if (timeout_ms > 0) {
        struct timespec now;
        clock_gettime(CLOCK_REALTIME, &now);
        int64_t deadline_ns = (int64_t)now.tv_sec * 1000000000LL +
                              (int64_t)now.tv_nsec +
                              (int64_t)timeout_ms * 1000000LL;
        deadline.tv_sec  = (time_t)(deadline_ns / 1000000000LL);
        deadline.tv_nsec = (long)(deadline_ns % 1000000000LL);
    }

    for (;;) {
        if (s->state != ST_RUNNING) {
            pthread_mutex_unlock(&s->lock);
            return CLEONA_VIDEO_READ_CLOSED;
        }

        if (s->has_pending) {
            if (s->pending_size > buf_cap) {
                *out_size = s->pending_size;
                pthread_mutex_unlock(&s->lock);
                return CLEONA_VIDEO_ERR_BUFFER_TOO_SMALL;
            }

            memcpy(buf, s->pending_buf, (size_t)s->pending_size);
            *out_size   = s->pending_size;
            *out_flags  = s->pending_flags;
            *out_pts_us = s->pending_pts_us;
            s->has_pending = 0;
            pthread_mutex_unlock(&s->lock);
            return CLEONA_VIDEO_READ_FRAME;
        }

        /* Wait for a frame or state change. */
        if (timeout_ms == 0) {
            /* Poll — no wait. */
            pthread_mutex_unlock(&s->lock);
            return CLEONA_VIDEO_READ_TIMEOUT;
        } else if (timeout_ms < 0) {
            /* Block indefinitely. */
            pthread_cond_wait(&s->frame_cond, &s->lock);
        } else {
            /* Timed wait. */
            int rc = pthread_cond_timedwait(&s->frame_cond, &s->lock, &deadline);
            if (rc != 0) {
                /* ETIMEDOUT or error. */
                pthread_mutex_unlock(&s->lock);
                return CLEONA_VIDEO_READ_TIMEOUT;
            }
        }
    }
}

CLEONA_VIDEO_API int32_t cleona_video_submit_encoded(cleona_video_session_t *s,
                                                      const uint8_t *data, int32_t size,
                                                      int32_t flags) {
    if (!s) return CLEONA_VIDEO_ERR_STATE;
    if (!data || size <= 0) return CLEONA_VIDEO_ERR_INVALID;

    pthread_mutex_lock(&s->lock);
    if (s->state != ST_RUNNING) {
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_STATE;
    }

    int32_t is_keyframe = (flags & CLEONA_VIDEO_FLAG_KEYFRAME) != 0;

    /* If awaiting keyframe and this is not one, skip without counting
     * as a failure (the ABI specifies this). */
    if (s->awaiting_keyframe && !is_keyframe) {
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VIDEO_SUBMIT_AWAITING_KEYFRAME;
    }

    /* Convert Annex-B to AVCC and extract SPS/PPS. */
    int32_t avcc_cap = size + 64;
    uint8_t *avcc_buf = (uint8_t *)malloc((size_t)avcc_cap);
    if (!avcc_buf) {
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_BACKEND;
    }

    const uint8_t *sps_data = NULL, *pps_data = NULL;
    size_t sps_size = 0, pps_size = 0;

    int32_t avcc_size = annexb_to_avcc(data, size, avcc_buf, avcc_cap,
                                        &sps_data, &sps_size,
                                        &pps_data, &pps_size);
    if (avcc_size <= 0) {
        free(avcc_buf);
        s->decode_failures++;
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_DECODE;
    }

    /* If we have SPS/PPS (keyframe), create or update the format description
     * and possibly recreate the decompression session. */
    if (is_keyframe && sps_data && sps_size > 0 && pps_data && pps_size > 0) {
        const uint8_t *paramSets[] = { sps_data, pps_data };
        const size_t paramSizes[] = { sps_size, pps_size };

        CMVideoFormatDescriptionRef newFmt = NULL;
        OSStatus fmtStatus = CMVideoFormatDescriptionCreateFromH264ParameterSets(
            NULL, 2, paramSets, paramSizes, 4, &newFmt);

        if (fmtStatus == noErr && newFmt) {
            /* Check if format changed — if so, recreate decoder. */
            int needNewDecoder = 0;
            if (!s->decoderFormatDesc) {
                needNewDecoder = 1;
            } else {
                CMVideoDimensions oldDim =
                    CMVideoFormatDescriptionGetDimensions(s->decoderFormatDesc);
                CMVideoDimensions newDim =
                    CMVideoFormatDescriptionGetDimensions(newFmt);
                if (oldDim.width != newDim.width || oldDim.height != newDim.height) {
                    needNewDecoder = 1;
                }
            }

            if (needNewDecoder) {
                if (s->decompressionSession) {
                    VTDecompressionSessionInvalidate(s->decompressionSession);
                    CFRelease(s->decompressionSession);
                    s->decompressionSession = NULL;
                }
                if (s->decoderFormatDesc) {
                    CFRelease(s->decoderFormatDesc);
                }
                s->decoderFormatDesc = newFmt;

                /* Create the decompression session. */
                VTDecompressionOutputCallbackRecord cbRecord;
                cbRecord.decompressionOutputCallback = decompression_output_callback;
                cbRecord.decompressionOutputRefCon = s;

                /* Request NV12 output for Metal/texture compatibility. */
                CFMutableDictionaryRef destAttrs =
                    CFDictionaryCreateMutable(NULL, 0,
                                              &kCFTypeDictionaryKeyCallBacks,
                                              &kCFTypeDictionaryValueCallBacks);
                int32_t pixFmt = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
                CFNumberRef pixFmtRef = CFNumberCreate(NULL, kCFNumberSInt32Type, &pixFmt);
                CFDictionarySetValue(destAttrs,
                    kCVPixelBufferPixelFormatTypeKey, pixFmtRef);
                CFRelease(pixFmtRef);

#if TARGET_OS_IPHONE
                /* On iOS, request IOSurface-backed buffers for Metal textures. */
                CFDictionarySetValue(destAttrs,
                    kCVPixelBufferIOSurfacePropertiesKey,
                    (__bridge CFDictionaryRef)@{});
#endif

                OSStatus decStatus = VTDecompressionSessionCreate(
                    NULL, s->decoderFormatDesc, NULL, destAttrs,
                    &cbRecord, &s->decompressionSession);

                CFRelease(destAttrs);

                if (decStatus != noErr) {
                    s->decompressionSession = NULL;
                    /* Query will return NOT_DETERMINABLE. */
                } else {
                    /* Query hardware decode status. VideoToolbox does not
                     * expose a direct property for hardware decode; on Apple
                     * silicon, H.264 decode is always hardware. We report
                     * HW_YES if we successfully created the session. */
                    s->hw_decode_verified = CLEONA_VIDEO_HW_YES;
                }
            } else {
                CFRelease(newFmt);
            }
        } else if (newFmt) {
            CFRelease(newFmt);
        }
    }

    if (!s->decompressionSession) {
        free(avcc_buf);
        if (is_keyframe) {
            /* Failed to create decoder even with a keyframe. */
            s->decode_failures++;
            pthread_mutex_unlock(&s->lock);
            return CLEONA_VIDEO_ERR_DECODE;
        }
        /* No decoder yet and not a keyframe — need a keyframe first. */
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VIDEO_SUBMIT_AWAITING_KEYFRAME;
    }

    /* Create a CMBlockBuffer from the AVCC data. */
    CMBlockBufferRef blockBuf = NULL;
    OSStatus bbStatus = CMBlockBufferCreateWithMemoryBlock(
        NULL, avcc_buf, (size_t)avcc_size,
        kCFAllocatorNull,  /* block allocator — we manage the memory */
        NULL, 0, (size_t)avcc_size,
        0, &blockBuf);

    if (bbStatus != noErr || !blockBuf) {
        free(avcc_buf);
        s->decode_failures++;
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_DECODE;
    }

    /* Create a CMSampleBuffer wrapping the block buffer. */
    CMSampleBufferRef sampleBuf = NULL;
    const size_t sampleSize = (size_t)avcc_size;
    CMSampleTimingInfo timing;
    timing.duration = kCMTimeInvalid;
    timing.presentationTimeStamp = kCMTimeZero;
    timing.decodeTimeStamp = kCMTimeInvalid;

    OSStatus sbStatus = CMSampleBufferCreateReady(
        NULL, blockBuf, s->decoderFormatDesc,
        1, 1, &timing, 1, &sampleSize, &sampleBuf);

    CFRelease(blockBuf);

    if (sbStatus != noErr || !sampleBuf) {
        free(avcc_buf);
        s->decode_failures++;
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_DECODE;
    }

    /* Snapshot the decompressionSession ref and release the lock before
     * calling VTDecompressionSessionDecodeFrame. The decode output callback
     * (decompression_output_callback) acquires s->lock to deposit the
     * decoded pixel buffer. If the callback fires synchronously on this
     * thread (which is the default behaviour), holding the lock here would
     * deadlock. Releasing first is safe: s->state is already checked above,
     * and a concurrent stop() NULLs the session pointer but the ref we
     * captured here keeps the session alive until CFRelease in stop(). */
    VTDecompressionSessionRef decSession = s->decompressionSession;
    pthread_mutex_unlock(&s->lock);

    VTDecodeFrameFlags decodeFlags = 0;
    VTDecodeInfoFlags infoFlags = 0;
    OSStatus decStatus = VTDecompressionSessionDecodeFrame(
        decSession,
        sampleBuf, decodeFlags,
        NULL, &infoFlags);

    CFRelease(sampleBuf);
    free(avcc_buf);

    if (decStatus != noErr) {
        pthread_mutex_lock(&s->lock);
        s->decode_failures++;
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_DECODE;
    }

    pthread_mutex_lock(&s->lock);
    s->awaiting_keyframe = 0;
    pthread_mutex_unlock(&s->lock);
    return CLEONA_VIDEO_SUBMIT_ACCEPTED;
}

CLEONA_VIDEO_API int32_t cleona_video_get_texture_id(cleona_video_session_t *s,
                                                      int64_t *out_id) {
    if (!s || !out_id) return CLEONA_VIDEO_ERR_INVALID;

    pthread_mutex_lock(&s->lock);
    if (s->state != ST_RUNNING) {
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_STATE;
    }

    /* The Flutter texture id must be registered via FlutterTextureRegistry
     * from the Dart/platform-channel side. This backend produces decoded
     * CVPixelBuffers; the actual texture registration is a platform
     * integration concern above this ABI.
     *
     * Until the texture path is wired from the Flutter side
     * (FlutterTextureRegistry.register → CVPixelBufferRef copyPixelBuffer),
     * we return ERR_UNSUPPORTED. A real integration would set texture_id_valid
     * after registration. */
    if (!s->texture_id_valid) {
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_UNSUPPORTED;
    }

    *out_id = s->texture_id;
    pthread_mutex_unlock(&s->lock);
    return CLEONA_VIDEO_OK;
}

/* ==========================================================================
 * Controls
 * ========================================================================== */

CLEONA_VIDEO_API int32_t cleona_video_request_keyframe(cleona_video_session_t *s) {
    if (!s) return CLEONA_VIDEO_ERR_INVALID;

    pthread_mutex_lock(&s->lock);
    if (s->state != ST_RUNNING) {
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_STATE;
    }
    s->force_keyframe = 1;
    pthread_mutex_unlock(&s->lock);
    return CLEONA_VIDEO_OK;
}

CLEONA_VIDEO_API void cleona_video_set_capture_enabled(cleona_video_session_t *s,
                                                        int32_t on) {
    if (!s) return;

    pthread_mutex_lock(&s->lock);
    int32_t want = on ? 1 : 0;

    if (want && !s->capture_enabled) {
        /* Re-enabling: the peer's decoder has been starved. Force a keyframe
         * so it can resume (unconditional, not a heuristic). */
        s->force_keyframe = 1;
    }
    if (!want) {
        /* Disabling: drop any pending frame. */
        s->has_pending = 0;
        s->pending_size = 0;
    }
    s->capture_enabled = want;
    pthread_mutex_unlock(&s->lock);
}

CLEONA_VIDEO_API int32_t cleona_video_switch_camera(cleona_video_session_t *s) {
    if (!s) return CLEONA_VIDEO_ERR_INVALID;

    pthread_mutex_lock(&s->lock);
    if (s->state != ST_RUNNING) {
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_STATE;
    }

    if (!s->cameras || s->cameras.count < 2) {
        pthread_mutex_unlock(&s->lock);
        return CLEONA_VIDEO_ERR_UNSUPPORTED;
    }

    int32_t nextIndex = (s->cameraIndex + 1) % (int32_t)s->cameras.count;
    AVCaptureDevice *nextDevice = s->cameras[nextIndex];

    /* Remove the current input and add the new one. */
    @autoreleasepool {
        [s->captureSession beginConfiguration];

        if (s->captureInput) {
            [s->captureSession removeInput:s->captureInput];
        }

        NSError *error = nil;
        AVCaptureDeviceInput *newInput =
            [AVCaptureDeviceInput deviceInputWithDevice:nextDevice error:&error];

        if (!newInput || error || ![s->captureSession canAddInput:newInput]) {
            /* Failed — re-add the old input. */
            if (s->captureInput && [s->captureSession canAddInput:s->captureInput]) {
                [s->captureSession addInput:s->captureInput];
            }
            [s->captureSession commitConfiguration];
            pthread_mutex_unlock(&s->lock);
            return CLEONA_VIDEO_ERR_BACKEND;
        }

        [s->captureSession addInput:newInput];
        s->captureInput = newInput;
        s->captureDevice = nextDevice;
        s->cameraIndex = nextIndex;

        /* Configure frame rate on the new device. */
        if ([nextDevice lockForConfiguration:&error]) {
            nextDevice.activeVideoMinFrameDuration =
                CMTimeMake(1, s->cfg.fps);
            nextDevice.activeVideoMaxFrameDuration =
                CMTimeMake(1, s->cfg.fps);
            [nextDevice unlockForConfiguration];
        }

        [s->captureSession commitConfiguration];
    }

    /* Force a keyframe after camera switch. */
    s->force_keyframe = 1;
    s->has_pending = 0;

    pthread_mutex_unlock(&s->lock);
    return CLEONA_VIDEO_OK;
}

/* ==========================================================================
 * Verification report (I11)
 * ========================================================================== */

CLEONA_VIDEO_API void cleona_video_get_report(cleona_video_session_t *s,
                                               cleona_video_report_t *out) {
    if (!out) return;
    memset(out, 0, sizeof(*out));

    /* "No session" is not evidence that there is no hardware (I11). */
    out->hardware_encode = CLEONA_VIDEO_HW_NOT_DETERMINABLE;
    out->hardware_decode = CLEONA_VIDEO_HW_NOT_DETERMINABLE;
    if (!s) return;

    pthread_mutex_lock(&s->lock);
    out->codec_in_use            = s->cfg.codec;
    out->hardware_encode         = s->hw_encode_verified;
    out->hardware_decode         = s->hw_decode_verified;
    out->negotiated_width        = s->cfg.width;
    out->negotiated_height       = s->cfg.height;
    out->negotiated_fps          = s->cfg.fps;
    out->capture_backend         = CLEONA_VIDEO_BACKEND_APPLE_AVCAPTURE;
    out->encode_backend          = CLEONA_VIDEO_BACKEND_APPLE_VIDEOTOOLBOX;
    out->frames_captured         = s->frames_captured;
    out->frames_encoded          = s->frames_encoded;
    out->frames_dropped_oversize = s->frames_dropped_oversize;
    out->frames_decoded          = s->frames_decoded;
    out->decode_failures         = s->decode_failures;
    pthread_mutex_unlock(&s->lock);
}

/* v4l2_capture.h — V4L2 camera capture for the Linux video backend (V1.13).
 *
 * Docs/SPEC_VOICE_VIDEO_REWORK.md I10: "camera -> platform surface -> hardware
 * encoder"; this file is the "camera" half. It never hands a raw pixel buffer
 * across the cleona_video ABI (I10 governs the whole session, not just the
 * public entry points) — cleona_video_linux.c reads a frame from here and
 * feeds it straight into a VAAPI-mapped surface (cleona_video_linux_encoder.c),
 * within the same process, never through Dart.
 *
 * SCOPE. This backend's camera on the verification machine
 * (uvcvideo "Integrated_Webcam_FHD") offers two capture formats: MJPG up to
 * 1920x1080 and uncompressed YUYV up to 640x480, both at 30 fps. Decoding MJPG
 * needs a JPEG decoder this package does not implement (no such dependency
 * exists anywhere else in native/cleona_video, and adding one is a
 * disproportionate amount of new attack surface for a capture-resolution
 * increase that V1.17's bandwidth-driven downscaling would frequently ask for
 * anyway). This file therefore captures YUYV only, at the LARGEST resolution
 * the device offers for that format — queried at runtime via
 * VIDIOC_ENUM_FRAMESIZES, not hard-coded, so a camera with a larger native
 * YUYV mode on a different machine is used at its own best size. Recorded as
 * a known limitation in this package's acceptance report, not hidden here.
 *
 * The device is opened and configured to this single "native" format ONCE, in
 * v4l2_capture_open(), and never reconfigured for the life of the capture
 * session — cleona_video_reconfigure() (Erratum 1) changes what the ENCODER
 * asks for, not what the camera streams. Every negotiated width/height at or
 * below the native size is served by software-scaling the native frame in
 * v4l2_capture_scale_to_nv12() below; every negotiated fps at or below the
 * native fps is served by frame decimation in the caller
 * (cleona_video_linux.c), never by touching V4L2 format/streaming state again.
 * This is a deliberate simplification: restarting V4L2 streaming (STREAMOFF,
 * re-negotiate S_FMT/S_PARM, re-mmap, STREAMON) on every reconfigure() would
 * add a real stall exactly when Erratum 1 wants the fastest possible reaction
 * to a shrinking ceiling, for a benefit (matching the sensor's native mode
 * exactly) invisible after software scaling.
 */

#ifndef CLEONA_VIDEO_LINUX_V4L2_CAPTURE_H
#define CLEONA_VIDEO_LINUX_V4L2_CAPTURE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct v4l2_capture v4l2_capture_t;

typedef struct {
    int32_t width, height;   /* native YUYV capture size actually opened */
    int32_t fps;              /* native frame rate, from VIDIOC_ENUM_FRAMEINTERVALS */
    char    bus_info[32];     /* USB bus path, used to de-duplicate multi-node
                               * UVC devices into physical cameras — see
                               * v4l2_capture_count_cameras() */
} v4l2_capture_info_t;

/* Enumerates /dev/video0.."/dev/video<max_index>" and returns the number of
 * DISTINCT physical cameras that expose V4L2_CAP_VIDEO_CAPTURE with a YUYV
 * mode (a UVC device commonly registers two nodes — one capture, one
 * metadata-only — that share bus_info; this counts physical devices, which is
 * what cleona_video_switch_camera cycles through, not raw device nodes).
 * Writes up to max_out chosen device paths (the capture-capable node of each
 * physical camera, lowest index first) into out_paths (each entry
 * PATH_CAP bytes) and returns the count, capped at max_out. */
#define V4L2_CAPTURE_PATH_CAP 32
int32_t v4l2_capture_enumerate(char out_paths[][V4L2_CAPTURE_PATH_CAP],
                               int32_t max_out);

/* Opens dev_path, negotiates YUYV at its largest enumerated frame size,
 * requests 4 mmap buffers and starts streaming (VIDIOC_STREAMON). Returns
 * NULL on any failure (device busy, no YUYV mode, mmap failure); the caller
 * maps this to CLEONA_VIDEO_ERR_BACKEND (a capable-in-principle device that
 * failed this attempt) or CLEONA_VIDEO_ERR_UNSUPPORTED (no YUYV mode at all)
 * as appropriate — this file does not know the ABI's error codes and returns
 * a plain out_no_yuyv_mode flag instead so the caller can pick. */
v4l2_capture_t* v4l2_capture_open(const char* dev_path, int32_t* out_no_yuyv_mode,
                                  v4l2_capture_info_t* out_info);

/* Stops streaming, unmaps buffers, closes the device. NULL is a no-op. */
void v4l2_capture_close(v4l2_capture_t* c);

/* Waits up to timeout_ms for the next frame via poll(), dequeues it (VIDIOC_DQBUF),
 * converts YUYV -> NV12 while simultaneously downscaling (nearest-neighbour;
 * a call's frame budget has no room for a real filtered scaler and the
 * VAAPI encoder's own in-loop and deblocking filters remove most of the
 * softness a box filter would otherwise buy) from the native capture size to
 * dst_width x dst_height (which MUST be <= the native size in both
 * dimensions — the caller is responsible for that, this file does not clamp),
 * and requeues the V4L2 buffer (VIDIOC_QBUF) before returning.
 *
 * out_nv12 must be at least dst_width*dst_height*3/2 bytes (Y plane followed
 * by interleaved UV, standard NV12 layout — the layout VAAPI's NV12 surfaces
 * on this driver expect, verified via vaDeriveImage's reported fourcc/pitch
 * in cleona_video_linux_encoder.c).
 *
 * Returns 1 on a frame delivered, 0 on timeout, -1 on a device error (the
 * caller treats this as the capture path failing, not as "no frame yet"). */
int32_t v4l2_capture_read_scaled_nv12(v4l2_capture_t* c, uint8_t* out_nv12,
                                      int32_t dst_width, int32_t dst_height,
                                      int32_t timeout_ms);

#ifdef __cplusplus
}
#endif

#endif /* CLEONA_VIDEO_LINUX_V4L2_CAPTURE_H */

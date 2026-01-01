/* v4l2_capture.c — see v4l2_capture.h for scope and rationale. */

#define _GNU_SOURCE
#if !defined(_POSIX_C_SOURCE)
  #define _POSIX_C_SOURCE 200809L
#endif

#include "v4l2_capture.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <poll.h>
#include <linux/videodev2.h>

#define V4L2_CAPTURE_N_BUFFERS 4

typedef struct {
    void*    start;
    uint32_t length;
} v4l2_mmap_buf_t;

struct v4l2_capture {
    int fd;
    int32_t width, height;   /* native format actually streaming */
    int32_t fps;
    v4l2_mmap_buf_t buffers[V4L2_CAPTURE_N_BUFFERS];
    int32_t n_buffers;
    int32_t streaming;
};

/* ==========================================================================
 * ioctl retry helper -- V4L2's documented convention: EINTR means "call it
 * again", not "it failed".
 * ========================================================================== */
static int xioctl(int fd, unsigned long req, void* arg) {
    int r;
    do { r = ioctl(fd, req, arg); } while (r < 0 && errno == EINTR);
    return r;
}

/* ==========================================================================
 * Enumeration / de-duplication into physical cameras
 * ========================================================================== */

static int32_t node_has_yuyv_capture(int fd) {
    struct v4l2_fmtdesc fmt;
    memset(&fmt, 0, sizeof(fmt));
    fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    while (xioctl(fd, VIDIOC_ENUM_FMT, &fmt) == 0) {
        if (fmt.pixelformat == V4L2_PIX_FMT_YUYV) return 1;
        fmt.index++;
    }
    return 0;
}

int32_t v4l2_capture_enumerate(char out_paths[][V4L2_CAPTURE_PATH_CAP], int32_t max_out) {
    char seen_bus[16][32];
    int32_t seen_n = 0;
    int32_t count = 0;

    for (int32_t idx = 0; idx < 64 && count < max_out; idx++) {
        char path[32];
        snprintf(path, sizeof(path), "/dev/video%d", idx);
        int fd = open(path, O_RDWR | O_NONBLOCK);
        if (fd < 0) continue;

        struct v4l2_capability cap;
        memset(&cap, 0, sizeof(cap));
        if (xioctl(fd, VIDIOC_QUERYCAP, &cap) < 0) { close(fd); continue; }

        /* device_caps is authoritative when V4L2_CAP_DEVICE_CAPS is set (every
         * kernel this backend targets sets it); capabilities alone can list
         * capabilities of OTHER nodes of a multi-node device, which is exactly
         * the ambiguity this function exists to resolve. */
        uint32_t caps = (cap.capabilities & V4L2_CAP_DEVICE_CAPS)
                       ? cap.device_caps : cap.capabilities;
        if (!(caps & V4L2_CAP_VIDEO_CAPTURE)) { close(fd); continue; }
        if (!node_has_yuyv_capture(fd)) { close(fd); continue; }

        const char* bus = (const char*)cap.bus_info;
        int32_t dup = 0;
        for (int32_t i = 0; i < seen_n; i++) {
            if (strncmp(seen_bus[i], bus, sizeof(seen_bus[i])) == 0) { dup = 1; break; }
        }
        close(fd);
        if (dup) continue;

        if (seen_n < 16) {
            snprintf(seen_bus[seen_n], sizeof(seen_bus[seen_n]), "%s", bus);
            seen_n++;
        }
        snprintf(out_paths[count], V4L2_CAPTURE_PATH_CAP, "%s", path);
        count++;
    }
    return count;
}

/* ==========================================================================
 * Open / negotiate / mmap / stream on
 * ========================================================================== */

/* Finds the largest (by pixel count) discrete YUYV frame size this device
 * offers, and its frame interval, via VIDIOC_ENUM_FRAMESIZES /
 * VIDIOC_ENUM_FRAMEINTERVALS. Returns 1 if a YUYV mode exists at all. */
static int32_t find_best_yuyv_mode(int fd, int32_t* out_w, int32_t* out_h, int32_t* out_fps) {
    if (!node_has_yuyv_capture(fd)) return 0;

    int32_t best_w = 0, best_h = 0, best_fps = 30;
    struct v4l2_frmsizeenum fs;
    memset(&fs, 0, sizeof(fs));
    fs.pixel_format = V4L2_PIX_FMT_YUYV;
    while (xioctl(fd, VIDIOC_ENUM_FRAMESIZES, &fs) == 0) {
        if (fs.type == V4L2_FRMSIZE_TYPE_DISCRETE) {
            int64_t px = (int64_t)fs.discrete.width * fs.discrete.height;
            int64_t best_px = (int64_t)best_w * best_h;
            if (px > best_px) {
                best_w = (int32_t)fs.discrete.width;
                best_h = (int32_t)fs.discrete.height;
            }
        }
        fs.index++;
    }
    if (best_w <= 0 || best_h <= 0) return 0;

    struct v4l2_frmivalenum fi;
    memset(&fi, 0, sizeof(fi));
    fi.pixel_format = V4L2_PIX_FMT_YUYV;
    fi.width = (uint32_t)best_w;
    fi.height = (uint32_t)best_h;
    int32_t best_num = 1, best_den = 30;
    while (xioctl(fd, VIDIOC_ENUM_FRAMEINTERVALS, &fi) == 0) {
        if (fi.type == V4L2_FRMIVAL_TYPE_DISCRETE) {
            /* Prefer the highest frame rate (smallest interval numerator/denominator ratio). */
            if ((int64_t)fi.discrete.denominator * best_num >
                (int64_t)best_den * fi.discrete.numerator) {
                best_num = (int32_t)fi.discrete.numerator;
                best_den = (int32_t)fi.discrete.denominator;
            }
        }
        fi.index++;
    }
    best_fps = best_num > 0 ? best_den / best_num : 30;
    if (best_fps <= 0) best_fps = 30;

    *out_w = best_w;
    *out_h = best_h;
    *out_fps = best_fps;
    return 1;
}

v4l2_capture_t* v4l2_capture_open(const char* dev_path, int32_t* out_no_yuyv_mode,
                                  v4l2_capture_info_t* out_info) {
    if (out_no_yuyv_mode) *out_no_yuyv_mode = 0;

    int fd = open(dev_path, O_RDWR | O_NONBLOCK);
    if (fd < 0) return NULL;

    struct v4l2_capability cap;
    memset(&cap, 0, sizeof(cap));
    if (xioctl(fd, VIDIOC_QUERYCAP, &cap) < 0) { close(fd); return NULL; }
    uint32_t caps = (cap.capabilities & V4L2_CAP_DEVICE_CAPS)
                   ? cap.device_caps : cap.capabilities;
    if (!(caps & V4L2_CAP_VIDEO_CAPTURE) || !(caps & V4L2_CAP_STREAMING)) {
        close(fd);
        return NULL;
    }

    int32_t w = 0, h = 0, fps = 0;
    if (!find_best_yuyv_mode(fd, &w, &h, &fps)) {
        if (out_no_yuyv_mode) *out_no_yuyv_mode = 1;
        close(fd);
        return NULL;
    }

    struct v4l2_format fmt;
    memset(&fmt, 0, sizeof(fmt));
    fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    fmt.fmt.pix.width = (uint32_t)w;
    fmt.fmt.pix.height = (uint32_t)h;
    fmt.fmt.pix.pixelformat = V4L2_PIX_FMT_YUYV;
    fmt.fmt.pix.field = V4L2_FIELD_ANY;
    if (xioctl(fd, VIDIOC_S_FMT, &fmt) < 0) { close(fd); return NULL; }
    /* The driver may have adjusted width/height/format; trust what it echoes
     * back rather than what was requested (the same discipline the ABI itself
     * requires of every negotiation in this backend). */
    if (fmt.fmt.pix.pixelformat != V4L2_PIX_FMT_YUYV) { close(fd); return NULL; }
    w = (int32_t)fmt.fmt.pix.width;
    h = (int32_t)fmt.fmt.pix.height;

    struct v4l2_streamparm parm;
    memset(&parm, 0, sizeof(parm));
    parm.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    parm.parm.capture.timeperframe.numerator = 1;
    parm.parm.capture.timeperframe.denominator = (uint32_t)fps;
    xioctl(fd, VIDIOC_S_PARM, &parm);  /* best-effort; frame decimation upstream
                                        * of this file covers a driver that
                                        * ignores this */

    struct v4l2_requestbuffers req;
    memset(&req, 0, sizeof(req));
    req.count = V4L2_CAPTURE_N_BUFFERS;
    req.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    req.memory = V4L2_MEMORY_MMAP;
    if (xioctl(fd, VIDIOC_REQBUFS, &req) < 0 || req.count < 2) { close(fd); return NULL; }

    v4l2_capture_t* c = (v4l2_capture_t*)calloc(1, sizeof(*c));
    if (!c) { close(fd); return NULL; }
    c->fd = fd;
    c->width = w;
    c->height = h;
    c->fps = fps;
    c->n_buffers = (int32_t)req.count;

    for (int32_t i = 0; i < c->n_buffers; i++) {
        struct v4l2_buffer buf;
        memset(&buf, 0, sizeof(buf));
        buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        buf.memory = V4L2_MEMORY_MMAP;
        buf.index = (uint32_t)i;
        if (xioctl(fd, VIDIOC_QUERYBUF, &buf) < 0) goto fail;
        c->buffers[i].length = buf.length;
        c->buffers[i].start = mmap(NULL, buf.length, PROT_READ | PROT_WRITE,
                                   MAP_SHARED, fd, (off_t)buf.m.offset);
        if (c->buffers[i].start == MAP_FAILED) { c->buffers[i].start = NULL; goto fail; }
        if (xioctl(fd, VIDIOC_QBUF, &buf) < 0) goto fail;
    }

    enum v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    if (xioctl(fd, VIDIOC_STREAMON, &type) < 0) goto fail;
    c->streaming = 1;

    if (out_info) {
        out_info->width = w;
        out_info->height = h;
        out_info->fps = fps;
        snprintf(out_info->bus_info, sizeof(out_info->bus_info), "%s", cap.bus_info);
    }
    return c;

fail:
    for (int32_t i = 0; i < c->n_buffers; i++) {
        if (c->buffers[i].start) munmap(c->buffers[i].start, c->buffers[i].length);
    }
    close(fd);
    free(c);
    return NULL;
}

void v4l2_capture_close(v4l2_capture_t* c) {
    if (!c) return;
    if (c->streaming) {
        enum v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        xioctl(c->fd, VIDIOC_STREAMOFF, &type);
    }
    for (int32_t i = 0; i < c->n_buffers; i++) {
        if (c->buffers[i].start) munmap(c->buffers[i].start, c->buffers[i].length);
    }
    close(c->fd);
    free(c);
}

/* ==========================================================================
 * YUYV -> NV12 with nearest-neighbour downscale
 * ==========================================================================
 * src is packed YUYV (Y0 U0 Y1 V0 per 2 horizontal pixels), src_w x src_h.
 * dst is NV12 (Y plane, then interleaved U/V at half resolution both axes),
 * dst_w x dst_h, dst_w/dst_h <= src_w/src_h (caller's contract).
 *
 * Luma: nearest-neighbour sample of the YUYV luma plane (every byte at an
 * even offset within a pixel pair is Y; the helper below resolves that per
 * sampled column).
 *
 * Chroma: sampled once per 2x2 output block, from the YUYV chroma sample that
 * nearest-neighbour maps to for that block's top-left source pixel -- YUYV
 * already carries chroma at half horizontal resolution (4:2:2), so this is a
 * second nearest-neighbour step down to 4:2:0, not a new subsampling scheme.
 */
static uint8_t yuyv_luma(const uint8_t* row, int32_t x) {
    /* byte 0,2,4,... within a pixel pair is Y for that pixel; U/V sit at
     * odd offsets and are shared by the pixel pair. */
    return row[x * 2];
}

static void yuyv_chroma(const uint8_t* row, int32_t x, uint8_t* out_u, uint8_t* out_v) {
    int32_t pair = (x / 2) * 4;   /* start of the 4-byte YUYV group x belongs to */
    *out_u = row[pair + 1];
    *out_v = row[pair + 3];
}

int32_t v4l2_capture_read_scaled_nv12(v4l2_capture_t* c, uint8_t* out_nv12,
                                      int32_t dst_width, int32_t dst_height,
                                      int32_t timeout_ms) {
    if (!c || !out_nv12 || dst_width <= 0 || dst_height <= 0) return -1;

    struct pollfd pfd;
    pfd.fd = c->fd;
    pfd.events = POLLIN;
    int pr = poll(&pfd, 1, timeout_ms);
    if (pr == 0) return 0;               /* timeout */
    if (pr < 0) return (errno == EINTR) ? 0 : -1;
    if (!(pfd.revents & POLLIN)) return 0;

    struct v4l2_buffer buf;
    memset(&buf, 0, sizeof(buf));
    buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    buf.memory = V4L2_MEMORY_MMAP;
    if (xioctl(c->fd, VIDIOC_DQBUF, &buf) < 0) {
        return (errno == EAGAIN) ? 0 : -1;
    }
    if ((int32_t)buf.index >= c->n_buffers) { xioctl(c->fd, VIDIOC_QBUF, &buf); return -1; }

    const uint8_t* src = (const uint8_t*)c->buffers[buf.index].start;
    int32_t src_w = c->width, src_h = c->height;
    int32_t src_stride = src_w * 2;   /* YUYV: 2 bytes/pixel */

    uint8_t* y_plane = out_nv12;
    uint8_t* uv_plane = out_nv12 + (size_t)dst_width * (size_t)dst_height;

    /* Luma: one nearest-neighbour sample per output pixel. */
    for (int32_t dy = 0; dy < dst_height; dy++) {
        int32_t sy = dy * src_h / dst_height;
        const uint8_t* srow = src + (size_t)sy * (size_t)src_stride;
        uint8_t* drow = y_plane + (size_t)dy * (size_t)dst_width;
        for (int32_t dx = 0; dx < dst_width; dx++) {
            int32_t sx = dx * src_w / dst_width;
            drow[dx] = yuyv_luma(srow, sx);
        }
    }

    /* Chroma: one U/V sample per output 2x2 block, standard NV12 order (U
     * then V), matching VA_FOURCC_NV12 as reported by vaDeriveImage on this
     * driver (cross-checked in cleona_video_linux_encoder.c). */
    int32_t dst_cw = dst_width / 2, dst_ch = dst_height / 2;
    for (int32_t cy = 0; cy < dst_ch; cy++) {
        int32_t dy = cy * 2;
        int32_t sy = dy * src_h / dst_height;
        const uint8_t* srow = src + (size_t)sy * (size_t)src_stride;
        uint8_t* drow = uv_plane + (size_t)cy * (size_t)dst_width;
        for (int32_t cx = 0; cx < dst_cw; cx++) {
            int32_t dx = cx * 2;
            int32_t sx = dx * src_w / dst_width;
            uint8_t u, v;
            yuyv_chroma(srow, sx, &u, &v);
            drow[cx * 2 + 0] = u;
            drow[cx * 2 + 1] = v;
        }
    }

    xioctl(c->fd, VIDIOC_QBUF, &buf);
    return 1;
}

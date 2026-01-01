/// Thin C shim for Video4Linux2 camera capture.
/// Provides a simple API: open camera → start → grab frame → stop → close.
/// Uses memory-mapped buffers for zero-copy frame access.
///
/// Build: gcc -shared -fPIC -O2 -o libcleona_v4l2.so v4l2_shim.c

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <linux/videodev2.h>

#define NUM_BUFFERS 4
#define MAX_DEVICES 8

typedef struct {
  void *start;
  size_t length;
} MappedBuffer;

typedef struct {
  int fd;
  int width;
  int height;
  uint32_t pixfmt;    // V4L2_PIX_FMT_* (negotiated)
  int streaming;

  MappedBuffer buffers[NUM_BUFFERS];
  int n_buffers;

  // Current frame (dequeued)
  uint8_t *frame_data;
  int frame_size;
  int frame_index;     // buffer index to requeue
} V4l2Camera;

// ── Helper ──────────────────────────────────────────────────────────

static int xioctl(int fd, unsigned long request, void *arg) {
  int r;
  do { r = ioctl(fd, request, arg); } while (r == -1 && errno == EINTR);
  return r;
}

// ── Public API ──────────────────────────────────────────────────────

/// Open a V4L2 camera device.
/// device: e.g., "/dev/video0"
/// width, height: requested resolution (may be adjusted by driver)
/// fps: requested framerate
/// Returns opaque handle or NULL on failure.
void *cleona_v4l2_open(const char *device, int width, int height, int fps) {
  int fd = open(device, O_RDWR | O_NONBLOCK);
  if (fd < 0) return NULL;

  // Query capabilities
  struct v4l2_capability cap;
  if (xioctl(fd, VIDIOC_QUERYCAP, &cap) < 0 ||
      !(cap.capabilities & V4L2_CAP_VIDEO_CAPTURE) ||
      !(cap.capabilities & V4L2_CAP_STREAMING)) {
    close(fd);
    return NULL;
  }

  // Negotiate pixel format: prefer I420 (YUV420), fallback to YUYV, MJPEG
  struct v4l2_format fmt;
  memset(&fmt, 0, sizeof(fmt));
  fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;

  // Try I420 first
  fmt.fmt.pix.width = width;
  fmt.fmt.pix.height = height;
  fmt.fmt.pix.pixelformat = V4L2_PIX_FMT_YUV420;
  fmt.fmt.pix.field = V4L2_FIELD_NONE;

  if (xioctl(fd, VIDIOC_S_FMT, &fmt) < 0 ||
      fmt.fmt.pix.pixelformat != V4L2_PIX_FMT_YUV420) {
    // Try YUYV
    fmt.fmt.pix.width = width;
    fmt.fmt.pix.height = height;
    fmt.fmt.pix.pixelformat = V4L2_PIX_FMT_YUYV;
    fmt.fmt.pix.field = V4L2_FIELD_NONE;

    if (xioctl(fd, VIDIOC_S_FMT, &fmt) < 0 ||
        fmt.fmt.pix.pixelformat != V4L2_PIX_FMT_YUYV) {
      // Try MJPEG
      fmt.fmt.pix.width = width;
      fmt.fmt.pix.height = height;
      fmt.fmt.pix.pixelformat = V4L2_PIX_FMT_MJPEG;
      fmt.fmt.pix.field = V4L2_FIELD_NONE;

      if (xioctl(fd, VIDIOC_S_FMT, &fmt) < 0) {
        close(fd);
        return NULL;
      }
    }
  }

  // Set framerate
  struct v4l2_streamparm parm;
  memset(&parm, 0, sizeof(parm));
  parm.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  parm.parm.capture.timeperframe.numerator = 1;
  parm.parm.capture.timeperframe.denominator = fps;
  xioctl(fd, VIDIOC_S_PARM, &parm); // best-effort, not fatal

  V4l2Camera *cam = (V4l2Camera *)calloc(1, sizeof(V4l2Camera));
  cam->fd = fd;
  cam->width = fmt.fmt.pix.width;
  cam->height = fmt.fmt.pix.height;
  cam->pixfmt = fmt.fmt.pix.pixelformat;
  cam->streaming = 0;
  cam->frame_index = -1;

  return cam;
}

/// Get the actual negotiated resolution.
void cleona_v4l2_get_size(void *handle, int *width, int *height,
                           uint32_t *pixfmt) {
  V4l2Camera *cam = (V4l2Camera *)handle;
  if (!cam) return;
  *width = cam->width;
  *height = cam->height;
  *pixfmt = cam->pixfmt;
}

/// Start streaming (mmap buffers + STREAMON).
/// Returns 0 on success.
int cleona_v4l2_start(void *handle) {
  V4l2Camera *cam = (V4l2Camera *)handle;
  if (!cam || cam->streaming) return -1;

  // Request buffers
  struct v4l2_requestbuffers req;
  memset(&req, 0, sizeof(req));
  req.count = NUM_BUFFERS;
  req.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  req.memory = V4L2_MEMORY_MMAP;

  if (xioctl(cam->fd, VIDIOC_REQBUFS, &req) < 0 || req.count < 2) {
    return -2;
  }
  cam->n_buffers = req.count;

  // Map buffers
  for (int i = 0; i < cam->n_buffers; i++) {
    struct v4l2_buffer buf;
    memset(&buf, 0, sizeof(buf));
    buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    buf.memory = V4L2_MEMORY_MMAP;
    buf.index = i;

    if (xioctl(cam->fd, VIDIOC_QUERYBUF, &buf) < 0) return -3;

    cam->buffers[i].length = buf.length;
    cam->buffers[i].start = mmap(NULL, buf.length, PROT_READ | PROT_WRITE,
                                  MAP_SHARED, cam->fd, buf.m.offset);
    if (cam->buffers[i].start == MAP_FAILED) return -4;

    // Queue buffer
    if (xioctl(cam->fd, VIDIOC_QBUF, &buf) < 0) return -5;
  }

  // Start streaming
  int type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  if (xioctl(cam->fd, VIDIOC_STREAMON, &type) < 0) return -6;

  cam->streaming = 1;
  return 0;
}

/// Grab the latest frame. Non-blocking.
/// Returns pointer to frame data + size, or NULL if no frame ready.
/// The frame data is valid until the next call to grab_frame or stop.
/// The frame is in the camera's native pixel format (see get_size).
const uint8_t *cleona_v4l2_grab_frame(void *handle, int *out_size) {
  V4l2Camera *cam = (V4l2Camera *)handle;
  if (!cam || !cam->streaming) return NULL;

  // Requeue previous buffer if any
  if (cam->frame_index >= 0) {
    struct v4l2_buffer buf;
    memset(&buf, 0, sizeof(buf));
    buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    buf.memory = V4L2_MEMORY_MMAP;
    buf.index = cam->frame_index;
    xioctl(cam->fd, VIDIOC_QBUF, &buf);
    cam->frame_index = -1;
  }

  // Dequeue next buffer (non-blocking)
  struct v4l2_buffer buf;
  memset(&buf, 0, sizeof(buf));
  buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  buf.memory = V4L2_MEMORY_MMAP;

  if (xioctl(cam->fd, VIDIOC_DQBUF, &buf) < 0) {
    if (errno == EAGAIN) return NULL; // no frame yet
    return NULL; // error
  }

  cam->frame_index = buf.index;
  cam->frame_data = (uint8_t *)cam->buffers[buf.index].start;
  cam->frame_size = buf.bytesused;

  *out_size = cam->frame_size;
  return cam->frame_data;
}

/// Convert YUYV frame to I420.
/// Input: YUYV data (width*height*2 bytes)
/// Output: I420 data (width*height*3/2 bytes, caller-provided buffer)
void cleona_v4l2_yuyv_to_i420(const uint8_t *yuyv, uint8_t *i420,
                                int width, int height) {
  int y_size = width * height;
  uint8_t *y = i420;
  uint8_t *u = i420 + y_size;
  uint8_t *v = u + y_size / 4;

  for (int row = 0; row < height; row++) {
    const uint8_t *src = yuyv + row * width * 2;
    uint8_t *y_row = y + row * width;

    for (int col = 0; col < width; col += 2) {
      y_row[col]     = src[col * 2];
      y_row[col + 1] = src[col * 2 + 2];

      if (row % 2 == 0) {
        int uv_idx = (row / 2) * (width / 2) + col / 2;
        u[uv_idx] = src[col * 2 + 1];
        v[uv_idx] = src[col * 2 + 3];
      }
    }
  }
}

/// Stop streaming.
int cleona_v4l2_stop(void *handle) {
  V4l2Camera *cam = (V4l2Camera *)handle;
  if (!cam || !cam->streaming) return -1;

  int type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  xioctl(cam->fd, VIDIOC_STREAMOFF, &type);
  cam->streaming = 0;
  cam->frame_index = -1;

  // Unmap buffers
  for (int i = 0; i < cam->n_buffers; i++) {
    if (cam->buffers[i].start && cam->buffers[i].start != MAP_FAILED) {
      munmap(cam->buffers[i].start, cam->buffers[i].length);
    }
    cam->buffers[i].start = NULL;
  }
  cam->n_buffers = 0;

  return 0;
}

/// Close camera and free resources.
void cleona_v4l2_close(void *handle) {
  V4l2Camera *cam = (V4l2Camera *)handle;
  if (!cam) return;
  if (cam->streaming) cleona_v4l2_stop(cam);
  if (cam->fd >= 0) close(cam->fd);
  free(cam);
}

/// List available V4L2 camera devices.
/// out_paths: array of char* (caller provides array of MAX_DEVICES pointers)
/// Returns number of devices found.
int cleona_v4l2_list_devices(char **out_paths, int max_count) {
  int count = 0;
  char path[32];
  for (int i = 0; i < 16 && count < max_count; i++) {
    snprintf(path, sizeof(path), "/dev/video%d", i);
    int fd = open(path, O_RDWR);
    if (fd < 0) continue;

    struct v4l2_capability cap;
    if (xioctl(fd, VIDIOC_QUERYCAP, &cap) == 0 &&
        (cap.capabilities & V4L2_CAP_VIDEO_CAPTURE)) {
      out_paths[count] = strdup(path);
      count++;
    }
    close(fd);
  }
  return count;
}

/// Free device path strings from list_devices.
void cleona_v4l2_free_device_list(char **paths, int count) {
  for (int i = 0; i < count; i++) {
    free(paths[i]);
    paths[i] = NULL;
  }
}

/// Check if V4L2 capture is available (any camera device).
int cleona_v4l2_available(void) {
  char path[32];
  for (int i = 0; i < 8; i++) {
    snprintf(path, sizeof(path), "/dev/video%d", i);
    int fd = open(path, O_RDWR);
    if (fd < 0) continue;

    struct v4l2_capability cap;
    int ok = (xioctl(fd, VIDIOC_QUERYCAP, &cap) == 0 &&
              (cap.capabilities & V4L2_CAP_VIDEO_CAPTURE));
    close(fd);
    if (ok) return 0;
  }
  return -1;
}

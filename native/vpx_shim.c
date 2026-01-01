/// Thin C shim for libvpx VP8 encoder/decoder.
/// Hides complex struct handling behind a simple opaque-pointer API.
/// All libvpx structs are treated as opaque byte buffers with patched offsets.
///
/// Build: gcc -shared -fPIC -O2 -o libcleona_vpx.so vpx_shim.c -ldl

#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <dlfcn.h>

// ── Opaque types ────────────────────────────────────────────────────

// All libvpx structs are opaque buffers of sufficient size.
// Field offsets determined empirically from libvpx 1.14.0 on x86_64 Linux.
#define VPX_CTX_SIZE 256
#define VPX_CFG_SIZE 2048
#define VPX_IMG_SIZE 512

// enc_cfg field offsets (in bytes) — libvpx 1.14.0, x86_64
#define CFG_G_USAGE          0
#define CFG_G_THREADS        4
#define CFG_G_PROFILE        8
#define CFG_G_W             12
#define CFG_G_H             16
// [20] g_bit_depth=8, [24] g_input_bit_depth=8 (libvpx 1.14 extras)
#define CFG_G_TIMEBASE_NUM  28
#define CFG_G_TIMEBASE_DEN  32
#define CFG_G_ERROR_RESIL   36
#define CFG_G_PASS          40
#define CFG_G_LAG_FRAMES   44
#define CFG_RC_TARGET_BR   112   // rc_target_bitrate (default 256)
#define CFG_RC_END_USAGE   108   // rc_end_usage (0=VBR, 1=CBR)
#define CFG_KF_MODE        160   // kf_mode (1=auto)
#define CFG_KF_MIN_DIST    164   // kf_min_dist
#define CFG_KF_MAX_DIST    168   // kf_max_dist (default 128)

// vpx_image_t field offsets (bytes)
#define IMG_FMT       0
#define IMG_W        12    // allocated width
#define IMG_H        16    // allocated height
#define IMG_D_W      24    // display width
#define IMG_D_H      28    // display height
#define IMG_PLANES   48    // planes[4]: 4 pointers (32 bytes on 64-bit)
#define IMG_STRIDE   80    // stride[4]: 4 ints (16 bytes)

// vpx_codec_cx_pkt_t offsets
#define PKT_KIND      0
#define PKT_FRAME_BUF 8    // data.frame.buf (pointer)
#define PKT_FRAME_SZ 16    // data.frame.sz (size_t)
#define PKT_FRAME_FL 40    // data.frame.flags

// Constants
#define VPX_IMG_FMT_I420   0x102
#define VPX_CODEC_CX_FRAME_PKT 0
#define VPX_FRAME_IS_KEY   0x01
#define VPX_EFLAG_FORCE_KF (1 << 0)
#define VPX_DL_REALTIME    1
#define VPX_RC_CBR         1
#define VPX_KF_AUTO        1
#define VPX_CODEC_OK       0
#define VP8E_SET_CPUUSED       13
#define VP8E_SET_NOISE_SENS    15
#define MY_VPX_ENC_ABI    1
#define MY_VPX_DEC_ABI    1

// ── Function pointer types ──────────────────────────────────────────

typedef void *vpx_iface_ptr;
typedef int vpx_err;

typedef vpx_iface_ptr (*fn_vp8_cx)(void);
typedef vpx_iface_ptr (*fn_vp8_dx)(void);
typedef vpx_err (*fn_enc_cfg_default)(vpx_iface_ptr, void *, unsigned int);
typedef vpx_err (*fn_enc_init)(void *, vpx_iface_ptr, void *, long, int);
typedef vpx_err (*fn_encode)(void *, const void *, int64_t, unsigned long,
                             unsigned long, unsigned long);
typedef const void *(*fn_get_cx_data)(void *, void **);
typedef vpx_err (*fn_dec_init)(void *, vpx_iface_ptr, void *, long, int);
typedef vpx_err (*fn_decode)(void *, const uint8_t *, unsigned int, void *, long);
typedef void *(*fn_get_frame)(void *, void **);
typedef vpx_err (*fn_destroy)(void *);
typedef void *(*fn_img_alloc)(void *, int, unsigned int, unsigned int, unsigned int);
typedef void (*fn_img_free)(void *);
typedef vpx_err (*fn_control)(void *, int, ...);

// ── Loaded function pointers ────────────────────────────────────────

static void *g_lib = NULL;
static fn_vp8_cx        f_vp8_cx;
static fn_vp8_dx        f_vp8_dx;
static fn_enc_cfg_default f_enc_cfg;
static fn_enc_init      f_enc_init;
static fn_encode        f_encode;
static fn_get_cx_data   f_get_cx;
static fn_dec_init      f_dec_init;
static fn_decode        f_decode;
static fn_get_frame     f_get_frame;
static fn_destroy       f_destroy;
static fn_img_alloc     f_img_alloc;
static fn_img_free      f_img_free;
static fn_control       f_control;

static int load_vpx(void) {
  if (g_lib) return 0;
  const char *names[] = {
    "libvpx.so.9", "libvpx.so.8", "libvpx.so.7", "libvpx.so",
    "/usr/lib/x86_64-linux-gnu/libvpx.so.9",
    "/lib/x86_64-linux-gnu/libvpx.so.9",
    NULL
  };
  for (int i = 0; names[i]; i++) {
    g_lib = dlopen(names[i], RTLD_NOW);
    if (g_lib) break;
  }
  if (!g_lib) return -1;

  f_vp8_cx    = (fn_vp8_cx)dlsym(g_lib, "vpx_codec_vp8_cx");
  f_vp8_dx    = (fn_vp8_dx)dlsym(g_lib, "vpx_codec_vp8_dx");
  f_enc_cfg   = (fn_enc_cfg_default)dlsym(g_lib, "vpx_codec_enc_config_default");
  f_enc_init  = (fn_enc_init)dlsym(g_lib, "vpx_codec_enc_init_ver");
  f_encode    = (fn_encode)dlsym(g_lib, "vpx_codec_encode");
  f_get_cx    = (fn_get_cx_data)dlsym(g_lib, "vpx_codec_get_cx_data");
  f_dec_init  = (fn_dec_init)dlsym(g_lib, "vpx_codec_dec_init_ver");
  f_decode    = (fn_decode)dlsym(g_lib, "vpx_codec_decode");
  f_get_frame = (fn_get_frame)dlsym(g_lib, "vpx_codec_get_frame");
  f_destroy   = (fn_destroy)dlsym(g_lib, "vpx_codec_destroy");
  f_img_alloc = (fn_img_alloc)dlsym(g_lib, "vpx_img_alloc");
  f_img_free  = (fn_img_free)dlsym(g_lib, "vpx_img_free");
  f_control   = (fn_control)dlsym(g_lib, "vpx_codec_control_");

  if (!f_vp8_cx || !f_enc_cfg || !f_enc_init || !f_encode || !f_get_cx ||
      !f_destroy || !f_vp8_dx || !f_dec_init || !f_decode || !f_get_frame ||
      !f_img_alloc || !f_img_free) {
    dlclose(g_lib); g_lib = NULL; return -2;
  }
  return 0;
}

// ── Helper: read/write uint32 at byte offset in buffer ──────────────

static inline uint32_t rd32(const void *buf, int off) {
  uint32_t v; memcpy(&v, (const char *)buf + off, 4); return v;
}
static inline void wr32(void *buf, int off, uint32_t v) {
  memcpy((char *)buf + off, &v, 4);
}
static inline uint8_t **rd_ptr_array(void *buf, int off) {
  return (uint8_t **)((char *)buf + off);
}
static inline int *rd_int_array(void *buf, int off) {
  return (int *)((char *)buf + off);
}

// ── Encoder context ─────────────────────────────────────────────────

typedef struct {
  char codec[VPX_CTX_SIZE];
  char cfg[VPX_CFG_SIZE];
  char raw[VPX_IMG_SIZE];
  int width;
  int height;
  int64_t frame_count;
} VpxEncoder;

// ── Decoder context ─────────────────────────────────────────────────

typedef struct {
  char codec[VPX_CTX_SIZE];
  int initialized;
} VpxDecoder;

// ── Public API ──────────────────────────────────────────────────────

void *cleona_vpx_encoder_create(int width, int height,
                                 int bitrate_kbps, int fps,
                                 int keyframe_interval) {
  if (load_vpx() != 0) return NULL;

  VpxEncoder *enc = (VpxEncoder *)calloc(1, sizeof(VpxEncoder));
  if (!enc) return NULL;

  enc->width = width;
  enc->height = height;
  enc->frame_count = 0;

  vpx_iface_ptr iface = f_vp8_cx();
  if (!iface) { free(enc); return NULL; }

  vpx_err res = f_enc_cfg(iface, enc->cfg, 0);
  if (res != VPX_CODEC_OK) { free(enc); return NULL; }

  // Patch config fields at known offsets
  wr32(enc->cfg, CFG_G_W, width);
  wr32(enc->cfg, CFG_G_H, height);
  wr32(enc->cfg, CFG_G_TIMEBASE_NUM, 1);
  wr32(enc->cfg, CFG_G_TIMEBASE_DEN, fps);
  wr32(enc->cfg, CFG_RC_TARGET_BR, bitrate_kbps);
  wr32(enc->cfg, CFG_RC_END_USAGE, VPX_RC_CBR);
  wr32(enc->cfg, CFG_G_ERROR_RESIL, 1);
  wr32(enc->cfg, CFG_G_LAG_FRAMES, 0);
  wr32(enc->cfg, CFG_G_THREADS, 2);
  wr32(enc->cfg, CFG_KF_MODE, VPX_KF_AUTO);
  wr32(enc->cfg, CFG_KF_MIN_DIST, 0);
  wr32(enc->cfg, CFG_KF_MAX_DIST, keyframe_interval);

  res = f_enc_init(enc->codec, iface, enc->cfg, 0, MY_VPX_ENC_ABI);
  if (res != VPX_CODEC_OK) { free(enc); return NULL; }

  // Real-time speed preset
  if (f_control) {
    f_control(enc->codec, VP8E_SET_CPUUSED, 8);
    f_control(enc->codec, VP8E_SET_NOISE_SENS, 1);
  }

  // Allocate I420 image
  if (!f_img_alloc(enc->raw, VPX_IMG_FMT_I420, width, height, 16)) {
    f_destroy(enc->codec);
    free(enc);
    return NULL;
  }

  return enc;
}

int cleona_vpx_encoder_encode(void *handle, const uint8_t *i420_data,
                               int force_keyframe,
                               const uint8_t **out_data, int *out_size,
                               int *out_is_keyframe) {
  VpxEncoder *enc = (VpxEncoder *)handle;
  if (!enc || !i420_data || !out_data || !out_size) return -1;

  *out_data = NULL;
  *out_size = 0;
  *out_is_keyframe = 0;

  int w = enc->width, h = enc->height;
  int y_size = w * h;
  int uv_size = y_size / 4;

  // Copy I420 data into vpx_image planes
  uint8_t **planes = rd_ptr_array(enc->raw, IMG_PLANES);
  int *stride = rd_int_array(enc->raw, IMG_STRIDE);

  // Y plane
  for (int row = 0; row < h; row++)
    memcpy(planes[0] + row * stride[0], i420_data + row * w, w);
  // U plane
  int uv_h = h / 2, uv_w = w / 2;
  for (int row = 0; row < uv_h; row++)
    memcpy(planes[1] + row * stride[1], i420_data + y_size + row * uv_w, uv_w);
  // V plane
  for (int row = 0; row < uv_h; row++)
    memcpy(planes[2] + row * stride[2], i420_data + y_size + uv_size + row * uv_w, uv_w);

  unsigned long flags = force_keyframe ? VPX_EFLAG_FORCE_KF : 0;
  vpx_err res = f_encode(enc->codec, enc->raw, enc->frame_count++, 1,
                          flags, VPX_DL_REALTIME);
  if (res != VPX_CODEC_OK) return -1;

  // Get output packet
  void *iter = NULL;
  const void *pkt;
  while ((pkt = f_get_cx(enc->codec, &iter)) != NULL) {
    if (rd32(pkt, PKT_KIND) == VPX_CODEC_CX_FRAME_PKT) {
      void *buf_ptr;
      memcpy(&buf_ptr, (const char *)pkt + PKT_FRAME_BUF, sizeof(void *));
      size_t sz;
      memcpy(&sz, (const char *)pkt + PKT_FRAME_SZ, sizeof(size_t));
      uint32_t fl = rd32(pkt, PKT_FRAME_FL);

      *out_data = (const uint8_t *)buf_ptr;
      *out_size = (int)sz;
      *out_is_keyframe = (fl & VPX_FRAME_IS_KEY) ? 1 : 0;
      return 0;
    }
  }
  return 1; // no packet (buffering)
}

int cleona_vpx_encoder_set_bitrate(void *handle, int bitrate_kbps) {
  VpxEncoder *enc = (VpxEncoder *)handle;
  if (!enc) return -1;
  wr32(enc->cfg, CFG_RC_TARGET_BR, bitrate_kbps);
  return 0;
}

void cleona_vpx_encoder_get_size(void *handle, int *width, int *height) {
  VpxEncoder *enc = (VpxEncoder *)handle;
  if (enc) { *width = enc->width; *height = enc->height; }
}

void cleona_vpx_encoder_destroy(void *handle) {
  VpxEncoder *enc = (VpxEncoder *)handle;
  if (!enc) return;
  f_img_free(enc->raw);
  f_destroy(enc->codec);
  free(enc);
}

void *cleona_vpx_decoder_create(void) {
  if (load_vpx() != 0) return NULL;

  VpxDecoder *dec = (VpxDecoder *)calloc(1, sizeof(VpxDecoder));
  if (!dec) return NULL;

  vpx_iface_ptr iface = f_vp8_dx();
  if (!iface) { free(dec); return NULL; }

  vpx_err res = f_dec_init(dec->codec, iface, NULL, 0, MY_VPX_DEC_ABI);
  if (res != VPX_CODEC_OK) { free(dec); return NULL; }

  dec->initialized = 1;
  return dec;
}

int cleona_vpx_decoder_decode(void *handle, const uint8_t *data, int size,
                               uint8_t *out_i420, int out_buf_size,
                               int *out_width, int *out_height) {
  VpxDecoder *dec = (VpxDecoder *)handle;
  if (!dec || !dec->initialized || !data || size <= 0) return -1;

  *out_width = 0;
  *out_height = 0;

  vpx_err res = f_decode(dec->codec, data, size, NULL, 0);
  if (res != VPX_CODEC_OK) return -1;

  void *iter = NULL;
  void *img = f_get_frame(dec->codec, &iter);
  if (!img) return 1;

  int w = (int)rd32(img, IMG_D_W);
  int h = (int)rd32(img, IMG_D_H);
  int y_size = w * h;
  int uv_size = y_size / 4;
  int total = y_size + uv_size * 2;
  if (out_buf_size < total) return -1;

  *out_width = w;
  *out_height = h;

  uint8_t **planes = rd_ptr_array(img, IMG_PLANES);
  int *stride = rd_int_array(img, IMG_STRIDE);

  // Copy Y
  for (int row = 0; row < h; row++)
    memcpy(out_i420 + row * w, planes[0] + row * stride[0], w);
  // Copy U
  int uv_h = h / 2, uv_w = w / 2;
  for (int row = 0; row < uv_h; row++)
    memcpy(out_i420 + y_size + row * uv_w, planes[1] + row * stride[1], uv_w);
  // Copy V
  for (int row = 0; row < uv_h; row++)
    memcpy(out_i420 + y_size + uv_size + row * uv_w, planes[2] + row * stride[2], uv_w);

  return 0;
}

void cleona_vpx_decoder_destroy(void *handle) {
  VpxDecoder *dec = (VpxDecoder *)handle;
  if (!dec) return;
  if (dec->initialized) f_destroy(dec->codec);
  free(dec);
}

int cleona_vpx_available(void) {
  return load_vpx();
}

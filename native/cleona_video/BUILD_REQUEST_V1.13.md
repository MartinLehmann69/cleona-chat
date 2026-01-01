# STATUS NOTE — V1.13 (Linux video backend), interrupted mid-package

**This is not a finished BUILD_REQUEST.** Session budget ran out while V1.13
was still in progress. This file is the handoff a follow-up session needs —
what exists, what was verified, what was NOT verified, and what to do next.
Read this before touching `native/cleona_video/linux/**` again.

**Package status: NOT acceptance-ready.** The conformance test has never been
run against this backend. `scripts/preflight.sh` and `dart analyze` have not
been run in this worktree for this package. Do not report this package as
done based on this file — it is the opposite of that.

---

## 1. What exists and compiles

`native/cleona_video/linux/`:
- `h264_bitstream.h/.c` — Annex-B bit reader/writer, SPS/PPS/slice-header
  parse and emit. **Verified correct** by a standalone round-trip test (build
  it and run it — see §5) and by cross-checking byte-for-byte against
  ffmpeg's own `h264_vaapi` encoder output via `LIBVA_TRACE=1` (identical SPS
  bytes for every field this backend controls). This file is solid.
- `v4l2_capture.h/.c` — V4L2 camera capture, YUYV at the camera's native max
  size, nearest-neighbour downscale to NV12. **Verified working** against the
  real webcam on this dev machine (`/dev/video0`, "Integrated_Webcam_FHD",
  YUYV up to 640x480@30). This file is solid.
- `cleona_video_linux.c` — the ABI glue: V4L2 capture → VAAPI EncSliceLP
  encode → Annex-B, and Annex-B → VAAPI VLD decode. **Compiles clean, zero
  warnings** (`gcc -std=gnu11 -Wall -Wextra`, verified in this session — see
  the exact command in §5). **Never linked into a full binary, never run,
  never tested.** Written against everything learned in §2-3 below but not
  yet exercised end to end as a whole.
- `CMakeLists.txt` — standalone build, host-guarded (`if(ANDROID) return()`),
  pkg-config against `libva`/`libva-drm`. **Never actually invoked** — cmake
  was not run against it in this session. It should work given §4's dev-env
  workaround, but has zero mileage.

## 2. What was verified about the hardware, empirically, on this dev machine

Confirmed via a throwaway VAAPI probe program (not checked in, was in
`/tmp/.../scratchpad/vaenc/`, gone with the session):

- GPU: Intel UHD 630 (Coffee Lake-H), driver **iHD 24.1.0**, VA-API 1.20, at
  `/dev/dri/renderD128`.
- `VAProfileH264ConstrainedBaseline` / `VAProfileH264Main` /
  `VAProfileH264High` all report entrypoints **`{VAEntrypointVLD,
  VAEntrypointEncSliceLP}`** — NOT `VAEntrypointEncSlice` (the "normal",
  textbook VAAPI encode entrypoint). This SoC generation only exposes the
  low-power VDEnc path for encode. `hardware_encode=1`/`hardware_decode=1` is
  real and defensible for a report **if** the rest of the package earns it.
- Within `VAEntrypointEncSliceLP`, `vaGetConfigAttributes(..., 
  VAConfigAttribRateControl, ...)` returns **only `VA_RC_CQP`** — CBR/VBR are
  not in the mask. `cleona_video_linux.c` therefore runs its own QP-feedback
  loop on top of hardware CQP encode (see the file's own doc comment) instead
  of relying on a hardware bitrate governor. This is a genuine hardware/driver
  limit on this SoC, confirmed by directly querying the attribute — not
  assumed.
- **This driver does NOT auto-generate SPS/PPS at the LP entrypoint.** Without
  a packed-header submission, the coded buffer contains only slice NALs (no
  type 7/8 at all). Confirmed by scanning the raw coded-buffer bytes for
  Annex-B start codes.
- `VAConfigAttribEncPackedHeaders` reports full support
  (`SEQUENCE|PICTURE|SLICE|MISC|RAW_DATA`, mask `0x1f`).
- **Working technique, cross-verified against ffmpeg's own `h264_vaapi`
  encoder via `LIBVA_TRACE=1 LIBVA_TRACE_BUFDATA=1`:** submit the SPS and PPS
  RBSP **concatenated into ONE `VAEncPackedHeaderSequence` buffer** (both NALs
  back to back, each with its own start code), not as two separate
  Sequence+Picture packed headers. ffmpeg's own trace shows exactly this
  shape: its second packed header (type=RawData) is an unrelated SEI, and its
  real SPS+PPS both live inside the type=Sequence data buffer. This is
  implemented in `cvl_encode_one_locked()` (`cleona_video_linux.c`) and is the
  one non-obvious VAAPI fact this package cost the most time to find.
- Camera: `/dev/video0` (uvcvideo, "Integrated_Webcam_FHD") offers MJPG up to
  1920x1080@30 and uncompressed YUYV up to **640x480@30**. This backend
  captures YUYV only (no JPEG decode dependency — see `v4l2_capture.h`'s file
  doc for the reasoning) and negotiates down from there, rounding to
  macroblock (16px) alignment so no SPS cropping fields are needed.

## 3. UNRESOLVED — the reason this package is not done

**`cleona_video_linux.c`'s encoder produces an Annex-B stream that this
backend's own `h264_bitstream.c` parser AND `ffprobe` both parse correctly at
the SPS level** (profile=Baseline/Constrained Baseline, correct width/height
recovered independently) **but ffmpeg's reference software H.264 decoder
fails starting at the first inter (P) frame**, reporting `reference count
overflow` / `illegal reordering_of_pic_nums_idc`, escalating to macroblock-
level garbage on later frames.

What was ruled out, methodically, with evidence (do not re-derive these —
start past them):
- **Not the SPS bytes.** Verified three independent ways: (a) a standalone
  reproduction of the exact SPS-building code path (`spscheck.c`, not
  committed) computes the expected 8-byte RBSP and matches by hand-trace bit
  for bit; (b) `ffprobe` parses profile/level/resolution from the real
  encoder's output correctly; (c) LIBVA_TRACE field-by-field comparison
  against ffmpeg's own `VAEncSequenceParameterBufferH264` for the identical
  configuration matches on every field this backend sets
  (`log2_max_frame_num_minus4=4`, `pic_order_cnt_type=2`,
  `max_num_ref_frames=1`, `chroma_format_idc=1`, `frame_mbs_only_flag=1`,
  `direct_8x8_inference_flag=1`).
- **Not the PPS bytes.** Same field-by-field comparison; only
  `pic_init_qp` differs (expected — different QP values), everything
  structural matches.
- **Not the packed-header submission shape** — fixed already (§2), and
  confirmed the fix changed observable behaviour (moved the failure from
  "wrong PPS entirely missing" to the current "reference count overflow").
- **Substituting ffmpeg's own byte-identical SPS+PPS (captured via
  LIBVA_TRACE, hardcoded into a diagnostic build) in place of this
  backend's, while keeping this backend's own hardware-generated slices
  unchanged, made the `reference count overflow` / `reordering` class of
  error DISAPPEAR** (ffprobe then read `profile=Constrained Baseline`
  correctly and the failure moved to macroblock-level decode errors instead).
  This proves the bug is specifically in **this backend's own constructed
  SPS or PPS bytes** in a way that individual field comparison did not catch
  — most likely a subtle difference in a field whose *effect* only shows up
  in how the hardware-generated slice header/data was built around it (i.e.
  the mismatch might not be a byte typo but a genuine semantic disagreement
  between what this file tells the `VAEncSequenceParameterBufferH264`/
  `VAEncPictureParameterBufferH264` structs — which the driver uses to
  generate the ACTUAL slice bitstream — and what this file's own hand-built
  SPS/PPS packed-header bytes claim). **This is the lead the next session
  should chase first**: dump this backend's OWN struct field values via
  `LIBVA_TRACE=1 LIBVA_TRACE_BUFDATA=1 ./your_test_binary` (see §5 for how)
  and diff every field against the ffmpeg trace referenced above, not just
  the ones already checked.
- A same-session hardware-decode round trip (this backend's own VAAPI VLD
  decode, fed this backend's own encoder output within the same process) was
  **written but never successfully tested** before the session ended — the
  `decode_probe.c` throwaway test needed a real slice-header bit-offset
  computation this session ran out of time to wire up correctly before
  budget ran out. **This is the single most valuable next experiment**: if
  hardware decode (same driver, possibly more tolerant/self-consistent with
  its own encode quirks than ffmpeg's independent software decoder) round-
  trips cleanly, that satisfies the conformance harness's actual requirement
  (V22 only ever decodes what the same session encoded) even before the
  ffmpeg-interop question is resolved — and the ffmpeg discrepancy becomes a
  narrower, separately-trackable interop gap rather than a total blocker.

**Do not ship or report `hardware_encode=1`/`hardware_decode=1` with a
"conformance green" claim until at minimum the same-session round trip
(`cleona_video_read_encoded` → `cleona_video_submit_encoded` on the SAME
session) is proven, ideally via the real conformance test.**

## 4. Dev environment workaround (this sandbox has no sudo)

`libva-dev`, `libva-drm2`'s pkg-config files and `libdrm-dev` are not
installed and `sudo apt install` needs a password this session does not have.
Worked around with:

```bash
mkdir -p /tmp/.../scratchpad/apt-dl && cd /tmp/.../scratchpad/apt-dl
apt-get download libva-dev libdrm-dev   # download only, no root needed
mkdir -p /tmp/.../scratchpad/local-prefix
dpkg-deb -x libva-dev_*.deb /tmp/.../scratchpad/local-prefix
dpkg-deb -x libdrm-dev_*.deb /tmp/.../scratchpad/local-prefix

# pkg-config's .pc files hard-code prefix=/usr, so PKG_CONFIG_PATH alone
# is not enough -- PKG_CONFIG_SYSROOT_DIR redirects every emitted -I/-L too:
export PKG_CONFIG_PATH="/tmp/.../scratchpad/local-prefix/usr/lib/x86_64-linux-gnu/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="/tmp/.../scratchpad/local-prefix"
pkg-config --cflags --libs libva libva-drm   # now resolves into local-prefix
```

The runtime `.so.2` files (`libva.so.2`, `libva-drm.so.2`, `libdrm.so.2`) are
already present system-wide (the non-dev runtime packages `libva2`,
`libva-drm2`, `libdrm2` are installed) — only the headers, `.pc` files and
unversioned `.so` symlinks were missing, and the unversioned symlinks were
recreated locally pointing at the real system `.so.2` files.

**This is purely a local dev-environment workaround, not something to bake
into the repo.** A real dev machine or CI image needs `libva-dev`,
`libva-drm2`, `libdrm-dev` installed normally (`apt install libva-dev
libdrm-dev`) — this is the actual build request for V0.5/V1.8 once this
package is otherwise ready:

**Requested (not yet — package isn't ready to make this request "for real"
until §3 is resolved, recorded here so it isn't lost):**
- `libva-dev`, `libdrm-dev` as Linux build-time dependencies (headers only —
  the runtime `.so`s this backend links against, `libva.so.2`/
  `libva-drm.so.2`/`libdrm.so.2`, are ordinary Mesa/VAAPI runtime packages
  already present on any desktop Linux with `intel-media-va-driver` or
  equivalent installed — same "dynamic, not vendored" shape as V1.1's
  PipeWire/WebRTC-APM dependencies, see that package's own
  `BUILD_REQUEST_V1.1.md` §2 for the precedent).
- `linux/CMakeLists.txt` wiring, matching V1.1's request exactly in shape
  (add_subdirectory + install(TARGETS cleona_video ...)) — template already
  in `native/cleona_video/BUILD_REQUEST.md` §2 (V0.3's request, still open).

## 5. Exact commands the next session needs

```bash
# Standalone RBSP writer/reader round-trip sanity (rewrite this test file —
# it lived in scratchpad and is gone; the code it tests, h264_bitstream.c, is
# solid and committed):
#   build a small main() that calls h264_bw_put_* to build a Baseline SPS/PPS
#   (profile=66, level=30, sps_id=0, log2_max_frame_num_minus4=4,
#   pic_order_cnt_type=2, max_num_ref_frames=1, width/height in MBs,
#   frame_mbs_only=1, direct_8x8=1, no cropping, no VUI), then
#   h264_annexb_wrap, then h264_ebsp_to_rbsp + h264_parse_sps back, assert the
#   fields match. This exact sequence was verified working in this session.

# Local dev headers (see §4):
export PKG_CONFIG_PATH="<local-prefix>/usr/lib/x86_64-linux-gnu/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="<local-prefix>"

# Build this package standalone:
cmake -S native/cleona_video/linux -B build/video_linux
cmake --build build/video_linux -j

# Build the mock + conformance harness (unrelated tree, no dependency on the
# above):
cmake -S native/cleona_video -B build/video -DCLEONA_VIDEO_BUILD_SMOKE=OFF
cmake --build build/video -j

# Run the REAL conformance test against this backend (route A, see
# native/cleona_video/test/CMakeLists.txt's own top comment):
./build/video/test/cleona_video_conformance_loader \
    build/video_linux/libcleona_video.so --shipping

# Trace-compare against ffmpeg's own vaapi encoder to keep chasing §3:
LIBVA_TRACE=1 LIBVA_TRACE_BUFDATA=1 ffmpeg -y -f v4l2 -input_format yuyv422 \
  -video_size 640x480 -framerate 30 -i /dev/video0 -frames:v 5 \
  -c:v h264_vaapi -vaapi_device /dev/dri/renderD128 -vf 'format=nv12,hwupload' \
  -profile:v constrained_baseline -low_power 1 -bf 0 -g 30 -f h264 ref.h264
# then grep the resulting trace file (1.<pid>.thd-...) in the CWD for
# VAEncSequenceParameterBufferH264 / VAEncPictureParameterBufferH264 /
# VAEncSliceParameterBufferH264 and diff field by field against a
# LIBVA_TRACE=1-wrapped run of this backend's own test binary.
```

## 6. Not yet touched / gates not run

- `scripts/preflight.sh` — not run in this worktree.
- `dart analyze` against the 21/0/0 baseline — not run (nothing Dart-side was
  touched by this package anyway; `lib/core/calls/video_pipeline.dart` is
  V0.3's file, not this package's).
- `smoke_video_calls.dart` / any Dart smoke — not touched, not run.
- Negative control (deliberately fail the conformance test and show it
  catches it) — not run. `native/cleona_video/test/CMakeLists.txt` already
  has a `cleona_video_saboteur` target with five pre-built negative controls
  (`oversize`, `pts_from_index`, `capture_closed`, `no_h264`,
  `open_err_swap`) wired to `ctest` — running `ctest --test-dir build/video`
  once the tree above is built exercises them against the MOCK and is
  probably sufficient evidence for the "negative control" gate without this
  package needing to write a new one; confirm this reasoning holds before
  relying on it, it was not re-verified in this session.
- `git add -A` was NOT used anywhere in this session — only this package's
  own files were touched. Confirmed no other package's files are modified.

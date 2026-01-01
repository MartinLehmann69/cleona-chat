# BUILD_REQUEST — `native/cleona_voice/linux` → work package V0.5 (build ownership)

**From:** V1.1 (Linux voice backend, PipeWire)
**To:** V0.5 / V1.8 — owner of all build and CI files (SPEC §9)
**Status:** open, non-blocking. Nothing here fails `scripts/preflight.sh` on this
branch — the real backend exists but is not yet reachable from
`flutter build linux`, exactly the state `linux/CMakeLists.txt:72-93` already
anticipated and left a placeholder comment for.

V1.1 owns `native/cleona_voice/linux/**` (three source files + this package's
own `CMakeLists.txt`) and nothing else. `linux/CMakeLists.txt` (the Flutter
Linux runner's build) lies outside that set and was deliberately **not**
edited here.

---

## 1. `linux/CMakeLists.txt` — wire in the real backend

Lines 72-93 already carry the exact snippet this request is asking for,
written by whoever did V0.5/V0.2's build-ownership pass, anticipating this
package by name:

```cmake
# === cleona_voice / cleona_video — NOT wired in yet, deliberately ===
...
# Wire this up when the real backend lands, not before:
#   voice (V1.1, PipeWire):  add_subdirectory("${CMAKE_SOURCE_DIR}/../native/cleona_voice" "${CMAKE_BINARY_DIR}/cleona_voice_build")
#                            install the `cleona_voice` target (NOT `cleona_voice_mock`)
#                            into ${INSTALL_BUNDLE_LIB_DIR}, same pattern as cleona_audio/cleona_net below.
```

The real backend has landed. This package's CMake target is named exactly
`cleona_voice` (`native/cleona_voice/linux/CMakeLists.txt`) — matching that
comment on purpose, so this request is literally "uncomment and adapt", not
"reconcile a name". Two changes:

**(a)** Replace the comment block (lines 72-93) with:

```cmake
# === cleona_voice (libcleona_voice.so) — V1.1, PipeWire ===
# Built from native/cleona_voice/, installed into bundle/lib/ for FFI loading.
# Same install pattern as cleona_audio/cleona_net: the install(TARGETS)
# directive lives further down, after the bundle REMOVE_RECURSE block.
set(CLEONA_VOICE_BUILD_SMOKE OFF CACHE BOOL "" FORCE)
add_subdirectory("${CMAKE_SOURCE_DIR}/../native/cleona_voice" "${CMAKE_BINARY_DIR}/cleona_voice_build")
```

`CLEONA_VOICE_BUILD_SMOKE OFF` matches this package's own CMakeLists.txt
comment ("A production Linux build should pass
`-DCLEONA_VOICE_BUILD_SMOKE=OFF`; it does not need the smoke executable") —
copied here so the request is self-contained rather than requiring a second
read. `CLEONA_VOICE_BUILD_MOCK` is intentionally left at its default (ON):
Check 15 (`scripts/preflight.sh`) only forbids **referencing** the mock
target from a production build file, and the mock target still needs to
exist for `native/cleona_voice/test`'s conformance harness (built as a
subdirectory of the same CMake tree) to have something to link against in
link mode. Nothing in `linux/CMakeLists.txt` will name `cleona_voice_mock`
after this change, so Check 15 stays green — verified locally:

```
$ bash scripts/preflight.sh 2>&1 | grep -A1 "Mock voice/video"
[PREFLIGHT] Mock voice/video backend not in production build wiring...
OK: no mock voice/video backend references in production build wiring
```

**(b)** Near line 137 (right after the `cleona_net` install block), add:

```cmake
# cleona_voice — same install pattern as cleona_audio/cleona_net.
install(TARGETS cleona_voice LIBRARY DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)
```

**Verify:** `flutter build linux --release` produces
`build/linux/*/release/bundle/lib/libcleona_voice.so`, and that binary passes
the conformance loader exactly as tested during V1.1's own acceptance (see
this package's git history / the V1.1 session report for the full transcript):

```
./build/voice/test/cleona_voice_conformance_loader \
    build/linux/*/release/bundle/lib/libcleona_voice.so --shipping
```

---

## 2. New runtime (not build-time) dependency: two system shared libraries

This is new information for the packaging side of the pipeline, not present
in `native/cleona_audio`'s footprint: `libcleona_voice.so` is **dynamically
linked** (not statically vendored, unlike `cleona_audio`'s speexdsp) against:

```
$ ldd build/voice-test/linux/libcleona_voice.so | grep -E "pipewire|webrtc"
libpipewire-0.3.so.0        => /lib/x86_64-linux-gnu/libpipewire-0.3.so.0
libwebrtc_audio_processing.so.1 => /lib/x86_64-linux-gnu/libwebrtc_audio_processing.so.1
```

Both are ordinary system packages on any PipeWire-based desktop
(`libpipewire-0.3-0`, `libwebrtc-audio-processing1` on Debian/Ubuntu; the
"first" chain additionally needs `libpipewire-0.3-modules` at **runtime**
for `libpipewire-module-echo-cancel.so` and `pipewire-modules`'s
`aec/libspa-aec-webrtc.so` — this is a `dlopen`-style runtime load by
PipeWire itself, not a link-time dependency of `libcleona_voice.so`, so it
will not show up in `ldd` output but will show up as a fallback to the
`LINKED_APM` chain — see this package's report — if missing at runtime).

Neither library is vendored or statically linked, unlike
`cleona_audio`'s speexdsp (architecture §10.4's Superseded-stack table).
Whatever produces a distributable Linux artifact (AppImage, .deb, Flatpak —
whichever `scripts/release-build.sh` currently targets for Linux) needs
these two as runtime dependencies, or bundled `.so`s if the target format
does not assume a system PipeWire install. This request does not prescribe
which; it records the fact so packaging does not discover it by a user's
crash report instead.

---

## 3. `scripts/build-android-libs.sh`, `build-ios-libs.sh`, `build-macos-libs.sh`

Nothing to do here for V1.1 — this package is Linux-only. Recorded so V1.2
(Android)/V1.3 (Apple) do not have to re-derive that the Linux backend's
build shape (dynamic pkg-config dependencies, no vendored C++ library) is
unrelated to theirs.

---

## 4. Not requested: `scripts/preflight.sh` Check 5's `native/<name>/<name>.c`
loop

`native/cleona_voice/BUILD_REQUEST.md` §5(b) already flagged that
`native/cleona_voice` does not fit the `native/<name>/<name>.c` shape Check 5
assumes, and asked V0.5 to give the loop a per-library source path or compare
against the newest `.c` under the package. That request already covers
`native/cleona_voice/linux/cleona_voice_linux.c` as one of the files such a
fix would need to notice — nothing additional to ask for here.

# BUILD_REQUEST — `native/cleona_video/` → package V0.5 (build ownership)

**From:** V0.3 (video ABI + Dart binding + mock)
**To:** V0.5 / V1.8, the owner of every build and CI file (SPEC §9)
**Status:** open. Nothing in this list has been done by V0.3, and nothing in it
may be done by V0.3 — every file named below belongs to the build package.

V0.3 delivered, entirely inside its own directory:

| File | What it is |
|---|---|
| `native/cleona_video/cleona_video.h` | the frozen C ABI (SPEC §4b) |
| `native/cleona_video/mock/cleona_video_mock.{c,h}` | hardware-free backend (SPEC §5) |
| `native/cleona_video/smoke/smoke_video_mock.c` | V0.3 acceptance smoke |
| `native/cleona_video/CMakeLists.txt` | standalone build of the above |
| `lib/core/calls/video_pipeline.dart` | the single Dart binding |

Verified on Linux (gcc 13.3.0, cmake 3.28.3):

```
cmake -S native/cleona_video -B build/cleona_video -DCMAKE_BUILD_TYPE=Debug
cmake --build build/cleona_video      # 0 warnings at -Wall -Wextra
ctest --test-dir build/cleona_video   # 1/1 passed
```

---

## 1. BLOCKING — `ios/CleonaNative/cleona_exported_symbols.txt`

`scripts/check_ios_exports.sh` fails **today** because `video_pipeline.dart`
looks up twelve symbols that are not listed. Reproduced verbatim:

```
$ bash scripts/check_ios_exports.sh
ERROR: 12 FFI symbol(s) missing from iOS exports file!

  File: ios/CleonaNative/cleona_exported_symbols.txt

  MISSING: _cleona_video_close
  MISSING: _cleona_video_get_report
  MISSING: _cleona_video_get_texture_id
  MISSING: _cleona_video_open
  MISSING: _cleona_video_read_encoded
  MISSING: _cleona_video_reconfigure
  MISSING: _cleona_video_request_keyframe
  MISSING: _cleona_video_set_capture_enabled
  MISSING: _cleona_video_start
  MISSING: _cleona_video_stop
  MISSING: _cleona_video_submit_encoded
  MISSING: _cleona_video_switch_camera
```

`_cleona_video_reconfigure` is new since Erratum 1 (project owner,
2026-07-30) — the twelfth symbol arrived while this request was already open,
which is precisely the argument for the wildcard below rather than a
hand-maintained list of names.

`scripts/preflight.sh` Check 6 runs the same script with `--ci`, so this also
blocks every commit that stages `lib/core/calls/video_pipeline.dart` until V0.5
acts. That is the gate doing its job, not a defect.

**Recommended fix — one wildcard line, not eleven explicit ones:**

```
# libcleona_video (ABI: native/cleona_video/cleona_video.h)
_cleona_video_*
```

Rationale, checked against the two gates rather than assumed:

* `check_ios_exports.sh` matches wildcard entries by prefix
  (`grep '\*$' "$EXPORTS"`, then `[[ "_${sym}" == "${prefix}"* ]]`), so one
  line covers all twelve and every future ABI addition — including
  `_cleona_video_reconfigure`, which Erratum 1 added after this file was first
  written and which an explicit list would have missed.
* `preflight.sh` Check 12 part B iterates only over
  `grep -E '^_[A-Za-z_][A-Za-z0-9_]*$'`, i.e. it deliberately skips wildcard
  lines. **This matters:** an explicit `_cleona_video_open` entry would make
  Check 12 B look for a `native/**/*.c` that defines it, find
  `native/cleona_video/mock/cleona_video_mock.c`, and then demand that
  `scripts/build-ios-libs.sh` compiles **the mock** into the iOS image. Shipping
  a synthetic-bitstream encoder in a release build is not the intent, and the
  Apple backend that should define these symbols is package V1.15 and does not
  exist yet.
* Precedent in the same file: `_cleona_audio_*` (line 87), `_cleona_vpx_*`
  (line 101), `_vpx_codec_*` (line 97).

Once V1.15 lands `native/cleona_video/apple/**`, the wildcard keeps working and
Check 12 A/C apply to the real archive as usual.

## 1b. BLOCKING, but NOT caused by V0.3 — `scripts/preflight.sh` Check 5

Check 5 (Android native lib staleness) also fails in this worktree, and it will
fail in every other worktree of this repo at random. It is listed here only so
that the two blockers are not confused with each other: **nothing in V0.3
touches its inputs.**

```
$ git status --short native/cleona_audio native/cleona_net native/cleona_pow \
                     android/app/src/main/jniLibs
(empty — V0.3 modifies none of them)

$ stat -c '%y' native/cleona_audio/cleona_audio.c
2026-07-30 14:38:35.658678429 +0200
$ stat -c '%y' android/app/src/main/jniLibs/arm64-v8a/libcleona_audio.so
2026-07-30 14:38:35.531676254 +0200
```

Both files were written by the same `git worktree add`, 127 ms apart. Check 5
compares them with `[ "$CSRC" -nt "$SOFILE" ]`, and git stores no mtimes, so the
verdict depends on the order the checkout happened to write the two trees — not
on whether the `.so` is actually stale.

**No action needed from V0.5: the fix already exists** on branch
`s290/v0.5a-preflight-staleness`, commit `cac6c03e`, which replaces the mtime
compare with a `*.srchash` content hash for exactly this reason. This entry is a
cross-reference, not a request. Once that commit is on `main`, this blocker
disappears on its own.

## 2. Linux desktop — `linux/CMakeLists.txt`

Follow the `cleona_audio` / `cleona_net` pattern already in that file
(lines 60-70 and 109-115):

```cmake
add_subdirectory("${CMAKE_SOURCE_DIR}/../native/cleona_video"
                 "${CMAKE_BINARY_DIR}/cleona_video_build")
install(TARGETS cleona_video LIBRARY DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
        COMPONENT Runtime)
```

Two things V0.5 has to decide, because V0.3 cannot:

* **Target name.** V0.3 ships only `cleona_video_mock`. The real Linux backend
  is V1.13 and will provide a `cleona_video` target. Until it exists there is
  no library worth installing into a desktop bundle, so the request is: wire
  this up when V1.13 lands, not before. `video_pipeline.dart` searches for
  `libcleona_video.so`; a missing library raises
  `VideoLibraryNotAvailable` and the caller degrades to audio-only, which is
  the current behaviour anyway.
* **Never install the mock into a shipped bundle.** `libcleona_video_mock.so`
  is a test artefact. `native/cleona_video/CMakeLists.txt` builds it behind
  `-DCLEONA_VIDEO_BUILD_MOCK=ON` (default ON for standalone use); a bundle build
  should pass `-DCLEONA_VIDEO_BUILD_MOCK=OFF -DCLEONA_VIDEO_BUILD_SMOKE=OFF`.

## 3. Windows — `windows/runner/CMakeLists.txt`

Same shape as Linux, same "wait for V1.16" caveat. `video_pipeline.dart` looks
for `cleona_video.dll` next to the executable and in `native\` beside it.
MSVC needs no special flags for this code: it is C11 with `<stdint.h>` and
`QueryPerformanceCounter`, no `<stdatomic.h>` (unlike `cleona_audio_ring.c`).

## 4. Android — `scripts/build-android-libs.sh` and `scripts/preflight.sh`

* Cross-compile `native/cleona_video/` for `arm64-v8a` and `x86_64` once the
  Android backend (V1.14) exists, producing `libcleona_video.so`.
* Add `libcleona_video.so` to **both** jniLibs lists in `scripts/preflight.sh`
  Check 8 — `ARM64_LIBS` (line 171) and `X86_64_LIBS` (line 174). Adding it to
  only one is the failure mode SPEC §7 V1.8 already calls out for Opus.
* Do this in the same commit as the Android backend, not earlier: a name on the
  jniLibs list with no file behind it turns Check 8 red for everyone.

## 5. Apple — `scripts/build-ios-libs.sh`, `scripts/build-macos-libs.sh`

* iOS links statically: build `native/cleona_video/` with
  `-DCLEONA_VIDEO_STATIC=ON` (the option exists) into a `.a`, make an
  XCFramework, and put its install subdir on **both** the `make_xcfw` list and
  the `for subdir in ...` merge loop — `preflight.sh` Check 12 A derives those
  two lists from the script itself and fails when they diverge.
* macOS builds dylibs into `Contents/Frameworks`, matching `cleona_audio`.
* Again: only when V1.15 exists. The mock must never reach an Apple artefact.

## 6. `ctest` default run

`native/cleona_video/CMakeLists.txt` already registers `video_mock_smoke` and
adds `native/cleona_video/test/` automatically once V0.4 creates it, so V0.5
only has to make sure the directory is reached by whatever top-level CTest
aggregation exists. No change inside `native/cleona_video/` is needed for that.

## 7. Nothing else

V0.3 requests **no** change to `scripts/release-build.sh`,
`scripts/dry-run-cleonagit-push.sh`, `scripts/build-ensure.sh`,
`proto/cleona.proto`, `lib/main.dart`, `lib/core/calls/video_engine.dart`,
`lib/core/node/cleona_node.dart` or `lib/core/network/udp_fragmenter.dart`.
The transport-side enforcement of I8/I9 is package V1.11; the value that
`VideoConfig.maxFrameBytes` is set to comes from there and is deliberately not
hard-coded anywhere in `native/cleona_video/`.

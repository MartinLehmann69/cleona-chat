# BUILD_REQUEST — `native/cleona_voice` → work package V0.5 (build ownership)

**From:** V0.2 (Voice ABI + Dart binding + mock)
**To:** V0.5 / V1.8 — owner of all build and CI files (SPEC §9)
**Status:** open. One item (§1) currently **fails `scripts/preflight.sh`** and is
therefore blocking, see §6.

V0.2 owns `native/cleona_voice/**`, `lib/core/calls/voice_session.dart` and
`lib/core/calls/voice_report.dart`. Everything below lies outside that set and
was deliberately **not** changed here — a second edit in a file V0.5 owns is
exactly the conflict the ownership rule exists to prevent. Each item states what
to add, where, and how to verify it.

---

## 1. `ios/CleonaNative/cleona_exported_symbols.txt` — BLOCKING

`scripts/check_ios_exports.sh` scans `lib/**.dart` for `lookupFunction` /
`.lookup<` and requires every symbol to be a dead-strip root. The new Dart
binding looks up **12** symbols, none of which is covered by an existing
wildcard (the file's wildcards are `_cleona_audio_*`, `_cleona_vpx_*`, `_vpx_*`,
`_whisper_*`).

Measured on this branch:

```
$ bash scripts/check_ios_exports.sh --ci
ERROR: 12 FFI symbol(s) missing from iOS exports file!

  File: ios/CleonaNative/cleona_exported_symbols.txt

  MISSING: _cleona_voice_capture_read
  MISSING: _cleona_voice_close
  MISSING: _cleona_voice_get_report
  MISSING: _cleona_voice_get_routes
  MISSING: _cleona_voice_open
  MISSING: _cleona_voice_playback_write
  MISSING: _cleona_voice_poll_event
  MISSING: _cleona_voice_set_mic_muted
  MISSING: _cleona_voice_set_output_muted
  MISSING: _cleona_voice_set_route
  MISSING: _cleona_voice_start
  MISSING: _cleona_voice_stop
```

**Requested change** — append next to the existing `# libcleona_audio` block:

```
# libcleona_voice (§10.4 native voice session)
_cleona_voice_*
```

One wildcard rather than twelve lines, matching the `_cleona_audio_*` precedent:
the ABI is frozen but will gain platform backends, and a per-symbol list would
have to be edited by every one of V1.1-V1.4. The wildcard covers exactly the
`cleona_voice_` prefix and nothing else.

**Do NOT** solve this by adding the binding to `EXCLUDE_PATTERN` or to
`OPTIONAL_SYMBOLS` in `check_ios_exports.sh`. The gate's own comment explains
why (lines 30-58): an exemption makes the gate silent for precisely the change
it exists to catch. `voice_session.dart` is genuinely iOS-relevant — V1.3 builds
the Apple VoiceProcessingIO backend against it — so the symbols must really be
in the image.

**Note on the mock:** `cleona_voice_mock.c` also exports
`cleona_voice_mock_*` (config/injection helpers, `CLEONA_VOICE_MOCK_API`).
Those are **not** looked up from `lib/**` and must **not** be added to the
exports file — the mock has no business in a shipped iOS image.

**Verify:** `bash scripts/check_ios_exports.sh --ci` prints
`✓ All N FFI symbols found` and exits 0.

---

## 2. `linux/CMakeLists.txt`

`native/cleona_voice/CMakeLists.txt` is standalone and is not referenced from
the Flutter Linux build yet.

**Requested change** — alongside the existing `cleona_audio` / `cleona_net` /
`cleona_pow` handling:

```cmake
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../native/cleona_voice"
                 "${CMAKE_CURRENT_BINARY_DIR}/cleona_voice")
```

and add the produced library to the bundled-libraries list, as the other native
targets are (`$<TARGET_FILE:...>`), so it lands in `<bundle>/lib/` where the
`$ORIGIN/lib` RPATH and the Dart loader find it.

Which target to bundle depends on the wave:

* **now (V0.2 only):** `cleona_voice_mock` — nothing else exists, and the Dart
  loader only picks it up when a caller explicitly asks for
  `VoiceNativeLibrary.mock()`. Bundling it is optional; it is only needed if
  smoke/E2E work is to run against an installed bundle rather than the build
  tree. If it is bundled in a **release** build, note that `VoiceBackend.mock`
  (wire value 100) then becomes reachable — see §7.
* **from V1.1 on:** `cleona_voice` (the real PipeWire backend), which is the
  one production must load.

Options this file understands: `CLEONA_VOICE_BUILD_MOCK` (default ON),
`CLEONA_VOICE_BUILD_SMOKE` (default ON), `CLEONA_VOICE_ASAN` (default OFF),
`CLEONA_IOS_STATIC` (default OFF). A production Linux build should pass
`-DCLEONA_VOICE_BUILD_SMOKE=OFF`; it does not need the smoke executable.

**Verify:** `flutter build linux --release` produces
`build/linux/*/release/bundle/lib/libcleona_voice*.so`.

---

## 3. `windows/runner/CMakeLists.txt`

Same shape as §2. The CMake here already sets `PREFIX ""` on Windows, so the
outputs are `cleona_voice.dll` / `cleona_voice_mock.dll` — which is what
`VoiceNativeLibrary` looks for next to `Platform.resolvedExecutable`.

MSVC note: the mock uses `<stdint.h>`, `CRITICAL_SECTION` and
`QueryPerformanceCounter` only — no `<stdatomic.h>` — so it does **not** need
the `/std:c17 /experimental:c11atomics` flags that `cleona_audio` requires.

**Verify:** the Windows build produces `cleona_voice*.dll` next to
`cleona.exe`.

---

## 4. `scripts/build-android-libs.sh`, `build-ios-libs.sh`, `build-macos-libs.sh`

Nothing to do for V0.2 — there is no Android/Apple voice backend yet. The
request is recorded so V1.2/V1.3 do not each discover it separately:

* **Android** (V1.2): the backend is Kotlin + JNI. The native part builds with
  the NDK toolchain like `cleona_audio` does and installs
  `libcleona_voice.so` into `android/app/src/main/jniLibs/<abi>/`.
* **iOS** (V1.3): static archive, merged like the other libs; `CLEONA_IOS_STATIC=ON`
  makes `native/cleona_voice/CMakeLists.txt` emit `STATIC`. The symbols must be
  in the exports file — §1.
* **macOS** (V1.3): dylib into `Contents/Frameworks/`.

---

## 5. `scripts/preflight.sh`

Two checks will need V0.5's attention once a real backend exists:

**(a) Check 8 — Android jniLibs completeness.** Add `libcleona_voice.so` to both
`ARM64_LIBS` and `X86_64_LIBS` **at the same time as V1.2 lands**, not before:
adding it earlier fails the check for a library nothing builds yet.

**(b) Check 5 — Android native lib staleness.** The loop is

```bash
for CLIB in cleona_audio cleona_net cleona_pow; do
  CSRC="$REPO_ROOT/native/${CLIB}/${CLIB}.c"
```

which assumes `native/<name>/<name>.c`. `cleona_voice` does **not** have that
shape: the ABI is a header, and the sources live in `mock/`, `linux/`,
`android/` … So adding `cleona_voice` to that list would silently do nothing
(`[ -f "$CSRC" ]` is false), which is worse than not adding it — the check would
*look* extended without checking anything. Either give the loop a per-library
source path, or compare against the newest `.c` under `native/cleona_voice/`.

**(c) Observation for V0.5, not a request.** Check 5 compares **mtimes** of
git-tracked files. Git does not preserve mtimes, so in a **fresh worktree or a
clean CI checkout** the ordering of `native/cleona_audio/cleona_audio.c` versus
`android/.../libcleona_audio.so` is arbitrary. On this worktree the check failed
at the base commit `d8ca549f`, before any change of this package:

```
STALE: libcleona_audio.so older than cleona_audio.c — run scripts/build-android-libs.sh
STALE: libcleona_pow.so older than cleona_pow.c — run scripts/build-android-libs.sh
FAIL: Android native libs stale or missing
```

Both files are unmodified — this is a checkout artefact, not a real staleness.
A content hash recorded next to the `.so` would make the check mean what it
says; mtime cannot.

---

## 6. Consequence for the V0.2 commit — read this first

Until §1 is applied, `scripts/preflight.sh` fails on **Check 6** and the
`pre-commit` hook refuses any commit in this repository, including commits that
have nothing to do with voice. This is not a defect of the gate: the gate is
reporting a real, if future, hazard, and it is reporting it accurately.

V0.2 did **not** work around it — not by editing the V0.5-owned file, not by
`--no-verify`, and not by hiding the lookups from the scanner (which would trade
a build-time failure for a silent iOS runtime crash, the exact failure the gate
was written to prevent).

**§1 is a two-line append with no conflict surface. Please apply it first.**

---

## 7. Release gate worth adding while you are in these files

`VoiceBackend.mock` and `VoiceChainOrigin.mock` both carry wire value **100**,
and `cleona_voice.h` reserves everything `>= 100` for non-shipping backends.
A shipped build that emits either in its verification report has loaded the mock
instead of a real chain — an entirely silent failure otherwise, because the mock
answers every call successfully.

`VoiceReport.backend.isTestOnly` (`voice_report.dart`) is the predicate; the one
report line per call carries `backend=mock`, so a grep over release logs is
sufficient. Suggested home: the same place `release-build.sh` performs its other
artefact assertions.

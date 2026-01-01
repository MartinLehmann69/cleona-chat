# BUILD_REQUEST — `native/cleona_video/test` (V0.4) → V0.5 (build ownership)

**From:** V0.4 (conformance harness for both ABIs)
**To:** V0.5 / V1.8 — owner of all build and CI files (SPEC §9)
**Status:** one open item (§1), not blocking. V0.4 is acceptance-complete without
it; the item removes a foreseeable edit conflict for V1.13-V1.16.

V0.4 owns `native/cleona_voice/test/**` and `native/cleona_video/test/**`, plus
the two lines in each parent `CMakeLists.txt` that add those directories and
call `enable_testing()`. Everything below is outside that set and was
deliberately **not** changed here.

---

## 1. `native/cleona_video/CMakeLists.txt` — platform subdirectory loop

The **voice** tree ends with a loop that picks up a platform backend as soon as
it exists, so V1.1-V1.4 never have to edit a file they do not own:

```cmake
foreach(_plat linux android apple windows)
  if(EXISTS "${CMAKE_CURRENT_LIST_DIR}/${_plat}/CMakeLists.txt")
    add_subdirectory(${_plat})
  endif()
endforeach()
```

`native/cleona_video/CMakeLists.txt` has **no such loop**. V1.13-V1.16 own
`native/cleona_video/<platform>/**` (SPEC §7) but not the parent file, so as
things stand each of the four packages would have to ask for the same one-line
change, or four packages would edit the same file.

**Requested change** — append to `native/cleona_video/CMakeLists.txt`, *after*
the `add_subdirectory(test)` block, so that the conformance harness has already
defined `cleona_video_add_conformance_test()` by the time a platform directory
is processed:

```cmake
# Platform backends, when they land (V1.13-V1.16). Each brings its own
# CMakeLists.txt and its own BUILD_REQUEST.md. Added after test/ so that
# cleona_video_add_conformance_test() is already defined.
foreach(_plat linux android apple windows)
  if(EXISTS "${CMAKE_CURRENT_LIST_DIR}/${_plat}/CMakeLists.txt")
    add_subdirectory(${_plat})
  endif()
endforeach()
```

**Verification:** `cmake -S native/cleona_video -B build/video` still configures
with no platform directory present, and a platform package can register its
conformance run with one call from its own file.

**Until it lands** there is no blockage: route (A) in
`native/cleona_video/test/CMakeLists.txt` — build the loader once, hand it the
backend library at run time — needs no build integration at all, and is the
route Linux, Android and Windows should use anyway.

---

## 2. `ios/CleonaNative/cleona_exported_symbols.txt` — **no action needed**

Stated explicitly so it is not investigated twice. `scripts/check_ios_exports.sh`
scans `lib/**.dart` for FFI lookups; V0.4 adds no Dart and no FFI symbol. The
harness reaches an iOS backend by **linking** against it (link mode), not by
looking a symbol up at run time, so the exports file is untouched by this
package. The twelve voice symbols are already requested by
`native/cleona_voice/BUILD_REQUEST.md` §1 on behalf of the Dart binding; the
video binding will bring its own request.

---

## 3. Optional: run the conformance tests in CI

Both harnesses are in the `ctest` default of their own tree, so a CI step is two
commands per tree and needs no new script:

```bash
cmake -S native/cleona_voice -B build/voice && cmake --build build/voice -j
ctest --test-dir build/voice --output-on-failure

cmake -S native/cleona_video -B build/video && cmake --build build/video -j
ctest --test-dir build/video --output-on-failure
```

That covers the ABI against the mocks **and** the negative controls, which are
the part that keeps the harness honest: each of them runs the real harness
against a backend with one injected defect and passes only if exactly the
corresponding check goes red.

The sanitizer variants are worth a nightly rather than every commit (they cost
about a minute each and are the only place where SPEC §6 check 9 is actually
decided):

```bash
cmake -S native/cleona_voice -B build/voice-asan -DCLEONA_VOICE_ASAN=ON
cmake -S native/cleona_video -B build/video-asan -DCLEONA_VIDEO_TEST_ASAN=ON
```

Each adds one extra test that passes **only when LeakSanitizer reports the
deliberately injected leak** — without it, "no leak reported" and "the leak
checker never ran" are the same output, which is the failure mode preflight
check 5 had for years.

No change to `scripts/preflight.sh` is requested. The harness builds no shipped
artefact and adds nothing to any jniLibs list.

# libcleona_link — Elligator2 shim for the V4 link handshake (E-42, §20.4.1;
# build plan migration plan §4d, step 0).
#
# SCOPE OF THIS FILE. It builds exclusively what lies under
# native/cleona_link/, and is deliberately self-contained — the same pattern
# as native/cleona_video/CMakeLists.txt ("V0.3 does not own any build file
# outside this directory"). The repo-wide integration (linux/CMakeLists.txt,
# windows/runner/CMakeLists.txt, scripts/build-android-libs.sh,
# scripts/build-ios-libs.sh + ios/CleonaNative/cleona_exported_symbols.txt,
# scripts/build-macos-libs.sh, preflight lists scripts/preflight.sh:132 and
# :322/:325) is a package of its own — §4d.5 names the places.
#
# Standalone build (that is the step-0 acceptance):
#   cmake -S native/cleona_link -B build/cleona_link
#   cmake --build build/cleona_link
#   ./build/cleona_link/smoke_link_elligator            # must deliver PASS
#   ./build/cleona_link/smoke_link_elligator_sabotage   # must FAIL
#
# Vendoring: vendor/monocypher/ contains Monocypher 4.0.3 unchanged
# (monocypher.c/.h + LICENCE.md from the release tarball
# monocypher-4.0.3.tar.gz, SHA-256
# 8cc9bc341a66249016db9bd70e9142d8d0aef9945973744b1ac05dbc55d8ee66;
# byte-identical with Git tag 4.0.3 = ab2b16dd619ad5f6979a4fbe69cfa324a6fcc35f
# except for the stamped version line 1). Version pinned, not
# "latest" (§4d.5). No find_library: on the cross targets Android/iOS there
# is no system Monocypher, and a system search would not pin the
# version.
#
# Licence: BSD-2-Clause OR CC0-1.0 (SPDX line 10 of vendor/monocypher/
# monocypher.h; full text vendor/monocypher/LICENCE.md).

cmake_minimum_required(VERSION 3.13)

project(cleona_link
        VERSION 1.0.0
        LANGUAGES C
        DESCRIPTION "Cleona Elligator2 link-handshake shim (vendored Monocypher 4.0.3)")

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(NOT MSVC)
  # -fvisibility=hidden: the Monocypher symbols stay library-internal,
  # exported are exactly the three EXPORT-annotated cleona_link_* functions
  # (verifiable: nm -D --defined-only libcleona_link.so).
  add_compile_options(-fvisibility=hidden -Wall -Wextra -Wpedantic -O3)
endif()

set(CLEONA_LINK_SOURCES
    cleona_link.c
    vendor/monocypher/monocypher.c)

# iOS requires static libraries (no own dylibs allowed) — same
# switch as native/cleona_pow/CMakeLists.txt.
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
  add_library(cleona_link STATIC ${CLEONA_LINK_SOURCES})
else()
  add_library(cleona_link SHARED ${CLEONA_LINK_SOURCES})
endif()

if(WIN32)
  set_target_properties(cleona_link PROPERTIES PREFIX "")
endif()

if(UNIX AND NOT APPLE AND NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
  set_target_properties(cleona_link PROPERTIES
                        VERSION ${PROJECT_VERSION}
                        SOVERSION 1)
endif()

# ── Step-0 gate: upstream vectors + round trip + reverse probe ──────────────
# Two executables from the same test source:
#   smoke_link_elligator          against the real library → must pass
#   smoke_link_elligator_sabotage against a deliberately broken variant
#                                 (one flipped bit in map) → must fail
# The sabotage variant is the reverse probe: a gate that stays green even against the
# defect proves nothing (S336: three blind gates).
option(CLEONA_LINK_BUILD_SMOKE "Stufe-0-Gate (Vektoren + Umkehrprobe) bauen" ON)

if(CLEONA_LINK_BUILD_SMOKE)
  add_executable(smoke_link_elligator test/link_elligator_smoke.c)
  target_link_libraries(smoke_link_elligator PRIVATE cleona_link)

  # Saboteur: identical sources, one macro. Is never installed.
  add_library(cleona_link_saboteur SHARED ${CLEONA_LINK_SOURCES})
  target_compile_definitions(cleona_link_saboteur PRIVATE CLEONA_LINK_SABOTAGE)
  add_executable(smoke_link_elligator_sabotage test/link_elligator_smoke.c)
  target_link_libraries(smoke_link_elligator_sabotage PRIVATE cleona_link_saboteur)
endif()

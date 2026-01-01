# libcleona_store — encrypted local store (S366).
#
# The carrier is SQLite3 Multiple Ciphers (SQLite3MC): SQLite with
# encryption at the VFS level. The database AND its journals lie
# encrypted; a plaintext temp file as in the rejected draft from
# docs/CRYPTO.md ("SQLite on a decrypted temp file, flush every 60s")
# does not arise — see SQLITE_TEMP_STORE=3 below.
#
# SCOPE OF THIS FILE. It builds exclusively what lies under
# native/cleona_store/ — the same pattern as
# native/cleona_link/CMakeLists.txt. The repo-wide integration
# (linux/CMakeLists.txt, windows/runner/CMakeLists.txt,
# scripts/build-android-libs.sh, scripts/build-ios-libs.sh +
# ios/CleonaNative/cleona_exported_symbols.txt, scripts/build-macos-libs.sh,
# the preflight lists) is a package of its own and NOT contained here.
#
# Standalone build (the acceptance of this step):
#   cmake -S native/cleona_store -B build/cleona_store
#   cmake --build build/cleona_store
#   ./build/cleona_store/smoke_store_encryption            # must deliver PASS
#   ./build/cleona_store/smoke_store_encryption_sabotage   # must FAIL
#
# VENDORING. vendor/sqlite3mc/ contains the amalgamation from release
# v2.5.1 (SQLite base 3.53.4, published 2026-08-27), unchanged from
# sqlite3mc-2.5.1-sqlite-3.53.4-amalgamation.zip, SHA-256
# 4125f8ff275ea953dabb3289331b20a0e76d4fc060f57148f4a5df3bf3b0d5e0
# (checked against the shipped UPSTREAM-SHA256SUMS; the
# release signature .sig/.pem could NOT be checked with openssl — it is
# not an X.509 certificate, and a suitable tool was not available. What is checked
# is therefore the checksum, not the signature).
#
# Version pinned, not "latest". The SQLite base is deliberately
# >= 3.53.3: CVE-2026-11822 and CVE-2026-11824 are memory errors in the
# FTS5 full-text search (out-of-bounds read in fts5LeafSeek(),
# heap overflow in fts5ChunkIterate()), fixed in 3.53.2/3.53.3. The
# system library of this workbench is 3.45.1 and thus affected — therefore
# NO find_library and no system search, on any platform.
#
# Licence: SQLite itself is public domain; the MC extension is under
# MIT (see vendor/sqlite3mc/README.md).

cmake_minimum_required(VERSION 3.13)

project(cleona_store
        VERSION 1.0.0
        LANGUAGES C
        DESCRIPTION "Cleona encrypted local store (vendored SQLite3MC 2.5.1 / SQLite 3.53.4)")

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# ── Compile switches, and why each one ──────────────────────
#
# SQLITE_TEMP_STORE=3      Temporary tables and sort runs ALWAYS in
#                          memory. Without it SQLite could write plaintext
#                          to disk during large sorts
#                          — exactly the flaw on which the old
#                          draft failed. Not negotiable.
# SQLITE_SECURE_DELETE     Deleted contents are overwritten with zeros
#                          instead of merely freed. A
#                          database otherwise only frees deleted pages for
#                          reuse; "deleted" would then mean
#                          "no longer listed". §21.5 requires more.
# SQLITE_DQS=0             Double quotes are NEVER a string.
#                          Excludes a whole class of typos
#                          that otherwise silently pass as a literal.
# SQLITE_ENABLE_FTS5       The full-text search. It is the reason for the
#                          whole conversion (search over years).
# SQLITE_DEFAULT_FOREIGN_KEYS=1
#                          Foreign keys take effect without the caller's intervention.
# SQLITE_OMIT_DEPRECATED   Smaller attack surface, no loss.
# SQLITE_THREADSAFE=1      The service accesses from several isolates.
set(CLEONA_STORE_DEFINES
    SQLITE_ENABLE_FTS5
    SQLITE_THREADSAFE=1
    SQLITE_TEMP_STORE=3
    SQLITE_SECURE_DELETE
    SQLITE_DQS=0
    SQLITE_DEFAULT_MEMSTATUS=0
    SQLITE_DEFAULT_FOREIGN_KEYS=1
    SQLITE_ENABLE_MATH_FUNCTIONS
    SQLITE_OMIT_DEPRECATED
    HAVE_USLEEP=1)

if(NOT MSVC)
  add_compile_options(-O2 -Wall)
endif()

set(CLEONA_STORE_SOURCES vendor/sqlite3mc/sqlite3mc_amalgamation.c)

if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
  add_library(cleona_store STATIC ${CLEONA_STORE_SOURCES})
else()
  add_library(cleona_store SHARED ${CLEONA_STORE_SOURCES})
endif()

target_compile_definitions(cleona_store PRIVATE ${CLEONA_STORE_DEFINES})
target_include_directories(cleona_store PUBLIC vendor/sqlite3mc)

find_package(Threads REQUIRED)
target_link_libraries(cleona_store PRIVATE Threads::Threads)
if(UNIX)
  target_link_libraries(cleona_store PRIVATE m ${CMAKE_DL_LIBS})
endif()

if(WIN32)
  set_target_properties(cleona_store PROPERTIES PREFIX "")
endif()

if(UNIX AND NOT APPLE AND NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
  set_target_properties(cleona_store PROPERTIES
                        VERSION ${PROJECT_VERSION}
                        SOVERSION 1)
endif()

# ── The gate, and its reverse probe ─────────────────────────────────────
# smoke_store_encryption          against the real library   → must pass
# smoke_store_encryption_sabotage the same source, but WITHOUT the key
#                                 set                        → must fail
#
# The sabotage is not cosmetic here: the test claims "the file on
# disk is encrypted". If one leaves out the key, an
# ordinary SQLite file arises — and a test that does not notice that
# measures a proxy instead of the statement.
option(CLEONA_STORE_BUILD_SMOKE "Build the encryption gate with its reverse probe" ON)

if(CLEONA_STORE_BUILD_SMOKE)
  add_executable(smoke_store_encryption test/store_encryption_smoke.c)
  target_link_libraries(smoke_store_encryption PRIVATE cleona_store)

  add_executable(smoke_store_encryption_sabotage test/store_encryption_smoke.c)
  target_compile_definitions(smoke_store_encryption_sabotage
                             PRIVATE CLEONA_STORE_SABOTAGE)
  target_link_libraries(smoke_store_encryption_sabotage PRIVATE cleona_store)
endif()

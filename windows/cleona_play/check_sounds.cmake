# check_sounds.cmake -- every bundled sound must decode with the player that
# was just built. Invoked via `cmake -P` from a POST_BUILD step in
# windows/runner/CMakeLists.txt.
#
# WHY THIS EXISTS (S403). Up to here the Windows player was a PowerShell
# SoundPlayer call that plays WAV only, while the bundle carried Ogg Vorbis
# only: every Windows build was silent and no build step, no smoke and no gate
# said so. "The player is in the bundle" (verify_bundle_dlls.cmake) is not the
# statement that matters; "the player decodes what the bundle ships" is. This
# script measures exactly that, with `--check` (decode, no output device --
# the build VM has none in a non-interactive session).
#
# Arguments (both required):
#   -DPLAYER=<path to cleona-play.exe>
#   -DSOUNDS_DIR=<directory with the .ogg files that go into the bundle>

if(NOT DEFINED PLAYER OR NOT DEFINED SOUNDS_DIR)
  message(FATAL_ERROR "check_sounds: -DPLAYER=<exe> and -DSOUNDS_DIR=<dir> are required")
endif()
if(NOT EXISTS "${PLAYER}")
  message(FATAL_ERROR "check_sounds: player does not exist:\n  ${PLAYER}")
endif()

file(GLOB _sounds "${SOUNDS_DIR}/*.ogg")
list(LENGTH _sounds _count)
# Fail closed on an empty set: a moved assets directory would otherwise turn
# this check into one that passes without having looked at anything.
if(_count EQUAL 0)
  message(FATAL_ERROR
    "check_sounds: no .ogg file found in\n  ${SOUNDS_DIR}\n"
    "The sounds directory moved or is empty -- adjust -DSOUNDS_DIR in\n"
    "windows/runner/CMakeLists.txt.")
endif()

set(_failed "")
foreach(_sound IN LISTS _sounds)
  execute_process(
    COMMAND "${PLAYER}" "${_sound}" --check
    RESULT_VARIABLE _exit
    OUTPUT_QUIET ERROR_QUIET
  )
  if(NOT _exit EQUAL 0)
    get_filename_component(_name "${_sound}" NAME)
    list(APPEND _failed "${_name} (exit ${_exit})")
  endif()
endforeach()

if(_failed)
  string(REPLACE ";" "\n  " _failed_text "${_failed}")
  message(FATAL_ERROR
    "cleona-play cannot decode these bundled sounds:\n"
    "  ${_failed_text}\n"
    "\n"
    "Exit codes: windows/cleona_play/cleona_play.c. A sound the player\n"
    "cannot decode is silent on Windows -- this build is failed on purpose.")
endif()

message(STATUS "cleona-play decodes all ${_count} bundled sounds")

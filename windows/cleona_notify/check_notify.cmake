# check_notify.cmake -- the toast helper that was just built must build its
# toast XML correctly. Invoked via `cmake -P` from a POST_BUILD step in
# windows/runner/CMakeLists.txt.
#
# WHAT IT MEASURES. `cleona-notify.exe --check` builds the toast from a fixed
# sample full of markup characters and reads it back: both texts must come
# back as text (no element of a message can enter the toast, §22.8) and the
# toast must be silent (Cleona plays its own sound). No toast is shown, no
# registry value and no start-menu shortcut is written (--check returns
# before both), nothing is printed -- the build VM runs this in a
# non-interactive build.
#
# Arguments (required):
#   -DHELPER=<path to cleona-notify.exe>

if(NOT DEFINED HELPER)
  message(FATAL_ERROR "check_notify: -DHELPER=<exe> is required")
endif()
if(NOT EXISTS "${HELPER}")
  message(FATAL_ERROR "check_notify: helper does not exist:\n  ${HELPER}")
endif()

execute_process(
  COMMAND "${HELPER}" --check
  RESULT_VARIABLE _exit
  OUTPUT_QUIET ERROR_QUIET
)

if(NOT _exit EQUAL 0)
  message(FATAL_ERROR
    "cleona-notify --check failed (exit ${_exit}).\n"
    "\n"
    "Exit codes: windows/cleona_notify/cleona_notify.cpp. A helper that does\n"
    "not build its toast XML as text-only and silent must not ship -- this\n"
    "build is failed on purpose.")
endif()

message(STATUS "cleona-notify builds a silent toast with text-only content")

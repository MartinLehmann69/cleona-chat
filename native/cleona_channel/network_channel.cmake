# Network channel of a desktop bundle (data/channel) — ONE source for Linux and
# Windows (S413-13/S414).
#
# The window (linux/runner/my_application.cc, windows/runner/main.cpp), the
# user copy and the update path (lib/core/update/user_copy.dart,
# binary_update_manager.dart) read the channel of a bundle from data/channel.
# The channel itself is compiled into the Dart side from
# --dart-define=NETWORK_CHANNEL (lib/core/config/network_channel.dart). This
# module derives the file from that same define, so every
# `flutter build linux|windows` carries it — the lab build exactly like the
# release build; scripts/release-build.sh only checks it.
#
# Where the define comes from: the flutter tool writes
# <platform>/flutter/ephemeral/generated_config.cmake before every build and
# then runs the CMake configure step (flutter_tools lib/src/linux/
# build_linux.dart and lib/src/windows/build_windows.dart, both through
# writeGeneratedCmakeConfig in lib/src/cmake.dart — the same writer on both
# platforms). Its FLUTTER_TOOL_ENVIRONMENT holds one line
#   "DART_DEFINES=<b64>,<b64>,…"
# with one standard base64 of the UTF-8 "KEY=VALUE" per define
# (lib/src/build_info.dart, encodeDartDefines), and no such line when there is
# no define at all. That list lives in the scope of the flutter/ subdirectory,
# so the line is read from the file. The include in flutter/CMakeLists.txt
# makes the file a configure input, so a channel change reconfigures.
#
# Same rule as NetworkChannel.fromString and activeNetworkChannel on the
# desktop: "live" in any case is live; any other value, an empty one or no
# define at all is beta.
#
# The file is "<channel>\n" with LF on every platform (NEWLINE_STYLE UNIX,
# CMake >= 3.18): file(WRITE) does not pin the line ending. Readers trim it
# (g_strstrip, String.trim) or read the first four bytes (main.cpp).

if(CMAKE_VERSION VERSION_LESS 3.18)
  message(FATAL_ERROR "data/channel needs CMake >= 3.18 (file(CONFIGURE ... NEWLINE_STYLE)), found ${CMAKE_VERSION}")
endif()

function(cleona_base64_decode encoded out_var)
  set(alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
  string(REGEX REPLACE "=+$" "" encoded "${encoded}")
  string(LENGTH "${encoded}" length)
  set(decoded "")
  set(acc 0)
  set(acc_bits 0)
  set(index 0)
  while(index LESS length)
    string(SUBSTRING "${encoded}" ${index} 1 char)
    string(FIND "${alphabet}" "${char}" value)
    if(value LESS 0)
      message(FATAL_ERROR "DART_DEFINES entry is not base64: '${encoded}'")
    endif()
    math(EXPR acc "(${acc} << 6) | ${value}")
    math(EXPR acc_bits "${acc_bits} + 6")
    if(NOT acc_bits LESS 8)
      math(EXPR acc_bits "${acc_bits} - 8")
      math(EXPR byte "(${acc} >> ${acc_bits}) & 255")
      math(EXPR acc "${acc} & ((1 << ${acc_bits}) - 1)")
      string(ASCII ${byte} char)
      string(APPEND decoded "${char}")
    endif()
    math(EXPR index "${index} + 1")
  endwhile()
  set(${out_var} "${decoded}" PARENT_SCOPE)
endfunction()

# cleona_network_channel_file(<generated_config.cmake> <out_file_var>)
# Writes <binary dir>/cleona_channel and returns its path in <out_file_var>.
function(cleona_network_channel_file generated_config out_file_var)
  set(channel "beta")
  file(STRINGS "${generated_config}" defines_line REGEX "\"DART_DEFINES=")
  if(defines_line MATCHES "\"DART_DEFINES=([^\"]*)\"")
    string(REPLACE "," ";" defines "${CMAKE_MATCH_1}")
    foreach(define_b64 IN LISTS defines)
      cleona_base64_decode("${define_b64}" define_text)
      if(define_text MATCHES "^NETWORK_CHANNEL=(.*)$")
        string(TOLOWER "${CMAKE_MATCH_1}" value)
        if(value STREQUAL "live")
          set(channel "live")
        else()
          set(channel "beta")
        endif()
      endif()
    endforeach()
  endif()
  message(STATUS "Cleona network channel of this bundle: ${channel}")
  set(out_file "${CMAKE_BINARY_DIR}/cleona_channel")
  file(CONFIGURE OUTPUT "${out_file}" CONTENT "${channel}\n" NEWLINE_STYLE UNIX)
  set(${out_file_var} "${out_file}" PARENT_SCOPE)
endfunction()

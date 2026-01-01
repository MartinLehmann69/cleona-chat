cmake_minimum_required(VERSION 3.13)
project(cleona_audio_tests C)
set(CMAKE_C_STANDARD 11)

# Pull in the shim itself so test_loopback can link against it. test_ring
# stays standalone (it tests the ring buffer in isolation, no shim init).
add_subdirectory(.. cleona_audio_build)

add_executable(test_ring
  test_ring.c
  ../cleona_audio_ring.c
)
target_include_directories(test_ring PRIVATE ..)
target_link_libraries(test_ring PRIVATE pthread)

# End-to-end loopback. Excluded from default ctest run because it needs a
# working mic + speaker on the host. Run manually:
#   cd build && ./test_loopback 3
add_executable(test_loopback test_loopback.c)
target_link_libraries(test_loopback PRIVATE cleona_audio)
target_include_directories(test_loopback PRIVATE ..)

enable_testing()
add_test(NAME ring_buffer COMMAND test_ring)
add_test(NAME loopback_smoke
         COMMAND test_loopback 1
         CONFIGURATIONS Manual)

#
# CleonaNative — umbrella podspec for prebuilt native C libraries.
#
# The actual .a archives (merged into libcleona_all_{device,simulator}.a by
# scripts/build-ios-libs.sh) are force-loaded via the Podfile post_install
# hook, NOT via vendored_frameworks or vendored_libraries.
#
# This podspec exists as a CocoaPods dependency anchor to:
#   1. Declare system frameworks needed by the native libs
#   2. Declare system libraries (libc++, libz) needed for linking
#   3. Provide a compilable source file so CocoaPods doesn't reject the pod
#
# vendored_frameworks / vendored_libraries are intentionally NOT used.
# See the Podfile post_install comment for the full rationale.
#
Pod::Spec.new do |s|
  s.name         = 'CleonaNative'
  s.version      = '0.1.0'
  s.summary      = 'Prebuilt native libraries for Cleona (crypto, audio, codecs)'
  s.homepage     = 'https://github.com/nicokimmel/cleona'
  s.license      = { :type => 'Proprietary' }
  s.author       = 'Cleona Dev'
  s.source       = { :path => '.' }
  s.platform     = :ios, '15.5'
  s.static_framework = true

  # Dummy source so CocoaPods accepts the pod (empty pods are rejected)
  s.source_files = 'CleonaNativeDummy.m'

  # System frameworks required by the native libraries:
  # - AudioToolbox, AVFoundation: libcleona_audio (miniaudio backend)
  # - CoreFoundation: general
  # - Accelerate: whisper.cpp GGML (BLAS/vecLib)
  # - Metal, MetalKit: whisper.cpp GGML Metal acceleration (device only)
  s.frameworks = 'AudioToolbox', 'CoreFoundation', 'AVFoundation',
                 'Accelerate', 'Metal', 'MetalKit'

  # System libraries required for C++ code in whisper.cpp/ggml and zstd
  s.libraries = 'c++', 'z'
end

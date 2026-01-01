#
# CleonaNative — prebuilt native C libraries for Cleona Chat.
#
# All native libs (libsodium, liboqs, libzstd, liberasurecode, libopus,
# whisper.cpp, libcleona_voice, libcleona_video) are merged into a single
# static archive by scripts/build-ios-libs.sh. The merged archive is
# force-loaded so that dart:ffi can find symbols via
# DynamicLibrary.process().
#
# WHY THE FRAMEWORK LIST BELOW MUST BE COMPLETE
# ----------------------------------------------
# A static library does NOT pass on its link dependencies.
# native/cleona_video/apple/CMakeLists.txt does say
# target_link_libraries(... VideoToolbox CoreMedia CoreVideo ...), but that
# holds only while building the .a -- when the app is linked, nothing of it
# is known any more. If a framework is missing here, only the Xcode link step
# on the macOS runner fails, with undefined symbols instead of a statement
# of what is missing. Measured: without VideoToolbox the runner reported
# eleven undefined symbols (_kVTCompressionPropertyKey_*, _kVTProfileLevel_*,
# _kVTVideoEncoderSpecification_*). macOS stayed unaffected, because a dylib
# is built there, which brings its dependencies itself.
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

  s.source_files = 'CleonaNativeDummy.m'

  s.frameworks = 'AudioToolbox', 'CoreFoundation', 'AVFoundation',
                 'Accelerate', 'Metal', 'MetalKit',
                 # libcleona_video (§10.6): encoder/decoder, sample buffer and
                 # pixel buffer. None of the three needs a privacy key -- the
                 # camera/microphone keys hang on AVFoundation, which is
                 # listed here anyway.
                 'VideoToolbox', 'CoreMedia', 'CoreVideo'

  s.libraries = 'c++', 'z'

  # -force_load loads ALL object files from the merged archive into the
  # linker, even though no ObjC/Swift code references the C symbols.
  # EXPORTED_SYMBOLS_FILE marks FFI entry points as dead-strip roots;
  # DEAD_CODE_STRIPPING=YES (default) resolves duplicate symbols.
  # STRIP_STYLE=non-global preserves the export trie so dlsym() can
  # find the symbols at runtime (default 'all' strips the export trie).
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '-force_load $(PODS_ROOT)/../CleonaNative/libcleona_all_device.a',
    'EXPORTED_SYMBOLS_FILE' => '$(PODS_ROOT)/../CleonaNative/cleona_exported_symbols.txt',
    'STRIP_STYLE' => 'non-global',
  }
end

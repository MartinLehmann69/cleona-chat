#
# CleonaNative — prebuilt native C libraries for Cleona Chat.
#
# All native libs (libsodium, liboqs, libzstd, liberasurecode, libopus,
# whisper.cpp, libcleona_voice, libcleona_video) are merged into a single
# static archive by scripts/build-ios-libs.sh. The merged archive is
# force-loaded so that dart:ffi can find symbols via
# DynamicLibrary.process().
#
# WARUM DIE FRAMEWORK-LISTE UNTEN VOLLSTAENDIG SEIN MUSS
# ------------------------------------------------------
# Eine statische Bibliothek traegt ihre Link-Abhaengigkeiten NICHT weiter.
# native/cleona_video/apple/CMakeLists.txt sagt zwar
# target_link_libraries(... VideoToolbox CoreMedia CoreVideo ...), aber das
# gilt nur beim Bauen der .a -- beim Linken der App ist davon nichts mehr
# bekannt. Fehlt ein Framework hier, scheitert erst der Xcode-Link-Schritt auf
# dem macOS-Runner, mit undefinierten Symbolen statt einer Aussage darueber,
# was fehlt. Gemessen: ohne VideoToolbox meldete der Runner elf undefinierte
# Symbole (_kVTCompressionPropertyKey_*, _kVTProfileLevel_*,
# _kVTVideoEncoderSpecification_*). macOS blieb davon unberuehrt, weil dort
# eine dylib gebaut wird, die ihre Abhaengigkeiten selbst mitbringt.
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
                 # libcleona_video (§10.6): Encoder/Decoder, Sample-Buffer und
                 # Pixel-Buffer. Keines der drei verlangt einen Privacy-Key --
                 # die Kamera-/Mikrofon-Keys haengen an AVFoundation, das hier
                 # ohnehin schon steht.
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

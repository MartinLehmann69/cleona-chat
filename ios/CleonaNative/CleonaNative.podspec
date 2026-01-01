#
# CleonaNative — prebuilt native C libraries for Cleona Chat.
#
# All native libs (libsodium, liboqs, libzstd, liberasurecode, libopus,
# whisper.cpp, libcleona_audio) are merged into a single static archive
# by scripts/build-ios-libs.sh. The merged archive is force-loaded so
# that dart:ffi can find symbols via DynamicLibrary.process().
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
                 'Accelerate', 'Metal', 'MetalKit'

  s.libraries = 'c++', 'z'

  # -force_load ensures ALL object files from the merged archive are
  # included in the Runner binary, even though no ObjC/Swift code
  # references the C symbols directly. Without this, the linker
  # dead-strips everything and DynamicLibrary.process() finds nothing.
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '-force_load $(PODS_ROOT)/../CleonaNative/libcleona_all_device.a',
    'DEAD_CODE_STRIPPING' => 'NO'
  }
end

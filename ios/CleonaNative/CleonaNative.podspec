#
# CleonaNative — umbrella podspec for prebuilt native C libraries.
#
# The static .a files are built by scripts/build-ios-libs.sh and output as
# XCFrameworks in build/ios-frameworks/. The CI workflow downloads them into
# ios/CleonaNative/Frameworks/ before pod install.
#
# Locally: run ./scripts/build-ios-libs.sh, then:
#   mkdir -p ios/CleonaNative/Frameworks
#   cp -R build/ios-frameworks/*.xcframework ios/CleonaNative/Frameworks/
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

  frameworks_dir = File.join(__dir__, 'Frameworks')
  xcframeworks = Dir.glob("#{frameworks_dir}/*.xcframework").map { |f|
    Pathname.new(f).relative_path_from(Pathname.new(__dir__)).to_s
  }

  if xcframeworks.any?
    s.vendored_frameworks = xcframeworks
  end

  s.frameworks = 'AudioToolbox', 'CoreFoundation', 'AVFoundation', 'Accelerate', 'Metal', 'MetalKit'

  # Force-load all symbols from static archives so dart:ffi
  # DynamicLibrary.process() can find them at runtime.
  s.pod_target_xcconfig = {
    'OTHER_LDFLAGS' => '-ObjC -all_load',
  }
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '-ObjC -all_load',
  }
end

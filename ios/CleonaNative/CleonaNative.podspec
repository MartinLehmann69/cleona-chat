#
# CleonaNative — umbrella podspec for prebuilt native C libraries.
#
# The static .a files are built by scripts/build-ios-libs.sh and output as
# XCFrameworks in build/ios-frameworks/. This podspec links them into the
# Runner binary so dart:ffi's DynamicLibrary.process() can resolve symbols.
#
# In CI the XCFrameworks are downloaded as artifacts before `pod install`.
# Locally: run `./scripts/build-ios-libs.sh` on a Mac first.
#
Pod::Spec.new do |s|
  s.name         = 'CleonaNative'
  s.version      = '0.1.0'
  s.summary      = 'Prebuilt native libraries for Cleona (crypto, audio, codecs)'
  s.homepage     = 'https://github.com/nicokimmel/cleona'
  s.license      = { :type => 'Proprietary' }
  s.author       = 'Cleona Dev'
  s.source       = { :path => '.' }
  s.platform     = :ios, '13.0'
  s.static_framework = true

  xcfw_dir = File.expand_path('../../build/ios-frameworks', __dir__)

  # Collect all XCFrameworks that were built
  xcframeworks = Dir.glob("#{xcfw_dir}/*.xcframework").map { |f| f }

  if xcframeworks.any?
    s.vendored_frameworks = xcframeworks
  end

  # Apple frameworks required by the native libs
  s.frameworks = 'AudioToolbox', 'CoreFoundation', 'AVFAudio', 'Accelerate', 'Metal', 'MetalKit'

  # Force-load all static libs so dart:ffi DynamicLibrary.process() finds symbols
  s.pod_target_xcconfig = {
    'OTHER_LDFLAGS' => '-ObjC -all_load',
  }
end

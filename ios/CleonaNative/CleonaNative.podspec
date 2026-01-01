#
# CleonaNative — umbrella podspec for prebuilt native C libraries.
#
# The static .a files are built by scripts/build-ios-libs.sh and output as
# XCFrameworks in build/ios-frameworks/. The CI workflow downloads them into
# ios/CleonaNative/Frameworks/ before pod install.
#
# NOTE: vendored_frameworks with static .a XCFrameworks does NOT actually
# link the archives into the Runner binary with use_frameworks!(:static).
# The CI workflow injects -force_load flags post pod-install to fix this.
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

  s.pod_target_xcconfig = {
    'OTHER_LDFLAGS' => '-ObjC',
  }
end

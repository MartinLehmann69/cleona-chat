#
# CleonaNative — umbrella podspec for prebuilt native C libraries.
#
# The static .a files are built by scripts/build-ios-libs.sh and output as
# XCFrameworks in build/ios-frameworks/. The CI workflow downloads them into
# ios/CleonaNative/Frameworks/ before pod install.
#
# The Podfile post_install hook injects -force_load flags to link the .a
# files into the Runner. vendored_frameworks is NOT used because CocoaPods
# with use_frameworks!(:static) links them but then dead-strips the symbols
# that dart:ffi needs at runtime.
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

  s.frameworks = 'AudioToolbox', 'CoreFoundation', 'AVFoundation', 'Accelerate', 'Metal', 'MetalKit'
end

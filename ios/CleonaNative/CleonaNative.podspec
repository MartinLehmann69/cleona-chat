#
# CleonaNative — umbrella podspec for prebuilt native C libraries.
#
# The .a files are force-loaded via the CI workflow step into the Runner
# binary. This podspec exists only as a CocoaPods dependency anchor and
# to declare the system frameworks needed by the native libs.
#
# vendored_frameworks is intentionally NOT used — it causes duplicate
# symbols when combined with -force_load in the xcconfig.
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

  s.frameworks = 'AudioToolbox', 'CoreFoundation', 'AVFoundation', 'Accelerate', 'Metal', 'MetalKit'
end

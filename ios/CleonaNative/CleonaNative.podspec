#
# CleonaNative — umbrella podspec for prebuilt native C libraries.
#
# The .a files are linked via -force_load in the Podfile post_install hook.
# vendored_frameworks is NOT used — it causes duplicate symbols when
# combined with -force_load, and without -force_load the linker
# dead-strips symbols that dart:ffi needs at runtime.
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

  s.source_files = 'CleonaNative.h'

  s.frameworks = 'AudioToolbox', 'CoreFoundation', 'AVFoundation', 'Accelerate', 'Metal', 'MetalKit'
end

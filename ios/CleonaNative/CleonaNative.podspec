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

  # dart:ffi loads symbols at runtime via DynamicLibrary.process().
  # Without -force_load the linker dead-strips unreferenced symbols.
  # We force-load only the libs that FFI actually needs; liberasurecode
  # is excluded (Reed-Solomon is pure Dart) because its xor_hd backend
  # has unresolved deps that would break the link.
  ffi_libs = %w[libsodium liboqs libzstd libopus libcleona_audio libwhisper libggml]
  force_flags = ffi_libs.map { |name|
    xcfw = File.join(frameworks_dir, "#{name}.xcframework")
    lib_dir = File.join(xcfw, 'ios-arm64')
    lib_file = Dir.glob("#{lib_dir}/#{name}.a").first ||
               Dir.glob("#{lib_dir}/lib*.a").first
    if lib_file
      "-force_load $(PODS_ROOT)/CleonaNative/Frameworks/#{name}.xcframework/ios-arm64/#{File.basename(lib_file)}"
    end
  }.compact

  s.pod_target_xcconfig = {
    'OTHER_LDFLAGS' => '-ObjC',
  }
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => (['-ObjC'] + force_flags).join(' '),
  }
end

import Flutter
import UIKit

// Force the linker to include native FFI symbols that dart:ffi loads
// at runtime via DynamicLibrary.process(). Without references the
// linker dead-strips them from the binary.
@_silgen_name("sodium_init") func _sodium_init() -> Int32
@_silgen_name("OQS_version") func _OQS_version() -> UnsafePointer<CChar>?
@_silgen_name("ZSTD_versionNumber") func _ZSTD_versionNumber() -> UInt32
@_silgen_name("opus_get_version_string") func _opus_get_version_string() -> UnsafePointer<CChar>?
@_silgen_name("cleona_audio_init") func _cleona_audio_init(_ a: Int32, _ b: Int32, _ c: Int32) -> Int32
@_silgen_name("whisper_print_system_info") func _whisper_print_system_info() -> UnsafePointer<CChar>?

@inline(never)
private func _forceFFISymbols() {
    _ = _sodium_init
    _ = _OQS_version
    _ = _ZSTD_versionNumber
    _ = _opus_get_version_string
    _ = _cleona_audio_init
    _ = _whisper_print_system_info
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    _forceFFISymbols()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

// Force the linker to include native FFI symbols that dart:ffi
// loads at runtime via DynamicLibrary.process(). Without explicit
// references the linker dead-strips them from the final binary.

// libsodium
extern int sodium_init(void);
// liboqs
extern const char *OQS_version(void);
// libzstd
extern unsigned ZSTD_versionNumber(void);
// libopus
extern const char *opus_get_version_string(void);
// libcleona_audio
extern int cleona_audio_init(int, int, int);
// libwhisper
extern const char *whisper_print_system_info(void);

__attribute__((used))
void _cleona_force_link_ffi_symbols(void) {
    (void)sodium_init;
    (void)OQS_version;
    (void)ZSTD_versionNumber;
    (void)opus_get_version_string;
    (void)cleona_audio_init;
    (void)whisper_print_system_info;
}

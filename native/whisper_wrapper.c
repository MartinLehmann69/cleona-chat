// Dart FFI bridge for whisper.cpp.
//
// Two jobs, both of which Dart FFI cannot do on its own:
//
// 1. `whisper_full()` takes `struct whisper_full_params` BY VALUE. On x86_64
//    SysV a 264-byte struct is MEMORY class and gets copied onto the stack —
//    handing Dart's `Pointer` to it would corrupt the call. `whisper_full_from_ptr`
//    takes the params by reference and does the dereference on the C side.
//    (On ARM64 the AAPCS passes such structs indirectly anyway, which is why
//    Android works without this wrapper — see Architecture §14.9.2.1.)
//
// 2. The setters below let the C compiler compute the field offsets instead of
//    the Dart side hardcoding them. Field positions inside `whisper_full_params`
//    have moved between whisper.cpp releases (`language` sits at offset 96 in
//    v1.7.1 and at 104 in 1.8.4), and writing a pointer at the wrong offset is
//    silent: the language stays at its "en" default while neighbouring sampling
//    flags take on arbitrary pointer bytes. Where this wrapper is present,
//    `whisper_ffi.dart` prefers these setters over its runtime layout probe.
//
// Build: scripts/build-whisper-wrapper.sh

#include <whisper.h>

int whisper_full_from_ptr(struct whisper_context *ctx,
                          const struct whisper_full_params *params,
                          const float *samples,
                          int n_samples) {
    if (!ctx || !params) return -1;
    return whisper_full(ctx, *params, samples, n_samples);
}

void whisper_params_set_language(struct whisper_full_params *params,
                                 const char *language) {
    if (!params) return;
    params->language = language;
}

void whisper_params_set_n_threads(struct whisper_full_params *params,
                                  int n_threads) {
    if (!params) return;
    params->n_threads = n_threads;
}

/* cleona_voice_apple_platform.h — the internal seam between the shared VPIO
 * core and the two per-OS session layers.
 *
 * Work package: docs/SPEC_VOICE_VIDEO_REWORK.md V1.3.
 * Architecture:  Cleona_Chat_Architecture_v3_0.md §10.4 (normative).
 *
 * ---------------------------------------------------------------------------
 * WHY THIS SEAM EXISTS
 * ---------------------------------------------------------------------------
 * §10.4's platform matrix gives iOS and macOS the SAME row — "same AudioUnit,
 * one shared implementation with iOS". That is true for the part that matters:
 * kAudioUnitSubType_VoiceProcessingIO, its BypassVoiceProcessing and AGC
 * properties, the frame contract, the ring buffers and the verification report
 * are literally one file (cleona_voice_apple.c).
 *
 * What is NOT shared is everything around the unit:
 *
 *   iOS    AVAudioSession — category `playAndRecord`, **mode `voiceChat`**,
 *          route observation via AVAudioSession.currentRoute, route control via
 *          overrideOutputAudioPort/setPreferredInput. Objective-C only; there
 *          is no C entry point for any of it.
 *   macOS  CoreAudio HAL — there is no AVAudioSession at all. Routes are
 *          derived from the default output device's transport type, and there
 *          is no earpiece (§10.4: "macOS, Windows and Linux have no earpiece").
 *
 * Hiding that difference behind six functions keeps the ObjC surface down to
 * one file. cleona_voice_apple.c contains no `#if TARGET_OS_*` for anything but
 * the two framework-specific detail comments.
 *
 * ---------------------------------------------------------------------------
 * OWNERSHIP NOTE
 * ---------------------------------------------------------------------------
 * Interruption handling (AVAudioSessionInterruptionNotification), `duckOthers`
 * and audio focus belong to work package **V1.10** (`ios/Runner/`,
 * `lib/core/calls/session_behaviour.dart`), NOT here. This layer therefore
 * observes route changes and nothing else, and the backend never emits
 * CLEONA_VOICE_EV_INTERRUPTION_BEGIN/END. That is a deliberate ownership
 * boundary, not an omission — see the file header of cleona_voice_apple.c.
 */

#ifndef CLEONA_VOICE_APPLE_PLATFORM_H
#define CLEONA_VOICE_APPLE_PLATFORM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct cva_platform cva_platform_t;

/* Called from the route-change notification of the OS, on whatever thread the
 * OS posts it on. The implementation of this callback (in cleona_voice_apple.c)
 * only takes the session lock briefly and queues an event, so it is safe from
 * a CoreAudio listener thread and from an NSNotificationCenter post. */
typedef void (*cva_route_changed_fn)(void* ctx);

/* Opens the per-OS session layer and makes the route set observable.
 *
 * iOS:   sets AVAudioSession category `playAndRecord` + mode `voiceChat` and
 *        activates the session, then registers a routeChangeNotification
 *        observer. Activation happens HERE rather than in cleona_voice_start()
 *        on purpose: cleona_voice_open() has to report a negotiated sample rate
 *        and a route set, and both are only *observations* once the session is
 *        active. Reporting them from an inactive session would be a guess, and
 *        I3/I11 do not permit guesses.
 * macOS: registers CoreAudio HAL property listeners on the device list and on
 *        the default input/output device.
 *
 * Returns CLEONA_VOICE_OK, or a negative CLEONA_VOICE_ERR_* (in particular
 * CLEONA_VOICE_ERR_PERMISSION when the microphone permission is known to be
 * denied, and CLEONA_VOICE_ERR_BACKEND when the OS refused the configuration).
 * On failure *out is left NULL. */
int32_t cva_platform_open(cva_route_changed_fn cb, void* ctx,
                          cva_platform_t** out);

/* Releases the layer: removes the observers and, on iOS, drops this session's
 * reference on the shared AVAudioSession activation. NULL is a no-op. */
void cva_platform_close(cva_platform_t* p);

/* The sample rate the hardware is running at right now, in Hz, or 0 when the
 * platform cannot report one. NEVER a constant — I3. */
double cva_platform_hardware_rate(cva_platform_t* p);

/* Current route observation. All three out-pointers must be non-NULL.
 *
 * `mask` is a CLEONA_VOICE_ROUTE_BIT() bitmask and never contains bit 0
 * (ROUTE_UNKNOWN is a state, not a route). `active_out` is ROUTE_UNKNOWN only
 * when the platform genuinely has not resolved a route yet. */
void cva_platform_routes(cva_platform_t* p, int32_t* mask,
                         int32_t* active_in, int32_t* active_out);

/* Switches the active OUTPUT route. `route` has already been validated by the
 * caller to be one of EARPIECE/SPEAKER/WIRED/BLUETOOTH and to be present in the
 * current mask, so this function only has to perform the switch or explain why
 * it cannot. Returns CLEONA_VOICE_OK or a negative CLEONA_VOICE_ERR_*. */
int32_t cva_platform_set_route(cva_platform_t* p, int32_t route);

/* "ios" / "macos" — used only in log-style strings, never parsed. */
const char* cva_platform_name(void);

#ifdef __cplusplus
}
#endif

#endif /* CLEONA_VOICE_APPLE_PLATFORM_H */

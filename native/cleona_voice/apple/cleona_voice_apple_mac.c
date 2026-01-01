/* cleona_voice_apple_mac.c — the macOS half of the Apple voice backend:
 * CoreAudio HAL route observation.
 *
 * Work package: docs/SPEC_VOICE_VIDEO_REWORK.md V1.3.
 * Architecture:  Cleona_Chat_Architecture_v3_0.md §10.4 (normative), §24
 *                (macOS is tier 2 — "at runtime the user experience matches
 *                Linux").
 *
 * ===========================================================================
 * WHAT IS SHARED WITH iOS AND WHAT IS NOT
 * ===========================================================================
 * §10.4's platform matrix puts macOS and iOS on the same AudioUnit: "same
 * AudioUnit, one shared implementation with iOS". That is exactly true of
 * cleona_voice_apple.c — the VPIO instance, both mandatory properties, the
 * frame contract, the rings and the verification report are one file.
 *
 * What macOS does not have is AVAudioSession. There is no category, no mode, no
 * overrideOutputAudioPort and no route-change notification. Routes are derived
 * from the HAL: the default output device's transport type is the route, and
 * the set of devices that can play audio is the route set.
 *
 * ===========================================================================
 * NO EARPIECE, AND WHY set_route DECLINES
 * ===========================================================================
 * §10.4: "macOS, Windows and Linux have no earpiece — there 'speaker' is not a
 * toggle but an output device selection, and the UI shows a device chooser
 * rather than a button that does nothing." CLEONA_VOICE_ROUTE_EARPIECE is
 * therefore never in the mask, and cleona_voice_set_route() answers
 * CLEONA_VOICE_ERR_ROUTE_UNAVAILABLE for it — the defined code SPEC §4 demands
 * instead of a silent no-op.
 *
 * For a route that IS in the mask, this backend returns
 * CLEONA_VOICE_ERR_ROUTE_UNSUPPORTED rather than switching. That is a stated
 * property, not an omission, and it rests on two facts:
 *
 *  1. The ABI switches ROUTE KINDS (earpiece / speaker / wired / bluetooth).
 *     On macOS a "kind" routinely maps to several devices — two USB interfaces
 *     are both WIRED — so a kind is not enough information to pick one. What
 *     the desktop needs is a device chooser, which §10.4 says in as many words
 *     and which V1.6 owns on the UI side. Expressing that would take an ABI
 *     extension (a device list with ids), and `cleona_voice.h` belongs to V0.2,
 *     not to this package.
 *  2. Re-pointing an already-initialised VPIO instance at another device means
 *     AudioOutputUnitStop + AudioUnitUninitialize + set CurrentDevice +
 *     AudioUnitInitialize + AudioOutputUnitStart. That is a full stream
 *     rebuild, and rule 4 of §10.4 ("every switch without tearing the stream
 *     down, so the AEC stays converged") allows it only "where a platform
 *     forces a rebuild" — which is not the case here, because the user can
 *     change the system output device without the call losing its stream at
 *     all. Rebuilding to reach the same end state would cost AEC convergence
 *     for nothing.
 *
 * Route OBSERVATION is fully implemented: the mask, the active route and the
 * CLEONA_VOICE_EV_ROUTES_CHANGED event all follow the HAL live, so RoutePolicy
 * (V1.5) sees a truthful device set at all times. Conformance check S5 accepts
 * ERR_ROUTE_UNAVAILABLE or ERR_ROUTE_UNSUPPORTED and S9 records a declined
 * switch as an observation, so this is a conformant answer, not an exemption.
 */

#include "cleona_voice_apple_platform.h"
#include "../cleona_voice.h"

#include <TargetConditionals.h>

#if TARGET_OS_OSX

#include "cleona_voice_apple_live.h"

#include <CoreAudio/CoreAudio.h>

#include <pthread.h>
#include <stdlib.h>
#include <string.h>

/* kAudioObjectPropertyElementMain arrived in the macOS 12 SDK; the deployment
 * target here is 10.15/11.0 (macos/Runner.xcodeproj, scripts/build-macos-libs.sh).
 * Both spellings are the constant 0, so this picks whichever the SDK in use
 * declares and avoids a deprecation warning on new SDKs without breaking old
 * ones. */
#if defined(__MAC_OS_X_VERSION_MAX_ALLOWED) && __MAC_OS_X_VERSION_MAX_ALLOWED >= 120000
  #define CVA_ELEM kAudioObjectPropertyElementMain
#else
  #define CVA_ELEM kAudioObjectPropertyElementMaster
#endif

/* Four-character codes returned by kAudioDevicePropertyDataSource for the
 * built-in output. Apple ships no named constants for them, and a multi-
 * character literal ('hdpn') is implementation-defined and warns under
 * -Wpedantic, so they are spelled as the bytes they are. */
#define CVA_SRC_HEADPHONES 0x6864706EU  /* 'hdpn' */
#define CVA_SRC_INT_SPEAKER 0x6973706BU /* 'ispk' */

struct cva_platform {
    pthread_mutex_t lock;
    cva_route_changed_fn cb;
    void* ctx;
    int listening;
};

/* ==========================================================================
 * HAL helpers
 * ========================================================================== */

static int cva_get_u32(AudioObjectID obj, AudioObjectPropertySelector sel,
                       AudioObjectPropertyScope scope, UInt32* out) {
    AudioObjectPropertyAddress addr;
    addr.mSelector = sel;
    addr.mScope    = scope;
    addr.mElement  = CVA_ELEM;
    UInt32 size = (UInt32)sizeof(*out);
    return AudioObjectGetPropertyData(obj, &addr, 0, NULL, &size, out) == noErr;
}

static AudioObjectID cva_default_device(AudioObjectPropertySelector sel) {
    AudioObjectID dev = kAudioObjectUnknown;
    AudioObjectPropertyAddress addr;
    addr.mSelector = sel;
    addr.mScope    = kAudioObjectPropertyScopeGlobal;
    addr.mElement  = CVA_ELEM;
    UInt32 size = (UInt32)sizeof(dev);
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, NULL,
                                   &size, &dev) != noErr) {
        return kAudioObjectUnknown;
    }
    return dev;
}

/* Does this device have at least one channel in `scope`? */
static int cva_device_has_channels(AudioObjectID dev, AudioObjectPropertyScope scope) {
    AudioObjectPropertyAddress addr;
    addr.mSelector = kAudioDevicePropertyStreamConfiguration;
    addr.mScope    = scope;
    addr.mElement  = CVA_ELEM;

    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(dev, &addr, 0, NULL, &size) != noErr || size == 0) {
        return 0;
    }
    AudioBufferList* abl = (AudioBufferList*)malloc(size);
    if (!abl) return 0;
    int has = 0;
    if (AudioObjectGetPropertyData(dev, &addr, 0, NULL, &size, abl) == noErr) {
        for (UInt32 i = 0; i < abl->mNumberBuffers; i++) {
            if (abl->mBuffers[i].mNumberChannels > 0) { has = 1; break; }
        }
    }
    free(abl);
    return has;
}

/* Transport type -> CLEONA_VOICE_ROUTE_*.
 *
 * The mapping is deliberately coarse, because the ABI's route enum is
 * phone-shaped and macOS is not a phone:
 *   built-in + data source 'hdpn'  -> WIRED      (the headphone jack)
 *   built-in, anything else        -> SPEAKER    (the internal speakers)
 *   Bluetooth / Bluetooth LE       -> BLUETOOTH
 *   everything else                -> WIRED      (USB/Thunderbolt/HDMI/DP/
 *                                                 AirPlay/aggregate/virtual)
 * "Everything else is WIRED" is a choice, and the reason it is defensible is
 * what the route set is USED for: RoutePolicy's rule 1 ("a headset appears,
 * switch to it") and rule 2 (the I7 fallback) treat every non-Bluetooth
 * external output identically. Never EARPIECE — macOS has none. */
static int32_t cva_route_for_device(AudioObjectID dev, AudioObjectPropertyScope scope) {
    UInt32 transport = 0;
    if (!cva_get_u32(dev, kAudioDevicePropertyTransportType,
                     kAudioObjectPropertyScopeGlobal, &transport)) {
        return CLEONA_VOICE_ROUTE_WIRED;
    }
    if (transport == kAudioDeviceTransportTypeBluetooth ||
        transport == kAudioDeviceTransportTypeBluetoothLE) {
        return CLEONA_VOICE_ROUTE_BLUETOOTH;
    }
    if (transport == kAudioDeviceTransportTypeBuiltIn) {
        UInt32 src = 0;
        if (cva_get_u32(dev, kAudioDevicePropertyDataSource, scope, &src)) {
            if (src == CVA_SRC_HEADPHONES) return CLEONA_VOICE_ROUTE_WIRED;
            if (src == CVA_SRC_INT_SPEAKER) return CLEONA_VOICE_ROUTE_SPEAKER;
        }
        return CLEONA_VOICE_ROUTE_SPEAKER;
    }
    return CLEONA_VOICE_ROUTE_WIRED;
}

static void cva_probe_routes(int32_t* out_mask, int32_t* out_in, int32_t* out_out) {
    int32_t mask = 0;
    int32_t active_out = CLEONA_VOICE_ROUTE_UNKNOWN;
    int32_t active_in  = CLEONA_VOICE_ROUTE_UNKNOWN;

    AudioObjectID def_out = cva_default_device(kAudioHardwarePropertyDefaultOutputDevice);
    AudioObjectID def_in  = cva_default_device(kAudioHardwarePropertyDefaultInputDevice);

    if (def_out != kAudioObjectUnknown) {
        active_out = cva_route_for_device(def_out, kAudioObjectPropertyScopeOutput);
    }
    if (def_in != kAudioObjectUnknown) {
        active_in = cva_route_for_device(def_in, kAudioObjectPropertyScopeInput);
    }

    /* The full device list is what makes the mask an observation of the machine
     * rather than of the one device that happens to be default right now —
     * RoutePolicy needs to see a headset appear before it is selected. */
    AudioObjectPropertyAddress addr;
    addr.mSelector = kAudioHardwarePropertyDevices;
    addr.mScope    = kAudioObjectPropertyScopeGlobal;
    addr.mElement  = CVA_ELEM;
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &addr, 0, NULL,
                                       &size) == noErr && size > 0) {
        AudioObjectID* devs = (AudioObjectID*)malloc(size);
        if (devs) {
            if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, NULL,
                                           &size, devs) == noErr) {
                UInt32 n = size / (UInt32)sizeof(AudioObjectID);
                for (UInt32 i = 0; i < n; i++) {
                    if (!cva_device_has_channels(devs[i], kAudioObjectPropertyScopeOutput)) {
                        continue;
                    }
                    int32_t r = cva_route_for_device(devs[i], kAudioObjectPropertyScopeOutput);
                    if (r != CLEONA_VOICE_ROUTE_UNKNOWN) {
                        mask |= CLEONA_VOICE_ROUTE_BIT(r);
                    }
                }
            }
            free(devs);
        }
    }

    /* SPEC §6 check 8: on a started session the active route is in the mask.
     * If the enumeration above came up empty (a machine with no output device
     * at all, or a HAL that refused the query), the active route is still the
     * one observed fact available, so it goes in — a mask without it would be
     * a report contradicting itself. */
    if (active_out != CLEONA_VOICE_ROUTE_UNKNOWN) {
        mask |= CLEONA_VOICE_ROUTE_BIT(active_out);
    }

    *out_mask = mask;
    *out_in   = active_in;
    *out_out  = active_out;
}

/* ==========================================================================
 * HAL property listener
 * ========================================================================== */

static const AudioObjectPropertySelector cva_watch[] = {
    kAudioHardwarePropertyDevices,
    kAudioHardwarePropertyDefaultOutputDevice,
    kAudioHardwarePropertyDefaultInputDevice,
};
#define CVA_WATCH_N ((int)(sizeof(cva_watch) / sizeof(cva_watch[0])))

static OSStatus cva_hal_listener(AudioObjectID obj, UInt32 n,
                                 const AudioObjectPropertyAddress* addrs,
                                 void* ctx) {
    (void)obj;
    (void)n;
    (void)addrs;
    cva_platform_t* p = (cva_platform_t*)ctx;
    /* The registry is what makes this safe against a concurrent teardown: `p`
     * is compared, not dereferenced, until it is known to be live.
     * See cleona_voice_apple_live.h. */
    pthread_mutex_lock(&cva_live_lock);
    if (cva_live_contains_locked(p) && p->cb) {
        p->cb(p->ctx);
    }
    pthread_mutex_unlock(&cva_live_lock);
    return noErr;
}

static void cva_listeners(cva_platform_t* p, int add) {
    for (int i = 0; i < CVA_WATCH_N; i++) {
        AudioObjectPropertyAddress addr;
        addr.mSelector = cva_watch[i];
        addr.mScope    = kAudioObjectPropertyScopeGlobal;
        addr.mElement  = CVA_ELEM;
        if (add) {
            AudioObjectAddPropertyListener(kAudioObjectSystemObject, &addr,
                                           cva_hal_listener, p);
        } else {
            AudioObjectRemovePropertyListener(kAudioObjectSystemObject, &addr,
                                              cva_hal_listener, p);
        }
    }
}

/* ==========================================================================
 * cva_platform_* — the seam declared in cleona_voice_apple_platform.h
 * ========================================================================== */

int32_t cva_platform_open(cva_route_changed_fn cb, void* ctx,
                          cva_platform_t** out) {
    if (!out) return CLEONA_VOICE_ERR_INVALID_ARG;
    *out = NULL;

    /* There is no AVAudioSession to configure and no permission API that can be
     * queried from plain C without pulling AVFoundation into a file that needs
     * nothing else from it. macOS microphone permission (TCC) is granted
     * against NSMicrophoneUsageDescription in macos/Runner/Info.plist — see
     * BUILD_REQUEST_V1.3.md §3, which is a real gap on this branch. A denial
     * surfaces as a failing AudioUnitInitialize or as silence, never as a
     * fabricated success here. */

    cva_platform_t* p = (cva_platform_t*)calloc(1, sizeof(cva_platform_t));
    if (!p) return CLEONA_VOICE_ERR_BACKEND;
    pthread_mutex_init(&p->lock, NULL);
    p->cb  = cb;
    p->ctx = ctx;

    if (!cva_live_add(p)) {
        pthread_mutex_destroy(&p->lock);
        free(p);
        return CLEONA_VOICE_ERR_BACKEND;
    }
    cva_listeners(p, 1);
    p->listening = 1;

    *out = p;
    return CLEONA_VOICE_OK;
}

void cva_platform_close(cva_platform_t* p) {
    if (!p) return;
    if (p->listening) {
        cva_listeners(p, 0);
        p->listening = 0;
    }
    /* Removing the listener stops NEW invocations; dropping the registry entry
     * waits out one that is already inside its critical section. Only then is
     * it safe to free — see cleona_voice_apple_live.h. */
    cva_live_remove(p);
    pthread_mutex_destroy(&p->lock);
    free(p);
}

double cva_platform_hardware_rate(cva_platform_t* p) {
    (void)p;
    /* I3: the capture device's nominal rate. The VPIO instance converts between
     * this and the client format itself; nothing here resamples, and nothing
     * here assumes 48 kHz — a 96 kHz interface is ordinary on this platform and
     * is handled by cva_choose_rate() in cleona_voice_apple.c, in the open. */
    AudioObjectID dev = cva_default_device(kAudioHardwarePropertyDefaultInputDevice);
    if (dev == kAudioObjectUnknown) {
        dev = cva_default_device(kAudioHardwarePropertyDefaultOutputDevice);
    }
    if (dev == kAudioObjectUnknown) return 0.0;

    AudioObjectPropertyAddress addr;
    addr.mSelector = kAudioDevicePropertyNominalSampleRate;
    addr.mScope    = kAudioObjectPropertyScopeGlobal;
    addr.mElement  = CVA_ELEM;
    Float64 rate = 0.0;
    UInt32 size = (UInt32)sizeof(rate);
    if (AudioObjectGetPropertyData(dev, &addr, 0, NULL, &size, &rate) != noErr) {
        return 0.0;
    }
    return (double)rate;
}

void cva_platform_routes(cva_platform_t* p, int32_t* mask,
                         int32_t* active_in, int32_t* active_out) {
    if (!mask || !active_in || !active_out) return;
    if (!p) {
        *mask = 0;
        *active_in = CLEONA_VOICE_ROUTE_UNKNOWN;
        *active_out = CLEONA_VOICE_ROUTE_UNKNOWN;
        return;
    }
    cva_probe_routes(mask, active_in, active_out);
}

int32_t cva_platform_set_route(cva_platform_t* p, int32_t route) {
    (void)p;
    (void)route;
    /* Declined by design, with the full reasoning in the file header. The
     * caller has already handled "already active" (OK) and "not in the mask"
     * (ERR_ROUTE_UNAVAILABLE), so the only case reaching here is a switch
     * between kinds that both exist — which on macOS is a DEVICE choice the
     * ABI cannot express and the user makes in the device chooser (§10.4). */
    return CLEONA_VOICE_ERR_ROUTE_UNSUPPORTED;
}

const char* cva_platform_name(void) { return "macos"; }

#else  /* !TARGET_OS_OSX */

/* Selected by CMake for macOS targets only; see the matching note in
 * cleona_voice_apple_ios.m. */
typedef int cleona_voice_apple_mac_not_built_here;

#endif /* TARGET_OS_OSX */

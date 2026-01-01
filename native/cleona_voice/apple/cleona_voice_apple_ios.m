/* cleona_voice_apple_ios.m — the iOS half of the Apple voice backend:
 * AVAudioSession configuration, route observation and route control.
 *
 * Work package: docs/SPEC_VOICE_VIDEO_REWORK.md V1.3.
 * Architecture:  Cleona_Chat_Architecture_v3_0.md §10.4 (normative), §24 (iOS
 *                is the most restrictive of the five platforms).
 *
 * ===========================================================================
 * THE ONE LINE THAT WAS MISSING FOR YEARS
 * ===========================================================================
 * §10.4, defect row 3: "grep setMode = 0". The superseded stack never set an
 * AVAudioSession MODE. Category alone is not enough: `playAndRecord` with the
 * default mode gives a media-playback session — no voice processing tuning, the
 * speaker as the default output, and no guarantee that the input path is the
 * one VPIO expects. SPEC §7 V1.3 makes both mandatory:
 *
 *     category  AVAudioSessionCategoryPlayAndRecord
 *     mode      AVAudioSessionModeVoiceChat        <-- was absent entirely
 *
 * Both are set in cva_platform_open() below, before the AudioUnit exists,
 * because the unit inherits the session's hardware configuration at
 * instantiation time.
 *
 * ===========================================================================
 * WHAT THIS FILE DELIBERATELY DOES NOT DO
 * ===========================================================================
 *  - No `duckOthers`, no AVAudioSessionInterruptionNotification handling, no
 *    audio focus. Those are work package **V1.10** (`ios/Runner/`,
 *    `lib/core/calls/session_behaviour.dart`). Doing them here as well would
 *    put two owners on one behaviour, which SPEC §9 exists to prevent.
 *  - No `AVAudioSessionCategoryOptionDefaultToSpeaker`. That option makes the
 *    speaker the default output and would break **I7** ("a phone does not blast
 *    the room") at the source, before RoutePolicy ever sees a decision.
 *  - No explicit `AllowBluetooth` option: Apple documents it as implicitly set
 *    by mode `voiceChat`. Naming it explicitly would mean spelling either the
 *    constant deprecated in iOS 18 or its replacement, for a behaviour the mode
 *    already guarantees.
 */

#include "cleona_voice_apple_platform.h"
#include "../cleona_voice.h"

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

#include <TargetConditionals.h>

#if TARGET_OS_IOS

#include "cleona_voice_apple_live.h"

#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* ==========================================================================
 * Shared AVAudioSession activation
 * ==========================================================================
 * AVAudioSession is a process singleton, so two overlapping cleona_voice
 * sessions must not deactivate each other's audio. The conformance harness
 * opens exactly that constellation (cleona_voice.h note "N3": a second open()
 * while the first session is live), so it is not a hypothetical.
 */
static pthread_mutex_t g_act_lock  = PTHREAD_MUTEX_INITIALIZER;
static int             g_act_count = 0;

static int cva_session_retain(NSError** err) {
    int ok = 1;
    pthread_mutex_lock(&g_act_lock);
    if (g_act_count == 0) {
        ok = [[AVAudioSession sharedInstance] setActive:YES error:err] ? 1 : 0;
    }
    if (ok) g_act_count++;
    pthread_mutex_unlock(&g_act_lock);
    return ok;
}

static void cva_session_release(void) {
    pthread_mutex_lock(&g_act_lock);
    if (g_act_count > 0) g_act_count--;
    if (g_act_count == 0) {
        [[AVAudioSession sharedInstance]
            setActive:NO
          withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                error:nil];
    }
    pthread_mutex_unlock(&g_act_lock);
}

/* ==========================================================================
 * Port type -> CLEONA_VOICE_ROUTE_*
 * ==========================================================================
 * The ABI's route enum is phone-shaped, which fits iOS better than any other
 * platform. The only judgement call is where to put the "external, not
 * Bluetooth" ports (USB, HDMI, AirPlay, line out, CarPlay): they all become
 * WIRED, because what the route set is used for — RoutePolicy's rule 1 ("a
 * headset appears, switch to it") and rule 2 (I7 fallback) — treats them
 * identically, and inventing a fifth route would be an ABI change this package
 * does not own.
 */
static int32_t cva_out_route_for_port(NSString* t) {
    if ([t isEqualToString:AVAudioSessionPortBuiltInReceiver]) return CLEONA_VOICE_ROUTE_EARPIECE;
    if ([t isEqualToString:AVAudioSessionPortBuiltInSpeaker])  return CLEONA_VOICE_ROUTE_SPEAKER;
    if ([t isEqualToString:AVAudioSessionPortBluetoothA2DP] ||
        [t isEqualToString:AVAudioSessionPortBluetoothHFP]  ||
        [t isEqualToString:AVAudioSessionPortBluetoothLE])     return CLEONA_VOICE_ROUTE_BLUETOOTH;
    if ([t isEqualToString:AVAudioSessionPortHeadphones] ||
        [t isEqualToString:AVAudioSessionPortUSBAudio]   ||
        [t isEqualToString:AVAudioSessionPortLineOut]    ||
        [t isEqualToString:AVAudioSessionPortHDMI]       ||
        [t isEqualToString:AVAudioSessionPortAirPlay]    ||
        [t isEqualToString:AVAudioSessionPortCarAudio])        return CLEONA_VOICE_ROUTE_WIRED;
    return CLEONA_VOICE_ROUTE_UNKNOWN;
}

static int32_t cva_in_route_for_port(NSString* t) {
    if ([t isEqualToString:AVAudioSessionPortBluetoothHFP] ||
        [t isEqualToString:AVAudioSessionPortBluetoothLE]) return CLEONA_VOICE_ROUTE_BLUETOOTH;
    if ([t isEqualToString:AVAudioSessionPortHeadsetMic] ||
        [t isEqualToString:AVAudioSessionPortUSBAudio]   ||
        [t isEqualToString:AVAudioSessionPortLineIn]     ||
        [t isEqualToString:AVAudioSessionPortCarAudio])   return CLEONA_VOICE_ROUTE_WIRED;
    /* Built-in mic: the ABI has no value for it. On Apple hardware the built-in
     * mic and the built-in outputs are one device, so the honest answer is the
     * built-in OUTPUT currently in use — resolved by the caller, which knows
     * it. Signalled as UNKNOWN here rather than guessed. */
    return CLEONA_VOICE_ROUTE_UNKNOWN;
}

/* ==========================================================================
 * Platform object
 * ========================================================================== */

struct cva_platform {
    pthread_mutex_t lock;

    cva_route_changed_fn cb;
    void*                ctx;

    void* observer;   /* __bridge_retained id, removed in cva_platform_close */

    /* Whether this device HAS an earpiece is not exposed by any iOS API. It is
     * therefore observed, not assumed:
     *   earpiece_seen       the receiver was actually the output at least once
     *   earpiece_ruled_out  the built-in speaker was the output while no
     *                       speaker override was in force. In mode voiceChat a
     *                       device with a receiver routes to the receiver by
     *                       default, so this is positive evidence of absence
     *                       (iPad, iPod touch).
     * Until one of the two is established the earpiece bit stays OUT of the
     * mask — I11's rule applied to the route set: not determinable is not the
     * same as available. */
    int earpiece_seen;
    int earpiece_ruled_out;
    int speaker_override;
};

/* --------------------------------------------------------------------------
 * Route observation. Recomputed from AVAudioSession on every call; nothing is
 * cached, because a cached route is an old observation wearing the clothes of
 * a current one.
 * -------------------------------------------------------------------------- */
static void cva_probe_routes(cva_platform_t* p, int32_t* out_mask,
                             int32_t* out_in, int32_t* out_out) {
    AVAudioSession* sess = [AVAudioSession sharedInstance];
    AVAudioSessionRouteDescription* route = sess.currentRoute;

    /* Every iOS device has a built-in speaker. That is a hardware fact, not an
     * inference from a property we failed to read. */
    int32_t mask = CLEONA_VOICE_ROUTE_BIT(CLEONA_VOICE_ROUTE_SPEAKER);
    int32_t active_out = CLEONA_VOICE_ROUTE_UNKNOWN;

    for (AVAudioSessionPortDescription* o in route.outputs) {
        int32_t r = cva_out_route_for_port(o.portType);
        if (r == CLEONA_VOICE_ROUTE_UNKNOWN) continue;
        if (active_out == CLEONA_VOICE_ROUTE_UNKNOWN) active_out = r;
        if (r != CLEONA_VOICE_ROUTE_EARPIECE) mask |= CLEONA_VOICE_ROUTE_BIT(r);
    }

    /* Accessories are visible as available INPUTS even before they carry the
     * output route, which is what makes RoutePolicy's rule 1 actionable. */
    for (AVAudioSessionPortDescription* i in sess.availableInputs) {
        int32_t r = cva_in_route_for_port(i.portType);
        if (r == CLEONA_VOICE_ROUTE_WIRED || r == CLEONA_VOICE_ROUTE_BLUETOOTH) {
            mask |= CLEONA_VOICE_ROUTE_BIT(r);
        }
    }

    pthread_mutex_lock(&p->lock);
    if (active_out == CLEONA_VOICE_ROUTE_EARPIECE) {
        p->earpiece_seen = 1;
    } else if (active_out == CLEONA_VOICE_ROUTE_SPEAKER && !p->speaker_override) {
        p->earpiece_ruled_out = 1;
    }
    int has_earpiece = p->earpiece_seen && !p->earpiece_ruled_out;
    pthread_mutex_unlock(&p->lock);

    if (has_earpiece) mask |= CLEONA_VOICE_ROUTE_BIT(CLEONA_VOICE_ROUTE_EARPIECE);

    int32_t active_in = CLEONA_VOICE_ROUTE_UNKNOWN;
    for (AVAudioSessionPortDescription* i in route.inputs) {
        int32_t r = cva_in_route_for_port(i.portType);
        if (r != CLEONA_VOICE_ROUTE_UNKNOWN) { active_in = r; break; }
    }
    if (active_in == CLEONA_VOICE_ROUTE_UNKNOWN) {
        /* Built-in mic — see cva_in_route_for_port(). It belongs to the same
         * built-in device as the active built-in output. */
        if (active_out == CLEONA_VOICE_ROUTE_EARPIECE ||
            active_out == CLEONA_VOICE_ROUTE_SPEAKER) {
            active_in = active_out;
        }
    }

    /* A started session must report an active output route that is in the mask
     * (SPEC §6 check 8). If iOS reported a port this file does not map, the
     * built-in speaker is the one route guaranteed to exist AND to be in the
     * mask — and the unmapped port stays visible in the log line through the
     * route it was NOT given, rather than through a fabricated bit. */
    if (active_out == CLEONA_VOICE_ROUTE_UNKNOWN) active_out = CLEONA_VOICE_ROUTE_SPEAKER;
    if (!(mask & CLEONA_VOICE_ROUTE_BIT(active_out))) {
        mask |= CLEONA_VOICE_ROUTE_BIT(active_out);
    }

    *out_mask = mask;
    *out_in   = active_in;
    *out_out  = active_out;
}

/* --------------------------------------------------------------------------
 * Microphone permission — a precise ABI error code instead of silence.
 * -------------------------------------------------------------------------- */
static int cva_mic_permission_denied(void) {
    /* The SDK guard is separate from the runtime guard on purpose: @available
     * decides whether the class EXISTS at run time, the #if decides whether the
     * SDK being compiled against declares it at all. build-ios-libs.sh sets a
     * 13.0 deployment target, so both questions are live. */
#if defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 170000
    if (@available(iOS 17.0, *)) {
        return AVAudioApplication.sharedInstance.recordPermission
               == AVAudioApplicationRecordPermissionDenied;
    }
#endif
    /* Below iOS 17 AVAudioApplication does not exist and
     * -[AVAudioSession recordPermission] is the ONLY way to ask. The
     * deployment target is 15.5 (ios/Runner), so dropping the check would mean
     * iOS 15 and 16 users get "no audio" instead of ERR_PERMISSION. The
     * diagnostic is silenced for exactly this one expression and nothing else;
     * the API is deprecated, not removed. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [AVAudioSession sharedInstance].recordPermission
           == AVAudioSessionRecordPermissionDenied;
#pragma clang diagnostic pop
}

/* ==========================================================================
 * cva_platform_* — the seam declared in cleona_voice_apple_platform.h
 * ========================================================================== */

int32_t cva_platform_open(cva_route_changed_fn cb, void* ctx,
                          cva_platform_t** out) {
    if (!out) return CLEONA_VOICE_ERR_INVALID_ARG;
    *out = NULL;

    if (cva_mic_permission_denied()) return CLEONA_VOICE_ERR_PERMISSION;

    cva_platform_t* p = (cva_platform_t*)calloc(1, sizeof(cva_platform_t));
    if (!p) return CLEONA_VOICE_ERR_BACKEND;
    pthread_mutex_init(&p->lock, NULL);
    p->cb  = cb;
    p->ctx = ctx;

    AVAudioSession* sess = [AVAudioSession sharedInstance];
    NSError* err = nil;

    /* SPEC §7 V1.3, mandatory: category AND mode. Options deliberately 0 —
     * see the file header for why neither AllowBluetooth nor DefaultToSpeaker
     * is spelled out here. */
    if (![sess setCategory:AVAudioSessionCategoryPlayAndRecord
                      mode:AVAudioSessionModeVoiceChat
                   options:0
                     error:&err]) {
        pthread_mutex_destroy(&p->lock);
        free(p);
        return CLEONA_VOICE_ERR_BACKEND;
    }

    if (!cva_session_retain(&err)) {
        pthread_mutex_destroy(&p->lock);
        free(p);
        return CLEONA_VOICE_ERR_BACKEND;
    }

    if (!cva_live_add(p)) {
        cva_session_release();
        pthread_mutex_destroy(&p->lock);
        free(p);
        return CLEONA_VOICE_ERR_BACKEND;
    }

    /* queue:nil means the block runs synchronously on the posting thread, so no
     * dispatch queue has to stay alive for the notification to be delivered —
     * and the liveness registry (cleona_voice_apple_live.h) is what makes that
     * safe against a concurrent teardown. */
    id token = [[NSNotificationCenter defaultCenter]
        addObserverForName:AVAudioSessionRouteChangeNotification
                    object:sess
                     queue:nil
                usingBlock:^(NSNotification* _Nonnull note) {
        (void)note;
        pthread_mutex_lock(&cva_live_lock);
        if (cva_live_contains_locked(p) && p->cb) {
            p->cb(p->ctx);
        }
        pthread_mutex_unlock(&cva_live_lock);
    }];
    p->observer = (__bridge_retained void*)token;

    *out = p;
    return CLEONA_VOICE_OK;
}

void cva_platform_close(cva_platform_t* p) {
    if (!p) return;

    if (p->observer) {
        id token = (__bridge_transfer id)p->observer;
        p->observer = NULL;
        [[NSNotificationCenter defaultCenter] removeObserver:token];
    }
    /* Order matters: the observer is gone, so no NEW block starts. Dropping the
     * registry entry then waits out any block already inside its critical
     * section — after this returns, no callback can touch `p` or the session. */
    cva_live_remove(p);

    cva_session_release();
    pthread_mutex_destroy(&p->lock);
    free(p);
}

double cva_platform_hardware_rate(cva_platform_t* p) {
    (void)p;
    /* I3: whatever the hardware is running at right now. On a Bluetooth HFP
     * route this is 8 or 16 kHz, on the built-in path 48 kHz — and the caller
     * computes with the value, never with a constant. */
    return (double)[AVAudioSession sharedInstance].sampleRate;
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
    cva_probe_routes(p, mask, active_in, active_out);
}

int32_t cva_platform_set_route(cva_platform_t* p, int32_t route) {
    if (!p) return CLEONA_VOICE_ERR_CLOSED;

    AVAudioSession* sess = [AVAudioSession sharedInstance];
    NSError* err = nil;

    if (route == CLEONA_VOICE_ROUTE_SPEAKER) {
        if (![sess overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker
                                     error:&err]) {
            return CLEONA_VOICE_ERR_BACKEND;
        }
        pthread_mutex_lock(&p->lock);
        p->speaker_override = 1;
        pthread_mutex_unlock(&p->lock);
    } else {
        /* Everything else is "stop forcing the speaker and steer the input".
         * iOS derives the output from the selected input for headset-style
         * accessories, so setPreferredInput is the lever for WIRED/BLUETOOTH,
         * and clearing the override alone is the lever for EARPIECE. */
        if (![sess overrideOutputAudioPort:AVAudioSessionPortOverrideNone
                                     error:&err]) {
            return CLEONA_VOICE_ERR_BACKEND;
        }
        pthread_mutex_lock(&p->lock);
        p->speaker_override = 0;
        pthread_mutex_unlock(&p->lock);

        AVAudioSessionPortDescription* want = nil;
        for (AVAudioSessionPortDescription* i in sess.availableInputs) {
            int32_t r = cva_in_route_for_port(i.portType);
            if (route == CLEONA_VOICE_ROUTE_EARPIECE) {
                if ([i.portType isEqualToString:AVAudioSessionPortBuiltInMic]) { want = i; break; }
            } else if (r == route) {
                want = i;
                break;
            }
        }
        if (want && ![sess setPreferredInput:want error:&err]) {
            return CLEONA_VOICE_ERR_BACKEND;
        }
    }

    /* The ABI's contract for set_route is "switched", which is an observation,
     * not a request — so the switch is confirmed against currentRoute instead
     * of assumed from a successful API call. iOS applies an override or a
     * preferred-input change asynchronously; the wait is bounded at 120 ms and
     * sits on a user-initiated control path, never on the audio hot path
     * (capture_read and playback_write are untouched by it). */
    for (int i = 0; i < 12; i++) {
        int32_t m = 0, ri = 0, ro = 0;
        cva_probe_routes(p, &m, &ri, &ro);
        if (ro == route) return CLEONA_VOICE_OK;
        struct timespec ts = { 0, 10 * 1000 * 1000 };
        nanosleep(&ts, NULL);
    }
    /* The platform accepted the call but did not take the route. Saying so is
     * the point of having an error code at all. */
    return CLEONA_VOICE_ERR_BACKEND;
}

const char* cva_platform_name(void) { return "ios"; }

#else  /* !TARGET_OS_IOS */

/* This translation unit is selected by CMake for iOS targets only. The typedef
 * keeps it a valid C translation unit if it is ever compiled elsewhere, instead
 * of tripping "ISO C requires a translation unit to contain at least one
 * declaration" under -Wpedantic. */
typedef int cleona_voice_apple_ios_not_built_here;

#endif /* TARGET_OS_IOS */

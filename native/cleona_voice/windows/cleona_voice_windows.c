/* cleona_voice_windows.c — WASAPI backend for cleona_voice.h.
 *
 * Work package: docs/SPEC_VOICE_VIDEO_REWORK.md V1.4 (Windows-Voice-Backend).
 * Architecture:  Cleona_Chat_Architecture_v3_0.md §10.4 (normative), §15.2
 *                ("Audio: WASAPI via cleona_voice (Communications category,
 *                endpoint effects)").
 *
 * ---------------------------------------------------------------------------
 * DESIGN
 * ---------------------------------------------------------------------------
 * WASAPI has no single bidirectional stream object (unlike ASIO). "One OS
 * duplex session" (I2) is therefore two IAudioClient objects — one eCapture,
 * one eRender — both tagged AudioCategory_Communications and bound to the
 * eCommunications role. This is the same construction every WASAPI-based VoIP
 * client uses (Teams, Skype, Lync): tagging both directions Communications is
 * what makes Windows treat them as one voice session for AEC-reference
 * purposes, not a single combined handle. `report.duplex` is 1 whenever both
 * clients are open and started, which is the only way I2 can be expressed on
 * this platform.
 *
 * Mono 16-bit PCM at the negotiated rate is requested directly from WASAPI via
 * AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM | AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY
 * (Microsoft's own doc for these flags: "a channel matrixer and a sample rate
 * converter are inserted as necessary to convert between the ... format
 * supplied to IAudioClient::Initialize and the audio engine mix format").
 * That is what turns the device's usual stereo/float mix format into exactly
 * the mono S16 frame contract this ABI requires, inside the audio engine,
 * without Cleona doing its own resampling or channel mixing (I1: no DSP of
 * our own — format conversion is not signal processing).
 *
 * I3 (never force a rate): if `rate_hint` is a valid ABI rate it is used
 * as-is (WASAPI's AUTOCONVERTPCM makes any 8k-48k mono/S16 request
 * achievable in shared mode); otherwise the render endpoint's own
 * IAudioClient::GetMixFormat() rate is read and used. Either way the
 * negotiated format is reported back truthfully, never assumed.
 *
 * I4 (frame size guaranteed here): WASAPI delivers capture data in
 * variable-sized packets tied to the engine's scheduling period (~10 ms by
 * default, not the ABI's fixed 20 ms frame). capture_read() accumulates
 * packets into an internal ring and only ever hands the caller exactly
 * `frame_samples` — the same technique the mock uses, applied to a real
 * variable-size source instead of a synthetic one.
 *
 * I5 (pacing is the output device's job): a dedicated internal render thread
 * waits on WASAPI's render event (signalled by the engine on its own
 * schedule) and only then pulls from the ring cleona_voice_playback_write()
 * fills. Nothing in the write path waits or sleeps.
 *
 * I6 (mute keeps streams open): mic mute zeroes samples as they are copied
 * out of the capture ring, at the same cadence as before; the underlying
 * WASAPI capture stream is never stopped. Output mute renders silence from
 * the render thread while continuing to drain (and thus keep moving) the
 * internal playback ring, so an unmute does not replay a backlog.
 *
 * I7 (route policy lives in Dart): this backend only has to make the switch
 * executable and its failure visible (cleona_voice.h). ROUTE_EARPIECE is
 * never in routes_available_mask on Windows (no earpiece exists), so
 * set_route(EARPIECE) always returns CLEONA_VOICE_ERR_ROUTE_UNAVAILABLE, the
 * defined code SPEC §4 asks for.
 *
 * I11 (verification report, never guessed): AEC/NS/AGC state is read back via
 * IAudioEffectsManager::GetAudioEffects() (Windows Build 22000+; on an older
 * OS, or if the driver's endpoint does not expose the interface at all, the
 * states are honestly reported as CLEONA_VOICE_FX_UNKNOWN — never upgraded to
 * ENABLED because a category was requested). Whether an ENABLED effect
 * originates from the driver's own APO (CLEONA_VOICE_CHAIN_WIN_ENDPOINT) or
 * from Windows' own fallback "Voice Capture DSP"
 * (CLEONA_VOICE_CHAIN_WIN_VOICE_DSP) is, by Microsoft's own documentation,
 * NOT observable through IAudioEffectsManager or any category/mode query —
 * "Applications have no visibility into how many modes are present... They
 * cannot find out what mode is used for each of their streams" (Microsoft
 * Learn, "Audio Signal Processing Modes"). The only documented, evidence-based
 * signal this backend found is the capture endpoint's KS topology: if the
 * driver exposes a KSNODETYPE_ACOUSTIC_ECHO_CANCEL / KSNODETYPE_AGC /
 * KSNODETYPE_NOISE_SUPPRESS node in its own filter graph (IDeviceTopology),
 * that is real evidence of a driver-native implementation and the report says
 * WIN_ENDPOINT; absent that evidence, the documented fallback (SPEC §7 "V1.4")
 * applies and the report says WIN_VOICE_DSP. This is a best-effort, disclosed
 * heuristic, not a certainty Windows itself does not expose — see
 * wv_detect_chain_origin() below and the acceptance report for this package.
 * ---------------------------------------------------------------------------
 */

#define INITGUID
#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#define _CRT_SECURE_NO_WARNINGS

#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <audiosessiontypes.h>
#include <devicetopology.h>
#include <functiondiscoverykeys_devpkey.h>
#include <ksmedia.h>
#include <propidl.h>

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#include "../cleona_voice.h"

/* ==========================================================================
 * GUID storage
 * ==========================================================================
 * `#define INITGUID` above makes guiddef.h's DEFINE_GUID macro allocate
 * storage (DECLSPEC_SELECTANY) instead of merely declaring `extern`. That
 * covers PKEY_Device_InstanceId / PKEY_AudioEndpoint_FormFactor from
 * functiondiscoverykeys_devpkey.h, which route through DEFINE_GUID directly.
 *
 * It does NOT cover the two other GUID families used below, verified on the
 * build VM (Windows Kit 10.0.26100.0) by object-level inspection
 * (`dumpbin /symbols`) after a plain compile:
 *   - The MIDL-generated interface IIDs/CLSIDs in mmdeviceapi.h/audioclient.h/
 *     devicetopology.h (e.g. `EXTERN_C const IID IID_IAudioClient2;`) are
 *     unconditional externs with no INITGUID branch in this SDK at all --
 *     confirmed by reading the header text directly, not assumed.
 *   - The KS type GUIDs in ksmedia.h (KSNODETYPE_AGC and friends) expand,
 *     for a plain-C translation unit, through ks.h's OWN `DEFINE_GUIDEX(n)`
 *     -> `EXTERN_C const CDECL GUID n` (ks.h:37) -- a macro with the same
 *     name as guiddef.h's DEFINE_GUID but a DIFFERENT, always-extern-only
 *     body that ignores INITGUID entirely. This was verified empirically: a
 *     minimal `#define INITGUID` + `#include <ksmedia.h>` translation unit
 *     still produced an UNDEF external symbol on this SDK.
 * Neither family's storage exists in any .lib under this Windows Kit's
 * `um\x64` either (checked by dumping every .lib there) -- this is a gap in
 * this particular SDK packaging for C (non-C++, non-__uuidof) consumers, not
 * a mistake in how this file uses the headers.
 *
 * The values below are transcribed byte-for-byte from the SDK headers
 * themselves (MIDL_INTERFACE(...) annotations for the interfaces, the
 * STATIC_KSNODETYPE_... and STATIC_AUDIO_EFFECT_TYPE_... macros for the
 * KS/effect GUIDs -- both grepped directly off the build VM, not recalled from
 * memory), so this is a re-statement of the SDK's own data, not an invented
 * value. Multiple `extern const GUID X;` declarations followed by one
 * defining one in the same translation unit is ordinary, legal C.
 */
DEFINE_GUID(CLSID_MMDeviceEnumerator,  0xBCDE0395, 0xE52F, 0x467C, 0x8E, 0x3D, 0xC4, 0x57, 0x92, 0x91, 0x69, 0x2E);
DEFINE_GUID(IID_IMMDeviceEnumerator,   0xA95664D2, 0x9614, 0x4F35, 0xA7, 0x46, 0xDE, 0x8D, 0xB6, 0x36, 0x17, 0xE6);
DEFINE_GUID(IID_IMMNotificationClient, 0x7991EEC9, 0x7E89, 0x4D85, 0x83, 0x90, 0x6C, 0x70, 0x3C, 0xEC, 0x60, 0xC0);
DEFINE_GUID(IID_IAudioClient2,         0x726778CD, 0xF60A, 0x4EDA, 0x82, 0xDE, 0xE4, 0x76, 0x10, 0xCD, 0x78, 0xAA);
DEFINE_GUID(IID_IAudioRenderClient,    0xF294ACFC, 0x3146, 0x4483, 0xA7, 0xBF, 0xAD, 0xDC, 0xA7, 0xC2, 0x60, 0xE2);
DEFINE_GUID(IID_IAudioCaptureClient,   0xC8ADBD64, 0xE71E, 0x48A0, 0xA4, 0xDE, 0x18, 0x5C, 0x39, 0x5C, 0xD3, 0x17);
DEFINE_GUID(IID_IAudioEffectsManager,  0x4460B3AE, 0x4B44, 0x4527, 0x86, 0x76, 0x75, 0x48, 0xA8, 0xAC, 0xD2, 0x60);
DEFINE_GUID(IID_IPart,                 0xAE2DE0E4, 0x5BCA, 0x4F2D, 0xAA, 0x46, 0x5D, 0x13, 0xF8, 0xFD, 0xB3, 0xA9);
DEFINE_GUID(IID_IDeviceTopology,       0x2A07407E, 0x6497, 0x4A18, 0x97, 0x87, 0x32, 0xF7, 0x9B, 0xD0, 0xD9, 0x8F);
DEFINE_GUID(KSCATEGORY_ACOUSTIC_ECHO_CANCEL, 0xBF963D80, 0xC559, 0x11D0, 0x8A, 0x2B, 0x00, 0xA0, 0xC9, 0x25, 0x5A, 0xC1);
DEFINE_GUID(KSNODETYPE_AGC,            0xE88C9BA0, 0xC557, 0x11D0, 0x8A, 0x2B, 0x00, 0xA0, 0xC9, 0x25, 0x5A, 0xC1);
DEFINE_GUID(KSNODETYPE_NOISE_SUPPRESS, 0xE07F903F, 0x62FD, 0x4E60, 0x8C, 0xDD, 0xDE, 0xA7, 0x23, 0x66, 0x65, 0xB5);
DEFINE_GUID(AUDIO_EFFECT_TYPE_ACOUSTIC_ECHO_CANCELLATION, 0x6f64adbe, 0x8211, 0x11e2, 0x8c, 0x70, 0x2c, 0x27, 0xd7, 0xf0, 0x01, 0xfa);
DEFINE_GUID(AUDIO_EFFECT_TYPE_NOISE_SUPPRESSION,          0x6f64adbf, 0x8211, 0x11e2, 0x8c, 0x70, 0x2c, 0x27, 0xd7, 0xf0, 0x01, 0xfa);
DEFINE_GUID(AUDIO_EFFECT_TYPE_AUTOMATIC_GAIN_CONTROL,     0x6f64adc0, 0x8211, 0x11e2, 0x8c, 0x70, 0x2c, 0x27, 0xd7, 0xf0, 0x01, 0xfa);

/* ==========================================================================
 * Small helpers shared by both directions
 * ========================================================================== */

#define WV_EVENT_QUEUE      16
#define WV_CAPTURE_ACCUM_FRAMES 8   /* headroom before capture overrun, mirrors mock/cleona_voice_mock.c */
#define WV_PLAYBACK_RING_FRAMES 8

static int rate_is_valid(int32_t rate) {
    return rate >= CLEONA_VOICE_RATE_MIN
        && rate <= CLEONA_VOICE_RATE_MAX
        && (rate % CLEONA_VOICE_FRAME_HZ) == 0;
}

static void format_from_rate(cleona_voice_format_t* f, int32_t rate) {
    f->sample_rate   = rate;
    f->channels      = CLEONA_VOICE_CHANNELS;
    f->frame_samples = rate / CLEONA_VOICE_FRAME_HZ;
    f->frame_bytes   = f->frame_samples * f->channels * 2;
}

static void fail_open(cleona_voice_format_t* out_format, int32_t err) {
    if (out_format) {
        out_format->sample_rate   = err;
        out_format->channels      = 0;
        out_format->frame_samples = 0;
        out_format->frame_bytes   = 0;
    }
}

/* COM must be initialised on every thread that touches an interface pointer
 * (open()/start()/control calls, the caller's own capture thread via
 * capture_read(), and our internal render thread). Idempotent per thread via
 * TLS; deliberately never paired with CoUninitialize() here — the thread's
 * lifetime is owned by the caller (or, for the render thread, by us and torn
 * down once at thread exit), and premature uninitialisation while another
 * call on the same thread might still be in flight is the greater risk. */
static __declspec(thread) int g_com_inited = 0;
static void wv_com_ensure(void) {
    if (g_com_inited) return;
    HRESULT hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    /* RPC_E_CHANGED_MODE: some other component (e.g. Flutter's own plugin
     * registrar) already put this thread into an STA. We cannot force MTA at
     * that point, but the thread IS COM-capable, so calls proceed — flagged
     * here rather than silently possibly-not-working. */
    if (SUCCEEDED(hr) || hr == RPC_E_CHANGED_MODE) g_com_inited = 1;
}
static void wv_com_thread_exit(void) {
    if (g_com_inited) { CoUninitialize(); g_com_inited = 0; }
}

/* ==========================================================================
 * Route classification (I7's executable half — the decision itself is Dart's)
 * ==========================================================================
 * Windows has no ROUTE_EARPIECE; routes_available_mask never sets that bit
 * (architecture §10.4, mock/cleona_voice_mock.h cleona_voice_mock_config_desktop()).
 * Classification is evidence-based, not guessed:
 *   - PKEY_Device_InstanceId starting "BTH" (BTHENUM / BTHLEDevice, the PnP
 *     enumerators Windows uses for Bluetooth-paired audio endpoints) -> BLUETOOTH.
 *   - PKEY_AudioEndpoint_FormFactor Headphones/Headset/LineLevel -> WIRED.
 *   - Everything else (Speakers, or a property read that failed) -> SPEAKER,
 *     which is also the guaranteed non-empty fallback (SPEC §4: "a desktop
 *     backend returns ERR_ROUTE_UNAVAILABLE for EARPIECE", not an empty mask).
 * ========================================================================== */
static int32_t wv_classify_endpoint(IMMDevice* dev) {
    if (!dev) return CLEONA_VOICE_ROUTE_SPEAKER;
    int32_t route = CLEONA_VOICE_ROUTE_SPEAKER;
    IPropertyStore* store = NULL;
    if (SUCCEEDED(IMMDevice_OpenPropertyStore(dev, STGM_READ, &store)) && store) {
        PROPVARIANT pv;
        PropVariantInit(&pv);
        if (SUCCEEDED(IPropertyStore_GetValue(store, &PKEY_Device_InstanceId, &pv))
            && pv.vt == VT_LPWSTR && pv.pwszVal
            && _wcsnicmp(pv.pwszVal, L"BTH", 3) == 0) {
            route = CLEONA_VOICE_ROUTE_BLUETOOTH;
        }
        PropVariantClear(&pv);

        if (route != CLEONA_VOICE_ROUTE_BLUETOOTH) {
            PropVariantInit(&pv);
            if (SUCCEEDED(IPropertyStore_GetValue(store, &PKEY_AudioEndpoint_FormFactor, &pv))
                && pv.vt == VT_UI4) {
                EndpointFormFactor ff = (EndpointFormFactor)pv.uintVal;
                if (ff == Headphones || ff == Headset || ff == LineLevel) {
                    route = CLEONA_VOICE_ROUTE_WIRED;
                }
            }
            PropVariantClear(&pv);
        }
        IPropertyStore_Release(store);
    }
    return route;
}

/* Builds the current output-route mask + the classification of the default
 * communications render endpoint. Never returns an empty mask (SPEC §6 check
 * 8 requires the active route to be present in it). */
static int32_t wv_compute_routes_mask(IMMDeviceEnumerator* en, int32_t* out_active) {
    int32_t mask = 0;
    IMMDeviceCollection* coll = NULL;
    if (SUCCEEDED(IMMDeviceEnumerator_EnumAudioEndpoints(en, eRender, DEVICE_STATE_ACTIVE, &coll)) && coll) {
        UINT n = 0;
        IMMDeviceCollection_GetCount(coll, &n);
        for (UINT i = 0; i < n; i++) {
            IMMDevice* d = NULL;
            if (SUCCEEDED(IMMDeviceCollection_Item(coll, i, &d)) && d) {
                mask |= CLEONA_VOICE_ROUTE_BIT(wv_classify_endpoint(d));
                IMMDevice_Release(d);
            }
        }
        IMMDeviceCollection_Release(coll);
    }
    if (mask == 0) mask = CLEONA_VOICE_ROUTE_BIT(CLEONA_VOICE_ROUTE_SPEAKER);

    if (out_active) {
        *out_active = CLEONA_VOICE_ROUTE_SPEAKER;
        IMMDevice* def = NULL;
        if (SUCCEEDED(IMMDeviceEnumerator_GetDefaultAudioEndpoint(en, eRender, eCommunications, &def)) && def) {
            *out_active = wv_classify_endpoint(def);
            IMMDevice_Release(def);
        }
    }
    return mask;
}

/* First active render endpoint classifying as `route`, or NULL. Caller owns
 * the returned IMMDevice (Release() it). */
static IMMDevice* wv_find_render_for_route(IMMDeviceEnumerator* en, int32_t route) {
    IMMDevice* result = NULL;
    IMMDeviceCollection* coll = NULL;
    if (SUCCEEDED(IMMDeviceEnumerator_EnumAudioEndpoints(en, eRender, DEVICE_STATE_ACTIVE, &coll)) && coll) {
        UINT n = 0;
        IMMDeviceCollection_GetCount(coll, &n);
        for (UINT i = 0; i < n && !result; i++) {
            IMMDevice* d = NULL;
            if (SUCCEEDED(IMMDeviceCollection_Item(coll, i, &d)) && d) {
                if (wv_classify_endpoint(d) == route) {
                    result = d;
                } else {
                    IMMDevice_Release(d);
                }
            }
        }
        IMMDeviceCollection_Release(coll);
    }
    return result;
}

/* ==========================================================================
 * chain_origin (I11) — see the file doc's long comment. Bounded, cycle-safe
 * KS topology walk from the capture endpoint's single connector, looking for
 * a driver-native AEC/NS/AGC node. No node found within the bound => the
 * documented Voice Capture DSP fallback (SPEC §7 "V1.4").
 * ========================================================================== */
#define WV_TOPO_MAX_VISITED 64
#define WV_TOPO_MAX_DEPTH   12

static int wv_subtype_is_voice_dsp_node(const GUID* g) {
    return IsEqualGUID(g, &KSNODETYPE_ACOUSTIC_ECHO_CANCEL)
        || IsEqualGUID(g, &KSNODETYPE_AGC)
        || IsEqualGUID(g, &KSNODETYPE_NOISE_SUPPRESS);
}

/* Depth- and visit-bounded so a malformed or cyclic topology (neither
 * expected nor ruled out by the API contract) cannot hang open(). Visited
 * parts are tracked by IPart pointer identity within this single walk. */
static int wv_topology_walk(IPart* part, IPart** visited, int* visited_n, int depth) {
    if (!part || depth > WV_TOPO_MAX_DEPTH || *visited_n >= WV_TOPO_MAX_VISITED) return 0;
    for (int i = 0; i < *visited_n; i++) {
        if (visited[i] == part) return 0; /* already walked */
    }
    if (*visited_n < WV_TOPO_MAX_VISITED) visited[(*visited_n)++] = part;

    PartType pt;
    if (SUCCEEDED(IPart_GetPartType(part, &pt)) && pt == Subunit) {
        GUID sub;
        if (SUCCEEDED(IPart_GetSubType(part, &sub)) && wv_subtype_is_voice_dsp_node(&sub)) {
            return 1;
        }
    }

    int found = 0;
    IPartsList* incoming = NULL;
    if (SUCCEEDED(IPart_EnumPartsIncoming(part, &incoming)) && incoming) {
        UINT n = 0;
        IPartsList_GetCount(incoming, &n);
        for (UINT i = 0; i < n && !found; i++) {
            IPart* next = NULL;
            if (SUCCEEDED(IPartsList_GetPart(incoming, i, &next)) && next) {
                found = wv_topology_walk(next, visited, visited_n, depth + 1);
                IPart_Release(next);
            }
        }
        IPartsList_Release(incoming);
    }
    return found;
}

/* Returns CLEONA_VOICE_CHAIN_WIN_ENDPOINT if topology evidence of a
 * driver-native AEC/NS/AGC node was found on `capture_device`, otherwise the
 * documented fallback CLEONA_VOICE_CHAIN_WIN_VOICE_DSP. Never fails outward —
 * an inability to obtain the topology (common on virtual/basic drivers, e.g.
 * this package's own test VM) is itself evidence of "no driver-native
 * effects visible", which correctly resolves to the fallback. */
static int32_t wv_detect_chain_origin(IMMDevice* capture_device) {
    int32_t result = CLEONA_VOICE_CHAIN_WIN_VOICE_DSP;
    if (!capture_device) return result;

    IDeviceTopology* topo = NULL;
    if (FAILED(IMMDevice_Activate(capture_device, &IID_IDeviceTopology, CLSCTX_ALL, NULL, (void**)&topo)) || !topo) {
        return result;
    }

    UINT connCount = 0;
    if (SUCCEEDED(IDeviceTopology_GetConnectorCount(topo, &connCount)) && connCount > 0) {
        IConnector* conn = NULL;
        if (SUCCEEDED(IDeviceTopology_GetConnector(topo, 0, &conn)) && conn) {
            IPart* part = NULL;
            if (SUCCEEDED(IConnector_QueryInterface(conn, &IID_IPart, (void**)&part)) && part) {
                IPart* visited[WV_TOPO_MAX_VISITED];
                int visited_n = 0;
                if (wv_topology_walk(part, visited, &visited_n, 0)) {
                    result = CLEONA_VOICE_CHAIN_WIN_ENDPOINT;
                }
                IPart_Release(part);
            }
            IConnector_Release(conn);
        }
    }
    IDeviceTopology_Release(topo);
    return result;
}

/* ==========================================================================
 * Effects read-back (I11) — IAudioEffectsManager, Windows Build 22000+.
 * Absence of the interface (older Windows, or a driver/engine combination
 * that does not implement it) is reported as FX_UNKNOWN on all three effects,
 * never guessed from the category having been requested.
 * ========================================================================== */
typedef struct {
    int32_t aec, ns, agc; /* CLEONA_VOICE_FX_* */
} wv_fx_states_t;

static int32_t wv_fx_from_effect_list(AUDIO_EFFECT* effects, UINT32 n, const GUID* type) {
    for (UINT32 i = 0; i < n; i++) {
        if (IsEqualGUID(&effects[i].id, type)) {
            return effects[i].state == AUDIO_EFFECT_STATE_ON
                 ? CLEONA_VOICE_FX_ENABLED : CLEONA_VOICE_FX_AVAILABLE_OFF;
        }
    }
    return CLEONA_VOICE_FX_UNAVAILABLE; /* not in the list -> chain does not offer it */
}

static wv_fx_states_t wv_read_effects(IAudioClient2* capture_client) {
    wv_fx_states_t st;
    st.aec = st.ns = st.agc = CLEONA_VOICE_FX_UNKNOWN;
    if (!capture_client) return st;

    IAudioEffectsManager* mgr = NULL;
    if (FAILED(IAudioClient2_GetService(capture_client, &IID_IAudioEffectsManager, (void**)&mgr)) || !mgr) {
        return st; /* interface unavailable on this OS/driver -> honestly UNKNOWN */
    }

    AUDIO_EFFECT* effects = NULL;
    UINT32 n = 0;
    if (SUCCEEDED(IAudioEffectsManager_GetAudioEffects(mgr, &effects, &n))) {
        st.aec = wv_fx_from_effect_list(effects, n, &AUDIO_EFFECT_TYPE_ACOUSTIC_ECHO_CANCELLATION);
        st.ns  = wv_fx_from_effect_list(effects, n, &AUDIO_EFFECT_TYPE_NOISE_SUPPRESSION);
        st.agc = wv_fx_from_effect_list(effects, n, &AUDIO_EFFECT_TYPE_AUTOMATIC_GAIN_CONTROL);
        if (effects) CoTaskMemFree(effects);
    }
    /* else: GetAudioEffects itself failed post-activation -> leave UNKNOWN,
     * do not infer anything from the failure mode. */
    IAudioEffectsManager_Release(mgr);
    return st;
}

/* ==========================================================================
 * IMMNotificationClient — minimal C-style COM object so route changes surface
 * as CLEONA_VOICE_EV_ROUTES_CHANGED (cleona_voice.h) instead of requiring the
 * caller to poll. Ref-counted independently of the session so the OS can hold
 * a reference across Unregister races during close().
 * ========================================================================== */
/* cleona_voice_session_t is already typedef'd by cleona_voice.h (the ABI
 * forward-declares it as an opaque type); struct cleona_voice_session below
 * gives the OPAQUE tag its real definition for this translation unit only. */

typedef struct {
    IMMNotificationClientVtbl* lpVtbl;
    LONG refcount;
    cleona_voice_session_t* owner; /* cleared by the session before it is torn down */
    CRITICAL_SECTION* owner_lock; /* same lock as the session, for owner access */
} wv_notify_t;

static void wv_push_event_locked(cleona_voice_session_t* s, int32_t ev, int32_t arg);
static void wv_recompute_routes_locked(cleona_voice_session_t* s);

static HRESULT STDMETHODCALLTYPE wv_notify_QI(IMMNotificationClient* self, REFIID riid, void** ppv) {
    if (!ppv) return E_POINTER;
    if (IsEqualGUID(riid, &IID_IUnknown) || IsEqualGUID(riid, &IID_IMMNotificationClient)) {
        *ppv = self;
        IUnknown_AddRef((IUnknown*)self);
        return S_OK;
    }
    *ppv = NULL;
    return E_NOINTERFACE;
}
static ULONG STDMETHODCALLTYPE wv_notify_AddRef(IMMNotificationClient* self) {
    return (ULONG)InterlockedIncrement(&((wv_notify_t*)self)->refcount);
}
static ULONG STDMETHODCALLTYPE wv_notify_Release(IMMNotificationClient* self) {
    LONG r = InterlockedDecrement(&((wv_notify_t*)self)->refcount);
    if (r == 0) free(self);
    return (ULONG)r;
}
static HRESULT STDMETHODCALLTYPE wv_notify_OnDeviceStateChanged(IMMNotificationClient* self, LPCWSTR id, DWORD state) {
    (void)id; (void)state;
    wv_notify_t* n = (wv_notify_t*)self;
    if (n->owner_lock) {
        EnterCriticalSection(n->owner_lock);
        if (n->owner) wv_recompute_routes_locked(n->owner);
        LeaveCriticalSection(n->owner_lock);
    }
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE wv_notify_OnDeviceAdded(IMMNotificationClient* self, LPCWSTR id) {
    return wv_notify_OnDeviceStateChanged(self, id, 0);
}
static HRESULT STDMETHODCALLTYPE wv_notify_OnDeviceRemoved(IMMNotificationClient* self, LPCWSTR id) {
    return wv_notify_OnDeviceStateChanged(self, id, 0);
}
static HRESULT STDMETHODCALLTYPE wv_notify_OnDefaultDeviceChanged(IMMNotificationClient* self, EDataFlow flow, ERole role, LPCWSTR id) {
    (void)flow; (void)role; (void)id;
    return wv_notify_OnDeviceStateChanged(self, id, 0);
}
static HRESULT STDMETHODCALLTYPE wv_notify_OnPropertyValueChanged(IMMNotificationClient* self, LPCWSTR id, const PROPERTYKEY key) {
    (void)key;
    return wv_notify_OnDeviceStateChanged(self, id, 0);
}

static IMMNotificationClientVtbl g_notify_vtbl = {
    wv_notify_QI, wv_notify_AddRef, wv_notify_Release,
    wv_notify_OnDeviceStateChanged, wv_notify_OnDeviceAdded, wv_notify_OnDeviceRemoved,
    wv_notify_OnDefaultDeviceChanged, wv_notify_OnPropertyValueChanged,
};

/* ==========================================================================
 * Session
 * ========================================================================== */
struct cleona_voice_session {
    CRITICAL_SECTION lock;
    cleona_voice_format_t fmt;

    IMMDeviceEnumerator* enumerator;
    wv_notify_t* notify;
    int notify_registered;

    /* capture side */
    IMMDevice*            cap_device;
    IAudioClient2*        cap_client;
    IAudioCaptureClient*  cap_capture;
    HANDLE                cap_event;
    int32_t               chain_origin; /* resolved once at open(), I11 */

    /* render side (rebuildable by set_route without touching capture) */
    IMMDevice*            rnd_device;
    IAudioClient2*        rnd_client;
    IAudioRenderClient*   rnd_render;
    HANDLE                rnd_event;
    UINT32                rnd_buffer_frames;
    HANDLE                rnd_thread;
    HANDLE                rnd_stop_event;

    int32_t running;
    int32_t mic_muted;
    int32_t output_muted;

    int32_t routes_mask;
    int32_t route_in, route_out;

    int64_t underruns, overruns;

    /* capture accumulation ring (I4) */
    int16_t* cap_accum;
    int32_t  cap_accum_len;
    int32_t  cap_accum_cap;

    /* playback ring (I5 — filled by playback_write, drained by the render thread) */
    int16_t* pb_ring;
    int32_t  pb_ring_cap;   /* capacity in samples */
    int32_t  pb_ring_head;  /* next sample to read */
    int32_t  pb_ring_len;   /* samples currently queued */

    int32_t ev_type[WV_EVENT_QUEUE];
    int32_t ev_arg[WV_EVENT_QUEUE];
    int32_t ev_head, ev_count;
};

static void wv_push_event_locked(cleona_voice_session_t* s, int32_t ev, int32_t arg) {
    if (s->ev_count == WV_EVENT_QUEUE) {
        s->ev_head = (s->ev_head + 1) % WV_EVENT_QUEUE;
        s->ev_count--;
    }
    int32_t tail = (s->ev_head + s->ev_count) % WV_EVENT_QUEUE;
    s->ev_type[tail] = ev;
    s->ev_arg[tail] = arg;
    s->ev_count++;
}

/* Recomputes the route mask/active-out and queues EV_ROUTES_CHANGED if it
 * actually changed. Called both from the notification client and, harmlessly,
 * from get_routes()'s own callers via poll. Caller holds s->lock. */
static void wv_recompute_routes_locked(cleona_voice_session_t* s) {
    if (!s->enumerator) return;
    int32_t active = s->route_out;
    int32_t mask = wv_compute_routes_mask(s->enumerator, &active);
    if (mask != s->routes_mask) {
        s->routes_mask = mask;
        if (!(mask & CLEONA_VOICE_ROUTE_BIT(s->route_out))) {
            /* The active route just vanished. This layer does not pick a
             * successor -- that is I7 / RoutePolicy's job (V1.5), exactly as
             * mock/cleona_voice_mock.c's cleona_voice_mock_set_routes() does
             * it for the same reason. */
            s->route_out = CLEONA_VOICE_ROUTE_UNKNOWN;
        }
        wv_push_event_locked(s, CLEONA_VOICE_EV_ROUTES_CHANGED, mask);
    }
}

/* ==========================================================================
 * Format negotiation
 * ========================================================================== */
static int32_t wv_pick_rate(int32_t rate_hint, IMMDevice* probe_render) {
    if (rate_is_valid(rate_hint)) return rate_hint;

    int32_t rate = CLEONA_VOICE_RATE_MAX; /* last-resort only if the probe itself fails */
    if (probe_render) {
        IAudioClient2* probe = NULL;
        if (SUCCEEDED(IMMDevice_Activate(probe_render, &IID_IAudioClient2, CLSCTX_ALL, NULL, (void**)&probe)) && probe) {
            WAVEFORMATEX* mix = NULL;
            if (SUCCEEDED(IAudioClient2_GetMixFormat(probe, &mix)) && mix) {
                if ((int32_t)mix->nSamplesPerSec >= CLEONA_VOICE_RATE_MIN) {
                    rate = (int32_t)mix->nSamplesPerSec;
                }
                CoTaskMemFree(mix);
            }
            IAudioClient2_Release(probe);
        }
    }
    if (rate > CLEONA_VOICE_RATE_MAX) rate = CLEONA_VOICE_RATE_MAX;
    if (rate < CLEONA_VOICE_RATE_MIN) rate = CLEONA_VOICE_RATE_MIN;
    if (rate % CLEONA_VOICE_FRAME_HZ != 0) rate -= (rate % CLEONA_VOICE_FRAME_HZ);
    if (rate < CLEONA_VOICE_RATE_MIN) rate = CLEONA_VOICE_RATE_MIN;
    return rate;
}

static void wv_build_wfx(WAVEFORMATEX* wfx, int32_t rate) {
    memset(wfx, 0, sizeof(*wfx));
    wfx->wFormatTag      = WAVE_FORMAT_PCM;
    wfx->nChannels       = 1;
    wfx->nSamplesPerSec  = (DWORD)rate;
    wfx->wBitsPerSample  = 16;
    wfx->nBlockAlign     = (WORD)(wfx->nChannels * wfx->wBitsPerSample / 8);
    wfx->nAvgBytesPerSec = wfx->nSamplesPerSec * wfx->nBlockAlign;
    wfx->cbSize          = 0;
}

/* Activates `device`, tags it AudioCategory_Communications (SPEC §7 "V1.4"
 * requirement), and Initializes it in shared/event-driven mode at `rate`
 * mono/S16 via AUTOCONVERTPCM. On AUDCLNT_E_UNSUPPORTED_FORMAT, retries once
 * with the device's own mix-format rate rather than failing outright — still
 * I3-honest, since that is the platform's own reported rate, not an assumed
 * one. Returns a started-but-not-yet-Start()ed client + its event handle. */
static HRESULT wv_activate_and_init(IMMDevice* device, int32_t* io_rate,
                                     IAudioClient2** out_client, HANDLE* out_event) {
    IAudioClient2* client = NULL;
    HRESULT hr = IMMDevice_Activate(device, &IID_IAudioClient2, CLSCTX_ALL, NULL, (void**)&client);
    if (FAILED(hr) || !client) return FAILED(hr) ? hr : E_FAIL;

    AudioClientProperties props;
    memset(&props, 0, sizeof(props));
    props.cbSize     = sizeof(props);
    props.bIsOffload = FALSE;
    props.eCategory  = AudioCategory_Communications; /* SPEC §7 V1.4, mandatory */
    IAudioClient2_SetClientProperties(client, &props); /* best-effort; category is a hint the engine may decline */

    WAVEFORMATEX wfx;
    wv_build_wfx(&wfx, *io_rate);
    DWORD flags = AUDCLNT_STREAMFLAGS_EVENTCALLBACK
                | AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM
                | AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY;
    hr = IAudioClient2_Initialize(client, AUDCLNT_SHAREMODE_SHARED, flags, 0, 0, &wfx, NULL);

    if (hr == AUDCLNT_E_UNSUPPORTED_FORMAT) {
        WAVEFORMATEX* mix = NULL;
        if (SUCCEEDED(IAudioClient2_GetMixFormat(client, &mix)) && mix
            && (int32_t)mix->nSamplesPerSec >= CLEONA_VOICE_RATE_MIN) {
            int32_t retry_rate = (int32_t)mix->nSamplesPerSec;
            if (retry_rate > CLEONA_VOICE_RATE_MAX) retry_rate = CLEONA_VOICE_RATE_MAX;
            wv_build_wfx(&wfx, retry_rate);
            hr = IAudioClient2_Initialize(client, AUDCLNT_SHAREMODE_SHARED, flags, 0, 0, &wfx, NULL);
            if (SUCCEEDED(hr)) *io_rate = retry_rate;
        }
        if (mix) CoTaskMemFree(mix);
    }
    if (FAILED(hr)) {
        IAudioClient2_Release(client);
        return hr;
    }

    HANDLE ev = CreateEventW(NULL, FALSE, FALSE, NULL);
    if (!ev) {
        IAudioClient2_Release(client);
        return E_OUTOFMEMORY;
    }
    hr = IAudioClient2_SetEventHandle(client, ev);
    if (FAILED(hr)) {
        CloseHandle(ev);
        IAudioClient2_Release(client);
        return hr;
    }

    *out_client = client;
    *out_event = ev;
    return S_OK;
}

/* ==========================================================================
 * Render thread — the ONLY place that touches the render device (I5).
 * ========================================================================== */
static DWORD WINAPI wv_render_thread_proc(LPVOID arg) {
    cleona_voice_session_t* s = (cleona_voice_session_t*)arg;
    wv_com_ensure();

    HANDLE waits[2];
    for (;;) {
        EnterCriticalSection(&s->lock);
        HANDLE render_event = s->rnd_event;
        HANDLE stop_event = s->rnd_stop_event;
        LeaveCriticalSection(&s->lock);
        if (!render_event || !stop_event) break;

        waits[0] = stop_event;
        waits[1] = render_event;
        DWORD w = WaitForMultipleObjects(2, waits, FALSE, INFINITE);
        if (w == WAIT_OBJECT_0) break; /* stop requested */
        if (w != WAIT_OBJECT_0 + 1) continue;

        EnterCriticalSection(&s->lock);
        IAudioClient2* client = s->rnd_client;
        IAudioRenderClient* render = s->rnd_render;
        UINT32 bufferFrames = s->rnd_buffer_frames;
        int muted = s->output_muted;
        if (!client || !render) { LeaveCriticalSection(&s->lock); continue; }

        UINT32 padding = 0;
        if (FAILED(IAudioClient2_GetCurrentPadding(client, &padding))) {
            LeaveCriticalSection(&s->lock);
            continue;
        }
        UINT32 avail = (bufferFrames > padding) ? (bufferFrames - padding) : 0;
        if (avail == 0) { LeaveCriticalSection(&s->lock); continue; }

        BYTE* data = NULL;
        if (FAILED(IAudioRenderClient_GetBuffer(render, avail, &data)) || !data) {
            LeaveCriticalSection(&s->lock);
            continue;
        }

        int16_t* out = (int16_t*)data;
        UINT32 fromRing = (UINT32)((s->pb_ring_len < (int32_t)avail) ? s->pb_ring_len : (int32_t)avail);
        for (UINT32 i = 0; i < fromRing; i++) {
            out[i] = muted ? 0 : s->pb_ring[s->pb_ring_head];
            s->pb_ring_head = (s->pb_ring_head + 1) % s->pb_ring_cap;
        }
        s->pb_ring_len -= (int32_t)fromRing;
        if (fromRing < avail) {
            /* Ring underflow: nothing queued to render. Real gap in supply,
             * not a mute -- count it (I6 keeps this path silent-but-open,
             * distinct from an actual underrun). */
            memset(out + fromRing, 0, (size_t)(avail - fromRing) * sizeof(int16_t));
            s->underruns++;
        }
        LeaveCriticalSection(&s->lock);

        IAudioRenderClient_ReleaseBuffer(render, avail, 0);
    }

    wv_com_thread_exit();
    return 0;
}

/* ==========================================================================
 * Lifecycle
 * ========================================================================== */
CLEONA_VOICE_API cleona_voice_session_t* cleona_voice_open(
    int32_t rate_hint, cleona_voice_format_t* out_format) {

    if (!out_format) return NULL;
    wv_com_ensure();

    IMMDeviceEnumerator* en = NULL;
    HRESULT hr = CoCreateInstance(&CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL,
                                   &IID_IMMDeviceEnumerator, (void**)&en);
    if (FAILED(hr) || !en) {
        fail_open(out_format, CLEONA_VOICE_ERR_BACKEND);
        return NULL;
    }

    IMMDevice* cap_dev = NULL;
    IMMDevice* rnd_dev = NULL;
    hr = IMMDeviceEnumerator_GetDefaultAudioEndpoint(en, eCapture, eCommunications, &cap_dev);
    if (FAILED(hr) || !cap_dev) {
        IMMDeviceEnumerator_Release(en);
        fail_open(out_format, hr == AUDCLNT_E_DEVICE_INVALIDATED ? CLEONA_VOICE_ERR_NO_DEVICE
                                                                   : CLEONA_VOICE_ERR_NO_DEVICE);
        return NULL;
    }
    hr = IMMDeviceEnumerator_GetDefaultAudioEndpoint(en, eRender, eCommunications, &rnd_dev);
    if (FAILED(hr) || !rnd_dev) {
        IMMDevice_Release(cap_dev);
        IMMDeviceEnumerator_Release(en);
        fail_open(out_format, CLEONA_VOICE_ERR_NO_DEVICE);
        return NULL;
    }

    int32_t rate = wv_pick_rate(rate_hint, rnd_dev);

    IAudioClient2* cap_client = NULL; HANDLE cap_event = NULL;
    int32_t cap_rate = rate;
    hr = wv_activate_and_init(cap_dev, &cap_rate, &cap_client, &cap_event);
    if (FAILED(hr)) {
        IMMDevice_Release(rnd_dev); IMMDevice_Release(cap_dev); IMMDeviceEnumerator_Release(en);
        fail_open(out_format, hr == E_ACCESSDENIED ? CLEONA_VOICE_ERR_PERMISSION : CLEONA_VOICE_ERR_BACKEND);
        return NULL;
    }

    IAudioClient2* rnd_client = NULL; HANDLE rnd_event = NULL;
    int32_t rnd_rate = cap_rate; /* both directions must share one format (ABI is one format for the session) */
    hr = wv_activate_and_init(rnd_dev, &rnd_rate, &rnd_client, &rnd_event);
    if (FAILED(hr) || rnd_rate != cap_rate) {
        if (rnd_client) IAudioClient2_Release(rnd_client);
        if (rnd_event) CloseHandle(rnd_event);
        CloseHandle(cap_event);
        IAudioClient2_Release(cap_client);
        IMMDevice_Release(rnd_dev); IMMDevice_Release(cap_dev); IMMDeviceEnumerator_Release(en);
        fail_open(out_format, CLEONA_VOICE_ERR_BACKEND);
        return NULL;
    }

    IAudioCaptureClient* cap_capture = NULL;
    hr = IAudioClient2_GetService(cap_client, &IID_IAudioCaptureClient, (void**)&cap_capture);
    IAudioRenderClient* rnd_render = NULL;
    if (SUCCEEDED(hr)) {
        hr = IAudioClient2_GetService(rnd_client, &IID_IAudioRenderClient, (void**)&rnd_render);
    }
    if (FAILED(hr) || !cap_capture || !rnd_render) {
        if (rnd_render) IAudioRenderClient_Release(rnd_render);
        if (cap_capture) IAudioCaptureClient_Release(cap_capture);
        CloseHandle(rnd_event); IAudioClient2_Release(rnd_client);
        CloseHandle(cap_event); IAudioClient2_Release(cap_client);
        IMMDevice_Release(rnd_dev); IMMDevice_Release(cap_dev); IMMDeviceEnumerator_Release(en);
        fail_open(out_format, CLEONA_VOICE_ERR_BACKEND);
        return NULL;
    }

    UINT32 rnd_buffer_frames = 0;
    IAudioClient2_GetBufferSize(rnd_client, &rnd_buffer_frames);

    cleona_voice_session_t* s = (cleona_voice_session_t*)calloc(1, sizeof(cleona_voice_session_t));
    if (!s) {
        IAudioRenderClient_Release(rnd_render); IAudioCaptureClient_Release(cap_capture);
        CloseHandle(rnd_event); IAudioClient2_Release(rnd_client);
        CloseHandle(cap_event); IAudioClient2_Release(cap_client);
        IMMDevice_Release(rnd_dev); IMMDevice_Release(cap_dev); IMMDeviceEnumerator_Release(en);
        fail_open(out_format, CLEONA_VOICE_ERR_BACKEND);
        return NULL;
    }

    InitializeCriticalSection(&s->lock);
    format_from_rate(&s->fmt, cap_rate);

    s->enumerator = en;
    s->cap_device = cap_dev; s->cap_client = cap_client; s->cap_capture = cap_capture; s->cap_event = cap_event;
    s->rnd_device = rnd_dev; s->rnd_client = rnd_client; s->rnd_render = rnd_render; s->rnd_event = rnd_event;
    s->rnd_buffer_frames = rnd_buffer_frames;

    s->chain_origin = wv_detect_chain_origin(cap_dev);

    s->cap_accum_cap = s->fmt.frame_samples * WV_CAPTURE_ACCUM_FRAMES;
    s->cap_accum = (int16_t*)calloc((size_t)s->cap_accum_cap, sizeof(int16_t));
    s->pb_ring_cap = s->fmt.frame_samples * WV_PLAYBACK_RING_FRAMES;
    s->pb_ring = (int16_t*)calloc((size_t)s->pb_ring_cap, sizeof(int16_t));
    if (!s->cap_accum || !s->pb_ring) {
        free(s->cap_accum); free(s->pb_ring);
        DeleteCriticalSection(&s->lock);
        IAudioRenderClient_Release(rnd_render); IAudioCaptureClient_Release(cap_capture);
        CloseHandle(rnd_event); IAudioClient2_Release(rnd_client);
        CloseHandle(cap_event); IAudioClient2_Release(cap_client);
        IMMDevice_Release(rnd_dev); IMMDevice_Release(cap_dev); IMMDeviceEnumerator_Release(en);
        free(s);
        fail_open(out_format, CLEONA_VOICE_ERR_BACKEND);
        return NULL;
    }

    s->routes_mask = wv_compute_routes_mask(en, &s->route_out);
    s->route_in = s->route_out; /* one duplex pair, one physical device set — mirrors mock start() */

    wv_notify_t* nc = (wv_notify_t*)calloc(1, sizeof(wv_notify_t));
    if (nc) {
        nc->lpVtbl = &g_notify_vtbl;
        nc->refcount = 1;
        nc->owner = s;
        nc->owner_lock = &s->lock;
        if (SUCCEEDED(IMMDeviceEnumerator_RegisterEndpointNotificationCallback(en, (IMMNotificationClient*)nc))) {
            s->notify = nc;
            s->notify_registered = 1;
        } else {
            free(nc);
        }
    }

    *out_format = s->fmt;
    return s;
}

CLEONA_VOICE_API int32_t cleona_voice_start(cleona_voice_session_t* s) {
    if (!s) return CLEONA_VOICE_ERR_CLOSED;
    EnterCriticalSection(&s->lock);
    if (s->running) {
        LeaveCriticalSection(&s->lock);
        return CLEONA_VOICE_ERR_ALREADY_STARTED;
    }

    s->rnd_stop_event = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (!s->rnd_stop_event) {
        LeaveCriticalSection(&s->lock);
        return CLEONA_VOICE_ERR_BACKEND;
    }

    HRESULT hr = IAudioClient2_Start(s->rnd_client);
    if (SUCCEEDED(hr)) hr = IAudioClient2_Start(s->cap_client);
    if (FAILED(hr)) {
        IAudioClient2_Stop(s->rnd_client);
        IAudioClient2_Stop(s->cap_client);
        CloseHandle(s->rnd_stop_event);
        s->rnd_stop_event = NULL;
        LeaveCriticalSection(&s->lock);
        return CLEONA_VOICE_ERR_BACKEND;
    }

    s->running = 1;
    s->cap_accum_len = 0;
    s->pb_ring_head = s->pb_ring_len = 0;
    LeaveCriticalSection(&s->lock);

    s->rnd_thread = CreateThread(NULL, 0, wv_render_thread_proc, s, 0, NULL);
    return CLEONA_VOICE_OK;
}

CLEONA_VOICE_API void cleona_voice_stop(cleona_voice_session_t* s) {
    if (!s) return;
    EnterCriticalSection(&s->lock);
    if (!s->running) { LeaveCriticalSection(&s->lock); return; }
    s->running = 0;
    HANDLE stop_event = s->rnd_stop_event;
    LeaveCriticalSection(&s->lock);

    if (stop_event) SetEvent(stop_event);
    if (s->rnd_thread) {
        WaitForSingleObject(s->rnd_thread, 2000);
        CloseHandle(s->rnd_thread);
        s->rnd_thread = NULL;
    }

    EnterCriticalSection(&s->lock);
    IAudioClient2_Stop(s->cap_client);
    IAudioClient2_Stop(s->rnd_client);
    if (s->rnd_stop_event) { CloseHandle(s->rnd_stop_event); s->rnd_stop_event = NULL; }
    s->cap_accum_len = 0;
    s->pb_ring_head = s->pb_ring_len = 0;
    LeaveCriticalSection(&s->lock);
}

CLEONA_VOICE_API void cleona_voice_close(cleona_voice_session_t* s) {
    if (!s) return;
    cleona_voice_stop(s);

    if (s->notify_registered && s->enumerator && s->notify) {
        IMMDeviceEnumerator_UnregisterEndpointNotificationCallback(s->enumerator, (IMMNotificationClient*)s->notify);
        EnterCriticalSection(&s->lock);
        s->notify->owner = NULL; /* no more callbacks may touch this session */
        LeaveCriticalSection(&s->lock);
        IMMNotificationClient_Release((IMMNotificationClient*)s->notify);
    }

    if (s->rnd_render) IAudioRenderClient_Release(s->rnd_render);
    if (s->cap_capture) IAudioCaptureClient_Release(s->cap_capture);
    if (s->rnd_event) CloseHandle(s->rnd_event);
    if (s->rnd_client) IAudioClient2_Release(s->rnd_client);
    if (s->cap_event) CloseHandle(s->cap_event);
    if (s->cap_client) IAudioClient2_Release(s->cap_client);
    if (s->rnd_device) IMMDevice_Release(s->rnd_device);
    if (s->cap_device) IMMDevice_Release(s->cap_device);
    if (s->enumerator) IMMDeviceEnumerator_Release(s->enumerator);

    free(s->cap_accum);
    free(s->pb_ring);
    DeleteCriticalSection(&s->lock);
    free(s);
}

/* ==========================================================================
 * Data path
 * ========================================================================== */
CLEONA_VOICE_API int32_t cleona_voice_capture_read(cleona_voice_session_t* s,
                                                   int16_t* out, int32_t timeout_ms) {
    if (!s || !out) return CLEONA_VOICE_CAPTURE_CLOSED;
    if (timeout_ms < 0) timeout_ms = 0;
    wv_com_ensure();

    DWORD start_tick = GetTickCount();

    for (;;) {
        EnterCriticalSection(&s->lock);
        if (!s->running) { LeaveCriticalSection(&s->lock); return CLEONA_VOICE_CAPTURE_CLOSED; }

        if (s->cap_accum_len >= s->fmt.frame_samples) {
            memcpy(out, s->cap_accum, (size_t)s->fmt.frame_bytes);
            s->cap_accum_len -= s->fmt.frame_samples;
            if (s->cap_accum_len > 0) {
                memmove(s->cap_accum, s->cap_accum + s->fmt.frame_samples,
                        (size_t)s->cap_accum_len * sizeof(int16_t));
            }
            LeaveCriticalSection(&s->lock);
            return CLEONA_VOICE_CAPTURE_FRAME;
        }

        HANDLE ev = s->cap_event;
        IAudioCaptureClient* cap = s->cap_capture;
        LeaveCriticalSection(&s->lock);

        DWORD elapsed = GetTickCount() - start_tick;
        DWORD remaining = (elapsed >= (DWORD)timeout_ms) ? 0 : (DWORD)timeout_ms - elapsed;
        if (remaining == 0 && elapsed > 0) return CLEONA_VOICE_CAPTURE_TIMEOUT;

        DWORD w = WaitForSingleObject(ev, remaining == 0 ? 0 : remaining);
        if (w == WAIT_TIMEOUT) {
            if (timeout_ms == 0) {
                /* Non-blocking poll: still drain whatever is already queued
                 * once before giving up, matching S2's "poll instead of
                 * block" semantics without missing already-ready data. */
            } else {
                return CLEONA_VOICE_CAPTURE_TIMEOUT;
            }
        }

        /* Drain every packet currently available (I4: buffer, never drop a
         * "wrong sized" chunk — cleona_voice.h's defect #7 for the superseded
         * stack). */
        EnterCriticalSection(&s->lock);
        for (;;) {
            UINT32 packetFrames = 0;
            if (FAILED(IAudioCaptureClient_GetNextPacketSize(cap, &packetFrames)) || packetFrames == 0) break;

            BYTE* data = NULL; UINT32 numFrames = 0; DWORD flags = 0;
            if (FAILED(IAudioCaptureClient_GetBuffer(cap, &data, &numFrames, &flags, NULL, NULL))) break;

            if (s->cap_accum_len + (int32_t)numFrames > s->cap_accum_cap) {
                /* Consumer not keeping up -- drop and count, never silently
                 * overwrite (cleona_voice_mock.c's defect #1 rationale). */
                s->overruns++;
            } else {
                int16_t* dst = s->cap_accum + s->cap_accum_len;
                if (flags & AUDCLNT_BUFFERFLAGS_SILENT) {
                    memset(dst, 0, (size_t)numFrames * sizeof(int16_t));
                } else if (s->mic_muted) {
                    memset(dst, 0, (size_t)numFrames * sizeof(int16_t)); /* I6: stream stays open, samples zeroed */
                } else {
                    memcpy(dst, data, (size_t)numFrames * sizeof(int16_t));
                }
                s->cap_accum_len += (int32_t)numFrames;
                if (flags & AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY) s->overruns++;
            }
            IAudioCaptureClient_ReleaseBuffer(cap, numFrames);
        }
        LeaveCriticalSection(&s->lock);

        if (timeout_ms == 0 && w == WAIT_TIMEOUT) {
            /* One drain pass done for the non-blocking poll; re-check the
             * accumulator once more at the top of the loop, then return
             * TIMEOUT if still short (loop condition re-evaluates running +
             * accum_len). Force the exit here to honour "do not block". */
            EnterCriticalSection(&s->lock);
            int32_t have = s->cap_accum_len;
            LeaveCriticalSection(&s->lock);
            if (have < s->fmt.frame_samples) return CLEONA_VOICE_CAPTURE_TIMEOUT;
        }
    }
}

CLEONA_VOICE_API int32_t cleona_voice_playback_write(cleona_voice_session_t* s,
                                                     const int16_t* pcm, int32_t frame_samples) {
    if (!s) return CLEONA_VOICE_ERR_CLOSED;
    if (!pcm) return CLEONA_VOICE_ERR_INVALID_ARG;

    EnterCriticalSection(&s->lock);
    if (!s->running) { LeaveCriticalSection(&s->lock); return CLEONA_VOICE_ERR_NOT_STARTED; }
    if (frame_samples != s->fmt.frame_samples) {
        LeaveCriticalSection(&s->lock);
        return CLEONA_VOICE_ERR_FRAME_SIZE;
    }

    /* Never blocks (I5): if the ring is full the caller is far enough ahead
     * that the oldest queued frame is stale anyway -- drop it to make room
     * rather than waiting for the render thread. */
    if (s->pb_ring_len + frame_samples > s->pb_ring_cap) {
        int32_t drop = s->pb_ring_len + frame_samples - s->pb_ring_cap;
        s->pb_ring_head = (s->pb_ring_head + drop) % s->pb_ring_cap;
        s->pb_ring_len -= drop;
        s->overruns++;
    }
    int32_t tail = (s->pb_ring_head + s->pb_ring_len) % s->pb_ring_cap;
    for (int32_t i = 0; i < frame_samples; i++) {
        s->pb_ring[(tail + i) % s->pb_ring_cap] = pcm[i];
    }
    s->pb_ring_len += frame_samples;
    LeaveCriticalSection(&s->lock);
    return CLEONA_VOICE_OK;
}

/* ==========================================================================
 * Controls (I6, I7)
 * ========================================================================== */
CLEONA_VOICE_API void cleona_voice_set_mic_muted(cleona_voice_session_t* s, int32_t muted) {
    if (!s) return;
    EnterCriticalSection(&s->lock);
    s->mic_muted = muted ? 1 : 0;
    LeaveCriticalSection(&s->lock);
}

CLEONA_VOICE_API void cleona_voice_set_output_muted(cleona_voice_session_t* s, int32_t muted) {
    if (!s) return;
    EnterCriticalSection(&s->lock);
    s->output_muted = muted ? 1 : 0;
    LeaveCriticalSection(&s->lock);
}

CLEONA_VOICE_API int32_t cleona_voice_set_route(cleona_voice_session_t* s, int32_t route) {
    if (!s) return CLEONA_VOICE_ERR_CLOSED;
    if (route <= CLEONA_VOICE_ROUTE_UNKNOWN || route > CLEONA_VOICE_ROUTE_BLUETOOTH) {
        return CLEONA_VOICE_ERR_INVALID_ARG;
    }

    EnterCriticalSection(&s->lock);
    if (!(s->routes_mask & CLEONA_VOICE_ROUTE_BIT(route))) {
        LeaveCriticalSection(&s->lock);
        /* Windows has no earpiece -- this is exactly the defined code SPEC §4
         * asks a desktop backend to return for ROUTE_EARPIECE. */
        return CLEONA_VOICE_ERR_ROUTE_UNAVAILABLE;
    }
    if (route == s->route_out) {
        LeaveCriticalSection(&s->lock);
        return CLEONA_VOICE_OK; /* already active */
    }
    IMMDeviceEnumerator* en = s->enumerator;
    LeaveCriticalSection(&s->lock);

    IMMDevice* target = wv_find_render_for_route(en, route);
    if (!target) return CLEONA_VOICE_ERR_ROUTE_UNAVAILABLE;

    int32_t rate = s->fmt.sample_rate;
    IAudioClient2* new_client = NULL; HANDLE new_event = NULL;
    HRESULT hr = wv_activate_and_init(target, &rate, &new_client, &new_event);
    if (FAILED(hr) || rate != s->fmt.sample_rate) {
        /* Known, documented property of this backend (cleona_voice.h,
         * "Where a platform forces a rebuild, that convergence cost is
         * documented"): a target endpoint that cannot deliver the session's
         * negotiated rate cannot be switched to live. */
        if (new_client) IAudioClient2_Release(new_client);
        if (new_event) CloseHandle(new_event);
        IMMDevice_Release(target);
        return CLEONA_VOICE_ERR_BACKEND;
    }
    IAudioRenderClient* new_render = NULL;
    hr = IAudioClient2_GetService(new_client, &IID_IAudioRenderClient, (void**)&new_render);
    if (FAILED(hr) || !new_render) {
        IAudioClient2_Release(new_client);
        CloseHandle(new_event);
        IMMDevice_Release(target);
        return CLEONA_VOICE_ERR_BACKEND;
    }
    UINT32 new_buffer_frames = 0;
    IAudioClient2_GetBufferSize(new_client, &new_buffer_frames);

    EnterCriticalSection(&s->lock);
    int was_running = s->running;
    LeaveCriticalSection(&s->lock);
    if (was_running) hr = IAudioClient2_Start(new_client);

    if (FAILED(hr)) {
        IAudioRenderClient_Release(new_render);
        IAudioClient2_Release(new_client);
        CloseHandle(new_event);
        IMMDevice_Release(target);
        return CLEONA_VOICE_ERR_BACKEND;
    }

    /* Swap under the lock -- the render thread only ever reads these fields
     * while holding it, so this is the entire "rebuild without tearing the
     * capture stream down" (rule 4): the capture side above is never touched. */
    EnterCriticalSection(&s->lock);
    IMMDevice* old_device = s->rnd_device;
    IAudioClient2* old_client = s->rnd_client;
    IAudioRenderClient* old_render = s->rnd_render;
    HANDLE old_event = s->rnd_event;

    s->rnd_device = target;
    s->rnd_client = new_client;
    s->rnd_render = new_render;
    s->rnd_event = new_event;
    s->rnd_buffer_frames = new_buffer_frames;
    s->route_out = route;
    LeaveCriticalSection(&s->lock);

    if (old_client) { IAudioClient2_Stop(old_client); IAudioClient2_Release(old_client); }
    if (old_render) IAudioRenderClient_Release(old_render);
    if (old_event) CloseHandle(old_event);
    if (old_device) IMMDevice_Release(old_device);

    /* The render thread waits on s->rnd_event via a local copy taken under
     * the lock each iteration, so it will pick up the new event handle on its
     * next wait cycle without needing to be restarted. */
    return CLEONA_VOICE_OK;
}

CLEONA_VOICE_API int32_t cleona_voice_get_routes(cleona_voice_session_t* s,
                                                 int32_t* out_mask, int32_t* out_active) {
    if (!s) return CLEONA_VOICE_ERR_CLOSED;
    if (!out_mask || !out_active) return CLEONA_VOICE_ERR_INVALID_ARG;
    EnterCriticalSection(&s->lock);
    wv_recompute_routes_locked(s); /* cheap: re-enumerates + compares, no I/O storm */
    *out_mask = s->routes_mask;
    *out_active = s->route_out;
    LeaveCriticalSection(&s->lock);
    return CLEONA_VOICE_OK;
}

/* ==========================================================================
 * Events
 * ========================================================================== */
CLEONA_VOICE_API int32_t cleona_voice_poll_event(cleona_voice_session_t* s,
                                                 int32_t* out_event, int32_t* out_arg) {
    if (!s) return CLEONA_VOICE_ERR_CLOSED;
    if (!out_event || !out_arg) return CLEONA_VOICE_ERR_INVALID_ARG;

    EnterCriticalSection(&s->lock);
    if (s->ev_count == 0) {
        *out_event = CLEONA_VOICE_EV_NONE;
        *out_arg = 0;
    } else {
        *out_event = s->ev_type[s->ev_head];
        *out_arg = s->ev_arg[s->ev_head];
        s->ev_head = (s->ev_head + 1) % WV_EVENT_QUEUE;
        s->ev_count--;
    }
    LeaveCriticalSection(&s->lock);
    return CLEONA_VOICE_OK;
}

/* ==========================================================================
 * Report (I11)
 * ========================================================================== */
CLEONA_VOICE_API void cleona_voice_get_report(cleona_voice_session_t* s, cleona_voice_report_t* out) {
    if (!out) return;
    memset(out, 0, sizeof(*out));
    if (!s) return;

    EnterCriticalSection(&s->lock);
    out->format = s->fmt;
    out->backend = CLEONA_VOICE_BACKEND_WASAPI;
    out->duplex = (s->cap_client && s->rnd_client) ? 1 : 0;
    out->route_active_in = s->route_in;
    out->route_active_out = s->route_out;
    out->routes_available_mask = s->routes_mask;
    /* Erratum E6a: a plain observation of the state last set through
     * set_mic_muted() / set_output_muted(), never derived from the render
     * thread or the capture drain. Both fields are already normalised to
     * exactly 0 or 1 at the setter (cleona_voice_set_mic_muted /
     * cleona_voice_set_output_muted), so no second normalisation here.
     * Neither setter nor cleona_voice_set_route() ever touches the other
     * field or resets either one, so both survive the render-side rebuild
     * set_route() performs (§10.4 "the mute states survive route changes",
     * S13) structurally, by construction -- not by a special case here. */
    out->mic_muted    = s->mic_muted;
    out->output_muted = s->output_muted;
    out->underruns = s->underruns;
    out->overruns = s->overruns;
    IAudioClient2* cap_client = s->cap_client;
    int32_t chain_origin = s->chain_origin;
    LeaveCriticalSection(&s->lock);

    wv_fx_states_t fx = wv_read_effects(cap_client);
    out->aec_state = fx.aec;
    out->ns_state  = fx.ns;
    out->agc_state = fx.agc;

    int any_enabled = fx.aec == CLEONA_VOICE_FX_ENABLED
                    || fx.ns  == CLEONA_VOICE_FX_ENABLED
                    || fx.agc == CLEONA_VOICE_FX_ENABLED;
    /* chain_origin is reported whenever we have a Windows voice session open
     * at all (WIN_ENDPOINT or WIN_VOICE_DSP, resolved once at open() by
     * wv_detect_chain_origin) -- not only when an effect reads back ENABLED.
     * That satisfies cleona_voice.h's "MUST NOT be CHAIN_NONE if ENABLED"
     * (any_enabled implies chain_origin is one of the two WIN_* constants,
     * never NONE) while also matching the mock's convention of describing the
     * chain even when every effect is UNAVAILABLE/AVAILABLE_OFF/UNKNOWN. */
    (void)any_enabled;
    out->chain_origin = chain_origin;
}

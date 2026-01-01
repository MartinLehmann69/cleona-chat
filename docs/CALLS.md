# CALLS.md — Voice & Video Calls Architektur

## Status
Phase 3a (1:1 Audio-Calls), Phase 3b (1:1 Video-Calls) und Phase 3d (Overlay Multicast Tree) abgeschlossen.
Phase 3c (Gruppen-Calls) offen.

---

## 1. Uebersicht

### 1.1 Design-Prinzipien
- **Direkt P2P**, kein Server, kein SFU, kein TURN
- **Post-Quantum-Verschluesselung:** X25519 Ephemeral DH + ML-KEM-768 Hybrid (wie Messages)
- **Overlay Multicast Tree** fuer Gruppen-Calls (kein Full Mesh)
- **LAN IPv6 Multicast** fuer lokale Teilnehmer (ff02::cleona:call)
- **Minimaler Overhead:** Eigenes Frame-basiertes Protokoll, kein RTP/SRTP-Stack
- **Forward Secrecy:** Ephemeral Keys nur im RAM, nie persistiert

### 1.2 Bestehende Implementierung (Prototyp)

**CallManager** (`lib/core/calls/call_manager.dart`):
- Vollstaendige 1:1 Signaling State Machine (idle → ringing → inCall → ended)
- `CallSession` mit Ephemeral X25519 Keypair, Shared Secret, Call-ID (16 Bytes random)
- Signaling-Nachrichten: CALL_INVITE, CALL_ANSWER, CALL_REJECT, CALL_HANGUP
- Key Exchange: Beidseitiges Ephemeral X25519 DH → SHA-256 KDF → 32-Byte Shared Secret
- Auto-Reject bei Busy (bereits im Call)
- Verdrahtet in `CleonaService`: Eingehende Envelopes werden an Handler dispatcht
- UI-Callbacks: `onIncomingCall`, `onCallAccepted`, `onCallRejected`, `onCallEnded`

**AudioEngine** (`lib/core/calls/audio_engine.dart`):
- PulseAudio Simple API via dart:ffi (nur Linux)
- Capture: 16 kHz, Mono, 16-Bit PCM, 20ms Frames (640 Bytes)
- Playback: Gleiche Parameter, `pa_simple_write()` pro Frame
- Verschluesselung: AES-256-GCM pro Frame
- Frame-Format: `[4B seqNum][12B nonce][ciphertext + 16B GCM-Tag]`
- Capture-Loop: `Timer.periodic(20ms)` → `pa_simple_read()` → encrypt → Callback
- Playback: `playFrame()` → decrypt → `pa_simple_write()`

**CleonaService** Integration (`lib/core/service/cleona_service.dart`):
- CallManager wird bei `startService()` initialisiert
- AudioEngine startet automatisch bei `onCallAccepted`
- AudioEngine stoppt bei `onCallRejected`, `onCallEnded`, `hangup()`
- CALL_AUDIO Frames werden direkt via `sendEnvelope()` an den Peer geschickt
- Empfangene CALL_AUDIO Frames werden direkt an `AudioEngine.playFrame()` weitergeleitet

**Call-UI** (`lib/ui/screens/call_screen.dart`):
- Peer-Avatar (Initial-Buchstabe), Name, Status-Text
- Eingehend: Annehmen/Ablehnen Buttons
- Im Gespraech: Mute/Speaker Toggles (nur UI-State, nicht verdrahtet), Auflegen
- Timer-Anzeige (mm:ss), Verschluesselungs-Indikator
- Auto-Pop bei Call-Ende

**Protobuf Messages** (`proto/cleona.proto`):
- `CALL_INVITE = 30`, `CALL_ANSWER = 31`, `CALL_REJECT = 32`, `CALL_HANGUP = 33`
- `ICE_CANDIDATE = 34`, `CALL_REJOIN = 35`, `CALL_AUDIO = 36`

### 1.3 Bekannte Luecken im Prototyp
1. ~~**ML-KEM nicht integriert**~~ — **FIXED in v2.7.1:** Hybrid X25519 + ML-KEM-768 in CallManager implementiert
2. ~~**Kein Jitter Buffer**~~ — **FIXED in v2.8:** 100ms adaptiver Buffer
3. ~~**Kein Opus-Codec**~~ — **FIXED in v2.8:** libopus FFI (16-64 kbps)
4. ~~**Mute/Speaker nur UI**~~ — **FIXED in v2.8:** Mit AudioEngine verdrahtet
5. **Kein Video-Support**
6. **Kein NAT Traversal fuer Media** — nur Direct-Send
7. **Keine Gruppen-Calls**
8. ~~**Timer.periodic blockiert**~~ — **FIXED in v2.8:** Capture-Loop in eigenem Isolate

---

## 2. Signaling-Protokoll

### 2.1 1:1 Call Flow

```
Alice                                          Bob
  │                                              │
  │─── CALL_INVITE ─────────────────────────────→│
  │    (call_id, eph_x25519_pk_a,                │
  │     kem_ciphertext_a, is_video)              │
  │                                              │
  │    [Bob sieht "Eingehender Anruf..."]        │
  │                                              │
  │←── CALL_ANSWER ──────────────────────────────│
  │    (call_id, eph_x25519_pk_b,                │
  │     kem_ciphertext_b)                        │
  │                                              │
  │  Beide: call_key = HKDF-SHA256(              │
  │    DH(eph_sk_a, eph_pk_b) ||                 │
  │    DH(eph_sk_b, eph_pk_a) ||                 │
  │    KEM_ss_a || KEM_ss_b,                     │
  │    "cleona-call-v1")                         │
  │                                              │
  │←──── Verschluesselte Media Frames ──────────→│
  │    (CALL_AUDIO / CALL_VIDEO)                 │
  │                                              │
  │─── CALL_HANGUP ─────────────────────────────→│
  │    (call_id)                                 │
```

**Timing:**
- Klingeln-Timeout: 60s (danach automatisch CALL_HANGUP)
- Invite wird per UDP gesendet (Relay-Cascade bei Bedarf)

### 2.2 Ablehnungs-Szenarien

| Szenario | Aktion |
|----------|--------|
| Bob lehnt ab | CALL_REJECT (reason: "declined") |
| Bob ist im Call | Auto-CALL_REJECT (reason: "busy") |
| Bob ist offline | Timeout nach 60s, kein Retry |
| Netzwerk-Fehler | CALL_HANGUP von beiden Seiten moeglich |

### 2.3 Gruppen-Call Flow (geplant)

```
Initiator                   Teilnehmer A, B, C
  │                                │
  │─── CALL_INVITE (is_group) ───→│ (an jeden einzeln, Per-Message KEM)
  │    + encrypted call_key        │
  │                                │
  │←── CALL_ANSWER ───────────────│ (pro Teilnehmer)
  │                                │
  │  [Media ueber Overlay Tree]    │
  │                                │
  │─── KEY_ROTATION ──────────────→│ (bei Kick oder neuer Teilnehmer)
  │    + neuer call_key            │
```

- Initiator generiert zufaelligen 256-Bit `call_key`
- Key wird an jeden Teilnehmer einzeln per Per-Message KEM verschluesselt
- Key-Rotation bei: Kick, neuer Teilnehmer beitritt
- KEINE Rotation bei Crash+Rejoin (Forward Secrecy akzeptabel, da kurzlebig)

### 2.4 Protobuf-Definitionen (bestehend)

```protobuf
message CallInvite {
  bytes call_id = 1;
  bytes caller_eph_x25519_pk = 2;
  bytes caller_kem_ciphertext = 3;    // ML-KEM-768 (FIXED v2.7.1)
  bool is_video = 4;
  bool is_group_call = 5;
  bytes group_id = 6;
}

message CallAnswer {
  bytes call_id = 1;
  bytes callee_eph_x25519_pk = 2;
  bytes callee_kem_ciphertext = 3;    // ML-KEM-768 (FIXED v2.7.1)
}

message CallReject {
  bytes call_id = 1;
  string reason = 2;
}

message CallHangup {
  bytes call_id = 1;
}

message IceCandidate {
  bytes call_id = 1;
  string candidate = 2;
  string sdp_mid = 3;
  uint32 sdp_m_line_index = 4;
}

message CallRejoin {
  bytes call_id = 1;
}

// MessageType Enum:
// CALL_INVITE = 30, CALL_ANSWER = 31, CALL_REJECT = 32,
// CALL_HANGUP = 33, ICE_CANDIDATE = 34, CALL_REJOIN = 35,
// CALL_AUDIO = 36
```

---

## 3. Call-Key Negotiation

### 3.1 Hybrid Key Exchange (1:1) — Zielzustand

**Sende-Seite (Caller):**
1. Frisches X25519 Ephemeral Keypair: `(eph_pk_a, eph_sk_a)`
2. ML-KEM-768 Encapsulate mit Bob's ML-KEM Public Key: `(kem_ct_a, kem_ss_a) = Encap(bob_ml_kem_pk)`
3. Sende CALL_INVITE: `{eph_pk_a, kem_ct_a, is_video}`

**Empfangs-Seite (Callee):**
1. ML-KEM-768 Decapsulate: `kem_ss_a = Decap(kem_ct_a, own_ml_kem_sk)`
2. Frisches X25519 Ephemeral Keypair: `(eph_pk_b, eph_sk_b)`
3. ML-KEM-768 Encapsulate mit Alice's ML-KEM Public Key: `(kem_ct_b, kem_ss_b) = Encap(alice_ml_kem_pk)`
4. DH: `dh_secret = X25519(eph_sk_b, eph_pk_a)`
5. `call_key = HKDF-SHA256(dh_secret || kem_ss_a || kem_ss_b, "cleona-call-v1")`
6. Sende CALL_ANSWER: `{eph_pk_b, kem_ct_b}`

**Caller nach Empfang von CALL_ANSWER:**
1. DH: `dh_secret = X25519(eph_sk_a, eph_pk_b)`
2. ML-KEM-768 Decapsulate: `kem_ss_b = Decap(kem_ct_b, own_ml_kem_sk)`
3. `call_key = HKDF-SHA256(dh_secret || kem_ss_a || kem_ss_b, "cleona-call-v1")`

**Ergebnis:** Identischer 32-Byte `call_key` auf beiden Seiten. Hybrid-sicher gegen klassische UND Quanten-Angriffe.

**Overhead pro Signaling:**
- X25519 eph_pk: 32 Bytes
- ML-KEM-768 ciphertext: 1088 Bytes
- Gesamt pro Richtung: ~1120 Bytes (vernachlaessigbar)

### 3.2 Implementierung (DONE)

**Status:** Vollstaendig implementiert (v2.8). `call_manager.dart` nutzt Hybrid X25519 + ML-KEM-768 Key-Exchange mit HKDF-SHA256:
1. `startCall()`: ML-KEM Encapsulate mit Peer's ML-KEM Public Key
2. `acceptCall()`: ML-KEM Decapsulate + eigene Encapsulation, HKDF-SHA256 KDF
3. `handleCallAnswer()`: ML-KEM Decapsulate, HKDF-SHA256 KDF
4. KDF: `HKDF-SHA256(dh_secret || kem_ss_caller || kem_ss_callee, "cleona-call-v1")`

Alle Differenzen zum Zielzustand aus Sektion 3.1 sind behoben:
1. ~~Kein ML-KEM~~ — **FIXED (v2.7.1)**
2. ~~SHA-256 statt HKDF-SHA256 als KDF~~ — **FIXED (v2.8)**
3. ~~KDF-Context `"cleona-call-key"` statt `"cleona-call-v1"`~~ — **FIXED (v2.8)**

### 3.4 Gruppen-Key Distribution

- Initiator generiert zufaelligen 256-Bit Key: `call_key = randomBytes(32)`
- An jeden Teilnehmer per Per-Message KEM verschluesselt (gleicher Mechanismus wie normale Nachrichten)
- **Rotation-Events:**
  - Kick: Neuer Key generiert, an verbleibende Teilnehmer verteilt
  - Neuer Teilnehmer: Neuer Key generiert, an ALLE (inkl. neuem) verteilt
  - Crash+Rejoin: Kein neuer Key (Rejoin mit altem Key)
- **Kein Rekeying bei Audio-Stille** — Key gilt fuer gesamte Call-Dauer

---

## 4. Media-Transport

### 4.1 Audio

| Parameter | Prototyp (aktuell) | Ziel (MVP) |
|-----------|-------------------|------------|
| Codec | PCM 16-bit | Opus |
| Sample Rate | 16 kHz | 48 kHz |
| Channels | Mono | Mono |
| Frame-Dauer | 20 ms | 20 ms |
| Frame-Groesse (roh) | 640 Bytes | 640 Bytes (Opus: ~40-80 Bytes) |
| Bitrate | 256 kbps (roh) | 16-64 kbps (Opus) |
| Verschluesselung | AES-256-GCM | AES-256-GCM |

**Frame-Format (bestehend, bewaehrt):**
```
[4 Bytes: Sequence Number (Big Endian)]
[12 Bytes: AES-256-GCM Nonce (random)]
[N Bytes: Ciphertext + 16 Bytes GCM Authentication Tag]
```

- Sequence Number: Monoton steigend, fuer Replay-Protection und Reordering
- Nonce: Zufaellig generiert (NICHT aus Sequence Number abgeleitet — sicherer)
- GCM-Tag: 16 Bytes Authentisierung

**Paketgroesse:**
- Aktuell (PCM): 4 + 12 + 640 + 16 = 672 Bytes/Frame → 33.600 Bytes/s
- Ziel (Opus): 4 + 12 + ~60 + 16 = ~92 Bytes/Frame → ~4.600 Bytes/s

**Jitter Buffer (geplant):**
- Einfacher adaptiver Buffer: 40-200ms (2-10 Frames)
- Sortierung nach Sequence Number
- Spaete Pakete verwerfen (> Buffer-Fenster)
- Luecken-Interpolation: Silence oder letztes Frame wiederholen

### 4.2 Video (geplant)

| Parameter | Wert |
|-----------|------|
| Codec | VP8 (Software) oder H.264 (Hardware) |
| Aufloesung | 360p (Mobil), 720p (Desktop), 1080p (WiFi/LAN) |
| Framerate | 30 fps (Standard), 15 fps (Low-Bandwidth) |
| Keyframe-Intervall | 2 Sekunden |
| Bitrate | 500 kbps - 2 Mbps (adaptiv) |
| Verschluesselung | AES-256-GCM pro Frame (wie Audio) |

**Video-Frame-Format:**
```
[4 Bytes: Sequence Number]
[1 Byte: Flags (Keyframe, Fragment-Index, Last-Fragment)]
[12 Bytes: Nonce]
[N Bytes: Ciphertext + 16 Bytes GCM Tag]
```

- Grosse Frames (> MTU 1200 Bytes): Fragmentierung in Chunks
- Keyframe-Request: Bei zu vielen verlorenen Frames (> 5% Loss)
- Kein FEC auf Video-Ebene (UDP + Retransmit fuer Keyframes)

### 4.3 Paket-Priorisierung

- Audio-Pakete haben Vorrang (niedrigere Latenz-Toleranz: <150ms)
- Video kann bei Paketverlust degradieren:
  - Keyframe anfordern
  - Framerate senken (30→15 fps)
  - Aufloesung senken (720p→360p)
- Bei > 30% Packet Loss: Video automatisch pausieren, nur Audio

### 4.4 Capture-Isolate (DONE v2.8)

`pa_simple_read()` blockiert bis Daten verfuegbar. Seit v2.8 laeuft der Capture-Loop in einem eigenen `Isolate`:

1. **Capture-Isolate:** Eigene PulseAudio-Session + SodiumFFI, `pa_simple_read()` → encrypt → `SendPort`
2. **Main-Isolate:** `ReceivePort` → `onAudioFrame` Callback (non-blocking)
3. **Playback:** Bleibt im Main-Isolate (`pa_simple_write()` ist non-blocking bei kleinen Frames)
4. **Steuerung:** Mute/Unmute/Stop via `_CaptureCommand` enum ueber `SendPort`

---

## 5. NAT Traversal fuer Media

### 5.1 ICE-aehnliches Verfahren

Cleona hat kein STUN/TURN-Server. NAT Traversal nutzt die bestehende P2P-Infrastruktur:

**Candidate-Ermittlung:**
1. **Host Candidates:** Lokale IP-Adressen (IPv4 + IPv6 Link-Local)
2. **Server-Reflexive:** Peer-reported Public IP (aus DHT-Kommunikation bekannt)
3. **LAN Multicast:** IPv6 ff02::1 Discovery-Adresse

**Ablauf:**
```
Alice                                          Bob
  │                                              │
  │  [Nach CALL_ANSWER, Shared Secret steht]     │
  │                                              │
  │─── ICE_CANDIDATE (host: 192.168.1.5:39874)─→│
  │─── ICE_CANDIDATE (srflx: 85.1.2.3:39874)──→│
  │                                              │
  │←── ICE_CANDIDATE (host: 192.168.1.10:20280)─│
  │←── ICE_CANDIDATE (srflx: 91.4.5.6:20280)───│
  │                                              │
  │  [Beide probieren alle Candidate-Paare]      │
  │  [Erster erfolgreicher Pfad gewinnt]         │
```

**Kandidat-Selektion:**
- Multi-Address Parallel Delivery (wie bei normalen Nachrichten)
- Priorisierung: LAN > Host > Server-Reflexive
- Connectivity Check: Verschluesseltes Ping-Pong (CALL_AUDIO Sequenz 0 als Probe)

### 5.2 UDP Hole Punching

- Nutzt den vorhandenen Transport-Socket (gleicher UDP-Port wie alle andere Kommunikation)
- Beide Seiten senden gleichzeitig an die Server-Reflexive-Adresse des anderen
- Timeout: 5s, dann naechstes Candidate-Paar

### 5.3 Relay Fallback

Wenn direkter Kontakt nicht moeglich (symmetrisches NAT, restriktive Firewall):

1. **Gemeinsamer Kontakt als Relay:** Ein Peer, der beide Teilnehmer direkt erreichen kann
2. **Media-Relay Overhead:** ~2x Latenz, aber funktioniert durch jedes NAT/Firewall

**Relay-Protokoll:**
- Relay-Peer leitet verschluesselte Frames weiter (kann Inhalt NICHT entschluesseln)
- Relay sieht nur: Absender-IP, Empfaenger-IP, Paketgroesse
- Auswahl: Peer mit bester Erreichbarkeit zu beiden Teilnehmern

---

## 6. Overlay Multicast Tree (Gruppen-Calls)

### 6.1 Problem: Full Mesh skaliert nicht

| Teilnehmer | Upload pro Person (Audio) | Upload pro Person (Video 720p) |
|------------|--------------------------|-------------------------------|
| 3 | 2 × 16 kbps = 32 kbps | 2 × 1 Mbps = 2 Mbps |
| 5 | 4 × 16 kbps = 64 kbps | 4 × 1 Mbps = 4 Mbps |
| 10 | 9 × 16 kbps = 144 kbps | 9 × 1 Mbps = 9 Mbps |
| 20 | 19 × 16 kbps = 304 kbps | 19 × 1 Mbps = 19 Mbps |

Ab 5+ Teilnehmern mit Video ist Full Mesh fuer Heim-Anschluesse nicht tragbar.

### 6.2 Loesung: Application-Layer Multicast

**Baumstruktur:**
- Jeder Node leitet empfangene Media-Frames an max. 2-3 Kinder weiter
- Upload pro Person: max. 3 × Bitrate (statt N-1)
- Konstruktion: RTT-basiert, Nodes mit bester Konnektivitaet als innere Knoten

**Beispiel (8 Teilnehmer, Fan-Out 3):**
```
          Initiator
         /    |    \
        A     B     C
       /|\   /
      D E F G
              \
               H
```

- Initiator sendet an A, B, C (3 Streams)
- A sendet an D, E, F (3 Streams)
- B sendet an G (1 Stream)
- Upload: max. 3 Streams pro Node

### 6.3 LAN-Optimierung

Wenn mehrere Teilnehmer im selben LAN:
- IPv6 Multicast `ff02::cleona:call` fuer Audio/Video
- EIN Paket fuer alle LAN-Teilnehmer (statt N Einzelpakete)
- Erkennung: Gleiche IPv6 Link-Local Prefix oder IPv4 Subnetz
- Automatischer Fallback auf Unicast bei Multicast-Failure

### 6.4 Baum-Rebalancing

| Event | Aktion |
|-------|--------|
| Join | Neuer Node ans Ende anhaengen, Rebalancing wenn Tiefe > log₃(N)+1 |
| Leave | Kinder des verlassenden Nodes an dessen Eltern umhaengen |
| Crash | Timeout-Detection (3s kein Paket), automatisches Reattach an naechsten verfuegbaren Eltern-Node |
| Latenz-Spike | Subtree neu balancieren (> 200ms kumulative Latenz) |

### 6.5 Skalierungslimits

| Modus | Max. Teilnehmer | Begruendung |
|-------|-----------------|-------------|
| Audio-Only | 100+ | 16 kbps/Stream, Baumtiefe ~5, kumulative Latenz <500ms |
| Video 360p | 50 | 500 kbps/Stream, Fan-Out 3, kumulative Latenz akzeptabel |
| Video 720p | 20 | 1 Mbps/Stream, Upload-Limit der inneren Knoten |
| Video 1080p | 10 | 2 Mbps/Stream, nur in LAN sinnvoll |

---

## 7. Plattform-Support

### 7.1 Linux (Prototyp — implementiert)

| Komponente | Status | Implementierung |
|------------|--------|----------------|
| Audio Capture | Funktioniert | PulseAudio Simple API via dart:ffi |
| Audio Playback | Funktioniert | PulseAudio Simple API via dart:ffi |
| AES-256-GCM | Funktioniert | libsodium via SodiumFFI |
| Video Capture | Nicht implementiert | — |
| Video Playback | Nicht implementiert | — |

**Abhaengigkeiten:** `libpulse-simple.so.0` (PulseAudio), `libsodium.so` (Crypto)

**PipeWire-Kompatibilitaet:** PipeWire bietet PulseAudio-kompatible API, der bestehende Code funktioniert ohne Aenderung.

### 7.2 Android (geplant)

| Komponente | API | Notes |
|------------|-----|-------|
| Audio Capture | Oboe (C++) oder AudioRecord (Java) | Via Platform Channel |
| Audio Playback | Oboe oder AudioTrack | Low-Latency ueber AAudio Backend |
| Video Capture | CameraX | Platform Channel |
| Video Playback | TextureWidget + SurfaceTexture | Flutter-native |

**Permissions:**
- `android.permission.RECORD_AUDIO`
- `android.permission.CAMERA`
- `android.permission.FOREGROUND_SERVICE` (fuer Hintergrund-Calls)

**Besonderheiten:**
- Wakelock waehrend Call (Bildschirm-Aus erlaubt, CPU wach)
- Proximity Sensor: Bildschirm aus bei Ohr-Naehe
- Audio Focus: Andere Apps stummschalten

### 7.3 iOS (geplant)

| Komponente | API | Notes |
|------------|-----|-------|
| Audio Capture | AVAudioEngine | Low-Latency Audio Unit |
| Audio Playback | AVAudioEngine | Routing: Speaker/Kopfhoerer |
| Video Capture | AVCaptureSession | Front/Back Kamera |
| Video Playback | TextureWidget + CVPixelBuffer | Flutter-native |

**Info.plist Eintraege:**
- `NSMicrophoneUsageDescription`
- `NSCameraUsageDescription`

**Besonderheiten:**
- CallKit Integration fuer native Anruf-UI und Siri-Integration
- VoIP Push Notifications (PushKit) fuer eingehende Calls bei geschlossener App
- Audio Session Category: `.playAndRecord` mit `.allowBluetooth`

### 7.4 Codec-Strategie

| Option | Vorteile | Nachteile |
|--------|----------|-----------|
| **A: flutter_webrtc** | Full Stack (Audio+Video+NAT), bewaehrt | Grosse Dependency (~15 MB), eigenes Signaling kollidiert, schwer zu debuggen |
| **B: libopus FFI + Plattform-Audio** | Leichtgewichtig, volle Kontrolle, passt zu Cleona-Architektur | Mehr Implementierungsarbeit, Video muss separat geloest werden |
| **C: Hybrid (eigenes Signaling + WebRTC Media)** | Nutzt WebRTC Media-Stack ohne Signaling-Konflikt | Komplexe Integration, zwei Crypto-Stacks |

**Empfehlung:** Option B fuer Audio-MVP, dann evaluieren ob flutter_webrtc fuer Video sinnvoll ist.

**Begruendung:**
- Cleona hat bereits eigenes Signaling, eigene Crypto, eigenes NAT Traversal
- libopus ist ~300 KB (vs. 15 MB WebRTC), laesst sich einfach via FFI einbinden
- Volle Kontrolle ueber Verschluesselung (kein SRTP/DTLS noetig)
- Video kann spaeter ueber Plattform-APIs (CameraX/AVCaptureSession) + eigenes Framing geloest werden

---

## 8. Call-UI

### 8.1 Bestehend (call_screen.dart)

- **Layout:** Fullscreen, SafeArea, vertikale Anordnung
- **Peer-Info:** CircleAvatar mit Initial, Name, Status-Text
- **Ringing-Modus (eingehend):** Zwei Buttons — Ablehnen (rot) / Annehmen (gruen)
- **Ringing-Modus (ausgehend):** Ein Button — Auflegen (rot)
- **In-Call-Modus:** Mute-Toggle, Speaker-Toggle, Auflegen
- **Timer:** Sekundengenau (MM:SS oder H:MM:SS)
- **Verschluesselung:** Lock-Icon + "Ende-zu-Ende verschluesselt"
- **Auto-Navigation:** Pop bei Call-Ende (currentCall == null)

### 8.2 Geplant

| Feature | Prioritaet | Beschreibung |
|---------|-----------|-------------|
| Mute verdrahten | Hoch | AudioEngine.capture pausieren bei Mute |
| Speaker verdrahten | Hoch | PulseAudio Sink wechseln |
| Video-Ansicht | Mittel | Lokale + Remote Video, PiP-Layout |
| Vollbild-Modus | Mittel | Immersive Mode bei Video |
| Bild-in-Bild (PiP) | Niedrig | Android: PiP Activity, iOS: CallKit |
| Teilnehmer-Liste | Mittel | Gruppen-Calls: Grid mit Avataren |
| Screen-Sharing | Niedrig | Spaeter, nicht fuer v1 |
| Kamera-Wechsel | Mittel | Front/Back bei Video-Calls |
| Bluetooth-Audio | Niedrig | Plattform-spezifisch |

### 8.3 Video-Layout (geplant)

**1:1 Video:**
```
┌──────────────────────────┐
│                          │
│    Remote Video (gross)  │
│                          │
│              ┌──────┐    │
│              │ Lokal│    │
│              │(PiP) │    │
│              └──────┘    │
│  [Mute] [Kamera] [Ende] │
└──────────────────────────┘
```

**Gruppen-Video (4 Teilnehmer):**
```
┌────────────┬────────────┐
│  Peer A    │  Peer B    │
│            │            │
├────────────┼────────────┤
│  Peer C    │  Lokal     │
│            │            │
└────────────┴────────────┘
      [Mute] [Ende]
```

---

## 9. Implementierungs-Roadmap

### Phase 3a: 1:1 Audio-Calls (MVP)

**Ziel:** Funktionierender Audio-Call zwischen zwei Linux-Nodes.

| # | Aufgabe | Aufwand | Abhaengigkeit | Status |
|---|---------|---------|---------------|--------|
| 1 | ~~ML-KEM in CallManager integrieren~~ | ~~1 Tag~~ | — | **DONE (v2.7.1)** |
| 2 | KDF auf HKDF-SHA256 umstellen + Context-String "cleona-call-v1" | 0.5 Tage | #1 | **DONE (v2.8)** |
| 3 | Mute/Speaker mit AudioEngine verdrahten | 0.5 Tage | — | **DONE (v2.8)** |
| 4 | Capture-Loop in Isolate verschieben | 1 Tag | — | **DONE (v2.8)** |
| 5 | Jitter Buffer implementieren (einfach, 100ms) | 1 Tag | — | **DONE (v2.8)** |
| 6 | Opus-Codec via libopus FFI | 2-3 Tage | — | **DONE (v2.8)** |
| 7 | Klingel-Timeout (60s) | 0.5 Tage | — | **DONE (v2.8)** |
| 8 | Smoke-Tests (Call Signaling + Audio Round-Trip) | 1 Tag | #1-#7 | **DONE (v2.8, 64 Tests)** |
| 9 | E2E-Test ueber VMs | 1 Tag | #8 | **DONE (v3.1.20, 11 Desktop + 4 AVM E2E, Frame-Counter IPC)** |

**Status:** 9/9 Aufgaben abgeschlossen. Phase 3a komplett.

### Phase 3b: 1:1 Video-Calls

| # | Aufgabe | Aufwand | Status |
|---|---------|---------|--------|
| 1 | Codec: VP8 via libvpx FFI (C-Shim + Dart Binding) | 1 Tag | **DONE (v3.1.21)** |
| 2 | Video-Capture Linux (v4l2 FFI C-Shim) | 1 Tag | **DONE (v3.1.21)** |
| 3 | Video-Display + VideoEngine (Capture-Isolate, I420→RGBA) | 1 Tag | **DONE (v3.1.21)** |
| 4 | CALL_VIDEO(40) + CALL_KEYFRAME_REQUEST(41) Protobuf | 0.5 Tag | **DONE (v3.1.21)** |
| 5 | Adaptive Bitrate (BandwidthEstimator, Degradation-Cascade) | 0.5 Tag | **DONE (v3.1.21)** |
| 6 | Video-UI (PiP-Layout, Kamera-Wechsel, Video-Toggle) | 0.5 Tag | **DONE (v3.1.21)** |
| 7 | Android Video-Capture (CameraX Platform Channel) | 1 Tag | **DONE (v3.1.21)** |

**Status:** 7/7 Aufgaben abgeschlossen. Phase 3b komplett.

### Phase 3c: Gruppen-Calls (Full Mesh MVP)

| # | Aufgabe | Aufwand |
|---|---------|---------|
| 1 | Multi-Participant CallManager State Machine | 2-3 Tage |
| 2 | Gruppen-Key-Distribution (Per-Message KEM) | 1 Tag |
| 3 | Key-Rotation bei Join/Leave/Kick | 1 Tag |
| 4 | CALL_REJOIN Handling | 1 Tag |
| 5 | Full Mesh Audio (bis 5 Teilnehmer) | 1 Tag |
| 6 | Audio-Mixing (mehrere Streams ueberlagern) | 1-2 Tage |
| 7 | Gruppen-Call UI (Teilnehmer-Grid) | 1 Tag |

**Geschaetzter Aufwand:** ~8-11 Tage

### Phase 3d: Overlay Multicast Tree

| # | Aufgabe | Aufwand | Status |
|---|---------|---------|--------|
| 1 | RTT-Messung zwischen Teilnehmern (Ping-Pong) | 1 Tag | **DONE (v3.1.20)** |
| 2 | Baum-Konstruktions-Algorithmus (MST + DV-Route-Costs) | 2-3 Tage | **DONE (v3.1.20)** |
| 3 | Media-Relay Implementierung (Forward-Logik) | 2 Tage | **DONE (v3.1.20)** |
| 4 | Rebalancing bei Join/Leave/Crash | 2 Tage | **DONE (v3.1.20)** |
| 5 | LAN IPv6 Multicast Integration | 1 Tag | **DONE (v3.1.20)** |
| 6 | Skalierungs-Tests (10, 20, 50 Teilnehmer) | 2 Tage | **DONE (v3.1.20, 100 Smoke-Tests)** |

**Status:** 6/6 Aufgaben abgeschlossen. Phase 3d komplett.

### Gesamt-Schaetzung Phase 3

| Sub-Phase | Aufwand | Kumulativ |
|-----------|---------|-----------|
| 3a: 1:1 Audio (MVP) | 8-10 Tage | 8-10 Tage |
| 3b: 1:1 Video | 10-14 Tage | 18-24 Tage |
| 3c: Gruppen (Full Mesh) | 8-11 Tage | 26-35 Tage |
| 3d: Overlay Multicast | 10-13 Tage | 36-48 Tage |

---

## 10. Offene Entscheidungen

- [ ] **Codec:** libopus FFI vs flutter_webrtc vs Plattform-nativ?
  - Empfehlung: libopus FFI fuer Audio, VP8/H.264 spaeter entscheiden
- [ ] **Video-Transport:** Eigenes Frame-Format vs RTP/SRTP?
  - Empfehlung: Eigenes Format (konsistent mit Audio, volle Crypto-Kontrolle)
- [ ] **Gruppen-Call Limit:** 10? 20? 50?
  - Empfehlung: Audio 50, Video 20, im UI konfigurierbar
- [ ] **Screen Sharing:** Ja/Nein fuer v1?
  - Empfehlung: Nein fuer v1, spaetere Phase
- [ ] **Disappearing Messages:** Timer auch fuer Call-History?
  - Empfehlung: Ja, konsistent mit Chat-Policy
- [ ] **Android-Audio-API:** Oboe (C++ via FFI) vs AudioRecord (Java via Platform Channel)?
  - Empfehlung: Platform Channel (einfacher), Oboe nur bei Latenz-Problemen
- [ ] **Capture-Isolate:** Dart Isolate vs native Thread?
  - Empfehlung: Dart Isolate (portabel, einfacher zu debuggen)
- [ ] **Ringtone:** System-Sound vs eigener Sound vs nur Vibration?
  - Empfehlung: System-Sound (Plattform-nativ) + Vibration auf Mobil

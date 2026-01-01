# Cleona Chat — Feature TODO (Stand V3.1.67, 2026-04-18)

Features die in der Master-Architektur-Doku (`Cleona_Chat_Architecture_v2_2.md`) beschrieben aber noch nicht oder nur teilweise implementiert sind. Erledigte Eintraege werden entfernt (Belege stehen im Changelog).

## Offen, mittel

### Signed Update Manifest — UI-Widget fehlt noch
- **Architektur:** §17.5.5
- **Status:** `UpdateChecker` laeuft periodisch (6h), `onUpdateAvailable` Callback existiert (V3.1.26)
- **TODO:** UI-Banner in HomeScreen, non-dismissable Dialog bei deprecated Version

### Secret Rotation V2+
- **Architektur:** §17.5.5
- **Status:** Framework mit Dual-Secret + 90-Tage-Transition implementiert (V3.1.23), nur V1 existiert
- **TODO:** Bei naechstem Major-Release: V2-Secret generieren, in `network_secret.dart` eintragen

### Camera Crop/Rotate
- **Architektur:** §14.2
- **Status:** Video-Capture auf Android/Linux vorhanden, kein Crop/Rotate fuer Fotos
- **TODO:** `image_cropper`-Package oder eigene Implementierung

### Paket C Retry-Pfad (KEY_ROTATION_BROADCAST an Offline-Kontakte)
- **Architektur:** §26.6.2
- **Status:** 30d-S&F-TTL committed (V3.1.67, e916e36). `_handleKeyRotationAck`-Retry fuer weiterhin offline bleibende Kontakte noch offen.
- **TODO:** Persistente State-Machine + Timer, security-sensitive — User-Review vor Implementierung

## Offen, niedrig / Zukunft

### Share Peer List (.clp Datei)
- **Architektur:** §2.3.4
- **TODO:** "Share my network"-Button, `.clp`-Export (signierte Peer-Liste), Import per Intent/File-Picker

### FCM/APNs Push Wake-up
- **Architektur:** §7.5
- **Status:** Nicht implementiert, Adaptive Polling als P2P-Alternative in V3.1.56 dokumentiert
- **TODO:** Zero-content Push-Notification fuer Mobile Wake-up, Push-Token-Registrierung, Relay-Service

### iOS Platform Support
- **Architektur:** §18.2
- **Status:** Flutter-Scaffold vorhanden, keine plattformspezifische Logik
- **TODO:** Swift-Code fuer Crypto-FFI, Audio-Engine, Background-Service, Secure Enclave Key Storage

### Biometric/PIN App Lock
- **Architektur:** §14.2
- **TODO:** `local_auth`-Package, PIN-Fallback, Lock-Screen, Auto-Lock-Timer

### Reputation System (fortgeschritten)
- **Architektur:** §9.3
- **Status:** Basis implementiert (V3.1.26/V3.1.38), fortgeschrittene Features offen
- **TODO:** Gewichtete Scoring-Faktoren (Uptime, Relay-Beitrag, Fragment-Storage), UI-Dashboard

### Network Size Estimation
- **Architektur:** §11.1
- **TODO:** Random DHT-Adressraum-Sampling, statistische Schaetzung (Mark-Recapture-Analogie)

### Sliding Window Congestion Control
- **Architektur:** §14.5 (explizit als "planned" markiert)
- **TODO:** Fuer grosse Netzwerke (Millionen Peers) — RUDP Light um Window-basierte Flow Control erweitern

### In-Call Collaboration (§25)
- Whiteboard (Echtzeit, Multi-Page), Screen-Sharing (PipeWire/MediaProjection), File/Clipboard-Exchange, Call-Chat, Remote Control (Phase 2)
- Noch nicht in Angriff genommen, Architektur v2.4 dokumentiert

## Testbaustellen (nicht Feature-Gaps, aber offen)

Siehe `BUGFIX_CURRENT.md` fuer aktuelle Test-Failures. Die 4 groessten Baustellen nach V3.1.67-Nightly:
1. Windows-Deploy-Depth (38 WIN Failures trotz Binary-Deploy)
2. Bilateral-GUI-Receive-Regression (6 Linux, ChatScreen refresht nicht)
3. SSH-Mux-Cascade (13 Failures bei 2h-Runs)
4. gui-00 0.06 Setup-Timeout

## Erledigt (seit V3.1.26) — zur Historie siehe `docs/CHANGELOG.md`
- Reactions (V3.1.30), NFC (V3.1.29), Link Previews (V3.1.29), RTL + 33 Sprachen (V3.1.36), Manual Peer Entry (V3.1.26), Voice-Transkription (V3.1.27/V3.1.36), Calls Phase 3a-3d (V3.1.20/V3.1.21), Closed Network Model (V3.1.22), Calendar §23 komplett (V3.1.46-V3.1.65), Polls §24 (V3.1.66), Multi-Device §26 Phase 2-4 + Twin-Sync (V3.1.44-V3.1.67).

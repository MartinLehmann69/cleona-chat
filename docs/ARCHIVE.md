# Media-Archiv & Voice-Transkription

**Status: Implementiert (v2.8)** — 145 + 87 Smoke-Tests, 18 + 14 GUI-Tests, alle GRÜN.

## Übersicht

Automatische Auslagerung von Medien (Bilder, Videos, Dateien) auf einen lokalen Netzwerk-Share
und On-Device-Transkription von Sprachnachrichten. Ziel: Handy-Speicher schonen, ohne Daten
zu verlieren oder auf Cloud-Dienste angewiesen zu sein.

**Geltungsbereich:** DMs und Gruppen. Channels sind ausgenommen.

### Implementierte Komponenten

| Datei | Beschreibung |
|-------|-------------|
| `lib/core/archive/archive_config.dart` | Konfiguration (Tiers, Budget, Protokolle) |
| `lib/core/archive/archive_types.dart` | ArchiveEntry, Dateinamen-Generierung, Filterung |
| `lib/core/archive/archive_manager.dart` | Scheduler, Tier-Übergänge, Budget-Enforcement, Pin |
| `lib/core/archive/archive_transport.dart` | 4 Protokolle: SMB, SFTP, FTPS, HTTP/WebDAV |
| `lib/core/archive/archive_placeholder.dart` | Tier-spezifische Placeholder-Infos |
| `lib/core/archive/voice_transcription_config.dart` | Transkriptions-Konfiguration |
| `lib/core/archive/voice_transcription_types.dart` | VoiceTranscription Datentyp |
| `lib/core/archive/voice_transcription_service.dart` | Queue, Lifecycle, Cleanup, ffmpeg |
| `lib/core/archive/whisper_ffi.dart` | FFI-Bindings für whisper.cpp |

---

## 1. Media-Archiv

### 1.1 Konzept

Wenn sich das Gerät im konfigurierten Heim-WLAN befindet und der Netzwerk-Share erreichbar ist,
werden Medien automatisch auf den Share kopiert. Nach einer konfigurierbaren Frist werden die
Originale vom Gerät gelöscht — **niemals ohne bestätigte Archivierung**.

Im Chat sieht der User gestaffelte Platzhalter statt leerer Lücken. Ein Tap auf den Platzhalter
holt das Original bei bestehender Verbindung zurück; bei fehlender Verbindung erscheint ein
Hinweis, dass das Medium im Archiv liegt.

### 1.2 Gestaffelte Speicherung

| Stufe | Zeitraum | Auf dem Gerät | Auf dem Share |
|-------|----------|---------------|---------------|
| 1 | 0 – 30 Tage | Original | — (noch nicht archiviert) |
| 2 | 30 – 90 Tage | Thumbnail (~20–50 KB) | Original |
| 3 | 90 – 365 Tage | Mini-Thumbnail (~2–5 KB, 64px) | Original |
| 4 | > 1 Jahr | Nur Metadaten-Link (Datum, Größe, Typ-Icon) | Original |

Alle Stufen-Grenzen sind konfigurierbar. Gepinnte Medien ignorieren die Stufen komplett.

### 1.3 Pin / Behalten

- **Pro Nachricht:** Stern/Pin-Icon im 3-Punkte-Menü jeder Medien-Nachricht
- **Pro Chat:** "Medien in diesem Chat nie löschen" in den Chat-Einstellungen
- **Global:** "Nie automatisch löschen" in den Archiv-Einstellungen
- Gepinnte Medien werden trotzdem archiviert (Backup!), aber **nicht vom Gerät gelöscht**

### 1.4 Netzwerk-Erkennung

Zwei Mechanismen kombiniert:

1. **SSID-basiert:** User konfiguriert ein oder mehrere WLAN-Namen (z.B. "FritzBox7590")
   → schneller Check, ob man "zu Hause" ist
2. **Share-Erreichbarkeit:** Cleona prüft periodisch ob der Share tatsächlich erreichbar ist
   → robuster (funktioniert auch über VPN von unterwegs)

Archivierung startet nur wenn **beide** Bedingungen erfüllt sind (oder nur Share-Erreichbarkeit,
falls kein WLAN konfiguriert — z.B. bei kabelgebundenem Desktop).

### 1.5 Unterstützte Protokolle

| Protokoll | Beschreibung | Priorität |
|-----------|-------------|-----------|
| **SMB/CIFS** | Standard für NAS (Synology, QNAP, Fritz!NAS) | Pflicht |
| **SFTP** | SSH-basiert, sicher, auf Android/iOS gut machbar | Pflicht |
| **FTPS** | FTP über TLS, für ältere NAS-Systeme | Nice to have |
| **HTTP/HTTPS** | WebDAV-basiert, für eigene Server | Nice to have |

Kein plain FTP (unsicher), kein NFS (auf Mobilgeräten nicht praktikabel).

### 1.6 Verzeichnisstruktur auf dem Share

```
<Share-Root>/
  Cleona/
    <Identity-Name>/
      <Chat-Name>/
        2026-03/
          IMG_20260315_143022_a1b2c3.jpg
          VID_20260318_091500_d4e5f6.mp4
        2026-04/
          ...
```

Dateinamen enthalten einen Content-Hash-Suffix → automatische Deduplizierung wenn
mehrere Geräte/Identitäten denselben Chat archivieren.

### 1.7 Sicherheitsregeln

1. **Niemals ohne bestätigte Archivierung löschen.** Wenn der Share nicht erreichbar ist
   und die Lösch-Frist abläuft, bleibt das Original auf dem Gerät.
2. **Erinnerung:** Bei angesammelten archivierbaren Medien zeigt Cleona eine dezente
   Benachrichtigung: "Du hast X MB archivierbare Medien. Verbinde dich mit deinem
   Heim-WLAN um Speicher freizugeben."
3. **Keine Verschlüsselung auf dem Share.** Medien werden entschlüsselt abgelegt,
   damit sie auch am PC/NAS direkt anschaubar sind. Der Share befindet sich im
   eigenen Heimnetz.
4. **Erstmalige Archivierung:** Bei Aktivierung läuft ein initialer Sync im Hintergrund
   mit Fortschrittsbalken. Idealerweise über Nacht am Ladegerät.

### 1.8 Konfiguration

```
Archiv-Einstellungen (Settings-Screen):
├── Archiv aktiviert: [AN/AUS]
├── Archiv-Ziel: [SMB/SFTP/FTPS/HTTP(S)] + Adresse + Credentials
├── Heim-WLAN(s): ["FritzBox7590", ...] (mehrere möglich)
├── Stufen-Grenzen: [30/60/90 | 90/180/365 | 365/730/∞] Tage
├── Nur bei WLAN archivieren: [AN/AUS]
├── Nur bei Ladegerät: [AN/AUS] (Akkuschutz)
└── Speicher-Budget: "Max X GB Medien auf dem Gerät behalten"
```

**Speicher-Budget:** Zusätzlich zur zeitbasierten Regel. Wenn das Limit erreicht wird,
werden die ältesten ungepinnten Medien zuerst archiviert — unabhängig von der
Stufen-Konfiguration.

### 1.9 Batch-Rückholen

Statt einzeln auf jeden Platzhalter zu klicken:
- "Hole alle Medien von [Datumsbereich] zurück"
- "Hole alle Medien aus diesem Chat zurück"
- Funktioniert nur bei bestehender Share-Verbindung
- Fortschrittsbalken während des Downloads

---

## 2. Voice-Transkription

### 2.1 Konzept

Sprachnachrichten werden On-Device transkribiert (Speech-to-Text). Das Transkript wird als
Text unter der Sprachnachricht angezeigt. Nach einer konfigurierbaren Frist wird das Audio
gelöscht und nur der transkribierte Text bleibt dauerhaft erhalten.

Passt zur Cleona-Philosophie: keine Cloud, keine externen Dienste, alles lokal.

### 2.2 Voice-Lifecycle

```
Empfang der Sprachnachricht
  │
  ├── Sofort: Transkription im Hintergrund starten
  │
  ├── Phase 1: Audio + Text parallel (konfigurierbar)
  │   ├── User kann abspielen ODER lesen
  │   └── Manueller Download jederzeit möglich (→ Downloads-Ordner)
  │
  └── Phase 2: Nur noch Text (nach Ablauf der Frist)
      ├── Audio gelöscht (nicht archiviert, einfach weg)
      └── Transkription bleibt dauerhaft
```

### 2.3 Transkriptions-Engine

- **whisper.cpp** — OpenAI Whisper als C-Bibliothek, läuft vollständig On-Device
- Modell: "tiny" oder "base" (~40–75 MB), gute Qualität für Sprachnachrichten
- Unterstützte Sprachen: DE, EN, ES, HU, SV (alle Cleona-Sprachen)
- Automatische Spracherkennung oder manuelle Auswahl
- **Source-Side Transcription:** Sender transkribiert vor dem Senden, Transkript wird im VoicePayload-Protobuf mitgeschickt. Empfänger nutzt das Sender-Transkript direkt. Fallback: Empfänger transkribiert lokal falls kein Transkript vom Sender.

### 2.3.1 Native Abhängigkeiten (Runtime)

Ohne diese Abhängigkeiten funktionieren Sprachnachrichten weiterhin, aber ohne Transkriptionstext.

**Linux:**

| Abhängigkeit | Zweck | Installation |
|-------------|-------|-------------|
| `libwhisper.so` | Speech-to-Text Engine | Aus Quellcode bauen (whisper.cpp) |
| `libggml.so`, `libggml-base.so`, `libggml-cpu.so` | Tensor-Berechnung (transitive whisper-Deps) | Wird mit whisper.cpp gebaut |
| `libwhisper_wrapper.so` | Dart-FFI-Bridge (struct-by-value ABI) | `scripts/build-whisper-wrapper.sh` |
| `ffmpeg` | Audio-Konvertierung (AAC/OGG → WAV 16kHz PCM) | `sudo apt install ffmpeg` |
| GGML-Modelldatei | Trainiertes Sprachmodell | Download von Hugging Face |

Suchpfade für Libraries: System-Default, `/usr/lib/`, `/usr/local/lib/`, `$HOME/lib/`, `./build/`.
Modellpfad: `$HOME/.cleona/models/ggml-{tiny,base,small}.bin`.

Der FFI-Loader (`whisper_ffi.dart`) lädt die GGML-Abhängigkeiten vorab per `DynamicLibrary.open()`, bevor `libwhisper.so` geöffnet wird. Dadurch findet der Dynamic Linker die transitiven Dependencies auch wenn sie nicht im System-Suchpfad liegen (z.B. in `$HOME/lib/`).

**Android:** `libwhisper.so` und `libggml*.so` müssen für arm64-v8a cross-compiled und im APK gebundelt werden. ffmpeg entfällt — stattdessen Dart-seitige WAV-Extraktion oder gebundeltes `libavcodec`.

**Linux-Paketierung (deb/rpm):**
- `ffmpeg` als Paket-Abhängigkeit deklarieren
- whisper.cpp + GGML-Libraries im Paket bündeln (nicht in Distro-Repos verfügbar)
- Modelldatei (~75 MB) optional im Paket oder Post-Install-Download

### 2.4 Konfiguration

```
Sprachnachrichten-Einstellungen:
├── Auto-Transkription: [AN/AUS]
├── Audio behalten für: [7/14/30/60/90 Tage] (Default: 30)
├── "Nie löschen": [pro Nachricht (Pin) | pro Chat | global]
└── Transkriptions-Sprache: [Auto | DE | EN | ES | HU | SV]
```

### 2.5 Anzeige im Chat

```
┌──────────────────────────────────┐
│ 🎤 0:47  ▶ ━━━━━━━━━━━━━━━━━━━  │  ← Audio-Player (Phase 1)
│                                  │
│ "Hey, ich wollte nur sagen dass  │  ← Transkription (immer sichtbar)
│  wir uns morgen um 3 treffen.    │
│  Bring bitte die Unterlagen mit."│
└──────────────────────────────────┘

Nach Ablauf der Frist:

┌──────────────────────────────────┐
│ 🎤 Transkription (Audio gelöscht)│  ← Header
│                                  │
│ "Hey, ich wollte nur sagen dass  │  ← Text bleibt
│  wir uns morgen um 3 treffen.    │
│  Bring bitte die Unterlagen mit."│
└──────────────────────────────────┘
```

### 2.6 Eigenständig nutzbar

Die Transkription funktioniert auch **ohne** aktiviertes Media-Archiv. Das sind zwei
unabhängige Features:
- Archiv = Medien auf NAS auslagern
- Transkription = Sprachnachrichten in Text umwandeln

Beides kann einzeln oder zusammen aktiviert werden.

---

## 3. Geplante Modulstruktur

```
lib/core/archive/
├── archive_config.dart       # Einstellungen (Share, WLAN, Stufen, Budget)
├── archive_manager.dart      # Scheduling, Share-Erkennung, Archivierungs-Loop
├── archive_transport.dart    # SMB/SFTP/FTPS/HTTP-Client Abstraktion
├── archive_placeholder.dart  # Thumbnail/Mini/Link Platzhalter-Logik
└── voice_transcription.dart  # whisper.cpp FFI Binding, Transkriptions-Queue

lib/ui/screens/
├── archive_settings_screen.dart  # Konfiguration
└── archive_browser_screen.dart   # Batch-Rückholen nach Datum/Chat
```

---

## 4. Zusammenfassung

| Aspekt | Media-Archiv | Voice-Transkription |
|--------|-------------|---------------------|
| Zweck | Speicher sparen | Inhalt bewahren, Durchsuchbarkeit |
| Ziel | Lokaler NAS/Share | On-Device |
| Protokolle | SMB, SFTP, FTPS, HTTP(S) | — (lokal) |
| Engine | — | whisper.cpp (On-Device) |
| Löschung | Gestaffelt (Thumbnail → Mini → Link) | Audio nach Frist, Text bleibt |
| Pin | Ja (Nachricht/Chat/Global) | Ja (Audio nie löschen) |
| Geltungsbereich | DMs + Gruppen | DMs + Gruppen |
| Cloud nötig | Nein | Nein |

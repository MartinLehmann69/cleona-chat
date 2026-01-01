# Cleona on macOS — Build Guide / Bauanleitung

*Version: v1 port, 2026-04-18. Status: Dart-Code + `macos/`-Scaffold + Build-Scripts vorbereitet, aber noch nie auf echtem Mac ausgeführt. Der erste macOS-Build dient zugleich als Akzeptanztest dieser Anleitung.*

---

## Deutsch

### Voraussetzungen

- macOS 11 Big Sur oder neuer (Apple Silicon empfohlen, Intel unterstützt)
- [Xcode](https://apps.apple.com/de/app/xcode/id497799835) (Command Line Tools reichen **nicht** — das vollständige Xcode wird für `xcodebuild` und die macOS-SDK benötigt)
  ```bash
  xcode-select --install                # optional, wenn nur CLI-Tools aktuell
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  sudo xcodebuild -license accept
  ```
- [Homebrew](https://brew.sh/)
- [Flutter 3.41+](https://docs.flutter.dev/get-started/install/macos) (Stable-Channel)
  ```bash
  flutter config --enable-macos-desktop
  flutter doctor        # alle Zeilen bis auf Android-ggf. grün
  ```
- Build-Abhängigkeiten:
  ```bash
  brew install cmake ninja autoconf automake libtool pkg-config git libvpx
  ```

### Schritt 1 — Native Libraries bauen

```bash
cd /pfad/zu/Cleona
./scripts/build-macos-libs.sh --arch arm64       # Apple Silicon
# oder
./scripts/build-macos-libs.sh --arch x86_64      # Intel
# oder
./scripts/build-macos-libs.sh --arch universal   # beide + lipo merge
```

Das Script baut `libsodium`, `liboqs`, `libzstd`, `liberasurecode`, `libopus` und `whisper.cpp` (mit Metal-Beschleunigung auf arm64) sowie den VPX-Shim als Dylib nach `build/macos-libs/<arch>/`. Alle Dylibs werden auf `@rpath/` umgeschrieben und ad-hoc signiert.

Dauer beim ersten Lauf: ~15–25 Minuten (alle Repos werden geklont + gebaut).

**Schneller Dev-Shortcut** (ohne Source-Build, nutzt Homebrew-Libs für libsodium/libzstd/libopus — liboqs/liberasurecode/whisper bleiben außen vor):

```bash
brew install libsodium zstd opus
./scripts/build-macos-libs.sh --arch arm64 --use-homebrew
```

### Schritt 2 — App bauen und deployen

```bash
./scripts/deploy-macos-app.sh --arch arm64
```

Das Script:
1. Kompiliert den Headless-Daemon (`dart compile exe lib/service_daemon.dart`)
2. Baut die Flutter-GUI (`flutter build macos --release`)
3. Kopiert alle Dylibs aus `build/macos-libs/arm64/` nach `Cleona.app/Contents/Frameworks/`
4. Legt den Daemon-Binary nach `Cleona.app/Contents/MacOS/cleona-daemon`
5. Ad-hoc-Signiert das Bundle (`codesign --deep --force --sign -`) — reicht für lokale Nutzung, **nicht für Distribution**

Für einen Debug-Build: `--debug` statt `--release` anhängen.

### Schritt 3 — Erster Start

```bash
open build/macos/Build/Products/Release/Cleona.app
```

Beim ersten Start:
- **macOS-Gatekeeper**: Warnt, dass Cleona von einem nicht-identifizierten Entwickler stammt. Rechtsklick auf die App → "Öffnen" → "Öffnen" bestätigen. Nur beim ersten Start nötig.
- **Lokales-Netzwerk-Prompt** (macOS 14 Sonoma+): „Cleona möchte in deinem lokalen Netzwerk nach Geräten suchen" — **muss bestätigt werden**, sonst funktioniert P2P-Discovery (Broadcast + Multicast) nicht.
- Cleona legt das Profil unter `~/.cleona/` an (gleicher Ort wie auf Linux).

### Was in v1 NICHT funktioniert

- **System-Tray / Menüleiste** — der Daemon hat keinen FlutterEngine, darum kein MethodChannel; NSStatusItem via reine Cocoa-FFI-Bridge ist für v2 geplant.
- **Voice-Calls** — PulseAudio-basiert auf Linux, CoreAudio-Port steht aus.
- **Video-Calls** — V4L2-basiert auf Linux, AVFoundation-Port steht aus.
- **App-Store-Distribution** — braucht Apple-Developer-Cert, Sandbox, und Profil-Pfad-Migration nach `~/Library/Containers/…`. Bewusst für später.

### Fehlersuche

**„Couldn't find framework `liboqs.dylib`"** beim App-Start
→ Dylibs wurden nicht nach `Contents/Frameworks/` kopiert oder `@rpath` ist nicht gesetzt. Prüfen: `otool -L Cleona.app/Contents/MacOS/Cleona | grep dylib`.

**Daemon startet, aber GUI findet ihn nicht**
→ `~/.cleona/cleona.sock` prüfen. Daemon-Log: `~/.cleona/daemon.log`. Manuell starten zum Debuggen: `Cleona.app/Contents/MacOS/cleona-daemon --base-dir ~/.cleona --port 4443`.

**Kein Peer-Discovery**
→ Local-Network-Permission in Systemeinstellungen → Datenschutz → Lokales Netzwerk prüfen. Bei Bedarf Haken rausnehmen und wieder rein.

**Build-Script-Fehler `ld: library 'vpx' not found`**
→ `brew install libvpx`.

### Universal Binaries (Intel + Apple Silicon)

```bash
./scripts/build-macos-libs.sh --arch universal
./scripts/deploy-macos-app.sh --arch universal
```

Baut alle Dylibs für arm64 und x86_64 separat und merged sie per `lipo` zu Universal-Binaries. Bundle-Größe wächst um ca. 40 %.

### Signierung für Distribution

Wenn du die App verteilen willst (nicht nur lokal nutzen), brauchst du:

1. Apple Developer Program Mitgliedschaft (99 USD/Jahr)
2. Ein Developer-ID-Application-Zertifikat in der Schlüsselbundverwaltung
3. Ersetze in `deploy-macos-app.sh` den `--sign -` (ad-hoc) durch `--sign "Developer ID Application: Dein Name (TEAMID)"`
4. Notarisierung:
   ```bash
   xcrun notarytool submit Cleona.app.zip \
     --apple-id deine@apple.id --team-id TEAMID --wait
   xcrun stapler staple Cleona.app
   ```

---

## English

### Prerequisites

- macOS 11 Big Sur or newer (Apple Silicon recommended, Intel supported)
- [Xcode](https://apps.apple.com/app/xcode/id497799835) (Command Line Tools alone are **not** enough — full Xcode required for `xcodebuild` and the macOS SDK)
  ```bash
  xcode-select --install                # optional if CLI tools already current
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  sudo xcodebuild -license accept
  ```
- [Homebrew](https://brew.sh/)
- [Flutter 3.41+](https://docs.flutter.dev/get-started/install/macos) (stable channel)
  ```bash
  flutter config --enable-macos-desktop
  flutter doctor        # all rows green except maybe Android
  ```
- Build dependencies:
  ```bash
  brew install cmake ninja autoconf automake libtool pkg-config git libvpx
  ```

### Step 1 — Build native libraries

```bash
cd /path/to/Cleona
./scripts/build-macos-libs.sh --arch arm64       # Apple Silicon
# or
./scripts/build-macos-libs.sh --arch x86_64      # Intel
# or
./scripts/build-macos-libs.sh --arch universal   # both + lipo merge
```

The script builds `libsodium`, `liboqs`, `libzstd`, `liberasurecode`, `libopus` and `whisper.cpp` (with Metal acceleration on arm64), plus the VPX shim, as dylibs in `build/macos-libs/<arch>/`. All dylibs have their install names rewritten to `@rpath/` and are ad-hoc signed.

First run takes ~15–25 minutes (all source repos are cloned + built).

**Dev shortcut** (skips source builds, uses Homebrew for libsodium/libzstd/libopus — liboqs/liberasurecode/whisper remain source-only):

```bash
brew install libsodium zstd opus
./scripts/build-macos-libs.sh --arch arm64 --use-homebrew
```

### Step 2 — Build and deploy the app

```bash
./scripts/deploy-macos-app.sh --arch arm64
```

The script:
1. Compiles the headless daemon (`dart compile exe lib/service_daemon.dart`)
2. Builds the Flutter GUI (`flutter build macos --release`)
3. Copies all dylibs from `build/macos-libs/arm64/` into `Cleona.app/Contents/Frameworks/`
4. Drops the daemon binary into `Cleona.app/Contents/MacOS/cleona-daemon`
5. Ad-hoc signs the bundle (`codesign --deep --force --sign -`) — enough for local use, **not for distribution**.

For a debug build: append `--debug` instead of `--release`.

### Step 3 — First launch

```bash
open build/macos/Build/Products/Release/Cleona.app
```

On first launch:
- **macOS Gatekeeper**: warns that Cleona comes from an unidentified developer. Right-click the app → "Open" → confirm "Open". Only needed once.
- **Local-Network prompt** (macOS 14 Sonoma+): "Cleona wants to find devices on your local network" — **must be accepted**, otherwise P2P discovery (broadcast + multicast) won't work.
- Cleona creates its profile under `~/.cleona/` (same location as on Linux).

### What does NOT work in v1

- **System tray / menu bar** — the daemon has no FlutterEngine, hence no MethodChannel; an NSStatusItem via pure Cocoa FFI bridge is planned for v2.
- **Voice calls** — PulseAudio-based on Linux; a CoreAudio port is pending.
- **Video calls** — V4L2-based on Linux; an AVFoundation port is pending.
- **App Store distribution** — requires Apple Developer cert, sandbox, and profile-path migration to `~/Library/Containers/…`. Deliberately deferred.

### Troubleshooting

**"Couldn't find framework `liboqs.dylib`"** at launch
→ Dylibs weren't copied to `Contents/Frameworks/`, or `@rpath` isn't set. Check: `otool -L Cleona.app/Contents/MacOS/Cleona | grep dylib`.

**Daemon starts but GUI can't find it**
→ Check `~/.cleona/cleona.sock`. Daemon log: `~/.cleona/daemon.log`. Start manually to debug: `Cleona.app/Contents/MacOS/cleona-daemon --base-dir ~/.cleona --port 4443`.

**No peer discovery**
→ Check local network permission in System Settings → Privacy → Local Network. If needed, toggle off and on again.

**Build-script error `ld: library 'vpx' not found`**
→ `brew install libvpx`.

### Universal binaries (Intel + Apple Silicon)

```bash
./scripts/build-macos-libs.sh --arch universal
./scripts/deploy-macos-app.sh --arch universal
```

Builds every dylib for both arm64 and x86_64 and merges them into universal binaries via `lipo`. Bundle size grows by ~40%.

### Signing for distribution

If you want to ship the app (not just use it locally), you need:

1. Apple Developer Program membership (USD 99/year)
2. A Developer ID Application certificate in Keychain
3. Replace `--sign -` (ad-hoc) in `deploy-macos-app.sh` with `--sign "Developer ID Application: Your Name (TEAMID)"`
4. Notarize:
   ```bash
   xcrun notarytool submit Cleona.app.zip \
     --apple-id your@apple.id --team-id TEAMID --wait
   xcrun stapler staple Cleona.app
   ```

# Cleona Chat — Publishing & GitHub Strategie

Dieses Dokument beschreibt die Strategie fuer die Veroeffentlichung von Cleona Chat
auf GitHub, einschliesslich Lizenzierung, Ordnerstruktur und Release-Prozess.

## Verzeichnisstruktur

```
/home/claude/
├── Cleona/          ← Arbeitsverzeichnis (vollstaendige Entwicklungsumgebung)
├── CleonaPrivat/    ← Private Keys, Secrets, interne Dokumentation
└── CleonaGit/       ← Bereinigte Prestage-Version fuer GitHub
```

### Cleona/ (Arbeitsverzeichnis)
Enthält alles: Quellcode, Tests, VM-Scripts, interne Docs, Build-Konfigurationen.
Wird NICHT direkt auf GitHub gepusht.

### CleonaPrivat/ (Vertraulich)
Enthält Private Keys, Passwoerter, interne Dokumentation.
Wird NIEMALS versioniert oder veroeffentlicht.
Siehe `CleonaPrivat/README.md` fuer Details.

### CleonaGit/ (Prestage fuer GitHub)
Bereinigte Kopie — nur was oeffentlich sein darf.
Wird per `scripts/sync-to-git.sh` aus Cleona/ synchronisiert.

## Lizenz: Source Available

Entscheidung dokumentiert in Architektur-Dokument §16.1.

**Erlaubt:**
- Quellcode lesen und studieren
- Kryptografische Implementierung auditieren
- Bug Reports und Feature Requests einreichen
- Aus Source fuer persoenlichen Gebrauch bauen

**Nicht erlaubt:**
- Redistribution oder veroeffentlichte Forks
- Kommerzielle Nutzung
- Verwendung des Namens "Cleona Chat" oder des Logos

**Schutzebenen:**
1. Custom Source Available License (rechtlich)
2. Trademark auf "Cleona Chat" + Logo (markenrechtlich)
3. Closed Network Model — Forks ohne Network Secret sind isoliert (technisch)

**Konsequenz:** F-Droid ist nicht moeglich (erfordert OSS-Lizenz).

## Was wird veroeffentlicht

### Quellcode (via sync-to-git.sh)
- `lib/` — Dart-Quellcode (ohne headless.dart)
- `proto/` — Protobuf-Definitionen
- `assets/` — Nur cleona_maintainer_public.pem (Public Key)
- `pubspec.yaml` — Dependencies
- `android/`, `linux/`, `windows/` — Plattform-Shells (ohne key.properties, keystore)

### Dokumente (separat gepflegt in CleonaGit/)
- `README.md` — Projektbeschreibung, Features, Screenshots
- `LICENSE` — Source Available Custom License
- `SECURITY.md` — Responsible Disclosure Policy
- `CHANGELOG.md` — Bereinigt (Versionen + Features, ohne Daten)
- `docs/ARCHITECTURE.md` — Oeffentliche Architektur (bereinigt: keine IPs, Passwoerter, Schwellwerte)
- `docs/SECURITY_WHITEPAPER.md` — Crypto-Design fuer Auditoren
- `manual/de/BENUTZERHANDBUCH.md` — Nutzerhandbuch Deutsch
- `manual/en/USER_MANUAL.md` — User Manual English
- `manual/` — Weitere Sprachen bei Bedarf

### Release-Artifacts (signiert, als GitHub Releases)
- Linux: `cleona-chat-X.Y.Z-x86_64.AppImage` + `.sig`
- Linux: `cleona-chat_X.Y.Z_amd64.deb` + `.sig`
- Linux: `cleona-chat-X.Y.Z.x86_64.rpm` + `.sig`
- Windows: `cleona-chat-X.Y.Z-windows-setup.exe` + `.sig`
- Android: `cleona-chat-X.Y.Z.apk` + `.sig`
- `SHA256SUMS` + `.sig`

### Linux-Paketierung
Build-Script: `Cleona/scripts/build-linux-packages.sh`
Erzeugt aus dem Flutter-Linux-Bundle drei Formate:
- **AppImage** — Universell, keine Installation, kein Root. Nutzt `appimagetool`.
- **.deb** — Fuer Debian/Ubuntu/Mint. Installiert nach `/opt/cleona/`, Wrapper in `/usr/bin/`.
- **.rpm** — Fuer Fedora/openSUSE/RHEL. Gleiche Struktur wie .deb.

Signaturen mit Ed25519 Maintainer-Key. Verifikation mit dem in assets/ eingebetteten Public Key.

## Was wird NICHT veroeffentlicht

| Kategorie | Dateien | Grund |
|-----------|---------|-------|
| Private Keys | `cleona_maintainer_private.pem`, `upload-keystore.jks`, `key.properties` | Kryptografische Sicherheit |
| Interne Docs | `CLAUDE.md`, `HANDOVER.md`, `BUGFIX_*.md` | Enthalten IPs, Passwoerter, Infra-Details |
| Test-Infrastruktur | `test/`, `tests/`, `scripts/vm/`, `scripts/jury-swarm.sh` | Enthalten echte IPs, VM-Passwoerter, Netzwerk-Topologie |
| Internes Tooling | `lib/headless.dart`, `scripts/init_profile.dart` | Test/Setup-Tools, nicht fuer Endnutzer |
| Alte Architektur | `v2.0.md`, `v2.1.md` | Veraltet, in CleonaPrivat/ archiviert |
| Debug-Builds | Alles mit Debug-Flags | Logging, Assertions, Performance-Overhead |

## Commit-Daten Neutralisierung

Entwicklungstimeline soll nicht sichtbar sein auf GitHub.

**Initialer Push:** Squash aller Historie in einen Commit mit neutralem Datum.

**Kuenftige Pushes:** Commit-Daten vor Push neutralisieren:
```bash
GIT_AUTHOR_DATE="2026-01-01T12:00:00+00:00" \
GIT_COMMITTER_DATE="2026-01-01T12:00:00+00:00" \
git commit -m "Commit message"
```

**Push-Datum:** Von GitHub serverseitig gesetzt — nicht kontrollierbar, aber akzeptiert.
Der Zeitpunkt des Pushes verraet nicht die Entwicklungstimeline.

## Reproducible Builds

Nutzer koennen verifizieren dass das offizielle Binary exakt dem Source entspricht:

1. Nutzer baut aus Source → unsigniertes Binary
2. Nutzer streift Signatur vom offiziellen Binary ab
3. Vergleich → muss Byte-fuer-Byte identisch sein

Die Signatur (Ed25519) beweist separat: "Dieses Binary kommt vom Maintainer."
Der Private Key wird NICHT benoetigt — nur der Public Key fuer Verifikation.

## Distribution

| Kanal | Status | Anmerkung |
|-------|--------|-----------|
| GitHub Releases | Geplant | Tarballs + signierte Binaries |
| Google Play | Geplant | Von Maintainer signierte APK |
| Eigene Website | Geplant | Download + Signatur-Verifikation |
| F-Droid | Nicht moeglich | Source Available ist keine OSS-Lizenz |

## Sync-Workflow

```bash
# 1. Aenderungen in Cleona/ entwickeln und testen
# 2. Sync ausfuehren
cd /home/claude/Cleona
./scripts/sync-to-git.sh

# 3. Ergebnis pruefen
cd /home/claude/CleonaGit
git diff

# 4. Committen mit neutralem Datum
GIT_AUTHOR_DATE="2026-01-01T12:00:00+00:00" \
GIT_COMMITTER_DATE="2026-01-01T12:00:00+00:00" \
git commit -m "Release vX.Y.Z"

# 5. Pushen (NUR nach manueller Pruefung!)
git push
```

## GitHub Repository Erstellen

1. https://github.com/new aufrufen
2. Repository name: `cleona-chat` (oder `Cleona`)
3. Visibility: **Public**
4. KEIN README, KEINE License, KEIN .gitignore (kommt alles von uns)
5. "Create repository"
6. Im CleonaGit-Verzeichnis:
   ```bash
   cd /home/claude/CleonaGit
   git init
   git remote add origin git@github.com:USERNAME/cleona-chat.git
   ```

## Noch zu erstellen

- [ ] LICENSE (Source Available Custom License Text)
- [ ] README.md (Projektbeschreibung + Screenshots)
- [ ] SECURITY.md (Responsible Disclosure)
- [ ] CHANGELOG.md (bereinigt)
- [ ] docs/ARCHITECTURE.md (oeffentliche Version)
- [ ] docs/SECURITY_WHITEPAPER.md
- [ ] manual/ (Nutzerhandbuch, 33 Sprachen)
- [ ] .gitignore fuer CleonaGit/
- [ ] Reproducible Build Anleitung

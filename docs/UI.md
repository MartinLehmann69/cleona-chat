# Cleona — UI Architecture

## Service/GUI Trennung
- **Background Service (Daemon):** Networking, DHT, Crypto, Storage, Relay — läuft ohne GUI
- **Flutter GUI:** Verbindet sich zum lokalen Service per IPC (Unix Domain Socket), kann unabhängig geöffnet/geschlossen werden

## Navigation (6 Tabs)
| Tab | Inhalt | FAB |
|-----|--------|-----|
| Recent | Alle Conversations, sortiert nach letzter Nachricht | Add Contact |
| Favorites | Nur favorisierte Conversations | — |
| Chats | Nur 1:1 DMs | Add Contact |
| Groups | Nur Gruppen | New Group |
| Channels | Nur Private Channels | New Channel |
| Inbox | Pending Contact Requests + akzeptierte Kontaktliste | — |

- FAB kontextabhängig pro Tab (s.o.)
- Unread Badges auf jedem Tab
- Inbox: Kontaktanfragen (Annehmen/Ablehnen) + Kontaktliste mit Lösch-Option

## AppBar
- Titel: "Cleona — {Identity Name}"
- Actions: Netzwerk-Status-Chip (Peer-Anzahl, grün/rot), Settings-Zahnrad
- Identity Tabs (horizontal scrollbar): Active hervorgehoben mit Primary-Border, Tap zum Wechseln, Tap auf aktive → öffnet Identity Detail Screen, "+" für neue Identity

## Identity Detail Screen (Fullscreen, geplant v2.6)
Eigener Fullscreen-Screen pro Identity. Auslöser: Tap auf den bereits aktiven Identity-Tab.

**Layout (scrollbar, von oben nach unten):**
1. **QR-Code** — groß und prominent (ContactSeed der aktiven Identity)
2. **Profilbild** — aktuelles Bild + Ändern/Entfernen (Kamera + Galerie)
3. **Beschreibung** — Textfeld für Profiltext der Identity
4. **Umbenennen** — Display-Name ändern (löst PROFILE_UPDATE Broadcast aus)
5. **Skin wählen** — Skin-Auswahl für diese Identity (9 Skins)
6. **Identity löschen** — mit Bestätigungsdialog
7. **"Ich bin über 18" Toggle** — ganz unten, erst durch Scrollen sichtbar, standardmäßig AUS

Ersetzt alle identity-spezifischen Einstellungen aus dem Settings Screen.

## Settings Screen (eigene Route, nur App-weite Einstellungen)
- **Darstellung:** Theme (Light/System/Dark)
- **Sprache:** Flaggen-Selector (DE/EN/ES/HU/SV)
- **Sicherheit:** Seed-Phrase Backup, Guardian Recovery
- **Netzwerk:** Node-ID, Port, Peers, Fragmente
- **Info:** Version, Verschlüsselung, Netzwerk-Tag

## Conversation List
- CircleAvatar: Profilbild (MemoryImage) oder Initial-Fallback, Gruppen: Gruppen-Icon
- Letzte Nachricht Preview (gelöschte kursiv, Medien mit 📎-Prefix)
- Zeitstempel + Unread-Badge (farbig, rechts)
- **Gruppen:** Drei-Punkte-Menü (⋮) mit Gruppeninfo + Verlassen

## Gruppeninfo-Dialog
- Mitgliederliste mit rollenspezifischen Icons: ★ Owner (amber), 🛡 Admin (primary), 👤 Mitglied
- **Owner sieht:** Drei-Punkte-Menü pro Mitglied (Zum Admin machen, Zum Mitglied machen, Ownership übertragen, Entfernen)
- **Admin sieht:** Entfernen-Option
- **Member sieht:** Nur Liste
- "Einladen"-Button: Zeigt Kontakte die noch nicht in der Gruppe sind
- "Verlassen"-Button mit Bestätigungsdialog

## Gruppen-Rollen & Berechtigungen
| Aktion | Owner | Admin | Member |
|--------|-------|-------|--------|
| Nachrichten senden | ✓ | ✓ | ✓ |
| Mitglieder einladen | ✓ | ✓ | ✗ |
| Mitglieder entfernen | ✓ | ✓ | ✗ |
| Rollen ändern | ✓ | ✗ | ✗ |
| Gruppenconfig ändern | ✓ | ✗ | ✗ |

## Kontakt umbenennen (Lokaler Alias)
- **3-Punkte-Menü** bei DM-Konversationen und in der Kontaktliste: "Kontakt umbenennen"
- **Dialog:** Zeigt Originalnamen des Kontakts, Textfeld für lokalen Alias. Leer = Alias entfernen.
- **Anzeige:** `effectiveName` = localAlias ?? displayName. Bei gesetztem Alias wird der Originalname in Klammern kursiv angezeigt.
- **Name-Change-Banner:** Wenn ein Kontakt mit lokalem Alias sich selbst umbenennt, erscheint ein Banner: "X hat sich in Y umbenannt. Übernehmen?" mit Buttons "Übernehmen" / "Alias behalten".
- **Persistierung:** `localAlias` und `pendingNameChange` in `contacts.json`, über IPC synchronisiert.
- **IPC:** `rename_contact`, `accept_name_change` Commands.

## Sende-Performance (Optimistic UI)
- **Fire-and-Forget:** `_send()` blockiert die UI nicht — Nachricht erscheint sofort mit Sanduhr-Icon (Status `sending`).
- **PoW im Isolate:** Proof-of-Work Berechnung (1M SHA-256 Hashes) läuft in separatem Dart-Isolate (`ProofOfWork.computeAsync`).
- **Status-Updates:** `sending` → `sent`/`queued` nach Abschluss von Crypto + Netzwerk.
- **SafeArea:** Android-Systemleiste verdeckt das Eingabefeld nicht (SafeArea mit `top: false`).

## Message Bubbles
- Eigene: rechts, primaryContainer. Peer: links, surfaceContainerHighest.
- Status: ⏳ sending, 🕐 queued, ✓ sent, ☁ storedInNetwork, ✓✓ delivered, ✓✓ read
- **Bearbeitet:** "bearbeitet" kursiv neben Zeitstempel
- **Gelöscht:** "Nachricht gelöscht" kursiv mit Block-Icon
- **Gruppen:** Absendername (primary, bold, 11pt) über der Nachricht
- **System-Nachrichten:** Zentriert, kursiv, outline-Farbe (z.B. "Bob hat die Gruppe verlassen")
- **Bilder:** Inline-Preview (max 200px), Thumbnail bei Announcement
- **Dateien:** Icon (nach MIME) + Filename + Größe
- **Download-Button:** Bei MEDIA_ANNOUNCEMENT (Two-Stage)
- Drei-Punkte-Menü (PopupMenuButton ⋮ oben rechts): Bearbeiten (innerhalb 15 Min), Löschen

## Media-Nachrichten Kontextmenü
- **Speichern:** Kopiert Datei nach `~/Downloads` (Linux) / `/storage/emulated/0/Download` (Android), SnackBar mit Pfad
- **In Zwischenablage:** Linux: `wl-copy` (Wayland) / `xclip` (X11) mit MIME-Type. Android: Dateipfad als Text.
- **Weiterleiten:** Media wird als echtes IMAGE/FILE re-sent (nicht als Text). Nutzt `sendMediaMessage()` mit Original-`filePath`.
- Nur sichtbar wenn Chat-Config `allowDownloads` erlaubt und Nachricht Media hat (`isMedia && filePath != null`).

## Chat Input Area
- **Edit-Modus:** Banner "Nachricht bearbeiten" mit Abbrechen-X, Check-Button statt Send
- **Anhang-Button:** 📎 links vom Textfeld, öffnet file_picker
- **Send-Button:** IconButton.filled rechts

## Profilbilder
- Max 64KB nach Komprimierung
- Auto-Resize: >64KB → ImageMagick convert (200x200, JPEG q75, Fallback 128x128 q50)
- Kamera-Capture: fswebcam (Linux), Fallback mit Fehlermeldung
- In CR/CR-Response eingebettet, PROFILE_UPDATE Broadcast an alle Kontakte
- Conversation-Liste: Sync aus Kontakt-Profilbildern in Conversation.profilePictureBase64

## Media Transfer (Two-Stage)
- **Inline (<256KB):** Direkt als IMAGE/FILE gesendet, sofort angezeigt
- **Two-Stage (>256KB):** MEDIA_ANNOUNCEMENT (Metadata + Thumbnail) → User klickt Download → MEDIA_ACCEPT → Sender sendet Content
- Empfangene Dateien gespeichert in `$profileDir/media/`

## Clipboard (Linux)
- `ClipboardHelper`: Erkennt wl-paste (Wayland) / xclip (X11)
- Ctrl+V: Text → normaler Paste, Binary → Confirmation Dialog mit Preview
- Paste-Button in Input Area
- Benötigt: `wl-clipboard` oder `xclip` installiert

## Connection Status Icon (V3.1.46)
AppBar-Mascot zwischen Sprach-Flagge und Netzwerk-Statistik:
- **WiFi**: Gruenes Icon — Verbindung ueber WLAN/Ethernet
- **Mobil**: Gelbes Icon — Verbindung ueber Mobilfunk
- **Offline**: Weisses Icon — Keine Netzwerkverbindung
- `connectivity_plus` liefert den Zustand, Tooltip in 33 Sprachen

## Kalender-Screen (V3.1.46, §23)
Navigation: Kalender-Icon in der Home-Screen AppBar.

### 4 Ansichten
- **Tagesansicht**: Stundenraster mit Events
- **Wochenansicht**: 7-Tage-Grid mit Stundenraster
- **Monatsansicht**: Kalender-Grid mit Tages-Nummern (Standard)
- **Jahresansicht**: 12-Monats-Uebersicht
- View-Switcher: PopupMenu in der AppBar

### Event-Editor
- Titel, Kategorie (5 Typen), Ganztaegig-Toggle
- Beginn/Ende mit Datum- und Zeitpicker
- Ort, Beschreibung
- Wiederholung (RFC 5545 RRULE)
- Erinnerungen (15min/30min/1h/1d vorher)
- Gruppentermin mit Gruppen-Auswahl
- Sichtbarkeit (Voll/Nur Zeiten/Versteckt)
- Speichern/Loeschen in AppBar

### Chat-Integration
- CalendarEventCard in Chat-Bubbles bei CALENDAR_INVITE
- RSVP-Buttons: Zusagen/Ablehnen/Vielleicht/Neuen Zeitpunkt vorschlagen
- Kalender-Events per Pairwise Fan-out an Gruppenmitglieder

### Import/Export
- iCal Import/Export (RFC 5545: VCALENDAR/VEVENT/VTODO/VALARM)
- PDF-Druck aller 4 Views (A4/Landscape, System-Druckdialog)
- Menue ueber Drei-Punkte-Button in der AppBar

## Daten-Chain
UiMessage (filePath, mimeType, thumbnailBase64, mediaState) → Conversation (+ profilePictureBase64, isGroup) → ChatScreen → MessageBubble

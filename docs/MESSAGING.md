# Cleona — Messaging & Delivery

## Erasure Coding
- Reed-Solomon: N=10 Fragmente, K=7 zum Rekonstruieren
- Overhead: 1.43x
- Fragmente verteilt auf Peers nahe der Empfänger-Mailbox (XOR-Distanz)
- Max 5 Kopien pro Fragment
- Kleine Netze (3-5 Nodes): Round-Robin-Verteilung, Sender behält alle Fragmente bis DELIVERED

## Message Status Lifecycle
```
QUEUED → SENT → STORED_IN_NETWORK → DELIVERED → READ
```
- QUEUED: In SendQueue, kein Peer erreichbar (persistiert auf Disk)
- SENT: Fragmente dispatched, ACKs pending
- STORED_IN_NETWORK: ≥N ACKs, Message rekonstruierbar
- DELIVERED: Empfänger hat reassembled (DELIVERY_RECEIPT)
- READ: Empfänger hat gesehen (READ_RECEIPT, optional)

## Mailbox: Push-First
- Relay Nodes forwarden Fragmente sofort an Mailbox-Owner (< 1s)
- Polling nur bei Startup (5s Delay) und nach Restore
- Startup-Poll: An ALLE recently-confirmed Peers (< 10min), nicht nur K closest
- Fragment Aging: Incomplete Sets (< K) nach 10 Min evicted
- Cleanup: FRAGMENT_DELETE an alle Relay Peers nach Rekonstruktion

## Two-Stage Media Delivery
1. **Inline (<256KB):** Direkt als IMAGE/FILE Typ gesendet, Per-Message KEM verschlüsselt, sofort angezeigt
2. **Two-Stage (>256KB):** MEDIA_ANNOUNCEMENT (Metadata: Filename, Size, MIME, Thumbnail, Hash) → Empfänger klickt Download → MEDIA_ACCEPT → Sender sendet verschlüsselten Content
- Empfangene Dateien gespeichert in `$profileDir/media/`
- Auto-Download konfigurierbar pro Medientyp (Images 10MB, Videos 50MB, Files 25MB, Voice 5MB)

## Relay Storage
- Budget dynamisch nach verfügbarem Speicher
- TTL: 7-14 Tage
- Persistiert als JSON in `<profileDir>/mailbox/`, batched writes alle 2s
- Proactive Push: Relay kennt Mailbox-Owner via PK→Mailbox-Mapping
- WICHTIG: Forwarded envelope nutzt Relay's eigene senderId (nicht Original-Sender)

## Per-Chat Policies
| Setting | Default | Scope |
|---------|---------|-------|
| allow_downloads | true | Dateien speicherbar? |
| allow_forwarding | true | Weiterleiten erlaubt? |
| expiry_duration_ms | null (aus) | Auto-Delete nach Read |
| edit_window_ms | 3600000 (1h) | Editier-Zeitfenster (null = unlimitiert) |
| read_receipts | true | Lesebestätigungen |
| typing_indicators | true | Tipp-Anzeige |

## Config-Änderungen
- **DM:** Vorschlag via CHAT_CONFIG_UPDATE (type 100) → Partner bestätigt/lehnt ab via CHAT_CONFIG_RESPONSE (type 101). Config wird erst nach Bestätigung beider Seiten aktiv.
- **Gruppen:** Owner ODER Admin setzt Config. Änderung wird an alle Mitglieder per CHAT_CONFIG_UPDATE (pairwise) gesendet. Keine Bestätigung nötig — Mitglieder übernehmen direkt.
- **Channels:** Wie Gruppen (Owner/Admin setzt, Subscriber werden benachrichtigt).

## Enforcement
- **allow_downloads:** GUI blockiert Speichern/Download-Button, Backend lehnt `acceptMediaDownload` ab
- **allow_forwarding:** GUI blendet Weiterleiten-Option aus, Backend lehnt `forwardMessage` ab
- **expiry_duration_ms:** Timer startet nach READ (READ_RECEIPT), nicht nach Send. Nachricht wird nach Ablauf lokal gelöscht + DELETE an Peers. Änderungen gelten nur für zukünftige Nachrichten.
- **edit_window_ms:** Dual-Enforcement: Sender + Empfänger prüfen Zeitfenster

## Message Editing
- Nur Original-Autor, innerhalb edit_window_ms (Default: 1 Stunde)
- Dual-Enforcement: Client + Empfänger prüfen Zeitfenster
- Kein Edit-History (Data Minimization)
- MESSAGE_EDIT Typ: original_message_id + new_text + edit_timestamp, Per-Message KEM verschlüsselt

## Message Deletion
- Nur Original-Autor, kein Zeitlimit
- MESSAGE_DELETE Typ: message_id + deleted_at, Per-Message KEM verschlüsselt
- Lokal: text wird geleert, isDeleted=true (Platzhalter bleibt)

## Gruppen-Nachrichten
- **Pairwise Fan-out:** Jede Gruppennachricht wird einzeln an jedes Mitglied verschlüsselt (Per-Message KEM)
- **Kein Gruppenkey:** Kein shared secret, maximale Forward Secrecy
- **group_id Feld (19)** im MessageEnvelope: Routing zur Gruppen-Conversation statt DM
- **Rollen:** owner (★), admin (🛡), member (👤)
  - Owner: alles (einladen, entfernen, Rollen ändern, Config ändern)
  - Admin: einladen, entfernen, Config ändern
  - Member: nur Nachrichten senden
- **GROUP_INVITE:** Enthält vollständige Mitgliederliste mit Public Keys
- **GROUP_LEAVE:** Benachrichtigt alle Mitglieder, System-Nachricht

## Channels
- **Asymmetrisches Modell:** Owner/Admins senden, Subscriber empfangen nur
- **Rollen:** owner (★), admin (🛡), subscriber (👤)
  - Owner: alles (Nachrichten senden, Subscriber verwalten, Admins ernennen, Config)
  - Admin: Nachrichten senden, Config ändern
  - Subscriber: nur lesen (KEINE Nachrichten senden)
- **Pairwise Fan-out:** Wie Gruppen, jede Nachricht einzeln an jeden Subscriber verschlüsselt
- **CHANNEL_INVITE:** Enthält Channel-Metadaten (Name, Beschreibung, Owner)
- **CHANNEL_LEAVE:** Subscriber kann jederzeit verlassen
- **CHANNEL_POST:** Nur Owner/Admin, wird an alle Subscriber pairwise gesendet
- **Config:** Wie Gruppen — Owner/Admin setzt, Subscriber werden benachrichtigt
- **Protobuf:** Neue MessageTypes: CHANNEL_INVITE, CHANNEL_LEAVE, CHANNEL_POST, CHANNEL_ROLE_CHANGE
- **Datenmodell:** ChannelInfo (analog GroupInfo) mit channelIdHex, ownerNodeIdHex, subscribers Map
- **GUI:** Channels-Tab in HomeScreen, Channel-Chat-Screen (Send-Bereich nur für Owner/Admin sichtbar)
- **IPC:** create_channel, invite_to_channel, leave_channel, send_channel_post, set_channel_role

### Content-Rating (geplant v2.6)
- **ContentRating Enum:** `GENERAL` (Standard), `MATURE` (ab 16), `ADULT` (ab 18)
- **Setzen:** Channel-Owner wählt Rating bei Erstellung, änderbar über Channel-Config
- **Prüfung bei Beitritt:** ADULT-Channels erfordern `isAdult`-Flag auf der beitretenden Identity
- **Ohne Flag:** Beitritt verweigert, Hinweis auf Identity-Einstellungen ("Ich bin über 18"-Toggle)
- **Anzeige:** Rating-Badge in der Channel-Liste (z.B. "18+" Badge bei ADULT)
- **Kein serverseitiger Filter:** Alles lokal geprüft, passt zur dezentralen Architektur

## Profilbilder
- Max 64KB JPEG/PNG, in ContactRequest/Response eingebettet
- PROFILE_UPDATE (Typ 103): Broadcast an alle akzeptierten Kontakte, Per-Message KEM verschlüsselt
- Auto-Resize bei >64KB: ImageMagick convert (200x200 JPEG q75)
- Persistiert als `$profileDir/profile_picture.b64`

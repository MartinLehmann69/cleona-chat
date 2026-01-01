# Cleona — Identity & Contacts

## HD-Wallet Multi-Identity
- Master Seed → Identity Keys via SHA-256 mit Index-Context-Strings
- Recovery: 24-Wort-Phrase → Master Seed → Alle Identities
- Registry im DHT (erasure-coded), siehe RECOVERY.md

## Identity Keys (pro Identity)
- Ed25519 (Signatur) — abgeleitet vom Seed
- ML-DSA-65 (PQ-Signatur) — NICHT deterministisch ableitbar
- X25519 (DH) — re-derived von Ed25519
- ML-KEM-768 (PQ-KEM) — NICHT deterministisch ableitbar

## Contact Request Protocol
1. Alice sendet CONTACT_REQUEST: Display Name, alle Public Keys, optional Profilbild/Beschreibung, PoW
2. Bob sieht Request in "Inbox", kann Accept/Reject/Block
3. Accept: Kontaktrecord erstellt, sofort verschlüsselt kommunizierbar (dank stateless KEM)
4. Mutual Auto-Accept: Wenn beide gleichzeitig CR senden

**ContactSeed-URI im Add-Contact-Dialog (V3.1.41):** Akzeptiert sowohl plain Hex-Node-ID als auch volle `cleona://...` URIs. Bei URI: Seed-Peers werden registriert (`addPeersFromContactSeed()`), 3s auf PONGs warten, dann CR senden — identischer Flow wie QR-Scan. Ermoeglicht Netzwerk-Bootstrap auch ohne vorherigen Cleona-Kontakt.

**Anti-Spam:** PoW Difficulty 20, Rate Limit 1/20s, Deduplication, Blocking (kein Response)

**Persistent Deletion Flag:** Gelöschte Kontakte in `_deletedContacts` Set (contacts.json). Verhindert Re-Import durch Restore/PeerExchange. Nur explizites Re-Add (neuer QR-Scan) cleared Flag.

## KEX Gate
Verschlüsselte Nachrichten werden NUR verarbeitet wenn Sender = akzeptierter Kontakt ODER Gruppenmitglied. Unbekannte Sender → silent drop.

## Contact Verification Levels
1. Unverified — Node-ID oder ContactSeed-URI
2. Seen — Key Exchange erfolgreich
3. Verified — QR/NFC in Person
4. Trusted — explizit vom User markiert

## Contact Local Alias (Umbenennung)
- **Lokaler Alias:** Jeder Kontakt kann lokal umbenannt werden ohne den Originalnamen zu ändern.
- **`localAlias`:** Optionales Feld in `ContactInfo`. Wenn gesetzt, wird `effectiveName` (= localAlias ?? displayName) überall verwendet.
- **Name-Change-Handling:** Wenn ein Kontakt sich selbst umbenennt (PROFILE_UPDATE mit `display_name`):
  - **Ohne Alias:** Name wird automatisch aktualisiert.
  - **Mit Alias:** `pendingNameChange` gesetzt, Banner in UI zeigt "Übernehmen" / "Alias behalten".
- **Eigene Umbenennung:** `updateDisplayName()` → ändert Service-Name + sendet PROFILE_UPDATE Broadcast an alle Kontakte.
- **Protobuf:** `ProfileData.display_name` (Feld 4) überträgt den neuen Namen.

## Profile
- Profilbild: JPEG, max 64KB, validiert via `ImageProcessor.validateProfilePicture()`
- Beschreibung: max 500 Zeichen
- Display Name: Wird in PROFILE_UPDATE (type 103) mit `display_name` Feld übertragen
- Ausgetauscht in: Contact Requests, PROFILE_UPDATE (type 103), Restore Responses, Group/Channel Invites
- `updated_at_ms` Timestamp für Konfliktauflösung

## Altersverifikation (Self-Declaration, geplant v2.6)
- **`isAdult`:** Bool-Flag pro Identity, default `false`
- **Setzen:** Toggle im Identity Detail Screen, ganz unten, erst durch Scrollen erreichbar
- **Vorsatz-Prinzip:** Bewusst versteckt — kein Kind stolpert zufällig darüber
- **Prüfung:** Beim Beitritt zu Channels mit ContentRating ADULT
- **Kein externer Verifier:** Rein lokale Self-Declaration, kein Datenaustausch
- **Rechtliche Grundlage:** Dezentraler P2P-Messenger hat keinen zentralen Betreiber → keine JMStV-Anbieterpflicht. Self-Declaration ist Branchenstandard (wie Reddit, Discord, Telegram).
- **Pro Identity:** Eltern können Sub-Identity für Kind erstellen und Flag bewusst nicht setzen

## Identity Deletion
- IDENTITY_DELETED Notification (type 102) an alle Kontakte
- Enthält: identity_ed25519_pk, deleted_at_ms, display_name

## DHT Identity Registry
- Implementierung: `lib/core/identity/identity_dht_registry.dart`
- Speichert Multi-Identity-Zuordnungen im DHT für Recovery und Geräte-Sync
- **Format:** JSON-Payload mit Identity-Liste (Public Keys, Display Names, Ableitungsindizes)
- **Verschlüsselung:** XSalsa20-Poly1305, Key abgeleitet vom Master-Seed
- **Redundanz:** Erasure-coded (N=10, K=7) — 7 von 10 Fragmenten genügen zur Rekonstruktion
- **Lookup:** Registry-ID = SHA-256("identity-registry" + master_public_key)
- Nur der Besitzer des Master-Seeds kann die Registry entschlüsseln und aktualisieren

# Cleona — Identity Recovery & Restore

## Recovery Phrase
- 24 Wörter = 264 Bits (256 Entropy + 8 Checksum)
- Wortliste: 2048 phonetisch distinkte Wörter (Indices 0-1215: CVCV 4-Buchstaben, 1216-2047: CVCVC 5-Buchstaben)
- Entropy → Master Seed: `SHA-256("cleona-master-seed-v1" + entropy)`
- Ed25519 Keys: deterministisch via HKDF-SHA-256 (`"cleona-ed25519-$index"`)
- X25519 Keys: abgeleitet aus Ed25519 (`ed25519PkToX25519`)
- PQ-Keys (ML-KEM, ML-DSA) NICHT deterministisch → werden nach Restore neu generiert

### Implementierung
- `lib/core/crypto/seed_phrase.dart` — Generation, Validation, Entropy↔Words Roundtrip
- `lib/core/identity/identity_manager.dart` — `generateSeedPhrase()`, `restoreFromPhrase()`, `loadSeedPhrase()`
- Seed-Phrase verschlüsselt gespeichert in `~/.cleona/seed_phrase.json.enc` (für Backup-Anzeige in Settings)
- Master Seed in `~/.cleona/master_seed.json.enc`

## Social Recovery (Shamir SSS)
- 5 Guardians, Threshold 3/5
- GF(256), irreduzibles Polynom 0x11B (AES-Feld)
- Shares: [1-byte Index (1-basiert)][share data]
- Jede Kombination von 3 aus 5 Shares rekonstruiert den Master Seed
- 2 oder weniger Shares verraten nichts über den Seed

### Implementierung
- `lib/core/crypto/shamir_sss.dart` — `split(secret, n, k)`, `reconstruct(shares)`
- Smoke-getestet: alle 10 Kombinationen von 3/5, verschiedene Thresholds, Edge Cases

## Restore Broadcast Flow
1. User gibt 24-Wort-Phrase ein (Setup → "Wiederherstellen")
2. `restoreFromPhrase(words)` → Master Seed → Identity mit HD-Wallet Keys
3. Ed25519 Keys = identisch zu vorher (deterministisch), Node-ID = identisch
4. PQ-Keys (ML-KEM, ML-DSA) werden neu generiert
5. `sendRestoreBroadcast()` an alle alten Kontakte (signiert mit Ed25519 Key)
6. Kontakte verifizieren Signatur → antworten mit RestoreResponse

### Signatur-Verifikation
- RestoreBroadcast wird mit dem Ed25519 Key signiert (alt = neu bei HD-Wallet)
- Empfänger prüft: "Ist old_node_id in meiner Kontaktliste?" + Signatur gültig?
- Update der PQ-Keys (ML-KEM, ML-DSA) beim Kontakt
- Update der Gruppen-/Channel-Mitgliedschaften

### Rate Limiting
- Max 1 Restore Broadcast pro Identity pro 5 Minuten
- Automatischer Retry nach 30 Sekunden

## Progressive Restoration
- **Phase 1** (sofort): Kontaktliste + eigene Info + Gruppen-/Channel-Strukturen
- **Phase 2** (nach 2s): Letzte 50 Messages aus DM-Conversation
- **Phase 3** (nach 10s): Vollständige History aus ALLEN Conversations (DMs, Gruppen, Channels)

### Phase 1 Details
- Alle akzeptierten Kontakte mit Keys + Profilbild
- Gruppen: `RestoreGroupInfo` mit Name, Owner, alle Mitglieder + Rollen + Keys
- Channels: `RestoreChannelInfo` mit Name, Owner, alle Subscriber + Rollen + Keys
- Kontakte aus Gruppen/Channels werden dedupliziert mitgeschickt

### Phase 2+3 Details
- Messages als `StoredMessage` Protobuf (ID, Sender, Recipient, Conversation, Timestamp, Type, Payload)
- Duplikat-Check: Messages die bereits aus einer früheren Phase kamen werden übersprungen
- Phase 3 enthält Phase 2 als Subset — kein Datenverlust wenn Phase 2 fehlschlägt

## Aggressive Mailbox Polling nach Restore
- 10 Polls à 3 Sekunden direkt nach `sendRestoreBroadcast()`
- Kademlia-Bootstrap braucht ~15-20s → erste Antworten ab ~20s
- Polling fängt RestoreResponses sofort auf
- Danach normales Polling (bei nächstem Startup)

## Protobuf-Definitionen
```protobuf
message RestoreBroadcast {
  bytes old_node_id = 1;
  bytes new_node_id = 2;
  bytes new_ed25519_pk = 3;
  bytes new_x25519_pk = 4;
  bytes new_ml_kem_pk = 5;
  bytes new_ml_dsa_pk = 6;
  string display_name = 7;
  uint64 timestamp = 8;
  bytes signature = 9;           // signed with Ed25519 key
}

message RestoreResponse {
  uint32 phase = 1;              // 1=contacts, 2=recent, 3=full history
  repeated ContactEntry contacts = 2;
  repeated StoredMessage messages = 3;
  repeated RestoreGroupInfo groups = 4;
  repeated RestoreChannelInfo channels = 5;
}

message RestoreGroupInfo {
  bytes group_id = 1;
  string name = 2;
  string description = 3;
  string owner_node_id_hex = 4;
  repeated RestoreGroupMember members = 5;
}

message RestoreChannelInfo {
  bytes channel_id = 1;
  string name = 2;
  string description = 3;
  string owner_node_id_hex = 4;
  repeated RestoreChannelMember members = 5;
}
```

## GUI
- **Setup Screen:** "Wiederherstellen" Button → 24-Wort Eingabe-Grid + Name + Fortschrittsanzeige
- **Settings → Sicherung:** "Recovery-Phrase anzeigen" → Dialog mit 24 nummerierten Wörtern + Kopier-Button
- **Seed-Phrase Backup:** Wird automatisch bei Ersteinrichtung angezeigt (Dialog, nicht dismissbar)

## DHT Identity Registry (Multi-Identity)
- DHT Key: `SHA-256(master_seed + "cleona-registry-id")`
- Encryption Key: `SHA-256(master_seed + "cleona-registry-key")` → XSalsa20-Poly1305
- Payload: JSON mit active indices, next_index, names
- Erasure-coded (N=10, K=7) auf 10 nächste DHT-Nodes

## NICHT implementiert (by design)
- **Proactive DHT Restore Snapshots** — deaktiviert wegen 16MB/h Mobilfunk-Traffic
- Recovery funktioniert ausschließlich via Kontakte (Restore Broadcast)

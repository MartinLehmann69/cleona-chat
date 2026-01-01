# Cleona — Encryption & Cryptography

## Design: Stateless Per-Message KEM
Kein Session-State, kein Double Ratchet. Jede Nachricht ist eigenständig.

## Algorithmen
| Zweck | Algorithmus | Key Size |
|-------|------------|----------|
| Identity-Signaturen | Ed25519 + ML-DSA-65 | 32B + 4595B |
| Per-Message KEM | X25519 + ML-KEM-768 | 32B + 1184B |
| Nachrichten | AES-256-GCM | 256-bit |
| DB at rest | XSalsa20-Poly1305 | 256-bit |
| Calls (SRTP) | AES-256-GCM | 256-bit |
| KDF | HKDF-SHA256 | — |
| Password Hash | Argon2id | — |

## Per-Message KEM Ablauf
**Senden (Alice → Bob):**
1. Frisches X25519-Ephemeral-Keypair
2. DH: `dh_secret = DH(eph_sk, bob_x25519_pk)`
3. ML-KEM Encapsulate: `(kem_ct, kem_secret) = Encap(bob_ml_kem_pk)`
4. `msg_key = HKDF-SHA256(dh_secret || kem_secret, "cleona-msg-v1")`
5. AES-256-GCM encrypt
6. Sende: `[eph_pk | kem_ct | nonce | ciphertext]`
7. `eph_sk` sofort löschen

**Empfangen:** Umgekehrt mit eigenen Private Keys.

**Overhead pro Nachricht:** ~1.1 KB (32B eph_pk + 1088B kem_ct + 12B nonce)

## Ausnahmen (NICHT KEM-verschlüsselt)
- RESTORE_BROADCAST / RESTORE_RESPONSE — nur signiert
- CONTACT_REQUEST / CONTACT_REQUEST_RESPONSE — nur signiert

## Key Rotation
- Wöchentlich (konfigurierbar), sofort bei Verdacht auf Kompromittierung
- Alter Private Key 7 Tage behalten für Transit-Nachrichten (Decrypt-Fallback)
- Verteilung via KEY_ROTATION Nachricht an alle akzeptierten Kontakte
- Nur KEM-Keys (x25519, ML-KEM) werden rotiert — Identity-Keys (Ed25519, ML-DSA) bleiben fix
- Neue x25519-Keys sind unabhängig generiert (nicht mehr von Ed25519 abgeleitet)
- Empfänger aktualisiert Kontakt-Keys + Gruppen-Mitglieder-Keys
- Protobuf: `KeyRotation { new_x25519_pk, new_ml_kem_pk, rotation_timestamp, signature }`
- Impl: `IdentityContext.rotateKemKeys()`, `CleonaService._performKeyRotation()/_handleKeyRotation()`

## Emergency Key Rotation Retry (§26.6.2 Paket C)
Bei Emergency Key Rotation (verlorenes/gestohlenes Geraet → neuer Master-Seed) senden wir `KEY_ROTATION_BROADCAST` an alle Kontakte. Der Broadcast wird zusaetzlich mit 30d S&F-TTL abgelegt (V3.1.67, commit e916e36). Fuer Kontakte, die laenger als 30d offline sind, reicht das nicht — deswegen fuehrt `KeyRotationRetryManager` (`lib/core/service/key_rotation_retry_manager.dart`) einen persistenten Retry-Pfad:

- Pro Identity eine verschluesselte Datei `key_rotation_retry.json.enc` mit Rotation-State: `rotationId`, `rotatedAt`, `expireAt = rotatedAt + 90d`, `maxAttempts = 3`, den Bytes des **dual-signierten inneren `KeyRotationBroadcast`-Protobufs**, plus `pending / acked / expired`-Mengen.
- Beim 24h-Timer-Tick (und einmal beim Daemon-Start) sendet der Service den gespeicherten Broadcast pro faelligem Kontakt erneut — **neue Per-Message-KEM-Verschluesselung und neuer Outer-Envelope mit dem NEUEN Identity-Key**, **gleiche innere Dual-Signatur**. Das funktioniert nach Key-Wipe, weil die Authentifizierung an der inneren (Old-Key+New-Key)-Signatur haengt, die der Sender nach Rotation nicht mehr neu erzeugen koennte.
- `KEY_ROTATION_ACK` ruft `markAcked()` und entfernt den Kontakt aus `pending`. Eine neue Rotation (`rotateIdentityKeys()` erneut aufgerufen) ueberschreibt den State komplett; parallele Epochen gibt es bewusst nicht.
- Nach `maxAttempts` **oder** `expireAt` (whichever first) → Kontakt wandert in `expired` und `CleonaService` feuert `onKeyRotationPendingExpired(contactHex, pendingCount)` → IPC-Event `key_rotation_pending_contact`. Der Kontakt wird **nicht** automatisch entfernt — die UI soll den User zur Re-Verifizierung auffordern.
- Bekannter Edge-Case (v2 / deferred): Wenn ein ACK verloren geht UND der Empfaenger die Rotation bereits uebernommen hat, schlaegt die Old-Signature-Verifizierung fehl (Receiver-seitig ist `contact.ed25519Pk` schon der NEUE Schluessel). Die Retries landen dann letztlich in `expired`. Ein idempotenter Re-ACK-Pfad (Receiver erkennt `newEd25519Pk == contact.ed25519Pk` → ACK direkt, Signaturpruefung skippen) ist als separates Follow-up eingeplant, da security-sensitive.
- **Sicherheitsdetails (V3.1.67 Security-Review):**
  - **senderId-Override beim Retry:** Der State haelt die `oldUserIdHex` fest (BEFORE `rotateIdentityFull` gespeichert). Jede Retry-Envelope-Generierung nutzt `identity.createSignedEnvelope(..., senderIdOverride: oldUserIdBytes)`. Ohne diesen Override wuerde der Empfaenger-seitige Kontakt-Lookup (`_contacts[senderHex]` in `_handleKeyRotationBroadcast`) auf der neuen (post-Rotation) User-ID vergeblich nachschlagen und stumm verwerfen — der Retry hatte nie eine Chance die innere Dual-Signaturpruefung zu erreichen.
  - **KEY_ROTATION_ACK outer-sig verification:** `_handleKeyRotationAck` verifiziert die Outer-Envelope-Ed25519-Signatur gegen `contact.ed25519Pk`. Ohne diese Pruefung koennte jeder Angreifer, der die Node-ID eines Opfer-Kontakts kennt, eine gefaelschte ACK-Nachricht mit der Opfer-Senderid schicken und die Retries stumm stoppen (Opfer-Kontakt bleibt dauerhaft auf alten Keys). Der ACK-Sender rotiert seine eigenen Keys nicht → die beim Rotator gespeicherte Pubkey ist der gueltige Verifier.

## Call-Encryption
- 1:1: Beidseitiges Ephemeral-DH → `call_key = HKDF(DH_a||DH_b||KEM_a||KEM_b, "cleona-call-v1")`
- Gruppen: Initiator generiert `call_key`, per KEM an jeden Teilnehmer
- Key Rotation bei Kick oder neuem Teilnehmer (nicht bei Crash+Rejoin)
- Overlay Multicast Tree für effizientes Streaming (nicht Full Mesh)

## DB-Verschlüsselung
- Algorithmus: XSalsa20-Poly1305 (libsodium)
- Key: `SHA-256(ed25519_sk[0:32] + "cleona-db-key-v1")`
- Format: `cleona.db.enc` = [24B nonce][ciphertext]
- SQLite auf entschlüsseltem Temp-File, verschlüsselter Flush alle 60s
- Automatische Migration von unverschlüsselt → verschlüsselt

## Key Storage
| Plattform | Speicher |
|-----------|---------|
| Android | Android Keystore (hardware-backed) |
| iOS | Secure Enclave / Keychain |
| Linux | keys.json (Argon2id + XSalsa20-Poly1305) |

## Signaturen
Alle Nachrichten dual signiert: Ed25519 + ML-DSA-65. Beide werden bei Empfang verifiziert.
Stale Keys: Bei Mismatch wird gecachter Key gelöscht (nicht Message rejected).

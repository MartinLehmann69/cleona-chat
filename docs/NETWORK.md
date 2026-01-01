# Cleona — Network Architecture

## Port & Transport
- Einzelner zufaelliger UDP-Port (10000-65000), persistiert im Profil
- **UDP fuer ALLES** (Chat, DHT, Relay, Signaling, Media)
- **Dual-Stack (V3.1.48):** IPv4-Socket (`_udpSocket`) + IPv6-Socket (`_udpSocket6`), gleicher Port, gleicher Handler
- `_socketFor(addr)` waehlt Ausgangs-Socket nach Adresstyp (IPv4 oder IPv6)
- Implizites IPv4↔IPv6 Bridging: Dual-Stack-Nodes koennen zwischen reinen IPv4- und IPv6-Peers vermitteln
- **Kein plain TCP** (V3.2) — entfernt, da nicht relaybar und keine Offline-Zustellung
- TLS 1.3 Fallback auf **demselben Port wie UDP** (V3.1.71, IPv4 + IPv6), aktiviert nach 15 konsekutiven UDP-Fehlern. UDP (SOCK_DGRAM) und TCP (SOCK_STREAM) teilen sich die Port-Nummer kernel-seitig ohne Konflikt. Bootstrap: UDP+TCP 8080 (Live) / 8081 (Beta). Mobile/Desktop: zufälliger UDP-Port = TCP-Port
- Payloads >1200B: App-Level-Fragmentierung (siehe ROUTING_V3.md)
- RUDP Light fuer Zustellbestaetigung (DELIVERY_RECEIPT)

## DHT (Kademlia)
- Node-ID: `SHA-256(network_tag + public_key_bytes)` — 256-bit
- Mailbox-ID: `SHA-256("mailbox" + public_key_bytes)` — separate Adresse, keine Korrelation
- 256 k-Buckets, persistierte Routing Table
- Startup: 2-Phasen (Load + Prune 2h). Safety: Wenn Prune ALLE entfernt → Reload ohne Prune
- Maintenance: Prune alle 60s, Peers > 4h werden entfernt
- `findClosestPeers()`: Bevorzugt recent (< 10min), stale nur als Fallback

## Mesh Discovery (V3.1.1: Drei-Kanal + Subnet-Scan)
- **Passiv (alle parallel pro Burst):**
  - IPv4 Broadcast 255.255.255.255:41338 — selbes /24
  - IPv4 Multicast 239.192.67.76:41338 TTL=4 — cross-subnet nur bei IGMP (oft nicht verfuegbar!)
  - IPv6 Multicast ff02::1:636c — falls IPv6 verfuegbar
- **Kein BLE:** Bewusste Designentscheidung — Presence Leakage (30m Tracking), Eclipse-Angriffe, Peer-List-Poisoning ausserhalb des HMAC-Gates
- **V3.1: 3x Burst auf ALLEN Kanaelen gleichzeitig, dann STILLE** (kein Dauerfeuer!)
- **V3.1.1: Subnet-Scan Fallback:** Wenn nach Burst 0 Peers → Unicast-Probes (CLEO 38B) ueber /16 auf Port 41338
  - Scan-Reihenfolge: DHCP-Hotspots zuerst (.1,.50,.100,.150,.200), dann auffuellen
  - Abbruch bei erstem Fund (~10-15s in Praxis)
  - ~65K Pakete = ~4MB, einmalig beim Start, ~500/s
  - Discovery-Listener reagiert auf Unicast identisch zu Broadcast
- **ACHTUNG:** IPv4 Multicast funktioniert cross-subnet NUR mit IGMP-Routing auf dem Router. Viele Consumer-Router (Fritzbox) unterstuetzen das NICHT. Der Subnet-Scan ist der zuverlaessige Fallback
- Kein manueller --bootstrap-peer noetig
- Listener laeuft permanent — hoert neue Nodes wenn SIE ihren Burst senden
- **Aktiv:** NFC (Contact Exchange + Peer-List), QR (ContactSeed URI), .clp Datei
- CLEO-Pakete: `[4B "CLEO"][32B nodeId][2B port]` — muessen VOR Protobuf-Parsing gefiltert werden

## ContactSeed URI
`cleona://<nodeIdHex>?n=<name>&a=<ip:port%2Bip:port>&s=<seedPeers>`
- QR: max 5 Seed-Peers mit je 2 Adressen
- .clp Datei: max 10 Seed-Peers

## Routing Table (V3: Distance-Vector)
- **Route-basiert** statt nur Peer-Adressen: destination, nextHop, hopCount, cost, connType
- Mehrere Routen pro Ziel, sortiert nach Cost (billigste zuerst)
- Bellman-Ford + Split Horizon + Poison Reverse
- Route-Updates event-driven (nicht periodisch), Safety-Net 1x/h
- **Default-Gateway:** Unbekannte Ziele → Public IP des best-connected Peers
- **TTL = 64:** Pro Relay-Hop -1, bei 0 verwerfen (Loop-Schutz)
- **Max ~2.100 Eintraege:** 1.000 Kontakte + 640 Transit + 500 Channel
- Siehe `docs/ROUTING_V3.md` fuer vollstaendige Spezifikation

## Multi-Address Support
- Jeder Peer hat Liste von `PeerAddress` (ip, port, type, score 0.0-1.0, success/fail counts)
- `allConnectionTargets()`: Dedupliziert, sortiert nach Priority (LAN>Public>CGNAT) dann Score
- Stale: > 14 Tage ohne Erfolg → entfernt

## NAT Traversal (V3: Aktiver Hole Punch)
- Dezentrales STUN: Peers berichten oeffentliche IP zurueck (min 2 Bestaetigungen), Private/CGNAT-IPs werden automatisch abgelehnt (PeerAddress.isPrivateIp-Guard)
- **V3: Aktiver UDP Hole Punch** via Koordinator (HolePunchRequest/Notify)
- **V3: NAT-Timeout-Probing** (dynamisch pro Verbindung: 15s→30s→60s→... bis Timeout)
- **V3: Keepalive = 80% des NAT-Timeouts** (einziger periodischer Verkehr!)
- Route-basierte Zustellung statt Schrotflinte an alle Adressen (V3)

## Network Change Detection
- Flutter GUI: `connectivity_plus` + `AppLifecycleListener`
- Headless: IP-Polling (10s), Public-IP-Polling via ipify (60s)
- Recovery: NAT reset → Fast Discovery → Ping alle Peers → DHT Re-Bootstrap → Address Broadcast → Mailbox Poll
- Keepalive: 3 konsekutive Totalfehler (~75s) → voller Recovery-Zyklus

## RUDP Light (Reliable UDP)
- **Jede nicht-ephemere Nachricht bekommt DELIVERY_RECEIPT** (ACK)
- ACK-Timeout: 2xRTT + 50ms (Default 1s fuer unbekannte Peers)
- **3x konsekutiver Timeout = Route DOWN** (V3), Poison Reverse an Nachbarn
- Kein Timer-basiertes Route-Expiry mehr — nur ACK-basiert
- **Ausnahmen (kein ACK):** TYPING_INDICATOR, READ_RECEIPT, Live Audio/Video
- Max 5 Kopien pro Fragment im Netzwerk

## Multi-Hop Relay (RELAY_FORWARD)
- **V3: Relay ist Teil des Distance-Vector-Routing** — die Routing-Tabelle WEISS proaktiv, welcher Peer als Relay dient. Kein reaktives Suchen von Kandidaten
- **Wrapper-Architektur:** Original-Envelope bleibt unveraendert (Signaturen + PoW gueltig). Relay-Nodes sehen nur verschluesselten Blob
- **Loop-Prevention:** 3 Schichten — relay_id Dedup-Cache (10.000 LRU), visited_nodes Liste, **TTL=64 (V3)** dekrementiert pro Hop
- **TTL (V3):** Startwert 64, -1 pro Hop, bei 0 verwerfen. Ersetzt zeitbasiertes 5-Min-Expiry
- **Rate-Limiting (RelayBudget):** 1 MB/Min total, 256 KB/Min pro Quell-Node, 50 Messages/Min, max 64 KB Payload
- **RELAY_ACK:** Informiert den Sender ob Zustellung erfolgreich (delivered=true) oder weitergeleitet (false). Bei delivered=true wird Relay-Route in Routing-Tabelle gespeichert
- **PoW-Exempt:** RELAY_FORWARD/ACK sind Infrastruktur-Messages, kein PoW noetig
- Impl: `relay_budget.dart`, `cleona_node.dart`

## Bootstrap Node
- Nicht hardcoded — wird via ContactSeed QR gelernt
- Normaler Peer, gleiches Protokoll
- Decommission: ≥10 Nodes gleichzeitig online über 30 Tage
- Aktuell: Hyper-V 192.0.2.15:8080 (NICHT die decommissioned KVM-VM starten!)

## Proof of Work (Spam-Schutz)
- SHA-256-basiertes Hashcash auf jeder Anwendungs-Nachricht
- Difficulty 20 (≈ 2^20 Hashes ≈ 50-100ms auf Desktop)
- Berechnet nach Signierung: `SHA-256(signedEnvelopeBytes || nonce_8LE)` mit `difficulty` führenden Null-Bits
- Nur auf Anwendungs-Nachrichten (TEXT, GROUP_INVITE, etc.), NICHT auf DHT-Protokoll (PING/PONG/FIND_NODE)
- Verifizierung beim Empfang, ungültige PoW wird still verworfen
- Protobuf: `ProofOfWork { nonce, difficulty, hash }` in `MessageEnvelope.pow`

## Kompression
- zstd auf alle Protobuf-Payloads, VOR Verschlüsselung
- Header-Flag: `compression: NONE | ZSTD`
- Text immer `utf8.encode()`/`utf8.decode()` — NIEMALS `.codeUnits`

## Network Statistics Dashboard
- Implementierung: `lib/core/network/network_stats.dart` (Datensammlung), `lib/ui/screens/network_stats_screen.dart` (UI)
- 4 Sektionen: Health (Uptime, DHT-Peers, Latenz), Data Usage (Sent/Received, Fragmente), Relay (weitergeleitete Nachrichten), Connection Details (UDP-Aufschlüsselung)
- Erreichbar über AppBar (📊 Icon)
- **Byte-Zählung:** Transport-Callbacks `onBytesSent`/`onBytesReceived` in `transport.dart` melden jede UDP-Operation an `NetworkStatsCollector.addBytesSent()`/`addBytesReceived()`. Verdrahtet in `CleonaService.startService()` via `node.transport.onBytesSent`.

## IPv6 Dual-Stack Transport (V3.1.48)

### Motivation
- DS-Lite (Standard bei deutschen ISPs) gibt globale IPv6, aber IPv4 hinter CGNAT
- CGNAT = Symmetric NAT → Standard Hole Punching scheitert
- IPv6 hat kein NAT → jedes Geraet direkt erreichbar → ideal fuer P2P

### Dual-Socket-Architektur
- `_udpSocket` (IPv4, `InternetAddress.anyIPv4`) + `_udpSocket6` (IPv6, `InternetAddress.anyIPv6`)
- Gleicher Port, gleicher `_processUdpDatagram()` Handler
- `_socketFor(addr)`: IPv6-Adresse → `_udpSocket6`, sonst `_udpSocket`
- `rebind()` re-erstellt beide Sockets bei Port-Aenderung

### Adress-Prioritaet
| Typ | Priority | Beispiel |
|---|---|---|
| LAN IPv4 | 1 | 192.168.x.x, 10.x.x.x |
| IPv6 Link-Local | 1 | fe80::... |
| IPv6 Global | 2 | 2001:db8::... |
| Public IPv4 | 3 | 203.0.113.x |
| CGNAT IPv4 | 5 | 100.64.x.x, 192.0.0.x |

### PeerCapabilities
- Bitmask: `ipv4=1`, `ipv6=2`, `dualStack=3`
- Advertised in PEER_LIST_PUSH und PONG
- Relay-Selektion bevorzugt Dual-Stack-Nodes (koennen IPv4↔IPv6 bridgen)

### CGNAT-Bypass (IPv4 Fallback)
- **CGNAT-Erkennung:** 100.64.0.0/10 und 192.0.0.0/24 als nicht-routable
- **PCP (RFC 6887):** Requests an 192.0.0.1 (DS-Lite AFTR) und 100.64.0.1 (CGNAT-Gateway)
- **Port-Prediction Hole Punch:** ±10 Ports bei Symmetric NAT (koordiniert via Mutual Peer)

### Seed-Peer Persistenz
- QR/NFC/ContactSeed-Peers: `isProtectedSeed = true`
- Ueberlebt DHT Maintenance-Pruning (normalerweise 4h Timeout)
- Android Doze: Resume → `onNetworkChanged()` + ipify Re-Discovery

### Public-IP Discovery
- Desktop/Headless: `api.ipify.org` (IPv4) + `api6.ipify.org` (IPv6), Startup + 60s Polling
- Android: gleich, aber Trigger bei Start + Resume (kein Polling im Doze)
- Beide Adressen in PEER_LIST_PUSH fuer Kontakt-Lernen

### ContactSeed IPv6-Format
- IPv6 in Bracket-Notation: `[2001:db8::1]:41338`
- Seed-Peers koennen gemischt IPv4 + IPv6 enthalten

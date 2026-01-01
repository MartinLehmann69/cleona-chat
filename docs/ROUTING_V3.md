# Cleona — Routing V3 Spezifikation

**Version 3.0 — Distance-Vector Routing, Event-Driven Architecture**
**Datum: 2026-03-30**
**Status: Geplant (ersetzt reaktives Routing aus v2.9)**

---

## Inhaltsverzeichnis

1. [Motivation & Probleme in V2.9](#1-motivation--probleme-in-v29)
2. [Distance-Vector Routing](#2-distance-vector-routing)
3. [Cost-Modell](#3-cost-modell)
4. [TTL (Hop Limit)](#4-ttl-hop-limit)
5. [Default-Gateway](#5-default-gateway)
6. [Discovery (Event-Driven)](#6-discovery-event-driven)
7. [QR-Code / ContactSeed](#7-qr-code--contactseed)
8. [RUDP Light & Route-Down-Propagation](#8-rudp-light--route-down-propagation)
9. [NAT Hole Punch & Keepalive](#9-nat-hole-punch--keepalive)
10. [App-Level-Fragmentierung](#10-app-level-fragmentierung)
11. [TCP/TLS Entfernt (V3.2)](#11-tcptls-entfernt-v32)
12. [Reed-Solomon Fragment-Retention](#12-reed-solomon-fragment-retention)
13. [Routing-Tabellen-Limit](#13-routing-tabellen-limit)
14. [Store-and-Forward (Push-basiert)](#14-store-and-forward-push-basiert)
15. [Adress-Propagation](#15-adress-propagation)
16. [Implementierungsplan](#16-implementierungsplan)

---

## 1. Motivation & Probleme in V2.9

### Warum ein Routing-Redesign?

Die vorherigen Sessions haben den Netzwerkstack instabil gemacht. Die Grundursache: **es gibt kein echtes Routing.** Stattdessen werden Pakete "auf gut Glück" an alle bekannten Adressen geschossen (Schrotflinte) und Relay-Routen nur reaktiv und temporaer entdeckt.

### Konkrete Probleme

| Problem | Ursache |
|---------|---------|
| Alice→Handy Rueckweg offen | Relay-Route verfaellt nach 10 Min (Timer-basiert statt ACK-basiert) |
| UDP-Port-Problem | Kein aktiver Hole Punch, kein Keepalive |
| Discovery-Dauerfeuer | IPv4 Broadcast alle 10s, IPv6 Multicast alle 30s — endlos |
| Schrotflinten-Send | Kein priorisiertes Routing, alle Adressen parallel |
| CR via Relay instabil | Relay-Kandidaten reaktiv gesucht statt proaktiv gewusst |
| TCP als allgemeiner Fallback | TCP bei >1200B und nach 5 UDP-Fehlern — unnoetig, entfernt in V3.2 |
| Reed-Solomon Fragment-Retention | Zweck unklar (Offline-Zustellung vs. Netzwerkfehler) |

### Design-Prinzipien V3

1. **Proaktiv statt reaktiv:** Die Routing-Tabelle WEISS, wie jeder Peer erreichbar ist
2. **Event-driven statt Timer-basiert:** Aenderungen werden sofort propagiert, kein Polling
3. **ACK-basiert statt Timer-basiert:** Routen sterben durch fehlende DELIVERY_RECEIPTs, nicht durch Zeitablauf
4. **Nur UDP:** Kein TCP, kein TLS — alles per UDP + RUDP Light
5. **Kein Netz-Spam:** Discovery nur beim Start, sonst Stille

---

## 2. Distance-Vector Routing

### Konzept

Inspiriert von RIP (Routing Information Protocol), aber fuer P2P-Mesh optimiert. Jeder Node pflegt eine Routing-Tabelle mit **Routen** (nicht nur Peers).

### Route-Eintrag

```dart
class Route {
  Uint8List destination;     // Ziel-NodeId (32 bytes)
  Uint8List nextHop;         // Naechster Sprung (32 bytes), null = direkt
  int hopCount;              // Entfernung in Hops
  int cost;                  // Gesamtkosten des Pfads
  RouteType type;            // direct | relay
  DateTime lastConfirmed;    // Letzter erfolgreicher ACK ueber diese Route
  ConnectionType connType;   // lan | wifi | publicUdp | holePunch | relay | mobile
}

enum RouteType { direct, relay }
enum ConnectionType { lanSameSubnet, lanOtherSubnet, wifiDirect, publicUdp, holePunch, relay, mobile }
```

### Mehrere Routen pro Ziel

Pro Ziel koennen **mehrere Routen** existieren, sortiert nach Cost (billigste zuerst). Die billigste Route ist primaer, der Rest dient als Fallback.

Beispiel:
```
Ziel: Handy
  Route 1: via Bootstrap (LAN→Public), Cost 6,  HopCount 2  ← primaer
  Route 2: via NodeX (Relay→Relay),    Cost 20, HopCount 3  ← Fallback
```

### Bellman-Ford-Algorithmus

Wenn ein Nachbar eine Route advertised, berechnet der empfangende Node:

```
neueKosten = kosten_zum_nachbarn + advertised_cost
if (neueKosten < aktuelle_kosten_zum_ziel) {
  route_uebernehmen(ziel, nextHop: nachbar, cost: neueKosten);
}
```

### Split Horizon

Eine Route wird **NICHT** zurueck an den Nachbarn advertised, von dem sie gelernt wurde. Das verhindert einfache Routing-Loops.

### Poison Reverse

Wenn eine Route ausfaellt, wird sie mit **Cost = infinity (65535)** an alle Nachbarn gemeldet. Das verhindert das "Counting-to-Infinity"-Problem.

### Route-Update-Trigger

Route-Updates werden **event-driven** propagiert (kein Timer!):

1. **Eigene Adresse aendert sich** (Netzwerkwechsel, neuer Hole Punch)
2. **Neuer Peer entdeckt** (Discovery, QR-Scan) → **Welcome-Update** (volles Route-Table nach 500ms)
3. **Route faellt aus** (3x RUDP Light Timeout)
4. **Route wird besser** (neuer Hole Punch, direkter Kontakt etabliert)
5. **Zurueckkehrender Peer** → **Catch-up-Update** (volles Route-Table wenn letztes Update >60s her)
6. **Safety-Net:** Alle 1h einmal komplett austauschen (falls ein Update durchgerutscht ist)

### Protobuf: ROUTE_UPDATE (neuer MessageType)

```protobuf
message RouteUpdate {
  repeated RouteEntry routes = 1;
}

message RouteEntry {
  bytes destination = 1;     // 32 bytes NodeId
  int32 hopCount = 2;
  int32 cost = 3;
  ConnectionType connType = 4;
  int64 lastConfirmedMs = 5;
}
```

---

## 3. Cost-Modell

### Streckenkosten (pro Hop)

| Verbindungstyp | Cost | Begruendung |
|----------------|------|-------------|
| LAN same-subnet | 1 | Kostenlos, schnell, zuverlaessig |
| LAN other-subnet | 2 | Gateway-Hop, aber noch lokal |
| WiFi direkt | 3 | Kostenlos, aber weniger zuverlaessig |
| Public UDP (direkt) | 5 | Internet, aber kein Relay-Overhead |
| Public UDP (Hole Punch) | 5 | Wie Public UDP, aber Keepalive noetig |
| Relay (pro Hop) | 10 | Nutzt Bandbreite eines Dritten |
| Mobilfunk direkt | 20 | Datenvolumen kostet Geld |
| Mobilfunk via Relay | 30 | Teuerste Variante |

### Gesamtkosten

Die Gesamtkosten einer Route sind die **Summe aller Streckenkosten** auf dem Pfad:

```
Alice ──(LAN:1)──► Bootstrap ──(Public:5)──► Handy = Cost 6
Alice ──(Relay:10)──► NodeX ──(Mobile:20)──► Handy = Cost 30
```

Route 1 gewinnt (Cost 6 < Cost 30).

### Cost ist NICHT TTL

Cost und TTL sind voellig getrennte Konzepte:
- **Cost:** Fuer Route-Auswahl (welcher Weg ist am guenstigsten?)
- **TTL:** Fuer Loop-Schutz (wie viele Hops darf ein Paket maximal machen?)

---

## 4. TTL (Hop Limit)

### Konzept

Wie IPv4 TTL / IPv6 Hop Limit. Schuetzt gegen Routing-Loops.

### Regeln

- **Startwert:** 64 (gesetzt vom Sender)
- **Pro Relay-Hop:** -1 (immer genau 1, unabhaengig von Verbindungstyp)
- **Bei TTL = 0:** Paket verwerfen, NICHT weiterleiten
- **Keine Fehlermeldung:** Sender erfaehrt Verlust ueber RUDP Light Timeout

### Implementierung

Das Feld `ttl` wird im `RelayForward`-Protobuf hinzugefuegt (ersetzt/ergaenzt `maxHops`):

```protobuf
message RelayForward {
  bytes relayId = 1;
  bytes finalRecipientId = 2;
  bytes wrappedEnvelope = 3;
  int32 hopCount = 4;
  int32 ttl = 5;              // NEU: Startwert 64, dekrementiert pro Hop
  bytes originNodeId = 6;
  int64 createdAtMs = 7;
  repeated bytes visitedNodes = 8;  // Loop-Prevention (zusaetzlich zu TTL)
}
```

### Zusammenspiel mit visited_nodes

TTL und `visited_nodes` ergaenzen sich:
- **visited_nodes:** Erkennt Loops frueh (exakt, aber speicherintensiv)
- **TTL:** Harter Fallback wenn visited_nodes versagt (z.B. bei Bugs)

---

## 5. Default-Gateway

### Konzept

Wenn keine Route zum Ziel bekannt ist, wird das Paket an einen **Default-Gateway** weitergeleitet — wie bei TCP/IP.

### Auswahl-Algorithmus (Kombination lokal + oeffentlich)

```
Paket fuer unbekanntes Ziel X:
1. Lokale Routing-Tabelle → Route gefunden? → nutzen
2. Best-connected LOKALER Peer → kennt er die Route? → weiterleiten
3. Keiner lokal weiss Bescheid → PUBLIC IP des best-connected Peers
   (raus aus dem lokalen Netz, Richtung Hub)
4. TTL schuetzt vor Endlosschleifen
```

### Best-Connected Peer Metrik

```dart
defaultGateway = peers
  .where((p) => p.isConfirmed && p.isOnline)
  .sortBy(knownRoutes DESC, avgCost ASC, uptime DESC)
  .first;
```

Kriterien:
1. **Meiste bekannte Routen** (= breitestes Netzwerkwissen)
2. **Niedrigster durchschnittlicher Cost** (= gute Anbindung)
3. **Hoechste Uptime** (= zuverlaessig)

### Natuerliche Hubs

Nodes die lange online sind und viele Kontakte haben, werden automatisch zum Default-Gateway vieler Peers — genau wie zentrale Router in IP-Netzen. Der Bootstrap ist anfangs der natuerliche Hub.

### Default-Gateway-Wechsel

- Bei Ausfall (3x RUDP Timeout) → naechstbesten waehlen
- Bei Netzwerkwechsel → neu evaluieren
- Periodisch (alle 10 Min) → pruefen ob ein besserer verfuegbar ist

---

## 6. Discovery (Event-Driven, V3.1: Drei-Kanal-Parallel)

### Drei Discovery-Mechanismen (parallel pro Burst)

| Mechanismus | Ziel-Adresse | Reichweite | Voraussetzung |
|-------------|-------------|------------|---------------|
| IPv4 Broadcast | 255.255.255.255 | Selbes /24 Subnetz | Keine (immer) |
| IPv4 Multicast | 239.192.67.76 | Gesamtes geroutetes LAN | Router mit IGMP |
| IPv6 Multicast | ff02::1:636c | Link-Local / geroutet | IPv6 aktiv |

**Warum drei?** Broadcast ist zuverlaessig im lokalen Subnetz, aber ueberschreitet KEINE Subnetzgrenzen. Multicast wird vom Router ueber Subnetzgrenzen weitergeleitet (sofern IGMP aktiv). Die drei Mechanismen ergaenzen sich — jeder Burst sendet auf ALLEN Kanaelen gleichzeitig.

**Multicast-Gruppe:** `239.192.67.76` — Organization-Local Scope (RFC 2365). 67.76 = ASCII "CL" (Cleona).

### 3x Burst, dann Stille

```
Burst 1: Broadcast + IPv4 Multicast + IPv6 Multicast (parallel)
  wait 2s
Burst 2: dasselbe
  wait 2s
Burst 3: dasselbe
  → STILLE. Kein Dauerfeuer.
```

### Warum reicht das?

Wenn ein neuer Node online geht, sendet ER seinen eigenen 3x-Burst. Die bestehenden Nodes HOEREN ihn auf dem Discovery-Port (der Listener laeuft ja weiter). Dauersenden ist unnoetig — die Gegenseite meldet sich selbst.

### Cross-Subnet-Szenario

```
Alice (192.0.2.201/24) ──── Router (IGMP) ──── Bootstrap (192.0.2.15/24)

Alice startet → sendet Multicast an 239.192.67.76
→ Router leitet an alle Subnetze weiter (IGMP)
→ Bootstrap empfaengt → antwortet per Unicast
→ Alice kennt Bootstrap → Bootstrap als Seed im QR
```

Kein manueller `bootstrap_seeds.json` noetig. Die Nodes finden sich ueber Standard-Netzwerkprotokolle.

### Listener

Listener bleibt dauerhaft aktiv auf Broadcast-Port (41338) — empfaengt sowohl Broadcast als auch Multicast (selber Socket, `joinMulticast()` bei Start).

---

## 7. QR-Code / ContactSeed

### Aktuell (unvollstaendig)

- `ownAddresses` enthaelt nur private LAN-IPs
- Seed-Peers nicht auf Erreichbarkeit geprueft
- Keine Mindestanzahl Private + Public

### Neu: Private + Public, nur bestaetigte Peers

```dart
ContactSeed buildContactSeed() {
  final ownAddrs = <String>[];

  // Private Adressen (max 2)
  for (final ip in localIps.take(2)) {
    ownAddrs.add('$ip:$port');
  }

  // Oeffentliche Adresse (aus NatTraversal)
  if (natTraversal.hasPublicIp) {
    ownAddrs.add('${natTraversal.publicIp}:${natTraversal.publicPort}');
  }

  // Seed-Peers: nur BESTAETIGTE, aktuell erreichbare Peers
  // Min 1 privat + 1 oeffentlich, max 2+2
  final confirmedPeers = routingTable.allPeers
    .where((p) => confirmedPeerIds.contains(p.nodeIdHex))
    .where((p) => DateTime.now().difference(p.lastSeen).inMinutes < 10);

  final privatePeers = confirmedPeers
    .where((p) => _isPrivateIp(p.bestAddress.ip))
    .take(2);
  final publicPeers = confirmedPeers
    .where((p) => !_isPrivateIp(p.bestAddress.ip))
    .take(2);

  return ContactSeed(
    nodeIdHex: nodeIdHex,
    displayName: displayName,
    ownAddresses: ownAddrs,  // Privat + Public!
    seedPeers: [...privatePeers, ...publicPeers],
  );
}
```

### Nach dem Scan: Ablauf

1. Scanner-Node verbindet sich zu einem der Seed-Peers (vorzugsweise LAN)
2. Holt sich die **komplette Peer-Liste** via Peer Exchange
3. **Teilt ALLEN Peers seine eigene Erreichbarkeit mit** (Privat + Public, notfalls via Relay)
4. Sendet CONTACT_REQUEST an den QR-Ersteller

---

## 8. RUDP Light & Route-Down-Propagation

### Grundsatz

**Jede nicht-ephemere Nachricht wird per RUDP Light versendet.** Das bedeutet: jede Nachricht bekommt eine DELIVERY_RECEIPT als Bestaetigung.

### Ausnahmen (kein RUDP Light)

- TYPING_INDICATOR (Gegenstelle tippt gerade)
- READ_RECEIPT (Lesebestaetigung)
- Live Audio/Video Stream (Echtzeit, Verlust akzeptabel)
- DHT-Protokoll (PING/PONG/FIND_NODE — haben eigene ACK-Mechanismen)

### Route-Down-Erkennung

```
3 aufeinanderfolgende Nachrichten an denselben Peer ohne DELIVERY_RECEIPT
→ Route als DOWN markieren
→ Sofort allen Nachbarn mitteilen (Poison Reverse, Cost = infinity)
```

### Kein Timer-basiertes Expiry mehr

**ALT (v2.9):**
```dart
bool get hasValidRelayRoute =>
    DateTime.now().difference(relaySetAt!).inMinutes < 10;  // ENTFERNEN!
```

**NEU (v3.0):**
```dart
bool get hasValidRelayRoute =>
    relayViaNodeId != null &&
    consecutiveRouteFailures < 3;  // ACK-basiert!
```

Eine Relay-Route bleibt gueltig solange DELIVERY_RECEIPTs zurueckkommen. Erst bei 3x Timeout wird sie als DOWN markiert.

### Route-Down-Propagation

```
Alice sendet 3x an Handy via Bootstrap → kein DELIVERY_RECEIPT
→ Alice markiert Route "Handy via Bootstrap" als DOWN
→ Alice sendet ROUTE_UPDATE(destination=Handy, cost=65535) an alle Nachbarn
→ Nachbarn entfernen/aktualisieren ihre Route zu Handy ueber Alice
→ Falls Nachbarn alternative Routen kennen, advertisen sie diese
```

---

## 9. NAT Hole Punch & Keepalive

### Aktiver Hole Punch (NEU)

Wenn ein Node erstmals einen Peer mit oeffentlicher IP lernt, versucht er **sofort** einen UDP Hole Punch:

1. Node A lernt Peer B's oeffentliche IP (via Routing-Tabelle, Peer Exchange)
2. A sendet UDP-Paket an B's oeffentliche IP (oeffnet NAT-Pinhole bei A)
3. B sendet UDP-Paket an A's oeffentliche IP (oeffnet NAT-Pinhole bei B)
4. Koordination ueber einen gemeinsamen Dritten (z.B. Bootstrap) der beiden die jeweils andere Adresse mitteilt

### NAT-Timeout-Probing

Der Keepalive-Intervall wird **dynamisch ermittelt** statt fest konfiguriert:

```
1. Hole Punch aufbauen
2. Leichtes PING/PONG ueber den gepunchten Kanal
3. Intervall verdoppeln: 15s, 30s, 60s, 90s, 120s
4. Sobald PONG ausbleibt → letztes funktionierendes Intervall = NAT-Timeout
5. Keepalive-Intervall = 80% davon
6. Wert persistieren pro Verbindung
```

### Typische NAT-Timeouts

| Router-Typ | Typischer Timeout | Keepalive (80%) |
|------------|-------------------|-----------------|
| Heimrouter (Fritz!Box) | 60-180s | 48-144s |
| Mobilfunk (CGNAT) | 30-60s | 24-48s |
| Firmen-NAT | 120-300s | 96-240s |

### Keepalive = einziger periodischer Verkehr

Der NAT-Keepalive ist der **EINZIGE** periodische Netzwerkverkehr im gesamten System. Alles andere ist event-driven.

### Hole-Punch-Koordinations-Protokoll

```protobuf
message HolePunchRequest {
  bytes targetNodeId = 1;     // Wer soll gepuncht werden?
  string myPublicIp = 2;      // Meine oeffentliche IP
  int32 myPublicPort = 3;     // Mein oeffentlicher Port
}

message HolePunchNotify {
  bytes requesterNodeId = 1;   // Wer will punchen?
  string requesterIp = 2;     // Dessen oeffentliche IP
  int32 requesterPort = 3;    // Dessen oeffentlicher Port
}
```

Ablauf:
1. A → Koordinator: `HolePunchRequest(target=B, myIp=85.x.x.x:39874)`
2. Koordinator → B: `HolePunchNotify(requester=A, ip=85.x.x.x:39874)`
3. A sendet UDP an B's oeffentliche IP (oeffnet Pinhole)
4. B sendet UDP an A's oeffentliche IP (oeffnet Pinhole)
5. Beide koennen jetzt direkt kommunizieren

---

## 10. App-Level-Fragmentierung

### Warum?

Payloads >1200 Bytes (PQ-Keys ~2KB, Media-Announcements, etc.) wuerden bei UDP die MTU sprengen. OS-Level IP-Fragmentierung funktioniert hinter NAT oft nicht zuverlaessig.

### App-Level-Fragmentierung

```dart
class UdpFragmenter {
  static const maxFragmentSize = 1200; // bytes

  List<Uint8List> fragment(Uint8List payload) {
    if (payload.length <= maxFragmentSize) return [payload];

    final fragments = <Uint8List>[];
    final totalFragments = (payload.length / maxFragmentSize).ceil();

    for (var i = 0; i < totalFragments; i++) {
      final start = i * maxFragmentSize;
      final end = min(start + maxFragmentSize, payload.length);
      // Header: [2B fragmentId][1B index][1B total][data]
      final header = Uint8List(4);
      header[0] = fragmentId >> 8;
      header[1] = fragmentId & 0xFF;
      header[2] = i;
      header[3] = totalFragments;
      fragments.add(Uint8List.fromList([...header, ...payload.sublist(start, end)]));
    }
    return fragments;
  }
}
```

### Jedes Fragment einzeln per RUDP Light

- Jedes Fragment bekommt einen eigenen ACK (DELIVERY_RECEIPT)
- Bei Verlust: nur das verlorene Fragment neu anfordern
- Empfaenger reassembliert nach Empfang aller Fragmente

### Abgrenzung zu Reed-Solomon

| | App-Level-Fragmentierung | Reed-Solomon |
|---|---|---|
| **Zweck** | Grosse Payloads per UDP senden | Offline-Zustellung + Backup |
| **Wann** | Payload > 1200 bytes, Peer ONLINE | Peer OFFLINE |
| **Redundanz** | Keine (1:1) | 1.43x (N=10, K=7) |
| **ACK** | Pro Fragment (RUDP Light) | Pro Fragment (FRAGMENT_STORE_ACK) |

---

## 11. TCP entfernt, TLS bleibt (V3.2)

### ALT (v2.9 — v3.0)

- TCP parallel zu UDP bei >1200B Payloads
- TCP als allgemeiner Fallback
- TLS nach 5/15 konsekutiven UDP-Fehlern

### NEU (v3.2): TCP entfernt

TCP wurde **komplett aus dem Code entfernt**. Gruende:

1. **TCP kann nicht relayed werden** — kein Relay, kein Multi-Hop, kein Default-Gateway
2. **TCP kann nicht offline zugestellt werden** — kein Store-and-Forward
3. **RUDP Light reicht** — DELIVERY_RECEIPT bestaetigt Zustellung, Per-Message KEM + SHA-256 garantieren Integritaet
4. **App-Level-Fragmentierung** loest das >1200B Problem ohne TCP
5. **Ein Transport fuer alles** — Text, Bilder, Audio, Video, Dateien: alles per UDP + RUDP Light

### TLS-Fallback bleibt (Anti-Zensur)

TLS auf **demselben Port wie UDP** (V3.1.71, davor Port+2) bleibt als letztes Mittel wenn UDP komplett blockiert ist (Corporate Firewalls, zensierte Laender). Aktiviert nach 15 konsekutiven UDP-Fehlern. Periodische UDP-Probes versuchen Rueckkehr zum normalen Pfad. Kernel handhabt UDP (SOCK_DGRAM) und TCP (SOCK_STREAM) in getrennten Namespaces, sodass dieselbe Port-Nummer fuer beide Protokolle kein Bind-Konflikt ist.

Fuer zukuenftige Skalierung (Millionen Peers) ist ein **Sliding-Window Congestion Control** auf RUDP-Light-Ebene geplant.

---

## 12. Reed-Solomon Fragment-Retention

### Klarstellung: Zweck

Reed-Solomon ist **NICHT** fuer Netzwerkausfaelle waehrend der Uebertragung. Es ist fuer:

1. **Offline-Zustellung:** Ziel-Node ist offline → Fragmente auf DHT-Nachbarn verteilen
2. **Recovery-Backup:** Fragmente dienen als verteiltes Backup fuer Chat-Recovery

### Offline-Zustellung Ablauf

1. Ziel-Node ist offline
2. Nachricht in 10 Fragmente splitten (N=10, K=7)
3. Auf 10 Nodes **in DHT-Naehe des Ziels** verteilen (XOR-Distanz)
4. Ziel kommt online → fragt bei DHT-Nachbarn: "Was gibt's fuer mich?"
5. 7 von 10 antworten reicht → Nachricht rekonstruiert
6. **Fragmente werden NICHT sofort geloescht** (dienen als Backup)

### Fragment-Retention: 7 Tage

- Fragmente bleiben **7 Tage** auf den speichernden Nodes
- Loeschung nach 7 Tagen oder wenn beide Chat-Partner die Nachricht geloescht/archiviert haben
- Fuer aeltere Nachrichten: Recovery ueber Kontakt-Partner (die haben den kompletten Chat)
- Passt zur Designentscheidung "Kontakte = dein Backup"

### Warum nicht 30 Tage?

30 Tage waeren zu viel Storage-Last auf fremden Nodes. 7 Tage sind ein guter Kompromiss:
- Kurzfristiger Ausfall (Stunden/Tage): Fragmente verfuegbar
- Langfristiger Ausfall (Wochen): Recovery ueber Kontakte

---

## 13. Routing-Tabellen-Limit

### Problem

Bei Milliarden Nutzern mit mehreren Geraeten kann die Routing-Tabelle nicht unbegrenzt wachsen.

### Dreistufiges Modell

```
Routing Table (max ~2.100 Eintraege):

  1. Kontakt-Routen (IMMER behalten):           max 1.000
     → Direkte Kontakte, muessen immer erreichbar sein
     → NIE evicten (User hat sie aktiv hinzugefuegt)

  2. Transit-Routen (Kademlia k-Buckets):        max ~640
     → 256 Buckets x ~20 Eintraege, logarithmisch verteilt
     → Fuer Relay/Forwarding fremder Nachrichten
     → Bei 1 Mrd. Nodes: ~30 Buckets aktiv belegt
     → Eviction: Kademlia-Regeln (aeltesten anpingen, bei Timeout ersetzen)

  3. Channel-Routen (temporaer):                  max 500
     → Subscriber in eigenen Channels
     → Eviction: LRU + hoechste Cost zuerst raus
```

### Eviction-Policy

- **Kontakt-Routen:** Nie evicten
- **Transit-Routen:** Kademlia (k-Bucket voll → aeltesten anpingen → bei Timeout ersetzen)
- **Channel-Routen:** LRU (Least Recently Used) + hoechste Cost zuerst

---

## 14. Store-and-Forward (Push-basiert)

### Konzept

Wenn Direct und Relay fehlschlagen, werden ganze Nachrichten (nicht fragmentiert!) auf bis zu 3 bestaetigte Online-Peers gespeichert.

### Push-Zustellung

Kein Polling! Wenn der Empfaenger irgendwann ein Paket an den speichernden Peer schickt, erkennt dieser die live UDP-Adresse und **pusht sofort** alle gespeicherten Nachrichten.

### Einziger Poll: Beim Service-Start

8 Sekunden nach Dienststart sendet der Node `PEER_RETRIEVE` an alle Peers — einmalig. Das ist der **EINZIGE** Poll im gesamten System (plus nach Netzwerkwechsel).

### Budget

- Max 50 Nachrichten pro Empfaenger
- Max 100 KB pro Nachricht
- TTL: 7 Tage

---

## 15. Adress-Propagation

### Wann eigene Adresse propagieren?

| Ereignis | Aktion |
|----------|--------|
| Netzwerkwechsel | Sofort ROUTE_UPDATE an alle Nachbarn |
| Neuer Hole Punch | Sofort ROUTE_UPDATE (neue oeffentliche Erreichbarkeit) |
| Nach QR-Scan (als Scanner) | Eigene Erreichbarkeit an alle gelernten Peers |
| Route-Down erkannt (3x Timeout) | Poison Reverse an alle Nachbarn |
| Safety-Net | Alle 1h einmal komplett austauschen |

### Wann NICHT propagieren?

- Kein periodisches Broadcasting (ausser 1h Safety-Net)
- Kein Discovery-Dauerfeuer
- Kein "Schrotflinten-Send" an alle Adressen

---

## 16. Relay-Aware ACK-Tracking (V3.1)

### Problem

Die V3.0-Implementierung behandelt Relay-Sends wie Direct-Sends: `sendEnvelope` gibt `true` zurueck sobald das UDP-Paket am Relay-Hop ankommt, aber ohne End-to-End-Bestaetigung. RUDP Light (DELIVERY_RECEIPT) wird nur bei Direct-Sends getrackt, nie bei Relay/DV-Sends. Das fuehrt zu:

1. **Falsches Route-DOWN:** Direct-Send-Versuche an unerreichbare LAN-IPs (z.B. Handy → Alice's 192.168.10.x) loesen 3x ACK-Timeout → Route DOWN fuer ALLE Routen zu Alice (auch die funktionierende Relay-Route via Bootstrap)
2. **Kein Recovery:** Nach Route-DOWN werden alle Routen permanent geloescht. Kein Re-Discovery ausser dem 1h Safety-Net
3. **Zu kurze Timeouts:** 2×RTT+50ms (Default 2050ms) ist fuer Relay-Pfade (4+ Hops) zu knapp

### Loesung: 6 Korrekturen

#### 16.1 ACK-Tracking auf Relay-Sends

`_sendViaNextHop()`, `_sendViaRelay()`, und `_sendViaSpecificRelay()` muessen `_trackAck()` aufrufen fuer den FINALEN Empfaenger (nicht den Relay-Hop). Die DELIVERY_RECEIPT vom Empfaenger kommt per Relay zurueck und loest den Tracker auf.

#### 16.2 Relay-angepasste Timeouts

```
Direct:  2 × RTT + 50ms  (wie bisher)
Relay:   max(2 × RTT × hopCount, 8000ms)  (Minimum 8s, Maximum 30s)
```

#### 16.3 Chirurgisches Route-DOWN

`onRouteDown` bekommt `viaNextHopHex` Parameter. `markRouteDown(peerHex, viaNextHopHex: ...)` markiert NUR die spezifische Route als DOWN, nicht alle. Wenn Alternativ-Routen existieren, wird `PeerInfo.consecutiveRouteFailures` NICHT auf 3 gesetzt.

#### 16.4 Route-Recovery nach DOWN

Tote Routen werden NICHT sofort geloescht, sondern 5 Minuten lang mit `cost=infinity` beibehalten. Eingehende ROUTE_UPDATEs von Nachbarn koennen sie wiederbeleben.

#### 16.5 Private-IP-Filterung

`_sendDirectToPeer()` ueberspringt private IP-Adressen, wenn der Sender kein lokales Interface im selben Subnetz hat. Verhindert sinnlose Direct-Sends von Mobilfunk an LAN-IPs.

#### 16.6 CR-Retry prueft Route-Gesundheit

`_retryPendingContactRequests()` ueberspringt Peers ohne lebende DV-Route. Kein blindes Haemmern auf kaputte Pfade.

### Per-Route Failure-Tracking

Statt eines einfachen Per-Peer-Zaehlers nutzt der AckTracker einen zusammengesetzten Schluessel:

```
Key: "${peerHex}|${viaNextHopHex ?? 'direct'}"
```

3x Timeout auf dem gleichen Schluessel → nur DIESE Route wird DOWN markiert. Ein ACK auf IRGENDEINER Route setzt alle Zaehler fuer den Peer zurueck (Peer ist erreichbar).

### Beispiel-Szenario: Handy → Bootstrap → Alice

```
1. Handy scannt Alice's QR (LAN-IP 192.0.2.201 + Bootstrap als Seed)
2. sendEnvelope: DV-Route via Bootstrap → _sendViaNextHop an Bootstrap
3. _trackAck: msgId, recipient=Alice, viaNextHop=Bootstrap, timeout=8s
4. Bootstrap: RELAY_FORWARD → Alice (LAN)
5. Alice: empfaengt CR, sendet DELIVERY_RECEIPT via gelernter Relay-Route
6. DELIVERY_RECEIPT kommt per Relay am Handy an
7. AckTracker.handleAck: loest pending ACK auf → Route bestaetigt
8. Kein Route-DOWN, kein Poison Reverse
```

---

## 17. Implementierungsplan

### Session 5: Relay-Aware ACK-Tracking (V3.1)

**Betroffene Dateien:**
- `lib/core/network/peer_info.dart` — `PeerAddress.isReachableFromCurrentNetwork`
- `lib/core/network/dv_routing.dart` — `hasAliveRouteTo()`, Route-Recovery-Graceperiod
- `lib/core/network/ack_tracker.dart` — Per-Route-Tracking, Relay-Timeouts, `viaNextHopHex` in Callbacks
- `lib/core/node/cleona_node.dart` — ACK-Tracking in Relay-Sends, chirurgisches Route-DOWN, Private-IP-Filter
- `lib/core/service/cleona_service.dart` — CR-Retry mit Route-Health-Check

**Schritte (in Kompilier-Reihenfolge):**
1. `peer_info.dart`: `isReachableFromCurrentNetwork` Getter hinzufuegen
2. `dv_routing.dart`: `hasAliveRouteTo()`, Route-Removal-Graceperiod 5 Min
3. `ack_tracker.dart`: `_PendingAck.viaNextHopHex/estimatedHops`, `computeTimeout()`, Per-Route-Zaehler, `onRouteDown` Signatur
4. `cleona_node.dart`: `_trackAck` Relay-Context, `onRouteDown` chirurgisch, ACK in `_sendViaNextHop`/`_sendViaRelay`, Private-IP-Filter
5. `cleona_service.dart`: CR-Retry Route-Health-Check
6. Smoke-Tests: Relay-ACK, Surgical-Route-DOWN, Recovery, Private-IP-Filter, CR-Retry, End-to-End

**Abhaengigkeiten:** Session 5 baut auf Session 4 auf. Keine Protokoll-Aenderungen, keine neuen MessageTypes, volle Rueckwaertskompatibilitaet.

### Session 2: Fundament (sequentiell, keine Parallelisierung)

**Betroffene Dateien:**
- `lib/core/network/peer_info.dart` — Route-Datenstruktur, Cost-Modell
- `lib/core/node/cleona_node.dart` — Routing-Tabelle, Distance-Vector-Logik
- `lib/core/network/lan_discovery.dart` — 3x Burst, dann Stopp
- `lib/core/network/contact_seed.dart` — Public IP + bestaetigte Peers
- `lib/ui/screens/qr_contact_screen.dart` — QR mit Public IP

**Schritte:**
1. `Route` Klasse erstellen in `peer_info.dart`
2. Routing-Tabelle in `CleonaNode` um Route-Verwaltung erweitern
3. `ROUTE_UPDATE` Protobuf definieren
4. Bellman-Ford + Split Horizon + Poison Reverse implementieren
5. Default-Gateway-Auswahl implementieren
6. Discovery auf 3x Burst umstellen
7. QR-Code mit Public IP + bestaetigten Peers
8. Smoke-Tests fuer Routing

### Session 3a: sendEnvelope + RUDP Light (parallelisierbar)

**Betroffene Dateien:**
- `lib/core/node/cleona_node.dart` — sendEnvelope komplett neu
- `lib/core/network/ack_tracker.dart` — Route-Down-Zaehler
- `lib/core/network/reachability_probe.dart` — entfaellt (durch Routing ersetzt)

**Schritte:**
1. `sendEnvelope()` auf Route-basiertes Senden umstellen
2. TTL (Hop Limit) im RelayForward implementieren
3. Route-Down nach 3x RUDP Timeout + Poison Reverse
4. Timer-basiertes Relay-Expiry entfernen
5. Priorisiertes Senden (billigste Route zuerst, nicht Schrotflinte)

### Session 3b: NAT Hole Punch + Fragmentierung (parallelisierbar)

**Betroffene Dateien:**
- `lib/core/network/nat_traversal.dart` — Hole Punch + Keepalive + NAT-Probing
- `lib/core/network/udp_fragmenter.dart` — NEU: App-Level-Fragmentierung
- `lib/core/network/transport.dart` — Fragment-Reassembly

**Schritte:**
1. `HolePunchRequest`/`HolePunchNotify` Protobuf definieren
2. Koordinations-Logik in `nat_traversal.dart`
3. NAT-Timeout-Probing implementieren
4. Keepalive-Timer (einziger periodischer Verkehr!)
5. `UdpFragmenter` fuer >1200B Payloads
6. Fragment-Reassembly im Transport

### Session 4: Integration + Bereinigung (sequentiell)

**Betroffene Dateien:**
- `lib/core/service/cleona_service.dart` — Reed-Solomon 7-Tage-Retention
- `lib/core/network/transport.dart` — UDP-only (TCP/TLS entfernt V3.2)
- `lib/core/node/cleona_node.dart` — TLS-Fallback entfernt (V3.2)
- Alle Smoke-Tests + E2E-Tests

**Schritte:**
1. Reed-Solomon Fragment-TTL auf 7 Tage
2. Fragment-Loeschung nur bei beiderseitigem Loeschen oder >7 Tage
3. TCP/TLS komplett entfernt (V3.2)
4. Integration aller Aenderungen
6. Smoke-Tests aktualisieren
7. Deploy + Live-Test

---

## Abhaengigkeiten zwischen Sessions

```
Session 2 (Fundament)
    │
    ├──► Session 3a (sendEnvelope + RUDP)  ─┐
    │                                        ├──► Session 4 (Integration)
    └──► Session 3b (Hole Punch + Fragment) ─┘
```

Session 3a und 3b koennen parallel laufen, da sie unterschiedliche Dateien betreffen. Session 4 braucht beide.

# Cleona — Öffentliche Channels & Content-Moderation

> **Status:** Implementiert & Live-getestet (Stand 29.03.2026)
> **Offene Themen:** Keine kritischen — siehe [Offene Punkte](#offene-punkte) für Feinabstimmung

## Überblick

Erweiterung des bestehenden Channel-Systems (v2.5: private Channels mit Pairwise Fan-out)
um **öffentliche Channels** mit Suche, Content-Rating und dezentraler Moderation.

## Channel-Tab Reiter

| Reiter | Inhalt |
|--------|--------|
| **Abonnierte Kanäle** | Channels, die die aktive Identity abonniert hat |
| **Eigene Kanäle** | Channels, bei denen die aktive Identity Owner/Admin ist |
| **Suche** | Durchsuchbarer Index aller öffentlichen Channels im Netz |

**Standard-Tab beim allerersten App-Start:** Suche (damit neue Nutzer Channels entdecken)

## Channel-Erstellung

### Pflichtfelder
- **Name** — muss netzweit eindeutig sein (siehe [Channel-Index](#channel-index-im-dht))
- **Sprache** — Dropdown: DE / EN / ES / HU / SV / Andere/Multilingual
- **Öffentlich / Privat** — Toggle

### Optionale Felder
- **Bild** — Channel-Avatar
- **Beschreibung** — Freitext

### Content-Rating (nur bei öffentlichen Channels)
- **"Nicht jugendfrei"** Toggle — erscheint nur wenn "Öffentlich" gewählt
- **Standardmäßig AN** (= nicht jugendfrei) — muss explizit deaktiviert werden,
  um den Channel auch für Minderjährige freizugeben
- Owner/Admin kann Name, Beschreibung und Content-Rating nachträglich ändern

## Rollen & Zugriff

### Private Channels (bestehend, v2.5)
| Rolle | Lesen | Posten | Verwalten |
|-------|-------|--------|-----------|
| Owner | ✓ | ✓ | ✓ |
| Admin | ✓ | ✓ | teilweise |
| Subscriber | ✓ | ✗ | ✗ |

### Öffentliche Channels (neu)
| Rolle | Lesen | Posten | Verwalten |
|-------|-------|--------|-----------|
| Owner | ✓ | ✓ | ✓ |
| Admin | ✓ | ✓ | teilweise |
| Subscriber | ✓ | ✗ | ✗ |
| **Jeder** | ✓* | ✗ | ✗ |

\* **Einschränkung:** Bei Channels mit "Nicht jugendfrei"-Flag dürfen nur Identitäten
mit aktiviertem "Ich bin über 18"-Flag lesen. Ohne dieses Flag:
- Channel taucht **nicht in der Suche** auf
- Abonnieren/Lesen wird **verweigert**

## Channel-Index im DHT

Ein komprimierter, netzweit replizierter Index aller öffentlichen Channel-Namen.

### Datenstruktur pro Eintrag (~200-300 Bytes)
```
{
  name: String,                   // Channel-Name
  id: Hash(CreatorPubKey),        // Eindeutige Channel-ID
  language: String,               // Sprache (DE/EN/ES/HU/SV/multi)
  isAdult: bool,                  // Content-Rating
  description: String?,           // Kurzbeschreibung (gekürzt)
  subscriberCount: int,           // Ungefähre Abonnentenzahl
  badBadgeLevel: int,             // 0 = kein Badge, 1-3 = Stufe
  badBadgeSince: timestamp?,      // Wann der aktuelle Badge gesetzt wurde
  correctionSubmitted: timestamp? // Wann Admin korrigiert hat (Start Bewährung)
}
```

### Eindeutigkeit & Konsistenz
- **DHT-Key:** `SHA-256("channel-name:" + lowercase(name))`
- **First-Come-First-Served:** Wer den Namen zuerst registriert, behält ihn
- **Squatting-Schutz:** Identity muss mindestens 7 Tage im Netz aktiv sein bevor
  Channel-Erstellung erlaubt ist
- **Speicher:** Bei 10.000 Channels ca. 3 MB — als Bloom-Filter für
  Namensprüfung deutlich weniger

### Suchfunktion
- Nutzer können nach Name, Sprache und Content-Rating filtern
- NSFW-Channels werden bei Identitäten ohne "Ich bin über 18"-Flag ausgeblendet

## Dezentrale Content-Moderation

### Meldungskategorien

| Kategorie | Beschreibung | Verfahren |
|-----------|-------------|-----------|
| **Nicht jugendfrei** | Channel als jugendfrei markiert, enthält aber NSFW | Jury (Standard) |
| **Falscher Inhalt** | Inhalt entspricht nicht der Channel-Beschreibung | Jury (Standard) |
| **Illegal: Drogenhandel** | Angebote/Handel mit illegalen Substanzen | Jury (Standard) |
| **Illegal: Waffenhandel** | Angebote/Handel mit illegalen Waffen | Jury (Standard) |
| **Illegal: CSAM** | Kinderpornografie | **Sonderverfahren** (keine Jury) |
| **Illegal: Sonstiges** | Andere illegale Inhalte | Jury (Standard) |

### Meldung: Einzelner Beitrag
- Nutzer meldet einen spezifischen Post im Channel
- → **Admins des Channels werden benachrichtigt** (im Tab "Anfragen")
- → Kein Jury-Verfahren, Admins entscheiden selbst
- → **Eskalation:** Wird der gemeldete Beitrag nach 7 Tagen nicht entfernt,
  wird die Meldung automatisch zur Channel-Meldung hochgestuft

### Meldung: Gesamter Channel (alle Kategorien außer CSAM)
- Nutzer wählt eine der Kategorien
- Melder wählt **3-10 konkrete Posts** aus dem Channel als Beweismittel
- Meldecounter für die jeweilige Kategorie wird hochgezählt
- Max. Anzahl Meldungen pro Identity pro Zeitraum begrenzt (Spam-Schutz)

### Unabhängigkeits-Kriterien (Melder & Richter)

Gilt für alle Kategorien. Bestimmt, ob zwei Identitäten als "verbunden" gelten.

**Größenbasierter Schwellwert** (nicht öffentlich/privat-basiert):
```
Grenze = max(50, Gesamtnutzer × 0.05)
```

Zwei Identitäten gelten als **verbunden**, wenn sie eine gemeinsame Gruppe oder
einen gemeinsamen Channel haben, dessen Mitgliederzahl **unter** der Grenze liegt.

| Gesamtnutzer | Grenze | Beispiel |
|---|---|---|
| 200 | 50 | Minimum greift |
| 1.000 | 50 | Gruppen < 50 = verbunden |
| 10.000 | 500 | Gruppen < 500 = verbunden |
| 100.000 | 5.000 | Gruppen < 5.000 = verbunden |

**Begründung:** Nicht "öffentlich vs. privat" entscheidet über Koordinationsfähigkeit,
sondern die **relative Gruppengröße**. Eine private Gruppe mit 500 Mitgliedern sagt
genauso wenig über Koordination aus wie ein öffentlicher Channel mit 500 Abonnenten.
Ein öffentlicher Channel mit 5 Leuten ist praktisch eine private Runde.

Zusätzlich gelten **direkte Kontakte** immer als verbunden (unabhängig von Gruppengröße).

### Jury-Verfahren (Standard — alle Kategorien außer CSAM)

Wenn der Meldecounter einer Kategorie den Schwellwert erreicht:

1. **Richter-Auswahl:**
   - Zufällige Nutzer mit **derselben Spracheinstellung wie der Channel**
   - **Nicht** mit dem Channel verbunden (kein Subscriber/Admin/Owner)
   - **Nicht** mit einem der Melder **verbunden** (siehe Unabhängigkeits-Kriterien)
   - Identity muss mindestens 7 Tage im Netz aktiv sein
   - Identity muss "Ich bin über 18" aktiviert haben
   - Identity muss "Kanal-Meldungen bewerten" aktiviert haben (Standard: AN)

2. **Richter-Anzahl:**
   - **Minimum:** 5 Richter
   - **Maximum:** `min(11, verfügbare_Richter × 0.01)` — max. 1% der verfügbaren Richter
   - **Fallback:** Weniger als 5 Richter verfügbar → Schwellwert für Auslösung verdoppeln

3. **Was die Richter sehen:**
   - Channel-Name, Beschreibung, Sprache, Content-Rating
   - Die **3-10 vom Melder ausgewählten Posts** als Beweis
   - Die Meldungskategorie

4. **Abstimmung:**
   - **2/3-Mehrheit** nötig für Maßnahme
   - Optionen: Zustimmen / Ablehnen / Enthalten
   - **Enthaltung:** Richter wird ersetzt durch anderen Nutzer
   - **Timeout:** 2 Tage keine Antwort → Anfrage wird entfernt, Ersatz-Richter

5. **Keine Wiederholung:** Wer einmal für einen Channel abgestimmt hat,
   wird für denselben Channel nicht nochmal gefragt

### Konsequenzen nach Jury-Entscheidung

| Kategorie | Maßnahme bei 2/3-Zustimmung |
|-----------|---------------------------|
| **Nicht jugendfrei** | Channel wird als NSFW umgestuft, Admins werden informiert |
| **Falscher Inhalt** | Channel erhält Bad Badge (siehe [Bad Badge System](#bad-badge-system)), Admins werden informiert |
| **Illegal (nicht CSAM)** | Channel wird gelöscht (siehe [Tombstone](#channel-löschung-tombstone)), Admins werden informiert |

### Channel-Löschung (Tombstone)
- Ein **Tombstone-Eintrag** wird im DHT platziert: "Channel X gelöscht wegen illegaler Inhalte"
- Channel verschwindet aus der Suche
- Neue Abonnements werden verweigert
- Bestehende Subscriber erhalten die Lösch-Nachricht
- Inhalte auf einzelnen Nodes verfallen über TTL

### Rückmeldung an Melder
- "Deine Meldung zu Channel X wurde geprüft. Ergebnis: Maßnahme ergriffen / Keine Maßnahme"
- **Keine Details** über Abstimmungsergebnis (verhindert Reverse-Engineering)
- Nur bei Channel-Meldungen, nicht bei Einzelbeitrag-Meldungen

### Bewertungs-Anfragen (Tab "Anfragen")
- Jury-Anfragen erscheinen im Tab "Anfragen" der jeweiligen Identity
- Admins sehen dort auch Einzelbeitrag-Meldungen
- Abstimmungsergebnisse und Admin-Benachrichtigungen ebenfalls dort

## CSAM-Sonderverfahren

**Dilemma:** Bei CSAM (Kinderpornografie) ist schon das Betrachten strafbar.
Wir können den Inhalt nicht an Richter senden. Daher: **keine Jury**, stattdessen
abgestufte Reaktion über die Anzahl unabhängiger Melder.

### Abgestufte Reaktion

| Stufe | Auslöser | Maßnahme |
|-------|----------|----------|
| **1** | Erste Meldung | Wird registriert, nichts Sichtbares passiert |
| **2** | `max(10, Subscriber × 0.05)` unabhängige Meldungen | Channel **temporär aus Suche ausgeblendet** (14 Tage Frist), Admin kann Widerspruch einlegen |
| **3** | `max(20, Subscriber × 0.10)` unabhängige Meldungen | Channel **permanent gelöscht** (Tombstone) |

### Beispiel-Schwellwerte

| Channel-Subscriber | Temporär (Stufe 2) | Permanent (Stufe 3) |
|---|---|---|
| 50 | 10 Melder | 20 Melder |
| 200 | 10 Melder | 20 Melder |
| 500 | 25 Melder | 50 Melder |
| 5.000 | 250 Melder | 500 Melder |

**Temporäre Ausblendung (Stufe 2):**
- Admins werden informiert: "Channel wegen mehrfacher Inhaltsmeldung vorläufig ausgeblendet"
- Keine Details zur Kategorie (kein Hinweis auf CSAM)
- Wenn innerhalb von 14 Tagen kein Schwellwert 3 erreicht wird → Channel wird wieder eingeblendet
- Melder erhalten: "Meldung geprüft, keine Maßnahme"
- **Admin-Widerspruch:** Bei temporärer Ausblendung kann der Admin Widerspruch einlegen.
  Dann wird eine Jury einberufen, die jedoch **nicht den Content sieht**, sondern:
  - Channel-Name, Beschreibung, Posting-Frequenz
  - Die Textbeschreibungen der Melder (was sie gesehen haben wollen)
  - Ob der Channel thematisch plausibel zu CSAM-Vorwürfen passt
  Die Jury entscheidet: "Plausibel" (Ausblendung bleibt) oder "Konstruiert" (Channel wird wiederhergestellt).
  Dies gibt legitimen Channel-Betreibern eine Verteidigungsmöglichkeit gegen koordinierte Falschmeldungen.

**Permanente Löschung (Stufe 3):**
- Tombstone im DHT (wie bei anderen illegalen Inhalten)
- Admins werden informiert: "Channel wegen illegaler Inhalte gelöscht"

### Erhöhte Melder-Qualifikation (nur CSAM)

CSAM-Meldungen sind die schärfste Waffe im System (sofortige Löschung ohne Jury).
Daher gelten **strengere Anforderungen** als bei anderen Kategorien:

| Kriterium | Standard-Meldung | CSAM-Meldung | Begründung |
|---|---|---|---|
| Identity-Alter | 7 Tage | **30 Tage** | Höhere Zeitinvestition |
| Bidirektionale Konversationen | — | **mind. 10 Partner** | Bot kann schwer faken |
| Empfangene Nachrichten | — | **mind. 100** | Echte Menschen interagieren |
| Langzeit-Kontakte (14+ Tage) | — | **mind. 3** | Dauerhafte Beziehungen |
| "Ich bin über 18" | — | **Pflicht** | Minderjährige sollen CSAM nicht melden |
| Melde-Sperre nach Meldung | — | **7 Tage** (alle Kategorien) | Kosten für den Melder |

**Warum empfangene Nachrichten statt gesendete?** Ein Bot kann Nachrichten senden,
aber schwer echte Menschen dazu bringen, ihm regelmäßig zu antworten.

### Anti-Sybil: Social Graph Reachability Check

**Problem:** Open-Source-Code ermöglicht Bot-Software, die Fake-Identitäten erstellt,
soziale Aktivität simuliert und koordiniert falsche CSAM-Meldungen abgibt.

**Lösung:** Netzwerk-seitige Validierung der sozialen Verankerung.

#### Prinzip: Kleine-Welt-Eigenschaft

In echten sozialen Netzen ist jeder mit jedem über ~6 Ecken verbunden.
Bot-Cluster bilden **isolierte Inseln** ohne Brücken zum Hauptgraph.

#### Algorithmus: Random Walk Reachability

```
1. CSAM-Meldung geht ein
2. Meldung wird an K zufällige Validator-Nodes im DHT verteilt
3. Jeder Validator prüft:
   "Kann ich diese Identity über meinen Sozialgraphen
    innerhalb von 5 Hops erreichen?"
4. Ergebnis:
   ≥ 60% der Validators erreichen den Melder → Meldung akzeptiert
   < 60% → Meldung abgelehnt ("Identity nicht ausreichend vernetzt")
```

#### Warum das Bot-resistenter ist

**Echter Nutzer:**
```
Alice → 5 Kontakte → je 5 weitere → je 5 weitere ...
Nach 3 Hops: ~125 erreichbare Identitäten
Nach 5 Hops: tausende
→ Zufälliger Validator findet fast immer einen Pfad ✓
```

**Bot-Cluster:**
```
Puppet_Mo → 5 andere Puppets → 5 weitere Puppets → Sackgasse
Kein Pfad zum echten Netzwerk
→ Kein Validator findet einen Pfad ✗
```

**Das Dilemma des Angreifers:**
- Bots untereinander vernetzen → isolierter Cluster → erkannt
- Bots mit echten Menschen vernetzen → skaliert nicht (echte Menschen müssen mitspielen)
- "Brücken-Account" zum echten Netz → verbindet den ganzen Cluster → Größenregel greift

#### Privacy: Bloom-Filter-basiert

Die Validators lernen **nicht** den kompletten Sozialgraphen:
- Jeder Node pflegt einen Bloom-Filter seiner Kontakte bis Tiefe 5
- Reachability-Prüfung ist ein **lokaler Lookup**, keine Graph-Traversierung über das Netz
- Bloom-Filter wird periodisch aktualisiert (z.B. täglich)
- Antwort ist nur ja/nein, ohne den Pfad offenzulegen

#### Netzwerk-Validierung, nicht App-Validierung

**Kritisch:** Alle Prüfungen werden von **empfangenden Nodes** durchgeführt,
nicht von der App des Melders. Ein modifizierter Client (Fork) kann die Meldung
abschicken, aber das Netzwerk ignoriert sie wenn die Kriterien nicht erfüllt sind.

| Ebene | Modifizierbar? | Durchsetzung |
|---|---|---|
| Eigene App | Ja (Open Source) | Keine — nutzlos |
| **Empfangende Nodes** | Nein (andere Nutzer) | **Stark** — Netzwerk lehnt ab |

### Anti-Missbrauch: Falsche CSAM-Meldungen (Option C)

Kombinierter Schutz gegen Missbrauch:

1. **Pfand:** Jede CSAM-Meldung kostet 7 Tage Melde-Sperre in **allen** Kategorien
2. **Strike:** Nur wenn nachweislich missbräuchlich:
   - Channel wurde wiederhergestellt (Schwellwert nicht erreicht)
   - UND der Melder hat den Channel erst kurz vor der Meldung entdeckt
3. **3 Strikes** = Identity darf keine CSAM-Meldungen mehr abgeben

## Bad Badge System

Signalisiert potenziellen Abonnenten: "Vorsicht, der Inhalt dieses Channels stimmt nicht
mit der Beschreibung überein." Ein **Vertrauenssignal**, kein Straf-Mechanismus.

### Lifecycle (Wiederholungsbasiert)

1. **Badge wird gesetzt:** Jury bestätigt "Falscher Inhalt" mit 2/3-Mehrheit
2. **Admin wird benachrichtigt** (Tab "Anfragen")
3. **Badge bleibt** bis der Admin Name/Beschreibung korrigiert hat
4. **Nach Korrektur:** Badge wechselt in Status "Korrektur eingereicht",
   Bewährungsphase startet
5. **Bewährungsphase ohne neue bestätigte Meldung:** Badge verschwindet
6. **Neue bestätigte Meldung in der Bewährungsphase:** Eskalation zur nächsten Stufe

### 3-Stufen-Eskalation

| Stufe | Auslöser | Markierung | Bewährung |
|-------|----------|------------|-----------|
| **1** | Erste bestätigte Meldung | "Inhalt fragwürdig" | 30 Tage nach Korrektur |
| **2** | Zweite bestätigte Meldung in der Bewährung | "Wiederholt irreführend" | 90 Tage nach Korrektur |
| **3** | Dritte bestätigte Meldung | **Permanent**, nicht entfernbar | — |

Der Admin hat zwei Chancen sich zu bessern. Beim dritten Mal ist klar: Absicht.

### Auswirkung auf die Suche

| Badge-Stufe | Anzeige in Suchergebnissen |
|-------------|---------------------------|
| **Kein Badge** | Normale Anzeige |
| **Stufe 1-2** | Weiter unten sortiert + visueller Hinweis (Warnsymbol) |
| **Stufe 3 (permanent)** | Ganz am Ende der Suche + deutlich sichtbarer Warnhinweis |

**Wichtig:** Channels werden **nie ausgeblendet** wegen Bad Badge — der Nutzer
entscheidet selbst. Nur Sortierung und visuelles Signal ändern sich.

## Identity-Einstellungen (Bezug)

Im **Identity Detail Screen** (geplant v2.6):
- **"Ich bin über 18"** Toggle — ganz unten, erst durch Scrollen sichtbar
- **"Kanal-Meldungen bewerten"** — erscheint NUR wenn "Ich bin über 18" aktiviert
  - Standardmäßig AN (Opt-in bei Volljährigkeit)
  - Kann deaktiviert werden (Opt-out)
  - Bei Identitäten ohne "Ich bin über 18" **nicht sichtbar** und automatisch deaktiviert

## Moderation-Timer (Zeitlimit-Durchsetzung)

Alle zeitbasierten Moderations-Limits werden durch einen periodischen Timer (`_moderationTimer`) in `CleonaService` durchgesetzt. Der Timer prüft pro Tick:

1. **Jury-Vote-Timeout** — Laufende Jury-Sessions ohne genügend Votes werden nach Ablauf aufgelöst
2. **Badge-Bewährung** — Channels mit Korrektur (`correctionSubmitted`) und abgelaufener Bewährungsfrist bekommen ihr Badge-Level gesenkt
3. **CSAM-Temp-Hide** — Temporäre Ausblendungen werden nach `csamTempHideDuration` aufgehoben
4. **Einzelbeitrag-Eskalation** — Offene Post-Reports eskalieren nach Timeout zu Channel-Reports

**Timer-Interval:** Adaptiv — 1/6 des kürzesten Timeouts, min 5s, max 5min. Bei Test-Preset (Sub-5s-Timeouts): 1s Tick.

## Offene Punkte

### Feinabstimmung (nicht-kritisch)
- **Schwellwerte** für Jury-Auslösung (wie viele Meldungen nötig?) — abhängig von Netzwerkgröße
- **CSAM-Schwellwerte** — dynamische Formel entschieden, Feinabstimmung der Faktoren (0.05/0.10) bei Bedarf
- **Bloom-Filter-Refresh-Intervall** — täglich? Bei Kontaktänderung?
- **Validator-Anzahl K** für Social Graph Reachability — wie viele Nodes befragen?
- **Spendenschutz bei Forks** — signierte DHT-Einträge vs. andere Ansätze (siehe CLAUDE.md)

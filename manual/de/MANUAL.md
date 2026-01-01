# Cleona Chat -- Benutzerhandbuch

Version 4.2 | Stand November 2026

---

## Inhaltsverzeichnis

1. [Was ist Cleona Chat?](#1-was-ist-cleona-chat)
2. [Erste Schritte](#2-erste-schritte)
3. [Kontakte](#3-kontakte)
4. [Nachrichten](#4-nachrichten)
5. [Gruppen](#5-gruppen)
6. [Oeffentliche Kanaele](#6-oeffentliche-kanaele)
7. [Anrufe](#7-anrufe)
8. [Kalender](#8-kalender)
9. [Umfragen](#9-umfragen)
10. [Mehrere Identitaeten](#10-mehrere-identitaeten)
11. [Mehrere Geraete](#11-mehrere-geraete)
12. [Wiederherstellung](#12-wiederherstellung)
13. [Einstellungen](#13-einstellungen)
14. [Sicherheit](#14-sicherheit)
15. [Software-Updates](#15-software-updates)
16. [Haeufige Fragen](#16-haeufige-fragen)

---

## 1. Was ist Cleona Chat?

### Dein Messenger, deine Daten

Cleona Chat ist ein Messenger, der komplett ohne zentralen Server funktioniert.
Deine Nachrichten reisen von deinem Geraet zum Geraet deines Gegenueber --
ohne Umweg ueber einen Firmensitz, ohne Cloud, ohne Datenzentrum. Wo
unterwegs ein anderes Geraet hilft, reicht es nur verschluesselte Pakete
weiter. Kein Unternehmen kann deine Nachrichten lesen, speichern oder
weitergeben, weil schlicht kein Unternehmen dazwischensteht.

### Kein Konto, keine Telefonnummer

Bei Cleona brauchst du weder eine Telefonnummer noch eine E-Mail-Adresse, um
dich anzumelden. Deine Identitaet besteht aus einem kryptografischen
Schluesselpaar, das beim ersten Start automatisch auf deinem Geraet erzeugt
wird. Das bedeutet: Niemand kann dich ueber deine Telefonnummer oder
E-Mail-Adresse ausfindig machen, es sei denn, du gibst deine Kontaktdaten
selbst weiter.

### Zukunftssichere Verschluesselung

Cleona nutzt sogenannte Post-Quantum-Verschluesselung. Das heisst: Selbst
kuenftige Quantencomputer koennten deine Nachrichten nicht knacken. Du musst
die Details nicht verstehen -- wichtig ist nur, dass deine Kommunikation nach
dem aktuellen Stand der Technik bestmoeglich geschuetzt ist.

### Wie funktioniert das ohne Server?

Das Netz von Cleona besteht nur aus den Geraeten seiner Nutzer. Jedes Geraet
ist ein Knoten, kein Knoten ist wichtiger als ein anderer, und jeder kennt nur
seine Nachbarn. Vier Dinge machen dieses Netz besonders:

- **Kein fester Punkt.** In der App steht keine Serveradresse, und das Netz
  haengt von keinem einzelnen Knoten ab. Es gibt nichts, was man abschalten
  koennte, um Cleona abzuschalten.
- **Sofort.** Deine Nachricht geht in dem Moment los, in dem du sie
  abschickst. Sie wartet auf keinen Takt und auf nichts anderes.
- **Tarnung nebenher.** Dein Geraet sendet laufend kleine Tarnpakete, damit
  von aussen nicht zu erkennen ist, wann du wirklich schreibst. Keine
  Nachricht haengt davon ab -- die Tarnung laeuft nur daneben.
- **Codes statt Namen.** Wer eine Nachricht weiterreicht, sieht nur einen
  Code, der sich jeden Tag aendert. Im Normalfall kennt keiner von ihnen
  Absender und Empfaenger zugleich; die Ausnahmen stehen in Kapitel 14.

**Drei Wege, alle gleichzeitig.** Wenn du eine Nachricht abschickst,
probiert Cleona nicht einen Weg nach dem anderen, sondern alle passenden
auf einmal. Sobald dein Gegenueber den Empfang bestaetigt, werden die
anderen abgebrochen.

1. **Im selben Netz:** Seid ihr im selben WLAN, geht die Nachricht direkt
   hinueber.
2. **Ueber die festen Nachbarn:** Im Internet gibt dein Geraet die
   Nachricht an seinen festen Nachbarn. Der reicht sie an die festen Nachbarn
   deines Gegenueber weiter (bis zu drei auf einmal), und einer davon liefert
   sie aus.
3. **Briefkasten:** Ist dein Gegenueber offline, legt Cleona die Nachricht
   verschluesselt bei drei Nachbarn ab. Dort bleibt sie bis zu 7 Tage. Kommt
   dein Gegenueber wieder online, holt er sie ab.

**Wie kommst du ins Netz?** In der App steht keine Serveradresse. Deinen
Einstieg bekommst du von deinem ersten Kontakt: Seine Einladung enthaelt die
Adressen, ueber die dein Geraet seine ersten Nachbarn findet. Im selben WLAN
finden sich Cleona-Geraete auch selbst. Von da an lernt dein Geraet mit
jedem Nachbarn weitere kennen.

### Plattformen

Cleona ist verfuegbar fuer Android, iOS, macOS, Linux und Windows. Auf
Computern und auf Android kommen Nachrichten und Anrufe innerhalb von Sekunden
an. Auf dem iPhone gilt das, solange die App geoeffnet ist. Ist sie nicht
geoeffnet, weckt iOS sie nur gelegentlich kurz; wann, bestimmt iOS. Dann holt
Cleona alles Aufbewahrte ab und zeigt eine Mitteilung mit Zahl am App-Symbol.
Anrufe erreichen ein iPhone mit nicht geoeffneter App nicht. Das ist eine
Regel von Apple, kein Fehler in Cleona.

---

## 2. Erste Schritte

### App installieren

**Android:**
1. Lade die APK-Datei von der Cleona-Website oder von GitHub Releases herunter.
2. Oeffne die Datei auf deinem Handy. Falls noetig, erlaube die Installation
   aus unbekannten Quellen (Android fragt dich automatisch).
3. Tippe auf "Installieren" und warte, bis die Installation abgeschlossen ist.

**iOS:**
1. Oeffne den TestFlight-Einladungslink auf deinem iPhone.
2. Tippe auf "Installieren". TestFlight ist Apples offizieller Weg, um
   Beta-Apps zu verteilen.
3. Nach der Installation findest du Cleona auf deinem Homescreen.

**macOS:**
1. Lade die DMG-Datei von der Cleona-Website oder von GitHub Releases herunter.
2. Oeffne das DMG und ziehe Cleona in deinen Programme-Ordner.
3. Beim ersten Start fragt macOS moeglicherweise, ob du die App eines
   identifizierten Entwicklers oeffnen moechtest -- bestaetige dies.

**Linux (Ubuntu/Debian):**
1. Lade die .deb-Datei von der Cleona-Website oder von GitHub Releases herunter.
2. Installiere mit Doppelklick oder im Terminal: `sudo dpkg -i cleona-chat-beta_VERSION_amd64.deb`
3. Starte Cleona ueber das Anwendungsmenue oder im Terminal mit `cleona-chat-beta`.

**Linux (Fedora/openSUSE):**
1. Lade die .rpm-Datei von der Cleona-Website oder von GitHub Releases herunter.
2. Installiere mit: `sudo dnf install cleona-chat-beta-VERSION-1.x86_64.rpm`
3. Starte Cleona ueber das Anwendungsmenue oder im Terminal mit `cleona-chat-beta`.

**Linux (alle Distributionen -- AppImage):**
1. Lade die .AppImage-Datei von der Cleona-Website oder von GitHub Releases herunter.
2. Mache die Datei ausfuehrbar: Rechtsklick, Eigenschaften, Ausfuehrbar, oder im Terminal: `chmod +x cleona-chat-beta-VERSION-x86_64.AppImage`
3. Starte per Doppelklick oder im Terminal: `./cleona-chat-beta-VERSION-x86_64.AppImage`

Die Paketnamen gelten fuer die Beta, die zurzeit die einzige veroeffentlichte
Fassung ist; sie heissen `cleona-chat-beta`.

**Windows:**
1. Lade den Installer von der Cleona-Website oder von GitHub Releases herunter.
2. Fuehre die Installationsdatei aus und folge den Anweisungen.
3. Starte Cleona ueber das Startmenue oder die Desktop-Verknuepfung.

### Identitaet erstellen

Beim ersten Start erstellt Cleona automatisch eine neue Identitaet fuer dich.
Du kannst dir einen Anzeigenamen geben -- das ist der Name, den deine Kontakte
sehen. Dieser Name laesst sich jederzeit aendern.

### Seed-Phrase aufschreiben -- das Wichtigste ueberhaupt

Nach dem Erstellen deiner Identitaet zeigt dir Cleona 24 Woerter an. Das ist
deine **Seed-Phrase** -- dein persoenlicher Wiederherstellungsschluessel.

**Schreibe diese 24 Woerter auf Papier auf und bewahre sie sicher auf.**

Warum ist das so wichtig?

- Wenn dein Handy kaputt geht, verloren geht oder gestohlen wird, kannst du
  mit diesen 24 Woertern deine gesamte Identitaet auf einem neuen Geraet
  wiederherstellen.
- Ohne die Seed-Phrase gibt es keinen Weg zurueck. Es gibt keinen "Passwort
  vergessen"-Button und keinen Support, der dir dein Konto zurueckgeben
  koennte -- denn es gibt gar kein Konto auf einem Server. Auch deine
  Kontakte koennen deine Identitaet nicht wiederherstellen, egal wie viele.
  Ein zweites Geraet mit derselben Identitaet kommt mit einer spaeteren
  Version (siehe Kapitel 11).
- Gib die Seed-Phrase niemals an andere weiter. Wer diese Woerter kennt, kann
  sich als du ausgeben.

Du findest die 24 Woerter spaeter in den Einstellungen unter "Sicherung" ->
"Recovery-Phrase anzeigen", falls du sie noch einmal ablesen moechtest. Auf
Android bestaetigst du dazu mit deiner Bildschirmsperre.

### Ersten Kontakt hinzufuegen

Um mit jemandem zu chatten, musst du die Person zuerst als Kontakt hinzufuegen.
Dafuer gibt es mehrere Wege -- alle davon werden im naechsten Abschnitt
erklaert.

---

## 3. Kontakte

### Deine Einladung

Kontakte entstehen bei Cleona nur ueber eine Einladung. Deine Einladung ist
vom ersten Start an da -- auch ohne Internet und bevor dein Geraet ueberhaupt
einen Nachbarn gefunden hat. Du findest sie auf deiner Identitaets-Detailseite
(Tipp auf den eigenen Namen in der oberen Leiste).

Die Einladung gibt es in zwei Formen, die genau dasselbe enthalten:

- als **QR-Code**, wenn dein Gegenueber neben dir steht, und
- als **Textzeile**, die du per E-Mail, SMS oder ueber einen anderen
  Messenger verschickst.

Die Einladung enthaelt keine Telefonnummer und keinen Namen aus einem
Verzeichnis. Sie enthaelt deine oeffentlichen Schluessel und die Adressen,
ueber die dein Gegenueber dich und deine Nachbarn erreicht. Fuer jemanden, der
Cleona neu installiert, ist deine Einladung deshalb auch der Einstieg ins
Netz.

### QR-Code scannen (empfohlen)

Wenn ihr euch persoenlich trefft:

1. Du zeigst deinem Gegenueber den QR-Code deiner Einladung.
2. Dein Gegenueber tippt auf den Plus-Button, waehlt "QR-Code scannen" und
   haelt die Kamera auf deinen Bildschirm. Das klappt auch mit der Webcam
   eines Computers.
3. Die Anfrage geht an dich und wird **automatisch angenommen** -- denn du
   hast den Code ja gerade selbst gezeigt.

Ein QR-Code gilt nur einmal: Die erste gueltige Anfrage wird angenommen,
danach ist die Einladung verbraucht. Der QR-Code ist die sicherste Methode,
weil ihr dabei genau wisst, mit wem ihr den Kontakt austauscht.

### NFC (Handys aneinander halten)

Wenn beide Geraete NFC unterstuetzen:

1. Oeffnet beide die Kontakt-Hinzufuegen-Funktion.
2. Haltet eure Handys Ruecken an Ruecken aneinander.
3. Die Einladung wird uebertragen und automatisch angenommen.

NFC bietet wie der QR-Code eine hohe Sicherheit, weil der Austausch nur
funktioniert, wenn ihr physisch nebeneinander steht.

### Textzeile verschicken

Wenn ihr euch nicht treffen koennt:

1. Oeffne deine Einladung und kopiere die Textzeile.
2. Schicke sie der Person, die dich hinzufuegen soll -- per Mail, SMS oder
   ueber einen anderen Messenger.
3. Die andere Person fuegt die Zeile in Cleona im Kontakt-Hinzufuegen-Dialog
   ein.
4. Die Anfrage erscheint bei dir unter **"Anfragen"**. Hier wird **nicht**
   automatisch angenommen: Du entscheidest selbst, denn du kannst nicht
   wissen, wer die Zeile unterwegs noch gelesen hat.

### Kontaktanfragen annehmen

Eine eingehende Anfrage erzeugt noch keinen Kontakt. Sie stellt dir eine
Frage und erscheint im Tab **"Anfragen"**. Dort siehst du den Namen und die
Verifikationsstufe und kannst waehlen:

- **Annehmen** -- erst jetzt wird die Person zu deinem Kontakt.
- **Ablehnen** -- die Anfrage wird verworfen.
- **Blockieren** -- die Person kann dir keine weiteren Anfragen schicken.

### Nie als festen Nachbarn verwenden

Im Menue eines Kontakts findest du den Schalter **"Nie als festen Nachbarn
verwenden"** (Vorgabe: aus). Ist er an, reicht dieser Kontakt keine
Nachrichten fuer dich weiter und erfaehrt deshalb auch nicht, wann du
Nachrichten sendest oder empfaengst. Das ist fuer den Fall gedacht, dass
dir Gefahr aus deinem eigenen Umfeld droht.

Von Unbekannten (weder Kontakt noch Mitglied einer gemeinsamen Gruppe) laesst
Cleona ausser einer solchen Anfrage nichts durch -- keine Nachricht, keinen
Anruf, keine Datei. Und selbst die Anfrage kommt nur
an, wenn der Absender vorher eine kleine Rechenaufgabe geloest hat. Das macht
Massen-Spam teuer.

### Verifikationsstufen

Cleona zeigt dir an, wie sicher die Identitaet eines Kontakts bestaetigt ist:

| Stufe | Bedeutung |
|-------|-----------|
| Nicht verifiziert | Ihr seid verbunden, aber nichts bestaetigt, dass wirklich die richtige Person dahintersteht. |
| Gesehen | Der Schluesselaustausch war erfolgreich, ihr koennt verschluesselt kommunizieren. |
| Verifiziert | Ihr habt euch persoenlich getroffen und per Kamera-Scan oder NFC verbunden. |
| Vertraut | Du hast diesen Kontakt ausdruecklich als vertrauenswuerdig markiert. |

"Verifiziert" gibt es nur fuer den persoenlichen Austausch. Eine Einladung,
die ueber einen Chat oder per Mail kam, erreicht diese Stufe nie -- auch wenn
sie dieselben Daten enthaelt.

Aendern sich die Schluessel eines Kontakts ohne Ankuendigung, setzt Cleona
ihn auf "Nicht verifiziert" zurueck. Das schuetzt dich davor, dass sich
jemand unbemerkt als dein Kontakt ausgibt.

---

## 4. Nachrichten

### Text senden und empfangen

Tippe einfach deine Nachricht ins Eingabefeld unten und druecke Enter oder den
Senden-Button. Deine Nachricht wird automatisch verschluesselt, bevor sie dein
Geraet verlaesst.

Eingehende Nachrichten erscheinen im Chat-Verlauf.

### Was die Zeichen an deiner Nachricht bedeuten

| Zeichen | Bedeutung |
|---------|-----------|
| Uhr | Die Nachricht ist erstellt, aber noch hat sie kein Weg getragen. |
| Ein Haken | Die Nachricht ist unterwegs. Das gilt auch, solange sie im Briefkasten auf dein Gegenueber wartet. |
| Zwei Haken | Zugestellt: Das Geraet deines Gegenueber hat den Empfang bestaetigt. |
| Warnzeichen | 14 Tage lang hat kein Weg die Nachricht getragen. Tippe darauf, um sie erneut zu senden. |

**Offline ist kein Fehler.** Ist dein Gegenueber nicht erreichbar, bleibt
die Nachricht beim einen Haken, bis sie abgeholt wird -- sie ist nicht
verloren. Hat dein Geraet selbst keine Verbindung, bleibt die Nachricht bei
der Uhr und geht von selbst los, sobald wieder ein Weg da ist. Das
Warnzeichen erscheint erst, wenn sie 14 Tage lang keinen Weg gefunden hat;
dann kannst du sie erneut senden.

Das gilt auch fuer ein iPhone, dessen App nicht geoeffnet ist: Die Nachricht
wartet im Briefkasten, bis iOS die App kurz weckt oder bis dein Gegenueber sie
oeffnet. Das kann laenger dauern als bei anderen Geraeten.

Zwei Haken gibt es nur, wenn der Empfaenger selbst den Empfang bestaetigt.
Diese Quittung ist verschluesselt und unterschrieben -- niemand unterwegs
kann sie faelschen, um dir eine Zustellung vorzutaeuschen.

### Bilder, Videos und Dateien senden

Du hast mehrere Moeglichkeiten:

- **Bueroklammer-Icon** im Eingabefeld: Tippe darauf, um eine Datei, ein Bild
  oder ein Video aus deiner Galerie oder deinem Dateisystem auszuwaehlen.
- **Drag and Drop** (Desktop): Ziehe eine Datei einfach in das Chat-Fenster.
- **Aus der Zwischenablage einfuegen** (Desktop): Kopiere ein Bild und fuege
  es im Chat ein.

Kleine Dateien (unter 256 KB) reisen direkt in der Nachricht mit. Groessere
Dateien werden in Stuecke zerlegt und mit einer Fehlerkorrektur versehen, so
dass einzelne verlorene Stuecke nichts ausmachen. Seid ihr beide online,
werden sie ueber einen Nachbarn gestreamt; sonst werden sie bei Geraeten
abgelegt, die staendig erreichbar sind, bis dein Gegenueber sie abholt.

Ab 256 KB fragt Cleona dich je Datei, bevor sie gesendet wird: Eine grosse
Datei kann nicht den Weg deiner Nachrichten nehmen. Ihr Inhalt bleibt
verschluesselt, und dein Gegenueber erfaehrt deine Internetadresse nicht.
Aber die Uebertragung ist von aussen als Ereignis sichtbar, und ein fremdes
Geraet, das sie weiterreicht oder aufbewahrt, sieht, wer hochlaedt und wer
abholt. Deine Zustimmung gilt nur fuer diese eine Datei.

### Sprachnachrichten

1. Halte den Mikrofon-Button im Eingabefeld gedrueckt.
2. Sprich deine Nachricht.
3. Lasse den Button los, um die Nachricht zu senden.

Wenn auf deinem Geraet die Spracherkennung aktiviert ist (siehe Einstellungen),
wird deine Sprachnachricht automatisch als Text transkribiert. Dein Gegenueber
sieht dann sowohl die Aufnahme als auch den transkribierten Text.

### Nachrichten beantworten (Zitieren)

Um auf eine bestimmte Nachricht zu antworten:

1. Oeffne das Drei-Punkte-Menue neben der Nachricht.
2. Waehle "Antworten".
3. Ueber dem Eingabefeld erscheint ein Banner mit der zitierten Nachricht.
4. Schreibe deine Antwort und sende sie.

Die zitierte Nachricht wird in deiner Antwort angezeigt, so dass der Bezug
klar ist.

### Nachrichten bearbeiten und loeschen

- **Bearbeiten:** Drei-Punkte-Menue der Nachricht, dann "Bearbeiten".
  Aendere den Text und sende ihn erneut. Dein Gegenueber sieht, dass die
  Nachricht bearbeitet wurde. Bearbeiten ist innerhalb von 15 Minuten nach
  dem Senden moeglich.
- **Loeschen:** Drei-Punkte-Menue der Nachricht, dann "Loeschen". Die
  Nachricht wird bei dir und deinem Gegenueber entfernt. Du kannst deine
  eigenen Nachrichten jederzeit loeschen -- es gibt kein Zeitfenster fuer
  das Loeschen.

### Emoji-Reaktionen

Statt eine Antwort zu schreiben, kannst du auf eine Nachricht mit einem
Emoji reagieren:

1. Oeffne das Drei-Punkte-Menue oder halte die Nachricht lange gedrueckt.
2. Waehle ein Emoji aus der Schnellauswahl oder oeffne den Emoji-Picker fuer
   die volle Auswahl.
3. Deine Reaktion erscheint unter der Nachricht.

### Text kopieren

Ueber das Drei-Punkte-Menue einer Nachricht kannst du den Nachrichtentext in
die Zwischenablage kopieren.

### Nachrichten suchen

Am oberen Rand des Chat-Fensters findest du die Suchfunktion. Gib einen
Suchbegriff ein, und Cleona zeigt dir alle Treffer im aktuellen Chat. Mit den
Pfeiltasten kannst du zwischen den Treffern hin- und herspringen.

Auf der Startseite gibt es zusaetzlich einen Tab-uebergreifenden Suchfilter,
mit dem du alle Unterhaltungen nach einem Begriff durchsuchen kannst.

### Link-Vorschau

Wenn du einen Link sendest, erzeugt Cleona automatisch eine Vorschau (Titel,
Beschreibung, Vorschaubild). Diese Vorschau wird von deinem Geraet erstellt
und mitverschickt -- dein Gegenueber muss dafuer keine Verbindung zur
verlinkten Website aufbauen.

Was ein Tipp auf einen empfangenen Link tut, stellst du in den Einstellungen
unter "Links oeffnen" ein: "Normal", "Privates Fenster bevorzugt" (wo das
Geraet kein privates Fenster oeffnen kann, oeffnet der Link normal) oder
"Jedes Mal fragen".

---

## 5. Gruppen

### Gruppe erstellen

1. Wechsle zum Tab "Gruppen".
2. Tippe auf den Plus-Button.
3. Gib der Gruppe einen Namen.
4. Waehle die Kontakte aus, die du einladen moechtest.
5. Tippe auf "Erstellen".

Die eingeladenen Kontakte erhalten eine Benachrichtigung und koennen der Gruppe
beitreten.

### Wie Gruppennachrichten geschuetzt sind

In einer Gruppe mit bis zu 16 Mitgliedern verschickt Cleona jede Nachricht an
jedes Mitglied einzeln -- jeweils nur fuer dieses Mitglied verschluesselt, so
als haettest du jedem eine eigene Nachricht geschrieben. Die Haken an einer
Gruppennachricht zeigen den Stand des Mitglieds, bei dem sie am wenigsten
weit ist.

Waechst die Gruppe ueber 16 Mitglieder, nutzt sie einen gemeinsamen
Schluessel. Er aendert sich jeden Tag und wird neu gezogen, wenn ein Mitglied
austritt oder entfernt wird; ein neues Mitglied liest erst ab seinem Beitritt.
Dort zeigen die Haken nicht mehr den Stand jedes Mitglieds, sondern dass die
Nachricht im Netz abgelegt ist. Sinkt die Gruppe auf 12 oder weniger
Mitglieder, geht sie zum Einzelversand zurueck.

### Bilder in Gruppen und Kanaelen

In den Einstellungen einer Gruppe oder eines Kanals legst du mit "Bilder
immer laden" fest, ob Bilder sofort geladen werden oder erst, wenn du auf
eines tippst.

### Mitglieder einladen

Auch nach der Erstellung kannst du weitere Kontakte einladen:

1. Oeffne die Gruppeninfo (Drei-Punkte-Menue in der Gruppenuebersicht oder
   obere Leiste im Gruppen-Chat).
2. Tippe auf "Einladen".
3. Waehle die Kontakte aus, die du hinzufuegen moechtest.

### Rollen

Jede Gruppe hat drei Rollen:

- **Eigentuemer (Owner):** Hat die volle Kontrolle. Kann Mitglieder
  hinzufuegen und entfernen, Admins ernennen und die Gruppe verwalten. Der
  Eigentuemer kann seinen Status auch an ein anderes Mitglied uebertragen.
- **Admin:** Kann Mitglieder entfernen und bei der Verwaltung helfen.
- **Mitglied:** Kann Nachrichten lesen und schreiben.

### Gruppe verlassen

1. Oeffne das Drei-Punkte-Menue in der Gruppenuebersicht.
2. Waehle "Verlassen".
3. Bestaetige deine Entscheidung.

Wenn du eine Gruppe verlaesst, bleiben deine bisherigen Nachrichten fuer die
anderen Mitglieder sichtbar.

---

## 6. Oeffentliche Kanaele

### Was sind Kanaele?

Kanaele sind oeffentliche Diskussionsforen innerhalb des Cleona-Netzes.
Im Gegensatz zu Gruppen kann hier jeder mitlesen, ohne eingeladen werden zu
muessen. Nur der Eigentuemer und Admins koennen Beitraege veroeffentlichen --
Abonnenten lesen mit.

### Kanaele finden und beitreten

1. Wechsle zum Tab "Kanaele".
2. Oeffne den Reiter "Suche".
3. Durchsuche die verfuegbaren Kanaele nach Name oder Thema.
4. Tippe auf einen Kanal und dann auf "Abonnieren".

Kanaele koennen nach Sprache gefiltert werden. Manche Kanaele sind als "Nicht
jugendfrei" gekennzeichnet -- diese sind nur sichtbar, wenn du in deinem Profil
bestaetigt hast, dass du ueber 18 bist.

### Eigenen Kanal erstellen

1. Wechsle zum Tab "Kanaele".
2. Tippe auf den Plus-Button.
3. Gib einen Kanalnamen ein (muss im gesamten Netz eindeutig sein).
4. Waehle die Sprache und ob der Kanal oeffentlich oder privat sein soll.
5. Optional: Fuege eine Beschreibung und ein Bild hinzu.
6. Tippe auf "Erstellen".

Bei oeffentlichen Kanaelen kannst du festlegen, ob der Inhalt als "Nicht
jugendfrei" eingestuft wird.

### Inhalte melden

Wenn dir in einem oeffentlichen Kanal unangemessene Inhalte auffallen, kannst
du diese melden. Cleona nutzt ein dezentrales Moderationssystem: Meldungen
werden von zufaellig ausgewaehlten Mitgliedern des Netzes bewertet (eine Art
"Geschworenengericht"). Wird ein Verstoss festgestellt, erhaelt der Kanal eine
Warnung. Bei wiederholten Verstoessen wird er im Suchindex herabgestuft oder
gesperrt.

### System-Kanaele

Cleona verfuegt ueber zwei eingebaute System-Kanaele:

- **Bug Log:** Wenn Cleona einen Fehler erkennt, fragt es dich, ob du einen
  Fehlerbericht senden moechtest; vorher siehst du genau, was veroeffentlicht
  wird. Diese Berichte landen im Bug-Log-Kanal, wo sie von der Community
  eingesehen werden koennen. Ein Bericht traegt keinen Namen und keinen
  Inhalt deiner Unterhaltungen, sondern ein Pseudonym. In der Beta nennt er
  zusaetzlich deine Kennung (User-ID), damit die Entwickler nachfragen
  koennen. Du kannst auch manuell einen Log-Report senden (mit
  Vorschau-Dialog und expliziter Zustimmung).
- **Feature Requests:** Hier koennen Nutzer Funktionswuensche einreichen
  und fuer bestehende Vorschlaege abstimmen. Die Vorschlaege werden nach
  Stimmen sortiert.

Jeder Computer haelt bis zu 25 MB je System-Kanal, jedes Handy bis zu 5 MB;
ist das voll, geht das Aelteste zuerst -- nie, was du selbst schon gesehen
hast.

---

## 7. Anrufe

### Sprachanruf starten

1. Oeffne den Chat mit dem Kontakt, den du anrufen moechtest.
2. Tippe auf das Telefon-Symbol in der oberen Leiste.
3. Warte, bis dein Gegenueber den Anruf annimmt.

Waehrend des Gespraechs siehst du eine Zeitleiste, die Gespraechsdauer und
hast Zugriff auf Stummschalten und Lautsprecher.

Zum Auflegen tippe auf den roten Auflegen-Button.

Siehst du "Nicht erreichbar", ist das Geraet deines Gegenueber gerade nicht zu
erreichen, zum Beispiel ein iPhone mit nicht geoeffneter App. Schreib
stattdessen eine Nachricht.

### Videoanruf starten

1. Oeffne den Chat mit dem Kontakt.
2. Tippe auf das Kamera-Symbol in der oberen Leiste.
3. Dein Videobild erscheint in einem kleinen Fenster, das Bild deines
   Gegenueber im grossen Bereich.

Du kannst waehrend des Gespraechs zwischen Vorder- und Rueckkamera wechseln.

### Eingehende Anrufe

Wenn dich jemand anruft, erscheint ein Benachrichtigungsfenster mit dem Namen
des Anrufers. Du kannst:

- **Annehmen** -- das Gespraech beginnt.
- **Ablehnen** -- der Anrufer wird benachrichtigt.

Bist du gerade in einem Gespraech, klingelt ein neuer Anruf nicht; du
bekommst stattdessen eine Nachricht "Verpasster Anruf". Dasselbe gilt fuer
einen Gruppenanruf, den du nicht angenommen hast -- die Nachricht steht dann
im Gruppenchat.

Ruft jemand eine deiner Identitaeten an, die gerade nicht angezeigt wird,
klingelt es trotzdem; der Anrufbildschirm nennt, welche deiner Identitaeten
angerufen wird.

Auf dem iPhone klingelt es nur, wenn die App geoeffnet ist. Wer dich anruft,
waehrend sie nicht geoeffnet ist, sieht nach 10 Sekunden "Nicht erreichbar".
Sobald du die App oeffnest, findest du eine Nachricht ueber den verpassten
Anruf.

### Gruppenanrufe

Du kannst auch Gruppenanrufe fuehren, an denen mehrere Personen gleichzeitig
teilnehmen. Der Anruf wird ueber einen intelligenten Weiterleitungsbaum
organisiert, sodass nicht jeder Teilnehmer mit jedem anderen direkt verbunden
sein muss. Alle Gespraeche sind durchgehend verschluesselt.

Jedes Gruppenmitglied kann einen Gruppenanruf starten. Zwei Teilnehmer, die
keine Kontakte voneinander sind, sehen nie die Internetadresse des anderen:
Ihr Ton und Bild laeuft ueber einen Teilnehmer, der mit beiden Kontakt ist.
Gibt es keinen solchen, sind die beiden nicht verbunden, und die Kachel sagt
"Kein gemeinsamer Kontakt im Anruf". Ist eine Weiterleitung ausgelastet,
bleibt der Ton, und das Video faellt fuer dieses Paar weg.

### Verschluesselung bei Anrufen

Alle Anrufe werden mit einmaligen Schluesseln verschluesselt, die nur fuer
die Dauer des Gespraechs existieren. Nach dem Auflegen werden diese Schluessel
sofort geloescht. Niemand kann ein vergangenes Gespraech nachtraeglich
entschluesseln.

Ehrlich gesagt: Anrufe laufen, wo immer moeglich, direkt zwischen den
Geraeten, denn schon eine kleine Verzoegerung stoert beim Sprechen. Anders
als bei Nachrichten kann dein Internetanbieter deshalb bei einem Anruf sehen,
mit welcher Internetadresse du verbunden bist. Was ihr sagt, sieht er nicht.

Bei einem Anruf sieht auch dein Kontakt deine Internetadresse. Willst du das
bei einem Kontakt nicht, schalte in seinem Menue "Anrufe erlauben" ab
(Vorgabe: an). Schaltest du spaeter ab, bleibt ihm eine schon gesehene
Adresse bekannt.

---

## 8. Kalender

Cleona enthaelt einen eingebauten Kalender, der verschluesselt und komplett
dezentral funktioniert -- ohne Cloud-Dienst.

### Ansichten

Der Kalender bietet fuenf Ansichten: Tag, Woche, Monat, Jahr und eine
Aufgaben-Ansicht. Wechsle zwischen ihnen ueber die Tabs am oberen Rand des
Kalender-Bildschirms.

### Termine erstellen

Tippe auf einen Zeitslot oder verwende den Hinzufuegen-Button, um einen neuen
Termin zu erstellen. Du kannst Titel, Datum, Uhrzeit, Ort und Notizen
eingeben. Termine werden verschluesselt auf deinem Geraet gespeichert.

### Wiederkehrende Termine

Termine koennen sich taeglich, woechentlich, monatlich oder jaehrlich
wiederholen. Du kannst das Muster anpassen (z.B. jeden zweiten Dienstag,
jeden Ersten des Monats) und ein Enddatum oder eine Anzahl von Wiederholungen
festlegen.

### Kontakte einladen

Beim Erstellen oder Bearbeiten eines Termins kannst du deine Cleona-Kontakte
einladen. Sie erhalten eine verschluesselte Kalendereinladung und koennen mit
Zusagen, Absagen oder Vielleicht antworten. Aenderungen am Termin werden
automatisch an alle Eingeladenen gesendet.

### Frei/Belegt-Anzeige

Du kannst deine Verfuegbarkeit mit Kontakten teilen, ohne Termindetails
preiszugeben. Es gibt drei Datenschutzstufen: volle Details, nur Zeitbloecke
oder verborgen. Du kannst einen Standard setzen und ihn pro Kontakt
ueberschreiben.

### Erinnerungen

Termine koennen Erinnerungen haben, die vor Terminbeginn eine
System-Benachrichtigung ausloesen. Du kannst Erinnerungen bei Bedarf
schlummern lassen.

### Externer Kalender-Sync

Cleona kann sich mit externen Kalenderdiensten synchronisieren:

- **CalDAV** -- Verbinde dich mit jedem CalDAV-kompatiblen Server (Nextcloud,
  Radicale usw.).
- **Google Kalender** -- Synchronisation ueber die Google Calendar API mit
  sicherer OAuth2-Authentifizierung.
- **Lokaler CalDAV-Server** -- Cleona kann einen lokalen CalDAV-Server auf
  deinem Geraet starten, sodass Desktop-Kalender-Apps (Thunderbird, Outlook,
  Apple Kalender, Evolution) mit deinem Cleona-Kalender synchronisieren
  koennen.
- **Android-Systemkalender** -- Termine aus Cleona koennen in die
  eingebaute Kalender-App deines Android-Geraets uebertragen werden.
- **ICS-Dateien** -- Importiere und exportiere Termine im
  Standard-iCalendar-Format.

### PDF-Export

Du kannst jede Kalenderansicht (Tag, Woche, Monat, Jahr) als PDF-Dokument
drucken oder exportieren.

---

## 9. Umfragen

Du kannst in jedem Chat oder jeder Gruppe Umfragen erstellen, um Meinungen
einzuholen oder Termine zu planen.

### Umfragetypen

Cleona unterstuetzt fuenf Arten von Umfragen:

- **Einfachauswahl** -- Teilnehmer waehlen eine Option.
- **Mehrfachauswahl** -- Teilnehmer koennen mehrere Optionen auswaehlen.
- **Terminumfrage** -- Finde einen Termin, der fuer alle passt. Jeder
  Teilnehmer markiert Termine als verfuegbar, vielleicht oder nicht
  verfuegbar.
- **Skala** -- Bewerte etwas auf einer numerischen Skala (z.B. 1 bis 5).
- **Freitext** -- Teilnehmer schreiben ihre eigene Antwort.

### Umfrage erstellen

Oeffne einen Chat und tippe auf das Umfrage-Symbol (oder nutze das
Anhaenge-Menue). Waehle den Umfragetyp, formuliere deine Frage und die
Optionen, und sende die Umfrage. Sie erscheint als Nachricht im Chat.

### Abstimmen

Tippe auf eine Umfrage, um deine Stimme abzugeben. Du kannst deine Stimme
jederzeit aendern oder zurueckziehen.

### Anonyme Abstimmung

Umfragen koennen fuer anonyme Abstimmung konfiguriert werden. Wenn aktiviert,
sind Stimmen kryptografisch anonym -- niemand, nicht einmal der
Umfrage-Ersteller, kann sehen, wer wofuer gestimmt hat. Die Stimmenzahl
bleibt trotzdem sichtbar.

### Terminumfrage zum Kalender

Wenn eine Terminumfrage abgeschlossen ist, kann der Gewinner-Termin mit einem
Tipp direkt in einen Kalendereintrag umgewandelt werden.

---

## 10. Mehrere Identitaeten

### Warum mehrere Identitaeten?

Stell dir vor, du moechtest dein Berufsleben und dein Privatleben trennen --
aehnlich wie mit zwei verschiedenen Telefonnummern, aber ohne zweites Handy.
In Cleona kannst du mehrere Identitaeten auf einem Geraet nutzen. Jede
Identitaet hat einen eigenen Namen, ein eigenes Profilbild, eigene Kontakte und
eigene Unterhaltungen.

### Neue Identitaet erstellen

1. In der oberen Leiste siehst du deine aktuelle Identitaet als Tab.
2. Tippe auf das Plus-Zeichen (+) rechts neben deinen Identitaets-Tabs.
3. Gib einen Namen fuer die neue Identitaet ein.
4. Fertig -- die neue Identitaet ist sofort aktiv.

### Zwischen Identitaeten wechseln

Tippe einfach auf den Identitaets-Tab in der oberen Leiste. Der Wechsel
ist sofort -- keine Wartezeit, kein Neuladen.

### Alle laufen gleichzeitig

Ein wichtiger Punkt: Alle deine Identitaeten sind gleichzeitig aktiv. Auch
wenn du gerade als "Beruflich" angezeigt wirst, empfaengt deine "Privat"-
Identitaet weiterhin Nachrichten. Du verpasst nichts, egal welche Identitaet
du gerade ausgewaehlt hast.

### Identitaets-Detailseite

Wenn du auf den Tab deiner gerade aktiven Identitaet tippst, oeffnet sich die
Detailseite. Hier kannst du:

- Deinen QR-Code fuer Kontakte anzeigen.
- Dein Profilbild aendern oder entfernen.
- Eine Profilbeschreibung hinzufuegen.
- Deinen Anzeigenamen aendern.
- Ein Design (Skin) fuer diese Identitaet waehlen.
- Die Identitaet loeschen, falls du sie nicht mehr brauchst.

### Identitaet loeschen

Wenn du eine Identitaet loeschst, werden deine Kontakte darueber
benachrichtigt. Die Identitaet und alle zugehoerigen Daten werden von deinem
Geraet entfernt. Dieser Vorgang ist nicht umkehrbar.

---

## 11. Mehrere Geraete

### Eine Identitaet, ein Geraet -- vorerst

Eine Identitaet laeuft heute auf einem Geraet. Ein zweites Geraet fuer
dieselbe Identitaet kommt mit einer spaeteren Version; in den Einstellungen
unter "Geraete" -> "Geraete verwalten" steht "Weiteres Geraet koppeln"
deshalb noch als "Noch nicht verfuegbar".

Wenn es kommt, gilt: Alle Geraete sind gleichberechtigt, es gibt kein
Hauptgeraet. Ein weiteres Geraet richtest du mit deinen 24 Woertern ein, und
eines deiner bisherigen Geraete stimmt zu. Hoechstens 5 Geraete.

Gibst du heute auf einem neuen Geraet deine 24 Woerter ein, ziehst du um: Die
Identitaet wird auf das neue Geraet wiederhergestellt, und dein bisheriges
Geraet entfernt sie danach bei sich (siehe Kapitel 12).

Auf mehreren Geraeten kannst du heute verschiedene Identitaeten nutzen
(Kapitel 10).

### Identitaet neu schluesseln

Vermutest du, dass jemand an deine Schluessel gekommen ist, kannst du unter
"Geraete verwalten" -> "Identitaet neu schluesseln" neue Schluessel erzeugen.
Deine Kontakte werden benachrichtigt, deine offenen Einladungen werden
widerrufen. Wichtig: Danach stellen die 24 Woerter allein nur noch die alten
Schluessel her. Lege deshalb direkt danach ein neues Recovery-Paket an;
wiederherstellen kannst du dann nur noch zusammen mit diesem Paket.

---

## 12. Wiederherstellung

### Seed-Phrase verwenden

Wenn du dein Geraet verlierst oder ein neues einrichtest:

1. Installiere Cleona auf dem neuen Geraet.
2. Waehle beim Start "Wiederherstellen".
3. Gib deine 24 Woerter ein.
4. Cleona erzeugt daraus alle deine Identitaeten wieder -- mit denselben
   Schluesseln wie vorher. Fuer deine Kontakte bist du derselbe Mensch.

### Was zurueckkommt -- und was nicht

Deine Identitaet steckt in den 24 Woertern, deine Kontakte und dein Verlauf
nicht. Zurueck kommt dein Netzzugang ueber das **Recovery-Paket**: Dein
Geraet legt ein kleines, verschluesseltes Paket im Netz ab. Nur deine 24
Woerter koennen es finden und oeffnen. Darin steht, was dein neues Geraet
braucht, um deine Kontakte wieder zu erreichen, und was in der Zwischenzeit
fuer dich im Netz lag. Dafuer muss kein Kontakt online sein.

Den bisherigen Chatverlauf bringt eine Wiederherstellung nicht zurueck.

Das Recovery-Paket lebt 7 Tage und wird von deinem Geraet erneuert, solange
es laeuft; in den Einstellungen siehst du, bis wann es gilt. Lief mehr als
7 Tage lang keines deiner Geraete, ist es abgelaufen. Dann stellen die 24
Woerter deine Identitaet trotzdem her, aber deine Kontakte musst du neu
einladen; was in der Zwischenzeit fuer dich im Netz lag, ist verloren.

### Wiederherstellen heisst umziehen

Findet dein bisheriges Geraet spaeter, dass die Identitaet woanders
wiederhergestellt wurde, entfernt es sie bei sich -- mit ihrem Verlauf.
Deshalb: Wer deine 24 Woerter hat, kann deine Identitaet auf diese Weise von
deinem Geraet holen. Bis alle Kontakte wieder da sind, erinnert dich die App;
mit "Abschliessen und Schluessel erneuern" beendest du die Wiederherstellung
selbst.

### Was niemand wiederherstellen kann

Das ist wichtig, und wir sagen es deshalb deutlich:

- **Niemand ausser dir kann deine Identitaet wiederherstellen.** Nicht der
  Entwickler, nicht ein Support, und auch nicht deine Kontakte -- egal wie
  viele es sind. Es gibt keinen Generalschluessel und keinen Teil deines
  Schluessels, der bei anderen hinterlegt waere.
- **Hast du die 24 Woerter verloren und kein Geraet mehr, ist deine Identitaet
  verloren.** Dann bleibt nur, eine neue anzulegen und deine Kontakte neu
  einzuladen.

Der beste Schutz: Schreib die 24 Woerter auf Papier und bewahre sie sicher
auf.

---

## 13. Einstellungen

Die Einstellungen erreichst du ueber das Zahnrad-Symbol in der oberen rechten
Ecke.

### Benachrichtigungen und Klingeltoene

- Waehle aus sechs verschiedenen Klingeltoenen fuer eingehende Anrufe.
- Stelle einen Nachrichtenton ein.
- Auf Android-Geraeten kannst du zusaetzlich die Vibration aktivieren oder
  deaktivieren.
- **"Alles stummschalten"** laesst auf diesem Geraet keine Nachricht mehr
  klingeln, vibrieren oder sich melden -- fuer alle Identitaeten. Anrufe
  klingeln weiter.
- **"Ruhezeiten"** legst du je Identitaet mit Von/Bis fest. In dieser Zeit
  klingelt, vibriert und meldet sich keine Nachricht dieser Identitaet; die
  Nachrichten kommen trotzdem an.
- **"Benachrichtigungen ohne Inhalt"** (Vorgabe: aus) zeigt nur, dass eine
  Nachricht, Einladung oder Erinnerung angekommen ist -- ohne Absender, Namen
  und Text. Anrufe zeigen weiter den Namen.
- Was nach dem Start auf einmal ankommt, meldet Cleona in einer Sammelmeldung
  ("5 neue Nachrichten in 2 Unterhaltungen"); alles Spaetere einzeln. Ein Tipp
  auf eine Nachrichtenmeldung oeffnet die Unterhaltung, auch in einer anderen
  Identitaet.

### Designs (Skins)

Cleona bietet zehn verschiedene Designs an: Teal, Ocean, Sunset, Forest,
Amethyst, Fire, Storm, Slate, Gold und Contrast. Das Contrast-Design erfuellt
die hoechste Zugaenglichkeitsstufe (WCAG AAA) und ist bei eingeschraenktem
Sehvermoegen besonders gut lesbar.

Jede Identitaet kann ihr eigenes Design haben. Du aenderst das Design in der
Identitaets-Detailseite (Tipp auf den aktiven Identitaets-Tab).

Zusaetzlich kannst du in den Einstellungen unter "Darstellung" zwischen
hellem, dunklem und dem System-Theme wechseln.

### Sprache aendern

Cleona ist in 34 Sprachen verfuegbar, darunter auch Sprachen mit
Rechts-nach-Links-Schrift (z.B. Arabisch, Hebraeisch). Aendere die Sprache in
den Einstellungen unter "Sprache".

### Media-Archivierung

Wenn du zu Hause einen Netzwerkspeicher (NAS) oder einen freigegebenen Ordner
hast, kann Cleona deine Medien automatisch dorthin auslagern. Unterstuetzt
werden SMB, SFTP, FTPS und WebDAV.

So funktioniert die gestaffelte Speicherung:
- Die ersten 30 Tage: Alles bleibt auf deinem Geraet.
- Nach 30 Tagen: Ein Vorschaubild bleibt auf dem Geraet, das Original wird
  archiviert.
- Nach 90 Tagen: Nur noch ein kleines Vorschaubild bleibt auf dem Geraet.
- Nach einem Jahr: Nur noch ein Platzhalter bleibt, das Original liegt sicher
  im Archiv.

Du kannst jederzeit auf ein archiviertes Medium tippen, um es zurueckzuholen --
vorausgesetzt, du bist mit deinem Heimnetzwerk verbunden. Besonders wichtige
Medien lassen sich anheften, damit sie nie ausgelagert werden.

Unter "Speicher-Budget" legst du fest, wie viele MB Medien auf dem Geraet
bleiben (Vorgabe: 100 MB auf dem Handy, 2 GB am Computer). Ist es voll, wird
das aelteste nicht angeheftete Medium zuerst archiviert. Geloescht wird ein
Original nur, wenn es sicher im Archiv liegt -- Textnachrichten bleiben immer
erhalten.

### Transkription fuer Sprachnachrichten

Wenn aktiviert, werden deine Sprachnachrichten lokal auf deinem Geraet in
Text umgewandelt (mit dem Open-Source-Modell Whisper). Der transkribierte Text
wird zusammen mit der Aufnahme an dein Gegenueber geschickt. Die Transkription
geschieht komplett auf deinem Geraet -- keine Daten gehen an externe Dienste.

Welches Modell (tiny, base, small) heruntergeladen wird, stellst du einmal
fuer das Geraet ein; die Sprache (automatisch oder fest) je Identitaet.

### Auto-Download

Du kannst einstellen, ab welcher Groesse Medien automatisch heruntergeladen
werden sollen. So kannst du zum Beispiel Bilder automatisch laden lassen, aber
bei grossen Videos manuell entscheiden.

### Geraete

Unter "Geraete" -> "Geraete verwalten" siehst du dieses Geraet. Ein weiteres
Geraet zu koppeln kommt mit einer spaeteren Version (Kapitel 11).

### Netzwerk

Cleona braucht keine Netzwerk-Einstellungen, um zu funktionieren. Es gibt
drei Netzschalter:

- **Portfreigabe am Router** (Vorgabe: an). Cleona bittet deinen eigenen
  Router, eine Tuer fuer Cleona zu oeffnen. Klappt das, ist dein Geraet fuer
  andere besser erreichbar und hilft dem Netz. Cleona spricht dabei nur mit
  deinem Router, nicht mit dem Internet.
- **Oeffentliche Adresseintraege** (Vorgabe: an). Hat dein Geraet noch zu
  wenige Nachbarn, schaut es in einem oeffentlichen Verzeichnis (Nostr) nach
  weiteren Einstiegspunkten, und ist es selbst gut erreichbar, traegt es sich
  dort ein. Der Eintrag enthaelt eine Adresse, keinen Namen und keinen Kontakt.
  Schaltest du ihn ab, findet dein Geraet Nachbarn nur noch ueber Einladungen,
  das lokale Netz und die Nachbarn, die es schon kennt.
- **Weniger Tarnpakete im WLAN** (Vorgabe: aus). Im WLAN oder am Kabel kannst
  du die leeren Tarnpakete abschalten. Dann ist dort aber wieder zu sehen,
  wann du schreibst. Im Mobilfunk gibt es diesen Schalter nicht -- dort
  sendet Cleona ohnehin nur ein Tarnpaket pro Minute.

Den Tarnstrom als Ganzes kann man nicht abschalten. Das ist Absicht: Nur wenn
er immer laeuft, sagt die Aktivitaet deines Geraets nichts darueber aus, ob
du gerade schreibst.

Ueber den drei Schaltern steht der **Datensparmodus**: Im Mobilfunk schlaegt
Cleona ihn vor, schaltet ihn aber nie selbst ein. Er spart Daten, dafuer ist
dein Geraet von aussen leichter zu erkennen.

Darunter stellst du den **"Zwischenspeicher fuer Medien anderer"** ein: Dein
Geraet haelt verschluesselte Teile von Medien anderer bis zu 7 Tage, damit
sie ihre Empfaenger erreichen (Vorgabe: 100 MB auf dem Handy, 1 GB am
Computer). Eine kleinere Groesse gibt den Platz sofort frei -- die aeltesten
Teile zuerst.

---

## 14. Sicherheit

### Was bedeutet Post-Quantum-Verschluesselung?

Heutige Verschluesselung basiert auf mathematischen Problemen, die fuer normale
Computer extrem schwer zu loesen sind. Quantencomputer koennten einige dieser
Probleme in Zukunft schnell loesen. Post-Quantum-Verschluesselung verwendet
zusaetzliche Verfahren, die auch Quantencomputern standhalten.

Cleona kombiniert beide Ansaetze: klassische Verschluesselung fuer
Zuverlaessigkeit und Post-Quantum-Verfahren fuer Zukunftssicherheit. So bist
du gegen heutige und zukuenftige Bedrohungen gleichzeitig geschuetzt.

Fuer jede einzelne Nachricht wird ein eigener Schluessel erzeugt. Selbst wenn
ein Angreifer den Schluessel einer Nachricht knacken wuerde, koennte er damit
keine andere Nachricht lesen.

### Warum kein Server sicherer ist

Bei herkoemmlichen Messengern laufen deine Nachrichten ueber die Server des
Anbieters. Auch wenn sie dort verschluesselt sein moegen: Der Anbieter hat
Zugriff auf Metadaten (wer kommuniziert wann mit wem, wie oft, von wo) und
muss diese unter Umstaenden auf richterliche Anordnung herausgeben.

Bei Cleona gibt es keinen solchen zentralen Punkt. Es gibt keinen Ort, an dem
alle Metadaten zusammenlaufen, und kein Verzeichnis, in dem man nachschlagen
koennte, wer du bist oder wen du kennst.

### Wer sieht, dass du mit jemandem schreibst?

Verschluesselung schuetzt, **was** du schreibst. Genauso wichtig ist, dass
kein einzelner Beobachter erfaehrt, **mit wem** und **wann** du schreibst.
Dafuer sorgt Cleona so:

- **Im Internet nie direkt.** Wuerde dein Geraet eine Nachricht direkt an die
  Internetadresse deines Gegenueber schicken, koennte dein Anbieter sehen, mit
  wem du schreibst. Deshalb geht eine Nachricht im Internet immer ueber eure
  festen Nachbarn: deinen und die deines Gegenueber.
- **Nachbarn, denen du vertraust.** Deine festen Nachbarn sind, wo immer
  moeglich, Geraete deiner eigenen Kontakte -- bis zu drei, die gerade von
  aussen erreichbar sind. Faellt einer weg, rueckt ein anderer Kontakt nach.
  Ein Kontakt laesst sich nicht mit Servern kaufen; ein beliebiger Knoten im
  Netz schon. Hast du noch keinen erreichbaren Kontakt, nimmt Cleona einen
  anderen Nachbarn. Deine Einladung nennt nie einen deiner Kontakte, damit
  niemand ueber sie die Adresse eines Freundes erfaehrt.
- **Codes statt Namen.** Die Nachbarn sehen keine Namen und keine Kennungen,
  sondern nur einen Code. Er gilt fuer genau euch beide, in eine Richtung,
  fuer einen Tag -- am naechsten Tag ist es ein anderer. Dein Nachbar weiss,
  woher das Paket kommt, aber nicht, wohin es am Ende geht. Der Nachbar deines
  Gegenueber weiss, wohin es geht, aber nicht, woher es kam. Im Normalfall
  sieht niemand unterwegs beide Enden.
- **Der Tarnstrom.** Dein Geraet sendet laufend, in unregelmaessigen
  Abstaenden, Tarnpakete an seine Nachbarn. Sie sind genauso gross wie echte
  Pakete, gehen ueber denselben Port und sind von aussen nicht von ihnen zu
  unterscheiden. Ob gerade ein Mensch schreibt oder das Geraet nur laeuft, ist
  damit nicht zu erkennen. Deine Nachrichten warten nie auf den Tarnstrom --
  sie gehen sofort los, er laeuft nur daneben.

**Was der Tarnstrom kostet:** Im WLAN rund 13 MB am Tag. Im Mobilfunk sendet
Cleona nur ein Tarnpaket pro Minute, das sind etwa 1,7 MB am Tag. Der Grund
fuer die Drosselung im Mobilfunk ist nicht die Datenmenge, sondern der Akku:
Jedes Paket weckt das Funkmodem auf.

**Was Cleona nicht verbergen kann** -- ehrlich gesagt:

- Kein **einzelner** Beobachter sieht, wer mit wem schreibt -- weder dein
  Anbieter noch die Knoten unterwegs. Wer aber **beide Enden gleichzeitig**
  ueberwacht, etwa ein Staat, der deinen Anschluss und den deines
  Gegenueber beobachtet oder beide Nachbarn stellt, kann ueber die Zeit
  zuordnen: Paket raus bei dir, kurz darauf Paket rein bei deinem Gegenueber.
  Oft genug wiederholt, ergibt das eine Verbindung.
- Der Tarnstrom erschwert diese Zuordnung, verhindert sie aber nicht. Er
  verbirgt einzelne Nachrichten, nicht die Menge: Wer sehr viel sendet,
  erhoeht den Gesamtverkehr seines Geraets.
- Ein Kontakt, der dein fester Nachbar ist, erfaehrt, **wann** und **wie viel**
  du sendest und empfaengst -- nicht mit wem und nicht was. Kommt die Gefahr
  aus deinem eigenen Umfeld, kannst du jeden Kontakt davon ausnehmen (siehe
  Kapitel 3, "Nie als festen Nachbarn verwenden").
- Haben zwei neue Nutzer nur denselben einen Nachbarn, laeuft ihre Nachricht
  ueber genau diesen Knoten, und er sieht beide Enden. Sobald einer von
  beiden weitere Nachbarn hat, ist das vorbei.
- Deine Einladung enthaelt deine Internetadressen. Wer die Textzeile hat,
  sieht, wo du online bist -- gib sie nur Menschen, denen du das zutraust.
- Ein Nachbar, der weiterreicht, sieht, dass zwei Codes Pakete austauschen --
  nicht, wer dahintersteht, und nicht, was drinsteht.
- Ein Signal eines laufenden Anrufs kann, wenn der erste Nachbar gerade
  nicht antwortet, ueber einen Knoten gehen, der beide Enden sieht; er
  erfaehrt, dass ihr gemeinsam telefoniert.
- Eine grosse Datei, der du zugestimmt hast, sieht der Rechner, der sie
  weiterreicht oder aufbewahrt, an beiden Enden (siehe Kapitel 4).
- Bei Anrufen gilt der Schutz vor dem Anbieter nicht, und dein Kontakt sieht
  deine Internetadresse (siehe Kapitel 7).

### Was passiert, wenn dein Gegenueber offline ist?

1. Cleona startet alle passenden Wege gleichzeitig: im selben WLAN direkt,
   im Internet ueber zwei Nachbarn -- und zusaetzlich den Briefkasten.
2. Fuer den Briefkasten legt Cleona die verschluesselte Nachricht bei drei
   Nachbarn ab. Sobald zwei den Empfang bestaetigt haben, gilt sie als
   abgelegt.
3. Cleona waehlt dafuer bevorzugt Nachbarn, bei denen dein Gegenueber auch
   nachschaut -- zuerst den Nachbarn, den seine Einladung nennt.
4. Die Nachricht wartet dort bis zu 7 Tage. Kommt dein Gegenueber zurueck,
   holt er sie ab und bestaetigt dir den Empfang. Erst dann siehst du zwei
   Haken.

Den Briefkasten kann nur dein Gegenueber leeren: Abholen und Loeschen geht
nur mit einem Schluessel, den nur er besitzt, und geloescht wird erst, wenn
er den Empfang bestaetigt hat. Die Nachbarn sehen nur verschluesselte
Pakete unter einem Wert, der jeden Tag wechselt.

### Fremde kommen nicht durch

Von jemandem, der weder dein Kontakt noch Mitglied einer gemeinsamen Gruppe
ist, nimmt Cleona genau zwei Dinge an:
die Frage nach deinen oeffentlichen Schluesseln, solange eine deiner
Einladungen offen ist, und eine Kontaktanfrage. Die Anfrage muss eine gueltige
Einladung von dir tragen, und der Absender muss vorher eine Rechenaufgabe
geloest haben. Alles andere -- Nachrichten, Anrufe, Dateien -- wird verworfen,
bevor es die App ueberhaupt erreicht. Wer nur deine gedruckte Visitenkarte
hat, kann dich also nicht einfach anrufen. Ein Mitglied einer gemeinsamen
Gruppe erreicht dich nur in dieser Gruppe -- mit Gruppennachrichten und
Gruppenanrufen, nie einzeln.

### Anti-Zensur

Cleona ist so gebaut, dass man es schwer blockieren kann:

- **Kein Server, keine feste Adresse.** In der App steht keine Adresse, die
  man sperren koennte, und das Netz haengt von keinem einzelnen Knoten ab.
- **Kein fester Port.** Jedes Geraet waehlt beim ersten Start einen
  zufaelligen Port. Es gibt keine bekannte Portnummer, an der man
  Cleona-Verkehr erkennen koennte.
- **Wie Zufallsdaten.** Der Verbindungsaufbau zwischen zwei Geraeten ist so
  kodiert, dass er von Zufallsdaten nicht zu unterscheiden ist.
- **Viele Einstiege.** Jede Einladung, jeder Nachbar und jedes Geraet im
  selben WLAN ist ein moeglicher Weg zurueck ins Netz.

### Sichere Schluesselspeicherung

Auf unterstuetzten Plattformen speichert Cleona deine Verschluesselungs-
Schluessel im sicheren Schluesselring des Betriebssystems (Android Keystore,
iOS Keychain, macOS Keychain). Wo verfuegbar, bietet das hardwaregestuetzten
Schutz fuer deine Schluessel.

### Datenbank-Verschluesselung

Deine Nachrichten und Unterhaltungen liegen in einer verschluesselten
Datenbank -- eine eigene fuer jede Identitaet, jede mit eigenem Schluessel.
Verschluesselt ist nicht nur die Datenbank selbst, sondern auch ihre
Zwischendateien; nichts wird unverschluesselt auf die Platte geschrieben,
auch nicht kurzzeitig. Einstellungen, Kontakte und Medien sind ebenfalls
verschluesselt gespeichert.

Die Schluessel werden aus deinen 24 Woertern abgeleitet und existieren nur
auf deinem Geraet. Selbst wer dein Geraet in die Haende bekommt und die Daten
ausliest, findet ohne diese Schluessel nur unlesbare Daten.

Unverschluesselt wird es nur, wo du Inhalte selbst aus Cleona hinausgibst:
- wenn du eine Datei aus einem Chat auf dein Geraet speicherst,
- wenn du mit dem Screenshot-Knopf ein Bild in deine Bilder legst,
- wenn du etwas an eine andere App teilst,
- wenn du die Media-Archivierung einrichtest (Kapitel 13): Die archivierten
  Originale liegen unverschluesselt auf deinem Netzwerkspeicher zu Hause,
  damit du sie dort auch ohne Cleona oeffnen kannst,
- wenn du Termine in den Android-Systemkalender spiegelst: Dort koennen
  andere Apps mit Kalenderzugriff sie lesen.

Was so hinausgegangen ist, wird nicht mit der Nachricht geloescht und laeuft
nicht mit ihr ab.

### Schutz auf dem Bildschirm

Auf Android, Windows und macOS laesst Cleona keine Bildschirmaufnahme durch
andere Apps zu. Brauchst du ein Bild, nimm den Screenshot-Knopf in der oberen
Leiste: Er legt das Bild in deine Bilder -- unverschluesselt. In einer
Unterhaltung, in der Weiterleiten nicht erlaubt ist, gibt es keinen
Screenshot.

---

## 15. Software-Updates

### Wie bekomme ich Updates?

Cleona kann auf verschiedenen Wegen aktualisiert werden. Das Ziel ist, dass
du auch dann Updates erhalten kannst, wenn einzelne Vertriebswege ausfallen
oder gesperrt werden:

1. **App Store / Play Store:** Sobald Cleona dort erscheint und du es ueber
   einen Store installiert hast, erhaeltst du Updates wie gewohnt ueber den
   Store. Auf dem iPhone kommen Updates ueber TestFlight.
2. **GitHub Releases:** Auf der GitHub-Seite des Projekts findest du
   signierte Installationspakete fuer alle Plattformen.
3. **Updates ueber das Netz:** Cleona kann ein Update direkt ueber das Netz
   beziehen -- ohne Download-Server. Die neue Version ist in
   fehlerkorrigierte Stuecke zerlegt, die sich im Netz verteilen; ein Teil
   davon reist sogar im Tarnstrom mit. Dein Geraet sammelt genug Stuecke und
   setzt das Update zusammen. Uebertragen wird meist nur die Aenderung --
   wenige MB statt der ganzen App. Das gilt fuer Linux, Windows und Android;
   unter macOS laedst du neue Versionen von der Website oder von GitHub.
4. **Einladungslinks:** Du kannst Einladungslinks erstellen, die alles
   enthalten, was ein neuer Nutzer braucht, um Cleona zu installieren und
   sich mit dem Netz zu verbinden.
5. **Physischer Transfer:** In Umgebungen ohne Internet kannst du Cleona
   per USB-Stick oder im lokalen Netzwerk an andere weitergeben.

### So laeuft ein Update ab

1. Cleona sammelt die Stuecke eines neuen Updates automatisch im Hintergrund
   und setzt sie zusammen.
2. Erst wenn das Update **vollstaendig** ist und seine **Signatur geprueft**
   wurde, bietet Cleona es dir an. Du bekommst also nie ein halbes oder
   ungeprueftes Update angeboten.
3. Tippst du auf "Installieren", startet die Installation ohne weitere
   Rueckfrage. Auf Android zeigt zusaetzlich das System seinen
   Installationsdialog.

Aeltere Versionen werden nicht angeboten -- ein Update geht immer nur
vorwaerts. Ist eine Version so alt, dass sie mit dem Netz nicht mehr
zusammenarbeiten kann, zeigt Cleona das deutlich an und bittet dich, zu
aktualisieren.

### Signaturpruefung

Jedes Update ist doppelt unterschrieben: mit einem klassischen und einem
Post-Quantum-Verfahren. Cleona prueft beide Unterschriften automatisch. So
ist sichergestellt, dass nur Updates vom offiziellen Entwickler akzeptiert
werden -- auch wenn das Update ueber das Netz von fremden Geraeten kam. Ein
Update entsteht nie automatisch aus der Entwicklung, sondern nur, wenn der
Entwickler es von Hand unterschreibt.

---

## 16. Haeufige Fragen

### "Kann ich Cleona ohne Internet nutzen?"

Cleona braucht eine Netzwerkverbindung, aber nicht unbedingt das Internet:
Im selben WLAN finden sich Cleona-Geraete selbst und koennen ganz ohne
Internetzugang miteinander schreiben. Gleichzeitig online sein musst du mit
deinem Gegenueber nicht: Ist er offline, wartet die Nachricht bis zu 7 Tage
im Briefkasten bei drei Nachbarn, bis er sie abholt.

### "Was wenn ich meine Seed-Phrase verliere?"

Solange noch ein Geraet mit deiner Identitaet laeuft, ist nichts verloren --
dort schreibst du einfach weiter. Auf dem Geraet, auf dem du die Identitaet
angelegt hast, kannst du die 24 Woerter meist erneut ablesen (siehe
Kapitel 2). Verlass dich nicht darauf: Eine Neuinstallation raeumt diese
Kopie weg, und auf Android vernichtet auch das Entfernen oder Aendern der
Bildschirmsperre sie. Hast du weder die Woerter noch ein Geraet, gibt es
keinen Weg zurueck -- auch nicht ueber deine Kontakte, den Entwickler oder
irgendjemand sonst. Deshalb ist es so wichtig, die 24 Woerter sicher
aufzubewahren.

### "Kann jemand meine Nachrichten mitlesen?"

Nein. Jede Nachricht wird mit einem einmaligen Schluessel verschluesselt, der
nur fuer diese eine Nachricht gilt. Nur du und dein Gegenueber koennen die
Nachricht entschluesseln. Es gibt keinen zentralen Server, keinen Generalschluessel
und keinen Zugang fuer den Entwickler. Selbst wenn ein Geraet auf dem
Transportweg die Nachricht weiterleitet, sieht es nur verschluesselten Datenbrei
und einen Code. Dein Nachbar weiss, dass das Paket von dir kommt, aber nicht,
an wen es geht; der Nachbar deines Gegenueber weiss, an wen es geht, aber
nicht, von wem.

### "Warum brauche ich keine Telefonnummer?"

Weil deine Identitaet rein kryptografisch ist. Statt einer Telefonnummer oder
E-Mail-Adresse, die mit deinem echten Namen verknuepft ist, identifiziert dich
ein Schluesselpaar, das auf deinem Geraet erzeugt wurde. Kontakte fuegst du
per QR-Code, NFC oder die Textzeile deiner Einladung hinzu -- nicht ueber ein
Telefonbuch. Das bedeutet
mehr Privatsphaere, weil dein Messenger-Konto nicht an deine reale Identitaet
gebunden ist.

### "Wie finde ich Leute auf Cleona?"

Cleona hat bewusst keine Kontaktsuche nach Telefonnummer oder Name -- das waere
ein Privatsphaere-Problem. Stattdessen tauschst du Einladungen direkt aus: per
QR-Code, NFC oder als Textzeile ueber einen anderen Weg. Das ist wie
Visitenkarten austauschen statt im Telefonbuch nachschlagen.

### "Funktioniert Cleona auch im Ausland?"

Ja. Solange du eine Internetverbindung hast, funktioniert Cleona ueberall auf
der Welt. Da es keinen zentralen Server und keine feste Adresse gibt, laesst
sich der Dienst nicht einfach fuer bestimmte Laender abschalten. Wie Cleona
Sperren erschwert, steht im Kapitel "Sicherheit" unter "Anti-Zensur". Ein Land,
das jeden unbekannten Verkehr an der Grenze blockiert, kann allerdings auch
Cleona aufhalten.

### "Ist Cleona kostenlos?"

Ja. Cleona ist kostenlos und ohne Werbung nutzbar. Da es keinen zentralen
Server gibt, fallen auch keine Serverkosten fuer den Betrieb an. In den
Einstellungen unter "Unterstuetze Cleona" -> "Spenden" kannst du die
Entwicklung freiwillig unterstuetzen.

### "Meine Nachricht hat nur einen Haken -- was bedeutet das?"

Die Nachricht ist unterwegs, aber dein Gegenueber hat den Empfang noch nicht
bestaetigt -- meistens, weil er gerade offline ist. Das ist kein Fehler: Die
Nachricht wartet bis zu 7 Tage im Briefkasten. Sobald er sie abholt, siehst du
zwei Haken. Eine Uhr bedeutet, dass noch kein Weg die Nachricht getragen hat
-- sie geht von selbst los, sobald einer da ist; ein Warnzeichen, dass sie
14 Tage lang keinen Weg gefunden hat und du sie erneut senden kannst.

### "Warum kommen Nachrichten auf meinem iPhone verspaetet?"

iOS laesst Apps im Hintergrund nicht dauerhaft laufen. Cleona wird nur
gelegentlich kurz geweckt; wann, bestimmt iOS. Dann holt es alles ab. Sobald
du die App oeffnest, holt Cleona ab, was fuer dich aufbewahrt wurde.

### "Kann ich von WhatsApp zu Cleona wechseln?"

Ja, aber du kannst deine WhatsApp-Chats nicht uebertragen. Cleona und WhatsApp
sind grundverschiedene Systeme. Du musst deine Kontakte einzeln in Cleona
hinzufuegen. Am einfachsten geht das, wenn du die Textzeile deiner Einladung
an deine Kontakte schickst. Jede Anfrage, die so ankommt, bestaetigst du
selbst unter "Anfragen".

### "Kann ich Cleona auf mehreren Geraeten gleichzeitig nutzen?"

Noch nicht. Ein zweites Geraet fuer dieselbe Identitaet kommt mit einer
spaeteren Version (Kapitel 11). Auf mehreren Geraeten kannst du heute
verschiedene Identitaeten nutzen.

### "Wie bekomme ich Updates wenn der App Store gesperrt ist?"

Cleona kann Updates direkt ueber das Netz beziehen, ohne auf einen
App Store, eine Website oder einen Download-Server angewiesen zu sein. Wenn
ein anderes Geraet im Netz die neueste Version hat, kann dein Geraet das
Update von dort laden. Die Echtheit wird durch eine digitale Signatur des
Entwicklers geprueft. Alternativ kann dir ein Kontakt die App per
Einladungslink oder USB-Stick weitergeben. Mehr dazu im Kapitel
"Software-Updates".

---

## Hilfe und Kontakt

Wenn du Fragen hast oder auf ein Problem stoesst, findest du aktuelle
Informationen auf der Cleona-Website und auf GitHub. Da Cleona ein dezentrales
Projekt ist, gibt es keinen klassischen Kundensupport -- aber eine aktive
Gemeinschaft, die gerne hilft.

---

*Dieses Handbuch beschreibt Cleona Chat Version 4.2. Einzelne Funktionen
koennen sich in neueren Versionen aendern oder erweitern.*

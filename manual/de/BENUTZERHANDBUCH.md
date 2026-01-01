# Cleona Chat -- Benutzerhandbuch

Version 3.1 | Stand April 2026

---

## Inhaltsverzeichnis

1. [Was ist Cleona Chat?](#1-was-ist-cleona-chat)
2. [Erste Schritte](#2-erste-schritte)
3. [Kontakte](#3-kontakte)
4. [Nachrichten](#4-nachrichten)
5. [Gruppen](#5-gruppen)
6. [Oeffentliche Kanaele](#6-oeffentliche-kanaele)
7. [Anrufe](#7-anrufe)
8. [Mehrere Identitaeten](#8-mehrere-identitaeten)
9. [Wiederherstellung](#9-wiederherstellung)
10. [Einstellungen](#10-einstellungen)
11. [Sicherheit](#11-sicherheit)
12. [Haeufige Fragen](#12-haeufige-fragen)

---

## 1. Was ist Cleona Chat?

### Dein Messenger, deine Daten

Cleona Chat ist ein Messenger, der komplett ohne zentralen Server funktioniert.
Deine Nachrichten laufen direkt von deinem Geraet zum Geraet deines
Gegenueber -- ohne Umweg ueber einen Firmensitz, ohne Cloud, ohne
Datenzentrum. Kein Unternehmen kann deine Nachrichten lesen, speichern oder
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

Stell dir vor, du und deine Kontakte bilden zusammen ein Netz. Jedes Geraet
hilft dabei, Nachrichten weiterzuleiten. Ist dein Gegenueber gerade online,
geht die Nachricht direkt hin. Ist dein Gegenueber offline, speichern
gemeinsame Kontakte die Nachricht zwischen und liefern sie zu, sobald der
Empfaenger wieder da ist. Deine Kontakte sind also gleichzeitig auch dein
Netzwerk.

---

## 2. Erste Schritte

### App installieren

**Android:**
1. Lade die APK-Datei von der Cleona-Website herunter.
2. Oeffne die Datei auf deinem Handy. Falls noetig, erlaube die Installation
   aus unbekannten Quellen (Android fragt dich automatisch).
3. Tippe auf "Installieren" und warte, bis die Installation abgeschlossen ist.

**Linux (Ubuntu/Debian):**
1. Lade die .deb-Datei von der Cleona-Website oder von GitHub Releases herunter.
2. Installiere mit Doppelklick oder im Terminal: `sudo dpkg -i cleona-chat_VERSION_amd64.deb`
3. Starte Cleona ueber das Anwendungsmenue oder im Terminal mit `cleona-chat`.

**Linux (Fedora/openSUSE):**
1. Lade die .rpm-Datei von der Cleona-Website oder von GitHub Releases herunter.
2. Installiere mit: `sudo dnf install cleona-chat-VERSION.x86_64.rpm`
3. Starte Cleona ueber das Anwendungsmenue oder im Terminal mit `cleona-chat`.

**Linux (alle Distributionen — AppImage):**
1. Lade die .AppImage-Datei von der Cleona-Website oder von GitHub Releases herunter.
2. Mache die Datei ausfuehrbar: Rechtsklick → Eigenschaften → Ausfuehrbar, oder im Terminal: `chmod +x cleona-chat-VERSION-x86_64.AppImage`
3. Starte per Doppelklick oder im Terminal: `./cleona-chat-VERSION-x86_64.AppImage`

**Windows:**
1. Lade den Installer von der Cleona-Website herunter.
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
  koennte -- denn es gibt gar kein Konto auf einem Server.
- Gib die Seed-Phrase niemals an andere weiter. Wer diese Woerter kennt, kann
  sich als du ausgeben.

Du findest die Seed-Phrase spaeter auch in den Einstellungen unter
"Sicherheit", falls du sie noch einmal ablesen moechtest.

### Ersten Kontakt hinzufuegen

Um mit jemandem zu chatten, musst du die Person zuerst als Kontakt hinzufuegen.
Dafuer gibt es mehrere Wege -- alle davon werden im naechsten Abschnitt
erklaert.

---

## 3. Kontakte

### QR-Code scannen (empfohlen)

Der einfachste Weg, einen Kontakt hinzuzufuegen:

1. Dein Gegenueber oeffnet seine Identitaets-Detailseite (Tipp auf den eigenen
   Namen in der oberen Leiste) und zeigt dir seinen QR-Code.
2. Du tippst auf den Plus-Button und wahlst "QR-Code scannen".
3. Halte dein Handy vor den QR-Code deines Gegenueber.
4. Die Kontaktanfrage wird automatisch gesendet. Sobald dein Gegenueber sie
   annimmt, koennt ihr miteinander schreiben.

Wenn ihr euch persoenlich trefft, ist der QR-Code die sicherste Methode, weil
du dabei genau weisst, mit wem du den Kontakt austauschst.

### NFC (Handys aneinander halten)

Wenn beide Geraete NFC unterstuetzen:

1. Oeffnet beide die Kontakt-Hinzufuegen-Funktion.
2. Haltet eure Handys Ruecken an Ruecken aneinander.
3. Die Kontaktdaten werden automatisch ausgetauscht.

NFC bietet wie der QR-Code eine hohe Sicherheit, weil der Austausch nur
funktioniert, wenn ihr physisch nebeneinander steht.

### Link teilen (cleona://-URI)

Du kannst deinen Kontaktlink auch per E-Mail, SMS oder ueber einen anderen
Messenger verschicken:

1. Oeffne deine Identitaets-Detailseite.
2. Kopiere deinen cleona://-Link.
3. Sende den Link an die Person, die dich hinzufuegen soll.
4. Die andere Person oeffnet den Link, oder fuegt ihn im
   Kontakt-Hinzufuegen-Dialog ein.

Beachte: Bei dieser Methode vertraust du darauf, dass der Link auf dem
Uebertragungsweg nicht veraendert wurde. Fuer besonders sensible Kontakte
empfehlen wir QR-Code oder NFC.

### Kontaktanfragen annehmen

Wenn jemand dir eine Kontaktanfrage sendet, erscheint sie in deiner Inbox (der
letzte Tab in der unteren Leiste). Dort kannst du:

- **Annehmen** -- die Person wird zu deinen Kontakten hinzugefuegt.
- **Ablehnen** -- die Anfrage wird verworfen.
- **Blockieren** -- die Person kann dir keine weiteren Anfragen schicken.

### Verifikationsstufen

Cleona zeigt dir an, wie sicher die Identitaet eines Kontakts bestaetigt ist:

| Stufe | Bedeutung |
|-------|-----------|
| Unbekannt | Du hast nur die Node-ID oder einen Link erhalten. |
| Gesehen | Der Schluesselaustausch war erfolgreich, ihr koennt verschluesselt kommunizieren. |
| Verifiziert | Ihr habt euch persoenlich getroffen und per QR-Code oder NFC verifiziert. |
| Vertraut | Du hast diesen Kontakt explizit als vertrauenswuerdig markiert. |

Je hoeher die Stufe, desto sicherer kannst du sein, dass du wirklich mit der
richtigen Person sprichst.

---

## 4. Nachrichten

### Text senden und empfangen

Tippe einfach deine Nachricht ins Eingabefeld unten und druecke Enter oder den
Senden-Button. Deine Nachricht wird automatisch verschluesselt, bevor sie dein
Geraet verlaesst.

Eingehende Nachrichten erscheinen im Chat-Verlauf. Ein Haekchen zeigt dir, ob
deine Nachricht zugestellt wurde.

### Bilder, Videos und Dateien senden

Du hast mehrere Moeglichkeiten:

- **Bueroklammer-Icon** im Eingabefeld: Tippe darauf, um eine Datei, ein Bild
  oder ein Video aus deiner Galerie oder deinem Dateisystem auszuwaehlen.
- **Drag and Drop** (Desktop): Ziehe eine Datei einfach in das Chat-Fenster.
- **Aus der Zwischenablage einfuegen** (Desktop): Kopiere ein Bild und fuege
  es im Chat ein.

Kleine Dateien (unter 256 KB) werden direkt mitgeschickt. Groessere Dateien
werden in einem zweistufigen Verfahren uebertragen: Erst wird die Datei
angekuendigt, dann in Teilen uebermittelt.

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

Du kannst deine eigenen Nachrichten innerhalb von 15 Minuten nach dem Senden
bearbeiten oder loeschen:

- **Bearbeiten:** Drei-Punkte-Menue der Nachricht, dann "Bearbeiten".
  Aendere den Text und sende ihn erneut. Dein Gegenueber sieht, dass die
  Nachricht bearbeitet wurde.
- **Loeschen:** Drei-Punkte-Menue der Nachricht, dann "Loeschen". Die
  Nachricht wird bei dir und deinem Gegenueber entfernt.

Nach Ablauf der 15 Minuten sind Bearbeiten und Loeschen nicht mehr moeglich.

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

Wenn du auf einen empfangenen Link tippst, wirst du gefragt, ob du ihn im
normalen Browser, im Inkognito-Modus oder gar nicht oeffnen moechtest.

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
3. Bestatige deine Entscheidung.

Wenn du eine Gruppe verlaesst, bleiben deine bisherigen Nachrichten fuer die
anderen Mitglieder sichtbar.

---

## 6. Oeffentliche Kanaele

### Was sind Kanaele?

Kanaele sind oeffentliche Diskussionsforen innerhalb des Cleona-Netzwerks.
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
werden von zufaellig ausgewaehlten Mitgliedern des Netzwerks bewertet (eine Art
"Geschworenengericht"). Wird ein Verstoss festgestellt, erhaelt der Kanal eine
Warnung. Bei wiederholten Verstoessen wird er im Suchindex herabgestuft oder
gesperrt.

---

## 7. Anrufe

### Sprachanruf starten

1. Oeffne den Chat mit dem Kontakt, den du anrufen moechtest.
2. Tippe auf das Telefon-Symbol in der oberen Leiste.
3. Warte, bis dein Gegenueber den Anruf annimmt.

Waehrend des Gespraechs siehst du eine Zeitleiste, die Gespraechsdauer und
hast Zugriff auf Stummschalten und Lautsprecher.

Zum Auflegen tippe auf den roten Auflegen-Button.

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

Wenn du bereits in einem Gespraech bist, wird ein neuer Anruf automatisch
abgelehnt.

### Gruppenanrufe

Du kannst auch Gruppenanrufe fuehren, an denen mehrere Personen gleichzeitig
teilnehmen. Der Anruf wird ueber einen intelligenten Weiterleitungsbaum
organisiert, sodass nicht jeder Teilnehmer mit jedem anderen direkt verbunden
sein muss. Alle Gespraeche sind durchgehend verschluesselt.

### Verschluesselung bei Anrufen

Alle Anrufe werden mit einmaligen Schluesseln verschluesselt, die nur fuer
die Dauer des Gespraechs existieren. Nach dem Auflegen werden diese Schluessel
sofort geloescht. Niemand kann ein vergangenes Gespraech nachtraeglich
entschluesseln.

---

## 8. Mehrere Identitaeten

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

## 9. Wiederherstellung

### Seed-Phrase verwenden

Wenn du dein Geraet verlierst oder ein neues einrichtest:

1. Installiere Cleona auf dem neuen Geraet.
2. Waehle beim Start "Wiederherstellen".
3. Gib deine 24 Woerter ein.
4. Cleona stellt deine Identitaet wieder her und kontaktiert automatisch deine
   bisherigen Kontakte.
5. Deine Kontakte antworten mit deinen Kontaktdaten, Gruppenmitgliedschaften
   und Nachrichtenverlaeufen.

Die Wiederherstellung geschieht in drei Schritten:
- Zuerst kommen deine Kontakte und Gruppen zurueck.
- Dann die letzten 50 Nachrichten aus jeder Unterhaltung.
- Zuletzt der vollstaendige Nachrichtenverlauf.

Es genuegt, wenn ein einziger deiner Kontakte online ist, damit die
Wiederherstellung funktioniert.

### Guardian Recovery (Vertrauenspersonen)

Du kannst bis zu fuenf Vertrauenspersonen als "Guardians" benennen. Dabei wird
dein Wiederherstellungsschluessel in fuenf Teile aufgeteilt, von denen jeder
Guardian einen erhaelt. Um deine Identitaet wiederherzustellen, genuegen drei
der fuenf Teile.

Das bedeutet: Selbst wenn du deine Seed-Phrase verloren hast, koennen drei
deiner Guardians zusammen dein Konto wiederherstellen. Kein einzelner Guardian
kann allein auf deine Daten zugreifen -- es werden immer mindestens drei
benoetigt.

So richtest du Guardians ein:
1. Oeffne die Einstellungen.
2. Gehe zu "Sicherheit".
3. Waehle "Guardian Recovery".
4. Waehle fuenf vertrauenswuerdige Kontakte aus.

### Warum Kontakte dein Backup sind

In herkoemmlichen Messengern liegen deine Daten auf den Servern des Anbieters.
Bei Cleona gibt es keinen Server -- aber deine Kontakte uebernehmen diese Rolle.
Wenn du eine Nachricht sendest, speichern gemeinsame Kontakte eine verschluesselte
Kopie fuer den Fall, dass der Empfaenger gerade offline ist. Bei einer
Wiederherstellung liefern deine Kontakte dir deine Daten zurueck.

Das heisst: Je mehr aktive Kontakte du hast, desto zuverlaessiger ist dein
Backup. Ein Kontakt, der regelmaessig online ist, reicht fuer eine
erfolgreiche Wiederherstellung aus.

---

## 10. Einstellungen

Die Einstellungen erreichst du ueber das Zahnrad-Symbol in der oberen rechten
Ecke.

### Benachrichtigungen und Klingeltoene

- Waehle aus sechs verschiedenen Klingeltoenen fuer eingehende Anrufe.
- Stelle einen Nachrichtenton ein.
- Auf Android-Geraeten kannst du zusaetzlich die Vibration aktivieren oder
  deaktivieren.

### Designs (Skins)

Cleona bietet neun verschiedene Designs an, von hell und farbenfroh bis dunkel
und dezent. Darunter befindet sich auch ein spezielles Kontrastdesign, das die
hoechste Zugaenglichkeitsstufe (WCAG AAA) erfuellt und bei eingeschraenktem
Sehvermoegen besonders gut lesbar ist.

Jede Identitaet kann ihr eigenes Design haben. Du aenderst das Design in der
Identitaets-Detailseite (Tipp auf den aktiven Identitaets-Tab).

Zusaetzlich kannst du in den Einstellungen unter "Darstellung" zwischen
hellem, dunklem und dem System-Theme wechseln.

### Sprache aendern

Cleona ist in 33 Sprachen verfuegbar, darunter auch Sprachen mit
Rechts-nach-Links-Schrift (z.B. Arabisch, Hebraeisch). Aendere die Sprache in
den Einstellungen unter "Sprache".

### Speicherlimit

Du kannst festlegen, wie viel Speicherplatz Cleona auf deinem Geraet nutzen
darf (zwischen 100 MB und 2 GB). Wenn das Limit erreicht ist, werden aeltere
Medien automatisch ausgelagert oder geloescht -- Textnachrichten bleiben immer
erhalten.

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

### Transkription fuer Sprachnachrichten

Wenn aktiviert, werden deine Sprachnachrichten lokal auf deinem Geraet in
Text umgewandelt (mit dem Open-Source-Modell Whisper). Der transkribierte Text
wird zusammen mit der Aufnahme an dein Gegenueber geschickt. Die Transkription
geschieht komplett auf deinem Geraet -- keine Daten gehen an externe Dienste.

### Auto-Download

Du kannst einstellen, ab welcher Groesse Medien automatisch heruntergeladen
werden sollen. So kannst du zum Beispiel Bilder automatisch laden lassen, aber
bei grossen Videos manuell entscheiden.

---

## 11. Sicherheit

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

Bei Cleona gibt es keinen solchen zentralen Punkt. Deine Nachrichten reisen
direkt von Geraet zu Geraet. Es gibt keinen Ort, an dem alle Metadaten
zusammenlaufen. Niemand kann anhand eines einzigen Datenpunkts dein
Kommunikationsverhalten rekonstruieren.

### Was passiert wenn du offline bist?

Wenn du eine Nachricht sendest und der Empfaenger offline ist:

1. Cleona versucht zunaechst, die Nachricht direkt zuzustellen.
2. Wenn das nicht klappt, wird sie ueber gemeinsame Kontakte weitergeleitet.
3. Gleichzeitig wird die Nachricht als verschluesselte Stuecke auf mehrere
   Knoten im Netzwerk verteilt (aehnlich wie ein Puzzle, das aus 10 Teilen
   besteht, von denen 7 genuegen, um das Bild zusammenzusetzen).
4. Die Nachricht wird bis zu 7 Tage lang aufbewahrt.

Sobald der Empfaenger wieder online kommt, werden die Nachrichten zugestellt.
Du bekommst eine Bestaetigung, wenn deine Nachricht angekommen ist.

### Datenbank-Verschluesselung

Alle deine Nachrichten, Kontakte und Einstellungen sind auf deinem Geraet
verschluesselt gespeichert. Selbst wenn jemand Zugriff auf dein Dateisystem
bekaeme, koennte er ohne deinen kryptografischen Schluessel nichts lesen.
Dieser Schluessel wird aus deiner Identitaet abgeleitet und existiert nur auf
deinem Geraet.

---

## 12. Haeufige Fragen

### "Kann ich Cleona ohne Internet nutzen?"

Nein, Cleona braucht eine Netzwerkverbindung, um Nachrichten zu senden und zu
empfangen. Allerdings musst du nicht gleichzeitig mit deinem Gegenueber online
sein: Nachrichten, die gesendet werden waehrend der Empfaenger offline ist,
werden zwischengespeichert und automatisch zugestellt, sobald beide Seiten
wieder verbunden sind. Im lokalen Netzwerk (z.B. im selben WLAN) koennt ihr
auch ganz ohne Internetzugang miteinander kommunizieren.

### "Was wenn ich meine Seed-Phrase verliere?"

Wenn du Guardians eingerichtet hast, koennen drei von fuenf
Vertrauenspersonen gemeinsam deinen Zugang wiederherstellen. Ohne Guardians
und ohne Seed-Phrase gibt es leider keinen Weg, deine Identitaet
zurueckzubekommen. Deshalb ist es so wichtig, die 24 Woerter sicher
aufzubewahren.

### "Kann jemand meine Nachrichten mitlesen?"

Nein. Jede Nachricht wird mit einem einmaligen Schluessel verschluesselt, der
nur fuer diese eine Nachricht gilt. Nur du und dein Gegenueber koennen die
Nachricht entschluesseln. Es gibt keinen zentralen Server, keinen Generalschluessel
und keinen Zugang fuer den Entwickler. Selbst wenn ein Geraet auf dem
Transportweg die Nachricht weiterleitet, sieht es nur verschluesselten Datenbrei.

### "Warum brauche ich keine Telefonnummer?"

Weil deine Identitaet rein kryptografisch ist. Statt einer Telefonnummer oder
E-Mail-Adresse, die mit deinem echten Namen verknuepft ist, identifiziert dich
ein Schluesselpaar, das auf deinem Geraet erzeugt wurde. Kontakte fuegst du
per QR-Code, NFC oder Link hinzu -- nicht ueber ein Telefonbuch. Das bedeutet
mehr Privatsphaere, weil dein Messenger-Konto nicht an deine reale Identitaet
gebunden ist.

### "Wie finde ich Leute auf Cleona?"

Cleona hat bewusst keine Kontaktsuche nach Telefonnummer oder Name -- das waere
ein Privatsphaere-Problem. Stattdessen tauschst du Kontaktdaten direkt aus: per
QR-Code, NFC, cleona://-Link oder in oeffentlichen Kanaelen. Das ist wie
Visitenkarten austauschen statt im Telefonbuch nachschlagen.

### "Funktioniert Cleona auch im Ausland?"

Ja. Solange du eine Internetverbindung hast, funktioniert Cleona ueberall auf
der Welt. Da es keinen zentralen Server gibt, kann der Dienst auch nicht fuer
bestimmte Laender gesperrt werden. Cleona verfuegt zudem ueber einen
Anti-Zensur-Fallback: Wenn die normale Verbindung (UDP) blockiert wird,
wechselt Cleona automatisch auf eine alternative Uebertragung (TLS), die
schwerer zu erkennen und zu blockieren ist.

### "Ist Cleona kostenlos?"

Ja. Cleona ist kostenlos und ohne Werbung nutzbar. Da es keinen zentralen
Server gibt, fallen auch keine Serverkosten fuer den Betrieb an. In der App
findest du unter "Spende" die Moeglichkeit, die Entwicklung freiwillig zu
unterstuetzen.

### "Meine Nachricht hat ein Uhrsymbol -- was bedeutet das?"

Das bedeutet, dass die Nachricht noch nicht zugestellt wurde. Dein Gegenueber
ist vermutlich gerade offline. Sobald die Nachricht zugestellt ist, aendert
sich das Symbol. Nachrichten werden bis zu 7 Tage lang fuer die Zustellung
aufbewahrt.

### "Kann ich von WhatsApp zu Cleona wechseln?"

Ja, aber du kannst deine WhatsApp-Chats nicht uebertragen. Cleona und WhatsApp
sind grundverschiedene Systeme. Du musst deine Kontakte einzeln in Cleona
hinzufuegen. Am einfachsten geht das, wenn du deinen cleona://-Link in eine
WhatsApp-Gruppe postest und bittest, dass dich die anderen dort hinzufuegen.

### "Kann ich Cleona auf mehreren Geraeten gleichzeitig nutzen?"

Derzeit laeuft Cleona auf einem Geraet pro Identitaet. Du kannst aber mehrere
Identitaeten haben und verschiedene Identitaeten auf verschiedenen Geraeten
nutzen. Die Multi-Geraete-Synchronisation fuer eine einzelne Identitaet ist
fuer eine zukuenftige Version geplant.

---

## Hilfe und Kontakt

Wenn du Fragen hast oder auf ein Problem stoesst, findest du aktuelle
Informationen auf der Cleona-Website. Da Cleona ein dezentrales Projekt ist,
gibt es keinen klassischen Kundensupport -- aber eine aktive Gemeinschaft, die
gerne hilft.

---

*Dieses Handbuch beschreibt Cleona Chat Version 3.1. Einzelne Funktionen
koennen sich in neueren Versionen aendern oder erweitern.*

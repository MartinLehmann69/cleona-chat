# Cleona Chat -- Gebruikershandleiding

Version 3.1.125 | juli 2026

---

## Inhoudsopgave

1. [Wat is Cleona Chat?](#1-wat-is-cleona-chat)
2. [Aan de slag](#2-aan-de-slag)
3. [Contacten](#3-contacten)
4. [Berichten](#4-berichten)
5. [Groepen](#5-groepen)
6. [Openbare kanalen](#6-openbare-kanalen)
7. [Oproepen](#7-oproepen)
8. [Agenda](#8-agenda)
9. [Peilingen](#9-peilingen)
10. [Meerdere identiteiten](#10-meerdere-identiteiten)
11. [Multi-Device](#11-multi-device)
12. [Herstel](#12-herstel)
13. [Instellingen](#13-instellingen)
14. [Veiligheid](#14-veiligheid)
15. [Software-updates](#15-software-updates)
16. [Veelgestelde vragen](#16-veelgestelde-vragen)

---

## 1. Wat is Cleona Chat?

### Jouw messenger, jouw gegevens

Cleona Chat is een messenger die volledig zonder centrale server werkt.
Je berichten gaan rechtstreeks van jouw apparaat naar het apparaat van
de ander -- zonder omweg via een bedrijfszetel, zonder cloud, zonder
datacenter. Geen enkel bedrijf kan je berichten lezen, opslaan of
doorgeven, simpelweg omdat er geen bedrijf tussen zit.

### Geen account, geen telefoonnummer

Bij Cleona heb je geen telefoonnummer of e-mailadres nodig om je aan te
melden. Je identiteit bestaat uit een cryptografisch sleutelpaar dat bij
de eerste start automatisch op je apparaat wordt gegenereerd. Dat betekent:
niemand kan je opsporen via je telefoonnummer of e-mailadres, tenzij je
zelf je contactgegevens deelt.

### Toekomstbestendige versleuteling

Cleona maakt gebruik van zogenaamde post-quantumversleuteling. Dat
betekent: zelfs toekomstige quantumcomputers zouden je berichten niet
kunnen kraken. Je hoeft de details niet te begrijpen -- belangrijk is
alleen dat je communicatie volgens de huidige stand van de techniek zo
goed mogelijk beschermd is.

### Hoe werkt dat zonder server?

Stel je voor dat jij en je contacten samen een netwerk vormen. Elk
apparaat helpt mee berichten door te sturen. Is de ander op dat moment
online, dan gaat het bericht rechtstreeks naartoe. Is de ander offline,
dan bewaren gemeenschappelijke contacten het bericht tijdelijk en
leveren het af zodra de ontvanger er weer is. Je contacten zijn dus
tegelijk ook je netwerk.

### Platforms

Cleona is beschikbaar voor Android, iOS, macOS, Linux en Windows.

---

## 2. Aan de slag

### App installeren

**Android:**
1. Download het APK-bestand van de Cleona-website of van GitHub Releases.
2. Open het bestand op je telefoon. Sta indien nodig installatie van
   onbekende bronnen toe (Android vraagt dit automatisch).
3. Tik op "Installeren" en wacht tot de installatie voltooid is.

**iOS:**
1. Open de TestFlight-uitnodigingslink op je iPhone.
2. Tik op "Installeren". TestFlight is Apples officiële manier om
   bèta-apps te verspreiden.
3. Na de installatie vind je Cleona op je startscherm.

**macOS:**
1. Download het DMG-bestand van de Cleona-website of van GitHub Releases.
2. Open het DMG-bestand en sleep Cleona naar je Programma's-map.
3. Bij de eerste start vraagt macOS mogelijk of je de app van een
   geïdentificeerde ontwikkelaar wilt openen -- bevestig dit.

**Linux (Ubuntu/Debian):**
1. Download het .deb-bestand van de Cleona-website of van GitHub Releases.
2. Installeer met een dubbelklik of in de terminal: `sudo dpkg -i cleona-chat_VERSION_amd64.deb`
3. Start Cleona via het toepassingenmenu of in de terminal met `cleona-chat`.

**Linux (Fedora/openSUSE):**
1. Download het .rpm-bestand van de Cleona-website of van GitHub Releases.
2. Installeer met: `sudo dnf install cleona-chat-VERSION.x86_64.rpm`
3. Start Cleona via het toepassingenmenu of in de terminal met `cleona-chat`.

**Linux (alle distributies -- AppImage):**
1. Download het .AppImage-bestand van de Cleona-website of van GitHub Releases.
2. Maak het bestand uitvoerbaar: rechtermuisknop, Eigenschappen, Uitvoerbaar, of in de terminal: `chmod +x cleona-chat-VERSION-x86_64.AppImage`
3. Start met een dubbelklik of in de terminal: `./cleona-chat-VERSION-x86_64.AppImage`

**Windows:**
1. Download het installatieprogramma van de Cleona-website of van GitHub Releases.
2. Voer het installatiebestand uit en volg de instructies.
3. Start Cleona via het startmenu of de snelkoppeling op het bureaublad.

### Identiteit aanmaken

Bij de eerste start maakt Cleona automatisch een nieuwe identiteit voor
je aan. Je kunt jezelf een weergavenaam geven -- dat is de naam die je
contacten zien. Deze naam kun je op elk moment wijzigen.

### Seed-phrase opschrijven -- het allerbelangrijkste

Nadat je identiteit is aangemaakt, toont Cleona je 24 woorden. Dit is je
**seed-phrase** -- je persoonlijke herstelsleutel.

**Schrijf deze 24 woorden op papier en bewaar ze veilig.**

Waarom is dit zo belangrijk?

- Als je telefoon kapotgaat, verloren raakt of gestolen wordt, kun je met
  deze 24 woorden je volledige identiteit op een nieuw apparaat
  herstellen.
- Zonder de seed-phrase is er geen weg terug. Er is geen "wachtwoord
  vergeten"-knop en geen support die je account voor je kan
  terughalen -- want er is helemaal geen account op een server.
- Deel de seed-phrase nooit met anderen. Wie deze woorden kent, kan zich
  voordoen als jou.

Je vindt de seed-phrase later ook terug in de instellingen onder
"Veiligheid", mocht je hem nog een keer willen aflezen.

### Eerste contact toevoegen

Om met iemand te chatten, moet je die persoon eerst als contact
toevoegen. Daarvoor zijn er meerdere manieren -- die worden allemaal in
de volgende paragraaf uitgelegd.

---

## 3. Contacten

### QR-code scannen (aanbevolen)

De eenvoudigste manier om een contact toe te voegen:

1. De ander opent zijn identiteitsdetailpagina (tik op de eigen naam in
   de bovenste balk) en laat je zijn QR-code zien.
2. Jij tikt op de plusknop en kiest "QR-code scannen".
3. Houd je telefoon voor de QR-code van de ander.
4. Het contactverzoek wordt automatisch verzonden. Zodra de ander het
   accepteert, kunnen jullie met elkaar chatten.

Als jullie elkaar persoonlijk ontmoeten, is de QR-code de veiligste
methode, omdat je dan precies weet met wie je het contact uitwisselt.

### NFC (telefoons tegen elkaar houden)

Als beide apparaten NFC ondersteunen:

1. Open op beide toestellen de functie Contact toevoegen.
2. Houd jullie telefoons rug tegen rug tegen elkaar.
3. De contactgegevens worden automatisch uitgewisseld.

NFC biedt, net als de QR-code, een hoge mate van veiligheid, omdat de
uitwisseling alleen werkt als jullie fysiek naast elkaar staan.

### Link delen (cleona://-URI)

Je kunt je contactlink ook per e-mail, sms of via een andere messenger
versturen:

1. Open je identiteitsdetailpagina.
2. Kopieer je cleona://-link.
3. Stuur de link naar de persoon die je wilt toevoegen.
4. De andere persoon opent de link, of plakt hem in het dialoogvenster
   Contact toevoegen.

Let op: bij deze methode vertrouw je erop dat de link tijdens de
overdracht niet is aangepast. Voor bijzonder gevoelige contacten raden
we QR-code of NFC aan.

### Contactverzoeken accepteren

Als iemand je een contactverzoek stuurt, verschijnt dit in je inbox (het
laatste tabblad in de onderste balk). Daar kun je:

- **Accepteren** -- de persoon wordt toegevoegd aan je contacten.
- **Weigeren** -- het verzoek wordt verworpen.
- **Blokkeren** -- de persoon kan je geen nieuwe verzoeken meer sturen.

### Verificatieniveaus

Cleona laat je zien hoe zeker de identiteit van een contact is
bevestigd:

| Niveau | Betekenis |
|-------|-----------|
| Onbekend | Je hebt alleen de node-ID of een link ontvangen. |
| Gezien | De sleuteluitwisseling is gelukt, jullie kunnen versleuteld communiceren. |
| Geverifieerd | Jullie hebben elkaar persoonlijk ontmoet en via QR-code of NFC geverifieerd. |
| Vertrouwd | Je hebt dit contact expliciet als vertrouwd gemarkeerd. |

Hoe hoger het niveau, hoe zekerder je kunt zijn dat je echt met de juiste
persoon spreekt.

---

## 4. Berichten

### Tekst versturen en ontvangen

Typ je bericht gewoon in het invoerveld onderaan en druk op Enter of de
verzendknop. Je bericht wordt automatisch versleuteld voordat het je
apparaat verlaat.

Binnenkomende berichten verschijnen in de chatgeschiedenis. Een vinkje
laat zien of je bericht is afgeleverd.

### Afbeeldingen, video's en bestanden versturen

Je hebt meerdere mogelijkheden:

- **Paperclip-icoon** in het invoerveld: tik erop om een bestand, foto
  of video uit je galerij of bestandssysteem te kiezen.
- **Slepen en neerzetten** (desktop): sleep een bestand gewoon naar het
  chatvenster.
- **Plakken vanuit het klembord** (desktop): kopieer een afbeelding en
  plak deze in de chat.

Kleine bestanden (onder 256 KB) worden direct meegestuurd. Grotere
bestanden worden in twee stappen overgedragen: eerst wordt het bestand
aangekondigd, daarna in delen verzonden.

### Spraakberichten

1. Houd de microfoonknop in het invoerveld ingedrukt.
2. Spreek je bericht in.
3. Laat de knop los om het bericht te verzenden.

Als op je apparaat spraakherkenning is ingeschakeld (zie instellingen),
wordt je spraakbericht automatisch als tekst getranscribeerd. De ander
ziet dan zowel de opname als de getranscribeerde tekst.

### Berichten beantwoorden (citeren)

Om op een specifiek bericht te reageren:

1. Open het menu met de drie puntjes naast het bericht.
2. Kies "Beantwoorden".
3. Boven het invoerveld verschijnt een balk met het geciteerde bericht.
4. Schrijf je antwoord en verstuur het.

Het geciteerde bericht wordt in je antwoord getoond, zodat het verband
duidelijk is.

### Berichten bewerken en verwijderen

- **Bewerken:** Menu met drie puntjes bij het bericht, dan "Bewerken".
  Wijzig de tekst en verstuur opnieuw. De ander ziet dat het bericht is
  bewerkt. Bewerken is mogelijk binnen 15 minuten na het verzenden.
- **Verwijderen:** Menu met drie puntjes bij het bericht, dan
  "Verwijderen". Het bericht wordt bij jou en bij de ander verwijderd.
  Je kunt je eigen berichten altijd verwijderen -- er is geen
  tijdslimiet voor het verwijderen.

### Emoji-reacties

In plaats van een antwoord te schrijven, kun je op een bericht reageren
met een emoji:

1. Open het menu met de drie puntjes of houd het bericht lang ingedrukt.
2. Kies een emoji uit de snelkeuze of open de emoji-kiezer voor de
   volledige selectie.
3. Je reactie verschijnt onder het bericht.

### Tekst kopiëren

Via het menu met de drie puntjes van een bericht kun je de berichttekst
naar het klembord kopiëren.

### Berichten zoeken

Bovenaan het chatvenster vind je de zoekfunctie. Voer een zoekterm in en
Cleona toont je alle treffers in de huidige chat. Met de pijltoetsen kun
je tussen de treffers heen en weer springen.

Op het startscherm is er daarnaast een tabbladoverstijgend zoekfilter,
waarmee je alle gesprekken op een term kunt doorzoeken.

### Linkvoorbeeld

Als je een link verstuurt, genereert Cleona automatisch een voorbeeld
(titel, beschrijving, voorbeeldafbeelding). Dit voorbeeld wordt door je
eigen apparaat aangemaakt en meegestuurd -- de ander hoeft daarvoor geen
verbinding met de gelinkte website op te bouwen.

Als je op een ontvangen link tikt, wordt je gevraagd of je deze in de
normale browser, in incognitomodus of helemaal niet wilt openen.

---

## 5. Groepen

### Groep aanmaken

1. Ga naar het tabblad "Groepen".
2. Tik op de plusknop.
3. Geef de groep een naam.
4. Kies de contacten die je wilt uitnodigen.
5. Tik op "Aanmaken".

De uitgenodigde contacten ontvangen een melding en kunnen zich bij de
groep aansluiten.

### Leden uitnodigen

Ook na het aanmaken kun je nog meer contacten uitnodigen:

1. Open de groepsinfo (menu met drie puntjes in het groepsoverzicht of
   de bovenste balk in de groepschat).
2. Tik op "Uitnodigen".
3. Kies de contacten die je wilt toevoegen.

### Rollen

Elke groep heeft drie rollen:

- **Eigenaar (Owner):** Heeft volledige controle. Kan leden toevoegen en
  verwijderen, admins benoemen en de groep beheren. De eigenaar kan zijn
  status ook overdragen aan een ander lid.
- **Admin:** Kan leden verwijderen en helpen bij het beheer.
- **Lid:** Kan berichten lezen en schrijven.

### Groep verlaten

1. Open het menu met de drie puntjes in het groepsoverzicht.
2. Kies "Verlaten".
3. Bevestig je keuze.

Als je een groep verlaat, blijven je eerdere berichten zichtbaar voor de
andere leden.

---

## 6. Openbare kanalen

### Wat zijn kanalen?

Kanalen zijn openbare discussieforums binnen het Cleona-netwerk. In
tegenstelling tot groepen kan hier iedereen meelezen, zonder uitgenodigd
te hoeven worden. Alleen de eigenaar en admins kunnen berichten
publiceren -- abonnees lezen mee.

### Kanalen vinden en volgen

1. Ga naar het tabblad "Kanalen".
2. Open het tabblad "Zoeken".
3. Doorzoek de beschikbare kanalen op naam of onderwerp.
4. Tik op een kanaal en dan op "Abonneren".

Kanalen kunnen op taal worden gefilterd. Sommige kanalen zijn
gemarkeerd als "Niet geschikt voor minderjarigen" -- deze zijn alleen
zichtbaar als je in je profiel hebt bevestigd dat je ouder dan 18 bent.

### Eigen kanaal aanmaken

1. Ga naar het tabblad "Kanalen".
2. Tik op de plusknop.
3. Voer een kanaalnaam in (moet uniek zijn binnen het hele netwerk).
4. Kies de taal en of het kanaal openbaar of privé moet zijn.
5. Optioneel: voeg een beschrijving en een afbeelding toe.
6. Tik op "Aanmaken".

Bij openbare kanalen kun je aangeven of de inhoud als "Niet geschikt
voor minderjarigen" wordt ingedeeld.

### Inhoud melden

Als je in een openbaar kanaal ongepaste inhoud tegenkomt, kun je deze
melden. Cleona gebruikt een gedecentraliseerd moderatiesysteem: meldingen
worden beoordeeld door willekeurig gekozen leden van het netwerk (een
soort "jury"). Wordt een overtreding vastgesteld, dan krijgt het kanaal
een waarschuwing. Bij herhaalde overtredingen wordt het kanaal
gedegradeerd in de zoekindex of geblokkeerd.

### Systeemkanalen

Cleona beschikt over twee ingebouwde systeemkanalen:

- **Bug Log:** Wanneer Cleona een fout detecteert, vraagt het je of je
  een geanonimiseerd foutrapport wilt versturen. Deze rapporten komen
  terecht in het Bug Log-kanaal, waar ze door de community kunnen worden
  ingezien. Er worden geen persoonlijke gegevens verzonden -- alleen
  technische foutbeschrijvingen. Je kunt ook handmatig een lograpport
  versturen (met voorbeeldvenster en expliciete toestemming).
- **Feature Requests:** Hier kunnen gebruikers functiewensen indienen en
  stemmen op bestaande voorstellen. De voorstellen worden gesorteerd op
  aantal stemmen.

Beide systeemkanalen hebben een grootte limiet van 25 MB en worden
bewaakt door het jury-moderatiesysteem.

---

## 7. Oproepen

### Spraakoproep starten

1. Open de chat met het contact dat je wilt bellen.
2. Tik op het telefoonicoon in de bovenste balk.
3. Wacht tot de ander de oproep aanneemt.

Tijdens het gesprek zie je een tijdlijn met de gespreksduur en heb je
toegang tot dempen en luidspreker.

Om op te hangen, tik je op de rode ophangknop.

### Video-oproep starten

1. Open de chat met het contact.
2. Tik op het camera-icoon in de bovenste balk.
3. Je eigen videobeeld verschijnt in een klein venster, het beeld van de
   ander in het grote gedeelte.

Je kunt tijdens het gesprek wisselen tussen voor- en achtercamera.

### Binnenkomende oproepen

Als iemand je belt, verschijnt een meldingsvenster met de naam van de
beller. Je kunt:

- **Aannemen** -- het gesprek begint.
- **Weigeren** -- de beller wordt hiervan op de hoogte gebracht.

Als je al in een gesprek zit, wordt een nieuwe oproep automatisch
geweigerd.

### Groepsoproepen

Je kunt ook groepsoproepen voeren, waaraan meerdere personen tegelijk
deelnemen. De oproep wordt georganiseerd via een intelligente
doorstuurboom, zodat niet elke deelnemer rechtstreeks met elke andere
deelnemer verbonden hoeft te zijn. Alle gesprekken zijn end-to-end
versleuteld.

### Versleuteling bij oproepen

Alle oproepen worden versleuteld met eenmalige sleutels die alleen
bestaan voor de duur van het gesprek. Na het ophangen worden deze
sleutels direct gewist. Niemand kan een eerder gesprek achteraf
ontsleutelen.

---

## 8. Agenda

Cleona bevat een ingebouwde agenda die versleuteld en volledig
gedecentraliseerd werkt -- zonder clouddienst.

### Weergaven

De agenda biedt vijf weergaven: dag, week, maand, jaar en een
takenweergave. Wissel ertussen via de tabbladen bovenaan het
agendascherm.

### Afspraken aanmaken

Tik op een tijdslot of gebruik de knop Toevoegen om een nieuwe afspraak
aan te maken. Je kunt titel, datum, tijd, locatie en notities invoeren.
Afspraken worden versleuteld op je apparaat opgeslagen.

### Terugkerende afspraken

Afspraken kunnen dagelijks, wekelijks, maandelijks of jaarlijks
terugkeren. Je kunt het patroon aanpassen (bijv. elke tweede dinsdag,
elke eerste van de maand) en een einddatum of aantal herhalingen
instellen.

### Contacten uitnodigen

Bij het aanmaken of bewerken van een afspraak kun je je Cleona-contacten
uitnodigen. Zij ontvangen een versleutelde agenda-uitnodiging en kunnen
antwoorden met toezeggen, afzeggen of misschien. Wijzigingen aan de
afspraak worden automatisch naar alle genodigden verstuurd.

### Vrij/bezet-weergave

Je kunt je beschikbaarheid delen met contacten zonder afspraakdetails
prijs te geven. Er zijn drie privacyniveaus: volledige details, alleen
tijdsblokken of verborgen. Je kunt een standaard instellen en deze per
contact overschrijven.

### Herinneringen

Afspraken kunnen herinneringen hebben die vóór aanvang van de afspraak
een systeemmelding activeren. Je kunt herinneringen indien nodig
uitstellen (snoozen).

### Externe agendasynchronisatie

Cleona kan synchroniseren met externe agendadiensten:

- **CalDAV** -- Verbind met elke CalDAV-compatibele server (Nextcloud,
  Radicale enz.).
- **Google Agenda** -- Synchronisatie via de Google Calendar API met
  veilige OAuth2-authenticatie.
- **Lokale CalDAV-server** -- Cleona kan een lokale CalDAV-server op je
  apparaat starten, zodat desktop-agenda-apps (Thunderbird, Outlook,
  Apple Agenda, Evolution) kunnen synchroniseren met je Cleona-agenda.
- **Android-systeemagenda** -- Afspraken uit Cleona kunnen worden
  overgezet naar de ingebouwde agenda-app van je Android-apparaat.
- **ICS-bestanden** -- Importeer en exporteer afspraken in het
  standaard iCalendar-formaat.

### PDF-export

Je kunt elke agendaweergave (dag, week, maand, jaar) als PDF-document
afdrukken of exporteren.

---

## 9. Peilingen

Je kunt in elke chat of groep peilingen aanmaken om meningen te peilen
of afspraken te plannen.

### Type peilingen

Cleona ondersteunt vijf soorten peilingen:

- **Enkele keuze** -- Deelnemers kiezen één optie.
- **Meerkeuze** -- Deelnemers kunnen meerdere opties kiezen.
- **Datumpeiling** -- Vind een datum die voor iedereen past. Elke
  deelnemer markeert data als beschikbaar, misschien of niet
  beschikbaar.
- **Schaal** -- Beoordeel iets op een numerieke schaal (bijv. 1 tot 5).
- **Vrije tekst** -- Deelnemers schrijven hun eigen antwoord.

### Peiling aanmaken

Open een chat en tik op het peiling-icoon (of gebruik het
bijlagenmenu). Kies het type peiling, formuleer je vraag en de opties,
en verstuur de peiling. Deze verschijnt als bericht in de chat.

### Stemmen

Tik op een peiling om je stem uit te brengen. Je kunt je stem op elk
moment wijzigen of intrekken.

### Anoniem stemmen

Peilingen kunnen worden geconfigureerd voor anoniem stemmen. Indien
ingeschakeld, zijn stemmen cryptografisch anoniem -- niemand, zelfs niet
de maker van de peiling, kan zien wie waarop heeft gestemd. Het aantal
stemmen blijft wel zichtbaar.

### Datumpeiling naar agenda

Zodra een datumpeiling is afgerond, kan de winnende datum met één tik
direct worden omgezet in een agenda-item.

---

## 10. Meerdere identiteiten

### Waarom meerdere identiteiten?

Stel je voor dat je je werkleven en je privéleven wilt scheiden --
vergelijkbaar met twee verschillende telefoonnummers, maar zonder een
tweede telefoon. In Cleona kun je meerdere identiteiten op één apparaat
gebruiken. Elke identiteit heeft een eigen naam, een eigen profielfoto,
eigen contacten en eigen gesprekken.

### Nieuwe identiteit aanmaken

1. In de bovenste balk zie je je huidige identiteit als tabblad.
2. Tik op het plusteken (+) rechts naast je identiteitstabbladen.
3. Voer een naam in voor de nieuwe identiteit.
4. Klaar -- de nieuwe identiteit is direct actief.

### Wisselen tussen identiteiten

Tik gewoon op het identiteitstabblad in de bovenste balk. Het wisselen
gebeurt direct -- geen wachttijd, geen herladen.

### Alles draait tegelijk

Een belangrijk punt: al je identiteiten zijn tegelijk actief. Ook als je
op dit moment als "Werk" wordt weergegeven, ontvangt je identiteit
"Privé" nog steeds berichten. Je mist niets, ongeacht welke identiteit
je op dat moment hebt geselecteerd.

### Identiteitsdetailpagina

Als je op het tabblad van je actieve identiteit tikt, opent de
detailpagina. Hier kun je:

- Je QR-code voor contacten weergeven.
- Je profielfoto wijzigen of verwijderen.
- Een profielbeschrijving toevoegen.
- Je weergavenaam wijzigen.
- Een ontwerp (skin) voor deze identiteit kiezen.
- De identiteit verwijderen, als je deze niet meer nodig hebt.

### Identiteit verwijderen

Als je een identiteit verwijdert, worden je contacten hierover op de
hoogte gebracht. De identiteit en alle bijbehorende gegevens worden van
je apparaat verwijderd. Deze handeling kan niet ongedaan worden gemaakt.

---

## 11. Multi-Device

### Cleona op meerdere apparaten gebruiken

Je kunt dezelfde identiteit op maximaal 5 apparaten tegelijk gebruiken.
Eén apparaat is het primaire apparaat (het bevat de seed-phrase), en
andere apparaten worden hiermee gekoppeld.

### Nieuw apparaat koppelen

1. Open de instellingen op je primaire apparaat.
2. Ga naar "Gekoppelde apparaten".
3. Kies "Nieuw apparaat koppelen".
4. Installeer Cleona op het nieuwe apparaat en kies bij het opstarten
   "Koppelen met bestaand apparaat".
5. Scan de koppel-QR-code die op je primaire apparaat wordt weergegeven,
   of gebruik de koppellink.

Het gekoppelde apparaat ontvangt een delegatiecertificaat van het
primaire apparaat. Berichten die vanaf een gekoppeld apparaat worden
verzonden, zijn cryptografisch ondertekend met een gedelegeerde
sleutel, zodat contacten kunnen controleren dat het bericht daadwerkelijk
van jouw identiteit afkomstig is.

### Hoe het werkt

- Het primaire apparaat bevat je seed-phrase en de mastersleutels.
- Gekoppelde apparaten ontvangen afgeleide ondertekeningssleutels en een
  delegatiecertificaat -- ze ontvangen nooit de seed-phrase zelf.
- Alle apparaten delen dezelfde identiteit en contacten. Berichten komen
  binnen op alle apparaten.
- Delegatiecertificaten worden automatisch vernieuwd voordat ze
  verlopen.

### Apparaatbeheer

Open de instellingen en ga naar "Gekoppelde apparaten" om al je
gekoppelde apparaten, hun status en laatste activiteit te zien. Je kunt
een gekoppeld apparaat op elk moment intrekken, mocht het verloren gaan
of gestolen worden.

### Noodsleutelrotatie

Als je vermoedt dat een apparaat is gecompromitteerd, kun je een
noodsleutelrotatie starten. Daarbij worden nieuwe sleutels gegenereerd,
en de rotatie moet worden bevestigd door een meerderheid van je andere
apparaten. Dit voorkomt dat een enkel gestolen apparaat op eigen houtje
sleutels kan roteren.

---

## 12. Herstel

### Seed-phrase gebruiken

Als je je apparaat kwijtraakt of een nieuw apparaat instelt:

1. Installeer Cleona op het nieuwe apparaat.
2. Kies bij het opstarten "Herstellen".
3. Voer je 24 woorden in.
4. Cleona herstelt je identiteit en neemt automatisch contact op met je
   eerdere contacten.
5. Je contacten antwoorden met je contactgegevens, groepslidmaatschappen
   en berichtgeschiedenis.

Het herstel verloopt in drie stappen:
- Eerst komen je contacten en groepen terug.
- Dan de laatste 50 berichten uit elk gesprek.
- Ten slotte de volledige berichtgeschiedenis.

Het is voldoende als één van je contacten online is om het herstel te
laten slagen.

### Guardian Recovery (vertrouwenspersonen)

Je kunt tot vijf vertrouwenspersonen aanwijzen als "Guardians". Hierbij
wordt je herstelsleutel in vijf delen opgesplitst, waarvan elke Guardian
er één ontvangt. Om je identiteit te herstellen, volstaan drie van de
vijf delen.

Dat betekent: zelfs als je je seed-phrase bent kwijtgeraakt, kunnen drie
van je Guardians samen je account herstellen. Geen enkele Guardian kan
alleen toegang krijgen tot je gegevens -- er zijn altijd minstens drie
nodig.

Zo stel je Guardians in:
1. Open de instellingen.
2. Ga naar "Veiligheid".
3. Kies "Guardian Recovery".
4. Kies vijf vertrouwde contacten.

### Waarom contacten je back-up zijn

Bij traditionele messengers staan je gegevens op de servers van de
aanbieder. Bij Cleona is er geen server -- maar je contacten nemen deze
rol over. Als je een bericht verstuurt, bewaren gemeenschappelijke
contacten een versleutelde kopie voor het geval de ontvanger op dat
moment offline is. Bij een herstel leveren je contacten je gegevens weer
aan je terug.

Dat betekent: hoe meer actieve contacten je hebt, hoe betrouwbaarder je
back-up is. Eén contact dat regelmatig online is, is voldoende voor een
succesvol herstel.

---

## 13. Instellingen

De instellingen bereik je via het tandwielicoon rechtsboven in de hoek.

### Meldingen en beltonen

- Kies uit zes verschillende beltonen voor binnenkomende oproepen.
- Stel een berichttoon in.
- Op Android-apparaten kun je daarnaast trillen in- of uitschakelen.

### Ontwerpen (skins)

Cleona biedt tien verschillende ontwerpen: Teal, Ocean, Sunset, Forest,
Amethyst, Fire, Storm, Slate, Gold en Contrast. Het Contrast-ontwerp
voldoet aan het hoogste toegankelijkheidsniveau (WCAG AAA) en is
bijzonder goed leesbaar bij een beperkt gezichtsvermogen.

Elke identiteit kan zijn eigen ontwerp hebben. Je wijzigt het ontwerp op
de identiteitsdetailpagina (tik op het actieve identiteitstabblad).

Daarnaast kun je in de instellingen onder "Weergave" wisselen tussen
licht, donker en het systeemthema.

### Taal wijzigen

Cleona is beschikbaar in 33 talen, waaronder ook talen met
rechts-naar-links-schrift (bijv. Arabisch, Hebreeuws). Wijzig de taal in
de instellingen onder "Taal".

### Opslaglimiet

Je kunt instellen hoeveel opslagruimte Cleona op je apparaat mag
gebruiken (tussen 100 MB en 2 GB). Als de limiet is bereikt, worden
oudere media automatisch uitgeplaatst of verwijderd -- tekstberichten
blijven altijd bewaard.

### Media-archivering

Als je thuis een netwerkopslag (NAS) of een gedeelde map hebt, kan
Cleona je media daar automatisch naartoe uitplaatsen. Ondersteund worden
SMB, SFTP, FTPS en WebDAV.

Zo werkt de gefaseerde opslag:
- De eerste 30 dagen: alles blijft op je apparaat.
- Na 30 dagen: een voorbeeldafbeelding blijft op het apparaat, het
  origineel wordt gearchiveerd.
- Na 90 dagen: alleen een klein voorbeeldafbeeldinkje blijft op het
  apparaat.
- Na een jaar: alleen nog een plaatshouder blijft over, het origineel
  bevindt zich veilig in het archief.

Je kunt op elk moment op een gearchiveerd medium tikken om het terug te
halen -- mits je verbonden bent met je thuisnetwerk. Bijzonder
belangrijke media kun je vastpinnen, zodat ze nooit worden uitgeplaatst.

### Transcriptie voor spraakberichten

Indien ingeschakeld, worden je spraakberichten lokaal op je apparaat
omgezet in tekst (met het opensource-model Whisper). De getranscribeerde
tekst wordt samen met de opname naar de ander verstuurd. De transcriptie
gebeurt volledig op je apparaat -- er gaan geen gegevens naar externe
diensten.

### Automatisch downloaden

Je kunt instellen vanaf welke grootte media automatisch moet worden
gedownload. Zo kun je bijvoorbeeld afbeeldingen automatisch laten laden,
maar bij grote video's handmatig beslissen.

### Gekoppelde apparaten

Beheer je gekoppelde apparaten in dit gedeelte van de instellingen. Zie
het hoofdstuk Multi-Device voor details.

---

## 14. Veiligheid

### Wat betekent post-quantumversleuteling?

Hedendaagse versleuteling is gebaseerd op wiskundige problemen die voor
gewone computers extreem moeilijk op te lossen zijn. Quantumcomputers
zouden sommige van deze problemen in de toekomst snel kunnen oplossen.
Post-quantumversleuteling gebruikt aanvullende methoden die ook bestand
zijn tegen quantumcomputers.

Cleona combineert beide benaderingen: klassieke versleuteling voor
betrouwbaarheid en post-quantummethoden voor toekomstbestendigheid. Zo
ben je tegelijk beschermd tegen huidige en toekomstige bedreigingen.

Voor elk afzonderlijk bericht wordt een eigen sleutel gegenereerd. Zelfs
als een aanvaller de sleutel van één bericht zou kraken, zou hij daarmee
geen ander bericht kunnen lezen.

### Waarom geen server veiliger is

Bij traditionele messengers lopen je berichten via de servers van de
aanbieder. Ook al zijn ze daar mogelijk versleuteld: de aanbieder heeft
toegang tot metadata (wie communiceert wanneer met wie, hoe vaak, van
waar) en moet deze onder omstandigheden op gerechtelijk bevel afgeven.

Bij Cleona is er geen zo'n centraal punt. Je berichten reizen
rechtstreeks van apparaat naar apparaat. Er is geen plek waar alle
metadata samenkomen. Niemand kan op basis van één enkel datapunt je
communicatiegedrag reconstrueren.

### Wat gebeurt er als je offline bent?

Als je een bericht verstuurt en de ontvanger is offline:

1. Cleona probeert eerst het bericht rechtstreeks af te leveren.
2. Als dat niet lukt, wordt het doorgestuurd via gemeenschappelijke
   contacten.
3. Tegelijkertijd wordt het bericht als versleutelde stukken over
   meerdere knooppunten in het netwerk verspreid (vergelijkbaar met een
   puzzel van 10 stukjes, waarvan er 7 volstaan om het beeld samen te
   stellen).
4. Het bericht wordt tot 7 dagen bewaard.

Zodra de ontvanger weer online komt, worden de berichten afgeleverd. Je
krijgt een bevestiging zodra je bericht is aangekomen.

### Anticensuur

Als je netwerk de standaardverbindingsmethode (UDP) blokkeert, schakelt
Cleona automatisch over op een alternatieve overdracht (TLS), die
moeilijker te herkennen en te blokkeren is. Dit gebeurt transparant -- je
hoeft niets te configureren.

### Veilige sleutelopslag

Op ondersteunde platforms slaat Cleona je versleutelingssleutels op in
de veilige sleutelring van het besturingssysteem (Android Keystore, iOS
Keychain, macOS Keychain). Waar beschikbaar biedt dit hardwaregeborgde
bescherming voor je sleutels.

### Databaseversleuteling

Al je berichten, contacten en instellingen worden versleuteld op je
apparaat opgeslagen. Zelfs als iemand toegang zou krijgen tot je
bestandssysteem, zou hij zonder je cryptografische sleutel niets kunnen
lezen. Deze sleutel wordt afgeleid van je identiteit en bestaat alleen
op je apparaat.

### Gesloten netwerk

Cleona werkt als een gesloten netwerk. Elk netwerkpakket is
geauthenticeerd, zodat alleen legitieme Cleona-apparaten kunnen
deelnemen. Dit voorkomt dat buitenstaanders vervalste berichten
injecteren of het netwerkverkeer afluisteren.

---

## 15. Software-updates

### Hoe krijg ik updates?

Cleona kan op verschillende manieren worden bijgewerkt. Het doel is dat
je ook dan updates kunt ontvangen als afzonderlijke distributiekanalen
uitvallen of geblokkeerd worden:

1. **App Store / Play Store:** Als je Cleona via een app store hebt
   geïnstalleerd, ontvang je updates zoals gebruikelijk via de store.
2. **GitHub Releases:** Op de GitHub-pagina van het project vind je
   ondertekende installatiepakketten voor alle platforms.
3. **In-network-updates:** Als een andere Cleona-gebruiker in je netwerk
   al de nieuwste versie heeft, kan Cleona de update rechtstreeks via het
   P2P-netwerk ophalen -- zonder externe server. Daarbij wordt de nieuwe
   versie opgesplitst in foutgecorrigeerde fragmenten en over meerdere
   knooppunten verspreid. Je apparaat verzamelt genoeg fragmenten en
   stelt de update samen. De echtheid wordt gecontroleerd via een
   Ed25519-handtekening van de ontwikkelaar.
4. **Uitnodigingslinks:** Je kunt uitnodigingslinks maken die alles
   bevatten wat een nieuwe gebruiker nodig heeft om Cleona te
   installeren en verbinding te maken met het netwerk.
5. **Fysieke overdracht:** In omgevingen zonder internet kun je Cleona
   via een USB-stick of over het lokale netwerk aan anderen doorgeven.

### Updatemelding

Als er een nieuwe update beschikbaar is, toont Cleona een melding op
het startscherm. Als de update ook via het netwerk beschikbaar is
(in-network-update), heb je de keuze om deze rechtstreeks vanuit het
netwerk te downloaden.

### Binaire distributie

Standaard helpt je apparaat mee om updates aan andere gebruikers in het
netwerk door te geven. Als je dat niet wilt, kun je deze functie in de
instellingen onder "Netwerk" uitschakelen. Het opslaggebruik voor
update-fragmenten is beperkt (5 MB op mobiele apparaten, 20 MB op
desktopapparaten) en wordt regelmatig opgeschoond.

### Handtekeningcontrole

Elke update wordt cryptografisch ondertekend. Cleona controleert de
handtekening automatisch voordat een update wordt geïnstalleerd. Zo is
gegarandeerd dat alleen updates van de officiële ontwikkelaar worden
geaccepteerd -- zelfs als de update via het P2P-netwerk is verkregen.

---

## 16. Veelgestelde vragen

### "Kan ik Cleona zonder internet gebruiken?"

Nee, Cleona heeft een netwerkverbinding nodig om berichten te versturen
en te ontvangen. Je hoeft echter niet tegelijk met de ander online te
zijn: berichten die worden verstuurd terwijl de ontvanger offline is,
worden tijdelijk opgeslagen en automatisch afgeleverd zodra beide
kanten weer verbonden zijn. Binnen een lokaal netwerk (bijv. hetzelfde
wifinetwerk) kunnen jullie ook zonder internettoegang met elkaar
communiceren.

### "Wat als ik mijn seed-phrase kwijtraak?"

Als je Guardians hebt ingesteld, kunnen drie van de vijf
vertrouwenspersonen samen je toegang herstellen. Zonder Guardians en
zonder seed-phrase is er helaas geen manier om je identiteit terug te
krijgen. Daarom is het zo belangrijk om de 24 woorden veilig te bewaren.

### "Kan iemand mijn berichten meelezen?"

Nee. Elk bericht wordt versleuteld met een eenmalige sleutel die alleen
voor dat ene bericht geldt. Alleen jij en de ander kunnen het bericht
ontsleutelen. Er is geen centrale server, geen hoofdsleutel en geen
toegang voor de ontwikkelaar. Zelfs als een apparaat onderweg het
bericht doorgeeft, ziet het alleen versleutelde brij aan gegevens.

### "Waarom heb ik geen telefoonnummer nodig?"

Omdat je identiteit puur cryptografisch is. In plaats van een
telefoonnummer of e-mailadres dat gekoppeld is aan je echte naam,
identificeert een sleutelpaar je, dat op je apparaat is gegenereerd.
Contacten voeg je toe via QR-code, NFC of link -- niet via een
telefoonboek. Dat betekent meer privacy, omdat je messenger-account niet
gekoppeld is aan je werkelijke identiteit.

### "Hoe vind ik mensen op Cleona?"

Cleona heeft bewust geen contactzoekfunctie op telefoonnummer of naam --
dat zou een privacyprobleem zijn. In plaats daarvan wissel je
contactgegevens rechtstreeks uit: via QR-code, NFC, cleona://-link of in
openbare kanalen. Het is als het uitwisselen van visitekaartjes in
plaats van opzoeken in een telefoonboek.

### "Werkt Cleona ook in het buitenland?"

Ja. Zolang je een internetverbinding hebt, werkt Cleona overal ter
wereld. Omdat er geen centrale server is, kan de dienst ook niet worden
geblokkeerd voor bepaalde landen. Cleona beschikt bovendien over een
anticensuur-fallback: als de normale verbinding (UDP) wordt geblokkeerd,
schakelt Cleona automatisch over op een alternatieve overdracht (TLS),
die moeilijker te herkennen en te blokkeren is.

### "Is Cleona gratis?"

Ja. Cleona is gratis en zonder reclame te gebruiken. Omdat er geen
centrale server is, zijn er ook geen serverkosten voor de werking. In de
app vind je onder "Doneren" de mogelijkheid om de ontwikkeling
vrijwillig te ondersteunen.

### "Mijn bericht heeft een klokicoon -- wat betekent dat?"

Dat betekent dat het bericht nog niet is afgeleverd. De ander is
vermoedelijk op dit moment offline. Zodra het bericht is afgeleverd,
verandert het icoon. Berichten worden tot 7 dagen bewaard voor
aflevering.

### "Kan ik overstappen van WhatsApp naar Cleona?"

Ja, maar je kunt je WhatsApp-chats niet overzetten. Cleona en WhatsApp
zijn compleet verschillende systemen. Je moet je contacten één voor één
toevoegen in Cleona. Het eenvoudigst gaat dat door je cleona://-link in
een WhatsApp-groep te plaatsen en de anderen te vragen je daar toe te
voegen.

### "Kan ik Cleona op meerdere apparaten tegelijk gebruiken?"

Ja. Je kunt tot 5 apparaten koppelen met dezelfde identiteit. Eén
apparaat is het primaire apparaat (het bevat de seed-phrase), en andere
apparaten worden gekoppeld via een veilig koppelproces. Alle apparaten
delen dezelfde identiteit, contacten en gesprekken. Zie het hoofdstuk
Multi-Device voor details.

### "Hoe krijg ik updates als de app store geblokkeerd is?"

Cleona kan updates rechtstreeks via het P2P-netwerk ophalen, zonder
afhankelijk te zijn van een app store, een website of een
downloadserver. Als een andere gebruiker in het netwerk de nieuwste
versie heeft, kan je apparaat de update daarvandaan laden. De echtheid
wordt gecontroleerd via een digitale handtekening van de ontwikkelaar.
Als alternatief kan een contact je de app doorgeven via een
uitnodigingslink of USB-stick. Meer hierover in het hoofdstuk
"Software-updates".

---

## Hulp en contact

Als je vragen hebt of tegen een probleem aanloopt, vind je actuele
informatie op de Cleona-website en op GitHub. Omdat Cleona een
gedecentraliseerd project is, bestaat er geen klassieke klantenservice --
maar wel een actieve gemeenschap die graag helpt.

---

*Deze handleiding beschrijft Cleona Chat versie 3.1.125. Afzonderlijke
functies kunnen in nieuwere versies wijzigen of worden uitgebreid.*

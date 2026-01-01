# Cleona Chat -- Gebruikershandleiding

Versie 4.2 | Stand november 2026

---

## Inhoudsopgave

1. [Wat is Cleona Chat?](#1-wat-is-cleona-chat)
2. [Eerste stappen](#2-eerste-stappen)
3. [Contacten](#3-contacten)
4. [Berichten](#4-berichten)
5. [Groepen](#5-groepen)
6. [Openbare kanalen](#6-openbare-kanalen)
7. [Oproepen](#7-oproepen)
8. [Agenda](#8-agenda)
9. [Peilingen](#9-peilingen)
10. [Meerdere identiteiten](#10-meerdere-identiteiten)
11. [Meerdere apparaten](#11-meerdere-apparaten)
12. [Herstel](#12-herstel)
13. [Instellingen](#13-instellingen)
14. [Beveiliging](#14-beveiliging)
15. [Software-updates](#15-software-updates)
16. [Veelgestelde vragen](#16-veelgestelde-vragen)

---

## 1. Wat is Cleona Chat?

### Jouw messenger, jouw gegevens

Cleona Chat is een messenger die volledig zonder centrale server werkt.
Jouw berichten reizen van jouw apparaat naar het apparaat van je tegenpartij --
zonder omweg via een bedrijfsvestiging, zonder cloud, zonder datacenter. Waar
onderweg een ander apparaat helpt, stuurt het alleen versleutelde pakketten
door. Geen bedrijf kan jouw berichten lezen, opslaan of doorgeven, omdat
simpelweg geen bedrijf ertussen staat.

### Geen account, geen telefoonnummer

Bij Cleona heb je geen telefoonnummer en geen e-mailadres nodig om je aan te
melden. Jouw identiteit bestaat uit een cryptografisch sleutelpaar, dat bij de
eerste start automatisch op jouw apparaat wordt aangemaakt. Dat betekent:
niemand kan je via je telefoonnummer of e-mailadres opsporen, tenzij je zelf
je contactgegevens doorgeeft.

### Toekomstbestendige versleuteling

Cleona gebruikt zogenoemde post-kwantum-versleuteling. Dat betekent: zelfs
toekomstige kwantumcomputers zouden jouw berichten niet kunnen kraken. Je hoeft
de details niet te begrijpen -- belangrijk is alleen dat jouw communicatie
naar de huidige stand van de techniek zo goed mogelijk beschermd is.

### Hoe werkt dat zonder server?

Het netwerk van Cleona bestaat alleen uit de apparaten van zijn gebruikers. Elk
apparaat is een knooppunt, geen knooppunt is belangrijker dan een ander, en elk
kent alleen zijn buren. Vier dingen maken dit netwerk bijzonder:

- **Geen vast punt.** In de app staat geen serveradres, en het netwerk
  hangt niet af van één enkel knooppunt. Er is niets wat men zou kunnen
  uitschakelen om Cleona uit te schakelen.
- **Meteen.** Jouw bericht gaat op weg op het moment dat je het
  verstuurt. Het wacht op geen klok en op niets anders.
- **Dekking op de achtergrond.** Jouw apparaat stuurt voortdurend kleine
  dekmantelpakketten, zodat van buiten niet te zien is wanneer je echt
  schrijft. Geen bericht hangt ervan af -- de dekking draait alleen
  ernaast.
- **Codes in plaats van namen.** Wie een bericht doorstuurt, ziet alleen een
  code die elke dag verandert. Normaal gesproken kent geen van hen
  afzender en ontvanger tegelijk; de uitzonderingen staan in hoofdstuk 14.

**Drie routes, allemaal tegelijk.** Als je een bericht verstuurt, probeert
Cleona niet de ene route na de andere, maar alle geschikte tegelijk. Zodra je
tegenpartij de ontvangst bevestigt, worden de andere afgebroken.

1. **In hetzelfde netwerk:** Zit je in hetzelfde Wi-Fi, dan gaat het bericht
   rechtstreeks over.
2. **Over de vaste buren:** Op het internet geeft jouw apparaat het
   bericht aan zijn vaste buur. Die stuurt het door naar de vaste buren
   van je tegenpartij (tot drie tegelijk), en een van hen levert het af.
3. **Postbus:** Is je tegenpartij offline, dan deponeert Cleona het bericht
   versleuteld bij drie buren. Daar blijft het tot 7 dagen. Komt je
   tegenpartij weer online, dan haalt hij het op.

**Hoe kom je in het netwerk?** In de app staat geen serveradres. Jouw
instappunt krijg je van je eerste contact: zijn uitnodiging bevat de
adressen waarmee jouw apparaat zijn eerste buren vindt. In hetzelfde Wi-Fi
vinden Cleona-apparaten elkaar ook zelf. Vanaf dan leert jouw apparaat met
elke buur meer kennen.

### Platformen

Cleona is beschikbaar voor Android, iOS, macOS, Linux en Windows. Op computers
en op Android komen berichten en gesprekken binnen enkele seconden aan. Op de
iPhone geldt dat zolang de app openstaat. Staat de app niet open, dan wekt iOS
hem alleen zo nu en dan kort op; wanneer, bepaalt iOS. Cleona haalt dan alles
op wat voor je bewaard is en toont een melding met een getal op het
app-pictogram. Gesprekken komen niet aan op een iPhone waarvan de app niet
openstaat. Dat is een regel van Apple, geen fout in Cleona.

---

## 2. Eerste stappen

### App installeren

**Android:**
1. Download het APK-bestand van de Cleona-website of van GitHub Releases.
2. Open het bestand op je telefoon. Indien nodig, sta installatie uit
   onbekende bronnen toe (Android vraagt je automatisch).
3. Tik op "Installeren" en wacht tot de installatie voltooid is.

**iOS:**
1. Open de TestFlight-uitnodigingslink op je iPhone.
2. Tik op "Installeren". TestFlight is de officiële manier van Apple om
   beta-apps te verspreiden.
3. Na de installatie vind je Cleona op je beginscherm.

**macOS:**
1. Download het DMG-bestand van de Cleona-website of van GitHub Releases.
2. Open het DMG en sleep Cleona naar je map Programma's.
3. Bij de eerste start vraagt macOS mogelijk of je een app van een
   geïdentificeerde ontwikkeler wilt openen -- bevestig dit.

**Linux (Ubuntu/Debian):**
1. Download het .deb-bestand van de Cleona-website of van GitHub Releases.
2. Installeer met dubbelklik of in de terminal: `sudo dpkg -i cleona-chat-beta_VERSION_amd64.deb`
3. Start Cleona via het toepassingsmenu of in de terminal met `cleona-chat-beta`.

**Linux (Fedora/openSUSE):**
1. Download het .rpm-bestand van de Cleona-website of van GitHub Releases.
2. Installeer met: `sudo dnf install cleona-chat-beta-VERSION-1.x86_64.rpm`
3. Start Cleona via het toepassingsmenu of in de terminal met `cleona-chat-beta`.

**Linux (alle distributies -- AppImage):**
1. Download het .AppImage-bestand van de Cleona-website of van GitHub Releases.
2. Maak het bestand uitvoerbaar: rechtsklik, eigenschappen, uitvoerbaar, of in de terminal: `chmod +x cleona-chat-beta-VERSION-x86_64.AppImage`
3. Start met dubbelklik of in de terminal: `./cleona-chat-beta-VERSION-x86_64.AppImage`

De pakketnamen gelden voor de bèta, die op dit moment de enige gepubliceerde
versie is; ze heten `cleona-chat-beta`.

**Windows:**
1. Download het installatieprogramma van de Cleona-website of van GitHub Releases.
2. Voer het installatiebestand uit en volg de aanwijzingen.
3. Start Cleona via het Start-menu of de bureaubladsnelkoppeling.

### Identiteit aanmaken

Bij de eerste start maakt Cleona automatisch een nieuwe identiteit voor je aan.
Je kunt jezelf een weergavenaam geven -- dat is de naam die je contacten
zien. Deze naam kan op elk moment worden gewijzigd.

### Seed-phrase opschrijven -- het allerbelangrijkste

Na het aanmaken van je identiteit toont Cleona je 24 woorden. Dat is jouw
**seed-phrase** -- jouw persoonlijke herstelsleutel.

**Schrijf deze 24 woorden op papier op en bewaar ze veilig.**

Waarom is dit zo belangrijk?

- Als je telefoon kapotgaat, verloren raakt of wordt gestolen, kun je
  met deze 24 woorden je volledige identiteit op een nieuw apparaat
  herstellen.
- Zonder de seed-phrase is er geen weg terug. Er is geen knop "wachtwoord
  vergeten" en geen support die je je account zou kunnen teruggeven --
  want er is helemaal geen account op een server. Ook je contacten
  kunnen je identiteit niet herstellen, hoeveel van hen er ook zijn. Een
  tweede apparaat met dezelfde identiteit komt met een latere versie
  (zie hoofdstuk 11).
- Geef de seed-phrase nooit aan anderen door. Wie deze woorden kent, kan
  zich als jij voordoen.

Je vindt de 24 woorden later in de instellingen onder "Back-up" ->
"Herstelzin tonen", voor het geval je ze nog eens wilt aflezen. Op
Android bevestig je dat met je schermvergrendeling.

### Eerste contact toevoegen

Om met iemand te chatten, moet je die persoon eerst als contact toevoegen.
Daarvoor zijn er meerdere wegen -- ze worden allemaal in het volgende
onderdeel uitgelegd.

---

## 3. Contacten

### Jouw uitnodiging

Contacten ontstaan bij Cleona alleen via een uitnodiging. Jouw uitnodiging is
er vanaf de eerste start -- ook zonder internet en voordat jouw apparaat
al een buur heeft gevonden. Je vindt hem op je identiteitsdetailpagina
(tik op je eigen naam in de bovenste balk).

De uitnodiging is er in twee vormen, die precies hetzelfde bevatten:

- als **QR-code**, als je tegenpartij naast je staat, en
- als **tekstregel**, die je per e-mail, sms of via een andere
  messenger verstuurt.

De uitnodiging bevat geen telefoonnummer en geen naam uit een
register. Ze bevat jouw publieke sleutels en de adressen
waarmee je tegenpartij jou en je buren bereikt. Voor iemand die Cleona
net geïnstalleerd heeft, is jouw uitnodiging daarom ook het instappunt in
het netwerk.

### QR-code scannen (aanbevolen)

Als jullie elkaar persoonlijk treffen:

1. Je toont je tegenpartij de QR-code van je uitnodiging.
2. Je tegenpartij tikt op de plusknop, kiest "QR-code scannen" en
   houdt de camera op jouw scherm. Dit werkt ook met de webcam
   van een computer.
3. Het verzoek gaat naar jou en wordt **automatisch geaccepteerd** -- want je
   hebt de code zojuist zelf getoond.

Een QR-code geldt slechts één keer: het eerste geldige verzoek wordt geaccepteerd,
daarna is de uitnodiging verbruikt. De QR-code is de veiligste methode,
want jullie weten daarbij precies met wie je het contact uitwisselt.

### NFC (telefoons tegen elkaar houden)

Als beide apparaten NFC ondersteunen:

1. Open op beide de functie contact toevoegen.
2. Houd jullie telefoons rug aan rug tegen elkaar.
3. De uitnodiging wordt overgedragen en automatisch geaccepteerd.

NFC biedt net als de QR-code een hoog veiligheidsniveau, omdat de uitwisseling
alleen werkt als jullie fysiek naast elkaar staan.

### Tekstregel versturen

Als jullie elkaar niet kunnen treffen:

1. Open je uitnodiging en kopieer de tekstregel.
2. Stuur hem naar de persoon die jou zou moeten toevoegen -- per e-mail, sms of
   via een andere messenger.
3. De andere persoon plakt de regel in Cleona in het dialoogvenster contact
   toevoegen.
4. Het verzoek verschijnt bij jou onder **"Verzoeken"**. Hier wordt **niet**
   automatisch geaccepteerd: jij beslist zelf, want je kunt niet
   weten wie de regel onderweg nog gelezen heeft.

### Contactverzoeken accepteren

Een binnenkomend verzoek maakt nog geen contact. Het stelt jou een
vraag en verschijnt in het tabblad **"Verzoeken"**. Daar zie je de naam en het
verificatieniveau en kun je kiezen:

- **Accepteren** -- pas nu wordt de persoon je contact.
- **Weigeren** -- het verzoek wordt verworpen.
- **Blokkeren** -- de persoon kan je geen verdere verzoeken sturen.

### Nooit als vaste buur gebruiken

In het menu van een contact vind je de schakelaar **"Nooit als vaste buur
gebruiken"** (standaard: uit). Staat hij aan, dan stuurt dit contact geen
berichten voor jou door en weet daarom ook niet wanneer je
berichten verstuurt of ontvangt. Dit is bedoeld voor het geval dat
gevaar uit je eigen omgeving dreigt.

Van onbekenden (noch contact noch lid van een gemeenschappelijke groep) laat
Cleona buiten zo'n verzoek niets door --
geen bericht, geen oproep, geen bestand. En zelfs het verzoek komt alleen
door als de afzender vooraf een kleine rekenopgave heeft opgelost. Dat maakt
massaspam duur.

### Verificatieniveaus

Cleona laat je zien hoe zeker de identiteit van een contact bevestigd is:

| Niveau | Betekenis |
|-------|-----------|
| Niet geverifieerd | Jullie zijn verbonden, maar niets bevestigt dat er echt de juiste persoon achter staat. |
| Gezien | De sleuteluitwisseling is gelukt; jullie kunnen versleuteld communiceren. |
| Geverifieerd | Jullie hebben elkaar persoonlijk getroffen en via camera-scan of NFC verbonden. |
| Vertrouwd | Je hebt dit contact expliciet als betrouwbaar gemarkeerd. |

"Geverifieerd" bestaat alleen voor de persoonlijke uitwisseling. Een uitnodiging
die via een chat of per e-mail kwam, bereikt dit niveau nooit -- ook als ze
dezelfde gegevens bevat.

Veranderen de sleutels van een contact zonder aankondiging, dan zet Cleona
hem terug op "Niet geverifieerd". Dat beschermt je ertegen dat
iemand ongemerkt als jouw contact voordoet.

---

## 4. Berichten

### Tekst versturen en ontvangen

Tik gewoon je bericht in het invoerveld onderaan en druk op Enter of op de
verstuurknop. Jouw bericht wordt automatisch versleuteld voordat het jouw
apparaat verlaat.

Binnenkomende berichten verschijnen in de chatgeschiedenis.

### Wat de tekens aan je bericht betekenen

| Teken | Betekenis |
|---------|-----------|
| Klok | Het bericht is aangemaakt, maar nog heeft geen route het vervoerd. |
| Één vinkje | Het bericht is onderweg. Dit geldt ook, zolang het in de postbus op je tegenpartij wacht. |
| Twee vinkjes | Bezorgd: het apparaat van je tegenpartij heeft de ontvangst bevestigd. |
| Waarschuwingsteken | 14 dagen lang heeft geen route het bericht vervoerd. Tik erop om het opnieuw te versturen. |

**Offline is geen fout.** Is je tegenpartij niet bereikbaar, dan blijft
het bericht bij één vinkje, tot het wordt opgehaald -- het is niet
verloren. Heeft jouw apparaat zelf geen verbinding, dan blijft het bericht bij
de klok en gaat het vanzelf op weg zodra er weer een route is. Het
waarschuwingsteken verschijnt pas als het 14 dagen lang geen route heeft
gevonden; dan kun je het opnieuw versturen.

Dit geldt ook voor een iPhone waarvan de app niet openstaat: het bericht wacht
in de postbus tot iOS de app kort wekt of tot je tegenpartij hem opent. Dat
kan langer duren dan op andere apparaten.

Twee vinkjes bestaan alleen als de ontvanger zelf de ontvangst bevestigt.
Deze ontvangstbevestiging is versleuteld en ondertekend -- niemand onderweg
kan haar vervalsen om jou een bezorging voor te spiegelen.

### Afbeeldingen, video's en bestanden versturen

Je hebt meerdere mogelijkheden:

- **Paperclip-pictogram** in het invoerveld: tik erop om een bestand, een afbeelding
  of een video uit je galerij of je bestandssysteem te kiezen.
- **Drag and drop** (desktop): sleep een bestand gewoon het chatvenster in.
- **Plakken vanaf het klembord** (desktop): kopieer een afbeelding en plak
  hem in de chat.

Kleine bestanden (onder 256 KB) reizen rechtstreeks mee in het bericht. Grotere
bestanden worden in stukken gesplitst en van foutcorrectie voorzien, zodat
enkele verloren stukken niet uitmaken. Zit je allebei online, dan
worden ze via een buur gestreamd; anders worden ze bij apparaten
gedeponeerd die voortdurend bereikbaar zijn, tot je tegenpartij ze ophaalt.

Vanaf 256 KB vraagt Cleona je per bestand om toestemming voordat het wordt
verstuurd: een groot bestand kan niet de route van je berichten nemen. De
inhoud blijft versleuteld, en je tegenpartij komt je internetadres niet te
weten. Maar de overdracht is van buiten als gebeurtenis zichtbaar, en een
vreemd apparaat dat het doorstuurt of bewaart, ziet wie er uploadt en wie er
ophaalt. Jouw toestemming geldt alleen voor dit ene bestand.

### Spraakberichten

1. Houd de microfoonknop in het invoerveld ingedrukt.
2. Spreek je bericht in.
3. Laat de knop los om het bericht te versturen.

Als spraakherkenning op je apparaat is ingeschakeld (zie instellingen),
wordt jouw spraakbericht automatisch als tekst getranscribeerd. Je tegenpartij
ziet dan zowel de opname als de getranscribeerde tekst.

### Berichten beantwoorden (citeren)

Om op een bepaald bericht te antwoorden:

1. Open het drie-punten-menu naast het bericht.
2. Kies "Antwoorden".
3. Boven het invoerveld verschijnt een banner met het geciteerde bericht.
4. Schrijf je antwoord en verstuur het.

Het geciteerde bericht wordt in je antwoord getoond, zodat het verband
duidelijk is.

### Berichten bewerken en verwijderen

- **Bewerken:** drie-punten-menu van het bericht, dan "Bewerken".
  Wijzig de tekst en verstuur hem opnieuw. Je tegenpartij ziet dat het
  bericht bewerkt is. Bewerken is binnen 15 minuten na
  het versturen mogelijk.
- **Verwijderen:** drie-punten-menu van het bericht, dan "Verwijderen". Het
  bericht wordt bij jou en je tegenpartij verwijderd. Je kunt je
  eigen berichten op elk moment verwijderen -- er is geen tijdvenster voor
  het verwijderen.

### Emoji-reacties

In plaats van een antwoord te schrijven, kun je op een bericht met een
emoji reageren:

1. Open het drie-punten-menu of houd het bericht lang ingedrukt.
2. Kies een emoji uit de snelle keuze of open de emoji-kiezer voor
   de volledige selectie.
3. Jouw reactie verschijnt onder het bericht.

### Tekst kopiëren

Via het drie-punten-menu van een bericht kun je de berichttekst naar het
klembord kopiëren.

### Berichten zoeken

Bovenaan het chatvenster vind je de zoekfunctie. Voer een
zoekterm in, en Cleona toont je alle treffers in de huidige chat. Met de
pijltoetsen kun je tussen de treffers heen en weer springen.

Op de startpagina is bovendien een zoekfilter dat alle tabbladen omvat,
waarmee je alle gesprekken op een term kunt doorzoeken.

### Linkvoorbeeld

Als je een link verstuurt, genereert Cleona automatisch een voorbeeld (titel,
beschrijving, voorbeeldafbeelding). Dit voorbeeld wordt door jouw apparaat gemaakt
en meegestuurd -- je tegenpartij hoeft daarvoor geen verbinding met de
gekoppelde website op te bouwen.

Wat een tik op een ontvangen link doet, stel je in de instellingen
onder "Links openen" in: "Normaal", "Bij voorkeur een privévenster"
(waar het apparaat geen privévenster kan openen, opent de link normaal)
of "Elke keer vragen".

---

## 5. Groepen

### Groep aanmaken

1. Ga naar het tabblad "Groepen".
2. Tik op de plusknop.
3. Geef de groep een naam.
4. Kies de contacten die je wilt uitnodigen.
5. Tik op "Aanmaken".

De uitgenodigde contacten ontvangen een melding en kunnen de groep
betreden.

### Hoe groepsberichten beschermd zijn

In een groep met tot 16 leden stuurt Cleona elk bericht aan elk
lid apart -- telkens alleen voor dat lid versleuteld, net
als had je aan elk een eigen bericht geschreven. De vinkjes aan een
groepsbericht tonen de stand van het lid bij wie het het minst ver is.

Groeit de groep boven 16 leden, dan gebruikt ze een gemeenschappelijke
sleutel. Die verandert elke dag en wordt opnieuw getrokken als een lid de
groep verlaat of wordt verwijderd; een nieuw lid leest pas vanaf zijn
toetreding. Daar tonen de vinkjes niet langer de stand van elk lid, maar
dat het bericht in het netwerk is gedeponeerd. Krimpt de groep tot 12 of
minder leden, dan gaat ze terug naar het apart versturen aan elk lid.

### Afbeeldingen in groepen en kanalen

In de instellingen van een groep of een kanaal leg je met "Afbeeldingen
altijd laden" vast of afbeeldingen meteen worden geladen of pas wanneer je
op een ervan tikt.

### Leden uitnodigen

Ook na het aanmaken kun je meer contacten uitnodigen:

1. Open de groepsinfo (drie-punten-menu in het groepsoverzicht of
   bovenste balk in de groepschat).
2. Tik op "Uitnodigen".
3. Kies de contacten die je wilt toevoegen.

### Rollen

Elke groep heeft drie rollen:

- **Eigenaar (Owner):** Heeft de volledige controle. Kan leden
  toevoegen en verwijderen, admins aanwijzen en de groep beheren. De
  eigenaar kan zijn status ook aan een ander lid overdragen.
- **Admin:** Kan leden verwijderen en helpen bij het beheer.
- **Lid:** Kan berichten lezen en schrijven.

### Groep verlaten

1. Open het drie-punten-menu in het groepsoverzicht.
2. Kies "Verlaten".
3. Bevestig je beslissing.

Als je een groep verlaat, blijven je eerdere berichten voor de
andere leden zichtbaar.

---

## 6. Openbare kanalen

### Wat zijn kanalen?

Kanalen zijn openbare discussiefora binnen het Cleona-netwerk.
In tegenstelling tot groepen kan hier iedereen meelezen, zonder uitgenodigd te
moeten worden. Alleen de eigenaar en admins kunnen berichten publiceren --
abonnees lezen mee.

### Kanalen vinden en betreden

1. Ga naar het tabblad "Kanalen".
2. Open het tabblad "Zoeken".
3. Doorzoek de beschikbare kanalen op naam of onderwerp.
4. Tik op een kanaal en dan op "Abonneren".

Kanalen kunnen op taal gefilterd worden. Sommige kanalen zijn als "Niet
jeugdvrij" gemarkeerd -- deze zijn alleen zichtbaar als je in je profiel
hebt bevestigd dat je boven 18 bent.

### Eigen kanaal aanmaken

1. Ga naar het tabblad "Kanalen".
2. Tik op de plusknop.
3. Voer een kanaalnaam in (moet in het hele netwerk uniek zijn).
4. Kies de taal en of het kanaal openbaar of privé moet zijn.
5. Optioneel: voeg een beschrijving en een afbeelding toe.
6. Tik op "Aanmaken".

Bij openbare kanalen kun je bepalen of de inhoud als "Niet
jeugdvrij" wordt ingedeeld.

### Inhoud melden

Als je in een openbaar kanaal ongepaste inhoud opmerkt, kun je
die melden. Cleona gebruikt een gedecentraliseerd moderatiesysteem: meldingen
worden door willekeurig geselecteerde leden van het netwerk beoordeeld (een soort
"jury"). Wordt een overtreding vastgesteld, dan krijgt het kanaal een
waarschuwing. Bij herhaalde overtredingen wordt het in de zoekindex gedegradeerd of
geblokkeerd.

### Systeemkanalen

Cleona beschikt over twee ingebouwde systeemkanalen:

- **Bug Log:** Als Cleona een fout herkent, vraagt het je of je een
  foutrapport wilt versturen; vooraf zie je precies wat er gepubliceerd
  wordt. Deze rapporten belanden in het Bug-Log-kanaal, waar ze door
  de community kunnen worden bekeken. Een rapport draagt geen naam en
  geen inhoud van je gesprekken, maar een pseudoniem. In de bèta noemt
  hij bovendien je User-ID, zodat de ontwikkelaars kunnen navragen. Je
  kunt ook handmatig een lograpport versturen (met voorbeelddialoog en
  expliciete toestemming).
- **Feature Requests:** Hier kunnen gebruikers functiewensen indienen
  en stemmen op bestaande voorstellen. De voorstellen worden op
  stemmen gesorteerd.

Elke computer houdt tot 25 MB per systeemkanaal aan, elke telefoon tot
5 MB; is dat vol, gaat het oudste eerst -- nooit wat je zelf al hebt
gezien.

---
## 7. Oproepen

### Spraakoproep starten

1. Open de chat met het contact dat je wilt bellen.
2. Tik op het telefoonsymbool in de bovenste balk.
3. Wacht tot je tegenpartij de oproep accepteert.

Tijdens het gesprek zie je een tijdlijn, de gespreksduur en
heb je toegang tot dempen en luidspreker.

Tik om op te hangen op de rode ophangknop.

Zie je "Niet bereikbaar", dan is het apparaat van je tegenpartij op dit moment
niet te bereiken, bijvoorbeeld een iPhone waarvan de app niet openstaat. Stuur
in plaats daarvan een bericht.

### Videooproep starten

1. Open de chat met het contact.
2. Tik op het camerasymbool in de bovenste balk.
3. Jouw videobeeld verschijnt in een klein venster, het beeld van je
   tegenpartij in het grote gebied.

Je kunt tijdens het gesprek tussen voor- en achtercamera wisselen.

### Binnenkomende oproepen

Als iemand je belt, verschijnt een meldingsvenster met de naam
van de beller. Je kunt:

- **Accepteren** -- het gesprek begint.
- **Weigeren** -- de beller wordt op de hoogte gesteld.

Zit je op dit moment in een gesprek, dan gaat een nieuwe oproep niet over; je
krijgt in plaats daarvan een bericht "Gemiste oproep". Datzelfde geldt voor
een groepsoproep die je niet hebt geaccepteerd -- het bericht staat dan in
de groepschat.

Belt iemand een van je identiteiten die op dit moment niet wordt getoond,
dan gaat het toch over; het oproepscherm noemt welke van je identiteiten
wordt gebeld.

Op de iPhone wordt er alleen overgegaan als de app openstaat. Wie je belt
terwijl de app niet openstaat, ziet na 10 seconden "Niet bereikbaar". Zodra je
de app opent, vind je een bericht over de gemiste oproep.

### Groepsoproepen

Je kunt ook groepsoproepen voeren, waaraan meerdere personen tegelijk
deelnemen. De oproep wordt via een intelligente doorstuurboom georganiseerd, zodat niet elke deelnemer rechtstreeks met elke andere
verbonden hoeft te zijn. Alle gesprekken zijn doorlopend versleuteld.

Elk groepslid kan een groepsoproep starten. Twee deelnemers die geen
contacten van elkaar zijn, zien nooit elkaars internetadres: hun geluid en
beeld lopen via een deelnemer die met beiden contact is. Is er zo iemand
niet, dan zijn de twee niet verbonden, en zegt de tegel "Geen
gemeenschappelijk contact in het gesprek". Is een doorsturing overbelast, dan blijft
het geluid en valt het beeld voor dit paar weg.

### Versleuteling bij oproepen

Alle oproepen worden versleuteld met eenmalige sleutels die alleen voor de
duur van het gesprek bestaan. Na het ophangen worden deze sleutels
meteen verwijderd. Niemand kan een afgelopen gesprek achteraf
ontsleutelen.

Eerlijk gezegd: oproepen verlopen, waar mogelijk, rechtstreeks tussen de
apparaten, want al een kleine vertraging stoort bij het spreken. Anders
dan bij berichten kan je internetprovider daarom bij een oproep zien,
met welk internetadres je verbonden bent. Wat jullie zeggen, ziet hij niet.

Bij een oproep ziet ook je contact je internetadres. Wil je dat bij een
contact niet, zet dan in zijn menu "Bellen toestaan" uit (standaard: aan).
Zet je hem later uit, dan blijft een al gezien adres bij hem bekend.

---

## 8. Agenda

Cleona bevat een ingebouwde agenda die versleuteld en volledig
gedecentraliseerd werkt -- zonder cloud-dienst.

### Weergaven

De agenda biedt vijf weergaven: dag, week, maand, jaar en een
takenweergave. Schakel tussen hen via de tabbladen bovenaan het
agenda-scherm.

### Afspraken aanmaken

Tik op een tijdslot of gebruik de toevoegknop om een nieuwe
afspraak aan te maken. Je kunt titel, datum, tijd, locatie en notities
invullen. Afspraken worden versleuteld op jouw apparaat opgeslagen.

### Terugkerende afspraken

Afspraken kunnen dagelijks, wekelijks, maandelijks of jaarlijks
herhalen. Je kunt het patroon aanpassen (bijv. elke tweede dinsdag,
elke eerste van de maand) en een einddatum of een aantal herhalingen
vastleggen.

### Contacten uitnodigen

Bij het aanmaken of bewerken van een afspraak kun je je Cleona-contacten
uitnodigen. Zij ontvangen een versleutelde agenda-uitnodiging en kunnen met
ja, nee of misschien antwoorden. Wijzigingen aan de afspraak worden
automatisch naar alle uitgenodigden gestuurd.

### Vrij/bezet-weergave

Je kunt je beschikbaarheid met contacten delen, zonder afspraakdetails
prijs te geven. Er zijn drie privacy-niveaus: volledige details, alleen tijdblokken
of verborgen. Je kunt een standaard instellen en hem per contact
overschrijven.

### Herinneringen

Afspraken kunnen herinneringen hebben die vóór aanvang van de afspraak een
systeemmelding activeren. Je kunt herinneringen indien nodig
laten sluimeren.

### Externe agenda-synchronisatie

Cleona kan synchroniseren met externe agenda-diensten:

- **CalDAV** -- verbind met elke CalDAV-compatibele server (Nextcloud,
  Radicale enz.).
- **Google Agenda** -- synchronisatie via de Google Calendar API met
  veilige OAuth2-authenticatie.
- **Lokale CalDAV-server** -- Cleona kan een lokale CalDAV-server op
  jouw apparaat starten, zodat desktop-agenda-apps (Thunderbird, Outlook,
  Apple Agenda, Evolution) met jouw Cleona-agenda kunnen synchroniseren.
- **Android-systeemagenda** -- afspraken uit Cleona kunnen naar de
  ingebouwde agenda-app van je Android-apparaat worden overgedragen.
- **ICS-bestanden** -- importeer en exporteer afspraken in het
  standaard iCalendar-formaat.

### PDF-export

Je kunt elke agendaweergave (dag, week, maand, jaar) als PDF-document
afdrukken of exporteren.

---

## 9. Peilingen

Je kunt in elke chat of groep peilingen aanmaken om meningen
te verzamelen of data te plannen.

### Peilingstypen

Cleona ondersteunt vijf soorten peilingen:

- **Enkele keuze** -- deelnemers kiezen één optie.
- **Meerdere keuze** -- deelnemers kunnen meerdere opties kiezen.
- **Datumpeiling** -- vind een datum die voor iedereen past. Elke
  deelnemer markeert data als beschikbaar, misschien of niet
  beschikbaar.
- **Schaal** -- beoordeel iets op een numerieke schaal (bijv. 1 tot 5).
- **Vrije tekst** -- deelnemers schrijven hun eigen antwoord.

### Peiling aanmaken

Open een chat en tik op het peilingsymbool (of gebruik het
bijlagemenu). Kies het peilingstype, formuleer je vraag en de
opties, en verstuur de peiling. Ze verschijnt als bericht in de chat.

### Stemmen

Tik op een peiling om je stem uit te brengen. Je kunt je stem op elk
moment wijzigen of intrekken.

### Anoniem stemmen

Peilingen kunnen voor anoniem stemmen worden geconfigureerd. Indien ingeschakeld,
zijn stemmen cryptografisch anoniem -- niemand, zelfs niet de
peiling-maker, kan zien wie waarop gestemd heeft. Het stemtal
blijft toch zichtbaar.

### Datumpeiling naar agenda

Als een datumpeiling afgesloten is, kan de winnende datum met één
tik rechtstreeks in een agenda-item worden omgezet.

---
## 10. Meerdere identiteiten

### Waarom meerdere identiteiten?

Stel je voor dat je je werk en je privéleven wilt scheiden --
vergelijkbaar met twee verschillende telefoonnummers, maar zonder tweede telefoon.
In Cleona kun je meerdere identiteiten op één apparaat gebruiken. Elke
identiteit heeft een eigen naam, een eigen profielfoto, eigen contacten en
eigen gesprekken.

### Nieuwe identiteit aanmaken

1. In de bovenste balk zie je je huidige identiteit als tabblad.
2. Tik op het plusteken (+) rechts naast je identiteitstabbladen.
3. Voer een naam in voor de nieuwe identiteit.
4. Klaar -- de nieuwe identiteit is meteen actief.

### Tussen identiteiten wisselen

Tik gewoon op het identiteitstabblad in de bovenste balk. De wissel
is meteen -- geen wachttijd, geen herladen.

### Alle draaien tegelijk

Een belangrijk punt: al je identiteiten zijn tegelijk actief. Ook
als je op dit moment als "Werk" wordt getoond, ontvangt je "Privé"-
identiteit nog steeds berichten. Je mist niets, ongeacht welke identiteit
je op dit moment hebt gekozen.

### Identiteitsdetailpagina

Als je op het tabblad van je zojuist actieve identiteit tikt, opent de
detailpagina. Hier kun je:

- Jouw QR-code voor contacten tonen.
- Jouw profielfoto wijzigen of verwijderen.
- Een profielbeschrijving toevoegen.
- Jouw weergavenaam wijzigen.
- Een design (skin) voor deze identiteit kiezen.
- De identiteit verwijderen, als je haar niet meer nodig hebt.

### Identiteit verwijderen

Als je een identiteit verwijdert, worden je contacten daarover
op de hoogte gesteld. De identiteit en alle bijbehorende gegevens worden van je
apparaat verwijderd. Dit proces is niet omkeerbaar.

---

## 11. Meerdere apparaten

### Eén identiteit, één apparaat -- voorlopig

Een identiteit draait vandaag op één apparaat. Een tweede apparaat voor
dezelfde identiteit komt met een latere versie; in de instellingen
onder "Apparaten" -> "Apparaten beheren" staat "Nog een apparaat
koppelen" daarom nog als "Nog niet beschikbaar".

Komt het, dan geldt: alle apparaten zijn gelijkwaardig, er is geen
hoofdapparaat. Een extra apparaat richt je met je 24 woorden in, en één
van je huidige apparaten geeft toestemming. Hooguit 5 apparaten.

Vul je vandaag op een nieuw apparaat je 24 woorden in, dan verhuis je: de
identiteit wordt op het nieuwe apparaat hersteld, en je huidige apparaat
verwijdert haar daarna bij zich (zie hoofdstuk 12).

Op meerdere apparaten kun je vandaag verschillende identiteiten gebruiken
(hoofdstuk 10).

### Sleutels van je identiteit vernieuwen

Vermoed je dat iemand aan je sleutels is gekomen, dan kun je onder
"Apparaten beheren" -> "Sleutels roteren" nieuwe sleutels laten aanmaken.
Je contacten worden op de hoogte gesteld, je open uitnodigingen worden
ingetrokken. Belangrijk: daarna herstellen de 24 woorden alleen nog de
oude sleutels. Maak daarom direct daarna een nieuw herstelpakket aan;
herstellen kan daarna alleen nog samen met dit pakket.

---

## 12. Herstel

### Seed-phrase gebruiken

Als je je apparaat verliest of een nieuw inricht:

1. Installeer Cleona op het nieuwe apparaat.
2. Kies bij het starten "Herstellen".
3. Voer je 24 woorden in.
4. Cleona maakt daaruit al je identiteiten weer aan -- met dezelfde
   sleutels als daarvoor. Voor je contacten ben jij dezelfde mens.

### Wat terugkomt -- en wat niet

Jouw identiteit zit in de 24 woorden, je contacten en je
gespreksgeschiedenis niet. Terug komt je toegang tot het netwerk via het
**herstelpakket**: jouw apparaat legt een klein, versleuteld pakket in het
netwerk. Alleen jouw 24 woorden kunnen het vinden en openen. Daarin staat
wat je nieuwe apparaat nodig heeft om je contacten weer te bereiken, en wat
er ondertussen voor jou in het netwerk lag. Daarvoor hoeft geen contact
online te zijn.

Je eerdere chatgeschiedenis komt bij een herstel niet terug.

Het herstelpakket leeft 7 dagen en wordt door je apparaat vernieuwd,
zolang het draait; in de instellingen zie je tot wanneer het geldt. Heeft
langer dan 7 dagen geen van je apparaten gedraaid, dan is het verlopen.
Dan herstellen de 24 woorden je identiteit toch, maar je contacten moet
je opnieuw uitnodigen; wat er ondertussen voor jou in het netwerk lag, is
verloren.

### Herstellen betekent verhuizen

Stelt je huidige apparaat later vast dat de identiteit ergens anders is
hersteld, dan verwijdert het haar bij zich -- met haar gespreksgeschiedenis.
Daarom: wie je 24 woorden heeft, kan je identiteit op deze manier van je
apparaat halen. Tot alle contacten er weer zijn, herinnert de app je
eraan; met "Afronden en sleutels vernieuwen" rond je het herstel zelf af.

### Wat niemand kan herstellen

Dit is belangrijk, en we zeggen het daarom duidelijk:

- **Niemand behalve jij kan je identiteit herstellen.** Niet de
  ontwikkelaar, niet een support, en ook niet je contacten -- hoeveel van hen
  er ook zijn. Er is geen mastersleutel en geen deel van je
  sleutel dat bij anderen in bewaring zou liggen.
- **Heb je de 24 woorden verloren en geen apparaat meer, dan is je identiteit
  verloren.** Dan blijft alleen nog een nieuwe aanmaken en je contacten opnieuw
  uitnodigen.

De beste bescherming: schrijf de 24 woorden op papier en bewaar ze veilig.

---
## 13. Instellingen

Je bereikt de instellingen via het tandwielsymbool in de rechterbovenhoek.

### Meldingen en beltonen

- Kies uit zes verschillende beltonen voor binnenkomende oproepen.
- Stel een berichtgeluid in.
- Op Android-apparaten kun je bovendien de trilling activeren of
  deactiveren.
- **"Alles dempen"** laat op dit apparaat geen bericht meer overgaan,
  trillen of zich melden -- voor alle identiteiten. Oproepen blijven
  overgaan.
- **"Stille uren"** stel je per identiteit met van/tot vast. In deze tijd
  gaat er geen bericht van deze identiteit over, trilt of meldt zich; de
  berichten komen toch aan.
- **"Meldingen zonder inhoud"** (standaard: uit) toont alleen dat een
  bericht, uitnodiging of herinnering is aangekomen -- zonder afzender,
  naam en tekst. Oproepen tonen verder de naam.
- Wat na het starten in één keer binnenkomt, meldt Cleona in een
  verzamelmelding ("5 nieuwe berichten in 2 gesprekken"); alles wat
  later komt, afzonderlijk. Een tik op een berichtmelding opent het
  gesprek, ook in een andere identiteit.

### Designs (skins)

Cleona biedt tien verschillende designs: Teal, Ocean, Sunset, Forest,
Amethyst, Fire, Storm, Slate, Gold en Contrast. Het Contrast-design voldoet
aan het hoogste toegankelijkheidsniveau (WCAG AAA) en is bij beperkt
zicht bijzonder goed leesbaar.

Elke identiteit kan een eigen design hebben. Je wijzigt het design in de
identiteitsdetailpagina (tik op het actieve identiteitstabblad).

Bovendien kun je in de instellingen onder "Weergave" tussen
licht, donker en het systeemthema wisselen.

### Taal wijzigen

Cleona is beschikbaar in 34 talen, waaronder ook talen met
recht-naar-links-schrift (bijv. Arabisch, Hebreeuws). Wijzig de taal in
de instellingen onder "Taal".

### Media-archivering

Als je thuis een netwerkopslag (NAS) of een gedeelde map
hebt, kan Cleona je media automatisch daarheen uitladen. Ondersteund
worden SMB, SFTP, FTPS en WebDAV.

Zo werkt de getrapte opslag:
- De eerste 30 dagen: alles blijft op je apparaat.
- Na 30 dagen: een voorbeeldafbeelding blijft op het apparaat, het origineel wordt
  gearchiveerd.
- Na 90 dagen: alleen nog een kleine voorbeeldafbeelding blijft op het apparaat.
- Na een jaar: alleen nog een plaatshouder blijft, het origineel ligt veilig
  in het archief.

Je kunt op elk moment op een gearchiveerd medium tikken om het terug te halen --
op voorwaarde dat je met je thuisnetwerk verbonden bent. Bijzonder belangrijke
media kun je vastpinnen, zodat ze nooit worden uitgeladen.

Onder "Opslagbudget" leg je vast hoeveel MB media op het apparaat
blijven (standaard: 100 MB op de telefoon, 2 GB op de computer). Is het
vol, dan wordt het oudste niet vastgepinde medium eerst gearchiveerd.
Verwijderd wordt een origineel alleen als het veilig in het archief ligt --
tekstberichten blijven altijd behouden.

### Transcriptie voor spraakberichten

Indien ingeschakeld, worden je spraakberichten lokaal op je apparaat naar
tekst omgezet (met het open-source-model Whisper). De getranscribeerde tekst
wordt samen met de opname naar je tegenpartij gestuurd. De transcriptie
gebeurt volledig op je apparaat -- er gaan geen gegevens naar externe diensten.

Welk model (tiny, base, small) wordt gedownload, stel je eenmalig voor het
apparaat in; de taal (automatisch of vast) per identiteit.

### Automatisch downloaden

Je kunt instellen vanaf welke grootte media automatisch moeten worden gedownload.
Zo kun je bijvoorbeeld afbeeldingen automatisch laten laden, maar
bij grote video's zelf beslissen.

### Apparaten

Onder "Apparaten" -> "Apparaten beheren" zie je dit apparaat. Een extra
apparaat koppelen komt met een latere versie (hoofdstuk 11).

### Netwerk

Cleona heeft geen netwerkinstellingen nodig om te werken. Er zijn
drie netwerkschakelaars:

- **Poort vrijgeven op de router** (standaard: aan). Cleona vraagt je eigen
  router om een deur voor Cleona te openen. Lukt dat, dan is je apparaat
  voor anderen beter bereikbaar en helpt het het netwerk. Cleona spreekt daarbij alleen met
  je router, niet met het internet.
- **Openbare adresvermeldingen** (standaard: aan). Heeft je apparaat nog te
  weinig buren, dan zoekt het in een openbaar register (Nostr) naar
  verdere instappunten, en is het zelf goed bereikbaar, dan vermeldt het zich
  daar. De vermelding bevat een adres, geen naam en geen contact.
  Schakel je hem uit, dan vindt je apparaat buren alleen nog via uitnodigingen,
  het lokale netwerk en de buren die het al kent.
- **Minder dekmantelpakketten in het Wi-Fi** (standaard: uit). In het Wi-Fi of aan de kabel kun
  je de lege dekmantelpakketten uitschakelen. Maar dan is daar weer te zien,
  wanneer je schrijft. Op mobiele data is er deze schakelaar niet -- daar
  stuurt Cleona toch al maar één dekmantelpakket per minuut.

Het dekmantelverkeer als geheel kan men niet uitschakelen. Dat is opzettelijk: pas als
het altijd draait, zegt de activiteit van je apparaat niets over of
je op dit moment schrijft.

Boven de drie schakelaars staat de **Databesparingsmodus**: op mobiele data stelt Cleona hem voor, maar schakelt Cleona hem nooit zelf in. Hij bespaart data, maar daardoor is je apparaat van buitenaf makkelijker te herkennen.

Daaronder stel je de **"Cache voor media van anderen"** in: jouw
apparaat houdt versleutelde delen van media van anderen tot 7 dagen,
zodat ze hun ontvangers bereiken (standaard: 100 MB op de telefoon,
1 GB op de computer). Een kleinere grootte geeft de ruimte meteen vrij --
de oudste delen eerst.

---

## 14. Beveiliging

### Wat betekent post-kwantum-versleuteling?

Huidige versleuteling is gebaseerd op wiskundige problemen die voor normale
computers buitengewoon moeilijk op te lossen zijn. Kwantumcomputers zouden sommige van deze
problemen in de toekomst snel kunnen oplossen. Post-kwantum-versleuteling gebruikt
bijkomende methoden die ook kwantumcomputers weerstaan.

Cleona combineert beide benaderingen: klassieke versleuteling voor
betrouwbaarheid en post-kwantum-methoden voor toekomstbestendigheid. Zo ben je
tegelijk tegen huidige en toekomstige bedreigingen beschermd.

Voor elk afzonderlijk bericht wordt een eigen sleutel gegenereerd. Zelfs als
een aanvaller de sleutel van één bericht zou kraken, zou hij daarmee
geen ander bericht kunnen lezen.

### Waarom geen server veiliger is

Bij conventionele messengers lopen je berichten via de servers van de
provider. Ook als ze daar versleuteld zouden zijn: de provider heeft
toegang tot metadata (wie communiceert wanneer met wie, hoe vaak, van waar) en
moet deze onder omstandigheden op rechterlijk bevel uitleveren.

Bij Cleona is er geen zulk centraal punt. Er is geen plaats waar
alle metadata samenkomen, en geen register waarin men zou kunnen opzoeken
wie je bent of wie je kent.

### Wie ziet dat je met iemand schrijft?

Versleuteling beschermt **wat** je schrijft. Net zo belangrijk is dat
geen enkele afzonderlijke waarnemer te weet komt **met wie** en
**wanneer** je schrijft. Daarvoor zorgt Cleona als volgt:

- **Op het internet nooit rechtstreeks.** Stuurde je apparaat een bericht rechtstreeks naar het
  internetadres van je tegenpartij, dan zou je provider kunnen zien met
  wie je schrijft. Daarom gaat een bericht op het internet altijd via jullie
  vaste buren: die van jou en die van je tegenpartij.
- **Buren die je vertrouwt.** Jouw vaste buren zijn, waar mogelijk,
  apparaten van je eigen contacten -- tot drie die op dit moment van
  buiten bereikbaar zijn. Valt er een weg, dan schuift een ander contact op.
  Een contact laat zich niet met servers kopen; een willekeurig knooppunt in het
  netwerk wel. Heb je nog geen bereikbaar contact, dan neemt Cleona een
  andere buur. Jouw uitnodiging noemt nooit een van je contacten, zodat
  niemand via hen het adres van een vriend te weten komt.
- **Codes in plaats van namen.** De buren zien geen namen en geen identificaties,
  maar alleen een code. Hij geldt voor precies jullie beiden, in één richting,
  voor één dag -- de volgende dag is het een andere. Jouw buur weet
  waar het pakket vandaan komt, maar niet waar het uiteindelijk heen gaat. De buur van je
  tegenpartij weet waar het heen gaat, maar niet waar het vandaan kwam. Normaal
  gesproken ziet niemand onderweg beide uiteinden.
- **Het dekmantelverkeer.** Jouw apparaat stuurt voortdurend, op onregelmatige
  tijdstippen, dekmantelpakketten naar zijn buren. Ze zijn net zo
  groot als echte pakketten, gaan via dezelfde poort en zijn
  van buiten niet van hen te onderscheiden. Of er op dit moment een mens schrijft of het apparaat alleen draait, is er
  niet aan af te zien. Jouw berichten wachten nooit op het dekmantelverkeer --
  ze gaan meteen op weg, het draait alleen ernaast.

**Wat het dekmantelverkeer kost:** in het Wi-Fi ongeveer 13 MB per dag.
Op mobiele data stuurt Cleona slechts één dekmantelpakket per minuut,
dat is ongeveer 1,7 MB per dag. De reden voor de beperking op mobiele
data is niet de datavolume, maar de accu: elk pakket wekt
de radiomodem.

**Wat Cleona niet kan verbergen** -- eerlijk gezegd:

- Geen **enkele** waarnemer ziet wie met wie schrijft -- noch je
  provider noch de knooppunten onderweg. Wie echter **beide uiteinden tegelijk**
  bewaakt, bijvoorbeeld een staat die jouw aansluiting en die van je
  tegenpartij observeert of beide buren opstelt, kan in de loop der tijd
  toewijzen: pakket naar buiten bij jou, kort daarna pakket naar binnen bij je tegenpartij.
  Vaak genoeg herhaald, levert dat een verband op.
- Het dekmantelverkeer maakt deze toewijzing moeilijker, maar voorkomt haar niet. Het
  verbergt afzonderlijke berichten, niet de hoeveelheid: wie heel veel verstuurt,
  verhoogt het totaalverkeer van zijn apparaat.
- Een contact dat je vaste buur is, komt te weten **wanneer** en **hoeveel**
  je verstuurt en ontvangt -- niet met wie en niet wat. Komt het gevaar
  uit je eigen omgeving, dan kun je elk contact ervan uitzonderen (zie
  hoofdstuk 3, "Nooit als vaste buur gebruiken").
- Hebben twee nieuwe gebruikers alleen dezelfde ene buur, dan loopt hun bericht
  via precies dit knooppunt, en hij ziet beide uiteinden. Zodra een van
  beiden verdere buren heeft, is dat voorbij.
- Jouw uitnodiging bevat je internetadressen. Wie de tekstregel heeft,
  ziet waar je online bent -- geef hem alleen aan mensen die je dat toevertrouwt.
- Een buur die doorstuurt, ziet dat twee codes pakketten uitwisselen --
  niet wie erachter staat, en niet wat erin zit.
- Een signaal van een lopende oproep kan, als de eerste buur op dat moment
  niet antwoordt, via een knooppunt gaan dat beide uiteinden ziet; het
  komt te weten dat jullie samen bellen.
- Een groot bestand waar je toestemming voor hebt gegeven, ziet de
  computer die het doorstuurt of bewaart aan beide uiteinden (zie
  hoofdstuk 4).
- Bij oproepen geldt de bescherming tegen de provider niet, en ziet je
  contact je internetadres (zie hoofdstuk 7).

### Wat gebeurt er als je tegenpartij offline is?

1. Cleona start alle geschikte routes tegelijk: in hetzelfde Wi-Fi rechtstreeks,
   op het internet via twee buren -- en bovendien de postbus.
2. Voor de postbus deponeert Cleona het versleutelde bericht bij drie
   buren. Zodra twee de ontvangst hebben bevestigd, geldt het als
   gedeponeerd.
3. Cleona kiest daarvoor bij voorkeur buren bij wie je tegenpartij ook
   kijkt -- eerst de buur die zijn uitnodiging noemt.
4. Het bericht wacht daar tot 7 dagen. Komt je tegenpartij terug,
   dan haalt hij het op en bevestigt hij je de ontvangst. Pas dan zie je twee
   vinkjes.

Alleen je tegenpartij kan de postbus legen: ophalen en verwijderen gaat
alleen met een sleutel die alleen hij bezit, en verwijderd wordt pas als
hij de ontvangst heeft bevestigd. De buren zien alleen versleutelde
pakketten onder een waarde die elke dag wisselt.

### Vreemden komen er niet door

Van iemand die noch je contact noch lid van een gemeenschappelijke groep
is, aanvaardt Cleona precies twee dingen:
de vraag naar je publieke sleutels, zolang een van je
uitnodigingen open staat, en een contactverzoek. Het verzoek moet een geldige
uitnodiging van jou dragen, en de afzender moet vooraf een rekenopgave
hebben opgelost. Alles andere -- berichten, oproepen, bestanden -- wordt verworpen,
voordat het de app überhaupt bereikt. Wie alleen je gedrukte visitekaartje
heeft, kan je dus niet zomaar bellen. Een lid van een gemeenschappelijke
groep bereikt je alleen in die groep -- met groepsberichten en
groepsoproepen, nooit afzonderlijk.

### Anti-censuur

Cleona is zo gebouwd dat het moeilijk te blokkeren is:

- **Geen server, geen vast adres.** In de app staat geen adres dat men
  zou kunnen blokkeren, en het netwerk hangt niet af van één enkel knooppunt.
- **Geen vaste poort.** Elk apparaat kiest bij de eerste start een
  willekeurige poort. Er is geen bekend poortnummer waaraan men
  Cleona-verkeer zou kunnen herkennen.
- **Als willekeurige data.** De verbindingsopbouw tussen twee apparaten is zo
  gecodeerd dat hij van willekeurige data niet te onderscheiden is.
- **Veel instappunten.** Elke uitnodiging, elke buur en elk apparaat in
  hetzelfde Wi-Fi is een mogelijke weg terug het netwerk in.

### Veilige sleutelopslag

Op ondersteunde platformen slaat Cleona je versleutelings-
sleutels op in de veilige sleutelring van het besturingssysteem (Android Keystore,
iOS Keychain, macOS Keychain). Waar beschikbaar biedt dat hardwarematige
bescherming voor je sleutels.

### Databaseversleuteling

Jouw berichten en gesprekken liggen in een versleutelde
database -- een eigen voor elke identiteit, elk met eigen sleutel.
Versleuteld is niet alleen de database zelf, maar ook haar
tussenbestanden; er wordt niets onversleuteld naar schijf geschreven,
ook niet kortstondig. Instellingen, contacten en media zijn eveneens
versleuteld opgeslagen.

De sleutels worden afgeleid van je 24 woorden en bestaan alleen
op je apparaat. Zelfs wie je apparaat in handen krijgt en de gegevens
uitleest, vindt zonder deze sleutels alleen onleesbare gegevens.

Onversleuteld is het alleen waar je inhoud zelf uit Cleona naar buiten
brengt:
- als je een bestand uit een chat op je apparaat opslaat,
- als je met de schermafbeeldingsknop een afbeelding in je galerij legt,
- als je iets aan een andere app deelt,
- als je de media-archivering instelt (hoofdstuk 13): de gearchiveerde
  originelen liggen onversleuteld op je netwerkopslag thuis, zodat je ze
  daar ook zonder Cleona kunt openen,
- als je afspraken naar de Android-systeemagenda spiegelt: daar kunnen
  andere apps met agendatoegang ze lezen.

Wat zo naar buiten is gegaan, wordt niet samen met het bericht verwijderd
en verloopt ook niet samen met het bericht.

### Bescherming op het scherm

Op Android, Windows en macOS laat Cleona geen schermopname door andere
apps toe. Heb je een afbeelding nodig, gebruik dan de
schermafbeeldingsknop in de bovenste balk: hij legt de afbeelding in je
galerij -- onversleuteld. In een gesprek waarin doorsturen niet is
toegestaan, is er geen schermafbeelding.

---

## 15. Software-updates

### Hoe krijg ik updates?

Cleona kan via verschillende wegen worden bijgewerkt. Het doel is dat je
ook updates kunt ontvangen als afzonderlijke distributiekanalen uitvallen
of worden geblokkeerd:

1. **App Store / Play Store:** Zodra Cleona daar verschijnt en je het
   via een store hebt geïnstalleerd, ontvang je updates zoals gebruikelijk
   via de store. Op de iPhone komen updates via TestFlight.
2. **GitHub Releases:** Op de GitHub-pagina van het project vind je
   ondertekende installatiepakketten voor alle platformen.
3. **Updates via het netwerk:** Cleona kan een update rechtstreeks via het netwerk
   ophalen -- zonder downloadserver. De nieuwe versie is in
   foutgecorrigeerde stukken gesplitst, die zich in het netwerk verspreiden; een deel
   daarvan reist zelfs mee in het dekmantelverkeer. Jouw apparaat verzamelt genoeg stukken en
   zet de update in elkaar. Overgedragen wordt meestal alleen de wijziging --
   enkele MB in plaats van de hele app. Dat geldt voor Linux, Windows en
   Android; onder macOS download je nieuwe versies van de website of van
   GitHub.
4. **Uitnodigingslinks:** Je kunt uitnodigingslinks aanmaken die alles
   bevatten wat een nieuwe gebruiker nodig heeft om Cleona te installeren en
   zich met het netwerk te verbinden.
5. **Fysieke overdracht:** In omgevingen zonder internet kun je Cleona
   per USB-stick of in het lokale netwerk aan anderen doorgeven.

### Zo verloopt een update

1. Cleona verzamelt de stukken van een nieuwe update automatisch op de achtergrond
   en zet ze in elkaar.
2. Pas als de update **volledig** is en zijn **handtekening is geverifieerd**,
   biedt Cleona hem je aan. Je krijgt dus nooit een halve of
   ongeverifieerde update aangeboden.
3. Tik je op "Installeren", dan start de installatie zonder verdere
   navraag. Op Android toont bovendien het systeem zijn
   installatiedialoog.

Oudere versies worden niet aangeboden -- een update gaat altijd alleen
vooruit. Is een versie zo oud dat hij niet meer met het netwerk kan
samenwerken, dan geeft Cleona dat duidelijk aan en verzoekt je te
actualiseren.

### Handtekeningverificatie

Elke update is dubbel ondertekend: met een klassieke en een
post-kwantum-methode. Cleona verifieert beide handtekeningen automatisch. Zo
is verzekerd dat alleen updates van de officiële ontwikkelaar worden geaccepteerd --
ook als de update via het netwerk van vreemde apparaten kwam. Een
update ontstaat nooit automatisch uit de ontwikkeling, maar pas als de
ontwikkelaar hem met de hand ondertekent.

---
## 16. Veelgestelde vragen

### "Kan ik Cleona zonder internet gebruiken?"

Cleona heeft een netwerkverbinding nodig, maar niet noodzakelijk het internet:
in hetzelfde Wi-Fi vinden Cleona-apparaten elkaar zelf en kunnen helemaal zonder
internettoegang met elkaar schrijven. Tegelijkertijd online hoef je met je
tegenpartij niet te zijn: is hij offline, dan wacht het bericht tot 7 dagen
in de postbus bij drie buren, tot hij het ophaalt.

### "Wat als ik mijn seed-phrase verlies?"

Zolang nog een apparaat met je identiteit draait, is er niets verloren --
daar schrijf je gewoon verder. Op het apparaat waarop je de identiteit
hebt aangemaakt, kun je de 24 woorden meestal opnieuw aflezen (zie
hoofdstuk 2). Verlaat je daar niet op: een herinstallatie ruimt deze kopie
op, en op Android vernietigt ook het verwijderen of wijzigen van de
schermvergrendeling hem. Heb je noch de woorden noch
een apparaat, dan is er geen weg terug -- ook niet via je contacten,
de ontwikkelaar of wie dan ook. Daarom is het zo belangrijk, de 24
woorden veilig te bewaren.

### "Kan iemand op mijn berichten meelezen?"

Nee. Elk bericht wordt met een eenmalige sleutel versleuteld, die
alleen voor dit ene bericht geldt. Alleen jij en je tegenpartij kunnen het
bericht ontsleutelen. Er is geen centrale server, geen mastersleutel
en geen toegang voor de ontwikkelaar. Zelfs als een apparaat op de
transportweg het bericht doorstuurt, ziet het alleen versleutelde brij
en een code. Jouw buur weet dat het pakket van jou komt, maar niet
aan wie het gaat; de buur van je tegenpartij weet aan wie het gaat, maar
niet van wie.

### "Waarom heb ik geen telefoonnummer nodig?"

Omdat je identiteit puur cryptografisch is. In plaats van een telefoonnummer of
e-mailadres dat aan je echte naam is gekoppeld, identificeert je een
sleutelpaar dat op je apparaat is gegenereerd. Contacten voeg je toe
via QR-code, NFC of de tekstregel van je uitnodiging -- niet via een
telefoonboek. Dat betekent
meer privacy, omdat je messenger-account niet aan je reële identiteit
gebonden is.

### "Hoe vind ik mensen op Cleona?"

Cleona heeft bewust geen mogelijkheid om contacten op telefoonnummer of naam te zoeken -- dat zou
een privacy-probleem zijn. In plaats daarvan wissel je uitnodigingen rechtstreeks uit: via
QR-code, NFC of als tekstregel via een andere weg. Dat is als
visitekaartjes uitwisselen in plaats van opzoeken in een telefoonboek.

### "Werkt Cleona ook in het buitenland?"

Ja. Zolang je een internetverbinding hebt, werkt Cleona overal op
de wereld. Omdat er geen centrale server en geen vast adres is, laat zich
de dienst niet eenvoudig voor bepaalde landen uitschakelen. Hoe Cleona
blokkades bemoeilijkt, staat in het hoofdstuk "Beveiliging" onder "Anti-censuur". Een land
dat elk onbekend verkeer aan de grens blokkeert, kan Cleona echter ook
stoppen.

### "Is Cleona gratis?"

Ja. Cleona is gratis en zonder reclame te gebruiken. Omdat er geen centrale
server is, vallen er ook geen serverkosten voor de exploitatie. In de
instellingen onder "Steun Cleona" -> "Doneren" kun je de ontwikkeling
vrijwillig steunen.

### "Mijn bericht heeft maar één vinkje -- wat betekent dat?"

Het bericht is onderweg, maar je tegenpartij heeft de ontvangst nog niet
bevestigd -- meestal omdat hij op dit moment offline is. Dat is geen fout: het
bericht wacht tot 7 dagen in de postbus. Zodra hij het ophaalt, zie je
twee vinkjes. Een klok betekent dat nog geen route het bericht heeft vervoerd
-- het gaat vanzelf op weg zodra er een is; een waarschuwingsteken dat het
14 dagen lang geen route heeft gevonden en je het opnieuw
kunt versturen.

### "Waarom komen berichten laat aan op mijn iPhone?"

iOS laat apps niet permanent op de achtergrond draaien. Cleona wordt alleen zo
nu en dan kort gewekt; wanneer, bepaalt iOS. Het haalt dan alles op. Zodra je
de app opent, haalt Cleona op wat voor je bewaard is.

### "Kan ik van WhatsApp naar Cleona overstappen?"

Ja, maar je kunt je WhatsApp-chats niet overdragen. Cleona en WhatsApp
zijn fundamenteel verschillende systemen. Je moet je contacten afzonderlijk in Cleona
toevoegen. Het eenvoudigst gaat dat als je de tekstregel van je uitnodiging
aan je contacten stuurt. Elk verzoek dat zo aankomt, bevestig je
zelf onder "Verzoeken".

### "Kan ik Cleona op meerdere apparaten tegelijk gebruiken?"

Nog niet. Een tweede apparaat voor dezelfde identiteit komt met een
latere versie (hoofdstuk 11). Op meerdere apparaten kun je vandaag
verschillende identiteiten gebruiken.

### "Hoe krijg ik updates als de app store geblokkeerd is?"

Cleona kan updates rechtstreeks via het netwerk ophalen, zonder afhankelijk te zijn van een
app store, een website of een downloadserver. Als een ander apparaat in
het netwerk de nieuwste versie heeft, kan je apparaat de
update daarvandaan laden. De echtheid wordt door een digitale handtekening van de
ontwikkelaar gecontroleerd. Als alternatief kan een contact je de app per
uitnodigingslink of USB-stick doorgeven. Meer daarover in het hoofdstuk
"Software-updates".

---

## Hulp en contact

Als je vragen hebt of op een probleem stuit, vind je actuele
informatie op de Cleona-website en op GitHub. Omdat Cleona een gedecentraliseerd
project is, is er geen klassieke klantensupport -- maar een actieve
gemeenschap die graag helpt.

---

*Dit handboek beschrijft Cleona Chat versie 4.2. Afzonderlijke functies
kunnen in nieuwere versies wijzigen of uitgebreid worden.*
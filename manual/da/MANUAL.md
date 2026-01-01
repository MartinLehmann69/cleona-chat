# Cleona Chat -- Brugervejledning

Version 4.2 | Stand november 2026

---

## Indholdsfortegnelse

1. [Hvad er Cleona Chat?](#1-hvad-er-cleona-chat)
2. [Første skridt](#2-første-skridt)
3. [Kontakter](#3-kontakter)
4. [Beskeder](#4-beskeder)
5. [Grupper](#5-grupper)
6. [Offentlige kanaler](#6-offentlige-kanaler)
7. [Opkald](#7-opkald)
8. [Kalender](#8-kalender)
9. [Afstemninger](#9-afstemninger)
10. [Flere identiteter](#10-flere-identiteter)
11. [Flere enheder](#11-flere-enheder)
12. [Gendannelse](#12-gendannelse)
13. [Indstillinger](#13-indstillinger)
14. [Sikkerhed](#14-sikkerhed)
15. [Softwareopdateringer](#15-softwareopdateringer)
16. [Ofte stillede spørgsmål](#16-ofte-stillede-spørgsmål)

---

## 1. Hvad er Cleona Chat?

### Din messenger, dine data

Cleona Chat er en messenger, der fungerer helt uden central server. Dine
beskeder rejser fra din enhed til modpartens enhed -- uden omvej via et
firma, uden sky, uden datacenter. Hvor en anden enhed undervejs hjælper,
videresender den kun krypterede pakker. Intet firma kan læse, gemme eller
videregive dine beskeder, fordi der ganske enkelt ikke er noget firma imellem.

### Ingen konto, intet telefonnummer

Ved Cleona har du hverken brug for et telefonnummer eller en e-mailadresse for
at tilmelde dig. Din identitet består af et kryptografisk nøglepar, der
oprettes automatisk på din enhed ved første start. Det betyder: Ingen kan
finde dig via dit telefonnummer eller din e-mailadresse, medmindre du selv
giver dine kontaktoplysninger videre.

### Fremtidssikret kryptering

Cleona bruger såkaldt post-quantum-kryptering. Det betyder: Selv fremtidige
kvantecomputere kan ikke bryde dine beskeder. Du behøver ikke at forstå
detaljerne -- det eneste, der er vigtigt, er, at din kommunikation efter
gældende teknologi er bedst muligt beskyttet.

### Hvordan fungerer det uden server?

Cleonas netværk består kun af dets brugeres enheder. Hver enhed er en knude,
ingen knude er vigtigere end en anden, og hver kender kun sine naboer. Fire
ting gør dette netværk specielt:

- **Intet fast punkt.** I appen står der ingen serveradresse, og netværket
  afhænger ikke af nogen enkelt knude. Der er intet, man kan slukke for at
  lukke Cleona.
- **Øjeblikkeligt.** Din besked går afsted i det øjeblik, du sender den. Den
  venter ikke på et takt eller noget som helst andet.
- **Tildækning ved siden af.** Din enhed sender løbende små
  tildækningspakker, så man udefra ikke kan se, hvornår du virkelig skriver.
  Ingen besked afhænger af det -- tildækningen kører kun ved siden af.
- **Koder i stedet for navne.** Den, der videresender en besked, ser kun en
  kode, der skifter hver dag. Normalt kender ingen af dem både afsender og
  modtager på én gang; undtagelserne står i kapitel 14.

**Tre veje, alle på én gang.** Når du sender en besked, prøver Cleona ikke
én vej efter den anden, men alle egnede på én gang. Så snart din modpart
bekræfter modtagelsen, bliver de andre afbrudt.

1. **I samme netværk:** Hvis I er i samme Wi-Fi, går beskeden direkte over.
2. **Over de faste naboer:** På internettet giver din enhed beskeden videre
   til sin faste nabo. Den videresender den til din modparts faste naboer
   (op til tre på én gang), og en af dem leverer den.
3. **Postkasse:** Er din modpart offline, lægger Cleona den krypterede besked
   hos tre naboer. Den bliver der i op til 7 dage. Kommer din modpart
   online igen, henter han den.

**Hvordan kommer du ind i netværket?** I appen står der ingen serveradresse.
Din indgang får du fra din første kontakt: Hans invitation indeholder de
adresser, hvorigennem din enhed finder sine første naboer. I samme Wi-Fi
finder Cleona-enheder også hinanden selv. Fra da af lærer din enhed med hver
nabo flere at kende.

### Platforme

Cleona er tilgængelig til Android, iOS, macOS, Linux og Windows. På computere
og på Android ankommer beskeder og opkald inden for få sekunder. På iPhone
gælder det, mens appen er åben. Når den ikke er åben, vækker iOS den kun kort
af og til; hvornår, bestemmer iOS. Cleona henter så alt, hvad der er gemt til
dig, og viser en meddelelse med et tal på app-ikonet. Opkald når ikke en
iPhone, hvis app ikke er åben. Det er en regel fra Apple, ikke en fejl i
Cleona.

---

## 2. Første skridt

### Installér appen

**Android:**
1. Hent APK-filen fra Cleonas hjemmeside eller fra GitHub Releases.
2. Åbn filen på din telefon. Hvis det er nødvendigt, tillad installation fra
   ukendte kilder (Android spørger dig automatisk).
3. Tryk på "Installér", og vent, indtil installationen er færdig.

**iOS:**
1. Åbn TestFlight-invitationslinket på din iPhone.
2. Tryk på "Installér". TestFlight er Apples officielle måde at udlevere
   beta-apps på.
3. Efter installationen finder du Cleona på din hjemmeskærm.

**macOS:**
1. Hent DMG-filen fra Cleonas hjemmeside eller fra GitHub Releases.
2. Åbn DMG'en, og træk Cleona over i din programmappe.
3. Ved første start spørger macOS muligvis, om du vil åbne appen fra en
   identificeret udvikler -- bekræft dette.

**Linux (Ubuntu/Debian):**
1. Hent .deb-filen fra Cleonas hjemmeside eller fra GitHub Releases.
2. Installér med dobbeltklik eller i terminalen: `sudo dpkg -i cleona-chat-beta_VERSION_amd64.deb`
3. Start Cleona via programmenuen eller i terminalen med `cleona-chat-beta`.

**Linux (Fedora/openSUSE):**
1. Hent .rpm-filen fra Cleonas hjemmeside eller fra GitHub Releases.
2. Installér med: `sudo dnf install cleona-chat-beta-VERSION-1.x86_64.rpm`
3. Start Cleona via programmenuen eller i terminalen med `cleona-chat-beta`.

**Linux (alle distributioner -- AppImage):**
1. Hent .AppImage-filen fra Cleonas hjemmeside eller fra GitHub Releases.
2. Gør filen eksekverbar: Højreklik, egenskaber, eksekverbar, eller i
   terminalen: `chmod +x cleona-chat-beta-VERSION-x86_64.AppImage`
3. Start med dobbeltklik eller i terminalen: `./cleona-chat-beta-VERSION-x86_64.AppImage`

Pakkenavnene gælder for betaversionen, der i øjeblikket er den eneste
offentliggjorte udgave; de hedder `cleona-chat-beta`.

**Windows:**
1. Hent installatøren fra Cleonas hjemmeside eller fra GitHub Releases.
2. Kør installationsfilen, og følg anvisningerne.
3. Start Cleona via startmenuen eller skrivebordsgenvejen.

### Opret identitet

Ved første start opretter Cleona automatisk en ny identitet til dig. Du kan
give dig selv et visningsnavn -- det er det navn, dine kontakter ser. Dette
navn kan altid ændres.

### Skriv seed-phrase ned -- det vigtigste overhovedet

Efter oprettelsen af din identitet viser Cleona dig 24 ord. Det er din
**seed-phrase** -- din personlige gendannelsesnøgle.

**Skriv disse 24 ord ned på papir, og opbevar dem sikkert.**

Hvorfor er det så vigtigt?

- Hvis din telefon går i stykker, forsvinder eller bliver stjålet, kan du
  med disse 24 ord gendanne hele din identitet på en ny enhed.
- Uden seed-phrasen er der ingen vej tilbage. Der er ingen "glemt
  adgangskode"-knap og ingen support, der kunne give dig din konto tilbage
  -- for der er slet ingen konto på en server. Også dine kontakter kan ikke
  gendanne din identitet, uanset hvor mange de er. En anden enhed med samme
  identitet kommer med en senere version (se kapitel 11).
- Giv aldrig seed-phrasen videre til andre. Den, der kender disse ord, kan
  udgive sig for at være dig.

Du finder de 24 ord senere i indstillingerne under "Sikkerhedskopi" ->
"Vis gendannelsesfrase", hvis du vil aflæse dem én gang til. På Android
bekræfter du det med din skærmlås.

### Tilføj den første kontakt

For at chatte med nogen skal du først tilføje personen som kontakt. Til det
er der flere veje -- alle forklares i næste afsnit.

---

## 3. Kontakter

### Din invitation

Kontakter opstår ved Cleona kun via en invitation. Din invitation er der fra
første start -- også uden internet og før din enhed overhovedet har fundet
en nabo. Du finder den på din identitets-detaljeside (tryk på dit eget navn
i den øverste linje).

Invitationen findes i to former, der indeholder præcis det samme:

- som **QR-kode**, når din modpart står ved siden af dig, og
- som **tekstlinje**, som du sender via e-mail, SMS eller en anden
  messenger.

Invitationen indeholder intet telefonnummer og intet navn fra et register.
Den indeholder dine offentlige nøgler og de adresser, hvorigennem din
modpart når dig og dine naboer. For en, der lige har installeret Cleona, er
din invitation derfor også indgangen til netværket.

### Scan QR-kode (anbefalet)

Hvis I mødes personligt:

1. Du viser din modpart QR-koden fra din invitation.
2. Din modpart trykker på plus-knappen, vælger "Scan QR-kode", og holder
   kameraet mod din skærm. Det virker også med et webkamera på en computer.
3. Anmodningen går til dig og bliver **automatisk accepteret** -- for du
   har netop selv vist koden.

En QR-kode gælder kun én gang: Den første gyldige anmodning bliver
accepteret, derefter er invitationen opbrugt. QR-koden er den sikreste metode,
fordi I netop derved ved præcis, hvem I udveksler kontakten med.

### NFC (hold telefoner mod hinanden)

Hvis begge enheder understøtter NFC:

1. Åbn begge funktionen "Tilføj kontakt".
2. Hold jeres telefoner ryg mod ryg.
3. Invitationen overføres og accepteres automatisk.

NFC tilbyder ligesom QR-koden en høj sikkerhed, fordi udvekslingen kun
fungerer, når I står fysisk ved siden af hinanden.

### Send tekstlinje

Hvis I ikke kan mødes:

1. Åbn din invitation, og kopier tekstlinjen.
2. Send den til den person, der skal tilføje dig -- via mail, SMS eller en
   anden messenger.
3. Den anden person indsætter linjen i Cleona i dialogen "Tilføj kontakt".
4. Anmodningen dukker op hos dig under **"Anmodninger"**. Her bliver den
   **ikke** automatisk accepteret: Du beslutter selv, for du kan ikke vide,
   hvem der har læst linjen undervejs.

### Acceptér kontaktanmodninger

En indgående anmodning opretter endnu ikke en kontakt. Den stiller dig et
spørgsmål og dukker op i fanebladet **"Anmodninger"**. Der ser du navnet og
verifikationsniveauet og kan vælge:

- **Acceptér** -- først nu bliver personen til din kontakt.
- **Afvis** -- anmodningen kasseres.
- **Blokér** -- personen kan ikke sende dig flere anmodninger.

### Brug aldrig som fast nabo

I en kontakts menu finder du kontakten **"Brug aldrig som fast nabo"**
(standard: fra). Er den slået til, videresender denne kontakt ingen beskeder
for dig og får derfor heller ikke at vide, hvornår du sender eller modtager
beskeder. Det er tænkt til det tilfælde, at truslen kommer fra dit eget
omgivende miljø.

Fra ukendte (hverken kontakt eller medlem af en fælles gruppe) lader
Cleona -- udover en sådan anmodning -- intet komme igennem -- ingen
besked, intet opkald, ingen fil. Og selv anmodningen når kun frem,
hvis afsenderen først har løst en lille regneopgave. Det gør massespam dyrt.

### Verifikationsniveauer

Cleona viser dig, hvor sikkert en kontakts identitet er bekræftet:

| Niveau | Betydning |
|-------|-----------|
| Ikke verifieret | I er forbundet, men intet bekræfter, at det virkelig er den rigtige person bag. |
| Set | Nøgleudvekslingen var vellykket, I kan kommunikere krypteret. |
| Verificeret | I har mødtes personligt og forbundet via kamera-scan eller NFC. |
| Betroet | Du har udtrykkeligt markeret denne kontakt som troværdig. |

"Verificeret" findes kun ved personlig udveksling. En invitation, der kom via
en chat eller mail, når aldrig dette niveau -- selv når den indeholder de
samme data.

Ændres en kontakts nøgler uden varsel, sætter Cleona den tilbage til "Ikke
verificeret". Det beskytter dig mod, at nogen ubemærket udgiver sig for at
være din kontakt.

---
## 4. Beskeder

### Send og modtag tekst

Skriv bare din besked i indtastningsfeltet nederst, og tryk på Enter eller
send-knappen. Din besked bliver automatisk krypteret, før den forlader din
enhed.

Indgående beskeder vises i chat-historikken.

### Hvad tegnene på din besked betyder

| Tegn | Betydning |
|---------|-----------|
| Ur | Beskeden er oprettet, men endnu har ingen vej båret den. |
| én hake | Beskeden er på vej. Det gælder også, mens den venter på din modpart i postkassen. |
| To hager | Leveret: Din modparts enhed har bekræftet modtagelsen. |
| Advarselstegn | I 14 dage har ingen vej båret beskeden. Tryk på den for at sende den igen. |

**Offline er ikke en fejl.** Er din modpart ikke nåelig, forbliver beskeden
ved én hake, indtil den bliver hentet -- den er ikke tabt. Har din egen
enhed ikke forbindelse, forbliver beskeden ved uret og går afsted af sig
selv, så snart der igen er en vej. Advarselstegnet vises først, når den i
14 dage ikke har fundet nogen vej; så kan du sende den igen.

Det gælder også en iPhone, hvis app ikke er åben: Beskeden venter i
postkassen, indtil iOS vækker appen kort, eller indtil din modpart åbner den.
Det kan tage længre tid end på andre enheder.

To hager findes kun, når modtageren selv bekræfter modtagelsen. Denne
kvittering er krypteret og underskrevet -- ingen undervejs kan forfalske den
for at lade som om, beskeden er leveret.

### Send billeder, videoer og filer

Du har flere muligheder:

- **Binders-ikon** i indtastningsfeltet: Tryk på det for at vælge en fil, et
  billede eller en video fra dit galleri eller dit filsystem.
- **Træk og slip** (skrivebord): Træk en fil direkte ind i chat-vinduet.
- **Indsæt fra udklipsholder** (skrivebord): Kopier et billede, og indsæt
  det i chatten.

Små filer (under 256 KB) rejser direkte med i beskeden. Større filer bliver
delt i stykker og forsynet med fejlkorrektion, så enkelte tabte stykker ikke
gør nogen forskel. Er I begge online, streames de over en nabo; ellers
lægges de hos enheder, der konstant er nåelige, indtil din modpart henter dem.

Fra 256 KB spørger Cleona dig pr. fil, før den sendes: En stor fil kan ikke
tage samme vej som dine beskeder. Indholdet forbliver krypteret, og din
modpart får ikke din internetadresse at vide. Men overførslen er udefra
synlig som en hændelse, og en fremmed enhed, der videresender eller
opbevarer den, ser, hvem der uploader, og hvem der henter. Dit samtykke
gælder kun for denne ene fil.

### Lydmeddelelser

1. Hold mikrofon-knappen i indtastningsfeltet nede.
2. Tal din besked.
3. Slip knappen for at sende beskeden.

Hvis talegenkendelse er aktiveret på din enhed (se indstillinger), bliver
din lydmeddelelse automatisk transskriberet som tekst. Din modpart ser så
både optagelsen og den transskriberede tekst.

### Besvare beskeder (citere)

For at svare på en bestemt besked:

1. Åbn tre-punkts-menuen ved siden af beskeden.
2. Vælg "Svar".
3. Over indtastningsfeltet vises et banner med den citerede besked.
4. Skriv dit svar, og send det.

Den citerede besked vises i dit svar, så sammenhængen er tydelig.

### Redigere og slette beskeder

- **Rediger:** Tre-punkts-menu på beskeden, derefter "Rediger". Ændr teksten,
  og send den igen. Din modpart ser, at beskeden er blevet redigeret.
  Redigering er mulig inden for 15 minutter efter afsendelsen.
- **Slet:** Tre-punkts-menu på beskeden, derefter "Slet". Beskeden fjernes
  hos dig og din modpart. Du kan altid slette dine egne beskeder -- der er
  intet tidsvindue for sletning.

### Emoji-reaktioner

I stedet for at skrive et svar kan du reagere på en besked med en emoji:

1. Åbn tre-punkts-menuen, eller hold beskeden længe nede.
2. Vælg en emoji fra hurtigvælgelsen, eller åbn emoji-vælgeren for det
   fulde udvalg.
3. Din reaktion vises under beskeden.

### Kopier tekst

Via tre-punkts-menuen på en besked kan du kopiere beskedteksten til
udklipsholderen.

### Søge i beskeder

Øverst i chat-vinduet finder du søgefunktionen. Indtast et søgeord, og Cleona
viser dig alle træf i den aktuelle chat. Med piletasterne kan du hoppe frem og
tilbage mellem træffene.

På startsiden findes der desuden et søgefilter på tværs af faneblade, hvormed
du kan gennemsøge alle samtaler efter et ord.

### Link-forhåndsvisning

Når du sender et link, opretter Cleona automatisk en forhåndsvisning (titel,
beskrivelse, miniaturebillede). Denne forhåndsvisning oprettes på din enhed og
medsendes -- din modpart behøver ikke at oprette forbindelse til den
henviste hjemmeside.

Hvad et tryk på et modtaget link gør, indstiller du i indstillingerne under
"Åbn links": "Normal", "Foretræk privat vindue" (hvor enheden ikke kan
åbne et privat vindue, åbner linket normalt) eller "Spørg hver gang".

---

## 5. Grupper

### Opret gruppe

1. Skift til fanebladet "Grupper".
2. Tryk på plus-knappen.
3. Giv gruppen et navn.
4. Vælg de kontakter, du vil invitere.
5. Tryk på "Opret".

De inviterede kontakter modtager en meddelelse og kan deltage i gruppen.

### Hvordan gruppebeskeder er beskyttet

I en gruppe med op til 16 medlemmer sender Cleona hver besked til hvert
medlem enkeltvis -- hver gang kun krypteret for netop dette medlem, som om
du havde skrevet en egen besked til hver af dem. Hagerne på en gruppebesked
viser status hos det medlem, hvor den er mindst langt.

Vokser gruppen over 16 medlemmer, bruger den en fælles nøgle. Den ændrer
sig hver dag og trækkes på ny, når et medlem forlader gruppen eller
fjernes; et nyt medlem læser først fra sit indtrædelsestidspunkt. Der viser
hagerne ikke længere status for hvert medlem, men at beskeden er lagt i
netværket. Falder gruppen til 12 eller færre medlemmer, går den tilbage til
enkeltforsendelse.

### Billeder i grupper og kanaler

I indstillingerne for en gruppe eller en kanal fastlægger du med "Indlæs
altid billeder", om billeder hentes straks, eller først når du trykker på
et af dem.

### Inviter medlemmer

Også efter oprettelsen kan du invitere flere kontakter:

1. Åbn gruppeinfo (tre-punkts-menu i gruppeoversigten eller øverste linje
   i gruppe-chatten).
2. Tryk på "Inviter".
3. Vælg de kontakter, du vil tilføje.

### Roller

Hver gruppe har tre roller:

- **Ejer (Owner):** Har den fulde kontrol. Kan tilføje og fjerne medlemmer,
  udpege admins og administrere gruppen. Ejeren kan også overføre sin
  status til et andet medlem.
- **Admin:** Kan fjerne medlemmer og hjælpe med administrationen.
- **Medlem:** Kan læse og skrive beskeder.

### Forlad gruppe

1. Åbn tre-punkts-menuen i gruppeoversigten.
2. Vælg "Forlad".
3. Bekræft din beslutning.

Når du forlader en gruppe, forbliver dine tidligere beskeder synlige for de
andre medlemmer.

---

## 6. Offentlige kanaler

### Hvad er kanaler?

Kanaler er offentlige diskussionsfora inden for Cleonas netværk. I
modsætning til grupper kan alle her læse med uden at skulle inviteres. Kun
ejeren og admins kan udgive indlæg -- abonnenter læser med.

### Find og tilmeld kanaler

1. Skift til fanebladet "Kanaler".
2. Åbn fanebladet "Søg".
3. Gennemsøg de tilgængelige kanaler efter navn eller emne.
4. Tryk på en kanal og derefter på "Abonner".

Kanaler kan filtreres efter sprog. Nogle kanaler er markeret som "Ikke
ungdomsegnet" -- de er kun synlige, når du i din profil har bekræftet, at du
er over 18.

### Opret egen kanal

1. Skift til fanebladet "Kanaler".
2. Tryk på plus-knappen.
3. Indtast et kanalnavn (skal være entydigt i hele netværket).
4. Vælg sproget, og om kanalen skal være offentlig eller privat.
5. Valgfrit: Tilføj en beskrivelse og et billede.
6. Tryk på "Opret".

Ved offentlige kanaler kan du fastlægge, om indholdet klassificeres som "Ikke
ungdomsegnet".

### Anmeld indhold

Hvis du i en offentlig kanal lægger mærke til upassende indhold, kan du
anmelde det. Cleona bruger et decentralt modereringssystem: Anmeldelser
bedømmes af tilfældigt udvalgte medlemmer af netværket (en slags
"nævningedomstol"). Konstateres der en overtrædelse, får kanalen en
advarsel. Ved gentagne overtrædelser nedgradueres den i søgeindekset eller
blokeres.

### System-kanaler

Cleona har to indbyggede system-kanaler:

- **Bug Log:** Når Cleona genkender en fejl, spørger den dig, om du vil sende
  en fejlrapport; først ser du præcis, hvad der offentliggøres. Disse
  rapporter lander i bug-log-kanalen, hvor de kan ses af fællesskabet. En
  rapport bærer intet navn og intet indhold fra dine samtaler, men et
  pseudonym. I betaversionen nævner den desuden din bruger-ID, så
  udviklerne kan følge op. Du kan også sende en log-rapport manuelt (med
  forhåndsvisningsdialog og udtrykkeligt samtykke).
- **Feature Requests:** Her kan brugere indsende funktionsønsker og stemme
  om eksisterende forslag. Forslagene sorteres efter stemmer.

Hver computer opbevarer op til 25 MB pr. system-kanal, hver mobiltelefon op
til 5 MB; er det fuldt, går det ældste først -- aldrig det, du selv
allerede har set.

---
## 7. Opkald

### Start taleopkald

1. Åbn chatten med den kontakt, du vil ringe til.
2. Tryk på telefon-symbolet i den øverste linje.
3. Vent, indtil din modpart tager opkaldet.

Under samtalen ser du en tidslinje, samtalesvarigheden, og har adgang til
lydløs og højtaler.

For at lægge på trykker du på den røde læg-på-knap.

Ser du "Ikke tilgængelig", kan din modparts enhed ikke nås lige nu, for
eksempel en iPhone, hvis app ikke er åben. Skriv en besked i stedet.

### Start videoopkald

1. Åbn chatten med kontakten.
2. Tryk på kamera-symbolet i den øverste linje.
3. Dit videobillede vises i et lille vindue, din modparts billede i det
   store område.

Du kan under samtalen skifte mellem for- og bagkamera.

### Indgående opkald

Når nogen ringer til dig, vises et meddelelsesvindue med navnet på den, der
ringer. Du kan:

- **Svar** -- samtalen begynder.
- **Afvis** -- den, der ringer, får besked.

Er du lige nu i en samtale, ringer et nyt opkald ikke; i stedet får du en
besked "Ubesvaret opkald". Det samme gælder et gruppeopkald, du ikke har
taget -- beskeden står da i gruppechatten.

Ringer nogen til en af dine identiteter, der lige nu ikke vises, ringer det
alligevel; opkaldsskærmen nævner, hvilken af dine identiteter der ringes til.

På iPhone ringer det kun, mens appen er åben. Den, der ringer til dig, mens
den ikke er åben, ser efter 10 sekunder "Ikke tilgængelig". Så snart du åbner
appen, finder du en besked om det ubesvarede opkald.

### Gruppeopkald

Du kan også føre gruppeopkald, hvor flere personer deltager på samme tid.
Opkaldet organiseres via et intelligent videresendelsestræ, så ikke hver
deltager behøver at være direkte forbundet med hver anden. Alle samtaler er
krypterede hele vejen.

Hvert gruppemedlem kan starte et gruppeopkald. To deltagere, der ikke er
kontakter for hinanden, ser aldrig hinandens internetadresse: Deres lyd og
billede løber over en deltager, der er kontakt med begge. Findes der ingen
sådan, er de to ikke forbundet, og feltet siger "Ingen fælles kontakt i
opkaldet". Er en videresendelse overbelastet, er lyden der stadig, og
videoen falder bort for det par.

### Kryptering ved opkald

Alle opkald krypteres med engangsnøgler, der kun eksisterer for samtalens
varighed. Efter op at lægge slettes disse nøgler omgående. Ingen kan
efterfølgende afkryptere en tidligere samtale.

Ærligt talt: Opkald foregår, hvor det er muligt, direkte mellem enhederne,
for selv en lille forsinkelse forstyrrer, når man taler. I modsætning til ved
beskeder kan din internetudbyder derfor ved et opkald se, med hvilken
internetadresse du er forbundet. Hvad I siger, ser han ikke.

Ved et opkald ser din kontakt også din internetadresse. Vil du ikke have
det ved en kontakt, slår du i vedkommendes menu "Tillad opkald" fra
(standard: til). Slår du den fra senere, forbliver en allerede set adresse
kendt for vedkommende.

---

## 8. Kalender

Cleona indeholder en indbygget kalender, der fungerer krypteret og helt
decentraliseret -- uden sky-tjeneste.

### Visninger

Kalenderen tilbyder fem visninger: Dag, uge, måned, år og en
opgave-visning. Skift mellem dem via fanebladene øverst på
kalender-skærmen.

### Opret aftaler

Tryk på et tidsrum, eller brug tilføj-knappen for at oprette en ny aftale.
Du kan indtaste titel, dato, klokkeslæt, sted og noter. Aftaler gemmes
krypteret på din enhed.

### Tilbagevendende aftaler

Aftaler kan gentage sig dagligt, ugentligt, månedligt eller årligt. Du kan
tilpasse mønsteret (f.eks. hver anden tirsdag, hver første i måneden) og
fastlægge en slutdato eller et antal gentagelser.

### Inviter kontakter

Når du opretter eller redigerer en aftale, kan du invitere dine
Cleona-kontakter. De modtager en krypteret kalenderinvitation og kan svare
med accept, afslag eller måske. Ændringer i aftalen sendes automatisk til
alle inviterede.

### Fri/optaget-visning

Du kan dele din tilgængelighed med kontakter uden at røbe aftaledetaljer.
Der findes tre privatlivsniveauer: fulde detaljer, kun tidsblokke eller
skjult. Du kan sætte en standard og overskrive den pr. kontakt.

### Påmindelser

Aftaler kan have påmindelser, der udløser en systemmeddelelse før
aftalens begyndelse. Du kan om nødvendigt lade påmindelser sove.

### Ekstern kalender-synk

Cleona kan synkronisere med eksterne kalendertjenester:

- **CalDAV** -- Forbind dig med enhver CalDAV-kompatibel server (Nextcloud,
  Radicale osv.).
- **Google Kalender** -- Synkronisering via Google Calendar API med sikker
  OAuth2-autentificering.
- **Lokal CalDAV-server** -- Cleona kan starte en lokal CalDAV-server på
  din enhed, så skrivebords-kalenderapps (Thunderbird, Outlook,
  Apple Kalender, Evolution) kan synkronisere med din Cleona-kalender.
- **Android-systemkalender** -- Aftaler fra Cleona kan overføres til den
  indbyggede kalender-app på din Android-enhed.
- **ICS-filer** -- Importér og eksportér aftaler i
  standard-iCalendar-format.

### PDF-eksport

Du kan udskrive eller eksportere hver kalendervisning (dag, uge, måned, år)
som et PDF-dokument.

---

## 9. Afstemninger

Du kan oprette afstemninger i enhver chat eller gruppe for at indsamle
meninger eller planlægge aftaler.

### Afstemningstyper

Cleona understøtter fem slags afstemninger:

- **Enkelvalg** -- Deltagerne vælger én mulighed.
- **Flervalg** -- Deltagerne kan vælge flere muligheder.
- **Aftaleafstemning** -- Find en aftale, der passer alle. Hver
  deltager markerer aftaler som ledige, måske eller ikke ledige.
- **Skala** -- Bedøm noget på en numerisk skala (f.eks. 1 til 5).
- **Fritekst** -- Deltagerne skriver deres eget svar.

### Opret afstemning

Åbn en chat, og tryk på afstemnings-symbolet (eller brug
vedhæft-menuen). Vælg afstemningstypen, formuler dit spørgsmål og
mulighederne, og send afstemningen. Den vises som en besked i chatten.

### Stemmeafgivelse

Tryk på en afstemning for at afgive din stemme. Du kan til enhver tid ændre
eller trække din stemme tilbage.

### Anonym afstemning

Afstemninger kan konfigureres til anonym afstemning. Når det er aktiveret,
er stemmerne kryptografisk anonyme -- ingen, ikke engang
afstemnings-ophavsmanden, kan se, hvem der stemte for hvad. Antallet af
stemmer forbliver dog synligt.

### Aftaleafstemning til kalenderen

Når en aftaleafstemning er afsluttet, kan vinder-aftalen med et tryk
omdannes direkte til en kalenderpost.

---
## 10. Flere identiteter

### Hvorfor flere identiteter?

Forestil dig, du vil adskille dit arbejdsliv og dit privatliv -- ligesom
med to forskellige telefonnumre, men uden en anden telefon. I Cleona kan du
bruge flere identiteter på én enhed. Hver identitet har sit eget navn, sit
eget profilbillede, egne kontakter og egne samtaler.

### Opret ny identitet

1. I den øverste linje ser du din aktuelle identitet som et faneblad.
2. Tryk på plus-tegnet (+) til højre for dine identitets-faneblade.
3. Indtast et navn til den nye identitet.
4. Færdig -- den nye identitet er straks aktiv.

### Skift mellem identiteter

Tryk bare på identitets-fanebladet i den øverste linje. Skiftet er
øjeblikkeligt -- ingen ventetid, ingen genindlæsning.

### Alle kører på samme tid

Et vigtigt punkt: Alle dine identiteter er aktive på samme tid. Selv
når du lige nu vises som "Arbejde", modtager din "Privat"-
identitet stadig beskeder. Du går ikke glip af noget, uanset hvilken
identitet du lige har valgt.

### Identitets-detaljeside

Når du trykker på fanebladet for din netop aktive identitet, åbnes
detaljesiden. Her kan du:

- Vise din QR-kode til kontakter.
- Ændre eller fjerne dit profilbillede.
- Tilføje en profilbeskrivelse.
- Ændre dit visningsnavn.
- Vælge et design (skin) til denne identitet.
- Slette identiteten, hvis du ikke længere har brug for den.

### Slet identitet

Når du sletter en identitet, bliver dine kontakter underrettet om det.
Identiteten og alle tilhørende data fjernes fra din enhed. Denne proces kan
ikke fortrydes.

---

## 11. Flere enheder

### Én identitet, én enhed -- indtil videre

En identitet kører i dag på én enhed. En anden enhed til samme identitet
kommer med en senere version; i indstillingerne under "Enheder" ->
"Administrer enheder" står "Par flere enheder" derfor endnu som "Endnu
ikke tilgængeligt".

Når det kommer, gælder: Alle enheder er ligestillede, der er ingen
hovedenhed. En yderligere enhed opretter du med dine 24 ord, og én af dine
hidtidige enheder skal give samtykke. Højst 5 enheder.

Indtaster du i dag dine 24 ord på en ny enhed, flytter du: Identiteten
gendannes på den nye enhed, og din hidtidige enhed fjerner den efterfølgende
hos sig selv (se kapitel 12).

På flere enheder kan du i dag bruge forskellige identiteter (kapitel 10).

### Roter nøgler for identiteten

Formoder du, at nogen er kommet til dine nøgler, kan du under "Administrer
enheder" -> "Roter nøgler" skabe nye nøgler. Dine kontakter bliver
underrettet, dine åbne invitationer bliver tilbagekaldt. Vigtigt: Derefter
gendanner de 24 ord alene kun de gamle nøgler. Opret derfor direkte efter
en ny gendannelsespakke; gendanne kan du derefter kun sammen med denne
pakke.

---

## 12. Gendannelse

### Brug seed-phrase

Når du mister din enhed eller indstiller en ny:

1. Installér Cleona på den nye enhed.
2. Vælg "Gendan" ved start.
3. Indtast dine 24 ord.
4. Cleona genskaber derfra alle dine identiteter -- med samme
   nøgler som før. For dine kontakter er du det samme menneske.

### Hvad kommer tilbage -- og hvad der ikke gør

Din identitet sidder i de 24 ord, dine kontakter og din historik gør
ikke. Tilbage kommer din netværksadgang via **gendannelsespakken**: Din
enhed lægger en lille, krypteret pakke i netværket. Kun dine 24 ord kan
finde og åbne den. I den står, hvad din nye enhed har brug for, for at nå
dine kontakter igen, og hvad der i mellemtiden lå til dig i netværket.
Til det behøver ingen kontakt at være online.

Den hidtidige chathistorik bringer en gendannelse ikke tilbage.

Gendannelsespakken lever i 7 dage og fornyes af din enhed, så længe den
kører; i indstillingerne ser du, indtil hvornår den gælder. Har ingen af
dine enheder kørt i mere end 7 dage, er den udløbet. Så gendanner de 24
ord din identitet stadig, men dine kontakter må du invitere på ny; hvad
der i mellemtiden lå til dig i netværket, er tabt.

### Gendannelse betyder at flytte

Finder din hidtidige enhed senere ud af, at identiteten er gendannet et
andet sted, fjerner den den hos sig -- med dens historik. Derfor: Den, der
har dine 24 ord, kan på denne måde hente din identitet fra din enhed.
Indtil alle kontakter er der igen, påmindes du af appen; med "Fuldfør og
forny nøgler" afslutter du selv gendannelsen.

### Hvad ingen kan gendanne

Det er vigtigt, og derfor siger vi det tydeligt:

- **Ingen uden for dig kan gendanne din identitet.** Hverken
  udvikleren, en support eller dine kontakter -- uanset hvor
  mange de er. Der findes ingen masternøgle og ingen del af din
  nøgle, der ville være deponeret hos andre.
- **Har du mistet de 24 ord og har ingen enhed tilbage, er din identitet
  tabt.** Så er det eneste at oprette en ny og invitere dine kontakter på
  ny.

Den bedste beskyttelse: Skriv de 24 ord ned på papir, og opbevar dem sikkert.

---
## 13. Indstillinger

Indstillingerne når du via tandhjuls-symbolet i øverste højre
hjørne.

### Meddelelser og ringetoner

- Vælg mellem seks forskellige ringetoner til indgående opkald.
- Indstil en beskedtone.
- På Android-enheder kan du derudover aktivere eller deaktivere vibration.
- **"Slå lyden fra for alt"** lader på denne enhed ingen besked længere
  ringe, vibrere eller melde sig -- for alle identiteter. Opkald ringer
  stadig.
- **"Stille timer"** fastlægger du pr. identitet med fra/til. I denne tid
  ringer, vibrerer og melder ingen besked fra denne identitet sig;
  beskederne kommer alligevel frem.
- **"Notifikationer uden indhold"** (standard: fra) viser kun, at en
  besked, invitation eller påmindelse er ankommet -- uden afsender, navn
  og tekst. Opkald viser stadig navnet.
- Hvad der efter start ankommer på én gang, melder Cleona i en samlet
  meddelelse ("5 nye beskeder i 2 samtaler"); alt senere enkelt. Et tryk på
  en beskedmeddelelse åbner samtalen, også i en anden identitet.

### Designs (skins)

Cleona tilbyder ti forskellige designs: Teal, Ocean, Sunset, Forest,
Amethyst, Fire, Storm, Slate, Gold og Contrast. Contrast-designet opfylder
det højeste tilgængelighedsniveau (WCAG AAA) og er især let at læse ved
nedsat syn.

Hver identitet kan have sit eget design. Du ændrer designet på
identitets-detaljesiden (tryk på det aktive identitets-faneblad).

Derudover kan du i indstillingerne under "Udseende" skifte mellem
lyst, mørkt og system-tema.

### Skift sprog

Cleona er tilgængelig på 34 sprog, herunder også sprog med
højre-mod-venstre-skrift (f.eks. arabisk, hebraisk). Ændr sproget i
indstillingerne under "Sprog".

### Medie-arkivering

Hvis du derhjemme har et netværkslager (NAS) eller en delt mappe,
kan Cleona automatisk udlægge dine medier dertil. Understøttet
er SMB, SFTP, FTPS og WebDAV.

Sådan fungerer den trinvise lagring:
- De første 30 dage: Alt forbliver på din enhed.
- Efter 30 dage: Et miniaturebillede forbliver på enheden, originalen
  arkiveres.
- Efter 90 dage: Kun et lille miniaturebillede forbliver på enheden.
- Efter et år: Kun en pladsholder forbliver, originalen ligger sikkert
  i arkivet.

Du kan til enhver tid trykke på et arkiveret medie for at hente det tilbage
-- forudsat at du er forbundet med dit hjemmenetværk. Især vigtige
medier kan fastgøres, så de aldrig udlægges.

Under "Lagerbudget" fastlægger du, hvor mange MB medier der forbliver på
enheden (standard: 100 MB på mobiltelefonen, 2 GB på computeren). Er det
fuldt, arkiveres det ældste medie, der ikke er fastgjort, først. Slettet
bliver en original kun, når den ligger sikkert i arkivet -- tekstbeskeder
forbliver altid bevarede.

### Transskription til lydmeddelelser

Når aktiveret, bliver dine lydmeddelelser lokalt på din enhed
omformet til tekst (med open source-modellen Whisper). Den transskriberede
tekst sendes sammen med optagelsen til din modpart. Transskriptionen
sker helt på din enhed -- ingen data går til eksterne tjenester.

Hvilken model (tiny, base, small) der downloades, indstiller du én gang
for enheden; sproget (automatisk eller fast) pr. identitet.

### Auto-download

Du kan indstille, fra hvilken størrelse medier skal hentes
automatisk. Således kan du f.eks. lade billeder hente automatisk, men
ved store videoer selv tage stilling.

### Enheder

Under "Enheder" -> "Administrer enheder" ser du denne enhed. At parre en
yderligere enhed kommer med en senere version (kapitel 11).

### Netværk

Cleona har ikke brug for netværks-indstillinger for at fungere. Der findes
tre netværkskontakter:

- **Port-frigivelse på routeren** (standard: til). Cleona beder din egen
  router om at åbne en dør for Cleona. Lykkes det, er din enhed bedre
  nåelig for andre og hjælper netværket. Cleona taler her kun med din
  router, ikke med internettet.
- **Offentlige adresse-indgange** (standard: til). Har din enhed stadig
  for få naboer, slår den op i et offentligt register (Nostr) efter
  yderligere indgangspunkter, og er den selv godt nåelig, indtager den sig
  der. Indgangen indeholder en adresse, intet navn og ingen kontakt.
  Slår du den fra, finder din enhed naboer kun via invitationer,
  det lokale netværk og de naboer, den allerede kender.
- **Færre tildækningspakker i Wi-Fi** (standard: fra). I Wi-Fi eller på
  kabel kan du slå de tomme tildækningspakker fra. Så er det dog der igen
  at se, hvornår du skriver. I mobildata findes denne kontakt ikke -- der
  sender Cleona alligevel kun én tildækningspakke i minuttet.

Tildækningsstrømmen som helhed kan man ikke slå fra. Det er
meningen: Kun når den altid kører, siger din enheds aktivitet intet om,
hvad enten du lige nu skriver.

Over de tre kontakter står **Datasparetilstanden**: I mobildata anbefaler
Cleona den, men slår den aldrig til selv. Den sparer data, til gengæld er
din enhed udefra lettere at genkende.

Derunder indstiller du **"Cache til andres medier"**: Din enhed opbevarer
krypterede dele af andres medier i op til 7 dage, så de når frem til deres
modtagere (standard: 100 MB på mobiltelefonen, 1 GB på computeren). En
mindre størrelse frigiver pladsen straks -- de ældste dele først.

---

## 14. Sikkerhed

### Hvad betyder post-quantum-kryptering?

Dagens kryptering bygger på matematiske problemer, der for almindelige
computere er ekstremt vanskelige at løse. Kvante-computere kunne i
fremtiden løse nogle af disse problemer hurtigt. Post-quantum-kryptering
anvender yderligere metoder, der også holder stand til kvante-computere.

Cleona kombinerer begge tilgange: klassisk kryptering for
pålidelighed og post-quantum-metoder for fremtidssikkerhed. Således er du
mod dagens og fremtidige trusler beskyttet på samme tid.

For hver enkelt besked genereres en egen nøgle. Selv hvis en
angriber ville bryde nøglen til én besked, kunne han med den ikke læse
nogen anden besked.

### Hvorfor ingen server er sikrere

Ved gængse messengere kører dine beskeder via udbyderens
servere. Selv om de måske er krypterede der: Udbyderen har
adgang til metadata (hvem kommunikerer hvornår med hvem, hvor ofte, hvorfra)
og skal under omstændigheder udlevere dem efter dommerkendelse.

Ved Cleona findes der intet sådant centralt punkt. Der er intet sted, hvor
alle metadata samles, og intet register, hvori man kunne slå op, hvem du
er, eller hvem du kender.

### Hvem ser, at du skriver med nogen?

Kryptering beskytter, **hvad** du skriver. Ligeså vigtigt er det, at
ingen enkelt observatør får at vide, **med hvem** og **hvornår** du skriver.
Til det sørger Cleona således:

- **På internettet aldrig direkte.** Hvis din enhed sendte en besked direkte
  til din modparts internetadresse, kunne din udbyder se, hvem du
  skriver med. Derfor går en besked på internettet altid via jeres
  faste naboer: din og din modparts.
- **Naboer, du stoler på.** Dine faste naboer er, hvor det er muligt,
  enheder fra dine egne kontakter -- op til tre, der lige nu er
  nåelige udefra. Falder en ud, rykker en anden kontakt ind. En
  kontakt kan ikke købes med servere; en tilfældig knude i
  netværket kan. Har du endnu ingen nåelig kontakt, tager Cleona en
  anden nabo. Din invitation nævner aldrig nogen af dine kontakter, så
  at ingen via dem får at vide en vens adresse.
- **Koder i stedet for navne.** Naboerne ser ingen navne og ingen
  identifikationer, men kun en kode. Den gælder for præcis jer to, i én
  retning, for én dag -- næste dag er det en anden. Din nabo ved,
  hvorfra pakken kommer, men ikke, hvorhen den til sidst går. Din
  modparts nabo ved, hvorhen den går, men ikke, hvorfra den kom. Normalt
  ser ingen undervejs begge ender.
- **Tildækningsstrømmen.** Din enhed sender løbende, i ujævne
  mellemrum, tildækningspakker til sine naboer. De er lige så store som
  ægte pakker, går over samme port og kan udefra ikke skelnes fra dem.
  Hvad enten der lige nu er et menneske, der skriver, eller enheden kun
  kører, kan det derved ikke ses. Dine beskeder venter aldrig på
  tildækningsstrømmen -- de går straks afsted, den kører kun ved
  siden af.

**Hvad tildækningsstrømmen koster:** I Wi-Fi cirka 13 MB om dagen. I
mobildata sender Cleona kun én tildækningspakke i minuttet, det er cirka
1,7 MB om dagen. Årsagen til drosslingen i mobildata er ikke datamængden,
men batteriet: Hver pakke vækker radio-modulet.

**Hvad Cleona ikke kan skjule** -- ærligt talt:

- Ingen **enkelt** observatør ser, hvem der skriver med hvem -- hverken din
  udbyder eller knuderne undervejs. Den, der **overvåger begge ender
  på samme tid**, for eksempel en stat, der overvåger din tilslutning og
  din modparts eller stiller begge naboer op, kan over tid
  tildele: Pakke ud hos dig, kort efter pakke ind hos din modpart.
  Gentaget ofte nok, giver det en forbindelse.
- Tildækningsstrømmen vanskeliggør denne tildeling, men forhindrer den
  ikke. Den skjuler enkelte beskeder, ikke mængden: Den, der sender meget,
  forøger den samlede trafik fra sin enhed.
- En kontakt, der er din faste nabo, får at vide, **hvornår** og **hvor
  meget** du sender og modtager -- ikke med hvem og ikke hvad. Kommer
  truslen fra dit eget omgivende miljø, kan du fritage hver kontakt derfra
  (se kapitel 3, "Brug aldrig som fast nabo").
- Har to nye brugere kun samme ene nabo, kører deres besked
  over præcis denne knude, og han ser begge ender. Så snart en af
  dem har flere naboer, er det slut.
- Din invitation indeholder dine internetadresser. Den, der har
  tekstlinjen, ser, hvor du er online -- giv den kun til mennesker, du
  tillægger det at kunne.
- En nabo, der videresender, ser, at to koder udveksler pakker --
  ikke, hvem der står bag, og ikke, hvad der står i.
- Et signal fra et igangværende opkald kan, når den første nabo lige nu
  ikke svarer, gå over en knude, der ser begge ender; den får at vide, at
  I taler sammen.
- En stor fil, som du har givet samtykke til, ser den computer, der
  videresender eller opbevarer den, i begge ender (se kapitel 4).
- Ved opkald gælder beskyttelsen mod udbyderen ikke, og din kontakt ser
  din internetadresse (se kapitel 7).

### Hvad sker der, når din modpart er offline?

1. Cleona starter alle egnede veje på samme tid: i samme Wi-Fi direkte,
   på internettet via to naboer -- og derudover postkassen.
2. Til postkassen lægger Cleona den krypterede besked hos tre
   naboer. Så snart to har bekræftet modtagelsen, gælder den som
   lagt.
3. Cleona vælger dertil fortrinsvis naboer, hvor din modpart også
   kigger -- først naboen, som hans invitation nævner.
4. Beskeden venter der i op til 7 dage. Kommer din modpart tilbage,
   henter han den og bekræfter modtagelsen over for dig. Først da ser du to
   hager.

Postkassen kan kun din modpart tømme: Hentning og sletning går
kun med en nøgle, som kun han har, og slettet bliver først, når
han har bekræftet modtagelsen. Naboerne ser kun krypterede
pakker under en værdi, der skifter hver dag.

### Fremmede kommer ikke igennem

Fra en, der hverken er din kontakt eller medlem af en fælles gruppe,
modtager Cleona præcis to ting: spørgsmålet om dine offentlige nøgler, så
længe en af dine invitationer er åben, og en kontaktanmodning. Anmodningen
skal bære en gyldig invitation fra dig, og afsenderen skal først have løst
en regneopgave. Alt andet -- beskeder, opkald, filer -- kasseres, før det
overhovedet når appen. Den, der kun har dit trykte visitkort, kan
altså ikke bare ringe til dig. Et medlem af en fælles gruppe når dig kun i
denne gruppe -- med gruppebeskeder og gruppeopkald, aldrig enkeltvis.

### Anti-censur

Cleona er bygget således, at det er vanskeligt at blokere:

- **Ingen server, ingen fast adresse.** I appen står der ingen adresse, man
  kunne spærre, og netværket afhænger ikke af nogen enkelt knude.
- **Ingen fast port.** Hver enhed vælger ved første start en
  tilfældig port. Der findes intet kendt portnummer, hvorpå man kunne
  genkende Cleona-trafik.
- **Som tilfældige data.** Opbygningen af forbindelsen mellem to enheder er
  koderet således, at den ikke kan skelnes fra tilfældige data.
- **Mange indgange.** Hver invitation, hver nabo og hver enhed i
  samme Wi-Fi er en mulig vej tilbage ind i netværket.

### Sikker nøglelagring

På understøttede platforme gemmer Cleona dine krypterings-
nøgler i operativsystemets sikre nøglering (Android Keystore,
iOS Keychain, macOS Keychain). Hvor tilgængeligt, tilbyder det
hardware-understøttet beskyttelse af dine nøgler.

### Database-kryptering

Dine beskeder og samtaler ligger i en krypteret
database -- en egen for hver identitet, hver med egen nøgle.
Krypteret er ikke blot selve databasen, men også dens
mellemfiler; intet skrives ukrypteret til disken,
heller ikke kortvarigt. Indstillinger, kontakter og medier er ligeledes
gemt krypteret.

Nøglerne afledes fra dine 24 ord og eksisterer kun
på din enhed. Selv den, der får din enhed i hænderne og
udlæser dataene, finder uden disse nøgler kun ulæselige data.

Ukrypteret bliver det kun, hvor du selv fører indhold ud af Cleona:
- når du gemmer en fil fra en chat på din enhed,
- når du med skærmbillede-knappen lægger et billede ind i dine billeder,
- når du deler noget til en anden app,
- når du indstiller medie-arkiveringen (kapitel 13): De arkiverede
  originaler ligger ukrypteret på dit netværkslager derhjemme, så du også
  kan åbne dem der uden Cleona,
- når du spejler aftaler til Android-systemkalenderen: Der kan andre apps
  med kalenderadgang læse dem.

Hvad der på den måde er ført ud, slettes ikke med beskeden og udløber
heller ikke med den.

### Beskyttelse på skærmen

På Android, Windows og macOS tillader Cleona ikke skærmoptagelse fra andre
apps. Har du brug for et billede, så brug skærmbillede-knappen i den
øverste linje: Den lægger billedet ind i dine billeder -- ukrypteret. I en
samtale, hvor videresendelse ikke er tilladt, findes der intet
skærmbillede.

---

## 15. Softwareopdateringer

### Hvordan får jeg opdateringer?

Cleona kan opdateres på forskellige veje. Målet er, at du også kan
modtage opdateringer, når enkelte distributionsveje fejler
eller blokeres:

1. **App Store / Play Store:** Så snart Cleona findes dér, og du har
   installeret den via en butik, modtager du opdateringer som sædvanligt
   via butikken. På iPhone kommer opdateringer via TestFlight.
2. **GitHub Releases:** På projektets GitHub-side finder du
   underskrevne installationspakker til alle platforme.
3. **Opdateringer via netværket:** Cleona kan hente en opdatering direkte via
   netværket -- uden download-server. Den nye version er delt i
   fejlkorregerende stykker, der fordeler sig i netværket; en del
   deraf rejser endda med i tildækningsstrømmen. Din enhed samler nok
   stykker og sætter opdateringen sammen. Overført bliver normalt kun
   ændringen -- få MB i stedet for hele appen. Det gælder Linux, Windows
   og Android; under macOS henter du nye versioner fra hjemmesiden eller
   fra GitHub.
4. **Invitationslinks:** Du kan oprette invitationslinks, der indeholder
   alt, hvad en ny bruger har brug for, for at installere Cleona og
   forbinde sig med netværket.
5. **Fysisk overdragelse:** I miljøer uden internet kan du give Cleona
   videre via USB-stick eller i det lokale netværk.

### Sådan forløber en opdatering

1. Cleona samler automatisk stykkerne af en ny opdatering i baggrunden
   og sætter dem sammen.
2. Først når opdateringen er **fuldstændig**, og dens **signatur er
   kontrolleret**, tilbyder Cleona den til dig. Du får altså aldrig en
   halv eller ukontrolleret opdatering tilbudt.
3. Trykker du på "Installér", starter installationen uden yderligere
   forespørgsel. På Android viser derudover systemet sin
   installationsdialog.

Ældre versioner tilbydes ikke -- en opdatering går altid kun
fremad. Er en version så gammel, at den ikke længere kan
samarbejde med netværket, viser Cleona det tydeligt og beder dig om at
opdatere.

### Signaturkontrol

Hver opdatering er dobbelt-underskrevet: med en klassisk og en
post-quantum-metode. Cleona kontrollerer automatisk begge underskrifter.
Således sikres det, at kun opdateringer fra den officielle udvikler
accepteres -- også selv om opdateringen kom via netværket fra fremmede
enheder. En opdatering opstår aldrig automatisk fra udviklingen, men kun
når udvikleren underskriver den manuelt.

---
## 16. Ofte stillede spørgsmål

### "Kan jeg bruge Cleona uden internet?"

Cleona har brug for en netværksforbindelse, men ikke nødvendigvis
internettet: I samme Wi-Fi finder Cleona-enheder hinanden selv og kan skrive
helt uden internetadgang. Være online på samme tid behøver du ikke med din
modpart: Er han offline, venter beskeden i op til 7 dage
i postkassen hos tre naboer, indtil han henter den.

### "Hvad hvis jeg mister min seed-phrase?"

Så længe der endnu kører en enhed med din identitet, er intet tabt --
der skriver du bare videre. På den enhed, hvor du har oprettet identiteten,
kan du som regel aflæse de 24 ord én gang til (se kapitel 2). Stol dog ikke
på det: En geninstallation fjerner denne kopi, og på Android tilintetgør
også fjernelse eller ændring af skærmlåsen den. Har du hverken ordene eller
en enhed, er der ingen vej tilbage -- heller ikke via dine kontakter,
udvikleren eller nogen som helst anden. Derfor er det så vigtigt at
opbevare de 24 ord sikkert.

### "Kan nogen læse mine beskeder med?"

Nej. Hver besked krypteres med en engangsnøgle, der
kun gælder for netop denne ene besked. Kun du og din modpart kan
afkryptere beskeden. Der findes ingen central server, ingen masternøgle
og ingen adgang for udvikleren. Selv hvis en enhed på
transportvejen videresender beskeden, ser den kun krypteret data-gødning
og en kode. Din nabo ved, at pakken kommer fra dig, men ikke, til hvem den
går; din modparts nabo ved, til hvem den går, men ikke, fra hvem.

### "Hvorfor har jeg ikke brug for et telefonnummer?"

Fordi din identitet er rent kryptografisk. I stedet for et telefonnummer
eller en e-mailadresse, der er knyttet til dit rigtige navn, identificerer
et nøglepar, der er oprettet på din enhed, dig. Kontakter tilføjer du via
QR-kode, NFC eller tekstlinjen fra din invitation -- ikke via et
telefonbibliotek. Det betyder
mere privatliv, fordi din messenger-konto ikke er bundet til din reelle
identitet.

### "Hvordan finder jeg folk på Cleona?"

Cleona har bevidst ingen kontaktsøgning efter telefonnummer eller navn -- det ville
være et privatlivsproblem. I stedet udveksler du invitationer direkte: via
QR-kode, NFC eller som tekstlinje via en anden vej. Det svarer til
at udveksle visitkort i stedet for at slå op i telefonbogen.

### "Fungerer Cleona også i udlandet?"

Ja. Så længe du har en internetforbindelse, fungerer Cleona overalt i
verden. Da der ikke findes nogen central server og ingen fast adresse, kan
tjenesten ikke let slukkes for bestemte lande. Hvordan Cleona
vanskeliggør blokeringer, står i kapitlet "Sikkerhed" under "Anti-censur". Et land,
der blokerer al ukendt trafik ved grænsen, kan dog også
stoppe Cleona.

### "Er Cleona gratis?"

Ja. Cleona kan bruges gratis og uden reklamer. Da der ikke findes nogen
central server, påløber der heller ingen serveromkostninger til driften. I
indstillingerne under "Støt Cleona" -> "Doner" kan du frivilligt støtte
udviklingen.

### "Min besked har kun én hage -- hvad betyder det?"

Beskeden er på vej, men din modpart har endnu ikke bekræftet
modtagelsen -- oftest fordi han lige nu er offline. Det er ikke en fejl:
Beskeden venter i op til 7 dage i postkassen. Så snart han henter den, ser du
to hager. Et ur betyder, at endnu ingen vej har båret beskeden -- den går
afsted af sig selv, så snart der er en; et advarselstegn, at den i 14 dage
ikke har fundet nogen vej, og du kan sende den igen.

### "Hvorfor kommer beskeder forsinket på min iPhone?"

iOS lader ikke apps køre permanent i baggrunden. Cleona vækkes kun kort af og
til; hvornår, bestemmer iOS. Den henter så alt. Så snart du åbner appen,
henter Cleona det, der er blevet gemt til dig.

### "Kan jeg skifte fra WhatsApp til Cleona?"

Ja, men du kan ikke overføre dine WhatsApp-chats. Cleona og WhatsApp
er grundforskellige systemer. Du skal tilføje dine kontakter enkeltvis i Cleona.
Det letteste er, når du sender tekstlinjen fra din invitation
til dine kontakter. Hver anmodning, der ankommer således, bekræfter du
selv under "Anmodninger".

### "Kan jeg bruge Cleona på flere enheder på samme tid?"

Ikke endnu. En anden enhed til samme identitet kommer med en senere
version (kapitel 11). På flere enheder kan du i dag bruge forskellige
identiteter.

### "Hvordan får jeg opdateringer, når App Store er blokeret?"

Cleona kan hente opdateringer direkte via netværket, uden at være
afhængig af en App Store, en hjemmeside eller en download-server. Når
en anden enhed i netværket har den nyeste version, kan din enhed hente
opdateringen derfra. Ægtheden kontrolleres via en digital signatur fra
udvikleren. Alternativt kan en kontakt give appen videre til dig via et
invitationslink eller USB-stick. Mere herom i kapitlet
"Softwareopdateringer".

---

## Hjælp og kontakt

Hvis du har spørgsmål eller støder på et problem, finder du aktuelle
informationer på Cleonas hjemmeside og på GitHub. Da Cleona er et decentralt
projekt, findes der ingen klassisk kundesupport -- men et aktivt
fællesskab, der gerne hjælper.

---

*Denne vejledning beskriver Cleona Chat version 4.2. Enkelte funktioner
kan i nyere versioner ændres eller udvides.*
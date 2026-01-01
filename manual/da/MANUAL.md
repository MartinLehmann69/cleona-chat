# Cleona Chat -- Brugervejledning

Version 3.1.125 | Juli 2026

---

## Indholdsfortegnelse

1. [Hvad er Cleona Chat?](#1-hvad-er-cleona-chat)
2. [Kom godt i gang](#2-kom-godt-i-gang)
3. [Kontakter](#3-kontakter)
4. [Beskeder](#4-beskeder)
5. [Grupper](#5-grupper)
6. [Offentlige kanaler](#6-offentlige-kanaler)
7. [Opkald](#7-opkald)
8. [Kalender](#8-kalender)
9. [Afstemninger](#9-afstemninger)
10. [Flere identiteter](#10-flere-identiteter)
11. [Multi-Device](#11-multi-device)
12. [Gendannelse](#12-gendannelse)
13. [Indstillinger](#13-indstillinger)
14. [Sikkerhed](#14-sikkerhed)
15. [Softwareopdateringer](#15-softwareopdateringer)
16. [Ofte stillede spoergsmaal](#16-ofte-stillede-spoergsmaal)

---

## 1. Hvad er Cleona Chat?

### Din messenger, dine data

Cleona Chat er en messenger, der fungerer helt uden en central server.
Dine beskeder sendes direkte fra din enhed til din kontakts enhed -- uden
omvej via et firmahovedkvarter, uden cloud, uden datacenter. Ingen virksomhed
kan laese, gemme eller videregive dine beskeder, fordi der ganske enkelt ikke
er nogen virksomhed imellem.

### Ingen konto, intet telefonnummer

Med Cleona behoever du hverken et telefonnummer eller en e-mailadresse for at
tilmelde dig. Din identitet bestaar af et kryptografisk noeglepar, som
automatisk oprettes paa din enhed ved foerste start. Det betyder: Ingen kan
finde dig via dit telefonnummer eller din e-mailadresse, medmindre du selv
deler dine kontaktoplysninger.

### Fremtidssikret kryptering

Cleona bruger saakaldt Post-Quantum-kryptering. Det betyder: Selv fremtidige
kvantecomputere vil ikke kunne knaekke dine beskeder. Du behoever ikke at
forstaa detaljerne -- det vigtige er, at din kommunikation er bedst muligt
beskyttet efter den aktuelle teknologiske standard.

### Hvordan fungerer det uden server?

Forestil dig, at du og dine kontakter tilsammen danner et netvaerk. Hver enhed
hjaelper med at videresende beskeder. Er din kontakt online, gaar beskeden
direkte derhen. Er din kontakt offline, gemmer faelles kontakter beskeden
midlertidigt og leverer den, saa snart modtageren er tilbage. Dine kontakter
er altsaa samtidig dit netvaerk.

### Platforme

Cleona er tilgaengelig til Android, iOS, macOS, Linux og Windows.

---

## 2. Kom godt i gang

### Installer appen

**Android:**
1. Download APK-filen fra Cleonas hjemmeside eller fra GitHub Releases.
2. Aabn filen paa din telefon. Hvis noedvendigt, tillad installation fra
   ukendte kilder (Android spoerger dig automatisk).
3. Tryk paa "Installer" og vent, til installationen er faerdig.

**iOS:**
1. Aabn TestFlight-invitationslinket paa din iPhone.
2. Tryk paa "Installer". TestFlight er Apples officielle maade at distribuere
   beta-apps paa.
3. Efter installationen finder du Cleona paa din startskaerm.

**macOS:**
1. Download DMG-filen fra Cleonas hjemmeside eller fra GitHub Releases.
2. Aabn DMG-filen og traek Cleona til din Programmer-mappe.
3. Ved foerste start spoerger macOS muligvis, om du vil aabne en app fra en
   identificeret udvikler -- bekraeft dette.

**Linux (Ubuntu/Debian):**
1. Download .deb-filen fra Cleonas hjemmeside eller fra GitHub Releases.
2. Installer med dobbeltklik eller i terminalen: `sudo dpkg -i cleona-chat_VERSION_amd64.deb`
3. Start Cleona via programmenuen eller i terminalen med `cleona-chat`.

**Linux (Fedora/openSUSE):**
1. Download .rpm-filen fra Cleonas hjemmeside eller fra GitHub Releases.
2. Installer med: `sudo dnf install cleona-chat-VERSION.x86_64.rpm`
3. Start Cleona via programmenuen eller i terminalen med `cleona-chat`.

**Linux (alle distributioner -- AppImage):**
1. Download .AppImage-filen fra Cleonas hjemmeside eller fra GitHub Releases.
2. Goer filen eksekverbar: Hoejreklik, Egenskaber, Eksekverbar, eller i terminalen: `chmod +x cleona-chat-VERSION-x86_64.AppImage`
3. Start med dobbeltklik eller i terminalen: `./cleona-chat-VERSION-x86_64.AppImage`

**Windows:**
1. Download installationsfilen fra Cleonas hjemmeside eller fra GitHub Releases.
2. Koer installationsfilen og foelg anvisningerne.
3. Start Cleona via startmenuen eller genvejen paa skrivebordet.

### Opret identitet

Ved foerste start opretter Cleona automatisk en ny identitet til dig.
Du kan give dig selv et visningsnavn -- det er det navn, dine kontakter
ser. Dette navn kan aendres naar som helst.

### Skriv din seed-phrase ned -- det vigtigste af alt

Efter oprettelsen af din identitet viser Cleona dig 24 ord. Det er din
**seed-phrase** -- din personlige gendannelsesnoegle.

**Skriv disse 24 ord ned paa papir og opbevar dem sikkert.**

Hvorfor er det saa vigtigt?

- Hvis din telefon gaar i stykker, bliver vaek eller bliver stjaalet, kan du
  med disse 24 ord gendanne hele din identitet paa en ny enhed.
- Uden seed-phrasen er der ingen vej tilbage. Der er ingen "glemt adgangskode"-
  knap og ingen support, der kan give dig din konto tilbage -- for der findes
  slet ingen konto paa en server.
- Del aldrig din seed-phrase med andre. Den, der kender disse ord, kan udgive
  sig for at vaere dig.

Du kan ogsaa finde seed-phrasen senere i indstillingerne under "Sikkerhed",
hvis du har brug for at se den igen.

### Tilfoejer din foerste kontakt

For at chatte med nogen skal du foerst tilfoeje personen som kontakt. Der er
flere maader at goere det paa -- alle forklares i naeste afsnit.

---

## 3. Kontakter

### Scan QR-kode (anbefalet)

Den nemmeste maade at tilfoeje en kontakt paa:

1. Din kontakt aabner sin identitetsdetaljeside (tryk paa sit eget navn i den
   oeverste linje) og viser dig sin QR-kode.
2. Du trykker paa plus-knappen og vaelger "Scan QR-kode".
3. Hold din telefon foran din kontakts QR-kode.
4. Kontaktanmodningen sendes automatisk. Saa snart din kontakt accepterer den,
   kan I skrive sammen.

Hvis I moedes personligt, er QR-koden den sikreste metode, fordi du ved praecis,
hvem du udveksler kontaktoplysninger med.

### NFC (hold telefonerne mod hinanden)

Hvis begge enheder understoetter NFC:

1. Aabn begge tilfoej-kontakt-funktionen.
2. Hold jeres telefoner ryg mod ryg.
3. Kontaktoplysningerne udveksles automatisk.

NFC tilbyder ligesom QR-koden hoej sikkerhed, fordi udvekslingen kun fungerer,
naar I fysisk staar ved siden af hinanden.

### Del link (cleona://-URI)

Du kan ogsaa sende dit kontaktlink via e-mail, SMS eller en anden messenger:

1. Aabn din identitetsdetaljeside.
2. Kopier dit cleona://-link.
3. Send linket til den person, der skal tilfoeje dig.
4. Den anden person aabner linket eller indsaetter det i tilfoej-kontakt-
   dialogen.

Bemaerk: Med denne metode stoler du paa, at linket ikke er blevet aendret
undervejs. For saerligt foelsomme kontakter anbefaler vi QR-kode eller NFC.

### Accepter kontaktanmodninger

Naar nogen sender dig en kontaktanmodning, vises den i din indbakke (den
sidste fane i den nederste linje). Der kan du:

- **Acceptere** -- personen tilfoejes til dine kontakter.
- **Afvise** -- anmodningen kasseres.
- **Blokere** -- personen kan ikke sende dig flere anmodninger.

### Verifikationsniveauer

Cleona viser dig, hvor sikkert en kontakts identitet er bekraeftet:

| Niveau | Betydning |
|--------|-----------|
| Ukendt | Du har kun modtaget Node-ID eller et link. |
| Set | Noegleudvekslingen lykkedes, I kan kommunikere krypteret. |
| Verificeret | I har moedt hinanden personligt og verificeret via QR-kode eller NFC. |
| Betroet | Du har eksplicit markeret denne kontakt som palidelig. |

Jo hoejere niveauet er, desto sikrere kan du vaere paa, at du virkelig
kommunikerer med den rigtige person.

---

## 4. Beskeder

### Send og modtag tekst

Skriv blot din besked i indtastningsfeltet nederst og tryk Enter eller paa
send-knappen. Din besked krypteres automatisk, foer den forlader din enhed.

Indgaaende beskeder vises i chathistorikken. Et flueben viser dig, om din
besked er blevet leveret.

### Send billeder, videoer og filer

Du har flere muligheder:

- **Papirklips-ikon** i indtastningsfeltet: Tryk paa det for at vaelge en fil,
  et billede eller en video fra dit galleri eller filsystem.
- **Traek og slip** (desktop): Traek en fil direkte ind i chatvinduet.
- **Indsaet fra udklipsholder** (desktop): Kopier et billede og indsaet det
  i chatten.

Smaa filer (under 256 KB) sendes direkte med. Stoerre filer overfoeres i en
totrinsproces: Foerst annonceres filen, derefter overfoeres den i dele.

### Talebeskeder

1. Hold mikrofon-knappen i indtastningsfeltet nede.
2. Tal din besked ind.
3. Slip knappen for at sende beskeden.

Hvis talegenkendelse er aktiveret paa din enhed (se Indstillinger), bliver
din talebesked automatisk transskriberet til tekst. Din kontakt ser baade
optagelsen og den transskriberede tekst.

### Svar paa beskeder (citer)

For at svare paa en bestemt besked:

1. Aabn trepunktsmenuen ved siden af beskeden.
2. Vaelg "Svar".
3. Over indtastningsfeltet vises et banner med den citerede besked.
4. Skriv dit svar og send det.

Den citerede besked vises i dit svar, saa sammenhaengen er tydelig.

### Rediger og slet beskeder

- **Rediger:** Trepunktsmenuen ved beskeden, derefter "Rediger". AEndr
  teksten og send den igen. Din kontakt kan se, at beskeden er blevet
  redigeret. Redigering er mulig inden for 15 minutter efter afsendelse.
- **Slet:** Trepunktsmenuen ved beskeden, derefter "Slet". Beskeden
  fjernes baade hos dig og din kontakt. Du kan slette dine egne beskeder
  naar som helst -- der er ingen tidsfrist for sletning.

### Emoji-reaktioner

I stedet for at skrive et svar kan du reagere paa en besked med en emoji:

1. Aabn trepunktsmenuen eller hold beskeden nede laenge.
2. Vaelg en emoji fra hurtigvalget eller aabn emoji-vaelgeren for det
   fulde udvalg.
3. Din reaktion vises under beskeden.

### Kopier tekst

Via trepunktsmenuen ved en besked kan du kopiere beskedteksten til
udklipsholderen.

### Soeg i beskeder

Oeverst i chatvinduet finder du soegefunktionen. Indtast et soegeord, og
Cleona viser dig alle resultater i den aktuelle chat. Med piletasterne kan
du hoppe mellem resultaterne.

Paa startsiden er der desuden et faneovergribende soegefilter, som lader dig
soege i alle samtaler efter et begreb.

### Link-forhaandsvisning

Naar du sender et link, genererer Cleona automatisk en forhaandsvisning
(titel, beskrivelse, miniaturebillede). Denne forhaandsvisning oprettes paa
din enhed og sendes med -- din kontakt behoever ikke at oprette forbindelse
til den linkede hjemmeside.

Naar du trykker paa et modtaget link, bliver du spurgt, om du vil aabne det
i den normale browser, i inkognitotilstand eller slet ikke.

---

## 5. Grupper

### Opret en gruppe

1. Skift til fanen "Grupper".
2. Tryk paa plus-knappen.
3. Giv gruppen et navn.
4. Vaelg de kontakter, du vil invitere.
5. Tryk paa "Opret".

De inviterede kontakter modtager en notifikation og kan slutte sig til gruppen.

### Inviter medlemmer

Ogsaa efter oprettelsen kan du invitere flere kontakter:

1. Aabn gruppeinfo (trepunktsmenuen i gruppeoversigten eller den oeverste
   linje i gruppechatten).
2. Tryk paa "Inviter".
3. Vaelg de kontakter, du vil tilfoeje.

### Roller

Hver gruppe har tre roller:

- **Ejer (Owner):** Har fuld kontrol. Kan tilfoeje og fjerne medlemmer,
  udnaevne administratorer og administrere gruppen. Ejeren kan ogsaa
  overdrage sin status til et andet medlem.
- **Administrator:** Kan fjerne medlemmer og hjaelpe med administrationen.
- **Medlem:** Kan laese og skrive beskeder.

### Forlad en gruppe

1. Aabn trepunktsmenuen i gruppeoversigten.
2. Vaelg "Forlad".
3. Bekraeft din beslutning.

Naar du forlader en gruppe, forbliver dine hidtidige beskeder synlige for
de andre medlemmer.

---

## 6. Offentlige kanaler

### Hvad er kanaler?

Kanaler er offentlige diskussionsfora inden for Cleona-netvaerket. I
modsaetning til grupper kan alle laese med her uden at skulle inviteres.
Kun ejeren og administratorer kan offentliggoere indlaeg -- abonnenter
laeser med.

### Find og tilmeld dig kanaler

1. Skift til fanen "Kanaler".
2. Aabn fanen "Soeg".
3. Gennemsoeg de tilgaengelige kanaler efter navn eller emne.
4. Tryk paa en kanal og derefter paa "Abonner".

Kanaler kan filtreres efter sprog. Nogle kanaler er markeret som "Ikke egnet
til mindreaarige" -- disse er kun synlige, hvis du i din profil har bekraeftet,
at du er over 18 aar.

### Opret din egen kanal

1. Skift til fanen "Kanaler".
2. Tryk paa plus-knappen.
3. Indtast et kanalnavn (skal vaere unikt i hele netvaerket).
4. Vaelg sprog, og om kanalen skal vaere offentlig eller privat.
5. Valgfrit: Tilfoeej en beskrivelse og et billede.
6. Tryk paa "Opret".

For offentlige kanaler kan du angive, om indholdet klassificeres som "Ikke
egnet til mindreaarige".

### Rapporter indhold

Hvis du opdager upassende indhold i en offentlig kanal, kan du rapportere
det. Cleona bruger et decentralt moderationssystem: Rapporter vurderes af
tilfaeldigt udvalgte medlemmer af netvaerket (en slags "naevningeting").
Konstateres en overtraedelse, modtager kanalen en advarsel. Ved gentagne
overtraedelser nedgraderes den i soegeindekset eller blokeres.

### Systemkanaler

Cleona har to indbyggede systemkanaler:

- **Bug Log:** Naar Cleona registrerer en fejl, spoerger den dig, om du vil
  sende en anonymiseret fejlrapport. Disse rapporter havner i Bug Log-kanalen,
  hvor de kan ses af faellesskabet. Der overfoeres ingen personlige data --
  kun tekniske fejlbeskrivelser. Du kan ogsaa manuelt sende en lograpport
  (med forhaandsvisningsdialog og eksplicit samtykke).
- **Feature Requests:** Her kan brugere indsende funktionsoensker og stemme
  paa eksisterende forslag. Forslagene sorteres efter stemmer.

Begge systemkanaler har en stoerrelsegraense paa 25 MB og overvaages af
jury-moderationssystemet.

---

## 7. Opkald

### Start et taleopkald

1. Aabn chatten med den kontakt, du vil ringe til.
2. Tryk paa telefonikonet i den oeverste linje.
3. Vent paa, at din kontakt besvarer opkaldet.

Under samtalen ser du en tidslinje, samtalens varighed og har adgang til
lydloes og hoejttaler.

For at laegge paa trykker du paa den roede laeg-paa-knap.

### Start et videoopkald

1. Aabn chatten med kontakten.
2. Tryk paa kameraikonet i den oeverste linje.
3. Dit videobillede vises i et lille vindue, din kontakts billede i det
   store omraade.

Du kan under samtalen skifte mellem front- og bagkamera.

### Indgaaende opkald

Naar nogen ringer til dig, vises et notifikationsvindue med opkalderens navn.
Du kan:

- **Besvar** -- samtalen begynder.
- **Afvis** -- opkalderen faar besked.

Hvis du allerede er i en samtale, afvises nye opkald automatisk.

### Gruppeopkald

Du kan ogsaa foere gruppeopkald, hvor flere personer deltager samtidig.
Opkaldet organiseres via et intelligent videresendingstraee, saa ikke alle
deltagere behoever at vaere direkte forbundet med hinanden. Alle samtaler
er gennemgaaende krypteret.

### Kryptering ved opkald

Alle opkald krypteres med engangsnoegler, der kun eksisterer i samtalens
varighed. Efter ophaeng slettes disse noegler straks. Ingen kan efterfoelgende
dekryptere en afsluttet samtale.

---

## 8. Kalender

Cleona indeholder en indbygget kalender, der er krypteret og fungerer helt
decentralt -- uden cloudtjeneste.

### Visninger

Kalenderen tilbyder fem visninger: Dag, Uge, Maaned, Aar og en
opgavevisning. Skift mellem dem via fanerne oeverst paa
kalenderskaermen.

### Opret begivenheder

Tryk paa et tidsrum eller brug tilfoej-knappen for at oprette en ny
begivenhed. Du kan indtaste titel, dato, tidspunkt, sted og noter.
Begivenheder gemmes krypteret paa din enhed.

### Tilbagevendende begivenheder

Begivenheder kan gentages dagligt, ugentligt, maanedligt eller aarligt.
Du kan tilpasse moenstret (f.eks. hver anden tirsdag, den foerste i hver
maaned) og angive en slutdato eller et antal gentagelser.

### Inviter kontakter

Naar du opretter eller redigerer en begivenhed, kan du invitere dine
Cleona-kontakter. De modtager en krypteret kalenderinvitation og kan svare
med tilsagn, afslag eller maaske. AEndringer af begivenheden sendes
automatisk til alle inviterede.

### Ledig/optaget-visning

Du kan dele din tilgaengelighed med kontakter uden at afsloere
begivenhedsdetaljer. Der er tre privatlivsniveauer: fulde detaljer, kun
tidsblokke eller skjult. Du kan angive en standard og tilsidesaette den pr.
kontakt.

### Paamindelser

Begivenheder kan have paamindelser, der udloeser en systemnotifikation foer
begivenhedens start. Du kan udsaette paamindelser efter behov.

### Ekstern kalendersynkronisering

Cleona kan synkronisere med eksterne kalendertjenester:

- **CalDAV** -- Forbind til enhver CalDAV-kompatibel server (Nextcloud,
  Radicale osv.).
- **Google Kalender** -- Synkronisering via Google Calendar API med sikker
  OAuth2-godkendelse.
- **Lokal CalDAV-server** -- Cleona kan starte en lokal CalDAV-server paa
  din enhed, saa desktop-kalenderapps (Thunderbird, Outlook, Apple Kalender,
  Evolution) kan synkronisere med din Cleona-kalender.
- **Android-systemkalender** -- Begivenheder fra Cleona kan overfoeres til
  den indbyggede kalenderapp paa din Android-enhed.
- **ICS-filer** -- Importer og eksporter begivenheder i
  standard-iCalendar-formatet.

### PDF-eksport

Du kan udskrive eller eksportere enhver kalendervisning (Dag, Uge, Maaned,
Aar) som PDF-dokument.

---

## 9. Afstemninger

Du kan oprette afstemninger i enhver chat eller gruppe for at indsamle
meninger eller planlaegge moeder.

### Afstemningstyper

Cleona understoetter fem typer afstemninger:

- **Enkeltvalg** -- Deltagere vaelger een mulighed.
- **Flervalg** -- Deltagere kan vaelge flere muligheder.
- **Tidsafstemning** -- Find et tidspunkt, der passer alle. Hver deltager
  markerer tidspunkter som tilgaengelig, maaske eller ikke tilgaengelig.
- **Skala** -- Vurder noget paa en numerisk skala (f.eks. 1 til 5).
- **Fritekst** -- Deltagere skriver deres eget svar.

### Opret en afstemning

Aabn en chat og tryk paa afstemningsikonet (eller brug vedhaeftningsmenuen).
Vaelg afstemningstype, formuler dit spoergsmaal og mulighederne, og send
afstemningen. Den vises som en besked i chatten.

### Stem

Tryk paa en afstemning for at afgive din stemme. Du kan naar som helst
aendre eller traekke din stemme tilbage.

### Anonym afstemning

Afstemninger kan konfigureres til anonym afstemning. Naar det er aktiveret,
er stemmer kryptografisk anonyme -- ingen, ikke engang afstemningens
opretter, kan se, hvem der har stemt paa hvad. Stemmetallene forbliver
dog synlige.

### Tidsafstemning til kalender

Naar en tidsafstemning er afsluttet, kan vinderens tidspunkt med et enkelt
tryk konverteres direkte til en kalenderbegivenhed.

---

## 10. Flere identiteter

### Hvorfor flere identiteter?

Forestil dig, at du gerne vil adskille dit arbejdsliv og dit privatliv --
ligesom med to forskellige telefonnumre, men uden en ekstra telefon. I Cleona
kan du bruge flere identiteter paa een enhed. Hver identitet har sit eget
navn, sit eget profilbillede, sine egne kontakter og sine egne samtaler.

### Opret ny identitet

1. I den oeverste linje ser du din aktuelle identitet som en fane.
2. Tryk paa plustegnet (+) til hoejre for dine identitetsfaner.
3. Indtast et navn til den nye identitet.
4. Faerdigt -- den nye identitet er straks aktiv.

### Skift mellem identiteter

Tryk blot paa identitetsfanen i den oeverste linje. Skiftet sker
oejeblikkeligt -- ingen ventetid, ingen genindlaesning.

### Alle koerer samtidig

Et vigtigt punkt: Alle dine identiteter er aktive samtidig. Selvom du lige
nu vises som "Arbejde", modtager din "Privat"-identitet fortsat beskeder.
Du gaar ikke glip af noget, uanset hvilken identitet du aktuelt har valgt.

### Identitetsdetaljeside

Naar du trykker paa fanen for din aktuelt aktive identitet, aabnes
detaljesiden. Her kan du:

- Vise din QR-kode til kontakter.
- AEndre eller fjerne dit profilbillede.
- Tilfoeje en profilbeskrivelse.
- AEndre dit visningsnavn.
- Vaelge et design (skin) for denne identitet.
- Slette identiteten, hvis du ikke laengere har brug for den.

### Slet identitet

Naar du sletter en identitet, faar dine kontakter besked om det. Identiteten
og alle tilhoerende data fjernes fra din enhed. Denne handling kan ikke
fortrydes.

---

## 11. Multi-Device

### Brug Cleona paa flere enheder

Du kan bruge den samme identitet paa op til 5 enheder samtidig. Een enhed er
den primaere (den holder seed-phrasen), og yderligere enheder tilknyttes den.

### Tilknyt ny enhed

1. Aabn indstillingerne paa din primaere enhed.
2. Gaa til "Tilknyttede enheder".
3. Vaelg "Tilknyt ny enhed".
4. Installer Cleona paa den nye enhed og vaelg ved start "Tilknyt til
   eksisterende enhed".
5. Scan parings-QR-koden, der vises paa din primaere enhed, eller brug
   paringslinket.

Den tilknyttede enhed modtager et delegationscertifikat fra den primaere
enhed. Beskeder sendt fra en tilknyttet enhed er kryptografisk signeret
med en delegeret noegle, saa kontakter kan verificere, at beskeden virkelig
stammer fra din identitet.

### Saadan fungerer det

- Den primaere enhed holder din seed-phrase og masternoeglerne.
- Tilknyttede enheder modtager afledte signaturnoegler og et
  delegationscertifikat -- de modtager aldrig selve seed-phrasen.
- Alle enheder deler den samme identitet og kontakter. Beskeder ankommer
  paa alle enheder.
- Delegationscertifikater fornyes automatisk foer udloeb.

### Enhedsadministration

Aabn indstillingerne og gaa til "Tilknyttede enheder" for at se alle dine
tilknyttede enheder, deres status og seneste aktivitet. Du kan til enhver
tid tilbagekalde en tilknyttet enhed, hvis den bliver vaek eller stjaalet.

### Noednoeglerotation

Hvis du mistaenker, at en enhed er blevet kompromitteret, kan du udloese en
noednoeglerotation. Nye noegler genereres, og rotationen skal bekraeftes af
et flertal af dine andre enheder. Det forhindrer, at en enkelt stjaalet
enhed egenhaendigt kan rotere noegler.

---

## 12. Gendannelse

### Brug seed-phrase

Hvis du mister din enhed eller opsaetter en ny:

1. Installer Cleona paa den nye enhed.
2. Vaelg "Gendan" ved start.
3. Indtast dine 24 ord.
4. Cleona gendanner din identitet og kontakter automatisk dine hidtidige
   kontakter.
5. Dine kontakter svarer med dine kontaktdata, gruppemedlemskaber og
   beskedhistorik.

Gendannelsen foregaar i tre trin:
- Foerst kommer dine kontakter og grupper tilbage.
- Derefter de seneste 50 beskeder fra hver samtale.
- Til sidst den komplette beskedhistorik.

Det er tilstraekkeligt, at en enkelt af dine kontakter er online, for at
gendannelsen fungerer.

### Guardian Recovery (betroede personer)

Du kan udnaevne op til fem betroede personer som "Guardians". Derved opdeles
din gendannelsesnoegle i fem dele, hvoraf hver Guardian modtager een. For at
gendanne din identitet er tre af de fem dele tilstraekkelige.

Det betyder: Selv hvis du har mistet din seed-phrase, kan tre af dine
Guardians tilsammen gendanne din konto. Ingen enkelt Guardian kan alene faa
adgang til dine data -- der kraeves altid mindst tre.

Saadan opsaetter du Guardians:
1. Aabn indstillingerne.
2. Gaa til "Sikkerhed".
3. Vaelg "Guardian Recovery".
4. Vaelg fem betroede kontakter.

### Hvorfor dine kontakter er dit backup

I traditionelle messengere ligger dine data paa udbyderens servere. Hos
Cleona er der ingen server -- men dine kontakter overtager denne rolle. Naar
du sender en besked, gemmer faelles kontakter en krypteret kopi for det
tilfaelde, at modtageren er offline. Ved en gendannelse leverer dine kontakter
dine data tilbage til dig.

Det betyder: Jo flere aktive kontakter du har, jo mere palidelig er dit
backup. Een kontakt, der regelmaessigt er online, er tilstraekkelig for en
vellykket gendannelse.

---

## 13. Indstillinger

Indstillingerne naar du via tandhjulsikonet i oeverste hoejre hjoerne.

### Notifikationer og ringetoner

- Vaelg mellem seks forskellige ringetoner til indgaaende opkald.
- Indstil en beskedtone.
- Paa Android-enheder kan du desuden aktivere eller deaktivere vibration.

### Design (Skins)

Cleona tilbyder ti forskellige designs: Teal, Ocean, Sunset, Forest,
Amethyst, Fire, Storm, Slate, Gold og Contrast. Contrast-designet opfylder
det hoejeste tilgaengelighedsniveau (WCAG AAA) og er saerligt laesbart ved
nedsat syn.

Hver identitet kan have sit eget design. Du aendrer designet paa
identitetsdetaljesiden (tryk paa den aktive identitetsfane).

Derudover kan du i indstillingerne under "Udseende" skifte mellem lyst,
moerkt og systemtema.

### Skift sprog

Cleona er tilgaengelig paa 33 sprog, herunder sprog med hoejre-til-venstre-
skrift (f.eks. arabisk, hebraisk). Skift sproget i indstillingerne under
"Sprog".

### Lagergraense

Du kan angive, hvor meget lagerplads Cleona maa bruge paa din enhed (mellem
100 MB og 2 GB). Naar graensen naaes, udlagres eller slettes aeldre medier
automatisk -- tekstbeskeder bevares altid.

### Mediearkivering

Hvis du derhjemme har en netvaerkslagring (NAS) eller en delt mappe, kan
Cleona automatisk udlagre dine medier dertil. Understoettede protokoller er
SMB, SFTP, FTPS og WebDAV.

Saadan fungerer den trinvise lagring:
- De foerste 30 dage: Alt forbliver paa din enhed.
- Efter 30 dage: Et miniaturebillede forbliver paa enheden, originalen
  arkiveres.
- Efter 90 dage: Kun et lille miniaturebillede forbliver paa enheden.
- Efter et aar: Kun en pladsholder forbliver, originalen ligger sikkert i
  arkivet.

Du kan naar som helst trykke paa et arkiveret medie for at hente det tilbage
-- forudsat at du er forbundet til dit hjemmenetvaerk. Saerligt vigtige medier
kan fastholdes, saa de aldrig udlagres.

### Transskription af talebeskeder

Naar aktiveret, konverteres dine talebeskeder lokalt paa din enhed til tekst
(med open source-modellen Whisper). Den transskriberede tekst sendes sammen
med optagelsen til din kontakt. Transskriptionen foregaar fuldstaendigt paa
din enhed -- ingen data sendes til eksterne tjenester.

### Auto-download

Du kan indstille, fra hvilken stoerrelse medier automatisk skal downloades.
Saa kan du f.eks. lade billeder downloade automatisk, men manuelt beslutte
ved store videoer.

### Tilknyttede enheder

Administrer dine tilknyttede enheder i dette omraade af indstillingerne.
Se Multi-Device-kapitlet for detaljer.

---

## 14. Sikkerhed

### Hvad betyder Post-Quantum-kryptering?

Nutidens kryptering er baseret paa matematiske problemer, der er ekstremt
svaere at loese for normale computere. Kvantecomputere kunne i fremtiden loese
nogle af disse problemer hurtigt. Post-Quantum-kryptering bruger yderligere
metoder, der ogsaa modstaar kvantecomputere.

Cleona kombinerer begge tilgange: klassisk kryptering for paalidelighed og
Post-Quantum-metoder for fremtidssikring. Saa er du beskyttet mod baade
nutidige og fremtidige trusler samtidig.

For hver enkelt besked genereres en unik noegle. Selv hvis en angriber
formaaede at knaekke noeglen til een besked, kunne vedkommende ikke laese
nogen anden besked med den.

### Hvorfor ingen server er sikrere

Med traditionelle messengere loeber dine beskeder over udbyderens servere.
Selvom de maaske er krypteret der: Udbyderen har adgang til metadata (hvem
kommunikerer hvornaar med hvem, hvor ofte, hvorfra) og skal under visse
omstaendigheder udlevere disse paa retskendelse.

Hos Cleona er der intet saadant centralt punkt. Dine beskeder rejser direkte
fra enhed til enhed. Der er intet sted, hvor alle metadata samles. Ingen kan
ud fra et enkelt datapunkt rekonstruere dit kommunikationsmoenter.

### Hvad sker der naar du er offline?

Naar du sender en besked, og modtageren er offline:

1. Cleona forsoeger foerst at levere beskeden direkte.
2. Hvis det ikke lykkes, viderestilles den via faelles kontakter.
3. Samtidig fordeles beskeden som krypterede stykker paa flere knuder i
   netvaerket (ligesom et puslespil bestaaende af 10 brikker, hvor 7 er
   tilstraekkelige til at samle billedet).
4. Beskeden opbevares i op til 7 dage.

Saa snart modtageren er online igen, leveres beskederne. Du faar en
bekraeftelse, naar din besked er ankommet.

### Anti-censur

Hvis dit netvaerk blokerer standardforbindelsesmetoden (UDP), skifter Cleona
automatisk til en alternativ overfoerselsmetode (TLS), der er svaerere at
genkende og blokere. Det sker transparent -- du behoever ikke at konfigurere
noget.

### Sikker noeglellagring

Paa understoettede platforme gemmer Cleona dine krypteringsnoegler i
operativsystemets sikre noeglering (Android Keystore, iOS Keychain, macOS
Keychain). Hvor tilgaengeligt tilbyder det hardwarebaseret beskyttelse af
dine noegler.

### Databasekryptering

Alle dine beskeder, kontakter og indstillinger er gemt krypteret paa din
enhed. Selv hvis nogen fik adgang til dit filsystem, kunne vedkommende ikke
laese noget uden din kryptografiske noegle. Denne noegle afledes fra din
identitet og eksisterer kun paa din enhed.

### Lukket netvaerk

Cleona fungerer som et lukket netvaerk. Hver netvaerkspakke er autentificeret,
saa kun legitime Cleona-enheder kan deltage. Det forhindrer udenforstaaende
i at indsluse forfalskede beskeder eller aflytte netvaerkstrafikken.

---

## 15. Softwareopdateringer

### Hvordan faar jeg opdateringer?

Cleona kan opdateres paa flere maader. Maalet er, at du ogsaa kan modtage
opdateringer, hvis enkelte distributionskanaler svigter eller blokeres:

1. **App Store / Play Store:** Hvis du har installeret Cleona via en app
   store, modtager du opdateringer som saedvanligt via butikken.
2. **GitHub Releases:** Paa projektets GitHub-side finder du signerede
   installationspakker til alle platforme.
3. **In-Network-opdateringer:** Hvis en anden Cleona-bruger i dit netvaerk
   allerede har den nyeste version, kan Cleona hente opdateringen direkte
   via P2P-netvaerket -- uden ekstern server. Den nye version opdeles i
   fejlkorrigerede fragmenter og fordeles over flere knuder. Din enhed
   samler nok fragmenter og saetter opdateringen sammen. Aegtheden
   verificeres med en Ed25519-signatur fra udvikleren.
4. **Invitationslinks:** Du kan oprette invitationslinks, der indeholder
   alt, hvad en ny bruger behoever for at installere Cleona og forbinde
   til netvaerket.
5. **Fysisk overfoersel:** I miljoeer uden internet kan du videregive Cleona
   via USB-stik eller i det lokale netvaerk.

### Opdateringsnotifikation

Naar en ny opdatering er tilgaengelig, viser Cleona dig en notifikation paa
startskaermen. Hvis opdateringen ogsaa er tilgaengelig via netvaerket
(In-Network-opdatering), har du mulighed for at downloade den direkte fra
netvaerket.

### Binaer distribution

Som standard hjaelper din enhed med at distribuere opdateringer til andre
brugere i netvaerket. Hvis du ikke oensker dette, kan du deaktivere denne
funktion i indstillingerne under "Netvaerk". Lagerforbruget til
opdateringsfragmenter er begraenset (5 MB paa mobile enheder, 20 MB paa
desktop-enheder) og ryddes regelmaessigt op.

### Signaturkontrol

Hver opdatering er kryptografisk signeret. Cleona kontrollerer signaturen
automatisk, foer en opdatering installeres. Saa er det sikret, at kun
opdateringer fra den officielle udvikler accepteres -- selv naar opdateringen
er hentet via P2P-netvaerket.

---

## 16. Ofte stillede spoergsmaal

### "Kan jeg bruge Cleona uden internet?"

Nej, Cleona kraever en netvaerksforbindelse for at sende og modtage beskeder.
Dog behoever du ikke vaere online samtidig med din kontakt: Beskeder sendt
mens modtageren er offline, gemmes midlertidigt og leveres automatisk, saa
snart begge parter er forbundet igen. I det lokale netvaerk (f.eks. paa det
samme WLAN) kan I ogsaa kommunikere helt uden internetadgang.

### "Hvad hvis jeg mister min seed-phrase?"

Hvis du har opsat Guardians, kan tre af fem betroede personer tilsammen
gendanne din adgang. Uden Guardians og uden seed-phrase er der desvaerre
ingen maade at faa din identitet tilbage. Derfor er det saa vigtigt at
opbevare de 24 ord sikkert.

### "Kan nogen laese mine beskeder med?"

Nej. Hver besked krypteres med en engangsnoegle, der kun gaelder for denne
ene besked. Kun du og din kontakt kan dekryptere beskeden. Der er ingen
central server, ingen generalnoegle og ingen adgang for udvikleren. Selv hvis
en enhed paa transportvejen videresender beskeden, ser den kun krypteret data.

### "Hvorfor behoever jeg ikke et telefonnummer?"

Fordi din identitet er rent kryptografisk. I stedet for et telefonnummer
eller en e-mailadresse, der er knyttet til dit rigtige navn, identificeres
du af et noeglepar, der er oprettet paa din enhed. Kontakter tilfoejes via
QR-kode, NFC eller link -- ikke via en telefonbog. Det betyder mere
privatlivsbeskyttelse, fordi din messenger-konto ikke er bundet til din
virkelige identitet.

### "Hvordan finder jeg folk paa Cleona?"

Cleona har bevidst ingen kontaktsoeening efter telefonnummer eller navn --
det ville vaere et privatlivsproblem. I stedet udveksler du kontaktdata
direkte: via QR-kode, NFC, cleona://-link eller i offentlige kanaler. Det
er som at udveksle visitkort i stedet for at slaa op i telefonbogen.

### "Fungerer Cleona ogsaa i udlandet?"

Ja. Saa laenge du har en internetforbindelse, fungerer Cleona overalt i
verden. Da der ingen central server er, kan tjenesten heller ikke blokeres
for bestemte lande. Cleona har desuden en anti-censur-fallback: Hvis den
normale forbindelse (UDP) blokeres, skifter Cleona automatisk til en
alternativ overfoerselsmetode (TLS), der er svaerere at genkende og blokere.

### "Er Cleona gratis?"

Ja. Cleona er gratis og uden reklamer. Da der ingen central server er,
paaloeber der heller ingen serveromkostninger til driften. I appen finder
du under "Donation" muligheden for frivilligt at stoette udviklingen.

### "Min besked har et ursymbol -- hvad betyder det?"

Det betyder, at beskeden endnu ikke er leveret. Din kontakt er formentlig
offline lige nu. Saa snart beskeden er leveret, aendres symbolet. Beskeder
opbevares i op til 7 dage til levering.

### "Kan jeg skifte fra WhatsApp til Cleona?"

Ja, men du kan ikke overfoere dine WhatsApp-chats. Cleona og WhatsApp er
grundlaeggende forskellige systemer. Du skal tilfoeje dine kontakter
enkeltvis i Cleona. Det nemmeste er at poste dit cleona://-link i en
WhatsApp-gruppe og bede de andre om at tilfoeje dig der.

### "Kan jeg bruge Cleona paa flere enheder samtidig?"

Ja. Du kan tilknytte op til 5 enheder med den samme identitet. Een enhed er
den primaere (den holder seed-phrasen), og yderligere enheder tilknyttes via
en sikker paringsproces. Alle enheder deler den samme identitet, kontakter
og samtaler. Se Multi-Device-kapitlet for detaljer.

### "Hvordan faar jeg opdateringer hvis app-butikken er blokeret?"

Cleona kan hente opdateringer direkte via P2P-netvaerket, uden at vaere
afhaengig af en app store, en hjemmeside eller en downloadserver. Hvis en
anden bruger i netvaerket har den nyeste version, kan din enhed hente
opdateringen derfra. Aegtheden verificeres med en digital signatur fra
udvikleren. Alternativt kan en kontakt give dig appen via invitationslink
eller USB-stik. Mere herom i kapitlet "Softwareopdateringer".

---

## Hjaelp og kontakt

Hvis du har spoergsmaal eller stoeder paa et problem, finder du aktuelle
oplysninger paa Cleonas hjemmeside og paa GitHub. Da Cleona er et decentralt
projekt, er der ingen klassisk kundesupport -- men et aktivt faellesskab,
der gerne hjaelper.

---

*Denne vejledning beskriver Cleona Chat version 3.1.125. Enkelte funktioner
kan aendres eller udvides i nyere versioner.*

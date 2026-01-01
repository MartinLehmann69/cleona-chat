# Cleona Chat -- Brukerhåndbok

Versjon 4.2 | Per november 2026

---

## Innholdsfortegnelse

1. [Hva er Cleona Chat?](#1-hva-er-cleona-chat)
2. [Komme i gang](#2-komme-i-gang)
3. [Kontakter](#3-kontakter)
4. [Meldinger](#4-meldinger)
5. [Grupper](#5-grupper)
6. [Offentlige kanaler](#6-offentlige-kanaler)
7. [Anrop](#7-anrop)
8. [Kalender](#8-kalender)
9. [Avstemninger](#9-avstemninger)
10. [Flere identiteter](#10-flere-identiteter)
11. [Flere enheter](#11-flere-enheter)
12. [Gjenoppretting](#12-gjenoppretting)
13. [Innstillinger](#13-innstillinger)
14. [Sikkerhet](#14-sikkerhet)
15. [Programvareoppdateringer](#15-programvareoppdateringer)
16. [Ofte stilte spørsmål](#16-ofte-stilte-spørsmål)

---
## 1. Hva er Cleona Chat?

### Din meldingstjeneste, dine data

Cleona Chat er en meldingstjeneste som fungerer helt uten en sentral server.
Meldingene dine reiser fra enheten din til motpartens enhet -- uten omvei via
et firmahovedkvarter, uten sky, uten datasenter. Der en annen enhet tilfeldigvis
hjelper til på veien, videresender den bare krypterte pakker. Ingen firma kan
lese, lagre eller videregive meldingene dine, rett og slett fordi ingen firma
står imellom.

### Ingen konto, ingen telefonnummer

Hos Cleona trenger du verken et telefonnummer eller en e-postadresse for å
registrere deg. Identiteten din består av et kryptografisk nøkkelpar som
opprettes automatisk på enheten din første gang du starter den. Det betyr:
Ingen kan spore deg opp via telefonnummeret eller e-postadressen din, med
mindre du selv gir kontaktopplysningene dine videre.

### Fremtidssikker kryptering

Cleona bruker såkalt post-kvantum-kryptering. Det betyr: Selv fremtidige
kvantedatamaskiner vil ikke kunne knekke meldingene dine. Du trenger ikke
forstå detaljene -- det eneste som betyr noe, er at kommunikasjonen din er
beskyttet så godt som dagens teknologi tillater.

### Hvordan fungerer det uten server?

Nettverket i Cleona består kun av enhetene til brukerne. Hver enhet er en
node, ingen node er viktigere enn en annen, og hver kjenner bare sine naboer.
Fire ting gjør dette nettverket spesielt:

- **Intet fast punkt.** Det står ingen serveradresse i appen, og nettverket
  er ikke avhengig av noen enkelt node. Det finnes ingenting man kunne slått
  av for å slå av Cleona.
- **Umiddelbart.** Meldingen din går i det øyeblikket du sender den. Den
  venter ikke på noen takt og ikke på noe annet.
- **Dekking på siden.** Enheten din sender hele tiden små dekkpakker, slik at
  det ikke kan sees utenfra når du virkelig skriver. Ingen melding avhenger av
  det -- dekkingen går bare ved siden av.
- **Koder i stedet for navn.** Den som videresender en melding, ser bare en
  kode som endres hver dag. Normalt kjenner ingen av dem avsender og mottaker
  samtidig; unntagelsene står i kapittel 14.

**Tre ruter, alle på en gang.** Når du sender en melding, prøver ikke Cleona
én rute etter den andre, men alle egne på én gang. Så snart motparten bekrefter
mottaket, avbrytes de andre.

1. **I samme nettverk:** Er dere i samme Wi-Fi, går meldingen rett over.
2. **Over de faste naboene:** På internettet overleverer enheten din meldingen
   til sin faste nabo. Den videresender den til motpartens faste naboer (opptil
   tre på én gang), og en av dem leverer den.
3. **Postkasse:** Er motparten din frakoblet, legger Cleona meldingen
   kryptert hos tre naboer. Der blir den i opptil 7 dager. Når motparten din
   kommer tilbake på nett, henter vedkommende den.

**Hvordan kommer du inn i nettverket?** Det står ingen serveradresse i appen.
Inngangspunktet ditt får du fra din første kontakt: Invitasjonen deres inneholder
adressene som enheten din finner sine første naboer gjennom. I samme Wi-Fi
finner Cleona-enheter hverandre også på egen hånd. Fra da av lærer enheten din
kjenne flere naboer for hver nabo den møter.

### Plattformer

Cleona er tilgjengelig for Android, iOS, macOS, Linux og Windows. På
datamaskiner og på Android kommer meldinger og anrop innenfor sekunder. På
iPhone gjelder dette så lenge appen er åpen. Når den ikke er åpen, vekker iOS
den bare kort av og til; når, bestemmer iOS. Cleona henter da alt som er
lagret for deg, og viser et varsel med et tall på app-ikonet. Anrop når ikke
en iPhone der appen ikke er åpen. Dette er en regel fra Apple, ikke en feil i
Cleona.

---

## 2. Komme i gang

### Installer appen

**Android:**
1. Last ned APK-filen fra Cleonas nettside eller fra GitHub Releases.
2. Åpne filen på telefonen din. Om nødvendig, tillat installasjon fra ukjente
   kilder (Android spør deg automatisk).
3. Trykk på «Installer» og vent til installasjonen er fullført.

**iOS:**
1. Åpne invitasjonslenken for TestFlight på iPhone-en din.
2. Trykk på «Installer». TestFlight er Apples offisielle måte å distribuere
   beta-apper på.
3. Etter installasjonen finner du Cleona på hjemskjermen.

**macOS:**
1. Last ned DMG-filen fra Cleonas nettside eller fra GitHub Releases.
2. Åpne DMG-en og dra Cleona i Programmer-mappen din.
3. Ved første oppstart spør macOS eventuelt om du vil åpne en app fra en
   identifisert utvikler -- bekreft dette.

**Linux (Ubuntu/Debian):**
1. Last ned .deb-filen fra Cleonas nettside eller fra GitHub Releases.
2. Installer med dobbeltklikk eller i terminalen: `sudo dpkg -i cleona-chat-beta_VERSION_amd64.deb`
3. Start Cleona fra programmenyen eller i terminalen med `cleona-chat-beta`.

**Linux (Fedora/openSUSE):**
1. Last ned .rpm-filen fra Cleonas nettside eller fra GitHub Releases.
2. Installer med: `sudo dnf install cleona-chat-beta-VERSION-1.x86_64.rpm`
3. Start Cleona fra programmenyen eller i terminalen med `cleona-chat-beta`.

**Linux (alle distribusjoner -- AppImage):**
1. Last ned .AppImage-filen fra Cleonas nettside eller fra GitHub Releases.
2. Gjør filen kjørbar: høyreklikk, egenskaper, kjørbar, eller i terminalen: `chmod +x cleona-chat-beta-VERSION-x86_64.AppImage`
3. Start med dobbeltklikk eller i terminalen: `./cleona-chat-beta-VERSION-x86_64.AppImage`

Pakkenavnene gjelder betaen, som for tiden er den eneste offentliggjorte
versjonen; de heter `cleona-chat-beta`.

**Windows:**
1. Last ned installasjonsprogrammet fra Cleonas nettside eller fra GitHub Releases.
2. Kjør installasjonsfilen og følg instruksjonene.
3. Start Cleona fra Start-menyen eller skrivebordssnarveien.

### Opprett en identitet

Ved første oppstart oppretter Cleona automatisk en ny identitet for deg.
Du kan gi deg selv et visningsnavn -- det er navnet kontaktene dine ser.
Dette navnet kan endres når som helst.

### Skriv ned seed-frasen -- det aller viktigste

Etter at identiteten din er opprettet, viser Cleona deg 24 ord. Det er din
**seed-frase** -- din personlige gjenopprettingsnøkkel.

**Skriv disse 24 ordene ned på papir og oppbevar dem trygt.**

Hvorfor er dette så viktig?

- Går telefonen din i stykker, mistes eller blir stjålet, kan du med disse 24
  ordene gjenopprette hele identiteten din på en ny enhet.
- Uten seed-frasen finnes det ingen vei tilbake. Det finnes ingen «glemt
  passord»-knapp og ingen kundestøtte som kunne gitt deg kontoen din tilbake
  -- for det finnes overhodet ingen konto på en server. Heller ikke kontaktene
  dine kan gjenopprette identiteten din, uansett hvor mange de er. En annen
  enhet med samme identitet kommer i en senere versjon (se kapittel 11).
- Aldri gi seed-frasen videre til andre. Den som kjenner disse ordene, kan
  utgi seg for å være deg.

Du finner de 24 ordene senere i innstillingene under «Sikkerhetskopi» ->
«Vis gjenopprettingsfrase», i tilfelle du vil lese dem av igjen. På Android
bekrefter du dette med skjermlåsen din.

### Legge til første kontakt

For å chatte med noen må du først legge vedkommende til som kontakt. Det
finnes flere veier å gjøre det på -- alle sammen forklares i neste avsnitt.

---

## 3. Kontakter

### Din invitasjon

Kontakter oppstår i Cleona kun gjennom en invitasjon. Din invitasjon er der
fra første oppstart -- selv uten internett og før enheten din overhodet har
funnet en nabo. Du finner den på din identitets-detaljside (trykk på ditt eget
navn i den øverste linjen).

Invitasjonen finnes i to former som inneholder nøyaktig det samme:

- som **QR-kode**, når motparten din står ved siden av deg, og
- som **tekstlinje**, som du sender med e-post, SMS eller via en annen
  meldingstjeneste.

Invitasjonen inneholder ingen telefonnummer og ingen navn fra en katalog. Den
inneholder dine offentlige nøkler og adressene som motparten din når deg og
dine naboer gjennom. For noen som nettopp har installert Cleona, er din
invitasjon derfor også inngangsporten til nettverket.

### Skanne QR-kode (anbefalt)

Når dere møtes personlig:

1. Du viser motparten din QR-koden fra invitasjonen din.
2. Motparten din trykker på pluss-knappen, velger «Skanne QR-kode» og holder
   kammeren mot skjermen din. Dette virker også med et webkamera på en datamaskin.
3. Forespørselen går til deg og **tas automatisk imot** -- for du viste jo
   nettopp koden selv.

En QR-kode gjelder kun én gang: Den første gyldige forespørselen tas imot,
deretter er invitasjonen brukt opp. QR-koden er den sikreste metoden, fordi
dere da vet nøyaktig hvem dere utveksler kontakten med.

### NFC (holde telefonene mot hverandre)

Når begge enhetene støtter NFC:

1. Åpne funksjonen for å legge til kontakt på begge.
2. Hold telefonene deres rygg mot rygg mot hverandre.
3. Invitasjonen overføres og tas automatisk imot.

NFC tilbyr i likhet med QR-koden høy sikkerhet, fordi utvekslingen kun
fungerer når dere står fysisk ved siden av hverandre.

### Sende tekstlinjen

Når dere ikke kan møtes:

1. Åpne invitasjonen din og kopier tekstlinjen.
2. Send den til personen som skal legge deg til -- med e-post, SMS eller via
   en annen meldingstjeneste.
3. Den andre personen limer inn linjen i Cleona i dialogen for å legge til
   kontakt.
4. Forespørselen dukker opp hos deg under **«Forespørsler»**. Her tas den
   **ikke** automatisk imot: Du bestemmer selv, for du kan ikke vite hvem
   som har lest linjen på veien.

### Ta imot kontaktforespørsler

En innkommende forespørsel oppretter foreløpig ingen kontakt. Den stiller deg
et spørsmål og dukker opp i fanen **«Forespørsler»**. Der ser du navnet og
verifiseringsnivået og kan velge:

- **Ta imot** -- først nå blir personen til din kontakt.
- **Avvis** -- forespørselen forkastes.
- **Blokker** -- personen kan ikke sende deg flere forespørsler.

### Aldri bruke som fast nabo

I menyen til en kontakt finner du bryteren **«Aldri bruke som fast nabo»**
(standard: av). Er den på, videresender ikke denne kontakten meldinger for
deg og får derfor heller ikke vite når du sender eller mottar meldinger. Dette
er ment for det tilfelle at fare truer deg fra ditt eget miljø.

Fra ukjente (verken kontakt eller medlem av en felles gruppe) slipper Cleona
ingenting gjennom bortsett fra en slik forespørsel -- ingen melding, ingen
anrop, ingen fil. Og selv forespørselen kommer kun
fram hvis avsenderen først har løst en liten regneoppgave. Det gjør massespam
dyrt.

### Verifiseringsnivåer

Cleona viser deg hvor sikkert en kontakts identitet er bekreftet:

| Nivå | Betydning |
|------|-----------|
| Ikke verifisert | Dere er koblet sammen, men ingenting bekrefter at det virkelig er riktig person bak. |
| Sett | Nøkkelutvekslingen var vellykket, dere kan kommunisere kryptert. |
| Verifisert | Dere har møttes personlig og koblet sammen via kammeraskann eller NFC. |
| Klarert | Du har uttrykkelig markert denne kontakten som tillitsverdig. |

«Verifisert» finnes kun for personlig utveksling. En invitasjon som kom via
en chat eller på e-post når aldri dette nivået -- selv om den inneholder de
samme dataene.

Endres nøklene til en kontakt uten forvarsel, setter Cleona vedkommende tilbake
til «Ikke verifisert». Det beskytter deg mot at noen ubemerket utgir seg for å
være kontakten din.

---
## 4. Meldinger

### Sende og motta tekst

Skriv bare meldingen din i tekstfeltet nederst og trykk Enter eller
send-knappen. Meldingen din krypteres automatisk før den forlater enheten din.

Innkommende meldinger dukker opp i chathistorikken.

### Hva symbolene på meldingen din betyr

| Symbol | Betydning |
|--------|-----------|
| Klokke | Meldingen er opprettet, men ennå har ingen rute båret den. |
| Én hake | Meldingen er på vei. Dette gjelder også så lenge den venter i postkassen på motparten din. |
| To haker | Levert: Motpartens enhet har bekreftet mottaket. |
| Advarselstegn | Ingen rute har båret meldingen på 14 dager. Trykk på den for å sende på nytt. |

**Frakoblet er ingen feil.** Er motparten din ikke tilgjengelig, blir
meldingen værende på én hake til den hentes -- den er ikke tapt. Har enheten
din selv ingen forbindelse, blir meldingen værende på klokken og går av gårde
av seg selv så snart det igjen finnes en rute. Advarselstegnet vises først når
den ikke har funnet noen rute på 14 dager; da kan du sende den på nytt.

Dette gjelder også en iPhone der appen ikke er åpen: Meldingen venter i
postkassen til iOS vekker appen kort, eller til motparten din åpner den. Det
kan ta lenger tid enn på andre enheter.

To haker finnes kun når mottakeren selv bekrefter mottaket. Denne kvitteringen
er kryptert og signert -- ingen på veien kan forfalske den for å lure deg til
å tro at meldingen er levert.

### Sende bilder, videoer og filer

Du har flere muligheter:

- **Binders-ikon** i tekstfeltet: Trykk på det for å velge en fil, et bilde
  eller en video fra galleriet ditt eller filsystemet ditt.
- **Dra og slipp** (datamaskin): Dra enkelt en fil inn i chattevinduet.
- **Lim inn fra utklippstavlen** (datamaskin): Kopier et bilde og lim det inn
  i chatten.

Små filer (under 256 KB) følger med direkte i meldingen. Større filer deles
opp i biter og utstyres med feilretting, slik at enkelte tapte biter ikke
gjør noe. Er dere begge på nett, strømmes de over en nabo; ellers legges de
hos enheter som stadig er tilgjengelige, til motparten din henter dem.

Fra 256 KB spør Cleona deg per fil før den sendes: En stor fil kan ikke ta
ruten til meldingene dine. Innholdet dens forblir kryptert, og motparten din
får ikke vite internettadressen din. Men overføringen er synbar utenfra som
en hendelse, og en fremmed enhet som videresender eller oppbevarer den, ser
hvem som laster opp og hvem som henter. Samtykket ditt gjelder kun for denne
ene filen.

### Talemeldinger

1. Hold mikrofon-knappen i tekstfeltet nede.
2. Snakk inn meldingen din.
3. Slipp knappen for å sende meldingen.

Er talegjenkjenning aktivert på enheten din (se innstillinger), blir
talemeldingen din automatisk transkribert til tekst. Motparten din ser da
både opptaket og den transkriberte teksten.

### Svar på meldinger (sitere)

For å svare på en bestemt melding:

1. Åpne tre-punkts-menyen ved siden av meldingen.
2. Velg «Svar».
3. Over tekstfeltet dukker det opp et banner med den siterte meldingen.
4. Skriv svaret ditt og send det.

Den siterte meldingen vises i svaret ditt, slik at sammenhengen er tydelig.

### Redigere og slette meldinger

- **Rediger:** Tre-punkts-menyen til meldingen, deretter «Rediger». Endre
  teksten og send den på nytt. Motparten din ser at meldingen ble redigert.
  Redigering er mulig innen 15 minutter etter sending.
- **Slett:** Tre-punkts-menyen til meldingen, deretter «Slett». Meldingen
  fjernes hos deg og hos motparten din. Du kan slette dine egne meldinger
  når som helst -- det finnes ingen tidsramme for sletting.

### Emoji-reaksjoner

I stedet for å skrive et svar kan du reagere på en melding med en emoji:

1. Åpne tre-punkts-menyen eller hold meldingen lenge nede.
2. Velg en emoji fra hurtigvalget, eller åpne emoji-velgeren for hele
   utvalget.
3. Reaksjonen din dukker opp under meldingen.

### Kopiere tekst

Via tre-punkts-menyen til en melding kan du kopiere meldingsteksten til
utklippstavlen.

### Søke i meldinger

Øverst i chattevinduet finner du søkefunksjonen. Skriv inn et søkeord, og
Cleona viser deg alle treff i den gjeldende chatten. Med piltastene kan du
hoppe frem og tilbake mellom treffene.

På startsiden finnes i tillegg et søkefilter på tvers av fanene, som lar deg
søke gjennom alle samtalene etter et begrep.

### Forhåndsvisning av lenker

Når du sender en lenke, genererer Cleona automatisk en forhåndsvisning (tittel,
beskrivelse, forhåndsvisningsbilde). Denne forhåndsvisningen lages av enheten
din og sendes med -- motparten din trenger ikke å opprette forbindelse til
den lenkede nettsiden for det.

Hva et trykk på en mottatt lenke gjør, stiller du inn i innstillingene under
«Åpne lenker»: «Normalt», «Foretrekk privat vindu» (der enheten ikke kan åpne
et privat vindu, åpnes lenken normalt) eller «Spør hver gang».

---

## 5. Grupper

### Opprette en gruppe

1. Bytt til fanen «Grupper».
2. Trykk på pluss-knappen.
3. Gi gruppen et navn.
4. Velg kontaktene du vil invitere.
5. Trykk på «Opprett».

De inviterte kontaktene får et varsel og kan bli med i gruppen.

### Hvordan gruppe meldinger er beskyttet

I en gruppe med opptil 16 medlemmer sender Cleona hver melding til hvert
medlem enkeltvis -- kryptert kun for dette medlemmet, akkurat som om du hadde
skrevet en egen melding til hver og en. Hakene på en gruppe melding viser statusen til
det medlemmet den har kommet minst langt med.

Vokser gruppen over 16 medlemmer, bruker den en felles nøkkel. Den endres
hver dag og trekkes på nytt når et medlem går ut eller fjernes; et nytt
medlem leser bare fra sitt inntreden. Der viser ikke hakene lenger statusen
til hvert medlem, men at meldingen er lagt i nettverket. Synker gruppen til
12 eller færre medlemmer, går den tilbake til enkeltforsendelse.

### Bilder i grupper og kanaler

I innstillingene til en gruppe eller en kanal bestemmer du med «Last alltid
inn bilder» om bilder lastes inn umiddelbart eller først når du trykker på
et av dem.

### Invitere medlemmer

Også etter opprettelsen kan du invitere flere kontakter:

1. Åpne gruppeinformasjonen (tre-punkts-meny i gruppeoversikten eller øvre
   linje i gruppe-chatten).
2. Trykk på «Inviter».
3. Velg kontaktene du vil legge til.

### Roller

Hver gruppe har tre roller:

- **Eier (Owner):** Har full kontroll. Kan legge til og fjerne medlemmer,
  utnevne administratorer og administrere gruppen. Eieren kan også overføre
  sin status til et annet medlem.
- **Admin:** Kan fjerne medlemmer og hjelpe til med administrasjonen.
- **Medlem:** Kan lese og skrive meldinger.

### Forlate en gruppe

1. Åpne tre-punkts-menyen i gruppeoversikten.
2. Velg «Forlat».
3. Bekreft avgjørelsen din.

Når du forlater en gruppe, forblir dine tidligere meldinger synlige for de
andre medlemmene.

---

## 6. Offentlige kanaler

### Hva er kanaler?

Kanaler er offentlige diskusjonsforum innenfor Cleona-nettverket. I motsetning
til grupper kan alle lese med her uten å måtte bli invitert. Kun eieren og
administratorer kan publisere innlegg -- abonnentene leser med.

### Finne og bli med i kanaler

1. Bytt til fanen «Kanaler».
2. Åpne fanen «Søk».
3. Søk i de tilgjengelige kanalene etter navn eller tema.
4. Trykk på en kanal og deretter på «Abonner».

Kanaler kan filtreres etter språk. Noen kanaler er merket som «Ikke
mindreårige» -- disse er kun synlige hvis du i profilen din har bekreftet at
du er over 18.

### Opprette egen kanal

1. Bytt til fanen «Kanaler».
2. Trykk på pluss-knappen.
3. Skriv inn et kanalnavn (må være unikt i hele nettverket).
4. Velg språk og om kanalen skal være offentlig eller privat.
5. Valgfritt: Legg til en beskrivelse og et bilde.
6. Trykk på «Opprett».

For offentlige kanaler kan du angi om innholdet klassifiseres som «Ikke
mindreårige».

### Melde innhold

Legger du merke upassende innhold i en offentlig kanal, kan du melde det.
Cleona bruker et desentralisert modereringssystem: Meldinger vurderes av
tilfeldig utvalgte medlemmer av nettverket (en slags «jury»). Finner den en
overtredelse, får kanalen en advarsel. Ved gjentatte overtredelser nedgraderes
den i søkeindeksen eller blokkeres.

### Systemkanaler

Cleona har to innebygde systemkanaler:

- **Bug Log:** Når Cleona oppdager en feil, spør den deg om du vil sende en
  feilrapport; først ser du nøyaktig hva som offentliggjøres. Disse rapportene
  havner i Bug Log-kanalen, der de kan ses av fellesskapet. En rapport bærer
  intet navn og intet innhold fra samtalene dine, men et pseudonym. I betaen
  nevner den i tillegg identifikatoren din (bruker-ID), slik at utviklerne
  kan følge opp. Du kan også sende en logg-rapport manuelt (med
  forhåndsvisningsdialog og uttrykkelig samtykke).
- **Feature Requests:** Her kan brukere sende inn funksjonsønsker og stemme
  over eksisterende forslag. Forslagene sorteres etter stemmer.

Hver datamaskin holder opptil 25 MB per systemkanal, hver telefon opptil 5 MB;
er det fullt, går det eldste først -- aldri det du selv allerede har sett.

---
## 7. Anrop

### Starte et taleanrop

1. Åpne chatten med kontakten du vil ringe.
2. Trykk på telefon-symbolet i den øvre linjen.
3. Vent til motparten din tar anropet.

Under samtalen ser du en tidslinje, samtaleslengden og har tilgang til
demping og høyttaler.

For å legge på trykker du på den røde legg-på-knappen.

Ser du «Ikke tilgjengelig», kan ikke enheten til motparten din nås akkurat
nå, for eksempel en iPhone der appen ikke er åpen. Send en melding i stedet.

### Starte et videoanrop

1. Åpne chatten med kontakten.
2. Trykk på kamera-symbolet i den øvre linjen.
3. Videobildet ditt vises i et lite vindu, motparten sitt bilde i det store
   feltet.

Du kan bytte mellom front- og bak-kamera under samtalen.

### Innkommende anrop

Når noen ringer deg, dukker det opp et varselvindu med ringerens navn. Du kan:

- **Ta imot** -- samtalen begynner.
- **Avvis** -- ringeren får beskjed.

Er du akkurat i en samtale, ringer det ikke ved et nytt anrop; i stedet får
du en melding «Tapt anrop». Det samme gjelder et gruppeanrop du ikke tok --
meldingen står da i gruppe-chatten.

Ringer noen en av identitetene dine som akkurat ikke vises, ringer det
likevel; anropsskjermen oppgir hvilken av identitetene dine som ringes.

På iPhone ringer det bare mens appen er åpen. Den som ringer deg mens den
ikke er åpen, ser «Ikke tilgjengelig» etter 10 sekunder. Så snart du åpner
appen, finner du en melding om tapt anrop.

### Gruppeanrop

Du kan også gjennomføre gruppeanrop der flere personer deltar samtidig. Anropet
organiseres via et intelligent videresendingstre, slik at ikke enhver deltager
behøver å være direkte forbundet med enhver annen. Alle samtaler er kryptert
hele veien.

Hvert gruppemedlem kan starte et gruppeanrop. To deltagere som ikke er
hverandres kontakter, ser aldri den andres internettadresse: Lyden og bildet
deres går via en deltager som har kontakt med begge. Finnes det ingen slik,
er de to ikke forbundet, og flisen sier «Ingen felles kontakt i samtalen».
Er en videresending overbelastet, blir lyden værende, og videoen faller bort
for dette paret.

### Kryptering ved anrop

Alle anrop krypteres med engangsnøkler som kun eksisterer i løpet av samtalen.
Etter at du har lagt på, slettes disse nøklene umiddelbart. Ingen kan
etterpå dekryptere en samtale som har funnet sted.

Ærlig talt: Anrop går, der det er mulig, direkte mellom enhetene, for
allerede en liten forsinkelse er forstyrrende når man snakker. I motsetning
til ved meldinger kan derfor internettleverandøren din, under et anrop, se
hvilken internettadresse du er forbundet med. Hva dere sier, ser den ikke.

Under et anrop ser også kontakten din internettadressen din. Vil du ikke ha
det ved en kontakt, slå «Tillat anrop» av i menyen dens (standard: på). Slår
du det av senere, forblir en allerede sett adresse kjent for vedkommende.

---

## 8. Kalender

Cleona inneholder en innebygd kalender som fungerer kryptert og helt
desentralt -- uten skytjeneste.

### Visninger

Kalenderen tilbyr fem visninger: dag, uke, måned, år og en oppgavevisning.
Bytt mellom dem via fanene øverst på kalenderskjermen.

### Opprette avtaler

Trykk på et tidsrom eller bruk legg-til-knappen for å opprette en ny avtale.
Du kan angi tittel, dato, klokkeslett, sted og notater. Avtaler lagres
kryptert på enheten din.

### Gjentakende avtaler

Avtaler kan gjentas daglig, ukentlig, månedlig eller årlig. Du kan tilpasse
mønsteret (f.eks. annenhver tirsdag, den første i hver måned) og sette en
sluttdato eller et antall gjentakelser.

### Invitere kontakter

Ved oppretting eller redigering av en avtale kan du invitere Cleona-kontaktene
dine. De mottar en kryptert kalenderinvitasjon og kan svare med ja, nei eller
kanskje. Endringer i avtalen sendes automatisk til alle inviterte.

### Ledig/opptatt-visning

Du kan dele tilgjengeligheten din med kontakter uten å røpe avtaledetaljer.
Det finnes tre personvernnivåer: fulle detaljer, kun tidsblokker eller skjult.
Du kan sette en standard og overstyre den per kontakt.

### Påminnelser

Avtaler kan ha påminnelser som utløser et systemvarsel før avtalen starter.
Du kan slumre påminnelser ved behov.

### Ekstern kalendersynkronisering

Cleona kan synkronisere med eksterne kalendertjenester:

- **CalDAV** -- Koble til enhver CalDAV-kompatibel server (Nextcloud,
  Radicale osv.).
- **Google Kalender** -- Synkronisering via Google Calendar API med sikker
  OAuth2-autentisering.
- **Lokal CalDAV-server** -- Cleona kan starte en lokal CalDAV-server på
  enheten din, slik at kalenderapper for datamaskin (Thunderbird, Outlook,
  Apple Kalender, Evolution) kan synkronisere med Cleona-kalenderen din.
- **Android-systemkalender** -- Avtaler fra Cleona kan overføres til den
  innebygde kalenderappen på Android-enheten din.
- **ICS-filer** -- Importer og eksporter avtaler i standardformatet iCalendar.

### PDF-eksport

Du kan skrive ut eller eksportere enhver kalendervisning (dag, uke, måned, år)
som et PDF-dokument.

---

## 9. Avstemninger

Du kan opprette avstemninger i enhver chat eller gruppe for å innhente
meninger eller planlegge datoer.

### Avstemningstyper

Cleona støtter fem typer avstemninger:

- **Enkeltvalg** -- Deltagerne velger ett alternativ.
- **Flervalg** -- Deltagerne kan velge flere alternativer.
- **Datoavstemning** -- Finn en dato som passer for alle. Hver deltager
  markerer datoer som tilgjengelig, kanskje eller ikke tilgjengelig.
- **Skala** -- Vurder noe på en numerisk skala (f.eks. 1 til 5).
- **Fritekst** -- Deltagerne skriver sitt eget svar.

### Opprette en avstemning

Åpne en chat og trykk på avstemning-symbolet (eller bruk vedleggsmenyen).
Velg avstemningstype, formuler spørsmålet ditt og alternativene, og send
avstemningen. Den dukker opp som en melding i chatten.

### Stemme

Trykk på en avstemning for å avgi stemmen din. Du kan endre eller trekke
tilbake stemmen din når som helst.

### Anonym avstemning

Avstemninger kan konfigureres for anonym stemming. Når dette er aktivert, er
stemmene kryptografisk anonyme -- ingen, ikke engang avstemningens oppretter,
kan se hvem som stemte på hva. Stemmeantallet forblir likevel synlig.

### Datoavstemning til kalenderen

Når en datoavstemning er avsluttet, kan vinnerdatoen med ett trykk gjøres om
til en kalenderoppføring.

---
## 10. Flere identiteter

### Hvorfor flere identiteter?

Tenk deg at du vil skille arbeidslivet og privatlivet ditt -- i likhet med to
ulike telefonnumre, men uten en annen telefon. I Cleona kan du bruke flere
identiteter på én enhet. Hver identitet har sitt eget navn, sitt eget
profilbilde, egne kontakter og egne samtaler.

### Opprette en ny identitet

1. I den øvre linjen ser du din gjeldende identitet som en fane.
2. Trykk på pluss-tegnet (+) til høyre for identitets-fanene dine.
3. Skriv inn et navn for den nye identiteten.
4. Ferdig -- den nye identiteten er umiddelbart aktiv.

### Bytte mellom identiteter

Trykk enkelt på identitets-fanen i den øvre linjen. Byttet er umiddelbart --
ingen ventetid, ingen omlasting.

### Alle kjører samtidig

Et viktig poeng: Alle identitetene dine er aktive samtidig. Selv om du akkurat
nå vises som «Arbeid», mottar «Privat»-identiteten din fortsatt meldinger.
Du går ikke glipp av noe, uansett hvilken identitet du akkurat har valgt.

### Identitets-detaljsiden

Når du trykker på fanen til din akkurat aktive identitet, åpnes detaljsiden.
Her kan du:

- Vise QR-koden din for kontakter.
- Endre eller fjerne profilbildet ditt.
- Legge til en profilbeskrivelse.
- Endre visningsnavnet ditt.
- Velge et design (skin) for denne identiteten.
- Slette identiteten, dersom du ikke lenger trenger den.

### Slette en identitet

Når du sletter en identitet, blir kontaktene dine varslet om det. Identiteten
og alle tilknyttede data fjernes fra enheten din. Denne prosessen er ikke
reversibel.

---

## 11. Flere enheter

### Én identitet, én enhet -- inntil videre

En identitet kjører i dag på én enhet. En annen enhet for samme identitet
kommer i en senere versjon; i innstillingene under «Enheter» -> «Administrer
enheter» står «Koble til en annen enhet» derfor ennå som «Ikke tilgjengelig
ennå».

Når det kommer, gjelder: Alle enheter er likestilte, det finnes ingen
hovedenhet. En annen enhet setter du opp med dine 24 ord, og én av enhetene
dine hittil samtykker. Høyst 5 enheter.

Skriver du i dag inn dine 24 ord på en ny enhet, flytter du: Identiteten
gjenopprettes på den nye enheten, og den forrige enheten din fjerner den
etterpå hos seg (se kapittel 12).

På flere enheter kan du i dag bruke ulike identiteter (kapittel 10).

### Roter nøkler

Mistenker du at noen har fått tak i nøklene dine, kan du under «Administrer
enheter» -> «Roter nøkler» generere nye nøkler. Kontaktene dine varsles, og
dine åpne invitasjoner trekkes tilbake. Viktig: Etterpå gjenoppretter de 24
ordene alene bare de gamle nøklene. Opprett derfor en ny gjenopprettingspakke
rett etterpå; gjenopprette kan du da bare sammen med denne pakken.

---

## 12. Gjenoppretting

### Bruke seed-frasen

Når du mister enheten din eller setter opp en ny:

1. Installer Cleona på den nye enheten.
2. Velg «Gjenopprett» ved oppstart.
3. Skriv inn dine 24 ord.
4. Cleona gjenoppretter alle identitetene dine fra dem -- med de samme
   nøklene som før. For kontaktene dine er du det samme mennesket.

### Hva som kommer tilbake -- og hva som ikke gjør det

Identiteten din sitter i de 24 ordene, kontaktene dine og historikken din
gjør det ikke. Tilbake kommer din tilgang til nettverket via
**gjenopprettingspakken**: Enheten din legger en liten, kryptert pakke i
nettverket. Kun dine 24 ord kan finne og åpne den. I den står det den nye
enheten din trenger for å nå kontaktene dine igjen, og det som i mellomtiden
lå for deg i nettverket. Da behøver ingen kontakt å være på nett.

En gjenoppretting bringer ikke den tidligere chathistorikken tilbake.

Gjenopprettingspakken lever i 7 dager og fornyes av enheten din så lenge den
kjører; i innstillingene ser du til når den gjelder. Har ingen av enhetene
dine kjørt på mer enn 7 dager, er den utløpt. Da gjenoppretter de 24 ordene
identiteten din likevel, men kontaktene dine må du invitere på nytt; det som
i mellomtiden lå for deg i nettverket, er tapt.

### Å gjenopprette betyr å flytte

Finner den forrige enheten din senere ut at identiteten er gjenoprettet et
annet sted, fjerner den den hos seg -- med historikken dens. Derfor: Den som
har dine 24 ord, kan på denne måten hente identiteten din fra enheten din.
Til alle kontaktene er tilbake, påminner appen deg; med «Fullfør og forny
nøklene» avslutter du gjenopprettingen selv.

### Hva ingen kan gjenopprette

Dette er viktig, og vi sier det derfor tydelig:

- **Ingen andre enn deg kan gjenopprette identiteten din.** Ikke utvikleren,
  ikke en kundestøtte, og heller ikke kontaktene dine -- uansett hvor mange
  de er. Det finnes ingen hovednøkkel og ingen del av nøkkelen din som er
  deponert hos andre.
- **Har du mistet de 24 ordene og ikke har noen enhet igjen, er identiteten
  din tapt.** Da gjenstår kun å opprette en ny og invitere kontaktene dine på
  nytt.

Den beste beskyttelsen: Skriv ned de 24 ordene på papir og oppbevar dem trygt.

---
## 13. Innstillinger

Du når innstillingene via tannhjul-symbolet i øvre høyre hjørne.

### Varsler og ringetoner

- Velg mellom seks ulike ringetoner for innkommende anrop.
- Still inn en meldingslyd.
- På Android-enheter kan du i tillegg slå vibrasjon på eller av.
- **«Demp alt»** lar ingen melding lenger ringe, vibrere eller melde seg på
  denne enheten -- for alle identitetene. Anrop ringer fortsatt.
- **«Stille timer»** legger du fast per identitet med fra/til. I denne tiden
  ringer, vibrerer eller melder ingen melding fra denne identiteten seg;
  meldingene kommer likevel frem.
- **«Varsler uten innhold»** (standard: av) viser bare at en melding,
  invitasjon eller påminnelse er kommet -- uten avsender, navn og tekst.
  Anrop viser fortsatt navnet.
- Det som kommer på én gang etter oppstart, melder Cleona i en samlet melding
  («5 nye meldinger i 2 samtaler»); alt senere enkeltvis. Et trykk på et
  meldingsvarsel åpner samtalen, også i en annen identitet.

### Design (skins)

Cleona tilbyr ti ulike design: Teal, Ocean, Sunset, Forest, Amethyst, Fire,
Storm, Slate, Gold og Contrast. Contrast-designet oppfyller det høyeste
tilgjengelighetsnivået (WCAG AAA) og er spesielt lett å lese ved nedsatt
syn.

Hver identitet kan ha sitt eget design. Du endrer designet på
identitets-detaljsiden (trykk på den aktive identitets-fanen).

I tillegg kan du i innstillingene under «Utseende» bytte mellom lyst, mørkt
og system-tema.

### Endre språk

Cleona er tilgjengelig på 34 språk, deriblant språk med høyre-til-venstre-skrift
(f.eks. arabisk, hebraisk). Endre språket i innstillingene under «Språk».

### Mediearkivering

Har du et nettverkslag (NAS) eller en delt mappe hjemme, kan Cleona automatisk
utelagre mediene dine dit. SMB, SFTP, FTPS og WebDAV støttes.

Slik fungerer det trinnvise lagringet:
- De første 30 dagene: Alt blir værende på enheten din.
- Etter 30 dager: Et forhåndsvisningsbilde blir værende på enheten, originalen
  arkiveres.
- Etter 90 dager: Bare et lite forhåndsvisningsbilde blir værende på enheten.
- Etter ett år: Bare en plassholder gjenstår, originalen ligger trygt i
  arkivet.

Du kan når som helst trykke på et arkivert medium for å hente det tilbake --
forutsatt at du er koblet til hjemmenettverket ditt. Spesielt viktige medier
kan festes slik at de aldri utelagres.

Under «Lagringsbudsjett» legger du fast hvor mange MB medier som blir
værende på enheten (standard: 100 MB på telefonen, 2 GB på datamaskinen).
Er det fullt, arkiveres først det eldste mediet som ikke er festet. Slettes
gjør et original bare når det ligger trygt i arkivet -- tekstmeldinger blir
alltid bevart.

### Transkripsjon for talemeldinger

Når dette er aktivert, gjøres talemeldingene dine om til tekst lokalt på
enheten din (med åpen-kilde-modellen Whisper). Den transkriberte teksten sendes
sammen med opptaket til motparten din. Transkripsjonen skjer fullstendig på
enheten din -- ingen data går til eksterne tjenester.

Hvilken modell (tiny, base, small) som lastes ned, stiller du inn én gang
for enheten; språket (automatisk eller fast) per identitet.

### Automatisk nedlasting

Du kan angi fra hvilken størrelse medier skal lastes ned automatisk. Slik kan
du for eksempel la bilder laste automatisk, men ta stilling manuelt til store
videoer.

### Enheter

Under «Enheter» -> «Administrer enheter» ser du denne enheten. Å koble til
en annen enhet kommer i en senere versjon (kapittel 11).

### Nettverk

Cleona trenger ingen nettverksinnstillinger for å fungere. Det finnes tre
nettbrytere:

- **Portvideresending på ruteren** (standard: på). Cleona ber din egen ruter
  om å åpne en dør for Cleona. Lykkes det, er enheten din bedre tilgjengelig
  for andre og hjelper nettverket. Cleona snakker da kun med ruteren din, ikke
  med internettet.
- **Offentlige adresseoppføringer** (standard: på). Har enheten din ennå for
  få naboer, slår den opp flere inngangspunkter i en offentlig katalog (Nostr),
  og er den selv godt tilgjengelig, registrerer den seg der. Oppføringen
  inneholder en adresse, intet navn og ingen kontakt. Slår du den av, finner
  enheten din naboer kun via invitasjoner, det lokale nettet og de naboene
  den allerede kjenner.
- **Færre dekkpakker på Wi-Fi** (standard: av). På Wi-Fi eller med kabel kan du
  slå av de tomme dekkpakkene. Da er det imidlertid igjen synbart når du
  skriver. På mobildata finnes det ingen slik bryter -- der sender Cleona
  uansett bare én dekkpakke i minuttet.

Dekktrafikken som helhet kan ikke slås av. Det er med vilje: Bare når den alltid
kjører, sier aktiviteten til enheten din ingenting om hvorvidt du akkurat
skriver.

Over de tre bryterne står **datasparemodusen**: På mobildata foreslår Cleona
den, men slår den aldri på selv. Den sparer data, men til gjengjeld er
enheten din lettere å kjenne igjen utenfra.

Under det stiller du inn **«Hurtigbuffer for andres medier»**: Enheten din
holder krypterte deler av andres medier i opptil 7 dager, slik at de når
mottakerne sine (standard: 100 MB på telefonen, 1 GB på datamaskinen). En
mindre størrelse frigir plassen umiddelbart -- de eldste delene først.

---

## 14. Sikkerhet

### Hva betyr post-kvantum-kryptering?

Dagens kryptering bygger på matematiske problemer som er ekstremt vanskelige
å løse for vanlige datamaskiner. Kvantedatamaskiner vil kunne løse noen av
disse problemene raskt i fremtiden. Post-kvantum-kryptering bruker
tilleggsmetoder som også holder stand mot kvantedatamaskiner.

Cleona kombinerer begge tilnærminger: klassisk kryptering for pålitelighet og
post-kvantum-metoder for fremtidssikring. Slik er du beskyttet mot dagens og
fremtidige trusler samtidig.

For hver enkelt melding genereres en egen nøkkel. Selv om en angriper ville
knekke nøkkelen til én melding, kunne vedkommende ikke lese noen annen melding
med den.

### Hvorfor ingen server er tryggere

Ved vanlige meldingstjenester går meldingene dine via leverandørens servere.
Selv om de kanskje er krypterte der: Leverandøren har tilgang til metadata
(hvem kommuniserer med hvem, når, hvor ofte, hvorfra) og må muligens gi dem
ut ved dommerkjennelse.

Hos Cleona finnes det intet slikt sentralt punkt. Det finnes ingen plass der
alle metadata samles, og ingen katalog der man kunne slå opp hvem du er eller
hvem du kjenner.

### Hvem ser at du skriver med noen?

Kryptering beskytter **hva** du skriver. Like viktig er det at ingen enkelt
observatør får vite **med hvem** og **når** du skriver. Det sørger Cleona for
slik:

- **På internettet aldri direkte.** Sendte enheten din en melding direkte til
  motpartens internettadresse, kunne leverandøren din se hvem du skriver med.
  Derfor går en melding på internettet alltid via de faste naboene deres: din
  og motpartens.
- **Naboer du stoler på.** De faste naboene dine er, der det er mulig, enheter
  til dine egne kontakter -- opptil tre som akkurat er tilgjengelige utenfra.
  Faller én bort, rykker en annen kontakt opp. En kontakt lar seg ikke kjøpe
  med servere; en hvilken som helst node i nettverket gjør det. Har du ennå
  ingen tilgjengelig kontakt, tar Cleona en annen nabo. Din invitasjon nevner
  aldri noen av kontaktene dine, slik at ingen gjennom dem får vite adressen
  til en venn.
- **Koder i stedet for navn.** Naboene ser ingen navn og ingen identifikatorer,
  men kun en kode. Den gjelder for nettopp dere to, i én retning, for én dag
  -- neste dag er det en annen. Naboen din vet hvor pakken kommer fra, men ikke
  hvor den til slutt går. Motpartens nabo vet hvor den går, men ikke hvor den
  kom fra. Normalt ser ingen på veien begge ender.
- **Dekktrafikken.** Enheten din sender hele tiden, i ujevne mellomrom,
  dekkpakker til sine naboer. De er akkurat like store som ekte pakker, går
  over samme port og kan ikke skilles fra dem utenfra. Hvorvidt et menneske
  akkurat skriver eller enheten bare kjører, kan ikke sees av det. Meldingene
  dine venter aldri på dekktrafikken -- de går umiddelbart av gårde, den går
  bare ved siden av.

**Hva dekktrafikken koster:** På Wi-Fi rundt 13 MB om dagen. På mobildata
sender Cleona bare én dekkpakke i minuttet, det er ca. 1,7 MB om dagen. Grunnen
til begrensningen på mobildata er ikke datamengden, men batteriet: Hver pakke
vekker radio-modemet.

**Hva Cleona ikke kan skjule** -- ærlig talt:

- Ingen **enkel** observatør ser hvem som skriver med hvem -- verken
  leverandøren din eller nodene på veien. Den som derimot overvåker **begge
  ender samtidig**, for eksempel en stat som overvåker din og motpartens
  tilknytning eller stiller begge naboer, kan over tid knytte det sammen: Pakke
  ut hos deg, kort tid etterpå pakke inn hos motparten. Gjentas det ofte nok,
  gir det en forbindelse.
- Dekktrafikken gjør denne sammenkobling vanskeligere, men forhindrer den ikke.
  Den skjuler enkelte meldinger, ikke mengden: Den som sender mye, øker den
  totale trafikken til enheten sin.
- En kontakt som er din faste nabo, får vite **når** og **hvor mye** du sender
  og mottar -- ikke med hvem og ikke hva. Kommer faren fra ditt eget miljø,
  kan du frita enhver kontakt fra det (se kapittel 3, «Aldri bruke som fast
  nabo»).
- Har to nye brukere kun samme ene nabo, går meldingen deres via akkurat denne
  noden, og den ser begge ender. Så snart en av de to har flere naboer, er det
  slutt.
- Invitasjonen din inneholder internettadressene dine. Den som har tekstlinjen,
  ser hvor du er på nett -- gi den kun til mennesker du stoler på i så måte.
- En nabo som videresender ser at to koder utveksler pakker -- ikke hvem som
  står bak, og ikke hva som er inni.
- Et signal fra et pågående anrop kan, når den første naboen akkurat ikke
  svarer, gå via en node som ser begge ender; den får vite at dere ringer
  sammen.
- En stor fil du har samtykket til, ser datamaskinen som videresender eller
  oppbevarer den, i begge ender (se kapittel 4).
- For anrop gjelder ikke beskyttelsen mot leverandøren, og kontakten din ser
  internettadressen din (se kapittel 7).

### Hva skjer når motparten din er frakoblet?

1. Cleona starter alle egnede ruter samtidig: i samme Wi-Fi direkte, på
   internettet via to naboer -- og i tillegg postkassen.
2. For postkassen legger Cleona den krypterte meldingen hos tre naboer. Så
   snart to har bekreftet mottaket, gjelder den som lagt.
3. Cleona velger for dette fortrinnsvis naboer der motparten din også slår opp
   -- først naboen som invitasjonen dens nevner.
4. Meldingen venter der i opptil 7 dager. Når motparten din kommer tilbake,
   henter vedkommende den og bekrefter mottaket til deg. Først da ser du to
   haker.

Kun motparten din kan tømme postkassen: Henting og sletting går kun med en
nøkkel som bare vedkommende har, og sletting skjer først når vedkommende har
bekreftet mottaket. Naboene ser bare krypterte pakker under en verdi som
veksler hver dag.

### Fremmede slipper ikke gjennom

Fra noen som verken er kontakten din eller medlem av en felles gruppe, tar
Cleona imot nøyaktig to ting:
forespørselen om dine offentlige nøkler, så lenge en av invitasjonene dine er
åpen, og en kontaktforespørsel. Forespørselen må bære en gyldig invitasjon fra
deg, og avsenderen må på forhånd ha løst en regneoppgave. Alt annet --
meldinger, anrop, filer -- forkastes før det overhodet når appen. Den som kun
har det trykte visittkortet ditt, kan altså ikke bare ringe deg. Et medlem av
en felles gruppe når deg bare i denne gruppen -- med gruppemeldinger og
gruppeanrop, aldri enkeltvis.

### Anti-sensur

Cleona er bygget slik at den er vanskelig å blokkere:

- **Ingen server, ingen fast adresse.** Det står ingen adresse i appen som
  man kunne sperre, og nettverket er ikke avhengig av noen enkelt node.
- **Ingen fast port.** Hver enhet velger en tilfeldig port ved første oppstart.
  Det finnes ingen kjent portnummer som man kunne gjenkjenne Cleona-trafikk
  ved.
- **Som tilfeldige data.** Oppkoblingen mellom to enheter er kodet slik at
  den ikke kan skilles fra tilfeldige data.
- **Mange innganger.** Hver invitasjon, hver nabo og hver enhet i samme Wi-Fi
  er en mulig rute tilbake inn i nettverket.

### Sikker nøkkellagring

På støttede plattformer lagrer Cleona krypteringsnøklene dine i operativsystemets
sikre nøkkelring (Android Keystore, iOS Keychain, macOS Keychain). Der det er
tilgjengelig, tilbyr det maskinvarestøttet beskyttelse for nøklene dine.

### Databasekryptering

Meldingene og samtalene dine ligger i en kryptert database -- en egen for hver
identitet, hver med sin egen nøkkel. Det er ikke bare selve databasen som er
kryptert, men også dens mellomfiler; ingenting skrives ukryptert til disken,
ikke engang kortvarig. Innstillinger, kontakter og medier er også lagret
kryptert.

Nøklene avledes fra dine 24 ord og eksisterer kun på enheten din. Selv den som
får enheten din i hendene og leser ut dataene, finner uten disse nøklene kun
ulesbare data.

Ukryptert blir det bare der du selv fører innhold ut av Cleona:
- når du lagrer en fil fra en chat på enheten din,
- når du legger et bilde i bildene dine med skjermbilde-knappen,
- når du deler noe med en annen app,
- når du setter opp mediearkivering (kapittel 13): De arkiverte originalene
  ligger ukryptert på nettverkslageret ditt hjemme, slik at du kan åpne dem
  der også uten Cleona,
- når du speiler avtaler i Android-systemkalenderen: Der kan andre apper med
  kalendertilgang lese dem.

Det som er ført ut på denne måten, slettes ikke med meldingen og utløper
ikke med den.

### Beskyttelse på skjermen

På Android, Windows og macOS tillater ikke Cleona skjermopptak fra andre
apper. Trenger du et bilde, bruk skjermbilde-knappen i den øvre linjen: Den
legger bildet i bildene dine -- ukryptert. I en samtale der videresending
ikke er tillatt, finnes det ikke noe skjermbilde.

---

## 15. Programvareoppdateringer

### Hvordan får jeg oppdateringer?

Cleona kan oppdateres på ulike veier. Målet er at du skal kunne motta
oppdateringer også når enkelte distribusjonskanaler svikter eller blokkeres:

1. **App Store / Play Store:** Så snart Cleona dukker opp der og du har
   installert den via en butikk, mottar du oppdateringer via butikken som
   vanlig. På iPhone kommer oppdateringer via TestFlight.
2. **GitHub Releases:** På prosjektets GitHub-side finner du signerte
   installasjonspakker for alle plattformer.
3. **Oppdateringer over nettverket:** Cleona kan hente en oppdatering direkte
   over nettverket -- uten nedlastingsserver. Den nye versjonen er delt opp i
   feilrettede biter som sprer seg i nettverket; en del av dem følger til og
   med med i dekktrafikken. Enheten din samler nok biter og setter sammen
   oppdateringen. Overført blir som regel bare endringen -- noen få MB i
   stedet for hele appen. Dette gjelder Linux, Windows og Android; under
   macOS laster du ned nye versjoner fra nettsiden eller fra GitHub.
4. **Invitasjonslenker:** Du kan lage invitasjonslenker som inneholder alt en
   ny bruker trenger for å installere Cleona og koble seg til nettverket.
5. **Fysisk overføring:** I miljøer uten internett kan du gi Cleona videre til
   andre via USB-minnepinne eller i det lokale nettverket.

### Slik forløper en oppdatering

1. Cleona samler bitene av en ny oppdatering automatisk i bakgrunnen og
   setter dem sammen.
2. Først når oppdateringen er **fullstendig** og dens **signatur er
   etterprøvd**, tilbyr Cleona den deg. Du får altså aldri tilbud om en halv
   eller uetterprøvd oppdatering.
3. Trykker du på «Installer», starter installasjonen uten ytterligere
   forespørsel. På Android viser i tillegg systemet sin
   installasjonsdialog.

Eldre versjoner tilbys ikke -- en oppdatering går alltid kun fremover. Er en
versjon så gammel at den ikke lenger kan samarbeide med nettverket, markerer
Cleona dette tydelig og ber deg oppdatere.

### Signaturprøving

Enhver oppdatering er signert to ganger: med en klassisk og en post-kvantum-
metode. Cleona etterprøver begge signaturene automatisk. Slik sikres at kun
oppdateringer fra den offisielle utvikleren aksepteres -- selv om oppdateringen
kom over nettverket fra fremmede enheter. En oppdatering oppstår aldri
automatisk fra utviklingen, men kun når utvikleren signerer den for hånd.

---
## 16. Ofte stilte spørsmål

### "Kan jeg bruke Cleona uten internett?"

Cleona trenger en nettverksforbindelse, men ikke nødvendigvis internettet:
I samme Wi-Fi finner Cleona-enheter hverandre selv og kan skrive med hverandre
helt uten internettilgang. Samtidig på nett behøver du ikke å være med
motparten din: Er vedkommende frakoblet, venter meldingen i opptil 7 dager i
postkassen hos tre naboer, til vedkommende henter den.

### "Hva hvis jeg mister seed-frasen min?"

Så lenge én enhet med identiteten din fortsatt kjører, er ingenting tapt --
der skriver du bare videre. På den enheten du opprettet identiteten på, kan du
som regel lese de 24 ordene av på nytt (se kapittel 2). Stol ikke på det: En
ny installasjon rydder denne kopien bort, og på Android utsletter også
fjerningen eller endringen av skjermlåsen den. Har du verken ordene eller en
enhet, finnes det ingen vei tilbake -- heller ikke via kontaktene dine,
utvikleren eller noen andre. Derfor er det så viktig å oppbevare de 24
ordene trygt.

### "Kan noen lese med i meldingene mine?"

Nei. Hver melding krypteres med en engangsnøkkel som kun gjelder for denne ene
meldingen. Bare du og motparten din kan dekryptere meldingen. Det finnes ingen
sentral server, ingen hovednøkkel og ingen tilgang for utvikleren. Selv om en
enhet videresender meldingen på transportveien, ser den bare kryptert
datagrot og en kode. Naboen din vet at pakken kommer fra deg, men ikke til
hvem den går; motpartens nabo vet til hvem den går, men ikke fra hvem.

### "Hvorfor trenger jeg ikke et telefonnummer?"

Fordi identiteten din er rent kryptografisk. I stedet for et telefonnummer
eller en e-postadresse som er knyttet til ditt virkelige navn, identifiserer
deg et nøkkelpar som er generert på enheten din. Kontakter legger du til via
QR-kode, NFC eller tekstlinjen i invitasjonen din -- ikke via en telefonkatalog.
Det betyr
mer personvern, fordi meldingskontoen din ikke er bundet til din virkelige
identitet.

### "Hvordan finner jeg folk på Cleona?"

Cleona har bevisst ingen kontaktsøk etter telefonnummer eller navn -- det
ville vært et personvernproblem. I stedet utveksler du invitasjoner direkte:
via QR-kode, NFC eller som tekstlinje via en annen vei. Det er som å utveksle
visittkort i stedet for å slå opp i en telefonkatalog.

### "Virker Cleona også i utlandet?"

Ja. Så lenge du har en internettforbindelse, virker Cleona overalt i verden.
Siden det ikke finnes noen sentral server og ingen fast adresse, lar
tjenesten seg ikke bare slås av for bestemte land. Hvordan Cleona gjør blokkering
vanskeligere, står i kapittelet «Sikkerhet» under «Anti-sensur». Et land som
blokkerer all ukjent trafikk ved grensen, kan imidlertid også stoppe Cleona.

### "Er Cleona gratis?"

Ja. Cleona er gratis å bruke og uten reklame. Siden det ikke finnes noen
sentral server, påløper det heller ingen serverkostnader for driften. I
innstillingene under «Støtt Cleona» -> «Doner» kan du støtte utviklingen
frivillig.

### "Meldingen min har bare én hake -- hva betyr det?"

Meldingen er på vei, men motparten din har ennå ikke bekreftet mottaket --
oftest fordi vedkommende akkurat er frakoblet. Det er ingen feil: Meldingen
venter i opptil 7 dager i postkassen. Så snart vedkommende henter den, ser du
to haker. En klokke betyr at ingen rute ennå har båret meldingen -- den går av
gårde av seg selv så snart det finnes en; et advarselstegn betyr at den ikke
har funnet noen rute på 14 dager og at du kan sende den på nytt.

### "Hvorfor kommer meldinger forsinket på iPhone-en min?"

iOS lar ikke apper kjøre permanent i bakgrunnen. Cleona vekkes bare kort av
og til; når, bestemmer iOS. Den henter da alt. Så snart du åpner appen,
henter Cleona det som er lagret for deg.

### "Kan jeg bytte fra WhatsApp til Cleona?"

Ja, men du kan ikke overføre WhatsApp-chattene dine. Cleona og WhatsApp er
grunnleggende ulike systemer. Du må legge til kontaktene dine enkeltvis i
Cleona. Enklest gjøres det ved å sende tekstlinjen i invitasjonen din til
kontaktene dine. Hver forespørsel som kommer slik, bekrefter du selv under
«Forespørsler».

### "Kan jeg bruke Cleona på flere enheter samtidig?"

Ikke ennå. En annen enhet for samme identitet kommer i en senere versjon
(kapittel 11). På flere enheter kan du i dag bruke ulike identiteter.

### "Hvordan får jeg oppdateringer når app-butikken er blokkert?"

Cleona kan hente oppdateringer direkte over nettverket, uten å være avhengig
av en app-butikk, en nettside eller en nedlastingsserver. Har en annen enhet
i nettverket den nyeste versjonen, kan enheten din laste oppdateringen
derfra. Ekteheten etterprøves ved en digital signatur fra utvikleren. Eventuelt
kan en kontakt gi deg appen videre via en invitasjonslenke eller
USB-minnepinne. Mer om dette i kapittelet «Programvareoppdateringer».

---

## Hjelp og kontakt

Har du spørsmål eller støter du på et problem, finner du oppdatert informasjon
på Cleonas nettside og på GitHub. Siden Cleona er et desentralt prosjekt,
finnes det ingen klassisk kundestøtte -- men et aktivt fellesskap som gjerne
hjelper.

---

*Denne håndboken beskriver Cleona Chat versjon 4.2. Enkelte funksjoner kan
endres eller utvides i nyere versjoner.*
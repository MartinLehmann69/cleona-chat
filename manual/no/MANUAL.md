# Cleona Chat -- Brukerhåndbok

Version 3.1.125 | juli 2026

---

## Innholdsfortegnelse

1. [Hva er Cleona Chat?](#1-hva-er-cleona-chat)
2. [Komme i gang](#2-komme-i-gang)
3. [Kontakter](#3-kontakter)
4. [Meldinger](#4-meldinger)
5. [Grupper](#5-grupper)
6. [Offentlige kanaler](#6-offentlige-kanaler)
7. [Samtaler](#7-samtaler)
8. [Kalender](#8-kalender)
9. [Avstemninger](#9-avstemninger)
10. [Flere identiteter](#10-flere-identiteter)
11. [Flere enheter](#11-flere-enheter)
12. [Gjenoppretting](#12-gjenoppretting)
13. [Innstillinger](#13-innstillinger)
14. [Sikkerhet](#14-sikkerhet)
15. [Programvareoppdateringer](#15-programvareoppdateringer)
16. [Ofte stilte spørsmål](#16-ofte-stilte-spoersmaal)

---

## 1. Hva er Cleona Chat?

### Din messenger, dine data

Cleona Chat er en meldingstjeneste som fungerer helt uten en sentral server.
Meldingene dine går direkte fra din enhet til enheten til den du snakker med
-- uten omveier via et firmahovedkontor, uten sky, uten datasenter. Ingen
bedrift kan lese, lagre eller videreformidle meldingene dine, ganske enkelt
fordi det ikke finnes noen bedrift i midten.

### Ingen konto, ingen telefonnummer

Med Cleona trenger du verken telefonnummer eller e-postadresse for å logge
deg på. Identiteten din består av et kryptografisk nøkkelpar som genereres
automatisk på enheten din ved første oppstart. Det betyr at ingen kan
oppspore deg via telefonnummeret eller e-postadressen din, med mindre du selv
deler kontaktinformasjonen din.

### Fremtidssikker kryptering

Cleona bruker såkalt post-kvante-kryptering. Det betyr at selv fremtidige
kvantedatamaskiner ikke vil kunne knekke meldingene dine. Du trenger ikke
forstå detaljene -- det viktige er at kommunikasjonen din er beskyttet så
godt som mulig etter dagens teknologiske standard.

### Hvordan fungerer dette uten server?

Tenk deg at du og kontaktene dine sammen danner et nettverk. Hver enhet
hjelper til med å videreformidle meldinger. Er personen du skriver til
online akkurat nå, går meldingen rett dit. Er personen offline, lagrer
felles kontakter meldingen midlertidig og leverer den så snart mottakeren er
tilbake. Kontaktene dine er altså samtidig ditt nettverk.

### Plattformer

Cleona er tilgjengelig for Android, iOS, macOS, Linux og Windows.

---

## 2. Komme i gang

### Installere appen

**Android:**
1. Last ned APK-filen fra Cleona-nettsiden eller fra GitHub Releases.
2. Åpne filen på telefonen din. Om nødvendig, tillat installasjon fra ukjente
   kilder (Android spør deg automatisk).
3. Trykk på «Installer» og vent til installasjonen er fullført.

**iOS:**
1. Åpne TestFlight-invitasjonslenken på iPhonen din.
2. Trykk på «Installer». TestFlight er Apples offisielle måte å distribuere
   beta-apper på.
3. Etter installasjonen finner du Cleona på hjemskjermen din.

**macOS:**
1. Last ned DMG-filen fra Cleona-nettsiden eller fra GitHub Releases.
2. Åpne DMG-filen og dra Cleona til Programmer-mappen din.
3. Ved første oppstart kan macOS spørre om du vil åpne appen til en
   identifisert utvikler -- bekreft dette.

**Linux (Ubuntu/Debian):**
1. Last ned .deb-filen fra Cleona-nettsiden eller fra GitHub Releases.
2. Installer med dobbeltklikk eller i terminalen: `sudo dpkg -i cleona-chat_VERSION_amd64.deb`
3. Start Cleona via applikasjonsmenyen eller i terminalen med `cleona-chat`.

**Linux (Fedora/openSUSE):**
1. Last ned .rpm-filen fra Cleona-nettsiden eller fra GitHub Releases.
2. Installer med: `sudo dnf install cleona-chat-VERSION.x86_64.rpm`
3. Start Cleona via applikasjonsmenyen eller i terminalen med `cleona-chat`.

**Linux (alle distribusjoner -- AppImage):**
1. Last ned .AppImage-filen fra Cleona-nettsiden eller fra GitHub Releases.
2. Gjør filen kjørbar: høyreklikk, Egenskaper, Kjørbar, eller i terminalen: `chmod +x cleona-chat-VERSION-x86_64.AppImage`
3. Start med dobbeltklikk eller i terminalen: `./cleona-chat-VERSION-x86_64.AppImage`

**Windows:**
1. Last ned installasjonsprogrammet fra Cleona-nettsiden eller fra GitHub Releases.
2. Kjør installasjonsfilen og følg instruksjonene.
3. Start Cleona via startmenyen eller snarveien på skrivebordet.

### Opprette identitet

Ved første oppstart oppretter Cleona automatisk en ny identitet for deg. Du
kan gi deg selv et visningsnavn -- det er navnet kontaktene dine ser. Dette
navnet kan endres når som helst.

### Skriv ned seed-phrasen -- det aller viktigste

Etter at identiteten din er opprettet, viser Cleona deg 24 ord. Dette er din
**seed-phrase** -- din personlige gjenopprettingsnøkkel.

**Skriv ned disse 24 ordene på papir og oppbevar dem trygt.**

Hvorfor er dette så viktig?

- Hvis telefonen din går i stykker, blir borte eller stjålet, kan du bruke
  disse 24 ordene til å gjenopprette hele identiteten din på en ny enhet.
- Uten seed-phrasen finnes det ingen vei tilbake. Det finnes ingen «glemt
  passord»-knapp og ingen kundestøtte som kan gi deg tilbake kontoen din --
  fordi det ikke finnes noen konto på en server i det hele tatt.
- Del aldri seed-phrasen med andre. Den som kjenner disse ordene, kan utgi
  seg for å være deg.

Du finner seed-phrasen senere også under innstillingene, under «Sikkerhet»,
hvis du vil lese den på nytt.

### Legge til din første kontakt

For å chatte med noen må du først legge til personen som kontakt. Det finnes
flere måter å gjøre dette på -- alle forklares i neste avsnitt.

---

## 3. Kontakter

### Skanne QR-kode (anbefalt)

Den enkleste måten å legge til en kontakt på:

1. Personen du snakker med åpner sin identitetsdetaljside (trykk på eget navn
   i den øverste linjen) og viser deg QR-koden sin.
2. Du trykker på plussknappen og velger «Skann QR-kode».
3. Hold telefonen din foran QR-koden til den andre personen.
4. Kontaktforespørselen sendes automatisk. Så snart personen godtar den, kan
   dere skrive til hverandre.

Hvis dere møtes personlig, er QR-koden den sikreste metoden, fordi du da vet
nøyaktig med hvem du utveksler kontakten.

### NFC (holde telefonene mot hverandre)

Hvis begge enhetene støtter NFC:

1. Åpne funksjonen for å legge til kontakt på begge enhetene.
2. Hold telefonene mot hverandre, bakside mot bakside.
3. Kontaktinformasjonen utveksles automatisk.

NFC gir, i likhet med QR-koden, høy sikkerhet, fordi utvekslingen bare
fungerer når dere står fysisk ved siden av hverandre.

### Dele lenke (cleona://-URI)

Du kan også sende kontaktlenken din via e-post, SMS eller en annen
meldingstjeneste:

1. Åpne identitetsdetaljsiden din.
2. Kopier cleona://-lenken din.
3. Send lenken til personen som skal legge deg til.
4. Den andre personen åpner lenken, eller limer den inn i
   dialogboksen for å legge til kontakt.

Merk: Med denne metoden stoler du på at lenken ikke er endret underveis. For
spesielt sensitive kontakter anbefaler vi QR-kode eller NFC.

### Godta kontaktforespørsler

Når noen sender deg en kontaktforespørsel, dukker den opp i innboksen din
(den siste fanen i den nederste linjen). Der kan du:

- **Godta** -- personen legges til blant kontaktene dine.
- **Avslå** -- forespørselen forkastes.
- **Blokkere** -- personen kan ikke sende deg flere forespørsler.

### Verifiseringsnivåer

Cleona viser deg hvor sikkert en kontakts identitet er bekreftet:

| Nivå | Betydning |
|-------|-----------|
| Ukjent | Du har bare mottatt node-ID-en eller en lenke. |
| Sett | Nøkkelutvekslingen var vellykket, dere kan kommunisere kryptert. |
| Verifisert | Dere har møttes personlig og verifisert via QR-kode eller NFC. |
| Betrodd | Du har eksplisitt merket denne kontakten som pålitelig. |

Jo høyere nivå, desto sikrere kan du være på at du virkelig snakker med
riktig person.

---

## 4. Meldinger

### Sende og motta tekst

Skriv ganske enkelt meldingen din i inntastingsfeltet nederst og trykk Enter
eller send-knappen. Meldingen din krypteres automatisk før den forlater
enheten din.

Innkommende meldinger vises i chatteloggen. En hake viser deg om meldingen
din er levert.

### Sende bilder, videoer og filer

Du har flere muligheter:

- **Binders-ikonet** i inntastingsfeltet: Trykk på det for å velge en fil,
  et bilde eller en video fra galleriet eller filsystemet ditt.
- **Dra-og-slipp** (skrivebord): Dra en fil rett inn i chattevinduet.
- **Lim inn fra utklippstavlen** (skrivebord): Kopier et bilde og lim det inn
  i chatten.

Små filer (under 256 KB) sendes direkte med. Større filer overføres i en
totrinnsprosess: Først varsles filen, deretter overføres den i deler.

### Talemeldinger

1. Hold mikrofonknappen i inntastingsfeltet inne.
2. Snakk inn meldingen din.
3. Slipp knappen for å sende meldingen.

Hvis talegjenkjenning er aktivert på enheten din (se innstillinger),
transkriberes talemeldingen din automatisk til tekst. Personen du snakker
med ser da både opptaket og den transkriberte teksten.

### Svare på meldinger (sitere)

For å svare på en bestemt melding:

1. Åpne trepunktsmenyen ved siden av meldingen.
2. Velg «Svar».
3. Over inntastingsfeltet vises et banner med den siterte meldingen.
4. Skriv svaret ditt og send det.

Den siterte meldingen vises i svaret ditt, slik at sammenhengen er tydelig.

### Redigere og slette meldinger

- **Redigere:** Trepunktsmenyen til meldingen, deretter «Rediger». Endre
  teksten og send den på nytt. Personen du snakker med ser at meldingen er
  redigert. Redigering er mulig innen 15 minutter etter sending.
- **Slette:** Trepunktsmenyen til meldingen, deretter «Slett». Meldingen
  fjernes hos deg og hos den du snakker med. Du kan slette dine egne
  meldinger når som helst -- det finnes ikke noe tidsvindu for sletting.

### Emoji-reaksjoner

I stedet for å skrive et svar, kan du reagere på en melding med en emoji:

1. Åpne trepunktsmenyen eller hold meldingen inne lenge.
2. Velg en emoji fra hurtigvalget, eller åpne emoji-velgeren for hele
   utvalget.
3. Reaksjonen din vises under meldingen.

### Kopiere tekst

Via trepunktsmenyen til en melding kan du kopiere meldingsteksten til
utklippstavlen.

### Søke i meldinger

Øverst i chattevinduet finner du søkefunksjonen. Skriv inn et søkeord, og
Cleona viser deg alle treff i den aktuelle chatten. Med pilene kan du hoppe
frem og tilbake mellom treffene.

På startsiden finnes det i tillegg et søkefilter på tvers av faner, der du
kan søke gjennom alle samtaler etter et begrep.

### Lenkeforhåndsvisning

Når du sender en lenke, oppretter Cleona automatisk en forhåndsvisning
(tittel, beskrivelse, forhåndsvisningsbilde). Denne forhåndsvisningen
opprettes av din enhet og sendes med -- personen du snakker med trenger ikke
å opprette noen forbindelse til den lenkede nettsiden for dette.

Når du trykker på en mottatt lenke, blir du spurt om du vil åpne den i vanlig
nettleser, i inkognitomodus, eller ikke åpne den i det hele tatt.

---

## 5. Grupper

### Opprette gruppe

1. Bytt til fanen «Grupper».
2. Trykk på plussknappen.
3. Gi gruppen et navn.
4. Velg kontaktene du vil invitere.
5. Trykk på «Opprett».

De inviterte kontaktene mottar et varsel og kan bli med i gruppen.

### Invitere medlemmer

Også etter opprettelsen kan du invitere flere kontakter:

1. Åpne gruppeinfoen (trepunktsmenyen i gruppeoversikten eller den øverste
   linjen i gruppechatten).
2. Trykk på «Inviter».
3. Velg kontaktene du vil legge til.

### Roller

Hver gruppe har tre roller:

- **Eier (Owner):** Har full kontroll. Kan legge til og fjerne medlemmer,
  utnevne administratorer og administrere gruppen. Eieren kan også overføre
  statusen sin til et annet medlem.
- **Administrator:** Kan fjerne medlemmer og hjelpe til med administrasjonen.
- **Medlem:** Kan lese og skrive meldinger.

### Forlate gruppe

1. Åpne trepunktsmenyen i gruppeoversikten.
2. Velg «Forlat».
3. Bekreft avgjørelsen din.

Når du forlater en gruppe, forblir dine tidligere meldinger synlige for de
andre medlemmene.

---

## 6. Offentlige kanaler

### Hva er kanaler?

Kanaler er offentlige diskusjonsforum innenfor Cleona-nettverket. I
motsetning til grupper kan hvem som helst lese med her, uten å måtte bli
invitert. Bare eieren og administratorer kan publisere innlegg -- abonnenter
leser med.

### Finne og bli med i kanaler

1. Bytt til fanen «Kanaler».
2. Åpne fanen «Søk».
3. Søk gjennom de tilgjengelige kanalene etter navn eller emne.
4. Trykk på en kanal og deretter på «Abonner».

Kanaler kan filtreres etter språk. Enkelte kanaler er merket «Ikke egnet for
mindreårige» -- disse er bare synlige hvis du har bekreftet i profilen din at
du er over 18 år.

### Opprette egen kanal

1. Bytt til fanen «Kanaler».
2. Trykk på plussknappen.
3. Skriv inn et kanalnavn (må være unikt i hele nettverket).
4. Velg språket, og om kanalen skal være offentlig eller privat.
5. Valgfritt: Legg til en beskrivelse og et bilde.
6. Trykk på «Opprett».

For offentlige kanaler kan du fastsette om innholdet skal klassifiseres som
«Ikke egnet for mindreårige».

### Rapportere innhold

Hvis du legger merke til upassende innhold i en offentlig kanal, kan du
rapportere det. Cleona bruker et desentralisert modereringssystem: Rapporter
vurderes av tilfeldig utvalgte medlemmer av nettverket (en slags «jury»).
Hvis det oppdages et brudd, får kanalen en advarsel. Ved gjentatte brudd blir
den nedgradert i søkeindeksen eller sperret.

### Systemkanaler

Cleona har to innebygde systemkanaler:

- **Bug Log:** Når Cleona oppdager en feil, spør den deg om du vil sende en
  anonymisert feilrapport. Disse rapportene havner i Bug-Log-kanalen, der de
  kan sees av fellesskapet. Det overføres ingen personopplysninger -- bare
  tekniske feilbeskrivelser. Du kan også sende en loggrapport manuelt (med
  forhåndsvisningsdialog og eksplisitt samtykke).
- **Feature Requests:** Her kan brukere sende inn funksjonsønsker og stemme
  på eksisterende forslag. Forslagene sorteres etter antall stemmer.

Begge systemkanalene har en størrelsesgrense på 25 MB og overvåkes av
jury-modereringssystemet.

---

## 7. Samtaler

### Starte talesamtale

1. Åpne chatten med kontakten du vil ringe.
2. Trykk på telefonsymbolet i den øverste linjen.
3. Vent til personen du ringer godtar samtalen.

Under samtalen ser du en tidslinje som viser samtalens varighet, og du har
tilgang til å slå av lyden og til høyttaler.

For å legge på, trykk på den røde legg på-knappen.

### Starte videosamtale

1. Åpne chatten med kontakten.
2. Trykk på kamerasymbolet i den øverste linjen.
3. Videobildet ditt vises i et lite vindu, bildet av personen du snakker med
   vises i det store området.

Du kan bytte mellom front- og bakkamera under samtalen.

### Innkommende samtaler

Når noen ringer deg, vises et varselvindu med navnet til den som ringer. Du
kan:

- **Godta** -- samtalen starter.
- **Avslå** -- den som ringer blir varslet.

Hvis du allerede er i en samtale, blir en ny samtale automatisk avslått.

### Gruppesamtaler

Du kan også gjennomføre gruppesamtaler der flere personer deltar samtidig.
Samtalen organiseres via et intelligent videresendingstre, slik at ikke alle
deltakere trenger å være direkte tilkoblet alle andre. Alle samtaler er
kryptert fra ende til ende.

### Kryptering ved samtaler

Alle samtaler krypteres med engangsnøkler som bare eksisterer for varigheten
av samtalen. Etter at samtalen er avsluttet, slettes disse nøklene
umiddelbart. Ingen kan i ettertid dekryptere en tidligere samtale.

---

## 8. Kalender

Cleona inneholder en innebygd kalender som er kryptert og fungerer helt
desentralisert -- uten noen skytjeneste.

### Visninger

Kalenderen tilbyr fem visninger: Dag, uke, måned, år og en oppgavevisning.
Bytt mellom dem via fanene øverst på kalenderskjermen.

### Opprette avtaler

Trykk på et tidspunkt eller bruk legg til-knappen for å opprette en ny
avtale. Du kan angi tittel, dato, klokkeslett, sted og notater. Avtaler
lagres kryptert på enheten din.

### Gjentakende avtaler

Avtaler kan gjentas daglig, ukentlig, månedlig eller årlig. Du kan tilpasse
mønsteret (f.eks. hver andre tirsdag, den første i måneden) og angi en
sluttdato eller et antall gjentakelser.

### Invitere kontakter

Når du oppretter eller redigerer en avtale, kan du invitere Cleona-kontaktene
dine. De mottar en kryptert kalenderinvitasjon og kan svare med ja, nei eller
kanskje. Endringer i avtalen sendes automatisk til alle inviterte.

### Ledig/opptatt-visning

Du kan dele tilgjengeligheten din med kontakter uten å avsløre
avtaledetaljer. Det finnes tre personvernnivåer: fulle detaljer, kun
tidsblokker, eller skjult. Du kan angi en standard og overstyre den per
kontakt.

### Påminnelser

Avtaler kan ha påminnelser som utløser et systemvarsel før avtalen starter.
Du kan utsette påminnelser ved behov.

### Ekstern kalendersynkronisering

Cleona kan synkronisere med eksterne kalendertjenester:

- **CalDAV** -- Koble til enhver CalDAV-kompatibel server (Nextcloud,
  Radicale osv.).
- **Google Kalender** -- Synkronisering via Google Calendar API med sikker
  OAuth2-autentisering.
- **Lokal CalDAV-server** -- Cleona kan starte en lokal CalDAV-server på
  enheten din, slik at kalenderapper for skrivebord (Thunderbird, Outlook,
  Apple Kalender, Evolution) kan synkronisere med Cleona-kalenderen din.
- **Android-systemkalender** -- Avtaler fra Cleona kan overføres til den
  innebygde kalenderappen på Android-enheten din.
- **ICS-filer** -- Importer og eksporter avtaler i standard
  iCalendar-format.

### PDF-eksport

Du kan skrive ut eller eksportere hver kalendervisning (dag, uke, måned, år)
som et PDF-dokument.

---

## 9. Avstemninger

Du kan opprette avstemninger i enhver chat eller gruppe for å samle inn
meninger eller planlegge avtaler.

### Avstemningstyper

Cleona støtter fem typer avstemninger:

- **Enkeltvalg** -- Deltakerne velger ett alternativ.
- **Flervalg** -- Deltakerne kan velge flere alternativer.
- **Terminavstemning** -- Finn et tidspunkt som passer for alle. Hver
  deltaker markerer tidspunkter som tilgjengelig, kanskje eller ikke
  tilgjengelig.
- **Skala** -- Vurder noe på en tallskala (f.eks. 1 til 5).
- **Fritekst** -- Deltakerne skriver sitt eget svar.

### Opprette avstemning

Åpne en chat og trykk på avstemningssymbolet (eller bruk vedleggsmenyen).
Velg avstemningstype, formuler spørsmålet ditt og alternativene, og send
avstemningen. Den vises som en melding i chatten.

### Stemme

Trykk på en avstemning for å avgi stemmen din. Du kan endre eller trekke
tilbake stemmen din når som helst.

### Anonym avstemning

Avstemninger kan konfigureres for anonym stemmegivning. Når dette er
aktivert, er stemmene kryptografisk anonyme -- ingen, ikke engang den som
opprettet avstemningen, kan se hvem som stemte på hva. Antall stemmer
forblir likevel synlig.

### Terminavstemning til kalender

Når en terminavstemning er avsluttet, kan det vinnende tidspunktet omgjøres
direkte til en kalenderoppføring med et trykk.

---

## 10. Flere identiteter

### Hvorfor flere identiteter?

Tenk deg at du vil skille arbeidslivet og privatlivet ditt -- omtrent som med
to forskjellige telefonnumre, men uten en ekstra telefon. I Cleona kan du
bruke flere identiteter på én enhet. Hver identitet har sitt eget navn, sitt
eget profilbilde, sine egne kontakter og sine egne samtaler.

### Opprette ny identitet

1. I den øverste linjen ser du din nåværende identitet som en fane.
2. Trykk på plusstegnet (+) til høyre for identitetsfanene dine.
3. Skriv inn et navn for den nye identiteten.
4. Ferdig -- den nye identiteten er aktiv umiddelbart.

### Bytte mellom identiteter

Trykk ganske enkelt på identitetsfanen i den øverste linjen. Byttet skjer
umiddelbart -- ingen ventetid, ingen omlasting.

### Alle kjører samtidig

Et viktig poeng: Alle identitetene dine er aktive samtidig. Selv om du for
øyeblikket vises som «Jobb», mottar «Privat»-identiteten din fortsatt
meldinger. Du går ikke glipp av noe, uansett hvilken identitet du har valgt
akkurat nå.

### Identitetsdetaljside

Når du trykker på fanen til din aktive identitet, åpnes detaljsiden. Her kan
du:

- Vise QR-koden din for kontakter.
- Endre eller fjerne profilbildet ditt.
- Legge til en profilbeskrivelse.
- Endre visningsnavnet ditt.
- Velge et design (skin) for denne identiteten.
- Slette identiteten hvis du ikke lenger trenger den.

### Slette identitet

Når du sletter en identitet, blir kontaktene dine varslet om det. Identiteten
og alle tilhørende data fjernes fra enheten din. Denne handlingen kan ikke
angres.

---

## 11. Flere enheter

### Bruke Cleona på flere enheter

Du kan bruke samme identitet på opptil 5 enheter samtidig. Én enhet er den
primære (den holder seed-phrasen), og andre enheter kobles til den.

### Koble til ny enhet

1. Åpne innstillingene på den primære enheten din.
2. Gå til «Koblede enheter».
3. Velg «Koble til ny enhet».
4. Installer Cleona på den nye enheten og velg «Koble til eksisterende
   enhet» ved oppstart.
5. Skann paringens QR-kode som vises på den primære enheten din, eller bruk
   paringslenken.

Den koblede enheten mottar et delegeringssertifikat fra den primære enheten.
Meldinger som sendes fra en koblet enhet, er kryptografisk signert med en
delegert nøkkel, slik at kontakter kan bekrefte at meldingen faktisk kommer
fra din identitet.

### Slik fungerer det

- Den primære enheten holder seed-phrasen din og hovednøklene.
- Koblede enheter mottar avledede signaturnøkler og et delegeringssertifikat
  -- de mottar aldri selve seed-phrasen.
- Alle enheter deler samme identitet og kontakter. Meldinger ankommer på
  alle enheter.
- Delegeringssertifikater fornyes automatisk før de utløper.

### Enhetsadministrasjon

Åpne innstillingene og gå til «Koblede enheter» for å se alle de koblede
enhetene dine, deres status og siste aktivitet. Du kan når som helst
tilbakekalle en koblet enhet, hvis den blir mistet eller stjålet.

### Nødnøkkelrotasjon

Hvis du mistenker at en enhet er kompromittert, kan du utløse en
nødnøkkelrotasjon. Da genereres nye nøkler, og rotasjonen må bekreftes av et
flertall av dine andre enheter. Dette hindrer at en enkelt stjålet enhet kan
rotere nøkler på egen hånd.

---

## 12. Gjenoppretting

### Bruke seed-phrasen

Hvis du mister enheten din eller setter opp en ny:

1. Installer Cleona på den nye enheten.
2. Velg «Gjenopprett» ved oppstart.
3. Skriv inn dine 24 ord.
4. Cleona gjenoppretter identiteten din og kontakter automatisk dine
   tidligere kontakter.
5. Kontaktene dine svarer med kontaktinformasjonen din, gruppemedlemskap og
   meldingshistorikk.

Gjenopprettingen skjer i tre trinn:
- Først kommer kontaktene og gruppene dine tilbake.
- Deretter de siste 50 meldingene fra hver samtale.
- Til slutt hele meldingshistorikken.

Det er nok at én eneste av kontaktene dine er online for at gjenopprettingen
skal fungere.

### Guardian Recovery (tillitspersoner)

Du kan utnevne opptil fem tillitspersoner som «guardians» (vergere).
Gjenopprettingsnøkkelen din deles da opp i fem deler, der hver guardian får
én. For å gjenopprette identiteten din trengs tre av de fem delene.

Det betyr: Selv om du har mistet seed-phrasen din, kan tre av guardianene
dine sammen gjenopprette kontoen din. Ingen enkelt guardian kan alene få
tilgang til dataene dine -- det trengs alltid minst tre.

Slik setter du opp guardians:
1. Åpne innstillingene.
2. Gå til «Sikkerhet».
3. Velg «Guardian Recovery».
4. Velg fem pålitelige kontakter.

### Hvorfor kontaktene dine er backupen din

I tradisjonelle meldingstjenester ligger dataene dine på leverandørens
servere. Hos Cleona finnes det ingen server -- men kontaktene dine overtar
denne rollen. Når du sender en melding, lagrer felles kontakter en kryptert
kopi i tilfelle mottakeren er offline akkurat da. Ved en gjenoppretting
leverer kontaktene dine dataene dine tilbake til deg.

Det betyr: Jo flere aktive kontakter du har, desto mer pålitelig er
backupen din. Én kontakt som er jevnlig online, er nok for en vellykket
gjenoppretting.

---

## 13. Innstillinger

Du kommer til innstillingene via tannhjulsymbolet øverst til høyre.

### Varsler og ringetoner

- Velg blant seks forskjellige ringetoner for innkommende samtaler.
- Still inn en meldingstone.
- På Android-enheter kan du i tillegg aktivere eller deaktivere vibrasjon.

### Design (skins)

Cleona tilbyr ti forskjellige design: Teal, Ocean, Sunset, Forest, Amethyst,
Fire, Storm, Slate, Gold og Contrast. Contrast-designet oppfyller det
høyeste tilgjengelighetsnivået (WCAG AAA) og er spesielt godt lesbart ved
nedsatt syn.

Hver identitet kan ha sitt eget design. Du endrer designet på
identitetsdetaljsiden (trykk på den aktive identitetsfanen).

I tillegg kan du bytte mellom lyst, mørkt og systemtema under «Utseende» i
innstillingene.

### Endre språk

Cleona er tilgjengelig på 33 språk, inkludert språk med skrift fra høyre mot
venstre (f.eks. arabisk, hebraisk). Endre språket under «Språk» i
innstillingene.

### Lagringsgrense

Du kan angi hvor mye lagringsplass Cleona får bruke på enheten din (mellom
100 MB og 2 GB). Når grensen er nådd, blir eldre medier automatisk arkivert
eller slettet -- tekstmeldinger bevares alltid.

### Media-arkivering

Hvis du har en nettverkslagringsenhet (NAS) eller en delt mappe hjemme, kan
Cleona automatisk arkivere mediene dine dit. SMB, SFTP, FTPS og WebDAV
støttes.

Slik fungerer den gradvise lagringen:
- De første 30 dagene: Alt forblir på enheten din.
- Etter 30 dager: Et forhåndsvisningsbilde forblir på enheten, originalen
  arkiveres.
- Etter 90 dager: Bare et lite forhåndsvisningsbilde forblir på enheten.
- Etter ett år: Bare en plassholder forblir, originalen ligger trygt i
  arkivet.

Du kan når som helst trykke på et arkivert medium for å hente det tilbake --
forutsatt at du er koblet til hjemmenettverket ditt. Spesielt viktige medier
kan festes, slik at de aldri arkiveres.

### Transkripsjon for talemeldinger

Når aktivert, konverteres talemeldingene dine lokalt på enheten din til
tekst (med åpen kildekode-modellen Whisper). Den transkriberte teksten
sendes sammen med opptaket til personen du snakker med. Transkripsjonen
skjer helt på enheten din -- ingen data sendes til eksterne tjenester.

### Auto-nedlasting

Du kan stille inn fra hvilken størrelse medier skal lastes ned automatisk.
Slik kan du for eksempel la bilder lastes ned automatisk, men bestemme
manuelt ved store videoer.

### Koblede enheter

Administrer de koblede enhetene dine i denne delen av innstillingene. Se
kapittelet om flere enheter for detaljer.

---

## 14. Sikkerhet

### Hva betyr post-kvante-kryptering?

Dagens kryptering er basert på matematiske problemer som er ekstremt
vanskelige å løse for vanlige datamaskiner. Kvantedatamaskiner kan i
fremtiden løse noen av disse problemene raskt. Post-kvante-kryptering bruker
ytterligere metoder som også står imot kvantedatamaskiner.

Cleona kombinerer begge tilnærmingene: klassisk kryptering for pålitelighet
og post-kvante-metoder for fremtidssikkerhet. Slik er du beskyttet mot
dagens og fremtidens trusler samtidig.

For hver enkelt melding genereres en egen nøkkel. Selv om en angriper skulle
knekke nøkkelen til én melding, ville han ikke kunne lese noen annen melding
med den.

### Hvorfor ingen server er tryggere

Hos tradisjonelle meldingstjenester går meldingene dine via leverandørens
servere. Selv om de skulle være kryptert der: Leverandøren har tilgang til
metadata (hvem kommuniserer med hvem når, hvor ofte, hvorfra) og må
eventuelt utlevere dette etter rettslig pålegg.

Hos Cleona finnes det ikke noe slikt sentralt punkt. Meldingene dine reiser
direkte fra enhet til enhet. Det finnes ikke noe sted der alle metadata
samles. Ingen kan ut fra ett enkelt datapunkt rekonstruere
kommunikasjonsmønsteret ditt.

### Hva skjer når du er offline?

Når du sender en melding og mottakeren er offline:

1. Cleona forsøker først å levere meldingen direkte.
2. Hvis det ikke lykkes, videresendes den via felles kontakter.
3. Samtidig fordeles meldingen som krypterte deler over flere noder i
   nettverket (litt som et puslespill som består av 10 deler, hvorav 7 er
   nok til å sette sammen bildet).
4. Meldingen oppbevares i opptil 7 dager.

Så snart mottakeren kommer online igjen, blir meldingene levert. Du får en
bekreftelse når meldingen din har kommet frem.

### Antisensur

Hvis nettverket ditt blokkerer standard tilkoblingsmetoden (UDP), bytter
Cleona automatisk til en alternativ overføring (TLS) som er vanskeligere å
oppdage og blokkere. Dette skjer transparent -- du trenger ikke konfigurere
noe.

### Sikker nøkkellagring

På støttede plattformer lagrer Cleona krypteringsnøklene dine i
operativsystemets sikre nøkkelring (Android Keystore, iOS Keychain, macOS
Keychain). Der det er tilgjengelig, gir dette maskinvarestøttet beskyttelse
for nøklene dine.

### Databasekryptering

Alle meldinger, kontakter og innstillinger lagres kryptert på enheten din.
Selv om noen skulle få tilgang til filsystemet ditt, ville de ikke kunne
lese noe uten din kryptografiske nøkkel. Denne nøkkelen avledes fra
identiteten din og finnes bare på enheten din.

### Lukket nettverk

Cleona fungerer som et lukket nettverk. Hver nettverkspakke er
autentisert, slik at bare legitime Cleona-enheter kan delta. Dette hindrer
utenforstående i å sende inn forfalskede meldinger eller avlytte
nettverkstrafikken.

---

## 15. Programvareoppdateringer

### Hvordan får jeg oppdateringer?

Cleona kan oppdateres på flere måter. Målet er at du skal kunne motta
oppdateringer selv om enkelte distribusjonskanaler faller ut eller blir
sperret:

1. **App Store / Play Store:** Hvis du har installert Cleona via en app
   store, mottar du oppdateringer som vanlig via butikken.
2. **GitHub Releases:** På GitHub-siden til prosjektet finner du signerte
   installasjonspakker for alle plattformer.
3. **Nettverksinterne oppdateringer:** Hvis en annen Cleona-bruker i
   nettverket ditt allerede har den nyeste versjonen, kan Cleona hente
   oppdateringen direkte via P2P-nettverket -- uten ekstern server. Da deles
   den nye versjonen opp i feilkorrigerte fragmenter og fordeles over flere
   noder. Enheten din samler nok fragmenter og setter sammen oppdateringen.
   Ektheten kontrolleres med en Ed25519-signatur fra utvikleren.
4. **Invitasjonslenker:** Du kan opprette invitasjonslenker som inneholder
   alt en ny bruker trenger for å installere Cleona og koble seg til
   nettverket.
5. **Fysisk overføring:** I miljøer uten internett kan du gi Cleona videre
   til andre via en USB-minnepenn eller i det lokale nettverket.

### Oppdateringsvarsel

Når en ny oppdatering er tilgjengelig, viser Cleona deg et varsel på
startskjermen. Hvis oppdateringen også er tilgjengelig via nettverket
(nettverksintern oppdatering), har du valget om å laste den ned direkte fra
nettverket.

### Binærdistribusjon

Som standard hjelper enheten din til med å videreformidle oppdateringer til
andre brukere i nettverket. Hvis du ikke ønsker dette, kan du deaktivere
denne funksjonen under «Nettverk» i innstillingene. Lagringsbruken for
oppdateringsfragmenter er begrenset (5 MB på mobile enheter, 20 MB på
skrivebordsenheter) og ryddes regelmessig opp.

### Signaturkontroll

Hver oppdatering signeres kryptografisk. Cleona kontrollerer signaturen
automatisk før en oppdatering installeres. Slik sikres det at bare
oppdateringer fra den offisielle utvikleren godtas -- selv om oppdateringen
ble hentet via P2P-nettverket.

---

## 16. Ofte stilte spørsmål

### «Kan jeg bruke Cleona uten internett?»

Nei, Cleona trenger en nettverkstilkobling for å sende og motta meldinger.
Du trenger imidlertid ikke være online samtidig med personen du snakker med:
Meldinger som sendes mens mottakeren er offline, mellomlagres og leveres
automatisk så snart begge parter er tilkoblet igjen. I det lokale nettverket
(f.eks. i samme Wi-Fi) kan dere også kommunisere helt uten internettilgang.

### «Hva skjer hvis jeg mister seed-phrasen min?»

Hvis du har satt opp guardians, kan tre av fem tillitspersoner sammen
gjenopprette tilgangen din. Uten guardians og uten seed-phrase finnes det
dessverre ingen måte å få tilbake identiteten din på. Derfor er det så
viktig å oppbevare de 24 ordene trygt.

### «Kan noen lese meldingene mine?»

Nei. Hver melding krypteres med en engangsnøkkel som bare gjelder for
nettopp denne meldingen. Bare du og personen du snakker med kan dekryptere
meldingen. Det finnes ingen sentral server, ingen hovednøkkel og ingen
tilgang for utvikleren. Selv om en enhet videresender meldingen underveis,
ser den bare kryptert datastøy.

### «Hvorfor trenger jeg ikke telefonnummer?»

Fordi identiteten din er rent kryptografisk. I stedet for et telefonnummer
eller en e-postadresse som er knyttet til ditt virkelige navn, identifiseres
du av et nøkkelpar som er generert på enheten din. Du legger til kontakter
via QR-kode, NFC eller lenke -- ikke via en telefonbok. Det betyr mer
personvern, fordi meldingskontoen din ikke er bundet til din virkelige
identitet.

### «Hvordan finner jeg folk på Cleona?»

Cleona har bevisst ikke noe kontaktsøk etter telefonnummer eller navn -- det
ville vært et personvernproblem. I stedet utveksler du kontaktinformasjon
direkte: via QR-kode, NFC, cleona://-lenke eller i offentlige kanaler. Det
er som å utveksle visittkort i stedet for å slå opp i en telefonkatalog.

### «Fungerer Cleona også i utlandet?»

Ja. Så lenge du har en internettforbindelse, fungerer Cleona overalt i
verden. Siden det ikke finnes noen sentral server, kan tjenesten heller ikke
sperres for bestemte land. Cleona har i tillegg en antisensur-reserveløsning:
Hvis den normale tilkoblingen (UDP) blokkeres, bytter Cleona automatisk til
en alternativ overføring (TLS) som er vanskeligere å oppdage og blokkere.

### «Er Cleona gratis?»

Ja. Cleona er gratis og reklamefritt å bruke. Siden det ikke finnes noen
sentral server, påløper det heller ingen serverkostnader for driften. I
appen finner du under «Doner» muligheten til å frivillig støtte utviklingen.

### «Meldingen min har et klokkesymbol -- hva betyr det?»

Det betyr at meldingen ennå ikke er levert. Personen du snakker med er
sannsynligvis offline akkurat nå. Så snart meldingen er levert, endres
symbolet. Meldinger oppbevares i opptil 7 dager for levering.

### «Kan jeg bytte fra WhatsApp til Cleona?»

Ja, men du kan ikke overføre WhatsApp-chattene dine. Cleona og WhatsApp er
fundamentalt forskjellige systemer. Du må legge til kontaktene dine
enkeltvis i Cleona. Den enkleste måten er å poste cleona://-lenken din i en
WhatsApp-gruppe og be de andre om å legge deg til der.

### «Kan jeg bruke Cleona på flere enheter samtidig?»

Ja. Du kan koble opptil 5 enheter til samme identitet. Én enhet er den
primære (den holder seed-phrasen), og andre enheter kobles til via en sikker
paringsprosess. Alle enheter deler samme identitet, kontakter og samtaler.
Se kapittelet om flere enheter for detaljer.

### «Hvordan får jeg oppdateringer når App Store er sperret?»

Cleona kan hente oppdateringer direkte via P2P-nettverket, uten å være
avhengig av en app store, en nettside eller en nedlastingsserver. Hvis en
annen bruker i nettverket har den nyeste versjonen, kan enheten din laste
oppdateringen derfra. Ektheten kontrolleres med en digital signatur fra
utvikleren. Alternativt kan en kontakt gi deg appen videre via
invitasjonslenke eller USB-minnepenn. Mer om dette i kapittelet
«Programvareoppdateringer».

---

## Hjelp og kontakt

Hvis du har spørsmål eller støter på et problem, finner du oppdatert
informasjon på Cleona-nettsiden og på GitHub. Siden Cleona er et
desentralisert prosjekt, finnes det ingen tradisjonell kundestøtte -- men et
aktivt fellesskap som gjerne hjelper til.

---

*Denne håndboken beskriver Cleona Chat versjon 3.1.125. Enkelte funksjoner
kan endres eller utvides i nyere versjoner.*

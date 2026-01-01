# Cleona Chat -- Användarhandbok

Version 4.2 | Per november 2026

---

## Innehållsförteckning

1. [Vad är Cleona Chat?](#1-vad-är-cleona-chat)
2. [Kom igång](#2-kom-igång)
3. [Kontakter](#3-kontakter)
4. [Meddelanden](#4-meddelanden)
5. [Grupper](#5-grupper)
6. [Offentliga kanaler](#6-offentliga-kanaler)
7. [Samtal](#7-samtal)
8. [Kalender](#8-kalender)
9. [Omröstningar](#9-omröstningar)
10. [Flera identiteter](#10-flera-identiteter)
11. [Flera enheter](#11-flera-enheter)
12. [Återställning](#12-återställning)
13. [Inställningar](#13-inställningar)
14. [Säkerhet](#14-säkerhet)
15. [Programuppdateringar](#15-programuppdateringar)
16. [Vanliga frågor](#16-vanliga-frågor)

---
## 1. Vad är Cleona Chat?

### Din meddelandetjänst, din data

Cleona Chat är en meddelandetjänst som fungerar helt utan central server.
Dina meddelanden färdas från din enhet till din motparts enhet -- utan
omväg via ett företags högkvarter, utan moln, utan datacenter. När en
annan enhet hjälper till på vägen, skickar den vidare bara krypterade
paket. Inget företag kan läsa, lagra eller vidarebefordra dina meddelanden,
för att det enkelt inte finns något företag emellan.

### Inget konto, inget telefonnummer

Med Cleona behöver du varken ett telefonnummer eller en e-postadress för
att logga in. Din identitet består av ett kryptografiskt nyckelpar som
skapas automatiskt på din enhet vid första starten. Det betyder: Ingen
kan spåra dig via ditt telefonnummer eller din e-postadress, om du inte
själv ger ut dina kontaktuppgifter.

### Framtidssäker kryptering

Cleona använder så kallad postkvantumkryptering. Det innebär: Inte ens
framtida kvantdatorer skulle kunna knäcka dina meddelanden. Du behöver
inte förstå detaljerna -- det enda som är viktigt är att din kommunikation
är så väl skyddad som det är tekniskt möjligt idag.

### Hur fungerar det utan server?

Cleonas nätverk består bara av sina användares enheter. Varje enhet är
en nod, ingen nod är viktigare än en annan, och varje nod känner bara
sina grannar. Fyra saker gör detta nätverk speciellt:

- **Ingen fast punkt.** I appen står ingen serveradress, och nätverket
  beror inte av någon enskild nod. Det finns inget man kunde stänga av
  för att stänga av Cleona.
- **Direkt.** Ditt meddelande ger sig iväg i samma ögonblick som du
  skickar det. Det väntar varken på någon takt eller på något annat.
- **Döljning vid sidan av.** Din enhet skickar hela tiden små
  döljningspaket, så att man utifrån inte kan se när du verkligen
  skriver. Inget meddelande beror på det -- döljningen löper bara vid
  sidan.
- **Koder istället för namn.** Den som skickar ett meddelande vidare ser
  bara en kod som byts varje dag. Normalt känner ingen av dem både
  avsändare och mottagare samtidigt; undantagen står i kapitel 14.

**Tre vägar, alla samtidigt.** När du skickar ett meddelande, provar inte
Cleona en väg i taget, utan alla lämpliga på en gång. Så fort din motpart
bekräftar mottagandet, avbryts de övriga.

1. **I samma nätverk:** Är ni i samma Wi-Fi, går meddelandet direkt
   över.
2. **Via de fasta grannarna:** På internet lämnar din enhet över
   meddelandet till sin fasta granne. Den skickar det vidare till din
   motparts fasta grannar (upp till tre på en gång), och en av dem
   levererar det.
3. **Brevlåda:** Är din motpart offline, lägger Cleona det krypterade
   meddelandet hos tre grannar. Där ligger det i upp till 7 dagar. När
   din motpart kommer online igen, hämtar hen det.

**Hur kommer du in i nätverket?** I appen står ingen serveradress. Din
ingång får du från din första kontakt: Dens inbjudan innehåller de
adresser via vilka din enhet hittar sina första grannar. I samma Wi-Fi
hittar Cleona-enheter också varandra själva. Från och med då lär din
enhet känna fler för varje granne.

### Plattformar

Cleona är tillgänglig för Android, iOS, macOS, Linux och Windows. På datorer och
på Android kommer meddelanden och samtal inom sekunder. På iPhone gäller det så
länge appen är öppen. När den inte är öppen väcker iOS den bara kort då och då;
iOS avgör när. Cleona hämtar då allt som har sparats åt dig och visar en
avisering med en siffra på appikonen. Samtal når inte en iPhone vars app inte är
öppen. Det är en regel från Apple, inte ett fel i Cleona.

---

## 2. Kom igång

### Installera appen

**Android:**
1. Ladda ner APK-filen från Cleonas webbplats eller från GitHub Releases.
2. Öppna filen på din telefon. Vid behov, tillåt installation från
   okända källor (Android frågar dig automatiskt).
3. Tryck på "Installera" och vänta tills installationen är klar.

**iOS:**
1. Öppna TestFlight-inbjudningslänken på din iPhone.
2. Tryck på "Installera". TestFlight är Apples officiella väg för att
   distribuera beta-appar.
3. Efter installationen hittar du Cleona på din hemskärm.

**macOS:**
1. Ladda ner DMG-filen från Cleonas webbplats eller från GitHub Releases.
2. Öppna DMG-filen och dra Cleona till mappen Program.
3. Vid första starten kan macOS fråga om du vill öppna en app från en
   identifierad utvecklare -- bekräfta detta.

**Linux (Ubuntu/Debian):**
1. Ladda ner .deb-filen från Cleonas webbplats eller från GitHub Releases.
2. Installera med dubbelklick eller i terminalen: `sudo dpkg -i cleona-chat-beta_VERSION_amd64.deb`
3. Starta Cleona via programmenyn eller i terminalen med `cleona-chat-beta`.

**Linux (Fedora/openSUSE):**
1. Ladda ner .rpm-filen från Cleonas webbplats eller från GitHub Releases.
2. Installera med: `sudo dnf install cleona-chat-beta-VERSION-1.x86_64.rpm`
3. Starta Cleona via programmenyn eller i terminalen med `cleona-chat-beta`.

**Linux (alla distributioner -- AppImage):**
1. Ladda ner .AppImage-filen från Cleonas webbplats eller från GitHub Releases.
2. Gör filen körbar: Högerklick, egenskaper, körbar, eller i terminalen: `chmod +x cleona-chat-beta-VERSION-x86_64.AppImage`
3. Starta med dubbelklick eller i terminalen: `./cleona-chat-beta-VERSION-x86_64.AppImage`

Paketnamnen gäller betan, som för närvarande är den enda publicerade
versionen; den heter `cleona-chat-beta`.

**Windows:**
1. Ladda ner installationsprogrammet från Cleonas webbplats eller från GitHub Releases.
2. Kör installationsfilen och följ anvisningarna.
3. Starta Cleona via startmenyn eller skrivbordsgenvägen.

### Skapa identitet

Vid första starten skapar Cleona automatiskt en ny identitet åt dig.
Du kan ge dig själv ett visningsnamn -- det är namnet dina kontakter
ser. Detta namn kan ändras när som helst.

### Skriv ner seed-frasen -- det allra viktigaste

När din identitet har skapats visar Cleona 24 ord åt dig. Det är din
**seed-fras** -- din personliga återställningsnyckel.

**Skriv ner dessa 24 ord på papper och förvara dem säkert.**

Varför är detta så viktigt?

- Om din telefon går sönder, tappas bort eller blir stulen, kan du med
  dessa 24 ord återställa hela din identitet på en ny enhet.
- Utan seed-frasen finns det ingen väg tillbaka. Det finns ingen knapp
  för "glömt lösenord" och ingen support som skulle kunna ge tillbaka
  ditt konto -- för det finns inget konto på en server överhuvudtaget.
  Inte ens dina kontakter kan återställa din identitet, oavsett hur
  många de är. En andra enhet med samma identitet kommer i en senare
  version (se kapitel 11).
- Ge aldrig seed-frasen till andra. Den som känner dessa ord kan
  utge sig för att vara du.

Du hittar de 24 orden senare i inställningarna under
"Säkerhetskopiering" -> "Visa återställningsfras", om du vill läsa av dem
en gång till. På Android bekräftar du det med ditt skärmlås.

### Lägg till första kontakten

För att chatta med någon måste du först lägga till personen som kontakt.
Det finns flera sätt till det -- alla förklaras i nästa avsnitt.

---

## 3. Kontakter

### Din inbjudan

Kontakter uppstår i Cleona bara via en inbjudan. Din inbjudan finns där
från första starten -- även utan internet och innan din enhet överhuvudtaget
har hittat en granne. Du hittar den på din identitets-detaljsida
(tryck på ditt eget namn i den övre listen).

Inbjudan finns i två former, som innehåller exakt detsamma:

- som **QR-kod**, när din motpart står bredvid dig, och
- som **textrad**, som du skickar via e-post, SMS eller via en annan
  meddelandetjänst.

Inbjudan innehåller varken telefonnummer eller ett namn ur en katalog.
Den innehåller dina offentliga nycklar och de adresser via vilka din
motpart når dig och dina grannar. För någon som nyss har installerat
Cleona är din inbjudan därför också ingången till nätverket.

### Skanna QR-kod (rekommenderas)

När ni träffas personligen:

1. Du visar din motpart QR-koden från din inbjudan.
2. Din motpart trycker på plus-knappen, väljer "Skanna QR-kod" och
   håller kameran mot din skärm. Det fungerar även med en dators
   webbkamera.
3. Förfrågan går till dig och **automatiskt antas** -- för du har ju
   nyss visat koden själv.

En QR-kod gäller bara en gång: Den första giltiga förfrågan antas,
därefter är inbjudan förbrukad. QR-koden är den säkraste metoden,
eftersom ni då vet exakt med vem ni utbyter kontakten.

### NFC (håll telefonerna mot varandra)

Om båda enheterna stöder NFC:

1. Öppna funktionen för att lägga till kontakt på båda.
2. Håll era telefoner rygg mot rygg mot varandra.
3. Inbjudan överförs och antas automatiskt.

NFC erbjuder liksom QR-koden hög säkerhet, eftersom utbytet bara
fungerar när ni står fysiskt bredvid varandra.

### Skicka textrad

När ni inte kan träffas:

1. Öppna din inbjudan och kopiera textraden.
2. Skicka den till personen som ska lägga till dig -- via mejl, SMS
   eller via en annan meddelandetjänst.
3. Personen klistrar in raden i Cleona i dialogen för att lägga till
   kontakt.
4. Förfrågan dyker upp hos dig under **"Förfrågningar"**. Här **antas
   inte** automatiskt: Du bestämmer själv, för du kan inte veta vem som
   har läst raden på vägen.

### Acceptera kontaktförfrågningar

En inkommande förfrågan skapar ännu ingen kontakt. Den ställer en fråga
till dig och dyker upp i fliken **"Förfrågningar"**. Där ser du namnet
och verifikationsnivån och kan välja:

- **Acceptera** -- först nu blir personen din kontakt.
- **Avvisa** -- förfrågan kasseras.
- **Blockera** -- personen kan inte skicka fler förfrågningar till dig.

### Använd aldrig som fast granne

I menyn för en kontakt hittar du reglaget **"Använd aldrig som fast
granne"** (standard: av). Är det på, skickar denna kontakt inga
meddelanden vidare för dig och får därför heller inte veta när du
skickar eller tar emot meddelanden. Det är tänkt för fallet att ett hot
mot dig kommer från din egen omgivning.

Från främlingar (varken kontakt eller medlem i en gemensam grupp)
släpper Cleona -- utöver en sådan förfrågan -- inget
igenom: inget meddelande, inget samtal, ingen fil. Och även förfrågan
kommer bara fram om avsändaren först har löst en liten beräkningsuppgift.
Det gör masspam dyrt.

### Verifikationsnivåer

Cleona visar dig hur säkert en kontakts identitet är bekräftad:

| Nivå | Betydelse |
|-------|-----------|
| Inte verifierad | Ni är anslutna, men ingenting bekräftar att rätt person verkligen står bakom. |
| Sedd | Nyckelutbytet lyckades, ni kan kommunicera krypterat. |
| Verifierad | Ni har träffats personligen och kopplats via kameraskanning eller NFC. |
| Betrodd | Du har uttryckligen markerat denna kontakt som pålitlig. |

"Verifierad" finns bara för det personliga utbytet. En inbjudan
som kom via en chatt eller via mejl når aldrig denna nivå -- även om
den innehåller samma data.

Ändras en kontakts nycklar utan förvarning, återställer Cleona
den till "Inte verifierad". Det skyddar dig mot att någon obemärkt
utger sig för att vara din kontakt.

---
## 4. Meddelanden

### Skicka och ta emot text

Skriv bara ditt meddelande i inmatningsfältet nedan och tryck på Enter eller
skicka-knappen. Ditt meddelande krypteras automatiskt innan det lämnar din
enhet.

Inkommande meddelanden dyker upp i chattloggen.

### Vad tecknen vid ditt meddelande betyder

| Tecken | Betydelse |
|---------|-----------|
| Klocka | Meddelandet är skapat, men ännu har ingen väg burit det. |
| En bock | Meddelandet är på väg. Det gäller också när det väntar i brevlådan på din motpart. |
| Två bockar | Levererat: Din motparts enhet har bekräftat mottagandet. |
| Varningsikon | I 14 dagar har ingen väg burit meddelandet. Tryck på det för att skicka det igen. |

**Offline är inget fel.** Går din motpart inte att nå, stannar meddelandet
vid en bock tills det hämtas -- det är inte förlorat. Har din egen enhet
ingen anslutning, stannar meddelandet vid klockan och ger sig iväg av
sig själv så fort det finns en väg igen. Varningsikonen dyker upp först
när det inte har hittat någon väg på 14 dagar; då kan du skicka det
igen.

Det gäller också en iPhone vars app inte är öppen: meddelandet väntar i brevlådan
tills iOS väcker appen kort eller tills din motpart öppnar den. Det kan ta längre
tid än på andra enheter.

Två bockar finns bara när mottagaren själv bekräftar mottagandet.
Detta kvitto är krypterat och signerat -- ingen på vägen kan förfalska
det för att låtsas om en leverans till dig.

### Skicka bilder, videos och filer

Du har flera möjligheter:

- **Gem-ikonen** i inmatningsfältet: Tryck på den för att välja en fil,
  en bild eller en video från ditt galleri eller ditt filsystem.
- **Drag and Drop** (skrivbord): Dra en fil till chattfönstret.
- **Klistra in från urklipp** (skrivbord): Kopiera en bild och klistra
  in den i chatten.

Små filer (under 256 KB) färdas direkt i meddelandet. Större filer
delas upp i bitar och förses med felkorrigering, så att enskilda
förlorade bitar inte spelar någon roll. Är ni båda online strömmas de
via en granne; annars läggs de hos enheter som är ständigt nåbara,
tills din motpart hämtar dem.

Från 256 KB frågar Cleona dig per fil innan den skickas: En stor fil
kan inte ta dina meddelandens väg. Filens innehåll förblir krypterat,
och din motpart får inte veta din internetadress. Men överföringen är
utifrån synlig som en händelse, och en främmande enhet som
vidarebefordrar eller förvarar den ser vem som laddar upp och vem som
hämtar. Ditt samtycke gäller bara för just denna fil.

### Röstmeddelanden

1. Håll mikrofonknappen i inmatningsfältet intryckt.
2. Tala in ditt meddelande.
3. Släpp knappen för att skicka meddelandet.

Om taligenkänning är aktiverad på din enhet (se inställningar),
transkriberas ditt röstmeddelande automatiskt till text. Din motpart
ser då både inspelningen och den transkriberade texten.

### Svara på meddelanden (citera)

För att svara på ett visst meddelande:

1. Öppna tre-punktsmenyn bredvid meddelandet.
2. Välj "Svara".
3. Ovanför inmatningsfältet dyker en banner upp med det citerade
   meddelandet.
4. Skriv ditt svar och skicka det.

Det citerade meddelandet visas i ditt svar, så att sammanhanget
är tydligt.

### Redigera och ta bort meddelanden

- **Redigera:** Tre-punktsmenyn för meddelandet, sedan "Redigera".
  Ändra texten och skicka den på nytt. Din motpart ser att meddelandet
  har redigerats. Redigering är möjlig inom 15 minuter efter
  skickandet.
- **Ta bort:** Tre-punktsmenyn för meddelandet, sedan "Ta bort". Det
  meddelandet tas bort hos dig och din motpart. Du kan ta bort dina
  egna meddelanden när som helst -- det finns inget tidsfönster för
  borttagning.

### Emoji-reaktioner

I stället för att skriva ett svar kan du reagera på ett meddelande med
ett emoji:

1. Öppna tre-punktsmenyn eller håll meddelandet intryckt länge.
2. Välj ett emoji från snabbvallet eller öppna emoji-väljaren för
   hela urvalet.
3. Din reaktion dyker upp under meddelandet.

### Kopiera text

Via tre-punktsmenyn för ett meddelande kan du kopiera meddelandetexten
till urklipp.

### Söka meddelanden

Längst upp i chattfönstret hittar du sökfunktionen. Skriv in ett
sökord, och Cleona visar alla träffar i den aktuella chatten. Med
piltangenterna kan du hoppa fram och tillbaka mellan träffarna.

På startsidan finns dessutom ett fliköverskridande sökfilter,
med vilket du kan söka igenom alla konversationer efter ett ord.

### Länkförhandsvisning

När du skickar en länk skapar Cleona automatiskt en förhandsvisning (titel,
beskrivning, miniatyrbild). Denna förhandsvisning skapas på din enhet
och skickas med -- din motpart behöver ingen anslutning till den
länkade webbplatsen för det.

Vad ett tryck på en mottagen länk gör ställer du in i inställningarna
under "Öppna länkar": "Normalt", "Föredra ett privat fönster" (där
enheten inte kan öppna ett privat fönster öppnas länken normalt) eller
"Fråga varje gång".

---

## 5. Grupper

### Skapa grupp

1. Växla till fliken "Grupper".
2. Tryck på plus-knappen.
3. Ge gruppen ett namn.
4. Välj de kontakter du vill bjuda in.
5. Tryck på "Skapa".

De inbjudna kontakterna får en avisering och kan gå med i gruppen.

### Hur gruppmeddelanden skyddas

I en grupp med upp till 16 medlemmar skickar Cleona varje meddelande till
varje medlem enskilt -- var och ett krypterat bara för den medlemmen, som
om du hade skrivit ett eget meddelande till var och en. Bockarna på ett
gruppmeddelande visar statusen hos den medlem där det har kommit
minst långt.

Växer gruppen över 16 medlemmar använder den en gemensam nyckel. Den
byts varje dag och dras på nytt när en medlem lämnar gruppen eller tas
bort; en ny medlem kan läsa från och med sitt inträde. Där visar
bockarna inte längre statusen hos varje medlem, utan att meddelandet har
lagts i nätverket. Sjunker gruppen till 12 eller färre medlemmar, går
den tillbaka till enskild sändning.

### Bilder i grupper och kanaler

I inställningarna för en grupp eller en kanal ställer du in med "Ladda
alltid bilder" om bilder ska laddas direkt eller först när du trycker
på en.

### Bjud in medlemmar

Även efter skapandet kan du bjuda in fler kontakter:

1. Öppna gruppinfon (tre-punktsmenyn i gruppöversikten eller
   övre listen i gruppchatten).
2. Tryck på "Bjud in".
3. Välj de kontakter du vill lägga till.

### Roller

Varje grupp har tre roller:

- **Ägare (Owner):** Har full kontroll. Kan lägga till och ta bort
  medlemmar, utse administratörer och hantera gruppen. Ägaren kan
  också överföra sin status till en annan medlem.
- **Admin:** Kan ta bort medlemmar och hjälpa till med hanteringen.
- **Medlem:** Kan läsa och skriva meddelanden.

### Lämna grupp

1. Öppna tre-punktsmenyn i gruppöversikten.
2. Välj "Lämna".
3. Bekräfta ditt val.

När du lämnar en grupp förblir dina tidigare meddelanden synliga för
de övriga medlemmarna.

---

## 6. Offentliga kanaler

### Vad är kanaler?

Kanaler är offentliga diskussionsforum inom Cleonas nätverk.
Till skillnad från grupper kan alla här läsa med, utan att behöva
bli inbjuden. Bara ägaren och administratörerna kan publicera inlägg --
prenumeranterna läser med.

### Hitta och gå med i kanaler

1. Växla till fliken "Kanaler".
2. Öppna fliken "Sök".
3. Sök bland de tillgängliga kanalerna efter namn eller ämne.
4. Tryck på en kanal och sedan på "Prenumerera".

Kanaler kan filtreras efter språk. Vissa kanaler är märkta som "Ej
för unga" -- dessa syns bara om du i din profil har bekräftat att
du är över 18.

### Skapa egen kanal

1. Växla till fliken "Kanaler".
2. Tryck på plus-knappen.
3. Skriv in ett kanalnamn (måste vara unikt i hela nätverket).
4. Välj språk och om kanalen ska vara offentlig eller privat.
5. Frivilligt: Lägg till en beskrivning och en bild.
6. Tryck på "Skapa".

För offentliga kanaler kan du bestämma om innehållet klassas som
"Ej för unga".

### Rapportera innehåll

Om du lägger märke till olämpligt innehåll i en offentlig kanal kan du
rapportera det. Cleona använder ett decentraliserat moderingssystem:
rapporter bedöms av slumpmässigt utvalda medlemmar i nätverket (en sorts
"jury"). Konstateras en överträdelse får kanalen en varning. Vid
upprepade överträdelser nedgraderas den i sökindexet eller
spärras.

### Systemkanaler

Cleona har två inbyggda systemkanaler:

- **Bug Log:** När Cleona känner igen ett fel frågar den dig om du vill
  skicka en felrapport; innan dess ser du exakt vad som publiceras.
  Dessa rapporter hamnar i Bug Log-kanalen, där de kan granskas av
  gemenskapen. En rapport bär inget namn och inget innehåll från dina
  konversationer, utan ett pseudonym. I betan anger den dessutom din
  identifierare (User-ID), så att utvecklarna kan fråga dig. Du kan
  också manuellt skicka en loggrapport (med
  förhandsgranskningsdialog och uttryckligt samtycke).
- **Feature Requests:** Här kan användare lämna in funktionsönskemål
  och rösta på befintliga förslag. Förslagen sorteras efter
  röster.

Varje dator håller upp till 25 MB per systemkanal, varje mobil upp till
5 MB; är det fullt, går det äldsta ut först -- aldrig det du själv
redan har sett.

---
## 7. Samtal

### Starta röstsamtal

1. Öppna chatten med kontakten du vill ringa.
2. Tryck på telefonikonen i den övre listen.
3. Vänta tills din motpart besvarar samtalet.

Under samtalet ser du en tidslinje, samtalslängden och har
tillgång till att stänga av mikrofonen och högtalare.

För att lägga på trycker du på den röda lägg på-knappen.

Om du ser "Inte nåbar" kan motpartens enhet inte nås just nu, till exempel en
iPhone vars app inte är öppen. Skicka ett meddelande i stället.

### Starta videosamtal

1. Öppna chatten med kontakten.
2. Tryck på kameraikonen i den övre listen.
3. Din videobild dyker upp i ett litet fönster, din motparts bild i
   den stora ytan.

Du kan under samtalet växla mellan fram- och bakkamera.

### Inkommande samtal

När någon ringer dig dyker ett meddelandefönster upp med uppringarens
namn. Du kan:

- **Acceptera** -- samtalet börjar.
- **Avvisa** -- uppringaren aviseras.

Befinner du dig just nu i ett samtal ringer det inte vid ett nytt
samtal; du får i stället ett meddelande "Missat samtal". Detsamma
gäller ett gruppsamtal som du inte har accepterat -- meddelandet står
då i gruppchatten.

Ringer någon en av dina identiteter som just nu inte visas, ringer det
ändå; samtalsskärmen namnger vilken av dina identiteter som rings upp.

På iPhone ringer det bara medan appen är öppen. Den som ringer dig medan appen
inte är öppen ser "Inte nåbar" efter 10 sekunder. Så fort du öppnar appen hittar
du ett meddelande om det missade samtalet.

### Gruppsamtal

Du kan också föra gruppsamtal där flera personer deltar samtidigt.
Samtalet organiseras via ett intelligent vidarebefordringsträd,
så att inte varje deltagare behöver vara direkt ansluten till varje
annan. Alla samtal är krypterade hela tiden.

Varje gruppmedlem kan starta ett gruppsamtal. Två deltagare som inte
är kontakter med varandra ser aldrig den andras internetadress: Deras
ljud och bild går via en deltagare som är kontakt med båda. Finns det
ingen sådan är de två inte anslutna, och rutan säger "Ingen gemensam
kontakt i samtalet". Är en vidarebefordring överbelastad, finns ljudet
kvar, och videon faller bort för det paret.

### Kryptering vid samtal

Alla samtal krypteras med engångsnycklar som bara existerar under
samtalets längd. Efter påläggning raderas dessa nycklar omedelbart.
Ingen kan i efterhand avkryptera ett tidigare samtal.

Ärligt talat: Samtal går, i den mån det är möjligt, direkt mellan
enheterna, för redan en liten fördröjning stör när man talar. Till
skillnad från meddelanden kan din internetleverantör därför vid ett
samtal se med vilken internetadress du är ansluten. Vad ni säger ser
den inte.

Vid ett samtal ser också din kontakt din internetadress. Vill du inte
det hos en kontakt, stäng av "Tillåt samtal" i dennes meny (standard:
på). Stänger du av senare, vet kontakten fortfarande en adress som den
redan har sett.

---

## 8. Kalender

Cleona innehåller en inbyggd kalender som fungerar krypterat och helt
decentraliserat -- utan molntjänst.

### Vyer

Kalendern erbjuder fem vyer: Dag, Vecka, Månad, År och en
uppgiftsvy. Växla mellan dem via flikarna längst upp på
kalenderskärmen.

### Skapa händelser

Tryck på en tidslucka eller använd lägg till-knappen för att skapa en ny
händelse. Du kan mata in titel, datum, tid, plats och anteckningar.
Händelser sparas krypterade på din enhet.

### Återkommande händelser

Händelser kan upprepas dagligen, veckovis, månadsvis eller årsvis.
Du kan anpassa mönstret (t.ex. varannan tisdag,
första dagen varje månad) och ange ett slutdatum eller ett antal
upprepningar.

### Bjud in kontakter

När du skapar eller redigerar en händelse kan du bjuda in dina
Cleona-kontakter. De får en krypterad kalenderinbjudan och kan svara
med Ja, Nej eller Kanske. Ändringar i händelsen skickas
automatiskt till alla inbjudna.

### Ledig/Upptagen-visning

Du kan dela din tillgänglighet med kontakter utan att röja
händelseinformation. Det finns tre integritetsnivåer: fullständiga
detaljer, bara tidsblock eller dold. Du kan ställa in en standard och
åsidosätta den per kontakt.

### Påminnelser

Händelser kan ha påminnelser som utlöser en
systemavisering innan händelsen börjar. Du kan snooza påminnelser vid
behov.

### Extern kalendersynk

Cleona kan synkronisera med externa kalendertjänster:

- **CalDAV** -- Anslut till vilken CalDAV-kompatibel server som helst
  (Nextcloud, Radicale osv.).
- **Google Kalender** -- Synkronisering via Google Calendar API med
  säker OAuth2-autentisering.
- **Lokal CalDAV-server** -- Cleona kan starta en lokal CalDAV-server på
  din enhet, så att skrivbordskalenderappar (Thunderbird, Outlook,
  Apple Kalender, Evolution) kan synkronisera med din Cleona-kalender.
- **Android-systemkalender** -- Händelser från Cleona kan överföras till
  den inbyggda kalenderappen på din Android-enhet.
- **ICS-filer** -- Importera och exportera händelser i
  iCalendar-standardformat.

### PDF-export

Du kan skriva ut eller exportera varje kalendervy (Dag, Vecka, Månad, År)
som ett PDF-dokument.

---

## 9. Omröstningar

Du kan skapa omröstningar i varje chatt eller grupp för att samla
åsikter eller planera möten.

### Omröstningstyper

Cleona stöder fem typer av omröstningar:

- **Enkelval** -- Deltagarna väljer ett alternativ.
- **Flerval** -- Deltagarna kan välja flera alternativ.
- **Mötesomröstning** -- Hitta en tid som passar alla. Varje
  deltagare markerar tider som tillgängliga, kanske eller inte
  tillgängliga.
- **Skala** -- Betygsätt något på en numerisk skala (t.ex. 1 till 5).
- **Fritext** -- Deltagarna skriver sitt eget svar.

### Skapa omröstning

Öppna en chatt och tryck på omröstningsikonen (eller använd
bilagsmenyn). Välj omröstningstyp, formulera din fråga och
alternativen, och skicka omröstningen. Den dyker upp som ett meddelande
i chatten.

### Rösta

Tryck på en omröstning för att lägga din röst. Du kan när som helst
ändra eller dra tillbaka din röst.

### Anonym röstning

Omröstningar kan ställas in för anonym röstning. Om det är aktiverat
är rösterna kryptografiskt anonyma -- ingen, inte ens
omröstningsskaparen, kan se vem som röstade för vad. Röstantalet
förblir ändå synligt.

### Mötesomröstning till kalendern

När en mötesomröstning är avslutad kan vinnartiden med ett tryck
omvandlas direkt till en kalenderpost.

---
## 10. Flera identiteter

### Varför flera identiteter?

Tänk dig att du vill hålla isär arbetsliv och privatliv --
likt två olika telefonnummer, men utan en andra telefon.
I Cleona kan du använda flera identiteter på en enhet. Varje
identitet har ett eget namn, en egen profilbild, egna kontakter och
egna konversationer.

### Skapa ny identitet

1. I den övre listen ser du din aktuella identitet som en flik.
2. Tryck på plus-tecknet (+) till höger om dina identitetsflikar.
3. Skriv in ett namn för den nya identiteten.
4. Klart -- den nya identiteten är omedelbart aktiv.

### Växla mellan identiteter

Tryck bara på identitetsfliken i den övre listen. Växlingen
är omedelbar -- ingen väntetid, ingen omladdning.

### Alla är aktiva samtidigt

En viktig punkt: Alla dina identiteter är aktiva samtidigt. Även
om du just nu visas som "Arbete", tar din "Privat"-
identitet emot meddelanden likadant hela tiden. Du missar inget, oavsett
vilken identitet du just har valt.

### Identitets-detaljsida

När du trycker på fliken för din just nu aktiva identitet öppnas
detaljsidan. Här kan du:

- Visa din QR-kod för kontakter.
- Ändra eller ta bort din profilbild.
- Lägga till en profilbeskrivning.
- Ändra ditt visningsnamn.
- Välja en design (skal) för denna identitet.
- Ta bort identiteten, om du inte längre behöver den.

### Ta bort identitet

När du tar bort en identitet aviseras dina kontakter om
det. Identiteten och all tillhörande data tas bort från din
enhet. Detta förfarande går inte att ångra.

---

## 11. Flera enheter

### En identitet, en enhet -- tills vidare

En identitet körs idag på en enhet. En andra enhet för samma identitet
kommer i en senare version; i inställningarna under "Enheter" ->
"Hantera enheter" står "Koppla ytterligare enhet" därför fortfarande som
"Inte tillgängligt än".

När det kommer gäller: Alla enheter är likvärdiga, det finns ingen
huvudenhet. En ytterligare enhet ställer du in med dina 24 ord, och en
av dina hittillsvarande enheter samtycker. Högst 5 enheter.

Matar du in dina 24 ord på en ny enhet idag, flyttar du: Identiteten
återställs på den nya enheten, och din hittillsvarande enhet tar
efteråt bort den hos sig (se kapitel 12).

På flera enheter kan du idag använda olika identiteter (kapitel 10).

### Rotera identitetsnycklar

Misstänker du att någon har fått tag i dina nycklar, kan du under
"Hantera enheter" -> "Rotera identitetsnycklar" skapa nya nycklar.
Dina kontakter aviseras, dina öppna inbjudningar återkallas. Viktigt:
Därefter skapar de 24 orden ensamma bara de gamla nycklarna. Skapa
därför direkt efteråt ett nytt återställningspaket; återställa kan du
därefter bara tillsammans med detta paket.

---

## 12. Återställning

### Använd seed-frasen

Om du tappar din enhet eller ställer in en ny:

1. Installera Cleona på den nya enheten.
2. Välj "Återställ" vid starten.
3. Skriv in dina 24 ord.
4. Cleona återskapar därifrån alla dina identiteter -- med samma
   nycklar som förut. För dina kontakter är du samma person.

### Vad som kommer tillbaka -- och vad som inte

Din identitet ligger i de 24 orden, dina kontakter och din historik
inte. Tillbaka kommer din nätåtkomst via **återställningspaketet**: Din
enhet lägger ett litet, krypterat paket i nätverket. Bara dina 24 ord
kan hitta och öppna det. Där står vad din nya enhet behöver för att nå
dina kontakter igen, och vad som under tiden låg för dig i nätverket.
För det behöver ingen kontakt vara online.

Den tidigare chathistoriken för en återställning inte tillbaka.

Återställningspaketet lever i 7 dagar och förnyas av din enhet så länge
den är igång; i inställningarna ser du hur länge det gäller. Har ingen av
dina enheter varit igång på mer än 7 dagar, har det löpt ut. Då
återställer de 24 orden din identitet ändå, men dina kontakter måste du
bjuda in på nytt; det som under tiden låg för dig i nätverket är
förlorat.

### Återställning är att flytta

Upptäcker din hittillsvarande enhet senare att identiteten har
återställts någon annanstans, tar den bort den hos sig -- med dess
historik. Därför: Den som har dina 24 ord kan på detta sätt hämta din
identitet från din enhet. Tills alla kontakter är tillbaka påminner
appen dig; med "Slutför och förnya nycklar" avslutar du
återställningen själv.

### Vad ingen kan återställa

Detta är viktigt, och vi säger det därför tydligt:

- **Ingen utom du kan återställa din identitet.** Inte utvecklaren,
  inte en support, och inte heller dina kontakter -- oavsett hur
  många de är. Det finns ingen masternyckel och ingen del av din
  nyckel som är deponerad hos andra.
- **Har du tappat de 24 orden och inte har någon enhet kvar, är din identitet
  förlorad.** Då återstår bara att skapa en ny och bjuda in dina kontakter
  på nytt.

Det bästa skyddet: Skriv de 24 orden på papper och förvara dem
säkert.

---
## 13. Inställningar

Inställningarna når du via kugghjulsikonen i det övre högra
hörnet.

### Aviseringar och ringsignaler

- Välj mellan sex olika ringsignaler för inkommande samtal.
- Ställ in ett meddelandeljud.
- På Android-enheter kan du dessutom aktivera eller
  avaktivera vibration.
- **"Stäng av ljud för allt"** låter inget meddelande på denna enhet
  längre ringa, vibrera eller göra sig påmind -- för alla identiteter.
  Samtal ringer vidare.
- **"Tysta timmar"** ställer du in per identitet med Från/Till. Under
  denna tid ringer eller vibrerar inget meddelande från denna
  identitet, och ingen avisering visas; meddelandena kommer ändå fram.
- **"Aviseringar utan innehåll"** (standard: av) visar bara att ett
  meddelande, en inbjudan eller en påminnelse har kommit -- utan
  avsändare, namn och text. Samtal visar fortsatt namnet.
- Det som efter starten kommer på en gång rapporterar Cleona i en
  samlingsavisering ("5 nya meddelanden i 2 konversationer"); allt
  senare enskilt. Ett tryck på en meddelandeavisering öppnar
  konversationen, även i en annan identitet.

### Designer (skal)

Cleona erbjuder tio olika designer: Teal, Ocean, Sunset, Forest,
Amethyst, Fire, Storm, Slate, Gold och Contrast. Contrast-designen uppfyller
den högsta tillgänglighetsnivån (WCAG AAA) och är särskilt
lättläst vid nedsatt syn.

Varje identitet kan ha sin egen design. Du ändrar designen i
identitets-detaljsidan (tryck på den aktiva identitetsfliken).

Dessutom kan du i inställningarna under "Utseende" växla mellan
ljust, mörkt och systemtema.

### Ändra språk

Cleona är tillgängligt på 34 språk, däribland språk med
höger-till-vänster-skrift (t.ex. arabiska, hebreiska). Ändra språk i
inställningarna under "Språk".

### Mediearkivering

Om du har en nätverkslagring (NAS) eller en delad mapp
hemma, kan Cleona automatiskt flytta ut din media dit. Stöds
gör SMB, SFTP, FTPS och WebDAV.

Så här fungerar den stegvisa lagringen:
- De första 30 dagarna: Allt ligger kvar på din enhet.
- Efter 30 dagar: En miniatyrbild ligger kvar på enheten, originalet
  arkiveras.
- Efter 90 dagar: Bara en liten miniatyrbild ligger kvar på enheten.
- Efter ett år: Bara en platshållare ligger kvar, originalet ligger
  säkert i arkivet.

Du kan när som helst trycka på ett arkiverat media för att hämta tillbaka
det -- förutsatt att du är ansluten till ditt hemnätverk. Särskilt
viktig media kan fästas, så att den aldrig flyttas ut.

Under "Lagringsbudget" ställer du in hur många MB media som får bli
kvar på enheten (standard: 100 MB på mobilen, 2 GB på datorn). Är den
full, arkiveras det äldsta mediet som inte är fäst först. Ett original
raderas bara om det ligger säkert i arkivet -- textmeddelanden bevaras
alltid.

### Transkription för röstmeddelanden

Om det är aktiverat transkriberas dina röstmeddelanden lokalt på din
enhet till text (med open-source-modellen Whisper). Den transkriberade
texten skickas tillsammans med inspelningen till din motpart. Transkriptionen
sker helt på din enhet -- ingen data går till externa tjänster.

Vilken modell (tiny, base, small) som laddas ner ställer du in en gång
för enheten; språket (automatiskt eller fast) per identitet.

### Automatisk hämtning

Du kan ställa in från vilken storlek media ska hämtas
automatiskt. Så kan du till exempel låta bilder laddas automatiskt, men
själv bestämma vid stora videos.

### Enheter

Under "Enheter" -> "Hantera enheter" ser du denna enhet. Att koppla en
ytterligare enhet kommer med en senare version (kapitel 11).

### Nätverk

Cleona behöver inga nätverksinställningar för att fungera. Det finns
tre nätverksreglage:

- **Portöppning i routern** (standard: på). Cleona ber din egna
  router att öppna en dörr för Cleona. Fungerar det, är din enhet
  bättre nåbar för andra och hjälper nätverket. Cleona talar då bara med
  din router, inte med internet.
- **Offentliga adressposter** (standard: på). Har din enhet för
  få grannar, slår den upp ytterligare ingångspunkter i en offentlig
  katalog (Nostr), och är den själv väl nåbar, registerar den sig
  där. Posten innehåller en adress, inget namn och ingen kontakt.
  Stänger du av den, hittar din enhet grannar bara via inbjudningar,
  det lokala nätet och de grannar den redan känner.
- **Färre döljningspaket i Wi-Fi** (standard: av). I Wi-Fi eller på
  kabel kan du stänga av de tomma döljningspaketen. Då är det där
  igen att se när du skriver. I mobildata finns inte detta reglage -- där
  skickar Cleona ändå bara ett döljningspaket per minut.

Döljningstrafiken i sin helhet kan man inte stänga av. Det är
medvetet: Bara om den alltid löper säger din enhets aktivitet ingenting
om huruvida du just skriver.

Ovanför de tre reglagen står **databesparingsläget**: I mobildata
föreslår Cleona det, men slår aldrig på det själv. Det sparar data, men
din enhet blir lättare att känna igen utifrån.

Därunder ställer du in **"Cache för andras media"**: Din enhet håller
krypterade delar av andras media i upp till 7 dagar, så att de når sina
mottagare (standard: 100 MB på mobilen, 1 GB på datorn). En mindre
storlek frigör utrymmet omedelbart -- de äldsta delarna först.

---

## 14. Säkerhet

### Vad betyder postkvantumkryptering?

Dagens kryptering bygger på matematiska problem som är extremt svåra
att lösa för vanliga datorer. Kvantdatorer skulle i framtiden kunna
lösa några av dessa problem snabbt. Postkvantumkryptering använder
ytterligare metoder som också motstår kvantdatorer.

Cleona kombinerar båda ansatserna: klassisk kryptering för
tillförlitlighet och postkvantummetoder för framtidssäkerhet. Så är
du skyddad mot dagens och framtidens hot samtidigt.

För varje enskilt meddelande skapas en egen nyckel. Även om
en angripare skulle knäcka nyckeln för ett meddelande, kunde den
inte läsa något annat meddelande med den.

### Varför ingen server är säkrare

Vid konventionella meddelandetjänster går dina meddelanden via
leverantörens servrar. Även om de där kunde vara krypterade: Leverantören
har tillgång till metadata (vem kommunicerar med vem, när, hur ofta, varifrån) och
måste under omständigheter lämna ut dem på domstolsbeslut.

Vid Cleona finns ingen sådan central punkt. Det finns ingen plats där
all metadata samlas, och ingen katalog i vilken man kunde
slå upp vem du är eller vem du känner.

### Vem ser att du skriver med någon?

Kryptering skyddar **vad** du skriver. Lika viktigt är att
ingen enskild observatör får veta **med vem** och **när** du skriver.
För det ser Cleona till så:

- **På internet aldrig direkt.** Skickade din enhet ett meddelande direkt till
  din motparts internetadress, kunde din leverantör se med
  vem du skriver. Därför går ett meddelande på internet alltid via era
  fasta grannar: din och din motparts.
- **Grannar du litar på.** Dina fasta grannar är, i den mån det är
  möjligt, enheter som tillhör dina egna kontakter -- upp till tre som
  just är nåbara utifrån. Faller en bort, träder en annan kontakt in.
  En kontakt går inte att köpa med servrar; en godtycklig nod i
  nätverket däremot. Har du ännu ingen nåbar kontakt, tar Cleona en
  annan granne. Din inbjudan namnger aldrig någon av dina kontakter, så
  att ingen via dem får veta en väns adress.
- **Koder istället för namn.** Grannarna ser inga namn och inga
  identifierare, utan bara en kod. Den gäller för just er två, i en
  riktning, för en dag -- nästa dag är det en annan. Din granne vet
  varifrån paketet kommer, men inte varthän det till slut går. Din
  motparts granne vet varthän det går, men inte varifrån det kom. Normalt
  ser ingen på vägen båda ändarna.
- **Döljningstrafiken.** Din enhet skickar hela tiden, i
  oregelbundna intervall, döljningspaket till sina grannar. De är
  lika stora som äkta paket, går via samma port och går inte att
  skilja från dem utifrån. Om en människa skriver just nu eller
  enheten bara löper går inte att se med det. Dina meddelanden
  väntar aldrig på döljningstrafiken --
  de ger sig iväg omedelbart, den löper bara vid sidan.

**Vad döljningstrafiken kostar:** I Wi-Fi cirka 13 MB per dag. I mobildata skickar
Cleona bara ett döljningspaket per minut, det är cirka 1,7 MB per dag. Orsaken
till begränsningen i mobildata är inte datamängden, utan batteriet:
Varje paket väcker radiomodemet.

**Vad Cleona inte kan dölja** -- ärligt talat:

- Ingen **enskild** observatör ser vem som skriver med vem -- varken din
  leverantör eller noderna längs vägen. Den som däremot **övervakar båda
  ändarna samtidigt**, till exempel en stat som övervakar din anslutning
  och din motparts, eller ställer båda grannarna, kan med tiden
  koppla: Paket ut från dig, strax därpå paket in till din motpart.
  Upprepas det tillräckligt ofta, ger det ett samband.
- Döljningstrafiken försvårar denna koppling, men förhindrar den inte. Den
  döljer enskilda meddelanden, inte mängden: Den som skickar mycket,
  ökar den totala trafiken från sin enhet.
- En kontakt som är din fasta granne får veta **när** och **hur mycket**
  du skickar och tar emot -- inte med vem och inte vad. Kommer hotet
  från din egen omgivning, kan du undanta varje kontakt (se
  kapitel 3, "Använd aldrig som fast granne").
- Har två nya användare bara samma enda granne, går deras meddelande
  via just denna nod, och den ser båda ändarna. Så fort en av
  de båda har fler grannar, är det över.
- Din inbjudan innehåller dina internetadresser. Den som har textraden,
  ser var du är online -- ge den bara till människor du litar på med det.
- En granne som vidarebefordrar ser att två koder utbyter paket --
  inte vem som står bakom, och inte vad som ligger i.
- En signal från ett pågående samtal kan, om den första grannen just
  inte svarar, gå via en nod som ser båda ändarna; den får veta att ni
  ringer tillsammans.
- En stor fil som du har samtyckt till ser datorn som vidarebefordrar
  eller förvarar den, i båda ändarna (se kapitel 4).
- Vid samtal gäller inte skyddet mot leverantören, och din kontakt ser
  din internetadress (se kapitel 7).

### Vad händer när din motpart är offline?

1. Cleona startar alla lämpliga vägar samtidigt: i samma Wi-Fi direkt,
   på internet via två grannar -- och dessutom brevlådan.
2. För brevlådan lägger Cleona det krypterade meddelandet hos tre
   grannar. Så fort två har bekräftat mottagande, gäller det som
   deponerat.
3. Cleona väljer då företrädesvis grannar där din motpart också
   letar -- först grannen som dess inbjudan namnger.
4. Meddelandet väntar där i upp till 7 dagar. När din motpart kommer
   tillbaka, hämtar den det och bekräftar mottagandet åt dig. Först då ser du
   två bockar.

Brevlådan kan bara din motpart tömma: Hämtning och radering går
bara med en nyckel som bara den personen har, och raderas gör först när
den har bekräftat mottagandet. Grannarna ser bara krypterade
paket under ett värde som byts varje dag.

### Främlingar kommer inte igenom

Från någon som varken är din kontakt eller medlem i en gemensam grupp
tar Cleona emot exakt två saker:
frågan efter dina offentliga nycklar, så länge en av dina
inbjudningar är öppna, och en kontaktförfrågan. Förfrågan måste bära en giltig
inbjudan från dig, och avsändaren måste först ha löst en beräkningsuppgift.
Allt annat -- meddelanden, samtal, filer -- kasseras,
innan det överhuvudtaget når appen. Den som bara har ditt tryckta visitkort
kan alltså inte bara ringa dig. En medlem i en gemensam grupp når dig bara
i denna grupp -- med gruppmeddelanden och gruppsamtal, aldrig enskilt.

### Anticensur

Cleona är byggt så att det är svårt att blockera:

- **Ingen server, ingen fast adress.** I appen står ingen adress som
  man kunde spärra, och nätverket beror inte av någon enskild nod.
- **Ingen fast port.** Varje enhet väljer en
  slumpmässig port vid första starten. Det finns ingen känd portnummer
  vid vilken man kunde
  känna igen Cleona-trafik.
- **Som slumpdata.** Etableringen av anslutningen mellan två enheter är
  så kodad att den inte går att skilja från slumpdata.
- **Många ingångar.** Varje inbjudan, varje granne och varje enhet i
  samma Wi-Fi är en möjlig väg tillbaka in i nätverket.

### Säker nyckellagring

På plattformar som stöds lagrar Cleona dina krypterings-
nycklar i operativsystemets säkra nyckelring (Android Keystore,
iOS Keychain, macOS Keychain). Där det är tillgängligt erbjuder det
hårdvarubaserat skydd för dina nycklar.

### Databaskryptering

Dina meddelanden och konversationer ligger i en krypterad
databas -- en egen för varje identitet, var och en med egen nyckel.
Krypterad är inte bara själva databasen, utan även dess
tillfälliga filer; ingenting skrivs okrypterat till disken,
inte ens tillfälligt. Inställningar, kontakter och media är också
krypterat lagrade.

Nycklarna härleds från dina 24 ord och existerar bara
på din enhet. Även den som får din enhet i sina händer och
läser ut data, hittar utan dessa nycklar bara oläsbara data.

Okrypterat blir det bara där du själv tar innehåll ut ur Cleona:
- när du sparar en fil från en chatt på din enhet,
- när du lägger en bild i dina bilder med skärmdump-knappen,
- när du delar något till en annan app,
- när du ställer in mediearkivering (kapitel 13): De arkiverade
  originalen ligger okrypterade på din nätverkslagring hemma, så att du
  kan öppna dem där även utan Cleona,
- när du speglar händelser i Android-systemkalendern: Där kan andra
  appar med kalenderåtkomst läsa dem.

Det som har gått ut på det sättet raderas inte med meddelandet och
löper inte ut med det.

### Skydd på skärmen

På Android, Windows och macOS tillåter Cleona ingen skärminspelning
genom andra appar. Behöver du en bild, använd skärmdump-knappen i den
övre listen: Den lägger bilden i dina bilder -- okrypterat. I en
konversation där vidarebefordran inte är tillåten finns ingen
skärmdump.

---

## 15. Programuppdateringar

### Hur får jag uppdateringar?

Cleona kan uppdateras på olika vägar. Målet är att du
ska kunna få uppdateringar även när enskilda distributionsvägar faller ut
eller spärras:

1. **App Store / Play Store:** Så snart Cleona finns där och du har
   installerat det via en butik, får du uppdateringar som vanligt via
   butiken. På iPhone kommer uppdateringar via TestFlight.
2. **GitHub Releases:** På projektets GitHub-sida hittar du
   signerade installationspaket för alla plattformar.
3. **Uppdateringar via nätverket:** Cleona kan hämta en uppdatering direkt
   via nätverket -- utan nedladdningsserver. Den nya versionen är
   uppdelad i felkorrigerande bitar som sprids i nätverket; en del
   av dem färdas till och med med i döljningstrafiken. Din enhet
   samlar tillräckligt många bitar och
   sammanställer uppdateringen. Oftast överförs bara ändringen --
   några få MB i stället för hela appen. Det gäller Linux, Windows och
   Android; under macOS laddar du ner nya versioner från webbplatsen
   eller från GitHub.
4. **Inbjudningslänkar:** Du kan skapa inbjudningslänkar som
   innehåller allt en ny användare behöver för att installera Cleona och
   ansluta till nätverket.
5. **Fysisk överföring:** I miljöer utan internet kan du vidarebefordra Cleona
   via USB-minne eller i det lokala nätverket.

### Så här går en uppdatering till

1. Cleona samlar bitarna av en ny uppdatering automatiskt i bakgrunden
   och sammanställer dem.
2. Först när uppdateringen är **komplett** och dess **signatur har verifierats**
   erbjuder Cleona den åt dig. Du får alltså aldrig en ofullständig eller
   overifierad uppdatering erbjuden.
3. Trycker du på "Installera", startar installationen utan ytterligare
   frågor. På Android visar dessutom systemet sin
   installationsdialog.

Äldre versioner erbjuds inte -- en uppdatering går alltid bara
framåt. Är en version så gammal att den inte längre kan samarbeta
med nätverket, visar Cleona det tydligt och ber dig att
uppdatera.

### Signaturverifiering

Varje uppdatering är dubbelt signerad: med en klassisk och en
postkvantummetod. Cleona verifierar båda signaturerna automatiskt. Så
är säkerställt att bara uppdateringar från den officiella utvecklaren accepteras
-- även när uppdateringen kom via nätverket från främmande enheter. En
uppdatering uppstår aldrig automatiskt från utvecklingen, utan bara när
utvecklaren signerar den manuellt.

---
## 16. Vanliga frågor

### "Kan jag använda Cleona utan internet?"

Cleona behöver en nätverksanslutning, men inte nödvändigtvis internet:
I samma Wi-Fi hittar Cleona-enheter varandra själva och kan skriva
helt utan internetåtkomst. Att vara online samtidigt behöver du inte
med din motpart: Är hen offline, väntar meddelandet i upp till 7 dagar
i brevlådan hos tre grannar, tills hen hämtar det.

### "Vad händer om jag tappar min seed-fras?"

Så länge en enhet med din identitet fortfarande löper, är ingenting förlorat --
där skriver du bara vidare. På den enhet där du skapade
identiteten kan du oftast läsa av de 24 orden på nytt (se
kapitel 2). Lita inte på det: En nyinstallation tar bort denna kopia,
och på Android förstör även borttagning eller ändring av skärmlåset
den. Har du varken orden eller
en enhet, finns det ingen väg tillbaka -- inte heller via dina kontakter,
utvecklaren eller någon annan. Därför är det så viktigt att förvara de 24
orden säkert.

### "Kan någon läsa mina meddelanden?"

Nej. Varje meddelande krypteras med en engångsnyckel som
bara gäller för just det meddelandet. Bara du och din motpart kan
avkryptera meddelandet. Det finns ingen central server, ingen masternyckel
och ingen tillgång för utvecklaren. Även om en enhet på
transportvägen vidarebefordrar meddelandet, ser den bara krypterat datagytter
och en kod. Din granne vet att paketet kommer från dig, men inte till
vem det går; din motparts granne vet till vem det går, men inte från
vem.

### "Varför behöver jag inget telefonnummer?"

För att din identitet är helt kryptografisk. I stället för ett telefonnummer
eller en e-postadress som är kopplad till ditt riktiga namn, identifierar dig
ett nyckelpar som har skapats på din enhet. Kontakter lägger du till
via QR-kod, NFC eller textraden i din inbjudan -- inte via en
telefonkatalog. Det betyder
mer integritet, eftersom ditt meddelandekonto inte är kopplat
till din verkliga identitet.

### "Hur hittar jag personer på Cleona?"

Cleona har medvetet ingen kontaktsökning efter telefonnummer eller namn -- det vore
ett integritetsproblem. I stället utbyter du inbjudningar direkt: via
QR-kod, NFC eller som textrad via en annan väg. Det är som
att byta visitkort i stället för att slå upp i telefonkatalogen.

### "Fungerar Cleona även utomlands?"

Ja. Så länge du har en internetanslutning fungerar Cleona överallt i
världen. Eftersom det inte finns en central server och ingen fast adress, låter
sig tjänsten inte enkelt stängas av för vissa länder. Hur Cleona
försvårar blockering står i kapitlet "Säkerhet" under "Anticensur". Ett land
som blockerar all okänd trafik vid gränsen kan dock också
stoppa Cleona.

### "Är Cleona gratis?"

Ja. Cleona är gratis och utan reklam att använda. Eftersom det inte finns en central
server, uppstår heller inga serverkostnader för driften. I inställningarna
under "Stöd Cleona" -> "Donera" kan du stödja utvecklingen frivilligt.

### "Mitt meddelande har bara en bock -- vad betyder det?"

Meddelandet är på väg, men din motpart har ännu inte bekräftat
mottagandet -- oftast för att hen just nu är offline. Det är inget fel:
Meddelandet väntar i upp till 7 dagar i brevlådan. Så fort hen hämtar det, ser du
två bockar. En klocka betyder att ingen väg ännu har burit meddelandet
-- det ger sig iväg av sig själv så fort det finns en; en varningsikon
att det inte har hittat någon väg på 14 dagar och att du kan skicka
det igen.

### "Varför kommer meddelanden sent på min iPhone?"

iOS låter inte appar köras permanent i bakgrunden. Cleona väcks bara kort då och
då; iOS avgör när. Den hämtar då allt. Så fort du öppnar appen hämtar Cleona det
som har sparats åt dig.

### "Kan jag byta från WhatsApp till Cleona?"

Ja, men du kan inte överföra dina WhatsApp-chattar. Cleona och WhatsApp
är helt olika system. Du måste lägga till dina kontakter en och en i Cleona.
Enklast går det om du skickar textraden i din inbjudan
till dina kontakter. Varje förfrågan som kommer på det sättet bekräftar du
själv under "Förfrågningar".

### "Kan jag använda Cleona på flera enheter samtidigt?"

Inte än. En andra enhet för samma identitet kommer i en senare version
(kapitel 11). På flera enheter kan du idag använda olika identiteter.

### "Hur får jag uppdateringar om App Store är spärrad?"

Cleona kan hämta uppdateringar direkt via nätverket, utan att vara
beroende av en App Store, en webbplats eller en nedladdningsserver. Om
en annan enhet i nätverket har den senaste versionen, kan din enhet hämta
uppdateringen därifrån. Äktheten verifieras genom en digital signatur av
utvecklaren. Alternativt kan en kontakt vidarebefordra appen till dig via
inbjudningslänk eller USB-minne. Mer om det i kapitlet
"Programuppdateringar".

---

## Hjälp och kontakt

Om du har frågor eller stöter på ett problem, hittar du aktuell
information på Cleonas webbplats och på GitHub. Eftersom Cleona är ett decentraliserat
projekt, finns ingen klassisk kundsupport -- men en aktiv
gemenskap som hjälper gärna.

---

*Denna handbok beskriver Cleona Chat version 4.2. Enskilda funktioner
kan ändras eller utökas i nyare versioner.*
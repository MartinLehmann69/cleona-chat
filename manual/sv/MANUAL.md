# Cleona Chat -- Användarhandbok

Version 3.1.125 | juli 2026

---

## Innehållsförteckning

1. [Vad är Cleona Chat?](#1-vad-ar-cleona-chat)
2. [Komma igång](#2-komma-igang)
3. [Kontakter](#3-kontakter)
4. [Meddelanden](#4-meddelanden)
5. [Grupper](#5-grupper)
6. [Offentliga kanaler](#6-offentliga-kanaler)
7. [Samtal](#7-samtal)
8. [Kalender](#8-kalender)
9. [Omröstningar](#9-omrostningar)
10. [Flera identiteter](#10-flera-identiteter)
11. [Multi-Device](#11-multi-device)
12. [Återställning](#12-aterstallning)
13. [Inställningar](#13-installningar)
14. [Säkerhet](#14-sakerhet)
15. [Programvaruuppdateringar](#15-programvaruuppdateringar)
16. [Vanliga frågor](#16-vanliga-fragor)

---

## 1. Vad är Cleona Chat?

### Din messenger, dina data

Cleona Chat är en meddelandetjänst som fungerar helt utan central server.
Dina meddelanden går direkt från din enhet till din motparts enhet -- utan
omväg via ett företags huvudkontor, utan moln, utan datacenter. Inget
företag kan läsa, lagra eller vidarebefordra dina meddelanden, eftersom det
helt enkelt inte finns något företag emellan.

### Inget konto, inget telefonnummer

Med Cleona behöver du varken telefonnummer eller e-postadress för att logga
in. Din identitet består av ett kryptografiskt nyckelpar som skapas
automatiskt på din enhet vid första starten. Det betyder: ingen kan hitta
dig via ditt telefonnummer eller din e-postadress, om du inte själv delar
dina kontaktuppgifter.

### Framtidssäker kryptering

Cleona använder så kallad post-kvantkryptering. Det betyder att inte ens
framtida kvantdatorer skulle kunna knäcka dina meddelanden. Du behöver inte
förstå detaljerna -- det viktiga är att din kommunikation skyddas så bra som
möjligt enligt dagens teknik.

### Hur fungerar det utan server?

Föreställ dig att du och dina kontakter tillsammans bildar ett nätverk.
Varje enhet hjälper till att vidarebefordra meddelanden. Är din motpart
online just nu går meddelandet direkt dit. Är din motpart offline lagrar
gemensamma kontakter meddelandet tillfälligt och levererar det så snart
mottagaren är tillbaka. Dina kontakter är alltså samtidigt ditt nätverk.

### Plattformar

Cleona finns tillgängligt för Android, iOS, macOS, Linux och Windows.

---

## 2. Komma igång

### Installera appen

**Android:**
1. Ladda ner APK-filen från Cleonas webbplats eller från GitHub Releases.
2. Öppna filen på din telefon. Tillåt vid behov installation från okända
   källor (Android frågar dig automatiskt).
3. Tryck på "Installera" och vänta tills installationen är klar.

**iOS:**
1. Öppna TestFlight-inbjudningslänken på din iPhone.
2. Tryck på "Installera". TestFlight är Apples officiella sätt att
   distribuera beta-appar.
3. Efter installationen hittar du Cleona på din hemskärm.

**macOS:**
1. Ladda ner DMG-filen från Cleonas webbplats eller från GitHub Releases.
2. Öppna DMG-filen och dra Cleona till din Program-mapp.
3. Vid första starten kan macOS fråga om du vill öppna appen från en
   identifierad utvecklare -- bekräfta detta.

**Linux (Ubuntu/Debian):**
1. Ladda ner .deb-filen från Cleonas webbplats eller från GitHub Releases.
2. Installera med dubbelklick eller i terminalen: `sudo dpkg -i cleona-chat_VERSION_amd64.deb`
3. Starta Cleona via programmenyn eller i terminalen med `cleona-chat`.

**Linux (Fedora/openSUSE):**
1. Ladda ner .rpm-filen från Cleonas webbplats eller från GitHub Releases.
2. Installera med: `sudo dnf install cleona-chat-VERSION.x86_64.rpm`
3. Starta Cleona via programmenyn eller i terminalen med `cleona-chat`.

**Linux (alla distributioner -- AppImage):**
1. Ladda ner .AppImage-filen från Cleonas webbplats eller från GitHub Releases.
2. Gör filen körbar: högerklick, Egenskaper, Körbar, eller i terminalen: `chmod +x cleona-chat-VERSION-x86_64.AppImage`
3. Starta med dubbelklick eller i terminalen: `./cleona-chat-VERSION-x86_64.AppImage`

**Windows:**
1. Ladda ner installationsprogrammet från Cleonas webbplats eller från
   GitHub Releases.
2. Kör installationsfilen och följ instruktionerna.
3. Starta Cleona via Startmenyn eller genvägen på skrivbordet.

### Skapa identitet

Vid första starten skapar Cleona automatiskt en ny identitet åt dig. Du kan
ge dig själv ett visningsnamn -- det är namnet som dina kontakter ser.
Namnet kan ändras när som helst.

### Skriv ner seed-phrasen -- det allra viktigaste

Efter att du skapat din identitet visar Cleona 24 ord. Det är din
**seed-phrase** -- din personliga återställningsnyckel.

**Skriv ner dessa 24 ord på papper och förvara dem säkert.**

Varför är detta så viktigt?

- Om din telefon går sönder, försvinner eller blir stulen kan du med dessa
  24 ord återställa hela din identitet på en ny enhet.
- Utan seed-phrasen finns det ingen väg tillbaka. Det finns ingen "glömt
  lösenord"-knapp och ingen support som kan ge dig tillbaka ditt konto --
  för det finns inget konto på någon server överhuvudtaget.
- Dela aldrig din seed-phrase med andra. Den som känner till dessa ord kan
  utge sig för att vara du.

Du hittar seed-phrasen senare även i inställningarna under "Säkerhet", om du
vill läsa den igen.

### Lägg till din första kontakt

För att chatta med någon måste du först lägga till personen som kontakt.
Det finns flera sätt att göra detta -- alla förklaras i nästa avsnitt.

---

## 3. Kontakter

### Skanna QR-kod (rekommenderas)

Det enklaste sättet att lägga till en kontakt:

1. Din motpart öppnar sin identitetsdetaljsida (tryck på sitt eget namn i
   det övre fältet) och visar dig sin QR-kod.
2. Du trycker på plus-knappen och väljer "Skanna QR-kod".
3. Håll din telefon framför din motparts QR-kod.
4. Kontaktförfrågan skickas automatiskt. Så snart din motpart accepterar
   den kan ni skriva till varandra.

Om ni träffas personligen är QR-koden den säkraste metoden, eftersom du då
vet exakt med vem du utbyter kontakten.

### NFC (håll telefonerna mot varandra)

Om båda enheterna stödjer NFC:

1. Öppna kontakt-läggtill-funktionen på båda enheterna.
2. Håll era telefoner rygg mot rygg mot varandra.
3. Kontaktuppgifterna utbyts automatiskt.

NFC erbjuder, precis som QR-koden, hög säkerhet eftersom utbytet bara
fungerar om ni fysiskt står bredvid varandra.

### Dela länk (cleona://-URI)

Du kan även skicka din kontaktlänk via e-post, SMS eller en annan
messenger:

1. Öppna din identitetsdetaljsida.
2. Kopiera din cleona://-länk.
3. Skicka länken till personen som ska lägga till dig.
4. Den andra personen öppnar länken, eller klistrar in den i dialogrutan
   för att lägga till kontakt.

Observera: med denna metod litar du på att länken inte har ändrats under
överföringen. För särskilt känsliga kontakter rekommenderar vi QR-kod eller
NFC.

### Acceptera kontaktförfrågningar

När någon skickar dig en kontaktförfrågan visas den i din inkorg (den
sista fliken i det nedre fältet). Där kan du:

- **Acceptera** -- personen läggs till bland dina kontakter.
- **Avvisa** -- förfrågan förkastas.
- **Blockera** -- personen kan inte skicka fler förfrågningar till dig.

### Verifieringsnivåer

Cleona visar hur säkert en kontakts identitet är bekräftad:

| Nivå | Betydelse |
|-------|-----------|
| Okänd | Du har bara fått Node-ID:t eller en länk. |
| Sedd | Nyckelutbytet lyckades, ni kan kommunicera krypterat. |
| Verifierad | Ni har träffats personligen och verifierat via QR-kod eller NFC. |
| Betrodd | Du har uttryckligen markerat denna kontakt som betrodd. |

Ju högre nivå, desto säkrare kan du vara på att du verkligen pratar med
rätt person.

---

## 4. Meddelanden

### Skicka och ta emot text

Skriv helt enkelt ditt meddelande i inmatningsfältet nedtill och tryck på
Enter eller skicka-knappen. Ditt meddelande krypteras automatiskt innan det
lämnar din enhet.

Inkommande meddelanden visas i chatthistoriken. En bock visar om ditt
meddelande har levererats.

### Skicka bilder, videor och filer

Du har flera möjligheter:

- **Gemikonen** i inmatningsfältet: tryck på den för att välja en fil, en
  bild eller en video från ditt galleri eller filsystem.
- **Dra och släpp** (dator): dra en fil direkt in i chattfönstret.
- **Klistra in från urklipp** (dator): kopiera en bild och klistra in den
  i chatten.

Små filer (under 256 KB) skickas med direkt. Större filer överförs i en
tvåstegsprocess: först aviseras filen, sedan överförs den i delar.

### Röstmeddelanden

1. Håll ner mikrofonknappen i inmatningsfältet.
2. Tala in ditt meddelande.
3. Släpp knappen för att skicka meddelandet.

Om taligenkänning är aktiverad på din enhet (se inställningar)
transkriberas ditt röstmeddelande automatiskt till text. Din motpart ser då
både inspelningen och den transkriberade texten.

### Svara på meddelanden (citera)

För att svara på ett specifikt meddelande:

1. Öppna menyn med tre punkter bredvid meddelandet.
2. Välj "Svara".
3. Ovanför inmatningsfältet visas en banner med det citerade meddelandet.
4. Skriv ditt svar och skicka det.

Det citerade meddelandet visas i ditt svar så att sambandet blir tydligt.

### Redigera och radera meddelanden

- **Redigera:** Menyn med tre punkter på meddelandet, sedan "Redigera".
  Ändra texten och skicka den igen. Din motpart ser att meddelandet har
  redigerats. Redigering är möjlig inom 15 minuter efter att meddelandet
  skickades.
- **Radera:** Menyn med tre punkter på meddelandet, sedan "Radera".
  Meddelandet tas bort hos både dig och din motpart. Du kan radera dina
  egna meddelanden när som helst -- det finns inget tidsfönster för
  radering.

### Emoji-reaktioner

Istället för att skriva ett svar kan du reagera på ett meddelande med en
emoji:

1. Öppna menyn med tre punkter eller håll meddelandet nedtryckt en stund.
2. Välj en emoji från snabbvalet eller öppna emoji-väljaren för hela
   urvalet.
3. Din reaktion visas under meddelandet.

### Kopiera text

Via menyn med tre punkter på ett meddelande kan du kopiera
meddelandetexten till urklipp.

### Sök meddelanden

Överst i chattfönstret hittar du sökfunktionen. Skriv in en sökterm så
visar Cleona alla träffar i den aktuella chatten. Med piltangenterna kan du
hoppa fram och tillbaka mellan träffarna.

På startsidan finns dessutom ett flik-övergripande sökfilter som du kan
använda för att söka igenom alla konversationer efter en term.

### Länkförhandsvisning

När du skickar en länk skapar Cleona automatiskt en förhandsvisning
(titel, beskrivning, förhandsgranskningsbild). Denna förhandsvisning
skapas av din enhet och skickas med -- din motpart behöver inte upprätta
någon anslutning till den länkade webbplatsen för detta.

Om du trycker på en mottagen länk blir du tillfrågad om du vill öppna den
i vanlig webbläsare, i inkognitoläge, eller inte alls.

---

## 5. Grupper

### Skapa grupp

1. Växla till fliken "Grupper".
2. Tryck på plus-knappen.
3. Ge gruppen ett namn.
4. Välj de kontakter du vill bjuda in.
5. Tryck på "Skapa".

De inbjudna kontakterna får en avisering och kan gå med i gruppen.

### Bjud in medlemmar

Även efter att gruppen skapats kan du bjuda in fler kontakter:

1. Öppna gruppinformationen (menyn med tre punkter i gruppöversikten eller
   det övre fältet i gruppchatten).
2. Tryck på "Bjud in".
3. Välj de kontakter du vill lägga till.

### Roller

Varje grupp har tre roller:

- **Ägare (Owner):** Har full kontroll. Kan lägga till och ta bort
  medlemmar, utse administratörer och hantera gruppen. Ägaren kan även
  överföra sin status till en annan medlem.
- **Administratör (Admin):** Kan ta bort medlemmar och hjälpa till med
  administrationen.
- **Medlem:** Kan läsa och skriva meddelanden.

### Lämna grupp

1. Öppna menyn med tre punkter i gruppöversikten.
2. Välj "Lämna".
3. Bekräfta ditt beslut.

Om du lämnar en grupp förblir dina tidigare meddelanden synliga för de
andra medlemmarna.

---

## 6. Offentliga kanaler

### Vad är kanaler?

Kanaler är offentliga diskussionsforum inom Cleona-nätverket. Till
skillnad från grupper kan vem som helst läsa med här utan att behöva bli
inbjuden. Endast ägaren och administratörerna kan publicera inlägg --
prenumeranter läser med.

### Hitta och gå med i kanaler

1. Växla till fliken "Kanaler".
2. Öppna fliken "Sök".
3. Sök bland tillgängliga kanaler efter namn eller ämne.
4. Tryck på en kanal och sedan på "Prenumerera".

Kanaler kan filtreras efter språk. Vissa kanaler är märkta som "Ej lämplig
för minderåriga" -- dessa syns bara om du i din profil har bekräftat att du
är över 18 år.

### Skapa egen kanal

1. Växla till fliken "Kanaler".
2. Tryck på plus-knappen.
3. Ange ett kanalnamn (måste vara unikt i hela nätverket).
4. Välj språk och om kanalen ska vara offentlig eller privat.
5. Valfritt: lägg till en beskrivning och en bild.
6. Tryck på "Skapa".

För offentliga kanaler kan du ange om innehållet ska klassas som "Ej
lämplig för minderåriga".

### Anmäla innehåll

Om du upptäcker olämpligt innehåll i en offentlig kanal kan du anmäla det.
Cleona använder ett decentraliserat moderationssystem: anmälningar bedöms
av slumpmässigt utvalda medlemmar av nätverket (en slags "jury"). Om ett
brott mot reglerna konstateras får kanalen en varning. Vid upprepade
överträdelser nedgraderas den i sökindexet eller spärras.

### Systemkanaler

Cleona har två inbyggda systemkanaler:

- **Bug Log:** När Cleona upptäcker ett fel frågar det dig om du vill
  skicka en anonymiserad felrapport. Dessa rapporter hamnar i Bug
  Log-kanalen, där de kan granskas av communityn. Inga personuppgifter
  överförs -- endast tekniska felbeskrivningar. Du kan även manuellt
  skicka en loggrapport (med förhandsgranskningsdialog och uttryckligt
  samtycke).
- **Feature Requests:** Här kan användare lämna in funktionsönskemål och
  rösta på befintliga förslag. Förslagen sorteras efter antal röster.

Båda systemkanalerna har en storleksgräns på 25 MB och övervakas av juryns
moderationssystem.

---

## 7. Samtal

### Starta röstsamtal

1. Öppna chatten med kontakten du vill ringa.
2. Tryck på telefonsymbolen i det övre fältet.
3. Vänta tills din motpart svarar på samtalet.

Under samtalet ser du en tidslinje som visar samtalslängden, och du har
tillgång till att stänga av mikrofonen och slå på högtalare.

Tryck på den röda lägg-på-knappen för att avsluta samtalet.

### Starta videosamtal

1. Öppna chatten med kontakten.
2. Tryck på kamerasymbolen i det övre fältet.
3. Din videobild visas i ett litet fönster, din motparts bild i det stora
   området.

Du kan växla mellan fram- och bakkamera under samtalet.

### Inkommande samtal

När någon ringer dig visas ett aviseringsfönster med den uppringandes
namn. Du kan:

- **Svara** -- samtalet börjar.
- **Avvisa** -- den som ringer aviseras.

Om du redan är i ett samtal avvisas ett nytt samtal automatiskt.

### Gruppsamtal

Du kan även genomföra gruppsamtal där flera personer deltar samtidigt.
Samtalet organiseras via ett intelligent vidarebefordringsträd, så att
inte alla deltagare behöver vara direkt anslutna till varandra. Alla
samtal är helt krypterade.

### Kryptering vid samtal

Alla samtal krypteras med engångsnycklar som endast existerar under
samtalets längd. Efter att samtalet avslutats raderas dessa nycklar
omedelbart. Ingen kan i efterhand dekryptera ett tidigare samtal.

---

## 8. Kalender

Cleona innehåller en inbyggd kalender som är krypterad och fungerar helt
decentraliserat -- utan molntjänst.

### Vyer

Kalendern erbjuder fem vyer: dag, vecka, månad, år och en uppgiftsvy.
Växla mellan dem via flikarna högst upp på kalenderskärmen.

### Skapa möten

Tryck på en tidslucka eller använd lägg till-knappen för att skapa ett
nytt möte. Du kan ange titel, datum, tid, plats och anteckningar. Möten
lagras krypterat på din enhet.

### Återkommande möten

Möten kan upprepas dagligen, veckovis, månadsvis eller årligen. Du kan
anpassa mönstret (t.ex. varannan tisdag, den första i varje månad) och
ange ett slutdatum eller antal upprepningar.

### Bjuda in kontakter

När du skapar eller redigerar ett möte kan du bjuda in dina
Cleona-kontakter. De får en krypterad kalenderinbjudan och kan svara med
Ja, Nej eller Kanske. Ändringar av mötet skickas automatiskt till alla
inbjudna.

### Ledig/upptagen-visning

Du kan dela din tillgänglighet med kontakter utan att avslöja
mötesdetaljer. Det finns tre sekretessnivåer: fullständiga detaljer,
endast tidsblock, eller dold. Du kan ange en standard och åsidosätta den
per kontakt.

### Påminnelser

Möten kan ha påminnelser som utlöser en systemavisering innan mötet
börjar. Du kan snooza påminnelser vid behov.

### Extern kalendersynkronisering

Cleona kan synkronisera med externa kalendertjänster:

- **CalDAV** -- anslut till vilken CalDAV-kompatibel server som helst
  (Nextcloud, Radicale osv.).
- **Google Kalender** -- synkronisering via Google Calendar API med säker
  OAuth2-autentisering.
- **Lokal CalDAV-server** -- Cleona kan starta en lokal CalDAV-server på
  din enhet, så att kalenderprogram på datorn (Thunderbird, Outlook, Apple
  Kalender, Evolution) kan synkronisera med din Cleona-kalender.
- **Androids systemkalender** -- möten från Cleona kan överföras till den
  inbyggda kalenderappen på din Android-enhet.
- **ICS-filer** -- importera och exportera möten i standardformatet
  iCalendar.

### PDF-export

Du kan skriva ut eller exportera valfri kalendervy (dag, vecka, månad, år)
som ett PDF-dokument.

---

## 9. Omröstningar

Du kan skapa omröstningar i vilken chatt eller grupp som helst för att
samla in åsikter eller planera möten.

### Omröstningstyper

Cleona stödjer fem typer av omröstningar:

- **Enkelval** -- deltagarna väljer ett alternativ.
- **Flerval** -- deltagarna kan välja flera alternativ.
- **Datumomröstning** -- hitta ett datum som passar alla. Varje deltagare
  markerar datum som tillgängliga, kanske, eller inte tillgängliga.
- **Skala** -- betygsätt något på en numerisk skala (t.ex. 1 till 5).
- **Fritext** -- deltagarna skriver sitt eget svar.

### Skapa omröstning

Öppna en chatt och tryck på omröstningssymbolen (eller använd
bilagemenyn). Välj omröstningstyp, formulera din fråga och alternativen,
och skicka omröstningen. Den visas som ett meddelande i chatten.

### Rösta

Tryck på en omröstning för att avge din röst. Du kan ändra eller dra
tillbaka din röst när som helst.

### Anonym omröstning

Omröstningar kan konfigureras för anonym röstning. Om aktiverat är
rösterna kryptografiskt anonyma -- ingen, inte ens den som skapade
omröstningen, kan se vem som röstat på vad. Antalet röster förblir ändå
synligt.

### Datumomröstning till kalender

När en datumomröstning är avslutad kan det vinnande datumet med ett tryck
omvandlas direkt till en kalenderpost.

---

## 10. Flera identiteter

### Varför flera identiteter?

Föreställ dig att du vill separera ditt yrkesliv från ditt privatliv --
ungefär som med två olika telefonnummer, men utan en andra telefon. I
Cleona kan du använda flera identiteter på en enhet. Varje identitet har
ett eget namn, en egen profilbild, egna kontakter och egna konversationer.

### Skapa ny identitet

1. I det övre fältet ser du din aktuella identitet som en flik.
2. Tryck på plustecknet (+) till höger om dina identitetsflikar.
3. Ange ett namn för den nya identiteten.
4. Klart -- den nya identiteten är omedelbart aktiv.

### Växla mellan identiteter

Tryck helt enkelt på identitetsfliken i det övre fältet. Växlingen sker
omedelbart -- ingen väntetid, ingen omladdning.

### Alla körs samtidigt

En viktig poäng: alla dina identiteter är aktiva samtidigt. Även om du för
tillfället visas som "Jobb" fortsätter din "Privat"-identitet att ta emot
meddelanden. Du missar ingenting, oavsett vilken identitet du för
tillfället har valt.

### Identitetsdetaljsida

När du trycker på fliken för din just nu aktiva identitet öppnas
detaljsidan. Här kan du:

- Visa din QR-kod för kontakter.
- Ändra eller ta bort din profilbild.
- Lägga till en profilbeskrivning.
- Ändra ditt visningsnamn.
- Välja ett tema (skin) för denna identitet.
- Radera identiteten, om du inte längre behöver den.

### Radera identitet

Om du raderar en identitet meddelas dina kontakter om detta. Identiteten
och all tillhörande data tas bort från din enhet. Denna åtgärd kan inte
ångras.

---

## 11. Multi-Device

### Använda Cleona på flera enheter

Du kan använda samma identitet på upp till 5 enheter samtidigt. En enhet
är den primära (den håller seed-phrasen), och ytterligare enheter länkas
till den.

### Länka ny enhet

1. Öppna inställningarna på din primära enhet.
2. Gå till "Länkade enheter".
3. Välj "Länka ny enhet".
4. Installera Cleona på den nya enheten och välj vid start "Länka med
   befintlig enhet".
5. Skanna QR-koden för parkoppling som visas på din primära enhet, eller
   använd parkopplingslänken.

Den länkade enheten får ett delegeringscertifikat från den primära
enheten. Meddelanden som skickas från en länkad enhet signeras
kryptografiskt med en delegerad nyckel, så att kontakter kan verifiera att
meddelandet verkligen kommer från din identitet.

### Så fungerar det

- Den primära enheten håller din seed-phrase och huvudnycklarna.
- Länkade enheter får härledda signeringsnycklar och ett
  delegeringscertifikat -- de får aldrig själva seed-phrasen.
- Alla enheter delar samma identitet och kontakter. Meddelanden anländer
  på alla enheter.
- Delegeringscertifikat förnyas automatiskt innan de går ut.

### Enhetshantering

Öppna inställningarna och gå till "Länkade enheter" för att se alla dina
länkade enheter, deras status och senaste aktivitet. Du kan när som helst
återkalla en länkad enhet, om den går förlorad eller blir stulen.

### Nödrotation av nycklar

Om du misstänker att en enhet har komprometterats kan du utlösa en
nödrotation av nycklar. Nya nycklar genereras då, och rotationen måste
bekräftas av en majoritet av dina andra enheter. Det förhindrar att en
enda stulen enhet på egen hand kan rotera nycklar.

---

## 12. Återställning

### Använda seed-phrasen

Om du förlorar din enhet eller sätter upp en ny:

1. Installera Cleona på den nya enheten.
2. Välj "Återställ" vid start.
3. Ange dina 24 ord.
4. Cleona återställer din identitet och kontaktar automatiskt dina
   tidigare kontakter.
5. Dina kontakter svarar med dina kontaktuppgifter, gruppmedlemskap och
   meddelandehistorik.

Återställningen sker i tre steg:
- Först kommer dina kontakter och grupper tillbaka.
- Sedan de senaste 50 meddelandena från varje konversation.
- Till sist den fullständiga meddelandehistoriken.

Det räcker att en enda av dina kontakter är online för att återställningen
ska fungera.

### Guardian Recovery (betrodda personer)

Du kan utse upp till fem betrodda personer som "guardians". Din
återställningsnyckel delas då upp i fem delar, varav varje guardian får
en. För att återställa din identitet räcker det med tre av de fem delarna.

Det betyder: även om du har förlorat din seed-phrase kan tre av dina
guardians tillsammans återställa ditt konto. Ingen enskild guardian kan på
egen hand komma åt dina data -- det behövs alltid minst tre.

Så här ställer du in guardians:
1. Öppna inställningarna.
2. Gå till "Säkerhet".
3. Välj "Guardian Recovery".
4. Välj fem betrodda kontakter.

### Varför kontakter är din backup

I traditionella messengers ligger dina data på leverantörens servrar. Hos
Cleona finns ingen server -- men dina kontakter tar över den rollen. När
du skickar ett meddelande lagrar gemensamma kontakter en krypterad kopia
för det fall att mottagaren just då är offline. Vid en återställning
levererar dina kontakter tillbaka dina data till dig.

Det betyder: ju fler aktiva kontakter du har, desto pålitligare är din
backup. En kontakt som regelbundet är online räcker för en lyckad
återställning.

---

## 13. Inställningar

Du når inställningarna via kugghjulssymbolen i övre högra hörnet.

### Aviseringar och ringsignaler

- Välj bland sex olika ringsignaler för inkommande samtal.
- Ställ in en meddelandeton.
- På Android-enheter kan du dessutom aktivera eller inaktivera vibration.

### Teman (Skins)

Cleona erbjuder tio olika teman: Teal, Ocean, Sunset, Forest, Amethyst,
Fire, Storm, Slate, Gold och Contrast. Contrast-temat uppfyller den
högsta tillgänglighetsnivån (WCAG AAA) och är särskilt lättläst vid
nedsatt syn.

Varje identitet kan ha sitt eget tema. Du ändrar temat på
identitetsdetaljsidan (tryck på den aktiva identitetsfliken).

Dessutom kan du i inställningarna under "Utseende" växla mellan ljust,
mörkt och systemtema.

### Ändra språk

Cleona finns tillgängligt på 33 språk, inklusive språk med skrift från
höger till vänster (t.ex. arabiska, hebreiska). Ändra språk i
inställningarna under "Språk".

### Lagringsgräns

Du kan ange hur mycket lagringsutrymme Cleona får använda på din enhet
(mellan 100 MB och 2 GB). När gränsen nås flyttas äldre media automatiskt
ut eller raderas -- textmeddelanden bevaras alltid.

### Mediearkivering

Om du har en nätverksenhet (NAS) eller en delad mapp hemma kan Cleona
automatiskt flytta ut dina media dit. SMB, SFTP, FTPS och WebDAV stöds.

Så fungerar den stegvisa lagringen:
- De första 30 dagarna: allt förblir på din enhet.
- Efter 30 dagar: en förhandsgranskningsbild förblir på enheten, originalet
  arkiveras.
- Efter 90 dagar: endast en liten förhandsgranskningsbild förblir på
  enheten.
- Efter ett år: endast en platshållare förblir, originalet ligger säkert i
  arkivet.

Du kan när som helst trycka på ett arkiverat media för att hämta tillbaka
det -- förutsatt att du är ansluten till ditt hemnätverk. Särskilt viktiga
media kan fästas så att de aldrig flyttas ut.

### Transkription för röstmeddelanden

Om aktiverat omvandlas dina röstmeddelanden lokalt på din enhet till text
(med den öppen källkods-modellen Whisper). Den transkriberade texten
skickas tillsammans med inspelningen till din motpart. Transkriptionen
sker helt på din enhet -- ingen data skickas till externa tjänster.

### Auto-nedladdning

Du kan ställa in från vilken storlek media ska laddas ner automatiskt. På
så sätt kan du till exempel låta bilder laddas ner automatiskt, men
bestämma manuellt vid stora videor.

### Länkade enheter

Hantera dina länkade enheter i detta avsnitt av inställningarna. Se
kapitlet om Multi-Device för detaljer.

---

## 14. Säkerhet

### Vad betyder post-kvantkryptering?

Dagens kryptering bygger på matematiska problem som är extremt svåra för
vanliga datorer att lösa. Kvantdatorer skulle i framtiden kunna lösa några
av dessa problem snabbt. Post-kvantkryptering använder ytterligare metoder
som även står emot kvantdatorer.

Cleona kombinerar båda tillvägagångssätten: klassisk kryptering för
tillförlitlighet och post-kvantmetoder för framtidssäkerhet. På så sätt är
du skyddad mot både dagens och framtidens hot samtidigt.

För varje enskilt meddelande skapas en egen nyckel. Även om en angripare
skulle knäcka nyckeln för ett meddelande kunde denne inte läsa något annat
meddelande med den.

### Varför ingen server är säkrare

I traditionella messengers går dina meddelanden via leverantörens
servrar. Även om de må vara krypterade där har leverantören tillgång till
metadata (vem kommunicerar när med vem, hur ofta, varifrån) och måste
under vissa omständigheter lämna ut dessa på domstolsbeslut.

Hos Cleona finns ingen sådan central punkt. Dina meddelanden reser direkt
från enhet till enhet. Det finns ingen plats där all metadata samlas.
Ingen kan utifrån en enda datapunkt rekonstruera ditt kommunikationsmönster.

### Vad händer om du är offline?

När du skickar ett meddelande och mottagaren är offline:

1. Cleona försöker först leverera meddelandet direkt.
2. Om det inte fungerar vidarebefordras det via gemensamma kontakter.
3. Samtidigt fördelas meddelandet som krypterade bitar över flera noder i
   nätverket (ungefär som ett pussel med 10 bitar, av vilka 7 räcker för
   att sätta ihop bilden).
4. Meddelandet sparas i upp till 7 dagar.

Så snart mottagaren kommer online igen levereras meddelandena. Du får en
bekräftelse när ditt meddelande har anlänt.

### Anti-censur

Om ditt nätverk blockerar standardanslutningsmetoden (UDP) växlar Cleona
automatiskt till en alternativ överföring (TLS) som är svårare att
upptäcka och blockera. Detta sker transparent -- du behöver inte
konfigurera något.

### Säker nyckellagring

På plattformar som stödjer det lagrar Cleona dina krypteringsnycklar i
operativsystemets säkra nyckelring (Android Keystore, iOS Keychain, macOS
Keychain). Där det är tillgängligt ger detta hårdvarustött skydd för dina
nycklar.

### Databaskryptering

Alla dina meddelanden, kontakter och inställningar lagras krypterade på
din enhet. Även om någon skulle få tillgång till ditt filsystem kunde de
inte läsa något utan din kryptografiska nyckel. Denna nyckel härleds från
din identitet och existerar bara på din enhet.

### Slutet nätverk

Cleona fungerar som ett slutet nätverk. Varje nätverkspaket är
autentiserat, så att endast legitima Cleona-enheter kan delta. Det
förhindrar att utomstående kan smyga in förfalskade meddelanden eller
avlyssna nätverkstrafiken.

---

## 15. Programvaruuppdateringar

### Hur får jag uppdateringar?

Cleona kan uppdateras på flera olika sätt. Målet är att du ska kunna få
uppdateringar även om enskilda distributionsvägar slutar fungera eller
blockeras:

1. **App Store / Play Store:** Om du har installerat Cleona via en app
   store får du uppdateringar som vanligt via butiken.
2. **GitHub Releases:** På projektets GitHub-sida hittar du signerade
   installationspaket för alla plattformar.
3. **Uppdateringar inom nätverket (In-Network-Updates):** Om en annan
   Cleona-användare i ditt nätverk redan har den senaste versionen kan
   Cleona hämta uppdateringen direkt via P2P-nätverket -- utan extern
   server. Den nya versionen delas då upp i felkorrigerade fragment och
   fördelas över flera noder. Din enhet samlar tillräckligt med fragment
   och sätter ihop uppdateringen. Äktheten kontrolleras genom
   utvecklarens Ed25519-signatur.
4. **Inbjudningslänkar:** Du kan skapa inbjudningslänkar som innehåller
   allt en ny användare behöver för att installera Cleona och ansluta
   till nätverket.
5. **Fysisk överföring:** I miljöer utan internet kan du vidarebefordra
   Cleona till andra via ett USB-minne eller i det lokala nätverket.

### Uppdateringsavisering

När en ny uppdatering är tillgänglig visar Cleona en avisering på
startskärmen. Om uppdateringen även är tillgänglig via nätverket
(In-Network-Update) kan du välja att ladda ner den direkt från nätverket.

### Binärdistribution

Som standard hjälper din enhet till att vidarebefordra uppdateringar till
andra användare i nätverket. Om du inte vill det kan du inaktivera denna
funktion i inställningarna under "Nätverk". Lagringsutrymmet för
uppdateringsfragment är begränsat (5 MB på mobila enheter, 20 MB på
datorer) och rensas regelbundet.

### Signaturkontroll

Varje uppdatering signeras kryptografiskt. Cleona kontrollerar signaturen
automatiskt innan en uppdatering installeras. På så sätt säkerställs att
endast uppdateringar från den officiella utvecklaren accepteras -- även om
uppdateringen hämtades via P2P-nätverket.

---

## 16. Vanliga frågor

### "Kan jag använda Cleona utan internet?"

Nej, Cleona behöver en nätverksanslutning för att skicka och ta emot
meddelanden. Du behöver dock inte vara online samtidigt som din motpart:
meddelanden som skickas medan mottagaren är offline sparas tillfälligt och
levereras automatiskt så snart båda sidor är anslutna igen. I ett lokalt
nätverk (t.ex. samma Wi-Fi) kan ni kommunicera med varandra helt utan
internetuppkoppling.

### "Vad händer om jag förlorar min seed-phrase?"

Om du har ställt in guardians kan tre av fem betrodda personer tillsammans
återställa din åtkomst. Utan guardians och utan seed-phrase finns tyvärr
ingen väg att få tillbaka din identitet. Därför är det så viktigt att
förvara de 24 orden säkert.

### "Kan någon läsa mina meddelanden?"

Nej. Varje meddelande krypteras med en engångsnyckel som endast gäller för
just det meddelandet. Bara du och din motpart kan dekryptera meddelandet.
Det finns ingen central server, ingen huvudnyckel och ingen åtkomst för
utvecklaren. Även om en enhet vidarebefordrar meddelandet på vägen ser den
bara krypterad datagröt.

### "Varför behöver jag inget telefonnummer?"

Eftersom din identitet är rent kryptografisk. Istället för ett
telefonnummer eller en e-postadress som är kopplad till ditt riktiga namn
identifieras du av ett nyckelpar som skapats på din enhet. Du lägger till
kontakter via QR-kod, NFC eller länk -- inte via en telefonbok. Det
innebär mer integritet, eftersom ditt messenger-konto inte är bundet till
din verkliga identitet.

### "Hur hittar jag folk på Cleona?"

Cleona har medvetet ingen kontaktsökning via telefonnummer eller namn --
det skulle vara ett integritetsproblem. Istället utbyter du
kontaktuppgifter direkt: via QR-kod, NFC, cleona://-länk eller i
offentliga kanaler. Det är som att byta visitkort istället för att slå
upp i telefonboken.

### "Fungerar Cleona även utomlands?"

Ja. Så länge du har en internetanslutning fungerar Cleona överallt i
världen. Eftersom det inte finns någon central server kan tjänsten inte
heller spärras för vissa länder. Cleona har dessutom en anti-censur-
fallback: om den normala anslutningen (UDP) blockeras växlar Cleona
automatiskt till en alternativ överföring (TLS) som är svårare att
upptäcka och blockera.

### "Är Cleona gratis?"

Ja. Cleona kan användas gratis och utan reklam. Eftersom det inte finns
någon central server uppstår heller inga serverkostnader för driften. I
appen hittar du under "Donera" möjligheten att frivilligt stödja
utvecklingen.

### "Mitt meddelande har en klocksymbol -- vad betyder det?"

Det betyder att meddelandet ännu inte har levererats. Din motpart är
förmodligen offline just nu. Så snart meddelandet har levererats ändras
symbolen. Meddelanden sparas i upp till 7 dagar för leverans.

### "Kan jag byta från WhatsApp till Cleona?"

Ja, men du kan inte överföra dina WhatsApp-chattar. Cleona och WhatsApp är
helt olika system. Du måste lägga till dina kontakter en och en i Cleona.
Det enklaste sättet är att posta din cleona://-länk i en WhatsApp-grupp
och be de andra att lägga till dig där.

### "Kan jag använda Cleona på flera enheter samtidigt?"

Ja. Du kan länka upp till 5 enheter med samma identitet. En enhet är den
primära (den håller seed-phrasen), och ytterligare enheter länkas via en
säker parkopplingsprocess. Alla enheter delar samma identitet, kontakter
och konversationer. Se kapitlet om Multi-Device för detaljer.

### "Hur får jag uppdateringar om App Store är blockerad?"

Cleona kan hämta uppdateringar direkt via P2P-nätverket, utan att vara
beroende av en app store, en webbplats eller en nedladdningsserver. Om en
annan användare i nätverket har den senaste versionen kan din enhet ladda
uppdateringen därifrån. Äktheten kontrolleras genom utvecklarens digitala
signatur. Alternativt kan en kontakt vidarebefordra appen till dig via
inbjudningslänk eller USB-minne. Mer om detta i kapitlet
"Programvaruuppdateringar".

---

## Hjälp och kontakt

Om du har frågor eller stöter på ett problem hittar du aktuell information
på Cleonas webbplats och på GitHub. Eftersom Cleona är ett decentraliserat
projekt finns ingen traditionell kundsupport -- men en aktiv gemenskap som
gärna hjälper till.

---

*Denna handbok beskriver Cleona Chat version 3.1.125. Enskilda funktioner
kan ändras eller utökas i nyare versioner.*

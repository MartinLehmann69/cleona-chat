# Cleona Chat -- Používateľská príručka

Verzia 3.1.125 | Júl 2026

---

## Obsah

1. [Čo je Cleona Chat?](#1-co-je-cleona-chat)
2. [Prvé kroky](#2-prve-kroky)
3. [Kontakty](#3-kontakty)
4. [Správy](#4-spravy)
5. [Skupiny](#5-skupiny)
6. [Verejné kanály](#6-verejne-kanaly)
7. [Hovory](#7-hovory)
8. [Kalendár](#8-kalendar)
9. [Ankety](#9-ankety)
10. [Viacero identít](#10-viacero-identit)
11. [Multi-Device](#11-multi-device)
12. [Obnovenie](#12-obnovenie)
13. [Nastavenia](#13-nastavenia)
14. [Bezpečnosť](#14-bezpecnost)
15. [Softvérové aktualizácie](#15-softverove-aktualizacie)
16. [Časté otázky](#16-caste-otazky)

---

## 1. Čo je Cleona Chat?

### Tvoj messenger, tvoje dáta

Cleona Chat je messenger, ktorý funguje úplne bez centrálneho servera.
Tvoje správy putujú priamo z tvojho zariadenia na zariadenie tvojho partnera
v komunikácii -- bez okľuky cez sídlo firmy, bez cloudu, bez dátového
centra. Žiadna spoločnosť nemôže tvoje správy čítať, ukladať ani odovzdávať
ďalej, pretože jednoducho žiadna spoločnosť nestojí uprostred.

### Žiadny účet, žiadne telefónne číslo

Pri Cleone nepotrebuješ na prihlásenie ani telefónne číslo, ani e-mailovú
adresu. Tvoja identita pozostáva z kryptografického páru kľúčov, ktorý sa
pri prvom spustení automaticky vygeneruje na tvojom zariadení. To znamená:
nikto ťa nemôže vypátrať cez tvoje telefónne číslo alebo e-mailovú adresu,
pokiaľ svoje kontaktné údaje sám neposkytneš.

### Šifrovanie odolné voči budúcnosti

Cleona využíva takzvané postkvantové šifrovanie. To znamená: ani budúce
kvantové počítače by nedokázali tvoje správy prelomiť. Detailom nemusíš
rozumieť -- dôležité je len to, že tvoja komunikácia je podľa aktuálneho
stavu techniky chránená čo najlepšie.

### Ako to funguje bez servera?

Predstav si, že ty a tvoje kontakty spolu tvoríte sieť. Každé zariadenie
pomáha preposielať správy ďalej. Ak je tvoj partner v komunikácii práve
online, správa ide priamo k nemu. Ak je offline, spoločné kontakty správu
dočasne uložia a doručia ju, akonáhle sa príjemca opäť pripojí. Tvoje
kontakty sú teda zároveň aj tvoja sieť.

### Platformy

Cleona je dostupná pre Android, iOS, macOS, Linux a Windows.

---

## 2. Prvé kroky

### Inštalácia aplikácie

**Android:**
1. Stiahni si súbor APK z webu Cleona alebo z GitHub Releases.
2. Otvor súbor vo svojom telefóne. Ak je to potrebné, povoľ inštaláciu
   z neznámych zdrojov (Android sa ťa na to automaticky opýta).
3. Ťukni na „Inštalovať" a počkaj, kým sa inštalácia dokončí.

**iOS:**
1. Otvor pozývací odkaz TestFlight na svojom iPhone.
2. Ťukni na „Inštalovať". TestFlight je oficiálny spôsob Apple na
   distribúciu beta aplikácií.
3. Po inštalácii nájdeš Cleonu na ploche svojho telefónu.

**macOS:**
1. Stiahni si súbor DMG z webu Cleona alebo z GitHub Releases.
2. Otvor DMG a presuň Cleonu do priečinka Aplikácie.
3. Pri prvom spustení sa ťa macOS možno opýta, či chceš otvoriť aplikáciu
   od identifikovaného vývojára -- potvrď to.

**Linux (Ubuntu/Debian):**
1. Stiahni si súbor .deb z webu Cleona alebo z GitHub Releases.
2. Nainštaluj dvojklikom alebo v termináli: `sudo dpkg -i cleona-chat_VERSION_amd64.deb`
3. Spusti Cleonu cez ponuku aplikácií alebo v termináli príkazom `cleona-chat`.

**Linux (Fedora/openSUSE):**
1. Stiahni si súbor .rpm z webu Cleona alebo z GitHub Releases.
2. Nainštaluj pomocou: `sudo dnf install cleona-chat-VERSION.x86_64.rpm`
3. Spusti Cleonu cez ponuku aplikácií alebo v termináli príkazom `cleona-chat`.

**Linux (všetky distribúcie -- AppImage):**
1. Stiahni si súbor .AppImage z webu Cleona alebo z GitHub Releases.
2. Nastav súbor ako spustiteľný: pravý klik, Vlastnosti, Spustiteľný, alebo v termináli: `chmod +x cleona-chat-VERSION-x86_64.AppImage`
3. Spusti dvojklikom alebo v termináli: `./cleona-chat-VERSION-x86_64.AppImage`

**Windows:**
1. Stiahni si inštalátor z webu Cleona alebo z GitHub Releases.
2. Spusti inštalačný súbor a postupuj podľa pokynov.
3. Spusti Cleonu cez ponuku Štart alebo odkaz na pracovnej ploche.

### Vytvorenie identity

Pri prvom spustení Cleona pre teba automaticky vytvorí novú identitu.
Môžeš si zvoliť zobrazované meno -- je to meno, ktoré vidia tvoje kontakty.
Toto meno môžeš kedykoľvek zmeniť.

### Zapíš si Seed-Phrase -- najdôležitejšia vec zo všetkých

Po vytvorení tvojej identity ti Cleona zobrazí 24 slov. To je tvoja
**Seed-Phrase** -- tvoj osobný obnovovací kľúč.

**Napíš si týchto 24 slov na papier a bezpečne ich uschovaj.**

Prečo je to také dôležité?

- Ak sa ti telefón pokazí, stratí sa alebo je ukradnutý, môžeš pomocou
  týchto 24 slov obnoviť celú svoju identitu na novom zariadení.
- Bez Seed-Phrase neexistuje cesta späť. Neexistuje tlačidlo „Zabudnuté
  heslo" ani podpora, ktorá by ti mohla vrátiť tvoj účet -- pretože na
  serveri žiadny účet vôbec neexistuje.
- Seed-Phrase nikdy nikomu neodovzdávaj. Kto pozná tieto slová, môže sa
  vydávať za teba.

Seed-Phrase neskôr nájdeš aj v Nastaveniach v časti „Bezpečnosť", ak by si
si ju chcel ešte raz pozrieť.

### Pridanie prvého kontaktu

Aby si mohol s niekým chatovať, musíš danú osobu najprv pridať ako
kontakt. Existuje na to viacero spôsobov -- všetky sú vysvetlené v
nasledujúcej kapitole.

---

## 3. Kontakty

### Skenovanie QR-Code (odporúčané)

Najjednoduchší spôsob, ako pridať kontakt:

1. Tvoj partner v komunikácii otvorí svoju detailnú stránku identity
   (ťuknutím na svoje meno v hornej lište) a ukáže ti svoj QR-Code.
2. Ty ťukneš na tlačidlo plus a zvolíš „Skenovať QR-Code".
3. Nasmeruj svoj telefón na QR-Code svojho partnera v komunikácii.
4. Žiadosť o kontakt sa odošle automaticky. Akonáhle ju tvoj partner v
   komunikácii prijme, môžete si spolu písať.

Ak sa stretnete osobne, QR-Code je najbezpečnejšia metóda, pretože presne
vieš, s kým si vymieňaš kontakt.

### NFC (priloženie telefónov k sebe)

Ak obe zariadenia podporujú NFC:

1. Obaja otvorte funkciu pridania kontaktu.
2. Priložte si telefóny zadnými stranami k sebe.
3. Kontaktné údaje sa automaticky vymenia.

NFC ponúka podobne ako QR-Code vysokú úroveň bezpečnosti, pretože výmena
funguje len vtedy, keď stojíte fyzicky vedľa seba.

### Zdieľanie odkazu (cleona://-URI)

Svoj kontaktný odkaz môžeš poslať aj e-mailom, SMS správou alebo cez iný
messenger:

1. Otvor svoju detailnú stránku identity.
2. Skopíruj svoj odkaz cleona://.
3. Odošli odkaz osobe, ktorá ťa má pridať.
4. Druhá osoba odkaz otvorí, alebo ho vloží do dialógového okna pridania
   kontaktu.

Pozor: pri tejto metóde sa spoliehaš na to, že odkaz nebol počas prenosu
zmenený. Pre obzvlášť citlivé kontakty odporúčame QR-Code alebo NFC.

### Prijímanie žiadostí o kontakt

Ak ti niekto pošle žiadosť o kontakt, zobrazí sa v tvojej schránke
(posledná karta v dolnej lište). Tam môžeš:

- **Prijať** -- daná osoba sa pridá do tvojich kontaktov.
- **Odmietnuť** -- žiadosť sa zamietne.
- **Blokovať** -- daná osoba ti už nemôže posielať ďalšie žiadosti.

### Úrovne overenia

Cleona ti ukazuje, ako spoľahlivo je potvrdená identita kontaktu:

| Úroveň | Význam |
|--------|--------|
| Neznáme | Dostal si len Node-ID alebo odkaz. |
| Videné | Výmena kľúčov prebehla úspešne, môžete komunikovať šifrovane. |
| Overené | Stretli ste sa osobne a overili ste sa cez QR-Code alebo NFC. |
| Dôveryhodné | Tento kontakt si explicitne označil ako dôveryhodný. |

Čím vyššia úroveň, tým väčšiu istotu máš, že skutočne komunikuješ so
správnou osobou.

---

## 4. Správy

### Odosielanie a prijímanie textu

Jednoducho napíš svoju správu do vstupného poľa dole a stlač Enter alebo
tlačidlo odoslať. Tvoja správa sa automaticky zašifruje skôr, než opustí
tvoje zariadenie.

Prichádzajúce správy sa zobrazujú v histórii chatu. Fajočka ti ukáže, či
bola tvoja správa doručená.

### Odosielanie obrázkov, videí a súborov

Máš viacero možností:

- **Ikona kancelárskej spinky** vo vstupnom poli: Ťukni na ňu a vyber
  súbor, obrázok alebo video zo svojej galérie alebo súborového systému.
- **Drag and Drop** (Desktop): Jednoducho pretiahni súbor do okna chatu.
- **Vloženie zo schránky** (Desktop): Skopíruj obrázok a vlož ho do chatu.

Malé súbory (pod 256 KB) sa odošlú priamo. Väčšie súbory sa prenášajú
dvojstupňovým postupom: najprv sa súbor ohlási, potom sa prenesie po
častiach.

### Hlasové správy

1. Podrž stlačené tlačidlo mikrofónu vo vstupnom poli.
2. Nahovor svoju správu.
3. Uvoľnením tlačidla správu odošleš.

Ak máš na svojom zariadení aktivované rozpoznávanie reči (pozri
Nastavenia), tvoja hlasová správa sa automaticky prepíše do textu. Tvoj
partner v komunikácii potom vidí ako nahrávku, tak aj prepísaný text.

### Odpovedanie na správy (citovanie)

Ak chceš odpovedať na konkrétnu správu:

1. Otvor menu s tromi bodkami vedľa správy.
2. Zvoľ „Odpovedať".
3. Nad vstupným poľom sa zobrazí panel s citovanou správou.
4. Napíš svoju odpoveď a odošli ju.

Citovaná správa sa zobrazí v tvojej odpovedi, takže súvislosť je jasná.

### Úprava a mazanie správ

- **Úprava:** Menu s tromi bodkami pri správe, potom „Upraviť". Zmeň text
  a znova ho odošli. Tvoj partner v komunikácii vidí, že správa bola
  upravená. Úprava je možná do 15 minút od odoslania.
- **Mazanie:** Menu s tromi bodkami pri správe, potom „Vymazať". Správa
  sa odstráni u teba aj u tvojho partnera v komunikácii. Svoje vlastné
  správy môžeš vymazať kedykoľvek -- pre mazanie neexistuje časové
  obmedzenie.

### Emoji reakcie

Namiesto písania odpovede môžeš na správu zareagovať pomocou emoji:

1. Otvor menu s tromi bodkami alebo podrž správu dlho stlačenú.
2. Vyber emoji z rýchleho výberu, alebo otvor výber emoji pre plnú
   ponuku.
3. Tvoja reakcia sa zobrazí pod správou.

### Kopírovanie textu

Cez menu s tromi bodkami pri správe môžeš skopírovať text správy do
schránky.

### Vyhľadávanie správ

V hornej časti okna chatu nájdeš vyhľadávaciu funkciu. Zadaj hľadaný
výraz a Cleona ti zobrazí všetky výsledky v aktuálnom chate. Pomocou
šípok môžeš medzi výsledkami prechádzať.

Na úvodnej obrazovke je navyše filter vyhľadávania naprieč kartami,
ktorým môžeš prehľadať všetky konverzácie podľa výrazu.

### Náhľad odkazu

Keď odošleš odkaz, Cleona automaticky vytvorí náhľad (názov, popis,
náhľadový obrázok). Tento náhľad vytvorí tvoje zariadenie a odošle ho
spolu so správou -- tvoj partner v komunikácii kvôli tomu nemusí
nadviazať spojenie s odkazovanou webovou stránkou.

Keď ťukneš na prijatý odkaz, opýta sa ťa, či ho chceš otvoriť v bežnom
prehliadači, v anonymnom režime, alebo vôbec neotvoriť.

---

## 5. Skupiny

### Vytvorenie skupiny

1. Prepni sa na kartu „Skupiny".
2. Ťukni na tlačidlo plus.
3. Zadaj skupine názov.
4. Vyber kontakty, ktoré chceš pozvať.
5. Ťukni na „Vytvoriť".

Pozvané kontakty dostanú upozornenie a môžu sa pripojiť do skupiny.

### Pozývanie členov

Aj po vytvorení skupiny môžeš pozvať ďalšie kontakty:

1. Otvor informácie o skupine (menu s tromi bodkami v prehľade skupín
   alebo horná lišta v skupinovom chate).
2. Ťukni na „Pozvať".
3. Vyber kontakty, ktoré chceš pridať.

### Role

Každá skupina má tri role:

- **Vlastník (Owner):** Má úplnú kontrolu. Môže pridávať a odstraňovať
  členov, menovať administrátorov a spravovať skupinu. Vlastník môže
  svoj status preniesť aj na iného člena.
- **Administrátor:** Môže odstraňovať členov a pomáhať pri správe.
- **Člen:** Môže čítať a písať správy.

### Opustenie skupiny

1. Otvor menu s tromi bodkami v prehľade skupín.
2. Zvoľ „Opustiť".
3. Potvrď svoje rozhodnutie.

Keď opustíš skupinu, tvoje doterajšie správy zostanú pre ostatných
členov viditeľné.

---

## 6. Verejné kanály

### Čo sú kanály?

Kanály sú verejné diskusné fóra v rámci siete Cleona. Na rozdiel od
skupín tu môže čítať ktokoľvek bez toho, aby musel byť pozvaný. Príspevky
môžu zverejňovať len vlastník a administrátori -- odberatelia iba čítajú.

### Vyhľadávanie kanálov a pripojenie

1. Prepni sa na kartu „Kanály".
2. Otvor záložku „Hľadať".
3. Prehľadaj dostupné kanály podľa názvu alebo témy.
4. Ťukni na kanál a potom na „Odoberať".

Kanály je možné filtrovať podľa jazyka. Niektoré kanály sú označené ako
„Nevhodné pre mládež" -- tie sú viditeľné len vtedy, ak si vo svojom
profile potvrdil, že máš viac ako 18 rokov.

### Vytvorenie vlastného kanála

1. Prepni sa na kartu „Kanály".
2. Ťukni na tlačidlo plus.
3. Zadaj názov kanála (musí byť jedinečný v celej sieti).
4. Vyber jazyk a či má byť kanál verejný alebo súkromný.
5. Voliteľné: Pridaj popis a obrázok.
6. Ťukni na „Vytvoriť".

Pri verejných kanáloch môžeš určiť, či bude obsah označený ako „Nevhodné
pre mládež".

### Nahlasovanie obsahu

Ak si vo verejnom kanáli všimneš nevhodný obsah, môžeš ho nahlásiť.
Cleona využíva decentralizovaný systém moderácie: hlásenia posudzujú
náhodne vybraní členovia siete (druh „poroty"). Ak sa zistí porušenie,
kanál dostane upozornenie. Pri opakovaných porušeniach je znížené jeho
hodnotenie vo vyhľadávaní alebo je zablokovaný.

### Systémové kanály

Cleona má dva zabudované systémové kanály:

- **Bug Log:** Keď Cleona zaznamená chybu, opýta sa ťa, či chceš odoslať
  anonymizovanú správu o chybe. Tieto správy sa dostanú do kanála Bug
  Log, kde si ich môže pozrieť komunita. Neprenášajú sa žiadne osobné
  údaje -- len technické popisy chýb. Log report môžeš odoslať aj
  manuálne (s dialógom náhľadu a explicitným súhlasom).
- **Feature Requests:** Tu môžu používatelia predkladať návrhy na nové
  funkcie a hlasovať o existujúcich návrhoch. Návrhy sú zoradené podľa
  počtu hlasov.

Oba systémové kanály majú limit veľkosti 25 MB a sú monitorované systémom
porotnej moderácie.

---

## 7. Hovory

### Začatie hlasového hovoru

1. Otvor chat s kontaktom, ktorému chceš zavolať.
2. Ťukni na ikonu telefónu v hornej lište.
3. Počkaj, kým tvoj partner v komunikácii hovor prijme.

Počas hovoru vidíš časovú os, dĺžku hovoru a máš prístup k stlmeniu zvuku
a hlasitému odposluchu.

Na ukončenie hovoru ťukni na červené tlačidlo zavesiť.

### Začatie video hovoru

1. Otvor chat s kontaktom.
2. Ťukni na ikonu kamery v hornej lište.
3. Tvoj obraz z videa sa zobrazí v malom okne, obraz tvojho partnera v
   komunikácii vo veľkej ploche.

Počas hovoru môžeš prepínať medzi prednou a zadnou kamerou.

### Prichádzajúce hovory

Keď ti niekto volá, zobrazí sa okno s upozornením a menom volajúceho.
Môžeš:

- **Prijať** -- hovor sa začne.
- **Odmietnuť** -- volajúci dostane upozornenie.

Ak už si v hovore, nový hovor sa automaticky odmietne.

### Skupinové hovory

Môžeš viesť aj skupinové hovory, na ktorých sa súčasne zúčastňuje viacero
osôb. Hovor je organizovaný pomocou inteligentného stromu preposielania,
takže nemusí byť každý účastník priamo prepojený s každým ostatným.
Všetky hovory sú od začiatku do konca šifrované.

### Šifrovanie hovorov

Všetky hovory sú šifrované jednorazovými kľúčmi, ktoré existujú len počas
trvania hovoru. Po zavesení sa tieto kľúče okamžite vymažú. Nikto nemôže
dodatočne dešifrovať už uskutočnený hovor.

---

## 8. Kalendár

Cleona obsahuje zabudovaný kalendár, ktorý funguje šifrovane a úplne
decentralizovane -- bez cloudovej služby.

### Zobrazenia

Kalendár ponúka päť zobrazení: deň, týždeň, mesiac, rok a zobrazenie
úloh. Medzi nimi prepínaš pomocou kariet v hornej časti obrazovky
kalendára.

### Vytváranie udalostí

Ťukni na časový slot alebo použi tlačidlo pridať, aby si vytvoril novú
udalosť. Môžeš zadať názov, dátum, čas, miesto a poznámky. Udalosti sa
ukladajú šifrovane na tvojom zariadení.

### Opakujúce sa udalosti

Udalosti sa môžu opakovať denne, týždenne, mesačne alebo ročne. Vzor si
môžeš prispôsobiť (napr. každý druhý utorok, vždy prvého v mesiaci) a
nastaviť dátum ukončenia alebo počet opakovaní.

### Pozývanie kontaktov

Pri vytváraní alebo úprave udalosti môžeš pozvať svoje kontakty z Cleony.
Dostanú šifrovanú pozvánku do kalendára a môžu odpovedať áno, nie alebo
možno. Zmeny v udalosti sa automaticky odošlú všetkým pozvaným.

### Zobrazenie voľno/obsadené

Svoju dostupnosť môžeš zdieľať s kontaktmi bez toho, aby si prezradil
podrobnosti o udalosti. Existujú tri úrovne ochrany súkromia: úplné
podrobnosti, len časové bloky alebo skryté. Môžeš nastaviť predvolenú
úroveň a pre jednotlivé kontakty ju prepísať.

### Pripomienky

Udalosti môžu mať pripomienky, ktoré pred začiatkom udalosti spustia
systémové upozornenie. Pripomienky môžeš v prípade potreby odložiť.

### Synchronizácia s externým kalendárom

Cleona sa dokáže synchronizovať s externými kalendárovými službami:

- **CalDAV** -- Pripoj sa k ľubovoľnému serveru kompatibilnému s CalDAV
  (Nextcloud, Radicale atď.).
- **Google Kalendár** -- Synchronizácia cez Google Calendar API s
  bezpečnou autentifikáciou OAuth2.
- **Lokálny CalDAV server** -- Cleona dokáže na tvojom zariadení spustiť
  lokálny CalDAV server, vďaka čomu sa s tvojím kalendárom Cleona môžu
  synchronizovať desktopové kalendárové aplikácie (Thunderbird, Outlook,
  Apple Kalendár, Evolution).
- **Systémový kalendár Android** -- Udalosti z Cleony je možné preniesť
  do zabudovanej kalendárovej aplikácie tvojho zariadenia s Androidom.
- **Súbory ICS** -- Importuj a exportuj udalosti v štandardnom formáte
  iCalendar.

### Export do PDF

Každé zobrazenie kalendára (deň, týždeň, mesiac, rok) môžeš vytlačiť
alebo exportovať ako dokument PDF.

---

## 9. Ankety

V každom chate alebo skupine môžeš vytvárať ankety na zisťovanie názorov
alebo plánovanie termínov.

### Typy ankiet

Cleona podporuje päť typov ankiet:

- **Jednoduchý výber** -- účastníci si vyberú jednu možnosť.
- **Viacnásobný výber** -- účastníci môžu vybrať viacero možností.
- **Anketa o termíne** -- nájdi termín, ktorý vyhovuje všetkým. Každý
  účastník označí termíny ako dostupné, možno alebo nedostupné.
- **Škála** -- ohodnoť niečo na číselnej škále (napr. 1 až 5).
- **Voľný text** -- účastníci napíšu vlastnú odpoveď.

### Vytvorenie ankety

Otvor chat a ťukni na ikonu ankety (alebo použi menu príloh). Vyber typ
ankety, sformuluj svoju otázku a možnosti a odošli anketu. Zobrazí sa ako
správa v chate.

### Hlasovanie

Ťukni na anketu, aby si odovzdal svoj hlas. Svoj hlas môžeš kedykoľvek
zmeniť alebo stiahnuť.

### Anonymné hlasovanie

Ankety je možné nastaviť na anonymné hlasovanie. Ak je táto možnosť
zapnutá, hlasy sú kryptograficky anonymné -- nikto, ani tvorca ankety,
nevidí, kto ako hlasoval. Počet hlasov zostáva napriek tomu viditeľný.

### Anketa o termíne do kalendára

Keď je anketa o termíne uzavretá, víťazný termín je možné jedným ťuknutím
priamo previesť na záznam v kalendári.

---

## 10. Viacero identít

### Prečo viacero identít?

Predstav si, že chceš oddeliť svoj pracovný a súkromný život -- podobne
ako s dvoma rôznymi telefónnymi číslami, ale bez druhého telefónu. V
Cleone môžeš na jednom zariadení používať viacero identít. Každá identita
má vlastné meno, vlastnú profilovú fotku, vlastné kontakty a vlastné
konverzácie.

### Vytvorenie novej identity

1. V hornej lište vidíš svoju aktuálnu identitu ako kartu.
2. Ťukni na znamienko plus (+) vpravo vedľa kariet svojich identít.
3. Zadaj názov novej identity.
4. Hotovo -- nová identita je okamžite aktívna.

### Prepínanie medzi identitami

Jednoducho ťukni na kartu identity v hornej lište. Prepnutie je okamžité
-- žiadne čakanie, žiadne opätovné načítanie.

### Všetky bežia súčasne

Dôležitá vec: všetky tvoje identity sú aktívne súčasne. Aj keď je práve
zobrazená identita „Pracovná", tvoja identita „Súkromná" naďalej prijíma
správy. Nič ti neunikne bez ohľadu na to, ktorú identitu máš práve
vybranú.

### Detailná stránka identity

Keď ťukneš na kartu svojej práve aktívnej identity, otvorí sa detailná
stránka. Tu môžeš:

- Zobraziť svoj QR-Code pre kontakty.
- Zmeniť alebo odstrániť svoju profilovú fotku.
- Pridať popis profilu.
- Zmeniť svoje zobrazované meno.
- Vybrať vzhľad (skin) pre túto identitu.
- Vymazať identitu, ak ju už nepotrebuješ.

### Vymazanie identity

Keď vymažeš identitu, tvoje kontakty o tom dostanú upozornenie. Identita
a všetky súvisiace údaje sa odstránia z tvojho zariadenia. Tento proces
je nezvratný.

---

## 11. Multi-Device

### Používanie Cleony na viacerých zariadeniach

Rovnakú identitu môžeš súčasne používať až na 5 zariadeniach. Jedno
zariadenie je primárne (drží Seed-Phrase) a ďalšie zariadenia sa s ním
prepoja.

### Prepojenie nového zariadenia

1. Otvor Nastavenia na svojom primárnom zariadení.
2. Prejdi na „Prepojené zariadenia".
3. Zvoľ „Prepojiť nové zariadenie".
4. Nainštaluj Cleonu na novom zariadení a pri spustení zvoľ „Prepojiť s
   existujúcim zariadením".
5. Naskenuj párovací QR-Code, ktorý sa zobrazí na tvojom primárnom
   zariadení, alebo použi párovací odkaz.

Prepojené zariadenie dostane od primárneho zariadenia delegačný
certifikát. Správy odoslané z prepojeného zariadenia sú kryptograficky
podpísané delegovaným kľúčom, takže kontakty môžu overiť, že správa
skutočne pochádza od tvojej identity.

### Ako to funguje

- Primárne zariadenie drží tvoju Seed-Phrase a hlavné kľúče.
- Prepojené zariadenia dostanú odvodené podpisové kľúče a delegačný
  certifikát -- samotnú Seed-Phrase nikdy nedostanú.
- Všetky zariadenia zdieľajú tú istú identitu a kontakty. Správy
  prichádzajú na všetky zariadenia.
- Delegačné certifikáty sa pred vypršaním platnosti automaticky
  obnovujú.

### Správa zariadení

Otvor Nastavenia a prejdi na „Prepojené zariadenia", kde uvidíš všetky
svoje prepojené zariadenia, ich stav a poslednú aktivitu. Prepojené
zariadenie môžeš kedykoľvek odvolať, ak sa stratí alebo je ukradnuté.

### Núdzová rotácia kľúčov

Ak máš podozrenie, že bolo niektoré zariadenie kompromitované, môžeš
spustiť núdzovú rotáciu kľúčov. Pri nej sa vygenerujú nové kľúče a
rotáciu musí potvrdiť väčšina tvojich ostatných zariadení. To zabraňuje
tomu, aby jediné ukradnuté zariadenie mohlo kľúče rotovať svojvoľne.

---

## 12. Obnovenie

### Použitie Seed-Phrase

Ak stratíš svoje zariadenie alebo si nastavuješ nové:

1. Nainštaluj Cleonu na novom zariadení.
2. Pri spustení zvoľ „Obnoviť".
3. Zadaj svojich 24 slov.
4. Cleona obnoví tvoju identitu a automaticky kontaktuje tvoje doterajšie
   kontakty.
5. Tvoje kontakty odpovedia tvojimi kontaktnými údajmi, členstvami v
   skupinách a históriou správ.

Obnovenie prebieha v troch krokoch:
- Najprv sa vrátia tvoje kontakty a skupiny.
- Potom posledných 50 správ z každej konverzácie.
- Nakoniec kompletná história správ.

Na to, aby obnovenie fungovalo, stačí, ak je online jediný z tvojich
kontaktov.

### Guardian Recovery (dôveryhodné osoby)

Môžeš určiť až päť dôveryhodných osôb ako „Guardianov". Tvoj obnovovací
kľúč sa pritom rozdelí na päť častí, z ktorých každý Guardian dostane
jednu. Na obnovenie tvojej identity stačia tri z piatich častí.

To znamená: aj keby si stratil svoju Seed-Phrase, traja z tvojich
Guardianov spoločne dokážu obnoviť tvoj účet. Žiadny jednotlivý Guardian
nemá sám prístup k tvojim údajom -- vždy sú potrební minimálne traja.

Takto nastavíš Guardianov:
1. Otvor Nastavenia.
2. Prejdi na „Bezpečnosť".
3. Zvoľ „Guardian Recovery".
4. Vyber päť dôveryhodných kontaktov.

### Prečo sú tvoje kontakty tvojou zálohou

V bežných messengeroch sú tvoje údaje uložené na serveroch poskytovateľa.
Cleona žiadny server nemá -- túto úlohu preberajú tvoje kontakty. Keď
odošleš správu, spoločné kontakty si uložia šifrovanú kópiu pre prípad,
že príjemca je práve offline. Pri obnovení ti tvoje kontakty vrátia tvoje
údaje späť.

To znamená: čím viac aktívnych kontaktov máš, tým spoľahlivejšia je tvoja
záloha. Na úspešné obnovenie stačí jeden kontakt, ktorý je pravidelne
online.

---

## 13. Nastavenia

Nastavenia sú dostupné cez ikonu ozubeného kolieska v pravom hornom rohu.

### Upozornenia a vyzváňacie tóny

- Vyber si z šiestich rôznych vyzváňacích tónov pre prichádzajúce hovory.
- Nastav tón pre správy.
- Na zariadeniach s Androidom môžeš navyše zapnúť alebo vypnúť vibrácie.

### Vzhľady (skiny)

Cleona ponúka desať rôznych vzhľadov: Teal, Ocean, Sunset, Forest,
Amethyst, Fire, Storm, Slate, Gold a Contrast. Vzhľad Contrast spĺňa
najvyššiu úroveň prístupnosti (WCAG AAA) a je obzvlášť dobre čitateľný
pri obmedzenom zraku.

Každá identita môže mať svoj vlastný vzhľad. Vzhľad zmeníš na detailnej
stránke identity (ťuknutím na aktívnu kartu identity).

Okrem toho môžeš v Nastaveniach v časti „Vzhľad" prepínať medzi svetlým,
tmavým a systémovým motívom.

### Zmena jazyka

Cleona je dostupná v 33 jazykoch vrátane jazykov s písmom sprava doľava
(napr. arabčina, hebrejčina). Jazyk zmeníš v Nastaveniach v časti
„Jazyk".

### Limit úložiska

Môžeš určiť, koľko miesta na disku smie Cleona na tvojom zariadení
využívať (medzi 100 MB a 2 GB). Keď je limit dosiahnutý, staršie médiá sa
automaticky presunú alebo vymažú -- textové správy zostávajú vždy
zachované.

### Archivácia médií

Ak máš doma sieťové úložisko (NAS) alebo zdieľaný priečinok, Cleona môže
tvoje médiá automaticky presúvať tam. Podporované sú SMB, SFTP, FTPS a
WebDAV.

Takto funguje stupňované ukladanie:
- Prvých 30 dní: všetko zostáva na tvojom zariadení.
- Po 30 dňoch: náhľadový obrázok zostáva na zariadení, originál sa
  archivuje.
- Po 90 dňoch: na zariadení zostáva už len malý náhľadový obrázok.
- Po roku: zostáva už len zástupný symbol, originál je bezpečne uložený
  v archíve.

Na archivované médium môžeš kedykoľvek ťuknúť a stiahnuť ho späť -- za
predpokladu, že si pripojený k svojej domácej sieti. Obzvlášť dôležité
médiá je možné pripnúť, aby sa nikdy neodsúvali.

### Prepis hlasových správ

Ak je táto funkcia zapnutá, tvoje hlasové správy sa lokálne na tvojom
zariadení prevedú na text (pomocou open-source modelu Whisper). Prepísaný
text sa odošle spolu s nahrávkou tvojmu partnerovi v komunikácii. Prepis
prebieha úplne na tvojom zariadení -- žiadne dáta neopúšťajú zariadenie
smerom k externým službám.

### Automatické sťahovanie

Môžeš nastaviť, od akej veľkosti sa majú médiá sťahovať automaticky.
Napríklad si môžeš nechať obrázky sťahovať automaticky, ale pri veľkých
videách rozhodovať manuálne.

### Prepojené zariadenia

V tejto časti Nastavení spravuješ svoje prepojené zariadenia. Podrobnosti
nájdeš v kapitole Multi-Device.

---

## 14. Bezpečnosť

### Čo znamená postkvantové šifrovanie?

Dnešné šifrovanie je založené na matematických problémoch, ktoré sú pre
bežné počítače extrémne ťažko riešiteľné. Kvantové počítače by v
budúcnosti niektoré z týchto problémov mohli vyriešiť rýchlo. Postkvantové
šifrovanie využíva dodatočné postupy, ktoré odolávajú aj kvantovým
počítačom.

Cleona kombinuje oba prístupy: klasické šifrovanie pre spoľahlivosť a
postkvantové postupy pre odolnosť voči budúcnosti. Si tak chránený
súčasne pred dnešnými aj budúcimi hrozbami.

Pre každú jednotlivú správu sa vytvára vlastný kľúč. Aj keby útočník
prelomil kľúč jednej správy, nemohol by ním prečítať žiadnu inú správu.

### Prečo je bez servera bezpečnejšie

V bežných messengeroch prechádzajú tvoje správy cez servery poskytovateľa.
Aj keď tam môžu byť šifrované: poskytovateľ má prístup k metadátam (kto
kedy s kým komunikuje, ako často, odkiaľ) a za určitých okolností ich
musí na základe súdneho príkazu vydať.

Pri Cleone takýto centrálny bod neexistuje. Tvoje správy putujú priamo
zo zariadenia na zariadenie. Neexistuje miesto, kde by sa zbiehali všetky
metadáta. Nikto nemôže na základe jediného dátového bodu rekonštruovať
tvoje komunikačné správanie.

### Čo sa stane, keď si offline?

Keď odošleš správu a príjemca je offline:

1. Cleona sa najprv pokúsi doručiť správu priamo.
2. Ak sa to nepodarí, správa sa preposiela cez spoločné kontakty.
3. Súčasne sa správa rozdelí na šifrované časti a rozloží na viacero
   uzlov v sieti (podobne ako puzzle zložené z 10 dielikov, z ktorých 7
   stačí na zloženie obrázka).
4. Správa sa uchováva až 7 dní.

Akonáhle sa príjemca opäť pripojí, správy sa doručia. Keď tvoja správa
dorazí, dostaneš potvrdenie.

### Ochrana proti cenzúre

Ak tvoja sieť blokuje štandardný spôsob pripojenia (UDP), Cleona
automaticky prepne na alternatívny prenos (TLS), ktorý sa ťažšie
rozpoznáva a blokuje. Deje sa to transparentne -- nemusíš nič nastavovať.

### Bezpečné uloženie kľúčov

Na podporovaných platformách Cleona ukladá tvoje šifrovacie kľúče do
bezpečného zväzku kľúčov operačného systému (Android Keystore, iOS
Keychain, macOS Keychain). Tam, kde je to dostupné, to poskytuje
hardvérovo podporovanú ochranu tvojich kľúčov.

### Šifrovanie databázy

Všetky tvoje správy, kontakty a nastavenia sú na tvojom zariadení uložené
šifrovane. Aj keby niekto získal prístup k tvojmu súborovému systému, bez
tvojho kryptografického kľúča by nič neprečítal. Tento kľúč je odvodený
z tvojej identity a existuje len na tvojom zariadení.

### Uzavretá sieť

Cleona funguje ako uzavretá sieť. Každý sieťový paket je autentifikovaný,
takže sa siete môžu zúčastniť len legitímne zariadenia Cleona. To
zabraňuje tomu, aby cudzie osoby vkladali falošné správy alebo
odpočúvali sieťovú prevádzku.

---

## 15. Softvérové aktualizácie

### Ako získam aktualizácie?

Cleonu je možné aktualizovať viacerými spôsobmi. Cieľom je, aby si
aktualizácie dostal aj vtedy, keď jednotlivé distribučné kanály vypadnú
alebo sú zablokované:

1. **App Store / Play Store:** Ak si Cleonu nainštaloval cez niektorý
   App Store, aktualizácie dostávaš ako obvykle cez daný obchod.
2. **GitHub Releases:** Na stránke projektu na GitHub nájdeš podpísané
   inštalačné balíky pre všetky platformy.
3. **Aktualizácie v rámci siete (In-Network):** Ak má iný používateľ
   Cleony vo tvojej sieti už najnovšiu verziu, Cleona môže aktualizáciu
   získať priamo cez P2P sieť -- bez externého servera. Nová verzia sa
   pritom rozloží na fragmenty s korekciou chýb a rozdelí sa medzi
   viacero uzlov. Tvoje zariadenie zozbiera dostatok fragmentov a
   aktualizáciu poskladá. Pravosť sa overuje pomocou podpisu Ed25519 od
   vývojára.
4. **Pozývacie odkazy:** Môžeš vytvárať pozývacie odkazy, ktoré obsahujú
   všetko, čo nový používateľ potrebuje na inštaláciu Cleony a pripojenie
   k sieti.
5. **Fyzický prenos:** V prostrediach bez internetu môžeš Cleonu odovzdať
   ostatným cez USB kľúč alebo v lokálnej sieti.

### Upozornenie na aktualizáciu

Keď je dostupná nová aktualizácia, Cleona ti zobrazí upozornenie na
úvodnej obrazovke. Ak je aktualizácia dostupná aj cez sieť (In-Network
aktualizácia), máš možnosť stiahnuť ju priamo zo siete.

### Distribúcia binárnych súborov

Predvolene tvoje zariadenie pomáha odovzdávať aktualizácie ďalším
používateľom v sieti. Ak si to neželáš, môžeš túto funkciu vypnúť v
Nastaveniach v časti „Sieť". Využitie úložiska pre fragmenty aktualizácií
je obmedzené (5 MB na mobilných zariadeniach, 20 MB na desktopových
zariadeniach) a pravidelne sa čistí.

### Overenie podpisu

Každá aktualizácia je kryptograficky podpísaná. Cleona automaticky
overí podpis skôr, než sa aktualizácia nainštaluje. Tým je zaručené, že
sa akceptujú len aktualizácie od oficiálneho vývojára -- aj keby bola
aktualizácia získaná cez P2P sieť.

---

## 16. Časté otázky

### „Môžem používať Cleonu bez internetu?"

Nie, Cleona potrebuje sieťové pripojenie na odosielanie a prijímanie
správ. Nemusíš však byť online v rovnakom čase ako tvoj partner v
komunikácii: správy odoslané v čase, keď je príjemca offline, sa dočasne
uložia a automaticky doručia, akonáhle sa obe strany znova pripoja. V
lokálnej sieti (napr. v tej istej WLAN) môžete komunikovať aj úplne bez
prístupu na internet.

### „Čo ak stratím svoju Seed-Phrase?"

Ak máš nastavených Guardianov, traja z piatich dôveryhodných osôb ti
spoločne môžu obnoviť prístup. Bez Guardianov a bez Seed-Phrase bohužiaľ
neexistuje spôsob, ako svoju identitu znova získať. Preto je také
dôležité bezpečne uschovať tých 24 slov.

### „Môže niekto čítať moje správy?"

Nie. Každá správa je zašifrovaná jednorazovým kľúčom, ktorý platí len
pre túto jednu správu. Dešifrovať ju môžete len ty a tvoj partner v
komunikácii. Neexistuje centrálny server, žiadny univerzálny kľúč a
žiadny prístup pre vývojára. Aj keď správu na ceste preposiela nejaké
zariadenie, vidí len šifrovanú digitálnu kašu.

### „Prečo nepotrebujem telefónne číslo?"

Pretože tvoja identita je čisto kryptografická. Namiesto telefónneho
čísla alebo e-mailovej adresy spojenej s tvojím skutočným menom ťa
identifikuje pár kľúčov vygenerovaný na tvojom zariadení. Kontakty
pridávaš cez QR-Code, NFC alebo odkaz -- nie cez telefónny zoznam. To
znamená viac súkromia, pretože tvoj účet messengera nie je viazaný na
tvoju reálnu identitu.

### „Ako nájdem ľudí na Cleone?"

Cleona zámerne nemá vyhľadávanie kontaktov podľa telefónneho čísla alebo
mena -- to by bol problém súkromia. Namiesto toho si kontaktné údaje
vymieňaš priamo: cez QR-Code, NFC, odkaz cleona:// alebo vo verejných
kanáloch. Je to ako výmena vizitiek namiesto listovania v telefónnom
zozname.

### „Funguje Cleona aj v zahraničí?"

Áno. Pokiaľ máš internetové pripojenie, Cleona funguje kdekoľvek na
svete. Keďže neexistuje centrálny server, službu nemožno zablokovať ani
pre konkrétne krajiny. Cleona má navyše záložný mechanizmus proti
cenzúre: keď je bežné pripojenie (UDP) blokované, Cleona automaticky
prepne na alternatívny prenos (TLS), ktorý sa ťažšie rozpoznáva a
blokuje.

### „Je Cleona zadarmo?"

Áno. Cleonu môžeš používať zadarmo a bez reklám. Keďže neexistuje
centrálny server, nevznikajú ani žiadne prevádzkové náklady na server. V
aplikácii nájdeš v časti „Darovať" možnosť dobrovoľne podporiť vývoj.

### „Moja správa má ikonu hodín -- čo to znamená?"

Znamená to, že správa ešte nebola doručená. Tvoj partner v komunikácii
je pravdepodobne práve offline. Akonáhle je správa doručená, ikona sa
zmení. Správy sa na účely doručenia uchovávajú až 7 dní.

### „Môžem prejsť z WhatsApp na Cleonu?"

Áno, ale svoje chaty z WhatsApp nemôžeš preniesť. Cleona a WhatsApp sú
zásadne odlišné systémy. Svoje kontakty musíš do Cleony pridať
jednotlivo. Najjednoduchšie je, keď svoj odkaz cleona:// zverejníš v
skupine na WhatsApp a požiadaš ostatných, aby ťa tam pridali.

### „Môžem používať Cleonu na viacerých zariadeniach súčasne?"

Áno. Môžeš prepojiť až 5 zariadení s rovnakou identitou. Jedno zariadenie
je primárne (drží Seed-Phrase) a ďalšie zariadenia sa prepájajú
prostredníctvom bezpečného párovacieho procesu. Všetky zariadenia
zdieľajú rovnakú identitu, kontakty a konverzácie. Podrobnosti nájdeš v
kapitole Multi-Device.

### „Ako získam aktualizácie, keď je App Store zablokovaný?"

Cleona dokáže získať aktualizácie priamo cez P2P sieť bez toho, aby bola
odkázaná na App Store, webovú stránku alebo sťahovací server. Ak má iný
používateľ v sieti najnovšiu verziu, tvoje zariadenie si aktualizáciu
môže stiahnuť odtiaľ. Pravosť sa overuje digitálnym podpisom vývojára.
Alternatívne ti aplikáciu môže odovzdať kontakt cez pozývací odkaz alebo
USB kľúč. Viac o tom v kapitole „Softvérové aktualizácie".

---

## Pomoc a kontakt

Ak máš otázky alebo narazíš na problém, aktuálne informácie nájdeš na
webe Cleona a na GitHub. Keďže Cleona je decentralizovaný projekt,
neexistuje klasická zákaznícka podpora -- ale existuje aktívna komunita,
ktorá rada pomôže.

---

*Táto príručka popisuje Cleona Chat vo verzii 3.1.125. Jednotlivé funkcie
sa môžu v novších verziách zmeniť alebo rozšíriť.*

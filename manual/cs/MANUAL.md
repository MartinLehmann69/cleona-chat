# Cleona Chat -- Uživatelská příručka

Verze 3.1.125 | Červenec 2026

---

## Obsah

1. [Co je Cleona Chat?](#1-co-je-cleona-chat)
2. [První kroky](#2-prvni-kroky)
3. [Kontakty](#3-kontakty)
4. [Zprávy](#4-zpravy)
5. [Skupiny](#5-skupiny)
6. [Veřejné kanály](#6-verejne-kanaly)
7. [Hovory](#7-hovory)
8. [Kalendář](#8-kalendar)
9. [Ankety](#9-ankety)
10. [Více identit](#10-vice-identit)
11. [Multi-Device](#11-multi-device)
12. [Obnovení](#12-obnoveni)
13. [Nastavení](#13-nastaveni)
14. [Zabezpečení](#14-zabezpeceni)
15. [Aktualizace softwaru](#15-aktualizace-softwaru)
16. [Časté dotazy](#16-caste-dotazy)

---

## 1. Co je Cleona Chat?

### Tvůj messenger, tvá data

Cleona Chat je messenger, který funguje zcela bez centrálního serveru.
Tvoje zprávy putují přímo z tvého zařízení do zařízení tvého protějšku --
bez oklik přes sídlo firmy, bez cloudu, bez datového centra. Žádná
společnost nemůže tvoje zprávy číst, ukládat ani předávat dál, protože mezi
vámi jednoduše žádná společnost nestojí.

### Žádný účet, žádné telefonní číslo

U Cleony nepotřebuješ k přihlášení ani telefonní číslo, ani e-mailovou
adresu. Tvá identita se skládá z kryptografického páru klíčů, který se při
prvním spuštění automaticky vygeneruje na tvém zařízení. To znamená: nikdo
tě nemůže vypátrat podle telefonního čísla nebo e-mailové adresy, pokud své
kontaktní údaje sám nesdělíš.

### Budoucnosti odolné šifrování

Cleona používá tzv. postkvantové šifrování. To znamená: ani budoucí
kvantové počítače by nedokázaly tvoje zprávy prolomit. Detaily nemusíš
chápat -- důležité je jen to, že tvá komunikace je chráněna co nejlépe podle
současného stavu techniky.

### Jak to funguje bez serveru?

Představ si, že ty a tvoje kontakty společně tvoříte síť. Každé zařízení
pomáhá předávat zprávy dál. Pokud je tvůj protějšek zrovna online, jde
zpráva přímo k němu. Pokud je offline, uloží zprávu mezitím společné
kontakty a doručí ji, jakmile se příjemce znovu objeví. Tvoje kontakty jsou
tedy zároveň i tvá síť.

### Platformy

Cleona je dostupná pro Android, iOS, macOS, Linux a Windows.

---

## 2. První kroky

### Instalace aplikace

**Android:**
1. Stáhni si soubor APK z webu Cleony nebo z GitHub Releases.
2. Otevři soubor v telefonu. Pokud je potřeba, povol instalaci z neznámých
   zdrojů (Android se tě zeptá automaticky).
3. Klepni na "Instalovat" a počkej, až se instalace dokončí.

**iOS:**
1. Otevři pozvánku do TestFlight na svém iPhonu.
2. Klepni na "Instalovat". TestFlight je oficiální způsob Applu pro
   distribuci beta aplikací.
3. Po instalaci najdeš Cleonu na ploše.

**macOS:**
1. Stáhni si soubor DMG z webu Cleony nebo z GitHub Releases.
2. Otevři DMG a přetáhni Cleonu do složky Aplikace.
3. Při prvním spuštění se macOS možná zeptá, jestli chceš otevřít aplikaci
   od identifikovaného vývojáře -- potvrď to.

**Linux (Ubuntu/Debian):**
1. Stáhni si soubor .deb z webu Cleony nebo z GitHub Releases.
2. Nainstaluj dvojklikem nebo v terminálu: `sudo dpkg -i cleona-chat_VERSION_amd64.deb`
3. Spusť Cleonu z nabídky aplikací nebo v terminálu příkazem `cleona-chat`.

**Linux (Fedora/openSUSE):**
1. Stáhni si soubor .rpm z webu Cleony nebo z GitHub Releases.
2. Nainstaluj příkazem: `sudo dnf install cleona-chat-VERSION.x86_64.rpm`
3. Spusť Cleonu z nabídky aplikací nebo v terminálu příkazem `cleona-chat`.

**Linux (všechny distribuce -- AppImage):**
1. Stáhni si soubor .AppImage z webu Cleony nebo z GitHub Releases.
2. Nastav soubor jako spustitelný: pravé tlačítko, Vlastnosti, Spustitelný,
   nebo v terminálu: `chmod +x cleona-chat-VERSION-x86_64.AppImage`
3. Spusť dvojklikem nebo v terminálu: `./cleona-chat-VERSION-x86_64.AppImage`

**Windows:**
1. Stáhni si instalátor z webu Cleony nebo z GitHub Releases.
2. Spusť instalační soubor a postupuj podle pokynů.
3. Spusť Cleonu z nabídky Start nebo pomocí zástupce na ploše.

### Vytvoření identity

Při prvním spuštění vytvoří Cleona automaticky novou identitu. Můžeš si
zvolit zobrazované jméno -- to je jméno, které uvidí tvoje kontakty. Toto
jméno lze kdykoli změnit.

### Zapsání Seed-Phrase -- to nejdůležitější ze všeho

Po vytvoření identity ti Cleona zobrazí 24 slov. To je tvá
**Seed-Phrase** -- tvůj osobní klíč pro obnovení.

**Zapiš si těchto 24 slov na papír a bezpečně je ulož.**

Proč je to tak důležité?

- Pokud se tvůj telefon rozbije, ztratí se nebo je ukraden, můžeš pomocí
  těchto 24 slov obnovit celou svou identitu na novém zařízení.
- Bez Seed-Phrase neexistuje cesta zpět. Neexistuje tlačítko "zapomenuté
  heslo" ani podpora, která by ti mohla vrátit účet -- protože žádný účet na
  serveru vůbec neexistuje.
- Seed-Phrase nikdy nikomu nesděluj. Kdokoli tato slova zná, se za tebe může
  vydávat.

Seed-Phrase najdeš později také v nastavení pod "Zabezpečení", pokud si ji
budeš chtít znovu přečíst.

### Přidání prvního kontaktu

Aby ses s někým mohl bavit, musíš danou osobu nejprve přidat jako kontakt.
K tomu vede několik cest -- všechny jsou vysvětleny v následující kapitole.

---

## 3. Kontakty

### Naskenování QR kódu (doporučeno)

Nejjednodušší způsob, jak přidat kontakt:

1. Tvůj protějšek otevře stránku podrobností své identity (klepnutím na
   vlastní jméno v horní liště) a ukáže ti svůj QR kód.
2. Klepneš na tlačítko plus a zvolíš "Naskenovat QR kód".
3. Namiř telefon na QR kód protějšku.
4. Žádost o kontakt se odešle automaticky. Jakmile ji protějšek přijme,
   můžete si spolu psát.

Pokud se setkáte osobně, je QR kód nejbezpečnější metodou, protože přesně
víš, s kým si kontakt vyměňuješ.

### NFC (přiložení telefonů k sobě)

Pokud obě zařízení podporují NFC:

1. Oba otevřete funkci přidání kontaktu.
2. Přiložte telefony k sobě zády.
3. Kontaktní údaje se automaticky vymění.

NFC nabízí, podobně jako QR kód, vysokou úroveň bezpečnosti, protože výměna
funguje jen tehdy, když stojíte fyzicky vedle sebe.

### Sdílení odkazu (cleona:// URI)

Svůj kontaktní odkaz můžeš poslat také e-mailem, SMS nebo přes jiný
messenger:

1. Otevři stránku podrobností své identity.
2. Zkopíruj svůj odkaz cleona://.
3. Pošli odkaz osobě, která tě má přidat.
4. Druhá osoba odkaz otevře, nebo ho vloží do dialogu pro přidání kontaktu.

Pozor: u této metody spoléháš na to, že odkaz nebyl při přenosu pozměněn.
Pro obzvlášť citlivé kontakty doporučujeme QR kód nebo NFC.

### Přijímání žádostí o kontakt

Když ti někdo pošle žádost o kontakt, objeví se v tvé schránce (poslední
záložka ve spodní liště). Tam můžeš:

- **Přijmout** -- osoba se přidá mezi tvoje kontakty.
- **Odmítnout** -- žádost se zamítne.
- **Blokovat** -- osoba ti nemůže posílat další žádosti.

### Úrovně ověření

Cleona ti ukazuje, jak spolehlivě je potvrzená identita kontaktu:

| Úroveň | Význam |
|-------|-----------|
| Neznámý | Máš pouze Node-ID nebo odkaz. |
| Viděný | Výměna klíčů proběhla úspěšně, můžete spolu komunikovat šifrovaně. |
| Ověřený | Setkali jste se osobně a ověřili se přes QR kód nebo NFC. |
| Důvěryhodný | Tento kontakt jsi výslovně označil jako důvěryhodný. |

Čím vyšší úroveň, tím si můžeš být jistější, že skutečně mluvíš se správnou
osobou.

---

## 4. Zprávy

### Odesílání a přijímání textu

Stačí napsat zprávu do vstupního pole dole a stisknout Enter nebo tlačítko
odeslat. Tvoje zpráva se automaticky zašifruje, než opustí tvé zařízení.

Příchozí zprávy se zobrazují v historii chatu. Zaškrtávátko ti ukáže, zda
byla tvoje zpráva doručena.

### Odesílání obrázků, videí a souborů

Máš několik možností:

- **Ikona sponky** ve vstupním poli: klepni na ni a vyber soubor, obrázek
  nebo video z galerie nebo souborového systému.
- **Přetažení (drag and drop)** (desktop): jednoduše přetáhni soubor do okna
  chatu.
- **Vložení ze schránky** (desktop): zkopíruj obrázek a vlož ho do chatu.

Malé soubory (do 256 KB) se posílají přímo. Větší soubory se přenášejí ve
dvoufázovém postupu: nejdřív se soubor ohlásí, poté se přenese po částech.

### Hlasové zprávy

1. Podrž tlačítko mikrofonu ve vstupním poli.
2. Namluv svou zprávu.
3. Tlačítko pusť, aby se zpráva odeslala.

Pokud máš na svém zařízení aktivované rozpoznávání řeči (viz nastavení),
tvá hlasová zpráva se automaticky přepíše do textu. Tvůj protějšek pak vidí
jak nahrávku, tak přepsaný text.

### Odpovídání na zprávy (citace)

Chceš-li odpovědět na konkrétní zprávu:

1. Otevři menu se třemi tečkami vedle zprávy.
2. Zvol "Odpovědět".
3. Nad vstupním polem se objeví banner s citovanou zprávou.
4. Napiš svou odpověď a odešli ji.

Citovaná zpráva se zobrazí v tvé odpovědi, takže je souvislost jasná.

### Úprava a mazání zpráv

- **Úprava:** Menu se třemi tečkami u zprávy, poté "Upravit". Změň text a
  znovu ho odešli. Tvůj protějšek uvidí, že zpráva byla upravena. Úprava je
  možná do 15 minut od odeslání.
- **Mazání:** Menu se třemi tečkami u zprávy, poté "Smazat". Zpráva se
  odstraní u tebe i u tvého protějšku. Vlastní zprávy můžeš smazat kdykoli --
  pro mazání neexistuje žádné časové omezení.

### Emoji reakce

Místo psaní odpovědi můžeš na zprávu reagovat emoji:

1. Otevři menu se třemi tečkami nebo podrž zprávu stiskem.
2. Vyber emoji z rychlého výběru, nebo otevři výběr emoji pro plnou
   nabídku.
3. Tvá reakce se zobrazí pod zprávou.

### Kopírování textu

Přes menu se třemi tečkami u zprávy můžeš zkopírovat text zprávy do
schránky.

### Vyhledávání ve zprávách

V horní části okna chatu najdeš vyhledávací funkci. Zadej hledaný výraz a
Cleona ti zobrazí všechny výskyty v aktuálním chatu. Šipkami se můžeš
pohybovat mezi výsledky.

Na úvodní obrazovce je navíc filtr pro vyhledávání napříč záložkami, kterým
můžeš prohledat všechny konverzace podle zadaného výrazu.

### Náhled odkazu

Když pošleš odkaz, Cleona automaticky vytvoří náhled (titulek, popis,
náhledový obrázek). Tento náhled vytváří tvé zařízení a posílá ho spolu se
zprávou -- tvůj protějšek proto nemusí navazovat spojení s odkazovanou
webovou stránkou.

Když klepneš na přijatý odkaz, budeš dotázán, zda ho chceš otevřít v
běžném prohlížeči, v anonymním režimu, nebo vůbec ne.

---

## 5. Skupiny

### Vytvoření skupiny

1. Přepni na záložku "Skupiny".
2. Klepni na tlačítko plus.
3. Zadej název skupiny.
4. Vyber kontakty, které chceš pozvat.
5. Klepni na "Vytvořit".

Pozvané kontakty dostanou upozornění a mohou do skupiny vstoupit.

### Zvaní členů

I po vytvoření skupiny můžeš zvát další kontakty:

1. Otevři informace o skupině (menu se třemi tečkami v přehledu skupiny
   nebo horní lišta v chatu skupiny).
2. Klepni na "Pozvat".
3. Vyber kontakty, které chceš přidat.

### Role

Každá skupina má tři role:

- **Vlastník (Owner):** Má plnou kontrolu. Může přidávat a odebírat členy,
  jmenovat administrátory a spravovat skupinu. Vlastník může svůj status
  přenést i na jiného člena.
- **Administrátor:** Může odebírat členy a pomáhat se správou.
- **Člen:** Může číst a psát zprávy.

### Opuštění skupiny

1. Otevři menu se třemi tečkami v přehledu skupiny.
2. Zvol "Opustit".
3. Potvrď své rozhodnutí.

Když skupinu opustíš, tvé dosavadní zprávy zůstanou pro ostatní členy
viditelné.

---

## 6. Veřejné kanály

### Co jsou kanály?

Kanály jsou veřejná diskuzní fóra uvnitř sítě Cleona. Na rozdíl od skupin
zde může kdokoli číst, aniž by musel být pozván. Příspěvky mohou
zveřejňovat pouze vlastník a administrátoři -- odběratelé pouze čtou.

### Vyhledávání kanálů a přihlášení k odběru

1. Přepni na záložku "Kanály".
2. Otevři záložku "Hledat".
3. Procházej dostupné kanály podle názvu nebo tématu.
4. Klepni na kanál a poté na "Odebírat".

Kanály lze filtrovat podle jazyka. Některé kanály jsou označené jako
"Nevhodné pro mladistvé" -- ty jsou viditelné pouze tehdy, když jsi ve svém
profilu potvrdil, že je ti více než 18 let.

### Vytvoření vlastního kanálu

1. Přepni na záložku "Kanály".
2. Klepni na tlačítko plus.
3. Zadej název kanálu (musí být jedinečný v celé síti).
4. Vyber jazyk a zda má být kanál veřejný, nebo soukromý.
5. Volitelně: přidej popis a obrázek.
6. Klepni na "Vytvořit".

U veřejných kanálů můžeš určit, zda bude obsah označen jako "Nevhodné pro
mladistvé".

### Nahlašování obsahu

Pokud si ve veřejném kanálu všimneš nevhodného obsahu, můžeš ho nahlásit.
Cleona využívá decentralizovaný systém moderace: nahlášení vyhodnocují
náhodně vybraní členové sítě (jakási forma "poroty"). Pokud se zjistí
porušení, dostane kanál varování. Při opakovaném porušování je kanál v
indexu vyhledávání znevýhodněn, nebo úplně zablokován.

### Systémové kanály

Cleona má dva vestavěné systémové kanály:

- **Bug Log:** Když Cleona rozpozná chybu, zeptá se tě, zda chceš odeslat
  anonymizované hlášení o chybě. Tato hlášení se objeví v kanálu Bug Log,
  kde je může vidět komunita. Nepřenáší se žádné osobní údaje -- pouze
  technické popisy chyb. Log-hlášení můžeš odeslat i ručně (s náhledovým
  dialogem a výslovným souhlasem).
- **Feature Requests:** Zde mohou uživatelé podávat návrhy na nové funkce a
  hlasovat pro existující návrhy. Návrhy jsou seřazeny podle počtu hlasů.

Oba systémové kanály mají limit velikosti 25 MB a jsou sledovány systémem
porotní moderace.

---

## 7. Hovory

### Zahájení hlasového hovoru

1. Otevři chat s kontaktem, kterému chceš zavolat.
2. Klepni na ikonu telefonu v horní liště.
3. Počkej, až tvůj protějšek hovor přijme.

Během hovoru vidíš časovou osu, dobu trvání hovoru a máš přístup k ztlumení
mikrofonu a reproduktoru.

Pro ukončení klepni na červené tlačítko zavěsit.

### Zahájení videohovoru

1. Otevři chat s kontaktem.
2. Klepni na ikonu kamery v horní liště.
3. Tvůj obraz se objeví v malém okně, obraz protějšku ve velké ploše.

Během hovoru můžeš přepínat mezi přední a zadní kamerou.

### Příchozí hovory

Když ti někdo volá, objeví se okno s upozorněním obsahující jméno
volajícího. Můžeš:

- **Přijmout** -- hovor začne.
- **Odmítnout** -- volající dostane upozornění.

Pokud už v jednom hovoru jsi, nový hovor se automaticky odmítne.

### Skupinové hovory

Můžeš uskutečňovat i skupinové hovory, kterých se účastní více lidí
najednou. Hovor je organizován přes inteligentní strom pro předávání dat,
takže nemusí být každý účastník přímo propojen s každým jiným. Všechny
hovory jsou po celou dobu šifrované.

### Šifrování hovorů

Všechny hovory jsou šifrovány jednorázovými klíči, které existují pouze po
dobu hovoru. Po zavěšení jsou tyto klíče okamžitě smazány. Nikdo nemůže
dodatečně dešifrovat proběhlý hovor.

---

## 8. Kalendář

Cleona obsahuje vestavěný kalendář, který funguje šifrovaně a zcela
decentralizovaně -- bez cloudové služby.

### Zobrazení

Kalendář nabízí pět zobrazení: den, týden, měsíc, rok a zobrazení úkolů.
Mezi nimi přepínáš přes záložky v horní části obrazovky kalendáře.

### Vytváření událostí

Klepni na časový slot nebo použij tlačítko přidat, čímž vytvoříš novou
událost. Můžeš zadat název, datum, čas, místo a poznámky. Události se
ukládají na tvém zařízení v šifrované podobě.

### Opakující se události

Události se mohou opakovat denně, týdně, měsíčně nebo ročně. Vzor můžeš
přizpůsobit (např. každé druhé úterý, každý první den v měsíci) a nastavit
datum ukončení nebo počet opakování.

### Zvaní kontaktů

Při vytváření nebo úpravě události můžeš pozvat své kontakty z Cleony.
Dostanou šifrovanou pozvánku do kalendáře a mohou odpovědět "ano", "ne"
nebo "možná". Změny v události se automaticky odešlou všem pozvaným.

### Zobrazení volno/obsazeno

Svou dostupnost můžeš sdílet s kontakty, aniž bys odhalil podrobnosti o
události. Existují tři úrovně ochrany soukromí: plné podrobnosti, pouze
časové bloky nebo skryto. Můžeš nastavit výchozí hodnotu a přepsat ji
individuálně pro každý kontakt.

### Připomenutí

Události mohou mít připomenutí, které před začátkem spustí systémové
upozornění. Připomenutí lze podle potřeby odložit.

### Synchronizace s externím kalendářem

Cleona se může synchronizovat s externími kalendářovými službami:

- **CalDAV** -- Připoj se k libovolnému serveru kompatibilnímu s CalDAV
  (Nextcloud, Radicale atd.).
- **Google kalendář** -- Synchronizace přes Google Calendar API se
  zabezpečeným ověřením OAuth2.
- **Lokální server CalDAV** -- Cleona umí spustit lokální server CalDAV
  přímo na tvém zařízení, takže se s tvým kalendářem Cleony mohou
  synchronizovat desktopové kalendářové aplikace (Thunderbird, Outlook,
  Apple Kalendář, Evolution).
- **Systémový kalendář Androidu** -- Události z Cleony lze přenést do
  vestavěné kalendářové aplikace tvého zařízení Android.
- **Soubory ICS** -- Importuj a exportuj události ve standardním formátu
  iCalendar.

### Export do PDF

Každé zobrazení kalendáře (den, týden, měsíc, rok) můžeš vytisknout nebo
exportovat jako dokument PDF.

---

## 9. Ankety

V každém chatu nebo skupině můžeš vytvářet ankety, abys zjistil názory nebo
naplánoval termín.

### Typy anket

Cleona podporuje pět typů anket:

- **Jednoduchý výběr** -- účastníci vyberou jednu možnost.
- **Vícenásobný výběr** -- účastníci mohou vybrat více možností.
- **Termínová anketa** -- najdi termín, který vyhovuje všem. Každý účastník
  označí termíny jako dostupné, možná dostupné nebo nedostupné.
- **Škála** -- ohodnoť něco na číselné škále (např. 1 až 5).
- **Volný text** -- účastníci napíší vlastní odpověď.

### Vytvoření ankety

Otevři chat a klepni na ikonu ankety (nebo použij menu příloh). Vyber typ
ankety, zformuluj otázku a možnosti a anketu odešli. Zobrazí se jako zpráva
v chatu.

### Hlasování

Klepnutím na anketu odevzdáš svůj hlas. Svůj hlas můžeš kdykoli změnit
nebo odvolat.

### Anonymní hlasování

Ankety lze nastavit pro anonymní hlasování. Pokud je aktivní, jsou hlasy
kryptograficky anonymní -- nikdo, ani tvůrce ankety, nevidí, kdo pro co
hlasoval. Počet hlasů přesto zůstává viditelný.

### Termínová anketa do kalendáře

Jakmile je termínová anketa uzavřena, lze vítězný termín jedním klepnutím
přímo převést na položku v kalendáři.

---

## 10. Více identit

### Proč více identit?

Představ si, že chceš oddělit pracovní a soukromý život -- podobně jako se
dvěma různými telefonními čísly, ale bez druhého telefonu. V Cleoně můžeš
na jednom zařízení používat více identit. Každá identita má vlastní jméno,
vlastní profilový obrázek, vlastní kontakty a vlastní konverzace.

### Vytvoření nové identity

1. V horní liště vidíš svou aktuální identitu jako záložku.
2. Klepni na znaménko plus (+) vpravo vedle záložek identit.
3. Zadej jméno pro novou identitu.
4. Hotovo -- nová identita je okamžitě aktivní.

### Přepínání mezi identitami

Stačí klepnout na záložku identity v horní liště. Přepnutí je okamžité --
žádné čekání, žádné znovunačítání.

### Všechny běží zároveň

Důležitý bod: všechny tvoje identity jsou aktivní současně. I když je
právě zobrazená identita "Pracovní", tvá identita "Soukromá" nadále přijímá
zprávy. Nic ti neunikne, ať už máš zrovna vybranou jakoukoli identitu.

### Stránka podrobností identity

Když klepneš na záložku právě aktivní identity, otevře se stránka
podrobností. Zde můžeš:

- Zobrazit svůj QR kód pro kontakty.
- Změnit nebo odstranit svůj profilový obrázek.
- Přidat popis profilu.
- Změnit své zobrazované jméno.
- Zvolit design (skin) pro tuto identitu.
- Smazat identitu, pokud ji už nepotřebuješ.

### Smazání identity

Když smažeš identitu, budou o tom tvoje kontakty upozorněny. Identita a
všechna související data se odstraní z tvého zařízení. Tento krok je
nevratný.

---

## 11. Multi-Device

### Používání Cleony na více zařízeních

Stejnou identitu můžeš používat současně až na 5 zařízeních. Jedno
zařízení je primární (drží Seed-Phrase) a další zařízení se s ním propojí.

### Propojení nového zařízení

1. Otevři nastavení na svém primárním zařízení.
2. Přejdi na "Propojená zařízení".
3. Zvol "Propojit nové zařízení".
4. Na novém zařízení nainstaluj Cleonu a při spuštění zvol "Propojit s
   existujícím zařízením".
5. Naskenuj párovací QR kód zobrazený na primárním zařízení, nebo použij
   párovací odkaz.

Propojené zařízení obdrží delegační certifikát od primárního zařízení.
Zprávy odeslané z propojeného zařízení jsou kryptograficky podepsány
delegovaným klíčem, takže kontakty mohou ověřit, že zpráva skutečně
pochází od tvé identity.

### Jak to funguje

- Primární zařízení drží tvou Seed-Phrase a hlavní klíče.
- Propojená zařízení obdrží odvozené podpisové klíče a delegační
  certifikát -- samotnou Seed-Phrase nikdy nezískají.
- Všechna zařízení sdílejí stejnou identitu a kontakty. Zprávy přicházejí
  na všechna zařízení.
- Delegační certifikáty se automaticky obnovují před vypršením platnosti.

### Správa zařízení

Otevři nastavení a přejdi na "Propojená zařízení", kde uvidíš všechna
propojená zařízení, jejich stav a poslední aktivitu. Propojené zařízení
můžeš kdykoli odvolat, pokud se ztratí nebo je ukradeno.

### Nouzová rotace klíčů

Pokud máš podezření, že bylo některé zařízení kompromitováno, můžeš
spustit nouzovou rotaci klíčů. Vygenerují se nové klíče a rotaci musí
potvrdit většina tvých ostatních zařízení. To zabraňuje tomu, aby jediné
ukradené zařízení mohlo svévolně rotovat klíče.

---

## 12. Obnovení

### Použití Seed-Phrase

Pokud ztratíš zařízení nebo si nastavuješ nové:

1. Nainstaluj Cleonu na nové zařízení.
2. Při spuštění zvol "Obnovit".
3. Zadej svých 24 slov.
4. Cleona obnoví tvou identitu a automaticky osloví tvé dosavadní kontakty.
5. Tvoje kontakty odpoví svými kontaktními údaji, členstvím ve skupinách a
   historií zpráv.

Obnovení probíhá ve třech krocích:
- Nejprve se vrátí tvoje kontakty a skupiny.
- Poté posledních 50 zpráv z každé konverzace.
- Nakonec kompletní historie zpráv.

Stačí, aby byl online jediný z tvých kontaktů, aby obnovení fungovalo.

### Guardian Recovery (důvěryhodné osoby)

Můžeš jmenovat až pět důvěryhodných osob jako "Guardians". Tvůj obnovovací
klíč se přitom rozdělí na pět částí, z nichž každý Guardian obdrží jednu.
K obnovení tvé identity stačí tři z pěti částí.

To znamená: i když ztratíš svou Seed-Phrase, mohou tři z tvých Guardianů
společně obnovit tvůj účet. Žádný jednotlivý Guardian nemá přístup k tvým
datům sám -- vždy jsou potřeba minimálně tři.

Jak nastavit Guardians:
1. Otevři nastavení.
2. Přejdi na "Zabezpečení".
3. Zvol "Guardian Recovery".
4. Vyber pět důvěryhodných kontaktů.

### Proč jsou tvé kontakty tvou zálohou

U běžných messengerů leží tvá data na serverech poskytovatele. U Cleony
žádný server neexistuje -- ale tuto roli přebírají tvoje kontakty. Když
odešleš zprávu, uloží si společné kontakty šifrovanou kopii pro případ, že
je příjemce zrovna offline. Při obnovení ti tvoje kontakty tvá data vrátí
zpět.

To znamená: čím více aktivních kontaktů máš, tím spolehlivější je tvá
záloha. Na úspěšné obnovení stačí jediný kontakt, který je pravidelně
online.

---

## 13. Nastavení

Do nastavení se dostaneš přes ikonu ozubeného kola v pravém horním rohu.

### Upozornění a vyzváněcí tóny

- Vyber si z šesti různých vyzváněcích tónů pro příchozí hovory.
- Nastav si tón pro zprávy.
- Na zařízeních Android můžeš navíc zapnout nebo vypnout vibrace.

### Designy (skiny)

Cleona nabízí deset různých designů: Teal, Ocean, Sunset, Forest, Amethyst,
Fire, Storm, Slate, Gold a Contrast. Design Contrast splňuje nejvyšší
úroveň přístupnosti (WCAG AAA) a je obzvlášť dobře čitelný při omezeném
zraku.

Každá identita může mít vlastní design. Design měníš na stránce
podrobností identity (klepnutím na aktivní záložku identity).

Navíc můžeš v nastavení pod "Vzhled" přepínat mezi světlým, tmavým a
systémovým motivem.

### Změna jazyka

Cleona je dostupná v 33 jazycích, včetně jazyků psaných zprava doleva
(např. arabština, hebrejština). Jazyk změníš v nastavení pod "Jazyk".

### Limit úložiště

Můžeš nastavit, kolik místa na zařízení může Cleona využívat (mezi 100 MB a
2 GB). Jakmile je limit dosažen, starší média se automaticky přesunou
jinam nebo smažou -- textové zprávy zůstávají vždy zachovány.

### Archivace médií

Pokud máš doma síťové úložiště (NAS) nebo sdílenou složku, může tam Cleona
automaticky přesouvat tvá média. Podporovány jsou SMB, SFTP, FTPS a WebDAV.

Jak funguje stupňované ukládání:
- Prvních 30 dní: vše zůstává na zařízení.
- Po 30 dnech: náhledový obrázek zůstává na zařízení, originál se
  archivuje.
- Po 90 dnech: na zařízení zůstane už jen malý náhled.
- Po roce: zůstane už jen zástupný symbol, originál je bezpečně uložen v
  archivu.

Na archivované médium můžeš kdykoli klepnout, aby se stáhlo zpět -- za
předpokladu, že jsi připojen ke své domácí síti. Obzvlášť důležitá média
lze připnout, aby nikdy nebyla přesunuta.

### Přepis hlasových zpráv

Pokud je aktivní, tvé hlasové zprávy se lokálně na tvém zařízení převádějí
na text (pomocí open-source modelu Whisper). Přepsaný text se posílá
spolu s nahrávkou protějšku. Přepis probíhá zcela na tvém zařízení --
žádná data se neposílají do externích služeb.

### Automatické stahování

Můžeš nastavit, od jaké velikosti se mají média stahovat automaticky.
Můžeš si tak nechat například automaticky stahovat obrázky, ale u velkých
videí rozhodovat ručně.

### Propojená zařízení

Svá propojená zařízení spravuj v této části nastavení. Podrobnosti najdeš
v kapitole Multi-Device.

---

## 14. Zabezpečení

### Co znamená postkvantové šifrování?

Dnešní šifrování je založeno na matematických problémech, které jsou pro
běžné počítače extrémně obtížné vyřešit. Kvantové počítače by v budoucnu
mohly některé z těchto problémů řešit rychle. Postkvantové šifrování
používá dodatečné metody, které odolávají i kvantovým počítačům.

Cleona kombinuje oba přístupy: klasické šifrování pro spolehlivost a
postkvantové postupy pro odolnost do budoucna. Jsi tak chráněn zároveň
proti dnešním i budoucím hrozbám.

Pro každou jednotlivou zprávu se vytváří vlastní klíč. I kdyby útočník
prolomil klíč jedné zprávy, nemohl by s ním přečíst žádnou jinou zprávu.

### Proč je absence serveru bezpečnější

U běžných messengerů procházejí tvé zprávy servery poskytovatele. I když
tam mohou být šifrované, poskytovatel má přístup k metadatům (kdo s kým kdy
komunikuje, jak často, odkud) a za určitých okolností je musí na soudní
příkaz vydat.

U Cleony žádný takový centrální bod neexistuje. Tvé zprávy putují přímo ze
zařízení na zařízení. Neexistuje žádné místo, kde by se sbíhala všechna
metadata. Nikdo nemůže na základě jediného datového bodu rekonstruovat tvé
komunikační chování.

### Co se stane, když jsi offline?

Když odešleš zprávu a příjemce je offline:

1. Cleona se nejprve pokusí doručit zprávu přímo.
2. Pokud se to nepodaří, přeposílá se přes společné kontakty.
3. Zároveň se zpráva rozdělí na šifrované kusy a distribuuje na více uzlů
   v síti (podobně jako puzzle o 10 dílcích, z nichž 7 stačí k sestavení
   obrázku).
4. Zpráva se uchovává až 7 dní.

Jakmile se příjemce znovu připojí, zprávy se doručí. Dostaneš potvrzení,
jakmile tvá zpráva dorazí.

### Ochrana proti cenzuře

Pokud tvá síť blokuje standardní způsob spojení (UDP), přepne se Cleona
automaticky na alternativní přenos (TLS), který je obtížnější rozpoznat a
zablokovat. Děje se to transparentně -- nic nastavovat nemusíš.

### Bezpečné uložení klíčů

Na podporovaných platformách ukládá Cleona tvé šifrovací klíče do bezpečné
klíčenky operačního systému (Android Keystore, iOS Keychain, macOS
Keychain). Tam, kde je to dostupné, poskytuje hardwarově podporovanou
ochranu tvých klíčů.

### Šifrování databáze

Všechny tvé zprávy, kontakty a nastavení jsou na tvém zařízení uloženy v
šifrované podobě. I kdyby někdo získal přístup k tvému souborovému systému,
nemohl by bez tvého kryptografického klíče nic přečíst. Tento klíč je
odvozen z tvé identity a existuje pouze na tvém zařízení.

### Uzavřená síť

Cleona funguje jako uzavřená síť. Každý síťový paket je autentizován, takže
se sítě mohou účastnit pouze legitimní zařízení Cleona. To brání tomu, aby
cizí subjekty vpašovali padělané zprávy nebo odposlouchávali síťový
provoz.

---

## 15. Aktualizace softwaru

### Jak získám aktualizace?

Cleonu lze aktualizovat několika způsoby. Cílem je, abys mohl získávat
aktualizace i tehdy, když některé distribuční kanály selžou nebo jsou
zablokovány:

1. **App Store / Play Store:** Pokud sis Cleonu nainstaloval z app storu,
   dostáváš aktualizace obvyklým způsobem přes obchod.
2. **GitHub Releases:** Na stránce projektu na GitHubu najdeš podepsané
   instalační balíčky pro všechny platformy.
3. **Aktualizace v rámci sítě (In-Network):** Pokud má jiný uživatel
   Cleony ve tvé síti již nejnovější verzi, může Cleona získat aktualizaci
   přímo přes síť P2P -- bez externího serveru. Nová verze se přitom
   rozloží na fragmenty s korekcí chyb a rozdistribuuje přes více uzlů.
   Tvé zařízení nasbírá dostatek fragmentů a sestaví aktualizaci dohromady.
   Pravost se ověřuje pomocí podpisu Ed25519 od vývojáře.
4. **Pozvánkové odkazy:** Můžeš vytvářet pozvánkové odkazy, které obsahují
   vše, co nový uživatel potřebuje k instalaci Cleony a připojení k síti.
5. **Fyzický přenos:** V prostředích bez internetu můžeš Cleonu předat
   dalším lidem přes USB flash disk nebo v lokální síti.

### Upozornění na aktualizaci

Když je k dispozici nová aktualizace, zobrazí ti Cleona upozornění na
úvodní obrazovce. Pokud je aktualizace dostupná i přes síť (In-Network
Update), máš možnost stáhnout ji přímo ze sítě.

### Binární distribuce

Ve výchozím nastavení tvé zařízení pomáhá šířit aktualizace dalším
uživatelům v síti. Pokud si to nepřeješ, můžeš tuto funkci vypnout v
nastavení pod "Síť". Využití úložiště pro fragmenty aktualizací je omezené
(5 MB na mobilních zařízeních, 20 MB na desktopových zařízeních) a
pravidelně se čistí.

### Kontrola podpisu

Každá aktualizace je kryptograficky podepsána. Cleona automaticky ověří
podpis, než se aktualizace nainstaluje. Tím je zajištěno, že se přijmou
pouze aktualizace od oficiálního vývojáře -- i když byla aktualizace
získána přes síť P2P.

---

## 16. Časté dotazy

### "Můžu Cleonu používat bez internetu?"

Ne, Cleona potřebuje síťové připojení k odesílání a přijímání zpráv.
Nemusíš však být online zároveň se svým protějškem: zprávy odeslané v
době, kdy je příjemce offline, se dočasně uloží a automaticky doručí,
jakmile jsou obě strany znovu připojeny. V lokální síti (např. ve stejné
WLAN) můžete spolu komunikovat i úplně bez přístupu k internetu.

### "Co když ztratím svou Seed-Phrase?"

Pokud máš nastavené Guardians, mohou tři z pěti důvěryhodných osob
společně obnovit tvůj přístup. Bez Guardianů a bez Seed-Phrase bohužel
neexistuje způsob, jak svou identitu získat zpět. Proto je tak důležité
bezpečně uchovávat těch 24 slov.

### "Může někdo číst mé zprávy?"

Ne. Každá zpráva je šifrována jednorázovým klíčem, který platí pouze pro
tuto jednu zprávu. Zprávu může dešifrovat pouze ty a tvůj protějšek.
Neexistuje žádný centrální server, žádný univerzální klíč a žádný přístup
pro vývojáře. I kdyby zprávu na cestě přeposílalo nějaké zařízení, vidělo
by pouze zašifrovanou změť dat.

### "Proč nepotřebuji telefonní číslo?"

Protože tvá identita je čistě kryptografická. Místo telefonního čísla nebo
e-mailové adresy spojené s tvým skutečným jménem tě identifikuje pár klíčů
vygenerovaný na tvém zařízení. Kontakty přidáváš přes QR kód, NFC nebo
odkaz -- nikoli přes telefonní seznam. To znamená více soukromí, protože
tvůj účet v messengeru není vázán na tvou reálnou identitu.

### "Jak najdu lidi na Cleoně?"

Cleona záměrně nemá vyhledávání kontaktů podle telefonního čísla nebo
jména -- to by byl problém pro soukromí. Místo toho si kontaktní údaje
vyměňuješ přímo: přes QR kód, NFC, odkaz cleona:// nebo ve veřejných
kanálech. Je to jako výměna vizitek místo vyhledávání v telefonním
seznamu.

### "Funguje Cleona i v zahraničí?"

Ano. Dokud máš připojení k internetu, funguje Cleona kdekoli na světě.
Protože neexistuje žádný centrální server, nemůže být služba zablokována
pro konkrétní země. Cleona navíc disponuje ochranou proti cenzuře: pokud
je běžné spojení (UDP) blokováno, přepne se Cleona automaticky na
alternativní přenos (TLS), který je obtížnější rozpoznat a zablokovat.

### "Je Cleona zdarma?"

Ano. Cleona je zdarma a bez reklam. Protože neexistuje centrální server,
nevznikají ani žádné náklady na jeho provoz. V aplikaci pod "Darovat"
najdeš možnost dobrovolně podpořit vývoj.

### "Moje zpráva má symbol hodin -- co to znamená?"

To znamená, že zpráva ještě nebyla doručena. Tvůj protějšek je
pravděpodobně zrovna offline. Jakmile je zpráva doručena, symbol se změní.
Zprávy se uchovávají k doručení až 7 dní.

### "Můžu přejít z WhatsApp na Cleonu?"

Ano, ale své konverzace z WhatsApp nemůžeš přenést. Cleona a WhatsApp jsou
zcela odlišné systémy. Své kontakty musíš do Cleony přidat jednotlivě.
Nejjednodušší je vložit svůj odkaz cleona:// do skupiny na WhatsApp a
požádat ostatní, aby tě tam přidali.

### "Můžu Cleonu používat na více zařízeních současně?"

Ano. Se stejnou identitou můžeš propojit až 5 zařízení. Jedno zařízení je
primární (drží Seed-Phrase) a další zařízení se propojí přes bezpečný
párovací proces. Všechna zařízení sdílejí stejnou identitu, kontakty a
konverzace. Podrobnosti najdeš v kapitole Multi-Device.

### "Jak získám aktualizace, když je app store zablokovaný?"

Cleona umí získávat aktualizace přímo přes síť P2P, aniž by byla odkázána
na app store, webovou stránku nebo stahovací server. Pokud má jiný
uživatel v síti nejnovější verzi, může si tvé zařízení aktualizaci
stáhnout odtud. Pravost se ověřuje digitálním podpisem vývojáře.
Alternativně ti může kontakt aplikaci předat přes pozvánkový odkaz nebo
USB flash disk. Více v kapitole "Aktualizace softwaru".

---

## Pomoc a kontakt

Pokud máš otázky nebo narazíš na problém, aktuální informace najdeš na
webu Cleony a na GitHubu. Protože je Cleona decentralizovaný projekt,
neexistuje klasická zákaznická podpora -- ale aktivní komunita, která ráda
pomůže.

---

*Tato příručka popisuje Cleona Chat verzi 3.1.125. Jednotlivé funkce se
mohou v novějších verzích měnit nebo rozšiřovat.*

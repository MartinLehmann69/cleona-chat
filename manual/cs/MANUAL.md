# Cleona Chat -- Uživatelská příručka

Verze 4.2 | Stav k listopadu 2026

---

## Obsah

1. [Co je Cleona Chat?](#1-co-je-cleona-chat)
2. [První kroky](#2-první-kroky)
3. [Kontakty](#3-kontakty)
4. [Zprávy](#4-zprávy)
5. [Skupiny](#5-skupiny)
6. [Veřejné kanály](#6-veřejné-kanály)
7. [Hovory](#7-hovory)
8. [Kalendář](#8-kalendář)
9. [Ankety](#9-ankety)
10. [Více identit](#10-více-identit)
11. [Více zařízení](#11-více-zařízení)
12. [Obnova](#12-obnova)
13. [Nastavení](#13-nastavení)
14. [Zabezpečení](#14-zabezpečení)
15. [Aktualizace softwaru](#15-aktualizace-softwaru)
16. [Časté otázky](#16-časté-otázky)

---
## 1. Co je Cleona Chat?

### Tvůj messenger, tvá data

Cleona Chat je messenger, který funguje úplně bez centrálního serveru. Tvé
zprávy cestují z tvého zařízení do zařízení tvého protějšku -- bez objížďky
přes sídlo firmy, bez cloudu, bez datacentra. Kdekoliv na cestě pomůže jiné
zařízení, jen předá dál šifrované pakety. Žádná firma nemůže tvé zprávy číst,
ukládat ani předávat dál, protože prostě žádná firma nestojí mezi nimi.

### Žádný účet, žádné telefonní číslo

U Cleony nepotřebuješ k registraci ani telefonní číslo, ani e-mailovou adresu.
Tvoje identita se skládá z kryptografického klíčového páru, který se při prvním
spuštění automaticky vygeneruje na tvém zařízení. To znamená: nikdo tě nemůže
vypátrat přes tvé telefonní číslo nebo e-mailovou adresu, ledaže bys své
kontaktní údaje sám někam předal.

### Šifrování odolné vůči budoucnosti

Cleona používá takzvané post-kvantové šifrování. To znamená: ani budoucí
kvantové počítače by tvé zprávy nedokázaly rozluštit. Nemusíš rozumět
detailům -- důležité je jen, že je tvá komunikace chráněna tak dobře, jak
umožňuje současný stav techniky.

### Jak to funguje bez serveru?

Síť Cleony se skládá jen ze zařízení jejích uživatelů. Každé zařízení je uzel,
žádný uzel není důležitější než jiný a každý zná jen své sousedy. Čtyři věci
činí tuto síť zvláštní:

- **Žádný pevný bod.** V aplikaci nestojí žádná adresa serveru a síť nezávisí
  na žádném jediném uzlu. Neexistuje nic, co by šlo vypnout, aby se vypnula
  Cleona.
- **Okamžitě.** Tvá zpráva vyrazí v okamžiku, kdy ji odešleš. Nečeká na žádný
  takt ani na nic jiného.
- **Krycí provoz při tom.** Tvé zařízení neustále odesílá malé krycí pakety,
  aby zvenku nebylo poznat, kdy opravdu píšeš. Žádná zpráva na tom nezávisí --
  krycí provoz jen běží vedle.
- **Kódy místo jmen.** Kdo zprávu předává dál, vidí jen kód, který se každý den
  mění. Normálně žádný z nich nezná odesílatele i příjemce zároveň; výjimky
  stojí v kapitole 14.

**Tři cesty, všechny najednou.** Když odešleš zprávu, Cleona nezkouší jednu
cestu po druhé, ale všechny vhodné najednou. Jakmile tvůj protějšek potvrdí
příjem, ostatní se přeruší.

1. **Ve stejné síti:** Jste-li ve stejné Wi-Fi, zpráva přejde přímo.
2. **Přes pevné sousedy:** Na internetu předá tvé zařízení zprávu svému pevnému
   sousedovi. Ten ji předá dál pevným sousedům tvého protějšku (až třem
   najednou) a jeden z nich ji doručí.
3. **Schránka:** Je-li tvůj protějšek offline, uloží Cleona zprávu šifrovaně u
   tří sousedů. Tam zůstane až 7 dní. Jakmile se tvůj protějšek vrátí online,
   vyzvedne si ji.

**Jak se dostaneš do sítě?** V aplikaci nestojí žádná adresa serveru. Svůj
vstupní bod dostaneš od svého prvního kontaktu: Jeho pozvánka obsahuje adresy,
přes které tvé zařízení najde své první sousedy. Ve stejné Wi-Fi se zařízení
Cleony najdou i sama. Od té chvíle se tvé zařízení s každým sousedem učí
poznávat další.

### Platformy

Cleona je dostupná pro Android, iOS, macOS, Linux a Windows. Na počítačích a na
Androidu dorazí zprávy a hovory během několika sekund. Na iPhone to platí, dokud
je aplikace otevřená. Není-li otevřená, iOS ji probouzí jen občas a jen krátce;
kdy, to rozhoduje iOS. Cleona pak vyzvedne všechno, co pro tebe bylo schováno, a
ukáže upozornění s počtem na ikoně aplikace. Hovory nedorazí na iPhone se
zavřenou aplikací. To je pravidlo Applu, ne chyba v Cleoně.

---

## 2. První kroky

### Nainstalovat aplikaci

**Android:**
1. Stáhni si soubor APK z webu Cleony nebo z GitHub Releases.
2. Otevři soubor na svém telefonu. Pokud je to potřeba, povol instalaci z
   neznámých zdrojů (Android se tě zeptá automaticky).
3. Klepni na „Instalovat" a počkej, dokud instalace neskončí.

**iOS:**
1. Otevři na svém iPhonu odkaz na pozvánku TestFlight.
2. Klepni na „Instalovat". TestFlight je oficiální cesta Applu, jak distribuovat
   beta aplikace.
3. Po instalaci najdeš Cleonu na domovské obrazovce.

**macOS:**
1. Stáhni si soubor DMG z webu Cleony nebo z GitHub Releases.
2. Otevři DMG a přetáhni Cleonu do složky Aplikace.
3. Při prvním spuštění se macOS možná zeptá, zda chceš otevřít aplikaci od
   identifikovaného vývojáře -- potvrď to.

**Linux (Ubuntu/Debian):**
1. Stáhni si soubor .deb z webu Cleony nebo z GitHub Releases.
2. Nainstaluj dvojklikem nebo v terminálu: `sudo dpkg -i cleona-chat-beta_VERSION_amd64.deb`
3. Spusť Cleonu z nabídky aplikací nebo v terminálu příkazem `cleona-chat-beta`.

**Linux (Fedora/openSUSE):**
1. Stáhni si soubor .rpm z webu Cleony nebo z GitHub Releases.
2. Nainstaluj příkazem: `sudo dnf install cleona-chat-beta-VERSION-1.x86_64.rpm`
3. Spusť Cleonu z nabídky aplikací nebo v terminálu příkazem `cleona-chat-beta`.

**Linux (všechny distribuce -- AppImage):**
1. Stáhni si soubor .AppImage z webu Cleony nebo z GitHub Releases.
2. Udělej soubor spustitelný: pravé tlačítko, vlastnosti, spustitelný, nebo v
   terminálu: `chmod +x cleona-chat-beta-VERSION-x86_64.AppImage`
3. Spusť dvojklikem nebo v terminálu: `./cleona-chat-beta-VERSION-x86_64.AppImage`

Názvy balíčků platí pro betu, která je zatím jedinou zveřejněnou verzí; jmenují
se `cleona-chat-beta`.

**Windows:**
1. Stáhni si instalátor z webu Cleony nebo z GitHub Releases.
2. Spusť instalační soubor a postupuj podle pokynů.
3. Spusť Cleonu z nabídky Start nebo ze zástupce na ploše.

### Vytvořit identitu

Při prvním spuštění Cleona automaticky vytvoří novou identitu pro tebe. Můžeš si
dát zobrazované jméno -- to je jméno, které vidí tví kontakty. Toto jméno lze
kdykoliv změnit.

### Zapsat seed frázi -- to nejdůležitější vůbec

Po vytvoření tvé identity ti Cleona ukáže 24 slov. To je tvá **seed fráze** --
tvůj osobní klíč pro obnovu.

**Zapiš si těchto 24 slov na papír a uschovej je bezpečně.**

Proč je to tak důležité?

- Když se tvůj telefon rozbije, ztratí nebo ho někdo ukradne, můžeš s těmito 24
  slovy obnovit celou svou identitu na novém zařízení.
- Bez seed fráze neexistuje cesta zpět. Neexistuje žádné tlačítko „zapomenuté
  heslo" a žádná podpora, která by ti mohla vrátit tvůj účet -- protože žádný
  účet na serveru vůbec neexistuje. Ani tví kontakty nemohou tvou identitu
  obnovit, ať je jich kolik chce. Druhé zařízení se stejnou identitou přijde
  s pozdější verzí (viz kapitola 11).
- Seed frázi nikdy nikomu nepředávej. Kdo tato slova zná, se může vydávat za
  tebe.

24 slov najdeš později v nastavení pod „Záloha" -> „Zobrazit frázi obnovy",
kdybys si je chtěl ještě jednou opsat. Na Androidu to potvrdíš svým zámkem
obrazovky.

### Přidat první kontakt

Abys s někým mohl chatovat, musíš toho člověka nejprve přidat jako kontakt. K
tomu vede několik cest -- všechny jsou vysvětleny v dalším oddílu.

---

## 3. Kontakty

### Tvá pozvánka

Kontakty v Cleoně vznikají jen přes pozvánku. Tvá pozvánka je tu od prvního
spuštění -- i bez internetu a dřív, než tvé zařízení vůbec našlo souseda. Najdeš
ji na stránce s detaily identity (klepni na své jméno v horním pruhu).

Pozvánka existuje ve dvou formách, které obsahují přesně to samé:

- jako **QR kód**, když tvůj protějšek stojí vedle tebe, a
- jako **textový řádek**, který pošleš e-mailem, SMS nebo přes jiný messenger.

Pozvánka neobsahuje žádné telefonní číslo a žádné jméno z adresáře. Obsahuje tvé
veřejné klíče a adresy, přes které tvůj protějšek dosáhne na tebe a na tvé
sousedy. Pro někoho, kdo si Cleonu právě nainstaloval, je tvá pozvánka proto
také vstupním bodem do sítě.

### Naskenovat QR kód (doporučeno)

Když se potkáte osobně:

1. Ukaž svému protějšku QR kód své pozvánky.
2. Tvůj protějšek klepne na tlačítko plus, vybere „Naskenovat QR kód" a namíří
   kameru na tvou obrazovku. Funguje to i s webkamerou počítače.
3. Požadavek přijde tobě a je **přijat automaticky** -- protože jsi ten kód
   přece právě sám ukázal.

QR kód platí jen jednou: první platný požadavek je přijat, poté je pozvánka
spotřebována. QR kód je nejbezpečnější metoda, protože přesně víte, s kým si
kontakt vyměňujete.

### NFC (přiložit telefony k sobě)

Když obě zařízení podporují NFC:

1. Otevřete u obou funkci přidání kontaktu.
2. Přiložte své telefony zády k sobě.
3. Pozvánka se přenese a přijme se automaticky.

NFC nabízí jako QR kód vysokou míru zabezpečení, protože výměna funguje jen,
když stojíte fyzicky vedle sebe.

### Poslat textový řádek

Když se nemůžete potkat:

1. Otevři svou pozvánku a zkopíruj textový řádek.
2. Pošli ho osobě, která tě má přidat -- e-mailem, SMS nebo přes jiný
   messenger.
3. Druhá osoba vloží řádek v Cleoně do dialogu přidání kontaktu.
4. Požadavek se u tebe objeví pod **„Žádosti"**. Tady se **nepřijímá**
   automaticky: rozhoduješ sám, protože nemůžeš vědět, kdo si řádek cestou ještě
   přečetl.

### Přijmout žádosti o kontakt

Příchozí požadavek ještě kontakt nevytváří. Klade ti otázku a objeví se v tabu
**„Žádosti"**. Tam vidíš jméno a stupeň ověření a můžeš si vybrat:

- **Přijmout** -- teprve teď se z osoby stane tvůj kontakt.
- **Odmítnout** -- požadavek se zahodí.
- **Blokovat** -- osoba ti nemůže posílat další žádosti.

### Nikdy nepoužívat jako pevného souseda

V nabídce kontaktu najdeš přepínač **„Nikdy nepoužívat jako pevného souseda"**
(výchozí: vypnuto). Je-li zapnutý, tento kontakt pro tebe nepředává zprávy dál a
proto se také nedozví, kdy odesíláš nebo přijímáš zprávy. Je to myšleno pro
případ, že ti hrozí nebezpečí z tvého vlastního okolí.

Od neznámých (ani kontakt, ani člen společné skupiny) Cleona kromě takového
požadavku nepustí nic -- žádnou zprávu, žádný hovor, žádný soubor. A ani ten
požadavek projde jen tehdy, když odesílatel předtím vyřešil malou
výpočetní úlohu. To dělá hromadný spam drahým.

### Stupně ověření

Cleona ti ukazuje, jak spolehlivě je identita kontaktu potvrzena:

| Stupeň | Význam |
|-------|-----------|
| Neověřeno | Jste propojeni, ale nic nepotvrzuje, že za tím skutečně stojí správná osoba. |
| Viděno | Výměna klíčů proběhla úspěšně, můžete komunikovat šifrovaně. |
| Ověřeno | Potkali jste se osobně a spojili se přes sken kamerou nebo NFC. |
| Důvěryhodný | Tohoto kontaktu jsi výslovně označil jako důvěryhodného. |

„Ověřeno" existuje jen pro osobní výměnu. Pozvánka, která přišla přes chat nebo
e-mailem, tento stupeň nikdy nedosáhne -- i když obsahuje stejná data.

Změní-li se klíče kontaktu bez oznámení, Cleona ho vrátí na „Neověřeno". To tě
chrání před tím, aby se někdo nepozorovaně vydával za tvůj kontakt.

---
## 4. Zprávy

### Odeslat a přijímat text

Jednoduše napiš svou zprávu do vstupního pole dole a stiskni Enter nebo
tlačítko Odeslat. Tvá zpráva se automaticky zašifruje dřív, než opustí tvé
zařízení.

Příchozí zprávy se objeví v historii chatu.

### Co znamenají značky u tvé zprávy

| Značka | Význam |
|---------|-----------|
| Hodiny | Zpráva je vytvořena, ale ještě ji neunesla žádná cesta. |
| Jeden háček | Zpráva je na cestě. To platí i, zatímco čeká ve schránce na tvého protějška. |
| Dva háčky | Doručeno: Zařízení tvého protějška potvrdilo příjem. |
| Varovný symbol | 14 dní žádná cesta zprávu nenesla. Klepni na ni, abys ji odeslal znovu. |

**Offline není chyba.** Není-li tvůj protějšek dostupný, zpráva zůstává u jednoho
háčku, dokud si ji nevyzvedne -- není ztracena. Nemá-li tvé zařízení samotné
připojení, zpráva zůstává u hodin a vyrazí sama, jakmile je zase nějaká cesta.
Varovný symbol se objeví teprve, když 14 dní nenašla žádnou cestu; tehdy ji
můžeš odeslat znovu.

To platí i pro iPhone se zavřenou aplikací: zpráva čeká ve schránce, dokud iOS
aplikaci na chvíli neprobudí nebo dokud ji tvůj protějšek neotevře. To může trvat
déle než na jiných zařízeních.

Dva háčky existují jen tehdy, když příjemce sám potvrdí příjem. Toto potvrzení o
přijetí je šifrované a podepsané -- nikdo cestou ho nemůže zfalšovat, aby ti
předstíral doručení.

### Odesílat obrázky, videa a soubory

Máš několik možností:

- **Ikona sponky** ve vstupním poli: Klepni na ni, abys vybral soubor, obrázek
  nebo video z galerie nebo ze svého souborového systému.
- **Drag and Drop** (desktop): Přetáhni soubor jednoduše do okna chatu.
- **Vložit ze schránky** (desktop): Zkopíruj obrázek a vlož ho v chatu.

Malé soubory (pod 256 KB) cestují přímo ve zprávě. Větší soubory se rozdělují na
kousky a opatřují se korekcí chyb, takže jednotlivé ztracené kousky nevadí. Jste-
li oba online, streamují se přes souseda; jinak se ukládají u zařízení, která jsou
stále dostupná, dokud si je tvůj protějšek nevyzvedne.

Od 256 KB se tě Cleona zeptá u každého souboru, dřív než ho odešle: Velký
soubor nemůže vzít cestu tvých zpráv. Jeho obsah zůstává šifrovaný a tvůj
protějšek se nedozví tvou internetovou adresu. Přenos je ale zvenku vidět jako
událost a cizí zařízení, které ho předává dál nebo uchovává, vidí, kdo nahrává
a kdo vyzvedává. Tvůj souhlas platí jen pro tento jeden soubor.

### Hlasové zprávy

1. Podrž tlačítko mikrofonu ve vstupním poli.
2. Vyslov svou zprávu.
3. Tlačítko pusť, abys zprávu odeslal.

Je-li na tvém zařízení zapnuté rozpoznávání řeči (viz Nastavení), přepíše se
tvá hlasová zpráva automaticky do textu. Tvůj protějšek pak vidí nahrávku i
přepsaný text.

### Odpovídat na zprávy (citovat)

Když chceš odpovědět na konkrétní zprávu:

1. Otevři nabídku tří teček vedle zprávy.
2. Vyber „Odpovědět".
3. Nad vstupním polem se objeví pruh s citovanou zprávou.
4. Napiš svou odpověď a odešli ji.

Citovaná zpráva se ukáže ve tvé odpovědi, takže je vztah jasný.

### Upravit a mazat zprávy

- **Upravit:** Nabídka tří teček u zprávy, pak „Upravit". Změň text a odešli ho
  znovu. Tvůj protějšek vidí, že zpráva byla upravena. Upravit lze do 15 minut po
  odeslání.
- **Smazat:** Nabídka tří teček u zprávy, pak „Smazat". Zpráva se odstraní u tebe
  i u tvého protějška. Své vlastní zprávy můžeš mazat kdykoliv -- pro mazání
  neexistuje žádný časový rámec.

### Emoji reakce

Místo toho, aby sis psal odpověď, můžeš na zprávu reagovat emoji:

1. Otevři nabídku tří teček nebo zprávu dlouze podrž.
2. Vyber emoji z rychlého výběru nebo otevři výběr emoji pro plný sortiment.
3. Tvá reakce se objeví pod zprávou.

### Kopírovat text

Přes nabídku tří teček u zprávy můžeš text zprávy zkopírovat do schránky.

### Hledat zprávy

Na horním okraji okna chatu najdeš funkci hledání. Zadej hledaný výraz a Cleona
ti ukáže všechny shody v aktuálním chatu. Šipkami můžeš mezi shodami
přeskakovat tam a zpět.

Na úvodní obrazovce je navíc vyhledávací filtr napříč taby, kterým můžeš
prohledat všechny konverzace podle jednoho výrazu.

### Náhled odkazu

Když pošleš odkaz, Cleona automaticky vytvoří náhled (titulek, popis, náhledový
obrázek). Tento náhled vzniká na tvém zařízení a odesílá se s ním -- tvůj
protějšek kvůli tomu nemusí budovat spojení s odkazovaným webem.

Co udělá klepnutí na přijatý odkaz, nastavuješ v nastavení pod „Otevírání
odkazů": „Normálně", „Upřednostnit anonymní okno" (kde zařízení neumí otevřít
anonymní okno, odkaz se otevře normálně) nebo „Pokaždé se zeptat".

---

## 5. Skupiny

### Vytvořit skupinu

1. Přepni na tab „Skupiny".
2. Klepni na tlačítko plus.
3. Dej skupině jméno.
4. Vyber kontakty, které chceš pozvat.
5. Klepni na „Vytvořit".

Pozvané kontakty dostanou oznámení a mohou se ke skupině připojit.

### Jak jsou skupinové zprávy chráněny

Ve skupině s až 16 členy odesílá Cleona každou zprávu každému členovi zvlášť --
vždy šifrovanou jen pro tohoto člena, jako bys každému napsal vlastní zprávu.
Háčky u skupinové zprávy ukazují stav člena, u kterého je nejméně daleko.

Přeroste-li skupina 16 členů, používá společný klíč. Ten se mění každý den a
vytahuje se znovu, když nějaký člen odejde nebo je odebrán; nový člen čte
teprve od svého vstupu. Háčky tam už neukazují stav každého člena, ale to, že
je zpráva uložena v síti. Klesne-li skupina na 12 členů nebo méně, vrací se
zpět k odesílání jednotlivě.

### Obrázky ve skupinách a kanálech

V nastavení skupiny nebo kanálu určuješ pomocí „Vždy načítat obrázky", zda se
obrázky načítají hned, nebo až když na jeden klepneš.

### Pozvat členy

I po vytvoření můžeš pozvat další kontakty:

1. Otevři informace o skupině (nabídka tří teček v přehledu skupin nebo horní
   pruh ve skupinovém chatu).
2. Klepni na „Pozvat".
3. Vyber kontakty, které chceš přidat.

### Role

Každá skupina má tři role:

- **Majitel (Owner):** Má plnou kontrolu. Může přidávat a odebírat členy, jmenovat
  správce a skupinu spravovat. Majitel může také svůj status převést na jiného
  člena.
- **Správce (Admin):** Může odebírat členy a pomáhat se správou.
- **Člen:** Může číst a psát zprávy.

### Opustit skupinu

1. Otevři nabídku tří teček v přehledu skupin.
2. Vyber „Opustit".
3. Potvrď své rozhodnutí.

Když skupinu opustíš, zůstávají tvé dosavadní zprávy pro ostatní členy viditelné.

---

## 6. Veřejné kanály

### Co jsou kanály?

Kanály jsou veřejná diskuzní fóra uvnitř sítě Cleony. Na rozdíl od skupin tu
může každý číst, aniž by musel být pozvaný. Jen majitel a správci mohou
zveřejňovat příspěvky -- odběratelé čtou.

### Najít kanály a připojit se

1. Přepni na tab „Kanály".
2. Otevři záložku „Hledání".
3. Prohledávej dostupné kanály podle jména nebo tématu.
4. Klepni na kanál a pak na „Odebírat".

Kanály lze filtrovat podle jazyka. Některé kanály jsou označeny jako „Nevhodné
pro mládež" -- ty jsou viditelné jen tehdy, když jsi ve svém profilu potvrdil,
že je ti více než 18.

### Vytvořit vlastní kanál

1. Přepni na tab „Kanály".
2. Klepni na tlačítko plus.
3. Zadej jméno kanálu (musí být jedinečné v celé síti).
4. Vyber jazyk a to, zda má být kanál veřejný nebo soukromý.
5. Volitelné: Přidej popis a obrázek.
6. Klepni na „Vytvořit".

U veřejných kanálů můžeš určit, zda má být obsah klasifikován jako „Nevhodné pro
mládež".

### Nahlásit obsah

Všimneš-li si ve veřejném kanálu nevhodného obsahu, můžeš ho nahlásit. Cleona
používá decentralizovaný systém moderování: hlášení hodnotí náhodně vybraní
členové sítě (jakási „porota"). Je-li zjištěn přestupek, dostane kanál
varování. Při opakovaných přestupcích je ve vyhledávacím indexu degradován nebo
zablokován.

### Systémové kanály

Cleona má dva vestavěné systémové kanály:

- **Bug Log:** Když Cleona rozpozná chybu, zeptá se tě, zda chceš odeslat
  hlášení o chybě; předtím přesně vidíš, co se zveřejní. Tato hlášení přistanou
  v kanálu Bug Log, kde si je může komunita prohlédnout. Hlášení nenese žádné
  jméno ani žádný obsah tvých konverzací, nýbrž pseudonym. V betě navíc uvádí
  tvou identifikaci (User-ID), aby se tě vývojáři mohli na něco zeptat. Můžeš
  také ručně odeslat hlášení (s náhledovým dialogem a výslovným souhlasem).
- **Feature Requests:** Zde mohou uživatelé podávat návrhy na funkce a hlasovat o
  stávajících návrzích. Návrhy se řadí podle hlasů.

Každý počítač drží až 25 MB na systémový kanál, každý mobil až 5 MB; je plno,
jde nejdřív to nejstarší -- nikdy to, co už jsi sám viděl.

---
## 7. Hovory

### Zahájit hlasový hovor

1. Otevři chat s kontaktem, kterého chceš zavolat.
2. Klepni na symbol telefonu v horním pruhu.
3. Počkej, dokud tvůj protějšek hovor nepřijme.

Během hovoru vidíš časovou osu, délku hovoru a máš přístup k ztlumení a
reproduktoru.

K zahájení klepni na červené tlačítko závěru hovoru.

Pokud vidíš „Nedostupný", zařízení tvého protějška právě teď není dostupné,
například iPhone se zavřenou aplikací. Napiš místo toho zprávu.

### Zahájit videohovor

1. Otevři chat s kontaktem.
2. Klepni na symbol kamery v horním pruhu.
3. Tvůj obraz se objeví v malém okně, obraz tvého protějška ve velké oblasti.

Během hovoru můžeš přepínat mezi předním a zadním fotoaparátem.

### Příchozí hovory

Když tě někdo volá, objeví se okno s oznámením se jménem volajícího. Můžeš:

- **Přijmout** -- hovor začíná.
- **Odmítnout** -- volající je upozorněn.

Jsi-li právě v hovoru, nový hovor nezvoní; dostaneš místo toho zprávu
„Zmeškaný hovor". Platí totéž pro skupinový hovor, který jsi nepřijal -- zpráva
pak stojí ve skupinovém chatu.

Zavolá-li někdo na jednu z tvých identit, která se právě nezobrazuje, zazvoní
to přesto; obrazovka hovoru říká, která z tvých identit je volaná.

Na iPhone zazvoní jen při otevřené aplikaci. Kdo ti volá, když není otevřená,
vidí po 10 sekundách „Nedostupný". Jakmile aplikaci otevřeš, najdeš zprávu o
zmeškaném hovoru.

### Skupinové hovory

Můžeš také vést skupinové hovory, kterých se současně účastní více osob. Hovor
je organizován přes inteligentní strom předávání, takže nemusí být každý účastník
spojen přímo s každým jiným. Všechny hovory jsou po celou dobu šifrované.

Každý člen skupiny může skupinový hovor zahájit. Dva účastníci, kteří nejsou
navzájem kontakty, nikdy nevidí internetovou adresu toho druhého: Jejich zvuk a
obraz běží přes účastníka, který je kontaktem s oběma. Není-li takový, ti dva
nejsou propojeni a dlaždice říká „Žádný společný kontakt v hovoru". Je-li
nějaké přeposílání vytížené, zvuk zůstává a video tomu páru odpadne.

### Šifrování u hovorů

Všechny hovory se šifrují jednorázovými klíči, které existují jen po dobu hovoru.
Po zavěšení se tyto klíče okamžitě smažou. Nikdo nemůže minulý hovor dodatečně
rozšifrovat.

Upřímně řečeno: Hovory probíhají, kdykoli je to možné, přímo mezi zařízeními,
protože i malé zpoždění u mluvení vadí. Na rozdíl od zpráv proto může tvůj
poskytovatel internetu při hovoru vidět, s jakou internetovou adresou jsi
spojen. Co říkáte, nevidí.

Při hovoru vidí tvůj kontakt také tvou internetovou adresu. Nechceš-li to u
nějakého kontaktu, vypni v jeho nabídce „Povolit hovory" (výchozí: zapnuto).
Vypneš-li to později, zůstane mu adresa, kterou už viděl, známá.

---

## 8. Kalendář

Cleona obsahuje vestavěný kalendář, který funguje šifrovaně a zcela
decentralizovaně -- bez cloudové služby.

### Zobrazení

Kalendář nabízí pět zobrazení: den, týden, měsíc, rok a zobrazení úkolů. Přepínej
mezi nimi přes taby na horním okraji obrazovky kalendáře.

### Vytvářet termíny

Klepni na časový slot nebo použij tlačítko přidat, abys vytvořil nový termín.
Můžeš zadat titulek, datum, čas, místo a poznámky. Termíny se ukládají šifrovaně
na tvém zařízení.

### Opakující se termíny

Termíny se mohou opakovat denně, týdně, měsíčně nebo ročně. Vzor můžeš upravit
(např. každé druhé úterý, každý první v měsíci) a stanovit koncové datum nebo
počet opakování.

### Pozvat kontakty

Při vytváření nebo úpravě termínu můžeš pozvat své kontakty z Cleony. Dostanou
šifrovanou pozvánku do kalendáře a mohou odpovědět přislíbením, odmítnutím nebo
možná. Změny termínu se automaticky odešlou všem pozvaným.

### Zobrazení volno/obsazeno

Své dostupnosti se můžeš sdílet s kontakty, aniž bys prozradil detaily termínu.
Existují tři úrovně soukromí: plné detaily, jen časové bloky nebo skryté.
Můžeš stanovit výchozí a u každého kontaktu ho přepsat.

### Připomínky

Termíny mohou mít připomínky, které před začátkem termínu vyvolají systémové
oznámení. Připomínky můžeš případně uspat.

### Externí synchronizace kalendáře

Cleona se umí synchronizovat s externími kalendářovými službami:

- **CalDAV** -- Připoj se k libovolnému serveru kompatibilnímu s CalDAV
  (Nextcloud, Radicale atd.).
- **Google Kalendář** -- Synchronizace přes Google Calendar API se zabezpečeným
  ověřením OAuth2.
- **Lokální server CalDAV** -- Cleona může na tvém zařízení spustit lokální
  server CalDAV, takže desktopové kalendářové aplikace (Thunderbird, Outlook,
  Apple Kalendář, Evolution) se mohou synchronizovat s tvým kalendářem Cleony.
- **Systémový kalendář Android** -- Termíny z Cleony se mohou přenést do
  vestavěné kalendářové aplikace tvého zařízení s Androidem.
- **Soubory ICS** -- Importuj a exportuj termíny ve standardním formátu
  iCalendar.

### Export do PDF

Každé zobrazení kalendáře (den, týden, měsíc, rok) můžeš vytisknout nebo
exportovat jako dokument PDF.

---

## 9. Ankety

V každém chatu nebo skupině můžeš vytvářet ankety, abys zjišťoval názory nebo
plánoval termíny.

### Typy anket

Cleona podporuje pět druhů anket:

- **Jednoduchý výběr** -- Účastníci vyberou jednu možnost.
- **Vícenásobný výběr** -- Účastníci mohou vybrat více možností.
- **Termínová anketa** -- Najdi termín, který vyhovuje všem. Každý účastník
  označí termíny jako dostupné, možná nebo nedostupné.
- **Škála** -- Ohodnoť něco na číselné škále (např. 1 až 5).
- **Volný text** -- Účastníci napíší vlastní odpověď.

### Vytvořit anketu

Otevři chat a klepni na symbol ankety (nebo použij nabídku příloh). Vyber typ
ankety, sformuluj svou otázku a možnosti a odešli anketu. Objeví se jako zpráva v
chatu.

### Hlasovat

Klepni na anketu, abys odevzdal svůj hlas. Hlas můžeš kdykoliv změnit nebo vzít
zpět.

### Anonymní hlasování

Ankety lze konfigurovat pro anonymní hlasování. Je-li zapnuté, jsou hlasy
kryptograficky anonymní -- nikdo, ani tvůrce ankety, nevidí, kdo pro co hlasoval.
Počet hlasů zůstává přesto viditelný.

### Termínová anketa do kalendáře

Když termínová anketa skončí, lze vítězný termín jedním klepnutím přímo převést
na záznam v kalendáři.

---
## 10. Více identit

### Proč více identit?

Představ si, že chceš oddělit svůj pracovní a soukromý život -- podobně jako se
dvěma různými telefonními čísly, ale bez druhého telefonu. V Cleoně můžeš na
jednom zařízení používat více identit. Každá identita má vlastní jméno, vlastní
profilový obrázek, vlastní kontakty a vlastní konverzace.

### Vytvořit novou identitu

1. V horním pruhu vidíš svou aktuální identitu jako tab.
2. Klepni na znak plus (+) vpravo vedle svých tabů identit.
3. Zadej jméno pro novou identitu.
4. Hotovo -- nová identita je okamžitě aktivní.

### Přepínat mezi identitami

Jednoduše klepni na tab identity v horním pruhu. Přepnutí je okamžité -- žádná
čekací doba, žádné načítání.

### Všechny běží současně

Důležitý bod: Všechny tvé identity jsou současně aktivní. I když se právě
zobrazuješ jako „Pracovní", nadále přijímá tvá identita „Soukromé" zprávy. Nic ti
neunikne, ať máš právě vybranou kteroukoliv identitu.

### Stránka s detaily identity

Když klepneš na tab své právě aktivní identity, otevře se stránka s detaily. Zde
můžeš:

- Zobrazit svůj QR kód pro kontakty.
- Změnit nebo odstranit svůj profilový obrázek.
- Přidat popis profilu.
- Změnit své zobrazované jméno.
- Vybrat design (skin) pro tuto identitu.
- Identitu smazat, pokud ji už nepotřebuješ.

### Smazat identitu

Když identitu smažeš, tví kontakty se o tom dozví. Identita a všechny příslušné
údaje se odstraní z tvého zařízení. Tento proces nelze vrátit zpět.

---

## 11. Více zařízení

### Jedna identita, jedno zařízení -- zatím

Jedna identita dnes běží na jednom zařízení. Druhé zařízení pro tutéž identitu
přijde s pozdější verzí; v nastavení pod „Zařízení" -> „Spravovat zařízení"
proto stojí „Spárovat další zařízení" zatím jako „Zatím nedostupné".

Přijde-li to, platí: Všechna zařízení jsou rovnocenná, neexistuje žádné
hlavní zařízení. Další zařízení nastavíš svými 24 slovy a jedno z tvých
dosavadních zařízení to potvrdí. Nejvýše 5 zařízení.

Zadáš-li dnes na novém zařízení svých 24 slov, stěhuješ se: Identita se na
nové zařízení obnoví a tvé dosavadní zařízení ji poté u sebe odstraní (viz
kapitola 12).

Na více zařízeních můžeš dnes používat různé identity (kapitola 10).

### Rotovat klíče

Máš-li podezření, že se někdo dostal k tvým klíčům, můžeš pod „Spravovat
zařízení" -> „Rotovat klíče" vygenerovat nové klíče. Tví kontakty dostanou
oznámení, tvé otevřené pozvánky se odvolají. Důležité: Potom vytvoří 24 slov
sama už jen staré klíče. Vytvoř proto přímo poté nový balíček pro obnovu;
obnovit se pak dá už jen spolu s tímto balíčkem.

---

## 12. Obnova

### Použít seed frázi

Když ztratíš zařízení nebo zakládáš nové:

1. Nainstaluj Cleonu na nové zařízení.
2. Vyber při startu „Obnovit".
3. Zadej svých 24 slov.
4. Cleona z nich vygeneruje všechny tvé identity zpět -- se stejnými klíči jako
   dřív. Pro tvé kontakty jsi stejný člověk.

### Co se vrátí -- a co ne

Tvoje identita je v těch 24 slovech, tvé kontakty a tvá historie ne. Vrátí se
tvůj přístup do sítě přes **balíček pro obnovu**: Tvé zařízení ukládá v síti
malý, šifrovaný balíček. Jen tvých 24 slov ho umí najít a otevřít. Uvnitř stojí,
co tvé nové zařízení potřebuje, aby znovu dosáhlo na tvé kontakty, a co
mezitím pro tebe v síti leželo. K tomu nemusí být žádný kontakt online.

Dosavadní historii chatu obnova nepřináší zpět.

Balíček pro obnovu žije 7 dní a tvé zařízení ho obnovuje, dokud běží; v
nastavení vidíš, do kdy platí. Neběželo-li žádné z tvých zařízení déle než
7 dní, propadl. Pak 24 slov tvou identitu přesto obnoví, ale své kontakty
musíš pozvat znovu; co mezitím pro tebe v síti leželo, je ztraceno.

### Obnova znamená stěhování

Zjistí-li tvé dosavadní zařízení později, že identita byla obnovena jinde,
odstraní ji u sebe -- i s její historií. Proto: Kdo má tvých 24 slov, může
tímto způsobem tvou identitu stáhnout z tvého zařízení. Dokud nejsou zpět
všechny kontakty, připomíná ti to aplikace; s „Dokončit a obnovit klíče"
obnovu ukončíš sám.

### Co nikdo nemůže obnovit

To je důležité a říkáme to proto zřetelně:

- **Nikdo kromě tebe nemůže obnovit tvou identitu.** Ne vývojář, ne podpora, a
  ani tvé kontakty -- ať je jich kolik chce. Neexistuje žádný hlavní klíč a
  žádná část tvého klíče, která by u jiných ležela v úschově.
- **Ztratíš-li 24 slov a nemáš už žádné zařízení, je tvá identita ztracena.**
  Pak zbývá jen založit novou a znovu pozvat své kontakty.

Nejlepší ochrana: Zapiš si 24 slov na papír a uschovej je bezpečně.

---
## 13. Nastavení

Nastavení otevřeš přes symbol ozubeného kola v horním pravém rohu.

### Oznámení a vyzváněcí tóny

- Vyber jeden ze šesti různých vyzváněcích tónů pro příchozí hovory.
- Nastav tón zpráv.
- Na zařízeních s Androidem můžeš navíc zapnout nebo vypnout vibrace.
- **„Ztlumit vše"** nedovolí na tomto zařízení žádné zprávě zazvonit,
  zavibrovat ani se nahlásit -- pro všechny identity. Hovory dál zvoní.
- **„Dobu klidu"** nastavuješ pro každou identitu s od/do. V této době
  nezvoní, nezavibruje ani se neohlásí žádná zpráva této identity; zprávy
  přesto dorazí.
- **„Oznámení bez obsahu"** (výchozí: vypnuto) ukazuje jen to, že přišla
  zpráva, pozvánka nebo připomínka -- bez odesílatele, jména a textu. Hovory
  dál ukazují jméno.
- Co po startu přijde najednou, to Cleona ohlásí v jednom souhrnném oznámení
  („5 nových zpráv ve 2 konverzacích"); všechno pozdější zvlášť. Klepnutí na
  oznámení o zprávě otevře konverzaci, i v jiné identitě.

### Designy (skiny)

Cleona nabízí deset různých designů: Teal, Ocean, Sunset, Forest, Amethyst,
Fire, Storm, Slate, Gold a Contrast. Design Contrast splňuje nejvyšší úroveň
přístupnosti (WCAG AAA) a je při omezeném zraku obzvlášť dobře čitelný.

Každá identita může mít svůj vlastní design. Design měníš na stránce s detaily
identity (klepni na tab aktivní identity).

Navíc můžeš v nastavení pod „Vzhled" přepínat mezi světlým, tmavým a motivem
systému.

### Změnit jazyk

Cleona je dostupná ve 34 jazycích, včetně jazyků s písmem zprava doleva (např.
arabština, hebrejština). Jazyk změníš v nastavení pod „Jazyk".

### Archivace médií

Máš-li doma síťové úložiště (NAS) nebo sdílenou složku, může Cleona tvá média
automaticky odložit tam. Podporovány jsou SMB, SFTP, FTPS a WebDAV.

Tak funguje stupňovité ukládání:
- Prvních 30 dní: Vše zůstává na tvém zařízení.
- Po 30 dnech: Na zařízení zůstává náhledový obrázek, originál se archivuje.
- Po 90 dnech: Na zařízení zůstává už jen malý náhledový obrázek.
- Po roce: Zůstává už jen zástupný symbol, originál leží bezpečně v archivu.

Na archivované médium můžeš kdykoliv klepnout, abys ho stáhl zpět -- za
předpokladu, že jsi připojen ke své domácí síti. Obzvlášť důležitá média lze
připnout, aby se nikdy neodložila.

Pod „Rozpočet úložiště" určuješ, kolik MB médií zůstane na zařízení (výchozí:
100 MB na mobilu, 2 GB na počítači). Je-li plno, archivuje se nejdřív
nejstarší nepřipnuté médium. Originál se smaže jen tehdy, když bezpečně leží
v archivu -- textové zprávy zůstávají vždy zachovány.

### Přepis pro hlasové zprávy

Je-li zapnuté, převádí se tvé hlasové zprávy lokálně na tvém zařízení na text (s
modelem Whisper s otevřeným zdrojovým kódem). Přepsaný text se společně s
nahrávkou pošle tvému protějškovi. Přepis probíhá kompletně na tvém zařízení --
žádná data nejdou k externím službám.

Který model (tiny, base, small) se stáhne, nastavuješ jednou pro zařízení; jazyk
(automaticky nebo pevně) pro každou identitu.

### Automatické stahování

Můžeš nastavit, od jaké velikosti se mají média automaticky stahovat. Tak můžeš
například nechat obrázky stahovat automaticky, ale u velkých videí rozhodnout
ručně.

### Zařízení

Pod „Zařízení" -> „Spravovat zařízení" vidíš toto zařízení. Spárovat další
zařízení přijde s pozdější verzí (kapitola 11).

### Síť

Cleona nepotřebuje žádné nastavení sítě, aby fungovala. Existují tři síťové
přepínače:

- **Otevření portu na routeru** (výchozí: zapnuto). Cleona požádá tvůj vlastní
  router, aby pro Cleonu otevřel dveře. Funguje-li to, je tvé zařízení pro ostatní
  lépe dostupné a síti pomáhá. Cleona přitom mluví jen s tvým routerem, ne s
  internetem.
- **Veřejné záznamy adres** (výchozí: zapnuto). Má-li tvé zařízení ještě příliš
  málo sousedů, podívá se ve veřejném adresáři (Nostr) po dalších vstupních bodech
  a je-li samo dobře dostupné, sám se tam zapíše. Záznam obsahuje adresu, žádné
  jméno a žádný kontakt. Vypneš-li ho, najde tvé zařízení sousedy už jen přes
  pozvánky, místní síť a sousedy, které už zná.
- **Méně krycích paketů ve Wi-Fi** (výchozí: vypnuto). Ve Wi-Fi nebo na kabelu
  můžeš vypnout prázdné krycí pakety. Pak je tam ale zas vidět, kdy píšeš. V
  mobilních datech tento přepínač neexistuje -- tam Cleona stejně posílá jen jeden
  krycí paket za minutu.

Krycí provoz jako celek nelze vypnout. To je záměr: Jen když běží pořád, neříká
aktivita tvého zařízení nic o tom, zda právě píšeš.

Nad třemi přepínači stojí **Režim úspory dat**: V mobilních datech ho Cleona
navrhuje, ale nikdy ho sama nezapne. Šetří data, ale tvé zařízení je zvenku
snáze poznatelné.

Pod nimi nastavuješ **„Mezipaměť pro média ostatních"**: Tvé zařízení drží
šifrované kousky médií ostatních až 7 dní, aby dorazily k příjemcům (výchozí:
100 MB na mobilu, 1 GB na počítači). Menší velikost uvolní místo okamžitě --
nejdřív nejstarší kousky.

---

## 14. Zabezpečení

### Co znamená post-kvantové šifrování?

Dnešní šifrování vychází z matematických problémů, které jsou pro normální
počítače extrémně těžké na řešení. Kvantové počítače by mohly některé z těchto
problemů v budoucnu rychle vyřešit. Post-kvantové šifrování používá další
postupy, které odolají i kvantovým počítačům.

Cleona kombinuje oba přístupy: klasické šifrování pro spolehlivost a
post-kvantové postupy pro odolnost vůči budoucnosti. Tak jsi chráněn před
dnešními i budoucími hrozbami současně.

Pro každou jednotlivou zprávu se vygeneruje vlastní klíč. I kdyby útočník
rozluštil klíč jedné zprávy, nemohl by s ním přečíst žádnou jinou zprávu.

### Proč je absence serveru bezpečnější

U běžných messengerů tvé zprávy cestují přes servery poskytovatele. I kdyby tam
byly šifrované: Poskytovatel má přístup k metadatům (kdo s kým komunikuje, kdy,
jak často, odkud) a musí je případně na soudní příkaz vydat.

U Cleony takový centrální bod neexistuje. Neexistuje žádné místo, kde by se
scházela všechna metadata, a žádný adresář, ve kterém by šlo dohledat, kdo jsi
nebo koho znáš.

### Kdo vidí, že s někým píšeš?

Šifrování chrání, **co** píšeš. Stejně důležité je, aby se žádný jediný
pozorovatel nedozvěděl, **s kým** a **kdy** píšeš. O to se Cleona postará takto:

- **Na internetu nikdy ne přímo.** Poslalo-li by tvé zařízení zprávu přímo na
  internetovou adresu tvého protějška, mohl by tvůj poskytovatel vidět, s kým
  píšeš. Proto jde zpráva na internetu vždy přes vaše pevné sousedy: tvého a
  toho tvého protějška.
- **Sousedi, kterým věříš.** Tvoji pevní sousedi jsou, kdykoli je to možné,
  zařízení tvých vlastních kontaktů -- až tři, kteří jsou právě zvenku
  dostupní. Padne-li jeden, nastupuje jiný kontakt. Kontakt se nedá koupit
  servery; libovolný uzel v síti ano. Nemáš-li ještě žádný dostupný kontakt,
  vezme Cleona jiného souseda. Tvá pozvánka nikdy nejmenuje žádného z tvých
  kontaktů, aby přes ně nikdo nezedhal adresu přítele.
- **Kódy místo jmen.** Sousedé nevidí jména a žádné identifikátory, jen kód.
  Platí přesně pro vás dva, v jednom směru, na jeden den -- další den je to
  jiný. Tvůj soused ví, odkud paket přichází, ale ne, kam nakonec jde. Soused
  tvého protějška ví, kam jde, ale ne, odkud přišel. Normálně nikdo cestou
  nevidí oba konce.
- **Krycí provoz.** Tvé zařízení neustále odesílá v nepravidelných intervalech
  krycí pakety svým sousedům. Jsou stejně velké jako skutečné pakety, jdou přes
  stejný port a zvenku jsou od nich k nerozeznání. Zda právě píše člověk nebo
  zařízení jen běží, tak není poznat. Tvé zprávy nikdy nečekají na krycí provoz
  -- jdou hned, on jen běží vedle.

**Co krycí provoz stojí:** Ve Wi-Fi asi 13 MB za den. V mobilních datech posílá
Cleona jen jeden krycí paket za minutu, to je asi 1,7 MB za den. Důvodem pro
omezení v mobilních datech není objem dat, ale baterie: Každý paket probudí
rádiový modul.

**Co Cleona nedokáže skrýt** -- upřímně řečeno:

- Žádný **jediný** pozorovatel nevidí, kdo s kým píše -- ani tvůj poskytovatel,
  ani uzly cestou. Kdo ale **oba konce současně** sleduje, například stát, který
  sleduje tvůj přípojný bod i ten tvého protějška, nebo zadrží oba sousedy, může
  v průběhu času přiřadit: Paket odejde u tebe, krátce nato paket přijde u tvého
  protějška. Často se to opakuje, a vzniká spojení.
- Krycí provoz toto přiřazení ztíží, ale nezabrání mu. Skrývá jednotlivé zprávy,
  ne objem: Kdo velmi mnoho odesílá, zvyšuje celkový provoz svého zařízení.
- Kontakt, který je tvým pevným sousedem, se dozví, **kdy** a **kolik**
  odesíláš a přijímáš -- ne s kým a ne co. Hrozí-li nebezpečí z tvého vlastního
  okolí, můžeš každého kontaktu to vyjmout (viz kapitola 3, „Nikdy nepoužívat
  jako pevného souseda").
- Mají-li dva noví uživatelé jen téhož jednoho souseda, jde jejich zpráva přes
  přesně tento uzel a on vidí oba konce. Jakmile má jeden z nich další sousedy,
  je to u konce.
- Tvá pozvánka obsahuje tvé internetové adresy. Kdo má textový řádek, vidí, kde
  jsi online -- dej ho jen lidem, kterým to důvěřuješ.
- Soused, který předává dál, vidí, že si dva kódy vyměňují pakety -- ne, kdo za
  tím stojí, a ne, co je uvnitř.
- Signál běžícího hovoru může, když první soused zrovna neodpovídá, jít přes
  uzel, který vidí oba konce; dozví se, že spolu telefonujete.
- Velký soubor, se kterým jsi souhlasil, vidí počítač, který ho předává dál
  nebo uchovává, na obou koncích (viz kapitola 4).
- U hovorů ochrana před poskytovatelem neplatí a tvůj kontakt vidí tvou
  internetovou adresu (viz kapitola 7).

### Co se stane, když je tvůj protějšek offline?

1. Cleona spustí všechny vhodné cesty současně: ve stejné Wi-Fi přímo, na
   internetu přes dva sousedy -- a navíc schránku.
2. Pro schránku uloží Cleona šifrovanou zprávu u tří sousedů. Jakmile dva
   potvrdí přijetí, platí za uloženou.
3. Cleona k tomu preferuje sousedy, u kterých se tvůj protějšek také
   rozhlíží -- nejprve souseda, kterého jmenuje jeho pozvánka.
4. Zpráva tam čeká až 7 dní. Vrátí-li se tvůj protějšek, vyzvedne si ji a
   potvrdí ti přijetí. Teprve pak vidíš dva háčky.

Schránku může vyprázdnit jen tvůj protějšek: Vyzvednutí a mazání jde jen s
klíčem, který má jen on, a smaže se teprve, když potvrdí přijetí. Sousedé vidí
jen šifrované pakety pod hodnotou, která se každý den mění.

### Cizí se neprobojí

Od někoho, kdo není tvůj kontakt ani člen společné skupiny, Cleona přijme
přesně dvě věci: dotaz na tvé veřejné klíče, dokud je jedna z tvých pozvánek
otevřená, a žádost o kontakt.
Žádost musí nést platnou pozvánku od tebe a odesílatel musí předtím vyřešit
výpočetní úlohu. Všechno ostatní -- zprávy, hovory, soubory -- se zahodí, dřív
než to vůbec dosáhne aplikace. Kdo má jen tištěnou vizitku, tě tedy prostě
nezavolá. Člen společné skupiny tě dosáhne jen v této skupině -- se
skupinovými zprávami a skupinovými hovory, nikdy mimo ni.

### Anticenzura

Cleona je postavena tak, aby se těžko blokovala:

- **Žádný server, žádná pevná adresa.** V aplikaci nestojí žádná adresa, kterou by
  šlo zablokovat, a síť nezávisí na žádném jediném uzlu.
- **Žádný pevný port.** Každé zařízení si při prvním spuštění vybere náhodný
  port. Neexistuje žádné známé číslo portu, na kterém by šlo rozpoznat provoz
  Cleony.
- **Jako náhodná data.** Navázání spojení mezi dvěma zařízeními je tak kódované,
  že ho nelze od náhodných dat rozeznat.
- **Mnoho vstupů.** Každá pozvánka, každý soused a každé zařízení ve stejné Wi-Fi
  je možnou cestou zpět do sítě.

### Bezpečné ukládání klíčů

Na podporovaných platformách ukládá Cleona tvé šifrovací klíče v bezpečném
klíčenku operačního systému (Android Keystore, iOS Keychain, macOS Keychain). Je-
li k dispozici, nabízí to hardwarovou podporu pro tvé klíče.

### Šifrování databáze

Tvé zprávy a konverzace leží v šifrované databázi -- vlastní pro každou
identitu, každá s vlastním klíčem. Šifrovaná není jen databáze samotná, ale i její
dočasné soubory; nic se nezapíše nešifrovaně na disk, ani krátce. Nastavení,
kontakty a média jsou také uloženy šifrovaně.

Klíče se odvozují z tvých 24 slov a existují jen na tvém zařízení. I když se
někdo dostane k tvému zařízení a data si přečte, najde bez těchto klíčů jen
nečitelná data.

Nešifrované je to jen tam, kde sám vydáváš obsah z Cleony ven:
- když uložíš soubor z chatu na své zařízení,
- když tlačítkem snímku obrazovky uložíš obrázek do svých obrázků,
- když něco sdílíš do jiné aplikace,
- když nastavíš archivaci médií (kapitola 13): Archivované originály leží
  nešifrovaně na tvém síťovém úložišti doma, abys je tam mohl otevřít i bez
  Cleony,
- když zrcadlíš termíny do systémového kalendáře Androidu: Tam je mohou číst
  jiné aplikace s přístupem ke kalendáři.

Co takhle vyšlo ven, nemaže se se zprávou a nevyprší s ní.

### Ochrana na obrazovce

Na Androidu, Windows a macOS Cleona nedovolí jiným aplikacím nahrávat
obrazovku. Potřebuješ-li obrázek, použij tlačítko snímku obrazovky v horním
pruhu: Uloží obrázek do tvých obrázků -- nešifrovaný. V konverzaci, ve které
není povoleno přeposílání, snímek obrazovky neexistuje.

---

## 15. Aktualizace softwaru

### Jak dostanu aktualizace?

Cleona se dá aktualizovat různými cestami. Cílem je, aby ses dostal k aktualizacím
i tehdy, když jednotlivé distribuční cesty selžou nebo se zablokují:

1. **App Store / Play Store:** Jakmile Cleona ve store vyjde a nainstaloval
   jsi ji přes store, dostáváš aktualizace jako obvykle přes store. Na iPhonu
   přicházejí aktualizace přes TestFlight.
2. **GitHub Releases:** Na GitHubové stránce projektu najdeš podepsané
   instalační balíčky pro všechny platformy.
3. **Aktualizace přes síť:** Cleona může aktualizaci stáhnout přímo přes síť --
   bez serveru ke stažení. Nová verze je rozdělena na kousky s korekcí chyb, které
   se rozprostřou v síti; část z nich cestuje dokonce i v krycím provozu. Tvé
   zařízení posbírá dost kousků a sestaví aktualizaci. Přenáší se většinou jen
   změna -- pár MB místo celé aplikace. Platí to pro Linux, Windows a Android;
   na macOS stahuješ nové verze z webu nebo z GitHubu.
4. **Pozvánkové odkazy:** Můžeš vytvořit pozvánkové odkazy, které obsahují vše,
   co nový uživatel potřebuje, aby nainstaloval Cleonu a připojil se k síti.
5. **Fyzický přenos:** V prostředích bez internetu můžeš Cleonu předat dál přes
   USB klíčenku nebo v místní síti.

### Jak probíhá aktualizace

1. Cleona automaticky na pozadí posbírá kousky nové aktualizace a sestaví je.
2. Teprve když je aktualizace **kompletní** a její **podpis ověřen**, nabídne ti
   ji Cleona. Nedostaneš tedy nikdy poloviční nebo neověřenou aktualizaci.
3. Klepneš-li na „Instalovat", spustí se instalace bez dalšího dotazu. Na
   Androidu navíc systém ukáže svůj instalační dialog.

Starší verze se nenabízejí -- aktualizace jde vždy jen dopředu. Je-li verze tak
stará, že už nedokáže se sítí spolupracovat, Cleona to zřetelně ukáže a poprosí
tě o aktualizaci.

### Ověření podpisu

Každá aktualizace je dvojitě podepsaná: klasickým a post-kvantovým postupem.
Cleona automaticky ověřuje oba podpisy. Tak je zajištěno, že se přijímají jen
aktualizace od oficiálního vývojáře -- i když aktualizace přišla přes síť od
cizích zařízení. Aktualizace nikdy nevzniká automaticky z vývoje, ale jen tehdy,
když ji vývojář podepíše ručně.

---
## 16. Časté otázky

### „Můžu Cleonu používat bez internetu?"

Cleona potřebuje síťové spojení, ale ne nutně internet: Ve stejné Wi-Fi se
zařízení Cleony najdou sama a můžou si zcela bez přístupu k internetu psát.
Současně online s tvým protějškem být nemusíš: Je offline, čeká zpráva až 7
dní ve schránce u tří sousedů, dokud si ji nevyzvedne.

### „Co když ztratím svou seed frázi?"

Dokud ještě běží nějaké zařízení s tvou identitou, není nic ztraceno -- tam
prostě píšeš dál. Na zařízení, na kterém jsi identitu založil, můžeš 24 slov
zpravidla znovu opsat (viz kapitola 2). Nespoléhej se na to: Nová instalace
tuto kopii odstraní a na Androidu ji zničí i odebrání nebo změna zámku
obrazovky. Nemáš-li ani slova ani zařízení, neexistuje cesta zpět -- ani přes
tvé kontakty, vývojáře nebo kohokoliv jiného. Proto je tak důležité 24 slov
bezpečně uschovat.

### „Může někdo číst moje zprávy?"

Ne. Každá zpráva se šifruje jednorázovým klíčem, který platí jen pro tuto jednu
zprávu. Jen ty a tvůj protějšek můžete zprávu rozšifrovat. Neexistuje žádný
centrální server, žádný hlavní klíč a žádný přístup pro vývojáře. I když nějaké
zařízení na trase zprávu předává dál, vidí jen šifrovanou kaši a kód. Tvůj
soused ví, že paket přichází od tebe, ale ne, komu jde; soused tvého protějška
ví, komu jde, ale ne, od koho.

### „Proč nepotřebuji telefonní číslo?"

Protože tvá identita je čistě kryptografická. Místo telefonního čísla nebo
e-mailové adresy, které jsou svázané s tvým skutečným jménem, tě identifikuje
klíčový pár, který se vygeneroval na tvém zařízení. Kontakty přidáváš přes QR
kód, NFC nebo textový řádek své pozvánky -- ne přes telefonní seznam. To znamená
více soukromí, protože tvůj účet u messengeru není vázaný na tvou skutečnou
identitu.

### „Jak na Cleoně najdu lidi?"

Cleona úmyslně nemá vyhledávání kontaktů podle telefonního čísla nebo jména --
to by byl problém se soukromím. Místo toho si pozvánky vyměňuješ přímo: přes QR
kód, NFC nebo jako textový řádek přes jinou cestu. To je jako vyměňovat si
vizitky místo listování telefonním seznamem.

### „Funguje Cleona i v zahraničí?"

Ano. Dokud máš připojení k internetu, funguje Cleona všude na světě. Protože
neexistuje žádný centrální server a žádná pevná adresa, nedá se služba prostě
pro určité země vypnout. Jak Cleona ztěžuje blokování, stojí v kapitole
„Zabezpečení" pod „Anticenzura". Země, která na hranici blokuje každý neznámý
provoz, však dokáže Cleonu také zastavit.

### „Je Cleona zdarma?"

Ano. Cleona je použitelná zdarma a bez reklamy. Protože neexistuje žádný
centrální server, nevznikají ani žádné náklady na servery pro provoz. V nastavení
pod „Podpoř Cleona" -> „Darovat" můžeš dobrovolně podpořit vývoj.

### „Moje zpráva má jen jeden háček -- co to znamená?"

Zpráva je na cestě, ale tvůj protějšek ještě nepotvrdil přijetí -- většinou
proto, že je právě offline. To není chyba: Zpráva čeká až 7 dní ve schránce.
Jakmile si ji vyzvedne, vidíš dva háčky. Hodiny znamenají, že dosud žádná cesta
zprávu nenesla -- vyrazí sama, jakmile nějaká bude; varovný symbol, že 14 dní
nenašla žádnou cestu a můžeš ji odeslat znovu.

### „Proč zprávy přicházejí pozdě na mém iPhonu?"

iOS nedovoluje aplikacím trvale běžet na pozadí. Cleona je probouzena jen občas a
jen krátce; kdy, to rozhoduje iOS. Pak vyzvedne všechno. Jakmile aplikaci
otevřeš, Cleona vyzvedne, co pro tebe bylo schováno.

### „Můžu přejít z WhatsAppu na Cleonu?"

Ano, ale své chaty z WhatsAppu nepřeneseš. Cleona a WhatsApp jsou zásadně
různé systémy. Své kontakty musíš v Cleoně přidávat jednotlivě. Nejjednodušší
to je, když svým kontaktům pošleš textový řádek své pozvánky. Každou žádost,
která tak dorazí, potvrzuješ sám pod „Žádosti".

### „Můžu Cleonu používat na více zařízeních současně?"

Zatím ne. Druhé zařízení pro tutéž identitu přijde s pozdější verzí
(kapitola 11). Na více zařízeních můžeš dnes používat různé identity.

### „Jak dostanu aktualizace, když je App Store zablokovaný?"

Cleona může stahovat aktualizace přímo přes síť, bez závislosti na App Storu,
webu nebo serveru ke stažení. Má-li jiné zařízení v síti nejnovější verzi, může
tvé zařízení aktualizaci stáhnout od něj. Pravost se ověřuje digitálním podpisem
vývojáře. Alternativně ti může kontakt předat aplikaci přes pozvánkový odkaz
nebo USB klíčenku. Více v kapitole „Aktualizace softwaru".

---

## Pomoc a kontakt

Máš-li otázky nebo narazíš-li na problém, najdeš aktuální informace na webu
Cleony a na GitHubu. Protože je Cleona decentralizovaný projekt, neexistuje
klasická zákaznická podpora -- ale aktivní komunita, která ráda pomůže.

---

*Tato příručka popisuje Cleona Chat verze 4.2. Jednotlivé funkce se v novějších
verzích mohou měnit nebo rozšiřovat.*
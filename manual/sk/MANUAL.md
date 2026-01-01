# Cleona Chat -- Používateľská príručka

Verzia 4.2 | Stav november 2026

---

## Obsah

1. [Čo je Cleona Chat?](#1-čo-je-cleona-chat)
2. [Prvé kroky](#2-prvé-kroky)
3. [Kontakty](#3-kontakty)
4. [Správy](#4-správy)
5. [Skupiny](#5-skupiny)
6. [Verejné kanály](#6-verejné-kanály)
7. [Hovory](#7-hovory)
8. [Kalendár](#8-kalendár)
9. [Ankety](#9-ankety)
10. [Viacero identít](#10-viacero-identít)
11. [Viacero zariadení](#11-viacero-zariadení)
12. [Obnova](#12-obnova)
13. [Nastavenia](#13-nastavenia)
14. [Bezpečnosť](#14-bezpečnosť)
15. [Aktualizácie softvéru](#15-aktualizácie-softvéru)
16. [Časté otázky](#16-časté-otázky)

---

## 1. Čo je Cleona Chat?

### Tvoj messenger, tvoje dáta

Cleona Chat je messenger, ktorý funguje úplne bez centrálneho servera.
Tvoje správy putujú z tvojho zariadenia do zariadenia tvojho protistrana --
bez obchádzania cez sídlo firmy, bez cloudu, bez dátového centra. Keď
sa cestou pridá iné zariadenie, len preposiela šifrované pakety. Žiadny
podnik nedokáže tvoje správy čítať, ukladať ani odovzdávať, pretože
jednoducho medzi nimi žiadny podnik nestojí.

### Žiadny účet, žiadne telefónne číslo

V Cleona nepotrebuješ na prihlásenie ani telefónne číslo, ani e-mailovú
adresu. Tvoja identita pozostáva z kryptografického páru kľúčov, ktorý sa
pri prvom spustení automaticky vygeneruje na tvojom zariadení. To znamená:
nikto ťa nedokáže vypátrať cez tvoje telefónne číslo alebo e-mailovú
adresu, jedine ak sám odovzdáš svoje kontaktné údaje.

### Šifrovanie odolné voči budúcnosti

Cleona používa tzv. post-kvantové šifrovanie. To znamená: ani budúce
kvantové počítače by nedokázali tvoje správy rozlúštiť. Nemusíš
chápať detaily -- dôležité je len, že tvoja komunikácia je podľa aktuálneho
stavu techniky chránená čo najlepšie.

### Ako to funguje bez servera?

Sieť Cleona pozostáva len zo zariadení jej používateľov. Každé zariadenie
je uzol, žiadny uzol nie je dôležitejší ako iný a každý pozná len svojich
susedov. Štyri veci robia túto sieť výnimočnou:

- **Žiadny pevný bod.** V apke nie je žiadna adresa servera a sieť
  nezávisí od žiadneho jediného uzla. Neexistuje nič, čo by sa dalo
  vypnúť, aby sa vypla Cleona.
- **Okamžite.** Tvoja správa vyrazí v momente, keď ju odošleš. Nečaká
  na žiadny takt a na nič iné.
- **Maskovanie popri ceste.** Tvoje zariadenie neustále odosiela malé
  maskovacie pakety, aby zvonku nebolo vidno, kedy skutočne píšeš. Žiadna
  správa na tom nezávisí -- maskovanie len beží popri.
- **Kódy namiesto mien.** Kto prepošle správu, vidí len kód, ktorý sa
  každý deň mení. V normálnom prípade žiadny z nich nepozná odosielateľa
  a príjemcu súčasne; výnimky stoja v kapitole 14.

**Tri cesty, všetky naraz.** Keď odošleš správu, Cleona neskúša jednu
cestu po druhej, ale všetky vhodné naraz. Len čo tvoj protistrana potvrdí
doručenie, ostatné sa prerušia.

1. **V rovnakej sieti:** Ak ste v rovnakej Wi-Fi, správa prejde priamo.
2. **Cez pevných susedov:** Na internete odovzdá tvoje zariadenie správu
   svojmu pevnému susedovi. Ten ju prepošle pevným susedom tvojho
   protistrana (až trom naraz) a jeden z nich ju doručí.
3. **Schránka:** Je tvoj protistrana offline, uloží Cleona správu
   šifrovane u troch susedov. Tam zostane až 7 dní. Keď sa tvoj protistrana
   vráti online, vyzdvihne si ju.

**Ako sa dostaneš do siete?** V apke nie je žiadna adresa servera. Svoj
vstup získaš od svojho prvého kontaktu: Jeho pozvánka obsahuje adresy,
cez ktoré tvoje zariadenie nájde svojich prvých susedov. V rovnakej Wi-Fi
sa zariadenia Cleona nájdu aj samy. Odvtedy sa tvoje zariadenie spoznáva
s každým susedom s ďalšími.

### Platformy

Cleona je dostupná pre Android, iOS, macOS, Linux a Windows. Na počítačoch
a na Androide dorazia správy a hovory do niekoľkých sekúnd. Na iPhone to
platí, kým je aplikácia otvorená. Keď nie je, iOS ju prebúdza len občas a
len krátko; kedy, to rozhoduje iOS. Cleona potom vyzdvihne všetko, čo bolo
pre teba uschované, a zobrazí upozornenie s počtom na ikone aplikácie.
Hovory nedorazia na iPhone so zatvorenou aplikáciou. To je pravidlo Applu,
nie chyba v Cleona.

---

## 2. Prvé kroky

### Nainštalovať apku

**Android:**
1. Stiahni si súbor APK z webovej stránky Cleona alebo z GitHub Releases.
2. Otvor súbor na svojom telefóne. Ak treba, povoľ inštaláciu
   z neznámych zdrojov (Android sa ťa opýta automaticky).
3. Ťukni na „Inštalovať" a počkaj, kým sa inštalácia dokončí.

**iOS:**
1. Otvor pozvánkový odkaz TestFlight na svojom iPhone.
2. Ťukni na „Inštalovať". TestFlight je oficiálny spôsob od Applu na
   distribúciu beta apiek.
3. Po inštalácii nájdeš Cleona na svojej domovskej obrazovke.

**macOS:**
1. Stiahni si súbor DMG z webovej stránky Cleona alebo z GitHub Releases.
2. Otvor DMG a presuň Cleonu do svojho priečinka Aplikácie.
3. Pri prvom spustení sa ťa macOS môže opýtať, či chceš otvoriť apku od
   identifikovaného vývojára -- potvrď to.

**Linux (Ubuntu/Debian):**
1. Stiahni si súbor .deb z webovej stránky Cleona alebo z GitHub Releases.
2. Nainštaluj dvojklikom alebo v termináli: `sudo dpkg -i cleona-chat-beta_VERSION_amd64.deb`
3. Spusti Cleonu z ponuky aplikácií alebo v termináli pomocou `cleona-chat-beta`.

**Linux (Fedora/openSUSE):**
1. Stiahni si súbor .rpm z webovej stránky Cleona alebo z GitHub Releases.
2. Nainštaluj pomocou: `sudo dnf install cleona-chat-beta-VERSION-1.x86_64.rpm`
3. Spusti Cleonu z ponuky aplikácií alebo v termináli pomocou `cleona-chat-beta`.

**Linux (všetky distribúcie -- AppImage):**
1. Stiahni si súbor .AppImage z webovej stránky Cleona alebo z GitHub Releases.
2. Nastav súbor ako spustiteľný: pravý klik, vlastnosti, spustiteľný, alebo
   v termináli: `chmod +x cleona-chat-beta-VERSION-x86_64.AppImage`
3. Spusti dvojklikom alebo v termináli: `./cleona-chat-beta-VERSION-x86_64.AppImage`

Názvy balíkov platia pre betu, ktorá je momentálne jediná uverejnená
podoba; volajú sa `cleona-chat-beta`.

**Windows:**
1. Stiahni si inštalátor z webovej stránky Cleona alebo z GitHub Releases.
2. Spusti inštalačný súbor a riaď sa pokynmi.
3. Spusti Cleonu z ponuky Štart alebo pomocou odkazu na pracovnej ploche.

### Vytvoriť identitu

Pri prvom spustení Cleona automaticky vytvorí novú identitu pre teba.
Môžeš si dať zobrazované meno -- to je meno, ktoré vidia tvoje kontakty.
Toto meno sa dá kedykoľvek zmeniť.

### Zapísať si seed-frázu -- vôbec najdôležitejšie

Po vytvorení tvojej identity ti Cleona ukáže 24 slov. To je tvoja
**seed-fráza** -- tvoj osobný kľúč na obnovu.

**Týchto 24 slov si zapíš na papier a bezpečne ich uschovaj.**

Prečo je to také dôležité?

- Ak sa tvoj telefón pokazí, stratí alebo ho ukradnú, môžeš s tými 24
  slovami obnoviť celú svoju identitu na novom zariadení.
- Bez seed-frázy neexistuje cesta späť. Neexistuje žiadne tlačidlo
  „zabudnuté heslo" a žiadna podpora, ktorá by ti mohla vrátiť tvoj účet
  -- pretože na serveri žiadny účet nie je. Ani tvoje kontakty nedokážu
  obnoviť tvoju identitu, nech je ich koľkokoľvek. Druhé zariadenie s
  rovnakou identitou príde s neskoršou verziou (pozri kapitolu 11).
- Seed-frázu nikdy nedávaj ďalej iným. Kto pozná tieto slová, sa môže
  vydávať za teba.

Tých 24 slov nájdeš neskôr v nastaveniach pod „Záloha" ->
„Zobraziť frázu obnovy", ak si ich chceš ešte raz odčítať. Na Androide
pritom potvrdíš svojím zámkom obrazovky.

### Pridať prvý kontakt

Aby si s niekým mohol chatovať, musíš túto osobu najprv pridať ako kontakt.
Na to existuje viacero ciest -- všetky sú vysvetlené v ďalšej časti.

---

## 3. Kontakty

### Tvoja pozvánka

Kontakty v Cleona vznikajú len cez pozvánku. Tvoja pozvánka je tam od
prvého spustenia -- aj bez internetu a ešte predtým, ako tvoje zariadenie
vôbec našlo suseda. Nájdeš ju na svojej stránke s detailom identity
(Ťukni na vlastné meno v hornom pruhu).

Pozvánka existuje v dvoch formách, ktoré obsahujú presne to isté:

- ako **QR kód**, keď tvoj protistrana stojí pri tebe, a
- ako **riadok textu**, ktorý odošleš e-mailom, SMS alebo cez iný
  messenger.

Pozvánka neobsahuje žiadne telefónne číslo ani meno z nejakého adresára.
Obsahuje tvoje verejné kľúče a adresy, cez ktoré ťa tvoj protistrana a
tvojich susedov dosiahne. Pre niekoho, kto si práve nainštaloval Cleonu,
je tvoja pozvánka preto aj vstupom do siete.

### Naskenovať QR kód (odporúčané)

Keď sa stretnete osobne:

1. Ukáž svojmu protistranovi QR kód svojej pozvánky.
2. Tvoj protistrana Ťukne na tlačidlo s plusom, vyberie „Skenovať QR kód"
   a namiéri kameru na tvoju obrazovku. Funguje to aj s webkamerou
   počítača.
3. Žiadosť príde tebe a **automaticky sa prijme** -- veď si ten kód práve
   sám ukázal.

QR kód platí len raz: prvá platná žiadosť sa prijme, potom je pozvánka
spotrebovaná. QR kód je najbezpečnejšia metóda, lebo pri tom presne viete,
s kým si kontakt vymieňate.

### NFC (priložiť telefóny k sebe)

Keď obe zariadenia podporujú NFC:

1. Otvorte na oboch funkciu pridania kontaktu.
2. Priložte si telefóny chrbtom k chrbtu k sebe.
3. Pozvánka sa prenesie a automaticky prijme.

NFC ponúka ako QR kód vysokú úroveň bezpečnosti, pretože výmena funguje
len vtedy, keď fyzicky stojíte vedľa seba.

### Odoslať riadok textu

Keď sa nemôžete stretnúť:

1. Otvor svoju pozvánku a skopíruj riadok textu.
2. Pošli ho osobe, ktorá ťa má pridať -- e-mailom, SMS alebo cez iný
   messenger.
3. Druhá osoba vloží riadok v Cleone do dialógu pridania kontaktu.
4. Žiadosť sa u teba objaví pod **„Žiadosti"**. Tu sa **nepríjme**
   automaticky: Rozhodneš sám, lebo nemôžeš vedieť, kto si riadok cestou
   ešte prečítal.

### Prijímať žiadosti o kontakt

Prichádzajúca žiadosť ešte nevytvára kontakt. Klade ti otázku a objaví sa
v karte **„Žiadosti"**. Tam vidíš meno a úroveň overenia a môžeš si vybrať:

- **Prijať** -- až teraz sa osoba stane tvojím kontaktom.
- **Odmietnuť** -- žiadosť sa zahodí.
- **Zablokovať** -- osoba ti nedokáže posielať ďalšie žiadosti.

### Nikdy nepoužívať ako pevného suseda

V ponuke kontaktu nájdeš prepínač **„Nikdy nepoužívať ako pevného
suseda"** (predvolené: vypnuté). Keď je zapnutý, tento kontakt pre teba
nepreposiela správy a preto sa ani nedozvie, kedy posielaš alebo
prijímaš správy. Je to myslené pre prípad, že ti hrozí nebezpečenstvo
z vlastného okolia.

Od neznámych (ani kontaktov, ani členov spoločnej skupiny) Cleona
nepustí okrem takej žiadosti nič -- žiadnu správu,
žiadny hovor, žiadny súbor. A ani žiadosť dôjde len vtedy, ak odosielateľ
predtým vyriešil malú výpočtovú úlohu. To robí hromadný spam drahým.

### Úrovne overenia

Cleona ti ukazuje, ako istotne je identita kontaktu potvrdená:

| Úroveň | Význam |
|-------|-----------|
| Neoverené | Ste prepojení, ale nič nepotvrdzuje, že za tým skutočne stojí správna osoba. |
| Videné | Výmena kľúčov prebehla úspešne, môžete komunikovať šifrovane. |
| Overené | Stretnuli ste sa osobne a prepojili ste sa skenom kamery alebo cez NFC. |
| Dôveryhodný | Tento kontakt si výslovne označil ako dôveryhodný. |

„Overené" existuje len pre osobnú výmenu. Pozvánka, ktorá prišla cez chat
alebo e-mailom, túto úroveň nikdy nedosiahne -- aj keď obsahuje rovnaké
dáta.

Zmenia sa kľúče kontaktu bez oznámenia, Cleona ho vráti na „Neoverené".
To ťa chráni predtým, aby sa niekto nepozorovane vydával za tvoj kontakt.

---
## 4. Správy

### Odosielanie a prijímanie textu

Jednoducho napíš svoju správu do vstupného poľa dole a stlač Enter alebo
tlačidlo Odoslať. Tvoja správa sa automaticky zašifruje, skôr ako opustí
tvoje zariadenie.

Prichádzajúce správy sa zobrazia v histórii chatu.

### Čo znamenajú znamenia na tvojej správe

| Znamenie | Význam |
|---------|-----------|
| Hodiny | Správa je vytvorená, ale ešte ju nenesie žiadna cesta. |
| Jedna faha | Správa je na ceste. Platí to aj vtedy, kým v schránke čaká na tvojho protistrana. |
| Dve fahy | Doručené: Zariadenie tvojho protistrana potvrdilo prijatie. |
| Varovné znamenie | 14 dní nenesie správu žiadna cesta. Ťukni naň, aby si ju odoslal znova. |

**Offline nie je chyba.** Keď tvoj protistrana nie je dosiahnuteľný, správa
zostane pri jednej fahe, kým si ju nevyzdvihne -- nie je stratená. Nemá
tvoje vlastné zariadenie pripojenie, správa zostane pri hodinách a vyrazí
sama, len čo zas existuje nejaká cesta. Varovné znamenie sa objaví až
vtedy, keď 14 dní nenašla žiadnu cestu; vtedy ju môžeš odoslať znova.

To platí aj pre iPhone so zatvorenou aplikáciou: správa čaká v schránke,
kým iOS aplikáciu na chvíľu neprebudí alebo kým ju tvoj protistrana
neotvorí. To môže trvať dlhšie ako na iných zariadeniach.

Dve fahy sú len vtedy, keď sám príjemca potvrdí prijatie. Toto potvrdenie
je šifrované a podpísané -- nikto cestou ho nedokáže sfalšovať, aby ti
nasimuloval doručenie.

### Odosielanie obrázkov, videí a súborov

Máš viacero možností:

- **Ikona sponky** vo vstupnom poli: Ťukni na ňu, aby si vybral súbor,
  obrázok alebo video zo svojej galérie alebo zo svojho súborového systému.
- **Drag and Drop** (desktop): Pretiahni súbor jednoducho do okna chatu.
- **Vložiť zo schránky** (desktop): Skopíruj obrázok a vlož ho v chate.

Malé súbory (pod 256 KB) putujú priamo v správe. Väčšie súbory sa rozdelia
na kúsky a opatria sa korekciou chýb, takže jednotlivé stratené kúsky
nič nepokazia. Ak ste obaja online, streamujú sa cez suseda; inak sa
uložia u zariadení, ktoré sú stále dosiahnuteľné, kým si ich tvoj
protistrana vyzdvihne.

Od 256 KB sa ťa Cleona opýta pri každom súbore, skôr než sa odošle: Veľký
súbor nedokáže ísť cestou tvojich správ. Jeho obsah zostáva šifrovaný a
tvoj protistrana sa nedozvie tvoju internetovú adresu. Prenos je ale
zvonku vidieť ako udalosť a cudzie zariadenie, ktoré ho preposiela
alebo uchováva, vidí, kto nahráva a kto vyzdvihuje. Tvoj súhlas platí len
pre tento jeden súbor.

### Hlasové správy

1. Pridrž tlačidlo mikrofónu vo vstupnom poli.
2. Povedz svoju správu.
3. Pustí tlačidlo, aby si správu odoslal.

Ak máš na svojom zariadení aktivované rozpoznávanie reči (pozri Nastavenia),
tvoja hlasová správa sa automaticky prepíše do textu. Tvoj protistrana
potom vidí aj nahrávku, aj prepísaný text.

### Odpovedať na správy (citovať)

Aby si odpovedal na konkrétnu správu:

1. Otvor trojbodkové menu vedľa správy.
2. Vyber „Odpovedať".
3. Nad vstupným poľom sa objaví banner s citovanou správou.
4. Napíš svoju odpoveď a odošli ju.

Citovaná správa sa zobrazí v tvojej odpovedi, takže vzťah je jasný.

### Upravovať a mazať správy

- **Upraviť:** Trojbodkové menu správy, potom „Upraviť". Zmeň text a
  odošli ho znova. Tvoj protistrana vidí, že správa bola upravená. Úprava
  je možná do 15 minút po odoslaní.
- **Zmazať:** Trojbodkové menu správy, potom „Zmazať". Správa sa odstráni
  u teba aj u tvojho protistrana. Svoje vlastné správy môžeš kedykoľvek
  zmazať -- na mazanie neexistuje žiadne časové okno.

### Emoji reakcie

Namiesto písania odpovede môžeš na správu reagovať emoji:

1. Otvor trojbodkové menu alebo správu dlho pridrž.
2. Vyber emoji z rýchleho výberu alebo otvor emoji-výber pre plný výber.
3. Tvoja reakcia sa objaví pod správou.

### Kopírovať text

Cez trojbodkové menu správy môžeš skopírovať text správy do schránky.

### Hľadať správy

Na hornom okraji okna chatu nájdeš funkciu hľadania. Zadaj hľadaný pojem
a Cleona ti ukáže všetky zásahy v aktuálnom chate. Šípkami sa môžeš medzi
zásahmi pohybovať sem a tam.

Na štartovacej stránke je navyše vyhľadávací filter naprieč kartami,
ktorým môžeš prehľadávať všetky konverzácie podľa pojmu.

### Náhľad odkazu

Keď odošleš odkaz, Cleona automaticky vygeneruje náhľad (titul,
popis, náhľadový obrázok). Tento náhľad vytvorí tvoje zariadenie a odošle
sa spolu so správou -- tvoj protistrana preto nemusí nadväzovať spojenie
s odkazovanou webovou stránkou.

Čo urobí ťuk na prijatý odkaz, nastavuješ v nastaveniach pod
„Otváranie odkazov": „Normálne", „Uprednostniť anonymné okno" (kde
zariadenie nedokáže otvoriť anonymné okno, odkaz sa otvorí normálne)
alebo „Pýtať sa vždy".

---

## 5. Skupiny

### Vytvoriť skupinu

1. Prejdi na kartu „Skupiny".
2. Ťukni na tlačidlo s plusom.
3. Daj skupine meno.
4. Vyber kontakty, ktoré chceš pozvať.
5. Ťukni na „Vytvoriť".

Pozvané kontakty dostanú oznámenie a môžu sa pridať do skupiny.

### Ako sú chránené skupinové správy

V skupine s až 16 členmi odošle Cleona každú správu každému členovi
osobitne -- vždy len pre toho člena zašifrovanú, akoby si každému napísal
vlastnú správu. Fahy na skupinovej správe ukazujú stav
člena, ktorý je najmenej ďaleko.

Prejde skupina cez 16 členov, používa spoločný
kľúč. Ten sa mení každý deň a nanovo sa ťahá, keď nejaký člen
odíde alebo sa odstráni; nový člen číta až od svojho vstupu.
Tam fahy neukazujú už stav každého člena, ale to, že
správa je uložená v sieti. Klesne skupina na 12 alebo menej
členov, vráti sa k osobnému odosielaniu.

### Obrázky v skupinách a kanáloch

V nastaveniach skupiny alebo kanála určíš pomocou „Vždy načítať
obrázky", či sa obrázky načítajú hneď, alebo až keď na jeden z nich
ťukneš.

### Pozvať členov

Aj po vytvorení môžeš pozvať ďalšie kontakty:

1. Otvor info skupiny (trojbodkové menu v prehľade skupín alebo horný
   pruh v skupinovom chate).
2. Ťukni na „Pozvať".
3. Vyber kontakty, ktoré chceš pridať.

### Role

Každá skupina má tri role:

- **Vlastník (Owner):** Má plnú kontrolu. Môže pridávať a odstraňovať
  členov, menovať adminov a spravovať skupinu. Vlastník môže svoj status
  preložiť aj na iného člena.
- **Admin:** Môže odstraňovať členov a pomáhať pri správe.
- **Člen:** Môže čítať a písať správy.

### Opustiť skupinu

1. Otvor trojbodkové menu v prehľade skupín.
2. Vyber „Opustiť".
3. Potvrď svoje rozhodnutie.

Keď opustíš skupinu, tvoje doterajšie správy zostanú viditeľné pre ostatných
členov.

---

## 6. Verejné kanály

### Čo sú kanály?

Kanály sú verejné diskusné fóra v rámci siete Cleona. Na rozdiel od skupín
tu môže ktokoľvek čítať, bez toho, aby musel byť pozvaný. Iba vlastník
a admini môžu uverejňovať príspevky -- odberovatelia čítajú.

### Nájsť a pridať sa do kanálov

1. Prejdi na kartu „Kanály".
2. Otvor záložku „Hľadať".
3. Prehľadávaj dostupné kanály podľa mena alebo témy.
4. Ťukni na kanál a potom na „Odoberať".

Kanály sa dajú filtrovať podľa jazyka. Niektoré kanály sú označené ako
„Nie pre mladšie ako 18" -- tie sú viditeľné len vtedy, keď si vo svojom
profile potvrdil, že si starší ako 18 rokov.

### Vytvoriť vlastný kanál

1. Prejdi na kartu „Kanály".
2. Ťukni na tlačidlo s plusom.
3. Zadaj názov kanála (musí byť v celej sieti jedinečný).
4. Vyber jazyk a či má byť kanál verejný alebo súkromný.
5. Voliteľné: Pridaj popis a obrázok.
6. Ťukni na „Vytvoriť".

Pri verejných kanáloch môžeš určiť, či sa obsah klasifikuje ako
„Nie pre mladšie ako 18".

### Nahlásiť obsah

Ak vo verejnom kanále spozoruješ nevhodný obsah, môžeš ho nahlásiť.
Cleona používa decentralizovaný systém moderovania: hlásenia hodnotia
náhodne vybraní členovia siete (akýsi „porotný súd"). Keď sa zistí
porušenie, kanál dostane varovanie. Pri opakovaných porušeniach sa
v vyhľadávacom indexe zníži alebo sa zablokuje.

### Systémové kanály

Cleona má dva vstavané systémové kanály:

- **Bug Log:** Keď Cleona rozpozná chybu, opýta sa ťa, či chceš poslať
  hlásenie o chybe; predtým presne vidíš, čo sa uverejní.
  Tieto hlásenia prídu do kanála Bug
  Log, kde si ich môže prehliadnuť komunita. Hlásenie nenesie žiadne meno
  ani obsah tvojich konverzácií, ale pseudonym. V bete uvádza
  navyše tvoju identifikáciu (User-ID), aby sa ťa vývojári mohli
  opýtať. Môžeš tiež manuálne poslať
  hlásenie z logu (s dialógom náhľadu a výslovným súhlasom).
- **Feature Requests:** Tu môžu používatelia podávať želania na funkcie a
  hlasovať za existujúce návrhy. Návrhy sa zoraďujú podľa hlasov.

Každý počítač drží až 25 MB na systémový kanál, každý telefón až 5 MB;
je to plné, odíde najstaršie ako prvé -- nikdy nie to, čo si už sám videl.

---
## 7. Hovory

### Začať hlasový hovor

1. Otvor chat s kontaktom, ktorému chceš zavolať.
2. Ťukni na ikonu telefónu v hornom pruhu.
3. Počkaj, kým tvoj protistrana prijme hovor.

Počas hovoru vidíš časovú os, dĺžku hovoru a máš prístup k stlmeniu
mikrofónu a reproduktoru.

Pre zloženie ťukni na červené tlačidlo zloženia.

Ak vidíš „Nedostupný", zariadenie tvojho protistrana práve nie je
dosiahnuteľné, napríklad iPhone so zatvorenou aplikáciou. Namiesto toho
napíš správu.

### Začať videohovor

1. Otvor chat s kontaktom.
2. Ťukni na ikonu kamery v hornom pruhu.
3. Tvoj obraz sa objaví v malom okne, obraz tvojho protistrana vo veľkej
   oblasti.

Počas hovoru sa môžeš prepínať medzi prednou a zadnou kamerou.

### Prichádzajúce hovory

Keď ťa niekto volá, objaví sa okno s oznámením s menom volajúceho. Môžeš:

- **Prijať** -- hovor sa začne.
- **Odmietnuť** -- volajúci dostane oznámenie.

Si práve v hovore, nový hovor nezvoní; dostaneš namiesto
toho správu „Zmeškaný hovor". To isté platí pre
skupinový hovor, ktorý si neprijal -- správa vtedy stojí
v skupinovom chate.

Zavolá niekto na jednu z tvojich identít, ktorá sa práve nezobrazuje,
zvoní to napriek tomu; obrazovka hovoru vymenúva, ktorá z tvojich identít
je volaná.

Na iPhone zazvoní len pri otvorenej aplikácii. Kto ti volá, keď nie je
otvorená, vidí po 10 sekundách „Nedostupný". Akonáhle otvoríš aplikáciu,
nájdeš správu o zmeškanom hovore.

### Skupinové hovory

Môžeš viesť aj skupinové hovory, na ktorých sa naraz zúčastňuje viacero
osôb. Hovor sa organizuje cez inteligentný strom prepošľania, takže
nemusí byť každý účastník priamo prepojený s každým iným. Všetky hovory
sú všetkým prešifrované.

Každý člen skupiny môže začať skupinový hovor. Dvaja účastníci, ktorí
nie sú kontaktmi jeden druhého, nikdy nevidia internetovú adresu toho
druhého: Ich zvuk a obraz idú cez účastníka, ktorý je kontaktom s oboma.
Takýto neexistuje, dvaja nie sú prepojení a dlaždička hovorí
„Žiadny spoločný kontakt v hovore". Je prepojenie vyťažené,
zvuk zostáva a video pre túto dvojicu odpadá.

### Šifrovanie pri hovoroch

Všetky hovory sa šifrujú jednorazovými kľúčmi, ktoré existujú len počas
hovoru. Po zložení sa tieto kľúče okamžite vymažu. Nikto nedokáže minulý
hovor dodatočne dešifrovať.

Úprimne povedané: Hovory prebiehajú, kdekoľvek je to možné, priamo medzi
zariadeniami, lebo už malé oneskorenie pri rozprávaní vadí. Na rozdiel
od správ preto môže tvoj poskytovateľ internetu pri hovore vidieť, s
akou internetovou adresou si prepojený. Čo si hovoríte, nevidí.

Pri hovore vidí tvoju internetovú adresu aj tvoj kontakt. Nechceš to
pri nejakom kontakte, vypni v jeho ponuke „Povoliť hovory"
(predvolené: zapnuté). Vypneš to neskôr, adresa, ktorú už videl, mu
ostáva známa.

---

## 8. Kalendár

Cleona obsahuje vstavaný kalendár, ktorý funguje šifrovane a úplne
decentrálne -- bez cloudovej služby.

### Zobrazenia

Kalendár ponúka päť zobrazení: deň, týždeň, mesiac, rok a zobrazenie
úloh. Prepájaj medzi nimi cez karty na hornom okraji obrazovky kalendára.

### Vytváranie termínov

Ťukni na časový slot alebo použi tlačidlo pridania, aby si vytvoril nový
termín. Môžeš zadať titul, dátum, čas, miesto a poznámky. Termíny sa
ukladajú šifrovane na tvojom zariadení.

### Opakujúce sa termíny

Termíny sa môžu opakovať denne, týždenne, mesačne alebo ročne. Môžeš
upraviť vzor (napr. každý druhý utorok, každý prvý v mesiaci) a určiť
dátum ukončenia alebo počet opakovaní.

### Pozvať kontakty

Pri vytváraní alebo úprave termínu môžeš pozvať svoje kontakty Cleona.
Dostanú zašifrovanú pozvánku do kalendára a môžu odpovedať s prísľubom,
odmietnutím alebo „možno". Zmeny v termíne sa automaticky odošlú všetkým
pozvaným.

### Zobrazenie voľný/obsadený

Svoju dostupnosť môžeš zdieľať s kontaktmi, a to bez toho, aby si prezradil
detaily termínu. Existujú tri úrovne ochrany súkromia: plné detaily, len
časové bloky alebo skryté. Môžeš nastaviť predvolené a pre každý kontakt
ho prepísať.

### Pripomenutia

Termíny môžu mať pripomenutia, ktoré pred začiatkom termínu vyvolajú
systémové oznámenie. Pripomenutia môžeš podľa potreby odložiť.

### Externá synchronizácia kalendára

Cleona sa dokáže synchronizovať s externými kalendárovými službami:

- **CalDAV** -- Pripoj sa na akýkoľvek CalDAV-kompatibilný server (Nextcloud,
  Radicale atď.).
- **Google Kalendár** -- Synchronizácia cez Google Calendar API so
  zabezpečenou OAuth2 autentifikáciou.
- **Lokálny CalDAV-server** -- Cleona môže na tvojom zariadení spustiť
  lokálny CalDAV-server, aby desktopové kalendárové apky (Thunderbird,
  Outlook, Apple Kalendár, Evolution) mohli synchronizovať s tvojim
  kalendárom Cleona.
- **Systémový kalendár Android** -- Termíny z Cleony sa dajú preniesť do
  vstavanej apky kalendára tvojho zariadenia Android.
- **Súbory ICS** -- Importuj a exportuj termíny vo formáte
  iCalendar štandard.

### Export do PDF

Každé zobrazenie kalendára (deň, týždeň, mesiac, rok) môžeš vytlačiť
alebo exportovať ako PDF dokument.

---

## 9. Ankety

V každom chate alebo skupine môžeš vytvárať ankety, aby si zisťoval
názory alebo plánoval termíny.

### Typy ankiet

Cleona podporuje päť druhov ankiet:

- **Jednoduchý výber** -- Účastníci si zvolia jednu možnosť.
- **Viacnásobný výber** -- Účastníci si môžu vybrať viacero možností.
- **Anketa na termín** -- Nájdi termín, ktorý vyhovuje všetkým. Každý
  účastník označí termíny ako dostupné, možno alebo nie dostupné.
- **Stupnica** -- Ohodnoť niečo na číselnej stupnici (napr. 1 až 5).
- **Voľný text** -- Účastníci napíšu vlastnú odpoveď.

### Vytvoriť anketu

Otvor chat a Ťukni na ikonu ankety (alebo použi menu príloh). Vyber typ
ankety, sformuluj svoju otázku a možnosti a odošli anketu. Zobrazí sa
ako správa v chate.

### Hlasovanie

Ťukni na anketu, aby si odovzdal svoj hlas. Svoj hlas môžeš kedykoľvek
zmeniť alebo stiahnuť.

### Anonymné hlasovanie

Ankety sa dajú nastaviť pre anonymné hlasovanie. Keď je aktivované, hlasy
sú kryptograficky anonymné -- nik, a ani tvorca ankety, nevidí, kto za čo
hlasoval. Počet hlasov zostane napriek tomu viditeľný.

### Anketa na termín do kalendára

Keď sa anketa na termín uzavrie, víťazný termín sa môže jedným ťukom
priamo previesť na kalendárový záznam.

---
## 10. Viacero identít

### Prečo viacero identít?

Predstav si, že chceš oddeliť svoj pracovný a súkromný život -- podobne
ako s dvoma rôznymi telefónnymi číslami, ale bez druhého telefónu. V
Clone môžeš na jednom zariadení používať viacero identít. Každá identita
má vlastné meno, vlastný profilový obrázok, vlastné kontakty a vlastné
konverzácie.

### Vytvoriť novú identitu

1. V hornom pruhu vidíš svoju aktuálnu identitu ako kartu.
2. Ťukni na znak plusa (+) vpravo od svojich kariet identity.
3. Zadaj meno pre novú identitu.
4. Hotovo -- nová identita je okamžite aktívna.

### Prepínať medzi identitami

Jednoducho Ťukni na kartu identity v hornom pruhu. Prepnutie je okamžité
-- žiadne čakanie, žiadne načítavanie.

### Všetky bežia súčasne

Dôležitý bod: Všetky tvoje identity sú súčasne aktívne. Aj keď sa práve
zobrazuješ ako „Pracovne", tvoja identita „Súkromne" naďalej prijíma
správy. Nič nepremeškáš, nech si si práve vybral akúkoľvek identitu.

### Stránka detailu identity

Keď Ťukneš na kartu svojej práve aktívnej identity, otvorí sa stránka
detailu. Tu môžeš:

- Zobraziť svoj QR kód pre kontakty.
- Zmeniť alebo odstrániť svoj profilový obrázok.
- Pridať popis profilu.
- Zmeniť svoje zobrazované meno.
- Vybrať dizajn (skin) pre túto identitu.
- Zmazať identitu, ak ju už nepotrebuješ.

### Zmazať identitu

Keď zmažeš identitu, tvoje kontakty sa o tom dozvia. Identita a všetky
k nej patriace dáta sa odstránia z tvojho zariadenia. Tento proces sa nedá
vrátiť späť.

---

## 11. Viacero zariadení

### Jedna identita, jedno zariadenie -- zatiaľ

Identita dnes beží na jednom zariadení. Druhé zariadenie pre
rovnakú identitu príde s neskoršou verziou; v nastaveniach
pod „Zariadenia" -> „Spravovať zariadenia" stojí preto
„Spárovať ďalšie zariadenie" ešte ako „Zatiaľ nedostupné".

Keď príde, platí: Všetky zariadenia sú si rovné, neexistuje
žiadne hlavné zariadenie. Ďalšie zariadenie nastavíš so svojimi 24 slovami
a jedno z tvojich doterajších zariadení dáva súhlas. Najviac 5 zariadení.

Zadáš dnes na novom zariadení svojich 24 slov, presťahuješ sa: Identita
sa obnoví na nové zariadenie a tvoje doterajšie
zariadenie ju potom odstráni u seba (pozri kapitolu 12).

Na viacerých zariadeniach môžeš dnes používať rôzne identity
(kapitola 10).

### Rotovať kľúče identity

Predpokladáš, že sa niekto dostal k tvojim kľúčom, môžeš pod
„Spravovať zariadenia" -> „Rotovať kľúče" vygenerovať nové kľúče.
Tvoje kontakty dostanú oznámenie, tvoje otvorené pozvánky sa
zrušia. Dôležité: Potom samotných 24 slov obnoví už len staré
kľúče. Vytvor preto hneď potom nový balík na obnovu;
obnoviť sa dá potom už len spolu s týmto balíkom.

---

## 12. Obnova

### Použiť seed-frázu

Keď stratíš svoje zariadenie alebo nastavuješ nové:

1. Nainštaluj Cleonu na nové zariadenie.
2. Vyber pri štarte „Obnoviť".
3. Zadaj svojich 24 slov.
4. Cleona z nich znovu vygeneruje všetky tvoje identity -- s rovnakými
   kľúčmi ako predtým. Pre tvoje kontakty si rovnaký človek.

### Čo sa vráti -- a čo nie

Tvoja identita je v 24 slovách, tvoje kontakty a tvoja história
nie. Vráti sa tvoj prístup do siete cez **balík na obnovu**: Tvoje
zariadenie uloží v sieti malý, šifrovaný balík. Len tvojich 24
slov ho dokáže nájsť a otvoriť. Vnútri stojí, čo tvoje nové zariadenie
potrebuje, aby znova dosiahlo tvoje kontakty, a čo medzitým
ležalo v sieti pre teba. Pre to nemusí byť žiadny kontakt online.

Doterajšiu históriu chatu obnova späť neprinesie.

Balík na obnovu žije 7 dní a tvoje zariadenie ho obnovuje, kým
beží; v nastaveniach vidíš, do kedy platí. Nebehlo viac ako
7 dní žiadne z tvojich zariadení, vypršal. Vtedy tvojich
24 slov napriek tomu obnoví tvoju identitu, ale svoje kontakty musíš
pozvať nanovo; čo medzitým ležalo v sieti pre teba, je stratené.

### Obnoviť znamená presťahovať sa

Zistí neskôr tvoje doterajšie zariadenie, že identita bola inde
obnovená, odstráni si ju u seba -- s jej históriou.
Preto: Kto má tvojich 24 slov, vie takto zobrať tvoju identitu
z tvojho zariadenia. Kým sa nevrátia všetky kontakty, pripomína ti to
apka; s „Dokončiť a obnoviť kľúče" ukončíš obnovu
sám.

### Čo nedokáže obnoviť nikto

To je dôležité a preto to hovoríme jasne:

- **Nikto okrem teba nedokáže obnoviť tvoju identitu.** Ani vývojár,
  ani podpora, a ani tvoje kontakty -- nech je ich koľkokoľvek. Neexistuje
  žiadny hlavný kľúč ani žiadna časť tvojho kľúča, ktorá by bola zložená
  u iných.
- **Ak si stratil 24 slov a nemáš už žiadne zariadenie, tvoja identita
  je stratená.** Potom zostáva len vytvoriť novú a znovu pozvať svoje
  kontakty.

Najlepšia ochrana: Zapíš si 24 slov na papier a bezpečne ich uschovaj.

---
## 13. Nastavenia

Nastavenia otvoríš cez ikonu ozubeného kolieska v hornej pravej rohovke.

### Oznámenia a zvonenia

- Vyber si z šiestich rôznych zvonení pre prichádzajúce hovory.
- Nastav si tón správ.
- Na zariadeniach Android môžeš navyše aktivovať alebo deaktivovať
  vibráciu.
- **„Stlmiť všetko"** nenechá na tomto zariadení už žiadnu správu
  zvoniť, vibrovať ani sa hlásiť -- pre všetky identity. Hovory
  zvonia ďalej.
- **„Čas pokoja"** nastavuješ pre každú identitu s Od/Do. V tomto čase
  nezvonia, nevibrujú ani sa nehlásia žiadne správy tejto identity; správy
  prídu napriek tomu.
- **„Oznámenia bez obsahu"** (predvolené: vypnuté) ukazuje len to, že prišla
  správa, pozvánka alebo pripomenutie -- bez odosielateľa, mena
  a textu. Hovory naďalej ukazujú meno.
- Čo po štarte naraz príde, oznámi Cleona v súhrnnom oznámení
  („5 nových správ v 2 konverzáciách"); všetko neskoršie jednotlivo. Ťuk
  na oznámenie správy otvorí konverzáciu, aj v inej
  identite.

### Dizajny (skiny)

Cleona ponúka desať rôznych dizajnov: Teal, Ocean, Sunset, Forest,
Amethyst, Fire, Storm, Slate, Gold a Contrast. Dizajn Contrast spĺňa
najvyššiu úroveň prístupnosti (WCAG AAA) a pri obmedzenom zraku je
obzvlášť dobre čitateľný.

Každá identita môže mať vlastný dizajn. Dizajn zmeníš na stránke detailu
identity (Ťukni na aktívnu kartu identity).

Navyše sa môžeš v nastaveniach pod „Vzhľad" prepájať medzi svetlým,
tmavým a motívom systému.

### Zmeniť jazyk

Cleona je dostupná v 34 jazykoch, vrátane jazykov s písmom sprava doľava
(napr. arabčina, hebrejčina). Zmeň jazyk v nastaveniach pod „Jazyk".

### Archivácia médií

Ak máš doma sieťové úložisko (NAS) alebo zdieľaný priečinok, môže Cleona
automaticky presúvať svoje médiá tam. Podporované sú SMB, SFTP, FTPS
a WebDAV.

Takto funguje stupňovité ukladanie:
- Prvých 30 dní: Všetko zostane na tvojom zariadení.
- Po 30 dňoch: Na zariadení zostane náhľadový obrázok, originál sa
  archivuje.
- Po 90 dňoch: Na zariadení zostane len malý náhľadový obrázok.
- Po roku: Zostane len zástupný symbol, originál leží bezpečne v archíve.

Kedykoľvek môžeš Ťuknúť na archivované médium, aby si ho vrátil -- za
predpokladu, že si pripojený na svoju domácu sieť. Obzvlášť dôležité médiá
sa dajú pripnúť, aby sa nikdy nepresunuli.

Pod „Rozpočet úložiska" určuješ, koľko MB médií zostáva na zariadení
(predvolené: 100 MB na telefóne, 2 GB na počítači). Je to plné,
archivuje sa najstaršie nepripnuté médium ako prvé. Originál sa vymaže
len vtedy, keď bezpečne leží v archíve -- textové správy zostanú vždy
zachované.

### Prepis pre hlasové správy

Ak je aktivované, tvoje hlasové správy sa lokálne na tvojom zariadení
prepoja do textu (modelom Whisper s otvoreným zdrojom). Prepísaný text
sa spolu s nahrávkou odošle tvojmu protistranovi. Prepis sa deje úplne
na tvojom zariadení -- žiadne dáta nejdú na externé služby.

Ktorý model (tiny, base, small) sa stiahne, nastavuješ raz
pre zariadenie; jazyk (automaticky alebo stanovený) pre každú identitu.

### Automatické sťahovanie

Môžeš nastaviť, od akej veľkosti sa majú médiá automaticky sťahovať.
Tak môžeš napríklad obrázky automaticky načítať, ale pri veľkých videách
sa rozhodnúť manuálne.

### Zariadenia

Pod „Zariadenia" -> „Spravovať zariadenia" vidíš toto zariadenie. Spárovať
ďalšie zariadenie príde s neskoršou verziou (kapitola 11).

### Sieť

Cleona nepotrebuje na fungovanie žiadne nastavenia siete. Existujú
tri sieťové prepínače:

- **Povolenie portu na routeri** (predvolené: zapnuté). Cleona poprosí svoj
  vlastný router, aby otvoril dvere pre Cleonu. Ak to vyjde, je tvoje
  zariadenie pre iných lepšie dosiahnuteľné a pomáha sieti. Cleona pritom
  rozpráva len so svojím routerom, nie s internetom.
- **Verejné záznamy adries** (predvolené: zapnuté). Ak má tvoje zariadenie
  ešte príliš málo susedov, pozrie sa vo verejnom adresári (Nostr) po
  ďalších vstupných bodoch a ak je samé dobre dosiahnuteľné, zapíše sa tam.
  Záznam obsahuje adresu, žiadne meno a žiadny kontakt. Keď ho vypneš,
  nachádza tvoje zariadenie susedov len cez pozvánky, lokálnu sieť a
  susedov, ktorých už pozná.
- **Menej maskovacích paketov vo Wi-Fi** (predvolené: vypnuté). Vo Wi-Fi
  alebo na kábli môžeš vypnúť prázdne maskovacie pakety. Vtedy je tam
  ale znova vidno, kedy píšeš. V mobilných dátach tento prepínač neexistuje
  -- tam Cleona aj tak posiela len jeden maskovací paket za minútu.

Maskovací tok ako celok sa nedá vypnúť. To je zámer: Len keď beží vždy,
nehlási aktivita tvojho zariadenia nič o tom, či práve píšeš.

Nad troma prepínačmi stojí **režim úspory dát**: V mobilných dátach ti ho
Cleona navrhne, nikdy si ho ale sama nezapne. Šetrí dáta, za to je
tvoje zariadenie zvonku ľahšie spoznateľné.

Pod nimi nastavuješ **„Vyrovnávaciu pamäť pre médiá iných"**: Tvoje
zariadenie drží šifrované kúsky médií iných až 7 dní, aby
dosiahli svojich príjemcov (predvolené: 100 MB na telefóne, 1 GB na
počítači). Menšia veľkosť uvoľní miesto okamžite -- najstaršie
kúsky ako prvé.

---

## 14. Bezpečnosť

### Čo znamená post-kvantové šifrovanie?

Dnešné šifrovanie je založené na matematických problémoch, ktoré sú pre
normálne počítače extrémne ťažké na riešenie. Kvantové počítače by
mohli niektoré z týchto problémov v budúcnosti rýchlo vyriešiť.
Post-kvantové šifrovanie používa prídavné postupy, ktoré odolajú aj
kvantovým počítačom.

Cleona kombinuje oba prístupy: klasické šifrovanie pre spoľahlivosť a
post-kvantové postupy pre bezpečnosť do budúcnosti. Tak si chránený
súčasne proti dnešným aj budúcim hrozbám.

Pre každú jednu správu sa vygeneruje vlastný kľúč. Aj keby útočník
rozlúskol kľúč jednej správy, nedokázal by pomocou neho prečítať žiadnu
inú správu.

### Prečo je žiadny server bezpečnejší

Pri konvenčných messengeroch prechádzajú tvoje správy cez servery
poskytovateľa. Aj keby tam boli šifrované: Poskytovateľ má prístup k
metadátam (kto komunikuje kedy s kým, ako často, odkiaľ) a za určitých
okolností ich musí na sudické nariadenie vydať.

Pri Clone neexistuje žiadny takýto centrálny bod. Neexistuje miesto, kde
sa schádzajú všetky metadáta, a žiadny adresár, v ktorom by sa dalo
nahliadnuť, kto si alebo koho poznáš.

### Kto vidí, že s niekým píšeš?

Šifrovanie chráni, **čo** píšeš. Rovnako dôležité je, že sa jediný
pozorovateľ nedozvie, **s kým** a **kedy** píšeš. O to sa Cleona postará takto:

- **Na internete nikdy priamo.** Keby tvoje zariadenie poslalo správu
  priamo na internetovú adresu tvojho protistrana, mohol by tvoj
  poskytovateľ vidieť, s kým píšeš. Preto na internete vždy ide správa cez
  vašich pevných susedov: tvojho a tých tvojho protistrana.
- **Susedia, ktorým dôveruješ.** Tvojich pevných susedov sú, kdekoľvek je
  to možné, zariadenia tvojich vlastných kontaktov -- až tri, ktoré sú
  práve zvonku dosiahnuteľné. Vypadne jeden, posunie sa doľava iný kontakt.
  Kontakt sa nedá kúpiť so servermi; ľubovoľný uzol v sieti áno. Ak ešte
  nemáš žiadny dosiahnuteľný kontakt, vezme Cleona iného suseda. Tvoja
  pozvánka nikdy neomenie žiadneho z tvojich kontaktov, aby cez nich nikto
  nezistil adresu priateľa.
- **Kódy namiesto mien.** Susedia nevidia mená ani žiadne identifikátory,
  ale len kód. Platí presne pre vás oboch, v jednom smere, pre jeden deň
  -- na druhý deň je to iný. Tvoj sused vie, odkiaľ paket prichádza, ale
  nie, kam na konci ide. Sused tvojho protistrana vie, kam ide, ale nie,
  odkiaľ prišiel. V normálnom prípade nikto cestou nevidí oba konce.
- **Maskovací tok.** Tvoje zariadenie neustále, v nepravidelných
  intervaloch, odosiela maskovacie pakety svojim susedom. Sú rovnako
  veľké ako skutočné pakety, idú cez rovnaký port a zvonku sa od nich
  nedajú odlíšiť. Či práve píše človek alebo len beží zariadenie, tým nie
  je rozoznateľné. Tvoje správy nikdy nečakajú na maskovací tok -- idú
  okamžite, on len beží popri.

**Čo maskovací tok stojí:** Vo Wi-Fi zhruba 13 MB za deň. V mobilných
dátach Cleona posiela len jeden maskovací paket za minútu, to je asi 1,7 MB
za deň. Dôvodom pre spomalenie v mobilných dátach nie je množstvo dát,
ale batéria: Každý paket prebudí rádiový modem.

**Čo Cleona nedokáže skryť** -- úprimne povedané:

- Žiadny **jediný** pozorovateľ nevidí, kto s kým píše -- ani tvoj
  poskytovateľ, ani uzly cestou. Kto ale **oba konce súčasne** sleduje,
  napríklad štát, ktorý pozoruje tvoj prípojný bod a ten tvojho protistrana,
  alebo stavia oboch susedov, môže v priebehu času priradiť: Paket von u
  teba, krátko na to paket dnu u tvojho protistrana. Často sa opakujúc,
  dá to spojenie.
- Maskovací tok sťažuje toto priradenie, no nezabraňuje mu. Skrýva
  jednotlivé správy, nie množstvo: Kto veľmi veľa odosiela, zvyšuje celkovú
  prevádzku svojho zariadenia.
- Kontakt, ktorý je tvojím pevným susedom, sa dozvie, **kedy** a **koľko**
  odosielaš a prijímaš -- nie s kým a nie čo. Ak hrozí nebezpečenstvo z
  tvojho vlastného okolia, môžeš vyňať každý kontakt (pozri kapitolu 3,
  „Nikdy nepoužívať ako pevného suseda").
- Ak majú dvaja noví používatelia len toho istého jedného suseda, ide ich
  správa cez presne tento uzol a on vidí oba konce. Len čo má jeden z
  nich ďalších susedov, je to koniec.
- Tvoja pozvánka obsahuje tvoje internetové adresy. Kto má riadok textu,
  vidí, kde si online -- daj ho len ľudom, ktorým to dôveruješ.
- Sused, ktorý preposiela, vidí, že si dva kódy vymieňajú pakety -- nie,
  kto za tým stojí, a nie, čo je vnútri.
- Signál bežiaceho hovoru môže, keď prvý sused práve
  neodpovedá, ísť cez uzol, ktorý vidí oba konce; ten sa
  dozvie, že spolu telefonujete.
- Veľký súbor, ktorému si dal súhlas, vidí počítač, ktorý ho
  preposiela alebo uchováva, na oboch koncoch (pozri kapitolu 4).
- Pri hovoroch neplatí ochrana pred poskytovateľom a tvoj kontakt vidí
  tvoju internetovú adresu (pozri kapitolu 7).

### Čo sa stane, keď je tvoj protistrana offline?

1. Cleona naraz spustí všetky vhodné cesty: v rovnakej Wi-Fi priamo,
   na internete cez dvoch susedov -- a navyše schránku.
2. Pre schránku uloží Cleona šifrovanú správu u troch susedov. Len čo dvaja
   potvrdia prijatie, platí ako uložená.
3. Cleona si preto vyberá predovšetkým susedov, u ktorých tvoj protistrana
   aj nahliada -- najprv suseda, ktorého vymenuje jeho pozvánka.
4. Správa tam čaká až 7 dní. Vráti sa tvoj protistrana, vyzdvihne si ju
   a potvrdí ti prijatie. Až vtedy vidíš dve fahy.

Schránku môže vyprázdniť len tvoj protistrana: Vyzdvihnutie a zmazanie ide
len s kľúčom, ktorý má len on, a vymaže sa až keď potvrdí prijatie.
Susedia vidia len šifrované pakety pod hodnotou, ktorá sa každý deň mení.

### Cudzí sa nedostanú cez

Od niekoho, kto nie je ani tvojím kontaktom, ani členom spoločnej skupiny,
príjme Cleona presne dve veci:
otázku po tvojich verejných kľúčoch, kým je jedna z tvojich pozvánok
otvorená, a žiadosť o kontakt. Žiadosť musí niesť platnú pozvánku od teba
a odosielateľ musel predtým vyriešiť výpočtovú úlohu. Všetko iné -- správy,
hovory, súbory -- sa zahodí, skôr než to vôbec dosiahne apku. Kto má len
tvoju vytlačenú vizitku, ťa teda nemôže jednoducho zavolať. Člen spoločnej
skupiny ťa dosiahne len v tejto skupine -- so skupinovými správami a
skupinovými hovormi, nikdy jednotlivo.

### Anticenzúra

Cleona je stavaná tak, aby sa dala ťažko zablokovať:

- **Žiadny server, žiadna pevná adresa.** V apke nie je žiadna adresa,
  ktorá by sa dala zablokovať, a sieť nezávisí od žiadneho jediného uzla.
- **Žiadny pevný port.** Každé zariadenie si pri prvom spustení vyberie
  náhodný port. Neexistuje žiadne známe číslo portu, na ktorom by sa dal
  rozpoznať prenos Cleony.
- **Ako náhodné dáta.** Nadväzovanie spojenia medzi dvoma zariadeniami je
  kódované tak, že sa od náhodných dát nedá odlíšiť.
- **Mnoho vstupov.** Každá pozvánka, každý sused a každé zariadenie v
  rovnakej Wi-Fi je možná cesta späť do siete.

### Bezpečné ukladanie kľúčov

Na podporovaných platformách ukladá Cleona svoje šifrovacie kľúče v
bezpečnom kľúčenke operačného systému (Android Keystore, iOS Keychain,
macOS Keychain). Kde je to dostupné, ponúka to hardvérom chránenú ochranu
pre tvoje kľúče.

### Šifrovanie databázy

Tvoje správy a konverzácie ležia v šifrovanej databáze -- vlastná pre
každú identitu, každá s vlastným kľúčom. Šifrovaná nie je len samotná
databáza, ale aj jej dočasné súbory; nič sa nezapíše nezašifrovane na disk,
ani krátkodobo. Nastavenia, kontakty a médiá sú tiež uložené šifrovane.

Kľúče sa odvádzajú z tvojich 24 slov a existujú len na tvojom zariadení.
Aj keď sa niekto dostane k tvojmu zariadeniu a prečíta dáta, nájde bez
týchto kľúčov len nečitateľné dáta.

Nezašifrované je to len tam, kde sám vyvedieš obsah z Cleony:
- keď uložíš súbor z chatu na svoje zariadenie,
- keď tlačidlom na snímku obrazovky uložíš obrázok do svojich obrázkov,
- keď niečo zdieľaš do inej apky,
- keď si nastavíš archiváciu médií (kapitola 13): Archivované originály
  ležia nezašifrovane na tvojom sieťovom úložisku doma, aby si ich tam
  mohol otvoriť aj bez Cleony,
- keď zrkadlíš termíny do systémového kalendára Android: Tam ich môžu
  prečítať iné apky s prístupom ku kalendáru.

Čo takto odišlo z Cleony, nemaže sa spolu so správou a nevyprší
spolu s ňou.

### Ochrana na obrazovke

Na Androide, Windows a macOS Cleona nedovolí iným apkám nahrávať obrazovku.
Potrebuješ obrázok, použi tlačidlo na snímku obrazovky v hornom pruhu:
Uloží obrázok do tvojich obrázkov -- nezašifrovaný. V konverzácii, v ktorej
nie je povolené preposielanie, neexistuje snímka obrazovky.

---

## 15. Aktualizácie softvéru

### Ako dostanem aktualizácie?

Cleona sa dá aktualizovať rôznymi cestami. Cieľom je, aby si mohol dostať
aktualizácie aj vtedy, keď jednotlivé distribučné cesty zlyhajú alebo
sa zablokujú:

1. **App Store / Play Store:** Akonáhle sa Cleona objaví v Store a nainštaloval
   si ju cez Store, dostávaš aktualizácie ako zvyčajne cez Store.
   Na iPhone prichádzajú aktualizácie cez TestFlight.
2. **GitHub Releases:** Na stránke GitHubu projektu nájdeš podpísané
   inštalačné balíky pre všetky platformy.
3. **Aktualizácie cez sieť:** Cleona môže získať aktualizáciu priamo cez
   sieť -- bez servera na sťahovanie. Nová verzia je rozdelená na kúsky
   s korekciou chýb, ktoré sa rozptýlia v sieti; jedna časť ide dokonca
   spolu s maskovacím tokom. Tvoje zariadenie nazbiera dostatok kúskov a
   poskladá aktualizáciu. Prenáša sa zvyčajne len zmena -- pár MB namiesto
   celej apky. To platí pre Linux, Windows a Android; pod macOS sťahuješ
   nové verzie z webovej stránky alebo z GitHubu.
4. **Pozvánkové odkazy:** Môžeš vytvoriť pozvánkové odkazy, ktoré
   obsahujú všetko, čo nový používateľ potrebuje, aby si nainštaloval
   Cleonu a pripojil sa k sieti.
5. **Fyzický prenos:** V prostrediach bez internetu môžeš Cleonu odovzdať
   ďalej cez USB kľúč alebo v lokálnej sieti.

### Ako prebieha aktualizácia

1. Cleona zbiera kúsky novej aktualizácie automaticky na pozadí a
   skladá ich.
2. Až keď je aktualizácia **úplná** a jej **podpis bol skontrolovaný**,
   ponúkne ti ju Cleona. Nedostaneš teda nikdy polovičatú ani
   neskontrolovanú aktualizáciu.
3. Keď Ťukneš na „Inštalovať", spustí sa inštalácia bez ďalšieho opýtania.
   Na Android navyše zobrazí systém svoj inštalačný dialóg.

Staršie verzie sa neponúkajú -- aktualizácia ide vždy len vpred. Je
verzia taká stará, že už nedokáže spolupracovať so sieťou, Cleona to jasne
oznámi a poprosí ťa o aktualizáciu.

### Kontrola podpisu

Každá aktualizácia je dvojnásobne podpísaná: klasickým a post-kvantovým
postupom. Cleona automaticky skontroluje oba podpisy. Tak je zabezpečené,
že sa prijmú len aktualizácie od oficiálneho vývojára -- aj keď prišla
aktualizácia cez sieť od cudzích zariadení. Aktualizácia nikdy nevznikne
automaticky z vývoja, ale len keď ju vývojár ručne podpíše.

---
## 16. Časté otázky

### „Môžem používať Cleonu bez internetu?"

Cleona potrebuje sieťové pripojenie, ale nie nevyhnutne internet:
V rovnakej Wi-Fi sa zariadenia Cleona nájdu samy a môžu si bez prístupu
k internetu navzájom písať. Súčasne online byť s tvojím protistrana
nemusíš: Je offline, správa čaká až 7 dní v schránke u troch susedov,
kým si ju vyzdvihne.

### „Čo keď stratím svoju seed-frázu?"

Kým ešte beží jedno zariadenie s tvojou identitou, nie je nič stratené --
tam jednoducho píšeš ďalej. Na zariadení, na ktorom si identitu založil,
môžeš tých 24 slov zvyčajne znova odčítať (pozri kapitolu 2). Nespoliehaj
sa na to: Preinštalovanie túto kópiu zruší a na Androide ju zničí aj
odstránenie alebo zmena zámku obrazovky. Ak nemáš ani slová, ani
zariadenie, neexistuje cesta späť -- ani cez tvoje kontakty, vývojára
alebo kohokoľvek iného. Preto je také dôležité tých 24 slov bezpečne
uschovať.

### „Môže niekto čítať moje správy?"

Nie. Každá správa sa zašifruje jednorazovým kľúčom, ktorý platí len pre
túto jednu správu. Len ty a tvoj protistrana môžete správu dešifrovať.
Neexistuje žiadny centrálny server, žiadny hlavný kľúč a žiadny prístup
pre vývojára. Aj keby zariadenie na ceste preposielalo správu, vidí len
šifrovanú kašu a kód. Tvoj sused vie, že paket prichádza od teba, ale nie,
komu ide; sused tvojho protistrana vie, komu ide, ale nie, od koho.

### „Prečo nepotrebujem telefónne číslo?"

Lebo tvoja identita je čisto kryptografická. Namiesto telefónneho čísla
alebo e-mailovej adresy, ktorá je prepojená s tvojím skutočným menom, ťa
identifikuje pár kľúčov, ktorý sa vygeneroval na tvojom zariadení. Kontakty
pridávaš cez QR kód, NFC alebo riadok textu svojej pozvánky -- nie cez
akýsi telefónny zoznam. To znamená
viac súkromia, lebo tvoj účet messengera nie je naviazaný na tvoju reálnu
identitu.

### „Ako nájdem ľudí na Clone?"

Cleona zámerne nemá vyhľadávanie kontaktov podľa telefónneho čísla
alebo mena -- to by bol problém súkromia. Namiesto toho si pozvánky
vymieňaš priamo: cez QR kód, NFC alebo ako riadok textu inou cestou. To je
ako vymieňať si vizitky namiesto nahliadania do telefónneho zoznamu.

### „Funguje Cleona aj v zahraničí?"

Áno. Kým máš internetové pripojenie, funguje Cleona všade na svete. Keďže
neexistuje žiadny centrálny server a žiadna pevná adresa, nedá sa služba
len tak pre určité krajiny vypnúť. Ako Cleona sťažuje blokovanie, stojí
v kapitole „Bezpečnosť" pod „Anticenzúra". Krajina, ktorá blokuje každú
neznámu prevádzku na hranici, však dokáže Cleonu aj zastaviť.

### „Je Cleona zadarmo?"

Áno. Cleona je použiteľná zadarmo a bez reklamy. Keďže neexistuje žiadny
centrálny server, nevznikajú ani žiadne náklady na server pre prevádzku.
V nastaveniach pod „Podporuj Cleona" -> „Darovať" môžeš vývoj dobrovoľne
podporiť.

### „Moja správa má len jednu fahu -- čo to znamená?"

Správa je na ceste, ale tvoj protistrana ešte nepotvrdil prijatie --
najčastejšie preto, lebo je práve offline. To nie je chyba: Správa čaká
až 7 dní v schránke. Len čo si ju vyzdvihne, vidíš dve fahy. Hodiny
znamenajú, že ešte žiadna cesta nenesie správu -- sama vyrazí, len čo
nejaká existuje; varovné znamenie, že 14 dní nenašla žiadnu cestu
a môžeš ju odoslať znova.

### „Prečo správy prichádzajú neskoro na mojom iPhone?"

iOS neumožňuje aplikáciám trvalo bežať na pozadí. Cleona je prebúdzaná len
občas a len krátko; kedy, to rozhoduje iOS. Potom prevezme všetko. Akonáhle
otvoríš aplikáciu, Cleona vyzdvihne, čo bolo pre teba uschované.

### „Môžem prejsť z WhatsAppu na Cleonu?"

Áno, ale svoje chaty z WhatsAppu nedokážeš preniesť. Cleona a WhatsApp
sú fundamentálne odlišné systémy. Svoje kontakty musíš pridávať do Cleony
jednotlivo. Najjednoduchšie to ide, keď pošleš riadok textu svojej
pozvánky svojím kontaktom. Každú žiadosť, ktorá tak príde, potvrdíš sám
pod „Žiadosti".

### „Môžem používať Cleonu na viacerých zariadeniach súčasne?"

Zatiaľ nie. Druhé zariadenie pre rovnakú identitu príde s neskoršou
verziou (kapitola 11). Na viacerých zariadeniach môžeš dnes používať
rôzne identity.

### „Ako dostanem aktualizácie, keď je App Store zablokovaný?"

Cleona môže získať aktualizácie priamo cez sieť, bez závislosti na App
Store, webovej stránke alebo serveri na sťahovanie. Ak má iné zariadenie
v sieti najnovšiu verziu, môže tvoje zariadenie stiahnuť aktualizáciu
odtiaľ. Pravosť sa skontroluje digitálnym podpisom vývojára. Prípadne ti
môže kontakt odovzdať apku cez pozvánkový odkaz alebo USB kľúč. Viac v
kapitole „Aktualizácie softvéru".

---

## Pomoc a kontakt

Ak máš otázky alebo narazíš na problém, aktuálne informácie nájdeš na
webovej stránke Cleona a na GitHube. Keďže je Cleona decentralizovaný
projekt, neexistuje žiadna klasická zákaznícka podpora -- ale aktívna
komunita, ktorá rada pomôže.

---

*Táto príručka popisuje Cleona Chat verzia 4.2. Jednotlivé funkcie sa
môžu v novších verziách zmeniť alebo rozšíriť.*
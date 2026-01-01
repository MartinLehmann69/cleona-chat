# Cleona Chat -- Felhasználói kézikönyv

4.2-es verzió | 2026 novemberi állapot

---

## Tartalomjegyzék

1. [Mi az a Cleona Chat?](#1-mi-az-a-cleona-chat)
2. [Első lépések](#2-első-lépések)
3. [Kapcsolatok](#3-kapcsolatok)
4. [Üzenetek](#4-üzenetek)
5. [Csoportok](#5-csoportok)
6. [Nyilvános csatornák](#6-nyilvános-csatornák)
7. [Hívások](#7-hívások)
8. [Naptár](#8-naptár)
9. [Szavazások](#9-szavazások)
10. [Több identitás](#10-több-identitás)
11. [Több eszköz](#11-több-eszköz)
12. [Helyreállítás](#12-helyreállítás)
13. [Beállítások](#13-beállítások)
14. [Biztonság](#14-biztonság)
15. [Szoftverfrissítések](#15-szoftverfrissítések)
16. [Gyakori kérdések](#16-gyakori-kérdések)

---

## 1. Mi az a Cleona Chat?

### A te üzenetküldőd, a te adataid

A Cleona Chat egy üzenetküldő, amely teljesen központi szerver nélkül működik.
Az üzeneteid a te készülékedtől a partnered készülékéig utaznak -- egy
cégszékhely, egy felhő és egy adatközpont megkerülése nélkül. Ahol útközben
egy másik készülék segít, az csak titkosított csomagokat továbbít. Egyetlen
cégnél sem tudja elolvasni, eltárolni vagy továbbadni az üzeneteidet, egyszerűen
azért, mert egyetlen cég sem áll közben.

### Nincs fiók, nincs telefonszám

A Cleonánál nincs szükséged sem telefonszára, sem e-mail-címre a bejelentkezéshez.
Az identitásod egy kriptográfiai kulcspárból áll, amely az első induláskor
automatikusan a készülékeden jön létre. Ez azt jelenti: senki sem tud
megkeresni a telefonszámod vagy az e-mail-címed alapján, hacsak te magad nem
adod tovább a kapcsolattartási adataidat.

### Jövőbiztos titkosítás

A Cleona úgynevezett post-kvantum titkosítást használ. Ez azt jelenti: a
jövőbeli kvantumszámítógépek sem tudnák feltörni az üzeneteidet. A részleteket
nem kell értened -- csak az a fontos, hogy a kommunikációd a jelenlegi technikai
állapot szerint a lehető legjobban védve legyen.

### Hogyan működik ez szerver nélkül?

A Cleona hálózata csak a felhasználók készülékeiből áll. Minden készülék egy
csomópont, egyetlen csomópont sem fontosabb a másiknál, és mindegyik csak a
saját szomszédjait ismeri. Négy dolog teszi különlegessé ezt a hálózatot:

- **Nincs fix pont.** Az alkalmazásban nem szerepel szervercím, és a hálózat
  nem függ egyetlen csomóponttól sem. Nincs semmi, amit lekapcsolhatnál, hogy
  a Cleonát leállítsd.
- **Azonnali.** Az üzeneted abban a pillanatban indul, amikor elküldöd. Nem
  vár semmilyen ütemre és semmi másra.
- **Álcaforgalom mellékesen.** A készüléked folyamatosan kis álcacsomagokat
  küld, hogy kívülről ne lehessen látni, mikor írsz valójában. Egyetlen
  üzenet sem függ tőle -- az álcaforgalom csak mellette fut.
- **Kódok nevek helyett.** Aki továbbít egy üzenetet, csak egy olyan kódot
  lát, amely minden nap változik. Rendszerint egyikük sem ismeri egyszerre a
  feladót és a címzettet; a kivételeket a 14. fejezet írja le.

**Három út, egyszerre.** Amikor elküldesz egy üzenetet, a Cleona nem sorban
egyesével próbálja az utakat, hanem az összes megfelelőt egyszerre. Amint a
partnered visszaigazolja a kézbesítést, a többi megszakad.

1. **Ugyanabban a hálózatban:** Ha ugyanabban a Wi-Fi-ben vagytok, az üzenet
   egyenesen átmegy.
2. **Az állandó szomszédokon át:** Az interneten a készüléked átadja az
   üzenetet az állandó szomszédjának. Az továbbítja a partnered állandó
   szomszédainak (egyszerre legfeljebb háromnak), és az egyikük kézbesíti.
3. **Postafiók:** Ha a partnered offline van, a Cleona titkosítva leteszi az
   üzenetet három szomszédnál. Ott marad legfeljebb 7 napig. Ha a partnered
   újra online lesz, ő felmenti.

**Hogyan jutsz be a hálózatba?** Az alkalmazásban nem szerepel szervercím. A
belépést az első kapcsolatodtól kapod: a meghívója tartalmazza azokat a
címeket, amelyeken a készüléked az első szomszédjait megtalálja. Ugyanabban a
Wi-Fi-ben a Cleona-készülékek önmaguk is megtalálják egymást. Onnan kezdve a
készüléked minden szomszéddal megismer továbbiakat is.

### Platformok

A Cleona elérhető Androidra, iOS-re, macOS-re, Linuxra és Windowsra.
Számítógépeken és Androidon az üzenetek és a hívások másodperceken belül
megérkeznek. Az iPhone-on ez addig áll fenn, amíg az alkalmazás nyitva van.
Ha nincs nyitva, az iOS csak időnként ébreszti fel rövid időre; hogy mikor,
azt az iOS dönti el. A Cleona ilyenkor lekéri mindazt, amit neked
megőriztek, és egy számot megjelenítő értesítést mutat az alkalmazás
ikonján. A hívások nem érik el azt az iPhone-t, amelyen az alkalmazás nincs
nyitva. Ez az Apple szabálya, nem a Cleona hibája.

---

## 2. Első lépések

### Az alkalmazás telepítése

**Android:**
1. Töltsd le az APK-fájlt a Cleona-weboldalról vagy a GitHub Releasesből.
2. Nyisd meg a fájlt a telefonodon. Szükség esetén engedélyezd az ismeretlen
   forrásból történő telepítést (az Android automatikusan megkérdez).
3. Koppints a „Telepítés" gombra, és várj, amíg a telepítés befejeződik.

**iOS:**
1. Nyisd meg a TestFlight-meghívó linket az iPhone-odon.
2. Koppints a „Telepítés" gombra. A TestFlight az Apple hivatalos módja a
   béta-alkalmazások terjesztésére.
3. A telepítés után a Cleonát a kezdőképernyődön találod.

**macOS:**
1. Töltsd le a DMG-fájlt a Cleona-weboldalról vagy a GitHub Releasesből.
2. Nyisd meg a DMG-t, és húzd a Cleonát a Programok mappádba.
3. Az első indításkor a macOS esetleg megkérdezi, hogy meg akarod-e nyitni egy
   azonosított fejlesztő alkalmazását -- erősítsd meg.

**Linux (Ubuntu/Debian):**
1. Töltsd le a .deb-fájlt a Cleona-weboldalról vagy a GitHub Releasesből.
2. Telepítsd dupla kattintással vagy a terminálban: `sudo dpkg -i cleona-chat-beta_VERSION_amd64.deb`
3. Indítsd a Cleonát az alkalmazásmenüből vagy a terminálban a `cleona-chat-beta` paranccsal.

**Linux (Fedora/openSUSE):**
1. Töltsd le a .rpm-fájlt a Cleona-weboldalról vagy a GitHub Releasesből.
2. Telepítsd így: `sudo dnf install cleona-chat-beta-VERSION-1.x86_64.rpm`
3. Indítsd a Cleonát az alkalmazásmenüből vagy a terminálban a `cleona-chat-beta` paranccsal.

**Linux (minden disztribúció -- AppImage):**
1. Töltsd le az .AppImage-fájlt a Cleona-weboldalról vagy a GitHub Releasesből.
2. Tedd a fájlt futtathatóvá: jobb kattintás, Tulajdonságok, Futtatható, vagy a
   terminálban: `chmod +x cleona-chat-beta-VERSION-x86_64.AppImage`
3. Indítsd dupla kattintással vagy a terminálban: `./cleona-chat-beta-VERSION-x86_64.AppImage`

A csomagnevek a bétára vonatkoznak, amely jelenleg az egyetlen közzétett
változat; így hívják: `cleona-chat-beta`.

**Windows:**
1. Töltsd le a telepítőt a Cleona-weboldalról vagy a GitHub Releasesből.
2. Futtasd a telepítőfájlt, és kövesd az utasításokat.
3. Indítsd a Cleonát a Start menüből vagy az asztali parancsikonról.

### Identitás létrehozása

Az első indításkor a Cleona automatikusan létrehoz neked egy új identitást.
Adhatsz magadnak egy megjelenítendő nevet -- ez az a név, amelyet a kapcsolataid
látnak. Ez a név bármikor módosítható.

### Seed-kifejezés leírása -- a legfontosabb egyáltalán

Az identitásod létrehozása után a Cleona 24 szót mutat neked. Ez a te
**seed-kifejezésed** -- a személyes helyreállítási kulcsod.

**Írd fel ezt a 24 szót papírra, és őrizd biztonságban.**

Miért olyan fontos ez?

- Ha a telefonod tönkremegy, elveszik vagy ellopják, ezzel a 24 szóval a
  teljes identitásodat helyreállíthatod egy új készüléken.
- A seed-kifejezés nélkül nincs visszaút. Nincs „elfelejtett jelszó" gomb és
  nincs olyan ügyfélszolgálat, amely visszaadhatná a fiókodat -- mert
  egyáltalán nincs fiók egy szerveren. A kapcsolataid sem tudják
  helyreállítani az identitásodat, bármennyien is legyenek. Egy második
  készülék ugyanazzal az identitással egy későbbi verzióval jön (lásd a 11.
  fejezetet).
- Soha ne add tovább a seed-kifejezést másnak. Aki ismeri ezeket a szavakat,
  kiadhatja magát teként.

A 24 szót később a beállítások „Biztonsági mentés" -> „Helyreállítási
kifejezés megjelenítése" alatt találod meg, ha újra le akarod olvasni.
Androidon ehhez a képernyőzáraddal erősíted meg.

### Első kapcsolat hozzáadása

Ahhoz, hogy valakivel csevegj, először kapcsolatként kell hozzáadnod a személyt.
Ehhez több út van -- mindegyiket a következő szakasz magyarázza el.

---

## 3. Kapcsolatok

### A te meghívód

A Cleonánál kapcsolatok csak meghívón keresztül jönnek létre. A meghívód az
első indítástól ott van -- internet nélkül is, még mielőtt a készüléked
egyáltalán szomszédot talált volna. Az identitás-részletek oldalán találod
(koppints a saját nevedre a felső sávban).

A meghívó két formában létezik, amely pontosan ugyanazt tartalmazza:

- **QR-kódként**, ha a partnered melletted áll, és
- **szövegsorként**, amelyet e-mailben, SMS-ben vagy egy másik üzenetküldőn
  keresztül küldesz el.

A meghívó nem tartalmaz telefonszámot és nem tartalmaz egy címtárból származó
nevet. A nyilvános kulcsaidat és azokat a címeket tartalmazza, amelyeken a
partnered elér téged és a szomszédjaidat. Olyasvalakinek, aki most telepíti a
Cleonát, a meghívód ezért egyben a belépés is a hálózatba.

### QR-kód beolvasása (ajánlott)

Ha személyesen találkoztok:

1. Mutasd a partnerednek a meghívód QR-kódját.
2. A partnered koppint a plusz gombra, választja a „QR-kód beolvasása"
   lehetőséget, és a kamerát a képernyődre tartja. Ez a számítógép webkamerájával
   is működik.
3. A kérés hozzád érkezik, és **automatikusan elfogadásra kerül** -- hiszen
   te magad mutattad az imént a kódot.

Egy QR-kód csak egyszer érvényes: az első érvényes kérés elfogadásra kerül,
utána a meghívó felhasználtnak minősül. A QR-kód a legbiztonságosabb módszer,
mert közben pontosan tudjátok, kivel cserélitek a kapcsolatot.

### NFC (telefonok összeérintése)

Ha mindkét készülék támogatja az NFC-t:

1. Mindketten nyissátok meg a kapcsolat-hozzáadás funkciót.
2. Tartsátok össze a telefonjaitokat hátoldallal egymáshoz.
3. A meghívó átkerül, és automatikusan elfogadásra kerül.

Az NFC a QR-kódhoz hasonlóan magas biztonságot kínál, mert a csere csak akkor
működik, ha fizikailag egymás mellett álltok.

### Szövegsor elküldése

Ha nem tudtok találkozni:

1. Nyisd meg a meghívódat, és másold ki a szövegsort.
2. Küldd el annak a személynek, aki hozzád akar adni -- e-mailben, SMS-ben
   vagy egy másik üzenetküldőn keresztül.
3. A másik személy illessze be a sort a Cleonában a kapcsolat-hozzáadás
   ablakban.
4. A kérés nálad a **„Kérések"** alatt jelenik meg. Itt **nem** történik
   automatikus elfogadás: te magad döntesz, hiszen nem tudhatod, ki olvasta
   még a sort útközben.

### Kapcsolatkérések elfogadása

Egy beérkező kérés még nem hoz létre kapcsolatot. Feltéz neked egy kérdést, és
a **„Kérések"** fülön jelenik meg. Ott látod a nevet és az ellenőrzési
szintet, és választhatsz:

- **Elfogadás** -- csak most válik a személy a kapcsolatoddá.
- **Elutasítás** -- a kérés elvetésre kerül.
- **Letiltás** -- a személy nem küldhet neked további kéréseket.

### Soha ne állandó szomszédként használni

Egy kapcsolat menüjében megtalálod a **„Soha ne állandó szomszédként használni"**
kapcsolót (alapértelmezés: ki). Ha be van kapcsolva, ez a kapcsolat nem
továbbít neked üzeneteket, és így nem is tudja meg, mikor küldesz vagy fogadsz
üzeneteket. Arra az esetre van gondolva, ha a veszély a saját környezetedből
fenyeget.

Az ismeretlenektől (sem kapcsolat, sem egy közös csoport tagja) a Cleona egy
ilyen kérésen kívül semmit sem enged át -- sem üzenetet, sem hívást, sem fájlt.
És még a kérés is csak akkor érkezik be,
ha a feladó előbb megoldott egy kis számítási feladatot. Ez tömeges spammelést
drágává teszi.

### Ellenőrzési szintek

A Cleona jelzi neked, mennyire biztosan igazolt egy kapcsolat identitása:

| Szint | Jelentés |
|-------|-----------|
| Nem ellenőrzött | Kapcsolatban vagytok, de semmi sem igazolja, hogy tényleg a megfelelő személy áll mögötte. |
| Látva | A kulcscsere sikeres volt, titkosítva tudtok kommunikálni. |
| Ellenőrizve | Személyesen találkoztatok, és kamerás szkenneléssel vagy NFC-vel csatlakoztatok. |
| Megbízható | Ezt a kapcsolatot kifejezetten megbízhatónak jelölted. |

„Ellenőrizve" csak a személyes cserénél létezik. Egy olyan meghívó, amely
csevegéssel vagy e-maillel érkezett, soha nem éri el ezt a szintet -- akkor
sem, ha ugyanazokat az adatokat tartalmazza.

Ha egy kapcsolat kulcsai bejelentés nélkül megváltoznak, a Cleona
visszaállítja „Nem ellenőrzött"re. Ez megvéd attól, hogy valaki észrevétlenül
a kapcsolatodnak adja ki magát.

---
## 4. Üzenetek

### Szöveg küldése és fogadása

Írd be egyszerűen az üzenetedet az alsó beviteli mezőbe, és nyomd le az Entert
vagy a küldés gombot. Az üzeneted automatikusan titkosításra kerül, mielőtt
elhagyja a készülékedet.

A beérkező üzenetek a csevegés előzményében jelennek meg.

### Mit jelentenek az üzeneted jelei

| Jel | Jelentés |
|---------|-----------|
| Óra | Az üzenet létrejött, de még egyetlen út sem vitte el. |
| Egy pipa | Az üzenet úton van. Ez érvényes addig is, amíg a postafiókban várakozik a partneredre. |
| Két pipa | Kézbesítve: a partnered készüléke visszaigazolta a kézbesítést. |
| Figyelmeztető jel | 14 napig egyetlen út sem vitte el az üzenetet. Koppints rá, hogy újra elküldd. |

**Az offline nem hiba.** Ha a partnered nem érhető el, az üzenet egy pipánál
marad, amíg fel nem mélik -- nem veszett el. Ha a te készülékednek magának
nincs kapcsolata, az üzenet az óránál marad, és magától elindul, amint újra
van egy út. A figyelmeztető jel csak akkor jelenik meg, ha 14 napig nem
talált utat; akkor újra elküldheted.

Ez akkor is érvényes, ha egy iPhone-on az alkalmazás nincs nyitva: az üzenet
a postafiókban vár, amíg az iOS rövid időre fel nem ébreszti az alkalmazást,
vagy amíg a partnered meg nem nyitja. Ez tovább tarthat, mint más
készülékeken.

Két pipa csak akkor van, ha a címzett maga igazolja vissza a kézbesítést. Ez
a visszaigazolás titkosított és aláírt -- senki útközben nem hamisíthatja meg,
hogy kézbesítést színleljen neked.

### Képek, videók és fájlok küldése

Több lehetőséged van:

- **Gemkapocs-ikon** a beviteli mezőben: Koppints rá, hogy kiválassz egy fájlt,
  képet vagy videót a galériádból vagy a fájlrendszeredből.
- **Fogd és vidd** (asztali): Húzz egy fájlt egyszerűen a csevegés ablakába.
- **Beillesztés a vágólapról** (asztali): Másolj egy képet, és illeszd be a
  csevegésbe.

Kis fájlok (256 KB alatt) közvetlenül az üzenetben utaznak. A nagyobb fájlok
darabokra bontódnak, és hibajavítással látják el őket, úgyhogy az egyes
elveszett darabok nem okoznak gondot. Ha mindketten online vagytok, egy
szomszédon keresztül kerülnek streamelve; különben olyan készülékeknől kerülnek
letétbe, amelyek folyamatosan elérhetők, amíg a partnered fel nem médi őket.

256 KB-tól a Cleona fájlonként megkérdez, mielőtt elküldené: egy nagy fájl
nem mehet az üzeneteid útján. A tartalma titkosított marad, és a partnered
nem tudja meg az internetcímedet. Az átvitel viszont kívülről eseményként
látszik, és egy idegen készülék, amely továbbítja vagy megőrzi, látja, ki
tölti fel, és ki méri le. A beleegyezésed csak erre az egy fájlra érvényes.

### Hangüzenetek

1. Tartsd nyomva a mikrofongombot a beviteli mezőben.
2. Mondd el az üzenetedet.
3. Engedd el a gombot, hogy elküldd az üzenetet.

Ha a készülékeden be van kapcsolva a beszédfelismerés (lásd a beállításokat),
a hangüzeneted automatikusan szöveggé íródik át. A partnered ekkor mind a
felvételt, mind az átiratolt szöveget látja.

### Üzenetek megválaszolása (idézés)

Egy adott üzenetre való válaszoláshoz:

1. Nyisd meg az üzenet melletti hárompontos menüt.
2. Válaszd az „Válasz" lehetőséget.
3. A beviteli mező felett megjelenik egy sáv az idézett üzenettel.
4. Írd meg a válaszodat, és küldd el.

Az idézett üzenet a válaszodban megjelenik, hogy az utalás egyértelmű legyen.

### Üzenetek szerkesztése és törlése

- **Szerkesztés:** Az üzenet hárompontos menüje, majd „Szerkesztés". Módosítsd
  a szöveget, és küldd el újra. A partnered látja, hogy az üzenet szerkesztve
  lett. A szerkesztés a küldéstől számított 15 percen belül lehetséges.
- **Törlés:** Az üzenet hárompontos menüje, majd „Törlés". Az üzenet nálad és
  a partnerednél is eltávolításra kerül. A saját üzeneteid bármikor törölheted
  -- nincs időablak a törlésre.

### Emoji-reakciók

Ahelyett, hogy választ írnál, egy emoji-val is reagálhatsz egy üzenetre:

1. Nyisd meg a hárompontos menüt, vagy tartsd hosszan nyomva az üzenetet.
2. Válassz egy emoji-t a gyorsválasztóból, vagy nyisd meg az emoji-választót
   a teljes kínálatért.
3. A reakciód az üzenet alatt jelenik meg.

### Szöveg másolása

Egy üzenet hárompontos menüjéből a vágólapra másolhatod az üzenet szövegét.

### Üzenetek keresése

A csevegés ablakának felső szélén találod a kereső funkciót. Írj be egy
keresőkifejezést, és a Cleona megmutatja az összes találatot az aktuális
csevegésben. A nyílgombokkal ugorhatsz a találatok között oda-vissza.

A kezdőlapon emellett van egy fülek közötti keresési szűrő is, amellyel az
összes beszélgetést átkutathatod egy kifejezésre.

### Link-előnézet

Ha egy linket küldesz, a Cleona automatikusan előnézetet készít (cím,
leírás, előnézeti kép). Ezt az előnézetet a te készüléked hozza létre, és
együtt küldi el -- a partnerednek emiatt nem kell kapcsolatot létesítenie a
hivatkozott weboldallal.

Azt, hogy mit tesz egy koppintás egy beérkezett linkre, a beállítások „Linkek
megnyitása" alatt állítod be: „Normál", „Privát ablak előnyben részesítve"
(ahol a készülék nem tud privát ablakot nyitni, a link normál módon nyílik
meg) vagy „Rákérdezés minden alkalommal".

---

## 5. Csoportok

### Csoport létrehozása

1. Válts a „Csoportok" fülre.
2. Koppints a plusz gombra.
3. Adj a csoportnak egy nevet.
4. Válaszd ki a kapcsolatokat, akiket meg akarsz hívni.
5. Koppints a „Létrehozás" gombra.

A meghívott kapcsolatok értesítést kapnak, és csatlakozhatnak a csoporthoz.

### Hogyan védettek a csoportüzenetek

Egy legfeljebb 16 tagú csoportban a Cleona minden üzenetet minden tagnak
egyenként küld -- mindegyet csak annak a tagnak titkosítva, mintha mindegyiknek
egy külön üzenetet írtál volna. A pipák egy csoportüzeneten annak a tagnak az
állapotát mutatják, akinél a legkevésbé jutott előre.

Ha a csoport 16 tag fölé nő, közös kulcsot használ. Az minden nap változik,
és újra sorsolják, ha egy tag kilép vagy eltávolítják; egy új tag csak a
csatlakozásától olvas. Ott a pipák már nem minden tag állapotát mutatják,
hanem azt, hogy az üzenet a hálózatban lett letéve. Ha a csoport 12 vagy
kevesebb tagra csökken, visszaáll az egyenkénti küldés.

### Képek a csoportokban és csatornákban

Egy csoport vagy csatorna beállításaiban a „Képek mindig betöltése"
kapcsolóval állítod be, hogy a képek azonnal betöltődjenek, vagy csak akkor,
amikor rájuk koppintasz.

### Tagok meghívása

A létrehozás után is meghívhatsz további kapcsolatokat:

1. Nyisd meg a csoportinformációkat (hárompontos menü a csoport áttekintésében
   vagy a felső sáv a csoportcsevegésben).
2. Koppints a „Meghívás" gombra.
3. Válaszd ki a kapcsolatokat, akiket hozzá akarsz adni.

### Szerepkörök

Minden csoportban három szerepkör van:

- **Tulajdonos (Owner):** Teljes kontrollja van. Hozzáadhat és eltávolíthat
  tagokat, adminokat nevezhet ki, és kezelheti a csoportot. A tulajdonos az
  státuszát egy másik tagra is átruházhatja.
- **Admin:** Eltávolíthat tagokat, és segít a csoport kezelésében.
- **Tag:** Olvashat és írhat üzeneteket.

### Csoport elhagyása

1. Nyisd meg a hárompontos menüt a csoport áttekintésében.
2. Válaszd az „Elhagyás" lehetőséget.
3. Erősítsd meg a döntésedet.

Ha elhagyod a csoportot, az eddigi üzeneteid a többi tag számára láthatóak
maradnak.

---

## 6. Nyilvános csatornák

### Mik azok a csatornák?

A csatornák a Cleona-hálózaton belüli nyilvános vitafórumok. A csoportokkal
ellentétben itt mindenki olvashat anélkül, hogy meg kellene hívni. Csak a
tulajdonos és az adminok tehetnek közzé bejegyzéseket -- a feliratkozók
csak olvassák.

### Csatornák keresése és csatlakozás

1. Válts a „Csatornák" fülre.
2. Nyisd meg a „Keresés" fület.
3. Keresd át az elérhető csatornákat név vagy téma szerint.
4. Koppints egy csatornára, majd az „Feliratkozás" gombra.

A csatornák nyelv szerint szűrhetők. Egyes csatornák „Nem ifjúsági" jelöléssel
ellátottak -- ezek csak akkor láthatók, ha a profilodban megerősítetted, hogy
18 évesnél idősebb vagy.

### Saját csatorna létrehozása

1. Válts a „Csatornák" fülre.
2. Koppints a plusz gombra.
3. Írj be egy csatornanevet (az egész hálózatban egyedinek kell lennie).
4. Válaszd ki a nyelvet, és hogy a csatorna nyilvános vagy privát legyen.
5. Opcionális: Adj hozzá leírást és egy képet.
6. Koppints a „Létrehozás" gombra.

A nyilvános csatornáknál beállíthatod, hogy a tartalom „Nem ifjúsági"
besorolású-e.

### Tartalmak jelentése

Ha egy nyilvános csatornában nem megfelelő tartalmat veszel észre, jelentheted.
A Cleona decentralizált moderációs rendszert használ: a jelentéseket a hálózat
véletlenszerűen kiválasztott tagjai értékelik (egyfajta „esküdtbíróság").
Ha visszaélést állapítanak meg, a csatorna figyelmeztetést kap. Ismételt
visszaélések esetén a keresési indexben visszasorolásra kerül, vagy blokkolják.

### Rendszercsatornák

A Cleona két beépített rendszercsatornával rendelkezik:

- **Bug Log:** Ha a Cleona hibát észlel, megkérdezi, hogy akarsz-e
  hibajelentést küldeni; előtte pontosan látod, mit tesznek közzé. Ezek a
  jelentések a Bug-Log csatornába
  kerülnek, ahol a közösség megtekintheti őket. Egy jelentés nem hordoz nevet
  és nem a beszélgetéseid tartalmát, hanem egy álnevet. A béta esetében
  emellett feltünteti az azonosítódat (User-ID), hogy a fejlesztők rá tudjanak
  kérdezni. Manuálisan is küldhetsz log-jelentést
  (előnézeti ablakkal és kifejezett hozzájárulással).
- **Feature Requests:** Itt a felhasználók funkciókéréseket nyújthatnak be,
  és szavazhatnak a meglévő javaslatokra. A javaslatok szavazatok szerint
  rendezve.

Minden számítógép legfeljebb 25 MB-ot tart rendszercsatornánként, minden
telefon legfeljebb 5 MB-ot; ha megtelt, a legrégebbi megy el először -- soha
nem az, amit te magad már láttál.

---
## 7. Hívások

### Hanghívás indítása

1. Nyisd meg a csevegést azzal a kapcsolattal, akit fel akarsz hívni.
2. Koppints a telefon szimbólumra a felső sávban.
3. Várj, amíg a partnered felveszi a hívást.

A beszélgetés alatt látsz egy idővonalat, a hívás hosszát, és hozzáférsz a
némításhoz és a hangszóróhoz.

A letételhez koppints a piros letétel gombra.

Ha „Nem elérhető” jelzést látsz, a partnered készüléke most nem érhető el,
például egy iPhone, amelyen az alkalmazás nincs nyitva. Írj helyette
üzenetet.

### Videohívás indítása

1. Nyisd meg a csevegést a kapcsolattal.
2. Koppints a kamera szimbólumra a felső sávban.
3. A videód egy kis ablakban jelenik meg, a partnered képe a nagy területen.

A beszélgetés alatt válthatsz az előlap és a hátlap kamera között.

### Beérkező hívások

Ha valaki felhív, megjelenik egy értesítési ablak a hívó nevével. Választhatsz:

- **Felvesz** -- a beszélgetés elkezdődik.
- **Elutasít** -- a hívó értesítést kap.

Ha épp beszélgetésben vagy, egy új hívás nem cseng; helyette egy „Nem fogadott
hívás" üzenetet kapsz. Ugyanez érvényes egy csoportos hívásra, amelyet nem
fogadtál -- az üzenet akkor a csoportcsevegésben áll.

Ha valaki egy olyan identitásodat hívja, amely épp nincs megjelenítve, akkor
is cseng; a hívás képernyője megmondja, melyik identitásodat hívják.

Az iPhone-on csak akkor csöng, ha az alkalmazás nyitva van. Aki akkor hív,
amíg nincs nyitva, 10 másodperc után „Nem elérhető” jelzést lát. Amint
megnyitod az alkalmazást, találsz egy üzenetet a nem fogadott hívásról.

### Csoportos hívások

Olyan csoportos hívásokat is folytathatsz, amelyeken több személy vesz részt
egyszerre. A hívást egy intelligens továbbítási fa szervezi, úgyhogy nem kell
minden résztvevőnek mindenkivel közvetlenül kapcsolódnia. Minden beszélgetés
végig titkosított.

Bármely csoporttag indíthat csoportos hívást. Két résztvevő, akik nem egymás
kapcsolatai, sosem látják a másik internetcímét: a hangjuk és a képük egy
olyan résztvevőn fut át, aki mindkettővel kapcsolatban van. Ha nincs ilyen,
a kettő nincs összekapcsolva, és a csempe azt mondja: „Nincs közös kapcsolat
a hívásban". Ha egy továbbítás ki van terhelve, a hang megmarad, és a videó
e pár számára elmarad.

### Titkosítás a hívásoknál

Minden hívás egyszeri kulcsokkal titkosított, amelyek csak a beszélgetés
idejére léteznek. A letétel után ezek a kulcsok azonnal törlődnek. Senki sem
tud egy múltbeli beszélgetést utólag visszafejteni.

Őszintén: a hívások, ahol csak lehetséges, közvetlenül a készülékek között
folynak, mert már egy kis késés is zavarja a beszédet. Az üzenetekkel ellentétben
az internetszolgáltatód egy hívásnál emiatt láthatja, melyik internetcímmel
vagy összeköttetésben. Amit mondtok, azt nem látja.

Hívásnál a kapcsolatod is látja az internetcímedet. Ha ezt egy kapcsolatnál
nem szeretnéd, kapcsold ki a menüjében a „Hívások engedélyezése" kapcsolót
(alapértelmezés: be). Ha csak később kapcsolod ki, egy már látott cím
továbbra is ismert marad nála.

---

## 8. Naptár

A Cleona tartalmaz egy beépített naptárt, amely titkosított és teljesen
decentralizált módon működik -- felhőszolgáltatás nélkül.

### Nézetek

A naptár öt nézetet kínál: nap, hét, hónap, év és egy feladat-nézet. A
naptár-képernyő felső szélén lévő fülekkel váltogathatod őket.

### Események létrehozása

Koppints egy idősávra, vagy használd a hozzáadás gombot egy új esemény
létrehozásához. Megadhatsz címet, dátumot, időt, helyet és jegyzeteket.
Az események titkosítva a készülékeden tárolódnak.

### Ismétlődő események

Az események ismétlődhetnek naponta, hetente, havonta vagy évente. A
mintát módosíthatod (pl. minden második kedd, minden hónap elseje), és
megadhatsz végdátumot vagy ismétlések számát.

### Kapcsolatok meghívása

Esemény létrehozásakor vagy szerkesztésekor meghívhatod a Cleona-kapcsolataidat.
Titkosított naptár-meghívót kapnak, és igennel, nemmel vagy „talán"nal
válaszolhatnak. Az esemény változásai automatikusan az összes meghívottnak
elküldésre kerülnek.

### Szabad/Foglalt megjelenítés

Megoszthatod a kapcsolataiddal az elérhetőségedet anélkül, hogy az esemény
részleteit felfednéd. Három adatvédelmi szint van: teljes részletek, csak
idősávok vagy rejtett. Beállíthatsz egy alapértelmezést, és kapcsolatonként
felülírhatod.

### Emlékeztetők

Az eseményekhez emlékeztetők tartozhatnak, amelyek az esemény kezdete előtt
rendszerértesítést váltanak ki. Az emlékeztetőket szükség esetén szundíttathatod.

### Külső naptár-szinkronizáció

A Cleona szinkronizálhat külső naptárszolgáltatásokkal:

- **CalDAV** -- Csatlakozz bármilyen CalDAV-kompatibilis szerverhez (Nextcloud,
  Radicale stb.).
- **Google Naptár** -- Szinkronizálás a Google Calendar API-n keresztül
  biztonságos OAuth2-hitelesítéssel.
- **Helyi CalDAV-szerver** -- A Cleona elindíthat egy helyi CalDAV-szervert a
  készülékeden, úgyhogy az asztali naptár-alkalmazások (Thunderbird, Outlook,
  Apple Naptár, Evolution) szinkronizálhatnak a Cleona-naptáradkal.
- **Android rendszer-naptár** -- A Cleona eseményei átvihetők az Android-
  készüléked beépített naptár-alkalmazásába.
- **ICS-fájlok** -- Importálj és exportálj eseményeket a szabványos
  iCalendar-formátumban.

### PDF-export

Bármelyik naptárnézetet (nap, hét, hónap, év) kinyomtathatod vagy
exportálhatod PDF-dokumentumként.

---

## 9. Szavazások

Minden csevegésben vagy csoportban készíthetsz szavazásokat, hogy véleményeket
kérj be, vagy időpontokat tervezz.

### Szavazástípusok

A Cleona ötféle szavazást támogat:

- **Egyszeres választás** -- A résztvevők egy lehetőséget választanak.
- **Többszörös választás** -- A résztvevők több lehetőséget is kiválaszthatnak.
- **Időpont-szavazás** -- Keress egy időpontot, amely mindenkinek megfelel.
  Minden résztvevő megjelöli az időpontokat elérhetőként, talánként vagy nem
  elérhetőként.
- **Skála** -- Értékelj valamit egy numerikus skálán (pl. 1-től 5-ig).
- **Szabad szöveg** -- A résztvevők saját választ írnak.

### Szavazás létrehozása

Nyiss meg egy csevegést, és koppints a szavazás szimbólumra (vagy használd a
melléklet-menüt). Válaszd ki a szavazás típusát, fogalmazd meg a kérdésedet és
a lehetőségeket, és küldd el a szavazást. Üzenetként jelenik meg a csevegésben.

### Szavazás

Koppints egy szavazásra, hogy lead a szavadat. A szavadat bármikor
megváltoztathatod vagy visszavonhatod.

### Névtelen szavazás

A szavazások beállíthatók névtelen szavazásra. Ha engedélyezve van, a szavazatok
kriptográfiailag anonimek -- senki, még a szavazás készítője sem látja, ki
mire szavazott. A szavazatok száma ettől is látható marad.

### Időpont-szavazás a naptárba

Amikor egy időpont-szavazás lezárult, a nyertes időpont egy koppintással
közvetlenül naptár-bejegyzéssé alakítható.

---
## 10. Több identitás

### Miért több identitás?

Képzeld el, hogy szét akarod választani a munkádat és a magánéletedet --
hasonlóan, mint két különböző telefonszámmal, de második telefon nélkül. A
Cleonában több identitást is használhatsz egy készüléken. Minden identitásnak
saját neve, saját profilképe, saját kapcsolatai és saját beszélgetései vannak.

### Új identitás létrehozása

1. A felső sávban az aktuális identitásod fülként látható.
2. Koppints a plusz jelre (+) az identitás-füleidtől jobbra.
3. Írj be egy nevet az új identitásnak.
4. Kész -- az új identitás azonnal aktív.

### Váltás identitások között

Koppints egyszerűen az identitás-fülre a felső sávban. A váltás azonnali --
nincs várakozás, nincs újratöltés.

### Mind egyszerre fut

Egy fontos dolog: az összes identitásod egyszerre aktív. Még akkor is, ha
épp „Munka" néven jelenítel meg, a „Privát" identitásod továbbra is fogadja
az üzeneteket. Semmiről sem maradsz le, bármelyik identitást is választottad
épp ki.

### Identitás-részletek oldala

Ha az épp aktív identitásod fülére koppintasz, megnyílik a részletek oldala.
Itt:

- Megjelenítheted a QR-kódodat a kapcsolatoknak.
- Megváltoztathatod vagy eltávolíthatod a profilképedet.
- Hozzáadhatsz egy profilismertetőt.
- Megváltoztathatod a megjelenítendő nevedet.
- Választhatsz egy dizájnt (skint) ehhez az identitáshoz.
- Törölheted az identitást, ha már nincs rá szükséged.

### Identitás törlése

Ha törölsz egy identitást, a kapcsolataid értesítést kapnak róla. Az identitás
és az összes hozzá tartozó adat eltávolításra kerül a készülékedről. Ez a
folyamat nem fordítható vissza.

---

## 11. Több eszköz

### Egy identitás, egy eszköz -- egyelőre

Egy identitás ma egy eszközön fut. Egy második eszköz ugyanahhoz az
identitáshoz egy későbbi verzióval jön; a beállítások „Eszközök" ->
„Eszközök kezelése" alatt a „További eszköz párosítása" ezért még „Még nem
érhető el" állapotban szerepel.

Ha eljön, akkor így lesz: minden eszköz egyenrangú, nincs fő eszköz. Egy
további eszközt a 24 szavaddal állítasz be, és egy eddigi eszközöd
jóváhagyja. Legfeljebb 5 eszköz.

Ha ma egy új eszközön beírod a 24 szavad, átköltözöl: az identitás az új
eszközön áll helyre, és az eddigi eszközöd ezt követően eltávolítja magáról
(lásd a 12. fejezetet).

Több eszközön ma különböző identitásokat használhatsz (10. fejezet).

### Kulcsok cseréje

Ha gyanítod, hogy valaki a kulcsaidhoz jutott, az „Eszközök kezelése" ->
„Kulcsok cseréje" alatt új kulcsokat állíthatsz elő. A kapcsolataid
értesítést kapnak, a nyitott meghívóid visszavonásra kerülnek. Fontos:
ezután a 24 szó önmagában csak a régi kulcsokat állítja elő. Csinálj ezért
közvetlenül utána új helyreállítási csomagot; helyreállítani akkor már csak
ezzel a csomaggal együtt tudsz.

---

## 12. Helyreállítás

### A seed-kifejezés használata

Ha elveszíted a készülékedet, vagy újat állítasz be:

1. Telepítsd a Cleonát az új készülékre.
2. Válaszd induláskor a „Helyreállítás" lehetőséget.
3. Írd be a 24 szavadat.
4. A Cleona ebből az összes identitásodat újra előállítja -- ugyanazokkal a
   kulcsokkal, mint korábban. A kapcsolataid számára ugyanaz az ember maradsz.

### Mi jön vissza -- és mi nem

Az identitásod benne van a 24 szóban, a kapcsolataid és az előzményeid
nem. Visszajön a hálózati hozzáférésed a **Helyreállítási csomag**
révén: A készüléked letesz egy kis, titkosított csomagot a hálózatban. Csak
a 24 szavad tudja megtalálni és kinyitni. Benne áll, amire az új
készülékednek szüksége van, hogy újra elérje a kapcsolataidat, és azt,
ami időközben a hálózatban várakozott rád. Ehhez nem kell, hogy egyetlen
kapcsolat is online legyen.

Az eddigi csevegés-előzményeket egy helyreállítás nem hozza vissza.

A helyreállítási csomag 7 napig él, és a készüléked megújítja, amíg fut; a
beállításokban látod, meddig érvényes. Ha több mint 7 napig egyetlen
készüléked sem futott, lejárt. A 24 szó akkor is helyreállítja az
identitásodat, de a kapcsolataidat újra meg kell hívnod; ami időközben a
hálózatban várakozott rád, az elveszett.

### A helyreállítás költözést jelent

Ha az eddigi készüléked később észleli, hogy az identitást máshol állították
helyre, eltávolítja magánál -- az előzményeivel együtt. Ezért: akinél a 24
szavad van, így elviheti az identitásodat a készülékedről. Amíg minden
kapcsolat vissza nem érkezik, az alkalmazás emlékeztet; a „Befejezés és
kulcsmegújítás" gombbal magad fejezed be a helyreállítást.

### Amit senki sem tud helyreállítani

Ez fontos, és ezért egyértelműen mondjuk:

- **Rajtad kívül senki sem tudja helyreállítani az identitásodat.** Sem a
  fejlesztő, sem egy ügyfélszolgálat, és a kapcsolataid sem -- bármennyien is
  legyenek. Nincs masterkulcs és nincs olyan darabja a kulcsodnak, amely
  másnál lenne letétben.
- **Ha elvesztetted a 24 szót és nincs több készüléked, az identitásod
  elveszett.** Akkor csak az marad, hogy újat hozol létre, és a kapcsolataidat
  újból meghívod.

A legjobb védelem: írd fel a 24 szót papírra, és őrizd biztonságban.

---
## 13. Beállítások

A beállításokat a fogaskerék-szimbólumon keresztül éred el a jobb felső sarokban.

### Értesítések és csengőhangok

- Válassz hat különböző csengőhang közül a beérkező hívásokhoz.
- Állíts be egy üzenethangot.
- Android-készülékeken emellett be- vagy kikapcsolhatod a rezgést.
- **„Minden némítása"** ezen a készüléken egyetlen üzenetet sem hagy
  csöngeni, rezegni vagy jelentkezni -- az összes identitásra. A hívások
  tovább csengenek.
- **„Csendes órák"**-at identitásonként állítod be Kezdet/Vég értékekkel.
  Ebben az időben egyetlen üzenet sem cseng, sem rezeg, sem jelentkezik ezen az
  identitáson; az üzenetek ettől még megérkeznek.
- **„Értesítések tartalom nélkül"** (alapértelmezés: ki) csak azt mutatja,
  hogy üzenet, meghívó vagy emlékeztető érkezett -- feladó, név és szöveg
  nélkül. A hívások továbbra is a nevet mutatják.
- Amit az indítás után egyszerre érkezik meg, azt a Cleona összesített
  értesítésben jelenti („5 új üzenet 2 beszélgetésben"); minden későbbi
  egyenként. Egy üzenet-értesítésre koppintva megnyílik a beszélgetés, akár
  egy másik identitásban is.

### Dizájnok (skinek)

A Cleona tíz különböző dizájnt kínál: Teal, Ocean, Sunset, Forest, Amethyst,
Fire, Storm, Slate, Gold és Contrast. A Contrast-dizájn a legmagasabb
akadálymentességi szintet (WCAG AAA) teljesíti, és korlátozott látás esetén
különösen jól olvasható.

Minden identitásnak saját dizájnja lehet. A dizájnt az identitás-részletek
oldalán módosítod (koppints az aktív identitás-fülre).

Emellett a beállítások „Megjelenés" szakaszában váltogathatsz a világos, a
sötét és a rendszer témája között.

### Nyelv megváltoztatása

A Cleona 34 nyelven elérhető, köztük jobbról-balra író nyelveken is (pl. arab,
héber). A nyelvet a beállítások „Nyelv" szakaszában módosíthatod.

### Média-archiválás

Ha otthon van egy hálózati tárolód (NAS) vagy egy megosztott mappád, a Cleona
a médiáidat automatikusan oda helyezheti ki. Támogatott az SMB, SFTP, FTPS
és WebDAV.

A fokozatos tárolás így működik:
- Az első 30 nap: Minden megmarad a készülékeden.
- 30 nap után: Egy előnézeti kép megmarad a készüléken, az eredeti
  archiválásra kerül.
- 90 nap után: Már csak egy kis előnézeti kép marad a készüléken.
- Egy év után: Már csak egy helykitöltő marad, az eredeti biztonságosan az
  archívumban fekszik.

Bármikor rákoppinthatsz egy archivált médiára, hogy visszahozd -- feltéve, hogy
csatlakozol a házi hálózatodhoz. A különösen fontos médiákat rögzítheted, hogy
soha ne kerüljenek kihelyezésre.

A „Tárhely költségkeret" alatt állítod be, hány MB média maradjon a
készüléken (alapértelmezés: 100 MB a telefonon, 2 GB a számítógépen). Ha
megtelt, a legrégebbi, nem rögzített média archiválódik először. Egy
eredetit csak akkor töröl a Cleona, ha biztonságosan az archívumban van --
a szöveges üzenetek mindig megmaradnak.

### Leiratozás a hangüzenetekhez

Ha engedélyezve van, a hangüzeneteid helyileg, a készülékeden szöveggé
alakulnak (a nyílt forráskódú Whisper modellel). Az átiratolt szöveg a
felvétellel együtt a partneredhez kerül. A leiratozás teljesen a
készülékeden történik -- nem megy adat külső szolgáltatásokhoz.

Melyik modell (tiny, base, small) töltődik le, azt egyszer, a készülékre
állítod be; a nyelvet (automatikus vagy rögzített) identitásonként.

### Automatikus letöltés

Beállíthatod, milyen mérettől legyenek a médiák automatikusan letöltve. Így
például a képeket automatikusan töltheted, de a nagy videóknál manuálisan
dönthess.

### Eszközök

Az „Eszközök" -> „Eszközök kezelése" alatt látod ezt az eszközt. Egy további
eszköz párosítása egy későbbi verzióval jön (11. fejezet).

### Hálózat

A Cleonának nincs szüksége hálózati beállításokra a működéshez. Három
hálózati kapcsoló van:

- **Porttovábbítás a routeren** (alapértelmezés: be). A Cleona kéri a saját
  routeredet, hogy nyisson egy ajtót a Cleonának. Ha sikerül, a készüléked
  mások számára jobban elérhető, és segíti a hálózatot. A Cleona közben csak a
  te routereddel beszél, nem az internettel.
- **Nyilvános címbejegyzések** (alapértelmezés: be). Ha a készülékednek még
  túl kevés szomszédja van, egy nyilvános címtárban (Nostr) keres további
  belépési pontokat, és ha ő maga jól elérhető, ott bejegyezi magát. A bejegyzés
  egy címet tartalmaz, nem nevet és nem kapcsolatot. Ha kikapcsolod, a
  készüléked csak meghívókon, a helyi hálózaton és a már ismert szomszédokon
  keresztül talál szomszédokat.
- **Kevesebb álcacsomag a Wi-Fi-ben** (alapértelmezés: ki). Wi-Fi-n vagy kábelen
  kikapcsolhatod az üres álcacsomagokat. De akkor ismét látszik, mikor írsz.
  Mobilon ez a kapcsoló nem létezik -- ott a Cleona amúgy is csak álcacsomagot
  küld percenként.

Az álcaforgalmat egészként nem lehet kikapcsolni. Ez szándékos: csak ha mindig
fut, nem mond semmit a készüléked aktivitása arról, hogy épp írsz-e.

A három kapcsoló fölött található az **Adattakarékos mód**: Mobilhálózaton a
Cleona javasolja, de sosem kapcsolja be magától. Adatot spórol, cserébe a
készüléked kívülről könnyebben felismerhető.

Alatta állítod be a **„Gyorsítótár mások médiájához"** méretét: A
készüléked legfeljebb 7 napig őrzi mások médiáinak titkosított darabjait,
hogy elérjék a címzettjüket (alapértelmezés: 100 MB a telefonon, 1 GB a
számítógépen). Egy kisebb méret azonnal felszabadítja a helyet -- a
legrégebbi darabok először.

---

## 14. Biztonság

### Mit jelent a post-kvantum titkosítás?

A mai titkosítás olyan matematikai problémákon alapul, amelyek normál
számítógépek számára rendkívül nehezen megoldhatók. A kvantumszámítógépek a
jövőben némelyik problémát gyorsan megoldhatják. A post-kvantum titkosítás
olyan eljárásokat is használ, amelyek a kvantumszámítógépeknek is ellenállnak.

A Cleona mindkét megközelítést ötvözi: klasszikus titkosítást a
megbízhatóságért és post-kvantum eljárásokat a jövőbiztonságért. Így egyszerre
vagy védve a jelenlegi és a jövőbeli fenyegetésekkel szemben.

Minden egyes üzenethez egy saját kulcs jön létre. Még ha egy támadó fel is
törné egy üzenet kulcsát, azzal nem tudna másik üzenetet elolvasni.

### Miért biztonságosabb a szerver hiánya

A hagyományos üzenetküldőknél az üzeneteid a szolgáltató szerverein keresztül
mennek. Még ha ott titkosítottak is lennének: a szolgáltató hozzáfér a
metaadatokhoz (ki mikor kommunikál kivel, milyen gyakran, honnan), és ezeket
esetleg bírósági intézkedésre ki kell adnia.

A Cleonánál nincs ilyen központi pont. Nincs olyan hely, ahol az összes
metaadat összefut, és nincs olyan címtár, amelyben utána lehetne nézni, ki vagy
vagy kit ismersz.

### Ki látja, hogy valakivel írsz?

A titkosítás védi, **mit** írsz. Ugyanilyen fontos, hogy egyetlen megfigyelő se
tudja meg, **kivel** és **mikor** írsz. Ezt a Cleona így biztosítja:

- **Az interneten soha nem közvetlenül.** Ha a készüléked közvetlenül a
  partnered internetcímére küldené az üzenetet, a szolgáltatód láthatná, hogy
  kivel írsz. Ezért az interneten egy üzenet mindig az állandó szomszédokon
  keresztül megy: a tieden és a partneredén.
- **Szomszédok, akikben megbízol.** Az állandó szomszédjaid, ahol csak lehetséges,
  a saját kapcsolataid készülékei -- legfeljebb három, amelyek épp kívülről
  elérhetők. Ha egy kiesik, egy másik kapcsolat lép a helyébe. Egy kapcsolatot
  nem lehet szerverekkel megvenni; egy tetszőleges csomópontot a hálózatban
  igen. Ha még nincs elérhető kapcsolatod, a Cleona egy másik szomszédot választ.
  A meghívód sosem nevez meg egyetlen kapcsolatodat sem, hogy senki ne
  tudja meg rajtuk keresztül egy barátod címét.
- **Kódok nevek helyett.** A szomszédok nem neveket és nem azonosítókat látnak,
  hanem csak egy kódot. Pontosan rátok kétőtöző érvényes, egy irányba, egy
  napra -- a következő napon már egy másik. A szomszédod tudja, honnan jön a
  csomag, de nem, hová megy végül. A partnered szomszédja tudja, hová megy,
  de nem, honnan jött. Normál esetben senki útközben nem látja mindkét véget.
- **Az álcaforgalom.** A készüléked folyamatosan, szabálytalan időközökben
  álcacsomagokat küld a szomszédjainak. Ugyanakkora mint az igazi csomagok,
  ugyanazon a porton mennek, és kívülről nem lehet őket megkülönböztetni az
  igaziaktól. Hogy épp egy ember ír, vagy a készülék csak fut, így nem
  megállapítható. Az üzeneteid sosem várnak az álcaforgalomra -- azonnal
  indulnak, az csak mellette fut.

**Mit költsz az álcaforgalom:** Wi-Fi-n körülbelül 13 MB naponta. Mobilon a
Cleona csak álcacsomagot küld percenként, ez napi kb. 1,7 MB. A mobilon történő
fojtás oka nem az adatmennyiség, hanem az akku: minden csomag felébreszti a
rádiómodemet.

**Mit nem tud elrejteni a Cleona** -- őszintén:

- Egyetlen **megfigyelő** sem látja, ki kivel ír -- sem a szolgáltatód, sem a
  csomópontok útközben. Aki viszont **mindkét véget egyszerre** figyeli, például
  egy állam, amely a te csatlakozásodat és a partneredét figyeli, vagy mindkét
  szomszédot lecsapja, az idővel hozzárendelhet: nálad csomag ki, röviddel
  utána a partnerednél csomag be. Elég gyakran megismételve ez egy kapcsolatot
  ad ki.
- Az álcaforgalom megnehezíti ezt a hozzárendelést, de nem akadályozza meg.
  Egyedi üzeneteket rejt, nem a mennyiséget: aki nagyon sokat küld, növeli a
  készüléke összforgalmát.
- Egy kapcsolat, amely az állandó szomszédod, megtudja, **mikor** és **mennyit**
  küldesz és fogadsz -- nem azt, hogy kivel, és nem azt, hogy mit. Ha a veszély
  a saját környezetedből fenyeget, minden kapcsolatot kivehet ebből (lásd a 3.
  fejezet „Soha ne állandó szomszédként használni" szakaszát).
- Ha két új felhasználónak csak ugyanaz az egy szomszédja van, az üzenetük
  pontosan ezen a csomóponton megy át, és ő mindkét véget látja. Amint egyiküknek
  további szomszédjai lesznek, ennek vége.
- A meghívód tartalmazza az internetcímeidet. Akinél a szövegsor van, látja,
  hol vagy online -- csak olyan embereknek add, akiben megbízol ebben.
- Egy szomszéd, aki továbbít, látja, hogy két kód csomagokat cserél -- nem
  azt, ki áll mögötte, és nem azt, mi van benne.
- Egy folyamatban lévő hívás jele, ha az első szomszéd épp nem válaszol,
  egy olyan csomóponton mehet át, amely mindkét véget látja; megtudja, hogy
  együtt telefonáltok.
- Egy nagy fájlt, amelyet jóváhagytál, a gép, amely továbbítja vagy tárolja,
  mindkét végén lát (lásd a 4. fejezetet).
- Hívásoknál a szolgáltató elleni védelem nem érvényesül, és a kapcsolatod
  látja az internetcímedet (lásd a 7. fejezetet).

### Mi történik, ha a partnered offline van?

1. A Cleona egyszerre elindítja az összes megfelelő utat: ugyanabban a Wi-Fi-ben
   közvetlenül, az interneten két szomszédon keresztül -- és emellett a
   postafiókot.
2. A postafiókhoz a Cleona a titkosított üzenetet három szomszédnál teszi le.
   Amint kettő visszaigazolja a kézbesítést, letettnek minősül.
3. A Cleona ehhez előnyben részesíti azokat a szomszédokat, amelyeknél a
   partnered is utánanéz -- először azt a szomszédot, amelyet a meghívója nevez
   meg.
4. Az üzenet ott várakozik legfeljebb 7 napig. Ha a partnered visszatér, ő
   felmenti, és visszaigazolja neked a kézbesítést. Csak akkor látsz két pipát.

A postafiókot csak a partnered tudja kiüríteni: a felemelés és a törlés csak
egy olyan kulccsal megy, amely csak neki van, és a törlés csak akkor történik,
amikor visszaigazolta a kézbesítést. A szomszédok csak titkosított csomagokat
látnak egy olyan érték alatt, amely minden nap változik.

### Idegenek nem jutnak át

Valakitól, aki sem a kapcsolatod, sem egy közös csoport tagja, a Cleona
pontosan két dolgot elfogad: a
kérdést a nyilvános kulcsaid felől, amíg az egyik meghívód nyitva van, és egy
kapcsolatkérést. A kérésnek érvényes meghívót kell hordoznia tőled, és a
feladónak előbb meg kell oldania egy számítási feladatot. Minden más --
üzenetek, hívások, fájlok -- elvetésre kerül, mielőtt az alkalmazást egyáltalán
elérné. Aki csak a nyomtatott névjegykártyádat megvan, az tehát nem tud
egyszerűen felhívni. Egy közös csoport tagja csak ebben a csoportban ér el
-- csoportüzenetekkel és csoportos hívásokkal, soha egyénileg.

### Anti-cenzúra

A Cleona úgy van felépítve, hogy nehéz legyen blokkolni:

- **Nincs szerver, nincs fix cím.** Az alkalmazásban nem szerepel cím, amelyet
  le lehetne tiltani, és a hálózat nem függ egyetlen csomóponttól sem.
- **Nincs fix port.** Minden készülék az első indításkor egy véletlenszerű
  portot választ. Nincs ismert portszám, amelyen a Cleona-forgalmat fel lehetne
  ismerni.
- **Mint véletlen adatok.** Két készülék között a kapcsolatfelvétel úgy van
  kódolva, hogy véletlen adatoktól nem lehet megkülönböztetni.
- **Sok belépés.** Minden meghívó, minden szomszéd és minden készülék ugyanabban
  a Wi-Fi-ben egy lehetséges út vissza a hálózatba.

### Biztonságos kulcstárolás

A támogatott platformokon a Cleona a titkosítási kulcsaidat az operációs
rendszer biztonságos kulcstárolójában tárolja (Android Keystore, iOS Keychain,
macOS Keychain). Ahol elérhető, ez hardveres védelmet kínál a kulcsaidnak.

### Adatbázis-titkosítás

Az üzeneteid és beszélgetéseid egy titkosított adatbázisban fekszenek --
identitásonként egy külön, mindegyik saját kulccsal. Nemcsak maga az
adatbázis titkosított, hanem a köztes fájljai is; semmi sem kerül
titkosítatlanul a lemezre, még rövid időre sem. A beállítások, kapcsolatok és
médiák szintén titkosítva tárolódnak.

A kulcsok a 24 szavadból származnak, és csak a készülékeden léteznek. Még ha a
készülékedbe valaki hozzá is jut és kiolvassa az adatokat, ezek nélkül a
kulcsok nélkül csak olvashatatlan adatokat talál.

Csak ott lesz titkosítatlan, ahol te magad viszel ki tartalmat a Cleonából:
- amikor egy fájlt egy csevegésből a készülékedre mentesz,
- amikor a képernyőkép-gombbal egy képet a képeid közé teszel,
- amikor megosztasz valamit egy másik alkalmazással,
- amikor beállítod a média-archiválást (13. fejezet): az archivált eredetek
  titkosítatlanul fekszenek a házi hálózati tárolódon, hogy ott Cleona
  nélkül is meg tudjad nyitni őket,
- amikor az eseményeket az Android rendszer-naptárba tükrözöd: ott más,
  naptárhoz hozzáférő alkalmazások olvashatják őket.

Ami így kikerült, nem törlődik az üzenettel együtt, és nem jár le vele.

### Védelem a képernyőn

Androidon, Windowsban és macOS-en a Cleona nem engedélyezi más
alkalmazásoknak a képernyőfelvételt. Ha kell egy kép, használd a felső sávban
lévő képernyőkép-gombot: a képet a képeid közé teszi -- titkosítatlanul.
Egy olyan beszélgetésben, amelyben a továbbítás nincs engedélyezve, nincs
képernyőkép.

---

## 15. Szoftverfrissítések

### Hogyan kapok frissítéseket?

A Cleona többféleképpen frissíthető. A cél, hogy akkor is kapj frissítéseket,
amikor egyes terjesztési útvonalak kiesnek vagy blokkolódnak:

1. **App Store / Play Store:** Amint a Cleona megjelenik ott, és egy áruházon
   keresztül telepítetted, a frissítéseket megszokott módon az áruházon át
   kapod. Az iPhone-on a frissítések TestFlighton át jönnek.
2. **GitHub Releases:** A projekt GitHub-oldalán aláírt telepítőcsomagokat
   találsz minden platformra.
3. **Frissítések a hálózaton keresztül:** A Cleona közvetlenül a hálózaton
   keresztül is kérhet frissítést -- letöltő-szerver nélkül. Az új verzió
   hibajavított darabokra van bontva, amelyek a hálózatban szétterjednek; egy
   részük még az álcaforgalomban is utazik. A készüléked elég darabot gyűjt, és
   összeállítja a frissítést. Átvitelre többnyire csak a változás kerül --
   néhány MB a teljes alkalmazás helyett. Ez Linuxra, Windowsra és Androidra
   érvényes; macOS-en az új verziókat a weboldalról vagy a GitHubról töltöd le.
4. **Meghívó linkek:** Készíthetsz meghívó linkeket, amelyek mindent
   tartalmaznak, amire egy új felhasználónak szüksége van a Cleona telepítéséhez
   és a hálózathoz való csatlakozáshoz.
5. **Fizikai átvitel:** Internet nélküli környezetben a Cleonát USB-szalagon
   vagy a helyi hálózaton keresztül is átadhatod másoknak.

### Így fut egy frissítés

1. A Cleona automatikusan a háttérben gyűjti egy új frissítés darabjait, és
   állítja össze őket.
2. Csak amikor a frissítés **teljes**, és az **aláírása ellenőrizve** lett,
   ajánlja fel a Cleona neked. Így sosem kapsz fél vagy ellenőrizetlen
   frissítést.
3. Ha a „Telepítés" gombra koppintasz, a telepítés további rákérdezés nélkül
   elindul. Androidon emellett a rendszer is mutatja a telepítő ablakát.

Régebbi verziók nem kerülnek felajánlásra -- egy frissítés mindig csak előre
megy. Ha egy verzió olyan régi, hogy már nem tud együttműködni a hálózattal, a
Cleona ezt egyértelműen jelzi, és kér, hogy frissíts.

### Aláírás-ellenőrzés

Minden frissítés kétszeresen aláírt: egy klasszikus és egy post-kvantum
eljárással. A Cleona automatikusan ellenőrzi mindkét aláírást. Így biztosított,
hogy csak a hivatalos fejlesztőtől származó frissítések kerüljenek elfogadásra --
még akkor is, ha a frissítés a hálózaton keresztül idegen készülékektől jött.
Egy frissítés sosem jön létre automatikusan a fejlesztésből, hanem csak akkor,
amikor a fejlesztő kézzel aláírja.

---
## 16. Gyakori kérdések

### „Használhatom a Cleonát internet nélkül?"

A Cleonának hálózati kapcsolatra van szüksége, de nem feltétlenül internetre:
ugyanabban a Wi-Fi-ben a Cleona-készülékek önmaguk is megtalálják egymást, és
internetelérés nélkül is tudnak egymással írni. Ugyanakkor online lenni a
partnereddel nem kell: ha offline van, az üzenet legfeljebb 7 napig várakozik
három szomszéd postafiókjában, amíg fel nem médi.

### „Mi van, ha elveszítem a seed-kifejezésemet?"

Amíg egy készülék még fut az identitásoddal, semmi sem veszett el -- ott
egyszerűen írsz tovább. Abban a készülékben, amelyen az identitást létrehoztad,
a 24 szót többnyire újra le is olvashatod (lásd a 2. fejezetet). Ne hagyatkozz
erre: egy újratelepítés eltünteti ezt a másolatot, és Androidon a képernyőzár
eltávolítása vagy megváltoztatása is megsemmisíti. Ha se a szavak,
se egy készülék nincs már, nincs visszaút -- a kapcsolataidon, a fejlesztőn
vagy bárki máson keresztül sem. Ezért olyan fontos a 24 szót biztonságban
őrizni.

### „Valaki elolvashatja az üzeneteimet?"

Nem. Minden üzenet egy olyan egyszeri kulccsal titkosított, amely csak erre
az egy üzenetre érvényes. Csak te és a partnered tudjátok visszafejteni az
üzenetet. Nincs központi szerver, nincs masterkulcs és nincs hozzáférés a
fejlesztő számára. Még ha egy készülék útközben továbbítja is az üzenetet, csak
titkosított adathalmazt és egy kódot lát. A szomszédod tudja, hogy a csomag
tőled jön, de nem, hová megy; a partnered szomszédja tudja, hová megy, de
nem, kitől.

### „Miért nincs szükségem telefonszámra?"

Mert az identitásod tisztán kriptográfiai. Egy telefonszám vagy e-mail-cím
helyett, amely a valódi nevedhez van kötve, egy olyan kulcspár azonosít, amely
a készülékeden jött létre. A kapcsolatokat QR-kóddal, NFC-fel vagy a meghívód
szövegsorával adod hozzá -- nem egy telefonkönyvön keresztül. Ez több
magánszférát jelent, mert az üzenetküldő-fiókod nincs a valós identitásodhoz
kötve.

### „Hogyan találok embereket a Cleonán?"

A Cleonában szándékosan nincs kapcsolatkeresés telefonszám vagy név szerint --
ez magánszféra-probléma lenne. Ehelyett a meghívókat közvetlenül cserélitek ki:
QR-kóddal, NFC-fel vagy szövegsorként egy másik úton keresztül. Ez olyan, mint
névjegykártyák cseréje a telefonkönyvben való keresés helyett.

### „Működik a Cleona külföldön is?"

Igen. Amíg van internetkapcsolatod, a Cleona a világ minden táján működik.
Mivel nincs központi szerver és nincs fix cím, a szolgáltatás nem kapcsolható
le egyszerűen bizonyos országokra. Hogyan nehezíti meg a Cleona a blokkolást,
arról a „Biztonság" fejezet „Anti-cenzúra" szakaszában olvashatsz. Egy olyan
ország, amely minden ismeretlen forgalmat a határon blokkol, viszont a
Cleonát is megállíthatja.

### „A Cleona ingyenes?"

Igen. A Cleona ingyenes és reklám nélkül használható. Mivel nincs központi
szerver, üzemeltetési szerverköltségek sem merülnek fel. A beállításokban a
„Támogasd a Cleonát" -> „Adományozás" alatt önkéntesen támogathatod a
fejlesztést.

### „Az üzenetemnek csak egy pipája van -- mit jelent ez?"

Az üzenet úton van, de a partnered még nem igazolta vissza a kézbesítést --
legtöbbször, mert épp offline. Ez nem hiba: az üzenet legfeljebb 7 napig a
postafiókban várakozik. Amint felmédi, két pipát látsz. Egy óra azt jelenti,
hogy még egyetlen út sem vitte el az üzenetet -- magától elindul, amint van
egy; egy figyelmeztető jel azt, hogy 14 napig nem talált utat, és újra
elküldheted.

### „Miért érkeznek késve az üzenetek az iPhone-omon?"

Az iOS nem engedi, hogy az alkalmazások véglegesen a háttérben fussanak. A
Cleonát csak időnként ébreszti fel rövid időre; hogy mikor, azt az iOS dönti
el. Ilyenkor mindent lekér. Amint megnyitod az alkalmazást, a Cleona lekéri,
amit neked megőriztek.

### „Átválthatok a WhatsApp-ról a Cleonára?"

Igen, de a WhatsApp-csevegéseidet nem tudod áthozni. A Cleona és a WhatsApp
alapvetően különböző rendszerek. A kapcsolataidat egyenként kell a Cleonához
hozzáadni. A legegyszerűbb, ha a meghívód szövegsorát elküldöd a kapcsolataidnak.
Minden így beérkező kérést te magad erősítesd meg a „Kérések" alatt.

### „Használhatom a Cleonát több eszközön egyszerre?"

Még nem. Egy második eszköz ugyanahhoz az identitáshoz egy későbbi verzióval
jön (11. fejezet). Több eszközön ma különböző identitásokat használhatsz.

### „Hogyan kapok frissítéseket, ha az áruház blokkolva van?"

A Cleona közvetlenül a hálózaton keresztül is kérhet frissítést, anélkül, hogy
egy áruházra, weboldalra vagy letöltő-szerverre támaszkodna. Ha egy másik
készülék a hálózatban a legújabb verzióval rendelkezik, a készüléked onnan is
letöltheti a frissítést. Az eredetiséget a fejlesztő digitális aláírásával
ellenőrzik. Alternatívaként egy kapcsolat is átadhatja neked az alkalmazást
meghívó linkkel vagy USB-szalagon. Erről bővebben a „Szoftverfrissítések"
fejezetben.

---

## Súgó és kapcsolat

Ha kérdésed van, vagy egy problémába ütközöl, aktuális információkat a
Cleona-weboldalon és a GitHubon találsz. Mivel a Cleona egy decentralizált
projekt, nincs klasszikus ügyfélszolgálat -- de van egy aktív közösség, amely
szívesen segít.

---

*Ez a kézikönyv a Cleona Chat 4.2-es verzióját írja le. Egyes funkciók újabb
verziókban megváltozhatnak vagy bővülhetnek.*
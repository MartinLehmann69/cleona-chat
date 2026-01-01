# Cleona Chat -- Felhasznaloi kezikonyv

Verzio 3.1.125 | Kelt 2026. julius

---

## Tartalomjegyzek

1. [Mi az a Cleona Chat?](#1-mi-az-a-cleona-chat)
2. [Elso lepesek](#2-elso-lepesek)
3. [Kontaktok](#3-kontaktok)
4. [Uzenetek](#4-uzenetek)
5. [Csoportok](#5-csoportok)
6. [Nyilvanos csatornak](#6-nyilvanos-csatornak)
7. [Hivasok](#7-hivasok)
8. [Naptar](#8-naptar)
9. [Szavazasok](#9-szavazasok)
10. [Tobb identitas](#10-tobb-identitas)
11. [Multi-Device](#11-multi-device)
12. [Helyreallitas](#12-helyreallitas)
13. [Beallitasok](#13-beallitasok)
14. [Biztonsag](#14-biztonsag)
15. [Szoftverfrissitesek](#15-szoftverfrissitesek)
16. [Gyakran ismetelt kerdesek](#16-gyakran-ismetelt-kerdesek)

---

## 1. Mi az a Cleona Chat?

### A te uzenetoalkalmazasod, a te adataid

A Cleona Chat egy uzenetoalkalmazas, amely teljesen kozponti szerver nelkul
mukodik. Az uzeneteid kozvetlenul a te keszulekedrol a masik fel keszulekere
jutnak el -- ceges kozvetitok, felho vagy adatkozpont nelkul. Egyetlen
vallalat sem tudja elolvasni, tarolni vagy tovabbitani az uzeneteidet,
egyszeruen azert, mert nincs kozbeiktatva egyetlen vallalat sem.

### Nincs fiok, nincs telefonszam

A Cleonaban nem kell sem telefonszam, sem e-mail-cim a regisztraciohoz. Az
identitasod egy kriptografiai kulcsparbol all, amelyet az elso indulaskor
automatikusan letrehoz a keszuleked. Ez azt jelenti: senki sem tud megtalalni
a telefonszamod vagy az e-mail-cimed alapjan, hacsak nem te adod meg onkent
az elerhetesegidet.

### Jovobiztonsagos titkositas

A Cleona ugynevezett Post-Quantum-titkositast hasznal. Ez azt jelenti: meg a
jovobeli kvantumszamitogepek sem lennenek kepesek feltorni az uzeneteidet. Nem
kell ertened a reszleteket -- a lenyeg az, hogy a kommunikaciod a technika
jelenlegi allasa szerint a leheto legjobban vedett.

### Hogyan mukodik szerver nelkul?

Kepzeld el, hogy te es a kontaktjaid egyutt alkottok egy halozatot. Minden
keszulek segit az uzenetek tovabbitasaban. Ha a masik fel eppen online, az
uzenet kozvetlenul megerkezik. Ha a masik fel offline, kozos ismerosok
kozvetitenek es kezbesitik, amint a cimzett ujra elerheto. A kontaktjaid
tehat egyben a halozatodat is jelentik.

### Platformok

A Cleona elerheto Android, iOS, macOS, Linux es Windows rendszerekre.

---

## 2. Elso lepesek

### Az alkalmazas telepitese

**Android:**
1. Toltsd le az APK-fajlt a Cleona weboldalrol vagy a GitHub Releases oldalrol.
2. Nyisd meg a fajlt a telefonodon. Ha szukseges, engedelyezd az ismeretlen
   forrasbol torteno telepitesest (az Android automatikusan rakerdez).
3. Koppints a "Telepites"-re es vard meg, amig a telepites befejezodik.

**iOS:**
1. Nyisd meg a TestFlight-meghivolinket az iPhone-odon.
2. Koppints a "Telepites"-re. A TestFlight az Apple hivatalos modja beta
   alkalmazasok terjesztesere.
3. A telepites utan a Cleonat megtalalodon a kezdokepernyodon.

**macOS:**
1. Toltsd le a DMG-fajlt a Cleona weboldalrol vagy a GitHub Releases oldalrol.
2. Nyisd meg a DMG-t es huzd a Cleonat a Programok mappaba.
3. Az elso indulaskor a macOS megkerdezheti, hogy meg akarod-e nyitni egy
   azonositott fejleszto alkalmazasat -- erositsd meg.

**Linux (Ubuntu/Debian):**
1. Toltsd le a .deb-fajlt a Cleona weboldalrol vagy a GitHub Releases oldalrol.
2. Telepitsd dupla kattintassal vagy a terminalban: `sudo dpkg -i cleona-chat_VERSION_amd64.deb`
3. Inditsd el a Cleonat az alkalmazasmenubol vagy a terminalban: `cleona-chat`

**Linux (Fedora/openSUSE):**
1. Toltsd le a .rpm-fajlt a Cleona weboldalrol vagy a GitHub Releases oldalrol.
2. Telepitsd: `sudo dnf install cleona-chat-VERSION.x86_64.rpm`
3. Inditsd el a Cleonat az alkalmazasmenubol vagy a terminalban: `cleona-chat`

**Linux (minden disztribucio -- AppImage):**
1. Toltsd le az .AppImage-fajlt a Cleona weboldalrol vagy a GitHub Releases oldalrol.
2. Tedd futtathatova a fajlt: jobb kattintas, Tulajdonsagok, Futtathato, vagy a terminalban: `chmod +x cleona-chat-VERSION-x86_64.AppImage`
3. Inditsd el dupla kattintassal vagy a terminalban: `./cleona-chat-VERSION-x86_64.AppImage`

**Windows:**
1. Toltsd le a telepitot a Cleona weboldalrol vagy a GitHub Releases oldalrol.
2. Futtasd a telepitofajlt es kovesd az utasitasokat.
3. Inditsd el a Cleonat a Start menubol vagy az asztali parancsikonrol.

### Identitas letrehozasa

Az elso indulaskor a Cleona automatikusan letrehoz egy uj identitast szamodra.
Megadhatsz egy megjelenesi nevet -- ez az a nev, amelyet a kontaktjaid latni
fognak. Ezt a nevet barmikor modosithatod.

### Seed-Phrase felirasa -- a legfontosabb teendo

Az identitasod letrehozasa utan a Cleona megmutat neked 24 szot. Ez a te
**Seed-Phrase-ed** -- a szemelyes helyreallitasi kulcsod.

**Ird fel ezt a 24 szot papirra es orizd biztonsagos helyen.**

Miert olyan fontos ez?

- Ha a telefonod elromlik, elveszik vagy ellopjak, ezzel a 24 szoval a
  teljes identitasodat helyreallithatod egy uj keszuleken.
- A Seed-Phrase nelkul nincs visszaut. Nincs "Elfelejtett jelszo" gomb es
  nincs ugyfelszolgalat, amely visszaadhatna a fiokod -- hiszen egyaltalan
  nincs fiok egyetlen szerveren sem.
- Soha ne add meg a Seed-Phrase-t masoknak. Aki ismeri ezeket a szavakat,
  az a te nevedben lephet fel.

A Seed-Phrase-t kesobb is megtekintheted a beallitasokban a "Biztonsag"
pont alatt, ha meg egyszer el szeretned olvasni.

### Elso kontakt hozzaadasa

Ahhoz, hogy valakivel csevegj, eloszor kontaktkent kell hozzaadnod az illetot.
Ehhez tobb lehetoseg is van -- mindet a kovetkezo fejezetben ismertetjuk.

---

## 3. Kontaktok

### QR-kod beolvasasa (ajanlott)

A legegyszerubb mod kontakt hozzaadasara:

1. A masik fel megnyitja az identitas-reszletek oldalt (koppintson a sajat
   nevere a felso savban) es megmutatja a QR-kodjat.
2. Te koppints a Plusz gombra es valaszd a "QR-kod beolvasasa" lehetoseget.
3. Tartsd a telefonodat a masik fel QR-kodja ele.
4. A kontaktkeres automatikusan elkuldesre kerul. Amint a masik fel elfogadja,
   mar irhattok egymasnak.

Ha szemelyesen talalkoztok, a QR-kod a legbiztonsagosabb modszer, mert
pontosan tudod, kivel cserelsz kontaktadatot.

### NFC (telefonok osszeertintese)

Ha mindket keszulek tamogatja az NFC-t:

1. Mindketten nyissatok meg a kontakt hozzaadasa funkciot.
2. Tartsatok a telefonokat hattal egymasnak.
3. A kontaktadatok automatikusan kicserelodnek.

Az NFC a QR-kodhoz hasonloan magas biztonsagot nyujt, mert a csere csak
akkor mukodik, ha fizikailag egymas mellett alltok.

### Link megosztasa (cleona://-URI)

A kontaktlinkedet e-mailben, SMS-ben vagy mas uzenetoalkalmazason keresztul
is elkuldheted:

1. Nyisd meg az identitas-reszletek oldalad.
2. Masold ki a cleona://-linked.
3. Kuldd el a linket annak a szemelynek, akinek hozza kell adnia teged.
4. A masik szemely megnyitja a linket, vagy beilleszti a kontakt hozzaadasa
   dialogusba.

Fontos: ennel a modszernel abban bizol, hogy a linket az atviteli uton nem
valtoztatta meg senki. Kulonosen erzekeny kontaktoknal a QR-kodot vagy az
NFC-t ajanjuk.

### Kontaktkelmek elfogadasa

Ha valaki kontaktkerelmet kuld neked, az megjelenik a bejovo uzenetek kozott
(az utolso ful az also savban). Itt a kovetkezoket teheted:

- **Elfogadas** -- a szemely felkerul a kontaktjaid koze.
- **Elutasitas** -- a keres elvetesre kerul.
- **Tiltas** -- a szemely nem kuldhet tobb kerest neked.

### Verifikacios szintek

A Cleona megmutatja, mennyire biztonsagosan van igazolva egy kontaktod
identitasa:

| Szint | Jelentes |
|-------|----------|
| Ismeretlen | Csak a Node-ID-t vagy egy linket kaptal. |
| Latott | A kulcscsere sikeres volt, titkositottan kommunikalhattok. |
| Verifikalt | Szemelyesen talalkoztatok es QR-koddal vagy NFC-vel igazoltatok egymast. |
| Megbizhato | Kifejezetten megbizhatokent jelolted meg ezt a kontaktot. |

Minel magasabb a szint, annal biztosabb lehetsz benne, hogy tenyleg a
megfelelo szemelylyel beszelsz.

---

## 4. Uzenetek

### Szoveg kuldese es fogadasa

Egyszeruen gepeld be az uzenetedet az also beviteli mezobe es nyomd meg az
Enter billentyut vagy a Kuldes gombot. Az uzeneted automatikusan
titkositasra kerul, mielott elhagyna a keszulekedet.

A bejovo uzenetek a csevegesi elozmenyekben jelennek meg. Egy pipa jelzi,
hogy az uzeneted kezbesitesre kerult-e.

### Kepek, videok es fajlok kuldese

Tobb lehetoseged is van:

- **Gembkapocs ikon** a beviteli mezoben: koppints ra, hogy fajlt, kepet
  vagy videot valassz a galeriadbol vagy a fajlrendszeredbol.
- **Drag and Drop** (asztali gepen): huzd a fajlt egyszeruen a csevegesi
  ablakba.
- **Beillesztes a vagolaprol** (asztali gepen): masolj egy kepet es
  illeszd be a csevegben.

Kis fajlok (256 KB alatt) kozvetlenul elkuldesre kerulnek. Nagyobb fajlok
ketlepcsos eljarassal kerulnek atvitelre: eloszor a fajl bejelentese, majd
reszenkent tortenik az atvitel.

### Hanguzenet

1. Tartsd lenyomva a Mikrofon gombot a beviteli mezoben.
2. Mond el az uzenetedet.
3. Engedd el a gombot az uzenet elkuldesehez.

Ha a keszulemekeden be van kapcsolva a beszedfelmeres (lasd Beallitasok), a
hanguzeneted automatikusan szovegge alakul. A masik fel igy a felvetelt es
az atirt szoveget is latja.

### Uzenetek megvalaszolasa (idezes)

Egy adott uzenetre valo valaszolashoz:

1. Nyisd meg a harom pontos menut az uzenet mellett.
2. Valaszd a "Valasz" lehetoseget.
3. A beviteli mezo felett megjelenik egy banner az idezett uzenettel.
4. Ird meg a valaszodat es kuldd el.

Az idezett uzenet megjelenik a valaszodban, igy egyertelmu az osszefugges.

### Uzenetek szerkesztese es torlese

- **Szerkesztes:** az uzenet harom pontos menujebol, majd "Szerkesztes".
  Modositsd a szoveget es kuldd el ujra. A masik fel latja, hogy az
  uzenetet szerkesztettek. A szerkesztes a kuldes utani 15 percen belul
  lehetseges.
- **Torles:** az uzenet harom pontos menujebol, majd "Torles". Az uzenet
  mind nalad, mind a masik felnel eltunik. A sajat uzeneteidet barmikor
  toriheted -- nincs idokorlat a torlesre.

### Emoji-reakciok

Valasz irasa helyett egy emojiival is reagalhatsz egy uzenetre:

1. Nyisd meg a harom pontos menut, vagy tartsd hosszan lenyomva az uzenetet.
2. Valassz egy emojit a gyorsvalasztekbol, vagy nyisd meg az emoji-valasztot
   a teljes kinalatert.
3. A reakciod megjelenik az uzenet alatt.

### Szoveg masolasa

Az uzenet harom pontos menujen keresztul az uzenet szoveget a vagolapra
masolhatod.

### Uzenetek keresese

A csevegesi ablak felso reszen talalhato a keresofunkcio. Adj meg egy
keresokifejezest, es a Cleona megmutatja az osszes talalatot az aktualis
csevegben. A nyilgombokkal lephetsz a talalatok kozott.

A kezdokepernyoen tovabba van egy fulek koze kiterjedt keresoszuro, amellyel
az osszes beszelgetesben kereshetsz egy kifejezesre.

### Link-elonezet

Amikor linket kuldesz, a Cleona automatikusan letrehoz egy elonezetet (cim,
leiras, elonezeti kep). Ezt az elonezetet a te keszuleked kesziti el es
kuldi az uzenettel egyutt -- a masik felnek nem kell kapcsolodnia a
linkelt weboldalhoz.

Ha egy kapott linkre koppintasz, a rendszer megkerdezi, hogy a normala
bongeszeben, inkognito modban vagy egyaltalan ne nyissad-e meg.

---

## 5. Csoportok

### Csoport letrehozasa

1. Valts a "Csoportok" fulre.
2. Koppints a Plusz gombra.
3. Adj nevet a csoportnak.
4. Valaszd ki a meghivni kivant kontaktokat.
5. Koppints a "Letrehozas"-ra.

A meghivott kontaktok ertesitest kapnak es csatlakozhatnak a csoporthoz.

### Tagok meghivasa

A letrehozas utan is meghivhatsz tovabbi kontaktokat:

1. Nyisd meg a csoportinfot (harom pontos menu a csoportattekintesben vagy
   felso sav a csoportos csevegben).
2. Koppints a "Meghivas"-ra.
3. Valaszd ki a hozzaadni kivant kontaktokat.

### Szerepkorok

Minden csoportban harom szerepkor letezik:

- **Tulajdonos (Owner):** teljes jogosultsaggal rendelkezik. Tagokat adhat
  hozza es tavolithat el, adminisztratorokat nevezhet ki es kezelheti a
  csoportot. A tulajdonos atruhazhata statuszat egy masik tagra is.
- **Adminisztrator:** tagokat tavolithat el es segithet az uzemeltetesben.
- **Tag:** uzeneteket olvashat es irhat.

### Csoport elhagyasa

1. Nyisd meg a harom pontos menut a csoportattekintesben.
2. Valaszd az "Elhagyas" lehetoseget.
3. Erositsd meg a dontesedet.

Ha elhagysz egy csoportot, a korabbi uzeneteid a tobbi tag szamara lathatoak
maradnak.

---

## 6. Nyilvanos csatornak

### Mik azok a csatornak?

A csatornak nyilvanos vitaforumok a Cleona-halozaton belul. A csoportokkal
ellentetben itt barki olvashatja az uzeneteket anelkul, hogy meghivast kapna.
Csak a tulajdonos es az adminisztratorok tehetnek kozze bejegyzeseket --
a feliratkozok olvasnak.

### Csatornak keresese es feliratkozas

1. Valts a "Csatornak" fulre.
2. Nyisd meg a "Kereses" fult.
3. Kergesd az elerheto csatornakat nev vagy tema alapjan.
4. Koppints egy csatornara, majd koppints a "Feliratkozas"-ra.

A csatornak nyelv szerint szurhetok. Egyes csatornak "Nem kiskoruaknak"
jelzessel vannak ellatva -- ezek csak akkor lathatoak, ha a profilodban
megerositetted, hogy 18 ev feletti vagy.

### Sajat csatorna letrehozasa

1. Valts a "Csatornak" fulre.
2. Koppints a Plusz gombra.
3. Adj meg egy csatornanevet (az egesz halozatban egyedinek kell lennie).
4. Valaszd ki a nyelvet es hogy a csatorna nyilvanos vagy privat legyen-e.
5. Opcionalis: adj hozza leirast es kepet.
6. Koppints a "Letrehozas"-ra.

Nyilvanos csatornaknal meghatarozhatod, hogy a tartalom "Nem kiskoruaknak"
besorolasu legyen-e.

### Tartalom bejelentese

Ha egy nyilvanos csatornaban nem megfelelo tartalmat latsz, bejelentheted
azt. A Cleona decentralizalt moderacios rendszert hasznal: a bejelenteseket
a halozat veletlenszeruen kivalasztott tagjai biraljak el (egyfajta
"eskudtszek"). Ha szabalysertest allapitanak meg, a csatorna figyelmeztetest
kap. Ismetelt szabalysertes eseten a keresesi indexben hatrebb sorolodik
vagy zarolasra kerul.

### Rendszercsatornak

A Cleona ket beepitett rendszercsatornaval rendelkezik:

- **Bug Log:** ha a Cleona hibat eszlel, megkerdezi, hogy szeretnel-e
  anonimizalt hibajellentest kuldeni. Ezek a jelentesek a Bug Log
  csatornaba kerulnek, ahol a kozosseg megtekintheti oket. Nem kerulnek
  szemelyes adatok atvitelre -- csak technikai hibairasok. Kezzel is
  kuldhetsz naplojellenteset (elonezeti dialogussal es kifejezett
  hozzajarulassal).
- **Feature Requests:** itt a felhasznalok funkciokivanssagokat nyujthatnak
  be es szavazhatnak a meglevo javaslatokra. A javaslatok szavazatok
  szerint rendezodnek.

Mindket rendszercsatorna 25 MB-os meretkorlattal rendelkezik es az
eskudtszek-moderacios rendszer felugyelete alatt all.

---

## 7. Hivasok

### Hanghivas inditasa

1. Nyisd meg a csevgest azzal a kontakttal, akit hivni szeretnel.
2. Koppints a telefon ikonra a felso savban.
3. Vard meg, amig a masik fel elfogadja a hivast.

A beszelgetes soran latod az idovonalat, a beszelgetes idejet, es
hasznalhatod a nemitas es hangszoro funkciot.

A hivas befejezesehez koppints a piros Lerakas gombra.

### Videohivas inditasa

1. Nyisd meg a csevgest a kontakttal.
2. Koppints a kamera ikonra a felso savban.
3. A te videokeped egy kis ablakban jelenik meg, a masik fel kepe a nagy
   teruleton.

A beszelgetes soran valtahatsz az elso es hato kamera kozott.

### Bejovo hivasok

Ha valaki hiv teged, egy ertesitesi ablak jelenik meg a hivo nevevel. A
kovetkezoket teheted:

- **Elfogadas** -- a beszelgetes megkezdodik.
- **Elutasitas** -- a hivo ertesitest kap.

Ha mar beszelgetsz valakivel, az uj hivas automatikusan elutasitasra kerul.

### Csoporthivasok

Csoporthivasokat is folytathatsz, amelyekben tobb szemely vesz reszt
egyidejuleg. A hivas egy intelligens tovabbitasi fan keresztul szervezodik,
igy nem szukseges, hogy minden resztvevo kozvetlenul csatlakozzon minden
masik resztvevohoz. Minden beszelgetes vegig titkositott.

### Titkositas hivasoknal

Minden hivast egyszer hasznalatos kulcsokkal titkositanak, amelyek csak a
beszelgetes idejetartamara leteznek. A lerakas utan ezek a kulcsok azonnal
torlodnek. Senki sem tudja utolagosan megfejteni egy korabbi beszelgetest.

---

## 8. Naptar

A Cleona rendelkezik egy beepitett naptarral, amely titkositottan es teljesen
decentralizaltan mukodik -- felhoszolgaltatas nelkul.

### Nezetek

A naptar ot nezetet kinal: Nap, Het, Honap, Ev es egy Feladat-nezet. Valts
koztuk a naptar kepernyojenek felso reszen levo fulekkel.

### Esemenyek letrehozasa

Koppints egy idosavra vagy hasznald a Hozzaadas gombot uj esemeny
letrehozasahoz. Megadhatsz cimet, datumot, idopontot, helyszint es
jegyzeteket. Az esemenyek titkositottan tarolodnak a keszulemekeden.

### Ismetlodo esemenyek

Az esemenyek ismetlodhetnek naponta, hetente, havonta vagy evente. A mintat
testre szabhatod (pl. minden masodik kedden, minden honap elsejen) es
megadhatsz vegdatumot vagy ismetlesszamot.

### Kontaktok meghivasa

Egy esemeny letrehozasakor vagy szerkesztesekor meghivhatod a
Cleona-kontaktjaidat. Ok titkositott naptarmeghivot kapnak es valaszolhatnak
elfogadassal, elutasitassal vagy talan-nal. Az esemenyen torteno valtozasok
automatikusan elkuldodnek minden meghivottnak.

### Szabad/Foglalt jelzes

Megoszthatod az elerhetosegedet a kontaktjaiddal anelkul, hogy az esemenyek
reszleteit felfedned. Harom adatvedelmi szint letezik: teljes reszletek,
csak idoblokkok vagy rejtett. Beallithatsz egy alapertelmezettet es
kontaktonkent felulirhatod.

### Emlekeztetok

Az esemenyek emlekeztetokkel lathatok el, amelyek az esemeny kezdete elott
rendszerertesitest valtsanak ki. Az emlekeztetoket szukseg eseten
halaszthatod.

### Kulso naptar-szinkronizalas

A Cleona kulso naptarszolgaltatasokkal is szinkronizalhato:

- **CalDAV** -- csatlakozz barmely CalDAV-kompatibilis szerverhez (Nextcloud,
  Radicale stb.).
- **Google Naptar** -- szinkronizalas a Google Calendar API-n keresztul
  biztonsagos OAuth2-hitelesitessel.
- **Helyi CalDAV-szerver** -- a Cleona kepes helyi CalDAV-szervert inditani
  a keszulemekeden, igy asztali naptaralkalmazasok (Thunderbird, Outlook,
  Apple Naptar, Evolution) szinkronizalhatnak a Cleona-naptaraddal.
- **Android-rendszernaptar** -- a Cleona esemenyei atvihetok az Android
  keszuleked beepitett naptaralkalmazasaba.
- **ICS-fajlok** -- esemenyek importalasa es exportalasa a szabvanyos
  iCalendar formatumban.

### PDF-export

Barmely naptarnezetet (Nap, Het, Honap, Ev) PDF-dokumentumkent
kinyomtathatod vagy exportalhatod.

---

## 9. Szavazasok

Barmely csevegben vagy csoportban letrehozhatsz szavazasokat, hogy
velemenyeket gyujts vagy idopontot egyeztess.

### Szavazastipusok

A Cleona ot szavazastipust tamogat:

- **Egyszeru valasztas** -- a resztvevok egy lehetoseget valasztanak.
- **Tobbszoros valasztas** -- a resztvevok tobb lehetoseget is
  kivalaszthatnak.
- **Idopontszavazas** -- talald meg az idopontot, ami mindenkinek megfelel.
  Minden resztvevo jeloli az idopontokat elerheto, talan vagy nem elerheto
  besorolassal.
- **Skala** -- ertekelj valamit egy numerikus skalan (pl. 1-tol 5-ig).
- **Szabad szoveg** -- a resztvevok sajat valaszukat irjak be.

### Szavazas letrehozasa

Nyiss meg egy csevgest es koppints a szavazas ikonra (vagy hasznald a
mellekeltek menut). Valaszd ki a szavazas tipusat, fogalmazd meg a kerdesed
es a lehetosegeket, es kuldd el a szavazast. Az uizenetkent jelenik meg a
csevegben.

### Szavazas leadasa

Koppints egy szavazasra a szavazatod leadasahoz. A szavazatodat barmikor
modosithatod vagy visszavonhatod.

### Anonim szavazas

A szavazasok konfiguralhatok anonim szavazasra. Ha ez be van kapcsolva, a
szavazatok kriptografiailag anonimek -- senki, meg a szavazas letrehozoja sem
lathatja, ki mire szavazott. A szavazatok szama ennek ellenere lathato marad.

### Idopontszavazas a naptarba

Ha egy idopontszavazas lezarult, a nyertes idopont egy koppintassal
kozvetlenul naptarbejegyezesse alakithato.

---

## 10. Tobb identitas

### Miert tobb identitas?

Kepzeld el, hogy szeretned kulonvalasztani a munkahelyi es a maganeletedet --
hasonloan ket kulonbozo telefonszamhoz, de masodik telefon nelkul. A Cleonaban
tobb identitast is hasznalhatsz egyetlen keszuleken. Minden identitasnak sajat
neve, sajat profilkepe, sajat kontaktjai es sajat beszelgetesei vannak.

### Uj identitas letrehozasa

1. A felso savban latod az aktualis identitasodat fulkent.
2. Koppints a plusz jelre (+) az identitas-fulek jobb oldalan.
3. Adj meg egy nevet az uj identitasnak.
4. Kesz -- az uj identitas azonnal aktiv.

### Valtas identitasok kozott

Egyszeruen koppints az identitas-fulre a felso savban. A valtas azonnali --
nincs varakozas, nincs ujratoltes.

### Minden egyszerre fut

Fontos pont: az osszes identitasod egyszerre aktiv. Meg ha eppen
"Munkahelyi"-kent jelensz is meg, a "Magan" identitasod tovabbra is fogadja
az uzeneteket. Semmit sem mulasztasz el, barmelyik identitas legyen is
kivalasztva.

### Identitas-reszletek oldala

Ha a jelenleg aktiv identitas fulere koppintasz, megnyilik a reszletek
oldala. Itt a kovetkezoket teheted:

- A QR-kodod megjelenitese kontaktok szamara.
- A profilkeped modositasa vagy eltavolitasa.
- Profleiras hozzaadasa.
- A megjelenesi neved modositasa.
- Egy dizajn (Skin) kivalasztasa ehhez az identitashoz.
- Az identitas torlese, ha mar nincs ra szukseged.

### Identitas torlese

Ha torolsz egy identitast, a kontaktjaid ertesitest kapnak rola. Az
identitas es az osszes hozza tartozo adat torlesre kerul a keszulekedrol.
Ez a muvelet nem visszafordithato.

---

## 11. Multi-Device

### A Cleona hasznalata tobb keszuleken

Ugyanazt az identitast akar 5 keszuleken is hasznalhatod egyidejuleg. Egy
keszulek a primaris (ez tartalmazza a Seed-Phrase-t), es tovabbi keszulekek
csatlakoztathatoak hozza.

### Uj keszulek csatlakoztatasa

1. Nyisd meg a beallitasokat a primaris keszulemekeden.
2. Menj az "Osszekapcsolt keszulekek" reszhez.
3. Valaszd az "Uj keszulek csatlakoztatasa" lehetoseget.
4. Telepitsd a Cleonat az uj keszuleken es az indulaskor valaszd a "Meglevo
   keszulekhez csatlakozes" lehetoseget.
5. Olvasd be a parosito QR-kodot, amely a primaris keszulemekeden jelenik meg,
   vagy hasznald a parosito linket.

A csatlakoztatott keszulek egy delegacios tanusitvanyt kap a primaris
keszulektol. A csatlakoztatott keszulekrol kuldott uzeneteket egy delegalt
kulcs irja ala kriptografiailag, igy a kontaktok ellenorizhetik, hogy az
uzenet valoban a te identitasodtol szarmazik.

### Hogyan mukodik

- A primaris keszulek tartalmazza a Seed-Phrase-t es a mester-kulcsokat.
- A csatlakoztatott keszulekek szarmaztatott alairo kulcsokat es egy
  delegacios tanusitvanyt kapnak -- soha nem kapjak meg magat a
  Seed-Phrase-t.
- Minden keszulek ugyanazt az identitast es kontaktokat hasznalja. Az
  uzenetek minden keszulekre megerkeznek.
- A delegacios tanusitanyok automatikusan megujulnak a lejaratuk elott.

### Keszulekkezeles

Nyisd meg a beallitasokat es menj az "Osszekapcsolt keszulekek" reszhez, hogy
lasd az osszes csatlakoztatott keszulekedet, azok allapotat es utolso
aktivitasat. Barmikor visszavonhatsz egy csatlakoztatott keszuleket, ha az
elveszik vagy ellopjak.

### Veszhellyzeti kulcsrotacio

Ha ugy velod, hogy egy keszulek kompromittalodott, veszhellyzeti
kulcsrotaciot indithatsz. Ennek soran uj kulcsok generalodnak, es a
rotaciot a tobbi keszuleked tobbsegenek meg kell erosetenie. Ez meggatolja,
hogy egyetlen ellopott keszulek egyedul forgasson kulcsokat.

---

## 12. Helyreallitas

### A Seed-Phrase hasznalata

Ha elveszited a keszulekedet vagy ujat allitasz be:

1. Telepitsd a Cleonat az uj keszulekre.
2. Az indulaskor valaszd a "Helyreallitas" lehetoseget.
3. Gepeld be a 24 szavadat.
4. A Cleona helyreallitja az identitasodat es automatikusan felveszi a
   kapcsolatot a korabbi kontaktjaiddal.
5. A kontaktjaid valaszolnak a kontaktadataiddal, csoporttagsagaiddal es
   uzenetelozmennyeiddel.

A helyreallitas harom lepesben tortenik:
- Eloszor a kontaktjaid es a csoportjaid jonnek vissza.
- Aztan az utolso 50 uzenet minden beszelgetesbol.
- Vegul a teljes uzenetelozmeny.

Elegseges, ha egyetlen kontaktod online van, hogy a helyreallitas mukodjon.

### Guardian Recovery (bizalmi szemelyek)

Akar ot bizalmi szemelyt is kijelolhetsz "Guardian"-kent. Ennek soran a
helyreallitasi kulcsod ot reszre osztodik, amelyekbol mindegyik Guardian
egyet kap. Az identitasod helyreallitasahoz harom az otbol elegseges.

Ez azt jelenti: meg ha el is vesztetted a Seed-Phrase-t, harom Guardianod
egyutt kepes helyreallitani a fiokodot. Egyetlen Guardian sem ferhet hozza
egyedul az adataidhoz -- mindig legalabb harom szukseges.

Igy allitsd be a Guardianokat:
1. Nyisd meg a beallitasokat.
2. Menj a "Biztonsag" reszhez.
3. Valaszd a "Guardian Recovery" lehetoseget.
4. Valassz ki ot megbizhato kontaktot.

### Miert a kontaktjaid a biztonsagi mentesed

A hagyomanyos uzenetoalkalmazasoknal az adataid a szolgaltato szerveren
vannak. A Cleona eseten nincs szerver -- de a kontaktjaid atveszik ezt a
szerepet. Amikor uzenetet kuldesz, a kozos kontaktok egy titkositott
masolatot tarolnak arra az esetre, ha a cimzett eppen offline. Helyreallitas
eseten a kontaktjaid visszaadjak az adataidat.

Ez azt jelenti: minel tobb aktiv kontaktod van, annal megbizhatoabb a
biztonsagi mentesed. Egyetlen kontakt, aki rendszeresen online van, elegseges
a sikeres helyreallitashoz.

---

## 13. Beallitasok

A beallitasokat a jobb felso sarokban levo fogaskerek ikonon keresztul
erheted el.

### Ertesitesek es csengohangok

- Valassz hat kulonbozo csengohang kozul bejovo hivasokhoz.
- Allits be uzenethangot.
- Android keszulekeken tovabba be- es kikapcsolhatod a rezgest.

### Dizajnok (Skinek)

A Cleona tiz kulonbozo dizajnt kinal: Teal, Ocean, Sunset, Forest, Amethyst,
Fire, Storm, Slate, Gold es Contrast. A Contrast dizajn megfelel a legmagasabb
akadalymentesitesi szintnek (WCAG AAA) es korlatozott latas eseten kulonosen
jol olvashato.

Minden identitas sajat dizajnnal rendelkezhet. A dizajnt az
identitas-reszletek oldalon valtoztathatod meg (koppints az aktiv
identitas-fulre).

Ezenkivul a beallitasokban a "Megjelenes" pont alatt valtahatsz vilagos,
sotet es rendszer-tema kozott.

### Nyelv megvaltoztatasa

A Cleona 33 nyelven elerheto, beleertve a jobbrol balra irt nyelveket
is (pl. arab, heber). A nyelvet a beallitasokban a "Nyelv" pont alatt
valtoztathatod meg.

### Tarolasi korlat

Meghatarozhatod, mennyi tarhelyet hasznalhat a Cleona a keszulemekeden
(100 MB es 2 GB kozott). Amikor a korlat eleresre kerul, a regebbi mediak
automatikusan kikerulnek vagy torlodnek -- a szoveges uzenetek mindig
megmaradnak.

### Media-archivalas

Ha otthon halozati tarhelyed (NAS) vagy megosztott mappad van, a Cleona
automatikusan oda archivalhatja a mediaidat. Tamogatott protokollok: SMB,
SFTP, FTPS es WebDAV.

Igy mukodik a fokozatos tarolas:
- Az elso 30 nap: minden a keszulemekeden marad.
- 30 nap utan: egy elonezeti kep marad a keszuleken, az eredeti archivalasra
  kerul.
- 90 nap utan: csak egy kis elonezeti kep marad a keszuleken.
- Egy ev utan: csak egy helyfoglalo marad, az eredeti biztonsagosan az
  archivumban van.

Barmikor koppinthatsz egy archivalt mediara, hogy visszatoltsd --
felteve, hogy csatlakozva vagy az otthoni halozatodhoz. Kulonosen fontos
mediakat rogzithetsz, hogy soha ne keruljenek archivalasra.

### Hanguzenet-atiras

Ha be van kapcsolva, a hanguzeneteid helyben, a keszulemekeden szovegge
alakulnak (a nyilt forrasu Whisper modellel). Az atirt szoveg a felvetellel
egyutt kerul elkuldesre a masik felnek. Az atiras teljes egeszeben a
keszulemekeden tortenik -- semmilyen adat nem kerul kulso szolgaltatashoz.

### Automatikus letoltes

Beallithatod, milyen merettol toltsek le automatikusan a mediakat. Igy
peldaul a kepeket automatikusan letoltetheted, de nagy videoknal kezzel
donthetsz.

### Osszekapcsolt keszulekek

Kezeld az osszekapcsolt keszulekeidet a beallitasok ezen reszeben.
Reszleteket lasd a Multi-Device fejezetben.

---

## 14. Biztonsag

### Mit jelent a Post-Quantum-titkositas?

A mai titkositas olyan matematikai problemakra epul, amelyek a hagyomanyos
szamitogepek szamara rendkivul nehezan megoldhatok. A kvantumszamitogepek a
jovoben ezek kozul nehanyet gyorsan megoldhatnak. A Post-Quantum-titkositas
tovabbi eljarasokat hasznal, amelyek a kvantumszamitogepeknek is ellenallnak.

A Cleona mindket megkozelitest kombinalja: klasszikus titkositast a
megbizhatosagert es Post-Quantum-eljarasokat a jovoallossagert. Igy
egyszerre vagy vedett a jelenlegi es a jovobeli fenyegetesek ellen.

Minden egyes uzenethez kulon kulcs generalodik. Meg ha egy tamado feltorne is
egy uzenet kulcsat, azzal semmilyen mas uzenetet nem tudna elolvasni.

### Miert biztonsagosabb szerver nelkul

A hagyomanyos uzenetoalkalmazasoknal az uzeneteid a szolgaltato szerveren
haladnak at. Meg ha titkositottak is lehetnek: a szolgaltato hozzaferhet a
metaadatokhoz (ki kommunikal kivel, mikor, milyen gyakran, honnan) es ezeket
korulmenyek kozott biroi vegzesre ki kell adnia.

A Cleona eseten nincs ilyen kozponti pont. Az uzeneteid kozvetlenul
keszulekrol keszulekre utaznak. Nincs olyan hely, ahol minden metaadat
osszefutna. Senki sem tudja egyetlen adatpont alapjan rekonstrualni a
kommunikacios szokasaidat.

### Mi tortenik ha offline vagy?

Ha uzenetet kuldesz es a cimzett offline:

1. A Cleona eloszor megprobjalja kozvetlenul kezbesiteni az uzenetet.
2. Ha ez nem sikerul, kozos kontaktokon keresztul tovabbitja.
3. Egyidejuleg az uzenet titkositott darabokra osztva tobb csomopontra
   kerul elosztasra a halozatban (hasonloan egy kirakoshoz, amely 10
   darabbol all, amelyekbol 7 elegseges a kep osszeallitasahoz).
4. Az uzenetet legfeljebb 7 napig tarolodik.

Amint a cimzett ujra online lesz, az uzenetek kezbesitodnek. Ertesitest
kapsz, ha az uzeneted megerezett.

### Cenzura elleni vedelem

Ha a halozatod blokkolja a szabvanyos kapcsolodasi modszert (UDP), a Cleona
automatikusan atvalt egy alternativ atvitelre (TLS), amelyet nehezebb
felismerni es blokkolni. Ez atlatszoan tortenik -- neked nem kell semmit
beallitanod.

### Biztonsagos kulcstarolas

A tamogatott platformokon a Cleona a titkositasi kulcsaidat az operacios
rendszer biztonsagos kulcstarojaban tarolja (Android Keystore, iOS Keychain,
macOS Keychain). Ahol elerheto, ez hardveres vedelmet biztosit a kulcsaid
szamara.

### Adatbazis-titkositas

Az osszes uzeneted, kontaktod es beallitasod titkositottan tarolodik a
keszulemekeden. Meg ha valaki hozzaferne is a fajlrendszeredhez, a
kriptografiai kulcsod nelkul semmit sem tudna olvasni. Ez a kulcs az
identitasodbol szarmazik es kizarolag a keszulemekeden letezik.

### Zart halozat

A Cleona zart halozatkent mukodik. Minden halozati csomag hitelesitett,
igy csak legitim Cleona-keszulekek vehetnek reszt. Ez meggatolja, hogy
kulso felek hamis uzeneteket juttassanak be vagy a halozati forgalmat
lehallgassak.

---

## 15. Szoftverfrissitesek

### Hogyan kapok frissiteseket?

A Cleona tobbfele modon frissitheto. A cel az, hogy akkor is frissiteseket
kaphass, ha egyes terjesztesi csatornak kiesnek vagy blokkolt lesz:

1. **App Store / Play Store:** ha a Cleonat egy App Store-bol telepitetted,
   a frissiteseket a szokasos modon a Store-bol kapod.
2. **GitHub Releases:** a projekt GitHub oldalon alirt telepitocsomagokat
   talalsz minden platformra.
3. **Halozaton beluli frissitesek:** ha a Cleona-halozatban egy masik
   felhasznalo mar rendelkezik a legujabb verzioval, a Cleona a frissittest
   kozvetlenul a P2P-halozaton keresztul szerezheti be -- kulso szerver
   nelkul. Az uj verzio hibajavitott fragmentumokra bontodik es tobb
   csomopontra oszlik el. A keszuleked osszegyujti a szukseges
   fragmentumokat es osszeallitja a frissittest. A hitelleseget a fejleszto
   Ed25519-alairasa igazolja.
4. **Meghivolinkek:** meghivolinkeket hozhatsz letre, amelyek mindent
   tartalmaznak, amire egy uj felhasznalonak szuksege van a Cleona
   telepitesehez es a halozathoz valo csatlakozashoz.
5. **Fizikai atadas:** internet nelkuli kornyezetben a Cleonat USB-kulcson
   vagy helyi halozaton keresztul is tovabbadhatod masoknak.

### Frissitesi ertesites

Ha uj frissites elerheto, a Cleona ertesitest jelez a kezdokepernyoon.
Ha a frissites a halozaton keresztul is elerheto (halozaton beluli
frissites), valaszthatsz, hogy kozvetlenul a halozatbol toltod le.

### Binaris terjesztes

Alapertelmezetten a keszuleked segit a frissitesek terjeszteseben mas
felhasznalok szamara a halozatban. Ha ezt nem szeretned, a beallitasokban
a "Halozat" pont alatt kikapcsolhatod ezt a funkciot. A frissitesi
fragmentumok tarolasanak merete korlatozott (5 MB mobilkeszulekeken, 20 MB
asztali gepeken) es rendszeresen takaritodik.

### Alairas-ellenorzes

Minden frissites kriptografiailag alirt. A Cleona automatikusan ellenorzi
az alairst, mielott egy frissites telepitesre kerulne. Igy biztositott,
hogy csak a hivatalos fejlesztotol szarmazo frissitesek kerulnek elfogadasra
-- meg akkor is, ha a frissites a P2P-halozaton keresztul erkezett.

---

## 16. Gyakran ismetelt kerdesek

### "Hasznalhatom a Cleonat internet nelkul?"

Nem, a Cleonanak halozati kapcsolat szukseges az uzenetek kuldesehez es
fogadasahoz. Ugyanakkor nem kell egyidejuleg online lenned a masik fellel:
az uzenetek, amelyeket a cimzett offline allapotaban kuldesz, tarolodnak es
automatikusan kezbesitodnek, amint mindket fel ujra csatlakozik. A helyi
halozatban (pl. ugyanabban a WLAN-ban) internet-hozzaferes nelkul is
kommunikalhattok egymassal.

### "Mi van ha elveszitem a Seed-Phrase-t?"

Ha beallitottad a Guardianokat, harom az ot bizalmi szemelybol egyutt kepes
helyreallitani a hozzaferesedet. Guardianok es Seed-Phrase nelkul sajnos
nincs mod az identitasod visszaszerzesere. Ezert olyan fontos a 24 szot
biztonsagosan megorizni.

### "Elolvashatja valaki az uzeneteimet?"

Nem. Minden uzenetet egyszer hasznalatos kulccsal titkositanak, amely csak
erre az egy uzenetre ervenyes. Csak te es a masik fel tudjatok megfejteni
az uzenetet. Nincs kozponti szerver, nincs mesterkulcs es nincs hozzaferes
a fejleszto szamara. Meg ha egy keszulek az atviteli uton tovabbitja is
az uzenetet, az csak titkositott adathalmazt lat.

### "Miert nincs szukseg telefonszamra?"

Mert az identitasod tisztan kriptografiai. Telefonszam vagy e-mail-cim
helyett, amely a valos nevedhez kotheto, egy kulcspar azonosit, amelyet a
keszulemekeden hoztak letre. Kontaktokat QR-koddal, NFC-vel vagy linkkel
adsz hozza -- nem telefonkonyvbol. Ez tobb maganszferat jelent, mert az
uzenetoalkalmazas-fiokod nincs a valos identitasodhoz kotve.

### "Hogyan talalhatok embereket a Cleonan?"

A Cleona tudatosan nem rendelkezik telefonszam vagy nev szerinti
kontaktkeresessel -- az adatvedelmi problema lenne. Ehelyett kozvetlenul
cserelsz kontaktadatot: QR-koddal, NFC-vel, cleona://-linkkel vagy
nyilvanos csatornakban. Ez olyan, mint nevjegykartya-csere a telefonkonyvben
valo keresgetees helyett.

### "Mukodik a Cleona kulfoldon is?"

Igen. Amig van internetkapcsolatod, a Cleona mindenhol mukodik a vilagon.
Mivel nincs kozponti szerver, a szolgaltatas nem blokkothato egyes orszagokra
vonatkozoan. A Cleona ezenfelul cenzura elleni fallbackkel is rendelkezik:
ha a normala kapcsolat (UDP) blokkolt, a Cleona automatikusan atvalt egy
alternativ atvitelre (TLS), amelyet nehezebb felismerni es blokkolni.

### "Ingyenes a Cleona?"

Igen. A Cleona ingyenes es reklam nelkul hasznalhato. Mivel nincs kozponti
szerver, szerverkoltsegek sem merulnek fel az uzemelteteshez. Az
alkalmazasban a "Tamogatas" pont alatt megtalalhato a lehetoseg a fejlesztes
onkentes tamogatasara.

### "Az uzentemnel egy orajel latszik -- mit jelent ez?"

Ez azt jelenti, hogy az uzeneted meg nem kerult kezbesitesre. A masik fel
valoszinuleg eppen offline. Amint az uzenet kezbesitesre kerul, a szimbolum
megvaltozik. Az uzenetek legfeljebb 7 napig tarolodnak a kezbesitesig.

### "Atvalhatok WhatsApp-rol Cleonara?"

Igen, de a WhatsApp-csevegesidet nem tudod atvinni. A Cleona es a WhatsApp
alapvetoen kulonbozo rendszerek. A kontaktjaidat egyenkent kell hozzaadnod
a Cleonaban. A legegyszerubb modja az, ha a cleona://-linked bepostolod egy
WhatsApp-csoportba es megkered a tobieket, hogy adjanak hozza teged.

### "Hasznalhatom a Cleonat tobb keszuleken egyidejuleg?"

Igen. Akar 5 keszuleket is csatlakoztathatsz ugyanazzal az identitassal. Egy
keszulek a primaris (ez tartalmazza a Seed-Phrase-t), es tovabbi keszulekek
biztonsagos parosito folyamaton keresztul csatlakoztathatoak. Minden keszulek
ugyanazt az identitast, kontaktokat es beszelgeteseket hasznalja. Reszleteket
lasd a Multi-Device fejezetben.

### "Hogyan kapok frissiteseket ha az App Store blokkolt?"

A Cleona a frissiteseket kozvetlenul a P2P-halozaton keresztul is
beszerezheti, anelkul hogy App Store-ra, weboldalra vagy letoltesi szerverre
szorulna. Ha a halozatban mas felhasznalo rendelkezik a legujabb verzioval,
a keszuleked onnan toltheti le a frissittest. A hitelleseget a fejleszto
digitalis alaiersa igazolja. Alternativakent egy kontaktod meghivolinkkel
vagy USB-kulcson is tovabbadhatja az alkalmazast. Tovabbiak a
"Szoftverfrissitesek" fejezetben.

---

## Segitseg es kapcsolat

Ha kerdeseid vannak vagy problemaba utkozel, aktualis informaciokat talalsz
a Cleona weboldalan es a GitHubon. Mivel a Cleona egy decentralizalt projekt,
nincs klasszikus ugyfelszolgalat -- de van egy aktiv kozosseg, amely szivesen
segit.

---

*Ez a kezikonyv a Cleona Chat 3.1.125 verziojat irja le. Egyes funkciok
ujabb verziokaban megvaltozhatnak vagy bovulhetnek.*

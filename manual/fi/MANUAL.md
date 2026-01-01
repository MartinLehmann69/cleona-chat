# Cleona Chat -- Käyttöohje

Versio 4.2 | Tilanne marraskuu 2026

---

## Sisällysluettelo

1. [Mikä Cleona Chat on?](#1-mikä-cleona-chat-on)
2. [Aloittaminen](#2-aloittaminen)
3. [Yhteystiedot](#3-yhteystiedot)
4. [Viestit](#4-viestit)
5. [Ryhmät](#5-ryhmät)
6. [Julkiset kanavat](#6-julkiset-kanavat)
7. [Puhelut](#7-puhelut)
8. [Kalenteri](#8-kalenteri)
9. [Kyselyt](#9-kyselyt)
10. [Useita identiteettejä](#10-useita-identiteettejä)
11. [Useita laitteita](#11-useita-laitteita)
12. [Palauttaminen](#12-palauttaminen)
13. [Asetukset](#13-asetukset)
14. [Tietoturva](#14-tietoturva)
15. [Ohjelmistopäivitykset](#15-ohjelmistopäivitykset)
16. [Usein kysytyt kysymykset](#16-usein-kysytyt-kysymykset)

---
## 1. Mikä Cleona Chat on?

### Sinun viestimesi, sinun datasit

Cleona Chat on viestiohjelma, joka toimii täysin ilman keskitettyä palvelinta.
Viestisi matkaavat laitteeltasi keskustelukumppanisi laitteelle -- ilman
kierrosta yrityksen pääkonttorin, pilven tai datakeskuksen kautta. Jos matkalla
jokin toinen laite auttaa, se vain välittää salattuja paketteja eteenpäin.
Mikään yritys ei voi lukea viestejäsi, tallentaa niitä tai välittää niitä
eteenpäin, koska yksinkertaisesti mikään yritys ei ole välissä.

### Ei tiliä, ei puhelinnumeroa

Cleonassa et tarvitse puhelinnumeroa etkä sähköpostiosoitetta kirjautuaksesi.
Identiteettisi muodostuu kryptografisesta avainparista, joka luodaan
automaattisesti laitteellasi ensimmäisen käynnistyksen yhteydessä. Tämä tarkoittaa:
kukaan ei voi jäljittää sinua puhelinnumerosi tai sähköpostiosoitteesi perusteella,
ellei itse anna yhteystietojasi eteenpäin.

### Tulevaisuusvarma salaus

Cleona käyttää nk. post-kvanttisalausta. Se tarkoittaa: edes tulevat
kvanttikoneet eivät voivat murtaa viestejäsi. Sinun ei tarvitse ymmärtää
yksityiskohtia -- tärkeää on vain, että viestintäsi on nykytekniikan mukaisesti
parhaalla mahdollisella tavalla suojattu.

### Miten se toimii ilman palvelinta?

Cleona-verkko koostuu vain sen käyttäjien laitteista. Jokainen laite on
solmu, yksikään solmu ei ole toista tärkeämpi, ja jokainen tuntee vain
naapurinsa. Neljä asiaa tekevät tästä verkon erityisen:

- **Ei kiinteää pistettä.** Sovelluksessa ei ole palvelinosoitetta, eikä verkko
  riipu mistään yksittäisestä solmusta. Ei ole mitään, jonka voisi katkaista
  sammuttaakseen Cleonan.
- **Välitön.** Viestisi lähtee heti, kun lähetät sen. Se ei odota rytmiä eikä
  mitään muutakaan.
- **Häivitysliikenne rinnalla.** Laitteesi lähettää jatkuvasti pienhiä
  häivytyspaketteja, jotta ulkoapäin ei näe, milloin oikeasti kirjoitat. Mikään
  viesti ei riipu siitä -- häivitysliikenne vain pyörii vieressä.
- **Koodeja nimien sijaan.** Viekö, joka välittää viestin, näkee vain koodin,
  joka vaihtuu joka päivä. Normaalitilanteessa kukaan heistä ei tunne
  lähettäjää ja vastaanottajaa yhtä aikaa; poikkeukset ovat luvussa 14.

**Kolme reittiä, kaikki yhtä aikaa.** Kun lähetät viestin, Cleona ei kokeile
reittiä toisensa jälkeen, vaan kaikki sopivat kerralla. Heti kun
keskustelukumppanisi vahvistaa vastaanoton, muut keskeytetään.

1. **Samassa verkossa:** Jos olette samassa Wi-Fi-verkossa, viesti menee
   suoraan toiselle puolelle.
2. **Kiinteiden naapureiden kautta:** Internetissä laitteesi antaa viestin
   kiinteälle naapurilleen. Se välittää sen keskustelukumppanisi
   kiinteille naapureille (enintään kolme kerralla), ja yksi heistä toimittaa
   sen perille.
3. **Postilaatikko:** Jos keskustelukumppanisi on offline-tilassa, Cleona
   tallentaa viestin salattuna kolmen naapurin luo. Se pysyy siellä enintään
   7 päivää. Kun keskustelukumppanisi tulee takaisin online-tilaan, hän noutaa
   sen.

**Miten pääset verkkoon?** Sovelluksessa ei ole palvelinosoitetta. Pääsysi
saat ensimmäiseltä yhteystiedoltasi: hänen kutsunsa sisältää osoitteet,
joiden kautta laitteesi löytää ensimmäiset naapurinsa. Samassa Wi-Fi-verkossa
Cleona-laitteet löytävät toisensa myös itsestään. Siitä eteenpäin laitteesi
oppii tuntemaan joka naapurin myötä lisää naapureita.

### Alustat

Cleona on saatavilla Androidille, iOS:lle, macOS:lle, Linuxille ja
Windowsille. Tietokoneilla ja Androidilla viestit ja puhelut saapuvat
sekunneissa. iPhonessa näin on, niin kauan kuin sovellus on auki. Kun se ei
ole auki, iOS herättää sen vain ajoittain lyhyeksi aikaa; milloin, iOS
päättää. Cleona noutaa tällöin kaiken sinulle säilytetyn ja näyttää
ilmoituksen numerolla sovelluksen kuvakkeessa. Puhelut eivät tavoita
iPhonea, jonka sovellus ei ole auki. Tämä on Applen sääntö, ei virhe
Cleonassa.

---

## 2. Aloittaminen

### Asenna sovellus

**Android:**
1. Lataa APK-tiedosto Cleona-sivustolta tai GitHub Releases -julkaisuista.
2. Avaa tiedosto puhelimessasi. Tarvittaessa salli asennus tuntemattomista
   lähteistä (Android kysyy sinulta tätä automaattisesti).
3. Napauta "Asenna" ja odota, kunnes asennus on valmis.

**iOS:**
1. Avaa TestFlight-kutsulinkki iPhonellasi.
2. Napauta "Asenna". TestFlight on Applen virallinen tapa jakaa
   beta-sovelluksia.
3. Asennuksen jälkeen löydät Cleonan kotinäytöltäsi.

**macOS:**
1. Lataa DMG-tiedosto Cleona-sivustolta tai GitHub Releases -julkaisuista.
2. Avaa DMG ja vedä Cleona Ohjelmat-kansioosi.
3. Ensimmäisen käynnistyksen yhteydessä macOS saattaa kysyä, haluatko avata
   tunnistetun kehittäjän sovelluksen -- vahvista tämä.

**Linux (Ubuntu/Debian):**
1. Lataa .deb-tiedosto Cleona-sivustolta tai GitHub Releases -julkaisuista.
2. Asenna kaksoisklikkauksella tai terminaalissa: `sudo dpkg -i cleona-chat-beta_VERSION_amd64.deb`
3. Käynnistä Cleona sovellusvalikosta tai terminaalissa komennolla `cleona-chat-beta`.

**Linux (Fedora/openSUSE):**
1. Lataa .rpm-tiedosto Cleona-sivustolta tai GitHub Releases -julkaisuista.
2. Asenna komennolla: `sudo dnf install cleona-chat-beta-VERSION-1.x86_64.rpm`
3. Käynnistä Cleona sovellusvalikosta tai terminaalissa komennolla `cleona-chat-beta`.

**Linux (kaikki jakelut -- AppImage):**
1. Lataa .AppImage-tiedosto Cleona-sivustolta tai GitHub Releases -julkaisuista.
2. Tee tiedostosta suoritettava: oikea klikkaus, ominaisuudet, suoritettava,
   tai terminaalissa: `chmod +x cleona-chat-beta-VERSION-x86_64.AppImage`
3. Käynnistä kaksoisklikkauksella tai terminaalissa: `./cleona-chat-beta-VERSION-x86_64.AppImage`

Pakettien nimet koskevat betaa, joka on tällä hetkellä ainoa julkaistu
versio; ne ovat nimeltään `cleona-chat-beta`.

**Windows:**
1. Lataa asennusohjelma Cleona-sivustolta tai GitHub Releases -julkaisuista.
2. Suorita asennustiedosto ja seuraa ohjeita.
3. Käynnistä Cleona Käynnistä-valikosta tai työpöydän pikakuvakkeesta.

### Luo identiteetti

Ensimmäisen käynnistyksen yhteydessä Cleona luo sinulle automaattisesti uuden
identiteetin. Voit antaa itsellesi näyttönimen -- se on nimi, jonka
yhteystiedot näkevät. Tätä nimeä voi vaihtaa milloin tahansa.

### Kirjoita siemenfraasi ylös -- kaikkein tärkeintä

Identiteetin luomisen jälkeen Cleona näyttää sinulle 24 sanaa. Se on
**siemenfraasisi** -- henkilökohtainen palautusavaimesi.

**Kirjoita nämä 24 sanaa paperille ja säilytä ne turvassa.**

Miksi tämä on niin tärkeää?

- Jos puhelimesi hajoaa, katoaa tai varastetaan, voit näillä 24 sanalla
  palauttaa koko identiteettisi uudelle laitteelle.
- Ilman siemenfraasia ei ole paluutietoa. Ei ole "unohtunut salasana"
  -painiketta eikä tukea, joka voisi palauttaa tilisi -- koska tilinäkään
  ei ole palvelimella. Eivätkä yhteystietosikaan voi palauttaa identiteettiäsi,
  kuinka monia tahansa. Toinen laite samalla identiteetillä tulee myöhemmässä
  versiossa (katso luku 11).
- Älä koskaan anna siemenfraasia muille. Ken tahansa, joka tuntee nämä sanat,
  voi esiintyä sinuna.

Löydät 24 sanaa myöhemmin myös asetuksista kohdasta "Varmuuskopio" ->
"Näytä palautuslause", jos haluat lukea ne uudelleen. Androidissa
vahvistat sen näyttölukituksellasi.

### Lisää ensimmäinen yhteystieto

Keskustellaksesi jonkun kanssa sinun on ensin lisättävä henkilö yhteystiedoksi.
Siihen on useita tapoja -- kaikki selitetään seuraavassa osiossa.

---

## 3. Yhteystiedot

### Kutsusi

Yhteystiedot Cleonassa syntyvät vain kutsun kautta. Kutsusi on olemassa
ensimmäisestä käynnistyksestä asti -- jopa ilman internetiä ja ennen kuin
laitteesi on löytänyt naapurinakaan. Löydät sen identiteetin tietosivulta
(napauta omaa nimeäsi yläpalkissa).

Kutsu on saatavilla kahdessa muodossa, jotka sisältävät täsmälleen saman:

- **QR-koodina**, kun keskustelukumppanisi seisoo vieressäsi, ja
- **tekstirivinä**, jonka lähetät sähköpostilla, tekstiviestillä tai jonkin
  toisen viestiohjelman kautta.

Kutsu ei sisällä puhelinnumeroa eikä nimeä hakemistosta. Se sisältää
julkiset avaimesi ja osoitteet, joiden kautta keskustelukumppanisi tavoittaa
sinut ja naapurisi. Siksi joku, joka on juuri asentanut Cleonan, saa kutsustasi
myös sisäänpääsyn verkkoon.

### Skannaa QR-koodi (suositeltu)

Kun tapaatte henkilökohtaisesti:

1. Näytät keskustelukumppanillesi kutsusi QR-koodin.
2. Keskustelukumppanisi napauttaa plus-painiketta, valitsee "Skannaa QR-koodi"
   ja pitää kameran näyttöösi. Tämä toimii myös tietokoneen web-kameralla.
3. Pyyntö tulee sinulle ja **hyväksytään automaattisesti** -- sillä näytit
   koodinhan juuri itse.

QR-koodi kelpaa kerran: ensimmäinen kelvollinen pyyntö hyväksytään, sen
jälkeen kutsu on käytetty. QR-koodi on turvallisin tapa, koska silloin
tiedätte tarkalleen, kenen kanssa vaihdatte yhteystiedot.

### NFC (pidä puhelimet yhdessä)

Kun molemmat laitteet tukevat NFC:tä:

1. Avaa yhteystiedon lisääminen molemmissa.
2. Pitäkää puhelimienne selät vastakkain kiinni toisissaan.
3. Kutsu siirtyy ja hyväksytään automaattisesti.

NFC tarjoaa kuten QR-koodikin korkean turvallisuustason, koska vaihto
toimii vain, kun seisotte fyysisesti vierekkäin.

### Lähetä tekstirivi

Kun ette voi tavata:

1. Avaa kutsusi ja kopioi tekstirivi.
2. Lähetä se henkilölle, jonka pitäisi lisätä sinut -- sähköpostilla,
   tekstiviestillä tai jonkin toisen viestiohjelman kautta.
3. Toinen henkilö liittää rivin Cleonan yhteystiedon lisääminen -ikkunaan.
4. Pyyntö ilmestyy sinulle kohtaan **"Pyynnöt"**. Tässä ei **hyväksytä**
   automaattisesti: päätät itse, sillä et voi tietää, kuka luki riviä
   matkalla.

### Hyväksy yhteystietopyynnöt

Saapuva pyyntö ei vielä luo yhteystietoa. Se esittää sinulle kysymyksen ja
ilmestyy välilehdelle **"Pyynnöt"**. Siellä näet nimen ja
vahvistustason ja voit valita:

- **Hyväksy** -- vasta nyt henkilöstä tulee yhteystietosi.
- **Hylkää** -- pyyntö hylätään.
- **Estä** -- henkilö ei voi lähettää sinulle lisäpyyntöjä.

### Älä koskaan käytä kiinteänä naapurina

Yhteystiedon valikossa löydät kytkimen **"Älä koskaan käytä kiinteänä
naapurina"** (oletus: pois). Kun se on päällä, tämä yhteystieto ei välitä
viestejä sinulle eteenpäin eikä siksi myöskään saa tietää, milloin lähetät
tai vastaanotat viestejä. Se on tarkoitettu tilanteeseen, jossa uhka
uhkaa sinua omasta piiristäsi.

Tuntemattomilta (eivät kontaktejasi eivätkä yhteisen ryhmän jäseniä)
Cleona päästää läpi tällaisen pyynnön lisäksi ei mitään --
ei viestiä, ei puhelua, ei tiedostoa. Ja edes pyyntö pääsee läpi vain, jos
lähettäjä on ensin ratkaissut pienen laskentatehtävän. Se tekee
massaroskapostista kallista.

### Vahvistustasot

Cleona näyttää sinulle, kuinka varmasti yhteystiedon identiteetti on
vahvistettu:

| Taso | Merkitys |
|-------|-----------|
| Ei vahvistettu | Olette yhteydessä, mutta mikään ei vahvista, että oikea henkilö on todella takana. |
| Nähty | Avainten vaihto onnistui; voitte viestiä salattuna. |
| Vahvistettu | Tapasitte henkilökohtaisesti ja yhdistyitte kameraskannauksella tai NFC:llä. |
| Luotettu | Olet nimenomaisesti merkinnyt tämän yhteystiedon luotettavaksi. |

"Vahvistettu" on olemassa vain henkilökohtaiseen vaihtoon. Kutsu, joka
tuli keskustelun kautta tai sähköpostilla, ei saavuta koskaan tätä tasoa --
vaikka se sisältäisi samat tiedot.

Jos yhteystiedon avaimet muuttuvat ilmoitusta antamatta, Cleona palauttaa
hänet tasolle "Ei vahvistettu". Se suojaa sinua siltä, että joku esiintyy
huomaamattasi yhteystietonasi.

---
## 4. Viestit

### Tekstin lähettäminen ja vastaanottaminen

Kirjoita viestisi yksinkertaisesti syöttökenttään alareunassa ja paina Enter
tai lähetä-painiketta. Viestisi salataan automaattisesti, ennen kuin se lähtee
laitteeltasi.

Saapuvat viestit ilmestyvät keskusteluhistoriaan.

### Mitä viestisi merkit tarkoittavat

| Merkki | Merkitys |
|---------|-----------|
| Kello | Viesti on luotu, mutta yksikään reitti ei ole vielä kantanut sitä. |
| Yksi ruks | Viesti on matkalla. Tämä pätee myös silloin, kun se odottaa postilaatikossa keskustelukumppaniasi. |
| Kaksi ruksia | Toimitettu: Keskustelukumppanisi laite on vahvistananut vastaanoton. |
| Varoitustermerkki | 14 päivän ajan mikään reitti ei kantanut viestiä. Napauta sitä lähettääksesi sen uudelleen. |

**Offline ei ole virhe.** Jos keskustelukumppanisi ei ole tavoitettavissa,
viesti pysyy yhden ruksin tilassa, kunnes se noudetaan -- se ei ole
hukkunut. Jos laitteellasi itsellään ei ole yhteyttä, viesti pysyy kellon
kohdalla ja lähtee itsestään, kunhan reitti on taas olemassa.
Varoitustermerkki ilmestyy vasta, kun viesti ei 14 päivän aikana ole
löytänyt reittiä; silloin voit lähettää sen uudelleen.

Näin on myös iPhonen kohdalla, jonka sovellus ei ole auki: viesti odottaa
postilaatikossa, kunnes iOS herättää sovelluksen hetkeksi tai kunnes
keskustelukumppanisi avaa sen. Se voi kestää pidempään kuin muilla
laitteilla.

Kaksi ruksia on olemassa vain, kun vastaanottaja itse vahvistaa vastaanoton.
Tämä kuittaus on salattu ja allekirjoitettu -- kukaan matkalla ei voi
väärentää sitä teeskennellykseen toimitusta.

### Kuvien, videoiden ja tiedostojen lähettäminen

Sinulla on useita mahdollisuuksia:

- **Lemu-kuvake** syöttökentässä: Napauta sitä valitaksesi tiedoston, kuvan
  tai videon galleriastasi tai tiedostojärjestelmästäsi.
- **Vedä ja pudota** (työpöytä): Vedä tiedosto yksinkertaisesti
  keskusteluikkunaan.
- **Liitä leikepöydältä** (työpöytä): Kopioi kuva ja liitä se
  keskustelussa.

Pienet tiedostot (alle 256 KB) matkaavat suoraan viestin mukana. Suuremmat
tiedostot pilkotaan osiin ja varustetaan virheenkorjauksella, jotta yksittäiset
hukkuneet osat eivät haittaa. Jos olette molemmat online-tilassa, ne
suoratoistetaan naapurin kautta; muussa tapauksessa ne tallennetaan laitteille,
jotka ovat jatkuvasti tavoitettavissa, kunnes keskustelukumppanisi noutaa ne.

Jos tiedosto on vähintään 256 KB, Cleona kysyy sinulta jokaisen tiedoston
kohdalla ennen lähettämistä:
Suuri tiedosto ei voi kulkea viestiesi reittiä. Sen sisältö pysyy salattuna,
eikä keskustelukumppanisi saa tietää internet-osoitettasi. Siirto näkyy
ulkoapäin kuitenkin tapahtumana, ja vieras laite, joka välittää tai säilyttää
sitä, näkee, kuka lataa ylös ja kuka noutaa. Suostumuksesi koskee vain
tätä yhtä tiedostoa.

### Ääniviestit

1. Pidä mikrofonipainiketta syöttökentässä painettuna.
2. Puhu viestisi.
3. Päästä irti painikkeesta lähettääksesi viestin.

Jos laitteellasi on puheentunnistus käytössä (katso asetukset),
ääniviestisi transkriboidaan automaattisesti tekstiksi. Keskustelukumppanisi
näkee sitten sekä tallenteen että transkriboidun tekstin.

### Viesteihin vastaaminen (lainaus)

Vastataksesi tiettyyn viestiin:

1. Avaa viestin vieressä oleva kolmen pisteen valikko.
2. Valitse "Vastaa".
3. Syöttökentän yläpuolelle ilmestyy banneri lainatun viestin kanssa.
4. Kirjoita vastauksesi ja lähetä se.

Lainattu viesti näytetään vastauksessasi, jotta viittaus on
selkeä.

### Viestien muokkaaminen ja poistaminen

- **Muokkaa:** Viestin kolmen pisteen valikko, sitten "Muokkaa".
  Muuta tekstiä ja lähetä se uudelleen. Keskustelukumppanisi näkee, että
  viestiä on muokattu. Muokkaaminen on mahdollista 15 minuutin kuluessa
  lähettämisestä.
- **Poista:** Viestin kolmen pisteen valikko, sitten "Poista". Viesti
  poistetaan sinulta ja keskustelukumppaniltasi. Voit poistaa
  omat viestisi milloin tahansa -- poistamiselle ei ole aikarajaa.

### Emoji-reaktiot

Kirjoitetun vastauksen sijaan voit reagoida viestiin emojilla:

1. Avaa kolmen pisteen valikko tai pidä viestiä pitkään painettuna.
2. Valitse emoji pikavalinnasta tai avaa emoji-valitsin
   koko valikoimaa varten.
3. Reaktiosi ilmestyy viestin alle.

### Tekstin kopiointi

Viestin kolmen pisteen valikon kautta voit kopioida viestitekstin
leikepöydälle.

### Viestien haku

Keskusteluikkunan yläreunasta löydät hakutoiminnon. Syötä hakusana, ja
Cleona näyttää sinulle kaikki osumat nykyisessä keskustelussa. Nuolinäppäimillä
voit hypähdellä osumien välillä.

Aloitussivulla on lisäksi välilehtien yläpuolella toimiva hakusuodatin,
jolla voit selata kaikkia keskusteluja termin perusteella.

### Linkin esikatselu

Kun lähetät linkin, Cleona luo automaattisesti esikatselun (otsikko,
kuvaus, esikatselukuva). Tämä esikatselu luodaan laitteellasi ja
lähetetään sen mukana -- keskustelukumppanisi ei tarvitse varten
yhteyttä linkitettyyn verkkosivustoon.

Sen, mitä napautus vastaanotettuun linkkiin tekee, säädät asetuksista
kohdasta "Linkkien avaaminen": "Normaalisti", "Suosi yksityistä ikkunaa"
(missä laite ei voi avata yksityistä ikkunaa, linkki avautuu normaalisti)
tai "Kysy joka kerta".

---

## 5. Ryhmät

### Ryhmän luominen

1. Vaihda välilehdelle "Ryhmät".
2. Napauta plus-painiketta.
3. Anna ryhmälle nimi.
4. Valitse yhteystiedot, jotka haluat kutsua.
5. Napauta "Luo".

Kutsutut yhteystiedot saavat ilmoituksen ja voivat liittyä ryhmään.

### Miten ryhmäviestit on suojattu

Ryhmässä, jossa on enintään 16 jäsentä, Cleona lähettää jokaisen viestin
jokaiselle jäsenelle erikseen -- kullakin vain tätä jäsentä varten salattuna,
ikään kuin olisit kirjoittanut jokaiselle oman viestin. Ryhmäviestin
ruksit näyttävät sen jäsenen tilan, jolla se on vähiten edistynyt.

Kasvaessa ryhmä yli 16 jäsenen, se käyttää yhteistä avainta. Avain vaihtuu
joka päivä ja arvotaan uudelleen, kun jäsen lähtee tai poistetaan; uusi
jäsen lukee vasta liittymisestään alkaen. Siellä ruksit eivät enää näytä
jokaisen jäsenen tilaa, vaan sen, että viesti on talletettu verkkoon.
Pudotessa ryhmä 12 jäseneen tai vähemmän, se palaa yksittäislähetykseen.

### Kuvat ryhmissä ja kanavissa

Ryhmän tai kanavan asetuksissa säädät kohdalla "Lataa kuvat aina",
ladataanko kuvat heti vai vasta, kun napautat yhtä.

### Jäsenten kutsuminen

Myös luomisen jälkeen voit kutsua lisää yhteystietoja:

1. Avaa ryhmän tiedot (kolmen pisteen valikko ryhmäluettelossa tai
   yläpalkki ryhmäkeskustelussa).
2. Napauta "Kutsu".
3. Valitse yhteystiedot, jotka haluat lisätä.

### Roolit

Jokaisessa ryhmässä on kolme roolia:

- **Omistaja (Owner):** Täysi valta. Voi lisätä ja poistaa jäseniä,
  nimetä ylläpitäjiä ja hallita ryhmää. Omistaja voi siirtää
  asemansa myös toiselle jäsenelle.
- **Ylläpitäjä:** Voi poistaa jäseniä ja auttaa hallinnoinnissa.
- **Jäsen:** Voi lukea ja kirjoittaa viestejä.

### Ryhmästä poistuminen

1. Avaa kolmen pisteen valikko ryhmäluettelossa.
2. Valitse "Poistu".
3. Vahvista päätöksesi.

Kun poistut ryhmästä, aiemmat viestisi pysyvät muiden
jäsenien nähtävillä.

---

## 6. Julkiset kanavat

### Mitä kanavat ovat?

Kanavat ovat julkisia keskustelufoorumeita Cleona-verkon sisällä.
Toisin kuin ryhmissä, täällä jokainen voi lukea mukana ilman, että häntä
tarvitsee kutsua. Vain omistaja ja ylläpitäjät voivat julkaista viestejä --
tilaajat lukevat mukana.

### Kanavien löytäminen ja niihin liittyminen

1. Vaihda välilehdelle "Kanavat".
2. Avaa välilehti "Haku".
3. Selaa saatavilla olevia kanavia nimen tai aiheen perusteella.
4. Napauta kanavaa ja sitten "Tilaa".

Kanavia voi suodattaa kielen perusteella. Jotkin kanavat on merkitty
"Ei nuorille" -- ne näkyvät vain, jos olet profiilissasi vahvistanut,
että olet yli 18-vuotias.

### Oman kanavan luominen

1. Vaihda välilehdelle "Kanavat".
2. Napauta plus-painiketta.
3. Syötä kanavan nimi (sen on oltava yksilöllinen koko verkossa).
4. Valitse kieli ja onko kanava julkinen vai yksityinen.
5. Valinnainen: Lisää kuvaus ja kuva.
6. Napauta "Luo".

Julkisissa kanavissa voit määrittää, luokitellaanko sisältö kohdassa
"Ei nuorille".

### Sisällön ilmoittaminen

Jos huomaat julkisessa kanavassa sopimattomia sisältöjä, voit
ilmoittaa niistä. Cleona käyttää hajautettua moderointijärjestelmää: ilmoitukset
arvioivat verkon satunnaisesti valitut jäsenet (eräänlainen
"valamiesoikeus"). Jos rikkomus todetaan, kanava saa
varoituksen. Toistuvien rikkomusten yhteydessä se alennetaan
hakuindeksissä tai se estetään.

### Järjestelmäkanavat

Cleonassa on kaksi sisäänrakennettua järjestelmäkanavaa:

- **Bug Log:** Kun Cleona tunnistaa virheen, se kysyy, haluatko lähettää
  virheraportin; sitä ennen näet tarkalleen, mitä julkaistaan. Nämä
  raportit päätyvät Bug-Log-kanavaan, jossa yhteisö voi tarkastella niitä.
  Raportissa ei ole nimeä eikä keskustelujesi sisältöä, vaan pseudonyymi.
  Betassa se mainitsee lisäksi tunnuksesi (User-ID), jotta kehittäjät
  voivat kysellä jälkikäteen. Voit myös lähettää manuaalisesti
  lokiraportin (esikatseluikkunan ja nimenomaisen suostumuksen kera).
- **Feature Requests:** Täällä käyttäjät voivat jättää
  toimintatoiveita ja äänestää olemassa olevien ehdotusten puolesta. Ehdotukset
  lajitellaan äänten perusteella.

Jokainen tietokone pitää enintään 25 MB kutakin järjestelmäkanavaa, jokainen
puhelin enintään 5 MB; kun tila on täynnä, vanhin menee ensin -- ei koskaan
mitään, mitä olet itse jo nähnyt.

---
## 7. Puhelut

### Äänipuhelun aloittaminen

1. Avaa keskustelu yhteystiedon kanssa, jota haluat soittaa.
2. Napauta puhelinkuvaketta yläpalkissa.
3. Odota, kunnes keskustelukumppanisi vastaa puheluun.

Keskustelun aikana näet aikajanan, puhelun keston ja
sinulla on käyttöoikeus mykistykseen ja kaiuttimeen.

Luurin asettamiseksi napauta punaista lopeta-painiketta.

Jos näet "Ei tavoitettavissa", keskustelukumppanisi laitteeseen ei juuri
nyt saada yhteyttä, esimerkiksi iPhoneen, jonka sovellus ei ole auki.
Lähetä sen sijaan viesti.

### Videopuhelun aloittaminen

1. Avaa keskustelu yhteystiedon kanssa.
2. Napauta kamerakuvaketta yläpalkissa.
3. Kuvasi ilmestyy pieneen ikkunaan, keskustelukumppanisi
   kuva suureen alueeseen.

Voit keskustelun aikana vaihtaa etu- ja takakameran välillä.

### Saapuvat puhelut

Kun joku soittaa sinulle, ilmestyy ilmoitusikkuna soittajan
nimen kanssa. Voit:

- **Vastata** -- keskustelu alkaa.
- **Hylätä** -- soittajalle ilmoitetaan.

Jos olet juuri keskustelussa, uusi puhelu ei soi; saat sen sijaan viestin
"Vastaamaton puhelu". Sama koskee ryhmäpuhelua, johon et ole vastannut --
viesti on silloin ryhmäkeskustelussa.

Jos joku soittaa identiteetillesi, jota juuri ei näytetä, se soi silti;
puheluruutu kertoo, mihin identiteetteihisi soitetaan.

iPhonessa puhelin soi vain silloin, kun sovellus on auki. Se, joka soittaa
sinulle, kun sovellus ei ole auki, näkee 10 sekunnin jälkeen "Ei
tavoitettavissa". Heti kun avaat sovelluksen, löydät viestin
vastaamattomasta puhelusta.

### Ryhmäpuhelut

Voit myös käydä ryhmäpuheluita, joissa useampi henkilö osallistuu
samaan aikaan. Puhelu organisoidaan älykkään välityspuun
avulla, joten jokaisen osallistujan ei tarvitse olla suoraan yhteydessä
jokaiseen toiseen. Kaikki keskustelut ovat alusta loppuun salattuja.

Jokainen ryhmän jäsen voi aloittaa ryhmäpuhelun. Kaksi osallistujaa, jotka
eivät ole toistensa kontaktia, eivät koskaan näe toistensa internet-osoitetta:
heidän äänensä ja kuvansa kulkee osallistujan kautta, joka on kummankin
kontakti. Jos sellaista ei ole, nämä kaksi eivät ole yhteydessä toisiinsa,
ja laatta sanoo "Ei yhteistä kontaktia puhelussa". Jos välitys on
varattu, ääni pysyy ja video jää pois tältä parilta.

### Salaus puheluissa

Kaikki puhelut salataan kertakäyttöisillä avaimilla, jotka ovat olemassa vain
keskustelun ajan. Luurin asettamisen jälkeen nämä avaimet
poistetaan välittömästi. Kukaan ei voi purkaa mennyttä keskustelua
jälkikäteen.

Rehellisesti sanottuna: puhelut kulkevat, aina kun mahdollista, suoraan
laitteiden välillä, sillä jo pieni viive häiritsee puhumista. Toisin
kuin viesteissä, internetin tarjoajasi voi siksi puhelun yhteydessä nähdä,
mihin internet-osoitteeseen olet yhteydessä. Mitä sanotte, hän ei näe.

Puhelun yhteydessä myös kontaktisi näkee internet-osoitteesi. Jos et halua
sitä erään kontaktin kohdalla, sammuta hänen valikostaan "Salli puhelut"
(oletus: päällä). Jos sammutat sen myöhemmin, hänelle jää tunnettuna osoite,
jonka hän on jo nähnyt.

---

## 8. Kalenteri

Cleonassa on sisäänrakennettu kalenteri, joka toimii salattuna ja täysin
hajautetusti -- ilman pilvipalvelua.

### Näkymät

Kalenterissa on viisi näkymää: päivä, viikko, kuukausi, vuosi ja
tehtävä-näkymä. Vaihda niiden välillä kalenterinäkymän yläreunan
välilehtien kautta.

### Tapahtumien luominen

Napauta aikaväliä tai käytä lisää-painiketta luodaksesi uuden
tapahtuman. Voit syöttää otsikon, päivämäärän, kellonajan, paikan ja
muistiinpanot. Tapahtumat tallennetaan salattuna laitteellesi.

### Toistuvat tapahtumat

Tapahtumat voivat toistua päivittäin, viikoittain, kuukausittain tai
vuosittain. Voit mukauttaa kaavaa (esim. joka toinen tiistai,
joka kuun ensimmäinen) ja asettaa päättymispäivän tai
toistojen määrän.

### Yhteystietojen kutsuminen

Tapahtumaa luodessasi tai muokatessasi voit kutsua Cleona-yhteystietojasi.
He saavat salatun kalenterikutsun ja voivat vastata
kyllä, ei tai ehkä. Tapahtuman muutokset
lähetetään automaattisesti kaikille kutsutuille.

### Vapaa/varattu-näyttö

Voit jakaa saatavuutesi yhteystietojesi kanssa paljastamatta
tapahtuman tietoja. Yksityisyyssuojan tasoja on kolme: kaikki tiedot, vain
aikajaksot tai piilotettu. Voit asettaa oletuksen ja ohittaa sen
yhteystiedoittain.

### Muistutukset

Tapahtumilla voi olla muistutuksia, jotka laukaisevat
järjestelmäilmoituksen ennen tapahtuman alkua. Voit tarvittaessa
torkuttaa muistutuksia.

### Ulkoinen kalenterisynkronointi

Cleona voi synkronoida ulkoisten kalenteripalveluiden kanssa:

- **CalDAV** -- Yhdistä mihin tahansa CalDAV-yhteensopivaan palvelimeen (Nextcloud,
  Radicale jne.).
- **Google Kalenteri** -- Synkronointi Google Calendar API:n kautta
  turvallisella OAuth2-todennuksella.
- **Paikallinen CalDAV-palvelin** -- Cleona voi käynnistää paikallisen
  CalDAV-palvelimen laitteellasi, jotta työpöydän kalenterisovellukset
  (Thunderbird, Outlook, Apple Kalenteri, Evolution) voivat synkronoida
  Cleona-kalenterisi kanssa.
- **Androidin järjestelmäkalenteri** -- Cleonan tapahtumat voidaan siirtää
  Android-laitteesi sisäänrakennettuun kalenterisovellukseen.
- **ICS-tiedostot** -- Tuo ja vie tapahtumia
  standardi-iCalendar-muodossa.

### PDF-vienti

Voit tulostaa tai viedä minkä tahansa kalenterinäkymän (päivä, viikko,
kuukausi, vuosi) PDF-asiakirjana.

---

## 9. Kyselyt

Voit luoda kyselyitä jokaisessa keskustelussa tai ryhmässä kerätäksesi
 mielipiteitä tai suunnitellaksesi aikoja.

### Kyselytyypit

Cleona tukee viittälaista kyselyitä:

- **Yksittäisvalinta** -- Osallistujat valitsevat yhden vaihtoehdon.
- **Monivalinta** -- Osallistujat voivat valita useita vaihtoehtoja.
- **Aikakysely** -- Etsi aika, joka sopii kaikille. Jokainen
  osallistuja merkitsee ajat saatavilla, ehkä tai ei
  saatavilla.
- **Asteikko** -- Arvioi jotain numeerisella asteikolla (esim. 1–5).
- **Vapaa teksti** -- Osallistujat kirjoittavat oman vastauksensa.

### Kyselyn luominen

Avaa keskustelu ja napauta kyselykuvaketta (tai käytä
liitevalikkoa). Valitse kyselytyyppi, muotoile kysymyksesi ja
vaihtoehdot, ja lähetä kysely. Se ilmestyy viestinä keskusteluun.

### Äänestäminen

Napauta kyselyä antaaksesi äänesi. Voit milloin tahansa
muuttaa ääntäsi tai peruuttaa sen.

### Anonyymi äänestys

Kyselyt voidaan määrittää anonyymiä äänestystä varten. Kun se on käytössä,
äänet ovat kryptografisesti anonyymejä -- kukaan, edes
kyselyn luoja, ei näe, kuka äänesti mitä. Äänimäärä
pysyy silti näkyvissä.

### Aikakysely kalenteriin

Kun aikakysely on päättynyt, voittaneenajan voi yhdellä napautuksella
muuttaa suoraan kalenterimerkinnäksi.

---
## 10. Useita identiteettejä

### Miksi useita identiteettejä?

Kuvittele, että haluat erottaa työelämäsi ja yksityiselämäsi --
samaan tapaan kuin kahdella eri puhelinnumerolla, mutta ilman toista
puhelinta. Cleonassa voit käyttää useita identiteettejä yhdellä laitteella.
Jokaisella identiteetillä on oma nimi, oma profiilikuva, omat yhteystiedot ja
omat keskustelut.

### Uuden identiteetin luominen

1. Yläpalkissa näet nykyisen identiteettisi välilehtenä.
2. Napauta plus-merkkiä (+) identiteettivälilehtien oikealla puolella.
3. Syötä nimi uudelle identiteetille.
4. Valmis -- uusi identiteetti on heti aktiivinen.

### Identiteettien välillä vaihtaminen

Napauta yksinkertaisesti identiteettivälilehteä yläpalkissa. Vaihto
on välitön -- ei odotusta, ei uudelleenlatausta.

### Kaikki pyörivät samanaikaisesti

Tärkeä seikka: Kaikki identiteettisi ovat yhtä aikaa aktiivisia. Vaikka
näytät juuri "Työ"-identiteettiä, "Yksityinen"-
identiteettisi vastaanottaa edelleen viestejä. Et missaa mitään, riippumatta
siitä, minkä identiteetin olet juuri valinnut.

### Identiteetin tietosivu

Kun napautat juuri aktiivisen identiteettisi välilehteä, avautuu
tietosivu. Täällä voit:

- Näyttää QR-koodisi yhteystietoja varten.
- Vaihtaa tai poistaa profiilikuvasi.
- Lisätä profiilikuvauksen.
- Vaihtaa näyttönimesi.
- Valita ulkoasun (skin) tälle identiteetille.
- Poistaa identiteetin, jos et enää tarvitse sitä.

### Identiteetin poistaminen

Kun poistat identiteetin, yhteystietojasi ilmoitetaan siitä.
Identiteetti ja kaikki siihen liittyvät tiedot poistetaan
laitteeltasi. Tätä toimenpidettä ei voi peruuttaa.

---

## 11. Useita laitteita

### Yksi identiteetti, yksi laite -- toistaiseksi

Identiteetti toimii tänään yhdellä laitteella. Toinen laite samalle
identiteetille tulee myöhemmässä versiossa; asetuksissa kohdassa
"Laitteet" -> "Hallinnoi laitteita" lukee "Kytke lisälaite" siksi
vielä "Ei vielä saatavilla".

Kun se tulee, pätee: Kaikki laitteet ovat tasavertaisia, päälaitetta ei
ole. Lisälaitteen asennat 24 sanallasi, ja yksi tähänastisista
laitteistasi suostuu siihen. Enintään 5 laitetta.

Jos syötät tänään 24 sanaasi uudella laitteella, siirrät identiteettiä:
Identiteetti palautetaan uudelle laitteelle, ja tähänastinen laitteesi
poistaa sen jälkeen identiteetin luotaan (katso luku 12).

Usealla laitteella voit tänään käyttää eri identiteettejä (luku 10).

### Identiteetin avainten vaihto

Jos epäilet, että joku on päässyt käsiksi avaimiisi, voit luoda kohdasta
"Hallinnoi laitteita" -> "Vaihda avaimet" uudet avaimet.
Yhteystietosi saavat ilmoituksen, avoimet kutsusi peruutetaan. Tärkeää:
Sen jälkeen 24 sanaa tuottavat yksin vain enää vanhat avaimet. Tee siksi
heti sen jälkeen uusi palautuspaketti; palauttaa voit sen jälkeen vain
yhdessä tämän paketin kanssa.

---

## 12. Palauttaminen

### Siemenfraasin käyttäminen

Kun menetät laitteesi tai perustat uuden:

1. Asenna Cleona uudelle laitteelle.
2. Valitse käynnistyksen yhteydessä "Palauta".
3. Syötä 24 sanaasi.
4. Cleona luo niistä kaikki identiteettisi uudelleen -- samoilla
   avaimilla kuin ennenkin. Yhteystiedoillesi olet sama ihminen.

### Mitä palautuu -- ja mitä ei

Identiteettisi on 24 sanassa, yhteystietosi ja keskusteluhistoriasi
eivät. Palautuu verkkopääsysi **palautuspaketin** kautta: Laitteesi
tallentaa pienen, salatun paketin verkkoon. Vain sinun 24 sanaasi voivat
löytää ja avata sen. Siinä lukee, mitä uusi laitteesi tarvitsee
tavoittaakseen yhteystietosi uudelleen, ja mitä välillä sinulle lojui
verkossa. Sen vuoksi yksikään yhteystieto ei tarvitse olla
online-tilassa.

Aikaisempaa keskusteluhistoriaa palautus ei tuo takaisin.

Palautuspaketti elää 7 päivää, ja laitteesi uusii sen, niin kauan kuin se
on käynnissä; asetuksissa näet, mihin asti se on voimassa. Jos yksikään
laitteistasi ei ollut käynnissä yli 7 päivään, se on vanhentunut.
Silloin 24 sanaa palauttavat identiteettisi silti, mutta yhteystiedot
sinun on kutsuttava uudelleen; se, mitä välillä sinulle lojui verkossa,
on menetetty.

### Palauttaminen on muutto

Jos aiempi laitteesi havaitsee myöhemmin, että identiteetti on palautettu
muualle, se poistaa sen luotaan -- keskusteluhistoriansa kanssa. Siksi:
se, jolla on sinun 24 sanaasi, voi tällä tavalla hakea identiteettisi
laitteeltasi. Kunnes kaikki yhteystiedot ovat taas olemassa, sovellus
muistuttaa sinua; kohdalla "Viimeistele ja uudista avaimet" lopetat
palautuksen itse.

### Mitä kukaan ei voi palauttaa

Tämä on tärkeää, ja siksi sanomme sen selkeästi:

- **Kukaan muu kuin sinä ei voi palauttaa identiteettiäsi.** Ei
  kehittäjä, ei tuki, eivätkä myöskään yhteystietosi -- kuinka
  monta tahansa. Ei ole pääavainta eikä osaa avaimestasi, joka olisi
  talletettu muille.
- **Jos olet menettänyt 24 sanaa etkä enää ole yhtäkään laitetta,
    identiteettisi on menetetty.** Silloin ei auta muu kuin luoda
    uusi ja kutsua yhteystietosi uudelleen.

Paras suoja: Kirjoita 24 sanaa paperille ja säilytä ne turvassa.

---
## 13. Asetukset

Pääset asetuksiin rataskuvakkeen kautta oikeassa yläkulmassa.

### Ilmoitukset ja soittoäänet

- Valitse kuudesta eri soittoäänestä saapuville puheluille.
- Aseta viestiääni.
- Android-laitteilla voit lisäksi aktivoida tai
  deaktivoida värinän.
- **"Mykistä kaikki"** ei päästä tällä laitteella enää yhtäkään viestiä
  soimaan, värisemään tai ilmoittamaan itsestään -- koskien kaikkia
  identiteettejä. Puhelut soivat edelleen.
- **"Hiljaiset tunnit"** asetat identiteettikohtaisesti alkaen-/asti-
  aikajoilla. Tuona aikana yksikään tämän identiteetin viesti ei soi,
  värisi tai ilmoita itsestään; viestit saapuvat silti.
- **"Ilmoitukset ilman sisältöä"** (oletus: pois) näyttää vain, että
  viesti, kutsu tai muistutus on saapunut -- ilman lähettäjää, nimeä
  ja tekstiä. Puhelut näyttävät edelleen nimen.
- Se, mitä käynnistyksen jälkeen saapuu kerralla, Cleona ilmoittaa
  kootussa ilmoituksessa ("5 uutta viestiä 2 keskustelussa"); kaikki
  myöhempi erikseen. Napautus viesti-ilmoitusta avaa keskustelun,
  myös toisessa identiteetissä.

### Ulkoasut (skinit)

Cleona tarjoaa kymmenen eri ulkoasua: Teal, Ocean, Sunset, Forest,
Amethyst, Fire, Storm, Slate, Gold ja Contrast. Contrast-ulkoasu täyttää
korkeimman saavutettavuustason (WCAG AAA) ja on rajoittuneen
näön kanssa erityisen helposti luettava.

Jokaisella identiteetillä voi olla oma ulkoasunsa. Vaihdat ulkoasun
identiteetin tietosivulla (napauta aktiivista identiteettivälilehteä).

Lisäksi voit asetuksissa kohdassa "Ulkoasu" vaihtaa vaalean,
tumman ja järjestelmän teeman välillä.

### Kielen vaihtaminen

Cleona on saatavilla 34 kielellä, mukaan lukien oikealta vasemmalle
-kirjoitettavat kielet (esim. arabia, heprea). Vaihda kieli
asetuksissa kohdassa "Kieli".

### Medioiden arkistointi

Jos sinulla on kotona verkkolevy (NAS) tai jaettu kansio,
Cleona voi arkistoida mediasi automaattisesti sinne. Tukevat
ovat SMB, SFTP, FTPS ja WebDAV.

Nin portaittainen tallennus toimii:
- Ensimmäiset 30 päivää: Kaikki pysyy laitteellasi.
- 30 päivän jälkeen: Esikatselukuva pysyy laitteella, alkuperäinen arkistoidaan.
- 90 päivän jälkeen: Vain pieni esikatselukuva pysyy laitteella.
- Vuoden jälkeen: Vain paikanvaraus pysyy, alkuperäinen on turvallisesti
  arkistossa.

Voit milloin tahansa napauttaa arkistoitua mediaa noutaaksesi sen
takaisin -- edellyttäen, että olet yhteydessä kotiverkkoosi. Erityisen
tärkeät mediat voidaan kiinnittää, jotta niitä ei koskaan siirretä
syrjään.

Kohdassa "Tallennusbudjetti" määrität, kuinka monta megatavua medialle
jää laitteelle (oletus: 100 MB puhelimessa, 2 GB tietokoneella). Kun se
on täynnä, vanhin kiinnittämätön media arkistoidaan ensin. Alkuperäinen
poistetaan vain, kun se on turvallisesti arkistossa -- tekstiviestit
säilyvät aina.

### Transkriptio ääniviesteille

Kun se on käytössä, ääniviestisi muutetaan tekstiksi paikallisesti
laitteellasi (avoimen lähdekoden mallilla Whisper). Transkriboitu teksti
lähetetään tallenteen mukana keskustelukumppanillesi. Transkriptio
tapahtuu kokonaan laitteellasi -- mikään data ei mene ulkoisiin palveluihin.

Mallin (tiny, base, small), joka ladataan, säädät kerran koko laitteelle;
kielen (automaattinen tai kiinteä) identiteettikohtaisesti.

### Automaattinen lataus

Voit asettaa, mistä koosta alkaen mediat ladataan
automaattisesti. Voit esimerkiksi antaa kuvien latautua
automaattisesti, mutta päättää suurista videoista manuaalisesti.

### Laitteet

Kohdasta "Laitteet" -> "Hallinnoi laitteita" näet tämän laitteen. Lisälaitteen
kytkeminen tulee myöhemmässä versiossa (luku 11).

### Verkko

Cleona ei tarvitse verkkoasetuksia toimiakseen. Siellä on
kolme verkkokytkintä:

- **Portin välitys reitittimellä** (oletus: päällä). Cleona pyytää omaa
  reititintäsi avaamaan Cleonalle oven. Jos se onnistuu, laiteesi on
  muille paremmin tavoitettavissa ja auttaa verkkoa. Cleona puhuu
  siinä vain reitittimellesi, ei internetiin.
- **Julkiset osoitemerkinnät** (oletus: päällä). Jos laitteellasi on vielä
  liian vähän naapureita, se etsii julkisesta hakemistosta (Nostr)
  lisää sisäänpääsykohtia, ja jos se on itse hyvin tavoitettavissa, se
  merkitsee itsensä sinne. Merkintä sisältää osoitteen, ei nimeä eikä
  yhteystietoa. Sammutitpa sen, laitteesi löytää naapureita enää vain
  kutsujen, paikallisen verkon ja tuntemiensa naapureiden kautta.
- **Vähemmän häivytyspaketteja Wi-Fi-verkossa** (oletus: pois). Wi-Fi-verkossa
  tai kaapelissa voit sammuttaa tyhjät häivytyspaketit. Silloin kuitenkin
  näkyy taas, milloin kirjoitat. Mobiiliverkossa tätä kytkintä ei ole --
  siellä Cleona lähettää joka tapauksessa vain yhden häivytyspaketin
  minuutissa.

Häivitysliikennettä kokonaisuutena ei voi sammuttaa. Se on tahallaan:
vain jos se pyörii aina, laitteesi aktiivisuus ei kerro mitään siitä,
kirjoitatko juuri nyt.

Kolmen kytkimen yläpuolella on **Datansäästötila**: Mobiiliverkossa Cleona
ehdottaa sitä, mutta ei koskaan kytke sitä itse päälle. Se säästää dataa,
sen hintana laitteesi on ulkoapäin helpompi tunnistaa.

Sen alapuolella säädät **"Välimuisti muiden medialle"**: Laitteesi pitää
salattuja osia muiden medioista enintään 7 päivää, jotta ne tavoittavat
vastaanottajansa (oletus: 100 MB puhelimessa, 1 GB tietokoneella).
Pienempi koko vapauttaa tilan heti -- vanhimmat osat ensin.

---

## 14. Tietoturva

### Mitä post-kvanttisalaus tarkoittaa?

Nykyinen salaus perustuu matemaattisiin ongelmiin, jotka ovat tavallisille
koneille äärimmäisen vaikeita ratkaista. Kvanttikoneet voisivat ratkaista
jotkin näistä ongelmista tulevaisuudessa nopeasti. Post-kvanttisalaus
käyttää lisämenetelmiä, jotka kestävät myös kvanttikoneet.

Cleona yhdistää molemmat lähestymistavat: klassisen salauksen
luotettavuuteen ja post-kvanttimenetelmät tulevaisuusvarmuuteen. Näin olet
samaan aikaan suojattu nykyisiä ja tulevia uhkia vastaan.

Jokaista yksittäistä viestiä varten luodaan oma avain. Vaikka
hyökkääjä murtaisi yhden viestin avaimen, hän ei voisi
sillä lukea mitään muuta viestiä.

### Miksi ei-palvelin on turvallisempi

Tavanomaisissa viestiohjelmissa viestisi kulkevat tarjoajan
palvelimien kautta. Vaikka ne olisivat siellä salattuja:
tarjoajalla on pääsy metatietoihin (kuka viestii milloin kenen kanssa,
kuinka usein, mistä) ja hänen on ehkä annettava ne
tuomioistuimen määräyksen nojalla.

Cleonassa ei ole sellaista keskitettyä pistettä. Ei ole paikkaa, johon
kaikki metatiedot kertyvät, eikä hakemistoa, josta voisi
tarkistaa, kuka olet tai ketkä tunnet.

### Kuka näkee, että kirjoitat jonkun kanssa?

Salaus suojaa, **mitä** kirjoitat. Yhtä tärkeää on, ettei
yksikään yksittäinen tarkkailija saa tietää, **kenen kanssa** ja **milloin**
kirjoitat. Tähän Cleona huolehtii nin:

- **Internetissä ei koskaan suoraan.** Jos laitteesi lähettäisi viestin
  suoraan keskustelukumppanisi internet-osoitteeseen, tarjoajasi voisi nähdä,
  kenen kanssa kirjoitat. Siksi viesti menee internetissä aina kiinteiden
  naapuriesi kautta: sinun ja keskustelukumppanisi.
- **Naapurit, joille luotat.** Kiinteät naapurisi ovat, aina kun mahdollista,
  omien yhteystietojesi laitteita -- enintään kolme, jotka ovat juuri ulkoapäin
  tavoitettavissa. Jos yksi putoaa pois, toinen yhteystieto astuu tilalle.
  Yhteystietoa ei voi ostaa palvelimilla; mielivaltaisen solmun
  verkossa kyllä. Jos sinulla ei ole vielä yhtään tavoitettavaa yhteystietoa,
  Cleona ottaa toisen naapurin. Kutsusi ei nimeä koskaan ketään
  yhteystiedoistasi, jotta kukaan ei saa niiden kautta tietoonsa ystäväsi
  osoitetta.
- **Koodeja nimien sijaan.** Naapurit eivät näe nimiä eikä tunnisteita,
  vaan vain koodin. Se on voimassa juuri teille kahdelle, yhteen suuntaan,
  yhden päivän -- seuraavana päivänä se on eri. Naapurisi tietää,
  mistä paketti tulee, mutta ei minne se lopulta mene. Keskustelukumppanisi
  naapuri tietää, minne se menee, mutta ei mistä se tuli. Normaalitilanteessa
  kukaan matkalla ei näe molempia päätepisteitä.
- **Häivitysliikenne.** Laitteesi lähettää jatkuvasti, epäsäännöllisin
  välein, häivytyspaketteja naapureilleen. Ne ovat yhtä suuria kuin
  todelliset paketit, menevät saman portin kautta eivätkä ole ulkoapäin
  niistä erotettavissa. Kirjoittaako juuri ihminen vai pyöriikö vain laite,
  ei näy siitä. Viestisi eivät koskaan odota häivitysliikennettä --
  ne lähtevät heti, se vain pyörii vieressä.

**Mitä häivitysliikenne maksaa:** Wi-Fi-verkossa noin 13 MB päivässä.
Mobiiliverkossa Cleona lähettää vain yhden häivytyspaketin minuutissa,
se on noin 1,7 MB päivässä. Syy mobiiliverkon rajoittamiseen
ei ole datamäärä, vaan akku:
jokainen paketti herättää radiomoduulin.

**Mitä Cleona ei voi piilottaa** -- rehellisesti sanottuna:

- Yksikään **yksittäinen** tarkkaaja ei näe, kuka kirjoittaa kenen kanssa --
  ei tarjoajasi eivätkä matkan solmut. Mutta ken, joka **tarkkailee molempia
  päätepisteitä yhtä aikaa**, esimerkiksi valtio, joka tarkkailee liittymääsi
  ja keskustelukumppanisi liittymää tai asettaa molemmat naapurit, voi ajan
  myötä yhdistää: paketti lähtee sinulta, pian sen jälkeen paketti saapuu
  keskustelukumppanillesi. Tarpeeksi usein toistettuna se antaa yhteyden.
- Häivitysliikenne vaikeuttaa tätä yhdistämistä, mutta ei estä sitä. Se
  piilottaa yksittäiset viestit, ei määrää: kuka lähettää paljon,
  nostaa laitensa kokonaisliikennettä.
- Yhteystieto, joka on kiinteä naapurisi, saa tietää, **milloin** ja **kuinka
  paljon** lähetät ja vastaanotat -- ei kenen kanssa eikä mitä. Jos uhka
  tulee omasta piiristäsi, voit jättää minkä tahansa yhteystiedon tästä
  ulkopuolelle (katso luku 3, "Älä koskaan käytä kiinteänä naapurina").
- Jos kahdella uudella käyttäjällä on vain sama yksi naapuri, heidän
  viestinsä kulkee juuri tämän solmun kautta, ja hän näkee molemmat
  päätepisteet. Heti kun kummallakin on lisää naapureita, se päättyy.
- Kutsusi sisältää internet-osoitteesi. Ken, jolla on tekstirivi,
  näkee, missä olet online-tilassa -- anna se vain ihmisille,
  joihin luotat sen kanssa.
- Naapuri, joka välittää eteenpäin, näkee, että kaksi koodia vaihtaa
  paketteja -- ei kuka on takana eikä mitä sisällä on.
- Käynnissä olevan puhelun signaali voi, jos ensimmäinen naapuri ei juuri
  vastaa, kulkea solmun kautta, joka näkee molemmat päät; hän saa tietää,
  että puhutte yhdessä.
- Suuren tiedoston, johon olet suostunut, näkee kone, joka välittää tai
  säilyttää sitä, molemmista päistä (katso luku 4).
- Puheluissa tarjoajalta suoja ei päde, ja kontaktisi näkee
  internet-osoitteesi (katso luku 7).

### Mitä tapahtuu, kun keskustelukumppanisi on offline-tilassa?

1. Cleona käynnistää kaikki sopivat reitit samanaikaisesti: samassa
   Wi-Fi-verkossa suoraan, internetissä kahden naapurin kautta -- ja lisäksi
   postilaatikon.
2. Postilaatikkoa varten Cleona tallentaa salatun viestin kolmen
   naapurin luo. Heti kun kaksi on vahvistanut vastaanoton, sitä
   pidetään talletettuna.
3. Cleona valitsee siihen ensisijaisesti naapureita, joiden luona
   keskustelukumppanisi myös katsoo -- ensin naapurin, jonka hänen
   kutsunsa nimeää.
4. Viesti odottaa siellä enintään 7 päivää. Kun keskustelukumppanisi
   palaa, hän noutaa sen ja vahvistaa sinulle vastaanoton. Vasta silloin
   näet kaksi ruksia.

Postilaatikon voi tyhjentää vain keskustelukumppanisi: noutaminen ja
poistaminen onnistuvat vain avaimella, joka on vain hänellä, ja
poistetaan vasta kun hän on vahvistanut vastaanoton. Naapurit näkevät vain
salattuja paketteja arvon alla, joka vaihtuu joka päivä.

### Tuntemattomat eivät pääse läpi

Joltakin, joka ei ole yhteystietosi eikä yhteisen ryhmän jäsen, Cleona
hyväksyy tarkalleen kaksi asiaa:
kysymyksen julkisista avaimistasi, kunhan jokin kutsuistasi on
avoin, ja yhteystietopyynnön. Pyynnössä on oltava
kelvollinen kutsusi, ja lähettäjän on ensin ratkaistava laskentatehtävä.
Kaikki muu -- viestit, puhelut, tiedostot -- hylätään,
ennen kuin se yletää sovellukseen asti. Joku, jolla on vain
painettu käyntikorttisi, ei siis voi vain soittaa sinulle. Yhteisen
ryhmän jäsen tavoittaa sinut vain tässä ryhmässä -- ryhmäviesteillä ja
ryhmäpuheluilla, ei koskaan yksitellen.

### Sensuurin vastustus

Cleona on rakennettu niin, että sitä on vaikea estää:

- **Ei palvelinta, ei kiinteää osoitetta.** Sovelluksessa ei ole osoitetta,
  jonka voisi estää, eikä verkko riipu mistään yksittäisestä solmusta.
- **Ei kiinteää porttia.** Jokainen laite valitsee ensimmäisen käynnistyksen
  yhteydessä satunnaisen portin. Ei ole tunnettua porttinumeroa, josta
  voisi tunnistaa Cleona-liikenteen.
- **Kuten satunnaisdataa.** Kahden laitteen välisen yhteyden muodostaminen
  on koodattu niin, ettei se ole erotettavissa satunnaisdatasta.
- **Monia sisäänpääsyjä.** Jokainen kutsu, jokainen naapuri ja jokainen laite
  samassa Wi-Fi-verkossa on mahdollinen tie takaisin verkkoon.

### Turvallinen avainten tallennus

Tuetuilla alustoilla Cleona tallentaa
salausavaimesi käyttöjärjestelmän turvalliseen avainrenkaaseen (Android
Keystore, iOS Keychain, macOS Keychain). Missä se on saatavilla, se tarjoaa
laitteistotuetun suojan avaimillesi.

### Tietokannan salaus

Viestisi ja keskustelusi ovat salatussa tietokannassa -- oma
kutakin identiteettiä kohden, kullakin oma avain.
Salattua ei ole vain itse tietokanta, vaan myös sen
väliaikaistiedostot; mitään ei kirjoiteta salauksetta levylle,
ei edes tilapäisesti. Asetukset, yhteystiedot ja mediat ovat myös
salattuna tallennettuja.

Avaimet johdetaan 24 sanastasi ja ovat olemassa vain
laitteellasi. Vaikka joku saisi laitteesi käsiinsä ja lukisi
tiedot, hän löytää ilman näitä avaimia vain lukukelvotonta dataa.

Salaamatonta se on vain siellä, missä annat itse sisältöjä ulos Cleonasta:
- kun tallennat tiedoston keskustelusta laitteellesi,
- kun laitat kuvakaappauksen painikkeella kuvan kuviisi,
- kun jaat jotain toiselle sovellukselle,
- kun perustat media-arkistoinnin (luku 13): Arkistoidut alkuperäiset
  ovat salauksettomina kotiverkkolevylläsi, jotta voit avata ne siellä
  myös ilman Cleonaa,
- kun peilaat tapahtumat Androidin järjestelmäkalenteriin: Siellä
  muut kalenteripääsyn omaavat sovellukset voivat lukea ne.

Mitä näin on ulos mennyt, ei poisteta viestin mukana eikä se vanhene sen
mukana.

### Suoja näytöllä

Androidissa, Windowsissa ja macOS:ssa Cleona ei anna muiden sovellusten
ottaa kuvakaappauksia. Jos tarvitset kuvaa, käytä kuvakaappauspainiketta
yläpalkissa: Se laittaa kuvan kuviisi -- salaamattomana. Keskustelussa,
jossa viestien edelleen välittäminen ei ole sallittua, kuvakaappausta
ei ole.

---

## 15. Ohjelmistopäivitykset

### Miten saan päivityksiä?

Cleona voidaan päivittää eri tavoilla. Tavoitteena on, että
voit saada päivityksiä silloinkin, kun yksittäiset jakelutiet pätkivät
tai estetään:

1. **App Store / Play Store:** Kun Cleona ilmestyy sinne ja olet asentanut
   sen kaupasta, saat päivitykset kuten totuttua kaupan kautta.
   iPhonessa päivitykset tulevat TestFlightin kautta.
2. **GitHub Releases:** Projektin GitHub-sivulta löydät
   allekirjoitetut asennuspaketit kaikille alustoille.
3. **Päivitykset verkon kautta:** Cleona voi hakea päivityksen suoraan
   verkon kautta -- ilman latauspalvelinta. Uusi versio on
   pilkottu virheenkorjattuihin osiin, jotka leviävät verkossa; osa
   niistä matkaavat jopa häivitysliikenteen mukana. Laitteesi kerää
   tarpeeksi osia ja kokoaa päivityksen. Siirretään yleensä vain
   muutos -- muutama megatavu koko sovelluksen sijaan. Tämä pätee
   Linuxiin, Windowsiin ja Androidiin; macOS:ssa lataat uudet versiot
   verkkosivustolta tai GitHubista.
4. **Kutsulinkit:** Voit luoda kutsulinkkejä, jotka sisältävät
   kaiken, mitä uusi käyttäjä tarvitsee asentaakseen Cleonan ja
   yhdistääkseen verkkoon.
5. **Fyysinen siirto:** Ympäristöissä ilman internetiä voit antaa Cleonan
   toisille USB-tikutlla tai paikallisessa verkossa.

### Miten päivitys etenee

1. Cleona kerää uuden päivityksen osat automaattisesti taustalla
   ja kokoaa ne.
2. Vasta kun päivitys on **täydellinen** ja sen **allekirjoitus
   on tarkistettu**, Cleona tarjoaa sitä sinulle. Et siis saa koskaan
   puoliakaan tai tarkistamatonta päivitystä.
3. Kun napautat "Asenna", asennus alkaa ilman
   jatkokysymystä. Androidissa järjestelmä näyttää lisäksi
   asennusikkunan.

Vanhempia versioita ei tarjota -- päivitys menee aina vain
eteenpäin. Jos versio on niin vanha, ettei se enää osaa
toimia yhdessä verkon kanssa, Cleona näyttää sen selkeästi ja pyytää
sinua päivittämään.

### Allekirjoituksen tarkistus

Jokainen päivitys on kaksoisallekirjoitettu: klassisella ja
post-kvanttimenetelmällä. Cleona tarkistaa molemmat allekirjoitukset
automaattisesti. Näin
varmistetaan, että vain virallisen kehittäjän päivitykset hyväksytään
-- vaikka päivitys tulisi verkon kautta vieraista laitteista.
Päivitys ei synny koskaan automaattisesti kehityksestä, vaan
vasta kun kehittäjä allekirjoittaa sen käsin.

---
## 16. Usein kysytyt kysymykset

### "Voinko käyttää Cleonaa ilman internetiä?"

Cleona tarvitsee verkkoyhteyden, mutta ei välttämättä internetiä:
Samassa Wi-Fi-verkossa Cleona-laitteet löytävät toisensa ja voivat
kirjoittaa toisilleen täysin ilman internet-yhteyttä. Sinun ei tarvitse olla
samaan aikaan online-tilassa keskustelukumppanisi kanssa: Jos hän on
offline-tilassa, viesti odottaa enintään 7 päivää
postilaatikossa kolmen naapurin luona, kunnes hän noutaa sen.

### "Mitä jos menetän siemenfraasini?"

Niin kauan kuin yksi laite, jossa on identiteettisi, pyörii, mikään ei ole
hukassa -- siellä kirjoitat vain eteenpäin. Laitteella, jolla loit
identiteetin, voit yleensä lukea 24 sanaa uudelleen (katso
luku 2). Älä nojaa siihen: Uudelleenasennus raivaa tämän kopion pois,
ja Androidissa myös näyttölukituksen poistaminen tai muuttaminen tuhoaa
sen. Jos sinulla ei ole
sanoja etkä
yhtäkään laitetta, ei ole paluutietoa -- ei edes yhteystitojesi,
kehittäjän tai kenen tahansa muun kautta. Siksi on niin tärkeää
säilyttää 24 sanaa turvassa.

### "Voiko joku lukea viestejäni mukanani?"

Ei. Jokainen viesti salataan kertakäyttöisellä avaimella, joka
kelpaa vain tähän yhteen viestiin. Vain sinä ja keskustelukumppanisi voitte
purkaa viestin. Ei ole keskitettyä palvelinta, ei pääavainta
eikä pääsyä kehittäjälle. Vaikka jokin laite matkalla
välittäisi viestin eteenpäin, se näkee vain salattua datasotaa
ja koodin. Naapurisi tietää, että paketti tulee sinulta, mutta ei kenelle
se menee; keskustelukumppanisi naapuri tietää, kenelle se menee, mutta ei
keneltä.

### "Miksi en tarvitse puhelinnumeroa?"

Koska identiteettisi on puhtaasti kryptografinen. Puhelinnumeron tai
sähköpostiosoitteen sijaan, joka on sidottu oikeaan nimeesi, sinut tunnistaa
avainpari, joka on luotu laitteellasi. Yhteystietoja lisäät
QR-koodin, NFC:n tai kutsusi tekstirivin kautta -- et
puheluhakemiston kautta. Tämä tarkoittaa
enemmän yksityisyyttä, koska viestitilisi ei ole sidottu
todelliseen identiteettiisi.

### "Miten löydän ihmisiä Cleonasta?"

Cleonassa ei tahallisesti ole yhteystietohakua puhelinnumeron tai nimen
perusteella -- se olisi
yksityisyysongelma. Sen sijaan vaihdatte kutsut suoraan: QR-koodilla,
NFC:llä tai tekstirivinä toista reittiä. Se on kuin
vaihtaisitte käyntikortteja sen sijaan, että katsoisitte puhelinluettelosta.

### "Toimiiko Cleona myös ulkomailla?"

Kyllä. Niin kauan kuin sinulla on internet-yhteys, Cleona toimii kaikkialla
maailmassa. Koska ei ole keskitettyä palvelinta eikä kiinteää osoitetta,
palvelua ei voi yksinkertaisesti katkaista tietyille maille. Miten Cleona
vaikeuttaa estoja, lue luvusta "Tietoturva" kohdasta "Sensuurin vastustus".
Maa, joka
estää jokaisen tuntemattoman liikenteen rajalla, voi kuitenkin myös
pysäyttää Cleonan.

### "Onko Cleona ilmainen?"

Kyllä. Cleona on ilmainen ja käytettävissä ilman mainoksia. Koska ei ole
keskitettyä
palvelinta, palvelinkuluja ei myöskään synny käytön vuoksi. Asetuksissa
kohdasta "Tue Cleonaa" -> "Lahjoita" voit tukea
kehitystä vapaaehtoisesti.

### "Viestilläni on vain yksi ruks -- mitä se tarkoittaa?"

Viesti on matkalla, mutta keskustelukumppanisi ei ole vielä vahvistanut
vastaanottoa -- useimmiten koska hän on juuri offline-tilassa. Se ei ole
virhe: Viesti odottaa enintään 7 päivää postilaatikossa. Heti kun hän
noutaa sen, näet kaksi ruksia. Kello tarkoittaa, että yksikään reitti ei
ole vielä kantanut viestiä -- se lähtee itsestään, kunhan sellainen on;
varoitustermerkki, ettei viesti 14 päivän aikana löytänyt reittiä ja
voit lähettää sen uudelleen.

### "Miksi viestit saapuvat iPhonellani myöhässä?"

iOS ei anna sovellusten pyöriä taustalla jatkuvasti. Cleona herätetään vain
ajoittain lyhyeksi aikaa; milloin, iOS päättää. Se noutaa tällöin kaiken.
Heti kun avaat sovelluksen, Cleona noutaa sinulle säilytetyn.

### "Voinko vaihtaa WhatsAppista Cleonaan?"

Kyllä, mutta et voi siirtää WhatsApp-keskustelujasi. Cleona ja WhatsApp
ovat täysin erilaisia järjestelmiä. Sinun on lisättävä yhteystietosi
yksitellen Cleonaan. Helpointa se on, kun lähetät
kutsusi tekstirivin yhteystiedoillesi. Jokaisen näin saapuvan pyynnön
vahvistat itse kohdassa "Pyynnöt".

### "Voinko käyttää Cleonaa usealla laitteella yhtä aikaa?"

Ei vielä. Toinen laite samalle identiteetille tulee myöhemmässä
versiossa (luku 11). Usealla laitteella voit tänään käyttää eri
identiteettejä.

### "Miten saan päivityksiä kun App Store on estetty?"

Cleona voi hakea päivityksiä suoraan verkon kautta, ilman
App Storea, verkkosivustoa tai latauspalvelinta. Jos
jokin muu laite verkossa on uusin versio, laitteesi voi ladata
päivityksen sieltä. Echttiyys tarkistetaan kehittäjän
digitaalisen allekirjoituksen avulla. Vaihtoehtoisesti yhteystieto voi
antaa sinulle sovelluksen kutsulinkin tai USB-tikut kautta. Lisää aiheesta
luvussa "Ohjelmistopäivitykset".

---

## Apu ja yhteystiedot

Jos sinulla on kysymyksiä tai kohtaat ongelman, löydät ajankohtaiset
tiedot Cleona-sivustolta ja GitHubista. Koska Cleona on hajautettu
projekti, ei ole klassista asiakastukea -- mutta aktiivinen
yhteisö, joka auttaa mielellään.

---

*Tämä ohje kuvaa Cleona Chat versio 4.2. Yksittäiset toiminnot
voivat muuttua tai laajentua uudemmissa versioissa.*
# Cleona Chat -- Käyttöopas

Versio 3.1.125 | Heinäkuu 2026

---

## Sisällysluettelo

1. [Mikä on Cleona Chat?](#1-mikä-on-cleona-chat)
2. [Alkuun pääseminen](#2-alkuun-pääseminen)
3. [Yhteystiedot](#3-yhteystiedot)
4. [Viestit](#4-viestit)
5. [Ryhmät](#5-ryhmät)
6. [Julkiset kanavat](#6-julkiset-kanavat)
7. [Puhelut](#7-puhelut)
8. [Kalenteri](#8-kalenteri)
9. [Kyselyt](#9-kyselyt)
10. [Useita identiteettejä](#10-useita-identiteettejä)
11. [Multi-Device](#11-multi-device)
12. [Palautus](#12-palautus)
13. [Asetukset](#13-asetukset)
14. [Turvallisuus](#14-turvallisuus)
15. [Ohjelmistopäivitykset](#15-ohjelmistopäivitykset)
16. [Usein kysytyt kysymykset](#16-usein-kysytyt-kysymykset)

---

## 1. Mikä on Cleona Chat?

### Sinun viestimesi, sinun tietosi

Cleona Chat on viestisovellus, joka toimii täysin ilman keskitettyä palvelinta.
Viestisi kulkevat suoraan laitteeltasi vastaanottajan laitteelle -- ilman
kiertotietä minkään yrityksen kautta, ilman pilvipalvelua, ilman
datakeskusta. Mikään yritys ei voi lukea, tallentaa tai luovuttaa viestejäsi,
koska välissä ei yksinkertaisesti ole mitään yritystä.

### Ei tiliä, ei puhelinnumeroa

Cleonassa et tarvitse puhelinnumeroa etkä sähköpostiosoitetta
rekisteröitymiseen. Identiteettisi koostuu kryptografisesta avainparista, joka
luodaan automaattisesti laitteellasi ensimmäisellä käynnistyskerralla. Tämä
tarkoittaa: kukaan ei voi löytää sinua puhelinnumerosi tai
sähköpostiosoitteesi perusteella, ellet itse jaa yhteystietojasi.

### Tulevaisuudenkestävä salaus

Cleona käyttää niin sanottua Post-Quantum-salausta. Tämä tarkoittaa: edes
tulevaisuuden kvanttitietokoneet eivät pystyisi murtamaan viestejäsi. Sinun
ei tarvitse ymmärtää yksityiskohtia -- tärkeää on vain, että viestintäsi on
suojattu parhaalla mahdollisella tavalla nykytekniikan mukaisesti.

### Miten se toimii ilman palvelinta?

Kuvittele, että sinä ja yhteyshenkilösi muodostatte yhdessä verkon. Jokainen
laite auttaa viestien välittämisessä. Jos vastaanottajasi on parhaillaan
verkossa, viesti menee suoraan perille. Jos vastaanottajasi on offline,
yhteiset kontaktit tallentavat viestin väliin ja toimittavat sen heti, kun
vastaanottaja on taas tavoitettavissa. Yhteyshenkilösi ovat siis samalla myös
sinun verkkosi.

### Alustat

Cleona on saatavilla Androidille, iOS:lle, macOS:lle, Linuxille ja Windowsille.

---

## 2. Alkuun pääseminen

### Sovelluksen asentaminen

**Android:**
1. Lataa APK-tiedosto Cleonan verkkosivuilta tai GitHub Releases -sivulta.
2. Avaa tiedosto puhelimessasi. Tarvittaessa salli asentaminen tuntemattomista
   lähteistä (Android kysyy automaattisesti).
3. Napauta "Asenna" ja odota, kunnes asennus on valmis.

**iOS:**
1. Avaa TestFlight-kutsulinkki iPhonessasi.
2. Napauta "Asenna". TestFlight on Applen virallinen tapa jakaa
   beta-sovelluksia.
3. Asennuksen jälkeen löydät Cleonan aloitusnäytöltäsi.

**macOS:**
1. Lataa DMG-tiedosto Cleonan verkkosivuilta tai GitHub Releases -sivulta.
2. Avaa DMG ja vedä Cleona Ohjelmat-kansioon.
3. Ensimmäisellä käynnistyskerralla macOS saattaa kysyä, haluatko avata
   tunnistetun kehittäjän sovelluksen -- vahvista tämä.

**Linux (Ubuntu/Debian):**
1. Lataa .deb-tiedosto Cleonan verkkosivuilta tai GitHub Releases -sivulta.
2. Asenna kaksoisnapsauttamalla tai terminaalissa: `sudo dpkg -i cleona-chat_VERSION_amd64.deb`
3. Käynnistä Cleona sovellusvalikosta tai terminaalissa komennolla `cleona-chat`.

**Linux (Fedora/openSUSE):**
1. Lataa .rpm-tiedosto Cleonan verkkosivuilta tai GitHub Releases -sivulta.
2. Asenna komennolla: `sudo dnf install cleona-chat-VERSION.x86_64.rpm`
3. Käynnistä Cleona sovellusvalikosta tai terminaalissa komennolla `cleona-chat`.

**Linux (kaikki jakelut -- AppImage):**
1. Lataa .AppImage-tiedosto Cleonan verkkosivuilta tai GitHub Releases -sivulta.
2. Tee tiedostosta suoritettava: hiiren oikea painike, Ominaisuudet, Suoritettava, tai terminaalissa: `chmod +x cleona-chat-VERSION-x86_64.AppImage`
3. Käynnistä kaksoisnapsauttamalla tai terminaalissa: `./cleona-chat-VERSION-x86_64.AppImage`

**Windows:**
1. Lataa asennusohjelma Cleonan verkkosivuilta tai GitHub Releases -sivulta.
2. Suorita asennustiedosto ja seuraa ohjeita.
3. Käynnistä Cleona Käynnistä-valikosta tai työpöydän pikakuvakkeesta.

### Identiteetin luominen

Ensimmäisellä käynnistyskerralla Cleona luo automaattisesti uuden identiteetin
sinulle. Voit antaa itsellesi näyttönimen -- se on nimi, jonka yhteyshenkilösi
näkevät. Tätä nimeä voi muuttaa milloin tahansa.

### Seed-lauseen kirjoittaminen muistiin -- kaikkein tärkein asia

Identiteetin luomisen jälkeen Cleona näyttää sinulle 24 sanaa. Tämä on
**seed-lauseesi** -- henkilökohtainen palautusavaimesi.

**Kirjoita nämä 24 sanaa paperille ja säilytä ne turvallisessa paikassa.**

Miksi tämä on niin tärkeää?

- Jos puhelimesi hajoaa, katoaa tai varastetaan, voit näillä 24 sanalla
  palauttaa koko identiteettisi uudella laitteella.
- Ilman seed-lausetta paluutietä ei ole. Mitään "Unohdin salasanan"
  -painiketta ei ole eikä tukea, joka voisi palauttaa tilisi -- koska
  mitään tiliä ei ole millään palvelimella.
- Älä koskaan anna seed-lausetta muille. Se joka tuntee nämä sanat, voi
  esiintyä sinuna.

Löydät seed-lauseen myöhemmin myös asetuksista kohdasta "Turvallisuus", jos
haluat lukea sen uudelleen.

### Ensimmäisen yhteyshenkilön lisääminen

Jotta voit keskustella jonkun kanssa, sinun täytyy ensin lisätä henkilö
yhteyshenkilöksi. Tähän on useita tapoja -- ne kaikki selitetään seuraavassa
osiossa.

---

## 3. Yhteystiedot

### QR-koodin skannaaminen (suositeltu)

Helpoin tapa lisätä yhteyshenkilö:

1. Vastaanottajasi avaa identiteettisivunsa (napauta omaa nimeä yläpalkissa) ja
   näyttää sinulle QR-koodinsa.
2. Napauta plus-painiketta ja valitse "Skannaa QR-koodi".
3. Pidä puhelintasi vastaanottajasi QR-koodin edessä.
4. Yhteystietopyyntö lähetetään automaattisesti. Kun vastaanottajasi hyväksyy
   sen, voitte alkaa keskustella.

Kun tapaatte henkilökohtaisesti, QR-koodi on turvallisin menetelmä, koska
tiedät tarkalleen kenen kanssa vaihdat yhteystiedot.

### NFC (puhelimien pitäminen vastakkain)

Jos molemmat laitteet tukevat NFC:tä:

1. Avatkaa molemmat yhteystiedon lisäystoiminto.
2. Pitäkää puhelimianne selät vastakkain.
3. Yhteystiedot vaihdetaan automaattisesti.

NFC tarjoaa QR-koodin tavoin korkean turvallisuustason, koska vaihto toimii
vain kun seisotte fyysisesti vierekkäin.

### Linkin jakaminen (cleona://-URI)

Voit myös lähettää yhteystietolinkisi sähköpostilla, tekstiviestillä tai
toisen viestisovelluksen kautta:

1. Avaa identiteettisivusi.
2. Kopioi cleona://-linkkisi.
3. Lähetä linkki henkilölle, jonka haluat lisäävän sinut.
4. Toinen henkilö avaa linkin tai liittää sen
   yhteystiedon lisäysikkunassa.

Huomaa: Tässä menetelmässä luotat siihen, ettei linkkiä ole muutettu
siirron aikana. Erityisen arkaluontoisille yhteystiedoille suosittelemme
QR-koodia tai NFC:tä.

### Yhteystietopyyntöjen hyväksyminen

Kun joku lähettää sinulle yhteystietopyynnön, se näkyy saapuneet-kansiossasi
(viimeinen välilehti alapalkissa). Siellä voit:

- **Hyväksyä** -- henkilö lisätään yhteystietoihisi.
- **Hylätä** -- pyyntö hylätään.
- **Estää** -- henkilö ei voi lähettää sinulle enää pyyntöjä.

### Vahvistustasot

Cleona näyttää sinulle, kuinka varmasti yhteyshenkilön identiteetti on
vahvistettu:

| Taso | Merkitys |
|------|----------|
| Tuntematon | Olet saanut vain Node-ID:n tai linkin. |
| Nähty | Avainten vaihto onnistui, voitte kommunikoida salattuina. |
| Vahvistettu | Olette tavanneet henkilökohtaisesti ja vahvistaneet QR-koodilla tai NFC:llä. |
| Luotettu | Olet nimenomaisesti merkinnyt tämän yhteyshenkilön luotetuksi. |

Mitä korkeampi taso, sitä varmempi voit olla, että puhut todella oikean
henkilön kanssa.

---

## 4. Viestit

### Tekstin lähettäminen ja vastaanottaminen

Kirjoita viestisi alareunan syöttökenttään ja paina Enter tai Lähetä-painiketta.
Viestisi salataan automaattisesti ennen kuin se lähtee laitteestasi.

Saapuvat viestit näkyvät keskusteluhistoriassa. Merkki näyttää sinulle, onko
viestisi toimitettu.

### Kuvien, videoiden ja tiedostojen lähettäminen

Sinulla on useita vaihtoehtoja:

- **Paperiliitinkuvake** syöttökentässä: napauta sitä valitaksesi tiedoston,
  kuvan tai videon galleriastasi tai tiedostojärjestelmästäsi.
- **Vedä ja pudota** (työpöytä): vedä tiedosto keskusteluikkunaan.
- **Leikepöydältä liittäminen** (työpöytä): kopioi kuva ja liitä se
  keskusteluun.

Pienet tiedostot (alle 256 KB) lähetetään suoraan mukana. Suuremmat tiedostot
siirretään kaksivaiheisessa menettelyssä: ensin tiedosto ilmoitetaan, sitten
se lähetetään osissa.

### Ääniviestit

1. Pidä mikrofoni-painiketta painettuna syöttökentässä.
2. Puhu viestisi.
3. Vapauta painike lähettääksesi viestin.

Jos puheentunnistus on aktivoitu laitteellasi (katso asetukset), ääniviestisi
muunnetaan automaattisesti tekstiksi. Vastaanottajasi näkee sekä äänitteen
että muunnetun tekstin.

### Viesteihin vastaaminen (lainaaminen)

Vastataksesi tiettyyn viestiin:

1. Avaa kolmen pisteen valikko viestin vieressä.
2. Valitse "Vastaa".
3. Syöttökentän yläpuolelle ilmestyy banneri lainatun viestin kanssa.
4. Kirjoita vastauksesi ja lähetä se.

Lainattu viesti näytetään vastauksessasi, jotta yhteys on selvä.

### Viestien muokkaaminen ja poistaminen

- **Muokkaaminen:** viestin kolmen pisteen valikko, sitten "Muokkaa".
  Muuta tekstiä ja lähetä se uudelleen. Vastaanottajasi näkee, että viestiä
  on muokattu. Muokkaaminen on mahdollista 15 minuutin kuluessa lähettämisestä.
- **Poistaminen:** viestin kolmen pisteen valikko, sitten "Poista". Viesti
  poistetaan sekä sinulta että vastaanottajaltasi. Voit poistaa omat viestisi
  milloin tahansa -- poistamiselle ei ole aikarajaa.

### Emoji-reaktiot

Sen sijaan, että kirjoittaisit vastauksen, voit reagoida viestiin emojilla:

1. Avaa kolmen pisteen valikko tai paina viestiä pitkään.
2. Valitse emoji pikavalikoimasta tai avaa emoji-valitsin koko valikoimalle.
3. Reaktiosi näkyy viestin alla.

### Tekstin kopioiminen

Viestin kolmen pisteen valikon kautta voit kopioida viestin tekstin
leikepöydälle.

### Viestien hakeminen

Keskusteluikkunan yläreunasta löydät hakutoiminnon. Syötä hakusana, ja Cleona
näyttää kaikki osumat nykyisessä keskustelussa. Nuolinäppäimillä voit
hypätä osumien välillä.

Aloitusnäytöllä on lisäksi välilehtien yli toimiva hakusuodatin, jolla voit
hakea kaikista keskusteluista.

### Linkin esikatselu

Kun lähetät linkin, Cleona luo automaattisesti esikatselun (otsikko,
kuvaus, esikatselukuva). Tämä esikatselu luodaan laitteellasi ja lähetetään
mukana -- vastaanottajasi ei tarvitse muodostaa yhteyttä linkitettyyn
verkkosivustoon.

Kun napautat vastaanotettua linkkiä, sinulta kysytään, haluatko avata sen
normaalissa selaimessa, incognito-tilassa vai et ollenkaan.

---

## 5. Ryhmät

### Ryhmän luominen

1. Vaihda "Ryhmät"-välilehdelle.
2. Napauta plus-painiketta.
3. Anna ryhmälle nimi.
4. Valitse yhteyshenkilöt, jotka haluat kutsua.
5. Napauta "Luo".

Kutsutut yhteyshenkilöt saavat ilmoituksen ja voivat liittyä ryhmään.

### Jäsenten kutsuminen

Voit kutsua lisää yhteyshenkilöitä myös luomisen jälkeen:

1. Avaa ryhmätiedot (kolmen pisteen valikko ryhmänäkymässä tai yläpalkki
   ryhmäkeskustelussa).
2. Napauta "Kutsu".
3. Valitse yhteyshenkilöt, jotka haluat lisätä.

### Roolit

Jokaisessa ryhmässä on kolme roolia:

- **Omistaja (Owner):** Täysi hallinta. Voi lisätä ja poistaa jäseniä,
  nimittää ylläpitäjiä ja hallita ryhmää. Omistaja voi myös siirtää
  asemansa toiselle jäsenelle.
- **Ylläpitäjä (Admin):** Voi poistaa jäseniä ja auttaa hallinnassa.
- **Jäsen:** Voi lukea ja kirjoittaa viestejä.

### Ryhmästä poistuminen

1. Avaa kolmen pisteen valikko ryhmänäkymässä.
2. Valitse "Poistu".
3. Vahvista päätöksesi.

Kun poistut ryhmästä, aiemmat viestisi jäävät näkyviin muille jäsenille.

---

## 6. Julkiset kanavat

### Mitä kanavat ovat?

Kanavat ovat julkisia keskustelufoorumeja Cleona-verkossa. Toisin kuin
ryhmissä, kuka tahansa voi lukea niitä ilman kutsua. Vain omistaja ja
ylläpitäjät voivat julkaista sisältöä -- tilaajat lukevat mukana.

### Kanavien löytäminen ja liittyminen

1. Vaihda "Kanavat"-välilehdelle.
2. Avaa "Haku"-välilehti.
3. Selaa saatavilla olevia kanavia nimen tai aiheen mukaan.
4. Napauta kanavaa ja sitten "Tilaa".

Kanavia voi suodattaa kielen mukaan. Jotkut kanavat on merkitty "Ei
alaikäisille" -- nämä näkyvät vain, jos olet vahvistanut profiilissasi
olevasi yli 18-vuotias.

### Oman kanavan luominen

1. Vaihda "Kanavat"-välilehdelle.
2. Napauta plus-painiketta.
3. Anna kanavan nimi (sen on oltava yksilöllinen koko verkossa).
4. Valitse kieli ja onko kanava julkinen vai yksityinen.
5. Valinnainen: lisää kuvaus ja kuva.
6. Napauta "Luo".

Julkisissa kanavissa voit määrittää, luokitellaanko sisältö
"Ei alaikäisille" -sisällöksi.

### Sisällön ilmiantaminen

Jos huomaat julkisessa kanavassa sopimatonta sisältöä, voit ilmiantaa sen.
Cleona käyttää hajautettua moderointijärjestelmää: ilmiannot arvioidaan
satunnaisesti valittujen verkon jäsenten toimesta (eräänlainen
"valamiehistö"). Jos rikkomus todetaan, kanava saa varoituksen. Toistuvien
rikkomusten yhteydessä kanava alennetaan hakuindeksissä tai estetään.

### Järjestelmäkanavat

Cleonassa on kaksi sisäänrakennettua järjestelmäkanavaa:

- **Bug Log:** Kun Cleona havaitsee virheen, se kysyy sinulta, haluatko
  lähettää anonymisoidun virheraportin. Nämä raportit päätyvät
  Bug Log -kanavalle, jossa yhteisö voi tarkastella niitä. Henkilökohtaisia
  tietoja ei siirretä -- vain teknisiä virhekuvauksia. Voit myös lähettää
  lokiraportin manuaalisesti (esikatseludialogi ja nimenomainen suostumus).
- **Feature Requests:** Täällä käyttäjät voivat esittää toiveita
  ominaisuuksista ja äänestää olemassa olevia ehdotuksia. Ehdotukset
  lajitellaan äänten mukaan.

Molemmilla järjestelmäkanavilla on 25 MB:n kokorajoitus, ja niitä
valvotaan valamiehistömoderaatiojärjestelmällä.

---

## 7. Puhelut

### Äänipuhelun aloittaminen

1. Avaa keskustelu yhteyshenkilön kanssa, jolle haluat soittaa.
2. Napauta puhelinkuvaketta yläpalkissa.
3. Odota, kunnes vastaanottajasi vastaa puheluun.

Puhelun aikana näet aikajanan, puhelun keston ja sinulla on pääsy
mykistys- ja kaiutintoimintoihin.

Lopettaaksesi paina punaista lopetuspainiketta.

### Videopuhelun aloittaminen

1. Avaa keskustelu yhteyshenkilön kanssa.
2. Napauta kamerakuvaketta yläpalkissa.
3. Videokuvasi näkyy pienessä ikkunassa, vastaanottajasi kuva suuressa
   alueessa.

Voit vaihtaa etu- ja takakameran välillä puhelun aikana.

### Saapuvat puhelut

Kun joku soittaa sinulle, näkyviin tulee ilmoitusikkuna soittajan nimellä.
Voit:

- **Vastata** -- puhelu alkaa.
- **Hylätä** -- soittajalle ilmoitetaan.

Jos olet jo puhelussa, uusi puhelu hylätään automaattisesti.

### Ryhmäpuhelut

Voit myös käydä ryhmäpuheluita, joihin useat henkilöt osallistuvat
samanaikaisesti. Puhelu järjestetään älykkään välityspuun kautta, joten
jokaisen osallistujan ei tarvitse olla suoraan yhteydessä jokaiseen toiseen.
Kaikki puhelut ovat päästä päähän salattuja.

### Salaus puheluissa

Kaikki puhelut salataan kertakäyttöisillä avaimilla, jotka ovat olemassa vain
puhelun ajan. Puhelun päätyttyä avaimet poistetaan välittömästi. Kukaan ei
voi jälkikäteen purkaa aiemman puhelun salausta.

---

## 8. Kalenteri

Cleona sisältää sisäänrakennetun kalenterin, joka on salattu ja toimii täysin
hajautetusti -- ilman pilvipalvelua.

### Näkymät

Kalenteri tarjoaa viisi näkymää: päivä, viikko, kuukausi, vuosi ja
tehtävänäkymä. Vaihda niiden välillä kalenterinäytön yläreunassa olevien
välilehtien kautta.

### Tapahtumien luominen

Napauta aikaväliä tai käytä lisäyspainiketta luodaksesi uuden tapahtuman.
Voit syöttää otsikon, päivämäärän, kellonajan, paikan ja muistiinpanoja.
Tapahtumat tallennetaan salattuina laitteellesi.

### Toistuvat tapahtumat

Tapahtumat voivat toistua päivittäin, viikoittain, kuukausittain tai
vuosittain. Voit mukauttaa kaavaa (esim. joka toinen tiistai, joka kuukauden
ensimmäinen päivä) ja asettaa päättymispäivän tai toistojen määrän.

### Yhteyshenkilöiden kutsuminen

Tapahtumaa luodessasi tai muokatessasi voit kutsua Cleona-yhteyshenkilöitäsi.
He saavat salatun kalenterikutsun ja voivat vastata hyväksymällä, hylkäämällä
tai ehkä-vastauksella. Tapahtuman muutokset lähetetään automaattisesti
kaikille kutsutuille.

### Vapaa/varattu-näyttö

Voit jakaa saatavuutesi yhteyshenkilöiden kanssa paljastamatta
tapahtumatietoja. Yksityisyystasoja on kolme: täydet tiedot, vain aikablokit
tai piilotettu. Voit asettaa oletusasetuksen ja ohittaa sen yhteyshenkilökohtaisesti.

### Muistutukset

Tapahtumiin voi liittää muistutuksia, jotka laukaisevat
järjestelmäilmoituksen ennen tapahtuman alkua. Voit torkuttaa muistutuksia
tarvittaessa.

### Ulkoinen kalenterisynkronointi

Cleona voi synkronoida ulkoisten kalenteripalveluiden kanssa:

- **CalDAV** -- yhdistä mihin tahansa CalDAV-yhteensopivaan palvelimeen
  (Nextcloud, Radicale jne.).
- **Google-kalenteri** -- synkronointi Google Calendar API:n kautta
  turvallisella OAuth2-todennuksella.
- **Paikallinen CalDAV-palvelin** -- Cleona voi käynnistää paikallisen
  CalDAV-palvelimen laitteellasi, jotta työpöydän kalenterisovellukset
  (Thunderbird, Outlook, Apple-kalenteri, Evolution) voivat synkronoida
  Cleona-kalenterisi kanssa.
- **Androidin järjestelmäkalenteri** -- Cleonan tapahtumat voidaan siirtää
  Android-laitteesi sisäänrakennettuun kalenterisovellukseen.
- **ICS-tiedostot** -- tuo ja vie tapahtumia standardi-iCalendar-muodossa.

### PDF-vienti

Voit tulostaa tai viedä minkä tahansa kalenterinäkymän (päivä, viikko,
kuukausi, vuosi) PDF-dokumenttina.

---

## 9. Kyselyt

Voit luoda kyselyitä missä tahansa keskustelussa tai ryhmässä kerätäksesi
mielipiteitä tai suunnitellaksesi aikatauluja.

### Kyselytyypit

Cleona tukee viittä kyselytyyppiä:

- **Yksittäisvalinta** -- osallistujat valitsevat yhden vaihtoehdon.
- **Monivalinta** -- osallistujat voivat valita useita vaihtoehtoja.
- **Ajankohtakysely** -- löydä kaikille sopiva ajankohta. Jokainen
  osallistuja merkitsee ajankohdat sopivaksi, ehkä tai ei sovi.
- **Asteikko** -- arvioi jotain numeerisella asteikolla (esim. 1-5).
- **Vapaa teksti** -- osallistujat kirjoittavat oman vastauksensa.

### Kyselyn luominen

Avaa keskustelu ja napauta kyselykuvaketta (tai käytä liitevalikkoa). Valitse
kyselytyyppi, muotoile kysymyksesi ja vaihtoehdot ja lähetä kysely. Se
näkyy viestinä keskustelussa.

### Äänestäminen

Napauta kyselyä antaaksesi äänesi. Voit muuttaa tai perua äänesi
milloin tahansa.

### Anonyymi äänestys

Kyselyt voidaan määrittää anonyymiksi äänestykseksi. Kun se on aktivoitu,
äänet ovat kryptografisesti anonyymeja -- kukaan, ei edes kyselyn luoja, ei
voi nähdä kuka äänesti mitäkin. Äänten lukumäärä pysyy silti näkyvissä.

### Ajankohtakyselystä kalenteriin

Kun ajankohtakysely on valmis, voittanut ajankohta voidaan muuntaa suoraan
kalenterimerkinnäksi yhdellä napautuksella.

---

## 10. Useita identiteettejä

### Miksi useita identiteettejä?

Kuvittele, että haluat pitää työ- ja yksityiselämäsi erillään -- samaan
tapaan kuin kahdella eri puhelinnumerolla, mutta ilman toista puhelinta.
Cleonassa voit käyttää useita identiteettejä yhdellä laitteella. Jokaisella
identiteetillä on oma nimi, oma profiilikuva, omat yhteyshenkilöt ja omat
keskustelut.

### Uuden identiteetin luominen

1. Yläpalkissa näet nykyisen identiteettisi välilehtenä.
2. Napauta plus-merkkiä (+) identiteettivälilehtien oikealla puolella.
3. Anna uudelle identiteetille nimi.
4. Valmis -- uusi identiteetti on heti aktiivinen.

### Identiteettien välillä vaihtaminen

Napauta yksinkertaisesti identiteettivälilehteä yläpalkissa. Vaihto on
välitön -- ei odotusaikaa, ei uudelleenlatausta.

### Kaikki toimivat samanaikaisesti

Tärkeä seikka: kaikki identiteettisi ovat samanaikaisesti aktiivisia. Vaikka
sinulla olisi "Työ"-identiteetti näkyvissä, "Yksityinen"-identiteettisi
vastaanottaa edelleen viestejä. Et menetä mitään riippumatta siitä, mikä
identiteetti on valittuna.

### Identiteetin tietosivu

Kun napautat aktiivisen identiteettisi välilehteä, tietosivu avautuu. Täällä
voit:

- Näyttää QR-koodisi yhteystietoja varten.
- Vaihtaa tai poistaa profiilikuvasi.
- Lisätä profiilikuvauksen.
- Vaihtaa näyttönimesi.
- Valita ulkoasun (skin) tälle identiteetille.
- Poistaa identiteetin, jos et enää tarvitse sitä.

### Identiteetin poistaminen

Kun poistat identiteetin, yhteyshenkilöillesi ilmoitetaan asiasta.
Identiteetti ja kaikki siihen liittyvät tiedot poistetaan laitteestasi. Tätä
toimintoa ei voi peruuttaa.

---

## 11. Multi-Device

### Cleonan käyttäminen useilla laitteilla

Voit käyttää samaa identiteettiä jopa 5 laitteella samanaikaisesti. Yksi
laite on ensisijainen (se pitää seed-lauseen), ja lisälaitteet linkitetään
siihen.

### Uuden laitteen linkittäminen

1. Avaa asetukset ensisijaisella laitteellasi.
2. Siirry kohtaan "Linkitetyt laitteet".
3. Valitse "Linkitä uusi laite".
4. Asenna Cleona uudelle laitteelle ja valitse käynnistyksen yhteydessä
   "Linkitä olemassa olevaan laitteeseen".
5. Skannaa paritus-QR-koodi, joka näkyy ensisijaisella laitteellasi, tai
   käytä parituslinkkiä.

Linkitetty laite saa delegointisertifikaatin ensisijaiselta laitteelta.
Linkitetyltä laitteelta lähetetyt viestit on kryptografisesti allekirjoitettu
delegoidulla avaimella, joten yhteyshenkilöt voivat varmistaa, että viesti
todella tulee sinun identiteetiltäsi.

### Miten se toimii

- Ensisijainen laite pitää seed-lauseesi ja pääavaimet.
- Linkitetyt laitteet saavat johdetut allekirjoitusavaimet ja
  delegointisertifikaatin -- ne eivät koskaan saa itse seed-lausetta.
- Kaikki laitteet jakavat saman identiteetin ja yhteyshenkilöt. Viestit
  saapuvat kaikille laitteille.
- Delegointisertifikaatit uusitaan automaattisesti ennen voimassaolon
  päättymistä.

### Laitteiden hallinta

Avaa asetukset ja siirry kohtaan "Linkitetyt laitteet" nähdäksesi kaikki
linkitetyt laitteesi, niiden tilan ja viimeisimmän aktiviteetin. Voit
peruuttaa linkitetyn laitteen milloin tahansa, jos se katoaa tai varastetaan.

### Hätäavainten vaihto

Jos epäilet laitteen joutuneen vaarannetuksi, voit käynnistää
hätäavainten vaihdon. Tällöin luodaan uudet avaimet, ja vaihdon on saatava
vahvistus enemmistöltä muista laitteistasi. Tämä estää yksittäisen
varastetun laitteen itsenäisen avainten vaihtamisen.

---

## 12. Palautus

### Seed-lauseen käyttäminen

Jos menetät laitteesi tai otat käyttöön uuden:

1. Asenna Cleona uudelle laitteelle.
2. Valitse käynnistyksen yhteydessä "Palauta".
3. Syötä 24 sanaasi.
4. Cleona palauttaa identiteettisi ja ottaa automaattisesti yhteyttä aiempiin
   yhteyshenkilöihisi.
5. Yhteyshenkilösi vastaavat yhteystiedoillasi, ryhmäjäsenyyksillä ja
   viestihistorialla.

Palautus tapahtuu kolmessa vaiheessa:
- Ensin palaavat yhteyshenkilöt ja ryhmät.
- Sitten viimeiset 50 viestiä jokaisesta keskustelusta.
- Lopuksi täydellinen viestihistoria.

Riittää, että yksi ainoa yhteyshenkilöistäsi on verkossa, jotta palautus
onnistuu.

### Guardian Recovery (luottohenkilöt)

Voit nimetä jopa viisi luottohenkilöä "Guardianeiksi". Tällöin
palautusavaimesi jaetaan viiteen osaan, joista jokainen Guardian saa yhden.
Identiteettisi palauttamiseen riittää kolme viidestä osasta.

Tämä tarkoittaa: vaikka olisit menettänyt seed-lauseesi, kolme Guardianiasi
voivat yhdessä palauttaa tilisi. Yksikään Guardian ei voi yksin päästä
tietoihisi käsiksi -- aina tarvitaan vähintään kolme.

Näin määrität Guardianit:
1. Avaa asetukset.
2. Siirry kohtaan "Turvallisuus".
3. Valitse "Guardian Recovery".
4. Valitse viisi luotettavaa yhteyshenkilöä.

### Miksi yhteyshenkilöt ovat varmuuskopiosi

Perinteisissä viestisovelluksissa tietosi sijaitsevat palveluntarjoajan
palvelimilla. Cleonassa ei ole palvelinta -- mutta yhteyshenkilösi ottavat
tämän roolin. Kun lähetät viestin, yhteiset yhteyshenkilöt tallentavat
salatun kopion siltä varalta, että vastaanottaja on juuri silloin offline.
Palautuksen yhteydessä yhteyshenkilösi toimittavat tietosi takaisin.

Tämä tarkoittaa: mitä enemmän aktiivisia yhteyshenkilöitä sinulla on, sitä
luotettavampi varmuuskopiosi on. Yksi yhteyshenkilö, joka on säännöllisesti
verkossa, riittää onnistuneeseen palautukseen.

---

## 13. Asetukset

Asetuksiin pääset hammasrataskuvakkeesta oikeassa yläkulmassa.

### Ilmoitukset ja soittoäänet

- Valitse kuudesta eri soittoäänestä saapuville puheluille.
- Aseta viesti-ilmoitusääni.
- Android-laitteilla voit lisäksi ottaa värinän käyttöön tai poistaa
  sen käytöstä.

### Ulkoasut (Skins)

Cleona tarjoaa kymmenen eri ulkoasua: Teal, Ocean, Sunset, Forest,
Amethyst, Fire, Storm, Slate, Gold ja Contrast. Contrast-ulkoasu täyttää
korkeimman saavutettavuustason (WCAG AAA) ja on erityisen hyvin luettavissa
heikkonäköisille.

Jokaisella identiteetillä voi olla oma ulkoasunsa. Vaihdat ulkoasua
identiteetin tietosivulla (napauta aktiivista identiteettivälilehteä).

Lisäksi voit asetuksista kohdasta "Ulkoasu" vaihtaa vaalean, tumman ja
järjestelmäteeman välillä.

### Kielen vaihtaminen

Cleona on saatavilla 33 kielellä, mukaan lukien oikealta vasemmalle
kirjoitettavat kielet (esim. arabia, heprea). Vaihda kieli asetuksista
kohdasta "Kieli".

### Tallennusraja

Voit määrittää, kuinka paljon tallennustilaa Cleona saa käyttää laitteellasi
(100 MB - 2 GB). Kun raja saavutetaan, vanhemmat mediatiedostot arkistoidaan
tai poistetaan automaattisesti -- tekstiviestit säilyvät aina.

### Median arkistointi

Jos sinulla on kotona verkkolevyasema (NAS) tai jaettu kansio, Cleona voi
arkistoida mediasi automaattisesti sinne. Tuettuja ovat SMB, SFTP, FTPS ja
WebDAV.

Näin porrastettu tallennus toimii:
- Ensimmäiset 30 päivää: kaikki pysyy laitteellasi.
- 30 päivän jälkeen: esikatselukuva pysyy laitteella, alkuperäinen
  arkistoidaan.
- 90 päivän jälkeen: vain pieni esikatselukuva pysyy laitteella.
- Vuoden jälkeen: vain paikkamerkki jää, alkuperäinen on turvallisesti
  arkistossa.

Voit milloin tahansa napauttaa arkistoitua mediaa hakeaksesi sen takaisin --
edellyttäen, että olet yhteydessä kotiverkkoosi. Erityisen tärkeitä
mediatiedostoja voi kiinnittää, jotta niitä ei koskaan arkistoida.

### Ääniviestien transkriptio

Kun aktivoitu, ääniviestisi muunnetaan paikallisesti laitteellasi tekstiksi
(avoimen lähdekoodin Whisper-mallilla). Muunnettu teksti lähetetään
äänitteen mukana vastaanottajallesi. Transkriptio tapahtuu kokonaan
laitteellasi -- mitään tietoja ei lähetetä ulkoisille palveluille.

### Automaattinen lataus

Voit asettaa, minkä kokoiset mediatiedostot ladataan automaattisesti. Näin
voit esimerkiksi antaa kuvien latautua automaattisesti, mutta päättää
suurista videoista manuaalisesti.

### Linkitetyt laitteet

Hallitse linkitettyjä laitteitasi tässä asetusten osiossa. Katso
Multi-Device-luku lisätietoja varten.

---

## 14. Turvallisuus

### Mitä Post-Quantum-salaus tarkoittaa?

Nykyinen salaus perustuu matemaattisiin ongelmiin, joita tavallisten
tietokoneiden on äärimmäisen vaikea ratkaista. Kvanttitietokoneet voisivat
tulevaisuudessa ratkaista joitakin näistä ongelmista nopeasti.
Post-Quantum-salaus käyttää lisämenetelmiä, jotka kestävät myös
kvanttitietokoneet.

Cleona yhdistää molemmat lähestymistavat: klassisen salauksen
luotettavuuden vuoksi ja Post-Quantum-menetelmät tulevaisuudenkestävyyden
vuoksi. Näin olet suojattu sekä nykyisiä että tulevia uhkia vastaan.

Jokaiselle yksittäiselle viestille luodaan oma avain. Vaikka hyökkääjä
murtaisi yhden viestin avaimen, hän ei voisi lukea sillä mitään muuta
viestiä.

### Miksi palvelimettomuus on turvallisempaa

Perinteisissä viestisovelluksissa viestisi kulkevat palveluntarjoajan
palvelinten kautta. Vaikka ne olisivatkin siellä salattuja: palveluntarjoajalla
on pääsy metatietoihin (kuka kommunikoi kenen kanssa milloin, kuinka usein,
mistä) ja sen on mahdollisesti luovutettava ne tuomioistuimen määräyksestä.

Cleonassa ei ole tällaista keskitettyä pistettä. Viestisi kulkevat suoraan
laitteelta laitteelle. Ei ole paikkaa, johon kaikki metatiedot koottaisiin.
Kukaan ei voi yksittäisen tietopisteen perusteella rekonstruoida
viestintäkäyttäytymistäsi.

### Mitä tapahtuu kun olet offline?

Kun lähetät viestin ja vastaanottaja on offline:

1. Cleona yrittää ensin toimittaa viestin suoraan.
2. Jos se ei onnistu, viesti välitetään yhteisten yhteyshenkilöiden kautta.
3. Samalla viesti jaetaan salattuina paloina useille verkon solmuille
   (samaan tapaan kuin palapeli, joka koostuu 10 palasta, joista 7 riittää
   kuvan kokoamiseen).
4. Viesti säilytetään jopa 7 päivää.

Kun vastaanottaja tulee takaisin verkkoon, viestit toimitetaan. Saat
vahvistuksen, kun viestisi on saapunut perille.

### Sensuurin esto

Jos verkossasi estetään tavallinen yhteysmenetelmä (UDP), Cleona vaihtaa
automaattisesti vaihtoehtoiseen siirtotapaan (TLS), jota on vaikeampi
havaita ja estää. Tämä tapahtuu läpinäkyvästi -- sinun ei tarvitse
määrittää mitään.

### Turvallinen avainten säilytys

Tuetuilla alustoilla Cleona tallentaa salausavaimesi käyttöjärjestelmän
turvalliseen avainvarastoon (Android Keystore, iOS Keychain, macOS Keychain).
Saatavilla ollessaan tämä tarjoaa laitteistopohjaista suojaa avaimillesi.

### Tietokannan salaus

Kaikki viestisi, yhteyshenkilösi ja asetuksesi on salattuina laitteellasi.
Vaikka joku pääsisi käsiksi tiedostojärjestelmääsi, hän ei voisi lukea
mitään ilman kryptografista avaintasi. Tämä avain johdetaan identiteetistäsi
ja on olemassa vain laitteellasi.

### Suljettu verkko

Cleona toimii suljettuna verkkona. Jokainen verkkopaketti on todennettu,
joten vain aidot Cleona-laitteet voivat osallistua. Tämä estää ulkopuolisia
syöttämästä väärennettyjä viestejä tai salakuuntelemasta verkkoliikennettä.

---

## 15. Ohjelmistopäivitykset

### Miten saan päivityksiä?

Cleona voidaan päivittää eri tavoin. Tavoitteena on, että voit saada
päivityksiä myös silloin, kun yksittäiset jakelukanavat eivät ole
saatavilla tai ne on estetty:

1. **App Store / Play Store:** Jos olet asentanut Cleonan sovelluskaupasta,
   saat päivitykset tavalliseen tapaan kaupan kautta.
2. **GitHub Releases:** Projektin GitHub-sivulta löydät allekirjoitetut
   asennuspaketit kaikille alustoille.
3. **Verkon sisäiset päivitykset:** Jos toinen Cleona-käyttäjä verkossasi
   on jo päivittänyt uusimpaan versioon, Cleona voi hakea päivityksen
   suoraan P2P-verkon kautta -- ilman ulkoista palvelinta. Uusi versio
   jaetaan virheenkorjauspalasina useiden solmujen kautta. Laitteesi
   kerää tarpeeksi palasia ja kokoaa päivityksen. Aitous varmistetaan
   kehittäjän Ed25519-allekirjoituksella.
4. **Kutsulinkit:** Voit luoda kutsulinkkejä, jotka sisältävät kaiken
   mitä uusi käyttäjä tarvitsee Cleonan asentamiseen ja verkkoon
   liittymiseen.
5. **Fyysinen siirto:** Ilman internetiä olevissa ympäristöissä voit
   jakaa Cleonan USB-tikulta tai lähiverkon kautta muille.

### Päivitysilmoitus

Kun uusi päivitys on saatavilla, Cleona näyttää ilmoituksen
aloitusnäytöllä. Jos päivitys on saatavilla myös verkon kautta
(verkon sisäinen päivitys), voit valita sen lataamisen suoraan verkosta.

### Binäärien jakelu

Oletuksena laitteesi auttaa jakamaan päivityksiä muille verkon käyttäjille.
Jos et halua tätä, voit poistaa toiminnon käytöstä asetuksista kohdasta
"Verkko". Päivityspalojen tallennustila on rajattu (5 MB mobiililaitteilla,
20 MB työpöytälaitteilla) ja sitä siivotaan säännöllisesti.

### Allekirjoituksen tarkistus

Jokainen päivitys on kryptografisesti allekirjoitettu. Cleona tarkistaa
allekirjoituksen automaattisesti ennen päivityksen asentamista. Näin
varmistetaan, että vain virallisen kehittäjän päivitykset hyväksytään --
vaikka päivitys olisi haettu P2P-verkon kautta.

---

## 16. Usein kysytyt kysymykset

### "Voinko käyttää Cleonaa ilman internetiä?"

Et, Cleona tarvitsee verkkoyhteyden viestien lähettämiseen ja
vastaanottamiseen. Sinun ei kuitenkaan tarvitse olla samanaikaisesti verkossa
vastaanottajasi kanssa: viestit, jotka lähetetään vastaanottajan ollessa
offline, tallennetaan välimuistiin ja toimitetaan automaattisesti, kun
molemmat osapuolet ovat taas yhteydessä. Lähiverkossa (esim. samassa
WLAN-verkossa) voitte kommunikoida myös täysin ilman internet-yhteyttä.

### "Entä jos menetän seed-lauseeni?"

Jos olet määrittänyt Guardianit, kolme viidestä luottohenkilöstä voi yhdessä
palauttaa pääsysi. Ilman Guardianeita ja ilman seed-lausetta ei valitettavasti
ole tapaa saada identiteettiäsi takaisin. Siksi on niin tärkeää säilyttää 24
sanaa turvallisesti.

### "Voiko joku lukea viestejäni?"

Ei. Jokainen viesti salataan kertakäyttöisellä avaimella, joka on voimassa
vain tälle yhdelle viestille. Vain sinä ja vastaanottajasi voitte purkaa
viestin salauksen. Ei ole keskitettyä palvelinta, ei yleisavainta eikä
pääsyä kehittäjälle. Vaikka laite välittäisi viestin kuljetusreitillä, se
näkee vain salattua dataa.

### "Miksi en tarvitse puhelinnumeroa?"

Koska identiteettisi on puhtaasti kryptografinen. Puhelinnumeron tai
sähköpostiosoitteen sijaan, joka on yhdistetty oikeaan nimeesi, sinut
tunnistaa avainpari, joka luotiin laitteellasi. Yhteyshenkilöt lisäät
QR-koodin, NFC:n tai linkin kautta -- ei puhelinmuistion kautta. Tämä
tarkoittaa enemmän yksityisyyttä, koska viestintätilisi ei ole sidottu
todelliseen identiteettiisi.

### "Miten löydän ihmisiä Cleonasta?"

Cleonassa ei ole tarkoituksella yhteystietohakua puhelinnumeron tai nimen
perusteella -- se olisi yksityisyysongelma. Sen sijaan vaihdat yhteystietoja
suoraan: QR-koodilla, NFC:llä, cleona://-linkillä tai julkisissa kanavissa.
Se on kuin käyntikorttien vaihtamista puhelinluettelon selaamisen sijaan.

### "Toimiiko Cleona myös ulkomailla?"

Kyllä. Kunhan sinulla on internet-yhteys, Cleona toimii kaikkialla
maailmassa. Koska keskitettyä palvelinta ei ole, palvelua ei voi myöskään
estää tietyissä maissa. Cleonassa on lisäksi sensuurin eston varajärjestelmä:
jos normaali yhteys (UDP) estetään, Cleona vaihtaa automaattisesti
vaihtoehtoiseen siirtotapaan (TLS), jota on vaikeampi havaita ja estää.

### "Onko Cleona ilmainen?"

Kyllä. Cleona on ilmainen ja mainokseton. Koska keskitettyä palvelinta ei
ole, palvelinkustannuksiakaan ei synny. Sovelluksesta löydät kohdasta
"Lahjoitus" mahdollisuuden tukea kehitystä vapaaehtoisesti.

### "Viestissäni on kellokuvake -- mitä se tarkoittaa?"

Se tarkoittaa, että viestiä ei ole vielä toimitettu. Vastaanottajasi on
todennäköisesti juuri silloin offline. Kun viesti on toimitettu, kuvake
muuttuu. Viestejä säilytetään toimitusta varten jopa 7 päivää.

### "Voinko vaihtaa WhatsAppista Cleonaan?"

Kyllä, mutta et voi siirtää WhatsApp-keskustelujasi. Cleona ja WhatsApp ovat
täysin erilaisia järjestelmiä. Sinun täytyy lisätä yhteyshenkilösi yksitellen
Cleonaan. Helpoiten se onnistuu, kun lähetät cleona://-linkkisi WhatsApp-
ryhmään ja pyydät muita lisäämään sinut.

### "Voinko käyttää Cleonaa useilla laitteilla samanaikaisesti?"

Kyllä. Voit linkittää jopa 5 laitetta samaan identiteettiin. Yksi laite on
ensisijainen (se pitää seed-lauseen), ja lisälaitteet linkitetään turvallisen
paritusprosessin kautta. Kaikki laitteet jakavat saman identiteetin,
yhteyshenkilöt ja keskustelut. Katso Multi-Device-luku lisätietoja varten.

### "Miten saan päivityksiä, jos sovelluskauppa on estetty?"

Cleona voi hakea päivityksiä suoraan P2P-verkon kautta ilman
sovelluskauppaa, verkkosivustoa tai latauspalvelinta. Jos toinen
verkossa oleva käyttäjä on jo päivittänyt uusimpaan versioon, laitteesi
voi ladata päivityksen sieltä. Aitous varmistetaan kehittäjän
digitaalisella allekirjoituksella. Vaihtoehtoisesti yhteyshenkilö voi
lähettää sovelluksen kutsulinkin tai USB-tikun kautta. Lisätietoja
luvussa "Ohjelmistopäivitykset".

---

## Ohje ja yhteystiedot

Jos sinulla on kysymyksiä tai kohtaat ongelman, löydät ajankohtaista tietoa
Cleonan verkkosivuilta ja GitHubista. Koska Cleona on hajautettu projekti,
perinteistä asiakastukea ei ole -- mutta aktiivinen yhteisö auttaa mielellään.

---

*Tämä opas kuvaa Cleona Chat -versiota 3.1.125. Yksittäiset toiminnot
voivat muuttua tai laajentua uudemmissa versioissa.*

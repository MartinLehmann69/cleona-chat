# Cleona Chat -- Korisnički priručnik

Verzija 3.1.125 | stanje: srpanj 2026.

---

## Sadržaj

1. [Što je Cleona Chat?](#1-što-je-cleona-chat)
2. [Prvi koraci](#2-prvi-koraci)
3. [Kontakti](#3-kontakti)
4. [Poruke](#4-poruke)
5. [Grupe](#5-grupe)
6. [Javni kanali](#6-javni-kanali)
7. [Pozivi](#7-pozivi)
8. [Kalendar](#8-kalendar)
9. [Ankete](#9-ankete)
10. [Više identiteta](#10-više-identiteta)
11. [Multi-Device](#11-multi-device)
12. [Oporavak](#12-oporavak)
13. [Postavke](#13-postavke)
14. [Sigurnost](#14-sigurnost)
15. [Ažuriranja softvera](#15-ažuriranja-softvera)
16. [Česta pitanja](#16-česta-pitanja)

---

## 1. Što je Cleona Chat?

### Tvoj messenger, tvoji podaci

Cleona Chat je messenger koji radi potpuno bez središnjeg servera.
Tvoje poruke putuju izravno s tvog uređaja na uređaj tvog
sugovornika -- bez zaobilaska preko sjedišta neke tvrtke, bez oblaka, bez
podatkovnog centra. Nijedna tvrtka ne može čitati, pohranjivati ili
prosljeđivati tvoje poruke, jer jednostavno nijedna tvrtka nije uključena.

### Bez računa, bez broja telefona

Za Cleonu ti ne treba ni broj telefona ni adresa e-pošte da bi se
prijavio. Tvoj identitet čini kriptografski par ključeva koji se
automatski generira na tvom uređaju prilikom prvog pokretanja. To znači: nitko te ne može
pronaći preko tvog broja telefona ili adrese e-pošte, osim ako svoje kontakt
podatke sam ne podijeliš.

### Enkripcija otporna na budućnost

Cleona koristi takozvanu post-kvantnu enkripciju. To znači da čak ni
budući kvantni računala ne bi mogla razbiti tvoje poruke. Ne moraš
razumjeti detalje -- važno je samo da je tvoja komunikacija prema
trenutnom stanju tehnike zaštićena na najbolji mogući način.

### Kako to funkcionira bez servera?

Zamisli da ti i tvoji kontakti zajedno činite mrežu. Svaki uređaj
pomaže u prosljeđivanju poruka. Ako je tvoj sugovornik trenutno online,
poruka ide izravno njemu. Ako je tvoj sugovornik offline, zajednički
kontakti privremeno pohranjuju poruku i isporučuju je čim se
primatelj ponovno pojavi. Tvoji kontakti su, dakle, istovremeno i tvoja
mreža.

### Platforme

Cleona je dostupna za Android, iOS, macOS, Linux i Windows.

---

## 2. Prvi koraci

### Instalacija aplikacije

**Android:**
1. Preuzmi APK datoteku s Cleona web-stranice ili s GitHub Releases.
2. Otvori datoteku na svom mobitelu. Ako je potrebno, dopusti instalaciju
   iz nepoznatih izvora (Android će te automatski pitati).
3. Dodirni "Instaliraj" i pričekaj da instalacija bude dovršena.

**iOS:**
1. Otvori poveznicu za TestFlight pozivnicu na svom iPhoneu.
2. Dodirni "Instaliraj". TestFlight je Appleov službeni način
   distribucije beta aplikacija.
3. Nakon instalacije Cleonu ćeš pronaći na svom početnom zaslonu.

**macOS:**
1. Preuzmi DMG datoteku s Cleona web-stranice ili s GitHub Releases.
2. Otvori DMG i povuci Cleonu u svoju mapu Applications.
3. Prilikom prvog pokretanja macOS te može pitati želiš li otvoriti
   aplikaciju identificiranog developera -- potvrdi to.

**Linux (Ubuntu/Debian):**
1. Preuzmi .deb datoteku s Cleona web-stranice ili s GitHub Releases.
2. Instaliraj dvoklikom ili u terminalu: `sudo dpkg -i cleona-chat_VERSION_amd64.deb`
3. Pokreni Cleonu preko izbornika aplikacija ili u terminalu s `cleona-chat`.

**Linux (Fedora/openSUSE):**
1. Preuzmi .rpm datoteku s Cleona web-stranice ili s GitHub Releases.
2. Instaliraj s: `sudo dnf install cleona-chat-VERSION.x86_64.rpm`
3. Pokreni Cleonu preko izbornika aplikacija ili u terminalu s `cleona-chat`.

**Linux (sve distribucije -- AppImage):**
1. Preuzmi .AppImage datoteku s Cleona web-stranice ili s GitHub Releases.
2. Učini datoteku izvršnom: desni klik, Svojstva, Izvršno, ili u terminalu: `chmod +x cleona-chat-VERSION-x86_64.AppImage`
3. Pokreni dvoklikom ili u terminalu: `./cleona-chat-VERSION-x86_64.AppImage`

**Windows:**
1. Preuzmi instalacijsku datoteku s Cleona web-stranice ili s GitHub Releases.
2. Pokreni instalacijsku datoteku i slijedi upute.
3. Pokreni Cleonu preko izbornika Start ili prečaca na radnoj površini.

### Stvaranje identiteta

Prilikom prvog pokretanja Cleona automatski stvara novi identitet za tebe.
Možeš si dati prikazno ime -- to je ime koje vide tvoji kontakti.
To ime možeš promijeniti u bilo kojem trenutku.

### Zapiši Seed-Phrase -- najvažnija stvar od svega

Nakon stvaranja tvog identiteta Cleona ti prikazuje 24 riječi. To je
tvoja **Seed-Phrase** -- tvoj osobni ključ za oporavak.

**Zapiši ovih 24 riječi na papir i čuvaj ih na sigurnom mjestu.**

Zašto je to toliko važno?

- Ako ti se mobitel pokvari, izgubi ili ukrade, uz pomoć ovih 24 riječi
  možeš u potpunosti obnoviti svoj identitet na novom uređaju.
- Bez Seed-Phrase nema puta natrag. Ne postoji gumb "zaboravljena
  lozinka" i ne postoji podrška koja bi ti mogla vratiti tvoj račun --
  jer na serveru uopće ne postoji nikakav račun.
- Nikada ne dijeli Seed-Phrase s drugima. Tko poznaje te riječi, može se
  lažno predstavljati kao ti.

Seed-Phrase kasnije možeš pronaći i u postavkama pod
"Sigurnost", ako je želiš ponovno pročitati.

### Dodavanje prvog kontakta

Da bi mogao razgovarati s nekim, prvo moraš tu osobu dodati kao kontakt.
Za to postoji nekoliko načina -- svi su objašnjeni u
sljedećem odlomku.

---

## 3. Kontakti

### Skeniranje QR-koda (preporučeno)

Najjednostavniji način dodavanja kontakta:

1. Tvoj sugovornik otvara svoju stranicu s detaljima identiteta (dodirom na
   vlastito ime u gornjoj traci) i pokazuje ti svoj QR-kod.
2. Ti dodirneš gumb plus i odabereš "Skeniraj QR-kod".
3. Drži svoj mobitel ispred QR-koda svog sugovornika.
4. Zahtjev za kontakt šalje se automatski. Čim ga tvoj sugovornik
   prihvati, možete si međusobno pisati.

Kad se susretnete uživo, QR-kod je najsigurnija metoda jer
pritom točno znaš s kim razmjenjuješ kontakt.

### NFC (prislanjanje telefona)

Ako oba uređaja podržavaju NFC:

1. Oboje otvorite funkciju za dodavanje kontakta.
2. Prislonite mobitele leđima uz leđa.
3. Kontakt podaci automatski se razmjenjuju.

NFC, poput QR-koda, nudi visoku razinu sigurnosti jer
razmjena funkcionira samo ako fizički stojite jedno pored drugoga.

### Dijeljenje poveznice (cleona:// URI)

Svoju poveznicu za kontakt možeš poslati i putem e-pošte, SMS-a ili
nekog drugog messengera:

1. Otvori svoju stranicu s detaljima identiteta.
2. Kopiraj svoju cleona:// poveznicu.
3. Pošalji poveznicu osobi koja te treba dodati.
4. Druga osoba otvara poveznicu ili je umeće u
   dijalog za dodavanje kontakta.

Napomena: kod ove metode oslanjaš se na to da poveznica na putu
prijenosa nije izmijenjena. Za posebno osjetljive kontakte
preporučujemo QR-kod ili NFC.

### Prihvaćanje zahtjeva za kontakt

Kad ti netko pošalje zahtjev za kontakt, on se pojavljuje u tvom Inboxu (
zadnja kartica u donjoj traci). Ondje možeš:

- **Prihvatiti** -- osoba se dodaje u tvoje kontakte.
- **Odbiti** -- zahtjev se odbacuje.
- **Blokirati** -- osoba ti više ne može slati zahtjeve.

### Razine provjere

Cleona ti prikazuje koliko je sigurno potvrđen identitet nekog kontakta:

| Razina | Značenje |
|-------|-----------|
| Nepoznato | Dobio si samo Node-ID ili poveznicu. |
| Viđeno | Razmjena ključeva bila je uspješna, možete komunicirati šifrirano. |
| Provjereno | Susreli ste se uživo i potvrdili identitet putem QR-koda ili NFC-a. |
| Od povjerenja | Ovaj kontakt izričito si označio kao pouzdan. |

Što je razina viša, to možeš biti sigurniji da doista razgovaraš s
pravom osobom.

---

## 4. Poruke

### Slanje i primanje teksta

Jednostavno utipkaj svoju poruku u polje za unos na dnu i pritisni Enter ili
gumb za slanje. Tvoja poruka automatski se šifrira prije nego što
napusti tvoj uređaj.

Dolazne poruke pojavljuju se u povijesti razgovora. Kvačica ti pokazuje je li
tvoja poruka isporučena.

### Slanje slika, videozapisa i datoteka

Imaš nekoliko mogućnosti:

- **Ikona spajalice** u polju za unos: dodirni je da odabereš datoteku, sliku
  ili videozapis iz svoje galerije ili datotečnog sustava.
- **Povuci i ispusti** (Desktop): jednostavno povuci datoteku u prozor razgovora.
- **Zalijepi iz međuspremnika** (Desktop): kopiraj sliku i zalijepi
  je u razgovor.

Male datoteke (ispod 256 KB) šalju se izravno. Veće datoteke
prenose se u dvostupanjskom postupku: prvo se datoteka
najavljuje, a zatim prenosi u dijelovima.

### Glasovne poruke

1. Drži pritisnut gumb mikrofona u polju za unos.
2. Izgovori svoju poruku.
3. Otpusti gumb da bi poruku poslao.

Ako je na tvom uređaju aktivirano prepoznavanje govora (vidi postavke),
tvoja glasovna poruka automatski se transkribira u tekst. Tvoj sugovornik
tada vidi i snimku i transkribirani tekst.

### Odgovaranje na poruke (citiranje)

Da bi odgovorio na određenu poruku:

1. Otvori izbornik s tri točke pored poruke.
2. Odaberi "Odgovori".
3. Iznad polja za unos pojavljuje se traka s citiranom porukom.
4. Napiši svoj odgovor i pošalji ga.

Citirana poruka prikazuje se u tvom odgovoru, tako da je poveznica
jasno vidljiva.

### Uređivanje i brisanje poruka

- **Uređivanje:** izbornik s tri točke poruke, zatim "Uredi".
  Promijeni tekst i ponovno ga pošalji. Tvoj sugovornik vidi da je
  poruka uređena. Uređivanje je moguće u roku od 15 minuta nakon
  slanja.
- **Brisanje:** izbornik s tri točke poruke, zatim "Izbriši". Poruka
  se uklanja i kod tebe i kod tvog sugovornika. Svoje vlastite poruke
  možeš izbrisati u bilo kojem trenutku -- ne postoji vremensko ograničenje
  za brisanje.

### Emoji reakcije

Umjesto da napišeš odgovor, na poruku možeš reagirati
emojijem:

1. Otvori izbornik s tri točke ili dugo pritisni poruku.
2. Odaberi emoji iz brzog izbora ili otvori birač emojija za
   punu ponudu.
3. Tvoja reakcija pojavljuje se ispod poruke.

### Kopiranje teksta

Preko izbornika s tri točke neke poruke možeš kopirati tekst poruke u
međuspremnik.

### Pretraživanje poruka

Na vrhu prozora razgovora nalazi se funkcija pretraživanja. Unesi
pojam za pretraživanje, a Cleona ti prikazuje sve rezultate u trenutnom razgovoru. Pomoću
tipki sa strelicama možeš skakati između rezultata.

Na početnom zaslonu postoji i filtar za pretraživanje koji obuhvaća sve kartice,
pomoću kojeg možeš pretražiti sve razgovore prema određenom pojmu.

### Pregled poveznica

Kad pošalješ poveznicu, Cleona automatski generira pregled (naslov,
opis, sličicu). Taj pregled generira tvoj uređaj
i šalje ga zajedno s porukom -- tvoj sugovornik za to ne mora
uspostaviti vezu s povezanom web-stranicom.

Kad dodirneš primljenu poveznicu, pita te se želiš li je otvoriti u
normalnom pregledniku, u anonimnom načinu rada ili je uopće ne otvoriti.

---

## 5. Grupe

### Stvaranje grupe

1. Prijeđi na karticu "Grupe".
2. Dodirni gumb plus.
3. Daj grupi ime.
4. Odaberi kontakte koje želiš pozvati.
5. Dodirni "Stvori".

Pozvani kontakti dobivaju obavijest i mogu se pridružiti
grupi.

### Pozivanje članova

I nakon stvaranja grupe možeš pozvati dodatne kontakte:

1. Otvori informacije o grupi (izbornik s tri točke u pregledu grupa ili
   gornja traka u grupnom razgovoru).
2. Dodirni "Pozovi".
3. Odaberi kontakte koje želiš dodati.

### Uloge

Svaka grupa ima tri uloge:

- **Vlasnik (Owner):** ima punu kontrolu. Može dodavati i uklanjati
  članove, imenovati administratore i upravljati grupom. Vlasnik
  svoj status može prenijeti i na drugog člana.
- **Administrator:** može uklanjati članove i pomagati pri upravljanju.
- **Član:** može čitati i pisati poruke.

### Napuštanje grupe

1. Otvori izbornik s tri točke u pregledu grupa.
2. Odaberi "Napusti".
3. Potvrdi svoju odluku.

Kad napustiš grupu, tvoje dosadašnje poruke ostaju vidljive
ostalim članovima.

---

## 6. Javni kanali

### Što su kanali?

Kanali su javni diskusijski forumi unutar Cleona mreže.
Za razliku od grupa, ovdje svatko može čitati bez potrebe da bude pozvan.
Samo vlasnik i administratori mogu objavljivati sadržaj --
pretplatnici samo čitaju.

### Pronalaženje kanala i pridruživanje

1. Prijeđi na karticu "Kanali".
2. Otvori karticu "Pretraga".
3. Pretraži dostupne kanale prema imenu ili temi.
4. Dodirni kanal, a zatim "Pretplati se".

Kanali se mogu filtrirati prema jeziku. Neki kanali označeni su kao
"Nije za maloljetnike" -- oni su vidljivi samo ako si u svom profilu
potvrdio da imaš 18 ili više godina.

### Stvaranje vlastitog kanala

1. Prijeđi na karticu "Kanali".
2. Dodirni gumb plus.
3. Unesi ime kanala (mora biti jedinstveno u cijeloj mreži).
4. Odaberi jezik i treba li kanal biti javan ili privatan.
5. Opcionalno: dodaj opis i sliku.
6. Dodirni "Stvori".

Za javne kanale možeš odrediti hoće li sadržaj biti označen kao
"Nije za maloljetnike".

### Prijavljivanje sadržaja

Ako u javnom kanalu primijetiš neprimjeren sadržaj, možeš
ga prijaviti. Cleona koristi decentralizirani sustav moderacije: prijave
ocjenjuju nasumično odabrani članovi mreže (svojevrsna
"porota"). Ako se utvrdi prekršaj, kanal dobiva
upozorenje. Kod ponovljenih prekršaja kanal se degradira u indeksu pretrage ili
blokira.

### Sustavni kanali

Cleona raspolaže s dva ugrađena sustavna kanala:

- **Bug Log:** kad Cleona otkrije pogrešku, pita te želiš li poslati
  anonimizirano izvješće o pogrešci. Ta izvješća završavaju u
  kanalu Bug Log, gdje ih zajednica može pregledati. Pritom se ne
  prenose nikakvi osobni podaci -- samo tehnički opisi
  pogrešaka. Log izvješće možeš poslati i ručno
  (uz dijalog za pregled i izričitu suglasnost).
- **Feature Requests:** ovdje korisnici mogu podnositi želje za
  funkcionalnostima i glasovati za postojeće prijedloge. Prijedlozi se
  sortiraju prema broju glasova.

Oba sustavna kanala imaju ograničenje veličine od 25 MB i nadziru se
sustavom moderacije putem porote.

---

## 7. Pozivi

### Pokretanje glasovnog poziva

1. Otvori razgovor s kontaktom kojeg želiš nazvati.
2. Dodirni ikonu telefona u gornjoj traci.
3. Pričekaj da tvoj sugovornik prihvati poziv.

Tijekom razgovora vidiš vremensku traku koja prikazuje trajanje poziva, a
imaš i pristup isključivanju zvuka i zvučniku.

Za prekid poziva dodirni crveni gumb za prekid.

### Pokretanje videopoziva

1. Otvori razgovor s kontaktom.
2. Dodirni ikonu kamere u gornjoj traci.
3. Tvoja slika s kamere pojavljuje se u malom prozoru, a slika tvog
   sugovornika u velikom području.

Tijekom razgovora možeš prebacivati između prednje i stražnje kamere.

### Dolazni pozivi

Kad te netko nazove, pojavljuje se prozor s obavijesti s imenom
pozivatelja. Možeš:

- **Prihvatiti** -- razgovor počinje.
- **Odbiti** -- pozivatelj dobiva obavijest o tome.

Ako si već u razgovoru, novi poziv automatski se
odbija.

### Grupni pozivi

Možeš voditi i grupne pozive u kojima istovremeno sudjeluje više
osoba. Poziv se organizira preko inteligentnog stabla za
prosljeđivanje, tako da svaki sudionik ne mora biti izravno povezan sa
svakim drugim. Svi razgovori su potpuno šifrirani od kraja do kraja.

### Enkripcija poziva

Svi pozivi šifriraju se jednokratnim ključevima koji postoje samo
tijekom trajanja razgovora. Nakon prekida poziva ti se ključevi
odmah brišu. Nitko naknadno ne može dešifrirati prošli razgovor.

---

## 8. Kalendar

Cleona sadrži ugrađeni kalendar koji radi šifrirano i potpuno
decentralizirano -- bez usluge u oblaku.

### Prikazi

Kalendar nudi pet prikaza: dan, tjedan, mjesec, godina i
prikaz zadataka. Između njih prebacuješ se putem kartica na vrhu
zaslona kalendara.

### Stvaranje događaja

Dodirni vremenski termin ili upotrijebi gumb za dodavanje da bi stvorio novi
događaj. Možeš unijeti naslov, datum, vrijeme, mjesto i bilješke.
Događaji se pohranjuju šifrirano na tvom uređaju.

### Ponavljajući događaji

Događaji se mogu ponavljati dnevno, tjedno, mjesečno ili godišnje.
Uzorak možeš prilagoditi (npr. svaki drugi utorak,
svaki prvi dan u mjesecu) i odrediti datum završetka ili broj
ponavljanja.

### Pozivanje kontakata

Prilikom stvaranja ili uređivanja događaja možeš pozvati svoje Cleona
kontakte. Oni dobivaju šifriranu pozivnicu za kalendar i mogu
odgovoriti sa da, ne ili možda. Promjene na događaju
automatski se šalju svim pozvanima.

### Prikaz slobodno/zauzeto

Svoju dostupnost možeš dijeliti s kontaktima bez otkrivanja
detalja o događajima. Postoje tri razine privatnosti: puni detalji, samo
vremenski blokovi ili skriveno. Možeš postaviti zadanu vrijednost i
prepisati je za pojedini kontakt.

### Podsjetnici

Događaji mogu imati podsjetnike koji prije početka događaja
pokreću sistemsku obavijest. Podsjetnike po potrebi možeš
odgoditi.

### Vanjska sinkronizacija kalendara

Cleona se može sinkronizirati s vanjskim uslugama kalendara:

- **CalDAV** -- poveži se s bilo kojim CalDAV-kompatibilnim serverom (Nextcloud,
  Radicale itd.).
- **Google kalendar** -- sinkronizacija putem Google Calendar API-ja sa
  sigurnom OAuth2 autentifikacijom.
- **Lokalni CalDAV server** -- Cleona može pokrenuti lokalni CalDAV server na
  tvom uređaju, tako da se desktop aplikacije za kalendar (Thunderbird, Outlook,
  Apple Kalendar, Evolution) mogu sinkronizirati s tvojim Cleona
  kalendarom.
- **Android sistemski kalendar** -- događaji iz Cleone mogu se
  prenijeti u ugrađenu aplikaciju kalendara tvog Android uređaja.
- **ICS datoteke** -- uvezi i izvezi događaje u standardnom
  iCalendar formatu.

### PDF izvoz

Svaki prikaz kalendara (dan, tjedan, mjesec, godina) možeš
ispisati ili izvesti kao PDF dokument.

---

## 9. Ankete

U svakom razgovoru ili grupi možeš stvoriti ankete kako bi
prikupio mišljenja ili dogovorio termine.

### Vrste anketa

Cleona podržava pet vrsta anketa:

- **Jednostruki izbor** -- sudionici biraju jednu opciju.
- **Višestruki izbor** -- sudionici mogu odabrati više opcija.
- **Anketa o terminu** -- pronađi termin koji odgovara svima. Svaki
  sudionik označava termine kao dostupne, možda dostupne ili
  nedostupne.
- **Skala** -- ocijeni nešto na numeričkoj skali (npr. od 1 do 5).
- **Slobodan tekst** -- sudionici pišu vlastiti odgovor.

### Stvaranje ankete

Otvori razgovor i dodirni ikonu ankete (ili upotrijebi izbornik za
privitke). Odaberi vrstu ankete, formuliraj svoje pitanje i
opcije, te pošalji anketu. Pojavljuje se kao poruka u razgovoru.

### Glasovanje

Dodirni anketu da bi dao svoj glas. Svoj glas možeš u
bilo kojem trenutku promijeniti ili povući.

### Anonimno glasovanje

Ankete se mogu konfigurirati za anonimno glasovanje. Kad je ta opcija
aktivirana, glasovi su kriptografski anonimni -- nitko, čak ni
tvorac ankete, ne može vidjeti tko je za što glasovao. Broj glasova
ipak ostaje vidljiv.

### Iz ankete o terminu u kalendar

Kad je anketa o terminu završena, pobjednički termin jednim
dodirom može se izravno pretvoriti u unos u kalendaru.

---

## 10. Više identiteta

### Zašto više identiteta?

Zamisli da želiš odvojiti svoj poslovni i privatni život --
slično kao s dva različita broja telefona, ali bez drugog mobitela.
U Cleoni možeš na jednom uređaju koristiti više identiteta. Svaki
identitet ima vlastito ime, vlastitu profilnu sliku, vlastite kontakte i
vlastite razgovore.

### Stvaranje novog identiteta

1. U gornjoj traci vidiš svoj trenutni identitet kao karticu.
2. Dodirni znak plus (+) desno od svojih kartica identiteta.
3. Unesi ime za novi identitet.
4. Gotovo -- novi identitet odmah je aktivan.

### Prebacivanje između identiteta

Jednostavno dodirni karticu identiteta u gornjoj traci. Prebacivanje
je trenutno -- nema čekanja, nema ponovnog učitavanja.

### Svi rade istovremeno

Važna napomena: svi tvoji identiteti aktivni su istovremeno. Čak
i dok se prikazuješ kao "Poslovno", tvoj identitet "Privatno"
i dalje prima poruke. Ne propuštaš ništa, bez obzira koji identitet
trenutno imaš odabran.

### Stranica s detaljima identiteta

Kad dodirneš karticu svog trenutno aktivnog identiteta, otvara se
stranica s detaljima. Ovdje možeš:

- Prikazati svoj QR-kod za kontakte.
- Promijeniti ili ukloniti svoju profilnu sliku.
- Dodati opis profila.
- Promijeniti svoje prikazno ime.
- Odabrati izgled (skin) za taj identitet.
- Izbrisati identitet ako ti više nije potreban.

### Brisanje identiteta

Kad izbrišeš identitet, tvoji kontakti dobivaju obavijest o
tome. Identitet i svi pripadajući podaci uklanjaju se s tvog
uređaja. Taj se postupak ne može poništiti.

---

## 11. Multi-Device

### Korištenje Cleone na više uređaja

Isti identitet možeš istovremeno koristiti na do 5 uređaja. Jedan
uređaj je primarni (on čuva Seed-Phrase), a dodatni uređaji
povezuju se s njim.

### Povezivanje novog uređaja

1. Otvori postavke na svom primarnom uređaju.
2. Idi na "Povezani uređaji".
3. Odaberi "Poveži novi uređaj".
4. Instaliraj Cleonu na novom uređaju i pri pokretanju odaberi "Poveži
   s postojećim uređajem".
5. Skeniraj QR-kod za uparivanje koji se prikazuje na tvom primarnom uređaju,
   ili upotrijebi poveznicu za uparivanje.

Povezani uređaj dobiva delegacijski certifikat od primarnog uređaja.
Poruke poslane s povezanog uređaja kriptografski su
potpisane delegiranim ključem, tako da kontakti mogu
provjeriti da poruka doista dolazi od tvog identiteta.

### Kako to funkcionira

- Primarni uređaj čuva tvoju Seed-Phrase i glavne ključeve (master keys).
- Povezani uređaji dobivaju izvedene ključeve za potpisivanje i
  delegacijski certifikat -- Seed-Phrase nikada im se ne prosljeđuje.
- Svi uređaji dijele isti identitet i kontakte. Poruke stižu
  na sve uređaje.
- Delegacijski certifikati automatski se obnavljaju prije isteka.

### Upravljanje uređajima

Otvori postavke i idi na "Povezani uređaji" da bi vidio sve svoje
povezane uređaje, njihov status i posljednju aktivnost. Povezani
uređaj možeš u bilo kojem trenutku opozvati, ako se izgubi ili
bude ukraden.

### Hitna rotacija ključeva

Ako posumnjaš da je neki uređaj kompromitiran, možeš pokrenuti
hitnu rotaciju ključeva. Pritom se generiraju novi ključevi,
a rotaciju mora potvrditi većina tvojih ostalih uređaja.
To sprječava da jedan ukradeni uređaj samovoljno
rotira ključeve.

---

## 12. Oporavak

### Korištenje Seed-Phrase

Ako izgubiš svoj uređaj ili postavljaš novi:

1. Instaliraj Cleonu na novom uređaju.
2. Pri pokretanju odaberi "Oporavi".
3. Unesi svojih 24 riječi.
4. Cleona obnavlja tvoj identitet i automatski kontaktira tvoje
   dosadašnje kontakte.
5. Tvoji kontakti odgovaraju s tvojim kontakt podacima, članstvima u grupama
   i poviješću poruka.

Oporavak se odvija u tri koraka:
- Prvo se vraćaju tvoji kontakti i grupe.
- Zatim posljednjih 50 poruka iz svakog razgovora.
- Na kraju cjelokupna povijest poruka.

Dovoljno je da samo jedan od tvojih kontakata bude online da bi
oporavak funkcionirao.

### Guardian Recovery (osobe od povjerenja)

Možeš imenovati do pet osoba od povjerenja kao "Guardians". Pritom se
tvoj ključ za oporavak dijeli na pet dijelova, od kojih svaki
Guardian dobiva jedan. Za oporavak svog identiteta dovoljna su tri
od pet dijelova.

To znači: čak i ako izgubiš svoju Seed-Phrase, tri tvoja
Guardiana zajedno mogu obnoviti tvoj račun. Nijedan pojedinačni Guardian
ne može sam pristupiti tvojim podacima -- uvijek su potrebna barem tri.

Ovako postavljaš Guardiane:
1. Otvori postavke.
2. Idi na "Sigurnost".
3. Odaberi "Guardian Recovery".
4. Odaberi pet pouzdanih kontakata.

### Zašto su tvoji kontakti tvoja sigurnosna kopija

U uobičajenim messengerima tvoji se podaci nalaze na serverima davatelja usluge.
Kod Cleone nema servera -- ali tu ulogu preuzimaju tvoji kontakti.
Kad pošalješ poruku, zajednički kontakti pohranjuju šifriranu
kopiju za slučaj da je primatelj trenutno offline. Prilikom
oporavka tvoji kontakti vraćaju ti tvoje podatke.

To znači: što više aktivnih kontakata imaš, to je pouzdanija
tvoja sigurnosna kopija. Jedan kontakt koji je redovito online
dovoljan je za uspješan oporavak.

---

## 13. Postavke

Postavkama pristupaš preko ikone zupčanika u gornjem desnom
kutu.

### Obavijesti i tonovi zvona

- Odaberi jedan od šest različitih tonova zvona za dolazne pozive.
- Postavi ton za poruke.
- Na Android uređajima dodatno možeš uključiti ili
  isključiti vibraciju.

### Dizajni (skinovi)

Cleona nudi deset različitih dizajna: Teal, Ocean, Sunset, Forest,
Amethyst, Fire, Storm, Slate, Gold i Contrast. Dizajn Contrast ispunjava
najvišu razinu pristupačnosti (WCAG AAA) i posebno je dobro
čitljiv kod oštećenog vida.

Svaki identitet može imati svoj vlastiti dizajn. Dizajn mijenjaš na
stranici s detaljima identiteta (dodirom na aktivnu karticu identiteta).

Dodatno, u postavkama pod "Izgled" možeš prebacivati između
svijetle, tamne i sistemske teme.

### Promjena jezika

Cleona je dostupna na 33 jezika, uključujući i jezike s
pismom s desna na lijevo (npr. arapski, hebrejski). Jezik mijenjaš u
postavkama pod "Jezik".

### Ograničenje pohrane

Možeš odrediti koliko prostora za pohranu Cleona smije koristiti
na tvom uređaju (između 100 MB i 2 GB). Kad se ograničenje dosegne,
stariji mediji automatski se izmještaju ili brišu -- tekstualne poruke uvijek
ostaju sačuvane.

### Arhiviranje medija

Ako kod kuće imaš mrežnu pohranu (NAS) ili dijeljenu mapu,
Cleona može tvoje medije automatski izmjestiti onamo. Podržani su
SMB, SFTP, FTPS i WebDAV.

Ovako funkcionira stupnjevita pohrana:
- Prvih 30 dana: sve ostaje na tvom uređaju.
- Nakon 30 dana: sličica ostaje na uređaju, original se
  arhivira.
- Nakon 90 dana: na uređaju ostaje samo mala sličica.
- Nakon godinu dana: ostaje samo zamjenski prikaz (placeholder), original se sigurno
  čuva u arhivi.

Na arhivirani medij možeš u bilo kojem trenutku dodirnuti da bi ga vratio --
pod uvjetom da si povezan sa svojom kućnom mrežom. Posebno važne
medije možeš zakvačiti (pin) kako nikada ne bi bili izmješteni.

### Transkripcija glasovnih poruka

Kad je aktivirano, tvoje glasovne poruke lokalno se na tvom uređaju
pretvaraju u tekst (pomoću open-source modela Whisper). Transkribirani tekst
šalje se zajedno sa snimkom tvom sugovorniku. Transkripcija se
odvija potpuno na tvom uređaju -- nikakvi podaci ne odlaze prema vanjskim uslugama.

### Automatsko preuzimanje

Možeš postaviti od koje se veličine mediji automatski
preuzimaju. Tako, na primjer, možeš dopustiti automatsko učitavanje slika, ali
kod velikih videozapisa odlučivati ručno.

### Povezani uređaji

Svojim povezanim uređajima upravljaj u ovom dijelu postavki.
Pogledaj poglavlje Multi-Device za detalje.

---

## 14. Sigurnost

### Što znači post-kvantna enkripcija?

Današnja enkripcija temelji se na matematičkim problemima koji su za obične
računala izrazito teški za rješavanje. Kvantni računala mogla bi neke od tih
problema u budućnosti brzo riješiti. Post-kvantna enkripcija koristi
dodatne postupke koji odolijevaju i kvantnim računalima.

Cleona kombinira oba pristupa: klasičnu enkripciju za
pouzdanost i post-kvantne postupke za sigurnost u budućnosti. Tako si
istovremeno zaštićen i od današnjih i od budućih prijetnji.

Za svaku pojedinu poruku generira se zaseban ključ. Čak i kad bi
napadač uspio razbiti ključ jedne poruke, njime ne bi mogao
pročitati nijednu drugu poruku.

### Zašto je "bez servera" sigurnije

Kod uobičajenih messengera tvoje poruke prolaze preko servera
davatelja usluge. Iako mogu biti šifrirane, davatelj usluge ima
pristup metapodacima (tko s kim kada komunicira, koliko često, odakle) i
te podatke po sudskom nalogu ponekad mora predati.

Kod Cleone ne postoji takva središnja točka. Tvoje poruke putuju
izravno od uređaja do uređaja. Ne postoji mjesto na kojem bi se svi metapodaci
skupljali. Nitko na temelju jedne jedine točke podataka ne može
rekonstruirati tvoje komunikacijsko ponašanje.

### Što se događa kad si offline?

Ako pošalješ poruku, a primatelj je offline:

1. Cleona najprije pokušava poruku isporučiti izravno.
2. Ako to ne uspije, poruka se prosljeđuje preko zajedničkih kontakata.
3. Istovremeno se poruka raspoređuje kao šifrirani dijelovi na više
   čvorova u mreži (slično kao slagalica koja se sastoji od 10 dijelova,
   od kojih je 7 dovoljno da se slika sastavi).
4. Poruka se čuva do 7 dana.

Čim se primatelj ponovno spoji, poruke mu se isporučuju.
Ti dobivaš potvrdu kad je tvoja poruka stigla.

### Zaštita od cenzure

Ako tvoja mreža blokira standardnu metodu povezivanja (UDP), Cleona
automatski prelazi na alternativni prijenos (TLS), koji je teže
prepoznati i blokirati. To se događa transparentno -- ne moraš ništa
konfigurirati.

### Sigurna pohrana ključeva

Na podržanim platformama Cleona pohranjuje tvoje enkripcijske
ključeve u sigurnom sustavskom skladištu ključeva operacijskog sustava (Android Keystore,
iOS Keychain, macOS Keychain). Gdje je dostupno, to nudi hardversku
zaštitu za tvoje ključeve.

### Enkripcija baze podataka

Sve tvoje poruke, kontakti i postavke pohranjeni su na tvom uređaju
šifrirano. Čak i kad bi netko dobio pristup tvom datotečnom sustavu,
bez tvog kriptografskog ključa ne bi mogao ništa pročitati.
Taj se ključ izvodi iz tvog identiteta i postoji samo na
tvom uređaju.

### Zatvorena mreža

Cleona funkcionira kao zatvorena mreža. Svaki mrežni paket je
autentificiran, tako da samo legitimni Cleona uređaji mogu sudjelovati.
To sprječava da vanjske osobe ubace lažne poruke ili
prisluškuju mrežni promet.

---

## 15. Ažuriranja softvera

### Kako dobivam ažuriranja?

Cleona se može ažurirati na više načina. Cilj je da
ažuriranja možeš dobiti i onda kad pojedini distribucijski kanali otkažu
ili budu blokirani:

1. **App Store / Play Store:** ako si Cleonu instalirao preko nekog
   App Storea, ažuriranja dobivaš kao i obično preko trgovine.
2. **GitHub Releases:** na GitHub stranici projekta pronaći ćeš
   potpisane instalacijske pakete za sve platforme.
3. **In-Network ažuriranja:** ako neki drugi Cleona korisnik u tvojoj mreži
   već ima najnoviju verziju, Cleona može dobiti ažuriranje izravno preko
   P2P mreže -- bez vanjskog servera. Pritom se nova
   verzija razlaže na fragmente s korekcijom pogrešaka i raspoređuje preko
   više čvorova. Tvoj uređaj skuplja dovoljno fragmenata i sastavlja
   ažuriranje. Autentičnost se provjerava Ed25519 potpisom
   developera.
4. **Pozivnice:** možeš stvarati pozivnice koje sadrže sve
   što je novom korisniku potrebno za instalaciju Cleone i
   povezivanje s mrežom.
5. **Fizički prijenos:** u okruženjima bez interneta Cleonu možeš
   proslijediti drugima putem USB stika ili lokalne mreže.

### Obavijest o ažuriranju

Kad je dostupno novo ažuriranje, Cleona ti prikazuje obavijest
na početnom zaslonu. Ako je ažuriranje dostupno i preko mreže
(In-Network ažuriranje), možeš odabrati da ga preuzmeš izravno iz
mreže.

### Distribucija binarnih datoteka

Prema zadanim postavkama tvoj uređaj pomaže u prosljeđivanju ažuriranja drugim
korisnicima u mreži. Ako to ne želiš, tu funkciju možeš
isključiti u postavkama pod "Mreža". Korištenje pohrane
za fragmente ažuriranja je ograničeno (5 MB na mobilnim uređajima,
20 MB na desktop uređajima) i redovito se čisti.

### Provjera potpisa

Svako ažuriranje kriptografski je potpisano. Cleona automatski
provjerava potpis prije nego što se ažuriranje instalira. Time se
osigurava da se prihvaćaju samo ažuriranja od službenog developera --
čak i ako je ažuriranje preuzeto preko P2P mreže.

---

## 16. Česta pitanja

### "Mogu li koristiti Cleonu bez interneta?"

Ne, Cleoni je potrebna mrežna veza za slanje i primanje
poruka. Međutim, ne morate ti i tvoj sugovornik biti online
istovremeno: poruke poslane dok je primatelj offline
privremeno se pohranjuju i automatski isporučuju čim su obje strane
ponovno povezane. U lokalnoj mreži (npr. u istom WLAN-u) možete
komunicirati i potpuno bez pristupa internetu.

### "Što ako izgubim svoju Seed-Phrase?"

Ako si postavio Guardiane, tri od pet osoba od povjerenja
zajedno mogu obnoviti tvoj pristup. Bez Guardiana i bez
Seed-Phrase, nažalost, ne postoji način da povratiš svoj
identitet. Zato je toliko važno tih 24 riječi sigurno
čuvati.

### "Može li netko čitati moje poruke?"

Ne. Svaka poruka šifrira se jednokratnim ključem koji
vrijedi samo za tu jednu poruku. Samo ti i tvoj sugovornik možete
poruku dešifrirati. Ne postoji središnji server, ne postoji glavni ključ
i ne postoji pristup za developera. Čak i kad neki uređaj na
putu prijenosa proslijedi poruku, on vidi samo šifrirani skup podataka.

### "Zašto mi ne treba broj telefona?"

Zato što je tvoj identitet čisto kriptografski. Umjesto broja telefona ili
adrese e-pošte povezane s tvojim pravim imenom, identificira te
par ključeva generiran na tvom uređaju. Kontakte dodaješ
putem QR-koda, NFC-a ili poveznice -- ne preko imenika. To znači
više privatnosti, jer tvoj messenger račun nije vezan uz tvoj
stvarni identitet.

### "Kako pronalazim ljude na Cleoni?"

Cleona namjerno nema pretragu kontakata prema broju telefona ili imenu -- to bi
predstavljalo problem za privatnost. Umjesto toga, kontakt podatke razmjenjuješ izravno: putem
QR-koda, NFC-a, cleona:// poveznice ili u javnim kanalima. To je poput
razmjene posjetnica umjesto traženja u imeniku.

### "Radi li Cleona i u inozemstvu?"

Da. Dokle god imaš internetsku vezu, Cleona funkcionira posvuda u
svijetu. Budući da ne postoji središnji server, uslugu nije moguće
blokirati ni za pojedine zemlje. Cleona dodatno raspolaže
zaštitom od cenzure: ako se normalna veza (UDP) blokira,
Cleona automatski prelazi na alternativni prijenos (TLS), koji je
teže prepoznati i blokirati.

### "Je li Cleona besplatna?"

Da. Cleona se može koristiti besplatno i bez oglasa. Budući da ne postoji
središnji server, ne nastaju ni troškovi servera za rad. U aplikaciji
pod "Donacija" pronaći ćeš mogućnost da dobrovoljno
podržiš razvoj.

### "Moja poruka ima simbol sata -- što to znači?"

To znači da poruka još nije isporučena. Tvoj sugovornik
vjerojatno je trenutno offline. Čim poruka bude isporučena,
simbol se mijenja. Poruke se čuvaju do 7 dana radi
isporuke.

### "Mogu li prijeći s WhatsAppa na Cleonu?"

Da, ali svoje WhatsApp razgovore ne možeš prenijeti. Cleona i WhatsApp
su potpuno različiti sustavi. Svoje kontakte moraš u Cleonu
dodati pojedinačno. Najlakše je to učiniti tako da svoju cleona://
poveznicu objaviš u WhatsApp grupi i zamoliš ostale da te ondje dodaju.

### "Mogu li Cleonu koristiti istovremeno na više uređaja?"

Da. Do 5 uređaja možeš povezati s istim identitetom. Jedan uređaj
je primarni (on čuva Seed-Phrase), a dodatni uređaji povezuju se
putem sigurnog postupka uparivanja. Svi uređaji dijele isti
identitet, kontakte i razgovore. Pogledaj poglavlje Multi-Device za
detalje.

### "Kako dobivam ažuriranja ako je App Store blokiran?"

Cleona može dobivati ažuriranja izravno preko P2P mreže, bez oslanjanja na
App Store, web-stranicu ili server za preuzimanje. Ako
neki drugi korisnik u mreži ima najnoviju verziju, tvoj uređaj može
ažuriranje preuzeti odande. Autentičnost se provjerava digitalnim
potpisom developera. Alternativno, neki ti kontakt aplikaciju može
proslijediti putem pozivnice ili USB stika. Više o tome u poglavlju
"Ažuriranja softvera".

---

## Pomoć i kontakt

Ako imaš pitanja ili naiđeš na problem, aktualne informacije
pronaći ćeš na Cleona web-stranici i na GitHubu. Budući da je Cleona
decentraliziran projekt, ne postoji klasična korisnička podrška -- ali
postoji aktivna zajednica koja rado pomaže.

---

*Ovaj priručnik opisuje Cleona Chat verziju 3.1.125. Pojedine funkcije
mogu se u novijim verzijama promijeniti ili proširiti.*

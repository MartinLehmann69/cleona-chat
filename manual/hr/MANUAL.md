# Cleona Chat -- Korisnički priručnik

Verzija 4.2 | Stanje studeni 2026

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
11. [Više uređaja](#11-više-uređaja)
12. [Obnova](#12-obnova)
13. [Postavke](#13-postavke)
14. [Sigurnost](#14-sigurnost)
15. [Ažuriranja softvera](#15-ažuriranja-softvera)
16. [Česta pitanja](#16-česta-pitanja)

---
## 1. Što je Cleona Chat?

### Tvoj messenger, tvoji podaci

Cleona Chat je messenger koji u potpunosti radi bez središnjeg poslužitelja.
Tvoje poruke putuju s tvog uređaja na uređaj sugovornika -- bez zaobilaska
preko sjedišta tvrtke, bez oblaka, bez podatkovnog centra. Gdje bi putem
pomogao neki drugi uređaj, on samo prosljeđuje šifrirane pakete. Nijedna
tvrtka ne može čitati tvoje poruke, pohranjivati ih ili proslijeđivati,
jer naprosto nijedna tvrtka ne stoji između.

### Nema računa, nema telefonskog broja

Za Cleonu ne trebaš ni telefonski broj ni adresu e-pošte da bi se prijavio.
Tvoj identitet sastoji se od kriptografskog para ključeva koji se pri
prvom pokretanju automatski stvara na tvom uređaju. To znači: nitko te
ne može pronaći preko tvog telefonskog broja ili adrese e-pošte, osim
ako sam ne proslijediš svoje kontaktne podatke.

### Šifririranje otporno na budućnost

Cleona koristi takozvano post-kvantno šifriranje. To znači: ni budući
kvantni računali ne bi mogla razbiti tvoje poruke. Ne moraš razumjeti
detalje -- važno je samo da je tvoja komunikacija prema trenutnom
stanju tehnike na najbolji mogući način zaštićena.

### Kako to radi bez poslužitelja?

Mreža Cleone sastoji se samo od uređaja njezinih korisnika. Svaki uređaj
je čvor, nijedan čvor nije važniji od drugog, i svaki poznaje samo svoje
susjede. Četiri stvari ovu mrežu čine posebnom:

- **Nema čvrste točke.** U aplikaciji ne stoji adresa poslužitelja, i mreža
  ne ovisi ni o jednom jedinom čvoru. Nema ničega što bi se moglo isključiti
  da bi se Cleona isključila.
- **Odmah.** Tvoja poruka kreće u istom trenutku u kojem je pošalješ. Ne čeka
  ni na takt ni na išta drugo.
- **Prikrivanje usput.** Tvoj uređaj stalno šalje male prikrivne pakete,
  da izvana nije vidljivo kada stvarno pišeš. Nijedna poruka ne ovisi o tome
  -- prikrivanje tek teče usput.
- **Kodovi umjesto imena.** Tko proslijedi poruku, vidi samo kod koji se
  svakog dana mijenja. U pravilu nitko od njih istovremeno ne poznaje
  pošiljatelja i primatelja; iznimke stoje u poglavlju 14.

**Tri puta, istovremeno.** Kada pošalješ poruku, Cleona ne isprobava jedan
put za drugim, nego sve odgovarajuće odjednom. Čim sugovornik potvrdi
primitak, ostali se prekidaju.

1. **U istoj mreži:** Ako ste u istoj mreži WLAN, poruka prelazi izravno.
2. **Preko čvrstih susjeda:** Na internetu tvoj uređaj predaje poruku svom
   čvrstom susjedu. On je prosljeđuje čvrstim susjedima tvog sugovornika
   (do tri istovremeno), i jedan od njih je isporučuje.
3. **Poštanski sandučić:** Ako je sugovornik offline, Cleona ostavlja poruku
   šifrirano kod tri susjeda. Tamo ostaje do 7 dana. Kad se sugovornik
   vrati online, on je preuzima.

**Kako ući u mrežu?** U aplikaciji ne stoji adresa poslužitelja. Svoj ulaz
dobivaš od svog prvog kontakta: Njegov poziv sadrži adrese preko kojih
tvoj uređaj pronalazi svoje prve susjede. U istom WLAN-u Cleona-uređaji se
nalaze i sami. Od tada tvoj uređaj s każdym susjedom upoznaje nove.

### Platforme

Cleona je dostupna za Android, iOS, macOS, Linux i Windows. Na računalima i na
Androidu poruke i pozivi stižu u nekoliko sekundi. Na iPhoneu to vrijedi dok je
aplikacija otvorena. Kad nije, iOS je budi samo povremeno i kratko; kada,
odlučuje iOS. Cleona tada preuzima sve što je za tebe bilo pohranjeno i
pokazuje obavijest s brojem na ikoni aplikacije. Pozivi ne stižu na iPhone sa
zatvorenom aplikacijom. To je Appleovo pravilo, a ne greška u Cleoni.

---

## 2. Prvi koraci

### Instalacija aplikacije

**Android:**
1. Preuzmi APK-datoteku s web-mjesta Cleone ili s GitHub Releases.
2. Otvori datoteku na svom mobitelu. Ako je potrebno, dopusti instalaciju
   iz nepoznatih izvora (Android te automatski pita).
3. Dodirni "Instaliraj" i pričekaj dok instalacija ne završi.

**iOS:**
1. Otvori pozivnicu za TestFlight na svom iPhoneu.
2. Dodirni "Instaliraj". TestFlight je Appleov službeni način distribucije
   beta-aplikacija.
3. Nakon instalacije naći ćeš Cleonu na svom početnom zaslonu.

**macOS:**
1. Preuzmi DMG-datoteku s web-mjesta Cleone ili s GitHub Releases.
2. Otvori DMG i povuci Cleonu u svoju mapu Programa.
3. Pri prvom pokretanju macOS te možda upita želiš li otvoriti aplikaciju
   identificiranog razvojnog programera -- potvrdi to.

**Linux (Ubuntu/Debian):**
1. Preuzmi .deb-datoteku s web-mjesta Cleone ili s GitHub Releases.
2. Instaliraj dvostrukim klikom ili u terminalu: `sudo dpkg -i cleona-chat-beta_VERSION_amd64.deb`
3. Pokreni Cleonu preko izbornika aplikacija ili u terminalu s `cleona-chat-beta`.

**Linux (Fedora/openSUSE):**
1. Preuzmi .rpm-datoteku s web-mjesta Cleone ili s GitHub Releases.
2. Instaliraj s: `sudo dnf install cleona-chat-beta-VERSION-1.x86_64.rpm`
3. Pokreni Cleonu preko izbornika aplikacija ili u terminalu s `cleona-chat-beta`.

**Linux (sve distribucije -- AppImage):**
1. Preuzmi .AppImage-datoteku s web-mjesta Cleone ili s GitHub Releases.
2. Učini datoteku izvršnom: desni klik, svojstva, izvršna, ili u terminalu: `chmod +x cleona-chat-beta-VERSION-x86_64.AppImage`
3. Pokreni dvostrukim klikom ili u terminalu: `./cleona-chat-beta-VERSION-x86_64.AppImage`

Imena paketa vrijede za beta, koja je trenutno jedina objavljena inačica;
zovu se `cleona-chat-beta`.

**Windows:**
1. Preuzmi instalacijski program s web-mjesta Cleone ili s GitHub Releases.
2. Pokreni instalacijsku datoteku i slijedi upute.
3. Pokreni Cleonu preko izbornika Start ili prečaca na radnoj površini.

### Stvaranje identiteta

Pri prvom pokretanju Cleona automatski stvara novi identitet za tebe.
Možeš si zadati ime za prikaz -- to je ime koje vide tvoji kontakti. To se
ime može u svakom trenutku promijeniti.

### Zapiši seed-izraz -- najvažnije uopće

Nakon stvaranja tvog identiteta Cleona ti prikazuje 24 riječi. To je tvoj
**seed-izraz** -- tvoj osobni ključ za obnovu.

**Zapiši ovih 24 riječi na papir i čuvaj ih na sigurnom.**

Zašto je to tako važno?

- Ako ti mobitel pokvari, izgubi se ili bude ukraden, s ovih 24 riječi
  možeš obnoviti cijeli svoj identitet na novom uređaju.
- Bez seed-izraza nema povratka. Nema gumba "zaboravljena lozinka" i nema
  podrške koja bi ti mogla vratiti tvoj račun -- jer na poslužitelju uopće
  nema računa. Ni tvoji kontakti ne mogu obnoviti tvoj identitet, bez obzira
  koliko ih je. Drugi uređaj s istim identitetom stiže u kasnijoj verziji
  (vidi poglavlje 11).
- Nemoj seed-izraz nikada proslijeđivati drugima. Tko pozna ove riječi,
  može se izdavati za tebe.

Tvojih 24 riječi kasnije nađeš i u postavkama pod "Sigurnosna kopija" ->
"Prikaži frazu za oporavak", ako ih želiš još jednom pročitati. Na Androidu
pritom potvrđuješ svojim zaključavanjem zaslona.

### Dodavanje prvog kontakta

Da bi s nekim vodio razgovor, moraš tu osobu najprije dodati kao kontakt.
Za to postoji više načina -- svi su objašnjeni u sljedećem odlomku.

---

## 3. Kontakti

### Tvoj poziv

Kontakti nastaju u Cleoni samo preko poziva. Tvoj poziv tu je od prvog
pokretanja -- i bez interneta i prije nego što je tvoj uređaj uopće
pronašao susjeda. Nalazi se na stranici s detaljima identiteta (dodirni
vlastito ime u gornjoj traci).

Poziv postoji u dva oblika koji sadrže potpuno isto:

- kao **QR-kod**, kada ti sugovornik stoji uz tebe, i
- kao **tekstualni redak** koji šalješ e-poštom, SMS-om ili preko drugog
  messengera.

Poziv ne sadrži telefonski broj i nema ime iz imenika. Sadrži tvoje javne
ključeve i adrese preko kojih sugovornik doseže tebe i tvoje susjede. Za
nekoga tko je tek instalirao Cleonu, tvoj je poziv zato i ulaz u mrežu.

### Skeniranje QR-koda (preporučeno)

Ako se osobno sretnete:

1. Ti sugovorniku pokažeš QR-kod svog poziva.
2. Sugovornik dodirne gumb plus, odabere "Skeniraj QR-kod" i
   usmjeri kameru na tvoj zaslon. To radi i s web-kamerom računala.
3. Zahtjev ide k tebi i **automatski se prihvaća** -- jer si sam upravo
   pokazao kod.

QR-kod vrijedi samo jednom: Prvi valjani zahtjev se prihvaća, nakon toga
je poziv potrošen. QR-kod je najsigurnija metoda, jer pritom točno znate
s kime razmjenjujete kontakt.

### NFC (pristupanje mobitela jedan uz drugi)

Ako oba uređaja podržavaju NFC:

1. Oboje otvorite funkciju dodavanja kontakta.
2. Prislonite svoje mobitele leđima jedan o drugi.
3. Poziv se prenosi i automatski prihvaća.

NFC nudi kao i QR-kod visoku sigurnost, jer razmjena radi samo kada
fizički stojite jedan uz drugog.

### Slanje tekstualnog retka

Ako se ne možete sresti:

1. Otvori svoj poziv i kopiraj tekstualni redak.
2. Pošalji ga osobi koja te treba dodati -- e-poštom, SMS-om ili
   preko drugog messengera.
3. Ta osoba umetne redak u Cleonu u dijalogu za dodavanje kontakta.
4. Zahtjev se kod tebe pojavi pod **"Zahtjevi"**. Ovdje se **ne** prihvaća
   automatski: Ti odlučuješ sam, jer ne možeš znati tko je usput još
   pročitao redak.

### Prihvaćanje zahtjeva za kontakt

Dolazeći zahtjev još ne stvara kontakt. On ti postavlja pitanje i pojavljuje
se u kartici **"Zahtjevi"**. Tamo vidiš ime i razinu provjere i možeš
odabrati:

- **Prihvati** -- tek sada osoba postaje tvoj kontakt.
- **Odbij** -- zahtjev se odbacuje.
- **Blokiraj** -- osoba ti ne može slati daljnje zahtjeve.

### Nikada ne koristiti kao čvrstog susjeda

U izborniku kontakta nađeš prekidač **"Nikada ne koristiti kao čvrstog
susjeda"** (zadano: isključeno). Ako je uključen, ovaj kontakt ne prosljeđuje
poruke za tebe i zato ne doznaje ni kada šalješ ili primaš poruke. To je
predviđeno za slučaj da ti prijeti opasnost iz vlastite okoline.

Od nepoznatih (ni od kontakata ni od članova zajedničke grupe) Cleona ne
propušta ništa osim takvog zahtjeva -- nijednu poruku, nijedan poziv,
nijednu datoteku. A i sam zahtjev dolazi samo ako
je pošiljatelj prethodno riješio mali računski zadatak. To masovni spam
čini skupim.

### Razine provjere

Cleona ti pokazuje koliko je sigurno potvrđen identitet kontakta:

| Razina | Značenje |
|-------|-----------|
| Neprovjereno | Povezani ste, ali ništa ne potvrđuje da zaista stoji prava osoba. |
| Viđeno | Razmjena ključeva je uspjela, možete šifrirano komunicirati. |
| Provjereno | Osobno ste se sreli i povezali se skeniranjem kamere ili NFC-om. |
| Pouzdano | Ovaj kontakt si izričito označio kao pouzdanog. |

"Provjereno" postoji samo za osobnu razmjenu. Poziv koji je došao preko
chata ili e-pošte nikada ne doseže tu razinu -- iako sadrži iste podatke.

Ako se ključevi kontakta promijene bez najave, Cleona ga vraća na
"Neprovjereno". To te štiti da se netko neprimijećeno ne izdaje za tvoj
kontakt.

---
## 4. Poruke

### Slanje i primanje teksta

Jednostavno upiši svoju poruku u polje za unos dolje i pritisni Enter ili
gumb za slanje. Tvoja poruka se automatski šifrira prije nego napusti tvoj
uređaj.

Dolazeće poruke pojavljuju se u povijesti razgovora.

### Što znače znakovi uz tvoju poruku

| Znak | Značenje |
|---------|-----------|
| Sat | Poruka je stvorena, ali ju još nijedan put nije nosio. |
| Jedna kvačica | Poruka je na putu. To vrijedi i dok u poštanskom sandučiću čeka na sugovornika. |
| Dvije kvačice | Isporučeno: Uređaj tvog sugovornika je potvrdio primitak. |
| Znak upozorenja | 14 dana nijedan put nije nosio poruku. Dodirni ga da bi je ponovno poslao. |

**Offline nije greška.** Ako sugovornik nije dostupan, poruka ostaje na
jednoj kvačici dok se ne preuzme -- nije izgubljena. Nema li tvoj uređaj
sam vezu, poruka ostaje na satu i kreće sama čim se opet pojavi put. Znak
upozorenja pojavljuje se tek kada 14 dana nije pronašla nijedan put; tada
je možeš ponovno poslati.

To vrijedi i za iPhone sa zatvorenom aplikacijom: poruka čeka u poštanskom
sandučiću dok iOS ne probudi aplikaciju na trenutak ili dok je tvoj sugovornik
ne otvori. To može trajati dulje nego na drugim uređajima.

Dvije kvačice postoje samo kada primatelj sam potvrdi primitak. Ta potvrda
je šifrirana i potpisana -- nitko usput je ne može krivotvoriti da bi ti
prevario isporuku.

### Slanje slika, video-snimaka i datoteka

Imaš više mogućnosti:

- **Ikona spajalice** u polju za unos: Dodirni je da bi odabrao datoteku, sliku
  ili video-snimku iz svoje galerije ili svog datotečnog sustava.
- **Povuci i ispusti** (računalo): Jednostavno povuci datoteku u prozor chata.
- **Umetni iz međuspremnika** (računalo): Kopiraj sliku i umetni je u chatu.

Male datoteke (ispod 256 KB) putuju izravno u poruci. Veće datoteke se
razlažu u komade i opskrbljuju korekcijom pogrešaka, tako da pojedini
izgubljeni komadi ne smetaju. Ako ste oboje online, struje preko susjeda;
inače se polažu kod uređaja koji su stalno dostupni, dok ih sugovornik
ne preuzme.

Od 256 KB nadalje Cleona te pita za svaku datoteku prije nego što se pošalje:
Velika datoteka ne može ići putem tvojih poruka. Njezin sadržaj ostaje
šifriran, i tvoj sugovornik ne doznaje tvoju internet adresu. Ali je prijenos
izvana vidljiv kao događaj, i tuđi uređaj koji ga prosljeđuje ili čuva vidi
tko prenosi i tko preuzima. Tvoj pristanak vrijedi samo za tu jednu datoteku.

### Glasovne poruke

1. Drži pritisnut gumb mikrofona u polju za unos.
2. Izgovori svoju poruku.
3. Pusti gumb da bi poslao poruku.

Ako je na tvom uređaju aktivirano prepoznavanje govora (vidi postavke),
tvoja glasovna poruka se automatski transkribira kao tekst. Tvoj sugovornik
tada vidi i snimku i transkribirani tekst.

### Odgovaranje na poruke (citiranje)

Da bi odgovorio na određenu poruku:

1. Otvori izbornik s tri točkice pokraj poruke.
2. Odaberi "Odgovori".
3. Iznad polja za unos pojavljuje se natpis s citiranom porukom.
4. Napiši svoj odgovor i pošalji ga.

Citirana poruka prikazuje se u tvom odgovoru, tako da je veza jasna.

### Uređivanje i brisanje poruka

- **Uredi:** Izbornik s tri točkice poruke, zatim "Uredi". Promijeni tekst
  i pošalji ga ponovno. Tvoj sugovornik vidi da je poruka uređivana. Uređivanje
  je moguće unutar 15 minuta nakon slanja.
- **Izbriši:** Izbornik s tri točkice poruke, zatim "Izbriši". Poruka se
  uklanja kod tebe i tvog sugovornika. Svoje vlastite poruke možeš izbrisati
  u svakom trenutku -- nema vremenskog okvira za brisanje.

### Emoji-reakcije

Umjesto da napišeš odgovor, na poruku možeš reagirati emoji-em:

1. Otvori izbornik s tri točkice ili dugo pritisni poruku.
2. Odaberi emoji iz brzog odabira ili otvori emoji-birač za puni izbor.
3. Tvoja reakcija pojavljuje se ispod poruke.

### Kopiranje teksta

Preko izbornika s tri točkice poruke možeš kopirati tekst poruke u
međuspremnik.

### Pretraživanje poruka

Na gornjem rubu prozora chata nalazi se funkcija pretraživanja. Upiši
pojam za pretraživanje, i Cleona ti pokazuje sve pogodke u trenutnom chatu.
Tipkama sa strelicama možeš skakati naprijed-natrag između pogodaka.

Na početnoj stranici postoji dodatno pretraživački filter koji obuhvaća
sve kartice, s kojim možeš pretraživati sve razgovore po pojmu.

### Pretpregled poveznice

Kada pošalješ poveznicu, Cleona automatski stvara pretpregled (naslov,
opis, sličica). Taj pretpregled stvara tvoj uređaj i šalje se zajedno --
tvoj sugovornik ne mora radi toga graditi vezu s povezanim web-mjestom.

Što radi dodir na primljenu poveznicu, postavljaš u postavkama pod
"Otvaranje veza": "Normalno", "Po mogućnosti privatni prozor" (gdje uređaj
ne može otvoriti privatni prozor, poveznica se otvara normalno) ili
"Pitaj svaki put".

---

## 5. Grupe

### Stvaranje grupe

1. Prijeđi na karticu "Grupe".
2. Dodirni gumb plus.
3. Zadaj grupi ime.
4. Odaberi kontakte koje želiš pozvati.
5. Dodirni "Stvori".

Pozvani kontakti primaju obavijest i mogu pristupiti grupi.

### Kako su zaštićene poruke u grupi

U grupi do 16 članova Cleona šalje svaku poruku svakom članu pojedinačno --
svaki put šifriranu samo za tog člana, kao da si svakome napisao vlastitu
poruku. Kvačice uz grupnu poruku pokazuju stanje člana kod kojeg je najmanje
daleko.

Prijeđe li grupa preko 16 članova, koristi zajednički ključ. On se mijenja
svaki dan i iznova se izvlači kada član napusti grupu ili bude uklonjen; novi
član čita tek od svog pristupa. Tamo kvačice više ne pokazuju stanje svakog
člana, nego da je poruka položena u mreži. Padne li grupa na 12 ili manje
članova, vraća se na pojedinačno slanje.

### Slike u grupama i kanalima

U postavkama grupe ili kanala s "Uvijek učitaj slike" određuješ učitavaju li
se slike odmah ili tek kada dodirneš neku od njih.

### Pozivanje članova

I nakon stvaranja možeš pozvati daljnje kontakte:

1. Otvori podatke grupe (izbornik s tri točkice u pregledu grupa ili
   gornja traka u grupnom chatu).
2. Dodirni "Pozovi".
3. Odaberi kontakte koje želiš dodati.

### Uloge

Svaka grupa ima tri uloge:

- **Vlasnik (Owner):** Ima potpunu kontrolu. Može dodavati i uklanjati članove,
  imenovati administratore i upravljati grupom. Vlasnik može i prenijeti
  svoj status na drugog člana.
- **Administrator:** Može uklanjati članove i pomagati pri upravljanju.
- **Član:** Može čitati i pisati poruke.

### Napuštanje grupe

1. Otvori izbornik s tri točkice u pregledu grupa.
2. Odaberi "Napusti".
3. Potvrdi svoju odluku.

Kada napustiš grupu, tvoje dosadašnje poruke ostaju vidljive ostalim
članovima.

---

## 6. Javni kanali

### Što su kanali?

Kanali su javni raspravni forumi unutar mreže Cleone. Za razliku od
grupa, ovdje svatko može čitati bez poziva. Samo vlasnik i administratori
mogu objavljivati priloge -- pretplatnici čitaju.

### Pronalaženje i pristupanje kanalima

1. Prijeđi na karticu "Kanali".
2. Otvori karticu "Pretraga".
3. Pretraži dostupne kanale po imenu ili temi.
4. Dodirni kanal i zatim "Pretplati se".

Kanali se mogu filtrirati po jeziku. Neki su kanali označeni kao "Nije
prikladno za mlade" -- ti su vidljivi tek kad si u svom profilu potvrdio
da si stariji od 18 godina.

### Stvaranje vlastitog kanala

1. Prijeđi na karticu "Kanali".
2. Dodirni gumb plus.
3. Upiši ime kanala (mora biti jedinstveno u cijeloj mreži).
4. Odaberi jezik i treba li kanal biti javan ili privatan.
5. Neobavezno: Dodaj opis i sliku.
6. Dodirni "Stvori".

Za javne kanale možeš odrediti sadrži li sadržaj klasifikaciju "Nije
prikladno za mlade".

### Prijavljivanje sadržaja

Ako ti u javnom kanalu zapaze neprikladni sadržaj, možeš ga prijaviti.
Cleona koristi decentralizirani sustav moderacije: Prijave ocjenjuju
nasumično odabrani članovi mreže (neka vrsta "porote"). Ako se utvrdi
prekršaj, kanal dobiva upozorenje. Pri ponovljenim prekršajima on se u
indexu pretraživanja degradira ili blokira.

### Sustavski kanali

Cleona ima dva ugrađena sustavska kanala:

- **Bug Log:** Kada Cleona prepozna grešku, pita te želiš li poslati
  izvješće o grešci; prethodno vidiš točno što će se objaviti. Ta izvješća
  završavaju u kanalu Bug-Log, gdje ih zajednica može pregledavati. Izvješće
  ne nosi ni ime ni sadržaj tvojih razgovora, nego pseudonim. U beti ono
  dodatno navodi tvoju oznaku (User-ID), da razvojni programeri mogu pitati
  za detalje. Možeš i ručno poslati izvješće s logom (s dijalogom za
  pretpregled i izričitim pristankom).
- **Feature Requests:** Ovdje korisnici mogu podnositi želje za funkcijama
  i glasati za postojeće prijedloge. Prijedlozi se sortiraju po glasovima.

Svako računalo drži do 25 MB po sustavskom kanalu, svaki mobitel do 5 MB;
popuni li se, najstarije ide prvo -- nikad ono što si sam već vidio.

---
## 7. Pozivi

### Pokretanje glasovnog poziva

1. Otvori chat s kontaktom kojeg želiš nazvati.
2. Dodirni ikonu telefona u gornjoj traci.
3. Pričekaj dok sugovornik ne prihvati poziv.

Tijekom razgovora vidiš vremensku crtu, trajanje razgovora i imaš pristup
isključivanju zvuka i zvučniku.

Za prekid dodirni crveni gumb za prekid.

Ako vidiš "Nedostupan", uređaj tvog sugovornika trenutno nije dostupan,
primjerice iPhone sa zatvorenom aplikacijom. Pošalji umjesto toga poruku.

### Pokretanje video-poziva

1. Otvori chat s kontaktom.
2. Dodirni ikonu kamere u gornjoj traci.
3. Tvoja slika pojavljuje se u malom prozoru, a slika sugovornika u
   velikom području.

Tijekom razgovora možeš prebacivati između prednje i stražnje kamere.

### Dolazeći pozivi

Kada te netko nazove, pojavljuje se prozor obavijesti s imenom pozivnika.
Možeš:

- **Prihvatiti** -- razgovor počinje.
- **Odbiti** -- pozivnik se obavještava.

Ako si upravo u razgovoru, novi poziv ne zvoni; umjesto toga dobivaš poruku
"Propušteni poziv". Isto vrijedi za grupni poziv koji nisi prihvatio -- poruka
tada stoji u grupnom chatu.

Nazove li netko jedan od tvojih identiteta koji trenutno nije prikazan, ipak
zvoni; zaslon poziva navodi koji je od tvojih identiteta nazvan.

Na iPhoneu zvoni samo uz otvorenu aplikaciju. Tko te nazove dok nije otvorena,
nakon 10 sekundi vidi "Nedostupan". Čim otvoriš aplikaciju, nalaziš poruku o
propuštenom pozivu.

### Grupni pozivi

Možeš voditi i grupne pozive na kojima istovremeno sudjeluje više osoba.
Poziv se organizira preko inteligentnog stabla prosljeđivanja, tako da
ne mora svaki sudionik biti izravno povezan sa svakim drugim. Svi razgovori
su neprekidno šifrirani.

Svaki član grupe može pokrenuti grupni poziv. Dva sudionika koja nisu kontakti
jedno drugome nikad ne vide internet adresu onog drugog: Njihov ton i slika
teku preko sudionika koji je s oba u kontaktu. Nema li takvoga, ta dvojica
nisu povezana, a pločica kaže "Nema zajedničkog kontakta u pozivu". Je li
neko prosljeđivanje preopterećeno, ton ostaje, a video za taj par otpada.

### Šifriranje kod poziva

Svi pozivi šifriraju se ključevima za jednokratnu uporabu koji postoje
samo za trajanja razgovora. Nakon prekida ti se ključevi odmah brišu.
Nitko ne može naknadno dešifrirati prošli razgovor.

Iskreno rečeno: Pozivi, gdje god je moguće, teku izravno između uređaja,
jer već mala odgoda smeta pri govoru. Za razliku od poruka, tvoj pružatelj
interneta zato pri pozivu može vidjeti s kojom internet adresom si povezan.
Što govorite, ne vidi.

Pri pozivu i tvoj kontakt vidi tvoju internet adresu. Ako to kod nekog
kontakta ne želiš, isključi u njegovu izborniku "Dopusti pozive" (zadano:
uključeno). Isključiš li kasnije, adresa koju je već vidio ostaje mu poznata.

---

## 8. Kalendar

Cleona sadrži ugrađeni kalendar koji radi šifrirano i potpuno
decentralizirano -- bez oblaka.

### Prikazi

Kalendar nudi pet prikaza: dan, tjedan, mjesec, godina i prikaz zadataka.
Prebacuj između njih preko kartica na gornjem rubu zaslona kalendara.

### Stvaranje termina

Dodirni vremenski otvor ili koristi gumb za dodavanje da bi stvorio novi
termin. Možeš unijeti naslov, datum, vrijeme, mjesto i bilješke. Termini se
šifrirano pohranjuju na tvom uređaju.

### Ponavljajući termini

Termini se mogu ponavljati dnevno, tjedno, mjesečno ili godišnje. Možeš
prilagoditi uzorak (npr. svaki drugi utorak, svaki prvog u mjesecu) i
zadati završni datum ili broj ponavljanja.

### Pozivanje kontakata

Pri stvaranju ili uređivanju termina možeš pozvati svoje Cleona-kontakte.
Oni primaju šifriranu pozivnicu za kalendar i mogu odgovoriti s prihvaćanjem,
odbijanjem ili "možda". Promjene na terminu automatski se šalju svim
pozvanima.

### Prikaz slobodno/zauzeto

Svoju dostupnost možeš dijeliti s kontaktima bez otkrivanja detalja termina.
Postoje tri razine zaštite privatnosti: puni detalji, samo vremenski blokovi
ili skriveno. Možeš zadati standard i prepisivati ga po kontaktu.

### Podsjetnici

Termini mogu imati podsjetnike koji prije početka termina pokreću
sustavsku obavijest. Podsjetnike po potrebi možeš odgoditi.

### Sinkronizacija s vanjskim kalendarom

Cleona se može sinkronizirati s vanjskim kalendarima:

- **CalDAV** -- Poveži se s bilo kojim CalDAV-kompatibilnim poslužiteljem
  (Nextcloud, Radicale itd.).
- **Google Kalendar** -- Sinkronizacija preko Google Calendar API-ja s
  sigurnom OAuth2-autentifikacijom.
- **Lokalni CalDAV-poslužitelj** -- Cleona može pokrenuti lokalni
  CalDAV-poslužitelj na tvom uređaju, tako da kalendarske aplikacije za
  računala (Thunderbird, Outlook, Apple Kalendar, Evolution) mogu sinkronizirati
  s tvojim Cleona-kalendarom.
- **Sustavski kalendar Androida** -- Termini iz Cleone mogu se prenijeti u
  ugrađenu kalendarsku aplikaciju tvog Android-uređaja.
- **ICS-datoteke** -- Uvezi i izvezi termine u standardnom iCalendar-formatu.

### PDF-izvoz

Svaki prikaz kalendara (dan, tjedan, mjesec, godina) možeš ispisati ili
izvesti kao PDF-dokument.

---

## 9. Ankete

Možeš stvarati ankete u svakom chatu ili grupi da bi prikupio mišljenja
ili planirao termine.

### Vrste anketa

Cleona podržava pet vrsta anketa:

- **Jednostruki izbor** -- sudionici odabiru jednu opciju.
- **Višestruki izbor** -- sudionici mogu odabrati više opcija.
- **Anketa za termin** -- Nađi termin koji odgovara svima. Svaki sudionik
  označuje termine kao dostupne, možda ili nedostupne.
- **Ljestvica** -- Ocijeni nešto na numeričkoj ljestvici (npr. 1 do 5).
- **Slobodan tekst** -- Sudionici pišu vlastiti odgovor.

### Stvaranje ankete

Otvori chat i dodirni ikonu ankete (ili koristi izbornik privitaka). Odaberi
vrstu ankete, formuliraj svoje pitanje i opcije, i pošalji anketu. Ona se
pojavljuje kao poruka u chatu.

### Glasovanje

Dodirni anketu da bi glasao. Svoj glas možeš u svakom trenutku promijeniti
ili povući.

### Anonimno glasovanje

Ankete se mogu konfigurirati za anonimno glasovanje. Ako je aktivirano,
glasovi su kriptografski anonimni -- nitko, čak ni autor ankete, ne može
vidjeti tko je za što glasovao. Broj glasova ipak ostaje vidljiv.

### Anketa za termin u kalendar

Kada anketa za termin završi, pobjednički termin se jednim dodirom može
izravno pretvoriti u kalendarski unos.

---
## 10. Više identiteta

### Zašto više identiteta?

Zamisli da želiš odijeliti svoj profesionalni i privatni život -- slično
kao s dva različita telefonska broja, ali bez drugog mobitela. U Cleoni
možeš koristiti više identiteta na jednom uređaju. Svaki identitet ima
vlastito ime, vlastitu profilnu sliku, vlastite kontakte i vlastite
razgovore.

### Stvaranje novog identiteta

1. U gornjoj traci vidiš svoj trenutni identitet kao karticu.
2. Dodirni znak plus (+) desno uz svoje kartice identiteta.
3. Upiši ime za novi identitet.
4. Gotovo -- novi je identitet odmah aktivan.

### Prebacivanje između identiteta

Jednostavno dodirni karticu identiteta u gornjoj traci. Prebacivanje je
odmah -- bez čekanja, bez ponovnog učitavanja.

### Svi rade istovremeno

Važna točka: Svi su tvoji identiteti istovremeno aktivni. Čak i ako si
upravo prikazan kao "Poslovno", tvoj "Privatni" identitet i dalje prima
poruke. Ne propuštaš ništa, bez obzira koji identitet si upravo odabrao.

### Detaljna stranica identiteta

Kada dodirneš karticu svog trenutno aktivnog identiteta, otvara se
detaljna stranica. Ovdje možeš:

- Prikazati svoj QR-kod za kontakte.
- Promijeniti ili ukloniti svoju profilnu sliku.
- Dodati opis profila.
- Promijeniti svoje ime za prikaz.
- Odabrati dizajn (skin) za taj identitet.
- Izbrisati identitet ako ga više ne trebaš.

### Brisanje identiteta

Kada izbrišeš identitet, tvoji se kontakti o tome obavještavaju. Identitet
i svi pripadni podaci uklanjaju se s tvog uređaja. Ovaj postupak nije
povratan.

---

## 11. Više uređaja

### Jedan identitet, jedan uređaj -- za sada

Jedan identitet danas radi na jednom uređaju. Drugi uređaj za isti identitet
stiže u kasnijoj verziji; u postavkama pod "Uređaji" -> "Upravljaj uređajima"
zato "Upari još jedan uređaj" još stoji kao "Još nije dostupno".

Kad to dođe, vrijedi: Svi uređaji su ravnopravni, nema glavnog uređaja. Još
jedan uređaj postavljaš sa svojih 24 riječi, i jedan od tvojih dosadašnjih
uređaja pristaje. Najviše 5 uređaja.

Uneseš li danas svojih 24 riječi na novom uređaju, seliš se: Identitet se
obnavlja na novom uređaju, a tvoj dosadašnji uređaj uklanja je nakon toga
kod sebe (vidi poglavlje 12).

Na više uređaja možeš danas koristiti različite identitete (poglavlje 10).

### Rotiraj ključeve identiteta

Sumnjaš li da se netko domogao tvojih ključeva, možeš pod "Upravljaj
uređajima" -> "Rotiraj ključeve" stvoriti nove ključeve. Tvoji kontakti se
obavještavaju, tvoji otvoreni pozivi se opozivaju. Važno: Nakon toga 24 riječi
same stvaraju još samo stare ključeve. Zato odmah nakon toga napravi novi
paket za oporavak; obnoviti tada možeš još samo zajedno s tim paketom.

---

## 12. Obnova

### Korištenje seed-izraza

Ako izgubiš svoj uređaj ili postavljaš novi:

1. Instaliraj Cleonu na novom uređaju.
2. Pri pokretanju odaberi "Obnovi".
3. Upiši svojih 24 riječi.
4. Cleona iz njih ponovno stvara sve svoje identitete -- s istim
   ključevima kao prije. Za tvoje kontakte ti si ista osoba.

### Što se vraća -- a što ne

Tvoj identitet stoji u 24 riječi, tvoji kontakti i tvoja povijest ne. Vraća
se tvoj pristup mreži preko **paketa za oporavak**: Tvoj uređaj polaže mali,
šifrirani paket u mreži. Samo tvojih 24 riječi može ga pronaći i otvoriti.
U njemu stoji što tvoj novi uređaj treba da bi ponovno dosegnuo tvoje
kontakte, i što je u međuvremenu za tebe ležalo u mreži. Za to ne mora biti
online nijedan kontakt.

Dosadašnju povijest razgovora obnova ne vraća.

Paket za oporavak živi 7 dana i tvoj ga uređaj obnavlja dok god radi; u
postavkama vidiš do kada vrijedi. Nije li dulje od 7 dana radio nijedan od
tvojih uređaja, on je istekao. Tada 24 riječi ipak obnavljaju tvoj identitet,
ali tvoje kontakte moraš iznova pozvati; što je u međuvremenu za tebe ležalo
u mreži, izgubljeno je.

### Obnova znači seljenje

Utvrdi li tvoj dosadašnji uređaj kasnije da je identitet negdje drugdje
obnovljen, on ga uklanja kod sebe -- s njegovom poviješću. Zato: Tko ima
tvojih 24 riječi, može na taj način uzeti tvoj identitet s tvog uređaja.
Dok se svi kontakti ne vrate, aplikacija te podsjeća; s "Dovrši i obnovi
ključeve" sam završavaš obnovu.

### Što nitko ne može obnoviti

To je važno, i zato to kažemo jasno:

- **Nitko osim tebe ne može obnoviti tvoj identitet.** Ni razvojni programer,
  ni podrška, a ni tvoji kontakti -- bez obzira koliko ih je. Nema glavnog
  ključa i nema dijela tvog ključa koji bi bio pohranjen kod drugih.
- **Ako si izgubio 24 riječi i više nemaš uređaj, tvoj je identitet izgubljen.**
  Tada preostaje samo da stvoriš novi i iznova pozoveš svoje kontakte.

Najbolja zaštita: Zapiši 24 riječi na papir i čuvaj ih na sigurnom.

---
## 13. Postavke

Postavke otvaraš preko ikone zupčanika u gornjem desnom kutu.

### Obavijesti i melodije zvona

- Odaberi jednu od šest različitih melodija zvona za dolazeće pozive.
- Postavi ton poruke.
- Na Android-uređajima dodatno možeš aktivirati ili deaktivirati vibraciju.
- **"Utišaj sve"** ne dopušta da na ovom uređaju ijedna poruka više zvoni,
  vibrira ili se javlja -- za sve identitete. Pozivi i dalje zvone.
- **"Vrijeme tišine"** postavljaš po identitetu s Od/Do. U tom vremenu
  nijedna poruka tog identiteta ne zvoni, ne vibrira i ne javlja se; poruke
  ipak dolaze.
- **"Obavijesti bez sadržaja"** (zadano: isključeno) pokazuje samo da je
  stigla poruka, pozivnica ili podsjetnik -- bez pošiljatelja, imena i
  teksta. Pozivi i dalje pokazuju ime.
- Što nakon pokretanja odjednom stigne, Cleona prijavljuje u jednoj skupnoj
  obavijesti ("5 novih poruka u 2 razgovora"); sve kasnije pojedinačno.
  Dodir na obavijest o poruci otvara razgovor, čak i u drugom identitetu.

### Dizajni (skinovi)

Cleona nudi deset različitih dizajna: Teal, Ocean, Sunset, Forest,
Amethyst, Fire, Storm, Slate, Gold i Contrast. Dizajn Contrast ispunjava
najvišu razinu pristupačnosti (WCAG AAA) i pri smanjenom vidu posebno je
dobro čitljiv.

Svaki identitet može imati vlastiti dizajn. Dizajn mijenjaš na detaljnoj
stranici identiteta (dodirni aktivnu karticu identiteta).

Dodatno možeš u postavkama pod "Prikaz" prebacivati između svijetle,
tamne i teme sustava.

### Promjena jezika

Cleona je dostupna na 34 jezika, među njima i jezicima s pisanjem s desna
na lijevo (npr. arapski, hebrejski). Promijeni jezik u postavkama pod
"Jezik".

### Arhiviranje medija

Ako kod kuće imaš mrežni disk (NAS) ili dijeljenu mapu, Cleona može tvoje
medije automatski tamo izmjestiti. Podržani su SMB, SFTP, FTPS i WebDAV.

Tako radi stupnjevito pohranjivanje:
- Prvih 30 dana: Sve ostaje na tvom uređaju.
- Nakon 30 dana: Sličica za pretpregled ostaje na uređaju, original se
  arhivira.
- Nakon 90 dana: Samo mala sličica za pretpregled ostaje na uređaju.
- Nakon godine: Samo mjesto-držač ostaje, original sigurno leži u arhivi.

U svakom trenutku možeš dodirnuti arhivirani medij da bi ga vratio --
pod uvjetom da si povezan s kućnom mrežom. Posebno važne medije možeš
prikvačiti da nikada ne budu izmješteni.

Pod "Budžet pohrane" određuješ koliko MB medija ostaje na uređaju (zadano:
100 MB na mobitelu, 2 GB na računalu). Popuni li se, najstariji neprikvačeni
medij arhivira se prvi. Original se briše tek kad sigurno leži u arhivi --
tekstualne poruke uvijek ostaju sačuvane.

### Transkripcija za glasovne poruke

Ako je aktivirano, tvoje glasovne poruke lokalno se na tvom uređaju
pretvaraju u tekst (modelom Whisper otvorenog koda). Transkribirani tekst
šalje se zajedno sa snimkom tvom sugovorniku. Transkripcija se događa
potpuno na tvom uređaju -- nikakvi podaci ne idu vanjskim uslugama.

Koji se model preuzima (tiny, base, small) postavljaš jednom za uređaj; jezik
(automatski ili fiksno) po identitetu.

### Automatsko preuzimanje

Možeš postaviti od koje veličine mediji trebaju biti automatski preuzeti.
Tako možeš, na primjer, slike automatski učitavati, ali za velike video-snimke
odlučivati ručno.

### Uređaji

Pod "Uređaji" -> "Upravljaj uređajima" vidiš ovaj uređaj. Uparivanje još
jednog uređaja stiže u kasnijoj verziji (poglavlje 11).

### Mreža

Cleona ne treba mrežne postavke da bi radila. Postoje tri mrežna
prekidača:

- **Otvaranje porta na usmjerivaču** (zadano: uključeno). Cleona moli tvoj
  vlastiti usmjerivač da za Cleonu otvori vrata. Ako uspije, tvoj je uređaj
  za druge bolje dostupan i pomaže mreži. Pritom Cleona razgovara samo s
  tvojim usmjerivačem, ne s internetom.
- **Javni zapisi adresa** (zadano: uključeno). Ako tvoj uređaj još ima
  premalo susjeda, potražuje u javnom imeniku (Nostr) daljnje ulazne točke,
  a i sam se, ako je dobro dostupan, tamo upisuje. Zapis sadrži adresu, ne
  ime i ne kontakt. Ako ga isključiš, tvoj uređaj pronalazi susjede samo
  još preko poziva, lokalne mreže i susjeda koje već poznaje.
- **Manje prikrivnih paketa u WLAN-u** (zadano: isključeno). U WLAN-u ili
  na kabelu možeš isključiti prazne prikrivne pakete. Tada je tamo opet
  vidljivo kada pišeš. U mobilnoj mreži nema tog prekidača -- tamo Cleona
  ionako šalje samo jedan prikrivni paket u minuti.

Tok prikrivanja u cjelini ne može se isključiti. To je namjerno: Samo ako
uvijek teče, aktivnost tvog uređaja ne govori ništa o tome pišeš li upravo.

Iznad ta tri prekidača stoji **Način uštede podataka**: U mobilnoj mreži
Cleona ga predlaže, ali ga nikad ne uključuje sama. On štedi podatke, a za
uzvrat je tvoj uređaj izvana lakše prepoznatljiv.

Ispod njih postavljaš **"Predmemorija za tuđe medije"**: Tvoj uređaj čuva
šifrirane dijelove tuđih medija do 7 dana, da stignu do svojih primatelja
(zadano: 100 MB na mobitelu, 1 GB na računalu). Manja veličina odmah
oslobađa prostor -- najstariji dijelovi prvi.

---

## 14. Sigurnost

### Što znači post-kvantno šifriranje?

Današnje šifriranje temelji se na matematičkim problemima koji su za obična
računala iznimno teško rješivi. Kvantni računali bi neke od tih problema
ubuduće mogla brzo riješiti. Post-kvantno šifriranje koristi dodatne
postupke koji odolijevaju i kvantnim računalima.

Cleona kombinira oba pristupa: klasično šifriranje za pouzdanost i
post-kvantne postupke za sigurnost budućnosti. Tako si istovremeno zaštićen
od današnjih i budućih prijetnji.

Za svaku pojedinu poruku stvara se vlastiti ključ. Čak i kad bi napadač
razbio ključ jedne poruke, ne bi mogao pročitati nijednu drugu poruku.

### Zašto je bez poslužitelja sigurnije

Kod uobičajenih messengera tvoje poruke teku preko poslužitelja pružatelja.
Čak i ako su tamo šifrirane: Pružatelj ima pristup metapodacima (tko s kim
komunicira, kada, koliko često, odakle) i mora ih po sudskom nalogu eventualno
izručiti.

U Cleoni nema takve središnje točke. Nema mjesta gdje se svi metapodaci
okupljaju, i nema imenika u kojem bi se moglo potražiti tko si ili koga
poznaješ.

### Tko vidi da s nekim pišeš?

Šifriranje štiti **što** pišeš. Jednako je važno da nijedan pojedinačni
promatrač ne doznaje **s kim** i **kada** pišeš. Za to Cleona skrbi ovako:

- **Na internetu nikad izravno.** Da tvoj uređaj šalje poruku izravno na
  internet adresu sugovornika, tvoj bi pružatelj mogao vidjeti s kim pišeš.
  Zato poruka na internetu uvijek ide preko vaših čvrstih susjeda: tvog i
  onih tvog sugovornika.
- **Susjedi kojima vjeruješ.** Tvoji čvrsti susjedi su, gdje god je moguće,
  uređaji tvojih vlastitih kontakata -- do tri koji su upravo izvana dostupni.
  Padne li jedan, nadomješta drugi kontakt. Kontakt se ne da kupiti
  poslužiteljima; proizvoljan čvor u mreži već da. Ako još nemaš dostupnog
  kontakta, Cleona uzima drugog susjeda. Tvoj poziv nikada ne imenuje nijednog
  tvog kontakta, da nitko preko njih ne dozna adresu prijatelja.
- **Kodovi umjesto imena.** Susjedi ne vide imena i ne vide oznake, nego
  samo kod. On vrijedi točno za vas dvoje, u jednom smjeru, za jedan dan --
  sutradan je drugi. Tvoj susjed zna odakle paket dolazi, ali ne kamo na
  kraju ide. Susjed tvog sugovornika zna kamo ide, ali ne otkud je došao.
  U pravilu nitko usput ne vidi oba kraja.
- **Tok prikrivanja.** Tvoj uređaj stalno, u nepravilnim razmacima, šalje
  prikrivne pakete svojim susjedima. Oni su jednako veliki kao stvarni
  paketi, idu preko istog porta i izvana se od njih ne razlikuju. Piše li
  upravo čovjek ili uređaj samo radi, time nije prepoznatljivo. Tvoje poruke
  nikada ne čekaju na tok prikrivanja -- one kreću odmah, on tek teče usput.

**Što tok prikrivanja košta:** U WLAN-u oko 13 MB dnevno. U mobilnoj mreži
Cleona šalje samo jedan prikrivni paket u minuti, to je oko 1,7 MB dnevno.
Razlog za ograničenje u mobilnoj mreži nije količina podataka, nego baterija:
Svaki paket budi radijski modem.

**Što Cleona ne može sakriti** -- iskreno rečeno:

- Nijedan **pojedinačni** promatrač ne vidi tko s kim piše -- ni tvoj
  pružatelj ni čvorovi usput. Tko pak **istovremeno nadzire oba kraja**,
  primjerice država koja motri tvoj priključak i priključak tvog sugovornika
  ili postavlja oba susjeda, može tijekom vremena pridružiti: Paket izlazi
  kod tebe, malo zatim paket ulazi kod tvog sugovornika. Dovoljno često
  ponovljeno, daje to vezu.
- Tok prikrivanja otežava to pridruživanje, ali ga ne sprječava. On skriva
  pojedinačne poruke, ne količinu: Tko vrlo mnogo šalje, povećava ukupni
  promet svog uređaja.
- Kontakt koji je tvoj čvrsti susjed doznaje **kada** i **koliko** šalješ i
  primaš -- ne s kim i ne što. Ako prijetnja dolazi iz tvoje vlastite okoline,
  možeš izuzeti svaki kontakt (vidi poglavlje 3, "Nikada ne koristiti kao
  čvrstog susjeda").
- Ako dva nova korisnika imaju samo istog jednog susjeda, njihova poruka teče
  točno preko tog čvora, i on vidi oba kraja. Čim jedan od njih dvoje dobije
  daljnje susjede, to je gotovo.
- Tvoj poziv sadrži tvoje internet adrese. Tko ima tekstualni redak, vidi
  gdje si online -- daj ga samo ljudima kojima to povjeravaš.
- Susjed koji prosljeđuje vidi da dva koda razmjenjuju pakete -- ne tko stoji
  iza toga, i ne što je unutra.
- Signal poziva u tijeku može, ako prvi susjed upravo ne odgovara, ići preko
  čvora koji vidi oba kraja; on doznaje da zajedno telefonirate.
- Veliku datoteku kojoj si pristao, računalo koje je prosljeđuje ili čuva
  vidi na oba kraja (vidi poglavlje 4).
- Kod poziva zaštita od pružatelja ne vrijedi, i tvoj kontakt vidi tvoju
  internet adresu (vidi poglavlje 7).

### Što se događa kad je sugovornik offline?

1. Cleona istovremeno pokreće sve odgovarajuće puteve: u istom WLAN-u izravno,
   na internetu preko dva susjeda -- i dodatno poštanski sandučić.
2. Za poštanski sandučić Cleona polaže šifriranu poruku kod tri susjeda.
   Čim dvojica potvrde primitak, vrijedi kao položena.
3. Cleona za to preferira susjede kod kojih tvoj sugovornik i pretražuje --
   najprije susjeda kojeg imenuje njegov poziv.
4. Poruka tamo čeka do 7 dana. Vrati li se sugovornik, on je preuzima i
   potvrđuje ti primitak. Tek tada vidiš dvije kvačice.

Poštanski sandučić može isprazniti samo tvoj sugovornik: Preuzimanje i
brisanje ide samo s ključem koji posjeduje samo on, a briše se tek kad
potvrdi primitak. Susjedi vide samo šifrirane pakete pod vrijednošću koja
se svakog dana mijenja.

### Stranci ne prolaze

Od nekoga tko nije ni tvoj kontakt ni član zajedničke grupe, Cleona prima
točno dvije stvari: pitanje
za tvoje javne ključeve, dok god je jedan od tvojih poziva otvoren, i
zahtjev za kontakt. Zahtjev mora nositi valjani poziv od tebe, a pošiljatelj
mora prethodno riješiti računski zadatak. Sve ostalo -- poruke, pozive,
datoteke -- odbacuje se prije nego uopće dosegne aplikaciju. Tko ima samo
tvoju tiskanu vizitku, te ne može tek tako nazvati. Član zajedničke grupe
doseže te samo u toj grupi -- s grupnim porukama i grupnim pozivima, nikad
pojedinačno.

### Anticenzura

Cleona je tako građena da ju je teško blokirati:

- **Nema poslužitelja, nema čvrste adrese.** U aplikaciji ne stoji adresa
  koja bi se mogla zabraniti, i mreža ne ovisi ni o jednom jedinom čvoru.
- **Nema čvrstog porta.** Svaki uređaj pri prvom pokretanju bira slučajni
  port. Nema poznatog broja porta na kojem bi se mogao prepoznati Cleona-promet.
- **Kao slučajni podaci.** Uspostava veze između dvaju uređaja kodirana je
  tako da se od slučajnih podataka ne razlikuje.
- **Mnogo ulaza.** Svaki poziv, svaki susjed i svaki uređaj u istom WLAN-u
  je mogući put natrag u mrežu.

### Sigurna pohrana ključeva

Na podržanim platformama Cleona pohranjuje tvoje ključeve za šifriranje u
sigurnom skupu ključeva operativnog sustava (Android Keystore, iOS Keychain,
macOS Keychain). Gdje je dostupno, to nudi hardverski potkrijepljenu zaštitu
za tvoje ključeve.

### Šifriranje baze podataka

Tvoje poruke i razgovori leže u šifriranoj bazi podataka -- zasebna za
svaki identitet, svaka s vlastitim ključem. Šifrirana nije samo sama baza,
nego i njezine privremene datoteke; ništa se ne zapisuje nešifrirano na disk,
čak ni nakratko. Postavke, kontakti i mediji također su šifrirano pohranjeni.

Ključevi se izvode iz tvojih 24 riječi i postoje samo na tvom uređaju. Čak
i tko se domogne tvog uređaja i pročita podatke, bez tih ključeva nalazi
samo nečitljive podatke.

Nešifrirano je samo tamo gdje sam sadržaj iznosiš iz Cleone:
- kada datoteku iz chata spremaš na svoj uređaj,
- kada gumbom za snimku zaslona stavljaš sliku u svoje slike,
- kada nešto dijeliš s drugom aplikacijom,
- kada postavljaš arhiviranje medija (poglavlje 13): arhivirani originali
  leže nešifrirano na tvojem kućnom mrežnom disku, da bi ih tamo mogao
  otvoriti i bez Cleone,
- kada termine zrcališ u sustavski kalendar Androida: tamo ih mogu čitati
  druge aplikacije s pristupom kalendaru.

Što je tako izašlo, ne briše se s porukom i ne istječe s njom.

### Zaštita na zaslonu

Na Androidu, Windowsu i macOSu Cleona ne dopušta drugim aplikacijama
snimanje zaslona. Treba li ti slika, uzmi gumb za snimku zaslona u gornjoj
traci: On stavlja sliku u tvoje slike -- nešifrirano. U razgovoru u kojem
prosljeđivanje nije dopušteno, nema snimke zaslona.

---

## 15. Ažuriranja softvera

### Kako dobivam ažuriranja?

Cleona se može ažurirati na različite načine. Cilj je da ažuriranja možeš
dobiti i kad pojedini putovi distribucije otkažu ili budu blokirani:

1. **App Store / Play Store:** Čim Cleona tamo izađe i instaliraš je preko
   trgovine, ažuriranja dobivaš kao i obično preko trgovine. Na iPhoneu
   ažuriranja dolaze preko TestFlighta.
2. **GitHub Releases:** Na GitHub-stranici projekta nalaziš potpisane
   instalacijske pakete za sve platforme.
3. **Ažuriranja preko mreže:** Cleona može ažuriranje izravno nabaviti preko
   mreže -- bez poslužitelja za preuzimanje. Nova verzija razložena je u
   komade s korekcijom pogrešaka koji se raspodjeljuju u mreži; jedan dio
   čak putuje i u toku prikrivanja. Tvoj uređaj skupi dovoljno komada i
   sastavlja ažuriranje. Prenosi se najčešće samo promjena -- nekoliko MB
   umjesto cijele aplikacije. To vrijedi za Linux, Windows i Android; na
   macOSu nove verzije preuzimaš s web-mjesta ili s GitHuba.
4. **Pozivne poveznice:** Možeš stvoriti pozivne poveznice koje sadrže sve
   što novi korisnik treba da instalira Cleonu i poveže se s mrežom.
5. **Fizički prijenos:** U okruženjima bez interneta Cleonu možeš proslijediti
   drugima USB-stickom ili u lokalnoj mreži.

### Tako teče ažuriranje

1. Cleona automatski u pozadini skuplja komade novog ažuriranja i sastavlja
   ih.
2. Tek kad je ažuriranje **potpuno** i njegov **potpis provjeren**, Cleona
   ti ga nudi. Tako ti se nikada ne nudi polovično ili neprovjereno
   ažuriranje.
3. Kad dodirneš "Instaliraj", instalacija kreće bez daljnjeg ispitivanja. Na
   Androidu dodatno sustav prikazuje svoj dijalog instalacije.

Starije verzije se ne nude -- ažuriranje ide uvijek samo naprijed. Ako je
verzija tako stara da više ne može surađivati s mrežom, Cleona to jasno
pokazuje i moli te da ažuriraš.

### Provjera potpisa

Svako je ažuriranje dvostruko potpisano: klasičnim i post-kvantnim postupkom.
Cleona automatski provjerava oba potpisa. Tako je osigurano da se prihvaćaju
samo ažuriranja službenog razvojnog programera -- iako je ažuriranje preko
mreže došlo od tuđih uređaja. Ažuriranje nikada ne nastaje automatski iz
razvoja, nego tek kad razvojni programer ručno potpiše.

---
## 16. Česta pitanja

### "Mogu li koristiti Cleonu bez interneta?"

Cleona treba mrežnu vezu, ali ne nužno internet: U istom WLAN-u Cleona-uređaji
se nalaze sami i mogu potpuno bez internetskog pristupa pisati jedni s drugima.
Istovremeno online s sugovornikom ne moraš biti: Ako je offline, poruka čeka
do 7 dana u poštanskom sandučiću kod tri susjeda, dok je ne preuzme.

### "Što ako izgubim svoj seed-izraz?"

Dok god još radi jedan uređaj s tvojim identitetom, ništa nije izgubljeno --
tada jednostavno nastavljaš pisati na njemu. Na uređaju na kojem si stvorio
identitet možeš 24 riječi najčešće i ponovno pročitati (vidi poglavlje 2).
Ne oslanjaj se na to: Nova instalacija uklanja tu kopiju, a na Androidu
briše je i uklanjanje ili promjena zaključavanja zaslona. Ako nemaš ni
riječi ni uređaj, nema povratka -- ni preko tvojih kontakata, razvojnog
programera ili bilo koga drugog. Zato je tako važno čuvati 24 riječi na
sigurnom.

### "Može li netko čitati moje poruke?"

Ne. Svaka se poruka šifrira ključem za jednokratnu uporabu koji vrijedi samo
za tu jednu poruku. Samo ti i tvoj sugovornik možete dešifrirati poruku.
Nema središnjeg poslužitelja, nema glavnog ključa i nema pristupa za razvojnog
programera. Čak i ako uređaj na putu proslijedi poruku, vidi samo šifriranu
kašu podataka i kod. Tvoj susjed zna da paket dolazi od tebe, ali ne kamo
ide; susjed tvog sugovornika zna kamo ide, ali ne od koga.

### "Zašto ne trebam telefonski broj?"

Zato što je tvoj identitet čisto kriptografski. Umjesto telefonskog broja
ili adrese e-pošte koje su vezane uz tvoje pravo ime, tebe identificira par
ključeva stvoren na tvom uređaju. kontakte dodaješ preko QR-koda, NFC-a ili
tekstualnog retka svog poziva -- ne preko imenika. To znači više privatnosti,
jer tvoj račun za messenger nije vezan uz tvoj stvarni identitet.

### "Kako nađem ljude na Cleoni?"

Cleona namjerno nema pretragu kontakata po telefonskom broju ili imenu --
to bi bio problem privatnosti. Umjesto toga pozive razmjenjuješ izravno:
preko QR-koda, NFC-a ili kao tekstualni redak preko drugog puta. To je kao
razmjena vizitki umjesto pretraživanja imenika.

### "Radi li Cleona i u inozemstvu?"

Da. Dok god imaš internetsku vezu, Cleona radi svugdje u svijetu. Budući da
nema središnjeg poslužitelja i čvrste adrese, uslugu se ne može tek tako
isključiti za pojedine države. Kako Cleona otežava blokade, stoji u poglavlju
"Sigurnost" pod "Anticenzura". Država koja na granici blokira svaki nepoznati
promet, može ipak zaustaviti i Cleonu.

### "Je li Cleona besplatna?"

Da. Cleona je besplatna i bez reklama. Budući da nema središnjeg poslužitelja,
ne nastaju ni troškovi poslužitelja za pogon. U postavkama pod "Podrži
Cleona" -> "Doniraj" možeš dobrovoljno podržati razvoj.

### "Moja poruka ima samo jednu kvačicu -- što to znači?"

Poruka je na putu, ali tvoj sugovornik još nije potvrdio primitak -- najčešće
zato što je upravo offline. To nije greška: Poruka čeka do 7 dana u poštanskom
sandučiću. Čim je preuzme, vidiš dvije kvačice. Sat znači da poruku još
nije nosio nijedan put -- ona kreće sama čim se koji pojavi; znak upozorenja
da 14 dana nije pronašla nijedan put i da je možeš ponovno poslati.

### "Zašto poruke kasne na mom iPhoneu?"

iOS ne dopušta aplikacijama trajno raditi u pozadini. Cleona se budi samo
povremeno i kratko; kada, odlučuje iOS. Tada preuzima sve. Čim otvoriš
aplikaciju, Cleona preuzima ono što je za tebe bilo pohranjeno.

### "Mogu li prijeći s WhatsAppa na Cleonu?"

Da, ali svoje WhatsApp-chatove ne možeš prenijeti. Cleona i WhatsApp potpuno
su različiti sustavi. Svoje kontakte moraš pojedinačno dodati u Cleonu.
Najjednostavnije ide ako svojim kontaktima pošalješ tekstualni redak svog
poziva. Svaki zahtjev koji tako stigne, sam potvrđuješ pod "Zahtjevi".

### "Mogu li koristiti Cleonu na više uređaja istovremeno?"

Još ne. Drugi uređaj za isti identitet stiže u kasnijoj verziji (poglavlje
11). Na više uređaja možeš danas koristiti različite identitete.

### "Kako dobivam ažuriranja kad je App Store blokiran?"

Cleona može ažuriranja izravno nabaviti preko mreže, bez ovisnosti o
App Storeu, web-mjestu ili poslužitelju za preuzimanje. Ako drugi uređaj u
mreži ima najnoviju verziju, tvoj uređaj može ažuriranje preuzeti od tamo.
Vjerodostojnost se provjerava digitalnim potpisom razvojnog programera.
Alternativno, kontakt ti može aplikaciju proslijediti pozivnom poveznicom
ili USB-stickom. Više o tome u poglavlju "Ažuriranja softvera".

---

## Pomoć i kontakt

Ako imaš pitanja ili naiđeš na problem, aktualne informacije nalaziš na
web-mjestu Cleone i na GitHubu. Budući da je Cleona decentralizirani projekt,
nema klasične korisničke podrške -- ali aktivnu zajednicu koja rado pomaže.

---

*Ovaj priručnik opisuje Cleona Chat verziju 4.2. Pojedine funkcije se u
novijim verzijama mogu mijenjati ili proširivati.*
# Cleona Chat -- Manual de utilizare

Version 3.1.125 | Actualizat iulie 2026

---

## Cuprins

1. [Ce este Cleona Chat?](#1-ce-este-cleona-chat)
2. [Primii pasi](#2-primii-pasi)
3. [Contacte](#3-contacte)
4. [Mesaje](#4-mesaje)
5. [Grupuri](#5-grupuri)
6. [Canale publice](#6-canale-publice)
7. [Apeluri](#7-apeluri)
8. [Calendar](#8-calendar)
9. [Sondaje](#9-sondaje)
10. [Identitati multiple](#10-identitati-multiple)
11. [Multi-Device](#11-multi-device)
12. [Recuperare](#12-recuperare)
13. [Setari](#13-setari)
14. [Securitate](#14-securitate)
15. [Actualizari software](#15-actualizari-software)
16. [Intrebari frecvente](#16-intrebari-frecvente)

---

## 1. Ce este Cleona Chat?

### Mesageria ta, datele tale

Cleona Chat este un mesager care functioneaza complet fara un server central.
Mesajele tale ajung direct de la dispozitivul tau la dispozitivul
interlocutorului -- fara ocolul unui sediu de firma, fara cloud, fara centru
de date. Nicio companie nu iti poate citi, stoca sau distribui mesajele,
pentru ca pur si simplu nicio companie nu se afla la mijloc.

### Fara cont, fara numar de telefon

La Cleona nu ai nevoie nici de un numar de telefon, nici de o adresa de
e-mail pentru a te inregistra. Identitatea ta consta dintr-o pereche de chei
criptografice, generata automat pe dispozitivul tau la prima pornire. Asta
inseamna ca nimeni nu te poate identifica dupa numarul de telefon sau adresa
de e-mail, decat daca imparti tu insuti aceste date de contact.

### Criptare pregatita pentru viitor

Cleona foloseste asa-numita criptare post-cuantica. Asta inseamna ca nici
chiar viitoarele calculatoare cuantice nu ar putea sparge mesajele tale. Nu
trebuie sa intelegi detaliile tehnice -- important este doar ca
comunicarea ta este protejata cat mai bine posibil, conform stadiului actual
al tehnologiei.

### Cum functioneaza fara server?

Imagineaza-ti ca tu si contactele tale formati impreuna o retea. Fiecare
dispozitiv ajuta la transmiterea mesajelor mai departe. Daca interlocutorul
tau este online chiar acum, mesajul ajunge direct la el. Daca interlocutorul
tau este offline, contactele comune stocheaza mesajul temporar si il livreaza
de indata ce destinatarul revine online. Asadar, contactele tale sunt in
acelasi timp si reteaua ta.

### Platforme

Cleona este disponibil pentru Android, iOS, macOS, Linux si Windows.

---

## 2. Primii pasi

### Instalarea aplicatiei

**Android:**
1. Descarca fisierul APK de pe website-ul Cleona sau din GitHub Releases.
2. Deschide fisierul pe telefonul tau. Daca este necesar, permite
   instalarea din surse necunoscute (Android te va intreba automat).
3. Apasa pe "Instalare" si asteapta pana cand instalarea se incheie.

**iOS:**
1. Deschide link-ul de invitatie TestFlight pe iPhone-ul tau.
2. Apasa pe "Instalare". TestFlight este metoda oficiala Apple de
   distribuire a aplicatiilor beta.
3. Dupa instalare, gasesti Cleona pe ecranul principal.

**macOS:**
1. Descarca fisierul DMG de pe website-ul Cleona sau din GitHub Releases.
2. Deschide DMG-ul si trage Cleona in folderul Aplicatii.
3. La prima pornire, macOS te poate intreba daca vrei sa deschizi
   aplicatia unui dezvoltator identificat -- confirma acest lucru.

**Linux (Ubuntu/Debian):**
1. Descarca fisierul .deb de pe website-ul Cleona sau din GitHub Releases.
2. Instaleaza cu dublu-clic sau in terminal: `sudo dpkg -i cleona-chat_VERSION_amd64.deb`
3. Porneste Cleona din meniul de aplicatii sau in terminal cu `cleona-chat`.

**Linux (Fedora/openSUSE):**
1. Descarca fisierul .rpm de pe website-ul Cleona sau din GitHub Releases.
2. Instaleaza cu: `sudo dnf install cleona-chat-VERSION.x86_64.rpm`
3. Porneste Cleona din meniul de aplicatii sau in terminal cu `cleona-chat`.

**Linux (toate distributiile -- AppImage):**
1. Descarca fisierul .AppImage de pe website-ul Cleona sau din GitHub Releases.
2. Fa fisierul executabil: clic-dreapta, Proprietati, Executabil, sau in terminal: `chmod +x cleona-chat-VERSION-x86_64.AppImage`
3. Porneste prin dublu-clic sau in terminal: `./cleona-chat-VERSION-x86_64.AppImage`

**Windows:**
1. Descarca programul de instalare de pe website-ul Cleona sau din GitHub Releases.
2. Ruleaza fisierul de instalare si urmeaza instructiunile.
3. Porneste Cleona din meniul Start sau de pe scurtatura de pe desktop.

### Crearea unei identitati

La prima pornire, Cleona iti creeaza automat o noua identitate. Poti sa iti
alegi un nume afisat -- acesta este numele pe care il vor vedea contactele
tale. Acest nume poate fi schimbat oricand.

### Notarea Seed-Phrase -- cel mai important lucru dintre toate

Dupa crearea identitatii tale, Cleona iti afiseaza 24 de cuvinte. Aceasta este
**Seed-Phrase**-ul tau -- cheia ta personala de recuperare.

**Noteaza aceste 24 de cuvinte pe hartie si pastreaza-le intr-un loc sigur.**

De ce este atat de important?

- Daca telefonul tau se strica, se pierde sau este furat, poti sa iti
  recuperezi intreaga identitate pe un dispozitiv nou folosind aceste 24 de
  cuvinte.
- Fara Seed-Phrase nu exista cale de intoarcere. Nu exista un buton "am uitat
  parola" si niciun suport care sa iti poata reda contul -- pentru ca nu
  exista niciun cont pe un server.
- Nu impartasi niciodata Seed-Phrase-ul cu altcineva. Cine cunoaste aceste
  cuvinte se poate da drept tine.

Vei gasi Seed-Phrase-ul mai tarziu si in setari, la "Securitate", daca vrei
sa il vezi din nou.

### Adaugarea primului contact

Pentru a discuta cu cineva, trebuie mai intai sa adaugi acea persoana ca
si contact. Exista mai multe metode pentru asta -- toate sunt explicate in
sectiunea urmatoare.

---

## 3. Contacte

### Scanarea unui QR-Code (recomandat)

Cel mai simplu mod de a adauga un contact:

1. Interlocutorul tau deschide pagina de detalii a identitatii sale
   (apasa pe propriul nume din bara de sus) si iti arata QR-Code-ul sau.
2. Apesi pe butonul plus si alegi "Scaneaza QR-Code".
3. Tine telefonul in fata QR-Code-ului interlocutorului tau.
4. Cererea de contact este trimisa automat. De indata ce interlocutorul tau
   o accepta, puteti sa va scrieti unul altuia.

Daca va intalniti personal, QR-Code este cea mai sigura metoda, pentru ca
stii exact cu cine faci schimb de contact.

### NFC (apropierea telefoanelor)

Daca ambele dispozitive suporta NFC:

1. Deschideti amandoi functia de adaugare contact.
2. Tineti telefoanele spate in spate, unul langa altul.
3. Datele de contact sunt schimbate automat.

NFC ofera, la fel ca QR-Code, un nivel ridicat de securitate, pentru ca
schimbul functioneaza doar daca stati fizic unul langa altul.

### Trimiterea unui link (URI cleona://)

Poti sa iti trimiti link-ul de contact si prin e-mail, SMS sau printr-un
alt mesager:

1. Deschide pagina de detalii a identitatii tale.
2. Copiaza link-ul tau cleona://.
3. Trimite link-ul persoanei care vrea sa te adauge.
4. Cealalta persoana deschide link-ul sau il lipeste in dialogul de
   adaugare contact.

Retine: prin aceasta metoda ai incredere ca link-ul nu a fost modificat pe
parcursul transmiterii. Pentru contacte deosebit de sensibile, recomandam
QR-Code sau NFC.

### Acceptarea cererilor de contact

Cand cineva iti trimite o cerere de contact, aceasta apare in Inbox-ul tau
(ultimul tab din bara de jos). Acolo poti:

- **Accepta** -- persoana este adaugata la contactele tale.
- **Respinge** -- cererea este eliminata.
- **Bloca** -- persoana nu iti mai poate trimite alte cereri.

### Niveluri de verificare

Cleona iti arata cat de sigur este confirmata identitatea unui contact:

| Nivel | Semnificatie |
|-------|-----------|
| Necunoscut | Ai primit doar Node-ID-ul sau un link. |
| Vazut | Schimbul de chei a reusit, puteti comunica criptat. |
| Verificat | V-ati intalnit personal si ati verificat prin QR-Code sau NFC. |
| De incredere | Ai marcat explicit acest contact ca fiind de incredere. |

Cu cat nivelul este mai ridicat, cu atat poti fi mai sigur ca vorbesti
intr-adevar cu persoana potrivita.

---

## 4. Mesaje

### Trimiterea si primirea de text

Scrie pur si simplu mesajul tau in campul de introducere de jos si apasa
Enter sau butonul de trimitere. Mesajul tau este criptat automat inainte de
a parasi dispozitivul tau.

Mesajele primite apar in istoricul conversatiei. O bifa iti arata daca
mesajul tau a fost livrat.

### Trimiterea de imagini, videoclipuri si fisiere

Ai mai multe optiuni:

- **Iconita de agrafa** din campul de introducere: apasa pe ea pentru a
  selecta un fisier, o imagine sau un videoclip din galeria sau din sistemul
  tau de fisiere.
- **Drag and drop** (desktop): trage pur si simplu un fisier in fereastra
  de chat.
- **Lipire din clipboard** (desktop): copiaza o imagine si lipeste-o in
  chat.

Fisierele mici (sub 256 KB) sunt trimise direct impreuna cu mesajul.
Fisierele mai mari sunt transferate printr-o procedura in doua etape: mai
intai fisierul este anuntat, apoi transmis in bucati.

### Mesaje vocale

1. Tine apasat butonul de microfon din campul de introducere.
2. Rosteste mesajul tau.
3. Elibereaza butonul pentru a trimite mesajul.

Daca recunoasterea vocala este activata pe dispozitivul tau (vezi setari),
mesajul tau vocal este transcris automat in text. Interlocutorul tau vede
atunci atat inregistrarea, cat si textul transcris.

### Raspunsul la mesaje (citare)

Pentru a raspunde la un mesaj anume:

1. Deschide meniul cu trei puncte de langa mesaj.
2. Alege "Raspunde".
3. Deasupra campului de introducere apare un banner cu mesajul citat.
4. Scrie raspunsul tau si trimite-l.

Mesajul citat este afisat in raspunsul tau, astfel incat legatura sa fie
clara.

### Editarea si stergerea mesajelor

- **Editare:** meniul cu trei puncte al mesajului, apoi "Editeaza".
  Modifica textul si trimite-l din nou. Interlocutorul tau vede ca mesajul
  a fost editat. Editarea este posibila timp de 15 minute de la trimitere.
- **Stergere:** meniul cu trei puncte al mesajului, apoi "Sterge". Mesajul
  este eliminat atat la tine, cat si la interlocutorul tau. Poti sa iti
  stergi propriile mesaje oricand -- nu exista o limita de timp pentru
  stergere.

### Reactii cu emoji

In loc sa scrii un raspuns, poti reactiona la un mesaj cu un emoji:

1. Deschide meniul cu trei puncte sau tine apasat mesajul.
2. Alege un emoji din selectia rapida sau deschide selectorul de emoji
   pentru gama completa.
3. Reactia ta apare sub mesaj.

### Copierea textului

Prin meniul cu trei puncte al unui mesaj poti copia textul mesajului in
clipboard.

### Cautarea mesajelor

In partea de sus a ferestrei de chat gasesti functia de cautare. Introdu
un termen de cautare, iar Cleona iti va arata toate rezultatele din chat-ul
curent. Cu tastele sageata poti sari inainte si inapoi intre rezultate.

Pe ecranul principal exista suplimentar un filtru de cautare pe toate
tab-urile, cu care poti cauta toate conversatiile dupa un anumit termen.

### Previzualizarea link-urilor

Cand trimiti un link, Cleona genereaza automat o previzualizare (titlu,
descriere, imagine de previzualizare). Aceasta previzualizare este creata
de dispozitivul tau si trimisa impreuna cu mesajul -- interlocutorul tau nu
trebuie sa stabileasca o conexiune la website-ul respectiv.

Cand apesi pe un link primit, esti intrebat daca vrei sa il deschizi in
browser-ul normal, in modul incognito sau deloc.

---

## 5. Grupuri

### Crearea unui grup

1. Treci la tab-ul "Grupuri".
2. Apasa pe butonul plus.
3. Da grupului un nume.
4. Selecteaza contactele pe care vrei sa le inviti.
5. Apasa pe "Creeaza".

Contactele invitate primesc o notificare si se pot alatura grupului.

### Invitarea membrilor

Si dupa creare poti invita alte contacte:

1. Deschide informatiile grupului (meniul cu trei puncte din
   prezentarea grupului sau bara de sus din chat-ul grupului).
2. Apasa pe "Invita".
3. Selecteaza contactele pe care vrei sa le adaugi.

### Roluri

Fiecare grup are trei roluri:

- **Proprietar (Owner):** are control total. Poate adauga si elimina
  membri, poate numi admini si administra grupul. Proprietarul isi poate
  transfera statutul si catre alt membru.
- **Admin:** poate elimina membri si ajuta la administrare.
- **Membru:** poate citi si scrie mesaje.

### Parasirea unui grup

1. Deschide meniul cu trei puncte din prezentarea grupului.
2. Alege "Paraseste".
3. Confirma decizia ta.

Cand parasesti un grup, mesajele tale anterioare raman vizibile pentru
ceilalti membri.

---

## 6. Canale publice

### Ce sunt canalele?

Canalele sunt forumuri publice de discutie in cadrul retelei Cleona. Spre
deosebire de grupuri, aici oricine poate citi fara sa fie nevoie sa fie
invitat. Doar proprietarul si adminii pot publica postari -- abonatii
doar citesc.

### Gasirea si alaturarea la canale

1. Treci la tab-ul "Canale".
2. Deschide fila "Cautare".
3. Cauta printre canalele disponibile dupa nume sau tema.
4. Apasa pe un canal si apoi pe "Aboneaza-te".

Canalele pot fi filtrate dupa limba. Unele canale sunt marcate ca
"Interzis minorilor" -- acestea sunt vizibile doar daca ai confirmat in
profilul tau ca ai peste 18 ani.

### Crearea unui canal propriu

1. Treci la tab-ul "Canale".
2. Apasa pe butonul plus.
3. Introdu un nume de canal (trebuie sa fie unic in intreaga retea).
4. Alege limba si daca canalul va fi public sau privat.
5. Optional: adauga o descriere si o imagine.
6. Apasa pe "Creeaza".

La canalele publice poti stabili daca continutul este clasificat drept
"Interzis minorilor".

### Raportarea continutului

Daca observi continut nepotrivit intr-un canal public, il poti raporta.
Cleona foloseste un sistem de moderare descentralizat: raportarile sunt
evaluate de membri ai retelei selectati aleatoriu (un fel de "juriu
popular"). Daca se constata o incalcare, canalul primeste un avertisment.
In cazul incalcarilor repetate, canalul este retrogradat in indexul de
cautare sau blocat.

### Canale de sistem

Cleona are doua canale de sistem integrate:

- **Bug Log:** cand Cleona detecteaza o eroare, te intreaba daca vrei sa
  trimiti un raport de eroare anonimizat. Aceste rapoarte ajung in canalul
  Bug Log, unde pot fi vizualizate de comunitate. Nu se transmit date
  personale -- doar descrieri tehnice ale erorilor. Poti trimite si manual
  un raport de log (cu dialog de previzualizare si consimtamant explicit).
- **Feature Requests:** aici utilizatorii pot depune cereri de functii noi
  si pot vota propunerile existente. Propunerile sunt sortate dupa numarul
  de voturi.

Ambele canale de sistem au o limita de dimensiune de 25 MB si sunt
monitorizate prin sistemul de moderare Jury.

---

## 7. Apeluri

### Initierea unui apel vocal

1. Deschide chat-ul cu contactul pe care vrei sa il suni.
2. Apasa pe simbolul de telefon din bara de sus.
3. Asteapta pana cand interlocutorul tau accepta apelul.

In timpul convorbirii vezi o cronologie, durata convorbirii si ai acces
la functiile de mut si difuzor.

Pentru a inchide, apasa pe butonul rosu de inchidere.

### Initierea unui apel video

1. Deschide chat-ul cu contactul.
2. Apasa pe simbolul de camera din bara de sus.
3. Imaginea ta video apare intr-o fereastra mica, iar imaginea
   interlocutorului tau in zona mare.

Poti schimba intre camera frontala si cea din spate in timpul convorbirii.

### Apeluri primite

Cand cineva te suna, apare o fereastra de notificare cu numele
apelantului. Poti:

- **Accepta** -- convorbirea incepe.
- **Respinge** -- apelantul este notificat.

Daca esti deja intr-o convorbire, un apel nou este respins automat.

### Apeluri de grup

Poti face si apeluri de grup, la care participa mai multe persoane
simultan. Apelul este organizat printr-un arbore de retransmitere
inteligent, astfel incat nu fiecare participant trebuie sa fie conectat
direct cu ceilalti. Toate convorbirile sunt criptate integral.

### Criptarea apelurilor

Toate apelurile sunt criptate cu chei unice, care exista doar pe durata
convorbirii. Dupa inchidere, aceste chei sunt sterse imediat. Nimeni nu
poate decripta ulterior o convorbire trecuta.

---

## 8. Calendar

Cleona include un calendar integrat, care functioneaza criptat si complet
descentralizat -- fara niciun serviciu cloud.

### Vizualizari

Calendarul ofera cinci vizualizari: Zi, Saptamana, Luna, An si o
vizualizare de tip Sarcini. Comuti intre ele prin tab-urile din partea de
sus a ecranului calendarului.

### Crearea evenimentelor

Apasa pe un interval orar sau foloseste butonul de adaugare pentru a crea
un eveniment nou. Poti introduce titlu, data, ora, locul si notite.
Evenimentele sunt stocate criptat pe dispozitivul tau.

### Evenimente recurente

Evenimentele se pot repeta zilnic, saptamanal, lunar sau anual. Poti
personaliza tiparul (de exemplu, in fiecare a doua marti, in prima zi a
fiecarei luni) si poti stabili o data de final sau un numar de repetari.

### Invitarea contactelor

La crearea sau editarea unui eveniment, poti invita contactele tale
Cleona. Ele primesc o invitatie de calendar criptata si pot raspunde cu
Da, Nu sau Poate. Modificarile evenimentului sunt trimise automat tuturor
invitatilor.

### Afisarea Liber/Ocupat

Poti impartasi disponibilitatea ta cu contactele fara sa dezvalui detalii
despre evenimente. Exista trei niveluri de confidentialitate: detalii
complete, doar intervale orare sau ascuns. Poti seta un mod implicit si
il poti suprascrie pentru fiecare contact in parte.

### Notificari de reamintire

Evenimentele pot avea reamintiri, care declanseaza o notificare de sistem
inainte de inceperea evenimentului. Poti amana reamintirile daca este
nevoie.

### Sincronizare externa a calendarului

Cleona se poate sincroniza cu servicii externe de calendar:

- **CalDAV** -- conecteaza-te la orice server compatibil CalDAV
  (Nextcloud, Radicale etc.).
- **Google Calendar** -- sincronizare prin Google Calendar API, cu
  autentificare sigura OAuth2.
- **Server CalDAV local** -- Cleona poate porni un server CalDAV local pe
  dispozitivul tau, astfel incat aplicatiile de calendar de pe desktop
  (Thunderbird, Outlook, Apple Calendar, Evolution) sa se poata sincroniza
  cu calendarul tau Cleona.
- **Calendarul de sistem Android** -- evenimentele din Cleona pot fi
  transferate in aplicatia de calendar integrata a dispozitivului tau
  Android.
- **Fisiere ICS** -- importa si exporta evenimente in formatul standard
  iCalendar.

### Export PDF

Poti tipari sau exporta orice vizualizare a calendarului (Zi, Saptamana,
Luna, An) ca document PDF.

---

## 9. Sondaje

Poti crea sondaje in orice chat sau grup, pentru a aduna opinii sau pentru
a planifica intalniri.

### Tipuri de sondaje

Cleona suporta cinci tipuri de sondaje:

- **Alegere unica** -- participantii aleg o singura optiune.
- **Alegere multipla** -- participantii pot alege mai multe optiuni.
- **Sondaj de data** -- gaseste o data potrivita pentru toata lumea.
  Fiecare participant marcheaza datele ca disponibile, posibile sau
  indisponibile.
- **Scala** -- evalueaza ceva pe o scala numerica (de exemplu de la 1 la
  5).
- **Text liber** -- participantii scriu propriul raspuns.

### Crearea unui sondaj

Deschide un chat si apasa pe simbolul de sondaj (sau foloseste meniul de
atasamente). Alege tipul sondajului, formuleaza intrebarea si optiunile si
trimite sondajul. Acesta apare ca un mesaj in chat.

### Votarea

Apasa pe un sondaj pentru a-ti da votul. Iti poti schimba sau retrage
votul oricand.

### Vot anonim

Sondajele pot fi configurate pentru vot anonim. Daca este activat,
voturile sunt anonime din punct de vedere criptografic -- nimeni, nici
macar creatorul sondajului, nu poate vedea cine a votat pentru ce.
Numarul de voturi ramane insa vizibil.

### De la sondaj de data la calendar

Cand un sondaj de data s-a incheiat, data castigatoare poate fi
transformata direct intr-un eveniment din calendar cu o singura atingere.

---

## 10. Identitati multiple

### De ce mai multe identitati?

Imagineaza-ti ca vrei sa separi viata profesionala de cea privata --
similar cu doua numere de telefon diferite, dar fara un al doilea telefon.
In Cleona poti folosi mai multe identitati pe un singur dispozitiv. Fiecare
identitate are propriul nume, propria imagine de profil, propriile
contacte si propriile conversatii.

### Crearea unei identitati noi

1. In bara de sus vezi identitatea ta curenta ca un tab.
2. Apasa pe semnul plus (+) din dreapta tab-urilor de identitate.
3. Introdu un nume pentru noua identitate.
4. Gata -- noua identitate este activa imediat.

### Comutarea intre identitati

Apasa pur si simplu pe tab-ul de identitate din bara de sus. Comutarea
este instantanee -- fara timp de asteptare, fara reincarcare.

### Toate ruleaza simultan

Un aspect important: toate identitatile tale sunt active simultan. Chiar
daca esti afisat momentan ca "Profesional", identitatea ta "Personal"
continua sa primeasca mesaje. Nu ratezi nimic, indiferent de identitatea
pe care ai selectat-o in acel moment.

### Pagina de detalii a identitatii

Cand apesi pe tab-ul identitatii tale active, se deschide pagina de
detalii. Aici poti:

- Sa iti afisezi QR-Code-ul pentru contacte.
- Sa iti schimbi sau sa iti elimini imaginea de profil.
- Sa adaugi o descriere de profil.
- Sa iti schimbi numele afisat.
- Sa alegi un design (skin) pentru aceasta identitate.
- Sa stergi identitatea, daca nu mai ai nevoie de ea.

### Stergerea unei identitati

Cand stergi o identitate, contactele tale sunt notificate despre acest
lucru. Identitatea si toate datele asociate sunt eliminate de pe
dispozitivul tau. Acest proces este ireversibil.

---

## 11. Multi-Device

### Folosirea Cleona pe mai multe dispozitive

Poti folosi aceeasi identitate pe pana la 5 dispozitive simultan. Un
dispozitiv este cel primar (el detine Seed-Phrase-ul), iar celelalte
dispozitive sunt asociate cu acesta.

### Asocierea unui dispozitiv nou

1. Deschide setarile pe dispozitivul tau primar.
2. Mergi la "Dispozitive asociate".
3. Alege "Asociaza dispozitiv nou".
4. Instaleaza Cleona pe noul dispozitiv si alege la pornire "Asociaza cu
   dispozitiv existent".
5. Scaneaza codul QR de asociere afisat pe dispozitivul tau primar sau
   foloseste link-ul de asociere.

Dispozitivul asociat primeste un certificat de delegare de la dispozitivul
primar. Mesajele trimise de pe un dispozitiv asociat sunt semnate
criptografic cu o cheie delegata, astfel incat contactele pot verifica ca
mesajul provine intr-adevar de la identitatea ta.

### Cum functioneaza

- Dispozitivul primar detine Seed-Phrase-ul tau si cheile master.
- Dispozitivele asociate primesc chei de semnatura derivate si un
  certificat de delegare -- nu primesc niciodata Seed-Phrase-ul in sine.
- Toate dispozitivele impartasesc aceeasi identitate si aceleasi contacte.
  Mesajele ajung pe toate dispozitivele.
- Certificatele de delegare sunt reinnoite automat inainte de expirare.

### Gestionarea dispozitivelor

Deschide setarile si mergi la "Dispozitive asociate" pentru a vedea toate
dispozitivele tale asociate, statusul lor si ultima activitate. Poti
revoca un dispozitiv asociat oricand, daca acesta se pierde sau este
furat.

### Rotatia de urgenta a cheilor

Daca banuiesti ca un dispozitiv a fost compromis, poti declansa o rotatie
de urgenta a cheilor. In acest proces sunt generate chei noi, iar rotatia
trebuie confirmata de o majoritate a celorlalte dispozitive ale tale.
Acest lucru impiedica un singur dispozitiv furat sa roteasca cheile in mod
unilateral.

---

## 12. Recuperare

### Folosirea Seed-Phrase-ului

Daca iti pierzi dispozitivul sau configurezi unul nou:

1. Instaleaza Cleona pe noul dispozitiv.
2. Alege la pornire "Recupereaza".
3. Introdu cele 24 de cuvinte ale tale.
4. Cleona iti recupereaza identitatea si contacteaza automat contactele
   tale anterioare.
5. Contactele tale raspund cu datele tale de contact, apartenentele la
   grupuri si istoricul mesajelor.

Recuperarea are loc in trei etape:
- Mai intai revin contactele si grupurile tale.
- Apoi ultimele 50 de mesaje din fiecare conversatie.
- La final, istoricul complet al mesajelor.

Este suficient ca un singur contact de-al tau sa fie online pentru ca
recuperarea sa functioneze.

### Guardian Recovery (persoane de incredere)

Poti desemna pana la cinci persoane de incredere ca "Guardieni". In acest
proces, cheia ta de recuperare este impartita in cinci parti, dintre care
fiecare Guardian primeste una. Pentru a-ti recupera identitatea, sunt
suficiente trei din cele cinci parti.

Asta inseamna ca, chiar daca ti-ai pierdut Seed-Phrase-ul, trei dintre
Guardienii tai pot recupera impreuna contul tau. Niciun Guardian singur nu
poate accesa datele tale -- sunt necesari intotdeauna cel putin trei.

Asa configurezi Guardieni:
1. Deschide setarile.
2. Mergi la "Securitate".
3. Alege "Guardian Recovery".
4. Selecteaza cinci contacte de incredere.

### De ce contactele tale sunt backup-ul tau

In mesagerii traditionali, datele tale se afla pe serverele furnizorului.
La Cleona nu exista niciun server -- dar contactele tale preiau acest rol.
Cand trimiti un mesaj, contactele comune stocheaza o copie criptata pentru
cazul in care destinatarul este offline in acel moment. La o recuperare,
contactele tale iti returneaza datele.

Asta inseamna: cu cat ai mai multe contacte active, cu atat mai fiabil
este backup-ul tau. Un singur contact care este online in mod regulat este
suficient pentru o recuperare reusita.

---

## 13. Setari

Ajungi la setari prin simbolul de rotita din coltul din dreapta sus.

### Notificari si tonuri de apel

- Alege dintre sase tonuri de apel diferite pentru apelurile primite.
- Seteaza un ton de mesaj.
- Pe dispozitivele Android poti activa sau dezactiva suplimentar
  vibratia.

### Design-uri (Skins)

Cleona ofera zece design-uri diferite: Teal, Ocean, Sunset, Forest,
Amethyst, Fire, Storm, Slate, Gold si Contrast. Design-ul Contrast
indeplineste cel mai inalt nivel de accesibilitate (WCAG AAA) si este
deosebit de usor de citit pentru persoanele cu vedere limitata.

Fiecare identitate poate avea propriul design. Schimbi design-ul in
pagina de detalii a identitatii (apasa pe tab-ul identitatii active).

Suplimentar, in setari, la "Aspect", poti comuta intre tema deschisa,
intunecata si tema sistemului.

### Schimbarea limbii

Cleona este disponibil in 33 de limbi, inclusiv limbi scrise de la dreapta
la stanga (de exemplu araba, ebraica). Schimba limba in setari, la
"Limba".

### Limita de stocare

Poti stabili cat spatiu de stocare are voie sa foloseasca Cleona pe
dispozitivul tau (intre 100 MB si 2 GB). Cand limita este atinsa, media
mai veche este mutata automat in arhiva sau stearsa -- mesajele text
raman intotdeauna pastrate.

### Arhivare media

Daca ai acasa un spatiu de stocare in retea (NAS) sau un folder partajat,
Cleona iti poate arhiva automat media acolo. Sunt suportate SMB, SFTP,
FTPS si WebDAV.

Iata cum functioneaza stocarea esalonata:
- Primele 30 de zile: totul ramane pe dispozitivul tau.
- Dupa 30 de zile: o imagine de previzualizare ramane pe dispozitiv,
  originalul este arhivat.
- Dupa 90 de zile: doar o mica imagine de previzualizare mai ramane pe
  dispozitiv.
- Dupa un an: ramane doar un substituent, originalul se afla in siguranta
  in arhiva.

Poti apasa oricand pe un fisier media arhivat pentru a-l recupera --
cu conditia sa fii conectat la reteaua ta de acasa. Media deosebit de
importanta poate fi fixata, astfel incat sa nu fie niciodata mutata in
arhiva.

### Transcriere pentru mesajele vocale

Daca este activata, mesajele tale vocale sunt convertite in text local pe
dispozitivul tau (cu modelul open-source Whisper). Textul transcris este
trimis interlocutorului tau impreuna cu inregistrarea. Transcrierea are
loc complet pe dispozitivul tau -- niciun fel de date nu ajung la
servicii externe.

### Descarcare automata

Poti stabili de la ce dimensiune media va fi descarcata automat. Astfel
poti, de exemplu, sa lasi imaginile sa se incarce automat, dar sa decizi
manual pentru videoclipurile mari.

### Dispozitive asociate

Gestioneaza dispozitivele tale asociate in aceasta sectiune a setarilor.
Vezi capitolul Multi-Device pentru detalii.

---

## 14. Securitate

### Ce inseamna criptarea post-cuantica?

Criptarea de astazi se bazeaza pe probleme matematice extrem de greu de
rezolvat pentru calculatoarele normale. Calculatoarele cuantice ar putea
rezolva unele dintre aceste probleme rapid, in viitor. Criptarea
post-cuantica foloseste metode suplimentare care rezista si
calculatoarelor cuantice.

Cleona combina ambele abordari: criptarea clasica pentru fiabilitate si
metodele post-cuantice pentru siguranta pe termen lung. Astfel esti
protejat simultan impotriva amenintarilor de astazi si a celor viitoare.

Pentru fiecare mesaj in parte este generata o cheie proprie. Chiar daca un
atacator ar sparge cheia unui mesaj, nu ar putea citi cu ea niciun alt
mesaj.

### De ce lipsa unui server este mai sigura

La mesagerii traditionali, mesajele tale trec prin serverele
furnizorului. Chiar daca acolo sunt criptate, furnizorul are acces la
metadate (cine comunica cu cine, cand, cat de des, de unde) si trebuie
uneori sa le predea in urma unui ordin judecatoresc.

La Cleona nu exista un astfel de punct central. Mesajele tale calatoresc
direct de la dispozitiv la dispozitiv. Nu exista niciun loc unde toate
metadatele se aduna. Nimeni nu poate reconstitui comportamentul tau de
comunicare pornind de la un singur punct de date.

### Ce se intampla cand esti offline?

Cand trimiti un mesaj, iar destinatarul este offline:

1. Cleona incearca mai intai sa livreze mesajul direct.
2. Daca nu functioneaza, acesta este retransmis prin contacte comune.
3. In acelasi timp, mesajul este impartit in bucati criptate si distribuit
   pe mai multi noduri din retea (asemenea unui puzzle format din 10
   piese, dintre care 7 sunt suficiente pentru a reconstitui imaginea).
4. Mesajul este pastrat pana la 7 zile.

De indata ce destinatarul revine online, mesajele sunt livrate. Primesti
o confirmare cand mesajul tau a ajuns.

### Anti-cenzura

Daca reteaua ta blocheaza metoda standard de conectare (UDP), Cleona
comuta automat pe o transmisie alternativa (TLS), mai greu de detectat si
de blocat. Acest lucru se intampla transparent -- nu trebuie sa configurezi
nimic.

### Stocarea sigura a cheilor

Pe platformele suportate, Cleona iti stocheaza cheile de criptare in
inelul de chei securizat al sistemului de operare (Android Keystore, iOS
Keychain, macOS Keychain). Acolo unde este disponibila, aceasta ofera
protectie bazata pe hardware pentru cheile tale.

### Criptarea bazei de date

Toate mesajele, contactele si setarile tale sunt stocate criptat pe
dispozitivul tau. Chiar daca cineva ar avea acces la sistemul tau de
fisiere, nu ar putea citi nimic fara cheia ta criptografica. Aceasta cheie
este derivata din identitatea ta si exista doar pe dispozitivul tau.

### Retea inchisa

Cleona functioneaza ca o retea inchisa. Fiecare pachet de retea este
autentificat, astfel incat doar dispozitivele Cleona legitime pot
participa. Acest lucru impiedica persoanele din afara sa introduca mesaje
falsificate sau sa intercepteze traficul de retea.

---

## 15. Actualizari software

### Cum primesc actualizari?

Cleona poate fi actualizat in mai multe moduri. Scopul este ca tu sa poti
primi actualizari chiar si atunci cand anumite canale de distributie sunt
indisponibile sau blocate:

1. **App Store / Play Store:** daca ai instalat Cleona printr-un App
   Store, primesti actualizari ca de obicei prin acel Store.
2. **GitHub Releases:** pe pagina GitHub a proiectului gasesti pachete de
   instalare semnate pentru toate platformele.
3. **Actualizari in retea (In-Network):** daca un alt utilizator Cleona
   din reteaua ta are deja cea mai noua versiune, Cleona poate obtine
   actualizarea direct prin reteaua P2P -- fara un server extern. In acest
   proces, noua versiune este descompusa in fragmente cu corectie de
   erori si distribuita pe mai multi noduri. Dispozitivul tau colecteaza
   suficiente fragmente si reasambleaza actualizarea. Autenticitatea este
   verificata printr-o semnatura Ed25519 a dezvoltatorului.
4. **Link-uri de invitatie:** poti crea link-uri de invitatie care contin
   tot ce are nevoie un utilizator nou pentru a instala Cleona si a se
   conecta la retea.
5. **Transfer fizic:** in medii fara internet, poti transmite Cleona altor
   persoane printr-un stick USB sau in reteaua locala.

### Notificarea de actualizare

Cand este disponibila o noua actualizare, Cleona iti arata o notificare
pe ecranul principal. Daca actualizarea este disponibila si prin retea
(In-Network-Update), ai posibilitatea sa o descarci direct din retea.

### Distributia binara

Implicit, dispozitivul tau ajuta la distribuirea actualizarilor catre alti
utilizatori din retea. Daca nu doresti acest lucru, poti dezactiva aceasta
functie in setari, la "Retea". Utilizarea de stocare pentru fragmentele de
actualizare este limitata (5 MB pe dispozitivele mobile, 20 MB pe
dispozitivele desktop) si este curatata periodic.

### Verificarea semnaturii

Fiecare actualizare este semnata criptografic. Cleona verifica automat
semnatura inainte de instalarea unei actualizari. Astfel se asigura ca
sunt acceptate doar actualizari de la dezvoltatorul oficial -- chiar daca
actualizarea a fost obtinuta prin reteaua P2P.

---

## 16. Intrebari frecvente

### "Pot folosi Cleona fara internet?"

Nu, Cleona are nevoie de o conexiune de retea pentru a trimite si primi
mesaje. Totusi, nu trebuie sa fii online in acelasi timp cu interlocutorul
tau: mesajele trimise in timp ce destinatarul este offline sunt stocate
temporar si livrate automat de indata ce ambele parti sunt din nou
conectate. In reteaua locala (de exemplu in acelasi WLAN) puteti comunica
si complet fara acces la internet.

### "Ce se intampla daca imi pierd Seed-Phrase-ul?"

Daca ai configurat Guardieni, trei din cinci persoane de incredere pot
recupera impreuna accesul tau. Fara Guardieni si fara Seed-Phrase, din
pacate nu exista nicio cale de a-ti recupera identitatea. De aceea este
atat de important sa pastrezi cele 24 de cuvinte in siguranta.

### "Poate cineva sa imi citeasca mesajele?"

Nu. Fiecare mesaj este criptat cu o cheie unica, valabila doar pentru
acel mesaj. Doar tu si interlocutorul tau puteti decripta mesajul. Nu
exista niciun server central, nicio cheie generala si niciun acces pentru
dezvoltator. Chiar daca un dispozitiv retransmite mesajul pe parcursul
transportului, acesta vede doar date criptate fara sens.

### "De ce nu am nevoie de un numar de telefon?"

Pentru ca identitatea ta este pur criptografica. In loc de un numar de
telefon sau o adresa de e-mail legata de numele tau real, te identifica o
pereche de chei generata pe dispozitivul tau. Adaugi contacte prin
QR-Code, NFC sau link -- nu printr-o agenda de telefoane. Asta inseamna
mai multa confidentialitate, pentru ca contul tau de mesagerie nu este
legat de identitatea ta reala.

### "Cum gasesc oameni pe Cleona?"

Cleona nu are, in mod deliberat, cautare de contacte dupa numar de telefon
sau nume -- asta ar fi o problema de confidentialitate. In schimb, faci
schimb de date de contact direct: prin QR-Code, NFC, link cleona:// sau in
canale publice. Este ca un schimb de carti de vizita, in loc sa cauti
intr-o agenda telefonica.

### "Functioneaza Cleona si in strainatate?"

Da. Atata timp cat ai o conexiune la internet, Cleona functioneaza oriunde
in lume. Pentru ca nu exista niciun server central, serviciul nu poate fi
blocat nici pentru anumite tari. Cleona dispune in plus de un mecanism
anti-cenzura: daca conexiunea normala (UDP) este blocata, Cleona comuta
automat pe o transmisie alternativa (TLS), mai greu de detectat si de
blocat.

### "Este Cleona gratuit?"

Da. Cleona poate fi folosit gratuit si fara reclame. Pentru ca nu exista
niciun server central, nu exista nici costuri de server pentru
functionare. In aplicatie gasesti la "Donatie" posibilitatea de a sustine
voluntar dezvoltarea.

### "Mesajul meu are un simbol de ceas -- ce inseamna asta?"

Asta inseamna ca mesajul inca nu a fost livrat. Interlocutorul tau este
probabil offline chiar acum. De indata ce mesajul este livrat, simbolul se
schimba. Mesajele sunt pastrate pana la 7 zile pentru livrare.

### "Pot trece de la WhatsApp la Cleona?"

Da, dar nu iti poti transfera conversatiile din WhatsApp. Cleona si
WhatsApp sunt sisteme fundamental diferite. Trebuie sa iti adaugi
contactele individual in Cleona. Cel mai simplu este sa postezi link-ul
tau cleona:// intr-un grup de WhatsApp si sa ii rogi pe ceilalti sa te
adauge acolo.

### "Pot folosi Cleona pe mai multe dispozitive simultan?"

Da. Poti asocia pana la 5 dispozitive cu aceeasi identitate. Un dispozitiv
este cel primar (el detine Seed-Phrase-ul), iar celelalte dispozitive sunt
asociate printr-un proces sigur de asociere. Toate dispozitivele
impartasesc aceeasi identitate, aceleasi contacte si conversatii. Vezi
capitolul Multi-Device pentru detalii.

### "Cum primesc actualizari daca App Store-ul este blocat?"

Cleona poate obtine actualizari direct prin reteaua P2P, fara sa depinda
de un App Store, un website sau un server de descarcare. Daca un alt
utilizator din retea are cea mai noua versiune, dispozitivul tau poate
incarca actualizarea de acolo. Autenticitatea este verificata printr-o
semnatura digitala a dezvoltatorului. Alternativ, un contact iti poate
trimite aplicatia printr-un link de invitatie sau un stick USB. Mai multe
detalii in capitolul "Actualizari software".

---

## Ajutor si contact

Daca ai intrebari sau intampini o problema, gasesti informatii actuale pe
website-ul Cleona si pe GitHub. Pentru ca Cleona este un proiect
descentralizat, nu exista un suport clasic pentru clienti -- dar exista o
comunitate activa, bucuroasa sa ajute.

---

*Acest manual descrie Cleona Chat versiunea 3.1.125. Anumite functii se
pot schimba sau extinde in versiunile viitoare.*

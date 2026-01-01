# Cleona Chat -- Manual de utilizare

Versiunea 4.2 | Actualizat noiembrie 2026

---

## Cuprins

1. [Ce este Cleona Chat?](#1-ce-este-cleona-chat)
2. [Primii pași](#2-primii-pași)
3. [Contacte](#3-contacte)
4. [Mesaje](#4-mesaje)
5. [Grupuri](#5-grupuri)
6. [Canale publice](#6-canale-publice)
7. [Apeluri](#7-apeluri)
8. [Calendar](#8-calendar)
9. [Sondaje](#9-sondaje)
10. [Mai multe identități](#10-mai-multe-identități)
11. [Mai multe dispozitive](#11-mai-multe-dispozitive)
12. [Recuperare](#12-recuperare)
13. [Setări](#13-setări)
14. [Securitate](#14-securitate)
15. [Actualizări software](#15-actualizări-software)
16. [Întrebări frecvente](#16-întrebări-frecvente)

---

## 1. Ce este Cleona Chat?

### Aplicația ta de mesagerie, datele tale

Cleona Chat este o aplicație de mesagerie care funcționează complet fără un server central. Mesajele tale călătoresc de pe dispozitivul tău la dispozitivul interlocutorului -- fără ocol prin sediul unei firme, fără cloud, fără centru de date. Unde, pe traseu, un alt dispozitiv ajută, el doar retransmite pachete criptate. Nicio companie nu poate să-ți citească, să-ți stocheze sau să-ți transmită mai departe mesajele, pur și simplu pentru că nicio companie nu se află la mijloc.

### Fără cont, fără număr de telefon

La Cleona nu ai nevoie nici de număr de telefon, nici de adresă de e-mail pentru a te înregistra. Identitatea ta constă într-o pereche de chei criptografice, generată automat pe dispozitivul tău la prima pornire. Asta înseamnă: nimeni nu te poate găsi prin numărul tău de telefon sau adresa de e-mail, cu excepția cazului în care dai tu însuți/însăți mai departe datele tale de contact.

### Criptare rezistentă la viitor

Cleona folosește așa-numita criptare post-cuantum. Asta înseamnă: nici măcar viitoarele calculatoare cuantice nu ar putea să-ți spargă mesajele. Nu trebuie să înțelegi detaliile -- important este doar că informațiile tale sunt protejate cât mai bine, conform stadiului actual al tehnologiei.

### Cum funcționează fără server?

Rețeaua Cleona este formată doar din dispozitivele utilizatorilor săi. Fiecare dispozitiv este un nod, niciun nod nu este mai important decât altul, și fiecare își cunoaște doar vecinii. Patru lucruri fac această rețea deosebită:

- **Niciun punct fix.** În aplicație nu figurează nicio adresă de server, iar rețeaua nu depinde de niciun nod unic. Nu există nimic ce s-ar putea opri pentru a opri Cleona.
- **Instant.** Mesajul tău pornește în momentul în care îl trimiți. Nu așteaptă niciun tact și nimic altceva.
- **Camuflaj pe lângă.** Dispozitivul tău trimite în mod constant mici pachete de camuflaj, ca să nu se poată vedea din afară când scrii cu adevărat. Niciun mesaj nu depinde de ele -- camuflajul rulează doar pe lângă.
- **Coduri în loc de nume.** Cine retransmite un mesaj vede doar un cod care se schimbă în fiecare zi. În mod normal, niciunul dintre ei nu cunoaște expeditorul și destinatarul în același timp; excepțiile sunt în capitolul 14.

**Trei rute, toate deodată.** Când trimiți un mesaj, Cleona nu încearcă o rută după alta, ci toate cele potrivite deodată. De îndată ce interlocutorul confirmă primirea, celelalte sunt întrerupte.

1. **În aceeași rețea:** Dacă sunteți în același Wi-Fi, mesajul merge direct.
2. **Peste vecinii fixi:** Pe internet, dispozitivul tău predă mesajul vecinului său fix. Acesta îl retransmite către vecinii fixi ai interlocutorului (până la trei deodată), iar unul dintre ei îl livrează.
3. **Căsuță poștală:** Dacă interlocutorul este offline, Cleona depune mesajul criptat la trei vecini. Acolo rămâne până la 7 zile. Când interlocutorul revine online, îl ridică.

**Cum intri în rețea?** În aplicație nu figurează nicio adresă de server. Punctul tău de intrare îl primești de la primul tău contact: invitația lui conține adresele prin care dispozitivul tău își găsește primii vecini. În același Wi-Fi, dispozitivele Cleona se găsesc și singure. De atunci, dispozitivul tău află cu fiecare vecin și alți vecini noi.

### Platforme

Cleona este disponibil pentru Android, iOS, macOS, Linux și Windows. Pe calculatoare și pe Android, mesajele și apelurile sosesc în câteva secunde. Pe iPhone asta se aplică cât timp aplicația este deschisă. Când nu este, iOS o trezește doar din când în când, pe scurt; când anume, decide iOS. Cleona colectează atunci tot ce a fost păstrat pentru tine și arată o notificare cu un număr pe pictograma aplicației. Apelurile nu ajung pe un iPhone a cărui aplicație nu este deschisă. Aceasta este o regulă a Apple, nu o defecțiune în Cleona.

---

## 2. Primii pași

### Instalarea aplicației

**Android:**
1. Descarcă fișierul APK de pe site-ul Cleona sau de pe GitHub Releases.
2. Deschide fișierul pe telefon. Dacă e nevoie, permite instalarea din surse necunoscute (Android te întreabă automat).
3. Atinge „Instalare" și așteaptă până când instalarea se termină.

**iOS:**
1. Deschide linkul de invitație TestFlight pe iPhone-ul tău.
2. Atinge „Instalare". TestFlight este modul oficial al Apple de a distribui aplicații beta.
3. După instalare, găsești Cleona pe ecranul principal.

**macOS:**
1. Descarcă fișierul DMG de pe site-ul Cleona sau de pe GitHub Releases.
2. Deschide DMG-ul și trage Cleona în folderul Aplicații.
3. La prima pornire, macOS te poate întreba dacă vrei să deschizi o aplicație de la un dezvoltator identificat -- confirmă.

**Linux (Ubuntu/Debian):**
1. Descarcă fișierul .deb de pe site-ul Cleona sau de pe GitHub Releases.
2. Instalează cu dublu-clic sau în terminal: `sudo dpkg -i cleona-chat-beta_VERSION_amd64.deb`
3. Pornește Cleona din meniul de aplicații sau în terminal cu `cleona-chat-beta`.

**Linux (Fedora/openSUSE):**
1. Descarcă fișierul .rpm de pe site-ul Cleona sau de pe GitHub Releases.
2. Instalează cu: `sudo dnf install cleona-chat-beta-VERSION-1.x86_64.rpm`
3. Pornește Cleona din meniul de aplicații sau în terminal cu `cleona-chat-beta`.

**Linux (toate distribuțiile -- AppImage):**
1. Descarcă fișierul .AppImage de pe site-ul Cleona sau de pe GitHub Releases.
2. Fă fișierul executabil: clic dreapta, proprietăți, executabil, sau în terminal: `chmod +x cleona-chat-beta-VERSION-x86_64.AppImage`
3. Pornește cu dublu-clic sau în terminal: `./cleona-chat-beta-VERSION-x86_64.AppImage`

Numele pachetelor sunt cele pentru beta, care este momentan singura versiune
publicată; ele se numesc `cleona-chat-beta`.

**Windows:**
1. Descarcă programul de instalare de pe site-ul Cleona sau de pe GitHub Releases.
2. Rulează fișierul de instalare și urmează instrucțiunile.
3. Pornește Cleona din meniul Start sau din comanda rapidă de pe desktop.

### Crearea unei identități

La prima pornire, Cleona creează automat o identitate nouă pentru tine. Îți poți da un nume afișat -- acesta este numele pe care îl văd contactele tale. Acest nume se poate schimba oricând.

### Notează fraza-seed -- cel mai important lucru din toate

După crearea identității, Cleona îți arată 24 de cuvinte. Aceasta este **fraza-seed** a ta -- cheia ta personală de recuperare.

**Notează aceste 24 de cuvinte pe hârtie și păstrează-le în siguranță.**

De ce este asta atât de important?

- Dacă telefonul tău se strică, se pierde sau îți este furat, poți restabili întreaga ta identitate pe un dispozitiv nou cu aceste 24 de cuvinte.
- Fără fraza-seed nu există cale de întoarcere. Nu există buton „am uitat parola" și niciun suport care ți-ar putea returna contul -- pentru că nu există deloc un cont pe un server. Nici măcar contactele tale nu îți pot restabili identitatea, indiferent câte sunt. Un al doilea dispozitiv cu aceeași identitate vine într-o versiune ulterioară (vezi capitolul 11).
- Nu da fraza-seed niciodată altora. Cine cunoaște aceste cuvinte se poate da drept tine.

Cele 24 de cuvinte le găsești mai târziu în setări, la „Backup" ->
„Arată fraza de recuperare", în caz că vrei să le citești din nou. Pe
Android confirmi pentru asta cu blocarea ecranului tău.

### Adăugarea primului contact

Ca să comunici cu cineva, trebuie mai întâi să adaugi persoana drept contact. Pentru asta există mai multe căi -- toate sunt explicate în secțiunea următoare.

---

## 3. Contacte

### Invitația ta

La Cleona, contactele apar doar printr-o invitație. Invitația ta este acolo de la prima pornire -- chiar și fără internet și înainte ca dispozitivul tău să fi găsit măcar un vecin. O găsești pe pagina de detalii a identității (atinge propriul nume din bara de sus).

Invitația există în două forme care conțin exact același lucru:

- ca **cod QR**, când interlocutorul stă lângă tine, și
- ca **linie de text**, pe care o trimiți prin e-mail, SMS sau printr-o altă aplicație de mesagerie.

Invitația nu conține niciun număr de telefon și niciun nume dintr-un director. Ea conține cheile tale publice și adresele prin care interlocutorul te ajunge pe tine și pe vecinii tăi. Pentru cineva care tocmai și-a instalat Cleona, invitația ta este, prin urmare, și punctul de intrare în rețea.

### Scanarea codului QR (recomandat)

Când vă întâlniți în persoană:

1. Îi arăți interlocutorului codul QR al invitației tale.
2. Interlocutorul atinge butonul cu plus, alege „Scanează cod QR" și îndreaptă camera spre ecranul tău. Funcționează și cu webcam-ul unui calculator.
3. Cererea ajunge la tine și este **acceptată automat** -- pentru că tocmai ai arătat codul tu însuți/însăți.

Un cod QR este valabil o singură dată: prima cerere validă este acceptată, după aceea invitația este consumată. Codul QR este cea mai sigură metodă, pentru că, făcând asta, știți exact cu cine schimbați contactul.

### NFC (apropierea telefoanelor)

Când ambele dispozitive suportă NFC:

1. Deschideți pe ambele funcția de adăugare a contactelor.
2. Apropiați telefoanele spate în spate.
3. Invitația este transferată și acceptată automat.

NFC oferă, ca și codul QR, un nivel ridicat de siguranță, pentru că schimbul funcționează doar când stați fizic unul lângă celălalt.

### Trimiterea liniei de text

Când nu vă puteți întâlni:

1. Deschide invitația ta și copiază linia de text.
2. Trimite-o persoanei care trebuie să te adauge -- prin e-mail, SMS sau printr-o altă aplicație de mesagerie.
3. Cealaltă persoană lipește linia în Cleona, în dialogul de adăugare a contactelor.
4. Cererea apare la tine sub **„Cereri"**. Aici **nu** se acceptă automat: decizi tu, pentru că nu poți ști cine a mai citit linia pe traseu.

### Acceptarea cererilor de contact

O cerere primită nu creează încă un contact. Ea îți pune o întrebare și apare în tabul **„Cereri"**. Acolo vezi numele și nivelul de verificare și poți alege:

- **Acceptă** -- abia acum persoana devine contactul tău.
- **Refuză** -- cererea este eliminată.
- **Blochează** -- persoana nu îți mai poate trimite alte cereri.

### Nu folosi niciodată ca vecin fix

În meniul unui contact găsești comutatorul **„Nu folosi niciodată ca vecin fix"** (implicit: oprit). Când este pornit, acest contact nu mai retransmite mesaje pentru tine și, prin urmare, nici nu află când trimiți sau primești mesaje. Este gândit pentru cazul în care pericolul îți vine din propriul tău anturaj.

De la necunoscuți (nici contact, nici membru al unui grup comun), Cleona nu lasă să treacă nimic în afară de o astfel de cerere -- niciun mesaj, niciun apel, niciun fișier. Și chiar și cererea ajunge doar dacă expeditorul a rezolvat în prealabil o mică problemă de calcul. Asta face spamul în masă scump.

### Niveluri de verificare

Cleona îți arată cât de sigur este confirmată identitatea unui contact:

| Nivel | Semnificație |
|-------|-----------|
| Neverificat | Sunteți conectați, dar nimic nu confirmă că în spate este chiar persoana potrivită. |
| Văzut | Schimbul de chei a reușit; puteți comunica criptat. |
| Verificat | V-ați întâlnit în persoană și v-ați conectat prin scanare cu camera sau NFC. |
| De încredere | Ai marcat explicit acest contact drept demn de încredere. |

„Verificat" există doar pentru schimbul în persoană. O invitație venită printr-un chat sau prin e-mail nu atinge niciodată acest nivel -- chiar dacă conține aceleași date.

Dacă cheile unui contact se schimbă fără anunț, Cleona îl repoziționează la „Neverificat". Asta te protejează ca cineva să nu se dea drept contactul tău pe neobservate.

---
## 4. Mesaje

### Trimiterea și primirea textului

Pur și simplu tastează mesajul în câmpul de introducere de jos și apasă Enter sau butonul de trimitere. Mesajul tău este criptat automat înainte să părăsească dispozitivul.

Mesajele primite apar în istoricul chatului.

### Ce înseamnă semnele de pe mesajul tău

| Semn | Semnificație |
|---------|-----------|
| Ceas | Mesajul este creat, dar încă nicio rută nu l-a dus. |
| Un bif | Mesajul este pe drum. Asta valabil și cât timp așteaptă în căsuța poștală pentru interlocutor. |
| Două bifuri | Livrat: dispozitivul interlocutorului a confirmat primirea. |
| Semn de avertizare | Timp de 14 zile, nicio rută nu a dus mesajul. Atinge-l pentru a-l retrimite. |

**Offline nu este o eroare.** Dacă interlocutorul nu este disponibil, mesajul rămâne la un bif până este ridicat -- nu s-a pierdut. Dacă dispozitivul tău însuși nu are conexiune, mesajul rămâne la ceas și pornește de la sine de îndată ce există din nou o rută. Semnul de avertizare apare abia când mesajul nu a găsit timp de 14 zile nicio rută; atunci îl poți retrimite.

Aceasta se aplică și pentru un iPhone a cărui aplicație nu este deschisă: mesajul așteaptă în căsuța poștală până când iOS trezește aplicația pe scurt sau până când interlocutorul tău o deschide. Asta poate dura mai mult decât pe alte dispozitive.

Două bifuri există doar când destinatarul confirmă singur primirea. Această confirmare este criptată și semnată -- nimeni de pe traseu nu o poate falsifica ca să-ți simuleze o livrare.

### Trimiterea de imagini, videoclipuri și fișiere

Ai mai multe posibilități:

- **Iconița cu agrafă** din câmpul de introducere: atinge-o pentru a alege un fișier, o imagine sau un videoclip din galeria ta sau din sistemul tău de fișiere.
- **Drag and drop** (desktop): trage pur și simplu un fișier în fereastra de chat.
- **Lipire din clipboard** (desktop): copiază o imagine și lipește-o în chat.

Fișierele mici (sub 256 KB) călătoresc direct în mesaj. Fișierele mai mari sunt despicate în bucăți și prevăzute cu corecție de erori, astfel încât bucățile pierdute individual nu contează. Dacă sunteți amândoi online, ele sunt transmise în flux peste un vecin; altfel sunt depuse la dispozitive permanent accesibile, până când interlocutorul le ridică.

De la 256 KB în sus, Cleona te întreabă pentru fiecare fișier înainte de a fi trimis: un fișier mare nu poate lua ruta mesajelor tale. Conținutul lui rămâne criptat, iar interlocutorul nu află adresa ta de internet. Dar transferul este vizibil din afară ca eveniment, iar un dispozitiv străin care îl retransmite sau îl păstrează vede cine îl încarcă și cine îl ridică. Consimțământul tău este valabil doar pentru acest singur fișier.

### Mesaje vocale

1. Ține apăsat butonul microfon din câmpul de introducere.
2. Roște mesajul tău.
3. Eliberează butonul pentru a trimite mesajul.

Dacă pe dispozitivul tău este activată recunoașterea vorbirii (vezi setări), mesajul tău vocal este transcris automat în text. Interlocutorul vede atunci atât înregistrarea, cât și textul transcris.

### Răspunsul la mesaje (citat)

Pentru a răspunde la un anumit mesaj:

1. Deschide meniul cu trei puncte de lângă mesaj.
2. Alege „Răspunde".
3. Deasupra câmpului de introducere apare un banner cu mesajul citat.
4. Scrie răspunsul tău și trimite-l.

Mesajul citat este afișat în răspunsul tău, astfel încât referința este clară.

### Editarea și ștergerea mesajelor

- **Editare:** meniul cu trei puncte al mesajului, apoi „Editează". Modifică textul și trimite-l din nou. Interlocutorul vede că mesajul a fost editat. Editarea este posibilă în decurs de 15 minute de la trimitere.
- **Ștergere:** meniul cu trei puncte al mesajului, apoi „Șterge". Mesajul este eliminat la tine și la interlocutor. Îți poți șterge propriile mesaje oricând -- nu există o fereastră de timp pentru ștergere.

### Reacții cu emoji

În loc să scrii un răspuns, poți reacționa la un mesaj cu un emoji:

1. Deschide meniul cu trei puncte sau ține mesajul apăsat mult timp.
2. Alege un emoji din selecția rapidă sau deschide selectorul de emoji pentru selecția completă.
3. Reacția ta apare sub mesaj.

### Copierea textului

Prin meniul cu trei puncte al unui mesaj poți copia textul mesajului în clipboard.

### Căutarea mesajelor

În partea de sus a ferestrei de chat găsești funcția de căutare. Introdu un termen de căutare, iar Cleona îți arată toate potrivirile din chatul curent. Cu tastele săgeată poți sări înainte și înapoi între potriviri.

Pe pagina de start există suplimentar un filtru de căutare peste toate taburile, cu care poți căuta în toate conversațiile după un termen.

### Previzualizarea linkurilor

Când trimiți un link, Cleona generează automat o previzualizare (titlu, descriere, imagine de previzualizare). Această previzualizare este creată de dispozitivul tău și trimisă împreună -- interlocutorul nu trebuie să stabilească o conexiune la site-ul legat.

Ce face o atingere pe un link primit o stabilești în setări, la „Deschidere linkuri": „Normal", „Preferă o fereastră privată" (unde dispozitivul nu poate deschide o fereastră privată, linkul se deschide normal) sau „Întreabă de fiecare dată".

---

## 5. Grupuri

### Crearea unui grup

1. Treci la tabul „Grupuri".
2. Atinge butonul cu plus.
3. Dă grupului un nume.
4. Selectează contactele pe care vrei să le inviți.
5. Atinge „Creează".

Contactele invitate primesc o notificare și pot adera la grup.

### Cum sunt protejate mesajele de grup

Într-un grup cu până la 16 membri, Cleona trimite fiecare mesaj fiecărui membru individual -- criptat doar pentru acel membru, ca și cum ai fi scris fiecăruia un mesaj separat. Bifurile de pe un mesaj de grup arată starea membrului pentru care a avansat cel mai puțin.

Dacă grupul crește peste 16 membri, el folosește o cheie comună. Ea se schimbă în fiecare zi și se trage din nou când un membru iese sau este eliminat; un membru nou citește abia de la intrarea lui. Acolo bifurile nu mai arată starea fiecărui membru, ci că mesajul este depus în rețea. Dacă grupul scade la 12 membri sau mai puțin, revine la trimiterea individuală.

### Imagini în grupuri și canale

În setările unui grup sau ale unui canal stabilești cu „Încarcă mereu imaginile" dacă imaginile se încarcă imediat sau abia când atingi una.

### Invitarea membrilor

Chiar și după creare, poți invita și alte contacte:

1. Deschide informațiile grupului (meniul cu trei puncte în prezentarea generală a grupurilor sau bara de sus în chatul de grup).
2. Atinge „Invită".
3. Selectează contactele pe care vrei să le adaugi.

### Roluri

Fiecare grup are trei roluri:

- **Proprietar (Owner):** Are controlul complet. Poate adăuga și elimina membri, numi administratori și gestiona grupul. Proprietarul își poate transfera și statutul către alt membru.
- **Admin:** Poate elimina membri și ajuta la administrare.
- **Membru:** Poate citi și scrie mesaje.

### Părăsirea unui grup

1. Deschide meniul cu trei puncte în prezentarea generală a grupurilor.
2. Alege „Părăsește".
3. Confirmă decizia ta.

Când părăsești un grup, mesajele tale anterioare rămân vizibile pentru ceilalți membri.

---

## 6. Canale publice

### Ce sunt canalele?

Canalele sunt forumuri publice de discuție în interiorul rețelei Cleona. Spre deosebire de grupuri, aici oricine poate citi fără să fie invitat. Doar proprietarul și administratorii pot publica contribuții -- abonații doar citesc.

### Găsirea și aderarea la canale

1. Treci la tabul „Canale".
2. Deschide fila „Căutare".
3. Caută canalele disponibile după nume sau temă.
4. Atinge un canal și apoi „Abonează-te".

Canalele pot fi filtrate după limbă. Unele canale sunt marcate ca „Nesigure pentru minori" -- acestea sunt vizibile doar dacă ai confirmat în profilul tău că ai peste 18 ani.

### Crearea propriului canal

1. Treci la tabul „Canale".
2. Atinge butonul cu plus.
3. Introdu un nume de canal (trebuie să fie unic în toată rețeaua).
4. Alege limba și dacă canalul trebuie să fie public sau privat.
5. Opțional: adaugă o descriere și o imagine.
6. Atinge „Creează".

La canalele publice poți stabili dacă conținutul este clasificat ca „Nesigur pentru minori".

### Raportarea conținutului

Dacă observi conținut inadecvat într-un canal public, îl poți raporta. Cleona folosește un sistem de moderare descentralizat: raportările sunt evaluate de membri ai rețelei selectați aleatoriu (un fel de „jurați"). Dacă se constată o abatere, canalul primește un avertisment. La abateri repetate, este retrogradat în indexul de căutare sau blocat.

### Canale de sistem

Cleona dispune de două canale de sistem integrate:

- **Bug Log:** Când Cleona detectează o eroare, te întreabă dacă vrei să trimiți un raport de eroare; înainte vezi exact ce se publică. Aceste rapoarte ajung în canalul Bug Log, unde pot fi consultate de comunitate. Un raport nu poartă niciun nume și niciun conținut al conversațiilor tale, ci un pseudonim. În beta el numește în plus identificatorul tău (User-ID), ca dezvoltatorii să poată întreba. Poți trimite și manual un raport de jurnal (cu dialog de previzualizare și consimțământ explicit).
- **Cereri de funcții:** Aici utilizatorii pot depune dorințe de funcții și vota pentru propunerile existente. Propunerile sunt sortate după voturi.

Fiecare calculator păstrează până la 25 MB pe canal de sistem, fiecare telefon până la 5 MB; când se umple, iese primul cel mai vechi -- niciodată ce ai văzut tu deja.

---
## 7. Apeluri

### Pornirea unui apel vocal

1. Deschide chatul cu contactul pe care vrei să-l suni.
2. Atinge simbolul de telefon din bara de sus.
3. Așteaptă până când interlocutorul acceptă apelul.

În timpul convorbirii vezi o linie de timp, durata convorbirii și ai acces la funcțiile de dezactivare a microfonului și difuzor.

Pentru a închide, atinge butonul roșu de închidere.

Dacă vezi „Indisponibil", dispozitivul interlocutorului tău nu poate fi contactat chiar acum, de exemplu un iPhone a cărui aplicație nu este deschisă. Trimite un mesaj în schimb.

### Pornirea unui apel video

1. Deschide chatul cu contactul.
2. Atinge simbolul de cameră din bara de sus.
3. Imaginea ta video apare într-o fereastră mică, imaginea interlocutorului în zona mare.

Poți comuta în timpul convorbirii între camera din față și cea din spate.

### Apeluri primite

Când cineva te sună, apare o fereastră de notificare cu numele apelantului. Poți:

- **Acceptă** -- convorbirea începe.
- **Refuză** -- apelantul este notificat.

Dacă ești chiar acum într-o convorbire, un apel nou nu sună; primești în schimb un mesaj „Apel pierdut". Același lucru este valabil pentru un apel de grup pe care nu l-ai acceptat -- mesajul stă atunci în chatul de grup.

Dacă cineva sună una dintre identitățile tale care nu este afișată chiar acum, sună totuși; ecranul de apel spune care dintre identitățile tale este sunată.

Pe iPhone sună doar cât timp aplicația este deschisă. Cine te sună cât timp aplicația nu este deschisă vede „Indisponibil" după 10 secunde. De îndată ce deschizi aplicația, găsești un mesaj despre apelul pierdut.

### Apeluri de grup

Poți purta și apeluri de grup în care participă mai multe persoane simultan. Apelul este organizat printr-un arbore inteligent de retransmitere, astfel încât nu trebuie ca fiecare participant să fie conectat direct cu fiecare altul. Toate convorbirile sunt criptate pe toată durata.

Fiecare membru al grupului poate porni un apel de grup. Doi participanți care nu sunt contacte unul pentru altul nu văd niciodată adresa de internet a celuilalt: sunetul și imaginea lor trec peste un participant care este contact cu amândoi. Dacă nu există unul astfel, cei doi nu sunt conectați, iar caseta spune „Niciun contact comun în apel". Dacă o retransmitere este supraîncărcată, rămâne sunetul, iar imaginea video cade pentru această pereche.

### Criptarea la apeluri

Toate apelurile sunt criptate cu chei de unică folosință care există doar pe durata convorbirii. După închidere, aceste chei sunt șterse imediat. Nimeni nu poate decripta ulterior o convorbire trecută.

Sincer spus: apelurile rulează, pe cât posibil, direct între dispozitive, pentru că și o mică întârziere deranjează la vorbire. Spre deosebire de mesaje, furnizorul tău de internet poate deci vedea, în timpul unui apel, cu ce adresă de internet ești conectat. Ce spuneți, nu vede.

În timpul unui apel, contactul tău îți vede și el adresa de internet. Dacă nu vrei asta la un contact, oprește în meniul lui „Permite apelurile" (implicit: pornit). Dacă oprești mai târziu, o adresă pe care a văzut-o deja îi rămâne cunoscută.

---

## 8. Calendar

Cleona conține un calendar integrat care funcționează criptat și complet descentralizat -- fără serviciu cloud.

### Vizualizări

Calendarul oferă cinci vizualizări: zi, săptămână, lună, an și o vizualizare de sarcini. Comută între ele prin taburile din partea de sus a ecranului calendarului.

### Crearea programărilor

Atinge un interval de timp sau folosește butonul de adăugare pentru a crea o programare nouă. Poți introduce titlu, dată, oră, loc și notițe. Programările sunt stocate criptat pe dispozitivul tău.

### Programări recurente

Programările se pot repeta zilnic, săptămânal, lunar sau anual. Poți ajusta modelul (de exemplu, în fiecare al doilea marți, în prima zi a fiecărei luni) și poți stabili o dată de sfârșit sau un număr de repetări.

### Invitarea contactelor

La crearea sau editarea unei programări îți poți invita contactele Cleona. Ele primesc o invitație de calendar criptată și pot răspunde cu da, nu sau poate. Modificările programării sunt trimise automat tuturor invitaților.

### Afișare liber/ocupat

Îți poți împărtăși disponibilitatea cu contactele fără să divulgi detaliile programărilor. Există trei niveluri de confidențialitate: detalii complete, doar blocuri de timp sau ascuns. Poți stabili un implicit și îl poți suprascrie per contact.

### Memento-uri

Programările pot avea memento-uri care declanșează o notificare de sistem înainte de începerea programării. Poți amâna memento-urile la nevoie.

### Sincronizare externă de calendar

Cleona se poate sincroniza cu servicii externe de calendar:

- **CalDAV** -- Conectează-te la orice server compatibil CalDAV (Nextcloud, Radicale etc.).
- **Google Calendar** -- Sincronizare prin Google Calendar API cu autentificare OAuth2 securizată.
- **Server CalDAV local** -- Cleona poate porni un server CalDAV local pe dispozitivul tău, astfel încât aplicațiile de calendar pentru desktop (Thunderbird, Outlook, Apple Calendar, Evolution) să se sincronizeze cu calendarul tău Cleona.
- **Calendarul de sistem Android** -- Programările din Cleona pot fi transferate în aplicația de calendar integrată a dispozitivului tău Android.
- **Fișiere ICS** -- Importă și exportă programări în formatul standard iCalendar.

### Export PDF

Poți tipări sau exporta orice vizualizare de calendar (zi, săptămână, lună, an) ca document PDF.

---

## 9. Sondaje

Poți crea sondaje în orice chat sau grup pentru a aduna opinii sau a planifica date.

### Tipuri de sondaje

Cleona suportă cinci tipuri de sondaje:

- **O singură alegere** -- participanții aleg o opțiune.
- **Alegere multiplă** -- participanții pot alege mai multe opțiuni.
- **Sondaj de date** -- Găsește o dată care se potrivește tuturor. Fiecare participant marchează datele ca disponibile, poate sau nu disponibile.
- **Scară** -- Evaluează ceva pe o scară numerică (de exemplu 1 la 5).
- **Text liber** -- participanții scriu propriul lor răspuns.

### Crearea unui sondaj

Deschide un chat și atinge simbolul de sondaj (sau folosește meniul de atașare). Alege tipul de sondaj, formulează întrebarea și opțiunile, și trimite sondajul. Apare ca mesaj în chat.

### Votarea

Atinge un sondaj pentru a-ți da votul. Îți poți schimba sau retrage votul oricând.

### Votare anonimă

Sondajele pot fi configurate pentru votare anonimă. Când este activat, voturile sunt anonime criptografic -- nimeni, nici măcar creatorul sondajului, nu poate vedea cine a votat pentru ce. Numărul de voturi rămâne totuși vizibil.

### Sondaj de date în calendar

Când un sondaj de date este încheiat, data câștigătoare poate fi transformată într-o programare de calendar cu o singură atingere.

---
## 10. Mai multe identități

### De ce mai multe identități?

Imaginează-ți că vrei să-ți separi viața profesională de cea privată -- similar cu două numere de telefon diferite, dar fără un al doilea telefon. În Cleona poți folosi mai multe identități pe un singur dispozitiv. Fiecare identitate are propriul nume, propria imagine de profil, propriile contacte și propriile conversații.

### Crearea unei identități noi

1. În bara de sus îți vezi identitatea curentă ca tab.
2. Atinge semnul plus (+) din dreapta taburilor de identitate.
3. Introdu un nume pentru identitatea nouă.
4. Gata -- identitatea nouă este activă imediat.

### Comutarea între identități

Pur și simplu atinge tabul de identitate din bara de sus. Comutarea este imediată -- fără timp de așteptare, fără reîncărcare.

### Toate rulează simultan

Un punct important: toate identitățile tale sunt active în același timp. Chiar dacă ești afișat acum ca „Profesional", identitatea ta „Privat" primește în continuare mesaje. Nu ratezi nimic, indiferent ce identitate ai selectat acum.

### Pagina de detalii a identității

Când atingi tabul identității tale curent active, se deschide pagina de detalii. Aici poți:

- Afișa codul QR pentru contacte.
- Schimba sau elimina imaginea de profil.
- Adăuga o descriere de profil.
- Schimba numele afișat.
- Alege un design (temă) pentru această identitate.
- Șterge identitatea, dacă nu mai ai nevoie de ea.

### Ștergerea unei identități

Când ștergi o identitate, contactele tale sunt notificate despre asta. Identitatea și toate datele asociate sunt eliminate de pe dispozitivul tău. Acest proces nu este reversibil.

---

## 11. Mai multe dispozitive

### O identitate, un dispozitiv -- deocamdată

O identitate rulează astăzi pe un dispozitiv. Un al doilea dispozitiv pentru aceeași identitate vine într-o versiune ulterioară; în setările, la „Dispozitive" -> „Gestionează dispozitivele", „Cuplează un dispozitiv suplimentar" stă de aceea încă ca „Încă indisponibil".

Când vine, va fi așa: toate dispozitivele au drepturi egale, nu există un dispozitiv principal. Un dispozitiv suplimentar îl configurezi cu cele 24 de cuvinte ale tale, iar unul dintre dispozitivele tale de până acum dă aprobarea. Maximum 5 dispozitive.

Dacă introduci astăzi cele 24 de cuvinte pe un dispozitiv nou, te muți: identitatea este restabilită pe dispozitivul nou, iar dispozitivul tău de până acum o elimină apoi la el (vezi capitolul 12).

Pe mai multe dispozitive poți folosi astăzi identități diferite (capitolul 10).

### Rotirea cheilor identității

Dacă bănuiești că cineva a pus mâna pe cheile tale, poți genera chei noi la „Gestionează dispozitivele" -> „Rotire chei". Contactele tale sunt notificate, invitațiile tale deschise sunt revocate. Important: după asta, cele 24 de cuvinte produc de ele singure doar cheile vechi. Creează de aceea direct după asta un pachet de recuperare nou; restabilirea merge atunci doar împreună cu acest pachet.

---

## 12. Recuperare

### Folosirea frazei-seed

Când îți pierzi dispozitivul sau configurezi unul nou:

1. Instalează Cleona pe dispozitivul nou.
2. Alege la pornire „Restaurează".
3. Introdu cele 24 de cuvinte ale tale.
4. Cleona generează din ele toate identitățile tale -- cu aceleași chei ca înainte. Pentru contactele tale ești aceeași persoană.

### Ce revine -- și ce nu

Identitatea ta stă în cele 24 de cuvinte, contactele tale și istoricul tău nu. Înapoi revine accesul tău la rețea prin **pachetul de recuperare**: dispozitivul tău depune un pachet mic, criptat, în rețea. Doar cele 24 de cuvinte ale tale îl pot găsi și deschide. În el stă ce are nevoie dispozitivul tău nou pentru a-ți reajunge contactele, și ce a stat între timp în rețea pentru tine. Pentru asta nu trebuie ca niciun contact să fie online.

O restabilire nu aduce înapoi istoricul de chat de până acum.

Pachetul de recuperare trăiește 7 zile și este reînnoit de dispozitivul tău cât timp rulează; în setări vezi până când este valabil. Dacă niciunul dintre dispozitivele tale nu a rulat mai mult de 7 zile, pachetul a expirat. Atunci cele 24 de cuvinte îți restabilesc identitatea totuși, dar contactele trebuie să le reinvii; ce a stat între timp în rețea pentru tine este pierdut.

### Restabilirea înseamnă mutare

Dacă dispozitivul tău de până acum constată mai târziu că identitatea a fost restabilită în altă parte, el o elimină la el -- împreună cu istoricul ei. De aceea: cine are cele 24 de cuvinte ale tale îți poate lua identitatea în felul acesta de pe dispozitivul tău. Până revin toate contactele, aplicația îți amintește de asta; cu „Finalizează și reînnoiește cheile" închei tu însuți/însăți restabilirea.

### Ce nu poate restabili nimeni

Asta este important, și de aceea o spunem limpede:

- **Nimeni în afară de tine nu îți poate restabili identitatea.** Nu dezvoltatorul, nu un suport, și nici contactele tale -- indiferent câte sunt. Nu există nicio cheie principală și nicio parte a cheii tale depusă la alții.
- **Dacă ai pierdut cele 24 de cuvinte și nu mai ai niciun dispozitiv, identitatea ta este pierdută.** Atunci rămâne doar să creezi una nouă și să-ți reinvii contactele.

Cea mai bună protecție: scrie cele 24 de cuvinte pe hârtie și păstrează-le în siguranță.

---
## 13. Setări

Setările le accesezi prin simbolul de roată dințată din colțul din dreapta sus.

### Notificări și tonuri de apel

- Alege din șase tonuri de apel diferite pentru apelurile primite.
- Setează un sunet de mesaj.
- Pe dispozitivele Android poți activa sau dezactiva suplimentar vibrația.
- **„Dezactivează sunetul pentru tot"** nu mai lasă pe acest dispozitiv niciun mesaj să sune, să vibreze sau să te anunțe -- pentru toate identitățile. Apelurile sună în continuare.
- **„Ore de liniște"** le stabilești pentru fiecare identitate cu De/Până la. În acest interval, niciun mesaj al acestei identități nu sună, nu vibrează și nu te anunță; mesajele sosesc totuși.
- **„Notificări fără conținut"** (implicit: oprit) arată doar că a sosit un mesaj, o invitație sau un memento -- fără expeditor, nume și text. Apelurile arată în continuare numele.
- Ce sosește dintr-odată după pornire, Cleona anunță într-o notificare colectivă („5 mesaje noi în 2 conversații"); tot ce vine mai târziu, individual. O atingere pe o notificare de mesaj deschide conversația, chiar și într-o altă identitate.

### Design-uri (teme)

Cleona oferă zece design-uri diferite: Teal, Ocean, Sunset, Forest, Amethyst, Fire, Storm, Slate, Gold și Contrast. Design-ul Contrast îndeplinește cel mai înalt nivel de accesibilitate (WCAG AAA) și este deosebit de ușor de citit cu vedere limitată.

Fiecare identitate poate avea propriul design. Modifici design-ul pe pagina de detalii a identității (atinge tabul de identitate activ).

Suplimentar, poți comuta în setări, la „Aspect", între temele luminoasă, întunecată și cea de sistem.

### Schimbarea limbii

Cleona este disponibil în 34 de limbi, inclusiv limbi cu scriere de la dreapta la stânga (de exemplu araba, ebraica). Schimbă limba în setări, la „Limbă".

### Arhivarea mediilor

Dacă ai acasă un spațiu de stocare în rețea (NAS) sau un folder partajat, Cleona îți poate descărca automat mediile acolo. Sunt suportate SMB, SFTP, FTPS și WebDAV.

Așa funcționează stocarea în trepte:
- Primele 30 de zile: Totul rămâne pe dispozitivul tău.
- După 30 de zile: O imagine de previzualizare rămâne pe dispozitiv, originalul este arhivat.
- După 90 de zile: Doar o mică imagine de previzualizare rămâne pe dispozitiv.
- După un an: Rămâne doar un înlocuitor, originalul stă în siguranță în arhivă.

Poți atinge oricând un mediu arhivat pentru a-l recupera -- cu condiția să fii conectat la rețeaua ta de acasă. Mediile deosebit de importante pot fi fixate, ca să nu fie niciodată descărcate.

La „Buget stocare" stabilești câți MB de media rămân pe dispozitiv (implicit: 100 MB pe telefon, 2 GB pe calculator). Când se umple, este arhivat mai întâi cel mai vechi mediu nefixat. Un original este șters doar când stă în siguranță în arhivă -- mesajele text rămân mereu păstrate.

### Transcrierea mesajelor vocale

Când este activat, mesajele tale vocale sunt convertite local în text pe dispozitivul tău (cu modelul open-source Whisper). Textul transcris este trimis împreună cu înregistrarea către interlocutor. Transcrierea se face complet pe dispozitivul tău -- niciun date nu merg la servicii externe.

Ce model (tiny, base, small) se descarcă stabilești o singură dată pentru dispozitiv; limba (automată sau fixă) pentru fiecare identitate.

### Descărcare automată

Poți seta de la ce mărime mediile să fie descărcate automat. Așa poți, de exemplu, lăsa imaginile să se încarce automat, dar să decizi manual la videoclipuri mari.

### Dispozitive

La „Dispozitive" -> „Gestionează dispozitivele" vezi acest dispozitiv. Cuplarea unui dispozitiv suplimentar vine într-o versiune ulterioară (capitolul 11).

### Rețea

Cleona nu are nevoie de setări de rețea ca să funcționeze. Există
trei comutatoare de rețea:

- **Redirecționare port pe router** (implicit: pornit). Cleona cere propriului tău router să deschidă o ușă pentru Cleona. Dacă reușește, dispozitivul tău este mai ușor de atins de alții și ajută rețeaua. Cleona vorbește doar cu routerul tău, nu cu internetul.
- **Înregistrări publice de adresă** (implicit: pornit). Dacă dispozitivul tău are încă prea puțini vecini, caută în-un director public (Nostr) alte puncte de intrare, iar dacă el însuși este bine accesibil, se înregistrează acolo. Înregistrarea conține o adresă, niciun nume și niciun contact. Dacă îl oprești, dispozitivul tău găsește vecini doar prin invitații, rețeaua locală și vecinii pe care îi cunoaște deja.
- **Mai puține pachete de camuflaj în Wi-Fi** (implicit: oprit). În Wi-Fi sau la cablu poți opri pachetele goale de camuflaj. Atunci este însă din nou vizibil când scrii. În datele mobile nu există acest comutator -- acolo Cleona trimite oricum doar un pachet de camuflaj pe minut.

Camuflajul ca întreg nu poate fi oprit. Asta este intenționat: doar dacă rulează mereu, activitatea dispozitivului tău nu spune nimic despre dacă scrii sau nu chiar acum.

Peste cele trei comutatoare stă **Mod economie de date**: în datele mobile, Cleona ți-l propune, dar nu îl pornește niciodată singură. El economisește date, în schimb dispozitivul tău este mai ușor de recunoscut din afară.

Dedesubt stabilești **„Cache pentru media altor persoane"**: dispozitivul tău păstrează părți criptate din media altora până la 7 zile, ca ele să-și ajungă destinatarii (implicit: 100 MB pe telefon, 1 GB pe calculator). O mărime mai mică eliberează imediat locul -- întâi părțile cele mai vechi.

---

## 14. Securitate

### Ce înseamnă criptare post-cuantum?

Criptarea de azi se bazează pe probleme matematice care sunt extrem de greu de rezolvat pentru calculatoarele normale. Calculatoarele cuantice ar putea rezolva unele dintre aceste probleme rapid în viitor. Criptarea post-cuantum folosește proceduri suplimentare care rezistă și calculatoarelor cuantice.

Cleona combină ambele abordări: criptare clasică pentru fiabilitate și proceduri post-cuantum pentru siguranță la viitor. Așa ești protejat simultan împotriva amenințărilor de azi și de mâine.

Pentru fiecare mesaj individual se generează o cheie separată. Chiar dacă un atacator ar sparge cheia unui mesaj, nu ar putea citi cu ea niciun alt mesaj.

### De ce niciun server este mai sigur

La aplicațiile de mesagerie convenționale, mesajele tale trec prin serverele furnizorului. Chiar dacă acolo ar fi criptate: furnizorul are acces la metadate (cine comunică cu cine, când, cât de des, de unde) și trebuie eventual să le predea la ordinul instanței.

La Cleona nu există un astfel de punct central. Nu există niciun loc unde să convergă toate metadatele și niciun director în care s-ar putea căuta cine ești sau pe cine cunoști.

### Cine vede că scrii cu cineva?

Criptarea protejează **ce** scrii. La fel de important este ca niciun observator singular să nu afle **cu cine** și **când** scrii. De asta se îngrijește Cleona astfel:

- **Pe internet niciodată direct.** Dacă dispozitivul tău ar trimite un mesaj direct la adresa de internet a interlocutorului, furnizorul tău ar putea vedea cu cine scrii. De aceea un mesaj pe internet merge mereu peste vecinii tăi fixi: al tău și al interlocutorului.
- **Vecini în care ai încredere.** Vecinii tăi fixi sunt, pe cât posibil, dispozitive ale propriilor tale contacte -- până la trei care sunt accesibile din afară chiar acum. Dacă unul cedează, un alt contact îi ia locul. Un contact nu poate fi cumpărat cu servere; un nod oarecare din rețea, da. Dacă nu ai încă niciun contact accesibil, Cleona ia un alt vecin. Invitația ta nu numește niciodată vreun contact de-ale tale, ca nimeni să nu afle prin ele adresa unui prieten.
- **Coduri în loc de nume.** Vecinii nu văd nume și nici identificatori, ci doar un cod. El este valabil exact pentru voi doi, într-o direcție, pentru o zi -- a doua zi este altul. Vecinul tău știe de unde vine pachetul, dar nu unde ajunge la final. Vecinul interlocutorului știe unde merge, dar nu de unde a venit. În mod normal, nimeni de pe traseu nu vede ambele capete.
- **Camuflajul.** Dispozitivul tău trimite în mod constant, la intervale neregulate, pachete de camuflaj către vecinii săi. Ele sunt la fel de mari ca pachetele reale, trec peste același port și din afară nu se disting de ele. Dacă un om scrie chiar acum sau dispozitivul doar rulează nu se poate deduce. Mesajele tale nu așteaptă niciodată camuflajul -- pornesc imediat, el rulează doar pe lângă.

**Cât costă camuflajul:** În Wi-Fi aproximativ 13 MB pe zi. În datele mobile, Cleona trimite doar un pachet de camuflaj pe minut, adică aproximativ 1,7 MB pe zi. Motivul limitării în datele mobile nu este volumul de date, ci bateria: fiecare pachet trezește modemul radio.

**Ce nu poate ascunde Cleona** -- sincer spus:

- Niciun observator **singular** nu vede cine scrie cu cine -- nici furnizorul tău, nici nodurile de pe traseu. Cine supraveghează însă **ambele capete simultan**, de exemplu un stat care îți urmărește conexiunea ta și a interlocutorului sau instalează ambii vecini, poate corela în timp: pachet ieșit la tine, la scurt timp pachet intrat la interlocutor. Repetat suficient de des, asta dă o conexiune.
- Camuflajul îngreunează această corelare, dar nu o previne. El ascunde mesaje individuale, nu volumul: cine trimite foarte mult crește traficul total al dispozitivului său.
- Un contact care îți este vecin fix află **când** și **cât** trimiți și primești -- nu cu cine și nu ce. Dacă pericolul vine din propriul tău anturaj, poți exclude fiecare contact din asta (vezi capitolul 3, „Nu folosi niciodată ca vecin fix").
- Dacă doi utilizatori noi au doar același singur vecin, mesajul lor trece exact peste acest nod, și el vede ambele capete. De îndată ce unul dintre ei are alți vecini, asta se termină.
- Invitația ta conține adresele tale de internet. Cine are linia de text vede unde ești online -- dă-o doar oamenilor cărora le încredințezi asta.
- Un vecin care retransmite vede că două coduri schimbă pachete -- nu cine este în spate, și nu ce e înăuntru.
- Un semnal al unui apel în curs poate trece, dacă primul vecin nu răspunde chiar atunci, peste un nod care vede ambele capete; el află că vorbiți împreună la telefon.
- Un fișier mare căruia i-ai dat consimțământul este văzut de calculatorul care îl retransmite sau îl păstrează, la ambele capete (vezi capitolul 4).
- La apeluri, protecția față de furnizor nu se aplică, iar contactul tău îți vede adresa de internet (vezi capitolul 7).

### Ce se întâmplă când interlocutorul este offline?

1. Cleona pornește simultan toate rutele potrivite: în același Wi-Fi direct, pe internet peste doi vecini -- și suplimentar căsuța poștală.
2. Pentru căsuța poștală, Cleona depune mesajul criptat la trei vecini. De îndată ce doi confirmă primirea, el este considerat depus.
3. Cleona alege pentru asta preferențial vecini la care interlocutorul caută și el -- mai întâi vecinul pe care îl numește invitația lui.
4. Mesajul așteaptă acolo până la 7 zile. Când interlocutorul revine, îl ridică și îți confirmă primirea. Abia atunci vezi două bifuri.

Căsuța poștală o poate goli doar interlocutorul: ridicarea și ștergerea merg doar cu o cheie pe care o are doar el, iar ștergerea se face abia după ce a confirmat primirea. Vecinii văd doar pachete criptate sub o valoare care se schimbă în fiecare zi.

### Străinii nu trec

De la cineva care nu este nici contactul tău, nici membru al unui grup comun, Cleona acceptă exact două lucruri: cererea de chei publice ale tale, atâta timp cât una dintre invitațiile tale este deschisă, și o cerere de contact. Cererea trebuie să poarte o invitație validă de la tine, iar expeditorul trebuie să fi rezolvat în prealabil o problemă de calcul. Tot restul -- mesaje, apeluri, fișiere -- este eliminat înainte să ajungă măcar la aplicație. Cine are doar cartea ta de vizită tipărită nu te poate deci pur și simplu suna. Un membru al unui grup comun te ajunge doar în acest grup -- cu mesaje de grup și apeluri de grup, niciodată individual.

### Anti-cenzură

Cleona este construită ca să fie greu de blocat:

- **Fără server, fără adresă fixă.** În aplicație nu figurează nicio adresă care s-ar putea bloca, iar rețeaua nu depinde de niciun nod unic.
- **Fără port fix.** Fiecare dispozitiv alege un port aleatoriu la prima pornire. Nu există niciun număr de port cunoscut după care s-ar putea recunoaște traficul Cleona.
- **Ca date aleatoare.** Stabilirea conexiunii dintre două dispozitive este codată astfel încât să nu se distingă de date aleatoare.
- **Multe puncte de intrare.** Fiecare invitație, fiecare vecin și fiecare dispozitiv din același Wi-Fi este o rută posibilă înapoi în rețea.

### Stocare securizată a cheilor

Pe platformele suportate, Cleona îți stochează cheile de criptare în inelul de chei securizat al sistemului de operare (Android Keystore, iOS Keychain, macOS Keychain). Unde este disponibil, asta oferă protecție susținută de hardware pentru cheile tale.

### Criptarea bazei de date

Mesajele și conversațiile tale se află într-o bază de date criptată -- una separată pentru fiecare identitate, fiecare cu propria cheie. Criptat nu este doar baza de date însăși, ci și fișierele ei intermediare; nimic nu se scrie necriptat pe disc, nici măcar temporar. Setările, contactele și mediile sunt și ele stocate criptat.

Cheile sunt derivate din cele 24 de cuvinte ale tale și există doar pe dispozitivul tău. Chiar și cine pune mâna pe dispozitivul tău și citește datele găsește fără aceste chei doar date ilizibile.

Necriptat devine doar acolo unde scoți tu însuți/însăți conținuturi din Cleona:
- când salvezi un fișier dintr-un chat pe dispozitivul tău,
- când pui cu butonul de captură de ecran o imagine în imaginile tale,
- când trimiți ceva către o altă aplicație,
- când configurezi arhivarea mediilor (capitolul 13): originalele arhivate stau necriptate pe stocarea ta de rețea de acasă, ca să le poți deschide acolo și fără Cleona,
- când oglindești programări în calendarul de sistem Android: acolo le pot citi alte aplicații cu acces la calendar.

Ce a ieșit astfel nu se șterge odată cu mesajul și nu expiră odată cu el.

### Protecție pe ecran

Pe Android, Windows și macOS, Cleona nu permite nicio înregistrare a ecranului de către alte aplicații. Dacă ai nevoie de o imagine, folosește butonul de captură de ecran din bara de sus: el pune imaginea în imaginile tale -- necriptată. Într-o conversație în care transmiterea mai departe nu este permisă, nu există captură de ecran.

---

## 15. Actualizări software

### Cum primesc actualizări?

Cleona poate fi actualizată pe diferite căi. Scopul este să poți primi actualizări chiar și când canale individuale de distribuție cedează sau sunt blocate:

1. **App Store / Play Store:** De îndată ce Cleona apare acolo și ai instalat-o printr-un store, primești actualizări ca de obicei prin store. Pe iPhone, actualizările vin prin TestFlight.
2. **GitHub Releases:** Pe pagina de GitHub a proiectului găsești pachete de instalare semnate pentru toate platformele.
3. **Actualizări peste rețea:** Cleona poate obține o actualizare direct peste rețea -- fără server de descărcare. Noua versiune este despiciată în bucăți cu corecție de erori care se răspândesc în rețea; o parte din ele călătorește chiar și în camuflaj. Dispozitivul tău adună suficiente bucăți și asamblează actualizarea. Este transferat de obicei doar modificarea -- câțiva MB în locul întregii aplicații. Asta este valabil pentru Linux, Windows și Android; pe macOS descarci versiuni noi de pe site sau de pe GitHub.
4. **Linkuri de invitație:** Poți crea linkuri de invitație care conțin tot ce are nevoie un utilizator nou pentru a instala Cleona și a se conecta la rețea.
5. **Transfer fizic:** În medii fără internet poți pasa Cleona mai departe altora prin stick USB sau în rețeaua locală.

### Cum rulează o actualizare

1. Cleona adună automat în fundal bucățile unei actualizări noi și le asamblează.
2. Abia când actualizarea este **completă** și **semnătura ei verificată**, Cleona ți-o oferă. Nu primești deci niciodată o actualizare pe jumătate sau neverificată.
3. Când atingi „Instalează", instalarea pornește fără alte întrebări. Pe Android, sistemul își arată suplimentar dialogul de instalare.

Versiunile mai vechi nu sunt oferite -- o actualizare merge mereu doar înainte. Dacă o versiune este atât de veche încât nu mai poate coopera cu rețeaua, Cleona indică asta clar și te roagă să actualizezi.

### Verificarea semnăturii

Fiecare actualizare este semnată dublu: cu o procedură clasică și una post-cuantum. Cleona verifică automat ambele semnături. Astfel este asigurat că sunt acceptate doar actualizări de la dezvoltatorul oficial -- chiar dacă actualizarea a venit peste rețea de la dispozitive străine. O actualizare nu apare niciodată automat din dezvoltare, ci doar când dezvoltatorul o semnează de mână.

---
## 16. Întrebări frecvente

### „Pot folosi Cleona fără internet?"

Cleona are nevoie de o conexiune de rețea, dar nu neapărat de internet: în același Wi-Fi, dispozitivele Cleona se găsesc singure și pot scrie între ele complet fără acces la internet. Nu trebuie să fii online simultan cu interlocutorul: dacă este offline, mesajul așteaptă până la 7 zile în căsuța poștală la trei vecini, până când îl ridică.

### „Ce fac dacă îmi pierd fraza-seed?"

Atâta timp cât mai rulează un dispozitiv cu identitatea ta, nimic nu este pierdut -- acolo pur și simplu continui să scrii. Pe dispozitivul pe care ai creat identitatea, poți de obicei citi din nou cele 24 de cuvinte (vezi capitolul 2). Nu te baza pe asta: o reinstalare îndepărtează această copie, iar pe Android o distruge și eliminarea sau modificarea blocării ecranului. Dacă nu ai nici cuvintele, nici un dispozitiv, nu există cale de întoarcere -- nici prin contactele tale, dezvoltator sau oricine altcineva. De aceea este atât de important să păstrezi în siguranță cele 24 de cuvinte.

### „Poate cineva să-mi citească mesajele?"

Nu. Fiecare mesaj este criptat cu o cheie de unică folosință care este valabilă doar pentru acest singur mesaj. Doar tu și interlocutorul tău puteți decripta mesajul. Nu există niciun server central, nicio cheie principală și niciun acces pentru dezvoltator. Chiar dacă un dispozitiv retransmite mesajul pe traseul de transport, el vede doar tocătură de date criptate și un cod. Vecinul tău știe că pachetul vine de la tine, dar nu și către cine merge; vecinul interlocutorului știe către cine merge, dar nu și de la cine.

### „De ce nu am nevoie de număr de telefon?"

Pentru că identitatea ta este pur criptografică. În loc de un număr de telefon sau o adresă de e-mail legate de numele tău real, te identifică o pereche de chei generată pe dispozitivul tău. Contactele le adaugi prin cod QR, NFC sau linia de text a invitației tale -- nu printr-o agendă telefonică. Asta înseamnă mai multă intimitate, pentru că un cont de mesagerie nu este legat de identitatea ta reală.

### „Cum găsesc oameni pe Cleona?"

Cleona nu are intenționat nicio căutare de contacte după număr de telefon sau nume -- asta ar fi o problemă de intimitate. În schimb, schimbi invitații direct: prin cod QR, NFC sau ca linie de text pe o altă cale. Asta e ca schimbul de cartele de vizită, nu ca căutarea în agenda telefonică.

### „Funcționează Cleona și în străinătate?"

Da. Atâta timp cât ai o conexiune la internet, Cleona funcționează oriunde în lume. Deoarece nu există niciun server central și nicio adresă fixă, serviciul nu poate fi pur și simplu oprit pentru anumite țări. Cum îngreunează Cleona blocarea este descris în capitolul „Securitate" la „Anti-cenzură". O țară care blochează la graniță fiecare trafic necunoscut poate însă opri și Cleona.

### „Este Cleona gratuit?"

Da. Cleona este gratuit de folosit și fără reclame. Deoarece nu există un server central, nu cad nici costuri de server pentru funcționare. În setări, la „Sprijină Cleona" -> „Donează", poți sprijini voluntar dezvoltarea.

### „Mesajul meu are doar un bif -- ce înseamnă?"

Mesajul este pe drum, dar interlocutorul nu a confirmat încă primirea -- cel mai des pentru că este offline chiar acum. Asta nu este o eroare: mesajul așteaptă până la 7 zile în căsuța poștală. De îndată ce îl ridică, vezi două bifuri. Un ceas înseamnă că încă nicio rută nu a dus mesajul -- el pornește de la sine de îndată ce există una; un semn de avertizare, că mesajul nu a găsit timp de 14 zile nicio rută și că îl poți retrimite.

### „De ce sosesc mesajele cu întârziere pe iPhone-ul meu?"

iOS nu permite aplicațiilor să ruleze permanent în fundal. Cleona este trezită doar din când în când, pe scurt; când anume, decide iOS. Colectează atunci totul. De îndată ce deschizi aplicația, Cleona colectează ce a fost păstrat pentru tine.

### „Pot trece de la WhatsApp la Cleona?"

Da, dar nu îți poți transfera chaturile de WhatsApp. Cleona și WhatsApp sunt sisteme fundamental diferite. Trebuie să-ți adaugi contactele individual în Cleona. Cel mai simplu merge dacă trimi contactelor tale linia de text a invitației tale. Fiecare cerere care sosește așa o confirmi tu însuți/însăți sub „Cereri".

### „Pot folosi Cleona pe mai multe dispozitive simultan?"

Încă nu. Un al doilea dispozitiv pentru aceeași identitate vine într-o versiune ulterioară (capitolul 11). Pe mai multe dispozitive poți folosi astăzi identități diferite.

### „Cum primesc actualizări când App Store-ul este blocat?"

Cleona poate obține actualizări direct peste rețea, fără să depindă de un App Store, un site web sau un server de descărcare. Dacă un alt dispozitiv din rețea are cea mai nouă versiune, dispozitivul tău poate încărca actualizarea de acolo. Autenticitatea este verificată printr-o semnătură digitală a dezvoltatorului. Alternativ, un contact îți poate pasa aplicația prin link de invitație sau stick USB. Mai multe în capitolul „Actualizări software".

---

## Ajutor și contact

Dacă ai întrebări sau te lovesti de o problemă, găsești informații actuale pe site-ul Cleona și pe GitHub. Deoarece Cleona este un proiect descentralizat, nu există niciun suport clasic pentru clienți -- dar o comunitate activă care ajută cu drag.

---

*Acest manual descrie Cleona Chat versiunea 4.2. Funcții individuale se pot
schimba sau extinde în versiuni mai noi.*
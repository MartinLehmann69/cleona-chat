# Cleona Chat -- Manuale utente

Versione 4.2 | Aggiornamento novembre 2026

---

## Indice

1. [Che cos'è Cleona Chat?](#1-che-cosè-cleona-chat)
2. [Primi passi](#2-primi-passi)
3. [Contatti](#3-contatti)
4. [Messaggi](#4-messaggi)
5. [Gruppi](#5-gruppi)
6. [Canali pubblici](#6-canali-pubblici)
7. [Chiamate](#7-chiamate)
8. [Calendario](#8-calendario)
9. [Sondaggi](#9-sondaggi)
10. [Più identità](#10-più-identità)
11. [Più dispositivi](#11-più-dispositivi)
12. [Ripristino](#12-ripristino)
13. [Impostazioni](#13-impostazioni)
14. [Sicurezza](#14-sicurezza)
15. [Aggiornamenti software](#15-aggiornamenti-software)
16. [Domande frequenti](#16-domande-frequenti)

---

## 1. Che cos'è Cleona Chat?

### Il tuo messenger, i tuoi dati

Cleona Chat è un messenger che funziona del tutto senza un server centrale.
I tuoi messaggi viaggiano dal tuo dispositivo al dispositivo del tuo
interlocutore -- senza deviazione attraverso una sede aziendale, senza cloud,
senza data center. Se lungo il percorso un altro dispositivo dà una mano,
si limita a inoltrare pacchetti cifrati. Nessuna azienda può leggere,
memorizzare o passare avanti i tuoi messaggi, semplicemente perché nessuna
azienda si trova in mezzo.

### Nessun account, nessun numero di telefono

Con Cleona non hai bisogno né di un numero di telefono né di un indirizzo
email per registrarti. La tua identità è formata da una coppia di chiavi
crittografiche, generata automaticamente sul tuo dispositivo al primo avvio.
Questo significa: nessuno può rintracciarti tramite il tuo numero di
telefono o il tuo indirizzo email, a meno che tu stesso non condivida i tuoi
dati di contatto.

### Cifratura a prova di futuro

Cleona usa la cosiddetta cifratura post-quantum. Significa: nemmeno futuri
computer quantistici potrebbero decifrare i tuoi messaggi. Non devi
capirne i dettagli -- l'importante è solo che la tua comunicazione è
protetta nel miglior modo possibile secondo l'attuale stato dell'arte.

### Come funziona senza un server?

La rete di Cleona è formata solo dai dispositivi dei suoi utenti. Ogni
dispositivo è un nodo, nessun nodo è più importante di un altro, e ognuno
conosce solo i suoi vicini. Quattro cose rendono questa rete speciale:

- **Nessun punto fisso.** Nell'app non c'è alcun indirizzo di server, e la
  rete non dipende da alcun singolo nodo. Non c'è niente che si possa
  spegnere per spegnere Cleona.
- **Immediato.** Il tuo messaggio parte nell'istante in cui lo invii. Non
  aspetta alcun battito e nient'altro.
- **Traffico di copertura in parallelo.** Il tuo dispositivo invia di
  continuo piccoli pacchetti di copertura, così dall'esterno non si può
  capire quando scrivi davvero. Nessun messaggio dipende da questo -- il
  traffico di copertura scorre semplicemente a fianco.
- **Codici invece di nomi.** Chi inoltra un messaggio vede solo un codice
  che cambia ogni giorno. Di norma nessuno di loro conosce mittente e
  destinatario contemporaneamente; le eccezioni sono descritte nel
  capitolo 14.

**Tre percorsi, tutti in una volta.** Quando invii un messaggio, Cleona non
prova un percorso dopo l'altro, ma tutti quelli adatti in una volta sola.
Appena il tuo interlocutore conferma la ricezione, gli altri vengono
interrotti.

1. **Nella stessa rete:** Se siete nello stesso Wi-Fi, il messaggio va
   dritto di là.
2. **Attraverso i vicini fissi:** Su Internet, il tuo dispositivo consegna
   il messaggio al suo vicino fisso. Questo lo inoltra ai vicini fissi del
   tuo interlocutore (fino a tre in una volta), e uno di questi lo
   recapita.
3. **Mailbox:** Se il tuo interlocutore è offline, Cleona deposita il
   messaggio cifrato presso tre vicini. Lì resta fino a 7 giorni. Quando
   il tuo interlocutore torna online, lo ritira.

**Come entri nella rete?** Nell'app non c'è alcun indirizzo di server. Il
punto di ingresso lo ottieni dal tuo primo contatto: il suo invito contiene
gli indirizzi attraverso cui il tuo dispositivo trova i suoi primi vicini.
Nello stesso Wi-Fi i dispositivi Cleona si trovano anche da soli. Da quel
momento il tuo dispositivo, con ogni vicino che incontra, ne conosce di
nuovi.

### Piattaforme

Cleona è disponibile per Android, iOS, macOS, Linux e Windows. Su computer e
su Android, messaggi e chiamate arrivano entro pochi secondi. Su iPhone vale
finché l'app è aperta. Quando non lo è, iOS la riattiva solo brevemente di
tanto in tanto; decide iOS quando. Cleona allora raccoglie tutto ciò che è
stato conservato per te e mostra una notifica con un numero sull'icona
dell'app. Le chiamate non raggiungono un iPhone con l'app non aperta. È una
regola di Apple, non un difetto di Cleona.

---

## 2. Primi passi

### Installare l'app

**Android:**
1. Scarica il file APK dal sito web di Cleona o da GitHub Releases.
2. Apri il file sul tuo telefono. Se necessario, consenti l'installazione
   da fonti sconosciute (Android te lo chiede automaticamente).
3. Tocca "Installa" e aspetta che l'installazione sia completata.

**iOS:**
1. Apri il link dell'invito TestFlight sul tuo iPhone.
2. Tocca "Installa". TestFlight è il metodo ufficiale di Apple per
   distribuire app in beta.
3. Dopo l'installazione troverai Cleona nella tua schermata Home.

**macOS:**
1. Scarica il file DMG dal sito web di Cleona o da GitHub Releases.
2. Apri il DMG e trascina Cleona nella cartella Applicazioni.
3. Al primo avvio macOS potrebbe chiederti se vuoi aprire un'app di uno
   sviluppatore identificato -- conferma.

**Linux (Ubuntu/Debian):**
1. Scarica il file .deb dal sito web di Cleona o da GitHub Releases.
2. Installa con un doppio clic o nel terminale: `sudo dpkg -i cleona-chat-beta_VERSION_amd64.deb`
3. Avvia Cleona dal menu delle applicazioni o nel terminale con `cleona-chat-beta`.

**Linux (Fedora/openSUSE):**
1. Scarica il file .rpm dal sito web di Cleona o da GitHub Releases.
2. Installa con: `sudo dnf install cleona-chat-beta-VERSION-1.x86_64.rpm`
3. Avvia Cleona dal menu delle applicazioni o nel terminale con `cleona-chat-beta`.

**Linux (tutte le distribuzioni -- AppImage):**
1. Scarica il file .AppImage dal sito web di Cleona o da GitHub Releases.
2. Rendi il file eseguibile: clic col tasto destro, proprietà, eseguibile, o
   nel terminale: `chmod +x cleona-chat-beta-VERSION-x86_64.AppImage`
3. Avvia con un doppio clic o nel terminale: `./cleona-chat-beta-VERSION-x86_64.AppImage`

I nomi dei pacchetti valgono per la beta, che al momento è l'unica versione
pubblicata; si chiamano `cleona-chat-beta`.

**Windows:**
1. Scarica il programma di installazione dal sito web di Cleona o da GitHub Releases.
2. Esegui il file di installazione e segui le istruzioni.
3. Avvia Cleona dal menu Start o dalla scorciatoia sul desktop.

### Creare un'identità

Al primo avvio, Cleona crea automaticamente una nuova identità per te.
Puoi darti un nome visualizzato -- è il nome che vedono i tuoi contatti.
Questo nome può essere cambiato in qualsiasi momento.

### Scrivere la seed phrase -- la cosa più importante in assoluto

Dopo aver creato la tua identità, Cleona ti mostra 24 parole. Quella è la
tua **seed phrase** -- la tua chiave personale di ripristino.

**Scrivi queste 24 parole su carta e conservale al sicuro.**

Perché è così importante?

- Se il tuo telefono si rompe, si perde o viene rubato, puoi ripristinare
  l'intera identità su un nuovo dispositivo con queste 24 parole.
- Senza la seed phrase non c'è via di ritorno. Non c'è un pulsante
  "password dimenticata" e non c'è alcun supporto che possa restituirti il
  tuo account -- perché non c'è proprio nessun account su un server. Anche
  i tuoi contatti non possono ripristinare la tua identità, per quanto
  possano essere numerosi. Un secondo dispositivo con la stessa identità
  arriverà con una versione successiva (vedi capitolo 11).
- Non passare mai la seed phrase ad altri. Chi conosce queste parole può
  spacciarsi per te.

Le 24 parole le ritrovi più tardi nelle impostazioni sotto "Backup" ->
"Mostra frase di recupero", nel caso volessi rileggerle. Su Android lo
confermi con il tuo blocco dello schermo.

### Aggiungere il primo contatto

Per chattare con qualcuno, devi prima aggiungere quella persona come
contatto. Ci sono diversi modi per farlo -- tutti spiegati nella sezione
successiva.

---

## 3. Contatti

### Il tuo invito

I contatti in Cleona nascono solo tramite un invito. Il tuo invito è
presente fin dal primo avvio -- anche senza Internet e prima che il tuo
dispositivo abbia trovato un vicino. Lo trovi nella pagina dei dettagli
della tua identità (tocca il tuo nome nella barra in alto).

L'invito esiste in due forme che contengono esattamente la stessa cosa:

- come **codice QR**, quando il tuo interlocutore è accanto a te, e
- come **riga di testo**, che invii per email, SMS o attraverso un altro
  messenger.

L'invito non contiene alcun numero di telefono e alcun nome da un
elenco. Contiene le tue chiavi pubbliche e gli indirizzi attraverso cui il
tuo interlocutore raggiunge te e i tuoi vicini. Per chi ha appena
installato Cleona, il tuo invito è quindi anche il punto di ingresso
nella rete.

### Scansionare il codice QR (consigliato)

Quando vi incontrate di persona:

1. Mostri al tuo interlocutore il codice QR del tuo invito.
2. Il tuo interlocutore tocca il pulsante più, seleziona "Scansiona codice
   QR" e punta la fotocamera verso il tuo schermo. Funziona anche con la
   webcam di un computer.
3. La richiesta arriva a te e viene **accettata automaticamente** -- perché
   hai appena mostrato tu stesso il codice.

Un codice QR vale una sola volta: la prima richiesta valida viene
accettata, dopodiché l'invito è consumato. Il codice QR è il metodo più
sicuro, perché in questo modo sapete esattamente con chi state scambiando
il contatto.

### NFC (avvicinare i telefoni)

Quando entrambi i dispositivi supportano NFC:

1. Aprite la funzione di aggiunta contatto su entrambi.
2. Avvicinate i vostri telefoni schiena contro schiena.
3. L'invito viene trasferito e accettato automaticamente.

NFC, come il codice QR, offre un livello elevato di sicurezza, perché lo
scambio funziona solo se siete fisicamente l'uno accanto all'altro.

### Inviare la riga di testo

Quando non potete incontrarvi:

1. Apri il tuo invito e copia la riga di testo.
2. Inviala alla persona che dovrebbe aggiungerti -- per email, SMS o
   attraverso un altro messenger.
3. L'altra persona incolla la riga in Cleona nella finestra di aggiunta
   contatto.
4. La richiesta compare da te sotto **"Richieste"**. Qui **non** viene
   accettata automaticamente: decidi tu, perché non puoi sapere chi altro
   ha letto la riga durante il tragitto.

### Accettare le richieste di contatto

Una richiesta in arrivo non crea ancora un contatto. Ti pone una domanda e
compare nella scheda **"Richieste"**. Lì vedi il nome e il livello di
verifica e puoi scegliere:

- **Accetta** -- solo ora la persona diventa tuo contatto.
- **Rifiuta** -- la richiesta viene scartata.
- **Blocca** -- la persona non può inviarti ulteriori richieste.

### Non usare mai come vicino fisso

Nel menu di un contatto trovi l'interruttore **"Non usare mai come vicino
fisso"** (predefinito: spento). Quando è acceso, questo contatto non
inoltra messaggi per te e quindi non viene a sapere nemmeno quando invii o
ricevi messaggi. È pensato per il caso in cui ti minacci un pericolo dal
tuo stesso ambiente.

Da parte di sconosciuti (né contatti né membri di un gruppo in comune),
Cleona non fa passare nulla oltre a una tale richiesta -- nessun messaggio,
nessuna chiamata, nessun file. E anche la richiesta arriva solo se il
mittente ha prima risolto un piccolo compito di calcolo. Questo rende caro
lo spam di massa.

### Livelli di verifica

Cleona ti indica quanto è confermata in modo sicuro l'identità di un
contatto:

| Livello | Significato |
|-------|-----------|
| Non verificato | Siete collegati, ma niente conferma che ci sia davvero la persona giusta dietro. |
| Visto | Lo scambio di chiavi è riuscito; potete comunicare in modo cifrato. |
| Verificato | Vi siete incontrati di persona e collegati tramite scansione con la fotocamera o NFC. |
| Affidabile | Hai contrassegnato questo contatto esplicitamente come degno di fiducia. |

"Verificato" esiste solo per lo scambio di persona. Un invito arrivato
tramite chat o per email non raggiunge mai questo livello -- anche se
contiene gli stessi dati.

Se le chiavi di un contatto cambiano senza preavviso, Cleona le riporta a
"Non verificato". Ti protegge così da qualcuno che si spaccia inavvertito
per il tuo contatto.

---
## 4. Messaggi

### Inviare e ricevere testo

Scrivi semplicemente il tuo messaggio nel campo di immissione in basso e
premi Invio o il pulsante di invio. Il tuo messaggio viene cifrato
automaticamente prima di lasciare il tuo dispositivo.

I messaggi in arrivo compaiono nella cronologia della chat.

### Cosa significano i segni sul tuo messaggio

| Segno | Significato |
|---------|-----------|
| Orologio | Il messaggio è stato creato, ma ancora nessun percorso lo ha portato. |
| Una spunta | Il messaggio è in viaggio. Vale anche mentre aspetta nella mailbox il tuo interlocutore. |
| Due spunte | Consegnato: il dispositivo del tuo interlocutore ha confermato la ricezione. |
| Simbolo di avviso | Per 14 giorni nessun percorso ha portato il messaggio. Toccalo per inviarlo di nuovo. |

**Offline non è un errore.** Se il tuo interlocutore non è raggiungibile, il
messaggio resta a una spunta finché non viene ritirato -- non è perso. Se è
il tuo dispositivo stesso a non avere connessione, il messaggio resta
all'orologio e parte da solo appena c'è di nuovo un percorso. Il simbolo
di avviso compare solo quando il messaggio per 14 giorni non ha trovato
alcun percorso; allora puoi inviarlo di nuovo.

Vale anche per un iPhone con l'app non aperta: il messaggio aspetta nella
mailbox finché iOS non riattiva brevemente l'app o finché il tuo
interlocutore non la apre. Questo può richiedere più tempo che su altri
dispositivi.

Due spunte esistono solo quando il destinatario conferma la ricezione di
persona. Questa ricevuta è cifrata e firmata -- nessuno lungo il tragitto
può falsificarla per fingerti una consegna.

### Inviare immagini, video e file

Hai diverse possibilità:

- **Icona della clip** nel campo di immissione: toccala per selezionare un
  file, un'immagine o un video dalla tua galleria o dal tuo file system.
- **Drag and drop** (desktop): trascina semplicemente un file nella
  finestra della chat.
- **Incolla dagli appunti** (desktop): copia un'immagine e incollala nella
  chat.

I file piccoli (sotto 256 KB) viaggiano direttamente dentro il messaggio.
I file più grandi vengono suddivisi in pezzi e forniti di correzione degli
errori, così che singoli pezzi persi non fanno differenza. Se siete online
entrambi, vengono trasmessi in streaming attraverso un vicino; altrimenti
vengono depositati presso dispositivi costantemente raggiungibili, finché
il tuo interlocutore non li ritira.

A partire da 256 KB Cleona ti chiede per ogni file, prima che venga
inviato: un file grande non può prendere il percorso dei tuoi messaggi.
Il suo contenuto resta cifrato, e il tuo interlocutore non viene a sapere
il tuo indirizzo Internet. Ma la trasmissione è visibile dall'esterno come
evento, e un dispositivo estraneo che la inoltra o la conserva vede chi
carica e chi scarica. Il tuo consenso vale solo per quel singolo file.

### Messaggi vocali

1. Tieni premuto il pulsante del microfono nel campo di immissione.
2. Parla il tuo messaggio.
3. Rilascia il pulsante per inviare il messaggio.

Se sul tuo dispositivo è attivo il riconoscimento vocale (vedi
impostazioni), il tuo messaggio vocale viene trascritto automaticamente in
testo. Il tuo interlocutore vede allora sia la registrazione sia il testo
trascritto.

### Rispondere ai messaggi (citazione)

Per rispondere a un messaggio specifico:

1. Apri il menu dei tre punti accanto al messaggio.
2. Seleziona "Rispondi".
3. Sopra il campo di immissione compare un banner con il messaggio citato.
4. Scrivi la tua risposta e inviala.

Il messaggio citato viene mostrato nella tua risposta, così che il
riferimento sia chiaro.

### Modificare ed eliminare i messaggi

- **Modificare:** menu dei tre punti del messaggio, poi "Modifica". Cambia
  il testo e invialo di nuovo. Il tuo interlocutore vede che il messaggio
  è stato modificato. La modifica è possibile entro 15 minuti
  dall'invio.
- **Eliminare:** menu dei tre punti del messaggio, poi "Elimina". Il
  messaggio viene rimosso da te e dal tuo interlocutore. Puoi eliminare i
  tuoi messaggi in qualsiasi momento -- non c'è alcuna finestra temporale
  per l'eliminazione.

### Reazioni emoji

Invece di scrivere una risposta, puoi reagire a un messaggio con un emoji:

1. Apri il menu dei tre punti o tieni premuto a lungo il messaggio.
2. Scegli un emoji dalla selezione rapida o apri il selettore emoji per
   la selezione completa.
3. La tua reazione compare sotto il messaggio.

### Copiare testo

Tramite il menu dei tre punti di un messaggio puoi copiare il testo del
messaggio negli appunti.

### Cercare i messaggi

In alto nella finestra della chat trovi la funzione di ricerca. Inserisci un
termine di ricerca e Cleona ti mostra tutte le corrispondenze nella chat
attuale. Con i tasti freccia puoi saltare avanti e indietro tra le
corrispondenze.

Nella pagina iniziale c'è in più un filtro di ricerca tra le schede, con
cui puoi cercare un termine in tutte le conversazioni.

### Anteprima dei link

Quando invii un link, Cleona genera automaticamente un'anteprima (titolo,
descrizione, immagine di anteprima). Questa anteprima viene creata dal tuo
dispositivo e inviata insieme -- il tuo interlocutore non deve stabilire
alcuna connessione al sito web linkato.

Cosa fa un tocco su un link ricevuto lo imposti nelle impostazioni sotto
"Apertura link": "Normale", "Preferisci una finestra privata" (dove il
dispositivo non può aprire una finestra privata, il link si apre in modo
normale) o "Chiedi ogni volta".

---

## 5. Gruppi

### Creare un gruppo

1. Passa alla scheda "Gruppi".
2. Tocca il pulsante più.
3. Dai un nome al gruppo.
4. Seleziona i contatti che vuoi invitare.
5. Tocca "Crea".

I contatti invitati ricevono una notifica e possono entrare nel gruppo.

### Come sono protetti i messaggi di gruppo

In un gruppo con fino a 16 membri, Cleona invia ogni messaggio a ogni
membro singolarmente -- cifrato solo per quel membro, come se avessi
scritto un messaggio separato a ciascuno. Le spunte su un messaggio di
gruppo mostrano lo stato del membro per cui è progredito meno.

Se il gruppo cresce oltre i 16 membri, usa una chiave comune. Cambia ogni
giorno e viene rinnovata quando un membro esce o viene rimosso; un nuovo
membro legge solo da quando è entrato. Lì le spunte non mostrano più lo
stato di ogni membro, ma che il messaggio è depositato nella rete. Se il
gruppo scende a 12 membri o meno, torna all'invio individuale.

### Immagini nei gruppi e nei canali

Nelle impostazioni di un gruppo o di un canale stabilisci con "Carica
sempre le immagini" se le immagini vengono caricate subito o solo quando
ne tocchi una.

### Invitare membri

Anche dopo la creazione puoi invitare ulteriori contatti:

1. Apri le info del gruppo (menu dei tre punti nella panoramica dei gruppi
   o barra in alto nella chat di gruppo).
2. Tocca "Invita".
3. Seleziona i contatti che vuoi aggiungere.

### Ruoli

Ogni gruppo ha tre ruoli:

- **Proprietario (Owner):** Ha il pieno controllo. Può aggiungere e
  rimuovere membri, nominare amministratori e gestire il gruppo. Il
  proprietario può anche trasferire il proprio stato a un altro membro.
- **Admin:** Può rimuovere membri e aiutare nella gestione.
- **Membro:** Può leggere e scrivere messaggi.

### Lasciare un gruppo

1. Apri il menu dei tre punti nella panoramica dei gruppi.
2. Seleziona "Esci".
3. Conferma la tua decisione.

Quando lasci un gruppo, i tuoi messaggi precedenti restano visibili agli
altri membri.

---

## 6. Canali pubblici

### Cosa sono i canali?

I canali sono forum di discussione pubblici all'interno della rete di
Cleona. A differenza dei gruppi, qui chiunque può leggere senza dover
essere invitato. Solo il proprietario e gli admin possono pubblicare
post -- gli abbonati leggono.

### Trovare e unirsi ai canali

1. Passa alla scheda "Canali".
2. Apri la scheda "Ricerca".
3. Cerca tra i canali disponibili per nome o argomento.
4. Tocca un canale e poi "Abbonati".

I canali possono essere filtrati per lingua. Alcuni canali sono
contrassegnati come "Non adatto ai minorenni" -- questi sono visibili solo
se hai confermato nel tuo profilo di avere più di 18 anni.

### Creare un canale proprio

1. Passa alla scheda "Canali".
2. Tocca il pulsante più.
3. Inserisci un nome per il canale (deve essere univoco in tutta la rete).
4. Scegli la lingua e se il canale deve essere pubblico o privato.
5. Facoltativo: aggiungi una descrizione e un'immagine.
6. Tocca "Crea".

Per i canali pubblici puoi stabilire se il contenuto viene classificato
come "Non adatto ai minorenni".

### Segnalare contenuti

Se noti contenuti inappropriati in un canale pubblico, puoi segnalarli.
Cleona usa un sistema di moderazione decentralizzato: le segnalazioni
vengono valutate da membri della rete selezionati a caso (una sorta di
"giuria"). Se viene accertata una violazione, il canale riceve un
avvertimento. In caso di violazioni ripetute viene retrocesso
nell'indice di ricerca o bloccato.

### Canali di sistema

Cleona dispone di due canali di sistema integrati:

- **Bug Log:** Quando Cleona rileva un errore, ti chiede se vuoi inviare
  una segnalazione di errore; prima vedi esattamente cosa viene
  pubblicato. Queste segnalazioni finiscono nel canale Bug Log, dove
  possono essere consultate dalla community. Una segnalazione non reca né
  un nome né il contenuto delle tue conversazioni, ma uno pseudonimo.
  Nella beta indica inoltre il tuo identificativo (User-ID), così che gli
  sviluppatori possano chiedere ulteriori informazioni. Puoi inviare
  anche manualmente una segnalazione di log (con finestra di anteprima e
  consenso esplicito).
- **Feature Requests:** Qui gli utenti possono inviare desideri di
  funzionalità e votare le proposte esistenti. Le proposte vengono
  ordinate per voti.

Ogni computer conserva fino a 25 MB per canale di sistema, ogni telefono
fino a 5 MB; quando è pieno, se ne va prima il contenuto più vecchio --
mai ciò che hai già visto tu stesso.

---
## 7. Chiamate

### Avviare una chiamata vocale

1. Apri la chat con il contatto che vuoi chiamare.
2. Tocca il simbolo del telefono nella barra in alto.
3. Aspetta che il tuo interlocutore accetti la chiamata.

Durante la conversazione vedi una timeline, la durata della chiamata e hai
accesso a silenziamento e vivavoce.

Per riagganciare, tocca il pulsante rosso di riaggancio.

Se vedi "Non raggiungibile", il dispositivo del tuo interlocutore al momento
non è raggiungibile, per esempio un iPhone con l'app non aperta. Scrivi
invece un messaggio.

### Avviare una videochiamata

1. Apri la chat con il contatto.
2. Tocca il simbolo della fotocamera nella barra in alto.
3. La tua immagine video compare in una piccola finestra, l'immagine del
   tuo interlocutore nell'area grande.

Durante la conversazione puoi passare tra fotocamera anteriore e
posteriore.

### Chiamate in arrivo

Quando qualcuno ti chiama, compare una finestra di notifica con il nome
del chiamante. Puoi:

- **Accetta** -- la conversazione inizia.
- **Rifiuta** -- il chiamante viene avvisato.

Se sei al momento in una conversazione, una nuova chiamata non suona;
ricevi invece un messaggio "Chiamata persa". Vale lo stesso per una
chiamata di gruppo che non hai accettato -- il messaggio compare allora
nella chat di gruppo.

Se qualcuno chiama una delle tue identità che al momento non è
visualizzata, suona comunque; la schermata di chiamata indica quale delle
tue identità viene chiamata.

Sull'iPhone suona solo mentre l'app è aperta. Chi ti chiama mentre non è
aperta vede "Non raggiungibile" dopo 10 secondi. Appena apri l'app, trovi un
messaggio sulla chiamata persa.

### Chiamate di gruppo

Puoi anche tenere chiamate di gruppo a cui partecipano più persone
contemporaneamente. La chiamata è organizzata tramite un albero di
inoltro intelligente, così non ogni partecipante deve essere collegato
direttamente a ogni altro. Tutte le conversazioni sono cifrate per tutta
la durata.

Ogni membro del gruppo può avviare una chiamata di gruppo. Due
partecipanti che non sono contatti l'uno dell'altro non vedono mai
l'indirizzo Internet dell'altro: il loro audio e video passa per un
partecipante che è in contatto con entrambi. Se non esiste, i due non sono
collegati, e il riquadro dice "Nessun contatto in comune nella chiamata".
Se un inoltro è sovraccarico, l'audio resta e il video viene meno per
quella coppia.

### Cifratura delle chiamate

Tutte le chiamate vengono cifrate con chiavi monouso che esistono solo per
la durata della conversazione. Dopo aver riagganciato, queste chiavi
vengono cancellate immediatamente. Nessuno può decifrare a posteriori
una conversazione passata.

Sinceramente: le chiamate avvengono, per quanto possibile, direttamente
tra i dispositivi, perché già un piccolo ritardo disturba parlando. A
differenza dei messaggi, il tuo provider Internet può quindi vedere,
durante una chiamata, con quale indirizzo Internet sei collegato. Quello
che dite non lo vede.

Durante una chiamata anche il tuo contatto vede il tuo indirizzo
Internet. Se con un contatto non lo vuoi, spegni nel suo menu "Consenti
chiamate" (predefinito: acceso). Se lo spegni più tardi, un indirizzo che
ha già visto gli resta noto.

---

## 8. Calendario

Cleona contiene un calendario integrato che funziona in modo cifrato e
completamente decentralizzato -- senza servizio cloud.

### Viste

Il calendario offre cinque viste: giorno, settimana, mese, anno e una
vista attività. Passa dall'una all'altra tramite le schede in alto nella
schermata del calendario.

### Creare appuntamenti

Tocca uno spazio orario o usa il pulsante di aggiunta per creare un nuovo
appuntamento. Puoi inserire titolo, data, ora, luogo e note. Gli
appuntamenti vengono salvati in modo cifrato sul tuo dispositivo.

### Appuntamenti ricorrenti

Gli appuntamenti possono ripetersi giornalmente, settimanalmente,
mensilmente o annualmente. Puoi adattare lo schema (per es. ogni secondo
martedì, il primo di ogni mese) e fissare una data di fine o un numero di
ripetizioni.

### Invitare contatti

Quando crei o modifichi un appuntamento puoi invitare i tuoi contatti
Cleona. Ricevono un invito calendario cifrato e possono rispondere con sì,
no o forse. Le modifiche all'appuntamento vengono inviate automaticamente
a tutti gli invitati.

### Visualizzazione libero/occupato

Puoi condividere la tua disponibilità con i contatti senza rivelare i
dettagli dell'appuntamento. Ci sono tre livelli di riservatezza: dettagli
completi, solo blocchi temporali o nascosto. Puoi impostare un valore
predefinito e sovrascriverlo per singolo contatto.

### Promemoria

Gli appuntamenti possono avere promemoria che attivano una notifica di
sistema prima dell'inizio dell'appuntamento. Se necessario puoi
posticipare i promemoria.

### Sincronizzazione calendario esterno

Cleona può sincronizzarsi con servizi di calendario esterni:

- **CalDAV** -- Collegati a qualsiasi server compatibile con CalDAV
  (Nextcloud, Radicale, ecc.).
- **Google Calendar** -- Sincronizzazione tramite l'API di Google Calendar
  con autenticazione OAuth2 sicura.
- **Server CalDAV locale** -- Cleona può avviare un server CalDAV locale
  sul tuo dispositivo, così che le app calendario da desktop (Thunderbird,
  Outlook, Apple Calendar, Evolution) possano sincronizzarsi con il tuo
  calendario Cleona.
- **Calendario di sistema Android** -- Gli appuntamenti da Cleona possono
  essere trasferiti nell'app calendario integrata del tuo dispositivo
  Android.
- **File ICS** -- Importa ed esporta appuntamenti nel formato standard
  iCalendar.

### Esportazione PDF

Puoi stampare o esportare ogni vista del calendario (giorno, settimana,
mese, anno) come documento PDF.

---

## 9. Sondaggi

Puoi creare sondaggi in ogni chat o gruppo per raccogliere opinioni o
pianificare date.

### Tipi di sondaggio

Cleona supporta cinque tipi di sondaggi:

- **Scelta singola** -- I partecipanti scelgono un'opzione.
- **Scelta multipla** -- I partecipanti possono scegliere più opzioni.
- **Sondaggio per date** -- Trova una data adatta a tutti. Ogni
  partecipante segna le date come disponibili, forse o non disponibili.
- **Scala** -- Valuta qualcosa su una scala numerica (per es. da 1 a 5).
- **Testo libero** -- I partecipanti scrivono la propria risposta.

### Creare un sondaggio

Apri una chat e tocca il simbolo del sondaggio (oppure usa il menu
allegati). Scegli il tipo di sondaggio, formula la tua domanda e le
opzioni, e invia il sondaggio. Compare come messaggio nella chat.

### Votare

Tocca un sondaggio per esprimere il tuo voto. Puoi cambiare o ritirare il
tuo voto in qualsiasi momento.

### Votazione anonima

I sondaggi possono essere configurati per la votazione anonima. Quando
attivata, i voti sono anonimi a livello crittografico -- nessuno, nemmeno
l'autore del sondaggio, può vedere chi ha votato per cosa. Il conteggio
dei voti resta comunque visibile.

### Sondaggio per date nel calendario

Quando un sondaggio per date è concluso, la data vincente può essere
convertita con un tocco direttamente in una voce di calendario.

---
## 10. Più identità

### Perché più identità?

Immagina di voler separare la vita lavorativa e la vita privata -- in
modo simile a due numeri di telefono diversi, ma senza un secondo
telefono. In Cleona puoi usare più identità su un dispositivo. Ogni
identità ha un proprio nome, una propria immagine del profilo, propri
contatti e proprie conversazioni.

### Creare una nuova identità

1. Nella barra in alto vedi la tua identità attuale come scheda.
2. Tocca il segno più (+) a destra delle tue schede di identità.
3. Inserisci un nome per la nuova identità.
4. Fatto -- la nuova identità è subito attiva.

### Passare tra le identità

Tocca semplicemente la scheda di identità nella barra in alto. Il passaggio
è immediato -- nessun tempo di attesa, nessun ricaricamento.

### Tutte attive contemporaneamente

Un punto importante: tutte le tue identità sono attive contemporaneamente.
Anche se al momento sei mostrato come "Lavoro", la tua identità "Privata"
continua a ricevere messaggi. Non ti perdi niente, indipendentemente
dall'identità che hai attualmente selezionato.

### Pagina dei dettagli dell'identità

Quando tocchi la scheda della tua identità attualmente attiva, si apre la
pagina dei dettagli. Qui puoi:

- Mostrare il tuo codice QR per i contatti.
- Cambiare o rimuovere la tua immagine del profilo.
- Aggiungere una descrizione del profilo.
- Cambiare il tuo nome visualizzato.
- Scegliere un tema (skin) per questa identità.
- Eliminare l'identità, se non ti serve più.

### Eliminare un'identità

Quando elimini un'identità, i tuoi contatti ne vengono avvisati. L'identità
e tutti i dati associati vengono rimossi dal tuo dispositivo. Questo
processo non è reversibile.

---

## 11. Più dispositivi

### Un'identità, un dispositivo -- per ora

Un'identità oggi gira su un solo dispositivo. Un secondo dispositivo per
la stessa identità arriverà con una versione successiva; nelle
impostazioni sotto "Dispositivi" -> "Gestisci dispositivi" "Abbina un
altro dispositivo" compare perciò ancora come "Non ancora disponibile".

Quando arriverà, varrà: tutti i dispositivi sono alla pari, non c'è un
dispositivo principale. Un altro dispositivo lo configuri con le tue 24
parole, e uno dei tuoi dispositivi esistenti dà il suo consenso. Al
massimo 5 dispositivi.

Se oggi inserisci le tue 24 parole su un nuovo dispositivo, ti sposti:
l'identità viene ripristinata sul nuovo dispositivo, e il tuo dispositivo
precedente la rimuove poi da sé (vedi capitolo 12).

Su più dispositivi puoi oggi usare identità diverse (capitolo 10).

### Rinnovare le chiavi dell'identità

Se sospetti che qualcuno sia entrato in possesso delle tue chiavi, puoi
generare nuove chiavi sotto "Gestisci dispositivi" -> "Ruota chiavi
identità". I tuoi contatti vengono avvisati, i tuoi inviti aperti vengono
revocati. Importante: dopo, le 24 parole da sole ripristinano solo le
vecchie chiavi. Crea perciò subito dopo un nuovo pacchetto di
ripristino; potrai allora ripristinare solo insieme a questo pacchetto.

---

## 12. Ripristino

### Usare la seed phrase

Quando perdi il tuo dispositivo o ne imposti uno nuovo:

1. Installa Cleona sul nuovo dispositivo.
2. Seleziona all'avvio "Ripristina".
3. Inserisci le tue 24 parole.
4. Cleona genera da queste tutte le tue identità -- con le stesse chiavi
   di prima. Per i tuoi contatti sei la stessa persona.

### Cosa torna -- e cosa no

La tua identità è nelle 24 parole, i tuoi contatti e la tua cronologia
no. Torna il tuo accesso alla rete tramite il **pacchetto di
ripristino**: il tuo dispositivo deposita nella rete un piccolo pacchetto
cifrato. Solo le tue 24 parole possono trovarlo e aprirlo. Dentro c'è
scritto ciò che serve al tuo nuovo dispositivo per raggiungere di nuovo i
tuoi contatti, e ciò che nel frattempo era depositato per te nella rete.
Per questo non deve essere online nessun contatto.

La cronologia delle chat finora esistente, un ripristino non la riporta
indietro.

Il pacchetto di ripristino vive 7 giorni e viene rinnovato dal tuo
dispositivo finché è in funzione; nelle impostazioni vedi fino a quando
vale. Se per più di 7 giorni non è stato attivo nessuno dei tuoi
dispositivi, è scaduto. Le 24 parole ripristinano allora comunque la tua
identità, ma i tuoi contatti devi invitarli di nuovo; ciò che nel
frattempo era depositato per te nella rete è perso.

### Ripristinare significa traslocare

Se il tuo dispositivo finora esistente scopre più tardi che l'identità è
stata ripristinata altrove, la rimuove da sé -- insieme alla sua
cronologia. Perciò: chi ha le tue 24 parole può in questo modo portare
via la tua identità dal tuo dispositivo. Finché non ci sono di nuovo
tutti i contatti, l'app ti ricorda; con "Concludi e rinnova le chiavi"
concludi tu stesso il ripristino.

### Cosa nessuno può ripristinare

Questo è importante, e lo diciamo quindi chiaramente:

- **Nessuno tranne te può ripristinare la tua identità.** Non lo
  sviluppatore, non un supporto, e nemmeno i tuoi contatti -- per quanto
  numerosi siano. Non c'è una chiave master e nessuna parte della tua
  chiave che sia depositata presso altri.
- **Se hai perso le 24 parole e non hai più alcun dispositivo, la tua
  identità è perduta.** Allora resta solo crearne una nuova e invitare
  di nuovo i tuoi contatti.

La protezione migliore: scrivi le 24 parole su carta e conservale al
sicuro.

---
## 13. Impostazioni

Le impostazioni le raggiungi tramite il simbolo dell'ingranaggio nell'angolo
in alto a destra.

### Notifiche e suonerie

- Scegli tra sei suonerie diverse per le chiamate in arrivo.
- Imposta un suono per i messaggi.
- Sui dispositivi Android puoi inoltre attivare o disattivare la
  vibrazione.
- **"Silenzia tutto"** fa sì che su questo dispositivo nessun messaggio
  suoni, vibri o compaia più come notifica -- per tutte le identità. Le
  chiamate continuano a suonare.
- **"Ore di silenzio"** le fissi per ogni identità con da/a. In questo
  tempo nessun messaggio di questa identità suona, vibra o compare come
  notifica; i messaggi arrivano comunque.
- **"Notifiche senza contenuto"** (predefinito: spento) mostra solo che
  è arrivato un messaggio, un invito o un promemoria -- senza mittente,
  nome e testo. Le chiamate continuano a mostrare il nome.
- Ciò che arriva tutto d'un colpo dopo l'avvio, Cleona lo segnala in un
  riepilogo unico ("5 nuovi messaggi in 2 conversazioni"); tutto ciò che
  arriva dopo, singolarmente. Un tocco su una notifica di messaggio apre
  la conversazione, anche in un'altra identità.

### Temi (skin)

Cleona offre dieci temi diversi: Teal, Ocean, Sunset, Forest, Amethyst,
Fire, Storm, Slate, Gold e Contrast. Il tema Contrast soddisfa il livello
più elevato di accessibilità (WCAG AAA) ed è particolarmente leggibile in
caso di vista limitata.

Ogni identità può avere il proprio tema. Cambi il tema nella pagina dei
dettagli dell'identità (tocca la scheda di identità attiva).

Inoltre puoi passare nelle impostazioni, sotto "Aspetto", tra tema chiaro,
scuro e quello di sistema.

### Cambiare lingua

Cleona è disponibile in 34 lingue, incluse lingue con scrittura da destra a
sinistra (per es. arabo, ebraico). Cambia la lingua nelle impostazioni sotto
"Lingua".

### Archiviazione dei media

Se a casa hai un archivio di rete (NAS) o una cartella condivisa, Cleona
può spostare automaticamente lì i tuoi media. Sono supportati SMB, SFTP,
FTPS e WebDAV.

Così funziona la memorizzazione a livelli:
- I primi 30 giorni: tutto resta sul tuo dispositivo.
- Dopo 30 giorni: un'immagine di anteprima resta sul dispositivo, l'originale
  viene archiviato.
- Dopo 90 giorni: resta sul dispositivo solo una piccola immagine di
  anteprima.
- Dopo un anno: resta solo un segnaposto, l'originale si trova al sicuro
  nell'archivio.

Puoi toccare in qualsiasi momento un medium archiviato per recuperarlo --
a patto che tu sia connesso alla tua rete di casa. I media particolarmente
importanti si possono fissare, così che non vengano mai spostati.

Sotto "Budget archiviazione" stabilisci quanti MB di media restano sul
dispositivo (predefinito: 100 MB sul telefono, 2 GB al computer). Quando
è pieno, viene archiviato per primo il medium più vecchio non fissato.
Un originale viene eliminato solo quando si trova al sicuro nell'archivio
-- i messaggi di testo restano sempre conservati.

### Trascrizione per i messaggi vocali

Quando attivata, i tuoi messaggi vocali vengono convertiti in testo
localmente sul tuo dispositivo (con il modello open source Whisper). Il
testo trascritto viene inviato insieme alla registrazione al tuo
interlocutore. La trascrizione avviene interamente sul tuo dispositivo --
nessun dato va a servizi esterni.

Quale modello (tiny, base, small) viene scaricato lo imposti una volta
per il dispositivo; la lingua (automatica o fissa) per ogni identità.

### Download automatico

Puoi impostare da quale dimensione i media debbano essere scaricati
automaticamente. Così puoi, per esempio, far caricare automaticamente le
immagini ma decidere manualmente sui video grandi.

### Dispositivi

Sotto "Dispositivi" -> "Gestisci dispositivi" vedi questo dispositivo.
Abbinare un altro dispositivo arriverà con una versione successiva
(capitolo 11).

### Rete

Cleona non ha bisogno di impostazioni di rete per funzionare. Ci sono
tre interruttori di rete:

- **Apertura porta sul router** (predefinito: acceso). Cleona chiede al tuo
  router di aprire una porta per Cleona. Se funziona, il tuo dispositivo è
  meglio raggiungibile per gli altri e aiuta la rete. Cleona parla in
  questo caso solo con il tuo router, non con Internet.
- **Voci di indirizzo pubbliche** (predefinito: acceso). Se il tuo
  dispositivo ha ancora troppo pochi vicini, cerca ulteriori punti di
  ingresso in un elenco pubblico (Nostr), e se è esso stesso ben
  raggiungibile vi si registra. La voce contiene un indirizzo, nessun nome
  e nessun contatto. Se lo spegni, il tuo dispositivo trova vicini solo più
  tramite inviti, la rete locale e i vicini che già conosce.
- **Meno pacchetti di copertura nel Wi-Fi** (predefinito: spento). Nel
  Wi-Fi o via cavo puoi spegnere i pacchetti di copertura vuoti. Ma allora
  è di nuovo visibile quando scrivi. Non esiste questo interruttore sui
  dati mobili -- lì Cleona inva comunque solo un pacchetto di copertura
  al minuto.

Il traffico di copertura nel suo complesso non si può spegnere. È
intenzionale: solo se scorre sempre, l'attività del tuo dispositivo non
dice nulla su se stai scrivendo in questo momento.

Sopra i tre interruttori si trova la **Modalità risparmio dati**: sui dati
mobili Cleona la propone, ma non la attiva mai da sola. Risparmia dati, in
compenso il tuo dispositivo è più facilmente riconoscibile dall'esterno.

Sotto imposti la **"Cache per i media degli altri"**: il tuo dispositivo
conserva parti cifrate di media altrui fino a 7 giorni, così che
raggiungano i loro destinatari (predefinito: 100 MB sul telefono, 1 GB al
computer). Una dimensione più piccola libera subito lo spazio -- prima
le parti più vecchie.

---

## 14. Sicurezza

### Cosa significa cifratura post-quantum?

La cifratura attuale si basa su problemi matematici che sono estremamente
difficili da risolvere per i computer normali. I computer quantistici
potrebbero risolvere in futuro alcuni di questi problemi rapidamente. La
cifratura post-quantum usa procedure aggiuntive che resistono anche ai
computer quantistici.

Cleona combina entrambi gli approcci: cifratura classica per
affidabilità e procedure post-quantum per la sicurezza futura. Così sei
protetto contemporaneamente contro minacce attuali e future.

Per ogni singolo messaggio viene generata una chiave propria. Anche se un
attaccante decifrasse la chiave di un messaggio, con quella non potrebbe
leggere nessun altro messaggio.

### Perché nessun server è più sicuro

Con i messenger convenzionali i tuoi messaggi passano per i server del
provider. Anche se lì fossero cifrati: il provider ha accesso ai
metadati (chi comunica quando con chi, quanto spesso, da dove) e deve
eventualmente rilasciarli su ordine del giudice.

Con Cleona non c'è un tale punto centrale. Non c'è un luogo in cui
convergono tutti i metadati, e nessun elenco in cui si potrebbe cercare
chi sei o chi conosci.

### Chi vede che stai scrivendo con qualcuno?

La cifratura protegge **cosa** scrivi. Altrettanto importante è che
nessun singolo osservatore venga a sapere **con chi** e **quando** scrivi.
Cleona provvede così:

- **Su Internet mai direttamente.** Se il tuo dispositivo inviasse un
  messaggio direttamente all'indirizzo Internet del tuo interlocutore, il
  tuo provider potrebbe vedere con chi scrivi. Per questo un messaggio su
  Internet passa sempre attraverso i vostri vicini fissi: il tuo e quello
  del tuo interlocutore.
- **Vicini di cui ti fidi.** I tuoi vicini fissi sono, per quanto
  possibile, dispositivi dei tuoi stessi contatti -- fino a tre che sono
  attualmente raggiungibili dall'esterno. Se uno salta, subentra un altro
  contatto. Un contatto non si può comprare con i server; un nodo
  arbitrario nella rete sì. Se non hai ancora un contatto raggiungibile,
  Cleona prende un altro vicino. Il tuo invito non nomina mai nessuno dei
  tuoi contatti, così che nessuno attraverso di esso venga a sapere
  l'indirizzo di un amico.
- **Codici invece di nomi.** I vicini non vedono nomi e identificatori,
  ma solo un codice. Vale esattamente per voi due, in una direzione, per
  un giorno -- il giorno dopo è un altro. Il tuo vicino sa da dove viene
  il pacchetto, ma non dove va a finire. Il vicino del tuo interlocutore
  sa dove va, ma non da dove veniva. Di norma nessuno lungo il tragitto
  vede entrambe le estremità.
- **Il traffico di copertura.** Il tuo dispositivo invia di continuo, a
  intervalli irregolari, pacchetti di copertura ai suoi vicini. Sono
  grandi quanto i pacchetti veri, passano per la stessa porta e
  dall'esterno sono indistinguibili da essi. Se in questo momento un
  essere umano sta scrivendo o il dispositivo sta solo funzionando non si
  può riconoscere. I tuoi messaggi non aspettano mai il traffico di
  copertura -- partono subito, scorre solo a fianco.

**Quanto costa il traffico di copertura:** nel Wi-Fi circa 13 MB al
giorno. Sui dati mobili Cleona invia solo un pacchetto di copertura al
minuto, sono circa 1,7 MB al giorno. Il motivo della limitazione sui
dati mobili non è il volume dei dati, ma la batteria: ogni pacchetto
sveglia il modem radio.

**Cosa Cleona non può nascondere** -- sinceramente:

- Nessun **singolo** osservatore vede chi scrive con chi -- né il tuo
  provider né i nodi lungo il tragitto. Chi però **controlla entrambe le
  estremità contemporaneamente**, per esempio uno stato che sorveglia la
  tua connessione e quella del tuo interlocutore o prepara entrambi i
  vicini, può nel tempo correlare: pacchetto in uscita da te, poco dopo
  pacchetto in entrata dal tuo interlocutore. Ripetuto abbastanza spesso,
  questo dà una connessione.
- Il traffico di copertura rende più difficile questa correlazione, ma
  non la impedisce. Nasconde singoli messaggi, non il volume: chi invia
  molto aumenta il traffico complessivo del proprio dispositivo.
- Un contatto che è il tuo vicino fisso viene a sapere **quando** e
  **quanto** invii e ricevi -- non con chi e non cosa. Se il pericolo
  viene dal tuo stesso ambiente, puoi esonerarne ogni contatto (vedi
  capitolo 3, "Non usare mai come vicino fisso").
- Se due nuovi utenti hanno solo lo stesso unico vicino, il loro
  messaggio passa per esattamente questo nodo, ed esso vede entrambe le
  estremità. Appena uno dei due ha ulteriori vicini, è finita.
- Il tuo invito contiene i tuoi indirizzi Internet. Chi ha la riga di
  testo vede dove sei online -- dalle solo a persone di cui ti fidi in
  questo senso.
- Un vicino che inoltra vede che due codici scambiano pacchetti -- non
  chi c'è dietro, e non cosa c'è dentro.
- Un segnale di una chiamata in corso può, se il primo vicino al momento
  non risponde, passare per un nodo che vede entrambe le estremità; esso
  viene a sapere che telefonate insieme.
- Un file grande a cui hai dato il tuo consenso, il computer che lo
  inoltra o lo conserva lo vede a entrambe le estremità (vedi capitolo 4).
- Per le chiamate la protezione dal provider non vale, e il tuo contatto
  vede il tuo indirizzo Internet (vedi capitolo 7).

### Cosa succede quando il tuo interlocutore è offline?

1. Cleona avvia contemporaneamente tutti i percorsi adatti: nello stesso
   Wi-Fi direttamente, su Internet attraverso due vicini -- e inoltre la
   mailbox.
2. Per la mailbox Cleona deposita il messaggio cifrato presso tre vicini.
   Appena due confermano la ricezione, vale come depositato.
3. Cleona sceglie per questo preferibilmente vicini presso cui anche il
   tuo interlocutore guarda -- prima il vicino che nomina il suo invito.
4. Il messaggio aspetta lì fino a 7 giorni. Torna il tuo interlocutore,
   lo ritira e ti conferma la ricezione. Solo allora vedi due spunte.

La mailbox può svuotarla solo il tuo interlocutore: ritirare ed
eliminare funziona solo con una chiave che possiede solo lui, e
l'eliminazione avviene solo dopo che ha confermato la ricezione. I
vicini vedono solo pacchetti cifrati sotto un valore che cambia ogni
giorno.

### Gli sconosciuti non passano

Da qualcuno che non è né un tuo contatto né membro di un gruppo in
comune, Cleona accetta esattamente due cose: la richiesta delle tue
chiavi pubbliche, finché uno dei tuoi inviti è ancora aperto, e una
richiesta di contatto. La richiesta deve recare un invito valido da
parte tua, e il mittente deve prima aver risolto un compito di calcolo.
Tutto il resto -- messaggi, chiamate, file -- viene scartato prima
ancora di raggiungere l'app. Chi ha solo il tuo biglietto da visita
stampato non può quindi semplicemente chiamarti. Un membro di un gruppo
in comune ti raggiunge solo in quel gruppo -- con messaggi di gruppo e
chiamate di gruppo, mai singolarmente.

### Anti-censura

Cleona è costruito in modo che sia difficile bloccarlo:

- **Nessun server, nessun indirizzo fisso.** Nell'app non c'è alcun
  indirizzo che si potrebbe bloccare, e la rete non dipende da alcun
  singolo nodo.
- **Nessuna porta fissa.** Ogni dispositivo sceglie al primo avvio una
  porta casuale. Non c'è alcun numero di porta noto con cui si potrebbe
  riconoscere il traffico Cleona.
- **Come dati casuali.** La connessione tra due dispositivi è codificata
  in modo da essere indistinguibile da dati casuali.
- **Molti punti di ingresso.** Ogni invito, ogni vicino e ogni
  dispositivo nello stesso Wi-Fi è un possibile percorso di ritorno
  nella rete.

### Memoria sicura delle chiavi

Sulle piattaforme supportate, Cleona memorizza le tue chiavi di cifratura
nel portachiavi sicuro del sistema operativo (Android Keystore, iOS
Keychain, macOS Keychain). Dove disponibile, questo offre protezione
basata sull'hardware per le tue chiavi.

### Cifratura del database

I tuoi messaggi e le tue conversazioni si trovano in un database cifrato
-- uno separato per ogni identità, ciascuno con una propria chiave.
Cifrato non è solo il database stesso, ma anche i suoi file temporanei;
niente viene scritto in chiaro sul disco, nemmeno per breve tempo.
Impostazioni, contatti e media sono pure memorizzati in modo cifrato.

Le chiavi vengono derivate dalle tue 24 parole ed esistono solo sul tuo
dispositivo. Anche chi si impossessi del tuo dispositivo e ne leggesse i
dati, senza queste chiavi trova solo dati illeggibili.

In chiaro si trova solo dove fai uscire tu stesso contenuti da Cleona:
- quando salvi un file da una chat sul tuo dispositivo,
- quando con il pulsante screenshot metti un'immagine nelle tue immagini,
- quando condividi qualcosa con un'altra app,
- quando imposti l'archiviazione dei media (capitolo 13): gli originali
  archiviati si trovano in chiaro sul tuo archivio di rete di casa, così
  che puoi aprirli lì anche senza Cleona,
- quando sincronizzi gli appuntamenti nel calendario di sistema Android: lì
  altre app con accesso al calendario possono leggerli.

Ciò che è così uscito non viene eliminato con il messaggio e non scade
con esso.

### Protezione sullo schermo

Su Android, Windows e macOS Cleona non consente la registrazione dello
schermo da parte di altre app. Ti serve un'immagine, usa il pulsante
screenshot nella barra in alto: mette l'immagine nelle tue immagini -- in
chiaro. In una conversazione in cui inoltrare non è consentito, non c'è
screenshot.

---

## 15. Aggiornamenti software

### Come ottengo gli aggiornamenti?

Cleona può essere aggiornato in vari modi. L'obiettivo è che tu possa
ricevere aggiornamenti anche quando singole vie di distribuzione
vengono meno o vengono bloccate:

1. **App Store / Play Store:** Appena Cleona comparirà lì e lo avrai
   installato tramite uno store, ricevi gli aggiornamenti come al solito
   tramite lo store. Sull'iPhone gli aggiornamenti arrivano tramite
   TestFlight.
2. **GitHub Releases:** Sulla pagina GitHub del progetto trovi pacchetti
   di installazione firmati per tutte le piattaforme.
3. **Aggiornamenti tramite la rete:** Cleona può procurarsi un
   aggiornamento direttamente tramite la rete -- senza server di
   download. La nuova versione è suddivisa in pezzi con correzione degli
   errori che si distribuiscono nella rete; una parte di essi viaggia
   addirittura nel traffico di copertura. Il tuo dispositivo raccoglie
   abbastanza pezzi e assembla l'aggiornamento. Viene trasferita per lo
   più solo la modifica -- pochi MB invece di tutta l'app. Vale per
   Linux, Windows e Android; su macOS scarichi le nuove versioni dal
   sito web o da GitHub.
4. **Link di invito:** Puoi creare link di invito che contengono tutto
   ciò che serve a un nuovo utente per installare Cleona e collegarsi
   alla rete.
5. **Trasferimento fisico:** In ambienti senza Internet puoi passare
   Cleona ad altri tramite chiavetta USB o nella rete locale.

### Come si svolge un aggiornamento

1. Cleona raccoglie automaticamente in background i pezzi di un nuovo
   aggiornamento e li assembla.
2. Solo quando l'aggiornamento è **completo** e la sua **firma è stata
   verificata** Cleona te lo propone. Non ti viene quindi mai offerto un
   aggiornamento a metà o non verificato.
3. Se tocchi "Installa", l'installazione parte senza ulteriore richiesta.
   Su Android mostra inoltre il sistema la sua finestra di
   installazione.

Le versioni più vecchie non vengono proposte -- un aggiornamento va
sempre solo avanti. Se una versione è così vecchia che non può più
collaborare con la rete, Cleona lo segnala chiaramente e ti chiede di
aggiornare.

### Verifica della firma

Ogni aggiornamento è firmato due volte: con un procedimento classico e
uno post-quantum. Cleona verifica entrambe le firme automaticamente.
Così è garantito che vengano accettati solo aggiornamenti dello
sviluppatore ufficiale -- anche se l'aggiornamento è arrivato tramite la
rete da dispositivi estranei. Un aggiornamento non nasce mai
automaticamente dallo sviluppo, ma solo quando lo sviluppatore lo firma
a mano.

---
## 16. Domande frequenti

### "Posso usare Cleona senza Internet?"

Cleona ha bisogno di una connessione di rete, ma non necessariamente di
Internet: nello stesso Wi-Fi i dispositivi Cleona si trovano da soli e
possono scriversi del tutto senza accesso a Internet. Non devi essere
online contemporaneamente al tuo interlocutore: se è offline, il messaggio
aspetta fino a 7 giorni nella mailbox presso tre vicini, finché non lo
ritira.

### "Cosa succede se perdo la mia seed phrase?"

Finché un dispositivo con la tua identità è ancora attivo, niente è
perso -- lì continui semplicemente a scrivere. Sul dispositivo su cui hai
creato l'identità puoi il più delle volte rileggere di nuovo le 24 parole
(vedi capitolo 2). Non contarci: una reinstallazione elimina questa
copia, e su Android la distrugge anche rimuovere o cambiare il blocco
dello schermo. Se non hai né le parole né un dispositivo, non c'è via di
ritorno -- nemmeno tramite i tuoi contatti, lo sviluppatore o chiunque
altro. Per questo è così importante conservare al sicuro le 24 parole.

### "Qualcuno può leggere i miei messaggi?"

No. Ogni messaggio viene cifrato con una chiave monouso che vale solo per
quel singolo messaggio. Solo tu e il tuo interlocutore potete decifrare il
messaggio. Non c'è un server centrale, nessuna chiave master e nessun
accesso per lo sviluppatore. Anche se un dispositivo inoltra il messaggio
sul percorso di trasporto, vede solo un pasticcio di dati cifrati e un
codice. Il tuo vicino sa che il pacchetto viene da te, ma non a chi è
diretto; il vicino del tuo interlocutore sa a chi è diretto, ma non da
chi viene.

### "Perché non mi serve un numero di telefono?"

Perché la tua identità è puramente crittografica. Invece di un numero di
telefono o di un indirizzo email collegato al tuo vero nome, ti identifica
una coppia di chiavi generata sul tuo dispositivo. I contatti li aggiungi
tramite codice QR, NFC o la riga di testo del tuo invito -- non tramite
una rubrica. Questo significa
più riservatezza, perché il tuo account del messenger non è legato alla
tua identità reale.

### "Come trovo persone su Cleona?"

Cleona non ha volutamente una ricerca contatti per numero di telefono o
nome -- sarebbe un problema di riservatezza. Invece scambi inviti
direttamente: tramite codice QR, NFC o come riga di testo per un'altra
via. È come scambiarsi biglietti da visita invece di cercare in rubrica.

### "Cleona funziona anche all'estero?"

Sì. Finché hai una connessione Internet, Cleona funziona ovunque nel
mondo. Poiché non c'è un server centrale e nessun indirizzo fisso, il
servizio non si può semplicemente spegnere per determinati Paesi. Come
Cleona rende più difficile il blocco è descritto nel capitolo "Sicurezza"
sotto "Anti-censura". Un Paese che blocca ogni traffico sconosciuto alla
frontiera può però fermare anche Cleona.

### "Cleona è gratuito?"

Sì. Cleona è utilizzabile gratuitamente e senza pubblicità. Poiché non c'è
un server centrale, non ci sono nemmeno costi di server per l'esercizio.
Nelle impostazioni sotto "Supporta Cleona" -> "Dona" puoi sostenere
volontariamente lo sviluppo.

### "Il mio messaggio ha solo una spunta -- cosa significa?"

Il messaggio è in viaggio, ma il tuo interlocutore non ha ancora confermato
la ricezione -- il più delle volte perché è attualmente offline. Non è un
errore: il messaggio aspetta fino a 7 giorni nella mailbox. Appena lo
ritira, vedi due spunte. Un orologio significa che ancora nessun percorso
ha portato il messaggio -- parte da solo appena ce n'è uno; un simbolo di
avviso, che per 14 giorni non ha trovato alcun percorso e puoi inviarlo
di nuovo.

### "Perché i messaggi arrivano in ritardo sul mio iPhone?"

iOS non lascia girare le app in modo permanente in background. Cleona viene
riattivata solo brevemente di tanto in tanto; decide iOS quando. Raccoglie
allora tutto. Appena apri l'app, Cleona raccoglie ciò che è stato conservato
per te.

### "Posso passare da WhatsApp a Cleona?"

Sì, ma non puoi trasferire le tue chat di WhatsApp. Cleona e WhatsApp sono
sistemi fondamentalmente diversi. Devi aggiungere i tuoi contatti
singolarmente in Cleona. Il modo più semplice è inviare la riga di testo
del tuo invito ai tuoi contatti. Ogni richiesta che arriva così la
confermi tu stesso sotto "Richieste".

### "Posso usare Cleona su più dispositivi contemporaneamente?"

Non ancora. Un secondo dispositivo per la stessa identità arriverà con
una versione successiva (capitolo 11). Su più dispositivi puoi oggi usare
identità diverse.

### "Come ottengo aggiornamenti se l'app store è bloccato?"

Cleona può procurarsi gli aggiornamenti direttamente tramite la rete,
senza dipendere da un app store, un sito web o un server di download. Se
un altro dispositivo nella rete ha l'ultima versione, il tuo dispositivo
può caricare l'aggiornamento da lì. L'autenticità viene verificata tramite
una firma digitale dello sviluppatore. In alternativa un contatto può
passarti l'app tramite link di invito o chiavetta USB. Di più nel capitolo
"Aggiornamenti software".

---

## Aiuto e contatto

Se hai domande o ti imbatti in un problema, trovi informazioni aggiornate
sul sito web di Cleona e su GitHub. Poiché Cleona è un progetto
decentralizzato, non c'è un'assistenza clienti classica -- ma una
comunità attiva che aiuta volentieri.

---

*Questo manuale descrive Cleona Chat versione 4.2. Singole funzioni
possono cambiare o ampliarsi in versioni più recenti.*
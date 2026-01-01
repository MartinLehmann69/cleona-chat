# Cleona Chat -- Manuale Utente

Version 3.1.125 | Luglio 2026

---

## Indice

1. [Cos'è Cleona Chat?](#1-cose-cleona-chat)
2. [Primi passi](#2-primi-passi)
3. [Contatti](#3-contatti)
4. [Messaggi](#4-messaggi)
5. [Gruppi](#5-gruppi)
6. [Canali pubblici](#6-canali-pubblici)
7. [Chiamate](#7-chiamate)
8. [Calendario](#8-calendario)
9. [Sondaggi](#9-sondaggi)
10. [Identità multiple](#10-identita-multiple)
11. [Multi-Device](#11-multi-device)
12. [Ripristino](#12-ripristino)
13. [Impostazioni](#13-impostazioni)
14. [Sicurezza](#14-sicurezza)
15. [Aggiornamenti software](#15-aggiornamenti-software)
16. [Domande frequenti](#16-domande-frequenti)

---

## 1. Cos'è Cleona Chat?

### Il tuo messenger, i tuoi dati

Cleona Chat è un messenger che funziona completamente senza un server centrale.
I tuoi messaggi viaggiano direttamente dal tuo dispositivo al dispositivo del
tuo interlocutore -- senza passare per la sede di un'azienda, senza cloud, senza
data center. Nessuna azienda può leggere, memorizzare o cedere a terzi i tuoi
messaggi, perché semplicemente non c'è nessuna azienda in mezzo.

### Nessun account, nessun numero di telefono

Con Cleona non ti serve né un numero di telefono né un indirizzo e-mail per
accedere. La tua identità è costituita da una coppia di chiavi crittografiche,
generata automaticamente sul tuo dispositivo al primo avvio. Questo significa:
nessuno può rintracciarti tramite il tuo numero di telefono o il tuo indirizzo
e-mail, a meno che tu stesso non condivida i tuoi dati di contatto.

### Crittografia a prova di futuro

Cleona utilizza la cosiddetta crittografia post-quantistica. Questo significa
che nemmeno i futuri computer quantistici potrebbero decifrare i tuoi
messaggi. Non devi capire i dettagli tecnici -- l'importante è sapere che la
tua comunicazione è protetta nel miglior modo possibile secondo lo stato
attuale della tecnologia.

### Come funziona senza server?

Immagina che tu e i tuoi contatti formiate insieme una rete. Ogni dispositivo
aiuta a inoltrare i messaggi. Se il tuo interlocutore è online in quel
momento, il messaggio arriva direttamente a destinazione. Se il tuo
interlocutore è offline, i contatti in comune memorizzano temporaneamente il
messaggio e lo consegnano non appena il destinatario torna disponibile. I
tuoi contatti sono quindi allo stesso tempo anche la tua rete.

### Piattaforme

Cleona è disponibile per Android, iOS, macOS, Linux e Windows.

---

## 2. Primi passi

### Installare l'app

**Android:**
1. Scarica il file APK dal sito web di Cleona o dalle GitHub Releases.
2. Apri il file sul tuo telefono. Se necessario, consenti l'installazione da
   fonti sconosciute (Android te lo chiederà automaticamente).
3. Tocca "Installa" e attendi che l'installazione sia completata.

**iOS:**
1. Apri il link di invito TestFlight sul tuo iPhone.
2. Tocca "Installa". TestFlight è il canale ufficiale di Apple per
   distribuire app beta.
3. Dopo l'installazione troverai Cleona sulla tua schermata Home.

**macOS:**
1. Scarica il file DMG dal sito web di Cleona o dalle GitHub Releases.
2. Apri il DMG e trascina Cleona nella cartella Applicazioni.
3. Al primo avvio macOS potrebbe chiederti se vuoi aprire l'app di uno
   sviluppatore identificato -- conferma.

**Linux (Ubuntu/Debian):**
1. Scarica il file .deb dal sito web di Cleona o dalle GitHub Releases.
2. Installa con doppio clic oppure da terminale: `sudo dpkg -i cleona-chat_VERSION_amd64.deb`
3. Avvia Cleona dal menu delle applicazioni o da terminale con `cleona-chat`.

**Linux (Fedora/openSUSE):**
1. Scarica il file .rpm dal sito web di Cleona o dalle GitHub Releases.
2. Installa con: `sudo dnf install cleona-chat-VERSION.x86_64.rpm`
3. Avvia Cleona dal menu delle applicazioni o da terminale con `cleona-chat`.

**Linux (tutte le distribuzioni -- AppImage):**
1. Scarica il file .AppImage dal sito web di Cleona o dalle GitHub Releases.
2. Rendi il file eseguibile: tasto destro, Proprietà, Eseguibile, oppure da
   terminale: `chmod +x cleona-chat-VERSION-x86_64.AppImage`
3. Avvia con doppio clic oppure da terminale: `./cleona-chat-VERSION-x86_64.AppImage`

**Windows:**
1. Scarica l'installer dal sito web di Cleona o dalle GitHub Releases.
2. Esegui il file di installazione e segui le istruzioni.
3. Avvia Cleona dal menu Start o dal collegamento sul desktop.

### Creare un'identità

Al primo avvio Cleona crea automaticamente una nuova identità per te. Puoi
scegliere un nome visualizzato -- il nome che vedranno i tuoi contatti.
Questo nome può essere modificato in qualsiasi momento.

### Annotare la Seed-Phrase -- la cosa più importante in assoluto

Dopo aver creato la tua identità, Cleona ti mostra 24 parole. Questa è la tua
**Seed-Phrase** -- la tua chiave personale di ripristino.

**Scrivi queste 24 parole su carta e conservale in un luogo sicuro.**

Perché è così importante?

- Se il tuo telefono si rompe, va perso o viene rubato, con queste 24 parole
  puoi ripristinare l'intera identità su un nuovo dispositivo.
- Senza la Seed-Phrase non c'è modo di tornare indietro. Non esiste un
  pulsante "password dimenticata" né un supporto in grado di restituirti il
  tuo account -- perché non esiste alcun account su un server.
- Non condividere mai la Seed-Phrase con altri. Chi conosce queste parole
  può spacciarsi per te.

Trovi la Seed-Phrase anche in un secondo momento, nelle impostazioni alla
voce "Sicurezza", nel caso volessi rileggerla.

### Aggiungere il primo contatto

Per chattare con qualcuno devi prima aggiungere la persona come contatto. Ci
sono diversi modi per farlo -- tutti spiegati nella sezione successiva.

---

## 3. Contatti

### Scansionare un QR-Code (consigliato)

Il modo più semplice per aggiungere un contatto:

1. Il tuo interlocutore apre la propria pagina dei dettagli dell'identità
   (tocco sul proprio nome nella barra superiore) e ti mostra il suo
   QR-Code.
2. Tocchi il pulsante più e selezioni "Scansiona QR-Code".
3. Inquadra con il telefono il QR-Code del tuo interlocutore.
4. La richiesta di contatto viene inviata automaticamente. Non appena il tuo
   interlocutore la accetta, potete scrivervi.

Se vi incontrate di persona, il QR-Code è il metodo più sicuro, perché sai
esattamente con chi stai scambiando il contatto.

### NFC (avvicinare i telefoni)

Se entrambi i dispositivi supportano l'NFC:

1. Aprite entrambi la funzione Aggiungi contatto.
2. Avvicinate i telefoni schiena contro schiena.
3. I dati di contatto vengono scambiati automaticamente.

L'NFC offre, come il QR-Code, un alto livello di sicurezza, perché lo scambio
funziona solo se siete fisicamente vicini l'uno all'altro.

### Condividere un link (URI cleona://)

Puoi anche inviare il tuo link di contatto via e-mail, SMS o tramite un
altro messenger:

1. Apri la tua pagina dei dettagli dell'identità.
2. Copia il tuo link cleona://.
3. Invia il link alla persona che deve aggiungerti.
4. L'altra persona apre il link, oppure lo incolla nella finestra di dialogo
   Aggiungi contatto.

Attenzione: con questo metodo confidi nel fatto che il link non sia stato
alterato durante la trasmissione. Per i contatti particolarmente sensibili
consigliamo il QR-Code o l'NFC.

### Accettare le richieste di contatto

Quando qualcuno ti invia una richiesta di contatto, questa compare nella tua
Inbox (l'ultima scheda nella barra inferiore). Qui puoi:

- **Accettare** -- la persona viene aggiunta ai tuoi contatti.
- **Rifiutare** -- la richiesta viene scartata.
- **Bloccare** -- la persona non potrà più inviarti richieste.

### Livelli di verifica

Cleona ti mostra quanto è sicuramente confermata l'identità di un contatto:

| Livello | Significato |
|-------|-----------|
| Sconosciuto | Hai ricevuto solo il Node-ID o un link. |
| Visto | Lo scambio di chiavi è andato a buon fine, potete comunicare in modo cifrato. |
| Verificato | Vi siete incontrati di persona e vi siete verificati tramite QR-Code o NFC. |
| Fidato | Hai contrassegnato esplicitamente questo contatto come affidabile. |

Più alto è il livello, più puoi essere sicuro di parlare davvero con la
persona giusta.

---

## 4. Messaggi

### Inviare e ricevere testo

Digita semplicemente il tuo messaggio nel campo di inserimento in basso e
premi Invio o il pulsante Invia. Il tuo messaggio viene automaticamente
cifrato prima di lasciare il tuo dispositivo.

I messaggi in arrivo compaiono nella cronologia della chat. Un segno di
spunta ti mostra se il tuo messaggio è stato consegnato.

### Inviare immagini, video e file

Hai diverse possibilità:

- **Icona graffetta** nel campo di inserimento: toccala per selezionare un
  file, un'immagine o un video dalla tua galleria o dal file system.
- **Trascina e rilascia** (desktop): trascina semplicemente un file nella
  finestra della chat.
- **Incolla dagli appunti** (desktop): copia un'immagine e incollala nella
  chat.

I file piccoli (sotto i 256 KB) vengono inviati direttamente insieme al
messaggio. I file più grandi vengono trasferiti con una procedura in due
fasi: prima il file viene annunciato, poi trasmesso a parti.

### Messaggi vocali

1. Tieni premuto il pulsante del microfono nel campo di inserimento.
2. Parla il tuo messaggio.
3. Rilascia il pulsante per inviare il messaggio.

Se sul tuo dispositivo è attivato il riconoscimento vocale (vedi
Impostazioni), il tuo messaggio vocale viene automaticamente trascritto in
testo. Il tuo interlocutore vedrà sia la registrazione sia il testo
trascritto.

### Rispondere ai messaggi (citazione)

Per rispondere a un messaggio specifico:

1. Apri il menu a tre puntini accanto al messaggio.
2. Seleziona "Rispondi".
3. Sopra il campo di inserimento compare un banner con il messaggio citato.
4. Scrivi la tua risposta e inviala.

Il messaggio citato viene mostrato nella tua risposta, in modo che il
riferimento sia chiaro.

### Modificare ed eliminare i messaggi

- **Modificare:** menu a tre puntini del messaggio, poi "Modifica". Cambia
  il testo e invialo di nuovo. Il tuo interlocutore vedrà che il messaggio è
  stato modificato. La modifica è possibile entro 15 minuti dall'invio.
- **Eliminare:** menu a tre puntini del messaggio, poi "Elimina". Il
  messaggio viene rimosso sia da te che dal tuo interlocutore. Puoi
  eliminare i tuoi messaggi in qualsiasi momento -- non esiste una finestra
  temporale per l'eliminazione.

### Reazioni con emoji

Invece di scrivere una risposta, puoi reagire a un messaggio con
un'emoji:

1. Apri il menu a tre puntini oppure tieni premuto a lungo sul messaggio.
2. Seleziona un'emoji dalla selezione rapida oppure apri il selettore di
   emoji per la scelta completa.
3. La tua reazione compare sotto il messaggio.

### Copiare il testo

Tramite il menu a tre puntini di un messaggio puoi copiare il testo del
messaggio negli appunti.

### Cercare nei messaggi

Nella parte superiore della finestra della chat trovi la funzione di
ricerca. Digita un termine di ricerca e Cleona ti mostrerà tutti i risultati
nella chat corrente. Con i tasti freccia puoi passare da un risultato
all'altro.

Nella schermata principale è disponibile anche un filtro di ricerca
trasversale alle schede, con cui puoi cercare un termine in tutte le
conversazioni.

### Anteprima dei link

Quando invii un link, Cleona genera automaticamente un'anteprima (titolo,
descrizione, immagine di anteprima). Questa anteprima viene creata dal tuo
dispositivo e inviata insieme al link -- il tuo interlocutore non deve
stabilire alcuna connessione con il sito web collegato.

Se tocchi un link ricevuto, ti verrà chiesto se vuoi aprirlo nel browser
normale, in modalità in incognito, oppure non aprirlo affatto.

---

## 5. Gruppi

### Creare un gruppo

1. Passa alla scheda "Gruppi".
2. Tocca il pulsante più.
3. Dai un nome al gruppo.
4. Seleziona i contatti che vuoi invitare.
5. Tocca "Crea".

I contatti invitati ricevono una notifica e possono unirsi al gruppo.

### Invitare membri

Anche dopo la creazione puoi invitare ulteriori contatti:

1. Apri le informazioni del gruppo (menu a tre puntini nella panoramica del
   gruppo oppure barra superiore nella chat di gruppo).
2. Tocca "Invita".
3. Seleziona i contatti che vuoi aggiungere.

### Ruoli

Ogni gruppo ha tre ruoli:

- **Proprietario (Owner):** ha il controllo completo. Può aggiungere e
  rimuovere membri, nominare admin e gestire il gruppo. Il proprietario può
  anche trasferire il proprio status a un altro membro.
- **Admin:** può rimuovere membri e aiutare nella gestione.
- **Membro:** può leggere e scrivere messaggi.

### Lasciare un gruppo

1. Apri il menu a tre puntini nella panoramica del gruppo.
2. Seleziona "Esci".
3. Conferma la tua decisione.

Se lasci un gruppo, i tuoi messaggi precedenti restano visibili per gli
altri membri.

---

## 6. Canali pubblici

### Cosa sono i canali?

I canali sono forum di discussione pubblici all'interno della rete Cleona.
A differenza dei gruppi, qui chiunque può leggere senza dover essere
invitato. Solo il proprietario e gli admin possono pubblicare contenuti --
gli abbonati leggono soltanto.

### Trovare e unirsi ai canali

1. Passa alla scheda "Canali".
2. Apri la scheda "Cerca".
3. Cerca tra i canali disponibili per nome o argomento.
4. Tocca un canale e poi "Abbonati".

I canali possono essere filtrati per lingua. Alcuni canali sono
contrassegnati come "Vietato ai minori" -- questi sono visibili solo se hai
confermato nel tuo profilo di avere più di 18 anni.

### Creare un canale personale

1. Passa alla scheda "Canali".
2. Tocca il pulsante più.
3. Inserisci un nome per il canale (deve essere univoco in tutta la rete).
4. Scegli la lingua e se il canale deve essere pubblico o privato.
5. Facoltativo: aggiungi una descrizione e un'immagine.
6. Tocca "Crea".

Per i canali pubblici puoi stabilire se il contenuto viene classificato
come "Vietato ai minori".

### Segnalare i contenuti

Se in un canale pubblico noti contenuti inappropriati, puoi segnalarli.
Cleona utilizza un sistema di moderazione decentralizzato: le segnalazioni
vengono valutate da membri della rete selezionati casualmente (una sorta di
"giuria popolare"). Se viene accertata una violazione, il canale riceve un
avvertimento. In caso di violazioni ripetute, viene retrocesso nell'indice
di ricerca o bloccato.

### Canali di sistema

Cleona dispone di due canali di sistema integrati:

- **Bug Log:** quando Cleona rileva un errore, ti chiede se vuoi inviare un
  report di errore anonimizzato. Questi report finiscono nel canale Bug Log,
  dove possono essere consultati dalla community. Non vengono trasmessi
  dati personali -- solo descrizioni tecniche dell'errore. Puoi anche
  inviare manualmente un report di log (con finestra di anteprima e
  consenso esplicito).
- **Feature Requests:** qui gli utenti possono inviare richieste di
  funzionalità e votare le proposte esistenti. Le proposte vengono ordinate
  in base ai voti.

Entrambi i canali di sistema hanno un limite di dimensione di 25 MB e sono
supervisionati dal sistema di moderazione a giuria.

---

## 7. Chiamate

### Avviare una chiamata vocale

1. Apri la chat con il contatto che vuoi chiamare.
2. Tocca l'icona del telefono nella barra superiore.
3. Attendi che il tuo interlocutore accetti la chiamata.

Durante la conversazione vedi una barra con la durata della chiamata e hai
accesso alle funzioni di silenziamento e altoparlante.

Per riagganciare, tocca il pulsante rosso di chiusura chiamata.

### Avviare una videochiamata

1. Apri la chat con il contatto.
2. Tocca l'icona della fotocamera nella barra superiore.
3. La tua immagine video compare in una piccola finestra, l'immagine del
   tuo interlocutore nell'area grande.

Durante la conversazione puoi passare dalla fotocamera anteriore a quella
posteriore.

### Chiamate in arrivo

Quando qualcuno ti chiama, compare una finestra di notifica con il nome di
chi chiama. Puoi:

- **Accettare** -- la conversazione inizia.
- **Rifiutare** -- chi chiama viene avvisato.

Se sei già in una conversazione, una nuova chiamata viene rifiutata
automaticamente.

### Chiamate di gruppo

Puoi anche effettuare chiamate di gruppo, a cui partecipano più persone
contemporaneamente. La chiamata viene organizzata tramite un albero di
inoltro intelligente, in modo che non sia necessario che ogni partecipante
sia collegato direttamente con ogni altro. Tutte le conversazioni sono
cifrate end-to-end.

### Crittografia delle chiamate

Tutte le chiamate vengono cifrate con chiavi univoche, che esistono solo
per la durata della conversazione. Dopo aver riagganciato, queste chiavi
vengono immediatamente eliminate. Nessuno può decifrare a posteriori una
conversazione passata.

---

## 8. Calendario

Cleona include un calendario integrato che funziona in modo cifrato e
completamente decentralizzato -- senza alcun servizio cloud.

### Viste

Il calendario offre cinque viste: Giorno, Settimana, Mese, Anno e una vista
Attività. Passa da una all'altra tramite le schede nella parte superiore
della schermata del calendario.

### Creare appuntamenti

Tocca uno slot orario oppure usa il pulsante di aggiunta per creare un
nuovo appuntamento. Puoi inserire titolo, data, orario, luogo e note. Gli
appuntamenti vengono salvati in modo cifrato sul tuo dispositivo.

### Appuntamenti ricorrenti

Gli appuntamenti possono ripetersi giornalmente, settimanalmente,
mensilmente o annualmente. Puoi personalizzare lo schema (ad es. ogni
secondo martedì, il primo del mese) e impostare una data di fine oppure un
numero di ripetizioni.

### Invitare contatti

Durante la creazione o la modifica di un appuntamento puoi invitare i tuoi
contatti Cleona. Riceveranno un invito al calendario cifrato e potranno
rispondere con Accetta, Rifiuta o Forse. Le modifiche all'appuntamento
vengono inviate automaticamente a tutti gli invitati.

### Visualizzazione Libero/Occupato

Puoi condividere la tua disponibilità con i contatti senza rivelare i
dettagli degli appuntamenti. Esistono tre livelli di privacy: dettagli
completi, solo blocchi orari oppure nascosto. Puoi impostare un valore
predefinito e sovrascriverlo per singolo contatto.

### Promemoria

Gli appuntamenti possono avere promemoria che attivano una notifica di
sistema prima dell'inizio dell'appuntamento. Puoi posticipare i promemoria
in caso di necessità.

### Sincronizzazione con calendari esterni

Cleona può sincronizzarsi con servizi di calendario esterni:

- **CalDAV** -- collegati a qualsiasi server compatibile con CalDAV
  (Nextcloud, Radicale ecc.).
- **Google Calendar** -- sincronizzazione tramite la Google Calendar API
  con autenticazione sicura OAuth2.
- **Server CalDAV locale** -- Cleona può avviare un server CalDAV locale sul
  tuo dispositivo, in modo che le app calendario desktop (Thunderbird,
  Outlook, Calendario Apple, Evolution) possano sincronizzarsi con il tuo
  calendario Cleona.
- **Calendario di sistema Android** -- gli appuntamenti di Cleona possono
  essere trasferiti nell'app calendario integrata del tuo dispositivo
  Android.
- **File ICS** -- importa ed esporta appuntamenti nel formato standard
  iCalendar.

### Esportazione PDF

Puoi stampare o esportare ogni vista del calendario (Giorno, Settimana,
Mese, Anno) come documento PDF.

---

## 9. Sondaggi

Puoi creare sondaggi in ogni chat o gruppo per raccogliere opinioni o
pianificare appuntamenti.

### Tipi di sondaggio

Cleona supporta cinque tipi di sondaggio:

- **Scelta singola** -- i partecipanti scelgono un'opzione.
- **Scelta multipla** -- i partecipanti possono scegliere più opzioni.
- **Sondaggio per appuntamento** -- trova un appuntamento adatto a tutti.
  Ogni partecipante contrassegna gli appuntamenti come disponibile, forse o
  non disponibile.
- **Scala** -- valuta qualcosa su una scala numerica (ad es. da 1 a 5).
- **Testo libero** -- i partecipanti scrivono la propria risposta.

### Creare un sondaggio

Apri una chat e tocca l'icona del sondaggio (oppure usa il menu degli
allegati). Scegli il tipo di sondaggio, formula la tua domanda e le
opzioni, e invia il sondaggio. Comparirà come messaggio nella chat.

### Votare

Tocca un sondaggio per esprimere il tuo voto. Puoi cambiare o ritirare il
tuo voto in qualsiasi momento.

### Votazione anonima

I sondaggi possono essere configurati per la votazione anonima. Se
attivata, i voti sono crittograficamente anonimi -- nessuno, nemmeno il
creatore del sondaggio, può vedere chi ha votato cosa. Il numero dei voti
resta comunque visibile.

### Da sondaggio per appuntamento a calendario

Quando un sondaggio per appuntamento è concluso, l'appuntamento vincitore
può essere trasformato con un tocco direttamente in una voce di calendario.

---

## 10. Identità multiple

### Perché avere più identità?

Immagina di voler separare la tua vita professionale da quella privata --
un po' come avere due numeri di telefono diversi, ma senza un secondo
telefono. In Cleona puoi utilizzare più identità su un unico dispositivo.
Ogni identità ha un proprio nome, una propria immagine del profilo, propri
contatti e proprie conversazioni.

### Creare una nuova identità

1. Nella barra superiore vedi la tua identità attuale come scheda.
2. Tocca il simbolo più (+) a destra delle tue schede identità.
3. Inserisci un nome per la nuova identità.
4. Fatto -- la nuova identità è immediatamente attiva.

### Passare da un'identità all'altra

Basta toccare la scheda dell'identità nella barra superiore. Il passaggio è
immediato -- nessuna attesa, nessun ricaricamento.

### Sono tutte attive contemporaneamente

Un punto importante: tutte le tue identità sono attive contemporaneamente.
Anche se in quel momento sei mostrato come "Lavoro", la tua identità
"Privato" continua a ricevere messaggi. Non ti perdi nulla, indipendentemente
da quale identità hai selezionato in quel momento.

### Pagina dei dettagli dell'identità

Se tocchi la scheda della tua identità attualmente attiva, si apre la
pagina dei dettagli. Qui puoi:

- Mostrare il tuo QR-Code per i contatti.
- Cambiare o rimuovere la tua immagine del profilo.
- Aggiungere una descrizione del profilo.
- Cambiare il tuo nome visualizzato.
- Scegliere un design (Skin) per questa identità.
- Eliminare l'identità, se non ti serve più.

### Eliminare un'identità

Se elimini un'identità, i tuoi contatti ne vengono informati. L'identità e
tutti i dati correlati vengono rimossi dal tuo dispositivo. Questa
operazione non è reversibile.

---

## 11. Multi-Device

### Usare Cleona su più dispositivi

Puoi usare la stessa identità su un massimo di 5 dispositivi
contemporaneamente. Un dispositivo è quello primario (che detiene la
Seed-Phrase), mentre gli altri dispositivi vengono collegati ad esso.

### Collegare un nuovo dispositivo

1. Apri le impostazioni sul tuo dispositivo primario.
2. Vai su "Dispositivi collegati".
3. Seleziona "Collega nuovo dispositivo".
4. Installa Cleona sul nuovo dispositivo e, all'avvio, seleziona "Collega a
   un dispositivo esistente".
5. Scansiona il QR-Code di pairing mostrato sul tuo dispositivo primario,
   oppure usa il link di pairing.

Il dispositivo collegato riceve un certificato di delega dal dispositivo
primario. I messaggi inviati da un dispositivo collegato sono firmati
crittograficamente con una chiave delegata, in modo che i contatti possano
verificare che il messaggio proviene effettivamente dalla tua identità.

### Come funziona

- Il dispositivo primario detiene la tua Seed-Phrase e le chiavi master.
- I dispositivi collegati ricevono chiavi di firma derivate e un
  certificato di delega -- non ricevono mai la Seed-Phrase stessa.
- Tutti i dispositivi condividono la stessa identità e gli stessi contatti.
  I messaggi arrivano su tutti i dispositivi.
- I certificati di delega vengono rinnovati automaticamente prima della
  scadenza.

### Gestione dei dispositivi

Apri le impostazioni e vai su "Dispositivi collegati" per vedere tutti i
tuoi dispositivi collegati, il loro stato e l'ultima attività. Puoi
revocare un dispositivo collegato in qualsiasi momento, nel caso venga
perso o rubato.

### Rotazione di emergenza delle chiavi

Se sospetti che un dispositivo sia stato compromesso, puoi attivare una
rotazione di emergenza delle chiavi. In questo caso vengono generate nuove
chiavi, e la rotazione deve essere confermata dalla maggioranza dei tuoi
altri dispositivi. Questo impedisce che un singolo dispositivo rubato possa
ruotare le chiavi in autonomia.

---

## 12. Ripristino

### Usare la Seed-Phrase

Se perdi il tuo dispositivo o ne configuri uno nuovo:

1. Installa Cleona sul nuovo dispositivo.
2. Seleziona "Ripristina" all'avvio.
3. Inserisci le tue 24 parole.
4. Cleona ripristina la tua identità e contatta automaticamente i tuoi
   contatti precedenti.
5. I tuoi contatti rispondono con i loro dati di contatto, le appartenenze
   ai gruppi e le cronologie dei messaggi.

Il ripristino avviene in tre fasi:
- Prima tornano i tuoi contatti e gruppi.
- Poi gli ultimi 50 messaggi di ogni conversazione.
- Infine la cronologia completa dei messaggi.

Basta che un solo tuo contatto sia online perché il ripristino funzioni.

### Guardian Recovery (persone di fiducia)

Puoi nominare fino a cinque persone di fiducia come "Guardian". In questo
caso la tua chiave di ripristino viene suddivisa in cinque parti, di cui
ogni Guardian riceve una. Per ripristinare la tua identità bastano tre
delle cinque parti.

Questo significa: anche se hai perso la tua Seed-Phrase, tre dei tuoi
Guardian possono, insieme, ripristinare il tuo account. Nessun Guardian da
solo può accedere ai tuoi dati -- ne servono sempre almeno tre.

Ecco come configurare i Guardian:
1. Apri le impostazioni.
2. Vai su "Sicurezza".
3. Seleziona "Guardian Recovery".
4. Scegli cinque contatti di fiducia.

### Perché i tuoi contatti sono il tuo backup

Nei messenger tradizionali i tuoi dati risiedono sui server del fornitore.
Con Cleona non esiste alcun server -- ma i tuoi contatti assumono questo
ruolo. Quando invii un messaggio, i contatti in comune memorizzano una
copia cifrata nel caso in cui il destinatario sia offline in quel momento.
In caso di ripristino, i tuoi contatti ti restituiscono i tuoi dati.

Questo significa: più contatti attivi hai, più affidabile è il tuo backup.
Un contatto che è regolarmente online è sufficiente per un ripristino
riuscito.

---

## 13. Impostazioni

Puoi raggiungere le impostazioni tramite l'icona a forma di ingranaggio
nell'angolo in alto a destra.

### Notifiche e suonerie

- Scegli tra sei diverse suonerie per le chiamate in arrivo.
- Imposta un suono per i messaggi.
- Sui dispositivi Android puoi inoltre attivare o disattivare la
  vibrazione.

### Design (Skin)

Cleona offre dieci design diversi: Teal, Ocean, Sunset, Forest, Amethyst,
Fire, Storm, Slate, Gold e Contrast. Il design Contrast soddisfa il livello
di accessibilità più elevato (WCAG AAA) ed è particolarmente leggibile in
caso di vista ridotta.

Ogni identità può avere il proprio design. Puoi cambiare il design nella
pagina dei dettagli dell'identità (tocco sulla scheda dell'identità
attiva).

Inoltre, nelle impostazioni alla voce "Aspetto" puoi passare tra tema
chiaro, scuro e tema di sistema.

### Cambiare lingua

Cleona è disponibile in 33 lingue, incluse lingue con scrittura da destra a
sinistra (ad es. arabo, ebraico). Cambia la lingua nelle impostazioni alla
voce "Lingua".

### Limite di archiviazione

Puoi stabilire quanto spazio di archiviazione Cleona può utilizzare sul tuo
dispositivo (tra 100 MB e 2 GB). Quando viene raggiunto il limite, i media
più vecchi vengono automaticamente spostati altrove o eliminati -- i
messaggi di testo restano sempre conservati.

### Archiviazione dei media

Se a casa disponi di un archivio di rete (NAS) o di una cartella
condivisa, Cleona può spostare automaticamente i tuoi media lì. Sono
supportati SMB, SFTP, FTPS e WebDAV.

Ecco come funziona l'archiviazione a livelli:
- I primi 30 giorni: tutto resta sul tuo dispositivo.
- Dopo 30 giorni: un'anteprima resta sul dispositivo, l'originale viene
  archiviato.
- Dopo 90 giorni: resta sul dispositivo solo una piccola anteprima.
- Dopo un anno: resta solo un segnaposto, l'originale è conservato in modo
  sicuro nell'archivio.

Puoi toccare in qualsiasi momento un media archiviato per recuperarlo --
a condizione di essere connesso alla tua rete domestica. I media
particolarmente importanti possono essere fissati, in modo che non vengano
mai spostati.

### Trascrizione per i messaggi vocali

Se attivata, i tuoi messaggi vocali vengono convertiti in testo localmente
sul tuo dispositivo (con il modello open source Whisper). Il testo
trascritto viene inviato al tuo interlocutore insieme alla registrazione.
La trascrizione avviene completamente sul tuo dispositivo -- nessun dato
viene inviato a servizi esterni.

### Download automatico

Puoi impostare a partire da quale dimensione i media vengono scaricati
automaticamente. Così puoi, ad esempio, far scaricare automaticamente le
immagini, ma decidere manualmente per i video di grandi dimensioni.

### Dispositivi collegati

Gestisci i tuoi dispositivi collegati in questa sezione delle impostazioni.
Vedi il capitolo Multi-Device per i dettagli.

---

## 14. Sicurezza

### Cosa significa crittografia post-quantistica?

La crittografia odierna si basa su problemi matematici estremamente
difficili da risolvere per i computer normali. I computer quantistici
potrebbero in futuro risolvere rapidamente alcuni di questi problemi. La
crittografia post-quantistica utilizza procedure aggiuntive che resistono
anche ai computer quantistici.

Cleona combina entrambi gli approcci: crittografia classica per
l'affidabilità e procedure post-quantistiche per la sicurezza futura. In
questo modo sei protetto contemporaneamente dalle minacce di oggi e da
quelle future.

Per ogni singolo messaggio viene generata una chiave propria. Anche se un
aggressore riuscisse a decifrare la chiave di un messaggio, non potrebbe
leggere con essa nessun altro messaggio.

### Perché nessun server è più sicuro

Nei messenger tradizionali i tuoi messaggi passano attraverso i server del
fornitore. Anche se lì fossero cifrati: il fornitore ha accesso ai
metadati (chi comunica quando con chi, quanto spesso, da dove) e in certe
circostanze deve consegnarli su ordine di un giudice.

Con Cleona non esiste un punto centrale del genere. I tuoi messaggi
viaggiano direttamente da dispositivo a dispositivo. Non esiste un luogo in
cui confluiscano tutti i metadati. Nessuno può ricostruire il tuo
comportamento comunicativo a partire da un singolo punto di dati.

### Cosa succede se sei offline?

Se invii un messaggio e il destinatario è offline:

1. Cleona prova prima a consegnare il messaggio direttamente.
2. Se non funziona, viene inoltrato tramite contatti in comune.
3. Contemporaneamente il messaggio viene distribuito, come pezzi cifrati,
   su più nodi della rete (un po' come un puzzle composto da 10 pezzi, di
   cui 7 bastano per ricomporre l'immagine).
4. Il messaggio viene conservato fino a 7 giorni.

Non appena il destinatario torna online, i messaggi vengono consegnati.
Ricevi una conferma quando il tuo messaggio è arrivato.

### Anti-censura

Se la tua rete blocca il metodo di connessione standard (UDP), Cleona
passa automaticamente a una trasmissione alternativa (TLS), più difficile
da riconoscere e bloccare. Questo avviene in modo trasparente -- non devi
configurare nulla.

### Archiviazione sicura delle chiavi

Sulle piattaforme supportate, Cleona memorizza le tue chiavi di
crittografia nel portachiavi sicuro del sistema operativo (Android
Keystore, iOS Keychain, macOS Keychain). Dove disponibile, questo offre
una protezione delle chiavi supportata dall'hardware.

### Crittografia del database

Tutti i tuoi messaggi, contatti e impostazioni sono memorizzati in modo
cifrato sul tuo dispositivo. Anche se qualcuno ottenesse accesso al tuo
file system, senza la tua chiave crittografica non potrebbe leggere nulla.
Questa chiave è derivata dalla tua identità ed esiste solo sul tuo
dispositivo.

### Rete chiusa

Cleona opera come rete chiusa. Ogni pacchetto di rete è autenticato, in
modo che solo dispositivi Cleona legittimi possano partecipare. Questo
impedisce a soggetti esterni di introdurre messaggi falsificati o di
intercettare il traffico di rete.

---

## 15. Aggiornamenti software

### Come ricevo gli aggiornamenti?

Cleona può essere aggiornato in diversi modi. L'obiettivo è che tu possa
ricevere aggiornamenti anche se singoli canali di distribuzione dovessero
non funzionare o essere bloccati:

1. **App Store / Play Store:** se hai installato Cleona tramite un App
   Store, ricevi gli aggiornamenti come al solito tramite lo store.
2. **GitHub Releases:** sulla pagina GitHub del progetto trovi pacchetti
   di installazione firmati per tutte le piattaforme.
3. **Aggiornamenti in rete (In-Network):** se un altro utente Cleona nella
   tua rete dispone già dell'ultima versione, Cleona può scaricare
   l'aggiornamento direttamente tramite la rete P2P -- senza server
   esterni. In questo caso la nuova versione viene suddivisa in frammenti
   con correzione d'errore e distribuita su più nodi. Il tuo dispositivo
   raccoglie abbastanza frammenti e ricompone l'aggiornamento.
   L'autenticità viene verificata tramite una firma Ed25519 dello
   sviluppatore.
4. **Link di invito:** puoi creare link di invito che contengono tutto ciò
   di cui un nuovo utente ha bisogno per installare Cleona e connettersi
   alla rete.
5. **Trasferimento fisico:** in ambienti senza internet puoi trasmettere
   Cleona ad altri tramite chiavetta USB o nella rete locale.

### Notifica di aggiornamento

Quando è disponibile un nuovo aggiornamento, Cleona ti mostra una notifica
nella schermata principale. Se l'aggiornamento è disponibile anche tramite
la rete (In-Network-Update), hai la possibilità di scaricarlo direttamente
dalla rete.

### Distribuzione binaria

Per impostazione predefinita, il tuo dispositivo aiuta a distribuire gli
aggiornamenti ad altri utenti della rete. Se non lo desideri, puoi
disattivare questa funzione nelle impostazioni alla voce "Rete". L'utilizzo
di spazio di archiviazione per i frammenti di aggiornamento è limitato
(5 MB sui dispositivi mobili, 20 MB sui dispositivi desktop) e viene
ripulito regolarmente.

### Verifica della firma

Ogni aggiornamento viene firmato crittograficamente. Cleona verifica
automaticamente la firma prima di installare un aggiornamento. In questo
modo è garantito che vengano accettati solo aggiornamenti dello sviluppatore
ufficiale -- anche se l'aggiornamento è stato ottenuto tramite la rete P2P.

---

## 16. Domande frequenti

### "Posso usare Cleona senza internet?"

No, Cleona necessita di una connessione di rete per inviare e ricevere
messaggi. Tuttavia non devi essere online contemporaneamente al tuo
interlocutore: i messaggi inviati mentre il destinatario è offline vengono
memorizzati temporaneamente e consegnati automaticamente non appena
entrambe le parti sono di nuovo connesse. Nella rete locale (ad es. nella
stessa rete WLAN) potete comunicare tra voi anche senza alcun accesso a
internet.

### "Cosa succede se perdo la mia Seed-Phrase?"

Se hai configurato dei Guardian, tre delle cinque persone di fiducia
possono ripristinare insieme il tuo accesso. Senza Guardian e senza
Seed-Phrase purtroppo non c'è modo di recuperare la tua identità. Per
questo è così importante conservare in modo sicuro le 24 parole.

### "Qualcuno può leggere i miei messaggi?"

No. Ogni messaggio viene cifrato con una chiave univoca, valida solo per
quel singolo messaggio. Solo tu e il tuo interlocutore potete decifrare il
messaggio. Non esiste alcun server centrale, nessuna chiave universale e
nessun accesso per lo sviluppatore. Anche se un dispositivo lungo il
percorso di trasmissione inoltra il messaggio, vede solo dati cifrati
incomprensibili.

### "Perché non ho bisogno di un numero di telefono?"

Perché la tua identità è puramente crittografica. Invece di un numero di
telefono o di un indirizzo e-mail collegato al tuo vero nome, ti identifica
una coppia di chiavi generata sul tuo dispositivo. Aggiungi i contatti
tramite QR-Code, NFC o link -- non tramite una rubrica. Questo significa più
privacy, perché il tuo account messenger non è legato alla tua identità
reale.

### "Come trovo altre persone su Cleona?"

Cleona non dispone volutamente di una ricerca contatti per numero di
telefono o nome -- sarebbe un problema di privacy. Invece scambi i dati di
contatto direttamente: tramite QR-Code, NFC, link cleona:// oppure nei
canali pubblici. È come scambiarsi i biglietti da visita invece di cercare
nell'elenco telefonico.

### "Cleona funziona anche all'estero?"

Sì. Finché hai una connessione internet, Cleona funziona ovunque nel
mondo. Poiché non esiste un server centrale, il servizio non può essere
bloccato per determinati paesi. Cleona dispone inoltre di un fallback
anti-censura: se la connessione normale (UDP) viene bloccata, Cleona passa
automaticamente a una trasmissione alternativa (TLS), più difficile da
riconoscere e bloccare.

### "Cleona è gratuito?"

Sì. Cleona è utilizzabile gratuitamente e senza pubblicità. Poiché non
esiste un server centrale, non ci sono nemmeno costi di gestione dei
server. Nell'app trovi, alla voce "Dona", la possibilità di sostenere
volontariamente lo sviluppo.

### "Il mio messaggio ha un simbolo di orologio -- cosa significa?"

Significa che il messaggio non è ancora stato consegnato. Il tuo
interlocutore probabilmente è offline in questo momento. Non appena il
messaggio viene consegnato, il simbolo cambia. I messaggi vengono
conservati fino a 7 giorni in attesa della consegna.

### "Posso passare da WhatsApp a Cleona?"

Sì, ma non puoi trasferire le tue chat di WhatsApp. Cleona e WhatsApp sono
sistemi completamente diversi. Devi aggiungere i tuoi contatti uno per uno
in Cleona. Il modo più semplice è pubblicare il tuo link cleona:// in un
gruppo WhatsApp e chiedere agli altri di aggiungerti lì.

### "Posso usare Cleona su più dispositivi contemporaneamente?"

Sì. Puoi collegare fino a 5 dispositivi con la stessa identità. Un
dispositivo è quello primario (che detiene la Seed-Phrase), mentre gli
altri dispositivi vengono collegati tramite un processo di pairing sicuro.
Tutti i dispositivi condividono la stessa identità, gli stessi contatti e
le stesse conversazioni. Vedi il capitolo Multi-Device per i dettagli.

### "Come ricevo gli aggiornamenti se l'App Store è bloccato?"

Cleona può ricevere aggiornamenti direttamente tramite la rete P2P, senza
dipendere da un App Store, un sito web o un server di download. Se un
altro utente della rete dispone dell'ultima versione, il tuo dispositivo
può scaricare l'aggiornamento da lì. L'autenticità viene verificata
tramite una firma digitale dello sviluppatore. In alternativa, un contatto
può trasmetterti l'app tramite link di invito o chiavetta USB. Maggiori
informazioni nel capitolo "Aggiornamenti software".

---

## Aiuto e contatti

Se hai domande o incontri un problema, trovi informazioni aggiornate sul
sito web di Cleona e su GitHub. Poiché Cleona è un progetto decentralizzato,
non esiste un supporto clienti tradizionale -- ma una comunità attiva che è
felice di aiutare.

---

*Questo manuale descrive Cleona Chat versione 3.1.125. Alcune funzionalità
possono cambiare o essere ampliate nelle versioni più recenti.*

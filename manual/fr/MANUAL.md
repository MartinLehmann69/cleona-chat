# Cleona Chat -- Manuel utilisateur

Version 3.1.125 | Juillet 2026

---

## Table des matières

1. [Qu'est-ce que Cleona Chat ?](#1-quest-ce-que-cleona-chat)
2. [Premiers pas](#2-premiers-pas)
3. [Contacts](#3-contacts)
4. [Messages](#4-messages)
5. [Groupes](#5-groupes)
6. [Canaux publics](#6-canaux-publics)
7. [Appels](#7-appels)
8. [Calendrier](#8-calendrier)
9. [Sondages](#9-sondages)
10. [Identités multiples](#10-identites-multiples)
11. [Multi-appareils](#11-multi-appareils)
12. [Restauration](#12-restauration)
13. [Paramètres](#13-parametres)
14. [Sécurité](#14-securite)
15. [Mises à jour logicielles](#15-mises-a-jour-logicielles)
16. [Questions fréquentes](#16-questions-frequentes)

---

## 1. Qu'est-ce que Cleona Chat ?

### Ta messagerie, tes données

Cleona Chat est une messagerie qui fonctionne entièrement sans serveur central.
Tes messages transitent directement de ton appareil vers celui de ton
interlocuteur -- sans détour par un siège social, sans cloud, sans centre de
données. Aucune entreprise ne peut lire, stocker ou transmettre tes messages,
car tout simplement aucune entreprise ne s'interpose entre vous.

### Pas de compte, pas de numéro de téléphone

Avec Cleona, tu n'as besoin ni d'un numéro de téléphone ni d'une adresse
e-mail pour te connecter. Ton identité repose sur une paire de clés
cryptographiques, générée automatiquement sur ton appareil au premier
démarrage. Cela signifie que personne ne peut te retrouver via ton numéro de
téléphone ou ton adresse e-mail, à moins que tu ne transmettes toi-même tes
coordonnées.

### Un chiffrement à l'épreuve du futur

Cleona utilise ce qu'on appelle le chiffrement post-quantique. Cela signifie
que même de futurs ordinateurs quantiques ne pourraient pas déchiffrer tes
messages. Tu n'as pas besoin d'en comprendre les détails techniques -- il
suffit de savoir que ta communication est protégée au mieux selon l'état
actuel de la technique.

### Comment cela fonctionne-t-il sans serveur ?

Imagine que toi et tes contacts formez ensemble un réseau. Chaque appareil
aide à relayer les messages. Si ton interlocuteur est en ligne, le message lui
parvient directement. S'il est hors ligne, des contacts communs mettent le
message en attente et le lui remettent dès qu'il est de nouveau disponible.
Tes contacts constituent donc aussi ton réseau.

### Plateformes

Cleona est disponible pour Android, iOS, macOS, Linux et Windows.

---

## 2. Premiers pas

### Installer l'application

**Android :**
1. Télécharge le fichier APK depuis le site web de Cleona ou depuis les
   releases GitHub.
2. Ouvre le fichier sur ton téléphone. Si nécessaire, autorise l'installation
   depuis des sources inconnues (Android te le demandera automatiquement).
3. Appuie sur « Installer » et attends la fin de l'installation.

**iOS :**
1. Ouvre le lien d'invitation TestFlight sur ton iPhone.
2. Appuie sur « Installer ». TestFlight est le moyen officiel d'Apple pour
   distribuer des applications bêta.
3. Après l'installation, tu trouveras Cleona sur ton écran d'accueil.

**macOS :**
1. Télécharge le fichier DMG depuis le site web de Cleona ou depuis les
   releases GitHub.
2. Ouvre le DMG et fais glisser Cleona dans ton dossier Applications.
3. Au premier démarrage, macOS te demandera peut-être si tu souhaites ouvrir
   l'application d'un développeur identifié -- confirme.

**Linux (Ubuntu/Debian) :**
1. Télécharge le fichier .deb depuis le site web de Cleona ou depuis les
   releases GitHub.
2. Installe-le par double-clic ou dans le terminal : `sudo dpkg -i cleona-chat_VERSION_amd64.deb`
3. Démarre Cleona depuis le menu des applications ou dans le terminal avec `cleona-chat`.

**Linux (Fedora/openSUSE) :**
1. Télécharge le fichier .rpm depuis le site web de Cleona ou depuis les
   releases GitHub.
2. Installe-le avec : `sudo dnf install cleona-chat-VERSION.x86_64.rpm`
3. Démarre Cleona depuis le menu des applications ou dans le terminal avec `cleona-chat`.

**Linux (toutes distributions -- AppImage) :**
1. Télécharge le fichier .AppImage depuis le site web de Cleona ou depuis les
   releases GitHub.
2. Rends le fichier exécutable : clic droit, Propriétés, Exécutable, ou dans
   le terminal : `chmod +x cleona-chat-VERSION-x86_64.AppImage`
3. Démarre par double-clic ou dans le terminal : `./cleona-chat-VERSION-x86_64.AppImage`

**Windows :**
1. Télécharge l'installateur depuis le site web de Cleona ou depuis les
   releases GitHub.
2. Exécute le fichier d'installation et suis les instructions.
3. Démarre Cleona depuis le menu Démarrer ou le raccourci sur le bureau.

### Créer une identité

Au premier démarrage, Cleona crée automatiquement une nouvelle identité pour
toi. Tu peux te donner un nom d'affichage -- c'est le nom que verront tes
contacts. Ce nom peut être modifié à tout moment.

### Noter la Seed-Phrase -- l'élément le plus important de tous

Après la création de ton identité, Cleona t'affiche 24 mots. C'est ta
**Seed-Phrase** -- ta clé de récupération personnelle.

**Note ces 24 mots sur papier et conserve-les en lieu sûr.**

Pourquoi est-ce si important ?

- Si ton téléphone est cassé, perdu ou volé, ces 24 mots te permettent de
  restaurer toute ton identité sur un nouvel appareil.
- Sans la Seed-Phrase, il n'y a pas de retour en arrière possible. Il n'existe
  ni bouton « mot de passe oublié » ni support capable de te rendre ton
  compte -- car il n'existe tout simplement aucun compte sur un serveur.
- Ne transmets jamais ta Seed-Phrase à qui que ce soit. Quiconque connaît ces
  mots peut se faire passer pour toi.

Tu retrouveras la Seed-Phrase plus tard dans les paramètres, sous
« Sécurité », si tu souhaites la relire.

### Ajouter ton premier contact

Pour discuter avec quelqu'un, tu dois d'abord ajouter cette personne comme
contact. Il existe plusieurs façons de faire cela -- toutes sont expliquées
dans la section suivante.

---

## 3. Contacts

### Scanner un QR-Code (recommandé)

La façon la plus simple d'ajouter un contact :

1. Ton interlocuteur ouvre sa page de détail d'identité (appui sur son propre
   nom dans la barre supérieure) et te montre son QR-Code.
2. Tu appuies sur le bouton plus et choisis « Scanner un QR-Code ».
3. Place ton téléphone face au QR-Code de ton interlocuteur.
4. La demande de contact est envoyée automatiquement. Dès que ton
   interlocuteur l'accepte, vous pouvez discuter ensemble.

Si vous vous rencontrez en personne, le QR-Code est la méthode la plus sûre,
car tu sais alors exactement avec qui tu échanges le contact.

### NFC (rapprocher les téléphones)

Si les deux appareils prennent en charge le NFC :

1. Ouvrez tous les deux la fonction d'ajout de contact.
2. Tenez vos téléphones dos à dos.
3. Les données de contact sont échangées automatiquement.

Le NFC offre, tout comme le QR-Code, un haut niveau de sécurité, car
l'échange ne fonctionne que si vous êtes physiquement l'un à côté de l'autre.

### Partager un lien (URI cleona://)

Tu peux aussi envoyer ton lien de contact par e-mail, SMS ou via une autre
messagerie :

1. Ouvre ta page de détail d'identité.
2. Copie ton lien cleona://.
3. Envoie le lien à la personne qui doit t'ajouter.
4. L'autre personne ouvre le lien, ou le colle dans la boîte de dialogue
   d'ajout de contact.

Attention : avec cette méthode, tu fais confiance au fait que le lien n'a pas
été modifié en cours de transmission. Pour les contacts particulièrement
sensibles, nous recommandons le QR-Code ou le NFC.

### Accepter les demandes de contact

Quand quelqu'un t'envoie une demande de contact, elle apparaît dans ta boîte
de réception (le dernier onglet de la barre inférieure). Tu peux alors :

- **Accepter** -- la personne est ajoutée à tes contacts.
- **Refuser** -- la demande est rejetée.
- **Bloquer** -- la personne ne peut plus t'envoyer de nouvelles demandes.

### Niveaux de vérification

Cleona t'indique avec quelle certitude l'identité d'un contact est confirmée :

| Niveau | Signification |
|-------|-----------|
| Inconnu | Tu n'as reçu que l'ID de nœud ou un lien. |
| Vu | L'échange de clés a réussi, vous pouvez communiquer de façon chiffrée. |
| Vérifié | Vous vous êtes rencontrés en personne et avez vérifié via QR-Code ou NFC. |
| Fiable | Tu as explicitement marqué ce contact comme digne de confiance. |

Plus le niveau est élevé, plus tu peux être sûr de parler réellement à la
bonne personne.

---

## 4. Messages

### Envoyer et recevoir du texte

Tape simplement ton message dans le champ de saisie en bas et appuie sur
Entrée ou sur le bouton d'envoi. Ton message est automatiquement chiffré
avant de quitter ton appareil.

Les messages entrants apparaissent dans l'historique de la conversation. Une
coche t'indique si ton message a été remis.

### Envoyer des images, vidéos et fichiers

Tu as plusieurs possibilités :

- **Icône trombone** dans le champ de saisie : appuie dessus pour choisir un
  fichier, une image ou une vidéo depuis ta galerie ou ton système de
  fichiers.
- **Glisser-déposer** (ordinateur) : fais simplement glisser un fichier dans
  la fenêtre de discussion.
- **Coller depuis le presse-papiers** (ordinateur) : copie une image et
  colle-la dans la discussion.

Les petits fichiers (moins de 256 Ko) sont envoyés directement. Les fichiers
plus volumineux sont transférés en deux étapes : le fichier est d'abord
annoncé, puis transmis par morceaux.

### Messages vocaux

1. Maintiens le bouton microphone du champ de saisie enfoncé.
2. Prononce ton message.
3. Relâche le bouton pour envoyer le message.

Si la reconnaissance vocale est activée sur ton appareil (voir les
paramètres), ton message vocal est automatiquement transcrit en texte. Ton
interlocuteur voit alors à la fois l'enregistrement et le texte transcrit.

### Répondre à un message (citation)

Pour répondre à un message précis :

1. Ouvre le menu à trois points à côté du message.
2. Choisis « Répondre ».
3. Une bannière avec le message cité apparaît au-dessus du champ de saisie.
4. Écris ta réponse et envoie-la.

Le message cité s'affiche dans ta réponse, de sorte que le lien soit clair.

### Modifier et supprimer des messages

- **Modifier :** menu à trois points du message, puis « Modifier ». Change le
  texte et renvoie-le. Ton interlocuteur voit que le message a été modifié.
  La modification est possible dans les 15 minutes suivant l'envoi.
- **Supprimer :** menu à trois points du message, puis « Supprimer ». Le
  message est retiré chez toi et chez ton interlocuteur. Tu peux supprimer
  tes propres messages à tout moment -- il n'y a pas de délai limite pour la
  suppression.

### Réactions par emoji

Au lieu d'écrire une réponse, tu peux réagir à un message avec un emoji :

1. Ouvre le menu à trois points ou maintiens le message appuyé longuement.
2. Choisis un emoji dans la sélection rapide ou ouvre le sélecteur d'emoji
   pour l'ensemble du choix.
3. Ta réaction apparaît sous le message.

### Copier du texte

Via le menu à trois points d'un message, tu peux copier le texte du message
dans le presse-papiers.

### Rechercher des messages

En haut de la fenêtre de discussion, tu trouves la fonction de recherche.
Saisis un terme de recherche, et Cleona t'affiche tous les résultats dans la
conversation actuelle. Les touches fléchées te permettent de naviguer d'un
résultat à l'autre.

Sur la page d'accueil, il existe en plus un filtre de recherche
inter-onglets, qui te permet de parcourir toutes les conversations à la
recherche d'un terme.

### Aperçu de lien

Quand tu envoies un lien, Cleona génère automatiquement un aperçu (titre,
description, image d'aperçu). Cet aperçu est créé par ton appareil et envoyé
avec le message -- ton interlocuteur n'a pas besoin d'établir de connexion
vers le site lié pour cela.

Quand tu appuies sur un lien reçu, on te demande si tu veux l'ouvrir dans le
navigateur normal, en mode navigation privée, ou pas du tout.

---

## 5. Groupes

### Créer un groupe

1. Passe à l'onglet « Groupes ».
2. Appuie sur le bouton plus.
3. Donne un nom au groupe.
4. Choisis les contacts que tu souhaites inviter.
5. Appuie sur « Créer ».

Les contacts invités reçoivent une notification et peuvent rejoindre le
groupe.

### Inviter des membres

Même après la création, tu peux inviter d'autres contacts :

1. Ouvre les infos du groupe (menu à trois points dans l'aperçu du groupe ou
   barre supérieure dans la discussion de groupe).
2. Appuie sur « Inviter ».
3. Choisis les contacts que tu souhaites ajouter.

### Rôles

Chaque groupe comporte trois rôles :

- **Propriétaire (Owner) :** a le contrôle total. Peut ajouter et retirer des
  membres, nommer des admins et gérer le groupe. Le propriétaire peut aussi
  transférer son statut à un autre membre.
- **Admin :** peut retirer des membres et aider à la gestion.
- **Membre :** peut lire et écrire des messages.

### Quitter un groupe

1. Ouvre le menu à trois points dans l'aperçu du groupe.
2. Choisis « Quitter ».
3. Confirme ta décision.

Quand tu quittes un groupe, tes messages précédents restent visibles pour les
autres membres.

---

## 6. Canaux publics

### Que sont les canaux ?

Les canaux sont des forums de discussion publics au sein du réseau Cleona.
Contrairement aux groupes, tout le monde peut y lire sans avoir besoin d'être
invité. Seuls le propriétaire et les admins peuvent publier des messages --
les abonnés se contentent de lire.

### Trouver des canaux et s'y abonner

1. Passe à l'onglet « Canaux ».
2. Ouvre l'onglet « Recherche ».
3. Parcours les canaux disponibles par nom ou par thème.
4. Appuie sur un canal puis sur « S'abonner ».

Les canaux peuvent être filtrés par langue. Certains canaux sont marqués
« Interdit aux mineurs » -- ceux-ci ne sont visibles que si tu as confirmé
dans ton profil avoir plus de 18 ans.

### Créer son propre canal

1. Passe à l'onglet « Canaux ».
2. Appuie sur le bouton plus.
3. Saisis un nom de canal (doit être unique sur l'ensemble du réseau).
4. Choisis la langue et si le canal doit être public ou privé.
5. Optionnel : ajoute une description et une image.
6. Appuie sur « Créer ».

Pour les canaux publics, tu peux définir si le contenu est classé « Interdit
aux mineurs ».

### Signaler du contenu

Si tu remarques un contenu inapproprié dans un canal public, tu peux le
signaler. Cleona utilise un système de modération décentralisé : les
signalements sont évalués par des membres du réseau sélectionnés au hasard
(une sorte de « jury populaire »). Si une infraction est constatée, le canal
reçoit un avertissement. En cas d'infractions répétées, il est rétrogradé
dans l'index de recherche ou bloqué.

### Canaux système

Cleona dispose de deux canaux système intégrés :

- **Bug Log :** quand Cleona détecte une erreur, il te demande si tu souhaites
  envoyer un rapport d'erreur anonymisé. Ces rapports arrivent dans le canal
  Bug Log, où ils peuvent être consultés par la communauté. Aucune donnée
  personnelle n'est transmise -- uniquement des descriptions techniques
  d'erreurs. Tu peux aussi envoyer manuellement un rapport de log (avec une
  boîte de dialogue d'aperçu et un consentement explicite).
- **Feature Requests :** ici, les utilisateurs peuvent soumettre des
  souhaits de fonctionnalités et voter pour les propositions existantes. Les
  propositions sont triées par nombre de votes.

Les deux canaux système ont une limite de taille de 25 Mo et sont surveillés
par le système de modération par jury.

---

## 7. Appels

### Démarrer un appel vocal

1. Ouvre la discussion avec le contact que tu souhaites appeler.
2. Appuie sur l'icône téléphone dans la barre supérieure.
3. Attends que ton interlocuteur décroche.

Pendant l'appel, tu vois une chronologie indiquant la durée de l'appel et tu
as accès à la mise en sourdine et au haut-parleur.

Pour raccrocher, appuie sur le bouton rouge de fin d'appel.

### Démarrer un appel vidéo

1. Ouvre la discussion avec le contact.
2. Appuie sur l'icône caméra dans la barre supérieure.
3. Ton image vidéo apparaît dans une petite fenêtre, l'image de ton
   interlocuteur dans la zone principale.

Tu peux basculer entre la caméra avant et arrière pendant l'appel.

### Appels entrants

Quand quelqu'un t'appelle, une fenêtre de notification apparaît avec le nom
de l'appelant. Tu peux :

- **Accepter** -- l'appel commence.
- **Refuser** -- l'appelant en est notifié.

Si tu es déjà en communication, un nouvel appel est automatiquement refusé.

### Appels de groupe

Tu peux aussi passer des appels de groupe auxquels plusieurs personnes
participent simultanément. L'appel est organisé via un arbre de relais
intelligent, de sorte que chaque participant n'a pas besoin d'être connecté
directement à tous les autres. Toutes les communications sont chiffrées de
bout en bout.

### Chiffrement des appels

Tous les appels sont chiffrés avec des clés à usage unique, qui n'existent
que pour la durée de l'appel. Après avoir raccroché, ces clés sont
immédiatement supprimées. Personne ne peut déchiffrer ultérieurement une
communication passée.

---

## 8. Calendrier

Cleona intègre un calendrier qui fonctionne de façon chiffrée et entièrement
décentralisée -- sans service cloud.

### Vues

Le calendrier propose cinq vues : jour, semaine, mois, année et une vue
tâches. Bascule entre elles via les onglets en haut de l'écran du calendrier.

### Créer des rendez-vous

Appuie sur un créneau horaire ou utilise le bouton d'ajout pour créer un
nouveau rendez-vous. Tu peux saisir un titre, une date, une heure, un lieu et
des notes. Les rendez-vous sont stockés de façon chiffrée sur ton appareil.

### Rendez-vous récurrents

Les rendez-vous peuvent se répéter quotidiennement, hebdomadairement,
mensuellement ou annuellement. Tu peux adapter le motif (par ex. tous les
deux mardis, le premier du mois) et définir une date de fin ou un nombre de
répétitions.

### Inviter des contacts

Lors de la création ou de la modification d'un rendez-vous, tu peux inviter
tes contacts Cleona. Ils reçoivent une invitation de calendrier chiffrée et
peuvent répondre par « accepter », « refuser » ou « peut-être ». Les
modifications du rendez-vous sont automatiquement envoyées à tous les
invités.

### Affichage libre/occupé

Tu peux partager ta disponibilité avec tes contacts sans révéler les détails
du rendez-vous. Il existe trois niveaux de confidentialité : détails
complets, uniquement des plages horaires, ou masqué. Tu peux définir un
réglage par défaut et le remplacer contact par contact.

### Rappels

Les rendez-vous peuvent avoir des rappels qui déclenchent une notification
système avant le début du rendez-vous. Tu peux reporter les rappels si
besoin.

### Synchronisation avec un calendrier externe

Cleona peut se synchroniser avec des services de calendrier externes :

- **CalDAV** -- connecte-toi à n'importe quel serveur compatible CalDAV
  (Nextcloud, Radicale, etc.).
- **Google Agenda** -- synchronisation via l'API Google Calendar avec une
  authentification OAuth2 sécurisée.
- **Serveur CalDAV local** -- Cleona peut démarrer un serveur CalDAV local
  sur ton appareil, afin que les applications de calendrier de bureau
  (Thunderbird, Outlook, Calendrier Apple, Evolution) puissent se
  synchroniser avec ton calendrier Cleona.
- **Calendrier système Android** -- les rendez-vous de Cleona peuvent être
  transférés vers l'application calendrier intégrée de ton appareil Android.
- **Fichiers ICS** -- importe et exporte des rendez-vous au format standard
  iCalendar.

### Export PDF

Tu peux imprimer ou exporter chaque vue du calendrier (jour, semaine, mois,
année) au format PDF.

---

## 9. Sondages

Tu peux créer des sondages dans n'importe quelle discussion ou groupe pour
recueillir des avis ou planifier des rendez-vous.

### Types de sondages

Cleona prend en charge cinq types de sondages :

- **Choix unique** -- les participants choisissent une option.
- **Choix multiple** -- les participants peuvent choisir plusieurs options.
- **Sondage de date** -- trouve une date qui convient à tout le monde.
  Chaque participant marque les dates comme disponible, peut-être ou non
  disponible.
- **Échelle** -- évalue quelque chose sur une échelle numérique (par ex. de 1
  à 5).
- **Texte libre** -- les participants rédigent leur propre réponse.

### Créer un sondage

Ouvre une discussion et appuie sur l'icône sondage (ou utilise le menu des
pièces jointes). Choisis le type de sondage, formule ta question et les
options, puis envoie le sondage. Il apparaît comme un message dans la
discussion.

### Voter

Appuie sur un sondage pour donner ta voix. Tu peux modifier ou retirer ton
vote à tout moment.

### Vote anonyme

Les sondages peuvent être configurés pour un vote anonyme. Si cette option
est activée, les votes sont cryptographiquement anonymes -- personne, pas
même le créateur du sondage, ne peut voir qui a voté pour quoi. Le nombre de
votes reste néanmoins visible.

### Du sondage de date au calendrier

Quand un sondage de date est terminé, la date gagnante peut être convertie
directement en un événement du calendrier d'un simple appui.

---

## 10. Identités multiples

### Pourquoi plusieurs identités ?

Imagine que tu veuilles séparer ta vie professionnelle et ta vie privée --
un peu comme avec deux numéros de téléphone différents, mais sans second
téléphone. Dans Cleona, tu peux utiliser plusieurs identités sur un seul
appareil. Chaque identité a son propre nom, sa propre photo de profil, ses
propres contacts et ses propres conversations.

### Créer une nouvelle identité

1. Dans la barre supérieure, tu vois ton identité actuelle sous forme
   d'onglet.
2. Appuie sur le signe plus (+) à droite de tes onglets d'identité.
3. Saisis un nom pour la nouvelle identité.
4. C'est fait -- la nouvelle identité est immédiatement active.

### Changer d'identité

Appuie simplement sur l'onglet d'identité dans la barre supérieure. Le
changement est instantané -- pas de temps d'attente, pas de rechargement.

### Toutes fonctionnent simultanément

Point important : toutes tes identités sont actives en même temps. Même si tu
es actuellement affiché comme « Professionnel », ton identité « Privé »
continue de recevoir des messages. Tu ne rates rien, quelle que soit
l'identité actuellement sélectionnée.

### Page de détail de l'identité

Quand tu appuies sur l'onglet de ton identité actuellement active, la page de
détail s'ouvre. Tu peux y :

- Afficher ton QR-Code pour les contacts.
- Modifier ou supprimer ta photo de profil.
- Ajouter une description de profil.
- Modifier ton nom d'affichage.
- Choisir un thème (skin) pour cette identité.
- Supprimer l'identité, si tu n'en as plus besoin.

### Supprimer une identité

Quand tu supprimes une identité, tes contacts en sont notifiés. L'identité et
toutes les données associées sont retirées de ton appareil. Cette opération
est irréversible.

---

## 11. Multi-appareils

### Utiliser Cleona sur plusieurs appareils

Tu peux utiliser la même identité sur jusqu'à 5 appareils simultanément. Un
appareil est le principal (il détient la Seed-Phrase), et les autres
appareils y sont liés.

### Lier un nouvel appareil

1. Ouvre les paramètres sur ton appareil principal.
2. Va dans « Appareils liés ».
3. Choisis « Lier un nouvel appareil ».
4. Installe Cleona sur le nouvel appareil et choisis au démarrage « Lier à un
   appareil existant ».
5. Scanne le QR-Code de jumelage affiché sur ton appareil principal, ou
   utilise le lien de jumelage.

L'appareil lié reçoit un certificat de délégation de la part de l'appareil
principal. Les messages envoyés depuis un appareil lié sont signés
cryptographiquement avec une clé déléguée, ce qui permet à tes contacts de
vérifier que le message provient bien de ton identité.

### Comment cela fonctionne

- L'appareil principal détient ta Seed-Phrase et les clés maîtresses.
- Les appareils liés reçoivent des clés de signature dérivées et un
  certificat de délégation -- ils ne reçoivent jamais la Seed-Phrase
  elle-même.
- Tous les appareils partagent la même identité et les mêmes contacts. Les
  messages arrivent sur tous les appareils.
- Les certificats de délégation sont renouvelés automatiquement avant leur
  expiration.

### Gestion des appareils

Ouvre les paramètres et va dans « Appareils liés » pour voir tous tes
appareils liés, leur statut et leur dernière activité. Tu peux révoquer un
appareil lié à tout moment, s'il est perdu ou volé.

### Rotation d'urgence des clés

Si tu soupçonnes qu'un appareil a été compromis, tu peux déclencher une
rotation d'urgence des clés. De nouvelles clés sont alors générées, et la
rotation doit être confirmée par une majorité de tes autres appareils. Cela
empêche qu'un seul appareil volé puisse faire tourner les clés de sa propre
initiative.

---

## 12. Restauration

### Utiliser la Seed-Phrase

Si tu perds ton appareil ou en configures un nouveau :

1. Installe Cleona sur le nouvel appareil.
2. Choisis « Restaurer » au démarrage.
3. Saisis tes 24 mots.
4. Cleona restaure ton identité et contacte automatiquement tes contacts
   précédents.
5. Tes contacts répondent avec tes données de contact, tes appartenances aux
   groupes et tes historiques de messages.

La restauration se déroule en trois étapes :
- D'abord, tes contacts et groupes reviennent.
- Ensuite, les 50 derniers messages de chaque conversation.
- Enfin, l'historique complet des messages.

Il suffit qu'un seul de tes contacts soit en ligne pour que la restauration
fonctionne.

### Guardian Recovery (personnes de confiance)

Tu peux désigner jusqu'à cinq personnes de confiance comme « Guardians ». Ta
clé de récupération est alors divisée en cinq parts, dont chaque Guardian
reçoit une. Pour restaurer ton identité, trois des cinq parts suffisent.

Cela signifie que même si tu as perdu ta Seed-Phrase, trois de tes Guardians
peuvent restaurer ton compte ensemble. Aucun Guardian seul ne peut accéder à
tes données -- il en faut toujours au moins trois.

Voici comment configurer les Guardians :
1. Ouvre les paramètres.
2. Va dans « Sécurité ».
3. Choisis « Guardian Recovery ».
4. Choisis cinq contacts de confiance.

### Pourquoi tes contacts sont ta sauvegarde

Dans les messageries classiques, tes données se trouvent sur les serveurs du
fournisseur. Avec Cleona, il n'y a pas de serveur -- mais tes contacts
assument ce rôle. Quand tu envoies un message, des contacts communs
conservent une copie chiffrée au cas où le destinataire serait hors ligne.
Lors d'une restauration, tes contacts te renvoient tes données.

Cela signifie : plus tu as de contacts actifs, plus ta sauvegarde est fiable.
Un seul contact régulièrement en ligne suffit pour une restauration réussie.

---

## 13. Paramètres

Tu accèdes aux paramètres via l'icône en forme de roue dentée dans le coin
supérieur droit.

### Notifications et sonneries

- Choisis parmi six sonneries différentes pour les appels entrants.
- Configure un son de message.
- Sur les appareils Android, tu peux en plus activer ou désactiver la
  vibration.

### Thèmes (Skins)

Cleona propose dix thèmes différents : Teal, Ocean, Sunset, Forest, Amethyst,
Fire, Storm, Slate, Gold et Contrast. Le thème Contrast respecte le plus haut
niveau d'accessibilité (WCAG AAA) et est particulièrement lisible en cas de
déficience visuelle.

Chaque identité peut avoir son propre thème. Tu changes le thème dans la
page de détail de l'identité (appui sur l'onglet d'identité actif).

Tu peux en plus, dans les paramètres sous « Apparence », basculer entre le
thème clair, le thème sombre et le thème système.

### Changer de langue

Cleona est disponible en 33 langues, y compris des langues s'écrivant de
droite à gauche (par ex. l'arabe, l'hébreu). Change la langue dans les
paramètres sous « Langue ».

### Limite de stockage

Tu peux définir la quantité d'espace de stockage que Cleona peut utiliser sur
ton appareil (entre 100 Mo et 2 Go). Quand la limite est atteinte, les médias
les plus anciens sont automatiquement déplacés ou supprimés -- les messages
texte sont toujours conservés.

### Archivage des médias

Si tu disposes chez toi d'un stockage réseau (NAS) ou d'un dossier partagé,
Cleona peut y déplacer automatiquement tes médias. SMB, SFTP, FTPS et WebDAV
sont pris en charge.

Voici comment fonctionne le stockage échelonné :
- Les 30 premiers jours : tout reste sur ton appareil.
- Après 30 jours : une image d'aperçu reste sur l'appareil, l'original est
  archivé.
- Après 90 jours : seule une petite image d'aperçu reste sur l'appareil.
- Après un an : seul un espace réservé subsiste, l'original est conservé en
  sécurité dans l'archive.

Tu peux à tout moment appuyer sur un média archivé pour le récupérer -- à
condition d'être connecté à ton réseau domestique. Les médias particulièrement
importants peuvent être épinglés pour ne jamais être déplacés.

### Transcription des messages vocaux

Si cette option est activée, tes messages vocaux sont convertis localement en
texte sur ton appareil (avec le modèle open source Whisper). Le texte
transcrit est envoyé à ton interlocuteur avec l'enregistrement. La
transcription se déroule entièrement sur ton appareil -- aucune donnée n'est
envoyée à des services externes.

### Téléchargement automatique

Tu peux définir à partir de quelle taille les médias doivent être
téléchargés automatiquement. Tu peux ainsi par exemple laisser charger les
images automatiquement, mais décider manuellement pour les grandes vidéos.

### Appareils liés

Gère tes appareils liés dans cette section des paramètres. Voir le chapitre
Multi-appareils pour plus de détails.

---

## 14. Sécurité

### Que signifie le chiffrement post-quantique ?

Le chiffrement actuel repose sur des problèmes mathématiques extrêmement
difficiles à résoudre pour des ordinateurs classiques. Les ordinateurs
quantiques pourraient, à l'avenir, résoudre rapidement certains de ces
problèmes. Le chiffrement post-quantique utilise des procédés supplémentaires
qui résistent aussi aux ordinateurs quantiques.

Cleona combine les deux approches : le chiffrement classique pour la fiabilité
et les procédés post-quantiques pour la pérennité. Tu es ainsi protégé
simultanément contre les menaces actuelles et futures.

Une clé propre est générée pour chaque message individuel. Même si un
attaquant parvenait à casser la clé d'un message, il ne pourrait lire aucun
autre message avec celle-ci.

### Pourquoi l'absence de serveur est plus sûre

Dans les messageries classiques, tes messages passent par les serveurs du
fournisseur. Même s'ils y sont chiffrés, le fournisseur a accès aux métadonnées
(qui communique avec qui, quand, à quelle fréquence, depuis où) et doit
parfois les remettre sur ordonnance judiciaire.

Avec Cleona, il n'existe aucun point central de ce genre. Tes messages
voyagent directement d'appareil à appareil. Il n'existe aucun endroit où
toutes les métadonnées convergent. Personne ne peut reconstituer ton
comportement de communication à partir d'un seul point de données.

### Que se passe-t-il quand tu es hors ligne ?

Quand tu envoies un message et que le destinataire est hors ligne :

1. Cleona essaie d'abord de remettre le message directement.
2. Si cela ne fonctionne pas, il est relayé via des contacts communs.
3. En parallèle, le message est réparti sous forme de fragments chiffrés sur
   plusieurs nœuds du réseau (un peu comme un puzzle de 10 pièces, dont 7
   suffisent pour reconstituer l'image).
4. Le message est conservé jusqu'à 7 jours.

Dès que le destinataire revient en ligne, les messages lui sont remis. Tu
reçois une confirmation quand ton message est arrivé.

### Anti-censure

Si ton réseau bloque la méthode de connexion standard (UDP), Cleona bascule
automatiquement vers une transmission alternative (TLS), plus difficile à
détecter et à bloquer. Cela se fait de façon transparente -- tu n'as rien à
configurer.

### Stockage sécurisé des clés

Sur les plateformes prises en charge, Cleona stocke tes clés de chiffrement
dans le trousseau sécurisé du système d'exploitation (Android Keystore, iOS
Keychain, macOS Keychain). Là où c'est disponible, cela offre une protection
matérielle pour tes clés.

### Chiffrement de la base de données

Tous tes messages, contacts et paramètres sont stockés de façon chiffrée sur
ton appareil. Même si quelqu'un accédait à ton système de fichiers, il ne
pourrait rien lire sans ta clé cryptographique. Cette clé est dérivée de ton
identité et n'existe que sur ton appareil.

### Réseau fermé

Cleona fonctionne comme un réseau fermé. Chaque paquet réseau est
authentifié, de sorte que seuls des appareils Cleona légitimes puissent y
participer. Cela empêche des tiers d'injecter de faux messages ou d'écouter
le trafic réseau.

---

## 15. Mises à jour logicielles

### Comment obtenir des mises à jour ?

Cleona peut être mis à jour de différentes façons. L'objectif est que tu
puisses recevoir des mises à jour même si certains canaux de distribution
tombent en panne ou sont bloqués :

1. **App Store / Play Store :** si tu as installé Cleona via un App Store, tu
   reçois les mises à jour comme d'habitude via le store.
2. **Releases GitHub :** sur la page GitHub du projet, tu trouves des paquets
   d'installation signés pour toutes les plateformes.
3. **Mises à jour intra-réseau :** si un autre utilisateur de Cleona dans ton
   réseau dispose déjà de la dernière version, Cleona peut obtenir la mise à
   jour directement via le réseau P2P -- sans serveur externe. La nouvelle
   version est alors découpée en fragments à correction d'erreurs et répartie
   sur plusieurs nœuds. Ton appareil rassemble suffisamment de fragments et
   reconstitue la mise à jour. L'authenticité est vérifiée par une signature
   Ed25519 du développeur.
4. **Liens d'invitation :** tu peux créer des liens d'invitation contenant
   tout ce dont un nouvel utilisateur a besoin pour installer Cleona et se
   connecter au réseau.
5. **Transfert physique :** dans des environnements sans internet, tu peux
   transmettre Cleona à d'autres via une clé USB ou sur le réseau local.

### Notification de mise à jour

Quand une nouvelle mise à jour est disponible, Cleona t'affiche une
notification sur l'écran d'accueil. Si la mise à jour est aussi disponible
via le réseau (mise à jour intra-réseau), tu as le choix de la télécharger
directement depuis le réseau.

### Distribution binaire

Par défaut, ton appareil aide à transmettre les mises à jour à d'autres
utilisateurs du réseau. Si tu ne le souhaites pas, tu peux désactiver cette
fonction dans les paramètres sous « Réseau ». L'utilisation du stockage pour
les fragments de mise à jour est limitée (5 Mo sur les appareils mobiles, 20
Mo sur les appareils de bureau) et fait l'objet d'un nettoyage régulier.

### Vérification de signature

Chaque mise à jour est signée cryptographiquement. Cleona vérifie
automatiquement la signature avant qu'une mise à jour ne soit installée.
Cela garantit que seules les mises à jour du développeur officiel sont
acceptées -- même si la mise à jour a été obtenue via le réseau P2P.

---

## 16. Questions fréquentes

### « Puis-je utiliser Cleona sans internet ? »

Non, Cleona a besoin d'une connexion réseau pour envoyer et recevoir des
messages. Cependant, tu n'as pas besoin d'être en ligne en même temps que ton
interlocuteur : les messages envoyés pendant que le destinataire est hors
ligne sont mis en cache et remis automatiquement dès que les deux parties
sont de nouveau connectées. Sur un réseau local (par ex. le même WLAN), vous
pouvez aussi communiquer sans aucun accès à internet.

### « Que se passe-t-il si je perds ma Seed-Phrase ? »

Si tu as configuré des Guardians, trois des cinq personnes de confiance
peuvent restaurer ton accès ensemble. Sans Guardians et sans Seed-Phrase, il
n'existe malheureusement aucun moyen de récupérer ton identité. C'est
pourquoi il est si important de conserver les 24 mots en lieu sûr.

### « Quelqu'un peut-il lire mes messages ? »

Non. Chaque message est chiffré avec une clé à usage unique, valable
uniquement pour ce message. Seuls toi et ton interlocuteur pouvez déchiffrer
le message. Il n'existe ni serveur central, ni clé maîtresse, ni accès pour
le développeur. Même si un appareil relaie le message sur le trajet de
transport, il ne voit qu'un amas de données chiffrées.

### « Pourquoi n'ai-je pas besoin de numéro de téléphone ? »

Parce que ton identité est purement cryptographique. Au lieu d'un numéro de
téléphone ou d'une adresse e-mail liée à ton vrai nom, une paire de clés
générée sur ton appareil t'identifie. Tu ajoutes des contacts par QR-Code,
NFC ou lien -- pas via un annuaire téléphonique. Cela signifie plus de vie
privée, car ton compte de messagerie n'est pas lié à ton identité réelle.

### « Comment trouver des gens sur Cleona ? »

Cleona n'a délibérément pas de recherche de contact par numéro de téléphone
ou par nom -- ce serait un problème de confidentialité. Tu échanges plutôt
directement les données de contact : par QR-Code, NFC, lien cleona:// ou dans
des canaux publics. C'est comme échanger des cartes de visite plutôt que de
consulter un annuaire téléphonique.

### « Cleona fonctionne-t-il aussi à l'étranger ? »

Oui. Tant que tu as une connexion internet, Cleona fonctionne partout dans le
monde. Comme il n'y a pas de serveur central, le service ne peut pas non plus
être bloqué pour certains pays. Cleona dispose en outre d'un mécanisme
anti-censure : si la connexion normale (UDP) est bloquée, Cleona bascule
automatiquement vers une transmission alternative (TLS), plus difficile à
détecter et à bloquer.

### « Cleona est-il gratuit ? »

Oui. Cleona est utilisable gratuitement et sans publicité. Comme il n'y a pas
de serveur central, aucun coût de serveur n'est engendré pour son
fonctionnement. Dans l'application, tu trouves sous « Don » la possibilité de
soutenir volontairement le développement.

### « Mon message a un symbole d'horloge -- que signifie-t-il ? »

Cela signifie que le message n'a pas encore été remis. Ton interlocuteur est
probablement hors ligne en ce moment. Dès que le message est remis, le
symbole change. Les messages sont conservés jusqu'à 7 jours en vue de leur
remise.

### « Puis-je passer de WhatsApp à Cleona ? »

Oui, mais tu ne peux pas transférer tes discussions WhatsApp. Cleona et
WhatsApp sont des systèmes fondamentalement différents. Tu dois ajouter tes
contacts un par un dans Cleona. Le plus simple est de poster ton lien
cleona:// dans un groupe WhatsApp et de demander aux autres de t'y ajouter.

### « Puis-je utiliser Cleona sur plusieurs appareils simultanément ? »

Oui. Tu peux lier jusqu'à 5 appareils avec la même identité. Un appareil est
le principal (il détient la Seed-Phrase), et les autres appareils sont liés
via un processus de jumelage sécurisé. Tous les appareils partagent la même
identité, les mêmes contacts et les mêmes conversations. Voir le chapitre
Multi-appareils pour plus de détails.

### « Comment obtenir des mises à jour si l'App Store est bloqué ? »

Cleona peut obtenir des mises à jour directement via le réseau P2P, sans
dépendre d'un App Store, d'un site web ou d'un serveur de téléchargement. Si
un autre utilisateur du réseau dispose de la dernière version, ton appareil
peut charger la mise à jour depuis celui-ci. L'authenticité est vérifiée par
une signature numérique du développeur. Alternativement, un contact peut te
transmettre l'application via un lien d'invitation ou une clé USB. Plus de
détails dans le chapitre « Mises à jour logicielles ».

---

## Aide et contact

Si tu as des questions ou rencontres un problème, tu trouveras des
informations actuelles sur le site web de Cleona et sur GitHub. Comme Cleona
est un projet décentralisé, il n'existe pas de support client classique --
mais une communauté active qui se fera un plaisir de t'aider.

---

*Ce manuel décrit Cleona Chat version 3.1.125. Certaines fonctionnalités
peuvent évoluer ou être étendues dans les versions ultérieures.*

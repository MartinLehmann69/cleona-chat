# Cleona Chat -- Manuel utilisateur

Version 4.2 | À jour en novembre 2026

---

## Table des matières

1. [Qu'est-ce que Cleona Chat ?](#1-quest-ce-que-cleona-chat-)
2. [Premiers pas](#2-premiers-pas)
3. [Contacts](#3-contacts)
4. [Messages](#4-messages)
5. [Groupes](#5-groupes)
6. [Canaux publics](#6-canaux-publics)
7. [Appels](#7-appels)
8. [Calendrier](#8-calendrier)
9. [Sondages](#9-sondages)
10. [Plusieurs identités](#10-plusieurs-identités)
11. [Plusieurs appareils](#11-plusieurs-appareils)
12. [Récupération](#12-récupération)
13. [Paramètres](#13-paramètres)
14. [Sécurité](#14-sécurité)
15. [Mises à jour du logiciel](#15-mises-à-jour-du-logiciel)
16. [Questions fréquentes](#16-questions-fréquentes)

---

## 1. Qu'est-ce que Cleona Chat ?

### Ton messager, tes données

Cleona Chat est un messager qui fonctionne entièrement sans serveur central.
Tes messages voyagent de ton appareil vers l'appareil de ton interlocuteur --
sans détour par un siège d'entreprise, sans nuage, sans centre de données. Là
où un autre appareil aide en chemin, il ne fait que transmettre des paquets
chiffrés. Aucune entreprise ne peut lire, stocker ou transmettre tes messages,
tout simplement parce qu'aucune entreprise ne se trouve au milieu.

### Pas de compte, pas de numéro de téléphone

Avec Cleona, tu n'as besoin ni d'un numéro de téléphone ni d'une adresse e-mail
pour t'inscrire. Ton identité est constituée d'une paire de clés
cryptographiques, générée automatiquement sur ton appareil au premier
démarrage. Cela signifie : personne ne peut te retrouver via ton numéro de
téléphone ou ton adresse e-mail, sauf si tu transmets toi-même tes coordonnées.

### Un chiffrement à l'épreuve du futur

Cleona utilise ce qu'on appelle le chiffrement post-quantique. Cela veut dire :
même les futurs ordinateurs quantiques ne pourraient pas décrypter tes
messages. Tu n'as pas besoin d'en comprendre les détails -- l'important est
seulement que ta communication soit protégée au mieux de l'état actuel de la
technique.

### Comment ça fonctionne sans serveur ?

Le réseau de Cleona est constitué uniquement des appareils de ses
utilisateurs. Chaque appareil est un nœud, aucun nœud n'est plus important
qu'un autre, et chacun ne connaît que ses voisins. Quatre choses rendent ce
réseau particulier :

- **Pas de point fixe.** Aucune adresse de serveur ne figure dans
  l'application, et le réseau ne dépend d'aucun nœud unique. Il n'y a rien
  qu'on pourrait couper pour couper Cleona.
- **Instantané.** Ton message part à l'instant même où tu l'envoies. Il
  n'attend ni cadence ni quoi que ce soit d'autre.
- **Du trafic de couverture en parallèle.** Ton appareil envoie en permanence
  de petits paquets de couverture, afin que de l'extérieur on ne puisse pas
  dire quand tu écris vraiment. Aucun message n'en dépend -- le trafic de
  couverture tourne juste à côté.
- **Des codes au lieu de noms.** Celui qui transmet un message ne voit qu'un
  code, qui change chaque jour. En temps normal, aucun d'entre eux ne connaît
  l'expéditeur et le destinataire à la fois ; les exceptions figurent au
  chapitre 14.

**Trois chemins, tous à la fois.** Quand tu envoies un message, Cleona
n'essaie pas un chemin après l'autre, mais tous les chemins appropriés en
même temps. Dès que ton interlocuteur en confirme la réception, les autres
sont interrompus.

1. **Dans le même réseau :** Si vous êtes dans le même Wi-Fi, le message
   passe directement.
2. **Par les voisins fixes :** Sur Internet, ton appareil remet le message à
   son voisin fixe. Celui-ci le transmet aux voisins fixes de ton
   interlocuteur (jusqu'à trois à la fois), et l'un d'eux le livre.
3. **Boîte aux lettres :** Si ton interlocuteur est hors ligne, Cleona
   dépose le message chiffré chez trois voisins. Il y reste jusqu'à 7 jours.
   Quand ton interlocuteur revient en ligne, il va le récupérer.

**Comment entres-tu dans le réseau ?** Aucune adresse de serveur ne figure dans
l'application. Tu obtiens ton point d'entrée de ton premier contact : son
invitation contient les adresses par lesquelles ton appareil trouve ses
premiers voisins. Dans le même Wi-Fi, les appareils Cleona se trouvent aussi
eux-mêmes. À partir de là, ton appareil apprend d'autres voisins à chaque
voisin qu'il rencontre.

### Plateformes

Cleona est disponible pour Android, iOS, macOS, Linux et Windows. Sur
ordinateur et sur Android, messages et appels arrivent en quelques secondes.
Sur iPhone, c'est le cas tant que l'app est ouverte. Quand elle ne l'est
pas, iOS ne la réveille que brièvement de temps en temps ; iOS décide quand.
Cleona récupère alors tout ce qui a été gardé pour toi et affiche une
notification avec un chiffre sur l'icône de l'app. Les appels n'atteignent
pas un iPhone dont l'app n'est pas ouverte. C'est une règle d'Apple, pas un
défaut de Cleona.

---

## 2. Premiers pas

### Installer l'application

**Android :**
1. Télécharge le fichier APK depuis le site Cleona ou depuis GitHub Releases.
2. Ouvre le fichier sur ton téléphone. Si nécessaire, autorise l'installation
   depuis des sources inconnues (Android te le demande automatiquement).
3. Appuie sur « Installer » et attends que l'installation soit terminée.

**iOS :**
1. Ouvre le lien d'invitation TestFlight sur ton iPhone.
2. Appuie sur « Installer ». TestFlight est le moyen officiel d'Apple pour
   distribuer des applications bêta.
3. Après l'installation, tu trouveras Cleona sur ton écran d'accueil.

**macOS :**
1. Télécharge le fichier DMG depuis le site Cleona ou depuis GitHub Releases.
2. Ouvre le DMG et fais glisser Cleona dans ton dossier Applications.
3. Au premier démarrage, macOS peut te demander si tu veux ouvrir une
   application provenant d'un développeur identifié -- confirme-le.

**Linux (Ubuntu/Debian) :**
1. Télécharge le fichier .deb depuis le site Cleona ou depuis GitHub Releases.
2. Installe-le par un double-clic ou dans le terminal : `sudo dpkg -i cleona-chat-beta_VERSION_amd64.deb`
3. Démarre Cleona depuis le menu des applications ou dans le terminal avec `cleona-chat-beta`.

**Linux (Fedora/openSUSE) :**
1. Télécharge le fichier .rpm depuis le site Cleona ou depuis GitHub Releases.
2. Installe-le avec : `sudo dnf install cleona-chat-beta-VERSION-1.x86_64.rpm`
3. Démarre Cleona depuis le menu des applications ou dans le terminal avec `cleona-chat-beta`.

**Linux (toutes les distributions -- AppImage) :**
1. Télécharge le fichier .AppImage depuis le site Cleona ou depuis GitHub Releases.
2. Rends le fichier exécutable : clic droit, propriétés, exécutable, ou dans le terminal : `chmod +x cleona-chat-beta-VERSION-x86_64.AppImage`
3. Démarre par un double-clic ou dans le terminal : `./cleona-chat-beta-VERSION-x86_64.AppImage`

Les noms de paquets valent pour la version bêta, qui est pour l'instant la
seule version publiée ; elle s'appelle `cleona-chat-beta`.

**Windows :**
1. Télécharge l'installateur depuis le site Cleona ou depuis GitHub Releases.
2. Exécute le fichier d'installation et suis les instructions.
3. Démarre Cleona depuis le menu Démarrer ou le raccourci sur le bureau.

### Créer une identité

Au premier démarrage, Cleona crée automatiquement une nouvelle identité pour
toi. Tu peux te donner un nom d'affichage -- c'est le nom que tes contacts
voient. Ce nom peut être modifié à tout moment.

### Noter sa phrase de récupération -- le plus important de tout

Après la création de ton identité, Cleona t'affiche 24 mots. C'est ta
**phrase de récupération** -- ta clé de récupération personnelle.

**Écris ces 24 mots sur papier et garde-les en sécurité.**

Pourquoi est-ce si important ?

- Si ton téléphone tombe en panne, est perdu ou est volé, tu peux restaurer
  ton identité entière sur un nouvel appareil avec ces 24 mots.
- Sans la phrase de récupération, il n'y a pas de retour possible. Il n'y a
  pas de bouton « mot de passe oublié » et pas de support qui pourrait te
  rendre ton compte -- parce qu'il n'y a tout simplement pas de compte sur un
  serveur. Même tes contacts ne peuvent pas restaurer ton identité, quel que
  soit leur nombre. Un second appareil avec la même identité arrivera avec
  une version ultérieure (voir chapitre 11).
- Ne transmets jamais la phrase de récupération à d'autres. Celui qui connaît
  ces mots peut se faire passer pour toi.

Tu retrouveras aussi les 24 mots plus tard dans les paramètres sous
« Sauvegarde » -> « Afficher la phrase de récupération », au cas où tu
voudrais les relire. Sur Android, tu confirmes pour cela avec ton
verrouillage d'écran.

### Ajouter ton premier contact

Pour discuter avec quelqu'un, tu dois d'abord l'ajouter comme contact. Il y a
plusieurs moyens pour cela -- tous sont expliqués dans la section suivante.

---

## 3. Contacts

### Ton invitation

Les contacts dans Cleona naissent uniquement par une invitation. Ton
invitation est là dès le premier démarrage -- même sans Internet et avant
même que ton appareil ait trouvé un voisin. Tu la trouves sur ta page de
détail de l'identité (appuie sur ton propre nom dans la barre supérieure).

L'invitation existe sous deux formes qui contiennent exactement la même
chose :

- en **code QR**, quand ton interlocuteur se tient à côté de toi, et
- en **ligne de texte**, que tu envoies par e-mail, SMS ou via un autre
  messager.

L'invitation ne contient ni numéro de téléphone ni nom issu d'un annuaire.
Elle contient tes clés publiques et les adresses par lesquelles ton
interlocuteur t'atteint, toi et tes voisins. Pour quelqu'un qui vient juste
d'installer Cleona, ton invitation est donc aussi le point d'entrée dans le
réseau.

### Scanner un code QR (recommandé)

Quand vous vous rencontrez en personne :

1. Tu montres le code QR de ton invitation à ton interlocuteur.
2. Ton interlocuteur appuie sur le bouton plus, choisit « Scanner un code QR »
   et pointe la caméra vers ton écran. Cela fonctionne aussi avec la webcam
   d'un ordinateur.
3. La demande t'est envoyée et est **acceptée automatiquement** -- puisque
   c'est toi qui viens de montrer le code.

Un code QR n'est valable qu'une seule fois : la première demande valide est
acceptée, après quoi l'invitation est consommée. Le code QR est la méthode la
plus sûre, parce que vous savez alors exactement avec qui vous échangez le
contact.

### NFC (rapprocher les téléphones)

Quand les deux appareils prennent en charge le NFC :

1. Ouvrez la fonction d'ajout de contact sur les deux.
2. Maintenez vos téléphones dos à dos l'un contre l'autre.
3. L'invitation est transférée et acceptée automatiquement.

Le NFC offre, comme le code QR, un haut niveau de sécurité, parce que
l'échange ne fonctionne que lorsque vous vous tenez physiquement côte à
côte.

### Envoyer la ligne de texte

Quand vous ne pouvez pas vous rencontrer :

1. Ouvre ton invitation et copie la ligne de texte.
2. Envoie-la à la personne qui est censée t'ajouter -- par e-mail, SMS ou
   via un autre messager.
3. L'autre personne colle la ligne dans Cleona, dans la boîte de dialogue
   d'ajout de contact.
4. La demande apparaît chez toi sous **« Demandes »**. Ici, elle n'est
   **pas** acceptée automatiquement : tu décides toi-même, car tu ne peux pas
   savoir qui d'autre a lu la ligne en chemin.

### Accepter les demandes de contact

Une demande entrante ne crée pas encore un contact. Elle te pose une question
et apparaît dans l'onglet **« Demandes »**. Là, tu vois le nom et le niveau
de vérification, et tu peux choisir :

- **Accepter** -- seulement maintenant la personne devient ton contact.
- **Refuser** -- la demande est écartée.
- **Bloquer** -- la personne ne peut plus t'envoyer d'autres demandes.

### Ne jamais utiliser comme voisin fixe

Dans le menu d'un contact, tu trouves le commutateur **« Ne jamais utiliser
comme voisin fixe »** (par défaut : désactivé). Quand il est activé, ce
contact ne transmet pas de messages pour toi et n'apprend donc pas non plus
quand tu envoies ou reçois des messages. C'est prévu pour le cas où un danger
te menace de ton propre entourage.

De la part d'inconnus (ni un contact ni un membre d'un groupe en commun),
Cleona ne laisse rien passer à part une telle demande
-- aucun message, aucun appel, aucun fichier. Et même la demande n'arrive
que si l'expéditeur a d'abord résolu une petite tâche de calcul. Cela rend
le spam de masse coûteux.

### Niveaux de vérification

Cleona t'indique à quel point l'identité d'un contact est confirmée de façon
sûre :

| Niveau | Signification |
|-------|-----------|
| Non vérifié | Vous êtes connectés, mais rien ne confirme que la bonne personne se trouve vraiment derrière. |
| Vu | L'échange de clés a réussi ; vous pouvez communiquer de façon chiffrée. |
| Vérifié | Vous vous êtes rencontrés en personne et connectés par scan caméra ou NFC. |
| Approuvé | Tu as marqué ce contact explicitement comme digne de confiance. |

« Vérifié » n'existe que pour un échange en personne. Une invitation arrivée
par un chat ou par e-mail n'atteint jamais ce niveau -- même si elle contient
les mêmes données.

Si les clés d'un contact changent sans annonce, Cleona le réinitialise à
« Non vérifié ». Cela te protège contre quelqu'un qui se ferait passer pour
ton contact à ton insu.

---

## 4. Messages

### Envoyer et recevoir du texte

Tape simplement ton message dans le champ de saisie en bas et appuie sur Entrée
ou sur le bouton Envoyer. Ton message est automatiquement chiffré avant de
quitter ton appareil.

Les messages entrants apparaissent dans l'historique du chat.

### Ce que signifient les symboles sur ton message

| Symbole | Signification |
|---------|-----------|
| Horloge | Le message est créé, mais aucun chemin ne l'a encore porté. |
| Un crochet | Le message est en route. Cela vaut aussi tant qu'il attend ton interlocuteur dans la boîte aux lettres. |
| Deux crochets | Livré : l'appareil de ton interlocuteur a confirmé la réception. |
| Icône d'avertissement | Pendant 14 jours, aucun chemin n'a porté le message. Appuie dessus pour le renvoyer. |

**Hors ligne, ce n'est pas une erreur.** Si ton interlocuteur n'est pas
joignable, le message reste à un crochet jusqu'à ce qu'il soit récupéré --
il n'est pas perdu. Si ton propre appareil n'a pas de connexion, le message
reste à l'horloge et repart tout seul dès qu'un chemin est de nouveau là.
L'icône d'avertissement n'apparaît que lorsque le message n'a trouvé aucun
chemin pendant 14 jours ; tu peux alors le renvoyer.

Cela vaut aussi pour un iPhone dont l'app n'est pas ouverte : le message
attend dans la boîte aux lettres jusqu'à ce qu'iOS réveille brièvement l'app
ou que ton interlocuteur l'ouvre. Cela peut prendre plus de temps que sur
d'autres appareils.

Il n'y a deux crochets que lorsque le destinataire confirme lui-même la
réception. Cet accusé de réception est chiffré et signé -- personne en chemin
ne peut le falsifier pour te feindre une livraison.

### Envoyer des images, des vidéos et des fichiers

Tu as plusieurs possibilités :

- **L'icône trombone** dans le champ de saisie : appuie dessus pour choisir
  un fichier, une image ou une vidéo depuis ta galerie ou ton système de
  fichiers.
- **Glisser-déposer** (poste fixe) : fais simplement glisser un fichier dans
  la fenêtre de chat.
- **Coller depuis le presse-papiers** (poste fixe) : copie une image et
  colle-la dans le chat.

Les petits fichiers (moins de 256 Ko) voyagent directement dans le message.
Les fichiers plus volumineux sont découpés en morceaux et dotés d'une
correction d'erreurs, de sorte que des morceaux perdus isolés n'ont pas
d'importance. Si vous êtes tous les deux en ligne, ils sont diffusés en flux
via un voisin ; sinon, ils sont déposés chez des appareils constamment
joignables, jusqu'à ce que ton interlocuteur les récupère.

À partir de 256 Ko, Cleona te demande pour chaque fichier avant de
l'envoyer : un gros fichier ne peut pas prendre le chemin de tes messages.
Son contenu reste chiffré, et ton interlocuteur n'apprend pas ton adresse
Internet. Mais de l'extérieur, la transmission est visible comme un
événement, et un appareil étranger qui la transmet ou la conserve voit qui
charge et qui récupère. Ton accord ne vaut que pour ce seul fichier.

### Messages vocaux

1. Maintiens enfoncé le bouton du microphone dans le champ de saisie.
2. Énonce ton message.
3. Relâche le bouton pour envoyer le message.

Si la reconnaissance vocale est activée sur ton appareil (voir les
paramètres), ton message vocal est automatiquement transcrit en texte. Ton
interlocuteur voit alors à la fois l'enregistrement et le texte transcrit.

### Répondre à des messages (citer)

Pour répondre à un message précis :

1. Ouvre le menu des trois points à côté du message.
2. Choisis « Répondre ».
3. Au-dessus du champ de saisie apparaît une bannière avec le message cité.
4. Écris ta réponse et envoie-la.

Le message cité est affiché dans ta réponse, afin que le rapport soit clair.

### Modifier et supprimer des messages

- **Modifier :** Menu des trois points du message, puis « Modifier ».
  Modifie le texte et renvoie-le. Ton interlocuteur voit que le message a
  été modifié. La modification est possible dans les 15 minutes après
  l'envoi.
- **Supprimer :** Menu des trois points du message, puis « Supprimer ». Le
  message est supprimé chez toi et chez ton interlocuteur. Tu peux supprimer
  tes propres messages à tout moment -- il n'y a pas de fenêtre temporelle
  pour la suppression.

### Réactions par emoji

Au lieu d'écrire une réponse, tu peux réagir à un message avec un emoji :

1. Ouvre le menu des trois points ou maintiens longuement le message appuyé.
2. Choisis un emoji dans la sélection rapide ou ouvre le sélecteur d'emojis
   pour le choix complet.
3. Ta réaction apparaît sous le message.

### Copier du texte

Via le menu des trois points d'un message, tu peux copier le texte du message
dans le presse-papiers.

### Rechercher des messages

En haut de la fenêtre de chat, tu trouves la fonction de recherche. Saisis
un terme de recherche, et Cleona t'affiche tous les résultats dans le chat
actuel. Avec les flèches, tu peux passer d'un résultat à l'autre.

Sur la page d'accueil, il y a en plus un filtre de recherche inter-onglets,
avec lequel tu peux parcourir toutes les conversations selon un terme.

### Aperçu des liens

Quand tu envoies un lien, Cleona génère automatiquement un aperçu (titre,
description, image d'aperçu). Cet aperçu est créé par ton appareil et envoyé
avec -- ton interlocuteur n'a pas besoin d'établir de connexion vers le site
web lié pour cela.

Ce que fait un appui sur un lien reçu, tu le règles dans les paramètres sous
« Ouverture des liens » : « Normal », « Fenêtre privée si possible » (là où
l'appareil ne peut pas ouvrir de fenêtre privée, le lien s'ouvre normalement)
ou « Demander à chaque fois ».

---

## 5. Groupes

### Créer un groupe

1. Passe à l'onglet « Groupes ».
2. Appuie sur le bouton plus.
3. Donne un nom au groupe.
4. Choisis les contacts que tu veux inviter.
5. Appuie sur « Créer ».

Les contacts invités reçoivent une notification et peuvent rejoindre le groupe.

### Comment les messages de groupe sont protégés

Dans un groupe de jusqu'à 16 membres, Cleona envoie chaque message à chaque
membre individuellement -- à chaque fois chiffré uniquement pour ce membre,
comme si tu avais écrit un message distinct à chacun. Les crochets
sur un message de groupe indiquent l'état du membre où le message a le moins
progressé.

Si le groupe dépasse 16 membres, il utilise une clé commune. Elle change
chaque jour et est renouvelée quand un membre part ou en est retiré ; un
nouveau membre ne lit qu'à partir de son arrivée. Là, les crochets
n'indiquent plus l'état de chaque membre, mais que le message est déposé dans
le réseau. Si le groupe redescend à 12 membres ou moins, il revient à l'envoi
individuel.

### Images dans les groupes et les canaux

Dans les paramètres d'un groupe ou d'un canal, tu définis avec « Toujours
charger les images » si les images sont chargées immédiatement ou seulement
quand tu appuies sur l'une d'elles.

### Inviter des membres

Même après la création, tu peux inviter d'autres contacts :

1. Ouvre les infos du groupe (menu des trois points dans la liste des groupes
   ou barre supérieure dans le chat de groupe).
2. Appuie sur « Inviter ».
3. Choisis les contacts que tu veux ajouter.

### Rôles

Chaque groupe a trois rôles :

- **Propriétaire (Owner) :** A le contrôle total. Peut ajouter et supprimer
  des membres, nommer des administrateurs et gérer le groupe. Le propriétaire
  peut aussi transférer son statut à un autre membre.
- **Admin :** Peut supprimer des membres et aider à la gestion.
- **Membre :** Peut lire et écrire des messages.

### Quitter un groupe

1. Ouvre le menu des trois points dans la liste des groupes.
2. Choisis « Quitter ».
3. Confirme ta décision.

Quand tu quittes un groupe, tes messages précédents restent visibles pour
les autres membres.

---

## 6. Canaux publics

### Qu'est-ce que les canaux ?

Les canaux sont des forums de discussion publics au sein du réseau Cleona.
Contrairement aux groupes, tout le monde peut y lire sans avoir besoin d'être
invité. Seul le propriétaire et les administrateurs peuvent publier des
messages -- les abonnés lisent.

### Trouver et rejoindre des canaux

1. Passe à l'onglet « Canaux ».
2. Ouvre l'onglet « Recherche ».
3. Parcours les canaux disponibles par nom ou par thème.
4. Appuie sur un canal puis sur « S'abonner ».

Les canaux peuvent être filtrés par langue. Certains canaux sont marqués
comme « réservé aux adultes » -- ceux-ci ne sont visibles que si tu as
confirmé dans ton profil que tu as plus de 18 ans.

### Créer son propre canal

1. Passe à l'onglet « Canaux ».
2. Appuie sur le bouton plus.
3. Saisis un nom de canal (doit être unique dans tout le réseau).
4. Choisis la langue et si le canal doit être public ou privé.
5. Facultatif : ajoute une description et une image.
6. Appuie sur « Créer ».

Pour les canaux publics, tu peux définir si le contenu est classé comme
« réservé aux adultes ».

### Signaler du contenu

Si tu remarques du contenu inapproprié dans un canal public, tu peux le
signaler. Cleona utilise un système de modération décentralisé : les
signalements sont évalués par des membres du réseau choisis au hasard (une
sorte de « jury citoyen »). Si une infraction est constatée, le canal reçoit
un avertissement. En cas d'infractions répétées, il est rétrogradé dans
l'index de recherche ou bloqué.

### Canaux système

Cleona dispose de deux canaux système intégrés :

- **Bug Log :** Quand Cleona détecte une erreur, il te demande si tu veux
  envoyer un rapport d'erreur ; auparavant, tu vois exactement ce qui sera
  publié. Ces rapports atterrissent dans le canal Bug Log, où la communauté
  peut les consulter. Un rapport ne porte ni ton nom ni le contenu de tes
  conversations, mais un pseudonyme. Dans la version bêta, il indique en plus
  ton identifiant (User-ID), pour que les développeurs puissent te
  recontacter. Tu peux aussi envoyer manuellement un rapport de journal (avec
  une boîte de dialogue d'aperçu et un consentement explicite).
- **Feature Requests :** Ici, les utilisateurs peuvent soumettre des souhaits
  de fonctionnalités et voter pour des propositions existantes. Les
  propositions sont triées par nombre de voix.

Chaque ordinateur conserve jusqu'à 25 Mo par canal système, chaque téléphone
jusqu'à 5 Mo ; quand c'est plein, le plus ancien part en premier -- jamais
ce que tu as toi-même déjà vu.

---

## 7. Appels

### Démarrer un appel vocal

1. Ouvre le chat avec le contact que tu veux appeler.
2. Appuie sur l'icône du téléphone dans la barre supérieure.
3. Attends que ton interlocuteur accepte l'appel.

Pendant la conversation, tu vois une chronologie, la durée de l'appel et tu
as accès au mode muet et au haut-parleur.

Pour raccrocher, appuie sur le bouton de raccrochage rouge.

Si tu vois « Injoignable », l'appareil de ton interlocuteur n'est pas
joignable en ce moment, par exemple un iPhone dont l'app n'est pas ouverte.
Écris plutôt un message.

### Démarrer un appel vidéo

1. Ouvre le chat avec le contact.
2. Appuie sur l'icône de la caméra dans la barre supérieure.
3. Ton image vidéo apparaît dans une petite fenêtre, celle de ton
   interlocuteur dans la grande zone.

Tu peux basculer entre la caméra avant et arrière pendant la conversation.

### Appels entrants

Quand quelqu'un t'appelle, une fenêtre de notification apparaît avec le nom de
l'appelant. Tu peux :

- **Accepter** -- la conversation commence.
- **Refuser** -- l'appelant en est informé.

Si tu es justement dans une conversation, un nouvel appel ne sonne pas ; tu
reçois à la place un message « Appel manqué ». La même chose vaut pour un
appel de groupe que tu n'as pas accepté -- le message se trouve alors dans
le chat de groupe.

Si quelqu'un appelle une de tes identités qui n'est justement pas affichée,
ça sonne quand même ; l'écran d'appel indique laquelle de tes identités est
appelée.

Sur iPhone, ça ne sonne que lorsque l'app est ouverte. Qui t'appelle pendant
qu'elle n'est pas ouverte voit « Injoignable » après 10 secondes. Dès que tu
ouvres l'app, tu trouves un message sur l'appel manqué.

### Appels de groupe

Tu peux aussi mener des appels de groupe auxquels participent plusieurs
personnes en même temps. L'appel est organisé via un arbre de transmission
intelligent, de sorte que chaque participant n'a pas besoin d'être connecté
directement à tous les autres. Toutes les conversations sont chiffrées de bout
en bout.

Chaque membre du groupe peut démarrer un appel de groupe. Deux participants
qui ne sont pas contacts l'un de l'autre ne voient jamais l'adresse Internet
de l'autre : leur son et leur image passent par un participant qui est
contact avec les deux. S'il n'y en a pas, les deux ne sont pas connectés, et
la tuile indique « Aucun contact commun dans l'appel ». Si un relais est
surchargé, le son reste, et la vidéo tombe pour cette paire.

### Chiffrement des appels

Tous les appels sont chiffrés avec des clés à usage unique qui n'existent que
pour la durée de la conversation. Après le raccrochage, ces clés sont
immédiatement supprimées. Personne ne peut décrypter a posteriori une
conversation passée.

Pour être honnête : les appels s'établissent, autant que possible,
directement entre les appareils, car même un petit délai gêne la parole.
Contrairement aux messages, ton fournisseur d'accès peut donc voir, lors d'un
appel, à quelle adresse Internet tu es connecté. Ce que vous dites, il ne le
voit pas.

Lors d'un appel, ton contact voit aussi ton adresse Internet. Si tu ne le
veux pas pour un contact, désactive dans son menu « Autoriser les appels »
(par défaut : activé). Si tu désactives plus tard, une adresse déjà vue reste
connue de lui.

---

## 8. Calendrier

Cleona contient un calendrier intégré qui fonctionne de façon chiffrée et
complètement décentralisée -- sans service de nuage.

### Vues

Le calendrier propose cinq vues : jour, semaine, mois, année et une vue des
tâches. Bascule entre elles via les onglets en haut de l'écran du calendrier.

### Créer des rendez-vous

Appuie sur un créneau horaire ou utilise le bouton Ajouter pour créer un
nouveau rendez-vous. Tu peux saisir un titre, une date, une heure, un lieu et
des notes. Les rendez-vous sont stockés de façon chiffrée sur ton appareil.

### Rendez-vous récurrents

Les rendez-vous peuvent se répéter quotidiennement, hebdomadairement,
mensuellement ou annuellement. Tu peux ajuster le motif (par ex. tous les
deuxièmes mardis, le premier de chaque mois) et fixer une date de fin ou un
nombre de répétitions.

### Inviter des contacts

Lors de la création ou de la modification d'un rendez-vous, tu peux inviter
tes contacts Cleona. Ils reçoivent une invitation de calendrier chiffrée et
peuvent répondre par oui, non ou peut-être. Les modifications du rendez-vous
sont automatiquement envoyées à tous les invités.

### Affichage Libre/Occupé

Tu peux partager ta disponibilité avec des contacts sans révéler les
détails du rendez-vous. Il y a trois niveaux de confidentialité : détails
complets, seulement les plages horaires, ou masqué. Tu peux définir un
réglage par défaut et le remplacer par contact.

### Rappels

Les rendez-vous peuvent avoir des rappels qui déclenchent une notification
système avant le début du rendez-vous. Tu peux faire passer un rappel en mode
veille si besoin.

### Synchronisation avec un calendrier externe

Cleona peut se synchroniser avec des services de calendrier externes :

- **CalDAV** -- Connecte-toi à n'importe quel serveur compatible CalDAV
  (Nextcloud, Radicale, etc.).
- **Google Agenda** -- Synchronisation via l'API Google Calendar avec une
  authentification OAuth2 sécurisée.
- **Serveur CalDAV local** -- Cleona peut démarrer un serveur CalDAV local
  sur ton appareil, de sorte que les applications de calendrier de bureau
  (Thunderbird, Outlook, Calendrier Apple, Evolution) peuvent se synchroniser
  avec ton calendrier Cleona.
- **Calendrier système Android** -- Les rendez-vous de Cleona peuvent être
  transférés vers l'application de calendrier intégrée de ton appareil
  Android.
- **Fichiers ICS** -- Importe et exporte des rendez-vous au format iCalendar
  standard.

### Export PDF

Tu peux imprimer ou exporter chaque vue du calendrier (jour, semaine, mois,
année) sous forme de document PDF.

---

## 9. Sondages

Tu peux créer des sondages dans chaque chat ou groupe afin de recueillir des
avis ou de planifier des dates.

### Types de sondages

Cleona prend en charge cinq types de sondages :

- **Choix unique** -- les participants choisissent une option.
- **Choix multiple** -- les participants peuvent choisir plusieurs options.
- **Sondage de dates** -- Trouve une date qui convient à tous. Chaque
  participant marque des dates comme disponibles, peut-être ou non
  disponibles.
- **Échelle** -- Évalue quelque chose sur une échelle numérique (par ex. de
  1 à 5).
- **Texte libre** -- les participants écrivent leur propre réponse.

### Créer un sondage

Ouvre un chat et appuie sur l'icône de sondage (ou utilise le menu des pièces
jointes). Choisis le type de sondage, formule ta question et les options, et
envoie le sondage. Il apparaît comme un message dans le chat.

### Voter

Appuie sur un sondage pour donner ta voix. Tu peux modifier ou retirer ton
vote à tout moment.

### Vote anonyme

Les sondages peuvent être configurés pour un vote anonyme. Si activé, les
votes sont cryptographiquement anonymes -- personne, pas même le créateur du
sondage, ne peut voir qui a voté pour quoi. Le nombre de voix reste malgré
tout visible.

### Sondage de dates vers le calendrier

Quand un sondage de dates est terminé, la date gagnante peut être convertie
en un événement de calendrier en une seule touche.

---

## 10. Plusieurs identités

### Pourquoi plusieurs identités ?

Imagine que tu veuilles séparer ta vie professionnelle et ta vie privée --
comme avec deux numéros de téléphone différents, mais sans un second
téléphone. Dans Cleona, tu peux utiliser plusieurs identités sur un seul
appareil. Chaque identité a un propre nom, une propre photo de profil, des
propres contacts et des propres conversations.

### Créer une nouvelle identité

1. Dans la barre supérieure, tu vois ton identité actuelle sous forme
   d'onglet.
2. Appuie sur le signe plus (+) à droite de tes onglets d'identité.
3. Saisis un nom pour la nouvelle identité.
4. Terminé -- la nouvelle identité est immédiatement active.

### Basculer entre les identités

Appuie simplement sur l'onglet d'identité dans la barre supérieure. Le
basculement est immédiat -- pas d'attente, pas de rechargement.

### Toutes tournent en même temps

Un point important : toutes tes identités sont actives en même temps. Même si
tu es actuellement affiché comme « Professionnel », ton identité « Privé »
continue de recevoir des messages. Tu ne manques rien, quelle que soit
l'identité que tu as sélectionnée.

### Page de détail de l'identité

Quand tu appuies sur l'onglet de ton identité actuellement active, la page de
détail s'ouvre. Là, tu peux :

- Afficher ton code QR pour les contacts.
- Modifier ou supprimer ta photo de profil.
- Ajouter une description de profil.
- Modifier ton nom d'affichage.
- Choisir un thème (habillage) pour cette identité.
- Supprimer l'identité, si tu n'en as plus besoin.

### Supprimer une identité

Quand tu supprimes une identité, tes contacts en sont informés. L'identité et
toutes les données qui s'y rapportent sont supprimées de ton appareil. Cette
opération est irréversible.

---

## 11. Plusieurs appareils

### Une identité, un appareil -- pour l'instant

Aujourd'hui, une identité tourne sur un appareil. Un second appareil pour
la même identité arrivera avec une version ultérieure ; dans les paramètres,
sous « Appareils » -> « Gérer les appareils », « Coupler un autre appareil »
figure donc encore comme « Pas encore disponible — plusieurs appareils par
identité arriveront dans une version ultérieure. »

Quand il arrivera, ce sera ainsi : tous les appareils auront les mêmes
droits, il n'y aura pas d'appareil principal. Tu configureras un appareil
supplémentaire avec tes 24 mots, et l'un de tes appareils existants y
consentira. Cinq appareils au maximum.

Si tu saisis aujourd'hui tes 24 mots sur un nouvel appareil, tu déménages :
l'identité est restaurée sur le nouvel appareil, et ton appareil précédent
la retire ensuite chez lui (voir chapitre 12).

Sur plusieurs appareils, tu peux aujourd'hui utiliser des identités
différentes (chapitre 10).

### Rotation des clés

Si tu supposes que quelqu'un a eu accès à tes clés, tu peux générer de
nouvelles clés sous « Gérer les appareils » -> « Rotation des clés ». Tes
contacts sont avertis, tes invitations encore ouvertes sont révoquées.
Important : après cela, les 24 mots seuls ne restaurent plus que les
anciennes clés. Crée donc juste après un nouveau Pack de récupération ; tu
ne pourras ensuite restaurer qu'avec ce pack.

---

## 12. Récupération

### Utiliser la phrase de récupération

Si tu perds ton appareil ou que tu en configures un nouveau :

1. Installe Cleona sur le nouvel appareil.
2. Choisis « Récupérer » au démarrage.
3. Saisis tes 24 mots.
4. Cleona recrée à partir de là toutes tes identités -- avec les mêmes
   clés qu'auparavant. Pour tes contacts, tu es la même personne.

### Ce qui revient -- et ce qui ne revient pas

Ton identité tient dans les 24 mots, tes contacts et ton historique non. Ce
qui revient, c'est ton accès au réseau via le **Pack de récupération** : ton
appareil dépose un petit paquet chiffré dans le réseau. Seuls tes 24 mots
peuvent le trouver et l'ouvrir. Il contient ce dont ton nouvel appareil a
besoin pour réatteindre tes contacts, et ce qui a été déposé pour toi
entre-temps dans le réseau. Aucun contact n'a besoin d'être en ligne pour
cela.

L'historique de chat existant n'est pas ramené par une restauration.

Le Pack de récupération vit 7 jours et est renouvelé par ton appareil tant
qu'il tourne ; dans les paramètres, tu vois jusqu'à quand il est valable.
Si aucun de tes appareils n'a tourné pendant plus de 7 jours, il est
expiré. Les 24 mots restaurent alors ton identité quand même, mais tes
contacts, tu dois les réinviter ; ce qui a été déposé pour toi entre-temps
dans le réseau est perdu.

### Restaurer signifie déménager

Si ton appareil précédent constate plus tard que l'identité a été restaurée
ailleurs, il la retire chez lui -- avec son historique. Voilà pourquoi :
celui qui a tes 24 mots peut, de cette façon, prendre ton identité sur ton
appareil. Jusqu'à ce que tous les contacts soient de retour, l'app te le
rappelle ; avec « Terminer et renouveler les clés », tu termines toi-même la
restauration.

### Ce que personne ne peut récupérer

C'est important, et nous le disons donc clairement :

- **Personne d'autre que toi ne peut récupérer ton identité.** Ni le
  développeur, ni un support, ni même tes contacts -- quel que soit leur
  nombre. Il n'y a pas de clé maîtresse ni de partie de ta clé qui serait
  déposée chez d'autres.
- **Si tu as perdu les 24 mots et qu'il ne te reste plus d'appareil, ton
  identité est perdue.** Il ne reste alors qu'à en créer une nouvelle et à
  réinviter tes contacts.

La meilleure protection : écris les 24 mots sur papier et garde-les en
sécurité.

---

## 13. Paramètres

Tu accèdes aux paramètres via l'icône d'engrenage dans le coin supérieur
droit.

### Notifications et sonneries

- Choisis parmi six sonneries différentes pour les appels entrants.
- Définis un son de message.
- Sur les appareils Android, tu peux en plus activer ou désactiver la
  vibration.
- **« Tout mettre en sourdine »** ne laisse plus aucune notification sonner,
  vibrer ou se manifester sur cet appareil -- pour toutes les identités. Les
  appels continuent de sonner.
- **« Heures calmes »** se règlent pour chaque identité avec une heure de
  début et de fin. Pendant cette période, aucune notification de cette
  identité ne sonne, ne vibre ni ne se manifeste ; les messages arrivent
  quand même.
- **« Notifications sans contenu »** (par défaut : désactivé) montre
  seulement qu'un message, une invitation ou un rappel est arrivé -- sans
  expéditeur, sans nom et sans texte. Les appels continuent d'afficher le
  nom.
- Ce qui arrive d'un coup après le démarrage, Cleona l'annonce dans une
  notification groupée (« 5 nouveaux messages dans 2 conversations ») ;
  tout ce qui vient ensuite, individuellement. Un appui sur une
  notification de message ouvre la conversation, même dans une autre
  identité.

### Thèmes (habillages)

Cleona propose dix thèmes différents : Teal, Ocean, Sunset, Forest, Amethyst,
Fire, Storm, Slate, Gold et Contrast. Le thème Contrast remplit le plus haut
niveau d'accessibilité (WCAG AAA) et est particulièrement lisible en cas de
vision réduite.

Chaque identité peut avoir son propre thème. Tu modifies le thème dans la page
de détail de l'identité (appuie sur l'onglet d'identité actif).

De plus, tu peux basculer entre le thème clair, sombre et système dans les
paramètres sous « Apparence ».

### Changer la langue

Cleona est disponible en 34 langues, y compris des langues à écriture de
droite à gauche (par ex. arabe, hébreu). Change la langue dans les paramètres
sous « Langue ».

### Archivage des médias

Si tu as à la maison un stockage réseau (NAS) ou un dossier partagé, Cleona
peut y déporter automatiquement tes médias. SMB, SFTP, FTPS et WebDAV sont
pris en charge.

Voici comment fonctionne le stockage par paliers :
- Les 30 premiers jours : tout reste sur ton appareil.
- Après 30 jours : une image d'aperçu reste sur l'appareil, l'original est
  archivé.
- Après 90 jours : seule une petite image d'aperçu reste sur l'appareil.
- Après un an : seul un substitut reste, l'original est en sécurité dans
  l'archive.

Tu peux à tout moment appuyer sur un média archivé pour le récupérer -- à
condition d'être connecté à ton réseau domestique. Les médias particulièrement
importants peuvent être épinglés pour qu'ils ne soient jamais déportés.

Sous « Budget stockage », tu définis combien de Mo de médias restent sur
l'appareil (par défaut : 100 Mo sur le téléphone, 2 Go sur l'ordinateur).
Quand c'est plein, le média non épinglé le plus ancien est archivé en
premier. Un original n'est supprimé que lorsqu'il est en sécurité dans
l'archive -- les messages texte sont toujours conservés.

### Transcription des messages vocaux

Si activée, tes messages vocaux sont convertis en texte localement sur ton
appareil (avec le modèle open source Whisper). Le texte transcrit est envoyé
avec l'enregistrement à ton interlocuteur. La transcription se fait
entièrement sur ton appareil -- aucune donnée ne va vers des services
externes.

Le modèle téléchargé (tiny, base, small), tu le règles une seule fois pour
l'appareil ; la langue (automatique ou fixe), pour chaque identité.

### Téléchargement automatique

Tu peux définir à partir de quelle taille les médias doivent être téléchargés
automatiquement. Tu peux ainsi, par exemple, charger automatiquement les
images mais décider manuellement pour les grandes vidéos.

### Appareils

Sous « Appareils » -> « Gérer les appareils », tu vois cet appareil. Coupler
un autre appareil arrivera avec une version ultérieure (chapitre 11).

### Réseau

Cleona n'a besoin d'aucun réglage réseau pour fonctionner. Il y a exactement
trois commutateurs réseau :

- **Redirection de port sur le routeur** (par défaut : activé). Cleona
  demande à ton propre routeur d'ouvrir une porte pour Cleona. Si ça
  fonctionne, ton appareil est mieux joignable pour les autres et aide le
  réseau. Cleona ne parle alors qu'à ton routeur, pas à Internet.
- **Entrées d'adresse publiques** (par défaut : activé). Si ton appareil a
  encore trop peu de voisins, il cherche d'autres points d'entrée dans un
  annuaire public (Nostr), et s'il est lui-même bien joignable, il s'y
  inscrit. L'entrée contient une adresse, aucun nom et aucun contact. Si tu
  le désactives, ton appareil ne trouve des voisins que via les invitations,
  le réseau local et les voisins qu'il connaît déjà.
- **Moins de paquets de couverture en Wi-Fi** (par défaut : désactivé). En
  Wi-Fi ou sur câble, tu peux désactiver les paquets de couverture vides.
  Mais alors on voit de nouveau quand tu écris. Sur les données mobiles, ce
  commutateur n'existe pas -- là, Cleona envoie de toute façon seulement un
  paquet de couverture par minute.

Le trafic de couverture dans son ensemble ne peut pas être désactivé. C'est
intentionnel : seulement s'il tourne toujours, l'activité de ton appareil ne
dit rien de savoir si tu écris actuellement.

Au-dessus des trois commutateurs se trouve le **Mode économie de données** :
sur les données mobiles, Cleona te le propose, mais ne l'active jamais
lui-même. Il économise des données ; en contrepartie, ton appareil est
plus facile à reconnaître de l'extérieur.

En dessous, tu règles le **« Cache pour les médias des autres »** : ton
appareil conserve des parties chiffrées des médias des autres jusqu'à 7 jours,
pour qu'elles atteignent leurs destinataires (par défaut : 100 Mo sur le
téléphone, 1 Go sur l'ordinateur). Une taille plus petite libère
immédiatement la place -- les parties les plus anciennes d'abord.

---

## 14. Sécurité

### Que signifie le chiffrement post-quantique ?

Le chiffrement actuel repose sur des problèmes mathématiques qui sont
extrêmement difficiles à résoudre pour des ordinateurs normaux. Les
ordinateurs quantiques pourraient résoudre certains de ces problèmes
rapidement à l'avenir. Le chiffrement post-quantique utilise des procédés
supplémentaires qui résistent aussi aux ordinateurs quantiques.

Cleona combine les deux approches : chiffrement classique pour la fiabilité
et procédés post-quantiques pour la pérennité. Ainsi tu es protégé contre
les menaces actuelles et futures à la fois.

Pour chaque message individuel, une clé propre est générée. Même si un
attaquant venait à craquer la clé d'un message, il ne pourrait lire aucun
autre message avec celle-ci.

### Pourquoi pas de serveur est plus sûr

Avec les messagers classiques, tes messages passent par les serveurs du
fournisseur. Même s'ils y sont chiffrés : le fournisseur a accès aux
métadonnées (qui communique avec qui, quand, à quelle fréquence, d'où) et
peut être contraint de les remettre sur ordonnance judiciaire.

Avec Cleona, il n'y a pas de tel point central. Il n'y a pas d'endroit où
toutes les métadonnées convergent, ni d'annuaire dans lequel on pourrait
chercher qui tu es ou qui tu connais.

### Qui voit que tu écris avec quelqu'un ?

Le chiffrement protège **ce** que tu écris. Tout aussi important est qu'aucun
observateur isolé n'apprenne **avec qui** et **quand** tu écris. Cleona y
pourvoit ainsi :

- **Sur Internet jamais directement.** Si ton appareil envoyait un message
  directement à l'adresse Internet de ton interlocuteur, ton fournisseur
  pourrait voir avec qui tu écris. C'est pourquoi un message sur Internet
  passe toujours par vos voisins fixes : le tien et celui de ton
  interlocuteur.
- **Des voisins à qui tu fais confiance.** Tes voisins fixes sont, autant
  que possible, des appareils de tes propres contacts -- jusqu'à trois qui
  sont actuellement joignables de l'extérieur. Si l'un disparaît, un autre
  contact prend le relais. Un contact ne s'achète pas avec des serveurs ; un
  nœud quelconque du réseau, oui. Si tu n'as pas encore de contact
  joignable, Cleona prend un autre voisin. Ton invitation ne nomme jamais
  aucun de tes contacts, pour que personne n'apprenne via eux l'adresse d'un
  ami.
- **Des codes au lieu de noms.** Les voisins ne voient ni noms ni
  identifiants, mais seulement un code. Il vaut exactement pour vous deux,
  dans une direction, pour un jour -- le lendemain c'en est un autre. Ton
  voisin sait d'où vient le paquet, mais pas où il va au bout. Le voisin de
  ton interlocuteur sait où il va, mais pas d'où il venait. En temps
  normal, personne en chemin ne voit les deux extrémités.
- **Le trafic de couverture.** Ton appareil envoie en permanence, à
  intervalles irréguliers, des paquets de couverture à ses voisins. Ils
  sont tout aussi grands que les vrais paquets, passent par le même port et
  sont indistinguables d'eux de l'extérieur. Qu'un humain écrive
  actuellement ou que l'appareil tourne seulement, on ne peut le savoir. Tes
  messages n'attendent jamais le trafic de couverture -- ils partent
  immédiatement, il tourne seulement à côté.

**Ce que coûte le trafic de couverture :** En Wi-Fi environ 13 Mo par jour.
Sur les données mobiles, Cleona envoie seulement un paquet de couverture par
minute, soit environ 1,7 Mo par jour. La raison de la limitation sur les
données mobiles n'est pas le volume de données, mais la batterie : chaque
paquet réveille le modem radio.

**Ce que Cleona ne peut pas cacher** -- pour être honnête :

- Aucun observateur **unique** ne voit qui écrit avec qui -- ni ton
  fournisseur ni les nœuds en chemin. Mais celui qui surveille **les deux
  extrémités en même temps**, par exemple un État qui observe ta connexion
  et celle de ton interlocuteur ou qui contrôle les deux voisins, peut
  corréler dans le temps : paquet sortant chez toi, peu après paquet entrant
  chez ton interlocuteur. Suffisamment souvent répété, cela donne une
  relation.
- Le trafic de couverture rend cette corrélation plus difficile, mais ne
  l'empêche pas. Il cache des messages individuels, pas le volume : celui
  qui envoie beaucoup augmente le trafic total de son appareil.
- Un contact qui est ton voisin fixe apprend **quand** et **combien** tu
  envoies et reçois -- pas avec qui et pas quoi. Si le danger vient de ton
  propre entourage, tu peux exempter chaque contact (voir chapitre 3, « Ne
  jamais utiliser comme voisin fixe »).
- Si deux nouveaux utilisateurs n'ont que le même et unique voisin, leur
  message passe par exactement ce nœud, et il voit les deux extrémités. Dès
  que l'un des deux a d'autres voisins, c'est terminé.
- Ton invitation contient tes adresses Internet. Celui qui a la ligne de
  texte voit où tu es en ligne -- ne la donne qu'à des gens à qui tu fais
  confiance pour cela.
- Un voisin qui transmet voit que deux codes échangent des paquets -- pas
  qui est derrière, et pas ce qu'il y a dedans.
- Le signal d'un appel en cours peut, quand le premier voisin ne répond pas
  justement, passer par un nœud qui voit les deux extrémités ; il apprend
  que vous téléphonez ensemble.
- Un gros fichier auquel tu as consenti est vu par l'ordinateur qui le
  transmet ou le conserve, aux deux extrémités (voir chapitre 4).
- Pour les appels, la protection contre le fournisseur ne s'applique pas, et
  ton contact voit ton adresse Internet (voir chapitre 7).

### Que se passe-t-il quand ton interlocuteur est hors ligne ?

1. Cleona démarre tous les chemins appropriés en même temps : dans le même
   Wi-Fi directement, sur Internet via deux voisins -- et en plus la boîte
   aux lettres.
2. Pour la boîte aux lettres, Cleona dépose le message chiffré chez trois
   voisins. Dès que deux en confirment la réception, il compte comme
   déposé.
3. Cleona choisit pour cela de préférence des voisins chez qui ton
   interlocuteur regarde aussi -- d'abord le voisin que son invitation
   nomme.
4. Le message y attend jusqu'à 7 jours. Quand ton interlocuteur revient, il
   le récupère et t'en confirme la réception. Ce n'est qu'alors que tu vois
   deux crochets.

Seul ton interlocuteur peut vider la boîte aux lettres : récupérer et
supprimer ne fonctionne qu'avec une clé que seul il possède, et la
suppression n'a lieu qu'après qu'il a confirmé la réception. Les voisins ne
voient que des paquets chiffrés sous une valeur qui change chaque jour.

### Les inconnus ne passent pas

De quelqu'un qui n'est ni ton contact ni membre d'un groupe en commun, Cleona
n'accepte exactement deux choses : la demande de tes clés publiques, tant
qu'une de tes invitations est
encore ouverte, et une demande de contact. La demande doit porter une
invitation valide de ta part, et l'expéditeur doit avoir résolu au préalable
une tâche de calcul. Tout le reste -- messages, appels, fichiers -- est
écarté avant même d'atteindre l'application. Celui qui n'a que ta carte de
visite imprimée ne peut donc pas simplement t'appeler. Un membre d'un groupe
en commun ne t'atteint que dans ce groupe -- avec des messages de groupe et
des appels de groupe, jamais individuellement.

### Anti-censure

Cleona est conçu pour être difficile à bloquer :

- **Pas de serveur, pas d'adresse fixe.** Aucune adresse à bloquer ne figure
  dans l'application, et le réseau ne dépend d'aucun nœud unique.
- **Pas de port fixe.** Chaque appareil choisit un port aléatoire au premier
  démarrage. Il n'y a pas de numéro de port connu auquel on pourrait
  reconnaître le trafic Cleona.
- **Comme des données aléatoires.** L'établissement de connexion entre deux
  appareils est codé de façon à être indistinguable de données aléatoires.
- **De nombreux points d'entrée.** Chaque invitation, chaque voisin et
  chaque appareil dans le même Wi-Fi est un chemin possible de retour dans
  le réseau.

### Stockage sûr des clés

Sur les plateformes prises en charge, Cleona stocke tes clés de chiffrement
dans le trousseau sécurisé du système d'exploitation (Android Keystore, iOS
Keychain, macOS Keychain). Là où c'est disponible, cela offre une protection
matérielle pour tes clés.

### Chiffrement de la base de données

Tes messages et conversations reposent dans une base de données chiffrée --
une propre à chaque identité, chacune avec sa propre clé. Chiffré n'est pas
seulement la base de données elle-même, mais aussi ses fichiers
intermédiaires ; rien n'est écrit sur le disque en clair, pas même
brièvement. Les paramètres, contacts et médias sont également stockés
chiffrés.

Les clés sont dérivées de tes 24 mots et n'existent que sur ton appareil.
Même quelqu'un qui met la main sur ton appareil et en lit les données ne
trouve, sans ces clés, que des données illisibles.

Le contenu n'est non chiffré que là où tu fais sortir toi-même des contenus
de Cleona :
- quand tu enregistres un fichier d'un chat sur ton appareil,
- quand tu mets avec le bouton « Capture d'écran » une image dans tes
  images,
- quand tu partages quelque chose avec une autre app,
- quand tu configures l'archivage des médias (chapitre 13) : les originaux
  archivés reposent non chiffrés sur ton stockage réseau à la maison, pour
  que tu puisses les y ouvrir aussi sans Cleona,
- quand tu recopies tes rendez-vous dans le calendrier système Android :
  là, d'autres apps avec accès au calendrier peuvent les lire.

Ce qui est ainsi sorti n'est pas supprimé avec le message et n'expire pas
avec lui.

### Protection à l'écran

Sur Android, Windows et macOS, Cleona n'autorise pas de capture d'écran par
d'autres apps. Si tu as besoin d'une image, prends le bouton « Capture
d'écran » dans la barre supérieure : il met l'image dans tes images -- non
chiffrée. Dans une conversation où le transfert n'est pas autorisé, il n'y a
pas de capture d'écran.

---

## 15. Mises à jour du logiciel

### Comment obtiens-je des mises à jour ?

Cleona peut être mis à jour par diverses voies. L'objectif est que tu puisses
recevoir des mises à jour même quand des canaux de distribution individuels
tombent en panne ou sont bloqués :

1. **App Store / Play Store :** Dès que Cleona y apparaît et que tu l'as
   installé via un store, tu reçois les mises à jour comme d'habitude via le
   store. Sur iPhone, les mises à jour arrivent via TestFlight.
2. **GitHub Releases :** Sur la page GitHub du projet, tu trouves des paquets
   d'installation signés pour toutes les plateformes.
3. **Mises à jour via le réseau :** Cleona peut récupérer une mise à jour
   directement via le réseau -- sans serveur de téléchargement. La nouvelle
   version est découpée en morceaux à correction d'erreurs qui se répartissent
   dans le réseau ; une partie d'entre eux voyage même avec le trafic de
   couverture. Ton appareil rassemble assez de morceaux et reconstitue la
   mise à jour. La plupart du temps, seule la modification est
   transférée -- quelques Mo au lieu de l'app entière. Cela vaut pour
   Linux, Windows et Android ; sous macOS, tu charges les nouvelles versions
   depuis le site ou depuis GitHub.
4. **Liens d'invitation :** Tu peux créer des liens d'invitation qui
   contiennent tout ce dont un nouvel utilisateur a besoin pour installer
   Cleona et se connecter au réseau.
5. **Transfert physique :** Dans des environnements sans Internet, tu peux
   transmettre Cleona à d'autres via une clé USB ou dans le réseau local.

### Comment se déroule une mise à jour

1. Cleona rassemble les morceaux d'une nouvelle mise à jour automatiquement
   en arrière-plan et les reconstitue.
2. Ce n'est que lorsque la mise à jour est **complète** et que sa **signature
   a été vérifiée** que Cleona te la propose. On ne te propose donc jamais
   une mise à jour à moitié ou non vérifiée.
3. Si tu appuies sur « Installer », l'installation démarre sans nouvelle
   demande. Sur Android, le système affiche en plus sa boîte de dialogue
   d'installation.

Les versions plus anciennes ne sont pas proposées -- une mise à jour ne va
toujours qu'en avant. Si une version est si ancienne qu'elle ne peut plus
coopérer avec le réseau, Cleona l'indique clairement et te demande de te
mettre à jour.

### Vérification de signature

Chaque mise à jour est signée deux fois : avec un procédé classique et un
procédé post-quantique. Cleona vérifie les deux signatures automatiquement.
Cela garantit que seules les mises à jour du développeur officiel sont
acceptées -- même si la mise à jour est arrivée via le réseau depuis des
appareils étrangers. Une mise à jour n'est jamais créée automatiquement depuis
le développement, mais seulement quand le développeur la signe à la main.

---

## 16. Questions fréquentes

### « Puis-je utiliser Cleona sans Internet ? »

Cleona a besoin d'une connexion réseau, mais pas nécessairement d'Internet :
dans le même Wi-Fi, les appareils Cleona se trouvent eux-mêmes et peuvent
écrire entre eux tout à fait sans accès Internet. Être en ligne en même
temps que ton interlocuteur n'est pas nécessaire : s'il est hors ligne, le
message attend jusqu'à 7 jours dans la boîte aux lettres chez trois voisins,
jusqu'à ce qu'il le récupère.

### « Que faire si je perds ma phrase de récupération ? »

Tant qu'un appareil avec ton identité tourne encore, rien n'est perdu -- tu
y continues simplement à écrire. Sur l'appareil où tu as créé l'identité, tu
peux la plupart du temps relire les 24 mots (voir chapitre 2). Ne te repose
pas là-dessus : une nouvelle installation supprime cette copie, et sur
Android, retirer ou modifier le verrouillage d'écran la détruit aussi. Si tu
n'as ni les mots ni un appareil, il n'y a pas de retour possible -- pas même
via tes contacts, le développeur ou quiconque d'autre. C'est pourquoi il est
si important de conserver les 24 mots en sécurité.

### « Quelqu'un peut-il lire mes messages ? »

Non. Chaque message est chiffré avec une clé à usage unique qui ne vaut que
pour ce seul message. Seuls toi et ton interlocuteur pouvez déchiffrer le
message. Il n'y a pas de serveur central, pas de clé maîtresse et pas d'accès
pour le développeur. Même si un appareil sur le chemin de transmission
relaye le message, il ne voit qu'un flux de données chiffrées et un code.
Ton voisin sait que le paquet vient de toi, mais pas à qui il va ; le voisin
de ton interlocuteur sait à qui il va, mais pas de qui.

### « Pourquoi n'ai-je pas besoin de numéro de téléphone ? »

Parce que ton identité est purement cryptographique. Au lieu d'un numéro de
téléphone ou d'une adresse e-mail liés à ton vrai nom, une paire de clés
générée sur ton appareil t'identifie. Tu ajoutes des contacts par code QR,
NFC ou la ligne de texte de ton invitation -- pas via un annuaire
téléphonique. Cela signifie plus de vie privée, parce que ton compte de
messagerie n'est pas lié à ton identité réelle.

### « Comment trouver des gens sur Cleona ? »

Cleona n'a délibérément pas de recherche de contacts par numéro de téléphone
ou par nom -- ce serait un problème de vie privée. Au lieu de cela, tu
échanges directement des invitations : par code QR, NFC ou en ligne de texte
via un autre canal. C'est comme échanger des cartes de visite plutôt que de
chercher dans l'annuaire.

### « Cleona fonctionne-t-il aussi à l'étranger ? »

Oui. Tant que tu as une connexion Internet, Cleona fonctionne partout dans
le monde. Comme il n'y a pas de serveur central ni d'adresse fixe, le
service ne peut pas être simplement coupé pour certains pays. Comment Cleona
complique les blocages, c'est dans le chapitre « Sécurité » sous
« Anti-censure ». Un pays qui bloque tout trafic inconnu à la frontière peut
toutefois aussi arrêter Cleona.

### « Cleona est-il gratuit ? »

Oui. Cleona est utilisable gratuitement et sans publicité. Comme il n'y a pas
de serveur central, il n'y a pas non plus de coûts de serveur pour
l'exploitation. Dans les paramètres, sous « Soutenir Cleona » -> « Faire un
don », tu peux soutenir le développement de façon volontaire.

### « Mon message n'a qu'un crochet -- qu'est-ce que ça signifie ? »

Le message est en route, mais ton interlocuteur n'a pas encore confirmé la
réception -- le plus souvent parce qu'il est actuellement hors ligne. Ce
n'est pas une erreur : le message attend jusqu'à 7 jours dans la boîte aux
lettres. Dès qu'il le récupère, tu vois deux crochets. Une horloge signifie
qu'aucun chemin n'a encore porté le message -- il repart tout seul dès qu'il
y en a un ; une icône d'avertissement, qu'il n'a trouvé aucun chemin pendant
14 jours et que tu peux le renvoyer.

### « Pourquoi les messages arrivent-ils en retard sur mon iPhone ? »

iOS ne laisse pas les apps tourner en permanence en arrière-plan. Cleona
n'est réveillée que brièvement de temps en temps ; iOS décide quand. Elle
récupère alors tout. Dès que tu ouvres l'app, Cleona récupère ce qui a été
gardé pour toi.

### « Puis-je passer de WhatsApp à Cleona ? »

Oui, mais tu ne peux pas transférer tes chats WhatsApp. Cleona et WhatsApp
sont des systèmes fondamentalement différents. Tu dois ajouter tes contacts
un par un dans Cleona. Le plus simple est d'envoyer la ligne de texte de ton
invitation à tes contacts. Chaque demande qui arrive ainsi, tu la confirmes
toi-même sous « Demandes ».

### « Puis-je utiliser Cleona sur plusieurs appareils en même temps ? »

Pas encore. Un second appareil pour la même identité arrivera avec une
version ultérieure (chapitre 11). Sur plusieurs appareils, tu peux
aujourd'hui utiliser des identités différentes.

### « Comment obtenir des mises à jour si l'App Store est bloqué ? »

Cleona peut récupérer des mises à jour directement via le réseau, sans
dépendre d'un App Store, d'un site web ou d'un serveur de téléchargement. Si
un autre appareil dans le réseau a la dernière version, ton appareil peut
charger la mise à jour depuis celui-ci. L'authenticité est vérifiée par une
signature numérique du développeur. Alternativement, un contact peut te
transmettre l'application par un lien d'invitation ou une clé USB. Plus à ce
sujet dans le chapitre « Mises à jour du logiciel ».

---

## Aide et contact

Si tu as des questions ou que tu tombes sur un problème, tu trouves des
informations à jour sur le site Cleona et sur GitHub. Comme Cleona est un
projet décentralisé, il n'y a pas de support client classique -- mais une
communauté active qui aide volontiers.

---

*Ce manuel décrit Cleona Chat version 4.2. Des fonctions individuelles peuvent
changer ou s'étendre dans des versions plus récentes.*
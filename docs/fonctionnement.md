# Fonctionnement détaillé

Ce document explique comment le widget obtient l'état de kDrive, ce que fait chaque action, où sont
stockés les réglages, et comment le projet suit les versions d'Infomaniak. Les références au code
d'Infomaniak renvoient au sous-module `upstream/` (version 3.8.8).

- [Architecture de kDrive sous Linux](#architecture-de-kdrive-sous-linux)
- [Pourquoi le widget ne parle pas directement au serveur](#pourquoi-le-widget-ne-parle-pas-directement-au-serveur)
- [Lecture de l'état](#lecture-de-létat)
- [Le panneau](#le-panneau)
- [Actions](#actions)
- [Réglages](#réglages)
- [Notifications](#notifications)
- [Suivi du dépôt Infomaniak](#suivi-du-dépôt-infomaniak)
- [Dépannage](#dépannage)
- [Feuille de route](#feuille-de-route)

## Architecture de kDrive sous Linux

Le client kDrive est livré en AppImage et lance **deux processus** :

```
kDrive.AppImage
└── serveur de synchronisation (processus principal)
    │   écoute sur 127.0.0.1:<port aléatoire>   (OldCommServer)
    │
    └── kDrive_client <port>                     (interface Qt, lancée par le serveur)
            └── icône de la zone de notification (StatusNotifierItem « kDrive_client »)
```

- Le **serveur** fait tout le travail : surveillance des fichiers, échanges avec l'API Infomaniak,
  base de synchronisation. C'est lui qui démarre l'interface, en lui passant le port de
  communication en argument (`AppServer::startClient`, `src/server/appserver.cpp`).
- L'**interface** (`kDrive_client`) affiche la fenêtre, les préférences et l'icône de la zone de
  notification. Elle n'a aucune logique de synchronisation.

Quitter l'interface fait quitter le serveur : si la connexion se coupe sans un arrêt « propre »,
le serveur considère que l'interface a été tuée et s'arrête (`AppServer::onClientDisconnectedReceived`).

## Pourquoi le widget ne parle pas directement au serveur

Sous Linux, kDrive 3.x utilise encore l'ancien canal de communication, `OldCommServer`
(`src/server/comm/oldcommserver.cpp`) :

| Caractéristique | Conséquence pour une extension |
|---|---|
| **Un seul client à la fois** : une nouvelle connexion remplace la précédente | Se connecter déconnecterait l'interface officielle… |
| **Le serveur s'arrête quand son client se déconnecte** | … ce qui arrêterait la synchronisation. |
| Messages JSON dont les paramètres sont encodés en binaire Qt (`QDataStream`, base64) | Chaque type (dossier, erreur, compte…) a son propre encodage, non documenté. |
| 77 requêtes et 35 signaux, propres à chaque version | Toute mise à jour de kDrive peut casser l'extension. |

Remplacer complètement l'interface officielle serait possible, mais demanderait d'extraire l'AppImage
pour substituer `kDrive_client`, de réimplémenter ce protocole privé, et de refaire connexion au compte,
ajout de dossiers, conflits, exclusions… Le tout pour un canal qu'Infomaniak abandonne avec kDrive 4
(voir [Feuille de route](#feuille-de-route)).

Le widget s'appuie donc sur la seule source **sûre** : l'icône officielle de la zone de notification,
exposée sur D-Bus. La lire ne perturbe ni l'interface ni le serveur.

## Lecture de l'état

### Source : l'infobulle de l'icône officielle

L'interface met à jour l'infobulle de son icône à chaque changement d'état
(`ClientGui::computeOverallSyncStatus`, `src/gui/clientgui.cpp`). Le texte a deux formes :

```
Folder /run/media/rl/kDrive: Sync is running.          ← une ligne par dossier synchronisé
Folder Documents/kDrive: Last Sync was successful. (Sync is paused)

Please sign in                                          ← message global, sans dossier
```

Le widget récupère cette infobulle avec le module `Quickshell.Services.SystemTray` (l'élément dont
l'identifiant est `kDrive_client`). La propriété est réactive : le widget se met à jour dès que
kDrive change l'infobulle, sans interrogation périodique.

### Analyse (`Status.js`)

Pour chaque ligne, `Status.parse()` :

1. reconnaît le format « Dossier %1 : %2 » dans **toutes les langues** de kDrive
   (`folderFormats` dans `StatusStrings.js`). Le chemin est coupé au **dernier** séparateur, car un
   chemin peut contenir « : » mais pas le message d'état ;
2. retire le suffixe « (Sync is paused) » s'il est présent, et marque le dossier comme en pause ;
3. associe le message à un état (`states` dans `StatusStrings.js`) ;
4. remet en chemin absolu les chemins sous le dossier personnel, que kDrive raccourcit
   (`ClientGui::shortGuiLocalPath`).

L'état global est celui du dossier **le plus grave**, dans cet ordre :

| État | Message kDrive (anglais) | Libellé du widget | Icône de barre |
|---|---|---|---|
| `error` | *(texte vide)* | Erreur de synchronisation | couleur d'alerte |
| `stopped` | User Abort. | Synchronisation arrêtée | couleur d'alerte |
| `signin` | Please sign in | Connexion requise | couleur d'alerte |
| `nofolder` | There are no sync folders configured. | Aucun dossier synchronisé | |
| `undefined` | Undefined State. *(ou message inconnu)* | État inconnu | couleur d'alerte |
| `conflicts` | Sync was successful, unresolved conflicts. | Conflits à résoudre | couleur d'alerte |
| `paused` | Sync is paused. / Synchronization is paused | En pause | atténuée |
| `starting` | Waiting to start syncing. | Démarrage de la synchronisation | |
| `running` | Sync is running. | Synchronisation en cours | |
| `ok` | Last Sync was successful. | À jour | |
| `offline` | *(pas d'icône kDrive)* | kDrive n'est pas lancé | atténuée |

Remarques :

- kDrive laisse le texte **vide** quand un dossier est en erreur (`SyncStatus::Error` dans
  `ClientGui::trayTooltipStatusString`). Le widget le reconnaît même si l'espace final a disparu.
- « User Abort. » ne veut pas forcément dire que vous avez arrêté la synchronisation : kDrive utilise
  ce message pour tout arrêt (`SyncStatus::Stopped`), y compris après une erreur d'accès
  (voir [Dépannage](#dépannage)).
- Un message inconnu (nouvelle version de kDrive, langue absente) donne l'état `undefined`, et le
  panneau affiche alors le texte brut de kDrive.

## Le panneau

Un clic sur l'icône ouvre le panneau, qui contient de haut en bas :

1. **En-tête** : icône et libellé de l'état global.
2. **Dossiers** : un par ligne de l'infobulle, avec une pastille (accent si à jour ou en cours,
   alerte en cas de problème).
3. **Disque** du premier dossier : périphérique, système de fichiers, point de montage, espace libre
   (`findmnt -T` et `df`). Une alerte s'affiche si le dossier **n'est pas modifiable** par votre
   utilisateur.
4. **Dernières erreurs du journal**, seulement si l'état est un problème ou si kDrive est arrêté :
   les trois dernières lignes `[E]` du journal le plus récent du serveur
   (`~/.local/state/kDrive/logs/*_kDrive.log`), sans deux messages bénins et répétitifs
   (vérification de mise à jour, droits sur les dossiers spéciaux « Common documents » et « Shared »).
5. **Actions**, puis **Réglages**.

Le disque et le journal sont relus à l'ouverture du panneau, à chaque changement d'état, puis toutes
les 5 secondes panneau ouvert et toutes les 60 secondes panneau fermé.

## Actions

| Bouton | Ce qu'il fait | Visible |
|---|---|---|
| Démarrer kDrive | `uwsm-app -- <AppImage>` | kDrive arrêté |
| Dossier | `xdg-open <dossier>` | un dossier est connu |
| Fenêtre kDrive | Active l'icône officielle (`activate()` sur D-Bus) : ouvre la fenêtre kDrive, avec l'activité, la pause et les préférences | kDrive lancé |
| En ligne | `xdg-open https://kdrive.infomaniak.com` | toujours |
| Redémarrer | Voir ci-dessous | kDrive lancé |
| Journaux | `xdg-open ~/.local/state/kDrive/logs` | toujours |

**Redémarrer** envoie `SIGTERM` à `kDrive_client`, ce qui fait aussi quitter le serveur, attend
jusqu'à 30 secondes que tous les processus kDrive (`kDrive_client` et le contenu de l'AppImage
montée, `.mount_kDrive*`) aient disparu, puis relance l'AppImage avec `uwsm-app`, comme le fait
Omarchy au démarrage. Les notifications sont suspendues pendant le redémarrage et les 20 secondes
qui suivent, le temps que la nouvelle icône apparaisse.

## Réglages

Les réglages sont dans le panneau et enregistrés dans l'entrée du widget de
`~/.config/omarchy/shell.json` :

```json
{ "id": "rle87.kdrive", "notify": true, "hideTrayIcon": true, "appImage": "~/Applications/kDrive.AppImage" }
```

| Clé | Défaut | Rôle |
|---|---|---|
| `notify` | `true` | Notifications (voir ci-dessous) |
| `hideTrayIcon` | `false` | Masque l'icône officielle de la zone de notification |
| `appImage` | `~/Applications/kDrive.AppImage` | AppImage lancée par « Démarrer » et « Redémarrer » ; `~/` est développé |
| `webUrl` | `https://kdrive.infomaniak.com` | Adresse du bouton « En ligne » (pas d'interface, à modifier dans `shell.json`) |
| `folder` | *(vide)* | Dossier utilisé quand kDrive n'est pas lancé (pas d'interface) |

### Masquage de l'icône officielle

Masquer l'icône revient à ajouter `kDrive_client` à la liste `hidden` de l'entrée `omarchy.tray`
(et à la retirer de `pinned`). Deux contraintes d'Omarchy imposent la méthode :

- un widget tiers ne peut modifier **que sa propre entrée** de `shell.json` (API de plugin cloisonnée) ;
- `omarchy bar set <id> <clé> <valeur> --json` transmet mal les listes au shell : une liste d'un seul
  élément devient du texte et une liste plus longue fait échouer la commande.

Le widget modifie donc `shell.json` avec `jq`, en **une seule écriture** qui met à jour à la fois
l'entrée `omarchy.tray` et son propre réglage `hideTrayIcon` (via un fichier temporaire puis `mv`).
Le shell surveille le fichier et le recharge.

L'icône masquée reste fonctionnelle : le bouton « Fenêtre kDrive » l'active toujours.

## Notifications

Avec `notify` activé, le widget envoie une notification (`notify-send -a kDrive`) quand :

- l'état **passe** à `error`, `stopped`, `signin`, `undefined` ou `conflicts` ;
- kDrive **disparaît** (icône officielle absente), par exemple après un plantage.

Seuls les changements sont notifiés : pas de notification au chargement du widget, ni pendant un
redémarrage lancé depuis le panneau.

## Suivi du dépôt Infomaniak

### Le sous-module

`upstream/` pointe vers [Infomaniak/desktop-kDrive](https://github.com/Infomaniak/desktop-kDrive),
fixé sur le tag de la version prise en charge. Il sert de **référence** : le widget n'utilise aucun
code d'Infomaniak à l'exécution, seulement les messages traduits extraits dans `StatusStrings.js`.

`omarchy plugin add` clone le dépôt **sans** les sous-modules : `upstream/` est vide chez les
utilisateurs, ce qui évite de télécharger les sources de kDrive (et les liens symboliques qu'elles
contiennent, refusés par `omarchy plugin validate`).

### Le générateur (`tools/update-status-strings.py`)

1. **Vérifie** que `src/gui/clientgui.cpp` construit toujours l'infobulle avec les messages attendus
   (`tr("Sync is running.")`, etc.). Si l'un d'eux a disparu, il le signale et sort avec le code 1.
2. **Collecte** les traductions de ces messages dans `upstream/translations/client_*.ts`, en ignorant
   les traductions inachevées ou obsolètes.
3. **Détecte** le canal de communication utilisé par Linux, en lisant `useOldCommServer()` dans
   `src/server/appserver.h` : `old` tant que Linux utilise `OldCommServer`, `new` sinon.
4. **Écrit** `StatusStrings.js` (version d'Infomaniak, canal, formats, messages par état).

### La tâche GitHub (`.github/workflows/upstream.yml`)

Chaque lundi à 6 h 17 (UTC), ou à la demande depuis l'onglet *Actions* :

1. elle cherche le **dernier tag de version** `X.Y.Z` d'Infomaniak. Ce sont les tags et non les
   « releases » GitHub qui sont suivis : certaines versions Linux, comme la 3.8.8, n'ont qu'un tag ;
2. si le sous-module est déjà à ce tag, elle s'arrête ;
3. sinon, elle déplace le sous-module, lance le générateur et pousse une branche `upstream/<version>` ;
4. elle ouvre une **pull request** avec le lien de comparaison des sources et le rapport du
   générateur. Le titre est préfixé de ⚠️ si des messages de l'infobulle ont disparu.

Le rapport indique notamment `Linux GUI channel: new` le jour où Linux passe au nouveau canal.

**Quand fusionner ?** Une fois la nouvelle version de kDrive installée sur votre machine. Les
messages traduits suivent la version d'Infomaniak, et une version plus récente peut en avoir moins
(la 4.0.0 compte 60 traductions contre 153 pour la 3.8.8).

## Dépannage

### La synchronisation s'arrête toute seule (« User Abort. » / « Synchronisation arrêtée »)

Le panneau affiche alors les dernières erreurs du journal. Cause fréquente avec un disque dédié en
**ext4** : le dossier `lost+found`, créé par `mkfs` à la racine du disque et réservé à root.

En parcourant le dossier synchronisé, kDrive ne peut pas lire `lost+found`, reçoit une erreur
« accès refusé » et **arrête toute la synchronisation**. Le journal contient alors :

```
folderwatcher_linux.cpp - Unhandled error in FolderWatcher_linux::inotifyAddWatch: path='…/lost+found' errno=13
localfilesystemobserverworker.cpp - Local snapshot generation failed … SystemError-FileAccessError
```

L'erreur survient pendant le parcours des fichiers, **avant** la vérification des exclusions
(`LocalFileSystemObserverWorker::exploreDir`) : exclure `lost+found` dans kDrive ne suffit donc pas.
Solution : donner le dossier à votre utilisateur, ce qui n'empêche pas `fsck` de s'en servir.

```bash
sudo chown "$USER:$USER" /chemin/du/disque/lost+found
```

Puis cliquez sur « Redémarrer » dans le panneau.

### « Le dossier n'est pas modifiable par votre utilisateur »

Le dossier synchronisé, ou le disque, appartient à un autre utilisateur. Pour un disque dédié :

```bash
sudo chown -R "$USER:$USER" /chemin/du/disque
```

### Le disque n'est pas monté au démarrage

Si le dossier kDrive est sur un disque externe ou secondaire, montez-le via `/etc/fstab` avec
l'option `nofail` pour ne pas bloquer le démarrage s'il est absent. Exemple pour un disque ext4 :

```
UUID=<uuid>  /run/media/<vous>/kDrive  ext4  rw,nosuid,nodev,relatime,nofail,x-systemd.device-timeout=10s,x-mount.mkdir  0 2
```

### Le widget affiche « kDrive n'est pas lancé » alors qu'il tourne

Le widget cherche l'icône de la zone de notification portant l'identifiant `kDrive_client`.
Vérifiez qu'elle est bien enregistrée :

```bash
busctl --user get-property org.kde.StatusNotifierWatcher /StatusNotifierWatcher \
  org.kde.StatusNotifierWatcher RegisteredStatusNotifierItems
```

### L'état reste « État inconnu »

kDrive affiche un message que le widget ne connaît pas (nouvelle version, ou langue sans
traduction). Le panneau montre le texte brut ; ouvrez une *issue* avec ce texte et votre version de
kDrive.

## Feuille de route

Infomaniak prépare pour kDrive 4 un nouveau canal sous Linux : dans la branche
`linux-v4/release-appimage`, `useOldCommServer()` renvoie `false` pour la version 4, ce qui active
`CommManager` et `GuiCommServer` (messages JSON sur socket).

Quand une version Linux utilisant ce canal sera publiée, la tâche de suivi le signalera, et le
widget pourra :

- mettre en pause et reprendre la synchronisation ;
- afficher la progression et l'activité récente ;
- remplacer davantage l'interface officielle.

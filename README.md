# kDrive pour Omarchy

Widget pour la barre d'[Omarchy](https://omarchy.org) qui affiche l'état de la synchronisation
[kDrive](https://www.infomaniak.com/kdrive) (Infomaniak) et regroupe les actions utiles dans un panneau.

*An Omarchy bar widget showing the kDrive (Infomaniak) sync state, with quick actions and settings.*

## Fonctionnalités

- **Icône d'état** dans la barre, aux couleurs du thème : à jour, en cours, en pause, arrêté, erreur,
  connexion requise, client non lancé. Elle passe en couleur d'alerte en cas de problème.
- **Panneau** :
  - état de chaque dossier synchronisé ;
  - disque du dossier (périphérique, système de fichiers, espace libre) et alerte si le dossier
    n'est pas modifiable ;
  - dernières erreurs du journal kDrive quand la synchronisation s'arrête ;
  - actions : ouvrir le dossier, ouvrir la fenêtre kDrive, ouvrir kDrive en ligne,
    redémarrer ou démarrer le client, ouvrir les journaux.
- **Réglages** dans le panneau : notifications, masquage de l'icône officielle de la zone de
  notification, chemin de l'AppImage.
- **Notifications** quand la synchronisation s'arrête, échoue, ou que kDrive se ferme.

## Installation

Prérequis : le client kDrive pour Linux (AppImage) installé et lancé.

```bash
omarchy plugin add https://github.com/rle87/omarchy-kdrive.git --enable
```

Le widget se place à droite de la barre. Mise à jour : `omarchy plugin update rle87.kdrive`.

Par défaut, l'AppImage est cherchée dans `~/Applications/kDrive.AppImage` (modifiable dans le panneau).
Pour lancer kDrive à l'ouverture de session, ajoutez dans `~/.config/hypr/autostart.lua` :

```lua
o.launch_on_start("/home/<vous>/Applications/kDrive.AppImage")
```

## Fonctionnement en bref

Le fonctionnement complet est décrit dans **[docs/fonctionnement.md](docs/fonctionnement.md)** :
architecture de kDrive, lecture de l'état, actions, réglages, suivi d'Infomaniak et dépannage.

```
kDrive.AppImage ── serveur de synchronisation
                     └── kDrive_client (interface) ── icône de notification « kDrive_client »
                                                              │ infobulle (D-Bus)
                                                              ▼
                                           widget rle87.kdrive ── panneau, actions, notifications
```

- **Lecture seule de l'état.** Sous Linux, kDrive 3.x relie son interface et son serveur par un canal
  qui n'accepte qu'un seul client, et le serveur s'arrête si ce client se déconnecte. Le widget ne
  s'y branche donc pas : il lit l'infobulle de l'icône officielle, dans toutes les langues de kDrive.
- **Pilotage de l'extérieur** : ouvrir la fenêtre kDrive, redémarrer le client, ouvrir le dossier.
  **Pause et reprise** passent encore par la fenêtre kDrive.
- **Suivi d'Infomaniak** : les sources officielles sont en sous-module dans `upstream/`. Chaque
  semaine, une tâche GitHub passe au dernier tag de version, régénère les messages traduits, vérifie
  la compatibilité et ouvre une pull request avec un rapport. Elle signalera aussi l'arrivée sous
  Linux du nouveau canal de kDrive 4, qui permettra de piloter kDrive directement.

## Dépannage rapide

- **La synchronisation s'arrête toute seule** (« Synchronisation arrêtée ») sur un disque ext4 dédié :
  le dossier `lost+found`, réservé à root, bloque kDrive, et l'exclure dans kDrive ne suffit pas.
  `sudo chown "$USER:$USER" /chemin/du/disque/lost+found`, puis « Redémarrer » dans le panneau.
- **« Le dossier n'est pas modifiable »** : le dossier appartient à un autre utilisateur.
- **« État inconnu »** : message de kDrive non reconnu ; le panneau affiche le texte brut.

Détails et autres cas : [docs/fonctionnement.md#dépannage](docs/fonctionnement.md#dépannage).

## Développement

```bash
git clone --recurse-submodules https://github.com/rle87/omarchy-kdrive.git
cd omarchy-kdrive
tools/update-status-strings.py      # régénère StatusStrings.js depuis upstream/
```

| Fichier | Rôle |
|---|---|
| `manifest.json` | Déclaration du plugin Omarchy |
| `Panel.qml` | Widget de barre et panneau |
| `Status.js` | Analyse de l'infobulle kDrive |
| `StatusStrings.js` | Messages d'état traduits, **généré** |
| `tools/update-status-strings.py` | Générateur et vérifications de compatibilité |
| `.github/workflows/upstream.yml` | Suivi hebdomadaire des versions d'Infomaniak |
| `docs/fonctionnement.md` | Documentation détaillée |

Pour tester une modification, copiez les fichiers du plugin dans
`~/.config/omarchy/plugins/rle87.kdrive/` : le shell recharge le plugin à l'enregistrement.

## Licence

GPL-3.0, comme le client kDrive dont ce projet reprend les messages traduits. Projet indépendant,
non affilié à Infomaniak.

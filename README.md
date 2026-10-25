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

## Fonctionnement et limites

Sous Linux, kDrive 3.x fait communiquer son interface et son serveur de synchronisation par un canal
qui n'accepte **qu'un seul client** : un second client déconnecterait l'interface officielle, et le
serveur s'arrête quand l'interface se déconnecte. Le widget ne s'y branche donc pas.

Il lit l'état dans l'infobulle de l'icône officielle (StatusNotifierItem `kDrive_client`), en
reconnaissant les messages dans toutes les langues de kDrive, et pilote le client de l'extérieur.
Conséquence : **pause et reprise** passent encore par la fenêtre kDrive.

Infomaniak prépare pour kDrive 4 un nouveau canal sous Linux (branche `linux-v4/*`). Quand il sera
publié, le suivi automatique ci-dessous le signalera, et le widget pourra piloter kDrive directement.

## Suivi du dépôt Infomaniak

Les sources officielles ([Infomaniak/desktop-kDrive](https://github.com/Infomaniak/desktop-kDrive))
sont liées en sous-module dans `upstream/`, fixées sur la version prise en charge.

Chaque semaine, la tâche GitHub [`Track kDrive upstream`](.github/workflows/upstream.yml) :

1. cherche le dernier tag de version d'Infomaniak ;
2. met à jour le sous-module et régénère `StatusStrings.js` (messages d'état traduits) ;
3. vérifie que l'interface kDrive construit toujours l'infobulle avec ces messages, et quel canal
   de communication Linux utilise ;
4. ouvre une pull request avec ce rapport (titre marqué ⚠️ si l'infobulle a changé).

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

Pour tester une modification, copiez les fichiers du plugin dans
`~/.config/omarchy/plugins/rle87.kdrive/` : le shell recharge le plugin à l'enregistrement.

## Licence

GPL-3.0, comme le client kDrive dont ce projet reprend les messages traduits. Projet indépendant,
non affilié à Infomaniak.

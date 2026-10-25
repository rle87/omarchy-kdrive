# Sécurité

## Signaler une faille

Merci de **ne pas** ouvrir d'issue publique pour une faille de sécurité.
Utilisez le signalement privé de GitHub : onglet **Security** du dépôt, puis
**Report a vulnerability**.

Vous recevrez une réponse dans les meilleurs délais. Ce projet est maintenu
bénévolement par une seule personne.

## Périmètre

Ce dépôt contient un plugin pour le shell d'Omarchy. Un plugin s'exécute **sans
isolation** dans le processus `omarchy-shell`, avec les droits de votre
utilisateur. Le plugin :

- lit l'infobulle de l'icône kDrive sur D-Bus ;
- lance des commandes locales : `xdg-open`, `notify-send`, `findmnt`, `df`,
  `pkill`/`pgrep` sur les processus kDrive, `uwsm-app` pour lancer l'AppImage
  configurée, `jq` pour modifier `~/.config/omarchy/shell.json` ;
- lit les journaux kDrive dans `~/.local/state/kDrive/logs`.

Il n'envoie aucune donnée sur le réseau et ne demande aucun privilège root.

Les failles du client kDrive lui-même sont à signaler à Infomaniak :
<https://github.com/Infomaniak/desktop-kDrive>.

## Versions prises en charge

Seule la dernière version de la branche `main` est maintenue.

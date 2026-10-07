# Ultimate Wine Toolbox pour Batocera

[English](README.md) | [Français](README.fr.md)

**Ultimate Wine Toolbox** est une toolbox Wine / Proton / UMU conçue pour Batocera.

Créée par **Thomsonito**.

## Fonctionnalités

- interface Français / Anglais
- intégration avec UMU Runner Toolbox
- Starter Pack de runners Wine
- gestion individuelle des runners Wine classiques
- prise en charge des anciens GE-Proton adaptés à Batocera
- gestion globale et par jeu de MangoHud
- gestion de bundles DXVK / VKD3D
- sélection globale et par jeu de DXVK
- maintenance des Wine bottles et détection des bottles orphelines
- diagnostics des runners et de DXVK / VKD3D
- outils de squash / unsquash `.wine` / `.wsquashfs`
- suppression de jeux Windows
- analyse, nettoyage, organisation et restauration sécurisés de `batocera.conf`
- export / import additif des configurations Windows entre machines Batocera
- sauvegarde automatique avant les opérations destructives sur `batocera.conf`
- lanceur natif Batocera dans Ports avec prise en charge Pad2Key

## Nouveautés de la v0.2.0

- Création guidée de WSquashFS avec sauvegardes externalisées, test du jeu et reprise automatique.
- Sélection graphique des dossiers de sauvegarde, inspection et alternative `user.reg`.
- Sauvegarde/remplacement et renommage des archives, contrôle d’intégrité rapide ou complet et tutoriel intégré.
- Profils MangoHud minimaliste, par défaut et détaillé.
- Normalisation facultative des noms des runners, sauvegarde des références modifiées et installation multiple UMU sans interruption.

L’externalisation via `SAVEDIR=` nécessite **Batocera v42 ou supérieure**. Le contrôle d’intégrité complet nécessite le support `-pf` d’unsquashfs.

Création WSquashFS basée sur le script du Grand Maître **DreamerCG** :)

[Notes de version complètes](release-notes/v0.2.0.md)

## Installation

À exécuter en `root` sur Batocera :

```bash
curl -fsSL https://raw.githubusercontent.com/Thomson67/ultimate-wine-toolbox/main/install.sh | bash
```

Les fichiers de la Toolbox sont installés dans :

```text
/userdata/system/ultimate-wine-toolbox
```

La Toolbox est ensuite accessible depuis :

```text
Ports -> Ultimate Wine Toolbox
```

## Sécurité

Ultimate Wine Toolbox adopte volontairement un comportement conservateur lorsqu'elle modifie les données Batocera :

- les runners existants ne sont pas écrasés automatiquement
- les opérations destructives nécessitent une confirmation
- `batocera.conf` est sauvegardé avant toute modification
- les réglages Batocera `windows.dxvk` et `windows.dxvk_hud` sont protégés
- les installations DXVK externes ou personnalisées ne sont pas supprimées automatiquement
- les liens symboliques ne sont pas suivis lors de la suppression de jeux
- la migration des anciennes versions de développement préserve d'abord les données utilisateur avant de supprimer les anciens chemins

## Transfert des configurations Windows

Les exports de configuration Windows sont enregistrés dans :

```text
/userdata/system/ultimate-wine-toolbox/exports/windows-config
```

Les imports sont additifs : les réglages Windows déjà présents sur la machine cible sont conservés. Si une clé importée existe déjà localement, la valeur locale reste prioritaire.

Les réglages Batocera `windows.dxvk` et `windows.dxvk_hud` sont volontairement exclus des exports et imports.

## Logs

Log de lancement depuis Ports :

```bash
cat /userdata/system/logs/ultimate-wine-toolbox/port-launch.log
```

Dernier log de session de la Toolbox :

```bash
cat /userdata/system/logs/ultimate-wine-toolbox/latest.log
```

## Releases

Les versions stables sont publiées dans la section **Releases** du dépôt GitHub :

https://github.com/Thomson67/ultimate-wine-toolbox/releases

## Migration depuis les anciennes versions de développement

L'installation d'Ultimate Wine Toolbox par-dessus une ancienne version de développement migre automatiquement les données utiles vers les nouveaux chemins.

Les anciens lanceurs, hooks et répertoires runtime ne sont supprimés qu'après une migration réussie.

Les runners Wine/UMU, les jeux, les sauvegardes et les Wine bottles sont conservés.

## Mettre à jour un WSquashFS (version de test)

Dans Gestion des WSquashFS, l’option suit immédiatement la création. Sélectionnez une archive contenant un préfixe Wine et un dossier contenant directement les fichiers de la nouvelle version du jeu. Le dossier source est déplacé dans le dossier du jeu identifié par `autorun.cmd` (souvent `drive_c/game`) d’un préfixe de test distinct. Les archives de type `.pc` sans préfixe Wine ne sont pas prises en charge.

Sélectionnez l’exécutable, puis testez le lancement, la manette, le chargement de votre progression et une nouvelle sauvegarde. Le runner et les options du jeu sont repris ; le test utilise une copie des sauvegardes. Au retour, confirmez les règles de sauvegarde existantes ou choisissez un autre emplacement avec la détection ou l’explorateur.

La nouvelle archive doit passer un contrôle complet avant le remplacement. À la fin, choisissez « Sauvegarder l’ancien WSquashFS puis remplacer » ou « Remplacer directement ». Les sauvegardes originales et les modifications de `batocera.conf` restent sauvegardées. En cas d’échec de compression, les sauvegardes originales restent en place. Une mise à jour en attente se reprend depuis le menu. La copie des sauvegardes de test reste conservée ; la suppression du préfixe de travail est proposée à la fin.

Prévoyez de la place pour l’extraction, les sauvegardes de test et la nouvelle archive. La gestion `SAVEDIR=` nécessite Batocera v42 ou supérieur.

La mise à jour propose d’abord le lancement défini dans `autorun.cmd`, y compris les `start.bat` originaux recopiés dans le nouveau dossier aux mêmes emplacements. Vous pouvez choisir un autre exécutable. Sans `SAVEDIR=`, les liens existants vers `/userdata/saves/windows` ou un de ses sous-dossiers sont détectés, restaurés dans le jeu mis à jour et proposés par défaut. Un lien vers la racine utilise une vue de test séparée, sans copier les sauvegardes des autres jeux. Les références littérales à cette racine dans les fichiers batch sont adaptées pour le test puis restaurées ; les noms calculés par des scripts ne sont pas évalués. Vous pouvez copier un dossier de progression connu avant le test, puis conserver les liens ou sélectionner un autre emplacement au retour.

Avant le déplacement, l’ancien dossier du jeu est renommé en `<nom>.bak`. Le dossier mis à jour reprend le nom exact du dossier original ; le dossier source disparaît donc de son emplacement précédent. Le `.bak` est conservé jusqu’à validation du lancement, puis supprimé avant recompression. Les liens de sauvegarde contenus dans l’ancien dossier sont restaurés aux mêmes emplacements. Le déplacement nécessite un même système de fichiers et ne bascule jamais vers une copie implicite. Le choix de conserver les règles de sauvegarde ne demande plus de confirmation supplémentaire.

Le préfixe de test reprend le nom exact de l’archive en remplaçant `.wsquashfs` par `.wine`, balises comprises. Un dossier `.wine` existant déclenche le choix : remplacer le dossier, choisir un autre nom ou quitter. Les réglages ES du `.wsquashfs` sont prioritaires ; s’il n’a aucun réglage spécifique, ceux du `.wine` existant sont repris. Les réglages de `batocera.conf` sont sauvegardés avant modification. Un dossier contenant la source de mise à jour ne peut pas être supprimé : choisissez alors un autre nom de préfixe.

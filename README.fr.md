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

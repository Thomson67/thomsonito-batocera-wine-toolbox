# Ultimate Wine Toolbox for Batocera

[English](README.md) | [Français](README.fr.md)

**Ultimate Wine Toolbox** is a Wine / Proton / UMU toolbox designed for Batocera.

Created by **Thomsonito**.

## Features

- French / English interface
- UMU Runner Toolbox integration
- Wine Runner Starter Pack
- classic Wine runner management
- GE-Proton legacy support for Batocera
- MangoHud global and per-game management
- DXVK / VKD3D bundle management
- global and per-game DXVK selection
- Wine bottle maintenance and orphan detection
- runner and DXVK / VKD3D diagnostics
- `.wine` / `.wsquashfs` squash and unsquash tools
- Windows game removal
- safe `batocera.conf` analysis, cleanup, organization and restore
- additive Windows configuration export / import between Batocera machines
- automatic backups before destructive `batocera.conf` operations
- native Batocera Ports launcher and Pad2Key support

## New in v0.2.0

- Guided WSquashFS creation with external saves, game testing and automatic resume.
- Graphical save-folder selection, inspection and a `user.reg` alternative.
- Archive backup/replacement and renaming, quick/full integrity checks and a built-in guide.
- Minimal, default and detailed MangoHud profiles.
- Optional runner-name migration with reference backups, and uninterrupted multi-runner UMU installation.

Save externalization through `SAVEDIR=` requires **Batocera v42 or later**. Full integrity checks require unsquashfs `-pf` support.

WSquashFS creation is based on **DreamerCG**’s script.

[Full release notes](release-notes/v0.2.0.md)

## Installation

Run as `root` on Batocera.

Quick install:

```bash
curl -fsSL https://bit.ly/ultimate-wine-toolbox | bash
```

Direct GitHub install:

```bash
curl -fsSL https://raw.githubusercontent.com/Thomson67/ultimate-wine-toolbox/main/install.sh | bash
```

Installed files are stored under:

```text
/userdata/system/ultimate-wine-toolbox
```

Launch from:

```text
Ports -> Ultimate Wine Toolbox
```

## Safety

Ultimate Wine Toolbox is designed to remain conservative when modifying Batocera data:

- existing runners are not overwritten automatically
- destructive operations require confirmation
- `batocera.conf` is backed up before modification
- stock Batocera `windows.dxvk` and `windows.dxvk_hud` settings are protected
- external/custom DXVK installations are not removed automatically
- symbolic links are not followed during game deletion
- legacy development-build migration preserves user state before removing old paths

## Windows configuration transfer

Windows configuration exports are stored under:

```text
/userdata/system/ultimate-wine-toolbox/exports/windows-config
```

Imports are additive: existing Windows settings on the target machine are kept. If an imported key already exists locally, the local value has priority.

The stock Batocera settings `windows.dxvk` and `windows.dxvk_hud` are intentionally excluded from exports and imports.

## Logs

Port startup log:

```bash
cat /userdata/system/logs/ultimate-wine-toolbox/port-launch.log
```

Latest Toolbox session log:

```bash
cat /userdata/system/logs/ultimate-wine-toolbox/latest.log
```

## Releases

Stable releases are published in the GitHub **Releases** section:

https://github.com/Thomson67/ultimate-wine-toolbox/releases

## Legacy development-name migration

Installing Ultimate Wine Toolbox over an older development build automatically migrates the useful Toolbox state to the new paths and removes the old launcher, hooks and runtime directories only after the migration succeeds.

Wine/UMU runners, games, saves and bottles are preserved.

## Update a WSquashFS (test version)

In WSquashFS Management, Update follows Create. Select a Wine-prefix archive and a directory containing the updated game files directly. The source is copied into `drive_c/game` of a separate test prefix. `.pc` archives without a Wine prefix are not supported.

Select the executable and test launch, controller input, loading your progress and saving again. The original runner and game options are copied; testing uses a separate save copy. On return, confirm the previous save rules or select another location through detection or the graphical browser.

A full integrity check must pass before replacement. The old archive, original saves and changes to `batocera.conf` are backed up. Compression failure leaves original saves in place. Resume pending updates from the menu. Test saves remain available; deleting the working prefix is optional at completion.

Allow space for extraction, the updated game copy, test saves and the new archive. `SAVEDIR=` requires Batocera v42 or newer.

Updates first offer the launch command from `autorun.cmd`, preserving a custom `start.bat` when absent from the replacement folder. Another executable can be selected. Without `SAVEDIR=`, existing links to `/userdata/saves/windows` or its subdirectories are detected, restored in the updated game and offered by default. A root link uses a separate test view without copying other games' saves. Literal batch references to the save root are adapted for testing and restored afterwards; computed script names are not evaluated. A known progress folder can be copied before testing. On return, keep the links or choose another location.

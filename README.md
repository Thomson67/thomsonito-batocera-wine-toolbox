# Ultimate Wine Toolbox

Wine / Proton / UMU toolbox designed for Batocera.

Created by **Thomsonito**.

## Features

- French / English interface
- UMU Runner Toolbox integration
- Wine runner Starter Pack
- individual Wine runner management
- MangoHud management
- DXVK / VKD3D bundle management
- Wine bottle maintenance
- runner and DXVK/VKD3D diagnostics
- .wine / .wsquashfs squash and unsquash tools
- Windows game removal
- safe `batocera.conf` analysis, cleanup, organization and restore
- additive Windows configuration export / import between Batocera machines
- automatic backups before destructive `batocera.conf` operations
- native Batocera Ports launcher and Pad2Key support

## Installation

Run as root:

```bash
cd /tmp
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

## Logs

Port startup log:

```bash
cat /userdata/system/logs/ultimate-wine-toolbox/port-launch.log
```

Latest Toolbox session log:

```bash
cat /userdata/system/logs/ultimate-wine-toolbox/latest.log
```

## Windows configuration transfer

Windows configuration exports are stored under:

```text
/userdata/system/ultimate-wine-toolbox/exports/windows-config
```

Imports are additive: existing Windows settings on the target machine are kept. If an imported key already exists locally, the local value has priority.

The stock Batocera settings `windows.dxvk` and `windows.dxvk_hud` are intentionally excluded from exports and imports.

## Legacy development-name migration

Installing Ultimate Wine Toolbox over an older development build automatically migrates the useful Toolbox state to the new paths and removes the old launcher, hooks and runtime directories.

Wine/UMU runners, games, saves and bottles are not removed by this migration.

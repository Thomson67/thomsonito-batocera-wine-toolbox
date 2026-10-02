# Thomsonito Batocera Wine Toolbox

Early development build of the umbrella Wine / Proton / UMU toolbox for Batocera.

## v0.1.0-dev2

Already implemented:

- modular Bash architecture
- French / English key-based localization from the start
- persistent language selector
- UMU Runner Toolbox detection, launch and stable installation
- Starter Pack status (installed / missing)
- classic Wine Starter Pack installation:
  - downloads only missing runners
  - SHA-256 verification
  - safe staging
  - existing runners are never overwritten
  - conservative free-space preflight
- UMU Starter Pack baseline delegated to UMU Runner Toolbox via `--install-runner`
- Batocera Ports launcher
- placeholders for Runner Manager, Graphics/Performance and Maintenance

### Starter Pack UMU baseline

- GE-Proton9-27-UMU
- GE-Proton10-10-UMU
- GE-Proton10-25-UMU
- proton-EM-10.0-37-HDR-UMU

### Install

```bash
chmod +x install.sh
./install.sh
```

Direct launch:

```bash
/userdata/system/thomsonito-wine-toolbox/toolbox/thomsonito-wine-toolbox.sh
```

## Startup logs

If the Port does not open, inspect:

```bash
cat /userdata/system/logs/thomsonito-wine-toolbox/port-launch.log
```

If xterm opens but the Toolbox exits, inspect:

```bash
cat /userdata/system/logs/thomsonito-wine-toolbox/latest.log
```

## v0.1.0-dev5

- fixed Batocera xterm startup by using an available Xft font (`DejaVu Sans Mono`)
- restored the intended Port -> xterm -> terminal launcher -> Toolbox startup chain
- added native Batocera Pad2Key/evmapy support using a matching `.sh.keys` file
- controller mapping kept aligned with UMU Runner Toolbox for compatibility
- removed the erroneous leading `\\` line from scripts
- stopped piping the interactive `dialog` UI through `tee`
- added explicit terminal clearing around `dialog` transitions to reduce screen offset/artifacts
- installer now synchronizes both the Ports launcher and its Pad2Key mapping

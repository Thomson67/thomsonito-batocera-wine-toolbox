# Release process

Ultimate Wine Toolbox uses the following release convention:

- development versions: `X.Y.Z-devN` on the `test` branch
- stable versions: `X.Y.Z` on `main`
- GitHub release tags: `vX.Y.Z`

## Normal release workflow

1. Develop and validate the next version on `test`.
2. Set `VERSION` to the final stable version (for example `0.1.1`).
3. Merge `test` into `main`.
4. GitHub Actions automatically:
   - validates the shell/Python sources;
   - builds `Ultimate-Wine-Toolbox-vX.Y.Z.zip`;
   - generates `Ultimate-Wine-Toolbox-vX.Y.Z.zip.sha256`;
   - creates the `vX.Y.Z` GitHub Release, or refreshes its assets if it already exists.

No ZIP or checksum needs to be created manually.

## Development installation

To install the current `test` branch on Batocera:

```bash
curl -fsSL https://raw.githubusercontent.com/Thomson67/ultimate-wine-toolbox/test/install.sh | WT_INSTALL_CHANNEL=test bash
```

The normal public installation command always installs the latest stable GitHub Release:

```bash
curl -fsSL https://raw.githubusercontent.com/Thomson67/ultimate-wine-toolbox/main/install.sh | bash
```

## Update assets

Stable releases must contain both:

```text
Ultimate-Wine-Toolbox-vX.Y.Z.zip
Ultimate-Wine-Toolbox-vX.Y.Z.zip.sha256
```

The Toolbox updater requires the SHA-256 asset and refuses an update when verification fails or the checksum is missing.

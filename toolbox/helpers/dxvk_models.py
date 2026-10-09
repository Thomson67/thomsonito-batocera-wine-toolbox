#!/usr/bin/env python3
"""Pinned Batocera graphics models, independent of the latest release catalogs."""
import json
import sys
from pathlib import Path

CATALOG = Path(__file__).resolve().parents[1] / "data/batocera-dxvk-models.json"
KINDS = ("dxvk", "vkd3d-proton", "dxvk-nvapi")


def main(argv):
    models = json.loads(CATALOG.read_text(encoding="utf-8"))
    if argv == ["list"]:
        for model in models:
            print("\t".join([model["id"], model["label"]] +
                            [model["components"][k]["version"] for k in KINDS]))
        return 0
    if len(argv) != 2 or argv[0] not in ("releases", "metadata"):
        return 2
    model = next((m for m in models if m["id"] == argv[1]), None)
    if model is None:
        return 2
    if argv[0] == "metadata":
        print(json.dumps(model, indent=2))
    else:
        for kind in KINDS:
            part = model["components"][kind]
            print("\t".join(["v" + part["version"], part["url"],
                             "sha256:" + part["sha256"] if part["sha256"] else ""]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

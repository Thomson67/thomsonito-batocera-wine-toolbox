#!/usr/bin/env python3
"""Compatibility rules derived from upstream DXVK-NVAPI release notes.

Upstream publishes requirements in prose, not as a machine-readable matrix.
Keep these thresholds aligned with explicit compatibility notes in release
changelogs. Optional feature requirements are warnings, not blockers.
"""
import re
import sys


def version_tuple(value):
    match = re.search(r"(?<!\\d)(\\d+(?:\\.\\d+){1,3})", value.lstrip("v"))
    if not match:
        raise ValueError(f"invalid version: {value}")
    return tuple(int(part) for part in match.group(1).split("."))


def evaluate(dxvk_version, vkd3d_version, nvapi_version):
    dxvk = version_tuple(dxvk_version)
    vkd3d = version_tuple(vkd3d_version)
    nvapi = version_tuple(nvapi_version)
    minimum_dxvk = (2, 1) if nvapi >= (0, 6, 1) else None
    compatible = minimum_dxvk is None or dxvk >= minimum_dxvk

    limitations = []
    if nvapi >= (0, 6, 4) and dxvk < (2, 3):
        limitations.append("hdr")
    if nvapi >= (0, 7, 0) and vkd3d < (2, 12):
        limitations.append("reflex")
    if nvapi >= (0, 8, 0) and vkd3d < (2, 14):
        limitations.append("optical-flow")
    if nvapi >= (0, 9, 2) and vkd3d < (3, 0, 1):
        limitations.append("shader-extensions")

    return compatible, limitations


def main(argv):
    if len(argv) != 4 or argv[1] != "check":
        print("usage: dxvk_compat.py check DXVK_VERSION VKD3D_VERSION NVAPI_VERSION", file=sys.stderr)
        return 2
    try:
        compatible, limitations = evaluate(argv[2], argv[3], argv[4])
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    print(("compatible" if compatible else "incompatible") +
          ((" " + " ".join(limitations)) if limitations else ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

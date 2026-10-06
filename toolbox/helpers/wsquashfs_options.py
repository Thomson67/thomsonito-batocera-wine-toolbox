#!/usr/bin/env python3
"""Read and update the builder's per-game Batocera options atomically."""
import argparse
import os
from pathlib import Path

KEYS = ("enable_hidraw", "dxvk", "fps_limit", "force_large_adress", "virtual_desktop")


def key_prefix(rom):
    return 'windows["' + rom.replace("=", "").replace("#", "") + '"].'


def read_values(lines, rom):
    prefix = key_prefix(rom)
    values = {}
    for line in lines:
        line = line.strip()
        for key in KEYS:
            if line.startswith(prefix + key + "="):
                values[key] = line.split("=", 1)[1]
    return values


def write_values(path, lines, rom, values):
    prefix = key_prefix(rom)
    lines = [line for line in lines if not any(line.lstrip().startswith(prefix + key + "=") for key in values)]
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"
    for key, value in values.items():
        if value != "inherit":
            lines.append(prefix + key + "=" + value + "\n")
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + f".uwt-options-{os.getpid()}")
    try:
        tmp.write_text("".join(lines), encoding="utf-8", errors="surrogateescape")
        if path.exists():
            os.chmod(tmp, path.stat().st_mode & 0o777)
        os.replace(tmp, path)
    finally:
        tmp.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("get", "set", "copy"))
    parser.add_argument("conf", type=Path)
    parser.add_argument("rom")
    parser.add_argument("key_or_destination")
    parser.add_argument("value", nargs="?", choices=("0", "1", "inherit"))
    args = parser.parse_args()
    lines = args.conf.read_text(encoding="utf-8", errors="surrogateescape").splitlines(keepends=True) if args.conf.exists() else []
    if args.action == "copy":
        values = read_values(lines, args.rom)
        write_values(args.conf, lines, args.key_or_destination, {key: values.get(key, "inherit") for key in KEYS})
        return
    if args.key_or_destination not in KEYS:
        parser.error("unsupported game option")
    if args.action == "get":
        print(read_values(lines, args.rom).get(args.key_or_destination, "inherit"))
    else:
        if args.value is None:
            parser.error("set needs a value")
        write_values(args.conf, lines, args.rom, {args.key_or_destination: args.value})


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
import argparse
import json
import os
import re
import sys
from pathlib import Path

EXCLUDED_DIRS = {
    "windows", "system32", "syswow64", "_commonredist",
    "program files", "program files (x86)", "programdata",
    "$recycle.bin", "temp", "tmp",
}
EXCLUDED_EXE_NAMES = (
    "unins", "uninstall", "setup", "install", "crash", "report",
    "bug", "config", "settings", "updater", "update",
    "redistributable", "redist", "dxsetup",
)
PRIORITY_EXE_NAMES = ("game", "start", "play", "run", "main")
PRIORITY_DIRS = ("game", "bin", "binaries", "win32", "win64")
SAVE_ROOTS = (
    "AppData/Local", "AppData/LocalLow", "AppData/Roaming",
    "Documents", "Saved Games",
)
SAVE_EXTENSIONS = {
    ".sav", ".save", ".dat", ".profile", ".slot", ".bin", ".json",
}
POSITIVE_PATH = (
    "save", "saved", "savegame", "savegames", "profile", "profiles",
    "userdata", "user data",
)
NEGATIVE_PATH = (
    "cache", "shader", "log", "logs", "crash", "temp", "tmp",
    "d3dscache", "webcache",
)


def clean_game_name(name: str) -> str:
    name = re.sub(r"(?i)\bbuild\b[.\s]*\d*", " ", name)
    name = re.sub(r"(?i)\bv?\d+(?:\.\d+){1,}\b", " ", name)
    name = name.replace(".", " ")
    return re.sub(r"\s+", " ", name).strip()


def find_exes(prefix: Path):
    game_dir = prefix / "drive_c" / "game"
    rows = []
    if not game_dir.is_dir():
        return rows
    for root, dirs, files in os.walk(game_dir):
        dirs[:] = [
            d for d in dirs
            if d.casefold() not in EXCLUDED_DIRS
            and not d.casefold().endswith((".wine", ".pc"))
        ]
        root_p = Path(root)
        rel_root = root_p.relative_to(prefix)
        for filename in files:
            low = filename.casefold()
            if not low.endswith((".exe", ".bat", ".cmd")):
                continue
            if any(x in low for x in EXCLUDED_EXE_NAMES):
                continue
            rel = (rel_root / filename).as_posix()
            score = 0
            if any(x in low for x in PRIORITY_EXE_NAMES):
                score += 50
            if low.endswith((".bat", ".cmd")) and any(x in low for x in ("start", "launch", "play", "run")):
                score += 20
            rel_low = rel_root.as_posix().casefold()
            if any(x in rel_low for x in PRIORITY_DIRS):
                score += 30
            depth = len(rel_root.parts)
            score += max(0, 25 - depth * 4)
            folder_name = rel_root.name.casefold()
            if folder_name and folder_name in low:
                score += 35
            if "shipping" in low:
                score += 35
            rows.append((score, rel))
    return sorted(rows, key=lambda x: (-x[0], x[1].casefold()))


def candidate_roots(prefix: Path):
    roots = []
    users = prefix / "drive_c" / "users"
    if users.is_dir():
        for user in users.iterdir():
            if not user.is_dir() or user.is_symlink():
                continue
            for rel in SAVE_ROOTS:
                p = user / rel
                if p.is_dir():
                    roots.append(p)
    userdata = prefix / "userdata"
    if userdata.is_dir():
        roots.append(userdata)

    game = prefix / "drive_c" / "game"
    if game.is_dir():
        try:
            for child in game.iterdir():
                if child.is_dir() and any(k in child.name.casefold() for k in POSITIVE_PATH):
                    roots.append(child)
        except OSError:
            pass
    return roots


def file_state(path: Path):
    try:
        st = path.stat()
        return [st.st_mtime_ns, st.st_size]
    except OSError:
        return None


def snapshot(prefix: Path):
    out = {}
    for base in candidate_roots(prefix):
        for root, dirs, files in os.walk(base):
            dirs[:] = [
                d for d in dirs
                if not any(x in d.casefold() for x in ("cache", "shadercache", "webcache", "temp"))
            ]
            root_p = Path(root)
            for filename in files:
                p = root_p / filename
                state = file_state(p)
                if state is None:
                    continue
                try:
                    rel = p.relative_to(prefix).as_posix()
                except ValueError:
                    continue
                out[rel] = state

    game = prefix / "drive_c" / "game"
    if game.is_dir():
        try:
            for p in game.iterdir():
                if p.is_file() and p.suffix.casefold() in SAVE_EXTENSIONS:
                    state = file_state(p)
                    if state:
                        out[p.relative_to(prefix).as_posix()] = state
        except OSError:
            pass
    return out


def score_save_dir(rel_dir: str, changed_files):
    low = rel_dir.casefold()
    score = 25
    reasons = []
    if any(x in low for x in POSITIVE_PATH):
        score += 45
        reasons.append("save-like path")
    if any(x in low for x in NEGATIVE_PATH):
        score -= 70
        reasons.append("cache/log-like path")

    ext_hits = sum(Path(f).suffix.casefold() in SAVE_EXTENSIONS for f in changed_files)
    if ext_hits:
        score += min(40, ext_hits * 10)
        reasons.append(f"{ext_hits} save-like file(s)")

    if "/documents/" in f"/{low}/" or "/saved games/" in f"/{low}/":
        score += 20
        reasons.append("standard user save location")
    if "/appdata/" in f"/{low}/":
        score += 10

    return score, ", ".join(reasons) or "changed during test"


def diff_snapshots(prefix: Path, before, after):
    changed = []
    for rel, state in after.items():
        if before.get(rel) != state:
            changed.append(rel)

    grouped = {}
    for rel in changed:
        parent = str(Path(rel).parent).replace("\\", "/")
        grouped.setdefault(parent, []).append(rel)

    candidates = []
    for parent, files in grouped.items():
        score, reason = score_save_dir(parent, files)
        if score <= 0:
            continue
        candidates.append((score, parent, len(files), reason))
    return sorted(candidates, key=lambda x: (-x[0], x[1].casefold()))


def cmd_exes(args):
    for score, rel in find_exes(Path(args.prefix)):
        print(f"{score}\t{rel}")


def cmd_snapshot(args):
    data = snapshot(Path(args.prefix))
    Path(args.output).write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")


def cmd_diff(args):
    before = json.loads(Path(args.before).read_text(encoding="utf-8"))
    after = snapshot(Path(args.prefix))
    for score, rel, count, reason in diff_snapshots(Path(args.prefix), before, after):
        print(f"{score}\t{count}\t{rel}\t{reason}")


def cmd_clean_name(args):
    print(clean_game_name(args.name))


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("exes")
    p.add_argument("prefix")
    p.set_defaults(func=cmd_exes)

    p = sub.add_parser("snapshot")
    p.add_argument("prefix")
    p.add_argument("output")
    p.set_defaults(func=cmd_snapshot)

    p = sub.add_parser("diff")
    p.add_argument("prefix")
    p.add_argument("before")
    p.set_defaults(func=cmd_diff)

    p = sub.add_parser("clean-name")
    p.add_argument("name")
    p.set_defaults(func=cmd_clean_name)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()

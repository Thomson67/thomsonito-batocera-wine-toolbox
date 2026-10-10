#!/usr/bin/env python3
"""Limited 7z-compatible fallback for the official ReShade ZIP installer."""
from pathlib import Path
import sys
import zipfile


def extract(args):
    if len(args) != 3 or args[:2] != ['-y', 'e']:
        raise ValueError('unsupported extraction arguments')
    with zipfile.ZipFile(args[2]) as archive:
        payloads = {}
        for name in ('ReShade32.dll', 'ReShade64.dll'):
            info = archive.getinfo(name)
            if info.file_size > 64 * 1024 * 1024:
                raise ValueError('ReShade DLL exceeds extraction limit')
            payloads[name] = archive.read(info)
        for name, data in payloads.items():
            if not data.startswith(b'MZ'):
                raise ValueError('invalid ReShade DLL')
        for name, data in payloads.items():
            Path(name).write_bytes(data)


if __name__ == '__main__':
    try:
        extract(sys.argv[1:])
    except (OSError, ValueError, KeyError, zipfile.BadZipFile) as exc:
        print('ReShade extraction failed (install 7z/7za for older formats): ' + str(exc), file=sys.stderr)
        sys.exit(1)

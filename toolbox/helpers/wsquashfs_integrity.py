#!/usr/bin/env python3
"""Read-only SquashFS checks; full mode streams decompressed data to /dev/null."""
import argparse
import os
from pathlib import Path
import signal
import subprocess
import time


def run(command, log, cancel):
    with open(os.devnull, 'wb') as sink:
        process = subprocess.Popen(command, stdout=sink, stderr=log, start_new_session=True)
        while process.poll() is None:
            if cancel.exists():
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                return 130
            time.sleep(0.1)
        return process.returncode


def check(archive, mode, log_path, cancel, executable='unsquashfs'):
    with log_path.open('ab', buffering=0) as log:
        log.write((f'\nArchive: {archive}\nMode: {mode}\n').encode())
        if not archive.is_file():
            log.write(b'Archive is missing or is not a regular file.\n')
            return 1
        if cancel.exists():
            return 130
        if mode == 'full':
            help_result = subprocess.run([executable, '-help'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            if b'-pf ' not in help_result.stdout and b'-pseudo-file' not in help_result.stdout:
                log.write(b'Full check unsupported: unsquashfs has no pseudo-file output option.\n')
                return 3
        code = run([executable, '-s', str(archive)], log, cancel)
        if code:
            return 130 if code == 130 else 1
        command = [executable, '-ll', str(archive)] if mode == 'quick' else [executable, '-pf', os.devnull, str(archive)]
        code = run(command, log, cancel)
        log.write((f'Result code: {code}\n').encode())
        return 0 if code == 0 else (130 if code == 130 else 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('quick', 'full'))
    parser.add_argument('archive', type=Path)
    parser.add_argument('log', type=Path)
    parser.add_argument('cancel', type=Path)
    args = parser.parse_args()
    try:
        code = check(args.archive, args.mode, args.log, args.cancel)
    except (OSError, subprocess.SubprocessError) as error:
        with args.log.open('a') as log:
            log.write(f'Check could not be completed: {error}\n')
        code = 1
    raise SystemExit(code if code >= 0 else 1)


if __name__ == '__main__':
    main()

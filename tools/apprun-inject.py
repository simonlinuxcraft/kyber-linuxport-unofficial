#!/usr/bin/env python3
# Inserts a block (stdin) into AppRun once, marked by a sentinel. The block
# goes in front of the first needle found, or after it with "after".
# Usage: apprun-inject.py APPRUN SENTINEL before|after NEEDLE... < block
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
sentinel, mode, needles = sys.argv[2], sys.argv[3], sys.argv[4:]
block = sys.stdin.read()
src = path.read_text()
if sentinel in src:
    sys.exit(0)
for needle in needles:
    if needle in src:
        if mode == "after":
            new = needle + "\n\n" + block
        else:
            new = block + "\n" + needle
        path.write_text(src.replace(needle, new, 1))
        break

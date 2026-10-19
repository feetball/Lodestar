#!/usr/bin/env python3
"""Finds the pixels that are not red in the night-mode pictures of the visual review.

    night_leaks.py <folder with the PNGs> [--ignore-top N]

In night mode every pixel the app draws must be red (green and blue at zero). A picture is listed when more than a few
pixels have a green or blue channel above a small threshold; the bounding box of those pixels is printed so that the
place can be looked at. The status bar (the top N pixels, default 150) is ignored: the Simulator draws it white.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

THRESHOLD = 24      # channel value above which green or blue counts as "not red"
MINIMUM_PIXELS = 40


def main() -> None:
    args = sys.argv[1:]
    ignore_top = 150
    if "--ignore-top" in args:
        index = args.index("--ignore-top")
        ignore_top = int(args[index + 1])
        del args[index:index + 2]
    folder = Path(args[0])
    flagged = 0
    # capture.sh names a picture <name>-<d|n>-<page>.png; n is night mode.
    for path in sorted(folder.rglob("*-n-[0-9]*.png")):
        picture = np.asarray(Image.open(path).convert("RGB")).astype(int)
        body = picture[ignore_top:]
        leak = (body[:, :, 1] > THRESHOLD) | (body[:, :, 2] > THRESHOLD)
        count = int(leak.sum())
        if count < MINIMUM_PIXELS:
            continue
        flagged += 1
        rows, columns = np.where(leak)
        print(f"{path.name}: {count} pixels, box x {columns.min()}-{columns.max()}, "
              f"y {rows.min() + ignore_top}-{rows.max() + ignore_top}")
    print(f"{flagged} picture(s) with pixels that are not red")


if __name__ == "__main__":
    main()

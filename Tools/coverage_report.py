#!/usr/bin/env python3
"""Prints line coverage per source file and per folder from the llvm-cov JSON that
`swift test --enable-code-coverage` writes (`swift test --show-codecov-path` prints where it is).

Usage: coverage_report.py <codecov.json> <path fragment of the sources to report, e.g. LodestarKit/Sources/> [minimum total percent]

Only files whose path contains the fragment are counted. With a minimum, the exit code is 1 when the total is below it.
"""
import json
import sys
from collections import defaultdict


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    path, fragment = sys.argv[1], sys.argv[2]
    minimum = float(sys.argv[3]) if len(sys.argv) > 3 else None
    with open(path) as handle:
        data = json.load(handle)

    files = []
    folders = defaultdict(lambda: [0, 0])
    total_count = total_covered = 0
    for entry in data["data"][0]["files"]:
        name = entry["filename"]
        if fragment not in name:
            continue
        lines = entry["summary"]["lines"]
        relative = name.split(fragment, 1)[1].lstrip("/")
        files.append((lines["percent"], lines["covered"], lines["count"], relative))
        folder = "/".join(relative.split("/")[:2]) if relative.count("/") >= 2 else relative.split("/")[0]
        folders[folder][0] += lines["covered"]
        folders[folder][1] += lines["count"]
        total_covered += lines["covered"]
        total_count += lines["count"]

    out = []
    out.append("## Line coverage by folder")
    out.append("")
    out.append("| Folder | Covered | Lines | % |")
    out.append("|---|---:|---:|---:|")
    for folder, (covered, count) in sorted(folders.items(), key=lambda item: (item[1][0] / item[1][1] if item[1][1] else 1.0)):
        percent = 100.0 * covered / count if count else 100.0
        out.append(f"| {folder} | {covered} | {count} | {percent:.1f} |")
    total_percent = 100.0 * total_covered / total_count if total_count else 100.0
    out.append(f"| **Total** | **{total_covered}** | **{total_count}** | **{total_percent:.1f}** |")
    out.append("")
    out.append("## Files, lowest coverage first")
    out.append("")
    out.append("| % | Covered | Lines | File |")
    out.append("|---:|---:|---:|---|")
    for percent, covered, count, relative in sorted(files):
        out.append(f"| {percent:.1f} | {covered} | {count} | {relative} |")
    print("\n".join(out))

    if minimum is not None and total_percent < minimum:
        print(f"\nTotal line coverage {total_percent:.1f}% is below the minimum of {minimum:.1f}%.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

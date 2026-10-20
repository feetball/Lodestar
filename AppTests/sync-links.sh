#!/usr/bin/env bash
# Rebuilds AppTests/Sources/AppCore from appcore-files.txt: one symlink per app source file (paths relative to Lodestar/).
# The package compiles the app's own files, the way WidgetTests compiles WidgetShared/Core; add a line to the list and run this
# script to bring another file under test. A file can only join if everything it uses is in the list (or in LodestarKit).
set -euo pipefail
cd "$(dirname "$0")"
dir=Sources/AppCore
find "$dir" -type l -delete
while IFS= read -r file; do
    [ -z "$file" ] && continue
    case "$file" in \#*) continue ;; esac
    [ -f "../Lodestar/$file" ] || { echo "missing: Lodestar/$file" >&2; exit 1; }
    ln -s "../../../Lodestar/$file" "$dir/$(basename "$file")"
done < appcore-files.txt
echo "$(find "$dir" -type l | wc -l) links"

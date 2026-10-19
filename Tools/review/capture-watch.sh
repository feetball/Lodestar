#!/bin/bash
# Captures the Apple Watch app and the complication views in the watchOS Simulator (see LodestarWatch/WatchReviewMode.swift).
#
#   capture-watch.sh <udid> <out-dir> <shots-file>
#
# Each line of the shots file is   name | arguments   where the arguments follow -LodestarReview (view=app|complications,
# scrollTo=<id>, type=large). The watch app has no driver: a screen is taken once it no longer changes.
set -u

UDID="$1"
OUT="$2"
SHOTS="$3"
BUNDLE=net.kuecker.Lodestar.watchkitapp
COMMON="date=2026-10-19T05:00:00Z place=36.0544,-112.1401,2130,America/Phoenix"

mkdir -p "$OUT"

shoot() {
  xcrun simctl io "$UDID" screenshot --type=png "$1" >/dev/null 2>&1
}

settle() {
  local file="$1" tries=0
  sleep 4
  shoot "$file"
  while [ "$tries" -lt 20 ]; do
    sleep 1.5
    shoot "$file.next"
    if cmp -s "$file" "$file.next"; then
      rm -f "$file.next"
      return 0
    fi
    mv "$file.next" "$file"
    tries=$((tries + 1))
  done
  echo "  note: $file still changing after $tries tries"
}

while IFS='|' read -r name args; do
  name="$(echo "$name" | xargs)"
  case "$name" in ''|'#'*) continue ;; esac
  args="$(echo "$args" | xargs)"
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" -LodestarReview $COMMON $args >/dev/null 2>&1 \
    || echo "  warning: the watch app did not launch for $name"
  settle "$OUT/$name.png"
  echo "captured $name"
done < "$SHOTS"

xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
echo "done: $(ls "$OUT" | wc -l | xargs) pictures"

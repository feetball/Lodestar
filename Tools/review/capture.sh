#!/bin/bash
# Captures the screens of the visual review in the iOS Simulator (see Lodestar/Features/Review and
# Lodestar/App/ScreenshotMode.swift). The app must be installed and the Simulator booted.
#
#   capture.sh <udid> <out-dir> <shots-file> [d|n|dn]
#
# Each line of the shots file is   name | modes | arguments | options   (see Tools/review/shots-iphone.txt):
#   modes      d (day), n (night, pure red) or dn
#   arguments  the launch arguments after -LodestarScreenshot: screen=<name>, tab=<tab>, target=<id>, ...
#   options    pages=<n> at most this many screens of a long one (default 3); fixed=<seconds> a screen that keeps
#              moving: wait this long instead of waiting for it to settle
# The fourth argument limits the run to one mode. A shot is written as <name>-<d|n>-<page>.png, the page counted from 1.
# The review driver in the app (ReviewDriver) scrolls long screens one page at a time when told to.
# The environment variable EXTRA_ARGS (optional) adds launch arguments to every shot, such as nightchrome=win for the night
# chrome experiment (.github/workflows/review-chrome.yml). When the app wrote a chrome-log.txt (a Debug build does), it is
# copied next to the picture as <name>-<d|n>.chrome-log.txt and printed.
set -u

UDID="$1"
OUT="$2"
SHOTS="$3"
ONLY="${4:-dn}"
BUNDLE=net.kuecker.Lodestar
COMMON="date=2026-10-19T05:00:00Z lat=36.0544 lon=-112.1401 elevation=2130 site=Grand_Canyon tz=America/Phoenix pointing=350,38 review=1"
COMMON="$COMMON ${EXTRA_ARGS:-}"

mkdir -p "$OUT"
FAILED=0

# state_value <key>: the value of a key in the app's review-state.txt, or nothing.
state_value() {
  [ -f "$DATA/Documents/review-state.txt" ] || return 0
  sed -n "s/^$1=//p" "$DATA/Documents/review-state.txt" | head -n 1
}

# copy_chrome_log <label>: the night chrome log of the app (chrome-log.txt in its Documents), if there is one, kept next to the
# pictures and printed, so that a run can show which variant was really active.
copy_chrome_log() {
  [ -f "$DATA/Documents/chrome-log.txt" ] || return 0
  cp "$DATA/Documents/chrome-log.txt" "$OUT/$1.chrome-log.txt"
  sed "s/^/  chrome-log: /" "$DATA/Documents/chrome-log.txt"
}

# shoot <file>: one screenshot.
shoot() {
  xcrun simctl io "$UDID" screenshot --type=png "$1" >/dev/null 2>&1
}

# settle <file>: waits until the screen no longer changes, then leaves its picture in <file>.
settle() {
  local file="$1" tries=0
  shoot "$file"
  while [ "$tries" -lt 24 ]; do
    sleep 1
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

capture() {
  local name="$1" mode="$2" args="$3" options="$4"
  local suffix=d night=0 pages=3 fixed=""
  if [ "$mode" = n ]; then suffix=n; night=1; fi
  local option
  for option in $options; do
    case "$option" in
      pages=*) pages="${option#pages=}" ;;
      fixed=*) fixed="${option#fixed=}" ;;
    esac
  done

  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" -LodestarScreenshot $COMMON $args night=$night >/dev/null 2>&1
  DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data 2>/dev/null)"
  rm -f "$DATA/Documents/review-cmd.txt"

  # Wait for the driver to report that the screen is ready (60 s at most).
  local waited=0
  while [ "$waited" -lt 120 ]; do
    if [ "$(state_value ready)" = 1 ]; then break; fi
    sleep 0.5
    waited=$((waited + 1))
  done
  if [ "$waited" -ge 120 ]; then echo "  warning: $name ($suffix) was not ready after 60 s"; FAILED=$((FAILED + 1)); fi
  case " $args " in
    *" screen="*) if [ "$(state_value screen)" = none ]; then echo "  warning: $name: the app does not know this screen"; FAILED=$((FAILED + 1)); fi ;;
  esac

  local file="$OUT/$name-$suffix-1.png"
  if [ -n "$fixed" ]; then
    sleep "$fixed"
    shoot "$file"
  else
    settle "$file"
  fi
  local total
  copy_chrome_log "$name-$suffix"

  total="$(state_value pages)"
  [ -n "$total" ] || total=1
  [ "$total" -le "$pages" ] || total="$pages"

  local page=1
  while [ "$page" -lt "$total" ]; do
    echo "page=$page" > "$DATA/Documents/review-cmd.txt"
    waited=0
    while [ "$waited" -lt 20 ]; do
      if [ "$(state_value page)" = "$page" ]; then break; fi
      sleep 0.5
      waited=$((waited + 1))
    done
    file="$OUT/$name-$suffix-$((page + 1)).png"
    if [ -n "$fixed" ]; then
      sleep 1
      shoot "$file"
    else
      settle "$file"
    fi
    page=$((page + 1))
    # A lazily built list can turn out longer once it has been scrolled.
    total="$(state_value pages)"
    [ -n "$total" ] || total=1
    [ "$total" -le "$pages" ] || total="$pages"
  done
  echo "captured $name ($suffix): $page screen(s)"
}

while IFS='|' read -r name modes args options; do
  name="$(echo "$name" | xargs)"
  case "$name" in ''|'#'*) continue ;; esac
  modes="$(echo "$modes" | xargs)"
  args="$(echo "$args" | xargs)"
  options="$(echo "$options" | xargs)"
  for mode in d n; do
    case "$modes" in *"$mode"*) ;; *) continue ;; esac
    case "$ONLY" in *"$mode"*) ;; *) continue ;; esac
    capture "$name" "$mode" "$args" "$options"
  done
done < "$SHOTS"

xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
echo "done: $(ls "$OUT" | wc -l | xargs) pictures, $FAILED problem(s)"

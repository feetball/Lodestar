#!/usr/bin/env bash
# Checks that a built Lodestar.app contains the widget extension and the Apple Watch app with its complications, and
# prints the identifiers and keys they are signed and installed by.  Run after `xcodebuild build` of the Lodestar
# scheme; the argument is the products folder name, e.g. Debug-iphonesimulator or Release-iphoneos.
set -euo pipefail

configuration="${1:?usage: check-embedded-products.sh <Debug-iphonesimulator|Release-iphoneos>}"
app="$(find "$HOME/Library/Developer/Xcode/DerivedData" -type d -name Lodestar.app -path "*/Build/Products/$configuration/*" | head -n 1)"
if [ -z "$app" ]; then
  echo "error: no Lodestar.app found for $configuration" >&2
  exit 1
fi
echo "Checking $app"

widgets="$app/PlugIns/LodestarWidgets.appex"
watch="$app/Watch/LodestarWatch.app"
complications="$watch/PlugIns/LodestarWatchWidgets.appex"

failed=0
for bundle in "$widgets" "$watch" "$complications"; do
  if [ -d "$bundle" ]; then
    echo "found   ${bundle#"$app"/}"
  else
    echo "error: missing ${bundle#"$app"/}" >&2
    failed=1
  fi
done
[ "$failed" -eq 0 ] || exit 1

plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Info.plist" 2>/dev/null || echo "(not set)"; }

echo "app:           $(plist "$app" CFBundleIdentifier) $(plist "$app" CFBundleShortVersionString) ($(plist "$app" CFBundleVersion))"
echo "widgets:       $(plist "$widgets" CFBundleIdentifier) $(plist "$widgets" CFBundleShortVersionString) ($(plist "$widgets" CFBundleVersion)) location=$(plist "$widgets" NSWidgetWantsLocation)"
echo "watch app:     $(plist "$watch" CFBundleIdentifier) $(plist "$watch" CFBundleShortVersionString) ($(plist "$watch" CFBundleVersion)) companion=$(plist "$watch" WKCompanionAppBundleIdentifier)"
echo "complications: $(plist "$complications" CFBundleIdentifier) $(plist "$complications" CFBundleShortVersionString) ($(plist "$complications" CFBundleVersion)) location=$(plist "$complications" NSWidgetWantsLocation)"

[ "$(plist "$widgets" CFBundleIdentifier)" = "net.kuecker.Lodestar.Widgets" ] || { echo "error: wrong widget bundle id" >&2; exit 1; }
[ "$(plist "$watch" CFBundleIdentifier)" = "net.kuecker.Lodestar.watchkitapp" ] || { echo "error: wrong watch app bundle id" >&2; exit 1; }
[ "$(plist "$complications" CFBundleIdentifier)" = "net.kuecker.Lodestar.watchkitapp.Widgets" ] || { echo "error: wrong complications bundle id" >&2; exit 1; }
[ "$(plist "$widgets" NSWidgetWantsLocation)" = "true" ] || { echo "error: widget extension lacks NSWidgetWantsLocation" >&2; exit 1; }
[ "$(plist "$complications" NSWidgetWantsLocation)" = "true" ] || { echo "error: complications lack NSWidgetWantsLocation" >&2; exit 1; }
[ "$(plist "$watch" WKCompanionAppBundleIdentifier)" = "$(plist "$app" CFBundleIdentifier)" ] || { echo "error: the watch app's companion id is not the app's bundle id" >&2; exit 1; }

# App Store Connect rejects an app whose embedded watch app or extensions have another version or build number than
# the app (project.yml keeps all four targets equal), and the bundles need their privacy manifests and location texts.
app_short="$(plist "$app" CFBundleShortVersionString)"
app_build="$(plist "$app" CFBundleVersion)"
if [ "$app_short" = "(not set)" ] || [ "$app_build" = "(not set)" ]; then
  echo "error: the app has no version or build number" >&2
  exit 1
fi
failed=0
for bundle in "$widgets" "$watch" "$complications"; do
  name="${bundle#"$app"/}"
  short="$(plist "$bundle" CFBundleShortVersionString)"
  build="$(plist "$bundle" CFBundleVersion)"
  if [ "$short" != "$app_short" ]; then
    echo "error: $name has version $short, the app has $app_short" >&2
    failed=1
  fi
  if [ "$build" != "$app_build" ]; then
    echo "error: $name has build $build, the app has $app_build" >&2
    failed=1
  fi
  if [ ! -f "$bundle/PrivacyInfo.xcprivacy" ]; then
    echo "error: $name has no privacy manifest" >&2
    failed=1
  fi
  if [ "$(plist "$bundle" NSLocationWhenInUseUsageDescription)" = "(not set)" ]; then
    echo "error: $name has no location usage description" >&2
    failed=1
  fi
done
[ "$failed" -eq 0 ] || exit 1
echo "ok"

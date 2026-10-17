#!/bin/zsh
# Builds Lodestar (Debug) for the Simulator and captures the App Store screenshots in screenshot mode
# (see Lodestar/App/ScreenshotMode.swift). Run it on a Mac with Xcode 27 and the iOS 27 Simulator runtime.
set -e
cd ~
[ -d Lodestar ] || git clone -q https://github.com/feetball/Lodestar.git
cd Lodestar
git pull -q --ff-only
echo "commit $(git rev-parse --short HEAD)"

xcodebuild -project Lodestar.xcodeproj -scheme Lodestar -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/dd \
    CODE_SIGNING_ALLOWED=NO build -quiet
APP=/tmp/dd/Build/Products/Debug-iphonesimulator/Lodestar.app
echo "built $APP"

mkdir -p ~/shots
RUNTIME=com.apple.CoreSimulator.SimRuntime.iOS-27-0
COMMON=(date=2026-07-17T05:30:00Z lat=36.0544 lon=-112.1401 elevation=2130 site=Grand_Canyon tz=America/Phoenix)

shoot() {
    local udid=$1 file=$2
    shift 2
    xcrun simctl terminate "$udid" net.kuecker.Lodestar 2>/dev/null || true
    xcrun simctl launch "$udid" net.kuecker.Lodestar -LodestarScreenshot "${COMMON[@]}" "$@" >/dev/null
    sleep 14
    xcrun simctl io "$udid" screenshot "$file" >/dev/null
    echo "captured $file"
}

for device in iPhone-18-Pro-Max iPhone-18-Pro; do
    udid=$(xcrun simctl create "shots-$device" "com.apple.CoreSimulator.SimDeviceType.$device" "$RUNTIME")
    xcrun simctl boot "$udid"
    xcrun simctl bootstatus "$udid" -b >/dev/null
    xcrun simctl ui "$udid" appearance dark
    xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 \
        --cellularMode active --cellularBars 4 --wifiBars 3
    xcrun simctl install "$udid" "$APP"
    shoot "$udid" ~/shots/$device-1-aim.png tab=aim target=special.galacticCenter pointing=166,12
    shoot "$udid" ~/shots/$device-2-objects.png tab=objects target=special.galacticCenter
    shoot "$udid" ~/shots/$device-3-sky.png tab=sky target=special.galacticCenter
    shoot "$udid" ~/shots/$device-4-tonight.png tab=tonight
    shoot "$udid" ~/shots/$device-5-night.png tab=aim target=dso.M8 pointing=162,17 night=1
    xcrun simctl shutdown "$udid"
done
ls -la ~/shots

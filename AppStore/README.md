# App Store assets

`Screenshots/` holds the App Store screenshots, already sized and flattened (no alpha channel) for
App Store Connect: **iPhone 6.9-inch** (1320 × 2868, iPhone 18 Pro Max) and **iPhone 6.3-inch**
(1206 × 2622, iPhone 18 Pro). Upload them in file-name order.

They are captured in the iOS Simulator by `Tools/capture_screenshots.sh`, which runs a Debug build in
screenshot mode (`Lodestar/App/ScreenshotMode.swift`): the Grand Canyon on a moonless July night, with a
fixed camera pointing so the Aim screen shows real guidance. The app icon is not uploaded separately;
App Store Connect takes it from the build.

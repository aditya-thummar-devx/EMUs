# EMUs

A native macOS menu bar manager for system emulators and simulators (Android AVDs & iOS Simulators).

---

## Features

- **Menu Bar Resident**: Stays in the menu bar with no Dock clutter (`LSUIElement = true`).
- **Separated Tabs**:
  - **Android**: Lists all configured Android AVDs via Android SDK / `adb`.
  - **iOS**: Lists all available iOS Simulators via Xcode `xcrun simctl`.
- **Full-Height Display**: Built using native AppKit `NSStatusItem` + `NSPopover` with a 500pt height so all devices display comfortably without collapsing or cutting off items.
- **Controls for Every Device**:
  - **Play**: Launches the emulator/simulator in the background.
  - **Stop**: Terminates the running device (`adb emu kill` or `xcrun simctl shutdown`).
  - **Cold Boot**: Clean boots the device without cached snapshot state.
- **Auto Status & Refresh**: Real-time status indicators (Running / Stopped) and manual refresh.

---

## Build & Packaging (.dmg)

Run the build script to compile and generate `EMUs.dmg`:

```bash
cd /Users/aditya/Documents/learnings/EMUs
./build_dmg.sh
```

---

## Sharing to Another Mac

Copy `EMUs.dmg` to another Mac:
1. Double-click `EMUs.dmg`.
2. Drag `EMUs` into the `Applications` folder.
3. On first launch, right-click (Control-click) `EMUs.app` -> **Open** (or run `xattr -cr /Applications/EMUs.app`).

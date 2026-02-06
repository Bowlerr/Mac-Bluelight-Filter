# RedshiftMenuBar

Native macOS menu bar app (SwiftUI) for controlling `redshift` from the top bar.

## Features
- Enable/disable `redshift` directly from the menu bar.
- Timing modes:
  - Sunrise/Sunset (uses latitude/longitude)
  - Manual schedule (custom start/end time)
- Color temperature controls (day/night, depending on mode).
- Gamma controls (R/G/B).
- Brightness controls (day/night).
- Live preview swatches (approximate).
- Start-at-login support via LaunchAgent.

## Why Use This Over Night Shift?
- More control: separate day/night temperature, gamma, and brightness.
- Faster workflow: all controls are in the menu bar, with one-click apply/reset.

## Requirements
- macOS 13+
- `redshift` installed (default path: `/opt/homebrew/bin/redshift`)
- Xcode 15+ (recommended)
- `xcodegen` if regenerating the Xcode project (`brew install xcodegen`)

## Quick Start
1. Build with SwiftPM:
   - `swift build`
2. Run from Xcode:
   - `xcodegen generate`
   - Open `RedshiftMenuBar.xcodeproj`
   - Select the `RedshiftMenuBar` scheme
   - Run

## App Configuration
- Bundle identifier: `com.bowlerr.RedshiftMenuBar`
- Location permission usage key is in `Config/Info.plist`.
- If `Start at Login` is enabled, app manages:
  - `~/Library/LaunchAgents/com.user.redshift-menubar.plist`

## Notes
- Uses `redshift -m quartz` on macOS.
- In manual schedule mode, fixed night temperature is applied while active.
- If location is not needed, use manual schedule mode.

## Repository Layout
- `Sources/RedshiftMenuBar/RedshiftMenuBarApp.swift` - main menu bar UI.
- `Sources/RedshiftMenuBar/RedshiftController.swift` - process control, scheduling, settings persistence.
- `Sources/RedshiftMenuBar/LocationService.swift` - current location lookup.
- `Config/Info.plist` - app metadata and permission strings.
- `project.yml` - XcodeGen project spec.

## Troubleshooting
- `redshift not found`: verify `Binary Path` in Advanced settings.
- Location button not working: run as bundled app target with valid `Info.plist`.
- Settings not applying: click `Apply`; if needed, disable/enable once to restart process.

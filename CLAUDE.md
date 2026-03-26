# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
make build    # Build using xcodebuild
make run      # Build, kill any running instance, and launch the app
make kill     # Stop the running application
```

Tests are run via Xcode or:
```bash
xcodebuild test -scheme WorldClockWallpaper -derivedDataPath build/DerivedData
```

The project uses XcodeGen (`project.yml`) to generate the `.xcodeproj`. If you modify `project.yml`, regenerate with `xcodegen generate`.

## Architecture

**WorldClockWallpaper** is a macOS menu bar app (no dock icon, `LSUIElement=true`) that renders a world map with city clocks as the desktop wallpaper.

### Two-Layer Rendering

The core architecture splits rendering into Swift (app lifecycle, data) and Web (visualization):

- **Swift side**: Manages city data and passes it to a `WKWebView` via `window.updateCities()` JavaScript call
- **Web side** (`map.html`): D3.js + TopoJSON renders the world map, city pins, and live times entirely in JavaScript

This means city time display logic lives in two places: `City.swift` has `localTimeString` for the settings panel, while `map.html` computes times client-side using `toLocaleTimeString()`.

### Window Management

`WallpaperWindow` is an `NSWindow` subclass positioned at the desktop window level (below Finder icons). `AppDelegate` creates one wallpaper window per screen and responds to screen change notifications. The window ignores mouse events and uses `.canJoinAllSpaces` + `.stationary` collection behavior.

### Data Flow

```
CityManager (UserDefaults persistence)
    → AppDelegate (observes via Combine)
    → MapViewController.updateCities()
    → WKWebView JavaScript bridge → map.html D3 rendering
    → SettingsView (SwiftUI, reads CityManager directly)
```

### Key Files

| File | Role |
|------|------|
| `AppDelegate.swift` | Creates wallpaper windows per screen, observes CityManager |
| `CityManager.swift` | ObservableObject, UserDefaults persistence, add/remove/move |
| `MapViewController.swift` | WKWebView wrapper, Swift→JS bridge via `updateCities()` |
| `WallpaperWindow.swift` | Desktop-level NSWindow, ignores mouse, spans all spaces |
| `map.html` | D3.js world map, night overlay, city pins, live clock updates |
| `SettingsView.swift` | SwiftUI popover with city list, add-city geocoding, launch-at-login |
| `CityLookupService.swift` | CLGeocoder-based city search, validates placemark name matches |

### Frameworks

WebKit (WKWebView), Combine (reactive updates), ServiceManagement (launch-at-login), CoreLocation (CLGeocoder).

### Memory Management

`MapViewController` uses `WeakScriptMessageHandler` wrapper to break the retain cycle that `WKWebView` creates when registering script message handlers.

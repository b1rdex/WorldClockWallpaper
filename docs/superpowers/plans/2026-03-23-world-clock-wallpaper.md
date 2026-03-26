# World Clock Wallpaper — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS app that renders a live world clock map (day/night zones + city times) directly as the desktop wallpaper, with a menu bar icon for managing the city list.

**Architecture:** A Swift/AppKit app creates a fullscreen `NSWindow` at `kCGDesktopWindowLevel` (below Finder icons, above the wallpaper image). Inside that window sits a `WKWebView` that renders an SVG world map via D3.js with a real-time day/night terminator (using `d3.geoCircle` centered on the antisolar point via SunCalc.js) and animated city pins. The Swift layer owns window lifecycle, menu bar, settings persistence, and communicates the city list to JS via `WKScriptMessageHandler`.

**Tech Stack:** Swift 5.9+, AppKit, WebKit (WKWebView), SwiftUI (settings popover), D3.js v7, TopoJSON v3, SunCalc.js, UserDefaults for persistence, `SMAppService` for login-item (macOS 13+).

---

## File Map

```
WorldClockWallpaper/
├── WorldClockWallpaperApp.swift          # @main, NSApplication setup, no dock icon
├── AppDelegate.swift                     # App lifecycle, wires up window + menu bar
├── WallpaperWindow.swift                 # NSWindow subclass at desktop level
├── MapViewController.swift               # NSViewController wrapping WKWebView
├── MenuBarController.swift               # NSStatusItem + popover host
├── SettingsView.swift                    # SwiftUI city list editor (add/remove/reorder)
├── CityManager.swift                     # CRUD for city list, UserDefaults persistence
├── City.swift                            # Codable struct: name, timezone, lat, lon
├── Resources/
│   ├── map.html                          # Self-contained page: D3 + SunCalc + city pins
│   ├── d3.v7.min.js                      # Bundled D3 (no CDN — works offline)
│   ├── topojson.v3.min.js                # Bundled TopoJSON
│   ├── suncalc.js                        # Bundled SunCalc
│   └── world-110m.json                   # Natural Earth 110m TopoJSON
└── WorldClockWallpaperTests/
    ├── CityTests.swift                   # Codable round-trip, validation
    └── CityManagerTests.swift            # Add/remove/persist/reload
```

---

### Task 1: Xcode project scaffold

**Files:**
- Create: Xcode project at `WorldClockWallpaper.xcodeproj`
- Create: `WorldClockWallpaper/WorldClockWallpaperApp.swift`
- Create: `WorldClockWallpaper/AppDelegate.swift`
- Create: `WorldClockWallpaperTests/` test target

- [ ] **Step 1: Create macOS App project in Xcode**

  File → New → Project → macOS → App.
  - Product name: `WorldClockWallpaper`
  - Interface: **SwiftUI** (we'll switch to AppDelegate lifecycle manually)
  - Language: Swift
  - Uncheck "Include Tests" (we add the test target manually next)

- [ ] **Step 2: Set deployment target to macOS 13.0**

  Project → WorldClockWallpaper target → General → Minimum Deployments → **macOS 13.0**.
  Do this before writing any code — it affects what APIs are available throughout.

- [ ] **Step 3: Switch to AppDelegate lifecycle**

  Delete the generated `ContentView.swift`. Replace `WorldClockWallpaperApp.swift`:

  ```swift
  import AppKit

  @main
  struct WorldClockWallpaperApp {
      static func main() {
          let app = NSApplication.shared
          let delegate = AppDelegate()
          app.delegate = delegate
          app.setActivationPolicy(.accessory)  // No dock icon
          app.run()
      }
  }
  ```

- [ ] **Step 4: Stub AppDelegate**

  Create `AppDelegate.swift`:

  ```swift
  import AppKit

  class AppDelegate: NSObject, NSApplicationDelegate {
      func applicationDidFinishLaunching(_ notification: Notification) {
          // wired up in later tasks
      }
  }
  ```

- [ ] **Step 5: Link required frameworks**

  Project → WorldClockWallpaper target → General → "Frameworks, Libraries, and Embedded Content" → click **+**:
  - Add **WebKit.framework**
  - Add **Combine.framework**
  - Add **ServiceManagement.framework**

  These are system frameworks — no embedding needed (select "Do Not Embed").

- [ ] **Step 6: Add unit test target**

  File → New → Target → Unit Testing Bundle. Name it `WorldClockWallpaperTests`. Set "Host Application" to `WorldClockWallpaper`.

- [ ] **Step 7: Build and confirm it compiles cleanly (no window, no dock icon)**

  Product → Run. Confirm: no dock icon, no crash, no build warnings about missing frameworks.

- [ ] **Step 8: Commit**

  ```bash
  cd /Users/anatoly/Projects/WorldClockWallpaper
  git init
  git add .
  git commit -m "chore: initial Xcode project scaffold, deployment target macOS 13"
  ```

---

### Task 2: City model + CityManager

**Files:**
- Create: `WorldClockWallpaper/City.swift`
- Create: `WorldClockWallpaper/CityManager.swift`
- Create: `WorldClockWallpaperTests/CityTests.swift`
- Create: `WorldClockWallpaperTests/CityManagerTests.swift`

- [ ] **Step 1: Write failing tests for City**

  `WorldClockWallpaperTests/CityTests.swift`:

  ```swift
  import XCTest
  @testable import WorldClockWallpaper

  final class CityTests: XCTestCase {

      func test_codableRoundTrip() throws {
          let city = City(name: "Moscow", timezone: "Europe/Moscow", lat: 55.75, lon: 37.62)
          let data = try JSONEncoder().encode(city)
          let decoded = try JSONDecoder().decode(City.self, from: data)
          XCTAssertEqual(decoded.name, "Moscow")
          XCTAssertEqual(decoded.timezone, "Europe/Moscow")
          XCTAssertEqual(decoded.lat, 55.75)
          XCTAssertEqual(decoded.lon, 37.62)
      }

      func test_localTime_returnsNonEmptyString() {
          let city = City(name: "Tokyo", timezone: "Asia/Tokyo", lat: 35.68, lon: 139.69)
          XCTAssertFalse(city.localTimeString.isEmpty)
      }

      func test_unknownTimezone_doesNotCrash() {
          let city = City(name: "Nowhere", timezone: "Invalid/Zone", lat: 0, lon: 0)
          XCTAssertFalse(city.localTimeString.isEmpty)
      }
  }
  ```

- [ ] **Step 2: Run tests — confirm FAIL**

  Product → Test (⌘U). Expected: compile error "Cannot find type City".

- [ ] **Step 3: Implement City**

  `WorldClockWallpaper/City.swift`:

  ```swift
  import Foundation

  struct City: Codable, Identifiable, Equatable {
      let id: UUID
      var name: String
      var timezone: String   // IANA timezone id, e.g. "Europe/Moscow"
      var lat: Double
      var lon: Double

      init(id: UUID = UUID(), name: String, timezone: String, lat: Double, lon: Double) {
          self.id = id
          self.name = name
          self.timezone = timezone
          self.lat = lat
          self.lon = lon
      }

      /// Current time in this city's timezone, formatted as "HH:mm"
      var localTimeString: String {
          let formatter = DateFormatter()
          formatter.dateFormat = "HH:mm"
          formatter.timeZone = TimeZone(identifier: timezone) ?? .current
          return formatter.string(from: Date())
      }
  }
  ```

- [ ] **Step 4: Run tests — confirm City tests PASS**

- [ ] **Step 5: Write failing tests for CityManager**

  `WorldClockWallpaperTests/CityManagerTests.swift`:

  ```swift
  import XCTest
  @testable import WorldClockWallpaper

  final class CityManagerTests: XCTestCase {
      var sut: CityManager!
      let testKey = "test_cities_key"

      override func setUp() {
          super.setUp()
          UserDefaults.standard.removeObject(forKey: testKey)
          sut = CityManager(storageKey: testKey)
      }

      func test_defaultCities_areNotEmpty() {
          XCTAssertFalse(sut.cities.isEmpty)
      }

      func test_addCity_appendsToList() {
          let initial = sut.cities.count
          sut.add(City(name: "Paris", timezone: "Europe/Paris", lat: 48.85, lon: 2.35))
          XCTAssertEqual(sut.cities.count, initial + 1)
      }

      func test_removeCity_removesFromList() {
          let city = City(name: "Paris", timezone: "Europe/Paris", lat: 48.85, lon: 2.35)
          sut.add(city)
          sut.remove(id: city.id)
          XCTAssertFalse(sut.cities.contains(where: { $0.id == city.id }))
      }

      func test_persistAndReload() {
          let city = City(name: "Sydney", timezone: "Australia/Sydney", lat: -33.87, lon: 151.21)
          sut.add(city)
          let reloaded = CityManager(storageKey: testKey)
          XCTAssertTrue(reloaded.cities.contains(where: { $0.id == city.id }))
      }
  }
  ```

- [ ] **Step 6: Run tests — confirm FAIL** (CityManager not yet defined)

- [ ] **Step 7: Implement CityManager**

  `WorldClockWallpaper/CityManager.swift`:

  ```swift
  import Foundation
  import Combine

  final class CityManager: ObservableObject {
      @Published private(set) var cities: [City]
      private let storageKey: String

      init(storageKey: String = "saved_cities") {
          self.storageKey = storageKey
          if let data = UserDefaults.standard.data(forKey: storageKey),
             let saved = try? JSONDecoder().decode([City].self, from: data) {
              cities = saved
          } else {
              cities = CityManager.defaults
          }
      }

      func add(_ city: City) {
          cities.append(city)
          persist()
      }

      func remove(id: UUID) {
          cities.removeAll { $0.id == id }
          persist()
      }

      func move(fromOffsets: IndexSet, toOffset: Int) {
          cities.move(fromOffsets: fromOffsets, toOffset: toOffset)
          persist()
      }

      private func persist() {
          guard let data = try? JSONEncoder().encode(cities) else { return }
          UserDefaults.standard.set(data, forKey: storageKey)
      }

      private static let defaults: [City] = [
          City(name: "Moscow",    timezone: "Europe/Moscow",       lat: 55.75,  lon:  37.62),
          City(name: "New York",  timezone: "America/New_York",    lat: 40.71,  lon: -74.01),
          City(name: "London",    timezone: "Europe/London",       lat: 51.51,  lon:  -0.13),
          City(name: "Tokyo",     timezone: "Asia/Tokyo",          lat: 35.68,  lon: 139.69),
          City(name: "Dubai",     timezone: "Asia/Dubai",          lat: 25.20,  lon:  55.27),
      ]
  }
  ```

- [ ] **Step 8: Run ALL tests — confirm all PASS** (⌘U, both City and CityManager suites)

- [ ] **Step 9: Commit**

  ```bash
  git add WorldClockWallpaper/City.swift WorldClockWallpaper/CityManager.swift \
          WorldClockWallpaperTests/CityTests.swift WorldClockWallpaperTests/CityManagerTests.swift
  git commit -m "feat: City model and CityManager with persistence"
  ```

---

### Task 3: Bundle JS/web resources + complete map.html

**Files:**
- Download: `WorldClockWallpaper/Resources/d3.v7.min.js`
- Download: `WorldClockWallpaper/Resources/topojson.v3.min.js`
- Download: `WorldClockWallpaper/Resources/suncalc.js`
- Download: `WorldClockWallpaper/Resources/world-110m.json`
- Create: `WorldClockWallpaper/Resources/map.html` (stub first, then complete)

> All JS files must be bundled locally — WKWebView under sandbox cannot load CDN URLs, and we want offline operation.

- [ ] **Step 1: Download JS libraries**

  ```bash
  mkdir -p /Users/anatoly/Projects/WorldClockWallpaper/WorldClockWallpaper/Resources
  cd /Users/anatoly/Projects/WorldClockWallpaper/WorldClockWallpaper/Resources

  curl -L "https://cdn.jsdelivr.net/npm/d3@7/dist/d3.min.js" -o d3.v7.min.js
  curl -L "https://cdn.jsdelivr.net/npm/topojson@3/dist/topojson.min.js" -o topojson.v3.min.js
  curl -L "https://cdn.jsdelivr.net/npm/suncalc@1/suncalc.js" -o suncalc.js
  curl -L "https://cdn.jsdelivr.net/npm/world-atlas@2/countries-110m.json" -o world-110m.json
  ```

  Verify all four files exist and are non-empty:
  ```bash
  ls -lh /Users/anatoly/Projects/WorldClockWallpaper/WorldClockWallpaper/Resources/
  ```

- [ ] **Step 2: Create stub map.html — verifies libraries load**

  `WorldClockWallpaper/Resources/map.html`:

  ```html
  <!DOCTYPE html>
  <html>
  <head><meta charset="utf-8"></head>
  <body style="background:#0d0d0d">
  <svg id="map" width="100%" height="100%"></svg>
  <script src="d3.v7.min.js"></script>
  <script src="topojson.v3.min.js"></script>
  <script src="suncalc.js"></script>
  <script>
    // Smoke test — will print to console if libraries loaded
    console.log("D3 version:", d3.version);
    console.log("SunCalc loaded:", typeof SunCalc !== "undefined");
    console.log("TopoJSON loaded:", typeof topojson !== "undefined");
  </script>
  </body>
  </html>
  ```

- [ ] **Step 3: Add all 5 files to Xcode target**

  In Xcode: right-click `WorldClockWallpaper` group → "Add Files to WorldClockWallpaper".
  Select the `Resources` folder. Ensure:
  - "Add to targets: WorldClockWallpaper" ✓
  - "Copy items if needed" ✓
  - "Create folder references" (not "Create groups") — so the `Resources/` directory structure is preserved in the bundle

- [ ] **Step 4: Verify the stub loads in a local HTTP server**

  WKWebView uses `loadFileURL(allowingReadAccessTo:)` at runtime. To test the HTML in a browser during development, use a local server (direct `file://` in Safari blocks cross-origin loads for sibling files):

  ```bash
  cd /Users/anatoly/Projects/WorldClockWallpaper/WorldClockWallpaper/Resources
  python3 -m http.server 8765 &
  open http://localhost:8765/map.html
  ```

  Open Safari DevTools (Develop → localhost → map.html). Expected console output:
  ```
  D3 version: 7.x.x
  SunCalc loaded: true
  TopoJSON loaded: true
  ```

  Stop the server when done: `kill %1`

- [ ] **Step 5: Implement complete map.html**

  Replace `map.html` with the full implementation. The night-side polygon uses `d3.geoCircle()` centered on the **antisolar point** — this is the correct technique for D3 projections (avoids polygon winding-order issues):

  ```html
  <!DOCTYPE html>
  <html>
  <head>
  <meta charset="utf-8">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body { width: 100%; height: 100%; background: #0d0d0d; overflow: hidden; }
    svg { display: block; }

    .city-label {
      font-family: -apple-system, "SF Pro Display", sans-serif;
      fill: #e8e8e8;
      font-size: 12px;
      pointer-events: none;
    }
    .city-time {
      font-family: -apple-system, "SF Pro Display", sans-serif;
      fill: #f0c040;
      font-size: 13px;
      font-weight: 600;
      pointer-events: none;
    }
    .city-dot { fill: #f0c040; }
  </style>
  </head>
  <body>
  <svg id="map"></svg>
  <script src="d3.v7.min.js"></script>
  <script src="topojson.v3.min.js"></script>
  <script src="suncalc.js"></script>
  <script>
  // ── State ────────────────────────────────────────────────────────────────────
  let cities = [];
  let worldData = null;

  let width = window.innerWidth;
  let height = window.innerHeight;

  const svg = d3.select("#map")
    .attr("width", width)
    .attr("height", height);

  const projection = d3.geoNaturalEarth1()
    .scale(width / 6.2)
    .translate([width / 2, height / 2]);

  const path = d3.geoPath().projection(projection);

  // Layers (back → front)
  const nightLayer  = svg.append("g").attr("id", "night");
  const landLayer   = svg.append("g").attr("id", "land");
  const borderLayer = svg.append("g").attr("id", "borders");
  const cityLayer   = svg.append("g").attr("id", "cities");

  // ── Night polygon ─────────────────────────────────────────────────────────────
  // Use d3.geoCircle centered on the antisolar point (the point opposite the sun).
  // A circle of radius 90° around the antisolar point exactly equals the night hemisphere.
  function getAntisolarPoint(date) {
    // Compute antisolar point using UTC time and simplified declination formula.
    const utHours = date.getUTCHours() + date.getUTCMinutes() / 60 + date.getUTCSeconds() / 3600;
    const solarLon = (180 - (utHours - 12) * 15);

    // Solar declination
    const dayOfYear = Math.floor((date - new Date(date.getFullYear(), 0, 0)) / 86400000);
    const declination = -23.45 * Math.cos((2 * Math.PI / 365) * (dayOfYear + 10));

    // Antisolar point is directly opposite
    const antiLon = ((solarLon + 180 + 540) % 360) - 180;
    const antiLat = -declination;
    return [antiLon, antiLat];
  }

  function drawNight(date) {
    nightLayer.selectAll("*").remove();
    const [lon, lat] = getAntisolarPoint(date);
    const nightCircle = d3.geoCircle().center([lon, lat]).radius(90)();
    nightLayer.append("path")
      .datum(nightCircle)
      .attr("d", path)
      .attr("fill", "rgba(0, 0, 25, 0.68)");
  }

  // ── Land + borders ────────────────────────────────────────────────────────────
  function drawLand() {
    landLayer.selectAll("*").remove();
    borderLayer.selectAll("*").remove();
    const countries = topojson.feature(worldData, worldData.objects.countries);
    const borders   = topojson.mesh(worldData, worldData.objects.countries,
                                    (a, b) => a !== b);
    landLayer.selectAll("path.country")
      .data(countries.features)
      .enter().append("path")
        .attr("class", "country")
        .attr("d", path)
        .attr("fill", "#2a2a2a")
        .attr("stroke", "none");

    borderLayer.append("path")
      .datum(borders)
      .attr("d", path)
      .attr("fill", "none")
      .attr("stroke", "#444")
      .attr("stroke-width", 0.4);
  }

  // ── City pins ─────────────────────────────────────────────────────────────────
  function drawCities() {
    cityLayer.selectAll("*").remove();
    cities.forEach(city => {
      const projected = projection([city.lon, city.lat]);
      if (!projected) return;
      const [x, y] = projected;

      const g = cityLayer.append("g").attr("transform", `translate(${x},${y})`);
      g.append("circle").attr("class", "city-dot").attr("r", 4);
      g.append("text").attr("class", "city-label")
        .attr("dx", 8).attr("dy", -5)
        .text(city.name);
      g.append("text").attr("class", "city-time")
        .attr("dx", 8).attr("dy", 10)
        .attr("data-tz", city.timezone)
        .text(localTime(city.timezone));
    });
  }

  function updateTimes() {
    cityLayer.selectAll("text[data-tz]").each(function() {
      d3.select(this).text(localTime(this.dataset.tz));
    });
  }

  function localTime(timezone) {
    try {
      return new Date().toLocaleTimeString("en-GB", {
        timeZone: timezone, hour: "2-digit", minute: "2-digit"
      });
    } catch { return "--:--"; }
  }

  // ── Full redraw ───────────────────────────────────────────────────────────────
  function draw() {
    if (!worldData) return;
    drawNight(new Date());
    drawLand();
    drawCities();
  }

  // ── Load world data ───────────────────────────────────────────────────────────
  d3.json("world-110m.json").then(data => {
    worldData = data;
    draw();
    setInterval(() => drawNight(new Date()), 60000); // night zone every 1 min
    setInterval(updateTimes, 1000);                  // clock digits every 1 sec
  });

  // ── Resize ────────────────────────────────────────────────────────────────────
  window.addEventListener("resize", () => {
    width = window.innerWidth; height = window.innerHeight;
    svg.attr("width", width).attr("height", height);
    projection.scale(width / 6.2).translate([width / 2, height / 2]);
    draw();
  });

  // ── Swift ↔ JS bridge ─────────────────────────────────────────────────────────
  // Swift calls window.updateCities(jsonArray) to push city list
  window.updateCities = function(newCities) {
    cities = newCities;
    drawCities();
  };

  // Notify Swift that the page is ready — Swift will respond with updateCities()
  window.webkit?.messageHandlers?.cityBridge?.postMessage("requestCities");
  </script>
  </body>
  </html>
  ```

- [ ] **Step 6: Verify complete map.html in local server**

  ```bash
  cd /Users/anatoly/Projects/WorldClockWallpaper/WorldClockWallpaper/Resources
  python3 -m http.server 8765 &
  open http://localhost:8765/map.html
  ```

  Expected: dark world map, night hemisphere visibly shadowed, no JS errors in console. Cities array is empty at this stage (Swift bridge not wired yet) — that's fine.

  ```bash
  kill %1  # stop server
  ```

- [ ] **Step 7: Commit**

  ```bash
  git add WorldClockWallpaper/Resources/
  git commit -m "feat: bundle D3/TopoJSON/SunCalc/world map and complete map.html"
  ```

---

### Task 4: Desktop-level window + WKWebView

**Files:**
- Create: `WorldClockWallpaper/WallpaperWindow.swift`
- Create: `WorldClockWallpaper/MapViewController.swift`
- Modify: `WorldClockWallpaper/AppDelegate.swift`

- [ ] **Step 1: Create WallpaperWindow**

  `WorldClockWallpaper/WallpaperWindow.swift`:

  ```swift
  import AppKit

  final class WallpaperWindow: NSWindow {

      init(screen: NSScreen) {
          super.init(
              contentRect: screen.frame,
              styleMask: [.borderless],
              backing: .buffered,
              defer: false,
              screen: screen
          )
          // kCGDesktopWindowLevel (level 0) sits below Finder desktop icons.
          // Do NOT add +1: that would push the window into the icon layer.
          level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
          collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .transient]
          isOpaque = true
          hasShadow = false
          backgroundColor = .black
          ignoresMouseEvents = true
      }

      override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
          return screen?.frame ?? frameRect
      }
  }
  ```

  > **Window level note:** `CGWindowLevelForKey(.desktopWindow)` returns 0 (kCGDesktopWindowLevel). This is the correct level for a wallpaper window — it sits below the desktop icon layer (level 9) and above the backstop (level -2147483628). `.transient` in `collectionBehavior` additionally hides this window from Mission Control thumbnails.

- [ ] **Step 2: Create MapViewController**

  `WorldClockWallpaper/MapViewController.swift`:

  ```swift
  import AppKit
  import WebKit

  final class MapViewController: NSViewController, WKScriptMessageHandler {

      private var webView: WKWebView!

      var cities: [City] = [] {
          didSet { pushCitiesToJS() }
      }

      override func loadView() {
          let config = WKWebViewConfiguration()
          config.userContentController.add(self, name: "cityBridge")
          webView = WKWebView(frame: .zero, configuration: config)
          // underPageBackgroundColor avoids any flash of white before the HTML background renders.
          // Deployment target is 13.0, so no availability guard needed.
          webView.underPageBackgroundColor = .black
          view = webView
      }

      override func viewDidLoad() {
          super.viewDidLoad()
          loadMap()
      }

      private func loadMap() {
          guard let url = Bundle.main.url(forResource: "map", withExtension: "html",
                                          subdirectory: "Resources") else {
              assertionFailure("map.html not found in bundle — check Copy Bundle Resources phase")
              return
          }
          // allowingReadAccessTo grants WKWebView read access to the whole Resources dir,
          // so it can load the sibling d3, topojson, suncalc, and world-110m.json files.
          webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
      }

      private func pushCitiesToJS() {
          guard let data = try? JSONEncoder().encode(cities),
                let json = String(data: data, encoding: .utf8) else { return }
          webView.evaluateJavaScript("window.updateCities(\(json))", completionHandler: nil)
      }

      // MARK: - WKScriptMessageHandler
      func userContentController(_ userContentController: WKUserContentController,
                                  didReceive message: WKScriptMessage) {
          if message.name == "cityBridge" {
              pushCitiesToJS()
          }
      }
  }
  ```

- [ ] **Step 3: Wire up AppDelegate**

  Replace `AppDelegate.swift`:

  ```swift
  import AppKit
  import Combine

  class AppDelegate: NSObject, NSApplicationDelegate {
      private var wallpaperWindows: [WallpaperWindow] = []
      private var mapControllers: [MapViewController] = []
      private var cancellables = Set<AnyCancellable>()
      let cityManager = CityManager()

      func applicationDidFinishLaunching(_ notification: Notification) {
          setupWallpaperWindows()

          NotificationCenter.default.addObserver(
              self,
              selector: #selector(screensDidChange),
              name: NSApplication.didChangeScreenParametersNotification,
              object: nil
          )
      }

      private func setupWallpaperWindows() {
          for screen in NSScreen.screens {
              let vc = MapViewController()
              vc.cities = cityManager.cities
              let window = WallpaperWindow(screen: screen)
              window.contentViewController = vc
              window.orderFront(nil)  // orderFront, not makeKeyAndOrderFront — wallpaper must not steal focus
              wallpaperWindows.append(window)
              mapControllers.append(vc)
          }
      }

      @objc private func screensDidChange() {
          wallpaperWindows.forEach { $0.close() }
          wallpaperWindows.removeAll()
          mapControllers.removeAll()
          setupWallpaperWindows()
      }

      func refreshCities() {
          mapControllers.forEach { $0.cities = cityManager.cities }
      }
  }
  ```

- [ ] **Step 4: Build and run — confirm map renders on desktop**

  Product → Run. Hide all application windows (⌘H on each, or use Mission Control).
  You should see the world clock map behind the Finder desktop icons.

  **Troubleshooting:** If the map is blank:
  1. Check Xcode: Build Phases → Copy Bundle Resources — verify `map.html`, all `.js`, `.json` files are listed.
  2. Check Console.app for WKWebView errors (filter on "WorldClockWallpaper").
  3. If `map.html` not found: the folder reference may have been added incorrectly. Re-add with "Create folder references" not "Create groups".

- [ ] **Step 5: Commit**

  ```bash
  git add WorldClockWallpaper/WallpaperWindow.swift \
          WorldClockWallpaper/MapViewController.swift \
          WorldClockWallpaper/AppDelegate.swift
  git commit -m "feat: desktop-level WallpaperWindow with WKWebView map"
  ```

---

### Task 5: Menu bar + settings UI

**Files:**
- Create: `WorldClockWallpaper/MenuBarController.swift`
- Create: `WorldClockWallpaper/SettingsView.swift`
- Modify: `WorldClockWallpaper/AppDelegate.swift`

- [ ] **Step 1: Create SettingsView — city list display only**

  `WorldClockWallpaper/SettingsView.swift`:

  ```swift
  import SwiftUI
  import ServiceManagement

  struct SettingsView: View {
      @ObservedObject var cityManager: CityManager
      @State private var showingAdd = false

      var body: some View {
          VStack(alignment: .leading, spacing: 0) {
              Text("World Clock Wallpaper")
                  .font(.headline)
                  .padding(.horizontal, 12)
                  .padding(.top, 12)
                  .padding(.bottom, 6)

              cityListView

              Divider()
              footerView
          }
          .frame(width: 300)
      }

      private var cityListView: some View {
          List {
              ForEach(cityManager.cities) { city in
                  HStack {
                      VStack(alignment: .leading, spacing: 1) {
                          Text(city.name).font(.body)
                          Text(city.timezone).font(.caption).foregroundColor(.secondary)
                      }
                      Spacer()
                      Text(city.localTimeString).foregroundColor(.secondary)
                      Button(action: { cityManager.remove(id: city.id) }) {
                          Image(systemName: "minus.circle.fill").foregroundColor(.red)
                      }
                      .buttonStyle(.plain)
                  }
              }
              .onMove { cityManager.move(fromOffsets: $0, toOffset: $1) }
          }
          .frame(height: min(CGFloat(cityManager.cities.count) * 44 + 8, 280))
      }

      private var footerView: some View {
          VStack(alignment: .leading, spacing: 0) {
              if showingAdd {
                  AddCityForm(cityManager: cityManager, isShowing: $showingAdd)
              } else {
                  Button(action: { showingAdd = true }) {
                      Label("Add City", systemImage: "plus")
                  }
                  .padding(12)
              }

              Divider()

              HStack {
                  Toggle("Launch at login", isOn: Binding(
                      get: { SMAppService.mainApp.status == .enabled },
                      set: { on in
                          do {
                              if on { try SMAppService.mainApp.register() }
                              else  { try SMAppService.mainApp.unregister() }
                          } catch {
                              print("Login item error: \(error)")
                          }
                      }
                  ))
                  Spacer()
                  Button("Quit") { NSApplication.shared.terminate(nil) }
              }
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
          }
      }
  }
  ```

- [ ] **Step 2: Add AddCityForm subview**

  Append to `SettingsView.swift` (outside the `SettingsView` struct):

  ```swift
  struct AddCityForm: View {
      @ObservedObject var cityManager: CityManager
      @Binding var isShowing: Bool
      @State private var name = ""
      @State private var timezone = ""
      @State private var lat = ""
      @State private var lon = ""

      var body: some View {
          VStack(spacing: 6) {
              TextField("City name (e.g. Paris)", text: $name)
              TextField("Timezone (e.g. Europe/Paris)", text: $timezone)
              HStack {
                  TextField("Latitude", text: $lat)
                  TextField("Longitude", text: $lon)
              }
              HStack {
                  Button("Cancel") { isShowing = false }
                  Spacer()
                  Button("Add") {
                      cityManager.add(City(
                          name: name,
                          timezone: timezone,
                          lat: Double(lat) ?? 0,
                          lon: Double(lon) ?? 0
                      ))
                      isShowing = false
                  }
                  .disabled(name.isEmpty || timezone.isEmpty)
                  .keyboardShortcut(.return)
              }
          }
          .padding(12)
          .textFieldStyle(.roundedBorder)
      }
  }
  ```

- [ ] **Step 3: Create MenuBarController**

  `WorldClockWallpaper/MenuBarController.swift`:

  ```swift
  import AppKit
  import SwiftUI

  final class MenuBarController: NSObject {
      private var statusItem: NSStatusItem!
      private var popover: NSPopover!

      init(cityManager: CityManager) {
          super.init()
          setupStatusItem()
          setupPopover(cityManager: cityManager)
      }

      private func setupStatusItem() {
          statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
          if let button = statusItem.button {
              button.image = NSImage(systemSymbolName: "clock.fill",
                                     accessibilityDescription: "World Clock Wallpaper")
              button.action = #selector(togglePopover)
              button.target = self
          }
      }

      private func setupPopover(cityManager: CityManager) {
          let vc = NSHostingController(rootView: SettingsView(cityManager: cityManager))
          popover = NSPopover()
          popover.contentViewController = vc
          popover.behavior = .transient
      }

      @objc private func togglePopover() {
          guard let button = statusItem.button else { return }
          if popover.isShown {
              popover.performClose(nil)
          } else {
              popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
              popover.contentViewController?.view.window?.makeKey()
          }
      }
  }
  ```

- [ ] **Step 4: Wire MenuBarController + Combine observation into AppDelegate**

  In `AppDelegate.swift`, add:

  ```swift
  private var menuBar: MenuBarController!
  ```

  Inside `applicationDidFinishLaunching`, after `setupWallpaperWindows()`:

  ```swift
  menuBar = MenuBarController(cityManager: cityManager)

  cityManager.$cities
      .dropFirst()
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.refreshCities() }
      .store(in: &cancellables)
  ```

- [ ] **Step 5: Build and run — confirm menu bar icon appears**

  Click the clock icon in the menu bar. Confirm: popover opens, default cities listed, times update every second, adding/removing cities updates the map immediately.

- [ ] **Step 6: Commit**

  ```bash
  git add WorldClockWallpaper/MenuBarController.swift \
          WorldClockWallpaper/SettingsView.swift \
          WorldClockWallpaper/AppDelegate.swift
  git commit -m "feat: menu bar icon with city list settings popover"
  ```

---

### Task 6: App Sandbox + distribution prep

**Files:**
- Modify: `WorldClockWallpaper.entitlements`
- Modify: Xcode project settings (bundle ID)

- [ ] **Step 1: Enable App Sandbox**

  In `WorldClockWallpaper.entitlements`:
  ```xml
  <key>com.apple.security.app-sandbox</key><true/>
  ```

  No network entitlement is needed — all resources are bundled locally.

- [ ] **Step 2: Set bundle identifier**

  Project → General: set Bundle Identifier to `com.yourname.WorldClockWallpaper` (replace `yourname` with your identifier).

- [ ] **Step 3: Verify bundle resources are reachable under sandbox**

  Build and run. Open Console.app, filter "WorldClockWallpaper". Confirm no "file not found" or sandbox violation errors appear when the WKWebView loads `map.html` and its sibling assets.

  If you see `[blocked] ... world-110m.json` — this means `loadFileURL(allowingReadAccessTo:)` is not pointing at the correct directory. Check that `url.deletingLastPathComponent()` resolves to the `Resources/` folder inside the bundle.

- [ ] **Step 4: Run all tests — confirm still passing**

  ```bash
  xcodebuild test -scheme WorldClockWallpaper -destination 'platform=macOS'
  ```

  Expected: all City and CityManager tests pass.

- [ ] **Step 5: Archive for distribution**

  Product → Archive → Distribute App → Copy App.

  > This is a manual Xcode UI step. For automated builds use:
  > ```bash
  > xcodebuild archive -scheme WorldClockWallpaper \
  >   -archivePath build/WorldClockWallpaper.xcarchive
  > ```

- [ ] **Step 6: Final commit**

  ```bash
  git add .
  git commit -m "chore: enable App Sandbox, set bundle ID, distribution prep"
  ```

---

## Known Issues / Gotchas

1. **Window level on future macOS:** `kCGDesktopWindowLevel` (0) is documented in `CGWindowLevel.h` and has been stable across macOS versions. If a future macOS update causes the map to appear above icons, try `CGWindowLevelForKey(.desktopWindow) - 1`.

2. **Copy Bundle Resources — folder reference vs group:** Xcode has two modes when adding folders. "Create folder references" preserves the `Resources/` directory in the bundle (required for `loadFileURL(allowingReadAccessTo:)`). "Create groups" flattens files into the bundle root. If `map.html` can't find `d3.v7.min.js`, this is the cause — re-add as a folder reference.

3. **Night polygon accuracy:** The `getAntisolarPoint` function uses simplified solar declination (~0.5° accuracy). This is visually indistinguishable from astronomical precision for a wallpaper.

4. **Multiple monitors:** `screensDidChange` tears down and recreates all windows when the screen configuration changes. There's a brief flash during this transition. For a smoother experience, a future improvement would be to diff the old and new screen list and only create/destroy windows for added/removed screens.

5. **SMAppService + code signing:** `SMAppService.mainApp.register()` requires the app to be code-signed (at minimum ad-hoc signed) to persist across reboots. During development with Product → Run, this works. For a distributed app, sign with a Developer ID.

# Visual Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 5 UX/visual issues: flat rectangular map filling the full screen, gray+white terminator, correct menu popover position, and city-name-only geocoded add flow.

**Architecture:** Three independent changes — (1) `map.html` visual overhaul (projection, fill, terminator), (2) `MenuBarController.swift` popover edge fix, (3) new `CityLookupService.swift` + `SettingsView.swift` geocoding UI. Also cleans up the temporary sandbox-debugging code added during the sandbox investigation. App Sandbox stays OFF (`app-sandbox = false`); `loadFileURL` is the correct loader.

**Tech Stack:** D3.js v7 (geoEquirectangular, geoCircle, geoPath), AppKit/NSPopover, SwiftUI, CoreLocation (CLGeocoder async/await), Swift 6, macOS 13+.

---

## File Map

```
WorldClockWallpaper/
├── MapViewController.swift       MODIFY — revert loadMap() to loadFileURL, remove debug logs
├── MenuBarController.swift       MODIFY — fix popover preferredEdge .minY → .maxY
├── SettingsView.swift            MODIFY — replace AddCityForm with geocoding form
├── CityLookupService.swift       CREATE — CLGeocoder wrapper, returns City from name string
├── Resources/
│   └── map.html                  MODIFY — projection, scale, terminator style
└── project.yml                   MODIFY — add CoreLocation.framework dependency
```

---

### Task 1: Cleanup sandbox experiments + map visual overhaul

Cleans up the temporary `loadHTMLString`/debug-logging code added during the sandbox investigation,
reverts `loadMap()` to the simple `loadFileURL` approach (correct without App Sandbox),
and applies all visual map changes: flat equirectangular projection, "cover" fill, gray+white terminator.

**Files:**
- Modify: `WorldClockWallpaper/MapViewController.swift`
- Modify: `WorldClockWallpaper/Resources/map.html`

#### Step 1 — Revert `MapViewController.swift` to clean `loadFileURL` state

Replace the entire `MapViewController.swift` with this clean version (removes the inlining code,
debug NSLogs, and `jsError` message handler added during sandbox investigation):

```swift
import AppKit
import WebKit

/// Breaks the retain cycle between WKUserContentController and its script message handler.
///
/// WKUserContentController holds a **strong** reference to every registered
/// WKScriptMessageHandler. If MapViewController were registered directly, the
/// controller (owned by the WKWebViewConfiguration / WKWebView) would keep
/// MapViewController alive indefinitely, preventing it from being deallocated.
/// This lightweight wrapper holds only a weak reference to the real delegate,
/// so the cycle is broken and both objects can be released normally.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: (NSObject & WKScriptMessageHandler)?

    init(_ delegate: NSObject & WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ ucc: WKUserContentController,
                                didReceive message: WKScriptMessage) {
        delegate?.userContentController(ucc, didReceive: message)
    }
}

final class MapViewController: NSViewController, WKScriptMessageHandler, WKNavigationDelegate {

    private var webView: WKWebView!

    var cities: [City] = [] {
        didSet { pushCitiesToJS() }
    }

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.userContentController.add(WeakScriptMessageHandler(self), name: "cityBridge")
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.underPageBackgroundColor = .black
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadMap()
    }

    private func loadMap() {
        guard let url = Bundle.main.url(forResource: "map", withExtension: "html") else {
            NSLog("WCW: map.html not found in bundle")
            return
        }
        let resourceDir = Bundle.main.resourceURL ?? url.deletingLastPathComponent()
        webView.loadFileURL(url, allowingReadAccessTo: resourceDir)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!,
                 withError error: Error) {
        NSLog("WCW provisional load failed: %@", error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        NSLog("WCW load failed: %@", error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        injectWorldData()
    }

    /// Reads world-110m.json from the bundle in Swift and calls window.initMap(data).
    private func injectWorldData() {
        guard let jsonURL = Bundle.main.url(forResource: "world-110m", withExtension: "json"),
              let jsonData = try? Data(contentsOf: jsonURL),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            NSLog("WCW: world-110m.json not found")
            return
        }
        webView.evaluateJavaScript("window.initMap(\(jsonString))", completionHandler: nil)
    }

    private func pushCitiesToJS() {
        guard webView != nil,
              let data = try? JSONEncoder().encode(cities),
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

#### Step 2 — Rewrite `map.html` with flat projection + gray/white terminator

Replace the entire `map.html` content with:

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
<script>
// ── State ────────────────────────────────────────────────────────────────────
let cities = [];
let worldData = null;

let width = window.innerWidth;
let height = window.innerHeight;

const svg = d3.select("#map")
  .attr("width", width)
  .attr("height", height);

// ── Projection ────────────────────────────────────────────────────────────────
// Equirectangular ("cover" scale): fills the entire screen, clips excess edges.
// scaleForCover() ensures the map always fills both dimensions with no black bars.
function scaleForCover(w, h) {
  // Equirectangular maps 360° → width at scale s*2π; 180° → height at scale s*π.
  return Math.max(w / (2 * Math.PI), h / Math.PI);
}

const projection = d3.geoEquirectangular()
  .scale(scaleForCover(width, height))
  .translate([width / 2, height / 2])
  .clipExtent([[0, 0], [width, height]]);

const path = d3.geoPath().projection(projection);

// Layers (back → front)
const nightLayer  = svg.append("g").attr("id", "night");
const landLayer   = svg.append("g").attr("id", "land");
const borderLayer = svg.append("g").attr("id", "borders");
const cityLayer   = svg.append("g").attr("id", "cities");

// ── Antisolar point ───────────────────────────────────────────────────────────
// Returns [longitude, latitude] of the point directly opposite the sun.
// A geoCircle of radius 90° centered here equals exactly the night hemisphere.
function getAntisolarPoint(date) {
  const utHours = date.getUTCHours() + date.getUTCMinutes() / 60 + date.getUTCSeconds() / 3600;
  // Longitude of solar noon right now (subsolar meridian)
  const subsolarLon = (180 - (utHours - 12) * 15 + 360) % 360 - 180;
  // Solar declination via day-of-year approximation (±23.45°)
  const dayOfYear = Math.floor((date - new Date(Date.UTC(date.getUTCFullYear(), 0, 0))) / 86400000); // day 1 = Jan 1
  const declination = 23.45 * Math.sin((2 * Math.PI / 365) * (dayOfYear - 81));
  // Antisolar point is the antipode of the subsolar point
  const antiLon = ((subsolarLon + 180) + 540) % 360 - 180;
  const antiLat = -declination;
  return [antiLon, antiLat];
}

// ── Night overlay + terminator line ──────────────────────────────────────────
function drawNight(date) {
  nightLayer.selectAll("*").remove();
  const [lon, lat] = getAntisolarPoint(date);
  const nightGeo = d3.geoCircle().center([lon, lat]).radius(90)();

  // Night: dark semi-transparent gray overlay
  nightLayer.append("path")
    .datum(nightGeo)
    .attr("d", path)
    .attr("fill", "rgba(0, 0, 0, 0.52)");

  // Terminator: crisp white border line
  nightLayer.append("path")
    .datum(nightGeo)
    .attr("d", path)
    .attr("fill", "none")
    .attr("stroke", "rgba(255, 255, 255, 0.85)")
    .attr("stroke-width", 1.5);
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
      .text(city.name ?? "");
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

// ── Init (called by Swift after page load) ────────────────────────────────────
window.initMap = function(data) {
  worldData = data;
  draw();
  setInterval(() => drawNight(new Date()), 60000); // update night zone every 1 min
  setInterval(updateTimes, 1000);                  // update clock digits every 1 sec
};

// ── Resize ────────────────────────────────────────────────────────────────────
let resizeTimer;
window.addEventListener("resize", () => {
  clearTimeout(resizeTimer);
  resizeTimer = setTimeout(() => {
    width = window.innerWidth; height = window.innerHeight;
    svg.attr("width", width).attr("height", height);
    projection
      .scale(scaleForCover(width, height))
      .translate([width / 2, height / 2])
      .clipExtent([[0, 0], [width, height]]);
    draw();
  }, 100);
});

// ── Swift ↔ JS bridge ─────────────────────────────────────────────────────────
window.updateCities = function(newCities) {
  cities = newCities;
  drawCities();
};

window.webkit?.messageHandlers?.cityBridge?.postMessage("requestCities");
</script>
</body>
</html>
```

#### Step 3 — Build and verify visually

```bash
xcodebuild -scheme WorldClockWallpaper -configuration Debug \
  -derivedDataPath build/DerivedData build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

```bash
pkill -f WorldClockWallpaper.app 2>/dev/null; sleep 1
open build/DerivedData/Build/Products/Debug/WorldClockWallpaper.app
```

Expected:
- Map fills the entire screen (no black bars at any edge)
- Map is a flat rectangle, not a rounded-corner globe shape
- Countries visible as dark gray shapes
- Night hemisphere covered by a dark gray (not blue) overlay
- A crisp white line visible at the day/night boundary
- City dots and times visible

#### Step 4 — Run unit tests

```bash
xcodebuild test -scheme WorldClockWallpaper -configuration Debug \
  -derivedDataPath build/DerivedData 2>&1 | grep -E "Test Suite.*passed|FAILED|error:"
```

Expected: all tests pass.

#### Step 5 — Commit

```bash
git add WorldClockWallpaper/MapViewController.swift
git add WorldClockWallpaper/Resources/map.html
git commit -m "fix: flat equirectangular projection, cover-fill screen, gray/white terminator, revert loadFileURL"
```

---

### Task 2: Fix menu popover positioning

**Files:**
- Modify: `WorldClockWallpaper/MenuBarController.swift` line 42

**Root cause:** `NSStatusItem.button` is an `NSButton`, which uses a **flipped** coordinate system
(`isFlipped = true`). In a flipped view, `bounds.minY = 0` is the **top** of the button (the side
touching the menu bar background). `NSPopover` with `preferredEdge: .minY` places its arrow at the
minY edge of the anchor rect — in flipped coordinates this is the top of the button, so the popover
body ends up **above** the button, hidden behind the menu bar.

Fix: change `preferredEdge: .minY` → `.maxY`. In flipped coordinates, `maxY` is the **bottom** of
the button (the side facing into the screen), so the popover body appears **below** the menu bar.

- [ ] **Step 1: Change `preferredEdge` in `togglePopover()`**

  In `WorldClockWallpaper/MenuBarController.swift`, line 42, change:
  ```swift
  popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
  ```
  to:
  ```swift
  popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
  ```

- [ ] **Step 2: Build and verify**

  ```bash
  xcodebuild -scheme WorldClockWallpaper -configuration Debug \
    -derivedDataPath build/DerivedData build 2>&1 | tail -3
  ```

  Expected: `** BUILD SUCCEEDED **`

  Launch and click the menu bar icon. Expected: the popover appears **below** the menu bar with a
  downward-pointing arrow. The arrow tip should touch the icon without the arrow being hidden behind
  it.

  If the popover still appears in the wrong position, add a `DONE_WITH_CONCERNS` note describing
  exactly what you see.

- [ ] **Step 3: Commit**

  ```bash
  git add WorldClockWallpaper/MenuBarController.swift
  git commit -m "fix: show popover below menu bar (preferredEdge .maxY for flipped NSButton coords)"
  ```

---

### Task 3: City geocoding — name only, auto-lookup coordinates

**Files:**
- Create: `WorldClockWallpaper/CityLookupService.swift`
- Modify: `WorldClockWallpaper/SettingsView.swift`
- Modify: `WorldClockWallpaper/project.yml`

**Approach:** Geocoding via Apple's `CLGeocoder` (built-in, no API key, returns coordinates +
timezone from a city name string). The result is used to construct a `City` value. No changes to
`City`, `CityManager`, or the JS bridge — the geocoded `City` is added via the existing
`cityManager.add(_:)` path.

`CLGeocoder.geocodeAddressString(_:)` is available as an `async throws` function in macOS 13+
(the deployment target). It returns an array of `CLPlacemark`; we use the first result.
`CLPlacemark.timeZone` returns the timezone for the geographic location.

**CoreLocation does not require any special entitlements when App Sandbox is OFF**, which is our
current configuration.

- [ ] **Step 1: Add CoreLocation to `project.yml`**

  In `project.yml`, under `targets.WorldClockWallpaper.dependencies`, add:
  ```yaml
  - sdk: CoreLocation.framework
  ```

  Full dependencies section after edit:
  ```yaml
  dependencies:
    - sdk: WebKit.framework
    - sdk: Combine.framework
    - sdk: ServiceManagement.framework
    - sdk: CoreLocation.framework
  ```

- [ ] **Step 2: Regenerate the Xcode project**

  ```bash
  xcodegen generate
  ```

  Expected: `Writing project...` — `project.pbxproj` updated with CoreLocation.

- [ ] **Step 3: Write a failing unit test for `CityLookupService`**

  In `WorldClockWallpaperTests/CityManagerTests.swift`, **append only the class below** at the
  bottom of the file (after the last closing brace). Do NOT add the import lines — they already
  exist in that file.

  ```swift
  final class CityLookupServiceTests: XCTestCase {

      func test_lookup_knownCity_returnsCity() async throws {
          let service = CityLookupService()
          let city = try await service.lookup("Tokyo")
          // Tokyo is in Asia/Tokyo timezone (UTC+9)
          XCTAssertFalse(city.name.isEmpty)
          XCTAssertEqual(city.timezone, "Asia/Tokyo")
          XCTAssertGreaterThan(city.lat, 30)   // Tokyo ~35.7°N
          XCTAssertLessThan(city.lat, 40)
          XCTAssertGreaterThan(city.lon, 135)  // Tokyo ~139.7°E
          XCTAssertLessThan(city.lon, 145)
      }

      func test_lookup_unknownCity_throws() async {
          let service = CityLookupService()
          do {
              _ = try await service.lookup("xyzzy_nonexistent_city_12345")
              XCTFail("Expected error not thrown")
          } catch {
              // Expected
          }
      }
  }
  ```

- [ ] **Step 4: Run the failing test to verify it fails**

  ```bash
  xcodebuild test -scheme WorldClockWallpaper -configuration Debug \
    -derivedDataPath build/DerivedData \
    -only-testing:WorldClockWallpaperTests/CityLookupServiceTests 2>&1 \
    | grep -E "error:|FAILED|passed"
  ```

  Expected: FAILED — `CityLookupService` does not exist yet.

- [ ] **Step 5: Create `CityLookupService.swift`**

  Create `WorldClockWallpaper/CityLookupService.swift`:

  ```swift
  import CoreLocation

  enum CityLookupError: LocalizedError {
      case noResults
      case noLocation
      case noTimezone

      var errorDescription: String? {
          switch self {
          case .noResults:  return "City not found. Try a different spelling or add the country."
          case .noLocation: return "Could not determine coordinates for this city."
          case .noTimezone: return "Could not determine timezone for this city."
          }
      }
  }

  final class CityLookupService {
      private let geocoder = CLGeocoder()

      /// Geocodes `query` and returns a `City` with name, timezone, lat, and lon.
      /// Uses the first result from CLGeocoder. Throws `CityLookupError` on failure.
      func lookup(_ query: String) async throws -> City {
          let placemarks = try await geocoder.geocodeAddressString(query)
          guard let placemark = placemarks.first else { throw CityLookupError.noResults }
          guard let location = placemark.location   else { throw CityLookupError.noLocation }
          guard let tz = placemark.timeZone         else { throw CityLookupError.noTimezone }

          // Use city/town name if available, fall back to the placemark's name, then the query.
          let name = placemark.locality ?? placemark.name ?? query
          return City(
              name: name,
              timezone: tz.identifier,
              lat: location.coordinate.latitude,
              lon: location.coordinate.longitude
          )
      }
  }
  ```

- [ ] **Step 6: Run tests to verify they pass**

  ```bash
  xcodebuild test -scheme WorldClockWallpaper -configuration Debug \
    -derivedDataPath build/DerivedData \
    -only-testing:WorldClockWallpaperTests/CityLookupServiceTests 2>&1 \
    | grep -E "error:|FAILED|passed"
  ```

  Expected: `Test Suite 'CityLookupServiceTests' passed`

  Note: these tests make real network requests (CLGeocoder hits Apple's servers). They will fail
  without internet access. That is expected and acceptable — do not mock.

- [ ] **Step 7: Replace `AddCityForm` in `SettingsView.swift`**

  In `WorldClockWallpaper/SettingsView.swift`, replace the entire `AddCityForm` struct (lines 83–124)
  with this geocoding-based form. The `SettingsView` struct itself is unchanged.

  ```swift
  struct AddCityForm: View {
      @ObservedObject var cityManager: CityManager
      @Binding var isShowing: Bool
      @State private var query = ""
      @State private var isLoading = false
      @State private var errorMessage: String?

      private let lookupService = CityLookupService()

      var body: some View {
          VStack(alignment: .leading, spacing: 8) {
              TextField("City name (e.g. Tokyo, New York)", text: $query)
                  .textFieldStyle(.roundedBorder)
                  .disabled(isLoading)
                  .onSubmit { addCity() }

              if let msg = errorMessage {
                  Text(msg)
                      .font(.caption)
                      .foregroundColor(.red)
              }

              HStack {
                  Button("Cancel") { isShowing = false }
                      .disabled(isLoading)
                  Spacer()
                  if isLoading {
                      ProgressView().controlSize(.small)
                  } else {
                      Button("Add") { addCity() }
                          .keyboardShortcut(.return)
                          .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                  }
              }
          }
          .padding(12)
      }

      private func addCity() {
          let trimmed = query.trimmingCharacters(in: .whitespaces)
          guard !trimmed.isEmpty else { return }
          isLoading = true
          errorMessage = nil
          Task {
              do {
                  let city = try await lookupService.lookup(trimmed)
                  await MainActor.run {
                      isLoading = false
                      cityManager.add(city)
                      isShowing = false
                  }
              } catch {
                  await MainActor.run {
                      isLoading = false
                      errorMessage = error.localizedDescription
                  }
              }
          }
      }
  }
  ```

- [ ] **Step 8: Build and verify the full app compiles**

  ```bash
  xcodebuild -scheme WorldClockWallpaper -configuration Debug \
    -derivedDataPath build/DerivedData build 2>&1 | tail -3
  ```

  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 9: Smoke-test the geocoding UI**

  ```bash
  pkill -f WorldClockWallpaper.app 2>/dev/null; sleep 1
  open build/DerivedData/Build/Products/Debug/WorldClockWallpaper.app
  ```

  Click the menu bar icon → "Add City" → type "Berlin" → press Enter or click Add.
  Expected:
  - A spinner appears briefly while geocoding
  - City "Berlin" appears in the list with timezone `Europe/Berlin` and correct time
  - No lat/lon/timezone fields in the form

  Type "xyzzy_nonexistent" → click Add.
  Expected: an error message appears below the text field, form stays open.

- [ ] **Step 10: Run all unit tests**

  ```bash
  xcodebuild test -scheme WorldClockWallpaper -configuration Debug \
    -derivedDataPath build/DerivedData 2>&1 | grep -E "Test Suite.*passed|FAILED|error:"
  ```

  Expected: all test suites pass.

- [ ] **Step 11: Commit**

  ```bash
  git add WorldClockWallpaper/CityLookupService.swift
  git add WorldClockWallpaper/SettingsView.swift
  git add project.yml WorldClockWallpaper.xcodeproj/project.pbxproj
  git commit -m "feat: city geocoding — name-only add form using CLGeocoder (lat/lon/tz auto-resolved)"
  ```

---

## Build Command Reference

```bash
# Build only
xcodebuild -scheme WorldClockWallpaper -configuration Debug \
  -derivedDataPath build/DerivedData build 2>&1 | tail -5

# Run all tests
xcodebuild test -scheme WorldClockWallpaper -configuration Debug \
  -derivedDataPath build/DerivedData 2>&1 | grep -E "Test Suite.*passed|FAILED|error:"

# Kill old instance + launch fresh build
pkill -f WorldClockWallpaper.app 2>/dev/null; sleep 1
open build/DerivedData/Build/Products/Debug/WorldClockWallpaper.app
```

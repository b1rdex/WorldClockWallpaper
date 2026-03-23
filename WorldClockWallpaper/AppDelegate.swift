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

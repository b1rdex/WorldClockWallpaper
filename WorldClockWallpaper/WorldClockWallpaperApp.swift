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

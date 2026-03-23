import AppKit

final class WallpaperWindow: NSWindow {

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
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

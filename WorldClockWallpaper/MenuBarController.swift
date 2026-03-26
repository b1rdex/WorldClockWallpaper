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

    deinit {
        if popover.isShown {
            popover.performClose(nil)
        }
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

            // NSPopover miscalculates position for LSUIElement status-bar apps.
            // Fix: slide the popover window so its top edge aligns with the button's bottom.
            if let pw = popover.contentViewController?.view.window,
               let bw = button.window {
                let buttonScreen = bw.convertToScreen(button.convert(button.bounds, to: nil))
                var f = pw.frame
                f.origin.y = buttonScreen.minY - f.height
                pw.setFrameOrigin(f.origin)
            }

            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

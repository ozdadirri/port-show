import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let state = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = Self.menuBarIcon()
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = PopoverViewController(state: state)

        state.start()
    }

    /// ":_" badge matching the ":80" app icon. A template image, so macOS
    /// tints it for light/dark menu bars and the highlighted state.
    private static func menuBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.set()
            let badge = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 3.5, width: 15, height: 11), xRadius: 3, yRadius: 3)
            badge.lineWidth = 1.4
            badge.stroke()
            NSBezierPath(ovalIn: NSRect(x: 4.7, y: 6.2, width: 2.2, height: 2.2)).fill()
            NSBezierPath(ovalIn: NSRect(x: 4.7, y: 9.6, width: 2.2, height: 2.2)).fill()
            let cursor = NSBezierPath()
            cursor.move(to: NSPoint(x: 8.8, y: 10.7))
            cursor.line(to: NSPoint(x: 12.6, y: 10.7))
            cursor.lineWidth = 1.5
            cursor.lineCapStyle = .round
            cursor.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "PortShow"
        return image
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            state.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.stop()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

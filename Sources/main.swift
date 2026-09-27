import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let state = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "PortShow")
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

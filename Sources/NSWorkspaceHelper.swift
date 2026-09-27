import AppKit
import Foundation

enum NSWorkspaceHelper {

    /// Opens http://<host>:<port> in the default browser.
    static func open(address: String, port: Int) {
        let host = (address == "*" || address.isEmpty) ? "localhost" : address
        guard let url = URL(string: "http://\(host):\(port)") else { return }
        NSWorkspace.shared.open(url)
    }

    /// The user-facing app name for a PID, when it belongs to a registered
    /// running application (e.g. an .app bundle), else nil.
    static func runningAppName(forPID pid: Int32) -> String? {
        NSRunningApplication(processIdentifier: pid)?.localizedName
    }

    static func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}

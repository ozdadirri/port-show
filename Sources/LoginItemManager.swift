import Foundation

/// Manages launch-at-login via a per-user LaunchAgent. This avoids
/// SMAppService's stricter code-signing requirements so it works reliably
/// for an ad-hoc-signed, non-App-Store build across macOS versions.
enum LoginItemManager {

    private static let agentLabel = "com.portshow.launcher"

    private static var agentPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: agentPlistURL.path)
    }

    static func setEnabled(_ enabled: Bool) {
        if enabled {
            enable()
        } else {
            disable()
        }
    }

    private static func enable() {
        guard let executablePath = Bundle.main.executablePath else { return }
        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false
        ]
        let launchAgentsDir = agentPlistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return }
        try? data.write(to: agentPlistURL)
        runLaunchctl(["load", agentPlistURL.path])
    }

    private static func disable() {
        runLaunchctl(["unload", agentPlistURL.path])
        try? FileManager.default.removeItem(at: agentPlistURL)
    }

    @discardableResult
    private static func runLaunchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}

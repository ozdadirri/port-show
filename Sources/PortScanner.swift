import Foundation
import Darwin
import AppKit

enum PortScanner {

    static func scan() -> [PortEntry] {
        var entries: [PortEntry] = []
        entries.append(contentsOf: runLsof(protoFlag: "TCP", args: ["+c", "0", "-nP", "-iTCP", "-sTCP:LISTEN"]))
        entries.append(contentsOf: runLsof(protoFlag: "UDP", args: ["+c", "0", "-nP", "-iUDP"]))

        // Several processes (e.g. a supervisor + workers) can share one
        // listening socket after fork(); collapse those to one row, keeping
        // the lowest PID (typically the parent/owner process).
        var byPortProto: [String: PortEntry] = [:]
        for entry in entries {
            let key = "\(entry.proto)-\(entry.port)"
            if let existing = byPortProto[key] {
                if entry.pid < existing.pid { byPortProto[key] = entry }
            } else {
                byPortProto[key] = entry
            }
        }
        // Drop cached info for exited processes so a reused PID isn't mislabelled.
        let livePIDs = Set(entries.map(\.pid))
        nameCache = nameCache.filter { livePIDs.contains($0.key) }
        categoryCache = categoryCache.filter { livePIDs.contains($0.key) }

        return byPortProto.values.sorted { $0.port < $1.port }
    }

    private static func runLsof(protoFlag: String, args: [String]) -> [PortEntry] {
        guard let output = run("/usr/sbin/lsof", args) else { return [] }
        var entries: [PortEntry] = []

        let lines = output.split(separator: "\n").dropFirst()
        for line in lines {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard cols.count >= 9 else { continue }
            // lsof escapes spaces in the command name ("Code\x20Helper").
            let command = cols[0].replacingOccurrences(of: "\\x20", with: " ")
            guard let pid = Int32(cols[1]) else { continue }
            let name = cols[8]

            // strip "->remote" suffix from connected sockets, keep local side only
            let localPart = name.split(separator: "-").first.map(String.init) ?? name
            guard let colonRange = localPart.range(of: ":", options: .backwards) else { continue }
            var address = String(localPart[localPart.startIndex..<colonRange.lowerBound])
            let portStr = String(localPart[colonRange.upperBound...])
            guard let port = Int(portStr) else { continue }
            if address.isEmpty || address == "*" { address = "*" }

            let displayName = friendlyName(forPID: pid, shortCommand: command)
            entries.append(PortEntry(proto: protoFlag, port: port, pid: pid, processName: displayName, address: address, category: category(forPID: pid)))
        }
        return entries
    }

    /// Only touched from the serial scan queue.
    private static var categoryCache: [Int32: PortCategory] = [:]

    /// Classifies by where the executable lives: macOS system folders are
    /// System, anything inside an .app bundle is an App, everything else
    /// (Homebrew, interpreters, project binaries) is a Service.
    private static func category(forPID pid: Int32) -> PortCategory {
        if let cached = categoryCache[pid] { return cached }
        let path = executablePath(forPID: pid)
        let systemPrefixes = ["/System/", "/usr/bin/", "/usr/sbin/", "/usr/libexec/", "/bin/", "/sbin/", "/Library/Apple/"]
        let result: PortCategory
        let exeName = (path as NSString).lastPathComponent.lowercased()
        let userLibrary = FileManager.default.homeDirectoryForCurrentUser.path + "/Library/"
        if path.isEmpty || systemPrefixes.contains(where: path.hasPrefix) {
            // Empty means we can't read it — typically a root-owned system daemon.
            result = .system
        } else if path.hasPrefix(userLibrary) || path.hasPrefix("/Library/") {
            // Runtimes/helpers installed and managed by apps (e.g. Neo4j Desktop's
            // bundled Java under ~/Library/Application Support), not started by you.
            result = .system
        } else if interpreterNames.contains(where: { exeName == $0 || exeName.hasPrefix($0) }) {
            // Scripts are services even when the interpreter lives in a bundle
            // (Homebrew's Python runs from .../Python.app/Contents/MacOS/Python).
            result = .service
        } else if path.contains(".app/") {
            result = .app
        } else {
            result = .service
        }
        categoryCache[pid] = result
        return result
    }

    /// Full executable path from the kernel; `ps` gives only a bare name when
    /// the program was started via PATH, and splitting `command` breaks on spaces.
    private static func executablePath(forPID pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 4096)
        return proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : ""
    }

    /// Generic interpreters report their own name (e.g. "Python", "node") to
    /// `lsof`, which is useless when several scripts run under the same
    /// interpreter. Prefer the app's real name, then fall back to the
    /// script/jar being run, then the interpreter itself.
    private static let interpreterNames: Set<String> = [
        "python", "python3", "node", "ruby", "perl", "php", "java", "deno", "bun"
    ]

    /// Only touched from the serial scan queue.
    private static var nameCache: [Int32: String] = [:]

    private static func friendlyName(forPID pid: Int32, shortCommand: String) -> String {
        if let cached = nameCache[pid] { return cached }
        let name = resolveFriendlyName(forPID: pid, shortCommand: shortCommand)
        nameCache[pid] = name
        return name
    }

    private static func resolveFriendlyName(forPID pid: Int32, shortCommand: String) -> String {
        if let appName = NSWorkspaceHelper.runningAppName(forPID: pid), !appName.isEmpty {
            return appName
        }

        let lowerShort = shortCommand.lowercased()
        let isGenericInterpreter = interpreterNames.contains { lowerShort == $0 || lowerShort.hasPrefix($0) }
        guard isGenericInterpreter,
              let fullCommand = run("/bin/ps", ["-p", "\(pid)", "-o", "command="])?
                .trimmingCharacters(in: .whitespacesAndNewlines), !fullCommand.isEmpty else {
            return shortCommand
        }

        let args = Array(fullCommand.split(separator: " ").map(String.init).dropFirst())
        // What's being run: `-m module`, else the first script/jar-looking argument.
        var runner: String?
        if let m = args.firstIndex(of: "-m"), m + 1 < args.count {
            runner = args[m + 1]
        } else if let script = args.first(where: { !$0.hasPrefix("-") && ($0.contains("/") || $0.contains(".")) }) {
            runner = ((script as NSString).lastPathComponent as NSString).deletingPathExtension
        }

        // The working directory is usually the project folder (e.g. ~/Dev/audio-log),
        // which names the app far better than "app.main:app" or "server.js".
        if let project = projectFolderName(forPID: pid) {
            return "\(project) (\(runner ?? shortCommand))"
        }
        if let runner, !runner.isEmpty {
            return "\(runner) (\(shortCommand))"
        }
        return shortCommand
    }

    private static func projectFolderName(forPID pid: Int32) -> String? {
        guard let path = workingDirectory(forPID: pid) else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path != "/", path != home else { return nil }
        return (path as NSString).lastPathComponent
    }

    private static func workingDirectory(forPID pid: Int32) -> String? {
        guard let output = run("/usr/sbin/lsof", ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]),
              let line = output.split(separator: "\n").first(where: { $0.hasPrefix("n") }) else { return nil }
        return String(line.dropFirst())
    }

    /// Best guess at the file that started the process: the script/jar or
    /// Python module it was launched with (resolved against its working
    /// directory), falling back to the executable itself.
    static func startFileURL(forPID pid: Int32) -> URL? {
        let fm = FileManager.default
        let cwd = workingDirectory(forPID: pid)
        let args = run("/bin/ps", ["-p", "\(pid)", "-o", "command="])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ").map(String.init) ?? []

        func resolve(_ path: String) -> String? {
            let full = path.hasPrefix("/") ? path : cwd.map { ($0 as NSString).appendingPathComponent(path) } ?? path
            return fm.fileExists(atPath: full) ? full : nil
        }

        // "pkg.module:attr" or "pkg.module" -> pkg/module.py or pkg/module/__init__.py
        func pythonModuleFile(_ spec: String) -> String? {
            let module = spec.split(separator: ":").first.map(String.init) ?? spec
            let rel = module.replacingOccurrences(of: ".", with: "/")
            return resolve(rel + ".py") ?? resolve(rel + "/__init__.py") ?? resolve(rel + "/__main__.py")
        }

        let executable = executablePath(forPID: pid)
        let exeName = (executable as NSString).lastPathComponent.lowercased()
        let isInterpreter = interpreterNames.contains { exeName == $0 || exeName.hasPrefix($0) }

        // For native programs, path arguments are usually data dirs, not the start file.
        guard isInterpreter else {
            return fm.fileExists(atPath: executable) ? URL(fileURLWithPath: executable) : nil
        }

        let positional = args.dropFirst().filter { !$0.hasPrefix("-") }

        if let m = args.firstIndex(of: "-m"), m + 1 < args.count {
            // e.g. `python -m uvicorn app.main:app` -> app/main.py
            for candidate in positional where candidate != args[m + 1] && candidate.contains(".") {
                if let file = pythonModuleFile(candidate) { return URL(fileURLWithPath: file) }
            }
            if let file = pythonModuleFile(args[m + 1]) { return URL(fileURLWithPath: file) }
        }
        for candidate in positional where candidate.contains("/") || candidate.contains(".") {
            if let file = resolve(candidate) { return URL(fileURLWithPath: file) }
        }
        if let cwd, cwd != "/", cwd != fm.homeDirectoryForCurrentUser.path {
            return URL(fileURLWithPath: cwd)
        }
        return fm.fileExists(atPath: executable) ? URL(fileURLWithPath: executable) : nil
    }

    private static func run(_ launchPath: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func kill(pid: Int32, force: Bool) -> Bool {
        let signal: Int32 = force ? SIGKILL : SIGTERM
        return Darwin.kill(pid, signal) == 0
    }

    static func revealInFinder(pid: Int32) {
        guard let url = startFileURL(forPID: pid) else { return NSSound.beep() }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

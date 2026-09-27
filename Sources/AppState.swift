import Foundation

final class AppState {
    private(set) var entries: [PortEntry] = []
    var searchText: String = "" {
        didSet { onChange?() }
    }
    private(set) var launchAtLoginEnabled: Bool = LoginItemManager.isEnabled
    private(set) var notificationsEnabled: Bool = false

    /// Called on the main thread whenever data the UI should reflect changes.
    var onChange: (() -> Void)?

    let favoritesStore = FavoritesStore()

    private var timer: Timer?
    private var previousFavoritePorts: Set<Int> = []
    private var hasScannedOnce = false
    private let scanQueue = DispatchQueue(label: "com.portshow.scan", qos: .utility)

    var filteredEntries: [PortEntry] {
        guard !searchText.isEmpty else { return entries }
        let query = searchText.lowercased()
        return entries.filter {
            String($0.port).contains(query)
                || $0.processName.lowercased().contains(query)
                || String($0.pid).contains(query)
                || $0.address.lowercased().contains(query)
        }
    }

    var pinnedEntries: [PortEntry] {
        entries.filter { favoritesStore.isFavorite($0.port) }
    }

    func listedEntries(in category: PortCategory) -> [PortEntry] {
        filteredEntries.filter { $0.category == category && !favoritesStore.isFavorite($0.port) }
    }

    var showSystemPorts: Bool = UserDefaults.standard.bool(forKey: "com.portshow.showSystemPorts") {
        didSet {
            UserDefaults.standard.set(showSystemPorts, forKey: "com.portshow.showSystemPorts")
            onChange?()
        }
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        scanQueue.async { [weak self] in
            let scanned = PortScanner.scan()
            DispatchQueue.main.async {
                self?.apply(scanned)
            }
        }
    }

    func toggleLaunchAtLogin() {
        launchAtLoginEnabled.toggle()
        LoginItemManager.setEnabled(launchAtLoginEnabled)
        onChange?()
    }

    func toggleNotifications() {
        notificationsEnabled.toggle()
        if notificationsEnabled {
            NotificationManager.shared.requestAuthorizationIfNeeded()
        }
        onChange?()
    }

    func openInBrowser(_ entry: PortEntry) {
        NSWorkspaceHelper.open(address: entry.address, port: entry.port)
    }

    func kill(_ entry: PortEntry, force: Bool = false) {
        PortScanner.kill(pid: entry.pid, force: force)
        refresh()
    }

    func revealInFinder(_ entry: PortEntry) {
        PortScanner.revealInFinder(pid: entry.pid)
    }

    func copyDetails(_ entry: PortEntry) {
        NSWorkspaceHelper.copyToPasteboard("\(entry.proto) \(entry.port) — \(entry.processName) (pid \(entry.pid))")
    }

    func toggleFavorite(_ entry: PortEntry) {
        favoritesStore.toggle(port: entry.port, defaultLabel: entry.processName)
        onChange?()
    }

    private func apply(_ scanned: [PortEntry]) {
        if notificationsEnabled {
            diffFavoritesAndNotify(scanned)
        }
        entries = scanned
        onChange?()
    }

    private func diffFavoritesAndNotify(_ scanned: [PortEntry]) {
        let currentFavoritePorts = Set(scanned.map(\.port)).intersection(Set(favoritesStore.favorites.map(\.port)))

        if hasScannedOnce {
            let wentDown = previousFavoritePorts.subtracting(currentFavoritePorts)
            let wentUp = currentFavoritePorts.subtracting(previousFavoritePorts)
            for port in wentDown {
                let label = favoritesStore.label(for: port) ?? "Port \(port)"
                NotificationManager.shared.notifyPortWentDown(port: port, label: label)
            }
            for port in wentUp {
                let label = favoritesStore.label(for: port) ?? "Port \(port)"
                NotificationManager.shared.notifyPortWentUp(port: port, label: label)
            }
        }
        previousFavoritePorts = currentFavoritePorts
        hasScannedOnce = true
    }
}

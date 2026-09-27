import AppKit

/// A titled group of port rows in the scrolling list.
private final class ListSection {
    let category: PortCategory
    let container = NSStackView()
    let stack = NSStackView()
    var rowIDs: [String] = []

    init(category: PortCategory, label: NSTextField) {
        self.category = category
        stack.orientation = .vertical
        stack.spacing = 2
        container.orientation = .vertical
        container.spacing = 4
        container.addArrangedSubview(label)
        container.addArrangedSubview(stack)
    }
}

final class PopoverViewController: NSViewController, NSSearchFieldDelegate {
    private let state: AppState

    private let countLabel = NSTextField(labelWithString: "")
    private let searchField = NSSearchField()
    private let pinnedSectionLabel = sectionLabel("PINNED")
    private let pinnedStack = NSStackView()
    private let pinnedContainer = NSStackView()
    private let sections: [ListSection] = [
        ListSection(category: .app, label: sectionLabel("APPS")),
        ListSection(category: .service, label: sectionLabel("SERVICES")),
        ListSection(category: .system, label: sectionLabel("SYSTEM"))
    ]
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at Login", target: nil, action: nil)
    private let showSystemCheckbox = NSButton(checkboxWithTitle: "System ports", target: nil, action: nil)

    // Rows are expensive to recreate (each new view has to race through a
    // fresh Auto Layout resolution). When the same set of ports is still
    // showing, reuse the existing views and just refresh their text instead
    // of tearing the whole list down every 3-second refresh.
    private var pinnedRowIDs: [String] = []

    init(state: AppState) {
        self.state = state
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 600))
        view.appearance = NSAppearance(named: .darkAqua)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(red: 0.149, green: 0.149, blue: 0.145, alpha: 1).cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        state.onChange = { [weak self] in self?.reload() }
        reload()
    }

    private func buildUI() {
        // Header
        let titleLabel = NSTextField(labelWithString: "Ports")
        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        countLabel.font = NSFont.systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabelColor

        let refreshButton = iconButton(systemName: "arrow.triangle.2.circlepath", selector: #selector(handleRefresh))
        let settingsButton = iconButton(systemName: "gearshape", selector: #selector(handleSettings))

        let headerLeft = NSStackView(views: [titleLabel, countLabel])
        headerLeft.orientation = .horizontal
        headerLeft.alignment = .firstBaseline
        headerLeft.spacing = 6

        let headerRight = NSStackView(views: [refreshButton, settingsButton])
        headerRight.orientation = .horizontal
        headerRight.spacing = 4

        let headerRow = NSStackView(views: [headerLeft, NSView(), headerRight])
        headerRow.orientation = .horizontal
        headerRow.distribution = .fill

        // Search
        searchField.placeholderString = "Search port, app, or PID"
        searchField.delegate = self

        // Pinned
        pinnedStack.orientation = .vertical
        pinnedStack.spacing = 2
        pinnedContainer.orientation = .vertical
        pinnedContainer.spacing = 4
        pinnedContainer.addArrangedSubview(pinnedSectionLabel)
        pinnedContainer.addArrangedSubview(pinnedStack)

        let divider1 = NSBox()
        divider1.boxType = .separator

        // List: one section per category
        let listContentStack = NSStackView(views: sections.map(\.container))
        listContentStack.orientation = .vertical
        listContentStack.spacing = 14
        listContentStack.translatesAutoresizingMaskIntoConstraints = false

        let clipView = FlippedClipView()
        let scrollView = NSScrollView()
        scrollView.contentView = clipView
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = listContentStack
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clipView, queue: .main) { [weak self] _ in
            self?.refreshListHover()
            // Again after pending tracking events for this scroll step are delivered.
            DispatchQueue.main.async { self?.refreshListHover() }
        }

        // Vertical NSStackViews center children at their fitting width by
        // default; pin the row containers so rows span the full popover.
        NSLayoutConstraint.activate([
            listContentStack.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            listContentStack.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            listContentStack.topAnchor.constraint(equalTo: clipView.topAnchor),
            pinnedStack.widthAnchor.constraint(equalTo: pinnedContainer.widthAnchor)
        ])
        for section in sections {
            NSLayoutConstraint.activate([
                section.container.widthAnchor.constraint(equalTo: listContentStack.widthAnchor),
                section.stack.widthAnchor.constraint(equalTo: section.container.widthAnchor)
            ])
        }

        let divider2 = NSBox()
        divider2.boxType = .separator

        // Footer
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(handleLaunchAtLoginToggle)
        launchAtLoginCheckbox.font = NSFont.systemFont(ofSize: 11)

        let quitButton = NSButton(title: "Quit", target: self, action: #selector(handleQuit))
        quitButton.isBordered = false
        quitButton.font = NSFont.systemFont(ofSize: 11)

        showSystemCheckbox.target = self
        showSystemCheckbox.action = #selector(handleShowSystemToggle)
        showSystemCheckbox.font = NSFont.systemFont(ofSize: 11)

        let footerRow = NSStackView(views: [launchAtLoginCheckbox, showSystemCheckbox, NSView(), quitButton])
        footerRow.orientation = .horizontal

        // Root layout
        let root = NSStackView(views: [headerRow, searchField, pinnedContainer, divider1, scrollView, divider2, footerRow])
        root.orientation = .vertical
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 10, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 260),
            pinnedContainer.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -32),
            scrollView.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -32)
        ])
    }

    private func refreshListHover() {
        for section in sections {
            section.stack.arrangedSubviews.forEach { ($0 as? PortRowView)?.refreshHover() }
        }
    }

    private func iconButton(systemName: String, selector: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: systemName, accessibilityDescription: nil)!, target: self, action: selector)
        button.isBordered = false
        button.widthAnchor.constraint(equalToConstant: 26).isActive = true
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return button
    }

    private static func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func reload() {
        countLabel.stringValue = "\(state.entries.count) listening"

        updateRows(in: pinnedStack, entries: state.pinnedEntries, pinned: true, previousIDs: &pinnedRowIDs)
        pinnedContainer.isHidden = state.pinnedEntries.isEmpty

        for section in sections {
            let hidden = section.category == .system && !state.showSystemPorts
            let entries = hidden ? [] : state.listedEntries(in: section.category)
            updateRows(in: section.stack, entries: entries, pinned: false, previousIDs: &section.rowIDs)
            section.container.isHidden = entries.isEmpty
        }

        launchAtLoginCheckbox.state = state.launchAtLoginEnabled ? .on : .off
        showSystemCheckbox.state = state.showSystemPorts ? .on : .off
    }

    private func updateRows(in stack: NSStackView, entries: [PortEntry], pinned: Bool, previousIDs: inout [String]) {
        let newIDs = entries.map(\.id)

        if newIDs == previousIDs {
            // Same ports, same order — just refresh text in the existing views.
            for (row, entry) in zip(stack.arrangedSubviews.compactMap { $0 as? PortRowView }, entries) {
                let displayName = entry.processName
                row.configure(entry: entry, displayName: displayName, isPinned: pinned)
            }
            return
        }

        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for entry in entries {
            let row = makeRow(for: entry, pinned: pinned)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        previousIDs = newIDs
    }

    private func makeRow(for entry: PortEntry, pinned: Bool) -> PortRowView {
        let row = PortRowView(frame: NSRect(x: 0, y: 0, width: 300, height: 40))
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let displayName = entry.processName
        row.configure(entry: entry, displayName: displayName, isPinned: pinned)

        row.onOpen = { [weak self] in self?.state.openInBrowser(entry) }
        row.onCopy = { [weak self] in self?.state.copyDetails(entry) }
        row.onCopyPort = { NSWorkspaceHelper.copyToPasteboard("\(entry.port)") }
        row.onCopyPID = { NSWorkspaceHelper.copyToPasteboard("\(entry.pid)") }
        row.onKill = { [weak self] in self?.state.kill(entry) }
        row.onReveal = { [weak self] in self?.state.revealInFinder(entry) }
        row.onToggleFavorite = { [weak self] in self?.state.toggleFavorite(entry) }
        return row
    }

    @objc private func handleRefresh() { state.refresh() }
    @objc private func handleSettings(_ sender: NSButton) {
        let menu = NSMenu()

        let intervalItem = NSMenuItem(title: "Refresh Every", action: nil, keyEquivalent: "")
        let intervalMenu = NSMenu()
        for seconds in AppState.refreshIntervalOptions {
            let item = NSMenuItem(title: "\(Int(seconds)) seconds", action: #selector(handleIntervalChoice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = seconds
            item.state = seconds == state.refreshInterval ? .on : .off
            intervalMenu.addItem(item)
        }
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)

        let udpItem = NSMenuItem(title: "Show UDP Ports", action: #selector(handleUDPToggle), keyEquivalent: "")
        udpItem.target = self
        udpItem.state = state.showUDPPorts ? .on : .off
        menu.addItem(udpItem)

        let notifyItem = NSMenuItem(title: "Notify When Pinned Ports Go Up/Down", action: #selector(handleNotificationsToggle), keyEquivalent: "")
        notifyItem.target = self
        notifyItem.state = state.notificationsEnabled ? .on : .off
        menu.addItem(notifyItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "About PortShow", action: #selector(handleAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let githubItem = NSMenuItem(title: "View on GitHub", action: #selector(handleOpenGitHub), keyEquivalent: "")
        githubItem.target = self
        menu.addItem(githubItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit PortShow", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func handleIntervalChoice(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? TimeInterval else { return }
        state.refreshInterval = seconds
    }

    @objc private func handleUDPToggle() { state.showUDPPorts.toggle() }
    @objc private func handleNotificationsToggle() { state.toggleNotifications() }

    @objc private func handleAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func handleOpenGitHub() {
        NSWorkspace.shared.open(URL(string: "https://github.com/ozdadirri/port-show")!)
    }
    @objc private func handleLaunchAtLoginToggle() { state.toggleLaunchAtLogin() }
    @objc private func handleShowSystemToggle() { state.showSystemPorts = showSystemCheckbox.state == .on }
    @objc private func handleQuit() { NSApplication.shared.terminate(nil) }

    func controlTextDidChange(_ obj: Notification) {
        state.searchText = searchField.stringValue
        reload()
    }
}

final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

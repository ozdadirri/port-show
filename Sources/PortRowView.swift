import AppKit

final class PortRowView: NSView {
    var entry: PortEntry!
    var isPinned: Bool = false
    var displayName: String = ""

    var onOpen: (() -> Void)?
    var onCopy: (() -> Void)?
    var onCopyPort: (() -> Void)?
    var onCopyPID: (() -> Void)?
    var onKill: (() -> Void)?
    var onReveal: (() -> Void)?
    var onToggleFavorite: (() -> Void)?

    private let background = NSView()
    private let protoBadge = PaddedLabel()
    private let portLabel = NSTextField(labelWithString: "")
    private let nameLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let starButton = NSButton(image: NSImage(systemSymbolName: "star", accessibilityDescription: nil)!, target: nil, action: nil)
    private let actionsStack = NSStackView()
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        wantsLayer = true
        // Since macOS 14 views don't clip by default, which makes visibleRect
        // (and so the .inVisibleRect tracking area) span the whole list.
        if #available(macOS 14.0, *) { clipsToBounds = true }

        background.wantsLayer = true
        background.layer?.cornerRadius = 6
        background.layer?.backgroundColor = NSColor.clear.cgColor
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        portLabel.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .semibold)
        nameLabel.font = NSFont.systemFont(ofSize: 12.5)
        nameLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = NSFont.systemFont(ofSize: 10.5)
        subtitleLabel.textColor = .secondaryLabelColor

        protoBadge.font = NSFont.systemFont(ofSize: 9.5, weight: .bold)
        protoBadge.wantsLayer = true
        protoBadge.layer?.cornerRadius = 4

        starButton.isBordered = false
        starButton.target = self
        starButton.action = #selector(handleFavoriteTap)
        starButton.contentTintColor = .secondaryLabelColor

        let openButton = actionButton(systemName: "arrow.up.right.square", tint: NSColor(red: 0.5, green: 0.82, blue: 1, alpha: 1), selector: #selector(handleOpenTap))
        let copyButton = actionButton(systemName: "doc.on.doc", tint: .secondaryLabelColor, selector: #selector(handleCopyTap))
        let revealButton = actionButton(systemName: "folder", tint: .secondaryLabelColor, selector: #selector(handleRevealTap))
        revealButton.toolTip = "Show start script in Finder"
        let killButton = actionButton(systemName: "xmark.circle.fill", tint: NSColor(red: 1, green: 0.41, blue: 0.38, alpha: 1), selector: #selector(handleKillTap))
        actionsStack.orientation = .horizontal
        actionsStack.spacing = 3
        actionsStack.addArrangedSubview(openButton)
        actionsStack.addArrangedSubview(copyButton)
        actionsStack.addArrangedSubview(revealButton)
        actionsStack.addArrangedSubview(killButton)

        let textStack = NSStackView(views: [nameLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        textStack.setHuggingPriority(.defaultLow, for: .horizontal)
        textStack.setClippingResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
        protoBadge.setContentHuggingPriority(.required, for: .horizontal)
        portLabel.setContentHuggingPriority(.required, for: .horizontal)

        let leftStack = NSStackView(views: [protoBadge, portLabel, textStack])
        leftStack.orientation = .horizontal
        leftStack.alignment = .centerY
        leftStack.distribution = .fill
        leftStack.spacing = 10
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(leftStack)

        starButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(starButton)

        // The hover icons float over the end of the name instead of reserving
        // space, so the name gets the full width up to the star.
        actionsStack.wantsLayer = true
        actionsStack.layer?.backgroundColor = NSColor(calibratedWhite: 0.235, alpha: 1).cgColor
        actionsStack.layer?.cornerRadius = 5
        actionsStack.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 2)
        actionsStack.isHidden = true
        actionsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(actionsStack)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),

            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            leftStack.trailingAnchor.constraint(equalTo: starButton.leadingAnchor, constant: -10),
            leftStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            starButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            starButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            starButton.widthAnchor.constraint(equalToConstant: 20),

            actionsStack.trailingAnchor.constraint(equalTo: starButton.leadingAnchor, constant: -6),
            actionsStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            actionsStack.heightAnchor.constraint(equalToConstant: 26),

            portLabel.widthAnchor.constraint(equalToConstant: 42)
        ])
    }

    private func actionButton(systemName: String, tint: NSColor, selector: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: systemName, accessibilityDescription: nil)!, target: self, action: selector)
        button.isBordered = false
        button.contentTintColor = tint
        button.widthAnchor.constraint(equalToConstant: 22).isActive = true
        button.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return button
    }

    func configure(entry: PortEntry, displayName: String, isPinned: Bool) {
        self.entry = entry
        self.displayName = displayName
        self.isPinned = isPinned

        let isTCP = entry.proto == "TCP"
        protoBadge.stringValue = entry.proto
        protoBadge.textColor = isTCP ? NSColor(red: 0.5, green: 0.69, blue: 1, alpha: 1) : NSColor(red: 0.72, green: 0.55, blue: 1, alpha: 1)
        protoBadge.layer?.backgroundColor = (isTCP ? NSColor.systemBlue : NSColor.systemPurple).withAlphaComponent(0.16).cgColor

        portLabel.stringValue = "\(entry.port)"
        nameLabel.stringValue = displayName
        subtitleLabel.stringValue = "\(entry.address) · pid \(entry.pid)"

        starButton.image = NSImage(systemSymbolName: isPinned ? "star.fill" : "star", accessibilityDescription: nil)
        starButton.contentTintColor = isPinned ? .systemYellow : .secondaryLabelColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    // Enter/exit events are unreliable while scrolling (stale enters arrive for
    // rows that have already moved away), so always derive from the cursor.
    override func mouseEntered(with event: NSEvent) { refreshHover() }

    override func mouseExited(with event: NSEvent) { refreshHover() }

    /// Re-derives hover from the real cursor position; needed after scrolling,
    /// which moves rows under a stationary cursor without sending mouseExited.
    func refreshHover() {
        guard let window, !isHiddenOrHasHiddenAncestor else { return setHovered(false) }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        // visibleRect isn't limited to our bounds when views don't clip (macOS 14+).
        setHovered(bounds.intersection(visibleRect).contains(point))
    }

    private func setHovered(_ hovered: Bool) {
        background.layer?.backgroundColor = hovered ? NSColor.white.withAlphaComponent(0.09).cgColor : NSColor.clear.cgColor
        actionsStack.isHidden = !hovered
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open in Browser", action: #selector(handleOpenTap), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Copy Port", action: #selector(handleCopyPortTap), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Copy PID", action: #selector(handleCopyPIDTap), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Reveal in Finder", action: #selector(handleRevealTap), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: isPinned ? "Remove from Pinned" : "Add to Pinned", action: #selector(handleFavoriteTap), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let killItem = menu.addItem(withTitle: "Kill Process", action: #selector(handleKillTap), keyEquivalent: "")
        killItem.target = self
        return menu
    }

    @objc private func handleOpenTap() { onOpen?() }
    @objc private func handleCopyTap() { onCopy?() }
    @objc private func handleCopyPortTap() { onCopyPort?() }
    @objc private func handleCopyPIDTap() { onCopyPID?() }
    @objc private func handleKillTap() { onKill?() }
    @objc private func handleRevealTap() { onReveal?() }
    @objc private func handleFavoriteTap() { onToggleFavorite?() }
}

final class PaddedLabel: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEditable = false
        isBordered = false
        drawsBackground = false
        alignment = .center
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 10
        size.height += 4
        return size
    }
}

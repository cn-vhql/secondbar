import AppKit

/// One row of the manager: an app that can own menu bar items.
struct ManagedApp {
    /// The key this row toggles: the bundle id whose items get folded.
    let bundle: String
    let name: String
    /// What to show under the name. Usually the bundle id, but the input menu item's
    /// key belongs to an agent the user never heard of, so it shows its real id.
    let detail: String
    let icon: NSImage
    let isHidden: Bool
    /// False for an app that is not running, so its item cannot be seen right now.
    let isRunning: Bool
}

/// The window that manages which apps are folded into the second bar.
final class ManageWindow: NSObject {
    private var window: NSWindow?
    private var scroll = NSScrollView()
    // A scroll view's document view is laid out bottom-up unless it is flipped,
    // which would strand a short list at the bottom of the window.
    private let list = FlippedStackView()

    var onToggle: ((String, Bool) -> Void)?
    var onExpandAll: (() -> Void)?

    func show(apps: [ManagedApp], isExpanded: Bool) {
        let window = makeWindow()
        setApps(apps)
        self.isExpanded = isExpanded
        updateStateLabel()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func update(apps: [ManagedApp], isExpanded: Bool? = nil) {
        guard window != nil else { return }
        setApps(apps)
        if let isExpanded {
            self.isExpanded = isExpanded
            updateStateLabel()
        }
    }

    var isVisible: Bool { window?.isVisible ?? false }

    private func updateStateLabel() {
        expandStateLabel.stringValue = isExpanded
            ? "菜单栏当前全部展开；这里的开关仍然有效，收起后按开关执行"
            : "改动会立即生效；展开再收起也不会改变这里的设置"
    }

    private var isExpanded = false
    private let expandStateLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")

    private func makeWindow() -> NSWindow {
        if let window { return window }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
                             styleMask: [.titled, .closable, .resizable],
                             backing: .buffered,
                             defer: false)
        window.title = "SecondBar"
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("SecondBarManager")

        let root = BackgroundView()
        window.contentView = root

        let title = NSTextField(labelWithString: "第二个菜单栏")
        title.font = .systemFont(ofSize: 15, weight: .semibold)

        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor

        expandStateLabel.font = .systemFont(ofSize: 11)
        expandStateLabel.textColor = .secondaryLabelColor
        expandStateLabel.lineBreakMode = .byWordWrapping
        expandStateLabel.maximumNumberOfLines = 2

        let expandButton = NSButton(title: "展开全部图标…", target: self, action: #selector(expandAll))
        expandButton.bezelStyle = .rounded
        expandButton.controlSize = .small

        list.orientation = .vertical
        // In a vertical stack, .width pins both edges, so every row fills the list.
        list.alignment = .width
        list.spacing = 0
        list.translatesAutoresizingMaskIntoConstraints = false
        list.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)

        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = list
        list.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true

        let hint = NSTextField(labelWithString: "勾选的应用会被收进第二个菜单栏；系统项（时钟、Wi-Fi、控制中心等）无法收起。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 3

        let stack = NSStackView(views: [title, countLabel, expandStateLabel, expandButton, scroll, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(2, after: title)
        stack.setCustomSpacing(4, after: countLabel)
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            scroll.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            hint.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            expandButton.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
        ])

        self.window = window
        return window
    }

    private func setApps(_ apps: [ManagedApp]) {
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let hidden = apps.filter(\.isHidden).count
        countLabel.stringValue = "\(apps.count) 个可收起的应用，已收起 \(hidden) 个"

        guard !apps.isEmpty else {
            let empty = NSTextField(labelWithString: "还没有发现带菜单栏图标的第三方应用。")
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = .secondaryLabelColor
            list.addArrangedSubview(empty)
            return
        }

        for app in apps {
            list.addArrangedSubview(row(for: app))
        }
    }

    private func row(for app: ManagedApp) -> NSView {
        let holder = NSView()
        holder.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView(image: app.icon)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyUpOrDown

        let name = NSTextField(labelWithString: app.name)
        name.font = .systemFont(ofSize: 12)
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(labelWithString: app.isRunning ? app.detail : "\(app.detail)（未运行）")
        subtitle.font = .systemFont(ofSize: 10)
        subtitle.textColor = .tertiaryLabelColor
        subtitle.lineBreakMode = .byTruncatingMiddle
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        let toggle = NSSwitch()
        toggle.state = app.isHidden ? .on : .off
        toggle.controlSize = .small
        toggle.identifier = NSUserInterfaceItemIdentifier(app.bundle)
        toggle.target = self
        toggle.action = #selector(toggleChanged(_:))
        toggle.toolTip = app.isHidden ? "收进第二个菜单栏" : "显示在菜单栏"
        toggle.translatesAutoresizingMaskIntoConstraints = false

        for view in [icon, name, subtitle, toggle] { holder.addSubview(view) }
        NSLayoutConstraint.activate([
            holder.heightAnchor.constraint(equalToConstant: 44),
            icon.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 26),
            icon.heightAnchor.constraint(equalToConstant: 26),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            name.topAnchor.constraint(equalTo: holder.topAnchor, constant: 6),
            name.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -10),
            subtitle.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 1),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -10),
            toggle.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -6),
            toggle.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
        ])
        return holder
    }

    @objc private func toggleChanged(_ sender: NSSwitch) {
        guard let bundle = sender.identifier?.rawValue else { return }
        onToggle?(bundle, sender.state == .on)
    }

    @objc private func expandAll() {
        onExpandAll?()
    }
}

final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

/// Paints the window background itself, so an offscreen render is not transparent.
final class BackgroundView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}

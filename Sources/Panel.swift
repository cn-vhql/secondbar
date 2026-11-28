// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The SecondBar Authors

import AppKit

struct PanelEntry {
    let bundle: String
    let name: String
    let icon: NSImage
    /// Folded but not running: its row is drawn dimmed, because pressing it cannot
    /// open anything until the app is up.
    var isRunning: Bool = true
}

/// The drop-down second bar: a grid of the icons currently kept out of the menu
/// bar. Clicking one opens that app's own menu.
final class Panel: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let view = PanelView()
    private weak var button: NSStatusBarButton?
    private var outsideMonitor: Any?
    private var localMonitor: Any?
    /// When the panel last went away without this app asking for it (Escape, or the
    /// system dismissing a transient popover). A click on the arrow that closes the
    /// panel arrives as an action too, and without this the action would immediately
    /// reopen it, which reads as "the arrow does not toggle".
    private(set) var lastClosedBySystemAt: Date?
    /// Set by `close()` so a close this app asked for is never mistaken for one the
    /// system made: that distinction is what keeps fast repeated clicks honest.
    private var closeRequested = false

    var onPick: ((String, _ restore: Bool) -> Void)?
    var onClose: (() -> Void)?

    override init() {
        super.init()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        let controller = NSViewController()
        controller.view = view
        popover.contentViewController = controller
        view.onPick = { [weak self] bundle, restore in self?.onPick?(bundle, restore) }
    }

    var isShown: Bool { popover.isShown }

    var shownBundles: [String] { view.entries.map(\.bundle) }

    func show(entries: [PanelEntry], relativeTo button: NSStatusBarButton) {
        self.button = button
        view.entries = entries
        popover.contentSize = view.fittingSize
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // A LSUIElement app never becomes active on its own, so NSPopover's own
        // "click outside to dismiss" does not reliably fire. Watch for the click.
        watchOutsideClicks()
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.popover.contentViewController?.view.window else { return }
            Log.write("panel shown frame=\(window.frame) entries=\(entries.count)")
        }
    }

    /// Replaces the contents while the panel is open, without moving it.
    func update(entries: [PanelEntry]) {
        guard popover.isShown else { return }
        view.entries = entries
        popover.contentSize = view.fittingSize
    }

    func close() {
        closeRequested = true
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        lastClosedBySystemAt = closeRequested ? nil : Date()
        closeRequested = false
        stopWatchingOutsideClicks()
        onClose?()
    }

    /// Consumed by the arrow's action when it was the click that closed the panel.
    func clearLastClosedBySystem() {
        lastClosedBySystemAt = nil
    }

    private func watchOutsideClicks() {
        stopWatchingOutsideClicks()
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.closeIfClickIsOutside() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.closeIfClickIsOutside()
            return event
        }
    }

    private func stopWatchingOutsideClicks() {
        if let monitor = outsideMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
        outsideMonitor = nil
        localMonitor = nil
    }

    private func closeIfClickIsOutside() {
        guard popover.isShown else { return }
        let point = NSEvent.mouseLocation
        if let window = popover.contentViewController?.view.window, window.frame.contains(point) { return }
        // The arrow itself toggles through its action; closing here as well would
        // close and reopen in one click.
        if let button, let window = button.window,
           window.convertToScreen(button.convert(button.bounds, to: nil)).contains(point) { return }
        close()
    }
}

final class PanelView: NSView {
    var onPick: ((String, _ restore: Bool) -> Void)?

    var entries: [PanelEntry] = [] {
        didSet { rebuild() }
    }

    private let grid = NSStackView()
    private static let columns = 6
    private static let cell: CGFloat = 40

    override init(frame: NSRect) {
        super.init(frame: frame)
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.spacing = 2
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            grid.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            grid.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        // `rebuild` pads every row out to `columns` cells, so the panel is always
        // that wide — sizing it to the number of entries clipped the odd short row.
        let count = max(entries.count, 1)
        let columns = entries.isEmpty ? 1 : Self.columns
        let rows = max(1, Int(ceil(Double(count) / Double(Self.columns))))
        let spacing = Self.cell + 2
        return NSSize(width: CGFloat(columns) * spacing + 18,
                      height: CGFloat(rows) * spacing + 18)
    }

    private func rebuild() {
        grid.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard !entries.isEmpty else {
            let label = NSTextField(labelWithString: "菜单栏里没有收起的图标")
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false
            let holder = NSView()
            holder.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 4),
                label.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
                holder.heightAnchor.constraint(equalToConstant: Self.cell),
                holder.widthAnchor.constraint(equalToConstant: 160),
            ])
            grid.addArrangedSubview(holder)
            invalidateIntrinsicContentSize()
            return
        }

        for chunk in entries.chunked(into: Self.columns) {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 2
            for entry in chunk { row.addArrangedSubview(button(for: entry)) }
            for _ in chunk.count..<Self.columns { row.addArrangedSubview(filler()) }
            grid.addArrangedSubview(row)
        }
        invalidateIntrinsicContentSize()
    }

    private func filler() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: Self.cell),
            view.heightAnchor.constraint(equalToConstant: Self.cell),
        ])
        return view
    }

    private func button(for entry: PanelEntry) -> NSButton {
        let button = NSButton()
        button.image = entry.icon
        button.imageScaling = .scaleProportionallyDown
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.target = self
        button.action = #selector(pick(_:))
        button.identifier = NSUserInterfaceItemIdentifier(entry.bundle)
        button.toolTip = entry.isRunning ? entry.name : "\(entry.name)（未运行，点一下启动）"
        button.alphaValue = entry.isRunning ? 1 : 0.45
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Self.cell),
            button.heightAnchor.constraint(equalToConstant: Self.cell),
        ])
        return button
    }

    @objc private func pick(_ sender: NSButton) {
        guard let bundle = sender.identifier?.rawValue else { return }
        // Option-click asks for the icon itself, not its menu.
        let restore = NSApp.currentEvent?.modifierFlags.contains(.option) ?? false
        onPick?(bundle, restore)
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

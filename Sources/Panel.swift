// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The SecondBar Authors

import AppKit

struct PanelEntry {
    let bundle: String
    let name: String
    let icon: NSImage
}

/// The drop-down second bar: a grid of the icons currently kept out of the menu
/// bar. Clicking one opens that app's own menu.
final class Panel: NSObject {
    private let popover = NSPopover()
    private let view = PanelView()

    var onPick: ((String, _ restore: Bool) -> Void)?

    override init() {
        super.init()
        popover.behavior = .transient
        popover.animates = false
        let controller = NSViewController()
        controller.view = view
        popover.contentViewController = controller
        view.onPick = { [weak self] bundle, restore in self?.onPick?(bundle, restore) }
    }

    var isShown: Bool { popover.isShown }

    func show(entries: [PanelEntry], relativeTo button: NSStatusBarButton) {
        view.entries = entries
        popover.contentSize = view.fittingSize
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.popover.contentViewController?.view.window else { return }
            Log.write("panel shown frame=\(window.frame) entries=\(entries.count)")
        }
    }

    func close() {
        popover.performClose(nil)
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
        let count = max(entries.count, 1)
        let columns = min(count, Self.columns)
        let rows = max(1, Int(ceil(Double(count) / Double(Self.columns))))
        return NSSize(width: CGFloat(columns) * Self.cell + 20,
                      height: CGFloat(rows) * Self.cell + 20)
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
        button.toolTip = entry.name
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

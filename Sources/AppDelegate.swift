// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The SecondBar Authors

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let sections = Sections()
    private let hiding = Hiding()
    private let panel = Panel()
    private let manager = ManageWindow()

    /// Apps let through for the moment so their own menu can open.
    private var temporary: [String] = []
    private var releaseTimer: Timer?
    /// Bumped by every `open`, so a stale wait chain (which cannot be cancelled: it
    /// is a chain of asyncAfter hops) stops instead of pressing the wrong icon.
    private var openGeneration = 0
    private var trustTimer: Timer?
    private var isExpanded = false
    /// Last successfully read second-bar contents. The panel opens from this, so a
    /// click shows it immediately instead of after a full Accessibility walk.
    private var cachedEntries: [PanelEntry] = []
    private var entriesGeneration = 0

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.arrow(expanded: false)
            button.imagePosition = .imageOnly
            button.toolTip = "第二个菜单栏（左点查看收起的图标，右键菜单）"
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        // Record where the arrow landed, before anything is hidden.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.updateArrow() }

        panel.onPick = { [weak self] bundle, restore in
            if restore {
                self?.restore(bundle: bundle)
            } else {
                self?.open(bundle: bundle)
            }
        }
        panel.onClose = { Log.write("panel closed") }

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(
                self, selector: #selector(appsChanged), name: name, object: nil)
        }

        guard Hiding.isAvailable else {
            Log.write("launch: MenuBarClientCore unavailable")
            alert("这台 Mac 上的菜单栏隐藏接口不可用（需要 macOS 27）。")
            return
        }
        Log.write("launch: hiding available, trusted=\(AXReader.isTrusted), "
            + "cached \(sections.hidden.count) hidden of \(sections.visible.count + sections.hidden.count)")
        startDebugChannelIfEnabled()
        startWhenTrusted()
    }

    /// Accessibility can only be granted in System Settings, and granting it does
    /// not relaunch us, so poll until it lands and only then touch the bar.
    private func startWhenTrusted() {
        guard !AXReader.isTrusted else {
            start()
            return
        }
        statusItem.button?.toolTip = "SecondBar 需要「辅助功能」权限才能读取并收起菜单栏图标"
        AXReader.requestTrust()
        guard trustTimer == nil else { return }
        var ticks = 0
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            ticks += 1
            if AXReader.isTrusted {
                timer.invalidate()
                self.trustTimer = nil
                self.statusItem.button?.toolTip = "第二个菜单栏（左点查看收起的图标，右键菜单）"
                Log.write("trust granted after \(ticks)s")
                self.start()
            } else if ticks % 60 == 0 {
                Log.write("still waiting for Accessibility (\(ticks)s)")
            }
        }
        trustTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func start() {
        if sections.hidden.isEmpty && sections.visible.isEmpty {
            // Nothing arranged yet. The bar is complete right now, so this is the
            // only moment positions can be read; afterwards the arrangement is
            // whatever the manager window says.
            Log.write("start: no arrangement yet, reading the current layout once")
            let items = AXReader.items()
            sections.refresh(items: items, dividerX: dividerX)
            cachedEntries = makeEntries(from: items)
            Log.write("start: adopted \(sections.hidden.count) folded, \(sections.visible.count) visible")
            expand(hint: true)
        } else {
            applyHiding()
            // Warm the cache so the first click does not show an empty panel.
            refreshEntries(showing: false)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        releaseTimer?.invalidate()
        trustTimer?.invalidate()
        // Also lifted by process exit, but explicit is cleaner: the bar comes back
        // even if this app is killed while collapsed.
        hiding.release()
    }

    // MARK: - Acting on the bar

    /// Our own item's mid-x in screen coordinates, used as the divider: whatever
    /// sits left of the arrow belongs to the second bar. Read from the button, not
    /// its window, because macOS 27 draws the whole menu bar in one window.
    private var dividerX: CGFloat {
        // 0 rather than infinity: if the arrow has no button yet, nothing sits left
        // of it, so a read must fold nothing instead of folding the whole bar.
        guard let button = statusItem.button, let window = button.window else { return 0 }
        return window.convertToScreen(button.convert(button.bounds, to: nil)).midX
    }

    /// Applies the cached arrangement. Nothing is re-read, so the bar does not
    /// flash: only the arrow's left-hand side disappears.
    private func applyHiding() {
        guard !isExpanded else { return }
        // Anything not known to be in the second bar stays visible, so an app that
        // started after the last read is not hidden by surprise.
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let allowed = running.subtracting(sections.hidden).union(temporary)
        hiding.hold(bundles: Array(allowed)) { [weak self] ok in
            guard let self else { return }
            if !ok {
                self.alert("无法隐藏菜单栏图标，macOS 拒绝了这次请求。")
            } else {
                Log.write("holding: \(allowed.count) allowed, \(self.sections.hidden.count) in second bar")
            }
        }
    }

    /// Shows every icon. Nothing is read here: the arrangement comes from the
    /// manager window, and reading positions on the way back in re-decided it.
    private func expand(hint: Bool = false) {
        releaseTimer?.invalidate()
        temporary = []
        hiding.release()
        isExpanded = true
        updateArrow()
        refreshManager()
        if hint {
            statusItem.button?.toolTip = "⌥ 单击箭头，在管理窗口里选择要收起的应用"
        }
    }

    /// Reapplies the saved arrangement and reads nothing. Inferring the layout from
    /// positions was the source of two bugs: the arrow shifts when the bar reflows,
    /// and an icon sitting near the divider flips sides on every pass, so apps the
    /// user had just kept visible kept getting folded again.
    private func collapse() {
        isExpanded = false
        temporary = []
        updateArrow()
        applyHiding()
        refreshManager()
        refreshEntries(showing: false)
        Log.write("collapsed: \(sections.hidden.count) hidden, \(sections.visible.count) visible")
        if sections.hidden.isEmpty {
            Log.write("warning: nothing is folded yet")
        }
    }

    private func updateArrow() {
        statusItem.button?.image = Self.arrow(expanded: isExpanded)
        // The arrow moves whenever the allow list changes the bar's layout, so
        // its screen rect is recorded for the self-test.
        if let button = statusItem.button, let window = button.window {
            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
            let top = (NSScreen.screens.first?.frame.maxY ?? rect.maxY) - rect.maxY
            Log.write("arrow at \(Int(rect.midX)),\(Int(top + rect.height / 2)) "
                + "rect=\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))x\(Int(rect.height))")
        }
    }

    // MARK: - Second bar

    /// Builds the panel rows. The rows come from the folded set, not from the item
    /// list: a folded app belongs in the second bar whether or not macOS will talk
    /// about its item right now. Measured on macOS 27, `AXExtrasMenuBar` answers
    /// `cannotComplete` (-25212) for some apps exactly while their item is folded
    /// (QQ, WireGuard, CC Switch), so deriving rows from the read made a folded app
    /// that was launched after folding simply not appear.
    ///
    /// The item list is only used to name and draw a row that does have one.
    private func makeEntries(from items: [BarItem]) -> [PanelEntry] {
        var firstItem: [String: BarItem] = [:]
        for item in items {
            guard let bundle = item.bundle, firstItem[bundle] == nil else { continue }
            firstItem[bundle] = item
        }
        return sections.hidden.map { bundle -> PanelEntry in
            let item = firstItem[bundle]
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first
            let pid = item?.pid ?? running?.processIdentifier
            return PanelEntry(bundle: bundle,
                              name: Self.displayName(for: bundle, pid: pid, item: item),
                              icon: Self.icon(for: bundle, pid: pid),
                              isRunning: running != nil)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Reads the bar in the background and updates the cache. `showing` means the
    /// panel is already up and should be refreshed in place once the read lands.
    private func refreshEntries(showing: Bool) {
        entriesGeneration += 1
        let generation = entriesGeneration
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let items = AXReader.items()
            DispatchQueue.main.async {
                guard let self, generation == self.entriesGeneration else { return }
                self.cachedEntries = self.makeEntries(from: items)
                if showing, self.panel.isShown { self.panel.update(entries: self.cachedEntries) }
            }
        }
    }

    /// Opens the panel from the cache and corrects it once the background read lands.
    private func showPanel() {
        guard let button = statusItem.button else { return }
        panel.show(entries: cachedEntries, relativeTo: button)
        refreshEntries(showing: true)
    }

    /// The input menu item belongs to `TextInputMenuAgent`, whose own icon is a generic
    /// placeholder and whose own name is "TextInputMenuAgent"; both belong to the
    /// current input source instead. Shared by the second bar and the manager so the
    /// two never disagree about what that entry looks like.
    private static func inputSourceOverride(for bundle: String) -> InputSource.Current? {
        bundle == InputSource.agentBundle ? InputSource.current() : nil
    }

    /// A running app's own icon, else the icon of its bundle on disk: an app that is
    /// folded but not running (or whose items are owned by a helper) still has one.
    private static func icon(for bundle: String, pid: pid_t?) -> NSImage {
        if let current = inputSourceOverride(for: bundle), current.icon.size != .zero {
            return current.icon
        }
        if let running = pid.flatMap({ NSRunningApplication(processIdentifier: $0) }),
           let icon = running.icon {
            return icon
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return fallbackIcon
    }

    /// The row's key is the agent's bundle id, which means nothing to the user; show
    /// the input method's own id instead.
    private static func detail(for bundle: String) -> String {
        if bundle == InputSource.agentBundle, let real = InputSource.current()?.bundle { return real }
        return bundle
    }

    private static func displayName(for bundle: String, pid: pid_t?, item: BarItem? = nil) -> String {
        if let current = inputSourceOverride(for: bundle) { return current.name }
        if let owner = item?.ownerName { return owner }
        if let running = pid.flatMap({ NSRunningApplication(processIdentifier: $0) }) {
            if let name = running.localizedName { return name }
        }
        return prettyName(for: bundle)
    }

    private static var fallbackIcon: NSImage {
        NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: 20, height: 20))
    }

    // MARK: - Managing

    /// Every app that can own a menu bar item, with the one we know of even when it
    /// is not running. Running apps come first, then the ones already folded.
    private func managedApps() -> [ManagedApp] {
        var apps: [String: ManagedApp] = [:]
        for bundle in sections.hidden.union(sections.visible) {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first
            apps[bundle] = ManagedApp(bundle: bundle,
                                      name: Self.displayName(for: bundle, pid: running?.processIdentifier),
                                      detail: Self.detail(for: bundle),
                                      icon: Self.icon(for: bundle, pid: running?.processIdentifier),
                                      isHidden: sections.hidden.contains(bundle),
                                      isRunning: running != nil)
        }
        // Running apps that own a status item but were never arranged: before the
        // first read they are not in either section yet.
        for item in AXReader.items() {
            guard let bundle = item.bundle, apps[bundle] == nil else { continue }
            apps[bundle] = ManagedApp(bundle: bundle,
                                      name: Self.displayName(for: bundle, pid: item.pid, item: item),
                                      detail: Self.detail(for: bundle),
                                      icon: Self.icon(for: bundle, pid: item.pid),
                                      isHidden: sections.hidden.contains(bundle),
                                      isRunning: true)
        }
        // By name only, so flipping a switch does not move the row the user just
        // clicked: folding is what the switch shows, not where the row sits.
        return apps.values.sorted { lhs, rhs in
            let order = lhs.name.localizedStandardCompare(rhs.name)
            return order == .orderedSame ? lhs.bundle < rhs.bundle : order == .orderedAscending
        }
    }

    private static func prettyName(for bundle: String) -> String {
        // A not-running app still has a bundle on disk most of the time.
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            let name = FileManager.default.displayName(atPath: url.path)
            return (name as NSString).deletingPathExtension
        }
        return (bundle as NSString).pathExtension.isEmpty
            ? bundle
            : bundle.components(separatedBy: ".").last ?? bundle
    }

    private func showManager() {
        manager.onToggle = { [weak self] bundle, hidden in
            guard let self else { return }
            self.sections.setHidden(bundle, hidden)
            self.applyHiding()
            self.manager.update(apps: self.managedApps())
            Log.write("manager: \(bundle) \(hidden ? "folded" : "unfolded")")
        }
        manager.onExpandAll = { [weak self] in
            self?.expand()
            self?.refreshManager()
        }
        manager.show(apps: managedApps(), isExpanded: isExpanded)
    }

    /// Keeps the editor in step with the arrow. The manager is the only input to the
    /// arrangement, so this only ever pushes state one way.
    private func refreshManager() {
        guard manager.isVisible else { return }
        manager.update(apps: managedApps(), isExpanded: isExpanded)
    }

    /// Flips one app between the two sections, the same as its switch does.
    private func toggle(bundle: String) {
        sections.setHidden(bundle, !sections.hidden.contains(bundle))
        applyHiding()
        refreshManager()
        Log.write("toggled \(bundle) -> \(sections.hidden.contains(bundle) ? "folded" : "shown")")
    }

    /// Option-click in the second bar: put the icon back in the menu bar for good.
    private func restore(bundle: String) {
        panel.close()
        sections.setHidden(bundle, false)
        cachedEntries.removeAll { $0.bundle == bundle }
        applyHiding()
        refreshManager()
        Log.write("restored \(bundle) to the menu bar")
    }

    /// Opens one app's own menu from the second bar. A hidden item has no usable
    /// position, so the app is let back in, pressed, and collected again once its
    /// menu closes.
    private func open(bundle: String) {
        Log.write("open: \(bundle) requested from the second bar")
        panel.close()
        // Folded but not running: there is no item to press and no menu to open, so
        // this is a launch. The app is let back into the bar while it starts up and
        // folds again on the next applyHiding, once it owns an item.
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty {
            launch(bundle: bundle)
            return
        }
        // Clicking a second icon while the first is still being watched must not
        // leave the first watcher running: it would clear `temporary` in the middle
        // of the second open, folding the icon that is about to be pressed.
        releaseTimer?.invalidate()
        releaseTimer = nil
        openGeneration += 1
        // A hidden item keeps a stale AX element: pressing it reports success and
        // does nothing. The app has to be let back into the bar first, and macOS
        // needs a variable moment to reflow, so the item is polled for rather than
        // waited on for a fixed time.
        temporary = [bundle]
        applyHiding()
        waitForItem(of: bundle, attempt: 0, generation: openGeneration)
    }

    /// Polls for the app's item to exist in the bar, then presses it.
    private func waitForItem(of bundle: String, attempt: Int, generation: Int) {
        // A newer open superseded this one: leave its icon alone, the newer request
        // owns `temporary` now.
        guard generation == openGeneration else {
            Log.write("open: dropped stale wait for \(bundle)")
            return
        }
        let target = AXReader.items().first { $0.bundle == bundle && AXReader.isInMenuBar($0.frame) }
        if let target, let element = target.element {
            let anchors = menuAnchors(for: bundle)
            switch AXReader.press(element) {
            case .pressed, .menuTracking:
                // Start watching before returning: a press that opens a menu blocks
                // the app's AX queue, so the menu may already be up by now.
                Log.write("open: pressed \(bundle) at \(target.frame) (attempt \(attempt))")
                waitForMenuClose(of: bundle, anchors: anchors, generation: generation)
            case .unsupported, .unreachable:
                // No element accepted a press. A synthetic click is not an option:
                // measured on macOS 27, CGEvent at every tap location moves the
                // pointer but never opens another app's status item menu. The watch
                // below therefore ends in `fallback`, which brings the app forward.
                Log.write("open: \(bundle) exposes no press action (\(target.frame))")
                waitForMenuClose(of: bundle, anchors: anchors, generation: generation)
            }
            return
        }
        guard attempt < 14 else {
            Log.write("open: gave up waiting for \(bundle) to appear in the bar")
            temporary = []
            applyHiding()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.waitForItem(of: bundle, attempt: attempt + 1, generation: generation)
        }
    }

    /// Polls until the app's menu is gone, then puts its icon back in the second
    /// bar. A menu that was already open before the press is ignored, so a stale
    /// window cannot pin the icon in the bar forever.
    private func waitForMenuClose(of bundle: String, anchors: Set<String>, generation: Int) {
        let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: bundle).map(\.processIdentifier))
        var sawChange = false
        var ticks = 0
        releaseTimer?.invalidate()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] timer in
            guard let self, generation == self.openGeneration else {
                timer.invalidate()
                return
            }
            ticks += 1
            let current = self.menuAnchors(forPids: pids)
            let opened = !current.subtracting(anchors).isEmpty
            if opened { sawChange = true }
            let closedAgain = sawChange && current.subtracting(anchors).isEmpty
            // Some apps ignore AXPress on their status item (measured on
            // macOS 27: WeChat, QQ, Control Center extras, CC Switch report success
            // and open nothing; WireGuard, UURemote, Lumen work). After ~1s of
            // nothing, fall back to bringing the app itself forward so the click
            // still does something useful.
            if !sawChange && ticks == 5 {
                self.fallback(for: bundle)
            }
            // Nothing opened at all: give up after ~3s rather than holding the icon
            // in the bar forever.
            let settled = sawChange ? closedAgain : ticks > 15
            guard settled else { return }
            timer.invalidate()
            self.temporary = []
            self.applyHiding()
            Log.write("open: \(bundle) done after \(ticks) ticks, menu seen: \(sawChange)")
        }
        releaseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Starts a folded app that is not running, so its icon in the second bar does
    /// something useful instead of nothing.
    private func launch(bundle: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
            Log.write("launch: \(bundle) has no bundle on disk")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] app, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    Log.write("launch: \(bundle) failed: \(error.localizedDescription)")
                    return
                }
                Log.write("launch: started \(bundle) (pid \(app?.processIdentifier ?? 0))")
                self.refreshEntries(showing: false)
            }
        }
    }

    /// The app's status item accepted the press but opened no menu.
    private func fallback(for bundle: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else { return }
        Log.write("open: \(bundle) opened no menu, activating the app instead")
        app.activate()
    }

    /// Identity of the app's menu-level windows right now: one entry per window, so
    /// a second menu opening is distinguishable from the first still being up.
    private func menuAnchors(forPids pids: Set<pid_t>) -> Set<String> {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return Set(windows.compactMap { window -> String? in
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                  let layer = window[kCGWindowLayer as String] as? Int, layer >= 101,
                  let number = window[kCGWindowNumber as String] as? Int else { return nil }
            return "\(number)"
        })
    }

    private func menuAnchors(for bundle: String) -> Set<String> {
        menuAnchors(forPids: Set(NSRunningApplication.runningApplications(withBundleIdentifier: bundle)
            .map(\.processIdentifier)))
    }

    // MARK: - Events

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        Log.write("status item clicked, expanded=\(isExpanded) panelShown=\(panel.isShown) "
            + "option=\(modifiers.contains(.option)) right=\(NSApp.currentEvent?.type == .rightMouseUp)")
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else if modifiers.contains(.option) {
            showManager()
        } else {
            arrowClicked()
        }
    }

    /// Minimal, opt-in command channel used to drive the app deterministically in
    /// tests: `SECOND_BAR_DEBUG=1 SECOND_BAR_DEBUG_FILE=/tmp/cmd` turns lines in that
    /// file into commands (open:<bundle>, toggle:<bundle>, collapse, expand, panel,
    /// manager). With the environment variable unset it does nothing.
    private func startDebugChannelIfEnabled() {
        guard ProcessInfo.processInfo.environment["SECOND_BAR_DEBUG"] == "1" else { return }
        let path = ProcessInfo.processInfo.environment["SECOND_BAR_DEBUG_FILE"]
            ?? NSTemporaryDirectory() + "secondbar-commands"
        try? "".write(toFile: path, atomically: true, encoding: .utf8)
        Log.write("debug channel on \(path)")
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self,
                  let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
            let lines = text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
            guard !lines.isEmpty else { return }
            try? "".write(toFile: path, atomically: true, encoding: .utf8)
            for line in lines { self.run(command: line) }
        }
    }

    private func run(command: String) {
        Log.write("debug command: \(command)")
        let parts = command.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts.first {
        case "open": if parts.count > 1 { open(bundle: parts[1]) }
        case "toggle": if parts.count > 1 { toggle(bundle: parts[1]) }
        case "restore": if parts.count > 1 { restore(bundle: parts[1]) }
        case "collapse": collapse()
        case "expand": expand()
        case "panel": showPanel()
        case "close": panel.close()
        case "manager": showManager()
        default: Log.write("  unknown command")
        }
    }

    private func arrowClicked() {
        guard AXReader.isTrusted else {
            AXReader.requestTrust()
            return
        }
        if isExpanded {
            collapse()
            return
        }
        if panel.isShown {
            panel.close()
            return
        }
        // A panel dismissed by the system can close on the mouse-down of this very
        // click, and the action then arrives on mouse-up with the panel already gone;
        // without this the arrow would close and reopen in one click instead of
        // toggling. Never true for a click that closed it from this app's own monitor.
        if let closedAt = panel.lastClosedBySystemAt, Date().timeIntervalSince(closedAt) < 0.4 {
            panel.clearLastClosedBySystem()
            return
        }
        showPanel()
    }

    @objc private func screensChanged() {
        guard !isExpanded else { return }
        // Sections are per app, so a display change only needs the restriction
        // re-applied, not re-read.
        applyHiding()
    }

    @objc private func appsChanged() {
        guard !isExpanded else { return }
        applyHiding()
    }

    // MARK: - Menu

    private func showMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let title = sections.hidden.isEmpty
            ? "第二个菜单栏里还没有图标"
            : "第二个菜单栏：\(sections.hidden.count) 个应用"
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(item(isExpanded ? "收起" : "展开全部图标", #selector(toggleExpand)))
        menu.addItem(item("管理收起的应用…", #selector(manage)))
        let login = item(LoginItem.isEnabled ? "关闭开机启动" : "开机启动", #selector(toggleLoginItem))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(item("辅助功能权限…", #selector(openAccessibilitySettings)))
        menu.addItem(.separator())
        menu.addItem(item("退出", #selector(quit)))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func manage() {
        showManager()
    }

    @objc private func toggleExpand() {
        if isExpanded { collapse() } else { expand() }
    }

    @objc private func toggleLoginItem() {
        let enable = !LoginItem.isEnabled
        if let failure = LoginItem.setEnabled(enable) {
            alert(failure)
        }
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private static func arrow(expanded: Bool) -> NSImage? {
        let name = expanded ? "chevron.left.2" : "chevron.right.2"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: expanded ? "菜单栏已展开" : "第二个菜单栏")
        image?.isTemplate = true
        return image
    }

    private func alert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "SecondBar"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

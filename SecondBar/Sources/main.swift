import AppKit

// `SecondBar --show-ui` opens the manager on screen with sample rows, for a real
// screenshot of live controls (an offscreen render cannot show an NSSwitch state).
if CommandLine.arguments.contains("--show-ui") {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.regular)
    let manager = ManageWindow()
    manager.show(apps: SampleApps.all, isExpanded: false)
    NSApp.activate(ignoringOtherApps: true)
    if let frame = NSApp.windows.first?.frame {
        let screenHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let top = screenHeight - frame.maxY
        print("R \(Int(frame.origin.x)),\(Int(top)),\(Int(frame.width)),\(Int(frame.height))")
        fflush(stdout)
    }
    NSApp.run()
}

// `SecondBar --probe-press <bundle>`: can an already hidden icon be pressed
// through Accessibility, without letting it back into the bar first?
if let index = CommandLine.arguments.firstIndex(of: "--probe-press"),
   CommandLine.arguments.count > index + 1 {
    _ = NSApplication.shared
    let bundle = CommandLine.arguments[index + 1]
    let items = AXReader.items()
    for item in items where item.bundle == bundle {
        let pressable = item.element.map { element in
            ([element] + AXReader.children(element)).contains { AXReader.actions(of: $0).contains(kAXPressAction as String) }
        } ?? false
        print("item bundle=\(item.bundle ?? "-") frame=\(item.frame) pressable=\(pressable) inBar=\(AXReader.isInMenuBar(item.frame))")
    }
    let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: bundle).map(\.processIdentifier))
    print("before: menuOpen=\(AXReader.hasOpenMenu(pids: pids))")
    if CommandLine.arguments.contains("--press") {
        if let element = items.first(where: { $0.bundle == bundle })?.element {
            print("press result=\(AXReader.press(element))")
        }
        usleep(900_000)
        print("after: menuOpen=\(AXReader.hasOpenMenu(pids: pids))")
    }
    exit(0)
}

// `SecondBar --dump-ui <path>` renders the manager window to a PNG and exits, so
// the layout can be checked without taking a screenshot (which on this macOS
// needs Screen Recording). It never touches the real menu bar.
if let index = CommandLine.arguments.firstIndex(of: "--dump-ui"),
   CommandLine.arguments.count > index + 1 {
    let path = CommandLine.arguments[index + 1]
    // NSApp only exists once the shared application has been created.
    _ = NSApplication.shared

    let sample = SampleApps.all
    // Offscreen rendering has no window server to pick an appearance from, so the
    // colours must be the light ones explicitly.
    NSApp.appearance = NSAppearance(named: .aqua)
    let manager = ManageWindow()
    manager.show(apps: sample, isExpanded: false)
    if let window = NSApp.windows.first, let view = window.contentView {
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            print("cannot cache display")
            exit(1)
        }
        view.cacheDisplay(in: bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        print("wrote \(path) (\(Int(bounds.width))x\(Int(bounds.height))pt)")
    } else {
        print("no window")
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

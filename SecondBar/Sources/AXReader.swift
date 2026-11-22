import AppKit
import ApplicationServices

// One status item belonging to some app, as read through the Accessibility API.
struct BarItem {
    let pid: pid_t
    let bundle: String?
    let ownerName: String?
    let frame: CGRect      // Accessibility coordinates: origin at the top-left
    let element: AXUIElement?

    var midX: CGFloat { frame.midX }
}

enum AXReader {
    // Apps that hang would otherwise stall the whole walk; the default timeout is
    // several seconds per app.
    private static let timeout: Float = 0.15
    private static let retryTimeout: Float = 0.6

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private struct Candidate {
        let pid: pid_t
        let bundle: String?
        let name: String?
    }

    /// Every status item owned by another app. Needs the Accessibility permission.
    static func items() -> [BarItem] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let candidates: [Candidate] = NSWorkspace.shared.runningApplications
            .filter {
                $0.processIdentifier != ownPID
                    && !$0.isTerminated
                    && !["xpc", "appex"].contains($0.bundleURL?.pathExtension ?? "")
            }
            .map { Candidate(pid: $0.processIdentifier, bundle: $0.bundleIdentifier, name: $0.localizedName) }

        var results = [[BarItem]?](repeating: nil, count: candidates.count)
        let lock = NSLock()

        func pass(_ indices: [Int], _ limit: Float) {
            DispatchQueue.concurrentPerform(iterations: indices.count) { position in
                let index = indices[position]
                guard let read = read(candidates[index], timeout: limit) else { return }
                lock.lock()
                results[index] = read
                lock.unlock()
            }
        }

        pass(Array(candidates.indices), timeout)
        // A busy app can miss the short timeout under concurrent load; give it one
        // more, slower chance so its items are not silently dropped.
        let missing = candidates.indices.filter { results[$0] == nil }
        if !missing.isEmpty { pass(missing, retryTimeout) }

        return candidates.indices.compactMap { results[$0] }.flatMap { $0 }
    }

    // nil means "this app did not answer", which callers treat as "keep it
    // visible" rather than "hide it".
    private static func read(_ app: Candidate, timeout: Float) -> [BarItem]? {
        let element = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(element, timeout)
        guard let bar = value(element, "AXExtrasMenuBar"), CFGetTypeID(bar) == AXUIElementGetTypeID() else {
            // Either no status items, or the app answers nothing at all. Both are
            // "nothing to hide".
            return []
        }
        let children = self.children(bar as! AXUIElement)
        return children.map { child in
            BarItem(pid: app.pid,
                    bundle: app.bundle,
                    ownerName: app.name,
                    frame: frame(of: child) ?? .zero,
                    element: child)
        }
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = value(element, kAXPositionAttribute),
              let sizeValue = value(element, kAXSizeAttribute),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }

    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        return value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    static func actions(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return names as? [String] ?? []
    }

    enum PressResult {
        /// The action returned success.
        case pressed
        /// The app went into menu tracking, so the call cannot complete until the
        /// menu closes. A menu is almost certainly open.
        case menuTracking
        /// No element in the item accepted a press.
        case unsupported
        /// The app did not answer at all.
        case unreachable
    }

    /// Presses a status item so its own menu opens. The item may be the press
    /// target itself or host it.
    static func press(_ element: AXUIElement) -> PressResult {
        var sawTarget = false
        for target in [element] + children(element) where actions(of: target).contains(kAXPressAction as String) {
            sawTarget = true
            let error = AXUIElementPerformAction(target, kAXPressAction as CFString)
            switch error {
            case .success: return .pressed
            // Menu tracking is modal: the app stops answering AX calls, which is
            // reported as cannotComplete, and that is the success case for us.
            case .cannotComplete: return .menuTracking
            case .invalidUIElement, .failure: continue
            default: continue
            }
        }
        return sawTarget ? .unsupported : .unreachable
    }

    static func moveMouse(to point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    /// Clicks a point in Accessibility coordinates. Some status items draw
    /// themselves and expose no press action, so a real click is the only way in.
    static func click(at point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                      mouseCursorPosition: point, mouseButton: .left) else { continue }
            event.post(tap: .cghidEventTap)
            usleep(40_000)
        }
    }

    /// True while any of `pids` has a window at menu level, i.e. its menu is up.
    static func hasOpenMenu(pids: Set<pid_t>) -> Bool {
        guard !pids.isEmpty,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        return windows.contains { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                  let layer = window[kCGWindowLayer as String] as? Int else { return false }
            return layer >= 101 // NSPopUpMenuWindowLevel
        }
    }

    /// Whether an Accessibility frame sits in some screen's menu bar strip. A
    /// hidden item reports a stale or zero frame, which counts as "not there".
    static func isInMenuBar(_ frame: CGRect) -> Bool {
        guard frame != .zero else { return false }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        return menuBarBands().contains { band in band.contains(point) }
    }

    /// the strip of each screen where the menu bar is, in Accessibility coordinates
    static func menuBarBands() -> [CGRect] {
        guard let primaryHeight = NSScreen.screens.first?.frame.maxY else { return [] }
        return NSScreen.screens.map { screen in
            let height = max(screen.frame.maxY - screen.visibleFrame.maxY,
                             screen.safeAreaInsets.top,
                             NSStatusBar.system.thickness)
            return CGRect(x: screen.frame.minX,
                          y: primaryHeight - screen.frame.maxY,
                          width: screen.frame.width,
                          height: height + 2)
        }
    }
}

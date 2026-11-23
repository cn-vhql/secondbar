// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The SecondBar Authors

import AppKit

/// Which status items live in the second bar. macOS 27 can only hide a whole app's
/// items, so this is stored per bundle identifier and decided by the manager
/// window. Positions in the bar are deliberately not used: the arrow moves when the
/// bar reflows, so a position read would keep re-deciding what the user already set.
final class Sections {
    private static var hiddenKey: String { "hiddenBundles" }
    private static var knownKey: String { "knownBundles" }
    private static var shownKey: String { "shownBundles" }

    private(set) var hidden: Set<String>
    private(set) var visible: Set<String>
    /// Apps the user explicitly asked to keep in the menu bar. A position re-read
    /// must not undo this: an app's item sits left of the arrow by default, so
    /// reading positions alone would fold it back in on the next collapse.
    private(set) var shownByUser: Set<String>

    init() {
        let defaults = UserDefaults.standard
        hidden = Set(defaults.stringArray(forKey: Self.hiddenKey) ?? [])
        visible = Set(defaults.stringArray(forKey: Self.knownKey) ?? []).subtracting(hidden)
        shownByUser = Set(defaults.stringArray(forKey: Self.shownKey) ?? [])
        hidden.subtract(shownByUser)
        visible.formUnion(shownByUser)
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(Array(hidden).sorted(), forKey: Self.hiddenKey)
        defaults.set(Array(visible).sorted(), forKey: Self.knownKey)
        defaults.set(Array(shownByUser).sorted(), forKey: Self.shownKey)
    }

    /// Partitions a full read of the bar by position. Used once, on first launch
    /// only, when there is no arrangement yet; afterwards `setHidden` is the only
    /// input. Positions are only meaningful while every icon is visible.
    @discardableResult
    func refresh(items: [BarItem], dividerX: CGFloat) -> Bool {
        let bands = AXReader.menuBarBands()
        var hidden = Set<String>()
        var visible = Set<String>()
        for item in items {
            guard item.frame != .zero,
                  let bundle = item.bundle,
                  bands.contains(where: { $0.contains(CGPoint(x: item.frame.midX, y: item.frame.midY)) })
            else { continue }
            if item.frame.midX < dividerX {
                hidden.insert(bundle)
            } else {
                visible.insert(bundle)
            }
        }
        // An app that was not visible in this pass (not running, or its item
        // could not be read) keeps the section it had.
        for bundle in self.hidden.subtracting(hidden).subtracting(visible) { hidden.insert(bundle) }
        for bundle in self.visible.subtracting(hidden).subtracting(visible) { visible.insert(bundle) }
        // Whatever the user picked in the manager outranks a position read.
        for bundle in shownByUser {
            hidden.remove(bundle)
            visible.insert(bundle)
        }
        visible.subtract(hidden)
        let before = self.hidden
        let changed = hidden != self.hidden || visible != self.visible
        if changed {
            Log.write("layout: folded=\(hidden.subtracting(before).sorted().joined(separator: ",")) "
                + "unfolded=\(before.subtracting(hidden).sorted().joined(separator: ","))")
        }
        self.hidden = hidden
        self.visible = visible
        save()
        return changed
    }

    func setHidden(_ bundle: String, _ isHidden: Bool) {
        if isHidden {
            hidden.insert(bundle)
            visible.remove(bundle)
            shownByUser.remove(bundle)
        } else {
            hidden.remove(bundle)
            visible.insert(bundle)
            shownByUser.insert(bundle)
        }
        save()
    }
}

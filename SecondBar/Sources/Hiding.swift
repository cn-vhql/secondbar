import Foundation

/// Holds macOS 27's menu bar visibility restriction: only the listed apps (and
/// all system items) stay in the bar, everything else is hidden and the bar
/// reflows. The restriction lasts until it is released or this process exits, so
/// a crash cannot leave the menu bar broken.
final class Hiding {
    static let allSystemItems: [Int] = Array(0..<64)
    static var isAvailable: Bool { SBHidingIsAvailable() }

    private var assertion: AnyObject?
    private var requested: (bundles: [String], systemItems: [Int])?
    private var generation = 0

    var isHeld: Bool { assertion != nil }

    /// Keeps only `bundles` visible. Unknown identifiers are ignored by macOS.
    /// `completion` runs on the main queue with whether the restriction landed.
    func hold(bundles: [String], systemItems: [Int] = Hiding.allSystemItems,
              completion: ((Bool) -> Void)? = nil) {
        var unique = Array(Set(bundles)).sorted()
        if let own = Bundle.main.bundleIdentifier, !unique.contains(own) { unique.append(own) }
        let wanted = (bundles: unique, systemItems: systemItems)
        if let current = requested, current.bundles == unique, current.systemItems == systemItems, isHeld {
            completion?(true)
            return
        }
        requested = wanted
        generation += 1
        let mine = generation

        SBHidingActivate(systemItems.map { NSNumber(value: $0) }, unique) { [weak self] handle, error in
            guard let self else { return }
            let fresh = handle as AnyObject?
            // A newer request (or a release) has superseded this one.
            guard mine == self.generation else {
                if let fresh { SBHidingInvalidate(fresh) }
                return
            }
            if let fresh {
                let previous = self.assertion
                self.assertion = fresh
                if let previous { SBHidingInvalidate(previous) }
                completion?(true)
            } else {
                self.assertion = nil
                if let error { Log.write("hide failed: \(error.localizedDescription)") }
                completion?(false)
            }
        }
    }

    func release() {
        requested = nil
        generation += 1
        guard let assertion else { return }
        self.assertion = nil
        SBHidingInvalidate(assertion)
    }

    deinit { release() }
}

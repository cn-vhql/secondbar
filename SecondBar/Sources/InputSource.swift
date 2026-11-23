import AppKit
import Carbon

/// The input menu item in the menu bar does not belong to the input method: it is
/// owned by `TextInputMenuAgent`, so the app icon of the owning process is a generic
/// grid placeholder and its process name is "TextInputMenuAgent". The glyph and name
/// that actually belong on that item live on the current input source.
enum InputSource {
    static let agentBundle = "com.apple.TextInputMenuAgent"

    struct Current {
        let name: String
        let bundle: String
        let icon: NSImage
    }

    static func current() -> Current? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        let name = property(source, kTISPropertyLocalizedName as CFString) as? String
        let bundle = property(source, kTISPropertyBundleID as CFString) as? String
        guard let url = property(source, kTISPropertyIconImageURL as CFString) as? URL,
              let icon = NSImage(contentsOf: url) else {
            // Named, but no glyph: the caller still gets a better name than the
            // agent's. Only the icon is optional.
            return name.map { Current(name: $0, bundle: bundle ?? agentBundle, icon: NSImage()) }
        }
        // These glyphs are template PDFs: opaque shapes defined purely by alpha. Drawn
        // untemplated they keep their black fill and vanish on a dark panel.
        icon.isTemplate = true
        icon.size = NSSize(width: 18, height: 18)
        return Current(name: name ?? "Input", bundle: bundle ?? agentBundle, icon: icon)
    }

    private static func property(_ source: TISInputSource, _ key: CFString) -> AnyObject? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
    }
}

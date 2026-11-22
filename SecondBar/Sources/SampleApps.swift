import AppKit

/// Stand-in rows for `--dump-ui` / `--show-ui`, so the layout can be checked
/// without the real menu bar being involved.
enum SampleApps {
    private static func symbol(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: 22, height: 22))
    }

    static let all: [ManagedApp] = [
        ManagedApp(bundle: "com.tencent.xinWeChat", name: "微信",
                   icon: symbol("message.fill"), isHidden: true, isRunning: true),
        ManagedApp(bundle: "com.tencent.qq", name: "QQ",
                   icon: symbol("bubble.left.and.bubble.right.fill"), isHidden: true, isRunning: true),
        ManagedApp(bundle: "com.wireguard.macos", name: "WireGuard",
                   icon: symbol("lock.shield.fill"), isHidden: true, isRunning: true),
        ManagedApp(bundle: "com.tencent.LemonMonitor", name: "腾讯柠檬清理",
                   icon: symbol("sparkles"), isHidden: true, isRunning: true),
        ManagedApp(bundle: "local.lumen.controller", name: "Lumen",
                   icon: symbol("sun.max.fill"), isHidden: false, isRunning: true),
        ManagedApp(bundle: "com.apple.weather.menu", name: "WeatherMenu",
                   icon: symbol("cloud.sun.fill"), isHidden: true, isRunning: false),
    ]
}

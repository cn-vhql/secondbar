// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 The SecondBar Authors

import AppKit

/// Stand-in rows for `--dump-ui` / `--show-ui`, so the layout can be checked
/// without the real menu bar being involved.
enum SampleApps {
    private static func symbol(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: 22, height: 22))
    }

    private static func app(_ bundle: String, _ name: String, _ symbolName: String,
                            hidden: Bool, running: Bool = true) -> ManagedApp {
        ManagedApp(bundle: bundle, name: name, detail: bundle, icon: symbol(symbolName),
                   isHidden: hidden, isRunning: running)
    }

    static let all: [ManagedApp] = [
        app("com.tencent.xinWeChat", "微信", "message.fill", hidden: true),
        app("com.tencent.qq", "QQ", "bubble.left.and.bubble.right.fill", hidden: true),
        app("com.wireguard.macos", "WireGuard", "lock.shield.fill", hidden: true),
        app("com.tencent.LemonMonitor", "腾讯柠檬清理", "sparkles", hidden: true),
        app("local.lumen.controller", "Lumen", "sun.max.fill", hidden: false),
        app("com.apple.weather.menu", "WeatherMenu", "cloud.sun.fill", hidden: true, running: false),
    ]
}

import Foundation
import ServiceManagement

/// Launch at login. `SMAppService` is the modern path, but it refuses an app that
/// is not in /Applications and properly signed, so a LaunchAgent is the fallback.
/// Both are checked, so the menu item reflects whatever is actually registered.
enum LoginItem {
    private static var agentURL: URL {
        let support = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("LaunchAgents/local.secondbar.agent.plist")
    }

    static var isEnabled: Bool {
        if SMAppService.mainApp.status == .enabled { return true }
        return FileManager.default.fileExists(atPath: agentURL.path)
    }

    /// Returns nil on success, or a message describing why it could not be changed.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        if enabled {
            do {
                try SMAppService.mainApp.register()
                Log.write("login item registered with SMAppService")
                return nil
            } catch {
                Log.write("SMAppService refused (\(error.localizedDescription)), writing a LaunchAgent")
                return writeAgent()
            }
        }
        if SMAppService.mainApp.status != .notRegistered {
            try? SMAppService.mainApp.unregister()
        }
        return removeAgent()
    }

    private static func writeAgent() -> String? {
        let plist: [String: Any] = [
            "Label": "local.secondbar.agent",
            "ProgramArguments": [Bundle.main.executablePath ?? "/Applications/SecondBar.app/Contents/MacOS/SecondBar"],
            "RunAtLoad": true,
            "KeepAlive": false,
            // An agent that starts before login finishes cannot read the menu bar,
            // so the launch is delayed a little instead of retrying in a loop.
            "ThrottleInterval": 10,
        ]
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(),
                                                   withIntermediateDirectories: true)
            try data.write(to: agentURL)
            Log.write("launch agent written to \(agentURL.path)")
            return nil
        } catch {
            return "无法设置开机启动：\(error.localizedDescription)"
        }
    }

    private static func removeAgent() -> String? {
        guard FileManager.default.fileExists(atPath: agentURL.path) else { return nil }
        do {
            try FileManager.default.removeItem(at: agentURL)
            Log.write("launch agent removed")
            return nil
        } catch {
            return "无法取消开机启动：\(error.localizedDescription)"
        }
    }
}

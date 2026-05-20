import Foundation
import ServiceManagement
import SharedKit

public enum LaunchAgentInstaller {
    public static let label = "com.junwoo.mailsorter.daemon"

    // MARK: - App login item (SMAppService, macOS 13+)

    public static var isAppLoginItemRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public static func registerAppLoginItem() throws {
        try SMAppService.mainApp.register()
    }

    public static func unregisterAppLoginItem() throws {
        try SMAppService.mainApp.unregister()
    }

    public static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    public static var daemonBinaryPath: String {
        if let execURL = Bundle.main.executableURL {
            let daemonURL = execURL.deletingLastPathComponent().appendingPathComponent("MailSorterDaemon")
            if FileManager.default.fileExists(atPath: daemonURL.path) {
                return daemonURL.path
            }
        }
        let inBundle = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent("MailSorterDaemon")
        if FileManager.default.fileExists(atPath: inBundle.path) {
            return inBundle.path
        }
        let inResources = Bundle.main.resourceURL?
            .appendingPathComponent("MailSorterDaemon").path
        if let inResources, FileManager.default.fileExists(atPath: inResources) {
            return inResources
        }
        let cli = "/usr/local/bin/MailSorterDaemon"
        if FileManager.default.fileExists(atPath: cli) { return cli }
        return Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("MailSorterDaemon").path
    }

    public static var isRegistered: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    public static func writePlist() throws {
        let dir = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let logDir = AppPaths.logsDir.path
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [daemonBinaryPath],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Background",
            "StandardOutPath": "\(logDir)/daemon.log",
            "StandardErrorPath": "\(logDir)/daemon.err"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL)
    }

    public static func register() throws {
        try writePlist()
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["bootstrap", "gui/\(getuid())", plistURL.path]
        try task.run()
        task.waitUntilExit()
    }

    public static func unregister() throws {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        try? task.run()
        task.waitUntilExit()
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    public static func restart() throws {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        try? task.run()
        task.waitUntilExit()
        try register()
    }
}

import SwiftUI
import SharedKit

@main
struct MailSorterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = MailStore()
    @StateObject private var settings = SettingsStore()
    @Environment(\.openWindow) private var openWindow

    init() {
        _ = Database.shared
    }

    var body: some Scene {
        // Store openWindow into AppDelegate every time body is evaluated so
        // applicationShouldHandleReopen can call it without depending on
        // MenuBarView being initialized (it's lazily created on first popover open).
        let _ = {
            appDelegate.openMainWindow = {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
        }()

        MenuBarExtra("MailSorter", systemImage: "tray.full") {
            MenuBarView()
                .environmentObject(store)
                .environmentObject(settings)
                .frame(width: 360)
        }
        .menuBarExtraStyle(.window)

        Window("MailSorter", id: "main") {
            MailListView()
                .environmentObject(store)
                .environmentObject(settings)
                .frame(minWidth: 720, minHeight: 480)
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(settings)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var openMainWindow: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            await NotificationCenterClient.shared.requestAuthorization()
            do {
                try LaunchAgentInstaller.restart()
                MailSorterLog.app.info("daemon automatically started on app launch")
            } catch {
                MailSorterLog.app.error("failed to auto-start daemon: \(error.localizedDescription)")
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag {
            sender.windows.first(where: { $0.title == "MailSorter" })?.makeKeyAndOrderFront(nil)
            sender.activate(ignoringOtherApps: true)
        } else {
            openMainWindow?()
        }
        return true
    }
}

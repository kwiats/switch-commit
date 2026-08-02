import AppKit
import Combine
import SwitchCommitAppLogic
import SwiftUI

/// Records which Settings chrome sections actually appeared.
/// Used by `--smoke-settings-navigation` to catch blank-window regressions.
@MainActor
final class SettingsSmokeProbe: ObservableObject {
    private(set) var seenSidebarTabs: Set<String> = []
    private(set) var seenDetailTabs: Set<String> = []

    func reset() {
        seenSidebarTabs.removeAll()
        seenDetailTabs.removeAll()
    }

    func markSidebar(_ tab: SettingsTab) {
        seenSidebarTabs.insert(tab.rawValue)
    }

    func markDetail(_ tab: SettingsTab) {
        seenDetailTabs.insert(tab.rawValue)
    }
}

private struct SettingsSmokeProbeKey: EnvironmentKey {
    static let defaultValue: SettingsSmokeProbe? = nil
}

extension EnvironmentValues {
    var settingsSmokeProbe: SettingsSmokeProbe? {
        get { self[SettingsSmokeProbeKey.self] }
        set { self[SettingsSmokeProbeKey.self] = newValue }
    }
}

/// Headless Settings navigation smoke for CI/local runs.
/// Opens a real Settings window, cycles every section including Updates,
/// and fails if SwiftUI stops rendering sidebar/detail chrome.
@MainActor
enum SettingsNavigationSmoke {
    private final class SelectionOwner: ObservableObject {
        @Published var selectedTab: SettingsTab = .accounts
    }

    static func run() -> Int32 {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let viewModel = AppViewModel(updateChecker: DisabledAppUpdateChecker())
        let selection = SelectionOwner()
        let probe = SettingsSmokeProbe()

        func installRoot(on hostingController: NSHostingController<SettingsView>) {
            hostingController.rootView = SettingsView(
                viewModel: viewModel,
                selectedTab: Binding(
                    get: { selection.selectedTab },
                    set: { selection.selectedTab = $0 }
                ),
                smokeProbe: probe
            )
        }

        let hostingController = NSHostingController(
            rootView: SettingsView(
                viewModel: viewModel,
                selectedTab: Binding(
                    get: { selection.selectedTab },
                    set: { selection.selectedTab = $0 }
                ),
                smokeProbe: probe
            )
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Switch Commit Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 900, height: 560))
        window.center()
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)

        let sequence: [SettingsTab] = [
            .general, .accounts, .detection, .updates, .accounts, .updates, .general
        ]

        for tab in sequence {
            probe.reset()
            selection.selectedTab = tab
            installRoot(on: hostingController)
            hostingController.view.layoutSubtreeIfNeeded()
            window.layoutIfNeeded()
            window.displayIfNeeded()
            spin(0.6)

            guard let contentView = window.contentView,
                  contentView.bounds.width > 100,
                  contentView.bounds.height > 100 else {
                fputs("settings-smoke: content view collapsed after \(tab.rawValue)\n", stderr)
                return 1
            }

            // Give SwiftUI another turn after layout.
            spin(0.2)

            for sidebarTab in SettingsTab.allCases {
                guard probe.seenSidebarTabs.contains(sidebarTab.rawValue) else {
                    fputs(
                        "settings-smoke: sidebar blank for \(sidebarTab.rawValue) after selecting \(tab.rawValue); seen=\(probe.seenSidebarTabs.sorted())\n",
                        stderr
                    )
                    return 1
                }
            }
            guard probe.seenDetailTabs.contains(tab.rawValue) else {
                fputs(
                    "settings-smoke: detail blank for \(tab.rawValue); seen=\(probe.seenDetailTabs.sorted())\n",
                    stderr
                )
                return 1
            }
        }

        print("settings-smoke: passed")
        return 0
    }

    private static func spin(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }
}

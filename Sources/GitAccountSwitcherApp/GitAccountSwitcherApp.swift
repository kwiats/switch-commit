import AppKit
import Combine
import GitAccountSwitcherAppLogic

@main
@MainActor
final class GitAccountSwitcherApp: NSObject, NSApplicationDelegate {
    private static var sharedDelegate: GitAccountSwitcherApp?

    private let updateChecker = SparkleAppUpdateChecker()
    private lazy var viewModel = AppViewModel(updateChecker: updateChecker)
    private let settingsWindowController = SettingsWindowController()
    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []

    static func main() {
        let app = NSApplication.shared
        let delegate = GitAccountSwitcherApp()
        sharedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        print("GitAccountSwitcherApp starting AppKit run loop")
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("GitAccountSwitcherApp did finish launching")
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "person.crop.circle.badge.checkmark", accessibilityDescription: "Git Account Switcher")
        item.button?.imagePosition = .imageOnly
        item.menu = buildMenu()
        statusItem = item
        observeMenuContentChanges()
        print("GitAccountSwitcherApp status item installed")
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        if let activeProfile = viewModel.activeProfile {
            let activeItem = NSMenuItem(title: "Active: \(activeProfile.displayName)", action: nil, keyEquivalent: "")
            activeItem.isEnabled = false
            menu.addItem(activeItem)
            menu.addItem(.separator())

            for profile in viewModel.profiles {
                let item = NSMenuItem(title: profile.displayName, action: #selector(selectProfile(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = profile.id
                item.image = statusImage(for: viewModel.gitBindingStatus(for: profile))
                item.state = profile.id == viewModel.activeProfileId ? .on : .off
                menu.addItem(item)
            }
        } else {
            let emptyItem = NSMenuItem(title: "No profile selected", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        }

        menu.addItem(.separator())
        let diagnosticsItem = NSMenuItem(title: "Run Local Diagnostics", action: #selector(runLocalDiagnostics), keyEquivalent: "")
        diagnosticsItem.target = self
        menu.addItem(diagnosticsItem)

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func observeMenuContentChanges() {
        viewModel.$menuContentRevision
            .dropFirst()
            .sink { [weak self] _ in
                self?.statusItem?.menu = self?.buildMenu()
            }
            .store(in: &cancellables)
    }

    private func statusImage(for status: ProfileGitBindingStatus) -> NSImage? {
        let color: NSColor
        switch status.displayColorName {
        case "green":
            color = .systemGreen
        case "orange":
            color = .systemOrange
        default:
            color = .systemRed
        }
        let configuration = NSImage.SymbolConfiguration(hierarchicalColor: color)
        return NSImage(
            systemSymbolName: status.systemImageName,
            accessibilityDescription: "Git binding status"
        )?.withSymbolConfiguration(configuration)
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard
            let profileId = sender.representedObject as? String,
            let profile = viewModel.profiles.first(where: { $0.id == profileId })
        else {
            return
        }
        viewModel.switchGlobalProfile(to: profile)
        statusItem?.menu = buildMenu()
    }

    @objc private func runLocalDiagnostics() {
        viewModel.runLocalDiagnostics()
        presentRequestedWindow()
    }

    @objc private func showSettings() {
        viewModel.requestSettingsPresentation()
        presentRequestedWindow()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func presentRequestedWindow() {
        guard viewModel.presentationRequest == .settings else {
            return
        }
        settingsWindowController.show(viewModel: viewModel)
        viewModel.clearPresentationRequest()
    }
}

import AppKit
import Combine
import SwitchCommitAppLogic

@main
@MainActor
final class SwitchCommitApp: NSObject, NSApplicationDelegate {
    private static var sharedDelegate: SwitchCommitApp?

    private let updateChecker = SparkleAppUpdateChecker()
    private lazy var viewModel = AppViewModel(
        updateChecker: updateChecker,
        launchAtLoginManager: SystemLaunchAtLoginManager()
    )
    private let settingsWindowController = SettingsWindowController()
    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []
    private lazy var frontmostContextMonitor = FrontmostContextMonitor(
        viewModel: viewModel,
        provider: LiveFrontmostPathProvider()
    )

    static func main() {
        let app = NSApplication.shared
        let delegate = SwitchCommitApp()
        sharedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        print("SwitchCommitApp starting AppKit run loop")
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("SwitchCommitApp did finish launching")
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "person.crop.circle.badge.checkmark", accessibilityDescription: "Switch Commit")
        updateStatusItemPresentation(item)
        item.menu = buildMenu()
        statusItem = item
        observeMenuContentChanges()
        frontmostContextMonitor.start()
        print("SwitchCommitApp status item installed")
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let contextItem = NSMenuItem(title: viewModel.contextPresentation.menuHeader, action: nil, keyEquivalent: "")
        contextItem.isEnabled = false
        menu.addItem(contextItem)
        menu.addItem(.separator())

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
                guard let self, let statusItem else {
                    return
                }
                updateStatusItemPresentation(statusItem)
                statusItem.menu = buildMenu()
            }
            .store(in: &cancellables)
    }

    private func updateStatusItemPresentation(_ item: NSStatusItem) {
        let title = truncatedStatusTitle(viewModel.contextPresentation.menuTitle)
        item.button?.title = title
        item.button?.toolTip = viewModel.contextPresentation.menuHeader
        item.button?.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
    }

    private func truncatedStatusTitle(_ title: String) -> String {
        let maximumLength = 42
        guard title.count > maximumLength else {
            return title
        }
        return String(title.prefix(maximumLength - 1)) + "…"
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

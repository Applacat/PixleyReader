import SwiftUI
import SwiftData

// MARK: - Launch State

/// Determines what to show on app launch
enum LaunchState {
    case firstLaunch        // Show Welcome folder in browser
    case sessionRestore     // Restore last opened folder
    case minimalLauncher    // Show minimal launcher (no folder context)
}

// MARK: - App Delegate

/// Handles file/folder opens from Finder (double-click, "Open With", drag to Dock icon).
/// Unlike `onOpenURL`, this fires even when the browser window is suppressed on cold launch.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    static var coordinator: AppCoordinator?

    func applicationWillTerminate(_ notification: Notification) {
        Self.coordinator?.flushScrollPosition()
        FolderService.shared.flushCacheIfNeeded()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let coordinator = Self.coordinator, let url = urls.first else { return }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }

        if isDirectory.boolValue {
            // Folder opened — browse it (has security scope from Finder)
            RecentFoldersManager.shared.addFolder(url)
            coordinator.openFolder(url)
            activateOrOpenBrowser(coordinator)
        } else {
            let ext = url.pathExtension.lowercased()
            guard ext == "md" || ext == "markdown" else { return }
            // Markdown file — need security-scoped access to parent folder
            openMarkdownFileWithFolderAccess(url, coordinator: coordinator)
        }
    }

    /// Opens a markdown file by resolving sandbox access for its parent folder.
    /// Checks for a cached bookmark first; falls back to NSOpenPanel if needed.
    private func openMarkdownFileWithFolderAccess(_ fileURL: URL, coordinator: AppCoordinator) {
        let parentFolder = fileURL.deletingLastPathComponent()
        let parentPath = parentFolder.path

        // Check if we already have a saved bookmark for this folder
        if let savedFolder = RecentFoldersManager.shared.getRecentFolders()
            .first(where: { $0.path == parentPath }),
           let resolvedURL = RecentFoldersManager.shared.resolveBookmark(savedFolder) {
            // Bookmark found — open silently
            coordinator.openFolder(resolvedURL)
            coordinator.selectFile(fileURL)
            activateOrOpenBrowser(coordinator)
            return
        }

        // No bookmark — ask user to grant folder access via NSOpenPanel
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = parentFolder
        panel.message = "Grant access to this folder to browse its contents"
        panel.prompt = "Open"

        panel.begin { @MainActor [weak self, weak coordinator] response in
            guard response == .OK,
                  let grantedURL = panel.url,
                  let self,
                  let coordinator else { return }

            RecentFoldersManager.shared.addFolder(grantedURL)
            coordinator.openFolder(grantedURL)
            coordinator.selectFile(fileURL)
            self.activateOrOpenBrowser(coordinator)
        }
    }

    /// Activates an existing browser window or requests a new one
    private func activateOrOpenBrowser(_ coordinator: AppCoordinator) {
        if let browserWindow = NSApp.windows.first(where: {
            $0.identifier?.rawValue.contains("browser") == true && $0.isVisible
        }) {
            browserWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            coordinator.requestOpenBrowser()
        }
    }
}

// MARK: - App Entry Point

/// Pixley Markdown Reader - A native macOS markdown reader for AI-generated files.
/// Watch what AI writes, ask questions about it, stay in flow.
@main
struct AIMDReaderApp: App {

    // MARK: - Constants

    static let hasLaunchedBeforeKey = "hasLaunchedBefore"

    // MARK: - State

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var coordinator = AppCoordinator()
    @State private var launchState: LaunchState = .minimalLauncher

    /// Settings repository - injected into Environment for all views
    private let settings = UserDefaultsSettingsRepository.shared

    /// SwiftData container for file metadata persistence
    private let modelContainer: ModelContainer

    // MARK: - Initialization

    init() {
        // Initialize SwiftData container
        do {
            modelContainer = try MetadataContainerConfiguration.makeContainer()
        } catch {
            // Fatal error - app cannot function without persistence
            fatalError("Failed to initialize SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        // Start window - minimal launcher
        Window("Pixley Markdown Reader", id: "start") {
            StartView(performLaunchIfNeeded: performLaunchIfNeeded)
                .environment(\.coordinator, coordinator)
                .environment(\.settings, settings)
                .modelContainer(modelContainer)
                .preferredColorScheme(settings.appearance.colorScheme)
                .task {
                    configureMetadataRepository()
                    AppDelegate.coordinator = coordinator
                }
        }
        #if os(macOS)
        .defaultLaunchBehavior(.presented)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)  // Always open centered, don't remember position
        #endif

        // Browser window - shown after folder selection
        WindowGroup("Pixley Markdown Reader", id: "browser") {
            BrowserView()
                .environment(\.coordinator, coordinator)
                .environment(\.settings, settings)
                .modelContainer(modelContainer)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
        #if os(macOS)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(after: .newItem) {
                Button(coordinator.navigation.rootFolderURL == nil ? "Choose Folder..." : "Change Folder...") {
                    openFolderPanel()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Divider()

                Button("Reload") {
                    coordinator.reloadDocument()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(coordinator.navigation.selectedFile == nil)

                Button("Close Folder") {
                    coordinator.closeFolder()
                }
                .keyboardShortcut("w", modifiers: [.command])
                .disabled(coordinator.navigation.rootFolderURL == nil)
            }
            
            CommandGroup(after: .textEditing) {
                Button("Go to File...") {
                    coordinator.toggleQuickSwitcher()
                }
                .keyboardShortcut("p", modifiers: [.command])
            }

            // Find menu — routes to NSTextView's native find bar
            CommandGroup(after: .textEditing) {
                Button("Find...") {
                    Self.sendFindPanelAction(NSTextFinder.Action.showFindInterface.rawValue)
                }
                .keyboardShortcut("f", modifiers: [.command])

                Button("Find Next") {
                    Self.sendFindPanelAction(NSTextFinder.Action.nextMatch.rawValue)
                }
                .keyboardShortcut("g", modifiers: [.command])

                Button("Find Previous") {
                    Self.sendFindPanelAction(NSTextFinder.Action.previousMatch.rawValue)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            }

            // View menu — font size + AI Chat toggle
            CommandGroup(after: .toolbar) {
                if #available(macOS 26, *) {
                    Button(coordinator.ui.isAIChatVisible ? "Hide AI Chat" : "Show AI Chat") {
                        withAnimation {
                            coordinator.toggleAIChat()
                        }
                    }
                    .keyboardShortcut("a", modifiers: [.command, .shift])

                    Divider()
                }

                Button("Increase Font Size") {
                    settings.rendering.fontSize = min(32, settings.rendering.fontSize + 1)
                }
                .keyboardShortcut("=", modifiers: [.command])

                Button("Decrease Font Size") {
                    settings.rendering.fontSize = max(10, settings.rendering.fontSize - 1)
                }
                .keyboardShortcut("-", modifiers: [.command])
            }

            // Help menu
            CommandGroup(replacing: .help) {
                Button("Pixley Markdown Reader Help") {
                    openWelcomeToPage("01-Welcome.md")
                }
                .keyboardShortcut("/", modifiers: [.command])
                
                Button("Reading Documents") {
                    openWelcomeToPage("02-Reading.md")
                }

                Button("Navigating Files") {
                    openWelcomeToPage("03-Navigating.md")
                }

                if #available(macOS 26, *) {
                    Button("AI Chat") {
                        openWelcomeToPage("Tips and Tricks/04-AI-Chat.md")
                    }
                }

                Button("Quick Reference") {
                    openWelcomeToPage("Tips and Tricks/05-Quick-Reference.md")
                }
                
                Divider()
                
                Link("Report a Bug", destination: URL(string: "https://github.com")!)
            }
            
            // About menu
            CommandGroup(replacing: .appInfo) {
                Button("About Pixley Markdown Reader") {
                    showAboutPanel()
                }
            }
        }
        #endif

        // Settings window (Cmd+,)
        Settings {
            SettingsView()
                .environment(\.settings, settings)
        }
    }

    // MARK: - Repository Configuration

    /// Configures the metadata repository on the coordinator
    /// Called once when app launches
    @MainActor
    private func configureMetadataRepository() {
        guard coordinator.metadata == nil else { return }
        let context = modelContainer.mainContext
        coordinator.metadata = SwiftDataMetadataRepository(modelContext: context)
    }

    // MARK: - Launch Logic

    /// Determines and executes the appropriate launch behavior
    private func performLaunchIfNeeded() {
        launchState = determineLaunchState()

        switch launchState {
        case .firstLaunch:
            performFirstLaunch()
        case .sessionRestore:
            performSessionRestore()
        case .minimalLauncher:
            // Already showing launcher, nothing to do
            break
        }
    }

    /// Determines what launch state the app should use
    private func determineLaunchState() -> LaunchState {
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: Self.hasLaunchedBeforeKey)

        if !hasLaunchedBefore {
            return .firstLaunch
        }

        // Restore both folder AND file — never open an empty browser
        if let lastFolder = RecentFoldersManager.shared.lastSessionFolder(),
           let folderURL = RecentFoldersManager.shared.resolveBookmark(lastFolder),
           let fileURL = RecentFoldersManager.shared.lastSessionFile(forFolderPath: lastFolder.path) {
            coordinator.openFolder(folderURL)
            coordinator.selectFile(fileURL)
            return .sessionRestore
        }

        return .minimalLauncher
    }

    /// First launch: open Welcome folder and mark as launched
    private func performFirstLaunch() {
        // Ensure Welcome folder exists in Application Support (copy from bundle if needed)
        guard let welcomeURL = WelcomeManager.ensureWelcomeFolder() else {
            // No welcome folder available, fall back to launcher
            UserDefaults.standard.set(true, forKey: Self.hasLaunchedBeforeKey)
            return
        }

        coordinator.openFolder(welcomeURL)
        coordinator.setFirstLaunchWelcome(true)  // Flag to auto-select first file

        // Mark as launched
        UserDefaults.standard.set(true, forKey: Self.hasLaunchedBeforeKey)

        // Open browser window (StartView will handle the redirect)
    }

    /// Session restore: folder already set in determineLaunchState
    private func performSessionRestore() {
        // Folder is already set in coordinator by determineLaunchState
        // StartView will detect rootFolderURL and redirect to browser
    }

    #if os(macOS)
    // MARK: - Find Panel

    private static func sendFindPanelAction(_ tag: Int) {
        let menuItem = NSMenuItem()
        menuItem.tag = tag

        // Find the markdown NSTextView directly (identified by usesFindBar)
        // and make it first responder so the find bar attaches correctly
        if let window = NSApp.keyWindow,
           let textView = findMarkdownTextView(in: window.contentView) {
            window.makeFirstResponder(textView)
            textView.performFindPanelAction(menuItem)
        }
    }

    /// Recursively searches the view hierarchy for the markdown NSTextView (has usesFindBar enabled)
    private static func findMarkdownTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? NSTextView, textView.usesFindBar {
            return textView
        }
        for subview in view.subviews {
            if let found = findMarkdownTextView(in: subview) {
                return found
            }
        }
        return nil
    }

    // MARK: - Open Folder (macOS)

    private func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to browse markdown files"
        panel.prompt = "Choose"

        panel.begin { @MainActor response in
            guard response == .OK, let folderURL = panel.url else { return }
            self.coordinator.openFolder(folderURL)
        }
    }

    // MARK: - About Panel

    private func showAboutPanel() {
        let credits = NSMutableAttributedString()

        let bodyFont = NSFont.systemFont(ofSize: 11)
        let boldFont = NSFont.boldSystemFont(ofSize: 11)
        let bodyColor = NSColor.secondaryLabelColor
        let headingColor = NSColor.labelColor

        let bodyAttrs: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: bodyColor]
        let headingAttrs: [NSAttributedString.Key: Any] = [.font: boldFont, .foregroundColor: headingColor]

        credits.append(NSAttributedString(string: "Syntax Theme Color Schemes\n", attributes: headingAttrs))
        credits.append(NSAttributedString(string: "Used under MIT License\n\n", attributes: bodyAttrs))

        let themes: [(String, String)] = [
            ("Solarized", "Ethan Schoonover"),
            ("Dracula", "Zeno Rocha"),
            ("Monokai", "Wimer Hazenberg"),
            ("Nord", "Arctic Ice Studio"),
            ("One Dark", "Atom / GitHub"),
            ("GitHub", "GitHub Primer"),
        ]

        for (name, author) in themes {
            credits.append(NSAttributedString(string: "\(name)", attributes: headingAttrs))
            credits.append(NSAttributedString(string: " by \(author)\n", attributes: bodyAttrs))
        }

        // Center-align
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.paragraphSpacing = 2
        credits.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: credits.length))

        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits
        ])
    }

    // MARK: - Open Welcome Tutorial

    /// Opens the Welcome folder to a specific page
    /// Used for Help menu items and About screen
    private func openWelcomeToPage(_ fileName: String) {
        // Ensure Welcome folder exists in Application Support (copy from bundle if needed)
        guard let welcomeURL = WelcomeManager.ensureWelcomeFolder() else {
            return
        }

        // Find the requested file
        let targetFile = welcomeURL.appendingPathComponent(fileName)

        // Verify file exists
        guard FileManager.default.fileExists(atPath: targetFile.path) else {
            // Fallback to opening the folder without file selection
            coordinator.openFolder(welcomeURL)
            return
        }

        // Open with file context
        coordinator.openFolder(welcomeURL)
        coordinator.selectFile(targetFile)

        // Signal that browser window should open (consumed by StartView)
        coordinator.requestOpenBrowser()

        // Ensure app is active and a window exists to observe the flag
        // This handles the case where all windows are closed
        NSApp.activate(ignoringOtherApps: true)

        // If no windows exist, we need to trigger window creation
        // The Start window will observe shouldOpenBrowser and redirect to Browser
        if NSApp.windows.filter({ $0.isVisible }).isEmpty {
            // Force Start window to appear, which will then redirect to Browser
            Task { @MainActor in
                NSApp.sendAction(#selector(NSWindow.makeKeyAndOrderFront(_:)), to: nil, from: nil)
            }
        }
    }

    #endif
}


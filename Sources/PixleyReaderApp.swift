import SwiftUI

// MARK: - App Entry Point

/// Pixley Reader - A native macOS markdown reader for AI-generated files.
/// Watch what AI writes, ask questions about it, stay in flow.
@main
struct PixleyReaderApp: App {

    @State private var appState = AppState()

    var body: some Scene {
        // Start window - shown until user selects a folder
        Window("Pixley Reader", id: "start") {
            StartView()
                .environment(appState)
                .preferredColorScheme(.dark)
        }
        #if os(macOS)
        .defaultLaunchBehavior(.presented)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        #endif

        // AI Test window - for experimenting with Foundation Models
        Window("AI Test", id: "ai-test") {
            AITestView()
                .preferredColorScheme(.dark)
        }
        #if os(macOS)
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentSize)
        #endif

        // Browser window - shown after folder selection
        WindowGroup(id: "browser") {
            BrowserView()
                .environment(appState)
                .preferredColorScheme(.dark)
        }
        #if os(macOS)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(after: .newItem) {
                Button(appState.rootFolderURL == nil ? "Choose Folder..." : "Change Folder...") {
                    openFolderPanel()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Divider()

                Button("Reload") {
                    appState.triggerReload()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(appState.selectedFile == nil)
            }

        }
        #endif
    }

    #if os(macOS)
    // MARK: - Open Folder (macOS)

    private func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to browse markdown files"
        panel.prompt = "Choose"

        panel.begin { response in
            guard response == .OK, let folderURL = panel.url else { return }
            self.appState.setRootFolder(folderURL)
        }
    }
    #endif
}

// MARK: - App State

/// Central application state.
@MainActor
@Observable
final class AppState {

    /// Root folder selected by user (nil until user selects one)
    var rootFolderURL: URL? = nil

    /// Currently selected file to view
    var selectedFile: URL? = nil

    /// Whether the AI Chat panel is visible
    var isAIChatVisible: Bool = false

    /// Whether the current file has unseen changes
    var fileHasChanges: Bool = false

    /// Reload trigger (incremented to force reload)
    var reloadTrigger: Int = 0

    /// Current document content (loaded from selectedFile)
    var documentContent: String = ""

    /// Initial question for chat (set from Ask Pixley, cleared after use)
    var initialChatQuestion: String? = nil

    // MARK: - Actions

    func setRootFolder(_ url: URL) {
        // Stop accessing previous folder if any
        rootFolderURL?.stopAccessingSecurityScopedResource()

        // Start accessing new folder's security scope
        // This grants access to the folder AND all its descendants
        let didStart = url.startAccessingSecurityScopedResource()
        print("🔐 [AppState] setRootFolder: \(url.path)")
        print("🔐 [AppState] startAccessingSecurityScopedResource returned: \(didStart)")

        rootFolderURL = url
        selectedFile = nil
        documentContent = ""
        fileHasChanges = false
    }

    func closeFolder() {
        // Stop accessing security-scoped resource if needed
        rootFolderURL?.stopAccessingSecurityScopedResource()
        rootFolderURL = nil
        selectedFile = nil
        documentContent = ""
        fileHasChanges = false
    }

    func selectFile(_ url: URL) {
        selectedFile = url
        fileHasChanges = false
    }

    func triggerReload() {
        reloadTrigger += 1
        fileHasChanges = false
    }

    func markFileChanged() {
        fileHasChanges = true
    }

    func clearChanges() {
        fileHasChanges = false
    }

    /// Open browser with a specific file selected and chat ready
    func openWithFileContext(fileURL: URL, question: String) {
        let parentFolder = fileURL.deletingLastPathComponent()

        // Stop accessing previous folder if any
        rootFolderURL?.stopAccessingSecurityScopedResource()

        // Start accessing new folder's security scope
        _ = parentFolder.startAccessingSecurityScopedResource()

        rootFolderURL = parentFolder
        selectedFile = fileURL
        initialChatQuestion = question
        isAIChatVisible = true
        fileHasChanges = false
    }
}

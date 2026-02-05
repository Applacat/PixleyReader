import SwiftUI

// MARK: - Start View

/// Minimal launcher - centered single-column layout with branding and folder shortcuts.
/// Shows when no folder is open. Click app icon to open Welcome tour (easter egg).
struct StartView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var isDropTargeted = false
    @State private var hasPerformedLaunch = false
    @State private var isReady = false
    @State private var showWelcomeError = false

    /// Closure to perform launch logic (first launch, session restore)
    var performLaunchIfNeeded: (() -> Void)? = nil

    var body: some View {
        Group {
            if isReady {
                launcherContent
            } else {
                // Show nothing while determining launch state
                Color.clear
            }
        }
        .frame(width: 480, height: 520)
        .onAppear {
            // Run launch logic first (only once)
            if !hasPerformedLaunch {
                hasPerformedLaunch = true
                performLaunchIfNeeded?()
            }

            // If we have a root folder (from first launch or session restore),
            // redirect to browser immediately
            if appState.rootFolderURL != nil {
                openWindow(id: "browser")
                dismissWindow(id: "start")
            } else {
                // No folder context - show launcher
                isReady = true
            }
        }
        .onChange(of: appState.shouldOpenBrowser) { _, shouldOpen in
            // React to menu commands (Help, About) that request browser window
            if shouldOpen {
                appState.shouldOpenBrowser = false  // Consume the flag
                openWindow(id: "browser")
                dismissWindow(id: "start")
            }
        }
    }

    // MARK: - Launcher Content

    private var launcherContent: some View {
        VStack(spacing: 0) {
            Spacer()

            // Centered content
            VStack(spacing: 24) {
                // App mascot + title (click for welcome tour)
                Button(action: openWelcomeFolder) {
                    VStack(spacing: 16) {
                        Image("AIMD")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 140, height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                            .accessibilityLabel("AI.md Reader app icon")

                        VStack(spacing: 4) {
                            Text("AI.md Reader")
                                .font(.title2.bold())

                            Text("Read what AI writes")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(MascotButtonStyle())

                // Folder shortcuts
                VStack(spacing: 0) {
                    FolderShortcutButton(
                        title: "Read Sample Files",
                        icon: "book.circle",
                        action: openWelcomeFolderWithPrompt
                    )
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    FolderShortcutButton(
                        title: "Desktop",
                        icon: "menubar.dock.rectangle",
                        action: { openStandardFolder(.desktopDirectory) }
                    )
                    FolderShortcutButton(
                        title: "Documents",
                        icon: "doc.text",
                        action: { openStandardFolder(.documentDirectory) }
                    )
                    FolderShortcutButton(
                        title: "Downloads",
                        icon: "arrow.down.circle",
                        action: { openStandardFolder(.downloadsDirectory) }
                    )

                    Divider()
                        .padding(.vertical, 8)

                    FolderShortcutButton(
                        title: "Choose Folder...",
                        icon: "folder.badge.plus",
                        action: chooseFolder
                    )
                }
                .frame(width: 220)
            }

            Spacer()

            // Footer hint
            Text("or drop a folder anywhere")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(urls)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .overlay {
            if isDropTargeted {
                dropOverlay
            }
        }
        .alert("Tutorial Unavailable", isPresented: $showWelcomeError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("The tutorial files could not be found. Please reinstall the app.")
        }
    }

    // MARK: - Drop Overlay

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 4]))
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .padding(4)
            .allowsHitTesting(false)
    }

    // MARK: - Folder Actions

    private func openStandardFolder(_ directory: FileManager.SearchPathDirectory) {
        SecurityScopedBookmarkManager.shared.getOrRequestAccess(
            to: directory,
            onAccessGranted: { url in
                self.openFolder(url)
            },
            onPermissionNeeded: { url in
                self.showFolderPanel(for: directory, at: url)
            }
        )
    }
    
    #if os(macOS)
    private func showFolderPanel(for directory: FileManager.SearchPathDirectory, at url: URL) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = url
        panel.prompt = "Open"

        let name: String
        switch directory {
        case .desktopDirectory: name = "Desktop"
        case .documentDirectory: name = "Documents"
        case .downloadsDirectory: name = "Downloads"
        default: name = "folder"
        }
        panel.message = "Grant access to \(name)"

        panel.begin { [weak self] response in
            guard response == .OK, let selectedURL = panel.url else { return }

            // Save bookmark via manager
            SecurityScopedBookmarkManager.shared.saveBookmark(selectedURL, for: directory)

            self?.openFolder(selectedURL)
        }
    }
    #endif

    private func chooseFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to browse"
        panel.prompt = "Open"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.openFolder(url)
        }
        #endif
    }

    private func openFolder(_ url: URL) {
        RecentFoldersManager.shared.addFolder(url)
        appState.setRootFolder(url)
        openWindow(id: "browser")
        dismissWindow(id: "start")
    }

    private func handleDrop(_ urls: [URL]) -> Bool {
        guard let url = urls.first else { return false }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return false }
        openFolder(url)
        return true
    }

    // MARK: - Welcome Folder Location

    /// Welcome folder in Application Support (persists reliably, backed up)
    private static var welcomeFolderURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AIMDReader")
            .appendingPathComponent("Welcome")
    }

    /// Ensures Welcome folder exists in Application Support, copying from bundle if needed
    private static func ensureWelcomeFolder() -> URL? {
        guard let targetURL = welcomeFolderURL else { return nil }

        // Already exists - use it
        if FileManager.default.fileExists(atPath: targetURL.path) {
            return targetURL
        }

        // Copy from bundle
        guard let bundleURL = Bundle.main.url(forResource: "Welcome", withExtension: nil) else {
            return nil
        }

        do {
            let parentDir = targetURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: bundleURL, to: targetURL)
            return targetURL
        } catch {
            return nil  // Silent fallback
        }
    }

    // MARK: - Welcome Folder (Easter Egg)

    private func openWelcomeFolder() {
        // Ensure Welcome folder exists in Application Support (copy from bundle if needed)
        guard let welcomeURL = Self.ensureWelcomeFolder() else {
            return
        }

        appState.setRootFolder(welcomeURL)
        appState.isFirstLaunchWelcome = true
        openWindow(id: "browser")
        dismissWindow(id: "start")
    }

    // MARK: - Welcome Folder with AI Prompt

    /// Opens Welcome folder with 01-Welcome.md selected and AI chat pre-filled
    /// OOD Pattern: Uses existing infrastructure (openWithFileContext)
    /// Same code path as manual file selection + typing question
    private func openWelcomeFolderWithPrompt() {
        // Ensure Welcome folder exists in Application Support (copy from bundle if needed)
        guard let welcomeURL = Self.ensureWelcomeFolder() else {
            showWelcomeError = true
            return
        }

        // Find 01-Welcome.md
        let welcomeFile = welcomeURL.appendingPathComponent("01-Welcome.md")

        // Verify file exists
        guard FileManager.default.fileExists(atPath: welcomeFile.path) else {
            showWelcomeError = true
            return
        }

        // OOD: Use existing infrastructure
        // This is the same code path as if user:
        // 1. Opened folder manually
        // 2. Selected file manually
        // 3. Typed question manually
        appState.openWithFileContext(
            fileURL: welcomeFile,
            question: "What is this app and what can I do with it?"
        )

        openWindow(id: "browser")
        dismissWindow(id: "start")
    }
}

// MARK: - Folder Shortcut Button

struct FolderShortcutButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(.blue)
                    .frame(width: 24)

                Text(title)
                    .font(.body)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(FolderButtonStyle())
    }
}

// MARK: - Folder Button Style

struct FolderButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .onHover { isHovered = $0 }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return Color.primary.opacity(0.1)
        } else if isHovered {
            return Color.primary.opacity(0.05)
        }
        return .clear
    }
}

// MARK: - Mascot Button Style

struct MascotButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : (isHovered ? 1.02 : 1.0))
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

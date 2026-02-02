import SwiftUI
import FoundationModels

// MARK: - Start View

/// Welcome screen - Pixelmator-style layout with generous hit targets.
/// Left: branding + folder shortcuts. Right: Ask Pixley + recent folders.
struct StartView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var recentFolders: [RecentFolder] = []
    @State private var isDropTargeted = false

    // Ask Pixley state
    @State private var pixleyPrompt: String = ""
    @State private var pixleyResponse: String = ""
    @State private var isPixleyThinking = false
    @State private var attachedFileURL: URL?
    @State private var attachedFolderURL: URL?

    var body: some View {
        HStack(spacing: 0) {
            // Left: Branding + folder shortcuts
            brandingPanel
                .frame(width: 280)

            Divider()

            // Right: Ask Pixley + Recent folders
            rightPanel
                .frame(minWidth: 360)
        }
        .frame(minWidth: 640, minHeight: 440)
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
        .onAppear {
            recentFolders = RecentFoldersManager.shared.getRecentFolders()
        }
    }

    // MARK: - Branding Panel (Left)

    private var brandingPanel: some View {
        VStack(spacing: 0) {
            Spacer()

            // Mascot + Title (click to open Welcome tour)
            Button(action: openWelcomeFolder) {
                VStack(spacing: 16) {
                    Image("Pixley")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 140, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)

                    VStack(spacing: 4) {
                        Text("Pixley Reader")
                            .font(.title2.bold())

                        Text("Read what AI writes")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(PixleyMascotButtonStyle())
            .help("Click for a tour of Pixley Reader")

            Spacer()

            // Folder shortcuts
            VStack(spacing: 0) {
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
            .padding(16)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Ask Pixley section
            askPixleySection
                .padding(20)

            // Response (if any)
            if !pixleyResponse.isEmpty {
                pixleyResponseView
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }

            Divider()
                .padding(.horizontal, 20)

            // Recent folders
            recentFoldersSection

            Spacer(minLength: 0)

            // Footer hint
            Text("or drop a folder anywhere")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
        }
        .background(.thickMaterial)
    }

    // MARK: - Ask Pixley Section

    private var askPixleySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with context attachment
            HStack(spacing: 8) {
                Text("Ask Pixley")
                    .font(.headline)

                // Show attached folder
                if let folderURL = attachedFolderURL {
                    Button {
                        // Tap to change folder
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                                .font(.caption)
                            Text(folderURL.lastPathComponent)
                                .font(.callout)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.blue.opacity(0.15), in: Capsule())
                        .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)

                    Button {
                        attachedFolderURL = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                // Show attached file
                else if let fileURL = attachedFileURL {
                    Button {
                        pickFileForContext()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.fill")
                                .font(.caption)
                            Text(fileURL.lastPathComponent)
                                .font(.callout)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.blue.opacity(0.15), in: Capsule())
                        .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)

                    Button {
                        attachedFileURL = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                // No attachment
                else {
                    Button("Attach File...") {
                        pickFileForContext()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // Input row
            HStack(spacing: 12) {
                TextField(placeholderText, text: $pixleyPrompt)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await askPixley() }
                    }

                Button {
                    Task { await askPixley() }
                } label: {
                    if isPixleyThinking {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(pixleyPrompt.isEmpty ? Color.secondary : Color.blue)
                .disabled(pixleyPrompt.isEmpty || isPixleyThinking)
            }
        }
    }

    private var placeholderText: String {
        if attachedFolderURL != nil {
            return "Ask about this folder..."
        } else if attachedFileURL != nil {
            return "Ask about this file..."
        }
        return "What would you like to know?"
    }

    // MARK: - Pixley Response

    private var pixleyResponseView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image("Pixley")
                    .resizable()
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text("Pixley")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }

            Text(pixleyResponse)
                .font(.callout)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Recent Folders Section

    private var recentFoldersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if recentFolders.isEmpty {
                ContentUnavailableView {
                    Label("No Recent Folders", systemImage: "clock")
                } description: {
                    Text("Folders you open will appear here")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                Text("Recent Folders")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                List(recentFolders) { folder in
                    RecentFolderButton(folder: folder) {
                        openRecentFolder(folder)
                    } onAsk: {
                        askAboutFolder(folder)
                    } onRemove: {
                        removeRecentFolder(folder)
                    }
                    .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(maxHeight: 200)
            }
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

    // MARK: - Ask Pixley AI

    private func askPixley() async {
        guard !pixleyPrompt.isEmpty else { return }

        isPixleyThinking = true
        pixleyResponse = ""

        do {
            let availability = SystemLanguageModel.default.availability
            guard availability == .available else {
                pixleyResponse = "Apple Intelligence is not available on this device."
                isPixleyThinking = false
                return
            }

            // Build context with attached folder or file
            var context = ""

            if let folderURL = attachedFolderURL {
                // Scan folder for markdown files
                let folderSummary = scanFolderForContext(folderURL)
                context = "The user is asking about folder '\(folderURL.lastPathComponent)':\n\n\(folderSummary)\n\n"
            } else if let fileURL = attachedFileURL {
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    context = "The user attached this file (\(fileURL.lastPathComponent)):\n\n\(content.prefix(2000))\n\n"
                }
            }

            let session = LanguageModelSession(
                instructions: """
                    You are Pixley, a helpful assistant for navigating and understanding files.
                    Help users navigate folders, summarize files, and answer questions.
                    Be concise and friendly.
                    """
            )

            let response = try await session.respond(
                to: context + pixleyPrompt,
                generating: PixleyIntent.self
            )

            let intent = response.content
            await handlePixleyIntent(intent)

        } catch {
            pixleyResponse = "Sorry, I had trouble with that. Try again?"
        }

        isPixleyThinking = false
    }

    /// Scan a folder and build a summary of its contents for AI context
    private func scanFolderForContext(_ url: URL) -> String {
        let fm = FileManager.default
        var lines: [String] = []

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return "Could not read folder contents."
        }

        var mdFiles: [String] = []
        var otherFiles: [String] = []
        var folders: [String] = []
        var scanned = 0
        let maxScan = 100

        while let itemURL = enumerator.nextObject() as? URL {
            scanned += 1
            if scanned > maxScan { break }

            let relativePath = itemURL.path.replacingOccurrences(of: url.path + "/", with: "")
            let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            if isDir {
                folders.append(relativePath)
            } else {
                let ext = itemURL.pathExtension.lowercased()
                if ext == "md" || ext == "markdown" {
                    mdFiles.append(relativePath)
                } else {
                    otherFiles.append(relativePath)
                }
            }
        }

        lines.append("Markdown files (\(mdFiles.count)):")
        for file in mdFiles.prefix(20) {
            lines.append("  - \(file)")
        }
        if mdFiles.count > 20 { lines.append("  ... and \(mdFiles.count - 20) more") }

        if !folders.isEmpty {
            lines.append("\nFolders (\(folders.count)):")
            for folder in folders.prefix(10) {
                lines.append("  - \(folder)/")
            }
            if folders.count > 10 { lines.append("  ... and \(folders.count - 10) more") }
        }

        if scanned >= maxScan {
            lines.append("\n(Scanned first \(maxScan) items)")
        }

        return lines.joined(separator: "\n")
    }

    private func handlePixleyIntent(_ intent: PixleyIntent) async {
        switch intent.action {
        case "navigate":
            pixleyResponse = intent.interpretation

        case "summarize", "answer":
            if let fileURL = attachedFileURL {
                #if os(macOS)
                let parentFolder = fileURL.deletingLastPathComponent()
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.directoryURL = parentFolder
                panel.message = "Grant access to view folder contents"
                panel.prompt = "Open"

                panel.begin { response in
                    guard response == .OK, let folderURL = panel.url else {
                        self.pixleyResponse = intent.interpretation
                        return
                    }

                    RecentFoldersManager.shared.addFolder(folderURL)
                    self.recentFolders = RecentFoldersManager.shared.getRecentFolders()
                    self.appState.openWithFileContext(fileURL: fileURL, question: self.pixleyPrompt)
                    self.openWindow(id: "browser")
                    self.dismissWindow(id: "start")
                }
                return
                #endif
            }
            pixleyResponse = intent.interpretation

        default:
            pixleyResponse = intent.interpretation
        }
    }

    // MARK: - File Picker

    private func pickFileForContext() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.text, .plainText, .sourceCode]
        panel.message = "Choose a file to give Pixley context"
        panel.prompt = "Attach"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            self.attachedFileURL = url
        }
        #endif
    }

    // MARK: - Folder Actions

    private func openStandardFolder(_ directory: FileManager.SearchPathDirectory) {
        let key = "bookmark_\(directory.rawValue)"

        // Try saved bookmark first
        if let bookmarkData = UserDefaults.standard.data(forKey: key) {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale),
               !isStale,
               url.startAccessingSecurityScopedResource() {
                openFolder(url)
                return
            }
        }

        // Need to request permission via panel
        #if os(macOS)
        guard let directoryURL = FileManager.default.urls(for: directory, in: .userDomainMask).first else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = directoryURL
        panel.prompt = "Open"

        let name: String
        switch directory {
        case .desktopDirectory: name = "Desktop"
        case .documentDirectory: name = "Documents"
        case .downloadsDirectory: name = "Downloads"
        default: name = "folder"
        }
        panel.message = "Grant access to \(name)"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            if let bookmarkData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(bookmarkData, forKey: key)
            }

            self.openFolder(url)
        }
        #endif
    }

    private func chooseFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to browse"
        panel.prompt = "Open"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            self.openFolder(url)
        }
        #endif
    }

    private func openFolder(_ url: URL) {
        RecentFoldersManager.shared.addFolder(url)
        recentFolders = RecentFoldersManager.shared.getRecentFolders()
        appState.setRootFolder(url)
        openWindow(id: "browser")
        dismissWindow(id: "start")
    }

    private func openRecentFolder(_ folder: RecentFolder) {
        guard let url = RecentFoldersManager.shared.resolveBookmark(folder) else {
            removeRecentFolder(folder)
            return
        }
        appState.setRootFolder(url)
        openWindow(id: "browser")
        dismissWindow(id: "start")
    }

    private func removeRecentFolder(_ folder: RecentFolder) {
        RecentFoldersManager.shared.removeFolder(folder)
        recentFolders = RecentFoldersManager.shared.getRecentFolders()
    }

    private func askAboutFolder(_ folder: RecentFolder) {
        guard let url = RecentFoldersManager.shared.resolveBookmark(folder) else {
            removeRecentFolder(folder)
            return
        }
        // Set folder as context for Ask Pixley
        attachedFolderURL = url
        attachedFileURL = nil  // Clear any file attachment
        pixleyResponse = ""    // Clear previous response
    }

    private func handleDrop(_ urls: [URL]) -> Bool {
        guard let url = urls.first else { return false }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return false }
        openFolder(url)
        return true
    }

    // MARK: - Welcome Folder

    private func openWelcomeFolder() {
        // Find the bundled Welcome folder in app resources
        guard let bundleURL = Bundle.main.url(forResource: "Welcome", withExtension: nil) else {
            pixleyResponse = "Welcome tour not found. Try opening a folder to get started!"
            return
        }

        // Copy to temp so we have security scope access
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PixleyWelcome-\(UUID().uuidString)")

        do {
            try FileManager.default.copyItem(at: bundleURL, to: tempDir)
            appState.setRootFolder(tempDir)
            openWindow(id: "browser")
            dismissWindow(id: "start")
        } catch {
            pixleyResponse = "Couldn't open Welcome tour: \(error.localizedDescription)"
        }
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

// MARK: - Recent Folder Button

struct RecentFolderButton: View {
    let folder: RecentFolder
    let action: () -> Void
    let onAsk: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .font(.body)
                        .lineLimit(1)

                    Text(folder.path)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                if isHovered {
                    // Ask pill
                    Button(action: onAsk) {
                        Text("Ask")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.blue.opacity(0.15), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)

                    // Remove button
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(FolderButtonStyle())
        .onHover { isHovered = $0 }
    }
}

// MARK: - Pixley Mascot Button Style

struct PixleyMascotButtonStyle: ButtonStyle {
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

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Browser View

/// Main browser layout - shown after a folder is selected.
/// Displays folder navigation, markdown viewer, and AI chat inspector.
struct BrowserView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var isDropTargeted = false

    // State restoration
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @SceneStorage("lastSelectedFile") private var lastSelectedFilePath: String = ""

    // MARK: - Body

    var body: some View {
        Group {
            if appState.rootFolderURL != nil {
                browserContent
            } else {
                // Redirect to start window if no folder selected
                noFolderView
            }
        }
        .onDisappear {
            // Invalidate cache for this folder
            if let folderURL = appState.rootFolderURL {
                FolderService.shared.invalidateCache(for: folderURL)
            }
            
            // Clear folder state and reopen start window when browser closes
            appState.closeFolder()
            openWindow(id: "start")
        }
    }

    // MARK: - Browser Content

    private var browserContent: some View {
        @Bindable var appState = appState

        return NavigationSplitView(columnVisibility: $columnVisibility) {
            OutlineFileListWrapper()
                .navigationSplitViewColumnWidth(min: 280, ideal: 400, max: 600)
        } detail: {
            if appState.selectedFile != nil {
                MarkdownView()
            } else {
                noSelectionView
            }
        }
        .onAppear {
            // Consume the flag if it was set by menu commands
            if appState.shouldOpenBrowser {
                appState.shouldOpenBrowser = false
            }

            // Restore last selected file if valid
            if !lastSelectedFilePath.isEmpty && appState.selectedFile == nil {
                let url = URL(fileURLWithPath: lastSelectedFilePath)
                if FileManager.default.fileExists(atPath: url.path) {
                    appState.selectFile(url)
                }
            }
        }
        .onChange(of: appState.selectedFile) { _, newFile in
            // Persist selected file
            lastSelectedFilePath = newFile?.path ?? ""
        }
        #if os(macOS)
        .inspector(isPresented: $appState.isAIChatVisible) {
            ChatView()
                .inspectorColumnWidth(min: 250, ideal: 280, max: 400)
        }
        .toolbar {
            // Font size controls + Appearance toggle + AI Chat toggle
            ToolbarItemGroup(placement: .primaryAction) {
                FontSizeControls()

                AppearanceToggle()

                Button {
                    withAnimation {
                        appState.isAIChatVisible.toggle()
                    }
                } label: {
                    Label(
                        appState.isAIChatVisible ? "Hide AI Chat" : "Show AI Chat",
                        systemImage: appState.isAIChatVisible
                            ? "bubble.left.and.bubble.right.fill"
                            : "bubble.left.and.bubble.right"
                    )
                }
                .help(appState.isAIChatVisible ? "Hide AI Chat" : "Show AI Chat")
            }
        }
        #endif
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
        .errorBannerOverlay()
    }

    // MARK: - No Folder View

    private var noFolderView: some View {
        Color.clear
            .onAppear {
                // Auto-redirect to start screen
                openWindow(id: "start")
                dismissWindow(id: "browser")
            }
    }

    // MARK: - No Selection View

    private var noSelectionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tertiary)

            Text("Select a markdown file")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Drop Overlay

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 4]))
            .background(Color.accentColor.opacity(0.1))
            .padding(8)
            .allowsHitTesting(false)
    }

    // MARK: - Actions

    private func closeAndReturnToStart() {
        appState.closeFolder()
        openWindow(id: "start")
        dismissWindow(id: "browser")
    }

    private func handleDrop(_ urls: [URL]) -> Bool {
        guard let url = urls.first else { return false }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }

        if isDirectory.boolValue {
            RecentFoldersManager.shared.addFolder(url)
            appState.setRootFolder(url)
            return true
        } else if url.pathExtension.lowercased() == "md" || url.pathExtension.lowercased() == "markdown" {
            let folderURL = url.deletingLastPathComponent()
            RecentFoldersManager.shared.addFolder(folderURL)
            appState.setRootFolder(folderURL)
            appState.selectFile(url)
            return true
        }

        return false
    }
}

// MARK: - Outline File List Wrapper

/// Wrapper for OutlineFileList that handles loading and filtering
struct OutlineFileListWrapper: View {

    @Environment(AppState.self) private var appState
    @State private var rootItems: [FolderItem] = []
    @State private var displayItems: [FolderItem] = []  // Pre-filtered for display
    @State private var isLoading = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                OutlineFileList(
                    items: displayItems,
                    selection: Binding(
                        get: { appState.selectedFile },
                        set: { newValue in
                            if let url = newValue {
                                appState.selectFile(url)
                                RecentFoldersManager.shared.addRecentFile(url, parentFolder: appState.rootFolderURL)
                            }
                        }
                    )
                )
            }
        }
        .task(id: appState.rootFolderURL) {
            await loadRootFolder()
        }
    }
    
    private func loadRootFolder() async {
        guard let rootURL = appState.rootFolderURL else { return }
        isLoading = true
        FolderService.shared.invalidateCache(for: rootURL)
        rootItems = await FolderService.shared.loadTree(at: rootURL)

        // Pre-filter items for display (avoids filtering on every view update)
        displayItems = FolderTreeFilter.filterMarkdownOnly(rootItems)

        // First launch welcome: select first markdown
        if appState.isFirstLaunchWelcome {
            if let firstMarkdown = FolderTreeFilter.findFirstMarkdown(in: displayItems) {
                appState.selectFile(firstMarkdown.url)
            }
            appState.isFirstLaunchWelcome = false
        }

        isLoading = false
    }
}

// MARK: - Font Size Controls

/// Toolbar controls for adjusting markdown display settings
struct FontSizeControls: View {

    @AppStorage("fontSize") private var fontSize: Double = 14.0

    var body: some View {
        HStack(spacing: 2) {
            // Decrease font size
            Button {
                fontSize = max(10, fontSize - 1)
            } label: {
                Image(systemName: "minus")
            }
            .help("Decrease font size")
            .disabled(fontSize <= 10)

            // Font size display
            Text("\(Int(fontSize))")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .frame(minWidth: 20)

            // Increase font size
            Button {
                fontSize = min(32, fontSize + 1)
            } label: {
                Image(systemName: "plus")
            }
            .help("Increase font size")
            .disabled(fontSize >= 32)
        }
        .controlSize(.small)
    }
}

/// Toolbar toggle for dark/light mode (session-only, defaults to system)
struct AppearanceToggle: View {

    @Environment(AppState.self) private var appState

    private var isDarkMode: Bool {
        // nil means system, treat as dark for icon purposes
        appState.colorSchemeOverride == .dark || appState.colorSchemeOverride == nil
    }

    var body: some View {
        @Bindable var appState = appState

        Button {
            // Toggle between light and dark (never back to nil/system once toggled)
            appState.colorSchemeOverride = appState.colorSchemeOverride == .dark ? .light : .dark
        } label: {
            Image(systemName: appState.colorSchemeOverride == .light ? "sun.max.fill" : "moon.fill")
        }
        .help(appState.colorSchemeOverride == .light ? "Switch to dark mode" : "Switch to light mode")
        .controlSize(.small)
    }
}



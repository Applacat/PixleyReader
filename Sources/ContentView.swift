import SwiftUI
import UniformTypeIdentifiers

// MARK: - Browser View

/// Main browser layout - shown after a folder is selected.
/// Displays folder navigation, markdown viewer, and AI chat inspector.
struct BrowserView: View {

    @Environment(\.coordinator) private var coordinator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var isDropTargeted = false
    @State private var allMarkdownFiles: [FolderItem] = []

    // State restoration
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @SceneStorage("lastSelectedFile") private var lastSelectedFilePath: String = ""

    // MARK: - Body

    var body: some View {
        Group {
            if coordinator.navigation.rootFolderURL != nil {
                browserContent
            } else {
                // Redirect to start window if no folder selected
                noFolderView
            }
        }
        .onDisappear {
            // Invalidate cache for this folder
            if let folderURL = coordinator.navigation.rootFolderURL {
                FolderService.shared.invalidateCache(for: folderURL)
            }

            // Clear folder state and reopen start window when browser closes
            coordinator.closeFolder()
            openWindow(id: "start")
        }
    }

    // MARK: - Browser Content

    private var browserContent: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            OutlineFileListWrapper()
                .navigationSplitViewColumnWidth(min: 280, ideal: 400, max: 600)
        } detail: {
            if coordinator.navigation.selectedFile != nil {
                MarkdownView()
            } else {
                noSelectionView
            }
        }
        .onAppear {
            // Consume the flag if it was set by menu commands
            if coordinator.ui.shouldOpenBrowser {
                coordinator.consumeOpenBrowser()
            }

            // SceneStorage fallback — only if session restore didn't already set a file
            if coordinator.navigation.selectedFile == nil && !lastSelectedFilePath.isEmpty {
                let url = URL(fileURLWithPath: lastSelectedFilePath)
                if FileManager.default.fileExists(atPath: url.path) {
                    coordinator.selectFile(url)
                }
            }
        }
        .onChange(of: coordinator.navigation.selectedFile) { _, newFile in
            // Persist selected file
            lastSelectedFilePath = newFile?.path ?? ""
        }
        #if os(macOS)
        .modifier(AIChatModifier(coordinator: coordinator))
        .navigationTitle(coordinator.navigation.selectedFile?.deletingPathExtension().lastPathComponent ?? "Pixley Markdown Reader")
        .toolbar {
            // Font size stepper (trailing edge, own pill)
            ToolbarItem(placement: .primaryAction) {
                FontSizeControls()
            }
        }
        #endif
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDropTargeted {
                dropOverlay
            }
        }
        .quickSwitcherOverlay(allFiles: allMarkdownFiles)
        .errorBannerOverlay()
        .onChange(of: coordinator.navigation.displayItems) { _, newItems in
            allMarkdownFiles = FolderTreeFilter.flattenMarkdownFiles(newItems)
        }
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
                .font(.largeTitle.weight(.light))
                .imageScale(.large)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

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
        coordinator.closeFolder()
        openWindow(id: "start")
        dismissWindow(id: "browser")
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first,
              provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

            Task { @MainActor in
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }

                if isDirectory.boolValue {
                    RecentFoldersManager.shared.addFolder(url)
                    coordinator.openFolder(url)
                } else if url.pathExtension.lowercased() == "md" || url.pathExtension.lowercased() == "markdown" {
                    let folderURL = url.deletingLastPathComponent()
                    RecentFoldersManager.shared.addFolder(folderURL)
                    coordinator.openFolder(folderURL)
                    coordinator.selectFile(url)
                }
            }
        }
        return true
    }
}

// MARK: - Outline File List Wrapper

/// Wrapper for OutlineFileList that handles loading and filtering
struct OutlineFileListWrapper: View {

    @Environment(\.coordinator) private var coordinator
    @State private var rootItems: [FolderItem] = []
    @State private var isLoading = false
    @State private var showFavoritesOnly = false
    @State private var filteredItems: [FolderItem] = []
    @State private var filterTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Sidebar filter field
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Filter files...", text: Binding(
                    get: { coordinator.navigation.sidebarFilterQuery },
                    set: { coordinator.sidebarFilterQuery = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.callout)

                if !coordinator.navigation.sidebarFilterQuery.isEmpty {
                    Button {
                        coordinator.setSidebarFilter("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Clear filter")
                    .accessibilityLabel("Clear sidebar filter")
                    .accessibilityHint("Removes the current filter to show all files")
                }

                Button {
                    showFavoritesOnly.toggle()
                } label: {
                    Image(systemName: showFavoritesOnly ? "star.fill" : "star")
                        .foregroundStyle(showFavoritesOnly ? .yellow : .secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help(showFavoritesOnly ? "Show all files" : "Show favorites only")
                .accessibilityLabel(showFavoritesOnly ? "Show all files" : "Show favorites only")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            // File list or loading/empty states
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredItems.isEmpty && (showFavoritesOnly || !coordinator.navigation.sidebarFilterQuery.isEmpty) {
                VStack(spacing: 8) {
                    Image(systemName: showFavoritesOnly ? "star" : "doc.text.magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text(showFavoritesOnly ? "No favorites yet" : "No matching files")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if showFavoritesOnly {
                        Text("Star files to see them here")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                OutlineFileList(
                    items: filteredItems,
                    selection: Binding(
                        get: { coordinator.navigation.selectedFile },
                        set: { newValue in
                            if let url = newValue {
                                coordinator.selectFile(url)
                                RecentFoldersManager.shared.addRecentFile(url, parentFolder: coordinator.navigation.rootFolderURL)
                            }
                        }
                    ),
                    isFavorite: { url in coordinator.isFavorite(url) },
                    onToggleFavorite: { url in
                        coordinator.toggleFavorite(for: url)
                    }
                )
            }
        }
        .task(id: coordinator.navigation.rootFolderURL) {
            await loadRootFolder()
        }
        .onChange(of: coordinator.navigation.sidebarFilterQuery) { _, _ in
            recomputeFilteredItems(debounce: true)
        }
        .onChange(of: coordinator.navigation.displayItems) { _, _ in
            recomputeFilteredItems(debounce: false)
        }
        .onChange(of: showFavoritesOnly) { _, _ in
            recomputeFilteredItems(debounce: false)
        }
        .onDisappear {
            filterTask?.cancel()
            filterTask = nil
        }
    }

    /// Recomputes filtered items, optionally debounced for typing.
    private func recomputeFilteredItems(debounce: Bool) {
        filterTask?.cancel()
        filterTask = Task {
            if debounce {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
            }

            // filterByName is @MainActor (uses cache), so call it here
            var items = coordinator.navigation.displayItems
            let query = coordinator.navigation.sidebarFilterQuery
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                items = FolderTreeFilter.filterByName(items, query: query, rootPath: coordinator.navigation.rootFolderURL?.path ?? "")
            }

            if showFavoritesOnly {
                let allFiles = FolderTreeFilter.flattenMarkdownFiles(items)
                filteredItems = allFiles.filter { coordinator.isFavorite($0.url) }
            } else {
                filteredItems = items
            }
        }
    }

    private func loadRootFolder() async {
        guard let rootURL = coordinator.navigation.rootFolderURL else { return }
        isLoading = true
        FolderService.shared.invalidateCache(for: rootURL)
        rootItems = await FolderService.shared.loadTree(at: rootURL)

        // Pre-filter items for display and store on coordinator (shared with Quick Switcher)
        coordinator.setDisplayItems(FolderTreeFilter.filterMarkdownOnly(rootItems))
        filteredItems = coordinator.navigation.displayItems

        // First launch welcome: select first markdown
        if coordinator.navigation.isFirstLaunchWelcome {
            if let firstMarkdown = FolderTreeFilter.findFirstMarkdown(in: coordinator.navigation.displayItems) {
                coordinator.selectFile(firstMarkdown.url)
            }
            coordinator.setFirstLaunchWelcome(false)
        }

        isLoading = false
    }
}

// MARK: - Font Size Controls

/// Toolbar controls for adjusting markdown display settings
struct FontSizeControls: View {

    @Environment(\.settings) private var settings

    var body: some View {
        HStack(spacing: 2) {
            // Decrease font size
            Button {
                settings.rendering.fontSize = max(10, settings.rendering.fontSize - 1)
            } label: {
                Image(systemName: "minus")
            }
            .help("Decrease font size")
            .accessibilityLabel("Decrease font size")
            .disabled(settings.rendering.fontSize <= 10)

            // Font size display
            Text("\(Int(settings.rendering.fontSize))")
                .font(.caption2.monospacedDigit())
                .fontWeight(.medium)
                .frame(minWidth: 20)

            // Increase font size
            Button {
                settings.rendering.fontSize = min(32, settings.rendering.fontSize + 1)
            } label: {
                Image(systemName: "plus")
            }
            .help("Increase font size")
            .accessibilityLabel("Increase font size")
            .disabled(settings.rendering.fontSize >= 32)
        }
        .controlSize(.small)
    }
}

// MARK: - AI Chat Modifier

/// Wraps AI Chat inspector and toolbar button behind macOS 26 availability.
/// On macOS <26, this modifier is a no-op — no chat UI is shown.
struct AIChatModifier: ViewModifier {
    let coordinator: AppCoordinator

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .inspector(isPresented: Binding(
                    get: { coordinator.ui.isAIChatVisible },
                    set: { coordinator.isAIChatVisible = $0 }
                )) {
                    ChatView()
                        .inspectorColumnWidth(min: 250, ideal: 280, max: 400)
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                                coordinator.toggleAIChat()
                            } else {
                                withAnimation {
                                    coordinator.toggleAIChat()
                                }
                            }
                        } label: {
                            Label(
                                coordinator.ui.isAIChatVisible ? "Hide AI Chat" : "Show AI Chat",
                                systemImage: coordinator.ui.isAIChatVisible
                                    ? "bubble.left.and.bubble.right.fill"
                                    : "bubble.left.and.bubble.right"
                            )
                        }
                        .help(coordinator.ui.isAIChatVisible ? "Hide AI Chat" : "Show AI Chat")
                        .accessibilityLabel(coordinator.ui.isAIChatVisible ? "Hide AI Chat" : "Show AI Chat")
                    }
                }
        } else {
            content
        }
    }
}

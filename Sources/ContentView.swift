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
            // Reopen start window when browser closes
            openWindow(id: "start")
        }
    }

    // MARK: - Browser Content

    private var browserContent: some View {
        @Bindable var appState = appState

        return NavigationSplitView {
            FileBrowserSidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            if appState.selectedFile != nil {
                MarkdownView()
            } else {
                noSelectionView
            }
        }
        #if os(macOS)
        .inspector(isPresented: $appState.isAIChatVisible) {
            ChatView()
                .inspectorColumnWidth(min: 250, ideal: 280, max: 400)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
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

// MARK: - File Browser Sidebar

/// Hierarchical file browser with tap-to-expand folders and generous hit targets.
struct FileBrowserSidebar: View {

    @Environment(AppState.self) private var appState

    @State private var items: [FolderItem] = []
    @State private var isLoading = false
    @State private var expandedFolders: Set<String> = []

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                ContentUnavailableView("Empty Folder", systemImage: "folder")
            } else {
                fileList
            }
        }
        .navigationTitle(appState.rootFolderURL?.lastPathComponent ?? "Files")
        .task(id: appState.rootFolderURL) {
            guard let rootURL = appState.rootFolderURL else { return }
            isLoading = true
            items = await FolderService.shared.loadTree(at: rootURL)
            expandedFolders.removeAll()
            isLoading = false
        }
    }

    private var fileList: some View {
        ScrollView([.vertical, .horizontal], showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    FileRowView(
                        item: item,
                        expandedFolders: $expandedFolders,
                        depth: 0
                    )
                }
            }
            .frame(minWidth: 220)  // Minimum sidebar width
        }
        .background(.regularMaterial)
    }
}

// MARK: - File Row View

/// Recursive row view for files and folders.
/// - Folders: tap to expand/collapse, shows chevron + markdown count
/// - Files: tap to select (if markdown)
struct FileRowView: View {
    let item: FolderItem
    @Binding var expandedFolders: Set<String>
    let depth: Int

    @Environment(AppState.self) private var appState

    private var isExpanded: Bool {
        expandedFolders.contains(item.id)
    }

    private var isSelected: Bool {
        appState.selectedFile == item.url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The row itself
            rowButton

            // Children (if folder is expanded)
            if item.isFolder && isExpanded, let children = item.children {
                ForEach(children) { child in
                    FileRowView(
                        item: child,
                        expandedFolders: $expandedFolders,
                        depth: depth + 1
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rowButton: some View {
        Button {
            handleTap()
        } label: {
            HStack(spacing: 0) {
                // Indentation
                if depth > 0 {
                    Spacer()
                        .frame(width: CGFloat(depth) * 20)
                }

                // Chevron for folders
                if item.isFolder {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 20)
                } else {
                    Spacer().frame(width: 20)
                }

                // Icon
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(iconColor)
                    .frame(width: 24)

                // Name - no truncation, shows full text
                Text(item.name)
                    .foregroundStyle(textColor)
                    .fixedSize(horizontal: true, vertical: false)

                // Spacer ensures row extends to fill width
                Spacer(minLength: 16)

                // Markdown count for folders
                if item.isFolder && item.markdownCount > 0 {
                    Text("\(item.markdownCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarRowStyle(isSelected: isSelected, isFolder: item.isFolder))
        .disabled(!item.isFolder && !item.isMarkdown)
    }

    private func handleTap() {
        if item.isFolder {
            // Toggle expansion
            withAnimation(.easeInOut(duration: 0.2)) {
                if isExpanded {
                    expandedFolders.remove(item.id)
                } else {
                    expandedFolders.insert(item.id)
                }
            }
        } else if item.isMarkdown {
            appState.selectFile(item.url)
        }
    }

    private var icon: String {
        if item.isFolder {
            return isExpanded ? "folder.fill" : "folder.fill"
        }
        if item.isMarkdown { return "doc.text.fill" }
        return "doc.fill"
    }

    private var iconColor: Color {
        if item.isFolder { return .blue }
        if item.isMarkdown { return .primary }
        return .secondary
    }

    private var textColor: Color {
        if item.isFolder || item.isMarkdown { return .primary }
        return .secondary
    }
}

// MARK: - Sidebar Row Style

/// Button style for sidebar rows - generous hit target with hover and selection states
struct SidebarRowStyle: ButtonStyle {
    let isSelected: Bool
    let isFolder: Bool

    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .onHover { isHovered = $0 }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isSelected && !isFolder {
            return Color.accentColor.opacity(0.2)
        } else if isPressed {
            return Color.primary.opacity(0.1)
        } else if isHovered {
            return Color.primary.opacity(0.05)
        }
        return .clear
    }
}

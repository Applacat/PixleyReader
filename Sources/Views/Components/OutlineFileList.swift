import SwiftUI
import AppKit

// MARK: - NSOutlineView Wrapper

/// Native macOS file browser using NSOutlineView.
/// Single-column outline with disclosure triangles, like iPhone Files app.
struct OutlineFileList: NSViewRepresentable {

    let items: [FolderItem]
    @Binding var selection: URL?
    var isFavorite: ((URL) -> Bool)? = nil
    var onToggleFavorite: ((URL) -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        // Outline view with keyboard handling
        let outlineView = KeyHandlingOutlineView()
        outlineView.headerView = nil
        outlineView.indentationPerLevel = 10
        outlineView.rowSizeStyle = .default
        outlineView.rowHeight = 24  // Explicit row height for consistency
        outlineView.style = .sourceList  // macOS source list style
        outlineView.autoresizesOutlineColumn = true
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.floatsGroupRows = false
        outlineView.allowsEmptySelection = true
        outlineView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))  // Native double-click expand

        // Single column for file names
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FileColumn"))
        column.isEditable = false
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        // Accessibility
        outlineView.setAccessibilityLabel("File browser")
        outlineView.setAccessibilityHelp("Use arrow keys to navigate, left/right to expand/collapse folders, Return to select file")

        // Data source and delegate
        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator

        // Scroll view container
        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder  // Clean borders

        // Store reference for updates
        context.coordinator.outlineView = outlineView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let outlineView = context.coordinator.outlineView else { return }

        // Keep callback references current
        context.coordinator.isFavorite = isFavorite
        context.coordinator.onToggleFavorite = onToggleFavorite
        context.coordinator.selection = _selection

        // Pre-fetch favorites as Set<String> for O(1) lookup during cell configuration
        context.coordinator.refreshFavoriteSet(items: items)

        // Always keep coordinator's items in sync with SwiftUI
        let oldCount = context.coordinator.items.count
        context.coordinator.items = items

        // Reload if item count changed or outline view is empty but should have content
        let itemsChanged = oldCount != items.count
        let outlineStale = outlineView.numberOfRows == 0 && !items.isEmpty

        if itemsChanged || outlineStale {
            context.coordinator.lastSyncedURL = nil  // Force re-sync after data reload
            outlineView.reloadData()

            // Restore from persistent expandedPaths (tracked incrementally via delegate)
            context.coordinator.restoreExpansionState(outlineView: outlineView)
        }

        // Sync selection from coordinator → NSOutlineView
        context.coordinator.syncSelection(outlineView: outlineView)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        if let outlineView = scrollView.documentView as? NSOutlineView {
            outlineView.dataSource = nil
            outlineView.delegate = nil
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(items: items, selection: _selection, isFavorite: isFavorite, onToggleFavorite: onToggleFavorite)
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {

        var items: [FolderItem]
        var selection: Binding<URL?>
        weak var outlineView: NSOutlineView?
        var isFavorite: ((URL) -> Bool)?
        var onToggleFavorite: ((URL) -> Void)?
        /// Pre-fetched favorite paths for O(1) lookup during cell configuration
        var favoritePathsSet = Set<String>()
        private var hasPerformedInitialExpansion = false
        /// Persistent set of expanded folder paths — maintained incrementally
        private var expandedPaths = Set<String>()
        /// Tracks last URL we synced to, so we don't fight the user's keyboard navigation
        fileprivate var lastSyncedURL: URL?

        /// Static placeholder to avoid repeated allocations in data source methods
        /// This is used only as a safety fallback and should never actually appear in UI
        private static let placeholderItem = FolderItem(
            url: URL(fileURLWithPath: "/"),
            isFolder: false,
            markdownCount: 0
        )

        init(items: [FolderItem], selection: Binding<URL?>, isFavorite: ((URL) -> Bool)? = nil, onToggleFavorite: ((URL) -> Void)? = nil) {
            self.items = items
            self.selection = selection
            self.isFavorite = isFavorite
            self.onToggleFavorite = onToggleFavorite
        }

        /// Pre-fetches all favorites into a Set for O(1) lookup during cell configuration.
        func refreshFavoriteSet(items: [FolderItem]) {
            guard let isFavorite else {
                favoritePathsSet.removeAll()
                return
            }
            var set = Set<String>()
            func walk(_ items: [FolderItem]) {
                for item in items {
                    if item.isMarkdown, isFavorite(item.url) {
                        set.insert(item.url.path)
                    }
                    if let children = item.children {
                        walk(children)
                    }
                }
            }
            walk(items)
            favoritePathsSet = set
        }
        
        // MARK: - Expansion State Management
        
        /// Restores expansion state from the persistent expandedPaths set.
        func restoreExpansionState(outlineView: NSOutlineView) {
            // Expand all on first load (welcome experience)
            if !hasPerformedInitialExpansion {
                expandAllInitial(outlineView: outlineView, items: items)
                hasPerformedInitialExpansion = true
            } else {
                restoreFromPaths(outlineView: outlineView, items: items)
            }
        }

        private func restoreFromPaths(outlineView: NSOutlineView, items: [FolderItem]) {
            for item in items where item.isFolder {
                if expandedPaths.contains(item.url.path) {
                    outlineView.expandItem(item, expandChildren: false)
                }
                if let children = item.children {
                    restoreFromPaths(outlineView: outlineView, items: children)
                }
            }
        }

        private func expandAllInitial(outlineView: NSOutlineView, items: [FolderItem]) {
            for item in items {
                if item.isFolder {
                    expandedPaths.insert(item.url.path)
                    outlineView.expandItem(item, expandChildren: false)
                    if let children = item.children {
                        expandAllInitial(outlineView: outlineView, items: children)
                    }
                }
            }
        }

        // MARK: - Expansion Tracking (NSOutlineViewDelegate)

        func outlineViewItemDidExpand(_ notification: Notification) {
            guard let folderItem = notification.userInfo?["NSObject"] as? FolderItem else { return }
            expandedPaths.insert(folderItem.url.path)
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            guard let folderItem = notification.userInfo?["NSObject"] as? FolderItem else { return }
            expandedPaths.remove(folderItem.url.path)
        }
        
        // MARK: - Double Click Handler
        
        @objc func handleDoubleClick(_ sender: NSOutlineView) {
            let clickedRow = sender.clickedRow
            guard clickedRow >= 0,
                  let item = sender.item(atRow: clickedRow) as? FolderItem,
                  item.isFolder else {
                return
            }
            
            // Toggle expansion on double-click
            if sender.isItemExpanded(item) {
                sender.collapseItem(item)
            } else {
                sender.expandItem(item)
            }
        }

        // MARK: - Data Source

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if let folderItem = item as? FolderItem {
                return folderItem.children?.count ?? 0
            }
            return items.count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if let folderItem = item as? FolderItem {
                guard let children = folderItem.children, index < children.count else {
                    // Safety: Return static placeholder if children is nil or index out of bounds
                    return Self.placeholderItem
                }
                return children[index]
            }
            guard index < items.count else {
                // Safety: Return static placeholder if index out of bounds
                return Self.placeholderItem
            }
            return items[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let folderItem = item as? FolderItem else { return false }
            return folderItem.isFolder && (folderItem.children?.isEmpty == false)
        }

        // MARK: - Delegate

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let folderItem = item as? FolderItem else { return nil }

            let cellIdentifier = NSUserInterfaceItemIdentifier("FileCell")
            let cell: FileCellView

            if let existingCell = outlineView.makeView(withIdentifier: cellIdentifier, owner: self) as? FileCellView {
                cell = existingCell
            } else {
                cell = FileCellView()
                cell.identifier = cellIdentifier
            }

            // Calculate indentation level for this item
            var indentLevel = 0
            var currentItem: Any? = item
            while let parent = outlineView.parent(forItem: currentItem) {
                indentLevel += 1
                currentItem = parent
            }

            // Configure content with indentation awareness (uses pre-fetched favorites set)
            let favorited = folderItem.isMarkdown ? favoritePathsSet.contains(folderItem.url.path) : false
            cell.configure(with: folderItem, indentLevel: indentLevel, outlineView: outlineView, isFavorite: favorited, onToggleFavorite: onToggleFavorite)

            return cell
        }

        // MARK: - Selection Sync

        /// Syncs the coordinator's selectedFile to the NSOutlineView's visual selection.
        /// Called from updateNSView when the binding changes externally (e.g., AppDelegate, session restore).
        /// Only acts when the binding value actually changes — prevents fighting the user's
        /// keyboard navigation (e.g., arrow-keying to a folder shouldn't snap back to the last file).
        func syncSelection(outlineView: NSOutlineView) {
            let targetURL = selection.wrappedValue

            // Don't fight the user's navigation if the binding hasn't changed
            guard targetURL != lastSyncedURL else { return }
            lastSyncedURL = targetURL

            // Get the currently selected item in the outline view
            let currentRow = outlineView.selectedRow
            if let targetURL {
                // Check if the outline view already has this item selected
                if currentRow >= 0,
                   let currentItem = outlineView.item(atRow: currentRow) as? FolderItem,
                   currentItem.url == targetURL {
                    return // Already in sync
                }

                // Find and select the target item
                if let row = findRow(for: targetURL, in: outlineView) {
                    outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    outlineView.scrollRowToVisible(row)
                }
            } else if currentRow >= 0 {
                // No selection expected — deselect
                outlineView.deselectAll(nil)
            }
        }

        /// Recursively searches the outline view for a row matching the given URL.
        /// Expands parent folders as needed to reveal the item.
        private func findRow(for url: URL, in outlineView: NSOutlineView) -> Int? {
            // Walk through items recursively to find and expand path to target
            func search(items: [FolderItem], expandParents: Bool) -> FolderItem? {
                for item in items {
                    if item.url == url { return item }
                    if item.isFolder, let children = item.children {
                        if let found = search(items: children, expandParents: expandParents) {
                            // Expand this folder so the child is visible
                            if expandParents {
                                outlineView.expandItem(item)
                                expandedPaths.insert(item.url.path)
                            }
                            return found
                        }
                    }
                }
                return nil
            }

            guard let _ = search(items: items, expandParents: true) else { return nil }

            // Now that parents are expanded, find the row
            let rowCount = outlineView.numberOfRows
            for row in 0..<rowCount {
                if let item = outlineView.item(atRow: row) as? FolderItem, item.url == url {
                    return row
                }
            }
            return nil
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let outlineView = notification.object as? NSOutlineView else { return }
            let selectedRow = outlineView.selectedRow
            guard selectedRow >= 0,
                  let item = outlineView.item(atRow: selectedRow) as? FolderItem else {
                return
            }

            if item.isMarkdown {
                selection.wrappedValue = item.url
            } else if item.isFolder {
                // Toggle expand/collapse on mouse click only (not keyboard navigation)
                if let event = NSApp.currentEvent,
                   event.type == .leftMouseUp || event.type == .leftMouseDown {
                    if outlineView.isItemExpanded(item) {
                        outlineView.collapseItem(item)
                    } else {
                        outlineView.expandItem(item)
                    }
                }
            }
        }

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            // Allow selecting everything - folders expand/collapse, files open
            return true
        }

    }
}

// MARK: - Key Handling Outline View

/// NSOutlineView subclass that adds Return and Escape key handling.
/// Up/Down arrows and Left/Right expand/collapse are handled natively by NSOutlineView.
final class KeyHandlingOutlineView: NSOutlineView {
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36: // Return
            let row = selectedRow
            guard row >= 0, let item = item(atRow: row) as? FolderItem else {
                super.keyDown(with: event)
                return
            }
            if item.isFolder {
                // Toggle folder expansion
                if isItemExpanded(item) {
                    collapseItem(item)
                } else {
                    expandItem(item)
                }
            }
            // For files, the selection change already triggers opening via the delegate
            // so Return on a file is effectively a no-op (already selected = already open)

        case 53: // Escape
            deselectAll(nil)

        default:
            super.keyDown(with: event)
        }
    }
}

// MARK: - File Cell View

/// Custom cell view with icon, name, favorite star, and markdown count badge for folders.
final class FileCellView: NSTableCellView {

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let starButton = NSButton()
    private let countLabel = NSTextField(labelWithString: "")
    private var countMinWidthConstraint: NSLayoutConstraint!
    private var countTrailingConstraint: NSLayoutConstraint!
    private var starWidthConstraint: NSLayoutConstraint!
    private var itemURL: URL?
    private var isFavorited = false
    private var onToggleFavorite: ((URL) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)
        imageView = iconView

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.cell?.truncatesLastVisibleLine = true
        nameLabel.isEditable = false
        nameLabel.isSelectable = false
        nameLabel.isBordered = false
        nameLabel.backgroundColor = .clear
        addSubview(nameLabel)
        textField = nameLabel

        // Configure star button
        starButton.translatesAutoresizingMaskIntoConstraints = false
        starButton.bezelStyle = .inline
        starButton.isBordered = false
        starButton.imagePosition = .imageOnly
        starButton.imageScaling = .scaleProportionallyDown
        starButton.target = self
        starButton.action = #selector(starClicked)
        addSubview(starButton)

        starWidthConstraint = starButton.widthAnchor.constraint(equalToConstant: 16)

        // Configure countLabel
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right
        countLabel.isEditable = false
        countLabel.isSelectable = false
        countLabel.isBordered = false
        countLabel.backgroundColor = .clear
        addSubview(countLabel)

        // Create the width constraint but don't activate it yet
        countMinWidthConstraint = countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 30)
        countTrailingConstraint = countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Star sits between name and count
            starButton.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 4),
            starButton.trailingAnchor.constraint(equalTo: countLabel.leadingAnchor, constant: -4),
            starButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            starButton.heightAnchor.constraint(equalToConstant: 16),
            starWidthConstraint,

            countTrailingConstraint,
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // Make name compress first
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        starButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
    }

    func configure(with item: FolderItem, indentLevel: Int, outlineView: NSOutlineView, isFavorite: Bool = false, onToggleFavorite: ((URL) -> Void)? = nil) {
        self.itemURL = item.url
        self.onToggleFavorite = onToggleFavorite

        nameLabel.stringValue = item.name
        nameLabel.textColor = (item.isMarkdown || item.isFolder) ? .labelColor : .secondaryLabelColor

        // Accessibility: announce file type and favorite status to VoiceOver
        let typePrefix = item.isFolder ? "Folder" : "File"
        let favoriteStatus = isFavorite ? ", favorited" : ""
        setAccessibilityLabel("\(typePrefix): \(item.name)\(favoriteStatus)")

        iconView.image = icon(for: item)
        iconView.contentTintColor = item.isFolder ? .systemBlue : (item.isMarkdown ? .labelColor : .secondaryLabelColor)

        // Adjust trailing padding to compensate for indentation
        let indentationOffset = CGFloat(indentLevel) * outlineView.indentationPerLevel
        countTrailingConstraint.constant = -(4 + indentationOffset)

        // Star for markdown files only
        if item.isMarkdown {
            self.isFavorited = isFavorite
            let starName = isFavorite ? "star.fill" : "star"
            starButton.image = NSImage(systemSymbolName: starName, accessibilityDescription: isFavorite ? "Unfavorite" : "Favorite")
            starButton.contentTintColor = isFavorite ? .systemYellow : .tertiaryLabelColor
            starButton.isHidden = false
            starWidthConstraint.constant = 16
        } else {
            starButton.isHidden = true
            starWidthConstraint.constant = 0
        }

        // Show markdown count for folders only
        if item.isFolder && item.markdownCount > 0 {
            countLabel.stringValue = "\(item.markdownCount)"
            countLabel.isHidden = false
            countMinWidthConstraint.isActive = true
        } else {
            countLabel.stringValue = ""
            countLabel.isHidden = true
            countMinWidthConstraint.isActive = false
        }
    }

    @objc private func starClicked() {
        guard let url = itemURL else { return }
        onToggleFavorite?(url)

        // Toggle star appearance immediately for instant feedback
        isFavorited.toggle()
        let starName = isFavorited ? "star.fill" : "star"
        starButton.image = NSImage(systemSymbolName: starName, accessibilityDescription: isFavorited ? "Unfavorite" : "Favorite")
        starButton.contentTintColor = isFavorited ? .systemYellow : .tertiaryLabelColor
    }

    private func icon(for item: FolderItem) -> NSImage? {
        let name: String
        if item.isFolder {
            name = "folder.fill"
        } else if item.isMarkdown {
            name = "doc.text.fill"
        } else {
            name = "doc.fill"
        }
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }
}

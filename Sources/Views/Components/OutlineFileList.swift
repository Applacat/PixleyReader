import SwiftUI
import AppKit

// MARK: - NSOutlineView Wrapper

/// Native macOS file browser using NSOutlineView.
/// Single-column outline with disclosure triangles, like iPhone Files app.
struct OutlineFileList: NSViewRepresentable {

    let items: [FolderItem]
    @Binding var selection: URL?

    func makeNSView(context: Context) -> NSScrollView {
        // Outline view
        let outlineView = NSOutlineView()
        outlineView.headerView = nil
        outlineView.indentationPerLevel = 10
        outlineView.rowSizeStyle = .default
        outlineView.rowHeight = 24  // Explicit row height for consistency
        outlineView.selectionHighlightStyle = .sourceList  // macOS source list style
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
        
        // Only update if data actually changed
        let itemsChanged = context.coordinator.items.count != items.count
        
        if itemsChanged {
            // Save expansion state before reloading
            let expandedItems = context.coordinator.saveExpansionState(outlineView: outlineView)
            
            // Update data
            context.coordinator.items = items
            context.coordinator.selection = _selection
            outlineView.reloadData()
            
            // Restore expansion state
            context.coordinator.restoreExpansionState(outlineView: outlineView, expandedItems: expandedItems)
        } else {
            // Just update the binding reference
            context.coordinator.selection = _selection
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(items: items, selection: _selection)
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {

        var items: [FolderItem]
        var selection: Binding<URL?>
        weak var outlineView: NSOutlineView?
        private var hasPerformedInitialExpansion = false

        /// Static placeholder to avoid repeated allocations in data source methods
        /// This is used only as a safety fallback and should never actually appear in UI
        private static let placeholderItem = FolderItem(
            url: URL(fileURLWithPath: "/"),
            isFolder: false,
            markdownCount: 0
        )

        init(items: [FolderItem], selection: Binding<URL?>) {
            self.items = items
            self.selection = selection
        }
        
        // MARK: - Expansion State Management
        
        func saveExpansionState(outlineView: NSOutlineView) -> Set<String> {
            var expandedPaths = Set<String>()
            
            func collectExpanded(_ item: Any?) {
                if let folderItem = item as? FolderItem {
                    if outlineView.isItemExpanded(folderItem) {
                        expandedPaths.insert(folderItem.url.path)
                    }
                    if let children = folderItem.children {
                        for child in children where child.isFolder {
                            collectExpanded(child)
                        }
                    }
                } else {
                    // Root level
                    for rootItem in items where rootItem.isFolder {
                        collectExpanded(rootItem)
                    }
                }
            }
            
            collectExpanded(nil)
            return expandedPaths
        }
        
        func restoreExpansionState(outlineView: NSOutlineView, expandedItems: Set<String>) {
            func restore(_ item: Any?) {
                if let folderItem = item as? FolderItem {
                    if expandedItems.contains(folderItem.url.path) {
                        outlineView.expandItem(folderItem, expandChildren: false)
                    }
                    if let children = folderItem.children {
                        for child in children where child.isFolder {
                            restore(child)
                        }
                    }
                } else {
                    // Root level
                    for rootItem in items where rootItem.isFolder {
                        restore(rootItem)
                    }
                }
            }
            
            // Expand all on first load (welcome experience)
            if !hasPerformedInitialExpansion {
                expandAllInitial(outlineView: outlineView, items: items)
                hasPerformedInitialExpansion = true
            } else {
                restore(nil)
            }
        }
        
        private func expandAllInitial(outlineView: NSOutlineView, items: [FolderItem]) {
            for item in items {
                if item.isFolder {
                    outlineView.expandItem(item, expandChildren: false)
                    if let children = item.children {
                        expandAllInitial(outlineView: outlineView, items: children)
                    }
                }
            }
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

            // Configure content with indentation awareness
            cell.configure(with: folderItem, indentLevel: indentLevel, outlineView: outlineView)

            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let outlineView = notification.object as? NSOutlineView else { return }
            let selectedRow = outlineView.selectedRow
            guard selectedRow >= 0,
                  let item = outlineView.item(atRow: selectedRow) as? FolderItem else {
                return
            }

            // Files: Only update selection for markdown files
            // Non-markdown files can be selected but won't open
            if item.isMarkdown {
                selection.wrappedValue = item.url
            } else if item.isFolder {
                // Folders: toggle expansion on click, then deselect
                if outlineView.isItemExpanded(item) {
                    outlineView.collapseItem(item)
                } else {
                    outlineView.expandItem(item)
                }
                // Deselect folder so clicking again triggers selection change
                outlineView.deselectRow(selectedRow)
            }
        }

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            // Allow selecting everything - folders expand/collapse, files open
            return true
        }

    }
}

// MARK: - File Cell View

/// Custom cell view with icon, name, and markdown count badge for folders.
final class FileCellView: NSTableCellView {

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private var countMinWidthConstraint: NSLayoutConstraint!
    private var countTrailingConstraint: NSLayoutConstraint!

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
            
            // Name should compress before count gets clipped
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -8),

            countTrailingConstraint,
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // Make name compress first, count stays visible
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
    }

    func configure(with item: FolderItem, indentLevel: Int, outlineView: NSOutlineView) {
        nameLabel.stringValue = item.name
        nameLabel.textColor = (item.isMarkdown || item.isFolder) ? .labelColor : .secondaryLabelColor

        iconView.image = icon(for: item)
        iconView.contentTintColor = item.isFolder ? .systemBlue : (item.isMarkdown ? .labelColor : .secondaryLabelColor)

        // Adjust trailing padding to compensate for indentation
        // NSOutlineView shifts content right, but doesn't resize the cell
        let indentationOffset = CGFloat(indentLevel) * outlineView.indentationPerLevel
        countTrailingConstraint.constant = -(4 + indentationOffset)

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

import SwiftUI
import AppKit

public struct ParentFolderTreeView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.indent")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.orange)

                Text("PARENT TREE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))

                Spacer()

                // Orientation Toggle Button
                Button(action: { appState.toggleLeftPaneOrientation() }) {
                    Image(systemName: appState.leftPaneOrientation == .horizontal ? "rectangle.split.1x2" : "rectangle.split.2x1")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(3)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .help(appState.leftPaneOrientation == .horizontal ? "Switch to Stacked View" : "Switch to Columns View")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: NSColor(red: 0.16, green: 0.17, blue: 0.19, alpha: 1.0)))

            Divider().background(Color.black.opacity(0.4))

            // Ancestor Breadcrumb Trail
            if let current = appState.currentFolderURL {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        Image(systemName: "folder.tree")
                            .font(.system(size: 9))
                            .foregroundColor(.orange.opacity(0.8))

                        ForEach(ancestorChain(for: current), id: \.path) { folderURL in
                            let isCurrent = folderURL.path == current.path
                            let isParent = folderURL.path == appState.parentFolderURL?.path

                            Button(action: { appState.navigateToFolder(folderURL) }) {
                                Text(folderURL.lastPathComponent.isEmpty ? "/" : folderURL.lastPathComponent)
                                    .font(.system(size: 9.5, weight: (isCurrent || isParent) ? .bold : .regular, design: .monospaced))
                                    .foregroundColor(isCurrent ? .orange : (isParent ? .yellow : .white.opacity(0.7)))
                                    .padding(.horizontal, 3)
                                    .padding(.vertical, 1)
                                    .background((isCurrent || isParent) ? Color.white.opacity(0.08) : Color.clear)
                                    .cornerRadius(2)
                            }
                            .buttonStyle(.plain)
                            .help(folderURL.path)

                            if folderURL.path != current.path {
                                Text("›")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white.opacity(0.3))
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .background(Color.black.opacity(0.25))
                Divider().background(Color.white.opacity(0.04))
            }

            // Scrollable Folder Tree
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    // 1. Parent Folder Tree Section
                    if let parent = appState.parentFolderURL {
                        HStack(spacing: 4) {
                            Text("PARENT FOLDER")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundColor(.yellow.opacity(0.75))

                            Spacer()

                            Button(action: { NSWorkspace.shared.activateFileViewerSelecting([parent]) }) {
                                Image(systemName: "arrow.up.forward.app")
                                    .font(.system(size: 8.5))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                            .help("Reveal in Finder")
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                        .padding(.bottom, 2)

                        // Render Parent node as root of active tree
                        FolderTreeNodeRow(
                            folderURL: parent,
                            displayName: parent.lastPathComponent,
                            depth: 0,
                            appState: appState,
                            isParentBadge: true
                        )
                    }

                    // 2. Quick Access / Library Roots Section
                    Text("PLACES")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                        .padding(.horizontal, 8)
                        .padding(.top, 10)
                        .padding(.bottom, 2)

                    ForEach(appState.quickAccessFolders) { item in
                        FolderTreeNodeRow(
                            folderURL: item.url,
                            displayName: item.name,
                            depth: 0,
                            appState: appState,
                            iconOverride: iconForPlace(item.name)
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .background(Color(nsColor: NSColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1.0)))
        }
    }

    private func ancestorChain(for url: URL) -> [URL] {
        var chain: [URL] = []
        var current = url.resolvingSymlinksInPath().standardizedFileURL
        while current.path != "/" && current.path != current.deletingLastPathComponent().resolvingSymlinksInPath().path {
            chain.insert(current, at: 0)
            current = current.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        }
        chain.insert(current, at: 0)
        return chain
    }

    private func iconForPlace(_ name: String) -> String {
        switch name {
        case "Music": return "music.note"
        case "Downloads": return "arrow.down.circle"
        case "Desktop": return "display"
        case "Home": return "house"
        default: return "folder"
        }
    }
}

// Recursive Tree Node Row View
public struct FolderTreeNodeRow: View {
    let folderURL: URL
    let displayName: String
    let depth: Int
    @ObservedObject var appState: AppState
    var isParentBadge: Bool = false
    var iconOverride: String? = nil

    @State private var subdirectories: [URL] = []
    @State private var hasScanned: Bool = false

    private var isExpanded: Bool {
        appState.isFolderExpanded(folderURL)
    }

    private var isCurrent: Bool {
        appState.currentFolderURL?.resolvingSymlinksInPath().path == folderURL.resolvingSymlinksInPath().path
    }

    private var isParent: Bool {
        appState.parentFolderURL?.resolvingSymlinksInPath().path == folderURL.resolvingSymlinksInPath().path
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            // Main Folder Row
            HStack(spacing: 4) {
                // Indentation
                if depth > 0 {
                    Spacer().frame(width: CGFloat(depth * 14))
                }

                // Expand / Collapse Chevron Button
                Button(action: {
                    toggleExpand()
                }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(.white.opacity(0.45))
                        .frame(width: 14, height: 16)
                }
                .buttonStyle(.plain)

                // Folder Icon & Name
                Button(action: {
                    appState.navigateToFolder(folderURL)
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: folderIcon)
                            .font(.system(size: 10.5))
                            .foregroundColor(iconColor)
                            .frame(width: 14)

                        Text(displayName)
                            .font(.system(size: 11, weight: (isCurrent || isParent) ? .bold : .regular))
                            .foregroundColor(textColor)
                            .lineLimit(1)

                        Spacer()

                        if isParentBadge {
                            Text("PARENT")
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(Color.yellow)
                                .cornerRadius(2)
                        } else if isCurrent {
                            Text("ACTIVE")
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(Color.orange)
                                .cornerRadius(2)
                        }
                    }
                    .padding(.vertical, 3)
                    .padding(.trailing, 6)
                    .background(rowBackground)
                    .cornerRadius(3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)

            // Child subdirectories if expanded
            if isExpanded {
                ForEach(subdirectories, id: \.path) { childURL in
                    FolderTreeNodeRow(
                        folderURL: childURL,
                        displayName: childURL.lastPathComponent,
                        depth: depth + 1,
                        appState: appState
                    )
                }
            }
        }
        .onAppear {
            if isExpanded && !hasScanned {
                loadSubdirectories()
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded && !hasScanned {
                loadSubdirectories()
            }
        }
    }

    private func toggleExpand() {
        appState.toggleFolderExpansion(folderURL)
        if appState.isFolderExpanded(folderURL) && !hasScanned {
            loadSubdirectories()
        }
    }

    private func loadSubdirectories() {
        let fm = FileManager.default
        let resolved = folderURL.resolvingSymlinksInPath().standardizedFileURL
        guard let items = try? fm.contentsOfDirectory(
            at: resolved,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            subdirectories = []
            hasScanned = true
            return
        }

        self.subdirectories = items
            .map { $0.resolvingSymlinksInPath().standardizedFileURL }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        self.hasScanned = true
    }

    private var folderIcon: String {
        if let icon = iconOverride { return icon }
        if isCurrent { return "folder.fill" }
        if isParent { return "folder.fill" }
        return isExpanded ? "folder.fill" : "folder"
    }

    private var iconColor: Color {
        if isCurrent { return .orange }
        if isParent { return .yellow }
        if iconOverride != nil { return .white.opacity(0.6) }
        return .white.opacity(0.55)
    }

    private var textColor: Color {
        if isCurrent { return .orange }
        if isParent { return .yellow }
        return .white.opacity(0.85)
    }

    private var rowBackground: Color {
        if isCurrent { return Color.orange.opacity(0.18) }
        if isParent { return Color.yellow.opacity(0.12) }
        return Color.clear
    }
}

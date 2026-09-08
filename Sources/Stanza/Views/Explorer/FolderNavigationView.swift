import SwiftUI

public struct FolderNavigationView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.orange)

                Text("EXPLORER")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                // Navigate Up to Parent Button
                Button(action: { appState.navigateUpToParent() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 10, weight: .bold))
                        Text("Up")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(appState.parentFolderURL != nil ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
                    .foregroundColor(appState.parentFolderURL != nil ? .white : .white.opacity(0.25))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .disabled(appState.parentFolderURL == nil)
                .help("Go to Parent Folder")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: NSColor(red: 0.17, green: 0.18, blue: 0.20, alpha: 1.0)))

            Divider().background(Color.black.opacity(0.4))

            // Current Path Banner
            if let current = appState.currentFolderURL {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color.orange)

                    Text(current.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.2))
                Divider().background(Color.white.opacity(0.04))
            }

            // Folder List
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    // Parent folder entry (..)
                    if let parent = appState.parentFolderURL {
                        Button(action: { appState.navigateToFolder(parent) }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.turn.left.up")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.5))
                                    .frame(width: 16)

                                Text(".. [\(parent.lastPathComponent)]")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.75))
                                    .lineLimit(1)

                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Parent directory: \(parent.path)")
                    }

                    // Sibling & Current Folders Section
                    if !appState.siblingFolders.isEmpty {
                        Text("FOLDERS IN PARENT")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                            .padding(.horizontal, 8)
                            .padding(.top, 6)
                            .padding(.bottom, 2)

                        ForEach(appState.siblingFolders) { item in
                            let isCurrent = item.url.path == appState.currentFolderURL?.path

                            Button(action: { appState.navigateToFolder(item.url) }) {
                                HStack(spacing: 6) {
                                    Image(systemName: isCurrent ? "folder.fill" : "folder")
                                        .font(.system(size: 11))
                                        .foregroundColor(isCurrent ? Color.orange : Color.white.opacity(0.6))
                                        .frame(width: 16)

                                    Text(item.name)
                                        .font(.system(size: 11, weight: isCurrent ? .bold : .regular))
                                        .foregroundColor(isCurrent ? Color.orange : Color.white.opacity(0.9))
                                        .lineLimit(1)

                                    Spacer()

                                    if isCurrent {
                                        Text("ACTIVE")
                                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                                            .foregroundColor(.black)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.orange)
                                            .cornerRadius(3)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(isCurrent ? Color.orange.opacity(0.18) : Color.clear)
                                .cornerRadius(4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(item.url.path)
                        }
                    }

                    // Subfolders of Current Directory
                    if !appState.childFolders.isEmpty {
                        Text("SUBDIRECTORIES")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                            .padding(.horizontal, 8)
                            .padding(.top, 8)
                            .padding(.bottom, 2)

                        ForEach(appState.childFolders) { item in
                            Button(action: { appState.navigateToFolder(item.url) }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 11))
                                        .foregroundColor(Color.cyan.opacity(0.7))
                                        .frame(width: 16)

                                    Text(item.name)
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.85))
                                        .lineLimit(1)

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 9))
                                        .foregroundColor(.white.opacity(0.2))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(item.url.path)
                        }
                    }

                    // Quick Access Section
                    Text("QUICK ACCESS")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                        .padding(.horizontal, 8)
                        .padding(.top, 10)
                        .padding(.bottom, 2)

                    ForEach(appState.quickAccessFolders) { item in
                        let isSelected = item.url.path == appState.currentFolderURL?.path
                        Button(action: { appState.navigateToFolder(item.url) }) {
                            HStack(spacing: 6) {
                                Image(systemName: quickAccessIcon(for: item.name))
                                    .font(.system(size: 11))
                                    .foregroundColor(isSelected ? Color.orange : Color.white.opacity(0.55))
                                    .frame(width: 16)

                                Text(item.name)
                                    .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                                    .foregroundColor(isSelected ? Color.orange : .white.opacity(0.85))
                                    .lineLimit(1)

                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isSelected ? Color.orange.opacity(0.18) : Color.clear)
                            .cornerRadius(4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            }
            .background(Color(nsColor: NSColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 1.0)))
        }
    }

    private func quickAccessIcon(for name: String) -> String {
        switch name {
        case "Music": return "music.note"
        case "Downloads": return "arrow.down.circle"
        case "Desktop": return "display"
        case "Home": return "house"
        default: return "folder"
        }
    }
}

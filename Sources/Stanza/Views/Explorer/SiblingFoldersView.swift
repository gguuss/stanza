import SwiftUI

public struct SiblingFoldersView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.orange)

                Text("CURRENT & SIBLINGS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))

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
                .help("Go to Parent Folder (Cmd+Opt+Up)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: NSColor(red: 0.16, green: 0.17, blue: 0.19, alpha: 1.0)))

            Divider().background(Color.black.opacity(0.4))

            // Parent Folder Banner
            if let parent = appState.parentFolderURL {
                Button(action: { appState.navigateToFolder(parent) }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.turn.left.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.yellow.opacity(0.8))

                        Text(".. / \(parent.lastPathComponent)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)

                        Spacer()

                        Text("PARENT")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.yellow.opacity(0.85))
                            .cornerRadius(2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.yellow.opacity(0.08))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Jump to parent: \(parent.path)")

                Divider().background(Color.white.opacity(0.04))
            }

            // Scrollable List of Sibling Folders & Subdirectories
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    // Sibling Folders Section
                    if !appState.siblingFolders.isEmpty {
                        HStack {
                            Text("SIBLING FOLDERS")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.35))

                            Spacer()

                            Text("\(appState.siblingFolders.count)")
                                .font(.system(size: 8.5, design: .monospaced))
                                .foregroundColor(.white.opacity(0.3))
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                        .padding(.bottom, 2)

                        ForEach(appState.siblingFolders) { item in
                            let isCurrent = item.url.path == appState.currentFolderURL?.path

                            Button(action: { appState.navigateToFolder(item.url) }) {
                                HStack(spacing: 6) {
                                    Image(systemName: isCurrent ? "speaker.wave.2.fill" : "folder")
                                        .font(.system(size: 10.5))
                                        .foregroundColor(isCurrent ? Color.orange : Color.white.opacity(0.6))
                                        .frame(width: 16)

                                    Text(item.name)
                                        .font(.system(size: 11, weight: isCurrent ? .bold : .regular))
                                        .foregroundColor(isCurrent ? Color.orange : Color.white.opacity(0.9))
                                        .lineLimit(1)

                                    Spacer()

                                    if isCurrent {
                                        Text("\(appState.queue.count) files")
                                            .font(.system(size: 8.5, design: .monospaced))
                                            .foregroundColor(.orange.opacity(0.9))

                                        Text("ACTIVE")
                                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                            .foregroundColor(.black)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.orange)
                                            .cornerRadius(3)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(isCurrent ? Color.orange.opacity(0.18) : Color.white.opacity(0.02))
                                .cornerRadius(4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(item.url.path)
                        }
                    }

                    // Subdirectories Section
                    if !appState.childFolders.isEmpty {
                        HStack {
                            Text("SUBDIRECTORIES")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.35))

                            Spacer()

                            Text("\(appState.childFolders.count)")
                                .font(.system(size: 8.5, design: .monospaced))
                                .foregroundColor(.white.opacity(0.3))
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 10)
                        .padding(.bottom, 2)

                        ForEach(appState.childFolders) { item in
                            Button(action: { appState.navigateToFolder(item.url) }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 10.5))
                                        .foregroundColor(Color.cyan.opacity(0.75))
                                        .frame(width: 16)

                                    Text(item.name)
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.85))
                                        .lineLimit(1)

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 8.5))
                                        .foregroundColor(.white.opacity(0.25))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.02))
                                .cornerRadius(4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(item.url.path)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .background(Color(nsColor: NSColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 1.0)))

            Divider().background(Color.black.opacity(0.3))

            // Footer info
            if let current = appState.currentFolderURL {
                HStack(spacing: 4) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.4))

                    Text(current.lastPathComponent)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)

                    Spacer()

                    Text("\(appState.queue.count) tracks")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.orange.opacity(0.8))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.25))
            }
        }
    }
}

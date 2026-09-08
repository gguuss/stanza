import SwiftUI

public struct FileExplorerSplitView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        Group {
            if appState.leftPaneOrientation == .horizontal {
                // 3 columns: [ Parent Tree ] | [ Current & Sibling Folders ] | [ Media Files ]
                HSplitView {
                    ParentFolderTreeView(appState: appState)
                        .frame(minWidth: 160, idealWidth: 200, maxWidth: 360)

                    SiblingFoldersView(appState: appState)
                        .frame(minWidth: 160, idealWidth: 210, maxWidth: 360)

                    FolderFilesTableView(appState: appState)
                        .frame(minWidth: 320, maxWidth: .infinity)
                }
            } else {
                // Stacked: [ [ Parent Tree ] / [ Current & Sibling Folders ] ] | [ Media Files ]
                HSplitView {
                    VSplitView {
                        ParentFolderTreeView(appState: appState)
                            .frame(minHeight: 90, idealHeight: 150, maxHeight: .infinity)

                        SiblingFoldersView(appState: appState)
                            .frame(minHeight: 90, idealHeight: 150, maxHeight: .infinity)
                    }
                    .frame(minWidth: 180, idealWidth: 240, maxWidth: 400)

                    FolderFilesTableView(appState: appState)
                        .frame(minWidth: 320, maxWidth: .infinity)
                }
            }
        }
    }
}

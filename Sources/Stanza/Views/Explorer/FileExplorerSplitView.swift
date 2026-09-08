import SwiftUI

public struct FileExplorerSplitView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        HSplitView {
            // Left Pane: Folder Navigation (Parent, Siblings, Subdirectories)
            FolderNavigationView(appState: appState)
                .frame(minWidth: 170, idealWidth: 220, maxWidth: 350)

            // Right Pane: Playable Media Files in Current Folder
            FolderFilesTableView(appState: appState)
                .frame(minWidth: 340, maxWidth: .infinity)
        }
    }
}

import Foundation

public enum FolderKind: String, Sendable {
    case parent
    case current
    case sibling
    case child
    case quickAccess
}

public struct FolderItem: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let kind: FolderKind
    public let audioFileCount: Int?

    public init(url: URL, name: String? = nil, kind: FolderKind = .sibling, audioFileCount: Int? = nil) {
        self.url = url
        self.name = name ?? url.lastPathComponent
        self.kind = kind
        self.audioFileCount = audioFileCount
    }
}

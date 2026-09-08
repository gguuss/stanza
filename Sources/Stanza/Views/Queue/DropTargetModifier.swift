import SwiftUI
import UniformTypeIdentifiers

public func extractURLsFromItem(_ item: Any?) -> [URL] {
    guard let item = item else { return [] }
    var result: [URL] = []

    if let url = item as? URL {
        result.append(url)
    } else if let nsURL = item as? NSURL {
        result.append(nsURL as URL)
    } else if let urlArray = item as? [URL] {
        result.append(contentsOf: urlArray)
    } else if let nsURLArray = item as? [NSURL] {
        result.append(contentsOf: nsURLArray.map { $0 as URL })
    } else if let pathArray = item as? [String] {
        for path in pathArray {
            let clean = path.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.hasPrefix("file://") {
                if let u = URL(string: clean) { result.append(u) }
            } else {
                result.append(URL(fileURLWithPath: clean))
            }
        }
    } else if let nsArray = item as? NSArray {
        for element in nsArray {
            result.append(contentsOf: extractURLsFromItem(element))
        }
    } else if let str = item as? String {
        let clean = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("file://") {
            if let u = URL(string: clean) { result.append(u) }
        } else {
            result.append(URL(fileURLWithPath: clean))
        }
    } else if let data = item as? Data {
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
            result.append(contentsOf: extractURLsFromItem(plist))
        } else if let str = String(data: data, encoding: .utf8) {
            result.append(contentsOf: extractURLsFromItem(str))
        } else if let unarchived = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSURL.self, from: data) {
            result.append(unarchived as URL)
        }
    }

    return result
}

public struct DropTargetModifier: ViewModifier {
    let onDropURLs: ([URL]) -> Void
    @State private var isTargeted: Bool = false

    public func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isTargeted ? Color(red: 1.0, green: 0.45, blue: 0.15) : Color.clear, lineWidth: 2)
                    .padding(2)
            )
            .onDrop(of: [
                UTType.fileURL,
                UTType.item,
                UTType.data,
                UTType.content
            ], isTargeted: $isTargeted) { providers in
                let group = DispatchGroup()
                var collectedURLs: [URL] = []
                let lock = NSLock()

                for provider in providers {
                    group.enter()

                    let typesToTry = [
                        UTType.fileURL.identifier,
                        "NSFilenamesPboardType",
                        UTType.utf8PlainText.identifier,
                        UTType.item.identifier
                    ]

                    var didAttemptLoad = false
                    for typeId in typesToTry {
                        if provider.hasItemConformingToTypeIdentifier(typeId) {
                            didAttemptLoad = true
                            provider.loadItem(forTypeIdentifier: typeId, options: nil) { item, _ in
                                let urls = extractURLsFromItem(item)
                                if !urls.isEmpty {
                                    lock.lock()
                                    collectedURLs.append(contentsOf: urls)
                                    lock.unlock()
                                }
                                group.leave()
                            }
                            break
                        }
                    }

                    if !didAttemptLoad {
                        _ = provider.loadObject(ofClass: URL.self) { fallbackURL, _ in
                            if let fallbackURL = fallbackURL {
                                lock.lock()
                                collectedURLs.append(fallbackURL)
                                lock.unlock()
                            }
                            group.leave()
                        }
                    }
                }

                group.notify(queue: .main) {
                    if !collectedURLs.isEmpty {
                        self.onDropURLs(collectedURLs)
                    }
                }
                return true
            }
    }
}

extension View {
    public func audioFileDropTarget(onDrop: @escaping ([URL]) -> Void) -> some View {
        self.modifier(DropTargetModifier(onDropURLs: onDrop))
    }
}

private func resolveAudioURLs(from urls: [URL]) -> [URL] {
    let supportedExtensions: Set<String> = [
        "mp3", "wav", "wave", "flac", "m4a", "aac", "aiff", "aif", "caf", "alac", "ogg", "oga", "opus", "mp4", "m4b", "m4r"
    ]

    var results: [URL] = []
    let fileManager = FileManager.default

    for url in urls {
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDir) {
            if isDir.boolValue {
                if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                    for case let fileURL as URL in enumerator {
                        if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                            results.append(fileURL)
                        }
                    }
                }
            } else {
                if supportedExtensions.contains(url.pathExtension.lowercased()) {
                    results.append(url)
                }
            }
        }
    }
    return results
}

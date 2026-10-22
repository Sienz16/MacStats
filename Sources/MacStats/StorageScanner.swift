import Foundation

struct JunkCategory: Identifiable {
    let id: String
    let name: String
    let icon: String
    /// Folders scanned for this category. Clean trashes every item directly inside these folders.
    let paths: [URL]
    var sizeBytes: Int64 = 0
    var itemCount: Int = 0
    var isSelected: Bool = true
}

struct StorageBucket: Identifiable {
    let id: String
    let name: String
    var sizeBytes: Int64 = 0
}

/// Scans well-known cache/log/junk locations and a top-level "About This Mac"-style
/// storage breakdown. All sizes are computed off the main actor; cleaning moves items
/// to the Trash (never a hard delete) so it stays recoverable.
actor StorageScanner {
    private let fm = FileManager.default
    private var home: URL { fm.homeDirectoryForCurrentUser }

    func scanJunk() -> [JunkCategory] {
        let candidates: [(id: String, name: String, icon: String, paths: [URL])] = [
            ("caches", "App Caches", "trash.circle", [home.appending(path: "Library/Caches")]),
            ("logs", "Log Files", "doc.text.magnifyingglass", [home.appending(path: "Library/Logs")]),
            ("crashReports", "Diagnostic Reports", "exclamationmark.triangle", [home.appending(path: "Library/Logs/DiagnosticReports")]),
            ("xcodeDerived", "Xcode DerivedData", "hammer", [home.appending(path: "Library/Developer/Xcode/DerivedData")]),
            ("xcodeArchives", "Xcode Archives", "archivebox", [home.appending(path: "Library/Developer/Xcode/Archives")]),
            ("iosDeviceSupport", "iOS Device Support", "iphone", [home.appending(path: "Library/Developer/Xcode/iOS DeviceSupport")]),
            ("homebrew", "Homebrew Cache", "mug", [home.appending(path: "Library/Caches/Homebrew")]),
            ("npm", "npm Cache", "shippingbox", [home.appending(path: ".npm/_cacache")]),
            ("trash", "Trash", "trash", [home.appending(path: ".Trash")]),
        ]

        var results: [JunkCategory] = []
        for c in candidates {
            let existing = c.paths.filter { fm.fileExists(atPath: $0.path) }
            guard !existing.isEmpty else { continue }
            let (size, count) = sizeAndCount(of: existing)
            guard size > 0 else { continue }
            results.append(JunkCategory(id: c.id, name: c.name, icon: c.icon, paths: existing, sizeBytes: size, itemCount: count))
        }
        return results.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    func scanBreakdown() -> [StorageBucket] {
        let folders: [(id: String, name: String, path: URL)] = [
            ("documents", "Documents", home.appending(path: "Documents")),
            ("desktop", "Desktop", home.appending(path: "Desktop")),
            ("downloads", "Downloads", home.appending(path: "Downloads")),
            ("pictures", "Pictures", home.appending(path: "Pictures")),
            ("movies", "Movies", home.appending(path: "Movies")),
            ("music", "Music", home.appending(path: "Music")),
            ("developer", "Developer", home.appending(path: "Library/Developer")),
            ("caches", "Caches", home.appending(path: "Library/Caches")),
        ]

        var buckets: [StorageBucket] = []
        for f in folders {
            guard fm.fileExists(atPath: f.path.path) else { continue }
            let size = sizeOf(f.path)
            guard size > 0 else { continue }
            buckets.append(StorageBucket(id: f.id, name: f.name, sizeBytes: size))
        }
        return buckets.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// Moves every item inside the category's folders to the Trash. Returns the number
    /// of items successfully trashed.
    func clean(_ category: JunkCategory) -> Int {
        var trashed = 0
        for folder in category.paths {
            guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
            for item in items {
                if (try? fm.trashItem(at: item, resultingItemURL: nil)) != nil {
                    trashed += 1
                }
            }
        }
        return trashed
    }

    private func sizeAndCount(of folders: [URL]) -> (Int64, Int) {
        var total: Int64 = 0
        var count = 0
        for folder in folders {
            guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
            count += items.count
            for item in items {
                total += sizeOf(item)
            }
        }
        return (total, count)
    }

    private func sizeOf(_ url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        guard isDir.boolValue else {
            return Int64((try? url.resourceValues(forKeys: [.fileAllocatedSizeKey]))?.fileAllocatedSize ?? 0)
        }
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isDirectoryKey]),
                  values.isDirectory != true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}

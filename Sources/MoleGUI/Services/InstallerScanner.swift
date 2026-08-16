import AppKit
import Foundation

/// Leftover installer image found in one of the CLI's scan directories.
struct InstallerFile: Identifiable, Hashable {
    let url: URL
    let size: UInt64
    let source: String
    let modified: Date?

    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var sizeLabel: String { ByteFormat.string(size) }
}

/// `mo installer` is a full-screen keyboard selector with no non-interactive
/// mode: piped into the GUI it draws its menu, reads EOF, and exits having
/// removed nothing. So the GUI does its own read-only scan over the same
/// directories and extensions, and removes through the Trash — the CLI's own
/// default. The Terminal button still hands the job to the real TUI.
enum InstallerScanner {
    /// Mirrors INSTALLER_SCAN_PATHS in mole/bin/installer.sh.
    static var scanDirectories: [URL] {
        let home = NSHomeDirectory()
        return [
            "\(home)/Downloads",
            "\(home)/Desktop",
            "\(home)/Documents",
            "\(home)/Public",
            "\(home)/Library/Downloads",
            "/Users/Shared",
            "/Users/Shared/Downloads",
            "\(home)/Library/Caches/Homebrew",
            "\(home)/Library/Mobile Documents/com~apple~CloudDocs/Downloads",
            "\(home)/Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
            "\(home)/Library/Application Support/Telegram Desktop",
            "\(home)/Downloads/Telegram Desktop"
        ].map { URL(fileURLWithPath: $0) }
    }

    /// `.zip` is deliberately left out: the CLI only takes a zip after peeking
    /// inside for an .app/.pkg payload, and a wrong guess here would offer up
    /// someone's archive.
    static let extensions: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip"]

    private static let maxDepth = 2

    static func scan() async -> [InstallerFile] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: collect())
            }
        }
    }

    private static func collect() -> [InstallerFile] {
        let fm = FileManager.default
        var seen = Set<String>()
        var found: [InstallerFile] = []

        for directory in scanDirectories {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else { continue }
            guard let enumerator = fm.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                if enumerator.level > maxDepth {
                    enumerator.skipDescendants()
                    continue
                }
                guard extensions.contains(url.pathExtension.lowercased()) else { continue }
                guard let values = try? url.resourceValues(forKeys: [
                    .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey
                ]) else { continue }
                guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                guard seen.insert(url.resolvingSymlinksInPath().path).inserted else { continue }

                found.append(
                    InstallerFile(
                        url: url,
                        size: UInt64(values.fileSize ?? 0),
                        source: label(for: url),
                        modified: values.contentModificationDate
                    )
                )
            }
        }

        return found.sorted { $0.size > $1.size }
    }

    private static func label(for url: URL) -> String {
        let path = url.path
        let home = NSHomeDirectory()
        switch path {
        case let p where p.hasPrefix("\(home)/Downloads/Telegram Desktop"): return "Telegram"
        case let p where p.contains("Telegram Desktop"): return "Telegram"
        case let p where p.hasPrefix("\(home)/Downloads"): return "Downloads"
        case let p where p.hasPrefix("\(home)/Desktop"): return "Desktop"
        case let p where p.hasPrefix("\(home)/Documents"): return "Documents"
        case let p where p.hasPrefix("\(home)/Public"): return "Public"
        case let p where p.contains("com~apple~CloudDocs"): return "iCloud"
        case let p where p.contains("Caches/Homebrew"): return "Homebrew"
        case let p where p.contains("Mail Downloads"): return "Mail"
        case let p where p.hasPrefix("/Users/Shared"): return "Shared"
        case let p where p.hasPrefix("\(home)/Library"): return "Library"
        default: return url.deletingLastPathComponent().lastPathComponent
        }
    }

    /// Move to Trash so every removal stays recoverable from Finder.
    /// Returns the files that could not be trashed, with the reason.
    static func moveToTrash(_ files: [InstallerFile]) async -> [(InstallerFile, String)] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var failures: [(InstallerFile, String)] = []
                for file in files {
                    do {
                        try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
                    } catch {
                        failures.append((file, error.localizedDescription))
                    }
                }
                continuation.resume(returning: failures)
            }
        }
    }
}

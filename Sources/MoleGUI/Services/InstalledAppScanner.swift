import AppKit
import Foundation

/// Native inventory of user-installed apps.
///
/// `mo uninstall --list` is the authoritative source — it knows Homebrew cask
/// names and the exact strings `mo uninstall` accepts. But some CLI builds die
/// partway through that scan (an app with an unknown size aborts the loop under
/// `set -e`), leaving a short list. This scanner fills the gap so the GUI never
/// shows fewer apps than the CLI's own interactive selector.
enum InstalledAppScanner {
    /// Mirrors the CLI's app roots. `/System/Applications` is excluded: those
    /// are Apple's, SIP-protected, and not uninstallable.
    static var roots: [String] {
        [
            "/Applications",
            "\(NSHomeDirectory())/Applications"
        ]
    }

    private static let maxDepth = 2

    static func scan() async -> [InstalledApp] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: collect())
            }
        }
    }

    private static func collect() -> [InstalledApp] {
        let fm = FileManager.default
        var apps: [InstalledApp] = []
        var seen = Set<String>()

        for root in roots {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else { continue }
            guard let enumerator = fm.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                if enumerator.level > maxDepth {
                    enumerator.skipDescendants()
                    continue
                }
                guard url.pathExtension == "app" else { continue }
                enumerator.skipDescendants()
                guard seen.insert(url.path).inserted else { continue }
                apps.append(app(at: url))
            }
        }

        return apps
    }

    private static func app(at url: URL) -> InstalledApp {
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary
        let name = (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent

        return InstalledApp(
            name: name,
            bundleId: bundle?.bundleIdentifier,
            source: "App",
            // `mo uninstall` matches on the app name; for Homebrew casks the CLI
            // list supplies the cask name instead and that entry wins the merge.
            uninstallName: name,
            path: url.path,
            size: nil
        )
    }

    /// Bundle size on disk. Walked lazily because a full pass over every app
    /// costs seconds — the list renders first, sizes land as they resolve.
    static func size(of path: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: directorySize(path).map { ByteFormat.string($0) })
            }
        }
    }

    private static func directorySize(_ path: String) -> UInt64? {
        let url = URL(fileURLWithPath: path)
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: []
        ) else { return nil }

        var total: UInt64 = 0
        for case let child as URL in enumerator {
            let values = try? child.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            let bytes = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0
            total += UInt64(max(bytes, 0))
        }
        return total
    }

    /// CLI rows win on metadata; native-only apps are appended so nothing is
    /// missing. Matching is by bundle path, the one stable identity both share.
    static func merge(cli: [InstalledApp], native: [InstalledApp]) -> [InstalledApp] {
        let known = Set(cli.map(\.path))
        return (cli + native.filter { !known.contains($0.path) })
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

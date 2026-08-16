import Foundation

/// Row from `mo uninstall --list` (JSON array).
struct InstalledApp: Codable, Hashable, Identifiable {
    var name: String
    var bundleId: String?
    var source: String?
    var uninstallName: String
    var path: String
    var size: String?

    var id: String { path }

    enum CodingKeys: String, CodingKey {
        case name, path, size, source
        case bundleId = "bundle_id"
        case uninstallName = "uninstall_name"
    }

    var displaySize: String {
        guard let size, !size.isEmpty, size != "--" else { return "—" }
        return size
    }

    var sourceLabel: String {
        source?.isEmpty == false ? (source ?? "App") : "App"
    }
}

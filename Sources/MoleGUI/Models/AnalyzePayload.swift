import Foundation

struct AnalyzePayload: Codable, Hashable {
    var path: String
    var overview: Bool?
    var entries: [AnalyzeEntry]
}

struct AnalyzeEntry: Codable, Hashable, Identifiable {
    var name: String
    var path: String
    var size: UInt64
    var isDir: Bool
    var cleanable: Bool?

    var id: String { path }

    enum CodingKeys: String, CodingKey {
        case name, path, size
        case isDir = "is_dir"
        case cleanable
    }

    var sizeLabel: String { ByteFormat.string(size) }
}

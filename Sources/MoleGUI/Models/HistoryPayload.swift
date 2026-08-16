import Foundation

struct HistoryPayload: Codable, Hashable {
    var logs: HistoryLogs?
    var limit: Int?
    var sessions: [HistorySession]
    var deletions: [HistoryDeletion]

    init(logs: HistoryLogs? = nil, limit: Int? = nil, sessions: [HistorySession] = [], deletions: [HistoryDeletion] = []) {
        self.logs = logs
        self.limit = limit
        self.sessions = sessions
        self.deletions = deletions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        logs = try c.decodeIfPresent(HistoryLogs.self, forKey: .logs)
        limit = try c.decodeIfPresent(Int.self, forKey: .limit)
        sessions = try c.decodeIfPresent([HistorySession].self, forKey: .sessions) ?? []
        deletions = try c.decodeIfPresent([HistoryDeletion].self, forKey: .deletions) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case logs, limit, sessions, deletions
    }
}

struct HistoryLogs: Codable, Hashable {
    var operations: String?
    var deletions: String?
}

struct HistorySession: Codable, Hashable, Identifiable {
    var command: String
    var startedAt: String
    var endedAt: String?
    var items: Int?
    var size: String?
    var operationCount: Int?
    var failedTasks: Int?
    var actions: HistoryActions?

    var id: String {
        "\(command)|\(startedAt)|\(endedAt ?? "")|\(items ?? -1)|\(operationCount ?? -1)|\(size ?? "")"
    }

    enum CodingKeys: String, CodingKey {
        case command, items, size, actions
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case operationCount = "operation_count"
        case failedTasks = "failed_tasks"
    }
}

struct HistoryActions: Codable, Hashable {
    var removed: Int?
    var trashed: Int?
    var skipped: Int?
    var failed: Int?
    var rebuilt: Int?
    var other: Int?
}

struct HistoryDeletion: Codable, Hashable, Identifiable {
    var timestamp: String
    var mode: String?
    var status: String?
    var sizeKb: Int?
    var path: String

    var id: String { "\(timestamp)-\(path)" }

    enum CodingKeys: String, CodingKey {
        case timestamp, mode, status, path
        case sizeKb = "size_kb"
    }

    var sizeLabel: String {
        guard let kb = sizeKb else { return "—" }
        return ByteFormat.string(UInt64(kb) * 1024)
    }
}

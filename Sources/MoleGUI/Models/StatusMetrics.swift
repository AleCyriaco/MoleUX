import Foundation

struct StatusMetrics: Codable, Hashable {
    /// Keep as String — status-go emits fractional ISO-8601 that Foundation's
    /// default `.iso8601` strategy often rejects.
    var collectedAt: String?
    var host: String
    var platform: String
    var uptime: String
    var uptimeSeconds: UInt64
    var procs: UInt64
    var hardware: HardwareInfo
    var healthScore: Int
    var healthScoreMsg: String
    var cpu: CPUStatus
    var gpu: [GPUStatus]
    var memory: MemoryStatus
    var disks: [DiskStatus]
    var trashSize: UInt64
    var trashApprox: Bool
    var diskIO: DiskIOStatus
    var network: [NetworkStatus]
    var batteries: [BatteryStatus]
    var thermal: ThermalStatus
    var topProcesses: [ProcInfo]

    enum CodingKeys: String, CodingKey {
        case collectedAt = "collected_at"
        case host, platform, uptime
        case uptimeSeconds = "uptime_seconds"
        case procs, hardware
        case healthScore = "health_score"
        case healthScoreMsg = "health_score_msg"
        case cpu, gpu, memory, disks
        case trashSize = "trash_size"
        case trashApprox = "trash_approx"
        case diskIO = "disk_io"
        case network, batteries, thermal
        case topProcesses = "top_processes"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        collectedAt = try c.decodeIfPresent(String.self, forKey: .collectedAt)
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? "—"
        platform = try c.decodeIfPresent(String.self, forKey: .platform) ?? "—"
        uptime = try c.decodeIfPresent(String.self, forKey: .uptime) ?? "—"
        uptimeSeconds = try c.decodeIfPresent(UInt64.self, forKey: .uptimeSeconds) ?? 0
        procs = try c.decodeIfPresent(UInt64.self, forKey: .procs) ?? 0
        hardware = try c.decode(HardwareInfo.self, forKey: .hardware)
        healthScore = try c.decodeIfPresent(Int.self, forKey: .healthScore) ?? 0
        healthScoreMsg = try c.decodeIfPresent(String.self, forKey: .healthScoreMsg) ?? ""
        cpu = try c.decode(CPUStatus.self, forKey: .cpu)
        gpu = try c.decodeIfPresent([GPUStatus].self, forKey: .gpu) ?? []
        memory = try c.decode(MemoryStatus.self, forKey: .memory)
        disks = try c.decodeIfPresent([DiskStatus].self, forKey: .disks) ?? []
        trashSize = try c.decodeIfPresent(UInt64.self, forKey: .trashSize) ?? 0
        trashApprox = try c.decodeIfPresent(Bool.self, forKey: .trashApprox) ?? false
        diskIO = try c.decodeIfPresent(DiskIOStatus.self, forKey: .diskIO) ?? DiskIOStatus(readRate: 0, writeRate: 0)
        network = try c.decodeIfPresent([NetworkStatus].self, forKey: .network) ?? []
        batteries = try c.decodeIfPresent([BatteryStatus].self, forKey: .batteries) ?? []
        thermal = try c.decodeIfPresent(ThermalStatus.self, forKey: .thermal) ?? ThermalStatus()
        topProcesses = try c.decodeIfPresent([ProcInfo].self, forKey: .topProcesses) ?? []
    }

    var primaryDisk: DiskStatus? { disks.first }
    var primaryBattery: BatteryStatus? { batteries.first }

    var healthColorName: String {
        switch healthScore {
        case 85...100: return "green"
        case 70..<85: return "yellow"
        case 50..<70: return "orange"
        default: return "red"
        }
    }
}

struct HardwareInfo: Codable, Hashable {
    var model: String
    var cpuModel: String
    var totalRAM: String
    var diskSize: String
    var osVersion: String
    var refreshRate: String?

    enum CodingKeys: String, CodingKey {
        case model
        case cpuModel = "cpu_model"
        case totalRAM = "total_ram"
        case diskSize = "disk_size"
        case osVersion = "os_version"
        case refreshRate = "refresh_rate"
    }
}

struct CPUStatus: Codable, Hashable {
    var usage: Double
    var perCore: [Double]
    var load1: Double
    var load5: Double
    var load15: Double
    var coreCount: Int
    var logicalCPU: Int
    var pCoreCount: Int?
    var eCoreCount: Int?

    enum CodingKeys: String, CodingKey {
        case usage
        case perCore = "per_core"
        case load1, load5, load15
        case coreCount = "core_count"
        case logicalCPU = "logical_cpu"
        case pCoreCount = "p_core_count"
        case eCoreCount = "e_core_count"
    }
}

struct GPUStatus: Codable, Hashable {
    var name: String
    var usage: Double
    var coreCount: Int
    var note: String?

    enum CodingKeys: String, CodingKey {
        case name, usage, note
        case coreCount = "core_count"
    }
}

struct MemoryStatus: Codable, Hashable {
    var used: UInt64
    var total: UInt64
    var available: UInt64
    var usedPercent: Double
    var swapUsed: UInt64
    var swapTotal: UInt64
    var cached: UInt64
    var pressure: String?

    enum CodingKeys: String, CodingKey {
        case used, total, available, cached, pressure
        case usedPercent = "used_percent"
        case swapUsed = "swap_used"
        case swapTotal = "swap_total"
    }
}

struct DiskStatus: Codable, Hashable, Identifiable {
    var mount: String
    var device: String
    var used: UInt64
    var total: UInt64
    var usedPercent: Double
    var fstype: String
    var external: Bool
    var smartStatus: String?
    var purgeable: UInt64?

    var id: String { mount + device }

    enum CodingKeys: String, CodingKey {
        case mount, device, used, total, fstype, external, purgeable
        case usedPercent = "used_percent"
        case smartStatus = "smart_status"
    }

    var freeBytes: UInt64 { total > used ? total - used : 0 }
}

struct DiskIOStatus: Codable, Hashable {
    var readRate: Double
    var writeRate: Double

    init(readRate: Double = 0, writeRate: Double = 0) {
        self.readRate = readRate
        self.writeRate = writeRate
    }

    enum CodingKeys: String, CodingKey {
        case readRate = "read_rate"
        case writeRate = "write_rate"
    }
}

struct NetworkStatus: Codable, Hashable, Identifiable {
    var name: String
    var rxRateMBs: Double
    var txRateMBs: Double
    var ip: String?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, ip
        case rxRateMBs = "rx_rate_mbs"
        case txRateMBs = "tx_rate_mbs"
    }
}

struct BatteryStatus: Codable, Hashable {
    var percent: Double
    var status: String
    var timeLeft: String?
    var health: String?
    var cycleCount: Int?
    var capacity: Int?

    enum CodingKeys: String, CodingKey {
        case percent, status, health, capacity
        case timeLeft = "time_left"
        case cycleCount = "cycle_count"
    }
}

struct ThermalStatus: Codable, Hashable {
    var cpuTemp: Double
    var gpuTemp: Double
    var batteryTemp: Double
    var fanSpeed: Double
    var fanCount: Int?
    var systemPower: Double?
    var adapterPower: Double?
    var batteryPower: Double?

    init(
        cpuTemp: Double = 0,
        gpuTemp: Double = 0,
        batteryTemp: Double = 0,
        fanSpeed: Double = 0,
        fanCount: Int? = nil,
        systemPower: Double? = nil,
        adapterPower: Double? = nil,
        batteryPower: Double? = nil
    ) {
        self.cpuTemp = cpuTemp
        self.gpuTemp = gpuTemp
        self.batteryTemp = batteryTemp
        self.fanSpeed = fanSpeed
        self.fanCount = fanCount
        self.systemPower = systemPower
        self.adapterPower = adapterPower
        self.batteryPower = batteryPower
    }

    enum CodingKeys: String, CodingKey {
        case cpuTemp = "cpu_temp"
        case gpuTemp = "gpu_temp"
        case batteryTemp = "battery_temp"
        case fanSpeed = "fan_speed"
        case fanCount = "fan_count"
        case systemPower = "system_power"
        case adapterPower = "adapter_power"
        case batteryPower = "battery_power"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cpuTemp = try c.decodeIfPresent(Double.self, forKey: .cpuTemp) ?? 0
        gpuTemp = try c.decodeIfPresent(Double.self, forKey: .gpuTemp) ?? 0
        batteryTemp = try c.decodeIfPresent(Double.self, forKey: .batteryTemp) ?? 0
        fanSpeed = try c.decodeIfPresent(Double.self, forKey: .fanSpeed) ?? 0
        fanCount = try c.decodeIfPresent(Int.self, forKey: .fanCount)
        systemPower = try c.decodeIfPresent(Double.self, forKey: .systemPower)
        adapterPower = try c.decodeIfPresent(Double.self, forKey: .adapterPower)
        batteryPower = try c.decodeIfPresent(Double.self, forKey: .batteryPower)
    }
}

struct ProcInfo: Codable, Hashable, Identifiable {
    var pid: Int
    var ppid: Int?
    var name: String
    var command: String?
    var cpu: Double
    var memory: Double
    var memoryBytes: UInt64?

    var id: Int { pid }

    enum CodingKeys: String, CodingKey {
        case pid, ppid, name, command, cpu, memory
        case memoryBytes = "memory_bytes"
    }
}

enum ByteFormat {
    static func string(_ bytes: UInt64, decimals: Int = 1) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var idx = 0
        while value >= 1024 && idx < units.count - 1 {
            value /= 1024
            idx += 1
        }
        return String(format: "%.\(decimals)f %@", value, units[idx])
    }
}

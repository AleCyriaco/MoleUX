import Foundation

/// Whether the CLI can elevate when it needs to.
///
/// Clean and Optimize touch a few system caches that need root. A GUI-spawned
/// process has no controlling terminal, so sudo cannot prompt for a password —
/// but `pam_tid` authenticates through the system's biometric sheet, which needs
/// no terminal at all. Mole ships `mo touchid` to configure exactly that, so the
/// app detects the state and hands the setup to the CLI instead of building its
/// own password prompt. Without Touch ID the work goes to Terminal, where the
/// CLI asks for the password the native way.
enum AdminAccess {
    enum State: Equatable {
        /// `pam_tid` is in the sudo PAM stack: sudo authenticates biometrically.
        case touchID
        /// A sudo credential is already cached for this session.
        case cached
        /// No elevation available — privileged steps will be skipped.
        case unavailable

        var canElevate: Bool { self != .unavailable }

        var summary: String {
            switch self {
            case .touchID: return "Touch ID is set up for sudo — system caches are included."
            case .cached: return "An admin session is already active — system caches are included."
            case .unavailable: return "No admin access: steps that need root will be skipped."
            }
        }
    }

    /// Mirrors `is_touchid_configured` in the mole entrypoint.
    static func touchIDConfigured() -> Bool {
        ["/etc/pam.d/sudo", "/etc/pam.d/sudo_local"].contains { path in
            guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
            return contents
                .split(separator: "\n")
                .contains { line in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    return !trimmed.hasPrefix("#") && trimmed.contains("pam_tid.so")
                }
        }
    }

    /// `sudo -n true` never prompts: it just reports whether a credential is cached.
    static func sudoCached() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
                process.arguments = ["-n", "true"]
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: false)
                    return
                }
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0)
            }
        }
    }

    static func current() async -> State {
        if touchIDConfigured() { return .touchID }
        if await sudoCached() { return .cached }
        return .unavailable
    }
}

import AppKit

/// A candidate destination app for composed text.
struct TargetApp: Equatable {
    let pid: pid_t
    let name: String
    let icon: NSImage?

    static func == (lhs: TargetApp, rhs: TargetApp) -> Bool { lhs.pid == rhs.pid }
}

/// Lists the user-facing apps that text can be dropped into, with the
/// `preferred` app (usually whatever was frontmost when the composer opened)
/// floated to the front so it becomes the default target.
enum TargetEnumerator {

    static func currentTargets(preferred: pid_t?, limit: Int = 9) -> [TargetApp] {
        let selfPid = ProcessInfo.processInfo.processIdentifier
        var apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != selfPid }
            .map { TargetApp(pid: $0.processIdentifier, name: $0.localizedName ?? "App", icon: $0.icon) }

        // Stable, human-friendly ordering, then float the preferred app first.
        apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if let preferred, let idx = apps.firstIndex(where: { $0.pid == preferred }) {
            let t = apps.remove(at: idx)
            apps.insert(t, at: 0)
        }
        return Array(apps.prefix(limit))
    }
}

import AppKit
import ApplicationServices

@MainActor
final class ScreenContextProvider {

    private var cachedContext = ""
    private var lastRefresh: Date = .distantPast
    private let refreshInterval: TimeInterval = 5.0
    private let maxContextLength = 2000
    private var refreshInFlight = false

    func warmUp() {
        scheduleRefresh()
    }

    func context() -> String? {
        if Date().timeIntervalSince(lastRefresh) > refreshInterval {
            scheduleRefresh()
        }
        return cachedContext.isEmpty ? nil : cachedContext
    }

    private func scheduleRefresh() {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        lastRefresh = Date()
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let maxLen = maxContextLength

        Task.detached { [weak self] in
            guard let self else { return }
            let result = Self.gatherContext(ownPID: ownPID, maxLength: maxLen)
            await MainActor.run {
                self.cachedContext = result
                self.refreshInFlight = false
            }
        }
    }

    nonisolated private static func gatherContext(ownPID: pid_t, maxLength: Int) -> String {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else {
            return ""
        }

        var seenPIDs = Set<pid_t>()
        var texts: [String] = []
        var totalLength = 0

        for info in windowList {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid != ownPID,
                  !seenPIDs.contains(pid) else { continue }
            seenPIDs.insert(pid)

            let appElement = AXUIElementCreateApplication(pid)
            var extracted: [String] = []
            extractText(from: appElement, depth: 0, maxDepth: 3, texts: &extracted)

            for t in extracted {
                if totalLength + t.count > maxLength { break }
                texts.append(t)
                totalLength += t.count
            }
            if totalLength >= maxLength { break }
        }

        return texts.joined(separator: "\n")
    }

    nonisolated private static func extractText(from element: AXUIElement, depth: Int, maxDepth: Int, texts: inout [String]) {
        guard depth < maxDepth else { return }

        if let value = AccessibilityBridge.string(element, kAXValueAttribute as String),
           value.count > 5 {
            texts.append(value)
        }
        if let title = AccessibilityBridge.string(element, kAXTitleAttribute as String),
           title.count > 3 {
            texts.append(title)
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return }
        for child in children.prefix(20) {
            extractText(from: child, depth: depth + 1, maxDepth: maxDepth, texts: &texts)
        }
    }
}

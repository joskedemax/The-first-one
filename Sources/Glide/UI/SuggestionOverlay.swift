import AppKit

/// A borderless, click-through window that draws gray "ghost" text at the
/// caret, mimicking inline autocomplete. For corrections it draws the fix in a
/// subtle pill so it reads differently from a plain completion.
final class SuggestionOverlay {

    private let window: NSWindow
    private let label: NSTextField

    init() {
        label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = NSColor.secondaryLabelColor
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.drawsBackground = false

        window = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView?.addSubview(label)
    }

    /// Show `suggestion` anchored to a caret rect (Cocoa screen coords).
    /// If `caretRect` is nil we can't place it precisely; the caller decides on
    /// a fallback HUD.
    func show(_ suggestion: Suggestion, caretRect: CGRect) {
        configureAppearance(for: suggestion)
        label.stringValue = suggestion.displayText
        label.sizeToFit()

        let padding: CGFloat = suggestion.kind == .correction ? 6 : 2
        let size = NSSize(width: label.frame.width + padding * 2,
                          height: max(label.frame.height, caretRect.height) + padding * 2)

        // Place just to the right of the caret, vertically centered on it.
        let origin = NSPoint(
            x: caretRect.maxX + 2,
            y: caretRect.midY - size.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: size), display: true)
        label.frame = NSRect(x: padding, y: padding,
                             width: label.frame.width, height: label.frame.height)
        window.orderFrontRegardless()
    }

    private func configureAppearance(for suggestion: Suggestion) {
        switch suggestion.kind {
        case .completion, .nextWord:
            label.textColor = NSColor.tertiaryLabelColor
            window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
            window.contentView?.wantsLayer = false
        case .correction:
            label.textColor = NSColor.systemBlue
            let view = window.contentView!
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.controlBackgroundColor
                .withAlphaComponent(0.95).cgColor
            view.layer?.cornerRadius = 5
            view.layer?.borderWidth = 1
            view.layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }

    func hide() {
        window.orderOut(nil)
        label.stringValue = ""
    }

    var isVisible: Bool { window.isVisible }
}

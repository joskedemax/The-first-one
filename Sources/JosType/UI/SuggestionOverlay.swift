import AppKit

/// A borderless, click-through window that draws gray "ghost" text directly
/// after the caret, so it looks like inline continuation of what the user typed.
/// For corrections it uses a subtle blue pill style.
final class SuggestionOverlay {

    private let window: NSWindow
    private let label: NSTextField

    init() {
        label = NSTextField(labelWithString: "")
        label.isBezeled = false
        label.isEditable = false
        label.drawsBackground = false
        label.backgroundColor = .clear
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byClipping

        window = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView?.addSubview(label)
    }

    /// Show `suggestion` anchored directly after the caret (inline ghost text).
    /// Clamps to `fieldFrame` boundaries when provided.
    func show(_ suggestion: Suggestion, caretRect: CGRect, fieldFrame: CGRect? = nil, font: NSFont? = nil) {
        let displayFont = font ?? NSFont.systemFont(ofSize: 13)
        label.font = displayFont
        configureAppearance(for: suggestion)
        label.stringValue = suggestion.displayText
        label.sizeToFit()

        let isCorrection = suggestion.kind == .correction
        let hPad: CGFloat = isCorrection ? 6 : 0
        let vPad: CGFloat = isCorrection ? 3 : 0

        var labelW = label.frame.width
        let labelH = label.frame.height

        // Clamp to field boundaries.
        if let field = fieldFrame {
            let available = field.maxX - caretRect.maxX - hPad * 2 - 4
            if available < 30 {
                hide()
                return
            }
            labelW = min(labelW, available)
        }

        let winW = labelW + hPad * 2
        let winH = max(labelH, caretRect.height) + vPad * 2

        let origin = NSPoint(
            x: caretRect.maxX,
            y: caretRect.origin.y - vPad
        )

        window.setFrame(NSRect(origin: origin, size: NSSize(width: winW, height: winH)),
                        display: false)
        label.frame = NSRect(x: hPad, y: vPad, width: labelW, height: labelH)

        if isCorrection {
            let view = window.contentView!
            view.wantsLayer = true
            view.layer?.cornerRadius = 5
            view.layer?.borderWidth = 1
            view.layer?.borderColor = NSColor.separatorColor.cgColor
        }

        window.orderFrontRegardless()
    }

    private func configureAppearance(for suggestion: Suggestion) {
        switch suggestion.kind {
        case .completion, .nextWord:
            label.textColor = NSColor.placeholderTextColor
            let view = window.contentView!
            view.wantsLayer = false
            view.layer?.backgroundColor = NSColor.clear.cgColor
            view.layer?.cornerRadius = 0
            view.layer?.borderWidth = 0
        case .correction:
            label.textColor = NSColor.systemBlue
            let view = window.contentView!
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.controlBackgroundColor
                .withAlphaComponent(0.95).cgColor
        }
    }

    func hide() {
        window.orderOut(nil)
        label.stringValue = ""
    }

    var isVisible: Bool { window.isVisible }
}

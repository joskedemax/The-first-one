import AppKit

/// A borderless, click-through window that draws "ghost" text for a suggestion.
///
/// Two presentation modes, chosen automatically per render:
/// - **Inline**: short suggestions render directly after the caret, like
///   continuation of what the user typed.
/// - **Panel**: long / multi-line suggestions drop into a small blur-backed
///   floating card just below the caret so they aren't clipped to the field.
///
/// Both modes apply a *confidence gradient* — the text starts solid and fades
/// toward transparent along its length, so the suggestion visually "dissolves"
/// the further it gets from what the user has already committed to. The user
/// reads the fade as "trust the bright part, the tail is a guess" and naturally
/// stops accepting (Tab) where it thins out.
///
/// On first appearance the suggestion fades in and (on Force Touch trackpads)
/// delivers a subtle haptic tap, so it feels like it *arrived* rather than
/// popped in. Streaming updates re-render without repeating that feedback.
@MainActor
final class SuggestionOverlay {

    private let window: NSWindow
    private let label: NSTextField
    private let backdrop: NSVisualEffectView

    /// Context from the most recent `show`, so streaming `updateText` can
    /// re-decide inline vs. panel as the suggestion grows.
    private var lastCaretRect: CGRect = .zero
    private var lastFieldFrame: CGRect?
    private var lastFont: NSFont = .systemFont(ofSize: 13)

    /// Throttle so rapid show/hide flicker doesn't machine-gun the haptic.
    private var lastArrivalFeedback: Date = .distantPast
    private static let arrivalFeedbackInterval: TimeInterval = 0.8

    // Gradient endpoints (alpha at the start vs. the end of the suggestion).
    private static let gradientHighAlpha: CGFloat = 0.92
    private static let gradientLowAlpha: CGFloat = 0.38

    // Long suggestions switch to the floating panel.
    private static let panelMaxWidth: CGFloat = 460
    private static let inlineMinWidth: CGFloat = 40
    private static let fadeInDuration: TimeInterval = 0.18

    init() {
        label = NSTextField(labelWithString: "")
        label.isBezeled = false
        label.isEditable = false
        label.drawsBackground = false
        label.backgroundColor = .clear
        label.cell?.wraps = true
        label.cell?.isScrollable = false

        backdrop = NSVisualEffectView()
        backdrop.material = .hudWindow
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = 8
        backdrop.layer?.borderWidth = 1
        backdrop.isHidden = true

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
        window.setAccessibilityElement(false)
        let content = window.contentView!
        content.addSubview(backdrop)
        content.addSubview(label)
    }

    /// Show `suggestion` anchored at the caret. Chooses inline vs. panel mode
    /// based on whether the text fits comfortably on one line within the field.
    func show(_ suggestion: Suggestion, caretRect: CGRect, fieldFrame: CGRect? = nil, font: NSFont? = nil) {
        let wasVisible = window.isVisible
        lastCaretRect = caretRect
        lastFieldFrame = fieldFrame
        lastFont = font ?? NSFont.systemFont(ofSize: 13)

        render(suggestion)
        window.orderFrontRegardless()

        // Multi-modal "arrival" feedback only on the transition from hidden→shown,
        // and throttled so rapid flicker doesn't repeat it.
        let now = Date()
        if !wasVisible, now.timeIntervalSince(lastArrivalFeedback) > Self.arrivalFeedbackInterval {
            lastArrivalFeedback = now
            window.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Self.fadeInDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            }
            NSHapticFeedbackManager.defaultPerformer.perform(
                .levelChange, performanceTime: .now
            )
        } else {
            window.alphaValue = 1
        }
    }

    /// Update the displayed text mid-stream, reusing the last anchor and
    /// re-deciding inline vs. panel as the suggestion grows. Does not repeat
    /// the fade-in / haptic.
    func updateText(_ text: String) {
        guard window.isVisible else { return }
        let suggestion = Suggestion(
            kind: .nextWord, insertText: text, displayText: text, replaceRange: 0..<0
        )
        render(suggestion)
    }

    // MARK: - Rendering

    private func render(_ suggestion: Suggestion) {
        let font = lastFont
        label.font = font

        if suggestion.kind == .correction {
            renderCorrection(suggestion, font: font)
            return
        }

        // Width available to the right of the caret inside the field.
        let inlineAvailable: CGFloat
        if let field = lastFieldFrame {
            inlineAvailable = field.maxX - lastCaretRect.maxX - 4
        } else {
            inlineAvailable = Self.panelMaxWidth
        }

        let plain = NSAttributedString(
            string: suggestion.displayText,
            attributes: [.font: font]
        )
        let singleLineW = ceil(plain.size().width)
        let fitsInline = inlineAvailable >= Self.inlineMinWidth && singleLineW <= inlineAvailable

        if fitsInline {
            renderInline(suggestion, font: font, width: singleLineW)
        } else {
            renderPanel(suggestion, font: font)
        }
    }

    private func renderInline(_ suggestion: Suggestion, font: NSFont, width: CGFloat) {
        backdrop.isHidden = true
        resetContentLayer()
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byClipping
        label.attributedStringValue = gradientString(suggestion.displayText, font: font, baseColor: .placeholderTextColor)

        let h = max(ceil(label.attributedStringValue.size().height), lastCaretRect.height)
        let origin = NSPoint(x: lastCaretRect.maxX, y: lastCaretRect.origin.y)
        window.setFrame(NSRect(x: origin.x, y: origin.y, width: width, height: h), display: false)
        label.frame = NSRect(x: 0, y: 0, width: width, height: h)
    }

    private func renderPanel(_ suggestion: Suggestion, font: NSFont) {
        resetContentLayer()
        let hPad: CGFloat = 10
        let vPad: CGFloat = 8

        var maxTextW = Self.panelMaxWidth - hPad * 2
        if let field = lastFieldFrame {
            maxTextW = min(maxTextW, max(field.width - hPad * 2, 160))
        }

        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.preferredMaxLayoutWidth = maxTextW
        label.attributedStringValue = gradientString(suggestion.displayText, font: font, baseColor: .labelColor)

        let textSize = label.sizeThatFits(NSSize(width: maxTextW, height: .greatestFiniteMagnitude))
        let textW = ceil(min(textSize.width, maxTextW))
        let textH = ceil(textSize.height)

        let winW = textW + hPad * 2
        let winH = textH + vPad * 2

        // Position the card just below the caret (AppKit coords are y-up, so
        // "below" is a smaller y). Nudge left if it would run off the field.
        var x = lastCaretRect.minX
        if let field = lastFieldFrame, x + winW > field.maxX {
            x = max(field.minX, field.maxX - winW)
        }
        let y = lastCaretRect.minY - winH - 4

        window.setFrame(NSRect(x: x, y: y, width: winW, height: winH), display: false)

        backdrop.isHidden = false
        backdrop.frame = NSRect(x: 0, y: 0, width: winW, height: winH)
        backdrop.layer?.borderColor = NSColor.separatorColor.cgColor
        label.frame = NSRect(x: hPad, y: vPad, width: textW, height: textH)
    }

    private func renderCorrection(_ suggestion: Suggestion, font: NSFont) {
        backdrop.isHidden = true
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byClipping
        label.attributedStringValue = NSAttributedString(
            string: suggestion.displayText,
            attributes: [.font: font, .foregroundColor: NSColor.systemBlue]
        )

        let size = label.attributedStringValue.size()
        let hPad: CGFloat = 6
        let vPad: CGFloat = 3
        let labelW = ceil(size.width)
        let labelH = ceil(size.height)
        let winW = labelW + hPad * 2
        let winH = max(labelH, lastCaretRect.height) + vPad * 2

        window.setFrame(
            NSRect(x: lastCaretRect.maxX, y: lastCaretRect.origin.y - vPad, width: winW, height: winH),
            display: false
        )
        label.frame = NSRect(x: hPad, y: vPad, width: labelW, height: labelH)

        let view = window.contentView!
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.95).cgColor
        view.layer?.cornerRadius = 5
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.cgColor
    }

    private func resetContentLayer() {
        guard let layer = window.contentView?.layer else { return }
        layer.backgroundColor = NSColor.clear.cgColor
        layer.cornerRadius = 0
        layer.borderWidth = 0
    }

    // MARK: - Confidence gradient

    /// Build an attributed string whose per-character alpha ramps from
    /// `gradientHighAlpha` (start) down to `gradientLowAlpha` (end), so the
    /// suggestion fades out along its length.
    private func gradientString(_ text: String, font: NSFont, baseColor: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text)
        let full = NSRange(location: 0, length: (text as NSString).length)
        result.addAttribute(.font, value: font, range: full)

        let chars = Array(text)
        let denom = CGFloat(max(chars.count - 1, 1))
        var utf16Loc = 0
        for (idx, ch) in chars.enumerated() {
            let frac = CGFloat(idx) / denom
            let alpha = Self.gradientHighAlpha - (Self.gradientHighAlpha - Self.gradientLowAlpha) * frac
            let len = String(ch).utf16.count
            result.addAttribute(
                .foregroundColor,
                value: baseColor.withAlphaComponent(alpha),
                range: NSRange(location: utf16Loc, length: len)
            )
            utf16Loc += len
        }
        return result
    }

    func hide() {
        window.orderOut(nil)
        label.stringValue = ""
        backdrop.isHidden = true
    }

    var isVisible: Bool { window.isVisible }
}

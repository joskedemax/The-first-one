import AppKit

/// Borderless panel that can still take keyboard focus (so the text view gets a
/// blinking caret) without fully activating the app behind it.
final class ComposerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The floating "funky Apple" composer: a glassy rounded card with a numbered
/// row of target-app chips on top, a ghost-text input in the middle, and a hint
/// line at the bottom. Compose here, pick a target, drop the text in.
@MainActor
final class ComposerWindow: NSObject {

    let panel: ComposerPanel
    let textView: GhostTextView

    /// Fired when a chip is clicked (0-based index).
    var onSelectChip: ((Int) -> Void)?

    private let effect: NSVisualEffectView
    private let scrollView: NSScrollView
    private let chipsContainer: NSView
    private let hintLabel: NSTextField
    private var chipButtons: [NSButton] = []

    private let width: CGFloat = 720
    private let pad: CGFloat = 20
    private let chipH: CGFloat = 28
    private let chipGap: CGFloat = 4
    private let hintH: CGFloat = 16
    private let gap: CGFloat = 10
    private let minTextH: CGFloat = 240
    private let maxTextH: CGFloat = 500

    override init() {
        effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.alphaValue = 0.92
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 18
        effect.layer?.cornerCurve = .continuous
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
        effect.layer?.masksToBounds = true

        let font = NSFont.systemFont(ofSize: 17)
        let textWidth = width - pad * 2
        textView = GhostTextView()
        textView.font = font
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.frame = NSRect(x: 0, y: 0, width: textWidth, height: minTextH)
        textView.minSize = NSSize(width: textWidth, height: minTextH)
        textView.maxSize = NSSize(width: textWidth, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: textWidth, height: .greatestFiniteMagnitude)

        scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView

        chipsContainer = NSView()
        chipsContainer.wantsLayer = true
        chipsContainer.layer?.masksToBounds = true

        hintLabel = NSTextField(labelWithString: "Tab accept · ⏎ insert · ⌘1–9 pick app · esc cancel")
        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.alignment = .right

        let wrapper = NSView()
        wrapper.wantsLayer = true
        wrapper.layer?.backgroundColor = NSColor.clear.cgColor

        panel = ComposerPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = wrapper
        wrapper.addSubview(effect)

        super.init()

        effect.addSubview(chipsContainer)
        effect.addSubview(scrollView)
        effect.addSubview(hintLabel)
    }

    // MARK: - Targets

    func setTargets(_ targets: [TargetApp], selected: Int) {
        chipButtons.forEach { $0.removeFromSuperview() }
        chipButtons = []

        for (i, target) in targets.enumerated() {
            let button = NSButton()
            button.setButtonType(.pushOnPushOff)
            button.bezelStyle = .recessed
            button.showsBorderOnlyWhileMouseInside = false
            button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            button.title = "\(i + 1)  \(shortName(target.name))"
            button.imagePosition = .imageLeading
            button.imageScaling = .scaleProportionallyDown
            if let icon = target.icon {
                let img = icon.copy() as! NSImage
                img.size = NSSize(width: 14, height: 14)
                button.image = img
            }
            button.wantsLayer = true
            button.layer?.masksToBounds = true
            button.toolTip = "\(target.name)  (⌘\(i + 1))"
            button.tag = i
            button.target = self
            button.action = #selector(chipClicked(_:))
            button.state = (i == selected) ? .on : .off
            chipsContainer.addSubview(button)
            chipButtons.append(button)
        }
        layoutChips()
        highlightChip(selected)
    }

    func highlightChip(_ index: Int) {
        for (i, button) in chipButtons.enumerated() {
            button.state = (i == index) ? .on : .off
        }
    }

    @objc private func chipClicked(_ sender: NSButton) {
        onSelectChip?(sender.tag)
    }

    private func shortName(_ name: String) -> String {
        name.count > 14 ? String(name.prefix(13)) + "…" : name
    }

    private var chipsHeight: CGFloat = 28

    private func layoutChips() {
        let maxW = width - pad * 2
        let h = chipH
        let hSpacing: CGFloat = 6

        // First pass: compute row assignments and total height.
        var rows: [[NSButton]] = [[]]
        var rowX: CGFloat = 0
        for button in chipButtons {
            button.sizeToFit()
            let w = min(max(button.frame.width + 14, 56), 150)
            if rowX + w > maxW && rowX > 0 {
                rows.append([])
                rowX = 0
            }
            rows[rows.count - 1].append(button)
            rowX += w + hSpacing
        }
        let totalRows = CGFloat(rows.count)
        chipsHeight = totalRows * h + max(totalRows - 1, 0) * chipGap

        // Second pass: position buttons (AppKit y-up, first row at top).
        for (rowIdx, row) in rows.enumerated() {
            let y = chipsHeight - CGFloat(rowIdx + 1) * h - CGFloat(rowIdx) * chipGap
            var x: CGFloat = 0
            for button in row {
                let w = min(max(button.frame.width + 14, 56), 150)
                button.frame = NSRect(x: x, y: y, width: w, height: h)
                x += w + hSpacing
            }
        }
    }

    // MARK: - Layout & presentation

    /// Recompute the text height from content and re-lay-out / re-center.
    func refreshLayout() {
        guard let lm = textView.layoutManager, let tc = textView.textContainer else { return }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc).height
        let textH = min(max(used + textView.textContainerInset.height * 2 + 4, minTextH), maxTextH)

        let totalH = pad + chipsHeight + gap + textH + gap + hintH + pad
        let frame = currentFrame(height: totalH)
        panel.setFrame(frame, display: true)

        effect.frame = NSRect(x: 0, y: 0, width: frame.width, height: frame.height)

        let innerW = frame.width - pad * 2
        // Bottom-up (AppKit y-up).
        hintLabel.frame = NSRect(x: pad, y: pad, width: innerW, height: hintH)
        scrollView.frame = NSRect(x: pad, y: pad + hintH + gap, width: innerW, height: textH)
        let chipsY = pad + hintH + gap + textH + gap
        chipsContainer.frame = NSRect(x: pad, y: chipsY, width: innerW, height: chipsHeight)
    }

    private func currentFrame(height: CGFloat) -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = visible.midX - width / 2
        // Anchor near the top third; keep the top edge stable as it grows.
        let topY = visible.minY + visible.height * 0.72
        let y = topY - height
        return NSRect(x: x, y: max(visible.minY + 20, y), width: width, height: height)
    }

    func show() {
        refreshLayout()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(textView)
    }

    func hide() {
        panel.orderOut(nil)
    }

    var isVisible: Bool { panel.isVisible }
}

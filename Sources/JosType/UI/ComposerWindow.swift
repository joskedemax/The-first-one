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

    private let width: CGFloat = 660
    private let pad: CGFloat = 16
    private let chipRowH: CGFloat = 30
    private let hintH: CGFloat = 16
    private let gap: CGFloat = 10
    private let minTextH: CGFloat = 56
    private let maxTextH: CGFloat = 280

    init() {
        effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 18
        effect.layer?.borderWidth = 1
        effect.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
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

        hintLabel = NSTextField(labelWithString: "Tab accept · ⏎ insert · ⌘1–9 pick app · esc cancel")
        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.alignment = .right

        panel = ComposerPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 180),
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
        panel.contentView = effect

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
            if let icon = target.icon {
                let img = icon.copy() as! NSImage
                img.size = NSSize(width: 16, height: 16)
                button.image = img
            }
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

    private func layoutChips() {
        var x: CGFloat = 0
        let h = chipRowH
        for button in chipButtons {
            button.sizeToFit()
            let w = min(max(button.frame.width + 14, 56), 150)
            button.frame = NSRect(x: x, y: 0, width: w, height: h)
            x += w + 6
        }
    }

    // MARK: - Layout & presentation

    /// Recompute the text height from content and re-lay-out / re-center.
    func refreshLayout() {
        guard let lm = textView.layoutManager, let tc = textView.textContainer else { return }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc).height
        let textH = min(max(used + textView.textContainerInset.height * 2 + 4, minTextH), maxTextH)

        let totalH = pad + chipRowH + gap + textH + gap + hintH + pad
        let frame = currentFrame(height: totalH)
        panel.setFrame(frame, display: true)

        effect.frame = NSRect(x: 0, y: 0, width: frame.width, height: frame.height)

        let innerW = frame.width - pad * 2
        // Bottom-up (AppKit y-up).
        hintLabel.frame = NSRect(x: pad, y: pad, width: innerW, height: hintH)
        scrollView.frame = NSRect(x: pad, y: pad + hintH + gap, width: innerW, height: textH)
        let chipsY = pad + hintH + gap + textH + gap
        chipsContainer.frame = NSRect(x: pad, y: chipsY, width: innerW, height: chipRowH)
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

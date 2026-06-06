import AppKit

/// Floating pill that appears during voice capture, showing a pulsing mic icon
/// and live partial transcription text.
@MainActor
final class RecordingIndicator {

    private let window: NSWindow
    private let container: NSView
    private let micLabel: NSTextField
    private let textLabel: NSTextField
    private var pulseTimer: Timer?

    init() {
        micLabel = NSTextField(labelWithString: "\u{1F3A4}")
        micLabel.font = NSFont.systemFont(ofSize: 16)
        micLabel.isBezeled = false
        micLabel.isEditable = false
        micLabel.drawsBackground = false

        textLabel = NSTextField(labelWithString: "Listening...")
        textLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        textLabel.textColor = .labelColor
        textLabel.isBezeled = false
        textLabel.isEditable = false
        textLabel.drawsBackground = false
        textLabel.maximumNumberOfLines = 1
        textLabel.lineBreakMode = .byTruncatingTail

        container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 16
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.cgColor

        container.addSubview(micLabel)
        container.addSubview(textLabel)

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
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = container
    }

    func show(near caretRect: CGRect) {
        textLabel.stringValue = "Listening..."
        layout()

        let origin = NSPoint(
            x: caretRect.minX,
            y: caretRect.minY - window.frame.height - 4
        )
        window.setFrameOrigin(origin)
        window.orderFrontRegardless()
        startPulse()
    }

    func updatePartialText(_ text: String) {
        guard window.isVisible else { return }
        textLabel.stringValue = text.isEmpty ? "Listening..." : text
        layout()
    }

    func showProcessing() {
        guard window.isVisible else { return }
        stopPulse()
        textLabel.stringValue = "Processing..."
        layout()
    }

    func hide() {
        stopPulse()
        window.orderOut(nil)
    }

    var isVisible: Bool { window.isVisible }

    private func layout() {
        micLabel.sizeToFit()
        textLabel.sizeToFit()

        let pad: CGFloat = 10
        let gap: CGFloat = 6
        let micW = micLabel.frame.width
        let micH = micLabel.frame.height
        let textW = min(textLabel.frame.width, 300)
        let textH = textLabel.frame.height

        let totalW = pad + micW + gap + textW + pad
        let totalH = max(micH, textH) + pad * 2

        let frame = NSRect(origin: window.frame.origin, size: NSSize(width: totalW, height: totalH))
        window.setFrame(frame, display: false)

        let centerY = (totalH - micH) / 2
        micLabel.frame = NSRect(x: pad, y: centerY, width: micW, height: micH)
        let textCenterY = (totalH - textH) / 2
        textLabel.frame = NSRect(x: pad + micW + gap, y: textCenterY, width: textW, height: textH)
    }

    private func startPulse() {
        var bright = true
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.micLabel.alphaValue = bright ? 0.4 : 1.0
                bright.toggle()
            }
        }
    }

    private func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        micLabel.alphaValue = 1.0
    }
}

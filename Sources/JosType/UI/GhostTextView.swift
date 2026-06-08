import AppKit

/// An editable text view that shows inline "ghost" suggestion text after the
/// caret — the same Copilot-style autocomplete, but inside a view JosType fully
/// controls, so acceptance and rendering are reliable across every app.
///
/// The ghost is stored as a trailing gray run in the text storage (so it wraps
/// and scrolls naturally) with a confidence gradient: it starts solid and fades
/// out along its length. Typing, deleting, or moving the caret strips it; Tab
/// accepts a word, Right-at-end accepts the rest.
@MainActor
final class GhostTextView: NSTextView {

    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onSelectTarget: ((Int) -> Void)?   // 1-based index from ⌘1…⌘9
    var onUserEdit: (() -> Void)?

    private(set) var ghostText: String = ""
    private var isMutatingGhost = false

    private static let gradientHighAlpha: CGFloat = 0.45
    private static let gradientLowAlpha: CGFloat = 0.18

    /// The text the user has actually committed (everything except the ghost).
    var committedString: String {
        let full = string as NSString
        let ghostLen = (ghostText as NSString).length
        guard ghostLen > 0, full.length >= ghostLen else { return string }
        return full.substring(to: full.length - ghostLen)
    }

    private var committedLength: Int {
        max(0, (string as NSString).length - (ghostText as NSString).length)
    }

    /// True when the latest text change came from the user (not our own ghost
    /// bookkeeping), so the controller knows when to recompute a suggestion.
    func textChangedShouldRecompute() -> Bool { !isMutatingGhost }

    // MARK: - Ghost mutation

    func showGhost(_ text: String) {
        removeGhost()
        guard !text.isEmpty, let storage = textStorage else { return }
        // Only show ghost when cursor is at the end of committed text.
        let caret = selectedRange().location
        let committed = committedLength
        guard caret >= committed else { return }
        isMutatingGhost = true
        storage.append(gradientGhost(text))
        ghostText = text
        setSelectedRange(NSRange(location: committed, length: 0))
        isMutatingGhost = false
    }

    func removeGhost() {
        guard !ghostText.isEmpty else { return }
        guard let storage = textStorage else { ghostText = ""; return }
        isMutatingGhost = true
        let len = (ghostText as NSString).length
        let total = storage.length
        if total >= len {
            storage.deleteCharacters(in: NSRange(location: total - len, length: len))
        }
        ghostText = ""
        isMutatingGhost = false
    }

    @discardableResult
    func acceptGhostWord() -> Bool {
        guard !ghostText.isEmpty else { return false }
        let g = ghostText
        var idx = g.startIndex
        while idx < g.endIndex, g[idx] == " " { idx = g.index(after: idx) }   // leading spaces
        while idx < g.endIndex, g[idx] != " " { idx = g.index(after: idx) }   // the word
        if idx < g.endIndex, g[idx] == " " { idx = g.index(after: idx) }      // trailing space
        let firstChunk = String(g[g.startIndex..<idx])
        let remaining = String(g[idx...])
        removeGhost()
        insertCommitted(firstChunk, recompute: remaining.isEmpty)
        if !remaining.isEmpty { showGhost(remaining) }
        return true
    }

    @discardableResult
    func acceptGhostAll() -> Bool {
        guard !ghostText.isEmpty else { return false }
        let all = ghostText
        removeGhost()
        insertCommitted(all, recompute: true)
        return true
    }

    private func insertCommitted(_ text: String, recompute: Bool) {
        guard let storage = textStorage, !text.isEmpty else { return }
        isMutatingGhost = true
        let caret = committedLength
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.labelColor
        ]
        storage.insert(NSAttributedString(string: text, attributes: attrs), at: caret)
        setSelectedRange(NSRange(location: caret + (text as NSString).length, length: 0))
        isMutatingGhost = false
        if recompute { onUserEdit?() }
    }

    // MARK: - Gradient

    private func gradientGhost(_ text: String) -> NSAttributedString {
        let f = font ?? NSFont.systemFont(ofSize: 15)
        let result = NSMutableAttributedString(string: text, attributes: [.font: f])
        let chars = Array(text)
        let denom = CGFloat(max(chars.count - 1, 1))
        var loc = 0
        for (i, ch) in chars.enumerated() {
            let frac = CGFloat(i) / denom
            let alpha = Self.gradientHighAlpha - (Self.gradientHighAlpha - Self.gradientLowAlpha) * frac
            let len = String(ch).utf16.count
            result.addAttribute(
                .foregroundColor,
                value: NSColor.secondaryLabelColor.withAlphaComponent(alpha),
                range: NSRange(location: loc, length: len)
            )
            loc += len
        }
        return result
    }

    // MARK: - Key handling

    override func insertText(_ string: Any, replacementRange: NSRange) {
        if let s = string as? String, s == "`", !ghostText.isEmpty {
            _ = acceptGhostAll()
            return
        }
        removeGhost()
        super.insertText(string, replacementRange: replacementRange)
    }

    override func deleteBackward(_ sender: Any?) {
        let pos = selectedRange().location
        removeGhost()
        setSelectedRange(NSRange(location: min(pos, committedLength), length: 0))
        super.deleteBackward(sender)
    }

    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(insertTab(_:)):
            if !ghostText.isEmpty { _ = acceptGhostWord() }
            return  // never tab out / insert a literal tab
        case #selector(insertNewline(_:)):
            onSubmit?()
            return
        case #selector(insertNewlineIgnoringFieldEditor(_:)):  // Shift+Return → real newline
            removeGhost()
            super.doCommand(by: selector)
            return
        case #selector(cancelOperation(_:)):
            onCancel?()
            return
        case #selector(moveRight(_:)), #selector(moveLeft(_:)),
             #selector(moveUp(_:)), #selector(moveDown(_:)),
             #selector(moveToBeginningOfLine(_:)), #selector(moveToEndOfLine(_:)),
             #selector(moveWordRight(_:)), #selector(moveWordLeft(_:)):
            removeGhost()
            super.doCommand(by: selector)
        default:
            if !ghostText.isEmpty { removeGhost() }
            super.doCommand(by: selector)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           let chars = event.charactersIgnoringModifiers,
           let digit = Int(chars), (1...9).contains(digit) {
            onSelectTarget?(digit)
            return
        }
        super.keyDown(with: event)
    }
}

import SwiftUI
import AppKit

/// Read-only, selectable text drawn by AppKit so the color of mouse-selected text can be customised
/// (SwiftUI's own selectable `Text` always uses the system color).
///
/// The visible text view always wraps to the width it is actually given (`widthTracksTextView`);
/// heights are measured on a separate scratch layout, so measuring at a different proposed width
/// can never leave the visible text wrapped differently from the space reserved for it.
struct SelectableText: NSViewRepresentable {
    let text: String
    let font: NSFont
    let lineSpacing: CGFloat
    let selectionColor: NSColor

    final class Box {
        var lastKey = ""
        let scratchStorage = NSTextStorage()
        let scratchLM = NSLayoutManager()
        let scratchContainer = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        var scratchKey = ""
        init() {
            scratchContainer.lineFragmentPadding = 0
            scratchStorage.addLayoutManager(scratchLM)
            scratchLM.addTextContainer(scratchContainer)
        }
    }
    func makeCoordinator() -> Box { Box() }

    private var key: String { "\(text)|\(font.fontName)|\(font.pointSize)|\(lineSpacing)" }
    private var attributed: NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = lineSpacing
        return NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: p])
    }

    func makeNSView(context: Context) -> NSTextView {
        let storage = NSTextStorage()
        let lm = NSLayoutManager()
        storage.addLayoutManager(lm)
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        lm.addTextContainer(container)
        let tv = NSTextView(frame: .zero, textContainer: container)
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        return tv
    }

    func updateNSView(_ tv: NSTextView, context: Context) {
        if key != context.coordinator.lastKey {
            tv.textStorage?.setAttributedString(attributed)
            context.coordinator.lastKey = key
        }
        tv.selectedTextAttributes = [.backgroundColor: selectionColor]
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView tv: NSTextView, context: Context) -> CGSize? {
        let box = context.coordinator
        if box.scratchKey != key {
            box.scratchStorage.setAttributedString(attributed)
            box.scratchKey = key
        }
        var w = proposal.width ?? 600
        if !w.isFinite || w <= 0 { w = 600 }
        box.scratchContainer.containerSize = NSSize(width: w, height: CGFloat.greatestFiniteMagnitude)
        box.scratchLM.ensureLayout(for: box.scratchContainer)
        return CGSize(width: w, height: ceil(box.scratchLM.usedRect(for: box.scratchContainer).height))
    }
}

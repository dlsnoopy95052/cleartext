import SwiftUI
import AppKit
import UniformTypeIdentifiers

@Observable
@MainActor
final class DocModel {
    var sourceText = ""
    var fileName: String?
    var options = ParseOptions()
    var doc = Document()
    var collapsed: Set<UUID> = []
    var sidebarExpanded: Set<UUID> = []
    var showOriginal = false
    var scrollTarget: UUID?
    var scrollTick = 0
    var scrollAnchor: UnitPoint = .top
    /// Temporary reading marker (lives only in the app; the source text is never changed).
    var markedBlock: UUID?
    var errorMessage: String?
    /// Source was edited in the Original view; re-organize when switching back.
    var sourceDirty = false

    func setText(_ text: String, name: String?) {
        sourceText = text
        fileName = name
        sourceDirty = false
        reparse()
    }

    func reparse() {
        doc = Parser.parse(sourceText, options: options)
        markedBlock = nil
        collapsed = []
        var ids: Set<UUID> = []
        doc.root.walk { if !$0.children.isEmpty { ids.insert($0.id) } }
        sidebarExpanded = ids
    }

    func load(url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            var enc = String.Encoding.utf8
            let text: String
            if let t = try? String(contentsOf: url, usedEncoding: &enc) {
                text = t
            } else {
                let data = try Data(contentsOf: url)
                // Messy files are often Windows-1252 / MacRoman.
                guard let t = String(data: data, encoding: .windowsCP1252)
                        ?? String(data: data, encoding: .macOSRoman)
                        ?? String(data: data, encoding: .isoLatin1) else {
                    errorMessage = "Couldn't decode “\(url.lastPathComponent)” as text."
                    return
                }
                text = t
            }
            setText(text, name: url.lastPathComponent)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clear() {
        sourceText = ""
        fileName = nil
        sourceDirty = false
        showOriginal = false
        doc = Document()
        markedBlock = nil
        collapsed = []
        sidebarExpanded = []
    }

    func loadClipboard() {
        guard let s = NSPasteboard.general.string(forType: .string), !s.isEmpty else { return }
        setText(s, name: "Pasted text")
    }

    func openPanel() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.plainText, .text, .utf8PlainText, .rtf, .data]
        p.allowsMultipleSelection = false
        if p.runModal() == .OK, let u = p.url { load(url: u) }
    }

    // MARK: Collapse / navigate

    func toggle(_ id: UUID) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }

    func collapseAll() {
        var ids: Set<UUID> = []
        doc.root.walk { if $0.level > 0 && (!$0.children.isEmpty || !$0.blocks.isEmpty) { ids.insert($0.id) } }
        collapsed = ids
    }

    func expandAll() { collapsed = [] }

    func reveal(_ id: UUID) {
        if let path = doc.root.path(to: id) { collapsed.subtract(path) }
        scrollAnchor = .top
        scrollTarget = id
        scrollTick += 1
    }

    // MARK: Reading marker

    func toggleMark(_ id: UUID) { markedBlock = (markedBlock == id) ? nil : id }

    func jumpToMark() {
        guard let m = markedBlock else { return }
        var path: [UUID]?
        doc.root.walk { n in
            if path == nil, n.blocks.contains(where: { $0.id == m }) { path = doc.root.path(to: n.id) }
        }
        if let path { collapsed.subtract(path) }   // open any collapsed section holding the mark
        scrollAnchor = .center
        scrollTarget = m
        scrollTick += 1
    }

    // MARK: Export

    func markdown() -> String {
        var out: [String] = []
        func emit(_ n: Node) {
            if n.level > 0 { out.append(String(repeating: "#", count: n.level) + " " + n.title) }
            var lastWasList = false
            for b in n.blocks {
                switch b.kind {
                case .paragraph(let t):
                    out.append(t); lastWasList = false
                case .listItem(let t, let indent, let marker):
                    let ordered = marker.first?.isLetter == true || marker.first?.isNumber == true
                    let line = String(repeating: " ", count: indent) + (ordered ? marker : "-") + " " + t
                    if lastWasList, !out.isEmpty { out[out.count - 1] += "\n" + line } else { out.append(line) }
                    lastWasList = true
                case .pageBreak(let p):
                    out.append("---\n<!-- page \(p) -->"); lastWasList = false
                }
            }
            n.children.forEach(emit)
        }
        emit(doc.root)
        return out.joined(separator: "\n\n") + "\n"
    }

    func exportMarkdown() {
        let p = NSSavePanel()
        p.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        let base = (fileName as NSString?)?.deletingPathExtension ?? "Organized"
        p.nameFieldStringValue = base + ".md"
        guard p.runModal() == .OK, let u = p.url else { return }
        do { try markdown().write(to: u, atomically: true, encoding: .utf8) }
        catch { errorMessage = error.localizedDescription }
    }
}

import Foundation

// MARK: - Options

struct ParseOptions: Equatable {
    /// Join hard-wrapped lines inside a paragraph into a single flowing paragraph.
    var joinWrappedLines = true
    /// Numbered / lettered / "Chapter 1" style headings.
    var detectNumbered = true
    /// Short ALL-CAPS lines on their own.
    var detectAllCaps = true
    /// Short, un-punctuated lines standing alone between blank lines.
    var detectShortLines = true
}

// MARK: - Model

struct Block: Identifiable {
    enum Kind {
        case paragraph(String)
        case listItem(text: String, indent: Int, marker: String)
        case pageBreak(page: Int) // page that *starts* here
    }
    let id = UUID()
    let kind: Kind
    var stripe = 0   // running index of text blocks, used for alternating backgrounds
}

final class Node: Identifiable, Hashable {
    let id = UUID()
    let level: Int          // 0 = root
    let title: String
    var blocks: [Block] = []
    var children: [Node] = []

    init(level: Int, title: String) {
        self.level = level
        self.title = title
    }

    static func == (l: Node, r: Node) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    func walk(_ f: (Node) -> Void) {
        f(self)
        children.forEach { $0.walk(f) }
    }

    /// IDs from the root's child down to the node with `target`, or nil.
    func path(to target: UUID) -> [UUID]? {
        if id == target { return [id] }
        for c in children {
            if let p = c.path(to: target) { return [id] + p }
        }
        return nil
    }
}

struct Document {
    var root = Node(level: 0, title: "")
    var pageCount = 1
    var headingCount = 0
    var maxLevel = 0
    var isEmpty: Bool { root.blocks.isEmpty && root.children.isEmpty }
}

// MARK: - Parser

enum Parser {
    private enum Tok {
        case line(String)
        case pageBreak(Int?)
    }

    private enum HStyle {
        case md(Int), underline(Int)
        case chapter, section
        case roman(String), alpha(String)
        case num(Int)
        case caps, short
    }

    private enum Raw {
        case heading(HStyle, String)
        case block(Block.Kind)
    }

    // Regex cache
    nonisolated(unsafe) private static var cache: [String: NSRegularExpression] = [:]
    private static func groups(_ s: String, _ pattern: String, ci: Bool = false) -> [String]? {
        let key = (ci ? "i:" : "c:") + pattern
        let re: NSRegularExpression
        if let c = cache[key] { re = c } else {
            guard let c = try? NSRegularExpression(pattern: pattern, options: ci ? [.caseInsensitive] : []) else { return nil }
            cache[key] = c; re = c
        }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    // MARK: Tokenize

    private static func tokenize(_ text: String) -> [Tok] {
        var t = text
        if t.hasPrefix("\u{FEFF}") { t.removeFirst() }
        t = t.replacingOccurrences(of: "\r\n", with: "\n")
             .replacingOccurrences(of: "\r", with: "\n")
             .replacingOccurrences(of: "\t", with: "    ")
             .replacingOccurrences(of: "\u{00A0}", with: " ")
        var toks: [Tok] = []
        for raw in t.split(separator: "\n", omittingEmptySubsequences: false) {
            let parts = raw.split(separator: "\u{0C}", omittingEmptySubsequences: false)
            for (k, p) in parts.enumerated() {
                if k > 0 { toks.append(.pageBreak(nil)) }
                toks.append(.line(String(p)))
            }
        }
        return toks
    }

    // MARK: Helpers

    private static func wordCount(_ s: String) -> Int { s.split(whereSeparator: \.isWhitespace).count }

    private static func headingLike(_ s: String, maxChars: Int = 80, maxWords: Int = 12) -> Bool {
        guard !s.isEmpty, s.count <= maxChars, wordCount(s) <= maxWords else { return false }
        if let last = s.last, ".,;".contains(last) { return false }
        return true
    }

    private static func startsUpper(_ s: String) -> Bool { s.first?.isUppercase == true }

    private static func isRomanNumeral(_ s: String) -> Bool {
        !s.isEmpty && groups(s, "^M{0,3}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})$") != nil
    }

    private static func isRuleLine(_ s: String) -> Bool {
        let core = s.filter { !$0.isWhitespace }
        guard core.count >= 3, let f = core.first, "-=_*~#".contains(f) else { return false }
        return core.allSatisfy { $0 == f }
    }

    private static func joinLines(_ ls: [String]) -> String {
        var out = ""
        for l in ls {
            if out.isEmpty { out = l }
            else if out.hasSuffix("-"), let f = l.first, f.isLowercase,
                    out.dropLast().last?.isLetter == true {
                out.removeLast(); out += l           // de-hyphenate "exam-\nple"
            } else { out += " " + l }
        }
        return out
    }

    // MARK: Parse

    static func parse(_ text: String, options: ParseOptions = ParseOptions()) -> Document {
        let toks = tokenize(text)
        var raws: [Raw] = []
        var para: [String] = []
        var list: (indent: Int, marker: String, lines: [String])? = nil

        func isBlank(_ k: Int) -> Bool {
            guard k >= 0, k < toks.count else { return true }
            switch toks[k] {
            case .pageBreak: return true
            case .line(let s): return s.trimmingCharacters(in: .whitespaces).isEmpty
            }
        }
        func lineText(_ k: Int) -> String? {
            guard k >= 0, k < toks.count, case .line(let s) = toks[k] else { return nil }
            return s.trimmingCharacters(in: .whitespaces)
        }
        func textFollows(after k: Int) -> Bool {
            var j = k + 1
            while j < toks.count {
                if case .line(let s) = toks[j] {
                    if !s.trimmingCharacters(in: .whitespaces).isEmpty { return true }
                } else { return false }
                j += 1
            }
            return false
        }
        func flushPara() {
            guard !para.isEmpty else { return }
            let t = options.joinWrappedLines
                ? joinLines(para).replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
                : para.joined(separator: "\n")
            raws.append(.block(.paragraph(t)))
            para = []
        }
        func flushList() {
            guard let l = list else { return }
            let t = options.joinWrappedLines ? joinLines(l.lines) : l.lines.joined(separator: "\n")
            raws.append(.block(.listItem(text: t, indent: l.indent, marker: l.marker)))
            list = nil
        }
        func flushAll() { flushPara(); flushList() }
        func heading(_ s: HStyle, _ t: String) { flushAll(); raws.append(.heading(s, t)) }

        // Numbered series that clearly organise the document: "1) … 2) … 3) …" (or "1. 2. 3.") standing
        // alone, with sub-steps in the *other* style ("1." under "1)") between them. These are headings
        // however long the line is.
        var forced = Set<Int>()
        if options.detectNumbered {
            for delim in [")", "."] {
                let other = delim == ")" ? "." : ")"
                let pat = #"^(\d+)\"# + delim + #"\s+(\S.*)$"#
                var seq: [Int] = []
                var expected = 1
                func commit() {
                    defer { seq = []; expected = 1 }
                    guard seq.count >= 2, let a = seq.first, let b = seq.last else { return }
                    let sub = #"^\s*\d+\"# + other + #"\s+\S"#
                    let hasSub = (a..<b).contains { k in lineText(k).map { groups($0, sub) != nil } ?? false }
                    if hasSub { forced.formUnion(seq) }
                }
                for k in 0..<toks.count {
                    guard let t = lineText(k), isBlank(k - 1), let g = groups(t, pat), startsUpper(g[2]) else { continue }
                    if let n = Int(g[1]), n == expected { seq.append(k); expected += 1 }
                    else if Int(g[1]) == 1 { commit(); seq = [k]; expected = 2 }
                }
                commit()
            }
        }

        var page = 1
        func addBreak(_ n: Int?) {
            flushAll()
            if case .block(.pageBreak)? = raws.last {   // consecutive markers = one break
                raws.removeLast(); page = n ?? page
            } else { page = n ?? page + 1 }
            raws.append(.block(.pageBreak(page: page)))
        }
        var i = 0
        while i < toks.count {
            defer { i += 1 }
            switch toks[i] {
            case .pageBreak(let n):
                addBreak(n)
            case .line(let rawLine):
                let t = rawLine.trimmingCharacters(in: .whitespaces)
                if t.isEmpty { flushAll(); continue }

                // Page markers
                if isRuleLine(t) {
                    addBreak(nil); continue
                }
                if let g = groups(t, #"^(?:page|p\.?)\s*(\d+)(?:\s*(?:of|/)\s*\d+)?$"#, ci: true)
                    ?? groups(t, #"^[-–—]\s*(\d+)\s*[-–—]$"#) {
                    addBreak(Int(g[1])); continue
                }

                let prevBlank = isBlank(i - 1)
                let nextBlank = isBlank(i + 1)

                // Setext underline
                if t.count <= 100, let u = lineText(i + 1), u.count >= 3 {
                    if u.allSatisfy({ $0 == "=" }) { heading(.underline(1), t); i += 1; continue }
                    if u.allSatisfy({ $0 == "-" }) { heading(.underline(2), t); i += 1; continue }
                }

                // Markdown
                if let g = groups(t, #"^(#{1,6})\s+(.+?)\s*#*$"#) {
                    heading(.md(g[1].count), g[2]); continue
                }

                if forced.contains(i) { heading(.num(1), t); continue }

                if options.detectNumbered {
                    // Chapter / Part / Section ...
                    if prevBlank, headingLike(t, maxChars: 80, maxWords: 10),
                       let g = groups(t, #"^(chapter|part|book|appendix|section|article)\s+(\d+[a-z]?|[ivxlcdm]+|[a-z]|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b(.*)$"#, ci: true) {
                        let sec = ["section", "article"].contains(g[1].lowercased())
                        heading(sec ? .section : .chapter, t); continue
                    }
                    // 1.2.3 Title
                    if let g = groups(t, #"^(\d+(?:\.\d+)+)\.?\s+(\S.*)$"#),
                       headingLike(g[2]), startsUpper(g[2]) {
                        heading(.num(g[1].split(separator: ".").count), t); continue
                    }
                    // 1. Title  (only when standing alone, not part of a list run)
                    if prevBlank, list == nil, let g = groups(t, #"^(\d+)[.)]\s+(\S.*)$"#),
                       headingLike(g[2]), startsUpper(g[2]) {
                        let nextIsNumbered = lineText(i + 1).map { groups($0, #"^\d+[.)]\s+\S"#) != nil } ?? false
                        if !nextIsNumbered { heading(.num(1), t); continue }
                    }
                    // I. Title
                    if prevBlank, let g = groups(t, #"^([IVXLCDM]+)[.)]\s+(\S.*)$"#),
                       isRomanNumeral(g[1]), headingLike(g[2]), startsUpper(g[2]) {
                        heading(g[1].count == 1 && g[1] != "I" ? .alpha(g[1]) : .roman(g[1]), t); continue
                    }
                    // A. Title
                    if prevBlank, let g = groups(t, #"^([A-Z])[.)]\s+(\S.*)$"#),
                       headingLike(g[2]), startsUpper(g[2]) {
                        heading(.alpha(g[1]), t); continue
                    }
                }

                // ALL CAPS
                if options.detectAllCaps, prevBlank, headingLike(t),
                   t.filter(\.isLetter).count >= 3, !t.contains(where: \.isLowercase) {
                    heading(.caps, t); continue
                }

                // Short stand-alone line
                if options.detectShortLines, prevBlank, nextBlank, textFollows(after: i),
                   t.count <= 60, wordCount(t) <= 8,
                   let l = t.last, !".,;!".contains(l),
                   let f = t.first, f.isUppercase || f.isNumber,
                   groups(t, #"^([-*•·▪‣◦–]|\d+[.)]|[a-zA-Z][.)])\s"#) == nil {
                    heading(.short, t); continue
                }

                // List items
                if let g = groups(rawLine, #"^(\s*)([-*•·▪‣◦–]|\d+[.)]|[a-zA-Z][.)])\s+(\S.*)$"#) {
                    flushAll()
                    list = (indent: g[1].count, marker: g[2], lines: [g[3].trimmingCharacters(in: .whitespaces)])
                    continue
                }
                if var l = list {
                    let indent = rawLine.prefix { $0 == " " }.count
                    if indent > l.indent {
                        l.lines.append(t); list = l; continue
                    }
                    flushList()
                }

                para.append(t)
            }
        }
        flushAll()

        return build(raws)
    }

    // MARK: Level assignment + tree

    private static func build(_ rawsIn: [Raw]) -> Document {
        var raws = rawsIn

        // Single I/V/X/L/C/D/M alpha headings become roman if the doc clearly uses roman numerals.
        let hasMultiRoman = raws.contains { if case .heading(.roman(let m), _) = $0 { return m.count > 1 } else { return false } }
        if hasMultiRoman {
            raws = raws.map {
                if case .heading(.alpha(let m), let t) = $0, isRomanNumeral(m) { return .heading(.roman(m), t) }
                return $0
            }
        }
        let hasRoman = raws.contains { if case .heading(.roman, _) = $0 { return true } else { return false } }
        let hasAlpha = raws.contains { if case .heading(.alpha, _) = $0 { return true } else { return false } }
        let offset = (hasRoman ? 1 : 0) + (hasAlpha ? 1 : 0)

        func natural(_ s: HStyle) -> Int {
            switch s {
            case .md(let n), .underline(let n): return n
            case .chapter, .roman, .caps: return 1
            case .section: return 2
            case .alpha: return 1 + (hasRoman ? 1 : 0)
            case .num(let d): return d + offset
            case .short: return 9
            }
        }

        // Compress used levels to 1...n (capped at 6) so there are no gaps.
        let used = Set(raws.compactMap { r -> Int? in
            if case .heading(let s, _) = r { if case .short = s { return nil }; return natural(s) } else { return nil }
        }).sorted()
        var rank: [Int: Int] = [:]
        for (k, l) in used.enumerated() { rank[l] = min(k + 1, 6) }

        var doc = Document()
        var stack = [doc.root]
        var shortNodes: Set<UUID> = []
        var page = 1
        var stripe = 0
        for r in raws {
            switch r {
            case .heading(let s, let text):
                var isShort = false
                if case .short = s { isShort = true }
                let lvl: Int
                if isShort {
                    // Un-numbered title lines nest one step under whatever heading is current
                    // (siblings of each other, never chained).
                    let top = stack.last!
                    lvl = shortNodes.contains(top.id) ? top.level : min(top.level + 1, 6)
                } else {
                    lvl = rank[natural(s)] ?? 1
                }
                while let top = stack.last, top.level >= lvl, stack.count > 1 { stack.removeLast() }
                let n = Node(level: lvl, title: text)
                if isShort { shortNodes.insert(n.id) }
                stack.last!.children.append(n)
                stack.append(n)
                doc.headingCount += 1
                doc.maxLevel = max(doc.maxLevel, lvl)
            case .block(let k):
                if case .pageBreak(let p) = k { page = max(page, p) }
                var b = Block(kind: k)
                if case .pageBreak = k {} else { b.stripe = stripe; stripe += 1 }
                stack.last!.blocks.append(b)
            }
        }
        doc.pageCount = page
        return doc
    }
}

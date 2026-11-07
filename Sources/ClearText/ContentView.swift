import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(DocModel.self) private var model
    @AppStorage("bodySize") private var bodySize = Theme.defaultBodySize
    @AppStorage("levelColors") private var colorString = Theme.encode(Theme.defaultHex)
    @AppStorage("stripePreset") private var stripePreset = 0
    @AppStorage("fontName") private var fontName = "System"
    @AppStorage("markColor") private var markColor = 0
    @AppStorage("markWidth") private var markWidth = 1
    @AppStorage("markTint") private var markTint = false
    @AppStorage("selectionColor") private var selectionColor = 0
    @State private var showOptions = false
    @State private var showStyle = false
    @State private var dropTargeted = false

    private var theme: Theme { Theme(bodySize: bodySize, colorString: colorString, fontName: fontName) }

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 400)
        } detail: {
            detail
        }
        .environment(\.theme, theme)
        .navigationTitle(model.fileName ?? "ClearText")
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        .onChange(of: model.options) { model.reparse() }
        .onChange(of: model.showOriginal) {
            if !model.showOriginal && model.sourceDirty { model.sourceDirty = false; model.reparse() }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in model.load(url: url) } }
            }
            return true
        }
        .overlay { if dropTargeted { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 3).padding(4).allowsHitTesting(false) } }
        .alert("Error", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") {}
        } message: { Text(model.errorMessage ?? "") }
        .frame(minWidth: 760, minHeight: 480)
    }

    private var subtitle: String {
        let d = model.doc
        guard !d.isEmpty else { return "" }
        return "\(d.headingCount) headings · \(d.pageCount) page\(d.pageCount == 1 ? "" : "s")"
    }

    // MARK: Sidebar

    private var sidebar: some View {
        Group {
            if model.doc.root.children.isEmpty {
                Text("No headings found").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.doc.root.children) { OutlineRow(node: $0) }
                }
                .listStyle(.sidebar)
            }
        }
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        if model.fileName == nil && model.sourceText.isEmpty {
            ContentUnavailableView {
                Label("Open a messy text file", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("Drop a .txt file here, or open one. Headings, nesting, paragraphs and page breaks are detected automatically.")
            } actions: {
                Button("Open…") { model.openPanel() }.keyboardShortcut(.defaultAction)
                Button("Paste from Clipboard") { model.loadClipboard() }
            }
        } else if model.showOriginal {
            TextEditor(text: Binding(
                get: { model.sourceText },
                set: { model.sourceText = $0; model.sourceDirty = true }))
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(20)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.doc.root.blocks) { BlockView(block: $0) }
                        ForEach(model.doc.root.children) { SectionView(node: $0) }
                    }
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 32).padding(.vertical, 24)
                }
                .onChange(of: model.scrollTick) {
                    guard let id = model.scrollTarget else { return }
                    withAnimation { proxy.scrollTo(id, anchor: model.scrollAnchor) }
                }
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        @Bindable var model = model
        ToolbarItemGroup {
            Button { model.openPanel() } label: { Label("Open", systemImage: "folder") }
                .help("Open a text file (⌘O)")
            Button { model.loadClipboard() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                .help("Organize text from the clipboard (⇧⌘V)")
        }
        ToolbarItemGroup {
            Button { model.clear() } label: { Label("Clear", systemImage: "xmark.circle") }
                .help("Clear the opened file and pasted text (⌘K)")
                .disabled(model.fileName == nil && model.sourceText.isEmpty)
            Picker("View", selection: $model.showOriginal) {
                Text("Organized").tag(false)
                Text("Original").tag(true)
            }
            .pickerStyle(.segmented)
            .disabled(model.sourceText.isEmpty)

            Button { model.expandAll() } label: { Label("Expand All", systemImage: "arrow.down.right.and.arrow.up.left") }
                .help("Expand all sections")
            Button { model.collapseAll() } label: { Label("Collapse All", systemImage: "arrow.up.left.and.arrow.down.right") }
                .help("Collapse all sections")
            Button { model.jumpToMark() } label: { Label("Jump to Mark", systemImage: "bookmark.fill") }
                .help("Jump to your reading mark (⌘J). Hover a paragraph and click its bookmark icon to set one.")
                .keyboardShortcut("j")
                .disabled(model.markedBlock == nil || model.showOriginal)
            Button { model.markedBlock = nil } label: { Label("Clear Mark", systemImage: "bookmark.slash") }
                .help("Remove the reading mark")
                .disabled(model.markedBlock == nil)
        }
        ToolbarItemGroup {
            Button { showOptions.toggle() } label: { Label("Detection", systemImage: "wand.and.stars") }
                .help("Detection options")
                .popover(isPresented: $showOptions) { optionsPanel }
            Button { showStyle.toggle() } label: { Label("Style", systemImage: "paintpalette") }
                .help("Heading sizes and colors")
                .popover(isPresented: $showStyle) { stylePanel }
            Button { model.exportMarkdown() } label: { Label("Export", systemImage: "square.and.arrow.up") }
                .help("Export as Markdown")
                .disabled(model.doc.isEmpty)
        }
    }

    private var optionsPanel: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 10) {
            Text("Detection").font(.headline)
            Toggle("Join wrapped lines into paragraphs", isOn: $model.options.joinWrappedLines)
            Toggle("Numbered & chapter headings (1., 1.2, I., A., Chapter 3)", isOn: $model.options.detectNumbered)
            Toggle("ALL CAPS lines", isOn: $model.options.detectAllCaps)
            Toggle("Short stand-alone lines", isOn: $model.options.detectShortLines)
            Text("Markdown (#) and underlined (===, ---) headings are always detected. Blank lines separate paragraphs; form feeds, rule lines (---) and “Page N” lines become page breaks.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(width: 360)
    }

    private var stylePanel: some View {
        ScrollView { stylePanelContent }
            .frame(width: 360, height: 620)
    }

    private var stylePanelContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Style").font(.headline)
            HStack {
                Text("Text size")
                Slider(value: $bodySize, in: 11...26, step: 1)
                Text("\(Int(bodySize)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            HStack {
                Text("Font")
                Spacer()
                Picker("Font", selection: $fontName) {
                    ForEach(Theme.fonts, id: \.self) { f in
                        Text(f == "System" ? "System (default)" : f)
                            .font(Theme.font(f, size: 13)).tag(f)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }
            Divider()
            Text("Alternating row color").font(.subheadline)
            HStack(spacing: 10) {
                ForEach(StripePreset.all) { p in
                    Button { stripePreset = p.id } label: {
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 6).fill(p.color)
                                .frame(width: 44, height: 28)
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(stripePreset == p.id ? Color.accentColor : Color.secondary.opacity(0.3),
                                                  lineWidth: stripePreset == p.id ? 2.5 : 1))
                            Text(p.name).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
                                .foregroundStyle(stripePreset == p.id ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(p.name)
                }
            }
            Divider()
            Text("Bookmark border").font(.subheadline)
            SwatchPicker(choices: MarkStyle.colors, selection: $markColor)
            Picker("Thickness", selection: $markWidth) {
                ForEach(0..<MarkStyle.widths.count, id: \.self) { Text(MarkStyle.widths[$0].name).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Also tint the marked paragraph", isOn: $markTint)
            Divider()
            Text("Highlight color for text selected with the mouse").font(.subheadline)
            SwatchPicker(choices: MarkStyle.selectionColors, selection: $selectionColor)
            Divider()
            ForEach(1...6, id: \.self) { lvl in
                HStack {
                    Text("Heading \(lvl)").font(theme.headingFont(lvl)).foregroundStyle(theme.color(lvl))
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { theme.color(lvl) },
                        set: { c in
                            var h = theme.hex; h[lvl - 1] = c.hexString
                            colorString = Theme.encode(h)
                        }), supportsOpacity: false)
                        .labelsHidden()
                }
            }
            Button("Reset to Defaults") {
                bodySize = Theme.defaultBodySize
                colorString = Theme.encode(Theme.defaultHex)
                stripePreset = 0
                fontName = "System"
                markColor = 0; markWidth = 1; markTint = false; selectionColor = 0
            }
        }
        .padding(16).frame(width: 340)
    }
}

// MARK: - Sidebar row

struct OutlineRow: View {
    @Environment(DocModel.self) private var model
    let node: Node
    @Environment(\.theme) private var theme

    private var label: some View {
        HStack(spacing: 6) {
            Circle().fill(theme.color(node.level)).frame(width: 7, height: 7)
            Text(node.title).lineLimit(1)
                .fontWeight(node.level <= 2 ? .semibold : .regular)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.reveal(node.id) }
    }

    var body: some View {
        if node.children.isEmpty {
            label
        } else {
            DisclosureGroup(isExpanded: Binding(
                get: { model.sidebarExpanded.contains(node.id) },
                set: { on in
                    if on { model.sidebarExpanded.insert(node.id) } else { model.sidebarExpanded.remove(node.id) }
                })) {
                ForEach(node.children) { OutlineRow(node: $0) }
            } label: { label }
        }
    }
}

// MARK: - Content

// MARK: - Organized document views

struct SectionView: View {
    @Environment(DocModel.self) private var model
    @Environment(\.theme) private var theme
    let node: Node

    var body: some View {
        let isCollapsed = model.collapsed.contains(node.id)
        let color = theme.color(node.level)
        let hasContent = !node.blocks.isEmpty || !node.children.isEmpty

        VStack(alignment: .leading, spacing: 10) {
            Button { model.toggle(node.id) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .font(.system(size: max(theme.bodySize * 0.6, 9), weight: .bold))
                        .foregroundStyle(color.opacity(hasContent ? 0.8 : 0.2))
                        .frame(width: 14)
                    Text(node.title)
                        .font(theme.headingFont(node.level))
                        .foregroundStyle(color)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, node.level <= 2 ? 10 : 4)

            if node.level == 1 { Divider().overlay(color.opacity(0.4)) }

            if !isCollapsed && hasContent {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(node.blocks) { BlockView(block: $0) }
                    ForEach(node.children) { SectionView(node: $0) }
                }
                .padding(.leading, 18)
                .overlay(alignment: .leading) {
                    Rectangle().fill(color.opacity(0.35)).frame(width: 2).padding(.leading, 5)
                }
            }
        }
        .id(node.id)
    }
}

struct BlockView: View {
    @Environment(DocModel.self) private var model
    @Environment(\.theme) private var theme
    @State private var hovering = false
    @AppStorage("markColor") private var markColor = 0
    @AppStorage("markWidth") private var markWidth = 1
    @AppStorage("markTint") private var markTint = false
    @AppStorage("selectionColor") private var selectionColor = 0
    @AppStorage("stripePreset") private var stripePreset = 0
    let block: Block

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            box
            bookmarkSlot
        }
        .onHover { hovering = $0 }
        .id(block.id)
    }

    /// The paragraph itself: row color, optional tint and the reading-mark border.
    private var box: some View {
        content
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isStriped ? StripePreset.preset(stripePreset).color : Color.clear)
                    if isMarked && markTint {
                        RoundedRectangle(cornerRadius: 5).fill(markTone.opacity(0.14))
                    }
                }
            }
            .overlay {
                if isMarked {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(markTone, lineWidth: MarkStyle.widths[min(max(markWidth, 0), 2)].value)
                }
            }
            .contextMenu {
                if isMarkable {
                    Button(isMarked ? "Remove Reading Mark" : "Mark Reading Position Here") { model.toggleMark(block.id) }
                }
            }
    }

    /// Fixed-size slot to the right of the paragraph. It is always laid out and only fades in and out,
    /// so showing the bookmark never moves or re-wraps the text.
    private var bookmarkSlot: some View {
        let visible = isMarkable && (hovering || isMarked)
        return Button { model.toggleMark(block.id) } label: {
            Image(systemName: isMarked ? "bookmark.fill" : "bookmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isMarked ? markTone : Color.secondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.primary.opacity(isMarked ? 0 : 0.08)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isMarked ? "Remove reading mark" : "Mark where I stopped reading")
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .frame(width: 32, height: 32)
    }

    private var isMarked: Bool { model.markedBlock == block.id }
    private var selectionTone: NSColor { NSColor(MarkStyle.color(MarkStyle.selectionColors, selectionColor)).withAlphaComponent(0.5) }
    private var markTone: Color { MarkStyle.color(MarkStyle.colors, markColor) }
    private var isMarkable: Bool { if case .pageBreak = block.kind { return false } else { return true } }

    private var isStriped: Bool {
        if case .pageBreak = block.kind { return false }
        return block.stripe % 2 == 1
    }

    @ViewBuilder private var content: some View {
        switch block.kind {
        case .paragraph(let t):
            SelectableText(text: t, font: theme.nsBodyFont, lineSpacing: theme.bodySize * 0.3, selectionColor: selectionTone)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .listItem(let t, let indent, let marker):
            HStack(alignment: .top, spacing: 8) {
                // Keep the source's numbering/lettering ("1.", "a)"); only bullets become •.
                Text(marker.first?.isLetter == true || marker.first?.isNumber == true ? marker : "•")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                SelectableText(text: t, font: theme.nsBodyFont, lineSpacing: theme.bodySize * 0.25, selectionColor: selectionTone)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(theme.bodyFont)
            .padding(.leading, CGFloat(min(indent, 12)) * 4 + 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .pageBreak(let p):
            HStack(spacing: 10) {
                line
                Text("PAGE \(p)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).tracking(1.2)
                line
            }
            .padding(.vertical, 6)
        }
    }

    private var line: some View {
        Rectangle().fill(.secondary.opacity(0.35)).frame(height: 1)
    }
}

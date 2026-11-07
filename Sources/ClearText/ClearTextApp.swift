import SwiftUI

@main
struct ClearTextApp: App {
    @State private var model = DocModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .onOpenURL { model.load(url: $0) }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About ClearText") {
                    let b = Bundle.main
                    let built = (b.object(forInfoDictionaryKey: "CTBuildDate") as? String) ?? "unknown"
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationVersion: (b.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.1",
                        .version: "",
                        .credits: NSAttributedString(string: "Version 1.1\nBuilt \(built)",
                            attributes: [.font: NSFont.systemFont(ofSize: 12),
                                         .paragraphStyle: { let p = NSMutableParagraphStyle(); p.alignment = .center; return p }()])
                    ])
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("Open…") { model.openPanel() }.keyboardShortcut("o")
                Button("Paste from Clipboard") { model.loadClipboard() }.keyboardShortcut("v", modifiers: [.command, .shift])
                Button("Clear") { model.clear() }.keyboardShortcut("k")
                    .disabled(model.fileName == nil && model.sourceText.isEmpty)
                Divider()
                Button("Export as Markdown…") { model.exportMarkdown() }
                    .keyboardShortcut("e").disabled(model.doc.isEmpty)
            }
        }
    }
}

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
            CommandGroup(replacing: .newItem) {
                Button("Open…") { model.openPanel() }.keyboardShortcut("o")
                Button("Paste from Clipboard") { model.loadClipboard() }.keyboardShortcut("v", modifiers: [.command, .shift])
                Divider()
                Button("Export as Markdown…") { model.exportMarkdown() }
                    .keyboardShortcut("e").disabled(model.doc.isEmpty)
            }
        }
    }
}

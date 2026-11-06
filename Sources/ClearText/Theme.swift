import SwiftUI
import AppKit

/// Per-level heading look. Colors are stored as comma-separated hex in AppStorage.
struct Theme {
    static let defaultHex = ["#5B5BD6", "#0E8FB3", "#1E9E6A", "#D98E04", "#D6457A", "#7A7F8A"]
    static let defaultBodySize = 15.0
    private static let scale: [Double] = [1.5, 1.35, 1.2, 1.1, 1.05, 1.0]
    private static let weights: [Font.Weight] = [.bold, .bold, .semibold, .semibold, .medium, .medium]

    /// Popular, widely installed macOS fonts. "System" is the default San Francisco.
    static let fonts: [String] = ["System", "Helvetica Neue", "Arial", "Verdana", "Avenir Next",
                                  "Georgia", "Times New Roman", "Palatino", "Menlo", "Courier New"]

    var bodySize: Double
    var hex: [String]
    var fontName: String

    init(bodySize: Double, colorString: String, fontName: String = "System") {
        self.bodySize = bodySize
        self.fontName = fontName
        let parts = colorString.split(separator: ",").map(String.init)
        self.hex = (0..<6).map { $0 < parts.count ? parts[$0] : Theme.defaultHex[$0] }
    }

    private func idx(_ level: Int) -> Int { min(max(level, 1), 6) - 1 }
    func color(_ level: Int) -> Color { Color(hex: hex[idx(level)]) }
    static func font(_ name: String, size: Double, weight: Font.Weight = .regular) -> Font {
        name == "System" ? .system(size: size, weight: weight) : .custom(name, size: size).weight(weight)
    }
    func headingFont(_ level: Int) -> Font {
        Theme.font(fontName, size: bodySize * Theme.scale[idx(level)], weight: Theme.weights[idx(level)])
    }
    var bodyFont: Font { Theme.font(fontName, size: bodySize) }
    var nsBodyFont: NSFont {
        fontName == "System" ? .systemFont(ofSize: bodySize) : (NSFont(name: fontName, size: bodySize) ?? .systemFont(ofSize: bodySize))
    }

    static func encode(_ hex: [String]) -> String { hex.joined(separator: ",") }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        if s.count != 6 { s = "808080" }
        let v = UInt32(s, radix: 16) ?? 0x808080
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }

    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
}

/// Soft, low-contrast backgrounds for alternating rows. Each has a light- and dark-mode tone
/// chosen to stay gentle on the eyes without hurting text contrast.
struct StripePreset: Identifiable {
    let id: Int
    let name: String
    let light: UInt32
    let dark: UInt32

    static let all: [StripePreset] = [
        .init(id: 0, name: "Mist Gray",   light: 0xDAE0EA, dark: 0x3C424D),
        .init(id: 1, name: "Sage Green",  light: 0xCBE3CF, dark: 0x2F4F37),
        .init(id: 2, name: "Warm Sand",   light: 0xEFDDAE, dark: 0x54451F),
        .init(id: 3, name: "Sky Blue",    light: 0xC4DCF5, dark: 0x2A4C73),
        .init(id: 4, name: "Lavender",    light: 0xDACDF3, dark: 0x43386B),
    ]
    static func preset(_ id: Int) -> StripePreset { all.first { $0.id == id } ?? all[0] }

    private static func ns(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
    /// Adapts automatically to light / dark appearance.
    var nsColor: NSColor {
        let l = Self.ns(light), d = Self.ns(dark)
        return NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? d : l
        }
    }
    var color: Color { Color(nsColor: nsColor) }
    var swatch: (light: Color, dark: Color) { (Color(nsColor: Self.ns(light)), Color(nsColor: Self.ns(dark))) }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(bodySize: Theme.defaultBodySize, colorString: Theme.encode(Theme.defaultHex))
}
extension EnvironmentValues {
    var theme: Theme { get { self[ThemeKey.self] } set { self[ThemeKey.self] = newValue } }
}

/// Choices for the reading-mark border and the color of mouse-selected text.
struct ColorChoice: Identifiable {
    let id: Int
    let name: String
    let hex: String
    var color: Color { Color(hex: hex) }
}

enum MarkStyle {
    static let colors: [ColorChoice] = [
        .init(id: 0, name: "Orange", hex: "#F5921E"), .init(id: 1, name: "Red", hex: "#E5484D"),
        .init(id: 2, name: "Green", hex: "#30A46C"), .init(id: 3, name: "Blue", hex: "#3E63DD"),
        .init(id: 4, name: "Purple", hex: "#8E4EC6"),
    ]
    static let selectionColors: [ColorChoice] = [
        .init(id: 0, name: "Yellow", hex: "#F5D90A"), .init(id: 1, name: "Sky", hex: "#52A9FF"),
        .init(id: 2, name: "Mint", hex: "#4CC38A"), .init(id: 3, name: "Pink", hex: "#F76B9C"),
        .init(id: 4, name: "Gray", hex: "#8B8D98"),
    ]
    static let widths: [(name: String, value: CGFloat)] = [("Thin", 1), ("Medium", 2), ("Thick", 3.5)]
    static func color(_ list: [ColorChoice], _ i: Int) -> Color { list[min(max(i, 0), list.count - 1)].color }
}

/// A row of round color swatches.
struct SwatchPicker: View {
    let choices: [ColorChoice]
    @Binding var selection: Int
    var body: some View {
        HStack(spacing: 10) {
            ForEach(choices) { c in
                Button { selection = c.id } label: {
                    Circle().fill(c.color).frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(selection == c.id ? 0.9 : 0.15),
                                                       lineWidth: selection == c.id ? 2.5 : 1))
                        .padding(2)
                }
                .buttonStyle(.plain)
                .help(c.name)
            }
        }
    }
}

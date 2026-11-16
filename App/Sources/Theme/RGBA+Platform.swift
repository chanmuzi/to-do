import AppKit
import SwiftUI

extension RGBA {
    public var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    public var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

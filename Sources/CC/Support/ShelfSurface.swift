import AppKit
import SwiftUI

enum ShelfSurface: Equatable {
    case regular
    case island

    var foreground: Color {
        self == .island ? .white.opacity(0.9) : .primary
    }

    var secondary: Color {
        self == .island ? .white.opacity(0.55) : .secondary
    }

    var controlBackground: Color {
        self == .island ? .white.opacity(0.07) : .primary.opacity(0.05)
    }

    var itemBackground: Color {
        self == .island ? .white.opacity(0.065) : .primary.opacity(0.035)
    }

    var tint: NSColor {
        self == .island ? .white : .labelColor
    }
}

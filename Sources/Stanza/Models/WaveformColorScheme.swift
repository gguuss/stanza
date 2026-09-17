import Foundation
import SwiftUI

public enum WaveformColorScheme: String, CaseIterable, Identifiable, Sendable {
    case classic = "Classic (Default)"
    case purpleMagenta = "Purple & Magenta"
    case blueViolet = "Blue & Violet"
    case amberLightBlue = "Amber & Light Blue"

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .classic: return "Classic"
        case .purpleMagenta: return "Purple / Magenta"
        case .blueViolet: return "Blue / Violet"
        case .amberLightBlue: return "Amber / Light Blue"
        }
    }

    /// Calculates the color for a normalized frequency value (0.0 = low frequency/bass, 1.0 = high frequency/treble)
    public func color(for frequency: Float) -> Color {
        let t = min(max(Double(frequency), 0.0), 1.0)
        switch self {
        case .classic:
            return Color(red: 0.52, green: 0.58, blue: 0.65)

        case .purpleMagenta:
            // Low: Deep Royal Purple (#5E17EB) -> High: Vibrant Neon Magenta (#FF007F)
            let r = 0.37 + t * (1.0 - 0.37)
            let g = 0.09 + t * (0.0 - 0.09)
            let b = 0.92 + t * (0.50 - 0.92)
            return Color(red: r, green: g, blue: b)

        case .blueViolet:
            // Low: Deep Electric Sapphire (#0066FF) -> High: Bright Violet/Orchid (#B026FF)
            let r = 0.00 + t * (0.69 - 0.00)
            let g = 0.40 + t * (0.15 - 0.40)
            let b = 1.00 + t * (1.00 - 1.00)
            return Color(red: r, green: g, blue: b)

        case .amberLightBlue:
            // Low: Warm Deep Amber/Gold (#FF7700) -> High: Crisp Ice Light Blue/Cyan (#00E5FF)
            let r = 1.00 + t * (0.00 - 1.00)
            let g = 0.47 + t * (0.90 - 0.47)
            let b = 0.00 + t * (1.00 - 0.00)
            return Color(red: r, green: g, blue: b)
        }
    }
}

import Foundation
import SwiftUI

public enum WaveformColorScheme: String, CaseIterable, Identifiable, Sendable {
    case classic = "Classic (Default)"
    case purpleMagenta = "Purple & Magenta"
    case blueViolet = "Blue & Violet"
    case amberLightBlue = "Amber & Light Blue"
    case rgb = "RGB (Red, Green, Blue)"

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .classic: return "Classic"
        case .purpleMagenta: return "Purple / Magenta"
        case .blueViolet: return "Blue / Violet"
        case .amberLightBlue: return "Amber / Light Blue"
        case .rgb: return "RGB"
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

        case .rgb:
            // Low Frequencies (Bass, sub-bass, kick drums): Red
            // Mid Frequencies (Vocals, lead melodies, guitars, synths): Yellow into Pure Green
            // High Frequencies (Hi-hats, cymbals, snares, risers): Cyan into Bright Blue
            let r: Double
            let g: Double
            let b: Double
            if t < 0.20 {
                let s = t / 0.20
                r = 0.96 + s * (0.98 - 0.96)
                g = 0.14 + s * (0.28 - 0.14)
                b = 0.14 + s * (0.10 - 0.14)
            } else if t < 0.35 {
                let s = (t - 0.20) / 0.15
                r = 0.98 + s * (0.96 - 0.98)
                g = 0.28 + s * (0.85 - 0.28)
                b = 0.10 + s * (0.10 - 0.10)
            } else if t < 0.50 {
                let s = (t - 0.35) / 0.15
                r = 0.96 + s * (0.12 - 0.96)
                g = 0.85 + s * (0.92 - 0.85)
                b = 0.10 + s * (0.28 - 0.10)
            } else if t < 0.70 {
                let s = (t - 0.50) / 0.20
                r = 0.12 + s * (0.08 - 0.12)
                g = 0.92 + s * (0.82 - 0.92)
                b = 0.28 + s * (0.92 - 0.28)
            } else {
                let s = min(1.0, (t - 0.70) / 0.30)
                r = 0.08 + s * (0.20 - 0.08)
                g = 0.82 + s * (0.48 - 0.82)
                b = 0.92 + s * (1.00 - 0.92)
            }
            return Color(red: r, green: g, blue: b)
        }
    }
}

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
        let v = simd4Color(for: frequency)
        return Color(red: Double(v.x), green: Double(v.y), blue: Double(v.z), opacity: Double(v.w))
    }

    /// Accent / peak-cap color corresponding to the color scheme
    public var peakSIMD4Color: SIMD4<Float> {
        switch self {
        case .classic:
            return SIMD4<Float>(1.00, 0.85, 0.40, 1.0) // Neon Amber / Gold
        case .purpleMagenta:
            return SIMD4<Float>(1.00, 0.60, 0.90, 1.0) // Vibrant Neon Magenta
        case .blueViolet:
            return SIMD4<Float>(0.80, 0.90, 1.00, 1.0) // Electric Ice Blue
        case .amberLightBlue:
            return SIMD4<Float>(1.00, 0.90, 0.45, 1.0) // Radiant Gold
        case .rgb:
            return SIMD4<Float>(1.00, 1.00, 0.70, 1.0) // Bright Sun Yellow
        }
    }

    /// Color for peak-cap indicators
    public var peakColor: Color {
        let p = peakSIMD4Color
        return Color(red: Double(p.x), green: Double(p.y), blue: Double(p.z), opacity: Double(p.w))
    }

    /// Primary accent color for curves, glows, and overlays
    public var accentColor: Color {
        switch self {
        case .classic:
            return Color(red: 0.10, green: 0.75, blue: 0.95)
        case .purpleMagenta:
            return Color(red: 1.00, green: 0.20, blue: 0.80)
        case .blueViolet:
            return Color(red: 0.55, green: 0.40, blue: 1.00)
        case .amberLightBlue:
            return Color(red: 0.00, green: 0.90, blue: 1.00)
        case .rgb:
            return Color(red: 0.20, green: 0.90, blue: 0.50)
        }
    }

    /// Calculates the SIMD4<Float> RGBA vector for a normalized frequency value
    public func simd4Color(for frequency: Float) -> SIMD4<Float> {
        let t = min(max(frequency, 0.0), 1.0)
        switch self {
        case .classic:
            // Multi-stop classic audio spectrum gradient:
            // 0.00: Deep Blue (#0D59B2: 0.05, 0.35, 0.70)
            // 0.55: Electric Cyan (#1ABFF2: 0.10, 0.75, 0.95)
            // 0.85: Neon Amber (#FFA626: 1.00, 0.65, 0.15)
            // 1.00: Bright Coral (#FF4726: 1.00, 0.28, 0.15)
            let r: Float
            let g: Float
            let b: Float
            if t <= 0.55 {
                let s = t / 0.55
                r = 0.05 + s * (0.10 - 0.05)
                g = 0.35 + s * (0.75 - 0.35)
                b = 0.70 + s * (0.95 - 0.70)
            } else if t <= 0.85 {
                let s = (t - 0.55) / 0.30
                r = 0.10 + s * (1.00 - 0.10)
                g = 0.75 + s * (0.65 - 0.75)
                b = 0.95 + s * (0.15 - 0.95)
            } else {
                let s = (t - 0.85) / 0.15
                r = 1.00
                g = 0.65 + s * (0.28 - 0.65)
                b = 0.15
            }
            return SIMD4<Float>(r, g, b, 1.0)

        case .purpleMagenta:
            // Low: Deep Royal Purple (#5E17EB) -> High: Vibrant Neon Magenta (#FF007F)
            let r = 0.37 + t * (1.0 - 0.37)
            let g = 0.09 + t * (0.0 - 0.09)
            let b = 0.92 + t * (0.50 - 0.92)
            return SIMD4<Float>(r, g, b, 1.0)

        case .blueViolet:
            // Low: Deep Electric Sapphire (#0066FF) -> High: Bright Violet/Orchid (#B026FF)
            let r = 0.00 + t * (0.69 - 0.00)
            let g = 0.40 + t * (0.15 - 0.40)
            let b = 1.00 + t * (1.00 - 1.00)
            return SIMD4<Float>(r, g, b, 1.0)

        case .amberLightBlue:
            // Low: Warm Deep Amber/Gold (#FF7700) -> High: Crisp Ice Light Blue/Cyan (#00E5FF)
            let r = 1.00 + t * (0.00 - 1.00)
            let g = 0.47 + t * (0.90 - 0.47)
            let b = 0.00 + t * (1.00 - 0.00)
            return SIMD4<Float>(r, g, b, 1.0)

        case .rgb:
            // Low Frequencies (Bass, sub-bass, kick drums): Red
            // Mid Frequencies (Vocals, lead melodies, guitars, synths): Yellow into Pure Green
            // High Frequencies (Hi-hats, cymbals, snares, risers): Cyan into Bright Blue
            let r: Float
            let g: Float
            let b: Float
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
            return SIMD4<Float>(r, g, b, 1.0)
        }
    }
}

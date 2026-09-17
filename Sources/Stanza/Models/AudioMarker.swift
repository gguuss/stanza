import Foundation
import SwiftUI

public struct AudioMarker: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var timestamp: TimeInterval  // Start time in seconds
    public var endTime: TimeInterval?   // Optional end time for region markers; nil for point markers
    public var colorHex: String         // Hex string (e.g. "#FF3B30", "#00E5FF", etc.)
    public var notes: String?

    public init(
        id: UUID = UUID(),
        name: String,
        timestamp: TimeInterval,
        endTime: TimeInterval? = nil,
        colorHex: String = "#FF9500",
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.timestamp = max(0, timestamp)
        if let end = endTime, end > self.timestamp {
            self.endTime = end
        } else {
            self.endTime = nil
        }
        self.colorHex = colorHex
        self.notes = notes
    }

    public var isRegion: Bool {
        if let end = endTime {
            return end > timestamp + 0.05
        }
        return false
    }

    public var duration: TimeInterval {
        if let end = endTime, end > timestamp {
            return end - timestamp
        }
        return 0
    }

    public var formattedTimestamp: String {
        Self.formatTime(timestamp)
    }

    public var formattedEndTime: String? {
        guard let end = endTime else { return nil }
        return Self.formatTime(end)
    }

    public var formattedDuration: String {
        guard isRegion else { return "" }
        let d = duration
        if d >= 60 {
            let m = Int(d) / 60
            let s = d.truncatingRemainder(dividingBy: 60)
            return String(format: "%dm %.1fs", m, s)
        } else {
            return String(format: "%.2fs", d)
        }
    }

    public var color: Color {
        Color(hex: colorHex) ?? Color.orange
    }

    public static func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite && time >= 0 else { return "0:00.00" }
        let totalHundredths = Int((time * 100).rounded())
        let hundredths = totalHundredths % 100
        let totalSeconds = totalHundredths / 100
        let seconds = totalSeconds % 60
        let minutes = totalSeconds / 60
        return String(format: "%d:%02d.%02d", minutes, seconds, hundredths)
    }

    public static let presetColors: [String] = [
        "#FF3B30", // Red (Bass / Drops)
        "#FF9500", // Orange
        "#FFCC00", // Yellow (Vocals / Leads)
        "#34C759", // Green (Breakdowns)
        "#00E5FF", // Cyan
        "#007AFF", // Blue (Treble / Cymbals)
        "#AF52DE", // Purple
        "#FF2D55"  // Pink / Magenta
    ]
}

// MARK: - Color Hex Conversion Extension

extension Color {
    public init?(hex: String) {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHex.hasPrefix("#") {
            cleanHex.removeFirst()
        }
        guard cleanHex.count == 6 || cleanHex.count == 8 else { return nil }

        var rgbValue: UInt64 = 0
        guard Scanner(string: cleanHex).scanHexInt64(&rgbValue) else { return nil }

        let r, g, b, a: Double
        if cleanHex.count == 6 {
            r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
            g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
            b = Double(rgbValue & 0x0000FF) / 255.0
            a = 1.0
        } else {
            r = Double((rgbValue & 0xFF000000) >> 24) / 255.0
            g = Double((rgbValue & 0x00FF0000) >> 16) / 255.0
            b = Double((rgbValue & 0x0000FF00) >> 8) / 255.0
            a = Double(rgbValue & 0x000000FF) / 255.0
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    public func toHex() -> String {
        #if canImport(AppKit)
        let nsColor = NSColor(self)
        guard let rgbColor = nsColor.usingColorSpace(.sRGB) else { return "#FF9500" }
        let r = Int(rgbColor.redComponent * 255.0)
        let g = Int(rgbColor.greenComponent * 255.0)
        let b = Int(rgbColor.blueComponent * 255.0)
        return String(format: "#%02X%02X%02X", r, g, b)
        #else
        return "#FF9500"
        #endif
    }
}

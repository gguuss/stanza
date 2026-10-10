import Foundation

/// Defines the analysis time window (FFT size) for the real-time spectrum analyzer.
/// Smaller windows reduce latency and averaging time for punchy, fast transient response.
public enum SpectrumTimeWindow: Int, CaseIterable, Identifiable, Sendable {
    /// 512 samples (~11.6 ms at 44.1 kHz): ultra-fast transient tracking with minimal averaging time.
    case small = 512

    /// 1024 samples (~23.2 ms at 44.1 kHz): default responsive window balancing frequency and time resolution.
    case medium = 1024

    /// 2048 samples (~46.4 ms at 44.1 kHz): high frequency resolution with a longer analysis time window.
    case large = 2048

    public var id: Int { rawValue }

    public var fftSize: Int { rawValue }

    public var displayName: String {
        switch self {
        case .small: return "512 (11.6 ms - Fast)"
        case .medium: return "1024 (23.2 ms - Standard)"
        case .large: return "2048 (46.4 ms - High Res)"
        }
    }

    public var shortTitle: String {
        switch self {
        case .small: return "512 (11ms)"
        case .medium: return "1024 (23ms)"
        case .large: return "2048 (46ms)"
        }
    }
}

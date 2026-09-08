import SwiftUI

public struct QueueRowView: View {
    let track: AudioTrack
    let isCurrentTrack: Bool
    let isPlaying: Bool
    let isSelected: Bool
    let index: Int

    public var body: some View {
        HStack(spacing: 8) {
            // Index or Playing indicator
            HStack(spacing: 4) {
                if isCurrentTrack {
                    Image(systemName: isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.15))
                        .frame(width: 14)
                } else {
                    Text(String(format: "%02d", index + 1))
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                        .frame(width: 16, alignment: .trailing)
                }
            }

            // File Name
            Text(track.filename)
                .font(.system(size: 12, weight: isCurrentTrack ? .bold : .regular))
                .foregroundColor(isCurrentTrack ? Color(red: 1.0, green: 0.65, blue: 0.25) : .white)
                .lineLimit(1)
                .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)

            // File Size
            Text(track.formattedFileSize)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 65, alignment: .trailing)

            // Length
            Text(track.formattedDuration)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(isCurrentTrack ? Color(red: 1.0, green: 0.65, blue: 0.25) : .white.opacity(0.75))
                .frame(width: 65, alignment: .trailing)

            // Title
            Text(track.title)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(1)
                .frame(minWidth: 100, maxWidth: 200, alignment: .leading)

            // Artist
            Text(track.artist)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.45))
                .lineLimit(1)
                .frame(minWidth: 80, maxWidth: 140, alignment: .leading)

            // Format tag
            Text(track.formatName)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.white.opacity(0.08))
                .cornerRadius(3)
                .frame(width: 45, alignment: .center)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4.5)
        .background(
            isSelected
                ? Color.white.opacity(0.12)
                : (isCurrentTrack ? Color(red: 1.0, green: 0.45, blue: 0.15).opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

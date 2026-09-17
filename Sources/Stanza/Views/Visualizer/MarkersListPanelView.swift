import SwiftUI
import AppKit

public struct MarkersListPanelView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var audioEngine: AudioEngineController

    @State private var isExporting: Bool = false
    @State private var exportStatusMessage: String? = nil
    @State private var selectedSliceFormat: SliceFormat = .wav
    @State private var colorPickerMarkerID: UUID? = nil

    public init(appState: AppState) {
        self.appState = appState
        self.audioEngine = appState.audioEngine
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerView

            Divider().background(Color.white.opacity(0.12))

            // Markers List or Empty State
            if appState.activeMarkers.isEmpty {
                emptyStateView
            } else {
                markersListView
            }

            // Export feedback bar if active
            if let msg = exportStatusMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 11))
                    Text(msg)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.4))
            }
        }
        .frame(minWidth: 260, maxWidth: 360)
        .background(Color(nsColor: NSColor(red: 0.11, green: 0.12, blue: 0.14, alpha: 0.96)))
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(red: 1.0, green: 0.58, blue: 0.0))

                Text("Markers & Slices")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)

                if !appState.activeMarkers.isEmpty {
                    Text("\(appState.activeMarkers.count)")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            Spacer()

            // Add Marker Button
            Button {
                appState.addMarkerAtPlayhead()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.borderless)
            .help("Add Marker at Playhead (M)")

            // Actions Menu
            Menu {
                Button("Export All Slices as WAV...") {
                    exportAllSlices(format: .wav)
                }
                Button("Export All Slices as M4A...") {
                    exportAllSlices(format: .m4a)
                }
                Divider()
                Button("Export CUE Sheet (.cue)...") {
                    exportCueSheet()
                }
                Button("Export Rekordbox XML (.xml)...") {
                    appState.exportRekordboxXML(forCurrentTrackOnly: true)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .disabled(appState.activeMarkers.isEmpty || audioEngine.currentTrack == nil)
            .help("Export Options")

            // Close Panel Button
            Button {
                appState.isMarkersPanelVisible = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.45))
            }
            .buttonStyle(.borderless)
            .help("Close Markers Panel (Cmd+Shift+M)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "flag.badge.ellipsis")
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.25))

            Text("No Markers for Track")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))

            Text("Press 'M' while listening to drop a cue at the playhead, or drag across the waveform to create a region slice.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Button {
                appState.addMarkerAtPlayhead()
            } label: {
                Label("Add Cue at Playhead", systemImage: "plus")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(Color(red: 1.0, green: 0.58, blue: 0.0))
            .disabled(audioEngine.currentTrack == nil)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var markersListView: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(appState.activeMarkers) { marker in
                    markerRowView(marker: marker)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    private func markerRowView(marker: AudioMarker) -> some View {
        let isSelected = appState.selectedMarkerID == marker.id
        return HStack(spacing: 8) {
            // Color tag dot with popup color selector
            Button {
                colorPickerMarkerID = marker.id
            } label: {
                Circle()
                    .fill(marker.color)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 0.75))
            }
            .buttonStyle(.borderless)
            .popover(isPresented: Binding(
                get: { colorPickerMarkerID == marker.id },
                set: { if !$0 { colorPickerMarkerID = nil } }
            )) {
                colorPalettePopover(for: marker)
            }
            .help("Change Marker Color")

            // Title & Timestamp
            VStack(alignment: .leading, spacing: 2) {
                TextField("Marker Name", text: Binding(
                    get: { marker.name },
                    set: { newName in
                        var updated = marker
                        updated.name = newName
                        appState.updateMarker(updated)
                    }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)

                HStack(spacing: 5) {
                    Text(marker.formattedTimestamp)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundColor(marker.color.opacity(0.95))

                    if marker.isRegion {
                        Text("•")
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.3))
                        Text(marker.formattedDuration)
                            .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }

            Spacer(minLength: 4)

            // Jump to Marker Button
            Button {
                appState.jumpToMarker(marker)
            } label: {
                Image(systemName: "arrow.right.to.line")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.75))
            }
            .buttonStyle(.borderless)
            .help("Jump Playhead to Marker")

            // Loop Region Button
            Button {
                appState.loopMarkerRegion(marker)
            } label: {
                Image(systemName: "repeat")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(isCurrentlyLooping(marker: marker) ? Color(red: 1.0, green: 0.45, blue: 0.15) : .white.opacity(0.5))
            }
            .buttonStyle(.borderless)
            .help(marker.isRegion ? "Loop This Region" : "Loop to Next Marker")

            // Export Slice Button
            Button {
                exportSingleSlice(marker: marker)
            } label: {
                Image(systemName: "scissors")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
            }
            .buttonStyle(.borderless)
            .help("Export This Audio Slice")

            // Delete Marker Button
            Button {
                appState.deleteMarker(id: marker.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.borderless)
            .help("Delete Marker")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isSelected ? Color.white.opacity(0.10) : Color.white.opacity(0.04))
        .cornerRadius(5)
        .contentShape(Rectangle())
        .onTapGesture {
            appState.selectedMarkerID = marker.id
        }
    }

    private func colorPalettePopover(for marker: AudioMarker) -> some View {
        HStack(spacing: 6) {
            ForEach(AudioMarker.presetColors, id: \.self) { hex in
                Button {
                    var updated = marker
                    updated.colorHex = hex
                    appState.updateMarker(updated)
                    colorPickerMarkerID = nil
                } label: {
                    Circle()
                        .fill(Color(hex: hex) ?? Color.orange)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: marker.colorHex.uppercased() == hex.uppercased() ? 2 : 0)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
    }

    private func isCurrentlyLooping(marker: AudioMarker) -> Bool {
        guard let range = audioEngine.loopRange, let track = audioEngine.currentTrack else { return false }
        let effective = AudioSlicer.shared.effectiveTimeRange(for: marker, in: appState.activeMarkers, trackDuration: track.duration)
        return abs(range.lowerBound - effective.start) < 0.05 && abs(range.upperBound - effective.end) < 0.05
    }

    // MARK: - Export Logic

    private func exportSingleSlice(marker: AudioMarker) {
        guard let track = audioEngine.currentTrack else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.wav, .mpeg4Audio]
        let defaultName = "\(track.title.isEmpty ? track.filename : track.title) - \(marker.name).wav"
        panel.nameFieldStringValue = defaultName
        panel.title = "Export Audio Slice"

        if panel.runModal() == .OK, let destinationURL = panel.url {
            let format: SliceFormat = destinationURL.pathExtension.lowercased() == "m4a" ? .m4a : .wav
            Task { @MainActor in
                do {
                    try await AudioSlicer.shared.exportSlice(
                        track: track,
                        marker: marker,
                        allMarkers: appState.activeMarkers,
                        destinationURL: destinationURL,
                        format: format
                    )
                    showExportFeedback("Exported slice '\(destinationURL.lastPathComponent)'")
                } catch {
                    appState.statusMessage = "Export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func exportAllSlices(format: SliceFormat) {
        guard let track = audioEngine.currentTrack else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose destination directory for \(format.rawValue) slices"

        if panel.runModal() == .OK, let destinationDir = panel.url {
            Task { @MainActor in
                do {
                    let files = try await AudioSlicer.shared.exportAllSlices(
                        track: track,
                        markers: appState.activeMarkers,
                        destinationFolder: destinationDir,
                        format: format
                    )
                    showExportFeedback("Exported \(files.count) slice(s) to \(destinationDir.lastPathComponent)")
                } catch {
                    appState.statusMessage = "Export all failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func exportCueSheet() {
        guard let track = audioEngine.currentTrack else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.init(filenameExtension: "cue") ?? .plainText]
        let defaultName = "\(track.url.deletingPathExtension().lastPathComponent).cue"
        panel.nameFieldStringValue = defaultName
        panel.title = "Export CUE Sheet"

        if panel.runModal() == .OK, let destinationURL = panel.url {
            do {
                try MarkerStorage.shared.exportCueSheet(for: track, markers: appState.activeMarkers, to: destinationURL)
                showExportFeedback("Exported CUE sheet to \(destinationURL.lastPathComponent)")
            } catch {
                appState.statusMessage = "CUE export failed: \(error.localizedDescription)"
            }
        }
    }

    private func showExportFeedback(_ message: String) {
        exportStatusMessage = message
        appState.statusMessage = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if exportStatusMessage == message {
                exportStatusMessage = nil
            }
        }
    }
}

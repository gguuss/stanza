# Stanza Roadmap

This document outlines planned features, enhancements, and known bugs/polish items targeted for upcoming releases of Stanza.

---

## 🚀 Planned Features

### 1. Persistent Playback & Last Opened Folder State
- **Description**: Remember and restore the last viewed/played directory across application restarts.
- **Details**:
  - Automatically persist the last active folder path and track selection in `UserDefaults` / `AppStorage`.
  - On launch without an external file open intent, immediately restore and open the previous folder session.

### 2. Recursive Folder Exploration (Alt + Click)
- **Description**: Allow viewing and listening to all audio files contained within a directory and all of its subdirectories recursively.
- **Details**:
  - `Option + Click` (Alt + Click) on any folder in the tree or sibling pane triggers a recursive directory scan.
  - Flattens all nested audio files into the media table with hierarchical subfolder relative path indicators.
  - Option to toggle recursive scanning via a button or keyboard modifier.

### 3. Waveform Zooming & Panning
- **Description**: High-resolution horizontal waveform zooming for detailed sample inspection and precise loop/marker positioning.
- **Details**:
  - Scroll-wheel / trackpad pinch-to-zoom on the waveform view.
  - Zoom levels ranging from 1x (full overview) up to sample-accurate zoom.
  - Horizontal panning / minimap overview bar indicating the current visible viewport.

### 4. Multi-Region Markers & Marker List
- **Description**: Add and manage multiple time markers and region loops within audio tracks.
- **Details**:
  - Keyboard shortcut (e.g. `M`) to drop markers at the current playhead timestamp.
  - Click-and-drag to create labeled named regions with custom start and end points.
  - Dedicated interactive **Markers List** panel in the player showing marker name, timestamp, region duration, and color tag.
  - Click a marker to jump playback instantly; loop toggle for individual regions.

### 5. Marker Section Exporting / Slicing
- **Description**: Export marked regions or slice audio at marker points.
- **Details**:
  - Batch export audio slices defined by marker boundaries (lossless cut or format transcode to WAV, FLAC, MP3).
  - Generate track chapter markers or standalone cue point files.

### 6. Folder-Level Marker Metadata Persistence
- **Description**: Save markers and region metadata alongside the audio files in their local directory.
- **Details**:
  - Store markers in a lightweight companion metadata file (e.g. `.stanza_markers.json` or `.cue`) within the track's folder.
  - Automatically reload and restore saved markers whenever the track or folder is revisited.
  - Non-destructive and safe for original audio files.

### 7. Rekordbox XML Integration
- **Description**: Export cues and markers directly into `rekordbox.xml` format.
- **Details**:
  - Generate and export Pioneer DJ / Rekordbox-compatible XML playlist and track definitions with hot cues, memory cues, and loop points.
  - Facilitates quick track preparation and library sharing between Stanza and DJ performance setups.

---

## 🐛 Bug Fixes & Technical Improvements

### 1. Default Startup Folder Restoration
- **Issue**: When launching Stanza without specifying a file from Finder or the command line, the player should restore the user's last visited folder rather than defaulting to an arbitrary state.
- **Resolution**: Wire initial app startup lifecycle to load `lastOpenedFolderURL` from preferences, falling back to `~/Music` only on fresh installs.

### 2. Setting Persistence vs Volatile State Management
- **Issue**: Certain preferences should persist across app relaunches, while playback transient states should always reset to standard defaults.
- **Persistent Settings (Persist on App Close)**:
  - Continuous vs Single-file playback mode (`isContinuousPlayback`).
  - Active visualizer mode (`stereoWaveform`, `frequency`, `stereoSpectrum`).
  - Explorer layout mode (Columns vs Stacked).
  - Volume level.
- **Volatile States (Always Reset to Default on Launch)**:
  - Reverse playback (always reset to forward playback).
  - Section loop range (always cleared on launch).
  - Playback state (always start stopped, ready for user trigger).
  - Mute / Dim states (reset to unmuted and full volume).

### 3. Spectral Visualizer Performance Optimization
- **Issue**: FFT spectral analysis and real-time visualization can consume unnecessary CPU cycles during sustained 60fps/120fps redraws.
- **Resolution**:
  - Explore dedicated high-performance native audio rendering components (Objective-C / C++ / Metal / CoreAnimation layer).
  - Optimize `AVAudioEngine` tap buffer deliveries with direct memory circular buffers.
  - Leverage Metal shader rendering or CoreGraphics bitmap caching for frequency bar decimation and peak hold decay.

---

## 📌 Release Milestones

| Version | Focus Area | Key Deliverables |
|---|---|---|
| **v1.1** | *Stanza Explorer (Current)* | Live folder media navigation, parent tree, sibling pane, signed release |
| **v1.2** | *Persistence & Recursive Browsing* | Last opened folder restore, persistent settings audit, Alt+Click recursive scan |
| **v1.3** | *Waveform Inspection* | Horizontal waveform zooming, smooth panning, minimap overview |
| **v1.4** | *Markers & Slicing* | Multi-marker lists, folder metadata `.stanza_markers.json`, slice export |
| **v1.5** | *DJ & Pro Audio Integrations* | `rekordbox.xml` cue export, native C++/Metal spectral visualizer pipeline |

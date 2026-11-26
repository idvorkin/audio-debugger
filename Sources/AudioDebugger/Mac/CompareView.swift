import AppKit
import AudioCore
import SwiftUI

/// Story 019: a capture set side by side. It reads only the set's files (AudioCore's `Comparison`), so a set from last
/// week opens like one just taken. It takes the main window's panels while open; Esc closes it.
extension AppModel {
    /// Loads `folder` off the main thread and shows it; a set that won't load says why.
    func openComparison(_ folder: URL) {
        let name = folder.lastPathComponent
        Task.detached(priority: .userInitiated) {
            let result = Result { try Comparison.load(folder) }
            await MainActor.run {
                switch result {
                case .success(let c):
                    self.closeReplay()
                    self.comparisonError = nil
                    self.comparison = c
                    self.comparisonName = name
                    self.comparisonFolder = folder
                    self.playingRow = nil
                    self.previousRow = nil
                    let ranked = c.rows.map { r in "\(r.stream.name) \(r.reading.map { "\($0.score)" } ?? "—")" }
                    SessionLog.shared.event(
                        "comparison_open", ["set": name, "rows": ranked, "mode": c.set.mode.rawValue])
                    Log.app.info(
                        "comparison \(name, privacy: .public): \(ranked.joined(separator: ", "), privacy: .public)")
                case .failure(let error):
                    Log.app.error(
                        "comparison \(name, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                    self.comparisonError = "Could not open capture set \(name): \(error)"
                }
            }
        }
    }

    /// ⌘O: choose a set under `captures/`.
    func chooseComparison() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose a capture set (a folder with manifest.json)"
        panel.directoryURL = SessionLog.root.appendingPathComponent("captures", isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openComparison(url)
    }

    func closeComparison() {
        guard comparison != nil else { return }
        closeReplay()
        comparison = nil
        playingRow = nil
        previousRow = nil
        SessionLog.shared.event("comparison_closed")
    }

    /// Digits: play ranked row `n` (0-based), raw, from the place on the set's timeline being heard now.
    func playRow(_ n: Int) {
        guard let c = comparison, c.rows.indices.contains(n), !c.rows[n].samples.isEmpty else { return }
        let row = c.rows[n]
        var start = 0.0
        if let current = playingRow, replayOpen, c.rows.indices.contains(current) {
            start = Comparison.position(seconds(position), from: c.rows[current], to: row)
            if current != n { previousRow = current }
        }
        playRaw(row.samples, rate: row.rate, at: start >= row.seconds ? 0 : start)
        playingRow = n
        SessionLog.shared.event("comparison_play", ["row": n + 1, "mic": row.stream.name, "at": start])
        Log.replay.info(
            "comparison: row \(n + 1) \(row.stream.name, privacy: .public) from \(start, format: .fixed(precision: 2), privacy: .public)s"
        )
    }

    /// ⇥: back to the row played before, at the same place, for A/B.
    func swapRows() {
        guard let other = previousRow else { return }
        playRow(other)
    }

    /// ⌘R: the set's folder in Finder.
    func revealComparison() {
        guard let folder = comparisonFolder else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
}

private let rowColors: [Color] = [
    Color(red: 0.36, green: 0.62, blue: 0.95), Color(red: 0.95, green: 0.55, blue: 0.25),
    Color(red: 0.45, green: 0.8, blue: 0.45), Color(red: 0.85, green: 0.45, blue: 0.85),
    Color(red: 0.9, green: 0.8, blue: 0.3), Color(red: 0.4, green: 0.85, blue: 0.85),
]

func rowColor(_ i: Int) -> Color { rowColors[i % rowColors.count] }

struct CompareView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let c = model.comparison {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Capture set \(model.comparisonName ?? "")").font(.headline)
                    Text(
                        "\(c.set.mode == .together ? "at once" : "in turn") · \(c.rows.count) mics · best first"
                    ).foregroundStyle(.secondary)
                    Spacer()
                    Text("1–9 listen (raw)   ⇥ A/B   ⌘O open   ⌘R reveal   Esc close").foregroundStyle(.secondary)
                        .font(.callout)
                }
                RowTable(comparison: c)
                Plot(title: "Waveforms, lined up in time") { AlignedWaveforms(comparison: c) }
                Plot(title: "Long-term spectrum (dBFS)") { SpectrumOverlay(comparison: c) }
            }
        }
    }
}

private struct RowTable: View {
    @Environment(AppModel.self) private var model
    let comparison: Comparison

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
            GridRow {
                ForEach(
                    ["", "Mic", "Score", "SNR", "Score floor", "Clipped", "Dropouts", "Peak", "Rate · top"], id: \.self
                ) { Text($0).font(.caption.bold()).foregroundStyle(.secondary) }
            }
            ForEach(Array(comparison.rows.enumerated()), id: \.offset) { i, row in
                GridRow {
                    Text("\(i + 1)").font(.system(.body, design: .monospaced).bold())
                        .foregroundStyle(model.playingRow == i ? Color.white : rowColor(i))
                        .padding(.horizontal, 4)
                        .background(model.playingRow == i ? rowColor(i) : .clear, in: RoundedRectangle(cornerRadius: 3))
                    Text("\(row.stream.name) (\(row.stream.kind.rawValue))")
                    if let r = row.reading {
                        Text("\(r.score)").font(.title3.bold()).foregroundStyle(scoreColor(r.score))
                        Text(r.snrDB.map { String(format: "%.0f dB", $0) } ?? "no speech")
                        Text(r.floorDB.map { String(format: "%.0f dB", $0) } ?? "—")
                        Text("\(r.clips) of \(r.pieces)").foregroundStyle(r.clips > 0 ? red : .primary)
                        Text("\(r.dropouts) of \(r.pieces)").foregroundStyle(r.dropouts > 0 ? red : .primary)
                        Text(String(format: "%.0f dB", r.peakDB))
                        Text(String(format: "%.0f kHz · %.0f kHz", row.rate / 1000, row.rate / 2000))
                            .foregroundStyle((row.nyquist ?? 0) < 8000 ? amber : .primary)
                    } else {
                        Text(row.problem ?? "no audio").foregroundStyle(red).textSelection(.enabled)
                            .gridCellColumns(7)
                    }
                }
            }
        }
        .font(.callout)
    }

    private func scoreColor(_ s: Int) -> Color { s >= 75 ? green : s >= 50 ? amber : red }
}

/// Each row's envelope on one time axis, placed by its offset; the playing row shows a playhead. Every lane has the same
/// gain (the loudest row's peak fills its lane), so a quiet mic still looks quieter.
private struct AlignedWaveforms: View {
    @Environment(AppModel.self) private var model
    let comparison: Comparison

    var body: some View {
        let span = max(comparison.span, 0.001)
        let rows = comparison.rows.enumerated().filter { !$0.element.samples.isEmpty }
        let loudest = rows.map { peak($0.element.samples[...]) }.max() ?? 1
        let gain = 1 / max(loudest, 1e-4)
        let envelopes = rows.map { row in
            envelope(row.element.samples, buckets: 600).map { (min: $0.min * gain, max: $0.max * gain) }
        }
        let playing = model.playingRow
        let at = model.seconds(model.position)
        Canvas { ctx, size in
            let laneHeight = size.height / CGFloat(max(1, rows.count))
            for (lane, (i, row)) in rows.enumerated() {
                let env = envelopes[lane]
                let x0 = CGFloat(row.offset / span) * size.width
                let w = CGFloat(row.seconds / span) * size.width
                let mid = laneHeight * (CGFloat(lane) + 0.5)
                var path = Path()
                for (k, b) in env.enumerated() {
                    let x = x0 + w * CGFloat(k) / CGFloat(env.count)
                    path.move(to: CGPoint(x: x, y: mid - CGFloat(b.max) * laneHeight / 2))
                    path.addLine(to: CGPoint(x: x, y: mid - CGFloat(b.min) * laneHeight / 2))
                }
                ctx.stroke(path, with: .color(rowColor(i)), lineWidth: 1)
                ctx.draw(
                    Text("\(i + 1) \(row.stream.name)").font(.caption).foregroundColor(rowColor(i)),
                    at: CGPoint(x: 4, y: mid - laneHeight / 2 + 8), anchor: .leading)
                if playing == i {
                    let x = CGFloat((row.offset + at) / span) * size.width
                    var head = Path()
                    head.move(to: CGPoint(x: x, y: mid - laneHeight / 2))
                    head.addLine(to: CGPoint(x: x, y: mid + laneHeight / 2))
                    ctx.stroke(head, with: .color(.white), lineWidth: 1.5)
                }
            }
        }
    }
}

/// Every row's long-term spectrum on one log-frequency axis, 40 Hz to 24 kHz, -120 to 0 dBFS.
private struct SpectrumOverlay: View {
    let comparison: Comparison

    var body: some View {
        Canvas { ctx, size in
            let lo = log10(40.0), hi = log10(24_000.0)
            func x(_ hz: Float) -> CGFloat { CGFloat((log10(Double(hz)) - lo) / (hi - lo)) * size.width }
            func y(_ db: Float) -> CGFloat { CGFloat(min(120, max(0, -db)) / 120) * size.height }
            for hz: Float in [100, 1000, 8000] {
                var grid = Path()
                grid.move(to: CGPoint(x: x(hz), y: 0))
                grid.addLine(to: CGPoint(x: x(hz), y: size.height))
                ctx.stroke(grid, with: .color(.gray.opacity(0.3)), lineWidth: 1)
                ctx.draw(
                    Text(hz >= 1000 ? "\(Int(hz / 1000))k" : "\(Int(hz))").font(.caption2).foregroundColor(.gray),
                    at: CGPoint(x: x(hz) + 2, y: size.height - 6), anchor: .leading)
            }
            for (i, row) in comparison.rows.enumerated() where !row.spectrum.isEmpty {
                var path = Path()
                for (k, p) in row.spectrum.enumerated() {
                    let pt = CGPoint(x: x(p.hz), y: y(p.db))
                    if k == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                ctx.stroke(path, with: .color(rowColor(i)), lineWidth: 1.5)
            }
        }
    }
}

import AudioCore
import BugKit
import SwiftUI

private let panel = Color(red: 0.05, green: 0.07, blue: 0.09)
private let grid = Color.white.opacity(0.08)
private let green = Color(red: 0.25, green: 0.73, blue: 0.31)
private let blue = Color(red: 0.35, green: 0.65, blue: 1)
private let amber = Color(red: 0.82, green: 0.6, blue: 0.13)
private let red = Color(red: 0.97, green: 0.32, blue: 0.29)
private let purple = Color(red: 0.64, green: 0.44, blue: 0.97)

/// Views read the @Observable model from the environment and bind through `Binding(get:set:)`: no `@State`, whose
/// macro plugin ships only with Xcode (this builds with the Command Line Tools).
struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MicBar()
            HStack {
                ForEach([20, 10, 5], id: \.self) { s in
                    Button("▶ Last \(s)s  \(Self.replayKey[s] ?? "")") { model.replay(seconds: s) }
                }
                Button("Reset peaks  C") { model.resetReadings() }
                Button("Report a bug  ⌘I") { model.showBugReport = true }
                if let saved = model.bugSaved {
                    Text("Saved report \(saved)").foregroundStyle(green).font(.callout)
                }
                Spacer()
                WhatsNewRow(feed: AppModel.whatsNew, logger: SessionLog.shared.bugLogger) { model.showWhatsNew = true }
                    .frame(maxWidth: 420)
            }
            StatusLine()
            if let error = model.micError {
                Text(error).foregroundStyle(red).font(.callout)
            }
            HStack(spacing: 8) {
                VStack(spacing: 8) {
                    Plot(title: "Waveform (auto-zoomed)") { WaveformShape(samples: model.waveform) }
                    Plot(title: "Spectrum") { SpectrumView() }
                    Plot(title: "Spectrogram (0–8 kHz)") { SpectrogramView() }
                }
                Plot(title: "Level dBFS") { MeterView() }.frame(width: 110)
            }
            if model.replayOpen { ReplayPanel().frame(height: 210) }
        }
        .padding(12)
        .background(Color(red: 0.08, green: 0.09, blue: 0.11))
        .foregroundStyle(Color(white: 0.85))
        .sheet(isPresented: Binding(get: { model.showBugReport }, set: { model.showBugReport = $0 })) {
            BugReportSheet().environment(model)
        }
        .sheet(isPresented: Binding(get: { model.showWhatsNew }, set: { model.showWhatsNew = $0 })) {
            VStack(spacing: 0) {
                WhatsNewView(feed: AppModel.whatsNew, logger: SessionLog.shared.bugLogger, from: "sheet")
                HStack {
                    Spacer()
                    Button("Done") { model.showWhatsNew = false }.keyboardShortcut(.cancelAction)
                }
                .padding(12)
            }
            .frame(width: 520, height: 560)
        }
    }

    static let replayKey = [20: "R", 10: "T", 5: "F"]
}

/// Story 006: ⌘I, a sentence, Return. Keys typed here reach the text field, never the transport (`Keys`).
private struct BugReportSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Report a bug").font(.title3.bold())
            Text(
                "Saved with the last 20 seconds the mic heard, the session log, the mic's readings and the replay's state. Nothing leaves this Mac."
            )
            .font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            TextField("What went wrong?", text: Binding(get: { model.bugNote }, set: { model.bugNote = $0 }))
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.saveBug() }
            HStack {
                Spacer()
                Button("Cancel") {
                    model.bugNote = ""
                    model.showBugReport = false
                }
                .keyboardShortcut(.cancelAction)
                Button("Save and Another") { model.saveBug(another: true) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.bugNote.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Save Report") { model.saveBug() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.bugNote.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

private struct MicBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            Text("Mic").font(.headline)
            ForEach(Array(model.mics.enumerated()), id: \.element.id) { i, m in
                let selected = m.uid == model.mic?.uid
                Button {
                    model.select(m)
                } label: {
                    Text(i < 9 ? "\(i + 1)  \(m.name)" : m.name).lineLimit(1)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(
                            selected ? blue.opacity(0.85) : Color.white.opacity(0.08), in: .rect(cornerRadius: 6)
                        )
                        .foregroundStyle(selected ? .white : Color(white: 0.85))
                }
                .buttonStyle(.plain)
                .help(
                    m.isBluetooth
                        ? "\(m.name): Bluetooth — opening it switches the headset to low-quality call mode" : m.name)
            }
            Spacer()
        }
    }
}

private struct StatusLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let floor = model.noiseFloorDB.map { String(format: "%.1f", $0) } ?? "—"
        HStack(spacing: 14) {
            Text(String(format: "RMS %6.1f dB   peak %6.1f dB", model.rmsDB, model.peakDB))
            Text("floor \(floor) dB")
            Text(String(format: "dominant %6.0f Hz", model.dominantHz))
            Text("pitch \(noteName(model.pitchHz))")
            Text("clips \(model.clips)").foregroundStyle(model.clips > 0 ? red : Color(white: 0.85))
            Text(model.hint.rawValue).foregroundStyle(model.hint == .good ? green : amber)
        }
        .font(.system(size: 13, design: .monospaced))
    }
}

private struct Plot<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 2) {
            Text(title).font(.caption)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(6)
        .background(panel, in: .rect(cornerRadius: 8))
    }
}

/// The scope, scaled to its own peak so a quiet mic still fills it.
private struct WaveformShape: View {
    let samples: [Float]

    var body: some View {
        Canvas { ctx, size in
            ctx.stroke(
                Path { p in
                    p.move(to: CGPoint(x: 0, y: size.height / 2));
                    p.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                }, with: .color(grid))
            guard samples.count > 1 else { return }
            let span = max(0.02, CGFloat(peak(samples[...])) * 1.2)
            var path = Path()
            for (i, s) in samples.enumerated() {
                let pt = CGPoint(
                    x: CGFloat(i) / CGFloat(samples.count - 1) * size.width,
                    y: size.height / 2 * (1 - CGFloat(s) / span))
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            ctx.stroke(path, with: .color(green), lineWidth: 1.2)
            ctx.draw(
                Text(String(format: "±%.3f", span)).font(.caption2).foregroundStyle(.secondary),
                at: CGPoint(x: 30, y: 8))
        }
    }
}

/// Log-frequency spectrum, -110…0 dBFS, with a decaying peak line.
private struct SpectrumView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Canvas { ctx, size in
            let freqs = model.frequencies
            guard let top = freqs.last, freqs.count == model.spectrum.count else { return }
            let lo = log10(Float(20)), hi = log10(top)
            func x(_ f: Float) -> CGFloat { CGFloat((log10(max(f, 20)) - lo) / (hi - lo)) * size.width }
            func y(_ db: Float) -> CGFloat { CGFloat(min(0, max(-110, db)) / -110) * size.height }
            for f: Float in [50, 100, 200, 500, 1000, 2000, 5000, 10_000] where f < top {
                ctx.stroke(
                    Path {
                        $0.move(to: CGPoint(x: x(f), y: 0)); $0.addLine(to: CGPoint(x: x(f), y: size.height))
                    }, with: .color(grid))
                ctx.draw(
                    Text(f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))").font(.caption2).foregroundStyle(.secondary),
                    at: CGPoint(x: x(f), y: size.height - 6))
            }
            for db: Float in [-20, -40, -60, -80, -100] {
                ctx.stroke(
                    Path {
                        $0.move(to: CGPoint(x: 0, y: y(db))); $0.addLine(to: CGPoint(x: size.width, y: y(db)))
                    }, with: .color(grid))
                ctx.draw(Text("\(Int(db))").font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: 14, y: y(db)))
            }
            var fill = Path()
            fill.move(to: CGPoint(x: x(freqs[0]), y: size.height))
            for (f, db) in zip(freqs, model.spectrum) { fill.addLine(to: CGPoint(x: x(f), y: y(db))) }
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            ctx.fill(fill, with: .color(blue.opacity(0.25)))
            var line = Path()
            for (i, (f, db)) in zip(freqs, model.spectrum).enumerated() {
                if i == 0 {
                    line.move(to: CGPoint(x: x(f), y: y(db)))
                } else {
                    line.addLine(to: CGPoint(x: x(f), y: y(db)))
                }
            }
            ctx.stroke(line, with: .color(blue), lineWidth: 1)
            if model.spectrumPeak.count == freqs.count {
                var p = Path()
                for (i, (f, db)) in zip(freqs, model.spectrumPeak).enumerated() {
                    if i == 0 {
                        p.move(to: CGPoint(x: x(f), y: y(db)))
                    } else {
                        p.addLine(to: CGPoint(x: x(f), y: y(db)))
                    }
                }
                ctx.stroke(p, with: .color(amber.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
        }
    }
}

private struct SpectrogramView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if let image = model.spectrogram {
                    Image(decorative: image, scale: 1).resizable().interpolation(.medium)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                ForEach([2000, 4000, 6000], id: \.self) { f in
                    Text("\(f / 1000)k").font(.caption2).foregroundStyle(.white.opacity(0.7))
                        .position(x: 12, y: geo.size.height * (1 - CGFloat(f) / 8000))
                }
            }
        }
    }
}

/// RMS (green) and peak (blue) bars, -60…0 dBFS, the held peak in red, guides at -18 and -6.
private struct MeterView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Canvas { ctx, size in
            func y(_ db: Float) -> CGFloat { CGFloat(min(0, max(-60, db)) / -60) * size.height }
            let w = size.width / 2 - 14
            ctx.fill(
                Path(CGRect(x: 4, y: y(model.rmsDB), width: w, height: size.height - y(model.rmsDB))),
                with: .color(green))
            ctx.fill(
                Path(CGRect(x: w + 10, y: y(model.peakDB), width: w, height: size.height - y(model.peakDB))),
                with: .color(blue))
            ctx.fill(Path(CGRect(x: 0, y: y(model.heldPeakDB) - 1, width: 2 * w + 10, height: 2)), with: .color(red))
            for (db, c) in [(Float(-18), Color.gray), (-6, amber)] {
                ctx.stroke(
                    Path {
                        $0.move(to: CGPoint(x: 0, y: y(db))); $0.addLine(to: CGPoint(x: 2 * w + 10, y: y(db)))
                    }, with: .color(c), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            for db: Float in [0, -10, -20, -30, -40, -50, -60] {
                ctx.draw(
                    Text("\(Int(db))").font(.caption2).foregroundStyle(.secondary),
                    at: CGPoint(x: size.width - 10, y: min(size.height - 6, max(6, y(db)))))
            }
        }
    }
}

/// The replay: the clip's envelope with a playhead (click or drag to seek), the transport and the processing toggles.
private struct ReplayPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Replay").font(.headline)
                Text(model.processing.label.isEmpty ? "raw (normalized)" : model.processing.label).foregroundStyle(
                    .secondary)
                if model.processingBusy {
                    ProgressView().controlSize(.small); Text("processing…").foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: "%5.1fs / %.1fs", model.seconds(model.position), model.seconds(model.replayLength)))
                    .font(.system(.body, design: .monospaced))
            }
            GeometryReader { geo in
                Canvas { ctx, size in
                    let cols = model.envelope
                    guard !cols.isEmpty else { return }
                    let mid = size.height / 2
                    var path = Path()
                    for (i, c) in cols.enumerated() {
                        let x = CGFloat(i) / CGFloat(cols.count) * size.width
                        path.move(to: CGPoint(x: x, y: mid - CGFloat(c.high) * mid))
                        path.addLine(to: CGPoint(x: x, y: mid - CGFloat(c.low) * mid + 0.5))
                    }
                    ctx.stroke(path, with: .color(purple), lineWidth: max(1, size.width / CGFloat(cols.count)))
                    let px =
                        model.replayLength > 0 ? CGFloat(model.position) / CGFloat(model.replayLength) * size.width : 0
                    ctx.fill(Path(CGRect(x: px - 1, y: 0, width: 2, height: size.height)), with: .color(.white))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { g in
                        let f = max(0, min(1, g.location.x / max(1, geo.size.width)))
                        model.seek(to: Int(f * CGFloat(model.replayLength)))
                    })
            }
            .background(panel, in: .rect(cornerRadius: 6))
            HStack(spacing: 10) {
                Button(model.playing ? "⏸ Pause  ␣" : "▶ Play  ␣") { model.togglePlay() }.frame(width: 110)
                Button("↺ Replay  A") { model.restart() }
                Slider(
                    value: Binding(get: { Double(model.position) }, set: { model.seek(to: Int($0)) }),
                    in: 0...Double(max(1, model.replayLength)))
                Toggle(
                    "Noise reduction  N",
                    isOn: Binding(
                        get: { model.processing.noiseReduction }, set: { model.processing.noiseReduction = $0 }))
                Toggle(
                    "Voice boost  B",
                    isOn: Binding(get: { model.processing.voiceBoost }, set: { model.processing.voiceBoost = $0 }))
                Button("✕ Close  Esc") { model.closeReplay() }
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 8))
    }
}

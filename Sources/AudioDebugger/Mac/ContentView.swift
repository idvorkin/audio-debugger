import BugKit
import SwiftUI

/// The Mac's window: the panels (Panels.swift) side by side, every button naming its key.
///
/// Views read the @Observable model from the environment and bind through `Binding(get:set:)`: no `@State`, whose
/// macro plugin ships only with Xcode (this builds with the Command Line Tools).
struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MicBar()
            InputLine()
            HStack {
                ForEach([5, 10, 20], id: \.self) { s in
                    Button("▶ Last \(s)s  \(Self.replayKey[s] ?? "")") { model.replay(seconds: s) }
                }
                Button("Reset peaks  C") { model.resetReadings() }
                Button("Report a bug  ⌘I") { model.showBugReport = true }
                Button("Keys  ?") { model.showKeys = true }
                Button("Capture every mic  M") { model.captureSet(.together) }
                    .help("Record every mic (not Bluetooth or iPhone) for 10 s into one capture set; ⇧M: each in turn")
                    .disabled(model.captureRun != nil)
                if let saved = model.bugSaved {
                    Text("Saved report \(saved)").foregroundStyle(green).font(.callout)
                }
                Spacer()
                WhatsNewRow(feed: AppModel.whatsNew, logger: SessionLog.shared.bugLogger) { model.showWhatsNew = true }
                    .frame(maxWidth: 420)
            }
            StatusLine()
            if let run = model.captureRun {
                // Stories 017/018: what the capture set is doing; in turn, the phrase to say, large.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Capture set: \(run.status)   Esc stops").foregroundStyle(amber).font(.callout.bold())
                    if let phrase = run.phrase {
                        Text("Say: “\(phrase)”").font(.title2.bold()).textSelection(.enabled)
                    }
                }
            } else if let saved = model.captureSaved {
                Text("Saved capture set captures/\(saved)").foregroundStyle(green).font(.callout)
                    .textSelection(.enabled)
            }
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
        .background(appBackground)
        .foregroundStyle(Color(white: 0.85))
        .sheet(isPresented: Binding(get: { model.showBugReport }, set: { model.showBugReport = $0 })) {
            BugReportSheet().environment(model)
        }
        .sheet(isPresented: Binding(get: { model.showKeys }, set: { model.showKeys = $0 })) {
            KeySheet().environment(model)
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

    static let replayKey = [5: "R", 10: "T", 20: "Y"]
}

/// Story 006: ⌘I, a sentence, Return. Keys typed here reach the text field, never the transport (`Keys`).
/// BugKit's own dialog is iOS only, so the Mac has this one.
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

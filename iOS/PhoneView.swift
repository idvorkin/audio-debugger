import BugKit
import SwiftUI

/// The iPhone's and iPad's screen: the Mac's panels (Panels.swift), stacked for a phone held upright and laid out as
/// the Mac's window on an iPad. Every action is a tap; on an iPad with a keyboard, the Mac's bare keys work too.
struct PhoneView: View {
    @Environment(AppModel.self) private var model
    @EnvironmentObject private var reporter: BugReporter
    @Environment(\.horizontalSizeClass) private var sizeClass
    @FocusState private var focused: Bool

    private var compact: Bool { sizeClass == .compact }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                MicBar()
                Menu {
                    Button("Report a problem", systemImage: "ladybug") { reporter.open(from: .button) }
                    Button("What's new", systemImage: "sparkles") { model.showWhatsNew = true }
                    Button("Keys", systemImage: "keyboard") { model.showKeys = true }
                    Button("About", systemImage: "info.circle") { model.showAbout = true }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title2)
                }
            }
            InputLine()
            HStack {
                ForEach([5, 10, 20], id: \.self) { s in
                    Button("▶ \(s)s") { model.replay(seconds: s) }.buttonStyle(.borderedProminent)
                }
                Button("Reset peaks") { model.resetReadings() }.buttonStyle(.bordered)
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
                Plot(title: "dBFS") { MeterView() }.frame(width: compact ? 70 : 110)
            }
            if model.replayOpen { ReplayPanel().frame(height: compact ? 240 : 210) }
        }
        .padding(compact ? 8 : 12)
        .background(appBackground.ignoresSafeArea())
        .foregroundStyle(Color(white: 0.85))
        .preferredColorScheme(.dark)
        .sheet(isPresented: Binding(get: { model.showWhatsNew }, set: { model.showWhatsNew = $0 })) {
            NavigationStack {
                WhatsNewView(feed: AppModel.whatsNew, logger: SessionLog.shared.bugLogger, from: "menu")
                    .toolbar { Button("Done") { model.showWhatsNew = false } }
            }
        }
        .sheet(isPresented: Binding(get: { model.showKeys }, set: { model.showKeys = $0 })) {
            ScrollView { KeySheet().environment(model) }
        }
        .sheet(isPresented: Binding(get: { model.showAbout }, set: { model.showAbout = $0 })) {
            NavigationStack {
                Form { BugKitAboutLink() }
                    .toolbar { Button("Done") { model.showAbout = false } }
            }
        }
        // An iPad's hardware keyboard: the Mac's bare keys (Keys.swift). Sheets take focus, so a bug note's typing
        // never reaches the transport. The keys the app's keyboard commands own (`KeyCommands`, listed when ⌘ is
        // held) are theirs: handling them here too would fire each twice, and N or B would toggle back.
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in
            guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
            let key: BareKey
            switch press.key {
            case .space: key = .space
            case .escape: key = .escape
            case .leftArrow: key = .left
            case .rightArrow: key = .right
            default: key = .character(press.characters)
            }
            if case .character(let c) = key, KeyCommands.owned.contains(c.lowercased()) { return .ignored }
            if key == .space || key == .left || key == .right { return .ignored }
            return model.press(key, shift: press.modifiers.contains(.shift)) ? .handled : .ignored
        }
        .onAppear { focused = true }
    }
}

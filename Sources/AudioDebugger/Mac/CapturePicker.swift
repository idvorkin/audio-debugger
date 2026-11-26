import AudioCore
import SwiftUI

/// Story 021: M's picker, in the main window in place of the panels. A switch per mic (Bluetooth and iPhone
/// mics start off, with what opening them would do), at once or in turn, and the length. Keyboard first: 1–9, T,
/// ← / →, Return, Esc.
struct CapturePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let plan = model.capturePlan {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Capture a set").font(.title3.bold())
                    Spacer()
                    Text("1–9 switch a mic   T at once / in turn   ← → seconds   Return start   Esc cancel")
                        .foregroundStyle(.secondary).font(.callout)
                }
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    ForEach(Array(plan.mics.enumerated()), id: \.element.uid) { i, mic in
                        GridRow {
                            Text(i < 9 ? "\(i + 1)" : " ").font(.system(.body, design: .monospaced).bold())
                            Toggle(
                                isOn: Binding(
                                    get: { model.capturePlan?.isOn(mic) ?? false },
                                    set: { _ in model.capturePlan?.toggle(i) })
                            ) {
                                Text("\(mic.name)  (\(mic.kind.rawValue))")
                            }
                            .toggleStyle(.switch)
                            Text(CapturePlan.risk(mic) ?? "").foregroundStyle(amber).font(.callout)
                        }
                    }
                }
                HStack(spacing: 16) {
                    Picker(
                        "T",
                        selection: Binding(
                            get: { model.capturePlan?.mode ?? .together },
                            set: { if $0 != model.capturePlan?.mode { model.capturePlan?.toggleMode() } })
                    ) {
                        Text("At once").tag(CaptureSet.Mode.together)
                        Text("In turn, with a phrase").tag(CaptureSet.Mode.inTurn)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    Text("\(Int(plan.seconds)) s\(plan.mode == .inTurn ? " each" : "")").monospacedDigit()
                        .frame(width: 60, alignment: .trailing)
                    Slider(
                        value: Binding(
                            get: { model.capturePlan?.seconds ?? 10 },
                            set: { model.capturePlan?.setSeconds($0) }),
                        in: CapturePlan.secondsRange, step: 1
                    )
                    .frame(maxWidth: 260)
                }
                HStack {
                    Button("Start  ↩") { model.startCapturePlan() }
                        .disabled(plan.selected.isEmpty)
                    Button("Cancel  Esc") { model.capturePlan = nil }
                    Text(
                        plan.selected.isEmpty
                            ? "Switch on at least one mic"
                            : "\(plan.selected.count) mic\(plan.selected.count == 1 ? "" : "s")"
                    )
                    .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

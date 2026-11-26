import AudioCore
import SwiftUI

/// Story 020: under the input line, where replay plays, chosen apart from the mic. O steps through the outputs; the
/// menu picks one directly. Amber while the chosen output is not plugged in (replay uses the system default meanwhile).
struct OutputLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let choice = model.output
        HStack(spacing: 8) {
            Text("Output  \(choice.active?.name ?? "system default")")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(choice.missing ? amber : Color(white: 0.7))
            if choice.missing {
                Text("(chosen output not plugged in)").foregroundStyle(amber).font(.callout)
            }
            Menu("Next  O") {
                Button("System default") { model.selectOutput(nil) }
                ForEach(choice.outputs) { o in
                    Button(o.name) { model.selectOutput(o.uid) }
                }
            } primaryAction: {
                model.nextOutput()
            }
            .fixedSize()
            .help("Replay's speakers or headphones, apart from the mic; O steps to the next")
        }
    }
}

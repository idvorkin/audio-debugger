import AVFoundation
import AVKit
import SwiftUI

/// Story 020 on iPhone and iPad (ad-8ev): where replay plays, and the system's route picker to change it (AirPods,
/// AirPlay, a wired headset, the speaker). iOS has no per-app output device: the audio session's route is the output,
/// so the picker is the system's own. With nothing plugged in the session plays on the speaker (`.defaultToSpeaker`),
/// not the earpiece. A Bluetooth headset whose mic is open (hands-free) carries the output too: they can't be split,
/// and the row says so.
struct OutputRow: View {
    @State private var route = OutputRoute.current()

    var body: some View {
        HStack(spacing: 8) {
            Text("Output  \(route.name)")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(route.tiedToHeadset ? amber : Color(white: 0.7))
                .lineLimit(1)
            RoutePicker().frame(width: 30, height: 30)
            if route.tiedToHeadset {
                Text("tied to the headset's mic").foregroundStyle(amber).font(.caption)
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification).receive(on: RunLoop.main)
        ) { _ in route = .current() }
    }
}

/// The session's current output, and whether a Bluetooth hands-free mic ties it to the same headset.
struct OutputRoute: Equatable {
    let name: String
    let tiedToHeadset: Bool

    static func current() -> OutputRoute {
        let r = AVAudioSession.sharedInstance().currentRoute
        let name = r.outputs.map(\.portName).joined(separator: ", ")
        return OutputRoute(
            name: name.isEmpty ? "none" : name, tiedToHeadset: r.inputs.contains { $0.portType == .bluetoothHFP })
    }
}

/// The system's output picker (the AirPlay button), as Control Center shows it.
private struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .lightGray
        view.activeTintColor = .systemBlue
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}

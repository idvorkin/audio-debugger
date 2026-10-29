import BugKit
import SwiftUI
import UIKit

/// The iPhone and iPad app: the Mac's model, capture, replay and panels (Sources/AudioDebugger outside Mac/) around
/// iOS's mics, its layout and this scene.
@main
struct AudioDebuggerApp: App {
    private let model: AppModel
    @StateObject private var reporter: BugReporter
    private let delivery: CloudKitReportDelivery?  // kept for the app's life, as BugKit asks
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Mics.configureSession()
        let model = AppModel()
        self.model = model
        let delivery = AppModel.makeBugDelivery()
        self.delivery = delivery
        _reporter = StateObject(wrappedValue: model.makeBugReporter(delivery: delivery))
    }

    var body: some Scene {
        WindowGroup {
            PhoneView()
                .environment(model)
                .environmentObject(reporter)
                .bugReporting(reporter)  // a shake or ⌘I
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = true  // the scope stays on screen
                    model.start()
                    if let seconds = Launch.selfTestSeconds { SelfTest.run(model, after: seconds) }
                    reporter.runLaunchHooks()
                    startBugDelivery()
                }
        }
        // Capture carries on in the background (UIBackgroundModes audio), so the last 20 s are there on return;
        // only the drawing stops.
        .onChange(of: scenePhase) { _, phase in
            let name =
                switch phase {
                case .active: "active"
                case .inactive: "inactive"
                case .background: "background"
                @unknown default: "unknown"
                }
            SessionLog.shared.event("scene", ["phase": name, "captured": model.capture.snapshot().captured])
            Log.app.info("scene \(name, privacy: .public)")
            model.onScreen = phase != .background
            if phase == .active { startBugDelivery() }
        }
    }

    /// Sends what is waiting, at launch and each time the app comes back (BugKit: iOS suspends its retry timers).
    private func startBugDelivery() {
        guard let delivery else { return }
        Task { await delivery.start() }
    }
}

/// The end of a scripted run (`SelfTest`): a simulator test, never a person's session.
@MainActor
func quitApp() { exit(0) }

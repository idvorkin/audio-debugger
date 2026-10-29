import BugKit
import Foundation

extension AppModel {
    /// iOS's bug reports through BugKit's reporter (story 03): a shake, ⌘I or the ⓘ menu opens its dialog (a picture
    /// of the screen and the note); it saves the Mac's report, the last 20 s the mic heard as a WAV included, into
    /// Documents, where the bug listener reads it from a paired device. `delivery` also sends it to Igor's private
    /// iCloud, which the Mac's listener reads without the phone nearby; nil keeps reports on the device.
    func makeBugReporter(delivery: CloudKitReportDelivery?) -> BugReporter {
        var options = BugReporterOptions()
        // Not dictation: it would take over the audio session this app is measuring with.
        options.dictation = false
        options.privacyNote =
            delivery == nil
            ? "Nothing leaves this device." : "Sent to your own iCloud for the Mac, with the last 20 s of audio."
        options.copySessionLog = true
        options.writeReportJSON = true
        options.launchHookPrefix = "AUDIO"  // SIMCTL_CHILD_AUDIO_BUG="a|b" in `just ios-selftest`
        let capture = capture
        return BugReporter(
            hooks: BugReporterHooks(
                screen: { [unowned self] in replayOpen ? "replay" : "live" },
                context: { [unowned self] in bugContext() },
                sessionLog: { SessionLog.shared.position },
                logger: SessionLog.shared.bugLogger,
                // At save, a moment after the dialog opened: the ring keeps the last 20 s either way.
                extraFiles: { folder in
                    let name = "mic-last-\(replaySeconds)s.wav"
                    try writeWAV(
                        capture.last(seconds: replaySeconds), sampleRate: capture.sampleRate,
                        to: folder.appendingPathComponent(name))
                    return [name]
                },
                flushLog: { SessionLog.shared.flush() }),
            options: options, store: Self.bugStore, info: Self.bugAppInfo, delivery: delivery)
    }

    /// The one store the reporter writes and the delivery sends from (BugKit: the same store for both).
    static let bugStore = BugStore(documents: SessionLog.root)

    /// BugKit's private CloudKit delivery, into the container every app and the Mac's reader share (the entitlement
    /// is in project.yml). On a device only: a simulator has no iCloud account.
    static func makeBugDelivery() -> CloudKitReportDelivery? {
        #if targetEnvironment(simulator)
        return nil
        #else
        return CloudKitReportDelivery(
            containerIdentifier: "iCloud.com.idvorkin.BugKitReports", store: bugStore,
            logger: SessionLog.shared.bugLogger)
        #endif
    }
}

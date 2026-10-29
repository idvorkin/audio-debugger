// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AudioDebugger",
    platforms: [.macOS(.v14), .iOS(.v17)],
    // For the iOS app (iOS/project.yml), which compiles Sources/AudioDebugger outside Mac/ itself.
    products: [.library(name: "AudioCore", targets: ["AudioCore"])],
    dependencies: [
        // The shared bug-report library (format, store, crash capture, log pruning, What's new, About), as
        // magic-monitor-native uses it. A release tag, exactly: every app and the Mac's listener share one format.
        .package(url: "https://github.com/idvorkin/bug-kit", exact: "0.3.11")
    ],
    targets: [
        // Platform-free maths: levels, FFT spectrum, pitch, the replay ring, noise reduction, voice boost, the
        // playback transport. Host tests.
        .target(name: "AudioCore"),
        .testTarget(name: "AudioCoreTests", dependencies: ["AudioCore"]),
        // The app: Core Audio mics, AVAudioEngine capture and playback, views. `just app` wraps it into a bundle.
        // Swift 5 mode: AVFoundation's render and tap callbacks are not Sendable-annotated.
        .executableTarget(
            name: "AudioDebugger", dependencies: ["AudioCore", .product(name: "BugKit", package: "bug-kit")],
            swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)

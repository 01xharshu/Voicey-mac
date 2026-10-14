// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Voicey", platforms: [.macOS(.v14)], products: [.executable(name: "Voicey", targets: ["Voicey"])], targets: [
.target(name: "NativeBridge", publicHeadersPath: "include"),
.target(name: "VoiceyCore", swiftSettings: [.swiftLanguageMode(.v5)]),
.executableTarget(name: "Voicey", dependencies: ["VoiceyCore", "NativeBridge"], swiftSettings: [.swiftLanguageMode(.v5)]),
.executableTarget(name: "VoiceyProcessRunner", swiftSettings: [.swiftLanguageMode(.v5)]),
.executableTarget(name: "VoiceyBrowserHost", dependencies: ["VoiceyCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
.executableTarget(name: "VoiceyChecks", dependencies: ["VoiceyCore"], path: "Tests/VoiceyCoreTests", swiftSettings: [.swiftLanguageMode(.v5)])
])

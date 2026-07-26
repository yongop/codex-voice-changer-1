// swift-tools-version: 6.1

import PackageDescription

let package = Package(
  name: "CodexVoiceChanger1",
  platforms: [
    .macOS("14.2")
  ],
  products: [
    .executable(name: "CodexVoiceChanger1", targets: ["CodexVoiceChanger1"])
  ],
  targets: [
    .target(
      name: "AudioBridge",
      publicHeadersPath: "include"
    ),
    .executableTarget(
      name: "CodexVoiceChanger1",
      dependencies: ["AudioBridge"],
      swiftSettings: [
        .swiftLanguageMode(.v5)
      ],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("AVFAudio"),
        .linkedFramework("CoreAudio"),
      ]
    ),
    .testTarget(
      name: "AudioBridgeTests",
      dependencies: ["AudioBridge", "CodexVoiceChanger1"]
    ),
  ],
  cxxLanguageStandard: .cxx17
)

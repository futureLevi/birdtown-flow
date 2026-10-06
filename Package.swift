// swift-tools-version: 6.2
import PackageDescription

// Birdtown Flow: push-to-talk dictation for macOS.
//
// Three layers:
//   MurmurDictionary  correction rules (platform-neutral, shared contract with windows/)
//   MurmurKit         everything that is pure logic: text pipeline, styles, snippets,
//                     history persistence, stats, AI-polish prompts and HTTP clients.
//                     Foundation-only, so it builds and tests on Linux as well as macOS.
//   BirdtownFlow      the macOS app (Birdtown Flow): audio, hotkeys, engines, injection, UI.
//
// "Murmur" is the codebase's original codename; the library targets keep it.
//
// The app target only exists on macOS. On Linux the manifest drops it (and the FluidAudio
// dependency it needs) so `swift test` exercises the logic layers anywhere.

#if os(macOS)
let platformDependencies: [Package.Dependency] = [
    // Parakeet (TDT v3 / Ultra) as CoreML on the Neural Engine, plus CTC vocabulary boosting.
    // `traits: []` opts out of FluidAudio's prebuilt NeMo text-normalization engine, which
    // only TTS and ITN use — it would otherwise need embedding as a binary framework.
    .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.17.5", traits: []),
]
#else
let platformDependencies: [Package.Dependency] = []
#endif

var targets: [Target] = [
    .target(
        name: "MurmurDictionary",
        path: "Sources/MurmurDictionary",
        swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .target(
        name: "MurmurKit",
        dependencies: ["MurmurDictionary"],
        path: "Sources/MurmurKit",
        swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
        name: "MurmurDictionaryTests",
        dependencies: ["MurmurDictionary"],
        path: "Tests/MurmurDictionaryTests",
        resources: [.copy("dictionary-test-vectors.json")],
        swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
        name: "MurmurKitTests",
        dependencies: ["MurmurKit", "MurmurDictionary"],
        path: "Tests/MurmurKitTests",
        swiftSettings: [.swiftLanguageMode(.v6)]
    ),
]

#if os(macOS)
targets.append(
    .executableTarget(
        name: "BirdtownFlow",
        dependencies: [
            "MurmurDictionary",
            "MurmurKit",
            .product(name: "FluidAudio", package: "FluidAudio"),
        ],
        path: "Sources/BirdtownFlow",
        swiftSettings: [.swiftLanguageMode(.v6)]
    )
)
#endif

let package = Package(
    name: "BirdtownFlow",
    platforms: [.macOS(.v26)],
    dependencies: platformDependencies,
    targets: targets
)

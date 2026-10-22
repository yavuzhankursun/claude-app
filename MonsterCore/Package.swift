// swift-tools-version: 6.2
// MonsterCore: UI'dan bağımsız motor, protokol, transcript ve geçmiş katmanı.
// Uygulama hedefi (Monster.app) kökteki project.yml ile XcodeGen tarafından üretilir ve bu paketi kullanır.
import PackageDescription

let package = Package(
    name: "MonsterCore",
    defaultLocalization: "tr",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MonsterCore", targets: ["MonsterCore"]),
    ],
    targets: [
        .target(name: "MonsterCore"),
        .testTarget(
            name: "MonsterCoreTests",
            dependencies: ["MonsterCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)

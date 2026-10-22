// swift-tools-version: 6.2
// NovaCore: UI'dan bağımsız motor, protokol, transcript ve geçmiş katmanı.
// Uygulama hedefi (Nova.app) kökteki project.yml ile XcodeGen tarafından üretilir ve bu paketi kullanır.
import PackageDescription

let package = Package(
    name: "NovaCore",
    defaultLocalization: "tr",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "NovaCore", targets: ["NovaCore"]),
    ],
    targets: [
        .target(name: "NovaCore"),
        .testTarget(
            name: "NovaCoreTests",
            dependencies: ["NovaCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)

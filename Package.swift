// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WebtoonLensV2Core",
    platforms: [.macOS(.v14), .iOS("18.0")],
    products: [
        .library(name: "WebtoonLensCore", targets: ["WebtoonLensCore"]),
        .executable(name: "V2Checks", targets: ["V2Checks"])
    ],
    targets: [
        .target(name: "WebtoonLensCore", path: "Core/Sources"),
        .testTarget(name: "WebtoonLensCoreTests", dependencies: ["WebtoonLensCore"], path: "Tests/WebtoonLensCoreTests"),
        .testTarget(
            name: "BrowserV2IntegrationTests", dependencies: ["WebtoonLensCore"],
            path: "Tests/BrowserV2IntegrationTests"
        ),
        .executableTarget(
            name: "V2Checks", dependencies: ["WebtoonLensCore"],
            path: "Tests/BrowserV2Checks", resources: [.copy("Fixtures")]
        )
    ]
)

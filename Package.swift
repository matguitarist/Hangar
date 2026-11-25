// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Hangar",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        // The Log page's viewer, shared by my Mac apps.
        .package(url: "https://github.com/matguitarist/LogKit", from: "0.6.0"),
        // Folder sizes, the library file and its saves, and the Keychain, shared by my apps.
        .package(url: "https://github.com/matguitarist/FileKit", from: "0.1.0"),
    ],
    targets: [
        // Rules and data logic with no SwiftUI, so tests run without the app.
        .target(name: "HangarKit", dependencies: [.product(name: "LogKit", package: "LogKit"), .product(name: "FileKit", package: "FileKit")]),
        .executableTarget(
            name: "Hangar",
            dependencies: ["HangarKit", .product(name: "Sparkle", package: "Sparkle"),
                           .product(name: "LogKitUI", package: "LogKit"), .product(name: "FileKit", package: "FileKit")],
            // App code runs on the main thread unless you say otherwise.
            swiftSettings: [.defaultIsolation(MainActor.self)],
            // Sparkle.framework sits in Contents/Frameworks (build.sh copies it).
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "HangarKitTests", dependencies: ["HangarKit", .product(name: "LogKit", package: "LogKit"), .product(name: "FileKit", package: "FileKit")]),
    ]
)

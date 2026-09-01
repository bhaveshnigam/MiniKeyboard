// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MiniKeyboard",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MiniKeyboardKit", targets: ["MiniKeyboardKit"]),
        .executable(name: "minikeyboard", targets: ["minikeyboard"]),
        .executable(name: "MiniKeyboardApp", targets: ["MiniKeyboardApp"]),
    ],
    targets: [
        .target(
            name: "MiniKeyboardKit",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        .executableTarget(name: "minikeyboard", dependencies: ["MiniKeyboardKit"]),
        .executableTarget(name: "MiniKeyboardApp", dependencies: ["MiniKeyboardKit"]),
        .testTarget(name: "MiniKeyboardKitTests", dependencies: ["MiniKeyboardKit"]),
    ]
)

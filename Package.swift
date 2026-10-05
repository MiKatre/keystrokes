// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Keystrokes",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Keystrokes", targets: ["Keystrokes"])],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "KeystrokesCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "Keystrokes", dependencies: ["KeystrokesCore"]),
        .testTarget(name: "KeystrokesCoreTests", dependencies: ["KeystrokesCore"]),
    ]
)

// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "ILRailBar",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(name: "ILRailBar", targets: ["ILRailBar"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ILRailBar",
            dependencies: [],
            path: ".",
            exclude: ["ILrail-bar.xcodeproj", "Info.plist"]
        ),
    ]
)

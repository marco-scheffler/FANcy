// swift-tools-version:6.0
import PackageDescription

// The app itself is built by native/build.sh (swiftc), which compiles
// native/Core together with native/Sources into a single module. This package
// exists so the pure logic in native/Core can be unit-tested with `swift test`.
let package = Package(
    name: "FANcy",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "FANcyCore",
            path: "native/Core"
        ),
        .testTarget(
            name: "FANcyCoreTests",
            dependencies: ["FANcyCore"],
            path: "Tests/FANcyCoreTests"
        ),
    ],
    // Same language mode as the swiftc app build, so the tests exercise the
    // code exactly as it ships.
    swiftLanguageModes: [.v5]
)

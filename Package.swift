// swift-tools-version:5.9
// AdPluga iOS SDK version 0.2.0 — keep in sync with Constants.sdkVersion
// and the sdk-ios-vX.Y.Z release tag.
import PackageDescription

let package = Package(
    name: "AdPluga",
    platforms: [.iOS(.v14), .macOS(.v12)],
    products: [
        .library(name: "AdPluga", targets: ["AdPluga"]),
    ],
    targets: [
        .target(
            name: "AdPluga",
            path: "Sources/AdPluga"
        ),
        .testTarget(
            name: "AdPlugaTests",
            dependencies: ["AdPluga"],
            path: "Tests/AdPlugaTests"
        ),
    ]
)

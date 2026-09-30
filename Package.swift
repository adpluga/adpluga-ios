// swift-tools-version:5.9
// AdPluga iOS SDK — the version lives in Constants.sdkVersion
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

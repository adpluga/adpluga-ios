// swift-tools-version:5.9
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

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EblituiIOS",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "EblituiIOS", targets: ["EblituiIOS"]),
    ],
    targets: [
        .target(
            name: "EblituiIOS"
        ),
    ]
)

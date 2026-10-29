// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AdwellSDK",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "AdwellSDK", targets: ["AdwellSDK"])
    ],
    targets: [
        .target(name: "AdwellSDK", resources: [.copy("PrivacyInfo.xcprivacy")]),
        .testTarget(name: "AdwellSDKTests", dependencies: ["AdwellSDK"])
    ]
)

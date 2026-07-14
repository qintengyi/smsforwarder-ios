// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SmsForwarder",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .executable(name: "SmsForwarder", targets: ["SmsForwarder"])
    ],
    targets: [
        .executableTarget(
            name: "SmsForwarder",
            path: "Sources/SmsForwarder",
            resources: [
                .copy("Info.plist")
            ]
        )
    ]
)

// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MailSorter",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SharedKit", targets: ["SharedKit"]),
        .executable(name: "MailSorterDaemon", targets: ["MailSorterDaemon"]),
        .executable(name: "MailSorterApp", targets: ["MailSorterApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.29.0")
    ],
    targets: [
        .target(
            name: "SharedKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/SharedKit"
        ),
        .executableTarget(
            name: "MailSorterDaemon",
            dependencies: ["SharedKit"],
            path: "Sources/MailSorterDaemon"
        ),
        .executableTarget(
            name: "MailSorterApp",
            dependencies: ["SharedKit"],
            path: "Sources/MailSorterApp",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "SharedKitTests",
            dependencies: ["SharedKit"],
            path: "Tests/SharedKitTests"
        )
    ]
)

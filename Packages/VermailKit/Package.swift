// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VermailKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MailCore", targets: ["MailCore"]),
        .library(name: "MailTransport", targets: ["MailTransport"]),
        .library(name: "POP3Kit", targets: ["POP3Kit"]),
        .library(name: "SMTPKit", targets: ["SMTPKit"]),
        .library(name: "MIMEKit", targets: ["MIMEKit"]),
        .library(name: "MailStorage", targets: ["MailStorage"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.29.3"),
    ],
    targets: [
        .target(name: "MailCore"),
        .target(name: "MailTransport"),
        .target(name: "POP3Kit", dependencies: ["MailCore", "MailTransport"]),
        .target(name: "SMTPKit", dependencies: ["MailCore", "MailTransport"]),
        .target(name: "MIMEKit", dependencies: ["MailCore"]),
        .target(
            name: "MailStorage",
            dependencies: [
                "MailCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),

        .testTarget(name: "MailCoreTests", dependencies: ["MailCore"]),
        .testTarget(name: "MailTransportTests", dependencies: ["MailTransport"]),
        .testTarget(name: "POP3KitTests", dependencies: ["POP3Kit"]),
        .testTarget(name: "SMTPKitTests", dependencies: ["SMTPKit", "POP3Kit"]),
        .testTarget(name: "MIMEKitTests", dependencies: ["MIMEKit"]),
        .testTarget(name: "MailStorageTests", dependencies: ["MailStorage"]),
    ]
)

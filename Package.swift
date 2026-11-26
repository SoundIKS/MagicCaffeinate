// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MagicCaffeinate",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "MagicCaffeinate",
            path: "Sources/MagicCaffeinate",
            swiftSettings: [
                // Swift 5 language mode: нет жёстких проверок строгого concurrency,
                // не мешает маленькому статус-бар приложению.
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)

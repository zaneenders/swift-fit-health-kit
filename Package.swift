// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "swift-fit-health-kit",
  platforms: [
    .iOS(.v26),
    .macOS(.v26),
  ],
  products: [
    .library(name: "SwiftFitHealthKit", targets: ["SwiftFitHealthKit"])
  ],
  dependencies: [
    .package(
      url: "https://github.com/zaneenders/swift-fit.git",
      revision: "16d9e57a48464e5857c7b49e9a83fde0f8db202a"
    )
  ],
  targets: [
    .target(
      name: "SwiftFitHealthKit",
      dependencies: [
        .product(name: "SwiftFit", package: "swift-fit"),
        .product(name: "SwiftFitActivity", package: "swift-fit"),
      ],
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ]
    ),
    .testTarget(
      name: "SwiftFitHealthKitTests",
      dependencies: [
        "SwiftFitHealthKit",
        .product(name: "SwiftFit", package: "swift-fit"),
        .product(name: "SwiftFitActivity", package: "swift-fit"),
      ],
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ]
    ),
  ]
)

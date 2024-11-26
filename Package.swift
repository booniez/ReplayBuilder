// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ReplayBuilder",
    platforms: [.iOS(.v13)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "ReplayBuilder",
            targets: ["ReplayBuilder"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ReactiveX/RxSwift.git", exact: "6.8.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "ReplayBuilder",
            dependencies: [
                "RxSwift",
                .product(name: "RxRelay", package: "RxSwift"),
                .product(name: "RxCocoa", package: "RxSwift")
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "ReplayBuilderTests",
            dependencies: [
                "ReplayBuilder",
                "RxSwift"
            ],
            path: "Tests"
        ),
    ]
)

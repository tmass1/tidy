// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tidy",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "TidyCore", targets: ["TidyCore"])],
    targets: [
        .target(name: "TidyCore"),
        .executableTarget(name: "Tidy", dependencies: ["TidyCore"], path: "Sources/Tidy",
            linkerSettings: [.linkedFramework("Carbon"), .linkedFramework("ServiceManagement")]),
        .testTarget(name: "TidyCoreTests", dependencies: ["TidyCore"]),
        .testTarget(name: "TidyMacTests", dependencies: ["Tidy"], path: "Tests/TidyMacTests")
    ]
)

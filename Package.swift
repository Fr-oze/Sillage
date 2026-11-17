// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Neige",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Neige", targets: ["Neige"])],
    targets: [.executableTarget(name: "Neige")]
)

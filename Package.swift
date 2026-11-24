// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ClassicPaint", platforms: [.macOS(.v13)], products: [.executable(name: "ClassicPaint", targets: ["ClassicPaint"])], targets: [.executableTarget(name: "ClassicPaint")])

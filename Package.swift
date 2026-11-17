// swift-tools-version: 5.7
import PackageDescription
let package = Package(
    name: "TROLLfxMacEQ",
    platforms: [.macOS(.v12)],
    products: [.executable(name: "TROLLfxMacEQ", targets: ["TROLLfxMacEQ"])],
    targets: [.executableTarget(name: "TROLLfxMacEQ")]
)
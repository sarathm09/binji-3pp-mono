// swift-tools-version: 6.2
import PackageDescription

let libassRelease = "https://github.com/sarathm09/binji-3pp-mono/releases/download/0.17.5-binji.1"

func libassFramework(_ name: String, checksum: String) -> Target {
    .binaryTarget(name: name, url: "\(libassRelease)/\(name).xcframework.zip", checksum: checksum)
}

let package = Package(
    name: "binji-3pp-mono",
    platforms: [.iOS(.v26), .macOS(.v26), .tvOS(.v26), .visionOS(.v26)],
    products: [
        .library(name: "BinjiLibass", targets: ["Libass", "Libfreetype", "Libfribidi", "Libharfbuzz"]),
    ],
    targets: [
        libassFramework("Libass", checksum: "d3890015843f150e94dee0981338e2ba403dcc0d9caaf8746cbd271bae17faf9"),
        libassFramework("Libfreetype", checksum: "1913a904770ae59a37c988d3ca8bf9d61b26490a90692dde29782abb971f39c6"),
        libassFramework("Libfribidi", checksum: "78e0070dc3bc8e81b552c9281aa896b7b3a5ea3bb391fe95b24ec6c5b8925ffe"),
        libassFramework("Libharfbuzz", checksum: "5ec8307095c8fb641b2c17beed3c43e30eff3620d188f3aad79981f711461c99"),
    ]
)

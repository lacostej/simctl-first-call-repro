// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Probe",
    platforms: [.iOS(.v16)],
    products: [.library(name: "Probe", targets: ["Probe"])],
    targets: [
        .target(name: "Probe"),
        .testTarget(name: "ProbeTests", dependencies: ["Probe"]),
    ]
)

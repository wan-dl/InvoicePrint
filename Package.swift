// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "InvoicePrint",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "InvoicePrintCore",
            path: "Sources/InvoicePrintCore"
        ),
        .executableTarget(
            name: "InvoicePrintApp",
            dependencies: ["InvoicePrintCore"],
            path: "Sources/InvoicePrint"
        ),
        .executableTarget(
            name: "invoiceprint",
            dependencies: ["InvoicePrintCore"],
            path: "Sources/InvoicePrintCLI"
        )
    ]
)

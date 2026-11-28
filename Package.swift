// swift-tools-version: 5.9
import PackageDescription

// Compiles the same Foundation-only ledger files used by the iOS target.
let package = Package(
    name: "FinamiDomainTests",
    platforms: [.macOS(.v13), .iOS(.v16)],
    targets: [
        .target(name: "FinamiLedger", path: "Finora/Domain/Ledger"),
        .testTarget(name: "FinamiLedgerTests", dependencies: ["FinamiLedger"], path: "Tests/XCTest/Ledger")
    ]
)

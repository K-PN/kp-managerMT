// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SoNoAI",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "SoNoCore", targets: ["SoNoCore"])],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3", providers: [.apt(["libsqlite3-dev"]), .brew(["sqlite3"])]),
        .target(name: "SoNoCore", dependencies: ["CSQLite"], resources: [.copy("Persistence/Migrations")]),
        .testTarget(name: "SoNoCoreTests", dependencies: ["SoNoCore"])
    ]
)

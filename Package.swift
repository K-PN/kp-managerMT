// swift-tools-version: 5.9
import PackageDescription

#if os(Linux)
let sqliteTarget = Target.systemLibrary(name: "CSQLite", pkgConfig: "sqlite3", providers: [.apt(["libsqlite3-dev"])])
#else
// Apple builds must use SDK SQLite, never a Homebrew macOS dylib in an iOS link.
let sqliteTarget = Target.systemLibrary(name: "CSQLite")
#endif

let package = Package(
    name: "SoNoAI",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "SoNoCore", targets: ["SoNoCore"])],
    targets: [
        sqliteTarget,
        .target(name: "SoNoCore", dependencies: ["CSQLite"], resources: [.copy("Persistence/Migrations")]),
        .testTarget(name: "SoNoCoreTests", dependencies: ["SoNoCore"])
    ]
)

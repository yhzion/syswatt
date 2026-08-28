// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SysWatt",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "syswatt", targets: ["SysWatt"])
    ],
    targets: [
        // /usr/lib/libIOReport.dylib 의 비공개 심볼 선언 묶음
        .target(name: "CIOReport", linkerSettings: [.linkedLibrary("IOReport")]),
        // AppleSMC IOConnectCallStructMethod 용 펌웨어 구조체
        .target(name: "CSmc"),
        .executableTarget(
            name: "SysWatt",
            dependencies: ["CIOReport", "CSmc"],
            path: "Sources/SysWatt"
        )
    ]
)

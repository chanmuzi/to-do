// swift-tools-version: 6.2
import PackageDescription

// 모듈 하나가 타깃 하나다. 의존 방향(App → Features → Core)을 컴파일러가 강제한다.
// Features 타깃끼리는 서로 의존하지 않는다. 구조 설명은 docs/architecture.md.

/// 화면을 다루는 타깃(Features, App)은 기본 격리를 MainActor로 둔다.
/// AppKit, SwiftUI 코드가 대부분 메인 스레드 전용이라 타입마다 @MainActor를 붙이지 않아도 된다.
let uiSettings: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "FloatingNotes",
    defaultLocalization: "ko",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "FloatMCP", targets: ["FloatMCP"]),
        .executable(name: "FloatingNotes", targets: ["FloatingNotes"]),
    ],
    targets: [
        // MARK: Core
        .target(
            name: "Theme",
            dependencies: ["Models"],
            // Resources/ 안의 항목은 App/Resources/ 를 가리키는 심볼릭 링크다(정본은 App/Resources/).
            resources: [.copy("Resources/tokens.json"), .copy("Resources/Fonts"), .copy("Resources/AgentLogos")]
        ),
        .target(name: "AgentRunner", dependencies: ["Store"]),
        .target(name: "Models"),
        .target(name: "MarkdownSyntax"),
        .target(name: "DateTime", dependencies: ["Models"]),
        .target(name: "SpaceIcons", dependencies: ["Models", "Theme"],
                resources: [.copy("Resources/SpaceImages")], swiftSettings: uiSettings),
        .target(name: "Store", dependencies: ["Models"]),
        .target(name: "Routing", dependencies: ["Models"]),

        .target(name: "Scheduling", dependencies: ["Models", "Store", "DateTime"]),

        // MARK: Features (서로 의존하지 않는다)
        .target(
            name: "NotePanel",
            dependencies: ["Theme", "Models", "Store", "Routing", "SpaceIcons", "DateTime"],
            swiftSettings: uiSettings
        ),
        .target(
            name: "Editor",
            dependencies: ["Theme", "DateTime", "MarkdownSyntax"],
            swiftSettings: uiSettings
        ),
        .target(
            name: "Capture",
            dependencies: ["Theme", "Models", "Store", "Routing", "DateTime"],
            swiftSettings: uiSettings
        ),
        .target(
            name: "Browse",
            dependencies: ["Theme", "Models", "Store", "Routing", "SpaceIcons"],
            swiftSettings: uiSettings
        ),

        .target(name: "Agent", dependencies: ["Theme", "Models", "Store", "Routing"], swiftSettings: uiSettings),

        .target(name: "Library", dependencies: ["MarkdownSyntax", "Theme", "Models", "Store", "Routing", "SpaceIcons"],
                swiftSettings: uiSettings),

        .target(name: "Reminders", dependencies: ["Theme", "Models", "Store", "DateTime"], swiftSettings: uiSettings),

        .target(name: "FloatSettings", dependencies: ["Models", "Theme", "Scheduling", "AgentRunner", "Store"], swiftSettings: uiSettings),

        .executableTarget(name: "FloatMCP", dependencies: ["Models"]),

        // MARK: App
        .executableTarget(
            name: "FloatingNotes",
            dependencies: [
                "Theme", "Models", "Store", "Routing", "AgentRunner", "Agent",
                "NotePanel", "Editor", "Capture", "Browse", "Library", "Scheduling", "Reminders", "DateTime", "FloatSettings",
            ],
            // Resources/ 안의 항목은 App/Resources/ 를 가리키는 심볼릭 링크다(정본은 App/Resources/).
            resources: [.copy("Resources/menubar-icon.pdf")],
            swiftSettings: uiSettings
        ),

        // 편집기만 띄워 보는 확인용 실행 파일. 앱에는 들어가지 않는다.
        .executableTarget(
            name: "EditorDemo",
            dependencies: ["Editor", "Theme"],
            swiftSettings: uiSettings
        ),

        // 캡처 바와 노트 찾기만 띄워 보는 확인용 실행 파일. 앱에는 들어가지 않는다.
        .executableTarget(
            name: "Stage4Demo",
            dependencies: ["Capture", "Browse", "Theme", "Models", "Store", "Routing"],
            swiftSettings: uiSettings
        ),

        // MARK: Tests
        .testTarget(name: "AgentTests", dependencies: ["Agent", "Theme", "Models", "Store"], swiftSettings: uiSettings),
        .testTarget(name: "AgentRunnerTests", dependencies: ["AgentRunner"]),
        .testTarget(name: "FloatMCPTests", dependencies: ["FloatMCP"]),
        .testTarget(name: "SchedulingTests", dependencies: ["FieldTestSupport", "Scheduling", "Models", "Store", "Reminders", "Theme"], swiftSettings: uiSettings),
        .testTarget(name: "LibraryTests", dependencies: ["FieldTestSupport", "Library", "SpaceIcons", "Store", "Models", "Theme", "Routing"], swiftSettings: uiSettings),
        .target(name: "FieldTestSupport", dependencies: ["Theme"], path: "Tests/ThemeTests/Support"),
        .testTarget(name: "ThemeTests", dependencies: ["Theme", "FieldTestSupport"], exclude: ["Support"]),
        .testTarget(name: "ModelsTests", dependencies: ["Models"]),
        .testTarget(name: "StoreTests", dependencies: ["Store", "Models"]),
        .testTarget(name: "RoutingTests", dependencies: ["Routing", "Models"]),
        .testTarget(
            name: "NotePanelTests",
            dependencies: ["FieldTestSupport", "NotePanel", "Theme", "Models", "Store", "Routing"]
        ),
        .testTarget(
            name: "FloatingNotesTests",
            dependencies: [
                "FloatingNotes", "FloatSettings", "Scheduling", "Library", "NotePanel", "Editor", "Capture", "Browse", "Theme", "Models", "Store", "Routing",
            ],
            swiftSettings: uiSettings
        ),
        .testTarget(name: "EditorTests", dependencies: ["FieldTestSupport", "Editor", "Theme"]),
        .testTarget(
            name: "CaptureTests",
            dependencies: ["FieldTestSupport", "Capture", "Theme", "Models", "Store", "Routing", "DateTime"],
            swiftSettings: uiSettings
        ),
        .testTarget(
            name: "BrowseTests",
            dependencies: ["FieldTestSupport", "Browse", "Theme", "Models", "Store", "Routing"],
            swiftSettings: uiSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)

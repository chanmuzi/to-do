# 모듈 구조

컴포넌트를 독립된 모듈로 나눠, 하나를 고치거나 확장해도 다른 것에 영향이 가지 않게 한다.
프로젝트 뼈대를 만드는 1단계에서 이 구조대로 세우고, 달라지는 점이 생기면 이 문서를 고친다.

## 계층과 의존 방향

```
App          앱 진입점, 창 띄우기, 메뉴 막대, 모듈 조립
  ↓
Features     화면 단위 모듈 (서로 참조하지 않는다)
  ↓
Core         모든 기능이 공유하는 바탕
```

의존은 위에서 아래로만 흐른다. Features의 모듈끼리는 서로 import하지 않는다.
한 기능이 다른 기능을 열어야 하면(예: 노트 창에서 AI 패널 열기) Core에 정의한 프로토콜을 통해 요청하고, App이 연결한다.

## 모듈

| 계층 | 모듈 | 책임 | 명세 |
| --- | --- | --- | --- |
| Core | `Theme` | `tokens.json` 읽기, 라이트·다크, 사용자 테마 덮어쓰기, 글꼴 등록 | 03 |
| Core | `Models` | 노트, 스페이스, 리마인더 같은 값 타입 | |
| Core | `Store` | 노트 파일 읽기·쓰기, 변경 감시. 저장 방식이 바뀌어도 이 모듈만 바뀐다 | decisions D-003 |
| Core | `Routing` | 기능 사이 요청을 전달하는 프로토콜 | 04 |
| Features | `NotePanel` | 플로팅 노트 창, 상단 줄, 호버 동작 | 05 |
| Features | `Editor` | TextKit 2 마크다운 편집기. 창과 무관하게 단독으로 쓸 수 있어야 한다 | 06 |
| Features | `Capture` | 빠른 캡처 바 | 07 |
| Features | `Browse` | 노트 찾기 | 08 |
| Features | `Library` | 라이브러리, 스페이스 아이콘 고르기 | 09, 10 |
| Features | `Reminders` | 리마인더 설정, 표시, 알림 | |
| Features | `Settings` | 테마 설정, 단축키 표 | 12, 13 |
| Features | `Agent` | AI 패널과 에이전트 연결. 연결 대상(Claude, Codex)은 같은 프로토콜의 구현으로 추가한다 | 11 |

## 규칙

- 모듈마다 공개하는 타입을 최소로 한다. 나머지는 모듈 안에 숨긴다.
- 화면 값은 `Theme`에서만 가져온다.
- 파일 하나에는 한 가지 책임만 둔다.
- 새 기능은 기존 모듈을 고치기보다 새 모듈을 추가하는 쪽을 먼저 검토한다.
- 모듈마다 단독으로 실행되는 테스트를 둔다.

## 폴더

```
App/
├─ Package.swift      모듈을 SwiftPM 타깃으로 정의해 의존 방향을 컴파일러가 강제하게 한다
├─ Sources/<모듈명>/   앱 실행 타깃은 Sources/FloatingNotes/
├─ Tests/<모듈명>Tests/
└─ Resources/         tokens.json, Fonts/, AppIcon.appiconset, Info.plist
scripts/
├─ build-app.sh       빌드해서 build/FloatingNotes.app 을 만든다 (인자: debug|release, 기본 release)
└─ run.sh             빌드 뒤 실행. 인자는 앱에 그대로 넘긴다
```

- Xcode 프로젝트 파일은 없다(D-011). `cd App && swift build`, `swift test`.
- `Sources/Theme/Resources/`의 `tokens.json`, `Fonts`는 `App/Resources/`를 가리키는 심볼릭 링크다. 정본은 `App/Resources/` 하나다.
- 실행 인자(확인용): `--notes-dir <경로>`(그 폴더만 읽고 씀), `--appearance light|dark`. 환경 변수 `FLOATING_NOTES_DIR`도 같은 일을 한다.

## 빌드 설정

- Swift 6 언어 모드(엄격한 동시성 검사), swift-tools-version 6.2, macOS 26 이상, 외부 의존 없음.
- Features와 App 타깃은 기본 격리가 MainActor다(`.defaultIsolation(MainActor.self)`). AppKit·SwiftUI 코드에 `@MainActor`를 일일이 붙이지 않는다. 메인 밖에서 돌릴 코드만 `nonisolated`로 표시한다.
- Core 타깃은 기본 격리가 없다. 값 타입은 `Sendable`이고, 상태를 가진 클래스(`Theme`, `FileNoteStore` 등)에만 `@MainActor`를 붙였다.
- 테스트는 Swift Testing(`import Testing`)으로 쓴다.

## Core 공개 API

기능 모듈은 아래만 보고 만든다. 자세한 것은 각 타입의 문서 주석에 있다.

### Theme

- `Theme` (`@MainActor @Observable`): `Theme.bundled(overrideStore:appearance:)`로 만든다. App이 하나 만들어 넘긴다. SwiftUI는 `@Environment(\.theme)`로도 받는다.
  - 색: `color(_: ColorToken) -> Color`, `nsColor(_:) -> NSColor`(둘 다 뷰의 라이트·다크를 스스로 따라감), `rgba(_:) -> RGBA`(지금 모양의 값), `noteBackgroundColor(paletteID:)` / `noteBackgroundNSColor(paletteID:)`, `shadow(_: ShadowToken) -> [ShadowLayer]`
  - 글꼴: `font(_: TextStyle, size:weight:) -> Font`, `nsFont(_:size:weight:) -> NSFont`, `lineHeight(_:)`, `tracking(_:)`. `TextStyle`은 spec 3.1 표의 줄(`.title .h1 .h2 .h3 .body .strong .paneTitle .row .rowSub .ui .micro .code .capture`)
  - 치수: `space(_: SpaceToken)`, `shape(_: ShapeToken)`, `component(_: ComponentToken)`, `docPadding`, `material`(opacity, blur, tintMix, tintMixRow), `motion`(duration, curve, `.animation`, `.timingFunction`), `palette`, `accentPresets`
  - 형광펜: `HighlightColor`(`.yellow=1 .gray .rose .blue`, 번호는 D-008의 `{n}`) → `.background`, `.foreground`가 `ColorToken`
  - 상태: `appearance`, `tokens`, `overrides`, `setOverrides(_:) throws`, `followAppearance(of: NSApplication)`. AppKit 쪽은 `Theme.didChangeNotification`을 받아 다시 그린다.
- `ThemeTokens` (`Sendable` 값): `tokens.json`을 푼 것. `Theme` 없이 쓸 수 있다. `color(_:_:)`, `textStyle(_:)`, `noteBackground(paletteID:_:)`, `rowTint(paletteID:)`, `applying(_: ThemeOverrides)`.
- `ThemeOverrides`: `[구역.키: 값]` 사전. 키 예 `color.light.accent`, `type.fs-body`, `palette.tint-1`. 값 표기는 `tokens.json`과 같다. `ThemeOverrideStore(url:)`가 JSON 파일로 읽고 쓴다(`stateDirectory/theme-overrides.json`).
- `FontRegistrar.registerBundledFonts()`: App이 켤 때 부른다. 기능 모듈은 부르지 않는다.
- 새 토큰을 쓰려면 `tokens.json`에 값을 넣고 `TokenKeys.swift`의 enum에 case를 더한다. 테스트가 파일과 enum이 어긋나면 실패한다.

### Models

- `Note`: `id: NoteID`, `title`, `body`(Markdown 원문), `spaceID: SpaceID?`, `colorID: PaletteID?`, `reminder: Date?`, `created`, `modified`. 핀은 없다(아래).
- `NoteDraft`: 새 노트 내용(`title`, `body`, `spaceID`, `colorID`, `reminder`).
- `NoteWindowState`: `frame: WindowFrame?`, `isPinned`(기본 켜짐), `isOpen`. 노트 파일이 아니라 로컬 상태다(D-003).
- `Space`(`id`, `name`, `icon: SpaceIcon`), `SpaceIcon`(`.symbol(name:colorID:)`, `.emoji`, `.image`).
- `NoteID`, `SpaceID`, `PaletteID`: 문자열을 감싼 식별자. `PaletteID.rawValue`를 `Theme`의 `paletteID:`에 넘긴다.

### Store

- `NoteStoring` (`@MainActor` 프로토콜, 구현은 `FileNoteStore`): `list()`, `load(_:)`, `create(_: NoteDraft)`, `save(_:)`(곧바로), `scheduleSave(_:)`(자동 저장, 기본 0.5초 뒤), `flushPendingSaves()`, `moveToTrash(_:)`, `listTrash()`, `restoreFromTrash(_:)`, `observe(_:) -> StoreObservation`. 모두 동기 호출이고 실패하면 던진다.
- `StoreChange`: `id`, `kind`(`.created .updated .removed .saveFailed(message:)`), `origin`(`.local` 이 앱, `.external` 다른 프로그램). 편집기는 `.external` `.updated`일 때만 다시 읽으면 된다.
- `FileNoteStore.refresh()`: 폴더를 다시 훑는다. 폴더 감시는 파일이 생기고 없어지고 바꿔치기되는 것만 잡고, 제자리 수정은 이 호출이 잡는다.
- `StoreLocation`: `notesDirectory`, `trashDirectory`(`notes/.trash/`), `stateDirectory`. `.standard()`는 `~/Library/Application Support/FloatingNotes/{notes,state}`, `.isolated(notesDirectory:)`는 그 폴더 안만 쓴다.
- `WindowStateStore`: `state(for:)`, `set(_:for:)`, `remove(_:)`, `all` → `stateDirectory/windows.json`.
- `SpaceStore`: `spaces`, `space(for:)`, `replace(with:)` → `stateDirectory/spaces.json`.
- 노트 파일은 `<id>.md`. 머리는 `title`(따옴표 문자열), `space`, `color`, `reminder`, `created`(ISO 8601, UTC, 초 단위)이고 닫는 `---` 다음 글자부터 끝까지가 본문 그대로다. 모르는 머리 줄은 저장해도 남는다. 머리 없는 `.md`도 읽는다.

### Routing

- `Route`: `.openNote(NoteID)`, `.newNote(NewNoteRequest)`, `.closeNoteWindow(NoteID)`, `.openCapture`, `.openBrowse(anchor: NoteID?)`, `.toggleAllNotesHidden`, `.openLibrary`, `.openAIPanel(context: NoteID?)`, `.openSettings`, `.openShortcuts`.
- `Routing` (`@MainActor` 프로토콜): `route(_: Route)`. 기능 모듈은 `any Routing`을 받아 부르기만 한다. SwiftUI는 `@Environment(\.router)`.
- `RouteDispatcher(handler:)`: 클로저로 받는 기본 구현(테스트용으로도 쓴다).

## App 타깃 (`Sources/FloatingNotes/`)

- `AppEnvironment`가 `Theme`, `FileNoteStore`, `WindowStateStore`, `SpaceStore`를 한 번 만들고, `AppRouter`(`Routing` 구현)가 요청을 받는다. 지금 `AppRouter`는 요청을 기록만 한다.
- 지금은 `PlaceholderWindowController`가 테마 확인용 창 하나를 띄운다. 2단계에서 `AppDelegate.showInitialWindows()`를 노트 창을 되살리는 코드로 바꾸고 `Placeholder*` 두 파일을 지운다.
- Features 타깃 `NotePanel`, `Editor`, `Capture`, `Browse`는 자리표시(`<모듈>Module`)만 있다. `Editor`는 `Theme`, `Models`에만 의존한다. `Library`, `Reminders`, `Settings`, `Agent`는 아직 타깃이 없다.

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
- 확인용 실행 인자: `--debug-hover <노트 id>`(그 노트를 마우스가 올라간 모습으로 띄움), `--debug-control`(다른 프로세스가 분산 알림 `local.floating-notes.debug`로 보내는 명령을 받음. 명령 목록은 `DebugControl.swift`의 주석). 마우스와 키보드를 건드리지 않고 창 상태를 바꾸고 읽을 때 쓴다.

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
  - 상태: `appearance`, `tokens`, `overrides`, `setOverrides(_:) throws`(잘못된 키·값이면 던지고 아무것도 바꾸지 않음), `followAppearance(of: NSApplication)`, `loadWarnings: [String]`. AppKit 쪽은 `Theme.didChangeNotification`을 받아 다시 그린다.
  - 저장된 덮어쓰기를 읽을 때는 던지지 않는다. 없어진 키나 잘못된 값은 버리고, 깨진 파일은 `theme-overrides.json.corrupt`로 옮긴 뒤 기본 테마로 시작하며, 버린 것을 `loadWarnings`에 적는다.
- `ThemeTokens` (`Sendable` 값): `tokens.json`을 푼 것. `Theme` 없이 쓸 수 있다. `color(_:_:)`, `textStyle(_:)`, `noteBackground(paletteID:_:)`, `rowTint(paletteID:)`, `applying(_: ThemeOverrides) throws`(엄격), `applyingValid(_:) -> (tokens, accepted, rejected: [ThemeError])`(쓸 수 있는 것만 얹음).
- 토큰 값 검증: 수는 십진 표기만 받는다(`nan`, `inf`, `0x10`, `1e3` 거부). 글자 크기·줄 높이는 0보다 커야 하고, 간격·모서리·치수·여백·흐림은 0 이상, 굵기는 1~1000, 불투명도는 0~1, 섞는 비율은 0~100%여야 한다. `tokens.json`과 덮어쓰기에 똑같이 적용된다.
- `ThemeOverrides`: `[구역.키: 값]` 사전. 키 예 `color.light.accent`, `type.fs-body`, `palette.tint-1`. 값 표기는 `tokens.json`과 같다. `ThemeOverrideStore(url:)`가 JSON 파일로 읽고 쓴다(`stateDirectory/theme-overrides.json`).
- `FontRegistrar.registerBundledFonts() -> FontRegistration`(`registered: [URL]`, `problems: [String]`): App이 켤 때 부른다. 던지지 않는다. 등록하지 못한 글꼴은 `problems`에 적히고 글꼴 고르기는 시스템 글꼴로 넘어간다. 기능 모듈은 부르지 않는다.
- 글꼴 고르기: 가족 이름은 `<이름> Variable`(번들의 가변 글꼴)을 먼저 찾고 그다음 `<이름>`을 찾는다. 가변 글꼴은 굵기 축에 토큰 값을 그대로 넣고, 굵기별 파일로 된 가족은 CSS 굵기가 가장 가까운 파일을 고른다.
- 새 토큰을 쓰려면 `tokens.json`에 값을 넣고 `TokenKeys.swift`의 enum에 case를 더한다. 테스트가 파일과 enum이 어긋나면 실패한다.
- 노트 창 단계에서 더한 토큰(시안의 CSS에만 있던 값): `component`의 `chrome-gap`, `chrome-pad-end`, `icon-s|m|l`(12, 13, 14), `icon-btn-gap`, `swatch-size|gap|ring`, `menu-w`, `note-w`, `note-w-min`, `note-w-max`와 `type.fw-ui-strong`(`TextStyle.uiStrong`, 임박한 리마인더).

### Models

- `Note`: `id: NoteID`, `title`, `body`(Markdown 원문), `spaceID: SpaceID?`, `colorID: PaletteID?`, `reminder: Date?`, `created`, `modified`. 핀은 없다(아래).
- `NoteDraft`: 새 노트 내용(`title`, `body`, `spaceID`, `colorID`, `reminder`).
- `NoteWindowState`: `frame: WindowFrame?`, `isPinned`(기본 켜짐), `isOpen`. 노트 파일이 아니라 로컬 상태다(D-003).
- `Space`(`id`, `name`, `icon: SpaceIcon`), `SpaceIcon`(`.symbol(name:colorID:)`, `.emoji`, `.image`).
- `NoteID`, `SpaceID`, `PaletteID`: 문자열을 감싼 식별자. `PaletteID.rawValue`를 `Theme`의 `paletteID:`에 넘긴다.

### Store

- `NoteStoring` (`@MainActor` 프로토콜, 구현은 `FileNoteStore`). 모두 동기 호출이고 실패하면 `StoreError`를 던진다.
  - `list() throws -> NoteListing`, `listTrash() throws -> NoteListing`: `NoteListing`은 `notes: [Note]`(최근에 고친 것이 앞)와 `failures: [NoteReadFailure]`(`id`, `url`, `error`). 읽지 못하는 `.md`(UTF-8 아님, `.md`로 끝나는 폴더)가 있어도 나머지를 돌려준다. 폴더 자체를 못 읽을 때만 던진다.
  - `load(_ id: NoteID) throws -> Note`: 노트의 지금 값(아직 쓰지 않은 변경 포함).
  - `create(_ draft: NoteDraft) throws -> Note`: 파일을 새로 만드는 호출은 이것뿐이다.
  - `update(_ id: NoteID, _ mutate: (inout Note) -> Void) throws -> Note`: 지금 값에 적용하고 곧바로 쓴다(`@discardableResult`).
  - `scheduleUpdate(_ id: NoteID, _ mutate: (inout Note) -> Void) throws -> Note`: 지금 값에 적용하고 잠시 뒤에 쓴다(자동 저장). 마지막 변경 뒤 0.5초, 계속 고치는 중이어도 첫 변경 뒤 3초 안에 쓴다. 돌려주는 값은 적용한 뒤의 지금 값.
  - `flushPendingSaves() throws`: 미뤄 둔 변경을 모두 쓴다. 하나가 실패해도 나머지를 쓰고, 실패한 것은 남겨 둔 채 `StoreError.pendingSavesFailed([SaveFailure])`(`id`, `title`, `error`)를 던진다.
  - `resolveConflict(_ id: NoteID, keeping: ConflictSide) throws -> Note`: `.mine`(이 앱에서 고친 내용을 쓴다) 또는 `.disk`(디스크 내용을 받아들이고 쓰지 않은 변경을 버린다).
  - `moveToTrash(_ id: NoteID) throws`, `restoreFromTrash(_ id: NoteID) throws -> Note`.
  - `refresh() throws`: 폴더를 다시 훑는다. 폴더 감시는 파일이 생기고 없어지고 바꿔치기되는 것만 잡고, 제자리 수정은 이 호출이 잡는다. App이 앞으로 올 때 부른다.
  - `observe(_ handler: (StoreChange) -> Void) -> StoreObservation`: 돌려받은 값을 들고 있는 동안만 알림이 온다.
- 노트를 고치는 규칙(기능 모듈이 지켜야 하는 것):
  - 노트의 지금 값은 저장소가 들고 있다. 노트를 통째로 넘겨 덮어쓰는 호출은 없다. 자기가 맡은 항목만 클로저에서 고친다. 예: 편집기 쪽 `scheduleUpdate(id) { $0.body = text }`, 노트 창 `update(id) { $0.colorID = color }`. 클로저는 다른 쪽이 미뤄 둔 변경까지 들어 있는 값을 받으므로 서로의 변경을 지우지 않는다.
  - 클로저에서 `id`, `created`, `modified`는 바꿀 수 없다(`modified`는 바꿔도 무시한다). 바뀐 것이 없으면 쓰지 않고 알리지도 않는다.
  - 노트 폴더에 파일이 없는 노트(휴지통으로 갔거나 지워짐)를 고치면 `noteNotFound`이고 파일을 만들지 않는다. 휴지통으로 보낸 뒤 늦게 도착한 저장이 노트를 되살리지 않는다.
  - `moveToTrash`는 미뤄 둔 변경을 먼저 쓰고 옮긴다. 그 쓰기가 실패하면(충돌 포함) 옮기지 않고 던진다. 휴지통에 같은 이름의 파일이 있으면 그 옛 파일을 `<id>-2.md`, `<id>-3.md`…로 옮겨 둘 다 남긴다(방금 버린 것이 원래 이름을 갖는다).
- 다른 프로그램이 고친 파일(충돌) 정책:
  - 저장소는 노트마다 "마지막으로 내준 글"을 기억한다. `load`, `create`, `restoreFromTrash`, 쓰기 성공, `resolveConflict`가 이것을 갱신한다. `list`, `refresh`는 갱신하지 않는다.
  - 쓰기 직전에 디스크의 글이 이것과 다르면 쓰지 않는다. `update`는 `StoreError.conflict(id)`를 던지고, 자동 저장은 `StoreChange.Kind.conflict`를 알린다. 고친 내용은 저장소에 남고(`load`가 돌려준다) `resolveConflict`로 풀 때까지 그 노트는 디스크에 쓰지 않는다. 글 전체를 견주므로 수정 시각만 바뀐 파일은 충돌이 아니다.
  - 쓰지 않은 변경이 없는 노트를 다른 프로그램이 고치면 `.updated`/`.external`이 온다. 그 노트를 보여 주는 쪽은 `load`로 다시 읽는다(다시 읽으면 충돌 기준도 갱신된다). 다시 읽지 않고 고치면 `conflict`다.
  - 노트를 편집용으로 열 때는 `list()`의 값을 그대로 쓰지 말고 `load(id)`를 한 번 부른다.
- `StoreChange`: `id`, `kind`(`.created .updated .removed .saveFailed(message:) .conflict`), `origin`(`.local` 이 앱, `.external` 다른 프로그램). `.saveFailed`와 `.conflict`는 미뤄 둔 저장에서만 오고, 고친 내용은 저장소에 남아 있다.
- `StoreError`: `.noteNotFound(id)`, `.noteAlreadyExists(id)`, `.unreadableFile(url)`, `.conflict(id)`, `.writeFailed(id, message:)`, `.pendingSavesFailed([SaveFailure])`.
- `StoreLocation`: `notesDirectory`, `trashDirectory`(`notes/.trash/`), `stateDirectory`. `.standard()`는 `~/Library/Application Support/FloatingNotes/{notes,state}`, `.isolated(notesDirectory:)`는 그 폴더 안만 쓴다.
- `WindowStateStore`: `state(for:)`, `set(_:for:)`, `remove(_:)`, `all`, `loadWarning: String?` → `stateDirectory/windows.json`.
- `SpaceStore`: `spaces`, `space(for:)`, `replace(with:)`, `loadWarning: String?` → `stateDirectory/spaces.json`.
- 두 상태 파일이 깨져 있으면(잘림, 모양 다름) 지우지 않고 `<이름>.corrupt`(이미 있으면 `.corrupt-2`…)로 옮긴 뒤 빈 상태로 시작하고 `loadWarning`에 적는다.
- 노트 파일은 `<id>.md`. 머리는 `title`(따옴표 문자열), `space`, `color`, `reminder`, `created`(ISO 8601, UTC, 초 단위)이고 닫는 `---` 다음 글자부터 끝까지가 본문 그대로다. 머리 없는 `.md`도 읽는다.
  - 아는 항목은 들여쓰기 없이 줄 맨 앞에서 시작하는 다섯 키뿐이다. 들여쓴 줄과 모르는 줄은 저장해도 그대로 남는다.
  - 이미 있는 파일을 고쳐 쓸 때는 값이 바뀐 항목의 줄만 새로 적는다. 값이 그대로인 줄(손으로 적은 표기, 초 아래 자리가 있는 날짜, 읽지 못한 날짜)과 줄 순서, 줄바꿈 종류, 맨 앞의 BOM은 그대로 둔다. `created` 줄은 있으면 언제나 그대로 둔다.
  - 날짜는 ISO 8601로 읽는다. 초 아래 자리(`…00.123Z`)와 날짜만 있는 값(`2026-11-17`, UTC 자정)도 받는다. 읽지 못한 `reminder`는 리마인더 없음으로 읽히고, 리마인더를 새로 정할 때만 그 줄이 바뀐다.

### Routing

- `Route`: `.openNote(NoteID)`, `.newNote(NewNoteRequest)`, `.closeNoteWindow(NoteID)`, `.openCapture`, `.openBrowse(anchor: NoteID?)`, `.toggleAllNotesHidden`, `.openLibrary`, `.openAIPanel(context: NoteID?)`, `.openSettings`, `.openShortcuts`, `.openReminderEditor(NoteID)`, `.openSpacePicker(NoteID)`.
- `Routing` (`@MainActor` 프로토콜): `route(_: Route)`. 기능 모듈은 `any Routing`을 받아 부르기만 한다. SwiftUI는 `@Environment(\.router)`.
- `RouteDispatcher(handler:)`: 클로저로 받는 기본 구현(테스트용으로도 쓴다).

## NotePanel 공개 API

플로팅 노트 창(spec 04, 05, 19). Core 모듈만 import하고, 다른 기능은 `Routing`으로만 부른다.

- `NotePanelCoordinator`: 떠 있는 노트 창 전부를 맡는다. App이 하나 만든다.
  - `init(theme:notes:windowStates:spaces:router:makeBodyEditor:log:)`. `makeBodyEditor`를 주지 않으면 기본 편집기(`PlainTextBodyEditor`)를 쓴다.
  - `restoreOpenNotes() -> [NoteID]`(지난번에 떠 있던 창을 제자리에), `open(_:nextTo:focus:) throws`, `createNote(_: NewNoteRequest) throws -> NoteID`(지금 노트 옆에 핀이 켜진 채), `closeWindow(_:)`(창만 내림), `moveToTrash(_:)`, `toggleAllHidden()`, `areNotesHidden`.
  - 창마다: `openNoteIDs`, `keyNoteID`, `snapshot(of:) -> NoteWindowSnapshot?`(틀, 핀, 창 단계, 보임, 호버), `setPinned(_:for:)`, `setColor(_:for:)`, `focusBody(of:)`, `popUpMoreMenu(for:)`, `setHoverOverride(_:for:)`(확인용).
  - `displayOptions: NotePanelDisplayOptions`: 스페이스 표시(아이콘, 아이콘+이름, 이름), 리마인더 표시(시간, 남은 시간, 아이콘), 시간 형식, 임박 기준. 설정 화면이 생기면 여기에 넣는다.
- 노트 창이 하는 일과 하지 않는 일:
  - 제목, 노트 색은 `update`/`scheduleUpdate`로 그 항목만 고친다. 핀과 창 틀, 열림 상태는 `WindowStateStore`에 둔다.
  - 노트 찾기, 새 노트, 창 닫기, 리마인더 설정, 스페이스 옮기기, AI 패널은 `Route`를 보낸다. 직접 열지 않는다.
  - 저장소 변경을 받아 다시 읽는다(`.updated`는 `load`, `.removed`는 창을 내림). 충돌(`.conflict`)이나 저장 실패가 나면 사용자가 쓴 글을 그대로 두고 상단 줄에 표시 하나를 띄운다. 누르면 내 내용으로 저장 / 파일의 내용으로 되돌리기(`resolveConflict`), 다시 저장을 고른다. 쓰지 못한 글이 있는 창은 닫지 않는다.
- 안쪽 구조: `Logic/`은 화면 없이 시험하는 값 계산(`TopRowState` 상단 줄의 내용과 색, `TopRowLayout` 요소 자리, `ReminderPresentation`, `NoteSizePolicy`, `WindowPlacement`, `HeightTransition`, `WindowStateRecorder`), `Views/`는 AppKit 뷰, `Menu/`는 더 보기 메뉴, `Body/`는 본문 이음매.

### 본문 편집기 이음매

노트 창은 편집기 모듈을 import하지 않는다. 아래 프로토콜의 구현을 App이 만들어 넘긴다.

```swift
@MainActor public protocol NoteBodyEditing: AnyObject {
    var view: NSView { get }
    var text: String { get set }
    var onTextChange: ((String) -> Void)? { get set }
    var onContentHeightChange: ((CGFloat) -> Void)? { get set }
    func focus()
}
public struct NoteBodyEditorContext { public let theme: Theme; public let noteID: NoteID }
public typealias NoteBodyEditorFactory = @MainActor (NoteBodyEditorContext) -> any NoteBodyEditing
```

- `view`는 노트 창이 가진 스크롤 뷰의 문서 뷰가 된다. 노트 창은 너비만 맞추고, 높이는 `view`가 내용에 맞춘다. 뒤집힌 좌표(`isFlipped`)여야 한다.
- 안쪽 여백(`Theme.docPadding`)은 편집기가 넣는다.
- `onContentHeightChange`에는 여백을 포함한 내용 높이를 넘긴다(글이나 너비가 바뀔 때마다, 처음 배치된 뒤 한 번). 노트 창이 이 값으로 창 높이를 맞춘다(위쪽 고정, 아래로, `dur` 동안).
- `text`를 밖에서 넣을 때는 `onTextChange`를 부르지 않는다. 노트 창은 `onTextChange`를 받아 `scheduleUpdate(id) { $0.body = text }`를 부르고, 저장소에서 온 변경은 `text`에 넣는다.
- `PlainTextBodyEditor(theme:)`: 서식 없는 기본 구현(TextKit 1). Editor 모듈을 끼울 때는 이 프로토콜에 맞춘 어댑터를 App 타깃에 두고 `makeBodyEditor`로 넘긴다.

## App 타깃 (`Sources/FloatingNotes/`)

- `AppEnvironment`가 `Theme`, `FileNoteStore`, `WindowStateStore`, `SpaceStore`를 한 번 만들고, `AppRouter`(`Routing` 구현)가 요청을 받는다. `AppRouter`는 `.openNote`, `.newNote`, `.closeNoteWindow`, `.toggleAllNotesHidden`을 `NotePanelCoordinator`로 넘기고, 나머지는 아직 기록만 한다.
- 켤 때 버려도 되는 상태가 잘못돼 있으면 앱을 멈추지 않고 기본값으로 넘어간다(글꼴 등록 실패 → 시스템 글꼴, 쓸 수 없는 테마 덮어쓰기 → 버림, 깨진 상태 파일 → 옆으로 옮기고 빈 상태). 넘어간 것은 `AppEnvironment.launchWarnings`에 모아 `AppLog.warning`(표준 오류)으로 남긴다. 읽지 못한 노트 파일도 같은 방식으로 남기고 건너뛴다.
- `AppDelegate`: 앱이 앞으로 올 때 `notes.refresh()`를 부른다. 끝낼 때(`applicationShouldTerminate`) `flushPendingSaves()`를 부르고, 못 쓴 노트가 있으면 노트 이름과 까닭을 알림으로 보여 주고 돌아갈지 저장하지 않고 끝낼지 묻는다(`UnsavedNotesAlert`).
- 켤 때 `NotePanelCoordinator.restoreOpenNotes()`로 지난번에 떠 있던 노트 창을 되살린다. 되살린 것이 없으면 가장 최근에 고친 노트를, 노트가 하나도 없으면 빈 노트를 새로 만들어 띄운다(D-017). Dock 아이콘을 눌렀을 때도 같다.
- 앱 메뉴(`MainMenu`)에는 글을 쓰는 데 필요한 것만 있다: 편집(실행 취소, 오려두기, 복사, 붙여넣기, 모두 선택), 새 노트, 창 닫기, 종료. 메뉴 막대 아이콘과 단축키 표는 4단계에서 만든다.
- Features 타깃 `Editor`, `Capture`, `Browse`는 자리표시(`<모듈>Module`)만 있다. `Editor`는 `Theme`, `Models`에만 의존한다. `Library`, `Reminders`, `Settings`, `Agent`는 아직 타깃이 없다.

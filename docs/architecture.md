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
한 기능이 다른 기능을 열어야 하면(예: 노트 창에서 에이전트 창 열기) Core에 정의한 프로토콜을 통해 요청하고, App이 연결한다.

## 모듈

| 계층 | 모듈 | 책임 | 명세 |
| --- | --- | --- | --- |
| Core | `Theme` | `tokens.json` 읽기, 라이트, 다크, 사용자 테마 덮어쓰기, 글꼴 등록 | 03 |
| Core | `SpaceIcons` | 스페이스 아이콘의 공용 AppKit, SwiftUI 표시, GIF 재생, 이미지 가져오기. Theme, Models만 참조 | 10, 16, 18 |
| Core | `DateTime` | 캡처, 본문, 제목 공용 날짜 읽기, UTF-16 인식 범위, InlineDateProposal, Acceptance, Effect. Models만 참조 | 07a |
| Core | `MarkdownSyntax` | 편집기, 라이브러리와 Theme의 제안 본문이 함께 읽는 줄, 인라인 서식과 숨김 범위. Foundation만 참조 | 06, 09 |
| Core | `Models` | 노트, 스페이스, 리마인더 같은 값 타입 | |
| Core | `Scheduling` | CalendarBridge, ReminderNotifier, 지연 EventKit, 직렬 양방향 동기화. Models, Store, DateTime, MarkdownSyntax만 참조(블록 원문으로 예정 연결, D-313) | 21 |
| Core | `Store` | 노트 파일 읽기, 쓰기, 변경 감시. 저장 방식이 바뀌어도 이 모듈만 바뀐다 | decisions D-003 |
| Core | `AgentRunner` | 구독 CLI 탐색, 전용 로그인, 격리된 자식 실행과 로컬 사용량 기록. Store의 경로 계약을 사용 | 11 |
| 실행 파일 | `FloatMCP` | 노트는 읽기만 하는 stdio MCP 서버. 대화 요청은 실행 전용 접수 폴더에만 제안을 쓴다. Models의 접수 값과 지문을 공유한다 | 11 |
| Core | `Routing` | 기능 사이 요청을 전달하는 프로토콜 | 04 |
| Features | `NotePanel` | Float 창, 상단 줄, 호버 동작 | 05 |
| Features | `Editor` | TextKit 2 마크다운 편집기. 창과 무관하게 단독으로 쓸 수 있어야 한다 | 06 |
| Features | `Capture` | 빠른 캡처 바 | 07 |
| Features | `Browse` | 노트 찾기 | 08 |
| Features | `Library` | 라이브러리, 스페이스 아이콘 고르기 | 09, 10 |
| Features | `Reminders` | 리마인더 설정, 표시, 알림 | |
| Features | `FloatSettings` | 테마 설정, 단축키 표 | 12, 13 |
| Features | `Agent` | 노트별 에이전트 창, 초안과 닫기. Models, Store, Routing, Theme에만 의존한다 | 11 |

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
└─ Resources/         tokens.json, Fonts/, AppIcon.appiconset, menubar-icon.pdf, Info.plist
scripts/
├─ build-app.sh       빌드해서 ${FLOATING_NOTES_APP_DIR:-build}/Float.app 을 만든다 (인자: debug|release, 기본 release)
├─ run.sh             빌드 뒤 실행. 인자는 앱에 그대로 넘긴다
├─ install-app.sh     릴리스로 빌드해 /Applications(쓸 수 없으면 ~/Applications)에 "Float.app"으로 넣는다. sudo를 쓰지 않고, 실행 중이면 먼저 정상 종료를 요청해 끝날 때까지 기다린다. 설치 후 같은 번들 ID의 이전 이름 묶음을 휴지통으로 옮긴다. FLOATING_NOTES_INSTALL_DIR로 넣을 폴더를 바꾼다
└─ debug-send.sh      실행 중인 디버그 빌드에 확인용 명령을 보낸다 (인자: 출력 폴더, 명령)
```

- Xcode 프로젝트 파일은 없다(D-011). `cd App && swift build`, `swift test`.
- `Sources/Theme/Resources/`의 `tokens.json`, `Fonts`와 `Sources/FloatingNotes/Resources/`의 `menubar-icon.pdf`는 `App/Resources/`를 가리키는 심볼릭 링크다. 정본은 `App/Resources/` 하나다. `.app` 묶음에서는 `Contents/Resources/`에서, `swift run`과 `swift test`에서는 SwiftPM 리소스 번들에서 찾는다.
- 실행 인자(확인용): `--notes-dir <경로>`(그 폴더만 읽고 씀), `--appearance light|dark`, `--menu-bar-icon on|off`(저장된 설정과 상관없이 이번 실행에서 메뉴 막대 아이콘을 보이거나 감춤). 환경 변수 `FLOATING_NOTES_DIR`도 같은 일을 한다.
- 확인용 실행 인자(디버그 빌드에만 있다. `#if DEBUG`로 묶여 릴리스 빌드에는 인자 해석도, 명령을 받는 코드도 들어가지 않는다): `--debug-hover <노트 id>`(그 노트를 마우스가 올라간 모습으로 띄움), `--debug-control <출력 폴더>`(다른 프로세스가 분산 알림 `local.floating-notes.debug`로 보내는 명령을 받음. 명령 목록은 `DebugControl.swift`의 주석). 마우스와 키보드를 건드리지 않고 창 상태를 바꾸고 읽을 때 쓴다.
  - 분산 알림은 이 Mac의 어느 프로세스나 보낼 수 있으므로 두 가지로 막는다. 명령마다 이번 실행의 표가 있어야 한다(켤 때 새로 만들어 `<출력 폴더>/control-token`에 소유자만 읽게 적는다. 알림의 `object`는 `<표> <명령>`). 명령이 쓰는 파일(`snapshot`, `menu`, `dump`)은 출력 폴더 바로 아래의 파일 이름으로만 받는다(경로, `..`, 폴더 밖을 가리키는 링크는 거부).
  - 자동 확인 실행에는 `--debug-passive`(노트 창이 어떤 경우에도 키 창이 되지 않음. 새 노트처럼 커서를 두는 동작도 키 창을 만들지 않는다), `--debug-no-hotkeys`(전역 단축키를 등록하지 않음), `--menu-bar-icon off`(메뉴 막대 아이콘이 켜고 끌 때마다 나타났다 사라지지 않게)를 함께 준다. 앱은 `open -g -n build/Float.app --args …`로 켠다(앞으로 가져오지 않음). 키 창을 봐야 할 때만 `click <id>`(이 앱의 이벤트 줄에만 넣는 누름)나 `focus <id>`로 키 창을 만들고 곧바로 `unfocus`로 물린다. 그 사이에는 사용자가 치는 글자가 그 노트로 들어간다. 테스트의 조립(`NotePanelFixture`, `AppFixture`)도 `allowsKeyWindows`를 끈다.
  - 창 밖에 그려지는 것(그림자, 모서리)은 `backdrop light|dark|stripes <파일>`로 노트 뒤에 불투명한 창을 깔고 그 안쪽만 `screencapture -R`로 찍어 본다. 확인용 노트는 화면 구석(있으면 보조 화면)에 두고, 깐 창은 찍는 동안만 둔다.
  - 보내기: `scripts/build-app.sh debug`로 만든 묶음을 `--notes-dir <폴더> --debug-control <출력 폴더>`로 켜고 `scripts/debug-send.sh <출력 폴더> dump state.json`처럼 보낸다.

## 빌드 설정

- Swift 6 언어 모드(엄격한 동시성 검사), swift-tools-version 6.2, macOS 26 이상, 외부 의존 없음.
- Features와 App 타깃은 기본 격리가 MainActor다(`.defaultIsolation(MainActor.self)`). AppKit, SwiftUI 코드에 `@MainActor`를 일일이 붙이지 않는다. 메인 밖에서 돌릴 코드만 `nonisolated`로 표시한다.
- Core 타깃은 기본 격리가 없다. 값 타입은 `Sendable`이고, 상태를 가진 클래스(`Theme`, `FileNoteStore` 등)에만 `@MainActor`를 붙였다.
- 테스트는 Swift Testing(`import Testing`)으로 쓴다.
- 앱 묶음은 `scripts/build-app.sh [debug|release]`가 만들고 `FLOATING_NOTES_APP_DIR`로 출력 폴더를 분리한다.
- 로컬 고정 서명(D-063): 사용자가 `scripts/create-signing-identity.sh`를 한 번 실행해 로그인 키체인에 `Float Local Code Signing` 자체 서명 인증서(3,650일, EKU codeSigning)를 만든다. 기존 인증서는 바꾸지 않고 개인 키 임시 파일은 종료 시 지운다. `security import -T /usr/bin/codesign`으로 해당 키 접근을 허용하며 신뢰 설정과 다른 키의 ACL은 바꾸지 않는다.
- 빌드 서명 우선순위는 `FLOATING_NOTES_SIGN_IDENTITY` → 키체인의 위 identity → 경고 후 임시 서명(`-`)이다. 명시한 identity의 실패는 숨기지 않는다. 자체 서명은 신뢰되지 않아도 사용할 수 있으므로 `security find-identity`에 `-v`를 붙이지 않는다. 생성, 빌드는 `FLOATING_NOTES_KEYCHAIN`으로 임시 키체인을 지정할 수 있고 검색 목록은 바꾸지 않는다.
- Hardened Runtime은 켜지 않는다. 켜면 EventKit 캘린더 접근에 `com.apple.security.personal-information.calendars` 엔타이틀먼트가 필요하다. 고정 인증서로 지정 요구사항을 유지하지만 실제 TCC 권한 유지는 6단계에서 권한 요청과 함께 확인한다.

## Core 공개 API

기능 모듈은 아래만 보고 만든다. 자세한 것은 각 타입의 문서 주석에 있다.

### 에이전트 창과 저장

FloatingNotes가 노트의 얼굴과 키 창의 ⌘J를 `.openAgentWindow(NoteID)`로 연결한다. NotePanel은 노트의 현재 제목과 화면 배치를 제공하고 AppRouter가 Agent에 넘긴다. AgentWindowCoordinator는 노트마다 열린 창을 재사용하고, 빈 창은 첫 편집 전까지 메모리에만 둔다.

Models의 AgentConversation과 AgentProposal은 실행기와 독립된 Codable 값이다. Store의 AgentStore는 상태 폴더 아래 `agent/conversations/<UUID>.json`과 UTF-8 `agent/instructions.md`를 원자 교체한다. 대화는 버전 1이며 대상 노트는 ID로 식별한다. 읽을 수 없는 파일은 보존하고 경고를 남긴다. 요청 전 초안은 대화 목록에서 제외한다. Models의 ConversationDay가 활동 시각을 현지 날짜로 묶고 Theme의 ConversationHistoryList를 Agent와 Library가 공유한다. App이 대화 ID로 같은 AgentDraft를 다시 연다. 선택, 열람, 다음 턴 전송은 별개이며 열람 시각 seenAt은 목록 순서를 바꾸지 않는다. 과거 버전 1 파일에서 빠진 seenAt은 비어 있는 값으로 읽는다. 대화 파일에는 표시된 요청과 답을 보관하며 사용량 파일, 제공자 연결 자료와 저장 위치가 다르다.

App의 AgentCorner는 대화에서 노트별 얼굴을 계산해 NotePanel에 전달하고 마지막으로 사용한 Float 창의 화면에 구석 패널 하나를 배치한다. 화면 변경 시 사용 가능 영역을 다시 읽고 그 화면이 사라지면 주 화면으로 옮긴다.

할 일 제안의 식별자와 상태는 요청의 proposals에 저장한다. FloatMCP와 Store가 공유하는 TodoSubmission은 대상, 줄 목록, 접수 당시 파일 지문이다. AgentRequestCoordinator가 정상 종료 때만 ProposalInbox를 읽는다. FileNoteStore는 Models의 TodoAppender로 예상 원문을 만들고 실제 파일 지문을 확인한 뒤 접미부를 바꾼다. 받기와 되돌리기 직전에 AgentDraft가 미완료 연산과 영수증을 대화에 저장한다. 재시작하면 전후 지문으로 상태를 복구하고 다른 내용은 보존한다. App의 TodoProposalController가 노트 카드, 대화와 Library의 동작을 연결한다. NotePanel은 창 수명만 알리고 기능 모듈끼리 참조하지 않는다.

### AgentRunner와 FloatMCP

- 연결 화면은 `AgentConnection(provider:location:)`에서 `discover()`로 CLI, 버전, Codex용 node를 찾는다. `account(_:)`는 로그인 여부와 CLI가 제공한 계정 정보만 읽는다. `loginCommand(_:)`는 실행 파일, 인자, 환경, cwd만 반환한다. 로그인 시작은 연결 화면의 명시적 동작이다. waitForLogin()은 기존 프로세스 그룹 실행기를 재사용한다. 디버그의 --debug-agent-bin은 해당 폴더에서만 탐색하며 --debug-passive도 실제 CLI로 폴백하지 않는다.
- 읽기 실행은 `AgentRunner(location:server:)`에서 `run(_:engine:installation:timeout:onEvent:)`를 호출한다. 서버의 기본 위치는 앱의 보조 실행 파일이다. `AgentEvent`는 시작, 본문, 도구 호출, 사용 한도, 사용량을 전달한다. 완료 값은 본문, 확인된 모델, 사용량이다. Swift Task를 취소하면 실행기가 만든 프로세스 그룹을 종료한다.
- `AgentEngine`은 Claude 별칭, Codex 모델명, API 키 공급자를 구분한다. `APIKeyStoring`의 기본 구현 `KeychainAPIKeyStore`는 공급자별 일반 암호를 읽고 갱신하고 삭제한다. G0에서 API 엔진을 실행하면 `unsupportedEngine`을 반환한다.
- `FloatMCP <노트 폴더> [실행 전용 접수 폴더]`는 한 줄에 JSON-RPC 메시지 하나를 읽고 응답한다. `list_notes`는 최근 수정 순으로 노트의 메타 정보를 나누어 반환한다. `read_note`는 같은 메타 정보와 머리를 포함한 UTF-8 원문을 구분한다. 파일 해석은 Store의 노트 코덱을 공유한다. 목록에 숨김 파일, 링크, 폴더를 넣지 않으며 읽을 때도 같은 조건을 검사한다.

### Theme

- `NoteDisplayOptions`, `ReminderPresentation`, `BellRing`: 노트 상단과 라이브러리가 공유하는 리마인더 표시 설정, 포맷, 상태, 움직임. `NotePanelDisplayOptions`는 호환 타입 별칭이다(D-066). 기능 모듈 간 참조는 추가하지 않는다.

- `Theme` (`@MainActor @Observable`): `Theme.bundled(overrideStore:appearance:)`로 만든다. App이 하나 만들어 넘긴다. SwiftUI는 `@Environment(\.theme)`로도 받는다.
  - 색: `color(_: ColorToken) -> Color`, `nsColor(_:) -> NSColor`(둘 다 뷰의 라이트, 다크를 스스로 따라감), `rgba(_:) -> RGBA`(지금 모양의 값), `noteBackgroundColor(paletteID:)` / `noteBackgroundNSColor(paletteID:)`, `shadow(_: ShadowToken) -> [ShadowLayer]`
  - 글꼴: `font(_: TextStyle, size:weight:) -> Font`, `nsFont(_:size:weight:) -> NSFont`, `lineHeight(_:)`, `tracking(_:)`. `TextStyle`은 spec 3.1 표의 줄(`.title .h1 .h2 .h3 .body .strong .paneTitle .row .rowSub .ui .micro .code .capture`)
  - 치수: `space(_: SpaceToken)`, `shape(_: ShapeToken)`, `component(_: ComponentToken)`, `docPadding`, `material`(opacity, blur, tintMix, tintMixRow), `motion`(duration, curve, `.animation`, `.timingFunction`), `palette`, `accentPresets`
  - 형광펜: `HighlightColor`(`.yellow=1 .gray .rose .blue`, 번호는 D-008의 `{n}`) → `.background`, `.foreground`가 `ColorToken`
  - 상태: `appearance`, `tokens`, `overrides`, `setOverrides(_:) throws`(잘못된 키, 값이면 던지고 아무것도 바꾸지 않음), `followAppearance(of: NSApplication)`, `loadWarnings: [String]`. AppKit 쪽은 `Theme.didChangeNotification`을 받아 다시 그린다.
  - 저장된 덮어쓰기를 읽을 때는 던지지 않는다. 없어진 키나 잘못된 값은 버리고, 깨진 파일은 `theme-overrides.json.corrupt`로 옮긴 뒤 기본 테마로 시작하며, 버린 것을 `loadWarnings`에 적는다.
- `ThemeTokens` (`Sendable` 값): `tokens.json`을 푼 것. `Theme` 없이 쓸 수 있다. `color(_:_:)`, `textStyle(_:)`, `noteBackground(paletteID:_:)`, `rowTint(paletteID:)`, `applying(_: ThemeOverrides) throws`(엄격), `applyingValid(_:) -> (tokens, accepted, rejected: [ThemeError])`(쓸 수 있는 것만 얹음).
- 토큰 값 검증: 수는 십진 표기만 받는다(`nan`, `inf`, `0x10`, `1e3` 거부). 글자 크기, 줄 높이는 0보다 커야 하고, 간격, 모서리, 치수, 여백, 흐림은 0 이상, 굵기는 1~1000, 불투명도는 0~1, 섞는 비율은 0~100%여야 한다. `tokens.json`과 덮어쓰기에 똑같이 적용된다.
- `TextInputPolicy.apply(to:)`: AppKit 입력의 자동 변경, 완성, 예측을 끄고 조합 장식을 숨긴다. `PlainTextInputCell`은 제목, 스페이스 이름, 일정 입력칸의 재사용 필드 편집기에 매번 적용한다. Features가 Core의 이 정책을 함께 사용한다(D-057).
- `ThemeOverrides`: `[구역.키: 값]` 사전. 키 예 `color.light.accent`, `type.fs-body`, `palette.tint-1`. 값 표기는 `tokens.json`과 같다. `ThemeOverrideStore(url:)`가 JSON 파일로 읽고 쓴다(`stateDirectory/theme-overrides.json`).
- `TransitionTimer.after(_ duration:, _ work:) -> Task<Void, Never>?` (`@MainActor`): 전환이 끝날 때 해야 하는 일을 전환 시간 뒤에 잡는다. 시간이 0이면("동작 줄이기") 그 자리에서 하고 `nil`을 돌려주며, 돌려받은 것을 취소하면 하지 않는다. 움직임이 끝났다는 알림에 상태를 걸지 않기 위한 한 곳이다(아래 "그 밖"의 "움직임과 상태").
- 입력 커서(D-042). 시스템의 커서 표시(`NSTextInsertionIndicator`)는 너비와 높이를 정할 수 없어 쓰지 않고, 텍스트 뷰 위에 작은 뷰 하나로 얇은 커서를 그린다.
  - `TextCaret` (`@MainActor`): `init(textView: NSTextView, theme: Theme)`. 너비 `caret-w`, 색 `accent`, `motion.caretBlink`마다 깜빡임. `rectProvider: (() -> NSRect?)?`(커서 자리의 글꼴 상자, 텍스트 뷰 좌표. `minX`가 글자 경계. 없으면 `defaultRect()`: `firstRect(forCharacterRange:)`의 줄 가운데에 입력 속성 글꼴의 ascender부터 descender까지), `refresh(restartBlink:focused:)`, `reposition()`, `forcesVisible`(키 창이 아니어도 보임. 확인용), 읽기: `isActive`, `frame`, `isBlinkedOff`, `color`. 선택, 글자, 틀, 키 창, 테마가 바뀌는 것은 스스로 듣는다. 텍스트 뷰는 `shouldDrawInsertionPoint`를 `false`로 덮어쓰고, `becomeFirstResponder`와 `resignFirstResponder`에서 받아들였는지를 `refresh(focused:)`로, `setMarkedText`와 `unmarkText` 뒤에 `refresh()`, `layout()` 뒤에 `reposition()`을 부른다. 편집기는 `EditorTextView`가 이것을 들고, 자리는 `EditorController+Caret`이 TextKit 2에서 잰다.
  - `ThinCaretFieldEditor` (`NSTextView` 하위 클래스, `open`): `init(theme:)`. `NSTextField`가 쓰는 필드 편집기. 위의 호출을 이미 하고 `caret`을 든다.
  - `CommandInputField` (`NSTextField` 하위 클래스, `open`): `init(theme:editor:)`. 칸마다 `commandEditor`(`ThinCaretFieldEditor`)를 들고, 셀(`PlainTextInputCell`)의 `fieldEditor(for:)`가 그것을 돌려주므로 창 대리자 없이 얇은 커서를 쓴다. 노트 제목 칸(`TitleField`)은 #34부터 이것의 하위 클래스다(D-132). SwiftUI 화면은 같은 구현의 `CommandTextField`를 쓴다. 시스템 커서에 색만 바꾸는 곳은 편집기를 못 만들 때의 `PlainTextBodyEditor` 하나가 남았다.
- `FontRegistrar.registerBundledFonts() -> FontRegistration`(`registered: [URL]`, `problems: [String]`): App이 켤 때 부른다. 던지지 않는다. 등록하지 못한 글꼴은 `problems`에 적히고 글꼴 고르기는 시스템 글꼴로 넘어간다. 기능 모듈은 부르지 않는다.
- 글꼴 고르기: 가족 이름은 `<이름> Variable`(번들의 가변 글꼴)을 먼저 찾고 그다음 `<이름>`을 찾는다. 가변 글꼴은 굵기 축에 토큰 값을 그대로 넣고, 굵기별 파일로 된 가족은 CSS 굵기가 가장 가까운 파일을 고른다.
- 새 토큰을 쓰려면 `tokens.json`에 값을 넣고 `TokenKeys.swift`의 enum에 case를 더한다. 테스트가 파일과 enum이 어긋나면 실패한다.
- 노트 창 단계에서 더한 토큰(시안의 CSS에만 있던 값): `component`의 `chrome-gap`, `chrome-pad-end`, `icon-s|m|l`(12, 13, 14), `icon-btn-gap`, `swatch-size|gap|ring`, `menu-w`, `note-w`, `note-w-min`, `note-w-max`와 `type.fw-ui-strong`(`TextStyle.uiStrong`, 임박한 리마인더).
- 캡처 바와 노트 찾기 단계에서 더한 토큰(D-028): `component`의 `capture-w|h|pad|gap|val-gap|rise`, `browse-pad|r|find-h|find-gap|gap|anchor-gap|anchor-inset`과 몫으로 적는 `capture-bottom-screen`, `browse-top-screen`, `browse-h-max-screen`(`RatioToken`).
- 치수가 아닌 값: `component.note-h-max-screen`(`70%`, 노트 높이 한도)은 `RatioToken`으로 받아 `ratio(_:)`가 0~1의 몫으로 낸다. `component.note-body-lines-min`(`4`, 노트 본문 영역이 적어도 보이는 줄 수, D-031)은 `CountToken`으로 받아 `count(_:)`가 1 이상의 정수로 낸다(단위 없는 정수만 받는다). `motion` 구역의 키는 `MotionToken`에 있고 값은 `MotionTokens`로 묶여 나온다: `duration`, `curve`와 `bell: BellMotion`(`bell-period` 1.6s, `bell-rest` 60%, `bell-angle-1|2|3` 14deg, -12deg, 6deg, `bell-pivot` 12%, `bell-ease`. `keyframes`가 주기 안의 때와 각도를 낸다).

### Models

- `Note`: `id: NoteID`, `title`, `body`(Markdown 원문), `spaceID: SpaceID?`, `colorID: PaletteID?`, `schedules: [ScheduleItem]`, 호환용 `reminder: Date?`, `created`, `modified`. 핀은 없다(아래).
- `NoteDraft`: 새 노트 내용(`title`, `body`, `spaceID`, `colorID`, `schedules`, 호환용 `reminder`).
- `NoteWindowState`: `frame: WindowFrame?`, `isPinned`(기본 켜짐), `isOpen`, `stackOrder: Int?`(창이 겹친 차례. 앞으로 올 때마다 가장 큰 값보다 하나 큰 값, 클수록 앞), `foldedLines: [Int]?`(접어 둔 토글의 줄 번호, 오름차순. 없으면 `nil`. App의 편집기 어댑터가 적는다, D-023), `lastOpened: Date?`(사용자가 그 노트의 창을 마지막으로 띄웠거나 키 창으로 만든 때. 노트 창이 적고 노트 찾기가 읽는다, D-033). 노트 파일이 아니라 로컬 상태다(D-003). 항목마다 주인이 다르므로 고칠 때는 지금 값을 읽어 제 항목만 바꿔 넣는다(`WindowStateRecorder`, `NoteFoldStore`가 그렇게 한다).
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
  - `hasPendingChanges(_ id: NoteID) -> Bool`: 아직 디스크에 쓰지 않은 변경이 있는지(저장 실패, 충돌, 없어진 파일 때문에 남은 것 포함).
  - `discardPendingChanges(_ id: NoteID)`: 쓰지 않은 변경을 버린다. 알리지 않는다. 파일이 없어진 노트를 정리할 때 쓴다(파일이 남아 있는 노트의 충돌은 `resolveConflict(.disk)`).
  - `moveToTrash(_ id: NoteID) throws`, `restoreFromTrash(_ id: NoteID) throws -> Note`.
  - `delete(_ id: NoteID) throws`: 휴지통을 거치지 않고 노트 폴더의 파일을 지운다. 미뤄 둔 변경을 버리고 `.removed`/`.local`로 알린다. 아무것도 적지 않은 노트(`Note.isBlank`)를 치울 때만 쓴다(D-040). 파일이 없으면 `noteNotFound`.
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
- 다른 프로그램이 지운 파일:
  - `.removed`/`.external`이 온다. 쓰지 않은 변경은 버리지 않고 저장소에 남긴다(`hasPendingChanges`, `load`가 돌려준다). 그 노트를 쓰려 하면 `noteNotFound`이고 파일을 만들지 않는다. 남은 변경은 보여 주는 쪽이 `create`로 새 노트에 옮기거나 `discardPendingChanges`로 버린다.
  - 자동 저장을 쓰려는 때에 파일이 없으면 `.saveFailed`가 아니라 `.removed`/`.external`로 알린다(폴더를 훑다가 이미 알렸으면 다시 알리지 않는다).
  - 같은 이름의 파일이 다시 생기면 `.created`/`.external`이 온다. 남아 있던 변경을 쓰려 할 때 내용이 예전과 다르면 `conflict`다.
- `StoreChange`: `id`, `kind`(`.created .updated .removed .saveFailed(message:) .conflict`), `origin`(`.local` 이 앱, `.external` 다른 프로그램). `.saveFailed`와 `.conflict`는 미뤄 둔 저장에서만 오고, 고친 내용은 저장소에 남아 있다. 이 앱이 한 쓰기는 모두 `.updated`/`.local`로 알려지므로, 받는 쪽은 `origin`으로 제 저장의 메아리와 다른 프로그램의 변경을 가른다.
- `StoreError`: `.noteNotFound(id)`, `.noteAlreadyExists(id)`, `.unreadableFile(url)`, `.conflict(id)`, `.writeFailed(id, message:)`, `.pendingSavesFailed([SaveFailure])`.
- `StoreLocation`: `notesDirectory`, `trashDirectory`(`notes/.trash/`), `stateDirectory`. `.standard()`는 `~/Library/Application Support/FloatingNotes/{notes,state}`, `.isolated(notesDirectory:)`는 그 폴더 안만 쓴다.
- `WindowStateStore`: `init(location:writeDelay:)`, `state(for:)`, `set(_:for:)`, `remove(_:)`, `all`, `flush() throws`, `onWriteFailure`, `writeCount`, `loadWarning: String?`, `observe(_:) -> StoreObservation` → `stateDirectory/windows.json`.
  - 값은 메모리에서 곧바로 바뀌고(`state(for:)`, `all`, `observe`가 그것을 본다) 파일에는 마지막 변경 뒤 `writeDelay`가 지나면 그사이의 변경을 한 번에 쓴다(D-033). 창 하나를 띄우거나 키 창이 될 때마다 잇달아 오는 변경(틀, 겹친 차례, 연 때)이 파일 전체를 여러 번 다시 쓰지 않는다. 기본값 0은 바꿀 때마다 곧바로 쓰고 실패를 그 자리에서 던진다(테스트, `Stage4Demo`). App은 `coalescingWriteDelay`(0.3초)를 주고, 끝낼 때와 파일을 직접 읽는 쪽이 지금 값을 봐야 할 때 `flush()`를 부른다. 미뤄 둔 쓰기가 실패하면 `onWriteFailure`로 알리고 값은 남겨 두었다가 다음 변경이나 `flush()` 때 다시 쓴다.
- `SpaceStore`: `spaces`, `space(for:)`, `replace(with:)`, `loadWarning: String?`, `observe(_:) -> StoreObservation` → `stateDirectory/spaces.json`.
- 두 저장소의 `observe`는 값이 실제로 바뀌면 인자 없는 클로저를 부른다(D-033. `SpaceStore`는 파일에 쓴 뒤에, `WindowStateStore`는 메모리의 값이 바뀐 때에. 쓰기를 미루는 동안에도 받는 쪽은 지금 값을 읽는다). 무엇이 바뀌었는지는 싣지 않으므로 받는 쪽이 지금 값을 다시 읽는다. 값이 그대로인 `set`, `replace`는 쓰지도 알리지도 않는다. 돌려받은 `StoreObservation`을 들고 있는 동안만 알림이 온다(노트 저장소의 `observe`와 같다).
- 두 상태 파일이 깨져 있으면(잘림, 모양 다름) 지우지 않고 `<이름>.corrupt`(이미 있으면 `.corrupt-2`…)로 옮긴 뒤 빈 상태로 시작하고 `loadWarning`에 적는다.
- 노트 파일은 `<id>.md`. 머리는 `title`(따옴표 문자열), `space`, `color`, `reminder`, `created`(ISO 8601, UTC, 초 단위)이고 닫는 `---` 다음 글자부터 끝까지가 본문 그대로다. 머리 없는 `.md`도 읽는다.
  - 아는 항목은 들여쓰기 없이 줄 맨 앞에서 시작하는 다섯 키뿐이다. 들여쓴 줄과 모르는 줄은 저장해도 그대로 남는다.
  - 이미 있는 파일을 고쳐 쓸 때는 값이 바뀐 항목의 줄만 새로 적는다. 값이 그대로인 줄(손으로 적은 표기, 초 아래 자리가 있는 날짜, 읽지 못한 날짜)과 줄 순서, 줄바꿈 종류, 맨 앞의 BOM은 그대로 둔다. `created` 줄은 있으면 언제나 그대로 둔다.
  - 날짜는 ISO 8601로 읽는다. 초 아래 자리(`…00.123Z`)와 날짜만 있는 값(`2026-11-17`, UTC 자정)도 받는다. 읽지 못한 `reminder`는 리마인더 없음으로 읽히고, 리마인더를 새로 정할 때만 그 줄이 바뀐다.

### Routing

- `Route`: `.openNote(NoteID)`, `.newNote(NewNoteRequest)`, `.closeNoteWindow(NoteID)`, `.openCapture`, `.openBrowse(anchor: NoteID?)`, `.toggleAllNotesHidden`, `.openLibrary`, `.openAgentWindow(NoteID)`, `.requestAgent`, `.openSettings`, `.openShortcuts`, `.openReminderEditor(NoteID)`, `.openSpacePicker(NoteID)`.
- `Routing` (`@MainActor` 프로토콜): `route(_: Route) -> RouteResult`(`@discardableResult`), `isConnected(_: Route) -> Bool`. 기능 모듈은 `any Routing`을 받아 부르기만 한다. SwiftUI는 `@Environment(\.router)`.
  - `RouteResult`: `.handled`(그 일을 했다), `.failed`(하려 했으나 하지 못했다. 사용자에게 알리는 일은 받은 쪽이 이미 했고, 알림 창이 닫힌 뒤에 돌아온다), `.unconnected`(그 화면이 아직 이어져 있지 않다). 보낸 쪽은 이 답으로 닫을지, 적던 글을 둘지, 포커스를 돌려줄지 정한다(D-034).
  - `isConnected(_:)`: 그 요청을 받는 화면이 이어져 있는지. 기능 모듈은 이어지지 않은 요청을 보내는 줄을 내놓지 않거나(노트 찾기의 "라이브러리 열기") 고를 수 없게 둔다(노트의 더 보기 메뉴).
- `RouteDispatcher(handler:)`: 클로저로 받는 기본 구현(모든 요청이 이어져 있고 `.handled`로 답한다. 테스트용으로도 쓴다). 답과 이어짐을 정하려면 `RouteDispatcher(isConnected:answering:)`.

## NotePanel 공개 API

Float 창(spec 04, 05, 19). Core 모듈만 import하고, 다른 기능은 `Routing`으로만 부른다.

- `NotePanelCoordinator`: 떠 있는 노트 창 전부를 맡는다. App이 하나 만든다.
  - `init(theme:notes:windowStates:spaces:router:makeBodyEditor:log:)`. `makeBodyEditor`를 주지 않으면 기본 편집기(`PlainTextBodyEditor`)를 쓴다.
  - `restoreOpenNotes() -> [NoteID]`(지난번에 떠 있던 창을 제자리에, 겹친 앞뒤도 그대로. 뒤에 있던 것부터 띄우고 그 차례로 돌려준다), `open(_:nextTo:focus:) throws`, `createNote(_: NewNoteRequest) throws -> NoteID`(지금 노트 옆에 핀이 켜진 채), `closeWindow(_:)`(창만 내림), `moveToTrash(_:)`, `toggleAllHidden()`, `areNotesHidden`.
  - 숨김은 전부 아니면 전무다. 숨긴 중에 `open`, `createNote`, `focusBody(of:)`, `popUpMoreMenu(for:)`를 부르면 숨김이 모두 풀린다(뒤에 있던 창부터 띄워 앞뒤를 지키고, 마우스가 올라가 있는지도 다시 잰다). `areNotesHidden`이 참이면 보이는 노트 창이 없다.
  - 창마다: `openNoteIDs`, `keyNoteID`(키 창인 노트), `frontmostNoteID`(키 창인 노트, 없으면 보이는 것 가운데 가장 앞에 겹친 노트), `window(for:) -> NSWindow?`(다른 화면을 그 노트에 붙일 때), `snapshot(of:) -> NoteWindowSnapshot?`(틀, 핀, 창 단계, 보임, 호버), `setPinned(_:for:)`, `setColor(_:for:)`, `focusBody(of:)`, `focusNextNote()`(띄운 순서로 다음 노트, 끝에서 처음으로), `focusFrontmostNote()`(키 창인 노트가 없으면 보이는 노트 가운데 가장 앞의 것을 키 창으로. App이 앱이 앞으로 왔을 때 부른다), `returnKey(to:) -> Bool`(키 창을 잠깐 가져갔던 캡처 바나 노트 찾기가 닫힐 때 App이 부른다. 그 노트가 다시 키 창이 되고 커서 자리는 그대로이며, 휴지통 되돌리기는 끝나지 않는다. 그 노트가 떠 있지 않거나 숨긴 중이면 아무것도 하지 않는다), `beginTitleEditing(for:)`, `popUpMoreMenu(for:)`, `setHoverOverride(_:for:)`(확인용).
  - 마지막으로 연 때(D-033): 사용자가 노트 창을 띄울 때(`open`, 새 노트, 노트 찾기에서 고름)와 그 창이 키 창이 될 때 `NoteWindowState.lastOpened`에 지금 시각을 적는다(겹친 차례와 한 번에 쓴다, `WindowStateRecorder.recordFronted(_:openedAt:)`). 켤 때 되살린 창과 "모두 보이기"로 돌아온 창은 적지 않는다.
  - 확인용으로만 쓰는 것은 `@_spi(Verification)` 뒤에 있다(편집기와 같다): `allowsKeyWindows`(끄면 노트 창이 키 창이 되지 않는다), `releaseKeyWindow()`(키 창인 노트 창을 물린다), `now`(지금 시각을 바꿔 끼운다). `@_spi(Verification) import NotePanel`로 들여와야 보이고, 앱에서는 디버그 빌드의 `DebugControl.swift`만 그렇게 한다.
  - 키 창과 앱 활성화(D-025의 4번, 사용자 결정): 노트 창은 보통 앱 창처럼 누르면 앱이 앞으로 온다(`.nonactivatingPanel`이 아니다). 앱이 뒤로 가도 숨지 않고(`hidesOnDeactivate` 끔) 모든 Spaces와 전체 화면 앱 위에 보인다. 키 창은 앱이 앞에 있을 때만 키 입력을 받으므로 `NotePanelWindow.canBecomeKey`는 확인용 스위치(`allowsKey`)만 본다. 다른 앱의 입력을 가져오지 않는 일은 앱을 앞으로 가져오는 쪽이 지킨다: 켤 때 되살린 창, `focus: false`로 띄운 창, 모두 보이기, 호버는 앱을 앞으로 가져오지 않고 키 창도 시키지 않는다. 사용자가 노트를 누를 때(버튼 누름은 `noteButtonPressed()`가 `activateApp`을 부른다)와 App이 사용자의 요청으로 노트를 열거나 만들 때(`AppRouter.activateApp`)만 앞으로 온다. 앱이 시켜서 키 창이 되는 때: `focusBody`, `beginTitleEditing`, `focusNextNote`, 새 노트, `open(_:focus: true)`, 휴지통에서 되살리기, 키 창이던 노트가 내려가 보이는 노트 가운데 가장 앞의 것이 이어받음(`KeyHandoff`. 남은 노트가 없고 휴지통으로 보낸 것이면 ⌘Z를 받도록 앱을 앞으로 가져온다), 사용자가 앱을 앞으로 가져왔는데 키 창이 없음(`focusFrontmostNote()`), 캡처 바나 노트 찾기가 닫히며 돌려줌(`returnKey(to:)`, D-032). 버튼으로 가는 누름은 `NotePanelWindow.sendEvent`가 창의 크기 조절이나 첫 누름 처리보다 먼저 그 버튼(`ClickableView`)에 건네고 뗄 때까지의 이벤트도 그 버튼이 받는다. `ClickableView`는 안의 아이콘이나 글자 대신 통째로 누름을 받고(`hitTest`) 첫 누름을 받는다(`acceptsFirstMouse`, D-039).
  - 크기(D-031): 본문 영역은 적어도 본문 `note-body-lines-min`(4)줄 높이다. 기본은 본문 여섯 줄 높이로 고정한다. 저장 높이가 없는 글에 맞춤 창은 상단 줄 + max(내용 높이, 최소 본문 높이)이고 한도(`note-h-max-screen`, 화면 아래 끝)까지 내용을 따라 는다(`NoteSizePolicy`). 적어 둔 틀이 더 낮은 노트는 위쪽 가장자리를 지킨 채 아래로 늘려 되살린다.
  - 그림자: 투명한 창의 그림자는 내용 모양에서 만들어 두고 다시 쓰이므로 창 크기가 바뀔 때마다(`windowDidResize`) `invalidateShadow()`를 부른다.
  - 휴지통 되돌리기(spec 5.3): `moveToTrash(_:)` 바로 뒤에 `canUndoTrash`가 참이 되고 `undoTrash() throws -> NoteID?`가 노트를 되살려 창 상태(틀, 핀, 접힘)째 다시 띄운다. 다른 노트가 키 창이 되거나 사용자가 노트 창을 누르면(보낸 직후 다음 노트가 키 창을 이어받는 것은 빼고), 글을 고치면(본문, 제목, 색), 새 노트를 만들면 거짓이 된다(D-024). 되살릴 수 없는 실패(`noteNotFound`, `noteAlreadyExists`)를 던질 때도 거짓이 되고, 그 밖의 실패에서는 다시 시도할 수 있게 남는다.
  - 빈 노트(D-040): `closeWindow(_:)`는 아무것도 적지 않은 노트(`Note.isBlank`, 쓰지 못한 글과 풀지 않은 문제 없음)를 창과 함께 `delete`로 지운다. `deleteBlankNotes() -> [NoteID]`는 떠 있는 빈 노트를 지운다(App이 끝낼 때 미뤄 둔 저장을 다 쓴 뒤 부른다).
  - 알림 고리(D-041): `onMovedToTrash: ((NoteID, NSScreen?, CGRect?) -> Void)?`(보낸 노트와 그 창이 있던 화면, 닫기 직전 보이던 창의 틀), `onTrashUndoEnded: (() -> Void)?`(되돌리기가 끝남. 되살렸거나 "바로 뒤"가 지남).
  - `flushPendingEdits()`: 떠 있는 모든 창에서 고치던 제목을 마무리하고 편집기가 아직 알리지 않은 본문을 받는다. App이 끝내기 전에 `flushPendingSaves()`보다 먼저 부른다. 창 하나를 닫거나 휴지통으로 보낼 때는 노트 창이 스스로 한다.
  - `displayOptions: NotePanelDisplayOptions`: 스페이스 표시(아이콘, 아이콘+이름, 이름), 리마인더 표시(시간, 남은 시간, 아이콘), 시간 형식, 임박 기준. 설정 화면이 생기면 여기에 넣는다.
- 노트 창이 하는 일과 하지 않는 일:
  - 제목, 노트 색은 `update`/`scheduleUpdate`로 그 항목만 고친다. 핀과 창 틀, 열림 상태는 `WindowStateStore`에 둔다.
  - 노트 찾기, 새 노트, 창 닫기, 리마인더 설정, 스페이스 옮기기, 에이전트 창은 `Route`를 보낸다. 직접 열지 않는다.
  - 저장소 변경을 받는다. 이 앱의 쓰기(`.updated`/`.local`)든 다른 프로그램의 변경(`.updated`/`.external`)이든 `load`로 다시 읽어 `note`와 상단 줄을 맞추고, 본문이 편집기와 마지막으로 주고받은 것과 다를 때만 편집기에 넣는다(아래 "본문 편집기 이음매"). 이 창이 한 저장은 언제나 주고받은 본문과 같아 편집기를 건드리지 않고, 이 앱의 다른 곳이 쓴 본문(빠른 캡처가 덧붙인 줄)만 들어간다. 그때도 `text`에 통째로 넣지 않고 `appendFromOutside`나 `applyOutsideChange(to:)`로 넘긴다.
  - 충돌(`.conflict`)이나 저장 실패가 나면 사용자가 쓴 글을 그대로 두고 상단 줄에 표시 하나를 띄운다. 누르면 내 내용으로 저장 / 파일의 내용으로 되돌리기(`resolveConflict`), 다시 저장을 고른다. "다시 저장"은 이 노트의 실패만 본다(다른 노트의 실패는 기록만 하고, 이 노트가 충돌이면 충돌 표시로 넘어간다). 쓰지 못한 글이 있는 창은 닫지 않는다.
  - 노트가 없어지면(`.removed`): 이 앱이 휴지통으로 보낸 것이면 창을 내린다. 다른 프로그램이 지운 것이면 쓰지 못한 글이나 풀지 않은 표시가 없을 때만 창을 내리고, 있으면 창을 남겨 표시("노트 파일이 없어졌습니다")를 띄운다. 누르면 "새 노트로 저장"(편집기가 아직 알리지 않은 글을 먼저 받고, 지금 제목, 본문, 스페이스, 색, 리마인더로 `create`한 새 노트를 같은 자리와 핀으로 띄우고 옛 창을 내림. 접힘 같은 창 상태도 새 노트로 옮긴다) / "버리기"(`discardPendingChanges` 뒤 창을 내림)를 고른다. 고를 때까지 닫기와 휴지통으로는 창이 닫히지 않는다. 같은 이름의 파일이 돌아오면 남은 변경을 다시 쓰고, 내용이 달라져 있으면 충돌 표시로 넘어간다.
  - 노트 창이 키 창이 될 때 `refresh()`를 부른다(앱이 이미 앞에 있는 채로 다른 노트를 누르면 App의 `refresh`가 돌지 않는다. 파일마다 수정 시각과 크기만 보므로 횟수를 줄이지 않았다).
  - 저장 문제 표시는 호버 아이콘 둘의 왼쪽(제목 쪽)에 놓인다. 나타나고 사라져도 자리를 미리 차지하는 것들은 움직이지 않고 긴 제목이 잘리는 자리만 달라진다. 표시와 리마인더는 알파로 `dur` 동안 나타나고 사라진다. 다 사라진 뒤에 숨기고 자리를 비우는 일은 움직임이 끝났다는 알림이 아니라 `dur` 뒤의 시계(`TransitionTimer`)가 한다. 누를 수 있는 것(`ClickableView`: 아이콘 버튼, 리마인더)은 제 영역의 커서를 화살표로 밝힌다(규칙 9).
- 안쪽 구조: `Logic/`은 화면 없이 시험하는 값 계산(`TopRowState` 상단 줄의 내용과 색, `TopRowLayout` 요소 자리, `ReminderPresentation`, `NoteSizePolicy`, `WindowPlacement`, `HeightTransition`, `WindowStateRecorder`, `KeyHandoff` 창이 내려간 뒤 키 입력을 누가 받을지), `Views/`는 AppKit 뷰, `Menu/`는 더 보기 메뉴, `Body/`는 본문 이음매.

### 본문 편집기 이음매

노트 창은 편집기 모듈을 import하지 않는다. 아래 프로토콜의 구현을 App이 만들어 넘긴다.

```swift
@MainActor public protocol NoteBodyEditing: AnyObject {
    var view: NSView { get }
    var text: String { get set }
    var onTextChange: ((String) -> Void)? { get set }
    var onContentHeightChange: ((CGFloat) -> Void)? { get set }
    func focus()
    func flushPendingChange()
    func appendFromOutside(_ suffix: String)   // 구현하지 않으면 `text += suffix`
    func applyOutsideChange(to newText: String) // 구현하지 않으면 `text = newText`
}
public struct NoteBodyEditorContext { public let theme: Theme; public let noteID: NoteID }
public typealias NoteBodyEditorFactory = @MainActor (NoteBodyEditorContext) -> any NoteBodyEditing
```

- `view`는 노트 창이 가진 스크롤 뷰의 문서 뷰가 된다. 노트 창은 너비만 맞추고, 높이는 `view`가 내용에 맞춘다. 뒤집힌 좌표(`isFlipped`)여야 한다.
- 안쪽 여백(`Theme.docPadding`)은 편집기가 넣는다.
- `onContentHeightChange`에는 여백을 포함한 내용 높이를 넘긴다(글이나 너비가 바뀔 때마다, 처음 배치된 뒤 한 번). 글에 맞춤이고 저장한 높이가 없는 노트 창이 이 값으로 높이를 맞춘다(위쪽 고정, 아래로, `dur` 동안).
- 배치 도중에 알게 된 내용 높이로 창 높이를 바꾸면(창을 처음 띄울 때가 그렇다) 그 배치가 끝나며 "다시 배치" 요청이 지워진다. `NoteRootView.layout()`은 `onLayout` 뒤에 크기가 달라졌으면 한 번 더 놓는다. 이것이 없으면 본문 영역이 옛 창 높이에 머물러 아래가 잘린다.
- `PlainTextBodyEditor(theme:)`: 서식 없는 기본 구현(TextKit 1). 제 실행 취소 기록을 따로 갖는다. `makeBodyEditor`를 주지 않았을 때의 기본값이고 노트 창 테스트가 쓴다. 앱에서는 App 타깃의 어댑터 `MarkdownBodyEditor`가 Editor 모듈을 끼운다.

글을 주고받는 약속(정본은 `NoteBodyEditing`의 문서 주석). 편집 중인 글의 주인은 편집기다. 편집기는 받은 글을 제 표기로 고쳐 보일 수 있고(CRLF를 LF로 등), 밖에서 다른 글을 넣으면 실행 취소 기록을 비우고 조합(한글 입력)을 끊어도 된다. 그래서 노트 창은 꼭 필요할 때만 `text`에 넣는다.

노트 창이 지키는 것:

- 편집기에 글을 넣는 때는 셋뿐이다. (1) 편집기를 만든 직후 한 번. (2) 다른 프로그램이 파일을 고쳤거나 "파일의 내용으로 되돌리기"를 골랐을 때. (3) 이 앱의 다른 곳이 이 노트의 본문을 저장소에 썼을 때(빠른 캡처가 떠 있는 노트에 한 줄을 덧붙임). (2)와 (3)에서는 저장소의 본문이 "편집기와 마지막으로 주고받은 본문"(마지막으로 넣은 값 또는 `onTextChange`로 받은 값)과 다를 때만 넣는다. (3)을 넣지 않으면 편집기가 옛 글을 들고 있다가 다음 입력 때 본문 전체를 옛 글로 덮어써, 덧붙인 줄이 사라진다.
- `text`에 넣는 것은 (1)뿐이다. (2)와 (3)에서는 새 본문이 주고받은 본문의 끝에 글이 붙은 것이면 `appendFromOutside(_:)`로 붙은 글만 넘기고, 아니면(빠른 캡처가 끝의 빈 줄을 걷어 내고 붙인 줄, 다른 프로그램이 고친 파일, "파일의 내용으로 되돌리기") `applyOutsideChange(to:)`로 새 본문을 넘긴다. 어느 쪽이든 주고받은 본문을 새 본문으로 맞춘다. `text`에 통째로 넣으면 편집기의 실행 취소 기록이 비워지고 커서와 접힘을 잃으므로, 달라진 곳만 바꿀 수 있는 편집기가 그 일을 맡게 한다.
- 편집기가 `onTextChange`로 알려 준 글을 되돌려 넣지 않는다. 이 창이 한 저장(자동 저장, 제목과 색 변경, 닫을 때 쓰기, "내가 고친 내용으로 저장", "다시 저장")은 저장소의 본문이 주고받은 본문과 같으므로 편집기를 건드리지 않는다.
- 저장하는 본문은 `onTextChange`로 받은 값 그대로다. 저장하려고 `text`를 읽지 않는다.

편집기가 지켜야 하는 것:

- 사용자가 고쳐 본문 원문이 달라질 때마다 `onTextChange`에 그때의 원문 전체를 넘긴다. 조합 중에는 메인 큐에서 한 차례 늦게 불러도 된다. 노트 창은 받은 값을 `scheduleUpdate(id) { $0.body = text }`로 넘긴다.
- `text`를 밖에서 넣을 때는 `onTextChange`를 부르지 않는다. 넣기 전에 미뤄 둔 알림(옛 글의 것)이 있으면 버린다. 버리지 않으면 방금 받은 글을 옛 글이 덮어쓴다.
- 지금 글과 같은 글을 넣으면 아무것도 하지 않는다(실행 취소 기록과 조합을 그대로 둔다).
- 다른 글을 넣으면 그 글로 바꾸고 실행 취소 기록을 비운다(옛 기록은 새 글에 없는 범위를 가리킨다).
- 받은 글을 제 표기로 고쳐 보이는 것만으로는 `onTextChange`를 부르지 않는다(사용자가 고친 것이 아니다).
- `appendFromOutside(_:)`가 불리면 지금 글의 끝에 그 글을 붙인다. `onTextChange`를 부르지 않되, 아직 알리지 않은 사용자의 변경이 있었다면 버리지 않고 다음에 알릴 때 붙인 글까지 든 원문을 넘긴다. 할 수 있는 편집기는 커서와 선택, 접힘, 실행 취소 기록, 조합 중인 글자를 그대로 둔다(`MarkdownBodyEditor`가 그렇다). 구현하지 않은 편집기(`PlainTextBodyEditor`)는 `text`에 통째로 넣는 것으로 넘어간다.
- `applyOutsideChange(to:)`가 불리면 지금 글을 받은 글로 맞춘다. `text`를 밖에서 넣을 때처럼 `onTextChange`를 부르지 않고, 넣기 전에 미뤄 둔 알림은 버린다. 할 수 있는 편집기는 달라진 곳만 바꿔 커서와 선택, 접힘, 실행 취소 기록을 그대로 둔다. 구현하지 않은 편집기(`PlainTextBodyEditor`)는 `text`에 통째로 넣는 것으로 넘어간다.
- `flushPendingChange()`가 불리면 아직 알리지 않은 변경(늦게 알리려고 미뤄 둔 것)을 그 자리에서 `onTextChange`로 알린다. 알릴 것이 없으면 아무것도 하지 않는다. 노트 창은 창을 내리기 전(`closeWindow`), 휴지통으로 보내기 전(`moveToTrash`), 없어진 노트를 새 노트로 저장하기 전, 그리고 App이 끝내기 전에 부르는 `flushPendingEdits()`에서 부른다. 이것이 없으면 알림이 한 차례 늦는 편집과 같은 차례에 닫힌 창의 마지막 글이 사라진다.

## Editor (`Sources/Editor/`)

본문 편집기(spec 6). `Theme`에만 기대고 창을 모른다. App이나 노트 창이 아래 창구만 보고 붙인다.

### 공개 API

- `MarkdownEditor` (`@MainActor`): `init(theme: Theme, configuration: MarkdownEditorConfiguration = .init())`
  - `view: NSView`: 세로 스크롤 뷰. 바탕은 그리지 않고 안쪽 여백(`doc-pad`)은 편집기가 둔다. 아무 뷰에나 넣는다.
  - `documentView: NSView`: 스크롤 뷰 없이 본문만 든 뷰(뒤집힌 좌표, 안쪽 여백 포함). 바깥이 스크롤 뷰를 가질 때(노트 창) 그 문서 뷰로 넣는다. 바깥은 너비만 맞추고 높이는 이 뷰가 내용에 맞춘다. 이것을 가져가면 `view`는 비므로 둘 중 하나만 쓴다.
  - `text: String`: 원문(Markdown 글자 그대로). 넣을 때는 `onTextChange`를 부르지 않고, 같은 글이면 아무것도 하지 않는다(커서, 되돌리기 기록 유지). 다른 글을 넣으면 되돌리기 기록을 비운다.
    - 편집기의 글은 언제나 `\n`으로 끝나는 줄이다. 넣을 때 `\r\n`, `\r`, U+2028, U+2029를 `\n`으로 바꾸므로, 그런 글을 넣으면 읽은 값이 넣은 값과 다르다(이때도 `onTextChange`는 부르지 않는다. 파일의 줄바꿈은 사용자가 고친 뒤 저장될 때 `\n`이 된다). 붙여넣기와 끌어다 놓기도 같게 바꾸고, Return 계열 키(⌃Return, ⌥Return 포함)는 모두 `\n` 하나를 넣는다.
  - `load(text:foldedLines:)`: 노트를 열 때 원문과 접힌 줄을 한 번에 넣는다. 아무것도 알리지 않는다. 같은 글이면 접힘만 바꾼다.
  - `appendFromOutside(_:)`: 바깥이 원문 끝에 덧붙인 글만 넘긴다(빠른 캡처가 떠 있는 노트에 한 줄을 덧붙임). 통째로 넣는 것과 달리 커서와 선택, 접힘, 되돌리기 기록을 그대로 둔다. 되돌리기에 적히지 않으므로 ⌘Z는 붙인 글을 지우지 않고 사용자가 한 편집만 되돌린다. `onTextChange`를 부르지 않는다. 한글을 조합하는 중이면 화면에 넣는 일을 조합이 끝날 때까지 미룬다: 입력기를 거치지 않고 원문 저장소가 바뀌면 텍스트 뷰가 조합을 끝내 버리기 때문이다(조합하는 자리가 글 끝이 아니어도 그렇다). 미룬 동안에도 `text`와 `onTextChange`로 나가는 원문에는 붙인 글이 들어 있다.
  - `onTextChange: ((String) -> Void)?`: 사용자가 고쳤을 때만. 한글을 조합하는 중에도 조합 중인 글자가 든 원문으로 부른다(높이도 같다). 예: `store.scheduleUpdate(id) { $0.body = text }`.
  - `onContentHeightChange: ((CGFloat) -> Void)?`, `contentHeight: CGFloat`: 안쪽 여백을 포함한 내용 높이. 뷰에 너비가 정해진 뒤에 맞는 값이 나온다. 창 높이를 움직이는 일(`dur`, 위쪽 고정)은 받는 쪽이 한다.
  - `foldedLines: Set<Int>`, `onFoldChange: ((Set<Int>) -> Void)?`: 접힌 토글의 줄 번호(0부터). 원문에 적지 않는 보기 상태다(D-018). 넣을 때는 알리지 않는다.
    - `foldedLines`는 지금 원문에 맞춰 걸러진다(토글이 아닌 줄 번호는 버린다). 원문보다 먼저 넣으면 남지 않으므로 함께 넣을 때는 `load`를 쓴다.
    - `onFoldChange`는 값이 바깥이 아는 것과 실제로 달라졌을 때만 한 번 부른다. `text`를 넣어 접힘이 없어진 경우도 그 자리에서 알린다.
    - 편집을 되돌리면 접힘도 그 편집 전으로 돌아간다(D-020).
  - `applyOutsideChange(to:)`: 바깥이 원문을 바꿨을 때 새 글 전체를 넘긴다. 지금 원문과 견주어 앞뒤의 같은 부분은 두고 달라진 가운데만 바꿔 넣는다. 되돌리기 기록, 접힘, 조합 중인 글자를 지키고 `onTextChange`를 부르지 않는다. `appendFromOutside`는 이것의 한 경우다. 커서, 되돌리기, 조합의 규칙은 D-037에 있다(문서 끝의 커서는 바깥의 글이 그 줄에 이어 붙었을 때만 그 글 뒤로 간다. 바깥의 변경은 되돌리기에 적히지 않고, 사용자의 기록이 가리키는 위치를 그만큼 옮긴다. 사용자가 고친 자리에 겹쳐 옮길 수 없는 단계와 그보다 오래된 단계는 버린다).
  - `configuration: MarkdownEditorConfiguration`(`checkboxStyle: .box | .bracket`, `inlineCodeStyle: .accent | .plain`. 인라인 코드의 글자색이고 기본은 `.accent`, D-035), `selectedRange: NSRange`, `undoManager: UndoManager`(편집기마다 따로. 기록은 편집기가 직접 들고 이것은 창구다: `undo`, `redo`, `canUndo`, `canRedo`, `removeAllActions`, `beginUndoGrouping`과 `endUndoGrouping`만 뜻이 있고 `registerUndo`는 받지 않는다), `onOpenLink: ((URL) -> Void)?`(없으면 기본 브라우저). 링크는 `http`, `https`, `mailto` 주소만 열고 `onOpenLink`에도 그것만 넘긴다. 복사한 HTML의 `href`도 같다(D-020).
  - `flushPendingChange()`: 아직 `onTextChange`로 알리지 않은 변경이 있으면 지금 알린다(창을 닫기 직전에 바깥이 부른다).
  - `focus()`, `perform(_ action: EditorAction)`: `EditorAction`은 spec 13 "편집" 표의 동작(`.indent .outdent .toggleTodo .toggleDone .moveLineUp .moveLineDown .fold .unfold .heading(1...3) .bold .strikethrough .highlight .inlineCode .codeBlock .link`). 단축키는 편집기가 직접 받고, 더 보기 메뉴 같은 곳에서는 이것을 부른다. 서식 동작(`.bold .strikethrough .highlight .inlineCode`)은 고른 글자가 있으면 그 글자를 고치고, 없으면 원문을 고치지 않고 다음에 칠 글자의 서식만 정한다. `.link`는 주소를 적는 칸을 띄운다(D-036).
  - `@_spi(Verification)`: `forcesActiveAppearance`(키 창이 아니어도 편집 중인 것으로 본다: 편집 단축키를 받는다), `textView`, `gutterPoint(forLine:)`, `textPoint(forLine:)`, `commitLink(_:)`(떠 있는 주소 칸에 주소를 넣고 확정). `EditorDemo`와 App의 디버그용 `DebugControl`만 쓴다.
  - 편집 단축키(`EditorShortcuts.bindings`)는 본문에 포커스가 있고 창이 키 창일 때만 받는다. 키 창이 아닌 창의 뷰에도 `performKeyEquivalent`가 올 수 있고, 그때 받으면 사용자가 보고 있지 않은 노트의 글이 바뀐다.

### 안쪽 구조

- `Model/`(AppKit 없음, 모두 `nonisolated` 값과 순수 함수): `MarkdownDocument`(원문을 줄로 풂. 줄 경계는 TextKit 문단과 같다), `InlineParser`(기호로 읽는 조건과 백슬래시, D-038), `InlineMarker`(줄 안의 감춘 기호와, 같은 자리에 겹쳐 보이는 원문 위치들 사이의 계산), `EditorCommands`(명령마다 `TextEdit` 하나를 돌려줌. `+Triggers` 줄 맨 앞 기호와 코드 블록 들고 나기 및 언어 이름, `+Replace` 기호가 짝을 잃지 않는 지우기와 덮어쓰기 및 ``` 줄 지키기, `+Delete` ⌫와 ⌦, `+Inline` 고른 글자의 서식, `+Link`, `+CodeBlock`(줄이 없는 블록 포함), `+Typing` 닫는 기호를 쳐서 서식이 되는 순간과 구간 끝의 공백 및 ⌃T와 붙여 넣을 글 다듬기, `+Safety` 편집의 경계를 감춘 글자 밖으로 옮기기와 편집 뒤 다듬기 및 있던 구간을 읽히지 않게 만드는 편집 가리기, `+Fences` ``` 줄의 짝 확인과 새로 생기는 ``` 를 글자로 막아 고치기), `TypingMarks`(고른 것 없이 정해 둔 다음 글자의 서식), `OutsideEdit`(바깥이 바꾼 글에서 달라진 가운데), `UndoHistory`(되돌리기 기록과, 바깥의 변경을 건너 위치를 옮기는 계산. 1,000단계까지 두고, 되돌리기 전에 적어 둔 글이 그 자리에 있는지 본다), `CodeLanguages`(언어 이름으로 받는 낱말), `FoldState`, `CaretSnapping`(커서와 선택이 감춘 곳에 놓이지 않게 옮기는 규칙), `ListStructure`(하위 계층의 부모 관계, D-043), `EditorCommands+Orphans`(부모를 잃는 하위 줄을 편집에 붙여 내어 쓰기. 편집이 하위 줄을 가진 부모 줄의 종류나 단계를 바꿨을 때만 따지고, 편집한 줄만 따로 읽어 그 뒤의 하위 덩어리만 본다. 따진 편집에는 `TextEdit.checkedForOrphans`를 붙여 다시 따지지 않는다, D-043), `LinePresentation`(줄별 모양 `LineRenderKey`), `CopyExport`, `EditorShortcuts`, `LineEndings`(줄바꿈을 `\n`으로), `LinkPolicy`(열어도 되는 주소).
- `View/`: `ParagraphStyler`(줄 하나를 화면 문단으로), `MarkdownLayoutFragment`(둥근 바탕, 왼쪽 칸 그림, 인용문 막대), `EditorTextView`, `CodeCopyButton`, `LinkField`(링크 주소 칸), `EditorStyle`(테마에서 푼 값과 토큰에 없는 치수 `EditorMetrics`).
- `EditorController`: TextKit 2 스택을 들고 위 둘을 잇는다. `MarkdownEditor`는 이것을 감싼 얇은 창구다. 확장 파일로 나뉜다: `+Commands`(입력과 편집 길목. 사용자 편집 다듬기와 `apply`에서 부모를 잃는 하위 줄을 함께 내어 쓴다. 다듬기에서 따진 편집은 `apply`가 다시 따지지 않는다), `+Caret`(얇은 커서의 자리), `+Composition`(조합 앞뒤에 자리를 만들고 치우기), `+Styling`(문단 만들기, 높이), `+Undo`(되돌리기 기록 적기와 되돌리기, 접힘 되돌리기), `+Mouse`, `+Pasteboard`, `+Link`(주소 칸), `+Outside`(바깥이 바꾼 글 넣기). `EditorUndoManager`는 그 기록을 `UndoManager`의 모양으로 잇는 창구다.
- 되돌리기 기록은 텍스트 뷰의 것을 쓰지 않고 편집기가 직접 든다(`textView.allowsUndo = false`). 텍스트 뷰의 기록은 범위를 밖에서 고칠 수 없어, 바깥이 원문을 바꾸면 그 변경을 되돌리기 한 단계로 적는 수밖에 없었다(⌘Z가 빠른 캡처가 붙인 줄을 지웠다). 원문 저장소가 바뀔 때마다(`didProcessEditing`) 그 바꿔 쓰기를 열린 단계에 적고, 묶음이 끝나면 닫는다: `beginUndoGrouping`과 `endUndoGrouping` 사이(확인용 실행 파일과 테스트)가 한 단계이고, 묶음을 열지 않으면 런 루프 한 차례가 한 단계다. 이어 친 글자는 한 단계로 합치고 낱말 사이의 공백에서 끊는다. 조합(한글 입력) 하나는 한 단계다. 되돌린 뒤의 커서는 그 편집 전의 선택이고 다시 한 뒤의 커서는 편집이 남긴 선택이다. 바깥의 변경은 적지 않고 기록의 위치를 옮긴다(`UndoHistory.shift`).

### 동작 원리와 TextKit 2에서 확인한 것

- 원문 저장소(`NSTextStorage`)에는 기본 글꼴과 글자색만 있다. 서식은 `NSTextContentStorageDelegate`의 `textParagraphWith:`에서 문단을 만들 때 얹는다. 감출 기호는 지우지 않고 글자 크기를 0.01로 해서 자리를 없앤다(문단 글자 수가 원문과 같아야 한다). 그래서 서식을 다시 입혀도 되돌리기 기록과 조합 중인 글자(한글 입력)를 건드리지 않는다. 기호는 커서가 있는 줄에서도 감춘다(D-036). 줄의 모양은 원문, 접힘, 마우스가 올라간 링크로만 정해지므로 커서를 옮겨도 줄을 다시 입히지 않고 높이도 바뀌지 않는다.
- 감춘 기호는 너비가 없어서 서식 구간의 양 끝에는 같은 자리에 보이는 원문 위치가 둘씩 있다. 어느 쪽에 설지는 `CaretSnapping`이 정한다(규칙은 D-036의 6번). 텍스트 뷰가 선택을 바꾸려 할 때마다(`willChangeSelection`) 옛 선택과 새 선택을 넘겨 받아, 지나온 것이 감춘 기호뿐이면 기호를 건너뛰고 보이는 글자 하나를 지나게 하고, 그 밖에는 기본 자리로 옮긴다. 편집에 딸려 온 선택 변화(원문이 바뀐 뒤 처음 오는 변화, 되돌리기)는 화살표로 옮긴 것처럼 다루지 않고 기호 한가운데만 피한다(`selectionVersion`으로 가린다).
- `NSTextLayoutManager.usesFontLeading`을 끈다. 켜 두면 글꼴의 leading이 고정한 줄 높이에 더해져 D2Coding이 든 줄이 0.96pt 높아진다(D-035).
- 감춘 여는 기호의 마지막 글자에 자간을 주어 인라인 코드와 형광펜의 안쪽 여백을 만든다. 그 자간은 `locationForCharacter(at:)`가 주는 글자 위치에 절반만 잡히므로, 바탕 상자의 첫 조각은 왼쪽을 그만큼 밀어 그린다(`InlineBackground.leadShift`).
- 모양이 달라진 줄만 다시 입힌다: `performEditingTransaction` 안에서 `textStorage.edited(.editedAttributes, …)`를 불러 그 문단을 다시 만들게 한다.
- `.baselineOffset`은 글자를 가운데로 옮기지 못한다(양수면 줄 높이가 그만큼 줄 뿐이다). 줄 높이를 고정하면 남는 공간이 모두 글자 위에 생기므로, 문단 조각의 `draw(at:in:)`에서 글자만 위로 옮겨 그린다.
- `usageBoundsForTextContainer`는 문단 높이가 줄어든 뒤 옛 값을 줄 때가 있다. 내용 높이는 마지막 문단 조각의 아래 끝으로 잰다.
- 접힌 줄과 코드 블록의 ``` 줄은 문단을 없애지 않고 줄 높이를 줄여 감춘다(접힌 줄 0.01, ``` 줄은 상자 안쪽 여백 `codeblock-pad-y`).
- 원문이 바뀌는 길목은 `shouldChangeTextIn` 하나다(글자 입력, 지우기, 붙여넣기, 끌어다 놓기, 조합, 편집 명령이 모두 지난다). 여기서 차례로: 접혀서 감춘 줄에 닿는 편집을 막고 그 토글을 편다(D-020). 감춘 줄까지 일부러 고치는 명령(줄 옮기기, 들여쓰기, 접힌 토글 뒤에 새 토글)만 `TextEdit.includesHiddenLines`로 지나간다. 보이지 않는 ``` 줄의 한쪽만 지우는 편집을 막는다. 조합 중이 아니면: 편집의 경계를 감춘 글자 밖으로 옮기고(`EditorCommands.normalized`: 백슬래시와 막은 글자 사이, 줄 머리 안에서 시작하는 범위, 뒷줄 맨 앞에서 끝나는 범위), 정해 둔 서식이 있으면 기호 쌍과 친 글자를 한 번에 넣고(여러 줄이면 줄마다 감싼다), 줄 맨 앞의 기호 뒤 Space와 세 번째 백틱은 줄의 종류를 바꾸는 편집으로 갈아 넣고, 닫는 기호를 쳐서 서식이 되는 입력은 두 단계(백슬래시로 막은 글자, 이어서 서식)로 넣어 되돌리면 글자가 남게 하고, 감춘 기호가 짝을 잃는 지우기와 덮어쓰기는 고쳐 쓴 편집(`EditorCommands.replacing`)으로 갈아 넣는다. 마지막으로 편집의 결과를 다듬는다(`EditorCommands.finalized`: 줄 맨 앞에 남는 공백 지우기, 구간 가장자리의 공백을 기호 밖으로, 붙여 넣은 글의 읽히지 않는 서식 벗기기, 맞붙은 같은 서식 합치기). 다른 줄바꿈 글자가 든 글도 여기서 `\n`으로 바꿔 넣는다. 어느 길로 들어온 편집이든 닫히지 않은 ``` 블록이 새로 생기면 그대로 넣지 않는다(`EditorCommands.keepsFencesBalanced`. `apply`와 그대로 넣는 길 둘 다에서 본다): 새로 생기는 ``` 를 글자로 막아 넣을 수 있으면 그렇게 넣고(`escapingNewFences`), 아니면 넣지 않고 알린다. 넣지 않은 편집(``` 줄, 있던 서식 구간을 읽히지 않게 만들거나 감춘 기호를 글자로 드러내는 편집. `breaksExistingRun`, `exposesHiddenMarkers`)은 `EditorController.onRejectedEdit`으로 알린다(기본은 `NSSound.beep()`, 테스트는 횟수를 센다). 바깥이 바꾼 글(`applyOutsideChange`)과 되돌리기는 막지 않고 그대로 받는다.
- 조합(한글 입력)이 시작되면 원문을 따로 고칠 수 없다(조합이 끊긴다). 그래서 조합을 시작하기 직전(`EditorTextView.setMarkedText`)에만 자리를 만든다: 기호가 짝을 잃는 선택과, 덮어쓰면 하위 줄을 내어 써야 하는 선택(부모 줄을 덮어씀, D-043)을 먼저 지우고, 정해 둔 서식의 빈 기호 쌍이나 바깥이 붙인 줄 뒤의 줄바꿈을 넣고, 구간 끝에서 친 공백 뒤라면 그 공백을 구간 안으로 들인다. 조합이 글자 없이 끝나면 넣어 둔 빈 쌍을 지우고 들여 둔 공백을 되돌려 놓는다. 텍스트 뷰가 조합을 끝내는 동안(`unmarkText`, 포커스를 잃을 때)에는 조합 중인 글자가 잠깐 비어 보이므로 `isEndingComposition`으로 그 사이의 치우기와 알림을 막는다. 구간의 글자를 모두 고르고 조합하다 그만둔 경우도 빈 쌍으로 다뤄 기호를 지운다.
- 바깥에 알리는 일(`onTextChange`, 높이, 접힘)은 `didProcessEditing`에서 표시해 두고 `flushPendingChange`에서 한다. 글자 입력은 `textDidChange`에서, 조합 중인 글자는 `setMarkedText` 바로 뒤에(이때는 `textDidChange`가 오지 않는다), 그 밖에는 다음 메인 큐 차례에 불린다.
- 접힘의 되돌리기: 편집을 되돌렸을 때 줄 번호를 따라 옮기는 것만으로 접힘이 편집 전으로 돌아가지 않으면(토글이 사라짐, 줄 옮기기, 접힌 덩어리를 통째로 고침) 편집 전 접힘을 같은 되돌리기 묶음에 적어 두고, 되돌리기가 끝난 뒤(`NSUndoManagerDidUndoChange`)에 넣는다. 글자를 치는 편집에는 적지 않는다(연달아 친 글자가 한 번에 되돌려지는 것을 깨지 않으려고).
- 입력 커서는 시스템의 것을 쓰지 않는다(D-042). `EditorTextView.shouldDrawInsertionPoint`가 `false`여서 시스템의 커서 표시 뷰가 생기지 않고, Theme의 `TextCaret`이 텍스트 뷰 위의 작은 뷰로 그린다. 자리(`EditorController.caretRect`)는 커서가 놓인 문단 조각의 줄 조각에서 글자 경계의 x를 재고(줄이 넘어간 경계는 `selectionAffinity`가 앞쪽이면 윗줄 끝), 세로는 글자를 줄 가운데에 놓은 기준선(`MarkdownLayoutFragment.textShift`와 같은 계산)에서 그 자리 글꼴의 ascender부터 descender까지다. 인라인 코드 안은 코드 글꼴과 `code-rise`를, 구간 맨 앞은 감춘 여는 기호의 자간 절반을 더한다. 글자가 없는 문서 끝의 빈 줄은 `enumerateTextSegments`의 커서 구간을 쓴다. 옛 그리기 경로(`drawInsertionPoint`)를 덮어쓰는 방식은 자국이 남아 쓰지 않는다(D-025). 기본 편집기(`PlainBodyTextView`)는 아직 시스템의 커서다.
- 링크 주소 칸(`LinkField`)은 본문 뷰의 하위 뷰다. 떠 있는 동안에는 칸의 아래 끝까지가 내용 높이에 들어가 창이 칸을 자르지 않는다.
- 텍스트 뷰는 마우스가 움직일 때마다 I자 커서를 넣는다(추적 영역이 보이는 영역 전체다). 그 자리에서 마우스를 받는 뷰가 텍스트 뷰(와 그 안의 뷰)가 아니면, 곧 위에 겹쳐 뜬 다른 뷰(노트 창의 휴지통, 닫기)면 I자 커서를 넣지 않고 화살표로 둔다(`EditorTextView.isHitView(for:)`, 규칙 9).
- 문서 끝의 빈 줄은 문단이 만들어지지 않고 앞 문단 조각에 붙은 빈 줄 조각으로 놓인다. 커서가 그 줄에 있으면 그 줄의 들여쓰기와 높이는 텍스트 뷰의 입력 속성(기본 문단 모양)을 따른다. 닫히지 않은 코드 블록이 줄바꿈으로 끝나면 `defaultParagraphStyle`에 코드 줄 모양을 넣고, 앞 문단 조각이 코드 상자를 그 줄까지 늘려 닫는다. 서식 없는 텍스트 뷰는 기본 문단 모양을 저장소의 글자에도 붙이므로 `willProcessEditing`에서 떼어 낸다(저장소에는 글꼴과 글자색만 남는다).

### 확인용 실행 파일 `EditorDemo` (`Sources/EditorDemo/`)

- `swift run EditorDemo --appearance light|dark --checkbox box|bracket --code-style accent|plain --sample note|elements|code|literal|structure|empty --caret-line <n> --fold <n,n> --width <pt> --script "<단계;단계>" --print-text --snapshot <png 경로>`
- `--activate --quit-after <초>`: 키 창으로 띄워(화면에서 커서를 볼 때) 1초쯤 뒤에 `KEY`, 커서의 틀(`CARET`), 시스템의 커서 표시가 생겼으면 `SYSTEM-CARET`을 적고 그만큼 뒤에 끝난다. `--origin`의 x는 음수일 수 있다(왼쪽의 보조 화면). `--snapshot`의 그림에도 얇은 커서가 찍힌다(`--snapshot`만 쓰면 키 창이 아니어도 보이게 한다).
- `--snapshot`은 창 내용을 프로세스 안에서 PNG로 그려 내고 끝낸다. 창을 화면에 올리지 않는다. 화면 녹화 권한이 필요 없고 다른 창이 찍히지 않는다. 창 그림자와 시스템 입력 커서는 찍히지 않는다.
- `--script`는 실제 입력 경로(`insertText`, `doCommand(by:)`, 마우스 이벤트)를 차례로 부른다. 단계는 `DemoScript.swift` 머리 주석에 있다. 다른 앱의 포커스를 빼앗지 않으려고 기본으로는 키 창이 되지 않는다(`--activate`로 바꾼다).
- 앱 묶음에는 들어가지 않는다.

## Capture (`Sources/Capture/`)

빠른 캡처 바(spec 7, 화면 3). Core 모듈만 import한다. 임시 값은 D-026, D-028.

### 공개 API

```swift
@MainActor public final class CaptureCoordinator {
    public init(theme: Theme, notes: any NoteStoring, spaces: SpaceStore, router: any Routing,
                log: @escaping @MainActor (String) -> Void)
    public var isVisible: Bool { get }
    public func show()      // 마우스가 있는 화면(없으면 주 화면)의 가운데 아래쪽(D-030)
    public func hide()
    public func toggle()
    public var onDismiss: (@MainActor (_ returnsFocus: Bool) -> Void)?
    public var onFailure: (@MainActor (Error) -> Void)?
    public var onCaptured: (@MainActor (NoteID) -> Void)?   // ↵로 넣은 줄이 들어간 노트(D-041)
}
```

- App이 하나 만들어(`QuickPanels`) `.openCapture`와 어디서나 쓰는 단축키에 잇는다. 창은 처음 띄울 때 만든다.
- ↵: 적은 글을 고른 스페이스의 오늘 노트에 투두로 붙이고 닫는다(없으면 `create`). 쓰는 길은 `NoteStoring.update` 하나라서 편집기가 미뤄 둔 본문 뒤에 붙는다. 넣지 못하면 `log`에 까닭을 적고 `onFailure`로 App에 알린 뒤 글을 그대로 둔 채 열어 둔다. 알리는 동안(알림 창이 키 창이 됨)에는 키 창에서 물러나도 닫히지 않고, 돌아오면 다시 입력을 받는다.
- `onDismiss`: 닫히기 시작할 때 한 번 불린다. 인자가 참이면 포커스를 열기 전의 자리로 돌려줄 때다(esc, ⌘W, ↵로 넣음, `hide()`, `toggle()`). 거짓이면 포커스가 갈 곳이 따로 있다(바깥을 눌러 키 창에서 물러남, ⌘↵로 새 노트를 띄움. 새 노트가 만들어진 뒤에 닫히므로 이때의 알림은 `Route.newNote` 뒤에 온다). 키 창을 누구에게 돌려줄지는 App이 정한다.
- 닫히기 시작하면(사라지는 `dur` 동안) 명령도 글도 받지 않는다: `perform`이 곧바로 돌아가고 입력 칸은 고칠 수 없게 된다. ↵를 잇달아 두 번 눌러도 한 번만 들어간다. 다시 띄우면 풀린다.
- 상태는 창의 움직임이 끝났는지에 기대지 않는다(D-032): `animator()`로 건 움직임은 꾸밈일 뿐이고, 창을 내리고(`orderOut`) 닫히는 중 표시를 풀고 끝의 자리와 알파로 놓는 일은 `dur` 뒤의 시계(`Theme`의 `TransitionTimer`, `CaptureStyle.afterTransition`)가 한다. "동작 줄이기"면 그 자리에서 한다. 다시 띄우면 걸어 둔 것을 취소한다. 화면이 꺼져 있거나 잠겨 있으면 창의 움직임은 나아가지 않고 끝났다는 알림도 오지 않으므로, `CaptureStyle.animate`는 끝났을 때를 알려 주지 않는다.
- 줄은 언제나 디스크에 쓰인 노트에 들어간다. 오늘 노트가 충돌 중이거나 파일이 없어졌으면(`StoreError.conflict`, `.noteNotFound`) 줄을 올리기 전에 알아내고(`CaptureWriter`가 미뤄 둔 변경을 먼저 써 본다) 오늘의 다음 노트나 새 노트에 넣은 뒤 `log`로 까닭을 남긴다. 그 밖의 쓰기 실패는 그대로 던진다.
- 읽은 때가 이미 지났으면(`CaptureInterpretation.isReminderPast`) 바에 지난 모습으로 보이고 리마인더는 걸지 않는다. 있던 리마인더와 합칠 때(`ReminderRule`)는 "지금"을 받아 이미 지난 값을 없는 것으로 친다.
- ⌘↵: `Route.newNote`(적은 글이 제목, 고른 스페이스와 리마인더)를 보내고, 답이 `.handled`일 때만 닫는다. 만들지 못했으면(`.failed`. 알리는 일은 받은 쪽이 했다) 적은 글을 그대로 둔 채 열어 두고 다시 입력을 받는다. 요청이 돌아오기 전에 키 창에서 물러나도(실패 알림 창, 새로 뜬 노트) 그 때문에 닫히지 않는다. 노트를 만들고 띄우는 일은 App이 한다.
- ⇥, ⇧⇥: 스페이스 바꾸기. ⌘R: 리마인더 직접 고르기. esc, ⌘W, 바깥 클릭(키 창에서 물러남): 닫기. ⌘W는 입력 칸이 키 자리로 직접 받는다(테두리 없는 창은 `performClose`를 받지 못한다). 나타날 때는 `capture-rise`만큼 아래에서 올라오며 알파가 함께 `dur`, `ease`로 바뀌고, 사라질 때는 그 반대다. 걸어 둔 알림(`NotificationCenter`)은 `deinit`에서 푼다.
- 떠 있는 노트에 붙인 줄은 그 창에 바로 보인다: 노트 창이 저장소 변경을 받아 붙은 글만 편집기에 넘긴다(`appendFromOutside`. 본문 끝의 빈 줄을 걷어 내고 붙였으면 `applyOutsideChange(to:)`, D-023의 7번). 커서, 접힘, 실행 취소 기록은 그대로이고, 그 뒤에 편집기에서 친 글과 함께 저장된다(App의 `QuickPanelResultsTests`가 실제 편집기로 끝에서 끝까지 보고, `CaptureIntoOpenNoteTests`가 노트 창이 편집기를 어느 길로 부르는지 본다).
- `@_spi(Verification)`: `now`, `calendar`, `takesKeyOnShow`, `window`, `inputView`, `displayedSpace`, `displayedReminder`, `displaysReminderAsPast`, `underlinedRanges`, `settledFrame`, `entranceFrame`, `notificationCenter`, `showsPlaceholder`, `performSubmit()` 등. 테스트와 `Stage4Demo`, App의 디버그용 `DebugQuickPanels`만 쓴다.

### 안쪽 구조

- Core `Sources/DateTime/`(Capture에서 옮긴 화면, 저장소 독립 모듈, D-029, D-074): 글에서 날짜와 시간 표현을 읽는다. `DateTimeParser.firstExpression(in:now:calendar:) -> DateTimeExpression?`가 창구이고, 결과는 `start`, `end`(범위일 때), `ranges`(차지한 글자들. 받은 글의 UTF-16 자리이고, 날과 시각을 떨어뜨려 적으면 두 곳), `assumptions`(`meridiem`, `timeOfDay`, `looseDate`, `past`, `recurring`, `unknownTimeZone`. 하나라도 있으면 `isAmbiguous`)다.
  - 차례: `NormalizedText`(NFC, 전각을 반각으로, 받은 글의 자리로 되돌리는 표) → `DateTimeLexer`(조각 찾기. 무늬는 `+Time`, `+Relative`, `+Date`에 나눠 둠) → `DateTimeParser`(조각을 시점과 범위로 잇기) → `DateTimeResolver`(지금 시각과 달력으로 날짜 정하기). 값 타입은 `DateTimePieces`, 기본 시각은 `DateTimeDefaults` 한 곳, 한글로 적은 수는 `KoreanNumeral`.
  - 규칙 요약(전체 표는 spec 7a): 앞에 0을 붙인 `HH:mm`과 0시, 13~23시는 24시간제. 오전과 오후가 없는 1~11시는 오후, 12시는 정오이고(D-157. 양쪽 다 없는 범위의 시작만 8~11시를 오전으로), 날이 없으면 오늘 남았을 때 오늘, 지났으면 같은 시각의 내일. 때를 가리키는 말은 시각 바로 앞이나 `N시 저녁에` 꼴일 때만 시각에 붙는다. 날만 적으면 09:00(때를 가리키는 말이 있으면 그 기본 시각). 오늘을 가리키는 날은 언제나 오늘이고 지났으면 `past`. 범위는 양 끝을 서로 맞게 읽는다(`9-6시`는 09:00~18:00). 날과 시각은 붙어 있으면 어느 쪽이 먼저든 한 표현이고, 떨어져 있어도 맨 앞이 날뿐이고 시각이 하나면 합친다. 지난 때와 되풀이, 기간, 분수, 비율은 읽지 않는다.
  - 규칙을 고칠 때는 `DateTime*Tests`의 표에 줄을 먼저 더한다.
- `Logic/`(화면 없음, `nonisolated` 값과 순수 함수): `CaptureSpaceToken`(`#이름`), `CaptureInterpretation`(글 한 줄에서 넣을 글, 스페이스, 읽은 때와 걸 리마인더, 밑줄 자리들), `CaptureDestination`(오늘 노트), `TodoAppender`, `ReminderRule`, `CaptureSpaceCycle`, `CaptureReminderPresets`, `CaptureReminderText`, `CapturePlacement`. `CaptureWriter`가 이것들로 저장소에 쓴다.
- `Views/`: `CapturePanel`(테두리 없는 `NSPanel`, 앱을 앞으로 가져오지 않고 키 창이 됨), `CaptureBarView`(한 줄 배치), `CaptureTextView`(한 줄 입력, 명령 키), `CaptureBadgeView`(스페이스와 리마인더 표시), `CaptureBackgroundView`(흐림 위에 `surface`를 `opacity`로), `CaptureStyle`.
- 입력 칸은 `NSTextView`다. 시간 표현의 밑줄은 글 저장소가 아니라 배치 쪽의 임시 속성(`addTemporaryAttributes`)이라 한글 조합을 끊지 않는다. 조합 중인 글자가 바뀔 때(`setMarkedText`)도 다시 읽는다.
- 조합 중의 ↵(D-028의 4번): 키를 누른 순간의 조합 여부는 보지 않는다. `insertNewline:` 명령이 왔을 때 조합 중인 글자가 남아 있는 경우에만 조합을 끝내고 멈춘다. 한글 두벌식은 입력기가 글자를 확정한 뒤 같은 키 입력에서 명령을 보내므로 ↵ 한 번에 들어간다. 테스트는 `inputContextOverride`에 입력기 흉내(`FakeInputContext`)를 끼워 `keyDown`부터 지나간다. 노트 찾기의 `BrowseTextView`도 같다.
- 편집 단축키(⌘A, ⌘C, ⌘X, ⌘V, ⌘Z)는 입력 칸이 직접 받는다. 이 창은 다른 앱이 앞에 있을 때도 떠서 앱 메뉴에 기대지 않는다.

## Browse (`Sources/Browse/`)

노트 찾기(spec 8, 화면 9). Core 모듈만 import한다. 임시 값은 D-027, D-028.

### 공개 API

```swift
@MainActor public final class BrowseCoordinator {
    public init(theme: Theme, notes: any NoteStoring, spaces: SpaceStore, router: any Routing,
                windowStates: WindowStateStore? = nil, log: @escaping @MainActor (String) -> Void)
    public var isVisible: Bool { get }
    public func show(anchoredTo window: NSWindow?, excluding current: NoteID?)   // 창이 없으면 화면 가운데 위쪽
    public func hide()
    public var onDismiss: (@MainActor (_ returnsFocus: Bool) -> Void)?
    public var onFailure: (@MainActor (Error) -> Void)?
}
```

- `windowStates`는 떠 있는 노트(열려 있는 창, 앞에 있는 것이 먼저)와 노트마다 마지막으로 연 때를 알아내는 데 쓴다. 주지 않으면 "떠 있는 노트" 구획과 핀이 보이지 않고 모든 노트가 "최근에 연 노트"로 간다. App은 노트 창에 넘긴 것과 같은 객체를 넘긴다.
- "최근에 연 노트"의 차례(D-033, `BrowseRecency`): 마지막으로 연 때(`NoteWindowState.lastOpened`)가 가까운 노트가 앞이다. 적힌 것이 없는 노트는 고친 시각으로 견주고, 때가 같으면 고친 차례를 지킨다. 떠 있는 노트와 검색 결과의 차례에는 쓰지 않는다.
- App은 `.openBrowse(anchor:)`를 받아 그 노트의 창과 id로 `show`를 부른다(`QuickPanels`, `BrowseAnchor`). 메뉴 막대에서 열 때는 둘 다 `nil`이다.
- 줄을 고르면(↵, 클릭) 요청을 보내고 닫는다: 노트는 `.openNote(id)`, "새 노트 만들기"는 `.newNote`(검색어가 제목, `nextTo`는 `current`), "라이브러리 열기"는 `.openLibrary`. 떠 있는 노트로 포커스를 옮기거나 닫혀 있던 노트를 지금 노트 옆에 띄우는 일은 App이 한다. 요청이 돌아오기 전에 키 창에서 물러나도(고른 노트가 키 창이 됨, 실패 알림 창) 그 때문에 닫히지 않고, 닫힘은 요청의 답을 본 뒤에 한 번 알린다.
- "라이브러리 열기" 줄은 `router.isConnected(.openLibrary)`가 참일 때만 있다(D-034). 눌러도 아무 일이 없는 줄을 내놓지 않는다. 그때는 그 위의 구분선도 없다.
- `onDismiss`: 닫히기 시작할 때 한 번 불린다. 인자가 참이면 포커스를 열기 전의 자리로 돌려줄 때다(esc, ⌘W, `hide()`, spec 17. 고른 줄의 요청이 이루어지지 못했을 때도 그렇다: 답이 `.failed`나 `.unconnected`). 거짓이면 포커스가 갈 곳이 따로 있다(바깥을 눌러 키 창에서 물러남, 고른 줄의 요청이 이루어짐. 이때의 알림은 요청 뒤에 온다). 이 모듈은 노트 창을 직접 키 창으로 만들지 않는다. 누구에게 돌려줄지는 App이 정한다(D-032).
- 닫히기 시작하면(사라지는 `dur` 동안) 명령도 글도 받지 않는다: esc 바로 뒤의 ↵가 줄을 열지 않는다. 다시 띄우면 풀린다.
- 상태는 창의 움직임이 끝났는지에 기대지 않는다(D-032, 캡처 바와 같다): 창을 내리는 일과, 높이가 바뀐 뒤 마지막으로 정한 틀에 놓고 그림자를 다시 만드는 일은 `dur` 뒤의 시계(`TransitionTimer`, `BrowseStyle.afterTransition`)가 한다. `BrowseStyle.animate`는 끝났을 때를 알려 주지 않고, "동작 줄이기"면 시간 0으로 묶어 바로 바꾼다.
- 열려 있는 동안 노트 저장소, 창 상태(`WindowStateStore.observe`), 스페이스 목록(`SpaceStore.observe`)의 변경을 받아 목록을 다시 만든다(D-033). 노트 창이 뜨고 내려가거나 핀과 스페이스 이름이 바뀌면 열려 있는 목록이 따라간다. 노트를 고치거나 만들지 않는다. 변경이 잇달아 와도 다음 차례(메인 큐)에 한 번만 다시 읽고, 고른 줄은 노트 id로 견주어 그대로 둔다(`BrowseSelection.index(keeping:in:)`). 닫히면 듣지 않는다.
- 노트 목록을 읽지 못하면 `log`로 까닭을 알리고, 보이던 목록이 있으면 그대로 둔다. 띄울 때 읽지 못했으면 `onFailure`로도 App에 알리고(열려 있는 동안 다시 읽다가 난 실패는 기록만 한다) "새 노트 만들기"(글자를 치면)와 "라이브러리 열기"(이어져 있으면)만 보인다. 알리는 동안(알림 창이 키 창이 됨)에는 키 창에서 물러나도 닫히지 않고, 돌아오면 다시 입력을 받는다. 걸어 둔 알림은 `deinit`에서 푼다.
- `@_spi(Verification)`: `now`, `calendar`, `takesKeyOnShow`, `window`, `inputView`, `rowDescriptions`, `settledFrame`, `drawnRowCount`, `listReadCount`, `notificationCenter` 등. 테스트와 `Stage4Demo`만 쓴다.

### 안쪽 구조

- `Logic/`(화면 없음): `BrowseMatcher`(소문자와 자모 단위로 견줌, 조합 중인 글자 처리), `BrowsePreview`(본문 첫머리), `BrowseContent`(목록의 줄과 차례: `BrowseEntry`), `BrowseSelection`(↑↓, 줄마다 보낼 `Route`), `BrowseFloating`, `BrowseRecency`(최근에 연 차례), `BrowseReminder`, `BrowsePlacement`.
- `Views/`: `BrowsePanel`, `BrowseRootView`(바탕, 검색 칸, 스크롤되는 목록), `BrowseSearchField`(`surface-2` 바탕과 `line` 테두리, D-039)와 `BrowseTextView`, `BrowseListView`(줄 쌓기, 고른 줄, 마우스), `BrowseEntryView`와 줄 뷰들, `BrowseStyle`.
- 글자를 칠 때마다 줄 뷰를 새로 만들어 바꾼다. 옛 줄은 바로 떼어 내고, 목록 전체를 겹쳐 넘기는 전환은 쓰지 않는다(옛 줄과 새 줄이 겹쳐 잔상으로 보인다).
- 창 높이는 위쪽을 고정한 채 `dur` 동안 내용을 따라간다. 움직이는 중에 내용이 또 바뀌면 마지막으로 정한 틀(`targetFrame`)과 견주어 새로 움직인다(움직이는 중의 `NSWindow.frame`은 가는 길의 값이라 견주면 안 된다). `dur` 뒤에 그 틀에 놓고 `invalidateShadow()`를 부른다(다음 변경이 먼저 오면 취소하고 새로 잡는다). 스크롤 막대는 내용이 높이 한도를 넘을 때만 둔다. 창 높이는 언제나 줄 수에 맞고, 한도(`browse-h-max-screen`)를 넘을 때만 스크롤된다. 띄울 때 아래로 그 한도만큼의 자리를 남기므로(`BrowsePlacement`) 화면 아래쪽의 노트에서 열어도 목록이 눌리지 않는다.

### 확인용 실행 파일 `Stage4Demo` (`Sources/Stage4Demo/`)

- `swift run Stage4Demo --notes-dir <폴더> --appearance light|dark --script "<단계;단계>" --snapshot <png 경로> --hold <초> --activate`
- `--notes-dir`는 꼭 줘야 하고 그 폴더 안만 읽고 쓴다. 비어 있으면 두 스페이스에 견본 노트 여덟 개를 채운다(만든 날짜와 고친 시각을 정해 적어 실행마다 차례가 같다).
- `--script`의 단계(`show:capture`, `show:browse`, `show:browse-anchored`, `type:`, `mark:`, `return`, `tab`, `up`, `down`, `esc`, `cmd-return`, `cmd-r`, `dump`, `snapshot:`, `screencap:` 등)는 `DemoScript.swift` 머리 주석에 있다. 실제 입력 경로(`insertText`, `setMarkedText`, `doCommand(by:)`)를 부르고 시스템에 키나 마우스 이벤트를 보내지 않는다. 받은 `Route`와 기록, 줄의 내용을 표준 출력에 적는다.
- `snapshot:`은 창의 레이어를 프로세스 안에서 그린다(그림자, 뒤 배경 흐림, 입력 커서는 찍히지 않음). `screencap:`은 `screencapture -l <창 번호>`로 그 창만 화면에서 찍는다(화면이 잠겨 있으면 안 된다).
- 기본으로는 키 창이 되지 않아 다른 앱의 입력을 빼앗지 않는다. `--activate`는 키 창 동작과 입력 커서를 볼 때만 짧게 쓴다.
- 앱 묶음에는 들어가지 않는다.

## App 타깃 (`Sources/FloatingNotes/`)

- `AppEnvironment`가 `Theme`, `FileNoteStore`, `WindowStateStore`(쓰기를 한데 모은다, `coalescingWriteDelay`), `SpaceStore`, `AppSettingsStore`(`stateDirectory/app-settings.json`. `showsMenuBarIcon`과 본문 편집기의 표시 방식 `inlineCode`(`accent` | `plain`), `checkbox`(`box` | `bracket`). 바뀌어 파일에 적히면 `onChange`를 부른다)를 한 번 만들고, `AppDelegate`가 아래를 조립한다(`AppRouter`, `NotePanelCoordinator`, `QuickPanels`, `AppCommandDispatcher`, 메뉴와 전역 단축키의 차례). 기능 모듈끼리는 서로를 모르고 여기서만 이어진다.
- 켤 때 버려도 되는 상태가 잘못돼 있으면 앱을 멈추지 않고 기본값으로 넘어간다(글꼴 등록 실패 → 시스템 글꼴, 쓸 수 없는 테마 덮어쓰기 → 버림, 깨진 상태 파일 → 옆으로 옮기고 빈 상태). 넘어간 것은 `AppEnvironment.launchWarnings`에 모아 `AppLog.warning`(표준 오류)으로 남긴다. 읽지 못한 노트 파일과 등록하지 못한 전역 단축키도 같은 방식으로 남긴다. 메뉴 막대 아이콘 파일은 아이콘을 켤 때 처음 읽고(`MenuBarIconSwitch`), 읽지 못하면 경고를 남긴 채 아이콘 없이 간다(같은 항목이 앱 메뉴와 Dock 메뉴에 있다). 꺼 둔 동안에는 읽지 않는다. 번들에 든 토큰이 없으면 시작하지 않는다.
- `AppDelegate`: 앱이 앞으로 올 때 `notes.refresh()`를 부르고, 사용자가 앞으로 가져온 것이면 `notePanels.focusFrontmostNote()`로 맨 앞 노트를 키 창으로 만든다(D-025). 알림 창이나 캡처 바, 노트 찾기가 키 입력을 받는 중이면 하지 않는다(실패를 알리는 알림 창은 스스로 앱을 앞으로 가져온다. 그때 노트가 키 창을 가져가면 알림 창과 캡처 바가 입력을 잃는다). 켜면서 오는 활성화는 뺀다: AppKit이 둘을 가려 주지 않아 `ActivationFocusPolicy`가 다 켠 뒤 1초(`launchGrace`) 안에 온 첫 활성화만 켜면서 온 것으로 본다(뒤에서 켠 실행에는 켜면서 오는 활성화가 없어 첫 활성화가 사용자의 것이다). 노트 창이 키 창이 될 때의 `refresh()`는 `NotePanelCoordinator`가 부른다. 끝낼 때(`applicationShouldTerminate`) `notePanels.flushPendingEdits()`로 편집기가 아직 알리지 않은 글을 받은 뒤 `flushPendingSaves()`를 부르고, 못 쓴 노트가 있으면 노트 이름과 까닭을 알림으로 보여 주고 돌아갈지 저장하지 않고 끝낼지 묻는다(`UnsavedNotesAlert`). 그 앞에 한데 모아 쓰려고 미뤄 둔 창 상태도 쓴다(`windowStates.flush()`. 쓰지 못하면 경고만 남기고 끝내기를 막지 않는다).
- 켤 때 `NotePanelCoordinator.restoreOpenNotes()`로 지난번 노트 창을 되살린다. 복원할 노트가 없으면 라이브러리를 연다. Dock 재열기도 숨긴 노트를 먼저 보이고, 열린 노트가 없으면 라이브러리로 간다(D-049). 최근 노트/빈 노트 자동 생성은 하지 않는다. `FallbackNotePresenter`는 기존 단위 테스트를 위한 구현으로 남아 있고 앱 시작에서는 쓰지 않는다.

### 앱 메뉴와 활성화

- 노트를 누르면 앱이 앞으로 오고 메뉴 막대에 `MainMenu`가 보인다: Float(관하여, 설정, 종료), 파일, 편집, 보기(노트 모두 숨기기), 창(다음 노트로), 도움말(단축키). 앱 메뉴 이름은 원본 Info.plist의 `CFBundleDisplayName`에서 읽는다. 파일 이름은 Float.app이고 `CFBundleDisplayName`과 `CFBundleName`은 모두 Float다(D-175). SwiftPM 실행, 테스트에서는 Float를 기본값으로 쓴다. 보이는 항목에는 단축키를 적지 않는다(규칙 4).
- `AppRouter.activateApp`: `.openNote`, `.newNote`를 해낸 뒤 부른다(기본은 아무것도 하지 않고 `AppDelegate`가 넣는다. 확인용 실행 `--debug-passive`에서는 넣지 않는다).
- `applicationDidBecomeActive`: 키 창인 노트가 없을 때만 맨 앞 노트를 키 창으로 만들고, 노트를 눌러 앞으로 온 경우 그 누름이 먼저 처리되도록 한 차례 미룬다.

### 짧은 알림 (`Toast/`, D-041)

- `ToastPresenter`: 한 줄의 글과 동작 하나를 화면 가운데 아래쪽(`ToastPlacement`, `toast-bottom-screen`)에 `toast-hold` 동안 띄운다. `ToastPanel`은 앱을 앞으로 가져오지 않고 키 창이 되지 않는다. 상태(`content`)는 곧바로 바뀌고 창 내리기와 떠 있는 시간은 `TransitionTimer`가 잡는다. 새 알림은 앞의 것을 바꾼다. `ToastView`, `ToastActionButton`(누름을 통째로 받고 첫 누름에 동작)이 모습이다.
- `AppToasts`: 노트 창의 `onMovedToTrash`에 "휴지통으로 보냈습니다"와 "되돌리기"(⌘Z와 같은 `undoOrRestoreTrash`)를, `onTrashUndoEnded`에 알림 거두기를, 캡처 바의 `onCaptured`에 "“제목”에 넣었습니다"와 "열기"(`.openNote`)를 잇는다. 그 노트의 창이 보이면 캡처 알림은 띄우지 않는다.

### 요청 전달 (`AppRouter`)

- `Routing` 구현. `.openNote`, `.newNote`, `.closeNoteWindow`, `.toggleAllNotesHidden`을 `NotePanelCoordinator`로, `.openCapture`, `.openBrowse(anchor:)`를 `QuickPanels`로 넘기고, `.openLibrary`와 `.openSpacePicker`는 `LibraryCoordinator`로 넘긴다. 노트의 `.openAgentWindow`는 AgentWindowCoordinator로 넘긴다. 전역 요청 막대인 `.requestAgent`는 기록만 하고(`unhandled`) `.unconnected`로 답한다. 어느 요청이 이어져 있는지는 `Route.isConnected`(App의 확장) 한 곳에 적고, `Routing.isConnected(_:)`로 기능 모듈에도 알려 준다. `AppCommand.isConnected`가 그것을 읽고, 전역 단축키는 그 값이 참인 동작만 등록하며, 메뉴 막대 메뉴와 Dock 메뉴와 앱 메뉴는 그 값이 거짓인 항목을 고를 수 없게 둔다. 뒤 단계의 화면을 이을 때도 그 줄을 참 쪽으로 옮기고 `route(_:)`에서 그 화면을 부르면 된다.
- 새 노트를 만들거나 노트를 열다가 실패하면 기록과 함께 알림 창으로 까닭을 보여 준 뒤 `.failed`로 답한다(`RouteFailureAlert`). 보낸 쪽이 그 답으로 뒷일을 정한다: 캡처 바는 적은 글을 둔 채 열려 있고, 노트 찾기는 닫히며 쓰던 노트가 다시 키 창이 된다. 캡처 바와 노트 찾기가 보낸 요청(고른 노트의 `.openNote`, "새 노트 만들기"와 캡처 ⌘↵의 `.newNote`)도 같은 길로 돌아오므로 같은 알림이 뜬다. `.openNote`는 그 창을 앞으로 가져오고 키 창으로 만든다(사용자가 고른 것이다, D-025의 "앱이 시킨다").

### 빠른 캡처와 노트 찾기 (`QuickPanels`)

- `QuickPanels`가 `CaptureCoordinator`와 `BrowseCoordinator`를 하나씩 만들어 들고(노트 찾기에는 노트 창과 같은 `WindowStateStore`를 넘긴다), 두 화면과 노트 창 사이의 규칙을 맡는다(D-032). 두 화면은 서로를 모르고 노트 창도 모른다.
  - `toggleCapture()`: 캡처 바를 띄우거나, 떠 있으면 닫는다. ⌃⌥N(전역), 메뉴 막대와 Dock과 앱 메뉴의 "빠른 캡처"가 여기로 온다.
  - `closeVisiblePanel()`: 떠 있는 쪽을 닫는다(esc와 같다). ⌘W와 앱 메뉴의 "창 닫기"가 `AppCommandDispatcher.closeQuickPanel`로 여기에 온다. 떠 있는 것이 없으면 전처럼 키 창인 노트의 창이 닫힌다.
  - `toggleBrowse(anchor:)`: 노트 찾기를 띄우거나, 떠 있으면 닫는다. 붙일 창은 `BrowseAnchor.resolve`가 정한다: 그 노트의 창(`notePanels.window(for:)`)이 보이면 그 상단 줄 아래에 붙이고 그 노트를 목록에서 빼며, 노트가 없거나 창이 보이지 않으면(닫힘, 모두 숨김) 화면 가운데 위쪽에 띄우고 아무 노트도 빼지 않는다. ⌘P는 키 창인 노트(`keyNoteID`)를, 노트의 돋보기는 그 노트를, 메뉴 막대와 Dock과 앱 메뉴의 "노트 찾기"는 `nil`을 보낸다.
  - 한 번에 하나만 열린다. 하나가 열려 있을 때 다른 것을 열면 먼저 것이 닫히고, 그 사이에 노트에게 키 창을 돌려주지 않는다.
  - 같은 누름으로 닫고 다시 열기(돋보기가 상단 줄에 있던 때의 규칙, 지금 상단 줄에는 돋보기가 없다, D-039. 장치는 남겨 둔다): 노트 찾기가 떠 있는 채로 그 노트의 돋보기를 누르면, 누르는 순간 노트 창이 키 창이 되어 노트 찾기가 물러나며 닫히고 떼는 순간 돋보기가 `.openBrowse`를 보낸다. `PointerPressMonitor`(앱 안의 이벤트 감시. 시스템에 이벤트를 보내거나 다른 앱의 이벤트를 보지 않는다)가 누름의 처음과 끝을 알려 주고(`pointerPressBegan()`, `pointerPressEnded()`), 그 누름이 닫은 노트 찾기를 같은 노트에 다시 열려는 요청은 삼킨다. 떠 있을 때 다시 고르면 닫힌다는 규칙(D-032의 1번)이 지켜진다. 다른 곳을 눌러 닫은 뒤의 ⌘P나 메뉴, 다른 노트의 돋보기는 그대로 연다.
  - 키 입력(`KeyFocusReturn`): 여는 순간 키 창이던 노트를 적어 두고, 화면이 포커스를 돌려줄 때라고 알리면(`onDismiss(true)`) 그 노트에게 `notePanels.returnKey(to:)`를 부른다. 그 노트가 그사이 닫혔거나 숨겨져 돌려주지 못했으면, 앱이 앞에 있을 때에 한해 `notePanels.focusFrontmostNote()`로 맨 앞 노트가 이어받는다(앱이 앞에 있지 않으면 쓰던 앱이 입력을 받는다). 열 때 키 창인 노트가 없었으면 어느 노트도 키 창으로 만들지 않는다(다른 앱을 쓰다가 전역 단축키로 열었으면 앱이 앞으로 온 적이 없으므로 시스템이 앞에 있던 앱에 키 입력을 돌려준다). 한쪽을 닫고 다른 쪽을 열 때는 처음에 적어 둔 노트를 이어받는다.
  - 실패: `onFailure`를 받아 `RouteFailureAlert`로 보여 준다("캡처한 글을 넣지 못했습니다", "노트 목록을 읽지 못했습니다"). 알림 창이 키 창을 가져가도 두 화면은 닫히지 않는다. `presentFailure`를 바꿔 넣어 시험한다.
- 두 화면은 `.nonactivatingPanel`이라 앱이 앞에 있지 않아도 키 창이 되어 글을 받고, 닫혀도 노트 창이 저절로 키 창이 되지 않는다(`NotePanelWindow.canBecomeKey`). 확인용 실행(`--debug-passive`)에서는 두 화면도 키 창이 되지 않는다(`refuseKeyWindowsForVerification()`). 그때 글자와 키는 확인용 명령 `capture`, `browse [<노트 id>]`, `panel capture|browse type <글자>`, `panel capture|browse key <이름>`, `panel screen <번호>`로 넣고, 두 화면의 상태(보임, 창 번호, 틀, 줄)는 `dump`의 `quickPanels`로, 모습은 `panel-snapshot capture|browse <파일>`(앱 안에서 그림. 그림자와 뒤 배경 흐림은 담기지 않는다)이나 그 창 번호로 `screencapture -l`을 불러 본다(`DebugQuickPanels`).

### 본문 편집기 (`Editor/`)

- `NoteEditorFactory`: `NotePanelCoordinator`의 `makeBodyEditor`로 넘기는 곳. 노트 창마다 `MarkdownEditor`를 만들어 `MarkdownBodyEditor`로 감싼다. `options: NoteEditorOptions`(체크박스 모양 `checkbox`, 기본 상자. 인라인 코드의 글자색 `inlineCode`, 기본 `accent`. `tokens.json`의 `display.defaults`와 같다)를 바꾸면 떠 있는 편집기에 바로 반영된다. `follow(_:)`가 이 값을 앱 설정(`AppSettingsStore`, `app-settings.json`의 `checkbox`와 `inlineCode`)에 잇는다: 저장된 값으로 시작하고 설정이 바뀔 때마다 따라간다. 바꾸는 쪽(설정 화면이 생기면 거기, 지금은 `AppDelegate.setEditorOptions(_:)`)은 `settings.update { options.write(to: &$0) }`로 적는다. 모르는 이름은 기본값으로 읽는다. `editor(for:)`로 그 노트의 편집기를 찾는다.
- `MarkdownBodyEditor`: `NoteBodyEditing` 어댑터. 편집기의 `documentView`를 본문 자리에 넘기고, 글과 높이 알림을 그대로 잇는다. 처음 넣는 글은 `load(text:foldedLines:)`로 지난번의 접힘과 함께 넣고, 그 뒤에 통째로 들어오는 글(다른 프로그램이 고친 본문)은 접힌 줄 번호를 새 본문에 맞춰 옮긴 뒤 넣는다. 끝에 붙은 글(`appendFromOutside`)과 이 앱의 다른 곳이 바꾼 본문(`applyOutsideChange(to:)`, D-037)은 편집기의 같은 이름 메서드로 넘긴다.
- 접힘 저장(D-018, D-023): `NoteFoldStore`가 `WindowStateStore`의 창 상태에 `foldedLines`와 `foldedLineTexts`(줄마다 그때의 줄 글)만 고쳐 적는다(`stateDirectory/windows.json`). 창 상태와 함께 살고 함께 지워진다. 접힘이 바뀔 때와 글이 바뀔 때(접힌 토글 줄의 글이 달라질 수 있다) 적는다. `FoldPersistence`가 맡는 것: 저장 표기(`stored(_:in:)`: 오름차순, 비면 항목 없음), 다시 열 때 되살리기(`restored(lines:texts:in:)`: 적어 둔 글이 제자리에 있으면 그대로, 없으면 같은 글의 줄이 하나뿐일 때만 그리로 옮기고 없거나 여럿이면 버린다. 제자리는 앞의 접힘이 밀린 만큼 밀린 곳이다. 글 없이 적힌 예전 상태는 줄 번호를 그대로 쓴다), 떠 있는 동안의 줄 번호 옮기기(`remapped`: 앞뒤에서 그대로인 줄을 찾아 바뀐 곳 위의 접힘은 그대로, 아래의 접힘은 늘고 준 줄 수만큼 옮기고, 바뀐 줄에 걸친 접힘은 버린다). 옮긴 줄이 토글인지는 편집기가 다시 거른다.

### 단축키 (`Shortcuts/`)

- `ShortcutTable.standard`(`ShortcutTable.swift`)가 단축키 표(spec 13)의 정본이다. 줄마다 구획(`ShortcutGroup`), 동작 이름, 키(`KeyChord`: `ShortcutKey`와 `ShortcutModifiers`. 키는 가상 키 코드로 적는다), App이 받는 동작(`AppCommand`, 없으면 그 화면이 스스로 받는 줄)을 든다. `tokens.json`의 `shortcuts`와 구획, 동작 이름, 키 표기가 줄마다 같은지 테스트가 견준다. `replacing(_:with:)`가 키를 바꾼 표를 내므로, 설정 화면은 그 표로 `MainMenu.make`와 `GlobalHotKeys.register`를 다시 부르면 된다. "편집" 줄은 보여 주기만 하고 실제로 듣는 키는 편집기의 `EditorShortcuts.bindings`다. 두 목록이 줄마다 같은지(키 자리, 보조 키, 동작) App의 테스트가 견준다.
- `AppCommandDispatcher`: `AppCommand`를 실제 일로 바꾼다. 다른 화면을 여는 일은 `Routing`으로, 지금 노트(키 창인 노트)에 하는 일은 `NotePanelCoordinator`로 보낸다. "노트 안에서 찾기"(⌘F)와 "전체 검색"(⇧⌘F)은 화면이 없어 기록만 한다(`unavailable`). "창 닫기"(⌘W)는 캡처 바나 노트 찾기가 떠 있으면 그것을 닫고(`closeQuickPanel`), 아니면 키 창인 노트의 창을 닫는다. `validateMenuItem`은 여는 화면이 아직 이어지지 않은 동작의 보이는 항목을 고를 수 없게 한다. `undoOrRestoreTrash(_:)`는 ⌘Z를 받아, 방금 휴지통으로 보낸 노트가 있으면(`canUndoTrash`) 되살리고 없으면 첫 응답자의 `undo:`로 넘긴다. 되살리지 못하면 알림 창으로 보여 준다.
- 전역 단축키: `GlobalHotKeys`가 표의 "어디서나" 줄 가운데 여는 화면이 이어진 동작(`AppCommand.isConnected`)만 `HotKeyRegistering`으로 등록한다. 건너뛴 동작은 `skipped`에 남는다(지금은 ⌃⌥N과 ⌃⌥H가 등록되고 ⌃⌥L, ⌃⌥A는 건너뛴다. 하는 일이 없는 키를 시스템 전체에서 차지하지 않는다). 실제 구현 `CarbonHotKeyRegistrar`는 `RegisterEventHotKey`를 독점(`kEventHotKeyExclusive`)으로 부른다. SDK의 `CarbonEvents.h`에 적힌 대로 보통 등록은 겹쳐도 받아들여지고 독점 등록은 겹치면 실패한다(인용과 헤더만으로 정해지지 않는 점은 D-024). 등록기는 받은 `OSStatus`를 그대로 던지고, 등록하지 못한 키는 `failures`에 남아 켤 때 경고로 기록된다(설정 화면이 생기면 이것으로 그 자리에서 알린다).
- 상단 앱 메뉴는 보이는 항목의 `keyEquivalent`에 키를 지정한다(D-340). 시스템이 추가한 항목도 원래 단축키를 표시한다. `KeyCodeMenu`는 AppKit이 글자로 처리하지 못한 키만 물리 키 자리와 보조 키로 찾아 실행한다. 숨은 항목은 시안에 없는 ⌘J와 본문 확대의 보조 키 ⌘=에만 둔다. 편집 단축키는 활성 편집기가 먼저 받고, 서식 메뉴도 같은 편집 동작을 호출한다.

### 메뉴 막대 (`MenuBar/`)

- 메뉴 막대 아이콘은 꺼 둘 수 있다(`AppSettings.showsMenuBarIcon`, 기본 보임. `AppDelegate.setMenuBarIconShown(_:)`이 적고 곧바로 반영한다. 실행 인자 `--menu-bar-icon on|off`가 그 실행에서만 덮어쓴다). 꺼도 모든 기능에 닿는다: 전역 단축키, 앱 안의 단축키, 앱 메뉴(메뉴 막대 메뉴의 항목이 모두 보이는 항목으로 있다. "노트 모두 숨기기"는 숨긴 중이면 "노트 모두 보이기"가 된다), Dock 메뉴(`DockMenu`: 메뉴 막대 메뉴에서 종료만 뺀 같은 항목), Dock 아이콘 누르기(숨긴 노트를 되돌리고, 떠 있는 노트가 없으면 라이브러리를 연다).
- `StatusItemController`: `NSStatusItem`(너비는 그림에 맞춤, `variableLength`)에 `MenuBarIcon.load()`의 18pt 템플릿 이미지(`App/Resources/menubar-icon.pdf`)를 넣고, 메뉴가 열릴 때마다 `StatusMenuModel.entries(areNotesHidden:)`로 다시 채운다. 노트를 숨긴 중이면 "노트 모두 숨기기" 자리에 "노트 모두 보이기"가 온다.
- `StatusMenuModel`: 항목의 순서, 이름, 아이콘(SF Symbols, spec 18.2), 동작(`StatusMenuAction`). 이름과 순서는 `tokens.json`의 `navigation.menuBar`와 같은지 테스트가 견준다. `StatusMenuBuilder`가 `NSMenu`로 만들고 줄은 `MenuBarRowView`(노트의 더 보기 메뉴와 같은 모양: `row-h`, 14pt 아이콘, `hover` 바탕, 불투명 `surface` 바탕), 구분선은 `MenuBarSeparatorView`가 그린다(D-039). `keyEquivalent`는 넣지 않는다.
- 여는 화면이 아직 이어지지 않은 항목(지금은 에이전트에게 요청. `StatusMenuAction.isConnected`)은 자리와 이름을 그대로 두되 고를 수 없게 흐려 둔다(글자와 아이콘 `text-3`, `hover` 바탕 없음). 항목과 차례는 spec 4.3 그대로다(D-034). Dock 메뉴와 앱 메뉴도 같다. "스페이스 옮기기"는 Library로 연결됐다.
- 고른 항목은 `AppCommandDispatcher.performStatusMenu(_:)`가 받는다. 메뉴 막대에서 연 노트 찾기는 `.openBrowse(anchor: nil)`이다(spec 4.1).

### 그 밖

- 설정은 FloatSettings, 에이전트 창은 Agent 타깃에 연결되어 있다.
- 움직임과 상태(D-032): 창이나 뷰의 움직임이 끝났다는 알림(`NSAnimationContext`의 `completionHandler`)에 상태를 걸지 않는다. 화면이 꺼져 있거나 잠겨 있으면 창의 움직임은 나아가지 않고 그 알림도 오지 않는다. 전환이 끝날 때 해야 하는 일(창 내리기, 끝의 값으로 놓기, 숨기고 자리 비우기)은 `Theme`의 `TransitionTimer.after(_:_:)`로 전환 시간 뒤에 잡고, 반대쪽 전환이 시작되면 취소한다. 세 기능의 `animate`(`CaptureStyle`, `BrowseStyle`, `PanelStyle`)는 끝났을 때를 알려 주는 인자가 없다. `swift test`는 화면이 잠겨 있어도 통과해야 한다.
- 자동으로 확인하지 못한 것(실제 한글 입력, 실제 전역 단축키, 키 창이 넘어가는 모습 등)은 `docs/verification-checklist.md`에 손으로 볼 목록으로 모아 두었다.
- SF Symbols 아이콘은 모두 `Theme.symbolImage(_:size:)`로 만든다(크기 토큰의 칸 안에 드는 크기, 눈으로 커 보이는 것만 `iconOptical` 표로 줄임, 1 이하만). 이미지 뷰는 그림을 늘리거나 줄이지 않고(`.scaleNone`) `Theme.symbolFrame`의 틀 가운데에 둔다(D-039).
- 창 그림자와 뒤 배경 흐림은 시스템의 것을 쓴다(`shadow-window`, `blur` 토큰 값은 쓰지 않는다. 까닭은 D-025).

## 5단계 Library와 SpaceIcons

- `LibraryCoordinator`가 일반 NSWindow(880×560, 최소 660×400)와 스페이스 옮기기 팝오버를 소유한다. App이 `Theme`, `NoteStoring`, `SpaceStore`, `WindowStateStore`, `LibraryPreferencesStore`, `Routing`을 주입한다. Features끼리는 import하지 않는다.
- `LibraryModel`이 저장소 변경을 다음 메인 큐 차례에 모아 읽고, 오류는 화면에 유지한다. 열린 창에서는 분마다 날짜와 리마인더를 다시 분류하며 닫으면 타이머를 해제한다.
- `LibraryIndex`는 현재 시각, 달력, 노트, 창 상태를 값으로 받아 날짜, 7일 아카이브, 오늘 합집합, 달별 목록, 개수, 떠 있는 순서를 계산한다.
- `LibrarySelection`/`LibraryPreferences`는 Models, `LibraryPreferencesStore`는 Store다. 보기와 아이콘 고정, 최근, 이미지 목록은 `state/library.json`으로 저장하고 깨진 파일은 기존 JSON 복구 정책을 따른다.
- `SpaceStore.create/update/delete`로 CRUD한다. 삭제는 노트 소속만 해제하며 오류가 나면 스페이스를 남긴다. 휴지통 파일은 복원 때 없어진 스페이스 연결을 해제한다.
- `SpaceIcon`은 기존 세 경우를 읽고 쓰는 형태를 유지하고 `.none`, `.customSymbol(name:hex:)`만 추가했다. `SpaceIcons`의 공용 뷰는 기본 GIF와 업로드 PNG/GIF를 표시한다. ImageIO에서 읽은 프레임과 지연에 따라 이미지를 교체해 화면과 내부 스냅숏에 같은 프레임을 그린다. 뷰가 창에서 떨어지거나 창이 닫히면 재생 타이머를 멈춘다. SVG는 가져올 때 PNG로 렌더링한다.
- 기본 GIF는 `App/Resources/SpaceImages/`가 정본이며 SwiftPM은 심볼릭 링크로, `.app`은 빌드 스크립트의 복사로 사용한다. 사용자 이미지는 `SpaceStore.imageDirectory` 아래에 둔다. 경로 이탈과 외부 심볼릭 링크를 거부한다.
- 노트 창은 `SpaceStore.observe`를 구독하고 상단 줄에 공용 아이콘 뷰를 넣는다. 이름, 색, 이미지를 바꾸면 열린 노트에도 반영된다. 편집기 모듈은 고치지 않았다.
- App은 `.openLibrary`, `.openSpacePicker`를 연결했다. 메뉴 막대, Dock, 앱 메뉴, 노트 찾기와 기존 단축키 표가 `Route.isConnected`를 따라 활성화된다. `.openSpacePicker` 전에 편집 중인 노트의 미전달 변경을 먼저 반영한다.
- 메뉴 막대 아이콘은 18pt 그림의 투명한 좌우 열만 제거한다. `variableLength`에 시스템 여백을 맡긴다. 그림의 배율, 높이는 유지한다.
- 디버그 명령: `library`, `library-close`, `library-select today|all|floating|trash|reminders|archive:YYYY-MM|<spaceID>`, `library-open <noteID>`, `library-expand <spaceID>`, `library-icon <spaceID> <imageName>`, `library-dump <file>`, `library-snapshot <file>`, `icon-snapshot|icon-symbol-snapshot|icon-emoji-snapshot <spaceID> <file>`, `reopen`. 스냅숏은 앱 안에서 그린다. `--debug-passive`는 라이브러리도 키 창이 되지 않게 한다.
- 실행 중인 사용자 앱을 덮어쓰지 않으려면 `FLOATING_NOTES_APP_DIR=<작업 폴더>/app scripts/build-app.sh debug`를 쓴다. `run.sh`에도 같은 변수가 전달된다.

## 6단계 예정과 외부 연동

- `Models.ScheduleItem`: 시작, 종료 기반 종류, 날짜만/완료/삭제 대기, 제목, TodoAnchor, 로컬, 외부 ID, 수정, 동기화 시각, 마지막 동기화 값과 실패. `Note.schedules`가 정본이고 `reminder`는 호환 투영이다. `displayedSchedule(at:)`은 가장 이른 다가오는 항목, 없으면 지난 항목을 고른다.
- `Store`는 `schedules` JSON을 한 줄 frontmatter로 저장한다. 기존 reminder는 안정된 ID로 읽고 옛 빌드용 날짜를 병기한다. 알 수 없는 줄 보존 정책은 유지한다. `LegacyStage5` 테스트 코드는 HEAD의 실제 codec을 이름만 바꿔 고정한 것이다.
- Core `Scheduling`의 `ScheduleService`가 저장소 변경과 CalendarBridge.onChange를 직렬 처리한다. EventKitBridge만 EventKit을 import하며 저장소 생성은 지연된다. SystemReminderNotifier만 UserNotifications를 import한다. 둘의 가짜 구현은 실제 권한, 계정을 전혀 쓰지 않는다.
- Feature `Reminders`는 Theme, Models, Store, DateTime을 참조한다. `ReminderEditorCoordinator`가 팝오버를, `ReminderEditorModel`이 입력, 범위 검증, 항목 단위 저장을 담당한다. Features끼리 참조하지 않는다. AppRouter가 `.openReminderEditor`를 노트 상단 anchor와 연결한다.
- 권한 요청 의도는 `ReminderEditorModel.onSave`와 `CaptureWriter.onScheduleCreated`(새 노트 캡처는 `AppRouter.onScheduleCreated`)에서 항목 ID로 전달하고 AppDelegate가 `ScheduleService.register`에 연결한다. 일반 저장 관찰은 권한을 요청하지 않는다. 옛 항목은 명시 저장과 다가오는 미완료 조건을 모두 확인한다(D-071).
- AppDelegate는 실행 옵션에 따라 실제/가짜 의존성을 조립한다. `--calendar fake`는 두 외부 API를 모두 대체하며 `--debug-passive`도 강제로 같은 경로를 쓴다. 종료 시 서비스 관찰과 편집 화면을 닫는다.
- Theme는 Models에 의존해 공통 ReminderPresentation으로 날짜, 범위, 아이콘, 임박을 포맷한다. NotePanel과 Library가 공유한다. Capture는 DateTimeExpression.isDateOnly와 end를 ScheduleItem에 전달하고 범위 글자를 제거한다. Editor와 NotePanel은 Core DateTime의 제안, 수락 계약을 공유한다.
- 확인용 명령: `reminder-editor <noteID>`, `reminder-close`, `reminder-snapshot <file>`, `fake-delay|fake-complete|fake-delete <scheduleID>`. 가짜 외부 변경도 실제 서비스의 onChange 경로를 지난다. 스냅숏은 앱 내부 렌더링이다.


## 본문, 제목 날짜 제안 (D-074~D-077)

- Core `DateTime`: 기존 Capture의 읽기 파일을 그대로 옮겼다. `DateTimeParser.firstExpression`, `DateTimeExpression`을 공개하며 Capture의 기존 파서 테스트도 같은 모듈을 검증한다. `InlineDateProposal`은 커서 조건, 제외 범위, 지난 시각 검증과 종일 범위 변환만 더한다.
- 표시(D-078): 본문 TextKit 2 문단, 제목 임시 속성에 단일 밑줄만 얹고 원문 속성으로 저장하지 않는다. 종류, 전체 날짜는 접근성 도움말이다. 제안 줄 번호, 줄 수를 보관하고 이전, 새 줄만 invalidate한다(줄 수 변경만 전체 갱신). 미리 보기 뷰, 문단 위 공간, 제목/창 높이 조정은 제거했다.
- Feature `Editor/EditorController+DateTime`: MarkdownDocument의 코드/링크/감춘 기호 범위를 제외해 제안한다. 기존 EditorCommands 삭제, 정리, 안전 검증으로 원문 변경을 미리 계산하고, 받기를 독립된 UndoRecord로 묶는다. `dateEffect` ID는 바깥 변경의 기록 위치 이동을 그대로 따른다. 기록에서 떨어진 효과는 정리한다.
- Feature `NotePanel/Views/TitleField+DateTime`: 한 줄 필드의 제안, Tab, Escape, 선택 관찰. AppKit 텍스트 저장소를 수정하며 native undo 한 동작에 글자와 예정 효과를 함께 등록한다. 한글 조합 중에는 글자를 건드리지 않는다.
- Core `Scheduling.InlineScheduleWriter`: 항목 단위 생성, 갱신, 삭제/복원. 삭제는 기존 ScheduleService 삭제 대기, 재시도 경로를 사용하며 최신 외부 연결을 지킨다. `Models.InlineScheduleSource`가 출처를 저장하고 Note.body 변경 시 안전하게 식별되는 줄만 따라간다.
- AppDelegate가 writer를 만들고 NoteEditorFactory.onAcceptDate와 NotePanelCoordinator.onAcceptTitleDate에 잇는다. Feature 간 import는 없고 Editor, Capture, NotePanel은 Core DateTime을 참조한다. 권한 의도는 수락된 항목 ID만 ScheduleService.register로 보낸다.
- 디버그 `date-suggestion <id> [UTF-16 위치]`, `input-command <id|title:id> tab|escape|undo|redo`는 자기 프로세스 입력 칸만 사용한다. `editor` 덤프에 dateSuggestionHelp 접근성 도움말을 포함한다. 실제 계정, 시스템 이벤트, 클립보드는 사용하지 않는다.

- L1과 E2(D-086~D-088): Theme.CommandTextField가 조합 보호, 밑줄, Return과 Escape를 제공한다. LibraryPreview는 목록 표시 제목과 본문을 만들며 저장 제목은 바꾸지 않는다. Models.ScheduleDestination은 외부 캘린더의 이름과 sRGB 색 값만 담는다. CalendarBridge.destination은 권한 요청 없이 조회하고 App이 ScheduleService를 통해 ReminderEditorCoordinator에 주입한다. AppSettings.scheduleDateFormat은 열린 NotePanel, Library, Reminders에 동시에 전달한다.

## 7단계 설정

- Feature `FloatSettings`는 Theme, Models, Scheduling, Store, AgentRunner에 의존한다. AgentSettings는 엔진별 계정 확인과 명시적인 로그인, 취소, 로그아웃의 수명을 관리한다. SettingsValues는 저장 형식, SettingsModel은 저장 콜백과 권한별 대상 선택, SettingsCoordinator는 단일 창을 맡는다. 다른 Feature를 import하지 않는다.
- AppSettingsStore가 JSON을 원자적으로 쓴 뒤 SettingsApplication과 NoteEditorFactory가 이미 열린 화면을 갱신한다. AppDelegate가 ShortcutTable의 표시 행, 저장소, ScheduleService를 주입한다.
- CalendarBridge가 권한 상태, 쓰기 가능한 대상, 시스템 기본값을 제공한다. ID 선택은 새 항목 생성과 E2가 공유하고 연결된 항목은 기존 대상을 유지한다.

FloatingNotes의 AgentRequestCoordinator가 현재 실행과 앱 전체 대기 순서를 소유한다. AgentExecution은 AgentRunner와 Store를 사용한다. Agent는 대화 파일과 관찰 가능한 화면 상태를 공유하고 실행, 재시도, 지금 보내기, 대상 선택, 노트 열기를 클로저로 App에 전달한다. Capture는 전송 콜백만 호출한다. 두 Features 사이의 의존은 없다.

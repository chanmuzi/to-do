# to-do (플로팅 노트) — 에이전트 라우터

이 파일이 규약의 단일 진입점이다. 아래 판정표로 작업 유형을 정하고 **그 행의 파일만** 읽는다.
`docs/spec/` 전체를 한꺼번에 읽지 않는다.

macOS 네이티브 플로팅 메모·투두 앱. SwiftUI + AppKit, 개인용, macOS 우선.

## 기본 규칙

1. **화면 값은 토큰을 거친다.** 색·크기·간격·시간을 코드에 직접 적지 않는다. 정본은 `App/Resources/tokens.json`.
2. **컴포넌트는 서로를 직접 참조하지 않는다.** 경계와 의존 방향은 `docs/architecture.md`를 따른다.
3. **결정은 바뀔 수 있다.** `docs/spec/`은 현재의 기본값이지 불변 규칙이 아니다.
   - 사용자가 다른 결정을 내리면 그 결정이 우선한다. 해당 spec 장을 직접 고치고 `docs/decisions.md`에 한 줄을 남긴다.
   - spec과 `docs/decisions.md`의 현행 항목이 다르면 decisions가 우선한다(더 최신이다).
   - spec과 시안(`design/handoff/design.html`)이 다르면 spec이 우선한다.
   - 결정 목록을 세션마다 다시 확인하지 않는다. 작업 중인 영역과 관련된 항목만 찾아본다.
4. **미결정 항목은 임시 값으로 진행하고 기록한다.** `docs/spec/20-open-questions.md`의 괄호 값을 쓰고, 그렇게 했다는 것을 `docs/decisions.md`에 남긴다.
5. **단계가 끝나면 실제로 확인한다.** 빌드해서 실행하고 `design/handoff/screens/`의 해당 화면과 견준다. 확인하지 못한 것은 못 했다고 보고한다.
6. **`design/`은 로컬 전용 참고 자료다.** 수정하지 않고 커밋되지 않는다. 필요한 파일만 `App/Resources/`로 복사해 쓴다.
7. 임시 파일은 세션 scratchpad에만 둔다. 레포 트리에 두지 않는다.

## 작업유형 판정표

| 작업 | 읽을 것 |
| --- | --- |
| 어떤 장이 있는지 모를 때 | `docs/spec/index.md` |
| 프로젝트 뼈대, 모듈 추가·분리 | `docs/architecture.md` |
| 테마 계층, 색·글꼴·치수 | `docs/spec/03-tokens.md`, `App/Resources/tokens.json` |
| 노트 창, 메뉴 막대 | `docs/spec/04-windows.md`, `05-note-panel.md`, `19-native-notes.md` |
| 본문 편집기 | `docs/spec/06-editor.md`, `13-shortcuts.md`, `19-native-notes.md` |
| 빠른 캡처, 노트 찾기 | `docs/spec/07-capture.md`, `08-browse.md`. 날짜와 시간 읽기를 고칠 때는 `07a-datetime.md` |
| 라이브러리, 스페이스 아이콘 | `docs/spec/09-library.md`, `10-icon-picker.md` |
| AI 패널, 에이전트 연결 | `docs/spec/11-ai-panel.md`, `docs/decisions.md`의 에이전트 항목 |
| 테마 설정, 단축키 표 | `docs/spec/12-settings.md`, `13-shortcuts.md` |
| 호버·포커스·움직임 판단 | `docs/spec/02-rules.md`, `14-states.md`, `15-motion.md` |
| 가장자리 경우, 접근성 | `docs/spec/16-edge-cases.md`, `17-accessibility.md` |
| 아이콘·이미지·글꼴 파일 | `docs/spec/18-assets.md` → `design/handoff/`에서 필요한 것만 복사 |
| 저장 방식, 과거 결정 확인 | `docs/decisions.md` |
| 화면 모양 확인 | `design/handoff/screens/NN-*.png` 중 해당 화면 한두 장 |

UI를 새로 만들거나 고칠 때는 `docs/spec/02-rules.md`(21줄)를 함께 읽는다.

## 정본 위치

- 명세: `docs/spec/` (장별 파일, 목차는 `index.md`)
- 결정 기록: `docs/decisions.md`
- 모듈 구조: `docs/architecture.md`
- 디자인 토큰: `App/Resources/tokens.json`
- 시안·캡처·에셋 원본: `design/handoff/` (로컬 전용, gitignore)
- 이 Mac에만 해당하는 메모: `CLAUDE.local.md` (gitignore)

## Git

- 구현 단계마다 브랜치를 나누고 PR로 합친다. 스쿼시하지 않는다.
- 커밋과 push는 사용자가 요청할 때만 한다.

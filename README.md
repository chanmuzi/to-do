# to-do

작은 메모 창 여러 개를 화면 위에 항상 띄워 두는 macOS용 메모·투두 앱 "플로팅 노트"(가칭).
SwiftUI + AppKit, 개인용. 아직 개발 중이며 진행 상황은 `docs/roadmap.md`에 있다.

## 요구 사항

- macOS 26 이상
- Xcode 26 이상(Swift 6.2 이상). Xcode 프로젝트 없이 Swift Package Manager로만 빌드한다.
- 외부 의존성 없음

## 설치

```sh
git clone https://github.com/chanmuzi/to-do.git
cd to-do
scripts/install-app.sh
```

- 릴리스 빌드를 만들어 `/Applications/플로팅 노트.app`으로 넣는다. `/Applications`에 쓸 수 없으면 `~/Applications`에 넣는다.
  `sudo`는 쓰지 않는다.
- 이미 실행 중이면 먼저 정상 종료를 요청하고(저장하지 못한 노트가 있으면 앱이 묻는다) 끝난 뒤 바꿔 넣는다.
- 설치한 뒤에는 Spotlight나 Launchpad에서 "플로팅 노트"로 찾아 실행한다.
- 서명하지 않은 개인용 빌드다. 다른 Mac으로 복사하면 Gatekeeper가 막을 수 있다.

### 업데이트

```sh
git pull
scripts/install-app.sh
```

### 설치하지 않고 실행

```sh
scripts/run.sh          # 릴리스 빌드 후 build/FloatingNotes.app 실행
scripts/build-app.sh    # 빌드만 (debug 인자를 주면 디버그 빌드)
```

## 사용

- 앱을 켜면 지난번에 띄워 둔 노트가 그 자리에 다시 뜬다. 노트가 하나도 없으면 빈 노트를 하나 띄운다.
- 노트 창을 닫아도 노트는 지워지지 않는다. 다시 열려면:
  - 메뉴 막대 아이콘이나 Dock 아이콘 메뉴(오른쪽 클릭)의 **노트 찾기**
  - 앱이 앞에 있을 때 ⌘P
  - 떠 있는 노트가 없을 때 Dock 아이콘을 누르면 가장 최근에 고친 노트가 뜬다.
- 어디서나 쓰는 단축키: ⌃⌥N 빠른 캡처, ⌃⌥H 떠 있는 노트 모두 숨기기와 다시 보이기.
  전체 표는 `docs/spec/13-shortcuts.md`에 있다.
- 라이브러리, 리마인더, 설정 화면, AI 패널은 아직 만들지 않았다. 메뉴에는 흐리게 보인다.

### 노트가 저장되는 곳

- `~/Library/Application Support/FloatingNotes/notes/`: 노트 하나가 마크다운 파일 하나다. 다른 편집기로 고쳐도 앱이 따라 읽는다.
- `~/Library/Application Support/FloatingNotes/state/`: 창 위치와 크기, 앱 설정.
- 휴지통으로 보낸 노트는 `notes/.trash/`로 옮겨진다. 보낸 직후 알림의 "되돌리기"로 되살릴 수 있다.
- 환경 변수 `FLOATING_NOTES_DIR`를 주면 그 폴더 하나만 쓴다.

### 실행 옵션

| 옵션 | 뜻 |
| --- | --- |
| `--notes-dir <경로>` | 그 폴더의 노트만 읽고 쓴다. 실제 노트를 건드리지 않고 시험할 때 쓴다. |
| `--appearance light\|dark` | 시스템 설정과 상관없이 라이트나 다크로 띄운다. |
| `--menu-bar-icon on\|off` | 이번 실행에서 메뉴 막대 아이콘을 보이거나 감춘다. |

예: `scripts/run.sh --notes-dir /tmp/fn-notes --appearance dark`

## 개발

```sh
swift build --package-path App
swift test --package-path App
```

- 작업 규칙과 문서 안내: `AGENTS.md`
- 진행 상황과 다음 할 일: `docs/roadmap.md`
- 구현 명세: `docs/spec/index.md`
- 결정 기록: `docs/decisions.md`
- 모듈 구조: `docs/architecture.md`

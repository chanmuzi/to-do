# Float

작은 메모 창 여러 개를 화면 위에 항상 띄워 두는 macOS용 메모, 투두 앱 "Float".
SwiftUI + AppKit, 개인용. 아직 개발 중이며 진행 상황은 `docs/roadmap.md`에 있다.

## 요구 사항

- macOS 26 이상
- Xcode 26 이상(Swift 6.2 이상). Xcode 프로젝트 없이 Swift Package Manager로만 빌드한다.
- 외부 의존성 없음

## 설치

```sh
git clone https://github.com/chanmuzi/to-do.git
cd to-do
scripts/create-signing-identity.sh # 처음 한 번: 이 Mac에서 계속 쓸 서명 인증서
scripts/install-app.sh
```

- 릴리스 빌드를 만들어 `/Applications/Float.app`으로 넣는다. `/Applications`에 쓸 수 없으면 `~/Applications`에 넣는다.
  `sudo`는 쓰지 않는다.
- 이미 실행 중이면 먼저 정상 종료를 요청하고(저장하지 못한 노트가 있으면 앱이 묻는다) 끝난 뒤 바꿔 넣는다.
- 같은 설치 폴더에서 이전 이름의 앱을 찾으면 번들 ID를 확인한다. ID가 일치하면 새 앱 설치 후 이전 앱을 휴지통으로 옮기고 옮긴 경로를 출력한다.
- 설치한 뒤에는 Spotlight나 Launchpad에서 "float"로 찾아 실행한다. 앱, Finder, Spotlight의 표시 이름은 Float이고 앱 파일 이름은 `Float.app`이다.
- `create-signing-identity.sh`는 로그인 키체인에 `Float Local Code Signing` 자체 서명 인증서와 개인 키를 넣는다.
  유효기간은 10년(3,650일), 용도는 코드 서명이다. 이미 해당 이름의 인증서가 있으면 아무것도 바꾸지 않는다.
  **보통 암호를 묻지 않으며, 키체인이 잠겨 있으면 macOS의 `security`가 직접 묻는다.**
  스크립트가 로그인 암호를 직접 읽거나 명령 인자로 전달하지 않는다. 관리자 암호나 신뢰 등록은 필요하지 않다.
  임시 개인 키 파일은 작업 종료 시 지운다. Apple 개발자 계정은 필요 없다.
  마지막 확인에서 `Matching identities`에 인증서가 나오면 된다. `CSSMERR_TP_NOT_TRUSTED`와 `0 valid identities`는 신뢰 등록을 하지 않은 자체 서명에서 예상되는 표시다.
- 같은 인증서와 번들 ID를 계속 사용하면 빌드 내용이 바뀌어도 지정 요구사항이 유지된다.
  인증서를 삭제, 재생성하면 달라지므로 업데이트할 때는 생성 스크립트를 다시 실행할 필요가 없다.
  임시 서명에서 처음 전환할 때의 권한 재승인과 실제 EventKit 권한 유지 여부는 별도 확인이 필요하다.
- Apple 공증을 받지 않은 개인용 빌드다. 다른 Mac으로 복사하면 Gatekeeper가 막을 수 있다.

신뢰 설정을 바꾸지 않는 근거는 [Apple 코드 서명 가이드](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html)의
`anchor trusted`를 요구하지 않는 지정 요구사항 검증 규칙이다.
권한과 지정 요구사항의 관계는 [TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)을 따른다.

### 업데이트

```sh
git pull
scripts/install-app.sh
```

### 설치하지 않고 실행

```sh
scripts/run.sh          # 릴리스 빌드 후 build/Float.app 실행
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

확인용 묶음을 실행 중인 앱과 분리하려면 `FLOATING_NOTES_APP_DIR=/원하는/폴더 scripts/build-app.sh debug`를 사용합니다. `scripts/run.sh`도 같은 변수를 따르며 기본은 `build/`입니다.

서명은 `FLOATING_NOTES_SIGN_IDENTITY`로 이름(또는 SHA-1 지문)을 지정할 수 있다. `-`를 지정하면 임시 서명을 쓴다.
지정하지 않으면 키체인의 `Float Local Code Signing`을 사용하고, 없으면 한 줄 경고 후 임시 서명으로 빌드한다.
명시한 인증서의 서명 실패는 그대로 실패로 보고한다. Hardened Runtime은 켜지 않는다.
생성, 빌드 스크립트 모두 `FLOATING_NOTES_KEYCHAIN=/임시/키체인.keychain-db`로 확인용 키체인을 지정할 수 있으며 검색 목록을 바꾸지 않는다.
자동 확인에만 `FLOATING_NOTES_KEYCHAIN_PASSWORD`로 명시한 임시 키체인(`/private/tmp` 또는 `/private/var/folders` 아래)의 암호를 넘길 수 있다.
보조 스크립트 `scripts/signing-keychain.swift`가 Security API로 잠금 상태를 확인하고 임시 키체인을 연다. 임시 암호도 명령 인자로 전달하지 않으며, 로그인, 시스템 키체인 및 그곳으로 향하는 심볼릭 링크는 이 경로에서 거부한다.

### 브랜드 에셋

종이 노트 창 아이콘을 사용한다. 빌드는 Icon Composer의 라이트, 다크 겹을 컴파일하고 7개 크기의 PNG로 ICNS를 함께 만든다.
`swift scripts/generate-brand-icons.swift <미리보기 폴더>`로 앱 아이콘 겹, PNG, 메뉴 막대 SVG와 PDF를 다시 만든다.
1024px 캔버스의 본체는 824px(80.46875%), 사방 여백은 100px이며 시스템 메모 앱의 본체 비율을 따른다.
앱 파일 이름은 `Float.app`이고 원본 `Info.plist`의 `CFBundleDisplayName`과 `CFBundleName`은 모두 `Float`다(D-175).
앱 메뉴는 표시 이름을 읽고, `swift run`과 테스트에서는 Float를 기본값으로 쓴다.
번들 ID, 실행 파일, 타깃, 모듈, 노트와 설정 저장 위치는 D-062를 따른다.
[Apple 표시 이름 규칙](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPFileSystem/Articles/DisplayNames.html)을 따른다.

## 리마인더와 캘린더 권한

노트의 더 보기 → **리마인더 설정**에서 날짜와 시각을 정합니다. 종료를 지정하면 일정, 종료가 없으면 리마인더입니다. 빠른 캡처의 `내일 오후 3~4시 회의`도 일정이 되며 본문에는 투두 '회의'가 남습니다. 노트마다 여러 항목을 추가할 수 있고 상단과 라이브러리는 가장 이른 다가오는 것 하나를 보여 줍니다.

처음 실제 등록할 때 macOS가 묻는 **캘린더 전체 접근**, **미리 알림 접근**을 허용해 주세요. 앱을 켜기만 할 때는 묻지 않습니다. 시스템 기본 캘린더와 기본 미리 알림 목록을 쓰며, Mac Apple 캘린더에 연결된 Google 계정도 EventKit으로 동기화합니다. 기본 대상 선택은 현재 Apple 앱 설정에서 하고 Float 설정 화면은 다음 단계입니다.

iPhone과 Mac의 같은 iCloud 계정에서 미리 알림을 켜면 시간, 완료, 삭제가 양방향으로 반영됩니다. 외부 제목 변경은 예정 제목만 바꾸고 노트 원문을 보호합니다. 연결된 리마인더는 Apple 미리 알림이 알립니다. 연동 권한이 없거나 거부하면 실패 표시 없이 앱 안에 보존합니다. 권한은 설정에서 새 항목을 저장하거나 빠른 캡처로 새 예정이 생길 때만 요청합니다. 옛 리마인더는 설정에서 그 항목을 열어 저장한 경우에만 다가오는 미완료 항목을 등록합니다. 권한 확인 후 실제 연동이 실패하면 작은 느낌표를 표시하며, 시각 지정 항목에는 Float 알림 권한을 받아 대체 알림을 냅니다. 날짜만인 항목에는 임의 알림 시각을 붙이지 않습니다.

[설치 후 Mac, iPhone 확인 순서](docs/verification-checklist.md#6단계-설치-앱과-iphone에서-직접-확인)를 따라 확인할 수 있습니다. Apple 계정의 동기화 주기에 따라 반영이 늦을 수 있습니다. 같은 고정 서명 인증서를 유지해야 업데이트 뒤 권한 유지 여부를 확인할 수 있습니다(D-063). 확인용 실행의 `--calendar fake`와 디버그 `--debug-passive`는 실제 계정, 권한에 접근하지 않습니다.

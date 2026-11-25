## 19. 네이티브 구현 메모

- **노트 창**: `NSPanel`에 `.nonactivatingPanel`, `.resizable`, `.fullSizeContentView`. `hidesOnDeactivate = false`, `isFloatingPanel = true`, `backgroundColor = .clear`. 핀이 켜지면 `level = .floating`.
- **바탕**: `NSVisualEffectView`(뒤 배경 흐림) 위에 `surface` 색 레이어를 `opacity` 알파로. 노트 색은 그 위에 팔레트 색 레이어를 `tint-mix` 알파로 한 장 더 얹습니다.
- **호버**: `NSTrackingArea`(`.mouseEnteredAndExited`, `.activeAlways`)로 받아 `NSAnimationContext`(0.18초)로 알파와 글자색을 바꿉니다. 숨긴 버튼도 레이아웃에는 항상 포함합니다.
- **포커스**: 따로 할 일이 없습니다. 키 창이 아니면 `NSTextView`가 커서를 그리지 않습니다. `insertionPointColor`만 `accent`로 맞춥니다.
- **마우스 모양**: AppKit의 버튼과 메뉴는 원래 화살표입니다. SwiftUI에서 `onHover`로 손 모양을 넣지 않습니다. 본문에서 열 수 있는 링크의 각 글자 조각은 `NSCursor.pointingHand`를 사용합니다(D-322).
- **편집기**: TextKit 2. 마크다운을 속성으로 입히고, 커서가 있는 줄에서만 기호를 보입니다. 인라인 코드와 코드 블록의 둥근 바탕은 `NSTextLayoutFragment`를 상속해 `draw(at:in:)`에서 글자 뒤에 먼저 그립니다. 인라인 구간의 사각형은 `enumerateTextSegments(in:type:options:)`로 얻습니다.
- **창 높이**: 내용 높이가 바뀌면 `setFrame(_:display:animate:)`로 같은 시간에 맞춰 바꿉니다. 창의 위쪽 가장자리를 고정하고 아래로 늘립니다.
- **오른쪽 아래 버튼**: 스크롤 뷰 위에 겹친 별도 뷰. 텍스트 뷰의 크기에 영향을 주지 않습니다.
- 목록, 투두, 토글의 왼쪽 칸은 단계별로 들여 씁니다. 세로 막대는 인용문에 그립니다(D-188).
- **메뉴 막대**: `NSStatusItem`과 `NSMenu`. 메뉴 항목에 `keyEquivalent`를 넣지 않습니다(단축키를 표시하지 않기 위해).
- **전역 단축키**: `RegisterEventHotKey`(또는 KeyboardShortcuts 같은 라이브러리). 등록이 실패하면 다른 앱이 쓰는 키입니다.
- **기본 이미지**: 프레임 PNG를 템플릿으로 읽어 `contentTintColor`로 물들이고, manifest의 순서와 시간대로 바꿉니다. `magnificationFilter = .nearest`.
- **사용자 GIF**: `NSImageView`의 `animates = true`. 창이 보이지 않을 때는 멈춥니다.
- **색 직접 고르기**: `NSColorPanel`.
- **기호 검색**: SF Symbols 이름 목록은 시스템이 주지 않습니다. 이름 목록을 앱에 넣어 두고 `NSImage(systemSymbolName:)`로 그립니다.


### 본문 블록 저장 형식

⇧↵는 앞줄 끝에 이스케이프되지 않은 백슬래시 하나와 개행을 기록합니다. 다음 줄은 주인 줄의 들여쓰기를 반복하고 본문만 담습니다. 예를 들어 아래 두 줄은 한 투두입니다(D-313).

```markdown
- [ ] 초안 읽기\
두 번째 단락 확인
```

편집기는 개행 앞의 연속 백슬래시가 홀수일 때 마지막 하나를 줄바꿈 기호로 사용합니다. 문서 끝, 코드 울타리 바로 앞이나 안의 백슬래시와 짝수 개의 백슬래시는 줄을 연결하지 않습니다. 기존 원문도 같은 규칙으로 읽습니다. 원문 복사는 이 표기를 보존합니다. 표준 Markdown 내보내기는 목록 머리와 이어지는 줄의 들여쓰기를 맞춥니다. 한 줄 제목이나 문단을 끊는 내용에는 인라인 `<br>`를 사용합니다. HTML 내보내기는 한 항목 안에 `<br>`를 둡니다.

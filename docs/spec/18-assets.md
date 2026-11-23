## 18. 에셋

### 18.1 Float 앱 아이콘 (D-124)

종이 노트 창 원본은 `scripts/generate-brand-icons.swift`에 있다. 앱 표시 이름은 Float다.

| 자산 | 쓰임 |
| --- | --- |
| `AppIcon.icon` | Icon Composer의 그룹 목록은 앞에서부터 노트 창, 그림자, 바탕 순서다. 라이트와 다크 원본을 분리하고 색조는 시스템이 렌더링한다. 빌드에서 actool로 Assets.car를 만들고 CFBundleIconName으로 지정한다. |
| `AppIcon.appiconset` | 1024 캔버스의 824 타일, 사방 여백 100. 16, 32에서는 글 줄을 덜어 낸다. iconutil로 AppIcon.icns도 함께 넣는다. |
| `menubar-icon.svg`, `menubar-icon.pdf` | 18pt 캔버스에 16pt 노트 창, 선 1.5pt. 런타임은 템플릿 PDF의 투명한 좌우 열을 자른다. |

`swift scripts/generate-brand-icons.swift <미리보기 폴더>`는 앱 리소스를 갱신하고 PNG 미리보기를 지정한 폴더에 쓴다.

### 18.2 화면 아이콘 (`assets/symbols/`)

화면에 쓴 선 아이콘은 SF Symbols로 대신하기를 권합니다. 기호 탭이 SF Symbols 전체를 쓰므로 같은 계열로 맞추는 편이 자연스럽습니다. 굵기는 regular, 크기는 표의 값에 맞춥니다. 시안에서 그린 모양 그대로가 필요하면 같은 이름의 SVG를 템플릿 이미지로 씁니다.

| 파일 | 쓰는 곳 | SF Symbols | 시안에서의 크기(pt) |
| --- | --- | --- | --- |
| `search.svg` | 노트 찾기, 검색 칸 | `magnifyingglass` | 14, 12 |
| `more.svg` | 더 보기 | `ellipsis` | 14 |
| `plus.svg` | 새 노트, 추가 | `plus` | 14, 16 |
| `trash.svg` | 휴지통으로 보내기, 휴지통 | `trash` | 14 |
| `close.svg` | 창 닫기, 닫기 | `xmark` | 13 |
| `pin-on.svg` | 항상 위에 고정(켜짐) | `pin.fill` | 13 |
| `pin-off.svg` | 항상 위에 고정(꺼짐) | `pin` | 13 |
| `clock.svg` | 리마인더(예정, 지남) | `clock` | 12 |
| `bell.svg` | 리마인더(임박), 리마인더 설정 | `bell` | 12, 14 |
| `briefcase.svg` | 스페이스 예시(회사), 스페이스 옮기기 | `briefcase` | 13, 14 |
| `house.svg` | 스페이스 예시(개인) | `house` | 13 |
| `check.svg` | 체크박스, 고른 에이전트, 끝난 도구 내역 | `checkmark` | 9, 13, 11 |
| `chev-right.svg` | 토글(접힘), 접힌 구획 | `chevron.right` | 12, 9 |
| `chev-down.svg` | 토글(펼침), 펼친 구획, 고르기 | `chevron.down` | 12, 9, 11 |
| `drop.svg` | 노트 색 | `drop` | 14 |
| `sparkle.svg` | AI 패널, 에이전트 | `sparkle` | 14, 15 |
| `library.svg` | 라이브러리 | `sidebar.left` | 14 |
| `capture.svg` | 빠른 캡처 | `terminal` | 14 |
| `eye-off.svg` | 노트 모두 숨기기 | `eye.slash` | 14 |
| 순서 손잡이 | 설정의 보기 순서. 16단위에서 x 6, 10과 y 4, 8, 12의 교차점에 반지름 1.1인 원을 그린다 | GRIP 벡터 | 14 |
| `sliders.svg` | 설정(사이드바 보기에는 쓰지 않음) | `slider.horizontal.3` | 14, 15 |
| `keyboard.svg` | 단축키 | `keyboard` | 14 |
| `sun.svg` | 보기: 오늘 | `sun.max` | 14 |
| `layers.svg` | 보기: 떠 있는 노트 | `square.on.square` | 14 |
| `stack.svg` | 보기: 전체 노트 | `line.3.horizontal` | 14 |
| `archive.svg` | 아카이브 | `archivebox` | 14 |
| `image.svg` | 아이콘 바꾸기, 이미지 끌어다 놓는 자리 | `photo` | 14, 18 |
| `text.svg` | 이름 바꾸기 | `character.cursor.ibeam` | 14 |
| `copy.svg` | 코드 블록 복사 | `doc.on.doc` | 13 |
| `send.svg` | 보내기 | `arrow.up` | 14 |
| `plug.svg` | 에이전트 연결 필요 | `powerplug` | 13 |
| `spinner.svg` | 읽는 중 | (SwiftUI의 ProgressView 또는 직접 그린 호) | 11 |
| `mail.svg` | 출처: 메일 | `envelope` | 12 |
| `calendar.svg` | 출처: 캘린더 | `calendar` | 12 |
| `doc.svg` | 출처: 문서 | `doc.text` | 12 |
| `link.svg` | 기호 목록 예시 | `arrow.up.right` | 15 |
| `book.svg` | 기호 목록 예시 | `book` | 15 |
| `code.svg` | 기호 목록 예시 | `chevron.left.forwardslash.chevron.right` | 15 |
| `star.svg` | 기호 목록 예시 | `star` | 15 |
| `heart.svg` | 기호 목록 예시 | `heart` | 15 |
| `flag.svg` | 기호 목록 예시 | `flag` | 15 |
| `cart.svg` | 기호 목록 예시 | `cart` | 15 |
| `flask.svg` | 기호 목록 예시 | `flask` | 15 |
| `pen.svg` | 기호 목록 예시 | `pencil` | 15 |
| `note.svg` | 기호 목록 예시 | `doc` | 15 |

노트 더 보기 메뉴의 그림 크기는 `component.menu-icon`(12pt), 정렬 칸은 `icon-l`(14pt)입니다(D-058).

SF Symbols로 그리는 닫기(`xmark`, 노트 메뉴의 "창 닫기" 등)와 더 보기(`ellipsis`)는 칸 크기를 유지하고 `iconOptical`의 `.85` 배율로 그림만 줄입니다(D-159). 노트 창 위쪽의 닫기와 더 보기는 확정 시안의 벡터 경로(`NoteButtonGlyph`)로 그려 이 값을 쓰지 않습니다.

SF Symbols 이름은 SF Symbols 앱에서 한 번 확인하세요. 버전에 따라 이름이 다를 수 있습니다.

### 18.3 기본 이미지 (`assets/pixel/`)

이미지 탭에 처음부터 들어 있는 넷입니다. 16x16 칸의 픽셀 그림이고 모두 움직입니다.

| id | 이름 | 움직임 | 프레임 수 | 한 바퀴 |
| --- | --- | --- | --- | --- |
| `terminal` | 터미널 | 커서가 깜빡임 | 2 | 1000ms |
| `computer` | 컴퓨터 | 화면의 커서가 깜빡임 | 2 | 1100ms |
| `keyboard` | 키보드 | 키가 차례로 눌림 | 4 | 1800ms |
| `mouse` | 마우스 | 왼쪽 버튼이 두 번 눌림 | 2 | 1800ms |

- `<id>/frame-N.png`(와 `@2x`, `@3x`): 템플릿 이미지. 잉크는 검정, 옅은 잉크는 검정 30%, 나머지는 투명. 앱에서 글자색으로 물들입니다.
- `manifest.json`: 프레임 파일, 보여 줄 순서, 프레임마다 머무는 시간(ms).
- `<id>.gif`, `<id>-dark.gif`: 같은 그림의 GIF(64px). 사용자가 올리는 GIF를 재생하는 경로를 시험할 때 씁니다.
- 16pt로 놓을 때는 보간을 끕니다(가장 가까운 픽셀). 그래야 픽셀이 또렷합니다.

### 18.4 글꼴 (`app-fonts/`)

| 파일 | 쓰임 | 라이선스 |
| --- | --- | --- |
| `PretendardVariable.ttf` | 본문, 버튼, 제목 | OFL 1.1 (`LICENSE-Pretendard.txt`) |
| `D2Coding.ttf`, `D2CodingBold.ttf` | 시간, 개수, 날짜, 코드 | OFL 1.1. npm 패키지의 WOFF를 TTF로 바꾼 것. 배포할 때는 https://github.com/naver/d2codingfont 의 원본과 라이선스 전문을 쓰세요 |

`fonts/`의 woff2는 `design.html`을 보기 위한 것이고 앱에는 넣지 않습니다.


### 에이전트 설정 로고

App/Resources/AgentLogos의 Claude와 OpenAI 벡터는 Simple Icons 13.21.0의 CC0 원본 경로를 사용한다. Claude는 주황 타일과 흰 그림, OpenAI는 흰 타일과 검은 그림이다. 목록 타일은 28pt, 상세 제목 타일은 20pt에 그림 12pt다. [Simple Icons 13.21.0](https://github.com/simple-icons/simple-icons/tree/13.21.0)

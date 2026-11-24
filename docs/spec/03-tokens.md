## 3. 토큰

`tokens.json`이 원본입니다. 아래 표는 그 값을 옮긴 것입니다.

### 3.1 글꼴과 크기

| 역할 | 글꼴 | 크기 / 줄 높이 | 굵기 |
| --- | --- | --- | --- |
| 노트 제목 (상단 줄) | Pretendard | `fs-title` 13px / `lh-ui` 16px | `fw-title` 600 |
| 본문 제목 1 (#) | Pretendard | `fs-h1` 21px / `lh-h1` 30px | `fw-h1` 650 |
| 본문 제목 2 (##) | Pretendard | `fs-h2` 18px / `lh-h2` 27px | `fw-h2` 650 |
| 본문 제목 3 (###) | Pretendard | `fs-h3` 16px / `lh-h3` 25px | `fw-h3` 600 |
| 본문 | Pretendard | `fs-body` 14px / `lh-body` 24px | `fw-body` 400 |
| 본문 굵게 | Pretendard | `fs-body` 14px / `lh-body` 24px | `fw-strong` 650 |
| 라이브러리 목록 제목 | Pretendard | `library-header-font` 15px / `lh-body` 24px | `fw-title` 600 |
| 라이브러리 묶음 머리 (`libraryListHeading`) | Pretendard | `fs-list-heading` 15px / `lh-list-heading` 19px | `fw-title` 600 |
| 라이브러리 줄 제목 | Pretendard | `fs-row` 14px / `lh-row` 18px | `fw-body` 400 |
| 라이브러리 줄 미리 보기 | Pretendard | `fs-row-sub` 12.5px / `lh-ui` 16px | `fw-body` 400 |
| 정보 (시간, 개수) | D2Coding | `fs-ui` 13px / `lh-ui` 16px | `fw-ui` 400 |
| 임박한 리마인더 | D2Coding | `fs-ui` 13px / `lh-ui` 16px | `fw-ui-strong` 600 |
| 날짜, 보조 숫자 | D2Coding | `fs-micro` 12px / `lh-micro` 14px | `fw-ui` 400 |
| 라이브러리 사이드바 시작 시각 | Pretendard, 같은 폭 숫자 | `fs-micro` 12px | `fw-body` 400 |
| 인라인 코드 | D2Coding | `fs-code` 12.5px / `lh-body` 24px | `fw-body` 400 |
| 코드 블록 | D2Coding | `fs-code` 12.5px / `lh-code` 20px | `fw-body` 400 |
| 캡처 입력 | Pretendard | `fs-capture` 14px / `lh-body` 24px | `fw-body` 400 |

- 라이브러리 묶음의 들임 20px은 그림 칸 `library-heading-icon` 14px과 이름까지의 간격 `chrome-pad-end` 6px의 합입니다. 묶음 사이에는 `sp-5` 24px을 씁니다.
- `font-body`: Pretendard. `font-ui`, `font-micro`, `font-mono`: D2Coding.
- 본문 글꼴과 크기는 사용자가 바꿀 수 있습니다(12장). 본문 크기는 12~17pt이며 제목과 코드의 크기는 본문에 비례합니다.

### 3.2 색

| 토큰 | 쓰임 | 라이트 | 다크 |
| --- | --- | --- | --- |
| `surface` | 창 바탕 | `#FFFFFF` | `#1E1E1E` |
| `surface-2` | 사이드바, 보조 바탕 | `#F6F6F6` | `#262626` |
| `surface-3` | 입력칸 | `#EDEDED` | `#303030` |
| `selected` | 고른 줄과 세그먼트 바탕 | `#DEDAD4` | `#46423D` |
| `format-active` | 노트 서식 막대의 켜진 버튼 바탕 | `rgba(96,76,52,.14)` | `rgba(224,208,186,.16)` |
| `row-title` | 목록 제목 | `#393632` | `#D5D2CE` |
| `hover` | 마우스를 올렸을 때의 바탕 효과 (버튼, 줄, 칸 공통. 어떤 바탕색 위에서도 보이도록 반투명) | `rgba(96,76,52,.08)` | `rgba(224,208,186,.12)` |
| `text` | 본문 글자 | `#000000` | `#ECECEC` |
| `text-2` | 보조 글자 | `#6B6B6B` | `#A3A3A3` |
| `text-3` | 흐린 글자(완료, 자리표시) | `#8F8F8F` | `#7C7C7C` |
| `line` | 안쪽 구분선 | `rgba(0,0,0,.09)` | `rgba(255,255,255,.09)` |
| `outline` | 창 테두리 | `rgba(0,0,0,.10)` | `rgba(255,255,255,.14)` |
| `guide` | 라이브러리 날짜 줄의 세로선, 설정 값 메뉴 테두리 | `rgba(0,0,0,.12)` | `rgba(255,255,255,.18)` |
| `accent` | 강조색(사용자 변경) | `#000000` | `#FFFFFF` |
| `on-accent` | 강조색 위 글자 | `#FFFFFF` | `#000000` |
| `warn` | 리마인더 임박과 지남 (글자, 아이콘 색) | `#E5342B` | `#FF796E` |
| `hl-1-bg` | 형광펜 1 바탕 | `#FFEB85` | `rgba(255,220,80,.19)` |
| `hl-1-fg` | 형광펜 1 글자 | `#000000` | `#ECECEC` |
| `hl-2-bg` | 형광펜 2 바탕 | `#E4E4E4` | `rgba(255,255,255,.14)` |
| `hl-2-fg` | 형광펜 2 글자 | `#000000` | `#ECECEC` |
| `hl-3-bg` | 형광펜 3 바탕 | `#FFD2CC` | `rgba(255,120,110,.27)` |
| `hl-3-fg` | 형광펜 3 글자 | `#000000` | `#ECECEC` |
| `hl-4-bg` | 형광펜 4 바탕 | `#CFE5FF` | `rgba(110,170,255,.28)` |
| `hl-4-fg` | 형광펜 4 글자 | `#000000` | `#ECECEC` |
| `code-bg` | 인라인 코드 바탕 (테두리 없음) | `rgba(0,0,0,.065)` | `rgba(255,255,255,.09)` |
| `codeblock-bg` | 코드 블록 바탕 (테두리 없음) | `rgba(0,0,0,.04)` | `rgba(255,255,255,.065)` |
| `code-fg` | 코드 블록 글자, 인라인 코드 글자("plain") | `#000000` | `#ECECEC` |
| `code-accent` | 인라인 코드 글자("accent", 기본. 규칙 1의 예외) | `#C8372E` | `#FFD1C9` |
| `link` | 링크 | `#000000` | `#ECECEC` |
| `shadow-window` | 노트 창 그림자 | `0 18px 44px -12px rgba(0,0,0,.28),0 4px 12px -2px rgba(0,0,0,.10)` | `0 20px 48px -12px rgba(0,0,0,.60),0 4px 12px -2px rgba(0,0,0,.32)` |
| `shadow-pop` | 캡처 바, 메뉴 그림자 | `0 28px 70px -16px rgba(0,0,0,.38),0 6px 16px -4px rgba(0,0,0,.12)` | `0 30px 80px -16px rgba(0,0,0,.70),0 6px 16px -4px rgba(0,0,0,.38)` |

- `accent`는 사용자가 바꿉니다. 프리셋: 잉크(라이트 `#000000`, 다크 `#FFFFFF`), 그린(라이트 `#1A8F4C`, 다크 `#3DDC84`), 앰버(라이트 `#B26A00`, 다크 `#FFB000`), 코발트(라이트 `#1F4FFF`, 다크 `#6E8BFF`), 그래파이트(라이트 `#6B6B6B`, 다크 `#9A9A9A`)
- 선택 바탕은 불투명하고 호버는 같은 계열의 반투명 색이다. 둘이 겹치면 선택을 우선한다.

다크 D1에서 작은 보조 글자는 지정 토큰을 기준으로 실제 바탕의 WCAG 대비가 4.5:1에 이르는 최소 8비트 회색까지 밝힙니다. 노트에서는 재질, 팔레트, 코드 블록과 선택 바탕도 고려합니다.

### 3.3 팔레트 (노트 바탕, 스페이스 아이콘 색)

| 토큰 | 이름 | 값 |
| --- | --- | --- |
| `tint-1` | 안개 | `#8E9AAF` |
| `tint-2` | 물빛 | `#6C8EAD` |
| `tint-3` | 세이지 | `#9AA5A0` |
| `tint-4` | 이끼 | `#8FA08A` |
| `tint-5` | 모래 | `#B8AA8E` |
| `tint-6` | 살구 | `#C2A090` |
| `tint-7` | 장미 | `#B5939B` |
| `tint-8` | 라일락 | `#A39BA8` |

- 노트 바탕 = `surface`에 팔레트 색을 `tint-mix`(26%)만큼 섞은 색. 라이브러리와 노트 찾기의 줄 바탕 = 팔레트 색을 `tint-mix-row`(18%) 알파로.
- 글자, 선, 아이콘 색은 바꾸지 않습니다.
- 노트 데이터에는 팔레트 키(`tint-1` 등)만 저장합니다. 팔레트를 바꾸면 노트도 함께 바뀝니다.
- 기본은 색 없음입니다.

### 3.4 치수, 모서리, 재질, 움직임

| 종류 | 토큰 | 값 | 쓰임 |
| --- | --- | --- | --- |
| 간격 | `sp-1` | `4px` | 아이콘과 글자 사이 |
| 간격 | `sp-2` | `8px` | 크롬 요소 사이 |
| 간격 | `sp-3` | `12px` | 창 안쪽 여백(좁게) |
| 간격 | `sp-4` | `16px` | 창 안쪽 여백 |
| 간격 | `sp-5` | `24px` | 구획 사이 |
| 간격 | `sp-6` | `32px` | 큰 구획 사이 |
| 모서리, 높이 | `r-window` | `10px` | 창 모서리 |
| 모서리, 높이 | `r-control` | `5px` | 버튼, 입력칸 |
| 모서리, 높이 | `r-chip` | `4px` | 태그, 칩 |
| 모서리, 높이 | `r-check` | `3px` | 체크박스 |
| 모서리, 높이 | `r-hl` | `2px` | 형광펜 |
| 모서리, 높이 | `bw` | `1px` | 테두리 두께 |
| 모서리, 높이 | `chrome-h` | `32px` | 창 크롬 높이 |
| 모서리, 높이 | `r-code` | `4.5px` | 인라인 코드 |
| 모서리, 높이 | `r-codeblock` | `8px` | 코드 블록 |
| 구성 요소 | `doc-pad` | `12px 16px 20px` | 노트 본문 안쪽 여백 (위 오른쪽 아래 왼쪽). 아래쪽은 오른쪽 아래 버튼 자리 |
| 구성 요소 | `gutter` | `21px` | 체크박스, 토글, 글머리표 칸 너비 (D-043) |
| 구성 요소 | `indent` | `21px` | 하위 계층 한 단계 들여쓰기 (D-043) |
| 구성 요소 | `check-size` | `14px` | 체크박스 크기 |
| 구성 요소 | `icon-gap` | `3px` | 아이콘과 바로 옆 글자 사이 |
| 구성 요소 | `pick-gutter` | `24px` | AI 후보 목록의 체크박스 칸 너비 |
| 구성 요소 | `ctl-h` | `24px` | 버튼과 선택 칸 높이 |
| 구성 요소 | `row-h` | `28px` | 사이드바 행 높이 |
| 구성 요소 | `caret-w` | `1.5px` | 입력 커서 너비 (얇은 일반 커서, D-042) |
| 구성 요소 | `quote-bar-w` | `2px` | 인용문 왼쪽 막대 너비 (D-044) |
| 구성 요소 | `quote-pad` | `8px` | 인용문 블록 왼쪽 끝에서 글자까지, 막대 뒤 공백 6pt (D-061) |
| 구성 요소 | `code-pad-x` | `5px` | 인라인 코드 상자의 좌우 안쪽 여백 |
| 구성 요소 | `code-gap` | `1.5px` | 인라인 코드 상자의 바깥 간격 |
| 구성 요소 | `code-h` | `16px` | 인라인 코드 상자의 높이 (본문 줄 22 안에서. 제목에서는 비례해 커짐) |
| 구성 요소 | `code-drop` | `1px` | 인라인 코드 상자를 줄 가운데에서 아래로 내리는 양 |
| 구성 요소 | `code-rise` | `0.5px` | 인라인 코드 글자의 기준선을 올리는 양 |
| 구성 요소 | `codeblock-pad-x` | `12px` | 코드 블록의 좌우 안쪽 여백 |
| 구성 요소 | `codeblock-pad-y` | `9px` | 코드 블록의 위아래 안쪽 여백 |
| 구성 요소 | `codeblock-gap` | `5px` | 코드 블록의 위아래 바깥 간격 |
| 구성 요소 | `link-field-w` | `220px` | 링크 주소를 적는 칸의 너비 |
| 구성 요소 | `icon-btn` | `24px` | 테두리 없는 아이콘 버튼의 기본 크기 |
| 구성 요소 | `note-top-button-size` | `20px` | 노트 상단 줄 아이콘 칸 |
| 구성 요소 | `note-top-button-gap` | `2px` | 노트 상단 줄 아이콘 칸 사이 |
| 구성 요소 | `note-top-pad-end` | `8px` | 노트 상단 줄의 오른쪽 여백 |
| 구성 요소 | `menubar-icon` | `18px` | 메뉴 막대 아이콘 캔버스 크기 (그림은 그 안에서 16pt) |
| 구성 요소 | `browse-w` | `300px` | 노트 찾기 목록 너비 |
| 구성 요소 | `chrome-gap` | `6px` | 노트 상단 줄의 요소 사이 |
| 구성 요소 | `chrome-pad-end` | `6px` | 노트 하단 서식 버튼 줄의 좌우 여백 |
| 구성 요소 | `icon-s`, `icon-m`, `icon-l` | `12px`, `13px`, `14px` | 선 아이콘 크기 (18.2의 표) |
| 구성 요소 | `icon-btn-gap` | `2px` | 나란히 놓인 아이콘 버튼 사이 (노트 오른쪽 아래) |
| 구성 요소 | `swatch-size`, `swatch-gap`, `swatch-ring` | `13px`, `5px`, `1.5px` | 노트 색 칸 크기, 사이, 고른 칸의 테두리 두께이자 띄우는 거리 |
| 구성 요소 | `menu-icon` | `12px` | 노트 메뉴 그림 크기(정렬 칸은 `icon-l` 14, D-058) |
| 구성 요소 | `note-menu-width` | `210px` | 노트 더 보기 메뉴 너비 |
| 구성 요소 | `menu-w` | `226px` | 메뉴 최소 너비 |
| 구성 요소 | `note-body-lines-default`, `note-body-lines-min` | `6`, `4` | 고정 창의 기본 본문 줄 수와 최소 줄 수. 본문 한 줄은 설정 줄 높이에 기본 글자와 현재 글자의 크기 차이를 반영한다. 상단 줄, 구분선, 본문 위아래 여백을 더한다. |
| 구성 요소 | `note-w`, `note-w-min`, `note-w-max` | `340px`, `260px`, `560px` | 노트 창 너비: 기본, 최소, 최대 (D-158) |
| 재질 | `opacity` | `.92` | 창 불투명도 (포커스와 상관없이 같음) |
| 재질 | `blur` | `24px` | 배경 흐림 반경 |
| 재질 | `tint-mix` | `26%` | 노트 바탕에 팔레트 색을 섞는 비율 |
| 재질 | `tint-mix-row` | `18%` | 라이브러리 줄 바탕에 섞는 비율 |
| 움직임 | `dur` | `180ms` | 전환 시간 (호버로 나타나고 사라지는 것 모두) |
| 움직임 | `ease` | `cubic-bezier(.25,.1,.25,1)` | 전환 곡선 |
| 움직임 | `caret-blink` | `530ms` | 입력 커서가 켜져 있는 시간이자 꺼져 있는 시간 (D-042, 임시) |


### 3.5 라이브러리와 아이콘 선택 (D-051)

편집기 장식은 `component.editor-*` 토큰으로 관리한다. 기존 값은 유지한다: 체크 테두리 1.25, 체크 그림 9와 선 1, 대괄호 칸 28, 글머리 원 5와 사각 4와 왼쪽 여백 4, 꺾쇠 12와 선 0.875, 줄 수 간격 8, 형광펜 여백 2/1, 링크 칸 간격 3과 안쪽 여백 6, 복사 버튼 여백 4. 제목 1/2/3의 전후 여백은 4/4, 6/2, 6/0이다. 복사 아이콘은 기존 `icon-m`과 공용 광학 보정을 쓴다(D-085).

- `library-w/h`: 920/640, `library-min-w/h`: 660/400, `library-sidebar-w`: 240.
- `library-header-h` 52, `library-section-head-h` 22, `library-section-gap` 11, `library-sidebar-inset` 10. `library-more-size` 20, 그림은 `menu-icon` 12다.
- `library-row-leading` 20을 양쪽에 쓰고 `library-row-pad-y` 9, `library-row-gap` 3을 적용한다. `upcoming-detail-w` 216, 상세 여백은 10/12/6이다. 일정 호버 지연은 없다.
- 라이브러리 목록 선택과 호버의 좌우 여백은 `sp-2` 8, 상하 여백은 `library-row-highlight-inset-y` 2다. 오른쪽 노트 목록의 맨 아래에는 여백이 없다(D-183).
- `library-sidebar-row-gap`: 2, `library-upcoming-time-w`: 120. 사이드바 선택 경계와 긴 절대 시간의 말줄임을 위한 값이다.
- `icon-picker-w/pad`: 248/10, `icon-picker-columns`: 7, `icon-picker-cell-h/icon/ring`: 28/15/1.25.
- `icon-picker-grid-h/drop-h`: 140/96, `icon-import-max-pixels`: 64.

- 6단계: `component.reminder-editor-w` 320px(설정 팝오버), `component.library-reminder-w` 200px(범위를 담는 예정 열).

- E2: `reminder-input-h` 36, `schedule-marker-w` 12, `schedule-event-bar-w` 3, `schedule-reminder-circle` 11, `schedule-row-h` 48, `schedule-list-max-h` 240. 구획 이름은 font-body/fs-micro/fw-ui-strong, 예정 입력은 font-body/fs-capture/fw-title, 시간은 font-ui/fs-row-sub/fw-ui를 조합한다(D-088).

### 한 줄 입력칸 토큰 확인 (D-132)

- [ ] 공용 입력칸에 화면 역할의 글꼴 토큰을 한 번 전달한다. 입력값과 자리 글자에 같은 NSFont를 사용한다.
- [ ] 커서는 ThinCaretFieldEditor의 `caret-w`, `accent`, `caret-blink`를 따른다.
- [ ] 한 줄 입력칸을 추가할 때 실제 글꼴로 포커스 전후와 첫 입력 전후의 시작점 및 기준선을 검사한다.

노트 찾기는 `browse-w` 300, `browse-r` 12, `browse-pad` 5, `browse-find-h` 30, `browse-header-h` 20, `browse-row-h` 26, `browse-gap` 9, `browse-row-r` 6, `browse-pin-w` 20을 쓴다. 메뉴 바탕은 `menu-surface`, 선택은 `menu-highlight`, 검색 자리 글자는 `text-4`다.

### 설정 창 (D-147, D-148)

창 크기는 settings-w 700, settings-content-h 540이다. settings-top은 52, settings-sidebar-w는 200, settings-sidebar-row는 28이다. 배경 높이는 26이며 선택과 호버는 selected와 hover다. 제목은 library-header-font 15, 굵기 600이다.

한 줄 이동 줄의 호버 높이는 `settings-nav-single-line-hover-h` 30pt다. 두 줄 이동 줄은 줄 높이에서 위아래로 `settings-nav-two-line-hover-inset-y` 4pt씩 뺀다. 둘 다 반경은 `settings-nav-hover-radius` 6pt, 내용 양끝에서 `settings-nav-hover-outset` 6pt다. 카드 행은 settings-row 36, 세그먼트 높이는 24, 슬라이더 폭은 148, 동작 버튼 높이는 22다. 단축키의 글자 칸은 15pt, 보조 키 자간은 1.5pt다. 미리보기 폭은 340, settings-flash는 600ms다. 에이전트 배너 높이는 44, 툴팁 꼬리는 9다. 경고에는 warn을 쓴다.

설정의 떠 있는 줄은 `settings-reorder-radius` 8pt, 사이드바 줄은 `sidebar-reorder-radius` 6pt다. 카드 여백은 sp-3, 손잡이와 글자 사이는 sp-2, 손잡이는 icon-m, 정보 아이콘은 icon-s다. 두 줄의 그림자 토큰은 `shadow-reorder`다. 밝은 그림자는 확정 CSS의 POP, 어두운 농도는 기존 어두운 팝오버를 따른다.

### 에이전트 창과 얼굴 (1단계 PR 1)

정지 가장자리는 `agent-edge-idle` 1pt, 밝은 색은 `agent-edge-a` #A597DB와 `agent-edge-b` #E6B89A다. 어두운 초안은 #80759F와 #AD8D79다. 작업 가장자리 1.5pt와 번짐 3pt는 각각 `agent-edge-working`, `agent-edge-glow`에 둔다.

얼굴은 icon-s 13pt, icon-m 14pt, agent-face-medium 16pt, agent-face-large 20pt다. 에이전트 창의 머리와 입력 높이는 chrome-h, 조작은 icon-btn과 icon-btn-gap을 쓴다. 머리 왼쪽은 14pt, 얼굴과 이름 사이는 9pt, 입력 글자는 13.5pt다. 상태별 주기와 점, 물결의 지연은 motion의 agent 키를 사용한다. 움직임 줄이기에서는 정지 벡터를 그린다.

작업 중 가장자리 주기는 3초, 글자 띠는 2.2초다. 밝은 agent-shimmer는 #6A5B9E, 알림 바탕 agent-bg-a/m/b는 #EEEBF7, #F5F0F2, #F9EFE8이다. 다크 초안은 D-220을 따른다. 대기 줄 높이는 24pt, 레이블 11pt, 요청 글 12.5pt, 묶음 좌우 12pt, 아래 6pt다. agent-queue-action-size(20pt)와 agent-queue-action-gap(2pt)은 각각 독립적으로 바꾼다.

대화 줄과 사이드바는 notice-dot 6pt, warn을 공유한다. corner-button 40pt 원 안에 agent-face-large 20pt를 놓는다. shadow-agent-corner는 표시 시안의 12pt 아래, 흐림 32pt, 퍼짐 -8pt와 0.5pt 윤곽이다. 어두운 그림자 농도는 기존 팝오버에서 가져온 초안이다.

### 변경 제안

`agent-dash`는 밝을 때 rgba(138,122,180,.55), `diff-add`는 #E4F3E6이다. 어두운 값은 각각 rgba(184,168,219,.65), #304538인 초안이다. 빼는 줄의 `diff-del`은 밝을 때 #FDE6E2, 어두울 때 #523836(임시)이다. 미리보기의 기호 칸은 `proposal-gutter` 28pt, 글은 13pt, 줄은 22pt다. 넓은 제안 페이지 목록 폭은 330pt, 대화 결과 연결 줄의 최소 높이는 30pt다. 점은 기존 6pt, 아이콘 버튼은 24pt다.

### 대화 메뉴와 다시 보내기

대화 명령 메뉴는 `conversation-menu-width` 170pt, 재사용하는 삭제 확인은 `confirmation-width` 236pt를 쓴다. 두 표면의 모서리는 `r-window` 10pt다.

예정의 노트 미리보기와 목록 사이는 `proposal-preview-gap` 14pt다. 다가오는 일정 미리보기는 최대 폭 `proposal-upcoming-width` 240pt, 줄 높이 `proposal-upcoming-row` 24pt를 쓴다. 칩과 일정 표시는 기존 예정 토큰을 사용한다.

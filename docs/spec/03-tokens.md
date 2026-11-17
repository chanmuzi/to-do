## 3. 토큰

`tokens.json`이 원본입니다. 아래 표는 그 값을 옮긴 것입니다.

### 3.1 글꼴과 크기

| 역할 | 글꼴 | 크기 / 줄 높이 | 굵기 |
| --- | --- | --- | --- |
| 노트 제목 (상단 줄) | Pretendard | `fs-title` 12px / `lh-ui` 16px | `fw-title` 600 |
| 본문 제목 1 (#) | Pretendard | `fs-h1` 17px / `lh-h1` 26px | `fw-h1` 700 |
| 본문 제목 2 (##) | Pretendard | `fs-h2` 15px / `lh-h2` 24px | `fw-h2` 650 |
| 본문 제목 3 (###) | Pretendard | `fs-h3` 13px / `lh-h3` 22px | `fw-h3` 650 |
| 본문 | Pretendard | `fs-body` 13px / `lh-body` 22px | `fw-body` 400 |
| 본문 굵게 | Pretendard | `fs-body` 13px / `lh-body` 22px | `fw-strong` 650 |
| 라이브러리 목록 제목 | Pretendard | `fs-pane-title` 14px / `lh-body` 22px | `fw-strong` 650 |
| 라이브러리 줄 제목 | Pretendard | `fs-row` 12.5px / `lh-row` 18px | `fw-title` 600 |
| 라이브러리 줄 미리 보기 | Pretendard | `fs-row-sub` 11.5px / `lh-ui` 16px | `fw-body` 400 |
| 정보 (시간, 개수) | D2Coding | `fs-ui` 12px / `lh-ui` 16px | `fw-ui` 400 |
| 임박한 리마인더 | D2Coding | `fs-ui` 12px / `lh-ui` 16px | `fw-ui-strong` 700 |
| 날짜, 보조 숫자 | D2Coding | `fs-micro` 11px / `lh-micro` 14px | `fw-ui` 400 |
| 인라인 코드 | D2Coding | `fs-code` 11.5px / `lh-body` 22px | `fw-body` 400 |
| 코드 블록 | D2Coding | `fs-code` 11.5px / `lh-code` 20px | `fw-body` 400 |
| 캡처 입력 | Pretendard | `fs-capture` 14px / `lh-body` 22px | `fw-body` 400 |

- `font-body`: Pretendard. `font-ui`, `font-micro`, `font-mono`: D2Coding.
- 본문 글꼴과 크기는 사용자가 바꿀 수 있습니다(12장). 크기를 바꾸면 줄 높이는 크기의 약 1.54배를 짝수로 맞춥니다.

### 3.2 색

| 토큰 | 쓰임 | 라이트 | 다크 |
| --- | --- | --- | --- |
| `surface` | 창 바탕 | `#FFFFFF` | `#000000` |
| `surface-2` | 사이드바, 보조 바탕 | `#F6F6F6` | `#0E0E0E` |
| `surface-3` | 입력칸, 칩, 호버 | `#EDEDED` | `#1C1C1C` |
| `hover` | 마우스를 올렸을 때의 바탕 효과 (버튼, 줄, 칸 공통. 어떤 바탕색 위에서도 보이도록 반투명) | `rgba(0,0,0,.07)` | `rgba(255,255,255,.11)` |
| `text` | 본문 글자 | `#000000` | `#F0F0F0` |
| `text-2` | 보조 글자 | `#6B6B6B` | `#9A9A9A` |
| `text-3` | 흐린 글자(완료, 자리표시) | `#8F8F8F` | `#6E6E6E` |
| `line` | 안쪽 구분선 | `rgba(0,0,0,.09)` | `rgba(255,255,255,.10)` |
| `outline` | 창 테두리 | `rgba(0,0,0,.16)` | `rgba(255,255,255,.20)` |
| `guide` | 들여쓰기 안내선 | `rgba(0,0,0,.12)` | `rgba(255,255,255,.16)` |
| `accent` | 강조색(사용자 변경) | `#000000` | `#FFFFFF` |
| `on-accent` | 강조색 위 글자 | `#FFFFFF` | `#000000` |
| `warn` | 리마인더 임박과 지남 (글자, 아이콘 색) | `#E5342B` | `#F2473C` |
| `hl-1-bg` | 형광펜 1 바탕 | `#FFEB85` | `rgba(255,220,80,.32)` |
| `hl-1-fg` | 형광펜 1 글자 | `#000000` | `#F0F0F0` |
| `hl-2-bg` | 형광펜 2 바탕 | `#E4E4E4` | `rgba(255,255,255,.18)` |
| `hl-2-fg` | 형광펜 2 글자 | `#000000` | `#F0F0F0` |
| `hl-3-bg` | 형광펜 3 바탕 | `#FFD2CC` | `rgba(255,120,110,.34)` |
| `hl-3-fg` | 형광펜 3 글자 | `#000000` | `#F0F0F0` |
| `hl-4-bg` | 형광펜 4 바탕 | `#CFE5FF` | `rgba(110,170,255,.36)` |
| `hl-4-fg` | 형광펜 4 글자 | `#000000` | `#F0F0F0` |
| `code-bg` | 인라인 코드 바탕 (테두리 없음) | `rgba(0,0,0,.065)` | `rgba(255,255,255,.13)` |
| `codeblock-bg` | 코드 블록 바탕 (테두리 없음) | `rgba(0,0,0,.04)` | `rgba(255,255,255,.085)` |
| `code-fg` | 코드 블록 글자, 인라인 코드 글자("plain") | `#000000` | `#F0F0F0` |
| `code-accent` | 인라인 코드 글자("accent", 기본. 규칙 1의 예외) | `#C8372E` | `#F47B70` |
| `link` | 링크 | `#000000` | `#F0F0F0` |
| `shadow-window` | 노트 창 그림자 | `0 18px 44px -12px rgba(0,0,0,.28),0 4px 12px -2px rgba(0,0,0,.10)` | `0 20px 48px -12px rgba(0,0,0,.80),0 4px 12px -2px rgba(0,0,0,.50)` |
| `shadow-pop` | 캡처 바, 메뉴 그림자 | `0 28px 70px -16px rgba(0,0,0,.38),0 6px 16px -4px rgba(0,0,0,.12)` | `0 30px 80px -16px rgba(0,0,0,.90),0 6px 16px -4px rgba(0,0,0,.50)` |

- `accent`는 사용자가 바꿉니다. 프리셋: 잉크(라이트 `#000000`, 다크 `#FFFFFF`), 그린(라이트 `#1A8F4C`, 다크 `#3DDC84`), 앰버(라이트 `#B26A00`, 다크 `#FFB000`), 코발트(라이트 `#1F4FFF`, 다크 `#6E8BFF`), 그래파이트(라이트 `#6B6B6B`, 다크 `#9A9A9A`)
- `hover`는 반투명이라 색을 입힌 노트나 줄 위에서도 같은 진하기로 보입니다. 흰 바탕(다크에서는 검정 바탕) 위에서는 `surface-3`와 같은 색이 됩니다. 시안의 일부 버튼은 `surface-3`로 칠했지만 앱에서는 올렸을 때의 바탕을 모두 `hover`로 통일합니다.

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
| 모서리, 높이 | `chrome-h` | `28px` | 창 크롬 높이 |
| 모서리, 높이 | `r-code` | `4.5px` | 인라인 코드 |
| 모서리, 높이 | `r-codeblock` | `8px` | 코드 블록 |
| 구성 요소 | `doc-pad` | `10px 14px 18px` | 노트 본문 안쪽 여백 (위 오른쪽 아래 왼쪽). 아래쪽은 오른쪽 아래 버튼 자리 |
| 구성 요소 | `gutter` | `19px` | 체크박스, 토글, 글머리표 칸 너비 (D-043) |
| 구성 요소 | `indent` | `19px` | 하위 계층 한 단계 들여쓰기 (D-043) |
| 구성 요소 | `check-size` | `13px` | 체크박스 크기 |
| 구성 요소 | `icon-gap` | `3px` | 아이콘과 바로 옆 글자 사이 |
| 구성 요소 | `pick-gutter` | `24px` | AI 후보 목록의 체크박스 칸 너비 |
| 구성 요소 | `ctl-h` | `22px` | 버튼과 선택 칸 높이 |
| 구성 요소 | `row-h` | `26px` | 사이드바 행 높이 |
| 구성 요소 | `caret-w` | `1.5px` | 입력 커서 너비 (얇은 일반 커서, D-042) |
| 구성 요소 | `quote-bar-w` | `2px` | 인용문 왼쪽 막대 너비 (D-044) |
| 구성 요소 | `quote-pad` | `8px` | 인용문 블록 왼쪽 끝에서 글자까지, 막대 뒤 공백 6pt (D-061) |
| 구성 요소 | `code-pad-x` | `4.5px` | 인라인 코드 상자의 좌우 안쪽 여백 |
| 구성 요소 | `code-gap` | `1.5px` | 인라인 코드 상자의 바깥 간격 |
| 구성 요소 | `code-h` | `16px` | 인라인 코드 상자의 높이 (본문 줄 22 안에서. 제목에서는 비례해 커짐) |
| 구성 요소 | `code-drop` | `1px` | 인라인 코드 상자를 줄 가운데에서 아래로 내리는 양 |
| 구성 요소 | `code-rise` | `0.5px` | 인라인 코드 글자의 기준선을 올리는 양 |
| 구성 요소 | `codeblock-pad-x` | `12px` | 코드 블록의 좌우 안쪽 여백 |
| 구성 요소 | `codeblock-pad-y` | `9px` | 코드 블록의 위아래 안쪽 여백 |
| 구성 요소 | `codeblock-gap` | `5px` | 코드 블록의 위아래 바깥 간격 |
| 구성 요소 | `link-field-w` | `220px` | 링크 주소를 적는 칸의 너비 |
| 구성 요소 | `icon-btn` | `18px` | 테두리 없는 아이콘 버튼 크기 |
| 구성 요소 | `menubar-icon` | `18px` | 메뉴 막대 아이콘 캔버스 크기 (그림은 그 안에서 약 13pt) |
| 구성 요소 | `browse-w` | `300px` | 노트 찾기 목록 너비 |
| 구성 요소 | `chrome-gap` | `6px` | 노트 상단 줄의 요소 사이 |
| 구성 요소 | `chrome-pad-end` | `6px` | 노트 상단 줄의 오른쪽 여백 (왼쪽은 `sp-3`) |
| 구성 요소 | `icon-s`, `icon-m`, `icon-l` | `12px`, `13px`, `14px` | 선 아이콘 크기 (18.2의 표) |
| 구성 요소 | `icon-btn-gap` | `0px` | 나란히 놓인 아이콘 버튼 사이 (노트 오른쪽 아래) |
| 구성 요소 | `swatch-size`, `swatch-gap`, `swatch-ring` | `13px`, `5px`, `1.5px` | 노트 색 칸 크기, 사이, 고른 칸의 테두리 두께이자 띄우는 거리 |
| 구성 요소 | `menu-icon` | `12px` | 노트 메뉴 그림 크기(정렬 칸은 `icon-l` 14, D-058) |
| 구성 요소 | `menu-w` | `210px` | 메뉴 최소 너비 |
| 구성 요소 | `note-w`, `note-w-min`, `note-w-max` | `340px`, `260px`, `560px` | 노트 창 너비: 기본, 최소, 최대 (가정) |
| 재질 | `opacity` | `.92` | 창 불투명도 (포커스와 상관없이 같음) |
| 재질 | `blur` | `24px` | 배경 흐림 반경 |
| 재질 | `tint-mix` | `26%` | 노트 바탕에 팔레트 색을 섞는 비율 |
| 재질 | `tint-mix-row` | `18%` | 라이브러리 줄 바탕에 섞는 비율 |
| 움직임 | `dur` | `180ms` | 전환 시간 (호버로 나타나고 사라지는 것 모두) |
| 움직임 | `ease` | `cubic-bezier(.25,.1,.25,1)` | 전환 곡선 |
| 움직임 | `caret-blink` | `530ms` | 입력 커서가 켜져 있는 시간이자 꺼져 있는 시간 (D-042, 임시) |


### 3.5 라이브러리와 아이콘 선택 (D-051)

편집기 장식은 `component.editor-*` 토큰으로 관리한다. 기존 값은 유지한다: 체크 테두리 1.25, 체크 그림 9와 선 1, 대괄호 칸 28, 글머리 원 5와 사각 4와 왼쪽 여백 4, 꺾쇠 12와 선 0.875, 줄 수 간격 8, 안내선 위치 6, 형광펜 여백 2/1, 링크 칸 간격 3과 안쪽 여백 6, 복사 버튼 여백 4. 제목 1/2/3의 전후 여백은 4/4, 6/2, 6/0이다. 복사 아이콘은 기존 `icon-m`과 공용 광학 보정을 쓴다(D-085).

- `library-w/h`: 880/560, `library-min-w/h`: 660/400, `library-sidebar-w`: 220.
- `library-header-h`: 42, `library-row-h`: 47, `library-row-leading/trailing/gap`: 20/14/14, `library-toolbar-button`: 24.
- `library-reminder-w/progress-w`: 200/46(D-066과 6단계, 체크 아이콘 포함). 값이 없는 줄도 정보 열의 자리를 유지한다.
- `icon-picker-w/pad`: 248/10, `icon-picker-columns`: 7, `icon-picker-cell-h/icon/ring`: 28/15/1.25.
- `icon-picker-grid-h/drop-h`: 140/96, `icon-import-max-pixels`: 64.

- 6단계: `component.reminder-editor-w` 320px(설정 팝오버), `component.library-reminder-w` 200px(범위를 담는 예정 열).

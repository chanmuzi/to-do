# 구현 명세 목차

디자인 최종안(B v8)의 명세를 장별 파일로 나눈 것이다. 필요한 장만 읽는다.

- 본문 안의 `assets/`, `screens/`, `app-fonts/`, `design.html`, `tokens.json` 경로는 `design/handoff/` 기준이다(로컬 전용).
  토큰만 예외로 정본이 `App/Resources/tokens.json`에 있다.
- 여기 적힌 것은 현재의 기본값이다. 결정이 바뀌면 해당 장을 직접 고치고 `docs/decisions.md`에 기록한다.

| 파일 | 내용 | 화면 |
| --- | --- | --- |
| `00-overview.md` | 읽는 법, 구성 요소 한눈에 보기, 범위 밖 | |
| `02-rules.md` | 디자인 규칙 16개 (흑백, 호버와 포커스, 마우스 모양, 글꼴 역할 등) | |
| `03-tokens.md` | 글꼴과 크기, 색(라이트, 다크), 팔레트, 치수, 재질, 움직임 | |
| `04-windows.md` | 창 종류와 크기, 가는 길, 메뉴 막대 | 8 |
| `05-note-panel.md` | 노트 창 구조, 상단 줄, 버튼, 더 보기 메뉴, 상태 조합 | 1, 2 |
| `06-editor.md` | 마크다운 요소별 입력과 모습, 들여쓰기, 기호 표시 | 2 |
| `07-capture.md` | 빠른 캡처 바 | 3 |
| `07a-datetime.md` | 캡처 바의 날짜와 시간 읽기: 읽는 꼴, 읽지 않는 꼴, 지원하지 않는 꼴 | |
| `08-browse.md` | 노트 찾기 | 9 |
| `09-library.md` | 라이브러리 사이드바와 목록 | 4 |
| `10-icon-picker.md` | 스페이스 아이콘 고르기 | 4 |
| `11-ai-panel.md` | AI 패널, 도구 내역, 후보 상자, 에이전트 목록 | 5 |
| `12-settings.md` | 테마 설정 | 6 |
| `13-shortcuts.md` | 단축키 전체 표 | 7 |
| `14-states.md` | 상태와 상호작용 요약 | |
| `15-motion.md` | 움직임 | |
| `16-edge-cases.md` | 가장자리 경우 | |
| `17-accessibility.md` | 접근성 | |
| `18-assets.md` | 앱 아이콘, 화면 아이콘과 SF Symbols 대응표, 기본 이미지, 글꼴 | |
| `19-native-notes.md` | AppKit, TextKit 2 구현 메모 | |
| `20-open-questions.md` | 정해지지 않은 것 13가지와 임시 값 | |
| `21-schedule.md` | 여러 예정, 리마인더 설정, EventKit 양방향 연동, 권한과 알림 | |

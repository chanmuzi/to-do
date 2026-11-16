# 앱에 넣을 글꼴

| 파일 | 쓰임 | 출처 | 라이선스 |
| --- | --- | --- | --- |
| `PretendardVariable.ttf` | 본문, 버튼, 제목 (굵기 400, 500, 600, 650, 700을 씀) | https://github.com/orioncactus/pretendard | OFL 1.1 (`LICENSE-Pretendard.txt`) |
| `D2Coding.ttf`, `D2CodingBold.ttf` | 시간, 개수, 날짜, 코드 | https://github.com/naver/d2codingfont | OFL 1.1 |

D2Coding은 npm 패키지 `@kfonts/d2coding`의 WOFF를 글자 모양 그대로 TTF로 바꾼 것입니다. 그 패키지에 라이선스 전문이 없어 넣지 못했습니다. 앱을 배포한다면 위 출처에서 원본 TTF와 라이선스 전문을 받아 바꿔 넣으세요.

Info.plist의 `ATSApplicationFontsPath`로 등록하거나 `CTFontManagerRegisterFontsForURL`로 실행할 때 등록합니다.

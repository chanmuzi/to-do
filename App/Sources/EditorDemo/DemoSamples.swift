/// 미리 넣을 내용.
enum DemoSamples {
    static func text(named name: String) -> String? {
        switch name {
        case "note": note
        case "elements": elements
        case "code": code
        case "literal": literal
        case "structure": structure
        case "empty": ""
        default: nil
        }
    }

    /// 서식처럼 생겼지만 글자인 것, 백슬래시로 막은 글자, 줄이 없는 코드 블록과 닫히지 않은 블록.
    static let literal = """
    if a == 1 && b == 2
    char **argv, int **p
    2 ** 3 ** 4 그리고 x==1&y==2
    use ` and ` here
    막은 글자: \\*\\*굵게 아님\\*\\* \\=\\=형광 아님\\=\\=
    진짜 서식: **굵게** ==형광== `코드` ~~취소~~
    줄이 없는 블록:
    ```
    ```
    닫히지 않은 블록:
    ```swift
    let a = 1
    """

    /// 화면 2 맨 위의 "오늘 할 일" 노트.
    static let note = """
    [x] 스탠드업 회의록 공유
    [ ] **PR #482** 리뷰
    \t[ ] 포커스 전환 애니메이션 확인
    \t- 리뷰 코멘트 2건에 답글
    [ ] ==배포 체크리스트 확인==
    + 지난주에서 넘어온 것
    \t[ ] **온보딩 문서** 초안 마무리
    \t[ ] `feature/quick-capture` 브랜치 정리
    \t\t- 리베이스한 뒤 푸시
    \t[x] 주간 리포트 제출
    """

    /// 인라인 코드가 다른 요소 안에 놓인 경우들과 코드 블록.
    static let code = """
    # 제목 1의 `code` 글자
    ## 제목 2의 `code` 글자
    ### 제목 3의 `code` 글자
    본문의 `git rebase main` 한 뒤 푸시
    [ ] 할 일의 `feature/quick-capture` 정리
    [x] 끝낸 일의 `swift test` 실행
    ==형광 안의 `code` 글자== 와 ==형광 `b`=={4}
    **굵은 글 안의 `code`** 와 ~~지운 `code`~~
    `가나다 한글 코드` 와 `a` `bb` `ccc`
    ```swift
    // 다른 앱 위에 항상 띄우기
    panel.level = .floating
    ```
    끝 줄
    """

    /// 화면 2 아래쪽의 요소별 카드를 한 노트에 모은 것.
    static let elements = """
    # 제목 1
    ## 제목 2
    ### 제목 3
    본문 글자
    [ ] **PR #482** 리뷰
    \t[ ] 포커스 전환 애니메이션 확인
    \t- 리뷰 코멘트 2건에 답글
    \t\t- 스크린샷 첨부
    [x] 스탠드업 회의록 공유
    + 지난주에서 넘어온 것
    \t[ ] 온보딩 문서
    \t[ ] 브랜치 정리
    \t[x] 주간 리포트
    + 참고 링크
    \t- [NSPanel 문서](https://developer.apple.com/documentation/appkit/nspanel)
    **굵게**, ~~취소선~~, [링크](https://example.com)
    ==형광 1== ==형광 2=={2} ==형광 3=={3} ==형광 4=={4}
    `git rebase main` 한 뒤 푸시
    브랜치는 `feature/quick-capture`
    ```swift
    // 다른 앱 위에 항상 띄우기
    panel.level = .floating
    panel.hidesOnDeactivate = false
    ```
    - 주소 붙여넣기 https://example.com/a/b
    """

    /// 하위 계층과 인용문(D-043, D-044): 부모가 있는 들여쓰기, 부모 없는 들여쓰기(다른 프로그램이 쓴 파일),
    /// 이어지는 인용문 줄, 목록 안의 인용문. 문서가 줄바꿈으로 끝나 끝의 빈 줄까지 인용문 막대가 이어지지 않는지 본다.
    static let structure = """
    - 부모 항목
    \t- 하위 항목
    \t\t[ ] 더 깊은 할 일
    \t본문 하위 줄
    본문 줄
    \t\t\t부모 없이 들여 쓴 줄(다른 앱이 쓴 파일)
    > 인용문 첫 줄은 길게 써서 줄이 넘어가는 모습까지 보이게 한다 **굵게** 와 `코드`
    > 둘째 줄 ==형광==
    본문 사이
    + 토글은 이제 원문에 + 로 적는다
    \t> 토글 안의 인용
    - 마지막 항목
    \t- 하위

    """
}

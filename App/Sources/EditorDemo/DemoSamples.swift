/// 미리 넣을 내용.
enum DemoSamples {
    static func text(named name: String) -> String? {
        switch name {
        case "note": note
        case "elements": elements
        case "empty": ""
        default: nil
        }
    }

    /// 화면 2 맨 위의 "오늘 할 일" 노트.
    static let note = """
    [x] 스탠드업 회의록 공유
    [ ] **PR #482** 리뷰
    \t[ ] 포커스 전환 애니메이션 확인
    \t- 리뷰 코멘트 2건에 답글
    [ ] ==배포 체크리스트 확인==
    > 지난주에서 넘어온 것
    \t[ ] **온보딩 문서** 초안 마무리
    \t[ ] `feature/quick-capture` 브랜치 정리
    \t\t- 리베이스한 뒤 푸시
    \t[x] 주간 리포트 제출
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
    > 지난주에서 넘어온 것
    \t[ ] 온보딩 문서
    \t[ ] 브랜치 정리
    \t[x] 주간 리포트
    > 참고 링크
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
}

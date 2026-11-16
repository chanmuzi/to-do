import Foundation
import Testing
@testable import Browse

/// 제목과 본문에서 찾기(spec 8): 한글, 대소문자, 조합형과 풀어 쓴 한글, 조합 중인 글자.
@Suite struct BrowseMatcherTests {
    private func match(_ query: String, in text: String, composing: Bool = false) -> Range<Int>? {
        BrowseMatcher.firstMatch(of: BrowseQuery(query, isComposing: composing), in: text)
    }

    /// 맞은 자리의 글자들.
    private func matched(_ query: String, in text: String, composing: Bool = false) -> String? {
        match(query, in: text, composing: composing).map { range in
            String(Array(text)[range])
        }
    }

    @Test func koreanSubstring() {
        #expect(match("배포", in: "배포 체크리스트 확인") == 0..<2)
        #expect(match("체크", in: "배포 체크리스트 확인") == 3..<5)
        #expect(match("확인", in: "배포 체크리스트 확인") == 9..<11)
        #expect(match("회의", in: "배포 체크리스트 확인") == nil)
    }

    @Test func caseDoesNotMatter() {
        #expect(matched("retry", in: "Rate limit and Retry policy") == "Retry")
        #expect(matched("RATE", in: "Rate limit and Retry policy") == "Rate")
        #expect(matched("api notes", in: "API Notes") == "API Notes")
        #expect(match("retries", in: "Rate limit and Retry policy") == nil)
    }

    /// 조합형(NFC)으로 친 말이 풀어 쓴 한글(NFD)로 저장된 글에서 찾아지고, 그 반대도 같다.
    @Test func composedAndDecomposedHangulAreTheSame() {
        let composed = "배포 순서"
        let decomposed = composed.decomposedStringWithCanonicalMapping
        #expect(composed.unicodeScalars.count != decomposed.unicodeScalars.count)
        #expect(match("배포", in: decomposed) == 0..<2)
        #expect(match("순서", in: decomposed) == 3..<5)
        #expect(match("배포".decomposedStringWithCanonicalMapping, in: composed) == 0..<2)
        #expect(match("순서".decomposedStringWithCanonicalMapping, in: decomposed) == 3..<5)
    }

    /// 받침 없는 글자는 받침 있는 글자의 앞부분으로 읽힌다(치는 도중의 모습). 맞은 자리는 글자 단위다.
    @Test func syllablePrefixMatchesWhileTyping() {
        #expect(matched("배", in: "백업 계획") == "백")
        #expect(matched("체크리스", in: "체크리스트") == "체크리스")
        #expect(matched("ㅂ", in: "배포") == "배")
        #expect(matched("배ㅍ", in: "배포 순서") == "배포")
        #expect(match("ㅋ", in: "배포") == nil)
        // 받침까지 친 글자는 받침이 다른 글자와 맞지 않는다.
        #expect(match("백", in: "배포") == nil)
        #expect(match("백", in: "밴드") == nil)
    }

    /// 두벌식으로 "배포"를 치는 동안 "뱊"이 된다. 조합 중에는 그 받침이 다음 글자의 첫소리로 넘어간 꼴도 찾는다.
    @Test func composingFinalConsonantMayMoveToTheNextSyllable() {
        #expect(matched("뱊", in: "배포 체크리스트", composing: true) == "배포")
        #expect(match("뱊", in: "배포 체크리스트", composing: false) == nil)
        // 겹받침은 뒤쪽 닿소리만 넘어간다: "닭" + ㅏ → "달가".
        #expect(matched("닭", in: "달가닥", composing: true) == "달가")
        #expect(matched("닭", in: "닭고기", composing: true) == "닭")
        #expect(matched("회읫", in: "회의실 예약", composing: true) == "회의실")
        // 조합 중이 아니면 적은 그대로만 찾는다.
        #expect(match("각", in: "가구 배치", composing: false) == nil)
        #expect(matched("각", in: "가구 배치", composing: true) == "가구")
    }

    @Test func queryIsTrimmedAndEmptyQueryMatchesNothing() {
        #expect(BrowseQuery("  배포 \n").text == "배포")
        #expect(BrowseQuery("   ").isEmpty)
        #expect(match("", in: "배포") == nil)
        #expect(match("배포", in: "") == nil)
    }

    @Test func rangeCountsCharactersNotCodeUnits() {
        // 이모지(여러 코드 단위)와 풀어 쓴 한글이 앞에 있어도 글자 차례로 센다.
        let text = "👩‍💻 " + "배포".decomposedStringWithCanonicalMapping + " 끝"
        #expect(match("끝", in: text) == 5..<6)
        #expect(matched("배포", in: text)?.precomposedStringWithCanonicalMapping == "배포")
    }
}

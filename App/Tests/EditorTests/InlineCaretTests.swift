import Foundation
import Testing
@testable import Editor

/// 감춘 인라인 기호와 ``` 줄을 커서와 선택이 어떻게 지나는지(`CaretSnapping`, D-036).
@Suite struct InlineCaretTests {
    // a0 b1 c2 *3 *4 d5 e6 f7 *8 *9 g10 h11 i12
    let doc = MarkdownDocument("가나다**라마바**사아자")

    private func caret(_ doc: MarkdownDocument, from old: Int, to new: Int, textChanged: Bool = false) -> Int {
        let result = CaretSnapping.snap(
            old: NSRange(location: old, length: 0),
            new: NSRange(location: new, length: 0),
            in: doc,
            folded: [],
            textChanged: textChanged
        )
        #expect(result.length == 0)
        return result.location
    }

    private func select(_ doc: MarkdownDocument, _ old: NSRange, _ new: NSRange) -> NSRange {
        CaretSnapping.snap(old: old, new: new, in: doc, folded: [])
    }

    @Test func markerHelpersSeeTheSameSpotFromBothSides() {
        let line = doc.lines[0]
        #expect(line.markers.map(\.range) == [NSRange(location: 3, length: 2), NSRange(location: 8, length: 2)])
        #expect(line.markers.map(\.isOpen) == [true, false])
        #expect(line.visualEnd(from: 3) == 5)
        #expect(line.visualStart(from: 5) == 3)
        #expect(line.visualEnd(from: 4) == 5)
        #expect(line.visualStart(from: 9) == 8)
        #expect(line.visualEnd(from: 6) == 6)
        #expect(line.isHiddenOnly(from: 3, to: 5))
        #expect(!line.isHiddenOnly(from: 2, to: 5))
        #expect(!line.isHiddenOnly(from: 5, to: 5))
        #expect(line.isVisualEnd(13) && !line.isVisualEnd(8))
        #expect(MarkdownDocument("a **b**").lines[0].isVisualEnd(5))
        #expect(MarkdownDocument("- **b** c").lines[0].isVisualStart(4))
    }

    @Test func rightArrowCrossesHiddenMarkersWithOneVisibleCharacter() {
        // c 뒤(구간 바깥)에서 →: 기호를 건너뛰고 d를 지난다.
        #expect(caret(doc, from: 3, to: 4) == 6)
        #expect(caret(doc, from: 6, to: 7) == 7)
        #expect(caret(doc, from: 7, to: 8) == 8)
    }

    @Test func rightArrowAtTheEndOfARunStepsOutWithoutMoving() {
        // f 뒤(구간 안)에서 →: 같은 자리에서 구간 밖으로 나간다. 다음 →가 g를 지난다.
        #expect(caret(doc, from: 8, to: 9) == 10)
        #expect(caret(doc, from: 10, to: 11) == 11)
        // 줄 끝의 구간도 같다. 한 번 더 누르면 다음 줄로 간다.
        let end = MarkdownDocument("가나다**라마바**\n다음")
        #expect(caret(end, from: 8, to: 9) == 10)
        #expect(caret(end, from: 10, to: 11) == 11)
        // 겹친 구간이 함께 끝나면 한 번에 모두 나간다. 이어진 다른 구간으로는 들어가지 않는다.
        let nested = MarkdownDocument("**~~ab~~**c")
        #expect(caret(nested, from: 6, to: 7) == 10)
        let adjacent = MarkdownDocument("**가**~~b~~")
        #expect(caret(adjacent, from: 3, to: 4) == 5)
        #expect(caret(adjacent, from: 5, to: 6) == 8)
    }

    @Test func leftArrowCrossesHiddenMarkersWithOneVisibleCharacter() {
        // g 앞(구간 바깥)에서 ←: 기호를 건너뛰고 f를 지난다.
        #expect(caret(doc, from: 10, to: 9) == 7)
        // d 뒤에서 ←: d를 지나 구간의 앞에 선다. 구간의 앞은 바깥쪽이 기본이다.
        #expect(caret(doc, from: 6, to: 5) == 3)
        #expect(caret(doc, from: 3, to: 2) == 2)
        // g 뒤에서 ←: g를 지나 구간의 끝에 선다. 구간의 끝은 안쪽이 기본이다.
        #expect(caret(doc, from: 11, to: 10) == 8)
    }

    @Test func atTheStartOfALineTheCaretIsInsideTheRunAndLeftStepsOut() {
        let lead = MarkdownDocument("앞\n- **굵게** 뒤")
        let line = lead.lines[1]
        #expect(line.contentStart == 4)
        // 줄 맨 앞으로 오면(Home, 윗줄 끝에서 →) 구간 안쪽에 선다.
        #expect(caret(lead, from: 10, to: 2) == 6)
        #expect(caret(lead, from: 1, to: 2) == 6)
        // 거기서 ←: 같은 자리에서 구간 밖으로, 한 번 더 누르면 윗줄 끝으로.
        #expect(caret(lead, from: 6, to: 5) == 4)
        #expect(caret(lead, from: 4, to: 3) == 1)
        // 밖에서 →: 굵을 지난다.
        #expect(caret(lead, from: 4, to: 5) == 7)
    }

    @Test func jumpsLandOnTheDefaultSide() {
        // 누르기, Home, End, ↑↓, 낱말 이동처럼 멀리서 온 커서: 구간 끝은 안쪽, 구간 앞은 바깥쪽.
        for target in 8...10 { #expect(caret(doc, from: 0, to: target) == 8) }
        for target in 3...5 { #expect(caret(doc, from: 13, to: target) == 3) }
        for target in 3...5 { #expect(caret(doc, from: 0, to: target) == 3) }
        // 링크의 주소, 형광펜의 색 번호도 통째로 건너뛴다.
        let link = MarkdownDocument("[글](https://a.example) 뒤 ==형=={3}")
        #expect(caret(link, from: 0, to: 12) == 2)
        #expect(caret(link, from: 0, to: 33) == 28)
        #expect(caret(link, from: 0, to: 31) == 28)
        // 기호가 없는 곳은 그대로다.
        #expect(caret(doc, from: 0, to: 6) == 6)
        #expect(caret(doc, from: 0, to: 12) == 12)
    }

    @Test func aSelectionChangeThatFollowsAnEditOnlyLeavesTheMarkers() {
        // 닫는 기호를 막 쳤을 때의 커서(구간 바깥)는 그대로 둔다: 이어 치는 글자는 서식이 없다.
        #expect(caret(doc, from: 9, to: 10, textChanged: true) == 10)
        #expect(caret(doc, from: 4, to: 5, textChanged: true) == 5)
        // 기호 한가운데에는 어떤 경우에도 놓이지 않는다.
        #expect(caret(doc, from: 0, to: 9, textChanged: true) == 8)
        #expect(caret(doc, from: 0, to: 4, textChanged: true) == 3)
    }

    @Test func shiftSelectionTreatsMarkersAsZeroWidth() {
        func range(_ location: Int, _ length: Int) -> NSRange { NSRange(location: location, length: length) }
        // c 앞에서 ⇧→ 를 이어 누른다: c, d(기호를 건너뛴다), e, f, g(기호를 건너뛴다).
        #expect(select(doc, range(2, 0), range(2, 1)) == range(2, 1))
        #expect(select(doc, range(2, 1), range(2, 2)) == range(2, 4))
        #expect(select(doc, range(2, 4), range(2, 5)) == range(2, 5))
        #expect(select(doc, range(2, 6), range(2, 7)) == range(2, 9))
        // 줄여 올 때도 같다.
        #expect(select(doc, range(2, 9), range(2, 8)) == range(2, 6))
        #expect(select(doc, range(2, 4), range(2, 3)) == range(2, 1))
        // g 뒤에서 ⇧← : g, 그다음 f(기호를 건너뛴다).
        #expect(select(doc, range(11, 0), range(10, 1)) == range(10, 1))
        #expect(select(doc, range(10, 1), range(9, 2)) == range(7, 4))
        // 구간의 끝(안쪽)에서 ⇧→ : 보이는 글자 g만 고른다.
        #expect(select(doc, range(8, 0), range(8, 1)) == range(10, 1))
        // 구간 밖(기호 바로 뒤)에서 ⇧← : 보이는 글자 f만 고른다.
        #expect(select(doc, range(10, 0), range(9, 1)) == range(7, 1))
    }

    @Test func draggedSelectionEndsStickToTheVisibleText() {
        func range(_ location: Int, _ length: Int) -> NSRange { NSRange(location: location, length: length) }
        // 끌어서 고른 범위가 기호에 걸치면 양 끝을 보이는 글자에 붙인다(시작은 기호 뒤, 끝은 기호 앞).
        #expect(select(doc, range(0, 0), range(3, 7)) == range(5, 3))
        #expect(select(doc, range(0, 0), range(4, 5)) == range(5, 3))
        #expect(select(doc, range(0, 0), range(1, 3)) == range(1, 2))
        #expect(select(doc, range(0, 0), range(9, 3)) == range(10, 2))
        // 고른 것이 기호뿐이면 선택이 되지 않는다.
        #expect(select(doc, range(0, 0), range(8, 2)).length == 0)
    }
}

@Suite struct CodeFenceCaretTests {
    // 0 앞 / 1 ```swift / 2 let x / 3 let y / 4 ``` / 5 뒤
    let doc = MarkdownDocument("앞\n```swift\nlet x\nlet y\n```\n뒤")

    private func caret(_ doc: MarkdownDocument, from old: Int, to new: Int) -> Int {
        CaretSnapping.snap(old: NSRange(location: old, length: 0), new: NSRange(location: new, length: 0), in: doc, folded: []).location
    }

    @Test func caretNeverRestsOnAFenceLine() {
        let lines = doc.lines
        // 위에서 내려오면 블록의 첫 줄로, 아래에서 올라오면 마지막 줄 끝으로.
        #expect(caret(doc, from: lines[0].end, to: lines[1].start) == lines[2].start)
        #expect(caret(doc, from: lines[0].start, to: lines[1].start + 3) == lines[2].start)
        #expect(caret(doc, from: lines[5].start, to: lines[4].end) == lines[3].end)
        #expect(caret(doc, from: lines[5].end, to: lines[4].start + 1) == lines[3].end)
        // 블록 안에서 위로 나가면 윗줄 끝으로, 아래로 나가면 아랫줄 맨 앞으로.
        #expect(caret(doc, from: lines[2].start, to: lines[1].end) == lines[0].end)
        #expect(caret(doc, from: lines[2].start + 2, to: lines[1].start + 2) == lines[0].end)
        #expect(caret(doc, from: lines[3].end, to: lines[4].start) == lines[5].start)
        // 블록 안의 줄 사이는 그대로다.
        #expect(caret(doc, from: lines[2].end, to: lines[3].start) == lines[3].start)
    }

    @Test func caretStaysWhenTheBlockIsAtTheEdgeOfTheDocument() {
        let only = MarkdownDocument("```\ncode\n```")
        #expect(caret(only, from: 4, to: 2) == 4)
        #expect(caret(only, from: 8, to: 9) == 8)
        #expect(caret(only, from: 8, to: 12) == 8)
    }

    @Test func backToBackBlocksHandTheCaretToEachOther() {
        let two = MarkdownDocument("```\na\n```\n```\nb\n```")
        let lines = two.lines
        #expect(caret(two, from: lines[1].end, to: lines[2].start) == lines[4].start)
        #expect(caret(two, from: lines[4].start, to: lines[3].end) == lines[1].end)
    }

    @Test func selectionInsideABlockStopsAtItsEdgesThenTakesTheWholeBlock() {
        let lines = doc.lines
        func select(_ old: NSRange, _ new: NSRange) -> NSRange { CaretSnapping.snap(old: old, new: new, in: doc, folded: []) }
        let inside = NSRange(location: lines[2].start, length: 2)
        // 블록 안에서 아래로 넓히면 마지막 줄 끝에서 멈춘다.
        let toEnd = select(inside, NSRange(location: lines[2].start, length: lines[4].start + 2 - lines[2].start))
        #expect(toEnd == NSRange(location: lines[2].start, length: lines[3].end - lines[2].start))
        // 더 넓히려 하면 블록을 통째로 고른다(``` 줄의 한쪽만 선택에 드는 일이 없다).
        let whole = select(toEnd, NSRange(location: toEnd.location, length: toEnd.length + 1))
        #expect(whole == NSRange(location: lines[1].start, length: lines[5].start - lines[1].start))
        // 밖에서 시작한 선택이 블록 안에서 끝나도 블록이 통째로 든다.
        let fromOutside = select(NSRange(location: 0, length: 0), NSRange(location: 0, length: lines[2].start + 3))
        #expect(fromOutside == NSRange(location: 0, length: lines[5].start))
        // 블록 바로 앞까지만 고른 선택(윗줄 전체)은 블록을 넣지 않는다.
        let above = NSRange(location: 0, length: lines[1].start)
        #expect(select(NSRange(location: 0, length: 0), above) == above)
    }
}

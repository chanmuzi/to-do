import AppKit
import Testing
@testable import Editor

@Suite struct NotionBlocksTests {
    typealias Object = [String: Any]

    // 개인 ID를 지운 실제 Notion 데스크톱 복사본. 레코드 순서와 별개로 content가 자식 순서를 정한다.
    private let sample = #"""
    {"blocks": [{"blockId": "00000000-0000-8065-8f4b-c20231e96854", "blockSubtree": {"__version__": 3, "block": {"00000000-0000-8065-8f4b-c20231e96854": {"value": {"id": "00000000-0000-8065-8f4b-c20231e96854", "type": "sub_sub_header", "version": 69, "parent_table": "block", "alive": true, "content": ["00000000-0000-809a-9453-cc192ec293bf", "00000000-0000-80f8-ba7c-c50a976bcb7c", "00000000-0000-806c-9086-fe043c9c37e9", "00000000-0000-805b-aa0b-d1f34d3d4e86"], "format": {"toggleable": true}, "properties": {"title": [["제목 토글"]]}}},
    "00000000-0000-809a-9453-cc192ec293bf": {"value": {"id": "00000000-0000-809a-9453-cc192ec293bf", "type": "bulleted_list", "version": 228, "parent_table": "block", "alive": true, "properties": {"title": [["굵게", [["b"]]], [", "], ["밑줄", [["_"]]], [", "], ["글자색", [["h", "purple_background"]]], [", 형광펜은 없어, "], ["링크", [["a", "/p/0123456789abcdef0123456789abcdef?pvs=25"]]], [", "], ["인라인 코드", [["c"]]]]}}},
    "00000000-0000-80f8-ba7c-c50a976bcb7c": {"value": {"id": "00000000-0000-80f8-ba7c-c50a976bcb7c", "type": "quote", "version": 69, "parent_table": "block", "alive": true, "properties": {"title": [["인용 블록"]]}}},
    "00000000-0000-806c-9086-fe043c9c37e9": {"value": {"id": "00000000-0000-806c-9086-fe043c9c37e9", "type": "divider", "version": 15, "parent_table": "block", "alive": true}},
    "00000000-0000-805b-aa0b-d1f34d3d4e86": {"value": {"id": "00000000-0000-805b-aa0b-d1f34d3d4e86", "type": "code", "version": 36, "parent_table": "block", "alive": true, "properties": {"language": [["JavaScript"]], "title": [["JavaScript"]]}}}}}}], "action": "copy", "wasContiguousSelection": true}
    """#

    private let relative = "/p/0123456789abcdef0123456789abcdef?pvs=25"

    @Test func readsNotionDesktopSample() {
        let expected = """
        + ### 제목 토글
        \t- **굵게**, <u>밑줄</u>, ==글자색=={보라}, 형광펜은 없어, [링크](https://www.notion.so\(relative)), `인라인 코드`
        \t> 인용 블록
        \t---
        \t```javascript
        \tJavaScript
        \t```
        """
        #expect(NotionBlocksImport.source(sample) == expected)
    }

    private func roots(_ json: String) throws -> [Object] {
        let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? Object)
        return try #require(object["blocks"] as? [Object])
    }

    @Test func writesTheSamplePropertiesAndOrderedSubtree() throws {
        let source = try #require(NotionBlocksImport.source(sample))
        let json = try #require(CopyExport(source: source).notionBlocksJSON)
        let root = try #require(try roots(json).first)
        let tree = try #require(root["blockSubtree"] as? Object)
        let records = try #require(tree["block"] as? [String: Object])
        let rootID = try #require(root["blockId"] as? String)
        let value = try #require(records[rootID]?["value"] as? Object)
        #expect(value["type"] as? String == "sub_sub_header")
        #expect((value["format"] as? Object)?["toggleable"] as? Bool == true)
        let children = try #require(value["content"] as? [String])
        let values = try children.map { id in
            let child = try #require(records[id]?["value"] as? Object)
            #expect(child["parent_id"] as? String == rootID && child["parent_table"] as? String == "block")
            return child
        }
        #expect(values.compactMap { $0["type"] as? String } == ["bulleted_list", "quote", "divider", "code"])
        let props = try #require(values.first?["properties"] as? Object)
        let title = try #require(props["title"] as? [[Any]])
        let marks = title.compactMap { $0.count > 1 ? $0[1] as? [[String]] : nil }
        #expect(marks == [[["b"]], [["_"]], [["h", "purple_background"]], [["a", "https://www.notion.so" + relative]], [["c"]]])
        #expect(values[2]["properties"] == nil)
        #expect((values[3]["properties"] as? Object)?["language"] as? [[String]] == [["JavaScript"]])
    }

    @Test func isolatedTreesHaveFreshIDsAndPreserveHierarchy() throws {
        let source = "+ 토글\n\t[x] 완료\n\t\t- 손자\n\t[ ] 할 일\n본문\n\t자식\n# 제목\n\t제목 자식\n\n끝"
        let copy = CopyExport(source: source)
        var ids: Set<String> = []
        for _ in 0..<2 {
            let json = try #require(copy.notionBlocksJSON)
            #expect(NotionBlocksImport.source(json) == source)
            var sizes: [Int] = []
            for root in try roots(json) {
                let tree = try #require(root["blockSubtree"] as? Object)
                let records = try #require(tree["block"] as? Object)
                sizes.append(records.count)
                for id in records.keys {
                    #expect(UUID(uuidString: id)?.uuidString.lowercased() == id)
                    #expect(ids.insert(id).inserted)
                }
            }
            #expect(sizes == [4, 2, 2, 1, 1])
        }
    }

    @Test func emptyParentAndToggleSeparatorKeepTheirChildrenInOrder() throws {
        let source = "\n\t빈 본문의 자식\n+ 토글\n\n\t하위 본문\n다음"
        let json = try #require(CopyExport(source: source).notionBlocksJSON)
        #expect(try roots(json).count == 3)
        #expect(NotionBlocksImport.source(json) == "\n\t빈 본문의 자식\n+ 토글\n\t\n\t하위 본문\n다음")
    }

    @Test func headingsInksAndInlineMarks() throws {
        for level in 1...3 {
            for prefix in ["", "+ "] {
                for ink in InkColor.palette {
                    let source = prefix + String(repeating: "#", count: level) + " ==**굵게**=={" + ink.suffix + "}" + ink.comment
                    let data = try #require(CopyExport(source: source).chromiumData)
                    #expect(NotionBlocksImport.source(from: data) == source)
                }
            }
        }
        let source = "~~취소~~ _기울임_ `\\*코드*` **겹친 <u>서식</u> 끝**"
        #expect(NotionBlocksImport.source(try #require(CopyExport(source: source).notionBlocksJSON)) == source)
    }

    @Test func hardBreaksAndCodeSelections() throws {
        let source = "+ 토글\n\t[x] 첫 줄\\\n\t둘째 줄\n\t```swift\n\t  let x = 1\n\t```"
        #expect(NotionBlocksImport.source(try #require(CopyExport(source: source).notionBlocksJSON)) == source)
        let doc = MarkdownDocument("```swift\n# 코드\n[ ] 글자\n```\n뒤")
        let selected = CopyExport(doc, selection: NSRange(location: doc.lines[1].start, length: doc.length - doc.lines[1].start))
        #expect(NotionBlocksImport.source(try #require(selected.notionBlocksJSON)) == "```\n# 코드\n[ ] 글자\n```\n뒤")
        let unknown = try #require(CopyExport(source: "```unknown\nx\n```").notionBlocksJSON)
        #expect(unknown.contains("Plain Text"))
    }

    @Test func pickleWireBytesAndMultipleEntries() throws {
        let wire = Data([20,0,0,0, 1,0,0,0, 1,0,0,0, 65,0,0,0, 2,0,0,0, 61,216,0,222])
        #expect(ChromiumCustomData.encode(["A": "😀"]) == wire)
        #expect(ChromiumCustomData.decode(wire) == ["A": "😀"])
        let entries = ["text/_notion-page-source-production": "", ChromiumCustomData.notionBlocks: "한글📝\u{0}끝"]
        #expect(ChromiumCustomData.decode(try #require(ChromiumCustomData.encode(entries))) == entries)
        for cut in 0..<wire.count {
            #expect(ChromiumCustomData.decode(wire.prefix(cut)) == nil)
        }
        for index in [0, 4, 8, 16] {
            var invalid = wire
            invalid.replaceSubrange(index..<index + 4, with: [255, 255, 255, 255])
            #expect(ChromiumCustomData.decode(invalid) == nil)
        }
        var surrogate = wire
        surrogate[23] = 0
        #expect(ChromiumCustomData.decode(surrogate) == nil)
        var padding = Data(wire.prefix(14))
        padding[0] = 10
        #expect(ChromiumCustomData.decode(padding) == nil)
    }

    @Test func unknownBlocksAndMalformedTrees() throws {
        let modified = sample.replacingOccurrences(of: "\"bulleted_list\"", with: "\"image\"")
            .replacingOccurrences(of: "\"divider\"", with: "\"table\"")
        let result = try #require(NotionBlocksImport.source(modified))
        #expect(result.contains("\n\t굵게, 밑줄, 글자색, 형광펜은 없어, 링크, 인라인 코드\n"))
        #expect(!result.contains("---"))
        let root = "00000000-0000-8065-8f4b-c20231e96854"
        let child = "00000000-0000-809a-9453-cc192ec293bf"
        for bad in ["invalid", "{}", sample.replacingOccurrences(of: "\"content\": [\"" + child, with: "\"content\": [\"" + root),
                    sample.replacingOccurrences(of: "\"content\": [\"" + child, with: "\"content\": [\"missing")] {
            #expect(NotionBlocksImport.source(bad) == nil)
        }
    }

    @MainActor @Test func flavorOrderAndRecovery() throws {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        board.setString("일반", forType: .string)
        board.setString("<details><summary>HTML</summary></details>", forType: .html)
        let other = try #require(ChromiumCustomData.encode(["other": "value"]))
        let empty = try #require(ChromiumCustomData.encode([ChromiumCustomData.notionBlocks: "{}"]))
        for invalid in [Data([1]), other, empty] {
            board.setData(invalid, forType: .chromiumWebCustomData)
            #expect(EditorController.source(from: board) == "+ HTML")
        }
        let valid = try #require(CopyExport(source: "+ Notion").chromiumData)
        board.setData(valid, forType: .chromiumWebCustomData)
        #expect(EditorController.source(from: board) == "+ Notion")
        board.setString("Float", forType: .floatingNotesMarkdown)
        #expect(EditorController.source(from: board) == "Float")
    }
}

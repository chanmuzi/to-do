import Foundation
import Models
import Store

/// 견본 노트 여덟 개를 두 스페이스에 채운다(화면 9의 내용). 노트 폴더가 비어 있을 때만 쓴다.
///
/// 파일을 직접 적는다: 만든 날짜와 고친 시각을 정해 두어야 "오늘 노트"와 목록의 차례가 실행마다 같다.
enum DemoSeed {
    static let work = Space(id: SpaceID(rawValue: "space-work"), name: "회사", icon: .symbol(name: "briefcase", colorID: nil))
    static let home = Space(id: SpaceID(rawValue: "space-home"), name: "개인", icon: .symbol(name: "house", colorID: nil))

    private struct Sample {
        var id: String
        var title: String
        var space: Space?
        var color: String?
        var reminder: Date?
        /// 오늘 만든 노트인지. 아니면 며칠 전에 만든 것으로 적는다.
        var createdToday = false
        var floatingOrder: Int?
        var body: String
    }

    static func seedIfEmpty(location: StoreLocation, now: Date, calendar: Calendar) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: location.notesDirectory, withIntermediateDirectories: true)
        let existing = try manager.contentsOfDirectory(atPath: location.notesDirectory.path)
        guard !existing.contains(where: { $0.hasSuffix(".md") }) else { return }

        let today = calendar.startOfDay(for: now)
        let tomorrowTen = calendar.date(byAdding: .day, value: 1, to: today)
            .flatMap { calendar.date(bySettingHour: 10, minute: 0, second: 0, of: $0) }
        let samples = [
            Sample(id: "demo-1-today", title: "오늘 할 일", space: work,
                   reminder: now.addingTimeInterval(12 * 60), createdToday: true, floatingOrder: 3,
                   body: "[x] 스탠드업\n[ ] PR #482 리뷰\n[ ] 배포 체크리스트 확인\n"),
            Sample(id: "demo-2-home", title: "개인", space: home, color: "tint-5", floatingOrder: 2,
                   body: "[ ] 치과 예약 전화\n[ ] 택배 반품 신청\n"),
            Sample(id: "demo-3-scratch", title: "스크래치", color: "tint-1", floatingOrder: 1,
                   body: "아이디어: 플로팅 창 투명도를 단축키로 바꾸기\n"),
            Sample(id: "demo-4-release", title: "릴리즈 노트 초안", space: work, reminder: tomorrowTen,
                   body: "2.3 변경 사항 정리\n- 배포 순서 확인\n"),
            Sample(id: "demo-5-untitled", title: "", space: home, body: "주말 장보기 목록\n"),
            Sample(id: "demo-6-meeting", title: "회의 메모 11-13", space: work,
                   body: "디자인 싱크, 다음 주 일정\n"),
            Sample(id: "demo-7-reading", title: "읽을 것", space: home,
                   body: "- TextKit 2 문서\n- Swift 동시성\n"),
            Sample(id: "demo-8-api", title: "API Notes", space: work,
                   body: "Rate limit and **Retry** policy\n"),
        ]

        let format = ISO8601DateFormatter()
        for (index, sample) in samples.enumerated() {
            let created = sample.createdToday
                ? today.addingTimeInterval(60)
                : today.addingTimeInterval(TimeInterval(-86400 * (index + 1)))
            var lines = ["---", "title: \"\(sample.title)\""]
            if let space = sample.space { lines.append("space: \(space.id.rawValue)") }
            if let color = sample.color { lines.append("color: \(color)") }
            if let reminder = sample.reminder { lines.append("reminder: \(format.string(from: reminder))") }
            lines += ["created: \(format.string(from: created))", "---"]
            let url = location.notesDirectory.appendingPathComponent("\(sample.id).md")
            try (lines.joined(separator: "\n") + "\n" + sample.body).write(to: url, atomically: true, encoding: .utf8)
            // 목록은 최근에 고친 것이 앞이다. 견본의 차례대로 놓이게 고친 시각을 한 시간씩 벌린다.
            let modified = now.addingTimeInterval(TimeInterval(-3600 * (index + 1)))
            try manager.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }

        try SpaceStore(location: location).replace(with: [work, home])
        let windows = try WindowStateStore(location: location)
        for sample in samples {
            guard let order = sample.floatingOrder else { continue }
            try windows.set(
                NoteWindowState(isPinned: true, isOpen: true, stackOrder: order), for: NoteID(rawValue: sample.id)
            )
        }
    }
}

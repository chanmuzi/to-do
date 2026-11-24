import AppKit
import Models
import Store
import SwiftUI
import Testing
import Theme
@testable import Agent

@Suite struct AgentProgressTests {
    @Test func durations() {
        var step = AgentRequest.Step(.think)
        for (value, expected): (Double?, String?) in [(nil, nil), (-1, nil), (0, nil), (0.049, nil),
            (0.05, "0.1초"), (0.3, "0.3초"), (2.35, "2.4초"), (59.9, "59.9초"),
            (60, "1분"), (65.1, "1분 5초"), (119.9, "2분"), (.infinity, nil)] {
            step.elapsed = value
            #expect(step.durationLabel == expected)
        }
    }

    @Test func activeAndHistoricalSteps() {
        var read = AgentRequest.Step(.read, callID: "read")
        read.noteTitle = "주간 작업"
        var req = AgentRequest(id: UUID(), text: "확인", engine: "fixture", model: nil)
        req.steps = [read]
        #expect(req.progressTitle == read.title(for: .active))
        #expect(read.phase(in: .interrupted, last: false) == .stopped)
        read.endedAt = Date()
        read.result = "실패"
        #expect(read.phase(in: .completed, last: true) == .failed)
        #expect(read.title(for: .failed) == "주간 작업 읽기 실패")
        read.result = "완료"
        #expect(read.phase(in: .interrupted, last: true) == .completed)
        #expect(read.title(for: .completed) == "주간 작업 읽음")
        var think = AgentRequest.Step(.think)
        think.endedAt = Date()
        #expect(think.phase(in: .failed, last: true) == .failed)
        #expect(think.phase(in: .interrupted, last: false) == .completed)
        think.result = "중단"
        #expect(think.title(for: think.phase(in: .failed, last: false)) == "생각 중단")
        req.steps = [AgentRequest.Step(.search), read]
        #expect(req.face == .search && req.progressTitle == "찾는 중")
    }

    @Test func renderedColumnsAndBaselines() async throws {
        _ = NSApplication.shared
        let theme = try Theme.bundled()
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let draft = AgentDraft(.init(targets: []), store: AgentStore(location: .isolated(notesDirectory: root)))
        var request = AgentRequest(id: UUID(), text: "주간 작업 확인", engine: "fixture", model: nil)
        request.status = .completed
        request.answer = "확인했어요."
        for kind: AgentRequest.Step.Kind in [.think, .search, .read, .write] {
            var step = AgentRequest.Step(kind)
            step.elapsed = kind == .think ? 0 : 2.4
            step.endedAt = Date()
            if kind == .read { step.noteID = .make(); step.noteTitle = "주간 작업" }
            request.steps.append(step)
        }
        draft.expanded.insert(request.id)
        draft.measuresProgress = true
        let host = NSHostingView(rootView: AgentTurnView(theme: theme, draft: draft, request: request,
                                                         still: true, openNote: { _ in }, retry: {}))
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        defer { panel.close() }
        for width in [260, 340, 560] {
            panel.setContentSize(.init(width: width, height: 260))
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(120))
            func frame(_ key: String) throws -> CGRect { try #require(draft.progressFrames[key]) }
            let rail = try frame("rail"), chevron = try frame("chevron"), answer = try frame("answer")
            #expect(chevron.midX == rail.midX)
            #expect(rail.minX.rounded() == rail.minX && rail.maxX.rounded() == rail.maxX)
            let rows = try request.steps.map { try frame("row-" + $0.id.uuidString) }
            #expect(rail.minY == rows[0].minY && rail.maxY == rows[3].maxY)
            var previous: CGFloat?
            var leading: CGFloat?
            for (i, step) in request.steps.enumerated() {
                let key = step.id.uuidString
                let label = try frame("baseline-label-" + key)
                #expect(label.minY > rows[i].minY && label.minY < rows[i].maxY)
                if let leading { #expect(label.minX == leading) }
                leading = label.minX
                if let previous { #expect(label.minY - previous == theme.component(.agentStepHeight) + theme.component(.iconButtonGap)) }
                previous = label.minY
                if step.durationLabel != nil {
                    #expect(try frame("baseline-time-" + key).minY == label.minY)
                    #expect(try frame("time-" + key).maxX == answer.maxX)
                }
            }
        }
    }
}

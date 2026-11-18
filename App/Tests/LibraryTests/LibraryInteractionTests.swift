import AppKit
import SwiftUI
import Foundation
import Testing
import Models
import Store
import Theme
import Routing
import SpaceIcons
@testable import Library

@Suite(.serialized) @MainActor struct LibraryInteractionTests {
    final class Fixture {
        let root: URL
        let notes: FileNoteStore
        let coordinator: LibraryCoordinator
        let recorder = Recorder()
        var routes: [Route] { recorder.values }
        var model: LibraryModel { coordinator.model }
        final class Recorder { var values: [Route] = [] }
        init() throws {
            _ = NSApplication.shared
            _ = FontRegistrar.registerBundledFonts()
            root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("library-input-\(UUID())")
            let location = StoreLocation.isolated(notesDirectory: root)
            notes = try FileNoteStore(location: location)
            let recorder = recorder
            let router = RouteDispatcher(isConnected: { route in
                switch route { case .openSettings, .openAIPanel: false; default: true }
            }, answering: { recorder.values.append($0); return .handled })
            coordinator = LibraryCoordinator(theme: try Theme.bundled(), notes: notes,
                spaces: try SpaceStore(location: location), windows: try WindowStateStore(location: location),
                preferences: try LibraryPreferencesStore(location: location), router: router)
        }
        func close() throws { coordinator.close(); try FileManager.default.removeItem(at: root) }
    }

    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.06)) }
    func click(_ window: NSWindow, at point: NSPoint, count: Int = 1) throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: count, pressure: 1))
            window.sendEvent(event)
        }
        settle()
    }
    func key(_ view: NSView, code: UInt16, characters: String) throws {
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: view.window?.windowNumber ?? 0,
            context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
        view.keyDown(with: event)
    }

    @Test func visibleRowOwnsClicksIncludingRightIconsAndNeverFocusesPlus() throws {
        let f = try Fixture(); defer { try? f.close() }
        let first = try f.notes.create(NoteDraft(title: "첫째", body: "[ ] 할 일", reminder: Date().addingTimeInterval(3600)))
        let second = try f.notes.create(NoteDraft(title: "둘째"))
        f.coordinator.allowsKeyWindows = false
        f.coordinator.show(); settle()
        let window = try #require(f.coordinator.window)
        let root = try #require(window.contentView)
        root.layoutSubtreeIfNeeded()
        #expect(descendants(root).allSatisfy { $0.focusRingType == .none })
        let rows = descendants(root).compactMap { $0 as? LibraryRowInputView }
            .filter { $0.bounds.height == f.model.theme.component(.libraryRowHeight) }
        #expect(rows.count == 2)
        for row in rows {
            for x in [1.0, row.bounds.midX, row.bounds.width - 1] {
                let point = row.convert(NSPoint(x: x, y: row.bounds.midY), to: nil)
                let hitMatches = root.hitTest(root.superview!.convert(point, from: nil)) === row
                #expect(hitMatches)
                try click(window, at: point)
                #expect(f.model.selectedNoteID == row.note?.id)
                let focusMatches = window.firstResponder === row
                #expect(focusMatches)
                #expect(row.focusRingType == .none)
                #expect(window.defaultButtonCell == nil)
                #expect(try f.notes.list().notes.count == 2)
            }
        }
        #expect(Set(f.model.rows.map(\.id)) == [first.id, second.id])
        #expect(!window.isKeyWindow)
        #expect(f.routes.isEmpty)
        let row = try #require(rows.first)
        try click(window, at: row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil), count: 2)
        #expect(f.routes == [.openNote(try #require(row.note).id)])
        try key(row, code: 36, characters: "\r")
        #expect(f.routes.count == 2)
    }

    @Test func clickSelectsDoubleClickAndReturnOpenAndTrashRestores() throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("library-actions-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let location = StoreLocation.isolated(notesDirectory: root)
        let notes = try FileNoteStore(location: location)
        let a = try notes.create(NoteDraft(title: "선택", body: "보존"))
        var routes: [Route] = []
        let model = LibraryModel(theme: try Theme.bundled(), notes: notes, spaces: try SpaceStore(location: location),
            windows: try WindowStateStore(location: location), preferences: try LibraryPreferencesStore(location: location),
            router: RouteDispatcher { routes.append($0) })
        let input = LibraryRowInputView(); input.model = model; input.note = a
        model.activate(a)
        #expect(model.selectedNoteID == a.id)
        #expect(routes.isEmpty)
        try key(input, code: 36, characters: "\r")
        #expect(routes == [.openNote(a.id)])
        routes.removeAll()
        model.activate(a, clickCount: 2)
        #expect(routes == [.openNote(a.id)])
        try notes.moveToTrash(a.id); model.refresh(); model.select(.trash)
        routes.removeAll(); model.activate(a)
        #expect(try notes.listTrash().notes.count == 1)
        #expect(routes.isEmpty)
        model.activate(a, clickCount: 2)
        #expect(routes == [.openNote(a.id)])
        #expect(try notes.load(a.id).body == "보존")
        #expect(try notes.listTrash().notes.isEmpty)
    }

    func clickAction(_ name: String, in root: NSView, window: NSWindow) throws {
        let region = try #require(descendants(root).first { $0.accessibilityLabel() == name + " 호버" })
        try click(window, at: region.convert(NSPoint(x: region.bounds.midX, y: region.bounds.midY), to: nil))
    }

    @Test func sidebarReminderOpensFromDetailWhileTrashStaysUntouched() throws {
        let f = try Fixture(); defer { try? f.close() }
        let note = try f.notes.create(NoteDraft(title: "다가옴", reminder: Date().addingTimeInterval(3600)))
        let trash = try f.notes.create(NoteDraft(title: "휴지통")); try f.notes.moveToTrash(trash.id)
        // 외부에서 노트 파일을 되살려 휴지통과 현재 노트의 ID가 겹친 상태.
        let location = StoreLocation.isolated(notesDirectory: f.root)
        try FileManager.default.copyItem(at: location.notesDirectory.appendingPathComponent(note.id.rawValue + ".md"),
            to: location.trashDirectory.appendingPathComponent(note.id.rawValue + ".md"))
        f.coordinator.allowsKeyWindows = false; f.coordinator.show(); f.model.select(.trash); settle()
        let window = try #require(f.coordinator.window)
        let root = try #require(window.contentView)
        let entry = try #require(f.model.index.upcoming.first)
        try clickAction(entry.id, in: root, window: window)
        #expect(f.model.upcomingID == entry.id && f.model.upcomingPinned)
        #expect(f.routes.isEmpty)
        try clickAction("일정 연결 열기", in: root, window: window)
        #expect(f.routes == [.openNote(note.id)])
        #expect(f.model.error == nil)
        #expect(Set(try f.notes.listTrash().notes.map(\.id)) == [trash.id, note.id])
    }

    @Test func upcomingHoverCancelsOnExitAndClickPersistsUntilOutside() async throws {
        let f = try Fixture()
        defer { try? f.close() }
        _ = try f.notes.create(NoteDraft(title: "다가옴", reminder: Date().addingTimeInterval(3600)))
        f.coordinator.allowsKeyWindows = false
        f.coordinator.show()
        settle()
        let window = try #require(f.coordinator.window)
        let root = try #require(window.contentView)
        let entry = try #require(f.model.index.upcoming.first)
        let hover = try #require(descendants(root).compactMap { $0 as? SidebarHoverView }
            .first { $0.accessibilityLabel() == entry.id + " 호버" })
        let pause = f.model.theme.motion.upcomingHover
        hover.changed(true)
        try await Task.sleep(for: .seconds(pause / 2))
        #expect(f.model.upcomingID == nil)
        try await Task.sleep(for: .seconds(pause))
        #expect(f.model.upcomingID == entry.id && !f.model.upcomingPinned)
        hover.changed(false)
        settle()
        #expect(f.model.upcomingID == nil)
        try clickAction(entry.id, in: root, window: window)
        hover.changed(false)
        #expect(f.model.upcomingID == entry.id && f.model.upcomingPinned)
        try click(window, at: NSPoint(x: root.bounds.maxX - 25, y: root.bounds.midY))
        #expect(f.model.upcomingID == nil)
    }

    @Test func bringingLibraryForwardKeepsTrashSelection() throws {
        let f = try Fixture(); defer { try? f.close() }
        let note = try f.notes.create(NoteDraft(title: "버린 노트"))
        try f.notes.moveToTrash(note.id)
        f.coordinator.allowsKeyWindows = false
        f.coordinator.show()
        f.model.select(.trash)
        f.model.activate(note)
        let window = try #require(f.coordinator.window)
        f.coordinator.bringForward()
        #expect(f.coordinator.window === window)
        #expect(window.isVisible && f.model.selectedNoteID == note.id)
        #expect(f.routes.isEmpty)
    }

    @Test func calendarOnlyRowOpensItsEventFromDetail() throws {
        let f = try Fixture(); defer { try? f.close() }
        let now = Date()
        _ = try f.notes.create(NoteDraft(title: "노트", reminder: now.addingTimeInterval(3600)))
        let event = CalendarEvent(item: ScheduleItem(start: now.addingTimeInterval(7200),
            end: now.addingTimeInterval(9000), title: "캘린더 회의"), destination: nil)
        f.model.readEvents = { _ in [event] }
        var opened: [CalendarEvent] = []
        f.model.openCalendarEvent = { opened.append($0) }
        f.coordinator.allowsKeyWindows = false
        f.coordinator.show(); settle()
        let window = try #require(f.coordinator.window)
        let root = try #require(window.contentView)
        let entry = UpcomingRow.calendar(event)
        try clickAction(entry.id, in: root, window: window)
        #expect(opened.isEmpty && f.model.upcomingID == entry.id)
        try clickAction("일정 연결 열기", in: root, window: window)
        #expect(opened == [event])
        #expect(f.routes.isEmpty)
    }

    @Test func draftAndSavedSpaceShareIconSizeAndColumn() throws {
        let f = try Fixture()
        defer { try? f.close() }
        _ = try f.model.spaces.create(name: "업무")
        f.coordinator.allowsKeyWindows = false
        f.coordinator.show()
        f.model.beginSpaceEditing()
        settle()
        let root = try #require(f.coordinator.window?.contentView)
        root.layoutSubtreeIfNeeded()
        let theme = f.model.theme
        let boxes = descendants(root).compactMap { $0 as? SpaceIconNSView }.map { $0.convert($0.bounds, to: root) }
        let side = theme.component(.iconLarge)
        let center = theme.space(.sp2) + theme.space(.sp1) + theme.component(.controlHeight) / 2
        #expect(boxes.count == 2)
        for box in boxes {
            #expect(box.size == NSSize(width: side, height: side))
            #expect(box.midX == center)
        }
        let field = try #require(descendants(root).compactMap { $0 as? NSTextField }
            .first { $0.accessibilityLabel() == "스페이스 이름" })
        let fieldStart = field.convert(field.bounds, to: root).minX + field.alignmentRectInsets.left
        let textStart = center + theme.component(.controlHeight) / 2 + theme.space(.sp1)
        #expect(fieldStart == textStart)
        #expect(!field.drawsBackground && !field.isBordered)
    }

    @Test func collapsedSpaceDisclosureStillRespondsAcrossItsButton() throws {
        let f = try Fixture()
        defer { try? f.close() }
        let space = try f.model.spaces.create(name: "업무")
        f.coordinator.allowsKeyWindows = false
        f.coordinator.show()
        settle()
        let window = try #require(f.coordinator.window)
        let root = try #require(window.contentView)
        let folder = try #require(descendants(root).compactMap { $0 as? SpaceIconNSView }.first)
        let center = folder.convert(folder.bounds, to: nil)
        let theme = f.model.theme
        let right = theme.component(.librarySidebarWidth) - theme.space(.sp2) - theme.space(.sp1)
        let control = theme.component(.controlHeight)
        #expect(!f.model.expanded.contains(space.id))
        try click(window, at: NSPoint(x: right - control + 1, y: center.midY))
        #expect(f.model.expanded.contains(space.id))
        try click(window, at: NSPoint(x: right - 1, y: center.midY))
        #expect(!f.model.expanded.contains(space.id))
    }

    @Test func noteMarkerUsesOnlyItsLinkedCalendarOrReminderList() throws {
        let f = try Fixture()
        defer { try? f.close() }
        let now = Date()
        let destination = ScheduleDestination(name: "업무", color: .init(red: 0, green: 0, blue: 1))
        var queries: [ScheduleItem.Kind] = []
        f.model.linkedDestination = { item in
            queries.append(item.kind)
            return destination
        }
        var item = ScheduleItem(start: now)
        #expect(f.model.markerDestination(for: item) == nil)
        item.link = .init(localID: "연결", externalID: nil, kind: .event)
        #expect(f.model.markerDestination(for: item) == nil)
        item.end = now.addingTimeInterval(3600)
        #expect(f.model.markerDestination(for: item) == destination)
        item.end = nil
        item.link?.kind = nil
        #expect(f.model.markerDestination(for: item) == destination)
        #expect(queries == [.event, .reminder])
    }

    @Test func selectedNoteFillKeepsSideMarginsAndSeparatorClear() throws {
        let f = try Fixture()
        defer { try? f.close() }
        let note = try f.notes.create(NoteDraft(title: "시험"))
        f.coordinator.allowsKeyWindows = false
        f.coordinator.show()
        settle()
        let root = try #require(f.coordinator.window?.contentView)
        let row = try #require(descendants(root).compactMap { $0 as? LibraryRowInputView }.first { $0.note?.id == note.id })
        let rect = row.convert(row.bounds, to: root)
        func render() throws -> NSBitmapImageRep {
            let bitmap = try #require(root.bitmapImageRepForCachingDisplay(in: rect))
            root.cacheDisplay(in: rect, to: bitmap)
            return bitmap
        }
        let before = try render()
        f.model.activate(note)
        RunLoop.main.run(until: Date().addingTimeInterval(f.model.theme.motion.duration + 0.05))
        let after = try render()
        let width = after.pixelsWide
        let height = after.pixelsHigh
        let insetX = Int(CGFloat(width) / rect.width * f.model.theme.space(.sp2))
        let insetY = Int(CGFloat(height) / rect.height * f.model.theme.component(.libraryRowHighlightInsetY))
        func unchanged(_ x: Int, _ y: Int) -> Bool { before.colorAt(x: x, y: y) == after.colorAt(x: x, y: y) }
        #expect(unchanged(insetX - 1, height / 2))
        #expect(unchanged(width - insetX, height / 2))
        #expect(!unchanged(insetX, height / 2))
        #expect(!unchanged(width - 1 - insetX, height / 2))
        #expect(unchanged(width / 2, insetY - 1))
        #expect(unchanged(width / 2, height - insetY))
        #expect(!unchanged(width / 2, height / 2))
    }

    @Test func sidebarUpdatesWhenNoteCountsChange() throws {
        let f = try Fixture(); defer { try? f.close() }
        _ = try f.notes.create(NoteDraft(title: "첫째"))
        f.coordinator.allowsKeyWindows = false; f.coordinator.show(); settle()
        let root = try #require(f.coordinator.window?.contentView)
        func sidebar() throws -> Data {
            root.layoutSubtreeIfNeeded()
            let rect = NSRect(x: 0, y: 0, width: f.model.theme.component(.librarySidebarWidth), height: root.bounds.height)
            let bitmap = try #require(root.bitmapImageRepForCachingDisplay(in: rect))
            root.cacheDisplay(in: rect, to: bitmap)
            return try #require(bitmap.representation(using: .png, properties: [:]))
        }
        let before = try sidebar()
        _ = try f.notes.create(NoteDraft(title: "둘째")); f.model.refresh(); settle()
        let after = try sidebar()
        #expect(before != after, "노트 수가 바뀌면 보기 오른쪽 개수를 갱신한다")
    }

    @Test func keyboardSelectionClearsWhenViewOrSearchChanges() throws {
        let f = try Fixture(); defer { try? f.close() }
        _ = try f.notes.create(NoteDraft(title: "A")); _ = try f.notes.create(NoteDraft(title: "B"))
        f.model.refresh(); f.model.moveSelection(by: 1)
        #expect(f.model.selectedNoteID == f.model.rows.first?.id)
        f.model.moveSelection(by: 1)
        #expect(f.model.selectedNoteID == f.model.rows.last?.id)
        f.model.query = "A"; #expect(f.model.selectedNoteID == nil)
        f.model.activate(try #require(f.model.rows.first)); f.model.select(.all)
        #expect(f.model.selectedNoteID == nil)
    }

    @Test func libraryUsesSharedKoreanReminderAndAllDisplayModes() throws {
        let f = try Fixture(); defer { try? f.close() }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 12))!
        let reminder = cal.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 15))!
        let note = try f.notes.create(NoteDraft(title: "일정", reminder: reminder))
        f.model.refresh(now: now, calendar: cal)
        #expect(f.model.reminderPresentation(for: note)?.text == "내일 오후 3:00")
        for mode in [NoteDisplayOptions.ReminderDisplay.time, .relative, .iconOnly] {
            f.model.displayOptions.reminder = mode
            #expect(f.model.reminderPresentation(for: note) == ReminderPresentation(reminder: reminder,
                now: now, options: f.model.displayOptions, calendar: cal))
        }
        let empty = LibraryPreview(Note(id: .make(), body: "본문", created: Date(), modified: Date()))
        #expect(empty.total == 0)
        let summary = LibraryPreview(Note(id: .make(), body: "- [x] 완료\n- [ ] 대기", created: Date(), modified: Date()))
        #expect(summary.completed == 1 && summary.total == 2)
    }
}

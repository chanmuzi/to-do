import AppKit
import SwiftUI
import Foundation
import Testing
import Models
import Store
import Theme
import Routing
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
            root = FileManager.default.temporaryDirectory.appendingPathComponent("library-input-\(UUID())")
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
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("library-actions-\(UUID())")
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

    @Test func sidebarReminderSelectsThenReturnOpensWhileTrashStaysUntouched() throws {
        let f = try Fixture(); defer { try? f.close() }
        let note = try f.notes.create(NoteDraft(title: "다가옴", reminder: Date().addingTimeInterval(3600)))
        let trash = try f.notes.create(NoteDraft(title: "휴지통")); try f.notes.moveToTrash(trash.id)
        f.coordinator.allowsKeyWindows = false; f.coordinator.show(); f.model.select(.trash); settle()
        let window = try #require(f.coordinator.window)
        let root = try #require(window.contentView)
        let row = try #require(descendants(root).compactMap { $0 as? LibraryRowInputView }
            .first { $0.bounds.height == f.model.theme.component(.rowHeight) })
        try click(window, at: row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil))
        #expect(f.model.selectedNoteID == note.id); #expect(f.routes.isEmpty)
        try key(row, code: 36, characters: "\r")
        #expect(f.routes == [.openNote(note.id)])
        #expect(try f.notes.listTrash().notes.map(\.id) == [trash.id])
    }

    @Test func sidebarPixelsDoNotChangeWhenOnlyNoteCountsChange() throws {
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
        #expect(before == after, "노트 수만 바뀔 때 사이드바의 숫자나 레이아웃이 바뀌면 안 된다")
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
        #expect(LibraryPreview.progress("본문") == "")
        #expect(LibraryPreview.progress("- [x] 완료\n- [ ] 대기") == "1/2")
    }
}

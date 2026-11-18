#if DEBUG
import AppKit
@_spi(Verification) import Editor
import Models
@_spi(Verification) import NotePanel
import Routing
import Library
import Scheduling
import FloatSettings
import Reminders
import Theme

extension NotePanelCoordinator {
    /// `--debug-passive`: 노트 창이 키 창이 되지 않게 한다(확인용 실행이 사용자의 키 입력을 가져오지 않게).
    func refuseKeyWindowsForVerification() {
        allowsKeyWindows = false
    }
}

/// 확인용 명령을 받는 곳. 디버그 빌드에서 `--debug-control <출력 폴더>`로 켰을 때만 듣는다.
/// 마우스와 키보드를 건드리지 않고 실행 중인 앱의 상태를 바꾸고 읽기 위한 것이다. 릴리스 빌드에는 없다.
///
/// 다른 프로세스가 분산 알림 `local.floating-notes.debug`의 `object`에 `<표> <명령>` 한 줄을 실어 보낸다.
/// 표는 켤 때마다 새로 만들어 `<출력 폴더>/control-token`에 적는다(`DebugControlSession`).
/// 표가 없거나 틀린 명령은 버린다. `scripts/debug-send.sh <출력 폴더> <명령...>`이 표를 읽어 보낸다.
///
/// - `open|close|trash <id>`, `new [<옆에 둘 노트 id>]`, `toggle-hidden`: 라우터나 노트 창으로 넘긴다.
/// - `focus <id>`: 앱을 앞으로 가져와 그 노트 본문에 커서를 둔다. `unfocus`: 그 전에 앞에 있던 앱으로 돌려준다.
///   그 사이에는 사용자가 치는 글자가 그 노트로 들어가므로 짧게만 쓴다.
/// - `hover <id> on|off|auto`, `pin <id> on|off`, `color <id> <팔레트 키|none>`
/// - `menu <id> <파일 이름>`: 더 보기 메뉴를 띄워 그 모습을 PNG로 쓰고 닫는다.
/// - `snapshot <id> <파일 이름>`: 그 노트 창의 내용을 앱 안에서 그려 PNG로 쓴다. 화면을 찍지 않으므로
///   화면 기록 권한이 필요 없지만, 뒤 배경 흐림과 창 그림자는 담기지 않는다.
/// - `dump <파일 이름>`: 떠 있는 노트 창의 틀, 창 단계, 핀, 호버 상태와 메뉴 막대 메뉴, 전역 단축키 등록 결과,
///   앱 메뉴에 보이는 단축키(없어야 한다)를 JSON으로 쓴다.
/// - `type <id> <글자>`: 그 노트 본문 끝에 실제 입력 경로(`insertText`)로 글자를 넣는다. `\n`은 Return이다.
/// - `fold|unfold <id> <줄 번호>`: 그 줄의 토글을 접거나 편다(편집기의 접기 동작).
/// - `editor <id> <파일 이름>`: 편집기의 원문, 접힌 줄, 내용 높이, 문서 뷰와 보이는 영역의 높이를 JSON으로 쓴다.
/// - `command <동작 이름>`: `AppCommand`를 실행한다(단축키가 하는 일).
/// - `key <동작 이름|undo>`: 그 동작의 단축키를 누른 키 이벤트를 만들어 앱 메뉴에 직접 넘긴다
///   (시스템에 이벤트를 보내지 않는다). 메뉴가 받았는지는 `dump`의 `lastKeyHandled`에 남는다.
/// - `status-menu <항목 이름>`: 메뉴 막대 메뉴의 그 항목을 고른 것처럼 한다.
/// - `status-snapshot <파일 이름>`: 메뉴 막대 메뉴의 줄들을 화면에 띄우지 않고 그려 PNG로 쓴다
///   (메뉴 창의 바탕과 모서리는 시스템이 그리므로 담기지 않는다).
/// - `click <id>`: 그 노트 본문을 누른 마우스 이벤트를 이 앱의 이벤트 줄에만 넣는다(시스템에는 보내지 않는다).
///   실제로 누른 것과 같은 길로 처리되므로 누르면 키 창이 되는지 볼 때 쓴다.
/// - `dock-menu <항목 이름>`, `main-menu <항목 이름>`: Dock 메뉴나 앱 메뉴의 보이는 항목을 고른 것처럼 한다.
/// - `menu-bar-icon on|off`: 메뉴 막대 아이콘을 보이거나 감추고 설정에 적는다.
/// - `backdrop light|dark|stripes <파일 이름>`: 떠 있는 노트 창 뒤에 불투명한 단색 창을 깔고, 그 안쪽을 찍을 영역
///   (`screencapture -R`의 `x,y,w,h`)을 파일에 쓴다. `backdrop off`: 치운다.
/// - `move <id> <x>,<y>`: 창을 그 자리(왼쪽 아래 기준)로 옮긴다. `appearance light|dark`: 앱의 모양을 바꾼다.
/// - `capture`: 빠른 캡처를 요청한다(`Route.openCapture`). `browse [<붙일 노트 id>]`: 노트 찾기를 요청한다.
/// - `panel …`: 떠 있는 캡처 바나 노트 찾기에 글자와 키를 넣는다(`DebugQuickPanels`의 주석).
/// - `panel-snapshot capture|browse <파일 이름>`: 그 화면의 내용을 앱 안에서 그려 PNG로 쓴다(`snapshot`과 같다).
/// - `menu-rows-snapshot <id> <파일 이름>`: 실제 메뉴 행 전체를 키 창이 되지 않는 확인용 창에 그린다.
/// - `caret-preview <id>`: passive 실행에서 키 창 없이 본문 커서만 보여 준다.
/// - `title-edit|title-end <id>`: 키 창을 만들 수 없는 passive 실행에서도 제목의 필드 편집기를 확인한다.
/// - `input-key <id> [|]|"|space`: 본문의 `keyDown`에 앱 내부 이벤트 하나를 보낸다.
/// - `input-mark|input-commit <id|title:id|capture|browse> <글자>`: 조합/확정 입력.
/// - `input-check <같은 대상> <파일 이름>`: 자동 입력 설정과 조합 상태를 JSON으로 쓴다.
/// - `date-suggestion <id> [UTF-16 위치]`, `input-command <id|title:id> tab|escape|undo|redo`: 자기 입력 칸의 날짜 제안, 키 경로 확인.
/// - `quit`
///
/// 파일 이름은 출력 폴더 바로 아래의 이름이어야 한다. 경로를 주면 쓰지 않는다.
final class DebugControl {
    static let notificationName = Notification.Name("local.floating-notes.debug")

    private let session: DebugControlSession
    private let router: any Routing
    private let notePanels: NotePanelCoordinator
    private let quickPanels: DebugQuickPanels
    private let editors: NoteEditorFactory
    private let commands: AppCommandDispatcher
    private let currentStatusItem: () -> StatusItemController?
    private let dockMenu: () -> NSMenu?
    private let setMenuBarIconShown: (Bool) -> Void
    /// 떠 있는 짧은 알림의 창과 그 동작(D-041).
    weak var settingsWindow: SettingsCoordinator?
    weak var reminderEditor: ReminderEditorCoordinator?
    weak var fakeCalendar: FakeCalendarBridge?
    weak var library: LibraryCoordinator?
    var setScheduleDateFormat: (String) -> Void = { _ in }
    var reopen: () -> Void = {}
    var simulateActivation: () -> Void = {}
    var toastWindow: () -> NSWindow? = { nil }
    var toastAction: () -> Void = {}
    private var statusItem: StatusItemController? { currentStatusItem() }
    private let hotKeys: GlobalHotKeys?
    private var observer: (any NSObjectProtocol)?
    private var previousApplication: NSRunningApplication?
    private var lastKeyHandled: Bool?
    private let backdrop = DebugBackdrop()
    private var verificationMenu: NSMenu?
    /// 노트 창이 키 창이 되지 않게 켠 실행(`--debug-passive`). `focus`와 `unfocus` 사이에만 푼다.
    private let isPassive: Bool

    init(
        session: DebugControlSession, router: any Routing, notePanels: NotePanelCoordinator,
        quickPanels: DebugQuickPanels, editors: NoteEditorFactory, commands: AppCommandDispatcher, hotKeys: GlobalHotKeys?, isPassive: Bool,
        statusItem: @escaping () -> StatusItemController?, dockMenu: @escaping () -> NSMenu?,
        setMenuBarIconShown: @escaping (Bool) -> Void
    ) {
        self.dockMenu = dockMenu
        self.setMenuBarIconShown = setMenuBarIconShown
        self.isPassive = isPassive
        self.session = session
        self.router = router
        self.notePanels = notePanels
        self.quickPanels = quickPanels
        self.editors = editors
        self.commands = commands
        currentStatusItem = statusItem
        self.hotKeys = hotKeys
    }

    func start() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.notificationName, object: nil, queue: .main
        ) { [weak self] notification in
            guard let payload = notification.object as? String else { return }
            MainActor.assumeIsolated { self?.receive(payload) }
        }
    }

    private func receive(_ payload: String) {
        guard let command = session.command(from: payload) else {
            AppLog.warning("표가 맞지 않는 확인용 명령을 버렸습니다")
            return
        }
        run(command)
    }

    private func run(_ command: String) {
        let words = command.split(separator: " ", maxSplits: 2).map(String.init)
        let id = words.count > 1 ? NoteID(rawValue: words[1]) : nil
        let argument = words.count > 2 ? words[2] : nil
        switch (words.first, id, argument) {
        case ("audit-live-problem", let id?, let name?):
            guard let menu = notePanels.problemMenuForVerification(for: id),
                  let anchor = notePanels.window(for: id)?.contentView, let url = output(named: name) else { return }
            snapshotLiveMenu(menu, anchor: anchor, to: url)
        case ("audit-live-status", let id?, let name?):
            guard let anchor = notePanels.window(for: id)?.contentView, let url = output(named: name) else { return }
            do {
                let theme = try Theme.bundled(appearance: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light)
                let menu = NSMenu()
                StatusMenuBuilder(theme: theme).fill(menu, with: StatusMenuModel.entries(areNotesHidden: false)) { _ in }
                snapshotLiveMenu(menu, anchor: anchor, to: url)
            } catch { AppLog.warning("메뉴 상태 검사 실패: \(error)") }
        case ("audit-live-menu", let id?, let name?):
            guard let menu = notePanels.moreMenuForVerification(for: id),
                  let anchor = notePanels.window(for: id)?.contentView, let url = output(named: name) else { return }
            snapshotLiveMenu(menu, anchor: anchor, to: url)
        case ("audit-hover", let id?, let label?):
            guard let root = notePanels.window(for: id)?.contentView else { return }
            DebugViewAudit.hover(root, label: label)
        case ("audit-drag", let id?, _):
            guard let editor = editor(of: id), let window = editor.textView.window,
                  let first = editor.textPoint(forLine: 1), let last = editor.textPoint(forLine: 4) else { return }
            for (type, point) in [(NSEvent.EventType.leftMouseDown, first), (.leftMouseDragged, last), (.leftMouseUp, last)] {
                let location = editor.textView.convert(point, to: nil)
                guard let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1) else { continue }
                NSApp.postEvent(event, atStart: false)
            }
        case ("audit-select", let id?, let range?):
            guard let editor = editor(of: id) else { return }
            editor.forcesActiveAppearance = true
            if range == "all" { editor.textView.selectAll(nil) }
            else {
                let parts = range.split(separator: ",").compactMap { Int($0) }
                guard parts.count == 2 else { return }
                editor.selectedRange = NSRange(location: parts[0], length: parts[1])
            }
        case ("audit-menu-action", let id?, let title?):
            guard let menu = notePanels.moreMenuForVerification(for: id),
                  let index = menu.items.firstIndex(where: { $0.title == title }) else { return }
            menu.performActionForItem(at: index)
        case ("audit-problem", let id?, let name?):
            guard let url = output(named: name), let menu = notePanels.problemMenuForVerification(for: id) else { return }
            do { try DebugMenuSnapshot.write(menu, to: url) }
            catch { AppLog.warning("문제 메뉴 검사 실패: \(error)") }
        case ("audit-status", let name?, _):
            guard let url = output(named: name.rawValue) else { return }
            do {
                let theme = try Theme.bundled(appearance: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light)
                let menu = NSMenu()
                StatusMenuBuilder(theme: theme).fill(menu, with: StatusMenuModel.entries(areNotesHidden: false)) { _ in }
                try DebugMenuSnapshot.write(menu, to: url)
            } catch { AppLog.warning("메뉴 막대 검사 실패: \(error)") }
        case ("audit-toast", let name?, _):
            guard let url = output(named: name.rawValue) else { return }
            write(toastWindow(), to: url)
        case ("library-mouse", let point?, let action?):
            guard let window = library?.window else { return }
            DebugLibraryInput.mouse(window: window, point: point.rawValue, action: action)
        case ("library-audit", let name?, _):
            guard let root = library?.window?.contentView, let url = output(named: name.rawValue) else { return }
            do { try DebugViewAudit.write(root, to: url) } catch { AppLog.warning("라이브러리 검사 실패: \(error)") }
        case ("library-hover", let label?, let rest):
            if let root = library?.window?.contentView { DebugViewAudit.hover(root, label: label.rawValue + (rest.map { " " + $0 } ?? "")) }
        case ("reminder-key", let key?, _):
            guard let root = reminderEditor?.contentView else { return }
            func field(in view: NSView) -> NSTextField? {
                if let value = view as? NSTextField, value.isEditable { return value }
                return view.subviews.lazy.compactMap { field(in: $0) }.first
            }
            guard let input = field(in: root) else { return }
            input.window?.makeFirstResponder(input)
            guard let editor = input.currentEditor() as? NSTextView else { return }
            let selectors: [String: Selector] = ["down": #selector(NSResponder.moveDown(_:)), "up": #selector(NSResponder.moveUp(_:)),
                "return": #selector(NSResponder.insertNewline(_:)), "escape": #selector(NSResponder.cancelOperation(_:))]
            if let selector = selectors[key.rawValue] { editor.doCommand(by: selector) }
        case ("schedule-dump", let name?, _):
            guard let url = output(named: name.rawValue) else { return }
            let model = reminderEditor?.model
            let state: [String: Any] = ["input": model?.input ?? "", "selected": model?.selectedID ?? "", "candidate": model?.candidateIndex ?? -1,
                "candidateKinds": model?.candidates.map { $0.kind.rawValue } ?? [],
                "candidateTitles": model?.candidates.map { $0.title } ?? [],
                "candidateLabels": model.map { model in model.candidates.map { model.presentation($0).accessibilityLabel(title: $0.title) } } ?? [],
                "items": model?.items.map { ["id": $0.id, "title": $0.title, "kind": $0.kind.rawValue] } ?? [],
                "permissionRequests": fakeCalendar?.authorizationPromptAttempts.count ?? -1,
                "error": model?.error ?? ""]
            do { try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]).write(to: url) }
            catch { AppLog.warning("예정 검사 저장 실패: \(error)") }
        case ("schedule-format", let value?, _):
            if ["relative", "absolute"].contains(value.rawValue) { setScheduleDateFormat(value.rawValue) }
        case ("space-edit", let value?, _):
            library?.model.beginSpaceEditing(value.rawValue == "new" ? nil : SpaceID(rawValue: value.rawValue))
        case ("space-name", let value?, let rest): library?.model.spaceName = value.rawValue + (rest.map { " " + $0 } ?? "")
        case ("space-submit", _, _): library?.model.submitSpaceEditing()
        case ("space-cancel", _, _): library?.model.cancelSpaceEditing()
        case ("reminder-input", let value?, let rest): reminderEditor?.model?.input = value.rawValue + (rest.map { " " + $0 } ?? "")
        case ("reminder-select", let value?, _): reminderEditor?.model?.select(value.rawValue == "new" ? nil : value.rawValue)
        case ("reminder-candidate", let value?, _): if let index = Int(value.rawValue) { reminderEditor?.model?.candidateIndex = index }
        case ("reminder-submit", _, _): reminderEditor?.model?.submitCandidate()
        case ("reminder-toggle", let value?, _): reminderEditor?.model?.toggleCompleted(value.rawValue)
        case ("fake-access", let value?, _):
            fakeCalendar?.isAllowed = value.rawValue == "on"
            reminderEditor?.model?.reload()
        case ("reminder-audit", let name?, _):
            guard let root = reminderEditor?.contentView, let url = output(named: name.rawValue) else { return }
            do { try DebugViewAudit.write(root, to: url) } catch { AppLog.warning("예정 화면 검사 실패: \(error)") }
        case ("reminder-editor", let id?, _): router.route(.openReminderEditor(id))
        case ("reminder-date", let action?, _):
            guard let model = reminderEditor?.model else { return }
            switch action.rawValue {
            case "open": model.showDates()
            case "scroll": model.datePicker?.scrollWeeks(3)
            case "months": model.datePicker?.choosingMonth = true
            case "close": model.datePicker = nil
            default: break
            }
        case ("date-snapshot", let name?, _):
            if let url = output(named: name.rawValue) { write(reminderEditor?.model?.pickerWindow, to: url) }
        case ("upcoming-detail", _, _):
            if let model = library?.model {
                if let entry = model.index.upcoming.first(where: { if case .note = $0 { true } else { false } }) {
                    model.pinUpcoming(entry.id)
                }
            }
        case ("reminder-close", _, _): reminderEditor?.close()
        case ("reminder-snapshot", let name?, _):
            guard let url = output(named: name.rawValue) else { return }
            write(reminderEditor?.contentView?.window, to: url)
        case ("fake-complete", let id?, _): fakeCalendar?.changeExternally(id.rawValue) { $0.isCompleted = true }
        case ("fake-delete", let id?, _): fakeCalendar?.deleteExternally(id.rawValue)
        case ("fake-delay", let id?, _):
            fakeCalendar?.changeExternally(id.rawValue) { item in
                item.start = item.start.addingTimeInterval(3600)
                item.end = item.end?.addingTimeInterval(3600)
            }
        case ("library-key", let key?, _):
            guard let window = library?.window else { return }
            DebugLibraryInput.key(window: window, key: key.rawValue)
        case ("library", _, _): router.route(.openLibrary)
        case ("library-close", _, _): library?.close()
        case ("reopen", _, _): reopen()
        case ("simulate-activation", _, _) where isPassive: simulateActivation()
        case ("library-select", let target?, _):
            let value = target.rawValue
            switch value {
            case "today": library?.model.select(.today)
            case "all": library?.model.select(.all)
            case "floating": library?.model.select(.floating)
            case "trash": library?.model.select(.trash)
            case "archived": library?.model.select(.archived)
            case "reminders": library?.model.select(.reminders)
            default:
                if value.hasPrefix("archive:") { library?.model.select(.archive(String(value.dropFirst(8)))) }
                else { library?.model.select(.space(SpaceID(rawValue: value))) }
            }
        case ("library-open", let id?, _):
            if let note = library?.model.rows.first(where: { $0.id == id }) { library?.model.open(note) }
        case ("settings-value-hover", _, _) where isPassive:
            if let root = settingsWindow?.window?.contentView { DebugViewAudit.hover(root, label: "기본 캘린더") }
        case ("library-views-snapshot", let name?, _) where isPassive:
            guard let library, let url = output(named: name.rawValue) else { return }
            library.model.editingViews = true
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                self?.write(NSApp.windows.first { $0.isVisible && $0.parent === library.window }, to: url)
                library.model.editingViews = false
            }
        case ("settings-popup-snapshot", let name?, _) where isPassive:
            func findPicker(_ view: NSView) -> NSView? {
                if view.accessibilityLabel() == "기본 캘린더", view.menu != nil { return view }
                return view.subviews.lazy.compactMap(findPicker).first
            }
            if let root = settingsWindow?.window?.contentView, let button = findPicker(root), let menu = button.menu,
               let url = output(named: name.rawValue) { snapshotLiveMenu(menu, anchor: button, to: url) }
        case ("settings-format-bar", let mode?, _) where isPassive:
            guard NoteDisplayOptions.FormatBar(rawValue: mode.rawValue) != nil else { return }
            settingsWindow?.model.change { $0.formatBar = mode.rawValue }
        case ("settings-input-style", let value?, _) where isPassive:
            settingsWindow?.model.change { $0.markedTextStyle = value.rawValue == "underline" ? .underline : .none }
        case ("settings-reset-sheet", _, _) where isPassive:
            settingsWindow?.confirmReset()
        case ("settings-sheet-snapshot", let name?, _) where isPassive:
            if let url = output(named: name.rawValue) { write(settingsWindow?.window?.attachedSheet, to: url) }
        case ("settings-reset-answer", let value?, _) where isPassive:
            if let sheet = settingsWindow?.window?.attachedSheet {
                settingsWindow?.window?.endSheet(sheet, returnCode: value.rawValue == "restore" ? .alertFirstButtonReturn : .alertSecondButtonReturn)
            }
        case ("format-bold", let id?, _) where isPassive:
            editor(of: id)?.perform(.bold)
        case ("settings-close", _, _) where isPassive:
            settingsWindow?.window?.close()
        case ("settings-pane", let pane?, _):
            guard let selection = SettingsPane(rawValue: pane.rawValue) else { return }
            settingsWindow?.show(selection)
        case ("settings-snapshot", let name?, _):
            guard let url = output(named: name.rawValue) else { return }
            write(settingsWindow?.window, to: url)
        case ("settings-fake-access", let mode?, _) where isPassive:
            fakeCalendar?.accessByKind = switch mode.rawValue {
            case "new": [.event: .needsRequest, .reminder: .needsRequest]
            case "blocked": [.event: .blocked, .reminder: .blocked]
            default: [:]
            }
        case ("settings-appearance", let value?, _) where isPassive:
            guard ["light", "dark", "system"].contains(value.rawValue) else { return }
            settingsWindow?.model.change { $0.appearance = value.rawValue }
        case ("settings-destination", let kind?, let id?) where isPassive:
            guard let kind = ScheduleItem.Kind(rawValue: kind.rawValue) else { return }
            settingsWindow?.model.choose(id, for: kind)
        case ("settings-connect", let kind?, _) where isPassive:
            guard let kind = ScheduleItem.Kind(rawValue: kind.rawValue) else { return }
            Task { if kind == .event { await settingsWindow?.model.connectRequestedCalendars() } else { await settingsWindow?.model.connect(kind) } }
        case ("library-snapshot", let name?, _):
            guard let url = output(named: name.rawValue) else { return }
            write(library?.window, to: url)
        case ("library-dump", let name?, _):
            guard let url = output(named: name.rawValue), let library else { return }
            let state: [String: Any] = ["visible": library.window?.isVisible == true,
                "rows": library.model.rows.map { $0.id.rawValue },
                "spaces": library.model.spaceList.map { $0.name },
                "archiveMonths": library.model.index.archiveMonths,
                "upcoming": library.model.index.upcoming.count,
                "error": library.model.error ?? "", "keyWindow": library.window?.isKeyWindow == true,
                "pid": ProcessInfo.processInfo.processIdentifier,
                "selection": String(describing: library.model.selection),
                "selectedNote": library.model.selectedNoteID?.rawValue ?? "",
                "input": DebugLibraryInput.state(window: library.window)]
            do { try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]).write(to: url) }
            catch { AppLog.warning("라이브러리 확인 상태 저장 실패: \(error)") }
        case ("library-import", let id?, let name?):
            guard let url = output(named: name) else { return }
            library?.importImageForVerification(url, space: SpaceID(rawValue: id.rawValue))
        case ("library-icon", let id?, let name?):
            library?.model.setIcon(.image(name), for: SpaceID(rawValue: id.rawValue))
        case ("icon-symbol-snapshot", let id?, let name?), ("icon-emoji-snapshot", let id?, let name?), ("icon-image-snapshot", let id?, let name?):
            guard let url = output(named: name), let library else { return }
            do { try library.snapshotIconPicker(space: SpaceID(rawValue: id.rawValue),
                tab: words[0] == "icon-symbol-snapshot" ? 0 : words[0] == "icon-emoji-snapshot" ? 1 : 2, to: url) }
            catch { AppLog.warning("아이콘 스냅숏 실패: \(error)") }
        case ("library-expand", let id?, _): library?.expandSpaceForVerification(SpaceID(rawValue: id.rawValue))
        case ("icon-snapshot", let id?, let name?):
            guard let url = output(named: name), let library else { return }
            do { try library.snapshotIconPicker(space: SpaceID(rawValue: id.rawValue), to: url) }
            catch { AppLog.warning("아이콘 스냅숏 실패: \(error)") }
        case ("open", let id?, _): router.route(.openNote(id))
        case ("close", let id?, _): router.route(.closeNoteWindow(id))
        case ("new", _, _): router.route(.newNote(NewNoteRequest(nextTo: id)))
        case ("toggle-hidden", _, _): router.route(.toggleAllNotesHidden)
        case ("trash", let id?, _): notePanels.moveToTrash(id)
        case ("focus", let id?, _):
            previousApplication = NSWorkspace.shared.frontmostApplication
            notePanels.allowsKeyWindows = true
            NSApplication.shared.activate()
            notePanels.focusBody(of: id)
        case ("unfocus", _, _):
            if isPassive { notePanels.allowsKeyWindows = false }
            notePanels.releaseKeyWindow()
            // 앞에 있던 앱에 차례를 넘긴다. 넘기지 않으면 그 앱의 요청이 받아들여지지 않을 때가 있다.
            if let previous = previousApplication {
                NSApplication.shared.yieldActivation(to: previous)
                previous.activate(from: .current)
            }
            NSApplication.shared.deactivate()
            previousApplication = nil
        case ("hover", let id?, let state?):
            notePanels.setHoverOverride(state == "auto" ? nil : state == "on", for: id)
        case ("pin", let id?, let state?): notePanels.setPinned(state == "on", for: id)
        case ("color", let id?, let key?):
            notePanels.setColor(key == "none" ? nil : PaletteID(rawValue: key), for: id)
        case ("menu-rows-snapshot", let id?, let name?):
            guard let menu = notePanels.moreMenuForVerification(for: id), let url = output(named: name) else { return }
            do { try DebugMenuSnapshot.write(menu, to: url) }
            catch { AppLog.warning("메뉴 행을 그리지 못했습니다: \(error)") }
        case ("menu", let id?, let name?):
            guard let url = output(named: name) else { return }
            showMoreMenu(for: id, snapshotURL: url)
        case ("screen-menu", let id?, let name?):
            guard let url = output(named: name) else { return }
            DebugWindowCapture.captureMenu(to: url) { notePanels.popUpMoreMenu(for: id) }
        case ("screen-status-menu", _, _):
            guard let url = output(named: words.dropFirst().first ?? "") else { return }
            DebugWindowCapture.captureMenu(to: url) { statusItem?.openMenuForVerification() }
        case ("screen-toast", _, _):
            guard let url = output(named: words.dropFirst().first ?? ""),
                  let number = toastWindow()?.windowNumber
            else { return }
            DebugWindowCapture.capture(windowNumber: number, to: url)
        case ("toast-action", _, _): toastAction()
        case ("snapshot", let id?, let name?):
            guard let url = output(named: name) else { return }
            let number = notePanels.snapshot(of: id)?.windowNumber
            write(NSApplication.shared.windows.first { $0.windowNumber == number }, to: url)
        case ("dump", _, _):
            guard let url = output(named: String(command.dropFirst("dump ".count))) else { return }
            dump(to: url)
        case ("input-select-all", let target?, _) where isPassive:
            verificationInput(target.rawValue)?.selectAll(nil)
        case ("input-check", let target?, let name?):
            guard let view = verificationInput(target.rawValue), let url = output(named: name) else { return }
            write(json: DebugInputVerification.state(of: view), to: url)
        case ("input-mark", let target?, let text?):
            guard let view = verificationInput(target.rawValue) else { return }
            view.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        case ("input-commit", let target?, let text?):
            verificationInput(target.rawValue)?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        case ("title-edit", let id?, _): notePanels.beginTitleEditing(for: id)
        case ("title-end", let id?, _): notePanels.window(for: id)?.makeFirstResponder(nil)
        case ("caret-preview", let id?, _):
            guard let editor = editor(of: id) else { return }
            editor.focus()
            editor.forcesActiveAppearance = true
        case ("date-suggestion", let id?, let offset):
            guard let editor = editor(of: id) else { return }
            editor.forcesActiveAppearance = true
            editor.focus()
            editor.selectedRange = NSRange(location: min(editor.text.utf16.count, max(0, offset.flatMap(Int.init) ?? editor.text.utf16.count)), length: 0)
            editor.refreshDateSuggestion()
        case ("input-command", let target?, let command?):
            guard let view = verificationInput(target.rawValue) else { return }
            let selectors = ["tab": "insertTab:", "escape": "cancelOperation:"]
            if let selector = selectors[command] { view.doCommand(by: NSSelectorFromString(selector)) }
            else if command == "undo" { view.undoManager?.undo() }
            else if command == "redo" { view.undoManager?.redo() }
        case ("input-key", let id?, let text?):
            guard let editor = editor(of: id) else { return }
            let chars = text == "space" ? " " : text
            let codes: [String: UInt16] = ["[": 33, "]": 30, "\"": 39, " ": 49]
            guard let code = codes[chars], let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: chars == "\"" ? .shift : [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: editor.textView.window?.windowNumber ?? 0,
                context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code
            ) else { return }
            editor.textView.window?.makeFirstResponder(editor.textView)
            editor.textView.keyDown(with: event)
        case ("type", let id?, let text?): insert(text, into: id)
        case ("fold", let id?, let line?): setFolded(true, line: Int(line), in: id)
        case ("unfold", let id?, let line?): setFolded(false, line: Int(line), in: id)
        case ("editor", let id?, let name?):
            guard let url = output(named: name) else { return }
            dumpEditor(of: id, to: url)
        case ("command", _, _):
            guard let command = words.dropFirst().first.flatMap(AppCommand.init(rawValue:)) else {
                AppLog.warning("모르는 동작입니다: \(command)")
                return
            }
            commands.perform(command)
        case ("key", _, _): pressKey(named: words.dropFirst().first ?? "")
        case ("status-menu", _, _):
            let title = String(command.dropFirst("status-menu ".count))
            let action = statusItem?.entries.compactMap { entry -> StatusMenuAction? in
                if case .item(title, _, let action) = entry { action } else { nil }
            }.first
            guard let action else {
                AppLog.warning("메뉴 막대 메뉴에 없는 항목입니다: \(title)")
                return
            }
            commands.performStatusMenu(action)
        case ("status-snapshot", _, _):
            guard let url = output(named: String(command.dropFirst("status-snapshot ".count))) else { return }
            snapshotStatusMenu(to: url)
        case ("click", let id?, _): click(id)
        case ("dock-menu", _, _): choose(String(command.dropFirst("dock-menu ".count)), in: dockMenu())
        case ("main-menu", _, _):
            choose(String(command.dropFirst("main-menu ".count)), in: NSApplication.shared.mainMenu)
        case ("menu-bar-icon", _, _): setMenuBarIconShown(words.dropFirst().first == "on")
        case ("backdrop", _, _): showBackdrop(words.dropFirst().first ?? "", fileName: argument)
        case ("move", let id?, let point?):
            let numbers = point.split(separator: ",").compactMap { Double($0) }
            guard numbers.count == 2, let window = notePanels.window(for: id) else { return }
            window.setFrameOrigin(NSPoint(x: numbers[0], y: numbers[1]))
        case ("appearance", _, _):
            NSApplication.shared.appearance = NSAppearance(
                named: words.dropFirst().first == "dark" ? .darkAqua : .aqua
            )
        case ("quit", _, _): NSApplication.shared.terminate(nil)
        case ("capture", _, _): router.route(.openCapture)
        case ("browse", _, _): router.route(.openBrowse(anchor: id))
        case ("panel-snapshot", let target?, let name?):
            guard let url = output(named: name) else { return }
            write(quickPanels.window(named: target.rawValue), to: url)
        case ("panel", _, _):
            if !quickPanels.run(Array(words.dropFirst())) { AppLog.warning("모르는 확인용 명령입니다: \(command)") }
        default: AppLog.warning("모르는 확인용 명령입니다: \(command)")
        }
    }

    private func output(named name: String) -> URL? {
        guard let url = session.outputURL(named: name) else {
            AppLog.warning("확인용 출력은 출력 폴더 바로 아래의 파일 이름으로만 받습니다: \(name)")
            return nil
        }
        return url
    }

    /// 자기 앱 메뉴에 방향키만 보내 호버와 같은 실제 선택 바탕을 확인한다.
    private func snapshotLiveMenu(_ menu: NSMenu, anchor: NSView, to url: URL) {
        verificationMenu = menu
        let known = Set(NSApp.windows.map(\.windowNumber))
        let select = Timer(timeInterval: 0.2, repeats: false) { _ in
            MainActor.assumeIsolated {
                if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
                    characters: "\u{F701}", charactersIgnoringModifiers: "\u{F701}", isARepeat: false, keyCode: 125) {
                    NSApp.postEvent(event, atStart: true)
                }
            }
        }
        let capture = Timer(timeInterval: 0.7, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.write(NSApp.windows.first { !known.contains($0.windowNumber) && $0.isVisible }, to: url)
                self?.verificationMenu?.cancelTracking()
            }
        }
        RunLoop.main.add(select, forMode: .common)
        RunLoop.main.add(capture, forMode: .common)
        menu.popUp(positioning: nil, at: .zero, in: anchor)
        select.invalidate()
        capture.invalidate()
        verificationMenu = nil
    }

    /// 메뉴는 닫힐 때까지 돌아오지 않는다. 메뉴가 도는 동안에도 불리는 타이머로 모습을 쓰고 esc를 넣어 닫는다.
    private func showMoreMenu(for id: NoteID, snapshotURL: URL) {
        let known = Set(NSApplication.shared.windows.map(\.windowNumber))
        let timer = Timer(timeInterval: 1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.write(NSApplication.shared.windows.first { !known.contains($0.windowNumber) }, to: snapshotURL)
                guard let escape = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
                    characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53
                ) else { return }
                NSApplication.shared.postEvent(escape, atStart: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        notePanels.popUpMoreMenu(for: id)
    }

    /// 창의 내용 뷰를 앱 안에서 그려 PNG로 쓴다.
    private func write(_ window: NSWindow?, to url: URL) {
        guard let view = window?.contentView?.superview ?? window?.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else {
            AppLog.warning("그릴 창을 찾지 못했습니다: \(url.lastPathComponent)")
            return
        }
        // 화면이 잠겨 있으면 창이 다시 그려지지 않아 미뤄 둔 배치가 남아 있다. 그리기 전에 마친다.
        view.layoutSubtreeIfNeeded()
        view.cacheDisplay(in: view.bounds, to: bitmap)
        do {
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                AppLog.warning("PNG로 바꾸지 못했습니다: \(url.lastPathComponent)")
                return
            }
            try data.write(to: url, options: .atomic)
            try DebugViewAudit.write(view, to: url.appendingPathExtension("json"))
        } catch {
            AppLog.warning("확인용 그림을 쓰지 못했습니다(\(url.path)): \(error)")
        }
    }

    // MARK: - 누르기와 메뉴

    /// 본문 첫 줄을 누르고 뗀 이벤트를 이 앱의 이벤트 줄에 넣는다. 런 루프가 꺼내 실제 누름과 같은 길로 보낸다.
    private func click(_ id: NoteID) {
        guard let window = notePanels.window(for: id), let view = editors.editor(for: id)?.view else {
            AppLog.warning("그 노트의 창이 없습니다: \(id)")
            return
        }
        let point = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.minY + 20), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ) else { return }
            NSApplication.shared.postEvent(event, atStart: false)
        }
    }

    /// 메뉴(와 그 아래 메뉴)에서 그 이름의 보이는 항목을 찾아 고른 것처럼 한다. 열 때처럼 먼저 다시 채우게 한다.
    private func choose(_ title: String, in menu: NSMenu?) {
        func find(in menu: NSMenu) -> (NSMenu, Int)? {
            menu.delegate?.menuNeedsUpdate?(menu)
            menu.update()
            for (index, item) in menu.items.enumerated() {
                if !item.isHidden, item.title == title, item.submenu == nil { return (menu, index) }
                if let found = item.submenu.flatMap(find(in:)) { return found }
            }
            return nil
        }
        guard let menu, let (owner, index) = find(in: menu) else {
            AppLog.warning("메뉴에 없는 항목입니다: \(title)")
            return
        }
        owner.performActionForItem(at: index)
    }

    // MARK: - 배경 창

    private func showBackdrop(_ kind: String, fileName: String?) {
        guard kind != "off" else {
            backdrop.hide()
            return
        }
        let frames = notePanels.openNoteIDs.compactMap { notePanels.snapshot(of: $0)?.frame }
        let color: NSColor = switch kind {
        case "dark": NSColor(white: 0.12, alpha: 1)
        case "stripes": Self.stripes
        default: NSColor(white: 0.93, alpha: 1)
        }
        guard let region = backdrop.show(color: color, around: frames, margin: 28),
              let url = fileName.flatMap(output(named:))
        else { return }
        let line = [region.minX, region.minY, region.width, region.height].map { String(Int($0)) }
        do {
            try Data(line.joined(separator: ",").utf8).write(to: url, options: .atomic)
        } catch {
            AppLog.warning("확인용 출력을 쓰지 못했습니다(\(url.path)): \(error)")
        }
    }

    /// 밝고 어두운 줄무늬. 뒤 배경 흐림이 실제로 걸리는지, 창 밖에 흐림이 남는지 볼 때 쓴다.
    private static var stripes: NSColor {
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { rect in
            NSColor(white: 0.95, alpha: 1).setFill()
            rect.fill()
            NSColor(white: 0.25, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 12, height: 24).fill()
            return true
        }
        return NSColor(patternImage: image)
    }

    // MARK: - 편집기

    private func editor(of id: NoteID) -> MarkdownEditor? {
        guard let editor = editors.editor(for: id)?.editor else {
            AppLog.warning("그 노트의 편집기가 없습니다: \(id)")
            return nil
        }
        return editor
    }

    /// 본문 끝에 글자를 넣는다. 키보드 이벤트가 아니라 텍스트 뷰의 입력 경로를 직접 부른다.
    private func insert(_ text: String, into id: NoteID) {
        guard let editor = editor(of: id) else { return }
        let view = editor.textView
        editor.selectedRange = NSRange(location: (editor.text as NSString).length, length: 0)
        for (index, piece) in text.components(separatedBy: "\\n").enumerated() {
            if index > 0 { view.doCommand(by: #selector(NSResponder.insertNewline(_:))) }
            for character in piece {
                view.insertText(String(character), replacementRange: view.selectedRange())
            }
        }
    }

    private func verificationInput(_ target: String) -> NSTextView? {
        if target == "capture" || target == "browse" { return quickPanels.input(named: target) }
        if target.hasPrefix("title:") {
            let id = NoteID(rawValue: String(target.dropFirst("title:".count)))
            notePanels.beginTitleEditing(for: id)
            return notePanels.window(for: id)?.firstResponder as? NSTextView
        }
        return editor(of: NoteID(rawValue: target))?.textView
    }

    private func setFolded(_ folded: Bool, line: Int?, in id: NoteID) {
        guard let editor = editor(of: id), let line else { return }
        let lines = editor.text.components(separatedBy: "\n")
        guard lines.indices.contains(line) else {
            AppLog.warning("그 줄이 없습니다: \(line)")
            return
        }
        let start = lines[..<line].reduce(0) { $0 + ($1 as NSString).length + 1 }
        editor.selectedRange = NSRange(location: start + (lines[line] as NSString).length, length: 0)
        editor.perform(folded ? .fold : .unfold)
    }

    private func dumpEditor(of id: NoteID, to url: URL) {
        guard let editor = editor(of: id) else { return }
        let view = editor.documentView
        view.window?.contentView?.layoutSubtreeIfNeeded()
        write(json: [
            "text": editor.text,
            "selectionFrames": editor.selectionFrames.map(NSStringFromRect),
            "dateSuggestionHelp": editor.textView.accessibilityHelp() ?? "",
            "selectedRange": NSStringFromRange(editor.selectedRange),
            "markedRange": NSStringFromRange(editor.textView.markedRange()),
            "automaticQuotes": editor.textView.isAutomaticQuoteSubstitutionEnabled,
            "automaticReplacement": editor.textView.isAutomaticTextReplacementEnabled,
            "font": editor.textView.font?.fontName ?? "",
            "fontSize": editor.textView.font?.pointSize ?? 0,
            "caretFrame": editor.caretFrame.map(NSStringFromRect) ?? "",
            "foldedLines": editor.foldedLines.sorted(),
            "contentHeight": editor.contentHeight,
            "documentViewHeight": view.frame.height,
            "documentViewIsFlipped": view.isFlipped,
            "visibleHeight": view.enclosingScrollView?.contentSize.height ?? 0,
            "scrollViewHeight": view.enclosingScrollView?.frame.height ?? 0,
            "windowHeight": view.window?.frame.height ?? 0,
            "windowContentHeight": view.window?.contentView?.frame.height ?? 0,
            "scrollOffset": view.enclosingScrollView?.contentView.bounds.minY ?? 0,
            "contentInsetTop": view.enclosingScrollView?.contentInsets.top ?? 0,
            "contentInsetBottom": view.enclosingScrollView?.contentInsets.bottom ?? 0,
            "isFirstResponder": view.window?.firstResponder === view,
            "canUndo": editor.undoManager.canUndo,
        ], to: url)
    }

    // MARK: - 단축키

    /// 그 동작의 단축키를 누른 것과 같은 키 이벤트를 만들어 앱 메뉴에 넘긴다. 시스템에는 보내지 않는다.
    private func pressKey(named name: String) {
        let chord = name == "undo"
            ? KeyChord(.z, .command)
            : AppCommand(rawValue: name).flatMap(ShortcutTable.standard.chord(for:))
        guard let chord, let event = Self.keyEvent(for: chord) else {
            AppLog.warning("단축키가 없는 동작입니다: \(name)")
            return
        }
        lastKeyHandled = NSApplication.shared.mainMenu?.performKeyEquivalent(with: event) ?? false
    }

    static func keyEvent(for chord: KeyChord) -> NSEvent? {
        let characters = chord.key.menuKeyEquivalent
        return NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: chord.modifiers.eventFlags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: NSApplication.shared.keyWindow?.windowNumber ?? 0, context: nil,
            characters: characters,
            charactersIgnoringModifiers: chord.modifiers.contains(.shift) ? characters.uppercased() : characters,
            isARepeat: false, keyCode: chord.key.keyCode
        )
    }

    /// 메뉴 막대 메뉴의 줄을 위에서부터 쌓아 그린다. 메뉴를 띄우지 않으므로 사용자의 입력을 가로채지 않는다.
    private func snapshotStatusMenu(to url: URL) {
        guard let rows = statusItem?.detachedRowViews, let width = rows.compactMap({ $0?.frame.width }).max() else {
            AppLog.warning("메뉴 막대 메뉴가 없습니다")
            return
        }
        let separatorHeight: CGFloat = 11
        let height = rows.reduce(0) { $0 + ($1?.frame.height ?? separatorHeight) }
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        // 레이어를 쓰는 줄 뷰는 창 안에 있어야 제자리에 그려진다. 화면에 올리지 않는 창에 넣는다.
        let window = NSWindow(
            contentRect: container.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        container.wantsLayer = true
        container.appearance.map { $0.performAsCurrentDrawingAppearance {
            container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        } }
        window.contentView = container
        defer { window.close() }
        var top = height
        for row in rows {
            let rowHeight = row?.frame.height ?? separatorHeight
            top -= rowHeight
            let view = row ?? NSBox(frame: .zero)
            if let box = view as? NSBox { box.boxType = .separator }
            view.frame = row == nil
                ? NSRect(x: 8, y: top + (separatorHeight - 1) / 2, width: width - 16, height: 1)
                : NSRect(x: 0, y: top, width: width, height: rowHeight)
            container.addSubview(view)
        }
        guard let bitmap = container.bitmapImageRepForCachingDisplay(in: container.bounds) else { return }
        container.layoutSubtreeIfNeeded()
        container.cacheDisplay(in: container.bounds, to: bitmap)
        do {
            guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
            try data.write(to: url, options: .atomic)
        } catch {
            AppLog.warning("확인용 그림을 쓰지 못했습니다(\(url.path)): \(error)")
        }
    }

    private func write(json document: [String: Any], to url: URL) {
        do {
            let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        } catch {
            AppLog.warning("확인용 상태를 쓰지 못했습니다(\(url.path)): \(error)")
        }
    }

    /// 앱 메뉴에서 보이는 항목 가운데 단축키가 적힌 것(규칙 4: 없어야 한다).
    private var visibleMainMenuKeyEquivalents: [String] {
        func visit(_ menu: NSMenu) -> [String] {
            // 메뉴를 열 때처럼 먼저 고치게 한다.
            menu.delegate?.menuNeedsUpdate?(menu)
            return menu.items.flatMap { item -> [String] in
                let own = !item.isHidden && !item.keyEquivalent.isEmpty ? [item.title] : []
                return own + (item.submenu.map(visit) ?? [])
            }
        }
        return NSApplication.shared.mainMenu.map(visit) ?? []
    }

    private func dump(to url: URL) {
        let windows = notePanels.openNoteIDs.compactMap(notePanels.snapshot(of:)).map { window in
            [
                "id": window.noteID.rawValue,
                "frame": [window.frame.minX, window.frame.minY, window.frame.width, window.frame.height],
                "pinned": window.isPinned,
                "level": window.level,
                "visible": window.isVisible,
                "key": window.isKey,
                "hovered": window.isHovered,
                "windowNumber": window.windowNumber,
                "problem": window.problem ?? "",
            ] as [String: Any]
        }
        let document: [String: Any] = [
            "hidden": notePanels.areNotesHidden,
            "settingsVisible": settingsWindow?.window?.isVisible == true,
            "libraryVisible": library?.window?.isVisible == true,
            "calendarURL": fakeCalendar?.openedURL?.absoluteString ?? "",
            "orderedNotes": NSApp.orderedWindows.compactMap { window in
                notePanels.openNoteIDs.first { notePanels.window(for: $0) === window }?.rawValue
            },
            "appActive": NSApplication.shared.isActive,
            "appDisplayName": AppDelegate.displayName,
            "mainMenuTitles": NSApplication.shared.mainMenu?.items.map(\.title) ?? [],
            "applicationMenuTitles": NSApplication.shared.mainMenu?.items.first?.submenu?.items
                .filter { !$0.isHidden && !$0.isSeparatorItem }.map(\.title) ?? [],
            "keyWindowNumber": NSApplication.shared.keyWindow?.windowNumber ?? 0,
            "firstResponder": NSApplication.shared.keyWindow?.firstResponder.map { "\(type(of: $0))" } ?? "",
            "windows": windows,
            "frontmostNote": notePanels.frontmostNoteID?.rawValue ?? "",
            "canUndoTrash": notePanels.canUndoTrash,
            "statusItem": [
                "installed": statusItem?.isInstalled ?? false,
                "dockMenu": (dockMenu()?.items ?? []).map { $0.isSeparatorItem ? "" : $0.title },
                "windowNumber": statusItem?.windowNumber ?? 0,
                "items": (statusItem?.menuItems ?? []).map { ["title": $0.title, "keyEquivalent": $0.keyEquivalent] },
            ] as [String: Any],
            "hotKeys": [
                "registered": (hotKeys?.registered ?? [:]).map { "\($0.key.rawValue) \($0.value.labels.joined())" }.sorted(),
                "failures": (hotKeys?.failures ?? []).map(\.warning),
            ],
            "mainMenuVisibleKeyEquivalents": visibleMainMenuKeyEquivalents,
            "lastKeyHandled": lastKeyHandled.map { $0 ? "yes" : "no" } ?? "",
            "unavailableCommands": commands.unavailable.map(\.rawValue),
            "quickPanels": quickPanels.dump(),
            "toastWindowNumber": toastWindow()?.isVisible == true ? toastWindow()?.windowNumber ?? 0 : 0,
            "statusItemLength": statusItem?.length ?? 0,
        ]
        write(json: document, to: url)
    }
}
#endif

import AppKit
import CoreText
import Models
import SwiftUI
import Theme

struct ScheduleDetail: View {
    @Bindable var model: ReminderEditorModel
    let item: ScheduleItem
    let theme: Theme
    private enum Field: Hashable { case title, day, start, end, allDay, calendar, imminentLead }
    @Environment(\.displayScale) private var displayScale
    @State private var lastFocus: Field = .title
    @FocusState private var focus: Field?
    private var destination: ScheduleDestination? { model.destinationForItem(item) }
    private var dateFormat: Date.FormatStyle {
        .dateTime.locale(ScheduleDateSelection.displayLocale).month().day().weekday(.abbreviated)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: theme.component(.iconButtonGap)) {
                iconButton("chevron.left", "목록으로") { model.select(nil) }
                Spacer()
                SegmentGroup(theme: theme) {
                    ForEach([ScheduleItem.Kind.event, .reminder], id: \.self) { kind in
                        Button {
                            guard item.kind != kind else { return }
                            model.hasEnd = kind == .event
                            if model.hasEnd && model.end <= model.start { model.end = model.calendar.date(byAdding: .hour, value: 1, to: model.start)! }
                            model.save()
                        } label: {
                            Text(kind == .event ? "일정" : "리마인더")
                                .font(theme.font(.rowSub, weight: theme.tokens.textStyle(item.kind == kind ? .title : .body).weight))
                                .padding(.horizontal, theme.component(.settingsSegmentPad))
                                .frame(height: theme.component(.segmentItem))
                                .background(item.kind == kind ? theme.color(.surface) : .clear, in: RoundedRectangle(cornerRadius: theme.shape(.controlRadius)))
                        }.buttonStyle(SettingsButton(theme: theme, selected: false)).focusable(false)
                            .accessibilityAddTraits(item.kind == kind ? .isSelected : [])
                    }
                }
                .padding(.trailing, theme.space(.sp1))
                iconButton("trash", "삭제") { model.remove() }
            }.padding(.horizontal, theme.space(.sp1)).frame(height: theme.shape(.chromeHeight))
            HStack(spacing: theme.component(.scheduleInset)) {
                Circle().fill(markerColor).measureScheduleCenter("titleDot").frame(width: theme.component(.menuDot), height: theme.component(.menuDot))
                    .frame(width: theme.component(.iconLarge))
                ScheduleTextLayout(capHeight: theme.nsFont(.scheduleTitle).capHeight) {
                    CommandTextField(text: Binding(get: { model.title }, set: model.changeTitle),
                                     theme: theme, placeholder: "제목", style: .scheduleTitle,
                                     submit: { focus = .day; model.showDates() },
                                     cancel: { model.select(nil) })
                        .measureScheduleCenter("title", capHeight: theme.nsFont(.scheduleTitle).capHeight)
                        .focused($focus, equals: .title)
                }
            }.padding(.horizontal, theme.component(.scheduleInset)).frame(height: theme.shape(.chromeHeight))
            row("clock") {
                HStack(spacing: theme.component(.iconButtonGap)) {
                    Button { model.showDates() } label: {
                        label(dateLabel).fixedSize().frame(height: theme.component(.controlHeight))
                    }.buttonStyle(SettingsButton(theme: theme, selected: model.datePicker != nil)).focused($focus, equals: .day)
                        .background(DatePickerAnchor(model: model))
                    if !model.dateOnly {
                        HStack(spacing: 0) {
                            timeField(isEnd: false)
                            if model.hasEnd {
                                label("~").foregroundStyle(theme.color(.text3)).padding(rangeSeparatorInsets)
                                timeField(isEnd: true)
                            }
                        }
                    }
                }
            }
            row("sun.max") {
                label("종일").foregroundStyle(theme.color(.text2))
                Spacer()
                Toggle("종일", isOn: Binding(get: { model.dateOnly }, set: { value in
                    model.dateOnly = value
                    if !value && model.end <= model.start { model.end = model.calendar.date(byAdding: .hour, value: 1, to: model.start)! }
                    model.save()
                })).labelsHidden().toggleStyle(SettingsSwitch(theme: theme, compact: true)).measureScheduleCenter("switch").focused($focus, equals: .allDay)
            }
            row("calendar") {
                let choices = model.calendarChoices(item.kind)
                DestinationPicker(title: "캘린더", choices: choices, current: destination,
                                  selectedID: item.pendingCalendarID ?? destination?.calendarID ?? (choices.filter { $0.destination == destination }.count == 1
                                      ? choices.first { $0.destination == destination }?.id : nil), includesDefault: false, theme: theme) { id in
                    if let id { model.chooseCalendar(id) }
                }.measureScheduleCenter("calendarValue").disabled(choices.isEmpty).focused($focus, equals: .calendar)
            }
            if model.showsImminentLead {
                row("timer") {
                    label("임박 표시").foregroundStyle(theme.color(.text2))
                    Spacer()
                    ValuePopup(label: "임박 표시", value: item.imminentLeadMinutes?.label ?? model.defaultLeadLabel,
                               theme: theme, makeMenu: makeLeadMenu) { choice in
                        model.chooseImminentLead(ImminentLead(rawValue: choice.tag))
                    }.measureScheduleCenter("leadValue").focused($focus, equals: .imminentLead)
                }
            }
            if let line = item.inlineSource?.line ?? item.todo?.line, line >= 0 {
                theme.color(.line).frame(height: theme.shape(.borderWidth)).padding(.horizontal, theme.component(.scheduleInset))
                    .padding(.vertical, theme.space(.sp1))
                row("text.alignleft") {
                    label("본문 \(line + 1)번째 줄").foregroundStyle(theme.color(.text3))
                }
            }
        }.font(theme.font(.body, size: theme.tokens.textStyle(.ui).size))
            .background(DetailTabOrder(model: model) { backward in
                let times: [Field] = model.dateOnly ? [] : (model.hasEnd ? [.start, .end] : [.start])
                let fields: [Field] = [.title, .day] + times + [.allDay] + (model.calendarChoices(item.kind).isEmpty ? [] : [.calendar])
                    + (model.showsImminentLead ? [.imminentLead] : [])
                let current = focus ?? lastFocus
                let index = fields.firstIndex(of: current) ?? 0
                let next = fields[(index + (backward ? -1 : 1) + fields.count) % fields.count]
                if next != .start && next != .end { focus = next }
                lastFocus = next
                if next == .day { model.showDates() }
                if next == .start || next == .end { model.focusTime(isEnd: next == .end, backward: backward) }
            })
            .onChange(of: model.tabDestination) { _, backward in
                guard let backward else { return }
                if backward { focus = .title }
                else if model.dateOnly { focus = .allDay }
                else { lastFocus = .start; model.focusTime(isEnd: false) }
                model.tabDestination = nil
            }
            .onAppear { focus = .title }
            .onChange(of: focus) { _, next in if let next { lastFocus = next } }
    }

    private func makeLeadMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.minimumWidth = theme.component(.noteMenuWidth)
        func append(_ lead: ImminentLead?) {
            let title = lead?.label ?? model.defaultLeadLabel
            let choice = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let selected = item.imminentLeadMinutes == lead
            choice.state = selected ? .on : .off
            choice.tag = lead?.rawValue ?? 0
            choice.view = PickerMenuRow(theme: theme, text: title, dot: nil, selected: selected, width: menu.minimumWidth)
            menu.addItem(choice)
        }
        append(nil)
        menu.addItem(MenuSeparatorView.item(theme: theme))
        ImminentLead.allCases.forEach { append($0) }
        return menu
    }

    private var markerColor: Color {
        guard let color = destination?.color else { return theme.color(.text2) }
        return Color(.sRGB, red: color.red, green: color.green, blue: color.blue)
    }

    private var dateLabel: String {
        model.start.formatted(dateFormat)
            .replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
    }

    private var rowFont: NSFont { theme.nsFont(.body, size: theme.tokens.textStyle(.ui).size) }

    private var rangeSeparatorInsets: EdgeInsets {
        func pixel(_ value: CGFloat) -> CGFloat { (value * displayScale).rounded() / displayScale }
        func metrics(_ text: String) -> (advance: CGFloat, ink: CGRect) {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: rowFont]))
            return (CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)), CTLineGetBoundsWithOptions(line, .useGlyphPathBounds))
        }

        // NSDatePicker의 한국어 시각은 '오'로 시작하고 분의 마지막 숫자로 끝난다.
        // 선택과 누름 영역은 그대로 두고, 글자가 이미 차지한 안쪽 여백만 목표 간격에서 뺀다.
        let gap = theme.space(.sp2)
        let edge = theme.component(.scheduleClockInset)
        let minute = metrics(String(model.calendar.component(.minute, from: model.start) % 10))
        let mark = metrics("~")
        let startTrailing = pixel(edge + minute.advance - minute.ink.maxX)
        let markWidth = ceil(mark.advance * displayScale) / displayScale
        let markLeading = ceil(mark.ink.minX * displayScale) / displayScale
        let leading = gap - startTrailing - markLeading
        let trailing = gap - (markWidth - pixel(mark.ink.maxX)) - edge
        return EdgeInsets(top: 0, leading: leading, bottom: 0, trailing: trailing)
    }

    private func label(_ value: String) -> some View {
        ScheduleTextLayout(capHeight: rowFont.capHeight) {
            Text(verbatim: value).lineLimit(1).measureScheduleCenter(value, capHeight: rowFont.capHeight)
        }
    }

    private func timeField(isEnd: Bool) -> some View {
        ScheduleTextLayout(capHeight: rowFont.capHeight) {
            ScheduleTimeField(model: model, isEnd: isEnd, theme: theme) { backward in
                let next: Field = backward ? .day : .allDay
                lastFocus = next
                focus = next
                if backward { model.showDates() }
            }
        }
    }

    private func row<Content: View>(_ symbol: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: theme.component(.scheduleInset)) {
            ScheduleGlyph(symbol: symbol, theme: theme).foregroundStyle(theme.color(.text3))
                .frame(width: theme.component(.iconLarge)).measureScheduleCenter(symbol)
            content()
        }.padding(.horizontal, theme.component(.scheduleInset)).frame(height: theme.component(.detailRow))
    }
    private func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ScheduleGlyph(symbol: symbol, theme: theme)
                .frame(width: theme.component(.noteTopButtonSize), height: theme.component(.noteTopButtonSize))
        }.buttonStyle(SettingsButton(theme: theme, selected: false)).focusable(false).accessibilityLabel(label)
    }
}

private struct DatePickerAnchor: NSViewRepresentable {
    let model: ReminderEditorModel
    func makeNSView(context: Context) -> Host {
        let view = Host()
        view.model = model
        return view
    }
    func updateNSView(_ view: Host, context: Context) {}
    final class Host: NSView {
        weak var model: ReminderEditorModel?
        override func viewDidMoveToWindow() { if window != nil { model?.pickerAnchor = self } }
    }
}

private struct DetailTabOrder: NSViewRepresentable {
    let model: ReminderEditorModel
    let step: (Bool) -> Void
    func makeNSView(context: Context) -> Monitor { Monitor() }
    func updateNSView(_ view: Monitor, context: Context) { view.model = model; view.step = step }
    static func dismantleNSView(_ view: Monitor, coordinator: ()) { view.stop() }

    final class Monitor: NSView {
        weak var model: ReminderEditorModel?
        var step: ((Bool) -> Void)?
        private var token: Any?
        override func viewDidMoveToWindow() {
            stop()
            guard window != nil else { return }
            token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === window, event.keyCode == 48,
                      event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                      (window?.firstResponder as? NSTextView)?.hasMarkedText() != true else { return event }
                // 시각을 편집하는 동안에는 AppKit이 세그먼트 사이의 Tab을 처리한다.
                for picker in [model?.startField, model?.endField].compactMap({ $0 }) {
                    if let responder = window?.firstResponder as? NSView,
                       responder === picker || responder.isDescendant(of: picker) || responder === picker.currentEditor() { return event }
                }
                step?(event.modifierFlags.contains(.shift))
                return nil
            }
        }
        func stop() { if let token { NSEvent.removeMonitor(token) }; token = nil }
        isolated deinit { stop() }
    }
}

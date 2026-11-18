import AppKit
import Models
import SwiftUI
import Theme

struct ScheduleDetail: View {
    @Bindable var model: ReminderEditorModel
    let item: ScheduleItem
    let theme: Theme
    private enum Field: Hashable { case title, day, start, end, allDay, calendar }
    @State private var lastFocus: Field = .title
    @FocusState private var focus: Field?
    private var destination: ScheduleDestination? { model.destinationForItem(item) }
    private var dateFormat: Date.FormatStyle {
        .dateTime.locale(Locale(identifier: "ko_KR")).month().day().weekday(.abbreviated)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: theme.space(.sp1)) {
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
                            Text(kind == .event ? "일정" : "리마인더").padding(.horizontal, theme.space(.sp2))
                                .frame(height: theme.component(.segmentItem))
                        }.buttonStyle(SettingsButton(theme: theme, selected: item.kind == kind)).focusable(false)
                    }
                }
                iconButton("trash", "삭제") { model.remove() }
            }.frame(height: theme.space(.sp6))
            HStack(spacing: theme.component(.scheduleInset)) {
                Circle().fill(markerColor).frame(width: theme.component(.scheduleInset), height: theme.component(.scheduleInset))
                    .frame(width: theme.component(.iconLarge))
                CommandTextField(text: Binding(get: { model.title }, set: model.changeTitle),
                                 theme: theme, placeholder: "제목", style: .scheduleTitle,
                                 submit: { focus = .day; model.showDates() },
                                 cancel: { model.select(nil) })
                    .focused($focus, equals: .title)
            }.padding(.horizontal, theme.component(.scheduleInset)).padding(.top, theme.component(.chromePaddingEnd))
                .padding(.bottom, theme.component(.scheduleInset))
            row("clock") {
                HStack(spacing: theme.component(.iconButtonGap)) {
                    Button { model.showDates() } label: {
                        Text(model.start.formatted(dateFormat).replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")).padding(.horizontal, theme.component(.chromePaddingEnd))
                            .frame(height: theme.component(.segmentHeight))
                    }.buttonStyle(SettingsButton(theme: theme, selected: model.datePicker != nil)).focused($focus, equals: .day)
                        .background(DatePickerAnchor(model: model))
                    if !model.dateOnly {
                        timeField(isEnd: false)
                        if model.hasEnd {
                            Text("~").foregroundStyle(theme.color(.text3))
                            timeField(isEnd: true)
                        }
                    }
                }
            }
            row("sun.max") {
                Text("종일").foregroundStyle(theme.color(.text2))
                Spacer()
                Toggle("종일", isOn: Binding(get: { model.dateOnly }, set: { value in
                    model.dateOnly = value
                    if !value && model.end <= model.start { model.end = model.calendar.date(byAdding: .hour, value: 1, to: model.start)! }
                    model.save()
                })).labelsHidden().toggleStyle(SettingsSwitch(theme: theme)).focused($focus, equals: .allDay)
            }
            row("calendar") {
                let choices = model.calendarChoices(item.kind)
                DestinationPicker(title: "캘린더", choices: choices, current: destination,
                                  selectedID: item.pendingCalendarID ?? destination?.calendarID ?? (choices.filter { $0.destination == destination }.count == 1
                                      ? choices.first { $0.destination == destination }?.id : nil), includesDefault: false, theme: theme) { id in
                    if let id { model.chooseCalendar(id) }
                }.disabled(choices.isEmpty).focused($focus, equals: .calendar)
            }
            if let line = item.inlineSource?.line ?? item.todo?.line, line >= 0 {
                theme.color(.line).frame(height: theme.shape(.borderWidth)).padding(.horizontal, theme.component(.scheduleInset))
                    .padding(.vertical, theme.component(.chromePaddingEnd))
                row("text.alignleft") {
                    Text("본문 \(line + 1)번째 줄").font(theme.font(.body, size: theme.tokens.textStyle(.ui).size)).foregroundStyle(theme.color(.text3))
                }
            }
        }.font(theme.font(.body))
            .background(DetailTabOrder { backward in
                let times: [Field] = model.dateOnly ? [] : (model.hasEnd ? [.start, .end] : [.start])
                let fields: [Field] = [.title, .day] + times + [.allDay] + (model.calendarChoices(item.kind).isEmpty ? [] : [.calendar])
                let current: Field = model.startField?.currentEditor() != nil ? .start
                    : (model.endField?.currentEditor() != nil ? .end : focus ?? lastFocus)
                let index = fields.firstIndex(of: current) ?? 0
                let next = fields[(index + (backward ? -1 : 1) + fields.count) % fields.count]
                if next != .start && next != .end { focus = next }
                lastFocus = next
                if next == .day { model.showDates() }
                if next == .start || next == .end { model.focusTime(isEnd: next == .end) }
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

    private var markerColor: Color {
        guard let color = destination?.color else { return theme.color(.text2) }
        return Color(.sRGB, red: color.red, green: color.green, blue: color.blue)
    }

    private func timeField(isEnd: Bool) -> some View {
        ScheduleTimeField(model: model, isEnd: isEnd, theme: theme)
    }

    private func row<Content: View>(_ symbol: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: theme.component(.scheduleInset)) {
            Image(systemName: symbol).font(.system(size: theme.component(.iconLarge))).foregroundStyle(theme.color(.text3))
                .frame(width: theme.component(.iconLarge))
            content()
        }.padding(.horizontal, theme.component(.scheduleInset)).frame(height: theme.component(.detailRow))
    }
    private func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        ChromeIconButton(theme: theme, title: label, symbol: symbol, action: action).focusable(false)
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
    let step: (Bool) -> Void
    func makeNSView(context: Context) -> Monitor { Monitor() }
    func updateNSView(_ view: Monitor, context: Context) { view.step = step }
    static func dismantleNSView(_ view: Monitor, coordinator: ()) { view.stop() }

    final class Monitor: NSView {
        var step: ((Bool) -> Void)?
        private var token: Any?
        override func viewDidMoveToWindow() {
            stop()
            guard window != nil else { return }
            token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === window, event.keyCode == 48,
                      event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                      (window?.firstResponder as? NSTextView)?.hasMarkedText() != true else { return event }
                step?(event.modifierFlags.contains(.shift))
                return nil
            }
        }
        func stop() { if let token { NSEvent.removeMonitor(token) }; token = nil }
        isolated deinit { stop() }
    }
}

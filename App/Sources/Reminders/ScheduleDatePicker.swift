import AppKit
import SwiftUI
import Theme

struct ScheduleDatePicker: View {
    @Bindable var state: ScheduleDateSelection
    let model: ReminderEditorModel
    let theme: Theme
    @FocusState private var gridFocused: Bool
    private let quick = [("오늘", "sun.max"), ("내일", "arrow.right"), ("다음 주", "calendar")]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !state.choosingMonth {
                CommandTextField(text: $state.input, theme: theme, placeholder: "날짜를 입력하세요",
                                 submit: confirm, cancel: { model.datePicker = nil }, move: { delta in
                    if let index = state.quickIndex {
                        state.quickIndex = min(2, max(0, index + delta))
                        state.input = ""
                    } else { state.moveDay(delta * 7) }
                }, moveDay: state.moveDay, tab: model.tabFromDate)
                .padding(.horizontal, theme.space(.sp2)).frame(height: theme.component(.rowHeight))
                rule.padding(.bottom, theme.component(.iconButtonGap))
                ForEach(quick.indices, id: \.self) { index in
                    Button { model.changeDay(state.quickDay(index)) } label: {
                        HStack(spacing: theme.space(.sp2)) {
                            glyph(quick[index].1)
                            Text(quick[index].0)
                            Spacer()
                            Text(state.format(state.quickDay(index), index == 2 ? "M월 d일 E" : "E"))
                                .foregroundStyle(theme.color(.text3))
                        }.padding(.horizontal, theme.space(.sp2)).frame(height: theme.component(.dateCell))
                    }.buttonStyle(SettingsButton(theme: theme, selected: state.quickIndex == index))
                }
                rule.padding(.vertical, theme.space(.sp1)).padding(.horizontal, theme.space(.sp2))
            }
            HStack(spacing: theme.component(.iconButtonGap)) {
                Button(state.format(state.month, state.choosingMonth ? "yyyy년" : "yyyy년 M월")) {
                    state.monthCursor = nil
                    state.choosingMonth.toggle()
                    gridFocused = true
                }.buttonStyle(.plain).font(theme.font(.title))
                Spacer()
                arrow("chevron.left", label: "이전", direction: -1)
                arrow("chevron.right", label: "다음", direction: 1)
            }.frame(height: theme.component(.rowHeight)).padding(.leading, theme.space(.sp2))
                .padding(.trailing, theme.component(.iconButtonGap))
            Group {
                if state.choosingMonth { months } else { days }
            }.focusable().focused($gridFocused).focusEffectDisabled()
                .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .return]) { press in
                    if press.key == .return {
                        if state.choosingMonth { state.showMonth(state.month) }
                        else { model.changeDay(state.cursor) }
                        return .handled
                    }
                    let offset: Int
                    switch press.key {
                    case .leftArrow: offset = -1
                    case .rightArrow: offset = 1
                    case .upArrow: offset = -7
                    default: offset = 7
                    }
                    if state.choosingMonth {
                        let jump = abs(offset) == 7 ? offset.signum() * 4 : offset
                        state.moveMonthCursor(jump)
                    } else { state.moveDay(offset) }
                    return .handled
                }
        }.font(theme.font(.body, size: theme.tokens.textStyle(.ui).size))
            .foregroundStyle(theme.color(.text)).padding(theme.component(.chromePaddingEnd))
            .frame(width: theme.component(.datePickerWidth)).fixedSize(horizontal: false, vertical: true)
            .background(theme.color(.surface), in: RoundedRectangle(cornerRadius: theme.component(.pickerRadius)))
            .focusEffectDisabled().onExitCommand { model.datePicker = nil }
    }

    private func confirm() {
        if !state.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let parsed = state.parse() { model.applyExpression(parsed) }
        } else if let quick = state.quickIndex { model.changeDay(state.quickDay(quick)) }
        else { model.changeDay(state.cursor) }
    }

    private var rule: some View { theme.color(.line).frame(height: theme.shape(.borderWidth)) }
    @ViewBuilder private func glyph(_ name: String) -> some View {
        if name == "calendar" {
            // 확정 시안의 16 x 16 뷰박스 경로. 외곽과 머리 구분선만 그린다.
            Canvas { context, size in
                context.scaleBy(x: size.width / 16, y: size.height / 16)
                var path = Path(roundedRect: CGRect(x: 2.5, y: 3, width: 11, height: 10.5), cornerRadius: 2)
                path.move(to: CGPoint(x: 2.5, y: 6.5))
                path.addLine(to: CGPoint(x: 13.5, y: 6.5))
                context.stroke(path, with: .color(theme.color(.text2)),
                               style: StrokeStyle(lineWidth: theme.component(.iconStroke), lineCap: .round, lineJoin: .round))
            }.frame(width: theme.component(.iconSmall), height: theme.component(.iconSmall))
                .accessibilityHidden(true)
        } else {
            Image(systemName: name).font(.system(size: theme.component(.iconMedium))).foregroundStyle(theme.color(.text2))
        }
    }
    private func arrow(_ name: String, label: String, direction: Int) -> some View {
        Button { state.moveHeader(direction); gridFocused = true } label: {
            Image(systemName: name).font(theme.font(.librarySection)).foregroundStyle(theme.color(.text2)).frame(width: theme.component(.controlHeight), height: theme.component(.controlHeight))
        }.buttonStyle(SettingsButton(theme: theme, selected: false)).accessibilityLabel(label)
    }
    private var days: some View {
        VStack(spacing: theme.shape(.borderWidth)) {
            HStack(spacing: 0) {
                ForEach(["일","월","화","수","목","금","토"], id: \.self) { day in
                    Text(day).font(theme.font(.librarySection)).foregroundStyle(theme.color(.text3))
                        .frame(maxWidth: .infinity)
                }
            }.frame(height: theme.component(.badgeHeight))
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        let date = state.day(row * 7 + col, from: state.week)
                        let today = state.calendar.isDate(date, inSameDayAs: state.now)
                        let selected = state.calendar.isDate(date, inSameDayAs: state.cursor)
                        Button { model.changeDay(date) } label: {
                            Text(String(state.calendar.component(.day, from: date)))
                                .font(theme.font(.rowSub)).monospacedDigit()
                                .foregroundStyle(theme.color(today ? .warn : date < state.calendar.startOfDay(for: state.now) ? .text3 : .text))
                                .frame(width: theme.component(.dateCell), height: theme.component(.dateCell))
                                .background(selected ? theme.color(.selected) : .clear, in: Circle())
                        }.buttonStyle(.plain).focusable(false).frame(maxWidth: .infinity)
                            .accessibilityLabel(state.format(date, "yyyy년 M월 d일 E"))
                    }
                }
            }
        }.padding(.horizontal, theme.space(.sp1)).padding(.bottom, theme.space(.sp1))
            .background(WeekScroll(step: theme.component(.dateCell), move: state.scrollWeeks))
    }
    private var months: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 4), spacing: theme.component(.chromePaddingEnd)) {
            ForEach(1...12, id: \.self) { index in
                let year = state.calendar.component(.year, from: state.month)
                let date = state.calendar.date(from: DateComponents(year: year, month: index, day: 1))!
                Button { state.showMonth(date); gridFocused = true } label: {
                    Text("\(index)월").foregroundStyle(theme.color(state.calendar.isDate(date, equalTo: state.now, toGranularity: .month) ? .warn : .text))
                        .padding(.horizontal, theme.space(.sp2)).frame(height: theme.component(.segmentHeight))
                        .background(state.calendar.isDate(date, equalTo: state.monthCursor ?? state.cursor, toGranularity: .month) ? theme.color(.selected) : .clear, in: Capsule())
                }.buttonStyle(.plain)
            }
        }.padding(.vertical, theme.component(.chromePaddingEnd))
    }
}

private struct WeekScroll: NSViewRepresentable {
    let step: CGFloat
    let move: (Int) -> Void
    func makeNSView(context: Context) -> WheelView { WheelView() }
    func updateNSView(_ view: WheelView, context: Context) { view.step = step; view.move = move }
    static func dismantleNSView(_ view: WheelView, coordinator: ()) { view.stop() }

    final class WheelView: NSView {
        var step: CGFloat = 1
        var move: ((Int) -> Void)?
        var remainder: CGFloat = 0
        private var monitor: Any?
        override func viewDidMoveToWindow() {
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === window, bounds.contains(convert(event.locationInWindow, from: nil)) else { return event }
                if event.phase == .began { remainder = 0 }
                remainder -= event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * step
                let weeks = Int(remainder / step)
                if weeks != 0 { move?(weeks); remainder -= CGFloat(weeks) * step }
                return nil
            }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
        isolated deinit { stop() }
    }
}

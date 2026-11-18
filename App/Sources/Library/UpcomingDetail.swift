import Models
import SwiftUI
import Theme

struct UpcomingBounds: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension UpcomingRow {
    func sidebarTime(now: Date, calendar: Calendar, clock: NoteDisplayOptions.ClockFormat) -> String {
        let start = item.start
        if calendar.isDate(start, inSameDayAs: now) {
            return item.isDateOnly ? "오늘" : ReminderPresentation.clock(start, format: clock, calendar: calendar)
        }

        let label: String
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(start, inSameDayAs: tomorrow) {
            label = "내일"
        } else if calendar.isDate(start, equalTo: now, toGranularity: .weekOfYear) {
            let style = Date.FormatStyle(locale: Locale(identifier: "ko_KR"), calendar: calendar, timeZone: calendar.timeZone)
            label = start.formatted(style.weekday(.abbreviated))
        } else {
            return "\(calendar.component(.month, from: start))월 \(calendar.component(.day, from: start))일"
        }
        return item.isDateOnly ? label : label + " " + ReminderPresentation.clock(start, format: .twentyFourHour, calendar: calendar)
    }
}

private extension UpcomingRow {
    var title: String {
        if !item.title.isEmpty { return item.title }
        if case .note(let note, _) = self { return LibraryPreview(note).upcomingTitle(for: item) }
        return "일정"
    }

    func destination(_ model: LibraryModel) -> ScheduleDestination? {
        switch self {
        case .note: model.markerDestination(for: item)
        case .calendar(let event): event.destination
        }
    }

    func detailTime(_ model: LibraryModel) -> String {
        var options = model.displayOptions
        options.reminder = .time
        return ReminderPresentation(item: item, now: model.index.now, options: options, calendar: model.index.calendar).text ?? ""
    }

    func color(_ model: LibraryModel) -> Color {
        guard let color = destination(model)?.color else { return model.theme.color(.text2) }
        return Color(.sRGB, red: color.red, green: color.green, blue: color.blue)
    }
}

struct UpcomingButton: View {
    let model: LibraryModel
    let entry: UpcomingRow
    private var theme: Theme { model.theme }

    var body: some View {
        let selected = model.upcomingID == entry.id
        Button {
            model.toggleUpcoming(entry.id)
        } label: {
            HStack(spacing: theme.space(.sp2)) {
                Circle().fill(entry.item.kind == .event ? entry.color(model) : .clear)
                    .overlay { Circle().strokeBorder(entry.color(model), lineWidth: theme.component(.iconStroke)) }
                    .frame(width: theme.component(.badgeDot), height: theme.component(.badgeDot))
                    .frame(width: theme.component(.iconLarge))
                Text(entry.title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Text(entry.sidebarTime(now: model.index.now, calendar: model.index.calendar, clock: model.displayOptions.clock))
                    .lineLimit(1).font(theme.libraryNumberFont)
                    .frame(maxWidth: theme.component(.libraryUpcomingTimeWidth), alignment: .trailing).fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(theme.libraryColor(selected ? .text2 : .text3)).layoutPriority(1)
            }.padding(.horizontal, theme.space(.sp2)).frame(height: theme.component(.rowHeight))
                .font(theme.font(.body, size: theme.tokens.textStyle(.ui).size))
                .foregroundStyle(theme.libraryColor(selected ? .text : .text2))
        }.buttonStyle(LibraryButtonStyle(theme: theme, selected: selected, hoverName: entry.id))
            .anchorPreference(key: UpcomingBounds.self, value: .bounds) { [entry.id: $0] }
            .background {
                if selected { UpcomingBoundsView(model: model, isSource: true) }
            }
    }
}

struct UpcomingDetail: View {
    let model: LibraryModel
    let entry: UpcomingRow
    private var theme: Theme { model.theme }

    let rowMidY: CGFloat
    let availableHeight: CGFloat
    @State private var height: CGFloat = 0

    var body: some View {
        let gap = theme.component(.chromePaddingEnd)
        let top = min(max(0, rowMidY - theme.component(.controlHeight)), max(0, availableHeight - height))
        let bubble = UpcomingBubble(tipY: rowMidY - top, radius: theme.shape(.windowRadius), tail: gap)
        let shadow = theme.shadow(.pop).last
        VStack(alignment: .leading, spacing: 0) {
            Text(entry.title).font(theme.font(.title)).lineLimit(1)
            Text(entry.detailTime(model)).font(theme.libraryNumberFont)
                .foregroundStyle(theme.libraryColor(.text2)).padding(.top, theme.space(.sp1))
            if let destination = entry.destination(model) {
                HStack(spacing: gap) {
                    Circle().fill(entry.color(model)).frame(width: theme.component(.badgeDot), height: theme.component(.badgeDot))
                    Text(destination.name).lineLimit(1)
                }.font(theme.libraryNumberFont).foregroundStyle(theme.libraryColor(.text3))
                    .padding(.top, theme.component(.iconButtonGap))
            }
            Button {
                model.dismissUpcoming()
                switch entry {
                case .note(let note, _): _ = model.router.route(.openNote(note.id))
                case .calendar(let event): model.openCalendarEvent(event)
                }
            } label: {
                HStack(spacing: theme.component(.badgePad)) {
                    switch entry {
                    case .note(let note, _):
                        LibrarySymbol(theme: theme, name: "note.text", size: .iconSmall)
                        Text(LibraryPreview(note).title)
                    case .calendar:
                        LibrarySymbol(theme: theme, name: "calendar", size: .iconSmall)
                        Text("캘린더에서 열기")
                    }
                    Spacer(minLength: 0)
                }.font(theme.font(.rowSub)).foregroundStyle(theme.libraryColor(.text2)).lineLimit(1)
                    .padding(.horizontal, gap).frame(height: theme.component(.controlHeight))
            }.buttonStyle(LibraryButtonStyle(theme: theme, hoverName: "일정 연결 열기"))
                .padding(.horizontal, -gap).padding(.top, theme.space(.sp2))
        }.padding(.horizontal, theme.space(.sp3)).padding(.top, theme.component(.scheduleInset))
            .padding(.bottom, gap).frame(width: theme.component(.upcomingWidth))
            .background {
                bubble.fill(theme.color(.surface))
                    .shadow(color: shadow?.color.color ?? .clear, radius: (shadow?.blur ?? 0) / 2, y: shadow?.y ?? 0)
                bubble.stroke(theme.libraryColor(.line), lineWidth: theme.shape(.borderWidth))
            }
            .background(UpcomingBoundsView(model: model, isSource: false))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .offset(y: top)
    }
}

private nonisolated struct UpcomingBubble: Shape {
    let tipY: CGFloat
    let radius: CGFloat
    let tail: CGFloat
    func path(in rect: CGRect) -> Path {
        let y = min(max(tipY, radius + tail), rect.height - radius - tail)
        var pointer = Path()
        pointer.move(to: CGPoint(x: rect.minX, y: y - tail))
        pointer.addLine(to: CGPoint(x: rect.minX - tail, y: y))
        pointer.addLine(to: CGPoint(x: rect.minX, y: y + tail))
        pointer.closeSubpath()
        return Path(roundedRect: rect, cornerRadius: radius).union(pointer)
    }
}

private struct UpcomingBoundsView: NSViewRepresentable {
    let model: LibraryModel
    let isSource: Bool
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        if isSource { model.upcomingSourceView = view } else { model.upcomingDetailView = view }
    }
}

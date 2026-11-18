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
            model.pinUpcoming(entry.id)
        } label: {
            HStack(spacing: theme.space(.sp2)) {
                Circle().fill(entry.item.kind == .event ? entry.color(model) : .clear)
                    .overlay { Circle().strokeBorder(entry.color(model), lineWidth: theme.component(.iconStroke)) }
                    .frame(width: theme.component(.menuDot), height: theme.component(.menuDot))
                    .frame(width: theme.component(.iconLarge))
                Text(entry.title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Text(entry.sidebarTime(now: model.index.now, calendar: model.index.calendar, clock: model.displayOptions.clock))
                    .lineLimit(1).font(theme.libraryNumberFont)
                    .frame(maxWidth: theme.component(.libraryUpcomingTimeWidth), alignment: .trailing).fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(theme.libraryColor(.text3)).layoutPriority(1)
            }.padding(.horizontal, theme.space(.sp2)).frame(height: theme.component(.rowHeight))
                .font(theme.font(.body, size: theme.tokens.textStyle(.ui).size, weight: theme.tokens.textStyle(selected ? .selected : .body).weight))
                .foregroundStyle(theme.libraryColor(selected ? .text : .text2))
        }.buttonStyle(LibraryButtonStyle(theme: theme, selected: selected))
            .anchorPreference(key: UpcomingBounds.self, value: .bounds) { [entry.id: $0] }
            .background(LibrarySidebarHover(name: entry.id) { inside in
                model.hoverUpcoming(entry.id, inside: inside)
            })
            .onDisappear { model.hoverUpcoming(entry.id, inside: false) }
    }
}

struct UpcomingDetail: View {
    let model: LibraryModel
    let entry: UpcomingRow
    private var theme: Theme { model.theme }

    var body: some View {
        let shadows = theme.shadow(.pop)
        let far = shadows.first
        let near = shadows.dropFirst().first
        return VStack(alignment: .leading, spacing: theme.space(.sp1)) {
            Text(entry.title).font(theme.font(.paneTitle)).lineLimit(1)
            Text(entry.detailTime(model)).font(theme.font(.body, size: theme.tokens.textStyle(.ui).size).monospacedDigit())
            if let destination = entry.destination(model) {
                HStack(spacing: theme.component(.chromePaddingEnd)) {
                    Circle().fill(entry.color(model)).frame(width: theme.component(.badgeDot), height: theme.component(.badgeDot))
                    Text(destination.name).font(theme.font(.body, size: theme.tokens.textStyle(.micro).size))
                        .foregroundStyle(theme.libraryColor(.text3))
                }
            }
            theme.color(.line).frame(height: theme.shape(.borderWidth))
            Button {
                model.dismissUpcoming()
                switch entry {
                case .note(let note, _): _ = model.router.route(.openNote(note.id))
                case .calendar(let event): model.openCalendarEvent(event)
                }
            } label: {
                HStack(spacing: theme.space(.sp2)) {
                    switch entry {
                    case .note(let note, _):
                        LibrarySymbol(theme: theme, name: "note.text", size: .iconLarge)
                        Text(LibraryPreview(note).title)
                    case .calendar:
                        LibrarySymbol(theme: theme, name: "calendar", size: .iconLarge)
                        Text("캘린더에서 열기")
                    }
                    Spacer()
                    LibrarySymbol(theme: theme, name: "chevron.right", size: .iconSmall)
                }.font(theme.font(.body, size: theme.tokens.textStyle(.ui).size)).lineLimit(1)
                    .padding(.horizontal, theme.space(.sp1)).frame(height: theme.component(.rowHeight))
            }.buttonStyle(LibraryButtonStyle(theme: theme, hoverName: "일정 연결 열기"))
        }.padding(theme.space(.sp3)).frame(width: theme.component(.upcomingWidth))
            .background(theme.color(.surface), in: RoundedRectangle(cornerRadius: theme.component(.pickerRadius)))
            .overlay { RoundedRectangle(cornerRadius: theme.component(.pickerRadius)).strokeBorder(theme.color(.line), lineWidth: theme.shape(.borderWidth)) }
            .shadow(color: near?.color.color ?? .clear, radius: (near?.blur ?? 0) / 2, x: near?.x ?? 0, y: near?.y ?? 0)
            .shadow(color: far?.color.color ?? .clear, radius: (far?.blur ?? 0) / 2, x: far?.x ?? 0, y: far?.y ?? 0)
    }
}

/// 바깥 클릭을 판별하되 다른 행의 클릭과 호버는 그대로 전달한다.
struct UpcomingDetailBounds: NSViewRepresentable {
    let model: LibraryModel
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        model.upcomingDetailView = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}

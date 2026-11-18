import AppKit
import SwiftUI
import Theme

/// 시각 칩 하나가 Tab 한 정거장이다. 편집을 끝낼 때 원래 날짜 위에 시각만 얹는다.
struct ScheduleTimeField: NSViewRepresentable {
    let model: ReminderEditorModel
    let isEnd: Bool
    let theme: Theme

    func makeNSView(context: Context) -> CommandInputField {
        let field = CommandInputField(theme: theme)
        field.delegate = context.coordinator
        field.setAccessibilityLabel(isEnd ? "끝" : "시작")
        if isEnd { model.endField = field } else { model.startField = field }
        return field
    }
    func updateNSView(_ field: CommandInputField, context: Context) {
        context.coordinator.parent = self
        field.apply(font: theme.nsFont(.body), ink: theme.nsColor(.text), placeholderInk: theme.nsColor(.text3))
        if field.currentEditor() == nil { field.stringValue = displayed }
    }
    private var displayed: String {
        ReminderPresentation.clock(isEnd ? model.end : model.start, format: model.displayOptions.clock, calendar: model.calendar)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CommandInputField, context: Context) -> CGSize? {
        let sample = model.displayOptions.clock == .twentyFourHour ? "23:59" : "오후 12:59"
        let width = (sample as NSString).size(withAttributes: [.font: theme.nsFont(.body)]).width
        return CGSize(width: ceil(width) + theme.space(.sp1), height: ceil(nsView.intrinsicContentSize.height))
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ScheduleTimeField
        init(_ parent: ScheduleTimeField) { self.parent = parent }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let model = parent.model
            let input = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard input != parent.displayed else { return }
            let formatter = DateFormatter()
            formatter.calendar = model.calendar
            formatter.timeZone = model.calendar.timeZone
            for (locale, format) in [("ko_KR", "a h:mm"), ("en_US_POSIX", "h:mm a"), ("en_US_POSIX", "H:mm")] {
                formatter.locale = Locale(identifier: locale)
                formatter.dateFormat = format
                guard let clock = formatter.date(from: input) else { continue }
                let day = parent.isEnd ? model.end : model.start
                let parts = model.calendar.dateComponents([.hour, .minute], from: clock)
                guard let date = model.calendar.date(bySettingHour: parts.hour!, minute: parts.minute!, second: 0, of: day) else { continue }
                if parent.isEnd { model.end = date }
                else { model.end = date.addingTimeInterval(model.end.timeIntervalSince(model.start)); model.start = date }
                model.save()
                break
            }
            field.stringValue = parent.displayed
        }
    }
}

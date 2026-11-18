import SwiftUI
import Models

package struct ScheduleMarker: View {
    let item: ScheduleItem
    let destination: ScheduleDestination?
    let theme: Theme
    package init(item: ScheduleItem, destination: ScheduleDestination?, theme: Theme) {
        self.item = item
        self.destination = destination
        self.theme = theme
    }

    private var color: Color {
        if let color = destination?.color { return Color(.sRGB, red: color.red, green: color.green, blue: color.blue) }
        return theme.color(Self.fallback(for: item.kind))
    }
    package static func fallback(for kind: ScheduleItem.Kind) -> ColorToken { kind == .event ? .text : .text2 }
    package var body: some View {
        ZStack {
            if item.kind == .event {
                Rectangle().fill(color).frame(width: theme.component(.scheduleEventBarWidth), height: theme.component(.scheduleReminderCircle))
            } else {
                Circle().strokeBorder(color, lineWidth: theme.shape(.borderWidth))
                    .background(Circle().fill(item.isCompleted ? color : .clear))
                    .frame(width: theme.component(.scheduleReminderCircle), height: theme.component(.scheduleReminderCircle))
            }
        }.frame(width: theme.component(.scheduleMarkerWidth), height: theme.lineHeight(.body))
    }
}

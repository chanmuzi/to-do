import AppKit
import SwiftUI
import Models
import Theme

struct ReminderEditorView: View {
    @Bindable var model: ReminderEditorModel
    let theme: Theme
    let close: () -> Void
    @State private var hoverID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.component(.iconButtonGap)) {
            if let item = model.selectedItem {
                ScheduleDetail(model: model, item: item, theme: theme).id(item.id)
            } else {
                Text("일정").font(theme.font(.body, size: theme.tokens.textStyle(.micro).size, weight: theme.tokens.textStyle(.selected).weight))
                    .foregroundStyle(theme.color(.text3)).padding(.horizontal, theme.space(.sp2))
                    .frame(height: theme.component(.segmentHeight))
                let items = model.items.filter { !$0.isCompleted }
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            let destination = model.destinationForItem(item)
                            Button { model.select(item.id) } label: {
                                HStack(spacing: theme.component(.scheduleInset)) {
                                    ScheduleMarker(item: item, destination: destination, theme: theme, tall: true)
                                    VStack(alignment: .leading, spacing: theme.component(.iconButtonGap)) {
                                        Text(item.title.isEmpty ? (item.kind == .event ? "일정" : "리마인더") : item.title)
                                            .font(theme.font(.body, size: theme.tokens.textStyle(.ui).size))
                                        Text(model.presentation(item).text ?? "").font(theme.font(.scheduleTime)).foregroundStyle(theme.color(.text2))
                                    }.lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                    if let destination {
                                        Text(destination.name).font(theme.font(.librarySection)).foregroundStyle(theme.color(.text3)).lineLimit(1)
                                    }
                                    Image(systemName: "chevron.right").font(theme.font(.librarySection)).foregroundStyle(theme.color(.text3))
                                }.padding(.horizontal, theme.space(.sp2)).frame(height: theme.component(.scheduleRowHeight))
                                    .contentShape(Rectangle()).background(hoverID == item.id ? theme.color(.hover) : .clear,
                                                 in: RoundedRectangle(cornerRadius: theme.shape(.controlRadius)))
                            }.buttonStyle(.plain).onHover { hoverID = $0 ? item.id : nil }
                        }
                    }
                }.frame(height: min(CGFloat(items.count) * theme.component(.scheduleRowHeight), theme.component(.scheduleListMaxHeight)))
            }
            if let error = model.error { Text(error).font(theme.font(.rowSub)).foregroundStyle(theme.color(.warn)) }
        }.padding(theme.component(.chromePaddingEnd))
            .frame(width: theme.component(model.selectedItem == nil ? .reminderEditorWidth : .detailWidth))
            .fixedSize(horizontal: false, vertical: true)
            .background(theme.color(.surface)).foregroundStyle(theme.color(.text)).focusEffectDisabled()
            .onExitCommand { if model.datePicker != nil { model.datePicker = nil } else { close() } }
    }
}

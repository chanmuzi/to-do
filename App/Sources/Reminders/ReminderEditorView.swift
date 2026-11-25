import AppKit
import SwiftUI
import Models
import Theme

struct ReminderEditorView: View {
    @Bindable var model: ReminderEditorModel
    let theme: Theme
    let close: () -> Void
    @State private var hoverID: String?
    @State private var completionHoverID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.component(.iconButtonGap)) {
            if let item = model.selectedItem {
                ScheduleDetail(model: model, item: item, theme: theme).id(item.id)
            } else {
                Text("일정").font(theme.font(.body, size: theme.tokens.textStyle(.micro).size, weight: theme.tokens.textStyle(.selected).weight))
                    .foregroundStyle(theme.color(.text3)).padding(.horizontal, theme.space(.sp2))
                    .frame(height: theme.component(.segmentHeight))
                let items = model.listItems
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            row(item)
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

    private func row(_ item: ScheduleItem) -> some View {
        let destination = model.destinationForItem(item)
        let title = item.title.isEmpty ? (item.kind == .event ? "일정" : "리마인더") : item.title
        let size = theme.component(.noteTopButtonSize)
        return HStack(spacing: theme.component(.scheduleInset)) {
            if item.kind == .reminder {
                let hovered = completionHovered(item.id)
                Button { model.toggleCompleted(item.id) } label: {
                    ScheduleMarker(item: item, destination: destination, theme: theme, highlighted: hovered)
                        .frame(width: size, height: size)
                        .background(hovered ? theme.color(.hover) : .clear,
                                    in: RoundedRectangle(cornerRadius: theme.shape(.controlRadius)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { completionHoverID = $0 ? item.id : nil }
                .accessibilityLabel((item.isCompleted ? "완료 해제 " : "완료 ") + title)
                .accessibilityValue(item.isCompleted ? "완료됨" : "미완료")
            } else {
                ScheduleMarker(item: item, destination: destination, theme: theme, tall: true)
                    .frame(width: size).accessibilityHidden(true)
            }
            Button { model.select(item.id) } label: {
                HStack(spacing: theme.component(.scheduleInset)) {
                    VStack(alignment: .leading, spacing: theme.component(.iconButtonGap)) {
                        Text(title).font(theme.font(.body, size: theme.tokens.textStyle(.ui).size))
                            .strikethrough(item.isCompleted)
                            .foregroundStyle(theme.color(item.isCompleted ? .text3 : .text))
                        Text(model.presentation(item).text ?? "")
                            .font(theme.font(.scheduleTime)).foregroundStyle(theme.color(.text2))
                    }.lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    if let destination {
                        Text(destination.name).font(theme.font(.librarySection))
                            .foregroundStyle(theme.color(.text3)).lineLimit(1)
                    }
                    Image(systemName: "chevron.right").font(theme.font(.librarySection)).foregroundStyle(theme.color(.text3))
                }.padding(.trailing, theme.space(.sp2)).frame(height: theme.component(.scheduleRowHeight))
                    .contentShape(Rectangle()).background(hoverID == item.id ? theme.color(.hover) : .clear,
                        in: RoundedRectangle(cornerRadius: theme.shape(.controlRadius)))
            }.buttonStyle(.plain).onHover { hoverID = $0 ? item.id : nil }
        }.padding(.leading, theme.space(.sp2))
            .animation(theme.motion.animation, value: completionHoverID)
    }

    private func completionHovered(_ id: String) -> Bool {
        #if DEBUG
        if let previewID = model.previewCompletionHoverID { return previewID == id }
        #endif
        return completionHoverID == id
    }
}

import AppKit
import SwiftUI
import Models
import Theme

struct ReminderEditorView: View {
    @Bindable var model: ReminderEditorModel
    let theme: Theme
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: theme.space(.sp2)) {
            CommandTextField(text: $model.input, theme: theme, placeholder: "예정 입력", style: .scheduleInput,
                ranges: model.expressionRanges, focusToken: model.focusToken, submit: { model.submitCandidate() }, cancel: close, move: model.moveCandidate)
                .padding(.horizontal, theme.space(.sp2)).frame(height: theme.component(.reminderInputHeight))
                .background(theme.color(.surface2), in: RoundedRectangle(cornerRadius: theme.shape(.controlRadius)))
            VStack(spacing: 0) {
                ForEach(Array(model.candidates.enumerated()), id: \.element.id) { index, item in
                    Button { model.chooseCandidate(index) } label: {
                        row(item, title: item.title,
                            selected: model.candidateIndex == index, destination: model.destinationForCandidate(item))
                    }.buttonStyle(.plain).accessibilityElement(children: .ignore)
                        .accessibilityLabel(model.presentation(item).accessibilityLabel(title: item.title))
                }
            }
            if !model.items.isEmpty {
                theme.color(.line).frame(height: theme.shape(.borderWidth))
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.items) { item in
                            existingRow(item)
                        }
                    }
                }.frame(height: min(CGFloat(model.items.count) * theme.component(.scheduleRowHeight), theme.component(.scheduleListMaxHeight)))
            }
            if model.selectedID != nil {
                Button("지우기") { model.remove() }
                    .font(theme.font(.rowSub)).foregroundStyle(theme.color(.text3))
                    .buttonStyle(.plain).frame(height: theme.component(.controlHeight))
            }
            if let error = model.error { Text(error).font(theme.font(.rowSub)).foregroundStyle(theme.color(.text2)) }
        }.padding(theme.space(.sp3)).frame(width: theme.component(.reminderEditorWidth))
            .background(theme.color(.surface)).foregroundStyle(theme.color(.text)).focusEffectDisabled()
            .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : theme.motion.animation, value: model.candidateIndex)
            .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : theme.motion.animation, value: model.selectedID)
            .onExitCommand(perform: close)
    }
    private func existingRow(_ item: ScheduleItem) -> some View {
        HStack(alignment: .top, spacing: theme.space(.sp2)) {
            if item.kind == .reminder {
                Button { model.toggleCompleted(item.id) } label: { marker(item, destination: model.destinationForItem(item)) }
                    .buttonStyle(.plain).accessibilityLabel(item.isCompleted ? "미완료로 바꾸기" : "완료로 바꾸기")
            } else { marker(item, destination: model.destinationForItem(item)) }
            Button { model.select(item.id) } label: {
                rowText(item, title: item.title.isEmpty ? (item.kind == .event ? "일정" : "리마인더") : item.title,
                        selected: model.selectedID == item.id, destination: model.destinationForItem(item))
            }.buttonStyle(.plain)
        }.padding(.horizontal, theme.space(.sp2)).padding(.vertical, theme.space(.sp1))
            .frame(height: theme.component(.scheduleRowHeight))
            .background(model.selectedID == item.id ? theme.color(.selected) : .clear, in: RoundedRectangle(cornerRadius: theme.shape(.controlRadius)))
    }
    private func row(_ item: ScheduleItem, title: String, selected: Bool, destination: ScheduleDestination?) -> some View {
        HStack(alignment: .top, spacing: theme.space(.sp2)) {
            marker(item, destination: destination)
            rowText(item, title: title, selected: selected, destination: destination)
        }.padding(.horizontal, theme.space(.sp2)).padding(.vertical, theme.space(.sp1))
            .frame(height: theme.component(.scheduleRowHeight))
            .contentShape(Rectangle())
            .background(selected ? theme.color(.selected) : .clear, in: RoundedRectangle(cornerRadius: theme.shape(.controlRadius)))
    }
    private func rowText(_ item: ScheduleItem, title: String, selected: Bool, destination: ScheduleDestination?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: theme.space(.sp2)) {
                Text(title).font(theme.font(selected ? .selected : .body)).lineLimit(1)
                    .foregroundStyle(theme.color(item.isCompleted ? .text3 : .text))
                Spacer(minLength: 0)
                if let destination { Text(destination.name).font(theme.font(.rowSub, size: theme.tokens.textStyle(.micro).size)).foregroundStyle(theme.color(.text3)).lineLimit(1) }
            }.frame(height: theme.lineHeight(.body))
            Text(model.presentation(item).text ?? "").font(theme.font(.scheduleTime)).foregroundStyle(theme.color(.text2))
                .lineLimit(1).truncationMode(.tail).frame(height: theme.lineHeight(.scheduleTime))
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .accessibilityLabel(model.presentation(item).accessibilityLabel(title: title))
    }
    private func marker(_ item: ScheduleItem, destination: ScheduleDestination?) -> some View {
        ScheduleMarker(item: item, destination: destination, theme: theme)
    }
}

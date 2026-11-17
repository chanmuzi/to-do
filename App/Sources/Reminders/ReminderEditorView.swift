import AppKit
import SwiftUI
import Observation
import Models
import Store
import Theme

struct ReminderEditorView: View {
    @Bindable var model: ReminderEditorModel
    let theme: Theme
    let close: () -> Void
    @FocusState private var titleFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: theme.space(.sp3)) {
            HStack(spacing: theme.space(.sp2)) {
                Text("리마인더 설정").font(theme.font(.paneTitle))
                Spacer()
                Button("추가") { model.select(nil); titleFocused = true }
            }
            HStack(spacing: theme.space(.sp1)) {
                TextField("제목", text: $model.title).focused($titleFocused)
                    .font(theme.font(.row, weight: theme.tokens.textStyle(.strong).weight))
                    .textFieldStyle(.plain).autocorrectionDisabled().accessibilityLabel("예정 제목")
                if !model.items.isEmpty {
                    Menu {
                        ForEach(model.items) { item in
                            Button(item.title.isEmpty ? "제목 없음" : item.title) {
                                model.select(item.id)
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(theme.font(.ui, size: theme.component(.iconSmall)))
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("수정할 예정")
                }
            }
            .padding(.horizontal, theme.space(.sp2))
            .frame(height: theme.component(.controlHeight))
            .background(theme.color(.surface3), in: RoundedRectangle(cornerRadius: theme.shape(.controlRadius)))
            Toggle("시각 지정", isOn: Binding(get: { !model.dateOnly }, set: { model.dateOnly = !$0 }))
                .toggleStyle(.checkbox)
            DatePicker("시작", selection: $model.start, displayedComponents: model.dateOnly ? [.date] : [.date, .hourAndMinute])
                .datePickerStyle(.field).font(theme.font(.ui))
                .frame(height: theme.component(.controlHeight))
            Toggle("종료 지정", isOn: $model.hasEnd).toggleStyle(.checkbox)
            if model.hasEnd {
                DatePicker("종료", selection: $model.end, displayedComponents: model.dateOnly ? [.date] : [.date, .hourAndMinute])
                    .datePickerStyle(.field).font(theme.font(.ui))
                    .frame(height: theme.component(.controlHeight))
            } else if model.selectedID != nil {
                Toggle("완료", isOn: $model.completed).toggleStyle(.checkbox)
            }
            if let error = model.error { Text(error).foregroundStyle(theme.color(.text2)) }
            HStack(spacing: theme.space(.sp2)) {
                if model.selectedID != nil { Button("삭제") { if model.remove() { close() } } }
                Spacer()
                Button("취소", action: close)
                Button("저장") { if model.save() { close() } }
            }
        }
        .font(theme.font(.row)).foregroundStyle(theme.color(.text))
        .buttonStyle(ReminderActionStyle(theme: theme))
        .padding(theme.space(.sp3)).frame(width: theme.component(.reminderEditorWidth))
        .background(theme.color(.surface)).tint(theme.color(.accent))
        .controlSize(.small).focusEffectDisabled()
        .environment(\.locale, Locale(identifier: "ko_KR"))
        .onAppear { titleFocused = true }
        .onExitCommand(perform: close)
    }
}

private struct ReminderActionStyle: ButtonStyle {
    let theme: Theme
    func makeBody(configuration: Configuration) -> some View {
        ReminderActionBody(theme: theme, pressed: configuration.isPressed, label: configuration.label)
    }
}
private struct ReminderActionBody<Label: View>: View {
    let theme: Theme
    let pressed: Bool
    let label: Label
    @State private var hovered = false
    var body: some View {
        label.padding(.horizontal, theme.space(.sp2))
            .frame(height: theme.component(.controlHeight))
            .contentShape(Rectangle())
            .background(hovered || pressed ? theme.color(.hover) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: theme.shape(.chipRadius)))
            .onHover { hovered = $0 }
            .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : theme.motion.animation,
                       value: hovered || pressed)
    }
}

import Models
import SwiftUI
import Theme

struct AgentContextPickerView: View {
    @Bindable var model: AgentContextPickerModel
    let controls: AgentContextControls
    let theme: Theme
    let maxHeight: CGFloat
    let close: () -> Void
    private var inset: CGFloat { theme.component(.browsePadding) + theme.component(.browseGap) }
    private var small: Font { theme.font(.body, size: theme.tokens.textStyle(.micro).size) }
    private var rowHeight: CGFloat { theme.component(.browseRowHeight) }

    var body: some View {
        VStack(spacing: 0) {
            if model.choosingDay {
                controls.datePicker(model.choose, { model.choosingDay = false })
            } else {
                HStack(spacing: theme.component(.agentChipInset)) {
                    Image(systemName: "magnifyingglass").foregroundStyle(theme.color(.text3))
                    CommandTextField(text: $model.query, theme: theme, placeholder: "노트, 스페이스, 날짜 찾기",
                                     font: theme.nsFont(.body, size: theme.component(.iconSmall)),
                                     submit: close, cancel: close, move: model.move)
                }.padding(.horizontal, inset).frame(height: theme.component(.browseFindHeight))
                rule.padding(.horizontal, inset).padding(.bottom, theme.space(.sp1))
                if let id = model.space {
                    Button(action: model.back) {
                        HStack(spacing: theme.component(.chromePaddingEnd)) {
                            Image(systemName: "chevron.left")
                            Text(model.catalog.name(.space(id)))
                            Spacer()
                        }.padding(.horizontal, theme.component(.browseGap)).frame(height: rowHeight)
                    }.buttonStyle(SettingsButton(theme: theme, selected: false)).padding(.horizontal, theme.component(.browsePadding))
                        .font(small).foregroundStyle(theme.color(.text2))
                }
                rows
                rule.padding(.top, theme.space(.sp1))
                HStack {
                    Text("\(model.draft.conversation.context.count)개 고름")
                    Spacer()
                    Text("↵ 또는 바깥을 눌러 닫기")
                }.font(small).foregroundStyle(theme.color(.text3))
                    .padding(.horizontal, inset).frame(height: theme.component(.rowHeight))
            }
        }.frame(width: theme.component(.browseWidth))
            .fixedSize(horizontal: false, vertical: true)
            .font(theme.font(.body, size: theme.tokens.textStyle(.ui).size)).foregroundStyle(theme.color(.text))
    }

    private var rule: some View { Rectangle().fill(theme.color(.line)).frame(height: theme.shape(.borderWidth)) }

    private var rows: some View {
        let values = model.rows
        let headerHeight = theme.component(.browseHeaderHeight)
        let height = values.reduce(CGFloat.zero) { sum, row in
            if case .header = row { return sum + headerHeight }
            return sum + rowHeight
        }
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(values, id: \.self) { row in
                        switch row {
                        case .header(let title):
                            Text(title).font(theme.font(.librarySection)).foregroundStyle(theme.color(.text3))
                                .padding(.horizontal, inset).frame(height: headerHeight)
                        default: entry(row).id(row)
                        }
                    }
                }
            }.frame(height: min(maxHeight, height)).onChange(of: model.selection) {
                if let selected = model.selection { proxy.scrollTo(selected) }
            }
        }
    }

    private func entry(_ row: AgentContextPickerModel.Row) -> some View {
        let item: AgentContextItem? = if case .item(let value) = row { value } else { nil }
        let name = item.map(model.catalog.name) ?? "날짜 고르기…"
        let checked = item.map(model.draft.conversation.context.contains) ?? false
        return Button { model.toggle(row) } label: {
            HStack(spacing: theme.space(.sp2)) {
                AgentContextIcon(item: item ?? .period(.today), size: theme.component(.iconSmall),
                                 catalog: model.catalog, controls: controls, theme: theme)
                Text(name).lineLimit(1)
                Spacer(minLength: 0)
                if !model.query.isEmpty, case .note(let id) = item,
                   let spaceID = model.catalog.notes[id]?.spaceID, let space = model.catalog.spaces[spaceID] {
                    Text(space.name).font(small).foregroundStyle(theme.color(.text3)).lineLimit(1)
                }
                HStack(spacing: 0) {
                    if case .space = item { Color.clear.frame(width: theme.component(.iconSmall)) }
                    Image(systemName: "checkmark").font(small).opacity(checked ? 1 : 0)
                        .frame(width: theme.component(.iconMedium))
                }
            }.padding(.horizontal, theme.component(.browseGap)).frame(height: rowHeight).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(name).accessibilityValue(checked ? "선택됨" : "")
            .overlay(alignment: .trailing) {
                if case .space(let id) = item {
                    Button { model.enter(id) } label: {
                        Image(systemName: "chevron.right").font(small)
                            .frame(width: theme.component(.iconSmall), height: rowHeight).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("\(name) 노트 보기")
                        .padding(.trailing, theme.component(.browseGap) + theme.component(.iconMedium))
                }
            }
            .background(model.selection == row ? theme.color(.surface3) : .clear,
                        in: RoundedRectangle(cornerRadius: theme.component(.browseRowRadius)))
            .onHover { if $0 { model.selection = row } }
            .padding(.horizontal, theme.component(.browsePadding))
    }
}

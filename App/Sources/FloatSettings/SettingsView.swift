import Models
import Scheduling
import SwiftUI
import Theme

struct SettingsView: View {
    let model: SettingsModel
    let theme: Theme
    let reset: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ZStack(alignment: .topTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: theme.space(.sp4)) {
                        header
                        contents
                        if let error = model.error { Text(error).foregroundStyle(theme.color(.warn)) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, theme.component(.settingsBodyInset))
                    .padding(.top, theme.component(.settingsTop))
                    .padding(.bottom, theme.space(.sp5))
                }.id(model.pane)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: theme.component(.settingsCloseIcon)))
                        .frame(width: theme.component(.connectHeight), height: theme.component(.connectHeight))
                }.buttonStyle(SettingsButton(theme: theme, selected: false))
                    .padding(theme.space(.sp3)).accessibilityLabel("설정 닫기")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .font(theme.font(.body, size: theme.tokens.textStyle(.ui).size))
        .foregroundStyle(theme.color(.text)).background(theme.color(.surface))
        .tint(theme.color(.accent))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            link(.general, "gearshape")
            link(.appearance, "circle.lefthalf.filled")
            link(.editor, "pencil")
            separator
            link(.schedule, "calendar")
            link(.shortcuts, "keyboard")
            separator
            Text("연결").font(theme.font(.librarySection)).foregroundStyle(theme.color(.text3))
                .padding(.horizontal, theme.space(.sp2)).padding(.vertical, theme.space(.sp1))
            link(.assistant, "sparkles")
            Spacer()
            separator
            link(.about, "info.circle")
        }.padding(.horizontal, theme.space(.sp2)).padding(.top, theme.space(.sp4)).padding(.bottom, theme.space(.sp2))
            .frame(width: theme.component(.settingsSidebarWidth)).background(theme.color(.surface2))
            .overlay(alignment: .trailing) { Rectangle().fill(theme.color(.line)).frame(width: theme.shape(.borderWidth)) }
    }

    private func link(_ pane: SettingsPane, _ symbol: String) -> some View {
        let selected = model.pane == pane || (pane == .assistant && model.pane == .accounts)
        return Button { model.pane = pane } label: {
            HStack(spacing: theme.space(.sp2)) {
                Image(systemName: symbol).font(.system(size: theme.component(.iconMedium)))
                    .frame(width: theme.component(.iconMedium))
                Text(pane.rawValue)
            }.padding(.horizontal, theme.space(.sp2)).frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: theme.component(.segmentHeight))
        }.buttonStyle(SettingsButton(theme: theme, selected: selected, selection: .settingsSelection))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var separator: some View {
        rule.padding(.horizontal, theme.space(.sp2)).padding(.vertical, theme.component(.chromeGap))
    }
    var rule: some View { Rectangle().fill(theme.color(.line)).frame(height: theme.shape(.borderWidth)) }
    var valueFont: Font { theme.font(.body, size: theme.tokens.textStyle(.micro).size) }
    private var header: some View {
        VStack(alignment: .leading, spacing: theme.component(.iconGap)) {
            if model.pane == .accounts {
                textButton("‹ AI 비서") { model.pane = .assistant }.accessibilityLabel("AI 비서로 돌아가기")
            }
            Text(model.pane.rawValue).font(theme.font(.scheduleTitle)).accessibilityAddTraits(.isHeader)
            Text(model.pane.summary).font(valueFont).foregroundStyle(theme.color(.text3))
        }
    }

    @ViewBuilder private var contents: some View {
        switch model.pane {
        case .general:
            card("앱") { toggle("메뉴 막대 아이콘", "메뉴 막대에서 Float 열기", \.showsMenuBarIcon) }
        case .appearance: appearance
        case .editor: editor
        case .schedule: schedule
        case .shortcuts:
            ForEach(model.shortcuts) { section in
                card(section.title) {
                    ForEach(section.rows, id: \.action) { item in
                        row(item.action) { Text(item.keys).font(theme.font(.ui)) }
                    }
                }
            }
        case .assistant: assistant
        case .accounts: accounts
        case .about:
            card("Float") {
                if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                    row("버전") { Text(version).font(valueFont) }
                }
                row("설정 초기화", "노트와 일정을 보존하고 설정을 되돌려요") { textButton("기본값으로", action: reset) }
            }
        }
    }

    func card<Content: View>(_ title: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: theme.component(.settingsPopupGap)) {
            if let title {
                Text(title).font(theme.font(.librarySection)).foregroundStyle(theme.color(.text3))
                    .padding(.leading, theme.space(.sp1)).accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) {
                Group(subviews: content()) { views in
                    ForEach(views) { view in
                        view.overlay(alignment: .top) { if view.id != views.first?.id { rule } }
                    }
                }
            }.padding(.horizontal, theme.space(.sp3))
                .background(theme.color(.surface2), in: RoundedRectangle(cornerRadius: theme.shape(.windowRadius)))
        }
    }

    func row<Control: View>(_ title: String, _ detail: String? = nil, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: theme.space(.sp3)) {
            VStack(alignment: .leading, spacing: theme.shape(.borderWidth)) {
                Text(verbatim: title)
                if let detail {
                    Text(verbatim: detail).font(theme.font(.body, size: theme.tokens.textStyle(.librarySection).size))
                        .foregroundStyle(theme.color(.text3)).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            control()
        }.padding(.vertical, theme.component(.chromeGap)).frame(minHeight: theme.component(.settingsRow))
    }

    func textButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(valueFont).padding(.horizontal, theme.space(.sp1))
                .frame(minHeight: theme.component(.controlHeight)) }
            .buttonStyle(SettingsButton(theme: theme, selected: false))
    }

    func popup<Value: Equatable>(_ title: String, _ detail: String, value: Value, choices: [(Value, String)],
                                 select: @escaping (Value) -> Void) -> some View {
        row(title, detail) {
            ValuePopup(label: title, value: choices.first { $0.0 == value }?.1 ?? "기본값", theme: theme, inSettings: true) {
                let menu = NSMenu()
                menu.autoenablesItems = false
                for (index, choice) in choices.enumerated() {
                    let item = menu.addItem(withTitle: choice.1, action: nil, keyEquivalent: "")
                    item.tag = index
                    item.state = choice.0 == value ? .on : .off
                }
                return menu
            } choose: { select(choices[$0.tag].0) }
        }
    }

    func setting(_ title: String, _ detail: String, _ key: WritableKeyPath<SettingsValues, String>,
                 _ choices: [(String, String)]) -> some View {
        popup(title, detail, value: model.values[keyPath: key], choices: choices) { value in
            model.change { $0[keyPath: key] = value }
        }
    }

    func toggle(_ title: String, _ detail: String, _ key: WritableKeyPath<SettingsValues, Bool>) -> some View {
        row(title, detail) {
            Toggle(title, isOn: Binding(get: { model.values[keyPath: key] },
                                        set: { value in model.change { $0[keyPath: key] = value } }))
                .labelsHidden().toggleStyle(SettingsSwitch(theme: theme)).accessibilityLabel(title)
        }
    }
}

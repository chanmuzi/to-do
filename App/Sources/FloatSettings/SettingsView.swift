import Models
import SwiftUI
import Theme

struct SettingsView: View {
    let model: SettingsModel
    let theme: Theme

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                sidebar
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if model.pane == .general {
                        general
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: theme.space(.sp4)) {
                                contents
                                if let error = model.error { Text(error).foregroundStyle(theme.color(.warn)) }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, theme.space(.sp5))
                        }.id(model.pane)
                    }
                }.padding(.horizontal, theme.component(.settingsBodyInset))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }.disabled(model.confirmingReset).accessibilityHidden(model.confirmingReset)
            if model.confirmingReset { resetDialog }
        }
        .font(theme.font(.body, size: theme.tokens.textStyle(.ui).size))
        .foregroundStyle(theme.color(.text)).background(theme.color(.surface)).tint(theme.color(.accent))
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
            if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                Text("Float " + version).font(theme.font(.librarySection)).foregroundStyle(theme.color(.text4))
                    .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, theme.component(.chromeGap))
            }
        }.padding(.horizontal, theme.component(.settingsSegmentPad))
            .padding(.top, theme.component(.settingsTop)).padding(.bottom, theme.space(.sp3))
            .frame(width: theme.component(.settingsSidebarWidth)).background(theme.color(.surface2))
            .overlay(alignment: .trailing) { Rectangle().fill(theme.color(.line)).frame(width: theme.shape(.borderWidth)) }
    }

    private func link(_ pane: SettingsPane, _ symbol: String) -> some View {
        let selected = model.pane == pane || (pane == .assistant && model.pane == .accounts)
        return Button { model.pane = pane } label: {
            HStack(spacing: theme.space(.sp2)) {
                Image(systemName: symbol).frame(width: theme.component(.iconLarge))
                Text(pane.rawValue)
                Spacer()
                if pane == .assistant && model.agents?.engines.contains(where: { $0.status == .expired }) == true {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.color(.warn))
                        .accessibilityLabel("다시 로그인 필요")
                }
            }.padding(.horizontal, theme.space(.sp2)).frame(height: theme.component(.settingsSegmentH))
        }.buttonStyle(SettingsButton(theme: theme, selected: selected, selection: .settingsSelection))
            .frame(height: theme.component(.settingsSidebarRow)).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var separator: some View {
        rule.padding(.horizontal, theme.space(.sp2)).padding(.vertical, theme.component(.settingsChipPad))
    }
    var rule: some View { Rectangle().fill(theme.color(.line)).frame(height: theme.shape(.borderWidth)) }
    var valueFont: Font { theme.font(.body, size: theme.tokens.textStyle(.micro).size) }
    private var header: some View {
        HStack(spacing: theme.component(.chromeGap)) {
            if model.pane == .accounts, let engine = model.detailEngine {
                Button { model.pane = .assistant } label: {
                    Image(systemName: "chevron.left").frame(width: theme.component(.settingsChipH), height: theme.component(.settingsChipH))
                }.buttonStyle(.plain).accessibilityLabel("에이전트 목록으로")
                logo(engine, small: true)
                Text(engine.name)
            } else { Text(model.pane.rawValue) }
        }.font(theme.font(.paneTitle, size: theme.component(.libraryHeaderFont)))
            .frame(height: theme.component(.settingsTop)).accessibilityAddTraits(.isHeader)
    }

    private var general: some View {
        VStack(spacing: theme.space(.sp4)) {
            card { toggle("메뉴 막대 아이콘", \.showsMenuBarIcon) }
            Spacer()
            if let error = model.error { Text(error).foregroundStyle(theme.color(.warn)) }
            card { row("모든 설정을 처음 상태로") { actionButton("되돌리기", ink: .warn) { model.confirmingReset = true } } }
        }.padding(.bottom, theme.space(.sp5))
    }

    private var resetDialog: some View {
        ZStack {
            theme.color(.outline).ignoresSafeArea()
            VStack(spacing: theme.space(.sp3)) {
                Text("모든 설정을 되돌릴까요?").font(theme.font(.paneTitle))
                Text("노트와 에이전트 연결은 그대로 남아요").font(valueFont)
                HStack {
                    actionButton("취소") { model.confirmingReset = false }.keyboardShortcut(.cancelAction)
                    actionButton("되돌리기", fill: .warn) {
                        model.confirmingReset = false
                        model.restoreDefaults(theme: theme)
                    }
                }
            }.padding(theme.space(.sp4)).frame(width: theme.component(.settingsAlertW))
                .background(theme.color(.surface2), in: RoundedRectangle(cornerRadius: theme.shape(.windowRadius)))
                .shadow(color: theme.color(.outline), radius: theme.space(.sp3))
        }.accessibilityElement(children: .contain).accessibilityAddTraits(.isModal)
    }

    @ViewBuilder private var contents: some View {
        switch model.pane {
        case .appearance, .editor:
            SettingsPreview(theme: theme, values: model.values)
            if model.pane == .appearance { appearance } else { editor }
        case .schedule: schedule
        case .shortcuts:
            ForEach(model.shortcuts) { section in
                card(section.title) {
                    ForEach(section.rows, id: \.action) { item in
                        row(item.action) {
                            HStack(spacing: theme.space(.sp1)) {
                                ForEach(item.keys, id: \.self) { key in
                                    Text(key).font(theme.font(.ui)).padding(.horizontal, theme.component(.settingsChipPad))
                                        .frame(height: theme.component(.settingsChipH)).modifier(WhiteControl(theme: theme))
                                }
                            }
                        }
                    }
                }
            }
        case .assistant: assistant
        case .accounts: if let engine = model.detailEngine { accountDetail(engine) }
        case .general: EmptyView()
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

    func row<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: theme.space(.sp2)) {
            Text(verbatim: title)
            Spacer(minLength: 0)
            control()
        }.frame(minHeight: theme.component(.settingsRow))
    }

    func actionButton(_ title: String, ink: ColorToken = .text, fill: ColorToken = .surface, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(valueFont).padding(.horizontal, theme.component(.settingsSegmentPad))
                .frame(height: theme.component(.settingsChipH)).foregroundStyle(theme.color(fill == .surface ? ink : .surface))
                .modifier(WhiteControl(theme: theme, fill: fill))
        }.buttonStyle(.plain)
    }

    func segment<Value: Equatable>(_ title: String, value: Value, choices: [(Value, String)], select: @escaping (Value) -> Void) -> some View {
        row(title) {
            HStack(spacing: 0) {
                ForEach(choices.indices, id: \.self) { index in
                    let choice = choices[index]
                    Button { select(choice.0) } label: {
                        Group {
                            if title == "체크박스", index == 0 { Image(systemName: "square") }
                            else { Text(choice.1) }
                        }.font(valueFont).padding(.horizontal, theme.component(.settingsSegmentPad))
                            .frame(maxHeight: .infinity)
                            .background(choice.0 == value ? theme.color(.surface) : .clear,
                                        in: RoundedRectangle(cornerRadius: theme.shape(.controlRadius)))
                    }.buttonStyle(.plain).accessibilityLabel(choice.1)
                        .accessibilityAddTraits(choice.0 == value ? .isSelected : [])
                }
            }.padding(theme.component(.iconButtonGap)).frame(height: theme.component(.settingsSegmentH))
                .background(theme.color(.settingsSelection), in: RoundedRectangle(cornerRadius: theme.component(.settingsSegmentRadius)))
                .accessibilityElement(children: .contain).accessibilityLabel(title)
        }
    }

    func setting(_ title: String, _ key: WritableKeyPath<SettingsValues, String>, _ choices: [(String, String)]) -> some View {
        segment(title, value: model.values[keyPath: key], choices: choices) { value in model.change { $0[keyPath: key] = value } }
    }

    func toggle(_ title: String, _ key: WritableKeyPath<SettingsValues, Bool>) -> some View {
        row(title) {
            Toggle(title, isOn: Binding(get: { model.values[keyPath: key] },
                                        set: { value in model.change { $0[keyPath: key] = value } }))
                .labelsHidden().toggleStyle(SettingsSwitch(theme: theme)).accessibilityLabel(title)
        }
    }
}

struct WhiteControl: ViewModifier {
    let theme: Theme
    var fill: ColorToken = .surface
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.shape(.controlRadius))
        content.background(theme.color(fill), in: shape)
            .overlay { shape.strokeBorder(theme.color(.line), lineWidth: theme.shape(.borderWidth)) }
    }
}

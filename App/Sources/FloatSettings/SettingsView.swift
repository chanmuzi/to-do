import Models
import Scheduling
import SwiftUI
import Theme

struct SettingsView: View {
    let model: SettingsModel
    let theme: Theme

    let reset: () -> Void

    var body: some View {
        Group {
            if model.pane == .shortcuts { shortcuts }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        section("모양") {
                            segments("화면", \.appearance, [("light", "라이트"), ("dark", "다크"), ("system", "시스템")])
                            row("본문 글자") {
                                stepper
                                group {
                                    let normal = Int(theme.tokens.textStyle(.body).lineHeight)
                                    ForEach([("좁게", Int(theme.component(.settingsLineMin))), ("보통", Int(theme.defaultBodyLineHeight)), ("넓게", Int(theme.component(.settingsLineMax)))], id: \.0) { name, height in
                                        choice(name, selected: normal == height) { model.change { $0.bodyLineHeight = height } }
                                    }
                                }
                            }
                            segments("스페이스", \.spaceDisplay, [("icon", "아이콘"), ("iconAndName", "아이콘과 이름"), ("name", "이름")])
                        }
                        sectionRule
                        section("편집기") {
                            segments("코드 글자색", \.inlineCode, [("accent", "강조"), ("plain", "흑백")])
                            segments("체크박스", \.checkbox, [("box", "상자"), ("bracket", "[ ] 대괄호")])
                            row("입력 중 글자") {
                                group {
                                    choice("표시 없음", selected: model.values.markedTextStyle == .none) { model.change { $0.markedTextStyle = .none } }
                                    choice("옅은 밑줄", selected: model.values.markedTextStyle == .underline) { model.change { $0.markedTextStyle = .underline } }
                                }
                            }
                            segments("서식 표시줄", \.formatBar, [("always", "항상"), ("editing", "편집할 때"), ("hidden", "숨김")])
                            toggle("날짜 알아보기", \.recognizesDates)
                        }
                        sectionRule
                        section("예정") {
                            segments("날짜 표시", \.scheduleDateFormat, [("relative", "내일 오후 3:00"), ("absolute", "11월 19일 오후 3:00")])
                            segments("시간 형식", \.clockFormat, [("twelveHour", "3:00 PM"), ("koreanMeridiem", "오후 3:00"), ("twentyFourHour", "15:00")])
                            calendars
                        }
                        sectionRule
                        section("앱") {
                            toggle("메뉴 막대 아이콘", \.showsMenuBarIcon)
                            row("단축키") { group { choice("단축키 표 보기") { model.pane = .shortcuts } } }
                        }
                        if let error = model.error { Text(error).foregroundStyle(theme.color(.warn)) }
                        rule.padding(.top, theme.component(.settingsRuleBefore))
                        Button(action: reset) { Text("기본값으로").underline() }.buttonStyle(.plain)
                            .foregroundStyle(theme.color(.text2)).padding(.top, theme.space(.sp3))
                    }.padding(.horizontal, theme.space(.sp6)).padding(.bottom, theme.space(.sp5))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .font(theme.font(.body, size: theme.tokens.textStyle(.ui).size)).foregroundStyle(theme.color(.text))
        .background(theme.color(.surface)).tint(theme.color(.accent)).focusEffectDisabled()
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: theme.space(.sp1)) {
            Text(title).font(theme.font(.title)).frame(height: theme.component(.settingsRow))
            content()
        }
    }

    private var sectionRule: some View {
        rule.padding(.top, theme.component(.settingsRuleBefore)).padding(.bottom, theme.component(.chromePaddingEnd))
    }

    private var rule: some View {
        Rectangle().fill(theme.color(.line)).frame(height: theme.shape(.borderWidth))
    }

    private func row<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 0) {
            Text(title).foregroundStyle(theme.color(.text2))
                .frame(width: theme.component(.settingsLabelWidth), alignment: .leading)
            control()
        }.frame(minHeight: theme.component(.settingsRow))
    }

    private func choice(_ title: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: theme.component(.chromeGap)) {
                if title == "강조" || title == "흑백" {
                    Text("code").font(theme.font(.code)).foregroundStyle(theme.color(title == "강조" ? .codeAccent : .text))
                }
                Text(title)
            }.padding(.horizontal, theme.space(.sp3)).frame(height: theme.component(.segmentItem))
        }.buttonStyle(SettingsButton(theme: theme, selected: selected))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func segments(_ title: String, _ key: WritableKeyPath<SettingsValues, String>,
                          _ items: [(String, String)]) -> some View {
        row(title) {
            group {
                ForEach(items, id: \.0) { value, label in
                    choice(label, selected: model.values[keyPath: key] == value) {
                        model.change { $0[keyPath: key] = value }
                    }.accessibilityLabel(title + ", " + label)
                }
            }
        }
    }

    private func group<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: theme.component(.iconButtonGap)) { content() }
            .padding(.horizontal, theme.component(.iconButtonGap)).frame(height: theme.component(.segmentHeight))
            .overlay { RoundedRectangle(cornerRadius: theme.shape(.controlRadius)).strokeBorder(theme.color(.line), lineWidth: theme.shape(.borderWidth)).allowsHitTesting(false) }
    }

    private var stepper: some View {
        let value = Int(theme.noteBodySize)
        let lower = Int(theme.component(.settingsFontMin)), upper = Int(theme.component(.settingsFontMax))
        return group {
            choice("−") { model.change { $0.bodySize = max(lower, value - 1) } }
                .disabled(value <= lower).accessibilityLabel("본문 글자 줄이기")
            Text(String(value)).monospacedDigit()
            choice("+") { model.change { $0.bodySize = min(upper, value + 1) } }
                .disabled(value >= upper).accessibilityLabel("본문 글자 늘리기")
        }.padding(.trailing, theme.space(.sp2))
    }

    private func toggle(_ title: String, _ key: WritableKeyPath<SettingsValues, Bool>) -> some View {
        row(title) {
            Toggle(title, isOn: Binding(get: { model.values[keyPath: key] },
                                        set: { value in model.change { $0[keyPath: key] = value } }))
                .labelsHidden().toggleStyle(SettingsSwitch(theme: theme)).accessibilityLabel(title)
        }
    }

    @ViewBuilder private var calendars: some View {
        ForEach([ScheduleItem.Kind.event, .reminder], id: \.self) { kind in
            if let menu = model.menus[kind], menu.access == .available {
                let title = kind == .event ? "기본 캘린더" : "미리 알림"
                row(title) {
                    DestinationPicker(title: title, menu: menu, selectedID: model.values[idFor: kind], theme: theme) {
                        model.choose($0, for: kind)
                    }.frame(height: theme.component(.controlHeight))
                }
            }
        }
        let kinds = [ScheduleItem.Kind.event, .reminder]
        if kinds.contains(where: { model.menus[$0]?.access == .needsRequest }) {
            row("캘린더") {
                connectButton("연결") { Task { await model.connectRequestedCalendars() } }
                    .disabled(model.connecting)
            }
        } else if let kind = kinds.first(where: { model.menus[$0]?.access == .blocked }) {
            row("캘린더") { connectButton("시스템 설정 열기") { model.openPrivacy(kind) } }
        }
    }

    private func connectButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).padding(.horizontal, theme.component(.connectPadding)).frame(height: theme.component(.connectHeight))
                .background(theme.color(.connectFill), in: RoundedRectangle(cornerRadius: theme.shape(.controlRadius)))
        }.buttonStyle(.plain)
    }

    private var shortcuts: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.space(.sp5)) {
                ForEach(model.shortcuts) { section in
                    VStack(alignment: .leading, spacing: theme.space(.sp1)) {
                        Text(section.title).font(theme.font(.sectionLabel))
                        rule
                        ForEach(section.rows, id: \.action) { row in
                            HStack {
                                Text(row.action)
                                Spacer()
                                Text(row.keys).font(theme.font(.ui))
                            }.frame(minHeight: theme.component(.settingsRow)).accessibilityElement(children: .combine)
                        }
                    }
                }
            }.padding(theme.space(.sp5))
        }
    }
}

private struct SettingsSwitch: ToggleStyle {
    let theme: Theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    func makeBody(configuration: Configuration) -> some View {
        let inset = theme.component(.iconButtonGap)
        let height = theme.component(.settingsSwitchHeight)
        Button { configuration.isOn.toggle() } label: {
            Capsule().fill(theme.color(configuration.isOn ? .text : .surface3))
                .frame(width: theme.component(.settingsSwitchWidth), height: height)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(theme.color(configuration.isOn ? .onAccent : .text2))
                        .frame(width: height - inset * 2, height: height - inset * 2)
                        .padding(inset)
                }.frame(height: theme.component(.controlHeight))
                .animation(reduced ? nil : theme.motion.animation, value: configuration.isOn)
        }.buttonStyle(.plain)
            .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch) }
    }
}

private struct SettingsButton: ButtonStyle {
    let theme: Theme
    let selected: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.font(.body, size: theme.tokens.textStyle(.ui).size, weight: theme.tokens.textStyle(selected ? .selected : .body).weight))
            .foregroundStyle(theme.color(enabled ? (selected || hovered ? .text : .text2) : .text3))
            .background(selected ? theme.color(.selected) : ((hovered || configuration.isPressed) && enabled ? theme.color(.hover) : .clear),
                        in: RoundedRectangle(cornerRadius: theme.shape(.controlRadius)))
            .contentShape(Rectangle()).onHover { hovered = $0 }
            .animation(reduced ? nil : theme.motion.animation, value: hovered || selected || configuration.isPressed)
    }
}

import Models
import Scheduling
import SwiftUI
import Theme

struct SettingsView: View {
    let model: SettingsModel
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: theme.space(.sp1)) {
                ForEach(SettingsPane.allCases, id: \.self) { pane in
                    choice(pane.rawValue, selected: model.pane == pane) { model.pane = pane }
                }
                Spacer()
            }.padding(theme.space(.sp3))
            rule
            if model.pane == .shortcuts {
                shortcuts
            } else {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: theme.space(.sp3)) {
                        Text(model.pane.rawValue).font(theme.font(.sectionLabel))
                        controls
                        if let error = model.error { Text(error).font(theme.font(.rowSub)).textSelection(.enabled) }
                        Spacer(minLength: 0)
                    }.padding(theme.space(.sp5)).frame(maxWidth: .infinity, alignment: .leading)
                    if model.pane == .appearance || model.pane == .editor {
                        SettingsPreview(theme: theme, values: model.values)
                    }
                }
            }
        }
        .frame(width: theme.component(.settingsWidth),
               height: theme.component(model.pane.heightToken))
        .font(theme.font(.row)).foregroundStyle(theme.color(.text))
        .background(theme.color(.surface)).tint(theme.color(.accent)).focusEffectDisabled()
    }

    @ViewBuilder private var controls: some View {
        switch model.pane {
        case .appearance:
            segments("모드", \.appearance, [("light", "라이트"), ("dark", "다크"), ("system", "시스템")])
            step("본문 글꼴 크기", \.bodySize, Int(theme.tokens.textStyle(.body).size), .settingsFontMin, .settingsFontMax)
            step("본문 줄 높이", \.bodyLineHeight, Int(theme.lineHeight(.body)), .settingsLineMin, .settingsLineMax)
            segments("스페이스 표시", \.spaceDisplay, [("icon", "아이콘"), ("iconAndName", "아이콘과 이름"), ("name", "이름")])
        case .editor:
            segments("인라인 코드 글자색", \.inlineCode, [("accent", "강조"), ("plain", "흑백")])
            segments("체크박스 모양", \.checkbox, [("box", "상자"), ("bracket", "대괄호")])
            toggle("본문과 제목에서 날짜 알아보기", \.recognizesDates)
        case .schedule:
            segments("날짜와 시간 표시", \.scheduleDateFormat, [("relative", "상대"), ("absolute", "절대")])
            segments("리마인더 표시", \.reminderDisplay, [("time", "시간"), ("relative", "남은 시간"), ("iconOnly", "아이콘")])
            segments("시간 형식", \.clockFormat, [("twelveHour", "3:00 PM"), ("koreanMeridiem", "오후 3:00"), ("twentyFourHour", "15:00")])
            calendars
        case .app:
            toggle("메뉴 막대 아이콘 표시", \.showsMenuBarIcon)
        case .shortcuts: EmptyView()
        }
    }

    private var rule: some View {
        Rectangle().fill(theme.color(.line)).frame(height: theme.shape(.borderWidth))
    }

    private func row<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: theme.space(.sp2)) {
            Text(title).foregroundStyle(theme.color(.text2))
                .frame(width: theme.component(.settingsLabelWidth), alignment: .leading)
            control()
        }.frame(minHeight: theme.component(.controlHeight))
    }

    private func choice(_ title: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).padding(.horizontal, theme.space(.sp2)).frame(height: theme.component(.controlHeight))
        }.buttonStyle(SettingsButton(theme: theme, selected: selected))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func segments(_ title: String, _ key: WritableKeyPath<SettingsValues, String>,
                          _ items: [(String, String)]) -> some View {
        row(title) {
            HStack(spacing: 0) {
                ForEach(items, id: \.0) { value, label in
                    choice(label, selected: model.values[keyPath: key] == value) {
                        model.change { $0[keyPath: key] = value }
                    }.accessibilityLabel(title + ", " + label)
                }
            }
        }
    }

    private func step(_ title: String, _ key: WritableKeyPath<SettingsValues, Int?>, _ value: Int,
                      _ minToken: ComponentToken, _ maxToken: ComponentToken) -> some View {
        let lower = Int(theme.component(minToken)), upper = Int(theme.component(maxToken))
        return row(title) {
            HStack(spacing: theme.space(.sp1)) {
                choice("−") { model.change { $0[keyPath: key] = max(lower, min(value - 1, upper)) } }
                    .disabled(value <= lower).accessibilityLabel(title + " 줄이기")
                Text("\(value) pt").font(theme.font(.ui)).monospacedDigit()
                choice("+") { model.change { $0[keyPath: key] = min(upper, max(value + 1, lower)) } }
                    .disabled(value >= upper).accessibilityLabel(title + " 늘리기")
            }
        }
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
                let title = kind == .event ? "기본 캘린더" : "기본 미리 알림 목록"
                row(title) {
                    DestinationPicker(title: title, menu: menu, selectedID: model.values[idFor: kind], theme: theme) {
                        model.choose($0, for: kind)
                    }.frame(height: theme.component(.controlHeight))
                }
                if model.returnedToDefault.contains(kind) {
                    Text((kind == .event ? "기본 캘린더를" : "기본 미리 알림 목록을") + " 시스템 기본값으로 변경했습니다").font(theme.font(.rowSub)).foregroundStyle(theme.color(.text2))
                }
            }
        }
        let unavailable = [ScheduleItem.Kind.event, .reminder].filter { model.menus[$0]?.access != .available }
        if let kind = unavailable.first(where: { model.menus[$0]?.access == .needsRequest }) {
            choice(kind == .event ? "캘린더 연결" : "미리 알림 연결") {
                Task { await model.connect(kind) }
            }.disabled(model.connecting)
        }
        ForEach(unavailable.filter { model.menus[$0]?.access == .blocked }, id: \.self) { kind in
            choice(kind == .event ? "캘린더 개인정보 보호 설정 열기" : "미리 알림 개인정보 보호 설정 열기") {
                model.openPrivacy(kind)
            }
        }
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
                            }.frame(minHeight: theme.component(.controlHeight)).accessibilityElement(children: .combine)
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
        let inset = theme.shape(.borderWidth)
        let height = theme.component(.settingsSwitchHeight)
        Button { configuration.isOn.toggle() } label: {
            Capsule().fill(theme.color(configuration.isOn ? .accent : .surface3))
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
            .font(theme.font(.row, weight: theme.tokens.textStyle(selected ? .selected : .row).weight))
            .foregroundStyle(theme.color(enabled ? (selected || hovered ? .text : .text2) : .text3))
            .background(selected ? theme.color(.selected) : ((hovered || configuration.isPressed) && enabled ? theme.color(.hover) : .clear),
                        in: RoundedRectangle(cornerRadius: theme.shape(.controlRadius)))
            .contentShape(Rectangle()).onHover { hovered = $0 }
            .animation(reduced ? nil : theme.motion.animation, value: hovered || selected || configuration.isPressed)
    }
}

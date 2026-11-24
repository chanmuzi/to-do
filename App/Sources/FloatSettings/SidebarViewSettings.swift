import Models
import SwiftUI
import Theme

extension SettingsView {
    func infoTooltip(_ tip: String) -> some View {
        let tooltipInk = theme.tokens.color(.surface, .light).color
        let tooltipFill = theme.tokens.color(.text, .light).color
        let tipOffset = theme.component(.iconLarge) + theme.space(.sp1)
        return VStack(spacing: 0) {
            Text(tip).font(valueFont).foregroundStyle(tooltipInk).fixedSize()
                .padding(.horizontal, theme.space(.sp2)).padding(.vertical, theme.component(.settingsPopupGap))
                .background(tooltipFill, in: RoundedRectangle(cornerRadius: theme.shape(.controlRadius)))
                .settingsMeasure("info-tooltip-bubble")
                .visualEffect { bubble, geometry in
                    let leadingEdge = geometry.bounds(of: .scrollView)?.minX ?? 0
                    return bubble.offset(x: max(0, leadingEdge))
                }
            Rectangle().fill(tooltipFill).frame(width: theme.component(.settingsTipTail), height: theme.component(.settingsTipTail))
                .rotationEffect(.degrees(45)).padding(.top, -theme.component(.settingsTipTail) / 2)
        }.fixedSize().offset(y: -tipOffset).allowsHitTesting(false)
    }

    func infoIcon(_ tip: String, shown: Bool, setShown: @escaping (Bool) -> Void) -> some View {
        Image(systemName: "info.circle").resizable().scaledToFit()
            .frame(width: theme.component(.iconSmall), height: theme.component(.iconSmall))
            .foregroundStyle(theme.color(.text2))
            .onHover(perform: setShown).accessibilityLabel(tip)
            .overlay(alignment: .bottom) { if shown { infoTooltip(tip) } }
    }

    @ViewBuilder var sidebarViewSettings: some View {
        let prefs = model.preferences.value
        let section = ReorderSection(prefs.viewOrder, stride: theme.component(.settingsRow))
        VStack(alignment: .leading, spacing: theme.component(.settingsPopupGap)) {
            Text("사이드바에 보일 보기").font(valueFont).foregroundStyle(theme.color(.text3, on: .surface2))
                .padding(.leading, theme.space(.sp1)).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(section.rows, id: \.self) { view in
                    let title = view.sidebarViewTitle ?? ""
                    let enabled = prefs.visibleViews.contains(view)
                    let actions = ReorderActions(view, section: section, move: model.moveView)
                    HStack(spacing: theme.space(.sp2)) {
                        Grip(theme: theme)
                            .settingsMeasure("grip-" + title)
                            .modifier(SidebarPan(view, section: section, drag: model.reorder, move: model.moveView))
                            .focusable().accessibilityElement(children: .ignore)
                            .accessibilityLabel("순서 바꾸기").accessibilityValue(title).accessibilityHint(title)
                            .reorderAccess(actions)
                        Text(title).foregroundStyle(theme.color(enabled ? .text : .text3, on: .surface2))
                            .settingsMeasure("label-" + title)
                        Spacer()
                        Toggle(title, isOn: Binding(get: { model.preferences.value.visibleViews.contains(view) },
                            set: { value in model.changeSidebar { $0.setVisible(view, value) } }))
                            .labelsHidden().toggleStyle(SettingsSwitch(theme: theme)).accessibilityLabel(title)
                    }.frame(height: theme.component(.settingsRow))
                        .overlay(alignment: .top) { if view != section.rows.first && !model.reorder.lifted(view, in: section) { rule } }
                        .padding(.horizontal, theme.space(.sp3))
                        .settingsMeasure("row-" + title)
                        .reorderSurface(model.reorder.lifted(view, in: section), theme: theme, radius: theme.component(.settingsReorderRadius))
                        .contextMenu { actions.menu }
                        .reorderPosition(view, in: section, drag: model.reorder, theme: theme)
                }
            }.background(theme.color(.surface2), in: RoundedRectangle(cornerRadius: theme.shape(.windowRadius)))
        }
        card {
            HStack(spacing: theme.component(.chromeGap)) {
                let title = "마지막으로 본 곳에서 열기"
                let tip = "끄면 맨 위의 보기에서 열어요"
                Text(title).settingsMeasure("opening-label")
                infoIcon(tip, shown: model.showsOpeningTip) { model.showsOpeningTip = $0 }
                    .settingsMeasure("opening-info")
                Spacer()
                Toggle(title, isOn: Binding(get: { model.preferences.value.opensLastSelection },
                    set: { value in model.changeSidebar { $0.opensLastSelection = value } }))
                    .labelsHidden().toggleStyle(SettingsSwitch(theme: theme)).accessibilityLabel(title).accessibilityHint(tip)
            }.frame(height: theme.component(.settingsRow))
        }
    }
}

private struct Grip: View {
    let theme: Theme
    @State private var hovering = false
    var body: some View {
        Canvas { context, size in
            let scale = size.width / 16
            let radius = 1.1 * scale
            for x: CGFloat in [6, 10] {
                for y: CGFloat in [4, 8, 12] {
                    let circle = CGRect(x: x * scale - radius, y: y * scale - radius, width: 2 * radius, height: 2 * radius)
                    context.fill(Path(ellipseIn: circle), with: .foreground)
                }
            }
        }.frame(width: theme.component(.iconMedium), height: theme.component(.iconMedium))
            .foregroundStyle(theme.color(hovering ? .text2 : .text3, on: .surface2))
            .contentShape(Rectangle()).onHover { hovering = $0 }
            .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : theme.motion.animation, value: hovering)
    }
}

import SwiftUI

package struct SettingsSwitch: ToggleStyle {
    let theme: Theme
    let compact: Bool
    package init(theme: Theme, compact: Bool = false) { self.theme = theme; self.compact = compact }
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var hovered = false
    package func makeBody(configuration: Configuration) -> some View {
        let height = theme.component(compact ? .scheduleSwitchHeight : .settingsSwitchHeight)
        let inset = compact ? (height - theme.component(.menuIcon)) / 2 : theme.component(.iconButtonGap)
        Button { configuration.isOn.toggle() } label: {
            Capsule().fill(theme.color(configuration.isOn ? .text : .surface3))
                .frame(width: theme.component(compact ? .scheduleSwitchWidth : .settingsSwitchWidth), height: height)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(theme.color(configuration.isOn ? .onAccent : .text2))
                        .frame(width: height - inset * 2, height: height - inset * 2)
                        .padding(inset)
                }.overlay { Capsule().fill(hovered || theme.previewsSurfaceHover ? theme.color(.hover) : .clear).allowsHitTesting(false) }
                .frame(height: theme.component(.controlHeight)).contentShape(Rectangle())
                .onHover { hovered = $0 }
                .animation(reduced ? nil : theme.motion.animation, value: hovered)
                .animation(reduced ? nil : theme.motion.animation, value: configuration.isOn)
        }.buttonStyle(.plain)
            .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch) }
    }
}

package struct SettingsButton: ButtonStyle {
    let theme: Theme
    let selected: Bool
    let showsHover: Bool
    package init(theme: Theme, selected: Bool, showsHover: Bool = false) {
        self.theme = theme
        self.selected = selected
        self.showsHover = showsHover
    }
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var hovered = false
    package func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.font(.body, size: theme.tokens.textStyle(.ui).size, weight: theme.tokens.textStyle(selected ? .selected : .body).weight))
            .foregroundStyle(theme.color(enabled ? (selected || hovered || showsHover ? .text : .text2) : .text3))
            .background(selected ? theme.color(.selected) : ((hovered || showsHover || configuration.isPressed) && enabled ? theme.color(.hover) : .clear),
                        in: RoundedRectangle(cornerRadius: theme.shape(.controlRadius)))
            .contentShape(Rectangle()).onHover { hovered = $0 }
            .animation(reduced ? nil : theme.motion.animation, value: hovered || selected || configuration.isPressed)
    }
}

package struct SegmentGroup<Content: View>: View {
    let theme: Theme
    let content: () -> Content
    package init(theme: Theme, @ViewBuilder content: @escaping () -> Content) {
        self.theme = theme
        self.content = content
    }
    package var body: some View {
        HStack(spacing: theme.component(.iconButtonGap)) { content() }
            .padding(theme.component(.iconButtonGap)).frame(height: theme.component(.settingsSegmentH))
            .background(theme.color(.surface3), in: RoundedRectangle(cornerRadius: theme.component(.settingsSegmentRadius)))
    }
}

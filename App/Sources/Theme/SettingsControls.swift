import SwiftUI

package struct SettingsSwitch: ToggleStyle {
    let theme: Theme
    package init(theme: Theme) { self.theme = theme }
    @Environment(\.accessibilityReduceMotion) private var reduced
    package func makeBody(configuration: Configuration) -> some View {
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

package struct SettingsButton: ButtonStyle {
    let theme: Theme
    let selected: Bool
    let selection: ColorToken
    package init(theme: Theme, selected: Bool, selection: ColorToken = .selected) {
        self.theme = theme
        self.selected = selected
        self.selection = selection
    }
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var hovered = false
    package func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.font(.body, size: theme.tokens.textStyle(.ui).size, weight: theme.tokens.textStyle(selected ? .selected : .body).weight))
            .foregroundStyle(theme.color(enabled ? (selected || hovered ? .text : .text2) : .text3))
            .background(selected ? theme.color(selection) : ((hovered || configuration.isPressed) && enabled ? theme.color(.hover) : .clear),
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
            .padding(.horizontal, theme.component(.iconButtonGap)).frame(height: theme.component(.segmentHeight))
            .overlay { RoundedRectangle(cornerRadius: theme.shape(.controlRadius)).strokeBorder(theme.color(.line), lineWidth: theme.shape(.borderWidth)).allowsHitTesting(false) }
    }
}

import SwiftUI

package struct WhiteControl: ButtonStyle {
    let theme: Theme
    let ink: ColorToken
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var hovered = false

    package init(theme: Theme, ink: ColorToken = .text) {
        self.theme = theme
        self.ink = ink
    }

    package func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.shape(.controlRadius))
        configuration.label
            .font(theme.font(.body, size: theme.tokens.textStyle(.micro).size, weight: theme.tokens.textStyle(.selected).weight))
            .foregroundStyle(theme.color(enabled ? ink : .text3))
            .padding(.horizontal, theme.component(.settingsSegmentPad)).frame(height: theme.component(.settingsChipH))
            .background {
                shape.fill(theme.color(.surface))
                if enabled && (hovered || configuration.isPressed) { shape.fill(theme.color(.hover)) }
                shape.strokeBorder(theme.color(.line), lineWidth: theme.shape(.borderWidth))
            }.contentShape(shape).onHover { hovered = $0 }
            .animation(reduced ? nil : theme.motion.animation, value: hovered || configuration.isPressed)
    }
}

package struct TextActionLink: View {
    let theme: Theme
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduced

    package init(theme: Theme, title: String, symbol: String, action: @escaping () -> Void) {
        self.theme = theme
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    package var body: some View {
        Button(action: action) {
            HStack(spacing: theme.space(.sp1)) {
                Text(title)
                Image(systemName: symbol).accessibilityHidden(true)
            }.font(theme.font(.body, size: theme.tokens.textStyle(.micro).size))
                .foregroundStyle(theme.color(hovered ? .text : .text2))
                .frame(minHeight: theme.component(.libraryMoreSize)).contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovered = $0 }
            .animation(reduced ? nil : theme.motion.animation, value: hovered)
    }
}

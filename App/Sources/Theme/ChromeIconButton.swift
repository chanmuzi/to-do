import SwiftUI

/// 노트, 일정과 라이브러리의 도구 아이콘 규격.
package struct ChromeIconButton: View {
    let theme: Theme
    let title: String
    let symbol: String
    let enabled: Bool
    let action: () -> Void

    package init(theme: Theme, title: String, symbol: String, enabled: Bool = true, action: @escaping () -> Void) {
        self.theme = theme
        self.title = title
        self.symbol = symbol
        self.enabled = enabled
        self.action = action
    }

    package var body: some View {
        Button(action: action) {
            if let image = theme.symbolImage(symbol, size: .iconLarge) {
                Image(nsImage: image).renderingMode(.template)
                    .frame(width: theme.component(.iconButton), height: theme.component(.iconButton))
            }
        }.buttonStyle(SettingsButton(theme: theme, selected: false)).disabled(!enabled).accessibilityLabel(title)
    }
}

import MarkdownSyntax

package extension InkColor {
    nonisolated var token: ColorToken {
        switch hue {
        case .gray: foreground ? .inkGrayFG : .inkGrayBG
        case .brown: foreground ? .inkBrownFG : .inkBrownBG
        case .orange: foreground ? .inkOrangeFG : .inkOrangeBG
        case .yellow: foreground ? .inkYellowFG : .inkYellowBG
        case .green: foreground ? .inkGreenFG : .inkGreenBG
        case .blue: foreground ? .inkBlueFG : .inkBlueBG
        case .purple: foreground ? .inkPurpleFG : .inkPurpleBG
        case .pink: foreground ? .inkPinkFG : .inkPinkBG
        case .red: foreground ? .inkRedFG : .inkRedBG
        }
    }
}

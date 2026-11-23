#if DEBUG
import SwiftUI
import Theme

enum DebugAgentFaces {
    static func write(theme: Theme, stationary: Bool, to url: URL) throws {
        let sizes = AgentFaceSize.allCases
        let sample = Grid(alignment: .leading, horizontalSpacing: theme.space(.sp5), verticalSpacing: theme.space(.sp2)) {
            GridRow {
                Text("상태")
                ForEach(sizes.indices, id: \.self) { i in Text("\(Int(theme.component(sizes[i].token)))pt") }
            }
            ForEach(AgentFaceState.allCases, id: \.self) { state in
                GridRow {
                    Text(state.rawValue)
                    ForEach(sizes.indices, id: \.self) { i in
                        let size = sizes[i]
                        AgentFace(theme: theme, state: state, size: size).glyph(at: stationary ? nil : 1)
                            .frame(width: theme.component(size.token), height: theme.component(size.token))
                            .gridColumnAlignment(.center)
                    }
                }
            }
        }
        .font(theme.font(.ui)).foregroundStyle(theme.color(.text))
        .padding(theme.space(.sp4)).background(theme.color(.surface))
        .environment(\.colorScheme, theme.appearance == .dark ? .dark : .light)
        let renderer = ImageRenderer(content: sample)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 1
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
    }
}
#endif

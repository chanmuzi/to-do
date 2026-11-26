import Models
import SwiftUI
import Theme

struct AgentContextIcon: View {
    let item: AgentContextItem
    let size: CGFloat
    let catalog: AgentContextCatalog
    let controls: AgentContextControls
    let theme: Theme
    var body: some View {
        Group {
            if case .space(let id) = item, let space = catalog.spaces[id], space.icon != .none {
                controls.spaceIcon(space, size)
            } else if case .note = item {
                Image(nsImage: AgentWindowGlyph.note.image(theme: theme)).resizable().renderingMode(.template)
            } else {
                Image(systemName: symbol).font(.system(size: size))
            }
        }.frame(width: size, height: size).foregroundStyle(theme.color(.text2)).accessibilityHidden(true)
    }
    private var symbol: String {
        switch item {
        case .view(.today): "sun.max"
        case .view(.pinned): "pin"
        case .space: "folder"
        case .period: "calendar"
        case .note: "doc"
        }
    }
}

struct AgentContextStrip: View {
    let draft: AgentDraft
    let theme: Theme
    let controls: AgentContextControls
    let openNote: (NoteID) -> Void
    let choose: () -> Void
    @State private var hover: AgentContextItem?
    @FocusState private var focused: AgentContextItem?

    var body: some View {
        let catalog = controls.catalog()
        ChipFlow(gap: theme.space(.sp1)) {
            ForEach(draft.conversation.context, id: \.self) { item in
                chip(item, catalog: catalog)
            }
            Button(action: choose) {
                HStack(spacing: theme.space(.sp1)) {
                    Image(nsImage: AgentWindowGlyph.plus.image(theme: theme)).renderingMode(.template)
                    if draft.conversation.context.isEmpty { Text("컨텍스트 추가").font(smallFont) }
                }.padding(.horizontal, draft.conversation.context.isEmpty ? theme.component(.chromePaddingEnd) : 0)
                    .frame(minWidth: theme.component(.iconButton), minHeight: theme.component(.iconButton))
            }.buttonStyle(SettingsButton(theme: theme, selected: draft.contextPanel != nil))
                .accessibilityLabel("컨텍스트 추가").background(ContextAnchor(draft: draft))
        }
    }

    private var smallFont: Font { theme.font(.body, size: theme.tokens.textStyle(.micro).size) }

    private func chip(_ item: AgentContextItem, catalog: AgentContextCatalog) -> some View {
        let name = catalog.name(item)
        let size = theme.component(.menuIcon)
        var expanded = hover == item || focused == item
        #if DEBUG
        expanded = expanded || draft.previewContextHover == item
        #endif
        return HStack(spacing: theme.component(.agentChipGap)) {
            Button {
                if case .note(let id) = item, catalog.notes[id] != nil { openNote(id) }
                else if let selection = item.librarySelection { controls.openLibrary(selection) }
            } label: {
                HStack(spacing: theme.component(.agentChipGap)) {
                    AgentContextIcon(item: item, size: size, catalog: catalog, controls: controls, theme: theme)
                    Text(name).lineLimit(1).font(smallFont).foregroundStyle(theme.color(.text))
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).focused($focused, equals: item)
                .onKeyPress(.delete) { draft.toggleContext(item); return .handled }
                .accessibilityAction(named: "빼기") { draft.toggleContext(item) }
            if expanded {
                Button { draft.toggleContext(item) } label: {
                    Image(systemName: "xmark").font(.system(size: theme.component(.settingsCloseIcon)))
                        .foregroundStyle(theme.color(.text)).frame(width: size, height: theme.component(.agentFaceLarge))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("\(name) 빼기")
            }
        }.padding(.horizontal, theme.component(.agentChipInset)).frame(height: theme.component(.agentFaceLarge))
            .background(theme.color(.surface2), in: RoundedRectangle(cornerRadius: theme.shape(.chipRadius)))
            .onHover { active in
                if active { hover = item } else if hover == item { hover = nil }
            }
    }
}

private struct ContextAnchor: NSViewRepresentable {
    let draft: AgentDraft
    final class AnchorView: NSView {
        weak var draft: AgentDraft?
        override func setFrameOrigin(_ newOrigin: NSPoint) {
            super.setFrameOrigin(newOrigin)
            draft?.contextPanel?.reposition()
        }
        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            draft?.contextPanel?.reposition()
        }
    }
    func makeNSView(context: Context) -> AnchorView { AnchorView() }
    func updateNSView(_ view: AnchorView, context: Context) {
        view.draft = draft
        draft.contextAnchor = view
        if let panel = draft.contextPanel {
            DispatchQueue.main.async { [weak panel] in panel?.reposition() }
        }
    }
}

private struct ChipFlow: Layout {
    let gap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.reduce(CGFloat.zero) { $0 + $1.sizeThatFits(.unspecified).width + gap }
        return CGSize(width: width, height: rows(width: width, subviews: subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, frame) in zip(subviews, rows(width: bounds.width, subviews: subviews).frames) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                       proposal: ProposedViewSize(frame.size))
        }
    }

    private func rows(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], height: CGFloat) {
        var frames: [CGRect] = []
        var rowStart = 0
        var rowTop: CGFloat = 0
        var rowHeight: CGFloat = 0
        var x: CGFloat = 0

        func centerRow() {
            for index in rowStart..<frames.count {
                frames[index].origin.y = rowTop + (rowHeight - frames[index].height) / 2
            }
        }

        for view in subviews {
            let ideal = view.sizeThatFits(.unspecified)
            let size = ideal.width > width ? view.sizeThatFits(.init(width: width, height: nil)) : ideal
            if x > 0 && x + size.width > width {
                centerRow()
                rowTop += rowHeight + gap
                rowStart = frames.count
                rowHeight = 0
                x = 0
            }
            frames.append(CGRect(x: x, y: rowTop, width: min(width, size.width), height: size.height))
            x += size.width + gap
            rowHeight = max(rowHeight, size.height)
        }
        centerRow()
        return (frames, rowTop + rowHeight)
    }
}

import Models
import SwiftUI

/// 시계와 라이브러리가 같은 날짜 구획과 열기 동작을 사용한다.
package struct ConversationHistoryList: View {
    let theme: Theme
    let conversations: [AgentConversation]
    let open: (UUID) -> Void
    @Binding var selection: UUID?
    var rename: ((UUID, String) -> Void)?
    var delete: ((UUID) -> Void)?
    @State private var editing: UUID?
    @State private var editedName = ""
    let previewHover: UUID?
    @State private var menuID: UUID?
    @State private var hovered: UUID?
    @Environment(\.calendar) private var calendar

    package init(theme: Theme, conversations: [AgentConversation], selection: Binding<UUID?>,
                 previewHover: UUID? = nil, rename: ((UUID, String) -> Void)? = nil, delete: ((UUID) -> Void)? = nil, open: @escaping (UUID) -> Void) {
        self.theme = theme
        self.conversations = conversations
        self._selection = selection
        self.previewHover = previewHover
        self.rename = rename
        self.delete = delete
        self.open = open
    }

    package var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: theme.space(.sp5)) {
                ForEach(ConversationDay.sections(conversations, calendar: calendar)) { day in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: theme.component(.agentRowInset)) {
                            Image(systemName: "calendar").font(theme.font(.body, size: theme.component(.libraryHeadingIcon)))
                                .foregroundStyle(theme.color(.text2))
                            Text(dayTitle(day.id)).font(theme.font(.libraryListHeading))
                        }
                        .frame(height: theme.lineHeight(.libraryListHeading))
                        .padding(.bottom, theme.component(.agentChipInset))
                        rule
                        ForEach(day.conversations) { value in
                            row(value)
                            if value.id != day.conversations.last?.id { rule.padding(.leading, theme.component(.libraryRowLeading)) }
                        }
                    }
                }
            }.padding(.horizontal, theme.component(.libraryRowLeading))
                .padding(.vertical, theme.component(.libraryRowTrailing))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rule: some View { theme.color(.line).frame(height: theme.shape(.borderWidth)) }

    private func dayTitle(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "오늘" }
        if calendar.isDateInYesterday(date) { return "어제" }
        return date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: Locale(identifier: "ko_KR")))
    }

    private var renameUnderline: some View {
        let font = theme.nsFont(.row, weight: theme.tokens.textStyle(.body).weight)
        let width = (editedName as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
        return GeometryReader { geometry in
            theme.color(.text3)
                .frame(width: min(geometry.size.width, width + theme.component(.caretWidth)), height: theme.shape(.borderWidth))
                .frame(maxHeight: .infinity, alignment: .bottomLeading)
        }.allowsHitTesting(false)
    }

    private func row(_ value: AgentConversation) -> some View {
        let isEditing = editing == value.id
        let isHovered = (previewHover ?? hovered) == value.id || menuID == value.id || isEditing
        func beginRename() {
            editedName = value.name
            editing = value.id
        }
        let subtitle = value.needsAnswer ? "답을 기다리고 있어요" : value.requests.last?.answer
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: theme.component(.iconButtonGap)) {
                if isEditing {
                    CommandTextField(text: $editedName, theme: theme, placeholder: "대화 이름",
                                     font: theme.nsFont(.row, weight: theme.tokens.textStyle(.body).weight), submit: {
                        rename?(value.id, editedName)
                        editing = nil
                    }, cancel: { editing = nil })
                    .frame(height: theme.lineHeight(.row))
                    .overlay(alignment: .bottomLeading) { renameUnderline }
                } else {
                    Text(value.name).font(theme.font(.row, weight: theme.tokens.textStyle(.body).weight))
                        .frame(height: theme.lineHeight(.row))
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(theme.font(.rowSub)).foregroundStyle(theme.color(.text3))
                        .frame(height: theme.component(.agentFaceMedium))
                }
            }.lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Group {
                Text(ReminderPresentation.clock(value.updatedAt, format: .koreanMeridiem, calendar: calendar))
                    .font(theme.font(.body, size: theme.tokens.textStyle(.micro).size).monospacedDigit()).foregroundStyle(theme.color(.text3))
                if value.needsAnswer {
                    ConversationNoticeDot(theme: theme).padding(.leading, theme.space(.sp2))
                        .padding(.trailing, theme.space(.sp1))
                }
            }.opacity(isHovered && rename != nil ? 0 : 1)
        }
        .padding(.leading, theme.component(.libraryRowLeading))
        .padding(.top, theme.component(.libraryRowPaddingY)).padding(.bottom, theme.space(.sp2))
        .background {
            RoundedRectangle(cornerRadius: theme.component(.agentRowInset))
                .fill(selection == value.id ? theme.color(.selected) : isHovered ? theme.color(.hover) : .clear)
                .padding(.horizontal, -theme.component(.agentInputInset))
                .padding(.top, theme.component(.iconButtonGap)).padding(.bottom, theme.shape(.borderWidth))
        }
        .contentShape(Rectangle())
        .overlay {
            if !isEditing {
                HistoryRowInput(id: value.id, contextMenu: rename != nil) { count in
                    selection = value.id
                    if count == 2 { open(value.id) }
                }
            }
        }
        .overlay(alignment: .trailing) {
            if let delete, !isEditing {
                ConversationMenu(theme: theme, id: value.id, revealed: isHovered, open: { open(value.id) },
                                 visibilityChanged: { shown in
                                     if shown { menuID = value.id } else if menuID == value.id { menuID = nil }
                                 }, rename: beginRename, delete: { delete(value.id) })
                    .frame(width: theme.component(.iconButton), height: theme.component(.iconButton))
            }
        }
        .onHover { if $0 { hovered = value.id } else if hovered == value.id { hovered = nil } }
        .accessibilityElement(children: rename == nil ? .combine : .contain)
        .accessibilityLabel(value.name).accessibilityValue(value.needsAnswer ? "답변 필요" : "")
        .accessibilityAddTraits(selection == value.id ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { selection = value.id; open(value.id) }
        .focusable()
        .onKeyPress(.return) { guard !isEditing else { return .ignored }; selection = value.id; open(value.id); return .handled }
    }
}

package struct ConversationNoticeDot: View {
    package let theme: Theme
    package init(theme: Theme) { self.theme = theme }
    package var body: some View {
        Circle().fill(theme.color(.warn))
            .frame(width: theme.component(.noticeDot), height: theme.component(.noticeDot))
            .accessibilityLabel("답변 필요")
    }
}

private struct HistoryRowInput: NSViewRepresentable {
    let id: UUID
    let contextMenu: Bool
    let activate: (Int) -> Void
    func makeNSView(context: Context) -> HistoryRowInputView { HistoryRowInputView() }
    func updateNSView(_ view: HistoryRowInputView, context: Context) {
        view.hasCommands = contextMenu
        view.id = id
        view.activate = activate
        view.setAccessibilityElement(false)
    }
}

/// 한 번의 누름과 뗌을 같은 줄이 받아 첫 선택과 두 번째 열기가 분리된다.
package final class HistoryRowInputView: NSView {
    package fileprivate(set) var id: UUID?
    fileprivate var activate: ((Int) -> Void)?
    fileprivate var hasCommands = false
    public override func rightMouseDown(with event: NSEvent) {
        guard hasCommands, let id else { super.rightMouseDown(with: event); return }
        window?.contentView?.conversationButton(id)?.showMenu()
    }
    private var clickCount = 0
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    public override var mouseDownCanMoveWindow: Bool { false }
    public override func mouseDown(with event: NSEvent) {
        if hasCommands && event.modifierFlags.contains(.control) { rightMouseDown(with: event) }
        else { clickCount = event.clickCount }
    }
    public override func mouseUp(with event: NSEvent) {
        defer { clickCount = 0 }
        guard clickCount > 0, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        activate?(clickCount)
    }
}

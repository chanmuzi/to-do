import AppKit
import SwiftUI
import Models
import SpaceIcons
import Theme

struct LibrarySidebar: View {
    @Bindable var model: LibraryModel
    @State private var deleting: Space?
    private var theme: Theme { model.theme }
    var body: some View {
        VStack(spacing: 0) {
            sidebarScroll
            if model.router.isConnected(.openSettings) { settingsRow.padding(.horizontal, theme.component(.librarySidebarInset)) }
        }.padding(.top, theme.component(.libraryHeaderHeight))
        .padding(.bottom, theme.space(.sp2))
        .frame(width: theme.component(.librarySidebarWidth))
        .foregroundStyle(theme.libraryColor(.text)).background(theme.libraryColor(.surface2))
        .confirmationDialog("스페이스를 삭제할까요? 노트는 스페이스 없이 남습니다.",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("스페이스 삭제", role: .destructive) { if let space = deleting { model.deleteSpace(space.id) }; deleting = nil }
            Button("취소", role: .cancel) { deleting = nil }
        }
    }

    private var sidebarScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.component(.librarySectionGap)) {
                VStack(spacing: theme.component(.librarySidebarRowGap)) {
                    sectionHeader("보기")
                    ForEach(model.settings.visibleViews, id: \.self) { item in row(item, symbol: symbol(item)) }
                }
                VStack(spacing: theme.component(.librarySidebarRowGap)) {
                    LibrarySectionHeader(theme: theme, title: "에이전트", symbol: nil, label: "에이전트에게 요청",
                                         action: { model.router.route(.requestAgent) }, agentFace: true, previewHover: headerHover)
                    conversationRow
                }
                VStack(spacing: theme.component(.librarySidebarRowGap)) {
                    sectionHeader("스페이스", symbol: "plus", label: "새 스페이스") { model.beginSpaceEditing() }
                    ForEach(model.spaceList) { space in
                        if model.editingSpace && model.renamingSpaceID == space.id {
                            spaceInput
                        } else {
                            LibrarySpaceRow(model: model, space: space,
                                rename: { model.beginSpaceEditing(space.id) }, delete: { deleting = space })
                        }
                        if model.expanded.contains(space.id) {
                            ForEach(model.index.days(in: space.id), id: \.self) { day in
                                row(.day(space.id, day), symbol: nil, indented: true)
                                    .overlay(alignment: .leading) {
                                        theme.libraryColor(.guide).frame(width: theme.shape(.borderWidth))
                                            .padding(.leading, theme.space(.sp4)).allowsHitTesting(false)
                                    }
                            }
                        }
                    }
                    if model.editingSpace && model.renamingSpaceID == nil { spaceInput }
                }
                VStack(spacing: theme.component(.librarySidebarRowGap)) {
                    sectionHeader("아카이브")
                    row(.archived, symbol: "archivebox")
                    row(.trash, symbol: "trash")
                }
                let upcoming = model.index.upcoming
                let collapsedLimit = 5
                if !upcoming.isEmpty {
                    VStack(spacing: theme.component(.librarySidebarRowGap)) {
                        sectionHeader("다가오는 일정")
                        ForEach(upcoming.prefix(model.showAllUpcoming ? upcoming.count : collapsedLimit)) { entry in
                            UpcomingButton(model: model, entry: entry)
                        }
                        if upcoming.count > collapsedLimit {
                            TextActionLink(theme: theme, title: model.showAllUpcoming ? "간단히 보기" : "모두 보기", symbol: "chevron.right") {
                                model.showAllUpcoming.toggle()
                                model.dismissUpcoming()
                            }
                            .padding(.trailing, theme.space(.sp2)).frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
            }.padding(.horizontal, theme.component(.librarySidebarInset))
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, _ in
            model.dismissUpcoming()
        }
    }

    @State private var hoveringConversation = false
    @FocusState private var focusedConversation: Bool
    private var headerHover: Bool {
        #if DEBUG
        model.previewSectionHover
        #else
        false
        #endif
    }

    private var conversationRow: some View {
        let showsAction = hoveringConversation || focusedConversation
        return row(.conversations, symbol: "bubble.left")
            .focused($focusedConversation)
            .overlay(alignment: .trailing) {
                if showsAction {
                    ChromeIconButton(theme: theme, title: "새 대화", symbol: "plus", action: model.newConversation)
                        .padding(.trailing, theme.space(.sp1))
                } else if model.conversations().contains(where: \.needsAnswer) {
                    ConversationNoticeDot(theme: theme)
                        .padding(.trailing, theme.space(.sp2) + theme.space(.sp1)).allowsHitTesting(false)
                }
            }
            .onHover { hoveringConversation = $0 }
            .contextMenu { Button("새 대화", action: model.newConversation) }
            .accessibilityAction(named: "새 대화", model.newConversation)
    }

    private var settingsRow: some View {
        VStack(spacing: theme.component(.chromePaddingEnd)) {
            theme.libraryColor(.line).frame(height: theme.shape(.borderWidth)).padding(.horizontal, theme.space(.sp2))
            Button { model.router.route(.openSettings) } label: {
                SidebarColumns(theme: theme) {
                    LibrarySymbol(theme: theme, name: "gearshape", size: .iconMedium)
                } content: {
                    Text("설정").font(theme.font(.body, size: theme.tokens.textStyle(.ui).size))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.foregroundStyle(theme.libraryColor(.text2)).frame(height: theme.component(.rowHeight))
            }.buttonStyle(LibraryButtonStyle(theme: theme, hoverName: "설정"))
        }
    }
    private var spaceInput: some View {
        SidebarColumns(theme: theme) {
            Button { model.choosingDraftIcon = true } label: {
                SidebarSpaceIcon(model: model, icon: model.draftIcon)
                    .frame(width: theme.component(.controlHeight), height: theme.component(.controlHeight))
                    .contentShape(Rectangle())
            }.buttonStyle(LibraryButtonStyle(theme: theme)).accessibilityLabel("스페이스 아이콘")
                .disabled(model.renamingSpaceID != nil)
                .popover(isPresented: $model.choosingDraftIcon) { IconPickerView(model: model) }
                .onChange(of: model.choosingDraftIcon) { _, open in if !open { model.draftFocus += 1 } }
        } content: {
            CommandTextField(text: $model.spaceName, theme: theme, placeholder: "스페이스 이름",
                             font: theme.spaceNameFont(selected: model.renamingSpaceID.map { model.selection == .space($0) } ?? false),
                             focusToken: model.draftFocus,
                             submit: model.submitSpaceEditing, cancel: model.cancelSpaceEditing)
        }.padding(.trailing, theme.space(.sp2)).frame(height: theme.component(.rowHeight))
            .background(theme.libraryColor(.selected), in: RoundedRectangle(cornerRadius: theme.shape(.controlRadius)))
            .background(SpaceInputBounds(model: model))
    }
    private func sectionHeader(_ title: String, symbol: String? = nil, label: String = "", action: @escaping () -> Void = {}) -> some View {
        LibrarySectionHeader(theme: theme, title: title, symbol: symbol, label: label, action: action)
    }

    private func row(_ item: LibrarySelection, symbol: String?, indented: Bool = false) -> some View {
        let selected = model.selection == item
        return Button { model.select(item) } label: {
            let title = Text(model.title(item)).lineLimit(1)
                .font(theme.font(.body, size: theme.tokens.textStyle(.row).size, weight: theme.tokens.textStyle(selected ? .selected : .body).weight))
                .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                if let symbol {
                    SidebarColumns(theme: theme) {
                        LibrarySymbol(theme: theme, name: symbol, size: .iconMedium)
                            .foregroundStyle(theme.libraryColor(selected ? .text : .text2))
                    } content: {
                        title
                    }
                } else {
                    title.padding(.leading, theme.space(.sp6))
                }
            }
            .foregroundStyle(theme.libraryColor(selected ? .text : .text2))
            .padding(.trailing, theme.space(.sp2)).frame(height: theme.component(.rowHeight))
        }.buttonStyle(LibraryButtonStyle(theme: theme, selected: selected, hoverName: model.title(item)))
    }
    private func symbol(_ item: LibrarySelection) -> String {
        switch item { case .today: "sun.max"; case .floating: "pin"; case .reminders: "clock"; default: "line.3.horizontal" }
    }
}

/// 이름 입력도 같은 아이콘 중심과 글자 시작선을 사용한다.
private struct SidebarColumns<Icon: View, Content: View>: View {
    let theme: Theme
    @ViewBuilder let icon: () -> Icon
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: theme.component(.iconGap)) {
            icon().frame(width: theme.component(.controlHeight))
            content()
        }.padding(.leading, theme.component(.iconGap))
    }
}

private struct SidebarSpaceIcon: View {
    let model: LibraryModel
    let icon: SpaceIcon

    var body: some View {
        let side = model.theme.component(.iconMedium)
        SpaceIconView(icon: icon == .none ? LibraryModel.defaultSpaceIcon : icon,
                      directory: model.spaces.imageDirectory, theme: model.theme,
                      size: side, color: model.theme.nsColor(.text2))
            .frame(width: side, height: side)
    }
}

private struct LibrarySpaceRow: View {
    @Bindable var model: LibraryModel
    let space: Space
    let rename: () -> Void
    let delete: () -> Void
    @State private var hovered = false
    private var theme: Theme { model.theme }
    private var selected: Bool { model.selection == .space(space.id) }
    var body: some View {
        let expanded = model.expanded.contains(space.id)
        SidebarColumns(theme: theme) {
            Button {
                if expanded { model.expanded.remove(space.id) } else { model.expanded.insert(space.id) }
            } label: {
                ZStack {
                    SidebarSpaceIcon(model: model, icon: space.icon).opacity(hovered || expanded ? 0 : 1)
                    LibrarySymbol(theme: theme, name: expanded ? "chevron.down" : "chevron.right", size: .iconSmall)
                        .opacity(hovered || expanded ? 1 : 0)
                }.frame(width: theme.component(.controlHeight), height: theme.component(.rowHeight)).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(space.name) 날짜").accessibilityValue(expanded ? "펼쳐짐" : "접힘")
        } content: {
            Button { model.select(.space(space.id)) } label: {
                Text(space.name).font(Font(theme.spaceNameFont(selected: selected) as CTFont))
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: theme.component(.rowHeight)).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
            SpaceMenuControl(model: model, space: space, rename: rename, delete: delete, contextOnly: false)
                .frame(width: theme.component(.libraryMoreSize), height: theme.component(.libraryMoreSize))
                .background(theme.libraryColor(.line), in: RoundedRectangle(cornerRadius: theme.shape(.controlRadius)))
                .opacity(hovered ? 1 : 0)
        }.padding(.trailing, theme.space(.sp1)).frame(height: theme.component(.rowHeight))
            .foregroundStyle(theme.libraryColor(selected || hovered ? .text : .text2))
            .background(selected ? theme.libraryColor(.selected) : (hovered ? theme.libraryColor(.hover) : .clear),
                        in: RoundedRectangle(cornerRadius: theme.shape(.controlRadius)))
            .background(LibrarySidebarHover(name: space.name) { hovered = $0 })
            .overlay { SpaceMenuControl(model: model, space: space, rename: rename, delete: delete, contextOnly: true) }
            .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : theme.motion.animation, value: hovered)
            .popover(isPresented: Binding(get: { model.iconSpace == space.id }, set: { if !$0 { model.iconSpace = nil } })) {
                IconPickerView(model: model, spaceID: space.id)
            }
    }

}

private struct LibrarySectionHeader: View {
    let theme: Theme
    let title: String
    let symbol: String?
    let label: String
    let action: () -> Void
    var agentFace = false
    var previewHover = false
    @State private var hovered = false
    var body: some View {
        HStack {
            Text(title).font(theme.font(.librarySection)).foregroundStyle(theme.libraryColor(.text3))
            Spacer()
            if agentFace {
                Button(action: action) {
                    AgentFace(theme: theme).frame(width: theme.component(.iconButton), height: theme.component(.iconButton))
                }.buttonStyle(SettingsButton(theme: theme, selected: false))
                    .accessibilityLabel(label).opacity(hovered || previewHover ? 1 : 0)
            } else if let symbol {
                ChromeIconButton(theme: theme, title: label, symbol: symbol, action: action).opacity(hovered ? 1 : 0)
            }
        }.frame(height: theme.component(.librarySectionHeaderHeight)).padding(.horizontal, theme.space(.sp2))
            .background(agentFace && (hovered || previewHover) ? theme.libraryColor(.hover) : .clear,
                        in: RoundedRectangle(cornerRadius: theme.shape(.controlRadius)))
            .contentShape(Rectangle()).onHover { hovered = $0 }
            .accessibilityActions { if agentFace { Button(label, action: action) } }
            .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : theme.motion.animation, value: hovered)
    }
}

private struct SpaceInputBounds: NSViewRepresentable {
    let model: LibraryModel
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        model.spaceInputView = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}

private extension Theme {
    func spaceNameFont(selected: Bool) -> NSFont {
        nsFont(selected ? .selected : .body, size: tokens.textStyle(.row).size)
    }
}

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
        ScrollView {
            VStack(alignment: .leading, spacing: theme.component(.sectionGap)) {
                VStack(spacing: theme.component(.librarySidebarRowGap)) {
                    sectionHeader("보기", symbol: "slider.horizontal.3", label: "보기 편집") { model.editingViews = true }
                        .popover(isPresented: $model.editingViews) { LibraryViewEditor(model: model) }
                    ForEach(model.settings.visibleViews, id: \.self) { item in row(item, symbol: symbol(item)) }
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
                            Button(model.showAllUpcoming ? "간단히 보기" : "모두 보기") {
                                model.showAllUpcoming.toggle()
                                model.dismissUpcoming()
                            }
                            .font(theme.font(.title, weight: theme.tokens.textStyle(.body).weight))
                            .foregroundStyle(theme.libraryColor(.text3)).buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, theme.space(.sp6))
                        }
                    }
                }
            }.padding(.top, theme.space(.sp2))
        }
        .padding(.top, theme.component(.libraryHeaderHeight))
        .padding(.horizontal, theme.space(.sp2))
        .padding(.bottom, theme.space(.sp2))
        .frame(width: theme.component(.librarySidebarWidth))
        .foregroundStyle(theme.libraryColor(.text)).background(theme.libraryColor(.surface2))
        .confirmationDialog("스페이스를 삭제할까요? 노트는 스페이스 없이 남습니다.",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("스페이스 삭제", role: .destructive) { if let space = deleting { model.deleteSpace(space.id) }; deleting = nil }
            Button("취소", role: .cancel) { deleting = nil }
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
                .font(theme.font(.body, size: theme.tokens.textStyle(.ui).size, weight: theme.tokens.textStyle(selected ? .selected : .body).weight))
                .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                if let symbol {
                    SidebarColumns(theme: theme) {
                        LibrarySymbol(theme: theme, name: symbol, size: .iconLarge)
                            .foregroundStyle(theme.libraryColor(selected ? .text : .text2))
                    } content: {
                        title
                        Text(String(model.index.rows(for: item).count)).font(theme.libraryNumberFont)
                            .foregroundStyle(theme.libraryColor(.text3))
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
        HStack(spacing: theme.space(.sp1)) {
            icon().frame(width: theme.component(.controlHeight))
            content()
        }.padding(.leading, theme.space(.sp1))
    }
}

private struct SidebarSpaceIcon: View {
    let model: LibraryModel
    let icon: SpaceIcon

    var body: some View {
        let side = model.theme.component(.iconLarge)
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
        HStack(spacing: theme.space(.sp1)) {
            Button { model.select(.space(space.id)) } label: {
                SidebarColumns(theme: theme) {
                    SidebarSpaceIcon(model: model, icon: space.icon)
                } content: {
                    Text(space.name).font(Font(theme.spaceNameFont(selected: selected) as CTFont))
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: theme.component(.rowHeight)).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
            ZStack {
                Text(String(model.index.rows(for: .space(space.id)).count)).font(theme.libraryNumberFont)
                    .foregroundStyle(theme.libraryColor(.text3)).opacity(hovered ? 0 : 1)
                Menu { menuContents } label: { LibrarySymbol(theme: theme, name: "ellipsis", size: .iconLarge) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .opacity(hovered ? 1 : 0).accessibilityLabel("\(space.name) 더 보기")
            }.frame(width: theme.component(.libraryToolbarButton))
            Button {
                if model.expanded.contains(space.id) { model.expanded.remove(space.id) } else { model.expanded.insert(space.id) }
            } label: {
                LibrarySymbol(theme: theme, name: model.expanded.contains(space.id) ? "chevron.down" : "chevron.right", size: .iconSmall)
                    .foregroundStyle(theme.libraryColor(.text3))
                    .opacity(hovered || model.expanded.contains(space.id) ? 1 : 0)
                    .frame(width: theme.component(.controlHeight), height: theme.component(.rowHeight))
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(space.name) 날짜").accessibilityValue(model.expanded.contains(space.id) ? "펼쳐짐" : "접힘")
        }.padding(.trailing, theme.space(.sp1)).frame(height: theme.component(.rowHeight))
            .foregroundStyle(theme.libraryColor(selected ? .text : .text2))
            .background(selected ? theme.libraryColor(.selected) : (hovered ? theme.libraryColor(.hover) : .clear),
                        in: RoundedRectangle(cornerRadius: theme.shape(.controlRadius)))

            .onHover { hovered = $0 }
            .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : theme.motion.animation, value: hovered)
            .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : theme.motion.animation, value: selected)
            .contextMenu { menuContents }
            .popover(isPresented: Binding(get: { model.iconSpace == space.id }, set: { if !$0 { model.iconSpace = nil } })) {
                IconPickerView(model: model, spaceID: space.id)
            }
    }
    @ViewBuilder private var menuContents: some View {
        Button("아이콘 바꾸기", systemImage: "photo") { model.iconSpace = space.id }
        Button("이름 바꾸기", systemImage: "character.cursor.ibeam", action: rename)
        Divider()
        Button("스페이스 삭제", systemImage: "trash", action: delete)
    }
}

private struct LibrarySectionHeader: View {
    let theme: Theme
    let title: String
    let symbol: String?
    let label: String
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        HStack {
            Text(title).font(theme.font(.librarySection)).foregroundStyle(theme.libraryColor(.text3))
            Spacer()
            if let symbol {
                ChromeIconButton(theme: theme, title: label, symbol: symbol, action: action).opacity(hovered ? 1 : 0)
            }
        }.frame(height: theme.lineHeight(.librarySection)).padding(.bottom, theme.space(.sp1) - theme.component(.librarySidebarRowGap)).padding(.horizontal, theme.space(.sp2))
            .contentShape(Rectangle()).onHover { hovered = $0 }
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
        nsFont(selected ? .selected : .body, size: tokens.textStyle(.ui).size)
    }
}

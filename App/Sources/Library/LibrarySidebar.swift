import AppKit
import SwiftUI
import Models
import SpaceIcons
import Theme

struct LibrarySidebar: View {
    @Bindable var model: LibraryModel
    @State private var creating = false
    @State private var name = ""
    @State private var renaming: Space?
    @State private var deleting: Space?
    private var theme: Theme { model.theme }
    var body: some View {
        VStack(spacing: theme.space(.sp2)) {
            HStack(spacing: theme.space(.sp1)) {
                LibrarySymbol(theme: theme, name: "magnifyingglass", size: .iconSmall)
                    .foregroundStyle(theme.libraryColor(.text3))
                LibrarySearchField(text: $model.query, theme: theme)
            }
                .font(theme.font(.body)).padding(.horizontal, theme.space(.sp2))
                .frame(height: theme.component(.browseFindHeight))
                .background(theme.libraryColor(.surface3), in: RoundedRectangle(cornerRadius: theme.shape(.controlRadius)))
                .padding(.top, theme.component(.libraryHeaderHeight))
            ScrollView {
                VStack(alignment: .leading, spacing: theme.space(.sp5)) {
                    VStack(spacing: 0) {
                        sectionHeader("보기", symbol: "slider.horizontal.3", label: "보기 편집") { model.editingViews = true }
                            .popover(isPresented: $model.editingViews) { LibraryViewEditor(model: model) }
                        ForEach(model.settings.visibleViews, id: \.self) { item in row(item, symbol: symbol(item)) }
                    }
                    VStack(spacing: 0) {
                        sectionHeader("스페이스", symbol: "plus", label: "새 스페이스") { name = ""; creating = true }
                        ForEach(model.spaceList) { space in
                            LibrarySpaceRow(model: model, space: space,
                                rename: { name = space.name; renaming = space }, delete: { deleting = space })
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
                        if !model.index.rows(for: .space(nil)).isEmpty { row(.space(nil), symbol: nil) }
                    }
                    VStack(spacing: 0) {
                        sectionHeader("아카이브")
                        ForEach(model.index.archiveMonths, id: \.self) { row(.archive($0), symbol: "archivebox") }
                        row(.trash, symbol: "trash")
                    }
                    if !model.index.upcoming.isEmpty {
                        VStack(spacing: 0) {
                            sectionHeader("리마인더")
                            ForEach(model.index.upcoming) { note in
                                LibrarySelectableRow(model: model, note: note, rounded: true) {
                                    HStack(spacing: theme.space(.sp1)) {
                                        LibraryReminder(note: note, model: model)
                                        Text(note.title.isEmpty ? "제목 없음" : note.title).lineLimit(1)
                                        Spacer(minLength: 0)
                                    }.font(theme.font(.body)).frame(height: theme.component(.rowHeight))
                                        .padding(.horizontal, theme.space(.sp2))
                                }
                            }
                        }
                    }
                }.padding(.top, theme.space(.sp2))
            }
        }
        .padding(.horizontal, theme.space(.sp2))
        .padding(.bottom, theme.space(.sp2))
        .frame(width: theme.component(.librarySidebarWidth))
        .foregroundStyle(theme.libraryColor(.text)).background(theme.libraryColor(.surface2))
        .alert("새 스페이스", isPresented: $creating) {
            TextField("이름", text: $name)
            Button("만들기") { model.createSpace(name: name) }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("취소", role: .cancel) {}
        }
        .alert("이름 바꾸기", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("이름", text: $name)
            Button("저장") { if let space = renaming { model.renameSpace(space.id, name: name) }; renaming = nil }
            Button("취소", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("스페이스를 삭제할까요? 노트는 스페이스 없이 남습니다.",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("스페이스 삭제", role: .destructive) { if let space = deleting { model.deleteSpace(space.id) }; deleting = nil }
            Button("취소", role: .cancel) { deleting = nil }
        }
    }
    private func sectionHeader(_ title: String, symbol: String? = nil, label: String = "", action: @escaping () -> Void = {}) -> some View {
        LibrarySectionHeader(theme: theme, title: title, symbol: symbol, label: label, action: action)
    }

    private func row(_ item: LibrarySelection, symbol: String?, indented: Bool = false) -> some View {
        let selected = model.selection == item
        return Button { model.select(item) } label: {
            HStack(spacing: theme.space(.sp2)) {
                if let symbol {
                    LibrarySymbol(theme: theme, name: symbol, size: .iconLarge)
                        .foregroundStyle(theme.libraryColor(selected ? .onAccent : .text2))
                }
                Text(model.title(item)).lineLimit(1)
                    .font(theme.font(indented || isArchive(item) ? .ui : .body))
                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.libraryColor(selected ? .onAccent : (isArchive(item) || isPastDay(item) ? .text3 : .text)))
            .padding(.leading, indented ? theme.space(.sp6) : theme.space(.sp2))
            .padding(.trailing, theme.space(.sp2)).frame(height: theme.component(.rowHeight))
        }.buttonStyle(LibraryButtonStyle(theme: theme, selected: selected))
    }
    private func isPastDay(_ item: LibrarySelection) -> Bool {
        if case .day(_, let day) = item { return !model.index.calendar.isDate(day, inSameDayAs: model.index.now) }
        return false
    }
    private func isArchive(_ item: LibrarySelection) -> Bool { if case .archive = item { true } else { false } }
    private func symbol(_ item: LibrarySelection) -> String {
        switch item { case .today: "sun.max"; case .floating: "square.on.square"; case .reminders: "clock"; default: "line.3.horizontal" }
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
            Button {
                if model.expanded.contains(space.id) { model.expanded.remove(space.id) } else { model.expanded.insert(space.id) }
            } label: {
                LibrarySymbol(theme: theme, name: model.expanded.contains(space.id) ? "chevron.down" : "chevron.right", size: .iconSmall)
                    .frame(width: theme.component(.iconSmall), height: theme.component(.rowHeight))
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(space.name) 날짜 펼치기")
            Button { model.select(.space(space.id)) } label: {
                HStack(spacing: theme.space(.sp2)) {
                    SpaceIconView(icon: space.icon, directory: model.spaces.imageDirectory, theme: theme,
                                  size: theme.component(.iconLarge), color: theme.nsColor(selected ? .onAccent : .text2))
                        .frame(width: theme.component(.iconLarge), height: theme.component(.iconLarge))
                    Text(space.name).font(theme.font(.body)).lineLimit(1)
                    Spacer(minLength: 0)
                }.frame(height: theme.component(.rowHeight)).contentShape(Rectangle())
            }.buttonStyle(.plain)
            ZStack {
                Menu { menuContents } label: { LibrarySymbol(theme: theme, name: "ellipsis", size: .iconLarge) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .opacity(hovered ? 1 : 0).accessibilityLabel("\(space.name) 더 보기")
            }.frame(width: theme.component(.libraryToolbarButton))
        }.padding(.horizontal, theme.space(.sp1)).frame(height: theme.component(.rowHeight))
            .foregroundStyle(theme.libraryColor(selected ? .onAccent : .text))
            .background(selected ? theme.libraryColor(.accent) : (hovered ? theme.libraryColor(.hover) : .clear),
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
            Text(title).font(theme.font(.rowSub).bold())
            Spacer()
            if let symbol {
                LibraryIconButton(theme: theme, title: label, symbol: symbol, action: action).opacity(hovered ? 1 : 0)
            }
        }.frame(height: theme.component(.rowHeight)).padding(.horizontal, theme.space(.sp1))
            .contentShape(Rectangle()).onHover { hovered = $0 }
            .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : theme.motion.animation, value: hovered)
    }
}

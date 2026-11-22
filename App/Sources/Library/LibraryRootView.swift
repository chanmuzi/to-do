import AppKit
import SwiftUI
import Models
import Theme

struct LibraryRootView: View {
    @Bindable var model: LibraryModel
    private var theme: Theme { model.theme }
    var body: some View {
        HStack(spacing: 0) {
            LibrarySidebar(model: model)
            theme.libraryColor(.line).frame(width: theme.shape(.borderWidth))
            VStack(spacing: 0) {
                HStack(spacing: theme.space(.sp1)) {
                    if model.selection == .trash {
                        LibrarySymbol(theme: theme, name: "trash", size: .iconLarge)
                            .foregroundStyle(theme.libraryColor(.text2)).accessibilityHidden(true)
                    }
                    Text(model.title(model.selection)).font(theme.font(.paneTitle, size: theme.component(.libraryHeaderFont)))
                    Spacer()
                    ChromeIconButton(theme: theme, title: "보기 편집", symbol: "line.3.horizontal.decrease") {
                        model.editingViews.toggle()
                    }.popover(isPresented: $model.editingViews, arrowEdge: .bottom) { LibraryViewEditor(model: model) }
                    if model.showsNewNote {
                        ChromeIconButton(theme: theme, title: "새 노트", symbol: "plus", action: model.newNoteInSelection)
                    }
                }.padding(.leading, theme.component(.libraryRowLeading)).padding(.trailing, theme.space(.sp3))
                    .frame(height: theme.component(.libraryHeaderHeight))
                theme.libraryColor(.line).frame(height: theme.shape(.borderWidth))
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if model.rows.isEmpty {
                            Button(model.showsNewNote ? "새 노트" : "전체 노트") {
                                if !model.showsNewNote { model.select(.all) }
                                else { model.newNoteInSelection() }
                            }.buttonStyle(WhiteControl(theme: theme))
                                .padding(theme.space(.sp3))
                        }
                        let sections = model.sections
                        ForEach(sections) { section in
                            Text(section.id).font(theme.font(.librarySection)).foregroundStyle(theme.libraryColor(.text3))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, theme.component(.libraryRowLeading))
                                .padding(.top, section.id == sections.first?.id ? theme.component(.libraryRowTrailing) : theme.lineHeight(.row))
                                .padding(.bottom, theme.component(.chromePaddingEnd))
                                .overlay(alignment: .bottom) { LibraryListRule(theme: theme) }
                            ForEach(section.notes) { note in LibraryNoteRow(model: model, note: note) }
                        }
                    }
                }
                if let error = model.error {
                    HStack {
                        Text(error).font(theme.font(.rowSub)).textSelection(.enabled)
                        Button("다시 시도") { model.error = nil; model.refresh() }
                        Button("닫기") { model.error = nil }
                    }.buttonStyle(WhiteControl(theme: theme)).padding(theme.space(.sp2))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(theme.libraryColor(.surface))
        }.overlayPreferenceValue(UpcomingBounds.self) { anchors in
            GeometryReader { geometry in
                if let id = model.upcomingID, let anchor = anchors[id],
                   let entry = model.index.upcoming.first(where: { $0.id == id }) {
                    let rect = geometry[anchor]
                    UpcomingDetail(model: model, entry: entry, rowMidY: rect.midY, availableHeight: geometry.size.height)
                        .offset(x: theme.component(.librarySidebarWidth) + theme.component(.badgePad))
                }
            }
        }.foregroundStyle(theme.libraryColor(.text)).ignoresSafeArea().focusEffectDisabled()
    }
}

struct LibraryNoteRow: View {
    let model: LibraryModel
    let note: Note
    private var theme: Theme { model.theme }
    var body: some View {
        let preview = LibraryPreview(note)
        let weight = theme.tokens.textStyle(preview.isEmpty ? .body : .selected).weight
        let insetX = theme.space(.sp2)
        let insetY = theme.component(.libraryRowHighlightInsetY)
        LibrarySelectableRow(model: model, note: note, label: preview.title,
                             highlightInsets: EdgeInsets(top: insetY, leading: insetX, bottom: insetY, trailing: insetX)) {
            VStack(alignment: .leading, spacing: theme.component(.libraryRowGap)) {
                Text(preview.title).font(theme.font(.row, weight: weight))
                    .foregroundStyle(theme.libraryColor(preview.isEmpty ? .text3 : model.selection == .trash ? .text2 : .text))
                    .lineLimit(1)
                if !preview.subtitle.isEmpty {
                    Text(preview.subtitle).font(theme.font(.rowSub))
                        .foregroundStyle(theme.libraryColor(.text3)).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, theme.component(.libraryRowLeading))
                .padding(.vertical, theme.component(.libraryRowPaddingY))
        }.background(theme.tokens.rowTint(paletteID: note.colorID?.rawValue)?.color ?? .clear)
            .overlay(alignment: .bottom) { LibraryListRule(theme: theme) }
    }
}

private struct LibraryListRule: View {
    let theme: Theme
    var body: some View {
        theme.libraryColor(.line).frame(height: theme.shape(.borderWidth))
            .padding(.horizontal, theme.component(.libraryRowLeading)).allowsHitTesting(false)
    }
}

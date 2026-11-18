import AppKit
import SwiftUI
import Models
import Routing
import SpaceIcons
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
                    Text(model.title(model.selection)).font(theme.font(.paneTitle))
                    Spacer()
                    if model.router.isConnected(.openSettings) {
                        ChromeIconButton(theme: theme, title: "설정", symbol: "slider.horizontal.3") {
                            model.router.route(.openSettings)
                        }
                    }
                    if model.showsNewNote {
                        ChromeIconButton(theme: theme, title: "새 노트", symbol: "plus") {
                            var draft = NoteDraft()
                            switch model.selection { case .space(let id), .day(let id, _): draft.spaceID = id; default: break }
                            model.router.route(.newNote(NewNoteRequest(draft: draft)))
                        }
                    }
                }.padding(.leading, theme.component(.libraryRowLeading)).padding(.trailing, theme.component(.libraryRowTrailing))
                    .frame(height: theme.component(.libraryHeaderHeight))
                theme.libraryColor(.line).frame(height: theme.shape(.borderWidth))
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if model.rows.isEmpty {
                            Button(model.showsNewNote ? "새 노트" : "전체 노트") {
                                if !model.showsNewNote { model.select(.all) }
                                else {
                                    var draft = NoteDraft()
                                    switch model.selection { case .space(let id), .day(let id, _): draft.spaceID = id; default: break }
                                    model.router.route(.newNote(NewNoteRequest(draft: draft)))
                                }
                            }.font(theme.font(.body))
                                .padding(.horizontal, theme.space(.sp2)).frame(height: theme.component(.controlHeight))
                                .buttonStyle(LibraryButtonStyle(theme: theme))
                                .padding(theme.space(.sp3))
                        }
                        ForEach(model.sections) { section in
                            Text(section.id).font(theme.font(.librarySection)).foregroundStyle(theme.libraryColor(.text3))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, theme.component(.libraryRowLeading))
                                .padding(.top, theme.space(.sp3)).padding(.bottom, theme.space(.sp1))
                            ForEach(section.notes) { note in LibraryNoteRow(model: model, note: note) }
                        }
                    }
                }
                if let error = model.error {
                    HStack {
                        Text(error).font(theme.font(.rowSub)).textSelection(.enabled)
                        Button("다시 시도") { model.error = nil; model.refresh() }
                        Button("닫기") { model.error = nil }
                    }.padding(theme.space(.sp2))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(theme.libraryColor(.surface))
        }.overlayPreferenceValue(UpcomingBounds.self) { anchors in
            GeometryReader { geometry in
                if let id = model.upcomingID, let anchor = anchors[id],
                   let entry = model.index.upcoming.first(where: { $0.id == id }) {
                    let rect = geometry[anchor]
                    UpcomingDetail(model: model, entry: entry)
                        .background(UpcomingDetailBounds(model: model))
                        .offset(x: theme.component(.librarySidebarWidth) + theme.space(.sp1),
                                y: min(rect.minY, max(0, geometry.size.height - theme.component(.upcomingDetailHeight))))
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
        let weight = preview.isEmpty ? theme.tokens.textStyle(.body).weight : (model.selectedNoteID == note.id ? theme.tokens.textStyle(.selected).weight : nil)
        let insetX = theme.space(.sp2)
        let insetY = theme.component(.libraryRowHighlightInsetY)
        LibrarySelectableRow(model: model, note: note, label: preview.title,
                             highlightInsets: EdgeInsets(top: insetY, leading: insetX, bottom: insetY, trailing: insetX)) {
            HStack(spacing: theme.component(.libraryRowGap)) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(preview.title).font(theme.font(.row, weight: weight))
                        .foregroundStyle(theme.libraryColor(preview.isEmpty || model.selection == .trash ? .text2 : .rowTitle, on: model.selectedNoteID == note.id ? .selected : .surface3)).lineLimit(1)
                        .frame(height: theme.lineHeight(.row))
                    if !preview.subtitle.isEmpty {
                        Text(preview.subtitle).font(theme.font(.rowSub))
                            .foregroundStyle(theme.libraryColor(.text3, on: model.selectedNoteID == note.id ? .selected : .surface3)).lineLimit(1)
                            .frame(height: theme.lineHeight(.rowSub))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if preview.total > 0 {
                    Text("\(preview.completed)/\(preview.total)").font(theme.libraryNumberFont)
                        .foregroundStyle(theme.libraryColor(.text3))
                }
            }.padding(.leading, theme.component(.libraryRowLeading)).padding(.trailing, theme.component(.libraryRowTrailing))
                .frame(height: theme.component(.libraryRowHeight))
        }.background(theme.tokens.rowTint(paletteID: note.colorID?.rawValue)?.color ?? .clear)
    }
}

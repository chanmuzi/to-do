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
                        LibraryIconButton(theme: theme, title: "설정", symbol: "slider.horizontal.3") {
                            model.router.route(.openSettings)
                        }
                    }
                    if model.showsNewNote {
                        LibraryIconButton(theme: theme, title: "새 노트", symbol: "plus") {
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
                            Button(model.query.isEmpty ? (model.selection == .trash ? "전체 노트" : "새 노트") : "검색 지우기") {
                                if !model.query.isEmpty { model.query = "" }
                                else if model.selection == .trash { model.select(.all) }
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
                        ForEach(model.rows) { note in LibraryNoteRow(model: model, note: note) }
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
                        .foregroundStyle(theme.libraryColor(preview.isEmpty || model.selection == .trash ? .text2 : .rowTitle)).lineLimit(1)
                        .frame(height: theme.lineHeight(.row))
                    if !preview.subtitle.isEmpty {
                        Text(preview.subtitle).font(theme.font(.rowSub))
                            .foregroundStyle(theme.libraryColor(.text2)).lineLimit(1)
                            .frame(height: theme.lineHeight(.rowSub))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                LibraryReminder(note: note, model: model)
                    .frame(width: theme.component(.libraryReminderWidth), alignment: .trailing)
                LibrarySymbol(theme: theme, name: "pin.fill", size: .iconSmall)
                    .foregroundStyle(theme.libraryColor(.text3))
                    .opacity(model.index.windows[note.id]?.isOpen == true ? 1 : 0)
                    .frame(width: theme.component(.iconSmall))
            }.padding(.leading, theme.component(.libraryRowLeading)).padding(.trailing, theme.component(.libraryRowTrailing))
                .frame(height: theme.component(.libraryRowHeight))
                .overlay(alignment: .bottom) {
                    theme.libraryColor(.line).frame(height: theme.shape(.borderWidth)).allowsHitTesting(false)
                }
        }.background(theme.tokens.rowTint(paletteID: note.colorID?.rawValue)?.color ?? .clear)
    }
}

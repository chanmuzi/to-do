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
                    Text(model.title(model.selection)).font(theme.font(.paneTitle))
                    Spacer()
                    LibraryIconButton(theme: theme, title: "AI 패널", symbol: "sparkle", enabled: model.router.isConnected(.openAIPanel(context: nil))) {
                        model.router.route(.openAIPanel(context: nil))
                    }
                    LibraryIconButton(theme: theme, title: "설정", symbol: "slider.horizontal.3", enabled: model.router.isConnected(.openSettings)) {
                        model.router.route(.openSettings)
                    }
                    LibraryIconButton(theme: theme, title: "새 노트", symbol: "plus") {
                        var draft = NoteDraft()
                        switch model.selection { case .space(let id), .day(let id, _): draft.spaceID = id; default: break }
                        model.router.route(.newNote(NewNoteRequest(draft: draft)))
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
        LibrarySelectableRow(model: model, note: note) {
            HStack(spacing: theme.component(.libraryRowGap)) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(note.title.isEmpty ? "제목 없음" : note.title).font(theme.font(.row))
                        .foregroundStyle(theme.libraryColor(note.title.isEmpty ? .text3 : .text)).lineLimit(1)
                        .frame(height: theme.lineHeight(.row))
                    if !LibraryPreview.text(note.body).isEmpty {
                        Text(LibraryPreview.text(note.body)).font(theme.font(.rowSub))
                            .foregroundStyle(theme.libraryColor(.text2)).lineLimit(1)
                            .frame(height: theme.lineHeight(.rowSub))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                LibraryReminder(note: note, model: model)
                    .frame(width: theme.component(.libraryReminderWidth), alignment: .trailing)
                HStack(spacing: theme.component(.iconGap)) {
                    if !LibraryPreview.progress(note.body).isEmpty {
                        LibrarySymbol(theme: theme, name: "checkmark", size: .iconSmall)
                        Text(LibraryPreview.progress(note.body)).font(theme.font(.ui))
                    }
                }.foregroundStyle(theme.libraryColor(.text3))
                    .frame(width: theme.component(.libraryProgressWidth), alignment: .trailing)
                SpaceIconView(icon: note.spaceID.flatMap { model.spaces.space(for: $0)?.icon } ?? .none,
                              directory: model.spaces.imageDirectory, theme: theme, size: theme.component(.iconMedium))
                    .frame(width: theme.component(.iconLarge), height: theme.component(.iconLarge))
                LibrarySymbol(theme: theme, name: model.selection == .trash ? "arrow.uturn.backward" : "pin.fill", size: .iconMedium)
                    .foregroundStyle(theme.libraryColor(.text3))
                    .opacity(model.selection == .trash || model.index.windows[note.id]?.isOpen == true ? 1 : 0)
                    .frame(width: theme.component(.iconLarge))
            }.padding(.leading, theme.component(.libraryRowLeading)).padding(.trailing, theme.component(.libraryRowTrailing))
                .frame(height: theme.component(.libraryRowHeight))
                .overlay(alignment: .bottom) {
                    theme.libraryColor(.line).frame(height: theme.shape(.borderWidth)).allowsHitTesting(false)
                }
        }.background(theme.tokens.rowTint(paletteID: note.colorID?.rawValue)?.color ?? .clear)
    }
}

/// 편집기 의존 없이 목록용 텍스트와 투두 개수만 추린다. 코드 울타리 안 체크박스는 세지 않는다.
enum LibraryPreview {
    static func text(_ body: String) -> String {
        body.split(separator: "\n").prefix(3).map {
            String($0).replacingOccurrences(of: #"^\s*(?:[-*] )?(?:\[[ xX]\] |#{1,3} |[>+] )?"#, with: "", options: .regularExpression)
        }.joined(separator: ", ")
    }
    static func progress(_ body: String) -> String {
        var fence: String?, done = 0, total = 0
        for line in body.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("```") || text.hasPrefix("~~~") {
                let marker = String(text.prefix(3)); if fence == marker { fence = nil } else if fence == nil { fence = marker }; continue
            }
            guard fence == nil else { continue }
            let value = text.hasPrefix("- ") ? String(text.dropFirst(2)) : text
            if value.hasPrefix("[ ] ") || value.hasPrefix("[x] ") || value.hasPrefix("[X] ") {
                total += 1; if !value.hasPrefix("[ ]") { done += 1 }
            }
        }
        return total == 0 ? "" : "\(done)/\(total)"
    }
}

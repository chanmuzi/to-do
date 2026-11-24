import AppKit
import SwiftUI
import Models
import Theme

struct LibraryRootView: View {
    @Bindable var model: LibraryModel
    private var theme: Theme { model.theme }
    private var historyHover: UUID? {
        #if DEBUG
        model.previewHistoryHover
        #else
        nil
        #endif
    }
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
                    if model.selection == .conversations {
                        ChromeIconButton(theme: theme, title: "새 대화", symbol: "plus", action: model.newConversation)
                    } else if model.showsNewNote {
                        ChromeIconButton(theme: theme, title: "새 노트", symbol: "plus", action: model.newNoteInSelection)
                    }
                }.padding(.leading, theme.component(.libraryRowLeading)).padding(.trailing, theme.space(.sp3))
                    .frame(height: theme.component(.libraryHeaderHeight))
                theme.libraryColor(.line).frame(height: theme.shape(.borderWidth))
                if model.selection == .memory {
                    if let view = model.instructionView { InstructionHost(view: view) }
                    else { Spacer() }
                } else if model.selection == .proposals {
                    LibraryProposalPage(model: model)
                } else if model.selection == .conversations {
                    ConversationHistoryList(theme: theme, conversations: model.conversations(), selection: $model.selectedConversation,
                                            previewHover: historyHover, rename: model.renameConversation,
                                            delete: model.deleteConversation, open: model.openConversation)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            let sections = model.sections
                            if sections.isEmpty {
                                Button(model.showsNewNote ? "새 노트" : "전체 노트") {
                                    if !model.showsNewNote { model.select(.all) }
                                    else { model.newNoteInSelection() }
                                }.buttonStyle(WhiteControl(theme: theme))
                                    .padding(theme.space(.sp3))
                            }
                            let viewTitle = model.title(model.selection)
                            ForEach(sections) { section in
                                let header = section.header.flatMap { $0.title == viewTitle ? nil : $0 }
                                let isFirst = section.id == sections.first?.id
                                let indent = header != nil || sections.count > 1
                                    ? theme.component(.libraryHeadingIcon) + theme.component(.chromePaddingEnd) : 0
                                Section {
                                    ForEach(section.notes) { note in
                                        LibraryNoteRow(model: model, note: note, indent: indent,
                                                       showsRule: note.id != section.notes.last?.id)
                                    }
                                } header: {
                                    if let header {
                                        HStack(spacing: theme.component(.chromePaddingEnd)) {
                                            LibrarySymbol(theme: theme, name: header.symbol, size: .libraryHeadingIcon)
                                                .foregroundStyle(theme.libraryColor(.text2)).accessibilityHidden(true)
                                            Text(header.title).font(theme.font(.libraryListHeading))
                                                .foregroundStyle(theme.libraryColor(.text)).accessibilityAddTraits(.isHeader)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .frame(height: theme.lineHeight(.libraryListHeading))
                                        .padding(.horizontal, theme.component(.libraryRowLeading))
                                        .padding(.top, isFirst ? theme.component(.libraryRowTrailing) : theme.space(.sp5))
                                        .padding(.bottom, theme.component(.chromePaddingEnd))
                                        LibraryListRule(theme: theme)
                                    } else if !isFirst {
                                        LibraryListRule(theme: theme).padding(.top, theme.space(.sp5))
                                    }
                                }
                            }
                        }.id(model.selection)
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
    let indent: CGFloat
    let showsRule: Bool
    private var theme: Theme { model.theme }
    var body: some View {
        let preview = LibraryPreview(note)
        let weight = theme.tokens.textStyle(.body).weight
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
                .padding(.leading, theme.component(.libraryRowLeading) + indent)
                .padding(.trailing, LibraryRowActionLayout(theme: theme, allowsPin: model.allowsRowPin).textTrailing)
                .padding(.vertical, theme.component(.libraryRowPaddingY))
        }.background(theme.tokens.rowTint(paletteID: note.colorID?.rawValue)?.color ?? .clear)
            .overlay(alignment: .bottom) {
                if showsRule { LibraryListRule(theme: theme).padding(.leading, indent) }
            }
    }
}

private struct LibraryListRule: View {
    let theme: Theme
    var body: some View {
        theme.libraryColor(.line).frame(height: theme.shape(.borderWidth))
            .padding(.horizontal, theme.component(.libraryRowLeading)).allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct InstructionHost: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

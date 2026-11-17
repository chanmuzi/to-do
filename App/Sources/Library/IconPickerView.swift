import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Models
import SpaceIcons
import Theme

struct IconPickerView: View {
    @Bindable var model: LibraryModel
    let spaceID: SpaceID
    @State private var tab: Int
    @State private var query = ""
    @State private var catalog = IconCatalog.shared
    @FocusState private var searchFocused: Bool
    private var theme: Theme { model.theme }
    private var space: Space? { model.spaceList.first { $0.id == spaceID } }
    private var icon: SpaceIcon { space?.icon ?? .none }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 0), count: theme.count(.iconPickerColumns))
    }
    init(model: LibraryModel, spaceID: SpaceID, initialTab: Int? = nil) {
        self.model = model; self.spaceID = spaceID
        let icon = model.spaceList.first { $0.id == spaceID }?.icon
        let selected: Int
        switch icon { case .emoji: selected = 1; case .image: selected = 2; default: selected = 0 }
        _tab = State(initialValue: initialTab ?? selected)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: theme.space(.sp2)) {
            HStack(spacing: theme.space(.sp2)) {
                iconView(icon)
                Text(space?.name ?? "").lineLimit(1)
                Spacer(minLength: 0)
                Button("아이콘 없음") { model.setIcon(.none, for: spaceID) }.buttonStyle(.plain)
            }
            HStack(spacing: 0) {
                ForEach(Array(["기호", "이모지", "이미지"].enumerated()), id: \.offset) { index, title in
                    Button { tab = index; query = "" } label: {
                        Text(title).font(theme.font(.body)).fontWeight(tab == index ? .semibold : .regular)
                            .foregroundStyle(theme.libraryColor(tab == index ? .text : .text2))
                            .frame(maxWidth: .infinity).frame(height: theme.component(.controlHeight))
                            .background(tab == index ? theme.libraryColor(.surface3) : .clear,
                                        in: RoundedRectangle(cornerRadius: theme.shape(.chipRadius)))
                    }.buttonStyle(LibraryButtonStyle(theme: theme))
                }
            }.overlay(RoundedRectangle(cornerRadius: theme.shape(.controlRadius)).stroke(theme.libraryColor(.line), lineWidth: theme.shape(.borderWidth)))
            if tab == 2 { images } else { searchable }
            if let error = model.error ?? catalog.warning { Text(error).font(theme.font(.rowSub)).foregroundStyle(theme.libraryColor(.text2)) }
            Divider()
            HStack { Spacer(); Button("완료") { model.iconSpace = nil }.buttonStyle(LibraryButtonStyle(theme: theme)) }
        }.font(theme.font(.body)).foregroundStyle(theme.libraryColor(.text))
            .padding(theme.component(.iconPickerPadding)).frame(width: theme.component(.iconPickerWidth))
            .background(theme.libraryColor(.surface))
            .onAppear { searchFocused = true }
            .onExitCommand { model.iconSpace = nil }
    }
    private var searchable: some View {
        VStack(alignment: .leading, spacing: theme.space(.sp2)) {
            TextField(tab == 0 ? "기호 검색" : "이모지 검색", text: $query).textFieldStyle(.plain)
                .focused($searchFocused).padding(.horizontal, theme.space(.sp2))
                .frame(height: theme.component(.browseFindHeight)).background(theme.libraryColor(.surface3), in: RoundedRectangle(cornerRadius: theme.shape(.controlRadius)))
            Text("고정").font(theme.font(.rowSub)).foregroundStyle(theme.libraryColor(.text3))
            grid(model.settings.pinnedIcons.filter(matchesTab))
            HStack {
                Text("최근에 쓴 것").foregroundStyle(theme.libraryColor(.text3))
                Spacer()
                Button("지우기") { model.changeSettings { $0.recentIcons.removeAll(where: matchesTab) } }.buttonStyle(.plain)
            }.font(theme.font(.rowSub))
            grid(model.settings.recentIcons.filter(matchesTab))
            Text("전체").font(theme.font(.rowSub)).foregroundStyle(theme.libraryColor(.text3))
            ScrollView {
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(searchResults) { entry in
                        cell(entry.icon).accessibilityLabel(entry.name)
                    }
                }
            }.frame(height: theme.component(.iconPickerGridHeight))
            if tab == 0 { colors }
        }
    }
    private var searchResults: [IconCatalog.Entry] {
        let entries = (tab == 0 ? catalog.symbols : catalog.emoji).filter { query.isEmpty || $0.name.localizedStandardContains(query) }
        if tab == 1, !query.isEmpty, IconCatalog.supportsEmoji(query), !entries.contains(where: { $0.icon == .emoji(query) }) {
            return [IconCatalog.Entry(icon: .emoji(query), name: query)] + entries
        }
        return entries
    }
    private func matchesTab(_ icon: SpaceIcon) -> Bool {
        switch icon { case .symbol, .customSymbol: tab == 0; case .emoji: tab == 1; default: false }
    }
    private func grid(_ icons: [SpaceIcon]) -> some View {
        LazyVGrid(columns: columns, spacing: 0) { ForEach(icons, id: \.self) { cell($0) } }
    }
    private func iconView(_ value: SpaceIcon) -> some View {
        SpaceIconView(icon: value, directory: model.spaces.imageDirectory, theme: theme, size: theme.component(.iconPickerIcon))
            .frame(width: theme.component(.iconPickerIcon), height: theme.component(.iconPickerIcon))
    }
    private func isSelected(_ value: SpaceIcon) -> Bool {
        if case .symbol(let candidate, _) = value {
            switch icon { case .symbol(let name, _), .customSymbol(let name, _): return name == candidate; default: break }
        }
        return value == icon
    }
    private func cell(_ value: SpaceIcon) -> some View {
        Button {
            var chosen = value
            if case .symbol(let name, _) = value {
                switch icon {
                case .symbol(_, let color): chosen = .symbol(name: name, colorID: color)
                case .customSymbol(_, let hex): chosen = .customSymbol(name: name, hex: hex)
                default: break
                }
            }
            model.setIcon(chosen, for: spaceID)
        } label: {
            iconView(value).frame(maxWidth: .infinity).frame(height: theme.component(.iconPickerCellHeight))
                .overlay(RoundedRectangle(cornerRadius: theme.shape(.chipRadius))
                    .stroke(isSelected(value) ? theme.libraryColor(.text) : .clear, lineWidth: theme.component(.iconPickerRing)))
        }.buttonStyle(LibraryButtonStyle(theme: theme))
            .contextMenu {
                Button(model.settings.pinnedIcons.contains(value) ? "고정 해제" : "고정") {
                    model.changeSettings { settings in
                        if settings.pinnedIcons.contains(value) { settings.pinnedIcons.removeAll { $0 == value } }
                        else { settings.pinnedIcons.append(value) }
                    }
                }
                Button("최근 목록에서 빼기") { model.changeSettings { $0.recentIcons.removeAll { $0 == value } } }
            }
    }
    private var colors: some View {
        VStack(alignment: .leading, spacing: theme.space(.sp1)) {
            Text("색").font(theme.font(.rowSub)).foregroundStyle(theme.libraryColor(.text3))
            HStack(spacing: theme.space(.sp1)) {
                Button { setColor(nil) } label: {
                    RoundedRectangle(cornerRadius: theme.shape(.checkRadius)).fill(theme.libraryColor(.surface))
                        .overlay(RoundedRectangle(cornerRadius: theme.shape(.checkRadius)).stroke(theme.libraryColor(.outline), lineWidth: theme.shape(.borderWidth)))
                }.accessibilityLabel("색 없음")
                ForEach(theme.palette, id: \.id) { tint in
                    Button { setColor(PaletteID(rawValue: tint.id)) } label: {
                        RoundedRectangle(cornerRadius: theme.shape(.checkRadius)).fill(tint.color.color)
                            .overlay(RoundedRectangle(cornerRadius: theme.shape(.checkRadius))
                                .stroke(selectedColorID == tint.id ? theme.libraryColor(.text) : .clear,
                                        lineWidth: theme.component(.iconPickerRing)))
                    }.accessibilityLabel(tint.name)
                }
                SymbolColorButton(theme: theme) { hex in
                    guard let name = symbolName else { return }
                    model.setIcon(.customSymbol(name: name, hex: hex), for: spaceID)
                }.frame(width: theme.component(.swatchSize), height: theme.component(.swatchSize))

            }.buttonStyle(.plain).frame(height: theme.component(.swatchSize))
        }
    }
    private var selectedColorID: String? {
        if case .symbol(_, let color) = icon { return color?.rawValue }
        return nil
    }
    private var symbolName: String? {
        switch icon { case .symbol(let name, _), .customSymbol(let name, _): name; default: nil }
    }
    private func setColor(_ color: PaletteID?) {
        if let name = symbolName { model.setIcon(.symbol(name: name, colorID: color), for: spaceID) }
    }
    private var images: some View {
        VStack(alignment: .leading, spacing: theme.space(.sp2)) {
            Text("기본 이미지").foregroundStyle(theme.libraryColor(.text3))
            grid(SpaceIconAssets.builtins.map(SpaceIcon.image))
            Text("내 이미지").foregroundStyle(theme.libraryColor(.text3))
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(model.settings.images, id: \.self) { cell(.image($0)) }
                Button(action: chooseFile) { Image(systemName: "plus").frame(height: theme.component(.iconPickerCellHeight)) }.buttonStyle(.plain).accessibilityLabel("이미지 추가")
            }
            VStack(spacing: theme.space(.sp2)) {
                Image(systemName: "photo")
                Text("이미지를 여기에 끌어다 놓기").foregroundStyle(theme.libraryColor(.text3))
                Button("파일 고르기", action: chooseFile).buttonStyle(.plain)
            }.frame(maxWidth: .infinity).frame(height: theme.component(.iconPickerDropHeight))
                .overlay(RoundedRectangle(cornerRadius: theme.shape(.controlRadius)).stroke(theme.libraryColor(.line), style: StrokeStyle(lineWidth: theme.shape(.borderWidth), dash: [theme.space(.sp1)])))
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first else { return false }
                    model.importImage(url, for: spaceID); return true
                }
        }.font(theme.font(.rowSub))
    }
    private func chooseFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .svg, .gif]
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url { model.importImage(url, for: spaceID) }
        }
    }
}

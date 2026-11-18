import SwiftUI
import Models
import Theme

struct LibraryViewEditor: View {
    @Bindable var model: LibraryModel
    var body: some View {
        VStack(alignment: .leading, spacing: model.theme.space(.sp2)) {
            Text("사이드바에 보일 보기").font(model.theme.font(.row))
            ForEach(LibrarySelection.views, id: \.self) { view in
                Toggle(model.title(view), isOn: Binding(get: { model.settings.visibleViews.contains(view) }, set: { visible in
                    model.changeSettings { settings in
                        settings.visibleViews.removeAll { $0 == view }
                        if visible { settings.visibleViews.append(view) }
                        settings.visibleViews = LibrarySelection.views.filter { settings.visibleViews.contains($0) }
                    }
                })).toggleStyle(.checkbox)
            }
            Divider()
            let choices: [LibrarySelection?] = [nil] + model.settings.visibleViews.map(Optional.some)
            HStack(spacing: 0) {
                Text("열 때 보여 줄 곳")
                ValuePopup(label: "열 때 보여 줄 곳", value: model.settings.openingView.map(model.title) ?? "마지막으로 본 보기",
                           theme: model.theme) {
                    let menu = NSMenu()
                    menu.autoenablesItems = false
                    for (index, view) in choices.enumerated() {
                        let item = menu.addItem(withTitle: view.map(model.title) ?? "마지막으로 본 보기", action: nil, keyEquivalent: "")
                        item.tag = index
                        item.state = view == model.settings.openingView ? .on : .off
                    }
                    return menu
                } choose: { item in
                    if choices.indices.contains(item.tag) { model.changeSettings { $0.openingView = choices[item.tag] } }
                }
            }
        }.focusEffectDisabled().tint(model.theme.libraryColor(.accent)).font(model.theme.font(.body)).padding(model.theme.space(.sp3))
            .frame(width: model.theme.component(.iconPickerWidth))
    }
}

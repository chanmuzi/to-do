import SwiftUI
import Models

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
            Picker("열 때 보여 줄 곳", selection: Binding(get: { model.settings.openingView }, set: { value in
                model.changeSettings { $0.openingView = value }
            })) {
                Text("마지막으로 본 보기").tag(Optional<LibrarySelection>.none)
                ForEach(model.settings.visibleViews, id: \.self) { Text(model.title($0)).tag(Optional($0)) }
            }
        }.tint(model.theme.libraryColor(.accent)).font(model.theme.font(.body)).padding(model.theme.space(.sp3))
            .frame(width: model.theme.component(.iconPickerWidth))
    }
}

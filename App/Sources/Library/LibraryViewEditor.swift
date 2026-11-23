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
                    model.changeSettings { $0.setVisible(view, visible) }
                })).toggleStyle(.checkbox)
            }
            Divider()
            Toggle("마지막으로 본 곳에서 열기", isOn: Binding(get: { model.settings.opensLastSelection },
                set: { enabled in model.changeSettings { $0.opensLastSelection = enabled } }))
        }.focusEffectDisabled().tint(model.theme.libraryColor(.accent)).font(model.theme.font(.body)).padding(model.theme.space(.sp3))
            .frame(width: model.theme.component(.iconPickerWidth))
    }
}

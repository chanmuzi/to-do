import SwiftUI
import Models
import Theme

struct LibraryReminder: View {
    let note: Note
    let model: LibraryModel
    var sidebar = false
    var body: some View {
        if let value = model.reminderPresentation(for: note), let text = value.text {
            Text(text).lineLimit(1).truncationMode(.tail)
                .font(model.theme.font(sidebar ? .micro : .scheduleTime))
                .foregroundStyle(model.theme.libraryColor(value.status == .scheduled ? (sidebar ? .text3 : .text2) : .warn))
                .accessibilityLabel(value.accessibilityLabel)
        }
    }
}

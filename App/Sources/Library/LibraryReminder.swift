import AppKit
import SwiftUI
import Models
import Theme

/// 노트 상단과 같은 포맷터·상태·표시 옵션을 쓴다. 시간과 남은 시간을 함께 표시하지 않는다.
struct LibraryReminder: View {
    let note: Note
    let model: LibraryModel
    var body: some View {
        if let value = model.reminderPresentation(for: note) {
            HStack(spacing: model.theme.component(.iconGap)) {
                LibraryReminderIcon(theme: model.theme, value: value)
                    .frame(width: model.theme.component(.iconSmall), height: model.theme.component(.iconSmall))
                if value.syncFailed { Image(systemName: "exclamationmark.circle").accessibilityLabel("연동 실패") }
                if let text = value.text { Text(text).lineLimit(1).truncationMode(.tail) }
            }.font(model.theme.font(value.textStyle))
                .foregroundStyle(model.theme.libraryColor(value.color))
                .accessibilityLabel(value.accessibilityLabel)
        }
    }
}

private struct LibraryReminderIcon: NSViewRepresentable {
    let theme: Theme
    let value: ReminderPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleNone
        view.wantsLayer = true
        view.setAccessibilityElement(false)
        return view
    }
    func updateNSView(_ view: NSImageView, context: Context) {
        view.image = theme.symbolImage(value.symbolName, size: .iconSmall)
        view.contentTintColor = theme.nsColor(value.color)
        guard let layer = view.layer else { return }
        if value.isRinging && !reduceMotion {
            if layer.animation(forKey: BellRing.animationKey) == nil {
                layer.add(BellRing.animation(for: layer, motion: theme.motion.bell), forKey: BellRing.animationKey)
            }
        } else { layer.removeAnimation(forKey: BellRing.animationKey) }
    }
}

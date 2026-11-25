import AppKit
import SwiftUI
import Theme

/// 시각 안의 숫자 이동, 구분 기호, 오전/오후 순서는 로캘을 아는 AppKit 셀에 맡긴다.
struct ScheduleTimeField: NSViewRepresentable {
    let model: ReminderEditorModel
    let isEnd: Bool
    let theme: Theme
    let leave: (Bool) -> Void

    func makeNSView(context: Context) -> ClockPicker {
        let picker = ClockPicker()
        picker.datePickerStyle = .textField
        picker.datePickerElements = .hourMinute
        picker.isBezeled = false
        picker.isBordered = false
        picker.drawsBackground = false
        picker.focusRingType = .none
        picker.calendar = model.calendar
        picker.timeZone = model.calendar.timeZone
        picker.locale = ScheduleDateSelection.displayLocale
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.change(_:))
        picker.setAccessibilityLabel(isEnd ? "끝" : "시작")
        if isEnd { model.endField = picker } else { model.startField = picker }
        return picker
    }

    func updateNSView(_ picker: ClockPicker, context: Context) {
        context.coordinator.parent = self
        picker.font = theme.nsFont(.body, size: theme.tokens.textStyle(.ui).size)
        picker.textColor = theme.nsColor(.text)
        let value = isEnd ? model.end : model.start
        if picker.dateValue != value { picker.dateValue = value }
        picker.neighbor = { [weak model] backward in
            guard let model, model.hasEnd, backward == isEnd else { return nil }
            return backward ? model.startField : model.endField
        }
        picker.exit.leave = leave
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ClockPicker, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor final class Coordinator: NSObject {
        var parent: ScheduleTimeField
        init(_ parent: ScheduleTimeField) { self.parent = parent }
        @objc func change(_ picker: NSDatePicker) {
            parent.model.changeTime(picker.dateValue, isEnd: parent.isEnd)
        }
    }
}

/// AppKit이 마지막 세그먼트에서 다음 키 뷰를 찾을 때만 상세 화면의 순서로 돌아간다.
final class ClockPicker: NSDatePicker {
    var neighbor: ((Bool) -> NSView?)?
    let exit = FocusExit()
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if exit.superview == nil { addSubview(exit) }
    }
    override var nextValidKeyView: NSView? { neighbor?(false) ?? exit }
    override var previousValidKeyView: NSView? { neighbor?(true) ?? exit }

    final class FocusExit: NSView {
        var leave: ((Bool) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override var nextValidKeyView: NSView? { superview }
        override var previousValidKeyView: NSView? { superview }
        override func becomeFirstResponder() -> Bool {
            let backward = window?.keyViewSelectionDirection == .selectingPrevious
            DispatchQueue.main.async { [weak self] in self?.leave?(backward) }
            return true
        }
    }
}

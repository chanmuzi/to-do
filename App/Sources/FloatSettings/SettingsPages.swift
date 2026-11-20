import Models
import Scheduling
import SwiftUI
import Theme

extension SettingsView {
    var appearance: some View {
        card {
            setting("화면", \.appearance, [("system", "시스템"), ("light", "라이트"), ("dark", "다크")])
            row("본문 글자 크기") {
                HStack(spacing: theme.space(.sp2)) {
                    Text("가").font(theme.font(.librarySection))
                    FontSlider(value: model.values.bodySize ?? Int(theme.noteBodySize),
                               range: Int(theme.component(.settingsFontMin))...Int(theme.component(.settingsFontMax))) { size in
                        model.change { $0.bodySize = size }
                    }.frame(width: theme.component(.settingsSliderW))
                    Text("가").font(theme.font(.body, size: theme.component(.settingsFontMax)))
                }.foregroundStyle(theme.color(.text3))
            }
            segment("줄 간격", value: Int(theme.lineHeight(.body)),
                    choices: [(Int(theme.component(.settingsLineMin)), "좁게"), (Int(theme.defaultBodyLineHeight), "보통"),
                              (Int(theme.component(.settingsLineMax)), "넓게")]) { value in model.change { $0.bodyLineHeight = value } }
            setting("스페이스 표시", \.spaceDisplay, [("icon", "아이콘"), ("iconAndName", "아이콘과 이름"), ("name", "이름")])
        }
    }

    var editor: some View {
        card {
            setting("코드 글자색", \.inlineCode, [("accent", "강조"), ("plain", "흑백")])
            setting("체크박스", \.checkbox, [("box", "상자"), ("bracket", "[ ]")])
            segment("입력 중 글자", value: model.values.markedTextStyle,
                    choices: [(.none, "표시 없음"), (.underline, "옅은 밑줄")]) { value in model.change { $0.markedTextStyle = value } }
            setting("서식 표시줄", \.formatBar, [("always", "항상"), ("editing", "편집할 때"), ("hidden", "숨김")])
            toggle("날짜 알아보기", \.recognizesDates)
        }
    }

    var schedule: some View {
        card {
            setting("날짜 표시", \.scheduleDateFormat, [("relative", "내일 오후 3:00"), ("absolute", "11월 19일 오후 3:00")])
            setting("시간 형식", \.clockFormat, [("twelveHour", "3:00 PM"), ("koreanMeridiem", "오후 3:00"), ("twentyFourHour", "15:00")])
            ForEach([ScheduleItem.Kind.event, .reminder], id: \.self) { kind in
                if let menu = model.menus[kind] {
                    let title = kind == .event ? "기본 캘린더" : "미리 알림 목록"
                    row(title) {
                        switch menu.access {
                        case .available:
                            DestinationPicker(title: title, choices: menu.choices, current: menu.system, selectedID: model.values[idFor: kind],
                                              inSettings: true, theme: theme) { model.choose($0, for: kind) }
                        case .needsRequest:
                            actionButton("연결") { Task { await model.connect(kind) } }.disabled(model.connecting)
                        case .blocked:
                            actionButton("시스템 설정 열기") { model.openPrivacy(kind) }
                        }
                    }
                }
            }
        }
    }
}

private struct FontSlider: NSViewRepresentable {
    let value: Int
    let range: ClosedRange<Int>
    let select: (Int) -> Void
    final class Coordinator: NSObject {
        var select: (Int) -> Void
        init(_ select: @escaping (Int) -> Void) { self.select = select }
        @objc func change(_ slider: NSSlider) { select(slider.integerValue) }
    }
    func makeCoordinator() -> Coordinator { Coordinator(select) }
    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: Double(value), minValue: Double(range.lowerBound), maxValue: Double(range.upperBound),
                              target: context.coordinator, action: #selector(Coordinator.change(_:)))
        slider.numberOfTickMarks = range.count
        slider.allowsTickMarkValuesOnly = true
        slider.isContinuous = true
        slider.controlSize = .small
        slider.trackFillColor = .labelColor
        slider.setAccessibilityLabel("본문 글자 크기")
        return slider
    }
    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.select = select
        slider.integerValue = value
    }
}

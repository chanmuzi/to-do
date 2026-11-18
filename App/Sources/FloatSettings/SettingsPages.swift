import Models
import Scheduling
import SwiftUI
import Theme

extension SettingsView {
    var appearance: some View {
        card("표시") {
            setting("화면", "Float 창에 적용할 모양", \.appearance, [("system", "시스템"), ("light", "라이트"), ("dark", "다크")])
            row("본문 글자 크기", "노트 본문의 기본 크기") {
                let value = Int(theme.noteBodySize)
                let range = Int(theme.component(.settingsFontMin))...Int(theme.component(.settingsFontMax))
                HStack(spacing: theme.space(.sp1)) {
                    textButton("−") { model.change { $0.bodySize = max(range.lowerBound, value - 1) } }
                        .disabled(value <= range.lowerBound).accessibilityLabel("본문 글자 줄이기")
                    Text(String(value)).font(valueFont).monospacedDigit()
                    textButton("+") { model.change { $0.bodySize = min(range.upperBound, value + 1) } }
                        .disabled(value >= range.upperBound).accessibilityLabel("본문 글자 늘리기")
                }
            }
            popup("줄 간격", "본문의 줄과 줄 사이 간격", value: Int(theme.lineHeight(.body)),
                  choices: [(Int(theme.component(.settingsLineMin)), "좁게"), (Int(theme.defaultBodyLineHeight), "보통"),
                            (Int(theme.component(.settingsLineMax)), "넓게")]) { value in
                model.change { $0.bodyLineHeight = value }
            }
            setting("스페이스 표시", "노트 상단에 보일 스페이스 정보", \.spaceDisplay,
                    [("icon", "아이콘"), ("iconAndName", "아이콘과 이름"), ("name", "이름")])
        }
    }

    @ViewBuilder var editor: some View {
        card("표시") {
            setting("코드 글자색", "\u{60}코드\u{60}로 감싼 글자를 강조색으로", \.inlineCode, [("accent", "강조"), ("plain", "흑백")])
            setting("체크박스", "할 일 앞 표시를 상자나 대괄호로", \.checkbox, [("box", "상자"), ("bracket", "[ ] 대괄호")])
            popup("입력 중 글자", "한글을 조합하는 동안의 표시", value: model.values.markedTextStyle,
                  choices: [(.none, "표시 없음"), (.underline, "옅은 밑줄")]) { value in model.change { $0.markedTextStyle = value } }
            setting("서식 표시줄", "노트 아래 굵게, 링크 같은 서식 버튼", \.formatBar,
                    [("always", "항상"), ("editing", "편집할 때"), ("hidden", "숨김")])
        }
        card("도움 기능") {
            toggle("날짜 알아보기", "본문과 제목의 날짜에 밑줄을 긋고 Tab으로 일정에 넣어요", \.recognizesDates)
        }
    }

    @ViewBuilder var schedule: some View {
        card("표시") {
            setting("날짜 표시", "예정에 보일 날짜", \.scheduleDateFormat, [("relative", "내일 오후 3:00"), ("absolute", "11월 19일 오후 3:00")])
            setting("시간 형식", "시각과 오전, 오후를 적는 방법", \.clockFormat,
                    [("twelveHour", "3:00 PM"), ("koreanMeridiem", "오후 3:00"), ("twentyFourHour", "15:00")])
        }
        card("저장 위치") {
            ForEach([ScheduleItem.Kind.event, .reminder], id: \.self) { kind in
                if let menu = model.menus[kind] {
                    let title = kind == .event ? "기본 캘린더" : "미리 알림 목록"
                    row(title) {
                        switch menu.access {
                        case .available:
                            DestinationPicker(title: title, choices: menu.choices, current: menu.system, selectedID: model.values[idFor: kind],
                                              inSettings: true, theme: theme) { model.choose($0, for: kind) }
                        case .needsRequest:
                            textButton("연결") { Task { await model.connect(kind) } }.disabled(model.connecting)
                        case .blocked:
                            textButton("시스템 설정 열기") { model.openPrivacy(kind) }
                        }
                    }
                }
            }
        }
    }
}

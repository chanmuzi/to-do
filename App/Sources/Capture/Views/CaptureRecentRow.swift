import SwiftUI
import Theme

package struct CaptureRecentRequest {
    package let id: UUID
    package let question: String
    package let detail: String
    let date: Date
    package let face: AgentFaceState

    package init(id: UUID, question: String, detail: String, date: Date, face: AgentFaceState) {
        self.id = id
        self.question = question
        self.detail = detail
        self.date = date
        self.face = face
    }
}

struct CaptureRecentRow: View {
    let theme: Theme
    let recent: CaptureRecentRequest
    let open: () -> Void

    var previewFont: Font { theme.font(.capture, size: theme.tokens.textStyle(.ui).size) }
    var elapsedFont: Font { theme.font(.capture, size: theme.tokens.textStyle(.micro).size) }

    var body: some View {
        Button(action: open) {
            HStack(spacing: theme.space(.sp2)) {
                AgentFace(theme: theme, state: recent.face)
                Text(recent.question).foregroundStyle(theme.color(.text))
                Text(recent.detail).foregroundStyle(theme.color(.text2))
                Spacer(minLength: 0)
                TimelineView(.everyMinute) { _ in
                    Text(Self.elapsed(since: recent.date))
                        .font(elapsedFont).foregroundStyle(theme.color(.text3))
                }.fixedSize()
            }
            .font(previewFont).lineLimit(1)
            .padding(.horizontal, theme.component(.capturePadding))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("직전 대화 열기, " + recent.question + ", " + recent.detail)
        .overlay(alignment: .top) { Rectangle().fill(theme.color(.line)).frame(height: theme.shape(.borderWidth)) }
    }
}

extension CaptureRecentRow {
    /// 1분이 안 됐으면 "방금". 그 뒤로는 지난 시간을 숫자로 적는다(앞으로의 시각으로 읽히지 않게 한다).
    static func elapsed(since date: Date, now: Date = Date()) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return "방금" }
        return date.formatted(.relative(presentation: .numeric).locale(Locale(identifier: "ko_KR")))
    }
}

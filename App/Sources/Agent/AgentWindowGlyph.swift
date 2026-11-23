import AppKit
import Theme

/// 확정 시안에 쓰인 16 단위 경로. 색은 버튼 상태와 테마에서 정한다.
enum AgentWindowGlyph {
    case clock, plus, more, close, send, note

    func image(theme: Theme) -> NSImage {
        let path: String
        switch self {
        case .clock: path = #"<circle cx="8" cy="8" r="5.5"/><path d="M8 5v3.2l2 1.3"/>"#
        case .plus: path = #"<path d="M8 3v10M3 8h10"/>"#
        case .more: path = #"<g stroke="none" fill="black"><circle cx="3.5" cy="8" r="1.1"/><circle cx="8" cy="8" r="1.1"/><circle cx="12.5" cy="8" r="1.1"/></g>"#
        case .close: path = #"<path d="M4 4l8 8M12 4l-8 8"/>"#
        case .send: path = #"<path d="M8 13V3.5M4 7.5l4-4 4 4"/>"#
        case .note: path = #"<rect x="3" y="2.5" width="10" height="11" rx="1.5"/><path d="M5.5 6h5M5.5 8.5h5M5.5 11h3"/>"#
        }
        let width = switch self {
        case .plus: theme.component(.agentPlusSize)
        case .note: theme.tokens.textStyle(.micro).size
        default: theme.component(.iconMedium)
        }
        let stroke = theme.component(self == .send ? .agentArrowStroke : .iconStroke)
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(width)" viewBox="0 0 16 16" fill="none" stroke="black" stroke-width="\(stroke)" stroke-linecap="round" stroke-linejoin="round">\(path)</svg>
        """
        return NSImage(data: Data(svg.utf8))!
    }
}

import AppKit
import Theme

/// 확정 시안의 16단위 벡터 경로를 테마의 그림 크기와 선 두께로 그린다.
enum NoteButtonGlyph {
    static func image(_ name: String, theme: Theme) -> NSImage? {
        let path: String
        switch name {
        case "clock": path = #"<circle cx="8" cy="8" r="6"></circle><path d="M8 4.8V8l2.2 1.5"></path>"#
        case "pin": path = #"<path d="M6 2.5h4l-.5 3.5 2.5 2.5H4l2.5-2.5z"></path><path d="M8 8.5V14"></path>"#
        case "plus": path = #"<path d="M8 3v10M3 8h10"></path>"#
        case "ellipsis": path = #"<g fill="black" stroke="none"><circle cx="3.5" cy="8" r="1.2"></circle><circle cx="8" cy="8" r="1.2"></circle><circle cx="12.5" cy="8" r="1.2"></circle></g>"#
        case "xmark": path = #"<path d="M4 4l8 8M12 4l-8 8"></path>"#
        case "trash": path = #"<path d="M3 4.5h10M6.5 4.5V3h3v1.5M4.5 4.5l.6 8.5h5.8l.6-8.5"></path>"#
        case "pin.fill": path = #"<path fill="black" d="M6 2.5h4l-.5 3.5 2.5 2.5H4l2.5-2.5z"></path><path d="M8 8.5V14"></path>"#
        case "a": path = #"<path d="M3.5 12L8 2l4.5 10M5.1 8.5h5.8"></path>"#
        case "chevron.left.forwardslash.chevron.right": path = #"<path d="M5.5 4.5L2 8l3.5 3.5M10.5 4.5L14 8l-3.5 3.5"></path>"#
        case "link": path = #"<path d="M6.5 9.5l3-3M7 4.5l1.2-1.2a2.6 2.6 0 0 1 3.6 3.6L10.5 8M9 11.5l-1.2 1.2a2.6 2.6 0 0 1-3.6-3.6L5.5 8"></path>"#
        case "checklist": path = #"<rect x="2.5" y="2.5" width="5" height="5" rx="1"></rect><path d="M10 5h4M10 11.5h4"></path><rect x="2.5" y="9" width="5" height="5" rx="1"></rect>"#
        case "list.bullet": path = #"<circle cx="3" cy="4.5" r=".8"></circle><circle cx="3" cy="11.5" r=".8"></circle><path d="M6 4.5h8M6 11.5h8"></path>"#
        default: return nil
        }
        let size = theme.component(.iconMedium)
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(size)" height="\(size)" viewBox="0 0 16 16" fill="none" stroke="black" stroke-width="\(theme.component(.iconStroke))" stroke-linecap="round" stroke-linejoin="round">\(path)</svg>
        """
        let image = NSImage(data: Data(svg.utf8))
        image?.isTemplate = true
        return image
    }
}

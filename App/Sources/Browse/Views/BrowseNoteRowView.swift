import AppKit
import Models
import SpaceIcons
import Theme

final class BrowseNoteRowView: BrowseEntryView {
    static let untitled = "제목 없음"

    let noteRow: BrowseNoteRow
    private let space: Space?
    private let directory: URL
    private let icon = SpaceIconNSView(frame: .zero)
    private let titleLabel = NSTextField(labelWithString: "")
    private let previewLabel = NSTextField(labelWithString: "")
    let pin = NSButton()
    var onPin: (() -> Void)?
    var onOpen: (() -> Void)?

    init(style: BrowseStyle, row: BrowseNoteRow, space: Space?, directory: URL) {
        noteRow = row
        self.space = space
        self.directory = directory
        super.init(style: style)
        for label in [titleLabel, previewLabel] {
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.cell?.usesSingleLineMode = true
        }
        pin.title = ""
        pin.imagePosition = .imageOnly
        pin.isBordered = false
        pin.focusRingType = .none
        pin.wantsLayer = true
        pin.target = self
        pin.action = #selector(togglePin)
        pin.setAccessibilityLabel("항상 위에 고정")
        pin.setAccessibilityValue(row.isFloating ? "켜짐" : "꺼짐")
        [icon, titleLabel, previewLabel, pin].forEach(addSubview)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityCustomActions([NSAccessibilityCustomAction(name: "노트 열기") { [weak self] in
            guard let open = self?.onOpen else { return false }
            open()
            return true
        }])
        setAccessibilityLabel([row.title.isEmpty ? Self.untitled : row.title, space?.name, row.preview]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
        refreshTheme()
    }

    @objc private func togglePin() { onPin?() }

    var titleText: String { titleLabel.stringValue }
    var titleFrame: NSRect { titleLabel.frame }
    var previewText: NSAttributedString { previewLabel.attributedStringValue }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        pin.isHidden = !noteRow.isFloating && !highlighted
        if !highlighted { setPinHover(false) }
    }

    func setPinHover(_ hovered: Bool) {
        pin.layer?.backgroundColor = hovered ? style.cgColor(.hover, in: self) : CGColor.clear
    }

    override func refreshTheme() {
        let fallback = SpaceIcon.symbol(name: "doc.text", colorID: nil)
        let glyph = space?.icon ?? fallback
        icon.apply(glyph == .none ? fallback : glyph, directory: directory, theme: style.theme,
                   size: style.leadWidth, symbolSize: .iconSmall)
        titleLabel.attributedStringValue = styled(
            noteRow.title.isEmpty ? Self.untitled : noteRow.title,
            font: style.plainFont, color: noteRow.title.isEmpty ? .text3 : .text,
            match: noteRow.titleHighlight, matchFont: style.titleFont, matchColor: .text
        )
        previewLabel.attributedStringValue = styled(
            noteRow.preview, font: style.previewFont, color: .text3,
            match: noteRow.previewHighlight, matchFont: style.previewMatchFont, matchColor: .text2
        )
        pin.image = style.symbol(noteRow.isFloating ? "pin.fill" : "pin", size: .menuIcon)
        pin.contentTintColor = style.color(.text2)
        pin.layer?.cornerRadius = style.theme.shape(.controlRadius)
        pin.isHidden = !noteRow.isFloating && !isHighlighted
        super.refreshTheme()
    }

    private func styled(_ value: String, font: NSFont, color: ColorToken, match: Range<Int>?,
                        matchFont: NSFont, matchColor: ColorToken) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let text = NSMutableAttributedString(string: value, attributes: [
            .font: font, .foregroundColor: style.color(color), .paragraphStyle: paragraph
        ])
        if let match {
            let start = value.index(value.startIndex, offsetBy: match.lowerBound)
            let end = value.index(value.startIndex, offsetBy: match.upperBound)
            text.addAttributes([.font: matchFont, .foregroundColor: style.color(matchColor)],
                               range: NSRange(start..<end, in: value))
        }
        return text
    }

    override func layout() {
        super.layout()
        let theme = style.theme
        let gap = theme.component(.browseGap)
        icon.frame = centered(width: style.leadWidth, height: style.leadWidth, x: style.rowPadding)
        let pinWidth = theme.component(.browsePinWidth)
        pin.frame = centered(width: pinWidth, height: pinWidth, x: bounds.width - theme.space(.sp1) - pinWidth)
        let start = icon.frame.maxX + gap
        let available = max(0, pin.frame.minX - gap - start)
        let titleWidth = min(style.textWidth(of: titleLabel), available)
        titleLabel.frame = style.labelFrame(titleLabel, textX: start, textWidth: titleWidth, centeredIn: bounds.height)
        let rest = available - titleWidth - gap
        previewLabel.isHidden = noteRow.preview.isEmpty || rest <= 0
        previewLabel.frame = style.labelFrame(previewLabel, textX: start + titleWidth + gap,
                                              textWidth: rest, centeredIn: bounds.height)
        previewLabel.frame.origin.y = titleLabel.frame.minY + titleLabel.firstBaselineOffsetFromTop
            - previewLabel.firstBaselineOffsetFromTop
    }
}

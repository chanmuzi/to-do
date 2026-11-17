import AppKit
import Theme

/// 노트 한 줄(spec 8): 스페이스 아이콘 13pt / 제목 / 본문 첫머리 / 리마인더 / 떠 있으면 핀. 높이 `row-h`, 한 줄.
final class BrowseNoteRowView: BrowseEntryView {
    static let untitled = "제목 없음"

    /// 줄에 보일 것. 스페이스 아이콘과 리마인더 글자는 만드는 쪽이 풀어서 넘긴다.
    struct Model: Hashable {
        var row: BrowseNoteRow
        var spaceSymbol: String?
        var spaceEmoji: String?
        var spaceName: String?
        var reminder: BrowseReminder?
    }

    private let model: Model
    private let spaceIconView = NSImageView()
    private let spaceEmojiLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let previewLabel = NSTextField(labelWithString: "")
    private let reminderIconView = NSImageView()
    private let reminderLabel = NSTextField(labelWithString: "")
    private let pinView = NSImageView()

    init(style: BrowseStyle, model: Model) {
        self.model = model
        super.init(style: style)
        for label in [titleLabel, previewLabel] {
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.cell?.usesSingleLineMode = true
        }
        for imageView in [spaceIconView, reminderIconView, pinView] {
            imageView.imageScaling = .scaleNone
        }
        [spaceIconView, spaceEmojiLabel, titleLabel, previewLabel, reminderIconView, reminderLabel, pinView]
            .forEach { view in
                view.setAccessibilityElement(false)
                addSubview(view)
            }
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(accessibilityText)
        refreshTheme()
    }

    var noteRow: BrowseNoteRow { model.row }
    var titleText: String { titleLabel.stringValue }
    /// 제목 글자의 자리(줄 좌표).
    var titleFrame: NSRect { titleLabel.frame }
    var previewText: NSAttributedString { previewLabel.attributedStringValue }
    var reminderText: String? { model.reminder?.text }
    var showsPin: Bool { !pinView.isHidden }

    private var isUntitled: Bool { model.row.title.isEmpty }

    /// 제목, 스페이스, 본문 첫머리, 리마인더, 떠 있는지를 차례로 읽는다.
    private var accessibilityText: String {
        var parts = [isUntitled ? Self.untitled : model.row.title]
        if let name = model.spaceName, !name.isEmpty { parts.append(name) }
        if !model.row.preview.isEmpty { parts.append(model.row.preview) }
        if let reminder = model.reminder { parts.append("리마인더 \(reminder.text)") }
        if model.row.isFloating { parts.append("떠 있음") }
        return parts.joined(separator: ", ")
    }

    override var tint: NSColor? {
        style.theme.tokens.rowTint(paletteID: model.row.colorID?.rawValue)?.nsColor
    }

    override func refreshTheme() {
        spaceIconView.image = model.spaceSymbol.flatMap { style.symbol($0, size: .iconMedium) }
        spaceIconView.contentTintColor = style.color(.text2)
        spaceIconView.isHidden = spaceIconView.image == nil
        spaceEmojiLabel.stringValue = model.spaceEmoji ?? ""
        spaceEmojiLabel.font = style.previewFont
        spaceEmojiLabel.isHidden = model.spaceEmoji == nil || !spaceIconView.isHidden

        titleLabel.stringValue = isUntitled ? Self.untitled : model.row.title
        titleLabel.font = isUntitled ? style.plainFont : style.titleFont
        titleLabel.textColor = style.color(isUntitled ? .text3 : .text)
        previewLabel.attributedStringValue = previewString()

        reminderIconView.image = model.reminder.flatMap { style.symbol($0.symbolName, size: .iconSmall) }
        reminderIconView.contentTintColor = model.reminder.map { style.color($0.color) }
        reminderIconView.isHidden = model.reminder == nil
        reminderLabel.stringValue = model.reminder?.text ?? ""
        reminderLabel.font = style.reminderFont(strong: model.reminder?.isStrong ?? false)
        reminderLabel.textColor = model.reminder.map { style.color($0.color) }
        reminderLabel.isHidden = model.reminder == nil

        pinView.image = style.symbol("pin.fill", size: .iconMedium)
        pinView.contentTintColor = style.color(.text3)
        pinView.isHidden = !model.row.isFloating
        super.refreshTheme()
    }

    /// 본문 첫머리는 `text-2`, 맞은 낱말은 `text` 색 굵기 600.
    private func previewString() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let text = NSMutableAttributedString(
            string: model.row.preview,
            attributes: [.font: style.previewFont, .foregroundColor: style.color(.text2), .paragraphStyle: paragraph]
        )
        guard let highlight = model.row.previewHighlight else { return text }
        let preview = model.row.preview
        let start = preview.index(preview.startIndex, offsetBy: highlight.lowerBound, limitedBy: preview.endIndex)
        let end = preview.index(preview.startIndex, offsetBy: highlight.upperBound, limitedBy: preview.endIndex)
        guard let start, let end else { return text }
        text.addAttributes(
            [.font: style.previewMatchFont, .foregroundColor: style.color(.text)],
            range: NSRange(start..<end, in: preview)
        )
        return text
    }

    override func layout() {
        super.layout()
        let theme = style.theme
        // 셀 상자의 가운데는 글꼴마다 다르다. 제목의 기준선을 한 줄의 공통 기준선으로 쓴다.
        let titleHeight = style.fittingSize(of: titleLabel).height
        let baseline = ((bounds.height - titleHeight) / 2).rounded() + titleLabel.firstBaselineOffsetFromTop
        func textFrame(_ label: NSTextField, x: CGFloat, width: CGFloat) -> NSRect {
            var frame = style.labelFrame(label, textX: x, textWidth: width, centeredIn: bounds.height)
            frame.origin.y = baseline - label.firstBaselineOffsetFromTop
            return frame
        }
        let gap = theme.component(.browseGap)
        let lead = style.leadWidth
        let leading = style.rowPadding
        let trailing = bounds.width - style.rowPadding

        // 맨 앞: 스페이스 아이콘 칸. 아이콘이 없어도 자리는 둔다.
        let icon = theme.component(.iconMedium)
        spaceIconView.frame = theme.symbolFrame(
            centered(width: icon, height: icon, x: leading + ((lead - icon) / 2).rounded())
        )
        let emojiWidth = style.textWidth(of: spaceEmojiLabel)
        spaceEmojiLabel.frame = style.labelFrame(
            spaceEmojiLabel, textX: leading + ((lead - emojiWidth) / 2).rounded(),
            textWidth: emojiWidth, centeredIn: bounds.height
        )

        // 맨 뒤: 핀 칸. 떠 있지 않아도 자리는 둔다.
        pinView.frame = theme.symbolFrame(
            centered(width: icon, height: icon, x: trailing - lead + ((lead - icon) / 2).rounded())
        )
        var contentEnd = trailing - lead - gap

        if model.reminder != nil {
            let labelWidth = style.textWidth(of: reminderLabel)
            let reminderIcon = theme.component(.iconSmall)
            reminderLabel.frame = textFrame(reminderLabel, x: contentEnd - labelWidth, width: labelWidth)
            let reminderSlot = centered(
                width: reminderIcon, height: reminderIcon,
                x: contentEnd - labelWidth - theme.component(.iconGap) - reminderIcon
            )
            reminderIconView.frame = theme.symbolFrame(reminderSlot)
            contentEnd = reminderSlot.minX - gap
        }

        // 제목은 제 너비만큼, 남는 자리는 본문 첫머리(시안의 칸 나눔). 자리가 모자라면 본문 첫머리가 먼저 줄어든다.
        let contentStart = leading + lead + gap
        let titleWidth = min(style.textWidth(of: titleLabel), max(0, contentEnd - contentStart))
        titleLabel.frame = textFrame(titleLabel, x: contentStart, width: titleWidth)

        let previewX = contentStart + titleWidth + gap
        let previewWidth = contentEnd - previewX
        previewLabel.frame = textFrame(previewLabel, x: previewX, width: previewWidth)
        previewLabel.isHidden = model.row.preview.isEmpty || previewWidth <= 0
    }
}

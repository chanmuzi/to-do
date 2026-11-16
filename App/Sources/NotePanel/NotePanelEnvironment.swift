import Foundation
import Routing
import Store
import Theme

/// 노트 창 하나가 일하는 데 필요한 것 묶음. `NotePanelCoordinator`가 만들어 창마다 넘긴다.
struct NotePanelEnvironment {
    let style: PanelStyle
    let notes: any NoteStoring
    let spaces: SpaceStore
    let router: any Routing
    let recorder: WindowStateRecorder
    let makeBodyEditor: NoteBodyEditorFactory
    let options: () -> NotePanelDisplayOptions
    /// 지금 시각(마지막으로 연 때를 적을 때 쓴다).
    let now: () -> Date
    let log: (String) -> Void

    var theme: Theme { style.theme }

    var sizePolicy: NoteSizePolicy {
        let padding = theme.docPadding
        return NoteSizePolicy(
            defaultWidth: theme.component(.noteWidth),
            minWidth: theme.component(.noteWidthMin),
            maxWidth: theme.component(.noteWidthMax),
            chromeHeight: theme.shape(.chromeHeight) + theme.shape(.borderWidth),
            minBodyHeight: theme.lineHeight(.body) * CGFloat(theme.count(.noteBodyLinesMin))
                + padding.top + padding.bottom,
            maxScreenFraction: theme.ratio(.noteMaxScreenHeight)
        )
    }

    var placement: WindowPlacement {
        WindowPlacement(
            gap: theme.space(.sp3), cascade: theme.shape(.chromeHeight), margin: theme.space(.sp5)
        )
    }
}

import SwiftUI

extension View {
    @ViewBuilder func progressFrame(_ name: String, draft: AgentDraft) -> some View {
        #if DEBUG
        if draft.measuresProgress {
            onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                draft.progressFrames[name] = $0
            }
        } else { self }
        #else
        self
        #endif
    }

    @ViewBuilder func progressBaseline(_ name: String, draft: AgentDraft) -> some View {
        #if DEBUG
        if draft.measuresProgress {
            overlay(alignment: Alignment(horizontal: .leading, vertical: .firstTextBaseline)) {
                Color.clear.frame(width: 0, height: 0).progressFrame("baseline-" + name, draft: draft)
            }
        } else { self }
        #else
        self
        #endif
    }
}
